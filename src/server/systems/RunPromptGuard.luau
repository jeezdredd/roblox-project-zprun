--!strict

-- The server's own check behind every mid-run ProximityPrompt (weapon pickups, the
-- upgrade station): the trigger came from a living participant of the active run, in
-- the Mission phase, whose root stands within reach of the prompt's anchor. The prompt
-- itself only shows within its MaxActivationDistance; the reach is a little more, for
-- the latency of a running player.

local MissionState = require(script.Parent.MissionState)

local RunPromptGuard = {}

function RunPromptGuard.canUse(player: Player, anchor: Vector3, reach: number): boolean
	if not MissionState.isActive() or not MissionState.isParticipant(player) then
		return false
	end
	if player:GetAttribute("FlowPhase") ~= "Mission" then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - anchor).Magnitude <= reach
end

return RunPromptGuard
