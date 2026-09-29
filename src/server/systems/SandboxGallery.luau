--!strict

-- Studio test yard (Sandbox): the zombie clip gallery. Every skin gets a row with one
-- standing model per clip, each looping its clip in place so it can be judged from the
-- side. Walk and run clips have their root travel removed (tools/zombie_pack), so each
-- walker stands on a strip whose texture the client scrolls at the clip's measured
-- ground speed (SandboxInput): feet that stay planted on the moving ground mean the
-- speed data, and so the in-game playback rate, is right. One-shots (attack, hit,
-- scream, deaths) hold their last frame for a moment and start again. Bullets pass
-- through the gallery (no queryable parts), so the range next to it is safe to use.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local ZombieSkins = require(ReplicatedStorage.Shared.config.ZombieSkins)
local ZombiesConfig = require(ReplicatedStorage.Shared.config.ZombiesConfig)
local ZombieFactory = require(script.Parent.ZombieFactory)

local SandboxGallery = {}

export type LabelFn = (text: string, position: Vector3, parent: Instance, maxDistance: number?) -> ()

type Station = {
	track: AnimationTrack,
	looped: boolean,
	holdUntil: number?,
}

-- clip slots in display order (AssetIds.animation.zombie_sf.<rig>.<slot>)
local SLOT_ORDER = {
	"idle",
	"idle_b",
	"walk_a",
	"walk_b",
	"run",
	"run_b",
	"attack",
	"attack_b",
	"hit",
	"spotted",
	"death_back",
	"death_forward",
}
local LOOPED: { [string]: boolean } = {
	idle = true,
	idle_b = true,
	walk_a = true,
	walk_b = true,
	run = true,
	run_b = true,
}
-- which ZombiesConfig entry builds each skin (the config only sets health and speeds)
local SKIN_CONFIG: { [string]: string } = { Walker = "Walker", Hazmat = "Walker", Ghoul = "Runner" }
local SKINS = { "Walker", "Hazmat", "Ghoul" }

local COLUMN_SPACING = 9
local ROW_SPACING = 28
local STATION_LABEL_RANGE = 24
-- a one-shot's last frame is held this long before it starts again
local HOLD = 1.2
-- one frame short of the end: a non-looped track that reaches its end stops, and the
-- rig would snap to its bind pose before the next play
local END_MARGIN = 0.06

local stations: { Station } = {}
local timeScale = 1
local stepping = false

local function configFor(id: string): ZombiesConfig.ZombieConfig?
	for _, config in ZombiesConfig do
		if config.id == id then
			return config
		end
	end
	return nil
end

local function groundSpeed(skin: ZombieSkins.Skin, id: number): number
	for _, group in { skin.walk, skin.run } do
		for _, clip in group do
			if clip.id == id then
				return clip.speed
			end
		end
	end
	return 0
end

-- Ground strip under a walking model; the client scrolls its texture along +X's
-- opposite (the model faces +X, so the ground moves toward its back).
local function treadmill(parent: Instance, position: Vector3, speed: number)
	local strip = Instance.new("Part")
	strip.Name = "Treadmill"
	strip.Anchored = true
	strip.CanQuery = false
	strip.Size = Vector3.new(8, 0.2, 3.5)
	strip.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0))
	strip.Color = Color3.fromRGB(70, 68, 64)
	strip.Material = Enum.Material.SmoothPlastic
	strip.Parent = parent
	local texture = Instance.new("Texture")
	texture.Face = Enum.NormalId.Top
	texture.Texture = "rbxassetid://" .. tostring((AssetIds.texture.surface :: any).asphalt or 0)
	texture.StudsPerTileU = 2
	texture.StudsPerTileV = 2
	texture.Parent = strip
	-- stripes make the motion easy to read at any distance
	for i = -3, 3, 2 do
		local line = Instance.new("Part")
		line.Name = "Stripe"
		line.Anchored = true
		line.CanQuery = false
		line.CanCollide = false
		line.Size = Vector3.new(0.25, 0.22, 3.5)
		line.CFrame = CFrame.new(position + Vector3.new(i, 0.12, 0))
		line.Color = Color3.fromRGB(230, 210, 120)
		line.Material = Enum.Material.SmoothPlastic
		line.Parent = strip
	end
	strip:SetAttribute("ScrollSpeed", speed)
	CollectionService:AddTag(strip, "SandboxTreadmill")
end

local function buildStation(parent: Instance, config: ZombiesConfig.ZombieConfig, skin: ZombieSkins.Skin, slot: string, id: number, ground: Vector3, label: LabelFn)
	local model = ZombieFactory.build(config, nil, skin.name)
	model.Name = skin.name .. "_" .. slot
	model:SetAttribute("SandboxGallery", true)
	local rootHeight = ZombieFactory.ROOT_HEIGHT
	model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, rootHeight, 0), ground + Vector3.new(1, rootHeight, 0)))
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	model.Parent = parent

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		label(slot .. " (failed to load)", ground + Vector3.new(0, 8, 0), parent)
		return
	end
	local looped = LOOPED[slot] == true
	track.Looped = looped
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0)
	track:AdjustSpeed(timeScale)
	table.insert(stations, { track = track, looped = looped, holdUntil = nil })

	local speed = groundSpeed(skin, id)
	local text = slot
	if speed > 0 then
		text ..= string.format("  %.2f st/s", speed)
		treadmill(parent, ground, speed)
	end
	-- short range: from in front of one row the labels of the rows behind stay hidden
	label(text, ground + Vector3.new(0, 7.5, 0), parent, STATION_LABEL_RANGE)
end

-- Holds each one-shot on its last frame for HOLD seconds, then restarts it.
local function step()
	local now = os.clock()
	for _, station in stations do
		local track = station.track
		if station.looped or not track.IsPlaying then
			if not station.looped and not track.IsPlaying then
				track:Play(0.1)
				track:AdjustSpeed(timeScale)
			end
			continue
		end
		local holdUntil = station.holdUntil
		if holdUntil then
			if now >= holdUntil then
				station.holdUntil = nil
				track.TimePosition = 0
				track:AdjustSpeed(timeScale)
			end
		elseif track.Length > 0 and track.TimePosition >= track.Length - END_MARGIN * math.max(timeScale, 0.05) then
			track:AdjustSpeed(0)
			station.holdUntil = now + HOLD
		end
	end
end

function SandboxGallery.build(parent: Instance, origin: Vector3, label: LabelFn)
	local rigs = (AssetIds.animation :: any).zombie_sf or {}
	for row, skinName in SKINS do
		local skin = ZombieSkins.get(skinName)
		local config = configFor(SKIN_CONFIG[skinName])
		local clips = rigs[string.lower(skinName)]
		if not skin or not config or not clips then
			continue
		end
		local z = origin.Z - (row - 1) * ROW_SPACING
		label(string.upper(skinName), Vector3.new(origin.X - 9, origin.Y + 6, z), parent)
		local column = 0
		for _, slot in SLOT_ORDER do
			local id = clips[slot]
			if typeof(id) == "number" and id > 0 then
				column += 1
				local ground = Vector3.new(origin.X + (column - 1) * COLUMN_SPACING, origin.Y, z)
				task.spawn(buildStation, parent, config, skin, slot, id, ground, label)
			end
		end
	end
	if not stepping then
		stepping = true
		RunService.Heartbeat:Connect(step)
	end
end

function SandboxGallery.setTimeScale(value: number)
	timeScale = math.clamp(value, 0, 4)
	for _, station in stations do
		if station.holdUntil == nil then
			station.track:AdjustSpeed(timeScale)
		end
	end
end

function SandboxGallery.clear()
	table.clear(stations)
end

return SandboxGallery
