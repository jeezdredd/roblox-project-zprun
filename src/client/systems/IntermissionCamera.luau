--!strict

-- The camera during the helicopter intermission (docs/gameplay/heli-intermission.md),
-- for now only the placeholders the server flow needs:
--
--   Cabin  the seated view from this player's seat (the SeatView part the server
--          builds per seat in Workspace.IntermissionCabin), looking at the open door;
--          holding the right mouse button looks around (yaw +-100, pitch -50..40 from
--          the seat's view, eased), the cursor staying free for the panel.
--   Crash  the crash cinematic (CrashCinematic) over the same seat for the beat's
--          length, ending in black; a plain black fade when the cabin is missing.
--          The rotor drone of the ready check runs on into it.
--   After  the black holds a moment over the teleport to the wreck, then fades out and
--          the camera goes back to the run's controller.
--
-- Bound after the camera controllers (RenderPriority.Camera + 5) so it is the last
-- write while it holds; it lets go the moment FlowPhase leaves "Cabin".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local IntermissionConfig = require(ReplicatedStorage.Shared.config.IntermissionConfig)
local IntermissionMath = require(ReplicatedStorage.Shared.util.IntermissionMath)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local CrashCinematic = require(script.Parent.CrashCinematic)
local CursorMode = require(script.Parent.CursorMode)

local IntermissionCamera = {}

local RENDER_NAME = "TfzIntermissionCamera"
local CAMERA_OWNER = "Intermission"
local CABIN_NAME = "IntermissionCabin"
local FADE_IN = 0.6
local HOLD_AFTER = 0.4
local FADE_OUT = 0.8

local player = Players.LocalPlayer
local bound = false
local fade: Frame? = nil
local view: BasePart? = nil
local crashActive = false
-- the crash beat's end (server time) from the cabin snapshot; the stage attribute and
-- the snapshot travel separately, so the beat waits a moment for it
local crashEndsAt: number? = nil
local CRASH_WAIT = 0.5
-- the look around the cabin, degrees from the seat's view: where the mouse put it and
-- where the camera is on its way there
local looking = false
local targetYaw, targetPitch = 0, 0
local yaw, pitch = 0, 0

local function resetLook()
	looking = false
	targetYaw, targetPitch, yaw, pitch = 0, 0, 0, 0
end

local function lookAllowed(): boolean
	return bound and player:GetAttribute("IntermissionStage") == "Cabin"
end

local function ensureFade(): Frame
	local existing = fade
	if existing and existing.Parent then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntermissionFade"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Name = "Black"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	fade = frame
	return frame
end

local function fadeTo(transparency: number, seconds: number)
	TweenService:Create(ensureFade(), TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		BackgroundTransparency = transparency,
	}):Play()
end

local function findView(): BasePart?
	local seat = player:GetAttribute("CabinSeat")
	local cabin = Workspace:FindFirstChild(CABIN_NAME)
	if typeof(seat) ~= "number" or not cabin then
		return nil
	end
	local part = cabin:FindFirstChild("SeatView" .. tostring(seat))
	return if part and part:IsA("BasePart") then part else nil
end

local function hold(deltaTime: number)
	local camera = Workspace.CurrentCamera
	local target = view or findView()
	view = target
	if not camera or not target then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if not lookAllowed() then
		-- the crash beat: exactly the seat's view (the cinematic will own it)
		camera.CFrame = target.CFrame
		return
	end
	yaw = IntermissionMath.easeLook(IntermissionConfig, yaw, targetYaw, deltaTime)
	pitch = IntermissionMath.easeLook(IntermissionConfig, pitch, targetPitch, deltaTime)
	camera.CFrame = target.CFrame * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
end

local function bind()
	if bound then
		return
	end
	bound = true
	view = nil
	resetLook()
	-- the cabin panel frees the cursor; the camera stays ours meanwhile
	CursorMode.setCameraOwner(CAMERA_OWNER, true)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 5, hold)
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	view = nil
	resetLook()
	CursorMode.setCameraOwner(CAMERA_OWNER, false)
	RunService:UnbindFromRenderStep(RENDER_NAME)
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- The crash beat: the cinematic over this player's seat, ending on the black this
-- module holds over the teleport; a plain black fade when it cannot play.
function IntermissionCamera.playCrash(endsAt: number)
	local seat = player:GetAttribute("CabinSeat")
	local started = typeof(seat) == "number"
		and CrashCinematic.play({
			endsAt = endsAt,
			seat = seat,
			blackout = function(seconds: number)
				fadeTo(0, seconds)
			end,
		})
	if not started then
		fadeTo(0, FADE_IN)
	end
end

local function startCrash()
	local waited = 0
	local function go()
		if not crashActive or player:GetAttribute("IntermissionStage") ~= "Crash" then
			return
		end
		local endsAt = crashEndsAt
		if endsAt == nil and waited < CRASH_WAIT then
			waited += 0.05
			task.delay(0.05, go)
			return
		end
		IntermissionCamera.playCrash(endsAt or (Workspace:GetServerTimeNow() + IntermissionConfig.CRASH_LENGTH))
	end
	go()
end

local function apply()
	local phase = player:GetAttribute("FlowPhase")
	local stage = player:GetAttribute("IntermissionStage")
	if phase == "Cabin" then
		bind()
		if stage == "Crash" and not crashActive then
			-- the view goes back to the door the moment the beat changes
			resetLook()
			crashActive = true
			startCrash()
		elseif stage == "Cabin" then
			crashActive = false
			CrashCinematic.setCabinAmbience(true)
			fadeTo(1, FADE_OUT)
		end
		return
	end
	local wasCrash = crashActive
	crashActive = false
	crashEndsAt = nil
	CrashCinematic.stop()
	CrashCinematic.setCabinAmbience(false)
	unbind()
	if wasCrash then
		-- hold the black over the teleport to the wreck (black at once when a skip vote
		-- cut the beat short), then open on the run
		fadeTo(0, 0.05)
		task.delay(HOLD_AFTER, function()
			fadeTo(1, FADE_OUT)
		end)
	else
		fadeTo(1, 0.2)
	end
end

function IntermissionCamera.isHolding(): boolean
	return bound
end

function IntermissionCamera.init()
	for _, attribute in { "FlowPhase", "IntermissionStage", "CabinSeat" } do
		player:GetAttributeChangedSignal(attribute):Connect(apply)
	end
	player:GetAttributeChangedSignal("IntermissionStage"):Connect(resetLook)
	Remotes.getEvent(Remotes.Event.IntermissionState).OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) == "table" and snapshot.stage == "Crash" and typeof(snapshot.endsAt) == "number" then
			crashEndsAt = snapshot.endsAt
		elseif snapshot == nil then
			crashEndsAt = nil
		end
	end)

	-- right mouse held: the mouse looks around; released, the view stays where it is
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed and lookAllowed() then
			looking = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if looking and lookAllowed() and input.UserInputType == Enum.UserInputType.MouseMovement then
			targetYaw, targetPitch = IntermissionMath.lookAfter(IntermissionConfig, targetYaw, targetPitch, input.Delta.X, input.Delta.Y)
		end
	end)
	apply()
end

return IntermissionCamera
