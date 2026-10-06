local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Icon = require("@game/ReplicatedStorage/Client/UI/Icons/Icon")
local Registry = require("@game/ReplicatedStorage/Client/UI/Icons/Registry")
local Glyph = require("@game/ReplicatedStorage/Client/UI/Icons/Glyph")
local FallbackKeys = require("@game/ReplicatedStorage/Shared/Assets/FallbackKeys")
local AssetResolver = require("@game/ReplicatedStorage/Shared/Assets/AssetResolver")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local fs = require("@lune/fs")

local describe, it, expect = Test.describe, Test.it, Test.expect

Support.install()

local SVG_FOLDERS = { "classes", "minimap", "tiers", "currency", "ammo", "modules", "crew", "ui" }

describe("Icons registry", function()
	it("matches Shared/Assets/FallbackKeys exactly", function()
		local registry = {}
		for _, key in Registry.keys() do
			registry[key] = true
		end
		local declared = {}
		for _, key in FallbackKeys.glyphs do
			declared[key] = true
			expect(registry[key]).toBe(true)
		end
		for key in registry do
			expect(declared[key]).toBe(true)
		end
	end)

	it("uses the asset pipeline's key names (assets/icons/<key>.svg) where source art exists", function()
		for _, key in Registry.keys() do
			local folder = AssetResolver.categoryOf(key)
			if folder ~= nil and table.find(SVG_FOLDERS, folder) then
				expect({ key = key, exists = fs.isFile(`assets/icons/{key}.svg`) }).toEqual({ key = key, exists = true })
			end
		end
	end)

	it("covers the required core sets", function()
		for _, key in
			{
				"classes/light",
				"classes/medium",
				"classes/heavy",
				"classes/td",
				"classes/artillery",
				"tiers/tier_01",
				"tiers/tier_11",
				"currency/credits",
				"currency/bullion",
				"currency/vehicle_xp",
				"ammo/heat",
				"modules/engine_damaged",
				"modules/gun_destroyed",
				"crew/loader_injured",
				"hits/ricochet",
				"pings/focus_fire",
				"hud/spotted",
			}
		do
			expect(Registry.has(key)).toBe(true)
		end
	end)

	it("rejects bad registrations", function()
		expect(function()
			Registry.register("NoSlash", { build = function() end })
		end).toThrow("malformed key")
		expect(function()
			Registry.register("custom/thing", {} :: any)
		end).toThrow("build function")
		expect(function()
			Registry.register("classes/heavy", { build = function() end })
		end).toThrow("already exists")
	end)
end)

describe("Icons glyph rendering", function()
	it("builds every glyph inside the canvas with valid Roblox properties", function()
		local problems = {}
		for _, key in Registry.keys() do
			local ok, result = pcall(Icon.glyph, key, 48)
			if not ok then
				table.insert(problems, `{key}: {result}`)
				continue
			end
			local root = result
			local descendants = root:GetDescendants()
			if #descendants < 1 then
				table.insert(problems, `{key}: only {#descendants} primitives`)
			end
			for _, d in descendants do
				if d.ClassName == "Frame" or d.ClassName == "TextLabel" then
					local position, size, anchor = d.Position, d.Size, d.AnchorPoint or Vector2.new(0, 0)
					local cx = position.X.Scale + size.X.Scale * (0.5 - anchor.X)
					local cy = position.Y.Scale + size.Y.Scale * (0.5 - anchor.Y)
					if cx < -0.02 or cx > 1.02 or cy < -0.02 or cy > 1.02 then
						table.insert(problems, `{key}: {d.Name} centred off-canvas at ({cx}, {cy})`)
					end
				end
			end
			Support.validateTree(root)
			root:Destroy()
		end
		expect(problems).toEqual({})
	end)

	it("draws the generic category badge for unknown keys, tinted by category", function()
		local badge = Icon.glyph("equipment/rammer", 32)
		expect(badge.Name).toBe("Badge")
		expect(badge:GetAttribute("IconKey")).toBe("equipment/rammer")
		local unknown = Icon.glyph("whatever/thing", 32)
		expect(unknown.Name).toBe("Badge")
		Support.validateTree(badge)
	end)

	it("binds stroke thickness and text size to the icon size", function()
		local size = State.Value(64)
		local canvas = Glyph.canvas(size)
		local ring = Glyph.ring(canvas, 32, 32, 20, 4, Color3.new(1, 1, 1))
		local text = Glyph.text(canvas, "VII", 32, 32, 20, Color3.new(1, 1, 1))
		local stroke = ring:FindFirstChildOfClass("UIStroke")
		expect(stroke.Thickness).toBe(4)
		expect(text.TextSize).toBe(20)
		expect(canvas.root.Size).toEqual(UDim2.fromOffset(64, 64))
		size:set(32)
		expect(stroke.Thickness).toBe(2)
		expect(text.TextSize).toBe(10)
		expect(canvas.root.Size).toEqual(UDim2.fromOffset(32, 32))
	end)
end)

describe("Icon component", function()
	local function fakeResolver(): any
		return AssetResolver.new({
			version = 1,
			generatedAt = "",
			images = {
				["classes/heavy"] = { id = "rbxassetid://555" },
				["ranks/rank_03"] = {
					id = "rbxassetid://777",
					rectSize = Vector2.new(64, 64),
					rectOffset = Vector2.new(128, 0),
				},
			},
			sounds = {},
		})
	end

	Test.afterEach(function()
		Icon.setResolver(nil)
	end)

	it("renders uploaded art as one tinted ImageLabel and glyphs otherwise", function()
		Icon.setResolver(fakeResolver())
		local tint = Theme.team("enemy")
		local uploaded = Icon.new({ key = "classes/heavy", size = 20, color = tint })
		local image = uploaded:FindFirstChildOfClass("ImageLabel")
		expect(image.Image).toBe("rbxassetid://555")
		expect(image.ImageColor3).toEqual(tint:peek())
		expect(uploaded.Size).toEqual(UDim2.fromOffset(20, 20))
		local sheet = Icon.new({ key = "ranks/rank_03" })
		local sheetImage = sheet:FindFirstChildOfClass("ImageLabel")
		expect(sheetImage.ImageRectOffset).toEqual(Vector2.new(128, 0))
		local glyph = Icon.new({ key = "classes/light" })
		expect(glyph:FindFirstChildOfClass("ImageLabel")).toBeNil()
		expect(glyph:FindFirstChild("Glyph")).never.toBeNil()
		local forced = Icon.new({ key = "classes/heavy", forceGlyph = true })
		expect(forced:FindFirstChild("Glyph")).never.toBeNil()
		Support.validateTree(uploaded)
		Support.validateTree(sheet)
	end)

	it("rebuilds when the key changes and destroys the old content", function()
		local key = State.Value("ui/close")
		local size = State.Value(24)
		local icon = Icon.new({ key = key, size = size, Name = "CloseIcon" })
		local first = icon:FindFirstChild("Glyph")
		expect(first:GetAttribute("IconKey")).toBe("ui/close")
		key:set("ui/check")
		expect(rawget(first, "_destroyed")).toBe(true)
		expect(icon:FindFirstChild("Glyph"):GetAttribute("IconKey")).toBe("ui/check")
		size:set(40)
		expect(icon.Size).toEqual(UDim2.fromOffset(40, 40))
		icon:Destroy()
	end)

	it("registers feature glyphs and declares them to the resolver", function()
		local resolver = fakeResolver()
		Icon.setResolver(resolver)
		expect(resolver:resolveImage("vehicles/iu_forge").kind).toBe("missing")
		Icon.register("vehicles/iu_forge", {
			build = function(c, p)
				Glyph.rect(c, 8, 20, 48, 24, p.fg)
			end,
			color = "brand.bone",
		})
		expect(resolver:resolveImage("vehicles/iu_forge").kind).toBe("glyph")
		expect(Icon.has("vehicles/iu_forge")).toBe(true)
		expect(table.find(Icon.keys(), "vehicles/iu_forge")).never.toBeNil()
	end)
end)
