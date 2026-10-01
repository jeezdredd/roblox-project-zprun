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
	-- Reload clip 2.708 s. The slide and hammer never move in it (only the Fire clips
	-- move the slide). MagOut 0.17, MagIn 0.67 (seated after a two-stage push); the
	-- right thumb presses 0.61-0.70 (peak 0.70: the empty cut's SlideRelease); the gun
	-- stays rolled about 83 degrees until 0.70 and snaps back up by 0.84 (3 degrees off
	-- idle, support hand on the grip). Both cuts end there; the rest of the clip is
	-- idle settle. The old tactical end 0.76 was mid-snap, 72 degrees off idle.
	Pistol = {
		asset = "pistol",
		clips = "PistolClips",
		eye = CFrame.new(0, 4.72, -0.066),
		-- the pack holds the pistol at arm's length in the middle of the view (hands 32 cm
		-- out, the gun 55-65 cm): 12 cm closer and a little right and up, near MW's hip
		hold = Vector3.new(0.03, 0.05, 0.14),
		-- the reload rolls the gun up to the face on its own: the pack's framing there
		actionHold = Vector3.zero,
		weaponBone = "DEF_Cuerpo_02",
		weaponMesh = "^Pistol_",
		equip = "Equip",
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		reload = { "Reload" },
		tactical = { clip = "Reload", to = 0.84, blendOut = 0.2 },
		empty = {
			clip = "Reload",
			to = 0.84,
			blendOut = 0.2,
			phases = { { at = 0.7, name = "SlideRelease" } },
		},
		phases = {
			Reload = { { at = 0.17, name = "MagOut" }, { at = 0.67, name = "MagIn" } },
		},
	},
	-- Reload clip 4.583 s: MagOut 0.20, MagIn 0.46, charging handle pulled 0.62, at the
	-- rear 0.64, home 0.68, gun back at idle by 0.83. The support hand never returns to
	-- the handguard before the rack, so the tactical cut ends at 0.54: the bottom of the
	-- hand's dip under the handguard, with the gun already rolling back (62 degrees off
	-- idle, 74 at MagIn), just before the hand sweeps right to the handle. The empty cut
	-- keeps the rack and ends at 0.83, 1 degree off idle, dropping the settle.
	Rifle = {
		asset = "rifle",
		clips = "RifleClips",
		eye = CFrame.new(0, 4.72, -0.066),
		-- the pack's idle carries the AK slanted across the body with the left forearm
		-- reaching in from the bottom-left corner (the owner's recording, 2026-09-30):
		-- 10 cm farther, a little down and right, turned 10 degrees left and pitched 4 up,
		-- it reads as a hip carry with the muzzle near the crosshair
		hold = Vector3.new(0.04, -0.04, -0.1),
		holdAngles = Vector3.new(4, 10, 0),
		weaponBone = "Grip_01",
		weaponMesh = "^SK_AK%-47_Material%.007",
		equip = "Equip",
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		reload = { "Reload" },
		-- The clip only returns the rifle from the mag-in pose (vertical, by the face) while
		-- the hand racks the bolt, 0.54..0.83. Cut at 0.54, a 0.35 s synthetic blend swung
		-- the gun down through the frame and out of view for a frame (the owner's recording,
		-- 2026-10-01); the tactical plays through the rack like the empty one.
		tactical = { clip = "Reload", to = 0.83, blendOut = 0.2 },
		empty = { clip = "Reload", to = 0.83, blendOut = 0.2 },
		phases = {
			Reload = {
				{ at = 0.2, name = "MagOut" },
				{ at = 0.46, name = "MagIn" },
				{ at = 0.64, name = "BoltBack" },
				{ at = 0.68, name = "BoltForward" },
			},
		},
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
