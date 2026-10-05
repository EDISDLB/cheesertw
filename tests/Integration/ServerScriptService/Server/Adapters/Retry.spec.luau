local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Retry = require("@game/ServerScriptService/Server/Adapters/Retry")

describe("Retry", function()
	it("returns the first success without waiting", function()
		local waits = {}
		local ok, value = Retry.call(function()
			return 42
		end, {
			wait = function(s)
				table.insert(waits, s)
			end,
		})
		expect(ok).toBe(true)
		expect(value).toBe(42)
		expect(waits).toEqual({})
	end)

	it("retries transient failures with exponential backoff", function()
		local waits = {}
		local calls = 0
		local ok, value = Retry.call(function()
			calls += 1
			if calls < 3 then
				error("502: API Services rejected request")
			end
			return "done"
		end, {
			attempts = 5,
			baseDelay = 0.5,
			wait = function(s)
				table.insert(waits, s)
			end,
		})
		expect(ok).toBe(true)
		expect(value).toBe("done")
		expect(waits).toEqual({ 0.5, 1 })
	end)

	it("stops on permanent errors and after the last attempt", function()
		local calls = 0
		local ok, err = Retry.call(function()
			calls += 1
			error("105: Serialized value exceeds 4MB limit.", 0)
		end, { wait = function() end })
		expect(ok).toBe(false)
		expect(err).toContain("105")
		expect(calls).toBe(1)
		calls = 0
		local okAll, lastErr = Retry.call(function()
			calls += 1
			error("throttled " .. calls, 0)
		end, { attempts = 3, maxDelay = 1, wait = function() end })
		expect(okAll).toBe(false)
		expect(lastErr).toBe("throttled 3")
		expect(calls).toBe(3)
	end)

	it("classifies Roblox error codes", function()
		expect(Retry.errorCode("502: x")).toBe(502)
		expect(Retry.errorCode("no code")).toBeNil()
		expect(Retry.isTransient("301: GetAsync request dropped")).toBe(true)
		expect(Retry.isTransient("101: Key name can't be empty")).toBe(false)
		expect(Retry.isTransient("403: Studio API access")).toBe(false)
		expect(Retry.isTransient("HTTP 500")).toBe(true)
	end)
end)
