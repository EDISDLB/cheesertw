local HttpService = game:GetService("HttpService")

local Config = require(script.Parent:WaitForChild("SurvivalConfig"))

local HUDSettings = {}

HUDSettings.StatusStyles = { "Circles", "Bars", "Squares" }
HUDSettings.SpeedometerStyles = { "Round", "Digital" }
HUDSettings.Layouts = { "Vertical", "Horizontal" }
HUDSettings.ScaleMin, HUDSettings.ScaleMax = 0.5, 2
HUDSettings.ThicknessMin, HUDSettings.ThicknessMax = 2, 12

-- Skaičius ribose
local function number(value, min, max, fallback)
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, min, max)
end

-- Leistinas pasirinkimas
local function choice(value, allowed, fallback)
	if type(value) == "string" and table.find(allowed, value) then
		return value
	end
	return fallback
end

-- Vieta ekrane
local function position(value, fallback)
	if type(value) ~= "table" then
		return table.clone(fallback)
	end
	return {
		number(value[1], 0, 1, fallback[1]),
		number(value[2], -4000, 4000, fallback[2]),
		number(value[3], 0, 1, fallback[3]),
		number(value[4], -4000, 4000, fallback[4]),
	}
end

-- Sutvarko nustatymus
function HUDSettings.sanitize(raw)
	local defaults = Config.DefaultLayout
	raw = if type(raw) == "table" then raw else {}
	local status = if type(raw.Status) == "table" then raw.Status else {}
	local speedometer = if type(raw.Speedometer) == "table" then raw.Speedometer else {}
	local info = if type(raw.Info) == "table" then raw.Info else {}

	return {
		Status = {
			Style = choice(status.Style, HUDSettings.StatusStyles, defaults.Status.Style),
			Layout = choice(status.Layout, HUDSettings.Layouts, defaults.Status.Layout),
			Scale = number(status.Scale, HUDSettings.ScaleMin, HUDSettings.ScaleMax, defaults.Status.Scale),
			Thickness = math.round(number(status.Thickness, HUDSettings.ThicknessMin, HUDSettings.ThicknessMax, defaults.Status.Thickness)),
			Position = position(status.Position, defaults.Status.Position),
		},
		Speedometer = {
			Style = choice(speedometer.Style, HUDSettings.SpeedometerStyles, defaults.Speedometer.Style),
			Scale = number(speedometer.Scale, HUDSettings.ScaleMin, HUDSettings.ScaleMax, defaults.Speedometer.Scale),
			Position = position(speedometer.Position, defaults.Speedometer.Position),
		},
		Info = {
			Visible = if type(info.Visible) == "boolean" then info.Visible else defaults.Info.Visible,
			Scale = number(info.Scale, HUDSettings.ScaleMin, HUDSettings.ScaleMax, defaults.Info.Scale),
			Position = position(info.Position, defaults.Info.Position),
		},
	}
end

-- Numatyti nustatymai
function HUDSettings.defaults()
	return HUDSettings.sanitize({})
end

-- Iš teksto
function HUDSettings.decode(json)
	if type(json) ~= "string" or #json > 3000 then
		return HUDSettings.defaults()
	end
	local ok, raw = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	return HUDSettings.sanitize(if ok then raw else nil)
end

-- Į tekstą
function HUDSettings.encode(settings)
	return HttpService:JSONEncode(HUDSettings.sanitize(settings))
end

return HUDSettings
