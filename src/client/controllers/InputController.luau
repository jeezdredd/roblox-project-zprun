--!strict

local ContextActionService = game:GetService("ContextActionService")

local InputController = {}

local leftHeld = false
local rightHeld = false

local function handleLeft(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	leftHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

local function handleRight(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	rightHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

function InputController.init()
	ContextActionService:BindAction("RunnerMoveLeft", handleLeft, false, Enum.KeyCode.A, Enum.KeyCode.Left)
	ContextActionService:BindAction("RunnerMoveRight", handleRight, false, Enum.KeyCode.D, Enum.KeyCode.Right)
end

function InputController.getLateralAxis(): number
	local axis = 0
	if leftHeld then
		axis -= 1
	end
	if rightHeld then
		axis += 1
	end
	return axis
end

return InputController
