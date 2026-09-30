--!strict

-- The client half of the weapon pickups (docs/gameplay/weapon-pickups.md) and the
-- upgrade station (docs/gameplay/upgrade-station.md): the Highlight outlines that let
-- a scene or a station read through the fog, pooled below Roblox's limit of 31
-- rendered Highlights and handed to the nearest by the pure HighlightBudget; the toast
-- when the server hands over a weapon, upgrades one or refuses; the announcer line and
-- the burst on an upgrade; and the station prompt's quote, written into the prompt's
-- action text locally for this player's weapon. The prompts are the server's.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.config.AssetIds)
local PickupScenesConfig = require(ReplicatedStorage.Shared.config.PickupScenesConfig)
local UpgradeStationConfig = require(ReplicatedStorage.Shared.config.UpgradeStationConfig)
local WeaponsConfig = require(ReplicatedStorage.Shared.config.WeaponsConfig)
local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local HighlightBudget = require(ReplicatedStorage.Shared.util.HighlightBudget)
local UpgradeStationMath = require(ReplicatedStorage.Shared.world.UpgradeStationMath)
local AudioEngine = require(script.Parent.Parent.audio.AudioEngine)
local SfxPlayer = require(script.Parent.SfxPlayer)
local UiSfx = require(script.Parent.UiSfx)
local WeaponVfx = require(script.Parent.WeaponVfx)
local UiTheme = require(script.Parent.Parent.ui.UiTheme)

local WeaponPickupClient = {}

local TAG = "WeaponPickup"
local UPGRADE_PROMPT = "UpgradePrompt"

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
			local kind = model:GetAttribute("Kind")
			highlight.OutlineColor = color(
				if kind == "Drop"
					then PickupScenesConfig.HIGHLIGHT_OUTLINE_DROP
					elseif kind == "Station" then UpgradeStationConfig.HIGHLIGHT_OUTLINE
					else PickupScenesConfig.HIGHLIGHT_OUTLINE
			)
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

-- An announcer line, 2D, when its id is non-zero (the slots are `needed` in the
-- manifest until real licensed files exist; nothing plays until then).
local function announce(key: string)
	local ids = AssetIds.audio.upgrade :: { [string]: number }
	local id = ids[key]
	if typeof(id) ~= "number" or id <= 0 then
		return
	end
	if AudioEngine.enabled() then
		AudioEngine.play({ id = id, class = "UI", volume = UpgradeStationConfig.ANNOUNCER_VOLUME })
		return
	end
	SfxPlayer.play2D(id, UpgradeStationConfig.ANNOUNCER_VOLUME)
end

-- The station prompt's action text is this player's quote: the level bought and its
-- price, or why not, from the attributes the server keeps (WeaponLevel, RunCredits).
local function quotePrompt(prompt: ProximityPrompt)
	local level = player:GetAttribute("WeaponLevel")
	local credits = player:GetAttribute("RunCredits")
	local quote = UpgradeStationMath.quote(WeaponsConfig, if typeof(level) == "number" then level else 1, if typeof(credits) == "number" then credits else 0)
	if quote.ok then
		prompt.ActionText = string.format("Upgrade to L%d · %d CR", quote.level, quote.price)
	elseif quote.price > 0 then
		prompt.ActionText = string.format("L%d · %d CR (short)", quote.level, quote.price)
	else
		prompt.ActionText = "At the top"
	end
end

local function onPickup(kind: any, payload: any, position: any, level: any)
	if typeof(kind) ~= "string" or typeof(payload) ~= "string" then
		return
	end
	if kind == "Refused" then
		toast(string.upper(payload), UiTheme.DANGER)
		if typeof(level) == "number" and level >= WeaponsConfig.MAX_LEVEL then
			announce(UpgradeStationConfig.ANNOUNCER_MAX)
		end
		return
	end
	local config = WeaponsConfig.get(payload)
	local name = if config then string.upper(config.displayName) else string.upper(payload)
	if kind == "Upgrade" then
		toast(string.format("%s UPGRADED TO L%d", name, if typeof(level) == "number" then level else 0), color(UpgradeStationConfig.HIGHLIGHT_OUTLINE))
		UiSfx.rewardTick()
		local lines = UpgradeStationConfig.ANNOUNCER_UPGRADE
		announce(lines[math.random(1, #lines)])
		if typeof(position) == "Vector3" then
			WeaponVfx.pickupBurst(position)
			WeaponVfx.pickupBurst(position + Vector3.new(0, 1.2, 0))
		end
		return
	end
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

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Name == UPGRADE_PROMPT then
			quotePrompt(prompt)
		end
	end)
	for _, attribute in { "WeaponLevel", "RunCredits", "WeaponId" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			for _, model in scenes do
				if model:GetAttribute("Kind") == "Station" then
					local prompt = model:FindFirstChild(UPGRADE_PROMPT, true)
					if prompt and prompt:IsA("ProximityPrompt") then
						quotePrompt(prompt)
					end
				end
			end
		end)
	end
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
