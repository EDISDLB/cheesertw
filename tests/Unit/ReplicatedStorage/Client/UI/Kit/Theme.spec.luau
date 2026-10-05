local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local Tokens = require("@game/ReplicatedStorage/Client/UI/Kit/Tokens")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

local function hex(color: Color3): string
	return "#" .. string.upper(color:ToHex())
end

describe("Tokens", function()
	it("mirror assets/brand/tokens.json exactly (regenerate Tokens.luau when this fails)", function()
		local json = serde.decode("json", fs.readFile("assets/brand/tokens.json"))
		local function count(t: { [any]: any }): number
			local n = 0
			for _ in t do
				n += 1
			end
			return n
		end
		expect(count(Tokens.colors)).toBe(count(json.ui))
		for name, value in json.ui do
			expect((Tokens.colors :: any)[name]).toBe(value)
		end
		for scheme, roles in json.team_cvd do
			for role, value in roles do
				expect((Tokens.teamSchemes :: any)[scheme][role]).toBe(value)
			end
		end
		expect(count(Tokens.factions)).toBe(count(json.factions))
		for id, faction in json.factions do
			expect((Tokens.factions :: any)[id]).toEqual(faction)
		end
		expect(count(Tokens.materials)).toBe(count(json.materials))
		for name, material in json.materials do
			expect((Tokens.materials :: any)[name]).toEqual(material)
		end
		expect(Tokens.ink).toBe(json.ink)
	end)

	it("are frozen", function()
		expect(function()
			(Tokens.colors :: any)["bg.base"] = "#000000"
		end).toThrow()
	end)

	it("high-contrast aliases point at existing tokens", function()
		for name, alias in Tokens.highContrast :: any do
			expect((Tokens.colors :: any)[name]).never.toBeNil()
			expect((Tokens.colors :: any)[alias]).never.toBeNil()
		end
	end)
end)

describe("Theme colours", function()
	Test.beforeEach(function()
		Theme.reset()
	end)

	it("parses #RRGGBB and #RRGGBBAA", function()
		local c, t = Theme.parseHex("#0A0D10CC")
		expect(hex(c)).toBe("#0A0D10")
		expect(t).toBeCloseTo(1 - 204 / 255, 1e-6)
		local c2, t2 = Theme.parseHex("#FF7A2F")
		expect(hex(c2)).toBe("#FF7A2F")
		expect(t2).toBe(0)
		expect(function()
			Theme.parseHex("FF7A2F")
		end).toThrow("invalid colour")
	end)

	it("resolves every token and rejects unknown names", function()
		for name in Tokens.colors :: any do
			expect(typeof(Theme.peekColor(name))).toBe("Color3")
		end
		expect(hex(Theme.peekColor("accent.dusk"))).toBe("#FF7A2F")
		expect(hex(Theme.peekColor("cta.top"))).toBe("#FF8A45")
		expect(hex(Theme.peekColor("ink"))).toBe("#0A0D10")
		expect(function()
			Theme.color("bg.nope" :: any)
		end).toThrow("unknown colour token")
		expect(Theme.color("bg.panel")).toBe(Theme.color("bg.panel"))
	end)

	it("switches team colours live with the colour-blind scheme", function()
		local frame = Create("Frame", { BackgroundColor3 = Theme.team("ally") })
		expect(hex(frame.BackgroundColor3)).toBe("#47D16C")
		local snapshots = {}
		local connection = Theme.changed:Connect(function(snapshot)
			table.insert(snapshots, snapshot.scheme)
		end)
		Theme.set({ scheme = "deuteranopia" })
		expect(hex(frame.BackgroundColor3)).toBe("#3F8CFF")
		expect(hex(Theme.peekColor("team.enemy"))).toBe("#FF8719")
		Theme.set({ scheme = "tritanopia" })
		expect(hex(Theme.peekColor("team.platoon"))).toBe("#7F33CC")
		Theme.set({ scheme = "tritanopia" })
		expect(snapshots).toEqual({ "deuteranopia", "tritanopia" })
		expect(hex(Theme.peekColor("team.destroyed"))).toBe("#5D666E")
		connection:Disconnect()
		expect(function()
			Theme.set({ scheme = "monochrome" :: any })
		end).toThrow("unknown colour-blind scheme")
	end)

	it("applies high contrast through palette aliases", function()
		local label = Create("TextLabel", { TextColor3 = Theme.color("text.secondary") })
		expect(hex(label.TextColor3)).toBe("#A8B5C0")
		local scrim = Theme.tokenTransparency("bg.scrim")
		expect(scrim:peek()).toBeCloseTo(0.2, 0.01)
		Theme.set({ highContrast = true })
		expect(hex(label.TextColor3)).toBe("#EAEFF2")
		expect(hex(Theme.peekColor("border.subtle"))).toBe("#3A4855")
		expect(scrim:peek()).toBe(0.1)
		expect(hex(Theme.peekColor("accent.dusk"))).toBe("#FF7A2F")
		expect(Theme.tokenTransparency("bg.panel"):peek()).toBe(0)
	end)

	it("exposes palettes, mixes and preferred transparency", function()
		expect(hex(Theme.faction("iron_union").primary)).toBe("#B8492A")
		expect(hex(Theme.material("gold").base)).toBe("#F0BD45")
		expect(hex(Theme.schemeColors("protanopia").enemy)).toBe("#FFBE19")
		expect(hex(Theme.rarity("epic"):peek())).toBe("#A970FF")
		expect(hex(Theme.currency("bullion"):peek())).toBe("#F4C653")
		expect(Theme.toneToken("danger")).toBe("state.danger")
		expect(Theme.toneToken("neutral")).toBe("text.secondary")
		local mixed = Theme.mix("bg.raised", "state.danger", 0.5):peek()
		local a, b = Theme.peekColor("bg.raised"), Theme.peekColor("state.danger")
		expect(mixed.R).toBeCloseTo((a.R + b.R) / 2, 1e-6)
		local transparency = Theme.backgroundTransparency(0.5)
		expect(transparency:peek()).toBe(0.5)
		Theme.setSystem({ preferredTransparency = 0 })
		expect(transparency:peek()).toBe(0)
		expect(function()
			Theme.faction("nope")
		end).toThrow("unknown faction")
		expect(function()
			Theme.material("nope")
		end).toThrow("unknown material")
	end)
end)

describe("Theme typography", function()
	Test.beforeEach(function()
		Theme.reset()
	end)

	it("builds brand fonts per role", function()
		local display = Theme.font("h1")
		expect(display.Family).toBe("rbxasset://fonts/families/Oswald.json")
		expect(display.Weight).toBe(Enum.FontWeight.Bold)
		expect(Theme.font("body").Family).toBe("rbxasset://fonts/families/BuilderSans.json")
		expect(Theme.font("mono").Family).toBe("rbxasset://fonts/families/BuilderMono.json")
		expect(Theme.font("h2").Weight).toBe(Enum.FontWeight.SemiBold)
		expect(Theme.lineHeight("body")).toBe(1.35)
		expect(Theme.isUpper("label")).toBe(true)
		expect(Theme.typography("num.l").baseSize).toBe(32)
		expect(function()
			Theme.font("h9" :: any)
		end).toThrow("unknown type role")
	end)

	it("computes sizes with text scale and platform minimums", function()
		expect(Theme.computeTextSize(18, "sentence", 1, 1, "pc")).toBe(18)
		expect(Theme.computeTextSize(18, "sentence", 1, 0.75, "tablet")).toBe(20)
		expect(Theme.computeTextSize(18, "sentence", 1, 1, "console")).toBe(20)
		expect(Theme.computeTextSize(12, "label", 1, 1, "pc")).toBe(12)
		expect(Theme.computeTextSize(12, "label", 1, 1, "phone")).toBe(14)
		expect(Theme.computeTextSize(18, "sentence", 1.5, 1, "pc")).toBe(27)
		expect(Theme.computeTextSize(14, "sentence", 0.8, 1, "pc")).toBe(14)
		expect(Theme.computeTextSize(72, "display", 1, 1.25, "console")).toBe(72)
	end)

	it("text sizes update live with text scale and render scale", function()
		local label = Create("TextLabel", { TextSize = Theme.textSize("body") })
		expect(label.TextSize).toBe(18)
		Theme.set({ textScale = 1.25 })
		expect(label.TextSize).toBe(23)
		Theme.set({ textScale = 9 })
		expect(Theme.snapshot().textScale).toBe(Theme.TEXT_SCALE_MAX)
		Theme.set({ textScale = 1 })
		Theme.setSystem({ renderScale = 0.75, platform = "phone" })
		expect(label.TextSize).toBe(22)
	end)
end)

describe("Theme scales and settings", function()
	Test.beforeEach(function()
		Theme.reset()
	end)

	it("looks up spacing, radii, strokes, layers, z, motion and easing", function()
		expect(Theme.space(0)).toBe(0)
		expect(Theme.space(2)).toBe(8)
		expect(Theme.space(8)).toBe(64)
		expect(Theme.radius("m")).toEqual(UDim.new(0, 4))
		expect(Theme.stroke("focus")).toBe(2)
		expect(Theme.chamfer("m")).toBe(8)
		expect(Theme.layer("Modals")).toBe(30)
		expect(Theme.layer("Tooltip")).toBeGreaterThan(Theme.layer("Toasts"))
		expect(Theme.z("popover")).toBeGreaterThan(Theme.z("base"))
		expect(Theme.duration("base")).toBe(0.15)
		local style, direction = Theme.easing("standard")
		expect(style).toBe(Enum.EasingStyle.Quad)
		expect(direction).toBe(Enum.EasingDirection.Out)
		expect(Theme.sizes.buttonHeight.large).toBe(56)
		expect(function()
			Theme.space(9)
		end).toThrow("spacing step")
		expect(function()
			Theme.layer("Nope" :: any)
		end).toThrow("unknown layer")
	end)

	it("clamps UI scale and ORs reduced motion from the player and the engine", function()
		Theme.set({ uiScale = 3 })
		expect(Theme.snapshot().uiScale).toBe(Theme.UI_SCALE_MAX)
		Theme.set({ uiScale = 0 / 0 })
		expect(Theme.snapshot().uiScale).toBe(Theme.UI_SCALE_MIN)
		expect(Theme.state.reducedMotion:peek()).toBe(false)
		Theme.set({ reducedMotion = true })
		expect(Theme.state.reducedMotion:peek()).toBe(true)
		Theme.set({ reducedMotion = false })
		local stop = Theme.bindEngine()
		env.guiService.ReducedMotionEnabled = true
		expect(Theme.state.reducedMotion:peek()).toBe(true)
		env.guiService.PreferredTransparency = 0.5
		expect(Theme.snapshot().preferredTransparency).toBe(0.5)
		stop()
		env.guiService.ReducedMotionEnabled = false
		expect(Theme.state.reducedMotion:peek()).toBe(true)
	end)
end)
