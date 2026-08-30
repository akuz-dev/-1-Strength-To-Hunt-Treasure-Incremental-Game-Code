--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthService = require(script.Parent.RebirthService)

local REMOTES_FOLDER_NAME = "Remotes"
local REBIRTH_REMOTE_NAME = "Rebirth"
local REMOTE_WAIT_TIMEOUT = 5
local MAX_REQUESTS_PER_SECOND = 2
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

local function onRebirthRequested(player: Player): ()
	if isRateLimited(player.UserId) then
		return
	end

	RebirthService.PerformRebirth(player)
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[RebirthHandler] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local rebirthRemote = remotesFolder:WaitForChild(REBIRTH_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if rebirthRemote == nil or not rebirthRemote:IsA("RemoteEvent") then
	warn(`[RebirthHandler] Rebirth RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

rebirthRemote.OnServerEvent:Connect(onRebirthRequested)
Players.PlayerRemoving:Connect(clearRateLimitState)
