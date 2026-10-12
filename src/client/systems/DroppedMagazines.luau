--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DroppedMagazines = {}

export type Piece = {
	part: BasePart,
	cframe: CFrame,
	bones: { [string]: CFrame }?,
	body: { center: Vector3, size: Vector3 }?,
}

type Mag = {
	model: Model,
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
		mag.model:Destroy()
	end
end

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

function DroppedMagazines.drop(pieces: { Piece }, eye: Vector3, scale: number, velocity: Vector3)
	if #pieces == 0 then
		return
	end
	while #mags >= MAX_MAGS do
		remove(1)
	end
	local model = Instance.new("Model")
	model.Name = "Magazine"
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
		local world = CFrame.new(eye + (cframe.Position - eye) * scale) * cframe.Rotation
		table.insert(worlds, world)
		if piece.bones then
			for name, boneWorld in piece.bones do
				local bone = Instance.new("Bone")
				bone.Name = name
				bone.CFrame = world:ToObjectSpace(CFrame.new(eye + (boneWorld.Position - eye) * scale) * boneWorld.Rotation)
				bone.Parent = copy
			end
		end
		copy.Parent = model
		table.insert(parts, copy)
	end
	model.Parent = getFolder()
	local main = parts[1]
	local pivot = worlds[1]
	local size = main.Size
	local body = pieces[1].body
	if body and main:IsA("MeshPart") then
		local toPart = main.Size / main.MeshSize
		pivot *= CFrame.new(body.center * toPart)
		size = body.size * toPart
	end
	local offsets: { CFrame } = {}
	for index, world in worlds do
		offsets[index] = pivot:ToObjectSpace(world)
	end
	local flatAxis = Vector3.xAxis
	local thinnest = size.X
	if size.Y < thinnest then
		flatAxis, thinnest = Vector3.yAxis, size.Y
	end
	if size.Z < thinnest then
		flatAxis, thinnest = Vector3.zAxis, size.Z
	end
	local mag: Mag = {
		model = model,
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
