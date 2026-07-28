--!strict

local ProximityPromptService = game:GetService("ProximityPromptService")

local ShopGui = require(script.Parent.Parent.ui.ShopGui)

local VendorInteraction = {}

function VendorInteraction.init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "VendorPrompt" then
			return
		end
		local parent = prompt.Parent
		local vendorId = if parent then parent:GetAttribute("VendorId") else nil
		if typeof(vendorId) == "string" then
			ShopGui.open(vendorId)
		end
	end)
end

return VendorInteraction
