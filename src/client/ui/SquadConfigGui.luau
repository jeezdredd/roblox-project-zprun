--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapsConfig = require(ReplicatedStorage.Shared.config.MapsConfig)
local ModifiersConfig = require(ReplicatedStorage.Shared.config.ModifiersConfig)
local Squad = require(ReplicatedStorage.Shared.types.Squad)

export type Handlers = {
	onSelectMap: (string) -> (),
	onSelectDifficulty: (string) -> (),
	onSelectPrivacy: (string) -> (),
	onToggleModifier: (string) -> (),
	onLaunch: () -> (),
	onLeave: () -> (),
}

export type GuiController = {
	update: (Squad.SquadSnapshot?) -> (),
}

local SquadConfigGui = {}

local PANEL_COLOR = Color3.fromRGB(20, 22, 27)
local ROW_COLOR = Color3.fromRGB(32, 35, 42)
local ACCENT = Color3.fromRGB(190, 55, 55)
local SELECTED = Color3.fromRGB(60, 120, 90)
local TEXT_COLOR = Color3.fromRGB(228, 228, 230)
local MUTED = Color3.fromRGB(150, 152, 158)
local DIFFICULTY_ORDER = { "Easy", "Medium", "Hard" }

type Option = { id: string, text: string }

type SelectorRow = {
	buttons: { [string]: TextButton },
	highlight: ({ string }) -> (),
	setEnabled: (boolean) -> (),
}

local function makeLabel(text: string, size: UDim2, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = MUTED
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 14
	label.Text = text
	label.Parent = parent
	return label
end

local function makeSelectorRow(title: string, options: { Option }, layoutOrder: number, parent: Instance, onSelect: (string) -> ()): SelectorRow
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 60)
	container.BackgroundTransparency = 1
	container.LayoutOrder = layoutOrder
	container.Parent = parent

	makeLabel(string.upper(title), UDim2.new(1, 0, 0, 18), container)

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 36)
	row.Position = UDim2.fromOffset(0, 22)
	row.BackgroundTransparency = 1
	row.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	local buttons: { [string]: TextButton } = {}
	for _, option in options do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 96, 1, 0)
		button.BackgroundColor3 = ROW_COLOR
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.TextColor3 = TEXT_COLOR
		button.Text = option.text
		button.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		button.Activated:Connect(function()
			onSelect(option.id)
		end)
		buttons[option.id] = button
	end

	local function highlight(selectedIds: { string })
		local selectedSet: { [string]: boolean } = {}
		for _, id in selectedIds do
			selectedSet[id] = true
		end
		for id, button in buttons do
			button.BackgroundColor3 = if selectedSet[id] then SELECTED else ROW_COLOR
		end
	end

	local function setEnabled(enabled: boolean)
		for _, button in buttons do
			button.Active = enabled
			button.AutoButtonColor = enabled
			button.TextTransparency = if enabled then 0 else 0.4
		end
	end

	return { buttons = buttons, highlight = highlight, setEnabled = setEnabled }
end

function SquadConfigGui.create(handlers: Handlers): GuiController
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "SquadLobby"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 20
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 560)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Parent = screen
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.PaddingTop = UDim.new(0, 18)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = TEXT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 22
	title.Text = "SQUAD LOBBY"
	title.LayoutOrder = 1
	title.Parent = panel

	local membersLabel = makeLabel("", UDim2.new(1, 0, 0, 18), panel)
	membersLabel.TextColor3 = TEXT_COLOR
	membersLabel.LayoutOrder = 2

	local mapOptions: { Option } = {}
	for _, id in MapsConfig.order do
		local map = MapsConfig.get(id)
		table.insert(mapOptions, { id = id, text = if map then map.displayName else id })
	end
	local mapRow = makeSelectorRow("Map", mapOptions, 3, panel, handlers.onSelectMap)

	local difficultyOptions: { Option } = {}
	for _, id in DIFFICULTY_ORDER do
		table.insert(difficultyOptions, { id = id, text = id })
	end
	local difficultyRow = makeSelectorRow("Difficulty", difficultyOptions, 4, panel, handlers.onSelectDifficulty)

	local privacyOptions: { Option } = {
		{ id = "Solo", text = "Solo" },
		{ id = "FriendsOnly", text = "Friends" },
		{ id = "Public", text = "Public" },
	}
	local privacyRow = makeSelectorRow("Privacy", privacyOptions, 5, panel, handlers.onSelectPrivacy)

	local modifierOptions: { Option } = {}
	for _, id in ModifiersConfig.order do
		local modifier = ModifiersConfig.get(id)
		table.insert(modifierOptions, { id = id, text = if modifier then modifier.displayName else id })
	end
	local modifierRow = makeSelectorRow("Modifiers", modifierOptions, 6, panel, handlers.onToggleModifier)

	local rewardLabel = makeLabel("", UDim2.new(1, 0, 0, 20), panel)
	rewardLabel.TextColor3 = ACCENT
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 16
	rewardLabel.LayoutOrder = 7

	local footer = Instance.new("Frame")
	footer.Size = UDim2.new(1, 0, 0, 46)
	footer.BackgroundTransparency = 1
	footer.LayoutOrder = 8
	footer.Parent = panel

	local leaveButton = Instance.new("TextButton")
	leaveButton.Size = UDim2.fromScale(0.4, 1)
	leaveButton.BackgroundColor3 = ROW_COLOR
	leaveButton.BorderSizePixel = 0
	leaveButton.Font = Enum.Font.GothamBold
	leaveButton.TextSize = 16
	leaveButton.TextColor3 = TEXT_COLOR
	leaveButton.Text = "Leave"
	leaveButton.Parent = footer
	local leaveCorner = Instance.new("UICorner")
	leaveCorner.CornerRadius = UDim.new(0, 6)
	leaveCorner.Parent = leaveButton
	leaveButton.Activated:Connect(handlers.onLeave)

	local launchButton = Instance.new("TextButton")
	launchButton.AnchorPoint = Vector2.new(1, 0)
	launchButton.Position = UDim2.fromScale(1, 0)
	launchButton.Size = UDim2.fromScale(0.55, 1)
	launchButton.BackgroundColor3 = ACCENT
	launchButton.BorderSizePixel = 0
	launchButton.Font = Enum.Font.GothamBlack
	launchButton.TextSize = 18
	launchButton.TextColor3 = TEXT_COLOR
	launchButton.Text = "LAUNCH"
	launchButton.Parent = footer
	local launchCorner = Instance.new("UICorner")
	launchCorner.CornerRadius = UDim.new(0, 6)
	launchCorner.Parent = launchButton
	launchButton.Activated:Connect(handlers.onLaunch)

	local currentSnapshot: Squad.SquadSnapshot? = nil

	local function refresh()
		local snapshot = currentSnapshot
		if not snapshot then
			screen.Enabled = false
			return
		end
		screen.Enabled = true

		local isLeader = snapshot.leaderUserId == Players.LocalPlayer.UserId

		membersLabel.Text = string.format("Squad %d/%d — %s", #snapshot.members, snapshot.capacity, if isLeader then "you lead" else "leader controls settings")

		mapRow.highlight({ snapshot.config.mapId })
		difficultyRow.highlight({ snapshot.config.difficultyId })
		privacyRow.highlight({ snapshot.config.privacy })
		modifierRow.highlight(snapshot.config.modifierIds)

		mapRow.setEnabled(isLeader)
		difficultyRow.setEnabled(isLeader)
		privacyRow.setEnabled(isLeader)
		modifierRow.setEnabled(isLeader)

		rewardLabel.Text = string.format("Reward x%.2f", snapshot.rewardMultiplier)

		if snapshot.state == "Launching" then
			local remaining = 0
			if snapshot.countdownEndsAt then
				remaining = math.max(0, snapshot.countdownEndsAt - Workspace:GetServerTimeNow())
			end
			launchButton.Text = string.format("LAUNCHING %d", math.ceil(remaining))
			launchButton.Active = false
			launchButton.AutoButtonColor = false
		elseif isLeader then
			launchButton.Text = "LAUNCH"
			launchButton.Active = true
			launchButton.AutoButtonColor = true
			launchButton.TextTransparency = 0
		else
			launchButton.Text = "WAITING"
			launchButton.Active = false
			launchButton.AutoButtonColor = false
			launchButton.TextTransparency = 0.3
		end
	end

	task.spawn(function()
		while screen.Parent do
			if currentSnapshot and currentSnapshot.state == "Launching" then
				refresh()
			end
			task.wait(0.2)
		end
	end)

	local function update(snapshot: Squad.SquadSnapshot?)
		currentSnapshot = snapshot
		refresh()
	end

	return { update = update }
end

return SquadConfigGui
