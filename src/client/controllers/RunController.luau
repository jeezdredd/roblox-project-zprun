--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local InputController = require(script.Parent.InputController)

local RunController = {}

local runDirection = GameConstants.RUN_DIRECTION
local rightDirection = runDirection:Cross(Vector3.yAxis)
local wrapThreshold = GameConstants.LANE_WIDTH / 2 - GameConstants.WALL_WRAP_MARGIN

local connection: RBXScriptConnection? = nil

local function getControls(): any
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule")) :: any
	return playerModule:GetControls()
end

local function getAliveHumanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function clampToField(root: BasePart)
	local offsetX = root.Position.X - GameConstants.RUN_ORIGIN.X
	if math.abs(offsetX) <= wrapThreshold then
		return
	end
	local targetX = math.sign(offsetX) * wrapThreshold
	root.CFrame = root.CFrame + Vector3.new(targetX - offsetX, 0, 0)
end

function RunController.start(force: boolean?)
	if connection then
		return
	end
	-- Frozen: leave the default controls enabled instead of taking them over, so you can
	-- actually walk around and look at things rather than being rooted in place. `force`
	-- is how the unfreeze debug command overrides the switch without editing config.
	if not force and RunService:IsStudio() and DevConfig.FREEZE_RUN then
		return
	end
	getControls():Disable()

	connection = RunService.RenderStepped:Connect(function()
		local humanoid = getAliveHumanoid()
		if not humanoid then
			return
		end

		local root = humanoid.RootPart
		if root then
			clampToField(root)
		end

		local axis = InputController.getLateralAxis()
		local direction = (runDirection + rightDirection * axis * GameConstants.LATERAL_SPEED_WEIGHT).Unit
		humanoid:Move(direction)
	end)
end

function RunController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	getControls():Enable()
end

return RunController
