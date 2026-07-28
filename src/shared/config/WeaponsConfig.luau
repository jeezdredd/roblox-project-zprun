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
	closeSound: string,
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
		closeSound = "close_pistol",
		recoilKick = 1.6,
		recoilSnap = 0.9,
		recoilStiffness = 240,
		recoilDamping = 22,
		cameraKick = 0.9,
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
		closeSound = "close_smg",
		recoilKick = 1,
		recoilSnap = 0.55,
		recoilStiffness = 260,
		recoilDamping = 24,
		cameraKick = 0.6,
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
		closeSound = "close_shotgun",
		recoilKick = 3.4,
		recoilSnap = 1.8,
		recoilStiffness = 150,
		recoilDamping = 16,
		cameraKick = 2.2,
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
		closeSound = "close_rifle",
		recoilKick = 1.7,
		recoilSnap = 1,
		recoilStiffness = 200,
		recoilDamping = 19,
		cameraKick = 1.2,
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
