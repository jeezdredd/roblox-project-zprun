--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local CursorMode = require(script.Parent.Parent.systems.CursorMode)
local SettingsService = require(script.Parent.Parent.systems.SettingsService)

local CameraController = {}

local RENDER_NAME = "RunnerCamera"

local bound = false
local hiddenCharacter: Model? = nil
local descendantConnection: RBXScriptConnection? = nil

local function isHeadPiece(instance: Instance): boolean
	local part = if instance:IsA("Decal") then instance.Parent else instance
	if not part or not part:IsA("BasePart") then
		return false
	end
	if part.Name == "Head" then
		return true
	end
	local parent = part.Parent
	return parent ~= nil and parent:IsA("Accessory")
end

-- Even with "Show Own Body" on, the torso and arms sit inside the camera and fill
-- the frame with giant untextured slabs, and the arms duplicate the viewmodel's.
-- Only the legs read correctly when looking down, so everything above the waist
-- is hidden regardless of the setting.
local ALWAYS_HIDDEN = {
	UpperTorso = true,
	LowerTorso = true,
	Torso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
}

local function isAlwaysHidden(instance: Instance): boolean
	local part = if instance:IsA("Decal") then instance.Parent else instance
	if not part or not part:IsA("BasePart") then
		return false
	end
	if ALWAYS_HIDDEN[part.Name] then
		return true
	end
	-- the third-person weapon model is welded to the hand and would double the viewmodel
	local ancestor = part.Parent
	while ancestor do
		if ancestor.Name == "WorldWeapon" then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function setCharacterVisible(character: Model, visible: boolean)
	local keepBody = SettingsService.get("firstPersonBody") == true
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			local hide = not visible and (not keepBody or isHeadPiece(descendant) or isAlwaysHidden(descendant))
			descendant.LocalTransparencyModifier = if hide then 1 else 0
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
			local keepBody = SettingsService.get("firstPersonBody") == true
			descendant.LocalTransparencyModifier = if not keepBody or isHeadPiece(descendant) or isAlwaysHidden(descendant) then 1 else 0
		end
	end)
end

local function updateCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	-- Studio QA: a fixed shot for screenshots, set from the command bar as the workspace
	-- attribute DevCameraCFrame (nil gives the camera back)
	if RunService:IsStudio() then
		local shot = Workspace:GetAttribute("DevCameraCFrame")
		if typeof(shot) == "CFrame" then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = shot
			return
		end
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

	-- Reviewing animation on the third-person body: give the camera back to Roblox's
	-- orbit controller, keep the character visible and open up the zoom clamp that
	-- CursorMode uses to hold first person. Checked before FREEZE_RUN because both are
	-- inspection modes and this one wants the stock camera either way.
	-- (the test yard toggles the same view at run time with V, SandboxInput)
	if RunService:IsStudio() and (DevConfig.THIRD_PERSON_VIEW or Workspace:GetAttribute("DevThirdPerson") == true) then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		local localPlayer = Players.LocalPlayer
		if localPlayer.CameraMode ~= Enum.CameraMode.Classic then
			localPlayer.CameraMode = Enum.CameraMode.Classic
		end
		if localPlayer.CameraMaxZoomDistance < 24 then
			localPlayer.CameraMinZoomDistance = 6
			localPlayer.CameraMaxZoomDistance = 24
		end
		unhideCharacter()
		return
	end

	-- With the run frozen for inspection, the fixed runner camera would leave you staring
	-- down the corridor with no way to look at anything, since it has no mouse look at
	-- all. Hand the camera back to Roblox's own first-person controller and keep only the
	-- body hiding. The viewmodel tracks whatever drives camera.CFrame, so it follows.
	if RunService:IsStudio() and DevConfig.FREEZE_RUN then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		-- Not while a menu is open: this runs every frame, so forcing the lock here
		-- overrode CursorMode releasing the cursor and left menus unclickable.
		if not CursorMode.isAnyOpen() then
			Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		end
		hideCharacter(character)
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
