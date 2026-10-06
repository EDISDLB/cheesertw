--!strict
--[[
	Kit/Theme — reactive design tokens and accessibility settings for every screen.

	Purpose:          Resolves token names (never hex literals in screens) to Roblox values: colours as live State
	                  (`Theme.color("bg.panel")`) that follow the colour-blind scheme and high-contrast mode,
	                  typography roles (Font + reactive TextSize honouring text scale and the brand minimum rendered
	                  sizes per platform), spacing, radii, strokes, layers, motion timings, team/rarity/currency/
	                  faction/material palettes. Holds the theme settings (scheme, high contrast, text scale, UI scale,
	                  reduced motion, preferred transparency) and fires `Theme.changed` when they change.
	Dependencies:     Kit/State, Kit/Tokens, Core/Signal, Core/Log. `bindEngine` reads GuiService accessibility
	                  properties (ReducedMotionEnabled, PreferredTransparency) at runtime only.
	State:            Module-level Values for each setting (app-global theme), caches of Computed tokens.
	Validation:       Unknown token/role names raise immediately ("Theme: unknown colour token ..."); settings are
	                  validated (scheme names) and clamped (text scale 0.8–1.5, UI scale 0.8–1.2, transparency 0–1).
	Error handling:   Invalid settings raise from Theme.set (callers are settings code, which must pass valid data).
	Performance notes: Each token's State is created once and cached; static tokens are constant Values (no
	                  recomputation). A scheme switch recomputes only team colours; text scale only text sizes.
]]

local State = require("./State")
local Tokens = require("./Tokens")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

type State<T> = State.State<T>

export type ColorToken =
	"bg.abyss"
	| "bg.base"
	| "bg.panel"
	| "bg.raised"
	| "bg.inset"
	| "bg.selected"
	| "bg.scrim"
	| "border.subtle"
	| "border.strong"
	| "border.bevel_hi"
	| "border.bevel_lo"
	| "text.primary"
	| "text.secondary"
	| "text.tertiary"
	| "text.disabled"
	| "text.inverse"
	| "text.brand"
	| "brand.bone"
	| "brand.khaki"
	| "brand.olive"
	| "accent.dusk"
	| "accent.dusk_hi"
	| "accent.dusk_lo"
	| "accent.steel"
	| "state.success"
	| "state.warning"
	| "state.danger"
	| "state.info"
	| "team.ally"
	| "team.enemy"
	| "team.platoon"
	| "team.self"
	| "team.neutral"
	| "team.destroyed"
	| "rarity.common"
	| "rarity.uncommon"
	| "rarity.rare"
	| "rarity.epic"
	| "rarity.legendary"
	| "rarity.prototype"
	| "currency.credits"
	| "currency.bullion"
	| "currency.vehicle_xp"
	| "currency.free_xp"
	| "currency.crew_xp"
	| "currency.campaign_token"
	| "ammo.ap"
	| "ammo.apcr"
	| "ammo.heat"
	| "ammo.he"
	| "ammo.hesh"
	| "ammo.special"
	| "equip.firepower"
	| "equip.survivability"
	| "equip.mobility"
	| "equip.scouting"
	| "grade.improved"
	| "grade.experimental"
	| "cta.top"
	| "cta.bottom"
	| "climate.temperate"
	| "climate.desert"
	| "climate.winter"
	| "climate.urban"
	| "climate.alpine"
	| "ink"

export type TeamRole = "ally" | "enemy" | "platoon" | "self" | "neutral" | "destroyed"
export type Scheme = "default" | "deuteranopia" | "protanopia" | "tritanopia"
export type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary" | "prototype"
export type Currency = "credits" | "bullion" | "vehicle_xp" | "free_xp" | "crew_xp" | "campaign_token"
export type Tone = "neutral" | "success" | "warning" | "danger" | "info"
export type Platform = "pc" | "console" | "phone" | "tablet"
export type TypeRole =
	"display.hero"
	| "h1"
	| "h2"
	| "h3"
	| "h4"
	| "body.l"
	| "body"
	| "body.s"
	| "label"
	| "caption"
	| "num.xl"
	| "num.l"
	| "num.m"
	| "mono"
	| "micro"
	| "button"
	| "button.cta"
	| "button.battle"
	| "tab"
	| "badge"
	| "title.s"
export type MotionToken =
	"instant"
	| "hover"
	| "fast"
	| "base"
	| "slow"
	| "toast"
	| "flourish"
	| "countUp"
	| "tooltipDelay"
	| "longPress"
	| "toastHold"
	| "toastHoldAction"
	| "focusPulse"
export type EasingToken = "standard" | "enter" | "exit" | "linear" | "emphasized"
export type Layer = "Background3D" | "HUD" | "Screens" | "TopBar" | "Modals" | "Toasts" | "Tooltip" | "Debug"
--- Layout family pushed by Kit/Layout: Regular, Compact (phones) or TV (10-ft); selects authored type minimums.
export type LayoutMode = "regular" | "compact" | "tv"

export type Settings = {
	scheme: Scheme,
	highContrast: boolean,
	textScale: number,
	uiScale: number,
	reducedMotion: boolean,
	preferredTransparency: number,
}

export type SettingsPatch = {
	scheme: Scheme?,
	highContrast: boolean?,
	textScale: number?,
	uiScale: number?,
	--- The player's "reduced effects/motion" setting (OR-ed with the engine's ReducedMotionEnabled).
	reducedMotion: boolean?,
}

export type SystemPatch = {
	renderScale: number?,
	platform: Platform?,
	layout: LayoutMode?,
	reducedMotionSystem: boolean?,
	preferredTransparency: number?,
}

export type Snapshot = {
	scheme: Scheme,
	highContrast: boolean,
	textScale: number,
	uiScale: number,
	reducedMotion: boolean,
	preferredTransparency: number,
	renderScale: number,
	platform: Platform,
	layout: LayoutMode,
}

export type TypeSpec = {
	role: TypeRole,
	font: Font,
	size: State<number>,
	baseSize: number,
	lineHeight: number,
	upper: boolean,
	kind: string,
}

export type FactionColors = { name: string, primary: Color3, secondary: Color3, tint: Color3 }
export type Material = { highlight: Color3, base: Color3, shade: Color3 }

local Theme = {}

Theme.SCHEMES = { "default", "deuteranopia", "protanopia", "tritanopia" } :: { Scheme }
Theme.TEXT_SCALE_MIN = 0.8
Theme.TEXT_SCALE_MAX = 1.5
Theme.UI_SCALE_MIN = 0.8
Theme.UI_SCALE_MAX = 1.2

--------------------------------------------------------------------------------
-- Colour parsing
--------------------------------------------------------------------------------

--- Parses "#RRGGBB" or "#RRGGBBAA" into (Color3, transparency) where transparency = 1 - alpha.
function Theme.parseHex(hex: string): (Color3, number)
	local digits = string.match(hex, "^#(%x+)$")
	if digits == nil or (#digits ~= 6 and #digits ~= 8) then
		error(`Theme: invalid colour "{hex}"`, 2)
	end
	local r = tonumber(string.sub(digits, 1, 2), 16) :: number
	local g = tonumber(string.sub(digits, 3, 4), 16) :: number
	local b = tonumber(string.sub(digits, 5, 6), 16) :: number
	local transparency = 0
	if #digits == 8 then
		local a = tonumber(string.sub(digits, 7, 8), 16) :: number
		transparency = 1 - a / 255
	end
	return Color3.fromRGB(r, g, b), transparency
end

local function color3(hex: string): Color3
	local c = Theme.parseHex(hex)
	return c
end

local rawColors: { [string]: string } = table.clone(Tokens.colors :: { [string]: string })
for name, hex in Tokens.extraColors :: { [string]: string } do
	rawColors[name] = hex
end
rawColors["ink"] = Tokens.ink

local function isColorToken(name: string): boolean
	return rawColors[name] ~= nil
end

local TEAM_SCHEME_ROLES = { ally = true, enemy = true, platoon = true, self = true }

--------------------------------------------------------------------------------
-- Settings state
--------------------------------------------------------------------------------

local DEFAULTS: Settings = {
	scheme = "default",
	highContrast = false,
	textScale = 1,
	uiScale = 1,
	reducedMotion = false,
	preferredTransparency = 1,
}

-- String-literal unions widen through generic instantiation in the old solver: annotate + cast.
local schemeValue: State.Value<Scheme> = State.Value(DEFAULTS.scheme) :: any
local highContrastValue = State.Value(DEFAULTS.highContrast)
local textScaleValue = State.Value(DEFAULTS.textScale)
local uiScaleValue = State.Value(DEFAULTS.uiScale)
local reducedMotionUserValue = State.Value(false)
local reducedMotionSystemValue = State.Value(false)
local preferredTransparencyValue = State.Value(1)
local renderScaleValue = State.Value(1)
local platformValue: State.Value<Platform> = State.Value("pc") :: any
local layoutValue: State.Value<LayoutMode> = State.Value("regular") :: any

local reducedMotionComputed = State.Computed(function(): boolean
	return reducedMotionUserValue:get() or reducedMotionSystemValue:get()
end)

--- Read-only reactive views of the settings (bind UI to these; change them with Theme.set / Theme.setSystem).
Theme.state = {
	scheme = State.readonly(schemeValue),
	highContrast = State.readonly(highContrastValue),
	textScale = State.readonly(textScaleValue),
	uiScale = State.readonly(uiScaleValue),
	reducedMotion = reducedMotionComputed,
	preferredTransparency = State.readonly(preferredTransparencyValue),
	renderScale = State.readonly(renderScaleValue),
	platform = State.readonly(platformValue),
	layout = State.readonly(layoutValue),
}

--- Fires (Snapshot) after any setting changes (user or system), once per Theme.set/setSystem call.
Theme.changed = Signal.new() :: Signal.Signal<Snapshot>

function Theme.snapshot(): Snapshot
	return {
		scheme = schemeValue:peek(),
		highContrast = highContrastValue:peek(),
		textScale = textScaleValue:peek(),
		uiScale = uiScaleValue:peek(),
		reducedMotion = reducedMotionComputed:peek(),
		preferredTransparency = preferredTransparencyValue:peek(),
		renderScale = renderScaleValue:peek(),
		platform = platformValue:peek(),
		layout = layoutValue:peek(),
	}
end

local function clamp(value: number, min: number, max: number): number
	if value ~= value then
		return min
	end
	return math.clamp(value, min, max)
end

local function sameSnapshot(a: Snapshot, b: Snapshot): boolean
	for key, value in a :: any do
		if (b :: any)[key] ~= value then
			return false
		end
	end
	return true
end

--- Applies player settings (validated/clamped). Fires Theme.changed once if anything changed.
function Theme.set(patch: SettingsPatch)
	if type(patch) ~= "table" then
		error("Theme.set expects a table", 2)
	end
	if patch.scheme ~= nil and table.find(Theme.SCHEMES, patch.scheme) == nil then
		error(`Theme.set: unknown colour-blind scheme "{tostring(patch.scheme)}"`, 2)
	end
	local before = Theme.snapshot()
	State.batch(function()
		if patch.scheme ~= nil then
			schemeValue:set(patch.scheme)
		end
		if patch.highContrast ~= nil then
			highContrastValue:set(patch.highContrast == true)
		end
		if patch.textScale ~= nil then
			textScaleValue:set(clamp(patch.textScale, Theme.TEXT_SCALE_MIN, Theme.TEXT_SCALE_MAX))
		end
		if patch.uiScale ~= nil then
			uiScaleValue:set(clamp(patch.uiScale, Theme.UI_SCALE_MIN, Theme.UI_SCALE_MAX))
		end
		if patch.reducedMotion ~= nil then
			reducedMotionUserValue:set(patch.reducedMotion == true)
		end
	end)
	local after = Theme.snapshot()
	if not sameSnapshot(before, after) then
		Theme.changed:Fire(after)
	end
end

--- Applies engine/system-derived values (Layout sets renderScale/platform; bindEngine sets the accessibility ones).
function Theme.setSystem(patch: SystemPatch)
	local before = Theme.snapshot()
	State.batch(function()
		if patch.renderScale ~= nil then
			renderScaleValue:set(clamp(patch.renderScale, 0.1, 10))
		end
		if patch.platform ~= nil then
			platformValue:set(patch.platform)
		end
		if patch.layout ~= nil then
			if patch.layout ~= "regular" and patch.layout ~= "compact" and patch.layout ~= "tv" then
				error(`Theme.setSystem: unknown layout "{tostring(patch.layout)}"`, 3)
			end
			layoutValue:set(patch.layout)
		end
		if patch.reducedMotionSystem ~= nil then
			reducedMotionSystemValue:set(patch.reducedMotionSystem == true)
		end
		if patch.preferredTransparency ~= nil then
			preferredTransparencyValue:set(clamp(patch.preferredTransparency, 0, 1))
		end
	end)
	local after = Theme.snapshot()
	if not sameSnapshot(before, after) then
		Theme.changed:Fire(after)
	end
end

--- Restores every setting to its default (tests, gallery "reset").
function Theme.reset()
	Theme.set({
		scheme = DEFAULTS.scheme,
		highContrast = DEFAULTS.highContrast,
		textScale = DEFAULTS.textScale,
		uiScale = DEFAULTS.uiScale,
		reducedMotion = false,
	})
	Theme.setSystem({
		renderScale = 1,
		platform = "pc",
		layout = "regular",
		reducedMotionSystem = false,
		preferredTransparency = 1,
	})
end

--- Follows GuiService.ReducedMotionEnabled / PreferredTransparency. Returns a function that stops listening.
function Theme.bindEngine(): () -> ()
	local GuiService = game:GetService("GuiService")
	local function sync()
		Theme.setSystem({
			reducedMotionSystem = GuiService.ReducedMotionEnabled,
			preferredTransparency = GuiService.PreferredTransparency,
		})
	end
	sync()
	local a = GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(sync)
	local b = GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(sync)
	return function()
		a:Disconnect()
		b:Disconnect()
	end
end

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

local colorCache: { [string]: State<Color3> } = {}
local transparencyCache: { [string]: State<number> } = {}

local function staticColor(name: string): Color3
	local hex = rawColors[name]
	if hex == nil then
		error(`Theme: unknown colour token "{name}"`, 3)
	end
	return color3(hex)
end

--- Pure resolution of a token under explicit settings (used by the State bindings, the gallery and tests).
function Theme.resolveColor(name: string, scheme: Scheme, highContrast: boolean): Color3
	if not isColorToken(name) then
		error(`Theme: unknown colour token "{name}"`, 2)
	end
	if string.sub(name, 1, 5) == "team." then
		local role = string.sub(name, 6)
		if TEAM_SCHEME_ROLES[role] then
			local schemeColors = (Tokens.teamSchemes :: any)[scheme]
			if schemeColors == nil then
				error(`Theme: unknown colour-blind scheme "{scheme}"`, 2)
			end
			return color3(schemeColors[role])
		end
	end
	if highContrast then
		local alias = Tokens.highContrast[name]
		if alias ~= nil then
			return staticColor(alias)
		end
	end
	return staticColor(name)
end

--- Live colour for a token: a State that follows the colour-blind scheme (team.*) and high-contrast mode.
--- Bind it directly: `BackgroundColor3 = Theme.color("bg.panel")`.
function Theme.color(name: ColorToken): State<Color3>
	local cached = colorCache[name]
	if cached ~= nil then
		return cached
	end
	if not isColorToken(name) then
		error(`Theme: unknown colour token "{tostring(name)}"`, 2)
	end
	local isTeam = string.sub(name, 1, 5) == "team." and TEAM_SCHEME_ROLES[string.sub(name, 6)] == true
	local hasContrastAlias = Tokens.highContrast[name] ~= nil
	local state: State<Color3>
	if isTeam or hasContrastAlias then
		state = State.Computed(function(): Color3
			return Theme.resolveColor(name, schemeValue:get(), highContrastValue:get())
		end, { name = `Theme.color({name})` })
	else
		state = State.Value(staticColor(name))
	end
	colorCache[name] = state
	return state
end

--- Current value of a colour token (no binding).
function Theme.peekColor(name: ColorToken): Color3
	return Theme.color(name):peek()
end

--- Token transparency (from an alpha channel such as bg.scrim's "CC"); 0 for opaque tokens. Reactive (HC mode).
function Theme.tokenTransparency(name: ColorToken): State<number>
	local cached = transparencyCache[name]
	if cached ~= nil then
		return cached
	end
	local hex = rawColors[name]
	if hex == nil then
		error(`Theme: unknown colour token "{tostring(name)}"`, 2)
	end
	local _, base = Theme.parseHex(hex)
	local state: State<number>
	if name == "bg.scrim" then
		state = State.Computed(function(): number
			return if highContrastValue:get() then Tokens.highContrastScrimTransparency else base
		end)
	else
		state = State.Value(base)
	end
	transparencyCache[name] = state
	return state
end

--- Live mix of two tokens: `Theme.mix("bg.raised", "state.danger", 0.12)` (12 % danger tint over a raised fill).
function Theme.mix(a: ColorToken, b: ColorToken, t: number): State<Color3>
	local ca, cb = Theme.color(a), Theme.color(b)
	return State.Computed(function(): Color3
		return ca:get():Lerp(cb:get(), t)
	end)
end

--- Background transparency honouring GuiService.PreferredTransparency (Roblox accessibility guidance: multiply).
function Theme.backgroundTransparency(base: number): State<number>
	return State.Computed(function(): number
		return math.clamp(base * preferredTransparencyValue:get(), 0, 1)
	end)
end

function Theme.team(role: TeamRole): State<Color3>
	return Theme.color(("team." .. role) :: any)
end

function Theme.rarity(name: Rarity): State<Color3>
	return Theme.color(("rarity." .. name) :: any)
end

function Theme.currency(name: Currency): State<Color3>
	return Theme.color(("currency." .. name) :: any)
end

--- Tone -> state colour token ("neutral" maps to text.secondary).
function Theme.toneToken(tone: Tone): ColorToken
	if tone == "success" then
		return "state.success"
	elseif tone == "warning" then
		return "state.warning"
	elseif tone == "danger" then
		return "state.danger"
	elseif tone == "info" then
		return "state.info"
	end
	return "text.secondary"
end

function Theme.tone(tone: Tone): State<Color3>
	return Theme.color(Theme.toneToken(tone))
end

--- Team colours of a scheme without touching the current settings (settings preview, gallery).
function Theme.schemeColors(scheme: Scheme): { ally: Color3, enemy: Color3, platoon: Color3, self: Color3 }
	local colors = (Tokens.teamSchemes :: any)[scheme]
	if colors == nil then
		error(`Theme: unknown colour-blind scheme "{tostring(scheme)}"`, 2)
	end
	return {
		ally = color3(colors.ally),
		enemy = color3(colors.enemy),
		platoon = color3(colors.platoon),
		self = color3(colors.self),
	}
end

local factionCache: { [string]: FactionColors } = {}

function Theme.faction(id: string): FactionColors
	local cached = factionCache[id]
	if cached then
		return cached
	end
	local data = (Tokens.factions :: any)[id]
	if data == nil then
		error(`Theme: unknown faction "{id}"`, 2)
	end
	local result: FactionColors = {
		name = data.name,
		primary = color3(data.primary),
		secondary = color3(data.secondary),
		tint = color3(data.tint),
	}
	factionCache[id] = result
	return result
end

local materialCache: { [string]: Material } = {}

--- Icon material (brand-art §3.8): highlight / base / shade Color3s.
function Theme.material(name: string): Material
	local cached = materialCache[name]
	if cached then
		return cached
	end
	local data = (Tokens.materials :: any)[name]
	if data == nil then
		error(`Theme: unknown material "{name}"`, 2)
	end
	local result: Material = {
		highlight = color3(data.highlight),
		base = color3(data.base),
		shade = color3(data.shade),
	}
	materialCache[name] = result
	return result
end

Theme.ink = color3(Tokens.ink)

--------------------------------------------------------------------------------
-- Typography
--------------------------------------------------------------------------------

local fontCache: { [string]: Font } = {}
local sizeCache: { [string]: State<number> } = {}

local function typeSpec(role: string): any
	local spec = (Tokens.typography :: any)[role]
	if spec == nil then
		error(`Theme: unknown type role "{tostring(role)}"`, 3)
	end
	return spec
end

--- Brand font for a role (Oswald display/numerals, Builder Sans UI, Builder Mono tabular).
function Theme.font(role: TypeRole): Font
	local cached = fontCache[role]
	if cached then
		return cached
	end
	local spec = typeSpec(role)
	local family = (Tokens.fontFamilies :: any)[spec.family]
	local font = Font.new(family, (Enum.FontWeight :: any)[spec.weight])
	fontCache[role] = font
	return font
end

--- Pure text-size rule: role size × text scale, raised so the RENDERED size (× renderScale) meets the brand
--- minimum for the platform (brand-art §4.2).
function Theme.computeTextSize(
	baseSize: number,
	kind: string,
	textScale: number,
	renderScale: number,
	platform: Platform
): number
	local scaled = math.floor(baseSize * textScale + 0.5)
	local mins = (Tokens.minTextSize :: any)[platform] or Tokens.minTextSize.pc
	local minRendered = mins[kind] or mins.label
	local minUnscaled = math.ceil(minRendered / math.max(renderScale, 0.01) - 1e-6)
	return math.max(scaled, minUnscaled)
end

--- Pure: the authored size of a role in a layout (the role size, raised to the layout's authored minimum).
function Theme.authoredSize(role: TypeRole, layout: LayoutMode): number
	local spec = typeSpec(role)
	local minimums = (Tokens.layoutTypeMinimums :: any)[layout]
	local minimum = if minimums ~= nil then minimums[role] else nil
	return if minimum ~= nil then math.max(spec.size, minimum) else spec.size
end

--- Reactive TextSize for a role (follows the layout's authored minimums, text scale, UI render scale and platform
--- minimums).
function Theme.textSize(role: TypeRole): State<number>
	local cached = sizeCache[role]
	if cached then
		return cached
	end
	local spec = typeSpec(role)
	local state = State.Computed(function(): number
		return Theme.computeTextSize(
			Theme.authoredSize(role, layoutValue:get()),
			spec.kind,
			textScaleValue:get(),
			renderScaleValue:get(),
			platformValue:get()
		)
	end, { name = `Theme.textSize({role})` })
	sizeCache[role] = state
	return state
end

function Theme.lineHeight(role: TypeRole): number
	return typeSpec(role).lineHeight
end

function Theme.isUpper(role: TypeRole): boolean
	return typeSpec(role).upper == true
end

function Theme.typography(role: TypeRole): TypeSpec
	local spec = typeSpec(role)
	return {
		role = role,
		font = Theme.font(role),
		size = Theme.textSize(role),
		baseSize = spec.size,
		lineHeight = spec.lineHeight,
		upper = spec.upper == true,
		kind = spec.kind,
	}
end

--------------------------------------------------------------------------------
-- Spacing, shapes, layers, motion
--------------------------------------------------------------------------------

--- Spacing step 0..8 -> px (0, 4, 8, 12, 16, 24, 32, 48, 64).
function Theme.space(step: number): number
	local value = (Tokens.spacing :: any)[step]
	if value == nil then
		error(`Theme: spacing step must be 0..8, got {tostring(step)}`, 2)
	end
	return value
end

function Theme.radius(name: "none" | "s" | "m" | "l"): UDim
	local px = (Tokens.radius :: any)[name]
	if px == nil then
		error(`Theme: unknown radius "{tostring(name)}"`, 2)
	end
	return UDim.new(0, px)
end

function Theme.stroke(name: "hairline" | "strong" | "focus" | "emphasis"): number
	local px = (Tokens.stroke :: any)[name]
	if px == nil then
		error(`Theme: unknown stroke "{tostring(name)}"`, 2)
	end
	return px
end

function Theme.chamfer(name: "s" | "m" | "l"): number
	local px = (Tokens.chamfer :: any)[name]
	if px == nil then
		error(`Theme: unknown chamfer "{tostring(name)}"`, 2)
	end
	return px
end

function Theme.layer(name: Layer): number
	local order = (Tokens.layers :: any)[name]
	if order == nil then
		error(`Theme: unknown layer "{tostring(name)}"`, 2)
	end
	return order
end

function Theme.z(name: "base" | "raised" | "content" | "overlay" | "popover" | "top"): number
	local z = (Tokens.z :: any)[name]
	if z == nil then
		error(`Theme: unknown z step "{tostring(name)}"`, 2)
	end
	return z
end

--- Raw duration in seconds (use Kit/Motion, which applies reduced motion).
function Theme.duration(name: MotionToken): number
	local seconds = (Tokens.motion :: any)[name]
	if seconds == nil then
		error(`Theme: unknown motion token "{tostring(name)}"`, 2)
	end
	return seconds
end

function Theme.easing(name: EasingToken): (Enum.EasingStyle, Enum.EasingDirection)
	local pair = (Tokens.easings :: any)[name]
	if pair == nil then
		error(`Theme: unknown easing "{tostring(name)}"`, 2)
	end
	return (Enum.EasingStyle :: any)[pair[1]], (Enum.EasingDirection :: any)[pair[2]]
end

--- Component size tokens (read-only table: buttonHeight, touchMin, icon, ...).
Theme.sizes = Tokens.sizes
Theme.shadow = Tokens.shadow

return Theme
