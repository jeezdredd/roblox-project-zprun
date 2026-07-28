--!strict

-- Semi-implicit Euler spring integrator.
-- An underdamped spring given an impulse overshoots its target and settles with a
-- decaying wobble: Spring.number(120, 12, 0) with :Impulse(10) rises past 0, crosses
-- back, and converges to 0 within roughly a second. Critical damping is damping =
-- 2 * sqrt(stiffness); values below that overshoot, values above crawl in.

local MAX_STEP = 1 / 30

export type NumberSpring = {
	value: number,
	velocity: number,
	target: number,
	stiffness: number,
	damping: number,
	SetTarget: (NumberSpring, number) -> (),
	Impulse: (NumberSpring, number) -> (),
	SetProperties: (NumberSpring, number, number) -> (),
	Reset: (NumberSpring, number) -> (),
	Update: (NumberSpring, number) -> number,
}

export type VectorSpring = {
	value: Vector3,
	velocity: Vector3,
	target: Vector3,
	stiffness: number,
	damping: number,
	SetTarget: (VectorSpring, Vector3) -> (),
	Impulse: (VectorSpring, Vector3) -> (),
	SetProperties: (VectorSpring, number, number) -> (),
	Reset: (VectorSpring, Vector3) -> (),
	Update: (VectorSpring, number) -> Vector3,
}

local Spring = {}

local NumberImpl = {}
NumberImpl.__index = NumberImpl

function NumberImpl:SetTarget(value: number)
	self.target = value
end

function NumberImpl:Impulse(value: number)
	self.velocity += value
end

function NumberImpl:SetProperties(stiffness: number, damping: number)
	self.stiffness = stiffness
	self.damping = damping
end

function NumberImpl:Reset(value: number)
	self.value = value
	self.target = value
	self.velocity = 0
end

function NumberImpl:Update(deltaTime: number): number
	local remaining = math.min(deltaTime, 0.25)
	while remaining > 0 do
		local step = math.min(remaining, MAX_STEP)
		remaining -= step
		local displacement = self.value - self.target
		self.velocity -= (self.stiffness * displacement + self.damping * self.velocity) * step
		self.value += self.velocity * step
	end
	return self.value
end

local VectorImpl = {}
VectorImpl.__index = VectorImpl

function VectorImpl:SetTarget(value: Vector3)
	self.target = value
end

function VectorImpl:Impulse(value: Vector3)
	self.velocity += value
end

function VectorImpl:SetProperties(stiffness: number, damping: number)
	self.stiffness = stiffness
	self.damping = damping
end

function VectorImpl:Reset(value: Vector3)
	self.value = value
	self.target = value
	self.velocity = Vector3.zero
end

function VectorImpl:Update(deltaTime: number): Vector3
	local remaining = math.min(deltaTime, 0.25)
	while remaining > 0 do
		local step = math.min(remaining, MAX_STEP)
		remaining -= step
		local displacement = self.value - self.target
		self.velocity -= (displacement * self.stiffness + self.velocity * self.damping) * step
		self.value += self.velocity * step
	end
	return self.value
end

function Spring.number(stiffness: number, damping: number, initial: number?): NumberSpring
	local spring = setmetatable({
		value = initial or 0,
		velocity = 0,
		target = initial or 0,
		stiffness = stiffness,
		damping = damping,
	}, NumberImpl)
	return (spring :: any) :: NumberSpring
end

function Spring.vector(stiffness: number, damping: number, initial: Vector3?): VectorSpring
	local start = initial or Vector3.zero
	local spring = setmetatable({
		value = start,
		velocity = Vector3.zero,
		target = start,
		stiffness = stiffness,
		damping = damping,
	}, VectorImpl)
	return (spring :: any) :: VectorSpring
end

function Spring.criticalDamping(stiffness: number): number
	return 2 * math.sqrt(stiffness)
end

return Spring
