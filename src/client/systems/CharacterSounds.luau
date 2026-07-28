--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)

local CharacterSounds = {}

local MUTED_SOUNDS = { "Died", "GettingUp", "FreeFalling", "Jumping", "Landing", "Splash", "Climbing", "Swimming" }

local function tuneSound(sound: Sound)
	if table.find(MUTED_SOUNDS, sound.Name) then
		sound.Volume = 0
		sound.Playing = false
		return
	end
	if sound.Name == "Running" then
		sound.Volume = 0.18
		sound.PlaybackSpeed = 0.85
		if AudioConfig.FOOTSTEP_ID and AudioConfig.FOOTSTEP_ID > 0 then
			sound.SoundId = "rbxassetid://" .. tostring(AudioConfig.FOOTSTEP_ID)
		end
	end
end

local function tuneCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child:IsA("Sound") then
			tuneSound(child)
		end
	end
	root.ChildAdded:Connect(function(child)
		if child:IsA("Sound") then
			tuneSound(child)
		end
	end)
end

function CharacterSounds.init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(tuneCharacter)
	if player.Character then
		task.spawn(tuneCharacter, player.Character)
	end
end

return CharacterSounds
