--!strict

-- Damage numbers (docs/gameplay/hit-markers.md): the damage the server confirmed for the
-- local shooter's shot rises from the hit point and fades over DamageNumberConfig.DURATION.
-- Fed by HitMarkers from the same WeaponHit "Shot" reply as the markers (its hits and
-- sixth value), placed at the first flesh hit: one number per shot, a shotgun's pellets
-- summed. A fixed pool of BillboardGuis on invisible, non-queryable anchors in
-- Workspace.DamageNumbers, the oldest reused when all are showing. Headshots take the
-- theme accent, kills the largest size; the "Damage numbers" setting turns them off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DamageNumberConfig = require(ReplicatedStorage.Shared.config.DamageNumberConfig)
local SettingsService = require(script.Parent.Parent.systems.SettingsService)
local UiTheme = require(script.Parent.UiTheme)

local DamageNumbers = {}

type Entry = {
	gui: BillboardGui,
	anchor: Part,
	label: TextLabel,
	active: boolean,
	startedAt: number,
	origin: Vector3,
	size: number,
}

local pool: { Entry } = {}
local folder: Folder
local enabled = true
local rng = Random.new()

local function build()
	folder = Instance.new("Folder")
	folder.Name = "DamageNumbers"
	folder.Parent = Workspace
	for index = 1, DamageNumberConfig.POOL_SIZE do
		local anchor = Instance.new("Part")
		anchor.Name = "Anchor" .. index
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.Parent = folder

		local gui = Instance.new("BillboardGui")
		gui.Name = "Number" .. index
		gui.Adornee = anchor
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.MaxDistance = DamageNumberConfig.MAX_DISTANCE
		gui.Size = UDim2.fromOffset(DamageNumberConfig.GUI_SIZE[1], DamageNumberConfig.GUI_SIZE[2])
		gui.Enabled = false
		gui.Parent = anchor

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui
		UiTheme.styleText(label)
		label.TextStrokeTransparency = 0.4

		pool[index] = {
			gui = gui,
			anchor = anchor,
			label = label,
			active = false,
			startedAt = 0,
			origin = Vector3.zero,
			size = 0,
		}
	end
end

local function acquire(): Entry
	local oldest = pool[1]
	for _, entry in pool do
		if not entry.active then
			return entry
		end
		if entry.startedAt < oldest.startedAt then
			oldest = entry
		end
	end
	return oldest
end

local function release(entry: Entry)
	entry.active = false
	entry.gui.Enabled = false
end

local function update()
	local now = os.clock()
	for _, entry in pool do
		if not entry.active then
			continue
		end
		local t = (now - entry.startedAt) / DamageNumberConfig.DURATION
		if t >= 1 then
			release(entry)
			continue
		end
		local eased = 1 - (1 - t) * (1 - t)
		entry.anchor.CFrame = CFrame.new(entry.origin + Vector3.new(0, DamageNumberConfig.RISE * eased, 0))
		local fade = math.clamp((t - DamageNumberConfig.FADE_FROM) / (1 - DamageNumberConfig.FADE_FROM), 0, 1)
		entry.label.TextTransparency = fade
		entry.label.TextStrokeTransparency = 0.4 + 0.6 * fade
	end
end

function DamageNumbers.show(position: Vector3, damage: number, headshot: boolean, killed: boolean)
	if not enabled then
		return
	end
	local variant = if killed then "Kill" elseif headshot then "Headshot" else "Hit"
	local entry = acquire()
	local jitter = DamageNumberConfig.JITTER
	entry.active = true
	entry.startedAt = os.clock()
	entry.origin = position + Vector3.new(rng:NextNumber(-jitter, jitter), 0, rng:NextNumber(-jitter, jitter))
	entry.anchor.CFrame = CFrame.new(entry.origin)
	entry.label.Text = tostring(math.max(1, math.round(damage)))
	entry.label.TextSize = DamageNumberConfig.TEXT_SIZE[variant]
	entry.label.TextColor3 = if headshot then UiTheme.ACCENT else UiTheme.TEXT
	entry.label.TextTransparency = 0
	entry.label.TextStrokeTransparency = 0.4
	entry.gui.Enabled = true
end

function DamageNumbers.init()
	build()
	SettingsService.observe(DamageNumberConfig.SETTING_KEY, function(value)
		enabled = value ~= false
		if not enabled then
			for _, entry in pool do
				release(entry)
			end
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return DamageNumbers
