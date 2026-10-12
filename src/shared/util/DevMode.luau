--!strict

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

function DevMode.frozen(): boolean
	return RunService:IsStudio() and (DevConfig.FREEZE_RUN or Workspace:GetAttribute("DevFreezeRun") == true)
end

return DevMode
