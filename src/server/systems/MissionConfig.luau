--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DifficultyConfig = require(ReplicatedStorage.Shared.config.DifficultyConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)

local MissionConfig = {}

local DIFFICULTY_ATTRIBUTE = "Difficulty"

local currentDifficultyId: string = GameConstants.DEFAULT_DIFFICULTY

local function applyDifficulty(id: string): boolean
	if not DifficultyConfig[id] then
		warn(`[TaskForceZ] Unknown difficulty "{id}", keeping "{currentDifficultyId}"`)
		Workspace:SetAttribute(DIFFICULTY_ATTRIBUTE, currentDifficultyId)
		return false
	end
	currentDifficultyId = id
	return true
end

function MissionConfig.getDifficulty(): DifficultyConfig.DifficultySetting
	return DifficultyConfig[currentDifficultyId] :: DifficultyConfig.DifficultySetting
end

function MissionConfig.setDifficulty(id: string)
	if applyDifficulty(id) then
		Workspace:SetAttribute(DIFFICULTY_ATTRIBUTE, id)
	end
end

function MissionConfig.init()
	Workspace:SetAttribute(DIFFICULTY_ATTRIBUTE, currentDifficultyId)
	Workspace:GetAttributeChangedSignal(DIFFICULTY_ATTRIBUTE):Connect(function()
		local value = Workspace:GetAttribute(DIFFICULTY_ATTRIBUTE)
		if typeof(value) == "string" and value ~= currentDifficultyId then
			applyDifficulty(value)
		end
	end)
end

return MissionConfig
