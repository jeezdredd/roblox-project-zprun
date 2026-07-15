--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local InputController = require(script.Parent.InputController)

local RunController = {}

local runDirection = GameConstants.RUN_DIRECTION
local rightDirection = runDirection:Cross(Vector3.yAxis)
local wrapThreshold = GameConstants.LANE_WIDTH / 2 - GameConstants.WALL_WRAP_MARGIN

local function disableDefaultControls()
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule")) :: any
	playerModule:GetControls():Disable()
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

local function wrapAroundWalls(root: BasePart)
	local x = root.Position.X
	if math.abs(x) < wrapThreshold then
		return
	end
	local targetX = -math.sign(x) * (wrapThreshold - 0.5)
	root.CFrame = root.CFrame + Vector3.new(targetX - x, 0, 0)
end

function RunController.init()
	disableDefaultControls()

	RunService.RenderStepped:Connect(function()
		local humanoid = getAliveHumanoid()
		if not humanoid then
			return
		end

		local root = humanoid.RootPart
		if root then
			wrapAroundWalls(root)
		end

		local axis = InputController.getLateralAxis()
		local direction = (runDirection + rightDirection * axis * GameConstants.LATERAL_SPEED_WEIGHT).Unit
		humanoid:Move(direction)
	end)
end

return RunController
