--!strict
--[[
	Kit/Tokens — design tokens as plain Luau data (the single token source for Theme).

	Purpose:          Brand colours mirrored 1:1 from assets/brand/tokens.json (block between the GENERATED markers),
	                  plus the brand-guide tokens that tokens.json does not carry: typography roles (brand-art §4.1),
	                  minimum text sizes (§4.2), spacing (research 06 A2, 8 px grid), radii/strokes/chamfers (§6.4,
	                  §8.2), the one elevation shadow (§8.2), ScreenGui layers (research 09 R2), motion (§8.1, 06 A6),
	                  component sizes (§8.3, §4.2) and the high-contrast aliases (kit choice, palette-only).
	Dependencies:     Core/Freeze.
	State:            Constant tables (deep-frozen on return).
	Validation:       tests/Unit/.../Kit/Theme.spec.luau asserts the GENERATED block equals tokens.json exactly.
	Error handling:   N/A.
	Performance notes: Read once by Theme at require time.

	Regenerating: the GENERATED block is produced from assets/brand/tokens.json by the snippet in
	docs/systems/ui-kit.md §Tokens ("python3 - <<'EOF' ... EOF"). Never hand-edit values inside the markers; the
	Theme spec fails when they drift from tokens.json. Brand changes go through tools/art/hdart/tokens.py first.
]]

local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")

local Tokens = {
	-- BEGIN GENERATED (assets/brand/tokens.json) --
	colors = {
		["bg.abyss"] = "#0A0D10",
		["bg.base"] = "#0F1418",
		["bg.panel"] = "#151C21",
		["bg.raised"] = "#1C252C",
		["bg.inset"] = "#0C1013",
		["bg.selected"] = "#26323B",
		["bg.scrim"] = "#0A0D10CC",
		["border.subtle"] = "#25303A",
		["border.strong"] = "#3A4855",
		["border.bevel_hi"] = "#56687A",
		["border.bevel_lo"] = "#070A0C",
		["text.primary"] = "#EAEFF2",
		["text.secondary"] = "#A8B5C0",
		["text.tertiary"] = "#76838F",
		["text.disabled"] = "#4B5661",
		["text.inverse"] = "#0C1013",
		["text.brand"] = "#E9DFC6",
		["brand.bone"] = "#E9DFC6",
		["brand.khaki"] = "#B9A77C",
		["brand.olive"] = "#5E6640",
		["accent.dusk"] = "#FF7A2F",
		["accent.dusk_hi"] = "#FFA066",
		["accent.dusk_lo"] = "#C9541A",
		["accent.steel"] = "#8FA3B5",
		["state.success"] = "#3FCB7A",
		["state.warning"] = "#F2C230",
		["state.danger"] = "#EF4747",
		["state.info"] = "#4AA8F0",
		["team.ally"] = "#47D16C",
		["team.enemy"] = "#F0443A",
		["team.platoon"] = "#FFD23F",
		["team.self"] = "#F4F7F9",
		["team.neutral"] = "#B3BDC6",
		["team.destroyed"] = "#5D666E",
		["rarity.common"] = "#A9B3BC",
		["rarity.uncommon"] = "#62C155",
		["rarity.rare"] = "#3E9BFF",
		["rarity.epic"] = "#A970FF",
		["rarity.legendary"] = "#FFB13B",
		["rarity.prototype"] = "#FF5A7A",
		["currency.credits"] = "#E0955A",
		["currency.bullion"] = "#F4C653",
		["currency.vehicle_xp"] = "#5BB1F5",
		["currency.free_xp"] = "#B08CFF",
		["currency.crew_xp"] = "#3FD0BE",
		["currency.campaign_token"] = "#EC6A93",
		["ammo.ap"] = "#F28C38",
		["ammo.apcr"] = "#86CDF5",
		["ammo.heat"] = "#EC4D82",
		["ammo.he"] = "#FFC23D",
		["ammo.hesh"] = "#9AA35E",
		["ammo.special"] = "#F0BD45",
		["equip.firepower"] = "#E0583A",
		["equip.survivability"] = "#4A86C8",
		["equip.mobility"] = "#3DAA6E",
		["equip.scouting"] = "#E9C03A",
		["grade.improved"] = "#C6CED6",
		["grade.experimental"] = "#FF8A3D",
	},
	teamSchemes = {
		default = {
			["ally"] = "#47D16C",
			["enemy"] = "#F0443A",
			["platoon"] = "#FFD23F",
			["self"] = "#F4F7F9",
		},
		deuteranopia = {
			["ally"] = "#3F8CFF",
			["enemy"] = "#FF8719",
			["platoon"] = "#BF1C6D",
			["self"] = "#F4F7F9",
		},
		protanopia = {
			["ally"] = "#3F8CFF",
			["enemy"] = "#FFBE19",
			["platoon"] = "#BF4C5F",
			["self"] = "#F4F7F9",
		},
		tritanopia = {
			["ally"] = "#418CD8",
			["enemy"] = "#EF3F34",
			["platoon"] = "#7F33CC",
			["self"] = "#F4F7F9",
		},
	},
	factions = {
		iron_union = { name = "IRON UNION", primary = "#B8492A", secondary = "#59616A", tint = "#E07A55" },
		crown_industries = { name = "CROWN INDUSTRIES", primary = "#5A3D8C", secondary = "#D6AA4E", tint = "#B79BE8" },
		eastern_armor = { name = "EASTERN ARMOR GROUP", primary = "#1C8582", secondary = "#E9DFC6", tint = "#4FC9C2" },
		desert_corps = { name = "DESERT ARMOR CORPS", primary = "#C8933A", secondary = "#7A5530", tint = "#E8B868" },
		mountain_republic = { name = "MOUNTAIN REPUBLIC", primary = "#3C7650", secondary = "#F2F5F7", tint = "#74B98A" },
		northern_federation = {
			name = "NORTHERN FEDERATION",
			primary = "#4F8FCB",
			secondary = "#EEF6FC",
			tint = "#8EC3EE",
		},
	},
	materials = {
		gunmetal = { highlight = "#7E8C99", base = "#38434E", shade = "#1C242B" },
		steel = { highlight = "#E2E9EF", base = "#9AA7B3", shade = "#596673" },
		bone = { highlight = "#FFFBF0", base = "#E3D8BC", shade = "#A3936D" },
		khaki = { highlight = "#E6D9B4", base = "#B4A275", shade = "#6F6141" },
		olive = { highlight = "#8E9862", base = "#5B6339", shade = "#363C21" },
		brass = { highlight = "#FFE6A0", base = "#D3A54A", shade = "#86641F" },
		bronze = { highlight = "#F4C49B", base = "#B5774A", shade = "#6B4227" },
		silver = { highlight = "#FFFFFF", base = "#C6CED6", shade = "#78848F" },
		gold = { highlight = "#FFF0B0", base = "#F0BD45", shade = "#A8741A" },
		obsidian = { highlight = "#56626E", base = "#1B2228", shade = "#0B0F12" },
		dusk = { highlight = "#FFC08F", base = "#FF7A2F", shade = "#B8460F" },
		copper = { highlight = "#FFD3AD", base = "#D98A4B", shade = "#8C4E22" },
		xp_blue = { highlight = "#C4E5FF", base = "#4FA6EE", shade = "#21609B" },
		xp_violet = { highlight = "#E4D6FF", base = "#A27CF4", shade = "#5B3AA6" },
		xp_teal = { highlight = "#C2FFF5", base = "#33C3B1", shade = "#167167" },
		rose = { highlight = "#FFD1DF", base = "#E2577F", shade = "#8E2446" },
		f_iron = { highlight = "#E98A63", base = "#B8492A", shade = "#6E2615" },
		f_crown = { highlight = "#A485D6", base = "#5A3D8C", shade = "#30204F" },
		f_eastern = { highlight = "#7FD8D2", base = "#1C8582", shade = "#0B4745" },
		f_desert = { highlight = "#F6CF86", base = "#C8933A", shade = "#7A5420" },
		f_desert_dark = { highlight = "#B48557", base = "#7A5530", shade = "#463019" },
		f_mountain = { highlight = "#86C49A", base = "#3C7650", shade = "#1E412A" },
		f_northern = { highlight = "#B5DBF7", base = "#4F8FCB", shade = "#24527F" },
		snow = { highlight = "#FFFFFF", base = "#EEF4F8", shade = "#AFC0CE" },
		amber = { highlight = "#FFE9A3", base = "#F2C230", shade = "#9C7612" },
		signal = { highlight = "#FFB3AC", base = "#EF4747", shade = "#8C1D1D" },
		verdant = { highlight = "#B8F2CF", base = "#3FCB7A", shade = "#1B7343" },
		azure = { highlight = "#C3E4FF", base = "#4AA8F0", shade = "#1E5E92" },
		ap = { highlight = "#FFDDB0", base = "#F28C38", shade = "#9A4A17" },
		apcr = { highlight = "#E6F7FF", base = "#86CDF5", shade = "#2D6E9C" },
		heat = { highlight = "#FFC9DA", base = "#EC4D82", shade = "#8A1D47" },
		he = { highlight = "#FFEFB5", base = "#FFC23D", shade = "#A06F0C" },
		ember = { highlight = "#FFB9A0", base = "#E0583A", shade = "#7F2617" },
		cobalt = { highlight = "#B9D6F5", base = "#4A86C8", shade = "#1F4775" },
		jade = { highlight = "#B4EBC9", base = "#3DAA6E", shade = "#1B5E3A" },
		scout = { highlight = "#FFF0B8", base = "#E9C03A", shade = "#8F7014" },
		r_rare = { highlight = "#BFE0FF", base = "#3E9BFF", shade = "#1A4F94" },
		r_epic = { highlight = "#E3D2FF", base = "#A970FF", shade = "#5A2FA8" },
		glass = { highlight = "#E4FAFF", base = "#5DB4D6", shade = "#1D4D63" },
		canvas = { highlight = "#E9E2C8", base = "#A99B70", shade = "#5E5434" },
	},
	ink = "#0A0D10",
	-- END GENERATED --

	--- Brand-guide colours that tokens.json does not carry (brand-art.md §8.3 primary CTA gradient, §9 climate strip).
	extraColors = {
		["cta.top"] = "#FF8A45",
		["cta.bottom"] = "#E8641F",
		["climate.temperate"] = "#7E8B4E",
		["climate.desert"] = "#C8933A",
		["climate.winter"] = "#9FC6E6",
		["climate.urban"] = "#8FA3B5",
		["climate.alpine"] = "#3C7650",
	},

	--- High-contrast mode: token -> token whose value it takes (kit choice; existing palette values only, no new hues).
	highContrast = {
		["text.secondary"] = "text.primary",
		["text.tertiary"] = "text.secondary",
		["text.disabled"] = "text.tertiary",
		["border.subtle"] = "border.strong",
		["border.strong"] = "border.bevel_hi",
		["bg.raised"] = "bg.panel",
	},
	--- Scrim transparency override in high-contrast mode (tokens.json scrim alpha CC = 0.2 transparency).
	highContrastScrimTransparency = 0.1,

	fontFamilies = {
		Oswald = "rbxasset://fonts/families/Oswald.json",
		BuilderSans = "rbxasset://fonts/families/BuilderSans.json",
		BuilderMono = "rbxasset://fonts/families/BuilderMono.json",
	},

	--- brand-art §4.1 at the 1080p reference. kind: "display" | "sentence" | "label" (selects the §4.2 minimum).
	typography = {
		["display.hero"] = {
			family = "Oswald",
			weight = "Bold",
			size = 72,
			lineHeight = 1.00,
			upper = true,
			kind = "display",
		},
		h1 = { family = "Oswald", weight = "Bold", size = 48, lineHeight = 1.05, upper = true, kind = "display" },
		h2 = { family = "Oswald", weight = "SemiBold", size = 36, lineHeight = 1.10, upper = true, kind = "display" },
		h3 = { family = "Oswald", weight = "SemiBold", size = 28, lineHeight = 1.15, upper = true, kind = "display" },
		h4 = { family = "BuilderSans", weight = "Bold", size = 22, lineHeight = 1.20, upper = false, kind = "label" },
		["body.l"] = {
			family = "BuilderSans",
			weight = "Medium",
			size = 20,
			lineHeight = 1.35,
			upper = false,
			kind = "sentence",
		},
		body = {
			family = "BuilderSans",
			weight = "Regular",
			size = 18,
			lineHeight = 1.35,
			upper = false,
			kind = "sentence",
		},
		["body.s"] = {
			family = "BuilderSans",
			weight = "Regular",
			size = 16,
			lineHeight = 1.35,
			upper = false,
			kind = "sentence",
		},
		label = { family = "BuilderSans", weight = "Bold", size = 14, lineHeight = 1.20, upper = true, kind = "label" },
		caption = {
			family = "BuilderSans",
			weight = "Medium",
			size = 14,
			lineHeight = 1.25,
			upper = false,
			kind = "sentence",
		},
		["num.xl"] = {
			family = "Oswald",
			weight = "Bold",
			size = 56,
			lineHeight = 1.00,
			upper = false,
			kind = "display",
		},
		["num.l"] = {
			family = "Oswald",
			weight = "SemiBold",
			size = 32,
			lineHeight = 1.00,
			upper = false,
			kind = "label",
		},
		["num.m"] = {
			family = "Oswald",
			weight = "SemiBold",
			size = 22,
			lineHeight = 1.00,
			upper = false,
			kind = "label",
		},
		mono = {
			family = "BuilderMono",
			weight = "Medium",
			size = 16,
			lineHeight = 1.30,
			upper = false,
			kind = "label",
		},
		micro = { family = "BuilderSans", weight = "Bold", size = 12, lineHeight = 1.10, upper = true, kind = "label" },
		--- Kit additions built from the brand rules: button labels (§8.3), top-level tabs (§8.4), badge counters (§8.5).
		button = {
			family = "BuilderSans",
			weight = "Bold",
			size = 18,
			lineHeight = 1.00,
			upper = false,
			kind = "label",
		},
		["button.cta"] = {
			family = "Oswald",
			weight = "Bold",
			size = 22,
			lineHeight = 1.00,
			upper = true,
			kind = "label",
		},
		["button.battle"] = {
			family = "Oswald",
			weight = "Bold",
			size = 28,
			lineHeight = 1.00,
			upper = true,
			kind = "label",
		},
		tab = { family = "Oswald", weight = "SemiBold", size = 20, lineHeight = 1.00, upper = true, kind = "label" },
		badge = { family = "Oswald", weight = "SemiBold", size = 13, lineHeight = 1.00, upper = true, kind = "label" },
		--- Toast titles (brand-art §8.5: Builder Sans Bold 16).
		["title.s"] = {
			family = "BuilderSans",
			weight = "Bold",
			size = 16,
			lineHeight = 1.20,
			upper = false,
			kind = "label",
		},
	},

	--- brand-art §4.2: minimum rendered sizes (after UIScale) per platform profile.
	--- Authored minimums per layout (docs/design/ui-ux.md §1.1): Compact authors larger roles so the 0.92 floor scale
	--- still meets the phone minimums without the clamp overflowing layouts; TV raises the smallest labels.
	--- Theme uses max(role size, minimum) before the text-scale and render-scale rules.
	layoutTypeMinimums = {
		compact = {
			body = 18,
			["body.s"] = 18,
			label = 16,
			caption = 16,
			micro = 16,
			h4 = 20,
			h3 = 24,
			h2 = 28,
			h1 = 32,
			["num.m"] = 20,
		},
		tv = { label = 15, caption = 15, micro = 15 },
	},
	minTextSize = {
		pc = { sentence = 14, label = 12, display = 12 },
		console = { sentence = 20, label = 18, display = 18 },
		phone = { sentence = 16, label = 14, display = 14 },
		tablet = { sentence = 15, label = 13, display = 13 },
	},

	--- research 06 A2: 8 px grid. Theme.space(n) for n = 0..8.
	spacing = { [0] = 0, 4, 8, 12, 16, 24, 32, 48, 64 },
	--- brand-art §6.4: 0 (chamfer) or a 4 px UICorner fallback, never above 8 px.
	radius = { none = 0, s = 2, m = 4, l = 8 },
	stroke = { hairline = 1, strong = 2, focus = 2, emphasis = 3 },
	--- HULLDOWN cut (brand-art §8.2): 8 px chamfers on panels and CTAs; 4 px on small tags.
	chamfer = { s = 4, m = 8, l = 9 },
	--- brand-art §8.2: one elevation shadow, ink at 45 %, offset 0/4 px, 12 px soft (modals and dropdowns only).
	shadow = { color = "ink", opacity = 0.45, offsetY = 4, blur = 12 },

	--- ScreenGui DisplayOrder per layer (research 09 R2; Loading in ReplicatedFirst stays at 100).
	layers = {
		Background3D = 0,
		HUD = 10,
		Screens = 20,
		--- Garage top bar in the engine's top-bar row (ScreenInsets.TopbarSafeInsets; ui-ux §1.1).
		TopBar = 25,
		Modals = 30,
		Toasts = 40,
		Tooltip = 50,
		Debug = 90,
	},
	--- ZIndex steps inside a layer (ZIndexBehavior = Sibling).
	z = { base = 1, raised = 2, content = 3, overlay = 5, popover = 10, top = 20 },

	--- brand-art §8.1 / research 06 A6 (seconds). Reduced motion is applied by Kit/Motion.
	motion = {
		instant = 0,
		hover = 0.08,
		fast = 0.12,
		base = 0.15,
		slow = 0.2,
		toast = 0.16,
		flourish = 0.4,
		countUp = 0.6,
		tooltipDelay = 0.4,
		longPress = 0.5,
		toastHold = 4,
		toastHoldAction = 8,
		focusPulse = 0.9,
	},
	--- Easing presets: { style, direction } (EasingStyle / EasingDirection names). "Nothing bounces" (§8.1).
	easings = {
		standard = { "Quad", "Out" },
		enter = { "Cubic", "Out" },
		exit = { "Quad", "In" },
		linear = { "Linear", "InOut" },
		emphasized = { "Quart", "Out" },
	},

	--- Component sizes in reference px (brand-art §8.3 buttons, §4.2 touch targets, research 06 A5 battle CTA).
	sizes = {
		buttonHeight = { large = 56, medium = 44, compact = 36, battle = 64 },
		buttonMinWidthRatio = 2.5,
		battleMinWidth = 280,
		touchMin = 44,
		touchPrimary = 48,
		icon = { xs = 16, s = 20, m = 24, l = 32, xl = 48, hero = 64 },
		focusRingOffset = 2,
		badgeMin = 18,
		toastWidth = 360,
		tooltipMaxWidth = 320,
		modalWidth = { s = 480, m = 640, l = 880 },
		tabHeight = 48,
		rowHeight = 56,
		scrollBar = { mouse = 6, gamepad = 4, touch = 4 },
	},
}

return Freeze.deep(Tokens)
