--!strict

-- Spent magazines dropped by a speed reload (PackViewmodel, ViewmodelPackConfig.magDrop).
-- The viewmodel magazine is copied at world size where the eye sees it (the rig is a
-- scaled-down copy around the eye, so scaling the position from the eye keeps the
-- image), then falls with the runner's velocity, bounces once or twice on whatever is
-- below and lies flat until it expires. Anchored and moved by hand like the casings: no
-- physics owner, nothing for the character to trip over.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DroppedMagazines = {}

export type Piece = { part: BasePart, cframe: CFrame }

type Mag = {
	parts: { BasePart },
	offsets: { CFrame },
	pivot: CFrame,
	velocity: Vector3,
	spin: Vector3,
	halfThickness: number,
	flatAxis: Vector3,
	resting: boolean,
	expires: number,
}

-- about real gravity at 28 cm per stud; the drop has to be seen, not snapped to the floor
local GRAVITY = 40
local RESTITUTION = 0.22
local FRICTION = 0.55
local REST_SPEED = 2.5
local MAX_BOUNCES = 3
local LIFETIME = 30
local MAX_MAGS = 12

local folder: Folder? = nil
local mags: { Mag } = {}
local bounces: { [Mag]: number } = {}
local connection: RBXScriptConnection? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = "DroppedMagazines"
	created.Parent = Workspace
	folder = created
	return created
end

local function refreshFilter()
	local list: { Instance } = { getFolder() }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(list, character)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(list, camera)
	end
	local vfx = Workspace:FindFirstChild("WeaponVfx")
	if vfx then
		table.insert(list, vfx)
	end
	rayParams.FilterDescendantsInstances = list
end

local function place(mag: Mag)
	local cframes = table.create(#mag.parts)
	for index, offset in mag.offsets do
		cframes[index] = mag.pivot * offset
	end
	Workspace:BulkMoveTo(mag.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function remove(index: number)
	local mag = table.remove(mags, index)
	if mag then
		bounces[mag] = nil
		for _, part in mag.parts do
			part:Destroy()
		end
	end
end

-- lies the magazine flat on `normal`, keeping its heading
local function settle(mag: Mag, position: Vector3, normal: Vector3)
	local rotation = mag.pivot.Rotation
	local flat = rotation:VectorToWorldSpace(mag.flatAxis)
	if flat:Dot(normal) < 0 then
		flat = -flat
	end
	local axis = flat:Cross(normal)
	local angle = math.acos(math.clamp(flat:Dot(normal), -1, 1))
	if axis.Magnitude > 1e-4 then
		rotation = CFrame.fromAxisAngle(axis.Unit, angle) * rotation
	end
	mag.pivot = CFrame.new(position + normal * mag.halfThickness) * rotation
	mag.velocity = Vector3.zero
	mag.spin = Vector3.zero
	mag.resting = true
	place(mag)
end

local function step(deltaTime: number)
	if #mags == 0 then
		return
	end
	refreshFilter()
	local now = os.clock()
	for index = #mags, 1, -1 do
		local mag = mags[index]
		if now >= mag.expires then
			remove(index)
			continue
		end
		if mag.resting then
			continue
		end
		mag.velocity += Vector3.new(0, -GRAVITY * deltaTime, 0)
		local from = mag.pivot.Position
		local move = mag.velocity * deltaTime
		local reach = move.Magnitude
		local hit = if reach > 1e-5 then Workspace:Raycast(from, move * ((reach + mag.halfThickness) / reach), rayParams) else nil
		if hit then
			local normal = hit.Normal
			local inward = mag.velocity:Dot(normal)
			local tangent = mag.velocity - normal * inward
			local count = (bounces[mag] or 0) + 1
			bounces[mag] = count
			if -inward * RESTITUTION < REST_SPEED or count > MAX_BOUNCES then
				settle(mag, hit.Position, normal)
				continue
			end
			mag.velocity = tangent * (1 - FRICTION) - normal * inward * RESTITUTION
			mag.spin *= 0.5
			mag.pivot = CFrame.new(hit.Position + normal * mag.halfThickness) * mag.pivot.Rotation
		else
			local spin = mag.spin * deltaTime
			local turn = if spin.Magnitude > 1e-6 then CFrame.fromAxisAngle(spin.Unit, spin.Magnitude) else CFrame.identity
			mag.pivot = CFrame.new(from + move) * turn * mag.pivot.Rotation
		end
		place(mag)
	end
end

-- `pieces` are the viewmodel meshes with the CFrame they are drawn at now, `eye` the
-- camera position the rig is scaled around, `scale` the rig-to-world factor,
-- `velocity` what the magazine leaves the hands with (the runner's own speed).
function DroppedMagazines.drop(pieces: { Piece }, eye: Vector3, scale: number, velocity: Vector3)
	if #pieces == 0 then
		return
	end
	while #mags >= MAX_MAGS do
		remove(1)
	end
	local parts: { BasePart } = {}
	local worlds: { CFrame } = {}
	for _, piece in pieces do
		local copy = piece.part:Clone()
		for _, child in copy:GetChildren() do
			if not child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Transparency = 0
		copy.LocalTransparencyModifier = 0
		copy.CastShadow = true
		copy.Size = piece.part.Size * scale
		local cframe = piece.cframe
		table.insert(worlds, CFrame.new(eye + (cframe.Position - eye) * scale) * cframe.Rotation)
		copy.Parent = getFolder()
		table.insert(parts, copy)
	end
	local main = parts[1]
	local pivot = worlds[1]
	local offsets: { CFrame } = {}
	for index, world in worlds do
		offsets[index] = pivot:ToObjectSpace(world)
	end
	-- the thinnest local axis of the body is the one it lies on
	local size = main.Size
	local flatAxis = Vector3.xAxis
	local thinnest = size.X
	if size.Y < thinnest then
		flatAxis, thinnest = Vector3.yAxis, size.Y
	end
	if size.Z < thinnest then
		flatAxis, thinnest = Vector3.zAxis, size.Z
	end
	local mag: Mag = {
		parts = parts,
		offsets = offsets,
		pivot = pivot,
		velocity = velocity + Vector3.new(0, -2, 0),
		spin = pivot:VectorToWorldSpace(Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 6)),
		halfThickness = thinnest * 0.5,
		flatAxis = flatAxis,
		resting = false,
		expires = os.clock() + LIFETIME,
	}
	table.insert(mags, mag)
	place(mag)
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

return DroppedMagazines
