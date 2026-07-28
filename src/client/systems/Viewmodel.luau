--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ExertionState = require(script.Parent.Parent.controllers.ExertionState)

local Viewmodel = {}

local camera = Workspace.CurrentCamera
local player = Players.LocalPlayer

type Rig = {
	model: Model,
	root: BasePart,
	muzzle: Attachment,
	eject: Attachment,
	slide: BasePart?,
	slideWeld: Weld?,
	slideRest: CFrame,
	slideTravel: number,
	pump: BasePart?,
	pumpWeld: Weld?,
	pumpRest: CFrame,
	magazine: BasePart?,
	magazineWeld: Weld?,
	magazineRest: CFrame,
	class: string,
}

local rig: Rig? = nil
local isVisible = true

local recoilOffset = 0
local recoilPitch = 0
local recoilRoll = 0
local swayYaw = 0
local swayPitch = 0
local sprintBlend = 0
local equipT = 1
local slideT = 1
local pumpT = 1
local reloadT = 1
local reloadDuration = 1
local breathClock = 0
local lastCameraCFrame = camera.CFrame

local BASE_OFFSET = CFrame.new(1.05, -1.15, -1.55)

local COLOR_METAL = Color3.fromRGB(46, 48, 52)
local COLOR_STEEL = Color3.fromRGB(72, 74, 80)
local COLOR_GRIP = Color3.fromRGB(52, 44, 36)
local COLOR_WOOD = Color3.fromRGB(96, 72, 48)
local COLOR_SLEEVE = Color3.fromRGB(66, 74, 58)
local COLOR_GLOVE = Color3.fromRGB(38, 38, 40)
local COLOR_SKIN = Color3.fromRGB(192, 152, 120)

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = parent
	return part
end

local function weldTo(root: BasePart, part: BasePart, offset: CFrame): Weld
	local weldInstance = Instance.new("Weld")
	weldInstance.Part0 = root
	weldInstance.Part1 = part
	weldInstance.C0 = offset
	weldInstance.Parent = root
	part.CFrame = root.CFrame * offset
	return weldInstance
end

local function addWedge(root: BasePart, name: string, size: Vector3, color: Color3, offset: CFrame, parent: Instance)
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.Color = color
	wedge.Material = Enum.Material.Metal
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CanQuery = false
	wedge.CanTouch = false
	wedge.CastShadow = false
	wedge.Massless = true
	wedge.Parent = parent
	weldTo(root, wedge, offset)
end

local function buildArm(
	root: BasePart,
	model: Model,
	side: number,
	handOffset: CFrame,
	elbowDrop: number
)
	local hand = makePart("Hand", Vector3.new(0.34, 0.26, 0.4), COLOR_GLOVE, Enum.Material.Fabric, model)
	weldTo(root, hand, handOffset)
	local thumb = makePart("Thumb", Vector3.new(0.1, 0.1, 0.22), COLOR_GLOVE, Enum.Material.Fabric, model)
	weldTo(root, thumb, handOffset * CFrame.new(-side * 0.18, 0.1, 0.04))
	local fingers = makePart("Fingers", Vector3.new(0.3, 0.12, 0.14), COLOR_GLOVE, Enum.Material.Fabric, model)
	weldTo(root, fingers, handOffset * CFrame.new(0, -0.12, -0.2) * CFrame.Angles(math.rad(-24), 0, 0))

	local wristTarget = handOffset * CFrame.new(side * 0.12, -0.24, 0.3)
	local forearm = makePart("Forearm", Vector3.new(0.36, 0.36, 1.35), COLOR_SLEEVE, Enum.Material.Fabric, model)
	weldTo(
		root,
		forearm,
		wristTarget * CFrame.Angles(math.rad(-46 - elbowDrop), math.rad(side * 18), math.rad(side * 6)) * CFrame.new(0, 0, 0.55)
	)
	local sleeve = makePart("SleeveCuff", Vector3.new(0.42, 0.42, 0.24), COLOR_SLEEVE:Lerp(Color3.new(), 0.2), Enum.Material.Fabric, model)
	weldTo(root, sleeve, wristTarget * CFrame.Angles(math.rad(-46 - elbowDrop), math.rad(side * 18), 0) * CFrame.new(0, 0, 0.1))
	local wrist = makePart("Wrist", Vector3.new(0.3, 0.24, 0.26), COLOR_SKIN, Enum.Material.SmoothPlastic, model)
	weldTo(root, wrist, wristTarget * CFrame.new(0, 0.02, -0.04))

	local upper = makePart("UpperArm", Vector3.new(0.42, 0.42, 1.5), COLOR_SLEEVE, Enum.Material.Fabric, model)
	weldTo(
		root,
		upper,
		wristTarget
			* CFrame.Angles(math.rad(-46 - elbowDrop), math.rad(side * 18), 0)
			* CFrame.new(0, 0, 1.15)
			* CFrame.Angles(math.rad(-38), math.rad(side * 10), 0)
			* CFrame.new(0, 0, 0.5)
	)
end

local function buildRig(config: WeaponsConfig.WeaponConfig)
	local previous = rig
	if previous then
		previous.model:Destroy()
		rig = nil
	end

	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local root = makePart("VmRoot", Vector3.new(0.2, 0.2, 0.2), Color3.new(), Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	model.PrimaryPart = root

	local class = config.class
	local isPistol = class == "Pistol"
	local isShotgun = class == "Shotgun"

	local bodyLength = if isPistol then 0.82 else 1.9
	local bodyHeight = if isPistol then 0.36 else 0.42
	local barrelLength = if isPistol then 0.34 else 1.15
	if isShotgun then
		barrelLength = 1.35
	end

	local receiver = makePart("Receiver", Vector3.new(0.24, bodyHeight, bodyLength), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(root, receiver, CFrame.new(0, 0, 0))

	local slide: BasePart? = nil
	local slideWeld: Weld? = nil
	local slideRest = CFrame.new(0, bodyHeight / 2 + 0.05, 0)
	local slideTravel = 0.34
	if isPistol then
		slide = makePart("Slide", Vector3.new(0.26, 0.18, bodyLength + 0.1), COLOR_STEEL, Enum.Material.Metal, model)
		slideWeld = weldTo(root, slide :: BasePart, slideRest)
	else
		local rail = makePart("TopRail", Vector3.new(0.14, 0.08, bodyLength * 0.8), COLOR_STEEL, Enum.Material.Metal, model)
		weldTo(root, rail, CFrame.new(0, bodyHeight / 2 + 0.04, 0))
		if class == "Rifle" or class == "SMG" then
			slideRest = CFrame.new(0.17, 0.08, 0.2)
			slideTravel = 0.22
			slide = makePart("BoltHandle", Vector3.new(0.12, 0.08, 0.16), COLOR_STEEL, Enum.Material.Metal, model)
			slideWeld = weldTo(root, slide :: BasePart, slideRest)
		end
	end

	local barrel = makePart("Barrel", Vector3.new(0.13, 0.13, barrelLength), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(root, barrel, CFrame.new(0, if isPistol then 0.1 else 0.06, -(bodyLength / 2 + barrelLength / 2 - 0.06)))
	if not isPistol then
		local handguard = makePart(
			"Handguard",
			Vector3.new(0.26, 0.3, barrelLength * 0.62),
			if isShotgun then COLOR_WOOD else COLOR_GRIP,
			if isShotgun then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic,
			model
		)
		weldTo(root, handguard, CFrame.new(0, -0.05, -(bodyLength / 2 + barrelLength * 0.3)))
	end

	local frontSight = makePart("FrontSight", Vector3.new(0.05, 0.14, 0.05), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(root, frontSight, CFrame.new(0, (if isPistol then 0.24 else bodyHeight / 2 + 0.12), -(bodyLength / 2 + barrelLength - 0.15)))
	local rearSight = makePart("RearSight", Vector3.new(0.16, 0.1, 0.06), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(root, rearSight, CFrame.new(0, (if isPistol then 0.22 else bodyHeight / 2 + 0.1), bodyLength / 2 - 0.1))

	local gripAngle = CFrame.Angles(math.rad(18), 0, 0)
	local gripOffset = CFrame.new(0, -bodyHeight / 2 - 0.26, bodyLength / 2 - 0.18) * gripAngle
	local grip = makePart("Grip", Vector3.new(0.24, 0.58, 0.28), COLOR_GRIP, Enum.Material.SmoothPlastic, model)
	weldTo(root, grip, gripOffset)

	local triggerGuard = makePart("TriggerGuard", Vector3.new(0.06, 0.05, 0.34), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(root, triggerGuard, CFrame.new(0, -bodyHeight / 2 - 0.14, bodyLength / 2 - 0.42))

	local magazine: BasePart? = nil
	local magazineWeld: Weld? = nil
	local magazineRest = CFrame.new(0, -bodyHeight / 2 - 0.3, if isPistol then bodyLength / 2 - 0.18 else -0.1)
	if isPistol then
		magazine = makePart("Magazine", Vector3.new(0.18, 0.5, 0.22), COLOR_STEEL, Enum.Material.Metal, model)
		magazineWeld = weldTo(root, magazine :: BasePart, gripOffset * CFrame.new(0, -0.1, 0))
		magazineRest = gripOffset * CFrame.new(0, -0.1, 0)
	elseif not isShotgun then
		magazine = makePart("Magazine", Vector3.new(0.2, 0.62, 0.32), COLOR_METAL, Enum.Material.Metal, model)
		magazineRest = CFrame.new(0, -bodyHeight / 2 - 0.28, -0.16) * CFrame.Angles(math.rad(-10), 0, 0)
		magazineWeld = weldTo(root, magazine :: BasePart, magazineRest)
	end

	local pump: BasePart? = nil
	local pumpWeld: Weld? = nil
	local pumpRest = CFrame.new(0, -0.18, -(bodyLength / 2 + barrelLength * 0.32))
	if isShotgun then
		pump = makePart("Pump", Vector3.new(0.3, 0.24, 0.5), COLOR_WOOD, Enum.Material.WoodPlanks, model)
		pumpWeld = weldTo(root, pump :: BasePart, pumpRest)
	end

	if not isPistol then
		local stock = makePart(
			"Stock",
			Vector3.new(0.22, 0.34, 0.85),
			if isShotgun then COLOR_WOOD else COLOR_GRIP,
			if isShotgun then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic,
			model
		)
		weldTo(root, stock, CFrame.new(0, -0.08, bodyLength / 2 + 0.4) * CFrame.Angles(math.rad(-4), 0, 0))
		addWedge(root, "StockWedge", Vector3.new(0.22, 0.2, 0.5), if isShotgun then COLOR_WOOD else COLOR_GRIP, CFrame.new(0, 0.19, bodyLength / 2 + 0.42) * CFrame.Angles(0, math.rad(180), 0), model)
	end

	local ejectionPort = makePart("EjectionPort", Vector3.new(0.02, 0.08, 0.16), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic, model)
	weldTo(root, ejectionPort, CFrame.new(0.13, 0.06, if isPistol then 0.08 else 0.3))

	buildArm(root, model, 1, gripOffset * CFrame.new(0.04, -0.05, 0.1), 4)
	local supportOffset = if isPistol
		then gripOffset * CFrame.new(-0.14, -0.02, 0.02) * CFrame.Angles(0, math.rad(10), 0)
		else CFrame.new(-0.06, -0.24, -(bodyLength / 2 + barrelLength * 0.3)) * CFrame.Angles(math.rad(6), 0, 0)
	if isShotgun then
		supportOffset = pumpRest * CFrame.new(-0.02, -0.1, 0)
	end
	buildArm(root, model, -1, supportOffset, 14)

	local muzzleAttachment = Instance.new("Attachment")
	muzzleAttachment.Name = "Muzzle"
	muzzleAttachment.Position = Vector3.new(0, 0, -barrelLength / 2)
	muzzleAttachment.Parent = barrel

	local ejectAttachment = Instance.new("Attachment")
	ejectAttachment.Name = "Eject"
	ejectAttachment.Position = Vector3.new(0.1, 0.05, 0)
	ejectAttachment.Parent = ejectionPort

	model.Parent = camera

	rig = {
		model = model,
		root = root,
		muzzle = muzzleAttachment,
		eject = ejectAttachment,
		slide = slide,
		slideWeld = slideWeld,
		slideRest = slideRest,
		slideTravel = slideTravel,
		pump = pump,
		pumpWeld = pumpWeld,
		pumpRest = pumpRest,
		magazine = magazine,
		magazineWeld = magazineWeld,
		magazineRest = magazineRest,
		class = class,
	}
	isVisible = true
end

local function easeOutCubic(t: number): number
	local inv = 1 - t
	return 1 - inv * inv * inv
end

local function pulse(t: number, upEnd: number): number
	if t < upEnd then
		return t / upEnd
	end
	return math.max(1 - (t - upEnd) / (1 - upEnd), 0)
end

function Viewmodel.setWeapon(weaponId: string)
	local config = WeaponsConfig.get(weaponId)
	if config then
		buildRig(config)
		equipT = 0
		reloadT = 1
		slideT = 1
		pumpT = 1
	end
end

function Viewmodel.onFired(config: WeaponsConfig.WeaponConfig)
	recoilOffset = math.min(recoilOffset + config.recoilKick * 0.075, 0.45)
	recoilPitch = math.min(recoilPitch + config.recoilSnap * 0.045, 0.26)
	recoilRoll = math.clamp(recoilRoll + (math.random() - 0.4) * config.recoilSnap * 0.02, -0.06, 0.06)
	if config.class == "Pistol" or config.class == "Rifle" or config.class == "SMG" then
		slideT = 0
	end
	if config.class == "Shotgun" then
		pumpT = -0.35
	end
end

function Viewmodel.playReload(duration: number)
	reloadDuration = math.max(duration, 0.6)
	reloadT = 0
end

function Viewmodel.getMuzzlePosition(): Vector3
	local current = rig
	if current then
		return current.muzzle.WorldPosition
	end
	return camera.CFrame.Position + camera.CFrame.LookVector * 2
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
	for _, part in current.model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "VmRoot" then
			part.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

local function reloadPose(t: number, current: Rig): CFrame
	local tilt = pulse(t, 0.18)
	local pose = CFrame.Angles(math.rad(-14 * tilt), math.rad(8 * tilt), math.rad(-22 * tilt)) * CFrame.new(0.05 * tilt, -0.25 * tilt, 0.08 * tilt)

	local magazineWeld = current.magazineWeld
	if magazineWeld then
		local drop = 0
		if t >= 0.16 and t < 0.42 then
			drop = easeOutCubic((t - 0.16) / 0.26)
		elseif t >= 0.42 and t < 0.68 then
			drop = 1 - easeOutCubic((t - 0.42) / 0.26)
		end
		magazineWeld.C0 = current.magazineRest * CFrame.new(0, -drop * 1.1, drop * 0.15) * CFrame.Angles(math.rad(drop * 12), 0, 0)
	end

	if t >= 0.74 then
		local rackT = math.clamp((t - 0.74) / 0.22, 0, 1)
		local rack = math.sin(rackT * math.pi)
		local slideWeld = current.slideWeld
		if slideWeld then
			slideWeld.C0 = current.slideRest * CFrame.new(0, 0, rack * current.slideTravel)
		end
		local pumpWeld = current.pumpWeld
		if pumpWeld then
			pumpWeld.C0 = current.pumpRest * CFrame.new(0, 0, rack * 0.4)
		end
	end

	return pose
end

local function step(deltaTime: number)
	local current = rig
	if not current or not current.model.Parent then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		Viewmodel.setVisible(false)
		return
	end
	Viewmodel.setVisible(true)

	breathClock += deltaTime
	local cameraCFrame = camera.CFrame
	local delta = cameraCFrame:ToObjectSpace(lastCameraCFrame)
	lastCameraCFrame = cameraCFrame
	local deltaPitch, deltaYaw, _ = delta:ToEulerAnglesYXZ()

	local blend = math.clamp(deltaTime * 10, 0, 1)
	swayYaw += (math.clamp(deltaYaw * 2.2, -0.1, 0.1) - swayYaw) * blend
	swayPitch += (math.clamp(deltaPitch * 1.8, -0.09, 0.09) - swayPitch) * blend

	local decay = math.clamp(deltaTime * 8.5, 0, 1)
	recoilOffset += (0 - recoilOffset) * decay
	recoilPitch += (0 - recoilPitch) * decay
	recoilRoll += (0 - recoilRoll) * decay * 0.7

	if equipT < 1 then
		equipT = math.min(equipT + deltaTime / 0.35, 1)
	end
	if slideT < 1 then
		slideT = math.min(slideT + deltaTime / 0.16, 1)
		local slideWeld = current.slideWeld
		if slideWeld then
			local travel = math.sin(math.min(slideT, 1) * math.pi)
			slideWeld.C0 = current.slideRest * CFrame.new(0, 0, travel * current.slideTravel)
		end
	end
	if pumpT < 1 then
		pumpT = math.min(pumpT + deltaTime / 0.42, 1)
		local pumpWeld = current.pumpWeld
		if pumpWeld and pumpT >= 0 then
			local travel = math.sin(pumpT * math.pi)
			pumpWeld.C0 = current.pumpRest * CFrame.new(0, 0, travel * 0.4)
		end
	end

	local reloadOffset = CFrame.identity
	if reloadT < 1 then
		reloadT = math.min(reloadT + deltaTime / reloadDuration, 1)
		reloadOffset = reloadPose(reloadT, current)
		if reloadT >= 1 then
			local magazineWeld = current.magazineWeld
			if magazineWeld then
				magazineWeld.C0 = current.magazineRest
			end
		end
	end

	local running = ExertionState.isRunning()
	local sprintTarget = if running then 1 else 0
	sprintBlend += (sprintTarget - sprintBlend) * math.clamp(deltaTime * 5, 0, 1)

	local stridePhase = ExertionState.getStridePhase()
	local speedFactor = math.clamp(ExertionState.getSpeed() / 16, 0, 1)
	local bobX = math.sin(stridePhase) * 0.05 * speedFactor
	local bobY = -math.abs(math.cos(stridePhase)) * 0.06 * speedFactor
	local breatheY = math.sin(breathClock * 1.4) * 0.012
	local breatheRoll = math.sin(breathClock * 0.9) * 0.006

	local equipEase = easeOutCubic(equipT)
	local equipDrop = (1 - equipEase) * 1.4
	local equipTilt = (1 - equipEase) * 0.7

	local sprintOffset = CFrame.new(-0.25 * sprintBlend, -0.18 * sprintBlend, 0.12 * sprintBlend)
		* CFrame.Angles(math.rad(-9 * sprintBlend), math.rad(16 * sprintBlend), math.rad(-7 * sprintBlend))

	local targetCFrame = cameraCFrame
		* BASE_OFFSET
		* CFrame.new(bobX + swayYaw * 1.5, bobY + breatheY + swayPitch * 1.1 - equipDrop, recoilOffset)
		* CFrame.Angles(
			recoilPitch + swayPitch * 0.55 - equipTilt,
			swayYaw * 0.75,
			swayYaw * 0.28 + recoilRoll + breatheRoll
		)
		* sprintOffset
		* reloadOffset

	current.model:PivotTo(targetCFrame)
end

function Viewmodel.init()
	camera = Workspace.CurrentCamera
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = Workspace.CurrentCamera
		local weaponId = player:GetAttribute("WeaponId")
		if typeof(weaponId) == "string" then
			Viewmodel.setWeapon(weaponId)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Viewmodel
