--!strict

-- Hit and kill markers (docs/gameplay/hit-markers.md), after Modern Warfare 2019's hip
-- fire: four short diagonal ticks around the crosshair when the server confirms the
-- local shooter's shot hurt a zombie, tinted for a headshot, larger and red for a kill.
-- Driven only by the server's confirmation in the WeaponHit "Shot" reply (its sixth
-- value), never by the client's prediction, so a marker never shows for a hit the
-- server did not count. One marker at a time, restarted by the next confirmation
-- (HitMarkerMath); the "Hit markers" setting turns them off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local HitMarkerConfig = require(ReplicatedStorage.Shared.config.HitMarkerConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local HitMarkerMath = require(ReplicatedStorage.Shared.util.HitMarkerMath)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local SettingsService = require(script.Parent.Parent.systems.SettingsService)
local SfxPlayer = require(script.Parent.Parent.systems.SfxPlayer)

local HitMarkers = {}

local player = Players.LocalPlayer

-- the four ticks: their direction from the centre and their rotation
local CORNERS = {
	{ -1, -1, 45 },
	{ 1, -1, -45 },
	{ -1, 1, -45 },
	{ 1, 1, 45 },
}

local screen: ScreenGui
local holder: Frame
local ticks: { Frame } = {}
local state: HitMarkerMath.State = HitMarkerMath.idle()
local enabled = true

local function color(spec: { number }): Color3
	return Color3.fromRGB(spec[1], spec[2], spec[3])
end

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "HitMarkers"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 12
	screen.Parent = player:WaitForChild("PlayerGui")

	holder = Instance.new("Frame")
	holder.Name = "Marker"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = screen

	for index, corner in CORNERS do
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. index
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BorderSizePixel = 0
		tick.Rotation = corner[3]
		tick.Parent = holder
		ticks[index] = tick
	end
end

-- The crosshair the weapon HUD draws (it moves with hip aim); the screen's centre when
-- it is not there.
local function crosshairCentre(): UDim2
	local hud = player:FindFirstChild("PlayerGui") and (player.PlayerGui :: PlayerGui):FindFirstChild("WeaponHud")
	local crosshair = hud and hud:FindFirstChild("Crosshair")
	if crosshair and crosshair:IsA("GuiObject") then
		local centre = crosshair.AbsolutePosition + crosshair.AbsoluteSize / 2
		return UDim2.fromOffset(centre.X, centre.Y)
	end
	return UDim2.fromScale(0.5, 0.5)
end

local function draw()
	local frame = HitMarkerMath.frame(HitMarkerConfig, state, os.clock())
	if not frame.visible or not frame.variant then
		holder.Visible = false
		return
	end
	holder.Visible = true
	holder.Position = crosshairCentre()
	local tint = color(HitMarkerConfig.colors[frame.variant])
	local gap = HitMarkerConfig.GAP * frame.scale
	local diagonal = gap / math.sqrt(2)
	for index, corner in CORNERS do
		local tick = ticks[index]
		tick.Size = UDim2.fromOffset(HitMarkerConfig.TICK_LENGTH * frame.scale, HitMarkerConfig.TICK_THICKNESS)
		tick.Position = UDim2.fromOffset(corner[1] * diagonal, corner[2] * diagonal)
		tick.BackgroundColor3 = tint
		tick.BackgroundTransparency = 1 - frame.alpha
	end
end

local function playSound(key: string)
	local ids = AssetIds.audio.ui :: { [string]: number }
	local id = ids[key]
	if typeof(id) ~= "number" or id <= 0 then
		return
	end
	if AudioEngine.enabled() then
		AudioEngine.play({ id = id, class = "UI", volume = HitMarkerConfig.SOUND_VOLUME })
		return
	end
	SfxPlayer.play2D(id, HitMarkerConfig.SOUND_VOLUME)
end

-- The server's confirmation for one of the local player's shots.
local function onConfirm(raw: any)
	if not enabled or typeof(raw) ~= "table" then
		return
	end
	if typeof(raw.damage) ~= "number" then
		return
	end
	local confirm: HitMarkerMath.Confirm = {
		damage = raw.damage,
		headshot = raw.headshot == true,
		killed = raw.killed == true,
	}
	local before = state
	state = HitMarkerMath.start(HitMarkerConfig, state, os.clock(), confirm)
	if state ~= before then
		playSound(if state.variant == "Kill" then HitMarkerConfig.SOUND_KILL else HitMarkerConfig.SOUND_HIT)
	end
end

function HitMarkers.init()
	build()
	SettingsService.observe(HitMarkerConfig.SETTING_KEY, function(value)
		enabled = value ~= false
		if not enabled then
			state = HitMarkerMath.idle()
			holder.Visible = false
		end
	end)
	-- the same reply WeaponController draws other players' shots from; only the local
	-- shooter's own shots carry a confirmation for this player
	Remotes.getEvent(Remotes.Event.WeaponHit).OnClientEvent:Connect(function(kind, _origin, _hits, shooter, _weaponId, confirm)
		if kind == "Shot" and shooter == player then
			onConfirm(confirm)
		end
	end)
	RunService.RenderStepped:Connect(draw)
end

return HitMarkers
