--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)

export type WeaponProgress = {
	level: number,
	xp: number,
}

export type ProfileData = {
	Version: number,
	Credits: number,
	XP: number,
	WeaponsOwned: { [string]: WeaponProgress },
	SkillLevels: { [string]: number },
	SkinsOwned: { [string]: boolean },
	EquippedSkin: string,
	PurchaseHistory: { [string]: boolean },
	Loadout: { string },
	Settings: { [string]: any },
	StatsLifetime: {
		Distance: number,
		Kills: number,
		Runs: number,
	},
}

local TEMPLATE: ProfileData = {
	Version = 2,
	Credits = 0,
	XP = 0,
	WeaponsOwned = {
		Pistol = { level = 1, xp = 0 },
	},
	SkillLevels = {},
	SkinsOwned = { Recruit = true },
	EquippedSkin = "Recruit",
	PurchaseHistory = {},
	Loadout = { "Pistol" },
	Settings = {},
	StatsLifetime = {
		Distance = 0,
		Kills = 0,
		Runs = 0,
	},
}

local ProfileManager = {}

type Profile = typeof(ProfileStore.New("", TEMPLATE):StartSessionAsync(""))

local store = ProfileStore.New("PlayerData", TEMPLATE)
local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, ProfileData) -> () } = {}
local started = false

local function dataStoresAvailable(): boolean
	if not RunService:IsStudio() then
		return true
	end
	local ok = pcall(function()
		DataStoreService:GetDataStore("__tfz_probe"):GetAsync("probe")
	end)
	return ok
end

local useMock = not dataStoresAvailable()

local function migrate(data: ProfileData)
	if data.Version < 1 then
		data.Version = 1
	end
	if data.Version < 2 then
		if #data.Loadout == 0 then
			data.Loadout = { "Pistol" }
		end
		data.Version = 2
	end
end

local function syncAttributes(player: Player, data: ProfileData)
	player:SetAttribute("Credits", data.Credits)
	player:SetAttribute("XP", data.XP)
end

local function onPlayerAdded(player: Player)
	local activeStore = if useMock then store.Mock else store
	local profile = activeStore:StartSessionAsync("Player_" .. tostring(player.UserId), {
		Cancel = function()
			return player.Parent == nil
		end,
	})

	if not profile then
		player:Kick("Profile load failed. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent then
			player:Kick("Profile session ended. Please rejoin.")
		end
	end)

	if player.Parent then
		profiles[player] = profile
		syncAttributes(player, profile.Data)
		for _, callback in loadedCallbacks do
			task.spawn(callback, player, profile.Data)
		end
	else
		profile:EndSession()
	end
end

function ProfileManager.get(player: Player): ProfileData?
	local profile = profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

function ProfileManager.waitFor(player: Player, timeout: number?): ProfileData?
	local deadline = os.clock() + (timeout or 10)
	while os.clock() < deadline do
		local data = ProfileManager.get(player)
		if data then
			return data
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

function ProfileManager.onLoaded(callback: (Player, ProfileData) -> ()): () -> ()
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
	return function()
		local index = table.find(loadedCallbacks, callback)
		if index then
			table.remove(loadedCallbacks, index)
		end
	end
end

function ProfileManager.awardRun(player: Player, credits: number, xp: number, distance: number)
	local data = ProfileManager.get(player)
	if not data then
		return
	end
	data.Credits += math.max(0, math.floor(credits))
	data.XP += math.max(0, math.floor(xp))
	data.StatsLifetime.Distance += math.max(0, math.floor(distance))
	data.StatsLifetime.Runs += 1
	syncAttributes(player, data)
end

function ProfileManager.addKill(player: Player, count: number?)
	local data = ProfileManager.get(player)
	if not data then
		return
	end
	data.StatsLifetime.Kills += count or 1
end

function ProfileManager.spendCredits(player: Player, amount: number): boolean
	local data = ProfileManager.get(player)
	if not data or amount < 0 or data.Credits < amount then
		return false
	end
	data.Credits -= amount
	syncAttributes(player, data)
	return true
end

function ProfileManager.addCredits(player: Player, amount: number)
	local data = ProfileManager.get(player)
	if not data then
		return
	end
	data.Credits += math.max(0, math.floor(amount))
	syncAttributes(player, data)
end

function ProfileManager.isUsingMock(): boolean
	return useMock
end

function ProfileManager.init()
	if started then
		return
	end
	started = true

	if useMock then
		warn("[TaskForceZ] DataStores unavailable, using mock profiles (Studio without API access)")
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profile:EndSession()
		end
	end)

	game:BindToClose(function()
		for _, profile in profiles do
			profile:EndSession()
		end
	end)
end

return ProfileManager
