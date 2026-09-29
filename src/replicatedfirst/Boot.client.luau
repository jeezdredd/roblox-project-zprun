--!strict

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Everything visual the first run needs: the mesh templates and their textures in
-- ReplicatedStorage, and every texture and mesh id in AssetIds (world props, PBR sets).
-- Without this the textures arrive while the player is already running and visibly
-- sharpen from a blurry first mip.
local PRELOAD_FOLDERS = { "ViewModels", "ViewModelArms", "ZombieMeshes" }
local PRELOAD_BRANCHES = { "texture", "mesh" }

-- Returns what to hand PreloadAsync and how many assets that should come to. The asset
-- folders go in as instances: SurfaceAppearance maps cannot be read from a game script
-- (reading ColorMap needs the Plugin capability), but PreloadAsync fetches everything an
-- instance references, so the folders load in full without reading them.
local function collectContent(): ({ any }, number)
	local seen: { [string]: boolean } = {}
	local list: { any } = {}
	local expected = 0
	local function add(content: string?)
		if content and content ~= "" and content ~= "rbxassetid://0" and not seen[content] then
			seen[content] = true
			table.insert(list, content)
			expected += 1
		end
	end
	for _, folderName in PRELOAD_FOLDERS do
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		if folder then
			table.insert(list, folder)
			for _, item in folder:GetDescendants() do
				if item:IsA("MeshPart") then
					expected += if item.TextureID ~= "" then 2 else 1
				elseif item:IsA("SurfaceAppearance") then
					expected += 3
				elseif item:IsA("Decal") then
					expected += 1
				end
			end
		end
	end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local config = shared and shared:FindFirstChild("config")
	local module = config and config:FindFirstChild("AssetIds")
	if module and module:IsA("ModuleScript") then
		local ok, ids = pcall(require, module)
		if ok and type(ids) == "table" then
			local function walk(node: any)
				if type(node) == "number" then
					if node > 0 then
						add("rbxassetid://" .. tostring(node))
					end
				elseif type(node) == "table" then
					for _, child in node do
						walk(child)
					end
				end
			end
			for _, branch in PRELOAD_BRANCHES do
				walk((ids :: any)[branch])
			end
		end
	end
	return list, expected
end

type PreloadProgress = { total: number, loaded: number, done: boolean }

-- Starts the preload in the background; the returned table fills in as assets arrive.
local function startPreload(): PreloadProgress
	local progress: PreloadProgress = { total = 0, loaded = 0, done = false }
	task.spawn(function()
		-- whatever goes wrong, the boot must not wait on a preload that died
		local ok, err = pcall(function()
			local list, expected = collectContent()
			progress.total = math.max(expected, 1)
			ContentProvider:PreloadAsync(list, function()
				progress.loaded = math.min(progress.loaded + 1, progress.total)
			end)
		end)
		if not ok then
			warn("[TaskForceZ][Boot] preload failed: " .. tostring(err))
		end
		progress.done = true
	end)
	return progress
end

-- Share of the bar each phase fills: uplink, assets (driven by the real preload count),
-- priming, deploying. The asset phase is the only one that waits on anything, and it
-- shows its count so a slow first load reads as progress rather than a hang.
local BAR_SPLIT = { 0.08, 0.8, 0.06, 0.06 }

local function runLoadingPhase(gui: BootGui)
	local steps = BootConfig.LOADING_STEPS
	local startClock = os.clock()

	local function setBar(fraction: number, time: number?)
		tween(gui.barFill, time or 0.15, { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) })
	end

	gui.statusLabel.Text = string.upper(steps[1] or "")
	setBar(BAR_SPLIT[1], BootConfig.STEP_DURATION)
	if not game:IsLoaded() then
		local deadline = os.clock() + BootConfig.LOADED_WAIT_DEADLINE
		while not game:IsLoaded() and os.clock() < deadline do
			task.wait()
		end
	end
	task.wait(BootConfig.STEP_DURATION)

	local progress = startPreload()
	local assetLabel = string.upper(steps[2] or "")
	local preloadDeadline = os.clock() + BootConfig.PRELOAD_DEADLINE
	local hintAt = os.clock() + BootConfig.SKIP_HINT_AFTER
	while not progress.done and not skipRequested and os.clock() < preloadDeadline do
		local fraction = if progress.total > 0 then progress.loaded / progress.total else 0
		local text = if progress.total > 0
			then string.format("%s  %d / %d", assetLabel, progress.loaded, progress.total)
			else assetLabel
		if os.clock() > hintAt then
			text ..= "   ·   SPACE TO SKIP"
		end
		gui.statusLabel.Text = text
		setBar(BAR_SPLIT[1] + BAR_SPLIT[2] * fraction)
		task.wait(0.1)
	end

	local reached = BAR_SPLIT[1] + BAR_SPLIT[2]
	for index = 3, #steps do
		if skipRequested then
			break
		end
		reached += BAR_SPLIT[index] or 0
		gui.statusLabel.Text = string.upper(steps[index])
		setBar(reached, BootConfig.STEP_DURATION)
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
