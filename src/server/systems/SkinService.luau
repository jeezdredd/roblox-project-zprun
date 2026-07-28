--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinsConfig = require(ReplicatedStorage.Shared.config.SkinsConfig)

local SkinService = {}

local owned: { [Player]: { [string]: boolean } } = {}
local equipped: { [Player]: string } = {}

local function buildDescription(skin: SkinsConfig.SkinConfig): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = skin.headColor
	description.TorsoColor = skin.torsoColor
	description.LeftArmColor = skin.armColor
	description.RightArmColor = skin.armColor
	description.LeftLegColor = skin.legColor
	description.RightLegColor = skin.legColor
	description.Shirt = 0
	description.Pants = 0
	description.GraphicTShirt = 0
	description.Face = 0
	description.Head = 0
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0
	description.HatAccessory = ""
	description.HairAccessory = ""
	description.FaceAccessory = ""
	description.NeckAccessory = ""
	description.ShouldersAccessory = ""
	description.FrontAccessory = ""
	description.BackAccessory = ""
	description.WaistAccessory = ""
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	return description
end

local function getSkin(player: Player): SkinsConfig.SkinConfig
	local id = equipped[player] or SkinsConfig.DEFAULT_ID
	local skin = SkinsConfig.get(id)
	if not skin then
		return SkinsConfig.get(SkinsConfig.DEFAULT_ID) :: SkinsConfig.SkinConfig
	end
	return skin
end

local function applyToCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local ok, err = pcall(function()
		humanoid:ApplyDescription(buildDescription(getSkin(player)))
	end)
	if not ok then
		warn(`[TaskForceZ] Failed to apply skin for {player.Name}: {err}`)
	end
end

local function onPlayerAdded(player: Player)
	local ownedSet: { [string]: boolean } = {}
	for _, id in SkinsConfig.order do
		local skin = SkinsConfig.get(id)
		if skin and skin.defaultOwned then
			ownedSet[id] = true
		end
	end
	owned[player] = ownedSet
	equipped[player] = SkinsConfig.DEFAULT_ID

	player.CharacterAppearanceLoaded:Connect(function(character)
		applyToCharacter(player, character)
	end)
	player.CharacterAdded:Connect(function(character)
		applyToCharacter(player, character)
	end)
	if player.Character then
		applyToCharacter(player, player.Character)
	end
end

function SkinService.getOwned(player: Player): { string }
	local result: { string } = {}
	local ownedSet = owned[player]
	if not ownedSet then
		return result
	end
	for _, id in SkinsConfig.order do
		if ownedSet[id] then
			table.insert(result, id)
		end
	end
	return result
end

function SkinService.isOwned(player: Player, skinId: string): boolean
	local ownedSet = owned[player]
	return ownedSet ~= nil and ownedSet[skinId] == true
end

function SkinService.grant(player: Player, skinId: string): boolean
	if not SkinsConfig.isValid(skinId) then
		return false
	end
	local ownedSet = owned[player]
	if not ownedSet then
		return false
	end
	ownedSet[skinId] = true
	return true
end

function SkinService.equip(player: Player, skinId: string): boolean
	if not SkinsConfig.isValid(skinId) or not SkinService.isOwned(player, skinId) then
		return false
	end
	equipped[player] = skinId
	local character = player.Character
	if character then
		applyToCharacter(player, character)
	end
	return true
end

function SkinService.getEquipped(player: Player): string
	return equipped[player] or SkinsConfig.DEFAULT_ID
end

function SkinService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		equipped[player] = nil
	end)
end

return SkinService
