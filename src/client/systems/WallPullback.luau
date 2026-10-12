--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WallPullbackConfig = require(ReplicatedStorage.Shared.config.WallPullbackConfig)
local WallPullbackMath = require(ReplicatedStorage.Shared.util.WallPullbackMath)

local WallPullback = {}

local IGNORED_FOLDERS = { "Zombies", "ZombieProps", "Pickups", "WeaponVfx" }
local STALE_AFTER = 0.25

local player = Players.LocalPlayer
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = WallPullbackConfig.RESPECT_CAN_COLLIDE

local blend = 0
local blocked = false
local lastUpdateAt = -math.huge
local lastDistance: number? = nil

local function ignoreList(camera: Camera?): { Instance }
	local list: { Instance } = {}
	local character = player.Character
	if character then
		table.insert(list, character)
	end
	if camera then
		table.insert(list, camera)
	end
	for _, name in IGNORED_FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

local function cast(cameraCFrame: CFrame, reach: number): number?
	params.FilterDescendantsInstances = ignoreList(Workspace.CurrentCamera)
	local direction = cameraCFrame.LookVector * reach
	local result = Workspace:Spherecast(cameraCFrame.Position, WallPullbackConfig.CAST_RADIUS, direction, params)
	return if result then result.Distance else nil
end

local function poseCFrame(value: number): CFrame
	local pose = WallPullbackMath.poseAt(WallPullbackConfig, value)
	return CFrame.new(pose.aside, -pose.down, pose.back)
		* CFrame.Angles(math.rad(pose.pitchUp), math.rad(-pose.yawAside), math.rad(-pose.roll))
end

function WallPullback.update(deltaTime: number, cameraCFrame: CFrame, class: string?): CFrame
	local reach = WallPullbackMath.reachFor(WallPullbackConfig, class)
	local distance = cast(cameraCFrame, reach)
	lastDistance = distance
	local target = WallPullbackMath.targetFor(WallPullbackConfig, distance, reach)
	blend = WallPullbackMath.ease(WallPullbackConfig, blend, target, deltaTime)
	blocked = WallPullbackMath.blocked(WallPullbackConfig, blocked, distance, reach)
	lastUpdateAt = os.clock()
	if blend <= 0 then
		return CFrame.identity
	end
	return poseCFrame(blend)
end

function WallPullback.blocksFire(): boolean
	return blocked and os.clock() - lastUpdateAt < STALE_AFTER
end

function WallPullback.state(): (number, number?)
	return blend, lastDistance
end

function WallPullback.reset()
	blend = 0
	blocked = false
	lastDistance = nil
end

return WallPullback
