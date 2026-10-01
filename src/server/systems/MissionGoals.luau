--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MissionGoalsConfig = require(ReplicatedStorage.Shared.config.MissionGoalsConfig)
local GoalsHudMath = require(ReplicatedStorage.Shared.util.GoalsHudMath)
local RunEconomyMath = require(ReplicatedStorage.Shared.util.RunEconomyMath)

local MissionGoals = {}

type RunProgress = { [string]: number }

local progress: { [Player]: RunProgress } = {}
-- the goals whose bonus a results screen has already paid this run
local paid: { [Player]: { [string]: boolean } } = {}

-- The run HUD reads the progress from one attribute (docs/gameplay/goals-hud-and-ladder.md);
-- reports come every frame for the distance, so the string is written at most every
-- PUBLISH_INTERVAL and only when a whole unit changed.
local PROGRESS_ATTRIBUTE = "GoalsProgress"
local PUBLISH_INTERVAL = 0.25
-- the distances are shown in steps of 5 studs, the counts whole
local STEPS = { Distance = 5, CleanDistance = 5 }
local dirty: { [Player]: boolean } = {}
local lastPublishAt = 0

local function publish(player: Player)
	local run = progress[player]
	local encoded = if run then GoalsHudMath.encode(MissionGoalsConfig, run, STEPS) else nil
	if player:GetAttribute(PROGRESS_ATTRIBUTE) ~= encoded then
		player:SetAttribute(PROGRESS_ATTRIBUTE, encoded)
	end
end

local function flush()
	local now = os.clock()
	if now - lastPublishAt < PUBLISH_INTERVAL then
		return
	end
	lastPublishAt = now
	for player in dirty do
		dirty[player] = nil
		publish(player)
	end
end

function MissionGoals.beginRun(player: Player)
	progress[player] = { Distance = 0, Kills = 0, CleanDistance = 0 }
	paid[player] = {}
	publish(player)
end

function MissionGoals.report(player: Player, metric: string, value: number)
	local run = progress[player]
	if not run then
		return
	end
	if metric == "Distance" or metric == "CleanDistance" then
		run[metric] = math.max(run[metric] or 0, value)
	else
		run[metric] = (run[metric] or 0) + value
	end
	dirty[player] = true
end

function MissionGoals.completed(player: Player): { string }
	local run = progress[player]
	local done: { string } = {}
	if not run then
		return done
	end
	for _, goalId in MissionGoalsConfig.order do
		local config = MissionGoalsConfig.get(goalId)
		if config and (run[config.metric] or 0) >= config.target then
			table.insert(done, goalId)
		end
	end
	return done
end

function MissionGoals.bonusCredits(player: Player): number
	local total = 0
	for _, goalId in MissionGoals.completed(player) do
		local config = MissionGoalsConfig.get(goalId)
		if config then
			total += config.rewardCredits
		end
	end
	return total
end

-- Pays the bonus of every completed goal not paid yet this run and marks them paid, so
-- the death after a Continue pays only the goals completed since.
function MissionGoals.claimBonus(player: Player): number
	local rewards: { [string]: number } = {}
	for _, goalId in MissionGoalsConfig.order do
		local config = MissionGoalsConfig.get(goalId)
		if config then
			rewards[goalId] = config.rewardCredits
		end
	end
	local total, nowPaid = RunEconomyMath.unpaidBonus(MissionGoals.completed(player), rewards, paid[player] or {})
	paid[player] = nowPaid
	return total
end

function MissionGoals.endRun(player: Player)
	progress[player] = nil
	paid[player] = nil
	dirty[player] = nil
	publish(player)
end

function MissionGoals.init()
	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
		paid[player] = nil
		dirty[player] = nil
	end)
	RunService.Heartbeat:Connect(flush)
end

return MissionGoals
