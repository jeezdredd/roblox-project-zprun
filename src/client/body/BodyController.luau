--!strict

-- Runs a BodyRig on every other player's character, and on the local one while the
-- third-person view is on (Studio only). Feeds each rig from what already replicates:
-- the WorldWeapon model and the WeaponId attribute for the gun and the draw, the
-- Reloading / AmmoMag / AmmoReserve / ReloadScale attributes for reloads, the
-- WeaponHit "Shot" remote for the kick, the BodyAim packets for the aim, and the root
-- velocity for the sprint. Updates are scheduled by distance (ThirdPersonConfig.lod)
-- in PreSimulation, after the animator, with a cap per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local ThirdPersonConfig = require(ReplicatedStorage.Shared.config.ThirdPersonConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local WorldWeaponModel = require(ReplicatedStorage.Shared.util.WorldWeaponModel)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local AimReplicator = require(script.Parent.AimReplicator)
local BodyRig = require(script.Parent.BodyRig)

local BodyController = {}

type Entry = {
	player: Player,
	character: Model,
	rig: BodyRig.BodyRig,
	index: number,
	cadence: number,
	pending: number,
	lastPacketAt: number,
	connections: { RBXScriptConnection },
}

local entries: { [Player]: Entry } = {}
local nextIndex = 0
local frame = 0
local lod: ThirdPersonConfig.LodProfile = ThirdPersonConfig.lod.desktop
local bands: BodyMath.LodBands = { full = 0, half = 0, quarter = 0, ikRange = 0 }
local started = false

local function thirdPersonView(): boolean
	return RunService:IsStudio() and (DevConfig.THIRD_PERSON_VIEW or Workspace:GetAttribute("DevThirdPerson") == true)
end

local function configFor(player: Player): WeaponsConfig.WeaponConfig?
	local weaponId = player:GetAttribute("WeaponId")
	return if typeof(weaponId) == "string" then WeaponsConfig.get(weaponId) else nil
end

local function bindWeapon(entry: Entry, weapon: Instance?)
	local config = configFor(entry.player)
	if weapon and weapon:IsA("Model") and config then
		entry.rig:setWeapon(weapon, config)
		entry.rig:equip()
	else
		entry.rig:setWeapon(nil, nil)
	end
end

local function onReloadingChanged(entry: Entry)
	local player = entry.player
	if player:GetAttribute("Reloading") ~= true then
		entry.rig:endReload()
		return
	end
	local config = configFor(player)
	if not config then
		return
	end
	local mag = player:GetAttribute("AmmoMag")
	local reserve = player:GetAttribute("AmmoReserve")
	local scale = player:GetAttribute("ReloadScale")
	local magCount = if typeof(mag) == "number" then mag else config.magSize
	local reserveCount = if typeof(reserve) == "number" then reserve else config.magSize
	local shells = math.max(math.min(config.magSize - magCount, reserveCount), 0)
	entry.rig:startReload(magCount <= 0, shells, if typeof(scale) == "number" then scale else 1)
end

local function unbind(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	entries[player] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.rig:destroy()
end

local function bind(player: Player, character: Model)
	unbind(player)
	local rig = BodyRig.new(character)
	if not rig then
		return
	end
	if player == Players.LocalPlayer then
		rig:setSmoothing(ThirdPersonConfig.AIM.localSmoothing)
	end
	nextIndex += 1
	local entry: Entry = {
		player = player,
		character = character,
		rig = rig,
		index = nextIndex,
		cadence = 1,
		pending = 0,
		lastPacketAt = 0,
		connections = {},
	}
	entries[player] = entry
	bindWeapon(entry, character:FindFirstChild(WorldWeaponModel.NAME))
	table.insert(entry.connections, character.ChildAdded:Connect(function(child)
		if child.Name == WorldWeaponModel.NAME then
			-- the sockets are children of the grip and arrive with the model
			task.defer(bindWeapon, entry, child)
		end
	end))
	table.insert(entry.connections, character.ChildRemoved:Connect(function(child)
		if child.Name == WorldWeaponModel.NAME and entry.rig.weapon == child then
			entry.rig:setWeapon(nil, nil)
		end
	end))
	table.insert(entry.connections, player:GetAttributeChangedSignal("Reloading"):Connect(function()
		onReloadingChanged(entry)
	end))
	if player:GetAttribute("Reloading") == true then
		onReloadingChanged(entry)
	end
end

-- The character is bound once its arms and torso exist; a character that never gets
-- them (an R6 avatar) is left to the animator.
local function watchCharacter(player: Player, character: Model)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		for _, name in { "UpperTorso", "Head", "RightUpperArm", "RightHand", "LeftUpperArm", "LeftHand" } do
			if not character:WaitForChild(name, 10) then
				return
			end
		end
		if character.Parent and player.Character == character then
			bind(player, character)
		end
	end)
end

local function watchPlayer(player: Player)
	if player == Players.LocalPlayer then
		return
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		unbind(player)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

local function onShot(kind: string, ...: any)
	if kind ~= "Shot" then
		return
	end
	local _, _, shooter = ...
	if typeof(shooter) ~= "Instance" or not shooter:IsA("Player") then
		return
	end
	local entry = entries[shooter]
	if entry then
		entry.rig:fire()
	end
end

local function onAim(player: Player, pitch: number, yaw: number)
	if player == Players.LocalPlayer or typeof(pitch) ~= "number" or typeof(yaw) ~= "number" then
		return
	end
	local entry = entries[player]
	if entry then
		entry.rig:setAim(pitch, yaw)
		entry.lastPacketAt = os.clock()
	end
end

-- The local character joins the set only while the third-person view is on, and its
-- aim comes straight from the camera.
local function updateLocal()
	local player = Players.LocalPlayer
	local character = player.Character
	local entry = entries[player]
	if not thirdPersonView() or not character then
		if entry then
			unbind(player)
		end
		return
	end
	if not entry or entry.character ~= character then
		if character:FindFirstChild("RightHand") and character:FindFirstChild("LeftHand") and character:FindFirstChild("UpperTorso") then
			bind(player, character)
		end
		return
	end
	local pitch, yaw = AimReplicator.sample()
	if pitch and yaw then
		entry.rig:setAim(pitch, yaw)
	end
end

local function speedOf(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
end

local function step(deltaTime: number)
	frame += 1
	updateLocal()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local updated = 0
	for player, entry in entries do
		if not entry.rig:isValid() then
			unbind(player)
			continue
		end
		entry.pending += deltaTime
		local root = entry.character:FindFirstChild("HumanoidRootPart")
		local distance = if root and root:IsA("BasePart") then (root.Position - eye).Magnitude else math.huge
		local cadence, ikOn = BodyMath.lodBand(distance, bands)
		entry.cadence = cadence
		entry.rig:setIkAllowed(ikOn)
		if not BodyMath.updatesThisFrame(frame, entry.index, cadence) or updated >= lod.maxPerFrame then
			continue
		end
		if entry.rig:isThrottled() then
			continue
		end
		entry.rig:setSpeed(speedOf(entry.character))
		entry.rig:update(entry.pending)
		entry.pending = 0
		updated += 1
	end
end

-- For the yard label under a real player: seconds since their last aim packet, or nil
-- for a player without a rig.
function BodyController.packetAge(player: Player): number?
	local entry = entries[player]
	if not entry or entry.lastPacketAt == 0 then
		return nil
	end
	return os.clock() - entry.lastPacketAt
end

function BodyController.describe(player: Player): string?
	local entry = entries[player]
	return if entry then entry.rig:describe() else nil
end

function BodyController.init()
	if started or not ThirdPersonConfig.ENABLED then
		return
	end
	started = true
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		lod = ThirdPersonConfig.lod.mobile
	end
	bands.full = lod.full
	bands.half = lod.half
	bands.quarter = lod.quarter
	bands.ikRange = lod.ikRange

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(unbind)

	Remotes.getEvent(Remotes.Event.WeaponHit).OnClientEvent:Connect(onShot)
	Remotes.getUnreliableEvent(Remotes.Unreliable.BodyAim).OnClientEvent:Connect(onAim)
	AimReplicator.init()
	RunService.PreSimulation:Connect(step)
end

return BodyController
