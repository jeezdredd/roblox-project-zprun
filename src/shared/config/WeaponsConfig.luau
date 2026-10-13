--!strict

export type ReloadStyle = "magazine" | "shell"

export type ShellReload = {
	start: number,
	perShell: number,
	addAt: number,
	finish: number,
	chamber: number,
	exit: number,
}

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
	reloadTimeEmpty: number,
	ammoAddTactical: number,
	ammoAddEmpty: number,
	reloadStyle: ReloadStyle,
	shellReload: ShellReload?,
	drawTime: number,
	casing: string,
	ejectOnFire: boolean,
	lowAmmo: number,
	price: number,
	shotVolume: number,
	shotPitch: number,
	shotSound: string,
	closeSounds: { string },
	midSound: string,
	farSound: string,
	recoilKick: number,
	recoilSnap: number,
	recoilStiffness: number,
	recoilDamping: number,
	cameraKick: number,
}

local WeaponsConfig = {}

WeaponsConfig.ALL_WEAPONS_UNLOCKED = true

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
		reloadTime = 2.1,
		reloadTimeEmpty = 2.4,
		ammoAddTactical = 1.52,
		ammoAddEmpty = 1.84,
		reloadStyle = "magazine",
		drawTime = 0.65,
		casing = "9mm",
		ejectOnFire = true,
		lowAmmo = 3,
		price = 0,
		shotVolume = 0.88,
		shotPitch = 1,
		shotSound = "shot_pistol",
		closeSounds = { "close_pistol", "close_pistol_02", "close_pistol_03" },
		midSound = "mid_pistol",
		farSound = "far_pistol",
		recoilKick = 0.7,
		recoilSnap = 0.35,
		recoilStiffness = 240,
		recoilDamping = 28,
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
		reloadTime = 2.0,
		reloadTimeEmpty = 3.53,
		ammoAddTactical = 1.04,
		ammoAddEmpty = 2.59,
		reloadStyle = "magazine",
		drawTime = 0.6,
		casing = "9mm",
		ejectOnFire = true,
		lowAmmo = 8,
		price = 900,
		shotVolume = 0.8,
		shotPitch = 1,
		shotSound = "shot_smg",
		closeSounds = { "close_mp7" },
		midSound = "mid_smg",
		farSound = "far_smg",
		recoilKick = 0.45,
		recoilSnap = 0.22,
		recoilStiffness = 260,
		recoilDamping = 29,
		cameraKick = 0.2,
	},
	Shotgun = {
		id = "Shotgun",
		displayName = "S870 Shotgun",
		class = "Shotgun",
		damage = 12,
		headshotMultiplier = 1.5,
		fireRate = 1.25,
		auto = false,
		magSize = 6,
		reserveMags = 4,
		spreadDeg = 5.5,
		range = 120,
		pellets = 8,
		reloadTime = 2.35,
		reloadTimeEmpty = 2.9,
		ammoAddTactical = 1.39,
		ammoAddEmpty = 1.39,
		reloadStyle = "shell",
		shellReload = {
			start = 0.45,
			perShell = 0.9,
			addAt = 0.64,
			finish = 0.7,
			chamber = 0.55,
			exit = 0.2,
		},
		drawTime = 0.75,
		casing = "12ga",
		ejectOnFire = false,
		lowAmmo = 2,
		price = 1600,
		shotVolume = 1.15,
		shotPitch = 1,
		shotSound = "shot_shotgun",
		closeSounds = { "close_m590" },
		midSound = "mid_shotgun",
		farSound = "far_shotgun",
		recoilKick = 1.5,
		recoilSnap = 0.7,
		recoilStiffness = 150,
		recoilDamping = 22,
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
		reloadTime = 2.45,
		reloadTimeEmpty = 3.4,
		ammoAddTactical = 1.79,
		ammoAddEmpty = 2.63,
		reloadStyle = "magazine",
		drawTime = 0.85,
		casing = "762x39",
		ejectOnFire = true,
		lowAmmo = 8,
		price = 2600,
		shotVolume = 1.04,
		shotPitch = 1,
		shotSound = "shot_rifle",
		closeSounds = { "close_g36c" },
		midSound = "mid_rifle",
		farSound = "far_rifle",
		recoilKick = 0.75,
		recoilSnap = 0.4,
		recoilStiffness = 200,
		recoilDamping = 25,
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

function WeaponsConfig.magazineReload(config: WeaponConfig, empty: boolean, scale: number): (number, number)
	if empty then
		return config.ammoAddEmpty * scale, config.reloadTimeEmpty * scale
	end
	return config.ammoAddTactical * scale, config.reloadTime * scale
end

function WeaponsConfig.shellAddTime(config: WeaponConfig, index: number, scale: number): number
	local shell = config.shellReload
	if not shell then
		return config.ammoAddTactical * scale
	end
	return (shell.start + (index - 1) * shell.perShell + shell.addAt) * scale
end

function WeaponsConfig.shellReloadTime(config: WeaponConfig, shells: number, empty: boolean, scale: number): number
	local shell = config.shellReload
	if not shell then
		return (if empty then config.reloadTimeEmpty else config.reloadTime) * scale
	end
	local total = shell.start + shells * shell.perShell + shell.finish
	if empty then
		total += shell.chamber
	end
	return total * scale
end

function WeaponsConfig.shellCancel(config: WeaponConfig, elapsed: number, shells: number, empty: boolean, scale: number): (number, number)
	local shell = config.shellReload
	local total = WeaponsConfig.shellReloadTime(config, shells, empty, scale)
	if not shell then
		return shells, total
	end
	local start = shell.start * scale
	local perShell = shell.perShell * scale
	local addAt = shell.addAt * scale
	local exit = shell.exit * scale
	local chamber = if empty then shell.chamber * scale else 0
	if elapsed < start then
		return 0, elapsed + exit + chamber
	end
	local cycle = math.floor((elapsed - start) / perShell)
	if cycle >= shells then
		return shells, total
	end
	local inCycle = elapsed - start - cycle * perShell
	if inCycle < addAt then
		return cycle + 1, start + cycle * perShell + addAt + exit + chamber
	end
	return cycle + 1, elapsed + exit + chamber
end

return table.freeze(WeaponsConfig)
