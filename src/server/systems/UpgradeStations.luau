--!strict

-- The upgrade station (docs/gameplay/upgrade-station.md): a field armourer's bench
-- placed along the run by the world generator (ChunkSpawner), one per
-- UpgradeStationConfig.SPACING_STUDS of road in the station biomes, its spot from a
-- Random seeded with the run seed and the chunk index. Holding its prompt upgrades the
-- carried weapon one level of the WeaponsConfig ladder for run credits through
-- RunEconomy; the level lives in WeaponService's run state and the profile is never
-- written. The station is tagged like a pickup scene so the client's pooled Highlight
-- outlines it; its bench lamp is its own light for when the pool is spent.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local UpgradeStationConfig = require(ReplicatedStorage.Shared.config.UpgradeStationConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local UpgradeStationMath = require(ReplicatedStorage.Shared.world.UpgradeStationMath)
local ChunkOccupancy = require(script.Parent.ChunkOccupancy)
local RunEconomy = require(script.Parent.RunEconomy)
local RunPromptGuard = require(script.Parent.RunPromptGuard)
local SceneParts = require(script.Parent.SceneParts)
local WeaponService = require(script.Parent.WeaponService)

local UpgradeStations = {}

UpgradeStations.TAG = "WeaponPickup"
UpgradeStations.PROMPT_NAME = "UpgradePrompt"

local FLOOR_TOP = 0.5
local CHECK_FLOOR = 1
local CHECK_HEIGHT = 7
local CHUNK_SEED_STEP = 7919
local SEED_MESH = 2

type Station = {
	model: Model,
	anchor: BasePart,
	chunkIndex: number,
}

local stations: { [Model]: Station } = {}
local seed = 0
local folder: Folder? = nil

local function color(spec: { number }): Color3
	return Color3.fromRGB(spec[1], spec[2], spec[3])
end

local function buildLights(model: Model)
	local face = model:FindFirstChild("LampFace")
	if face and face:IsA("BasePart") then
		local lamp = Instance.new("SpotLight")
		lamp.Name = "BenchLamp"
		lamp.Color = color(UpgradeStationConfig.LAMP_COLOR)
		lamp.Angle = 70
		lamp.Range = 22
		lamp.Brightness = 2.2
		lamp.Face = Enum.NormalId.Bottom
		lamp.Shadows = true
		lamp.Parent = face
	end
	local warning = model:FindFirstChild("WarningLight")
	if warning and warning:IsA("BasePart") then
		local glow = Instance.new("PointLight")
		glow.Name = "WarningGlow"
		glow.Color = color(UpgradeStationConfig.WARNING_COLOR)
		glow.Range = 9
		glow.Brightness = 1.2
		glow.Parent = warning
	end
end

local function buildAnchor(at: CFrame, parent: Model): BasePart
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = at
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.CastShadow = false
	anchor.Parent = parent
	parent.PrimaryPart = anchor
	return anchor
end

local function tell(player: Player, kind: string, payload: string, position: Vector3, level: number?)
	Remotes.getEvent(Remotes.Event.WeaponPickup):FireClient(player, kind, payload, position, level)
end

local function onTriggered(station: Station, player: Player)
	if not RunPromptGuard.canUse(player, station.anchor.Position, UpgradeStationConfig.USE_DISTANCE) then
		return
	end
	local position = station.anchor.Position
	local weaponId = WeaponService.carriedWeapon(player)
	local config = if weaponId then WeaponsConfig.get(weaponId) else nil
	if not weaponId or not config then
		return
	end
	local level = WeaponService.levelOf(player, weaponId)
	local quote = UpgradeStationMath.quote(WeaponsConfig, level, RunEconomy.snapshot(player).total)
	if not quote.ok then
		tell(player, "Refused", quote.reason or "Refused", position, level)
		return
	end
	if not RunEconomy.spend(player, quote.price) then
		tell(player, "Refused", string.format("Need %d CR", quote.price), position, level)
		return
	end
	WeaponService.setRunLevel(player, weaponId, quote.level)
	tell(player, "Upgrade", weaponId, position, quote.level)
end

local function register(model: Model, anchor: BasePart, prompt: ProximityPrompt, chunkIndex: number)
	model:SetAttribute("Kind", "Station")
	model:SetAttribute("Taken", false)
	CollectionService:AddTag(model, UpgradeStations.TAG)
	local station: Station = { model = model, anchor = anchor, chunkIndex = chunkIndex }
	stations[model] = station
	prompt.Triggered:Connect(function(player)
		onTriggered(station, player)
	end)
	model.Parent = folder or Workspace
end

local function buildStation(base: CFrame, rng: Random, chunkIndex: number)
	local model = Instance.new("Model")
	model.Name = "UpgradeStation"
	SceneParts.build(UpgradeStationConfig.parts, base, rng, model)
	buildLights(model)
	local at = UpgradeStationConfig.anchorAt
	local anchor = buildAnchor(base * CFrame.new(at[1], at[2], at[3]), model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = UpgradeStations.PROMPT_NAME
	prompt.ActionText = "Upgrade weapon"
	prompt.ObjectText = UpgradeStationConfig.DISPLAY_NAME
	prompt.HoldDuration = UpgradeStationConfig.HOLD_DURATION
	prompt.MaxActivationDistance = UpgradeStationConfig.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	register(model, anchor, prompt, chunkIndex)
end

-- The same spot check the pickups make (their footprints and crates aside: the station
-- is placed before the pickups of its chunk, they avoid it through Workspace.Pickups).
local function spotIsFree(chunk: Model, localX: number, localZ: number, position: Vector3, radius: number): boolean
	if not ChunkOccupancy.isFreeFor(chunk, localX, localZ, radius) then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { chunk, folder or Workspace }
	local center = CFrame.new(position + Vector3.new(0, CHECK_FLOOR + CHECK_HEIGHT / 2, 0))
	local hits = Workspace:GetPartBoundsInBox(center, Vector3.new(radius * 2, CHECK_HEIGHT, radius * 2), params)
	return #hits == 0
end

function UpgradeStations.configure(runSeed: number)
	seed = runSeed
end

-- Called by ChunkSpawner once the chunk stands at its pivot, before the pickups.
function UpgradeStations.spawnForChunk(chunkIndex: number, chunk: Model, biome: string)
	local chunkLength = GameConstants.CHUNK_LENGTH
	local rng = Random.new(seed + chunkIndex * CHUNK_SEED_STEP)
	local spots = UpgradeStationMath.plan(UpgradeStationConfig, biome, rng, {
		halfLength = chunkLength / 2,
		halfWidth = GameConstants.PLAYABLE_HALF_WIDTH,
		chunkStart = GameConstants.START_PLATFORM_LENGTH + chunkIndex * chunkLength,
	})
	if #spots == 0 then
		return
	end
	local meshRng = Random.new(seed + chunkIndex * CHUNK_SEED_STEP + SEED_MESH)
	local pivot = chunk:GetPivot()
	for _, spot in spots do
		local position = pivot.Position + Vector3.new(spot.x, FLOOR_TOP, spot.z)
		if spotIsFree(chunk, spot.x, spot.z, position, UpgradeStationConfig.RADIUS) then
			buildStation(CFrame.new(position) * CFrame.Angles(0, spot.yaw, 0), meshRng, chunkIndex)
			return
		end
	end
end

function UpgradeStations.clearChunk(chunkIndex: number)
	for model, station in stations do
		if station.chunkIndex == chunkIndex then
			model:Destroy()
			stations[model] = nil
		end
	end
end

-- Shares the pickups' folder so a pickup spot check sees the station.
function UpgradeStations.init(pickupsFolder: Folder)
	folder = pickupsFolder
end

return UpgradeStations
