--!strict

-- Zombie voices: a looping growl on every body, periodic idle moans from nearby
-- bodies, an alert bark volley when the horde aggros, bites, and the horde walla bed.
-- With the spatial audio engine on every voice is a ZombieLoop, ZombieVocal or Bite
-- class voice following the body, so it propagates (distance curve, air, occlusion,
-- delay); the walla is a 2D ambience bed. The Sound path from before stays for the
-- flag off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local ZombieRig = require(ReplicatedStorage.Shared.util.ZombieRig)
local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local ZombieAudio = {}

local AGGRO_ATTRIBUTE = "ZombiesAggro"
local GROWL_ATTRIBUTE = "GrowlAttached"

local random = Random.new()
local folder: Folder? = nil
local nextIdleAt = 0
local walla: Sound? = nil
local wallaHandle: AudioEngine.Handle? = nil
local wallaVolume = 0
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
		local body = model:IsA("Model") and ZombieRig.torso(model)
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
		local body = model:IsA("Model") and ZombieRig.torso(model)
		if body and body:IsA("BasePart") and (body.Position - origin).Magnitude <= range then
			count += 1
		end
	end
	return count
end

local function playVocal(body: BasePart, soundId: number, volume: number, range: number, pitchJitter: number, delay: number?)
	if AudioEngine.enabled() then
		AudioEngine.play({
			id = soundId,
			class = "ZombieVocal",
			follow = body,
			volume = volume,
			range = range,
			pitchJitter = pitchJitter,
			delay = delay,
		})
		return
	end
	if delay and delay > 0 then
		task.delay(delay, function()
			SfxPlayer.play3D(body, soundId, volume, AudioConfig.ZOMBIE_ROLLOFF_MIN, range, pitchJitter)
		end)
	else
		SfxPlayer.play3D(body, soundId, volume, AudioConfig.ZOMBIE_ROLLOFF_MIN, range, pitchJitter)
	end
end

local function attachGrowl(model: Model)
	if AudioConfig.ZOMBIE_GROWL_ID <= 0 then
		return
	end
	local body = ZombieRig.waitForTorso(model, 5)
	if not body or not body:IsA("BasePart") then
		return
	end

	if AudioEngine.enabled() then
		if body:GetAttribute(GROWL_ATTRIBUTE) == true then
			return
		end
		body:SetAttribute(GROWL_ATTRIBUTE, true)
		-- the voice follows the body and releases itself when the model leaves the world
		AudioEngine.play({
			id = AudioConfig.ZOMBIE_GROWL_ID,
			class = "ZombieLoop",
			follow = body,
			volume = AudioConfig.ZOMBIE_VOLUME,
			pitch = random:NextNumber(0.55, 0.85),
			loop = true,
			delay = random:NextNumber(0, 2.5),
			fadeIn = 0.4,
		})
		return
	end

	if body:FindFirstChild("Growl") then
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
	playVocal(body, SfxPlayer.pick(SfxConfig.ZOMBIE_IDLE_IDS), SfxConfig.ZOMBIE_IDLE_VOLUME, SfxConfig.ZOMBIE_IDLE_RANGE, 0.18)
end

local function playAlertBarks(origin: Vector3)
	local bodies = nearbyZombies(origin, SfxConfig.ZOMBIE_ALERT_RANGE, SfxConfig.ZOMBIE_ALERT_MAX_VOICES)
	for _, body in bodies do
		playVocal(body, SfxConfig.ZOMBIE_ALERT_ID, SfxConfig.ZOMBIE_ALERT_VOLUME, SfxConfig.ZOMBIE_ALERT_RANGE, 0.15, random:NextNumber(0, 0.35))
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

	if walla or wallaHandle then
		local count = countNearby(origin, SfxConfig.HORDE_WALLA_RANGE)
		local target = SfxConfig.HORDE_WALLA_VOLUME_MAX * math.clamp(count / SfxConfig.HORDE_WALLA_FULL_COUNT, 0, 1)
		wallaVolume = approach(wallaVolume, target, 1.5, deltaTime)
		if walla then
			walla.Volume = wallaVolume
		end
		local handle = wallaHandle
		if handle then
			handle:setVolume(wallaVolume)
		end
	end
end

function ZombieAudio.playBite(position: Vector3)
	local origin = playerPosition()
	if not origin then
		return
	end
	local bodies = nearbyZombies(position, 14, 1)
	local host = bodies[1]
	local soundId = SfxPlayer.pick(SfxConfig.ZOMBIE_BITE_IDS)
	if AudioEngine.enabled() then
		if host then
			AudioEngine.play({ id = soundId, class = "Bite", follow = host, volume = SfxConfig.ZOMBIE_BITE_VOLUME, pitchJitter = 0.12 })
		else
			AudioEngine.play({ id = soundId, class = "Bite", volume = SfxConfig.ZOMBIE_BITE_VOLUME * 0.8, pitchJitter = 0.12 })
		end
		return
	end
	if host then
		SfxPlayer.play3D(host, soundId, SfxConfig.ZOMBIE_BITE_VOLUME, 6, 70, 0.12)
	else
		SfxPlayer.play2D(soundId, SfxConfig.ZOMBIE_BITE_VOLUME * 0.8, 0.12)
	end
end

local function startWalla()
	if SfxConfig.HORDE_WALLA_ID <= 0 then
		return
	end
	if AudioEngine.enabled() then
		wallaHandle = AudioEngine.play({ id = SfxConfig.HORDE_WALLA_ID, class = "AmbienceBed", volume = 0, loop = true })
		return
	end
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

function ZombieAudio.init()
	if started then
		return
	end
	started = true

	startWalla()

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
