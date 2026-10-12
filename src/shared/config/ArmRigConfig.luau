--!strict

export type Side = {
	handCentre: Vector3,
	handSize: Vector3,
	wrist: CFrame,
	forearmCentre: Vector3,
	forearmSize: Vector3,
}

local ArmRigConfig = {}

ArmRigConfig.ready = true

ArmRigConfig.R = {
	handCentre = Vector3.new(-0.0344, 0.1164, -0.0745),
	handSize = Vector3.new(0.5115, 0.4493, 0.8807),
	wrist = CFrame.new(-0.0116, 0.1339, 0.2423, 0.9408, -0.0187, 0.33845, 0.03037, 0.99911, -0.02924, -0.33761, 0.03779, 0.94053),
	forearmCentre = Vector3.new(0.0886, 0.0828, 0.8812),
	forearmSize = Vector3.new(0.9432, 0.6559, 1.912),
} :: Side

ArmRigConfig.L = {
	handCentre = Vector3.new(0.0369, 0.12, -0.012),
	handSize = Vector3.new(0.5195, 0.5406, 0.7537),
	wrist = CFrame.new(0.019, 0.1822, 0.2426, 0.958, 0.01054, -0.28657, -0.0284, 0.9979, -0.05822, 0.28535, 0.06391, 0.95629),
	forearmCentre = Vector3.new(-0.095, 0.0822, 0.8819),
	forearmSize = Vector3.new(0.9475, 0.654, 1.9102),
} :: Side

return ArmRigConfig
