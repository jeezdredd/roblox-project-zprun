--!strict

-- The helicopter's two crew as soldiers (docs/gameplay/heli-intermission.md), client
-- only. The server builds the Pilot and Copilot as block figures in
-- Workspace.IntermissionCabin; while this player is in the cabin they are hidden locally
-- and two soldier bodies (clones of StarterPlayer.StarterCharacter, the same Mixamo
-- soldier every player wears) sit in the cockpit seats with the seated clip. The crash
-- beat (CrashCinematic) drives them through pose():
--
--   the pilot turns his head to the copilot (an IKControl LookAt)
--   the copilot turns his head to the pilot and brings a pistol up to the pilot's head
--   (an IKControl Transform whose end effector is the pistol's muzzle, so the barrel
--   points at the head whatever the hand's grip offset)
--   the shot: the pilot's head snaps aside and he slumps onto the console (the neck
--   and waist joints rotated after the animator, every PostSimulation)
--
-- No blood or wound: everyone sees the beat and the Gore toggle does not apply.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local SoldierBody = require(ReplicatedStorage.Shared.util.SoldierBody)
local WorldWeaponModel = require(ReplicatedStorage.Shared.util.WorldWeaponModel)

local CabinCrew = {}

local CABIN_NAME = "IntermissionCabin"
-- each soldier's root over its cockpit seat, in the cabin's frame (floor top, -z forward)
local PILOT_AT = Vector3.new(-1.9, 1.8, -11.3)
local COPILOT_AT = Vector3.new(1.9, 1.8, -11.3)
-- flight suits: a dull olive over the soldier's uniform texture
local SUIT_TORSO = Color3.fromRGB(96, 104, 78)
local SUIT_LEGS = Color3.fromRGB(80, 86, 66)
-- how close to the pilot's head the copilot holds the muzzle
local MUZZLE_GAP = 0.9

export type Member = {
	model: Model,
	humanoid: Humanoid,
	head: BasePart,
	look: IKControl,
	lookTarget: Attachment,
}

export type Crew = {
	cabin: Model,
	pilot: Member,
	copilot: Member,
	aim: IKControl,
	aimTarget: Attachment,
	pistol: Model?,
	muzzle: Attachment?,
	hidden: { [BasePart]: number },
	tracks: { AnimationTrack },
	-- the pilot's slump after the shot (0..1) and the head's knock aside (0..1)
	slump: number,
	knock: number,
	connection: RBXScriptConnection?,
}

local crew: Crew? = nil

local function cabinFrame(cabin: Model): CFrame
	local floor = cabin:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	end
	return cabin:GetPivot()
end

local function attachment(name: string, parent: Instance): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = parent
	return a
end

local function seatedTrack(humanoid: Humanoid): AnimationTrack?
	local id = AssetIds.animation.player.sit_idle
	if typeof(id) ~= "number" or id <= 0 then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	track:Play(0)
	return track
end

local function makeMember(template: Model, name: string, cframe: CFrame, parent: Instance, tracks: { AnimationTrack }): Member?
	local model = template:Clone()
	model.Name = name
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	local upper = model:FindFirstChild("UpperTorso")
	if not humanoid or not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") or not upper or not upper:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	-- a posed prop on an anchored root: no falling or getting-up states
	humanoid.EvaluateStateMachine = false
	model:PivotTo(cframe)
	root.Anchored = true
	model.Parent = parent
	if model:GetAttribute(SoldierBody.ATTRIBUTE) then
		SoldierBody.tint(model, SUIT_TORSO, SUIT_LEGS)
	end
	local track = seatedTrack(humanoid)
	if track then
		table.insert(tracks, track)
	end

	local lookTarget = attachment("CrewLookTarget", root)
	local look = Instance.new("IKControl")
	look.Name = "CrewLook"
	look.Type = Enum.IKControlType.LookAt
	look.ChainRoot = upper
	look.EndEffector = head
	look.Target = lookTarget
	look.Weight = 0
	look.SmoothTime = 0.12
	look.Parent = humanoid
	return { model = model, humanoid = humanoid, head = head, look = look, lookTarget = lookTarget }
end

local function hideBlocks(cabin: Model, hidden: { [BasePart]: number })
	for _, name in { "Pilot", "Copilot" } do
		local figure = cabin:FindFirstChild(name)
		if figure then
			for _, descendant in figure:GetDescendants() do
				if descendant:IsA("BasePart") then
					hidden[descendant] = descendant.LocalTransparencyModifier
					descendant.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

-- The neck and waist after the animator and the IK, every frame: the shot's knock and
-- the slump onto the console.
local function applySlump(current: Crew)
	local model = current.pilot.model
	local waist = model:FindFirstChild("Waist", true)
	local neck = model:FindFirstChild("Neck", true)
	if waist and waist:IsA("Motor6D") and current.slump > 0 then
		waist.Transform = waist.Transform * CFrame.Angles(math.rad(-34) * current.slump, 0, math.rad(9) * current.slump)
	end
	if neck and neck:IsA("Motor6D") and (current.slump > 0 or current.knock > 0) then
		neck.Transform = neck.Transform * CFrame.Angles(math.rad(-30) * current.slump, 0, math.rad(34) * current.knock)
	end
end

-- Builds the crew in the cabin (once); nil when the cabin or the soldier is missing,
-- and the block figures stay.
function CabinCrew.ensure(): Crew?
	local existing = crew
	if existing and existing.cabin.Parent then
		return existing
	end
	local cabin = Workspace:FindFirstChild(CABIN_NAME)
	local template = StarterPlayer:FindFirstChild("StarterCharacter")
	if not cabin or not cabin:IsA("Model") or not template or not template:IsA("Model") then
		return nil
	end
	local frame = cabinFrame(cabin)
	local folder = Instance.new("Folder")
	folder.Name = "CabinCrew"
	folder.Parent = Workspace
	local tracks: { AnimationTrack } = {}
	local pilot = makeMember(template, "CrewPilot", frame * CFrame.new(PILOT_AT), folder, tracks)
	local copilot = makeMember(template, "CrewCopilot", frame * CFrame.new(COPILOT_AT), folder, tracks)
	if not pilot or not copilot then
		folder:Destroy()
		return nil
	end
	folder:SetAttribute("Cabin", cabin.Name)

	-- the copilot's sidearm, holstered (hidden) until the beat brings it up; its muzzle
	-- is carried as an attachment on the hand so the arm's IK can aim the barrel itself
	local pistol: Model? = nil
	local muzzle: Attachment? = nil
	local config = WeaponsConfig.get("Pistol")
	local hand = copilot.model:FindFirstChild("RightHand")
	if config and hand and hand:IsA("BasePart") then
		pistol = WorldWeaponModel.build(copilot.model, config)
		local socket = pistol and pistol:FindFirstChild("Muzzle", true)
		if socket and socket:IsA("Attachment") then
			muzzle = attachment("CrewMuzzle", hand)
			muzzle.WorldCFrame = socket.WorldCFrame
		end
		if pistol then
			for _, descendant in pistol:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CanQuery = false
					descendant.LocalTransparencyModifier = 1
				end
			end
		end
	end
	local copilotRoot = copilot.model:FindFirstChild("HumanoidRootPart") :: BasePart
	local aimTarget = attachment("CrewAimTarget", copilotRoot)
	local aim = Instance.new("IKControl")
	aim.Name = "CrewAim"
	aim.Type = Enum.IKControlType.Transform
	aim.ChainRoot = copilot.model:FindFirstChild("RightUpperArm") :: BasePart
	aim.EndEffector = muzzle or (hand :: BasePart)
	aim.Target = aimTarget
	aim.Weight = 0
	aim.SmoothTime = 0.08
	aim.Parent = copilot.humanoid

	local hidden: { [BasePart]: number } = {}
	hideBlocks(cabin, hidden)

	local current: Crew = {
		cabin = cabin,
		pilot = pilot,
		copilot = copilot,
		aim = aim,
		aimTarget = aimTarget,
		pistol = pistol,
		muzzle = muzzle,
		hidden = hidden,
		tracks = tracks,
		slump = 0,
		knock = 0,
		connection = nil,
	}
	current.connection = RunService.PostSimulation:Connect(function()
		applySlump(current)
	end)
	crew = current
	return current
end

-- The beat's crew poses. `look`, `raise` and `pilotLook` are 0..1 weights from the
-- cinematic's timeline, `slump` and `knock` the shot's aftermath, `recoil` the pistol's
-- kick (0..1).
function CabinCrew.pose(current: Crew, pilotLook: number, copilotLook: number, raise: number, recoil: number, knock: number, slump: number)
	local pilotHead = current.pilot.head.Position
	local copilotHead = current.copilot.head.Position

	current.pilot.lookTarget.WorldPosition = copilotHead
	current.pilot.look.Weight = pilotLook * (1 - knock)
	current.copilot.lookTarget.WorldPosition = pilotHead
	current.copilot.look.Weight = copilotLook

	-- the muzzle a hand's width from the pilot's temple, the barrel on his head
	local from = (pilotHead - copilotHead)
	local flat = Vector3.new(from.X, 0, from.Z)
	local direction = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(-1, 0, 0)
	local muzzleAt = pilotHead - direction * MUZZLE_GAP + Vector3.new(0, 0.05, 0)
	local kick = CFrame.Angles(math.rad(18) * recoil, 0, 0)
	current.aimTarget.WorldCFrame = CFrame.lookAt(muzzleAt, pilotHead) * kick
	current.aim.Weight = raise

	local pistol = current.pistol
	if pistol then
		local shown = if raise > 0.05 then 0 else 1
		for _, descendant in pistol:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = shown
			end
		end
	end
	current.slump = slump
	current.knock = knock
end

-- The muzzle the flash and the shot come from, or nil.
function CabinCrew.muzzle(current: Crew): Attachment?
	return current.muzzle
end

-- Removes the soldiers and shows the block figures again.
function CabinCrew.destroy()
	local current = crew
	if not current then
		return
	end
	crew = nil
	if current.connection then
		(current.connection :: RBXScriptConnection):Disconnect()
	end
	for _, track in current.tracks do
		track:Stop(0)
	end
	for part, before in current.hidden do
		if part.Parent then
			part.LocalTransparencyModifier = before
		end
	end
	local folder = current.pilot.model.Parent
	if folder then
		folder:Destroy()
	end
end

-- the local player only ever sees one cabin; a respawn or a leave drops the crew
Players.LocalPlayer.CharacterRemoving:Connect(function()
	if Players.LocalPlayer:GetAttribute("FlowPhase") ~= "Cabin" then
		CabinCrew.destroy()
	end
end)

return CabinCrew
