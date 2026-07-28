--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local Viewmodel = require(script.Parent.Viewmodel)
local WeaponSfx = require(script.Parent.WeaponSfx)
local WeaponVfx = require(script.Parent.WeaponVfx)
local CursorMode = require(script.Parent.CursorMode)
local UiTheme = require(script.Parent.Parent.ui.UiTheme)

local WeaponController = {}

local player = Players.LocalPlayer

local triggerHeld = false
local lastShotAt = 0
local lastDryfireAt = 0
local predictedMag = 0
local localReloadUntil = 0

local ammoLabel: TextLabel? = nil
local weaponLabel: TextLabel? = nil

local function currentConfig(): WeaponsConfig.WeaponConfig?
	local weaponId = player:GetAttribute("WeaponId")
	if typeof(weaponId) ~= "string" then
		return nil
	end
	return WeaponsConfig.get(weaponId)
end

local function isAlive(): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.Health > 0
end

local function canFire(): boolean
	if CursorMode.isAnyOpen() then
		return false
	end
	if not isAlive() then
		return false
	end
	if player:GetAttribute("Reloading") == true or os.clock() < localReloadUntil then
		return false
	end
	return true
end

local function tryFire()
	local config = currentConfig()
	if not config or not canFire() then
		return
	end
	local now = os.clock()
	if now - lastShotAt < 1 / config.fireRate then
		return
	end

	if predictedMag <= 0 then
		if now - lastDryfireAt > 0.28 then
			lastDryfireAt = now
			WeaponSfx.playDryfire()
		end
		return
	end

	lastShotAt = now
	predictedMag -= 1
	local camera = Workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector

	Remotes.getEvent(Remotes.Event.WeaponFire):FireServer(origin, direction)

	WeaponSfx.playShot(config.id)
	Viewmodel.onFired(config)
	WeaponVfx.muzzleFlash(Viewmodel.getMuzzleAttachment(), config.id)
	WeaponVfx.shellEject(Viewmodel.getEjectAttachment())
end

local function tryReload()
	local config = currentConfig()
	if not config or not canFire() then
		return
	end
	local reserve = player:GetAttribute("AmmoReserve")
	if predictedMag >= config.magSize then
		return
	end
	if typeof(reserve) == "number" and reserve <= 0 then
		return
	end
	localReloadUntil = os.clock() + config.reloadTime
	Remotes.getEvent(Remotes.Event.WeaponReload):FireServer()
	WeaponSfx.playReload(config.reloadTime)
	Viewmodel.playReload(config.reloadTime)
end

local function equipSlot(slot: number)
	local weaponId = player:GetAttribute("LoadoutSlot" .. tostring(slot))
	if typeof(weaponId) ~= "string" or weaponId == "" then
		return
	end
	Remotes.getEvent(Remotes.Event.WeaponEquip):FireServer(weaponId)
end

local function buildHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeaponHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local ammo = Instance.new("TextLabel")
	ammo.Name = "Ammo"
	ammo.AnchorPoint = Vector2.new(1, 1)
	ammo.Position = UDim2.new(1, -28, 1, -26)
	ammo.Size = UDim2.fromOffset(180, 40)
	ammo.BackgroundTransparency = 1
	ammo.Font = UiTheme.FONT
	ammo.TextSize = 30
	ammo.TextXAlignment = Enum.TextXAlignment.Right
	ammo.TextColor3 = Color3.fromRGB(224, 224, 216)
	ammo.TextStrokeTransparency = 0.6
	ammo.Text = ""
	ammo.Parent = gui
	ammoLabel = ammo

	local weaponName = Instance.new("TextLabel")
	weaponName.Name = "WeaponName"
	weaponName.AnchorPoint = Vector2.new(1, 1)
	weaponName.Position = UDim2.new(1, -28, 1, -64)
	weaponName.Size = UDim2.fromOffset(220, 20)
	weaponName.BackgroundTransparency = 1
	weaponName.Font = UiTheme.FONT
	weaponName.TextSize = 14
	weaponName.TextXAlignment = Enum.TextXAlignment.Right
	weaponName.TextColor3 = Color3.fromRGB(150, 150, 144)
	weaponName.Text = ""
	weaponName.Parent = gui
	weaponLabel = weaponName

	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(3, 3)
	crosshair.BackgroundColor3 = Color3.fromRGB(230, 230, 224)
	crosshair.BackgroundTransparency = 0.25
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = crosshair
end

local function syncPredictedAmmo()
	local mag = player:GetAttribute("AmmoMag")
	if typeof(mag) == "number" then
		predictedMag = mag
	end
end

local function refreshHud()
	local mag = player:GetAttribute("AmmoMag")
	local reserve = player:GetAttribute("AmmoReserve")
	local label = ammoLabel
	if label then
		if typeof(mag) == "number" and typeof(reserve) == "number" then
			label.Text = string.format("%d / %d", mag, reserve)
			label.TextColor3 = if mag == 0
				then Color3.fromRGB(220, 90, 80)
				else Color3.fromRGB(224, 224, 216)
		else
			label.Text = ""
		end
	end
	local nameLabel = weaponLabel
	if nameLabel then
		local config = currentConfig()
		nameLabel.Text = if config then string.upper(config.displayName) else ""
	end
end

local function onWeaponChanged()
	local weaponId = player:GetAttribute("WeaponId")
	if typeof(weaponId) == "string" then
		Viewmodel.setWeapon(weaponId)
	end
	localReloadUntil = 0
	syncPredictedAmmo()
	refreshHud()
end

local function onWeaponHit(kind: string, ...: any)
	if kind == "Gong" then
		local position = ... :: Vector3
		WeaponSfx.playGong(position)
		return
	end
	if kind == "Shot" then
		local origin, hits, shooter, weaponId = ...
		local isLocal = shooter == player
		if typeof(hits) == "table" then
			for _, hit in hits :: { { position: Vector3, normal: Vector3, material: string } } do
				WeaponVfx.impact(hit.position, hit.normal, hit.material)
				local from = if isLocal then Viewmodel.getMuzzlePosition() else origin
				WeaponVfx.tracer(from, hit.position)
			end
		end
		if not isLocal and typeof(origin) == "Vector3" and typeof(weaponId) == "string" then
			WeaponSfx.playDistantShot(origin, weaponId)
		end
	end
end

function WeaponController.init()
	Viewmodel.init()
	buildHud()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
			tryFire()
		elseif input.KeyCode == Enum.KeyCode.R then
			tryReload()
		elseif input.KeyCode == Enum.KeyCode.One then
			equipSlot(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			equipSlot(2)
		elseif input.KeyCode == Enum.KeyCode.Q then
			local current = player:GetAttribute("WeaponId")
			equipSlot(if current == player:GetAttribute("LoadoutSlot1") then 2 else 1)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not triggerHeld then
			return
		end
		local config = currentConfig()
		if config and config.auto then
			tryFire()
		end
	end)

	for _, attribute in { "WeaponId" } do
		player:GetAttributeChangedSignal(attribute):Connect(onWeaponChanged)
	end
	player:GetAttributeChangedSignal("AmmoMag"):Connect(function()
		syncPredictedAmmo()
		refreshHud()
	end)
	player:GetAttributeChangedSignal("AmmoReserve"):Connect(refreshHud)
	player:GetAttributeChangedSignal("Reloading"):Connect(function()
		if player:GetAttribute("Reloading") ~= true then
			localReloadUntil = 0
		end
	end)

	Remotes.getEvent(Remotes.Event.WeaponHit).OnClientEvent:Connect(onWeaponHit)

	onWeaponChanged()
end

return WeaponController
