# Research: how Roblox shooters reach near-AAA look and feel

Status: 2026-10-01. Question: can Roblox carry MW2019-grade presentation, and how did the games that got closest do it. Short answer: yes for a small, art-directed scope. Nothing in these games is an engine trick hidden from us; the gap is content quality (custom models, PBR textures, hand-authored first-person animation, recorded audio) plus a dense layer of small details.

## The games

| Game | Maker | What is verifiable about the pipeline |
| --- | --- | --- |
| TTK (TTK Testing) | Sable Digital: PoptartNoahh and CanyonJack, two brothers working in their free time | Viewmodel animations commissioned: the in-game menu credits "Viewmodel Animations by Altronbee", the experience page lists "VIEWMODEL ANIMATIONS: Altron", "WEAPON FIRING SOUNDS: Hvellor" and a composer for the intro music. PoptartNoahh published a "Substance Bridge for Roblox" plugin: live editing between Substance Painter and SurfaceAppearance, automatic texture upload, PBR and emission maps. He earlier wrote a Doom WAD importer as a Studio plugin. Inspiration: Ready or Not with bodycam elements. 7 million plays within weeks of launch (June 2026). |
| Frontlines | MAXIMILLIAN (Clarence Maximillian), core team of five plus about fifteen contractors | Assets made in Blender, Adobe Suite, Substance Painter, Octane, Pro Tools, then brought into Roblox. "Thousands of iterations on every part of the game." One team member spent six months on weapon audio and surface bounces. Runs on mobile. |
| Deadline | RECOIL Studio | More than 1000 weapon parts, part-level customisation, slow movement with stamina, leaning, point aiming, NVG. |
| Blackhawk Rescue Mission 5 | PLATINUM FIVE | Large PvE co-op operations; hired builders and map designers through the DevForum (monthly paid contracts). |
| Project Apex | ARCSOFT | Tactical PMC shooter; no technical sources found. |

What they share: custom character models instead of Roblox avatars, every surface on authored PBR (SurfaceAppearance), hand-authored first-person clips from a dedicated animator, recorded gun audio, and a slow pace that lets the player see the detail.

## TTK, frame by frame

Watched the jackfrags video "Somehow they made a Realistic FPS Game in Roblox..." (12:38, 2026-06-19) every 8 s and the reload section at 2 fps.

**Viewmodel**
- Full forearms to the elbow, realistic skin with sweat specular, high-detail gloves (normal maps on the knit), a wristwatch. The arms are a large part of the frame and carry most of the realism.
- Held low and to the right, wide FOV. Three stances on a key: low, mid, high ready. Lean with a matching helmet POV change. Free look.
- Per weapon several distinct reloads. Pistol tactical (rounds left): the gun cants, the magazine drops out and the new one goes in, about 1.5 s. Pistol empty: the slide stays locked back after the last shot, the gun turns further toward the camera, new magazine, slide release, about 2.5 s. Shotgun: shell by shell with the loading port turned up, plus a second loading pose.
- Interaction animations: the left hand presses the elevator button; toggling the laser shows the hand on the PEQ box. Ammo/magazine check on a hold key.
- Casings and shotgun shells eject as world objects.

**World**
- Dark interiors with strong contrast; local coloured accent lights (red alarm, teal fluorescents, warm work lights) do the art direction. Emissive exit signs.
- Every surface PBR: concrete with normal detail, grated floor tiles, painted metal. Clutter decals on every floor: paper sheets, cables, stains.
- Glass breaks pane by pane; blood decals on characters after hits.
- Settings include a camera smudge, transparent optics off by default, ear muffling on death and flashbangs. A "swoosh" sound plays when the head turns quickly.

**Audio**: commissioned firing sounds, directional footsteps, ear muffling.

## Engine features that matter (verified)

- Unified Lighting: `Lighting.LightingStyle` (`Realistic` or `Soft`) and `Lighting.PrioritizeLightingQuality` replace `Lighting.Technology`; local lights still cap at 60 studs, longer ranges and better attenuation announced. Neither property is scriptable. (DevForum announcement, linked below.)
- SurfaceAppearance with PBR and emission maps (used by TTK through the Substance bridge, by Twin Atlas and Ecos per the Roblox newsroom interviews).
- Instance streaming for large maps (Twin Atlas).
- Animation capture from video in Studio (create.roblox.com/docs/animation/capture), useful for third-person body clips, not for first-person.

## What this means for us, in order of impact

1. **First-person clips with distinct variants per situation.** Done partly through Fab packs. Tactical and empty reloads must follow different handling, not only different lengths (see [[Decisions]] 2026-10-01). Next: a magazine/ammo check, interactions (button press, pickup), stance poses, inspect. A commissioned FP animator is what TTK did; the DevForum Talent Hub has viewmodel animator listings.
2. **Arms.** Sleeves or gloves with PBR detail and a watch on the wrist; the bare default arms read as cheap.
3. **PBR everywhere.** Megascans surfaces through the importer; a SurfaceAppearance workflow from Substance-style texture sets.
4. **Detail density.** Decals (papers, cables, stains), emissive signs, small props; "a lot of small things add up" (MAXIMILLIAN).
5. **Light direction.** Few strong coloured accents per scene, dark exposure in interiors and at night.
6. **Audio.** Layered recorded shots and surface-aware tails (already in place), plus ear muffling and the head-turn swoosh.

## Sources

- PC Gamer, "Realistic Roblox FPS made by two people hits 7 million plays": https://www.pcgamer.com/games/fps/realistic-roblox-fps-made-by-two-people-hits-7-million-plays-reminding-us-that-roblox-games-dont-have-to-be-terrible/
- PCGamesN, TTK Testing: https://www.pcgamesn.com/roblox/ttk-testing-tactical-fps
- TTK DevForum thread: https://devforum.roblox.com/t/ttk-our-very-early-tactical-fps/4664539
- PoptartNoahh, Substance Bridge for Roblox: https://x.com/PoptartNoahh/status/2034162150785102145
- Interview with PoptartNoahh (RooM): https://medium.com/@talkativeentertainmentrbx/room-and-gloom-an-interview-with-poptartnoahh-d05c11bf74f1
- jackfrags, TTK gameplay: https://www.youtube.com/watch?v=IcG2978ChwQ
- Dexerto, Frontlines creator: https://www.dexerto.com/roblox/roblox-frontlines-creator-reveals-how-he-made-viral-call-of-duty-inspired-game-2338310/
- PocketGamer.biz, Maximilian Studios: https://www.pocketgamer.biz/maximilian-studios-on-the-success-of-frontlines-you-dont-need-a-3000-rig-or-a-500-console-you-can-boot-it-up-on-your-mobile-device/
- Roblox newsroom, creators on fidelity (July 2026): https://about.roblox.com/newsroom/2026/07/roblox-studio-fidelity-creator-interviews-twin-atlas-fluorlite-maximillian-ecos
- NamuWiki, Deadline (Roblox): https://en.namu.wiki/w/Deadline(Roblox)
- NamuWiki, FRONTLINES: https://en.namu.wiki/w/FRONTLINES
- Unified Lighting announcement: https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512
- Animation capture docs: https://create.roblox.com/docs/animation/capture
