# Assets Pipeline

> Status 2026-09-29 (evening): the manifest holds 438 entries (421 `approved`, 5 `reviewing`, 7 `pending`, 4 `rejected`, 1 `needed`). Zombie clips now come from the Sketchfab packs (22 `animation/zombie_sf/*` entries), first-person clips are baked into Luau instead of uploaded, and the only pending animation slots are the two player strafe loops and five unused `animation/weapon/*` slots. New sections at the end cover the zombie and first-person pack pipelines and the Free Firearm Sound Library audio.

Every texture, sound and animation in Task Force Z goes through one path: a manifest entry, an Open Cloud upload, and a generated config module. No Roblox asset id is ever typed into gameplay code by hand.

```
assets/manifest.json
  -> scripts/upload_assets.py   (Open Cloud upload, moderation poll, writes assetId + status back)
  -> scripts/refresh_status.py  (re-reads moderation state later, marks rejections)
  -> scripts/sync_configs.py    (generates src/shared/config/AssetIds.luau and assets/LICENSES.md)
  -> src/shared/config/*.luau   (named aliases: TexturesConfig, AudioConfig, SfxConfig, ...)
  -> gameplay code              (guards on id > 0, degrades silently)
```

The rule is unconditional: every new asset is registered in the manifest, uploaded by the script, listed in `assets/LICENSES.md`, and audio must be a real CC0/licensed file, never generated.

## The manifest

`assets/manifest.json` is a flat JSON object keyed by a slash-separated path. The key is the identity of the asset everywhere else in the project: the folder layout on disk and the shape of `AssetIds.luau` both follow it.

| Field | Meaning |
| --- | --- |
| key | Slash path, e.g. `audio/footsteps/metal_01`, `texture/surface/asphalt`, `animation/player/run`. Becomes `AssetIds.audio.footsteps.metal_01`. |
| `source` | Origin URL, or the literal `generated` / `pending` for entries with no upstream page. |
| `license` | Licence string reproduced verbatim in `assets/LICENSES.md`. |
| `file` | Repo-relative path of the binary, e.g. `assets/audio/weapons/shot_pistol.wav`. |
| `assetId` | Roblox asset id written back by the upload script. `0` means not uploaded. |
| `status` | Lowercased moderation state from the Open Cloud operation: `approved`, `reviewing`, `rejected`, or `pending` for entries never uploaded (`needed` marks a slot with no acceptable source yet). |
| `note` | Optional free text: why an entry was replaced, or what an unrecorded animation is meant to be. |

Current state (2026-09-29): 302 entries: 247 `approved`, 43 `reviewing`, 7 `pending`, 4 `rejected`, 1 `needed`.

| Category | Entries |
| --- | --- |
| `audio/*` | 107 (weapons 43, footsteps 21, zombie 10, player 6, foley 6, city 5, ui 5, world 4, unused 4, music 2, range 1) |
| `texture/*` | 56 (pbr 24, world 16, surface 15, props 1) |
| `animation/*` | 39 (zombie_sf 22, zombie 7, player 5, weapon 5) |
| `zombie/*` | 53 (walker2 36, mesh 7, meshid 7, sketchfab 3) |
| `viewmodel/*` | 28 (arms 14, rifle 10, fps 4) |
| `mesh/*` | 19 (world 16, props 3) |

The binaries themselves are not tracked. `.gitignore` excludes `assets/textures/*.jpg`, `assets/textures/*.png` and `assets/audio/**/*.ogg|mp3|wav`, so the repository carries only `manifest.json`, the generated `LICENSES.md` and the generated `AssetIds.luau`. A fresh clone can build and run the game (every asset resolves from its uploaded id) but re-uploading requires re-downloading the source files.

## Upload: `scripts/upload_assets.py`

Uploads every manifest entry that has no `assetId` yet.

```
python3 scripts/upload_assets.py [--dry-run] [--only PREFIX]
```

- **Auth.** Reads an Open Cloud API key with asset read+write scope from `.opencloud.key` at the repo root. That file is git-ignored and the script exits immediately if it is missing. The owning account is hardcoded as `USER_ID = "3783240909"`.
- **Selection.** Skips entries that already have an `assetId`, entries whose `file` is missing on disk (printed as `skip <key>: file missing`), and entries whose extension maps to no asset type. `--only PREFIX` filters by key prefix, e.g. `--only audio/weapons`.
- **Asset type.** Inferred from the extension: `.ogg/.mp3/.wav` → `Audio`, `.png/.jpg/.jpeg` → `Image`, `.glb` → `Model` (meshes and skinned rigs), otherwise `Animation` if the key starts with `animation/` (`.rbxmx` / `.rbxm` KeyframeSequences). Anything else is skipped.
- **Upload.** A `curl` subprocess POSTs multipart form data to `https://apis.roblox.com/assets/v1/assets` with `x-api-key`, a `request` part holding the JSON body (`assetType`, `displayName`, description `"Task Force Z asset"`, `creationContext.creator.userId`) and a `fileContent` part with an explicit MIME type. The display name is derived from the key: `tfz-` plus the key with `/` and `_` replaced by `-`, so `audio/weapons/shot_pistol` uploads as `tfz-audio-weapons-shot-pistol`.
- **Moderation poll.** The POST returns an `operationId`; the script polls `https://apis.roblox.com/assets/v1/operations/<id>` up to 30 times with a 5 second delay (150 seconds per asset worst case) until `done` is set, then reads `response.assetId` and `response.moderationResult.moderationState`.
- **Write-back.** `assetId` and the lowercased state are written into the entry and the whole manifest is saved after *every* successful asset, so an interrupted or rate-limited run is resumable: rerunning picks up exactly where it stopped, because entries that already have an id are skipped.
- **Exit code.** Non-zero if any entry failed, which is what makes it usable from a script.

`--dry-run` prints what would upload (`would upload <key> (<type>) from <path>`) and exits without touching the network or the key file.

Two consequences worth knowing:

1. Entries whose file is not on disk are reported as `file missing` on every run and stay at id `0`. Today that is the two player strafe loops and the five `animation/weapon/*` slots, which no code reads any more (the viewmodel clips are baked into Luau). The game runs anyway; see the degradation rule below.
2. Moderation can reject an asset after it has been assigned an id. Four entries are `rejected` today (`audio/city/siren_police`, `audio/unused/siren_police_rejected`, `audio/weapons/shell_03`, `audio/range/gong`); the sync step is what neutralises them, and `refresh_status.py` is what finds them.

## Moderation refresh: `scripts/refresh_status.py`

Roblox moderates uploads asynchronously: an asset that returned `Reviewing` at upload time can later become `Approved` or `Rejected`, and a rejected id still in `AssetIds` fails at runtime with "Asset is not approved for the requester".

```
python3 scripts/refresh_status.py [--dry-run] [--only PREFIX]
```

For every entry with an id it asks Open Cloud (`GET https://apis.roblox.com/assets/v1/assets/<id>`) for the current `moderationState`, rewrites `status`, and lists the keys that came back rejected. The full order after adding assets is therefore:

```
upload_assets.py --only <prefix>  ->  (wait for moderation)  ->  refresh_status.py  ->  sync_configs.py  ->  sync_needed.py
```

`scripts/sync_needed.py [--check]` regenerates `assets/NEEDED.md`, the list of empty slots (id `0` or rejected) with where each one is consumed and what to look for.

## Sync: `scripts/sync_configs.py`

Regenerates both derived files from the manifest.

```
python3 scripts/sync_configs.py [--check]
```

**`src/shared/config/AssetIds.luau`.** Keys are split on `/` and folded into a nested table, all levels sorted alphabetically, emitted with a "Generated by scripts/sync_configs.py from assets/manifest.json. Do not edit by hand." header and closed with `return table.freeze(AssetIds)`. The id written is `entry.assetId or 0`, **forced to `0` when `status == "rejected"`**. Note that `reviewing` is *not* zeroed: an asset still in review keeps its id and starts working the moment moderation clears, with no code change.

**`assets/LICENSES.md`.** A single sorted Markdown table of asset key, licence, source link, asset id and status, plus the note that entries marked `Original work (project owner)` were made for this project. It is the attribution document, so it must be regenerated whenever a licence or source changes, not only when ids change.

**`--check`** compares the rendered output against the files on disk and exits `1` with `generated files are out of date, run scripts/sync_configs.py` if either differs, without writing. This is the CI/pre-commit form. Without `--check` the script writes only files whose content actually changed and prints a one-line summary (`synced 302 entries (298 with asset ids)` on 2026-09-29): that count includes rejected entries, since it counts a present `assetId`, not the status.

## How configs consume ids

`AssetIds.luau` is never required directly by gameplay code except where a whole branch is needed. Each domain config maps raw ids to named constants, and that is what systems require.

| Config | AssetIds branch | Notes |
| --- | --- | --- |
| `TexturesConfig.luau` | `texture.surface.*`, `texture.pbr.*` | Role aliases: `ASPHALT`, `CONCRETE_NORMAL`, `SAND_ROUGHNESS`, `FENCE_CHAINLINK`, ... |
| `AudioConfig.luau` | `audio.music.*`, `audio.city.*`, `audio.player.death_scream`, `audio.zombie.growl_01` | Music, sirens, helicopter loop, SoundGroup names and rolloff distances |
| `SfxConfig.luau` | `audio.foley.*`, `audio.player.*`, `audio.zombie.*`, `audio.world.*`, `audio.ui.*` | The large SFX tuning table; id lists like `FOLEY_GEAR_IDS`, `ZOMBIE_BITE_IDS` |
| `FootstepConfig.luau` | `audio.footsteps.*` | Three-variant sets per `Enum.Material`, concrete as fallback |
| `BreathingConfig.luau` | `audio.player.breath_calm/heavy/gasp` | Exertion-blended breath layers |
| `AnimationsConfig.luau` | `animation.player.*` | Run (live), strafe left and right (pending); `DeathService` reads `animation.player.death` directly |
| `src/server/systems/ZombieAnimator.luau` | `animation.zombie.*` | Requires `AssetIds` directly for the seven Quaternius clips of the fallback rigs |
| `ZombieSkins.luau` | `animation.zombie_sf.*`, `zombie.sketchfab.*.rig` | Skinned zombie rigs and their clips with ground speeds; a skin is used only when its rig id and idle clip are live |
| `src/server/systems/ViewmodelPacks.luau` | `viewmodel.fps.*.rig` | First-person pack rigs, loaded with `InsertService` |
| `WorldMeshConfig.luau` | `mesh.world.*`, `texture.world.*` | Cube 3D world props |
| `src/client/systems/WeaponSfx.luau` | `audio.weapons.*` | Requires `AssetIds` directly and looks the branch up by string key |

The last row is the one deliberate exception to the alias rule: `WeaponsConfig` stores sound *names* (`shotSound = "shot_pistol"`, `closeSounds = { "close_pistol", "close_pistol_02", "close_pistol_03" }`) and `WeaponSfx` resolves them, and its phase keys (`rifle_mag_in`, `pistol_slide_release`, `casing_brass_01`, ...), against `AssetIds.audio.weapons` at runtime, falling back to generic keys (`mag_in`, `bolt`, `shell_01`). Adding a weapon class or a better recording is a config edit plus a manifest entry with a matching key, with no new alias constant.

**The degradation rule.** Every consumer guards on `id > 0` (or `assetId <= 0`) and no-ops instead of erroring. `TextureUtil.applyFace` returns early, `ZombieAnimator.loadTrack` returns `nil` and the animator silently skips that track, `WeaponSfx.playTail` returns without a tail. This is why the game stays playable while any asset is missing or still in review, and why an asset moving from `reviewing` to `approved` needs no code change at all.

## MaterialVariant registration

`src/shared/util/MaterialUtil.luau` turns the PBR texture triples into real Roblox materials. `MaterialUtil.register()` runs once at boot from `src/server/init.server.luau` under `runStage("Materials", ...)`.

Eleven sets are defined, each a colour + normal + roughness (+ optional metalness) set over a base material. Six of them carry `override = true`: `register()` calls `MaterialService:SetBaseMaterialOverride(baseMaterial, name)` for those, so every part in the world that uses `Enum.Material.Metal`, `CorrodedMetal`, `Wood`, `WoodPlanks`, `Grass` or `Fabric` renders through the PBR set without any per-part `apply` call (`DiamondPlate` is untouched). The zombie rig relies on the Fabric override: its parts carry no `Texture` at all, so `part.Color` tints the cloth. The override replicates to clients (verified with `GetBaseMaterialOverride` on the client in a playtest, 2026-08-29).

| Variant | Base material | Textures | StudsPerTile | Override |
| --- | --- | --- | --- | --- |
| `TFZ_Asphalt` | `Enum.Material.Asphalt` | ambientCG Asphalt033 | 12 | no |
| `TFZ_Concrete` | `Enum.Material.Concrete` | ambientCG Concrete034 | 6 | no |
| `TFZ_Sand` | `Enum.Material.Sand` | ambientCG Ground080 | 8 | no |
| `TFZ_Metal` | `Enum.Material.Metal` | ambientCG Metal038 (galvanised scratched steel, neutral so `part.Color` tints it) | 6 | yes |
| `TFZ_Rust` | `Enum.Material.CorrodedMetal` | ambientCG Metal041C (rusted iron with bare patches) | 6 | yes |
| `TFZ_MetalPlates` | `Enum.Material.Metal` | ambientCG MetalPlates006 (dark scale-armour plates, decorative; per-part only) | 4 | no |
| `TFZ_DarkRust` | `Enum.Material.CorrodedMetal` | ambientCG Metal063 (dark oxidised steel; per-part only) | 6 | no |
| `TFZ_Wood` | `Enum.Material.Wood` | ambientCG WoodFloor064 | 6 | yes |
| `TFZ_WoodPlanks` | `Enum.Material.WoodPlanks` | ambientCG WoodFloor064 | 8 | yes |
| `TFZ_Grass` | `Enum.Material.Grass` | ambientCG Grass005 | 6 | yes |
| `TFZ_Fabric` | `Enum.Material.Fabric` | ambientCG Fabric061 | 3 | yes |

All normal maps are ambientCG `NormalGL` (OpenGL, Y+), which is what Roblox expects; the Asphalt033 normal in the repo is byte-identical to that file, so the convention is settled. `register()` skips a set already present in `MaterialService` and records what it registered. `MaterialUtil.apply(part, setName)` then sets `part.Material` to the base material and `part.MaterialVariant` to the name, returning `false` if the variant was never registered: callers use that return value as their fallback branch:

- `src/server/systems/ChunkFactory.luau` falls back to a plain tiled `Texture` for the lane floor.
- `src/server/systems/HangarBuilder.luau` (hangar floor, `TFZ_Concrete`), `src/server/systems/DesertBase.luau` (ground `TFZ_Sand`, road `TFZ_Asphalt`).

**Why `MaterialVariant` and not `SurfaceAppearance`:** `SurfaceAppearance` only applies to `MeshPart`. The entire world here is built from `Instance.new("Part")` (lane floors, hangar walls, desert ground) so `SurfaceAppearance` would attach to nothing. `MaterialVariant` is registered globally in `MaterialService` and selected per-part via the `MaterialVariant` string property on any `BasePart`, which is the only route to normal and roughness maps on primitives. The cost is that variants are a global registry keyed by name, hence the `registered` guard and the `MaterialUtil.ENABLED` kill switch.

For the non-PBR case `src/shared/util/TextureUtil.luau` attaches plain `Texture` instances with matched `StudsPerTileU/V`, per face (`applyFace`), on the four sides (`applySides`) or all six (`applyAll`), and returns early on `textureId <= 0`. Tiling density is chosen per surface rather than left at the default so texels stay square and do not smear when a part is scaled.

## Licensing sources

Only sources whose licence permits redistribution inside a Roblox experience are used, and each is recorded per entry so `LICENSES.md` can reproduce it.

| Source | Licence | Used for |
| --- | --- | --- |
| ambientCG | CC0 | All 39 surface and PBR textures: asphalt, concrete, grass, ground, bricks, metal plates, corrugated steel, tiles, wood floor, rust, fabric, chainlink fence, sand, each with its normal and roughness maps |
| Kenney | CC0 | Impact and interface sound packs: gear foley, landings, cloth whoosh, magazine in/out, bolt, shells (the generic weapon fallbacks), all five UI sounds; the Kenney dry fire was replaced by a Free Firearm Sound Library take |
| OpenGameArt | CC0 / CC BY 3.0 | Menu and mission music, death scream, zombie noises, facility siren, wind, distant explosion, hangar roomtone, radio call, and the gunshot pack |
| Wikimedia Commons | Public domain | Breathing loops, heartbeat, civil-defence siren, helicopter, fire crackle, gong, one zombie growl |
| The Free Firearm Sound Library (Ben Jaszczak; GitHub mirror by buddingmonkey) | CC0 1.0 | 38 weapon sounds (2026-09-29): close shots and class tails (v6, from the Prepared SFX Library), the sub layers, open tail, dry fire, low-ammo and last-round cues, reload and handling foley, draw and holster |
| Sketchfab | CC BY 4.0 | Skinned zombies by pxltiger, LxNazarov and stasbelyk13 with their 22 clips; first-person packs by DuqueCD7 (Pistol, AK-47, Saps-12) and 1Matzh (UZI 2026 remake, which uses "UZI" by Gintoki1234 and "Division Agent (Rigged)" by Blue-Spirit) |
| Roblox Cube 3D / generative AI | Owned by the project owner | World props and the walker2 zombie meshes (Cube 3D), the carbine viewmodel meshes (generative AI output) |
| Mixamo (Adobe) | Royalty-free for games | The "Swat Guy" first-person arms (fallback rig) |

Licence totals across the manifest (2026-09-29, evening): CC0 204, CC BY 4.0 83, Roblox Cube 3D generation 72, CC BY 3.0 20 (congusbongus footsteps 15, Vincent Sevedge 4, GreenFireSound 1), `Original work (project owner)` 17, Mixamo 14, Public domain 12, Roblox generative AI output 10, sole proprietor 5 (the unused `animation/weapon/*` slots), and one `needed` slot with no licence yet. Every CC BY author has to be credited in the shipped game as well; `assets/LICENSES.md` notes that those credits belong in the settings panel before release.

**Audio must be real licensed files, never generated.** Synthesised audio reads as thin and tonally wrong next to recorded material, and it makes the licence column meaningless. No entry carries `source: "generated"` any more (2026-09-29): the footsteps are congusbongus and Fantozzi recordings, the police siren slot is rejected and waiting for a stylised replacement, and the ambulance siren is `needed` because every candidate found was CC BY-SA.

## Gunshot audio provenance

Weapon audio comes from two generations of sources.

**The Free Firearm Sound Library** (Ben Jaszczak, CC0 1.0, taken from the GitHub mirror by buddingmonkey): 32 entries added 2026-09-29, each cut from a named master track with the time window recorded in `source`. The manifest fragments are kept in `tools/audio_fragments/ffsl_weapons.json`. Processing for every file: dual-mono take to mono, 90 Hz high-pass, trimmed to at most 3 ms before the first transient, cosine fade-out, resampled to 44.1 kHz, loudness-matched to -28 LUFS (100 ms K-weighted max) under a -6 dBFS peak ceiling, OGG Vorbis q6.

| Keys | Recorded weapon | Role |
| --- | --- | --- |
| `close_pistol`, `close_pistol_02`, `close_pistol_03` | Walther PPQ | Local shooter's shot, three takes picked without repeats |
| `close_smg`, `close_smg_02`, `close_smg_03` | Carl Gustav M45 | Local shooter's shot |
| `close_rifle`, `close_rifle_02`, `close_rifle_03` | AK-47 | Local shooter's shot |
| `close_shotgun`, `close_shotgun_02`, `close_shotgun_03` | Benelli Nova | Local shooter's shot |
| `tail_open` | AK-47 | Outdoor reflection tail |
| `dryfire`, `low_ammo_click` | AK-47 | Empty trigger, low-ammo spring layer |
| `last_round` | Walther PPQ | Last-round clack |
| `pistol_mag_out`, `pistol_mag_in`, `pistol_slide_back`, `pistol_slide_release` | Walther PPQ | Reload markers |
| `rifle_mag_out`, `rifle_mag_in`, `rifle_bolt_back`, `rifle_bolt_forward` | AK-47 | Reload markers |
| `shotgun_pump_back`, `shotgun_pump_forward`, `shotgun_shell_in` | Benelli Nova | Pump and shell markers |
| `smg_mag_out`, `smg_mag_in`, `smg_bolt` | Carl Gustav M45 | Reload markers |
| `weapon_draw`, `weapon_holster` | Carl Gustav M45 | Swap foley |

All 32 are `reviewing`, so they carry ids and start playing without a code change once moderation clears; `refresh_status.py` records the outcome.

**Older layers.** `shot_pistol`, `shot_smg`, `shot_rifle`, `shot_shotgun` (the fallback report, also used for other players' distant shots) and `tail_interior` come from the OpenGameArt gunshot pack (CC BY 3.0, Vincent Sevedge). `mag_out`, `mag_in`, `bolt`, `shell_01` and `shell_02` are Kenney CC0 and serve as the generic fallbacks for phase sounds and casing landings; `shell_03` was rejected and is zeroed by the sync step. Keys the code already asks for but the manifest does not have yet: `casing_brass_01..03`, `casing_shotgun_01..02` and `mag_drop`.

`src/client/systems/WeaponSfx.luau` picks one of the three `close_*` takes for the local player and falls back to the `shot_*` id when none has an id; `playDistantShot` uses the same choice on a temporary 3D anchor part. The tail choice is driven by geometry, not by biome: the module scans for `BasePart`s carrying an `AcousticSpace` attribute (set by `HangarBuilder` and `DesertBase` over the hangar interior and its canopy), and if the local root is inside an `AcousticSpace == "Interior"` zone it plays `tail_interior` and pushes the shared `ReverbSoundEffect` to `DecayTime` 1.5 / `WetLevel` -8, otherwise `tail_open` at 0.4 / -18. Tails are rate-limited to one per 0.55 s so sustained automatic fire does not stack them. See [[Gameplay Systems]] for the voice pools, the marker-driven foley and the casing landings.

## Adding a new asset

1. Obtain a real licensed file (CC0, public domain, or an attribution licence whose terms you can satisfy). Do not generate audio.
2. Drop it under `assets/audio/<group>/` or `assets/textures/` with a name matching the manifest key you intend to use.
3. Add the entry to `assets/manifest.json`: key, `source` URL, `license`, `file`, `assetId: 0`, `status: "pending"`.
4. `python3 scripts/upload_assets.py --dry-run --only <prefix>` and confirm it lists the new entry.
5. `python3 scripts/upload_assets.py --only <prefix>`: it uploads, polls moderation and writes back `assetId` and `status`.
6. `python3 scripts/sync_configs.py` to regenerate `AssetIds.luau` and `LICENSES.md`. Never hand-edit either file.
7. Add a named alias in the relevant config (`TexturesConfig`, `SfxConfig`, `AudioConfig`, `FootstepConfig`, ...), except for weapon sounds, which are resolved by string key from `WeaponsConfig`.
8. If it is a PBR set, add it to `MaterialUtil.sets` with a `TFZ_` name and a sensible `StudsPerTile`, mirror the block under `MaterialService` in `default.project.json`, and give every call site a non-variant fallback (or mark it `override = true` when it should replace a base material everywhere). Studio bakes each variant's maps into a TexturePack on save and logs `Failed to upload TexturePack ... HTTP StatusCode: -1` when its network is flaky; re-set `ColorMap` to retry. Freshly uploaded image ids can take a few minutes before Studio can fetch them; `ContentProvider:PreloadAsync` reports `Success` once they are live.
9. Consume it with an `id > 0` guard so the game still runs while moderation is pending.
10. Run the gate: `selene src/`, `python3 tools/validate_api.py`, `rojo build`. Commit the manifest, `LICENSES.md`, `AssetIds.luau` and your config change: the binary itself stays untracked.

If an asset comes back `rejected`, leave the entry in place with the rejection recorded in `note`, move the file under `assets/audio/unused/` if it is being replaced, and add a fresh entry for the replacement. The sync step already forces rejected ids to `0`, so no consumer needs to know.

---

See also: [[Overview]], [[Architecture]], [[Gameplay Systems]], [[Performance]], [[Decisions]].

## World props from Cube 3D (2026-09-28)

Cube 3D generation in Studio publishes the result under the owner's account, so the MeshPart it inserts already carries a permanent `MeshId` and `TextureID`. That skips the localhost export and Open Cloud upload the viewmodel flow in `tools/cube3d/README.md` needs. Steps:

1. `generate_mesh` with `segmentation: none`, a size close to the real object, a `maxTriangles` cap, and the house prompt suffix "realistic game asset, flat neutral albedo texture without baked lighting, no floating parts".
2. Look at it in Edit next to the others (screenshot). Re-roll anything off-style.
3. Read `MeshId`, `TextureID` and the triangle count (`AssetService:CreateEditableMeshAsync(...):GetFaces()`), add `mesh/world/<name>` (with `prompt`, `triangles`, `textureAssetId`) and `texture/world/<name>` to the manifest, run `python3 scripts/sync_configs.py`.
4. Add the entry and its group to `src/shared/config/WorldMeshConfig.luau`. Nothing else changes: `WorldMeshes` loads every configured entry at server start.

Generation is rate-limited: six parallel jobs gave one "Too Many Requests" failure, three or four at a time is safe. The generated source models are not kept in the place; the ids are the asset.

## Animation clips from CC0 libraries

The 2026-09-07 policy revision judges results instead of methods, and the first thing it unlocked was filling the animation slots without waiting for Mixamo downloads. `tools/animation_pipeline/glb_to_keyframes.py` runs headless in Blender 5.2, imports a glTF library, samples a named action at 30 fps and writes a Roblox `KeyframeSequence` `.rbxmx` per slot. Retargeting is a change of basis, not authoring: every R15 joint's pose is the child bone's world rotation relative to the parent bone's, taken against the rest pose, then converted from Blender Z-up to Roblox Y-up with `X -> -X, Y -> Z, Z -> Y` (the mirror that also maps Blender's -Y facing onto Roblox's -Z). Only `LowerTorso` carries translation (pelvis travel, scaled at 3.2 studs per metre); loops keep the vertical bob and drop horizontal drift, one-shots keep everything so a death clip can put the body on the ground. Bone names are resolved from candidate lists, so the Unreal mannequin set (UAL2), Rigify `DEF-*` (UAL1) and Mixamo `mixamorig:*` all map onto the same 15 parts.

Source: Quaternius Universal Animation Library 1 and 2, CC0 1.0, from OpenGameArt (`universal_animation_librarystandard.zip`, `universal_animation_library_2standard.zip`). Nine slots were filled from them (see the table in `tools/animation_pipeline/README.md`); the two strafe loops stay open because the free tiers carry no strafes. `default.project.json` mirrors `assets/animation` into `ReplicatedStorage.AnimationClips`, so any clip can be checked in Edit mode before upload by registering the `KeyframeSequence` with `KeyframeSequenceProvider` and stepping an `Animator`; that is how the zombie shuffle, the reduced-rig fit and the supine end pose of `Death01` were verified by screenshot before the Open Cloud upload.

## Skinned zombies from Sketchfab: `tools/zombie_pack` (2026-09-29)

The three zombies are CC BY 4.0 Sketchfab characters that ship with their own clips: "Zombie" by pxltiger, "Zombie Hazmat" by LxNazarov and "ZOMBIE. Animation test for the game" by stasbelyk13. No Blender is involved.

1. Strip the glb's animations with `tools/fps_pack/strip_glb.py`, wrapping the scene in a UnitScale node so the character stands about 5.5 studs (Walker 2.76, Hazmat 3.05, Ghoul 2.04), and upload it as a Model asset (`zombie/sketchfab/<skin>/rig`).
2. In Studio, read the Bone tree Roblox built on import (names, parents, local CFrames) into `tools/zombie_pack/roblox_bones.json`. The importer renames bones (`Base HumanHead_09`, `mixamorig:Head_06`, `Bone.005_3`), and `ZombieSkins` uses those names.
3. `python3 tools/zombie_pack/build_zombie_anims.py [--src ~/Downloads/zombie_packs] [--only Walker]` fits the file's bind pose onto the imported bones with one similarity transform (residual 0 on all three packs), maps the file's node space onto the rig (the glTF 180-degree turn about Y, the upload's UnitScale, the holder part's offset), samples every clip at 20 fps and writes one `KeyframeSequence` `.rbxmx` per slot to `assets/animation/zombie_sf/<skin>/`, with Poses named after the instance tree (`HumanoidRootPart > Rig > bones`; `ZombieRigs` renames the Bone holder to `Rig`).
4. Loops lose their horizontal root travel. The travel per second, or the planted foot's speed for in-place clips, is written to `assets/animation/zombie_sf/clips.json` as the clip's ground speed, and those numbers are copied into `ZombieSkins` so playback speed keeps the feet planted.
5. Upload the clips as Animation assets (`animation/zombie_sf/<skin>/<slot>`: Walker 7, Hazmat 4, Ghoul 11), run `refresh_status.py` and `sync_configs.py`.

One fix was needed after the bake: every Ghoul clip holds `Bone.009` 3.08 studs below its bind pose (the same constant in all 11 clips), so the skin carries an `offset` of (0, 3.077, -0.2) that `ZombieFactory` applies when placing the rig.

## First-person weapon packs: `tools/fps_pack` (2026-09-29)

Each weapon class uses a Sketchfab pack (CC BY 4.0) that holds arms, weapon and clips in one glb: DuqueCD7's Pistol, AK-47 and Saps-12 packs and 1Matzh's UZI 2026 remake. The rig goes through the asset pipeline; the clips do not. Steps, also in `tools/fps_pack/README.md`:

1. `gltf_anim.py report <scene>` lists meshes, triangle counts, materials, the joint tree and every clip with its length.
2. `strip_glb.py in.glb out.glb [--mesh REGEX ...] [--root-scale S] [--skin-fix JSON]` drops the animations and unwanted meshes and wraps the scene in a UnitScale node so every rig matches the pistol pack's arm size (AK 2.961, Saps-12 1.2218, Uzi 3.0). The result is uploaded as a Model asset (`viewmodel/fps/<class>/rig`).
3. `python3 tools/fps_pack/build_clips.py [--src ~/Downloads/fps_packs] [--only CLASS]` runs `gltf_anim.py bake` (every clip sampled, 30 fps by default, as per-joint transforms relative to rest) and `emit_luau.py --scale` (key reduction at 0.002 stud and 0.25 degree, int16 packing, one base64 string per joint track) into `src/shared/viewmodel_clips/<Class>Clips.luau`. The scale must equal the UnitScale of the uploaded rig.
4. Cut points and phase markers go into `ViewmodelPackConfig` by hand, measured from the magazine and bolt bones' motion relative to the weapon body.

**Broken shared skins.** Some Sketchfab exports share one skin between several meshes but keep the inverse bind matrices of only one of them. The Uzi pack's belong to its Background plane (scale about 710 x 358 x 372), and its arm and gun vertices are stored in a mirrored, scaled space, so on import the bones came in about 1000 times smaller than the mesh. `tools/fps_pack/skin_fixes/smg.json` holds the vertex transform and an inverse-bind correction solved on 2026-09-29 from the pack's source FBX (cluster Transform / TransformLink, vertices matched to the glb within 2e-5). `strip_glb.py --skin-fix` writes the repaired rig, `build_clips.py` bakes with the same file (`gltf_anim.py bake --skin-fix`), and the repaired rig is asset 118961607883385. teenjust500's 870 pump pack has the same broken skin and no idle or walk clips, so it was not used.

**Quaternion normalisation.** The baked quaternions are rounded to 5 decimals, and unnormalised they differed from themselves by about 0.3 degrees, which defeated the 0.25-degree key reduction. `emit_luau.py` now normalises every quaternion before reducing.

**Gunshots v6 (2026-09-29).** `tools/audio_build/build_shots_v6.py "<FFSL>/Prepared SFX Library" <out dir>` cuts single shots from the Prepared SFX Library files (AK-47 `C_28P`, Walther PPQ `X_39P`, Benelli Nova `O_21P` and `O_17P`, Carl Gustav M45 `G_31P`) into `close_<class>[_02|_03]` (blast and mechanism, 0.13 s) and `tail_open_<class>` (the reflection and decay, padded with 0.11 s of silence). The two microphones are aligned (1..3.4 ms apart) and matched in RMS so the blast stays mono-compatible; 96 kHz becomes 48 kHz stereo OGG Vorbis q6, with a 30 Hz high-pass and the close part peaking at -1 dBFS (the tail keeps the same gain). The manifest fragment is `tools/audio_fragments/gunshots_v6.json`; the replaced v5 ids stay in `previousAssetId`.
