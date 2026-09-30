--!strict

-- The pay table arithmetic of the run economy (RunEconomy on the server): what a kill
-- is worth, how a streak advances, what distance pays, and how a run balance is banked.
-- Pure Luau with no requires: the config table comes in as an argument, so
-- tests/economy/run.luau runs it under the standalone Luau CLI.

export type Config = {
	killPay: { [string]: number },
	KILL_PAY_DEFAULT: number,
	HEADSHOT_BONUS: number,
	STREAK_WINDOW: number,
	STREAK_STEP: number,
	STREAK_CAP: number,
	STUDS_PER_CREDIT: number,
}

export type Balance = {
	kills: number,
	distance: number,
}

local RunEconomyMath = {}

-- The streak position of a kill at `now` given the previous kill's time and streak:
-- 1 for the first kill or a kill after the window, else one more than before.
function RunEconomyMath.streakAfter(lastKillAt: number?, streak: number, now: number, window: number): number
	if lastKillAt == nil or now - lastKillAt > window then
		return 1
	end
	return streak + 1
end

-- The streak bonus at a streak position: nothing for the first kill, STREAK_STEP more
-- per position after it, capped.
function RunEconomyMath.streakBonus(config: Config, streak: number): number
	return math.clamp((streak - 1) * config.STREAK_STEP, 0, config.STREAK_CAP)
end

-- Credits one kill pays: base by zombie id, headshot and streak bonuses, all scaled by
-- the difficulty reward multiplier and floored so the balance stays whole credits.
function RunEconomyMath.killPay(config: Config, zombieId: string?, headshot: boolean, streak: number, multiplier: number): number
	local base = (if zombieId then config.killPay[zombieId] else nil) or config.KILL_PAY_DEFAULT
	local bonus = (if headshot then config.HEADSHOT_BONUS else 0) + RunEconomyMath.streakBonus(config, streak)
	return math.max(0, math.floor((base + bonus) * math.max(multiplier, 0)))
end

-- Credits the distance run so far is worth, the rate DistanceTracker always paid.
function RunEconomyMath.distanceCredits(config: Config, traveled: number, multiplier: number): number
	return math.max(0, math.floor(math.max(traveled, 0) / config.STUDS_PER_CREDIT * math.max(multiplier, 0)))
end

-- The one number the HUD shows: kill pay plus distance pay.
function RunEconomyMath.total(balance: Balance): number
	return balance.kills + balance.distance
end

-- Banking: what goes to the profile and the empty balance the run continues with.
-- Nothing earned is ever lost, whatever ended the run.
function RunEconomyMath.bank(balance: Balance): (number, Balance)
	return RunEconomyMath.total(balance), { kills = 0, distance = 0 }
end

return RunEconomyMath
