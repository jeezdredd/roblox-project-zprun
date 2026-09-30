--!strict

-- The client half of the weapon pickups (docs/gameplay/weapon-pickups.md): the
-- Highlight outlines that let a scene read through the fog, pooled below Roblox's
-- limit of 31 rendered Highlights and handed to the nearest scenes by the pure
-- HighlightBudget; and the toast when the server hands over a weapon or refuses a
-- supply drop. The prompt itself is the server's ProximityPrompt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PickupScenesConfig = require(ReplicatedStorage.Shared.config.PickupScenesConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local HighlightBudget = require(ReplicatedStorage.Shared.util.HighlightBudget)
local UiSfx = require(script.Parent.UiSfx)
local WeaponVfx = require(script.Parent.WeaponVfx)
local UiTheme = require(script.Parent.Parent.ui.UiTheme)

local WeaponPickupClient = {}

local TAG = "WeaponPickup"

local player = Players.LocalPlayer

local scenes: { [string]: Model } = {}
local nextId = 0
local idOf: { [Model]: string } = {}
local pool: { Highlight } = {}
local held: { [string]: Highlight } = {}
local heldSet: { [string]: boolean } = {}
local lastPass = 0
local gui: ScreenGui? = nil

local function color(spec: { number }): Color3
	return Color3.fromRGB(spec[1], spec[2], spec[3])
end

local function track(model: Instance)
	if not model:IsA("Model") or idOf[model] then
		return
	end
	nextId += 1
	local id = tostring(nextId)
	idOf[model] = id
	scenes[id] = model
end

local function untrack(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = idOf[model]
	if not id then
		return
	end
	idOf[model] = nil
	scenes[id] = nil
end

local function makeHighlight(): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "PickupHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = Workspace.CurrentCamera
	return highlight
end

-- One from the pool, made only while the pool is under the budget.
local function acquireHighlight(): Highlight?
	local highlight = table.remove(pool)
	if highlight then
		return highlight
	end
	local live = #pool
	for _ in held do
		live += 1
	end
	if live >= PickupScenesConfig.HIGHLIGHT_BUDGET then
		return nil
	end
	return makeHighlight()
end

local function releaseHighlight(id: string)
	local highlight = held[id]
	if not highlight then
		return
	end
	held[id] = nil
	heldSet[id] = nil
	highlight.Enabled = false
	highlight.Adornee = nil
	table.insert(pool, highlight)
end

local function viewpoint(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function pass()
	local from = viewpoint()
	if not from then
		return
	end
	local candidates: { HighlightBudget.Candidate } = {}
	for id, model in scenes do
		local anchor = model.PrimaryPart
		if anchor and model:GetAttribute("Taken") ~= true then
			table.insert(candidates, { id = id, distance = (anchor.Position - from).Magnitude })
		end
	end
	local assignment = HighlightBudget.assign(candidates, PickupScenesConfig.HIGHLIGHT_BUDGET, heldSet, PickupScenesConfig.HIGHLIGHT_SWAP_MARGIN)
	for _, id in assignment.release do
		releaseHighlight(id)
	end
	for _, id in assignment.acquire do
		local model = scenes[id]
		local highlight = if model then acquireHighlight() else nil
		if model and highlight then
			local drop = model:GetAttribute("Kind") == "Drop"
			highlight.OutlineColor = color(if drop then PickupScenesConfig.HIGHLIGHT_OUTLINE_DROP else PickupScenesConfig.HIGHLIGHT_OUTLINE)
			highlight.Adornee = model
			highlight.Enabled = true
			held[id] = highlight
			heldSet[id] = true
		end
	end
end

local function ensureGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "PickupGui"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.DisplayOrder = 6
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

local function toast(text: string, tint: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "PickupToast"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.66)
	label.Size = UDim2.fromOffset(360, 30)
	label.BackgroundTransparency = 1
	label.Font = UiTheme.FONT_BOLD
	label.TextSize = 22
	label.TextColor3 = tint
	label.TextStrokeTransparency = 0.6
	label.Text = text
	label.Parent = ensureGui()
	TweenService:Create(label, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.6),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.4, function()
		label:Destroy()
	end)
end

local function onPickup(kind: any, payload: any, position: any)
	if typeof(kind) ~= "string" or typeof(payload) ~= "string" then
		return
	end
	if kind == "Refused" then
		toast(string.upper(payload), UiTheme.DANGER)
		return
	end
	local config = WeaponsConfig.get(payload)
	local name = if config then string.upper(config.displayName) else string.upper(payload)
	if kind == "Drop" then
		toast("SUPPLY DROP: " .. name, color(PickupScenesConfig.HIGHLIGHT_OUTLINE_DROP))
	else
		toast("PICKED UP " .. name, color(PickupScenesConfig.HIGHLIGHT_OUTLINE))
	end
	UiSfx.rewardTick()
	if typeof(position) == "Vector3" then
		WeaponVfx.pickupBurst(position)
	end
end

function WeaponPickupClient.init()
	for _, model in CollectionService:GetTagged(TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastPass < PickupScenesConfig.HIGHLIGHT_REFRESH then
			return
		end
		lastPass = now
		pass()
	end)

	Remotes.getEvent(Remotes.Event.WeaponPickup).OnClientEvent:Connect(onPickup)
end

-- For the debug overlay and tests in Studio: highlights live right now.
function WeaponPickupClient.liveHighlights(): number
	local count = 0
	for _ in held do
		count += 1
	end
	return count
end

return WeaponPickupClient
