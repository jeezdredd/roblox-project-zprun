# Assets Pipeline

Every texture, sound and animation in Task Force Z goes through one path: a manifest entry, an Open Cloud upload, and a generated config module. No Roblox asset id is ever typed into gameplay code by hand.

```
assets/manifest.json
  -> scripts/upload_assets.py   (Open Cloud upload, moderation poll, writes assetId + status back)
  -> scripts/sync_configs.py    (generates src/shared/config/AssetIds.luau and assets/LICENSES.md)
  -> src/shared/config/*.luau   (named aliases: TexturesConfig, AudioConfig, SfxConfig, ...)
  -> gameplay code              (guards on id > 0, degrades silently)
```

The rule from `CLAUDE.md` is unconditional: every new asset is registered in the manifest, uploaded by the script, listed in `assets/LICENSES.md`, and audio must be a real CC0/licensed file, never generated.

## The manifest

`assets/manifest.json` is a flat JSON object keyed by a slash-separated path. The key is the identity of the asset everywhere else in the project — the folder layout on disk and the shape of `AssetIds.luau` both follow it.

| Field | Meaning |
| --- | --- |
| key | Slash path, e.g. `audio/footsteps/metal_01`, `texture/surface/asphalt`, `animation/player/run`. Becomes `AssetIds.audio.footsteps.metal_01`. |
| `source` | Origin URL, or the literal `generated` / `pending` for entries with no upstream page. |
| `license` | Licence string reproduced verbatim in `assets/LICENSES.md`. |
| `file` | Repo-relative path of the binary, e.g. `assets/audio/weapons/shot_pistol.wav`. |
| `assetId` | Roblox asset id written back by the upload script. `0` means not uploaded. |
| `status` | Lowercased moderation state from the Open Cloud operation: `approved`, `reviewing`, `rejected`, or `pending` for entries never uploaded. |
| `note` | Optional free text — why an entry was replaced, or what an unrecorded animation is meant to be. |

Current state: 110 entries — 83 `approved`, 13 `reviewing`, 12 `pending`, 2 `rejected`.

| Category | Entries |
| --- | --- |
| `audio/*` | 79 (footsteps 21, weapons 17, zombie 8, player 6, foley 6, city 5, ui 5, world 4, unused 4, music 2, range 1) |
| `texture/*` | 19 (surface 13, pbr 6) |
| `animation/*` | 12 (player 5, zombie 7) |

The binaries themselves are not tracked. `.gitignore` excludes `assets/textures/*.jpg`, `assets/textures/*.png` and `assets/audio/**/*.ogg|mp3|wav`, so the repository carries only `manifest.json`, the generated `LICENSES.md` and the generated `AssetIds.luau`. A fresh clone can build and run the game — every asset resolves from its uploaded id — but re-uploading requires re-downloading the source files.

## Upload: `scripts/upload_assets.py`

Uploads every manifest entry that has no `assetId` yet.

```
python3 scripts/upload_assets.py [--dry-run] [--only PREFIX]
```

- **Auth.** Reads an Open Cloud API key with asset read+write scope from `.opencloud.key` at the repo root. That file is git-ignored and the script exits immediately if it is missing. The owning account is hardcoded as `USER_ID = "3783240909"`.
- **Selection.** Skips entries that already have an `assetId`, entries whose `file` is missing on disk (printed as `skip <key>: file missing`), and entries whose extension maps to no asset type. `--only PREFIX` filters by key prefix, e.g. `--only audio/weapons`.
- **Asset type.** Inferred from the extension: `.ogg/.mp3/.wav` → `Audio`, `.png/.jpg/.jpeg` → `Image`, otherwise `Animation` if the key starts with `animation/`. Anything else is skipped.
- **Upload.** A `curl` subprocess POSTs multipart form data to `https://apis.roblox.com/assets/v1/assets` with `x-api-key`, a `request` part holding the JSON body (`assetType`, `displayName`, description `"Task Force Z asset"`, `creationContext.creator.userId`) and a `fileContent` part with an explicit MIME type. The display name is derived from the key: `tfz-` plus the key with `/` and `_` replaced by `-`, so `audio/weapons/shot_pistol` uploads as `tfz-audio-weapons-shot-pistol`.
- **Moderation poll.** The POST returns an `operationId`; the script polls `https://apis.roblox.com/assets/v1/operations/<id>` up to 30 times with a 5 second delay (150 seconds per asset worst case) until `done` is set, then reads `response.assetId` and `response.moderationResult.moderationState`.
- **Write-back.** `assetId` and the lowercased state are written into the entry and the whole manifest is saved after *every* successful asset, so an interrupted or rate-limited run is resumable — rerunning picks up exactly where it stopped, because entries that already have an id are skipped.
- **Exit code.** Non-zero if any entry failed, which is what makes it usable from a script.

`--dry-run` prints what would upload (`would upload <key> (<type>) from <path>`) and exits without touching the network or the key file.

Two consequences worth knowing:

1. The 12 animation entries have `source: "pending"` and reference `.rbxm` files under `assets/animation/` that do not exist. Every run reports them as `file missing` and their ids stay `0`. The game runs anyway — see the degradation rule below.
2. Moderation can reject an asset after it has been assigned an id. `audio/unused/siren_police_rejected` and `audio/weapons/shell_03` both carry real ids with `status: "rejected"`; the sync step is what neutralises them.

## Sync: `scripts/sync_configs.py`

Regenerates both derived files from the manifest.

```
python3 scripts/sync_configs.py [--check]
```

**`src/shared/config/AssetIds.luau`.** Keys are split on `/` and folded into a nested table, all levels sorted alphabetically, emitted with a "Generated by scripts/sync_configs.py — do not edit by hand" header and closed with `return table.freeze(AssetIds)`. The id written is `entry.assetId or 0`, **forced to `0` when `status == "rejected"`**. Note that `reviewing` is *not* zeroed — an asset still in review keeps its id and starts working the moment moderation clears, with no code change.

**`assets/LICENSES.md`.** A single sorted Markdown table of asset key, licence, source link, asset id and status, plus the note that entries marked `Original work (project owner)` were made for this project. It is the attribution document, so it must be regenerated whenever a licence or source changes, not only when ids change.

**`--check`** compares the rendered output against the files on disk and exits `1` with `generated files are out of date, run scripts/sync_configs.py` if either differs, without writing. This is the CI/pre-commit form. Without `--check` the script writes only files whose content actually changed and prints a one-line summary (`synced 110 entries (98 with asset ids)`) — that count includes rejected entries, since it counts a present `assetId`, not the status.

## How configs consume ids

`AssetIds.luau` is never required directly by gameplay code except where a whole branch is needed. Each domain config maps raw ids to named constants, and that is what systems require.

| Config | AssetIds branch | Notes |
| --- | --- | --- |
| `TexturesConfig.luau` | `texture.surface.*`, `texture.pbr.*` | Role aliases: `ASPHALT`, `CONCRETE_NORMAL`, `SAND_ROUGHNESS`, `FENCE_CHAINLINK`, ... |
| `AudioConfig.luau` | `audio.music.*`, `audio.city.*`, `audio.player.death_scream`, `audio.zombie.growl_01` | Music, sirens, helicopter loop, SoundGroup names and rolloff distances |
| `SfxConfig.luau` | `audio.foley.*`, `audio.player.*`, `audio.zombie.*`, `audio.world.*`, `audio.ui.*` | The large SFX tuning table; id lists like `FOLEY_GEAR_IDS`, `ZOMBIE_BITE_IDS` |
| `FootstepConfig.luau` | `audio.footsteps.*` | Three-variant sets per `Enum.Material`, concrete as fallback |
| `BreathingConfig.luau` | `audio.player.breath_calm/heavy/gasp` | Exertion-blended breath layers |
| `AnimationsConfig.luau` | `animation.player.*` | All five ids currently `0` |
| `src/server/systems/ZombieAnimator.luau` | `animation.zombie.*` | Requires `AssetIds` directly for the seven zombie clips |
| `src/client/systems/WeaponSfx.luau` | `audio.weapons.*` | Requires `AssetIds` directly and looks the branch up by string key |

The last row is the one deliberate exception to the alias rule: `WeaponsConfig` stores sound *names* (`shotSound = "shot_pistol"`, `closeSound = "close_pistol"`) and `WeaponSfx.weaponSoundId` resolves them against `AssetIds.audio.weapons` at runtime, so adding a weapon class is a config edit plus a manifest entry with a matching key, with no new alias constant.

**The degradation rule.** Every consumer guards on `id > 0` (or `assetId <= 0`) and no-ops instead of erroring. `TextureUtil.applyFace` returns early, `ZombieAnimator.loadTrack` returns `nil` and the animator silently skips that track, `WeaponSfx.playTail` returns without a tail. This is why the game is fully playable with all 12 animations still at `0`, and why an asset moving from `reviewing` to `approved` needs no code change at all.

## MaterialVariant registration

`src/shared/util/MaterialUtil.luau` turns the PBR texture triples into real Roblox materials. `MaterialUtil.register()` runs once at boot from `src/server/init.server.luau` under `runStage("Materials", ...)`.

Three sets are defined, each a colour + normal + roughness triple over a base material:

| Variant | Base material | Textures | StudsPerTile |
| --- | --- | --- | --- |
| `TFZ_Asphalt` | `Enum.Material.Asphalt` | ambientCG Asphalt033 | 12 |
| `TFZ_Concrete` | `Enum.Material.Concrete` | ambientCG Concrete034 | 6 |
| `TFZ_Sand` | `Enum.Material.Sand` | ambientCG Ground080 | 8 |

`register()` skips a set whose colour, normal or roughness id is `<= 0`, skips one already present in `MaterialService`, and records what it registered. `MaterialUtil.apply(part, setName)` then sets `part.Material` to the base material and `part.MaterialVariant` to the name, returning `false` if the variant was never registered — callers use that return value as their fallback branch:

- `src/server/systems/ChunkFactory.luau` falls back to a plain tiled `Texture` for the lane floor.
- `src/server/systems/HangarBuilder.luau` (hangar floor, `TFZ_Concrete`), `src/server/systems/DesertBase.luau` (ground `TFZ_Sand`, road `TFZ_Asphalt`).

**Why `MaterialVariant` and not `SurfaceAppearance`:** `SurfaceAppearance` only applies to `MeshPart`. The entire world here is built from `Instance.new("Part")` — lane floors, hangar walls, desert ground — so `SurfaceAppearance` would attach to nothing. `MaterialVariant` is registered globally in `MaterialService` and selected per-part via the `MaterialVariant` string property on any `BasePart`, which is the only route to normal and roughness maps on primitives. The cost is that variants are a global registry keyed by name, hence the `registered` guard and the `MaterialUtil.ENABLED` kill switch.

For the non-PBR case `src/shared/util/TextureUtil.luau` attaches plain `Texture` instances with matched `StudsPerTileU/V`, per face (`applyFace`), on the four sides (`applySides`) or all six (`applyAll`), and returns early on `textureId <= 0`. Tiling density is chosen per surface rather than left at the default so texels stay square and do not smear when a part is scaled.

## Licensing sources

Only sources whose licence permits redistribution inside a Roblox experience are used, and each is recorded per entry so `LICENSES.md` can reproduce it.

| Source | Licence | Used for |
| --- | --- | --- |
| ambientCG | CC0 | All 19 textures: asphalt, concrete, grass, ground, bricks, metal plates, corrugated steel, tiles, wood floor, rust, fabric, chainlink fence, sand — plus the six normal/roughness maps |
| Kenney | CC0 | Impact and interface sound packs: gear foley, landings, cloth whoosh, magazine in/out, bolt, shells, dryfire, all five UI sounds |
| OpenGameArt | CC0 / CC BY 3.0 | Menu and mission music, death scream, zombie noises, facility siren, wind, distant explosion, hangar roomtone, radio call, and the gunshot pack |
| Wikimedia Commons | Public domain | Breathing loops, heartbeat, civil-defence siren, helicopter, fire crackle, gong, one zombie growl |

Licence totals across the manifest: CC0 54, `Original work (project owner)` 35, Public domain 11, CC BY 3.0 (Vincent Sevedge) 10.

**Audio must be real licensed files, never generated.** 23 entries still carry `source: "generated"` — the 21 footstep variants and the police/ambulance sirens — and they are the debt this rule exists to retire. Synthesised audio reads as thin and tonally wrong next to recorded material, and it makes the licence column meaningless. The 12 `animation/*` entries are the other outstanding block: they are marked `Original work (project owner)` with no file, so nothing plays yet.

## Gunshot audio provenance

The per-class weapon audio is the newest and most structured part of the manifest. Ten entries come from a single OpenGameArt gunshot recording pack (CC BY 3.0, Vincent Sevedge), cut into one-shots:

| Key | Role |
| --- | --- |
| `shot_pistol`, `shot_smg`, `shot_rifle`, `shot_shotgun` | Base per-class report, used for other players' distant shots |
| `close_pistol`, `close_smg`, `close_rifle`, `close_shotgun` | Close-perspective layer for the local shooter |
| `tail_open` | Outdoor reflection tail |
| `tail_interior` | Enclosed-space reflection tail |

All ten are currently `reviewing`, so they carry ids and will start playing without a code change once moderation clears.

`src/client/systems/WeaponSfx.luau` prefers the `close_*` id for the local player and falls back to the `shot_*` id when it is `0`; `playDistantShot` always uses `shotSoundId` on a temporary 3D anchor part. The tail choice is driven by geometry, not by biome: the module scans for `BasePart`s carrying an `AcousticSpace` attribute (set by `HangarBuilder` and `DesertBase` over the hangar interior and its canopy), and if the local root is inside an `AcousticSpace == "Interior"` zone it plays `tail_interior` and pushes the shared `ReverbSoundEffect` to `DecayTime` 1.5 / `WetLevel` -8, otherwise `tail_open` at 0.4 / -18. Tails are rate-limited to one per 0.55 s so sustained automatic fire does not stack them.

The remaining weapon sounds (`mag_out`, `mag_in`, `bolt`, `dryfire`, `shell_01`..`shell_03`) are Kenney CC0. `shell_03` was rejected by moderation and is zeroed by the sync step; `WeaponSfx` picks between `shell_01` and `shell_02` only.

## Adding a new asset

1. Obtain a real licensed file (CC0, public domain, or an attribution licence whose terms you can satisfy). Do not generate audio.
2. Drop it under `assets/audio/<group>/` or `assets/textures/` with a name matching the manifest key you intend to use.
3. Add the entry to `assets/manifest.json`: key, `source` URL, `license`, `file`, `assetId: 0`, `status: "pending"`.
4. `python3 scripts/upload_assets.py --dry-run --only <prefix>` and confirm it lists the new entry.
5. `python3 scripts/upload_assets.py --only <prefix>` — it uploads, polls moderation and writes back `assetId` and `status`.
6. `python3 scripts/sync_configs.py` to regenerate `AssetIds.luau` and `LICENSES.md`. Never hand-edit either file.
7. Add a named alias in the relevant config (`TexturesConfig`, `SfxConfig`, `AudioConfig`, `FootstepConfig`, ...) — except for weapon sounds, which are resolved by string key from `WeaponsConfig`.
8. If it is a PBR triple, add a set to `MaterialUtil.sets` with a `TFZ_` name and a sensible `StudsPerTile`, and give every call site a non-variant fallback.
9. Consume it with an `id > 0` guard so the game still runs while moderation is pending.
10. Run the gate: `selene src/`, `python3 tools/validate_api.py`, `rojo build`. Commit the manifest, `LICENSES.md`, `AssetIds.luau` and your config change — the binary itself stays untracked.

If an asset comes back `rejected`, leave the entry in place with the rejection recorded in `note`, move the file under `assets/audio/unused/` if it is being replaced, and add a fresh entry for the replacement. The sync step already forces rejected ids to `0`, so no consumer needs to know.

---

See also: [[Overview]], [[Architecture]], [[Gameplay Systems]], [[Performance]], [[Decisions]].
