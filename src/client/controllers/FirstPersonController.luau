--!strict

local StarterGui = game:GetService("StarterGui")

local CursorMode = require(script.Parent.Parent.systems.CursorMode)

local FirstPersonController = {}

function FirstPersonController.init()
	CursorMode.init()
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
end

return FirstPersonController
