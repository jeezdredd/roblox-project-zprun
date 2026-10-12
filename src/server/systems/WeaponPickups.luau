--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local PickupScenesConfig = require(ReplicatedStorage.Shared.config.PickupScenesConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local PickupPlanner = require(ReplicatedStorage.Shared.world.PickupPlanner)
local AmmoCrates = require(script.Parent.AmmoCrates)
local ChunkOccupancy = require(script.Parent.ChunkOccupancy)
local RunEconomy = require(script.Parent.RunEconomy)
local RunPromptGuard = require(script.Parent.RunPromptGuard)
local WeaponService = require(script.Parent.WeaponService)
local SceneParts = require(script.Parent.SceneParts)
local UpgradeStations = require(script.Parent.UpgradeStations)
local WorldMeshes = require(script.Parent.WorldMeshes)

local WeaponPickups = {}

local color = SceneParts.color
local makePart = SceneParts.makePart

WeaponPickups.TAG = "WeaponPickup"
WeaponPickups.PROMPT_NAME = "PickupPrompt"

local FLOOR_TOP = 0.5
local CHECK_FLOOR = 1
local CHECK_HEIGHT = 5
local CHUNK_SEED_STEP = 7919
local SEED_ROLL = 1
local SEED_MESH = 2
local CRATE_RADIUS = 3

type Pickup = {
	model: Model,
	anchor: BasePart,
	prompt: ProximityPrompt,
	chunkIndex: number,
	kind: string,
	weaponId: string?,
	radius: number,
	taken: boolean,
}

local pickups: { [Model]: Pickup } = {}
local seed = 0
local folder: Folder? = nil

local function buildWeaponProp(weaponId: string, base: CFrame, parent: Instance): Model
	local prop = Instance.new("Model")
	prop.Name = "Weapon"
	local specs = PickupScenesConfig.weaponProps[weaponId]
	if specs then
		for _, spec in specs do
			makePart(spec, base, prop)
		end
	end
	prop.Parent = parent
	return prop
end

local function buildPrompt(anchor: BasePart, objectText: string, actionText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = WeaponPickups.PROMPT_NAME
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = PickupScenesConfig.HOLD_DURATION
	prompt.MaxActivationDistance = PickupScenesConfig.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	return prompt
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

local function buildRedSmoke(anchor: BasePart)
	local smoke = PickupScenesConfig.supplyDrop.smoke
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 1.6, 0)
	attachment.Parent = anchor

	local pillar = Instance.new("ParticleEmitter")
	pillar.Name = "RedSmoke"
	pillar.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color(smoke)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 26)),
	})
	pillar.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	pillar.Size = NumberSequence.new(4, 16)
	pillar.Lifetime = NumberRange.new(3.5, 5)
	pillar.Rate = 14
	pillar.Speed = NumberRange.new(14, 20)
	pillar.SpreadAngle = Vector2.new(8, 8)
	pillar.Acceleration = Vector3.new(-1, 8, 0)
	pillar.LightEmission = 0.5
	pillar.LightInfluence = 0
	pillar.Parent = attachment

	local glow = Instance.new("PointLight")
	glow.Color = color(smoke)
	glow.Range = 26
	glow.Brightness = 1.4
	glow.Parent = anchor
end

local function buildSupplyDrop(base: CFrame, rng: Random, parent: Model): BasePart
	local scrape = makePart({ kind = "box", name = "Scrape", size = { 9, 0.05, 6 }, at = { 0, 0.03, 0 }, yaw = 12, color = { 52, 44, 36 }, material = "Ground" }, base, parent)
	scrape.CastShadow = false
	local crateAt = base * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), math.rad(14))
	local crate = WorldMeshes.placeFrom("supply_crate", rng, crateAt, 3.2, parent, { collide = true, shadow = true, sink = 0.2 })
	if crate then
		crate.Name = "Crate"
	else
		makePart({ kind = "box", name = "Crate", size = { 4.4, 3, 3 }, at = { 0, 1.5, 0 }, roll = 14, color = { 92, 98, 70 }, material = "WoodPlanks", collide = true }, base, parent)
		makePart({ kind = "box", name = "Strap", size = { 4.5, 0.4, 3.1 }, at = { 0, 1.5, 0 }, roll = 14, color = { 60, 62, 58 }, material = "Metal" }, base, parent)
	end
	makePart({ kind = "box", name = "Silk", size = { 7, 0.3, 5 }, at = { 4.8, 0.2, 1.2 }, yaw = -30, color = { 214, 208, 190 }, material = "Fabric" }, base, parent)
	makePart({ kind = "box", name = "SilkFold", size = { 3.6, 0.5, 2.6 }, at = { 5.6, 0.45, 0.4 }, yaw = 20, color = { 200, 194, 176 }, material = "Fabric" }, base, parent)
	for i = 1, 3 do
		makePart({ kind = "cylinder", name = "Cord", size = { 4, 0.08, 0.08 }, at = { 2.6, 1.2 + i * 0.25, 0.4 + i * 0.5 }, yaw = 8 * i, color = { 220, 220, 214 }, material = "SmoothPlastic" }, base, parent)
	end
	local canister = makePart({ kind = "cylinder", name = "Canister", size = { 1.1, 0.5, 0.5 }, at = { -0.4, 3.4, -0.6 }, roll = 90, color = { 120, 40, 34 }, material = "Metal" }, base, parent)
	return canister
end

local function tell(player: Player, kind: string, payload: string, position: Vector3)
	Remotes.getEvent(Remotes.Event.WeaponPickup):FireClient(player, kind, payload, position)
end

local function canTake(player: Player, pickup: Pickup): boolean
	if pickup.taken then
		return false
	end
	return RunPromptGuard.canUse(player, pickup.anchor.Position, PickupScenesConfig.PICKUP_DISTANCE)
end

local function take(pickup: Pickup)
	pickup.taken = true
	pickup.prompt.Enabled = false
	pickup.model:SetAttribute("Taken", true)
	local weapon = pickup.model:FindFirstChild("Weapon")
	if weapon then
		weapon:Destroy()
	end
	if pickup.kind == "Drop" then
		for _, descendant in pickup.model:GetDescendants() do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("PointLight") then
				descendant.Enabled = false
			end
		end
	end
end

local function onTriggered(pickup: Pickup, player: Player)
	if not canTake(player, pickup) then
		return
	end
	local position = pickup.anchor.Position
	if pickup.kind == "Scene" then
		local weaponId = pickup.weaponId
		if not weaponId or not WeaponService.pickUp(player, weaponId) then
			return
		end
		take(pickup)
		tell(player, "Weapon", weaponId, position)
		return
	end

	local cost = PickupScenesConfig.supplyDrop.cost
	if RunEconomy.snapshot(player).total < cost then
		tell(player, "Refused", string.format("Need %d CR", cost), position)
		return
	end
	local rollRng = Random.new(seed + pickup.chunkIndex * CHUNK_SEED_STEP + SEED_ROLL)
	local weaponId = PickupPlanner.rollDrop(PickupScenesConfig, rollRng:NextNumber())
	if weaponId == player:GetAttribute("WeaponId") then
		weaponId = PickupPlanner.rollDrop(PickupScenesConfig, rollRng:NextNumber())
	end
	if not weaponId or not WeaponsConfig.get(weaponId) then
		return
	end
	if not RunEconomy.spend(player, cost) then
		tell(player, "Refused", string.format("Need %d CR", cost), position)
		return
	end
	if not WeaponService.pickUp(player, weaponId) then
		return
	end
	take(pickup)
	tell(player, "Drop", weaponId, position)
end

local function register(model: Model, anchor: BasePart, prompt: ProximityPrompt, chunkIndex: number, kind: string, weaponId: string?, radius: number)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Taken", false)
	if weaponId then
		model:SetAttribute("WeaponId", weaponId)
	end
	CollectionService:AddTag(model, WeaponPickups.TAG)
	local pickup: Pickup = { model = model, anchor = anchor, prompt = prompt, chunkIndex = chunkIndex, kind = kind, weaponId = weaponId, radius = radius, taken = false }
	pickups[model] = pickup
	prompt.Triggered:Connect(function(player)
		onTriggered(pickup, player)
	end)
	model.Parent = folder or Workspace
end

local function buildScene(sceneId: string, base: CFrame, rng: Random, chunkIndex: number)
	local config = PickupScenesConfig.get(sceneId)
	if not config then
		return
	end
	local model = Instance.new("Model")
	model.Name = "PickupScene_" .. sceneId
	model:SetAttribute("SceneId", sceneId)
	SceneParts.build(config.parts, base, rng, model)
	local weaponAt = base
		* CFrame.new(config.weaponAt[1], config.weaponAt[2], config.weaponAt[3])
		* CFrame.Angles(math.rad(config.weaponPitch or 0), math.rad(config.weaponYaw or 0), math.rad(config.weaponRoll or 0))
	buildWeaponProp(config.weaponId, weaponAt, model)
	local anchor = buildAnchor(weaponAt, model)
	local prompt = buildPrompt(anchor, config.prompt, "Take")
	register(model, anchor, prompt, chunkIndex, "Scene", config.weaponId, config.radius)
end

local function buildDrop(base: CFrame, rng: Random, chunkIndex: number)
	local model = Instance.new("Model")
	model.Name = "PickupSupplyDrop"
	local canister = buildSupplyDrop(base, rng, model)
	local anchor = buildAnchor(CFrame.new(canister.Position), model)
	buildRedSmoke(anchor)
	local prompt = buildPrompt(anchor, PickupScenesConfig.supplyDrop.displayName, string.format("Crack open · %d CR", PickupScenesConfig.supplyDrop.cost))
	register(model, anchor, prompt, chunkIndex, "Drop", nil, PickupScenesConfig.supplyDrop.radius)
end

local function spotIsFree(chunk: Model, chunkIndex: number, localX: number, localZ: number, position: Vector3, radius: number): boolean
	if not ChunkOccupancy.isFreeFor(chunk, localX, localZ, radius) then
		return false
	end
	for _, pickup in pickups do
		local reach = radius + pickup.radius
		local delta = pickup.anchor.Position - position
		if delta.X * delta.X + delta.Z * delta.Z < reach * reach then
			return false
		end
	end
	for _, crate in AmmoCrates.positionsForChunk(chunkIndex) do
		local reach = radius + CRATE_RADIUS
		local delta = crate - position
		if delta.X * delta.X + delta.Z * delta.Z < reach * reach then
			return false
		end
	end
	for _, station in UpgradeStations.footprintsForChunk(chunkIndex) do
		local reach = radius + station.radius
		local delta = station.position - position
		if delta.X * delta.X + delta.Z * delta.Z < reach * reach then
			return false
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { chunk, folder or Workspace }
	local center = CFrame.new(position + Vector3.new(0, CHECK_FLOOR + CHECK_HEIGHT / 2, 0))
	local hits = Workspace:GetPartBoundsInBox(center, Vector3.new(radius * 2, CHECK_HEIGHT, radius * 2), params)
	return #hits == 0
end

function WeaponPickups.configure(runSeed: number)
	seed = runSeed
end

function WeaponPickups.spawnForChunk(chunkIndex: number, chunk: Model, biome: string)
	local rng = Random.new(seed + chunkIndex * CHUNK_SEED_STEP)
	local placements = PickupPlanner.plan(PickupScenesConfig, biome, chunkIndex, rng, {
		halfLength = GameConstants.CHUNK_LENGTH / 2,
		halfWidth = GameConstants.PLAYABLE_HALF_WIDTH,
	})
	if #placements == 0 then
		return
	end
	local meshRng = Random.new(seed + chunkIndex * CHUNK_SEED_STEP + SEED_MESH)
	local pivot = chunk:GetPivot()
	for _, placement in placements do
		for _, spot in placement.spots do
			local position = pivot.Position + Vector3.new(spot.x, FLOOR_TOP, spot.z)
			if spotIsFree(chunk, chunkIndex, spot.x, spot.z, position, placement.radius) then
				local base = CFrame.new(position) * CFrame.Angles(0, spot.yaw, 0)
				if placement.kind == "Scene" and placement.sceneId then
					buildScene(placement.sceneId, base, meshRng, chunkIndex)
				elseif placement.kind == "Drop" then
					buildDrop(base, meshRng, chunkIndex)
				end
				break
			end
		end
	end
end

function WeaponPickups.clearChunk(chunkIndex: number)
	for model, pickup in pickups do
		if pickup.chunkIndex == chunkIndex then
			model:Destroy()
			pickups[model] = nil
		end
	end
end

function WeaponPickups.init(): Folder
	local created = Instance.new("Folder")
	created.Name = "Pickups"
	created.Parent = Workspace
	folder = created
	return created
end

return WeaponPickups
