--!strict

local Players = game:GetService("Players")

local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local RunController = require(script.Parent.RunController)

local FlowController = {}

local PHASE_ATTRIBUTE = "FlowPhase"

local function applyPhase()
	local player = Players.LocalPlayer
	local phase = player:GetAttribute(PHASE_ATTRIBUTE)
	if phase == "Mission" then
		InputController.start()
		CameraController.start()
		RunController.start()
	else
		RunController.stop()
		InputController.stop()
		CameraController.stop()
	end
end

function FlowController.init()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(applyPhase)
	player.CharacterAdded:Connect(function()
		task.defer(applyPhase)
	end)
	applyPhase()
end

return FlowController
