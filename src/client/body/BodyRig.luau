--!strict

-- One third-person body: the aim on the waist and neck, the weapon frame with its
-- recoil, sprint, draw and reload gestures, and the two hand IK chains that follow it.
-- The weapon leads and the hands follow: nothing here poses an arm joint directly.
-- Written in PreSimulation on top of whatever the Animator left in the joints (see
-- docs/animation/third-person-body.md section 3.1). The chest, the head and the gun are
-- aimed from the root's upright frame, worked out down the joint chain for this frame's
-- pose, so the run clip's forward lean does not tip the gun at the ground. Fed by
-- BodyController for real players and by SandboxBodyGallery for the yard mannequins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThirdPersonConfig = require(ReplicatedStorage.Shared.config.ThirdPersonConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local StanceConfig = require(ReplicatedStorage.Shared.config.StanceConfig)
local StanceMath = require(ReplicatedStorage.Shared.util.StanceMath)

local BodyRig = {}
BodyRig.__index = BodyRig

-- how close a read-back Transform must be to the last write to count as untouched
local WRITE_EPSILON = 1e-4

-- a joint the layer multiplies: what it wrote last and the animator pose under it, so a
-- frame where the animator did not rewrite the joint (no track playing, or throttled)
-- starts from the same base instead of stacking the twist
type Joint = {
	motor: Motor6D,
	written: CFrame,
	base: CFrame,
}

-- an arm's three joints, read each update for the reach (an avatar rescale moves them)
type Arm = {
	shoulder: Motor6D,
	elbow: Motor6D,
	wrist: Motor6D,
}

type Sockets = {
	grip: CFrame,
	support: CFrame,
	magazine: CFrame,
	charge: CFrame?,
	port: CFrame?,
	pump: CFrame?,
}

type Fields = {
	character: Model,
	humanoid: Humanoid,
	animator: Animator?,
	rootPart: BasePart,
	rootMotor: Motor6D,
	upperTorso: BasePart,
	waist: Joint?,
	neck: Joint?,
	rightControl: IKControl,
	leftControl: IKControl,
	rightTarget: Attachment,
	leftTarget: Attachment,
	rightArm: Arm?,
	leftArm: Arm?,
	weapon: Model?,
	class: ThirdPersonConfig.ClassSpec?,
	config: WeaponsConfig.WeaponConfig?,
	sockets: Sockets?,
	aimPitch: number,
	aimYaw: number,
	targetPitch: number,
	targetYaw: number,
	-- the manual lean (Stances), -1 left to 1 right: shown and wanted
	lean: number,
	targetLean: number,
	smoothing: number,
	speed: number,
	sprinting: boolean,
	sprintBlend: number,
	kick: BodyMath.SpringState,
	snap: BodyMath.SpringState,
	stiffness: number,
	damping: number,
	timeline: BodyMath.Timeline?,
	timelineKind: string,
	elapsed: number,
	sample: BodyMath.PoseSample,
	seatSocket: string,
	weight: number,
	ikAllowed: boolean,
	alive: boolean,
	spread: BodyMath.AimSpread,
}

export type BodyRig = typeof(setmetatable({} :: Fields, BodyRig))

local AIM = ThirdPersonConfig.AIM
local IK = ThirdPersonConfig.IK
local SPRINT = ThirdPersonConfig.SPRINT
local RECOIL = ThirdPersonConfig.RECOIL
local GESTURES = ThirdPersonConfig.GESTURES

local SHARES: BodyMath.AimShares = {
	waistPitch = AIM.waistPitch,
	waistYaw = AIM.waistYaw,
	pitchClamp = AIM.pitchClamp,
	yawClamp = AIM.yawClamp,
}

local PIVOT = CFrame.new(AIM.pivot)
local IDENTITY = CFrame.new()
local PIVOT_BACK = CFrame.new(-AIM.pivot)

local function findMotor(part: Instance?, name: string): Joint?
	if not part then
		return nil
	end
	local motor = part:FindFirstChild(name)
	if not motor or not motor:IsA("Motor6D") then
		return nil
	end
	return { motor = motor, written = motor.Transform, base = motor.Transform }
end

local function findArm(character: Model, side: string): Arm?
	local upper = character:FindFirstChild(side .. "UpperArm")
	local lower = character:FindFirstChild(side .. "LowerArm")
	local hand = character:FindFirstChild(side .. "Hand")
	local shoulder = if upper then upper:FindFirstChild(side .. "Shoulder") else nil
	local elbow = if lower then lower:FindFirstChild(side .. "Elbow") else nil
	local wrist = if hand then hand:FindFirstChild(side .. "Wrist") else nil
	if shoulder and shoulder:IsA("Motor6D") and elbow and elbow:IsA("Motor6D") and wrist and wrist:IsA("Motor6D") then
		return { shoulder = shoulder, elbow = elbow, wrist = wrist }
	end
	return nil
end

-- The shoulder joint in torso space and how far the hand's centre gets from it with the
-- arm straight.
local function armReach(arm: Arm): (Vector3, number)
	local upper = (arm.elbow.C0.Position - arm.shoulder.C1.Position).Magnitude
	local lower = (arm.wrist.C0.Position - arm.elbow.C1.Position).Magnitude
	return arm.shoulder.C0.Position, upper + lower + arm.wrist.C1.Position.Magnitude
end

-- The smallest slide along `back` (a unit vector) that brings `point` within `reach` of
-- `origin`, at most `limit`: 0 when the point is already in reach, or when sliding back
-- does not bring it closer.
local function slideIntoReach(point: Vector3, origin: Vector3, reach: number, back: Vector3, limit: number): number
	local offset = point - origin
	local excess = offset:Dot(offset) - reach * reach
	if excess <= 0 or limit <= 0 then
		return 0
	end
	local along = offset:Dot(back)
	local discriminant = along * along - excess
	local slide = if discriminant >= 0 then -along - math.sqrt(discriminant) else -along
	return math.clamp(slide, 0, limit)
end

local function makeTarget(name: string, parent: Instance): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = parent
	return attachment
end

local function makeControl(name: string, humanoid: Humanoid, chainRoot: Instance, endEffector: Instance, target: Attachment, priority: number): IKControl
	local control = Instance.new("IKControl")
	control.Name = name
	control.Type = Enum.IKControlType.Transform
	control.ChainRoot = chainRoot
	control.EndEffector = endEffector
	control.Target = target
	control.SmoothTime = IK.smoothTime
	control.Priority = priority
	control.Weight = 0
	control.Enabled = false
	control.Parent = humanoid
	return control
end

-- Binds an R15 character, or returns nil when it is not one or its arms are missing.
function BodyRig.new(character: Model): BodyRig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local rootMotor = if lowerTorso then lowerTorso:FindFirstChild("Root") else nil
	if not rootPart or not rootPart:IsA("BasePart") or not rootMotor or not rootMotor:IsA("Motor6D") then
		return nil
	end
	local upperTorso = character:FindFirstChild("UpperTorso")
	local rightUpperArm = character:FindFirstChild("RightUpperArm")
	local rightHand = character:FindFirstChild("RightHand")
	local leftUpperArm = character:FindFirstChild("LeftUpperArm")
	local leftHand = character:FindFirstChild("LeftHand")
	if not upperTorso or not upperTorso:IsA("BasePart") or not rightUpperArm or not rightHand or not leftUpperArm or not leftHand then
		return nil
	end

	local rightTarget = makeTarget("BodyGripTarget", upperTorso)
	local leftTarget = makeTarget("BodySupportTarget", upperTorso)
	local self: Fields = {
		character = character,
		humanoid = humanoid,
		animator = humanoid:FindFirstChildOfClass("Animator"),
		rootPart = rootPart,
		rootMotor = rootMotor,
		upperTorso = upperTorso,
		waist = findMotor(upperTorso, "Waist"),
		neck = findMotor(character:FindFirstChild("Head"), "Neck"),
		rightControl = makeControl("BodyRightArmIk", humanoid, rightUpperArm, rightHand, rightTarget, 0),
		leftControl = makeControl("BodyLeftArmIk", humanoid, leftUpperArm, leftHand, leftTarget, 1),
		rightTarget = rightTarget,
		leftTarget = leftTarget,
		rightArm = findArm(character, "Right"),
		leftArm = findArm(character, "Left"),
		weapon = nil,
		class = nil,
		config = nil,
		sockets = nil,
		aimPitch = 0,
		aimYaw = 0,
		targetPitch = 0,
		targetYaw = 0,
		lean = 0,
		targetLean = 0,
		smoothing = AIM.smoothing,
		speed = 0,
		sprinting = false,
		sprintBlend = 0,
		kick = { value = 0, velocity = 0 },
		snap = { value = 0, velocity = 0 },
		stiffness = 200,
		damping = 25,
		timeline = nil,
		timelineKind = "",
		elapsed = 0,
		sample = { from = "grip", to = "grip", alpha = 1 },
		seatSocket = "magazine",
		weight = 0,
		ikAllowed = true,
		alive = true,
		spread = { pitch = 0, yaw = 0, waistPitch = 0, waistYaw = 0, gunPitch = 0 },
	}
	return setmetatable(self, BodyRig)
end

local function socketFrame(grip: BasePart, name: string): CFrame?
	local attachment = grip:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment.CFrame
	end
	return nil
end

-- Reads the weapon's class and sockets; nil clears the weapon (the hands go back to
-- the animator).
function BodyRig.setWeapon(self: BodyRig, weapon: Model?, config: WeaponsConfig.WeaponConfig?)
	self.weapon = weapon
	self.config = config
	self.class = nil
	self.sockets = nil
	self.timeline = nil
	self.timelineKind = ""
	if not weapon or not config then
		return
	end
	local grip = weapon:FindFirstChild("Grip")
	local spec = ThirdPersonConfig.getClass(config.class)
	if not grip or not grip:IsA("BasePart") or not spec then
		return
	end
	local gripSocket = socketFrame(grip, "GripSocket")
	local support = socketFrame(grip, "SupportSocket")
	local magazine = socketFrame(grip, "MagazineSocket")
	if not gripSocket or not support or not magazine then
		return
	end
	self.class = spec
	self.sockets = {
		grip = gripSocket,
		support = support,
		magazine = magazine,
		charge = socketFrame(grip, "ChargeSocket"),
		port = socketFrame(grip, "PortSocket"),
		pump = socketFrame(grip, "PumpSocket"),
	}
	self.seatSocket = if config.reloadStyle == "shell" then "port" else "magazine"
	self.stiffness = config.recoilStiffness
	self.damping = config.recoilDamping
end

function BodyRig.setAim(self: BodyRig, pitch: number, yaw: number)
	self.targetPitch = pitch
	self.targetYaw = yaw
end

-- The manual lean, -1 (left) to 1 (right): the upper torso rolls toward it at the waist.
function BodyRig.setLean(self: BodyRig, lean: number)
	self.targetLean = math.clamp(lean, -1, 1)
end

function BodyRig.setSmoothing(self: BodyRig, timeConstant: number)
	self.smoothing = timeConstant
end

function BodyRig.setSpeed(self: BodyRig, speed: number)
	self.speed = speed
end

function BodyRig.setIkAllowed(self: BodyRig, allowed: boolean)
	self.ikAllowed = allowed
end

local function startTimeline(self: BodyRig, kind: string, timeline: BodyMath.Timeline)
	self.timeline = timeline
	self.timelineKind = kind
	self.elapsed = 0
end

-- A shot: the kick and snap springs, and the pump stroke on a gun that does not eject
-- on fire.
function BodyRig.fire(self: BodyRig)
	local class = self.class
	local config = self.config
	if not class or not config then
		return
	end
	BodyMath.springImpulse(self.kick, BodyMath.impulseForPeak(config.recoilKick * class.kickFactor, self.stiffness))
	BodyMath.springImpulse(self.snap, BodyMath.impulseForPeak(config.recoilSnap * class.snapFactor * RECOIL.snapDegrees, self.stiffness))
	if not config.ejectOnFire and class.pumpTime > 0 and self.timelineKind ~= "reload" then
		startTimeline(self, "pump", BodyMath.pumpTimeline(class.pumpTime, GESTURES.pumpDelay))
	end
end

-- A reload on the weapon's own timeline: `shells` for the pump shotgun (how many go
-- in), `empty` adds the chambering action, `scale` is the player's ReloadScale.
function BodyRig.startReload(self: BodyRig, empty: boolean, shells: number, scale: number)
	local class = self.class
	local config = self.config
	if not class or not config then
		return
	end
	if config.reloadStyle == "shell" and config.shellReload then
		startTimeline(self, "reload", BodyMath.shellTimeline(config.shellReload, shells, empty, scale))
		return
	end
	local ammoAdd, total = WeaponsConfig.magazineReload(config, empty, scale)
	local chargeTime = if empty then class.chargeTime * scale else 0
	startTimeline(self, "reload", BodyMath.magazineTimeline(ammoAdd, total, empty, chargeTime))
end

-- The reload ended or was cancelled: the support hand returns to the gun.
function BodyRig.endReload(self: BodyRig)
	if self.timelineKind ~= "reload" then
		return
	end
	local sample = self.sample
	local from = if sample.alpha < 0.5 then sample.from else sample.to
	startTimeline(self, "cancel", { { t = 0, pose = from }, { t = GESTURES.cancelReturn, pose = "grip" } })
end

-- The draw after an equip.
function BodyRig.equip(self: BodyRig)
	local config = self.config
	if not config then
		return
	end
	startTimeline(self, "equip", BodyMath.equipTimeline(config.drawTime))
end

-- The support hand's frame in grip space for a gesture pose; the belt is in torso
-- space, so it is returned with `inTorso` true.
local function poseFrame(self: BodyRig, sockets: Sockets, class: ThirdPersonConfig.ClassSpec, pose: string): (CFrame, boolean)
	if pose == "belt" then
		return GESTURES.belt, true
	elseif pose == "well" then
		return sockets.magazine, false
	elseif pose == "port" then
		return sockets.port or sockets.magazine, false
	elseif pose == "seat" then
		return (if self.seatSocket == "port" then sockets.port else nil) or sockets.magazine, false
	elseif pose == "charge" then
		return sockets.charge or sockets.support, false
	elseif pose == "chargePulled" then
		local charge = sockets.charge
		if charge and class.chargeStyle == "bolt" then
			return charge * CFrame.new(0, 0, class.chargePull), false
		end
		return sockets.support, false
	elseif pose == "pump" then
		return sockets.pump or sockets.support, false
	elseif pose == "pumpBack" then
		local pump = sockets.pump or sockets.support
		return pump * CFrame.new(0, 0, class.pumpTravel), false
	end
	return sockets.support, false
end

local function supportTarget(self: BodyRig, weaponFrame: CFrame, sockets: Sockets, class: ThirdPersonConfig.ClassSpec): CFrame
	local sample = self.sample
	local fromFrame, fromTorso = poseFrame(self, sockets, class, sample.from)
	local toFrame, toTorso = poseFrame(self, sockets, class, sample.to)
	local from = if fromTorso then fromFrame else weaponFrame * fromFrame
	local to = if toTorso then toFrame else weaponFrame * toFrame
	if sample.alpha >= 1 then
		return to
	elseif sample.alpha <= 0 then
		return from
	end
	return from:Lerp(to, sample.alpha)
end

-- The animator's pose under the layer this frame (see the Joint type): a Transform that
-- still reads back as the last write was not touched by the animator, so the base under
-- that write is used again instead of stacking on it.
local function baseOf(joint: Joint): CFrame
	local current = joint.motor.Transform
	-- Transform does not read back bit-exact (Studio, 2026-09-30), so an exact compare
	-- took every frame for an animator write and stacked the twist
	return if current:FuzzyEq(joint.written, WRITE_EPSILON) then joint.base else current
end

local function setJoint(joint: Joint, base: CFrame, twist: CFrame)
	local written = base * twist
	joint.motor.Transform = written
	joint.base = base
	joint.written = written
end

-- The rotation a joint's Transform has to add on top of `joint` (the joint frame under
-- the animator's pose, in world space) so Part1 ends on the world rotation `wanted`.
local function twistFor(joint: CFrame, motor: Motor6D, wanted: CFrame): CFrame
	return joint.Rotation:Inverse() * wanted * motor.C1.Rotation
end

-- Part1's rotation relative to Part0 when the joint's Transform is identity.
local function restOf(motor: Motor6D): CFrame
	return (motor.C0 * motor.C1:Inverse()).Rotation
end

local function stepTimeline(self: BodyRig, deltaTime: number)
	local timeline = self.timeline
	if not timeline then
		return
	end
	self.elapsed += deltaTime
	BodyMath.poseAt(timeline, self.elapsed, self.sample)
	if self.elapsed >= BodyMath.timelineDuration(timeline) then
		self.timeline = nil
		self.timelineKind = ""
	end
end

-- The draw's blend from the lowered pose (1 at the start of the draw, 0 once up) and
-- its IK weight.
local function equipBlend(self: BodyRig): number
	if self.timelineKind ~= "equip" then
		return 0
	end
	local sample = self.sample
	if sample.to == "lowered" then
		return 1
	end
	return if sample.from == "lowered" then 1 - sample.alpha else 0
end

-- One update, `deltaTime` seconds since the last one for this rig.
function BodyRig.update(self: BodyRig, deltaTime: number)
	local humanoid = self.humanoid
	self.alive = humanoid.Parent ~= nil and humanoid.Health > 0

	self.aimPitch = BodyMath.approachAngle(self.aimPitch, self.targetPitch, deltaTime, self.smoothing)
	self.aimYaw = BodyMath.approachAngle(self.aimYaw, self.targetYaw, deltaTime, self.smoothing)
	self.lean = BodyMath.approach(self.lean, if self.alive then self.targetLean else 0, deltaTime, self.smoothing)
	self.sprinting = BodyMath.sprintTarget(self.speed, SPRINT.speed, SPRINT.hysteresis, self.sprinting)
	self.sprintBlend = BodyMath.approach(self.sprintBlend, if self.sprinting then 1 else 0, deltaTime, SPRINT.blendTime)
	BodyMath.springStep(self.kick, self.stiffness, self.damping, deltaTime)
	BodyMath.springStep(self.snap, self.stiffness, self.damping, deltaTime)
	stepTimeline(self, deltaTime)

	local class = self.class
	local sockets = self.sockets
	local holding = class ~= nil and sockets ~= nil and self.alive
	local armScale = 1 - self.sprintBlend * (1 - SPRINT.armPitchScale)
	local spread = BodyMath.spreadAim(if self.alive then self.aimPitch else 0, if self.alive then self.aimYaw else 0, SHARES, armScale)
	self.spread = spread

	-- the hands' IK weight first: the chest straightens only as far as they hold the gun
	local equipping = equipBlend(self)
	local targetWeight = if holding and self.ikAllowed then 1 - equipping * (1 - IK.equipWeight) else 0
	local fade = if not self.alive then IK.deathFade elseif targetWeight > self.weight then IK.fadeIn else IK.fadeOut
	self.weight = BodyMath.approach(self.weight, targetWeight, deltaTime, fade)
	if self.weight < 1e-3 then
		self.weight = 0
	end

	-- this frame's pose in world space, from the root up the joint chain; `upright` is
	-- the root's rotation, what the torso and the head face with the clip's lean taken out
	local rootMotor = self.rootMotor
	local rootCFrame = self.rootPart.CFrame
	local lower = rootCFrame * rootMotor.C0 * rootMotor.Transform * rootMotor.C1:Inverse()
	local upright = rootCFrame.Rotation * restOf(rootMotor)
	local upper = self.upperTorso.CFrame
	local chestRest = upright

	local waist = self.waist
	if waist then
		local motor = waist.motor
		local base = baseOf(waist)
		local joint = lower * motor.C0 * base
		upper = joint * motor.C1:Inverse()
		chestRest = upright * restOf(motor)
		if self.alive then
			-- the aim's waist share (plus the recoil's) over the upright chest, keeping only
			-- part of the clip's lean while a gun is held
			local waistPitch = spread.waistPitch + self.snap.value * RECOIL.waistShare
			local lean = chestRest:Inverse() * upper.Rotation
			local keep = 1 - AIM.chestStabilize * self.weight
			local roll = StanceMath.bodyRoll(StanceConfig :: any, self.lean)
			local wanted = chestRest * CFrame.fromEulerAnglesYXZ(math.rad(waistPitch), math.rad(spread.waistYaw), math.rad(roll)) * IDENTITY:Lerp(lean, keep)
			local twist = twistFor(joint, motor, wanted)
			setJoint(waist, base, twist)
			upper = joint * twist * motor.C1:Inverse()
		end
	end

	local neck = self.neck
	if neck and self.alive then
		-- the head ends on the whole aim with a little of the clip's motion left in
		local motor = neck.motor
		local base = baseOf(neck)
		local joint = upper * motor.C0 * base
		local headRest = chestRest * restOf(motor)
		local lean = headRest:Inverse() * (joint * motor.C1:Inverse()).Rotation
		local wanted = headRest * CFrame.fromEulerAnglesYXZ(math.rad(spread.pitch), math.rad(spread.yaw), 0) * IDENTITY:Lerp(lean, 1 - AIM.headStabilize)
		setJoint(neck, base, twistFor(joint, motor, wanted))
	end

	local enabled = self.weight > 0
	if self.rightControl.Enabled ~= enabled then
		self.rightControl.Enabled = enabled
		self.leftControl.Enabled = enabled
	end
	self.rightControl.Weight = self.weight
	self.leftControl.Weight = self.weight
	if not enabled or not class or not sockets then
		return
	end

	-- the weapon frame: the hold, lowered for the draw and the sprint, placed from the
	-- point between the shoulders along the aim over the upright chest, then kicked by the
	-- recoil; kept in torso space, where the two hand targets live
	local hold = class.hold
	if equipping > 0 then
		hold = hold:Lerp(hold * class.lowered, equipping)
	end
	if self.sprintBlend > 0 then
		hold = hold:Lerp(hold * class.sprint, self.sprintBlend)
	end
	local shoulders = (upper * PIVOT).Position
	local aim = chestRest * CFrame.fromEulerAnglesYXZ(math.rad(spread.gunPitch), math.rad(spread.yaw), 0)
	local weaponFrame = upper:Inverse() * (CFrame.new(shoulders) * aim * PIVOT_BACK * hold)
	if self.kick.value ~= 0 or self.snap.value ~= 0 then
		weaponFrame = weaponFrame * CFrame.new(0, 0, self.kick.value) * CFrame.Angles(math.rad(self.snap.value), 0, 0)
	end
	if class.chargeStyle == "slide" and self.timelineKind == "reload" then
		local sample = self.sample
		local pull = 0
		if sample.to == "chargePulled" then
			pull = sample.alpha
		elseif sample.from == "chargePulled" then
			pull = 1 - sample.alpha
		end
		if pull > 0 then
			weaponFrame = weaponFrame * CFrame.new(0, 0, class.chargePull * pull)
		end
	end

	-- Both hands inside the arms' reach, whatever the avatar's proportions: a grip past
	-- the right arm's reach brings the whole gun back along its axis, and a support socket
	-- past the left arm's slides back along the gun (no closer than a hand's width to the
	-- right hand), so the left hand lands on the receiver instead of stopping short of the
	-- handguard in the air.
	local back = weaponFrame.ZVector
	local rightArm = self.rightArm
	if rightArm then
		local shoulder, reach = armReach(rightArm)
		local slide = slideIntoReach((weaponFrame * sockets.grip).Position, shoulder, reach * IK.reachMargin, back, IK.maxGunSlide)
		if slide > 0 then
			weaponFrame = weaponFrame + back * slide
		end
	end
	local grip = weaponFrame * sockets.grip
	local support = supportTarget(self, weaponFrame, sockets, class)
	local leftArm = self.leftArm
	if leftArm then
		local shoulder, reach = armReach(leftArm)
		local limit = -(support.Position - grip.Position):Dot(back) - IK.handGap
		local slide = slideIntoReach(support.Position, shoulder, reach * IK.reachMargin, back, limit)
		if slide > 0 then
			support = support + back * slide
		end
	end
	self.rightTarget.CFrame = grip
	self.leftTarget.CFrame = support
end

-- Whether the rig can still be used (the character is in the world).
function BodyRig.isValid(self: BodyRig): boolean
	return self.character.Parent ~= nil and self.upperTorso.Parent ~= nil
end

function BodyRig.destroy(self: BodyRig)
	self.rightControl:Destroy()
	self.leftControl:Destroy()
	self.rightTarget:Destroy()
	self.leftTarget:Destroy()
	for _, joint in { self.waist, self.neck } do
		if joint and joint.motor.Parent and joint.motor.Transform:FuzzyEq(joint.written, WRITE_EPSILON) then
			joint.motor.Transform = joint.base
		end
	end
end

-- For the yard label: the live gesture and IK state.
function BodyRig.describe(self: BodyRig): string
	local timeline = self.timeline
	local gesture = if timeline then string.format("%s %s>%s %.2fs", self.timelineKind, self.sample.from, self.sample.to, self.elapsed) else "-"
	return string.format("ik %.2f  pitch %.0f  yaw %.0f  %s", self.weight, self.aimPitch, self.aimYaw, gesture)
end

-- The animator reused its last pose this frame, so a multiplied twist would stack.
function BodyRig.isThrottled(self: BodyRig): boolean
	local animator = self.animator
	return animator ~= nil and animator.EvaluationThrottled
end

return BodyRig
