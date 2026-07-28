--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ExertionState = require(script.Parent.Parent.controllers.ExertionState)

local Viewmodel = {}

local player = Players.LocalPlayer

type Piece = {
	part: BasePart,
	offset: CFrame,
}

type Rig = {
	model: Model,
	pieces: { Piece },
	muzzle: Attachment,
	eject: Attachment,
	slide: BasePart?,
	slideRest: CFrame,
	slideTravel: number,
	pump: BasePart?,
	pumpRest: CFrame,
	pumpTravel: number,
	magazine: BasePart?,
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
local lastCameraCFrame: CFrame? = nil

local BASE_OFFSET = CFrame.new(0.9, -0.9, -1.9)

local COLOR_METAL = Color3.fromRGB(46, 48, 52)
local COLOR_STEEL = Color3.fromRGB(72, 74, 80)
local COLOR_GRIP = Color3.fromRGB(52, 44, 36)
local COLOR_WOOD = Color3.fromRGB(96, 72, 48)
local COLOR_SLEEVE = Color3.fromRGB(66, 74, 58)
local COLOR_GLOVE = Color3.fromRGB(38, 38, 40)
local COLOR_SKIN = Color3.fromRGB(192, 152, 120)

local function currentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function addPiece(target: Rig, className: string, name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = target.model
	table.insert(target.pieces, { part = part, offset = offset })
	return part
end

local function buildArm(target: Rig, side: number, handOffset: CFrame, elbowPitch: number)
	addPiece(target, "Part", "Hand", Vector3.new(0.34, 0.26, 0.4), COLOR_GLOVE, Enum.Material.Fabric, handOffset)
	addPiece(target, "Part", "Thumb", Vector3.new(0.1, 0.1, 0.22), COLOR_GLOVE, Enum.Material.Fabric, handOffset * CFrame.new(-side * 0.18, 0.1, 0.04))
	addPiece(
		target,
		"Part",
		"Fingers",
		Vector3.new(0.3, 0.12, 0.14),
		COLOR_GLOVE,
		Enum.Material.Fabric,
		handOffset * CFrame.new(0, -0.12, -0.2) * CFrame.Angles(math.rad(-24), 0, 0)
	)

	local wrist = handOffset * CFrame.new(side * 0.1, -0.16, 0.26)
	addPiece(target, "Part", "Wrist", Vector3.new(0.3, 0.24, 0.26), COLOR_SKIN, Enum.Material.SmoothPlastic, wrist)

	local forearmAxis = wrist * CFrame.Angles(math.rad(elbowPitch), math.rad(side * 16), 0)
	addPiece(target, "Part", "SleeveCuff", Vector3.new(0.42, 0.42, 0.24), COLOR_SLEEVE:Lerp(Color3.new(), 0.25), Enum.Material.Fabric, forearmAxis * CFrame.new(0, 0, 0.12))
	addPiece(target, "Part", "Forearm", Vector3.new(0.36, 0.36, 1.35), COLOR_SLEEVE, Enum.Material.Fabric, forearmAxis * CFrame.new(0, 0, 0.72))

	local elbow = forearmAxis * CFrame.new(0, 0, 1.4)
	local upperAxis = elbow * CFrame.Angles(math.rad(30), math.rad(side * 8), 0)
	addPiece(target, "Part", "UpperArm", Vector3.new(0.42, 0.42, 1.4), COLOR_SLEEVE, Enum.Material.Fabric, upperAxis * CFrame.new(0, 0, 0.6))
end

local function buildRig(config: WeaponsConfig.WeaponConfig)
	local previous = rig
	if previous then
		previous.model:Destroy()
		rig = nil
	end

	local camera = currentCamera()
	if not camera then
		return
	end

	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local class = config.class
	local isPistol = class == "Pistol"
	local isShotgun = class == "Shotgun"

	local bodyLength = if isPistol then 0.82 else 1.9
	local bodyHeight = if isPistol then 0.36 else 0.42
	local barrelLength = if isPistol then 0.34 else 1.15
	if isShotgun then
		barrelLength = 1.35
	end

	local target: Rig = {
		model = model,
		pieces = {},
		muzzle = Instance.new("Attachment"),
		eject = Instance.new("Attachment"),
		slide = nil,
		slideRest = CFrame.identity,
		slideTravel = 0.3,
		pump = nil,
		pumpRest = CFrame.identity,
		pumpTravel = 0.18,
		magazine = nil,
		magazineRest = CFrame.identity,
		class = class,
	}

	addPiece(target, "Part", "Receiver", Vector3.new(0.24, bodyHeight, bodyLength), COLOR_METAL, Enum.Material.Metal, CFrame.identity)

	local slideTopY = bodyHeight / 2 + 0.09
	if isPistol then
		target.slideRest = CFrame.new(0, bodyHeight / 2 + 0.05, 0)
		target.slideTravel = 0.3
		target.slide = addPiece(target, "Part", "Slide", Vector3.new(0.26, 0.18, bodyLength + 0.1), COLOR_STEEL, Enum.Material.Metal, target.slideRest)
	else
		addPiece(target, "Part", "TopRail", Vector3.new(0.14, 0.08, bodyLength * 0.8), COLOR_STEEL, Enum.Material.Metal, CFrame.new(0, bodyHeight / 2 + 0.04, 0))
		if class == "Rifle" or class == "SMG" then
			target.slideRest = CFrame.new(0.17, 0.08, 0.2)
			target.slideTravel = 0.22
			target.slide = addPiece(target, "Part", "BoltHandle", Vector3.new(0.12, 0.08, 0.16), COLOR_STEEL, Enum.Material.Metal, target.slideRest)
		end
	end

	local barrelY = if isPistol then 0.08 else 0.06
	addPiece(target, "Part", "Barrel", Vector3.new(0.13, 0.13, barrelLength), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, barrelY, -(bodyLength / 2 + barrelLength / 2 - 0.06)))

	if isShotgun then
		target.pumpRest = CFrame.new(0, -0.16, -(bodyLength / 2 + barrelLength * 0.34))
		target.pumpTravel = 0.3
		target.pump = addPiece(target, "Part", "Pump", Vector3.new(0.3, 0.26, 0.62), COLOR_WOOD, Enum.Material.WoodPlanks, target.pumpRest)
		addPiece(target, "Part", "MagTube", Vector3.new(0.13, 0.13, barrelLength * 0.8), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, barrelY - 0.16, -(bodyLength / 2 + barrelLength * 0.42)))
	elseif not isPistol then
		addPiece(
			target,
			"Part",
			"Handguard",
			Vector3.new(0.26, 0.3, barrelLength * 0.62),
			COLOR_GRIP,
			Enum.Material.SmoothPlastic,
			CFrame.new(0, -0.05, -(bodyLength / 2 + barrelLength * 0.3))
		)
	end

	local sightY = if isPistol then slideTopY + 0.14 else bodyHeight / 2 + 0.12
	local frontSightZ = if isPistol then -(bodyLength / 2 - 0.06) else -(bodyLength / 2 + barrelLength - 0.15)
	addPiece(target, "Part", "FrontSight", Vector3.new(0.05, 0.12, 0.05), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, sightY, frontSightZ))
	addPiece(target, "Part", "RearSight", Vector3.new(0.16, 0.1, 0.06), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, sightY - 0.01, bodyLength / 2 - 0.12))
	if not isPistol then
		addPiece(target, "Part", "SightPost", Vector3.new(0.04, 0.14, 0.04), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, barrelY + 0.1, frontSightZ))
	end

	local gripOffset = CFrame.new(0, -bodyHeight / 2 - 0.26, bodyLength / 2 - 0.18) * CFrame.Angles(math.rad(-18), 0, 0)
	addPiece(target, "Part", "Grip", Vector3.new(0.24, 0.58, 0.28), COLOR_GRIP, Enum.Material.SmoothPlastic, gripOffset)
	addPiece(target, "Part", "TriggerGuard", Vector3.new(0.06, 0.05, 0.34), COLOR_METAL, Enum.Material.Metal, CFrame.new(0, -bodyHeight / 2 - 0.12, bodyLength / 2 - 0.42))

	if isPistol then
		target.magazineRest = gripOffset * CFrame.new(0, -0.06, 0)
		target.magazine = addPiece(target, "Part", "Magazine", Vector3.new(0.18, 0.5, 0.22), COLOR_STEEL, Enum.Material.Metal, target.magazineRest)
	elseif not isShotgun then
		target.magazineRest = CFrame.new(0, -bodyHeight / 2 - 0.28, -0.16) * CFrame.Angles(math.rad(10), 0, 0)
		target.magazine = addPiece(target, "Part", "Magazine", Vector3.new(0.2, 0.62, 0.32), COLOR_METAL, Enum.Material.Metal, target.magazineRest)
	end

	if not isPistol then
		local stockColor = if isShotgun then COLOR_WOOD else COLOR_GRIP
		local stockMaterial = if isShotgun then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
		addPiece(target, "Part", "Stock", Vector3.new(0.22, 0.34, 0.8), stockColor, stockMaterial, CFrame.new(0, -0.08, bodyLength / 2 + 0.36) * CFrame.Angles(math.rad(-4), 0, 0))
		addPiece(target, "WedgePart", "StockComb", Vector3.new(0.22, 0.18, 0.46), stockColor, stockMaterial, CFrame.new(0, 0.17, bodyLength / 2 + 0.38) * CFrame.Angles(0, math.rad(180), 0))
	end

	local ejectionPort = addPiece(
		target,
		"Part",
		"EjectionPort",
		Vector3.new(0.02, 0.08, 0.16),
		Color3.fromRGB(20, 20, 22),
		Enum.Material.SmoothPlastic,
		CFrame.new(0.13, if isPistol then slideTopY - 0.1 else 0.06, if isPistol then 0.08 else 0.3)
	)

	buildArm(target, 1, gripOffset * CFrame.new(0.02, -0.04, 0.08), 42)
	local supportOffset = if isPistol
		then gripOffset * CFrame.new(-0.16, -0.02, 0.02) * CFrame.Angles(0, math.rad(10), 0)
		else CFrame.new(-0.04, -0.26, -(bodyLength / 2 + barrelLength * 0.3)) * CFrame.Angles(math.rad(6), 0, 0)
	buildArm(target, -1, if isShotgun then target.pumpRest * CFrame.new(-0.02, -0.1, 0) else supportOffset, 54)

	local barrelPart = model:FindFirstChild("Barrel") :: BasePart
	target.muzzle.Name = "Muzzle"
	target.muzzle.Position = Vector3.new(0, 0, -barrelLength / 2)
	target.muzzle.Parent = barrelPart
	target.eject.Name = "Eject"
	target.eject.Position = Vector3.new(0.1, 0.05, 0)
	target.eject.Parent = ejectionPort

	model.Parent = camera
	rig = target
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
	recoilRoll = math.clamp(recoilRoll + (math.random() - 0.5) * config.recoilSnap * 0.03, -0.06, 0.06)
	if config.class == "Shotgun" then
		pumpT = -0.4
	else
		slideT = 0
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
	for _, piece in current.pieces do
		piece.part.LocalTransparencyModifier = if visible then 0 else 1
	end
end

local function animatedOffsets(current: Rig, deltaTime: number): (CFrame?, CFrame?, CFrame?)
	local slideOffset: CFrame? = nil
	local pumpOffset: CFrame? = nil
	local magazineOffset: CFrame? = nil

	if slideT < 1 then
		slideT = math.min(slideT + deltaTime / 0.16, 1)
		slideOffset = current.slideRest * CFrame.new(0, 0, math.sin(slideT * math.pi) * current.slideTravel)
	end
	if pumpT < 1 then
		pumpT = math.min(pumpT + deltaTime / 0.42, 1)
		if pumpT > 0 then
			pumpOffset = current.pumpRest * CFrame.new(0, 0, math.sin(pumpT * math.pi) * current.pumpTravel)
		end
	end

	if reloadT < 1 then
		local drop = 0
		if reloadT >= 0.16 and reloadT < 0.42 then
			drop = easeOutCubic((reloadT - 0.16) / 0.26)
		elseif reloadT >= 0.42 and reloadT < 0.68 then
			drop = 1 - easeOutCubic((reloadT - 0.42) / 0.26)
		end
		if drop > 0 then
			magazineOffset = current.magazineRest * CFrame.new(0, -drop * 1.1, drop * 0.15) * CFrame.Angles(math.rad(drop * 14), 0, 0)
		end
		if reloadT >= 0.74 then
			local rack = math.sin(math.clamp((reloadT - 0.74) / 0.22, 0, 1) * math.pi)
			slideOffset = current.slideRest * CFrame.new(0, 0, rack * current.slideTravel)
			pumpOffset = current.pumpRest * CFrame.new(0, 0, rack * current.pumpTravel)
		end
	end

	return slideOffset, pumpOffset, magazineOffset
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

	breathClock += deltaTime
	local cameraCFrame = camera.CFrame
	local previousCFrame = lastCameraCFrame or cameraCFrame
	lastCameraCFrame = cameraCFrame
	local deltaPitch, deltaYaw, _ = cameraCFrame:ToObjectSpace(previousCFrame):ToEulerAnglesYXZ()

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

	local reloadOffset = CFrame.identity
	if reloadT < 1 then
		reloadT = math.min(reloadT + deltaTime / reloadDuration, 1)
		local tilt = pulse(reloadT, 0.18)
		reloadOffset = CFrame.Angles(math.rad(-14 * tilt), math.rad(8 * tilt), math.rad(-22 * tilt))
			* CFrame.new(0.05 * tilt, -0.25 * tilt, 0.08 * tilt)
	end

	local slideOffset, pumpOffset, magazineOffset = animatedOffsets(current, deltaTime)

	local running = ExertionState.isRunning()
	sprintBlend += ((if running then 1 else 0) - sprintBlend) * math.clamp(deltaTime * 5, 0, 1)

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

	local rootCFrame = cameraCFrame
		* BASE_OFFSET
		* CFrame.new(bobX - swayYaw * 1.5, bobY + breatheY + swayPitch * 1.1 - equipDrop, recoilOffset)
		* CFrame.Angles(
			recoilPitch + swayPitch * 0.55 - equipTilt,
			swayYaw * 0.75,
			swayYaw * 0.28 + recoilRoll + breatheRoll
		)
		* sprintOffset
		* reloadOffset

	for _, piece in current.pieces do
		local offset = piece.offset
		if slideOffset and piece.part == current.slide then
			offset = slideOffset
		elseif pumpOffset and piece.part == current.pump then
			offset = pumpOffset
		elseif magazineOffset and piece.part == current.magazine then
			offset = magazineOffset
		end
		piece.part.CFrame = rootCFrame * offset
	end
end

function Viewmodel.init()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local weaponId = player:GetAttribute("WeaponId")
		if typeof(weaponId) == "string" then
			Viewmodel.setWeapon(weaponId)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Viewmodel
