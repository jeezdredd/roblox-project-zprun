--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)

local DistanceTracker = {}

local distances: { [Player]: number } = {}

local function createLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local distanceStat = Instance.new("IntValue")
	distanceStat.Name = "Distance"
	distanceStat.Value = 0
	distanceStat.Parent = leaderstats
	leaderstats.Parent = player
end

local function updateLeaderstats(player: Player, distance: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local distanceStat = leaderstats and leaderstats:FindFirstChild("Distance")
	if distanceStat and distanceStat:IsA("IntValue") then
		distanceStat.Value = math.floor(distance)
	end
end

local function onPlayerAdded(player: Player)
	distances[player] = 0
	createLeaderstats(player)
	player.CharacterAdded:Connect(function()
		distances[player] = 0
		updateLeaderstats(player, 0)
	end)
end

local function step()
	for player, best in distances do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local traveled = root.Position:Dot(GameConstants.RUN_DIRECTION)
		if traveled > best then
			best = traveled
			distances[player] = traveled
			updateLeaderstats(player, traveled)
		end

		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = math.min(
				GameConstants.BASE_RUN_SPEED + best * GameConstants.SPEED_GAIN_PER_STUD,
				GameConstants.MAX_RUN_SPEED
			)
		end
	end
end

function DistanceTracker.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		distances[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

function DistanceTracker.getDistance(player: Player): number
	return distances[player] or 0
end

function DistanceTracker.getMaxDistance(): number
	local maxDistance = 0
	for _, distance in distances do
		maxDistance = math.max(maxDistance, distance)
	end
	return maxDistance
end

function DistanceTracker.getMinDistance(): number
	local minDistance = math.huge
	for _, distance in distances do
		minDistance = math.min(minDistance, distance)
	end
	if minDistance == math.huge then
		return 0
	end
	return minDistance
end

return DistanceTracker
