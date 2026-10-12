--!strict

export type Phase = { at: number, name: string }

export type ClipCut = {
	clip: string,
	from: number?,
	to: number?,
	blendOut: number?,
	phases: { Phase }?,
}

export type ShellClips = {
	enter: string,
	loop: ClipCut,
	leave: string,
	chamber: ClipCut,
}

export type MagDrop = {
	clip: string,
	at: number,
	pieces: {
		{
			part: string,
			bone: string,
			skin: { string }?,
			body: { center: Vector3, size: Vector3 }?,
			tuck: { [string]: { from: Vector3, to: Vector3 } }?,
		}
	},
	hidden: { { part: string, bone: string?, from: number, to: number } },
	worldScale: number,
}

export type LockBack = { bones: { string }, clip: string }

export type Cut = { clip: string, bones: string, frame: number }

export type ClassPack = {
	asset: string,
	clips: string,
	eye: CFrame,
	hold: Vector3?,
	holdAngles: Vector3?,
	actionHold: Vector3?,
	restTilt: CFrame?,
	muzzle: { position: Vector3, direction: Vector3 }?,
	importScale: number?,
	weaponBone: string,
	weaponMesh: string,
	equip: string,
	equipFrom: number?,
	equipTo: number?,
	idle: string,
	move: string?,
	fire: string,
	fireWeight: number?,
	fireTo: number?,
	fireFollow: string?,
	followReady: number?,
	reload: { string },
	reloadEmpty: { string }?,
	tactical: ClipCut?,
	empty: ClipCut?,
	shell: ShellClips?,
	inspect: string?,
	phases: { [string]: { Phase } },
	magDrop: MagDrop?,
	lockBack: LockBack?,
	cuts: { Cut }?,
	surfaces: { [string]: string }?,
	surfacesReplace: boolean?,
}

local ViewmodelPackConfig = {}

ViewmodelPackConfig.RIG_SCALE = 0.4

ViewmodelPackConfig.PROCEDURAL_POSITION_SCALE = 1.1

ViewmodelPackConfig.BOB_SCALE = 0.25

ViewmodelPackConfig.classes = {
	Pistol = {
		asset = "g17",
		clips = "G17Clips",
		importScale = 0.03,
		eye = CFrame.new(-0.039, 4.59, 0.33),
		hold = Vector3.new(0.07, -0.06, -0.15),
		actionHold = Vector3.new(0.04, -0.03, -0.08),
		weaponBone = "Main_j_050",
		weaponMesh = "^Main_Glock",
		equip = "Draw",
		equipFrom = 0.25,
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
			hidden = {
				{ part = "^Mag1_", from = 0.214, to = 54 / 91 },
				{ part = "^Mag2_", from = 54 / 91, to = 1.01 },
			},
			worldScale = 2.5,
		},
		lockBack = { bones = { "Slide_j_00", "FireSelector_j_057", "SlideRelease_j_059" }, clip = "ReloadEmpty" },
		cuts = {
			{ clip = "Reload", bones = "^Mag[12]_", frame = 54 },
			{ clip = "ReloadEmpty", bones = "^Mag[12]_", frame = 54 },
		},
		surfaces = {
			Glock_D = "g17_glock",
			Bullet_9mm_D = "g17_round",
			Hand_D = "fab_arms_hand",
			Glove_D = "fab_arms_glove",
		},
	},
	RifleM4 = {
		asset = "m4",
		clips = "M4Clips",
		importScale = 0.03,
		eye = CFrame.new(-0.033, 4.618, 0.302),
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
		lockBack = { bones = { "Bolt_j_052", "BoltCatch_j_053" }, clip = "ReloadEmpty" },
		surfaces = {
			Hand_D = "fab_arms_hand",
			Glove_D = "fab_arms_glove",
		},
		surfacesReplace = true,
	},
	Shotgun = {
		asset = "shotgun",
		clips = "ShotgunClips",
		eye = CFrame.new(0, 4.72, -0.066),
		weaponBone = "Root_0106",
		weaponMesh = "Weapon",
		equip = "Equip",
		equipFrom = 0.15,
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
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
		surfaces = { Shirt_BlackCamo2 = "comando_shirt" },
		surfacesReplace = true,
	},
	SMG = {
		asset = "smg",
		clips = "SMGClips",
		eye = CFrame.new(0, 4.42, -0.066),
		hold = Vector3.new(0.08, -0.16, -0.08),
		restTilt = CFrame.Angles(-math.pi / 2, 0, 0),
		weaponBone = "UZI Body_0725",
		weaponMesh = "^UZI_UZI_0$",
		equip = "Equip",
		equipFrom = 0.45,
		equipTo = 0.9,
		idle = "Idle",
		move = "Walk",
		fire = "Fire",
		reload = { "Reload" },
		reloadEmpty = { "ReloadEmpty" },
		tactical = { clip = "Reload", to = 0.9, blendOut = 0.17 },
		empty = { clip = "ReloadEmpty", to = 0.9, blendOut = 0.2 },
		magDrop = {
			clip = "ReloadEmpty",
			at = 10 / 111,
			pieces = {
				{
					part = "^UZI_UZI Magazine",
					bone = "UZI Mag_0713",
					skin = { "UZI Mag_0713", "UZI Bullets_0734" },
					body = { center = Vector3.new(0.21, -1.127, 0), size = Vector3.new(0.081, 0.103, 0.589) },
					tuck = {
						["UZI Bullets_0734"] = {
							from = Vector3.new(-0.222, 1.134, 0.053),
							to = Vector3.new(0.21, -1.127, 0.22),
						},
					},
				},
			},
			hidden = { { part = "^UZI_UZI Magazine", from = 10 / 111, to = 25 / 111 } },
			worldScale = 2.5,
		},
		inspect = "Inspect",
		surfaces = { Mesh_Watch_0 = "uzi_watch" },
		surfacesReplace = true,
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
	Rifle = {
		asset = "g36c",
		clips = "G36CClips",
		importScale = 4.29,
		eye = CFrame.new(-0.12, 0.3, 0.75),
		hold = Vector3.new(0, 0, 0),
		actionHold = Vector3.new(0, 0, 0),
		weaponBone = "MainBody_Controller",
		weaponMesh = "^G36C2$",
		muzzle = { position = Vector3.new(-0.1192, -0.1566, -0.1111), direction = Vector3.new(-0.7709, -0.4465, -0.4542) },
		equip = "Draw",
		idle = "Idle",
		move = "Idle",
		fire = "Fire",
		reload = { "Reload" },
		reloadEmpty = { "ReloadEmpty" },
		tactical = { clip = "Reload", to = 0.95, blendOut = 0.2 },
		empty = { clip = "ReloadEmpty", to = 0.95, blendOut = 0.2 },
		phases = {
			Reload = { { at = 0.2, name = "MagOut" }, { at = 0.585, name = "MagIn" } },
			ReloadEmpty = {
				{ at = 0.17, name = "MagOut" },
				{ at = 0.49, name = "MagIn" },
				{ at = 0.77, name = "BoltBack" },
				{ at = 0.82, name = "BoltForward" },
			},
		},
		surfaces = {
			G36C = "comando_shirt",
			G36C2 = "g36c_body",
			G36C3 = "g36c_body",
		},
		surfacesReplace = true,
	},
} :: { [string]: ClassPack }

function ViewmodelPackConfig.get(class: string): ClassPack?
	return ViewmodelPackConfig.classes[class]
end

return ViewmodelPackConfig
