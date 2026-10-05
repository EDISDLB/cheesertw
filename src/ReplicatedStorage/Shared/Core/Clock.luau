--!strict
--[[
	Clock — injectable time sources.

	Purpose:          Shared modules never read time directly; they receive a `Clock` (or a `now` number).
	Dependencies:     Types/Core (Clock, FakeClock).
	State:            Fake clocks hold their current time; the real clock is stateless.
	Validation:       Fake clocks reject negative or non-finite advances.
	Error handling:   Invalid arguments raise errors (programming mistakes).
	Performance notes: now() is a single call.

	Clock.real()  -> monotonic seconds via os.clock() (Roblox runtime; the only sanctioned os.clock in Shared).
	Clock.wall()  -> UTC wall time in seconds via os.time() (persisted timestamps, cross-server comparisons).
	Clock.fake(start?) -> FakeClock with :advance(dt) and :set(t) for tests.
]]

local CoreTypes = require("../Types/Core")

export type Clock = CoreTypes.Clock
export type FakeClock = CoreTypes.FakeClock

local Clock = {}

local RealClock = {}
RealClock.__index = RealClock
function RealClock.now(_self: any): number
	return os.clock()
end

local WallClock = {}
WallClock.__index = WallClock
function WallClock.now(_self: any): number
	return os.time()
end

local FakeClockClass = {}
FakeClockClass.__index = FakeClockClass

function FakeClockClass.now(self: any): number
	return self._t
end

function FakeClockClass.advance(self: any, dt: number): number
	if type(dt) ~= "number" or dt ~= dt or dt < 0 or dt == math.huge then
		error(`FakeClock:advance: dt must be a finite number >= 0, got {tostring(dt)}`, 2)
	end
	self._t += dt
	return self._t
end

function FakeClockClass.set(self: any, t: number)
	if type(t) ~= "number" or t ~= t or math.abs(t) == math.huge then
		error(`FakeClock:set: t must be a finite number, got {tostring(t)}`, 2)
	end
	self._t = t
end

function Clock.real(): Clock
	return (setmetatable({}, RealClock) :: any) :: Clock
end

function Clock.wall(): Clock
	return (setmetatable({}, WallClock) :: any) :: Clock
end

function Clock.fake(start: number?): FakeClock
	local t = start or 0
	if type(t) ~= "number" or t ~= t then
		error("Clock.fake: start must be a number", 2)
	end
	return (setmetatable({ _t = t }, FakeClockClass) :: any) :: FakeClock
end

return Clock
