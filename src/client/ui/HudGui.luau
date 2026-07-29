--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local SettingsService = require(script.Parent.Parent.systems.SettingsService)
local SettingsGui = require(script.Parent.SettingsGui)

local HudGui = {}

local MUTE_ACTION = "ToggleMute"
local SETTINGS_ACTION = "ToggleSettings"
local BUTTON_COLOR = Color3.fromRGB(28, 30, 36)
local TEXT_COLOR = Color3.fromRGB(228, 228, 230)

local function makeButton(parent: Instance, text: string, offsetX: number): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, offsetX, 0, 12)
	button.Size = UDim2.fromOffset(40, 40)
	button.BackgroundColor3 = BUTTON_COLOR
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = TEXT_COLOR
	button.Text = text
	button.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = button
	return button
end

function HudGui.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local settings = SettingsGui.create()

	local screen = Instance.new("ScreenGui")
	screen.Name = "Hud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 45
	screen.Parent = playerGui

	local gearButton = makeButton(screen, "⚙", -12)
	local muteButton = makeButton(screen, "🔊", -60)

	local function renderMute(muted: any)
		muteButton.Text = if muted == true then "🔇" else "🔊"
	end

	gearButton.Activated:Connect(function()
		settings.toggle()
	end)
	muteButton.Activated:Connect(function()
		SettingsService.set("muted", not (SettingsService.get("muted") == true))
	end)
	SettingsService.observe("muted", renderMute)

	ContextActionService:BindAction(MUTE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			SettingsService.set("muted", not (SettingsService.get("muted") == true))
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M)

	ContextActionService:BindAction(SETTINGS_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			settings.toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P)

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, -12, 0, 58)
	hint.Size = UDim2.fromOffset(180, 20)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 13
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = Color3.fromRGB(190, 190, 196)
	hint.TextStrokeTransparency = 0.6
	hint.Text = "P settings · M mute"
	hint.Parent = screen

	local player = Players.LocalPlayer

	local walletPanel = Instance.new("Frame")
	walletPanel.Name = "Wallet"
	walletPanel.AnchorPoint = Vector2.new(1, 0)
	walletPanel.Position = UDim2.new(1, -14, 0, 76)
	walletPanel.Size = UDim2.fromOffset(178, 40)
	walletPanel.BackgroundColor3 = Color3.fromRGB(12, 13, 14)
	walletPanel.BackgroundTransparency = 0.35
	walletPanel.BorderSizePixel = 0
	walletPanel.Parent = screen

	local walletAccent = Instance.new("Frame")
	walletAccent.Name = "Accent"
	walletAccent.Size = UDim2.new(0, 2, 1, 0)
	walletAccent.BackgroundColor3 = Color3.fromRGB(126, 142, 96)
	walletAccent.BorderSizePixel = 0
	walletAccent.Parent = walletPanel

	local creditsLabel = Instance.new("TextLabel")
	creditsLabel.Name = "Credits"
	creditsLabel.Position = UDim2.fromOffset(12, 4)
	creditsLabel.Size = UDim2.new(1, -22, 0, 20)
	creditsLabel.BackgroundTransparency = 1
	creditsLabel.Font = Enum.Font.RobotoMono
	creditsLabel.TextSize = 17
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
	creditsLabel.TextColor3 = Color3.fromRGB(214, 216, 206)
	creditsLabel.TextStrokeTransparency = 1
	creditsLabel.Text = ""
	creditsLabel.Parent = walletPanel

	local xpLabel = Instance.new("TextLabel")
	xpLabel.Name = "Xp"
	xpLabel.Position = UDim2.fromOffset(12, 22)
	xpLabel.Size = UDim2.new(1, -22, 0, 14)
	xpLabel.BackgroundTransparency = 1
	xpLabel.Font = Enum.Font.RobotoMono
	xpLabel.TextSize = 12
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.TextColor3 = Color3.fromRGB(138, 140, 130)
	xpLabel.TextStrokeTransparency = 1
	xpLabel.Text = ""
	xpLabel.Parent = walletPanel

	local function refreshWallet()
		local inMission = player:GetAttribute("FlowPhase") == "Mission"
		walletPanel.Visible = not inMission

		local credits = player:GetAttribute("Credits")
		local xp = player:GetAttribute("XP")
		creditsLabel.Text = if typeof(credits) == "number" then string.format("CR %d", credits) else "CR --"
		xpLabel.Text = if typeof(xp) == "number" then string.format("XP %d", xp) else ""
	end
	player:GetAttributeChangedSignal("Credits"):Connect(refreshWallet)
	player:GetAttributeChangedSignal("XP"):Connect(refreshWallet)
	player:GetAttributeChangedSignal("FlowPhase"):Connect(refreshWallet)
	refreshWallet()
end

return HudGui
