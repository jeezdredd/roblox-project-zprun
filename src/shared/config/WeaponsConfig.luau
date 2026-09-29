--!strict

-- Reload timings follow the MW model: a reload has a total length and an ammo-add
-- moment (the magazine seats, the counter updates). Only the tail after ammo-add can be
-- cut by firing; cancelling before it keeps the old count. The server (WeaponService)
-- and the client prediction (WeaponController) both read the helpers at the bottom of
-- this file, so they share one timeline and cannot drift apart.
--
-- The seconds here are matched to the baked pack clips (ViewmodelPackConfig), which are
-- played at natural speed or at most about 1.3x; see the notes per weapon. Change a
-- time here and the clip speed follows, but keep ammo-add on the clip's MagIn (or
-- SlideRelease / BoltForward) marker or the counter will tick before the hands do:
-- ammo-add = marker / cut end * (total - blendOut), the cut starting at 0.
-- Ammo-add times re-derived 2026-09-29 from the cut points and markers measured then
-- (method in ViewmodelPackConfig); the reload totals were kept.

export type ReloadStyle = "magazine" | "shell"

-- Pump shotgun reload, all in seconds (scaled together by SkillEffects.reloadScale).
export type ShellReload = {
	-- IdleToReload: the gun rolls over to the loading port
	start: number,
	-- one shell cycle: hand to the carrier, shell into the tube, hand back
	perShell: number,
	-- inside a cycle, when the shell is seated and counted
	addAt: number,
	-- ReloadToIdle
	finish: number,
	-- pump appended when the reload started from empty (nothing chambered)
	chamber: number,
	-- fast exit when fire interrupts the loop, after the shell in hand is seated
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
	-- tactical reload (rounds left in the mag): seconds until the weapon is ready
	reloadTime: number,
	-- empty reload: adds the chambering action (bolt rack, slide release, pump)
	reloadTimeEmpty: number,
	-- seconds into the reload when the rounds are counted
	ammoAddTactical: number,
	ammoAddEmpty: number,
	reloadStyle: ReloadStyle,
	shellReload: ShellReload?,
	-- seconds after an equip before the weapon can fire (the Equip clip plays at natural
	-- speed and is longer; firing cuts its tail)
	drawTime: number,
	-- WeaponVfx casing model and WeaponSfx landing sound set
	casing: string,
	-- false for the pump: the hull comes out on the pump stroke, not on the shot
	ejectOnFire: boolean,
	-- rounds left at or below which each shot adds the low-ammo spring layer
	lowAmmo: number,
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

-- TEMPORARY, for testing only: number keys 1-5 select any weapon in `order` and the
-- server skips the ownership check on equip. Set to false before shipping.
WeaponsConfig.ALL_WEAPONS_UNLOCKED = true

WeaponsConfig.order = { "Pistol", "SMG", "Shotgun", "Rifle" }

WeaponsConfig.weapons = {
	-- Pack Reload clip: 2.708 s, MagOut 0.17, MagIn 0.67, SlideRelease (right thumb)
	-- 0.70, gun back up by 0.84, no slide motion. Both cuts play 0-0.84 and blend to idle
	-- in 0.2 s: tactical at 1.2x (MagIn at 1.52 s), empty at 1.03x (SlideRelease at
	-- 1.84 s).
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
		shotVolume = 0.55,
		shotPitch = 1,
		shotSound = "shot_pistol",
		closeSounds = { "close_pistol", "close_pistol_02", "close_pistol_03" },
		recoilKick = 0.7,
		recoilSnap = 0.35,
		recoilStiffness = 240,
		recoilDamping = 28,
		cameraKick = 0.3,
	},
	-- Pack (Uzi) clips at natural speed. Tactical: Reload (2.033 s) to 0.9, MagIn at 0.51
	-- (1.04 s), then a 0.17 s blend to idle. Empty: ReloadEmpty (3.7 s) to 0.9 with a
	-- 0.2 s blend; MagIn at 0.35 (1.30 s), the open-bolt top-knob cock BoltBack 0.62,
	-- BoltForward 0.70 (2.59 s), where the rounds are counted.
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
		shotVolume = 0.5,
		shotPitch = 1.12,
		shotSound = "shot_smg",
		closeSounds = { "close_smg", "close_smg_02", "close_smg_03" },
		recoilKick = 0.45,
		recoilSnap = 0.22,
		recoilStiffness = 260,
		recoilDamping = 29,
		cameraKick = 0.2,
	},
	-- Pack clips: IdleToReload 1.0 s (1.33x), Reload 1.667 s one shell with ShellIn at
	-- 0.70, looped over 0.24-0.89 (1.2x, seated 0.64 s into the cycle), ReloadToIdle
	-- 0.917 s (1.31x), AccionFire pump to 0.51 as the chamber stroke (1.16x).
	-- fireRate 1.25 lets the trimmed Fire (recoil only) plus the AccionFire pump up to
	-- followReady close at 1.29x inside one interval; 1.5 would need 1.54x, over the
	-- 1.5x cap.
	-- reloadTime / ammoAdd* below describe a one-shell reload for anything that reads
	-- them generically; the shell loop itself runs on shellReload.
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
			start = 0.75,
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
		shotVolume = 0.72,
		shotPitch = 1,
		shotSound = "shot_shotgun",
		closeSounds = { "close_shotgun", "close_shotgun_02", "close_shotgun_03" },
		recoilKick = 1.5,
		recoilSnap = 0.7,
		recoilStiffness = 150,
		recoilDamping = 22,
		cameraKick = 0.75,
	},
	-- Pack (AK) Reload clip: 4.583 s, MagOut 0.20, MagIn 0.46, BoltBack 0.64,
	-- BoltForward 0.68. Tactical stops at 0.54, before the hand sweeps to the charging
	-- handle, at 1.18x (MagIn at 1.79 s) and blends to idle in 0.35 s. Empty keeps the
	-- charging-handle rack (an AK has no bolt hold-open), plays to 0.83 at 1.19x
	-- (BoltForward at 2.63 s) and blends out in 0.2 s.
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
		shotVolume = 0.65,
		shotPitch = 1,
		shotSound = "shot_rifle",
		closeSounds = { "close_rifle", "close_rifle_02", "close_rifle_03" },
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

-- Reload timeline helpers. Every time is in seconds from the moment the reload started
-- and already multiplied by `scale` (SkillEffects.reloadScale, 1 without the skill).

-- Magazine reload: (ammo-add time, total time).
function WeaponsConfig.magazineReload(config: WeaponConfig, empty: boolean, scale: number): (number, number)
	if empty then
		return config.ammoAddEmpty * scale, config.reloadTimeEmpty * scale
	end
	return config.ammoAddTactical * scale, config.reloadTime * scale
end

-- Shell reload: when shell `index` (1-based) is counted.
function WeaponsConfig.shellAddTime(config: WeaponConfig, index: number, scale: number): number
	local shell = config.shellReload
	if not shell then
		return config.ammoAddTactical * scale
	end
	return (shell.start + (index - 1) * shell.perShell + shell.addAt) * scale
end

-- Shell reload: total time for `shells` shells, with the chambering pump from empty.
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

-- Fire interrupting a shell reload `elapsed` seconds in. The shell already in the hand
-- is still seated at its add point, then a fast exit (plus the pump if nothing was
-- chambered). Returns how many shells end up loaded in total and when the weapon is
-- ready again (seconds from the reload start). Once the loop is over (ReloadToIdle is
-- already playing) nothing changes.
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
		-- still rolling the gun over: no shell in hand yet
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
