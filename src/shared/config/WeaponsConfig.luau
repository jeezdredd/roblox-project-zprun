--!strict

export type WeaponConfig = {
	id: string,
	displayName: string,
	class: string,
	damage: number,
	headshotMultiplier: number,
	fireRate: number,
	auto: boolean,
	magSize: number,
	reserveMags: number,
	spreadDeg: number,
	range: number,
	pellets: number,
	reloadTime: number,
	price: number,
	shotVolume: number,
	shotPitch: number,
	shotSound: string,
	closeSounds: { string },
	recoilKick: number,
	recoilSnap: number,
	recoilStiffness: number,
	recoilDamping: number,
	cameraKick: number,
}

local WeaponsConfig = {}

WeaponsConfig.order = { "Pistol", "SMG", "Shotgun", "Rifle" }

WeaponsConfig.weapons = {
	Pistol = {
		id = "Pistol",
		displayName = "M9 Sidearm",
		class = "Pistol",
		damage = 34,
		headshotMultiplier = 2,
		fireRate = 5,
		auto = false,
		magSize = 12,
		reserveMags = 4,
		spreadDeg = 1.1,
		range = 250,
		pellets = 1,
		reloadTime = 1.6,
		price = 0,
		shotVolume = 0.55,
		shotPitch = 1,
		shotSound = "shot_pistol",
		closeSounds = { "close_pistol", "close_pistol_02", "close_pistol_03" },
		recoilKick = 0.7,
		recoilSnap = 0.35,
		recoilStiffness = 240,
		recoilDamping = 22,
		cameraKick = 0.3,
	},
	SMG = {
		id = "SMG",
		displayName = "K10 SMG",
		class = "SMG",
		damage = 16,
		headshotMultiplier = 1.8,
		fireRate = 11,
		auto = true,
		magSize = 30,
		reserveMags = 4,
		spreadDeg = 2.6,
		range = 200,
		pellets = 1,
		reloadTime = 2,
		price = 900,
		shotVolume = 0.5,
		shotPitch = 1.12,
		shotSound = "shot_smg",
		closeSounds = { "close_smg", "close_smg_02", "close_smg_03" },
		recoilKick = 0.45,
		recoilSnap = 0.22,
		recoilStiffness = 260,
		recoilDamping = 24,
		cameraKick = 0.2,
	},
	Shotgun = {
		id = "Shotgun",
		displayName = "S870 Shotgun",
		class = "Shotgun",
		damage = 12,
		headshotMultiplier = 1.5,
		fireRate = 1.5,
		auto = false,
		magSize = 6,
		reserveMags = 4,
		spreadDeg = 5.5,
		range = 120,
		pellets = 8,
		reloadTime = 2.6,
		price = 1600,
		shotVolume = 0.72,
		shotPitch = 1,
		shotSound = "shot_shotgun",
		closeSounds = { "close_shotgun", "close_shotgun_02", "close_shotgun_03" },
		recoilKick = 1.5,
		recoilSnap = 0.7,
		recoilStiffness = 150,
		recoilDamping = 16,
		cameraKick = 0.75,
	},
	Rifle = {
		id = "Rifle",
		displayName = "R4 Carbine",
		class = "Rifle",
		damage = 30,
		headshotMultiplier = 2,
		fireRate = 8,
		auto = true,
		magSize = 30,
		reserveMags = 5,
		spreadDeg = 1.5,
		range = 350,
		pellets = 1,
		reloadTime = 2.2,
		price = 2600,
		shotVolume = 0.65,
		shotPitch = 1,
		shotSound = "shot_rifle",
		closeSounds = { "close_rifle", "close_rifle_02", "close_rifle_03" },
		recoilKick = 0.75,
		recoilSnap = 0.4,
		recoilStiffness = 200,
		recoilDamping = 19,
		cameraKick = 0.4,
	},
} :: { [string]: WeaponConfig }

WeaponsConfig.MAX_LEVEL = 5
WeaponsConfig.UPGRADE_BASE_PRICE = 400
WeaponsConfig.UPGRADE_PRICE_STEP = 350
WeaponsConfig.DAMAGE_PER_LEVEL = 0.08
WeaponsConfig.XP_PER_KILL = 6

function WeaponsConfig.get(id: string): WeaponConfig?
	return WeaponsConfig.weapons[id]
end

function WeaponsConfig.upgradePrice(level: number): number
	return WeaponsConfig.UPGRADE_BASE_PRICE + WeaponsConfig.UPGRADE_PRICE_STEP * math.max(level - 1, 0)
end

function WeaponsConfig.xpForLevel(level: number): number
	return 40 * level * level
end

function WeaponsConfig.damageAt(config: WeaponConfig, level: number): number
	return config.damage * (1 + WeaponsConfig.DAMAGE_PER_LEVEL * math.max(level - 1, 0))
end

return table.freeze(WeaponsConfig)
