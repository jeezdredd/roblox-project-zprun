--!strict

export type ProductConfig = {
	id: string,
	productId: number,
	displayName: string,
	description: string,
	robuxPrice: number,
}

export type PassConfig = {
	id: string,
	passId: number,
	displayName: string,
	description: string,
	cosmeticOnly: boolean,
}

local ProductsConfig = {}

ProductsConfig.products = {
	Continue = {
		id = "Continue",
		productId = 0,
		displayName = "Continue",
		description = "Get back up where you fell. Once per run.",
		robuxPrice = 49,
	},
} :: { [string]: ProductConfig }

ProductsConfig.passes = {
	VIP = {
		id = "VIP",
		passId = 0,
		displayName = "VIP",
		description = "Exclusive skin set and hangar nameplate. Cosmetic only.",
		cosmeticOnly = true,
	},
	Supporter = {
		id = "Supporter",
		passId = 0,
		displayName = "Supporter Pack",
		description = "Supporter badge and cosmetic weapon charms. Cosmetic only.",
		cosmeticOnly = true,
	},
} :: { [string]: PassConfig }

function ProductsConfig.getProduct(id: string): ProductConfig?
	return ProductsConfig.products[id]
end

function ProductsConfig.productById(productId: number): ProductConfig?
	for _, config in ProductsConfig.products do
		if config.productId == productId and productId > 0 then
			return config
		end
	end
	return nil
end

function ProductsConfig.getPass(id: string): PassConfig?
	return ProductsConfig.passes[id]
end

function ProductsConfig.isConfigured(id: string): boolean
	local product = ProductsConfig.products[id]
	if product then
		return product.productId > 0
	end
	local pass = ProductsConfig.passes[id]
	return pass ~= nil and pass.passId > 0
end

return table.freeze(ProductsConfig)
