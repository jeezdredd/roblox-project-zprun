--!strict

local ZombieRig = {}

ZombieRig.TORSO_NAME = "UpperTorso"
ZombieRig.LOWER_TORSO_NAME = "LowerTorso"
ZombieRig.HEAD_NAME = "Head"
ZombieRig.HITBOX_NAME = "Hitbox"

function ZombieRig.torso(model: Model): BasePart?
	local part = model:FindFirstChild(ZombieRig.TORSO_NAME) or model:FindFirstChild("Body")
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

function ZombieRig.waitForTorso(model: Model, timeout: number): BasePart?
	local part = model:WaitForChild(ZombieRig.TORSO_NAME, timeout)
	if part and part:IsA("BasePart") then
		return part
	end
	return ZombieRig.torso(model)
end

function ZombieRig.neck(model: Model): Motor6D?
	local torso = ZombieRig.torso(model)
	local motor = if torso then torso:FindFirstChild("Neck") else nil
	if motor and motor:IsA("Motor6D") then
		return motor
	end
	return nil
end

return table.freeze(ZombieRig)
