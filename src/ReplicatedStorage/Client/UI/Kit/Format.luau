--!strict
--[[
	Kit/Format — number and text formatting that follows the brand copy rules (brand-art.md §2).

	Purpose:          One place for UI numbers (ui-ux §1.11): comma thousands ("12,400"), signed deltas with a real
	                  minus sign ("+18 mm", "−0.4 s") and their state tone, compact amounts ("12.4K"), timers (one
	                  decimal under 10 s), cooldowns (whole seconds, ceil), clock times ("12:00"), durations with the
	                  two largest units ("6d 4h"), relative times ("5 min ago", "Yesterday", "5 Oct"), roman tier
	                  numerals and units ("54 km/h").
	Dependencies:     None (pure: times are passed in, never read from the clock).
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
	-- Index into COMPACT_UNITS (largest first); #COMPACT_UNITS + 1 = plain number.
	local index = #COMPACT_UNITS + 1
	for i, unit in COMPACT_UNITS do
		if abs >= unit.value then
			index = i
			break
		end
	end
	while true do
		local unit = COMPACT_UNITS[index]
		if unit == nil then
			-- Plain amounts: 999.5 would round to "1,000"; show "1K" instead.
			if math.floor(abs + 0.5) >= 1000 then
				index -= 1
				continue
			end
			return Format.integer(n)
		end
		local scaled = abs / unit.value
		local decimals = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
		local factor = 10 ^ decimals
		-- Rounding can carry into the next unit (999,950 -> "1,000K"): step up to "1M".
		if math.floor(scaled * factor + 0.5) / factor >= 1000 and index > 1 then
			index -= 1
			continue
		end
		local text = Format.number(scaled, decimals)
		if decimals > 0 then
			text = string.gsub(string.gsub(text, "0+$", ""), "%.$", "")
		end
		return (if n < 0 then Format.MINUS else "") .. text .. unit.suffix
	end
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

--- Cooldown slots: whole seconds, rounded up ("42", "1" until it really reaches zero; ui-ux §1.11).
function Format.cooldown(seconds: number): string
	local s = if isFinite(seconds) and seconds > 0 then seconds else 0
	return string.format("%d", math.ceil(s - 1e-9))
end

local DURATION_UNITS = {
	{ seconds = 86400, suffix = "d" },
	{ seconds = 3600, suffix = "h" },
	{ seconds = 60, suffix = "m" },
	{ seconds = 1, suffix = "s" },
}

--- Durations with the two largest units (ui-ux §1.11): "6d 4h", "4h 12m", "12m 30s", "45 s". Rounds down (a
--- remaining time never overstates); zero units are dropped ("2h", "3d"); < 1 s and invalid -> "0 s".
function Format.duration(seconds: number): string
	local total = if isFinite(seconds) and seconds > 0 then math.floor(seconds + 1e-9) else 0
	if total < 60 then
		return string.format("%d s", total)
	end
	for i, unit in DURATION_UNITS do
		if total >= unit.seconds then
			local major = math.floor(total / unit.seconds)
			local text = string.format("%d%s", major, unit.suffix)
			local nextUnit = DURATION_UNITS[i + 1]
			if nextUnit ~= nil then
				local minor = math.floor((total - major * unit.seconds) / nextUnit.seconds)
				if minor > 0 then
					text ..= string.format(" %d%s", minor, nextUnit.suffix)
				end
			end
			return text
		end
	end
	return "0 s"
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- Civil date (UTC) from unix seconds (Howard Hinnant's days-from-civil inverse; pure, no os.date).
local function civil(unixSeconds: number): (number, number, number)
	local z = math.floor(unixSeconds / 86400) + 719468
	local era = (if z >= 0 then z else z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	return (if m <= 2 then y + 1 else y), m, d
end

--- Date text: "5 Oct", or "5 Oct 2025" when the year differs from `now`'s (both unix seconds, UTC; pass
--- local-offset-adjusted values for local dates).
function Format.date(unixSeconds: number, now: number?): string
	if not isFinite(unixSeconds) then
		return Format.INVALID
	end
	local y, m, d = civil(unixSeconds)
	local text = string.format("%d %s", d, MONTHS[m])
	if now ~= nil and isFinite(now) then
		local nowYear = civil(now)
		if nowYear ~= y then
			text ..= string.format(" %d", y)
		end
	end
	return text
end

--- Relative time (ui-ux §1.11): < 60 s "just now", < 60 min "5 min ago", < 24 h "3 h ago", the previous calendar
--- day "Yesterday", else a date. `then_` and `now` are unix seconds (UTC; offset both for local days). Future
--- timestamps read "just now".
function Format.relative(then_: number, now: number): string
	if not isFinite(then_) or not isFinite(now) then
		return Format.INVALID
	end
	local delta = now - then_
	if delta < 60 then
		return "just now"
	elseif delta < 3600 then
		return string.format("%d min ago", math.floor(delta / 60))
	elseif delta < 86400 then
		return string.format("%d h ago", math.floor(delta / 3600))
	end
	if math.floor(now / 86400) - math.floor(then_ / 86400) == 1 then
		return "Yesterday"
	end
	return Format.date(then_, now)
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
