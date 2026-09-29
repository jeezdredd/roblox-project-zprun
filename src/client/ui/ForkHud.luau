--!strict

-- Route fork prompt: shows the two choices while the local runner approaches the vote
-- line, highlights the side they are on, then announces the result. Reads only the
-- Workspace attributes ForkService writes. See wiki/project-zprun/Route Forks.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local ForkConfig = require(ReplicatedStorage.Shared.config.ForkConfig)
local LocationsConfig = require(ReplicatedStorage.Shared.config.LocationsConfig)
local UiTheme = require(script.Parent.UiTheme)

local ForkHud = {}

local SHOW_BEFORE = ForkConfig.DIVIDER_LENGTH + 120

local screen: ScreenGui
local panel: Frame
local title: TextLabel
local leftLabel: TextLabel
local rightLabel: TextLabel
local timerLabel: TextLabel
local resultUntil = 0
local started = false

local function nameOf(id: any): string
	if typeof(id) ~= "string" then
		return "?"
	end
	local location = LocationsConfig.get(id)
	return string.upper(if location then location.displayName else id)
end

local function makeLabel(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.TextSize = textSize
	UiTheme.styleText(label)
	label.Parent = parent
	return label
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen = Instance.new("ScreenGui")
	screen.Name = "ForkHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 16
	screen.Enabled = false
	screen.Parent = playerGui

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 70)
	panel.Size = UDim2.fromOffset(520, 96)
	UiTheme.stylePanel(panel)
	panel.BackgroundTransparency = 0.35
	panel.Parent = screen

	title = makeLabel(panel, UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 6), 18)
	title.TextColor3 = UiTheme.ACCENT
	leftLabel = makeLabel(panel, UDim2.new(0.5, -10, 0, 36), UDim2.fromOffset(10, 34), 28)
	leftLabel.TextXAlignment = Enum.TextXAlignment.Left
	rightLabel = makeLabel(panel, UDim2.new(0.5, -10, 0, 36), UDim2.new(0.5, 0, 0, 34), 28)
	rightLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel = makeLabel(panel, UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 72), 16)
	UiTheme.styleText(timerLabel, true)
end

local function rootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function update()
	local now = os.clock()
	local vote = Workspace:GetAttribute("ForkVoteDistance")
	local root = rootPart()

	if typeof(vote) == "number" and root then
		local distance = (root.Position - GameConstants.RUN_ORIGIN):Dot(GameConstants.RUN_DIRECTION)
		local remaining = vote - distance
		if remaining > 0 and remaining < SHOW_BEFORE then
			local onLeft = root.Position.X < GameConstants.RUN_ORIGIN.X
			title.Text = "CHOOSE YOUR ROUTE"
			leftLabel.Text = "◀ " .. nameOf(Workspace:GetAttribute("ForkLeft"))
			rightLabel.Text = nameOf(Workspace:GetAttribute("ForkRight")) .. " ▶"
			leftLabel.TextColor3 = if onLeft then UiTheme.ACCENT else UiTheme.TEXT_DIM
			rightLabel.TextColor3 = if onLeft then UiTheme.TEXT_DIM else UiTheme.ACCENT
			local speed = math.max(1, root.AssemblyLinearVelocity:Dot(GameConstants.RUN_DIRECTION))
			timerLabel.Text = string.format("%d m  ·  %.0f s", math.floor(remaining), remaining / speed)
			screen.Enabled = true
			return
		end
	end

	if now < resultUntil then
		screen.Enabled = true
		return
	end
	screen.Enabled = false
end

local function onResult()
	local result = Workspace:GetAttribute("ForkResult")
	if typeof(result) ~= "string" then
		return
	end
	title.Text = "ROUTE"
	leftLabel.Text = ""
	rightLabel.Text = ""
	timerLabel.Text = ""
	leftLabel.TextColor3 = UiTheme.TEXT
	leftLabel.Size = UDim2.new(1, -20, 0, 36)
	leftLabel.TextXAlignment = Enum.TextXAlignment.Center
	leftLabel.Text = nameOf(result)
	resultUntil = os.clock() + ForkConfig.RESULT_SHOW_TIME
	task.delay(ForkConfig.RESULT_SHOW_TIME, function()
		leftLabel.Size = UDim2.new(0.5, -10, 0, 36)
		leftLabel.TextXAlignment = Enum.TextXAlignment.Left
	end)
end

function ForkHud.init()
	if started then
		return
	end
	started = true
	build()
	Workspace:GetAttributeChangedSignal("ForkResult"):Connect(onResult)
	RunService.RenderStepped:Connect(update)
end

return ForkHud
