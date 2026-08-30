--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)

export type InventoryDeltaAction = "Add" | "Remove" | "Sync"

export type InventoryUpdatedPayload = {
	Action: InventoryDeltaAction,
	ItemId: string?,
	Items: { string }?,
}

export type InventoryManager = {
	AddItem: (player: Player, itemId: string) -> boolean,
	RemoveItem: (player: Player, itemId: string) -> boolean,
	GetInventorySnapshot: (player: Player) -> { string }?,
	SendSync: (player: Player) -> (),
	FireClientUpdate: (player: Player, payload: InventoryUpdatedPayload) -> (),
}

local REMOTES_FOLDER_NAME = "Remotes"
local INVENTORY_UPDATED_REMOTE_NAME = "InventoryUpdated"
local REMOTE_WAIT_TIMEOUT = 5

local inventoryUpdatedRemote: RemoteEvent? = nil

local function getOrCreateRemotesFolder(): Folder
	local existingFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existingFolder and existingFolder:IsA("Folder") then
		return existingFolder
	end

	local remotesFolder = Instance.new("Folder")
	remotesFolder.Name = REMOTES_FOLDER_NAME
	remotesFolder.Parent = ReplicatedStorage
	return remotesFolder
end

local function getOrCreateRemoteEvent(parent: Instance, remoteName: string): RemoteEvent
	local existingRemote = parent:FindFirstChild(remoteName)
	if existingRemote and existingRemote:IsA("RemoteEvent") then
		return existingRemote
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = remoteName
	remoteEvent.Parent = parent
	return remoteEvent
end

local function getInventoryUpdatedRemote(): RemoteEvent
	if inventoryUpdatedRemote then
		return inventoryUpdatedRemote
	end

	inventoryUpdatedRemote =
		getOrCreateRemoteEvent(getOrCreateRemotesFolder(), INVENTORY_UPDATED_REMOTE_NAME)
	return inventoryUpdatedRemote
end

local function fireInventoryUpdated(player: Player, payload: InventoryUpdatedPayload): ()
	getInventoryUpdatedRemote():FireClient(player, payload)
end

local function getInventorySnapshot(player: Player): { string }?
	return PlayerDataService.GetInventory(player)
end

local function sendSync(player: Player): ()
	local inventory = getInventorySnapshot(player)
	if inventory == nil then
		return
	end

	fireInventoryUpdated(player, {
		Action = "Sync",
		Items = inventory,
	})
end

local function addItem(player: Player, itemId: string): boolean
	if itemId == "" then
		return false
	end

	if not PlayerDataService.AddInventoryItem(player, itemId) then
		return false
	end

	fireInventoryUpdated(player, {
		Action = "Add",
		ItemId = itemId,
	})
	return true
end

local function removeItem(player: Player, itemId: string): boolean
	if itemId == "" then
		return false
	end

	if not PlayerDataService.RemoveInventoryItem(player, itemId) then
		return false
	end

	fireInventoryUpdated(player, {
		Action = "Remove",
		ItemId = itemId,
	})
	return true
end

local InventoryManager: InventoryManager = {
	AddItem = addItem,
	RemoveItem = removeItem,
	GetInventorySnapshot = getInventorySnapshot,
	SendSync = sendSync,
	FireClientUpdate = fireInventoryUpdated,
}

return InventoryManager
