# Task Force Z — project overview for a fresh Claude Code session

Written 2026-08-21 as a handoff briefing. The repo zip you received is the source of
truth for code; this file summarises state, contracts and landmines that are not
obvious from reading the tree.

## What the game is

Co-op endless runner (1–3 players) in a zombie apocalypse. Roblox. First-person only.
Design references: CoD MW2019 (presentation, weapon feel), Into the Dead 1/2 (run core,
biome art), CoD Zombies (kill economy, perks, upgrade stations), Sable Digital's TTK
Testing (viewmodel quality benchmark).

## Stack and layout

Rojo (`default.project.json`) + Wally + Selene, Luau `--!strict` everywhere except
tools. Layout:

- `src/shared/config/` — data-only config modules, one per system
- `src/server/systems/` — authoritative services, `init()` from `init.server.luau` behind `runStage`
- `src/client/systems|controllers|ui/` — presentation
- `assets/` — manifest-driven asset pipeline (see below)
- `wiki/project-zprun/` — Obsidian vault, update after significant changes
- `tools/cube3d/` — Cube 3D weapon generator + extract/import/dump Studio scripts (README inside)

Validation before any commit: `selene src/`, `python3 tools/validate_api.py`,
`rojo build`. All three currently pass clean.

## Hard rules (do not violate)

- Server is authoritative for ammo, damage, credits, purchase grants. Every remote validates arguments.
- No pay-to-win: only cosmetics and post-death Continue are sold for Robux.
- **Never author artistic keyframe animation in code. Never synthesise audio.** A missing asset stays `assetId = 0` (consumers degrade to silence/no-op) and gets a row in `assets/NEEDED.md`. Never invent an assetId.
- Unreal Fab and Unity Asset Store packs are forbidden, even free ones.
- Every asset goes `assets/manifest.json` → `scripts/upload_assets.py` → `scripts/sync_configs.py`, and is listed in `assets/LICENSES.md`.
- Commits are authored by the project owner only — no co-author trailers, no AI mentions.

## Weapon/viewmodel system — current state

Four classes in `WeaponsConfig`: Pistol, SMG, Shotgun, Rifle. Player spawns with
Rifle (slot 1) + Pistol (slot 2); Q swaps.

The first-person rig is built at runtime by `src/client/systems/ViewmodelBuilder.luau`
and posed every RenderStepped by `Viewmodel.luau` (springs for recoil/slide/pump/mag +
authored pose sequences from `src/shared/config/PoseLibrary.luau` driven by
`AnimationSequencer`). Two build paths:

1. **Mesh path** — `buildMeshWeapon` clones `ReplicatedStorage.ViewModels.<class>`
   (mounted by Rojo from `assets/viewmodels/<name>.model.json`). Parts bind to bones
   **by exact name** via `MESH_BONES`:
   `Main→weaponRoot` (required, PrimaryPart), `Slide→slide`, `Pump→pump`,
   `Magazine`, `Barrel`, `Grip`. NOTE: the reciprocating part is named **Slide**
   for pistol/SMG/rifle and **Pump** for the shotgun — not "Bolt". Unknown names
   weld statically.
   Marker parts read by name: `Muzzle` (flash/tracer origin), `CasingEject`,
   `HandRMount`/`HandLMount` (hand positions; orientation stays in code; a
   template without them falls back to pistol-shaped constants; on a shotgun the
   left mount is read relative to `Pump` so the hand rides the stroke).
   `ViewmodelConfig.SCALE = 0.72` is applied to mesh sizes and rest offsets at build
   time; author templates at full size.
   Weapon convention: **muzzle faces −Z** in the template.
2. **Procedural fallback** — grey primitive boxes, used by any class without a mounted
   template. SMG and Shotgun still use this.

Status: **Pistol and Rifle have real mesh sets.** Pistol = free Glock kit meshes.
Rifle = Cube 3D generated (2026-08-14…18), see `assets/viewmodels/rifle.rig.txt` for
the full id table. Verified in-game: mesh renders, slide Motor6D travels on
fire/reload, muzzle flash spawns from the `Muzzle` marker, reload works, rifle is
scaled ×1.7 relative to Cube output so it reads bigger than the pistol.

Pipeline for a new mesh set:
`assets/viewmodels/<name>.rig.txt` (PART/JOINT pipe-format dump, see pistol/rifle
examples) → `python3 scripts/build_viewmodel.py <name>` → mount in
`default.project.json` under `ReplicatedStorage.ViewModels.<Class>` (key must equal
the WeaponsConfig class exactly). Joints are deliberately NOT in the model.json —
runtime rebuilds them (Rojo JSON cannot express Refs; also `MeshPart.MeshId` is not
script-writable in any available context, which is why meshes must arrive as mounted
instances with ids baked in).

## Mesh upload landmines (hard-won, do not rediscover)

- `AssetService:CreateAssetAsync` **cannot upload meshes** — the Studio binary
  literally contains "CreateAssetAsync does not support Mesh upload yet". It is also
  gated behind a beta + local-plugin context. Dead end; do not retry.
- Working path is now scripted end to end, see `tools/cube3d/README.md`:
  Studio `ExtractMeshes.server.luau` → `scripts/mesh_pipeline.py serve|convert` →
  `scripts/upload_assets.py --only viewmodel/<name>/` (GLB as assetType `Model`,
  needs `.opencloud.key`, **git-ignored — the zip will NOT contain it**) → Studio
  `ImportMeshes.server.luau` (`InsertService:LoadAsset`, reads real mesh ids) →
  `scripts/mesh_pipeline.py finalize` → Studio `DumpRig.server.luau`.
- Roblox's glTF importer rotates meshes 180° about Y (glTF +Z-forward vs Roblox
  −Z-look). Upload sources already oriented muzzle−Z; do not bake compensating
  rotations.
- Cube 3D (`GenerationService:GenerateModelAsync`, generator at
  `tools/cube3d/GenerateWeapon.server.luau`): group→part mapping for small parts is a
  dice roll ("Bolt" produced gas tube / muzzle brake / front sight across rolls; 1 in
  5 was a real charging handle). Cube outputs albedo only in `TextureContent` — no
  SurfaceAppearance/PBR maps. Groups arrive as container Models named like the group
  with a `<Group>_geom` MeshPart inside; recursive FindFirstChild on the group name
  hits the container first.
- Welds on anchored parts under Camera silently do nothing (recorded in wiki
  Decisions) — the rig stores rest offsets and writes CFrames per frame instead.

## Animations — the open blocker

- `src/shared/config/AnimationsConfig.luau` is all `assetId = 0` placeholders for
  third-person player and zombie clips. The Gun Viewmodel Kit's published animation
  ids do NOT load (Roblox animations are only usable by the uploading account) — the
  ids kept in `ViewmodelRigConfig.luau` are documentation only.
- The viewmodel needs no clips — it is fully procedural (springs + PoseLibrary +
  AnimationSequencer with phases that also drive audio, e.g. BoltBack/BoltForward).
- Third-person character does not animate its weapon carry yet.
- Policy forbids code-authored keyframes, so the fix is a real animation source:
  Mixamo or CC0 mocap → Blender retarget onto the rig → export KeyframeSequence rbxm
  → upload via Open Cloud (`upload_assets.py` already handles assetType `Animation`
  for `animation/` manifest keys, uploading under user 3783240909) → fill
  AnimationsConfig ids. Retarget quality must be checked by eye in a playtest.

## Asset pipeline details

`assets/manifest.json`: key → `{source, license, file, assetId, status}`. Entries with
`assetId` already set are skipped by the uploader; entries without are uploaded from
`file` and polled through moderation. Types supported by `upload_assets.py` today:
Audio (.ogg/.mp3/.wav), Image (.png/.jpg), Animation (`animation/` prefix). Meshes go
through the GLB/Open Cloud path above (extend the script if you productise it).
`assets/LICENSES.md` mirrors the manifest as a human table. `assets/NEEDED.md` tracks
missing/rejected slots — currently ~10 blockers (mostly audio) plus rifle PBR maps as
polish.

## Known gaps / next work candidates

- SMG and Shotgun viewmodel mesh sets (procedural boxes today). Same pipeline as the
  rifle (`tools/cube3d/README.md`); the shotgun names its moving part `Pump`.
- Rifle PBR maps (normal/roughness/metalness) — NEEDED.md polish row; sources for
  re-render are the GLBs in `assets/viewmodels/source/rifle/`.
- Third-person + zombie animation clips (see above).
- World PBR: `TFZ_Metal`/`TFZ_Rust` now override `Enum.Material.Metal`/`CorrodedMetal`
  globally via `MaterialService:SetBaseMaterialOverride` in `MaterialUtil.register()`;
  WoodPlanks (21 uses), Grass (13), Fabric (22) still render as stock materials and have
  only albedos uploaded. Same recipe: ambientCG CC0 pack → `assets/textures/` →
  manifest `texture/surface|pbr/*` → `upload_assets.py` → `MaterialUtil.sets` +
  `default.project.json`.
- `ProductsConfig` dev product/gamepass ids are 0 → Continue is effectively free.
- `MissionGoals` has no HUD surface.
- Some recently uploaded audio may still be in moderation; consumers guard on
  `assetId > 0`.

## Environment notes for the receiving session

- The zip lacks `.opencloud.key` (git-ignored). Without it, no uploads — ask the
  owner. USER_ID for uploads: `3783240909`.
- Live place: "Task Force Z", placeId 73546181882536, universeId 10577883954,
  Team Create enabled. Studio MCP (`.mcp.json`) only works with Studio open on the
  owner's machine with Assistant MCP enabled — a zip-only session has no Studio
  access; code-only work is still fine (selene/validate_api/rojo build all run
  offline).
- Studio currently holds a hand-placed copy of `ReplicatedStorage.ViewModels.Rifle`
  identical to `assets/viewmodels/rifle.model.json`; next `rojo serve` connect takes
  ownership with no visual change. `Workspace.Rifle_VM` and `Workspace.Pistol_VM` are
  authoring reference models, keep them.
- Obsidian wiki (`wiki/project-zprun/`) — `Gameplay Systems.md` §Viewmodel and
  `Progress.md` are current as of the rifle work.
