--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local PostFx = require(script.Parent.PostFx)

local CursorMode = {}

local ZOOM_DISTANCE = 0.5

local openModals: { [string]: boolean } = {}
local modalCount = 0
local freeConnection: RBXScriptConnection? = nil
local frozenCFrame: CFrame? = nil
-- systems that drive the camera themselves while a menu is open (the helicopter
-- cabin's view, IntermissionCamera): the held camera is theirs, only the cursor is ours
local cameraOwners: { [string]: boolean } = {}

local function cameraOwned(): boolean
	return next(cameraOwners) ~= nil
end

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
	if camera and frozenCFrame and not cameraOwned() and camera.CameraType == Enum.CameraType.Scriptable then
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
	if camera and not cameraOwned() and camera.CameraType == Enum.CameraType.Scriptable then
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

	PostFx.setMenuBlur(modalCount > 0)

	if modalCount > 0 then
		enterFreeMode()
	else
		exitFreeMode()
	end
end

-- A system that drives the camera itself (`owned` true) while a menu frees the
-- cursor: the menu no longer holds the camera still or hands it back to Custom.
function CursorMode.setCameraOwner(id: string, owned: boolean)
	cameraOwners[id] = if owned then true else nil
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

-- A menu only frees the cursor if it remembers to announce itself, and anything built
-- outside this codebase never will - which leaves the player staring at a menu they
-- cannot click. So rather than trusting every panel to call setModalOpen, watch for one
-- that looks modal: an enabled ScreenGui holding a solid frame over a good part of the
-- screen. Panels that do announce themselves are unaffected; the id is separate.
local EXTERNAL_ID = "ExternalMenu"
local MODAL_FRACTION = 0.3

-- GuiObject.Visible reports only its own flag, and a hidden parent still leaves children
-- flagged visible with a real AbsoluteSize. Checking the chain is what separates an open
-- menu from a closed one whose panels were never individually hidden.
local function shownOnScreen(object: GuiObject, gui: ScreenGui): boolean
	local current: Instance? = object
	while current and current ~= gui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function looksModal(gui: ScreenGui, viewport: Vector2): boolean
	local hasPanel = false
	local hasControl = false
	for _, descendant in gui:GetDescendants() do
		if not descendant:IsA("GuiObject") or not shownOnScreen(descendant, gui) then
			continue
		end
		if descendant:IsA("GuiButton") or descendant:IsA("TextBox") then
			hasControl = true
		elseif descendant.BackgroundTransparency < 0.9 then
			local size = descendant.AbsoluteSize
			if size.X > viewport.X * MODAL_FRACTION and size.Y > viewport.Y * MODAL_FRACTION then
				hasPanel = true
			end
		end
		if hasPanel and hasControl then
			return true
		end
	end
	return false
end

local function scanForExternalMenu()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local found = false
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled and looksModal(gui, viewport) then
			found = true
			break
		end
	end
	CursorMode.setModalOpen(EXTERNAL_ID, found)
end

function CursorMode.init()
	lockFirstPerson()
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if modalCount == 0 then
			lockFirstPerson()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(scanForExternalMenu)
			if not ok then
				warn("[CursorMode] menu scan failed: " .. tostring(err))
			end
		end
	end)
end

return CursorMode
