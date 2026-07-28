--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MissionGoalsConfig = require(ReplicatedStorage.Shared.config.MissionGoalsConfig)

local MissionGoals = {}

type RunProgress = { [string]: number }

local progress: { [Player]: RunProgress } = {}

function MissionGoals.beginRun(player: Player)
	progress[player] = { Distance = 0, Kills = 0, CleanDistance = 0 }
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

function MissionGoals.endRun(player: Player)
	progress[player] = nil
end

function MissionGoals.init()
	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
	end)
end

return MissionGoals
