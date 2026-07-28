--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ProfileManager = require(script.Parent.ProfileManager)

local WeaponService = {}

type PlayerWeaponState = {
	weaponId: string,
	mag: number,
	reserve: number,
	lastFireAt: number,
	reloadingUntil: number,
	reloadToken: number,
}

local ORIGIN_TOLERANCE = 5
local RATE_TOLERANCE = 0.97
local GONG_COOLDOWN = 0.8

type AmmoSnapshot = { mag: number, reserve: number, lastFireAt: number }

local states: { [Player]: PlayerWeaponState } = {}
local savedAmmo: { [Player]: { [string]: AmmoSnapshot } } = {}
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
		reloadingUntil = 0,
		reloadToken = 0,
	}
end

local function ownsWeapon(player: Player, weaponId: string): boolean
	local data = ProfileManager.get(player)
	if not data then
		return weaponId == "Pistol"
	end
	return data.WeaponsOwned[weaponId] ~= nil
end

local function onEquip(player: Player, weaponId: unknown)
	if typeof(weaponId) ~= "string" then
		return
	end
	local config = WeaponsConfig.get(weaponId)
	if not config or not ownsWeapon(player, weaponId) then
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

	local state = defaultState(weaponId)
	local prior = saved[weaponId]
	if prior then
		state.mag = prior.mag
		state.reserve = prior.reserve
		state.lastFireAt = prior.lastFireAt
	end
	state.reloadToken = if current then current.reloadToken + 1 else 0
	states[player] = state
	player:SetAttribute("Reloading", false)
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

	local damage = config.damage
	if part.Name == "Head" then
		damage *= config.headshotMultiplier
	end
	local wasAlive = humanoid.Health > 0
	humanoid:TakeDamage(damage)
	if wasAlive and humanoid.Health <= 0 then
		ProfileManager.addKill(player)
	end
end

local function onFire(player: Player, origin: unknown, direction: unknown)
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
	if now < state.reloadingUntil then
		return
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
		losParams.FilterDescendantsInstances = if character then { character } else {}
		if Workspace:Raycast(anchor, toOrigin, losParams) then
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
	if now < state.reloadingUntil then
		return
	end
	if state.mag >= config.magSize or state.reserve <= 0 then
		return
	end

	state.reloadingUntil = now + config.reloadTime
	state.reloadToken += 1
	local token = state.reloadToken
	player:SetAttribute("Reloading", true)

	task.delay(config.reloadTime, function()
		local currentState = states[player]
		if not currentState or currentState.reloadToken ~= token then
			return
		end
		local needed = config.magSize - currentState.mag
		local taken = math.min(needed, currentState.reserve)
		currentState.mag += taken
		currentState.reserve -= taken
		currentState.reloadingUntil = 0
		player:SetAttribute("Reloading", false)
		syncAttributes(player, currentState)
	end)
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
	state.mag = config.magSize
	state.reserve = config.magSize * config.reserveMags
	state.reloadingUntil = 0
	state.reloadToken += 1
	player:SetAttribute("Reloading", false)
	syncAttributes(player, state)
end

function WeaponService.init()
	Remotes.getEvent(Remotes.Event.WeaponEquip).OnServerEvent:Connect(onEquip)
	Remotes.getEvent(Remotes.Event.WeaponFire).OnServerEvent:Connect(onFire)
	Remotes.getEvent(Remotes.Event.WeaponReload).OnServerEvent:Connect(onReload)

	Players.PlayerAdded:Connect(function(player)
		local state = defaultState("Pistol")
		states[player] = state
		syncAttributes(player, state)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		savedAmmo[player] = nil
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
