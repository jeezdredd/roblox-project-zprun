--!strict

-- The per-run credit balance of each participant, separate from the profile balance
-- (docs/economy/run-economy-and-perks.md). Kills pay into it the moment they happen
-- (WeaponService), the distance pay DistanceTracker always made is folded into the
-- same balance, and the one number is replicated as the RunCredits player attribute.
-- The balance is banked into the profile by whoever ends the run (DeathService on the
-- results screen, MissionService when a participant leaves alive): nothing earned is
-- ever lost, whether the run ends in a death, a Continue or a walk back to the hub.

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
	-- distance pay already banked this run: a Continue keeps the distance, so the pay
	-- for it is owed only once
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

-- A kill by `player`: pays the zombie's base, the headshot and the streak bonus, all
-- scaled by the difficulty multiplier, into the run balance at once.
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

-- The distance pay for the furthest point reached, less what a bank earlier in the run
-- already paid for it (the distance survives a Continue, its pay does not repeat).
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

-- Takes the balance out of the run: returns what the caller pays into the profile and
-- leaves the run at zero, so a Continue earns afresh and a second bank pays nothing.
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

-- The run is over: what is still unbanked is returned for the caller to pay, and the
-- state and the attribute go.
function RunEconomy.endRun(player: Player): number
	local banked = RunEconomy.bank(player)
	runs[player] = nil
	player:SetAttribute(BALANCE_ATTRIBUTE, nil)
	return banked
end

return RunEconomy
