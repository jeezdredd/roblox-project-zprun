--!strict

-- Breathing layers (calm, heavy, gasp) weighted by exertion. With the spatial audio
-- engine on each layer is a 2D PlayerFoley loop that starts when its weight rises and
-- stops when it falls away, so idle layers cost no voice; with it off the Sounds from
-- before stay.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local BreathingConfig = require(ReplicatedStorage.Shared.config.BreathingConfig)
local ExertionState = require(script.Parent.ExertionState)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.Parent.systems.MusicController)

local BreathingController = {}

type LayerRuntime = {
	config: BreathingConfig.BreathLayer,
	sound: Sound?,
	handle: AudioEngine.Handle?,
	weight: number,
}

local SILENT_WEIGHT = 0.01
local STOP_FADE = 0.2

local runtime: { LayerRuntime } = {}
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	local alpha = 1 - math.exp(-speed * deltaTime)
	return current + (target - current) * alpha
end

local function isAlive(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function updateEngineLayer(layer: LayerRuntime)
	local handle = layer.handle
	if layer.weight > SILENT_WEIGHT then
		if not handle or not handle:isPlaying() then
			handle = AudioEngine.play({
				id = layer.config.soundId,
				class = "PlayerFoley",
				volume = 0,
				pitch = layer.config.pitch,
				loop = true,
			})
			layer.handle = handle
		end
		handle:setVolume(layer.config.volume * layer.weight)
	elseif handle then
		handle:stop(STOP_FADE)
		layer.handle = nil
	end
end

local function updateSoundLayer(layer: LayerRuntime, sound: Sound)
	sound.Volume = layer.config.volume * layer.weight
	if layer.weight > SILENT_WEIGHT and not sound.IsPlaying then
		pcall(function()
			sound:Play()
		end)
	elseif layer.weight <= SILENT_WEIGHT and sound.IsPlaying then
		sound:Stop()
	end
end

local function update(deltaTime: number)
	local exertion = ExertionState.get()
	local alive = isAlive()

	for _, layer in runtime do
		local target = if alive then BreathingConfig.weightFor(layer.config, exertion) else 0
		layer.weight = approach(layer.weight, target, BreathingConfig.FADE_SPEED, deltaTime)
		local sound = layer.sound
		if sound then
			updateSoundLayer(layer, sound)
		else
			updateEngineLayer(layer)
		end
	end
end

function BreathingController.init()
	if started then
		return
	end
	started = true
	ExertionState.init()

	local assets: { string } = {}
	for _, config in BreathingConfig.layers do
		if config.soundId <= 0 then
			continue
		end
		local sound: Sound? = nil
		if not AudioEngine.enabled() then
			local created = Instance.new("Sound")
			created.Name = "Breath" .. config.id
			created.SoundId = "rbxassetid://" .. tostring(config.soundId)
			created.Looped = true
			created.Volume = 0
			created.PlaybackSpeed = config.pitch
			created.SoundGroup = MusicController.getSfxGroup()
			created.Parent = SoundService
			sound = created
		end
		table.insert(runtime, { config = config, sound = sound, handle = nil, weight = 0 })
		table.insert(assets, "rbxassetid://" .. tostring(config.soundId))
	end

	if #assets > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(assets)
			end)
		end)
	end

	if #runtime > 0 then
		RunService.RenderStepped:Connect(update)
	end
end

return BreathingController
