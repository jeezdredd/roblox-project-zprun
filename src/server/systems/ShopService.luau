--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local SkillsConfig = require(ReplicatedStorage.Shared.config.SkillsConfig)
local SkinsConfig = require(ReplicatedStorage.Shared.config.SkinsConfig)
local ProfileManager = require(script.Parent.ProfileManager)
local SkinService = require(script.Parent.SkinService)
local WeaponService = require(script.Parent.WeaponService)

local ShopService = {}

export type CatalogEntry = {
	id: string,
	kind: string,
	displayName: string,
	description: string,
	price: number,
	level: number,
	maxLevel: number,
	owned: boolean,
	affordable: boolean,
	equipped: boolean,
	xp: number,
	xpNeeded: number,
}

export type Catalog = {
	vendorId: string,
	credits: number,
	entries: { CatalogEntry },
}

local REQUEST_COOLDOWN = 0.25
local lastRequestAt: { [Player]: number } = {}

local function throttle(player: Player): boolean
	local now = os.clock()
	if now - (lastRequestAt[player] or 0) < REQUEST_COOLDOWN then
		return false
	end
	lastRequestAt[player] = now
	return true
end

local function weaponEntries(data: ProfileManager.ProfileData): { CatalogEntry }
	local entries: { CatalogEntry } = {}
	for _, weaponId in WeaponsConfig.order do
		local config = WeaponsConfig.get(weaponId)
		if not config then
			continue
		end
		local progress = data.WeaponsOwned[weaponId]
		local owned = progress ~= nil
		local level = if progress then progress.level else 0
		local price = if owned then WeaponsConfig.upgradePrice(level) else config.price
		local maxed = owned and level >= WeaponsConfig.MAX_LEVEL
		local damage = WeaponsConfig.damageAt(config, math.max(level, 1))
		table.insert(entries, {
			id = weaponId,
			kind = if owned then "WeaponUpgrade" else "Weapon",
			displayName = config.displayName,
			description = string.format(
				"%s · %d dmg · %d rpm · mag %d",
				config.class,
				math.floor(damage + 0.5),
				math.floor(config.fireRate * 60),
				config.magSize
			),
			price = if maxed then 0 else price,
			level = level,
			maxLevel = WeaponsConfig.MAX_LEVEL,
			owned = owned,
			affordable = not maxed
				and data.Credits >= price
				and (not owned or (progress ~= nil and progress.xp >= WeaponsConfig.xpForLevel(level))),
			equipped = false,
			xp = if progress then progress.xp else 0,
			xpNeeded = WeaponsConfig.xpForLevel(math.max(level, 1)),
		})
	end
	return entries
end

local LOADOUT_SLOTS = 2

local function loadoutEntries(data: ProfileManager.ProfileData): { CatalogEntry }
	local entries: { CatalogEntry } = {}
	for _, weaponId in WeaponsConfig.order do
		local config = WeaponsConfig.get(weaponId)
		local progress = data.WeaponsOwned[weaponId]
		if not config or not progress then
			continue
		end
		local slot = table.find(data.Loadout, weaponId)
		table.insert(entries, {
			id = weaponId,
			kind = "Loadout",
			displayName = config.displayName,
			description = string.format("Loadout slot · %s · L%d", config.class, progress.level),
			price = 0,
			level = progress.level,
			maxLevel = 0,
			owned = true,
			affordable = true,
			equipped = slot ~= nil,
			xp = 0,
			xpNeeded = 0,
		})
	end
	return entries
end

local function skillEntries(data: ProfileManager.ProfileData): { CatalogEntry }
	local entries: { CatalogEntry } = {}
	for _, skillId in SkillsConfig.order do
		local config = SkillsConfig.get(skillId)
		if not config then
			continue
		end
		local level = data.SkillLevels[skillId] or 0
		local maxed = level >= config.maxLevel
		local price = SkillsConfig.priceFor(config, level)
		table.insert(entries, {
			id = skillId,
			kind = "Skill",
			displayName = config.displayName,
			description = string.format("%s (+%d %s per level)", config.description, config.valuePerLevel, config.unit),
			price = if maxed then 0 else price,
			level = level,
			maxLevel = config.maxLevel,
			owned = level > 0,
			affordable = not maxed and data.Credits >= price,
			equipped = false,
			xp = 0,
			xpNeeded = 0,
		})
	end
	return entries
end

local function skinEntries(data: ProfileManager.ProfileData): { CatalogEntry }
	local entries: { CatalogEntry } = {}
	for _, skinId in SkinsConfig.order do
		local config = SkinsConfig.skins[skinId]
		if not config then
			continue
		end
		local owned = data.SkinsOwned[skinId] == true or config.defaultOwned
		table.insert(entries, {
			id = skinId,
			kind = "Skin",
			displayName = config.displayName,
			description = config.description,
			price = if owned then 0 else config.price,
			level = 0,
			maxLevel = 0,
			owned = owned,
			affordable = owned or data.Credits >= config.price,
			equipped = data.EquippedSkin == skinId,
			xp = 0,
			xpNeeded = 0,
		})
	end
	return entries
end

local function buildCatalog(player: Player, vendorId: string): Catalog?
	local data = ProfileManager.get(player)
	if not data then
		return nil
	end
	local entries: { CatalogEntry }
	if vendorId == "Gunsmith" then
		entries = weaponEntries(data)
		for _, entry in loadoutEntries(data) do
			table.insert(entries, entry)
		end
	elseif vendorId == "WeaponDealer" then
		entries = weaponEntries(data)
	elseif vendorId == "Medbay" then
		entries = skillEntries(data)
	elseif vendorId == "Merchant" or vendorId == "BubblegumMachine" or vendorId == "SodaMachine" then
		entries = skinEntries(data)
	else
		return nil
	end
	return { vendorId = vendorId, credits = data.Credits, entries = entries }
end

local function purchaseWeapon(player: Player, data: ProfileManager.ProfileData, weaponId: string): (boolean, string)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return false, "Unknown weapon"
	end
	local progress = data.WeaponsOwned[weaponId]
	if not progress then
		if not ProfileManager.spendCredits(player, config.price) then
			return false, "Not enough credits"
		end
		data.WeaponsOwned[weaponId] = { level = 1, xp = 0 }
		return true, "Unlocked " .. config.displayName
	end
	if progress.level >= WeaponsConfig.MAX_LEVEL then
		return false, "Already at max level"
	end
	local xpNeeded = WeaponsConfig.xpForLevel(progress.level)
	if progress.xp < xpNeeded then
		return false, string.format("Needs %d more kills XP", xpNeeded - progress.xp)
	end
	local price = WeaponsConfig.upgradePrice(progress.level)
	if not ProfileManager.spendCredits(player, price) then
		return false, "Not enough credits"
	end
	progress.xp -= xpNeeded
	progress.level += 1
	return true, string.format("%s upgraded to L%d", config.displayName, progress.level)
end

local function purchaseSkill(player: Player, data: ProfileManager.ProfileData, skillId: string): (boolean, string)
	local config = SkillsConfig.get(skillId)
	if not config then
		return false, "Unknown skill"
	end
	local level = data.SkillLevels[skillId] or 0
	if level >= config.maxLevel then
		return false, "Already at max level"
	end
	local price = SkillsConfig.priceFor(config, level)
	if not ProfileManager.spendCredits(player, price) then
		return false, "Not enough credits"
	end
	data.SkillLevels[skillId] = level + 1
	return true, string.format("%s upgraded to L%d", config.displayName, level + 1)
end

local function purchaseSkin(player: Player, data: ProfileManager.ProfileData, skinId: string): (boolean, string)
	local config = SkinsConfig.skins[skinId]
	if not config then
		return false, "Unknown skin"
	end
	local owned = data.SkinsOwned[skinId] == true or config.defaultOwned
	if not owned then
		if not ProfileManager.spendCredits(player, config.price) then
			return false, "Not enough credits"
		end
		data.SkinsOwned[skinId] = true
	end
	SkinService.equip(player, skinId)
	return true, config.displayName .. " equipped"
end

local function toggleLoadout(data: ProfileManager.ProfileData, weaponId: string): (boolean, string)
	local config = WeaponsConfig.get(weaponId)
	if not config or not data.WeaponsOwned[weaponId] then
		return false, "Weapon not owned"
	end
	local slot = table.find(data.Loadout, weaponId)
	if slot then
		if #data.Loadout <= 1 then
			return false, "Need at least one weapon"
		end
		table.remove(data.Loadout, slot)
		return true, config.displayName .. " removed from loadout"
	end
	if #data.Loadout >= LOADOUT_SLOTS then
		table.remove(data.Loadout, 1)
	end
	table.insert(data.Loadout, weaponId)
	return true, config.displayName .. " added to loadout"
end

local function onPurchase(player: Player, vendorId: any, entryId: any, kind: any): any
	if typeof(vendorId) ~= "string" or typeof(entryId) ~= "string" then
		return { ok = false, message = "Bad request" }
	end
	if kind ~= nil and typeof(kind) ~= "string" then
		return { ok = false, message = "Bad request" }
	end
	if not throttle(player) then
		return { ok = false, message = "Slow down" }
	end
	local data = ProfileManager.get(player)
	if not data then
		return { ok = false, message = "Profile not loaded" }
	end

	local catalog = buildCatalog(player, vendorId)
	if not catalog then
		return { ok = false, message = "Unknown vendor" }
	end
	local matched: CatalogEntry? = nil
	for _, entry in catalog.entries do
		if entry.id == entryId and (kind == nil or entry.kind == kind) then
			matched = entry
			break
		end
	end
	if not matched then
		return { ok = false, message = "Item not sold here" }
	end

	local ok: boolean, message: string
	if matched.kind == "Loadout" then
		ok, message = toggleLoadout(data, entryId)
		if ok then
			WeaponService.applyLoadout(player)
		end
	elseif matched.kind == "Weapon" or matched.kind == "WeaponUpgrade" then
		ok, message = purchaseWeapon(player, data, entryId)
	elseif matched.kind == "Skill" then
		ok, message = purchaseSkill(player, data, entryId)
	else
		ok, message = purchaseSkin(player, data, entryId)
	end

	return { ok = ok, message = message, catalog = buildCatalog(player, vendorId) }
end

local function onCatalog(player: Player, vendorId: any): any
	if typeof(vendorId) ~= "string" then
		return nil
	end
	return buildCatalog(player, vendorId)
end

function ShopService.pushCatalog(player: Player, vendorId: string)
	local catalog = buildCatalog(player, vendorId)
	if catalog then
		Remotes.getEvent(Remotes.Event.ShopSync):FireClient(player, catalog)
	end
end

function ShopService.init()
	Remotes.getFunction(Remotes.Function.ShopCatalog).OnServerInvoke = onCatalog
	Remotes.getFunction(Remotes.Function.ShopPurchase).OnServerInvoke = onPurchase
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
end

return ShopService
