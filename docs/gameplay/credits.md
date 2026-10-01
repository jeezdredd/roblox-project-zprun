# In-game credits

The release blocker from the Roadmap ("In-game credits"): every CC BY asset must be
credited in the shipped game, not only in `assets/LICENSES.md`. The credits are
generated from `assets/manifest.json` and shown in a Credits section of the settings
panel. No credit line is written by hand.

## 1. What is credited

Every manifest entry whose licence is CC BY (any version, so 3.0 and 4.0; CC0 and the
share-alike variants are not, and no share-alike asset is used) and whose status is
`approved` or `reviewing`. Today that is 103 entries, credited in 25 lines:

| Group | Keys | Works today |
| --- | --- | --- |
| Models and textures | everything that is not `audio/` or `animation/` (props, their textures and read-back meshes, the first-person rigs, the zombie rigs) | 16 |
| Animations | `animation/...` (the zombie clips baked from the Sketchfab packs) | 3 |
| Audio | `audio/...` (the OpenGameArt footsteps and pistol shot, the freesound mag drop) | 7 |

One line per credited work: the many manifest entries of one work (a model, its colour
and roughness maps, its read-back mesh; a pack's twelve clips) share one line, and the
line lists the manifest keys it covers, so every entry is credited exactly once.

## 2. Where each field comes from

`scripts/sync_configs.py` writes `src/shared/config/CreditsConfig.luau` next to
`AssetIds.luau`, `LICENSES.md` and the prop surfaces, and its `--check` mode covers it.
The fields are read from each entry's own `license` and `source` strings, in this order:

1. An attribution the licence spells out, `"Title" by Author, URL` (the freesound mag
   drop), wins.
2. A quoted title in the source, `"Title" by Author (@handle), URL` (the Sketchfab rigs
   and the zombie clips; the SMG's author line keeps its "uses ... by ..." chain).
3. `Title by Author, URL` in the source (the Sketchfab props and their textures).
4. The author from the licence when the source has none: `credit X on Sketchfab`,
   `CC-BY 3.0 - author, derived from ... by ...` (the footsteps, keeping the original
   recordists), `CC BY 3.0 (Author)` (the pistol shot).
5. The URL: the first non-Creative-Commons link in the source (the licence's first, when
   the licence carried the attribution).
6. A title still missing comes from the URL's page slug (the two OpenGameArt pages,
   "Footsteps on different surfaces" and "Gunshot sounds").
7. A read-back mesh (`MeshId inside Model asset ... (model/props/x)`) takes the credit of
   the Model entry it names.

The licence field is normalised to `CC BY <version>`. An entry none of these rules can
read stops the generator with the key and what is missing, so a new CC BY asset whose
manifest strings carry no readable credit cannot ship uncredited.

Every line is preceded by one note: the assets were adapted for the game (scaled,
decimated, re-pivoted, retargeted, trimmed or filtered), which is the change indication
CC BY asks for.

## 3. Acknowledgements

Two more lines, after the credits, under "With thanks":

- **Mixamo (Adobe)**: the soldier character, the first-person arms and the player
  animations. Mixamo's licence lets them be used in a commercial game with no credit.
- **The Free Firearm Sound Library** (Ben Jaszczak, GitHub mirror by buddingmonkey): the
  gunshots and weapon foley. CC0, no credit required.

Neither licence requires these lines; they are thanks, and each line says "no
attribution required". The generator writes them only while the manifest has assets
from those sources, with the URL from the manifest.

## 4. The panel

`SettingsConfig` gains a fifth category, "Credits", with one read-only spec of the new
kind `"credits"`: nothing is stored or sent (`SettingsPersistence` keeps only toggles and
sliders). `SettingsGui` draws it as a scrolling list of 220 px: the note, each group's
header and lines ("Title by Author. CC BY 4.0. URL", wrapped), then the thanks. The
panel's rows now sit in their own scrolling body between the title and the close
button, so the longer schema never pushes the button off the panel.

## 5. Tests

- `python3 tests/credits/run.py`: reads the manifest on its own (not through the
  generator) and the generated Luau file as text; every CC BY entry, approved or
  reviewing, is in exactly one credit line, no other key is, and every line has a
  title, an author, a `CC BY` licence and a URL. This is the manifest-side test; it is
  Python because the Luau CLI cannot read the JSON manifest.
- `luau tests/credits/run.luau`: the generated module as the game reads it (three groups
  in order, complete lines, no key twice, each key in its kind's group, the two
  acknowledgements).

Both fail on a hand edit of `CreditsConfig.luau`, and `sync_configs.py --check` fails on
it too.

## 6. Studio check list

- Open Settings: the panel scrolls between SETTINGS and the Close button; Close is
  always visible.
- Scroll to CREDITS: the note, then MODELS AND TEXTURES (16 lines), ANIMATIONS (3),
  AUDIO (7), WITH THANKS (2); the list scrolls on its own with the mouse wheel over it;
  long lines wrap, nothing is cut.
- The toggles and sliders still save and restore across a rejoin (the credits row
  stores nothing).
