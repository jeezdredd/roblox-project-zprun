--!strict

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SettingsService = require(script.Parent.SettingsService)

local DeathGore = {}

local GIB_LIFETIME = 12
local GIB_COLORS = {
	Color3.fromRGB(118, 28, 28),
	Color3.fromRGB(96, 20, 20),
	Color3.fromRGB(140, 116, 96),
}

local random = Random.new()

local function spawnPool(position: Vector3)
	local pool = Instance.new("Part")
	pool.Name = "BloodPool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(0.2, 0.5, 0.5)
	pool.CFrame = CFrame.new(position.X, 0.62, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.Color = Color3.fromRGB(96, 16, 16)
	pool.Material = Enum.Material.SmoothPlastic
	pool.Parent = Workspace
	TweenService:Create(pool, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 9, 9),
	}):Play()
	Debris:AddItem(pool, GIB_LIFETIME)
end

local function spawnBurst(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 30, 30))
	emitter.Size = NumberSequence.new(1, 0.2)
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = attachment
	emitter:Emit(30)

	Debris:AddItem(anchor, 2)
end

local function spawnGibs(position: Vector3)
	for _ = 1, 7 do
		local size = random:NextNumber(0.7, 1.5)
		local gib = Instance.new("Part")
		gib.Name = "Gib"
		gib.Size = Vector3.new(size, size * random:NextNumber(0.5, 1), size * random:NextNumber(0.4, 0.9))
		gib.CFrame = CFrame.new(position + Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.5, 2), random:NextNumber(-1, 1)))
			* CFrame.Angles(random:NextNumber(0, math.pi), random:NextNumber(0, math.pi), 0)
		gib.Color = GIB_COLORS[random:NextInteger(1, #GIB_COLORS)]
		gib.Material = Enum.Material.SmoothPlastic
		gib.CanCollide = true
		gib.CanQuery = false
		gib.Parent = Workspace

		local direction = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.6, 1.4), random:NextNumber(-1, 1))
		gib:ApplyImpulse(direction * gib.AssemblyMass * random:NextNumber(14, 26))
		gib:ApplyAngularImpulse(Vector3.new(random:NextNumber(-4, 4), random:NextNumber(-4, 4), random:NextNumber(-4, 4)))

		Debris:AddItem(gib, GIB_LIFETIME)
	end
end

function DeathGore.render(position: Vector3)
	local blood = SettingsService.get("bloodEnabled") == true
	local gibs = SettingsService.get("dismembermentEnabled") == true
	if blood then
		spawnPool(position)
		spawnBurst(position)
	end
	if gibs then
		spawnGibs(position)
	end
end

return DeathGore
