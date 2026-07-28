--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local MusicController = require(script.Parent.MusicController)

local ZombieAudio = {}

local random = Random.new()

local function attachGrowl(model: Model)
	if AudioConfig.ZOMBIE_GROWL_ID <= 0 then
		return
	end
	local body = model:WaitForChild("Body", 5)
	if not body or not body:IsA("BasePart") then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Growl"
	sound.SoundId = "rbxassetid://" .. tostring(AudioConfig.ZOMBIE_GROWL_ID)
	sound.Looped = true
	sound.Volume = AudioConfig.ZOMBIE_VOLUME
	sound.PlaybackSpeed = random:NextNumber(0.55, 0.85)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = AudioConfig.ZOMBIE_ROLLOFF_MIN
	sound.RollOffMaxDistance = AudioConfig.ZOMBIE_ROLLOFF_MAX
	sound.SoundGroup = MusicController.getSfxGroup()
	sound.Parent = body

	task.delay(random:NextNumber(0, 2.5), function()
		if sound.Parent then
			pcall(function()
				sound:Play()
			end)
		end
	end)
end

function ZombieAudio.init()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Zombies", 60)
		if not folder then
			return
		end
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				task.spawn(attachGrowl, child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.spawn(attachGrowl, child)
			end
		end)
	end)
end

return ZombieAudio
