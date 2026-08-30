--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleAPI = require(script.Parent.ObstacleAPI)
local PlayerResolver = require(ReplicatedStorage.Shared.PlayerResolver)
local SafeZoneAPI = require(script.Parent.SafeZoneAPI)

local SAFE_ZONE_TAG = "SafeZone"

-- Enter-only debounce: reset fires when touch count goes from 0 to 1 (player entered),
-- not on every limb contact while standing inside the zone.
local function collectSafeZoneParts(taggedInstance: Instance): { BasePart }
	local parts: { BasePart } = {}

	if taggedInstance:IsA("BasePart") then
		table.insert(parts, taggedInstance)
		return parts
	end

	if taggedInstance:IsA("Model") then
		for _, descendant in taggedInstance:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	return parts
end

local function onSafeZoneTouched(_safeZone: BasePart, hitPart: BasePart): ()
	local player = PlayerResolver.getPlayerFromHitPart(hitPart)
	if player == nil then
		return
	end

	local didEnterZone = SafeZoneAPI.incrementTouchCount(player.UserId)
	if didEnterZone then
		task.defer(function()
			ObstacleAPI.resetPlayerObstacles(player)
		end)
	end
end

local function onSafeZoneTouchEnded(_safeZone: BasePart, hitPart: BasePart): ()
	local player = PlayerResolver.getPlayerFromHitPart(hitPart)
	if player == nil then
		return
	end

	SafeZoneAPI.decrementTouchCount(player.UserId)
end

local function registerSafeZonePart(safeZone: BasePart): ()
	safeZone.Touched:Connect(function(touchingPart: BasePart)
		onSafeZoneTouched(safeZone, touchingPart)
	end)

	safeZone.TouchEnded:Connect(function(touchingPart: BasePart)
		onSafeZoneTouchEnded(safeZone, touchingPart)
	end)
end

local function onSafeZoneInstanceAdded(instance: Instance): ()
	for _, safeZonePart in collectSafeZoneParts(instance) do
		registerSafeZonePart(safeZonePart)
	end
end

local function cleanupPlayerSafeZoneState(player: Player): ()
	SafeZoneAPI.clearPlayer(player.UserId)
end

Players.PlayerRemoving:Connect(cleanupPlayerSafeZoneState)

for _, safeZone in CollectionService:GetTagged(SAFE_ZONE_TAG) do
	onSafeZoneInstanceAdded(safeZone)
end

CollectionService:GetInstanceAddedSignal(SAFE_ZONE_TAG):Connect(onSafeZoneInstanceAdded)

--[[ SELF-AUDIT (Section 7):
  SafeZone Touched/TouchEnded:Connect — per registered safe-zone part; script-lifetime. OK.
  Players.PlayerRemoving:Connect — clears SafeZoneAPI touch counts. OK.
  CollectionService SafeZone tag added signal:Connect — script-lifetime singleton. OK.
  Safe-zone enter triggers obstacle reset only; trip bag clears on sell (event-driven). OK.
]]
