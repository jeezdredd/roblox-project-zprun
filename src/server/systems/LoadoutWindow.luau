--!strict

local MissionState = require(script.Parent.MissionState)

local LoadoutWindow = {}

function LoadoutWindow.inCabin(player: Player): boolean
	return not MissionState.isParticipant(player)
		and player:GetAttribute("FlowPhase") == "Cabin"
		and player:GetAttribute("IntermissionStage") == "Cabin"
end

function LoadoutWindow.isOpen(player: Player): boolean
	if MissionState.isParticipant(player) then
		return false
	end
	local phase = player:GetAttribute("FlowPhase")
	if phase == "Cabin" then
		return LoadoutWindow.inCabin(player)
	end
	return phase == "Hub"
end

return LoadoutWindow
