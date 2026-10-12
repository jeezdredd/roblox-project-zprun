--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ViewmodelPackConfig = require(ReplicatedStorage.Shared.config.ViewmodelPackConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ViewmodelClipPlayer = require(script.Parent.ViewmodelClipPlayer)
local DroppedMagazines = require(script.Parent.DroppedMagazines)

local PackViewmodel = {}

export type Entry = {
	name: string,
	speed: number?,
	duration: number?,
	from: number?,
	to: number?,
	fade: number?,
	tag: string?,
	phases: { ViewmodelPackConfig.Phase }?,
	blendOut: number?,
	weight: number?,
}

export type ReloadPlan = {
	config: WeaponsConfig.WeaponConfig,
	empty: boolean,
	shells: number,
	scale: number,
}

export type ReloadCancel = {
	exit: number,
	chamber: number?,
	finishShell: boolean,
}

export type Rig = {
	class: string,
	pack: ViewmodelPackConfig.ClassPack,
	model: Model,
	root: BasePart,
	player: ViewmodelClipPlayer.Player,
	parts: { BasePart },
	offsets: { CFrame },
	placed: { CFrame },
	muzzle: Attachment,
	eject: Attachment,
	muzzleLocal: CFrame,
	ejectLocal: CFrame,
	eyeInverse: CFrame,
	hold: CFrame,
	actionHold: CFrame,
	holdBlend: number,
	wallPose: CFrame,
	stancePose: CFrame,
	base: string?,
	queue: { Entry },
	entry: Entry?,
	phaseTime: number,
	returnFade: number,
	empty: boolean,
	locked: boolean,
	lockHolds: { { bone: Bone, pose: CFrame } },
	dropped: boolean,
	hiddenParts: { [BasePart]: number },
	partIndex: { [BasePart]: number },
}

local DEFAULT_RETURN_FADE = 0.25
local INTERRUPT_FADE = 0.12
local SNAP_FADE = 0.03
local CHAIN_FADE = 0.08
local FOLLOW_BUDGET = 0.9
local MAX_FOLLOW_SPEED = 1.5
local SEAT_MARGIN = 0.015
local MAX_TRANSITIONS_PER_STEP = 4
local HOLD_BLEND_TIME = 0.1

local SOFT_TAGS: { [string]: boolean } = {
	equip = true,
	inspect = true,
	tactical = true,
	empty = true,
	shell = true,
	chamber = true,
}

local clipCache: { [string]: ViewmodelClipPlayer.PackData } = {}

local function anglesOf(degrees: Vector3?): CFrame
	if not degrees then
		return CFrame.identity
	end
	return CFrame.fromEulerAnglesYXZ(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

local function clipData(pack: ViewmodelPackConfig.ClassPack): ViewmodelClipPlayer.PackData?
	local cached = clipCache[pack.clips]
	if cached then
		return cached
	end
	local module: Instance? = nil
	for _, name in { "viewmodel_clips", "fab", "unity" } do
		local folder = ReplicatedStorage.Shared:FindFirstChild(name)
		module = folder and folder:FindFirstChild(pack.clips)
		if module then
			break
		end
	end
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, data = pcall(require, module)
	if not ok then
		warn(`[PackViewmodel] {pack.clips} failed to load: {data}`)
		return nil
	end
	clipCache[pack.clips] = data :: any
	return data :: any
end

local function template(class: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("ViewModelPacks")
	local model = folder and folder:FindFirstChild(class)
	return if model and model:IsA("Model") then model else nil
end

function PackViewmodel.preloadPacks()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("ViewModelPacks", 30)
		if not folder then
			return
		end
		local function warm(model: Instance)
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync({ model })
				end)
			end)
		end
		for _, model in folder:GetChildren() do
			warm(model)
		end
		folder.ChildAdded:Connect(warm)
	end)
end

function PackViewmodel.available(class: string): boolean
	local pack = ViewmodelPackConfig.get(class)
	return pack ~= nil and template(class) ~= nil and clipData(pack) ~= nil
end

local function weaponAnchors(model: Model, root: BasePart, pack: ViewmodelPackConfig.ClassPack, boneRest: CFrame): (CFrame, CFrame)
	local inverse = boneRest:Inverse()
	local explicit: CFrame? = nil
	if pack.muzzle then
		local position = pack.muzzle.position * (ViewmodelPackConfig.RIG_SCALE * (pack.importScale or 1))
		explicit = inverse * CFrame.lookAt(position, position + pack.muzzle.direction)
	end
	local mesh: BasePart? = nil
	for _, item in model:GetDescendants() do
		if item:IsA("MeshPart") and string.find(item.Name, pack.weaponMesh) then
			mesh = item
			break
		end
	end
	if not mesh then
		return explicit or CFrame.identity, CFrame.identity
	end
	local local_ = root.CFrame:ToObjectSpace(mesh.CFrame)
	local size = mesh.Size
	local tilt = pack.restTilt
	if not tilt then
		local front = local_ * CFrame.new(0, size.Y * 0.28, -size.Z * 0.5)
		local port = local_ * CFrame.new(size.X * 0.5, size.Y * 0.3, -size.Z * 0.05)
		return explicit or inverse * front, inverse * port
	end
	local upright = tilt:Inverse() * local_
	local r = upright.Rotation
	local function extent(axis: Vector3): number
		return math.abs(r.XVector:Dot(axis)) * size.X + math.abs(r.YVector:Dot(axis)) * size.Y + math.abs(r.ZVector:Dot(axis)) * size.Z
	end
	local ex, ey, ez = extent(Vector3.xAxis), extent(Vector3.yAxis), extent(Vector3.zAxis)
	local center = upright.Position
	local front = tilt * CFrame.new(center + Vector3.new(0, ey * 0.28, -ez * 0.5))
	local port = tilt * CFrame.new(center + Vector3.new(ex * 0.5, ey * 0.3, -ez * 0.05))
	return explicit or inverse * front, inverse * port
end

local function start(rig: Rig, entry: Entry): boolean
	local ok = rig.player:play(entry.name, {
		speed = entry.speed,
		duration = entry.duration,
		from = entry.from,
		to = entry.to,
		fade = entry.fade,
		weight = entry.weight,
	})
	if ok then
		rig.base = nil
		rig.entry = entry
		rig.phaseTime = rig.player.time
		rig.returnFade = entry.blendOut or DEFAULT_RETURN_FADE
	end
	return ok
end

local function runQueue(rig: Rig, entries: { Entry }): boolean
	rig.queue = entries
	while #rig.queue > 0 do
		local entry = table.remove(rig.queue, 1) :: Entry
		if start(rig, entry) then
			return true
		end
	end
	return false
end

local function playEntry(rig: Rig, entry: Entry): boolean
	return runQueue(rig, { entry })
end

local function returnToBase(rig: Rig, fade: number)
	rig.queue = {}
	rig.entry = nil
	rig.base = nil
	rig.returnFade = fade
	rig.player:stop()
end

function PackViewmodel.build(class: string, camera: Camera, drawTime: number?): Rig?
	local pack = ViewmodelPackConfig.get(class)
	local source = template(class)
	local data = if pack then clipData(pack) else nil
	if not pack or not source or not data then
		return nil
	end
	local model = source:Clone()
	local root = model:FindFirstChild("RootPart", true)
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	local scale = ViewmodelPackConfig.RIG_SCALE
	model:ScaleTo(scale * (pack.importScale or 1))
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and item ~= root then
			table.insert(parts, item)
			table.insert(offsets, root.CFrame:ToObjectSpace(item.CFrame))
		end
	end
	root.CFrame = CFrame.identity

	local player = ViewmodelClipPlayer.new(data, root, scale)
	local boneRest = player:restWorld(pack.weaponBone) or CFrame.identity
	local muzzleLocal, ejectLocal = weaponAnchors(model, root, pack, boneRest)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = root
	local eject = Instance.new("Attachment")
	eject.Name = "Eject"
	eject.Parent = root

	model.Name = "Viewmodel"
	model.Parent = camera
	player:preload()

	local rig: Rig = {
		class = class,
		pack = pack,
		model = model,
		root = root,
		player = player,
		parts = parts,
		offsets = offsets,
		placed = table.create(#parts),
		muzzle = muzzle,
		eject = eject,
		muzzleLocal = muzzleLocal,
		ejectLocal = ejectLocal,
		eyeInverse = (CFrame.new(pack.eye.Position * scale) * pack.eye.Rotation):Inverse(),
		hold = CFrame.new(pack.hold or Vector3.zero) * anglesOf(pack.holdAngles),
		actionHold = CFrame.new(pack.actionHold or pack.hold or Vector3.zero),
		holdBlend = 1,
		wallPose = CFrame.identity,
		stancePose = CFrame.identity,
		base = nil,
		queue = {},
		entry = nil,
		phaseTime = 0,
		returnFade = DEFAULT_RETURN_FADE,
		empty = false,
		locked = false,
		lockHolds = {},
		dropped = false,
		hiddenParts = {},
		partIndex = {},
	}
	for index, part in parts do
		rig.partIndex[part] = index
	end
	for _, cut in pack.cuts or {} do
		player:cut(cut.clip, cut.bones, cut.frame)
	end
	local lock = pack.lockBack
	if lock then
		for _, name in lock.bones do
			local pose = player:localPose(name, lock.clip, 0)
			for _, item in model:GetDescendants() do
				if item:IsA("Bone") and item.Name == name then
					if pose then
						table.insert(rig.lockHolds, { bone = item, pose = pose })
					end
					break
				end
			end
		end
	end
	playEntry(rig, { name = pack.equip, from = pack.equipFrom, to = pack.equipTo, duration = drawTime, tag = "equip" })
	return rig
end

function PackViewmodel.setEmpty(rig: Rig, empty: boolean)
	rig.empty = empty
end

local function partsMatching(rig: Rig, pattern: string, bone: string?): { BasePart }
	local found: { BasePart } = {}
	for _, part in rig.parts do
		if string.find(part.Name, pattern) then
			table.insert(found, part)
		end
	end
	local rest = if bone and #found > 1 then rig.player:restWorld(bone) else nil
	if not rest then
		return found
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, part in found do
		local distance = (rig.offsets[rig.partIndex[part]].Position - rest.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return if best then { best } else {}
end

local function setHidden(rig: Rig, part: BasePart, hidden: boolean)
	local saved = rig.hiddenParts[part]
	if hidden and saved == nil then
		rig.hiddenParts[part] = part.Transparency
		part.Transparency = 1
	elseif not hidden and saved ~= nil then
		part.Transparency = saved
		rig.hiddenParts[part] = nil
	end
end

local function updateLockBack(rig: Rig)
	if #rig.lockHolds == 0 then
		return
	end
	local entry = rig.entry
	local want = rig.empty and not (entry ~= nil and entry.tag == "empty")
	if want ~= rig.locked then
		rig.locked = want
		rig.model:SetAttribute("LockedBack", want)
	end
	if want then
		for _, hold in rig.lockHolds do
			hold.bone.Transform = hold.pose
		end
	end
end

local function updateMagDrop(rig: Rig, rootCFrame: CFrame)
	local drop = rig.pack.magDrop
	if not drop then
		return
	end
	local entry = rig.entry
	local current = rig.player.current
	local active = entry ~= nil and entry.tag == "empty" and current ~= nil and current.name == drop.clip
	local fraction = if active and current and current.duration > 0 then rig.player.time / current.duration else -1
	for _, window in drop.hidden do
		local hide = active and fraction >= window.from and fraction < window.to
		for _, part in partsMatching(rig, window.part, window.bone) do
			setHidden(rig, part, hide)
		end
	end
	if not active then
		rig.dropped = false
		return
	end
	if rig.dropped or fraction < drop.at then
		return
	end
	rig.dropped = true
	local pieces: { DroppedMagazines.Piece } = {}
	for _, piece in drop.pieces do
		local bone = rig.player:boneWorld(piece.bone)
		local rest = rig.player:restWorld(piece.bone)
		if not bone or not rest then
			continue
		end
		local skin: { [string]: CFrame }? = nil
		if piece.skin then
			local worlds: { [string]: CFrame } = {}
			for _, name in piece.skin do
				local world = rig.player:boneWorld(name)
				if world then
					worlds[name] = rootCFrame * world
				end
			end
			skin = worlds
		end
		for _, part in partsMatching(rig, piece.part, piece.bone) do
			local offset = rig.offsets[rig.partIndex[part]]
			local bones: { [string]: CFrame }? = skin
			local body = piece.body
			if skin and piece.tuck and part:IsA("MeshPart") then
				local tucked = table.clone(skin)
				local toPart = part.Size / part.MeshSize
				local carry = bone * rest:Inverse()
				for name, move in piece.tuck do
					local tuckRest = rig.player:restWorld(name)
					if tuckRest then
						local shift = offset * (move.to * toPart) - offset * (move.from * toPart)
						tucked[name] = rootCFrame * carry * CFrame.new(shift) * tuckRest
					end
				end
				bones = tucked
			end
			table.insert(pieces, {
				part = part,
				cframe = rootCFrame * bone * rest:Inverse() * offset,
				bones = bones,
				body = body,
			})
		end
	end
	local camera = rig.model.Parent
	if not camera or not camera:IsA("Camera") then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local velocity = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
	DroppedMagazines.drop(pieces, camera.CFrame.Position, drop.worldScale, velocity)
end

function PackViewmodel.setWallPose(rig: Rig, pose: CFrame)
	rig.wallPose = pose
end

function PackViewmodel.setStancePose(rig: Rig, pose: CFrame)
	rig.stancePose = pose
end

function PackViewmodel.destroy(rig: Rig)
	rig.model:Destroy()
end

function PackViewmodel.setVisible(rig: Rig, visible: boolean)
	for _, part in rig.parts do
		part.LocalTransparencyModifier = if visible then 0 else 1
	end
end

function PackViewmodel.play(rig: Rig, name: string, options: ViewmodelClipPlayer.PlayOptions?): boolean
	local opts: ViewmodelClipPlayer.PlayOptions = options or {}
	return playEntry(rig, {
		name = name,
		speed = opts.speed,
		duration = opts.duration,
		from = opts.from,
		to = opts.to,
		fade = opts.fade,
	})
end

function PackViewmodel.playSequence(rig: Rig, names: { string }, duration: number?, tag: string?)
	local present = {}
	local total = 0
	for _, name in names do
		if rig.player:has(name) then
			table.insert(present, name)
			total += rig.player:length(name)
		end
	end
	if #present == 0 then
		return
	end
	local stretch = if duration and duration > 0 and total > 0 then duration / total else 1
	local entries: { Entry } = {}
	for index, name in present do
		table.insert(entries, {
			name = name,
			duration = rig.player:length(name) * stretch,
			fade = if index == 1 then INTERRUPT_FADE else CHAIN_FADE,
			tag = tag,
		})
	end
	runQueue(rig, entries)
end

local function currentFireFade(rig: Rig): number
	local entry = rig.entry
	local tag = entry and entry.tag
	return if tag and SOFT_TAGS[tag] then INTERRUPT_FADE else SNAP_FADE
end

function PackViewmodel.fire(rig: Rig, interval: number?)
	local pack = rig.pack
	local player = rig.player
	local fade = currentFireFade(rig)
	local follow = pack.fireFollow
	if not follow or not player:has(follow) then
		playEntry(rig, { name = pack.fire, fade = fade, tag = "fire", weight = pack.fireWeight })
		return
	end
	local fireTo = pack.fireTo or 1
	local natural = player:length(pack.fire) * fireTo + player:length(follow) * (pack.followReady or 1)
	local speed = 1
	if interval and interval > 0 and natural > 0 then
		speed = math.clamp(natural / (interval * FOLLOW_BUDGET), 1, MAX_FOLLOW_SPEED)
	end
	runQueue(rig, {
		{ name = pack.fire, speed = speed, to = fireTo, fade = fade, tag = "fire", weight = pack.fireWeight },
		{ name = follow, speed = speed, fade = CHAIN_FADE, tag = "fire" },
	})
end

local function reloadShells(rig: Rig, shell: ViewmodelPackConfig.ShellClips, timing: WeaponsConfig.ShellReload, plan: ReloadPlan)
	local scale = plan.scale
	local entries: { Entry } = {
		{ name = shell.enter, duration = timing.start * scale, fade = INTERRUPT_FADE, tag = "shell" },
	}
	local loop = shell.loop
	for _ = 1, plan.shells do
		table.insert(entries, {
			name = loop.clip,
			from = loop.from,
			to = loop.to,
			duration = timing.perShell * scale,
			fade = CHAIN_FADE,
			tag = "shell",
			phases = loop.phases,
		})
	end
	table.insert(entries, { name = shell.leave, duration = timing.finish * scale, fade = CHAIN_FADE, tag = "shell" })
	if plan.empty then
		local chamber = shell.chamber
		table.insert(entries, {
			name = chamber.clip,
			from = chamber.from,
			to = chamber.to,
			duration = timing.chamber * scale,
			fade = CHAIN_FADE,
			tag = "chamber",
			phases = chamber.phases,
			blendOut = chamber.blendOut,
		})
	end
	runQueue(rig, entries)
end

function PackViewmodel.reload(rig: Rig, plan: ReloadPlan)
	local config = plan.config
	local pack = rig.pack
	local scale = plan.scale
	if config.reloadStyle == "shell" then
		local shell = pack.shell
		local timing = config.shellReload
		if shell and timing then
			reloadShells(rig, shell, timing, plan)
		else
			local total = WeaponsConfig.shellReloadTime(config, plan.shells, plan.empty, scale)
			PackViewmodel.playSequence(rig, pack.reload, total, "shell")
		end
		return
	end

	local _, total = WeaponsConfig.magazineReload(config, plan.empty, scale)
	local tag = if plan.empty then "empty" else "tactical"
	local cut = if plan.empty then pack.empty or pack.tactical else pack.tactical
	if cut and rig.player:has(cut.clip) then
		local blend = (cut.blendOut or 0) * scale
		playEntry(rig, {
			name = cut.clip,
			from = cut.from,
			to = cut.to,
			duration = math.max(total - blend, 0.1),
			fade = INTERRUPT_FADE,
			tag = tag,
			phases = cut.phases,
			blendOut = if blend > 0 then blend else nil,
		})
		return
	end
	local names = if plan.empty and pack.reloadEmpty then pack.reloadEmpty else pack.reload
	PackViewmodel.playSequence(rig, names, total, tag)
end

local function shellSeat(pack: ViewmodelPackConfig.ClassPack, loop: ViewmodelPackConfig.ClipCut): number
	local lists: { { ViewmodelPackConfig.Phase }? } = { pack.phases[loop.clip], loop.phases }
	for index = 1, 2 do
		local list = lists[index]
		if list then
			for _, phase in list do
				if phase.name == "ShellIn" then
					return phase.at
				end
			end
		end
	end
	return loop.to or 1
end

function PackViewmodel.cancelReload(rig: Rig, cancel: ReloadCancel)
	local shell = rig.pack.shell
	local chamberEntry: Entry? = nil
	if shell and cancel.chamber and cancel.chamber > 0 then
		local chamber = shell.chamber
		chamberEntry = {
			name = chamber.clip,
			from = chamber.from,
			to = chamber.to,
			duration = cancel.exit + cancel.chamber,
			fade = cancel.exit,
			tag = "chamber",
			phases = chamber.phases,
			blendOut = chamber.blendOut,
		}
	end
	local entry = rig.entry
	if cancel.finishShell and shell and entry and entry.tag == "shell" and entry.name == shell.loop.clip and rig.player:isPlaying(entry.name) then
		rig.player:trim(shellSeat(rig.pack, shell.loop) + SEAT_MARGIN)
		rig.queue = if chamberEntry then { chamberEntry } else {}
		rig.returnFade = cancel.exit
		return
	end
	if chamberEntry then
		playEntry(rig, chamberEntry)
		return
	end
	returnToBase(rig, cancel.exit)
end

function PackViewmodel.isReloading(rig: Rig): boolean
	local entry = rig.entry
	local tag = entry and entry.tag
	return tag == "tactical" or tag == "empty" or tag == "shell" or tag == "chamber"
end

function PackViewmodel.inspect(rig: Rig): boolean
	local name = rig.pack.inspect
	if not name or not rig.player:has(name) then
		return false
	end
	return playEntry(rig, { name = name, fade = 0.2, tag = "inspect" })
end

local function firePhases(rig: Rig, clipName: string?, clipDuration: number, onPhase: (string, string?) -> ())
	local entry = rig.entry
	local time = rig.player.time
	if not clipName or not entry or entry.name ~= clipName or clipDuration <= 0 then
		rig.phaseTime = time
		return
	end
	local before = rig.phaseTime / clipDuration
	local now = time / clipDuration
	rig.phaseTime = time
	if now <= before then
		return
	end
	local lists: { { ViewmodelPackConfig.Phase }? } = { rig.pack.phases[clipName], entry.phases }
	for index = 1, 2 do
		local list = lists[index]
		if list then
			for _, phase in list do
				if phase.at > before and phase.at <= now then
					onPhase(phase.name, entry.tag)
				end
			end
		end
	end
end

local function desiredBase(rig: Rig, moving: boolean): string
	local pack = rig.pack
	return if moving and pack.move and rig.player:has(pack.move) then pack.move else pack.idle
end

local function advance(rig: Rig, moving: boolean)
	local player = rig.player
	if player:isPlaying() then
		local desired = desiredBase(rig, moving)
		if rig.base ~= nil and rig.base ~= desired then
			player:play(desired, { looped = true, fade = DEFAULT_RETURN_FADE })
			rig.base = desired
			rig.entry = nil
		end
		return
	end
	while #rig.queue > 0 do
		local entry = table.remove(rig.queue, 1) :: Entry
		if start(rig, entry) then
			return
		end
	end
	local base = desiredBase(rig, moving)
	player:play(base, { looped = true, fade = rig.returnFade })
	rig.base = base
	rig.entry = nil
	rig.returnFade = DEFAULT_RETURN_FADE
end

function PackViewmodel.step(rig: Rig, deltaTime: number, placement: CFrame, moving: boolean, onPhase: (string, string?) -> ())
	local player = rig.player
	local camera = rig.model.Parent
	local timeScale = if camera then camera:GetAttribute("ViewmodelTimeScale") else nil
	if typeof(timeScale) == "number" then
		deltaTime *= math.max(timeScale, 0)
	end

	local remaining = deltaTime
	for _ = 1, MAX_TRANSITIONS_PER_STEP do
		advance(rig, moving)
		local current = player.current
		local clipName = if current then current.name else nil
		local clipDuration = if current then current.duration else 0
		local finished = player:step(remaining)
		firePhases(rig, clipName, clipDuration, onPhase)
		if not finished then
			break
		end
		remaining = player.leftover
		if remaining <= 1e-4 then
			break
		end
	end

	updateLockBack(rig)
	local entry = rig.entry
	local tag = if entry then entry.tag else nil
	local blendTarget = if tag and SOFT_TAGS[tag] then 1 else 0
	rig.holdBlend += (blendTarget - rig.holdBlend) * (1 - math.exp(-deltaTime / HOLD_BLEND_TIME))

	local tune = if camera then camera:GetAttribute("ViewmodelHold") else nil
	local tuneAngles = if camera then camera:GetAttribute("ViewmodelHoldAngles") else nil
	local hold = rig.hold:Lerp(rig.actionHold, rig.holdBlend)
	if typeof(tune) == "Vector3" or typeof(tuneAngles) == "Vector3" then
		local offset = if typeof(tune) == "Vector3" then tune else hold.Position
		hold = CFrame.new(offset) * anglesOf(if typeof(tuneAngles) == "Vector3" then tuneAngles else nil)
	end
	local rootCFrame = placement * hold * rig.wallPose * rig.stancePose * rig.eyeInverse
	rig.root.CFrame = rootCFrame
	for index, offset in rig.offsets do
		rig.placed[index] = rootCFrame * offset
	end
	Workspace:BulkMoveTo(rig.parts, rig.placed, Enum.BulkMoveMode.FireCFrameChanged)
	updateMagDrop(rig, rootCFrame)
	local weapon = player:boneWorld(rig.pack.weaponBone)
	if weapon then
		rig.muzzle.CFrame = weapon * rig.muzzleLocal
		rig.eject.CFrame = weapon * rig.ejectLocal
	end
end

return PackViewmodel
