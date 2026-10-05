-- Regression specs for defects found in the adversarial review of the foundation layer (one describe per defect).
-- Each test failed (or hung / crashed) before its fix.
local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local FakeClock = require("@tests/Harness/FakeClock")
local Loader = require("@tests/Harness/Loader")
local ServerHarness = require("@tests/Harness/ServerHarness")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local TableUtil = require("@game/ReplicatedStorage/Shared/Core/TableUtil")
local Schema = require("@game/ReplicatedStorage/Shared/Core/Schema")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local ServiceLoader = require("@game/ReplicatedStorage/Shared/Core/ServiceLoader")
local RateLimiter = require("@game/ReplicatedStorage/Shared/Security/RateLimiter")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local NetServer = require("@game/ReplicatedStorage/Shared/Net/NetServer")
local NetClient = require("@game/ReplicatedStorage/Shared/Net/NetClient")
local Remotes = require("@game/ReplicatedStorage/Shared/Net/Remotes")
local BufferWriter = require("@game/ReplicatedStorage/Shared/Net/Codecs/BufferWriter")
local BufferReader = require("@game/ReplicatedStorage/Shared/Net/Codecs/BufferReader")
local Retry = require("@game/ServerScriptService/Server/Adapters/Retry")
local RobloxDataStore = require("@game/ServerScriptService/Server/Adapters/RobloxDataStore")
local HealthService = require("@game/ServerScriptService/Server/Services/HealthService")
local DebugService = require("@game/ServerScriptService/Server/Services/DebugService")

local capture

Test.beforeEach(function()
	capture = LogCapture.start()
end)

Test.afterEach(function()
	capture:stop()
end)

-- Roblox RBXScriptConnection stand-in: a userdata (not a table) whose methods come from its metatable.
local function userdataConnection(): (any, () -> boolean)
	local disconnected = false
	local proxy = newproxy(true)
	getmetatable(proxy).__index = function(_, key)
		if key == "Disconnect" then
			return function()
				disconnected = true
			end
		elseif key == "Connected" then
			return not disconnected
		end
		error(`{key} is not a valid member of RBXScriptConnection`, 2)
	end
	return proxy, function()
		return disconnected
	end
end

describe("Trove with engine (userdata) connections [High]", function()
	it("trove:Connect tracks an RBXScriptSignal connection and disconnects it on Clean", function()
		local connection, isDisconnected = userdataConnection()
		local rbxSignal = {
			Connect = function(_self, _fn)
				return connection
			end,
		}
		local trove = Trove.new()
		expect(trove:Connect(rbxSignal, function() end)).toBe(connection)
		expect(isDisconnected()).toBe(false)
		trove:Clean()
		expect(isDisconnected()).toBe(true)
	end)

	it("Add with an explicit method works for userdata and rejects missing members cleanly", function()
		local connection, isDisconnected = userdataConnection()
		local trove = Trove.new()
		trove:Add(connection, "Disconnect")
		expect(function()
			trove:Add(connection, "Destroy")
		end).toThrow('has no method "Destroy"')
		trove:Destroy()
		expect(isDisconnected()).toBe(true)
	end)

	it("refuses to add a trove to itself", function()
		local trove = Trove.new()
		expect(function()
			trove:Add(trove)
		end).toThrow("to itself")
	end)
end)

describe("NetServer validators that throw [Medium]", function()
	local throwing = function(value: any): (boolean, string?)
		return value.x > 0, nil -- indexes nil -> throws on hostile input
	end :: any
	local truthyString = function(_value: any): any
		return "oops, returned a message instead of false"
	end :: any

	local container, server, violations, player
	Test.beforeEach(function()
		local rs = game:GetService("RunService")
		rs:setServer(true)
		container = Instance.new("Folder")
		violations = {}
		server = NetServer.new({
			container = container,
			clock = FakeClock.new(0),
			registry = {
				{ name = "Ev", kind = "Event", direction = "C2S", args = { throwing } },
				{ name = "Fn", kind = "Function", direction = "C2S", args = { throwing } },
				{ name = "Truthy", kind = "Function", direction = "C2S", args = { truthyString } },
			},
		})
		server:setViolationHandler(function(_p, reason)
			table.insert(violations, reason)
		end)
		local players = game:GetService("Players")
		player = players:GetPlayerByUserId(901) or players:addPlayer({ UserId = 901 })
	end)
	Test.afterEach(function()
		server:destroy()
	end)

	it("Function remotes answer Err(INVALID_ARGS) instead of throwing to the client", function()
		local called = false
		server:onInvoke("Fn", function()
			called = true
			return Result.ok(true)
		end)
		local result = container.Remotes.Fn:_simulateInvokeServer(player, nil)
		expect(result).toBeErr("INVALID_ARGS")
		expect(called).toBe(false)
		expect(violations).toEqual({ "INVALID_ARGS" })
		expect(capture:find("error", "validator for Fn arg1 threw")).never.toBeNil()
	end)

	it("Event remotes are dropped and reported as a strike", function()
		local called = false
		server:on("Ev", function()
			called = true
		end)
		container.Remotes.Ev:_simulateFireServer(player, nil)
		expect(called).toBe(false)
		expect(violations).toEqual({ "INVALID_ARGS" })
	end)

	it("only an explicit `true` passes (a validator returning a message string fails closed)", function()
		server:onInvoke("Truthy", function()
			return Result.ok(true)
		end)
		expect(container.Remotes.Truthy:_simulateInvokeServer(player, 1)).toBeErr("INVALID_ARGS")
	end)

	it("NetClient never throws on a throwing validator either", function()
		local rs = game:GetService("RunService")
		rs:setClient(true)
		local client = NetClient.new({
			container = container,
			registry = { { name = "Fn", kind = "Function", direction = "C2S", args = { throwing } } },
		})
		local result = client:invoke("Fn", nil)
		expect(result).toBeErr("INVALID_ARGS")
		expect(result.detail).toContain("validator error")
		client:destroy()
	end)
end)

describe("TableUtil.diff on cyclic data [Medium]", function()
	it("fails fast with a clear error instead of overflowing the stack", function()
		local old: any = { name = "old" }
		old.self = old
		local new: any = { name = "new" }
		new.self = new
		local started = os.clock()
		expect(function()
			TableUtil.diff(old, new)
		end).toThrow("cyclic table at /self")
		expect(os.clock() - started).toBeLessThan(1)
	end)

	it("does not report aliasing between the two trees as a cycle", function()
		local new: any = { a = { v = 2 } }
		local old: any = { a = new } -- old.a is the new root (aliased, not cyclic)
		local patches = TableUtil.diff(old, new)
		local target = TableUtil.deepCopy(old)
		TableUtil.applyPatches(target, patches)
		expect(target).toEqual({ a = { v = 2 } })
	end)

	it("shares of the same (even cyclic) table produce no patches", function()
		local shared: any = { x = 1 }
		shared.loop = shared
		expect(TableUtil.diff({ s = shared }, { s = shared })).toEqual({})
	end)
end)

describe("ServiceLoader status of a yielding Start [Low]", function()
	it("is Started once Start has begun, and Failed if it errors after yielding", function()
		local resume: thread? = nil
		local loader = ServiceLoader.new()
		loader:register({
			Name = "Loop",
			Start = function()
				resume = coroutine.running()
				coroutine.yield()
				error("loop crashed later")
			end,
		})
		loader:boot()
		expect(loader:getStatus("Loop")).toBe("Started")
		coroutine.resume(resume :: thread)
		expect(loader:getStatus("Loop")).toBe("Failed")
		expect(capture:find("error", "loop crashed later")).never.toBeNil()
	end)
end)

describe("Signal:Wait with a cancelled waiter [Low]", function()
	it("drops the waiter silently instead of logging a resume error", function()
		local signal = Signal.new()
		local waiter = task.spawn(function()
			signal:Wait()
		end)
		task.cancel(waiter)
		signal:Fire("late")
		expect(capture:count("error")).toBe(0)
	end)
end)

describe("Schema.array maxLen before scanning [Low]", function()
	it("rejects oversized tables by length first (no full key scan of hostile input)", function()
		local hostile: any = { 1, 2, 3, 4, 5 }
		hostile.extra = true
		local ok, err = Schema.array(Schema.number(), { maxLen = 2 })(hostile)
		expect(ok).toBe(false)
		expect(err).toBe("expected at most 2 elements, got 5")
	end)

	it("stops scanning once more than maxLen keys were seen (border-less tables)", function()
		local hostile: any = { [1] = 1 }
		for i = 1, 1000 do
			hostile["k" .. i] = i
		end
		local ok, err = Schema.array(Schema.number(), { maxLen = 4 })(hostile)
		expect(ok).toBe(false)
		expect(err).toMatch("expected")
	end)
end)

describe("RateLimiter cost validation [Low]", function()
	it("rejects negative, NaN and infinite costs (a negative cost minted tokens)", function()
		local limiter = RateLimiter.new(FakeClock.new(0))
		local rate = { perSecond = 0, burst = 1 }
		for _, bad in { -5, 0 / 0, math.huge } do
			expect(function()
				limiter:consume("p", "x", rate, bad)
			end).toThrow("cost must be a finite number")
		end
		expect(limiter:consume("p", "x", rate, 0)).toBe(true)
		expect(limiter:consume("p", "x", rate)).toBe(true)
		expect(limiter:consume("p", "x", rate)).toBe(false)
		expect(limiter:remaining("p", "x", rate)).toBe(0)
	end)
end)

describe("Config.applyOverrides with empty tables [Low]", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	it("rejects an empty table where a number is expected (was silently Ok)", function()
		local result = Config.applyOverrides({ Battle = { TICK_RATE = {} } } :: any)
		expect(result).toBeErr("INVALID_ARGS")
		expect(result.detail).toContain("Battle.TICK_RATE: expected a finite number")
		expect(Config.Battle.TICK_RATE).toBe(30)
	end)

	it("still accepts an empty section as 'no overrides'", function()
		local result = Config.applyOverrides({ Battle = {} })
		expect(result).toBeOk()
		expect(result.value).toEqual({})
	end)
end)

describe("DebugService developer cache after a quick leave [Low]", function()
	it("does not cache developers whose group lookup finishes after they left", function()
		local config = {
			DevAccess = {
				GROUP_ID = 77,
				isAllowed = function(_userId: number, rank: number?, isStudio: boolean): boolean
					return isStudio or (rank or 0) >= 200
				end,
			},
		}
		local h = ServerHarness.boot({ modules = { HealthService, DebugService }, config = config })
		local players = h.adapters.players
		players.getGroupRankAsync = function(_self: any, _userId: number, _groupId: number): (boolean, any)
			task.wait(0.02) -- the web call yields
			return true, 255
		end
		local player = players:addPlayer({ UserId = 950 })
		players:removePlayer(player)
		task.wait(0.05)
		expect(DebugService._devCache[950]).toBeNil()
		h.shutdown()
	end)
end)

describe("RNG.hash of NaN [Low]", function()
	it("does not depend on the NaN bit pattern (x86 and ARM produce different NaNs)", function()
		local nan = 0 / 0
		expect(RNG.hash(nan)).toBe(RNG.hash(-nan))
		expect(RNG.hash(nan, "a")).toBe(RNG.hash(-nan, "a"))
		expect(RNG.hash(nan)).never.toBe(RNG.hash(0))
	end)
end)

describe("Retry permanent codes [Low]", function()
	it("does not retry 509 OperationNotAllowed or Studio without API access", function()
		expect(Retry.isTransient("509: Data store operations are blocked on a personal RCC")).toBe(false)
		expect(Retry.isTransient("Studio access to APIs is not allowed.")).toBe(false)
		expect(Retry.isTransient("502: API Services rejected request")).toBe(true)
	end)
end)

describe("Remote registry validation [Low]", function()
	it("rejects NaN rates (they passed the < 0 checks and made RateLimiter throw inside the gate)", function()
		local base = { name = "X", kind = "Event", direction = "C2S", args = {} }
		for _, rate in { { perSecond = 0 / 0, burst = 1 }, { perSecond = 1, burst = 0 / 0 } } do
			local spec = table.clone(base) :: any
			spec.rate = rate
			local ok, err = Remotes.validateSpec(spec)
			expect(ok).toBe(false)
			expect(err).toContain("rate must have")
		end
	end)

	it("NetServer.new validates custom registries like Net/Remotes entries", function()
		game:GetService("RunService"):setServer(true)
		expect(function()
			NetServer.new({
				container = Instance.new("Folder"),
				registry = { { name = "NoArgs", kind = "Event", direction = "C2S" } } :: any,
			})
		end).toThrow("C2S remotes must declare args validators")
		expect(function()
			NetServer.new({
				container = Instance.new("Folder"),
				registry = { { name = "Push", kind = "Function", direction = "S2C" } } :: any,
			})
		end).toThrow("Function remotes must be C2S")
	end)
end)

describe("RobloxDataStore request budget categories [Medium]", function()
	-- Fake enum that throws on unknown members, like Roblox enums.
	local function fakeEnum(names: { string }): any
		local items = {}
		for _, name in names do
			items[name] = { Name = name }
		end
		return setmetatable({}, {
			__index = function(_, key)
				local item = items[key]
				if item == nil then
					error(`{key} is not a valid member of DataStoreRequestType`, 2)
				end
				return item
			end,
		})
	end

	it("uses the Standard* categories when the engine has them", function()
		local types = RobloxDataStore.resolveRequestTypes(fakeEnum({
			"GetAsync",
			"SetIncrementAsync",
			"ListAsync",
			"GetVersionAsync",
			"StandardRead",
			"StandardWrite",
			"StandardList",
			"StandardRemove",
		}))
		expect(types.read.Name).toBe("StandardRead")
		expect(types.write.Name).toBe("StandardWrite")
		expect(types.remove.Name).toBe("StandardRemove")
		expect(types.list.Name).toBe("StandardList")
		expect(types.version.Name).toBe("StandardRead")
	end)

	it("falls back to the legacy categories on older reflection data", function()
		local types = RobloxDataStore.resolveRequestTypes(
			fakeEnum({ "GetAsync", "SetIncrementAsync", "ListAsync", "GetVersionAsync" })
		)
		expect(types.read.Name).toBe("GetAsync")
		expect(types.write.Name).toBe("SetIncrementAsync")
		expect(types.remove.Name).toBe("SetIncrementAsync")
		expect(types.list.Name).toBe("ListAsync")
		expect(types.version.Name).toBe("GetVersionAsync")
	end)
end)

describe("BufferReader finite reads for untrusted packets [Low]", function()
	local function packet(write: (any) -> ()): any
		local w = BufferWriter.new()
		write(w)
		return BufferReader.new(w:toBuffer())
	end

	it("readFiniteF32 rejects NaN, infinities and values above maxAbs", function()
		expect(packet(function(w)
			w:writeF32(1.5)
		end):readFiniteF32()).toBe(1.5)
		for _, bad in { 0 / 0, math.huge, -math.huge } do
			expect(function()
				packet(function(w)
					w:writeF32(bad)
				end):readFiniteF32()
			end).toThrow("readFiniteF32 rejected")
		end
		expect(function()
			packet(function(w)
				w:writeF32(1000)
			end):readFiniteF32(500)
		end).toThrow("readFiniteF32 rejected")
	end)

	it("readFiniteVector3 rejects NaN/inf components and enforces maxAbs", function()
		local ok = packet(function(w)
			w:writeVector3(Vector3.new(1, 2, 3))
		end):readFiniteVector3(10)
		expect(ok).toBeCloseTo(Vector3.new(1, 2, 3))
		expect(function()
			packet(function(w)
				w:writeVector3(Vector3.new(0, 0 / 0, 0))
			end):readFiniteVector3()
		end).toThrow("readFiniteVector3 rejected")
		expect(function()
			packet(function(w)
				w:writeVector3(Vector3.new(0, 0, 2000))
			end):readFiniteVector3(1000)
		end).toThrow("readFiniteVector3 rejected")
	end)
end)

describe("Test harness robustness [Low/Medium]", function()
	-- A fresh Loader gives a fresh Test module (its own suite tree) so the harness can be exercised in isolation.
	local function freshTest(): any
		local loader = Loader.new()
		return loader:require("@tests/Harness/Test")
	end

	it("runs afterEach hooks even when a beforeEach hook fails", function()
		local T = freshTest()
		local events = {}
		T.describe("suite", function()
			T.beforeEach(function()
				table.insert(events, "before")
				error("setup failed")
			end)
			T.afterEach(function()
				table.insert(events, "after")
			end)
			T.it("body", function()
				table.insert(events, "body")
			end)
		end)
		local result = T.run({ timeout = 1 })
		expect(result.failed).toBe(1)
		expect(result.failures[1].message).toContain("setup failed")
		expect(events).toEqual({ "before", "after" })
	end)

	it("flags focused files so the runner can reject a committed .only", function()
		local T = freshTest()
		T.it.only("focused", function() end)
		T.it("silently skipped", function()
			error("never runs")
		end)
		local result = T.run({ timeout = 1 })
		expect(result.focused).toBe(true)
		expect(result.skipped).toBe(1)

		local U = freshTest()
		U.it("plain", function() end)
		expect(U.run({ timeout = 1 }).focused).toBe(false)
	end)
end)
