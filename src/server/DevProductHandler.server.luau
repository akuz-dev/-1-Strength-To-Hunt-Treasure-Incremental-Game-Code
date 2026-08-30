--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DataStoreManagerEvents = require(script.Parent.DataStoreManager)
local PlayerDataService = require(game:GetService("ReplicatedStorage").Shared.PlayerDataService)
local SellService = require(script.Parent.SellService)
local WeaponConfig = require(game:GetService("ReplicatedStorage").Shared.WeaponConfig)
local WeaponShopService = require(script.Parent.WeaponShopService)

local SELL_BOOST_PRODUCT_ID = SellService.GetSellBoostProductId()
local SELL_BOOST_VALUE_MULTIPLIER = 2

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)

	if receiptInfo.ProductId == SELL_BOOST_PRODUCT_ID then
		if SELL_BOOST_PRODUCT_ID <= 0 then
			warn("[DevProductHandler] SellBoost product id is not configured yet")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if PlayerDataService.HasGrantedPurchase(player, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if not SellService.SellFullInventory(player, SELL_BOOST_VALUE_MULTIPLIER) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not PlayerDataService.MarkPurchaseGranted(player, purchaseId) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not DataStoreManagerEvents.SavePlayerData(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local weaponDef = WeaponConfig.GetWeaponByDevProductId(receiptInfo.ProductId)
	if weaponDef ~= nil then
		if PlayerDataService.HasGrantedPurchase(player, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if not WeaponShopService.GrantWeaponFromDevProduct(player, weaponDef.Id) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not PlayerDataService.MarkPurchaseGranted(player, purchaseId) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not DataStoreManagerEvents.SavePlayerData(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	warn(`[DevProductHandler] Unhandled dev product id {receiptInfo.ProductId}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = processReceipt

--[[
	SELF-AUDIT (Section 7):
	- MarketplaceService.ProcessReceipt assignment — single global handler for all dev products (GDD 2.6). OK.
	- No additional :Connect listeners; receipt dispatch is synchronous callback only. OK.
]]
