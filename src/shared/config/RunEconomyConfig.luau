--!strict

-- The kill economy of a run (docs/economy/run-economy-and-perks.md): what a kill pays
-- into the run balance, the headshot and streak bonuses, and the distance rate the
-- balance also carries. Numbers only, no engine types, so RunEconomyMath and its tests
-- load it under the standalone Luau CLI. Every pay is multiplied by the difficulty
-- reward multiplier (RewardMultiplier) at the moment it is earned.

local RunEconomyConfig = {}

-- credits per kill by zombie id (ZombiesConfig); an unknown id takes KILL_PAY_DEFAULT
RunEconomyConfig.killPay = {
	Walker = 25,
	Runner = 40,
} :: { [string]: number }
RunEconomyConfig.KILL_PAY_DEFAULT = 25

-- flat credits added to a kill whose killing shot hit the head
RunEconomyConfig.HEADSHOT_BONUS = 10

-- a kill within STREAK_WINDOW seconds of the last one extends the streak; every kill in
-- a streak adds STREAK_STEP per streak position beyond the first, capped at STREAK_CAP
RunEconomyConfig.STREAK_WINDOW = 4
RunEconomyConfig.STREAK_STEP = 5
RunEconomyConfig.STREAK_CAP = 25

-- one credit per this many studs of distance, the rate DistanceTracker always paid
RunEconomyConfig.STUDS_PER_CREDIT = 10

return RunEconomyConfig
