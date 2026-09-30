--!strict

-- Studio test yard, client side: the third-person body gallery. A row of mannequins per
-- weapon class (clones of the local character with the class's WorldWeapon built on),
-- one column per station: idle, walk, run, strafe, sprint, aim sweep, fire burst,
-- tactical reload, empty reload, shells and equip. Each station drives its BodyRig with
-- scripted inputs on a loop, so the hold, the aim spread, the recoil and every gesture
-- can be judged by eye at the class's real WeaponsConfig timings. Placed relative to the
-- SandboxOrigin attribute in the free strip east of the zombie gallery.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local ThirdPersonConfig = require(ReplicatedStorage.Shared.config.ThirdPersonConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local WorldWeaponModel = require(ReplicatedStorage.Shared.util.WorldWeaponModel)
local BodyRig = require(script.Parent.Parent.body.BodyRig)

local SandboxBodyGallery = {}

type StationSpec = {
	title: string,
	-- run clip speed (0 for none) and the reported body speed
	clip: number,
	speed: number,
	-- seconds of one loop; the driver runs on `phase` inside it
	loop: number,
}

type Station = {
	spec: StationSpec,
	class: string,
	config: WeaponsConfig.WeaponConfig,
	model: Model,
	rig: BodyRig.BodyRig,
	label: TextLabel,
	index: number,
	phase: number,
	fired: number,
	started: boolean,
	pending: number,
	track: AnimationTrack?,
	-- updates since the label was last written
	labelAge: number,
}

-- clear ground south of the props at real size (the first spot, z -170, stood among them)
local ORIGIN_OFFSET = Vector3.new(80, 0, -300)
local COLUMN_SPACING = 9
local ROW_SPACING = 14
local LABEL_RANGE = 60
local BURST_SHOTS = 8
local SWEEP_PERIOD = 4
local SWEEP_DEGREES = 60
local STRAFE_YAW = 30
local SHELLS = 4
local CLASS_ORDER = { "Pistol", "SMG", "Rifle", "Shotgun" }

local STATIONS: { StationSpec } = {
	{ title = "idle", clip = 0, speed = 0, loop = 1 },
	{ title = "walk", clip = 0.6, speed = 12, loop = 1 },
	{ title = "run", clip = 1, speed = 24, loop = 1 },
	{ title = "strafe", clip = 1, speed = 24, loop = 1 },
	{ title = "sprint", clip = 1.3, speed = 40, loop = 1 },
	{ title = "aim sweep", clip = 0, speed = 0, loop = SWEEP_PERIOD },
	{ title = "fire burst", clip = 0, speed = 0, loop = 4 },
	{ title = "tactical reload", clip = 0, speed = 0, loop = 0 },
	{ title = "empty reload", clip = 0, speed = 0, loop = 0 },
	{ title = "shells", clip = 0, speed = 0, loop = 0 },
	{ title = "equip", clip = 0, speed = 0, loop = 0 },
}

local stations: { Station } = {}
local frame = 0
local built = false
local lod = ThirdPersonConfig.lod.desktop
local bands: BodyMath.LodBands = { full = lod.full, half = lod.half, quarter = lod.quarter, ikRange = lod.ikRange }

local function makeLabel(parent: BasePart, text: string): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = LABEL_RANGE
	gui.AlwaysOnTop = true
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(230, 230, 220)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	return label
end

-- A copy of the local character stood on `cframe`: root anchored, scripts and the
-- server's gun removed, name hidden, the class's gun built on. The copy also drops the
-- local character's IKControls (FootPlanting's foot chains, and the body layer's own
-- when V was on): with their targets left on the real character, and no animator track
-- rewriting the joints each frame, they bent the mannequins over at the hips.
local function makeMannequin(template: Model, config: WeaponsConfig.WeaponConfig, cframe: CFrame, name: string): Model?
	local wasArchivable = template.Archivable
	template.Archivable = true
	local model = template:Clone()
	template.Archivable = wasArchivable
	model.Name = name
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ForceField")
			or descendant:IsA("IKControl")
			or (descendant:IsA("Attachment") and (descendant.Name == "BodyGripTarget" or descendant.Name == "BodySupportTarget"))
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.LocalTransparencyModifier = 0
		end
	end
	local existing = model:FindFirstChild(WorldWeaponModel.NAME)
	if existing then
		existing:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	-- a posed prop: no falling-down or getting-up states on an anchored root
	humanoid.EvaluateStateMachine = false
	model:PivotTo(cframe)
	root.Anchored = true
	model.Parent = Workspace
	WorldWeaponModel.build(model, config)
	return model
end

local function playRunClip(model: Model, speed: number): AnimationTrack?
	if speed <= 0 or AssetIds.animation.player.run <= 0 then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = "Run"
	animation.AnimationId = "rbxassetid://" .. tostring(AssetIds.animation.player.run)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	track:Play(0.1)
	track:AdjustSpeed(speed)
	return track
end

local function buildStation(parent: Instance, template: Model, class: string, config: WeaponsConfig.WeaponConfig, spec: StationSpec, cframe: CFrame)
	local model = makeMannequin(template, config, cframe, class .. "_" .. spec.title)
	if not model then
		return
	end
	model.Parent = parent
	local rig = BodyRig.new(model)
	if not rig then
		model:Destroy()
		return
	end
	local weapon = model:FindFirstChild(WorldWeaponModel.NAME)
	rig:setWeapon(if weapon and weapon:IsA("Model") then weapon else nil, config)
	rig:setSmoothing(ThirdPersonConfig.AIM.localSmoothing)
	local head = model:FindFirstChild("Head")
	local label = makeLabel(if head and head:IsA("BasePart") then head else (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) :: BasePart, spec.title)
	local station: Station = {
		spec = spec,
		class = class,
		config = config,
		model = model,
		rig = rig,
		label = label,
		index = #stations + 1,
		phase = 0,
		fired = 0,
		started = false,
		pending = 0,
		track = playRunClip(model, spec.clip),
		labelAge = 0,
	}
	table.insert(stations, station)
end

-- Seconds of one loop of a gesture station at this class's timings, plus a rest.
local function gestureLoop(station: Station): number
	local title = station.spec.title
	local config = station.config
	local class = ThirdPersonConfig.getClass(station.class)
	if title == "tactical reload" then
		return config.reloadTime + 1.5
	elseif title == "empty reload" then
		return config.reloadTimeEmpty + (if class then class.chargeTime else 0) + 1.5
	elseif title == "shells" then
		local shell = config.shellReload
		return (if shell then WeaponsConfig.shellReloadTime(config, SHELLS, true, 1) else 0) + 1.5
	elseif title == "equip" then
		return config.drawTime + 1.5
	end
	return station.spec.loop
end

-- The scripted input of one station for this update.
local function drive(station: Station, deltaTime: number)
	local title = station.spec.title
	local rig = station.rig
	local loop = gestureLoop(station)
	station.phase += deltaTime
	local wrapped = false
	if loop > 0 and station.phase >= loop then
		station.phase -= loop
		wrapped = true
	end
	rig:setSpeed(station.spec.speed)

	if title == "strafe" then
		rig:setAim(0, STRAFE_YAW * math.sin(station.phase * math.pi * 2 / 3))
	elseif title == "aim sweep" then
		rig:setAim(SWEEP_DEGREES * math.sin(station.phase * math.pi * 2 / SWEEP_PERIOD), 0)
	elseif title == "fire burst" then
		rig:setAim(0, 0)
		if wrapped then
			station.fired = 0
		end
		local interval = 1 / station.config.fireRate
		if station.fired < BURST_SHOTS and station.phase >= station.fired * interval then
			station.fired += 1
			rig:fire()
		end
	elseif title == "tactical reload" or title == "empty reload" or title == "shells" then
		rig:setAim(0, 0)
		if title == "shells" and station.config.reloadStyle ~= "shell" then
			return
		end
		if wrapped or not station.started then
			station.started = true
			local empty = title ~= "tactical reload"
			rig:startReload(empty, if title == "shells" then SHELLS else 0, 1)
		end
	elseif title == "equip" then
		rig:setAim(0, 0)
		if wrapped or not station.started then
			station.started = true
			rig:equip()
		end
	else
		rig:setAim(0, 0)
	end
end

local function updateLabel(station: Station)
	local title = station.spec.title
	if title == "shells" and station.config.reloadStyle ~= "shell" then
		station.label.Text = string.format("%s  shells\nn/a", station.class)
		return
	end
	station.label.Text = string.format("%s  %s\n%s", station.class, title, station.rig:describe())
end

local function step(deltaTime: number)
	if not built then
		return
	end
	frame += 1
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local updated = 0
	local count = #stations
	-- start the round at a different station each frame: with every station in full
	-- cadence the per-frame cap would otherwise starve the same last rows every frame
	for offset = 1, count do
		local station = stations[(frame + offset) % count + 1]
		station.pending += deltaTime
		local pivot = station.model:GetPivot().Position
		local cadence, ikOn = BodyMath.lodBand((pivot - eye).Magnitude, bands)
		station.rig:setIkAllowed(ikOn)
		if not BodyMath.updatesThisFrame(frame, station.index, cadence) or updated >= lod.maxPerFrame * 4 then
			continue
		end
		drive(station, station.pending)
		station.rig:update(station.pending)
		station.pending = 0
		updated += 1
		-- per station, not per frame: with the round robin a station and a frame
		-- multiple rarely met, and the labels froze for seconds
		station.labelAge += 1
		if station.labelAge >= 4 then
			station.labelAge = 0
			updateLabel(station)
		end
	end
end

local function build(origin: Vector3, template: Model)
	if built then
		return
	end
	built = true
	local folder = Instance.new("Folder")
	folder.Name = "SandboxBodyGallery"
	folder.Parent = Workspace
	local base = origin + ORIGIN_OFFSET
	for row, class in CLASS_ORDER do
		local config = WeaponsConfig.get(class)
		if not config then
			continue
		end
		local z = base.Z - (row - 1) * ROW_SPACING
		for column, spec in STATIONS do
			local x = base.X + (column - 1) * COLUMN_SPACING
			-- the mannequins face +z, so the walkway along the south side sees them head on
			local cframe = CFrame.new(x, base.Y + 3, z) * CFrame.Angles(0, math.rad(180), 0)
			buildStation(folder, template, class, config, spec, cframe)
		end
	end
end

function SandboxBodyGallery.init()
	if not RunService:IsStudio() or not DevConfig.SANDBOX.enabled or not ThirdPersonConfig.ENABLED then
		return
	end
	task.spawn(function()
		while Workspace:GetAttribute("SandboxActive") ~= true do
			task.wait(0.5)
		end
		local origin = Workspace:GetAttribute("SandboxOrigin")
		local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
		character:WaitForChild("RightHand", 20)
		character:WaitForChild("LeftHand", 20)
		if typeof(origin) == "Vector3" then
			build(origin, character)
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return SandboxBodyGallery
