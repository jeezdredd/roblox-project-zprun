--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local BootConfig = require(ReplicatedFirst:WaitForChild("BootConfig"))
local BootState = require(ReplicatedFirst:WaitForChild("BootState"))

ReplicatedFirst:RemoveDefaultLoadingScreen()

local SKIP_ACTION = "BootSkip"

local skipRequested = false

type BootGui = {
	screen: ScreenGui,
	background: Frame,
	statusLabel: TextLabel,
	barFill: Frame,
	title: TextLabel,
	tagline: TextLabel,
	lore: TextLabel,
}

local function makeLabel(name: string, parent: Instance, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextColor3 = BootConfig.TEXT_COLOR
	label.TextScaled = false
	label.TextTransparency = 1
	label.Parent = parent
	return label
end

local function buildGui(playerGui: Instance): BootGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "BootScreen"
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = BootConfig.DISPLAY_ORDER
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = BootConfig.BACKGROUND_COLOR
	background.BorderSizePixel = 0
	background.Parent = screen

	local statusLabel = makeLabel("Status", background, UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.5, 0.72))
	statusLabel.TextColor3 = BootConfig.MUTED_COLOR
	statusLabel.TextSize = 18
	statusLabel.TextTransparency = 0
	statusLabel.Text = ""

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.AnchorPoint = Vector2.new(0.5, 0.5)
	barBack.Size = UDim2.fromScale(0.42, 0.012)
	barBack.Position = UDim2.fromScale(0.5, 0.8)
	barBack.BackgroundColor3 = BootConfig.PANEL_COLOR
	barBack.BorderSizePixel = 0
	barBack.Parent = background

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = BootConfig.BAR_COLOR
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	local title = makeLabel("Title", background, UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.5, 0.44))
	title.Text = BootConfig.TITLE_PRIMARY
	title.TextSize = 72
	title.Font = Enum.Font.GothamBlack

	local tagline = makeLabel("Tagline", background, UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.5, 0.55))
	tagline.Text = BootConfig.TAGLINE
	tagline.TextColor3 = BootConfig.ACCENT_COLOR
	tagline.TextSize = 22

	local lore = makeLabel("Lore", background, UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.5, 0.62))
	lore.Text = BootConfig.LORE_LINE
	lore.TextColor3 = BootConfig.MUTED_COLOR
	lore.TextSize = 16

	screen.Parent = playerGui
	return {
		screen = screen,
		background = background,
		statusLabel = statusLabel,
		barFill = barFill,
		title = title,
		tagline = tagline,
		lore = lore,
	}
end

local function tween(instance: Instance, time: number, goals: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

local function runLoadingPhase(gui: BootGui)
	local steps = BootConfig.LOADING_STEPS
	local count = #steps
	local startClock = os.clock()

	if not game:IsLoaded() then
		local deadline = os.clock() + BootConfig.LOADED_WAIT_DEADLINE
		while not game:IsLoaded() and os.clock() < deadline do
			task.wait()
		end
	end

	for index, label in steps do
		if skipRequested then
			break
		end
		gui.statusLabel.Text = string.upper(label)
		tween(gui.barFill, BootConfig.STEP_DURATION, { Size = UDim2.fromScale(index / count, 1) })
		task.wait(BootConfig.STEP_DURATION)
	end

	gui.barFill.Size = UDim2.fromScale(1, 1)

	local elapsed = os.clock() - startClock
	if elapsed < BootConfig.MIN_DISPLAY_SECONDS then
		task.wait(BootConfig.MIN_DISPLAY_SECONDS - elapsed)
	end
end

local function runIntro(gui: BootGui)
	tween(gui.statusLabel, 0.3, { TextTransparency = 1 })
	tween(gui.barFill, 0.3, { BackgroundTransparency = 1 })

	if skipRequested then
		gui.title.TextTransparency = 0
		gui.tagline.TextTransparency = 0
		gui.lore.TextTransparency = 0
		return
	end

	gui.title.Position = UDim2.fromScale(0.5, 0.46)
	tween(gui.title, BootConfig.INTRO_TITLE_TIME, { TextTransparency = 0, Position = UDim2.fromScale(0.5, 0.44) })
	task.wait(BootConfig.INTRO_TITLE_TIME * 0.6)

	if not skipRequested then
		tween(gui.tagline, BootConfig.INTRO_LINE_TIME, { TextTransparency = 0 })
		task.wait(BootConfig.INTRO_LINE_TIME * 0.6)
	end
	if not skipRequested then
		tween(gui.lore, BootConfig.INTRO_LINE_TIME, { TextTransparency = 0 })
	end

	local holdEnd = os.clock() + BootConfig.INTRO_HOLD
	while os.clock() < holdEnd and not skipRequested do
		task.wait()
	end
end

local function fadeOut(gui: BootGui)
	tween(gui.background, BootConfig.FADE_TIME, { BackgroundTransparency = 1 })
	tween(gui.title, BootConfig.FADE_TIME, { TextTransparency = 1 })
	tween(gui.tagline, BootConfig.FADE_TIME, { TextTransparency = 1 })
	tween(gui.lore, BootConfig.FADE_TIME, { TextTransparency = 1 })
	task.wait(BootConfig.FADE_TIME)
	gui.screen:Destroy()
end

local function bindSkip()
	ContextActionService:BindAction(SKIP_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			skipRequested = true
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Return, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
end

local function main()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)

	local gui = buildGui(playerGui)
	bindSkip()

	runLoadingPhase(gui)
	runIntro(gui)
	fadeOut(gui)
end

local ok, err = pcall(main)
if not ok then
	warn("[TaskForceZ][Boot] boot sequence failed: " .. tostring(err))
end

ContextActionService:UnbindAction(SKIP_ACTION)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
end)
BootState.setReady()
