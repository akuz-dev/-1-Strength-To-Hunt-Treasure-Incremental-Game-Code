--!strict

-- Field-trip carry is session-only (not persisted). Trip loot stays in the bag until sold;
-- on disconnect, unsold trip loot transfers to persisted sell Inventory for next session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryManager = require(script.Parent.InventoryManager)
local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local StatUpgradeConfig = require(ReplicatedStorage.Shared.StatUpgradeConfig)

export type TripInventoryManagerModule = {
	CanAddItem: (player: Player) -> boolean,
	AddItem: (player: Player, itemId: string) -> boolean,
	RemoveItem: (player: Player, itemId: string) -> boolean,
	GetSnapshot: (player: Player) -> { string },
	Clear: (player: Player) -> (),
	TransferToSellInventory: (player: Player) -> (),
}

local tripInventoryByUserId: { [number]: { string } } = {}

local function getMaxCapacity(player: Player): number
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return 2
	end

	return StatUpgradeConfig.GetEffectiveCapacity(playerData.StatLevels.Capacity)
end

local function syncTripCarryCount(player: Player): ()
	local tripInventory = tripInventoryByUserId[player.UserId]
	local count = if tripInventory then #tripInventory else 0
	player:SetAttribute("TripCarryCount", count)
end

local function getOrCreateTripInventory(userId: number): { string }
	local existing = tripInventoryByUserId[userId]
	if existing == nil then
		existing = {}
		tripInventoryByUserId[userId] = existing
	end

	return existing
end

local function canAddItem(player: Player): boolean
	if PlayerDataService.GetData(player) == nil then
		return false
	end

	local tripInventory = tripInventoryByUserId[player.UserId]
	local count = if tripInventory then #tripInventory else 0
	return count < getMaxCapacity(player)
end

local function addItem(player: Player, itemId: string): boolean
	if itemId == "" then
		return false
	end

	if not canAddItem(player) then
		return false
	end

	local tripInventory = getOrCreateTripInventory(player.UserId)
	table.insert(tripInventory, itemId)
	syncTripCarryCount(player)
	InventoryManager.FireClientUpdate(player, {
		Action = "Add",
		ItemId = itemId,
	})
	return true
end

local function removeItem(player: Player, itemId: string): boolean
	if itemId == "" then
		return false
	end

	local tripInventory = tripInventoryByUserId[player.UserId]
	if tripInventory == nil then
		return false
	end

	for index, ownedItemId in tripInventory do
		if ownedItemId == itemId then
			table.remove(tripInventory, index)
			syncTripCarryCount(player)
			InventoryManager.FireClientUpdate(player, {
				Action = "Remove",
				ItemId = itemId,
			})
			return true
		end
	end

	return false
end

local function getSnapshot(player: Player): { string }
	local tripInventory = tripInventoryByUserId[player.UserId]
	if tripInventory == nil then
		return {}
	end

	return table.clone(tripInventory)
end

local function clear(player: Player): ()
	tripInventoryByUserId[player.UserId] = nil
	syncTripCarryCount(player)
end

local function transferToSellInventory(player: Player): ()
	local tripInventory = tripInventoryByUserId[player.UserId]
	if tripInventory == nil or #tripInventory == 0 then
		syncTripCarryCount(player)
		return
	end

	local itemsToTransfer = table.clone(tripInventory)
	for _, itemId in itemsToTransfer do
		if not InventoryManager.AddItem(player, itemId) then
			warn(`[TripInventoryManager] Failed to transfer {itemId} to sell inventory for {player.Name}`)
		end
	end

	clear(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	transferToSellInventory(player)
end)

local TripInventoryManager: TripInventoryManagerModule = {
	CanAddItem = canAddItem,
	AddItem = addItem,
	RemoveItem = removeItem,
	GetSnapshot = getSnapshot,
	Clear = clear,
	TransferToSellInventory = transferToSellInventory,
}

return TripInventoryManager

--[[ SELF-AUDIT (Section 7):
  Players.PlayerRemoving:Connect — permanent game-lifetime listener; transferToSellInventory
  runs before session table entry is orphaned. OK.
  TripCarryCount attribute updates on add/clear/transfer only; no polling loops. OK. ]]
