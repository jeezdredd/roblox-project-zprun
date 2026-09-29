--!strict

-- Debug overlay for the spatial audio engine: profile, listener environment, ray use,
-- pool occupancy, per-bus activity and one row per live voice with its class, bus,
-- distance, start delay, occlusion, filter cutoff and volume. Toggled from the Studio
-- test yard (SandboxInput binds a key to AudioDebug.toggle()).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AudioBus = require(script.Parent.AudioBus)
local AudioEngine = require(script.Parent.AudioEngine)
local AudioEnvironment = require(script.Parent.AudioEnvironment)

local AudioDebug = {}

local REFRESH = 0.1
local MAX_ROWS = 40

local screen: ScreenGui? = nil
local label: TextLabel? = nil
local nextRefresh = 0
local connection: RBXScriptConnection? = nil

local function build(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "AudioDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen = gui

	local text = Instance.new("TextLabel")
	text.Name = "Voices"
	text.AnchorPoint = Vector2.new(1, 0)
	text.Position = UDim2.new(1, -12, 0, 12)
	text.Size = UDim2.new(0, 560, 0, 720)
	text.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	text.BackgroundTransparency = 0.25
	text.BorderSizePixel = 0
	text.Font = Enum.Font.Code
	text.TextSize = 13
	text.TextColor3 = Color3.fromRGB(220, 228, 210)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.RichText = false
	text.Text = ""
	text.Parent = gui
	return text
end

local function render()
	local text = label
	if not text then
		return
	end
	local rows, active, poolSize = AudioEngine.snapshot()
	local activity: { [string]: number } = {}
	for _, row in rows do
		activity[row.bus] = (activity[row.bus] or 0) + math.max(row.volume, 0)
	end
	local lines: { string } = {}
	table.insert(lines, string.format(
		"audio  profile %s  env %s  voices %d/%d  rays %d  occlusion %s",
		AudioEngine.profileName(),
		AudioBus.environment(),
		active,
		poolSize,
		AudioEnvironment.raysUsed(),
		if AudioBus.simulationEnabled() then "engine" else "rays"
	))
	local buses: { string } = {}
	for bus, level in activity do
		table.insert(buses, string.format("%s %.2f", bus, level))
	end
	table.sort(buses)
	table.insert(lines, "bus activity  " .. table.concat(buses, "  "))
	table.insert(lines, "")
	table.insert(lines, string.format("%-18s %-9s %6s %6s %5s %6s %5s", "class", "bus", "dist", "delay", "occl", "cutoff", "vol"))
	table.sort(rows, function(a, b)
		return a.distance < b.distance
	end)
	for index, row in rows do
		if index > MAX_ROWS then
			table.insert(lines, string.format("... %d more", #rows - MAX_ROWS))
			break
		end
		table.insert(lines, string.format(
			"%-18s %-9s %6s %6s %5s %6s %5.2f%s",
			row.class,
			row.bus,
			if row.is3D then string.format("%.0f", row.distance) else "2D",
			if row.delay > 0 then string.format("%.0fms", row.delay * 1000) else "-",
			if row.is3D then string.format("%.2f", row.occlusion) else "-",
			if row.cutoff >= 0 then string.format("%.0f", row.cutoff) else "-",
			math.max(row.volume, 0),
			if row.loop then " loop" else ""
		))
	end
	text.Text = table.concat(lines, "\n")
end

function AudioDebug.isVisible(): boolean
	local gui = screen
	return gui ~= nil and gui.Enabled
end

function AudioDebug.setVisible(visible: boolean)
	if visible and not label then
		label = build()
	end
	local gui = screen
	if gui then
		gui.Enabled = visible
	end
	if visible and not connection then
		connection = RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			if clock < nextRefresh then
				return
			end
			nextRefresh = clock + REFRESH
			render()
		end)
	elseif not visible and connection then
		connection:Disconnect()
		connection = nil
	end
end

function AudioDebug.toggle()
	AudioDebug.setVisible(not AudioDebug.isVisible())
end

return AudioDebug
