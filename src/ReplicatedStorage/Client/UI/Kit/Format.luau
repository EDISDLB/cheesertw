--!strict
--[[
	Kit/Format — number and text formatting that follows the brand copy rules (brand-art.md §2).

	Purpose:          One place for UI numbers: comma thousands ("12,400"), signed deltas with a real minus sign
	                  ("+18 mm", "−0.4 s") and their state tone, compact amounts ("12.4K"), timers (one decimal under
	                  10 s), clock times ("12:00"), roman tier numerals and units ("54 km/h").
	Dependencies:     None (pure).
	State:            None.
	Validation:       Non-finite numbers format as "—"; roman numerals accept integers 1..3999.
	Error handling:   Invalid roman input raises (programming error); everything else degrades to "—".
	Performance notes: String building only; safe to call from bindings every change (not per frame in hot HUD
	                  paths without caching).
]]

export type Tone = "success" | "danger" | "neutral"
export type Delta = { text: string, tone: Tone, sign: number }
export type DeltaOptions = {
	--- Decimal places (default 0).
	decimals: number?,
	--- Unit appended after a space ("mm", "s", "km/h").
	unit: string?,
	--- When true a negative delta is good (reload time, dispersion): tones flip.
	lowerIsBetter: boolean?,
	--- |delta| below this is treated as zero (default: half of the last shown decimal).
	epsilon: number?,
}

local Format = {}

--- Typographic minus (U+2212) used for negative numbers and deltas, per brand examples ("−0.4 s").
Format.MINUS = "−"
Format.PLUS = "+"
--- Shown for values that cannot be formatted (NaN, ±inf, nil).
Format.INVALID = "—"

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Rounds |n| to `decimals` places, half away from zero; returns the integer and fraction digit strings.
local function roundedParts(n: number, decimals: number): (string, string)
	local factor = 10 ^ decimals
	local scaled = math.floor(math.abs(n) * factor + 0.5)
	local intPart = math.floor(scaled / factor)
	local fracPart = scaled - intPart * factor
	local intText = string.format("%d", intPart)
	local fracText = if decimals > 0 then string.format(`%0{decimals}d`, fracPart) else ""
	return intText, fracText
end

--- Inserts comma thousands separators into a digit string ("1234567" -> "1,234,567").
function Format.groupDigits(digits: string): string
	local out = digits
	while true do
		local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return out
end

local function isZeroText(intText: string, fracText: string): boolean
	return string.match(intText .. fracText, "^0*$") ~= nil
end

--- "12,400" / "−3,000" / "1,234.50" (decimals fixed). Never shows "-0".
function Format.number(n: number, decimals: number?): string
	if not isFinite(n) then
		return Format.INVALID
	end
	local places = decimals or 0
	local intText, fracText = roundedParts(n, places)
	local text = Format.groupDigits(intText)
	if places > 0 then
		text ..= "." .. fracText
	end
	if n < 0 and not isZeroText(intText, fracText) then
		text = Format.MINUS .. text
	end
	return text
end

--- Integer amount with thousands separators (Credits, XP, HP): "12,400".
function Format.integer(n: number): string
	return Format.number(n, 0)
end

--- Always signed: "+1,240", "−0.4", "0" for zero.
function Format.signed(n: number, decimals: number?): string
	if not isFinite(n) then
		return Format.INVALID
	end
	local places = decimals or 0
	local intText, fracText = roundedParts(n, places)
	local body = Format.groupDigits(intText)
	if places > 0 then
		body ..= "." .. fracText
	end
	if isZeroText(intText, fracText) then
		return body
	end
	return (if n < 0 then Format.MINUS else Format.PLUS) .. body
end

--- Signed delta with tone: `Format.delta(-0.4, { decimals = 1, unit = "s", lowerIsBetter = true })` ->
--- { text = "−0.4 s", tone = "success", sign = -1 }.
function Format.delta(value: number, options: DeltaOptions?): Delta
	local opts: DeltaOptions = options or {}
	local decimals = opts.decimals or 0
	if not isFinite(value) then
		return { text = Format.INVALID, tone = "neutral", sign = 0 }
	end
	local epsilon = opts.epsilon or (0.5 * 10 ^ -decimals)
	local sign = if math.abs(value) < epsilon then 0 elseif value > 0 then 1 else -1
	local text = if sign == 0 then Format.number(0, decimals) else Format.signed(value, decimals)
	if opts.unit ~= nil and opts.unit ~= "" then
		text ..= " " .. opts.unit
	end
	local good = if opts.lowerIsBetter then sign < 0 else sign > 0
	local tone: Tone = if sign == 0 then "neutral" elseif good then "success" else "danger"
	return { text = text, tone = tone, sign = sign }
end

local COMPACT_UNITS = {
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },
}

--- Compact amounts for tight spaces: 950 -> "950", 12400 -> "12.4K", 1250000 -> "1.25M", 3e9 -> "3B".
--- Two significant decimals below 10 units, one below 100, none above; trailing zeros trimmed.
function Format.compact(n: number): string
	if not isFinite(n) then
		return Format.INVALID
	end
	local abs = math.abs(n)
	for _, unit in COMPACT_UNITS do
		if abs >= unit.value then
			local scaled = abs / unit.value
			local decimals = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
			local text = Format.number(scaled, decimals)
			if decimals > 0 then
				text = string.gsub(string.gsub(text, "0+$", ""), "%.$", "")
			end
			return (if n < 0 then Format.MINUS else "") .. text .. unit.suffix
		end
	end
	return Format.integer(n)
end

--- 0.125 -> "13%" (decimals default 0). Input is a fraction.
function Format.percent(fraction: number, decimals: number?): string
	if not isFinite(fraction) then
		return Format.INVALID
	end
	return Format.number(fraction * 100, decimals) .. "%"
end

--- Value with a unit: `Format.unit(54, "km/h")` -> "54 km/h"; `Format.unit(0.34, "m", 2)` -> "0.34 m".
function Format.unit(value: number, unit: string, decimals: number?): string
	return Format.number(value, decimals) .. " " .. unit
end

--- Durations for stats/timers: one decimal under 10 s ("7.4 s"), whole seconds above ("12 s").
function Format.seconds(seconds: number): string
	if not isFinite(seconds) then
		return Format.INVALID
	end
	if math.abs(seconds) < 10 then
		return Format.number(seconds, 1) .. " s"
	end
	return Format.number(seconds, 0) .. " s"
end

--- Clock time: 720 -> "12:00", 65 -> "1:05", 3725 -> "1:02:05". Negative/invalid clamps to "0:00".
--- `ceil = true` rounds partial seconds up (countdowns show 0:01 until it really hits zero).
function Format.clock(seconds: number, ceil: boolean?): string
	local s = if isFinite(seconds) and seconds > 0 then seconds else 0
	local total = if ceil then math.ceil(s - 1e-9) else math.floor(s)
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

--- Countdown text: under 10 s shows one decimal ("7.4"), otherwise a clock ("1:05").
function Format.timer(seconds: number): string
	local s = if isFinite(seconds) and seconds > 0 then seconds else 0
	if s < 10 then
		return Format.number(math.floor(s * 10) / 10, 1)
	end
	return Format.clock(s, true)
end

local ROMAN_VALUES = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }
local ROMAN_SYMBOLS = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" }

--- Roman numerals for tiers: 7 -> "VII", 11 -> "XI".
function Format.roman(n: number): string
	if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > 3999 then
		error(`Format.roman expects an integer 1..3999, got {tostring(n)}`, 2)
	end
	local out = {}
	local rest = n
	for i, value in ROMAN_VALUES do
		while rest >= value do
			table.insert(out, ROMAN_SYMBOLS[i])
			rest -= value
		end
	end
	return table.concat(out)
end

--- "Tier VII" (brand: write the roman numeral).
function Format.tier(n: number): string
	return "Tier " .. Format.roman(n)
end

--- ASCII uppercase for display roles (headings, tabs, CTAs). Non-ASCII characters are left unchanged.
function Format.upper(text: string): string
	return string.upper(text)
end

return Format
