--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryManager = require(script.Parent.InventoryManager)
local TripInventoryManager = require(script.Parent.TripInventoryManager)
local CashUtil = require(ReplicatedStorage.Shared.CashUtil)
local LootConfig = require(ReplicatedStorage.Shared.LootConfig)
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local ProgressionConfig = require(ReplicatedStorage.Shared.ProgressionConfig)

local TutorialService = require(script.Parent.TutorialService)

export type SellService = {
	InitRemotes: () -> (),
	SellFullInventory: (player: Player, valueMultiplier: number) -> boolean,
	GetSellBoostProductId: () -> number,
}

-- TODO: replace with real dev product id once SellBoost is created in the Creator Dashboard.
local SELL_BOOST_DEV_PRODUCT_ID = 0

local REMOTES_FOLDER_NAME = "Remotes"
local SELL_ITEM_REMOTE_NAME = "SellItem"
local SELL_ALL_REMOTE_NAME = "SellAll"
local REMOTE_WAIT_TIMEOUT = 5
local MAX_REQUESTS_PER_SECOND = 5
local RATE_LIMIT_WINDOW_SECONDS = 1
local SELL_BOOST_VALUE_MULTIPLIER = 2

type RateLimitState = {
	windowStart: number,
	requestCount: number,
}

local rateLimitByUserId: { [number]: RateLimitState } = {}
local sellLockedByUserId: { [number]: boolean } = {}
local remotesInitialized = false

local function getCashMultiplier(player: Player): number
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return 1
	end

	local multiplier = ProgressionConfig.GetCashGainMultiplier(playerData.Rebirths)
	-- TODO(GDD 2.4): stack broad gamepass cash multipliers (e.g. 2x Cash) when that system exists.
	return multiplier
end

local function isRateLimited(userId: number): boolean
	local now = os.clock()
	local rateLimitState = rateLimitByUserId[userId]

	if rateLimitState == nil or now - rateLimitState.windowStart >= RATE_LIMIT_WINDOW_SECONDS then
		rateLimitByUserId[userId] = {
			windowStart = now,
			requestCount = 1,
		}
		return false
	end

	if rateLimitState.requestCount >= MAX_REQUESTS_PER_SECOND then
		return true
	end

	rateLimitState.requestCount += 1
	return false
end

local function clearPlayerSellState(player: Player): ()
	local userId = player.UserId
	rateLimitByUserId[userId] = nil
	sellLockedByUserId[userId] = nil
end

local function tryBeginSellLock(userId: number): boolean
	if sellLockedByUserId[userId] then
		return false
	end

	sellLockedByUserId[userId] = true
	return true
end

local function endSellLock(userId: number): ()
	sellLockedByUserId[userId] = nil
end

local function grantCash(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	local newCash = playerData.Cash + amount
	if not PlayerDataService.SetField(player, "Cash", newCash) then
		return false
	end

	player:SetAttribute("Cash", newCash)
	TutorialService.NotifyCashGranted(player, amount)
	return true
end

local function getSellValueForItem(itemId: string, cashMultiplier: number, valueMultiplier: number): number?
	local itemEntry = LootConfig.GetItem(itemId)
	if itemEntry == nil then
		return nil
	end

	return CashUtil.ComputeSellValue(itemEntry.BaseSellValue, cashMultiplier, valueMultiplier)
end

local function playerOwnsItem(player: Player, itemId: string): boolean
	for _, ownedItemId in TripInventoryManager.GetSnapshot(player) do
		if ownedItemId == itemId then
			return true
		end
	end

	local inventory = InventoryManager.GetInventorySnapshot(player)
	if inventory == nil then
		return false
	end

	for _, ownedItemId in inventory do
		if ownedItemId == itemId then
			return true
		end
	end

	return false
end

local function removeSoldItem(player: Player, itemId: string): boolean
	if TripInventoryManager.RemoveItem(player, itemId) then
		return true
	end

	return InventoryManager.RemoveItem(player, itemId)
end

local function getCombinedSellSnapshot(player: Player): { string }
	local combined: { string } = {}

	for _, itemId in TripInventoryManager.GetSnapshot(player) do
		table.insert(combined, itemId)
	end

	local persistedInventory = InventoryManager.GetInventorySnapshot(player)
	if persistedInventory ~= nil then
		for _, itemId in persistedInventory do
			table.insert(combined, itemId)
		end
	end

	return combined
end

local function sellInventoryItems(
	player: Player,
	inventory: { string },
	cashMultiplier: number,
	valueMultiplier: number
): number
	local totalGranted = 0

	for _, itemId in inventory do
		local sellValue = getSellValueForItem(itemId, cashMultiplier, valueMultiplier)
		if sellValue == nil then
			continue
		end

		if removeSoldItem(player, itemId) then
			totalGranted += sellValue
		end
	end

	if totalGranted > 0 then
		grantCash(player, totalGranted)
	end

	return totalGranted
end

local function onSellItemRequested(player: Player, itemId: any): ()
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	if isRateLimited(player.UserId) then
		return
	end

	if not tryBeginSellLock(player.UserId) then
		return
	end

	local released = false
	local function releaseLock(): ()
		if released then
			return
		end
		released = true
		endSellLock(player.UserId)
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		releaseLock()
		return
	end

	if not playerOwnsItem(player, itemId) then
		releaseLock()
		return
	end

	local cashMultiplier = getCashMultiplier(player)
	local sellValue = getSellValueForItem(itemId, cashMultiplier, 1)
	if sellValue == nil then
		releaseLock()
		return
	end

	if removeSoldItem(player, itemId) then
		grantCash(player, sellValue)
	end

	releaseLock()
end

local function onSellAllRequested(player: Player): ()
	if isRateLimited(player.UserId) then
		return
	end

	if not tryBeginSellLock(player.UserId) then
		return
	end

	local released = false
	local function releaseLock(): ()
		if released then
			return
		end
		released = true
		endSellLock(player.UserId)
	end

	local inventory = getCombinedSellSnapshot(player)
	if #inventory == 0 then
		releaseLock()
		return
	end

	local cashMultiplier = getCashMultiplier(player)
	sellInventoryItems(player, inventory, cashMultiplier, 1)
	releaseLock()
end

local function sellFullInventory(player: Player, valueMultiplier: number): boolean
	local inventory = getCombinedSellSnapshot(player)
	if #inventory == 0 then
		return true
	end

	local cashMultiplier = getCashMultiplier(player)
	sellInventoryItems(player, inventory, cashMultiplier, valueMultiplier)
	return true
end

local function initRemotes(): ()
	if remotesInitialized then
		return
	end
	remotesInitialized = true

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	if remotesFolder == nil then
		warn(`[SellService] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
		return
	end

	local sellItemRemote = remotesFolder:WaitForChild(SELL_ITEM_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if sellItemRemote and sellItemRemote:IsA("RemoteEvent") then
		sellItemRemote.OnServerEvent:Connect(onSellItemRequested)
	else
		warn(`[SellService] {SELL_ITEM_REMOTE_NAME} RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	end

	local sellAllRemote = remotesFolder:WaitForChild(SELL_ALL_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	if sellAllRemote and sellAllRemote:IsA("RemoteEvent") then
		sellAllRemote.OnServerEvent:Connect(onSellAllRequested)
	else
		warn(`[SellService] {SELL_ALL_REMOTE_NAME} RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	end

	Players.PlayerRemoving:Connect(clearPlayerSellState)
end

local SellService: SellService = {
	InitRemotes = initRemotes,
	SellFullInventory = sellFullInventory,
	GetSellBoostProductId = function(): number
		return SELL_BOOST_DEV_PRODUCT_ID
	end,
}

return SellService
