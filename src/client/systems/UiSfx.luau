--!strict

-- Interface sounds and the chase duck. With the spatial audio engine on the clicks are
-- UI-class voices on the ui bus, which joins the mix after the duck compressor so a
-- menu never dips under gunfire; the chase duck still goes through
-- MusicController.setDuck, which scales the music fader.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ZombieRig = require(ReplicatedStorage.Shared.util.ZombieRig)

local SfxConfig = require(ReplicatedStorage.Shared.config.SfxConfig)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.MusicController)
local SfxPlayer = require(script.Parent.SfxPlayer)

local UiSfx = {}

local AGGRO_ATTRIBUTE = "ZombiesAggro"

local duckUntil = 0
local duckLevel = 0
local started = false

local function approach(current: number, target: number, speed: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-speed * deltaTime))
end

local function chaseActive(): boolean
	if Workspace:GetAttribute(AGGRO_ATTRIBUTE) ~= true then
		return false
	end
	if Players.LocalPlayer:GetAttribute("FlowPhase") ~= "Mission" then
		return false
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zombies = Workspace:FindFirstChild("Zombies")
	if not root or not root:IsA("BasePart") or not zombies then
		return false
	end
	for _, model in zombies:GetChildren() do
		local body = model:IsA("Model") and ZombieRig.torso(model)
		if body and body:IsA("BasePart") and (body.Position - root.Position).Magnitude <= SfxConfig.MUSIC_DUCK_RANGE then
			return true
		end
	end
	return false
end

local function step(deltaTime: number)
	local now = os.clock()
	if chaseActive() then
		duckUntil = now + SfxConfig.MUSIC_DUCK_RELEASE
	end
	local target = if now < duckUntil then 1 else 0
	duckLevel = approach(duckLevel, target, SfxConfig.MUSIC_DUCK_SPEED, deltaTime)
	MusicController.setDuck(duckLevel * (1 - SfxConfig.MUSIC_DUCK_DB))
end

local function play(soundId: number, volume: number, pitchJitter: number)
	if AudioEngine.enabled() then
		AudioEngine.play({ id = soundId, class = "UI", volume = volume, pitchJitter = pitchJitter })
		return
	end
	SfxPlayer.play2D(soundId, volume, pitchJitter)
end

function UiSfx.hover()
	play(SfxConfig.UI_HOVER_ID, SfxConfig.UI_VOLUME * 0.6, 0.04)
end

function UiSfx.click()
	play(SfxConfig.UI_CLICK_ID, SfxConfig.UI_VOLUME, 0.04)
end

function UiSfx.countdownTick()
	play(SfxConfig.UI_COUNTDOWN_TICK_ID, SfxConfig.UI_VOLUME, 0)
end

function UiSfx.countdownGo()
	play(SfxConfig.UI_COUNTDOWN_GO_ID, SfxConfig.UI_VOLUME, 0)
end

function UiSfx.rewardTick()
	play(SfxConfig.UI_REWARD_TICK_ID, SfxConfig.UI_VOLUME * 0.7, 0.08)
end

function UiSfx.bindButton(button: GuiButton)
	button.MouseEnter:Connect(UiSfx.hover)
	button.Activated:Connect(UiSfx.click)
end

function UiSfx.init()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(step)
end

return UiSfx
