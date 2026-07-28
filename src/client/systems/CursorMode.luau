--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CursorMode = {}

local ZOOM_DISTANCE = 0.5

local openModals: { [string]: boolean } = {}
local modalCount = 0
local freeConnection: RBXScriptConnection? = nil
local frozenCFrame: CFrame? = nil

local function lockFirstPerson()
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = ZOOM_DISTANCE
	player.CameraMaxZoomDistance = ZOOM_DISTANCE
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

local function holdCursorFree()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local camera = Workspace.CurrentCamera
	if camera and frozenCFrame and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CFrame = frozenCFrame
	end
end

local function enterFreeMode()
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	if camera then
		frozenCFrame = camera.CFrame
		camera.CameraType = Enum.CameraType.Scriptable
	end
	player.CameraMode = Enum.CameraMode.Classic
	if not freeConnection then
		freeConnection = RunService.RenderStepped:Connect(holdCursorFree)
	end
	holdCursorFree()
end

local function exitFreeMode()
	if freeConnection then
		freeConnection:Disconnect()
		freeConnection = nil
	end
	frozenCFrame = nil
	GuiService.SelectedObject = nil
	UserInputService.MouseIconEnabled = false
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
	lockFirstPerson()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

function CursorMode.setModalOpen(id: string, open: boolean)
	local wasOpen = openModals[id] == true
	if wasOpen == open then
		return
	end
	openModals[id] = if open then true else nil
	modalCount += if open then 1 else -1
	if modalCount < 0 then
		modalCount = 0
	end

	if modalCount > 0 then
		enterFreeMode()
	else
		exitFreeMode()
	end
end

function CursorMode.isAnyOpen(): boolean
	return modalCount > 0
end

function CursorMode.focus(button: GuiButton?)
	if button then
		button.Selectable = true
		GuiService.SelectedObject = button
	end
end

function CursorMode.init()
	lockFirstPerson()
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if modalCount == 0 then
			lockFirstPerson()
		end
	end)
end

return CursorMode
