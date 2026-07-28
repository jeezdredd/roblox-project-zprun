--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local RewardMultiplier = require(ReplicatedStorage.Shared.util.RewardMultiplier)
local MissionState = require(script.Parent.MissionState)
local MissionConfig = require(script.Parent.MissionConfig)
local MissionService = require(script.Parent.MissionService)
local DistanceTracker = require(script.Parent.DistanceTracker)
local ProfileManager = require(script.Parent.ProfileManager)
local MonetizationService = require(script.Parent.MonetizationService)
local ProductsConfig = require(ReplicatedStorage.Shared.config.ProductsConfig)
local ZombieAI = require(script.Parent.ZombieAI)

local DeathService = {}

local SWARM_DURATION = 8
local CHOICE_TIMEOUT = 30
local MANUAL_RESPAWN_TIME = 600
local HUB_RESPAWN_DELAY = 3
local REVIVES_PER_RUN = 1
local REVIVE_PROTECTION_TIME = 3

type PendingDeath = {
	deathCFrame: CFrame,
	token: number,
}

local pending: { [Player]: PendingDeath } = {}
local revivesUsed: { [Player]: number } = {}
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
	revivesUsed[player] = nil
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
	ZombieAI.clearLure()
	player:LoadCharacter()
	local character = player.Character
	if character then
		character:PivotTo(deathCFrame + Vector3.new(0, 2, 0))
		local forceField = Instance.new("ForceField")
		forceField.Parent = character
		task.delay(REVIVE_PROTECTION_TIME, function()
			forceField:Destroy()
		end)
	end
	MissionService.watchPlayerDeath(player)
end

local function poseCorpse(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	root.Anchored = true
	local position = root.Position
	local _, yaw = root.CFrame:ToOrientation()
	local lying = CFrame.new(position.X, 1.15, position.Z)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(math.pi / 2, 0, 0)
	TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = lying,
	}):Play()
end

local function onPlayerDied(player: Player)
	if not MissionState.isParticipant(player) or pending[player] then
		return
	end

	local deathCFrame = getDeathCFrame(player)
	poseCorpse(player)
	tokenCounter += 1
	local token = tokenCounter
	pending[player] = { deathCFrame = deathCFrame, token = token }

	ZombieAI.swarmCorpse(deathCFrame.Position, SWARM_DURATION)
	task.delay(1.1, function()
		ZombieAI.feedOnCorpse(deathCFrame.Position, SWARM_DURATION, 5)
	end)

	local rewards = computeRewards(player)
	ProfileManager.awardRun(player, rewards.credits, rewards.xp, rewards.distance)
	Remotes.getEvent(Remotes.Event.DeathBegan):FireClient(player, rewards)

	task.delay(CHOICE_TIMEOUT, function()
		local current = pending[player]
		if current and current.token == token then
			returnToHub(player)
		end
	end)
end

local function canRevive(player: Player): boolean
	return (revivesUsed[player] or 0) < REVIVES_PER_RUN
end

local function grantContinue(player: Player): boolean
	local current = pending[player]
	if not current or not canRevive(player) then
		return false
	end
	revivesUsed[player] = (revivesUsed[player] or 0) + 1
	reviveAtDeath(player, current.deathCFrame)
	return true
end

local function onChoice(player: Player, choice: any)
	local current = pending[player]
	if not current then
		return
	end
	if choice ~= "continue" then
		returnToHub(player)
		return
	end
	if not canRevive(player) then
		returnToHub(player)
		return
	end
	if ProductsConfig.isConfigured("Continue") then
		MonetizationService.promptPurchase(player, "Continue")
		return
	end
	grantContinue(player)
end

local function watchHubDeaths(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		humanoid.Died:Connect(function()
			if MissionState.isParticipant(player) then
				return
			end
			task.delay(HUB_RESPAWN_DELAY, function()
				if player.Parent and not MissionState.isParticipant(player) then
					player:LoadCharacter()
				end
			end)
		end)
	end)
end

function DeathService.init()
	Players.RespawnTime = MANUAL_RESPAWN_TIME
	MissionService.setDeathHandler(onPlayerDied)

	Remotes.getEvent(Remotes.Event.DeathChoice).OnServerEvent:Connect(onChoice)
	MonetizationService.setGrantHandler("Continue", grantContinue)

	Players.PlayerAdded:Connect(watchHubDeaths)
	for _, player in Players:GetPlayers() do
		watchHubDeaths(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		revivesUsed[player] = nil
	end)
end

return DeathService
