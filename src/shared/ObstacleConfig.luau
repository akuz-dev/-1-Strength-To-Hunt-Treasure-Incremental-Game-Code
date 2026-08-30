--!strict

export type ObstacleTypeEntry = {
	Name: string,
	MaxHP: number,
	Zone: number,
}

export type SegmentPartNames = {
	Blocker: string,
	Visual: string,
}

export type ObstacleConfigModule = {
	SegmentPartNames: SegmentPartNames,
	GetObstacleType: (typeName: string) -> ObstacleTypeEntry?,
}

local OBSTACLE_TYPES: { [string]: ObstacleTypeEntry } = {
	Sand = {
		Name = "Sand",
		MaxHP = 50,
		Zone = 1,
	},
	Sand2 = {
		Name = "Sand2",
		MaxHP = 1000,
		Zone = 2,
	},
	Sand3 = {
		Name = "Sand3",
		MaxHP = 7500,
		Zone = 3,
	},
	Sand4 = {
		Name = "Sand4",
		MaxHP = 15000,
		Zone = 4,
	},
	Sand5 = {
		Name = "Sand5",
		MaxHP = 25000,
		Zone = 5,
	},
	Sand6 = {
		Name = "Sand6",
		MaxHP = 40000,
		Zone = 6,
	},
	Sand7 = {
		Name = "Sand7",
		MaxHP = 60000,
		Zone = 7,
	},
	Sand8 = {
		Name = "Sand8",
		MaxHP = 85000,
		Zone = 8,
	},
	Sand9 = {
		Name = "Sand9",
		MaxHP = 115000,
		Zone = 9,
	},
	Sand10 = {
		Name = "Sand10",
		MaxHP = 150000,
		Zone = 10,
	},
	Sand11 = {
		Name = "Sand11",
		MaxHP = 190000,
		Zone = 11,
	},
	Sand12 = {
		Name = "Sand12",
		MaxHP = 235000,
		Zone = 12,
	},
	Sand13 = {
		Name = "Sand13",
		MaxHP = 285000,
		Zone = 13,
	},
	Sand14 = {
		Name = "Sand14",
		MaxHP = 340000,
		Zone = 14,
	},
	Sand15 = {
		Name = "Sand15",
		MaxHP = 400000,
		Zone = 15,
	},
	Sand16 = {
		Name = "Sand16",
		MaxHP = 465000,
		Zone = 16,
	},
	Sand17 = {
		Name = "Sand17",
		MaxHP = 535000,
		Zone = 17,
	},
}

local function GetObstacleType(typeName: string): ObstacleTypeEntry?
	local directMatch = OBSTACLE_TYPES[typeName]
	if directMatch ~= nil then
		return directMatch
	end

	local normalizedTypeName = string.lower(typeName)
	for key, entry in OBSTACLE_TYPES do
		if string.lower(key) == normalizedTypeName then
			return entry
		end
	end

	return nil
end

local SEGMENT_PART_NAMES: SegmentPartNames = {
	Blocker = "Blocker",
	Visual = "Visual",
}

local ObstacleConfig: ObstacleConfigModule = {
	SegmentPartNames = SEGMENT_PART_NAMES,
	GetObstacleType = GetObstacleType,
}

return ObstacleConfig
