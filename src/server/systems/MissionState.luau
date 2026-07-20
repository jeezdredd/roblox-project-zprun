--!strict

local MissionState = {}

local active = false
local participants: { [Player]: true } = {}

function MissionState.isActive(): boolean
	return active
end

function MissionState.setActive(value: boolean)
	active = value
end

function MissionState.addParticipant(player: Player)
	participants[player] = true
end

function MissionState.removeParticipant(player: Player)
	participants[player] = nil
end

function MissionState.isParticipant(player: Player): boolean
	return participants[player] == true
end

function MissionState.getParticipants(): { Player }
	local list: { Player } = {}
	for player in participants do
		table.insert(list, player)
	end
	return list
end

function MissionState.countParticipants(): number
	local count = 0
	for _ in participants do
		count += 1
	end
	return count
end

return MissionState
