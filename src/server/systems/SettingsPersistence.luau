--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local SettingsConfig = require(ReplicatedStorage.Shared.config.SettingsConfig)
local ProfileManager = require(script.Parent.ProfileManager)

local SettingsPersistence = {}

local SAVE_THROTTLE = 1.5

local lastSaveAt: { [Player]: number } = {}
local started = false

local function sanitize(payload: any): { [string]: any }?
	if typeof(payload) ~= "table" then
		return nil
	end
	local clean: { [string]: any } = {}
	for key, value in payload do
		if typeof(key) ~= "string" then
			continue
		end
		local spec = SettingsConfig.byKey[key]
		if not spec then
			continue
		end
		if spec.kind == "toggle" then
			if typeof(value) == "boolean" then
				clean[key] = value
			end
		elseif spec.kind == "slider" then
			if typeof(value) == "number" then
				clean[key] = math.clamp(value, spec.min or 0, spec.max or 1)
			end
		end
	end
	return clean
end

function SettingsPersistence.init()
	if started then
		return
	end
	started = true

	ProfileManager.onLoaded(function(player, data)
		Remotes.getEvent(Remotes.Event.SettingsSync):FireClient(player, data.Settings)
	end)

	Remotes.getEvent(Remotes.Event.SettingsSave).OnServerEvent:Connect(function(player, payload)
		local now = os.clock()
		if lastSaveAt[player] and now - lastSaveAt[player] < SAVE_THROTTLE then
			return
		end
		lastSaveAt[player] = now

		local clean = sanitize(payload)
		if not clean then
			return
		end
		local data = ProfileManager.get(player)
		if not data then
			return
		end
		for key, value in clean do
			data.Settings[key] = value
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastSaveAt[player] = nil
	end)
end

return SettingsPersistence
