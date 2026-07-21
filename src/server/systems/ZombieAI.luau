--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local ZombiesConfig = require(ReplicatedStorage.Shared.config.ZombiesConfig)
local ModifiersConfig = require(ReplicatedStorage.Shared.config.ModifiersConfig)
local ZombieFactory = require(script.Parent.ZombieFactory)
local DistanceTracker = require(script.Parent.DistanceTracker)
local MissionConfig = require(script.Parent.MissionConfig)
local MissionState = require(script.Parent.MissionState)

local ZombieAI = {}

type ZombieState = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	config: ZombiesConfig.ZombieConfig,
	chunkIndex: number,
	lastHitAt: { [Player]: number },
}

local LURE_RANGE = 80

local random = Random.new()
local zombies: { [Model]: ZombieState } = {}
local zombiesFolder: Folder? = nil
local totalWeight = 0
local tickAccumulator = 0
local corpseLure: { pos: Vector3, expires: number }? = nil

for _, config in ZombiesConfig do
	totalWeight += config.weight
end

local function getFolder(): Folder
	local existing = zombiesFolder
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Zombies"
	folder.Parent = Workspace
	zombiesFolder = folder
	return folder
end

local function pickConfig(): ZombiesConfig.ZombieConfig
	local roll = random:NextNumber() * totalWeight
	for _, config in ZombiesConfig do
		roll -= config.weight
		if roll <= 0 then
			return config
		end
	end
	return ZombiesConfig[#ZombiesConfig]
end

local function onTouched(state: ZombieState, hit: BasePart)
	local character = hit.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.clock()
	local lastHit = state.lastHitAt[player]
	if lastHit and now - lastHit < state.config.damageCooldown then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	state.lastHitAt[player] = now
	humanoid:TakeDamage(state.config.touchDamage)
end

local function spawnZombie(chunkIndex: number, position: Vector3)
	local config = pickConfig()
	local model = ZombieFactory.build(config)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart

	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, random:NextNumber() * 2 * math.pi, 0))
	model.Parent = getFolder()
	root:SetNetworkOwner(nil)

	local state: ZombieState = {
		model = model,
		humanoid = humanoid,
		root = root,
		config = config,
		chunkIndex = chunkIndex,
		lastHitAt = {},
	}
	zombies[model] = state

	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		body.Touched:Connect(function(hit)
			onTouched(state, hit)
		end)
	end

	humanoid.Died:Connect(function()
		zombies[model] = nil
		task.delay(GameConstants.ZOMBIE_CORPSE_LIFETIME, function()
			model:Destroy()
		end)
	end)
end

type PositionSample = { t: number, pos: Vector3 }

local HISTORY_WINDOW = 2

local positionHistory: { [Player]: { PositionSample } } = {}

local function recordPositions()
	local now = os.clock()
	for _, player in MissionState.getParticipants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local samples = positionHistory[player]
		if not samples then
			samples = {}
			positionHistory[player] = samples
		end
		table.insert(samples, { t = now, pos = root.Position })
		while #samples > 0 and now - samples[1].t > HISTORY_WINDOW do
			table.remove(samples, 1)
		end
	end
	for player in positionHistory do
		if not MissionState.isParticipant(player) then
			positionHistory[player] = nil
		end
	end
end

local function getDelayedPosition(player: Player, currentPosition: Vector3, delay: number): Vector3
	local samples = positionHistory[player]
	if not samples or #samples == 0 then
		return currentPosition
	end
	local cutoff = os.clock() - delay
	local chosen = samples[1].pos
	for _, sample in samples do
		if sample.t <= cutoff then
			chosen = sample.pos
		else
			break
		end
	end
	return chosen
end

local function findNearestPlayer(from: Vector3): Player?
	local nearest: Player? = nil
	local nearestDistance = GameConstants.ZOMBIE_AGGRO_RANGE
	for _, player in MissionState.getParticipants() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		if not root or not root:IsA("BasePart") then
			continue
		end
		local distance = (root.Position - from).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = player
		end
	end
	return nearest
end

local function getModifierSpeedBonus(): number
	local bonus = 0
	for _, id in MissionState.getModifiers() do
		local modifier = ModifiersConfig.get(id)
		if modifier then
			bonus += modifier.zombieSpeedBonus
		end
	end
	return bonus
end

local function aiStep()
	if not MissionState.isActive() then
		return
	end
	recordPositions()

	local difficulty = MissionConfig.getDifficulty()
	local speedScale = difficulty.zombieSpeedMultiplier * (1 + getModifierSpeedBonus())
	local aggroActive = difficulty.zombiesChase and DistanceTracker.getMaxDistance() >= difficulty.aggroDistance

	local lure = corpseLure
	local lureActive = lure ~= nil and os.clock() < lure.expires

	for _, state in zombies do
		if state.humanoid.Health <= 0 then
			continue
		end
		state.humanoid.WalkSpeed = state.config.walkSpeed * speedScale

		if lureActive and lure and (state.root.Position - lure.pos).Magnitude < LURE_RANGE then
			state.humanoid:MoveTo(lure.pos)
			continue
		end

		if not aggroActive then
			continue
		end
		local target = findNearestPlayer(state.root.Position)
		if not target then
			continue
		end
		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local delayedPosition = getDelayedPosition(target, root.Position, state.config.reactionDelay)
			state.humanoid:MoveTo(delayedPosition)
		end
	end
end

function ZombieAI.swarmCorpse(position: Vector3, duration: number)
	corpseLure = { pos = position, expires = os.clock() + duration }
end

function ZombieAI.spawnForChunk(chunkIndex: number, chunkPivot: CFrame, chunkLength: number, count: number)
	local margin = GameConstants.ZOMBIE_SPAWN_EDGE_MARGIN
	local halfWidth = GameConstants.LANE_WIDTH / 2 - margin
	local halfLength = chunkLength / 2 - margin
	for _ = 1, count do
		local offset = Vector3.new(
			random:NextNumber(-halfWidth, halfWidth),
			2,
			random:NextNumber(-halfLength, halfLength)
		)
		spawnZombie(chunkIndex, chunkPivot.Position + offset)
	end
end

function ZombieAI.clearChunk(chunkIndex: number)
	for model, state in zombies do
		if state.chunkIndex == chunkIndex then
			zombies[model] = nil
			model:Destroy()
		end
	end
end

function ZombieAI.clearAll()
	for model in zombies do
		zombies[model] = nil
		model:Destroy()
	end
end

function ZombieAI.init()
	RunService.Heartbeat:Connect(function(deltaTime)
		tickAccumulator += deltaTime
		if tickAccumulator < GameConstants.ZOMBIE_AI_TICK then
			return
		end
		tickAccumulator = 0
		aiStep()
	end)
end

return ZombieAI
