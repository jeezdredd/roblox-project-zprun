--!strict

export type VendorConfig = {
	id: string,
	displayName: string,
	subtitle: string,
	offset: Vector3,
	rotationY: number,
	size: Vector3,
	wallColor: Color3,
	color: Color3,
}

local VendorsConfig = {}

VendorsConfig.order = { "Medbay", "SodaMachine", "WeaponDealer", "Gunsmith", "BubblegumMachine" }

VendorsConfig.vendors = {
	Medbay = {
		id = "Medbay",
		displayName = "Medbay",
		subtitle = "Heal soldiers — SOON",
		offset = Vector3.new(-152, 0, -52),
		rotationY = -math.pi / 2,
		size = Vector3.new(56, 18, 44),
		wallColor = Color3.fromRGB(206, 210, 214),
		color = Color3.fromRGB(220, 60, 60),
	},
	SodaMachine = {
		id = "SodaMachine",
		displayName = "Canteen",
		subtitle = "Random run buff — SOON",
		offset = Vector3.new(-152, 0, 56),
		rotationY = -math.pi / 2,
		size = Vector3.new(56, 18, 44),
		wallColor = Color3.fromRGB(72, 76, 84),
		color = Color3.fromRGB(200, 60, 60),
	},
	WeaponDealer = {
		id = "WeaponDealer",
		displayName = "Armory",
		subtitle = "Buy weapons — SOON",
		offset = Vector3.new(152, 0, -52),
		rotationY = math.pi / 2,
		size = Vector3.new(56, 18, 44),
		wallColor = Color3.fromRGB(96, 92, 74),
		color = Color3.fromRGB(150, 128, 70),
	},
	Gunsmith = {
		id = "Gunsmith",
		displayName = "Gunsmith",
		subtitle = "Upgrade weapons — SOON",
		offset = Vector3.new(152, 0, 62),
		rotationY = math.pi / 2,
		size = Vector3.new(56, 18, 44),
		wallColor = Color3.fromRGB(92, 88, 72),
		color = Color3.fromRGB(158, 116, 56),
	},
	BubblegumMachine = {
		id = "BubblegumMachine",
		displayName = "Bubblegum Stand",
		subtitle = "Random weapon buff — SOON",
		offset = Vector3.new(0, 0, 132),
		rotationY = 0,
		size = Vector3.new(52, 18, 40),
		wallColor = Color3.fromRGB(80, 70, 84),
		color = Color3.fromRGB(210, 120, 190),
	},
} :: { [string]: VendorConfig }

function VendorsConfig.get(id: string): VendorConfig?
	return VendorsConfig.vendors[id]
end

return VendorsConfig
