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
		studsPerTile = 6,
	},
	{
		name = "TFZ_Sand",
		baseMaterial = Enum.Material.Sand,
		color = TexturesConfig.SAND,
		normal = TexturesConfig.SAND_NORMAL,
		roughness = TexturesConfig.SAND_ROUGHNESS,
		studsPerTile = 8,
	},
} :: { PbrSet }

local registered: { [string]: boolean } = {}

-- MaterialVariant.BaseMaterial is a plugin-capability property, so a runtime script
-- cannot build these. They ship as instances declared under MaterialService in
-- default.project.json; this pass only records which ones actually arrived.
function MaterialUtil.register()
	if not MaterialUtil.ENABLED then
		return
	end
	for _, set in MaterialUtil.sets do
		if registered[set.name] then
			continue
		end
		local existing = MaterialService:FindFirstChild(set.name)
		if existing and existing:IsA("MaterialVariant") then
			registered[set.name] = true
		else
			warn(`[TaskForceZ] MaterialVariant "{set.name}" missing from MaterialService, falling back to flat textures`)
		end
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
