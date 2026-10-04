--!strict

-- Weapon stances, manual lean and the magazine check on the first-person rig
-- (wiki: Stances; numbers in StanceConfig, rules in StanceMath).
--
-- - Stances: the stance key cycles mid, high ready and low ready. The pose goes into the
--   pack viewmodel's hold space through PackViewmodel.setStancePose, eased like the
--   wall pull-back. A shot from high or low ready asks requestFire first: the gun comes
--   up over the class's raise time and the shot leaves when it is up; it stays up for
--   StanceConfig.RETURN_AFTER after the last shot, then eases back to the chosen stance.
--   A reload, the draw or an inspect eases the pose out without changing the stance.
-- - Lean: Q and E (hold, or toggle) roll the camera and move it sideways, stopping short
--   of a wall at the side; the viewmodel takes part of the roll back and the
--   third-person upper body leans (BodyRig, with the value on the BodyAim packet). The
--   lean is put on the camera after the camera's own steps and taken off again before
--   them, so the runner camera's lerp never sees it. Visual only: nothing reaches the
--   server's rules.
-- - Magazine check: WeaponController turns a held R into startCheck/releaseCheck; the
--   weapon tips toward the camera and the count shows while it is in.
--
-- Only the pack viewmodel shows the poses. Without one (the legacy rig, the hub, death)
-- the viewmodel stops asking and every shot is allowed at once.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local StanceConfig = require(ReplicatedStorage.Shared.config.StanceConfig)
local StanceMath = require(ReplicatedStorage.Shared.util.StanceMath)
local CursorMode = require(script.Parent.CursorMode)

local Stances = {}

local UNDO_STEP = "StanceLeanUndo"
local APPLY_STEP = "StanceLeanApply"
-- the viewmodel stopped asking for a pose this long ago: no pack rig on screen
local STALE_AFTER = 0.25
-- folders the side cast never stops on (as WallPullback)
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

-- lean
local leftHeld = false
local rightHeld = false
local lastSide = 1
local toggled = 0
-- set by the Studio DebugWeapon hook (WeaponController): a lean held without keys
local debugLean: number? = nil
local lean = 0
local applied: CFrame? = nil
local appliedOffset = CFrame.identity
-- prompts on screen that use the right-lean key (E is ProximityPrompt's default)
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
	return camera.CameraType == Enum.CameraType.Scriptable
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

-- Distance to a wall on the lean's side, nil when clear.
local function sideHit(camera: Camera, eye: CFrame, side: number): number?
	params.FilterDescendantsInstances = ignoreList(camera)
	local settings = StanceConfig.LEAN
	local direction = eye.RightVector * side * (settings.offset + settings.wallMargin)
	local result = Workspace:Spherecast(eye.Position, settings.castRadius, direction, params)
	return if result then result.Distance else nil
end

-- Camera.Value - 1: take last frame's lean off, but only if nothing else moved the
-- camera since (a cut, the death camera), so the camera's own steps start clean.
local function undoLean()
	local camera = Workspace.CurrentCamera
	local last = applied
	applied = nil
	if camera and last and camera.CFrame == last then
		camera.CFrame = last * appliedOffset:Inverse()
	end
	appliedOffset = CFrame.identity
end

-- Camera.Value + 2: after CameraController and CameraEffectsController.
local function applyLean(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- outside a live run (death camera, cabin, a menu) the lean is gone at once, so no
	-- other camera ever gets it on top
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

-- One frame of the stance state and the pose for the pack viewmodel's stance channel:
-- the stance or check pose with the lean's counter-pose on top. `suppressed` while a
-- reload, the draw or an inspect plays.
function Stances.viewmodelPose(deltaTime: number, suppressed: boolean): CFrame
	local now = os.clock()
	if now - lastPoseAt > STALE_AFTER then
		-- the rig was away (death, the hub, a weapon change): start from mid again
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

-- A shot asks to leave. True at once without a pack rig on screen; otherwise true when
-- the gun is up, and false while it comes up (the shot waits for isUp).
function Stances.requestFire(class: string?): boolean
	if os.clock() - lastPoseAt > STALE_AFTER then
		return true
	end
	return StanceMath.requestFire(config, state, class, os.clock())
end

function Stances.isUp(): boolean
	return os.clock() - lastPoseAt > STALE_AFTER or StanceMath.isUp(config, state)
end

-- Whether a shot is waiting on a raise right now.
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

-- Whether the pack viewmodel is on screen asking for poses (the check and the stances
-- only exist there).
function Stances.posesShown(): boolean
	return os.clock() - lastPoseAt <= STALE_AFTER
end

function Stances.isChecking(): boolean
	return state.checking
end

function Stances.countVisible(): boolean
	return os.clock() - lastPoseAt <= STALE_AFTER and StanceMath.countVisible(config, state)
end

-- The eased lean, -1 (left) to 1 (right), for the body and the BodyAim packet.
function Stances.lean(): number
	return lean
end

-- The weights and the lean, for overlays and Studio checks.
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

-- Studio checks: hold a lean (-1..1) without keys, nil hands it back to the keys.
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
