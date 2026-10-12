# Weapon sourcing: first-person packs (2026-10-12)

Owner: technical artist. Input: verified candidate list from the sourcing run of 2026-10-12 (every licence, price and clip list below was read on the live listing). Nothing has been downloaded yet.

Scope is licence-clean only. The repository is public and the game is monetized, so CLAUDE.md's hard rule and `docs/asset-policy.md` rule 3 apply: CC0, CC BY, Fab Standard License, and Unity Asset Store packs the owner bought. No CC BY-NC, no ND, no SA, no rips, nothing without a stated licence. Epic's Manny/Quinn meshes are Unreal-only content and never ship, even when a Fab pack includes them.

## What the arsenal has today

| Slot | Live pack | Source |
| --- | --- | --- |
| Rifle | BarcodeGames M4 (Fab, free) | `assets/fab/viewmodels/m4_rig.glb`, `src/shared/fab/M4Clips.luau` |
| Pistol | BarcodeGames G17 (Fab) | `assets/fab/viewmodels/g17_rig.glb`, `src/shared/fab/G17Clips.luau` |
| SMG | 1Matzh UZI (CC BY) | `assets/viewmodels/fps/source/smg_rig.glb`, `SMGClips` |
| Shotgun | DuqueCD7 Saps-12 (CC BY) | `assets/viewmodels/fps/source/shotgun_rig.glb`, `ShotgunClips` |
| Rifle (parked) | DuqueCD7 AK-47 (CC BY) | T24 brings it back as a second rifle |
| Pending | FPS Essentials Kit (Unity, bought): G36C, RSASS, MP7, M590, ACR | T25 |

So the BarcodeGames M4 candidate is already imported, and the T25 kit already covers MP7, a pump (M590), a DMR (RSASS) and two more rifles. The picks below avoid duplicating those.

## Budgets that apply

- The only hard number in the project is Roblox's 20,000-triangle limit per MeshPart (`wiki/project-zprun/Decisions.md`). A pack can be larger in total as long as each mesh stays under it; `gltf_anim.py report` prints per-mesh counts.
- There is no viewmodel triangle, texture-memory or bone-count budget in the project yet. I have not invented one. Current live rigs for reference: AK-47 rig 46,785 tris total (largest mesh 14,809), textures uploaded at 1024. Recommend that performance-analyst sets a viewmodel budget at T14 (baseline profile) before the first-wave rigs are uploaded.
- The live viewmodel textures are 1024. Packs advertised at 4K are still worth it because a 1024 downsample from a 4K source is cleaner, but the in-game resolution follows whatever size we upload.

## 1. Ranked shortlist per category

Legend for the animation column: D draw, I idle, W walk, S sprint, F fire, TR tactical reload, ER empty reload, In inspect, H holster. "UE only" means the clips must be exported from Unreal Engine to FBX first.

### Assault rifles

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [Tactical FPS Animation Pack - Assault Rifle](https://www.fab.com/listings/1ae386ab-4a40-4a0f-ac17-621e2d9d1028) | Infima Games | Fab Standard | 31,556 to 73,638 KZT (about $60 to $140) | All 9 plus aimed variants, quick reload, empty inspect, ammo check, fire mode, 2 malfunctions, 3 melee, grenade, heal. 100+ clips | Epic Manny (cannot ship), we supply arms | Not stated | Only candidate that clears the whole quality bar with AAA polish, 5.0 from 13 reviews, Blender source for the rifle, SFX and muzzle VFX. Ranked first despite the arms work because one modular rifle yields several variants and the malfunctions and ammo check are exactly the D8/D9 states. Blocked on the Epic-skeleton arms task (section 5, G1). UE only |
| 2 | [HK 416 A7 FPS ANIMATION](https://sketchfab.com/3d-models/hk-416-a7-fps-animation-9c05037d7d114ff28a82d8a83003b2bd) | Alexander_Ovelar, rifle by r4m | CC BY 4.0 | Free | D, F, TR, Reload 2, No Ammo, In, H. No I, W, S | Own arms, included | 36,220 (4K colour and normal, 2K metal and roughness) | Best free rifle, high texture quality, drops into the Sketchfab glTF path. All 7 actions on one timeline, so it needs frame-range splitting (G2). Idle and locomotion come from the procedural layer |
| 3 | [FPS Animations - Low Poly M4/M16 Modular](https://www.fab.com/listings/36fa380d-9a59-4eeb-999a-dcf51ff21c73) | Dannyboy730, model by D_U | Fab Standard | 18,405 to 36,816 KZT (about $35 to $70) | D, quick D, quick H, W, S, aim in/out, 15 reloads, 7 inspects, melee, throw. Idle and fire not confirmed | UE5 hands (cannot ship) | Low poly, not stated | Widest M4 variety, but low-poly art under the MW2019 bar, unrated, and "MP5" in the description suggests a copy-paste listing. UE only, needs G1 |
| 4 | [FPS Animations - Low Poly AK-74 Modular](https://www.fab.com/listings/729966ea-7315-44db-946b-56291884b944) | Dannyboy730, model by D_U | Fab Standard | 15,775 to 31,556 KZT (about $30 to $60) | D, H, W, S, aim in/out, 3 ER, 2 reloads, 1 TR, 2 In, fire mode. Idle and fire not confirmed | UE5 hands (cannot ship) | Low poly, not stated | Same rig as #3 so they would share setup, but the AK slot is already taken by the DuqueCD7 AK (T24). UE only, needs G1 |
| 5 | [M4 - FPS Weapon Animations Pack FREE (v.1)](https://www.fab.com/listings/38da8f1e-cb54-4cda-beb1-6e55642a55a9) | BarcodeGames | Fab Standard (free), CC BY 4.0 mirror | Free | D, F, TR, ER, H | Own arms | 14,814 | Already live as the Rifle. Listed for completeness; watch for the promised walk and run update and re-bake when it lands |

### Pistols

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [Desert Eagle, First Person Animations](https://sketchfab.com/3d-models/09a213d8510a42d1b747135e85712eff) | 1Matzh; weapon ELIZION; arms Blue-Spirit | CC BY 4.0 | Free | All 9: Equip, Idle, Walk, Run, Fire, Reload, Reload_Empty, Inspect, Unequip | Division Agent arms (same as the live UZI) | 37,636, metalness PBR, 30 textures | Complete set, separate clips, the arms rig family the pipeline already handles. Gives a heavy sidearm distinct from the G17. Needs the D7 sleeve reskin, same as the UZI (A33) |
| 2 | [9mm Pistol, First Person Animations](https://sketchfab.com/3d-models/c26d7f5aa72f4b01a6da4578caa8f07f) | 1Matzh; weapon Urpo; arms Blue-Spirit (Modern Soldier) | CC BY 4.0 | Free | All 9 plus Idle_2 | Modern Soldier arms | 29,321, metalness PBR | Full set, but it overlaps the live G17 and the author warns textures are disorganised. Keep as a better-animated replacement for the G17 if the G17's missing idle and inspect start to hurt |
| 3 | [Animated FPS Police Pistol Gun Pack](https://www.fab.com/listings/ebdc72f4-d41c-4120-a3e9-0b3d7a46d01c) | Ironbelly Studios | Fab Standard | 21,036 to 31,556 KZT (about $40 to $60) | I, W, S, F, Reload, Aim, Aim Walk, Aim Fire, Raise, Lower. No ER, no In | Own arms, 12,120 tris, 69 bones | Pistol 7,501 | Best textures in the slot (4096 PBR on gun and arms) and FBX included, so no UE step. Loses on animation: no empty reload, no inspect, one more Glock-type slot |
| 4 | [Pistol 43 Tactical, FPS Animations](https://sketchfab.com/3d-models/1a4c9d15818a4522aedbeb70919a17da) | dan741vlasov | CC BY 4.0 | Free | In, TR, ER, F, Run, Walk. No D, I, H | Own arms | 9,341 | Lightest pack with both reloads and an inspect, but missing draw and holster |
| 5 | [Animated FPS Loaded 3-Pistol Guns Pack](https://www.fab.com/listings/029c9662-a8aa-4b97-8da9-912160e5d97d) | Ironbelly Studios | Fab Standard | 52,597 to 78,898 KZT (about $100 to $150) | Per gun: I, W, S, F, Reload, Aim set, Raise, Lower. No ER, no In | Own arms, shared with #3 | TT-33 9,734, police 22,260, .44 10,711 | Best paid revolver, but expensive, UE only, rated 3.9, duplicates #3 |
| 6 | [revolver animated](https://sketchfab.com/3d-models/a34b6d0ddc774744bc3567d6afc0878f) | bumstrum | CC BY 4.0 | Free | One "allanims" take, contents unconfirmed | Own arms, bare-hand skin extra | 20,416, 2K PBR | Free revolver, but the clip breakdown cannot be confirmed (demo video gone). Needs G2 and a scrub |

### SMGs

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [FPS Animations LowPoly MP5](https://sketchfab.com/3d-models/fps-animations-lowpoly-mp5-568f00dd76944baaa5eae1a1cc871423) | Cransh; weapon TastyTony | CC BY 4.0 | Free | D, I, W, Run, S, F, TR, ER, In. No H | Cransh's own | 10,673 | 8 of 9 targets as separate clips, drops straight into report and bake. Low-poly weapon is the weakness; a texture pass may be needed for the MW2019 bar |
| 2 | [Scorpion, First Person Animations (2026 Remake)](https://sketchfab.com/3d-models/scorpion-first-person-animations-2026-remake-f2bdfac775344004ad38d0318f0664a4) | 1Matzh; weapon AlexFinsher; arms Blue-Spirit | CC BY 4.0 | Free | D, I, W, Run, F, TR, ER, In, H. No separate S | Division Agent (same as the live UZI) | 34,053 | Cleanest free set after the UZI, same rig family and skin-fix approach. Not on the named target list, but it is a strong second SMG |
| 3 | [FPS Animations - Low Poly MP5 (SD) Modular](https://www.fab.com/listings/fd74538c-3e7d-4e0a-b837-141c2dc70ab5) | Dannyboy730, model by D_U | Fab Standard | 15,775 to 31,556 KZT (about $30 to $60) | 39 clips: D, H, movement, aim, S, 3 reloads, 2 In, melee, throw | UE5 hands (cannot ship) | Low poly | More clips than #1 but same low-poly look plus UE export and G1. Only worth it after G1 exists |
| 4 | [MP7 - Weapon First person animations](https://www.fab.com/listings/6a7753bd-9064-46e4-ac97-217cf6b639da) | Alex Vikodin | Fab Standard | 3,677 to 5,255 KZT (about $7 to $10) | D, H, I, W, S, tactical sprint, 2 hip and 2 ADS fire, TR, ER. No In | Unknown origin | Not stated | Cheap and complete, but T25 already brings an MP7 from the FPS Essentials Kit. Buy only if that MP7 fails the look test |
| 5 | [FPS Animation Pack Ultimate](https://www.fab.com/listings/a2d0dc02-0380-4fb8-84a9-d9e03636aec9) | KINEMATION | Fab Standard | 52,597 to 105,199 KZT (about $100 to $200) | Baked: TR, ER, grenade, tactical sprint. Equip, idle, walk, sprint, recoil are procedural in their runtime and do not exist as clips | Own custom arms | Not stated | 20 weapons including MP5, P90 and Vector lookalikes, but most of the motion is runtime-procedural and would not come across. 3.8 from 20 reviews. Poor value for this pipeline |
| 6 | [Kriss Vector Animated (Free)](https://sketchfab.com/3d-models/kriss-vector-animated-free-54530c888cfd4ae7aab3c3852b229c7e) | BarcodeGames | CC BY 4.0 | Free | D, F, Reload, H | Own arms | 12,418 | Only clean Vector, but a thin 4-clip set |
| ref | [UZI (2026 Remake)](https://sketchfab.com/3d-models/uzi-first-person-animations-2026-remake-73266e9f1eb949b69a3ab11d8f636048) | 1Matzh | CC BY 4.0 | Free | 13 clips | Division Agent | 42,752 | Already live; the reference set for the class. No re-bake needed (latest archive already used) |

### Shotguns

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [FPS Benelli M4 Animations](https://sketchfab.com/3d-models/225a62190f6043ca975eaa2798ab7e2c) | Cransh; gun haoliu95; arms teenjust500 | CC BY 4.0 | Free | I, W, Run, F, last-round F, 2 single-shell reloads, full reload. No D, In, H | "Hand With Gloves" (gloved, military) | 45,748, 1K to 4K metalness PBR, 5 materials | Best free semi-auto with real 4K textures. Gloved arms are the closest free match to D7. Missing draw and holster are cheap to author or proceduralise. Check per-mesh tris against the 20k MeshPart limit |
| 2 | [Tactical Pump Shotgun](https://www.fab.com/listings/095f67f7-ff21-4429-9135-eb27f8c3b5df) | Rebel Thorp | Fab Standard | 34,186 to 68,377 KZT (about $65 to $130) | Every target, shell-by-shell start/loop/stop-loaded/stop-empty, In plus ammo, chamber and magazine checks, jump, interact | Own arms (Epic-skeleton compatible, not Epic's mesh), 3 grip variants | Not stated | The most complete pump set and the arms can ship. Ranked below #1 only on price, UE-only export, and T25's M590 pump overlap. First paid pick if the M590 fails |
| 3 | [VLCG - Double Barrel Shotgun Animations (Vertical)](https://www.fab.com/listings/0dfffdba-3eca-4de1-af25-06c11f5d9c7b) | VLCG | Fab Standard | 28,926 to 105,199 KZT (about $55 to $200) | 33 FP clips: D, H, 2 I, 2 W, Run, F, 2 full reloads, single reload, 3 In, jam fix, melee, block | Assume UE mannequin, needs G1 | Not stated, 1K to 4K | Best double barrel, and block and melee suit a zombie game. UE only plus G1 |
| 4 | [VLCG - Pump Shotgun Animations](https://www.fab.com/listings/237579f9-e011-4c95-ae2f-06feb3c82596) | VLCG | Fab Standard | 28,926 to 105,199 KZT (about $55 to $200) | 40 FP clips, no holster | Not included, needs G1 | Weapon 7,645, 4K | Large set, zombie-tagged, but no arms and no holster, and it overlaps #2 and the M590 |
| 5 | [Animated FPS Automatic-Shotgun Animations](https://www.fab.com/listings/4a25f93c-ec5d-4e98-81b4-c08390724e58) | Bugrimov Maksim | Fab Standard | 18,405 to 31,556 KZT (about $35 to $60) | D, H, 4 I, 4 W, 4 Run, 3 F, 4 melee, Reload, Cartridge Reload, 2 In, jump | Own arms, several skins | Not stated, Lowpoly tag | Full coverage and a Unity package (no UE needed), but low-poly and one magazine reload. Overlaps the live Saps-12 |
| 6 | [Animated Shotgun](https://sketchfab.com/3d-models/e048ba220f9e49c29a3e808cddc22a0a) | teenjust500 | CC BY 4.0 | Free | D (Take), F, reload start/loop/end, In (Watch), H. No I, W, S | Same "Hand With Gloves" as #1 | 28,596, 1K/2K | Best free pump with a real shell loop and the same arms as #1. Backup to the M590 at zero cost |

### Machine guns

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [LMG animated (2022, box-fed)](https://sketchfab.com/3d-models/lmg-animated-50d67a9e586148a49c086fe3127e7abb) | bumstrum | CC BY 4.0 | Free | One take with published ranges: fire 0-10, reload 11-164, reloadB 165-318, hide 319-330, ready 331-377, ambient 378-425, melee 426-450, chain 451-461, chainnormal 462-467 | Own arms (bare hands) | 30,386, 2K PBR | Only LMG with published frame ranges, so G2 can split it without guesswork. Has D, I, F, two reloads, H and melee. No W, S, In |
| 2 | [lmg animated (2019, gloved)](https://sketchfab.com/3d-models/lmg-animated-c02dc6663f344008a502148e751c9974) | bumstrum | CC BY 4.0 | Free | One take, ranges not published | Gloved arms and sleeves, plus a bare-hand skin | 26,630, 2K | Gloves and sleeves are closer to D7, but ranges must be found by scrubbing |
| 3 | [lmg animated (2019, PKM/RPD style)](https://sketchfab.com/3d-models/lmg-animated-3446e01368544efaaceb4635232b6d46) | bumstrum | CC BY 4.0 | Free | One take, ranges not published | Own arms | 21,445, 2K | Covers the Soviet LMG silhouette. The linked sounds have no stated licence, do not take them |
| 4 | [M249 Light Machine Gun LMG (Fps - Tps)](https://www.fab.com/listings/61160c99-aa70-4fb2-a614-84c734572c80) | AB3DX | Fab Standard | 18,407 to 36,818 KZT (about $35 to $70) | Hip and ADS idle, F, auto F, Reload, Reload From Dry, chamber | Not included (UE4/UE5 skeleton), needs G1 | Not stated, high and low poly | Realistic named M249 with FBX and GLB, rated 5.0 (7). No D, H, In, W, S |
| 5 | [Light Machine Gun (LMG) - Rigged, Animated](https://www.fab.com/listings/e63e1bc8-f7c9-492d-9899-019778646944) | mr macbeth | Fab Standard | 26,296 KZT (about $50) | 16 hand plus 9 weapon clips, names unknown | Not included (UE4 skeleton), needs G1 | 62,238, 4K PBR | Best texture fidelity but 62k tris needs decimation or splitting to pass the 20k MeshPart limit, clip names unknown |
| 6 | [FPS Animations - Low Poly RPD](https://www.fab.com/listings/a85a5f07-1b6c-4169-a0a0-5afd33ff8c45) | Dannyboy730 | Fab Standard | 15,775 to 31,556 KZT (about $30 to $60) | 60 clips incl. D, H, S, In, 6 reloads, bipod | UE5 hands, needs G1 | Low poly | Richest LMG clip set, but low-poly and UE only |
| 7 | [PKM Machinegun](https://www.fab.com/listings/34aad9b0-e053-41bb-b763-8cc40292a7d8) | PStudio | Fab Standard | 10,515 to 13,145 KZT (about $20 to $25) | 6 weapon-only clips | None | 40,929, 4x 4K | Realistic PKM weapon only; every hand clip would be authored |
| - | KINEMATION Ultimate (MGX5) | KINEMATION | Fab Standard | as above | Reloads only baked | Own arms | Not stated | Same verdict as in SMGs |

### Launchers

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [FPS Rocket Launcher Animations](https://www.fab.com/listings/93bd04a5-1ea9-4d26-98d8-80577c201ec5) | Bugrimov Maksim | Fab Standard | 18,405 to 31,556 KZT (about $35 to $60) | 23 clips: D, H, 2 I, aim and sight idles, 2 W, 2 Run, 3 F, 2 melee, Reload, In, jump set | Own arms, several skins | Not stated, Lowpoly tag | Only launcher with the whole target set. Unity package gives FBX without installing UE. Low-poly look is the trade-off |
| 2 | [RPG 7 Rocket (Fps - Tps)](https://www.fab.com/listings/887e3947-eede-41ac-9e11-6e546292beda) | AB3DX | Fab Standard | 26,296 to 52,597 KZT (about $50 to $100) | Hip and ADS, F, Reload | AB3DX own rig | Not stated | Realistic RPG-7 shipping as GLB, so it goes straight into report and bake. Only fire and reload; the rest is procedural or authored |
| 3 | [M203 Grenade Launcher (Fps - Tps)](https://www.fab.com/listings/87f3afe9-9099-4d4c-81be-c6a3f503c93a) | AB3DX | Fab Standard | about $50 to $100 | Hip and ADS, F, auto F, Reload, Reload From Dry, chamber | AB3DX own rig | Not stated | Only launcher with a separate dry reload. Underbarrel, so it fits as an attachment state later, not a standalone weapon |
| 4 | [Mk 153 SMAW (Fps-Tps)](https://www.fab.com/listings/e96eadc6-98ec-4b9a-a29c-00e8d5d466e1) | AB3DX | Fab Standard | about $50 to $100 | Hip and ADS, F, fire rocket, Reload | AB3DX own rig | Not stated | Western alternative to #2, same thin set |
| 5 | [Multiple Shot Grenade Launcher (Fps-Tps)](https://www.fab.com/listings/7654edbc-b819-4bed-9f80-d79befc6e870) | AB3DX | Fab Standard | about $50 to $100 | Hip and ADS, F, Reload | AB3DX own rig | Not stated | Closest clean M32-style, generic design, minimal clips |
| 6 | [M136 AT4 Anti Tank Rocket Launcher](https://www.fab.com/listings/66e4db1f-dd8e-468c-8264-7921c01ae3e5) | Max3d | Fab Standard | 15,249 KZT (about $29) | None (static) | None | 20,617, one 4K PBR set | Realistic AT4 model only; single-use weapon needs few clips (draw, idle, fire, discard) |
| 7 | KINEMATION Ultimate (RPG7) | KINEMATION | Fab Standard | about $100 to $200 | RPG7 reload types unconfirmed | Own arms | Not stated | Not worth it for one launcher |

### Throwables and melee

| # | Pack | Author | Licence | Price | Animations | Arms | Tris | Why this rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [First Person Machete](https://www.fab.com/listings/0b5a177a-ba9c-4f7a-85e5-0c8846714710) | BSP | Fab Standard | $3.99 Personal / $5.99 Professional | 12 separate tracks: Equip, Idle, Inspect, Walk, Run, 5 attacks, Punch, Hide | Own arms | 13,884, 2K | Ships as GLB with separate clips, so it is the cheapest possible import. Zombie-tagged. Buy on Fab, not the Sketchfab Store copy (Sketchfab Standard licence) |
| 2 | [Knife FPS Animations](https://www.fab.com/listings/ccff0d84-8219-4daf-9859-348b393b3d83) | Artem Dubinin's Projects | Fab Standard | Free (both tiers $0) | 15 hand plus 3 knife clips, names unconfirmed | Own arms, 5,700 faces | Knife 2,400, 2K and 4K | Free, own arms, Unity package gives FBX without UE. Do not take its placeholder SFX |
| 3 | [Grenade Animation Kit](https://www.fab.com/listings/65d09b89-e8bd-422e-bb50-ed4936150a9d) | Center of Nothing | Fab Standard | $14.99 | 18 FP: D, H (Unequip), I, aim set, pin pull, throw, S, punch, jump | None, Epic skeleton, needs G1 or #4's arms | Grenade 4K | Most complete grenade set (pin and spoon animated). Pairs with #4's bare arms on the same skeleton |
| 4 | [Advanced Combat Knife Animation Kit](https://www.fab.com/listings/791da422-e846-4187-90ae-a0893b9382f8) | Center of Nothing | Fab Standard | $19.99 | 21: D, I, fidget, In set, 2 attacks, backstab, punch, W, Run, knife throw set, jump. No H | Own 4K bare arms on Epic skeleton | Not stated | Own arms that can ship, and they unlock #3. UE only |
| 5 | [First Person Grenade Animations](https://www.fab.com/listings/9d66325a-1021-4ec4-8c14-230bae3320ca) | xidePunk Studio | Fab Standard | $14.99 Personal / $80.99 Professional | D, H, I, W, S, throw, jump | None (Manny demo), needs G1 | Grenade 2K | Clean set but the Professional tier price makes #3 better value |
| 6 | [Arms throwing](https://sketchfab.com/3d-models/1f9a5c717aae4d0f9b77232b7da4b875) | bumstrum | CC BY 4.0 | Free | One 16 s "throw" take | Own arms | 9,816, 2K | Only free usable throw. No grenade mesh, no D, I, H |
| 7 | [knife Animated](https://sketchfab.com/3d-models/f3140db917cc43389c14b5b2536c1dc8) | bumstrum | CC BY 4.0 | Free | One 3:49 "anims" take, contents unconfirmed | Own arms | 16,546, 2K | Popular free knife, but a long unlabelled take; G2 plus a scrub |

## 2. Recommended first wave

Picked for complete clip sets, separate clips over single takes, no Unreal export, and arms that can take the D7 black camo sleeves. All free unless noted; total spend for the wave is about $40 to $66.

| Category | Pick | Role | D7 arms path | Blocked by |
| --- | --- | --- | --- | --- |
| Assault rifle | HK 416 A7 FPS ANIMATION (free) | Second modern rifle next to the M4 and the AK (T24) | Own arms; reskin sleeve and glove materials | T23, G2 |
| Assault rifle (anchor buy, later) | Infima Tactical AR ($60 Personal) | The AAA flagship rifle, several variants from one modular model | Our D7 arms on the Epic skeleton (G1) | T23, G1, UE install |
| Pistol | Desert Eagle (free) | Heavy sidearm next to the G17 | Division Agent arms, same reskin as the UZI (A33) | T23 |
| SMG | FPS Animations LowPoly MP5 (free) | Second SMG | Cransh arms, reskin | T23 |
| SMG | Scorpion 2026 Remake (free) | Third SMG, same rig family as the UZI | Shares the UZI reskin | T23 |
| Shotgun | FPS Benelli M4 (free) | Semi-auto next to the Saps-12; M590 pump arrives through T25 | Gloved military arms, closest free match; sleeves to camo | T23 |
| Machine gun | LMG animated 2022 (free) | First LMG class | Bare hands; reskin or swap to the 2019 gloved variant's arm mesh (same author, likely same rig, check with report) | T23 (new class), G2 |
| Launcher | FPS Rocket Launcher Animations (about $35 Personal) | First launcher class | Pack ships several arm skins; pick the darkest, then camo pass | T23 (new class) |
| Melee | First Person Machete (about $4 Personal) | First melee weapon | Own arms; reskin | T23 (new class) |
| Throwable | Arms throwing (free) plus a grenade mesh | First grenade | Own arms; reskin | T23 (new class), G2, grenade mesh (section 5) |

Not in the first wave on purpose: KINEMATION (procedural core does not transfer), Dannyboy730 packs (low-poly look plus G1), the Ironbelly packs (no empty reload or inspect), MP7 and pump purchases (T25 covers both), the BarcodeGames M4 (already live).

D7 note: which camo and glove look each pack gets is the art director's call (A16 and A33). The technical path is the same for every pick: either retexture the pack's sleeve and glove materials (Blender MCP, bake to colour, normal, roughness, metalness) or transfer the DuqueCD7 Comando sleeve and glove meshes (`M_Shirt_BlackCamo2`, `M_Gloves_Black`, already CC BY in the repo) onto the pack's arm bones with weight transfer. The second gives one consistent sleeve on every class and is what I recommend once A16 settles the look.

## 3. Owner download steps

General: Sketchfab downloads need a free Sketchfab account. Fab needs an Epic Games account; add to library or buy, then download from the listing or the Epic launcher. Personal tier fits a sole proprietor under Fab's revenue threshold; check the threshold on https://www.fab.com/eula before buying and pick Professional if it is exceeded. Keep receipts.

Locations: Fab sources go under `assets/fab/` (gitignored). Sketchfab CC BY sources go under `assets/viewmodels/fps/source/` (not ignored: only the stripped `*_rig.glb` is committed there today, so do not stage the raw downloads; if you want them ignored, that is a one-line `.gitignore` change for a separate approval).

| Pick | Steps |
| --- | --- |
| HK 416 A7 | Sketchfab, Download 3D Model, choose "glTF" (the "Autoconverted format (glb)" option, original textures, not the 1K/2K downsample). Save as `assets/viewmodels/fps/source/hk416_src.glb`. Also grab the original FBX archive into `assets/viewmodels/fps/source/hk416_src_fbx/` as a fallback for skin repair |
| Desert Eagle | Sketchfab, glb at original texture size to `assets/viewmodels/fps/source/deagle_src.glb`; take the source archive (.blend and .fbx) into `assets/viewmodels/fps/source/deagle_src_fbx/` because the UZI needed the FBX to solve its skin fix |
| LowPoly MP5 | Sketchfab, glb to `assets/viewmodels/fps/source/mp5_src.glb`; source .blend to `assets/viewmodels/fps/source/mp5_src_blend/` |
| Scorpion | Sketchfab, glb to `assets/viewmodels/fps/source/scorpion_src.glb`; source archive (35 MB, FBX and .blend) to `assets/viewmodels/fps/source/scorpion_src_fbx/` |
| Benelli M4 | Sketchfab, glb to `assets/viewmodels/fps/source/benelli_src.glb`; original `HandWithGloves_AnimateRDY.fbx` to `assets/viewmodels/fps/source/benelli_src_fbx/` |
| LMG 2022 | Sketchfab, glb to `assets/viewmodels/fps/source/lmg_src.glb`. Optional: the 2019 gloved LMG glb to `assets/viewmodels/fps/source/lmg_gloved_src.glb` for its arm mesh |
| Arms throwing | Sketchfab, glb to `assets/viewmodels/fps/source/throw_src.glb` |
| Rocket Launcher (Bugrimov) | Fab, buy Personal, download the Unity package (not the UE package). Save to `assets/fab/viewmodels/rocket_src/`. The `.unitypackage` is unpacked with the same no-Unity unpack script T25 uses, keeping FBX and textures only |
| Machete (BSP) | Fab, buy Personal, download the "glb" converted format plus the FBX zip. Save to `assets/fab/viewmodels/machete_src/` |
| Infima AR (later) | Fab, buy Personal, download the UE project (5.4 to 5.8) and the Blender rifle source into `assets/fab/viewmodels/infima_ar_src/`. Needs Unreal Engine installed to export FBX |

## 4. Import plan through tools/fps_pack

### Common steps per pick

1. `python3 tools/fps_pack/gltf_anim.py report <src.glb>`: confirm clip names, per-mesh triangle counts against the 20k MeshPart limit, materials and textures, the joint tree. Record findings in the pack's manifest note.
2. If weapon parts are unskinned meshes under joint nodes (BarcodeGames-style): `python3 tools/fps_pack/rigidify.py <src.glb> <rigid.glb> [--joint-regex ...]`.
3. Strip: `python3 tools/fps_pack/strip_glb.py <src.glb> <rig.glb> --root-scale S [--mesh REGEX] [--skin-fix skin_fixes/<pack>.json]`. Choose S so forearms and hands match the pistol rig's size, as the AK (2.961), Saps-12 (1.2218) and UZI (3.0) did. If the skin imports at the wrong scale (the UZI symptom), solve a skin fix from the source FBX first.
4. Bake and emit: add a pack entry to `tools/fps_pack/build_clips.py` (glb, scale, extra nodes such as `Camera`, skin fix, skip regex) and run `python3 tools/fps_pack/build_clips.py --src <dir> --only <Pack>`; or by hand `gltf_anim.py bake <src.glb> <baked.json> --fps 30 [--extra Camera] [--skin-fix ...]` then `emit_luau.py <baked.json> <out.luau> --scale S [--rename ...] [--skip ...]`. CC BY packs emit to `src/shared/viewmodel_clips/<Pack>Clips.luau` (committed); Fab packs to `src/shared/fab/<Pack>Clips.luau` (gitignored).
5. If the importer drops SurfaceAppearances: `python3 tools/fps_pack/extract_surfaces.py <rig.glb> <out_dir> ...` and add `texture/viewmodel/<pack>_*` rows.
6. Manifest rows, then `python3 scripts/upload_assets.py` and `python3 scripts/sync_configs.py`, which regenerate `assets/LICENSES.md` and `CreditsConfig.luau`. Never hand-edit LICENSES.md and never type an asset id.
7. Wire through T23's weapon template, then the asset-policy gate: a look and listen in a Studio playtest, plus selene, validate_api, comment check, rojo build and the tests.

### Per pick

| Pick | Rig key | Notes beyond the common steps |
| --- | --- | --- |
| HK 416 A7 | `viewmodel/fps/hk416/rig` | Single timeline: needs G2 ranges for UP, INSPECTION, RELOAD, RELOAD 2, SHOOT, NO AMMO, DOWN; scrub "NO AMMO" to tell dry fire from empty reload. Map RELOAD and RELOAD 2 onto the D8 states (A42). Idle, walk, sprint from the procedural layer |
| Desert Eagle | `viewmodel/fps/deagle/rig` | Same rig family as the UZI: expect the shared-skin defect, solve `skin_fixes/deagle.json` from the FBX. `clip_name` already strips the `rig|` prefix |
| LowPoly MP5 | `viewmodel/fps/mp5/rig` | Strip the `Arms_` prefix with `--rename`. Holster from a reversed Arms_Draw or a procedural lower |
| Scorpion | `viewmodel/fps/scorpion/rig` | Same as Desert Eagle. Run doubles as sprint |
| Benelli M4 | `viewmodel/fps/benelli/rig` | Two single-shell reloads give the shell loop; ReloadFull is the empty reload. Author Equip and Unequip in Blender MCP on the same rig or use the procedural raise and lower. Split any mesh over 20k tris |
| LMG 2022 | `viewmodel/fps/lmg/rig` | G2 with the published ranges (fire 0-10, reload 11-164, reloadB 165-318, hide 319-330, ready 331-377, ambient 378-425, melee 426-450, chain 451-461, chainnormal 462-467). `chain` drives belt links during fire. Do not take the sounds unless their licence is found |
| Arms throwing | `viewmodel/fps/throw/rig` | G2 after a scrub; the grenade is a separate mesh attached to the hand bone |
| Rocket Launcher | `viewmodel/fps/rocket/rig` | FBX from the Unity package, FBX2glTF (as for the Fab zombie pack), then report. Arms skins: keep one, drop the rest with `--mesh` |
| Machete | `viewmodel/fps/machete/rig` | GLB direct. Fab's converter may lay all takes on one timeline; `rigidify.py` already shifts each animation to start at zero |
| Infima AR | `viewmodel/fps/infima_ar/rig` | UE export of the rifle skeletal mesh and every AnimSequence to FBX, FBX2glTF, retarget or re-skin onto G1 arms, bake with `--extra ik_hand_gun` |

### Manifest rows (shape)

Same shape as the existing `viewmodel/fps/smg/rig` and `viewmodel/fps/m4/rig` rows: `source`, `license`, `file`, `status`, `note` (scale, skin fix, clip module path). Licence strings:

- CC BY: `CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), credit the author`
- Fab: `Fab Standard License (https://www.fab.com/eula); not committed, the repo is public`

Source strings to put in the manifest (sync_configs.py copies them into LICENSES.md and the in-game credits):

- `"HK 416 A7 FPS ANIMATION" by Alexander_Ovelar (@Alexander_Ovelar); uses "HK 416 A7" by @r4m (https://sketchfab.com/3d-models/a16768f0ffa24737a4fe324a411cfbd9), https://sketchfab.com/3d-models/hk-416-a7-fps-animation-9c05037d7d114ff28a82d8a83003b2bd, glb downloaded <date>; animations stripped by tools/fps_pack/strip_glb.py`
- `"Desert Eagle | First Person Animations" by 1Matzh (@1Matzh); uses "Desert Eagle" by @ELIZION and "Division Agent (Rigged)" by @Blue-Spirit, https://sketchfab.com/3d-models/09a213d8510a42d1b747135e85712eff, glb downloaded <date>; ...`
- `"FPS Animations LowPoly MP5" by Cransh (@ccransh); uses "Low-Poly HK MP5SD" by @TastyTony, https://sketchfab.com/3d-models/fps-animations-lowpoly-mp5-568f00dd76944baaa5eae1a1cc871423, glb downloaded <date>; ...`
- `"Scorpion | First Person Animations (2026 Remake)" by 1Matzh (@1Matzh); uses "CZ Scorpion Evo3 A1" by @AlexFinsher and "Division Agent (Rigged)" by @Blue-Spirit, https://sketchfab.com/3d-models/scorpion-first-person-animations-2026-remake-f2bdfac775344004ad38d0318f0664a4, glb downloaded <date>; ...`
- `"FPS Benelli M4 Animations" by Cransh (@ccransh); uses "M4 Super 90 (JW2) Brand-Friendly version" by @haoliu95 and "Hand With Gloves" by @teenjust500, https://sketchfab.com/3d-models/225a62190f6043ca975eaa2798ab7e2c, glb downloaded <date>; ...`
- `"LMG animated" by DJMaesen (@bumstrum), https://sketchfab.com/3d-models/lmg-animated-50d67a9e586148a49c086fe3127e7abb, glb downloaded <date>; ...`
- `"Arms throwing" by DJMaesen (@bumstrum), https://sketchfab.com/3d-models/1f9a5c717aae4d0f9b77232b7da4b875, glb downloaded <date>; ...`
- `"FPS Rocket Launcher Animations" by Bugrimov Maksim, https://www.fab.com/listings/93bd04a5-1ea9-4d26-98d8-80577c201ec5, Unity package from Fab (Personal tier) downloaded <date>; FBX converted with FBX2glTF; ...`
- `"First Person Machete" by BSP, https://www.fab.com/listings/0b5a177a-ba9c-4f7a-85e5-0c8846714710, GLB from Fab (Personal tier) downloaded <date>; ...`

Any reskinned arm that uses the DuqueCD7 Comando sleeves or gloves also carries the existing DuqueCD7 credit on its texture rows.

### Dependency on T23

Every pick adds a second weapon to an existing class or a new class, and T23 (`production/claude-desktop-tasks.md`) is what makes either possible: today packs are looked up by class and about 17 files use the literal "Rifle". Order of work:

- Offline steps 1 to 5 (report, strip, bake, emit) and the manifest and upload can run before T23 lands; the clip modules simply have no consumer yet.
- Wiring into WeaponsConfig and ViewmodelPackConfig waits for T23's pack key and weapon template.
- LMG, launcher, melee and throwable also need new classes in AnimationsConfig.locomotionSets, ViewmodelConfig.ARM_GRIP defaults and the audio class map; T23 should keep that open-ended.
- Suggest T23 also re-key `tools/fps_pack/build_clips.py` `PACKS` by pack instead of class, or the new entries will collide with "Rifle" and "SMG".
- D8 three-state reloads (A42) and D7 arms (A16, A33) apply to every pick after it is wired.

## 5. Gaps and what to do instead

| Gap | Instead |
| --- | --- |
| G1. No shippable arms on the Epic skeleton. Blocks Infima AR, all Dannyboy730 packs, VLCG shotguns, Center of Nothing grenade, xidePunk grenade, AB3DX M249, mr macbeth LMG | One tooling task: build a D7 arms mesh (DuqueCD7 Comando black camo sleeves and black gloves, CC BY) skinned in Blender MCP to a skeleton we build with the Epic hand and arm bone names and Manny bind positions read from a pack FBX. Never ship Epic's mesh or skeleton asset. Alternative: extend `tools/zombie_pack/retarget_ue.py`'s method to map Epic arm and finger bones onto the Rigify `DEF-` bones of the existing Comando arms. Fingers retarget imperfectly per Infima's FAQ, so check grips frame by frame. Cheapest unblock: buy Center of Nothing's knife kit ($20), whose bare arms are already on the Epic skeleton and can ship |
| G2. No frame-range splitting in tools/fps_pack. `gltf_anim.py bake` and `build_clips.py` bake whole animations; `rigidify.py` only shifts takes to zero. Blocks HK416, all bumstrum packs, the revolver | Small tooling change (separate approval): a per-pack range table (`name: [start, end]` in frames or seconds) that slices one animation into clips before emit. Ranges for the LMG are published; the others come from a scrub in Blender MCP or Studio |
| Faithful M79 or M32 | None licence-clean with arms. Use "Grenade-launcher M79" by balaganila (CC BY 4.0, 6,894 tris, weapon reload clip only, https://sketchfab.com/3d-models/ea54d16860c14dffaede1e50a4f19a36) on our D7 arms with Blender MCP authored draw, idle, fire, break-open reload and holster. The Sketchfab Milkor M32 by user77 is CC BY-NC and rejected |
| AT4 | Max3d static AT4 ($29, 20,617 tris, 4K) plus four authored clips (draw, idle, fire, discard) on our arms |
| PKM with clips | PStudio PKM ($20, weapon-side clips only) plus authored hand clips, or the free bumstrum PKM-style LMG |
| AAA-textured LMG with own arms | None. bumstrum is 2K. If the LMG needs to look better up close, buy mr macbeth's 4K LMG and fit its weapon mesh onto bumstrum's weapon bones (decimate to under 20k per mesh), keeping bumstrum's arm clips |
| Grenade mesh for the free throw | "Grenades" by Cranks Dev on Fab ($8.99, GLB, frag, flash, stun, CS gas and 3 smoke at 9 to 11k tris, 2K), or a CC0 or AI-generated grenade through the Cube 3D path; pin and spoon need separate meshes for a pin-pull beat |
| Sniper rifle | Not covered by this search. T25's RSASS covers the DMR slot; KINEMATION includes snipers but bakes only reloads. Run a separate sourcing pass for a bolt-action |
| Holster, idle, walk, sprint missing in several picks | Procedural raise and lower, bob and sway already in Viewmodel, plus Luau-authored poses or Blender MCP clips on the pack's own rig; asset policy allows either if it passes the look test |
| Viewmodel triangle and texture budget | Not defined in the project. Ask performance-analyst to set one at T14 before the first-wave uploads |
