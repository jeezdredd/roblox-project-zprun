--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local SettingsService = require(script.Parent.Parent.systems.SettingsService)
local SettingsGui = require(script.Parent.SettingsGui)

local HudGui = {}

local MUTE_ACTION = "ToggleMute"
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
end

return HudGui
