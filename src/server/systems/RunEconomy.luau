--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunEconomyConfig = require(ReplicatedStorage.Shared.config.RunEconomyConfig)
local RunEconomyMath = require(ReplicatedStorage.Shared.util.RunEconomyMath)
local RewardMultiplier = require(ReplicatedStorage.Shared.util.RewardMultiplier)
local MissionConfig = require(script.Parent.MissionConfig)
local MissionState = require(script.Parent.MissionState)

local RunEconomy = {}

local BALANCE_ATTRIBUTE = "RunCredits"

type RunState = {
	balance: RunEconomyMath.Balance,
	distanceBanked: number,
	kills: number,
	streak: number,
	lastKillAt: number?,
}

local runs: { [Player]: RunState } = {}

local function newState(): RunState
	return { balance = { kills = 0, distance = 0 }, distanceBanked = 0, kills = 0, streak = 0, lastKillAt = nil }
end

local function multiplier(): number
	return RewardMultiplier.compute(MissionConfig.getDifficulty().id, MissionState.getModifiers())
end

local function publish(player: Player, state: RunState)
	player:SetAttribute(BALANCE_ATTRIBUTE, RunEconomyMath.total(state.balance))
end

function RunEconomy.beginRun(player: Player)
	local state = newState()
	runs[player] = state
	publish(player, state)
end

function RunEconomy.onKill(player: Player, zombieId: string?, headshot: boolean)
	local state = runs[player]
	if not state then
		return
	end
	local now = os.clock()
	state.streak = RunEconomyMath.streakAfter(state.lastKillAt, state.streak, now, RunEconomyConfig.STREAK_WINDOW)
	state.lastKillAt = now
	state.kills += 1
	state.balance.kills += RunEconomyMath.killPay(RunEconomyConfig, zombieId, headshot, state.streak, multiplier())
	publish(player, state)
end

function RunEconomy.setDistance(player: Player, traveled: number)
	local state = runs[player]
	if not state then
		return
	end
	local owed = RunEconomyMath.distanceOwed(RunEconomyConfig, traveled, multiplier(), state.distanceBanked)
	state.balance.distance = math.max(state.balance.distance, owed)
	publish(player, state)
end

export type Snapshot = {
	total: number,
	kills: number,
	distance: number,
	killCount: number,
}

function RunEconomy.snapshot(player: Player): Snapshot
	local state = runs[player]
	if not state then
		return { total = 0, kills = 0, distance = 0, killCount = 0 }
	end
	return {
		total = RunEconomyMath.total(state.balance),
		kills = state.balance.kills,
		distance = state.balance.distance,
		killCount = state.kills,
	}
end

function RunEconomy.spend(player: Player, amount: number): boolean
	local state = runs[player]
	if not state then
		return false
	end
	local ok, rest, distanceBanked = RunEconomyMath.spend(state.balance, state.distanceBanked, amount)
	if not ok then
		return false
	end
	state.balance = rest
	state.distanceBanked = distanceBanked
	publish(player, state)
	return true
end

function RunEconomy.bank(player: Player): number
	local state = runs[player]
	if not state then
		return 0
	end
	local banked, rest = RunEconomyMath.bank(state.balance)
	state.distanceBanked += state.balance.distance
	state.balance = rest
	publish(player, state)
	return banked
end

function RunEconomy.endRun(player: Player): number
	local banked = RunEconomy.bank(player)
	runs[player] = nil
	player:SetAttribute(BALANCE_ATTRIBUTE, nil)
	return banked
end

return RunEconomy
