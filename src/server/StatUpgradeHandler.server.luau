--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatUpgradeService = require(script.Parent.StatUpgradeService)

local REMOTES_FOLDER_NAME = "Remotes"
local PURCHASE_REMOTE_NAME = "PurchaseStatUpgrade"
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

local function onPurchaseRequested(player: Player, statName: unknown): ()
	if isRateLimited(player.UserId) then
		return
	end

	if type(statName) ~= "string" then
		return
	end

	StatUpgradeService.TryPurchase(player, statName)
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[StatUpgradeHandler] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local purchaseRemote = remotesFolder:WaitForChild(PURCHASE_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if purchaseRemote == nil or not purchaseRemote:IsA("RemoteEvent") then
	warn(`[StatUpgradeHandler] PurchaseStatUpgrade RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

StatUpgradeService.SetPurchaseRemote(purchaseRemote)
StatUpgradeService.InitCharacterHooks()

purchaseRemote.OnServerEvent:Connect(onPurchaseRequested)
Players.PlayerRemoving:Connect(clearRateLimitState)
