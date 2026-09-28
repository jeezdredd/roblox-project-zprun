--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)

local AnimationController = require(script.Parent.AnimationController)
local BodyMotionController = require(script.Parent.BodyMotionController)
local CameraEffectsController = require(script.Parent.CameraEffectsController)
local RunController = require(script.Parent.RunController)

local GlanceController = {}

local rightAxis = GameConstants.RUN_DIRECTION:Cross(Vector3.yAxis)

local function onGlanced(side: number, power: number)
	if typeof(side) ~= "number" or typeof(power) ~= "number" then
		return
	end
	local strength = math.clamp(power, 0, 1)
	local direction = rightAxis * math.sign(side) * 0.8 + Vector3.new(0, -0.35, 0)

	RunController.applyGlance(math.sign(side), strength)
	CameraEffectsController.impulse(direction, 3 + 3 * strength)
	CameraEffectsController.fovKick(-2 * strength)
	BodyMotionController.impulse(-6 * strength, math.sign(side) * 9 * strength)
	AnimationController.playOneShot("Stumble")
end

function GlanceController.init()
	Remotes.getEvent(Remotes.Event.PlayerGlanced).OnClientEvent:Connect(onGlanced)
end

return GlanceController
