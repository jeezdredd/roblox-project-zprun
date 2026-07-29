--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ViewmodelConfig = require(ReplicatedStorage.Shared.config.ViewmodelConfig)
local Spring = require(ReplicatedStorage.Shared.util.Spring)
local ExertionState = require(script.Parent.Parent.controllers.ExertionState)
local InputController = require(script.Parent.Parent.controllers.InputController)
local CameraEffectsController = require(script.Parent.Parent.controllers.CameraEffectsController)
local ViewmodelBuilder = require(script.Parent.ViewmodelBuilder)
local AnimationSequencer = require(script.Parent.AnimationSequencer)

local Viewmodel = {}

local player = Players.LocalPlayer

local rig: ViewmodelBuilder.Rig? = nil
local isVisible = true
local sequencer = AnimationSequencer.new("Pistol")
local phaseListeners: { (string) -> () } = {}
local sprintActive = false

local function makeSpring(id: string)
	local setting = ViewmodelConfig.spring(id)
	return Spring.vector(setting.stiffness, setting.damping)
end

local swayRot = makeSpring("sway")
local swayPos = makeSpring("sway")
local lagRot = makeSpring("lag")
local movePos = makeSpring("movePos")
local moveRot = makeSpring("moveRot")
local recoilPos = makeSpring("recoilPos")
local recoilRot = makeSpring("recoilRot")
local tiltRoll = makeSpring("tiltRoll")
local impactPos = makeSpring("impactPos")
local breathe = makeSpring("breathe")
local equipOffset = makeSpring("equip")
local inspectOffset = makeSpring("inspect")

local mechanismSetting = ViewmodelConfig.spring("mechanism")
local slideSpring = Spring.number(mechanismSetting.stiffness, mechanismSetting.damping)
local pumpSpring = Spring.number(mechanismSetting.stiffness, mechanismSetting.damping)
local magazineSpring = Spring.number(mechanismSetting.stiffness, mechanismSetting.damping)

local cameraHistory: { CFrame } = {}
local historyCursor = 0
local sprintBlend = 0
local breathClock = 0
local lastCameraCFrame: CFrame? = nil
local lastVerticalVelocity = 0
local inspecting = false

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function pushCameraHistory(cframe: CFrame)
	local frames = math.max(1, ViewmodelConfig.lag.frames)
	historyCursor += 1
	cameraHistory[(historyCursor % frames) + 1] = cframe
end

local function laggedCamera(current: CFrame): CFrame
	local frames = math.max(1, ViewmodelConfig.lag.frames)
	local index = ((historyCursor + 1) % frames) + 1
	return cameraHistory[index] or current
end

function Viewmodel.setWeapon(weaponId: string)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	local camera = currentCamera()
	if not camera then
		return
	end

	local previous = rig
	if previous then
		previous.model:Destroy()
	end
	rig = ViewmodelBuilder.build(config, camera)
	isVisible = true

	recoilPos:SetProperties(config.recoilStiffness, config.recoilDamping)
	recoilRot:SetProperties(config.recoilStiffness * 1.1, config.recoilDamping)
	recoilPos:Reset(Vector3.zero)
	recoilRot:Reset(Vector3.zero)
	slideSpring:Reset(0)
	pumpSpring:Reset(0)
	magazineSpring:Reset(0)
	equipOffset:Reset(Vector3.new(0, -ViewmodelConfig.equip.drop, 0))
	equipOffset:SetTarget(Vector3.zero)
	inspectOffset:Reset(Vector3.zero)
	inspecting = false

	sequencer:setClass(config.class)
	sequencer:play("Equip")
	sprintActive = false
end

function Viewmodel.onFired(config: WeaponsConfig.WeaponConfig)
	recoilPos:Impulse(Vector3.new(
		(math.random() - 0.5) * config.recoilSnap * 0.35,
		config.recoilKick * 0.5,
		config.recoilKick * 1.7
	))
	recoilRot:Impulse(Vector3.new(
		config.recoilSnap * 2.6,
		(math.random() - 0.5) * config.recoilSnap * 1.1,
		(math.random() - 0.5) * config.recoilSnap * 1.6
	))

	local kick = config.cameraKick
	CameraEffectsController.impulse(Vector3.new((math.random() - 0.5) * 0.6, 1, 0.25), kick * 6)
	CameraEffectsController.fovKick(kick * 0.6)

	if config.class == "Shotgun" then
		pumpSpring:Impulse(9)
	else
		slideSpring:Impulse(14)
	end
end

-- The authored sequence drives the pose and the audio phases; the springs only add
-- the mechanical travel on top, so nothing here runs on a wall-clock timer any more.
function Viewmodel.playReload(_duration: number, magazineEmpty: boolean?)
	sequencer:play(if magazineEmpty then "ReloadFull" else "ReloadShort")
	sprintActive = false
end

function Viewmodel.onPhase(listener: (string) -> ())
	table.insert(phaseListeners, listener)
end

function Viewmodel.toggleInspect()
	if not inspecting then
		sequencer:play("Inspect")
	end
	inspecting = not inspecting
	inspectOffset:SetTarget(if inspecting then Vector3.one else Vector3.zero)
	if inspecting then
		task.delay(ViewmodelConfig.inspect.holdTime, function()
			if inspecting then
				inspecting = false
				inspectOffset:SetTarget(Vector3.zero)
			end
		end)
	end
end

function Viewmodel.getMuzzlePosition(): Vector3
	local current = rig
	if current then
		return current.muzzle.WorldPosition
	end
	local camera = currentCamera()
	if camera then
		return camera.CFrame.Position + camera.CFrame.LookVector * 2
	end
	return Vector3.zero
end

function Viewmodel.getMuzzleAttachment(): Attachment?
	local current = rig
	return if current then current.muzzle else nil
end

function Viewmodel.getEjectAttachment(): Attachment?
	local current = rig
	return if current then current.eject else nil
end

function Viewmodel.setVisible(visible: boolean)
	local current = rig
	if not current or isVisible == visible then
		return
	end
	isVisible = visible
	for _, node in current.nodes do
		node.part.LocalTransparencyModifier = if visible then 0 else 1
	end
end

local function updateChannels(deltaTime: number, cameraCFrame: CFrame)
	local previousCFrame = lastCameraCFrame or cameraCFrame
	lastCameraCFrame = cameraCFrame

	local deltaPitch, deltaYaw = previousCFrame:ToObjectSpace(cameraCFrame):ToEulerAnglesYXZ()
	local swaySetting = ViewmodelConfig.sway
	local yawImpulse = math.clamp(deltaYaw * swaySetting.yawImpulse, -swaySetting.maxImpulse, swaySetting.maxImpulse)
	local pitchImpulse = math.clamp(deltaPitch * swaySetting.pitchImpulse, -swaySetting.maxImpulse, swaySetting.maxImpulse)
	swayRot:Impulse(Vector3.new(-pitchImpulse, -yawImpulse, -yawImpulse * 0.4))
	swayPos:Impulse(Vector3.new(yawImpulse, pitchImpulse, 0))

	local lagged = laggedCamera(cameraCFrame)
	local lagPitch, lagYaw, lagRoll = cameraCFrame:ToObjectSpace(lagged):ToEulerAnglesYXZ()
	lagRot:SetTarget(Vector3.new(lagPitch, lagYaw, lagRoll) * ViewmodelConfig.lag.rotationScale)

	local bob = ViewmodelConfig.bob
	local stridePhase = ExertionState.getStridePhase()
	local speedFactor = math.clamp(ExertionState.getSpeed() / bob.speedReference, 0, 1)
	movePos:SetTarget(Vector3.new(
		math.sin(stridePhase) * bob.horizontal * speedFactor,
		-math.abs(math.cos(stridePhase)) * bob.vertical * speedFactor,
		0
	))
	moveRot:SetTarget(Vector3.new(
		math.cos(stridePhase * 2) * bob.pitch * speedFactor,
		0,
		math.sin(stridePhase) * bob.roll * speedFactor
	))

	local breatheSetting = ViewmodelConfig.breathe
	breathClock += deltaTime
	breathe:SetTarget(Vector3.new(
		0,
		math.sin(breathClock * breatheSetting.rate) * breatheSetting.amplitude,
		math.sin(breathClock * breatheSetting.rate * 0.65) * breatheSetting.rollAmplitude
	))

	local axis = InputController.getLateralAxis()
	tiltRoll:SetTarget(Vector3.new(ViewmodelConfig.tilt.lateralShift * axis, 0, -ViewmodelConfig.tilt.roll * axis))

	local sprint = ViewmodelConfig.sprint
	local running = ExertionState.isRunning()
	sprintBlend += ((if running then 1 else 0) - sprintBlend) * math.clamp(deltaTime * sprint.blendRate, 0, 1)

	swayRot:Update(deltaTime)
	swayPos:Update(deltaTime)
	lagRot:Update(deltaTime)
	movePos:Update(deltaTime)
	moveRot:Update(deltaTime)
	recoilPos:Update(deltaTime)
	recoilRot:Update(deltaTime)
	tiltRoll:Update(deltaTime)
	impactPos:Update(deltaTime)
	breathe:Update(deltaTime)
	equipOffset:Update(deltaTime)
	inspectOffset:Update(deltaTime)
	slideSpring:Update(deltaTime)
	pumpSpring:Update(deltaTime)
	magazineSpring:Update(deltaTime)
end

local function trackImpact(deltaTime: number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local verticalVelocity = root.AssemblyLinearVelocity.Y
	local settings = ViewmodelConfig.impact
	if lastVerticalVelocity < -12 and verticalVelocity > -2 then
		local strength = math.min(math.abs(lastVerticalVelocity) * settings.landScale, settings.maxLand)
		impactPos:Impulse(Vector3.new(0, -strength * 14, 0))
	end
	lastVerticalVelocity += (verticalVelocity - lastVerticalVelocity) * math.clamp(deltaTime * 20, 0, 1)
end

local function step(deltaTime: number)
	local current = rig
	local camera = currentCamera()
	if not current or not camera or current.model.Parent ~= camera then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		Viewmodel.setVisible(false)
		return
	end
	Viewmodel.setVisible(true)

	local cameraCFrame = camera.CFrame
	pushCameraHistory(cameraCFrame)
	trackImpact(deltaTime)
	updateChannels(deltaTime, cameraCFrame)

	local swayScale = ViewmodelConfig.sway.positionScale
	local swayPosValue = swayPos.value * swayScale
	local sprint = ViewmodelConfig.sprint
	local inspectBlend = inspectOffset.value.X
	local inspectSetting = ViewmodelConfig.inspect
	local equipValue = equipOffset.value
	local equipTilt = -equipValue.Y / math.max(ViewmodelConfig.equip.drop, 0.001) * ViewmodelConfig.equip.tilt

	local position = swayPosValue
		+ movePos.value
		+ breathe.value
		+ impactPos.value
		+ tiltRoll.value
		+ equipValue
		+ recoilPos.value * -1
		+ sprint.position * sprintBlend
		+ inspectSetting.position * inspectBlend

	local rotation = swayRot.value
		+ lagRot.value
		+ moveRot.value
		+ recoilRot.value * 0.02
		+ Vector3.new(equipTilt, 0, 0)
		+ sprint.rotation * sprintBlend
		+ inspectSetting.rotation * inspectBlend
		+ Vector3.new(0, 0, tiltRoll.value.Z)

	local rootCFrame = cameraCFrame
		* ViewmodelConfig.BASE_OFFSET
		* CFrame.new(position)
		* CFrame.Angles(rotation.X, rotation.Y, rotation.Z)

	local slideOffset = CFrame.new(0, 0, math.clamp(slideSpring.value, 0, 1) * current.slideTravel)
	local pumpOffset = CFrame.new(0, 0, math.clamp(pumpSpring.value, 0, 1) * current.pumpTravel)
	local magazineDrop = math.clamp(magazineSpring.value, 0, 1)
	local magazineOffset = CFrame.new(0, -magazineDrop * 1.1, magazineDrop * 0.15) * CFrame.Angles(math.rad(magazineDrop * 14), 0, 0)

	local supportHand: CFrame? = nil
	if current.class ~= "Shotgun" and magazineDrop > 0.01 then
		supportHand = CFrame.new(0, -magazineDrop * 0.55, magazineDrop * 0.22) * CFrame.Angles(math.rad(magazineDrop * 20), 0, 0)
	end

	-- Sprint is the only looping sequence, and it yields to anything the player
	-- actively triggered: firing, reloading or inspecting.
	local isRunning = ExertionState.isRunning()
	if not sequencer:isPlaying() and isRunning then
		sequencer:play("Sprint")
		sprintActive = true
	elseif sprintActive and not isRunning and sequencer:isPlaying("Sprint") then
		sequencer:stop()
		sprintActive = false
	end

	local authored = sequencer:update(deltaTime)

	ViewmodelBuilder.pose(current, rootCFrame, {
		slide = slideOffset,
		pump = pumpOffset,
		magazine = magazineOffset,
		supportHand = supportHand,
		bones = authored,
	})
end

function Viewmodel.init()
	sequencer:onPhase(function(name)
		for _, listener in phaseListeners do
			listener(name)
		end
	end)

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local weaponId = player:GetAttribute("WeaponId")
		if typeof(weaponId) == "string" then
			Viewmodel.setWeapon(weaponId)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Viewmodel
