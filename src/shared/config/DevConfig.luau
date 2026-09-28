--!strict

-- Development switches. Every one of these is gated on RunService:IsStudio() at the
-- point of use, so a published server can never come up in a debug state no matter
-- what is committed here.

local DevConfig = {}

-- Skips hub, helicopter and squad lobby: spawning drops you straight into a solo run.
-- This is what makes a weapon iteration cost one Play click instead of twenty seconds
-- of scripted boarding.
DevConfig.QUICK_RUN = {
	enabled = true,
	delay = 1,
	relaunchAfterDeath = true,
	relaunchDelay = 1.5,
	seed = nil,
}

-- The content warning is a one-time player-facing gate; re-reading it every Play is
-- pure friction and it also blocks input until dismissed.
DevConfig.SKIP_GORE_WARNING = true

-- Hold the run still. The forward sprint is what you want when tuning feel, and what
-- gets in the way when tuning how something looks: the corridor drags you off the thing
-- you are inspecting within a second. With this on you spawn into the run with the
-- weapon live, but stand still and steer with the normal WASD controls, so you can walk
-- around a prop and look at it. The freeze/unfreeze debug commands still override it at
-- runtime.
DevConfig.FREEZE_RUN = false

-- Watch the third-person body instead of playing through the viewmodel: hands the
-- camera to Roblox's stock orbit controller, keeps the character visible and frees
-- the zoom clamp, so animation clips can be reviewed on the real character during a
-- run. Wins over FREEZE_RUN's camera handling; movement freezing still applies.
DevConfig.THIRD_PERSON_VIEW = false

-- A row of stationary dummies at fixed distances, for time-to-kill and spread checks
-- that a moving zombie cannot give you. Distances are in studs from the player spawn.
DevConfig.TARGET_RANGE = {
	enabled = true,
	distances = { 10, 25, 50, 100 },
	-- Lateral fan, so the row does not occlude itself. Kept small: at 12 studs the
	-- nearest dummy sat off the left edge of the screen.
	spacing = 4,
	health = 100,
	respawnDelay = 1.5,
}

return DevConfig
