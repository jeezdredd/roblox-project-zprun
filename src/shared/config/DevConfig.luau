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

-- Test yard instead of the run: you spawn on foot (the run frozen, stock first-person
-- camera, weapons live, keys 1-4 swap guns) in a flat yard away from the road with a
-- row of each zombie skin standing idle and respawning, target dummies, surface strips
-- for footstep and casing sounds, an interior room for the indoor acoustics, and a row
-- of props. Sandbox keys: G sends a chasing wave, H resets the yard, J calms everyone,
-- T teleports back to the start, V third person, Z slow motion, B plays the sound lane.
-- The yard also has both clip galleries (every zombie and weapon clip, seen from the
-- side), material walls, a texture wall and a sound lane (see Sandbox.luau).
-- Set enabled = false to play the normal run.
DevConfig.SANDBOX = {
	enabled = true,
	origin = Vector3.new(3000, 0, 0),
	respawnDelay = 3,
	waveSize = 6,
}
-- the yard is walked, so it rides on FREEZE_RUN's controls and camera
if DevConfig.SANDBOX.enabled then
	DevConfig.FREEZE_RUN = true
end

return DevConfig
