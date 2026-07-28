--!strict

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TexturesConfig = require(ReplicatedStorage.Shared.config.TexturesConfig)

export type PbrSet = {
	name: string,
	baseMaterial: Enum.Material,
	color: number,
	normal: number,
	roughness: number,
	studsPerTile: number,
}

local MaterialUtil = {}

MaterialUtil.ENABLED = true

MaterialUtil.sets = {
	{
		name = "TFZ_Asphalt",
		baseMaterial = Enum.Material.Asphalt,
		color = TexturesConfig.ASPHALT,
		normal = TexturesConfig.ASPHALT_NORMAL,
		roughness = TexturesConfig.ASPHALT_ROUGHNESS,
		studsPerTile = 12,
	},
	{
		name = "TFZ_Concrete",
		baseMaterial = Enum.Material.Concrete,
		color = TexturesConfig.CONCRETE,
		normal = TexturesConfig.CONCRETE_NORMAL,
		roughness = TexturesConfig.CONCRETE_ROUGHNESS,
		studsPerTile = 14,
	},
} :: { PbrSet }

local registered: { [string]: boolean } = {}

local function assetUrl(id: number): string
	return "rbxassetid://" .. tostring(id)
end

function MaterialUtil.register()
	if not MaterialUtil.ENABLED then
		return
	end
	for _, set in MaterialUtil.sets do
		if registered[set.name] or set.color <= 0 or set.normal <= 0 or set.roughness <= 0 then
			continue
		end
		if MaterialService:FindFirstChild(set.name) then
			registered[set.name] = true
			continue
		end
		local variant = Instance.new("MaterialVariant")
		variant.Name = set.name
		variant.BaseMaterial = set.baseMaterial
		variant.ColorMap = assetUrl(set.color)
		variant.NormalMap = assetUrl(set.normal)
		variant.RoughnessMap = assetUrl(set.roughness)
		variant.StudsPerTile = set.studsPerTile
		variant.Parent = MaterialService
		registered[set.name] = true
	end
end

function MaterialUtil.apply(part: BasePart, setName: string): boolean
	if not MaterialUtil.ENABLED or not registered[setName] then
		return false
	end
	for _, set in MaterialUtil.sets do
		if set.name == setName then
			part.Material = set.baseMaterial
			part.MaterialVariant = setName
			return true
		end
	end
	return false
end

return MaterialUtil
