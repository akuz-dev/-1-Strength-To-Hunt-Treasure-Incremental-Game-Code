--!strict

local SafeZoneAPI = {}

export type SafeZonePresenceCallback = (userId: number) -> ()

-- Ref-counted touch presence: count > 0 means at least one character part is touching a SafeZone.
local playerSafeZoneTouchCounts: { [number]: number } = {}
local onEnteredSafeZoneCallbacks: { SafeZonePresenceCallback } = {}
local onLeftSafeZoneCallbacks: { SafeZonePresenceCallback } = {}

function SafeZoneAPI.registerOnEnteredSafeZone(callback: SafeZonePresenceCallback): ()
	table.insert(onEnteredSafeZoneCallbacks, callback)
end

function SafeZoneAPI.registerOnLeftSafeZone(callback: SafeZonePresenceCallback): ()
	table.insert(onLeftSafeZoneCallbacks, callback)
end

function SafeZoneAPI.incrementTouchCount(userId: number): boolean
	local previousCount = playerSafeZoneTouchCounts[userId] or 0
	local nextCount = previousCount + 1
	playerSafeZoneTouchCounts[userId] = nextCount

	if previousCount == 0 then
		for _, callback in onEnteredSafeZoneCallbacks do
			callback(userId)
		end
	end

	return previousCount == 0
end

function SafeZoneAPI.decrementTouchCount(userId: number): ()
	local currentCount = playerSafeZoneTouchCounts[userId]
	if currentCount == nil then
		return
	end

	local nextCount = currentCount - 1
	if nextCount <= 0 then
		playerSafeZoneTouchCounts[userId] = nil
		for _, callback in onLeftSafeZoneCallbacks do
			callback(userId)
		end
	else
		playerSafeZoneTouchCounts[userId] = nextCount
	end
end

function SafeZoneAPI.isPlayerInSafeZone(userId: number): boolean
	return (playerSafeZoneTouchCounts[userId] or 0) > 0
end

function SafeZoneAPI.clearPlayer(userId: number): ()
	playerSafeZoneTouchCounts[userId] = nil
end

return SafeZoneAPI
