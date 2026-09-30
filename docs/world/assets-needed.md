# Environment pass — assets still needed

Every slot below is read through `AssetIds` with a missing or zero key meaning "place
nothing", so the run works without them; they only add detail. Candidate sources are CC0 or
CC BY, matching [asset-policy.md](../asset-policy.md): real files with a licence we can show,
uploaded through `assets/manifest.json` → `scripts/upload_assets.py` → `scripts/sync_configs.py`,
listed in `assets/LICENSES.md`. Nothing from Unreal or Unity packs, nothing extracted from
another game.

Decals are alpha PNGs (a colour map with transparency). Sizes: 1024 px for anything under the
feet (cracks, arrows, blood trail), 512 px for marks seen from the kerb.

## Decals (`texture/decal/*`, key in `AssetIds.texture.decal`)

| Key | Used by | What to look for | Candidate sources | Priority |
| --- | --- | --- | --- | --- |
| `road_crack_a` | `DecalsConfig` City and Wasteland lane cards | a long asphalt crack with alpha, no repeating edge | ambientCG "Asphalt Damage Set 001" (CC0) has potholes; a crack variant from the same set or Poly Haven "cracked_concrete" cut to alpha: https://ambientcg.com/view?id=AsphaltDamageSet001, https://polyhaven.com/a/cracked_concrete | blocker for the cracks layer |
| `oil_stain_a` | edge cards under abandoned cars | dark oil pool, soft edge | ambientCG decal sets (CC0): https://ambientcg.com/ (search "stain"); cgbookcase CC0 decals: https://www.cgbookcase.com/textures | polish |
| `scorch_a` | under burned cars, scorch points | black-to-grey burn mark, 2:1 aspect | ambientCG "Burned Ground" style masks or a scorch decal from cgbookcase CC0: https://www.cgbookcase.com/textures; Poly Haven "burned_ground_01" already in the project as `TFZ_GroundBurned` covers the patch until a true decal exists | polish |
| `blood_trail_a` | all biomes, lane and shoulder | a drag trail, long and thin, alpha | OpenGameArt CC0 "Blood Splatters": https://opengameart.org/content/blood-splatters; OpenGameArt "Blood Splatter": https://opengameart.org/content/blood-splatter | blocker for the blood layer (today: tinted parts) |
| `blood_pool_a` | shoulder and edge near barricades | round pool | same OpenGameArt entries | blocker for the blood layer |
| `tyre_marks_a` | City and Wasteland floor `Texture` (60 x 64 studs per tile) | two faint wear lanes across the tile width, dark on transparent | Poly Haven "aerial_asphalt_01" (CC0, "faint tire marks") as a source to mask: https://polyhaven.com/a/aerial_asphalt_01 | polish |
| `lane_arrow_worn` | City lane | worn white arrow | ambientCG "Road Lines 004" (CC0): https://ambientcg.com/view?id=RoadLines004 | polish |
| `crosswalk_worn` | City lane, one per three chunks | zebra stripes with wear | ambientCG "Road Lines" sets (CC0): https://ambientcg.com/view?id=RoadLines004 | polish |
| `manhole_a` | City lane | round cover with alpha | cgbookcase manhole cover (CC0): https://www.cgbookcase.com/textures | polish |

## Meshes (`mesh/props/*`, group in `WorldMeshConfig.groups`)

None are required: every recipe in `DressingConfig` uses the 16 props already in the project.
Two would raise the City read and get a recipe as soon as they exist:

| Key | Group | What to look for | Candidate sources | Priority |
| --- | --- | --- | --- | --- |
| `boarded_window` | `boarded` (new) | a 2 x 3 m panel of planks nailed across a frame, one texture | Poly Haven models (CC0): https://polyhaven.com/models; Sketchfab with the CC0 / CC BY filter: https://sketchfab.com/search?licenses=322a749bcfa841b29dff1e8a1bb74b0b&type=models | polish |
| `sign_quarantine` | `road_sign` | a standing metal sign with a hazard or evacuation panel | Sketchfab CC BY search "quarantine sign"; or the existing `road_sign_stop` with a decal on the panel once `texture/decal/sign_quarantine` exists | polish |

## Not needed

- Building and ruin meshes: the middle band and the ruins use `building_brick`,
  `building_concrete` and `building_townhouse` already in the project.
- Ground and wall materials: the eight variants from 2026-09-29 cover every surface in the
  assignment table.
- Lights and effects: presets only change numbers on instances that exist.
