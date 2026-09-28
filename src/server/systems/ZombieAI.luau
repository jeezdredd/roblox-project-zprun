--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local ZombiesConfig = require(ReplicatedStorage.Shared.config.ZombiesConfig)
local ZombieBehaviourConfig = require(ReplicatedStorage.Shared.config.ZombieBehaviourConfig)
local ZombieRig = require(ReplicatedStorage.Shared.util.ZombieRig)
local ZombieSpawnConfig = require(ReplicatedStorage.Shared.config.ZombieSpawnConfig)
local RoutePlan = require(script.Parent.RoutePlan)
local ModifiersConfig = require(ReplicatedStorage.Shared.config.ModifiersConfig)
local ZombieFactory = require(script.Parent.ZombieFactory)
local ZombieAnimator = require(script.Parent.ZombieAnimator)
local DistanceTracker = require(script.Parent.DistanceTracker)
local MissionConfig = require(script.Parent.MissionConfig)
local MissionState = require(script.Parent.MissionState)

local ZombieAI = {}

type ZombieState = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	config: ZombiesConfig.ZombieConfig,
	lastHitAt: { [Player]: number },
	neck: Motor6D?,
	neckBaseC0: CFrame,
	tracks: ZombieAnimator.ZombieTracks?,
	mode: string,
	strideOffset: number,
	facesPlayer: boolean,
	locked: boolean,
	wakeAt: number?,
	wakeDistance: number,
	speed: number,
	heading: Vector3,
	desiredHeading: Vector3,
	turnRate: number,
	moveActive: boolean,
	faceOnly: boolean,
	targetPoint: Vector3?,
	nextFacingAt: number,
	alertAt: number?,
}

local MAX_POOLED = 24
local MAX_ALIVE = 60

local HYSTERESIS = 1.25
local AI_FULL_RANGE = 180
local AI_FAR_STRIDE = 4

local LURE_RANGE = 80
local GRAB_DAMAGE_SCALE = 3

local random = Random.new()
local zombies: { [Model]: ZombieState } = {}
local zombiesFolder: Folder? = nil
local pools: { [string]: { Model } } = {}
local aliveCount = 0
local nextSpawnAt = 0
local sectionCap = 0
local totalWeight = 0
local tickAccumulator = 0
local tickIndex = 0
local strideCounter = 0
local corpseLure: { pos: Vector3, expires: number }? = nil
local lastAggroState = false
local propsFolder: Folder? = nil
local corpses: { Model } = {}

for _, config in ZombiesConfig do
	totalWeight += config.weight
	pools[config.id] = {}
end

local function getFolder(): Folder
	local existing = zombiesFolder
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Zombies"
	folder.Parent = Workspace
	zombiesFolder = folder
	return folder
end

local function getPropsFolder(): Folder
	local existing = propsFolder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ZombieProps"
	folder.Parent = Workspace
	propsFolder = folder
	return folder
end

local function pickConfigFrom(allowed: { string }?): ZombiesConfig.ZombieConfig
	if allowed and #allowed > 0 then
		local candidates: { ZombiesConfig.ZombieConfig } = {}
		local weight = 0
		for _, config in ZombiesConfig do
			if table.find(allowed, config.id) then
				table.insert(candidates, config)
				weight += config.weight
			end
		end
		if #candidates > 0 then
			local roll = random:NextNumber() * weight
			for _, config in candidates do
				roll -= config.weight
				if roll <= 0 then
					return config
				end
			end
			return candidates[#candidates]
		end
	end
	return ZombiesConfig[1]
end

local function pickConfig(): ZombiesConfig.ZombieConfig
	local roll = random:NextNumber() * totalWeight
	for _, config in ZombiesConfig do
		roll -= config.weight
		if roll <= 0 then
			return config
		end
	end
	return ZombiesConfig[#ZombiesConfig]
end

local GLANCE_MIN = 0.35
local rightAxis = GameConstants.RUN_DIRECTION:Cross(Vector3.yAxis)

local function onTouched(state: ZombieState, hit: BasePart)
	local character = hit.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	if state.humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local lastHit = state.lastHitAt[player]
	if lastHit and now - lastHit < state.config.damageCooldown then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local offset = character:GetPivot().Position - state.root.Position
	local lateral = math.abs(offset:Dot(rightAxis))
	local config = state.config

	if lateral > config.collisionGlanceDistance then
		return
	end
	if lateral > config.collisionDeathDistance and offset:Dot(GameConstants.RUN_DIRECTION) < -2 then
		return
	end

	state.lastHitAt[player] = now

	if lateral <= config.collisionDeathDistance then
		local difficulty = MissionConfig.getDifficulty()
		if difficulty.grabLethal then
			player:SetAttribute("DeathCause", "Grabbed")
			humanoid:TakeDamage(humanoid.Health)
		else
			humanoid:TakeDamage(config.touchDamage * GRAB_DAMAGE_SCALE * difficulty.damageMultiplier)
		end
		return
	end

	local band = config.collisionGlanceDistance - config.collisionDeathDistance
	local centrality = if band > 0 then 1 - (lateral - config.collisionDeathDistance) / band else 1
	local glanceScale = config.glancePower / ZombieBehaviourConfig.GLANCE_POWER_REFERENCE
	local power = math.clamp(GLANCE_MIN + (1 - GLANCE_MIN) * centrality * glanceScale, 0, 1)
	local side = if offset:Dot(rightAxis) >= 0 then 1 else -1

	DistanceTracker.applySlow(player, 1 - 0.45 * power, 0.35 + 0.45 * power)
	Remotes.getEvent(Remotes.Event.PlayerGlanced):FireClient(player, side, power)
end

local function onDied(state: ZombieState)
	state.mode = "Down"
	local model = state.model
	task.delay(GameConstants.ZOMBIE_CORPSE_LIFETIME, function()
		if zombies[model] == state then
			ZombieAI.recycle(state)
		end
	end)
end

local function buildModel(config: ZombiesConfig.ZombieConfig): Model
	local model = ZombieFactory.build(config)
	local hitbox = model:FindFirstChild("Hitbox")
	if hitbox and hitbox:IsA("BasePart") then
		hitbox.Touched:Connect(function(hit)
			local state = zombies[model]
			if state and not state.locked then
				onTouched(state, hit)
			end
		end)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			local state = zombies[model]
			if state then
				onDied(state)
			end
		end)
	end
	return model
end

local function acquireModel(config: ZombiesConfig.ZombieConfig): Model
	local pool = pools[config.id]
	if pool then
		local pooled = table.remove(pool)
		if pooled then
			return pooled
		end
	end
	return buildModel(config)
end

local function groundedY(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getFolder() }
	local hit = Workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	if hit then
		return hit.Position.Y + ZombieFactory.ROOT_HEIGHT
	end
	return position.Y
end

local function setTorsoCollision(model: Model, enabled: boolean)
	for _, name in { ZombieRig.LOWER_TORSO_NAME, ZombieRig.TORSO_NAME } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.CanCollide = enabled
		end
	end
end

local function spawnCorpse(position: Vector3): Model
	local model = ZombieFactory.build(pickConfig())
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == "Hitbox" or descendant.Name == "Eye" then
				descendant:Destroy()
			else
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.Color = descendant.Color:Lerp(Color3.fromRGB(40, 24, 22), 0.45)
			end
		end
	end
	local groundY = groundedY(position) - ZombieFactory.ROOT_HEIGHT
	local yaw = random:NextNumber() * 2 * math.pi
	model:PivotTo(CFrame.new(position.X, groundY + 0.75, position.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.pi / 2, 0, 0))
	local stain = Instance.new("Part")
	stain.Name = "Stain"
	stain.Size = Vector3.new(7, 0.05, 7)
	stain.CFrame = CFrame.new(position.X, groundY + 0.06, position.Z) * CFrame.Angles(0, yaw, 0)
	stain.Color = Color3.fromRGB(70, 18, 16)
	stain.Material = Enum.Material.SmoothPlastic
	stain.Transparency = 0.25
	stain.Anchored = true
	stain.CanCollide = false
	stain.CanQuery = false
	stain.CastShadow = false
	stain.Parent = model
	model.Name = "Corpse"
	model.Parent = getPropsFolder()
	table.insert(corpses, model)
	return model
end

local function spawnZombie(position: Vector3, config: ZombiesConfig.ZombieConfig, startAlert: boolean?, posture: string?, faceAt: Vector3?, wakeDistance: number?)
	if aliveCount >= MAX_ALIVE then
		return
	end
	local model = acquireModel(config)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart

	humanoid.Health = humanoid.MaxHealth
	local grounded = Vector3.new(position.X, groundedY(position), position.Z)
	local pivot = if faceAt
		then CFrame.lookAt(grounded, Vector3.new(faceAt.X, grounded.Y, faceAt.Z))
		else CFrame.new(grounded) * CFrame.Angles(0, random:NextNumber() * 2 * math.pi, 0)
	model:PivotTo(pivot)
	model.Parent = getFolder()
	root:SetNetworkOwner(nil)

	local neck = ZombieRig.neck(model)

	local state: ZombieState = {
		model = model,
		humanoid = humanoid,
		root = root,
		config = config,
		lastHitAt = {},
		neck = neck,
		neckBaseC0 = if neck then neck.C0 else CFrame.new(),
		tracks = ZombieAnimator.setup(model, humanoid, random),
		mode = "Idle",
		strideOffset = strideCounter,
		facesPlayer = random:NextNumber() < config.turnToFacePlayerChance,
		locked = false,
		wakeAt = nil,
		wakeDistance = 0,
		speed = config.speedMin,
		heading = pivot.LookVector,
		desiredHeading = pivot.LookVector,
		turnRate = math.rad(config.maxRotation),
		moveActive = false,
		faceOnly = false,
		targetPoint = nil,
		nextFacingAt = 0,
		alertAt = nil,
	}
	humanoid.WalkSpeed = config.speedMin
	humanoid.AutoRotate = false
	if startAlert then
		state.mode = "Alert"
	end
	if posture == "Dormant" and ZombieAnimator.holdLying(state.tracks) then
		state.mode = "Dormant"
		state.locked = true
		state.wakeDistance = wakeDistance or ZombieBehaviourConfig.STAND_UP_DISTANCE
		root.Anchored = true
		humanoid.WalkSpeed = 0
		setTorsoCollision(model, false)
	elseif posture == "Feeding" and ZombieAnimator.hasFeedingClip(state.tracks) then
		state.mode = "Feeding"
		state.locked = true
		state.wakeDistance = wakeDistance or config.alertRadius * ZombieBehaviourConfig.EATING_ALERT_MODIFIER
		root.Anchored = true
		humanoid.WalkSpeed = 0
		setTorsoCollision(model, false)
		ZombieAnimator.playFeeding(state.tracks)
	end
	strideCounter = (strideCounter + 1) % AI_FAR_STRIDE
	zombies[model] = state
	aliveCount += 1
end

local function findNearestPlayer(position: Vector3): Player?
	local nearest: Player? = nil
	local nearestDistance = math.huge
	for _, player in MissionState.getParticipants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local distance = (root.Position - position).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = player
		end
	end
	return nearest
end

local function turnToward(current: Vector3, desired: Vector3, maxAngle: number): Vector3
	local flatCurrent = Vector3.new(current.X, 0, current.Z)
	local flatDesired = Vector3.new(desired.X, 0, desired.Z)
	if flatDesired.Magnitude < 0.01 then
		return current
	end
	if flatCurrent.Magnitude < 0.01 then
		return flatDesired.Unit
	end
	flatCurrent = flatCurrent.Unit
	flatDesired = flatDesired.Unit
	local cosine = math.clamp(flatCurrent:Dot(flatDesired), -1, 1)
	local angle = math.acos(cosine)
	if angle <= maxAngle then
		return flatDesired
	end
	local sign = if flatCurrent:Cross(flatDesired).Y >= 0 then 1 else -1
	return (CFrame.fromAxisAngle(Vector3.yAxis, sign * maxAngle) * flatCurrent).Unit
end

local function speedFromCurve(config: ZombiesConfig.ZombieConfig, distance: number, speedScale: number): number
	local t = math.clamp(distance / config.alertRadius, 0, 1)
	local deadzone = ZombieBehaviourConfig.SPEED_CURVE_DEADZONE
	local floor = ZombieBehaviourConfig.SPEED_CURVE_FLOOR
	local curve = if t < deadzone then 0 else floor + (1 - floor) * (t - deadzone) / (1 - deadzone)
	return (config.speedMin + (config.speedMax - config.speedMin) * curve) * speedScale
end

local HEAD_TRACK_RANGE = 70
local HEAD_TRACK_LIMIT = math.rad(60)

local function trackPlayerWithHead(state: ZombieState)
	local neck = state.neck
	if not neck or not neck.Parent then
		return
	end
	local target = findNearestPlayer(state.root.Position)
	if not target then
		neck.C0 = state.neckBaseC0
		return
	end
	local character = target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then
		neck.C0 = state.neckBaseC0
		return
	end
	local offset = targetRoot.Position - state.root.Position
	if offset.Magnitude > HEAD_TRACK_RANGE then
		neck.C0 = state.neckBaseC0
		return
	end

	local localOffset = state.root.CFrame:VectorToObjectSpace(offset)
	local yaw = math.clamp(math.atan2(-localOffset.X, -localOffset.Z), -HEAD_TRACK_LIMIT, HEAD_TRACK_LIMIT)
	local pitch = math.clamp(math.atan2(localOffset.Y, math.max(0.1, math.abs(localOffset.Z))), -0.4, 0.4)
	neck.C0 = state.neckBaseC0 * CFrame.Angles(pitch * 0.5, yaw, 0)
end

local function getModifierSpeedBonus(): number
	local bonus = 0
	for _, id in MissionState.getModifiers() do
		local modifier = ModifiersConfig.get(id)
		if modifier then
			bonus += modifier.zombieSpeedBonus
		end
	end
	return bonus
end

local function finishWake(state: ZombieState)
	state.wakeAt = nil
	state.locked = false
	state.mode = "Idle"
	state.moveActive = false
	state.faceOnly = false
	if state.root.Parent then
		state.root.Anchored = false
	end
	setTorsoCollision(state.model, true)
	ZombieAnimator.setMode(state.tracks, "Idle", state.config.id == "Runner", state.config.speedMin)
end

local function beginWake(state: ZombieState, now: number)
	local formations = ZombieSpawnConfig.formations
	if state.mode == "Dormant" then
		state.wakeAt = now + ZombieAnimator.playRise(state.tracks)
	else
		ZombieAnimator.stopFeeding(state.tracks)
		state.wakeAt = now + formations.feedingWakeDelay
	end
end

local function stepSleeper(state: ZombieState, now: number)
	local wakeAt = state.wakeAt
	if wakeAt then
		if now >= wakeAt then
			finishWake(state)
		end
		return
	end
	local target = findNearestPlayer(state.root.Position)
	local character = target and target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	if targetRoot and targetRoot:IsA("BasePart") and (targetRoot.Position - state.root.Position).Magnitude <= state.wakeDistance then
		beginWake(state, now)
	end
end

local function smoothStep(deltaTime: number)
	for _, state in zombies do
		if not (state.moveActive or state.faceOnly) then
			continue
		end
		if not state.root.Parent or state.humanoid.Health <= 0 then
			continue
		end
		state.heading = turnToward(state.heading, state.desiredHeading, state.turnRate * deltaTime)
		if state.moveActive then
			state.humanoid:Move(state.heading)
		elseif state.faceOnly then
			local current = state.root.CFrame.LookVector
			if current:Dot(state.heading) < 0.9999 then
				state.root.CFrame = CFrame.lookAt(state.root.Position, state.root.Position + state.heading)
			end
		end
	end
end

local function aiStep()
	if not MissionState.isActive() then
		return
	end
	local difficulty = MissionConfig.getDifficulty()
	local speedScale = difficulty.zombieSpeedMultiplier * (1 + getModifierSpeedBonus())
	local aggroActive = difficulty.zombiesChase and DistanceTracker.getMaxDistance() >= difficulty.aggroDistance

	if aggroActive ~= lastAggroState then
		lastAggroState = aggroActive
		Workspace:SetAttribute("ZombiesAggro", aggroActive)
	end

	local lure = corpseLure
	local lureActive = lure ~= nil and os.clock() < lure.expires

	tickIndex += 1

	local now = os.clock()
	local cullEdge = DistanceTracker.getMinDistance() - GameConstants.DESPAWN_BEHIND_DISTANCE
	for _, state in zombies do
		local sleeper = state.mode == "Dormant" or state.mode == "Feeding"
		if (not state.locked or sleeper) and state.root.Position:Dot(GameConstants.RUN_DIRECTION) < cullEdge then
			ZombieAI.recycle(state)
		end
	end
	for index = #corpses, 1, -1 do
		local corpse = corpses[index]
		if not corpse.Parent then
			table.remove(corpses, index)
		elseif corpse:GetPivot().Position:Dot(GameConstants.RUN_DIRECTION) < cullEdge then
			corpse:Destroy()
			table.remove(corpses, index)
		end
	end

	for _, state in zombies do
		if state.humanoid.Health <= 0 then
			if state.mode ~= "Down" then
				state.mode = "Down"
			end
			continue
		end

		if state.mode == "Dormant" or state.mode == "Feeding" then
			stepSleeper(state, now)
			continue
		end

		if state.locked then
			continue
		end

		if lureActive and lure and (state.root.Position - lure.pos).Magnitude < LURE_RANGE then
			state.humanoid.AutoRotate = true
			state.humanoid.WalkSpeed = state.config.speedMax * speedScale
			state.humanoid:MoveTo(lure.pos)
			continue
		end

		local target = findNearestPlayer(state.root.Position)
		local targetRoot = nil
		local distance = math.huge
		if target then
			local character = target.Character
			local candidate = character and character:FindFirstChild("HumanoidRootPart")
			if candidate and candidate:IsA("BasePart") then
				targetRoot = candidate
				distance = (candidate.Position - state.root.Position).Magnitude
			end
		end

		if distance > AI_FULL_RANGE and (tickIndex + state.strideOffset) % AI_FAR_STRIDE ~= 0 then
			continue
		end

		local config = state.config
		local previous = state.mode
		local mode = previous

		if not targetRoot then
			mode = "Idle"
		elseif not aggroActive or not state.facesPlayer then
			mode = if distance <= config.awareRadius then "Aware" else "Idle"
		elseif distance <= config.attackRadius then
			mode = "Attack"
		elseif distance <= config.alertRadius then
			mode = "Alert"
		elseif distance <= config.awareRadius then
			mode = if previous == "Alert" or previous == "Attack" then
					(if distance <= config.alertRadius * HYSTERESIS then "Alert" else "Aware")
				else "Aware"
		else
			mode = if previous == "Aware" and distance <= config.awareRadius * HYSTERESIS then "Aware" else "Idle"
		end

		state.mode = mode

		local chasing = mode == "Alert" or mode == "Attack"
		local tick = GameConstants.ZOMBIE_AI_TICK
		if chasing and targetRoot then
			if previous ~= "Alert" and previous ~= "Attack" then
				state.alertAt = now
				state.nextFacingAt = 0
			end
			if now >= state.nextFacingAt then
				local velocity = targetRoot.AssemblyLinearVelocity
				local lead = Vector3.new(velocity.X, 0, velocity.Z) * ZombieBehaviourConfig.LEAD_SECONDS * config.playerLeading
				state.targetPoint = targetRoot.Position + lead
				state.nextFacingAt = now + config.facingUpdateFreq
			end
			local targetPoint = state.targetPoint or targetRoot.Position
			local toTarget = (targetPoint - state.root.Position) * Vector3.new(1, 0, 1)
			if toTarget.Magnitude > 0.01 then
				state.desiredHeading = toTarget.Unit
			end
			state.turnRate = math.rad(config.maxRotation)
			local cruise = speedFromCurve(config, distance, speedScale)
			local floorSpeed = config.speedMin * speedScale
			local ramp = math.clamp((now - (state.alertAt or now)) / ZombieBehaviourConfig.ALERT_ACCELERATION_DURATION, 0, 1)
			state.speed = floorSpeed + (cruise - floorSpeed) * ramp
			state.humanoid.AutoRotate = true
			state.humanoid.WalkSpeed = state.speed
			state.moveActive = true
			state.faceOnly = false
			ZombieAnimator.setSpeed(state.tracks, config.id == "Runner", state.speed)
		else
			state.alertAt = nil
			state.speed = 0
			state.humanoid.AutoRotate = false
			state.humanoid.WalkSpeed = config.speedMin * speedScale
			if state.moveActive then
				state.humanoid:Move(Vector3.zero)
			end
			state.moveActive = false
			if mode == "Aware" and targetRoot then
				local toTarget = (targetRoot.Position - state.root.Position) * Vector3.new(1, 0, 1)
				if toTarget.Magnitude > 0.01 then
					state.desiredHeading = toTarget.Unit
				end
				state.turnRate = math.rad(ZombieBehaviourConfig.AWARE_TURN_RATE)
				state.faceOnly = true
			else
				state.faceOnly = false
			end
			trackPlayerWithHead(state)
		end

		if mode ~= previous then
			ZombieAnimator.setMode(state.tracks, mode, config.id == "Runner", math.max(state.speed, config.speedMin))
		end
	end
end

function ZombieAI.swarmCorpse(position: Vector3, duration: number)
	corpseLure = { pos = position, expires = os.clock() + duration }
end

local FEED_REACH = 4.6
local FEED_STAND_MIN = 2.3
local FEED_STAND_MAX = 3.1
local FEED_RATE = 5.5
local KNEEL_DROP = 0.9

type FeedMotors = {
	waist: Motor6D?,
	neck: Motor6D?,
	leftShoulder: Motor6D?,
	rightShoulder: Motor6D?,
	leftHip: Motor6D?,
	rightHip: Motor6D?,
}

type Feeder = {
	state: ZombieState,
	phase: number,
	kneel: boolean,
	posed: boolean,
	procedural: boolean,
	motors: FeedMotors,
	base: { [string]: CFrame },
}

local poseRestores: { [Model]: () -> () } = {}

local function motorNamed(part: Instance?, name: string): Motor6D?
	local motor = if part then part:FindFirstChild(name) else nil
	if motor and motor:IsA("Motor6D") then
		return motor
	end
	return nil
end

local function collectMotors(model: Model): FeedMotors
	local lowerTorso = model:FindFirstChild(ZombieRig.LOWER_TORSO_NAME)
	local upperTorso = model:FindFirstChild(ZombieRig.TORSO_NAME)
	return {
		waist = motorNamed(lowerTorso, "Waist"),
		neck = motorNamed(upperTorso, "Neck"),
		leftShoulder = motorNamed(upperTorso, "LeftShoulder"),
		rightShoulder = motorNamed(upperTorso, "RightShoulder"),
		leftHip = motorNamed(lowerTorso, "LeftHip"),
		rightHip = motorNamed(lowerTorso, "RightHip"),
	}
end

local function releaseFeeder(feeder: Feeder)
	local state = feeder.state
	poseRestores[state.model] = nil
	for name, motor in feeder.motors :: { [string]: Motor6D? } do
		local base = feeder.base[name]
		if motor and motor.Parent and base then
			motor.C0 = base
		end
	end
	if state.root.Parent then
		state.root.Anchored = false
	end
	state.locked = false
end

local function poseFeeder(feeder: Feeder, corpse: Vector3)
	local state = feeder.state
	local root = state.root
	feeder.procedural = not ZombieAnimator.hasFeedingClip(state.tracks)
	local flat = (root.Position - corpse) * Vector3.new(1, 0, 1)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
	local standDistance = math.clamp(flat.Magnitude, FEED_STAND_MIN, FEED_STAND_MAX)
	local standY = root.Position.Y - (if feeder.kneel and feeder.procedural then KNEEL_DROP else 0)
	local standPosition = Vector3.new(corpse.X, standY, corpse.Z) + direction * standDistance

	state.locked = true
	state.humanoid.WalkSpeed = 0
	state.humanoid:MoveTo(root.Position)
	root.Anchored = true
	root.CFrame = CFrame.lookAt(standPosition, Vector3.new(corpse.X, standY, corpse.Z))

	feeder.motors = collectMotors(state.model)
	for name, motor in feeder.motors :: { [string]: Motor6D? } do
		if motor then
			feeder.base[name] = motor.C0
		end
	end
	feeder.posed = true
	poseRestores[state.model] = function()
		releaseFeeder(feeder)
	end
	ZombieAnimator.playFeeding(state.tracks)
end

local function animateFeeder(feeder: Feeder, elapsed: number)
	if not feeder.procedural then
		return
	end
	local motors = feeder.motors
	local base = feeder.base
	local t = elapsed * FEED_RATE + feeder.phase
	local chew = math.max(math.sin(t), 0) ^ 3
	local sway = math.sin(t * 0.37 + feeder.phase)
	local bend = if feeder.kneel then 40 else 54

	if motors.waist and base.waist then
		motors.waist.C0 = base.waist * CFrame.Angles(math.rad(-bend - chew * 7), math.rad(sway * 5), 0)
	end
	if motors.neck and base.neck then
		motors.neck.C0 = base.neck * CFrame.Angles(math.rad(-16 - chew * 16), math.rad(math.sin(t * 0.5) * 9), 0)
	end
	if motors.leftShoulder and base.leftShoulder then
		motors.leftShoulder.C0 = base.leftShoulder * CFrame.Angles(math.rad(46 + chew * 9), 0, math.rad(14 + sway * 4))
	end
	if motors.rightShoulder and base.rightShoulder then
		motors.rightShoulder.C0 = base.rightShoulder * CFrame.Angles(math.rad(50 + chew * 6), 0, math.rad(-14 - sway * 4))
	end
	if feeder.kneel then
		if motors.leftHip and base.leftHip then
			motors.leftHip.C0 = base.leftHip * CFrame.Angles(math.rad(-82), 0, 0)
		end
		if motors.rightHip and base.rightHip then
			motors.rightHip.C0 = base.rightHip * CFrame.Angles(math.rad(-82), 0, 0)
		end
	end
end

function ZombieAI.feedOnCorpse(position: Vector3, duration: number, maxFeeders: number)
	local candidates: { ZombieState } = {}
	for _, state in zombies do
		if state.humanoid.Health > 0 and not state.locked and (state.root.Position - position).Magnitude < LURE_RANGE then
			table.insert(candidates, state)
		end
	end
	table.sort(candidates, function(a, b)
		return (a.root.Position - position).Magnitude < (b.root.Position - position).Magnitude
	end)

	local feeders: { Feeder } = {}
	for index = 1, math.min(maxFeeders, #candidates) do
		table.insert(feeders, {
			state = candidates[index],
			phase = random:NextNumber(0, math.pi * 2),
			kneel = index % 2 == 0,
			posed = false,
			procedural = true,
			motors = {},
			base = {},
		})
	end
	if #feeders == 0 then
		return
	end

	local startedAt = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startedAt
		if elapsed > duration then
			connection:Disconnect()
			for _, feeder in feeders do
				if feeder.posed then
					releaseFeeder(feeder)
				end
			end
			return
		end
		for _, feeder in feeders do
			local state = feeder.state
			if zombies[state.model] ~= state or state.humanoid.Health <= 0 or not state.root.Parent then
				continue
			end
			if not feeder.posed then
				local flat = (state.root.Position - position) * Vector3.new(1, 0, 1)
				if flat.Magnitude <= FEED_REACH then
					poseFeeder(feeder, position)
				end
			else
				animateFeeder(feeder, elapsed)
			end
		end
	end)
end

function ZombieAI.clearLure()
	corpseLure = nil
end

function ZombieAI.recycle(state: ZombieState)
	local model = state.model
	if zombies[model] == nil then
		return
	end
	zombies[model] = nil
	aliveCount = math.max(0, aliveCount - 1)

	ZombieAnimator.stopAll(state.tracks)
	table.clear(state.lastHitAt)
	local restore = poseRestores[model]
	if restore then
		restore()
	end

	local humanoid = state.humanoid
	local pool = pools[state.config.id]
	local intact = humanoid.Health > 0
		and model.PrimaryPart ~= nil
		and humanoid.Parent == model
		and model:FindFirstChild("Hitbox") ~= nil
	if not pool or #pool >= MAX_POOLED or not intact then
		model:Destroy()
		return
	end

	model.Parent = nil
	state.root.Anchored = false
	setTorsoCollision(model, true)
	local neck = state.neck
	if neck and neck.Parent then
		neck.C0 = state.neckBaseC0
	end
	table.insert(pool, model)
end

function ZombieAI.configure(seed: number)
	random = Random.new(seed)
	nextSpawnAt = ZombieSpawnConfig.START_CLEARANCE
	sectionCap = 0
	for id, pool in pools do
		for _, model in pool do
			model:Destroy()
		end
		pools[id] = {}
	end
end

local TIER_OFFSETS: { [string]: number } = { Easy = -1, Medium = 0, Hard = 1 }

local function difficultyTierOffset(): number
	return TIER_OFFSETS[MissionConfig.getDifficulty().id] or 0
end

local function separatedEnough(candidate: Vector3, minimum: number): boolean
	local squared = minimum * minimum
	for _, state in zombies do
		if (state.root.Position - candidate).Magnitude ^ 2 < squared then
			return false
		end
	end
	return true
end

local function placeAt(alongDistance: number, lateralX: number, separation: number, spread: number?): Vector3?
	local base = GameConstants.RUN_ORIGIN + GameConstants.RUN_DIRECTION * alongDistance
	local range = spread or 6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getFolder(), getPropsFolder() }
	for _ = 1, ZombieSpawnConfig.SEPARATION_RETRIES do
		local jitter = random:NextNumber(-range, range)
		local candidate = Vector3.new(lateralX, base.Y + 2, base.Z + jitter)
		local hit = Workspace:Raycast(candidate + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
		local onGround = hit ~= nil and (hit.Instance.Name == "Floor" or hit.Instance.Name == "Apron")
		if onGround and separatedEnough(candidate, separation) then
			return candidate
		end
	end
	return nil
end

local function bandLimits(): (number, number)
	local originX = GameConstants.RUN_ORIGIN.X
	local half = GameConstants.PLAYABLE_HALF_WIDTH + GameConstants.ZOMBIE_SPAWN_BORDER
	return originX - half, originX + half
end

local function pickForSection(section: ZombieSpawnConfig.ResolvedSection): ZombiesConfig.ZombieConfig
	if section.zombieIds then
		return pickConfigFrom(section.zombieIds)
	end
	if random:NextNumber() < section.runnerChance then
		return pickConfigFrom({ "Runner" })
	end
	return pickConfigFrom({ "Walker" })
end

local function spawnAtSlot(alongDistance: number, lateralX: number, separation: number, spread: number, section: ZombieSpawnConfig.ResolvedSection, startAlert: boolean, posture: string?)
	local position = placeAt(alongDistance, lateralX, separation, spread)
	if not position then
		return
	end
	local config = pickForSection(section)
	if posture then
		spawnZombie(position, config, startAlert, posture, nil, section.standUpDistance)
		return
	end
	if random:NextNumber() < section.lyingChance then
		spawnZombie(position, config, false, "Dormant", nil, section.standUpDistance)
		return
	end
	if random:NextNumber() < section.eatingChance then
		local corpse = spawnCorpse(position)
		local corpsePosition = corpse:GetPivot().Position
		local angle = random:NextNumber() * math.pi * 2
		local feeder = Vector3.new(position.X + math.cos(angle) * 2.8, position.Y, position.Z + math.sin(angle) * 2.8)
		spawnZombie(feeder, config, false, "Feeding", corpsePosition, config.alertRadius * ZombieBehaviourConfig.EATING_ALERT_MODIFIER)
		return
	end
	spawnZombie(position, config, startAlert)
end

local function spawnClump(alongDistance: number, section: ZombieSpawnConfig.ResolvedSection, leadX: number, forceClump: boolean)
	local minX, maxX = bandLimits()
	local side = if random:NextNumber() < section.leftSideChance then -1 else 1
	local offset = random:NextNumber(section.lateralMin, section.lateralMax)
	local lateralX = math.clamp(leadX + side * offset, minX, maxX)

	local wantsClump = forceClump or random:NextNumber() < section.clumpChance
	local count = 1
	if wantsClump then
		local low = math.max(1, math.floor(section.clumpSizeMin + 0.5))
		local high = math.max(low, math.floor(section.clumpSizeMax + 0.5))
		count = random:NextInteger(low, high)
	end
	count = math.min(count, math.max(0, section.maxAlive - aliveCount))

	for i = 1, count do
		local spreadX = lateralX
		local spreadAlong = alongDistance
		if wantsClump and i > 1 then
			local angle = random:NextNumber() * math.pi * 2
			local radius = random:NextNumber() * math.max(section.clumpRadius, 6)
			spreadX = math.clamp(lateralX + math.cos(angle) * radius, minX, maxX)
			spreadAlong = alongDistance + math.sin(angle) * radius
		end
		local separation = if wantsClump then ZombieSpawnConfig.CLUMP_SEPARATION else ZombieSpawnConfig.MIN_SEPARATION
		spawnAtSlot(spreadAlong, spreadX, separation, 6, section, random:NextNumber() < section.alertChance)
	end
end

local function spawnPattern(pattern: string, alongDistance: number, section: ZombieSpawnConfig.ResolvedSection, leadX: number)
	local formations = ZombieSpawnConfig.formations
	local minX, maxX = bandLimits()
	local budget = math.max(0, section.maxAlive - aliveCount)
	if budget <= 0 then
		return
	end
	local side = if random:NextNumber() < section.leftSideChance then -1 else 1
	local clumpSeparation = ZombieSpawnConfig.CLUMP_SEPARATION

	if pattern == "wall" then
		local count = math.min(budget, random:NextInteger(formations.wallCountMin, formations.wallCountMax))
		local width = (count - 1) * formations.wallSpacing + (formations.wallGap - formations.wallSpacing)
		local start = math.clamp(leadX + random:NextNumber(-8, 8) - width / 2, minX, maxX - width)
		local gapIndex = random:NextInteger(1, math.max(1, count - 1))
		local cursor = start
		for i = 1, count do
			spawnAtSlot(alongDistance, cursor, clumpSeparation, formations.wallJitter, section, random:NextNumber() < section.alertChance)
			cursor += if i == gapIndex then formations.wallGap else formations.wallSpacing
		end
	elseif pattern == "diagonal" then
		local count = math.min(budget, random:NextInteger(formations.diagonalCountMin, formations.diagonalCountMax))
		local direction = if random:NextNumber() < 0.5 then -1 else 1
		local startX = math.clamp(leadX + side * random:NextNumber(2, 14), minX, maxX)
		for i = 0, count - 1 do
			local x = math.clamp(startX + direction * formations.diagonalStepX * i, minX, maxX)
			spawnAtSlot(alongDistance + formations.diagonalStepAlong * i, x, clumpSeparation, 1.5, section, random:NextNumber() < section.alertChance)
		end
	elseif pattern == "column" then
		local count = math.min(budget, random:NextInteger(formations.columnCountMin, formations.columnCountMax))
		local x = math.clamp(leadX + side * random:NextNumber(6, 22), minX, maxX)
		for i = 0, count - 1 do
			spawnAtSlot(alongDistance + formations.columnStep * i, x, clumpSeparation, 1.5, section, random:NextNumber() < section.alertChance)
		end
	elseif pattern == "loiter" then
		local count = math.min(budget, random:NextInteger(formations.loiterCountMin, formations.loiterCountMax))
		local edgeX = GameConstants.RUN_ORIGIN.X + side * (GameConstants.PLAYABLE_HALF_WIDTH - random:NextNumber(0, formations.loiterEdgeInset))
		for _ = 1, count do
			spawnAtSlot(alongDistance + random:NextNumber(0, 12), edgeX + random:NextNumber(-4, 4), ZombieSpawnConfig.MIN_SEPARATION, 3, section, false)
		end
	elseif pattern == "risers" then
		local count = math.min(budget, random:NextInteger(formations.riserCountMin, formations.riserCountMax))
		local centreX = math.clamp(leadX + side * random:NextNumber(4, 24), minX, maxX)
		local spread = formations.riserSpread
		for _ = 1, count do
			local x = math.clamp(centreX + random:NextNumber(-spread, spread), minX, maxX)
			spawnAtSlot(alongDistance + random:NextNumber(-spread, spread), x, clumpSeparation, 2, section, false, "Dormant")
		end
	elseif pattern == "feast" then
		local centreX = math.clamp(leadX + side * random:NextNumber(6, 26), minX + 4, maxX - 4)
		local base = GameConstants.RUN_ORIGIN + GameConstants.RUN_DIRECTION * alongDistance
		local corpsePosition = Vector3.new(centreX, base.Y + 2, base.Z)
		spawnCorpse(corpsePosition)
		local count = math.min(budget, formations.feastCount)
		for i = 1, count do
			local angle = (i / count) * math.pi * 2 + random:NextNumber(-0.4, 0.4)
			local position = Vector3.new(
				centreX + math.cos(angle) * formations.feastRadius,
				base.Y + 2,
				base.Z + math.sin(angle) * formations.feastRadius
			)
			spawnZombie(position, pickForSection(section), false, "Feeding", corpsePosition, nil)
		end
	elseif pattern == "clump" then
		spawnClump(alongDistance, section, leadX, true)
	else
		spawnClump(alongDistance, section, leadX, false)
	end
end

local function spawnEvent(alongDistance: number, section: ZombieSpawnConfig.ResolvedSection, leadX: number)
	local pattern = ZombieSpawnConfig.pickPattern(section.patterns, random:NextNumber())
	spawnPattern(pattern, alongDistance, section, leadX)
end

local function fallbackSection(location: LocationsConfig.LocationConfig): ZombieSpawnConfig.ResolvedSection
	local mean = math.max(1, (location.zombiesMin + location.zombiesMax) / 2)
	local delay = GameConstants.CHUNK_LENGTH / GameConstants.BASE_RUN_SPEED / mean
	return {
		spawnDelayMin = delay * 0.8,
		spawnDelayMax = delay * 1.2,
		lateralMin = 0,
		lateralMax = GameConstants.LANE_WIDTH / 2 - GameConstants.ZOMBIE_SPAWN_EDGE_MARGIN,
		leftSideChance = 0.5,
		alertChance = 0,
		clumpChance = 0,
		clumpRadius = 0,
		clumpSizeMin = 1,
		clumpSizeMax = 1,
		maxAlive = MAX_ALIVE,
		patterns = { single = 1 },
		zombieIds = nil,
	}
end

local function spawnStep()
	local lead = DistanceTracker.getMaxDistance()
	local leadX = GameConstants.RUN_ORIGIN.X
	for _, player in MissionState.getParticipants() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			leadX = root.Position.X
			break
		end
	end

	local budget = ZombieSpawnConfig.MAX_SPAWN_EVENTS_PER_STEP
	while lead + GameConstants.ZOMBIE_SPAWN_AHEAD >= nextSpawnAt and budget > 0 do
		local location = RoutePlan.locationForDistance(nextSpawnAt)
		local section: ZombieSpawnConfig.ResolvedSection? = nil
		if location and location.spawnSections then
			local id, t = RoutePlan.sectionAt(nextSpawnAt, location.spawnSections)
			if id then
				section = ZombieSpawnConfig.resolve(id, t, difficultyTierOffset())
			end
		end
		if not section and location then
			section = fallbackSection(location)
		end
		if not section then
			nextSpawnAt += GameConstants.CHUNK_LENGTH
			break
		end
		local resolved = section :: ZombieSpawnConfig.ResolvedSection
		sectionCap = resolved.maxAlive
		if aliveCount < resolved.maxAlive then
			spawnEvent(nextSpawnAt, resolved, leadX)
		end
		local delay = random:NextNumber(resolved.spawnDelayMin, resolved.spawnDelayMax)
		nextSpawnAt += math.max(4, delay * GameConstants.BASE_RUN_SPEED)
		budget -= 1
	end
end

function ZombieAI.clearAll()
	for model in zombies do
		zombies[model] = nil
		model:Destroy()
	end
	for _, corpse in corpses do
		corpse:Destroy()
	end
	table.clear(corpses)
	aliveCount = 0
end

function ZombieAI.getAliveCount(): number
	return aliveCount
end

function ZombieAI.getSectionCap(): number
	return sectionCap
end

function ZombieAI.getNextSpawnAt(): number
	return nextSpawnAt
end

function ZombieAI.getPooledCount(): number
	local total = 0
	for _, pool in pools do
		total += #pool
	end
	return total
end

function ZombieAI.init()
	RunService.Heartbeat:Connect(function(deltaTime)
		if MissionState.isActive() then
			smoothStep(deltaTime)
		end
		tickAccumulator += deltaTime
		if tickAccumulator < GameConstants.ZOMBIE_AI_TICK then
			return
		end
		tickAccumulator -= GameConstants.ZOMBIE_AI_TICK
		if MissionState.isActive() then
			spawnStep()
		end
		aiStep()
	end)
end

return ZombieAI
