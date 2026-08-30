--!strict
--!native

export type CompoundingStatDef = {
	BaseCost: number,
	Rate: number,
	DevProductId: number,
	EffectType: "compounding",
	EffectRate: number,
}

export type FlatStatDef = {
	BaseCost: number,
	Rate: number,
	DevProductId: number,
	EffectType: "flat",
	EffectPerLevel: number,
}

export type StatDef = CompoundingStatDef | FlatStatDef

export type StatName = "Agility" | "Range" | "WalkSpeed" | "Capacity"

export type StatUpgradeConfigModule = {
	Stats: { [string]: StatDef },
	IsValidStatName: (statName: string) -> boolean,
	GetCost: (statName: string, level: number) -> number?,
	GetEffect: (statName: string, level: number) -> number?,
	GetEffectiveRange: (rangeLevel: number) -> number,
	GetEffectiveCapacity: (capacityLevel: number) -> number,
	GetEffectiveWalkSpeed: (walkSpeedLevel: number) -> number,
	GetDamageTickInterval: (agilityLevel: number) -> number,
}

local BASE_DAMAGE_RADIUS = 3
local BASE_CARRY_CAPACITY = 2
local BASE_WALK_SPEED = 16
local BASE_DAMAGE_TICK_INTERVAL = 0.5

local Stats: { [string]: StatDef } = {
	Agility = {
		BaseCost = 15000,
		Rate = 2.21,
		DevProductId = 0,
		EffectType = "compounding",
		EffectRate = 1.10,
	},
	Range = {
		BaseCost = 6000,
		Rate = 2.19,
		DevProductId = 0,
		EffectType = "compounding",
		EffectRate = 1.02,
	},
	WalkSpeed = {
		BaseCost = 10000,
		Rate = 2.28,
		DevProductId = 0,
		EffectType = "flat",
		EffectPerLevel = 1,
	},
	Capacity = {
		BaseCost = 130000,
		Rate = 4.51,
		DevProductId = 0,
		EffectType = "flat",
		EffectPerLevel = 1,
	},
}

local function IsValidStatName(statName: string): boolean
	return Stats[statName] ~= nil
end

local function GetCost(statName: string, level: number): number?
	local def = Stats[statName]
	if def == nil then
		return nil
	end
	if level < 1 then
		return nil
	end

	return math.round(def.BaseCost * def.Rate ^ (level - 1))
end

local function GetEffect(statName: string, level: number): number?
	local def = Stats[statName]
	if def == nil then
		return nil
	end

	if def.EffectType == "compounding" then
		return def.EffectRate ^ level
	end

	return def.EffectPerLevel * level
end

local function GetEffectiveRange(rangeLevel: number): number
	local effect = GetEffect("Range", rangeLevel)
	if effect == nil then
		return BASE_DAMAGE_RADIUS
	end
	return BASE_DAMAGE_RADIUS * effect
end

local function GetEffectiveCapacity(capacityLevel: number): number
	local effect = GetEffect("Capacity", capacityLevel)
	if effect == nil then
		return BASE_CARRY_CAPACITY
	end
	return BASE_CARRY_CAPACITY + effect
end

local function GetEffectiveWalkSpeed(walkSpeedLevel: number): number
	local effect = GetEffect("WalkSpeed", walkSpeedLevel)
	if effect == nil then
		return BASE_WALK_SPEED
	end
	return BASE_WALK_SPEED + effect
end

local function GetDamageTickInterval(agilityLevel: number): number
	local effect = GetEffect("Agility", agilityLevel)
	if effect == nil or effect <= 0 then
		return BASE_DAMAGE_TICK_INTERVAL
	end
	return BASE_DAMAGE_TICK_INTERVAL / effect
end

local StatUpgradeConfig: StatUpgradeConfigModule = {
	Stats = Stats,
	IsValidStatName = IsValidStatName,
	GetCost = GetCost,
	GetEffect = GetEffect,
	GetEffectiveRange = GetEffectiveRange,
	GetEffectiveCapacity = GetEffectiveCapacity,
	GetEffectiveWalkSpeed = GetEffectiveWalkSpeed,
	GetDamageTickInterval = GetDamageTickInterval,
}

return StatUpgradeConfig
