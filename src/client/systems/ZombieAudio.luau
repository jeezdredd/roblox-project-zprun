--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local ZombieAudio = {}

local AGGRO_ATTRIBUTE = "ZombiesAggro"

local random = Random.new()
local folder: Folder? = nil
local nextIdleAt = 0
local walla: Sound? = nil
local lastAggro = false
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function playerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function nearbyZombies(origin: Vector3, range: number, limit: number): { BasePart }
	local result: { BasePart } = {}
	local zombies = folder
	if not zombies then
		return result
	end
	for _, model in zombies:GetChildren() do
		if #result >= limit then
			break
		end
		local body = model:IsA("Model") and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") and (body.Position - origin).Magnitude <= range then
			table.insert(result, body)
		end
	end
	return result
end

local function countNearby(origin: Vector3, range: number): number
	local zombies = folder
	if not zombies then
		return 0
	end
	local count = 0
	for _, model in zombies:GetChildren() do
		local body = model:IsA("Model") and model:FindFirstChild("Body")
		if body and body:IsA("BasePart") and (body.Position - origin).Magnitude <= range then
			count += 1
		end
	end
	return count
end

local function attachGrowl(model: Model)
	if AudioConfig.ZOMBIE_GROWL_ID <= 0 then
		return
	end
	local body = model:WaitForChild("Body", 5)
	if not body or not body:IsA("BasePart") then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Growl"
	sound.SoundId = "rbxassetid://" .. tostring(AudioConfig.ZOMBIE_GROWL_ID)
	sound.Looped = true
	sound.Volume = AudioConfig.ZOMBIE_VOLUME
	sound.PlaybackSpeed = random:NextNumber(0.55, 0.85)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = AudioConfig.ZOMBIE_ROLLOFF_MIN
	sound.RollOffMaxDistance = AudioConfig.ZOMBIE_ROLLOFF_MAX
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = body

	task.delay(random:NextNumber(0, 2.5), function()
		if sound.Parent then
			pcall(function()
				sound:Play()
			end)
		end
	end)
end

local function playIdleMoans(origin: Vector3)
	local bodies = nearbyZombies(origin, SfxConfig.ZOMBIE_IDLE_RANGE, SfxConfig.ZOMBIE_IDLE_MAX_VOICES)
	if #bodies == 0 then
		return
	end
	local body = bodies[random:NextInteger(1, #bodies)]
	SfxPlayer.play3D(
		body,
		SfxPlayer.pick(SfxConfig.ZOMBIE_IDLE_IDS),
		SfxConfig.ZOMBIE_IDLE_VOLUME,
		AudioConfig.ZOMBIE_ROLLOFF_MIN,
		SfxConfig.ZOMBIE_IDLE_RANGE,
		0.18
	)
end

local function playAlertBarks(origin: Vector3)
	local bodies = nearbyZombies(origin, SfxConfig.ZOMBIE_ALERT_RANGE, SfxConfig.ZOMBIE_ALERT_MAX_VOICES)
	for index, body in bodies do
		task.delay(random:NextNumber(0, 0.35), function()
			SfxPlayer.play3D(
				body,
				SfxConfig.ZOMBIE_ALERT_ID,
				SfxConfig.ZOMBIE_ALERT_VOLUME,
				AudioConfig.ZOMBIE_ROLLOFF_MIN,
				SfxConfig.ZOMBIE_ALERT_RANGE,
				0.15
			)
		end)
		local _ = index
	end
end

local function onAggroChanged()
	local aggro = Workspace:GetAttribute(AGGRO_ATTRIBUTE) == true
	if aggro and not lastAggro then
		local origin = playerPosition()
		if origin then
			playAlertBarks(origin)
		end
	end
	lastAggro = aggro
end

local function step(deltaTime: number)
	local origin = playerPosition()
	if not origin then
		return
	end
	local now = os.clock()

	if now >= nextIdleAt then
		nextIdleAt = now + random:NextNumber(SfxConfig.ZOMBIE_IDLE_INTERVAL_MIN, SfxConfig.ZOMBIE_IDLE_INTERVAL_MAX)
		playIdleMoans(origin)
	end

	if walla then
		local count = countNearby(origin, SfxConfig.HORDE_WALLA_RANGE)
		local target = SfxConfig.HORDE_WALLA_VOLUME_MAX * math.clamp(count / SfxConfig.HORDE_WALLA_FULL_COUNT, 0, 1)
		walla.Volume = approach(walla.Volume, target, 1.5, deltaTime)
	end
end

function ZombieAudio.playBite(position: Vector3)
	local origin = playerPosition()
	if not origin then
		return
	end
	local bodies = nearbyZombies(position, 14, 1)
	local host = bodies[1]
	if host then
		SfxPlayer.play3D(
			host,
			SfxPlayer.pick(SfxConfig.ZOMBIE_BITE_IDS),
			SfxConfig.ZOMBIE_BITE_VOLUME,
			6,
			70,
			0.12
		)
	else
		SfxPlayer.play2D(SfxPlayer.pick(SfxConfig.ZOMBIE_BITE_IDS), SfxConfig.ZOMBIE_BITE_VOLUME * 0.8, 0.12)
	end
end

function ZombieAudio.init()
	if started then
		return
	end
	started = true

	if SfxConfig.HORDE_WALLA_ID > 0 then
		local sound = Instance.new("Sound")
		sound.Name = "HordeWalla"
		sound.SoundId = "rbxassetid://" .. tostring(SfxConfig.HORDE_WALLA_ID)
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = MusicController.getSfxGroup()
		sound.Parent = SoundService
		pcall(function()
			sound:Play()
		end)
		walla = sound
	end

	Workspace:GetAttributeChangedSignal(AGGRO_ATTRIBUTE):Connect(onAggroChanged)

	task.spawn(function()
		local zombies = Workspace:WaitForChild("Zombies", 60)
		if not zombies or not zombies:IsA("Folder") then
			return
		end
		folder = zombies
		for _, child in zombies:GetChildren() do
			if child:IsA("Model") then
				task.spawn(attachGrowl, child)
			end
		end
		zombies.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.spawn(attachGrowl, child)
			end
		end)
	end)

	RunService.Heartbeat:Connect(step)
end

return ZombieAudio
