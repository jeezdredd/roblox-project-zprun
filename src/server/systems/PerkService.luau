--!strict

-- Perks on the server (docs/economy/run-economy-and-perks.md): the levels a player has
-- bought, the slots they own and the perks they equipped for the next run, all in the
-- profile; the Perk Lab catalog and purchases go through ShopService's remotes with
-- the vendor id "PerkLab". Slot 1 is free, slots 2 and 3 and every level cost Credits
-- through ProfileManager.spendCredits, never Robux. The equipped set is validated
-- against the slots and levels owned and cleared when the run ends; nothing reads the
-- effects yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerksConfig = require(ReplicatedStorage.Shared.config.PerksConfig)
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

-- Drops anything the profile no longer supports (a corrupted or older profile).
local function sanitize(data: ProfileManager.ProfileData)
	if not PerksConfig.validateEquipped(data.PerksEquipped, slotsOwned(data), data.PerkLevels) then
		data.PerksEquipped = {}
	end
end

local function publish(player: Player, data: ProfileManager.ProfileData)
	player:SetAttribute(SLOTS_ATTRIBUTE, slotsOwned(data))
	player:SetAttribute(EQUIPPED_ATTRIBUTE, table.concat(data.PerksEquipped, ","))
end

-- The Perk Lab catalog: the slots first, then every perk twice, its level purchase
-- (kind Perk) and its equip toggle (kind PerkEquip).
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
			local slot = table.find(data.PerksEquipped, id)
			table.insert(entries, {
				id = id,
				kind = "PerkEquip",
				displayName = config.displayName,
				description = if slot then string.format("Riding along in slot %d", slot) else "Take it on the next run",
				price = 0,
				level = level,
				maxLevel = 0,
				owned = true,
				affordable = true,
				equipped = slot ~= nil,
				xp = 0,
				xpNeeded = 0,
			})
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

-- Equips or unequips a perk for the next run, within the slots owned.
function PerkService.toggleEquip(player: Player, data: ProfileManager.ProfileData, perkId: string): (boolean, string)
	local config = PerksConfig.get(perkId)
	if not config then
		return false, "Unknown perk"
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

-- The perks riding along on this run, in slot order (validated).
function PerkService.equipped(player: Player): { string }
	local data = ProfileManager.get(player)
	if not data then
		return {}
	end
	sanitize(data)
	return table.clone(data.PerksEquipped)
end

-- The run is over: the choice is lost with it, the levels and slots stay.
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
