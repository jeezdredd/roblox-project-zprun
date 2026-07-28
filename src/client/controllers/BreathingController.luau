--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local BreathingConfig = require(ReplicatedStorage.Shared.config.BreathingConfig)
local ExertionState = require(script.Parent.ExertionState)
local MusicController = require(script.Parent.Parent.systems.MusicController)

local BreathingController = {}

type LayerRuntime = {
	config: BreathingConfig.BreathLayer,
	sound: Sound,
	weight: number,
}

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

local function update(deltaTime: number)
	local exertion = ExertionState.get()
	local alive = isAlive()

	for _, layer in runtime do
		local target = if alive then BreathingConfig.weightFor(layer.config, exertion) else 0
		layer.weight = approach(layer.weight, target, BreathingConfig.FADE_SPEED, deltaTime)
		layer.sound.Volume = layer.config.volume * layer.weight
		if layer.weight > 0.01 and not layer.sound.IsPlaying then
			pcall(function()
				layer.sound:Play()
			end)
		elseif layer.weight <= 0.01 and layer.sound.IsPlaying then
			layer.sound:Stop()
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
		local sound = Instance.new("Sound")
		sound.Name = "Breath" .. config.id
		sound.SoundId = "rbxassetid://" .. tostring(config.soundId)
		sound.Looped = true
		sound.Volume = 0
		sound.PlaybackSpeed = config.pitch
		sound.SoundGroup = MusicController.getSfxGroup()
		sound.Parent = SoundService
		table.insert(runtime, { config = config, sound = sound, weight = 0 })
		table.insert(assets, sound.SoundId)
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
