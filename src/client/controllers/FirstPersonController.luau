--!strict

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local FirstPersonController = {}

local function lockFirstPerson()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
end

function FirstPersonController.init()
	lockFirstPerson()
	Players.LocalPlayer.CharacterAdded:Connect(lockFirstPerson)
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
end

return FirstPersonController
