--!strict

-- The helicopter intermission's panel (docs/gameplay/heli-intermission.md):
--
--   Cabin  the ready check: the squad with a mark per member, the AFK timer, READY
--          (a toggle), LOADOUT (the shop panel on the "Cabin" catalog: loadout slots
--          and perk equips, nothing to buy) and LEAVE (back to the hub).
--   Crash  the timer and, on a repeat run, SKIP with the votes so far.
--   Wake   a large "RUN" while GraceUntil is ahead, with the seconds left.
--
-- Everything shown comes from the server's IntermissionState snapshot; the buttons
-- only send requests (IntermissionReady, IntermissionSkip, SquadLeave) the server
-- validates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local IntermissionMath = require(ReplicatedStorage.Shared.util.IntermissionMath)
local CursorMode = require(script.Parent.Parent.systems.CursorMode)
local UiSfx = require(script.Parent.Parent.systems.UiSfx)
local ShopGui = require(script.Parent.ShopGui)
local UiTheme = require(script.Parent.UiTheme)

local CabinGui = {}

local MODAL_ID = "Cabin"
local CABIN_VENDOR = "Cabin"
local MAX_ROWS = 3

local player = Players.LocalPlayer

type Row = {
	userId: number,
	name: string,
	ready: boolean,
	skip: boolean,
}

type Snapshot = {
	stage: string,
	endsAt: number,
	skippable: boolean,
	members: { Row },
}

local screen: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local timerLabel: TextLabel
local rowLabels: { TextLabel } = {}
local readyButton: TextButton
local loadoutButton: TextButton
local leaveButton: TextButton
local skipButton: TextButton
local runScreen: ScreenGui
local runLabel: TextLabel
local runTimer: TextLabel

local current: Snapshot? = nil
local modalOpen = false

local function label(name: string, size: UDim2, position: UDim2, textSize: number, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Size = size
	text.Position = position
	text.BackgroundTransparency = 1
	text.TextSize = textSize
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = ""
	UiTheme.styleText(text)
	text.Parent = parent
	return text
end

local function button(name: string, text: string, position: UDim2, width: number, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(width, 34)
	b.Position = position
	b.BackgroundColor3 = UiTheme.PANEL_LIGHT
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.TextSize = 14
	b.Text = text
	UiTheme.styleText(b)
	b.Parent = parent
	UiSfx.bindButton(b)
	return b
end

local function build()
	screen = Instance.new("ScreenGui")
	screen.Name = "CabinGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- above the intermission's black fade (50)
	screen.DisplayOrder = 60
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -28)
	panel.Size = UDim2.fromOffset(440, 200)
	UiTheme.stylePanel(panel)
	panel.Parent = screen

	titleLabel = label("Title", UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 10), 16, panel)
	timerLabel = label("Timer", UDim2.fromOffset(120, 22), UDim2.new(1, -134, 0, 10), 16, panel)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.TextColor3 = UiTheme.ACCENT

	for index = 1, MAX_ROWS do
		local row = label("Member" .. index, UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 38 + (index - 1) * 22), 14, panel)
		UiTheme.styleText(row, true)
		rowLabels[index] = row
	end

	readyButton = button("Ready", "READY", UDim2.new(0, 14, 1, -48), 130, panel)
	loadoutButton = button("Loadout", "LOADOUT", UDim2.new(0, 154, 1, -48), 130, panel)
	leaveButton = button("Leave", "LEAVE", UDim2.new(0, 294, 1, -48), 130, panel)
	skipButton = button("Skip", "SKIP", UDim2.new(0, 14, 1, -48), 410, panel)

	readyButton.Activated:Connect(function()
		local snapshot = current
		if not snapshot then
			return
		end
		local mine = false
		for _, row in snapshot.members do
			if row.userId == player.UserId then
				mine = row.ready
			end
		end
		Remotes.getEvent(Remotes.Event.IntermissionReady):FireServer(not mine)
	end)
	loadoutButton.Activated:Connect(function()
		ShopGui.open(CABIN_VENDOR, "Loadout and perks")
	end)
	leaveButton.Activated:Connect(function()
		ShopGui.close()
		Remotes.getEvent(Remotes.Event.SquadLeave):FireServer()
	end)
	skipButton.Activated:Connect(function()
		Remotes.getEvent(Remotes.Event.IntermissionSkip):FireServer()
	end)

	runScreen = Instance.new("ScreenGui")
	runScreen.Name = "WakeUpGui"
	runScreen.ResetOnSpawn = false
	runScreen.IgnoreGuiInset = true
	runScreen.DisplayOrder = 40
	runScreen.Enabled = false
	runScreen.Parent = player:WaitForChild("PlayerGui")

	runLabel = Instance.new("TextLabel")
	runLabel.Name = "Run"
	runLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	runLabel.Position = UDim2.fromScale(0.5, 0.36)
	runLabel.Size = UDim2.fromOffset(400, 96)
	runLabel.BackgroundTransparency = 1
	runLabel.TextSize = 84
	runLabel.Text = "RUN"
	UiTheme.styleText(runLabel)
	runLabel.Font = UiTheme.FONT_BOLD
	runLabel.TextColor3 = UiTheme.DANGER
	runLabel.TextStrokeTransparency = 0.5
	runLabel.Parent = runScreen

	runTimer = Instance.new("TextLabel")
	runTimer.Name = "Grace"
	runTimer.AnchorPoint = Vector2.new(0.5, 0)
	runTimer.Position = UDim2.new(0.5, 0, 0.36, 52)
	runTimer.Size = UDim2.fromOffset(400, 22)
	runTimer.BackgroundTransparency = 1
	runTimer.TextSize = 15
	runTimer.Text = ""
	UiTheme.styleText(runTimer, true)
	runTimer.Parent = runScreen
end

local function setModal(open: boolean)
	if modalOpen == open then
		return
	end
	modalOpen = open
	CursorMode.setModalOpen(MODAL_ID, open)
end

local function render()
	local snapshot = current
	if not snapshot then
		screen.Enabled = false
		setModal(false)
		return
	end
	screen.Enabled = true
	local inCabin = snapshot.stage == "Cabin"
	-- the crash beat is the cinematic's screen: the panel only stays for a skip vote
	local showPanel = inCabin or snapshot.skippable
	panel.Visible = showPanel
	setModal(showPanel)
	titleLabel.Text = if inCabin then "READY CHECK" else "BRACE FOR IMPACT"
	local skipCount, mine, myVote = 0, false, false
	for index = 1, MAX_ROWS do
		local row = snapshot.members[index]
		local text = rowLabels[index]
		if row then
			local mark = if inCabin then (if row.ready then "READY" else "...") else (if row.skip then "SKIP" else "")
			text.Text = string.format("%s  %s", string.upper(row.name), mark)
			text.TextColor3 = if (inCabin and row.ready) or (not inCabin and row.skip) then UiTheme.ACCENT else UiTheme.TEXT_DIM
			if row.skip then
				skipCount += 1
			end
			if row.userId == player.UserId then
				mine = row.ready
				myVote = row.skip
			end
		else
			text.Text = ""
		end
	end
	readyButton.Visible = inCabin
	loadoutButton.Visible = inCabin
	leaveButton.Visible = inCabin
	readyButton.Text = if mine then "NOT READY" else "READY"
	readyButton.TextColor3 = if mine then UiTheme.TEXT_DIM else UiTheme.ACCENT
	skipButton.Visible = not inCabin and snapshot.skippable
	skipButton.Text = string.format("%s  %d/%d", if myVote then "SKIP VOTED" else "SKIP", skipCount, #snapshot.members)
	if not inCabin then
		ShopGui.close()
	end
end

local function step()
	local snapshot = current
	if snapshot then
		local left = IntermissionMath.secondsLeft(snapshot.endsAt, Workspace:GetServerTimeNow())
		timerLabel.Text = if snapshot.stage == "Cabin" then string.format("AUTO %ds", left) else string.format("%ds", left)
	end
	if runScreen.Enabled then
		local graceUntil = player:GetAttribute("GraceUntil")
		local now = Workspace:GetServerTimeNow()
		if IntermissionMath.inGrace(graceUntil, now) and player:GetAttribute("FlowPhase") == "Mission" then
			runTimer.Text = string.format("THEY HAVE NOT SEEN YOU YET  %ds", IntermissionMath.secondsLeft(graceUntil :: number, now))
		else
			runScreen.Enabled = false
		end
	end
end

local function decode(raw: any): Snapshot?
	if typeof(raw) ~= "table" or typeof(raw.stage) ~= "string" or typeof(raw.endsAt) ~= "number" or typeof(raw.members) ~= "table" then
		return nil
	end
	local rows: { Row } = {}
	for _, row in raw.members do
		if typeof(row) == "table" and typeof(row.userId) == "number" and typeof(row.name) == "string" then
			table.insert(rows, { userId = row.userId, name = row.name, ready = row.ready == true, skip = row.skip == true })
		end
	end
	return { stage = raw.stage, endsAt = raw.endsAt, skippable = raw.skippable == true, members = rows }
end

local function onGrace()
	local graceUntil = player:GetAttribute("GraceUntil")
	if not IntermissionMath.inGrace(graceUntil, Workspace:GetServerTimeNow()) then
		return
	end
	runScreen.Enabled = true
	runLabel.TextTransparency = 1
	TweenService:Create(runLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
end

function CabinGui.init()
	build()
	Remotes.getEvent(Remotes.Event.IntermissionState).OnClientEvent:Connect(function(raw)
		current = decode(raw)
		render()
	end)
	player:GetAttributeChangedSignal("GraceUntil"):Connect(onGrace)
	RunService.Heartbeat:Connect(step)
end

return CabinGui
