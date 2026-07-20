--!strict

local ContextActionService = game:GetService("ContextActionService")

local InputController = {}

local LEFT_ACTION = "RunnerMoveLeft"
local RIGHT_ACTION = "RunnerMoveRight"

local leftHeld = false
local rightHeld = false
local active = false

local function handleLeft(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	leftHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

local function handleRight(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	rightHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

function InputController.start()
	if active then
		return
	end
	active = true
	ContextActionService:BindAction(LEFT_ACTION, handleLeft, false, Enum.KeyCode.A, Enum.KeyCode.Left)
	ContextActionService:BindAction(RIGHT_ACTION, handleRight, false, Enum.KeyCode.D, Enum.KeyCode.Right)
end

function InputController.stop()
	if not active then
		return
	end
	active = false
	leftHeld = false
	rightHeld = false
	ContextActionService:UnbindAction(LEFT_ACTION)
	ContextActionService:UnbindAction(RIGHT_ACTION)
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
