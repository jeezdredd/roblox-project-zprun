--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)

local DeathController = {}

local DEATH_CAM = "DeathCam"

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
	continueButton.Text = "Continue (Robux)"
	continueButton.Parent = buttonRow
	corner(continueButton, 6)

	local function choose(choice: string)
		if chosen then
			return
		end
		chosen = true
		active = false
		RunService:UnbindFromRenderStep(DEATH_CAM)
		screen.Enabled = false
		Remotes.getEvent(Remotes.Event.DeathChoice):FireServer(choice)
	end

	returnButton.Activated:Connect(function()
		choose("return")
	end)
	continueButton.Activated:Connect(function()
		choose("continue")
	end)
end

local function updateDeathCam()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		lastCorpsePos = root.Position
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local camPosition = lastCorpsePos + Vector3.new(3, 5, 8)
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camPosition, lastCorpsePos), 0.15)
end

local function onDeathBegan(rewards: any)
	if active then
		return
	end
	active = true
	chosen = false

	blackout.BackgroundTransparency = 1
	diedLabel.TextTransparency = 1
	resultsPanel.Visible = false
	resultsPanel.BackgroundTransparency = 1
	screen.Enabled = true

	RunService:BindToRenderStep(DEATH_CAM, Enum.RenderPriority.Camera.Value + 1, updateDeathCam)

	task.spawn(function()
		task.wait(3)
		if not active then
			return
		end
		TweenService:Create(blackout, TweenInfo.new(0.9), { BackgroundTransparency = 0.15 }):Play()
		TweenService:Create(diedLabel, TweenInfo.new(0.9), { TextTransparency = 0 }):Play()
		task.wait(1.4)
		if not active then
			return
		end
		distanceLabel.Text = string.format("Distance: %d m", rewards.distance or 0)
		xpLabel.Text = string.format("XP earned: %d", rewards.xp or 0)
		creditsLabel.Text = string.format("Credits: %d  (x%.2f)", rewards.credits or 0, rewards.multiplier or 1)
		resultsPanel.Visible = true
		TweenService:Create(resultsPanel, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	end)
end

function DeathController.init()
	build()
	Remotes.getEvent(Remotes.Event.DeathBegan).OnClientEvent:Connect(onDeathBegan)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		active = false
		RunService:UnbindFromRenderStep(DEATH_CAM)
		screen.Enabled = false
	end)
end

return DeathController
