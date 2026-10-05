local Test = require("@tests/Harness/Test")
local FakeClock = require("@tests/Harness/FakeClock")
local LogCapture = require("@tests/Harness/LogCapture")
local MockPlayersAdapter = require("@tests/Harness/Mocks/MockPlayersAdapter")
local describe, it, expect = Test.describe, Test.it, Test.expect

local NetServer = require("@game/ReplicatedStorage/Shared/Net/NetServer")
local Schema = require("@game/ReplicatedStorage/Shared/Core/Schema")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")

local REGISTRY = {
	{
		name = "Move",
		kind = "Event",
		direction = "C2S",
		rate = { perSecond = 1, burst = 2 },
		args = { Schema.number({ min = -1, max = 1 }), Schema.optional(Schema.string({ maxLen = 4 })) },
	},
	{
		name = "Input",
		kind = "Unreliable",
		direction = "C2S",
		rate = { perSecond = 30, burst = 30 },
		args = { Schema.buffer({ maxLen = 16 }) },
	},
	{
		name = "Buy",
		kind = "Function",
		direction = "C2S",
		rate = { perSecond = 5, burst = 5 },
		args = { Schema.string({ maxLen = 8 }) },
	},
	{
		name = "Admin",
		kind = "Function",
		direction = "C2S",
		devOnly = true,
		rate = { perSecond = 5, burst = 5 },
		args = {},
	},
	{ name = "Notice", kind = "Event", direction = "S2C" },
	{ name = "Snapshot", kind = "Unreliable", direction = "S2C" },
}

local clock, net, violations, player, capture, rs

local function newNet(extra: { [string]: any }?)
	local options: { [string]: any } = { registry = REGISTRY, clock = clock }
	for k, v in extra or {} do
		options[k] = v
	end
	local server = NetServer.new(options :: any)
	server:setViolationHandler(function(p, reason, weight, detail)
		table.insert(violations, { player = p, reason = reason, weight = weight, detail = detail })
	end)
	return server
end

local function remote(name: string): any
	return game:GetService("ReplicatedStorage").Remotes[name]
end

Test.beforeEach(function()
	capture = LogCapture.start()
	rs = game:GetService("RunService")
	rs:setServer(true)
	rs:setStudio(false)
	clock = FakeClock.new(0)
	violations = {}
	local players = game:GetService("Players")
	player = players:GetPlayerByUserId(1) or players:addPlayer({ UserId = 1 })
	net = newNet()
end)

Test.afterEach(function()
	net:destroy()
	capture:stop()
end)

describe("NetServer setup", function()
	it("refuses to run on the client", function()
		net:destroy()
		rs:setServer(false)
		expect(function()
			NetServer.new({ registry = REGISTRY })
		end).toThrow("only be used on the server")
		rs:setServer(true)
		net = newNet()
	end)

	it("creates the Remotes folder with one instance per entry", function()
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		expect(folder).never.toBeNil()
		expect(remote("Move").ClassName).toBe("RemoteEvent")
		expect(remote("Input").ClassName).toBe("UnreliableRemoteEvent")
		expect(remote("Buy").ClassName).toBe("RemoteFunction")
		expect(#folder:GetChildren()).toBe(#REGISTRY)
		expect(net:getRemote("Move")).toBe(remote("Move"))
		expect(net:getRemote("Nope")).toBeNil()
	end)

	it("refuses a second Remotes folder", function()
		expect(function()
			NetServer.new({ registry = REGISTRY })
		end).toThrow("already exists")
	end)

	it("destroy removes the folder", function()
		net:destroy()
		expect(game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")).toBeNil()
		net = newNet()
	end)
end)

describe("NetServer C2S events", function()
	it("delivers validated arguments to the handler", function()
		local got
		net:on("Move", function(p, axis, tag)
			got = { p, axis, tag }
		end)
		remote("Move"):_simulateFireServer(player, 0.5, "w")
		expect(got[1]).toBe(player)
		expect(got[2]).toBe(0.5)
		expect(got[3]).toBe("w")
		expect(#violations).toBe(0)
	end)

	it("drops invalid arguments and reports INVALID_ARGS with a path", function()
		local calls = 0
		net:on("Move", function()
			calls += 1
		end)
		remote("Move"):_simulateFireServer(player, 5)
		remote("Move"):_simulateFireServer(player, 0 / 0)
		clock:advance(1) -- stay under the 2-call burst
		remote("Move"):_simulateFireServer(player, 0, "toolong")
		expect(calls).toBe(0)
		expect(#violations).toBe(3)
		expect(violations[1].reason).toBe("INVALID_ARGS")
		expect(violations[1].weight).toBe(NetServer.VIOLATION_WEIGHTS.INVALID_ARGS)
		expect(violations[1].detail).toBe("Move: arg1: expected <= 1, got 5")
		expect(violations[3].detail).toBe("Move: arg2: expected at most 4 bytes, got 7")
	end)

	it("rejects extra arguments", function()
		net:on("Move", function() end)
		remote("Move"):_simulateFireServer(player, 0, "a", "extra")
		expect(violations[1].detail).toBe("Move: expected at most 2 arguments, got 3")
	end)

	it("rate limits per player per remote and refills over time", function()
		local calls = 0
		net:on("Move", function()
			calls += 1
		end)
		for _ = 1, 5 do
			remote("Move"):_simulateFireServer(player, 0)
		end
		expect(calls).toBe(2)
		expect(#violations).toBe(3)
		expect(violations[1].reason).toBe("RATE_LIMITED")
		local other = game:GetService("Players"):addPlayer({ UserId = 2 })
		remote("Move"):_simulateFireServer(other, 0)
		expect(calls).toBe(3)
		clock:advance(1)
		remote("Move"):_simulateFireServer(player, 0)
		expect(calls).toBe(4)
		other:Kick("done")
	end)

	it("reports clients firing server-to-client remotes", function()
		remote("Notice"):_simulateFireServer(player, "spoof")
		expect(violations[1].reason).toBe("PROTOCOL_VIOLATION")
		expect(violations[1].weight).toBe(NetServer.VIOLATION_WEIGHTS.PROTOCOL_VIOLATION)
	end)

	it("logs handler errors without crashing", function()
		net:on("Move", function()
			error("handler exploded")
		end)
		remote("Move"):_simulateFireServer(player, 0)
		expect(capture:find("error", "handler exploded")).never.toBeNil()
	end)

	it("validates binary payloads on unreliable remotes", function()
		local got
		net:on("Input", function(_, payload)
			got = buffer.len(payload)
		end)
		remote("Input"):_simulateFireServer(player, buffer.create(8))
		remote("Input"):_simulateFireServer(player, buffer.create(64))
		expect(got).toBe(8)
		expect(violations[1].detail).toBe("Input: arg1: expected at most 16 bytes, got 64")
	end)

	it("enforces one handler per remote and supports disconnecting it", function()
		local calls = 0
		local handle = net:on("Move", function()
			calls += 1
		end)
		expect(function()
			net:on("Move", function() end)
		end).toThrow("already registered")
		handle:Disconnect()
		remote("Move"):_simulateFireServer(player, 0)
		expect(calls).toBe(0)
		net:on("Move", function()
			calls += 1
		end)
		remote("Move"):_simulateFireServer(player, 0)
		expect(calls).toBe(1)
	end)

	it("rejects misuse of the registration API", function()
		expect(function()
			net:on("Nope", function() end)
		end).toThrow('unknown remote "Nope"')
		expect(function()
			net:on("Buy", function() end)
		end).toThrow("use onInvoke")
		expect(function()
			net:on("Notice", function() end)
		end).toThrow("requires a C2S")
		expect(function()
			net:onInvoke("Move", function()
				return Result.ok(nil)
			end)
		end).toThrow("requires a Function remote")
	end)
end)

describe("NetServer C2S functions", function()
	it("returns the handler's Result", function()
		net:onInvoke("Buy", function(_, item)
			if item == "tank" then
				return Result.ok({ bought = item })
			end
			return Result.err("NOT_FOUND", item)
		end)
		expect(remote("Buy"):_simulateInvokeServer(player, "tank")).toEqual({ ok = true, value = { bought = "tank" } })
		expect(remote("Buy"):_simulateInvokeServer(player, "boat")).toEqual({
			ok = false,
			err = "NOT_FOUND",
			detail = "boat",
		})
	end)

	it("answers NOT_READY before a handler exists", function()
		expect(remote("Buy"):_simulateInvokeServer(player, "x")).toBeErr("NOT_READY")
	end)

	it("answers INVALID_ARGS and RATE_LIMITED without calling the handler", function()
		local calls = 0
		net:onInvoke("Buy", function()
			calls += 1
			return Result.ok(true)
		end)
		local bad = remote("Buy"):_simulateInvokeServer(player, 42)
		expect(bad).toBeErr("INVALID_ARGS")
		expect(bad.detail).toBe("arg1: expected string, got number")
		for _ = 1, 4 do
			remote("Buy"):_simulateInvokeServer(player, "x")
		end
		expect(remote("Buy"):_simulateInvokeServer(player, "x")).toBeErr("RATE_LIMITED")
		expect(calls).toBe(4)
	end)

	it("maps handler errors and non-Result returns to INTERNAL", function()
		net:onInvoke("Buy", function(_, item)
			if item == "boom" then
				error("kaboom")
			end
			return "not a result" :: any
		end)
		expect(remote("Buy"):_simulateInvokeServer(player, "boom")).toBeErr("INTERNAL")
		expect(remote("Buy"):_simulateInvokeServer(player, "x")).toBeErr("INTERNAL")
		expect(capture:find("error", "kaboom")).never.toBeNil()
		expect(capture:find("error", "non-Result")).never.toBeNil()
	end)

	it("gates devOnly remotes with the developer check", function()
		net:onInvoke("Admin", function()
			return Result.ok("secret")
		end)
		expect(remote("Admin"):_simulateInvokeServer(player)).toBeErr("NOT_ALLOWED")
		expect(violations[1].reason).toBe("NOT_ALLOWED")
		expect(net:isDeveloper(player)).toBe(false)
		net:setDeveloperCheck(function(p)
			return p.UserId == 1
		end)
		expect(net:isDeveloper(player)).toBe(true)
		expect(remote("Admin"):_simulateInvokeServer(player)).toBeOk()
		net:setDeveloperCheck(function()
			error("check broke")
		end)
		expect(remote("Admin"):_simulateInvokeServer(player)).toBeErr("NOT_ALLOWED")
		expect(net:isDeveloper(player)).toBe(false)
	end)

	it("uses Studio as the default developer check", function()
		net:destroy()
		rs:setStudio(true)
		net = newNet()
		expect(net:isDeveloper(player)).toBe(true)
	end)
end)

describe("NetServer S2C", function()
	it("fires to one player, a list, or everyone", function()
		local other = game:GetService("Players"):addPlayer({ UserId = 3 })
		net:fire("Notice", player, { message = "hi" })
		net:fireList("Notice", { player, other }, "list")
		net:fireAll("Notice", "all")
		net:fire("Snapshot", player, buffer.create(4))
		local sent = remote("Notice")._sent
		expect(#sent).toBe(4)
		expect(sent[1].kind).toBe("FireClient")
		expect(sent[1].player).toBe(player)
		expect(sent[1].args[1]).toEqual({ message = "hi" })
		expect(sent[3].player).toBe(other)
		expect(sent[4].kind).toBe("FireAllClients")
		expect(#remote("Snapshot")._sent).toBe(1)
		other:Kick("done")
	end)

	it("refuses to fire client-to-server remotes", function()
		expect(function()
			net:fire("Move", player, 1)
		end).toThrow("requires an S2C")
		expect(function()
			net:fireAll("Buy")
		end).toThrow("requires an S2C")
	end)
end)

describe("NetServer player lifecycle", function()
	it("forgets rate-limit state when a player leaves", function()
		net:destroy()
		local adapter = MockPlayersAdapter.new()
		net = newNet({ players = adapter })
		local calls = 0
		net:on("Move", function()
			calls += 1
		end)
		local p = adapter:addPlayer({ UserId = 50 })
		for _ = 1, 3 do
			remote("Move"):_simulateFireServer(p, 0)
		end
		expect(calls).toBe(2)
		adapter:removePlayer(p)
		remote("Move"):_simulateFireServer(p, 0)
		expect(calls).toBe(3)
		net:forgetPlayer(p)
	end)
end)

describe("NetServer security (adversarial)", function()
	local function ownerCount(server: any): number
		local n = 0
		for _ in server._limiter._owners do
			n += 1
		end
		return n
	end

	it("no handler ever sees NaN, inf, wrong types, oversized strings or extra arguments", function()
		local seen = {}
		net:on("Move", function(_, axis, tag)
			table.insert(seen, { axis, tag })
		end)
		local P = table.pack
		local hostile = {
			P(0 / 0),
			P(math.huge),
			P(-math.huge),
			P("0.5"),
			P(true),
			P({}),
			P(Vector3.new(0, 0, 0)),
			P(0, string.rep("x", 5)),
			P(0, 5),
			P(0, "\255"),
			P(0, nil, "extra"),
		}
		for _, args in hostile do
			clock:advance(10) -- refill so every call reaches validation
			remote("Move"):_simulateFireServer(player, table.unpack(args, 1, args.n))
		end
		expect(seen).toEqual({})
		expect(#violations).toBe(#hostile)
		for i, v in violations do
			expect(v.reason).toBe("INVALID_ARGS")
			-- Only the last case is rejected for its argument count; all others by a validator.
			if i < #hostile then
				expect(v.detail).toMatch("^Move: arg[12]")
			end
		end
	end)

	it("rate limits are per player AND per remote (one spammer cannot starve others)", function()
		local moves, buys = 0, 0
		net:on("Move", function()
			moves += 1
		end)
		net:onInvoke("Buy", function()
			buys += 1
			return Result.ok(true)
		end)
		local victim = game:GetService("Players"):addPlayer({ UserId = 3 })
		for _ = 1, 50 do
			remote("Move"):_simulateFireServer(player, 0)
		end
		expect(moves).toBe(2)
		expect(remote("Buy"):_simulateInvokeServer(player, "x")).toBeOk() -- other remote: own bucket
		remote("Move"):_simulateFireServer(victim, 0) -- other player: own bucket
		expect(moves).toBe(3)
		expect(buys).toBe(1)
		victim:Kick("done")
	end)

	it("rate limiting happens before validation and handlers (floods cost one bucket check each)", function()
		local validations = 0
		net:destroy()
		net = newNet({
			registry = {
				{
					name = "Probe",
					kind = "Event",
					direction = "C2S",
					rate = { perSecond = 0, burst = 1 },
					args = {
						function(_v: any): (boolean, string?)
							validations += 1
							return true, nil
						end :: any,
					},
				},
			},
		})
		net:on("Probe", function() end)
		for _ = 1, 100 do
			remote("Probe"):_simulateFireServer(player, 1)
		end
		expect(validations).toBe(1)
		expect(#violations).toBe(99)
	end)

	it("leaves no per-player state behind after players leave (no leak across many sessions)", function()
		net:destroy()
		local adapter = MockPlayersAdapter.new()
		net = newNet({ players = adapter })
		net:on("Move", function() end)
		for i = 1, 25 do
			local p = adapter:addPlayer({ UserId = 1000 + i })
			remote("Move"):_simulateFireServer(p, 0)
			adapter:removePlayer(p)
		end
		expect(ownerCount(net)).toBe(0)
	end)

	it("clients can neither fire nor invoke server-to-client remotes", function()
		remote("Notice"):_simulateFireServer(player, "spoof")
		remote("Snapshot"):_simulateFireServer(player, buffer.create(4))
		expect(#violations).toBe(2)
		for _, v in violations do
			expect(v.reason).toBe("PROTOCOL_VIOLATION")
		end
		expect(remote("Notice").ClassName).toBe("RemoteEvent") -- no OnServerInvoke surface exists
		expect(remote("Notice").OnServerInvoke).toBeNil()
	end)

	it("a slow Function handler does not block other invocations (each call has its own thread)", function()
		local order = {}
		net:onInvoke("Buy", function(_, item)
			if item == "slow" then
				task.wait(0.05)
			end
			table.insert(order, item)
			return Result.ok(item)
		end)
		local other = game:GetService("Players"):addPlayer({ UserId = 4 })
		task.spawn(function()
			remote("Buy"):_simulateInvokeServer(player, "slow")
		end)
		local fast = remote("Buy"):_simulateInvokeServer(other, "fast")
		expect(fast).toBeOk()
		expect(order).toEqual({ "fast" })
		task.wait(0.1)
		expect(order).toEqual({ "fast", "slow" })
		other:Kick("done")
	end)

	it("handler errors never leak server details to the client", function()
		net:onInvoke("Buy", function()
			error("secret: DataStore key Profiles/123 failed at line 42")
		end)
		local result = remote("Buy"):_simulateInvokeServer(player, "x")
		expect(result).toBeErr("INTERNAL")
		expect(result.detail).toBeNil()
	end)

	it("a developer check or violation handler that throws fails closed without breaking the gate", function()
		net:setDeveloperCheck(function(): boolean
			error("group service down")
		end)
		net:setViolationHandler(function()
			error("anti-exploit crashed")
		end)
		net:onInvoke("Admin", function()
			return Result.ok("admin")
		end)
		expect(remote("Admin"):_simulateInvokeServer(player)).toBeErr("NOT_ALLOWED")
		expect(capture:find("error", "violation handler failed")).never.toBeNil()
	end)
end)
