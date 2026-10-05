--!strict

-- First-person weapon packs: skinned arms + weapon imported from Sketchfab glb files
-- (tools/fps_pack) with their clips baked into src/shared/viewmodel_clips. A class listed
-- here is drawn from its pack instead of ViewmodelBuilder's procedural rig.
--
-- Rig units: every rig is uploaded at the same size (arm span about 3.76 studs, the
-- pistol pack's native scale), so eye offsets and procedural sway share one scale.
-- `eye` is the view point in the rig's RootPart space at rest, looking down -Z.
-- `phases` are sound cues as fractions of a clip, measured from the magazine and bolt
-- bones' motion relative to the weapon body (tools/fps_pack, 2026-09-29). They fire
-- from PackViewmodel however the clip is cut or stretched, and WeaponsConfig's
-- ammo-add times are placed on them (MagIn, SlideRelease, BoltForward, ShellIn).
--
-- Cut points and phases re-measured 2026-09-29, offline: the baked tracks decoded as
-- ViewmodelClipPlayer does (targetWorld = delta * restWorld on the Studio rest positions
-- in tools/fps_pack/roblox_rest) and sampled at 240 Hz; the weapon bone's rotation
-- against Idle frame 0, and the support hand, magazine and bolt bones relative to the
-- weapon body. MagOut = magazine 0.05 stud out of the well, MagIn / ShellIn = seated
-- within 0.01, BoltBack = bolt at its rear stop, BoltForward = bolt home (studs of the
-- uploaded rig, before RIG_SCALE). A tactical cut ends after MagIn where the clip is
-- nearest the ready pose before any bolt motion; an empty cut ends once the action is
-- closed and the gun is back within a few degrees of idle.

export type Phase = { at: number, name: string }

-- A section of one clip. `from`/`to` are fractions of the clip; the section is played
-- at whatever speed fits the time WeaponsConfig gives it, then the idle/walk loop is
-- blended back in over `blendOut` seconds (that blend is part of the reload time).
-- `phases` are extra markers for this use of the clip only (the pistol's empty reload
-- adds SlideRelease, the tactical one never reaches it).
export type ClipCut = {
	clip: string,
	from: number?,
	to: number?,
	blendOut: number?,
	phases: { Phase }?,
}

-- Pump shotgun reload: enter, one `loop` section per shell (its ShellIn marker is the
-- add point), leave, and the `chamber` pump when the reload started from empty.
export type ShellClips = {
	enter: string,
	loop: ClipCut,
	leave: string,
	chamber: ClipCut,
}

-- A speed reload from empty drops the spent magazine instead of pouching it the way the
-- tactical reload does. When `clip` plays as the empty reload and passes `at` (clip
-- fraction), the meshes in `pieces` (name pattern and the bone that carries them; of
-- several meshes with a matching name, the one nearest that bone at rest) leave
-- the rig as a world-size copy that falls and lies on the ground (DroppedMagazines);
-- `hidden` keeps magazine meshes out of sight over clip fractions where the hand would
-- otherwise carry the dropped one. `worldScale` turns the rig size into world size.
export type MagDrop = {
	clip: string,
	at: number,
	pieces: { { part: string, bone: string } },
	hidden: { { part: string, bone: string?, from: number, to: number } },
	worldScale: number,
}

-- After the last round the bolt or slide stays locked back until an empty reload
-- releases it: the joint, and the clip whose first frame holds it back.
export type LockBack = { bone: string, clip: string }

export type ClassPack = {
	asset: string,
	clips: string,
	eye: CFrame,
	-- Where the rig sits relative to the pack camera, in camera space (studs of the scaled
	-- rig; +X right, +Y up, -Z away). The packs frame their guns for their own camera,
	-- which puts some of them in the middle of the view or against the face; this moves
	-- the whole rig, every clip alike. Tuned in Studio with the camera attribute
	-- ViewmodelHold (PackViewmodel.step).
	hold: Vector3?,
	-- Turn of the rig about the eye, degrees (pitch, yaw, roll), applied with `hold`: a
	-- pack whose idle carries the gun slanted across the body can be turned so the barrel
	-- runs more along the view. Tuned with the camera attribute ViewmodelHoldAngles.
	holdAngles: Vector3?,
	-- The same offset while a reload, a draw or an inspect plays (nil keeps `hold`): a
	-- hold that brings an idle gun closer can push those clips, which already bring the
	-- gun in, into the camera. The rig blends between the two over about 0.1 s.
	actionHold: Vector3?,
	-- Rotation of the rig's rest (bind) pose relative to the upright clip pose, when
	-- Roblox built the bones turned (the Uzi's bind A-pose comes in turned -90 degrees
	-- about X). Only the weapon anchors read it; the clips always pose the rig upright.
	restTilt: CFrame?,
	-- Roblox import units per pack unit when the rig did not come in at the clips' scale
	-- (the Fab M4 imports in centimetres: 0.03); 1 when omitted
	importScale: number?,
	weaponBone: string,
	weaponMesh: string,
	equip: string,
	idle: string,
	move: string?,
	fire: string,
	-- share of the Fire clip's move that is applied (1 = as authored)
	fireWeight: number?,
	-- fraction of `fire` played before `fireFollow` takes over (the shotgun keeps only
	-- the recoil of its Fire clip and hands over to the pump)
	fireTo: number?,
	fireFollow: string?,
	-- fraction of `fireFollow` at which the action is closed again; fire and follow are
	-- sped up together so this lands inside one fire interval
	followReady: number?,
	-- clip lists for classes without `tactical`/`empty` cuts, stretched to the reload time
	reload: { string },
	reloadEmpty: { string }?,
	tactical: ClipCut?,
	empty: ClipCut?,
	shell: ShellClips?,
	inspect: string?,
	phases: { [string]: { Phase } },
	magDrop: MagDrop?,
	lockBack: LockBack?,
	-- material name in a mesh's name -> SurfaceAppearance template in
	-- ReplicatedStorage.ViewmodelSurfaces, for meshes the importer left without one
	surfaces: { [string]: string }?,
}

local ViewmodelPackConfig = {}

-- The rigs are uploaded at about 2.2x life size. At that size the arms reach 2-3 studs
-- into the world and clip into walls and cars next to the camera, so the clone is scaled
-- down (Model:ScaleTo scales the bones too) and the clip translations and eye with it;
-- the image is the same, the world footprint shrinks.
ViewmodelPackConfig.RIG_SCALE = 0.4

-- The procedural channels (sway, recoil, impact) are in studs tuned for the old
-- 0.72-scale rig; their translations are multiplied by this for the pack rigs.
ViewmodelPackConfig.PROCEDURAL_POSITION_SCALE = 1.1

-- the pack clips carry their own walk bob, so the procedural bob is damped hard
ViewmodelPackConfig.BOB_SCALE = 0.25

ViewmodelPackConfig.classes = {
	-- Fab "G17 - FPS Weapon Animations Pack" (BarcodeGames, Fab Standard License; rig and
	-- clips are Fab content in assets/fab/ and src/shared/fab/G17Clips.luau, never
	-- committed). Replaced the pistol pack (2026-10-01). Imported in centimetres like the
	-- M4. The pack's Idle is one pose; Idle and Walk loop it. Both pack reloads fetch the
	-- spare first, strip the old magazine into the same hand and pouch it (a tactical
	-- reload with retention); from frame 54 the two magazine bones trade tracks
	-- (identical meshes, invisible), so the seated one is Mag1 again when the clip ends.
	-- The empty reload is turned into a speed reload (2026-10-01, the owner: tactical
	-- and empty must differ in handling, not only in length): the spent magazine falls
	-- free as it leaves the well (0.65 s) and the old-magazine track is hidden, and the
	-- slide stays locked back after the last round until the slide release.
	-- Reload 2.80 s: MagOut 0.60, MagIn 0.76, ready by 0.92. ReloadEmpty 3.03 s: MagOut
	-- 0.45, MagIn 0.58, slide release 0.63, ready by 0.78 (first estimates from the bone
	-- motion, to be tuned by ear).
	Pistol = {
		asset = "g17",
		clips = "G17Clips",
		importScale = 0.03,
		eye = CFrame.new(-0.039, 4.59, 0.33),
		-- the pack's camera holds the pistol in the middle of the view; moved right, down
		-- and forward into a ready hold, and about half as far while a reload or the draw
		-- plays, so the magazine work stays in frame
		hold = Vector3.new(0.07, -0.06, -0.15),
		actionHold = Vector3.new(0.04, -0.03, -0.08),
		weaponBone = "Main_j_050",
		weaponMesh = "^Main_Glock",
		equip = "Draw",
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		reload = { "Reload" },
		reloadEmpty = { "ReloadEmpty" },
		tactical = { clip = "Reload", to = 0.92, blendOut = 0.2 },
		empty = { clip = "ReloadEmpty", to = 0.78, blendOut = 0.2 },
		phases = {
			Reload = { { at = 0.6, name = "MagOut" }, { at = 0.76, name = "MagIn" } },
			ReloadEmpty = {
				{ at = 0.45, name = "MagOut" },
				{ at = 0.58, name = "MagIn" },
				{ at = 0.63, name = "SlideRelease" },
			},
		},
		magDrop = {
			clip = "ReloadEmpty",
			at = 0.214,
			pieces = {
				{ part = "^Mag1_Glock", bone = "Mag1_j_052" },
				{ part = "^Mag1_Bullet", bone = "Mag1_j_052" },
			},
			-- Mag1 is the dropped one until the trade at frame 54 (0.594), then Mag2 carries
			-- the old magazine's pouching track
			hidden = {
				{ part = "^Mag1_", from = 0.214, to = 0.594 },
				{ part = "^Mag2_", from = 0.594, to = 1.01 },
			},
			worldScale = 2.5,
		},
		lockBack = { bone = "Slide_j_00", clip = "ReloadEmpty" },
		-- the importer gave this rig no SurfaceAppearance at all (its materials carry only
		-- a base colour); the arms share the M4 pack's textures
		surfaces = {
			Glock_D = "g17_glock",
			Bullet_9mm_D = "g17_round",
			Hand_D = "fab_arms_hand",
			Glove_D = "fab_arms_glove",
		},
	},
	-- Fab "M4 - FPS Weapon Animations Pack FREE" (BarcodeGames, Fab Standard License; the
	-- rig and the clips are Fab content: assets/fab/ and src/shared/fab/M4Clips.luau, never
	-- committed). Replaced the AK pack (2026-10-01). Roblox imports the rig in centimetres,
	-- the clips are baked at 3 studs per metre, so the rig is scaled by 0.03 first. The pack
	-- has no idle or walk: both are the Draw clip's last pose (build in tools/fps_pack), the
	-- procedural layer carries breathing and bob. Reload 3.63 s: MagOut 0.29, MagIn 0.64,
	-- back at ready by 0.78. ReloadEmpty 3.80 s: MagOut 0.31, MagIn 0.57, bolt catch
	-- released 0.70, ready by 0.84. In both pack reloads the hand carries the old
	-- magazine to the pouch and comes back with "it" (Mag2 never moves): right for the
	-- tactical reload with retention. The empty one becomes a speed reload: the magazine
	-- falls free when it leaves the well (0.85 s, fraction 0.225) and Mag1 stays hidden
	-- until the hand turns back from the pouch with the fresh one (1.35 s); the bolt
	-- stays locked back after the last round until the bolt catch (2026-10-01).
	Rifle = {
		asset = "m4",
		clips = "M4Clips",
		importScale = 0.03,
		eye = CFrame.new(-0.033, 4.618, 0.302),
		-- the pack frames the rifle big in the middle of the view; moved right, down and
		-- forward into a hip carry, about half as far while a reload or the draw plays
		hold = Vector3.new(0.06, -0.07, -0.12),
		actionHold = Vector3.new(0.03, -0.035, -0.06),
		weaponBone = "Main_j_049",
		weaponMesh = "^Main_M4",
		equip = "Draw",
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		reload = { "Reload" },
		reloadEmpty = { "ReloadEmpty" },
		tactical = { clip = "Reload", to = 0.8, blendOut = 0.2 },
		empty = { clip = "ReloadEmpty", to = 0.85, blendOut = 0.2 },
		phases = {
			Reload = { { at = 0.29, name = "MagOut" }, { at = 0.64, name = "MagIn" } },
			ReloadEmpty = {
				{ at = 0.31, name = "MagOut" },
				{ at = 0.57, name = "MagIn" },
				{ at = 0.7, name = "BoltForward" },
			},
		},
		magDrop = {
			clip = "ReloadEmpty",
			at = 0.225,
			-- both magazines carry a round mesh of the same name: the one nearest the bone
			pieces = {
				{ part = "^Mag1_M4", bone = "Mag1_j_050" },
				{ part = "^Bullet5", bone = "Mag1_j_050" },
			},
			hidden = {
				{ part = "^Mag1_M4", from = 0.225, to = 0.355 },
				{ part = "^Bullet5", bone = "Mag1_j_050", from = 0.225, to = 0.355 },
			},
			worldScale = 2.5,
		},
		lockBack = { bone = "Bolt_j_052", clip = "ReloadEmpty" },
	},
	-- Fire (1.625 s) is recoil plus a slow settle: peak 0.12-0.14 (36 degrees) and the
	-- clip's own bolt flick is home by 0.16, so only the first 20% is kept (31 degrees
	-- off idle, recovering) and the AccionFire pump follows. AccionFire (1.25 s) starts
	-- and ends at idle: pump at the rear 0.10 (BoltBack, where the hull is ejected), home
	-- 0.48 (BoltForward and followReady). Reload (1.667 s, one shell, gun rolled 100
	-- degrees) seats the shell at 0.70. The loop section 0.24-0.89 starts and ends where
	-- the support hand crosses its own path (0.15 stud apart, 0.71 for the old
	-- 0.1-0.88), so each shell reads as one dip of the hand; one cycle fits
	-- WeaponsConfig perShell at 1.2x. The chamber pump ends at 0.51, just after home.
	Shotgun = {
		asset = "shotgun",
		clips = "ShotgunClips",
		eye = CFrame.new(0, 4.72, -0.066),
		weaponBone = "Root_0106",
		weaponMesh = "Weapon",
		equip = "Equip",
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		-- the clip kicks the gun 34 degrees (22 by 0.08, 34 at 0.17): at the hip that reads
		-- as a cartoon, so it plays at 45 %, about 15 degrees, like MW's pump guns
		fireWeight = 0.45,
		fireTo = 0.2,
		fireFollow = "AccionFire",
		followReady = 0.48,
		reload = { "IdleToReload", "Reload", "ReloadToIdle" },
		shell = {
			enter = "IdleToReload",
			loop = { clip = "Reload", from = 0.24, to = 0.89 },
			leave = "ReloadToIdle",
			chamber = { clip = "AccionFire", to = 0.51, blendOut = 0.2 },
		},
		phases = {
			AccionFire = { { at = 0.1, name = "BoltBack" }, { at = 0.48, name = "BoltForward" } },
			Reload = { { at = 0.7, name = "ShellIn" } },
		},
	},
	-- Uzi pack (1Matzh). Reload 2.033 s: MagOut 0.12, MagIn 0.51, gun back by 0.71 with
	-- a small overshoot, settled by 0.80 (0.2 degrees at the 0.9 cut). ReloadEmpty 3.7 s:
	-- MagOut 0.07, MagIn 0.35, then the open-bolt top-knob cock: pull from 0.58, knob at
	-- the rear 0.62 (BoltBack), home 0.70 (BoltForward), gun back by 0.88 (1 degree at
	-- the 0.9 cut). Both cuts play at natural speed. Fire moves no weapon part (open
	-- bolt), the procedural recoil carries the shot. Eye: the pack camera is at
	-- (0, 4.42, -0.07), moved back like the other packs'.
	SMG = {
		asset = "smg",
		clips = "SMGClips",
		eye = CFrame.new(0, 4.42, -0.066),
		-- the pack's camera sits on the sights with the extended stock against the cheek;
		-- lowered and moved right into a hip hold, the stock leaves the view at the
		-- bottom right
		hold = Vector3.new(0.08, -0.16, -0.08),
		restTilt = CFrame.Angles(-math.pi / 2, 0, 0),
		weaponBone = "UZI Body_0725",
		weaponMesh = "^UZI_UZI_0$",
		equip = "Equip",
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		reload = { "Reload" },
		reloadEmpty = { "ReloadEmpty" },
		tactical = { clip = "Reload", to = 0.9, blendOut = 0.17 },
		empty = { clip = "ReloadEmpty", to = 0.9, blendOut = 0.2 },
		inspect = "Inspect",
		phases = {
			Reload = { { at = 0.12, name = "MagOut" }, { at = 0.51, name = "MagIn" } },
			ReloadEmpty = {
				{ at = 0.07, name = "MagOut" },
				{ at = 0.35, name = "MagIn" },
				{ at = 0.62, name = "BoltBack" },
				{ at = 0.7, name = "BoltForward" },
			},
		},
	},
} :: { [string]: ClassPack }

function ViewmodelPackConfig.get(class: string): ClassPack?
	return ViewmodelPackConfig.classes[class]
end

return ViewmodelPackConfig
