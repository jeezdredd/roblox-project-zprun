# Into the Dead 2 — разбор билда 24439

Реверс-инжиниринг референсной игры (PikPok, `com.pikpok.dr2.play`, build 24439, август 2026).
Материал для анализа подходов — не для копирования кода или ассетов.

## Что удалось достать и как

Игра собрана на Unity с **IL2CPP**, поэтому C#-код скомпилирован в нативный ARM64.
Java-слоя с геймплеем нет вообще: из 28 010 классов в dex только **8** принадлежат PikPok,
и все служебные. Всё остальное — Unity-загрузчик и SDK-обвязка.

Восстановление шло через `global-metadata.dat` (версия формата 31, без шифрования):

| Артефакт | Объём |
| --- | --- |
| Типы `Assembly-CSharp.dll` | 4 120 |
| Методы (всего в билде) | 75 345 |
| Поля (всего в билде) | 63 716 |
| Строковые литералы | 20 211 |
| ScriptableObject'ы с данными | 5 059 |

Тела методов остались нативным кодом — восстановлены **имена и структура**, не реализация.
Значения параметров прочитаны отдельно: бандлы дефиниций поставляются **с type tree**,
поэтому UnityPy читает их напрямую.

Файлы разбора: `ITD2_Assembly-CSharp_dump.txt`, `ITD2_string_literals.txt`,
`ITD2_levels.json`, `ITD2_spawn_sections.json`, `ITD2_global_definitions.json`.

## Скорость бега

Пределы задаются на уровень, в `LevelDefinition`:

```
m_initialRunningSpeed        стартовая скорость
m_maxRunningSpeed            потолок
m_runningSpeedIncreaseTime   время выхода на потолок
m_runningSpeedIncreaseCurve  AnimationCurve разгона
```

Из 637 уровней подавляющее большинство держит **постоянные 6.0** — разгона нет вообще.
Разгон включают единицы: `Event_Tempest_S06` идёт 7.0 → 9.0 за 130 секунд,
тестовый `_Test_Player_Speedup` — 12 → 36 за 40 секунд.

Вывод, который стоит взвесить: в шиппящейся игре нарастающая скорость **почти не используется**.
Сложность растёт плотностью и составом зомби, а не скоростью игрока.
Скорость остаётся предсказуемой, чтобы игрок мог учиться читать препятствия.

## Система спавна зомби

Главная находка. `ZombieSpawnSection` — 63 поля, и почти каждый параметр
идёт **тройкой Start / End / Curve**: значение интерполируется от начального
к конечному по кривой на протяжении секции.

Что так рампится: задержка спавна (min/max), шанс появления слева, дистанции по X
слева и справа (min/max), ширина внешней границы, шанс кучи, радиус кучи,
размер кучи (min/max), шанс бочки вместе с кучей, шанс лежащего зомби, шанс поедающего.

Сентинел `-1` означает «не рампить, держать Start».

Секции именуются по схеме, которая сама себе документация:

```
ZSS_Diff4_Dense4_Z1234_LargeClump_Event_Tiger_S09
    │     │      │     │
    │     │      │     └─ пресет кучности
    │     │      └─ разрешённые типы зомби (1,2,3,4)
    │     └─ тир плотности
    └─ тир сложности
```

Распределение 1 365 секций:

| Тир | 0 | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- | --- |
| Сложность | 9 | 76 | 175 | 268 | 209 | 6 |
| Плотность | — | 43 | 167 | 335 | 191 | 7 |

Реальные диапазоны значений:

| Параметр | Мин | Макс |
| --- | --- | --- |
| Задержка спавна | 0.05 с | 6 с |
| Радиус кучи | 0.1 | 12 |
| Размер кучи (min) | 1 | 12 |
| Размер кучи (max) | 2 | 15 |
| Полуширина полосы по X | 0 | 16 |
| Шанс лежащего / поедающего | 0 | 1 |

Пример боевой секции (`Diff4_Dense4`): задержка 0.25 с, полоса ±6.5,
куча гарантированная (шанс 1.0) радиусом 8 из 7–9 зомби, бочка с кучей — 10 %.

## Зомби

`ZombieDefinition` (19 полей) — что описывает одного зомби:

```
m_health, m_size, m_gender, m_bodyArmour, m_helmet
m_movementDefintion            движение в спокойном состоянии
m_alertMovementDefintion       движение после обнаружения игрока
m_awareRadius / m_alertRadius / m_attackRadius    три радиуса реакции
m_turnToFacePlayerChance       шанс развернуться к игроку
m_glancePower                  сила скользящего столкновения
m_collisionMaxXDeathDistance   по X — граница смерти
m_collisionMaxXGlanceDistance  по X — граница скольжения
m_eatingEnabled, m_deathColliderMaxSlide
```

Два решения, которые стоит перенять по смыслу:

**Три радиуса вместо одного.** `aware` → `alert` → `attack` дают зомби постепенное
пробуждение, а не бинарный переключатель агро.

**Столкновение не бинарное.** Отдельные пороги по X для смерти и для скольжения:
задел зомби краем — тебя развернуло и притормозило, вошёл в центр — умер.
Это убирает ощущение несправедливости от «пиксельных» смертей.

`ZombieMovementDefinition` (12 полей): `m_zombieSpeedCurve`, `m_zombieSpeedMin/Max`,
`m_zombieSpeedWhenShotMultiplier` (ускоряется от попадания), `m_acceleration`,
`m_zombieSpeedThresholds`, `m_maxRotation`, `m_freeRotationWhileAlert`,
**`m_playerLeading`** и `m_playerFacingUpdateFreq` — то самое упреждение позиции игрока,
которое у нас уже реализовано.

`ZombieManager` (82 поля) добавляет уровень оркестрации: `m_spawnZDistanceFromPlayer`,
`m_despawnDistance`, `m_minZombieSeparationSq`, `m_minKnockbackSeparation`,
`m_clumpChanceMultiplier`, пул трупов (`m_corpsePool`, `m_corpsePoolSize`),
отдельная система статических зомби (декорации) со своими дистанциями и задержками,
и событийный спавн (`m_spawnEventSize`, `m_spawnEventInterval`, `m_currentEventCapacity`).

## Анимации

**Зомби — большая библиотека клипов.** `ZombieAnimationSet`, 51 поле, клипы лежат
массивами с случайным выбором:

- Скорости движения: `m_walkAnims`, `m_wogAnims`, `m_jogAnims`, `m_runAnims` — **четыре** тира
- Варианты телосложения: `m_fatWalkAnims`, `m_swatWalkAnims`, `m_shieldSwatWalkAnims`
- Состояния: `m_idleAnims`, `m_alertAnims`, `m_eatingAnims`, `m_eatingAlertAnim`
- Подъём и падение: `m_getUpAnims`, `m_selectedGetupAnims`, `m_fallingAnims`, `m_tripAnims`
- Смерти по типу урона: `m_critDeathAnim`, `m_critLegDeathAnims`, `m_deathAnimations`,
  четыре тира взрыва (`Highest` / `High` / `Medium` / `Low`)
- Отбрасывание: `m_knockbackAnims` + триггеры `KNOCKBACK_LEFT` / `MIDDLE` / `RIGHT`
- Взаимодействие с пропами: `m_bangPropAnims`, `m_pinToPropAnims`, `m_swoopAnims`,
  `m_pinnedToGroundAnims`
- Последний шанс: `m_lastChanceStartAnims`, `m_lastChanceStruggleAnims`, `m_lastChanceLifesaverAnims`

Клипы грузятся по пути `Assets/NotResources/ZombieAnimationSets/Animations_{0}.asset`,
отфильтрованный список кэшируется (`m_cachedFilteredAnimList`).

**У игрока полноростовой анимации бега нет.** `PlayerAnimation` (60 полей) — это
Animator, управляемый параметрами, без клипа «бег от первого лица»:

```
PARAM_SPEED, PARAM_WEAPON_BOB_SPEED, PARAM_AIMING, PARAM_SHAKE_LEVEL,
PARAM_STUMBLE_LEVEL, PARAM_ATTACK_SPEED, PARAM_RELOAD_SPEED, PARAM_AMMO_COUNT
TRIGGER_STUMBLE_LEFT / RIGHT, TRIGGER_JUMP, TRIGGER_DRAW, TRIGGER_HOLSTER,
TRIGGER_RELOAD, TRIGGER_RELOAD_DIVERGENT, TRIGGER_HOP_DOWN, TRIGGER_JUMP_DOWN_LAND
```

Ощущение бега целиком делают камера и покачивание оружия — `PARAM_WEAPON_BOB_SPEED`
плюс `m_flashlightAnimationHeadBob` и наклоны камеры в `PlayerMovement`.
Именно так у нас и сделано процедурно, и это подтверждает выбранный подход:
**клип бега для вида от первого лица не нужен**, он нужен только для третьего лица.

## Движение игрока

`PlayerMovement`, 64 поля. Что стоит отметить:

```
m_horizontalTiltDegrees / m_horizontalTiltDuration   наклон камеры по Z при стрейфе
m_facingTiltDegrees / m_facingTiltDuration           наклон по Y
m_speedupRange / m_speedupTimeCutoff                 окно разгона
m_stumbleMin / m_stumbleBoost                        спотыкание
m_glancePower                                        скольжение по препятствию
m_minFallHeight, m_jumpTime, m_gravity
m_flatWallCheckInterval / m_lastFlatWallCheckZ       периодическая проверка стены
m_minZDistanceToNotBeStuck                           анти-застревание
m_disableFlatWallDeath
```

Проверка «плоской стены» с интервалом и порогом застревания — та защита от застревания,
которую обычно дописывают после багрепортов. Имеет смысл заложить сразу.

## Монетизация

Стек рекламы и аналитики в dex — полтора десятка сетей через медиацию:

AppLovin (медиация), ironSource / Unity LevelPlay, Fyber, Chartboost, InMobi, Vungle,
Tapjoy, HyprMX, Moloco, Digital Turbine, Pangle (ByteDance), Facebook Audience Network,
Mintegral, Singular (атрибуция), Firebase + Crashlytics, AWS (Cognito, MobileAnalytics).

Экономические сущности из `global_definitions`: `DataDrivenOffer_Tier01…Tier11` (11 тиров офферов),
энергия с восстановлением (`m_secondsPerUnit`, `m_maxUnitsCommon` / `m_maxUnitsVIP`,
`m_goldPerEnergyRefill`, `m_overchargePurchaseCost`), VIP-подписка,
`m_lifeSaver*` — офферы продолжения после смерти с отдельными порогами для платящих
и неплатящих (`m_lifeSaverNonSpenderDeathsBeforeOffer` / `m_lifeSaverSpenderDeathsBeforeOffer`),
гача-сеты, таймлайн-офферы.

## Что из этого применимо к Task Force Z

| Находка | Что делать |
| --- | --- |
| Спавн через Start/End/Curve на секцию | Сильнее нашей текущей схемы — стоит перенять структуру |
| Скорость бега константная у 619 из 637 уровней | Пересмотреть ставку на разгон как основной драйвер сложности |
| Три радиуса реакции зомби | Заменить бинарное агро |
| Раздельные пороги смерти и скольжения по X | Убирает несправедливые смерти |
| Тиры сложности и плотности как именованные пресеты | Дешёвый способ собирать уровни из готовых блоков |
| Анимации зомби массивами со случайным выбором | Нам хватит 2–3 клипов на состояние вместо одного |
| Отсутствие клипа бега от первого лица | Подтверждает наш процедурный вьюмодель |
| Анти-застревание в стену | Заложить сразу |

## Границы

Разобраны структура кода и числовые параметры — это анализ подхода.
Модели, текстуры, анимационные клипы и звук остаются собственностью PikPok
и в проект не переносятся: политика ассетов проекта требует CC0 или собственных работ
с записью в `LICENSES.md`.
