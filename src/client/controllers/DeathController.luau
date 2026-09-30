--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.config.AudioConfig)
local GameConstants = require(ReplicatedStorage.Shared.config.GameConstants)
local ProductsConfig = require(ReplicatedStorage.Shared.config.ProductsConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local AnimationController = require(script.Parent.AnimationController)
local CameraEffectsController = require(script.Parent.CameraEffectsController)
local CursorMode = require(script.Parent.Parent.systems.CursorMode)
local UiSfx = require(script.Parent.Parent.systems.UiSfx)
local DeathGore = require(script.Parent.Parent.systems.DeathGore)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local MusicController = require(script.Parent.Parent.systems.MusicController)

local DeathController = {}

local DEATH_CAM = "DeathCam"
local CONFIRM_ACTION = "DeathConfirm"
local IMPACT_END = 0.22
local SIDE_END = 0.95
local ROLL_END = 1.75
local FALL_PITCH = math.rad(64)
local EYE_HEIGHT = 1.05
local SIDE_EYE_HEIGHT = 0.85
local HEAD_TRACK_WEIGHT = 0.22
local HEAD_TRACK_RATE = 2.5
local IMPACT_FOV_KICK = 6

local showResultsCursor: (() -> ())? = nil

local screen: ScreenGui
local blackout: Frame
local diedLabel: TextLabel
local resultsPanel: Frame
local distanceLabel: TextLabel
local xpLabel: TextLabel
local creditsLabel: TextLabel

local active = false
local chosen = false
local lastCorpsePos = Vector3.new(0, 5, 0)
local deathStartedAt = 0
local fallStart: CFrame? = nil
local groundY = 0
local trackedLook: CFrame? = nil

local function corner(instance: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = instance
end

local function makeResultLine(parent: Instance, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 30)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(225, 225, 228)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 20
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent
	return label
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	screen = Instance.new("ScreenGui")
	screen.Name = "DeathScreen"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 70
	screen.Enabled = false
	screen.Parent = playerGui

	blackout = Instance.new("Frame")
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	blackout.BackgroundTransparency = 1
	blackout.BorderSizePixel = 0
	blackout.Parent = screen

	diedLabel = Instance.new("TextLabel")
	diedLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	diedLabel.Position = UDim2.fromScale(0.5, 0.32)
	diedLabel.Size = UDim2.fromScale(0.8, 0.16)
	diedLabel.BackgroundTransparency = 1
	diedLabel.Font = Enum.Font.GothamBlack
	diedLabel.TextColor3 = Color3.fromRGB(190, 45, 45)
	diedLabel.TextTransparency = 1
	diedLabel.TextScaled = true
	diedLabel.Text = "YOU ARE DEAD"
	diedLabel.Parent = screen

	resultsPanel = Instance.new("Frame")
	resultsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultsPanel.Position = UDim2.fromScale(0.5, 0.62)
	resultsPanel.Size = UDim2.fromOffset(420, 300)
	resultsPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 27)
	resultsPanel.BackgroundTransparency = 1
	resultsPanel.BorderSizePixel = 0
	resultsPanel.Visible = false
	resultsPanel.Parent = screen
	corner(resultsPanel, 10)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 24)
	pad.PaddingRight = UDim.new(0, 24)
	pad.PaddingTop = UDim.new(0, 20)
	pad.PaddingBottom = UDim.new(0, 20)
	pad.Parent = resultsPanel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = resultsPanel

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 30)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextColor3 = Color3.fromRGB(200, 200, 205)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextSize = 18
	heading.Text = "RUN RESULTS"
	heading.LayoutOrder = 1
	heading.Parent = resultsPanel

	distanceLabel = makeResultLine(resultsPanel, 2)
	xpLabel = makeResultLine(resultsPanel, 3)
	creditsLabel = makeResultLine(resultsPanel, 4)

	local buttonRow = Instance.new("Frame")
	buttonRow.Size = UDim2.new(1, 0, 0, 46)
	buttonRow.BackgroundTransparency = 1
	buttonRow.LayoutOrder = 5
	buttonRow.Parent = resultsPanel

	local returnButton = Instance.new("TextButton")
	returnButton.Size = UDim2.fromScale(0.48, 1)
	returnButton.BackgroundColor3 = Color3.fromRGB(60, 120, 90)
	returnButton.BorderSizePixel = 0
	returnButton.Font = Enum.Font.GothamBold
	returnButton.TextSize = 16
	returnButton.TextColor3 = Color3.fromRGB(235, 235, 235)
	returnButton.Text = "Return to Hub"
	returnButton.Parent = buttonRow
	corner(returnButton, 6)

	local continueButton = Instance.new("TextButton")
	continueButton.AnchorPoint = Vector2.new(1, 0)
	continueButton.Position = UDim2.fromScale(1, 0)
	continueButton.Size = UDim2.fromScale(0.48, 1)
	continueButton.BackgroundColor3 = Color3.fromRGB(150, 110, 40)
	continueButton.BorderSizePixel = 0
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 15
	continueButton.TextColor3 = Color3.fromRGB(235, 235, 235)
	local continueProduct = ProductsConfig.getProduct("Continue")
	continueButton.Text = if continueProduct and continueProduct.productId > 0
		then string.format("Continue  %d R$", continueProduct.robuxPrice)
		else "Continue"
	continueButton.Parent = buttonRow
	corner(continueButton, 6)

	local function choose(choice: string)
		if chosen then
			return
		end
		chosen = true
		active = false
		RunService:UnbindFromRenderStep(DEATH_CAM)
		ContextActionService:UnbindAction(CONFIRM_ACTION)
		CursorMode.setModalOpen("DeathResults", false)
		screen.Enabled = false
		Remotes.getEvent(Remotes.Event.DeathChoice):FireServer(choice)
	end

	showResultsCursor = function()
		CursorMode.setModalOpen("DeathResults", true)
		CursorMode.focus(returnButton)
		ContextActionService:BindAction(CONFIRM_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				choose("return")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonA)
	end

	returnButton.Activated:Connect(function()
		choose("return")
	end)
	continueButton.Activated:Connect(function()
		if continueProduct and continueProduct.productId > 0 then
			Remotes.getEvent(Remotes.Event.DeathChoice):FireServer("continue")
			return
		end
		choose("continue")
	end)
end

local function findNearestZombieHead(origin: Vector3): Vector3?
	local zombies = Workspace:FindFirstChild("Zombies")
	if not zombies then
		return nil
	end
	local nearest: Vector3? = nil
	local nearestDistance = 26
	for _, model in zombies:GetChildren() do
		local head = model:IsA("Model") and model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local distance = (head.Position - origin).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearest = head.Position
			end
		end
	end
	return nearest
end

local function groundBelow(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local exclude: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	local zombies = Workspace:FindFirstChild("Zombies")
	if zombies then
		table.insert(exclude, zombies)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else position.Y - 3
end

local function easeOutCubic(alpha: number): number
	return 1 - (1 - alpha) ^ 3
end

local function easeInQuad(alpha: number): number
	return alpha * alpha
end

local function updateDeathCam(deltaTime: number)
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if not fallStart then
		fallStart = camera.CFrame
	end
	local start = fallStart :: CFrame

	local elapsed = os.clock() - deathStartedAt
	local runDirection = GameConstants.RUN_DIRECTION
	local right = runDirection:Cross(Vector3.yAxis)
	local corpseFlat = Vector3.new(lastCorpsePos.X, groundY, lastCorpsePos.Z) - runDirection * 0.6

	local impact = start * CFrame.new(0.15, -0.12, 0.45) * CFrame.Angles(math.rad(-12), math.rad(6), math.rad(9))

	local sideEye = corpseFlat + Vector3.new(0, SIDE_EYE_HEIGHT, 0) + right * 0.35
	local sideLook = (CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-60)) * runDirection)
	local side = CFrame.lookAt(sideEye, sideEye + sideLook) * CFrame.Angles(math.rad(-8), 0, math.rad(-78))

	local eyePosition = corpseFlat + Vector3.new(0, EYE_HEIGHT, 0)
	local lying = CFrame.lookAt(eyePosition, eyePosition + runDirection) * CFrame.Angles(FALL_PITCH, 0, 0)

	if elapsed >= ROLL_END then
		local head = findNearestZombieHead(eyePosition)
		local target = if head then lying:Lerp(CFrame.lookAt(eyePosition, head), HEAD_TRACK_WEIGHT) else lying
		local trackAlpha = 1 - math.exp(-HEAD_TRACK_RATE * deltaTime)
		trackedLook = if trackedLook then (trackedLook :: CFrame):Lerp(target, trackAlpha) else target
		lying = trackedLook :: CFrame
	else
		trackedLook = lying
	end

	local settled = math.max(elapsed - ROLL_END, 0)
	local bounce = math.exp(-settled * 6) * math.sin(settled * 22) * 0.1
	local breath = math.sin(elapsed * 2.1) * 0.05
	local roll = math.rad(math.sin(elapsed * 1.3) * 4 + 5)
	local resting = lying * CFrame.new(0, bounce + breath, 0) * CFrame.Angles(math.rad(math.sin(elapsed * 1.7) * 2), 0, roll)

	if elapsed < IMPACT_END then
		camera.CFrame = start:Lerp(impact, easeOutCubic(elapsed / IMPACT_END))
	elseif elapsed < SIDE_END then
		camera.CFrame = impact:Lerp(side, easeInQuad((elapsed - IMPACT_END) / (SIDE_END - IMPACT_END)))
	elseif elapsed < ROLL_END then
		camera.CFrame = side:Lerp(resting, easeOutCubic((elapsed - SIDE_END) / (ROLL_END - SIDE_END)))
	else
		camera.CFrame = resting
	end
end

local function playScream()
	if AudioConfig.DEATH_SCREAM_ID <= 0 then
		return
	end
	if AudioEngine.enabled() then
		AudioEngine.play({ id = AudioConfig.DEATH_SCREAM_ID, class = "Scream", volume = 1 })
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "DeathScream"
	sound.SoundId = "rbxassetid://" .. tostring(AudioConfig.DEATH_SCREAM_ID)
	sound.Volume = 1
	sound.SoundGroup = MusicController.getMasterGroup()
	sound.Parent = SoundService
	sound:Play()
	task.delay(8, function()
		sound:Destroy()
	end)
end

local function restoreCharacterVisibility()
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 0
		end
	end
end

local function onDeathBegan(rewards: any)
	if active then
		return
	end
	active = true
	chosen = false
	deathStartedAt = os.clock()
	fallStart = nil
	trackedLook = nil

	blackout.BackgroundTransparency = 1
	diedLabel.TextTransparency = 1
	resultsPanel.Visible = false
	resultsPanel.BackgroundTransparency = 1
	screen.Enabled = true

	restoreCharacterVisibility()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		lastCorpsePos = root.Position
	end
	groundY = groundBelow(lastCorpsePos)
	AnimationController.playOneShot("Death")
	CameraEffectsController.fovKick(IMPACT_FOV_KICK)
	DeathGore.render(lastCorpsePos)
	playScream()

	RunService:BindToRenderStep(DEATH_CAM, Enum.RenderPriority.Camera.Value + 1, updateDeathCam)

	task.spawn(function()
		for _ = 1, 5 do
			task.wait(1.1)
			if not active then
				return
			end
			DeathGore.feastTick(lastCorpsePos)
		end
	end)

	task.spawn(function()
		task.wait(6)
		if not active then
			return
		end
		TweenService:Create(blackout, TweenInfo.new(0.9), { BackgroundTransparency = 0.15 }):Play()
		TweenService:Create(diedLabel, TweenInfo.new(0.9), { TextTransparency = 0 }):Play()
		task.wait(1.5)
		if not active then
			return
		end
		distanceLabel.Text = "Distance: 0 m"
		xpLabel.Text = "XP earned: 0"
		creditsLabel.Text = "Credits: 0"
		resultsPanel.Visible = true

		task.spawn(function()
			local rows = {
				{ label = distanceLabel, value = rewards.distance or 0, format = "Distance: %d m" },
				{ label = xpLabel, value = rewards.xp or 0, format = "XP earned: %d" },
				{ label = creditsLabel, value = rewards.credits or 0, format = "Credits: %d" },
			}
			for _, row in rows do
				if not active then
					return
				end
				local steps = 14
				for index = 1, steps do
					if not active then
						return
					end
					local shown = math.floor(row.value * index / steps + 0.5)
					row.label.Text = string.format(row.format, shown)
					UiSfx.rewardTick()
					task.wait(0.03)
				end
				row.label.Text = string.format(row.format, row.value)
				task.wait(0.15)
			end
			creditsLabel.Text = string.format("Credits: %d  (x%.2f)", rewards.credits or 0, rewards.multiplier or 1)
		end)
		TweenService:Create(resultsPanel, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
		if showResultsCursor then
			showResultsCursor()
		end
	end)
end

function DeathController.init()
	build()
	Remotes.getEvent(Remotes.Event.DeathBegan).OnClientEvent:Connect(onDeathBegan)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		active = false
		fallStart = nil
		trackedLook = nil
		RunService:UnbindFromRenderStep(DEATH_CAM)
		ContextActionService:UnbindAction(CONFIRM_ACTION)
		CursorMode.setModalOpen("DeathResults", false)
		screen.Enabled = false
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
end

return DeathController
