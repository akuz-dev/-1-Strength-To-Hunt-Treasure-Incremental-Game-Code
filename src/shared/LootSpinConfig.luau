--!strict

--[[
	Shared loot spin/bob tuning. LootSpinHandler applies motion client-side via BulkMoveTo
	on PrimaryPart (see GDD Section 4.1).
]]

export type LootSpinConfigModule = {
	SPIN_SPEED_RADIANS_PER_SEC: number,
	BOB_AMPLITUDE_STUDS: number,
	BOB_SPEED_RADIANS_PER_SEC: number,
}

-- TODO(GDD 1.5): loot motion values are placeholder, not yet specced in GDD.
local SPIN_SPEED_RADIANS_PER_SEC = math.rad(90)
local BOB_AMPLITUDE_STUDS = 0.25
local BOB_SPEED_RADIANS_PER_SEC = math.rad(45)

local LootSpinConfig: LootSpinConfigModule = {
	SPIN_SPEED_RADIANS_PER_SEC = SPIN_SPEED_RADIANS_PER_SEC,
	BOB_AMPLITUDE_STUDS = BOB_AMPLITUDE_STUDS,
	BOB_SPEED_RADIANS_PER_SEC = BOB_SPEED_RADIANS_PER_SEC,
}

return LootSpinConfig
