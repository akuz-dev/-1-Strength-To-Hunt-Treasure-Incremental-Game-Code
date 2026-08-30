--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponShopService = require(script.Parent.WeaponShopService)

local REMOTES_FOLDER_NAME = "Remotes"
local PURCHASE_REMOTE_NAME = "PurchaseWeapon"
local EQUIP_REMOTE_NAME = "EquipWeapon"
local SHOP_UPDATED_REMOTE_NAME = "WeaponShopUpdated"
local REMOTE_WAIT_TIMEOUT = 5
local MAX_REQUESTS_PER_SECOND = 5
local RATE_LIMIT_WINDOW_SECONDS = 1

type RateLimitState = {
	windowStart: number,
	requestCount: number,
}

local rateLimitByUserId: { [number]: RateLimitState } = {}

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

local function clearRateLimitState(player: Player): ()
	rateLimitByUserId[player.UserId] = nil
end

local function onPurchaseRequested(player: Player, weaponId: unknown): ()
	if isRateLimited(player.UserId) then
		return
	end

	if type(weaponId) ~= "string" then
		return
	end

	WeaponShopService.TryPurchase(player, weaponId)
end

local function onEquipRequested(player: Player, weaponId: unknown): ()
	if isRateLimited(player.UserId) then
		return
	end

	if type(weaponId) ~= "string" then
		return
	end

	WeaponShopService.TryEquip(player, weaponId)
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[WeaponShopHandler] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local purchaseRemote = remotesFolder:WaitForChild(PURCHASE_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if purchaseRemote == nil or not purchaseRemote:IsA("RemoteEvent") then
	warn(`[WeaponShopHandler] {PURCHASE_REMOTE_NAME} RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local equipRemote = remotesFolder:WaitForChild(EQUIP_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if equipRemote == nil or not equipRemote:IsA("RemoteEvent") then
	warn(`[WeaponShopHandler] {EQUIP_REMOTE_NAME} RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local shopUpdatedRemote = remotesFolder:WaitForChild(SHOP_UPDATED_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if shopUpdatedRemote == nil or not shopUpdatedRemote:IsA("RemoteEvent") then
	warn(`[WeaponShopHandler] {SHOP_UPDATED_REMOTE_NAME} RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

WeaponShopService.SetShopUpdatedRemote(shopUpdatedRemote)

purchaseRemote.OnServerEvent:Connect(onPurchaseRequested)
equipRemote.OnServerEvent:Connect(onEquipRequested)
Players.PlayerRemoving:Connect(clearRateLimitState)
