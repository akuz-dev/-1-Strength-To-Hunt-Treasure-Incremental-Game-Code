--!strict

--[[
	Distance cutoff for client loot presentation (GDD Section 4.1):
	spin, VFX, and nametag Billboards within this radius of the local character.
]]

export type LootPresentationConfigModule = {
	PRESENTATION_DISTANCE_STUDS: number,
	MAX_VISIBLE_DISTANCE_STUDS: number,
	isWithinPresentationDistance: (distanceStuds: number?) -> boolean,
}

local PRESENTATION_DISTANCE_STUDS = 256

-- BillboardGui.MaxDistance is measured from the camera, not the character, so it must not be
-- set to PRESENTATION_DISTANCE_STUDS itself -- that would double-gate nametags (camera distance
-- AND character distance) and make them cut off sooner/later than LootSpinHandler's spin/bob,
-- which has no engine-level distance cutoff at all. Kept generously above the character-distance
-- cutoff so it never becomes the limiting factor; LootNametagHandler's Enabled toggle (character
-- distance, same PRESENTATION_DISTANCE_STUDS check as spin) is the real cutoff.
local MAX_VISIBLE_DISTANCE_STUDS = PRESENTATION_DISTANCE_STUDS * 4

local function isWithinPresentationDistance(distanceStuds: number?): boolean
	if distanceStuds == nil then
		return true
	end

	return distanceStuds <= PRESENTATION_DISTANCE_STUDS
end

local LootPresentationConfig: LootPresentationConfigModule = {
	PRESENTATION_DISTANCE_STUDS = PRESENTATION_DISTANCE_STUDS,
	MAX_VISIBLE_DISTANCE_STUDS = MAX_VISIBLE_DISTANCE_STUDS,
	isWithinPresentationDistance = isWithinPresentationDistance,
}

return LootPresentationConfig
