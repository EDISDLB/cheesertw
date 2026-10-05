--[[
	LogCapture — capture Core/Log output inside a spec.

	Purpose:          `local capture = LogCapture.start()` ... `capture:find("error", "handler")` ... `capture:stop()`.
	Dependencies:     Core/Log.
	State:            Captured entries; the previous sink (restored by stop()).
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: Test-only.
]]

local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

local LogCapture = {}
LogCapture.__index = LogCapture

export type Entry = { level: string, scope: string, message: string }

function LogCapture.start(level: string?)
	local self = setmetatable({ entries = {} :: { Entry }, _previousLevel = Log.getLevel() }, LogCapture)
	self._previous = Log.setSink(function(lvl, scope, message)
		table.insert(self.entries, { level = lvl, scope = scope, message = message })
	end)
	if level then
		Log.setLevel(level :: any)
	end
	return self
end

function LogCapture.stop(self: any)
	Log.setSink(self._previous)
	Log.setLevel(self._previousLevel)
end

--- First entry whose level matches (nil = any) and whose message contains `substring` (plain).
function LogCapture.find(self: any, level: string?, substring: string): Entry?
	for _, entry in self.entries do
		if (level == nil or entry.level == level) and string.find(entry.message, substring, 1, true) then
			return entry
		end
	end
	return nil
end

function LogCapture.count(self: any, level: string?): number
	local n = 0
	for _, entry in self.entries do
		if level == nil or entry.level == level then
			n += 1
		end
	end
	return n
end

return LogCapture
