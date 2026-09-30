--!strict

-- Plays clips baked by tools/fps_pack (gltf_anim.py + emit_luau.py) on an imported
-- skinned viewmodel by writing Bone.Transform every frame, so pack animations run
-- without uploading Animation assets.
--
-- A track holds, per key, the bone's model-space change from its rest pose (Roblox axes,
-- RootPart space): x, y, z in 1/2000 stud and a quaternion in 1/32767, base64 packed.
-- Roblox's importer drops bones without skin weights and folds their transforms into
-- the children, so baked local transforms would not match; a model-space change applied
-- to each bone's own rest world does:
--     targetWorld = delta(t) * restWorld
--     Transform   = boneCFrame^-1 * parentWorld^-1 * targetWorld
-- Bones are solved parent first. `extras` are nodes without skin (the pack's camera
-- bone) whose rest world was baked alongside; `extraWorld` samples them.

export type ClipData = { duration: number, frames: number, tracks: { [string]: string } }
export type PackData = { fps: number, extras: { [string]: { number } }?, clips: { [string]: ClipData } }

type Track = { frames: { number }, values: { CFrame } }
type Clip = { name: string, duration: number, tracks: { [string]: Track } }
type BoneEntry = { bone: Bone, name: string, parent: number, rest: CFrame, restWorld: CFrame }

export type PlayOptions = {
	speed: number?,
	fade: number?,
	looped: boolean?,
	-- stretch or squeeze the played section (from..to) to last this many seconds
	-- (reload timing from config); overrides `speed`
	duration: number?,
	-- start fraction of the clip (a shell loop skips the clip's idle lead-in)
	from: number?,
	-- end fraction of a one-shot: the clip reports finished there and the caller blends
	-- to the next clip (a tactical reload stops before the bolt pull)
	to: number?,
	-- share of the clip's move away from the pose it started in (1 = as authored): a
	-- lighter version of an authored motion, such as a kick that is too big
	weight: number?,
}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX: { [number]: number } = {}
for i = 1, #B64 do
	B64_INDEX[string.byte(B64, i)] = i - 1
end

local function base64Decode(input: string): buffer
	local clean = string.gsub(input, "[^%w%+/]", "")
	local length = #clean
	local out = buffer.create(length * 3 // 4)
	local o = 0
	for i = 1, length - 3, 4 do
		local a = B64_INDEX[string.byte(clean, i)]
		local b = B64_INDEX[string.byte(clean, i + 1)]
		local c = B64_INDEX[string.byte(clean, i + 2)]
		local d = B64_INDEX[string.byte(clean, i + 3)]
		local n = a * 262144 + b * 4096 + c * 64 + d
		buffer.writeu8(out, o, n // 65536)
		buffer.writeu8(out, o + 1, (n // 256) % 256)
		buffer.writeu8(out, o + 2, n % 256)
		o += 3
	end
	local rest = length % 4
	if rest >= 2 then
		local base = length - rest
		local a = B64_INDEX[string.byte(clean, base + 1)]
		local b = B64_INDEX[string.byte(clean, base + 2)]
		local c = if rest == 3 then B64_INDEX[string.byte(clean, base + 3)] else 0
		local n = a * 262144 + b * 4096 + c * 64
		buffer.writeu8(out, o, n // 65536)
		o += 1
		if rest == 3 then
			buffer.writeu8(out, o, (n // 256) % 256)
			o += 1
		end
	end
	return out
end

local POS_Q = 1 / 2000
local ROT_Q = 1 / 32767

-- frame indices and raw 7-number rows; free of Roblox types so it can be tested
-- outside the engine
local function decodeRaw(encoded: string): ({ number }, { { number } })
	local data = base64Decode(encoded)
	local count = buffer.readu16(data, 0)
	local frames, rows = table.create(count), table.create(count)
	local offset = 2
	for i = 1, count do
		frames[i] = buffer.readu16(data, offset)
		local row = table.create(7)
		for k = 0, 6 do
			local v = buffer.readi16(data, offset + 2 + k * 2)
			row[k + 1] = v * (if k < 3 then POS_Q else ROT_Q)
		end
		rows[i] = row
		offset += 16
	end
	return frames, rows
end

local ViewmodelClipPlayer = {}
ViewmodelClipPlayer.__index = ViewmodelClipPlayer
ViewmodelClipPlayer._decodeRaw = decodeRaw

export type Player = typeof(setmetatable(
	{} :: {
		fps: number,
		scale: number,
		pack: PackData,
		root: BasePart,
		order: { BoneEntry },
		cache: { [string]: Clip },
		current: Clip?,
		time: number,
		-- clip time at which a one-shot finishes (the `to` fraction)
		endTime: number,
		speed: number,
		looped: boolean,
		-- real seconds of the last step that were left over after a one-shot finished,
		-- so the next clip can start in the same frame instead of losing them
		leftover: number,
		fade: number,
		fadeTime: number,
		weight: number,
		from: { [string]: CFrame },
		applied: { [string]: CFrame },
		world: { [string]: CFrame },
	},
	ViewmodelClipPlayer
))

-- `root` is the importer's RootPart holding the Bone tree. Call before any Transform is
-- written so the rest worlds are read from the bind pose. `scale` multiplies the baked
-- translations, for a rig scaled with Model:ScaleTo.
function ViewmodelClipPlayer.new(pack: PackData, root: BasePart, scale: number?): Player
	local order: { BoneEntry } = {}
	local function walk(parent: Instance, parentIndex: number, parentWorld: CFrame)
		for _, child in parent:GetChildren() do
			if child:IsA("Bone") then
				child.Transform = CFrame.identity
				local world = parentWorld * child.CFrame
				table.insert(order, {
					bone = child,
					name = child.Name,
					parent = parentIndex,
					rest = child.CFrame,
					restWorld = world,
				})
				walk(child, #order, world)
			end
		end
	end
	walk(root, 0, CFrame.identity)
	return setmetatable({
		fps = pack.fps,
		scale = scale or 1,
		pack = pack,
		root = root,
		order = order,
		cache = {},
		current = nil,
		time = 0,
		endTime = 0,
		speed = 1,
		looped = false,
		leftover = 0,
		fade = 0,
		fadeTime = 0,
		weight = 1,
		from = {},
		applied = {},
		world = {},
	}, ViewmodelClipPlayer)
end

-- Rest world (RootPart space) of the first bone with this name.
function ViewmodelClipPlayer.restWorld(self: Player, name: string): CFrame?
	for _, entry in self.order do
		if entry.name == name then
			return entry.restWorld
		end
	end
	return nil
end

-- World (RootPart space) the bone was given on the last step, or its rest world.
function ViewmodelClipPlayer.boneWorld(self: Player, name: string): CFrame?
	return self.world[name] or self:restWorld(name)
end

function ViewmodelClipPlayer.has(self: Player, name: string): boolean
	return self.pack.clips[name] ~= nil
end

function ViewmodelClipPlayer.length(self: Player, name: string): number
	local data = self.pack.clips[name]
	return if data then data.duration else 0
end

local function load(self: Player, name: string): Clip?
	local cached = self.cache[name]
	if cached then
		return cached
	end
	local data = self.pack.clips[name]
	if not data then
		return nil
	end
	local tracks: { [string]: Track } = {}
	for joint, encoded in data.tracks do
		local frames, rows = decodeRaw(encoded)
		local values = table.create(#rows)
		local k = self.scale
		for i, r in rows do
			values[i] = CFrame.new(r[1] * k, r[2] * k, r[3] * k, r[4], r[5], r[6], r[7])
		end
		tracks[joint] = { frames = frames, values = values }
	end
	local clip = { name = name, duration = data.duration, tracks = tracks }
	self.cache[name] = clip
	return clip
end

function ViewmodelClipPlayer.preload(self: Player)
	for name in self.pack.clips do
		load(self, name)
	end
end

function ViewmodelClipPlayer.play(self: Player, name: string, options: PlayOptions?): boolean
	local clip = load(self, name)
	if not clip then
		return false
	end
	local opts: PlayOptions = options or {}
	self.from = table.clone(self.applied)
	self.current = clip
	self.looped = opts.looped == true
	local startFraction = math.clamp(opts.from or 0, 0, 1)
	local endFraction = if self.looped then 1 else math.clamp(opts.to or 1, startFraction, 1)
	self.time = startFraction * clip.duration
	self.endTime = endFraction * clip.duration
	self.leftover = 0
	self.speed = opts.speed or 1
	local section = self.endTime - self.time
	if opts.duration and opts.duration > 0 and section > 0 then
		self.speed = section / opts.duration
	end
	self.fadeTime = opts.fade or 0.1
	self.fade = 0
	self.weight = math.clamp(opts.weight or 1, 0, 1)
	return true
end

-- Moves the end of the playing one-shot, never behind the current time. Used to let a
-- shell reach its insert marker and stop there when fire cancels the loop.
function ViewmodelClipPlayer.trim(self: Player, to: number)
	local clip = self.current
	if not clip or self.looped then
		return
	end
	self.endTime = math.max(self.time, math.clamp(to, 0, 1) * clip.duration)
end

-- Drops the current clip; the pose holds until the next play() crossfades out of it.
function ViewmodelClipPlayer.stop(self: Player)
	self.current = nil
end

function ViewmodelClipPlayer.isPlaying(self: Player, name: string?): boolean
	local clip = self.current
	if not clip then
		return false
	end
	return name == nil or clip.name == name
end

local function sample(track: Track, frame: number): CFrame
	local frames, values = track.frames, track.values
	local n = #frames
	if frame <= frames[1] then
		return values[1]
	end
	if frame >= frames[n] then
		return values[n]
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if frames[mid] <= frame then
			lo = mid
		else
			hi = mid
		end
	end
	local u = (frame - frames[lo]) / (frames[hi] - frames[lo])
	return values[lo]:Lerp(values[hi], u)
end

-- The current model-space change of a track (blended through the crossfade, and held at
-- the clip's weight from the pose it started in).
local function delta(self: Player, clip: Clip, name: string, frame: number): CFrame
	local track = clip.tracks[name]
	local target = if track then sample(track, frame) else CFrame.identity
	local from = self.from[name]
	local blend = math.min(self.fade, self.weight)
	if from and blend < 1 then
		target = from:Lerp(target, blend)
	end
	return target
end

-- Rest-relative world (RootPart space) of a baked extra node, e.g. the camera bone.
function ViewmodelClipPlayer.extraWorld(self: Player, name: string): CFrame?
	local extras = self.pack.extras
	local restRow = extras and extras[name]
	if not restRow then
		return nil
	end
	local k = self.scale
	local rest = CFrame.new(restRow[1] * k, restRow[2] * k, restRow[3] * k, restRow[4], restRow[5], restRow[6], restRow[7])
	local d = self.applied[name] or CFrame.identity
	return d * rest
end

-- Advances the clip and writes every bone. Returns true on the step a one-shot clip ends.
function ViewmodelClipPlayer.step(self: Player, deltaTime: number): boolean
	local clip = self.current
	if not clip then
		return false
	end
	local finished = false
	self.leftover = 0
	self.time += deltaTime * self.speed
	if self.looped then
		if self.time >= clip.duration and clip.duration > 0 then
			self.time %= clip.duration
		end
	elseif self.time >= self.endTime then
		if self.speed > 0 then
			self.leftover = math.min((self.time - self.endTime) / self.speed, deltaTime)
		end
		self.time = self.endTime
		finished = true
	end
	if self.fadeTime > 0 then
		self.fade = math.min(1, self.fade + deltaTime / self.fadeTime)
	else
		self.fade = 1
	end
	local frame = self.time * self.fps
	local applied: { [string]: CFrame } = {}
	local byName: { [string]: CFrame } = {}
	local worlds: { CFrame } = table.create(#self.order)
	for index, entry in self.order do
		local parentWorld = if entry.parent > 0 then worlds[entry.parent] else CFrame.identity
		local d = applied[entry.name] or delta(self, clip, entry.name, frame)
		applied[entry.name] = d
		local target = d * entry.restWorld
		entry.bone.Transform = entry.rest:Inverse() * parentWorld:Inverse() * target
		worlds[index] = target
		if byName[entry.name] == nil then
			byName[entry.name] = target
		end
	end
	self.world = byName
	if self.pack.extras then
		for name in self.pack.extras do
			applied[name] = delta(self, clip, name, frame)
		end
	end
	self.applied = applied
	if finished and not self.looped then
		self.current = nil
	end
	return finished
end

return ViewmodelClipPlayer
