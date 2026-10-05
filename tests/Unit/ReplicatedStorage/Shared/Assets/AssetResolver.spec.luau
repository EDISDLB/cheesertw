local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local AssetResolver = require("@game/ReplicatedStorage/Shared/Assets/AssetResolver")
local AssetManifest = require("@game/ReplicatedStorage/Shared/Assets/AssetManifest")
local FallbackKeys = require("@game/ReplicatedStorage/Shared/Assets/FallbackKeys")

local describe, it, expect = Test.describe, Test.it, Test.expect

local function manifest(): any
	return {
		version = 1,
		generatedAt = "2026-10-05T00:00:00Z",
		images = {
			["classes/heavy"] = { id = "rbxassetid://101", size = Vector2.new(64, 64) },
			["equipment/rammer"] = { id = "rbxassetid://102" },
		},
		sounds = {
			ui_click = { id = "rbxassetid://201", durationS = 0.24, loop = false, bus = "UI", volume = 0.7 },
			amb_desert_bed = { id = "rbxassetid://202", durationS = 40, loop = true, bus = "Ambience", volume = 0.5 },
			ui_hover = {
				id = "rbxassetid://203",
				durationS = 0.18,
				loop = false,
				bus = "UI",
				volume = 0.6,
				region = { startS = 1.5, endS = 1.68 },
			},
		},
	}
end

describe("AssetResolver keys", function()
	it("validates key syntax and extracts categories", function()
		expect(AssetResolver.isValidKey("classes/heavy")).toBe(true)
		expect(AssetResolver.isValidKey("ui_click")).toBe(true)
		expect(AssetResolver.isValidKey("tiers/tier_07")).toBe(true)
		expect(AssetResolver.isValidKey("Classes/Heavy")).toBe(false)
		expect(AssetResolver.isValidKey("classes//heavy")).toBe(false)
		expect(AssetResolver.isValidKey("classes/heavy/")).toBe(false)
		expect(AssetResolver.isValidKey("a-b")).toBe(false)
		expect(AssetResolver.isValidKey("")).toBe(false)
		expect(AssetResolver.isValidKey(5)).toBe(false)
		expect(AssetResolver.isValidKey(string.rep("a", 129))).toBe(false)
		expect(AssetResolver.categoryOf("classes/heavy")).toBe("classes")
		expect(AssetResolver.categoryOf("ui_click")).toBeNil()
	end)

	it("ships fallback keys that are valid and unique", function()
		local seen = {}
		for _, key in FallbackKeys.glyphs do
			expect(AssetResolver.isValidKey(key)).toBe(true)
			expect(seen[key]).toBeNil()
			seen[key] = true
		end
		expect(#FallbackKeys.glyphs).toBeGreaterThan(100)
	end)
end)

describe("AssetResolver manifest validation", function()
	it("accepts the shipped (empty, generated) manifest and a well-formed one", function()
		expect(AssetResolver.validateManifest(AssetManifest)).toEqual({})
		expect(AssetResolver.validateManifest(manifest())).toEqual({})
	end)

	it("reports malformed entries", function()
		expect(AssetResolver.validateManifest(nil)).toEqual({ "manifest is not a table" })
		expect(#AssetResolver.validateManifest({ version = 1 })).toBe(2)
		local bad = manifest()
		bad.images["Bad Key"] = { id = "rbxassetid://1" }
		bad.images["ui/close"] = { id = "http://example.com/x.png" }
		bad.sounds.ui_click.bus = "Sfx"
		bad.sounds.ui_click.durationS = 0
		bad.sounds.amb_desert_bed.region = { startS = 0, endS = 1 }
		bad.sounds.ui_hover.region = { startS = 2, endS = 1 }
		bad.sounds.ui_back = { id = "rbxassetid://9", durationS = 1, loop = "no", bus = "UI", volume = 99 }
		local problems = AssetResolver.validateManifest(bad)
		local text = table.concat(problems, "\n")
		expect(text).toContain('image key "Bad Key" is malformed')
		expect(text).toContain('image "ui/close" has no valid id')
		expect(text).toContain('bus "Sfx" is not a mix bus')
		expect(text).toContain("durationS must be > 0")
		expect(text).toContain("loops are never banked")
		expect(text).toContain("0 <= startS < endS")
		expect(text).toContain("loop must be a boolean")
		expect(text).toContain("volume must be within 0..10")
	end)
end)

describe("AssetResolver resolution", function()
	it("resolves uploaded images and sounds", function()
		local resolver = AssetResolver.new(manifest())
		expect(resolver:image("classes/heavy")).toBe("rbxassetid://101")
		expect(resolver:imageAsset("classes/heavy").size).toEqual(Vector2.new(64, 64))
		expect(resolver:sound("ui_click").bus).toBe("UI")
		expect(resolver:sound("ui_hover").region).toEqual({ startS = 1.5, endS = 1.68 })
		expect(resolver:has("ui_click")).toBe(true)
		expect(resolver:has("equipment/rammer")).toBe(true)
		expect(resolver:hasImage("ui_click")).toBe(false)
		expect(resolver:hasSound("ui_click")).toBe(true)
	end)

	it("classifies image fallbacks: image, glyph, badge, missing", function()
		local resolver = AssetResolver.new(manifest())
		expect(resolver:resolveImage("classes/heavy").kind).toBe("image")
		expect(resolver:resolveImage("classes/light").kind).toBe("glyph")
		expect(resolver:resolveImage("equipment/turbocharger")).toEqual({
			kind = "badge",
			key = "equipment/turbocharger",
			category = "equipment",
		})
		expect(resolver:resolveImage("vehicles/iu_forge").kind).toBe("missing")
		expect(resolver:hasFallback("currency/credits")).toBe(true)
		expect(resolver:hasFallback("ranks/rank_03")).toBe(true)
		expect(resolver:hasFallback("vehicles/iu_forge")).toBe(false)
		expect(resolver:hasGlyph("ui/close")).toBe(true)
		resolver:declareGlyph("vehicles/iu_forge")
		expect(resolver:resolveImage("vehicles/iu_forge").kind).toBe("glyph")
		expect(function()
			resolver:declareGlyph("Bad Key")
		end).toThrow("invalid key")
		local extra = AssetResolver.new(manifest(), { glyphs = { "maps/x" }, badgeCategories = { "vehicles" } })
		expect(extra:resolveImage("vehicles/iu_forge").kind).toBe("badge")
		expect(extra:hasGlyph("maps/x")).toBe(true)
	end)

	it("warns once per missing key, at debug level when a fallback exists", function()
		local capture = LogCapture.start("debug")
		local resolver = AssetResolver.new(manifest())
		expect(resolver:sound("cue_spotted")).toBeNil()
		expect(resolver:sound("cue_spotted")).toBeNil()
		expect(resolver:image("vehicles/iu_forge")).toBeNil()
		resolver:image("vehicles/iu_forge")
		resolver:image("classes/td")
		resolver:image("classes/td")
		resolver:image("Not Valid")
		local warns, debugs = 0, 0
		for _, entry in capture.entries do
			if entry.scope == "Assets" then
				if entry.level == "warn" then
					warns += 1
				elseif entry.level == "debug" then
					debugs += 1
				end
			end
		end
		expect(warns).toBe(3)
		expect(debugs).toBe(1)
		expect(capture:find("warn", "playing silence")).never.toBeNil()
		expect(capture:find("warn", "no fallback")).never.toBeNil()
		expect(capture:find("warn", "malformed image key")).never.toBeNil()
		expect(resolver:missing()).toEqual({
			images = { "Not Valid", "classes/td", "vehicles/iu_forge" },
			sounds = { "cue_spotted" },
		})
		capture:stop()
	end)

	it("validates content key lists with and without fallbacks", function()
		local resolver = AssetResolver.new(manifest())
		local keys = { "classes/heavy", "classes/light", "equipment/turbocharger", "vehicles/iu_forge", "Bad Key" }
		expect(resolver:validateKeys(keys)).toEqual({ missing = { "vehicles/iu_forge" }, invalid = { "Bad Key" } })
		expect(resolver:validateKeys(keys, { allowFallback = false })).toEqual({
			missing = { "classes/light", "equipment/turbocharger", "vehicles/iu_forge" },
			invalid = { "Bad Key" },
		})
		expect(resolver:validateKeys({ "ui_click", "ui_nope" }, { kind = "sound" })).toEqual({
			missing = { "ui_nope" },
			invalid = {},
		})
	end)

	it("exposes a default resolver over the generated manifest", function()
		expect(AssetResolver.default()).toBe(AssetResolver.default())
		expect(AssetResolver.image("classes/heavy")).toBeNil()
		expect(AssetResolver.imageAsset("classes/heavy")).toBeNil()
		expect(AssetResolver.resolveImage("classes/heavy").kind).toBe("glyph")
		expect(AssetResolver.sound("ui_click")).toBeNil()
		expect(AssetResolver.has("ui_click")).toBe(false)
		expect(AssetResolver.hasFallback("tiers/tier_11")).toBe(true)
	end)
end)
