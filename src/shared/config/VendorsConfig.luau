--!strict

export type VendorConfig = {
	id: string,
	displayName: string,
	subtitle: string,
	offset: Vector3,
	color: Color3,
	material: Enum.Material,
}

local VendorsConfig = {}

VendorsConfig.order = { "SodaMachine", "BubblegumMachine", "WeaponDealer", "Gunsmith", "Medbay" }

VendorsConfig.vendors = {
	SodaMachine = {
		id = "SodaMachine",
		displayName = "Soda Machine",
		subtitle = "Random run buff — SOON",
		offset = Vector3.new(-70, 0, 70),
		color = Color3.fromRGB(200, 60, 60),
		material = Enum.Material.SmoothPlastic,
	},
	BubblegumMachine = {
		id = "BubblegumMachine",
		displayName = "Bubblegum",
		subtitle = "Random weapon buff — SOON",
		offset = Vector3.new(-35, 0, 70),
		color = Color3.fromRGB(210, 120, 190),
		material = Enum.Material.SmoothPlastic,
	},
	WeaponDealer = {
		id = "WeaponDealer",
		displayName = "Weapon Dealer",
		subtitle = "Buy weapons — SOON",
		offset = Vector3.new(0, 0, 72),
		color = Color3.fromRGB(90, 90, 96),
		material = Enum.Material.Metal,
	},
	Gunsmith = {
		id = "Gunsmith",
		displayName = "Gunsmith",
		subtitle = "Upgrade weapons — SOON",
		offset = Vector3.new(35, 0, 70),
		color = Color3.fromRGB(120, 100, 70),
		material = Enum.Material.WoodPlanks,
	},
	Medbay = {
		id = "Medbay",
		displayName = "Medbay",
		subtitle = "Heal soldiers — SOON",
		offset = Vector3.new(70, 0, 70),
		color = Color3.fromRGB(230, 230, 235),
		material = Enum.Material.SmoothPlastic,
	},
} :: { [string]: VendorConfig }

function VendorsConfig.get(id: string): VendorConfig?
	return VendorsConfig.vendors[id]
end

return VendorsConfig
