--!strict

-- Route forks: builds the centre divider and signs before a fork boundary, closes the
-- vote when the lead runner crosses the vote line, and hands the choice to RoutePlan.
-- The vote is physical: each living runner counts for the side of the divider they
-- are on. See wiki/project-zprun/Route Forks.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local ForkConfig = require(ReplicatedStorage.Shared.config.ForkConfig)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local DistanceTracker = require(script.Parent.DistanceTracker)
local MissionState = require(script.Parent.MissionState)
local RoutePlan = require(script.Parent.RoutePlan)

local ForkService = {}

type Built = {
	model: Model,
	voteDistance: number,
	endDistance: number,
}

local ATTR_LEFT = "ForkLeft"
local ATTR_RIGHT = "ForkRight"
local ATTR_VOTE = "ForkVoteDistance"
local ATTR_RESULT = "ForkResult"

local runDirection = GameConstants.RUN_DIRECTION
local origin = GameConstants.RUN_ORIGIN
local floorTop = origin.Y + 0.5
local random = Random.new()

local folder: Folder? = nil
local builtFor: RoutePlan.PlanEntry? = nil
local builtModels: { Built } = {}

local function worldAt(distance: number, lateral: number, height: number): Vector3
	-- lateral > 0 is the runner's right (+X when running towards -Z)
	return origin + runDirection * distance + Vector3.new(lateral, height, 0)
end

local function displayName(id: string): string
	local location = LocationsConfig.get(id)
	return string.upper(if location then location.displayName else id)
end

local function part(name: string, size: Vector3, position: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.lookAt(position, position + runDirection)
	p.Anchored = true
	p.CanCollide = true
	p.Material = Enum.Material.Concrete
	p.Color = Color3.fromRGB(150, 146, 138)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function signLabel(surface: SurfaceGui, text: string, xScale: number, alignment: Enum.TextXAlignment)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.5, 1)
	label.Position = UDim2.fromScale(xScale, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	-- Keep scaled text off the board edges; without it the descenders were clipped.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
	label.TextColor3 = Color3.fromRGB(240, 232, 200)
	label.TextXAlignment = alignment
	label.Text = text
	label.Parent = surface
end

local function buildDivider(entry: RoutePlan.PlanEntry, boundary: number): Built
	local options = (entry.fork :: RoutePlan.ForkInfo).options
	local voteDistance = boundary - ForkConfig.VOTE_LEAD
	local startDistance = voteDistance - ForkConfig.DIVIDER_LENGTH

	local model = Instance.new("Model")
	model.Name = "RouteFork"

	-- Jersey barriers down the centre line, with small gaps so it reads as a road
	-- divider and a runner who strays onto it is nudged rather than walled.
	local segment = 10
	local gap = 2
	local d = startDistance
	while d + segment <= voteDistance do
		part("Barrier", Vector3.new(1.6, 3.2, segment), worldAt(d + segment / 2, 0, floorTop + 1.6), model)
		d += segment + gap
	end

	-- Sign gantry at the divider start, facing the runners.
	local signPos = worldAt(startDistance - 2, 0, floorTop + ForkConfig.SIGN_HEIGHT)
	local post = part("SignPost", Vector3.new(1, ForkConfig.SIGN_HEIGHT, 1), worldAt(startDistance - 2, 0, floorTop + ForkConfig.SIGN_HEIGHT / 2), model)
	post.Color = Color3.fromRGB(60, 62, 64)
	post.Material = Enum.Material.Metal
	local board = part("SignBoard", Vector3.new(30, 6, 0.5), signPos, model)
	board.Color = Color3.fromRGB(34, 60, 42)
	board.Material = Enum.Material.SmoothPlastic
	local surface = Instance.new("SurfaceGui")
	-- Runners face RUN_DIRECTION, which is the part's look vector, so they see the Back face.
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = board
	signLabel(surface, "< " .. displayName(options[1]), 0, Enum.TextXAlignment.Left)
	signLabel(surface, displayName(options[2]) .. " >", 0.5, Enum.TextXAlignment.Right)

	model.Parent = folder
	return { model = model, voteDistance = voteDistance, endDistance = voteDistance }
end

local function livingRunnerSides(): (number, number)
	local left, right = 0, 0
	for _, player in MissionState.getParticipants() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			if root.Position.X - origin.X < 0 then
				left += 1
			else
				right += 1
			end
		end
	end
	return left, right
end

local function resolve(entry: RoutePlan.PlanEntry)
	local options = (entry.fork :: RoutePlan.ForkInfo).options
	local left, right = livingRunnerSides()
	local choice
	if left > right then
		choice = options[1]
	elseif right > left then
		choice = options[2]
	else
		choice = options[random:NextInteger(1, 2)]
	end
	RoutePlan.resolveFork(entry, choice)
	Workspace:SetAttribute(ATTR_RESULT, choice)
	Workspace:SetAttribute(ATTR_LEFT, nil)
	Workspace:SetAttribute(ATTR_RIGHT, nil)
	Workspace:SetAttribute(ATTR_VOTE, nil)
	builtFor = nil
end

local function clearAll()
	for _, built in builtModels do
		built.model:Destroy()
	end
	builtModels = {}
	builtFor = nil
	Workspace:SetAttribute(ATTR_LEFT, nil)
	Workspace:SetAttribute(ATTR_RIGHT, nil)
	Workspace:SetAttribute(ATTR_VOTE, nil)
	Workspace:SetAttribute(ATTR_RESULT, nil)
end

local function step()
	if not MissionState.isActive() then
		if #builtModels > 0 or builtFor then
			clearAll()
		end
		return
	end

	local lead = DistanceTracker.getMaxDistance()
	RoutePlan.planAhead(lead + GameConstants.SPAWN_AHEAD_DISTANCE + ForkConfig.VOTE_LEAD + ForkConfig.DIVIDER_LENGTH)

	local entry, boundary = RoutePlan.pendingFork()
	if entry and entry ~= builtFor then
		local built = buildDivider(entry, boundary)
		table.insert(builtModels, built)
		builtFor = entry
		local options = (entry.fork :: RoutePlan.ForkInfo).options
		Workspace:SetAttribute(ATTR_LEFT, options[1])
		Workspace:SetAttribute(ATTR_RIGHT, options[2])
		Workspace:SetAttribute(ATTR_VOTE, built.voteDistance)
	end

	if entry and lead >= boundary - ForkConfig.VOTE_LEAD then
		resolve(entry)
	end

	local cull = DistanceTracker.getMinDistance() - GameConstants.DESPAWN_BEHIND_DISTANCE
	for i = #builtModels, 1, -1 do
		if builtModels[i].endDistance < cull then
			builtModels[i].model:Destroy()
			table.remove(builtModels, i)
		end
	end
end

function ForkService.configure(seed: number)
	random = Random.new(seed + 7)
	clearAll()
end

function ForkService.init()
	local f = Instance.new("Folder")
	f.Name = "RouteForks"
	f.Parent = Workspace
	folder = f
	RunService.Heartbeat:Connect(step)
end

return ForkService
