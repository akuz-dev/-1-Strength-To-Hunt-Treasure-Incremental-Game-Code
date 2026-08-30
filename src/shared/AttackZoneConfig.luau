--!strict

local StatUpgradeConfig = require(script.Parent.StatUpgradeConfig)

export type AttackZoneConfigModule = {
	GetZoneSize: (rangeLevel: number) -> Vector3,
	GetZoneOffsetCFrame: (rangeLevel: number) -> CFrame,
}

local BASE_ZONE_WIDTH = 4
local BASE_ZONE_HEIGHT = 6

local function GetZoneSize(rangeLevel: number): Vector3
	local depth = StatUpgradeConfig.GetEffectiveRange(rangeLevel)
	return Vector3.new(BASE_ZONE_WIDTH, BASE_ZONE_HEIGHT, depth)
end

local function GetZoneOffsetCFrame(rangeLevel: number): CFrame
	local depth = StatUpgradeConfig.GetEffectiveRange(rangeLevel)
	return CFrame.new(0, 0, -depth / 2)
end

local AttackZoneConfig: AttackZoneConfigModule = {
	GetZoneSize = GetZoneSize,
	GetZoneOffsetCFrame = GetZoneOffsetCFrame,
}

return AttackZoneConfig
