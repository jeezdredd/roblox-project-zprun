--!strict

-- Studio test yard (Sandbox), client side:
--   * the first-person weapon gallery: every pack clip on its own copy of the pack rig,
--     standing in the world at the uploaded size (about twice life size) and seen from
--     the side, looping with a short pause; the in-game uses of a clip (tactical and
--     empty reload cuts, the shotgun's shell loop and chambering pump, fire into pump)
--     get their own stations. Clip markers flash on the label and play their sound at
--     the rig, so sound sync can be judged by eye and ear.
--   * the zombie gallery's treadmills (SandboxGallery on the server): strips scrolled at
--     each walk/run clip's measured ground speed.
--   * the sound lane: speakers played in turn (B) with a gunshot, a zombie call and an
--     explosion.
-- Everything honours the workspace attribute DevTimeScale (set by SandboxInput, Z).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local ViewmodelPackConfig = require(ReplicatedStorage.Shared.config.ViewmodelPackConfig)
local ViewmodelClipPlayer = require(script.Parent.ViewmodelClipPlayer)
local WeaponSfx = require(script.Parent.WeaponSfx)
local SfxPlayer = require(script.Parent.SfxPlayer)

local SandboxWeaponGallery = {}

type Segment = { clip: string, from: number, to: number, phases: { ViewmodelPackConfig.Phase } }
type Station = {
	class: string,
	title: string,
	segments: { Segment },
	player: ViewmodelClipPlayer.Player,
	anchor: BasePart,
	label: TextLabel,
	segment: number,
	lastFraction: number,
	restUntil: number,
	flashUntil: number,
	flashText: string,
}

-- rigs at 1.6x their uploaded size (about 3.5x life): hands, bolts and magazines read
-- from the walkway; each rig is raised so its weapon sits at eye height
local GALLERY_SCALE = 1.6
local GUN_HEIGHT = 5.2
local COLUMN_SPACING = 10
local ROW_SPACING = 30
local STEP_RANGE = 45
local SOUND_RANGE = 25
local REST = 0.9
local CLASS_ORDER = { "Pistol", "Rifle", "Shotgun", "SMG" }
-- display order; clips not listed follow alphabetically
local CLIP_ORDER = {
	"Equip",
	"Idle",
	"Idle2",
	"Walk",
	"Run",
	"Fire",
	"AccionFire",
	"Reload",
	"ReloadEmpty",
	"IdleToReload",
	"ReloadToIdle",
	"Inspect",
}

local stations: { Station } = {}
local built = false

local function timeScale(): number
	local value = Workspace:GetAttribute("DevTimeScale")
	return if typeof(value) == "number" then value else 1
end

local function makeLabel(parent: BasePart, text: string): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 30
	gui.LightInfluence = 0
	gui.Parent = parent
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Code
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.fromRGB(240, 232, 205)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Text = text
	textLabel.Parent = gui
	return textLabel
end

local function segment(pack: ViewmodelPackConfig.ClassPack, clip: string, from: number?, to: number?, extra: { ViewmodelPackConfig.Phase }?): Segment
	local phases = {}
	for _, phase in pack.phases[clip] or {} do
		table.insert(phases, phase)
	end
	for _, phase in extra or {} do
		table.insert(phases, phase)
	end
	return { clip = clip, from = from or 0, to = to or 1, phases = phases }
end

-- Every clip in the pack plus the in-game cuts of this class.
local function entriesFor(pack: ViewmodelPackConfig.ClassPack, clips: { [string]: any }): { { title: string, segments: { Segment } } }
	local names = {}
	for name in clips do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local ia, ib = table.find(CLIP_ORDER, a) or 100, table.find(CLIP_ORDER, b) or 100
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	local entries = {}
	for _, name in names do
		table.insert(entries, { title = name, segments = { segment(pack, name) } })
	end
	local function cut(title: string, value: ViewmodelPackConfig.ClipCut?)
		if value and clips[value.clip] then
			table.insert(entries, {
				title = title,
				segments = { segment(pack, value.clip, value.from, value.to, value.phases) },
			})
		end
	end
	cut("game: tactical reload", pack.tactical)
	cut("game: empty reload", pack.empty)
	local shell = pack.shell
	if shell then
		cut("game: one shell", shell.loop)
		cut("game: chamber pump", shell.chamber)
	end
	if pack.fireFollow and clips[pack.fire] and clips[pack.fireFollow] then
		table.insert(entries, {
			title = "game: fire + pump",
			segments = {
				segment(pack, pack.fire, 0, pack.fireTo or 1),
				segment(pack, pack.fireFollow),
			},
		})
	end
	return entries
end

local function playSegment(station: Station)
	local seg = station.segments[station.segment]
	station.player:play(seg.clip, { from = seg.from, to = seg.to, fade = 0.08 })
	station.lastFraction = seg.from
end

local function buildStation(parent: Instance, template: Model, data: any, class: string, title: string, segments: { Segment }, cframe: CFrame)
	local model = template:Clone()
	local root = model:FindFirstChild("RootPart", true)
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return
	end
	if GALLERY_SCALE ~= 1 then
		model:ScaleTo(GALLERY_SCALE)
	end
	-- move the whole model so the root lands on the station, then drive it by the root
	model:PivotTo(model:GetPivot() * root.CFrame:Inverse() * cframe)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	model.Name = class .. "_" .. title
	model.Parent = parent
	local root_ = root :: BasePart
	local player = ViewmodelClipPlayer.new(data, root_, GALLERY_SCALE)
	-- lift or lower the rig so the weapon at rest is at eye height, then stand a post
	-- under it, so each rig reads as one exhibit
	local pack = ViewmodelPackConfig.get(class)
	local weaponRest = if pack then player:restWorld(pack.weaponBone) else nil
	if weaponRest then
		local lift = GUN_HEIGHT - (root_.CFrame * weaponRest.Position).Y + cframe.Position.Y
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
	local gun = if weaponRest then root_.CFrame * weaponRest.Position else cframe.Position + Vector3.new(0, 4, 0)
	local postHeight = math.max(gun.Y - cframe.Position.Y - 0.6, 0.5)
	local anchor = Instance.new("Part")
	anchor.Name = "Post"
	anchor.Anchored = true
	anchor.CanQuery = false
	anchor.Size = Vector3.new(0.5, postHeight, 0.5)
	anchor.CFrame = CFrame.new(gun.X, cframe.Position.Y - 0.5 + postHeight / 2, gun.Z)
	anchor.Color = Color3.fromRGB(60, 58, 54)
	anchor.Material = Enum.Material.Metal
	anchor.Parent = parent
	local total = 0
	for _, seg in segments do
		total += (seg.to - seg.from) * player:length(seg.clip)
	end
	local station: Station = {
		class = class,
		title = title,
		segments = segments,
		player = player,
		anchor = anchor,
		label = makeLabel(anchor, string.format("%s %s  %.2fs", class, title, total)),
		segment = 1,
		lastFraction = 0,
		restUntil = 0,
		flashUntil = 0,
		flashText = "",
	}
	station.label.Text = string.format("%s\n%s  %.2fs", class, title, total)
	playSegment(station)
	table.insert(stations, station)
end

local function build(origin: Vector3)
	if built then
		return
	end
	built = true
	local folder = Instance.new("Folder")
	folder.Name = "SandboxWeaponGallery"
	folder.Parent = Workspace
	local packs = ReplicatedStorage:WaitForChild("ViewModelPacks", 20)
	local clipFolder = ReplicatedStorage.Shared:FindFirstChild("viewmodel_clips")
	if not packs or not clipFolder then
		warn("[SandboxWeaponGallery] no packs or clips")
		return
	end
	for row, class in CLASS_ORDER do
		local pack = ViewmodelPackConfig.get(class)
		local template = if pack then packs:WaitForChild(class, 20) else nil
		local module = if pack then clipFolder:FindFirstChild(pack.clips) else nil
		if not pack or not template or not template:IsA("Model") or not module or not module:IsA("ModuleScript") then
			continue
		end
		local ok, data = pcall(require, module)
		if not ok then
			continue
		end
		local z = origin.Z - (row - 1) * ROW_SPACING
		for column, entry in entriesFor(pack, (data :: any).clips) do
			local x = origin.X - (column - 1) * COLUMN_SPACING
			-- the rig looks down its -Z: turn it to look down world -X, so the +Z walkway
			-- sees its right side (ejection port, bolt, mag well)
			local cframe = CFrame.new(x, origin.Y + 0.5, z) * CFrame.Angles(0, math.rad(90), 0)
			buildStation(folder, template, data, class, entry.title, entry.segments, cframe)
		end
	end
end

local function playPhase(station: Station, phase: string)
	station.flashText = phase
	station.flashUntil = os.clock() + 0.5
	local camera = Workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - station.anchor.Position).Magnitude > SOUND_RANGE then
		return
	end
	local id, volume = WeaponSfx.resolvePhase(phase, station.class)
	if id > 0 then
		SfxPlayer.play3D(station.anchor, id, volume, 4, 60, 0)
	end
end

local function stepStations(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	local scaled = deltaTime * timeScale()
	for _, station in stations do
		if (station.anchor.Position - eye).Magnitude > STEP_RANGE then
			continue
		end
		if station.restUntil > 0 then
			if now < station.restUntil then
				continue
			end
			station.restUntil = 0
			station.segment = 1
			playSegment(station)
		end
		local player = station.player
		local finished = player:step(scaled)
		local seg = station.segments[station.segment]
		local length = player:length(seg.clip)
		local fraction = if finished then seg.to elseif length > 0 then player.time / length else 0
		for _, phase in seg.phases do
			if phase.at > station.lastFraction and phase.at <= fraction then
				playPhase(station, phase.name)
			end
		end
		station.lastFraction = fraction
		if finished then
			if station.segment < #station.segments then
				station.segment += 1
				playSegment(station)
			else
				station.restUntil = now + REST
			end
		end
		local flash = if now < station.flashUntil then "  >> " .. station.flashText else ""
		local base = string.split(station.label.Text, "  >>")[1]
		if station.label.Text ~= base .. flash then
			station.label.Text = base .. flash
		end
	end
end

local function stepTreadmills(deltaTime: number)
	local scaled = deltaTime * timeScale()
	for _, strip in CollectionService:GetTagged("SandboxTreadmill") do
		if not strip:IsA("BasePart") then
			continue
		end
		local speed = strip:GetAttribute("ScrollSpeed")
		if typeof(speed) ~= "number" then
			continue
		end
		local shift = speed * scaled
		local texture = strip:FindFirstChildOfClass("Texture")
		if texture then
			texture.OffsetStudsU = (texture.OffsetStudsU + shift) % texture.StudsPerTileU
		end
		-- the stripes run toward the model's back (-X) and wrap within the strip
		local half = strip.Size.X / 2
		for _, stripe in strip:GetChildren() do
			if stripe:IsA("BasePart") then
				local offset = stripe.Position.X - strip.Position.X - shift
				if offset < -half then
					offset += strip.Size.X
				end
				stripe.CFrame = CFrame.new(strip.Position.X + offset, stripe.Position.Y, stripe.Position.Z)
			end
		end
	end
end

-- The sound lane: each speaker in turn plays a gunshot, a zombie call and an explosion.
local laneBusy = false

function SandboxWeaponGallery.playSoundLane()
	if laneBusy then
		return
	end
	laneBusy = true
	task.spawn(function()
		local speakers = {}
		for _, item in CollectionService:GetTagged("SandboxSpeaker") do
			if item:IsA("BasePart") then
				table.insert(speakers, item)
			end
		end
		table.sort(speakers, function(a, b)
			return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
		end)
		local weapons = AssetIds.audio.weapons :: { [string]: number }
		local zombie = AssetIds.audio.zombie :: { [string]: number }
		local world = AssetIds.audio.world :: { [string]: number }
		local sounds = {
			{ id = weapons.close_rifle or 0, volume = 1 },
			{ id = zombie.alert_bark or 0, volume = 1 },
			{ id = world.distant_boom or 0, volume = 1 },
		}
		for _, box in speakers do
			local color = box.Color
			box.Color = Color3.fromRGB(255, 190, 60)
			box.Material = Enum.Material.Neon
			for _, sound in sounds do
				if sound.id > 0 then
					SfxPlayer.play3D(box, sound.id, sound.volume, 10, 1000, 0)
				end
				task.wait(1.4)
			end
			box.Color = color
			box.Material = Enum.Material.Metal
			task.wait(0.6)
		end
		laneBusy = false
	end)
end

function SandboxWeaponGallery.init()
	task.spawn(function()
		while Workspace:GetAttribute("SandboxOrigin") == nil do
			task.wait(0.5)
		end
		local origin = Workspace:GetAttribute("SandboxOrigin") :: Vector3
		-- wait for the yard, so the gallery is built once the player is there
		while Workspace:GetAttribute("SandboxActive") ~= true do
			task.wait(0.5)
		end
		build(origin + Vector3.new(-140, 0, 40))
	end)
	RunService.RenderStepped:Connect(function(deltaTime)
		if not built then
			return
		end
		stepStations(deltaTime)
		stepTreadmills(deltaTime)
	end)
end

return SandboxWeaponGallery
