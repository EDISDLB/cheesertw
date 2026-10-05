local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local FakeClock = require("@tests/Harness/FakeClock")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ServiceLoader = require("@game/ReplicatedStorage/Shared/Core/ServiceLoader")

-- Builds a service that appends lifecycle events to `log`.
local function service(name: string, log: { string }, extra: { [string]: any }?): any
	local module: any = { Name = name }
	for k, v in extra or {} do
		module[k] = v
	end
	if module.Init == nil then
		module.Init = function(_self, _ctx)
			table.insert(log, "init:" .. name)
		end
	end
	if module.Start == nil then
		module.Start = function()
			table.insert(log, "start:" .. name)
		end
	end
	if module.Stop == nil then
		module.Stop = function()
			table.insert(log, "stop:" .. name)
		end
	end
	return module
end

local capture
Test.beforeEach(function()
	capture = LogCapture.start()
end)
Test.afterEach(function()
	capture:stop()
end)

describe("ServiceLoader ordering", function()
	it("initializes and starts in dependency order with deterministic ties", function()
		local log = {}
		local loader = ServiceLoader.new({ role = "Hub" })
		loader:registerMany({
			service("Progression", log, { Dependencies = { "Data", "Content" } }),
			service("Data", log),
			service("Content", log),
			service("Audit", log, { Dependencies = { "Data" } }),
		})
		loader:boot()
		expect(loader:getOrder()).toEqual({ "Content", "Data", "Audit", "Progression" })
		expect(log).toEqual({
			"init:Content",
			"init:Data",
			"init:Audit",
			"init:Progression",
			"start:Content",
			"start:Data",
			"start:Audit",
			"start:Progression",
		})
	end)

	it("filters by role and treats missing Roles as every role", function()
		local log = {}
		local loader = ServiceLoader.new({ role = "Battle" })
		loader:registerMany({
			service("HubOnly", log, { Roles = { "Hub", "Dev" } }),
			service("BattleOnly", log, { Roles = { "Battle" } }),
			service("Everywhere", log),
		})
		loader:boot()
		expect(loader:getOrder()).toEqual({ "BattleOnly", "Everywhere" })
		expect(loader:getStatus("HubOnly")).toBe("Skipped")
		expect(loader:getStatus("BattleOnly")).toBe("Started")
	end)

	it("reports missing dependencies", function()
		local loader = ServiceLoader.new({ role = "Hub" })
		loader:register(service("A", {}, { Dependencies = { "Ghost" } }))
		expect(function()
			loader:boot()
		end).toThrow('A depends on missing Service "Ghost"')
	end)

	it("explains dependencies that are disabled for the role", function()
		local loader = ServiceLoader.new({ role = "Hub" })
		loader:register(service("A", {}, { Dependencies = { "BattleThing" } }))
		loader:register(service("BattleThing", {}, { Roles = { "Battle" } }))
		expect(function()
			loader:boot()
		end).toThrow('registered but not enabled for role "Hub"')
	end)

	it("detects cycles and prints the chain", function()
		local loader = ServiceLoader.new()
		loader:register(service("A", {}, { Dependencies = { "B" } }))
		loader:register(service("B", {}, { Dependencies = { "C" } }))
		loader:register(service("C", {}, { Dependencies = { "A" } }))
		expect(function()
			loader:boot()
		end).toThrow("dependency cycle: A -> B -> C -> A")
	end)

	it("validates module shape and duplicate names", function()
		local loader = ServiceLoader.new()
		expect(function()
			loader:register({} :: any)
		end).toThrow("missing a string Name")
		expect(function()
			loader:register({ Name = "X", Dependencies = "Y" } :: any)
		end).toThrow("Dependencies must be an array of strings")
		expect(function()
			loader:register({ Name = "X", Init = 5 } :: any)
		end).toThrow("Init must be a function")
		loader:register(service("Dup", {}))
		expect(function()
			loader:register(service("Dup", {}))
		end).toThrow('duplicate Service name "Dup"')
	end)

	it("refuses to register after boot", function()
		local loader = ServiceLoader.new()
		loader:register(service("A", {}))
		loader:boot()
		expect(function()
			loader:register(service("B", {}))
		end).toThrow("cannot register after boot")
	end)
end)

describe("ServiceLoader contexts", function()
	it("gives each service a scoped context sharing services and lifecycle", function()
		local seen = {}
		local loader = ServiceLoader.new({ role = "Dev", context = { role = "Dev", custom = 42 } })
		for _, name in { "A", "B" } do
			loader:register({
				Name = name,
				Init = function(_self, ctx)
					seen[name] = ctx
				end,
			})
		end
		loader:boot()
		expect(seen.A.custom).toBe(42)
		expect(seen.A.role).toBe("Dev")
		expect(seen.A.log.name).toBe("A")
		expect(seen.B.log.name).toBe("B")
		expect(seen.A.services).toBe(seen.B.services)
		expect(seen.A.services.B.Name).toBe("B")
		expect(seen.A.lifecycle).toBe(loader:getLifecycle())
		expect(seen.A.lifecycle.getOrder()).toEqual({ "A", "B" })
	end)
end)

describe("ServiceLoader failures", function()
	it("detects a yielding Init, fails it and skips dependents", function()
		local log = {}
		local failures = {}
		local loader = ServiceLoader.new()
		loader.ServiceFailed:Connect(function(name, phase, err)
			table.insert(failures, { name = name, phase = phase, err = err })
		end)
		loader:registerMany({
			service("Yields", log, {
				Init = function()
					coroutine.yield()
				end,
			}),
			service("Dependent", log, { Dependencies = { "Yields" } }),
			service("Independent", log),
		})
		loader:boot()
		expect(loader:getStatus("Yields")).toBe("Failed")
		expect(loader:getStatus("Dependent")).toBe("Skipped")
		expect(loader:getStatus("Independent")).toBe("Started")
		expect(#failures).toBe(1)
		expect(failures[1].phase).toBe("Init")
		expect(failures[1].err).toContain("Init yielded")
		expect(log).toEqual({ "init:Independent", "start:Independent" })
		expect(loader:getServices().Yields).toBeNil()
	end)

	it("detects a task.wait yield in Init (Roblox-style) and cancels the thread", function()
		local resumed = false
		local loader = ServiceLoader.new({ cancel = task.cancel })
		loader:register({
			Name = "Waits",
			Init = function()
				task.wait(0.01)
				resumed = true
			end,
		})
		loader:boot()
		task.wait(0.05)
		expect(loader:getStatus("Waits")).toBe("Failed")
		expect(resumed).toBe(false)
	end)

	it("reports Init errors with a traceback and continues", function()
		local loader = ServiceLoader.new()
		local failed
		loader.ServiceFailed:Connect(function(name, phase, err)
			failed = { name, phase, err }
		end)
		loader:register({
			Name = "Broken",
			Init = function()
				error("init exploded")
			end,
		})
		loader:register(service("Fine", {}))
		loader:boot()
		expect(failed[1]).toBe("Broken")
		expect(failed[2]).toBe("Init")
		expect(failed[3]).toContain("init exploded")
		expect(loader:getStatus("Fine")).toBe("Started")
		local statuses = loader:getStatuses()
		expect(statuses[1].name).toBe("Broken")
		expect(statuses[1].status).toBe("Failed")
		expect(statuses[1].phase).toBe("Init")
	end)

	it("failFast rethrows Init failures", function()
		local loader = ServiceLoader.new({ failFast = true })
		loader:register({
			Name = "Broken",
			Init = function()
				error("nope")
			end,
		})
		expect(function()
			loader:boot()
		end).toThrow("Broken failed during Init")
	end)

	it("runs each Start in its own thread and reports Start errors", function()
		local log = {}
		local failures = {}
		local loader = ServiceLoader.new()
		loader.ServiceFailed:Connect(function(name, phase)
			table.insert(failures, name .. ":" .. phase)
		end)
		loader:registerMany({
			service("Blocking", log, {
				Start = function()
					table.insert(log, "start:Blocking")
					coroutine.yield() -- never resumed: must not block the next Start
				end,
			}),
			service("Crashing", log, {
				Start = function()
					error("start exploded")
				end,
			}),
			service("Later", log),
		})
		loader:boot()
		expect(log).toEqual({ "init:Blocking", "init:Crashing", "init:Later", "start:Blocking", "start:Later" })
		expect(failures).toEqual({ "Crashing:Start" })
		-- A Start that yields has begun its work (long-running loops): it is reported Started, not Starting forever.
		expect(loader:getStatus("Blocking")).toBe("Started")
		expect(loader:getStatus("Crashing")).toBe("Failed")
		expect(loader:getStatus("Later")).toBe("Started")
	end)

	it("uses the injected spawn for Start", function()
		local spawned = 0
		local loader = ServiceLoader.new({
			spawn = function(fn)
				spawned += 1
				return task.spawn(fn)
			end,
		})
		loader:register(service("A", {}))
		loader:register({ Name = "NoStart" })
		loader:boot()
		expect(spawned).toBe(1)
		expect(loader:getStatus("NoStart")).toBe("Started")
	end)
end)

describe("ServiceLoader stop", function()
	it("stops in reverse order", function()
		local log = {}
		local loader = ServiceLoader.new()
		loader:registerMany({
			service("Data", log),
			service("Progression", log, { Dependencies = { "Data" } }),
		})
		loader:boot()
		table.clear(log)
		local report = loader:stop()
		expect(log).toEqual({ "stop:Progression", "stop:Data" })
		expect(report.stopped).toEqual({ "Progression", "Data" })
		expect(loader:getStatus("Data")).toBe("Stopped")
		expect(loader:stop().stopped).toEqual({})
	end)

	it("waits for yielding Stop methods within the budget", function()
		local log = {}
		local loader = ServiceLoader.new({
			spawn = function(fn)
				return task.spawn(fn)
			end,
			wait = function(seconds)
				task.wait(seconds)
			end,
		})
		loader:registerMany({
			service("Data", log, {
				Stop = function()
					task.wait(0.02)
					table.insert(log, "flushed:Data")
				end,
			}),
			service("Top", log, { Dependencies = { "Data" } }),
		})
		loader:boot()
		table.clear(log)
		local report = loader:stop(5)
		expect(log).toEqual({ "stop:Top", "flushed:Data" })
		expect(report.stopped).toEqual({ "Top", "Data" })
		expect(#report.timedOut).toBe(0)
	end)

	it("gives up on Stop methods that exceed the budget (fake clock)", function()
		local clock = FakeClock.new(0)
		local log = {}
		local loader = ServiceLoader.new({
			clock = clock,
			wait = function(seconds)
				clock:advance(seconds)
			end,
		})
		loader:registerMany({
			service("Hangs", log, {
				Stop = function()
					coroutine.yield() -- never finishes
				end,
			}),
			service("Quick", log),
		})
		loader:boot()
		table.clear(log)
		local report = loader:stop(25)
		expect(report.timedOut).toEqual({ "Hangs" })
		expect(report.stopped).toEqual({ "Quick" })
		expect(report.elapsed).toBeCloseTo(25, 0.06)
		expect(capture:find("warn", "Hangs Stop did not finish")).never.toBeNil()
	end)

	it("reports Stop errors", function()
		local loader = ServiceLoader.new()
		local failures = {}
		loader.ServiceFailed:Connect(function(name, phase)
			table.insert(failures, name .. ":" .. phase)
		end)
		loader:register(service("Bad", {}, {
			Stop = function()
				error("stop exploded")
			end,
		}))
		loader:boot()
		local report = loader:stop()
		expect(report.failed.Bad).toContain("stop exploded")
		expect(failures).toEqual({ "Bad:Stop" })
	end)

	it("does not stop services that failed or were skipped", function()
		local log = {}
		local loader = ServiceLoader.new()
		loader:registerMany({
			service("Broken", log, {
				Init = function()
					error("x")
				end,
			}),
			service("Dependent", log, { Dependencies = { "Broken" } }),
		})
		loader:boot()
		loader:stop()
		expect(log).toEqual({})
	end)
end)

describe("ServiceLoader (adversarial edge cases)", function()
	it("a self-dependency is reported as a cycle", function()
		local loader = ServiceLoader.new()
		loader:register(service("Narcissus", {}, { Dependencies = { "Narcissus" } }))
		expect(function()
			loader:boot()
		end).toThrow("dependency cycle: Narcissus -> Narcissus")
	end)

	it("duplicate dependency entries and diamond graphs init each service exactly once", function()
		local log = {}
		local loader = ServiceLoader.new()
		loader:registerMany({
			service("Top", log, { Dependencies = { "Left", "Right", "Left" } }),
			service("Left", log, { Dependencies = { "Base" } }),
			service("Right", log, { Dependencies = { "Base", "Base" } }),
			service("Base", log),
		})
		loader:boot()
		expect(loader:getOrder()).toEqual({ "Base", "Left", "Right", "Top" })
		local inits = {}
		for _, e in log do
			if string.sub(e, 1, 5) == "init:" then
				table.insert(inits, e)
			end
		end
		expect(inits).toEqual({ "init:Base", "init:Left", "init:Right", "init:Top" })
	end)

	it("an empty Roles list is never active; nil Roles is every role", function()
		local loader = ServiceLoader.new({ role = "Hub" })
		loader:registerMany({ service("Nowhere", {}, { Roles = {} }), service("Everywhere", {}) })
		loader:boot()
		expect(loader:getStatus("Nowhere")).toBe("Skipped")
		expect(loader:getStatus("Everywhere")).toBe("Started")
	end)

	it("a failed Init skips the whole dependent chain but not unrelated services", function()
		local log = {}
		local loader = ServiceLoader.new()
		loader:registerMany({
			service("Broken", log, {
				Init = function()
					error("nope")
				end,
			}),
			service("NeedsBroken", log, { Dependencies = { "Broken" } }),
			service("NeedsNeeds", log, { Dependencies = { "NeedsBroken" } }),
			service("Fine", log),
		})
		loader:boot()
		expect(loader:getStatus("Broken")).toBe("Failed")
		expect(loader:getStatus("NeedsBroken")).toBe("Skipped")
		expect(loader:getStatus("NeedsNeeds")).toBe("Skipped")
		expect(loader:getStatus("Fine")).toBe("Started")
		expect(loader:getServices().NeedsNeeds).toBeNil()
		expect(loader:getServices().Fine).never.toBeNil()
	end)

	it("cannot register after resolveOrder, and init twice is refused", function()
		local loader = ServiceLoader.new()
		loader:register(service("A", {}))
		loader:resolveOrder()
		expect(function()
			loader:register(service("B", {}))
		end).toThrow("cannot register after boot started")
		loader:init()
		expect(function()
			loader:init()
		end).toThrow("init() called twice")
	end)

	it("stop() is idempotent and stop() before boot is a no-op", function()
		local fresh = ServiceLoader.new()
		local report = fresh:stop(1)
		expect(report.stopped).toEqual({})
		local log = {}
		local loader = ServiceLoader.new()
		loader:register(service("A", log))
		loader:boot()
		expect(loader:stop(1).stopped).toEqual({ "A" })
		expect(loader:stop(1).stopped).toEqual({})
		local stops = 0
		for _, e in log do
			if e == "stop:A" then
				stops += 1
			end
		end
		expect(stops).toBe(1)
	end)

	it("a service whose Start yields forever is still stopped (it was reported Started)", function()
		local log = {}
		local loader = ServiceLoader.new()
		loader:register(service("Loop", log, {
			Start = function()
				coroutine.yield()
			end,
		}))
		loader:boot()
		expect(loader:getStatus("Loop")).toBe("Started")
		expect(loader:stop(1).stopped).toEqual({ "Loop" })
		expect(loader:getStatus("Loop")).toBe("Stopped")
	end)

	it("an Init that yields via coroutine.yield is cancelled and never resumes later", function()
		local resumedLater = false
		local loader = ServiceLoader.new({
			cancel = function(thread)
				coroutine.close(thread)
			end,
		})
		loader:register({
			Name = "Sneaky",
			Init = function()
				coroutine.yield()
				resumedLater = true
			end,
		})
		loader:boot()
		expect(loader:getStatus("Sneaky")).toBe("Failed")
		expect(resumedLater).toBe(false)
	end)
end)
