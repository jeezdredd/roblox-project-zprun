--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local VendorsConfig = require(ReplicatedStorage.Shared.config.VendorsConfig)
local UiTheme = require(script.Parent.UiTheme)
local CursorMode = require(script.Parent.Parent.systems.CursorMode)
local UiSfx = require(script.Parent.Parent.systems.UiSfx)

local ShopGui = {}

local MODAL_ID = "Shop"

local player = Players.LocalPlayer

local screen: ScreenGui? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local creditsLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
local rowTemplate: Frame? = nil

local currentVendor: string? = nil
local busy = false

local function makeRow(): Frame
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.new(1, -8, 0, 62)
	row.BackgroundColor3 = UiTheme.PANEL_LIGHT
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0

	local name = Instance.new("TextLabel")
	name.Name = "ItemName"
	name.Position = UDim2.fromOffset(14, 8)
	name.Size = UDim2.new(1, -180, 0, 20)
	name.BackgroundTransparency = 1
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextSize = 16
	name.Text = ""
	UiTheme.styleText(name)
	name.Parent = row

	local description = Instance.new("TextLabel")
	description.Name = "ItemDescription"
	description.Position = UDim2.fromOffset(14, 30)
	description.Size = UDim2.new(1, -180, 0, 22)
	description.BackgroundTransparency = 1
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextSize = 13
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.Text = ""
	UiTheme.styleText(description, true)
	description.Parent = row

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -12, 0.5, 0)
	action.Size = UDim2.fromOffset(140, 36)
	action.BackgroundColor3 = UiTheme.PANEL
	action.BackgroundTransparency = 0.1
	action.BorderSizePixel = 0
	action.AutoButtonColor = false
	action.TextSize = 14
	action.Text = ""
	UiTheme.styleText(action)
	action.Parent = row

	return row
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(560, 440)
	UiTheme.stylePanel(frame)
	frame.Parent = gui

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(1, 0, 0, 2)
	accent.BackgroundColor3 = UiTheme.ACCENT
	accent.BorderSizePixel = 0
	accent.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -220, 0, 26)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 22
	title.Text = ""
	UiTheme.styleText(title)
	title.Parent = frame

	local credits = Instance.new("TextLabel")
	credits.Name = "Credits"
	credits.AnchorPoint = Vector2.new(1, 0)
	credits.Position = UDim2.new(1, -20, 0, 18)
	credits.Size = UDim2.fromOffset(180, 22)
	credits.BackgroundTransparency = 1
	credits.TextXAlignment = Enum.TextXAlignment.Right
	credits.TextSize = 18
	credits.TextColor3 = UiTheme.ACCENT
	credits.Font = UiTheme.FONT
	credits.TextStrokeTransparency = 1
	credits.Text = ""
	credits.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(16, 56)
	list.Size = UDim2.new(1, -32, 1, -110)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = UiTheme.ACCENT
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 20, 1, -16)
	status.Size = UDim2.new(1, -200, 0, 20)
	status.BackgroundTransparency = 1
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextSize = 14
	status.Text = ""
	UiTheme.styleText(status, true)
	status.Parent = frame

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -20, 1, -14)
	close.Size = UDim2.fromOffset(150, 30)
	close.BackgroundColor3 = UiTheme.PANEL_LIGHT
	close.BackgroundTransparency = 0.1
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.TextSize = 14
	close.Text = "CLOSE  [E]"
	UiTheme.styleText(close)
	close.Parent = frame
	close.Activated:Connect(function()
		ShopGui.close()
	end)

	screen = gui
	panel = frame
	titleLabel = title
	creditsLabel = credits
	statusLabel = status
	listFrame = list
	rowTemplate = makeRow()
end

local function actionTextFor(entry: any): (string, Color3, boolean)
	if entry.kind == "Skin" then
		if entry.equipped then
			return "EQUIPPED", UiTheme.TEXT_DIM, false
		end
		if entry.owned then
			return "EQUIP", UiTheme.OK, true
		end
		return string.format("BUY  $%d", entry.price), (if entry.affordable then UiTheme.ACCENT else UiTheme.DANGER), entry.affordable
	end
	if entry.maxLevel > 0 and entry.level >= entry.maxLevel then
		return "MAX", UiTheme.TEXT_DIM, false
	end
	if entry.kind == "Weapon" then
		return string.format("BUY  $%d", entry.price), (if entry.affordable then UiTheme.ACCENT else UiTheme.DANGER), entry.affordable
	end
	return string.format("UPGRADE  $%d", entry.price), (if entry.affordable then UiTheme.ACCENT else UiTheme.DANGER), entry.affordable
end

local function purchase(entryId: string)
	local vendorId = currentVendor
	if busy or not vendorId then
		return
	end
	busy = true
	local status = statusLabel
	if status then
		status.Text = "Processing..."
	end
	task.spawn(function()
		local ok, response = pcall(function()
			return Remotes.getFunction(Remotes.Function.ShopPurchase):InvokeServer(vendorId, entryId)
		end)
		busy = false
		if not ok or typeof(response) ~= "table" then
			if status then
				status.Text = "Purchase failed"
			end
			return
		end
		if status then
			status.Text = response.message or ""
			status.TextColor3 = if response.ok then UiTheme.OK else UiTheme.DANGER
		end
		UiSfx.click()
		if response.catalog then
			ShopGui.render(response.catalog)
		end
	end)
end

function ShopGui.render(catalog: any)
	local list = listFrame
	local template = rowTemplate
	if not list or not template then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local credits = creditsLabel
	if credits then
		credits.Text = string.format("$%d", catalog.credits)
	end

	for index, entry in catalog.entries do
		local row = template:Clone()
		row.LayoutOrder = index
		local nameLabel = row:FindFirstChild("ItemName") :: TextLabel
		local descriptionLabel = row:FindFirstChild("ItemDescription") :: TextLabel
		local action = row:FindFirstChild("Action") :: TextButton

		local suffix = ""
		if entry.maxLevel > 0 and entry.level > 0 then
			suffix = string.format("   L%d/%d", entry.level, entry.maxLevel)
		end
		nameLabel.Text = string.upper(entry.displayName) .. suffix
		if entry.owned and entry.xpNeeded > 0 and entry.level < entry.maxLevel then
			descriptionLabel.Text = string.format("%s · XP %d/%d", entry.description, entry.xp, entry.xpNeeded)
		else
			descriptionLabel.Text = entry.description
		end

		local text, color, enabled = actionTextFor(entry)
		action.Text = text
		action.TextColor3 = color
		action.Active = enabled
		action.AutoButtonColor = enabled
		if enabled then
			action.Activated:Connect(function()
				purchase(entry.id)
			end)
		end

		row.Parent = list
	end
end

function ShopGui.open(vendorId: string)
	local gui = screen
	local frame = panel
	if not gui or not frame then
		return
	end
	local config = VendorsConfig.get(vendorId)
	currentVendor = vendorId

	local title = titleLabel
	if title then
		title.Text = string.upper(if config then config.displayName else vendorId)
	end
	local status = statusLabel
	if status then
		status.Text = ""
		status.TextColor3 = UiTheme.TEXT_DIM
	end

	gui.Enabled = true
	CursorMode.setModalOpen(MODAL_ID, true)
	UiTheme.appear(frame, UDim2.fromScale(0.5, 0.5))

	task.spawn(function()
		local ok, catalog = pcall(function()
			return Remotes.getFunction(Remotes.Function.ShopCatalog):InvokeServer(vendorId)
		end)
		if ok and typeof(catalog) == "table" and currentVendor == vendorId then
			ShopGui.render(catalog)
		elseif status then
			status.Text = "Catalog unavailable"
		end
	end)
end

function ShopGui.close()
	local gui = screen
	if not gui or not gui.Enabled then
		return
	end
	gui.Enabled = false
	currentVendor = nil
	CursorMode.setModalOpen(MODAL_ID, false)
end

function ShopGui.isOpen(): boolean
	return currentVendor ~= nil
end

function ShopGui.init()
	build()

	Remotes.getEvent(Remotes.Event.ShopSync).OnClientEvent:Connect(function(catalog)
		if typeof(catalog) == "table" and catalog.vendorId == currentVendor then
			ShopGui.render(catalog)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not ShopGui.isOpen() then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Escape then
			ShopGui.close()
		end
	end)
end

return ShopGui
