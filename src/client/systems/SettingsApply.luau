--!strict

local Lighting = game:GetService("Lighting")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxConfig = require(ReplicatedStorage.Shared.config.VfxConfig)
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
	SettingsService.observe("effectsQuality", function(value)
		if typeof(value) == "number" then
			VfxConfig.setDensity(value)
		end
	end)
end

return SettingsApply
