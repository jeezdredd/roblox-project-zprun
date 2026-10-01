--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CreditsConfig = require(ReplicatedStorage.Shared.config.CreditsConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.config.SettingsConfig)
local CursorMode = require(script.Parent.Parent.systems.CursorMode)
local UiSfx = require(script.Parent.Parent.systems.UiSfx)
local SettingsService = require(script.Parent.Parent.systems.SettingsService)

export type GuiController = {
	setOpen: (boolean) -> (),
	toggle: () -> (),
}

local SettingsGui = {}

local PANEL_COLOR = Color3.fromRGB(20, 22, 27)
local ROW_COLOR = Color3.fromRGB(32, 35, 42)
local ACCENT = Color3.fromRGB(190, 55, 55)
local ON_COLOR = Color3.fromRGB(60, 120, 90)
local TEXT_COLOR = Color3.fromRGB(228, 228, 230)
local MUTED = Color3.fromRGB(150, 152, 158)

local function corner(instance: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = instance
end

local function makeRow(parent: Instance, order: number): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(0.5, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 15
	label.Text = ""
	label.Parent = row

	return row
end

local function makeToggle(parent: Instance, spec: SettingsConfig.SettingSpec, order: number)
	local row = makeRow(parent, order)
	local label = row:FindFirstChild("Label") :: TextLabel
	label.Text = spec.label

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
	button.Size = UDim2.fromOffset(78, 28)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = TEXT_COLOR
	button.Parent = row
	corner(button, 6)

	local function render(value: any)
		button.BackgroundColor3 = if value == true then ON_COLOR else ROW_COLOR
		button.Text = if value == true then "ON" else "OFF"
	end

	button.Activated:Connect(function()
		SettingsService.set(spec.key, not (SettingsService.get(spec.key) == true))
	end)
	UiSfx.bindButton(button)
	SettingsService.observe(spec.key, render)
end

local function makeSlider(parent: Instance, spec: SettingsConfig.SettingSpec, order: number)
	local row = makeRow(parent, order)
	local label = row:FindFirstChild("Label") :: TextLabel

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromOffset(150, 8)
	track.BackgroundColor3 = ROW_COLOR
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)

	local minValue = spec.min or 0
	local maxValue = spec.max or 1
	local step = spec.step or 0.05

	local function render(value: any)
		local fraction = (value - minValue) / (maxValue - minValue)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		label.Text = string.format("%s  %d%%", spec.label, math.floor(fraction * 100 + 0.5))
	end

	local function setFromX(x: number)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = minValue + fraction * (maxValue - minValue)
		local stepped = math.floor(raw / step + 0.5) * step
		SettingsService.set(spec.key, math.clamp(stepped, minValue, maxValue))
	end

	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	SettingsService.observe(spec.key, render)
end

local CREDITS_HEIGHT = 220

local function creditLabel(parent: Instance, text: string, order: number, size: number, color: Color3, font: Enum.Font)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -8, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.TextSize = size
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
end

-- The read-only credits list (CreditsConfig, generated from the manifest): each group
-- of CC BY works, one line per work, then the acknowledgements; scrolls on its own.
local function makeCredits(parent: Instance, order: number)
	local list = Instance.new("ScrollingFrame")
	list.Name = "Credits"
	list.Size = UDim2.new(1, 0, 0, CREDITS_HEIGHT)
	list.BackgroundColor3 = ROW_COLOR
	list.BackgroundTransparency = 0.4
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.LayoutOrder = order
	list.Parent = parent
	corner(list, 6)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = list

	local line = 0
	local function add(text: string, size: number, color: Color3, font: Enum.Font)
		line += 1
		creditLabel(list, text, line, size, color, font)
	end

	add(CreditsConfig.NOTE, 12, MUTED, Enum.Font.Gotham)
	for _, group in CreditsConfig.groups do
		if #group.credits == 0 then
			continue
		end
		add(string.upper(group.name), 12, MUTED, Enum.Font.GothamBold)
		for _, credit in group.credits do
			add(string.format("%s by %s. %s. %s", credit.title, credit.author, credit.licence, credit.url), 12, TEXT_COLOR, Enum.Font.Gotham)
		end
	end
	if #CreditsConfig.acknowledgements > 0 then
		add("WITH THANKS", 12, MUTED, Enum.Font.GothamBold)
		for _, ack in CreditsConfig.acknowledgements do
			add(string.format("%s by %s. %s. %s", ack.title, ack.author, ack.licence, ack.url), 12, TEXT_COLOR, Enum.Font.Gotham)
		end
	end
end

function SettingsGui.create(): GuiController
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "Settings"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 50
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(460, 520)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Parent = screen
	corner(panel, 10)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	-- the setting rows scroll between the title and the close button, so a longer
	-- schema (the credits list) never pushes the button off the panel
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -88)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 5
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.LayoutOrder = 1
	body.Parent = panel
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 6)
	bodyLayout.Parent = body
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingRight = UDim.new(0, 10)
	bodyPad.Parent = body

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = TEXT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 22
	title.Text = "SETTINGS"
	title.LayoutOrder = 0
	title.Parent = panel

	local order = 1
	for _, category in SettingsConfig.categories do
		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 22)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.TextColor3 = MUTED
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextSize = 13
		header.Text = string.upper(category)
		header.LayoutOrder = order
		header.Parent = body
		order += 1

		for _, key in SettingsConfig.order do
			local spec = SettingsConfig.byKey[key]
			if spec.category == category then
				if spec.kind == "toggle" then
					makeToggle(body, spec, order)
				elseif spec.kind == "credits" then
					makeCredits(body, order)
				else
					makeSlider(body, spec, order)
				end
				order += 1
			end
		end
	end

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(1, 0, 0, 40)
	closeButton.BackgroundColor3 = ACCENT
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.TextColor3 = TEXT_COLOR
	closeButton.Text = "Close"
	closeButton.LayoutOrder = 2
	closeButton.Parent = panel
	corner(closeButton, 6)

	local function setOpen(open: boolean)
		screen.Enabled = open
		CursorMode.setModalOpen("Settings", open)
		if open then
			CursorMode.focus(closeButton)
		end
	end

	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	UiSfx.bindButton(closeButton)

	return {
		setOpen = setOpen,
		toggle = function()
			setOpen(not screen.Enabled)
		end,
	}
end

return SettingsGui
