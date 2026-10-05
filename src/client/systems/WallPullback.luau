--!strict

-- The first-person weapon pulling back near walls (docs/gameplay/wall-pullback.md),
-- after Modern Warfare 2019. Each frame the viewmodel asks for the pose: a thin
-- spherecast from the camera along the aim, as long as the held weapon's reach
-- (WallPullbackConfig.reach by class); the nearer the hit, the further the pack
-- viewmodel retracts toward the chest and tilts up and aside, eased in and out by
-- WallPullbackMath so it never pops. Fully pulled back (the muzzle would be inside the
-- wall) the gun does not fire until the hit is clear again; partly pulled back it
-- fires. The cast ignores the local character, zombies and their props, pickups,
-- casings and the viewmodel itself; parts with CanQuery off are never hit, and parts
-- with CanCollide off are skipped too (RESPECT_CAN_COLLIDE). The server's rules are
-- unchanged: this only keeps the client from sending a shot from inside a wall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WallPullbackConfig = require(ReplicatedStorage.Shared.config.WallPullbackConfig)
local WallPullbackMath = require(ReplicatedStorage.Shared.util.WallPullbackMath)

local WallPullback = {}

-- folders the cast never stops on (ZombieAI, ZombieAI's corpses and props,
-- WeaponPickups and the upgrade stations, WeaponVfx's casings and debris)
local IGNORED_FOLDERS = { "Zombies", "ZombieProps", "Pickups", "WeaponVfx" }
-- a fire block older than this is stale (the viewmodel stopped asking: hub, death)
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

-- One frame: casts, eases the blend and returns the pose for the pack viewmodel's hold
-- channel (identity when nothing is near). `class` is the held weapon's class.
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

-- Fully pulled back: the shot would leave from inside the wall.
function WallPullback.blocksFire(): boolean
	return blocked and os.clock() - lastUpdateAt < STALE_AFTER
end

-- The eased blend (0 ready, 1 fully pulled back) and the last hit distance, for
-- overlays and Studio checks.
function WallPullback.state(): (number, number?)
	return blend, lastDistance
end

function WallPullback.reset()
	blend = 0
	blocked = false
	lastDistance = nil
end

return WallPullback
