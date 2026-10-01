--!strict

-- The helicopter intermission (docs/gameplay/heli-intermission.md), between the squad's
-- launch countdown (SquadService) and the run (MissionService.startSquad):
--
--   Cabin  the squad sits in a helicopter cabin far off the map. Ready check: the run
--          goes when everyone still here is ready, or after READY_TIMEOUT for whoever
--          is here. Loadout and perk swaps are open (LoadoutWindow, the "Cabin" panel
--          of ShopService); a member may leave back to the hub.
--   Crash  the crash cinematic. The server only waits CRASH_LENGTH (the short,
--          skippable version when every member has run before); the camera, light and
--          sound are the client's. Nothing can be changed and nobody can leave.
--   Wake   MissionService.startSquad spawns whoever is still here at the wreck and
--          each gets GraceUntil (server time): ZombieAI neither chases nor hurts them
--          until it passes, and the client shows "RUN".
--
-- One intermission at a time (one run at a time); SquadService refuses a launch while
-- one is busy. The rules are IntermissionMath (pure, tests/intermission).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HangarConfig = require(ReplicatedStorage.Shared.config.HangarConfig)
local IntermissionConfig = require(ReplicatedStorage.Shared.config.IntermissionConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local Squad = require(ReplicatedStorage.Shared.types.Squad)
local IntermissionMath = require(ReplicatedStorage.Shared.util.IntermissionMath)
local FlowService = require(script.Parent.FlowService)
local MissionService = require(script.Parent.MissionService)
local MissionState = require(script.Parent.MissionState)
local ProfileManager = require(script.Parent.ProfileManager)
local SceneParts = require(script.Parent.SceneParts)

local IntermissionService = {}

local STAGE_ATTRIBUTE = "IntermissionStage"
local SEAT_ATTRIBUTE = "CabinSeat"
local GRACE_ATTRIBUTE = "GraceUntil"
local CABIN_NAME = "IntermissionCabin"

type Stage = "Cabin" | "Crash"

type Session = {
	members: { Player },
	config: Squad.SquadConfig,
	seed: number,
	stage: Stage,
	ready: IntermissionMath.ReadyCheck,
	skip: IntermissionMath.SkipVote?,
	crashEndsAt: number,
	skippable: boolean,
	seats: { [Player]: number },
	connections: { [Player]: { RBXScriptConnection } },
}

local session: Session? = nil
local cabin: Model? = nil
local seatParts: { Seat } = {}
local lastToggleAt: { [Player]: number } = {}

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function cabinOrigin(): CFrame
	return CFrame.new(vec(IntermissionConfig.CABIN_ORIGIN))
end

-- The wreck: an offset from the run's start, in its frame.
function IntermissionService.wreckCFrame(): CFrame
	return HangarConfig.RUN_START_CFRAME * CFrame.new(vec(IntermissionConfig.WRECK_OFFSET))
end

local function buildCabin()
	local model = Instance.new("Model")
	model.Name = CABIN_NAME
	local origin = cabinOrigin()
	local rng = Random.new(1)
	SceneParts.build(IntermissionConfig.parts, origin, rng, model)

	for _, figure in IntermissionConfig.crew do
		local crew = Instance.new("Model")
		crew.Name = figure.name
		SceneParts.build(figure.parts, origin * CFrame.new(vec(figure.at)), rng, crew)
		crew.Parent = model
	end

	for index, at in IntermissionConfig.seats do
		local seatCFrame = origin * CFrame.new(vec(at)) * CFrame.Angles(0, math.rad(IntermissionConfig.SEAT_YAW), 0)
		local seat = Instance.new("Seat")
		seat.Name = "Seat" .. index
		seat.Size = Vector3.new(2, 1, 2)
		seat.CFrame = seatCFrame
		seat.Anchored = true
		seat.Color = Color3.fromRGB(40, 44, 40)
		seat.Material = Enum.Material.Fabric
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.Parent = model
		seatParts[index] = seat

		-- the seated eye for IntermissionCamera, looking along the seat at the open door
		local view = Instance.new("Part")
		view.Name = "SeatView" .. index
		view.Size = Vector3.new(0.2, 0.2, 0.2)
		view.CFrame = seatCFrame * CFrame.new(vec(IntermissionConfig.EYE_OFFSET)) * CFrame.Angles(math.rad(IntermissionConfig.VIEW_PITCH), 0, 0)
		view.Anchored = true
		view.CanCollide = false
		view.CanQuery = false
		view.CanTouch = false
		view.Transparency = 1
		view.Parent = model
	end

	local strip = model:FindFirstChild("LightStrip")
	if strip and strip:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Name = "CabinLight"
		local c = IntermissionConfig.CABIN_LIGHT
		light.Color = Color3.fromRGB(c[1], c[2], c[3])
		light.Range = 18
		light.Brightness = 1.4
		light.Parent = strip
	end

	model.Parent = Workspace
	cabin = model
end

local function memberKey(player: Player): number
	return player.UserId
end

local function keysOf(members: { Player }): { number }
	local keys: { number } = {}
	for _, player in members do
		table.insert(keys, memberKey(player))
	end
	return keys
end

local function snapshotFor(current: Session): { [string]: any }
	local rows = {}
	for _, player in current.members do
		local key = memberKey(player)
		table.insert(rows, {
			userId = key,
			name = player.DisplayName,
			ready = current.ready.ready[key] == true,
			skip = current.skip ~= nil and (current.skip :: IntermissionMath.SkipVote).votes[key] == true,
		})
	end
	return {
		stage = current.stage,
		endsAt = if current.stage == "Cabin" then IntermissionMath.endsAt(current.ready) else current.crashEndsAt,
		skippable = current.stage == "Crash" and current.skippable,
		members = rows,
	}
end

local function publish()
	local current = session
	if not current then
		return
	end
	local snapshot = snapshotFor(current)
	local event = Remotes.getEvent(Remotes.Event.IntermissionState)
	for _, player in current.members do
		event:FireClient(player, snapshot)
	end
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function seat(player: Player)
	local current = session
	if not current then
		return
	end
	local index = current.seats[player]
	local seatPart = if index then seatParts[index] else nil
	local character = player.Character
	local humanoid = humanoidOf(player)
	if not seatPart or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart == seatPart then
		return
	end
	character:PivotTo(seatPart.CFrame * CFrame.new(0, 3, 0))
	seatPart:Sit(humanoid)
end

local function unseat(current: Session, player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.Sit = false
	end
	local index = current.seats[player]
	local seatPart = if index then seatParts[index] else nil
	local weld = if seatPart then seatPart:FindFirstChild("SeatWeld") else nil
	if weld then
		weld:Destroy()
	end
end

local function disconnect(current: Session, player: Player)
	local list = current.connections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		current.connections[player] = nil
	end
end

-- Keeps a member in their seat: after a character reset, and when the seat lets go
-- (a jump), seated again on the next frame.
local function watchMember(current: Session, player: Player)
	disconnect(current, player)
	local list: { RBXScriptConnection } = {}
	local function watchHumanoid(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid or not humanoid:IsA("Humanoid") or session ~= current then
			return
		end
		table.insert(list, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if session == current and current.seats[player] and humanoid.SeatPart == nil then
				task.defer(seat, player)
			end
		end))
		seat(player)
	end
	table.insert(list, player.CharacterAdded:Connect(function(character)
		task.defer(watchHumanoid, character)
	end))
	current.connections[player] = list
	if player.Character then
		task.spawn(watchHumanoid, player.Character)
	end
end

-- Takes a player out of the intermission's state (attributes, seat, watches).
local function release(current: Session, player: Player)
	disconnect(current, player)
	unseat(current, player)
	current.seats[player] = nil
	player:SetAttribute(STAGE_ATTRIBUTE, nil)
	player:SetAttribute(SEAT_ATTRIBUTE, nil)
end

local function sendHome(player: Player)
	if not player.Parent then
		return
	end
	FlowService.setPhase(player, "Hub")
	local character = player.Character
	if character then
		character:PivotTo(HangarConfig.HUB_SPAWN_CFRAME)
	end
	Remotes.getEvent(Remotes.Event.IntermissionState):FireClient(player, nil)
end

-- A member out of the intermission: they left the game, or chose to leave the cabin
-- (sent back to the hub). The rest carry on; an empty cabin ends it.
local function removeMember(player: Player, toHub: boolean)
	local current = session
	if not current then
		return
	end
	local index = table.find(current.members, player)
	if not index then
		return
	end
	table.remove(current.members, index)
	IntermissionMath.removeMember(current.ready, memberKey(player))
	local skip = current.skip
	if skip then
		IntermissionMath.removeVoter(skip, memberKey(player))
	end
	release(current, player)
	if toHub then
		sendHome(player)
	end
	publish()
end

local function toCrash(current: Session)
	local runs: { number } = {}
	for _, player in current.members do
		local data = ProfileManager.get(player)
		table.insert(runs, if data then data.StatsLifetime.Runs else 0)
	end
	local length, skippable = IntermissionMath.crashFor(IntermissionConfig, runs)
	current.stage = "Crash"
	current.crashEndsAt = now() + length
	current.skippable = skippable
	current.skip = IntermissionMath.newSkipVote(keysOf(current.members))
	for _, player in current.members do
		player:SetAttribute(STAGE_ATTRIBUTE, "Crash")
	end
	publish()
end

-- The wake-up: whoever is still here spawns at the wreck with the grace window.
local function finish(current: Session)
	session = nil
	local present: { Player } = {}
	for _, player in current.members do
		release(current, player)
		if player.Parent then
			table.insert(present, player)
		end
	end
	local event = Remotes.getEvent(Remotes.Event.IntermissionState)
	for _, player in present do
		event:FireClient(player, nil)
	end
	if #present == 0 then
		return
	end
	MissionService.startSquad(present, current.config, current.seed, IntermissionService.wreckCFrame())
	local graceUntil = IntermissionMath.graceUntil(now(), IntermissionConfig.GRACE_SECONDS)
	for _, player in present do
		if MissionState.isParticipant(player) then
			player:SetAttribute(GRACE_ATTRIBUTE, graceUntil)
		else
			-- the run did not take them (dead, or a run already going): back home
			sendHome(player)
		end
	end
end

local function abort(current: Session)
	session = nil
	for _, player in current.members do
		release(current, player)
		sendHome(player)
	end
end

local function step()
	local current = session
	if not current then
		return
	end
	local time = now()
	if current.stage == "Cabin" then
		local status = IntermissionMath.readyStatus(current.ready, time)
		if status == "Empty" then
			abort(current)
		elseif status == "AllReady" or status == "TimedOut" then
			toCrash(current)
		end
		return
	end
	if #current.members == 0 then
		abort(current)
		return
	end
	local skip = current.skip
	if time >= current.crashEndsAt or (current.skippable and skip ~= nil and IntermissionMath.skipPasses(skip)) then
		finish(current)
	end
end

function IntermissionService.isBusy(): boolean
	return session ~= nil
end

-- Called by SquadService at the end of the launch countdown in place of
-- MissionService.startSquad. False when another intermission is going or nobody
-- could board.
function IntermissionService.begin(members: { Player }, config: Squad.SquadConfig, seed: number): boolean
	if session or MissionState.isActive() or not cabin then
		return false
	end
	local boarding: { Player } = {}
	for _, player in members do
		local humanoid = humanoidOf(player)
		if player.Parent and humanoid and humanoid.Health > 0 and #boarding < #seatParts then
			table.insert(boarding, player)
		end
	end
	if #boarding == 0 then
		return false
	end
	local current: Session = {
		members = boarding,
		config = config,
		seed = seed,
		stage = "Cabin",
		ready = IntermissionMath.newReadyCheck(keysOf(boarding), now(), IntermissionConfig.READY_TIMEOUT),
		skip = nil,
		crashEndsAt = 0,
		skippable = false,
		seats = {},
		connections = {},
	}
	session = current
	for index, player in boarding do
		current.seats[player] = index
		player:SetAttribute(SEAT_ATTRIBUTE, index)
		player:SetAttribute(STAGE_ATTRIBUTE, "Cabin")
		player:SetAttribute(GRACE_ATTRIBUTE, nil)
		FlowService.setPhase(player, "Cabin")
		watchMember(current, player)
	end
	publish()
	return true
end

local function throttled(player: Player): boolean
	local time = os.clock()
	if time - (lastToggleAt[player] or 0) < IntermissionConfig.TOGGLE_COOLDOWN then
		return true
	end
	lastToggleAt[player] = time
	return false
end

local function onReady(player: Player, ready: any)
	local current = session
	if typeof(ready) ~= "boolean" or not current or current.stage ~= "Cabin" then
		return
	end
	if table.find(current.members, player) == nil or throttled(player) then
		return
	end
	if IntermissionMath.setReady(current.ready, memberKey(player), ready) then
		publish()
	end
end

local function onSkip(player: Player)
	local current = session
	if not current or current.stage ~= "Crash" or not current.skippable then
		return
	end
	local skip = current.skip
	if not skip or table.find(current.members, player) == nil or throttled(player) then
		return
	end
	if IntermissionMath.voteSkip(skip, memberKey(player)) then
		publish()
	end
end

-- The squad leave button: out of the cabin back to the hub, during the ready check only.
local function onLeave(player: Player)
	local current = session
	if current and current.stage == "Cabin" and table.find(current.members, player) then
		removeMember(player, true)
	end
end

function IntermissionService.init()
	buildCabin()
	Remotes.getEvent(Remotes.Event.IntermissionReady).OnServerEvent:Connect(onReady)
	Remotes.getEvent(Remotes.Event.IntermissionSkip).OnServerEvent:Connect(onSkip)
	-- the same remote the hangar's squad panel uses; SquadService ignores a player who
	-- is no longer in a hangar squad
	Remotes.getEvent(Remotes.Event.SquadLeave).OnServerEvent:Connect(onLeave)
	Players.PlayerRemoving:Connect(function(player)
		lastToggleAt[player] = nil
		removeMember(player, false)
	end)
	RunService.Heartbeat:Connect(step)
end

return IntermissionService
