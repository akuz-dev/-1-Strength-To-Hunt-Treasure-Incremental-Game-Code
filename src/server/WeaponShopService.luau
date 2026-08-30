--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local WeaponEquipService = require(script.Parent.WeaponEquipService)
local WeaponLoadoutService = require(script.Parent.WeaponLoadoutService)
local TutorialService = require(script.Parent.TutorialService)

export type WeaponShopAction = "Purchase" | "Equip"

export type WeaponShopDelta = {
	Action: WeaponShopAction,
	WeaponId: string,
	EquippedWeaponId: string,
	OwnedWeaponIds: { string },
	Cash: number,
}

export type WeaponShopServiceModule = {
	TryPurchase: (player: Player, weaponId: string) -> boolean,
	TryEquip: (player: Player, weaponId: string) -> boolean,
	SyncWeaponShopAttributes: (player: Player) -> (),
	GrantWeaponFromDevProduct: (player: Player, weaponId: string) -> boolean,
	SetShopUpdatedRemote: (remote: RemoteEvent) -> (),
}

local REMOTES_FOLDER_NAME = "Remotes"
local SHOP_UPDATED_REMOTE_NAME = "WeaponShopUpdated"
local REMOTE_WAIT_TIMEOUT = 5

local shopUpdatedRemote: RemoteEvent? = nil

local function grantWeaponToPlayer(player: Player, weaponId: string): boolean
	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	if WeaponCombatUtil.PlayerOwnsWeapon(playerData, weaponId) then
		return true
	end

	local ownedWeaponIds = table.clone(playerData.OwnedWeaponIds)
	table.insert(ownedWeaponIds, weaponId)
	playerData.OwnedWeaponIds = ownedWeaponIds
	PlayerDataService.SetData(player, playerData)
	return true
end

local function fireShopDelta(player: Player, action: WeaponShopAction, weaponId: string): ()
	local remote = shopUpdatedRemote
	if remote == nil then
		return
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	local delta: WeaponShopDelta = {
		Action = action,
		WeaponId = weaponId,
		EquippedWeaponId = WeaponCombatUtil.ResolveEquippedWeaponId(playerData),
		OwnedWeaponIds = table.clone(playerData.OwnedWeaponIds),
		Cash = playerData.Cash,
	}
	remote:FireClient(player, delta)
end

local function SyncWeaponShopAttributes(player: Player): ()
	WeaponLoadoutService.SyncPlayerWeaponData(player)

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	player:SetAttribute("Cash", playerData.Cash)
end

local function TryEquip(player: Player, weaponId: string): boolean
	if type(weaponId) ~= "string" then
		return false
	end

	if WeaponConfig.GetWeapon(weaponId) == nil then
		return false
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	if not WeaponCombatUtil.PlayerOwnsWeapon(playerData, weaponId) then
		return false
	end

	if WeaponCombatUtil.ResolveEquippedWeaponId(playerData) == weaponId then
		return false
	end

	if not PlayerDataService.SetField(player, "EquippedWeaponId", weaponId) then
		return false
	end

	WeaponLoadoutService.SyncPlayerWeaponData(player)
	WeaponEquipService.SyncEquippedWeaponVisual(player)
	fireShopDelta(player, "Equip", weaponId)
	return true
end

local function TryPurchase(player: Player, weaponId: string): boolean
	if type(weaponId) ~= "string" then
		return false
	end

	local weaponDef = WeaponConfig.GetWeapon(weaponId)
	if weaponDef == nil or weaponDef.IsStarter then
		return false
	end

	local cost = weaponDef.CashCost
	if type(cost) ~= "number" or cost <= 0 then
		return false
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return false
	end

	if WeaponCombatUtil.PlayerOwnsWeapon(playerData, weaponId) then
		return false
	end

	if playerData.Cash < cost then
		return false
	end

	local previousCash = playerData.Cash
	local newCash = previousCash - cost
	if not PlayerDataService.SetField(player, "Cash", newCash) then
		return false
	end

	if not grantWeaponToPlayer(player, weaponId) then
		PlayerDataService.SetField(player, "Cash", previousCash)
		return false
	end

	TryEquip(player, weaponId)
	SyncWeaponShopAttributes(player)
	fireShopDelta(player, "Purchase", weaponId)
	TutorialService.NotifyWeaponPurchased(player, weaponId)
	return true
end

local function GrantWeaponFromDevProduct(player: Player, weaponId: string): boolean
	if type(weaponId) ~= "string" or WeaponConfig.GetWeapon(weaponId) == nil then
		return false
	end

	if not grantWeaponToPlayer(player, weaponId) then
		return false
	end

	TryEquip(player, weaponId)
	SyncWeaponShopAttributes(player)
	fireShopDelta(player, "Purchase", weaponId)
	return true
end

local function SetShopUpdatedRemote(remote: RemoteEvent): ()
	shopUpdatedRemote = remote
end

local function resolveShopUpdatedRemote(): RemoteEvent?
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotesFolder == nil or not remotesFolder:IsA("Folder") then
		remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
	end
	if remotesFolder == nil or not remotesFolder:IsA("Folder") then
		return nil
	end

	local remote = remotesFolder:FindFirstChild(SHOP_UPDATED_REMOTE_NAME)
	if remote == nil then
		remote = remotesFolder:WaitForChild(SHOP_UPDATED_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
	end
	if remote == nil or not remote:IsA("RemoteEvent") then
		return nil
	end

	return remote
end

task.defer(function()
	if shopUpdatedRemote == nil then
		local remote = resolveShopUpdatedRemote()
		if remote ~= nil then
			shopUpdatedRemote = remote
		end
	end
end)

local WeaponShopService: WeaponShopServiceModule = {
	TryPurchase = TryPurchase,
	TryEquip = TryEquip,
	SyncWeaponShopAttributes = SyncWeaponShopAttributes,
	GrantWeaponFromDevProduct = GrantWeaponFromDevProduct,
	SetShopUpdatedRemote = SetShopUpdatedRemote,
}

return WeaponShopService
