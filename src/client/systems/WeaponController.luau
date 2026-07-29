--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local Viewmodel = require(script.Parent.Viewmodel)
local WeaponSfx = require(script.Parent.WeaponSfx)
local WeaponVfx = require(script.Parent.WeaponVfx)
local CursorMode = require(script.Parent.CursorMode)
local UiSfx = require(script.Parent.UiSfx)
local UiTheme = require(script.Parent.Parent.ui.UiTheme)

local WeaponController = {}

local player = Players.LocalPlayer

local triggerHeld = false
local lastShotAt = 0
local lastDryfireAt = 0
local predictedMag = 0
local localReloadUntil = 0
local burstShots = 0
local lastBurstAt = 0
local tracerCounter = 0

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
	burstShots += 1
	lastBurstAt = now
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

local function showPickup(rounds: number)
	local gui = ammoLabel and ammoLabel.Parent
	if not gui or not gui:IsA("ScreenGui") then
		return
	end
	local toast = Instance.new("TextLabel")
	toast.Name = "PickupToast"
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(0.5, 0.62)
	toast.Size = UDim2.fromOffset(240, 28)
	toast.BackgroundTransparency = 1
	toast.Font = UiTheme.FONT
	toast.TextSize = 20
	toast.TextColor3 = Color3.fromRGB(140, 226, 150)
	toast.TextStrokeTransparency = 0.6
	toast.Text = string.format("+%d AMMO", rounds)
	toast.Parent = gui

	TweenService:Create(toast, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.56),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.2, function()
		toast:Destroy()
	end)

	local label = ammoLabel
	if label then
		label.TextColor3 = Color3.fromRGB(140, 226, 150)
		task.delay(0.35, refreshHud)
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
		local config = if typeof(weaponId) == "string" then WeaponsConfig.get(weaponId) else nil
		tracerCounter += 1
		local everyThird = config ~= nil and config.auto
		local showTracer = not everyThird or tracerCounter % 3 == 0
		if typeof(hits) == "table" then
			local from = if isLocal then Viewmodel.getMuzzlePosition() else origin
			for _, hit in hits :: { { position: Vector3, normal: Vector3, material: string } } do
				WeaponVfx.impact(hit.position, hit.normal, hit.material)
				if showTracer then
					WeaponVfx.tracer(from, hit.position)
				end
			end
			if #hits == 0 and showTracer and config and typeof(origin) == "Vector3" then
				local direction = if isLocal
					then Workspace.CurrentCamera.CFrame.LookVector
					else Vector3.new(0, 0, 0)
				if direction.Magnitude > 0 then
					WeaponVfx.tracer(from, from + direction * config.range)
				end
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
	task.spawn(WeaponSfx.preload)

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
		elseif input.KeyCode == Enum.KeyCode.F then
			Viewmodel.toggleInspect()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		if triggerHeld then
			local config = currentConfig()
			if config and config.auto then
				tryFire()
			end
			return
		end
		if burstShots >= 3 and os.clock() - lastBurstAt > 0.35 then
			WeaponVfx.barrelSmoke(Viewmodel.getMuzzleAttachment())
			burstShots = 0
		elseif burstShots > 0 and os.clock() - lastBurstAt > 0.35 then
			burstShots = 0
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
	Remotes.getEvent(Remotes.Event.AmmoPickup).OnClientEvent:Connect(function(rounds, position)
		if typeof(rounds) ~= "number" then
			return
		end
		showPickup(rounds)
		UiSfx.rewardTick()
		if typeof(position) == "Vector3" then
			WeaponVfx.pickupBurst(position)
		end
	end)

	onWeaponChanged()
end

return WeaponController
