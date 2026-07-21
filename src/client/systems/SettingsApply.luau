--!strict

local Lighting = game:GetService("Lighting")

local SettingsService = require(script.Parent.SettingsService)
local MusicController = require(script.Parent.MusicController)
local FpsCounter = require(script.Parent.FpsCounter)

local SettingsApply = {}

function SettingsApply.init()
	SettingsService.observe("masterVolume", function(value)
		MusicController.setMasterVolume(value)
	end)
	SettingsService.observe("musicVolume", function(value)
		MusicController.setMusicVolume(value)
	end)
	SettingsService.observe("muted", function(value)
		MusicController.setMuted(value == true)
	end)
	SettingsService.observe("shadows", function(value)
		Lighting.GlobalShadows = value == true
	end)
	SettingsService.observe("fpsCounter", function(value)
		FpsCounter.setVisible(value == true)
	end)
end

return SettingsApply
