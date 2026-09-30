--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ProfileManager = require(script.Parent.ProfileManager)
local SkillEffects = require(script.Parent.SkillEffects)
local MissionGoals = require(script.Parent.MissionGoals)
local RunEconomy = require(script.Parent.RunEconomy)

local WeaponService = {}

-- A reload in progress, on the WeaponsConfig timeline the client predicts with. It is
-- advanced every Heartbeat and again right before a shot is judged, so a shot that
-- arrives just after the ammo-add sees the rounds.
type ReloadJob = {
	style: string,
	startedAt: number,
	empty: boolean,
	scale: number,
	endsAt: number,
	-- magazine: the mag seats here; after it a shot may cut the tail
	ammoAddAt: number,
	ammoAdded: boolean,
	-- shell: planned, counted so far, most that will go in (lowered by a cancel)
	planned: number,
	loaded: number,
	limit: number,
	cancelled: boolean,
}

type PlayerWeaponState = {
	weaponId: string,
	mag: number,
	reserve: number,
	lastFireAt: number,
	reload: ReloadJob?,
	-- no shots before this (the draw after an equip)
	drawUntil: number,
}

-- The client starts its reload one trip earlier than the server and its shots arrive
-- one trip later, so both sides line up on the same timeline; this only absorbs jitter.
local SYNC_TOLERANCE = 0.1
local ORIGIN_TOLERANCE = 5
local RATE_TOLERANCE = 0.97
local GONG_COOLDOWN = 0.8
local MAX_YAW_COSINE = math.cos(math.rad(100))
local MAX_PITCH_SINE = math.sin(math.rad(85))

type AmmoSnapshot = { mag: number, reserve: number, lastFireAt: number }

local states: { [Player]: PlayerWeaponState } = {}
local savedAmmo: { [Player]: { [string]: AmmoSnapshot } } = {}
-- the loadout for the current run once a pickup replaced a slot: the profile's loadout
-- with the found weapons in, gone when the run ends (WeaponPickups, MissionService)
local runLoadout: { [Player]: { string } } = {}
local random = Random.new()
local lastGongAt: { [Player]: number } = {}

local function syncAttributes(player: Player, state: PlayerWeaponState)
	player:SetAttribute("WeaponId", state.weaponId)
	player:SetAttribute("AmmoMag", state.mag)
	player:SetAttribute("AmmoReserve", state.reserve)
end

local function defaultState(weaponId: string): PlayerWeaponState
	local config = WeaponsConfig.get(weaponId)
	local magSize = if config then config.magSize else 0
	local reserve = if config then config.magSize * config.reserveMags else 0
	return {
		weaponId = weaponId,
		mag = magSize,
		reserve = reserve,
		lastFireAt = 0,
		reload = nil,
		drawUntil = 0,
	}
end

local function endReload(player: Player, state: PlayerWeaponState)
	state.reload = nil
	player:SetAttribute("Reloading", false)
end

-- Applies whatever the reload has reached by `now`: the magazine's ammo-add, each shell
-- at its add point, and the end. Attributes are synced on every count change so the
-- HUD ticks per shell.
-- A full magazine and reserve, as a hub refill and a found gun give.
local function fillWeapon(player: Player, state: PlayerWeaponState, config: WeaponsConfig.WeaponConfig)
	state.mag = config.magSize
	state.reserve = config.magSize * config.reserveMags
	endReload(player, state)
	syncAttributes(player, state)
end

local function advanceReload(player: Player, state: PlayerWeaponState, now: number)
	local job = state.reload
	if not job then
		return
	end
	local config = WeaponsConfig.get(state.weaponId)
	if not config then
		endReload(player, state)
		return
	end
	local changed = false
	if job.style == "shell" then
		while job.loaded < job.limit do
			if now < job.startedAt + WeaponsConfig.shellAddTime(config, job.loaded + 1, job.scale) then
				break
			end
			if state.mag >= config.magSize or state.reserve <= 0 then
				job.limit = job.loaded
				break
			end
			state.mag += 1
			state.reserve -= 1
			job.loaded += 1
			changed = true
		end
	elseif not job.ammoAdded and now >= job.ammoAddAt then
		local taken = math.min(config.magSize - state.mag, state.reserve)
		state.mag += taken
		state.reserve -= taken
		job.ammoAdded = true
		changed = true
	end
	if changed then
		syncAttributes(player, state)
	end
	if now >= job.endsAt then
		endReload(player, state)
	end
end

-- The loadout the 1 and 2 keys read: the run's once a pickup changed it, else the
-- profile's.
local function loadoutFor(player: Player): { string }
	local override = runLoadout[player]
	if override then
		return override
	end
	local data = ProfileManager.get(player)
	return if data then data.Loadout else { "Pistol" }
end

local function ownsWeapon(player: Player, weaponId: string): boolean
	local override = runLoadout[player]
	if override and table.find(override, weaponId) then
		return true
	end
	local data = ProfileManager.get(player)
	if not data then
		return weaponId == "Pistol"
	end
	return data.WeaponsOwned[weaponId] ~= nil
end

local function syncLoadout(player: Player)
	local loadout = loadoutFor(player)
	player:SetAttribute("LoadoutSlot1", loadout[1] or "Pistol")
	player:SetAttribute("LoadoutSlot2", loadout[2] or "")
end

local function onEquip(player: Player, weaponId: any)
	if typeof(weaponId) ~= "string" then
		return
	end
	local config = WeaponsConfig.get(weaponId)
	-- ALL_WEAPONS_UNLOCKED is the temporary test flag: any weapon, owned or not
	if not config or not (WeaponsConfig.ALL_WEAPONS_UNLOCKED or ownsWeapon(player, weaponId)) then
		return
	end
	local current = states[player]
	if current and current.weaponId == weaponId then
		return
	end

	local saved = savedAmmo[player]
	if not saved then
		saved = {}
		savedAmmo[player] = saved
	end
	if current then
		saved[current.weaponId] = { mag = current.mag, reserve = current.reserve, lastFireAt = current.lastFireAt }
	end

	-- a reload in progress is dropped with the old state: before its ammo-add the old
	-- count stands, shells already in stay in
	local state = defaultState(weaponId)
	local prior = saved[weaponId]
	if prior then
		state.mag = prior.mag
		state.reserve = prior.reserve
		state.lastFireAt = prior.lastFireAt
	end
	state.drawUntil = os.clock() + config.drawTime
	states[player] = state
	player:SetAttribute("Reloading", false)
	-- the client runs its reload prediction with this, so it has to be there before the
	-- first reload request
	player:SetAttribute("ReloadScale", SkillEffects.reloadScale(player))
	syncAttributes(player, state)
end

local function characterOrigin(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function applySpread(direction: Vector3, spreadDeg: number): Vector3
	local spread = math.rad(spreadDeg)
	local yaw = random:NextNumber(-spread, spread)
	local pitch = random:NextNumber(-spread, spread)
	local up = if math.abs(direction.Y) > 0.999 then Vector3.xAxis else Vector3.yAxis
	return (CFrame.lookAt(Vector3.zero, direction, up) * CFrame.Angles(pitch, yaw, 0)).LookVector
end

local function findZombieModel(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function handleHit(player: Player, config: WeaponsConfig.WeaponConfig, result: RaycastResult)
	local part = result.Instance
	if part.Name == "RangeGong" then
		local now = os.clock()
		if now - (lastGongAt[player] or 0) >= GONG_COOLDOWN then
			lastGongAt[player] = now
			Remotes.getEvent(Remotes.Event.WeaponHit):FireAllClients("Gong", result.Position)
		end
		return
	end

	local model = findZombieModel(part)
	if not model then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if Players:GetPlayerFromCharacter(model) then
		return
	end

	local data = ProfileManager.get(player)
	local progress = if data then data.WeaponsOwned[config.id] else nil
	local level = if progress then progress.level else 1
	local damage = WeaponsConfig.damageAt(config, level)
	local headshot = part.Name == "Head"
	if headshot then
		damage *= config.headshotMultiplier
	end
	local wasAlive = humanoid.Health > 0
	humanoid:TakeDamage(damage)
	if wasAlive and humanoid.Health <= 0 then
		ProfileManager.addKill(player)
		MissionGoals.report(player, "Kills", 1)
		-- the kill pays into the run balance at once (RunEconomy)
		local zombieId = model:GetAttribute("ZombieId")
		RunEconomy.onKill(player, if typeof(zombieId) == "string" then zombieId else nil, headshot)
		if progress then
			progress.xp += WeaponsConfig.XP_PER_KILL
		end
	end
end

local function onFire(player: Player, origin: any, direction: any)
	local state = states[player]
	if not state then
		return
	end
	local config = WeaponsConfig.get(state.weaponId)
	if not config then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local directionMagnitude = direction.Magnitude
	if not (directionMagnitude > 0.9 and directionMagnitude < 1.1) then
		return
	end

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if now < state.drawUntil then
		return
	end
	if state.reload then
		advanceReload(player, state, now + SYNC_TOLERANCE)
		local job = state.reload
		if job then
			if job.style == "magazine" and job.ammoAdded then
				-- the magazine is seated: firing cuts the rest of the reload
				endReload(player, state)
			else
				return
			end
		end
	end
	if now - state.lastFireAt < (1 / config.fireRate) * RATE_TOLERANCE then
		return
	end
	if state.mag <= 0 then
		return
	end
	local anchor = characterOrigin(player)
	if not anchor then
		return
	end
	local toOrigin = origin - anchor
	local originDistance = toOrigin.Magnitude
	if not (originDistance <= ORIGIN_TOLERANCE) then
		return
	end
	if originDistance > 0.05 then
		local losParams = RaycastParams.new()
		losParams.FilterType = Enum.RaycastFilterType.Exclude
		-- only world geometry may block the head-to-camera gap: a zombie hit box pressed
		-- against the player (a grab, a lunge) must not swallow a point-blank shot
		local ignore: { Instance } = if character then { character } else {}
		local zombies = Workspace:FindFirstChild("Zombies")
		if zombies then
			table.insert(ignore, zombies)
		end
		losParams.FilterDescendantsInstances = ignore
		if Workspace:Raycast(anchor, toOrigin, losParams) then
			return
		end
	end

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local facing = root.CFrame.LookVector
		local flatFacing = Vector3.new(facing.X, 0, facing.Z)
		local flatShot = Vector3.new(direction.X, 0, direction.Z)
		if flatFacing.Magnitude > 0.01 and flatShot.Magnitude > 0.01 then
			local yawCosine = flatFacing.Unit:Dot(flatShot.Unit)
			if not (yawCosine >= MAX_YAW_COSINE) then
				return
			end
		end
		if not (math.abs(direction.Y) <= MAX_PITCH_SINE) then
			return
		end
	end

	state.lastFireAt = now
	state.mag -= 1
	syncAttributes(player, state)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = {}
	if character then
		table.insert(filter, character)
	end
	params.FilterDescendantsInstances = filter

	local hits: { { position: Vector3, normal: Vector3, material: string } } = {}
	for _ = 1, config.pellets do
		local shotDirection = if config.pellets > 1 or config.spreadDeg > 0
			then applySpread(direction.Unit, config.spreadDeg)
			else direction.Unit
		local result = Workspace:Raycast(origin, shotDirection * config.range, params)
		if result then
			handleHit(player, config, result)
			local zombieModel = findZombieModel(result.Instance)
			local isZombie = zombieModel ~= nil and Players:GetPlayerFromCharacter(zombieModel) == nil
			table.insert(hits, {
				position = result.Position,
				normal = result.Normal,
				material = if isZombie then "Flesh" else result.Instance.Material.Name,
			})
		end
	end

	Remotes.getEvent(Remotes.Event.WeaponHit):FireAllClients("Shot", origin, hits, player, state.weaponId)
end

local function onReload(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local config = WeaponsConfig.get(state.weaponId)
	if not config then
		return
	end
	local now = os.clock()
	if state.reload or now < state.drawUntil then
		return
	end
	if state.mag >= config.magSize or state.reserve <= 0 then
		return
	end

	local scale = SkillEffects.reloadScale(player)
	player:SetAttribute("ReloadScale", scale)
	local empty = state.mag <= 0
	local job: ReloadJob = {
		style = "magazine",
		startedAt = now,
		empty = empty,
		scale = scale,
		endsAt = now,
		ammoAddAt = now,
		ammoAdded = false,
		planned = 0,
		loaded = 0,
		limit = 0,
		cancelled = false,
	}
	if config.reloadStyle == "shell" and config.shellReload then
		local shells = math.min(config.magSize - state.mag, state.reserve)
		job.style = "shell"
		job.planned = shells
		job.limit = shells
		job.endsAt = now + WeaponsConfig.shellReloadTime(config, shells, empty, scale)
	else
		local ammoAdd, total = WeaponsConfig.magazineReload(config, empty, scale)
		job.ammoAddAt = now + ammoAdd
		job.endsAt = now + total
	end
	state.reload = job
	player:SetAttribute("Reloading", true)
end

-- Fire pressed during a reload. Shells: the one in the hand is still counted, the loop
-- stops, and the job lives on through the fast exit (plus the pump from empty), which
-- is what keeps fire blocked for that window. Magazines: before ammo-add the old count
-- stands, after it the tail is cut; either way the reload ends now.
local function onReloadCancel(player: Player)
	local state = states[player]
	if not state or not state.reload then
		return
	end
	local config = WeaponsConfig.get(state.weaponId)
	if not config then
		return
	end
	local now = os.clock()
	advanceReload(player, state, now)
	local job = state.reload
	if not job then
		return
	end
	if job.style ~= "shell" then
		endReload(player, state)
		return
	end
	if job.cancelled then
		return
	end
	local limit, readyAfter = WeaponsConfig.shellCancel(config, now - job.startedAt, job.planned, job.empty, job.scale)
	job.cancelled = true
	job.limit = math.clamp(limit, job.loaded, job.limit)
	job.endsAt = math.min(job.endsAt, job.startedAt + readyAfter)
end

function WeaponService.applyLoadout(player: Player)
	syncLoadout(player)
	if not ProfileManager.get(player) then
		return
	end
	local loadout = loadoutFor(player)
	local state = states[player]
	if state and table.find(loadout, state.weaponId) then
		return
	end
	local primary = loadout[1]
	if typeof(primary) == "string" then
		onEquip(player, primary)
	end
end

function WeaponService.equip(player: Player, weaponId: string)
	onEquip(player, weaponId)
end

-- A weapon found in the world (WeaponPickups): it takes the slot of the weapon in hand
-- for the rest of the run and is equipped the way a loadout equip is, full. Finding a
-- weapon already carried refills that one instead. False for an unknown id.
function WeaponService.pickUp(player: Player, weaponId: string): boolean
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return false
	end
	local loadout = table.clone(loadoutFor(player))
	local current = states[player]
	local slot = table.find(loadout, weaponId)
		or (if current then table.find(loadout, current.weaponId) else nil)
		or 1
	loadout[slot] = weaponId
	runLoadout[player] = loadout
	-- a found gun is full: the ammo it had the last time it was carried is forgotten
	local saved = savedAmmo[player]
	if saved then
		saved[weaponId] = nil
	end
	if current and current.weaponId == weaponId then
		fillWeapon(player, current, config)
	else
		onEquip(player, weaponId)
	end
	syncLoadout(player)
	return true
end

-- The run is over: the found weapons go with it and the profile's loadout is back in
-- the slots; a hand still holding a found weapon draws the profile's primary.
function WeaponService.clearRunLoadout(player: Player)
	if not runLoadout[player] then
		return
	end
	runLoadout[player] = nil
	WeaponService.applyLoadout(player)
end

function WeaponService.addReserve(player: Player, rounds: number)
	local state = states[player]
	if not state or rounds <= 0 then
		return
	end
	local config = WeaponsConfig.get(state.weaponId)
	if not config then
		return
	end
	local cap = config.magSize * config.reserveMags
	state.reserve = math.min(state.reserve + math.floor(rounds), cap)
	syncAttributes(player, state)
end

function WeaponService.refillAmmo(player: Player)
	savedAmmo[player] = nil
	local state = states[player]
	if not state then
		return
	end
	local config = WeaponsConfig.get(state.weaponId)
	if not config then
		return
	end
	fillWeapon(player, state, config)
end

function WeaponService.init()
	Remotes.getEvent(Remotes.Event.WeaponEquip).OnServerEvent:Connect(onEquip)
	Remotes.getEvent(Remotes.Event.WeaponFire).OnServerEvent:Connect(onFire)
	Remotes.getEvent(Remotes.Event.WeaponReload).OnServerEvent:Connect(onReload)
	Remotes.getEvent(Remotes.Event.WeaponReloadCancel).OnServerEvent:Connect(onReloadCancel)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, state in states do
			if state.reload then
				advanceReload(player, state, now)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		local state = defaultState("Pistol")
		states[player] = state
		syncAttributes(player, state)
	end)
	ProfileManager.onLoaded(function(player, data)
		syncLoadout(player)
		player:SetAttribute("ReloadScale", SkillEffects.reloadScale(player))
		local primary = data.Loadout[1]
		if typeof(primary) == "string" and WeaponsConfig.get(primary) then
			onEquip(player, primary)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		savedAmmo[player] = nil
		runLoadout[player] = nil
		lastGongAt[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if not states[player] then
			local state = defaultState("Pistol")
			states[player] = state
			syncAttributes(player, state)
		end
	end
end

return WeaponService
