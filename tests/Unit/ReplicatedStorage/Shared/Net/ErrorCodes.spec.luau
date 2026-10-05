local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")

describe("ErrorCodes", function()
	it("every code equals its key, is SCREAMING_SNAKE and has a message", function()
		local all = ErrorCodes.all()
		expect(#all).toBeGreaterThan(10)
		local messages = ErrorCodes.messages()
		for _, code in all do
			expect((ErrorCodes :: any)[code]).toBe(code)
			expect(code).toMatch("^[A-Z][A-Z_]*$")
			expect(messages[code]).never.toBeNil()
		end
	end)

	it("includes the foundation codes", function()
		for _, code in
			{
				"RATE_LIMITED",
				"INVALID_ARGS",
				"NOT_FOUND",
				"NOT_ALLOWED",
				"INSUFFICIENT_FUNDS",
				"INTERNAL",
				"NOT_READY",
				"DUPLICATE_REQUEST",
				"TIMEOUT",
			}
		do
			expect(ErrorCodes.isKnown(code)).toBe(true)
		end
		expect(ErrorCodes.isKnown("NOPE")).toBe(false)
		expect(ErrorCodes.isKnown(5)).toBe(false)
		expect(ErrorCodes.isKnown("isKnown")).toBe(false)
	end)

	it("falls back to INTERNAL's message and is frozen", function()
		expect(ErrorCodes.message("NOPE")).toBe(ErrorCodes.message("INTERNAL"))
		expect(table.isfrozen(ErrorCodes)).toBe(true)
	end)
end)
