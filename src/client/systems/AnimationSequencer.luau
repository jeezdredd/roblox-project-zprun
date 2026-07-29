--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationTimings = require(ReplicatedStorage.Shared.config.AnimationTimings)
local PoseLibrary = require(ReplicatedStorage.Shared.config.PoseLibrary)

-- Plays authored pose sequences and hands the resulting bone offsets back to the
-- viewmodel. It never touches the procedural layer: sway, bob and recoil are applied
-- by Viewmodel on top of whatever this returns.

export type Sequencer = {
	class: string,
	activeId: string?,
	stepIndex: number,
	stepClock: number,
	current: PoseLibrary.Pose,
	fromPose: PoseLibrary.Pose,
	blendClock: number,
	blendFrom: PoseLibrary.Pose,
	phaseListeners: { (string) -> () },
}

local AnimationSequencer = {}
AnimationSequencer.__index = AnimationSequencer

local function easeValue(easing: string, t: number): number
	if easing == "linear" then
		return t
	elseif easing == "outQuad" then
		return 1 - (1 - t) * (1 - t)
	elseif easing == "outCubic" then
		local inv = 1 - t
		return 1 - inv * inv * inv
	elseif easing == "inOutQuad" then
		if t < 0.5 then
			return 2 * t * t
		end
		local inv = -2 * t + 2
		return 1 - inv * inv / 2
	end
	return t
end

local function blendPoses(from: PoseLibrary.Pose, to: PoseLibrary.Pose, alpha: number): PoseLibrary.Pose
	local result: PoseLibrary.Pose = {}
	for bone, cframe in to do
		local origin = from[bone] or CFrame.identity
		result[bone] = origin:Lerp(cframe, alpha)
	end
	for bone, cframe in from do
		if result[bone] == nil then
			result[bone] = cframe:Lerp(CFrame.identity, alpha)
		end
	end
	return result
end

function AnimationSequencer.new(class: string): Sequencer
	local self = setmetatable({
		class = class,
		activeId = nil,
		stepIndex = 0,
		stepClock = 0,
		current = {},
		fromPose = {},
		blendClock = 1,
		blendFrom = {},
		phaseListeners = {},
	}, AnimationSequencer)
	return (self :: any) :: Sequencer
end

function AnimationSequencer:setClass(class: string)
	self.class = class
end

function AnimationSequencer:onPhase(listener: (string) -> ())
	table.insert(self.phaseListeners, listener)
end

function AnimationSequencer:firePhase(name: string)
	for _, listener in self.phaseListeners do
		task.spawn(listener, name)
	end
end

function AnimationSequencer:isPlaying(id: string?): boolean
	if id then
		return self.activeId == id
	end
	return self.activeId ~= nil
end

-- Any sequence can be cut off mid-frame; the current pose becomes the blend origin
-- so the switch never snaps.
function AnimationSequencer:play(id: string)
	local sequence = AnimationTimings.get(id)
	if not sequence then
		return
	end
	if self.activeId == id and sequence.looped then
		return
	end

	self.blendFrom = self.current
	self.blendClock = 0
	self.activeId = id
	self.stepIndex = 1
	self.stepClock = 0
	self.fromPose = self.current

	local firstStep = sequence.steps[1]
	if firstStep and firstStep.phase then
		self:firePhase(firstStep.phase)
	end
end

function AnimationSequencer:stop()
	if not self.activeId then
		return
	end
	self.blendFrom = self.current
	self.blendClock = 0
	self.activeId = nil
	self.stepIndex = 0
	self.stepClock = 0
	self.fromPose = self.current
end

function AnimationSequencer:update(deltaTime: number): PoseLibrary.Pose
	local poses = PoseLibrary.forClass(self.class)
	local target: PoseLibrary.Pose = {}

	local activeId = self.activeId
	if activeId then
		local sequence = AnimationTimings.get(activeId)
		if sequence then
			local step = sequence.steps[self.stepIndex]
			if step then
				self.stepClock += deltaTime
				local duration = math.max(step.duration, 0.0001)
				local alpha = math.clamp(self.stepClock / duration, 0, 1)
				local eased = easeValue(step.easing, alpha)
				target = blendPoses(self.fromPose, poses[step.pose] or {}, eased)

				if alpha >= 1 then
					self.fromPose = poses[step.pose] or {}
					self.stepIndex += 1
					self.stepClock = 0
					local nextStep = sequence.steps[self.stepIndex]
					if nextStep then
						if nextStep.phase then
							self:firePhase(nextStep.phase)
						end
					elseif sequence.looped then
						self.stepIndex = #sequence.steps
						self.stepClock = duration
					else
						self.activeId = nil
						self.stepIndex = 0
					end
				end
			end
		end
	end

	if self.blendClock < 1 then
		self.blendClock = math.min(self.blendClock + deltaTime / AnimationTimings.BLEND_TIME, 1)
		target = blendPoses(self.blendFrom, target, self.blendClock)
	end

	self.current = target
	return target
end

return AnimationSequencer
