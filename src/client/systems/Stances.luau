--!strict

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local StanceConfig = require(ReplicatedStorage.Shared.config.StanceConfig)
local DevMode = require(ReplicatedStorage.Shared.util.DevMode)
local StanceMath = require(ReplicatedStorage.Shared.util.StanceMath)
local CursorMode = require(script.Parent.CursorMode)

local Stances = {}

local UNDO_STEP = "StanceLeanUndo"
local APPLY_STEP = "StanceLeanApply"
local STALE_AFTER = 0.25
local IGNORED_FOLDERS = { "Zombies", "ZombieProps", "Pickups", "WeaponVfx" }

local player = Players.LocalPlayer
local config = StanceConfig :: any
local state = StanceMath.new()
local lastPoseAt = -math.huge

local function keyCode(name: string): Enum.KeyCode?
	local ok, value = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok and typeof(value) == "EnumItem" then value else nil
end

local STANCE_KEY = keyCode(StanceConfig.keys.stance)
local LEFT_KEY = keyCode(StanceConfig.keys.leanLeft)
local RIGHT_KEY = keyCode(StanceConfig.keys.leanRight)

local leftHeld = false
local rightHeld = false
local lastSide = 1
local toggled = 0
local debugLean: number? = nil
local lean = 0
local applied: CFrame? = nil
local appliedOffset = CFrame.identity
local promptsOnKey: { [ProximityPrompt]: boolean } = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

local function isAlive(): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0
end

local function leanAllowed(camera: Camera): boolean
	local runnerCamera = camera.CameraType == Enum.CameraType.Scriptable
		or (
			camera.CameraType == Enum.CameraType.Custom
			and DevMode.frozen()
			and Workspace:GetAttribute("DevThirdPerson") ~= true
		)
	return runnerCamera
		and player:GetAttribute("FlowPhase") == "Mission"
		and isAlive()
		and not CursorMode.isAnyOpen()
end

local function promptBlocksRight(): boolean
	return next(promptsOnKey) ~= nil
end

local function leanTarget(): number
	if debugLean ~= nil then
		return debugLean
	end
	if StanceConfig.LEAN.mode == "toggle" then
		return toggled
	end
	return StanceMath.leanHeld(leftHeld, rightHeld and not promptBlocksRight(), lastSide)
end

local function ignoreList(camera: Camera): { Instance }
	local list: { Instance } = { camera }
	local character = player.Character
	if character then
		table.insert(list, character)
	end
	for _, name in IGNORED_FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

local function sideHit(camera: Camera, eye: CFrame, side: number): number?
	params.FilterDescendantsInstances = ignoreList(camera)
	local settings = StanceConfig.LEAN
	local direction = eye.RightVector * side * (settings.offset + settings.wallMargin)
	local result = Workspace:Spherecast(eye.Position, settings.castRadius, direction, params)
	return if result then result.Distance else nil
end

local function undoLean()
	local camera = Workspace.CurrentCamera
	local last = applied
	applied = nil
	if camera and last and camera.CFrame == last then
		camera.CFrame = last * appliedOffset:Inverse()
	end
	appliedOffset = CFrame.identity
end

local function applyLean(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not leanAllowed(camera) then
		lean = 0
		return
	end
	local settings = StanceConfig.LEAN
	lean = StanceMath.ease(lean, leanTarget(), settings.easeIn, settings.easeOut, deltaTime)
	if lean == 0 then
		return
	end
	local eye = camera.CFrame
	local side = if lean < 0 then -1 else 1
	local room = StanceMath.leanRoom(config, sideHit(camera, eye, side))
	local x, y, roll = StanceMath.leanCamera(config, lean, room)
	local offset = CFrame.new(x, y, 0) * CFrame.Angles(0, 0, math.rad(roll))
	camera.CFrame = eye * offset
	applied = camera.CFrame
	appliedOffset = offset
end

local function poseCFrame(pose: StanceMath.Pose): CFrame
	return CFrame.new(pose.aside, pose.up, pose.back) * CFrame.Angles(math.rad(pose.pitch), math.rad(pose.yaw), math.rad(pose.roll))
end

function Stances.viewmodelPose(deltaTime: number, suppressed: boolean): CFrame
	local now = os.clock()
	if now - lastPoseAt > STALE_AFTER then
		state.high = 0
		state.low = 0
		state.mag = 0
		state.raising = nil
	end
	lastPoseAt = now
	StanceMath.step(config, state, deltaTime, now, suppressed)
	local pose = StanceMath.added(StanceMath.pose(config, state), StanceMath.leanViewmodel(config, lean))
	return poseCFrame(pose)
end

function Stances.requestFire(class: string?): boolean
	if os.clock() - lastPoseAt > STALE_AFTER then
		return true
	end
	return StanceMath.requestFire(config, state, class, os.clock())
end

function Stances.isUp(): boolean
	return os.clock() - lastPoseAt > STALE_AFTER or StanceMath.isUp(config, state)
end

function Stances.isRaising(): boolean
	return state.raising ~= nil
end

function Stances.cycleStance()
	StanceMath.select(state, StanceMath.nextStance(config, state.selected))
end

function Stances.stance(): string
	return state.selected
end

function Stances.startCheck()
	StanceMath.startCheck(state, os.clock())
end

function Stances.releaseCheck()
	StanceMath.releaseCheck(config, state, os.clock())
end

function Stances.cancelCheck()
	StanceMath.cancelCheck(state)
end

function Stances.posesShown(): boolean
	return os.clock() - lastPoseAt <= STALE_AFTER
end

function Stances.isChecking(): boolean
	return state.checking
end

function Stances.countVisible(): boolean
	return os.clock() - lastPoseAt <= STALE_AFTER and StanceMath.countVisible(config, state)
end

function Stances.lean(): number
	return lean
end

function Stances.describe(): string
	return string.format(
		"stance=%s high=%.2f low=%.2f mag=%.2f raising=%s lean=%.2f",
		state.selected,
		state.high,
		state.low,
		state.mag,
		tostring(state.raising ~= nil),
		lean
	)
end

function Stances.setDebugLean(value: number?)
	debugLean = if value then math.clamp(value, -1, 1) else nil
end

function Stances.reset()
	state = StanceMath.new()
	leftHeld = false
	rightHeld = false
	toggled = 0
end

local function watchPrompt(prompt: ProximityPrompt, shown: boolean)
	if shown and RIGHT_KEY and prompt.KeyboardKeyCode == RIGHT_KEY then
		promptsOnKey[prompt] = true
	else
		promptsOnKey[prompt] = nil
	end
end

function Stances.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == STANCE_KEY then
			Stances.cycleStance()
		elseif key == LEFT_KEY then
			leftHeld = true
			lastSide = -1
			toggled = StanceMath.leanToggled(toggled, -1)
		elseif key == RIGHT_KEY then
			if promptBlocksRight() then
				return
			end
			rightHeld = true
			lastSide = 1
			toggled = StanceMath.leanToggled(toggled, 1)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == LEFT_KEY then
			leftHeld = false
		elseif input.KeyCode == RIGHT_KEY then
			rightHeld = false
		end
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		watchPrompt(prompt, true)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		watchPrompt(prompt, false)
	end)
	player.CharacterAdded:Connect(Stances.reset)
	RunService:BindToRenderStep(UNDO_STEP, Enum.RenderPriority.Camera.Value - 1, undoLean)
	RunService:BindToRenderStep(APPLY_STEP, Enum.RenderPriority.Camera.Value + 2, applyLean)
end

return Stances
