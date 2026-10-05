local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

local describe, it, expect = Test.describe, Test.it, Test.expect

describe("State.Value", function()
	it("gets, sets and updates", function()
		local v = State.Value(1)
		expect(v:get()).toBe(1)
		v:set(5)
		expect(v:peek()).toBe(5)
		v:update(function(x)
			return x * 2
		end)
		expect(v:get()).toBe(10)
	end)

	it("notifies only on real changes (NaN-safe), tables always re-notify", function()
		local v = State.Value(1)
		local calls = 0
		local connection = v:onChange(function()
			calls += 1
		end)
		v:set(1)
		expect(calls).toBe(0)
		v:set(2)
		expect(calls).toBe(1)
		v:set(0 / 0)
		v:set(0 / 0)
		expect(calls).toBe(2)
		v:set(2, true)
		v:set(2, true)
		expect(calls).toBe(4)
		connection:Disconnect()

		local t = { a = 1 }
		local tv = State.Value(t)
		local tableCalls = 0
		tv:onChange(function()
			tableCalls += 1
		end)
		t.a = 2
		tv:set(t)
		expect(tableCalls).toBe(1)
	end)

	it("supports custom equality", function()
		local v = State.Value({ a = 1 }, { equals = State.shallowEqual })
		local calls = 0
		v:onChange(function()
			calls += 1
		end)
		v:set({ a = 1 })
		expect(calls).toBe(0)
		v:set({ a = 2 })
		expect(calls).toBe(1)
		local r = State.Value({}, { equals = State.referenceEqual })
		local rCalls = 0
		r:onChange(function()
			rCalls += 1
		end)
		r:set(r:peek())
		expect(rCalls).toBe(0)
	end)

	it("passes (new, old) to onChange and stops after Disconnect", function()
		local v = State.Value("a")
		local seen = {}
		local connection = v:onChange(function(new, old)
			table.insert(seen, old .. ">" .. new)
		end)
		v:set("b")
		v:set("c")
		connection:Disconnect()
		v:set("d")
		expect(seen).toEqual({ "a>b", "b>c" })
		expect(connection.Connected).toBe(false)
	end)
end)

describe("State.Computed", function()
	it("is lazy and caches", function()
		local a = State.Value(2)
		local runs = 0
		local double = State.Computed(function()
			runs += 1
			return a:get() * 2
		end)
		expect(runs).toBe(0)
		expect(double:get()).toBe(4)
		expect(double:get()).toBe(4)
		expect(runs).toBe(1)
		a:set(3)
		expect(runs).toBe(1)
		expect(double:get()).toBe(6)
		expect(runs).toBe(2)
	end)

	it("tracks dependencies dynamically (switching branches drops old dependencies)", function()
		local useA = State.Value(true)
		local a = State.Value("A")
		local b = State.Value("B")
		local runs = 0
		local pick = State.Computed(function()
			runs += 1
			return if useA:get() then a:get() else b:get()
		end)
		expect(pick:get()).toBe("A")
		useA:set(false)
		expect(pick:get()).toBe("B")
		local before = runs
		a:set("A2")
		expect(pick:get()).toBe("B")
		expect(runs).toBe(before)
		b:set("B2")
		expect(pick:get()).toBe("B2")
	end)

	it("is glitch-free in a diamond and recomputes each node once", function()
		local a = State.Value(1)
		local bRuns, cRuns, dRuns = 0, 0, 0
		local b = State.Computed(function()
			bRuns += 1
			return a:get() + 1
		end)
		local c = State.Computed(function()
			cRuns += 1
			return a:get() * 10
		end)
		local d = State.Computed(function()
			dRuns += 1
			return { b = b:get(), c = c:get() }
		end)
		local observed = {}
		local connection = d:onChange(function(new)
			table.insert(observed, `{new.b},{new.c}`)
		end)
		expect(dRuns).toBe(1)
		a:set(2)
		expect(observed).toEqual({ "3,20" })
		expect(bRuns).toBe(2)
		expect(cRuns).toBe(2)
		expect(dRuns).toBe(2)
		connection:Disconnect()
	end)

	it("stops propagation when a Computed's result does not change", function()
		local n = State.Value(1)
		local parity = State.Computed(function()
			return n:get() % 2
		end)
		local downstreamRuns = 0
		local label = State.Computed(function()
			downstreamRuns += 1
			return if parity:get() == 0 then "even" else "odd"
		end)
		local changes = 0
		label:onChange(function()
			changes += 1
		end)
		local runsAfterBind = downstreamRuns
		n:set(3)
		expect(downstreamRuns).toBe(runsAfterBind)
		expect(changes).toBe(0)
		n:set(4)
		expect(label:get()).toBe("even")
		expect(changes).toBe(1)
	end)

	it("passes the previous value and runs cleanup on replace and destroy", function()
		local n = State.Value(1)
		local cleaned = {}
		local seenPrevious = {}
		local c = State.Computed(function(previous)
			table.insert(seenPrevious, previous or 0)
			return n:get() * 100
		end, {
			cleanup = function(old)
				table.insert(cleaned, old)
			end,
		})
		expect(c:get()).toBe(100)
		n:set(2)
		expect(c:get()).toBe(200)
		expect(seenPrevious).toEqual({ 0, 100 })
		expect(cleaned).toEqual({ 100 })
		c:Destroy()
		expect(cleaned).toEqual({ 100, 200 })
		n:set(3)
		expect(c:get()).toBe(200)
	end)

	it("keeps the previous value and logs when the computation throws", function()
		local capture = LogCapture.start()
		local n = State.Value(1)
		local c = State.Computed(function()
			if n:get() == 2 then
				error("boom")
			end
			return n:get()
		end)
		expect(c:get()).toBe(1)
		n:set(2)
		expect(c:get()).toBe(1)
		expect(capture:find("error", "boom")).never.toBeNil()
		n:set(3)
		expect(c:get()).toBe(3)
		capture:stop()
	end)

	it("detects cyclic dependencies", function()
		local capture = LogCapture.start()
		local cyclic
		cyclic = State.Computed(function()
			return (cyclic :: any):get()
		end)
		cyclic:get()
		expect(capture:find("error", "cyclic dependency")).never.toBeNil()
		capture:stop()
	end)

	it("refuses to set Values inside a Computed", function()
		local capture = LogCapture.start()
		local v = State.Value(0)
		local bad = State.Computed(function()
			v:set(1)
			return 1
		end)
		bad:get()
		expect(capture:find("error", "cannot set a Value inside Computed")).never.toBeNil()
		expect(v:peek()).toBe(0)
		capture:stop()
	end)
end)

describe("State observers and effects", function()
	it("onBind fires immediately with (current, current)", function()
		local v = State.Value(7)
		local observer = State.Observer(v)
		local seen = {}
		observer:onBind(function(new, old)
			table.insert(seen, { new, old })
		end)
		v:set(8)
		expect(seen).toEqual({ { 7, 7 }, { 8, 7 } })
		observer:Destroy()
		v:set(9)
		expect(#seen).toBe(2)
	end)

	it("observe supports immediate and scope", function()
		local trove = Trove.new()
		local v = State.Value(1)
		local seen = {}
		State.observe(v, function(new)
			table.insert(seen, new)
		end, { immediate = true, scope = trove })
		v:set(2)
		trove:Destroy()
		v:set(3)
		expect(seen).toEqual({ 1, 2 })
	end)

	it("effect re-runs on change and runs cleanups", function()
		local v = State.Value("x")
		local log = {}
		local connection = State.effect(function()
			local current = v:get()
			table.insert(log, "run " .. current)
			return function()
				table.insert(log, "cleanup " .. current)
			end
		end)
		v:set("y")
		connection:Disconnect()
		v:set("z")
		expect(log).toEqual({ "run x", "cleanup x", "run y", "cleanup y" })
	end)

	it("callbacks are untracked", function()
		local a = State.Value(1)
		local b = State.Value(1)
		local calls = 0
		a:onChange(function()
			calls += 1
			b:get()
		end)
		a:set(2)
		b:set(2)
		expect(calls).toBe(1)
	end)

	it("logs effect errors and keeps running other effects", function()
		local capture = LogCapture.start()
		local v = State.Value(0)
		local okRuns = 0
		State.effect(function()
			if v:get() == 1 then
				error("effect exploded")
			end
		end)
		State.effect(function()
			v:get()
			okRuns += 1
		end)
		v:set(1)
		expect(okRuns).toBe(2)
		expect(capture:find("error", "effect exploded")).never.toBeNil()
		capture:stop()
	end)

	it("guards against effects that re-trigger themselves forever", function()
		local v = State.Value(0)
		local connection = State.effect(function()
			local n = v:get()
			if n > 0 then
				v:set(n + 1)
			end
		end)
		expect(function()
			v:set(1)
		end).toThrow("effect runs")
		connection:Disconnect()
	end)

	it("effects may set other Values; dependents update in the same flush", function()
		local source = State.Value(1)
		local mirror = State.Value(0)
		State.effect(function()
			mirror:set(source:get() * 3)
		end)
		local seen = {}
		mirror:onChange(function(new)
			table.insert(seen, new)
		end)
		source:set(2)
		expect(mirror:peek()).toBe(6)
		expect(seen).toEqual({ 6 })
	end)
end)

describe("State.batch", function()
	it("coalesces sets into one flush and reads see new values", function()
		local a = State.Value(1)
		local b = State.Value(2)
		local sum = State.Computed(function()
			return a:get() + b:get()
		end)
		local seen = {}
		sum:onChange(function(new)
			table.insert(seen, new)
		end)
		State.batch(function()
			a:set(10)
			expect(sum:get()).toBe(12)
			b:set(20)
			State.batch(function()
				a:set(100)
			end)
			expect(#seen).toBe(0)
		end)
		expect(seen).toEqual({ 120 })
	end)

	it("still flushes and rethrows when the batch errors", function()
		local a = State.Value(1)
		local seen = {}
		a:onChange(function(new)
			table.insert(seen, new)
		end)
		expect(function()
			State.batch(function()
				a:set(2)
				error("inside batch")
			end)
		end).toThrow("inside batch")
		expect(seen).toEqual({ 2 })
		expect(State.stats().batchDepth).toBe(0)
	end)
end)

describe("State helpers", function()
	it("get/peek accept constants and states; isState; map; of; untracked", function()
		local v = State.Value(3)
		expect(State.peek(5)).toBe(5)
		expect(State.peek(v)).toBe(3)
		expect(State.isState(v)).toBe(true)
		expect(State.isState({})).toBe(false)
		expect(State.isState(5)).toBe(false)
		local doubled = State.map(v, function(x)
			return x * 2
		end)
		expect(doubled:get()).toBe(6)
		v:set(4)
		expect(doubled:get()).toBe(8)
		local wrapped = State.of(9)
		expect(State.isState(wrapped)).toBe(true)
		expect(wrapped:get()).toBe(9)
		expect(State.of(v)).toBe(v)
		local runs = 0
		local c = State.Computed(function()
			runs += 1
			return State.untracked(function()
				return v:get()
			end)
		end)
		c:get()
		v:set(5)
		c:get()
		expect(runs).toBe(1)
		expect(State.readonly(v)).toBe(v)
	end)

	it("scoped constructors die with their trove", function()
		local baseline = State.stats().liveEffects
		local trove = Trove.new()
		local s = State.scoped(trove)
		local v = s.Value(1)
		local c = s.Computed(function()
			return v:get() + 1
		end)
		local seen = {}
		s.observe(c, function(new)
			table.insert(seen, new)
		end)
		s.effect(function()
			c:get()
		end)
		expect(State.stats().liveEffects).toBe(baseline + 2)
		v:set(2)
		trove:Destroy()
		expect(State.stats().liveEffects).toBe(baseline)
		v:set(3)
		expect(seen).toEqual({ 3 })
	end)
end)

describe("State leak-freedom", function()
	it("unreferenced Computeds are collected from their sources' observer sets", function()
		local source = State.Value(1)
		do
			local derived = State.Computed(function()
				return source:get() + 1
			end)
			derived:get()
		end
		local observers = rawget(source :: any, "_observers")
		expect(observers).never.toBeNil()
		local function count(): number
			local n = 0
			for _ in observers do
				n += 1
			end
			return n
		end
		expect(count()).toBe(1)
		-- Luau only exposes collectgarbage("count"): create allocation pressure until the incremental GC runs.
		local sink = {}
		for i = 1, 400 do
			for j = 1, 500 do
				sink[j] = table.create(64, i)
			end
			if count() == 0 then
				break
			end
		end
		expect(count()).toBe(0)
	end)

	it("destroyed Computeds unlink and stop recomputing", function()
		local source = State.Value(1)
		local runs = 0
		local derived = State.Computed(function()
			runs += 1
			return source:get()
		end)
		derived:get()
		derived:Destroy()
		source:set(2)
		expect(derived:get()).toBe(1)
		expect(runs).toBe(1)
		local observers = rawget(source :: any, "_observers")
		expect(observers[derived]).toBeNil()
	end)

	it("observers release their root when the last listener disconnects", function()
		local baseline = State.stats().liveEffects
		local v = State.Value(1)
		local c1 = v:onChange(function() end)
		local observer = State.Observer(v)
		local c2 = observer:onChange(function() end)
		local c3 = observer:onChange(function() end)
		expect(State.stats().liveEffects).toBe(baseline + 2)
		c1:Disconnect()
		c2:Disconnect()
		expect(State.stats().liveEffects).toBe(baseline + 1)
		c3:Disconnect()
		expect(State.stats().liveEffects).toBe(baseline)
	end)

	it("bindEffect is not rooted and stops when disposed", function()
		local baseline = State.stats().liveEffects
		local v = State.Value(1)
		local seen = {}
		local dispose = State.bindEffect(function()
			table.insert(seen, v:get())
		end)
		expect(State.stats().liveEffects).toBe(baseline)
		v:set(2)
		dispose()
		v:set(3)
		expect(seen).toEqual({ 1, 2 })
	end)
end)

describe("State.list", function()
	it("renders once per key, updates items in place and destroys removed entries", function()
		local items = State.Value({ { id = "a", n = 1 }, { id = "b", n = 2 } })
		local renders = 0
		local destroyed = {}
		local list = State.list(items, function(item)
			return item.id
		end, function(item, index, scope)
			renders += 1
			local id = item:peek().id
			local row = { id = id, n = item:peek().n, index = index:peek() }
			scope:Add(function()
				table.insert(destroyed, id)
			end)
			State.observe(item, function(new)
				row.n = new.n
			end, { scope = scope })
			State.observe(index, function(new)
				row.index = new
			end, { scope = scope })
			return row
		end)
		local first = list:get()
		expect(#first).toBe(2)
		expect(renders).toBe(2)
		items:set({ { id = "b", n = 20 }, { id = "c", n = 3 }, { id = "a", n = 1 } })
		local second = list:get()
		expect(renders).toBe(3)
		expect(second[1]).toBe(first[2])
		expect(second[3]).toBe(first[1])
		expect(second[1].n).toBe(20)
		expect(second[1].index).toBe(1)
		expect(second[3].index).toBe(3)
		items:set({ { id = "c", n = 3 } })
		expect(destroyed).toEqual({ "a", "b" })
		list:Destroy()
		expect(destroyed).toEqual({ "a", "b", "c" })
	end)

	it("falls back to the index for duplicate keys", function()
		local capture = LogCapture.start()
		local list = State.list({ 1, 1, 2 }, function(item)
			return item
		end, function(item)
			return item:peek()
		end)
		expect(list:get()).toEqual({ 1, 1, 2 })
		expect(capture:find("warn", "duplicate key")).never.toBeNil()
		capture:stop()
	end)
end)
