--[[
	Test — minimal BDD test framework for HULLDOWN Lune specs.

	Purpose:          describe/it/hooks + `expect` matchers; one instance per spec file (fresh loader cache).
	Dependencies:     task (injected by the Loader) for test timeouts.
	State:            The suite tree collected while the spec file executes; results after Test.run().
	Validation:       Matchers validate their inputs (e.g. toThrow requires a function) and fail loudly.
	Error handling:   Each test runs in its own thread under xpcall; failures record message + spec location.
	Performance notes: Synchronous tests never touch the scheduler; only yielding tests are polled.

	Usage (spec files):
		local Test = require("@tests/Harness/Test")
		local describe, it, expect = Test.describe, Test.it, Test.expect
		describe("Thing", function()
			Test.beforeEach(function() ... end)
			it("works", function() expect(1 + 1).toBe(2) end)
			it.skip("later", function() end)
			it.only("focus", function() end)   -- focus while iterating only: the runner fails focused files
		end)

	Matchers (all support `.never`): toBe, toEqual (deep, readable diff), toBeCloseTo(n, eps?), toBeNil, toBeTruthy,
	toBeFalsy, toBeGreaterThan, toBeGreaterThanOrEqual, toBeLessThan, toBeLessThanOrEqual, toContain, toHaveLength,
	toThrow(substring?), toBeOk(), toBeErr(code?), toBeType(typeName), toMatch(luaPattern).
]]

local Test = {}

type Hook = () -> ()

type TestCase = {
	kind: "test",
	name: string,
	fn: Hook?,
	skip: boolean,
	only: boolean,
	parent: Suite,
}

type Suite = {
	kind: "suite",
	name: string,
	parent: Suite?,
	children: { any },
	beforeEach: { Hook },
	afterEach: { Hook },
	beforeAll: { Hook },
	afterAll: { Hook },
	skip: boolean,
	only: boolean,
}

export type Failure = { name: string, message: string, location: string? }
export type RunResult = {
	passed: number,
	failed: number,
	skipped: number,
	failures: { Failure },
	tests: { { name: string, status: string, ms: number } },
	--- True when the file used it.only / describe.only (the runner rejects focused files unless allowed).
	focused: boolean,
}

local function newSuite(name: string, parent: Suite?): Suite
	return {
		kind = "suite",
		name = name,
		parent = parent,
		children = {},
		beforeEach = {},
		afterEach = {},
		beforeAll = {},
		afterAll = {},
		skip = false,
		only = false,
	}
end

local root = newSuite("", nil)
local current = root
local collecting = true
local hasOnly = false

--------------------------------------------------------------------------------
-- Value formatting and deep comparison
--------------------------------------------------------------------------------

local function isArray(t: { [any]: any }): boolean
	local n = #t
	local count = 0
	for _ in t do
		count += 1
	end
	return count == n
end

local function sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then
			return ta < tb
		end
		if ta == "number" or ta == "string" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function format(value: any, depth: number?): string
	local d = depth or 0
	local t = type(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "table" then
		local mt = getmetatable(value)
		if type(mt) == "table" and (rawget(mt, "__tostring") ~= nil or rawget(mt, "__type") ~= nil) then
			return tostring(value)
		end
		if d >= 3 then
			return "{...}"
		end
		local parts = {}
		if isArray(value) then
			for i, v in value do
				if i > 12 then
					table.insert(parts, `...({#value} items)`)
					break
				end
				table.insert(parts, format(v, d + 1))
			end
		else
			local keys = sortedKeys(value)
			for i, k in keys do
				if i > 12 then
					table.insert(parts, `...({#keys} keys)`)
					break
				end
				local keyText = if type(k) == "string" and string.match(k, "^[%a_][%w_]*$")
					then k
					else "[" .. format(k, d + 1) .. "]"
				table.insert(parts, keyText .. " = " .. format(value[k], d + 1))
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif t == "number" then
		if value ~= value then
			return "nan"
		end
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return string.format("%.10g", value)
	end
	return tostring(value)
end

Test.format = format

local function pathText(path: { any }): string
	if #path == 0 then
		return "(root)"
	end
	local out = ""
	for _, k in path do
		if type(k) == "string" and string.match(k, "^[%a_][%w_]*$") then
			out ..= "." .. k
		else
			out ..= "[" .. format(k) .. "]"
		end
	end
	return out
end

local function collectDiffs(expected: any, received: any, path: { any }, out: { string }, seen: { [any]: any })
	if #out >= 12 then
		return
	end
	if expected == received then
		return
	end
	if type(expected) == "number" and type(received) == "number" and expected ~= expected and received ~= received then
		return
	end
	if type(expected) ~= "table" or type(received) ~= "table" then
		table.insert(out, `{pathText(path)}: expected {format(expected)}, received {format(received)}`)
		return
	end
	local mte, mtr = getmetatable(expected), getmetatable(received)
	if mte ~= mtr then
		table.insert(out, `{pathText(path)}: metatables differ`)
		return
	end
	if seen[expected] == received then
		return
	end
	seen[expected] = received
	for _, k in sortedKeys(expected) do
		local child = table.clone(path)
		table.insert(child, k)
		if received[k] == nil then
			table.insert(out, `{pathText(child)}: missing in received (expected {format(expected[k])})`)
		else
			collectDiffs(expected[k], received[k], child, out, seen)
		end
		if #out >= 12 then
			return
		end
	end
	for _, k in sortedKeys(received) do
		if expected[k] == nil then
			local child = table.clone(path)
			table.insert(child, k)
			table.insert(out, `{pathText(child)}: unexpected in received ({format(received[k])})`)
			if #out >= 12 then
				return
			end
		end
	end
end

local function deepDiff(expected: any, received: any): { string }
	local out = {}
	collectDiffs(expected, received, {}, out, {})
	return out
end

Test.deepEqual = function(a: any, b: any): boolean
	return #deepDiff(a, b) == 0
end

--------------------------------------------------------------------------------
-- expect
--------------------------------------------------------------------------------

-- Failures carry no position prefix; the runner locates the failing spec line from the stack instead.
local function fail(message: string)
	error(message, 0)
end

local function closeTo(a: any, b: any, eps: number): (boolean, number)
	local ta, tb = typeof(a), typeof(b)
	if ta == "number" and tb == "number" then
		local diff = math.abs(a - b)
		return diff <= eps, diff
	elseif (ta == "Vector3" and tb == "Vector3") or (ta == "Vector2" and tb == "Vector2") then
		local diff = (a - b).Magnitude
		return diff <= eps, diff
	elseif ta == "CFrame" and tb == "CFrame" then
		local ca = table.pack(a:GetComponents())
		local cb = table.pack(b:GetComponents())
		local worst = 0
		for i = 1, 12 do
			worst = math.max(worst, math.abs(ca[i] - cb[i]))
		end
		return worst <= eps, worst
	end
	return false, math.huge
end

local function errorText(err: any): string
	if type(err) == "table" and err.message ~= nil then
		return tostring(err.message)
	end
	return tostring(err)
end

local function buildMatchers(received: any, negated: boolean)
	local m = {}
	local notText = if negated then " not" else ""

	local function check(pass: boolean, message: string)
		if pass == negated then
			fail(message)
		end
	end

	function m.toBe(expected: any)
		local same = received == expected
			or (
				type(received) == "number"
				and type(expected) == "number"
				and received ~= received
				and expected ~= expected
			)
		check(same, `expected {format(received)}{notText} to be {format(expected)}`)
	end

	function m.toEqual(expected: any)
		local diffs = deepDiff(expected, received)
		if negated then
			check(#diffs == 0, `expected {format(received)} not to deep-equal {format(expected)}`)
		elseif #diffs > 0 then
			fail("expected values to be deeply equal:\n  " .. table.concat(diffs, "\n  "))
		end
	end

	function m.toBeCloseTo(expected: any, eps: number?)
		local tolerance = eps or 1e-6
		local ok, diff = closeTo(received, expected, tolerance)
		check(ok, `expected {format(received)}{notText} to be within {tolerance} of {format(expected)} (diff {diff})`)
	end

	function m.toBeNil()
		check(received == nil, `expected {format(received)}{notText} to be nil`)
	end

	function m.toBeTruthy()
		check(not not received, `expected {format(received)}{notText} to be truthy`)
	end

	function m.toBeFalsy()
		check(not received, `expected {format(received)}{notText} to be falsy`)
	end

	local function numeric(op: string, expected: number, pass: (number, number) -> boolean)
		if type(received) ~= "number" or type(expected) ~= "number" then
			fail(`{op}: expected numbers, got {format(received)} and {format(expected)}`)
		end
		check(pass(received, expected), `expected {format(received)}{notText} to be {op} {format(expected)}`)
	end

	function m.toBeGreaterThan(expected: number)
		numeric(">", expected, function(a, b)
			return a > b
		end)
	end

	function m.toBeGreaterThanOrEqual(expected: number)
		numeric(">=", expected, function(a, b)
			return a >= b
		end)
	end

	function m.toBeLessThan(expected: number)
		numeric("<", expected, function(a, b)
			return a < b
		end)
	end

	function m.toBeLessThanOrEqual(expected: number)
		numeric("<=", expected, function(a, b)
			return a <= b
		end)
	end

	function m.toContain(item: any)
		if type(received) == "string" then
			check(
				type(item) == "string" and string.find(received, item, 1, true) ~= nil,
				`expected {format(received)}{notText} to contain {format(item)}`
			)
		elseif type(received) == "table" then
			local found = false
			for _, v in received do
				if v == item then
					found = true
					break
				end
			end
			check(found, `expected {format(received)}{notText} to contain {format(item)}`)
		else
			fail(`toContain: expected a table or string, got {format(received)}`)
		end
	end

	function m.toHaveLength(n: number)
		if type(received) ~= "table" and type(received) ~= "string" then
			fail(`toHaveLength: expected a table or string, got {format(received)}`)
		end
		local len = #received
		check(len == n, `expected length {len}{notText} to be {n} ({format(received)})`)
	end

	function m.toThrow(substring: string?)
		if type(received) ~= "function" then
			fail(`toThrow: expected a function, got {format(received)}`)
		end
		local ok, err = pcall(received)
		if negated then
			if not ok then
				fail(`expected function not to throw, but it threw: {errorText(err)}`)
			end
			return
		end
		if ok then
			fail(
				if substring
					then `expected function to throw "{substring}", but it did not`
					else "expected function to throw"
			)
		end
		if substring ~= nil then
			local text = errorText(err)
			if string.find(text, substring, 1, true) == nil then
				fail(`expected error containing "{substring}", got: {text}`)
			end
		end
	end

	function m.toBeOk()
		local isResult = type(received) == "table" and type(received.ok) == "boolean"
		if not isResult then
			fail(`toBeOk: expected a Result, got {format(received)}`)
		end
		check(
			received.ok == true,
			if negated
				then `expected Result not to be ok, got {format(received)}`
				else `expected Result to be ok, got err {format(received.err)} (detail: {format(received.detail)})`
		)
	end

	function m.toBeErr(code: string?)
		local isResult = type(received) == "table" and type(received.ok) == "boolean"
		if not isResult then
			fail(`toBeErr: expected a Result, got {format(received)}`)
		end
		local pass = received.ok == false and (code == nil or received.err == code)
		check(pass, `expected Result{notText} to be err{if code then " " .. code else ""}, got {format(received)}`)
	end

	function m.toBeType(typeName: string)
		local actual = typeof(received)
		check(actual == typeName, `expected type {actual}{notText} to be {typeName}`)
	end

	function m.toMatch(pattern: string)
		if type(received) ~= "string" then
			fail(`toMatch: expected a string, got {format(received)}`)
		end
		check(string.match(received, pattern) ~= nil, `expected {format(received)}{notText} to match {format(pattern)}`)
	end

	return m
end

function Test.expect(received: any)
	local matchers = buildMatchers(received, false)
	matchers.never = buildMatchers(received, true)
	return matchers
end

--------------------------------------------------------------------------------
-- Spies
--------------------------------------------------------------------------------

export type Spy = {
	fn: (...any) -> ...any,
	calls: { { n: number, [number]: any } },
	count: (self: Spy) -> number,
	reset: (self: Spy) -> (),
}

function Test.spy(impl: ((...any) -> ...any)?): Spy
	local spy = {} :: Spy
	spy.calls = {}
	spy.fn = function(...)
		table.insert(spy.calls, table.pack(...))
		if impl then
			return impl(...)
		end
		return
	end
	function spy.count(self: Spy)
		return #self.calls
	end
	function spy.reset(self: Spy)
		table.clear(self.calls)
	end
	return spy
end

--------------------------------------------------------------------------------
-- Collection API
--------------------------------------------------------------------------------

local function assertCollecting(what: string)
	if not collecting then
		error(`Test.{what} must be called while the spec file is loading (not inside a running test)`, 3)
	end
end

local function addSuite(name: string, fn: () -> (), skip: boolean, only: boolean)
	assertCollecting("describe")
	local suite = newSuite(name, current)
	suite.skip = skip
	suite.only = only
	if only then
		hasOnly = true
	end
	table.insert(current.children, suite)
	local previous = current
	current = suite
	local ok, err = pcall(fn)
	current = previous
	if not ok then
		-- Surface describe-body errors as a failing test so they are never silently ignored.
		table.insert(suite.children, {
			kind = "test",
			name = "(describe body)",
			fn = function()
				error(err, 0)
			end,
			skip = false,
			only = false,
			parent = suite,
		})
	end
end

local function addTest(name: string, fn: Hook?, skip: boolean, only: boolean)
	assertCollecting("it")
	if only then
		hasOnly = true
	end
	table.insert(current.children, {
		kind = "test",
		name = name,
		fn = fn,
		skip = skip,
		only = only,
		parent = current,
	})
end

Test.describe = setmetatable({
	skip = function(name: string, fn: () -> ())
		addSuite(name, fn, true, false)
	end,
	only = function(name: string, fn: () -> ())
		addSuite(name, fn, false, true)
	end,
}, {
	__call = function(_, name: string, fn: () -> ())
		addSuite(name, fn, false, false)
	end,
})

Test.it = setmetatable({
	skip = function(name: string, fn: Hook?)
		addTest(name, fn, true, false)
	end,
	only = function(name: string, fn: Hook)
		addTest(name, fn, false, true)
	end,
}, {
	__call = function(_, name: string, fn: Hook)
		addTest(name, fn, false, false)
	end,
})

Test.test = Test.it

function Test.beforeEach(fn: Hook)
	assertCollecting("beforeEach")
	table.insert(current.beforeEach, fn)
end

function Test.afterEach(fn: Hook)
	assertCollecting("afterEach")
	table.insert(current.afterEach, fn)
end

function Test.beforeAll(fn: Hook)
	assertCollecting("beforeAll")
	table.insert(current.beforeAll, fn)
end

function Test.afterAll(fn: Hook)
	assertCollecting("afterAll")
	table.insert(current.afterAll, fn)
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function fullName(test: TestCase): string
	local parts = { test.name }
	local suite: Suite? = test.parent
	while suite ~= nil and suite.parent ~= nil do
		table.insert(parts, 1, suite.name)
		suite = suite.parent
	end
	return table.concat(parts, " > ")
end

local function findSpecLocation(): string?
	for level = 2, 40 do
		local source, line = debug.info(level, "sl")
		if source == nil then
			break
		end
		if string.find(source, "%.spec%.luau$") and line and line > 0 then
			return `{string.gsub(source, "^@", "")}:{line}`
		end
	end
	return nil
end

local function errorHandler(err: any)
	if type(err) == "table" and err.__testInfo == true then
		return err
	end
	return {
		__testInfo = true,
		message = errorText(err),
		location = findSpecLocation(),
		traceback = debug.traceback("", 2),
	}
end

-- Runs fn in its own thread; waits (polling) when it yields. Returns (ok, errInfo).
local function runIsolated(fn: () -> (), timeout: number): (boolean, any)
	local done = false
	local okResult, errResult = true, nil
	local thread = task.spawn(function()
		local ok, err = xpcall(fn, errorHandler)
		okResult, errResult = ok, err
		done = true
	end)
	if done then
		return okResult, errResult
	end
	local started = os.clock()
	while not done do
		if os.clock() - started > timeout then
			pcall(task.cancel, thread)
			return false, { message = `timed out after {timeout}s (test yielded and never resumed)` }
		end
		task.wait()
	end
	return okResult, errResult
end

local function suiteSelected(suite: Suite?): boolean
	while suite ~= nil do
		if suite.only then
			return true
		end
		suite = suite.parent
	end
	return false
end

local function suiteSkipped(suite: Suite?): boolean
	while suite ~= nil do
		if suite.skip then
			return true
		end
		suite = suite.parent
	end
	return false
end

local function shouldRun(test: TestCase): boolean
	if test.skip or test.fn == nil or suiteSkipped(test.parent) then
		return false
	end
	if hasOnly then
		return test.only or suiteSelected(test.parent)
	end
	return true
end

local function countRunnable(suite: Suite): number
	local n = 0
	for _, child in suite.children do
		if child.kind == "suite" then
			n += countRunnable(child)
		elseif shouldRun(child) then
			n += 1
		end
	end
	return n
end

local function hookChain(suite: Suite, field: "beforeEach" | "afterEach"): { Hook }
	local chain = {}
	local s: Suite? = suite
	local suites = {}
	while s ~= nil do
		table.insert(suites, 1, s)
		s = s.parent
	end
	if field == "beforeEach" then
		for _, x in suites do
			for _, h in x.beforeEach do
				table.insert(chain, h)
			end
		end
	else
		for i = #suites, 1, -1 do
			for _, h in suites[i].afterEach do
				table.insert(chain, h)
			end
		end
	end
	return chain
end

export type RunOptions = { timeout: number? }

function Test.run(options: RunOptions?): RunResult
	collecting = false
	local timeout = if options and options.timeout then options.timeout else 10
	local result: RunResult = { passed = 0, failed = 0, skipped = 0, failures = {}, tests = {}, focused = hasOnly }

	local function recordFailure(name: string, info: any)
		result.failed += 1
		local message = if type(info) == "table" then info.message else tostring(info)
		local location = if type(info) == "table" then info.location else nil
		table.insert(result.failures, { name = name, message = message, location = location })
	end

	local function runSuite(suite: Suite)
		local runnable = countRunnable(suite)
		local beforeAllFailed: any = nil
		if runnable > 0 then
			for _, hook in suite.beforeAll do
				local ok, err = runIsolated(hook, timeout)
				if not ok then
					beforeAllFailed = err
					break
				end
			end
		end
		for _, child in suite.children do
			if child.kind == "suite" then
				if beforeAllFailed == nil then
					runSuite(child)
				end
			else
				local test: TestCase = child
				local name = fullName(test)
				if not shouldRun(test) then
					result.skipped += 1
					table.insert(result.tests, { name = name, status = "skip", ms = 0 })
				elseif beforeAllFailed ~= nil then
					recordFailure(name, { message = "beforeAll failed: " .. errorText(beforeAllFailed.message) })
					table.insert(result.tests, { name = name, status = "fail", ms = 0 })
				else
					local started = os.clock()
					local ok, err = runIsolated(function()
						-- A failing beforeEach skips the test body but afterEach hooks still run, so state set up
						-- by earlier hooks (log sinks, mocks, globals) never leaks into the next test.
						local testOk, testErr = true, nil
						for _, hook in hookChain(test.parent, "beforeEach") do
							testOk, testErr = xpcall(hook, errorHandler)
							if not testOk then
								break
							end
						end
						if testOk then
							testOk, testErr = xpcall(test.fn :: Hook, errorHandler)
						end
						local afterErr: any = nil
						for _, hook in hookChain(test.parent, "afterEach") do
							local hookOk, hookErr = xpcall(hook, errorHandler)
							if not hookOk and afterErr == nil then
								afterErr = hookErr
							end
						end
						if not testOk then
							error(testErr, 0)
						end
						if afterErr ~= nil then
							error(afterErr, 0)
						end
					end, timeout)
					local ms = (os.clock() - started) * 1000
					if ok then
						result.passed += 1
						table.insert(result.tests, { name = name, status = "pass", ms = ms })
					else
						recordFailure(name, err)
						table.insert(result.tests, { name = name, status = "fail", ms = ms })
					end
				end
			end
		end
		if runnable > 0 then
			for _, hook in suite.afterAll do
				local ok, err = runIsolated(hook, timeout)
				if not ok then
					recordFailure((suite.name ~= "" and suite.name or "(file)") .. " > afterAll", err)
				end
			end
		end
	end

	runSuite(root)
	return result
end

return Test
