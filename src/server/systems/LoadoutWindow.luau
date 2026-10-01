--!strict

-- When a player may change what they take into a run (the loadout slots and the
-- equipped perks): in the hub, and in the helicopter cabin during the ready check
-- (docs/gameplay/heli-intermission.md). Never during the crash beat and never as a
-- run participant. Reads the attributes the server itself sets (FlowPhase from
-- FlowService, IntermissionStage from IntermissionService), so a client cannot open it.

local MissionState = require(script.Parent.MissionState)

local LoadoutWindow = {}

-- In the cabin, during the ready check.
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
