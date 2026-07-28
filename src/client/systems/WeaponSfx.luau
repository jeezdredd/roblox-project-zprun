--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local SfxPlayer = require(script.Parent.SfxPlayer)
local MusicController = require(script.Parent.MusicController)

local WeaponSfx = {}

local player = Players.LocalPlayer
local weaponGroup: SoundGroup? = nil
local reverb: ReverbSoundEffect? = nil
local acousticZones: { BasePart } = {}
local zonesScanned = false

local function scanZones()
	if zonesScanned then
		return
	end
	zonesScanned = true
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("AcousticSpace") ~= nil then
			table.insert(acousticZones, descendant)
		end
	end
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant:GetAttribute("AcousticSpace") ~= nil then
			table.insert(acousticZones, descendant)
		end
	end)
end

local function isInterior(position: Vector3): boolean
	for index = #acousticZones, 1, -1 do
		local zone = acousticZones[index]
		if not zone.Parent then
			table.remove(acousticZones, index)
		else
			local localPoint = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return zone:GetAttribute("AcousticSpace") == "Interior"
			end
		end
	end
	return false
end

local function ensureGroup(): SoundGroup
	local group = weaponGroup
	if group then
		return group
	end
	local created = Instance.new("SoundGroup")
	created.Name = "Weapons"
	created.Volume = 1
	created.Parent = MusicController.getSfxGroup()

	local reverbEffect = Instance.new("ReverbSoundEffect")
	reverbEffect.DecayTime = 0.4
	reverbEffect.Density = 0.6
	reverbEffect.Diffusion = 0.7
	reverbEffect.WetLevel = -18
	reverbEffect.DryLevel = 0
	reverbEffect.Parent = created

	weaponGroup = created
	reverb = reverbEffect
	return created
end

local function playOneShot(soundId: number, volume: number, pitch: number)
	if soundId <= 0 then
		return
	end
	local group = ensureGroup()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.SoundGroup = group
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	pcall(function()
		sound:Play()
	end)
end

local function updateTail(): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local interior = root ~= nil and root:IsA("BasePart") and isInterior(root.Position)

	local reverbEffect = reverb
	if reverbEffect then
		if interior then
			reverbEffect.DecayTime = 1.5
			reverbEffect.WetLevel = -8
		else
			reverbEffect.DecayTime = 0.4
			reverbEffect.WetLevel = -18
		end
	end
	return interior
end

local function weaponSoundId(key: string): number
	return (AssetIds.audio.weapons :: { [string]: number })[key] or 0
end

local function shotSoundId(config: WeaponsConfig.WeaponConfig): number
	local closeId = weaponSoundId(config.closeSound)
	if closeId > 0 then
		return closeId
	end
	return weaponSoundId(config.shotSound)
end

local TAIL_COOLDOWN = 0.55
local lastTailAt = 0

local function playTail(config: WeaponsConfig.WeaponConfig, interior: boolean)
	local now = os.clock()
	if now - lastTailAt < TAIL_COOLDOWN then
		return
	end
	lastTailAt = now
	local tailId = weaponSoundId(if interior then "tail_interior" else "tail_open")
	if tailId <= 0 then
		return
	end
	playOneShot(tailId, config.shotVolume * (if interior then 0.34 else 0.46), 1 + (math.random() - 0.5) * 0.06)
end

function WeaponSfx.playShot(weaponId: string)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	scanZones()
	local interior = updateTail()

	local jitter = 1 + (math.random() - 0.5) * 0.06
	playOneShot(shotSoundId(config), config.shotVolume, config.shotPitch * jitter)
	playTail(config, interior)

	task.delay(0.25 + math.random() * 0.3, function()
		local shellId = SfxPlayer.pick({ AssetIds.audio.weapons.shell_01, AssetIds.audio.weapons.shell_02 })
		playOneShot(shellId, 0.16, 1 + (math.random() - 0.5) * 0.2)
	end)
end

function WeaponSfx.playDryfire()
	playOneShot(AssetIds.audio.weapons.dryfire, 0.45, 1 + (math.random() - 0.5) * 0.08)
end

function WeaponSfx.playReload(reloadTime: number)
	playOneShot(AssetIds.audio.weapons.mag_out, 0.5, 1)
	task.delay(reloadTime * 0.55, function()
		playOneShot(AssetIds.audio.weapons.mag_in, 0.5, 1)
	end)
	task.delay(math.max(reloadTime - 0.3, 0.2), function()
		playOneShot(AssetIds.audio.weapons.bolt, 0.5, 1)
	end)
end

function WeaponSfx.playDistantShot(position: Vector3, weaponId: string)
	local config = WeaponsConfig.get(weaponId)
	if not config then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = Workspace
	SfxPlayer.play3D(anchor, shotSoundId(config), config.shotVolume * 0.8, 30, 400, 0.06)
	task.delay(4, function()
		anchor:Destroy()
	end)
end

function WeaponSfx.playGong(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = Workspace
	SfxPlayer.play3D(anchor, AssetIds.audio.range.gong, 0.9, 20, 300, 0.04)
	task.delay(5, function()
		anchor:Destroy()
	end)
end

return WeaponSfx
