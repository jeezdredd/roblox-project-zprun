--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)

local WeaponVfx = {}

local localPlayer = Players.LocalPlayer

local TAU = math.pi * 2

local TRACER_COLOR = Color3.fromRGB(255, 214, 140)
local FLASH_COLOR = Color3.fromRGB(255, 196, 110)
local FLASH_HOT_COLOR = Color3.fromRGB(255, 244, 222)
local FLASH_TIP_COLOR = Color3.fromRGB(255, 150, 60)
local SMOKE_COLOR = Color3.fromRGB(160, 158, 152)

-- The engine's own smoke sprite (the one the legacy Smoke object draws), shipped with
-- every client; it is not an uploaded asset. The default ParticleEmitter sprite is a
-- four-point sparkle, which reads as glitter rather than smoke once it is gray and
-- large. Set this to nil to fall back to that default.
local SMOKE_TEXTURE: string? = "rbxasset://textures/particles/smoke_main.dds"

-- One render-step callback drives both the casings and the flash timers. It runs just
-- after the camera scripts (Camera = 200) so a view-space casing is placed from this
-- frame's camera and never trails it by a frame; Heartbeat or a late priority jitters.
local STEP_NAME = "WeaponVfxStep"
local STEP_PRIORITY = Enum.RenderPriority.Camera.Value + 2
-- a hitch must not teleport a casing through half the map in one step
local MAX_STEP = 1 / 20

local vfxFolder: Folder? = nil

local function getFolder(): Folder
	local folder = vfxFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "WeaponVfx"
	created.Parent = Workspace
	vfxFolder = created
	return created
end

local function makeGhostPart(name: string, size: Vector3, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = getFolder()
	return part
end

local function rollRange(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

local stepBound = false
local onRenderStep: (number) -> ()

local function ensureStepBound()
	if stepBound then
		return
	end
	stepBound = true
	RunService:BindToRenderStep(STEP_NAME, STEP_PRIORITY, function(deltaTime: number)
		onRenderStep(deltaTime)
	end)
end

--------------------------------------------------------------------------------------
-- Muzzle flash
--
-- MW reads as a white-hot core that is gone in one or two frames, a few flame petals
-- thrown sideways, a forward tongue and a short light pop, never the same shape twice.
-- Everything is built once per muzzle attachment and reused, so a 600 rpm weapon does
-- not create and destroy a dozen instances a second. Every emitter is LockedToPart:
-- the player runs at about 24 studs/s, and a world-space flash or wisp gets left almost
-- a stud behind the muzzle in the two frames it lives, smearing back towards the eye.
--------------------------------------------------------------------------------------

type FlashVariant = {
	petals: number,
	petalLength: number,
	petalWidth: number,
	-- forward lean of the petals, radians; 0 is a flat star across the muzzle
	petalTilt: number,
	tongueLength: number,
	tongueWidth: number,
	core: number,
}

-- Four shapes picked at random (never the same one twice in a row) on top of the
-- random roll and scale, so sustained fire never repeats a frame.
local FLASH_VARIANTS: { FlashVariant } = {
	{ petals = 3, petalLength = 0.34, petalWidth = 0.11, petalTilt = math.rad(30), tongueLength = 0.7, tongueWidth = 0.16, core = 0.55 },
	{ petals = 4, petalLength = 0.3, petalWidth = 0.1, petalTilt = math.rad(38), tongueLength = 0.55, tongueWidth = 0.14, core = 0.6 },
	{ petals = 5, petalLength = 0.26, petalWidth = 0.085, petalTilt = math.rad(24), tongueLength = 0.8, tongueWidth = 0.15, core = 0.5 },
	{ petals = 4, petalLength = 0.4, petalWidth = 0.12, petalTilt = math.rad(46), tongueLength = 0.45, tongueWidth = 0.18, core = 0.68 },
}
local FLASH_MAX_PETALS = 5

local FLASH_CLASS_SCALE: { [string]: number } = {
	Pistol = 0.8,
	SMG = 0.85,
	Rifle = 1,
	Shotgun = 1.5,
}
-- +-20% per shot
local FLASH_SCALE_JITTER = 0.2
-- Petals and tongue stay up at least one rendered frame and are cut after this, which
-- is two frames at 60 fps. The core particle's own lifetime matches it.
local FLASH_CORE_TIME = 0.028
local FLASH_LIGHT_TIME = NumberRange.new(0.04, 0.06)
local FLASH_LIGHT_BRIGHTNESS = 3.5
local FLASH_LIGHT_RANGE = 12
local FLASH_SPARK_CHANCE = 0.35

local BEAM_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})

type MuzzleRig = {
	attachment: Attachment,
	core: ParticleEmitter,
	sparks: ParticleEmitter,
	wisp: ParticleEmitter,
	puff: ParticleEmitter,
	trail: ParticleEmitter,
	light: PointLight,
	-- beams[1] is the forward tongue, the rest are petals; tips[i] is beams[i]'s far end
	beams: { Beam },
	tips: { Attachment },
	flashOn: boolean,
	flashOffAt: number,
	framesShown: number,
	lightOn: boolean,
	lightOffAt: number,
	listed: boolean,
}

-- optional values so pruning can assign nil under strict mode
local muzzleRigs: { [Attachment]: MuzzleRig? } = {}
local activeFlashes: { MuzzleRig } = {}
local lastVariant = 0

local function applySmokeTexture(emitter: ParticleEmitter)
	local texture = SMOKE_TEXTURE
	if texture then
		emitter.Texture = texture
	end
end

local function buildMuzzleRig(attachment: Attachment): MuzzleRig
	-- Rate is zeroed before parenting: a fresh emitter defaults to 20/s and would
	-- spray for a frame otherwise.
	local core = Instance.new("ParticleEmitter")
	core.Name = "FlashCore"
	core.Rate = 0
	core.Color = ColorSequence.new(FLASH_HOT_COLOR, FLASH_COLOR)
	core.LightEmission = 1
	core.LightInfluence = 0
	core.Brightness = 2.5
	core.Size = NumberSequence.new(0.5)
	core.Transparency = NumberSequence.new(0, 0.5)
	core.Lifetime = NumberRange.new(0.022, 0.034)
	core.Speed = NumberRange.new(0)
	core.Rotation = NumberRange.new(0, 360)
	core.LockedToPart = true
	-- pulls the sprite towards the camera so the barrel end does not cut it in half
	core.ZOffset = 0.15
	core.Parent = attachment

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "FlashSparks"
	sparks.Rate = 0
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 222, 160), FLASH_TIP_COLOR)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Brightness = 2
	sparks.Size = NumberSequence.new(0.035, 0.01)
	sparks.Transparency = NumberSequence.new(0, 1)
	sparks.Lifetime = NumberRange.new(0.05, 0.12)
	sparks.Speed = NumberRange.new(14, 28)
	sparks.SpreadAngle = Vector2.new(22, 22)
	-- both rig builders keep the muzzle attachment's -Z along the barrel
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Drag = 4
	sparks.LockedToPart = true
	sparks.Parent = attachment

	-- per-shot wisp: faint and short, it only has to hint that the gun is hot
	local wisp = Instance.new("ParticleEmitter")
	wisp.Name = "FlashWisp"
	wisp.Rate = 0
	wisp.Color = ColorSequence.new(SMOKE_COLOR)
	wisp.LightEmission = 0
	wisp.LightInfluence = 0.8
	wisp.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12, 0.04),
		NumberSequenceKeypoint.new(1, 0.6, 0.15),
	})
	wisp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.74),
		NumberSequenceKeypoint.new(0.35, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisp.Lifetime = NumberRange.new(0.4, 0.6)
	wisp.Speed = NumberRange.new(0.8, 1.6)
	wisp.SpreadAngle = Vector2.new(25, 25)
	wisp.EmissionDirection = Enum.NormalId.Front
	wisp.Acceleration = Vector3.new(0, 1.2, 0)
	wisp.Drag = 3
	wisp.Rotation = NumberRange.new(0, 360)
	wisp.RotSpeed = NumberRange.new(-60, 60)
	wisp.LockedToPart = true
	applySmokeTexture(wisp)
	wisp.Parent = attachment

	-- a denser puff: every shotgun shot, and burstSmoke
	local puff = Instance.new("ParticleEmitter")
	puff.Name = "MuzzlePuff"
	puff.Rate = 0
	puff.Color = ColorSequence.new(SMOKE_COLOR)
	puff.LightEmission = 0
	puff.LightInfluence = 0.8
	puff.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25, 0.08),
		NumberSequenceKeypoint.new(1, 1.3, 0.3),
	})
	puff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.4, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	puff.Lifetime = NumberRange.new(0.6, 0.9)
	puff.Speed = NumberRange.new(2, 4)
	puff.SpreadAngle = Vector2.new(30, 30)
	puff.EmissionDirection = Enum.NormalId.Front
	puff.Acceleration = Vector3.new(0, 1.8, 0)
	puff.Drag = 4
	puff.Rotation = NumberRange.new(0, 360)
	puff.RotSpeed = NumberRange.new(-45, 45)
	puff.LockedToPart = true
	applySmokeTexture(puff)
	puff.Parent = attachment

	-- the lazy post-burst wisp that rises off the barrel (barrelSmoke)
	local trail = Instance.new("ParticleEmitter")
	trail.Name = "BarrelSmoke"
	trail.Rate = 0
	trail.Color = ColorSequence.new(SMOKE_COLOR)
	trail.LightEmission = 0
	trail.LightInfluence = 0.8
	trail.Size = NumberSequence.new(0.2, 1.2)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = NumberRange.new(0.9, 1.6)
	trail.Speed = NumberRange.new(0.6, 1.4)
	trail.SpreadAngle = Vector2.new(18, 18)
	trail.EmissionDirection = Enum.NormalId.Top
	trail.Acceleration = Vector3.new(0, 1.6, 0)
	trail.Drag = 0.8
	trail.Rotation = NumberRange.new(0, 360)
	trail.RotSpeed = NumberRange.new(-30, 30)
	trail.LockedToPart = true
	applySmokeTexture(trail)
	trail.Parent = attachment

	local light = Instance.new("PointLight")
	light.Name = "FlashLight"
	light.Enabled = false
	light.Color = FLASH_COLOR
	light.Brightness = FLASH_LIGHT_BRIGHTNESS
	light.Range = FLASH_LIGHT_RANGE
	light.Shadows = false
	light.Parent = attachment

	-- Untextured beams from the muzzle to a tip attachment, facing the camera and
	-- tapering to nothing, make the flame spikes. The tips live on the muzzle's part so
	-- they ride along with the viewmodel for the two frames a flash lasts.
	local beams: { Beam } = {}
	local tips: { Attachment } = {}
	local part = attachment.Parent
	if part and part:IsA("BasePart") then
		for _ = 1, FLASH_MAX_PETALS + 1 do
			local tip = Instance.new("Attachment")
			tip.Name = "FlashTip"
			tip.Parent = part

			local beam = Instance.new("Beam")
			beam.Name = "FlashPetal"
			beam.Enabled = false
			beam.Attachment0 = attachment
			beam.Attachment1 = tip
			beam.Color = ColorSequence.new(FLASH_HOT_COLOR, FLASH_TIP_COLOR)
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 2
			beam.Transparency = BEAM_TRANSPARENCY
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Width0 = 0.1
			beam.Width1 = 0
			beam.ZOffset = 0.1
			beam.Parent = part

			table.insert(beams, beam)
			table.insert(tips, tip)
		end
	end

	return {
		attachment = attachment,
		core = core,
		sparks = sparks,
		wisp = wisp,
		puff = puff,
		trail = trail,
		light = light,
		beams = beams,
		tips = tips,
		flashOn = false,
		flashOffAt = 0,
		framesShown = 0,
		lightOn = false,
		lightOffAt = 0,
		listed = false,
	}
end

-- Rigs die with their viewmodel on every weapon swap; drop the stale entries so the
-- table does not hold destroyed instances for the rest of the session.
local function pruneMuzzleRigs()
	for attachment, _ in muzzleRigs do
		if attachment.Parent == nil then
			muzzleRigs[attachment] = nil
		end
	end
end

local function getMuzzleRig(attachment: Attachment): MuzzleRig
	local existing = muzzleRigs[attachment]
	if existing then
		-- someone may have cleared the attachment's children; rebuild if so
		if existing.core.Parent == attachment then
			return existing
		end
	end
	pruneMuzzleRigs()
	local rig = buildMuzzleRig(attachment)
	muzzleRigs[attachment] = rig
	return rig
end

local function pickFlashVariant(): FlashVariant
	local index = math.random(1, #FLASH_VARIANTS)
	if index == lastVariant then
		index = index % #FLASH_VARIANTS + 1
	end
	lastVariant = index
	return FLASH_VARIANTS[index]
end

local function showFlashBeams(rig: MuzzleRig, variant: FlashVariant, scale: number, camera: Camera)
	local beams = rig.beams
	local tips = rig.tips
	local part = rig.attachment.Parent
	if #beams == 0 or not part or not part:IsA("BasePart") then
		return
	end
	-- The flash is laid out in camera axes, not the attachment's: the pack rigs'
	-- attachment frames follow a bone whose roll is arbitrary, and the star has to face
	-- the viewer whatever that bone does.
	local partCFrame = part.CFrame
	local cameraCFrame = camera.CFrame
	local forward = cameraCFrame.LookVector
	local right = cameraCFrame.RightVector
	local up = cameraCFrame.UpVector
	local origin = rig.attachment.WorldPosition

	local tongueLength = variant.tongueLength * scale * (0.85 + math.random() * 0.3)
	tips[1].Position = partCFrame:PointToObjectSpace(origin + forward * tongueLength)
	beams[1].Width0 = variant.tongueWidth * scale
	beams[1].Enabled = true

	local roll = math.random() * TAU
	local spacing = TAU / variant.petals
	local cosTilt = math.cos(variant.petalTilt)
	local sinTilt = math.sin(variant.petalTilt)
	for petal = 1, FLASH_MAX_PETALS do
		local beam = beams[petal + 1]
		if petal <= variant.petals then
			local angle = roll + (petal - 1) * spacing + (math.random() - 0.5) * spacing * 0.35
			local radial = right * math.cos(angle) + up * math.sin(angle)
			local direction = radial * cosTilt + forward * sinTilt
			local length = variant.petalLength * scale * (0.75 + math.random() * 0.5)
			tips[petal + 1].Position = partCFrame:PointToObjectSpace(origin + direction * length)
			beam.Width0 = variant.petalWidth * scale * (0.85 + math.random() * 0.3)
			beam.Enabled = true
		else
			beam.Enabled = false
		end
	end
end

local function emitPuff(rig: MuzzleRig, strength: number)
	local count = math.floor(6 * strength * VfxConfig.DENSITY + 0.5)
	if count > 0 then
		rig.puff:Emit(math.max(2, count))
	end
end

function WeaponVfx.muzzleFlash(attachment: Attachment?, weaponId: string)
	if not attachment or not attachment.Parent then
		return
	end
	local config = WeaponsConfig.get(weaponId)
	local class = if config then config.class else ""
	local rig = getMuzzleRig(attachment)
	local scale = (FLASH_CLASS_SCALE[class] or 1) * (1 + (math.random() * 2 - 1) * FLASH_SCALE_JITTER)
	local variant = pickFlashVariant()
	local density = VfxConfig.DENSITY

	-- Size is rewritten per shot for the +-20% scale; the envelope adds a little more
	-- spread between the two sprites, and Rotation 0-360 rolls each one.
	local coreSize = variant.core * scale
	rig.core.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, coreSize, coreSize * 0.2),
		NumberSequenceKeypoint.new(1, coreSize * 1.3, coreSize * 0.2),
	})
	rig.core:Emit(2)

	local camera = Workspace.CurrentCamera
	if camera then
		showFlashBeams(rig, variant, scale, camera)
	end

	local now = os.clock()
	rig.flashOn = #rig.beams > 0
	rig.flashOffAt = now + FLASH_CORE_TIME
	rig.framesShown = 0

	local light = rig.light
	light.Brightness = FLASH_LIGHT_BRIGHTNESS * (0.85 + math.random() * 0.3)
	light.Range = FLASH_LIGHT_RANGE * math.sqrt(scale)
	light.Enabled = true
	rig.lightOn = true
	rig.lightOffAt = now + rollRange(FLASH_LIGHT_TIME)

	if math.random() < FLASH_SPARK_CHANCE then
		local count = math.floor(math.random(1, 3) * density + 0.5)
		if count > 0 then
			rig.sparks:Emit(count)
		end
	end

	-- Spec: a puff after every shotgun shot; everything else leaves a faint wisp.
	if class == "Shotgun" then
		emitPuff(rig, 1)
	elseif density > 0 then
		rig.wisp:Emit(1)
	end

	if not rig.listed then
		rig.listed = true
		table.insert(activeFlashes, rig)
	end
	ensureStepBound()
end

-- A short, dense puff out of the muzzle. For the end of a sustained burst, or any
-- moment a single heavy shot should leave smoke hanging.
function WeaponVfx.burstSmoke(attachment: Attachment?)
	if not attachment or not attachment.Parent then
		return
	end
	emitPuff(getMuzzleRig(attachment), 1)
end

local function stepFlashes(now: number)
	for index = #activeFlashes, 1, -1 do
		local rig = activeFlashes[index]
		if rig.flashOn then
			-- at least one rendered frame, however high the frame rate or however late
			-- in the frame the shot landed
			if rig.framesShown >= 1 and now >= rig.flashOffAt then
				for _, beam in rig.beams do
					beam.Enabled = false
				end
				rig.flashOn = false
			else
				rig.framesShown += 1
			end
		end
		if rig.lightOn and now >= rig.lightOffAt then
			rig.light.Enabled = false
			rig.lightOn = false
		end
		if not rig.flashOn and not rig.lightOn then
			rig.listed = false
			activeFlashes[index] = activeFlashes[#activeFlashes]
			activeFlashes[#activeFlashes] = nil
		end
	end
end

--------------------------------------------------------------------------------------
-- Casings
--
-- Spec: parabola plus raycast bounce, never physics parts (small fast parts tunnel
-- through floors). A casing lives in two phases:
--   view:  simulated in CAMERA space from the eject port, so it arcs out of the frame
--          while the player runs forward at 24 studs/s instead of vanishing behind;
--   world: handed off with the carrier's velocity added, then a ballistic arc with a
--          raycast per frame, up to two bounces, and it lies still on the surface.
-- Parts are pooled per caliber and moved with one BulkMoveTo per frame; only casings
-- that are live get iterated.
--------------------------------------------------------------------------------------

type CaliberProfile = {
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	-- a second part for a different-looking base (the 12ga brass head); 0 = none
	headLength: number,
	headDiameter: number,
	headColor: Color3,
	headMaterial: Enum.Material,
	-- camera-space eject velocity, studs/s: +X right, +Y up, +Z back toward the camera
	right: NumberRange,
	up: NumberRange,
	back: NumberRange,
	-- tumble about one axis, revolutions per second
	spin: NumberRange,
}

local BRASS_COLOR = Color3.fromRGB(200, 160, 70)
-- lacquered steel, the usual finish on surplus 7.62x39; swap in BRASS_COLOR for brass
local STEEL_LACQUER_COLOR = Color3.fromRGB(112, 98, 60)
local HULL_RED = Color3.fromRGB(166, 30, 26)

-- Sizes are world sizes, a bit over life size so a casing on the ground still reads.
-- Casing sizes are real dimensions in metres times these. The world is about 3.6 studs
-- per metre (1 stud = 0.28 m); the pack viewmodels are drawn far smaller (an AK is
-- ~1.03 studs long, about 1.17 studs per metre, measured 2026-09-29), so a world-size
-- casing next to the eject port looked bigger than the gun. Both get a mild boost so a
-- 19 mm case still reads.
local CASING_WORLD_STUDS_PER_METRE = 3.57 * 1.3
local CASING_VIEW_STUDS_PER_METRE = 1.17 * 1.25

local CALIBERS: { [string]: CaliberProfile } = {
	["9mm"] = {
		length = 0.019 * CASING_WORLD_STUDS_PER_METRE,
		diameter = 0.0098 * CASING_WORLD_STUDS_PER_METRE,
		color = BRASS_COLOR,
		material = Enum.Material.Metal,
		headLength = 0,
		headDiameter = 0,
		headColor = BRASS_COLOR,
		headMaterial = Enum.Material.Metal,
		right = NumberRange.new(3, 4),
		up = NumberRange.new(1.8, 2.6),
		back = NumberRange.new(-0.8, -0.2),
		spin = NumberRange.new(18, 30),
	},
	-- AK: thrown harder and a touch forward rather than back at the shooter
	["762x39"] = {
		length = 0.039 * CASING_WORLD_STUDS_PER_METRE,
		diameter = 0.0113 * CASING_WORLD_STUDS_PER_METRE,
		color = STEEL_LACQUER_COLOR,
		material = Enum.Material.Metal,
		headLength = 0,
		headDiameter = 0,
		headColor = STEEL_LACQUER_COLOR,
		headMaterial = Enum.Material.Metal,
		right = NumberRange.new(3.5, 4.5),
		up = NumberRange.new(1.6, 2.4),
		back = NumberRange.new(-1.1, -0.5),
		spin = NumberRange.new(15, 24),
	},
	-- a pumped hull is heavier and flipped out by hand, so it goes slower and lazier
	["12ga"] = {
		length = 0.058 * CASING_WORLD_STUDS_PER_METRE,
		diameter = 0.0205 * CASING_WORLD_STUDS_PER_METRE,
		color = HULL_RED,
		material = Enum.Material.SmoothPlastic,
		headLength = 0.012 * CASING_WORLD_STUDS_PER_METRE,
		headDiameter = 0.0222 * CASING_WORLD_STUDS_PER_METRE,
		headColor = BRASS_COLOR,
		headMaterial = Enum.Material.Metal,
		right = NumberRange.new(2.6, 3.4),
		up = NumberRange.new(1.4, 2),
		back = NumberRange.new(-0.6, -0.1),
		spin = NumberRange.new(12, 18),
	},
}
local DEFAULT_CALIBER = "9mm"

local CASING_POOL_SIZE = 30 -- per caliber
local CASING_MAX_ACTIVE = 40 -- across calibers; the oldest is recycled past this
local CASING_LIFETIME = 3
local CASING_FADE_TIME = 0.25
local CASING_MAX_DISTANCE = 120
local CASING_VIEW_TIME = NumberRange.new(0.25, 0.35)
-- world-down, re-expressed in camera space each frame
local CASING_VIEW_GRAVITY = 18
-- Workspace.Gravity is ~5.6x real at 28 cm per stud; half of it lands the casing
-- about 0.55-0.65 s after the shot, where the spec puts the drop sound
local CASING_WORLD_GRAVITY_SCALE = 0.5
local CASING_RESTITUTION = 0.3
-- fraction of the along-surface speed kept per bounce, so a casing thrown forward at
-- run speed skids a couple of studs and falls behind rather than racing the player
local CASING_FRICTION = 0.45
local CASING_BOUNCE_SCATTER = 1.5 -- studs/s of random sideways kick per bounce
local CASING_MAX_BOUNCES = 2
-- a rebound slower than this settles on the spot instead of micro-hopping
local CASING_REST_SPEED = 1.5
-- hits slower than this into the surface are not reported (inaudible anyway)
local CASING_MIN_REPORT_SPEED = 1
local CASING_SPIN_KEEP = 0.5 -- spin kept per bounce
local CASING_WOBBLE = NumberRange.new(2, 5) -- rev/s about the long axis
local CASING_SURFACE_EPSILON = 0.01
-- The eject port sits about 0.6 studs from the eye, inside a viewmodel drawn at well
-- under world scale, so a world-size casing there would cover a good part of the
-- screen. It is drawn at this fraction while in view and snaps to world size at the
-- handoff, by which point it has always left the frame to the right. 1 disables it.
local CASING_VIEW_SCALE = CASING_VIEW_STUDS_PER_METRE / CASING_WORLD_STUDS_PER_METRE
-- used when the rig's Eject attachment is somewhere nonsensical (missing mesh anchor)
local CASING_DEFAULT_PORT = Vector3.new(0.27, -0.14, -0.58)
local CASING_MAX_PORT_DISTANCE = 4

local STATE_IDLE = 0
local STATE_VIEW = 1
local STATE_WORLD = 2
local STATE_REST = 3

type Casing = {
	caliber: string,
	body: BasePart,
	head: BasePart?,
	bodySize: Vector3,
	headSize: Vector3,
	-- head centre offset along -X (the base end), at scale 1
	headShift: number,
	radius: number,
	scale: number,
	state: number,
	-- index in activeCasings, 0 when idle
	slot: number,
	age: number,
	viewTime: number,
	lifetime: number,
	carrier: Vector3,
	localPos: Vector3,
	localVel: Vector3,
	pos: Vector3,
	vel: Vector3,
	-- rotation only; camera-relative in the view phase, world afterwards
	rot: CFrame,
	-- body-local unit axis
	spinAxis: Vector3,
	-- radians per second
	spinRate: number,
	wobbleRate: number,
	hits: number,
}

type LandedCallback = (position: Vector3, material: Enum.Material, caliber: string, impactSpeed: number) -> ()

local casingFolder: Folder? = nil
local casingPools: { [string]: { Casing } } = {}
local casingCursor: { [string]: number } = {}
local activeCasings: { Casing } = {}
local landedCallbacks: { LandedCallback } = {}

-- reused every frame so the step allocates nothing
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local casingRayParams = RaycastParams.new()
casingRayParams.FilterType = Enum.RaycastFilterType.Exclude
-- invisible trigger and acoustic volumes are non-collidable; casings fall through them
casingRayParams.RespectCanCollide = true
casingRayParams.IgnoreWater = false
local filteredCharacter: Model? = nil
local filteredCamera: Camera? = nil
local filteredFolder: Folder? = nil

local function getCasingFolder(): Folder
	local folder = casingFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Casings"
	created.Parent = getFolder()
	casingFolder = created
	return created
end

local function makeCasingPart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	-- a cylinder Part's axis is X, so Size.X is the length
	part.Shape = Enum.PartType.Cylinder
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function setCasingTransparency(casing: Casing, value: number)
	casing.body.Transparency = value
	local head = casing.head
	if head then
		head.Transparency = value
	end
end

local function setCasingScale(casing: Casing, scale: number)
	if casing.scale == scale then
		return
	end
	casing.scale = scale
	casing.body.Size = casing.bodySize * scale
	local head = casing.head
	if head then
		head.Size = casing.headSize * scale
	end
end

local function headOffset(casing: Casing): CFrame
	return CFrame.new(-casing.headShift * casing.scale, 0, 0)
end

local function queueCasing(casing: Casing, cframe: CFrame)
	table.insert(moveParts, casing.body)
	table.insert(moveCFrames, cframe)
	local head = casing.head
	if head then
		table.insert(moveParts, head)
		table.insert(moveCFrames, cframe * headOffset(casing))
	end
end

local function releaseCasing(casing: Casing)
	local slot = casing.slot
	if slot > 0 then
		-- swap-remove; the step walks the list backwards so the moved one is already done
		local count = #activeCasings
		local last = activeCasings[count]
		activeCasings[slot] = last
		last.slot = slot
		activeCasings[count] = nil
		casing.slot = 0
	end
	casing.state = STATE_IDLE
	setCasingTransparency(casing, 1)
end

local function activateCasing(casing: Casing)
	if #activeCasings >= CASING_MAX_ACTIVE then
		local oldest: Casing? = nil
		local oldestAge = -1
		for _, other in activeCasings do
			if other.age > oldestAge then
				oldest = other
				oldestAge = other.age
			end
		end
		if oldest then
			releaseCasing(oldest)
		end
	end
	table.insert(activeCasings, casing)
	casing.slot = #activeCasings
end

local function ensureCasingPool(caliber: string): { Casing }
	local pool = casingPools[caliber]
	if pool and pool[1] and pool[1].body.Parent ~= nil then
		return pool
	end
	-- the folder was destroyed under us; forget whatever was flying
	if pool then
		for _, casing in pool do
			if casing.slot > 0 then
				releaseCasing(casing)
			end
		end
	end

	local profile = CALIBERS[caliber]
	local folder = getCasingFolder()
	local bodySize = Vector3.new(profile.length, profile.diameter, profile.diameter)
	local hasHead = profile.headLength > 0
	local headSize = Vector3.new(profile.headLength, profile.headDiameter, profile.headDiameter)
	-- the head's end cap sits a hair past the hull's so the two discs do not z-fight
	local headShift = if hasHead then (profile.length - profile.headLength) / 2 + 0.004 else 0
	local radius = math.max(profile.diameter, if hasHead then profile.headDiameter else 0) / 2

	local created: { Casing } = {}
	for _ = 1, CASING_POOL_SIZE do
		local body = makeCasingPart("Casing_" .. caliber, bodySize, profile.color, profile.material, folder)
		local head = if hasHead
			then makeCasingPart("CasingHead_" .. caliber, headSize, profile.headColor, profile.headMaterial, folder)
			else nil
		table.insert(created, {
			caliber = caliber,
			body = body,
			head = head,
			bodySize = bodySize,
			headSize = headSize,
			headShift = headShift,
			radius = radius,
			scale = 1,
			state = STATE_IDLE,
			slot = 0,
			age = 0,
			viewTime = 0,
			lifetime = CASING_LIFETIME,
			carrier = Vector3.zero,
			localPos = Vector3.zero,
			localVel = Vector3.zero,
			pos = Vector3.zero,
			vel = Vector3.zero,
			rot = CFrame.identity,
			spinAxis = Vector3.yAxis,
			spinRate = 0,
			wobbleRate = 0,
			hits = 0,
		})
	end
	casingPools[caliber] = created
	casingCursor[caliber] = 0
	return created
end

local function refreshCasingFilter(camera: Camera)
	local character = localPlayer.Character
	local folder = vfxFolder
	if character == filteredCharacter and camera == filteredCamera and folder == filteredFolder then
		return
	end
	filteredCharacter = character
	filteredCamera = camera
	filteredFolder = folder
	-- the camera holds the viewmodel; the folder holds every other effect part
	local list: { Instance } = { camera }
	if folder then
		table.insert(list, folder)
	end
	if character then
		table.insert(list, character)
	end
	casingRayParams.FilterDescendantsInstances = list
end

local function reportLanding(position: Vector3, material: Enum.Material, caliber: string, speed: number)
	-- deferred so a listener that errors or yields cannot stall the render step
	for _, callback in landedCallbacks do
		task.defer(callback, position, material, caliber, speed)
	end
end

local function spin(casing: Casing, dt: number): CFrame
	return casing.rot * CFrame.fromAxisAngle(casing.spinAxis, casing.spinRate * dt) * CFrame.Angles(casing.wobbleRate * dt, 0, 0)
end

local function randomTangent(normal: Vector3): Vector3
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	local along = v - normal * v:Dot(normal)
	return if along.Magnitude > 1e-3 then along.Unit else Vector3.zero
end

local function isStatic(part: BasePart): boolean
	if part.Anchored then
		return true
	end
	local root = part.AssemblyRootPart
	return root ~= nil and root.Anchored
end

local function settleCasing(casing: Casing, result: RaycastResult)
	local hit = result.Instance
	-- Lying on something that moves (a zombie, a loose prop) would leave it floating
	-- once that thing walks off, so it just goes.
	local static = hit:IsA("BasePart") and isStatic(hit)
	if not static then
		releaseCasing(casing)
		return
	end
	local normal = result.Normal
	-- keep the heading it tumbled into, laid flat: long axis in the surface plane
	local axis = casing.rot.XVector
	local along = axis - normal * axis:Dot(normal)
	if along.Magnitude < 1e-3 then
		along = normal:Cross(if math.abs(normal.X) < 0.9 then Vector3.xAxis else Vector3.zAxis)
	end
	casing.rot = CFrame.fromMatrix(Vector3.zero, along.Unit, normal)
	casing.pos = result.Position + normal * casing.radius * casing.scale
	casing.vel = Vector3.zero
	casing.state = STATE_REST
end

local function onCasingHit(casing: Casing, result: RaycastResult, velocity: Vector3)
	local normal = result.Normal
	-- the speed INTO the surface: what makes the ting loud, whatever the skid speed
	local inward = -velocity:Dot(normal)
	casing.hits += 1
	if casing.hits <= CASING_MAX_BOUNCES and inward >= CASING_MIN_REPORT_SPEED then
		reportLanding(result.Position, result.Material, casing.caliber, inward)
	end
	if result.Material == Enum.Material.Water then
		-- report the plop, then it sinks
		releaseCasing(casing)
		return
	end

	local rebound = inward * CASING_RESTITUTION
	if casing.hits > CASING_MAX_BOUNCES or rebound < CASING_REST_SPEED then
		settleCasing(casing, result)
		return
	end

	local tangent = (velocity + normal * inward) * CASING_FRICTION
	local scatter = randomTangent(normal) * CASING_BOUNCE_SCATTER * math.random()
	casing.vel = tangent + scatter + normal * rebound
	casing.pos = result.Position + normal * (casing.radius * casing.scale + CASING_SURFACE_EPSILON)
	casing.spinRate *= CASING_SPIN_KEEP
	-- a bounce knocks the tumble off its clean axis
	local jittered = casing.spinAxis + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	if jittered.Magnitude > 1e-3 then
		casing.spinAxis = jittered.Unit
	end
end

local function stepCasings(dt: number, camera: Camera)
	local cameraCFrame = camera.CFrame
	local cameraPosition = cameraCFrame.Position
	local viewGravity = cameraCFrame:VectorToObjectSpace(Vector3.new(0, -CASING_VIEW_GRAVITY, 0))
	local worldGravity = Vector3.new(0, -Workspace.Gravity * CASING_WORLD_GRAVITY_SCALE, 0)
	refreshCasingFilter(camera)
	table.clear(moveParts)
	table.clear(moveCFrames)

	for index = #activeCasings, 1, -1 do
		local casing = activeCasings[index]
		casing.age += dt
		if casing.age >= casing.lifetime then
			releaseCasing(casing)
			continue
		end

		if casing.state == STATE_VIEW then
			casing.localVel += viewGravity * dt
			casing.localPos += casing.localVel * dt
			casing.rot = spin(casing, dt)
			if casing.age < casing.viewTime then
				queueCasing(casing, cameraCFrame * CFrame.new(casing.localPos) * casing.rot)
				continue
			end
			-- Handoff: same world point, and the velocity it really has there, which is
			-- the carrier's (the running player) plus the eject throw.
			local worldCFrame = cameraCFrame * CFrame.new(casing.localPos) * casing.rot
			casing.pos = worldCFrame.Position
			casing.vel = casing.carrier + cameraCFrame:VectorToWorldSpace(casing.localVel)
			casing.rot = worldCFrame.Rotation:Orthonormalize()
			casing.state = STATE_WORLD
			setCasingScale(casing, 1)
			queueCasing(casing, CFrame.new(casing.pos) * casing.rot)
			continue
		end

		if (casing.pos - cameraPosition).Magnitude > CASING_MAX_DISTANCE then
			releaseCasing(casing)
			continue
		end

		if casing.state == STATE_WORLD then
			local velocity = casing.vel + worldGravity * dt
			local travel = velocity * dt
			local result = if travel.Magnitude > 1e-4 then Workspace:Raycast(casing.pos, travel, casingRayParams) else nil
			if result and -velocity:Dot(result.Normal) > 0 then
				onCasingHit(casing, result, velocity)
			else
				casing.pos += travel
				casing.vel = velocity
				casing.rot = spin(casing, dt)
			end
			if casing.state == STATE_IDLE then
				continue
			end
			-- a casing that just settled is placed here once and then left alone
			queueCasing(casing, CFrame.new(casing.pos) * casing.rot)
		end

		local remaining = casing.lifetime - casing.age
		if remaining < CASING_FADE_TIME then
			setCasingTransparency(casing, 1 - remaining / CASING_FADE_TIME)
		end
	end

	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Spawns one casing at the eject port. `carrierVelocity` is the velocity of whatever
-- carries the gun (normally the HumanoidRootPart's), added at the world handoff so a
-- casing leaves with the runner's momentum instead of stopping dead in the air.
-- Unknown calibers fall back to 9mm. Pump shotguns should call this on the pump.
function WeaponVfx.ejectCasing(attachment: Attachment?, caliber: string, carrierVelocity: Vector3)
	if not attachment or not attachment:IsDescendantOf(Workspace) then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local key = if CALIBERS[caliber] then caliber else DEFAULT_CALIBER
	local profile = CALIBERS[key]
	local pool = ensureCasingPool(key)
	local cursor = (casingCursor[key] or 0) % #pool + 1
	casingCursor[key] = cursor
	local casing = pool[cursor]
	if casing.slot > 0 then
		releaseCasing(casing)
	end

	local cameraCFrame = camera.CFrame
	local localPos = cameraCFrame:PointToObjectSpace(attachment.WorldPosition)
	if localPos.Magnitude > CASING_MAX_PORT_DISTANCE or localPos.Z > 0 then
		localPos = CASING_DEFAULT_PORT
	end

	casing.state = STATE_VIEW
	casing.age = 0
	casing.hits = 0
	casing.viewTime = rollRange(CASING_VIEW_TIME)
	casing.lifetime = CASING_LIFETIME * (0.9 + math.random() * 0.2)
	casing.carrier = if typeof(carrierVelocity) == "Vector3" then carrierVelocity else Vector3.zero
	casing.localPos = localPos
	casing.localVel = Vector3.new(rollRange(profile.right), rollRange(profile.up), rollRange(profile.back))
	-- Long axis (X) along the barrel, nose forward. The tumble is mostly about the
	-- body's Y, which starts as camera up, so it cartwheels flat like a real ejection.
	-- Negative spin swings the nose out to the right first, pivoting on the extractor.
	casing.rot = CFrame.Angles(0, math.pi / 2 + (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.6)
	local tilt = (math.random() - 0.5) * 0.8
	casing.spinAxis = Vector3.new(0, math.cos(tilt), math.sin(tilt))
	casing.spinRate = -rollRange(profile.spin) * TAU
	casing.wobbleRate = rollRange(CASING_WOBBLE) * TAU * (if math.random() < 0.5 then -1 else 1)

	setCasingScale(casing, CASING_VIEW_SCALE)
	-- placed now as well as in the step, so it can never render one frame at wherever
	-- this pool slot last lay
	local cframe = cameraCFrame * CFrame.new(localPos) * casing.rot
	casing.body.CFrame = cframe
	local head = casing.head
	if head then
		head.CFrame = cframe * headOffset(casing)
	end
	setCasingTransparency(casing, 0)

	activateCasing(casing)
	ensureStepBound()
end

-- Fires on each of a casing's first two impacts with the surface's material and the
-- speed into the surface in studs/s (typically 25-35 for the drop, 6-10 for the
-- bounce). Meant for the drop sound: brass ting, dull wood, silent grass, hull thunk.
-- Returns a function that removes the listener.
function WeaponVfx.onCasingLanded(callback: LandedCallback): () -> ()
	table.insert(landedCallbacks, callback)
	return function()
		local index = table.find(landedCallbacks, callback)
		if index then
			table.remove(landedCallbacks, index)
		end
	end
end

-- Older entry point: a 9mm casing with no carrier velocity.
function WeaponVfx.shellEject(attachment: Attachment?)
	WeaponVfx.ejectCasing(attachment, DEFAULT_CALIBER, Vector3.zero)
end

function WeaponVfx.shellLandMaterial(position: Vector3): Enum.Material
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local folder = vfxFolder
	params.FilterDescendantsInstances = if folder then { folder } else {}
	local result = Workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return if result then result.Material else Enum.Material.Concrete
end

onRenderStep = function(deltaTime: number)
	if #activeFlashes > 0 then
		stepFlashes(os.clock())
	end
	if #activeCasings > 0 then
		local camera = Workspace.CurrentCamera
		if camera then
			-- the viewmodel's QA knob slows casings too, so a throw can be screenshotted
			local timeScale = camera:GetAttribute("ViewmodelTimeScale")
			local scaled = if typeof(timeScale) == "number" then deltaTime * math.max(timeScale, 0) else deltaTime
			stepCasings(math.min(scaled, MAX_STEP), camera)
		end
	end
end

--------------------------------------------------------------------------------------
-- Tracers, smoke, pickups, impacts
--------------------------------------------------------------------------------------

function WeaponVfx.tracer(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 4 then
		return
	end
	local beam = makeGhostPart("Tracer", Vector3.new(0.05, 0.05, distance), CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2))
	beam.Color = TRACER_COLOR
	beam.Transparency = 0.25
	task.delay(0.045, function()
		beam:Destroy()
	end)
end

-- The lazy wisp rising off a hot barrel after a burst. It uses the muzzle's pooled
-- emitter and is locked to the gun: world-space smoke streaks past the camera at run
-- speed instead of hanging off the barrel.
function WeaponVfx.barrelSmoke(attachment: Attachment?)
	if not attachment or not attachment.Parent then
		return
	end
	getMuzzleRig(attachment).trail:Emit(math.max(3, math.floor(10 * VfxConfig.DENSITY)))
end

function WeaponVfx.pickupBurst(position: Vector3)
	local anchor = makeGhostPart("PickupBurst", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position))
	anchor.Transparency = 1

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.fromRGB(140, 255, 170))
	sparkle.Size = NumberSequence.new(0.6, 0.05)
	sparkle.Transparency = NumberSequence.new(0.1, 1)
	sparkle.Lifetime = NumberRange.new(0.4, 0.8)
	sparkle.Speed = NumberRange.new(8, 16)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 0
	sparkle.LightEmission = 1
	sparkle.LightInfluence = 0
	sparkle.Parent = attachment
	sparkle:Emit(math.max(6, math.floor(18 * VfxConfig.DENSITY)))

	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

function WeaponVfx.impact(position: Vector3, normal: Vector3, materialName: string)
	local anchor = makeGhostPart("Impact", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(position, position + normal))
	anchor.Transparency = 1

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local isFlesh = materialName == "Flesh"
	local puff = Instance.new("ParticleEmitter")
	puff.Color = if isFlesh
		then ColorSequence.new(Color3.fromRGB(120, 26, 22))
		else ColorSequence.new(Color3.fromRGB(140, 128, 110))
	puff.Size = NumberSequence.new(0.3, 1.1)
	puff.Transparency = NumberSequence.new(0.25, 1)
	puff.Lifetime = NumberRange.new(0.25, 0.5)
	puff.Speed = NumberRange.new(3, 8)
	puff.SpreadAngle = Vector2.new(40, 40)
	puff.Rate = 0
	puff.LightInfluence = 0.6
	puff.Parent = attachment
	puff:Emit(math.max(2, math.floor(8 * VfxConfig.DENSITY)))

	if not isFlesh then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 208, 130))
		sparks.Size = NumberSequence.new(0.12, 0.02)
		sparks.Transparency = NumberSequence.new(0, 1)
		sparks.Lifetime = NumberRange.new(0.12, 0.3)
		sparks.Speed = NumberRange.new(10, 20)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.Rate = 0
		sparks.LightEmission = 1
		sparks.LightInfluence = 0
		sparks.Parent = attachment
		sparks:Emit(math.max(1, math.floor(4 * VfxConfig.DENSITY)))
	end

	task.delay(0.8, function()
		anchor:Destroy()
	end)
end

return WeaponVfx
