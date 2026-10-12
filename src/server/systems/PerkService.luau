--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerksConfig = require(ReplicatedStorage.Shared.config.PerksConfig)
local LoadoutWindow = require(script.Parent.LoadoutWindow)
local ProfileManager = require(script.Parent.ProfileManager)

local PerkService = {}

PerkService.VENDOR_ID = "PerkLab"

local EQUIPPED_ATTRIBUTE = "PerksEquipped"
local SLOTS_ATTRIBUTE = "PerkSlots"

export type Entry = {
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

local function slotsOwned(data: ProfileManager.ProfileData): number
	return math.clamp(data.PerkSlots, 1, PerksConfig.MAX_SLOTS)
end

local function sanitize(data: ProfileManager.ProfileData)
	if not PerksConfig.validateEquipped(data.PerksEquipped, slotsOwned(data), data.PerkLevels) then
		data.PerksEquipped = {}
	end
end

local function publish(player: Player, data: ProfileManager.ProfileData)
	player:SetAttribute(SLOTS_ATTRIBUTE, slotsOwned(data))
	player:SetAttribute(EQUIPPED_ATTRIBUTE, table.concat(data.PerksEquipped, ","))
end

local function equipEntry(data: ProfileManager.ProfileData, id: string, displayName: string, level: number): Entry
	local slot = table.find(data.PerksEquipped, id)
	return {
		id = id,
		kind = "PerkEquip",
		displayName = displayName,
		description = if slot then string.format("Riding along in slot %d", slot) else "Take it on the next run",
		price = 0,
		level = level,
		maxLevel = 0,
		owned = true,
		affordable = true,
		equipped = slot ~= nil,
		xp = 0,
		xpNeeded = 0,
	}
end

function PerkService.entries(data: ProfileManager.ProfileData): { Entry }
	sanitize(data)
	local entries: { Entry } = {}
	local owned = slotsOwned(data)
	local slotPrice = PerksConfig.slotPrice(owned)
	table.insert(entries, {
		id = "Slot",
		kind = "PerkSlot",
		displayName = "Perk slots",
		description = if slotPrice
			then string.format("%d of %d owned · slot %d unlocks another perk for the run", owned, PerksConfig.MAX_SLOTS, owned + 1)
			else string.format("%d of %d owned", owned, PerksConfig.MAX_SLOTS),
		price = slotPrice or 0,
		level = owned,
		maxLevel = PerksConfig.MAX_SLOTS,
		owned = true,
		affordable = slotPrice ~= nil and data.Credits >= slotPrice,
		equipped = false,
		xp = 0,
		xpNeeded = 0,
	})
	for _, id in PerksConfig.order do
		local config = PerksConfig.get(id)
		if not config then
			continue
		end
		local level = data.PerkLevels[id] or 0
		local price = PerksConfig.priceFor(config, level)
		local value = PerksConfig.valueAt(config, math.max(level, 1))
		table.insert(entries, {
			id = id,
			kind = "Perk",
			displayName = config.displayName,
			description = string.format("%s (%s %s at L%d)", config.description, tostring(value), config.unit, math.max(level, 1)),
			price = price or 0,
			level = level,
			maxLevel = config.maxLevel,
			owned = level > 0,
			affordable = price ~= nil and data.Credits >= price,
			equipped = false,
			xp = 0,
			xpNeeded = 0,
		})
		if level > 0 then
			table.insert(entries, equipEntry(data, id, config.displayName, level))
		end
	end
	return entries
end

function PerkService.equipEntries(data: ProfileManager.ProfileData): { Entry }
	sanitize(data)
	local entries: { Entry } = {}
	for _, id in PerksConfig.order do
		local config = PerksConfig.get(id)
		local level = data.PerkLevels[id] or 0
		if config and level > 0 then
			table.insert(entries, equipEntry(data, id, config.displayName, level))
		end
	end
	return entries
end

function PerkService.purchaseSlot(player: Player, data: ProfileManager.ProfileData): (boolean, string)
	local owned = slotsOwned(data)
	local price = PerksConfig.slotPrice(owned)
	if not price then
		return false, "Every slot is owned"
	end
	if not ProfileManager.spendCredits(player, price) then
		return false, "Not enough credits"
	end
	data.PerkSlots = owned + 1
	publish(player, data)
	return true, string.format("Perk slot %d unlocked", owned + 1)
end

function PerkService.purchaseLevel(player: Player, data: ProfileManager.ProfileData, perkId: string): (boolean, string)
	local config = PerksConfig.get(perkId)
	if not config then
		return false, "Unknown perk"
	end
	local level = data.PerkLevels[perkId] or 0
	local price = PerksConfig.priceFor(config, level)
	if not price then
		return false, "Already at max level"
	end
	if not ProfileManager.spendCredits(player, price) then
		return false, "Not enough credits"
	end
	data.PerkLevels[perkId] = level + 1
	return true, string.format("%s at L%d", config.displayName, level + 1)
end

function PerkService.toggleEquip(player: Player, data: ProfileManager.ProfileData, perkId: string): (boolean, string)
	local config = PerksConfig.get(perkId)
	if not config then
		return false, "Unknown perk"
	end
	if not LoadoutWindow.isOpen(player) then
		return false, "Perks are set before the run"
	end
	sanitize(data)
	local slot = table.find(data.PerksEquipped, perkId)
	if slot then
		table.remove(data.PerksEquipped, slot)
		publish(player, data)
		return true, config.displayName .. " left behind"
	end
	local proposed = table.clone(data.PerksEquipped)
	table.insert(proposed, perkId)
	if not PerksConfig.validateEquipped(proposed, slotsOwned(data), data.PerkLevels) then
		if (data.PerkLevels[perkId] or 0) <= 0 then
			return false, "Unlock a level first"
		end
		return false, string.format("All %d slots are taken", slotsOwned(data))
	end
	data.PerksEquipped = proposed
	publish(player, data)
	return true, config.displayName .. " equipped for the next run"
end

function PerkService.equipped(player: Player): { string }
	local data = ProfileManager.get(player)
	if not data then
		return {}
	end
	sanitize(data)
	return table.clone(data.PerksEquipped)
end

function PerkService.onRunEnd(player: Player)
	local data = ProfileManager.get(player)
	if not data then
		return
	end
	data.PerksEquipped = {}
	publish(player, data)
end

function PerkService.init()
	ProfileManager.onLoaded(function(player, data)
		sanitize(data)
		publish(player, data)
	end)
end

return PerkService
