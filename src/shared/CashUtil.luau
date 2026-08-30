--!strict
--!native

--[[
	Shared cash math used by server grants/deductions and client sell previews.

	Cash is always whole numbers: amounts truncate toward zero (floor for non-negative).
	Sell payouts floor after multipliers so rebirth/passive bonuses never grant fractional cash.
]]

export type CashUtil = {
	NormalizeBalance: (amount: number) -> number,
	ComputeSellValue: (baseSellValue: number, cashMultiplier: number, valueMultiplier: number?) -> number,
}

local function NormalizeBalance(amount: number): number
	if amount ~= amount or amount == math.huge or amount == -math.huge then
		return 0
	end

	if amount >= 0 then
		return math.floor(amount)
	end

	return math.ceil(amount)
end

local function ComputeSellValue(baseSellValue: number, cashMultiplier: number, valueMultiplier: number?): number
	local multiplier = valueMultiplier or 1
	if baseSellValue <= 0 or cashMultiplier <= 0 or multiplier <= 0 then
		return 0
	end

	return math.floor(baseSellValue * cashMultiplier * multiplier)
end

local CashUtil: CashUtil = {
	NormalizeBalance = NormalizeBalance,
	ComputeSellValue = ComputeSellValue,
}

return CashUtil
