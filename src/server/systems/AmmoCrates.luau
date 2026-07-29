--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local WeaponService = require(script.Parent.WeaponService)
local SkillEffects = require(script.Parent.SkillEffects)

local AmmoCrates = {}

local ROUNDS_MIN = 3
local ROUNDS_MAX = 8
local PICKUP_RADIUS = 9

type Crate = {
	model: Model,
	root: BasePart,
	chunkIndex: number,
	taken: boolean,
}

local crates: { [Model]: Crate } = {}
local random = Random.new()

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function buildSmoke(anchor: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 1.2, 0)
	attachment.Parent = anchor

	local pillar = Instance.new("ParticleEmitter")
	pillar.Name = "GreenSmoke"
	pillar.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 255, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 130, 70)),
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
	pillar.Acceleration = Vector3.new(1, 8, 0)
	pillar.LightEmission = 0.6
	pillar.LightInfluence = 0
	pillar.Parent = attachment

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(90, 240, 130)
	glow.Range = 26
	glow.Brightness = 1.4
	glow.Parent = anchor
end

function AmmoCrates.spawnForChunk(chunkIndex: number, chunkPivot: CFrame, chunkLength: number, chance: number)
	if random:NextNumber() > chance then
		return
	end

	local model = Instance.new("Model")
	model.Name = "AmmoCrate"

	local halfWidth = GameConstants.LANE_WIDTH / 2 - 24
	local offset = Vector3.new(
		random:NextNumber(-halfWidth, halfWidth),
		1.4,
		random:NextNumber(-chunkLength / 2 + 20, chunkLength / 2 - 20)
	)
	local position = chunkPivot.Position + offset

	local root = makePart("CrateBody", Vector3.new(5, 3, 3.4), CFrame.new(position) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0), Color3.fromRGB(74, 88, 64), Enum.Material.WoodPlanks, model)
	makePart("CrateLid", Vector3.new(5.2, 0.5, 3.6), root.CFrame * CFrame.new(0, 1.6, 0), Color3.fromRGB(60, 72, 52), Enum.Material.WoodPlanks, model)
	makePart("CrateStripe", Vector3.new(5.1, 0.5, 3.5), root.CFrame * CFrame.new(0, 0.2, 0), Color3.fromRGB(140, 190, 110), Enum.Material.SmoothPlastic, model)
	buildSmoke(root)

	model.PrimaryPart = root
	model.Parent = Workspace:FindFirstChild("Chunks") or Workspace

	crates[model] = { model = model, root = root, chunkIndex = chunkIndex, taken = false }
end

function AmmoCrates.clearChunk(chunkIndex: number)
	for model, crate in crates do
		if crate.chunkIndex == chunkIndex then
			model:Destroy()
			crates[model] = nil
		end
	end
end

local function collect(player: Player, crate: Crate)
	crate.taken = true
	local weaponId = player:GetAttribute("WeaponId")
	local config = if typeof(weaponId) == "string" then WeaponsConfig.get(weaponId) else nil
	local base = random:NextInteger(ROUNDS_MIN, ROUNDS_MAX)
	local rounds = if config then math.floor(base * SkillEffects.ammoScale(player)) else 0
	WeaponService.addReserve(player, rounds)
	Remotes.getEvent(Remotes.Event.AmmoPickup):FireClient(player, rounds, crate.root.Position)
	crate.model:Destroy()
	crates[crate.model] = nil
end

local function step()
	if next(crates) == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		for _, crate in crates do
			if not crate.taken and (crate.root.Position - root.Position).Magnitude <= PICKUP_RADIUS then
				collect(player, crate)
			end
		end
	end
end

function AmmoCrates.init()
	task.spawn(function()
		while true do
			task.wait(0.2)
			step()
		end
	end)
end

return AmmoCrates
