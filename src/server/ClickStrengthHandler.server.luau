--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(ReplicatedStorage.Shared.PlayerDataService)
local WeaponCombatUtil = require(ReplicatedStorage.Shared.WeaponCombatUtil)
local StrengthService = require(script.Parent.StrengthService)

local REMOTES_FOLDER_NAME = "Remotes"
local CLICK_STRENGTH_REMOTE_NAME = "ClickStrength"
local REMOTE_WAIT_TIMEOUT = 5
local MAX_REQUESTS_PER_SECOND = 20
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

local function onClickStrengthRequested(player: Player): ()
	if isRateLimited(player.UserId) then
		return
	end

	local playerData = PlayerDataService.GetData(player)
	if playerData == nil then
		return
	end

	local gain = WeaponCombatUtil.GetClickStrengthGain(playerData)
	StrengthService.AddStrength(player, gain)
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT)
if remotesFolder == nil then
	warn(`[ClickStrengthHandler] Remotes folder not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

local clickStrengthRemote = remotesFolder:WaitForChild(CLICK_STRENGTH_REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
if clickStrengthRemote == nil or not clickStrengthRemote:IsA("RemoteEvent") then
	warn(`[ClickStrengthHandler] ClickStrength RemoteEvent not found within {REMOTE_WAIT_TIMEOUT}s`)
	return
end

clickStrengthRemote.OnServerEvent:Connect(onClickStrengthRequested)
Players.PlayerRemoving:Connect(clearRateLimitState)

--[[
	SELF-AUDIT (Section 7):
	- clickStrengthRemote.OnServerEvent:Connect — script-lifetime singleton; rate-limit
	  table keyed by UserId, cleared on PlayerRemoving. OK.
	- Players.PlayerRemoving:Connect — script-lifetime singleton for rate-limit cleanup. OK.
]]
