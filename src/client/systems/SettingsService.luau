--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.config.SettingsConfig)

local SettingsService = {}

local values: { [string]: any } = {}
local observers: { [string]: { (any) -> () } } = {}

function SettingsService.init()
	for _, key in SettingsConfig.order do
		local spec = SettingsConfig.byKey[key]
		values[key] = spec.default
	end
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
