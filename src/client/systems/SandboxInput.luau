--!strict

-- Keys for the Studio test yard (server Sandbox, DevConfig.SANDBOX):
--   G sends a chasing wave, H resets the yard, J calms everyone, T teleports back to the
--   start (server commands);
--   V third person on/off (the stock orbit camera, viewmodel hidden, body visible);
--   Z slow motion: 1, 1/4, 1/10 for the viewmodel, casings, both clip galleries and the
--     treadmills (camera ViewmodelTimeScale, workspace DevTimeScale, server gallery);
--   B plays the sound lane.
-- Studio's own free camera (Shift+P) works too. Does nothing outside Studio or when the
-- yard is off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevConfig = require(ReplicatedStorage.Shared.config.DevConfig)
local Viewmodel = require(script.Parent.Viewmodel)
local SandboxWeaponGallery = require(script.Parent.SandboxWeaponGallery)

local SandboxInput = {}

local SERVER_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.G] = "wave",
	[Enum.KeyCode.H] = "reset",
	[Enum.KeyCode.J] = "calm",
	[Enum.KeyCode.T] = "start",
}
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
	label.Position = UDim2.new(0.5, 0, 0, 12)
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
	-- CameraController reads this (Studio only) like DevConfig.THIRD_PERSON_VIEW
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

function SandboxInput.init()
	if not RunService:IsStudio() or not DevConfig.SANDBOX.enabled then
		return
	end
	SandboxWeaponGallery.init()
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("SandboxCommand", 15)
		if not remote or not remote:IsA("RemoteEvent") then
			return
		end
		buildStatus()
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
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
			end
		end)
		-- a weapon swap builds a fresh, visible viewmodel
		Players.LocalPlayer:GetAttributeChangedSignal("WeaponId"):Connect(function()
			if thirdPerson then
				task.defer(Viewmodel.setVisible, false)
			end
		end)
	end)
end

return SandboxInput
