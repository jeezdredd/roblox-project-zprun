--!strict

local Players = game:GetService("Players")

local SettingsService = require(script.Parent.Parent.systems.SettingsService)

local GoreWarningGui = {}

local shown = false

local function corner(instance: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = instance
end

function GoreWarningGui.showOnce()
	if shown then
		return
	end
	shown = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "GoreWarning"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 60
	screen.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(460, 260)
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 27)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	corner(panel, 10)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24)
	pad.PaddingRight = UDim.new(0, 24)
	pad.PaddingTop = UDim.new(0, 22)
	pad.PaddingBottom = UDim.new(0, 22)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 32)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(200, 70, 70)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 24
	title.Text = "CONTENT WARNING"
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Position = UDim2.fromOffset(0, 44)
	body.Size = UDim2.new(1, 0, 0, 120)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.TextColor3 = Color3.fromRGB(210, 210, 214)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.TextSize = 16
	body.Text = "This game contains zombie combat and stylized blood effects. You can turn blood and gore off at any time in Settings (gear icon)."
	body.Parent = panel

	local continueButton = Instance.new("TextButton")
	continueButton.AnchorPoint = Vector2.new(0, 1)
	continueButton.Position = UDim2.fromScale(0, 1)
	continueButton.Size = UDim2.new(0.55, -6, 0, 42)
	continueButton.BackgroundColor3 = Color3.fromRGB(60, 120, 90)
	continueButton.BorderSizePixel = 0
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 16
	continueButton.TextColor3 = Color3.fromRGB(235, 235, 235)
	continueButton.Text = "I Understand"
	continueButton.Parent = panel
	corner(continueButton, 6)

	local disableButton = Instance.new("TextButton")
	disableButton.AnchorPoint = Vector2.new(1, 1)
	disableButton.Position = UDim2.fromScale(1, 1)
	disableButton.Size = UDim2.new(0.45, -6, 0, 42)
	disableButton.BackgroundColor3 = Color3.fromRGB(50, 54, 62)
	disableButton.BorderSizePixel = 0
	disableButton.Font = Enum.Font.GothamBold
	disableButton.TextSize = 16
	disableButton.TextColor3 = Color3.fromRGB(235, 235, 235)
	disableButton.Text = "Disable Gore"
	disableButton.Parent = panel
	corner(disableButton, 6)

	continueButton.Activated:Connect(function()
		screen:Destroy()
	end)
	disableButton.Activated:Connect(function()
		SettingsService.set("bloodEnabled", false)
		SettingsService.set("dismembermentEnabled", false)
		screen:Destroy()
	end)
end

return GoreWarningGui
