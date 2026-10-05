--!strict

-- The helicopter crash beat (docs/gameplay/heli-intermission.md, roadmap: "the pilot
-- turns, the copilot shoots him"), client only, played over the cabin the server built
-- (Workspace.IntermissionCabin: the SeatView parts, the Pilot and Copilot figures, the
-- LightStrip, the ConsoleGlow). No gore: everyone sees it and the Gore toggle does not
-- apply, so the shot is a flash, a jolt and a slump.
--
-- One 13 s timeline (seconds):
--   0.0-1.5   the seated view turns from the door to the cockpit
--   1.4-2.2   the pilot turns his head to the copilot
--   1.8-3.2   the copilot turns, raises a pistol to the pilot's head
--   3.6       the shot: muzzle flash, gunshot, camera jolt; the pilot's head snaps aside
--             and he slumps onto the console
--   4.0       the alarm and the red strobe; the helicopter starts to spin and drop
--   5.2-6.5   the view swings back to the door: the ground turns and rises outside
--   11.6      impact: white flash, the hardest shake, impact and debris
--   11.85     black; ringing in the ears until the wake-up at the wreck
-- A shorter beat (the repeat run's skippable version) plays the end of the same
-- timeline, so the impact always lands on the beat's last second.
--
-- The flight and the spin are faked: the cabin stays where the server built it and a
-- local ground (`Outside`: desert, a road, blocks of a town) slides under it during the
-- ready check, then turns and rises under it in the beat, which is the same picture
-- through the door without moving server parts the seated characters are welded to.
-- Everything the beat changes in the cabin is put back by stop().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local CabinCrew = require(script.Parent.CabinCrew)
local MusicController = require(script.Parent.MusicController)

local CrashCinematic = {}

export type Options = {
	-- server time the beat ends (the wake-up)
	endsAt: number,
	-- this player's seat (CabinSeat)
	seat: number,
	-- turns the screen black over `seconds` (the intermission camera's fade)
	blackout: ((seconds: number) -> ())?,
}

local RENDER_NAME = "TfzCrashCinematic"
-- after the intermission camera (Camera + 5), so this is the last write
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 6
local CABIN_NAME = "IntermissionCabin"

local FULL_LENGTH = 13
local T_LOOK = 1.5
local T_PILOT_TURN = 1.4
local T_COPILOT_TURN = 1.8
local T_RAISE = 2.2
local T_RAISED = 3.2
local T_SHOT = 3.6
local T_SLUMPED = 4.3
local T_ALARM = 4.0
local T_SPIN = 4.0
local T_TO_DOOR = 5.2
local T_AT_DOOR = 6.5
local T_CREAK = 6.2
local T_SPIN_FULL = 9.5
local T_IMPACT = 11.6
local T_BLACK = 11.85
local T_RING = 11.95

-- the turn of the helicopter at full spin (radians per second) and the bank it pulls
local SPIN_RATE = math.pi * 2 * 0.85
local BANK = math.rad(13)
-- the ground under the cabin when the spin starts, and at the impact
local ALTITUDE_START = 420
local ALTITUDE_END = 7
local GROUND_SIZE = 3200
local BUILDINGS = 70

local ids = (AssetIds :: any).audio
local cinematicIds = ids and ids.cinematic or {}
local weaponIds = ids and ids.weapons or {}

local random = Random.new()

type Saved = { part: BasePart, cframe: CFrame }

type State = {
	options: Options,
	cabin: Model,
	view: BasePart,
	start: number,
	offset: number,
	spinAngle: number,
	lastT: number,
	saved: { Saved },
	pilot: Model?,
	copilot: Model?,
	pilotParts: { [string]: CFrame },
	copilotParts: { [string]: CFrame },
	pilotOrigin: CFrame,
	copilotOrigin: CFrame,
	pistol: BasePart?,
	flashLight: PointLight?,
	strip: BasePart?,
	stripColor: Color3,
	cabinLight: PointLight?,
	cabinBrightness: number,
	glow: BasePart?,
	glowColor: Color3,
	sounds: { Sound },
	rotor: Sound?,
	alarm: Sound?,
	fired: { [string]: boolean },
	gui: ScreenGui,
	white: Frame,
	noiseSeed: number,
	-- the cabin floor's centre, x across to the door, -z to the cockpit
	frame: CFrame,
	fieldOfView: number,
}

local state: State? = nil
-- the rotor drone of the ready check, handed to the beat when it starts
local ambience: Sound? = nil
local AMBIENCE_VOLUME = 0.4

-- the ground outside, shared by the ready check's flight and the beat
type Outside = {
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	placed: { CFrame },
	-- the cabin floor's frame the ground hangs under
	frame: CFrame,
	-- studs flown so far (the town slides back along +z)
	flown: number,
}
local outside: Outside? = nil
local FLIGHT_SPEED = 70
local FLIGHT_NAME = "TfzCabinFlight"
local flightBound = false

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	local u = clamp01(x)
	return u * u * (3 - 2 * u)
end

-- eased 0..1 between two timeline marks
local function between(t: number, a: number, b: number): number
	return smooth((t - a) / (b - a))
end

local function makeSound(id: number?, volume: number, looped: boolean): Sound?
	if typeof(id) ~= "number" or id <= 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = volume
	sound.Looped = looped
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = SoundService
	return sound
end

local function oneShot(current: State, key: string, id: number?, volume: number)
	if current.fired[key] then
		return
	end
	current.fired[key] = true
	local sound = makeSound(id, volume, false)
	if sound then
		table.insert(current.sounds, sound)
		sound:Play()
	end
end

local function savePart(current: State, part: BasePart)
	table.insert(current.saved, { part = part, cframe = part.CFrame })
end

local function figureParts(model: Model?, current: State, into: { [string]: CFrame })
	if not model then
		return
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			into[child.Name] = child.CFrame
			savePart(current, child)
		end
	end
end

local function part(model: Model?, name: string): BasePart?
	local found = if model then model:FindFirstChild(name) else nil
	return if found and found:IsA("BasePart") then found else nil
end

-- The ground the helicopter falls toward: a desert plane and blocks of a town, built
-- locally around the cabin's floor and moved every frame.
local function buildOutside(cabinCFrame: CFrame): Outside
	local model = Instance.new("Model")
	model.Name = "CrashOutside"
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.CFrame = cabinCFrame * offset
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, offset)
	end
	add(Vector3.new(GROUND_SIZE, 2, GROUND_SIZE), CFrame.new(0, -1, 0), Color3.fromRGB(176, 152, 112), Enum.Material.Sand)
	add(Vector3.new(60, 2.2, GROUND_SIZE), CFrame.new(-140, -1, 0), Color3.fromRGB(70, 68, 66), Enum.Material.Asphalt)
	local rng = Random.new(7)
	for _ = 1, BUILDINGS do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(90, 1100)
		local width = rng:NextNumber(18, 60)
		local depth = rng:NextNumber(18, 60)
		local height = rng:NextNumber(14, 90)
		local shade = rng:NextInteger(70, 140)
		add(
			Vector3.new(width, height, depth),
			CFrame.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color3.fromRGB(shade, shade - 8, shade - 16),
			Enum.Material.Concrete
		)
	end
	model.Parent = Workspace
	return { model = model, parts = parts, offsets = offsets, placed = table.create(#parts), frame = cabinCFrame, flown = 0 }
end

-- Puts the ground under the cabin: `flown` slides the town back (each block wraps
-- round far out in the haze), `spin` turns it about the cabin, `altitude` below it.
local function placeOutside(ground: Outside, spin: number, altitude: number)
	local base = ground.frame * CFrame.Angles(0, -spin, 0) * CFrame.new(0, -altitude, 0)
	local half = GROUND_SIZE / 2
	for index, offset in ground.offsets do
		local placed = offset
		if index > 2 then
			local p = offset.Position
			local z = ((p.Z + ground.flown + half) % GROUND_SIZE) - half
			placed = CFrame.new(p.X, p.Y, z) * offset.Rotation
		end
		ground.placed[index] = base * placed
	end
	Workspace:BulkMoveTo(ground.parts, ground.placed, Enum.BulkMoveMode.FireCFrameChanged)
end

local function cabinFrame(): CFrame?
	local cabin = Workspace:FindFirstChild(CABIN_NAME)
	local floor = cabin and cabin:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	end
	return nil
end

local function ensureOutside(): Outside?
	if outside then
		return outside
	end
	local frame = cabinFrame()
	if not frame then
		return nil
	end
	outside = buildOutside(frame)
	return outside
end

local function destroyOutside()
	if flightBound then
		flightBound = false
		RunService:UnbindFromRenderStep(FLIGHT_NAME)
	end
	if outside then
		(outside :: Outside).model:Destroy()
		outside = nil
	end
end

local function altitudeAt(t: number): number
	if t <= T_SPIN then
		return ALTITUDE_START
	end
	local s = clamp01((t - T_SPIN) / (T_IMPACT - T_SPIN))
	return ALTITUDE_START + (ALTITUDE_END - ALTITUDE_START) * s ^ 2.2
end

-- spin rate ramps in from T_SPIN to T_SPIN_FULL
local function spinRateAt(t: number): number
	return SPIN_RATE * between(t, T_SPIN, T_SPIN_FULL)
end

local function noise3(current: State, t: number, frequency: number): Vector3
	local s = current.noiseSeed
	return Vector3.new(
		math.noise(t * frequency, s, 0.1),
		math.noise(t * frequency, s + 17.3, 0.7),
		math.noise(t * frequency, s + 41.9, 1.3)
	)
end

local function poseCrew(current: State, t: number)
	-- the soldier crew (CabinCrew) when it could be built; the block figures otherwise
	local crew = CabinCrew.ensure()
	if crew then
		local recoil = if t >= T_SHOT then math.exp(-(t - T_SHOT) * 14) else 0
		CabinCrew.pose(
			crew,
			between(t, T_PILOT_TURN, T_PILOT_TURN + 0.8),
			between(t, T_COPILOT_TURN, T_COPILOT_TURN + 0.6),
			between(t, T_RAISE, T_RAISED) * (1 - 0.6 * between(t, T_SHOT + 0.9, T_SHOT + 2.2)),
			recoil,
			between(t, T_SHOT, T_SHOT + 0.12),
			between(t, T_SHOT + 0.05, T_SLUMPED)
		)
		return
	end
	-- the pilot: head turns to the copilot, then the shot knocks it aside and he slumps
	local pilot = current.pilot
	if pilot then
		local origin = current.pilotOrigin
		local turn = between(t, T_PILOT_TURN, T_PILOT_TURN + 0.8) * math.rad(-70)
		local hit = between(t, T_SHOT, T_SHOT + 0.12)
		local slump = between(t, T_SHOT + 0.05, T_SLUMPED)
		local neck = origin * CFrame.new(0, 2.05, 0.1)
		local hip = origin * CFrame.new(0, 0.1, 0.3)
		local body = hip * CFrame.Angles(math.rad(-38) * slump, 0, math.rad(8) * slump) * hip:Inverse()
		local headTurn = CFrame.Angles(0, turn * (1 - hit), 0)
		local headHit = CFrame.Angles(math.rad(-25) * slump, 0, math.rad(32) * hit)
		for name, rest in current.pilotParts do
			local p = part(pilot, name)
			if p then
				if name == "Head" or name == "Helmet" or name == "Visor" then
					p.CFrame = body * neck * headHit * headTurn * neck:Inverse() * rest
				else
					p.CFrame = body * rest
				end
			end
		end
	end

	-- the copilot: head to the pilot, right arm up with the pistol at the pilot's head
	local copilot = current.copilot
	if copilot then
		local origin = current.copilotOrigin
		local look = between(t, T_COPILOT_TURN, T_COPILOT_TURN + 0.6) * math.rad(55)
		local neck = origin * CFrame.new(0, 2.05, 0.1)
		local raise = between(t, T_RAISE, T_RAISED)
		local recoil = if t >= T_SHOT then math.exp(-(t - T_SHOT) * 14) * (1 - between(t, T_SHOT + 0.6, T_SHOT + 1.6)) else 0
		for name, rest in current.copilotParts do
			local p = part(copilot, name)
			if p then
				if name == "Head" or name == "Helmet" or name == "Visor" then
					p.CFrame = neck * CFrame.Angles(0, look, 0) * neck:Inverse() * rest
				elseif name == "ArmR" then
					local shoulder = (origin * CFrame.new(0.9, 1.3, 0.2)).Position
					local target = (current.pilotOrigin * CFrame.new(0.2, 2.45, 0.1)).Position
					local aimed = CFrame.lookAt(shoulder, target) * CFrame.Angles(math.rad(14) * recoil, 0, 0) * CFrame.new(0, 0, -0.7)
					p.CFrame = rest:Lerp(aimed, raise)
					local pistol = current.pistol
					if pistol then
						pistol.CFrame = p.CFrame * CFrame.new(0, 0.12, -0.95)
						pistol.Transparency = if raise > 0.02 then 0 else 1
					end
				end
			end
		end
	end
end

local function lightCabin(current: State, t: number)
	local flash = current.flashLight
	if flash then
		local since = t - T_SHOT
		flash.Enabled = since >= 0 and since < 0.07
	end
	local strobe = t >= T_ALARM and t < T_IMPACT and (math.floor((t - T_ALARM) * 6) % 2 == 0)
	local cabinLight = current.cabinLight
	if cabinLight then
		cabinLight.Brightness = if strobe then current.cabinBrightness * 3 elseif t >= T_ALARM then current.cabinBrightness * 0.5 else current.cabinBrightness
		if t >= T_BLACK then
			cabinLight.Brightness = 0
		end
	end
	local strip = current.strip
	if strip then
		strip.Color = if strobe then Color3.fromRGB(255, 40, 30) elseif t >= T_ALARM then Color3.fromRGB(90, 16, 12) else current.stripColor
	end
	local glow = current.glow
	if glow and t >= T_SHOT then
		glow.Color = if random:NextNumber() < 0.25 then Color3.fromRGB(20, 40, 28) else current.glowColor
	end
end

local function playSounds(current: State, t: number)
	local rotor = current.rotor
	if rotor then
		local wobble = if t >= T_SPIN then math.sin(t * 9) * 0.04 * between(t, T_SPIN, T_SPIN_FULL) else 0
		rotor.PlaybackSpeed = 1 + 0.12 * between(t, T_SPIN, T_IMPACT) + wobble
		rotor.Volume = if t >= T_IMPACT then 0 else 0.55 + 0.25 * between(t, T_SPIN, T_IMPACT)
	end
	if t >= T_SHOT then
		oneShot(current, "shot", weaponIds.close_pistol, 0.9)
		oneShot(current, "shotTail", weaponIds.tail_interior, 0.6)
	end
	if t >= T_ALARM and t < T_IMPACT then
		local alarm = current.alarm
		if alarm and not alarm.IsPlaying then
			alarm:Play()
		end
	elseif current.alarm and t >= T_IMPACT then
		(current.alarm :: Sound):Stop()
	end
	if t >= T_CREAK then
		oneShot(current, "creak", cinematicIds.crash_creak, 0.7)
	end
	if t >= T_IMPACT then
		oneShot(current, "impact", cinematicIds.crash_impact, 1)
		oneShot(current, "debris", cinematicIds.crash_debris, 0.8)
	end
	if t >= T_RING then
		oneShot(current, "ring", cinematicIds.crash_ringing, 0.5)
	end
end

local function moveOutside(current: State, t: number, dt: number)
	current.spinAngle += spinRateAt(t) * dt
	local ground = outside
	if ground then
		-- forward flight fades out as the spin takes over
		ground.flown += dt * FLIGHT_SPEED * (1 - between(t, T_SPIN, T_SPIN_FULL))
		placeOutside(ground, current.spinAngle, altitudeAt(t))
	end
end

local function placeCamera(current: State, t: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local seated = current.view.CFrame
	local eye = seated.Position
	local cockpit = (current.frame * CFrame.new(0, 3.4, -11.6)).Position
	local atCockpit = CFrame.lookAt(eye, cockpit)
	local atDoor = seated * CFrame.Angles(math.rad(-14), 0, 0)
	local view = seated:Lerp(atCockpit, between(t, 0, T_LOOK))
	view = view:Lerp(atDoor, between(t, T_TO_DOOR, T_AT_DOOR))

	-- the bank of the turn, and the shake: rotor buzz always, the spin's buffeting, the
	-- shot's jolt and the impact
	local spin = spinRateAt(t) / SPIN_RATE
	local bank = BANK * spin * (1 + 0.25 * math.sin(t * 1.7))
	local buzz = 0.0025 + 0.02 * spin + 0.03 * between(t, T_SPIN_FULL, T_IMPACT)
	local jolt = if t >= T_SHOT then math.exp(-(t - T_SHOT) * 10) * 0.05 else 0
	local impact = if t >= T_IMPACT then math.exp(-(t - T_IMPACT) * 6) * 0.35 else 0
	local shake = noise3(current, t, 9) * (buzz + jolt + impact) + noise3(current, t, 31) * buzz * 0.4
	camera.CFrame = view * CFrame.Angles(shake.X, shake.Y, shake.Z + bank)
	camera.FieldOfView = current.fieldOfView + 6 * between(t, T_SPIN, T_SPIN_FULL)
end

local function flashScreen(current: State, t: number)
	local since = t - T_IMPACT
	current.white.BackgroundTransparency = if since < 0 then 1 else math.clamp(since / 0.22, 0, 1)
	if t >= T_BLACK and not current.fired.black then
		current.fired.black = true
		local blackout = current.options.blackout
		if blackout then
			blackout(0.06)
		end
	end
end

local function step(dt: number)
	local current = state
	if not current then
		return
	end
	-- debug knob for reviewing the beat slowly from the command bar (client):
	-- workspace.CurrentCamera:SetAttribute("CinematicTimeScale", 0.2)
	local camera = Workspace.CurrentCamera
	local scale = if camera then camera:GetAttribute("CinematicTimeScale") else nil
	-- or pinned to one moment: workspace.CurrentCamera:SetAttribute("CinematicAt", 3.6)
	local pinned = if camera then camera:GetAttribute("CinematicAt") else nil
	local t
	if typeof(pinned) == "number" then
		t = pinned
	elseif typeof(scale) == "number" then
		t = current.lastT + dt * math.max(scale, 0)
	else
		t = current.offset + (Workspace:GetServerTimeNow() - current.start)
	end
	local frameDt = math.max(0, t - current.lastT)
	current.lastT = t
	poseCrew(current, t)
	lightCabin(current, t)
	moveOutside(current, t, frameDt)
	placeCamera(current, t)
	playSounds(current, t)
	flashScreen(current, t)
end

-- Starts the beat; returns false when the cabin or the seat view is missing (the
-- caller keeps its plain black fade then).
function CrashCinematic.play(options: Options): boolean
	CrashCinematic.stop()
	local cabin = Workspace:FindFirstChild(CABIN_NAME)
	local view = cabin and cabin:FindFirstChild("SeatView" .. tostring(options.seat))
	if not cabin or not cabin:IsA("Model") or not view or not view:IsA("BasePart") then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local length = math.max(0.5, options.endsAt - now)
	local offset = math.max(0, FULL_LENGTH - length)

	local gui = Instance.new("ScreenGui")
	gui.Name = "CrashCinematic"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 49
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.BorderSizePixel = 0
	white.Parent = gui

	local pilot = cabin:FindFirstChild("Pilot")
	local copilot = cabin:FindFirstChild("Copilot")
	local strip = part(cabin, "LightStrip")
	local glow = part(cabin, "ConsoleGlow")
	local cabinLight = if strip then strip:FindFirstChildOfClass("PointLight") else nil
	local floorPart = part(cabin, "Floor")
	local frame = if floorPart then floorPart.CFrame * CFrame.new(0, floorPart.Size.Y / 2, 0) else cabin:GetPivot()
	ensureOutside()
	if flightBound then
		flightBound = false
		RunService:UnbindFromRenderStep(FLIGHT_NAME)
	end
	local camera = Workspace.CurrentCamera

	local current: State = {
		options = options,
		cabin = cabin,
		view = view,
		start = now,
		offset = offset,
		spinAngle = 0,
		lastT = offset,
		saved = {},
		pilot = if pilot and pilot:IsA("Model") then pilot else nil,
		copilot = if copilot and copilot:IsA("Model") then copilot else nil,
		pilotParts = {},
		copilotParts = {},
		pilotOrigin = if pilot and pilot:IsA("Model") then pilot:GetPivot() else CFrame.identity,
		copilotOrigin = if copilot and copilot:IsA("Model") then copilot:GetPivot() else CFrame.identity,
		pistol = nil,
		flashLight = nil,
		strip = strip,
		stripColor = if strip then strip.Color else Color3.new(1, 0.3, 0.2),
		cabinLight = cabinLight,
		cabinBrightness = if cabinLight then cabinLight.Brightness else 1,
		glow = glow,
		glowColor = if glow then glow.Color else Color3.new(0.3, 0.8, 0.5),
		sounds = {},
		rotor = nil,
		alarm = nil,
		fired = {},
		gui = gui,
		white = white,
		noiseSeed = random:NextNumber(0, 100),
		frame = frame,
		fieldOfView = if camera then camera.FieldOfView else 70,
	}
	figureParts(current.pilot, current, current.pilotParts)
	figureParts(current.copilot, current, current.copilotParts)
	-- a figure's pivot is its seat origin only if the server built it that way; use the
	-- torso's position as the anchor so the poses stay on the figure either way
	local pilotTorso = part(current.pilot, "Torso")
	if pilotTorso then
		current.pilotOrigin = pilotTorso.CFrame * CFrame.new(0, -1.0, -0.2)
	end
	local copilotTorso = part(current.copilot, "Torso")
	if copilotTorso then
		current.copilotOrigin = copilotTorso.CFrame * CFrame.new(0, -1.0, -0.2)
	end

	if current.copilot then
		local pistol = Instance.new("Part")
		pistol.Name = "CinematicPistol"
		pistol.Size = Vector3.new(0.22, 0.42, 0.75)
		pistol.Color = Color3.fromRGB(28, 28, 30)
		pistol.Material = Enum.Material.Metal
		pistol.Anchored = true
		pistol.CanCollide = false
		pistol.CanQuery = false
		pistol.CanTouch = false
		pistol.Transparency = 1
		pistol.Parent = current.copilot
		local muzzle = Instance.new("Attachment")
		muzzle.Position = Vector3.new(0, 0.1, -0.45)
		muzzle.Parent = pistol
		local flash = Instance.new("PointLight")
		flash.Color = Color3.fromRGB(255, 214, 160)
		flash.Brightness = 8
		flash.Range = 16
		flash.Enabled = false
		flash.Parent = muzzle
		current.pistol = pistol
		current.flashLight = flash
	end
	-- with the soldier crew the flash comes from the copilot's own pistol
	local crew = CabinCrew.ensure()
	local crewMuzzle = if crew then CabinCrew.muzzle(crew) else nil
	if crewMuzzle and current.flashLight then
		(current.flashLight :: PointLight).Parent = crewMuzzle
	end

	local rotor = ambience or makeSound(cinematicIds.crash_rotor_loop, 0.55, true)
	ambience = nil
	if rotor then
		table.insert(current.sounds, rotor)
		if not rotor.IsPlaying then
			rotor:Play()
		end
	end
	current.rotor = rotor
	local alarm = makeSound(cinematicIds.crash_alarm, 0.45, true)
	if alarm then
		table.insert(current.sounds, alarm)
	end
	current.alarm = alarm

	-- the spin already run before a late start (the short beat)
	local t = 0
	while t < offset do
		local dt = math.min(1 / 30, offset - t)
		current.spinAngle += spinRateAt(t) * dt
		t += dt
	end

	state = current
	RunService:BindToRenderStep(RENDER_NAME, RENDER_PRIORITY, step)
	step(0)
	return true
end

-- The rotor drone while the squad sits in the cabin (the ready check); the beat takes
-- it over, so the sound runs on without a seam into the crash.
function CrashCinematic.setCabinAmbience(on: boolean)
	if on then
		if state ~= nil then
			return
		end
		if ambience == nil then
			local sound = makeSound(cinematicIds.crash_rotor_loop, AMBIENCE_VOLUME, true)
			if sound then
				sound:Play()
			end
			ambience = sound
		end
		-- the two soldiers in the cockpit
		CabinCrew.ensure()
		-- the town sliding by under the open door
		if not flightBound and ensureOutside() then
			flightBound = true
			RunService:BindToRenderStep(FLIGHT_NAME, RENDER_PRIORITY - 2, function(dt: number)
				local ground = outside
				if ground then
					ground.flown += dt * FLIGHT_SPEED
					placeOutside(ground, 0, ALTITUDE_START)
				end
			end)
		end
	else
		if ambience then
			(ambience :: Sound):Destroy()
			ambience = nil
		end
		if state == nil then
			destroyOutside()
			CabinCrew.destroy()
		end
	end
end

function CrashCinematic.isPlaying(): boolean
	return state ~= nil
end

-- Ends the beat and puts the cabin back as the server built it.
function CrashCinematic.stop()
	local current = state
	if not current then
		return
	end
	state = nil
	RunService:UnbindFromRenderStep(RENDER_NAME)
	for _, saved in current.saved do
		if saved.part.Parent then
			saved.part.CFrame = saved.cframe
		end
	end
	if current.strip then
		(current.strip :: BasePart).Color = current.stripColor
	end
	if current.cabinLight then
		(current.cabinLight :: PointLight).Brightness = current.cabinBrightness
	end
	if current.glow then
		(current.glow :: BasePart).Color = current.glowColor
	end
	if current.pistol then
		(current.pistol :: BasePart):Destroy()
	end
	for _, sound in current.sounds do
		-- the ringing carries over the wake-up; everything else stops now
		if sound.Looped then
			sound:Destroy()
		else
			task.delay(12, function()
				sound:Destroy()
			end)
		end
	end
	destroyOutside()
	current.gui:Destroy()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = current.fieldOfView
	end
end

return CrashCinematic
