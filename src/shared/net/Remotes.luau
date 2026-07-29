--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"

Remotes.Event = table.freeze({
	SquadSnapshot = "SquadSnapshot",
	SquadUpdateConfig = "SquadUpdateConfig",
	SquadToggleModifier = "SquadToggleModifier",
	SquadLaunch = "SquadLaunch",
	SquadLeave = "SquadLeave",
	DeathBegan = "DeathBegan",
	DeathChoice = "DeathChoice",
	SettingsSync = "SettingsSync",
	SettingsSave = "SettingsSave",
	WeaponEquip = "WeaponEquip",
	WeaponFire = "WeaponFire",
	WeaponReload = "WeaponReload",
	WeaponHit = "WeaponHit",
	ShopSync = "ShopSync",
	PromptPurchase = "PromptPurchase",
	AmmoPickup = "AmmoPickup",
})

Remotes.Function = table.freeze({
	ShopCatalog = "ShopCatalog",
	ShopPurchase = "ShopPurchase",
})

local folder: Folder? = nil

local function getFolder(): Folder
	local current = folder
	if current then
		return current
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			folder = existing
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
		return created
	end
	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	folder = waited
	return waited
end

function Remotes.getEvent(name: string): RemoteEvent
	local parent = getFolder()
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
		return remote
	end
	return parent:WaitForChild(name) :: RemoteEvent
end

function Remotes.getFunction(name: string): RemoteFunction
	local parent = getFolder()
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteFunction") then
			return existing
		end
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = parent
		return remote
	end
	return parent:WaitForChild(name) :: RemoteFunction
end

function Remotes.init()
	for _, name in Remotes.Event do
		Remotes.getEvent(name)
	end
	for _, name in Remotes.Function do
		Remotes.getFunction(name)
	end
end

return Remotes
