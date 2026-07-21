--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local Flow = require(ReplicatedStorage.Shared.types.Flow)
local MissionState = require(script.Parent.MissionState)

local PHASE_ATTRIBUTE = "FlowPhase"

local FlowService = {}

local function applyHumanoidConfig(character: Model, phase: Flow.FlowPhase)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if phase == "Mission" then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = 0
	else
		humanoid.WalkSpeed = GameConstants.HUB_WALK_SPEED
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = GameConstants.HUB_JUMP_HEIGHT
	end
end

function FlowService.getPhase(player: Player): Flow.FlowPhase
	if player:GetAttribute(PHASE_ATTRIBUTE) == "Mission" then
		return "Mission"
	end
	return "Hub"
end

function FlowService.setPhase(player: Player, phase: Flow.FlowPhase)
	player:SetAttribute(PHASE_ATTRIBUTE, phase)
	local character = player.Character
	if character then
		applyHumanoidConfig(character, phase)
	end
end

local function moveToHub(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and root:IsA("BasePart") then
		character:PivotTo(HangarConfig.HUB_SPAWN_CFRAME)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local phase: Flow.FlowPhase = if MissionState.isParticipant(player) then "Mission" else "Hub"
	player:SetAttribute(PHASE_ATTRIBUTE, phase)
	applyHumanoidConfig(character, phase)
	if phase == "Hub" then
		task.spawn(moveToHub, character)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(PHASE_ATTRIBUTE, "Hub")
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function FlowService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return FlowService
