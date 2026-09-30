# Animation sources: what is available under our licences (checked 2026-09-30)

A search for animation packs the project may use, held to `docs/asset-policy.md`: CC0,
public domain, CC BY (credit recorded), Mixamo and the Roblox Creator Store are in;
CC BY-SA, CC BY-NC, packs whose licence names an engine (Fab and Unity Asset Store
engine-bound items, Unreal-only content) and anything ripped from a game are out. Every
Sketchfab licence below was read from Sketchfab's own API (`api.sketchfab.com/v3/models/<uid>`);
each returned "CC Attribution: author must be credited, commercial use is allowed". The
API does not list clip names, so clip counts are given; the viewer's animation list has
the names. A model page is `https://sketchfab.com/models/<uid>`.

**The short version.** Nothing free reaches Call of Duty MW2019 quality. The packs at
that level are Fab and Unreal listings with an engine-bound licence, which the policy
excludes. The best of the allowed tier is hobby work made in Blender (Cransh, 1Matzh).
The route to the look we want is Mixamo for the body, the best free first-person packs
for the arms, the procedural layers the game already has (recoil, sway, IK, gestures),
and hand fixes to the clips' defects in Blender.

## 1. First-person arms and weapon

Mixamo has no first-person arm animations (third person only).

### Rifle
- **FPS AK-74m animations**, Cransh, uid `94be8385c402474cacd39bc096c6ca14`. CC BY. 8
  clips (a run clip among them), 40,024 faces, 8 textures, own Blender armature, all
  clips packed in one FBX. Arms are "FP-ARMS by DJMaesen (bumstrum)", the AK-74m by
  creationwasteland. Licence risk: bumstrum publishes both a CC BY "First Person arms"
  and a CC BY-NC "FP Arms"; check which mesh the pack carries before use, or swap in
  our own arms mesh (the Mixamo Swat Guy arms already in `viewmodel/arms`).
- **Animated FPS hands (rifle animation pack)**, Cransh, uid `5f2d0ed780a94724b36ab505f7564057`.
  CC BY. 8 clips, 26,702 faces; the author notes glitchy vertices on the rifle.

### Pistol
- **9mm Pistol | First Person Animations**, 1Matzh, uid `c26d7f5aa72f4b01a6da4578caa8f07f`.
  CC BY. 10 clips including `Reload_Empty`, 29,321 faces. Pistol by Urpo, arms "Modern
  Soldier" by Blue-Spirit. No last-shot slide lock (a commenter asks for one), so the
  same defect as the DuqueCD7 pack we run today.
- **FPS pistol animations**, Cransh, uid `0d7a343dcb6f401197a73c91aee93f6d`. CC BY. 5
  clips, 32,670 faces. Reported issues: engines reject the root named "Armature", and
  "the arms are twisted" on import.

### SMG
- **Scorpion | First Person Animations (2026 Remake)**, 1Matzh, uid `f2bdfac775344004ad38d0318f0664a4`.
  CC BY. 9 clips, 34,053 faces, remade 2026-09-25, a camera animation added. The same
  Blue-Spirit "Division Agent" arms as our Uzi pack (CC BY, "Personal Design").
- **SMG FPS Animations**, Cransh, uid `ca37ea9148dc4fcc9cc632175d311b23`. CC BY. 8
  clips, 29,282 faces; textures come in turned 180 degrees, messy materials in Blender.
- **FPS Animations LowPoly MP5**, Cransh, uid `568f00dd76944baaa5eae1a1cc871423`. CC BY.
  9 clips, 10,673 faces, low-poly style.

### Pump shotgun
- **Animated Shotgun**, JUST (teenjust500), uid `e048ba220f9e49c29a3e808cddc22a0a`. CC
  BY. Clips: Take, Idle, Shoot, Reload Start, Reload, ReloadEnd, Watch, Hide. 28,596
  faces. Already evaluated on 2026-09-29 and rejected (broken shared skin, no idle or
  walk clips in the file we got); the start / loop / end reload structure would suit
  the shell-by-shell reload if a clean export turns up.
- **FPS Arms remington**, Cransh, uid `e68ef617fe8a48cca8610d016ffd5881`. CC BY. Only 4
  clips; left-arm lag noted by the author; "Several roots" import error reported.
- **FPS Benelli M4 Animations**, Cransh, uid `225a62190f6043ca975eaa2798ab7e2c`. CC BY.
  8 clips, semi-auto (no pump); in the auto-converted GLB the weapon is about 100x the
  arms, so take the original FBX.

### Other channels checked
- Quaternius Animated Guns (CC0): six animated guns, no arms.
- WRAD ARMS (CC0, itch.io): arms only, 1,200 triangles, no clips.
- OpenGameArt "fps arms (rigged only)" (CC0): one crude sample clip.

### Excluded
- TheParaziT MP7 / AR-15 / RPG packs: built on the Unreal Engine 5 skeleton.
- 1Matzh M4A1-S: CC BY-NC.
- BarcodeGames AKM: no licence, not downloadable.
- GDQuest FPS arms: art is CC BY-NC-SA.
- MoCap Online free pistol starter pack: its own licence, not CC.
- kevdev soldier pack (itch.io): no licence text.

## 2. Third-person locomotion (R15)

**Mixamo** (Adobe): "royalty free for personal, commercial, and non-profit projects
including video games" (helpx.adobe.com/creative-cloud/faq/mixamo-faq.html). Clip names,
checked against a catalogue mirror:
- Rifle: Rifle Idle, Rifle Aiming Idle, Rifle Down To Aim, Rifle Aim To Down; Rifle
  Walk and Walk Forward / Left / Right / Backward (with the diagonal variants); Rifle
  Run, Rifle Run 2 (aimed), Run Forward / Left / Right, Run Backward 3; Sprint Forward /
  Left / Right / Backward Left / Backward Right; Strafe (Rifle Walk Strafe Left /
  Right); Walk Crouching Forward and Rifle Turn 1 to 8; Firing Rifle (standing,
  walking, running); Reloading (standing), Reload (walk, run, crouch variants); Rifle
  Pull Out, Rifle Put Away, Rifle Death.
- Pistol: Pistol Idle, Pistol Walk, Pistol Run, Pistol Strafe (L/R), Pistol Walk
  Backward, Pistol Run Backward, Pistol Walk Arc, Pistol Jump, Pistol Kneeling Idle,
  Shooting Gun. No pistol-specific reload found.
- Hit reactions: Hit Reaction (holding a rifle, holding a pistol), Walking Hit
  Reaction, Standing React Small / Large From Front / Back / Left / Right.
- Aim offsets: none; the body layer does them procedurally (waist and neck by camera
  pitch), which is what `src/client/body` already does.

**Quaternius UAL.** UAL 1 (CC0): 120+ clips including "combat and gun", root-motion and
in-place versions; the gun clip names are not published online, check the local
download. UAL 2 free list: no gun clips; it has ZOMBIE_SCRATCH and ZOMBIE_WALK_FWD.

**CMU mocap** (mocap.cs.cmu.edu: "you may include this data in commercially-sold
products, but you may not resell this data directly"; cgspeed BVH conversion "free to
use worldwide for any purpose"): 79_96 and 80_03 shooting a gun, 79_05 pulling a gun,
139_19 to 24 walking with a wounded leg. No rifle locomotion. Acknowledgment to record:
"The data used in this project was obtained from mocap.cs.cmu.edu. The database was
created with funding from NSF EIA-0196217."

**Other mocap sets.** Bandai Namco Research motion dataset: CC BY-NC 4.0, excluded.
100STYLE (ianxmason.com/100style): CC BY 4.0, BVH only; DragLeftLeg, DragRightLeg,
Drunk, LimpLeft, LimpRight are usable stagger material.

**Roblox.**
- UTPS.dsk by pankii_kust (DevForum, asset 12247606728): R15 `.rbxm` with reload and
  fire for pistol, rifle, crossbow, one-handed SMG and shotgun; "free to use as long as
  you credit me"; needs the `RbxLegacyAnimationBlending` workaround.
- R15 GUN ANIMATIONS (asset 9703914879): shotgun pump, MP5 / rifle / pistol reload,
  rifle tactical reload; a Creator Store asset with no licence text in the post.
- Roblox Weapons Kit: RifleAim, RifleAimDownSights, RifleReload under Roblox's Limited
  Use License.

## 3. Zombie clips

- **Mixamo**: Zombie Stand Up (three variants: laying on back / side / stomach to
  standing), Zombie Biting, Zombie Biting Victim On The Ground, Zombie Standing To
  Biting On The Ground, Zombie Neck Bite, Zombie Stumbling, Zombie Reaction Hit, Zombie
  Scratch Idle; Walking "Creeping Zombie Walk", "Male Injured Walk", "Male Drunk Walk".
  These fill the two gaps the skinned zombies have (rise and feeding).
- **CMU**: get-ups 140_01 to 04, 140_08 / 09 and 139_16 to 18; ZombieWalk 104_41 to 43,
  zombie march 20_08 and 21_08; StumbleWalk 104_13, DrunkWalk 91_09, limping 77_19 to 24.
- **100STYLE** (CC BY 4.0): DragLeftLeg, DragRightLeg, Drunk, LimpLeft, LimpRight.
- Sketchfab: no CC BY rise or feeding clips found; "Classic Zombie | Half-Life 2" is a
  game rip, excluded.

## 4. Retargeting notes

- **R15 target**: Root, HumanoidRootNode, LowerTorso, UpperTorso, Head, the arm chain
  (UpperArm / LowerArm / Hand) and the leg chain (UpperLeg / LowerLeg / Foot); LowerTorso
  and Root at 0, 0, 0; rest pose I, A or T (create.roblox.com/docs/avatar/character-bodies/specifications).
  Import through the Animation Editor "Import > From File".
- **Mixamo**: the existing `tools/animation_pipeline` retarget (0.0217 studs per cm,
  T-pose calibration). Locomotion with In Place on; Stand Up and Biting with In Place
  off, then the root offset moved onto HumanoidRootPart.
- **UAL**: "compatible with other common rigs (Mixamo for example)"; a reviewer notes
  the UpperChest bends too much, so add a bone map that folds UpperChest into
  UpperTorso; v2.0 renamed the rig.
- **CMU and 100STYLE BVH**: cgspeed files carry a T-pose on frame 1 and MotionBuilder
  joint names; convert BVH to FBX in Blender, calibrate the pipeline from frame 1.
- **Sketchfab first-person packs**: not R15; a separate viewmodel rig (arms plus weapon
  bones) takes the clips, as the pack rigs do today. Download the original FBX or Blend
  (the auto-converted GLB has the scale bug above), rename the "Armature" root and keep a
  single root, split the takes (Cransh packs every clip into one FBX), and treat slide,
  magazine and pump as bones; a dropped magazine needs a detachable part.

## Ranked shortlist

1. **Mixamo**: every third-person locomotion, reload and hit need, and both missing
   zombie clips; already in the pipeline and royalty-free for games.
2. **Cransh FPS AK-74m**: the most-liked downloadable CC BY first-person pack, 8 clips,
   detailed mesh; check the arms mesh's licence first.
3. **1Matzh 9mm Pistol**: 10 clips including Reload_Empty, no bug reports, the same
   arms family as our Uzi; the slide lock still has to be authored.
4. **1Matzh Scorpion 2026 Remake**: the SMG replacement on the same rig as our Uzi.
5. **UTPS.dsk**: native R15 reloads and fires for pistol, rifle, SMG and shotgun with
   no retargeting; credit required.

## Owner's steps

- Sketchfab: log in, download the original format (FBX or Blend) of each pack.
- Mixamo: log in with an Adobe ID; export per the pipeline notes above.
- Roblox Creator Store: "Get" on 12247606728 (and 9703914879 only if its terms are
  found).
- Credit lines to record in `assets/manifest.json` and `assets/LICENSES.md`:
  "FPS AK-74m animations by Cransh, CC BY 4.0 (AK-74m by creationwasteland; arms by
  DJMaesen / bumstrum)"; "9mm Pistol | First Person Animations by 1Matzh, CC BY 4.0
  (pistol by Urpo; Modern Soldier by Blue-Spirit)"; "Scorpion | First Person
  Animations (2026 Remake) by 1Matzh, CC BY 4.0"; "UTPS.dsk by pankii_kust"; 100STYLE,
  CC BY 4.0; the CMU acknowledgment above.
