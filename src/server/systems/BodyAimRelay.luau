--!strict

-- Relays each player's third-person aim (pitch, yaw offset) and manual lean to every
-- client: validates the numbers, clamps them, drops packets that arrive faster than the
-- client is meant to send, and forwards them on the same unreliable remote with the
-- sender attached. The lean is cosmetic (Stances): clamped to -1..1, 0 when absent.
-- No state beyond the last accepted time per player; the aim is never authoritative
-- for anything (shots carry their own direction through WeaponService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThirdPersonConfig = require(ReplicatedStorage.Shared.config.ThirdPersonConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local StanceMath = require(ReplicatedStorage.Shared.util.StanceMath)

local BodyAimRelay = {}

local REPLICATION = ThirdPersonConfig.REPLICATION

local lastAcceptedAt: { [Player]: number } = {}

local function onAim(player: Player, pitch: any, yaw: any, lean: any)
	local ok, clampedPitch, clampedYaw = BodyMath.validateAim(pitch, yaw, REPLICATION.pitchLimit, REPLICATION.yawLimit)
	if not ok then
		return
	end
	local now = os.clock()
	if now - (lastAcceptedAt[player] or 0) < REPLICATION.relayInterval then
		return
	end
	lastAcceptedAt[player] = now
	Remotes.getUnreliableEvent(Remotes.Unreliable.BodyAim):FireAllClients(player, clampedPitch, clampedYaw, StanceMath.validateLean(lean))
end

function BodyAimRelay.init()
	if not ThirdPersonConfig.ENABLED then
		return
	end
	Remotes.getUnreliableEvent(Remotes.Unreliable.BodyAim).OnServerEvent:Connect(onAim)
	Players.PlayerRemoving:Connect(function(player)
		lastAcceptedAt[player] = nil
	end)
end

return BodyAimRelay
