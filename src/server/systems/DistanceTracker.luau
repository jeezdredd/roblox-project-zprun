--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local MissionState = require(script.Parent.MissionState)
local MissionGoals = require(script.Parent.MissionGoals)
local SkillEffects = require(script.Parent.SkillEffects)
local RunEconomy = require(script.Parent.RunEconomy)

local DistanceTracker = {}

type RunState = {
	best: number,
	startedAt: number,
	speed: number,
	slowFactor: number,
	slowUntil: number,
	lastCheckAt: number,
	lastCheckBest: number,
	strikes: number,
	-- the health seen last frame and the distance at the last drop of it, for the
	-- CleanDistance goal metric (the best clean stretch so far: the current stretch is
	-- the studs since the last hit, MissionGoals keeps the longest)
	lastHealth: number,
	lastHitDistance: number,
}

local STUCK_CHECK_INTERVAL = 2
local STUCK_MIN_PROGRESS = 6
local STUCK_NUDGE_STRIKES = 2
local STUCK_DEATH_STRIKES = 5
local STUCK_GRACE = 3
local NUDGE_STEPS = { 14, 28, 42 }

local runs: { [Player]: RunState } = {}

local function newRun(): RunState
	return {
		best = 0,
		startedAt = os.clock(),
		speed = GameConstants.BASE_RUN_SPEED,
		slowFactor = 1,
		slowUntil = 0,
		lastCheckAt = os.clock(),
		lastCheckBest = 0,
		strikes = 0,
		lastHealth = math.huge,
		lastHitDistance = 0,
	}
end

-- Studio only: DevConfig.FREEZE_RUN, or the DevFreezeRun workspace attribute set from the
-- server command bar while testing (the client's freeze debug command cannot reach here).
local function freezeHeld(): boolean
	return RunService:IsStudio() and (DevConfig.FREEZE_RUN or workspace:GetAttribute("DevFreezeRun") == true)
end

local function relocate(character: Model, root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local half = GameConstants.PLAYABLE_HALF_WIDTH
	local originX = GameConstants.RUN_ORIGIN.X
	local minX = originX - half
	local maxX = originX + half
	local toCentre = if root.Position.X > originX then -1 else 1
	for _, step in NUDGE_STEPS do
		for _, direction in { toCentre, -toCentre } do
			local targetX = math.clamp(root.Position.X + step * direction, minX, maxX)
			if math.abs(targetX - root.Position.X) >= 4 then
				local origin = Vector3.new(targetX, root.Position.Y + 24, root.Position.Z)
				local hit = Workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
				if hit then
					local rotation = root.CFrame - root.CFrame.Position
					root.CFrame = CFrame.new(targetX, hit.Position.Y + 3, root.Position.Z) * rotation
					return true
				end
			end
		end
	end
	return false
end

local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
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
	createLeaderstats(player)
end

local function currentLocation(): LocationsConfig.LocationConfig?
	local biomeId = Workspace:GetAttribute("Biome")
	if typeof(biomeId) ~= "string" then
		return nil
	end
	return LocationsConfig.get(biomeId)
end

local function locationTargetSpeed(elapsed: number): number
	local location = currentLocation()
	if not location then
		return GameConstants.BASE_RUN_SPEED
	end
	local initial = location.runSpeedInitial or GameConstants.BASE_RUN_SPEED
	local peak = location.runSpeedMax
	local rampTime = location.runSpeedRampTime
	if not peak or not rampTime or rampTime <= 0 then
		return initial
	end
	return initial + (peak - initial) * math.clamp(elapsed / rampTime, 0, 1)
end

local function approach(current: number, target: number, rate: number, deltaTime: number): number
	local delta = target - current
	local maxStep = rate * deltaTime
	if math.abs(delta) <= maxStep then
		return target
	end
	return current + if delta > 0 then maxStep else -maxStep
end

local function step(deltaTime: number)
	if not MissionState.isActive() then
		return
	end
	local now = os.clock()
	for _, player in MissionState.getParticipants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local run = runs[player]
		if not run then
			run = newRun()
			runs[player] = run
		end

		local traveled = root.Position:Dot(GameConstants.RUN_DIRECTION)
		if traveled > run.best then
			run.best = traveled
			updateLeaderstats(player, traveled)
			-- the distance pay goes into the run balance next to the kill pay
			RunEconomy.setDistance(player, traveled)
			MissionGoals.report(player, "Distance", traveled)
		end

		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		-- a drop in health is a hit: the current clean stretch starts again from here;
		-- the goal keeps the best stretch so far (MissionGoals takes the max)
		if humanoid then
			if humanoid.Health < run.lastHealth - 0.01 then
				run.lastHitDistance = run.best
			end
			run.lastHealth = humanoid.Health
			MissionGoals.report(player, "CleanDistance", run.best - run.lastHitDistance)
		end

		if now - run.lastCheckAt >= STUCK_CHECK_INTERVAL then
			local progressed = run.best - run.lastCheckBest
			run.lastCheckAt = now
			run.lastCheckBest = run.best
			local exempt = freezeHeld()
				or now - run.startedAt < STUCK_GRACE
				or humanoid == nil
				or humanoid.Health <= 0
			if exempt or progressed >= STUCK_MIN_PROGRESS then
				run.strikes = 0
			else
				run.strikes += 1
				if run.strikes >= STUCK_DEATH_STRIKES then
					(humanoid :: Humanoid).Health = 0
				elseif run.strikes >= STUCK_NUDGE_STRIKES then
					relocate(character :: Model, root)
				end
			end
		end

		if humanoid then
			local target = math.min(
				locationTargetSpeed(now - run.startedAt) + SkillEffects.bonusSpeed(player),
				GameConstants.MAX_RUN_SPEED
			)
			if now < run.slowUntil then
				target *= run.slowFactor
			end
			run.speed = approach(run.speed, target, GameConstants.RUN_SPEED_SLEW, deltaTime)
			humanoid.WalkSpeed = run.speed
		end
	end
end

function DistanceTracker.applySlow(player: Player, factor: number, duration: number)
	local run = runs[player]
	if not run then
		return
	end
	local until_ = os.clock() + math.max(duration, 0)
	if until_ > run.slowUntil or factor < run.slowFactor then
		run.slowFactor = math.clamp(factor, 0.1, 1)
		run.slowUntil = until_
	end
end

function DistanceTracker.beginRun(player: Player)
	runs[player] = newRun()
	player:SetAttribute("DeathCause", nil)
	createLeaderstats(player)
	updateLeaderstats(player, 0)
end

function DistanceTracker.endRun(player: Player)
	runs[player] = nil
	updateLeaderstats(player, 0)
end

function DistanceTracker.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

function DistanceTracker.getDistance(player: Player): number
	local run = runs[player]
	return if run then run.best else 0
end

function DistanceTracker.getMaxDistance(): number
	local maxDistance = 0
	for _, player in MissionState.getParticipants() do
		maxDistance = math.max(maxDistance, DistanceTracker.getDistance(player))
	end
	return maxDistance
end

function DistanceTracker.getMinDistance(): number
	local minDistance = math.huge
	for _, player in MissionState.getParticipants() do
		minDistance = math.min(minDistance, DistanceTracker.getDistance(player))
	end
	if minDistance == math.huge then
		return 0
	end
	return minDistance
end

return DistanceTracker
