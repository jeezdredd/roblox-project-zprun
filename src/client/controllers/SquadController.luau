--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local SquadConfigGui = require(script.Parent.Parent.ui.SquadConfigGui)

local SquadController = {}

function SquadController.init()
	local gui = SquadConfigGui.create({
		onSelectMap = function(id)
			Remotes.getEvent(Remotes.Event.SquadUpdateConfig):FireServer("mapId", id)
		end,
		onSelectDifficulty = function(id)
			Remotes.getEvent(Remotes.Event.SquadUpdateConfig):FireServer("difficultyId", id)
		end,
		onSelectPrivacy = function(mode)
			Remotes.getEvent(Remotes.Event.SquadUpdateConfig):FireServer("privacy", mode)
		end,
		onToggleModifier = function(id)
			Remotes.getEvent(Remotes.Event.SquadToggleModifier):FireServer(id)
		end,
		onLaunch = function()
			Remotes.getEvent(Remotes.Event.SquadLaunch):FireServer()
		end,
		onLeave = function()
			Remotes.getEvent(Remotes.Event.SquadLeave):FireServer()
		end,
	})

	Remotes.getEvent(Remotes.Event.SquadSnapshot).OnClientEvent:Connect(function(snapshot)
		gui.update(snapshot)
	end)
end

return SquadController
