--[[
	FakeClock — deterministic Clock for tests with scheduled callbacks.

	Purpose:          Implements Types.FakeClock (now/advance/set) and adds timers: schedule(delay, fn), cancel(id).
	                  advance(dt) fires due timers in time order (ties in scheduling order) with now() set to each
	                  timer's due time while it runs.
	Dependencies:     None.
	State:            Current time, timer list, id counter.
	Validation:       advance requires dt >= 0 and finite.
	Error handling:   Timer callback errors propagate to the caller of advance (tests should see them).
	Performance notes: Linear scans; test-only.
]]

local FakeClock = {}
FakeClock.__index = FakeClock

export type Timer = { id: number, due: number, seq: number, fn: () -> () }

function FakeClock.new(start: number?)
	return setmetatable({ _t = start or 0, _timers = {} :: { Timer }, _nextId = 1 }, FakeClock)
end

function FakeClock.now(self: any): number
	return self._t
end

local function nextDue(self: any): (Timer?, number?)
	local best, bestIndex = nil, nil
	for i, timer in self._timers do
		if best == nil or timer.due < best.due or (timer.due == best.due and timer.seq < best.seq) then
			best, bestIndex = timer, i
		end
	end
	return best, bestIndex
end

function FakeClock.advance(self: any, dt: number): number
	assert(type(dt) == "number" and dt >= 0 and dt == dt and dt ~= math.huge, "FakeClock:advance dt must be >= 0")
	local target = self._t + dt
	while true do
		local timer, index = nextDue(self)
		if timer == nil or timer.due > target then
			break
		end
		table.remove(self._timers, index)
		self._t = math.max(self._t, timer.due)
		timer.fn()
	end
	self._t = target
	return target
end

--- Jumps to `t`. Moving forward fires due timers (same as advance); moving backward does not.
function FakeClock.set(self: any, t: number)
	if t >= self._t then
		self:advance(t - self._t)
	else
		self._t = t
	end
end

--- Runs `fn` once `delay` seconds from now (on a later advance). Returns a timer id.
function FakeClock.schedule(self: any, delay: number, fn: () -> ()): number
	local id = self._nextId
	self._nextId += 1
	table.insert(self._timers, { id = id, due = self._t + math.max(0, delay), seq = id, fn = fn })
	return id
end

function FakeClock.cancel(self: any, id: number): boolean
	for i, timer in self._timers do
		if timer.id == id then
			table.remove(self._timers, i)
			return true
		end
	end
	return false
end

function FakeClock.pending(self: any): number
	return #self._timers
end

return FakeClock
