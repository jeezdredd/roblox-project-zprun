--!strict

-- Makes the soldier the character every player spawns as. Once the soldier meshes have
-- loaded, a fresh R15 model is converted by SoldierBody and parented to StarterPlayer as
-- StarterCharacter; players who spawned on the block body before that (the first seconds
-- after the server starts) are respawned unless they are in a run. While the mesh ids
-- are not filled in (SoldierRigConfig.ready is false) nothing happens and everyone keeps
-- the block body.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local SoldierBody = require(ReplicatedStorage.Shared.util.SoldierBody)
local MissionState = require(script.Parent.MissionState)

local SoldierCharacter = {}

local LOAD_TIMEOUT = 30

local ready = false

-- A character that spawned on the block body while the soldier was still loading (its
-- CharacterAdded can land after the build's own sweep) is respawned once the
-- StarterCharacter exists; a run is never interrupted for it.
local function respawnIfBlock(player: Player, character: Model)
	if not ready or character:GetAttribute(SoldierBody.ATTRIBUTE) or MissionState.isParticipant(player) then
		return
	end
	task.defer(function()
		if player.Parent and player.Character == character then
			player:LoadCharacter()
		end
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		respawnIfBlock(player, character)
	end)
end

local function build()
	if not SoldierBody.load(LOAD_TIMEOUT) then
		warn("[TaskForceZ] soldier meshes did not load, players keep the block body")
		return
	end
	local model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	-- the engine adds the default Animate to every character; a second copy would fight it
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	if not SoldierBody.apply(model) then
		warn("[TaskForceZ] soldier body could not be applied, players keep the block body")
		model:Destroy()
		return
	end
	local existing = StarterPlayer:FindFirstChild("StarterCharacter")
	if existing then
		existing:Destroy()
	end
	model.Name = "StarterCharacter"
	model.Parent = StarterPlayer

	ready = true
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			respawnIfBlock(player, character)
		end
	end
end

function SoldierCharacter.init()
	if not SoldierBody.available() then
		return
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	task.spawn(build)
end

return SoldierCharacter
