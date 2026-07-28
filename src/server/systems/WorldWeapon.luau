--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)

local WorldWeapon = {}

local COLOR_METAL = Color3.fromRGB(46, 48, 52)
local COLOR_GRIP = Color3.fromRGB(52, 44, 36)
local COLOR_WOOD = Color3.fromRGB(96, 72, 48)

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = parent
	return part
end

local function weldTo(anchorPart: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = anchorPart.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = anchorPart
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

local function build(character: Model, config: WeaponsConfig.WeaponConfig)
	local existing = character:FindFirstChild("WorldWeapon")
	if existing then
		existing:Destroy()
	end

	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	local model = Instance.new("Model")
	model.Name = "WorldWeapon"

	local isPistol = config.class == "Pistol"
	local isShotgun = config.class == "Shotgun"
	local bodyLength = if isPistol then 0.9 else 2.1
	local barrelLength = if isPistol then 0.4 else 1.3

	local grip = makePart("Grip", Vector3.new(0.3, 0.7, 0.34), COLOR_GRIP, Enum.Material.SmoothPlastic, model)
	local handOffset = CFrame.new(0, -0.9, -0.2) * CFrame.Angles(math.rad(-80), 0, 0)
	weldTo(hand, grip, handOffset)

	local receiver = makePart("Receiver", Vector3.new(0.28, 0.46, bodyLength), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(hand, receiver, handOffset * CFrame.new(0, 0.56, -bodyLength / 2 + 0.24))

	local barrel = makePart("Barrel", Vector3.new(0.15, 0.15, barrelLength), COLOR_METAL, Enum.Material.Metal, model)
	weldTo(hand, barrel, handOffset * CFrame.new(0, 0.62, -bodyLength - barrelLength / 2 + 0.3))

	if not isPistol then
		local furnitureColor = if isShotgun then COLOR_WOOD else COLOR_GRIP
		local furnitureMaterial = if isShotgun then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
		local stock = makePart("Stock", Vector3.new(0.24, 0.38, 0.9), furnitureColor, furnitureMaterial, model)
		weldTo(hand, stock, handOffset * CFrame.new(0, 0.5, 0.72))
		local handguard = makePart("Handguard", Vector3.new(0.28, 0.32, barrelLength * 0.6), furnitureColor, furnitureMaterial, model)
		weldTo(hand, handguard, handOffset * CFrame.new(0, 0.52, -bodyLength - 0.1))
	end

	if config.class == "SMG" or config.class == "Rifle" then
		local magazine = makePart("Magazine", Vector3.new(0.22, 0.66, 0.34), COLOR_METAL, Enum.Material.Metal, model)
		weldTo(hand, magazine, handOffset * CFrame.new(0, 0.2, -bodyLength / 2 + 0.1))
	end

	model.Parent = character
end

function WorldWeapon.apply(player: Player, weaponId: string)
	local character = player.Character
	if not character then
		return
	end
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	build(character, config)
end

function WorldWeapon.init()
	local function watch(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			local weaponId = player:GetAttribute("WeaponId")
			if typeof(weaponId) == "string" then
				task.defer(WorldWeapon.apply, player, weaponId)
			end
		end)
		player:GetAttributeChangedSignal("WeaponId"):Connect(function()
			local weaponId = player:GetAttribute("WeaponId")
			if typeof(weaponId) == "string" then
				WorldWeapon.apply(player, weaponId)
			end
		end)
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return WorldWeapon
