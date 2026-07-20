--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local MissionState = require(script.Parent.MissionState)
local FlowService = require(script.Parent.FlowService)
local TrackBuilder = require(script.Parent.TrackBuilder)
local ChunkSpawner = require(script.Parent.ChunkSpawner)
local ZombieAI = require(script.Parent.ZombieAI)
local DistanceTracker = require(script.Parent.DistanceTracker)

local MissionService = {}

local diedConnections: { [Player]: RBXScriptConnection } = {}

local function disconnectDied(player: Player)
	local connection = diedConnections[player]
	if connection then
		connection:Disconnect()
		diedConnections[player] = nil
	end
end

local function teleportCharacter(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(cframe)
	end
end

local function tearDownIfEmpty()
	if MissionState.countParticipants() > 0 then
		return
	end
	MissionState.setActive(false)
	ChunkSpawner.clear()
	ZombieAI.clearAll()
	TrackBuilder.clear()
end

function MissionService.start(player: Player)
	if MissionState.isParticipant(player) then
		return
	end

	if not MissionState.isActive() then
		MissionState.setActive(true)
		TrackBuilder.build()
		ChunkSpawner.reset()
	end

	MissionState.addParticipant(player)
	DistanceTracker.beginRun(player)
	FlowService.setPhase(player, "Mission")
	teleportCharacter(player, HangarConfig.RUN_START_CFRAME)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		disconnectDied(player)
		diedConnections[player] = humanoid.Died:Connect(function()
			MissionService.stop(player)
		end)
	end
end

function MissionService.stop(player: Player)
	if not MissionState.isParticipant(player) then
		return
	end

	disconnectDied(player)
	MissionState.removeParticipant(player)
	DistanceTracker.endRun(player)
	FlowService.setPhase(player, "Hub")
	teleportCharacter(player, HangarConfig.HUB_SPAWN_CFRAME)
	tearDownIfEmpty()
end

function MissionService.bindDeployPrompt(prompt: ProximityPrompt)
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local consolePosition = HangarConfig.DEPLOY_CONSOLE_CFRAME.Position
		if (root.Position - consolePosition).Magnitude > HangarConfig.DEPLOY_PROMPT_DISTANCE + 4 then
			return
		end
		MissionService.start(player)
	end)
end

function MissionService.init()
	Players.PlayerRemoving:Connect(function(player)
		disconnectDied(player)
		if MissionState.isParticipant(player) then
			MissionState.removeParticipant(player)
			DistanceTracker.endRun(player)
			tearDownIfEmpty()
		end
	end)
end

return MissionService
