# Credits

The in-game credits for every CC BY asset, generated from the manifest and shown in the
settings panel. Branch `cloud/credits` (2026-10-01); details and checks in
`docs/gameplay/credits.md`. Clears the "In-game credits" release blocker in [[Roadmap]];
the pipeline is [[Assets Pipeline]]'s.

## Files

| File | Role |
| --- | --- |
| `scripts/sync_configs.py` | Also writes `src/shared/config/CreditsConfig.luau`: every CC BY entry (approved or reviewing) grouped by kind, one line per work with the keys it covers, fields parsed from the entry's `license` and `source`; fails on an entry it cannot read; `--check` covers it |
| `src/shared/config/CreditsConfig.luau` | Generated: `groups` (Models and textures, Animations, Audio), `acknowledgements` (Mixamo, The Free Firearm Sound Library), `NOTE` (the assets were adapted) |
| `SettingsConfig`, `SettingsGui` | The "Credits" category with a read-only `credits` kind; a scrolling list; the panel's rows in a scrolling body |
| `tests/credits/run.py`, `tests/credits/run.luau` | Every CC BY entry exactly once (from the manifest); the generated module's shape |

## Rules

- No hand-written credit lines: a new CC BY asset is credited by its manifest strings or
  the generator stops.
- One line per work; every entry of the work listed under it.
- Mixamo and the Free Firearm Sound Library are thanked, not credited: their licences
  ask for nothing.
