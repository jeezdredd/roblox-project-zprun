--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)

local WeaponVfx = {}

local TRACER_COLOR = Color3.fromRGB(255, 214, 140)
local FLASH_COLOR = Color3.fromRGB(255, 196, 110)

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

function WeaponVfx.muzzleFlash(attachment: Attachment?, weaponId: string)
	if not attachment then
		return
	end
	local config = WeaponsConfig.get(weaponId)
	local scale = if config and config.class == "Shotgun" then 1.5 else 1

	local flash = Instance.new("ParticleEmitter")
	flash.Color = ColorSequence.new(FLASH_COLOR)
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.Size = NumberSequence.new(0.7 * scale, 0.1)
	flash.Transparency = NumberSequence.new(0.1, 1)
	flash.Lifetime = NumberRange.new(0.04, 0.07)
	flash.Speed = NumberRange.new(2, 5)
	flash.SpreadAngle = Vector2.new(35, 35)
	flash.Rate = 0
	flash.Parent = attachment
	flash:Emit(math.max(2, math.floor(6 * VfxConfig.DENSITY)))

	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Brightness = 3
	light.Range = 12 * scale
	light.Parent = attachment

	task.delay(0.05, function()
		light:Destroy()
	end)
	task.delay(0.4, function()
		flash:Destroy()
	end)
end

local SHELL_POOL_SIZE = 20
local shellPool: { BasePart } = {}
local shellCursor = 0

local function ensureShellPool()
	if #shellPool > 0 then
		return
	end
	for _ = 1, SHELL_POOL_SIZE do
		local shell = Instance.new("Part")
		shell.Name = "Shell"
		shell.Size = Vector3.new(0.08, 0.08, 0.24)
		shell.Color = Color3.fromRGB(190, 150, 60)
		shell.Material = Enum.Material.Metal
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CastShadow = false
		shell.Transparency = 1
		shell.Anchored = true
		shell.Parent = getFolder()
		table.insert(shellPool, shell)
	end
end

function WeaponVfx.shellEject(attachment: Attachment?)
	if not attachment then
		return
	end
	ensureShellPool()
	shellCursor = shellCursor % SHELL_POOL_SIZE + 1
	local shell = shellPool[shellCursor]
	if not shell or not shell.Parent then
		return
	end

	local origin = attachment.WorldPosition
	local rightVector = attachment.WorldCFrame.RightVector
	shell.Anchored = false
	shell.Transparency = 0
	shell.CFrame = CFrame.new(origin + rightVector * 0.3)
	shell.AssemblyLinearVelocity = rightVector * (6 + math.random() * 3) + Vector3.new(0, 5 + math.random() * 2, 0)
	shell.AssemblyAngularVelocity = Vector3.new(math.random() * 20 - 10, math.random() * 20 - 10, math.random() * 20 - 10)

	task.delay(1.4, function()
		if shell.Parent then
			shell.Anchored = true
			shell.Transparency = 1
			shell.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

function WeaponVfx.shellLandMaterial(position: Vector3): Enum.Material
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local folder = vfxFolder
	params.FilterDescendantsInstances = if folder then { folder } else {}
	local result = Workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return if result then result.Material else Enum.Material.Concrete
end

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

function WeaponVfx.barrelSmoke(attachment: Attachment?)
	if not attachment then
		return
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "BarrelSmoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(160, 158, 152))
	smoke.Size = NumberSequence.new(0.2, 1.6)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.7, 1.4)
	smoke.Speed = NumberRange.new(1.5, 3)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.Acceleration = Vector3.new(0, 2.5, 0)
	smoke.Rate = 0
	smoke.LightInfluence = 0.8
	smoke.Parent = attachment
	smoke:Emit(math.max(3, math.floor(10 * VfxConfig.DENSITY)))
	task.delay(2, function()
		smoke:Destroy()
	end)
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
