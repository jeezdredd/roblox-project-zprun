--!strict

local Players = game:GetService("Players")

local FriendCache = {}

local cache: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	if a < b then
		return tostring(a) .. "_" .. tostring(b)
	end
	return tostring(b) .. "_" .. tostring(a)
end

function FriendCache.areFriends(userIdA: number, userIdB: number): boolean
	if userIdA == userIdB then
		return true
	end
	local key = pairKey(userIdA, userIdB)
	local cached = cache[key]
	if cached ~= nil then
		return cached
	end

	local player = Players:GetPlayerByUserId(userIdA)
	if not player then
		return false
	end

	local ok, result = pcall(function()
		return player:IsFriendsWithAsync(userIdB)
	end)
	local value = ok and result == true
	cache[key] = value
	return value
end

return FriendCache
