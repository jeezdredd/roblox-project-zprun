--!strict

export type PrivacyMode = "Solo" | "FriendsOnly" | "Public"

export type SquadState = "Empty" | "Filling" | "Launching" | "Departed"

export type SquadConfig = {
	mapId: string,
	difficultyId: string,
	privacy: PrivacyMode,
	modifierIds: { string },
}

export type SquadMemberInfo = {
	userId: number,
	displayName: string,
}

export type SquadSnapshot = {
	squadIndex: number,
	state: SquadState,
	config: SquadConfig,
	members: { SquadMemberInfo },
	leaderUserId: number,
	capacity: number,
	rewardMultiplier: number,
	countdownEndsAt: number?,
}

return {}
