--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local MissionState = require(script.Parent.MissionState)
local MissionService = require(script.Parent.MissionService)
local ProfileManager = require(script.Parent.ProfileManager)
local WeaponService = require(script.Parent.WeaponService)

-- Iteration harness. Everything here is gated on RunService:IsStudio(), so none of it
-- can reach a published server. Its whole purpose is to make one weapon change cost a
-- single Play click instead of a scripted walk to the helicopter and a squad launch.

local DevBench = {}

local TARGET_TAG = "DevBenchTarget"
local PHASE_ATTRIBUTE = "FlowPhase"

local launching: { [Player]: boolean } = {}
local targetFolder: Folder? = nil

local function benchConfig()
	return {
		mapId = MapsConfig.DEFAULT_ID,
		difficultyId = GameConstants.DEFAULT_DIFFICULTY,
		privacy = "Solo" :: "Solo",
		modifierIds = {},
	}
end

local function launchSolo(player: Player)
	if launching[player] or MissionState.isActive() then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	launching[player] = true
	MissionService.startSquad({ player }, benchConfig(), DevConfig.QUICK_RUN.seed or Random.new():NextInteger(1, 2147483646))
	task.delay(2, function()
		launching[player] = nil
	end)
end

local function watchPlayer(player: Player)
	local quick = DevConfig.QUICK_RUN
	if not quick.enabled then
		return
	end

	local function onCharacter()
		task.delay(quick.delay, function()
			if player.Parent and player:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission" then
				launchSolo(player)
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter()
	end

	if quick.relaunchAfterDeath then
		player:GetAttributeChangedSignal(PHASE_ATTRIBUTE):Connect(function()
			if player:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission" then
				task.delay(quick.relaunchDelay, function()
					if player.Parent and player:GetAttribute(PHASE_ATTRIBUTE) ~= "Mission" then
						launchSolo(player)
					end
				end)
			end
		end)
	end
end

-- A dummy is any Model with a Humanoid that is not a player, which is exactly what
-- WeaponService.findZombieModel already accepts, so hit registration and gore both
-- work without the bench knowing anything about them.
local function buildTarget(position: Vector3, label: string): Model
	local settings = DevConfig.TARGET_RANGE
	local model = Instance.new("Model")
	model.Name = "BenchTarget_" .. label

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Position = position + Vector3.new(0, 3, 0)
	root.Anchored = true
	root.Color = Color3.fromRGB(120, 130, 120)
	root.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = root.CFrame
	torso.Anchored = true
	torso.Color = Color3.fromRGB(150, 120, 110)
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = root.CFrame * CFrame.new(0, 1.7, 0)
	head.Anchored = true
	head.Color = Color3.fromRGB(190, 165, 140)
	head.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = settings.health
	humanoid.Health = settings.health
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.Code
	text.TextColor3 = Color3.fromRGB(240, 230, 200)
	text.TextStrokeTransparency = 0.4
	text.Text = label
	text.Parent = billboard

	model.PrimaryPart = root
	CollectionService:AddTag(model, TARGET_TAG)
	return model
end

local function respawnTarget(position: Vector3, label: string, parent: Folder)
	local model = buildTarget(position, label)
	model.Parent = parent
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		task.delay(DevConfig.TARGET_RANGE.respawnDelay, function()
			model:Destroy()
			if parent.Parent then
				respawnTarget(position, label, parent)
			end
		end)
	end)
end

function DevBench.buildTargetRange(origin: Vector3)
	local settings = DevConfig.TARGET_RANGE
	if not settings.enabled then
		return
	end
	local existing = targetFolder
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevBenchTargets"
	folder.Parent = workspace
	targetFolder = folder

	local plate = Instance.new("Part")
	plate.Name = "BenchFloor"
	plate.Anchored = true
	plate.Size = Vector3.new(60, 1, settings.distances[#settings.distances] + 40)
	plate.Position = origin + Vector3.new(0, -0.5, -plate.Size.Z / 2 + 10)
	plate.Color = Color3.fromRGB(70, 68, 62)
	plate.Material = Enum.Material.Concrete
	plate.Parent = folder

	for index, distance in settings.distances do
		local offsetX = (index - (#settings.distances + 1) / 2) * settings.spacing
		local position = origin + Vector3.new(offsetX, 0, -distance)
		respawnTarget(position, tostring(distance) .. "m", folder)
	end
end

function DevBench.clearTargetRange()
	local folder = targetFolder
	if folder then
		folder:Destroy()
		targetFolder = nil
	end
end

-- Server-side command surface. The Studio command bar runs in a separate Lua VM from
-- the game scripts, so module state is not shared and calling DevBench directly from
-- there does nothing useful; a BindableEvent is the one channel that does reach us.
local function installCommands()
	local existing = ReplicatedStorage:FindFirstChild("DevBench")
	if existing then
		existing:Destroy()
	end
	local bindable = Instance.new("BindableEvent")
	bindable.Name = "DevBench"
	bindable.Parent = ReplicatedStorage

	bindable.Event:Connect(function(command: string, argument: any)
		local player = Players:GetPlayers()[1]
		if not player then
			return
		end
		if command == "launch" then
			launchSolo(player)
		elseif command == "targets" then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				DevBench.buildTargetRange(root.Position)
			end
		elseif command == "cleartargets" then
			DevBench.clearTargetRange()
		elseif command == "ammo" then
			WeaponService.refillAmmo(player)
		elseif command == "weapon" and typeof(argument) == "string" then
			-- WeaponService refuses to equip a weapon the profile does not own, so the
			-- bench grants it first rather than putting a bypass into the live path.
			local data = ProfileManager.get(player)
			if data and not data.WeaponsOwned[argument] then
				data.WeaponsOwned[argument] = { level = 1, xp = 0 }
			end
			WeaponService.equip(player, argument)
		elseif command == "state" then
			print(string.format(
				"[DevBench] phase=%s weapon=%s missionActive=%s",
				tostring(player:GetAttribute(PHASE_ATTRIBUTE)),
				tostring(player:GetAttribute("WeaponId")),
				tostring(MissionState.isActive())
			))
		end
	end)
end

function DevBench.init()
	if not RunService:IsStudio() then
		return
	end

	installCommands()

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return DevBench
