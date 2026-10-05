--!strict

-- Studio test yard (DevConfig.SANDBOX). Instead of the run, the player walks a flat
-- yard well away from the road with the weapons live, laid out as stations:
--   * spawn: key board; idle zombies of every skin at 25 and 60 studs (respawning a few
--     seconds after each death); G sends a chasing wave
--   * west: target dummies at 10/25/50/100 studs and a row of material walls to shoot
--     (impacts, casings, ricochet sounds); the first-person weapon gallery beyond it
--     (client, SandboxWeaponGallery): every pack clip on its own rig, seen from the side
--   * east: surface strips for footstep and casing sounds; the zombie clip gallery
--     (SandboxGallery): every skin x every clip, walkers on scrolling treadmills
--   * the sound lane (far east): speakers at 25/50/100/200/400 studs and one behind a
--     wall, played in turn by the client (B)
--   * north: every world prop at its real size next to a 1.8 m mannequin, then a wall of
--     every surface MaterialVariant and decal
--   * a closed room for the interior acoustics
-- Keys (client SandboxInput): G wave, H reset, J calm, T back to start, V third person,
-- Z slow motion (1, 1/4, 1/10), B sound lane.
--
-- It rides on the normal mission: DevBench's QUICK_RUN starts a solo run, this module
-- moves the character into the yard, and two workspace attributes switch the run's
-- systems over: SandboxActive (ZombieAI stops its own spawning; the stuck check is off
-- through DevFreezeRun) and SandboxAggro (ZombieAI's chase switch in the yard).
--
-- The yard and the normal run swap while playing (Studio only): the workspace attribute
-- DevMode holds "Yard" or "Run" (DevConfig.SANDBOX.enabled picks the first one) and
-- DevFreezeRun follows it. The client's dev button (SandboxInput) sends "mode"; a run in
-- progress is stopped, and DevBench's quick run launches the next one in the new mode.

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local WorldMeshConfig = require(ReplicatedStorage.Shared.config.WorldMeshConfig)
local ZombieSkins = require(ReplicatedStorage.Shared.config.ZombieSkins)
local ZombieAI = require(script.Parent.ZombieAI)
local WorldMeshes = require(script.Parent.WorldMeshes)
local DevBench = require(script.Parent.DevBench)
local MissionService = require(script.Parent.MissionService)
local DevMode = require(ReplicatedStorage.Shared.util.DevMode)
local SandboxGallery = require(script.Parent.SandboxGallery)

local Sandbox = {}

type Slot = { position: Vector3, configId: string, skin: string, model: Model?, deadSince: number? }

local PHASE_ATTRIBUTE = "FlowPhase"
-- the yard floor: x from -360 to +360, z from +60 to -400 around the origin
local YARD_WIDTH = 720
local YARD_LENGTH = 460
local YARD_CENTRE_Z = 60 - YARD_LENGTH / 2

local settings = DevConfig.SANDBOX
local origin: Vector3 = settings.origin
local yard: Folder? = nil
local slots: { Slot } = {}
local random = Random.new()

-- the player spawns here facing -Z (the run direction), with everything laid out ahead
local function spawnCFrame(): CFrame
	return CFrame.lookAt(origin + Vector3.new(0, 3, 30), origin + Vector3.new(0, 3, -100))
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(text: string, position: Vector3, parent: Instance, maxDistance: number?)
	local anchor = part("Label", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), Color3.new(), Enum.Material.SmoothPlastic, parent)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(190, 26)
	gui.MaxDistance = maxDistance or 60
	gui.LightInfluence = 0
	gui.Parent = anchor
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Code
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.fromRGB(240, 232, 205)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Text = text
	textLabel.Parent = gui
end

-- One strip per footstep/casing material, walked or shot over to hear each surface.
local STRIPS: { { name: string, material: Enum.Material, color: Color3 } } = {
	{ name = "Asphalt", material = Enum.Material.Asphalt, color = Color3.fromRGB(58, 58, 60) },
	{ name = "Concrete", material = Enum.Material.Concrete, color = Color3.fromRGB(128, 126, 120) },
	{ name = "Grass", material = Enum.Material.Grass, color = Color3.fromRGB(78, 104, 58) },
	{ name = "Sand", material = Enum.Material.Sand, color = Color3.fromRGB(188, 168, 128) },
	{ name = "Metal", material = Enum.Material.DiamondPlate, color = Color3.fromRGB(110, 112, 116) },
	{ name = "Wood", material = Enum.Material.WoodPlanks, color = Color3.fromRGB(120, 90, 62) },
	{ name = "Ground", material = Enum.Material.Ground, color = Color3.fromRGB(96, 80, 62) },
}

-- Walls to shoot at, one per impact material.
local WALLS: { { name: string, material: Enum.Material, color: Color3 } } = {
	{ name = "Concrete", material = Enum.Material.Concrete, color = Color3.fromRGB(140, 136, 128) },
	{ name = "Brick", material = Enum.Material.Brick, color = Color3.fromRGB(128, 70, 56) },
	{ name = "Metal plate", material = Enum.Material.DiamondPlate, color = Color3.fromRGB(118, 120, 124) },
	{ name = "Rusted metal", material = Enum.Material.CorrodedMetal, color = Color3.fromRGB(122, 84, 60) },
	{ name = "Wood planks", material = Enum.Material.WoodPlanks, color = Color3.fromRGB(128, 96, 64) },
	{ name = "Sand berm", material = Enum.Material.Sand, color = Color3.fromRGB(190, 170, 128) },
	{ name = "Glass", material = Enum.Material.Glass, color = Color3.fromRGB(170, 200, 210) },
}

local function buildRoom(parent: Instance, center: Vector3)
	-- 28 x 28 x 12 concrete room with a doorway facing the spawn
	local size = Vector3.new(28, 12, 28)
	local wall = Color3.fromRGB(122, 118, 110)
	local half = size / 2
	local thickness = 1
	part("RoomFloor", Vector3.new(size.X, 1, size.Z), CFrame.new(center + Vector3.new(0, 0.5, 0)), Color3.fromRGB(96, 94, 90), Enum.Material.Concrete, parent)
	part("RoomRoof", Vector3.new(size.X, thickness, size.Z), CFrame.new(center + Vector3.new(0, size.Y + 0.5, 0)), wall, Enum.Material.Concrete, parent)
	part("RoomBack", Vector3.new(size.X, size.Y, thickness), CFrame.new(center + Vector3.new(0, half.Y + 0.5, -half.Z)), wall, Enum.Material.Concrete, parent)
	part("RoomLeft", Vector3.new(thickness, size.Y, size.Z), CFrame.new(center + Vector3.new(-half.X, half.Y + 0.5, 0)), wall, Enum.Material.Concrete, parent)
	part("RoomRight", Vector3.new(thickness, size.Y, size.Z), CFrame.new(center + Vector3.new(half.X, half.Y + 0.5, 0)), wall, Enum.Material.Concrete, parent)
	-- front wall in two halves around a 6-stud doorway
	local side = (size.X - 6) / 2
	part("RoomFrontL", Vector3.new(side, size.Y, thickness), CFrame.new(center + Vector3.new(-(3 + side / 2), half.Y + 0.5, half.Z)), wall, Enum.Material.Concrete, parent)
	part("RoomFrontR", Vector3.new(side, size.Y, thickness), CFrame.new(center + Vector3.new(3 + side / 2, half.Y + 0.5, half.Z)), wall, Enum.Material.Concrete, parent)
	part("RoomLintel", Vector3.new(6, size.Y - 8, thickness), CFrame.new(center + Vector3.new(0, 8 + (size.Y - 8) / 2 + 0.5, half.Z)), wall, Enum.Material.Concrete, parent)
	-- WeaponSfx reads this attribute for the interior gun tail
	local zone = part("AcousticZone", size, CFrame.new(center + Vector3.new(0, half.Y + 0.5, 0)), Color3.new(), Enum.Material.SmoothPlastic, parent)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone:SetAttribute("AcousticSpace", "Interior")
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 226, 180)
	light.Parent = part("RoomLamp", Vector3.new(1, 0.3, 1), CFrame.new(center + Vector3.new(0, size.Y, 0)), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, parent)
	label("ROOM (interior acoustics)", center + Vector3.new(0, size.Y + 3, half.Z), parent)
	-- a speaker inside for the sound lane (B plays it last)
	local speaker = part("Speaker", Vector3.new(1.4, 2.4, 1.4), CFrame.new(center + Vector3.new(0, 2, -8)), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, parent)
	speaker:SetAttribute("Order", 99)
	speaker:SetAttribute("Caption", "inside the room")
	CollectionService:AddTag(speaker, "SandboxSpeaker")
end

-- A 1.8 m figure (6.4 studs at 1 stud = 0.28 m) for judging prop scale.
local MANNEQUIN_HEIGHT = 1.8 / 0.28

local function mannequin(parent: Instance, ground: Vector3)
	local h = MANNEQUIN_HEIGHT
	local color = Color3.fromRGB(220, 200, 150)
	local legs = part("MannequinLegs", Vector3.new(1.3, h * 0.47, 0.7), CFrame.new(ground + Vector3.new(0, h * 0.235, 0)), color, Enum.Material.SmoothPlastic, parent)
	local torso = part("MannequinTorso", Vector3.new(1.7, h * 0.36, 0.8), CFrame.new(ground + Vector3.new(0, h * 0.47 + h * 0.18, 0)), color, Enum.Material.SmoothPlastic, parent)
	local head = part("MannequinHead", Vector3.new(0.85, h * 0.15, 0.9), CFrame.new(ground + Vector3.new(0, h * 0.83 + h * 0.085, 0)), color, Enum.Material.SmoothPlastic, parent)
	for _, p in { legs, torso, head } do
		p.CanQuery = false
	end
end

-- Every world mesh at its in-game size, largest last, each with a mannequin beside it.
local function buildProps(parent: Instance)
	WorldMeshes.waitReady(10)
	local names = {}
	for name in WorldMeshConfig.meshes do
		table.insert(names, name)
	end
	table.sort(names)
	local x = origin.X - 330
	local z = origin.Z - 210
	for _, name in names do
		local entry = WorldMeshConfig.meshes[name]
		if not WorldMeshes.isLoaded(name) then
			label(name .. " (not loaded)", Vector3.new(x, origin.Y + 4, z), parent)
			x += 8
			continue
		end
		-- props modelled in metres go in at their real size; the older meshes have no
		-- real size, so they use the sizes the chunk builders give them
		local size: Vector3
		local placed: MeshPart?
		local base = CFrame.new(x, origin.Y, z)
		if entry.studsPerUnit then
			size = WorldMeshes.naturalSize(name) :: Vector3
			base = CFrame.new(x + size.X / 2, origin.Y, z)
			placed = WorldMeshes.placeNatural(name, base, parent, { collide = true, sink = 0 })
		else
			local native = WorldMeshes.nativeSize(name) :: Vector3
			local height = if string.find(name, "^building") then 40
				elseif string.find(name, "^tree") then 24
				elseif string.find(name, "^car") then 15 * native.Y / native.Z
				elseif name == "rock_boulder" then 5
				else 4
			size = native * (height / native.Y)
			base = CFrame.new(x + size.X / 2, origin.Y, z)
			placed = WorldMeshes.place(name, base, height, parent, { collide = true, sink = 0 })
		end
		local centre = x + size.X / 2
		mannequin(parent, Vector3.new(x - 1.2, origin.Y, z + size.Z / 2 + 2))
		label(string.format("%s  %.1f x %.1f x %.1f", name, size.X, size.Y, size.Z), Vector3.new(centre, origin.Y + size.Y + 3, z), parent)
		local _ = placed
		x += size.X + 7
	end
end

-- Every surface MaterialVariant as a standing tile and a floor patch, then the decals.
local function buildTextureWall(parent: Instance)
	local variants: { MaterialVariant } = {}
	for _, item in MaterialService:GetChildren() do
		if item:IsA("MaterialVariant") then
			table.insert(variants, item)
		end
	end
	table.sort(variants, function(a, b)
		return a.Name < b.Name
	end)
	local z = origin.Z - 340
	local x = origin.X - 330
	for _, variant in variants do
		-- white parts: a MaterialVariant's colour map is tinted by the part colour
		local tile = part("Tile_" .. variant.Name, Vector3.new(12, 12, 1), CFrame.new(x + 6, origin.Y + 6, z), Color3.new(1, 1, 1), variant.BaseMaterial, parent)
		tile.MaterialVariant = variant.Name
		local floor = part("Floor_" .. variant.Name, Vector3.new(12, 0.2, 12), CFrame.new(x + 6, origin.Y + 0.1, z + 7.5), Color3.new(1, 1, 1), variant.BaseMaterial, parent)
		floor.MaterialVariant = variant.Name
		label(variant.Name, Vector3.new(x + 6, origin.Y + 13.5, z), parent)
		x += 14
	end
	-- decals on concrete panels
	local decals = (AssetIds.texture :: any).decal or {}
	local keys = {}
	for key in decals do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local panel = part("Decal_" .. key, Vector3.new(12, 12, 1), CFrame.new(x + 6, origin.Y + 6, z), Color3.fromRGB(150, 146, 138), Enum.Material.Concrete, parent)
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal.Texture = "rbxassetid://" .. tostring(decals[key])
		decal.Parent = panel
		-- the front face points -Z: turn the panel so its decal faces the yard (+Z)
		panel.CFrame = panel.CFrame * CFrame.Angles(0, math.pi, 0)
		label("decal " .. key, Vector3.new(x + 6, origin.Y + 13.5, z), parent)
		x += 14
	end
end

-- A standing board with the yard's keys, readable from the spawn.
local KEY_LINES = {
	"TEST YARD",
	"1-4 weapons   R reload   F inspect",
	"G zombie wave   J calm   H reset   T back here",
	"V third person   Z slow motion   B sound lane",
	"K audio   L test shot   Shift+P free cam",
	"West: range, material walls, weapon clips",
	"East: surfaces, zombie clips, sound lane",
	"North: props at real size, texture wall",
}

local function keyBoard(parent: Instance, ground: Vector3)
	local board = part("KeyBoard", Vector3.new(12, 7, 0.4), CFrame.new(ground + Vector3.new(0, 5.5, 0)) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(30, 30, 32), Enum.Material.SmoothPlastic, parent)
	board.CanQuery = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingTop = UDim.new(0, 14)
	padding.Parent = gui
	for index, line in KEY_LINES do
		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, -36, 0, if index == 1 then 52 else 38)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Code
		text.TextSize = if index == 1 then 46 else 30
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextColor3 = if index == 1 then Color3.fromRGB(255, 200, 90) else Color3.fromRGB(235, 230, 215)
		text.Text = line
		text.LayoutOrder = index
		text.Parent = gui
	end
end

-- Walls to shoot beside the target range.
local function buildWalls(parent: Instance)
	local z = origin.Z - 150
	for index, wall in WALLS do
		local x = origin.X - 150 + (index - 1) * 13
		local slab = part("Wall_" .. wall.name, Vector3.new(10, 10, 2), CFrame.new(x, origin.Y + 5, z), wall.color, wall.material, parent)
		if wall.material == Enum.Material.Glass then
			slab.Transparency = 0.4
		end
		label(wall.name, Vector3.new(x, origin.Y + 11.5, z), parent)
	end
end

-- The sound lane: speakers at fixed distances from a listening pad, and a second lane
-- with a thick wall in front of its speaker, for distance and occlusion.
local SOUND_DISTANCES = { 25, 50, 100, 200, 400 }

local function speaker(parent: Instance, position: Vector3, order: number, caption: string)
	local pole = part("SpeakerPole", Vector3.new(0.4, 4, 0.4), CFrame.new(position + Vector3.new(0, 2, 0)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, parent)
	pole.CanQuery = false
	local box = part("Speaker", Vector3.new(1.4, 2.4, 1.4), CFrame.new(position + Vector3.new(0, 5.2, 0)), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, parent)
	box:SetAttribute("Order", order)
	box:SetAttribute("Caption", caption)
	CollectionService:AddTag(box, "SandboxSpeaker")
	label(caption, position + Vector3.new(0, 8, 0), parent)
end

local function buildSoundLane(parent: Instance)
	local pad = origin + Vector3.new(300, 0, 40)
	local listeningPad = part("ListeningPad", Vector3.new(8, 0.3, 8), CFrame.new(pad + Vector3.new(0, 0.15, 0)), Color3.fromRGB(200, 170, 60), Enum.Material.SmoothPlastic, parent)
	-- B brings the player here first (SandboxWeaponGallery.playSoundLane)
	CollectionService:AddTag(listeningPad, "SandboxListeningPad")
	label("LISTEN HERE (B brings you here and plays the lane)", pad + Vector3.new(0, 6, 0), parent)
	for index, distance in SOUND_DISTANCES do
		speaker(parent, pad + Vector3.new(0, 0, -distance), index, string.format("%d studs", distance))
	end
	-- behind a wall: same 50 studs, a concrete wall 10 studs in front of the speaker
	speaker(parent, pad + Vector3.new(30, 0, -50), #SOUND_DISTANCES + 1, "50 studs, behind a wall")
	part("OcclusionWall", Vector3.new(18, 14, 3), CFrame.new(pad + Vector3.new(30, 7, -40)), Color3.fromRGB(128, 124, 116), Enum.Material.Concrete, parent)
end

local function buildYard()
	if yard then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SandboxYard"
	folder.Parent = Workspace
	yard = folder

	part("YardFloor", Vector3.new(YARD_WIDTH, 4, YARD_LENGTH), CFrame.new(origin + Vector3.new(0, -2, YARD_CENTRE_Z)), Color3.fromRGB(86, 84, 80), Enum.Material.Concrete, folder)
	-- low walls so zombies and casings stay in
	for _, sign in { -1, 1 } do
		part("YardWall", Vector3.new(2, 6, YARD_LENGTH), CFrame.new(origin + Vector3.new(sign * YARD_WIDTH / 2, 3, YARD_CENTRE_Z)), Color3.fromRGB(100, 96, 90), Enum.Material.Concrete, folder)
	end

	-- surface strips beside the spawn
	for index, strip in STRIPS do
		local x = origin.X + 30 + (index - 1) * 8
		part("Strip_" .. strip.name, Vector3.new(8, 0.2, 60), CFrame.new(x, origin.Y + 0.1, origin.Z - 10), strip.color, strip.material, folder)
		label(strip.name, Vector3.new(x, origin.Y + 3, origin.Z + 22), folder)
	end

	buildRoom(folder, origin + Vector3.new(-50, 0, 10))
	buildWalls(folder)
	buildSoundLane(folder)
	buildTextureWall(folder)
	SandboxGallery.build(folder, origin + Vector3.new(110, 0, 40), label)
	-- the client builds the weapon gallery here (SandboxWeaponGallery)
	label("WEAPON CLIPS (walk along the south side)", origin + Vector3.new(-170, 12, 55), folder)
	label("ZOMBIE CLIPS (walkers on treadmills)", origin + Vector3.new(150, 12, 52), folder)
	keyBoard(folder, origin + Vector3.new(-14, 0, 14))
	task.spawn(buildProps, folder)
end

-- one of each skin at 25 and 60 studs, facing the spawn
local function buildSlots()
	table.clear(slots)
	local skins: { { configId: string, skin: string } } = {}
	for configId, options in ZombieSkins.byConfig do
		for _, option in options do
			if ZombieSkins.get(option.skin) then
				table.insert(skins, { configId = configId, skin = option.skin })
			end
		end
	end
	table.sort(skins, function(a, b)
		return a.skin < b.skin
	end)
	for rowIndex, distance in { 25, 60 } do
		for index, entry in skins do
			local x = origin.X + (index - (#skins + 1) / 2) * 14 - 10
			table.insert(slots, {
				position = Vector3.new(x, origin.Y + 3, origin.Z - distance),
				configId = entry.configId,
				skin = entry.skin,
				model = nil,
				deadSince = nil,
			})
			if rowIndex == 1 and yard then
				label(entry.skin, Vector3.new(x, origin.Y + 9, origin.Z - distance), yard)
			end
		end
	end
end

local function spawnSlot(slot: Slot)
	slot.model = ZombieAI.devSpawn(slot.position, slot.configId, slot.skin, origin + Vector3.new(0, 3, 30), false)
	slot.deadSince = nil
end

local function respawnDead(now: number)
	for _, slot in slots do
		local model = slot.model
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if not model or not model.Parent or not humanoid then
			spawnSlot(slot)
		elseif humanoid.Health <= 0 then
			slot.deadSince = slot.deadSince or now
			if now - (slot.deadSince :: number) >= settings.respawnDelay then
				spawnSlot(slot)
			end
		end
	end
end

local function sendWave(player: Player)
	Workspace:SetAttribute("SandboxAggro", true)
	local skins = {}
	for _, slot in slots do
		table.insert(skins, slot)
	end
	for _ = 1, settings.waveSize do
		local pick = skins[random:NextInteger(1, #skins)]
		local position = origin + Vector3.new(random:NextNumber(-40, 40), 3, -110 - random:NextNumber(0, 30))
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local faceAt = if root and root:IsA("BasePart") then root.Position else origin
		ZombieAI.devSpawn(position, pick.configId, pick.skin, faceAt, true)
	end
end

local function teleport(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(spawnCFrame())
	end
end

local function reset()
	Workspace:SetAttribute("SandboxAggro", false)
	ZombieAI.clearAll()
	for _, slot in slots do
		slot.model = nil
		slot.deadSince = nil
	end
end

local function enter(player: Player)
	buildYard()
	if #slots == 0 then
		buildSlots()
	end
	Workspace:SetAttribute("SandboxActive", true)
	Workspace:SetAttribute("SandboxAggro", false)
	-- after MissionService has placed the character at the run start
	task.delay(0.6, function()
		teleport(player)
		DevBench.buildTargetRange(origin + Vector3.new(-70, 0.05, -20))
	end)
end

local function watch(player: Player)
	player:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(function()
		if player:GetAttribute(PHASE_ATTRIBUTE) == "Mission" and DevMode.yard() then
			enter(player)
		end
	end)
	if player:GetAttribute(PHASE_ATTRIBUTE) == "Mission" and DevMode.yard() then
		enter(player)
	end
end

local function setMode(player: Player, mode: any)
	if (mode ~= "Yard" and mode ~= "Run") or DevMode.current() == mode then
		return
	end
	Workspace:SetAttribute("DevMode", mode)
	Workspace:SetAttribute("DevFreezeRun", mode == "Yard")
	if mode == "Run" then
		reset()
		Workspace:SetAttribute("SandboxActive", false)
	end
	-- a run in progress restarts in the new mode: stop sends the player to the hub and
	-- DevBench's quick run launches again from there (straight in for the yard, through
	-- the cabin for the run when DevConfig.QUICK_LAUNCH asks for it). In the cabin the
	-- launch already under way simply lands in the new mode.
	if player:GetAttribute(PHASE_ATTRIBUTE) == "Mission" then
		MissionService.stop(player)
	end
end

function Sandbox.init()
	if not RunService:IsStudio() then
		return
	end
	local startMode: DevMode.Mode = if settings.enabled then "Yard" else "Run"
	Workspace:SetAttribute("DevMode", startMode)
	Workspace:SetAttribute("DevFreezeRun", startMode == "Yard")
	-- the client builds its galleries around this point
	Workspace:SetAttribute("SandboxOrigin", origin)
	local remote = Instance.new("RemoteEvent")
	remote.Name = "SandboxCommand"
	remote.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(function(player, command, value)
		if command == "wave" then
			sendWave(player)
		elseif command == "reset" then
			reset()
			teleport(player)
		elseif command == "calm" then
			Workspace:SetAttribute("SandboxAggro", false)
		elseif command == "start" then
			teleport(player)
		elseif command == "timescale" and typeof(value) == "number" then
			SandboxGallery.setTimeScale(value)
		elseif command == "mode" then
			setMode(player, value)
		end
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < 0.5 or Workspace:GetAttribute("SandboxActive") ~= true then
			return
		end
		elapsed = 0
		respawnDead(os.clock())
	end)
end

return Sandbox
