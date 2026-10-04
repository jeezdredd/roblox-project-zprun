--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local ModifiersConfig = require(ReplicatedStorage.Shared.config.ModifiersConfig)
local Squad = require(ReplicatedStorage.Shared.types.Squad)
local MissionState = require(script.Parent.MissionState)
local MissionGoals = require(script.Parent.MissionGoals)
local MissionConfig = require(script.Parent.MissionConfig)
local FlowService = require(script.Parent.FlowService)
local TrackBuilder = require(script.Parent.TrackBuilder)
local ChunkSpawner = require(script.Parent.ChunkSpawner)
local MapPreload = require(script.Parent.MapPreload)
local ForkService = require(script.Parent.ForkService)
local WorldMeshes = require(script.Parent.WorldMeshes)
local ZombieAI = require(script.Parent.ZombieAI)
local DistanceTracker = require(script.Parent.DistanceTracker)
local ProfileManager = require(script.Parent.ProfileManager)
local RunEconomy = require(script.Parent.RunEconomy)
local PerkService = require(script.Parent.PerkService)
local WeaponService = require(script.Parent.WeaponService)

local MissionService = {}

local diedConnections: { [Player]: RBXScriptConnection } = {}
local deathHandler: ((Player) -> ())? = nil

function MissionService.setDeathHandler(handler: (Player) -> ())
	deathHandler = handler
end

local function disconnectDied(player: Player)
	local connection = diedConnections[player]
	if connection then
		connection:Disconnect()
		diedConnections[player] = nil
	end
end

local function teleportCharacter(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(cframe)
	end
end

local function applyEnvironment(modifierIds: { string })
	local wantNight = false
	for _, id in modifierIds do
		local modifier = ModifiersConfig.get(id)
		if modifier and modifier.nightMode then
			wantNight = true
		end
	end

	Workspace:SetAttribute("NightMission", wantNight)
end

local function restoreEnvironment()
	Workspace:SetAttribute("NightMission", false)
	Workspace:SetAttribute("Biome", nil)
end

local function watchDeath(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	disconnectDied(player)
	diedConnections[player] = humanoid.Died:Connect(function()
		if deathHandler then
			deathHandler(player)
		else
			MissionService.stop(player)
		end
	end)
end

local function tearDownIfEmpty()
	if MissionState.countParticipants() > 0 then
		return
	end
	MissionState.setActive(false)
	MissionState.setModifiers({})
	ChunkSpawner.clear()
	ZombieAI.clearAll()
	TrackBuilder.clear()
	restoreEnvironment()
end

-- `spawnCFrame` is where the squad stands up (the wreck after the helicopter
-- intermission); the run's start when omitted.
function MissionService.startSquad(players: { Player }, config: Squad.SquadConfig, seed: number, spawnCFrame: CFrame?)
	if MissionState.isActive() then
		return
	end

	local alivePlayers: { Player } = {}
	for _, player in players do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(alivePlayers, player)
		end
	end
	if #alivePlayers == 0 then
		return
	end
	players = alivePlayers

	MissionState.setActive(true)
	MissionConfig.setDifficulty(config.difficultyId)
	MissionState.setModifiers(config.modifierIds)

	WorldMeshes.waitReady(6)
	ChunkSpawner.configure(seed, config.mapId)
	MapPreload.configure(seed)
	ForkService.configure(seed)
	ZombieAI.configure(seed + 2)
	TrackBuilder.build()
	ChunkSpawner.reset()
	applyEnvironment(config.modifierIds)

	local count = #players
	for index, player in players do
		MissionState.addParticipant(player)
		MissionGoals.beginRun(player)
		DistanceTracker.beginRun(player)
		RunEconomy.beginRun(player)
		FlowService.setPhase(player, "Mission")
		local lateralOffset = (index - (count + 1) / 2) * HangarConfig.SQUAD_SPAWN_SPACING
		teleportCharacter(player, (spawnCFrame or HangarConfig.RUN_START_CFRAME) * CFrame.new(lateralOffset, 0, 0))
		watchDeath(player)
	end
end

function MissionService.watchPlayerDeath(player: Player)
	watchDeath(player)
end

function MissionService.removeFromMission(player: Player)
	if not MissionState.isParticipant(player) then
		return
	end
	disconnectDied(player)
	MissionState.removeParticipant(player)
	DistanceTracker.endRun(player)
	-- whatever the run still holds is banked (a death has banked its share already);
	-- the perks chosen for this run are spent with it
	local unbanked = RunEconomy.endRun(player)
	if unbanked > 0 then
		ProfileManager.addCredits(player, unbanked)
	end
	PerkService.onRunEnd(player)
	WeaponService.clearRunLoadout(player)
	-- the goals go with the run on a quit too (DeathService ends them on a death)
	MissionGoals.endRun(player)
	player:SetAttribute("GraceUntil", nil)
	tearDownIfEmpty()
end

function MissionService.stop(player: Player)
	if not MissionState.isParticipant(player) then
		return
	end
	MissionService.removeFromMission(player)
	FlowService.setPhase(player, "Hub")
	teleportCharacter(player, HangarConfig.HUB_SPAWN_CFRAME)
end

function MissionService.init()
	-- the profile's session ends synchronously on PlayerRemoving and on BindToClose, so
	-- the run is settled (banked, perks cleared) before it, while the data is still there
	ProfileManager.onReleasing(function(player)
		MissionService.removeFromMission(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		MissionService.removeFromMission(player)
	end)
end

return MissionService
