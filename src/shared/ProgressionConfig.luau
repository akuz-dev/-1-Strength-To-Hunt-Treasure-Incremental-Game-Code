--!strict
--!native

local BASE_STRENGTH = 45
local STRENGTH_GROWTH_RATE = 1.0949
local REBIRTH_LEVEL_MULTIPLIER = 25
local REBIRTH_STRENGTH_GAIN_PER_REBIRTH = 0.5
local REBIRTH_CASH_GAIN_PER_REBIRTH = 0.2
local BASE_STRENGTH_GAIN = 1

export type ProgressionConfig = {
	StrengthRequired: (level: number) -> number,
	RebirthLevelGate: (rebirthNumber: number) -> number,
	GetStrengthGainMultiplier: (rebirthCount: number) -> number,
	GetStrengthGainAmount: (rebirthCount: number) -> number,
	GetCashGainMultiplier: (rebirthCount: number) -> number,
	GetNextRebirthGate: (rebirthCount: number) -> number,
	FormatMultiplier: (multiplier: number) -> string,
	BaselineStrength: number,
	BaselineLevel: number,
	BaselineLevelProgress: number,
	BaseStrengthGain: number,
}

local function StrengthRequired(level: number): number
	if level < 2 then
		return 0
	end

	return math.round(BASE_STRENGTH * STRENGTH_GROWTH_RATE ^ (level - 2))
end

local function RebirthLevelGate(rebirthNumber: number): number
	return REBIRTH_LEVEL_MULTIPLIER * rebirthNumber
end

local function GetStrengthGainMultiplier(rebirthCount: number): number
	return 1 + REBIRTH_STRENGTH_GAIN_PER_REBIRTH * rebirthCount
end

local function GetStrengthGainAmount(rebirthCount: number): number
	return math.round(BASE_STRENGTH_GAIN * GetStrengthGainMultiplier(rebirthCount))
end

local function GetCashGainMultiplier(rebirthCount: number): number
	return 1 + REBIRTH_CASH_GAIN_PER_REBIRTH * rebirthCount
end

local function GetNextRebirthGate(rebirthCount: number): number
	return RebirthLevelGate(rebirthCount + 1)
end

local function FormatMultiplier(multiplier: number): string
	local roundedTenths = math.round(multiplier * 10)
	if roundedTenths % 10 == 0 then
		return `x{roundedTenths // 10}`
	end

	return `x{roundedTenths / 10}`
end

local ProgressionConfig: ProgressionConfig = {
	StrengthRequired = StrengthRequired,
	RebirthLevelGate = RebirthLevelGate,
	GetStrengthGainMultiplier = GetStrengthGainMultiplier,
	GetStrengthGainAmount = GetStrengthGainAmount,
	GetCashGainMultiplier = GetCashGainMultiplier,
	GetNextRebirthGate = GetNextRebirthGate,
	FormatMultiplier = FormatMultiplier,
	BaselineStrength = 1,
	BaselineLevel = 1,
	BaselineLevelProgress = 0,
	BaseStrengthGain = BASE_STRENGTH_GAIN,
}

return ProgressionConfig
