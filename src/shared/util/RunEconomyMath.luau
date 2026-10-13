--!strict

export type Config = {
	killPay: { [string]: number },
	KILL_PAY_DEFAULT: number,
	HEADSHOT_BONUS: number,
	STREAK_WINDOW: number,
	STREAK_STEP: number,
	STREAK_CAP: number,
	STUDS_PER_CREDIT: number,
	DISTANCE_PAY_SPEED: number,
	DISTANCE_PAY_SLACK: number,
}

export type Balance = {
	kills: number,
	distance: number,
}

local RunEconomyMath = {}

function RunEconomyMath.streakAfter(lastKillAt: number?, streak: number, now: number, window: number): number
	if lastKillAt == nil or now - lastKillAt > window then
		return 1
	end
	return streak + 1
end

function RunEconomyMath.streakBonus(config: Config, streak: number): number
	return math.clamp((streak - 1) * config.STREAK_STEP, 0, config.STREAK_CAP)
end

function RunEconomyMath.killPay(config: Config, zombieId: string?, headshot: boolean, streak: number, multiplier: number): number
	local base = (if zombieId then config.killPay[zombieId] else nil) or config.KILL_PAY_DEFAULT
	local bonus = (if headshot then config.HEADSHOT_BONUS else 0) + RunEconomyMath.streakBonus(config, streak)
	return math.max(0, math.floor((base + bonus) * math.max(multiplier, 0)))
end

function RunEconomyMath.distanceCredits(config: Config, traveled: number, multiplier: number): number
	return math.max(0, math.floor(math.max(traveled, 0) / config.STUDS_PER_CREDIT * math.max(multiplier, 0)))
end

function RunEconomyMath.distancePayCap(config: Config, elapsed: number, multiplier: number): number
	local perSecond = config.DISTANCE_PAY_SPEED / config.STUDS_PER_CREDIT * config.DISTANCE_PAY_SLACK
	return math.max(0, math.floor(math.max(elapsed, 0) * perSecond * math.max(multiplier, 0)))
end

function RunEconomyMath.distanceOwed(config: Config, traveled: number, multiplier: number, banked: number, elapsed: number?): number
	local earned = RunEconomyMath.distanceCredits(config, traveled, multiplier)
	if elapsed then
		earned = math.min(earned, RunEconomyMath.distancePayCap(config, elapsed, multiplier))
	end
	return math.max(0, earned - math.max(banked, 0))
end

function RunEconomyMath.unpaidBonus(completed: { string }, rewards: { [string]: number }, paid: { [string]: boolean }): (number, { [string]: boolean })
	local total = 0
	local nowPaid = table.clone(paid)
	for _, goalId in completed do
		if not nowPaid[goalId] then
			total += rewards[goalId] or 0
			nowPaid[goalId] = true
		end
	end
	return total, nowPaid
end

function RunEconomyMath.spend(balance: Balance, distanceBanked: number, amount: number): (boolean, Balance, number)
	local cost = math.max(math.floor(amount), 0)
	if cost == 0 then
		return true, { kills = balance.kills, distance = balance.distance }, distanceBanked
	end
	if RunEconomyMath.total(balance) < cost then
		return false, { kills = balance.kills, distance = balance.distance }, distanceBanked
	end
	local fromKills = math.min(balance.kills, cost)
	local fromDistance = cost - fromKills
	return true, { kills = balance.kills - fromKills, distance = balance.distance - fromDistance }, distanceBanked + fromDistance
end

function RunEconomyMath.total(balance: Balance): number
	return balance.kills + balance.distance
end

function RunEconomyMath.bank(balance: Balance): (number, Balance)
	return RunEconomyMath.total(balance), { kills = 0, distance = 0 }
end

return RunEconomyMath
