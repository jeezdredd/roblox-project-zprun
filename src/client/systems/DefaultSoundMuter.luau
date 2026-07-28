--!strict

local Players = game:GetService("Players")

local DefaultSoundMuter = {}

local MUTED_SOUNDS = { "Died", "GettingUp", "FreeFalling", "Jumping", "Landing", "Splash", "Climbing", "Swimming", "Running" }

local function muteSound(sound: Sound)
	if table.find(MUTED_SOUNDS, sound.Name) then
		sound.Volume = 0
		sound.Playing = false
	end
end

local function muteCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child:IsA("Sound") then
			muteSound(child)
		end
	end
	root.ChildAdded:Connect(function(child)
		if child:IsA("Sound") then
			muteSound(child)
		end
	end)
end

function DefaultSoundMuter.init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(muteCharacter)
	if player.Character then
		task.spawn(muteCharacter, player.Character)
	end
end

return DefaultSoundMuter
