--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)

local CameraController = {}

local RENDER_NAME = "RunnerCamera"

local bound = false
local hiddenCharacter: Model? = nil
local descendantConnection: RBXScriptConnection? = nil

local function setCharacterVisible(character: Model, visible: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

local function unhideCharacter()
	if descendantConnection then
		descendantConnection:Disconnect()
		descendantConnection = nil
	end
	local character = hiddenCharacter
	hiddenCharacter = nil
	if character then
		setCharacterVisible(character, true)
	end
end

local function hideCharacter(character: Model)
	if hiddenCharacter == character then
		return
	end
	unhideCharacter()
	hiddenCharacter = character
	setCharacterVisible(character, false)
	descendantConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 1
		end
	end)
end

local function updateCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		unhideCharacter()
		return
	end

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local runDirection = GameConstants.RUN_DIRECTION
	local eyePosition = root.Position + Vector3.new(0, 1.5, 0) + runDirection * 1
	local lookTarget = eyePosition + runDirection * GameConstants.CAMERA_LOOK_AHEAD
	local alpha = 1 - math.exp(-12 * deltaTime)
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eyePosition, lookTarget), alpha)

	hideCharacter(character)
end

function CameraController.start()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, updateCamera)
end

function CameraController.stop()
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end

	unhideCharacter()

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

return CameraController
