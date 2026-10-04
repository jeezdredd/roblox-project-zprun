--!strict

-- First-person rig built from a weapon pack (ReplicatedStorage.ViewModelPacks, loaded by
-- the server's ViewmodelPacks) and driven by its baked clips through ViewmodelClipPlayer.
-- Viewmodel.luau owns the procedural layer (sway, recoil, bob) and hands this module the
-- camera-space placement each frame; this module owns the clips: equip, the idle or walk
-- loop underneath, fire, reload sequences and their sound phases.
--
-- One-shots run as a queue of entries (a clip section with its own speed, fade and
-- phase tag). When the queue runs dry the idle/walk loop is blended back in over the
-- last entry's `blendOut`, which is how a cut reload returns to the ready pose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ViewmodelPackConfig = require(ReplicatedStorage.Shared.config.ViewmodelPackConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local ViewmodelClipPlayer = require(script.Parent.ViewmodelClipPlayer)

local PackViewmodel = {}

-- One clip section in the one-shot queue. `duration` fits the from..to section to that
-- many seconds and wins over `speed`. `tag` travels with every phase the entry emits
-- ("fire", "tactical", "empty", "shell", "chamber", "equip", "inspect") so listeners can
-- tell a pump after a shot (ejects a hull) from the chambering pump after a reload.
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
	-- ViewmodelClipPlayer weight: share of the clip's move that is applied
	weight: number?,
}

export type ReloadPlan = {
	config: WeaponsConfig.WeaponConfig,
	-- the magazine (or tube) was empty: empty clip cut, chambering pump for shells
	empty: boolean,
	-- shell reloads: how many shells go in
	shells: number,
	-- SkillEffects.reloadScale as replicated by the server (1 = config timings)
	scale: number,
}

export type ReloadCancel = {
	-- seconds to blend back to the ready pose (or into the chambering pump)
	exit: number,
	-- seconds of chambering pump after the exit, when nothing is chambered
	chamber: number?,
	-- a shell is in the hand and still goes in before the exit
	finishShell: boolean,
}

export type Rig = {
	class: string,
	pack: ViewmodelPackConfig.ClassPack,
	model: Model,
	root: BasePart,
	player: ViewmodelClipPlayer.Player,
	parts: { BasePart },
	-- each part's CFrame relative to the root; the parts follow the root every frame
	offsets: { CFrame },
	placed: { CFrame },
	muzzle: Attachment,
	eject: Attachment,
	muzzleLocal: CFrame,
	ejectLocal: CFrame,
	eyeInverse: CFrame,
	-- the class's `hold` offset, applied between the camera and the eye point, the one
	-- used while a reload, draw or inspect plays, and the blend between them (1 = action)
	hold: CFrame,
	actionHold: CFrame,
	holdBlend: number,
	-- the wall pull-back on top of the hold (WallPullback): identity in the open
	wallPose: CFrame,
	-- the stance, magazine check and lean counter-pose on top of that (Stances):
	-- identity at mid with no lean
	stancePose: CFrame,
	-- looping clip underneath (idle or walk), nil while a one-shot plays
	base: string?,
	queue: { Entry },
	-- the one-shot playing now, nil while the base loop plays
	entry: Entry?,
	-- clip time phases were last checked at
	phaseTime: number,
	-- fade for the next return to the base loop
	returnFade: number,
}

local DEFAULT_RETURN_FADE = 0.25
-- a shot out of a reload, equip or inspect pose: MW blends the cut over 0.1-0.15 s,
-- a hard cut would pop the arms across the screen
local INTERRUPT_FADE = 0.12
-- a shot out of idle or another shot: the kick has to land on the frame
local SNAP_FADE = 0.03
local CHAIN_FADE = 0.08
-- fire + follow (pump) must close within this share of the fire interval
local FOLLOW_BUDGET = 0.9
local MAX_FOLLOW_SPEED = 1.5
-- how far past the ShellIn marker a cancelled shell is allowed to run
local SEAT_MARGIN = 0.015
local MAX_TRANSITIONS_PER_STEP = 4
-- time constant of the blend between `hold` and `actionHold`
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
	local folder = ReplicatedStorage.Shared:FindFirstChild("viewmodel_clips")
	local module = folder and folder:FindFirstChild(pack.clips)
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

function PackViewmodel.available(class: string): boolean
	local pack = ViewmodelPackConfig.get(class)
	return pack ~= nil and template(class) ~= nil and clipData(pack) ~= nil
end

-- Front and top of the weapon mesh at rest, expressed in the weapon bone's frame so it
-- follows the bone through every clip. The packs' weapons point down -Z in rig space.
local function weaponAnchors(model: Model, root: BasePart, pack: ViewmodelPackConfig.ClassPack, boneRest: CFrame): (CFrame, CFrame)
	local mesh: BasePart? = nil
	for _, item in model:GetDescendants() do
		if item:IsA("MeshPart") and string.find(item.Name, pack.weaponMesh) then
			mesh = item
			break
		end
	end
	if not mesh then
		return CFrame.identity, CFrame.identity
	end
	local local_ = root.CFrame:ToObjectSpace(mesh.CFrame)
	local size = mesh.Size
	local inverse = boneRest:Inverse()
	local tilt = pack.restTilt
	if not tilt then
		local front = local_ * CFrame.new(0, size.Y * 0.28, -size.Z * 0.5)
		local port = local_ * CFrame.new(size.X * 0.5, size.Y * 0.3, -size.Z * 0.05)
		return inverse * front, inverse * port
	end
	-- a turned rest pose: measure the mesh box along the upright rig axes and put the
	-- anchors back into rest space with the upright orientation turned by `tilt`
	local upright = tilt:Inverse() * local_
	local r = upright.Rotation
	local function extent(axis: Vector3): number
		return math.abs(r.XVector:Dot(axis)) * size.X + math.abs(r.YVector:Dot(axis)) * size.Y + math.abs(r.ZVector:Dot(axis)) * size.Z
	end
	local ex, ey, ez = extent(Vector3.xAxis), extent(Vector3.yAxis), extent(Vector3.zAxis)
	local center = upright.Position
	local front = tilt * CFrame.new(center + Vector3.new(0, ey * 0.28, -ez * 0.5))
	local port = tilt * CFrame.new(center + Vector3.new(ex * 0.5, ey * 0.3, -ez * 0.05))
	return inverse * front, inverse * port
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

-- Replaces whatever plays with `entries` back to back. Entries whose clip is missing
-- from the pack are skipped.
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

-- Back to the idle/walk loop over `fade` seconds from wherever the arms are now.
local function returnToBase(rig: Rig, fade: number)
	rig.queue = {}
	rig.entry = nil
	rig.base = nil
	rig.returnFade = fade
	rig.player:stop()
end

function PackViewmodel.build(class: string, camera: Camera): Rig?
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
	model:ScaleTo(scale)
	-- The parts are anchored, so moving the root leaves them where the template had them.
	-- The skinned meshes still draw on the bones, but the engine picks each mesh's level
	-- of detail (and its bounds) from the part: left near the world origin, thousands of
	-- studs from the camera, the arms rendered from the lowest detail level and parts of
	-- the left arm flickered into the view for single frames (the owner's recording,
	-- 2026-10-01). The parts are carried with the root every frame instead.
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
		-- the rig starts on the draw
		holdBlend = 1,
		wallPose = CFrame.identity,
		stancePose = CFrame.identity,
		base = nil,
		queue = {},
		entry = nil,
		phaseTime = 0,
		returnFade = DEFAULT_RETURN_FADE,
	}
	-- the draw always plays at natural speed; WeaponsConfig.drawTime decides when a shot
	-- may cut its tail
	playEntry(rig, { name = pack.equip, tag = "equip" })
	return rig
end

-- The wall pull-back's pose for the next steps, in the hold space (WallPullback eases
-- it; identity puts the gun back in the ready pose).
function PackViewmodel.setWallPose(rig: Rig, pose: CFrame)
	rig.wallPose = pose
end

-- The stance pose for the next steps, in the hold space after the wall pose (Stances
-- eases it; identity is the class's own hold).
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

-- One-shot clip; the idle or walk loop resumes underneath when it ends.
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

-- Clips back to back, stretched together to `duration` when given.
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

-- `interval` is the weapon's fire interval. A class with a follow clip (the pump) keeps
-- only the recoil part of Fire and speeds both up together, no faster than 1.5x, so
-- the action is closed before the next shot is allowed.
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

-- Magazine reloads play one clip section fitted to the config time (tactical cut or
-- empty), shell reloads build enter + N shells + leave (+ pump from empty).
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

-- Fire (or a swap) interrupting a reload. For shells the one in the hand still reaches
-- its ShellIn marker, then the arms blend back over `exit` (or into the chambering
-- pump); anything else blends back right away.
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

-- Emits the markers the stepped clip crossed. `clip` is the clip that was playing
-- before the step, so a marker right at the end still fires on the step that finishes
-- the clip, and a cut clip never reaches the markers past its end.
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

-- Makes sure something plays: the next queued entry, else the idle/walk loop.
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

-- `placement` is the camera CFrame with the procedural offsets applied; the rig's eye
-- point is put on it.
function PackViewmodel.step(rig: Rig, deltaTime: number, placement: CFrame, moving: boolean, onPhase: (string, string?) -> ())
	local player = rig.player
	-- debug knob for checking clips frame by frame from the command bar:
	-- workspace.CurrentCamera:SetAttribute("ViewmodelTimeScale", 0.1)
	local camera = rig.model.Parent
	local timeScale = if camera then camera:GetAttribute("ViewmodelTimeScale") else nil
	if typeof(timeScale) == "number" then
		deltaTime *= math.max(timeScale, 0)
	end

	-- A clip that ends mid-frame hands the rest of the frame to the next one, so a chain
	-- of short sections (shell after shell) stays on the WeaponsConfig timeline instead
	-- of losing a frame at every seam.
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

	local entry = rig.entry
	local tag = if entry then entry.tag else nil
	local blendTarget = if tag and SOFT_TAGS[tag] then 1 else 0
	rig.holdBlend += (blendTarget - rig.holdBlend) * (1 - math.exp(-deltaTime / HOLD_BLEND_TIME))

	-- framing knob for tuning a class's `hold` from the command bar:
	-- workspace.CurrentCamera:SetAttribute("ViewmodelHold", Vector3.new(0.05, -0.1, 0.05))
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
	local weapon = player:boneWorld(rig.pack.weaponBone)
	if weapon then
		rig.muzzle.CFrame = weapon * rig.muzzleLocal
		rig.eject.CFrame = weapon * rig.ejectLocal
	end
end

return PackViewmodel
