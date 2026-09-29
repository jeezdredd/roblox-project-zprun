--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local WorldWeaponModel = require(ReplicatedStorage.Shared.util.WorldWeaponModel)

local WorldWeapon = {}

function WorldWeapon.apply(player: Player, weaponId: string)
	local character = player.Character
	if not character then
		return
	end
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	WorldWeaponModel.build(character, config)
end

function WorldWeapon.init()
	local function watch(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			local weaponId = player:GetAttribute("WeaponId")
			if typeof(weaponId) == "string" then
				task.defer(WorldWeapon.apply, player, weaponId)
			end
		end)
		player:GetAttributeChangedSignal("WeaponId"):Connect(function()
			local weaponId = player:GetAttribute("WeaponId")
			if typeof(weaponId) == "string" then
				WorldWeapon.apply(player, weaponId)
			end
		end)
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return WorldWeapon
