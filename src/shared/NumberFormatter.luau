--!strict
--[[
	DISPLAY-ONLY number formatting for client UI labels.

	Per GDD Section 5.9 "Client Number Display": abbreviate at >= 1000 using K/M/B
	suffixes, but never misrepresent the value (1500 -> 1.5K, not 1K). Truncate
	toward zero; do not round.

	Require only from client-side UI scripts (src/client/...). Never require from
	src/server — the server compares and stores raw numbers only.
]]

export type FormatOptions = {
	-- Digits after the decimal point in the abbreviated (or plain) form.
	-- When nil, plain values < 1000 use 0 decimals; abbreviated values auto-pick
	-- the minimum decimals needed for an accurate mantissa (GDD 5.9).
	Decimals: number?,
}

export type NumberFormatter = {
	Format: (value: number, options: FormatOptions?) -> string,
}

-- Standard short-scale suffixes; extend if economy values grow beyond these.
local SUFFIXES: { string } = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
}

local ABBREVIATE_THRESHOLD = 1000
local MAX_AUTO_ABBREVIATED_DECIMALS = 3

local function resolvePlainDecimals(options: FormatOptions?): number
	if options ~= nil and options.Decimals ~= nil then
		return math.max(0, math.floor(options.Decimals))
	end

	return 0
end

-- Truncate toward zero (do not round). `value` must be finite.
local function truncateToDecimals(value: number, decimals: number): number
	local factor = 10 ^ decimals
	if value >= 0 then
		return math.floor(value * factor) / factor
	end

	return math.ceil(value * factor) / factor
end

-- Formats a non-negative finite number that has already been truncated.
local function formatNonNegative(value: number, decimals: number): string
	if decimals <= 0 then
		return tostring(math.floor(value))
	end

	local whole = math.floor(value)
	local fraction = math.floor((value - whole) * (10 ^ decimals) + 1e-9)
	local fractionText = string.format("%0" .. tostring(decimals) .. "d", fraction)
	return `{whole}.{fractionText}`
end

local function resolveAbbreviatedDecimals(
	scaled: number,
	tier: number,
	absolute: number,
	options: FormatOptions?
): number
	if options ~= nil and options.Decimals ~= nil then
		return math.max(0, math.floor(options.Decimals))
	end

	local tierMultiplier = ABBREVIATE_THRESHOLD ^ tier
	local targetAbsolute = math.floor(absolute)

	for decimals = 0, MAX_AUTO_ABBREVIATED_DECIMALS do
		local mantissa = truncateToDecimals(scaled, decimals)
		if math.floor(mantissa * tierMultiplier) == targetAbsolute then
			return decimals
		end
	end

	return 1
end

local function Format(value: number, options: FormatOptions?): string
	if value ~= value or value == math.huge or value == -math.huge then
		return "0"
	end

	local negative = value < 0
	local absolute = math.abs(value)

	if absolute < ABBREVIATE_THRESHOLD then
		local plainDecimals = resolvePlainDecimals(options)
		local plain = formatNonNegative(truncateToDecimals(absolute, plainDecimals), plainDecimals)
		if negative and plain ~= "0" and not string.match(plain, "^0%.0+$") then
			return `-{plain}`
		end
		return plain
	end

	local tier = 0
	local scaled = absolute
	while scaled >= ABBREVIATE_THRESHOLD and tier < #SUFFIXES - 1 do
		scaled /= ABBREVIATE_THRESHOLD
		tier += 1
	end

	local abbreviatedDecimals = resolveAbbreviatedDecimals(scaled, tier, absolute, options)
	local truncatedScaled = truncateToDecimals(scaled, abbreviatedDecimals)
	if truncatedScaled >= ABBREVIATE_THRESHOLD and tier < #SUFFIXES - 1 then
		truncatedScaled = truncateToDecimals(truncatedScaled / ABBREVIATE_THRESHOLD, abbreviatedDecimals)
		tier += 1
	end

	local mantissa = formatNonNegative(truncatedScaled, abbreviatedDecimals)
	local suffix = SUFFIXES[tier + 1]
	if negative then
		return `-{mantissa}{suffix}`
	end

	return `{mantissa}{suffix}`
end

local NumberFormatter: NumberFormatter = {
	Format = Format,
}

return NumberFormatter
