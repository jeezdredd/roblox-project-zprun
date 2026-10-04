--!strict

-- Puts the local player's aim on the wire for the other clients' third-person bodies:
-- the camera's pitch and its yaw relative to the character's facing, whole degrees, and
-- the manual lean (Stances) in tenths, at most twenty times a second and only when
-- something moved, with a keepalive every second.
-- Lossy by design: a dropped packet is replaced by the next one 50 ms later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ThirdPersonConfig = require(ReplicatedStorage.Shared.config.ThirdPersonConfig)
local BodyMath = require(ReplicatedStorage.Shared.util.BodyMath)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local StanceMath = require(ReplicatedStorage.Shared.util.StanceMath)
local Stances = require(script.Parent.Parent.systems.Stances)

local AimReplicator = {}

local REPLICATION = ThirdPersonConfig.REPLICATION

local lastPitch = 0
local lastYaw = 0
local lastLean = 0
local lastSentAt = 0
local started = false

-- The local aim as the other clients should see it: (pitch, yaw offset) in degrees, or
-- nil without a live character.
function AimReplicator.sample(): (number?, number?)
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	local look = camera.CFrame.LookVector
	local facing = root.CFrame.LookVector
	local pitch = BodyMath.pitchOf(look.Y)
	local yaw = BodyMath.signedYaw(facing.X, facing.Z, look.X, look.Z)
	return pitch, yaw
end

local function step()
	local pitch, yaw = AimReplicator.sample()
	if not pitch or not yaw then
		return
	end
	local quantizedPitch = BodyMath.quantize(pitch)
	local quantizedYaw = BodyMath.quantize(yaw)
	local quantizedLean = StanceMath.quantizeLean(Stances.lean())
	local now = os.clock()
	local since = now - lastSentAt
	local aimMoved = BodyMath.shouldSend(lastPitch, lastYaw, quantizedPitch, quantizedYaw, since, REPLICATION.sendInterval, REPLICATION.keepalive, REPLICATION.minChange)
	local leanMoved = quantizedLean ~= lastLean and since >= REPLICATION.sendInterval
	if not aimMoved and not leanMoved then
		return
	end
	lastPitch = quantizedPitch
	lastYaw = quantizedYaw
	lastLean = quantizedLean
	lastSentAt = now
	Remotes.getUnreliableEvent(Remotes.Unreliable.BodyAim):FireServer(quantizedPitch, quantizedYaw, quantizedLean)
end

function AimReplicator.init()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(step)
end

return AimReplicator
