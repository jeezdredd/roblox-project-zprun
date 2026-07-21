--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FpsCounter = {}

local screen: ScreenGui
local label: TextLabel
local accumulator = 0
local frames = 0

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	screen = Instance.new("ScreenGui")
	screen.Name = "FpsCounter"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 40
	screen.Enabled = false
	screen.Parent = playerGui

	label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(120, 24)
	label.Position = UDim2.fromOffset(12, 88)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.Font = Enum.Font.Code
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(120, 230, 120)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "-- FPS"
	label.Parent = screen
end

function FpsCounter.setVisible(visible: boolean)
	screen.Enabled = visible
end

function FpsCounter.init()
	build()
	RunService.RenderStepped:Connect(function(deltaTime)
		accumulator += deltaTime
		frames += 1
		if accumulator >= 0.5 then
			local fps = math.floor(frames / accumulator + 0.5)
			label.Text = string.format("%d FPS", fps)
			accumulator = 0
			frames = 0
		end
	end)
end

return FpsCounter
