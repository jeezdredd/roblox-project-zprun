--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local SettingsConfig = require(ReplicatedStorage.Shared.config.SettingsConfig)

local SettingsService = {}

local SAVE_DEBOUNCE = 2

local values: { [string]: any } = {}
local observers: { [string]: { (any) -> () } } = {}
local applyingRemote = false
local saveScheduled = false
local started = false

local function scheduleSave()
	if applyingRemote or saveScheduled then
		return
	end
	saveScheduled = true
	task.delay(SAVE_DEBOUNCE, function()
		saveScheduled = false
		Remotes.getEvent(Remotes.Event.SettingsSave):FireServer(table.clone(values))
	end)
end

function SettingsService.init()
	if started then
		return
	end
	started = true

	for _, key in SettingsConfig.order do
		local spec = SettingsConfig.byKey[key]
		values[key] = spec.default
	end

	Remotes.getEvent(Remotes.Event.SettingsSync).OnClientEvent:Connect(function(saved)
		if typeof(saved) ~= "table" then
			return
		end
		applyingRemote = true
		for key, value in saved do
			if typeof(key) == "string" and SettingsConfig.byKey[key] ~= nil then
				SettingsService.set(key, value)
			end
		end
		applyingRemote = false
	end)
end

function SettingsService.get(key: string): any
	return values[key]
end

function SettingsService.set(key: string, value: any)
	values[key] = value
	local list = observers[key]
	if list then
		for _, fn in list do
			fn(value)
		end
	end
	scheduleSave()
end

function SettingsService.observe(key: string, fn: (any) -> ()): () -> ()
	local list = observers[key]
	if not list then
		list = {}
		observers[key] = list
	end
	table.insert(list, fn)
	fn(values[key])
	return function()
		local index = table.find(list, fn)
		if index then
			table.remove(list, index)
		end
	end
end

return SettingsService
