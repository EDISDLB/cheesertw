local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Schema = require("@game/ReplicatedStorage/Shared/Core/Schema")

local function errOf(validator: any, value: any): string?
	local ok, err = validator(value)
	if ok then
		return nil
	end
	return err
end

describe("Schema leaf validators", function()
	it("number: finite, bounds and integer", function()
		local v = Schema.number({ min = 0, max = 10, integer = true })
		expect(errOf(v, 5)).toBeNil()
		expect(errOf(v, 11)).toBe("expected <= 10, got 11")
		expect(errOf(v, -1)).toBe("expected >= 0, got -1")
		expect(errOf(v, 1.5)).toBe("expected integer, got 1.5")
		expect(errOf(v, "5")).toBe("expected integer, got string")
		expect(errOf(Schema.number(), 0 / 0)).toBe("expected finite number, got NaN")
		expect(errOf(Schema.number(), math.huge)).toBe("expected finite number, got inf")
	end)

	it("string: length, UTF-8 and pattern", function()
		local v = Schema.string({ minLen = 2, maxLen = 4, pattern = "^%a+$" })
		expect(errOf(v, "abc")).toBeNil()
		expect(errOf(v, "abcde")).toBe("expected at most 4 bytes, got 5")
		expect(errOf(v, "a")).toBe("expected at least 2 bytes, got 1")
		expect(errOf(v, "ab1")).toContain("does not match pattern")
		expect(errOf(Schema.string(), "\255\254")).toBe("expected valid UTF-8 string")
		expect(errOf(Schema.string({ allowInvalidUtf8 = true }), "\255")).toBeNil()
		expect(errOf(Schema.string(), 5)).toBe("expected string, got number")
	end)

	it("boolean, any, literal, enum", function()
		expect(errOf(Schema.boolean, true)).toBeNil()
		expect(errOf(Schema.boolean, nil)).toBe("expected boolean, got nil")
		expect(errOf(Schema.any, nil)).toBeNil()
		expect(errOf(Schema.literal("AP"), "AP")).toBeNil()
		expect(errOf(Schema.literal("AP"), "HE")).toBe('expected string "AP", got string "HE"')
		local ammo = Schema.enum({ "AP", "APCR", "HE" })
		expect(errOf(ammo, "HE")).toBeNil()
		expect(errOf(ammo, "HEAT")).toBe('expected one of "AP", "APCR", "HE", got string "HEAT"')
		expect(errOf(ammo, nil)).toContain("got nil")
	end)

	it("vector3: finite components and magnitude", function()
		local v = Schema.vector3({ maxMagnitude = 1.01 })
		expect(errOf(v, Vector3.new(0, 1, 0))).toBeNil()
		expect(errOf(v, Vector3.new(0, 2, 0))).toContain("expected magnitude <= 1.01")
		expect(errOf(v, Vector3.new(0 / 0, 0, 0))).toBe("expected finite Vector3 components")
		expect(errOf(v, { X = 1 })).toBe("expected Vector3, got table")
	end)

	it("buffer and instance", function()
		expect(errOf(Schema.buffer({ maxLen = 4 }), buffer.create(4))).toBeNil()
		expect(errOf(Schema.buffer({ maxLen = 4 }), buffer.create(5))).toBe("expected at most 4 bytes, got 5")
		expect(errOf(Schema.buffer(), "x")).toBe("expected buffer, got string")
		local folder = Instance.new("Folder")
		expect(errOf(Schema.instance(), folder)).toBeNil()
		expect(errOf(Schema.instance("Folder"), folder)).toBeNil()
		expect(errOf(Schema.instance("Player"), folder)).toBe("expected Player, got Folder")
		expect(errOf(Schema.instance(), {})).toBe("expected Instance, got table")
	end)
end)

describe("Schema composites", function()
	it("optional", function()
		local v = Schema.optional(Schema.number())
		expect(errOf(v, nil)).toBeNil()
		expect(errOf(v, 1)).toBeNil()
		expect(errOf(v, "x")).toBe("expected finite number, got string")
	end)

	it("array: strict keys, length and element paths", function()
		local v = Schema.array(Schema.number(), { maxLen = 3, minLen = 1 })
		expect(errOf(v, { 1, 2 })).toBeNil()
		expect(errOf(v, { 1, 2, 3, 4 })).toBe("expected at most 3 elements, got 4")
		expect(errOf(v, {})).toBe("expected at least 1 elements, got 0")
		expect(errOf(v, { 1, "x" })).toBe("[2]: expected finite number, got string")
		expect(errOf(v, { a = 1 })).toContain("non-sequential key")
		expect(errOf(v, { [1] = 1, [3] = 3 })).toContain("non-sequential key")
		expect(errOf(v, "x")).toBe("expected array, got string")
	end)

	it("map: key/value validation and maxLen", function()
		local v = Schema.map(Schema.string({ maxLen = 8 }), Schema.number({ min = 0 }), { maxLen = 2 })
		expect(errOf(v, { a = 1, b = 2 })).toBeNil()
		expect(errOf(v, { a = 1, b = 2, c = 3 })).toBe("expected at most 2 entries")
		expect(errOf(v, { a = -1 })).toBe(".a: expected >= 0, got -1")
		expect(errOf(v, { [5] = 1 })).toBe("key 5: expected string, got number")
		expect(errOf(v, { ["a b"] = -1 })).toBe(`["a b"]: expected >= 0, got -1`)
	end)

	it("struct: required/optional fields, unknown keys and nested paths", function()
		local loadout = Schema.struct({
			vehicleId = Schema.string({ maxLen = 40 }),
			shells = Schema.array(
				Schema.struct({
					id = Schema.string(),
					count = Schema.number({ integer = true, min = 0 }),
				}),
				{ maxLen = 3 }
			),
			note = Schema.optional(Schema.string()),
		})
		expect(errOf(loadout, { vehicleId = "t1", shells = { { id = "ap", count = 30 } } })).toBeNil()
		expect(errOf(loadout, { vehicleId = "t1", shells = { { id = "ap", count = 30 }, { id = "he", count = 2.5 } } })).toBe(
			".shells[2].count: expected integer, got 2.5"
		)
		expect(errOf(loadout, { shells = {} })).toBe(".vehicleId: expected string, got nil")
		expect(errOf(loadout, { vehicleId = "t1", shells = {}, extra = true })).toBe('unexpected key string "extra"')
		local loose = Schema.struct({ a = Schema.number() }, { allowExtra = true })
		expect(errOf(loose, { a = 1, b = 2 })).toBeNil()
		expect(errOf(loadout, 5)).toBe("expected table, got number")
	end)

	it("oneOf lists every alternative", function()
		local v = Schema.oneOf(Schema.number(), Schema.string({ maxLen = 2 }))
		expect(errOf(v, 1)).toBeNil()
		expect(errOf(v, "ab")).toBeNil()
		expect(errOf(v, true)).toBe(
			"no alternative matched: (1) expected finite number, got boolean; (2) expected string, got boolean"
		)
	end)

	it("check wraps the outcome in a Result with a labelled path", function()
		local v = Schema.struct({ a = Schema.array(Schema.number()) })
		expect(Schema.check(v, { a = { 1 } })).toBeOk()
		local bad = Schema.check(v, { a = { "x" } }, "arg1")
		expect(bad).toBeErr("INVALID_ARGS")
		expect(bad.detail).toBe("arg1.a[1]: expected finite number, got string")
		expect(Schema.check(Schema.number(), "x").detail).toBe("value: expected finite number, got string")
	end)

	it("describe renders values for messages", function()
		expect(Schema.describe(nil)).toBe("nil")
		expect(Schema.describe(0 / 0)).toBe("NaN")
		expect(Schema.describe("abc")).toBe('string "abc"')
		expect(Schema.describe(string.rep("x", 40))).toContain("...")
	end)
end)

describe("Schema (adversarial remote input)", function()
	local NUMBER = Schema.number({ min = -1000, max = 1000 })

	it("numbers: NaN, +/-inf, -0, huge, wrong types are handled", function()
		for _, bad in { 0 / 0, math.huge, -math.huge, 1e308 * 10, "1", true, {}, Vector3.new(1, 2, 3), nil } do
			expect(errOf(Schema.number(), bad)).never.toBeNil()
		end
		expect(errOf(Schema.number(), -0)).toBeNil()
		expect(errOf(NUMBER, 1001)).toBe("expected <= 1000, got 1001")
		expect(errOf(Schema.number({ integer = true }), 2 ^ 60)).toBeNil()
		expect(errOf(Schema.number({ integer = true }), 0.5)).toBe("expected integer, got 0.5")
	end)

	it("NaN/inf nested anywhere inside composite values is rejected with a path", function()
		local v = Schema.struct({
			pos = Schema.vector3({ maxMagnitude = 5000 }),
			list = Schema.array(NUMBER, { maxLen = 4 }),
			map = Schema.map(Schema.string({ maxLen = 8 }), NUMBER, { maxLen = 4 }),
		})
		local base = { pos = Vector3.new(1, 2, 3), list = { 1, 2 }, map = { a = 1 } }
		expect(errOf(v, base)).toBeNil()
		expect(errOf(v, { pos = Vector3.new(0 / 0, 0, 0), list = { 1 }, map = {} })).toBe(
			".pos: expected finite Vector3 components"
		)
		expect(errOf(v, { pos = Vector3.new(1, 1, 1), list = { 1, 0 / 0 }, map = {} })).toBe(
			".list[2]: expected finite number, got NaN"
		)
		expect(errOf(v, { pos = Vector3.new(1, 1, 1), list = {}, map = { a = math.huge } })).toBe(
			".map.a: expected finite number, got inf"
		)
		expect(errOf(v, { pos = Vector3.new(1e30, 0, 0), list = {}, map = {} })).toMatch("^%.pos: expected magnitude")
	end)

	it("strings: oversize, invalid UTF-8, embedded NULs and pattern anchoring", function()
		local s = Schema.string({ maxLen = 16, pattern = "^[%w_]+$" })
		expect(errOf(s, string.rep("a", 17))).toBe("expected at most 16 bytes, got 17")
		expect(errOf(Schema.string(), "\255\254")).toBe("expected valid UTF-8 string")
		expect(errOf(s, "ok\0bad")).toBe("string does not match pattern ^[%w_]+$")
		expect(errOf(s, "ok_1")).toBeNil()
		-- Length is checked before UTF-8/pattern work: a 1 MB string fails fast on maxLen.
		expect(errOf(s, string.rep("\255", 1048576))).toBe("expected at most 16 bytes, got 1048576")
	end)

	it("structs reject extra, non-string and missing keys; allowExtra opts out", function()
		local v = Schema.struct({ id = Schema.string({ maxLen = 4 }), n = Schema.optional(NUMBER) })
		expect(errOf(v, { id = "a" })).toBeNil()
		expect(errOf(v, { id = "a", extra = 1 })).toBe('unexpected key string "extra"')
		expect(errOf(v, { id = "a", [1] = "x" })).toBe("unexpected key 1")
		expect(errOf(v, {})).toBe(".id: expected string, got nil")
		expect(errOf(v, { id = "a", n = 0 / 0 })).toBe(".n: expected finite number, got NaN")
		expect(errOf(Schema.struct({ id = Schema.string() }, { allowExtra = true }), { id = "a", extra = 1 })).toBeNil()
		expect(errOf(v, "not a table")).toBe("expected table, got string")
	end)

	it("arrays reject holes, zero/negative/fractional/string keys and oversize", function()
		local a = Schema.array(NUMBER, { maxLen = 3 })
		expect(errOf(a, { 1, nil, 3 } :: any)).never.toBeNil()
		expect(errOf(a, { [0] = 1 })).toBe("expected array, found non-sequential key 0")
		expect(errOf(a, { [-1] = 1 })).toBe("expected array, found non-sequential key -1")
		expect(errOf(a, { [1] = 1, [1.5] = 2 })).toBe("expected array, found non-sequential key 1.5")
		expect(errOf(a, { 1, x = 2 } :: any)).toBe('expected array, found non-sequential key string "x"')
		expect(errOf(a, { 1, 2, 3, 4 })).toBe("expected at most 3 elements, got 4")
		expect(errOf(a, {})).toBeNil()
	end)

	it("maps cap entry counts and validate keys and values", function()
		local m = Schema.map(Schema.string({ maxLen = 3 }), Schema.boolean, { maxLen = 2 })
		expect(errOf(m, { a = true, b = false })).toBeNil()
		expect(errOf(m, { a = true, b = true, c = true })).toBe("expected at most 2 entries")
		expect(errOf(m, { [5] = true })).toBe("key 5: expected string, got number")
		expect(errOf(m, { toolong = true })).toBe('key string "toolong": expected at most 3 bytes, got 7')
		expect(errOf(m, { a = 1 })).toBe(".a: expected boolean, got number")
	end)

	it("enum/literal/oneOf never accept NaN, nil or look-alike types", function()
		local e = Schema.enum({ "AP", "HE", 1 })
		expect(errOf(e, "AP")).toBeNil()
		expect(errOf(e, "ap")).never.toBeNil()
		expect(errOf(e, "1")).never.toBeNil()
		expect(errOf(e, 0 / 0)).never.toBeNil()
		expect(errOf(e, nil)).never.toBeNil()
		expect(errOf(Schema.literal(0 / 0), 0 / 0)).never.toBeNil()
		local o = Schema.oneOf(Schema.string({ maxLen = 2 }), Schema.boolean)
		expect(errOf(o, "abc")).toMatch("no alternative matched")
		expect(errOf(o, false)).toBeNil()
	end)

	it("buffers are length-checked before anything reads them", function()
		local b = Schema.buffer({ maxLen = 8, minLen = 1 })
		expect(errOf(b, buffer.create(9))).toBe("expected at most 8 bytes, got 9")
		expect(errOf(b, buffer.create(0))).toBe("expected at least 1 bytes, got 0")
		expect(errOf(b, "not a buffer")).toBe("expected buffer, got string")
	end)

	it("check() labels nested paths for the client", function()
		local r = Schema.check(
			Schema.struct({ loadout = Schema.array(Schema.struct({ count = Schema.number({ integer = true }) })) }),
			{
				loadout = { { count = 1 }, { count = 2.5 } },
			},
			"arg1"
		)
		expect(r).toBeErr("INVALID_ARGS")
		expect(r.detail).toBe("arg1.loadout[2].count: expected integer, got 2.5")
	end)
end)
