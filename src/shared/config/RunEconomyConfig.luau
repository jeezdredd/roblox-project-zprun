--!strict

local RunEconomyConfig = {}

RunEconomyConfig.killPay = {
	Walker = 25,
	Runner = 40,
} :: { [string]: number }
RunEconomyConfig.KILL_PAY_DEFAULT = 25

RunEconomyConfig.HEADSHOT_BONUS = 10

RunEconomyConfig.STREAK_WINDOW = 4
RunEconomyConfig.STREAK_STEP = 5
RunEconomyConfig.STREAK_CAP = 25

RunEconomyConfig.STUDS_PER_CREDIT = 10

return RunEconomyConfig
