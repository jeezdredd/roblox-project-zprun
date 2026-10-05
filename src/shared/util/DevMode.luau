--!strict

-- Studio-only switches read while playing, shared by client and server. The run and the
-- test yard (DevConfig.SANDBOX) swap at run time: the server keeps the current mode in
-- the workspace attribute DevMode ("Run" or "Yard", Sandbox.luau) and DevFreezeRun with
-- it, and the client's dev button (SandboxInput, key M) asks for the other one. Outside
-- Studio both answers are always false.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DevConfig = require(script.Parent.Parent.config.DevConfig)

local DevMode = {}

export type Mode = "Run" | "Yard"

function DevMode.current(): Mode
	if RunService:IsStudio() and Workspace:GetAttribute("DevMode") == "Yard" then
		return "Yard"
	end
	return "Run"
end

function DevMode.yard(): boolean
	return DevMode.current() == "Yard"
end

-- the run held still: DevConfig.FREEZE_RUN, the yard, or DevFreezeRun set by hand
function DevMode.frozen(): boolean
	return RunService:IsStudio() and (DevConfig.FREEZE_RUN or Workspace:GetAttribute("DevFreezeRun") == true)
end

return DevMode
