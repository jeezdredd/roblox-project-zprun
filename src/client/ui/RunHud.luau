--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UiTheme = require(script.Parent.UiTheme)

local RunHud = {}

local HEALTH_VISIBLE_TIME = 3
local LOW_HEALTH_RATIO = 0.4

local screen: ScreenGui
local distanceLabel: TextLabel
local healthBack: Frame
local healthFill: Frame
local healthVisibleUntil = 0
local lastHealth = 1
local started = false

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	screen = Instance.new("ScreenGui")
	screen.Name = "RunHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 15
	screen.Enabled = false
	screen.Parent = playerGui

	distanceLabel = Instance.new("TextLabel")
	distanceLabel.Name = "Distance"
	distanceLabel.AnchorPoint = Vector2.new(0.5, 1)
	distanceLabel.Position = UDim2.new(0.5, 0, 1, -54)
	distanceLabel.Size = UDim2.fromOffset(320, 46)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.TextSize = 38
	distanceLabel.Text = "0"
	distanceLabel.TextTransparency = 0.08
	UiTheme.styleText(distanceLabel)
	distanceLabel.Parent = screen

	local unit = Instance.new("TextLabel")
	unit.AnchorPoint = Vector2.new(0.5, 1)
	unit.Position = UDim2.new(0.5, 0, 1, -38)
	unit.Size = UDim2.fromOffset(320, 16)
	unit.BackgroundTransparency = 1
	unit.TextSize = 12
	unit.Text = "METRES"
	UiTheme.styleText(unit, true)
	unit.TextTransparency = 0.35
	unit.Parent = screen

	local earnings = Instance.new("TextLabel")
	earnings.Name = "RunEarnings"
	earnings.AnchorPoint = Vector2.new(0.5, 1)
	earnings.Position = UDim2.new(0.5, 0, 1, -100)
	earnings.Size = UDim2.fromOffset(320, 18)
	earnings.BackgroundTransparency = 1
	earnings.TextSize = 14
	earnings.Text = ""
	UiTheme.styleText(earnings, true)
	earnings.TextColor3 = Color3.fromRGB(168, 178, 132)
	earnings.Parent = screen

	local function refreshEarnings()
		local runCredits = Players.LocalPlayer:GetAttribute("RunCredits")
		earnings.Text = if typeof(runCredits) == "number" then string.format("+%d CR THIS RUN", runCredits) else ""
	end
	Players.LocalPlayer:GetAttributeChangedSignal("RunCredits"):Connect(refreshEarnings)
	refreshEarnings()

	healthBack = Instance.new("Frame")
	healthBack.AnchorPoint = Vector2.new(0.5, 1)
	healthBack.Position = UDim2.new(0.5, 0, 1, -20)
	healthBack.Size = UDim2.fromOffset(220, 3)
	healthBack.BackgroundColor3 = Color3.fromRGB(60, 60, 62)
	healthBack.BackgroundTransparency = 1
	healthBack.BorderSizePixel = 0
	healthBack.Parent = screen

	healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = UiTheme.TEXT
	healthFill.BackgroundTransparency = 1
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
end

local function healthRatio(): number
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 1
	end
	return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
end

local function step()
	if not screen.Enabled then
		return
	end

	local leaderstats = Players.LocalPlayer:FindFirstChild("leaderstats")
	local distance = leaderstats and leaderstats:FindFirstChild("Distance")
	if distance and distance:IsA("IntValue") then
		distanceLabel.Text = tostring(distance.Value)
	end

	local ratio = healthRatio()
	if ratio < lastHealth - 0.001 then
		healthVisibleUntil = os.clock() + HEALTH_VISIBLE_TIME
	end
	lastHealth = ratio

	local shouldShow = ratio <= LOW_HEALTH_RATIO or os.clock() < healthVisibleUntil
	local targetTransparency = if shouldShow then 0.2 else 1
	healthBack.BackgroundTransparency += (targetTransparency + 0.35 - healthBack.BackgroundTransparency) * 0.12
	healthFill.BackgroundTransparency += (targetTransparency - healthFill.BackgroundTransparency) * 0.12
	healthFill.Size = UDim2.fromScale(ratio, 1)
	healthFill.BackgroundColor3 = if ratio <= LOW_HEALTH_RATIO then UiTheme.DANGER else UiTheme.TEXT
end

local function onPhaseChanged()
	local inMission = Players.LocalPlayer:GetAttribute("FlowPhase") == "Mission"
	screen.Enabled = inMission
	if inMission then
		distanceLabel.TextTransparency = 1
		TweenService:Create(distanceLabel, TweenInfo.new(0.3), { TextTransparency = 0.08 }):Play()
	end
end

function RunHud.init()
	if started then
		return
	end
	started = true
	build()
	Players.LocalPlayer:GetAttributeChangedSignal("FlowPhase"):Connect(onPhaseChanged)
	onPhaseChanged()
	RunService.Heartbeat:Connect(step)
end

return RunHud
