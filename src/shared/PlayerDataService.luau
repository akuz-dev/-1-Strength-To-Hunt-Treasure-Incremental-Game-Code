--!strict

local RunService = game:GetService("RunService")

local CashUtil = require(script.Parent.CashUtil)
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)
local StatUpgradeConfig = require(script.Parent.StatUpgradeConfig)

export type InventoryItemId = PlayerDataSchema.InventoryItemId
export type PlayerData = PlayerDataSchema.PlayerData

export type PlayerDataKey =
	"Strength"
	| "Level"
	| "LevelProgress"
	| "Cash"
	| "Rebirths"
	| "RangeLevel"
	| "EquippedWeaponId"

export type PlayerDataValue = number | string?

export type PlayerDataService = {
	GetData: (player: Player) -> PlayerData?,
	SetData: (player: Player, data: PlayerData) -> (),
	SetField: (player: Player, key: PlayerDataKey, value: PlayerDataValue) -> boolean,
	SetStatLevel: (player: Player, statName: string, level: number) -> boolean,
	GetInventory: (player: Player) -> { InventoryItemId }?,
	AddInventoryItem: (player: Player, itemId: InventoryItemId) -> boolean,
	RemoveInventoryItem: (player: Player, itemId: InventoryItemId) -> boolean,
	ClearInventory: (player: Player) -> boolean,
	MarkPurchaseGranted: (player: Player, purchaseId: string) -> boolean,
	HasGrantedPurchase: (player: Player, purchaseId: string) -> boolean,
	ClearData: (player: Player) -> (),
}

local playerDataByUserId: { [number]: PlayerData } = {}

local function assertServer(functionName: string): ()
	if not RunService:IsServer() then
		error(`{functionName} is server-only`, 2)
	end
end

local function cloneInventory(inventory: { InventoryItemId }): { InventoryItemId }
	return table.clone(inventory)
end

local function clonePlayerData(data: PlayerData): PlayerData
	local cloned = table.clone(data)
	cloned.StatLevels = table.clone(data.StatLevels)
	cloned.OwnedWeaponIds = table.clone(data.OwnedWeaponIds)
	cloned.OwnedAuraIds = table.clone(data.OwnedAuraIds)
	cloned.OwnedPetIds = table.clone(data.OwnedPetIds)
	cloned.Inventory = cloneInventory(data.Inventory)
	cloned.GrantedPurchaseIds = table.clone(data.GrantedPurchaseIds)
	return cloned
end

local function GetData(player: Player): PlayerData?
	assertServer("PlayerDataService.GetData")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return nil
	end

	return clonePlayerData(data)
end

local function SetData(player: Player, data: PlayerData): ()
	assertServer("PlayerDataService.SetData")
	local cloned = clonePlayerData(data)
	cloned.Cash = CashUtil.NormalizeBalance(cloned.Cash)
	playerDataByUserId[player.UserId] = cloned
end

local function SetStatLevel(player: Player, statName: string, level: number): boolean
	assertServer("PlayerDataService.SetStatLevel")

	if not StatUpgradeConfig.IsValidStatName(statName) then
		return false
	end
	if type(level) ~= "number" or level < 0 or level ~= level then
		return false
	end

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	if statName == "Range" then
		data.StatLevels.Range = level
	elseif statName == "Agility" then
		data.StatLevels.Agility = level
	elseif statName == "Capacity" then
		data.StatLevels.Capacity = level
	elseif statName == "WalkSpeed" then
		data.StatLevels.WalkSpeed = level
	else
		return false
	end

	return true
end

local function SetField(player: Player, key: PlayerDataKey, value: PlayerDataValue): boolean
	assertServer("PlayerDataService.SetField")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	if key == "Strength" then
		data.Strength = value :: number
	elseif key == "Level" then
		data.Level = value :: number
	elseif key == "LevelProgress" then
		data.LevelProgress = value :: number
	elseif key == "Cash" then
		data.Cash = CashUtil.NormalizeBalance(value :: number)
	elseif key == "Rebirths" then
		data.Rebirths = value :: number
	elseif key == "RangeLevel" then
		return SetStatLevel(player, "Range", value :: number)
	elseif key == "EquippedWeaponId" then
		data.EquippedWeaponId = value :: string?
	end

	return true
end

local function GetInventory(player: Player): { InventoryItemId }?
	assertServer("PlayerDataService.GetInventory")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return nil
	end

	return cloneInventory(data.Inventory)
end

local function AddInventoryItem(player: Player, itemId: InventoryItemId): boolean
	assertServer("PlayerDataService.AddInventoryItem")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	table.insert(data.Inventory, itemId)
	return true
end

local function RemoveInventoryItem(player: Player, itemId: InventoryItemId): boolean
	assertServer("PlayerDataService.RemoveInventoryItem")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	for index, ownedItemId in data.Inventory do
		if ownedItemId == itemId then
			table.remove(data.Inventory, index)
			return true
		end
	end

	return false
end

local function ClearInventory(player: Player): boolean
	assertServer("PlayerDataService.ClearInventory")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	table.clear(data.Inventory)
	return true
end

local function MarkPurchaseGranted(player: Player, purchaseId: string): boolean
	assertServer("PlayerDataService.MarkPurchaseGranted")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	data.GrantedPurchaseIds[purchaseId] = true
	return true
end

local function HasGrantedPurchase(player: Player, purchaseId: string): boolean
	assertServer("PlayerDataService.HasGrantedPurchase")

	local data = playerDataByUserId[player.UserId]
	if data == nil then
		return false
	end

	return data.GrantedPurchaseIds[purchaseId] == true
end

local function ClearData(player: Player): ()
	assertServer("PlayerDataService.ClearData")
	playerDataByUserId[player.UserId] = nil
end

local PlayerDataService: PlayerDataService = {
	GetData = GetData,
	SetData = SetData,
	SetField = SetField,
	SetStatLevel = SetStatLevel,
	GetInventory = GetInventory,
	AddInventoryItem = AddInventoryItem,
	RemoveInventoryItem = RemoveInventoryItem,
	ClearInventory = ClearInventory,
	MarkPurchaseGranted = MarkPurchaseGranted,
	HasGrantedPurchase = HasGrantedPurchase,
	ClearData = ClearData,
}

return PlayerDataService
