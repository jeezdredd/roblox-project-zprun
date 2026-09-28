--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ViewmodelConfig = require(ReplicatedStorage.Shared.config.ViewmodelConfig)
local ZombieRig = require(ReplicatedStorage.Shared.util.ZombieRig)

local HipAim = {}

local player = Players.LocalPlayer

local aimPoint: Vector3? = nil
local targetModel: Model? = nil
local lostAt = 0
local lock = 0
local crosshair: GuiObject? = nil

local function targetPoint(model: Model): Vector3?
	local torso = ZombieRig.torso(model)
	if torso then
		return torso.Position + Vector3.new(0, 0.4, 0)
	end
	local root = model.PrimaryPart
	return if root then root.Position else nil
end

local function hasLineOfSight(origin: Vector3, point: Vector3, model: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = { model }
	local character = player.Character
	if character then
		table.insert(filter, character)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(filter, camera)
	end
	params.FilterDescendantsInstances = filter
	return Workspace:Raycast(origin, point - origin, params) == nil
end

local function approach(current: number, target: number, rate: number, deltaTime: number): number
	return current + (target - current) * (1 - math.exp(-rate * deltaTime))
end

local function placeCrosshair(camera: Camera)
	local frame = crosshair
	if not frame then
		return
	end
	local point = aimPoint
	if point and lock > 0.5 then
		local screen, onScreen = camera:WorldToViewportPoint(point)
		if onScreen then
			frame.Position = UDim2.fromOffset(screen.X, screen.Y)
			frame.Size = UDim2.fromOffset(6, 6)
			frame.BackgroundTransparency = 0.1
			return
		end
	end
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(3, 3)
	frame.BackgroundTransparency = 0.25
end

function HipAim.update(deltaTime: number, cameraCFrame: CFrame)
	local settings = ViewmodelConfig.hipAim
	local folder = Workspace:FindFirstChild("Zombies")
	local origin = cameraCFrame.Position
	local look = cameraCFrame.LookVector
	local cone = math.rad(settings.coneDegrees)

	local best: Model? = nil
	local bestPoint: Vector3? = nil
	local bestScore = math.huge
	if folder then
		for _, child in folder:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local humanoid = child:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				continue
			end
			local point = targetPoint(child)
			if not point then
				continue
			end
			local offset = point - origin
			local distance = offset.Magnitude
			if distance > settings.range or distance < 2 then
				continue
			end
			local angle = math.acos(math.clamp(offset.Unit:Dot(look), -1, 1))
			if angle > cone then
				continue
			end
			local score = distance * (1 + (angle / cone) * settings.centreBias)
			if score < bestScore and hasLineOfSight(origin, point, child) then
				bestScore = score
				best = child
				bestPoint = point
			end
		end
	end

	local now = os.clock()
	if best and bestPoint then
		targetModel = best
		aimPoint = bestPoint
		lostAt = now
	elseif targetModel and now - lostAt < settings.hold then
		local held = targetModel and targetPoint(targetModel)
		if held then
			aimPoint = held
		end
	else
		targetModel = nil
		aimPoint = nil
	end

	lock = approach(lock, if aimPoint then 1 else 0, settings.blendRate, deltaTime)

	local camera = Workspace.CurrentCamera
	if camera then
		placeCrosshair(camera)
	end
end

function HipAim.angles(cameraCFrame: CFrame, weaponPosition: Vector3): (number, number)
	local point = aimPoint
	if not point or lock <= 0.001 then
		return 0, 0
	end
	local settings = ViewmodelConfig.hipAim
	local localDir = cameraCFrame:VectorToObjectSpace(point - weaponPosition)
	if localDir.Magnitude < 0.01 then
		return 0, 0
	end
	local unit = localDir.Unit
	local yaw = math.atan2(-unit.X, -unit.Z)
	local pitch = math.atan2(unit.Y, math.sqrt(unit.X * unit.X + unit.Z * unit.Z))
	yaw = math.clamp(yaw, -math.rad(settings.maxYawDegrees), math.rad(settings.maxYawDegrees))
	pitch = math.clamp(pitch, -math.rad(settings.maxPitchDegrees), math.rad(settings.maxPitchDegrees))
	return yaw * lock, pitch * lock
end

function HipAim.fireDirection(origin: Vector3): Vector3?
	local point = aimPoint
	if not point or lock < ViewmodelConfig.hipAim.fireLock then
		return nil
	end
	local offset = point - origin
	if offset.Magnitude < 0.01 then
		return nil
	end
	return offset.Unit
end

function HipAim.getLock(): number
	return lock
end

function HipAim.getAimPoint(): Vector3?
	return aimPoint
end

function HipAim.bindCrosshair(frame: GuiObject)
	crosshair = frame
end

return HipAim
