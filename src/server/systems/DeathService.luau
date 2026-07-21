--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local RewardMultiplier = require(ReplicatedStorage.Shared.util.RewardMultiplier)
local MissionState = require(script.Parent.MissionState)
local MissionConfig = require(script.Parent.MissionConfig)
local MissionService = require(script.Parent.MissionService)
local DistanceTracker = require(script.Parent.DistanceTracker)
local ZombieAI = require(script.Parent.ZombieAI)

local DeathService = {}

local SWARM_DURATION = 8
local CHOICE_TIMEOUT = 30
local MANUAL_RESPAWN_TIME = 600

type PendingDeath = {
	deathCFrame: CFrame,
	token: number,
}

local pending: { [Player]: PendingDeath } = {}
local tokenCounter = 0

local function computeRewards(player: Player)
	local distance = math.floor(DistanceTracker.getDistance(player))
	local multiplier = RewardMultiplier.compute(MissionConfig.getDifficulty().id, MissionState.getModifiers())
	return {
		distance = distance,
		xp = math.floor(distance / 5),
		credits = math.floor(distance / 10 * multiplier),
		multiplier = multiplier,
	}
end

local function getDeathCFrame(player: Player): CFrame
	local character = player.Character
	if character and character.PrimaryPart then
		return character:GetPivot()
	end
	return CFrame.new(0, 5, 0)
end

local function returnToHub(player: Player)
	pending[player] = nil
	MissionService.removeFromMission(player)
	player:SetAttribute("FlowPhase", "Hub")
	player:LoadCharacter()
end

local function reviveAtDeath(player: Player, deathCFrame: CFrame)
	pending[player] = nil
	if not MissionState.isParticipant(player) then
		returnToHub(player)
		return
	end
	player:LoadCharacter()
	local character = player.Character
	if character then
		character:PivotTo(deathCFrame + Vector3.new(0, 2, 0))
	end
	MissionService.watchPlayerDeath(player)
end

local function onPlayerDied(player: Player)
	if not MissionState.isParticipant(player) or pending[player] then
		return
	end

	local deathCFrame = getDeathCFrame(player)
	tokenCounter += 1
	local token = tokenCounter
	pending[player] = { deathCFrame = deathCFrame, token = token }

	ZombieAI.swarmCorpse(deathCFrame.Position, SWARM_DURATION)
	Remotes.getEvent(Remotes.Event.DeathBegan):FireClient(player, computeRewards(player))

	task.delay(CHOICE_TIMEOUT, function()
		local current = pending[player]
		if current and current.token == token then
			returnToHub(player)
		end
	end)
end

local function onChoice(player: Player, choice: any)
	local current = pending[player]
	if not current then
		return
	end
	if choice == "continue" then
		reviveAtDeath(player, current.deathCFrame)
	else
		returnToHub(player)
	end
end

function DeathService.init()
	Players.RespawnTime = MANUAL_RESPAWN_TIME
	MissionService.setDeathHandler(onPlayerDied)

	Remotes.getEvent(Remotes.Event.DeathChoice).OnServerEvent:Connect(onChoice)

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return DeathService
