--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FootstepConfig = require(ReplicatedStorage.Shared.config.FootstepConfig)
local ExertionState = require(script.Parent.ExertionState)
local MusicController = require(script.Parent.Parent.systems.MusicController)

local FootstepController = {}

type TeammateState = {
	phase: number,
	pool: { Sound },
	poolIndex: number,
	lastVariation: number,
}

local random = Random.new()
local localPool: { Sound } = {}
local localPoolIndex = 0
local lastLocalVariation = 0
local teammates: { [Player]: TeammateState } = {}
local rayParams = RaycastParams.new()
local started = false

local function isPlayableId(id: number): boolean
	return id > 0
end

local function createPool(parent: Instance, size: number, rolloffMax: number): { Sound }
	local pool: { Sound } = {}
	for index = 1, size do
		local sound = Instance.new("Sound")
		sound.Name = "Footstep" .. index
		sound.Volume = 0
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = FootstepConfig.ROLLOFF_MIN
		sound.RollOffMaxDistance = rolloffMax
		sound.SoundGroup = MusicController.getSfxGroup()
		sound.Parent = parent
		pool[index] = sound
	end
	return pool
end

local function pickVariation(ids: { number }, lastIndex: number): (number, number)
	local count = #ids
	if count == 0 then
		return 0, lastIndex
	end
	if count == 1 then
		return ids[1], 1
	end
	local index = random:NextInteger(1, count)
	if index == lastIndex then
		index = (index % count) + 1
	end
	return ids[index], index
end

local function materialUnder(character: Model, humanoid: Humanoid): Enum.Material
	local material = humanoid.FloorMaterial
	if material ~= Enum.Material.Air then
		return material
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Enum.Material.Air
	end
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -FootstepConfig.RAYCAST_DEPTH, 0), rayParams)
	if result then
		return result.Material
	end
	return Enum.Material.Air
end

local function playFrom(pool: { Sound }, poolIndex: number, soundId: number, volume: number, pitch: number): number
	if #pool == 0 or not isPlayableId(soundId) then
		return poolIndex
	end
	local nextIndex = (poolIndex % #pool) + 1
	local sound = pool[nextIndex]
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume * (1 + random:NextNumber(-FootstepConfig.VOLUME_JITTER, FootstepConfig.VOLUME_JITTER))
	sound.PlaybackSpeed = pitch * (1 + random:NextNumber(-FootstepConfig.PITCH_JITTER, FootstepConfig.PITCH_JITTER))
	sound.TimePosition = 0
	pcall(function()
		sound:Play()
	end)
	local length = sound.TimeLength
	if length <= 0 or length > FootstepConfig.MAX_SLICE then
		task.delay(FootstepConfig.MAX_SLICE, function()
			if sound.Parent and sound.IsPlaying then
				sound:Stop()
			end
		end)
	end
	return nextIndex
end

local function silencePool(pool: { Sound })
	for _, sound in pool do
		if sound.Parent and sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function onLocalStep()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local material = materialUnder(character, humanoid)
	if material == Enum.Material.Air then
		return
	end
	local entry = FootstepConfig.get(material)
	local soundId, variationIndex = pickVariation(entry.ids, lastLocalVariation)
	lastLocalVariation = variationIndex
	localPoolIndex = playFrom(localPool, localPoolIndex, soundId, entry.volume, entry.pitch)
end

local function setupLocalCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	localPool = createPool(root, FootstepConfig.POOL_SIZE, FootstepConfig.ROLLOFF_MAX)
end

local function teammateState(player: Player, root: BasePart): TeammateState
	local state = teammates[player]
	if state and state.pool[1] and state.pool[1].Parent == root then
		return state
	end
	state = {
		phase = 0,
		pool = createPool(root, 3, FootstepConfig.TEAMMATE_ROLLOFF_MAX),
		poolIndex = 0,
		lastVariation = 0,
	}
	teammates[player] = state
	return state
end

local function stepTeammates(deltaTime: number)
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer then
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			continue
		end

		local velocity = root.AssemblyLinearVelocity
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		if speed < 2 or humanoid.FloorMaterial == Enum.Material.Air then
			continue
		end

		local state = teammateState(player, root)
		local previous = state.phase
		state.phase += ExertionState.strideFrequencyFor(speed) * deltaTime * math.pi * 2
		if math.floor(state.phase / math.pi) > math.floor(previous / math.pi) then
			local entry = FootstepConfig.get(materialUnder(character, humanoid))
			local soundId, variationIndex = pickVariation(entry.ids, state.lastVariation)
			state.lastVariation = variationIndex
			state.poolIndex = playFrom(state.pool, state.poolIndex, soundId, entry.volume, entry.pitch)
		end
		if state.phase > math.pi * 4096 then
			state.phase -= math.pi * 4096
		end
	end
end

function FootstepController.preload()
	local assets: { string } = {}
	for _, entry in FootstepConfig.byMaterial do
		for _, id in entry.ids do
			if isPlayableId(id) then
				table.insert(assets, "rbxassetid://" .. tostring(id))
			end
		end
	end
	if #assets == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)
end

function FootstepController.init()
	if started then
		return
	end
	started = true
	ExertionState.init()

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(setupLocalCharacter)
	if player.Character then
		task.spawn(setupLocalCharacter, player.Character)
	end

	ExertionState.onStep(onLocalStep)
	RunService.Heartbeat:Connect(stepTeammates)

	local wasRunning = false
	RunService.Heartbeat:Connect(function()
		local isRunning = ExertionState.isRunning()
		if wasRunning and not isRunning then
			silencePool(localPool)
		end
		wasRunning = isRunning
	end)

	local function watchTeammate(other: Player)
		if other == player then
			return
		end
		other.CharacterRemoving:Connect(function()
			teammates[other] = nil
		end)
	end

	Players.PlayerAdded:Connect(watchTeammate)
	for _, existing in Players:GetPlayers() do
		watchTeammate(existing)
	end
	Players.PlayerRemoving:Connect(function(leaving)
		teammates[leaving] = nil
	end)

	FootstepController.preload()
end

return FootstepController
