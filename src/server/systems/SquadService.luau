--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DifficultyConfig = require(ReplicatedStorage.Shared.config.DifficultyConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local ModifiersConfig = require(ReplicatedStorage.Shared.config.ModifiersConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local Squad = require(ReplicatedStorage.Shared.types.Squad)
local RewardMultiplier = require(ReplicatedStorage.Shared.util.RewardMultiplier)
local HangarBuilder = require(script.Parent.HangarBuilder)
local FriendCache = require(script.Parent.FriendCache)
local MissionState = require(script.Parent.MissionState)
local MissionService = require(script.Parent.MissionService)

type SquadRecord = {
	index: number,
	helicopter: HangarBuilder.Helicopter,
	state: Squad.SquadState,
	members: { Player },
	config: Squad.SquadConfig,
	countdownEndsAt: number?,
	launchThread: thread?,
}

local SquadService = {}

local MAX_CONFIG_RATE = 12
local RATE_WINDOW = 1

local squads: { [number]: SquadRecord } = {}
local playerSquad: { [Player]: number } = {}
local rateTimestamps: { [Player]: { number } } = {}

local function defaultConfig(): Squad.SquadConfig
	return {
		mapId = MapsConfig.DEFAULT_ID,
		difficultyId = GameConstants.DEFAULT_DIFFICULTY,
		privacy = "Public",
		modifierIds = {},
	}
end

local function checkRate(player: Player): boolean
	local now = os.clock()
	local stamps = rateTimestamps[player]
	if not stamps then
		stamps = {}
		rateTimestamps[player] = stamps
	end
	local kept: { number } = {}
	for _, timestamp in stamps do
		if now - timestamp < RATE_WINDOW then
			table.insert(kept, timestamp)
		end
	end
	rateTimestamps[player] = kept
	if #kept >= MAX_CONFIG_RATE then
		return false
	end
	table.insert(kept, now)
	return true
end

local function updateBillboard(squad: SquadRecord)
	local label = squad.helicopter.statusLabel
	if squad.state == "Empty" then
		label.Text = "EMPTY\nBoard to lead"
	elseif squad.state == "Launching" then
		label.Text = "LAUNCHING"
	else
		label.Text = string.format("SQUAD  %d/%d\n%s", #squad.members, HangarConfig.SQUAD_CAPACITY, squad.config.privacy)
	end
end

local function buildSnapshot(squad: SquadRecord): Squad.SquadSnapshot
	local members: { Squad.SquadMemberInfo } = {}
	for _, player in squad.members do
		table.insert(members, { userId = player.UserId, displayName = player.DisplayName })
	end
	local leaderUserId = if squad.members[1] then squad.members[1].UserId else 0
	return {
		squadIndex = squad.index,
		state = squad.state,
		config = squad.config,
		members = members,
		leaderUserId = leaderUserId,
		capacity = HangarConfig.SQUAD_CAPACITY,
		rewardMultiplier = RewardMultiplier.compute(squad.config.difficultyId, squad.config.modifierIds),
		countdownEndsAt = squad.countdownEndsAt,
	}
end

local function pushSnapshot(squad: SquadRecord)
	local snapshot = buildSnapshot(squad)
	local event = Remotes.getEvent(Remotes.Event.SquadSnapshot)
	for _, player in squad.members do
		event:FireClient(player, snapshot)
	end
	updateBillboard(squad)
end

local function resetSquad(squad: SquadRecord)
	if squad.launchThread then
		task.cancel(squad.launchThread)
		squad.launchThread = nil
	end
	squad.state = "Empty"
	squad.members = {}
	squad.config = defaultConfig()
	squad.countdownEndsAt = nil
	updateBillboard(squad)
end

local function abortLaunch(squad: SquadRecord)
	if squad.launchThread then
		task.cancel(squad.launchThread)
		squad.launchThread = nil
	end
	squad.countdownEndsAt = nil
	squad.state = "Filling"
end

local function isLeader(squad: SquadRecord, player: Player): boolean
	return squad.members[1] == player
end

local function canBoard(squad: SquadRecord, player: Player): boolean
	if squad.state ~= "Empty" and squad.state ~= "Filling" then
		return false
	end
	if #squad.members >= HangarConfig.SQUAD_CAPACITY then
		return false
	end
	if playerSquad[player] then
		return false
	end
	if #squad.members == 0 then
		return true
	end
	local leader = squad.members[1]
	if squad.config.privacy == "Solo" then
		return false
	end
	if squad.config.privacy == "FriendsOnly" then
		return FriendCache.areFriends(leader.UserId, player.UserId)
	end
	return true
end

local function board(squad: SquadRecord, player: Player)
	if not canBoard(squad, player) then
		return
	end
	table.insert(squad.members, player)
	playerSquad[player] = squad.index
	if squad.state == "Empty" then
		squad.state = "Filling"
	end
	pushSnapshot(squad)
end

local function leave(player: Player)
	local index = playerSquad[player]
	if not index then
		return
	end
	local squad = squads[index]
	playerSquad[player] = nil

	local position = table.find(squad.members, player)
	if position then
		table.remove(squad.members, position)
	end

	Remotes.getEvent(Remotes.Event.SquadSnapshot):FireClient(player, nil)

	if #squad.members == 0 then
		resetSquad(squad)
	else
		if squad.state == "Launching" then
			abortLaunch(squad)
		end
		pushSnapshot(squad)
	end
end

local function doLaunch(squad: SquadRecord)
	local members = table.clone(squad.members)
	local config = squad.config
	local seed = Random.new():NextInteger(1, 2147483646)
	local snapshotEvent = Remotes.getEvent(Remotes.Event.SquadSnapshot)
	for _, player in members do
		playerSquad[player] = nil
		snapshotEvent:FireClient(player, nil)
	end
	resetSquad(squad)
	MissionService.startSquad(members, config, seed)
end

local function requestLaunch(player: Player)
	local index = playerSquad[player]
	if not index then
		return
	end
	local squad = squads[index]
	if not isLeader(squad, player) or squad.state ~= "Filling" then
		return
	end
	if MissionState.isActive() then
		return
	end
	squad.state = "Launching"
	squad.countdownEndsAt = Workspace:GetServerTimeNow() + HangarConfig.LAUNCH_COUNTDOWN
	pushSnapshot(squad)
	squad.launchThread = task.delay(HangarConfig.LAUNCH_COUNTDOWN, function()
		squad.launchThread = nil
		doLaunch(squad)
	end)
end

local function updateConfig(player: Player, field: string, value: any)
	local index = playerSquad[player]
	if not index or not checkRate(player) then
		return
	end
	local squad = squads[index]
	if not isLeader(squad, player) or squad.state ~= "Filling" then
		return
	end

	if field == "mapId" then
		if typeof(value) == "string" and MapsConfig.isValid(value) then
			squad.config.mapId = value
		end
	elseif field == "difficultyId" then
		if typeof(value) == "string" and DifficultyConfig[value] then
			squad.config.difficultyId = value
		end
	elseif field == "privacy" then
		if value == "Solo" or value == "FriendsOnly" or value == "Public" then
			if value == "Solo" and #squad.members > 1 then
				return
			end
			squad.config.privacy = value
		end
	else
		return
	end
	pushSnapshot(squad)
end

local function toggleModifier(player: Player, modifierId: any)
	local index = playerSquad[player]
	if not index or not checkRate(player) then
		return
	end
	local squad = squads[index]
	if not isLeader(squad, player) or squad.state ~= "Filling" then
		return
	end
	if typeof(modifierId) ~= "string" or not ModifiersConfig.isValid(modifierId) then
		return
	end

	local existing = table.find(squad.config.modifierIds, modifierId)
	if existing then
		table.remove(squad.config.modifierIds, existing)
	else
		table.insert(squad.config.modifierIds, modifierId)
	end
	pushSnapshot(squad)
end

function SquadService.init(helicopters: { HangarBuilder.Helicopter })
	Remotes.init()

	for _, helicopter in helicopters do
		local squad: SquadRecord = {
			index = helicopter.index,
			helicopter = helicopter,
			state = "Empty",
			members = {},
			config = defaultConfig(),
			countdownEndsAt = nil,
			launchThread = nil,
		}
		squads[helicopter.index] = squad
		updateBillboard(squad)

		helicopter.prompt.Triggered:Connect(function(player)
			board(squad, player)
		end)
	end

	Remotes.getEvent(Remotes.Event.SquadLeave).OnServerEvent:Connect(function(player)
		leave(player)
	end)
	Remotes.getEvent(Remotes.Event.SquadLaunch).OnServerEvent:Connect(function(player)
		requestLaunch(player)
	end)
	Remotes.getEvent(Remotes.Event.SquadUpdateConfig).OnServerEvent:Connect(function(player, field, value)
		if typeof(field) == "string" then
			updateConfig(player, field, value)
		end
	end)
	Remotes.getEvent(Remotes.Event.SquadToggleModifier).OnServerEvent:Connect(function(player, modifierId)
		toggleModifier(player, modifierId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		rateTimestamps[player] = nil
		if playerSquad[player] then
			leave(player)
		end
	end)
end

return SquadService
