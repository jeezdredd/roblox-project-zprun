--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevMode = require(ReplicatedStorage.Shared.util.DevMode)
local CursorMode = require(script.Parent.CursorMode)
local Viewmodel = require(script.Parent.Viewmodel)
local SandboxWeaponGallery = require(script.Parent.SandboxWeaponGallery)
local SandboxBodyGallery = require(script.Parent.SandboxBodyGallery)
local AudioDebug = require(script.Parent.Parent.audio.AudioDebug)

local SandboxInput = {}

local SERVER_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.G] = "wave",
	[Enum.KeyCode.H] = "reset",
	[Enum.KeyCode.J] = "calm",
	[Enum.KeyCode.T] = "start",
}
local YARD_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.G] = true,
	[Enum.KeyCode.H] = true,
	[Enum.KeyCode.J] = true,
	[Enum.KeyCode.T] = true,
	[Enum.KeyCode.Z] = true,
	[Enum.KeyCode.B] = true,
}
local MODE_KEY = Enum.KeyCode.M
local CURSOR_KEY = Enum.KeyCode.LeftAlt
local TIME_SCALES = { 1, 0.25, 0.1 }

local thirdPerson = false
local timeIndex = 1
local statusLabel: TextLabel? = nil

local function refreshStatus()
	local label = statusLabel
	if not label then
		return
	end
	local parts = {}
	if TIME_SCALES[timeIndex] ~= 1 then
		table.insert(parts, string.format("TIME x%.2f", TIME_SCALES[timeIndex]))
	end
	if thirdPerson then
		table.insert(parts, "3RD PERSON")
	end
	label.Text = table.concat(parts, "   ")
end

local function buildStatus()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SandboxStatus"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 44)
	label.Size = UDim2.fromOffset(420, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 200, 90)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = gui
	statusLabel = label
end

local function setThirdPerson(on: boolean)
	thirdPerson = on
	Workspace:SetAttribute("DevThirdPerson", on)
	Viewmodel.setVisible(not on)
	refreshStatus()
end

local function setTimeScale(index: number, remote: RemoteEvent)
	timeIndex = index
	local value = TIME_SCALES[index]
	local camera = Workspace.CurrentCamera
	if camera then
		camera:SetAttribute("ViewmodelTimeScale", if value == 1 then nil else value)
	end
	Workspace:SetAttribute("DevTimeScale", value)
	remote:FireServer("timescale", value)
	refreshStatus()
end

local function buildModeButton(remote: RemoteEvent)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevModeButton"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 8)
	button.Size = UDim2.fromOffset(196, 30)
	button.BackgroundColor3 = Color3.fromRGB(24, 26, 22)
	button.BackgroundTransparency = 0.25
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.Code
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(255, 200, 90)
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button
	local function render()
		button.Text = if DevMode.yard() then "[M] BACK TO RUN" else "[M] TEST YARD"
	end
	render()
	Workspace:GetAttributeChangedSignal("DevMode"):Connect(render)
	button.Activated:Connect(function()
		remote:FireServer("mode", if DevMode.yard() then "Run" else "Yard")
	end)
end

function SandboxInput.init()
	if not RunService:IsStudio() then
		return
	end
	SandboxWeaponGallery.init()
	SandboxBodyGallery.init()
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("SandboxCommand", 15)
		if not remote or not remote:IsA("RemoteEvent") then
			return
		end
		buildStatus()
		buildModeButton(remote)
		UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == CURSOR_KEY then
				CursorMode.setModalOpen("DevCursor", false)
			end
		end)
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == CURSOR_KEY then
				CursorMode.setModalOpen("DevCursor", true)
				return
			end
			if processed then
				return
			end
			if input.KeyCode == MODE_KEY then
				remote:FireServer("mode", if DevMode.yard() then "Run" else "Yard")
				return
			end
			if YARD_KEYS[input.KeyCode] and not DevMode.yard() then
				return
			end
			local command = SERVER_KEYS[input.KeyCode]
			if command then
				remote:FireServer(command)
			elseif input.KeyCode == Enum.KeyCode.V then
				setThirdPerson(not thirdPerson)
			elseif input.KeyCode == Enum.KeyCode.Z then
				setTimeScale(timeIndex % #TIME_SCALES + 1, remote)
			elseif input.KeyCode == Enum.KeyCode.B then
				SandboxWeaponGallery.playSoundLane()
			elseif input.KeyCode == Enum.KeyCode.K then
				AudioDebug.toggle()
			elseif input.KeyCode == Enum.KeyCode.L then
				AudioDebug.fireTestShot()
			end
		end)
	end)
end

return SandboxInput
