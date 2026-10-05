--[[
	FailureInjector — shared failure-injection bookkeeping for mock adapters.

	Purpose:          failNext(method, count?, message?), failAlways(method, message?), clear(), and a call log.
	                  Method "*" matches every method.
	Dependencies:     None.
	State:            Queued one-shot failures, permanent failures, call log.
	Validation:       count >= 1.
	Error handling:   check(method) returns the error message to fail with (consuming one-shot entries) or nil.
	Performance notes: Test-only.
]]

local FailureInjector = {}
FailureInjector.__index = FailureInjector

function FailureInjector.new()
	return setmetatable({ _next = {}, _always = {}, calls = {} }, FailureInjector)
end

--- The next `count` (default 1) calls of `method` fail with `message`.
function FailureInjector.failNext(self: any, method: string, count: number?, message: string?)
	local n = count or 1
	assert(n >= 1, "failNext count must be >= 1")
	for _ = 1, n do
		table.insert(self._next, { method = method, message = message or `injected failure ({method})` })
	end
end

--- Every call of `method` fails until clear().
function FailureInjector.failAlways(self: any, method: string, message: string?)
	self._always[method] = message or `injected failure ({method})`
end

function FailureInjector.clear(self: any)
	table.clear(self._next)
	table.clear(self._always)
end

--- Records the call and returns an error message if it must fail.
function FailureInjector.check(self: any, method: string): string?
	table.insert(self.calls, method)
	local always = self._always[method] or self._always["*"]
	if always ~= nil then
		return always
	end
	for i, entry in self._next do
		if entry.method == method or entry.method == "*" then
			table.remove(self._next, i)
			return entry.message
		end
	end
	return nil
end

function FailureInjector.callCount(self: any, method: string?): number
	if method == nil then
		return #self.calls
	end
	local n = 0
	for _, m in self.calls do
		if m == method then
			n += 1
		end
	end
	return n
end

return FailureInjector
