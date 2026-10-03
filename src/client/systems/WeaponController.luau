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
local RunController = require(script.Parent.Parent.controllers.RunController)
local HipAim = require(script.Parent.HipAim)
local AimAssist = require(script.Parent.AimAssist)
local UiSfx = require(script.Parent.UiSfx)
local UiTheme = require(script.Parent.Parent.ui.UiTheme)
local WallPullback = require(script.Parent.WallPullback)
local Stances = require(script.Parent.Stances)
local StanceConfig = require(ReplicatedStorage.Shared.config.StanceConfig)
local StanceMath = require(ReplicatedStorage.Shared.util.StanceMath)
local WeaponPickupClient = require(script.Parent.WeaponPickupClient)

local WeaponController = {}

local player = Players.LocalPlayer

-- Client-side reload, run on the same WeaponsConfig timeline as the server so the
-- predicted count changes when the hands seat the magazine (or each shell), not a
-- round trip later. The server runs its own copy of this and stays authoritative.
type ReloadState = {
	weaponId: string,
	style: string,
	startedAt: number,
	empty: boolean,
	scale: number,
	endsAt: number,
	-- magazine
	ammoAddAt: number,
	ammoAdded: boolean,
	fill: number,
	-- shell: shells planned, counted so far, and the most that will go in (fewer once
	-- fire has cancelled the loop)
	planned: number,
	loaded: number,
	limit: number,
	cancelled: boolean,
}

-- A higher AmmoMag than predicted within this long of a shot or a reload end is an
-- older update still in flight, not news. Past it the server's number wins.
local ACK_WINDOW = 0.75

local triggerHeld = false
local dryClickedThisPress = false
local lastShotAt = 0
local predictedMag = 0
local reloadState: ReloadState? = nil
local lastReloadEndedAt = 0
-- a shot pressed during a shell reload fires once the fast exit is over
local pendingShot = false
-- a shot pressed in high or low ready fires once the gun is up (Stances)
local raisePending = false
-- R: pressed when, and whether the hold has turned into a magazine check
local reloadPressedAt: number? = nil
local checkStarted = false
local magCheckLabel: TextLabel? = nil
local lastWheelSwapAt = 0
-- the mouse wheel's quick swap ignores ticks closer together than this
local WHEEL_SWAP_GAP = 0.25
local RELOAD_KEY: Enum.KeyCode = (Enum.KeyCode :: any)[StanceConfig.keys.reload] or Enum.KeyCode.R
local burstShots = 0
local lastBurstAt = 0
local tracerCounter = 0
-- client-side spread for the shooter's own predicted tracers and impacts
local shotRandom = Random.new()
local predictParams = RaycastParams.new()
predictParams.FilterType = Enum.RaycastFilterType.Exclude

-- Tracers, impact puffs and impact sounds for one shot. The shooter draws these the
-- frame the shot leaves (predictShot); everyone else draws them from the server's Shot.
local function drawShot(hits: { WeaponSfx.Hit }, from: Vector3, config: WeaponsConfig.WeaponConfig?, direction: Vector3?)
	tracerCounter += 1
	local everyThird = config ~= nil and config.auto
	local showTracer = not everyThird or tracerCounter % 3 == 0
	for _, hit in hits do
		WeaponVfx.impact(hit.position, hit.normal, hit.material)
		if showTracer then
			WeaponVfx.tracer(from, hit.position)
		end
	end
	WeaponSfx.playImpacts(hits)
	if #hits == 0 and showTracer and config and direction and direction.Magnitude > 0 then
		WeaponVfx.tracer(from, from + direction.Unit * config.range)
	end
end

local function findHumanoidModel(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- The shooter's own shot, drawn at once from a client ray with the same spread rule
-- as WeaponService. Damage stays the server's (it rays the same origin and direction
-- and validates them); waiting for its Shot reply put every tracer and impact one round
-- trip behind the muzzle flash, and the tracer then started from wherever the viewmodel
-- had moved to.
local function predictShot(config: WeaponsConfig.WeaponConfig, origin: Vector3, direction: Vector3)
	local filter: { Instance } = { Workspace.CurrentCamera }
	if player.Character then
		table.insert(filter, player.Character)
	end
	local vfxFolder = Workspace:FindFirstChild("WeaponVfx")
	if vfxFolder then
		table.insert(filter, vfxFolder)
	end
	predictParams.FilterDescendantsInstances = filter
	local hits: { WeaponSfx.Hit } = {}
	local unit = direction.Unit
	for _ = 1, config.pellets do
		local shotDirection = unit
		if config.pellets > 1 or config.spreadDeg > 0 then
			local spread = math.rad(config.spreadDeg)
			local up = if math.abs(unit.Y) > 0.999 then Vector3.xAxis else Vector3.yAxis
			shotDirection = (CFrame.lookAt(Vector3.zero, unit, up) * CFrame.Angles(shotRandom:NextNumber(-spread, spread), shotRandom:NextNumber(-spread, spread), 0)).LookVector
		end
		local result = Workspace:Raycast(origin, shotDirection * config.range, predictParams)
		if result then
			local model = findHumanoidModel(result.Instance)
			local isZombie = model ~= nil and Players:GetPlayerFromCharacter(model) == nil
			table.insert(hits, {
				position = result.Position,
				normal = result.Normal,
				material = if isZombie then "Flesh" else result.Instance.Material.Name,
			})
		end
	end
	drawShot(hits, Viewmodel.getMuzzlePosition(), config, direction)
end
local lastWeaponId: string? = nil
local previousWeaponId: string? = nil
-- the Studio "empty" debug command fakes an empty mag; keep reconcile off it for a bit
local holdPredictionUntil = 0

local ammoLabel: TextLabel? = nil
local weaponLabel: TextLabel? = nil

local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
}

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

local function canAct(): boolean
	return not CursorMode.isAnyOpen() and isAlive()
end

-- SkillEffects.reloadScale, replicated by the server so the client timeline matches.
local function reloadScale(): number
	local scale = player:GetAttribute("ReloadScale")
	return if typeof(scale) == "number" and scale > 0 then scale else 1
end

local function reserveCount(): number
	local reserve = player:GetAttribute("AmmoReserve")
	return if typeof(reserve) == "number" then reserve else 0
end

local function carrierVelocity(): Vector3
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.AssemblyLinearVelocity
	end
	return Vector3.zero
end

local function ejectCasing(config: WeaponsConfig.WeaponConfig)
	WeaponVfx.ejectCasing(Viewmodel.getEjectAttachment(), config.casing, carrierVelocity())
end

local function finishReload()
	reloadState = nil
	lastReloadEndedAt = os.clock()
end

-- Counts what the reload has seated by `now` and ends it when its time is up.
local function advanceReload(now: number)
	local reload = reloadState
	if not reload then
		return
	end
	local config = WeaponsConfig.get(reload.weaponId)
	if not config then
		finishReload()
		return
	end
	if reload.style == "shell" then
		while reload.loaded < reload.limit do
			if now < reload.startedAt + WeaponsConfig.shellAddTime(config, reload.loaded + 1, reload.scale) then
				break
			end
			reload.loaded += 1
			predictedMag = math.min(predictedMag + 1, config.magSize)
		end
	elseif not reload.ammoAdded and now >= reload.ammoAddAt then
		reload.ammoAdded = true
		predictedMag = reload.fill
	end
	if now >= reload.endsAt then
		finishReload()
	end
end

-- Fire pressed during a shell reload: the shell in the hand still goes in, then a fast
-- exit (plus the pump if nothing is chambered) and the buffered shot. Returns
-- "cancelled", "late" when the loop is already over (ReloadToIdle playing), or "empty"
-- when stopping now would leave nothing to fire.
local function cancelShellReload(config: WeaponsConfig.WeaponConfig, reload: ReloadState, now: number): string
	local shell = config.shellReload
	if not shell then
		return "late"
	end
	local limit, readyAfter = WeaponsConfig.shellCancel(config, now - reload.startedAt, reload.planned, reload.empty, reload.scale)
	limit = math.clamp(limit, reload.loaded, reload.limit)
	local readyAt = reload.startedAt + readyAfter
	if readyAt >= reload.endsAt then
		return "late"
	end
	if predictedMag + (limit - reload.loaded) <= 0 then
		return "empty"
	end
	local finishShell = limit > reload.loaded
	reload.cancelled = true
	reload.limit = limit
	reload.endsAt = readyAt
	Remotes.getEvent(Remotes.Event.WeaponReloadCancel):FireServer()
	Viewmodel.cancelReload({
		exit = shell.exit * reload.scale,
		chamber = if reload.empty then shell.chamber * reload.scale else nil,
		finishShell = finishShell,
	})
	return "cancelled"
end

-- `pressed` is a fresh trigger press (not the auto-fire repeat): it can cancel a shell
-- reload and it arms the one dry click per press.
local function tryFire(pressed: boolean)
	local config = currentConfig()
	if not config or not canAct() then
		return
	end
	-- fully pulled back against a wall: the muzzle is inside it, nothing leaves until
	-- it clears (partly pulled back, the gun fires)
	if WallPullback.blocksFire() then
		return
	end
	local now = os.clock()
	if Viewmodel.drawElapsed() < config.drawTime then
		return
	end

	local reload = reloadState
	if reload then
		local sameWeapon = reload.weaponId == config.id
		if sameWeapon and reload.style == "shell" then
			if pressed then
				local result = if reload.cancelled then "cancelled" else cancelShellReload(config, reload, now)
				if result ~= "empty" then
					pendingShot = true
				end
			end
			return
		elseif sameWeapon and not reload.ammoAdded then
			-- before ammo-add nothing fires and the old count stands
			return
		end
		-- another weapon's reload, or the magazine is seated: the shot cuts the rest
		finishReload()
	end

	-- from high or low ready (or a magazine check) the gun comes up first; the press
	-- fires once it is up
	if not Stances.requestFire(config.class) then
		if pressed then
			raisePending = true
		end
		return
	end

	if now - lastShotAt < 1 / config.fireRate then
		return
	end

	if predictedMag <= 0 then
		if not dryClickedThisPress then
			dryClickedThisPress = true
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
	local direction = HipAim.fireDirection(origin) or AimAssist.adjustFireDirection(origin, camera.CFrame.LookVector)

	Remotes.getEvent(Remotes.Event.WeaponFire):FireServer(origin, direction)

	WeaponSfx.playShot(config.id, predictedMag, Viewmodel.getMuzzlePosition())
	Viewmodel.onFired(config)
	WeaponVfx.muzzleFlash(Viewmodel.getMuzzleAttachment(), config.id)
	predictShot(config, origin, direction)
	-- the pump ejects its hull on the pump stroke instead (see the phase listener)
	if config.ejectOnFire then
		ejectCasing(config)
	end
end

local function tryReload()
	local config = currentConfig()
	if not config or not canAct() or reloadState then
		return
	end
	Stances.cancelCheck()
	local now = os.clock()
	if Viewmodel.drawElapsed() < config.drawTime then
		return
	end
	-- the action is still cycling (the pump after a shot): let it close first
	if now - lastShotAt < 1 / config.fireRate then
		return
	end
	local reserve = reserveCount()
	if predictedMag >= config.magSize or reserve <= 0 then
		return
	end

	local scale = reloadScale()
	local empty = predictedMag <= 0
	local reload: ReloadState = {
		weaponId = config.id,
		style = "magazine",
		startedAt = now,
		empty = empty,
		scale = scale,
		endsAt = now,
		ammoAddAt = now,
		ammoAdded = false,
		fill = math.min(config.magSize, predictedMag + reserve),
		planned = 0,
		loaded = 0,
		limit = 0,
		cancelled = false,
	}
	if config.reloadStyle == "shell" and config.shellReload then
		local shells = math.min(config.magSize - predictedMag, reserve)
		reload.style = "shell"
		reload.planned = shells
		reload.limit = shells
		reload.endsAt = now + WeaponsConfig.shellReloadTime(config, shells, empty, scale)
	else
		local ammoAdd, total = WeaponsConfig.magazineReload(config, empty, scale)
		reload.ammoAddAt = now + ammoAdd
		reload.endsAt = now + total
	end
	reloadState = reload
	pendingShot = false

	Remotes.getEvent(Remotes.Event.WeaponReload):FireServer()
	Viewmodel.playReload({ config = config, empty = empty, shells = reload.planned, scale = scale })
end

local function requestEquip(weaponId: string)
	if player:GetAttribute("WeaponId") == weaponId then
		return
	end
	local current = currentConfig()
	if current then
		WeaponSfx.playPhase("Holster", current.class)
	end
	Remotes.getEvent(Remotes.Event.WeaponEquip):FireServer(weaponId)
end

local function equipSlot(slot: number)
	local weaponId = player:GetAttribute("LoadoutSlot" .. tostring(slot))
	if typeof(weaponId) ~= "string" or weaponId == "" then
		return
	end
	requestEquip(weaponId)
end

-- Number keys: loadout slots 1 and 2 normally. With the temporary
-- WeaponsConfig.ALL_WEAPONS_UNLOCKED test flag, key N takes WeaponsConfig.order[N]
-- whether it is owned or not (keys past the list do nothing).
local function selectNumber(index: number)
	if WeaponsConfig.ALL_WEAPONS_UNLOCKED then
		local weaponId = WeaponsConfig.order[index]
		if weaponId then
			requestEquip(weaponId)
		end
	elseif index <= 2 then
		equipSlot(index)
	end
end

-- The mouse wheel (Q leans now, Stances): back to the previous weapon when testing with
-- every weapon unlocked, otherwise the loadout slot toggle.
local function quickSwap()
	local previous = previousWeaponId
	if WeaponsConfig.ALL_WEAPONS_UNLOCKED and previous then
		requestEquip(previous)
		return
	end
	local current = player:GetAttribute("WeaponId")
	equipSlot(if current == player:GetAttribute("LoadoutSlot1") then 2 else 1)
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
	HipAim.bindCrosshair(crosshair)

	-- the magazine check's count (hold R), only while the weapon is tipped in
	local check = Instance.new("TextLabel")
	check.Name = "MagCheck"
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = UDim2.fromScale(0.5, 0.7)
	check.Size = UDim2.fromOffset(220, 34)
	check.BackgroundTransparency = 1
	check.Font = UiTheme.FONT
	check.TextSize = 24
	check.TextColor3 = Color3.fromRGB(224, 224, 216)
	check.TextStrokeTransparency = 0.5
	check.Text = ""
	check.Visible = false
	check.Parent = gui
	magCheckLabel = check
end

-- The check's count from the client's own count, shown only while the weapon is tipped
-- toward the camera; optionally the corner counter is hidden outside a check.
local function updateMagCheck()
	local config = currentConfig()
	local showing = config ~= nil and Stances.countVisible()
	local label = magCheckLabel
	if label then
		label.Visible = showing
		if showing and config then
			label.Text = StanceMath.readout(StanceConfig.MAG_CHECK.readout, predictedMag, config.magSize)
		end
	end
	local counter = ammoLabel
	if counter then
		counter.Visible = not StanceConfig.MAG_CHECK.hideAmmoCounter or showing
	end
end

-- Hold R: once held past MAG_CHECK.holdTime with the pack viewmodel up and no reload
-- running, the press is a magazine check instead of a reload.
local function updateReloadHold(now: number)
	local pressedAt = reloadPressedAt
	if not pressedAt or checkStarted then
		return
	end
	if StanceMath.isHold(StanceConfig :: any, now - pressedAt) and Stances.posesShown() and not reloadState and canAct() then
		checkStarted = true
		Stances.startCheck()
	end
end

-- The server only lowers AmmoMag on a shot, so a lower value than predicted is news
-- (a shot it rejected, a reload it refused). A higher one right after a shot is usually
-- an older update still in flight; reconcileAmmo takes it once things are quiet. While
-- a local reload runs the prediction owns the count.
local function syncPredictedAmmo(force: boolean?)
	local mag = player:GetAttribute("AmmoMag")
	if typeof(mag) ~= "number" then
		return
	end
	if force or (reloadState == nil and mag < predictedMag) then
		predictedMag = mag
	end
end

local function reconcileAmmo(now: number)
	if reloadState or now < holdPredictionUntil or now - lastShotAt < ACK_WINDOW or now - lastReloadEndedAt < ACK_WINDOW then
		return
	end
	local mag = player:GetAttribute("AmmoMag")
	if typeof(mag) == "number" and mag ~= predictedMag then
		predictedMag = mag
	end
end

local function refreshHud()
	local mag = player:GetAttribute("AmmoMag")
	local reserve = player:GetAttribute("AmmoReserve")
	local label = ammoLabel
	if label then
		if typeof(mag) == "number" and typeof(reserve) == "number" then
			local config = currentConfig()
			local low = config ~= nil and mag <= config.lowAmmo
			label.Text = string.format("%d / %d", mag, reserve)
			label.TextColor3 = if mag == 0
				then Color3.fromRGB(220, 90, 80)
				elseif low then Color3.fromRGB(232, 176, 84)
				else Color3.fromRGB(224, 224, 216)
		else
			label.Text = ""
		end
	end
	local nameLabel = weaponLabel
	if nameLabel then
		local config = currentConfig()
		local level = player:GetAttribute("WeaponLevel")
		local upgraded = typeof(level) == "number" and level > 1
		nameLabel.Text = if config
			then string.upper(config.displayName) .. (if upgraded then string.format("  L%d", level) else "")
			else ""
		nameLabel.TextColor3 = if upgraded then UiTheme.ACCENT else Color3.fromRGB(150, 150, 144)
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
	-- a swap cancels the reload (the server keeps whatever it had counted) and any
	-- buffered shot; reset before setWeapon, which can yield while the rig loads
	reloadState = nil
	pendingShot = false
	raisePending = false
	Stances.cancelCheck()
	lastShotAt = 0
	lastReloadEndedAt = 0
	syncPredictedAmmo(true)
	refreshHud()
	if typeof(weaponId) == "string" then
		if lastWeaponId and lastWeaponId ~= weaponId then
			previousWeaponId = lastWeaponId
		end
		lastWeaponId = weaponId
		Viewmodel.setWeapon(weaponId)
	end
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
		-- the shooter already drew this shot when it left (predictShot)
		if not isLocal and typeof(hits) == "table" and typeof(origin) == "Vector3" then
			drawShot(hits :: { WeaponSfx.Hit }, origin, config, nil)
		end
		if not isLocal and typeof(origin) == "Vector3" and typeof(weaponId) == "string" then
			WeaponSfx.playDistantShot(origin, weaponId)
		end
	end
end

-- Studio-only hook so animation work can be driven and screenshotted without
-- synthetic mouse input, which does not reach the client under a locked cursor.
local function installDebugHook()
	if not RunService:IsStudio() then
		return
	end
	local existing = ReplicatedStorage:FindFirstChild("DebugWeapon")
	if existing then
		existing:Destroy()
	end
	local bindable = Instance.new("BindableEvent")
	bindable.Name = "DebugWeapon"
	bindable.Parent = ReplicatedStorage
	bindable.Event:Connect(function(command: string)
		if command == "fire" then
			dryClickedThisPress = false
			tryFire(true)
		elseif command == "reload" then
			tryReload()
		elseif command == "inspect" then
			Viewmodel.toggleInspect()
		elseif command == "stance" then
			Stances.cycleStance()
			print("[DebugWeapon] " .. Stances.describe())
		elseif command == "magcheck" then
			Stances.startCheck()
		elseif command == "magcheck_end" then
			Stances.releaseCheck()
		elseif command == "lean_left" or command == "lean_right" or command == "lean_off" then
			Stances.setDebugLean(if command == "lean_left" then -1 elseif command == "lean_right" then 1 else nil)
		elseif command == "preview_tactical" or command == "preview_empty" then
			-- the reload animation alone, with no reload behind it: slowed down with the
			-- camera's ViewmodelTimeScale it is not cut short when the server's reload ends
			local config = currentConfig()
			if config then
				local empty = command == "preview_empty"
				local shells = if config.reloadStyle == "shell" then math.min(3, config.magSize) else 0
				Viewmodel.playReload({ config = config, empty = empty, shells = shells, scale = 1 })
			end
		elseif command == "empty" then
			predictedMag = 0
			holdPredictionUntil = os.clock() + 5
		elseif command == "clearmodals" then
			for _, id in { "GoreWarning", "Shop", "Settings", "SquadLobby", "DeathResults" } do
				CursorMode.setModalOpen(id, false)
			end
		elseif command == "freeze" then
			-- Stops the forward run so a static target range stays in front of you.
			-- Without this the runner leaves the dummies behind within a second.
			RunController.stop()
		elseif command == "unfreeze" then
			RunController.start(true)
		elseif command == "state" then
			local reload = reloadState
			print(string.format(
				"[DebugWeapon] modalOpen=%s alive=%s reloading=%s local=%s predictedMag=%d weapon=%s",
				tostring(CursorMode.isAnyOpen()),
				tostring(isAlive()),
				tostring(player:GetAttribute("Reloading")),
				if reload then reload.style else "none",
				predictedMag,
				tostring(player:GetAttribute("WeaponId"))))
		end
	end)
end

-- Clip markers: reload foley, and the pump's hull. BoltBack tagged "fire" is the pump
-- stroke after a shot; the chambering pump after a reload ("chamber") ejects nothing.
local function onPhase(phase: string, class: string, tag: string?)
	WeaponSfx.playPhase(phase, class, tag)
	if phase == "BoltBack" and tag == "fire" then
		local config = currentConfig()
		if config and config.class == class and not config.ejectOnFire then
			ejectCasing(config)
		end
	end
end

function WeaponController.init()
	Viewmodel.init()
	Stances.init()
	Viewmodel.onPhase(onPhase)
	WeaponVfx.onCasingLanded(WeaponSfx.playCasingLand)
	-- the pickups' outlines and toasts start with the weapons
	WeaponPickupClient.init()
	buildHud()
	installDebugHook()
	task.spawn(WeaponSfx.preload)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local slot = NUMBER_KEYS[input.KeyCode]
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
			dryClickedThisPress = false
			tryFire(true)
		elseif input.KeyCode == RELOAD_KEY then
			-- a short press reloads on release; a hold is the magazine check
			reloadPressedAt = os.clock()
			checkStarted = false
		elseif slot then
			selectNumber(slot)
		elseif input.KeyCode == Enum.KeyCode.F then
			if not reloadState then
				Viewmodel.toggleInspect()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		elseif input.KeyCode == RELOAD_KEY and reloadPressedAt then
			reloadPressedAt = nil
			if checkStarted then
				checkStarted = false
				Stances.releaseCheck()
			else
				tryReload()
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local now = os.clock()
		if now - lastWheelSwapAt >= WHEEL_SWAP_GAP then
			lastWheelSwapAt = now
			quickSwap()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		advanceReload(now)
		reconcileAmmo(now)
		updateReloadHold(now)
		updateMagCheck()
		if pendingShot and not reloadState then
			pendingShot = false
			tryFire(false)
		end
		if raisePending and not Stances.isRaising() then
			raisePending = false
			tryFire(false)
		end
		if triggerHeld then
			local config = currentConfig()
			if config and config.auto then
				tryFire(false)
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
	player:GetAttributeChangedSignal("WeaponLevel"):Connect(refreshHud)

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
