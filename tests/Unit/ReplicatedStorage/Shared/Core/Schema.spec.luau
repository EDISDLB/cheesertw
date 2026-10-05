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
		expect(errOf(Schema.number(), math.huge)).toBe("expected finite number, got number")
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
