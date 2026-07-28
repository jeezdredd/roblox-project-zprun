--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.net.Remotes)
local ProductsConfig = require(ReplicatedStorage.Shared.config.ProductsConfig)
local ProfileManager = require(script.Parent.ProfileManager)

local MonetizationService = {}

type GrantHandler = (Player) -> boolean

local PASS_CACHE_TTL = 120

local grantHandlers: { [string]: GrantHandler } = {}
local passCache: { [Player]: { [string]: { owned: boolean, at: number } } } = {}

local function warnOnce(message: string)
	warn("[TaskForceZ][Monetization] " .. message)
end

function MonetizationService.setGrantHandler(productId: string, handler: GrantHandler)
	grantHandlers[productId] = handler
end

function MonetizationService.promptPurchase(player: Player, productId: string): boolean
	local config = ProductsConfig.getProduct(productId)
	if not config or config.productId <= 0 then
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, config.productId)
	end)
	return ok
end

function MonetizationService.promptPass(player: Player, passId: string): boolean
	local config = ProductsConfig.getPass(passId)
	if not config or config.passId <= 0 then
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, config.passId)
	end)
	return ok
end

function MonetizationService.ownsPass(player: Player, passId: string): boolean
	local config = ProductsConfig.getPass(passId)
	if not config or config.passId <= 0 then
		return false
	end

	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	local cached = cache[passId]
	local now = os.clock()
	if cached and now - cached.at < PASS_CACHE_TTL then
		return cached.owned
	end

	local owned = false
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, config.passId)
		end)
		if ok then
			owned = result == true
			cache[passId] = { owned = owned, at = now }
			return owned
		end
		if attempt < 3 then
			task.wait(0.5 * attempt)
		end
	end

	if cached then
		return cached.owned
	end
	return false
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = ProfileManager.get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptKey = tostring(receiptInfo.PurchaseId)
	if data.PurchaseHistory[receiptKey] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local config = ProductsConfig.productById(receiptInfo.ProductId)
	if not config then
		warnOnce("unknown product id " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = grantHandlers[config.id]
	if not handler then
		warnOnce("no grant handler for " .. config.id)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, player)
	if not ok or not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.PurchaseHistory[receiptKey] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPromptRequest(player: Player, kind: any, id: any)
	if typeof(kind) ~= "string" or typeof(id) ~= "string" then
		return
	end
	if kind == "Product" then
		MonetizationService.promptPurchase(player, id)
	elseif kind == "Pass" then
		MonetizationService.promptPass(player, id)
	end
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt
	Remotes.getEvent(Remotes.Event.PromptPurchase).OnServerEvent:Connect(onPromptRequest)

	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return MonetizationService
