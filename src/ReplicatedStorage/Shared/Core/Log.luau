--!strict
--[[
	Log — scoped, level-filtered logging with a swappable sink.

	Purpose:          `Log.scope("CombatService"):info("fired %s", id)`; the only place in src/ allowed to print.
	Dependencies:     Types/Core (LogLevel, LogSink, Logger).
	State:            Module-level current level (default "info") and sink (default prints/warns).
	Validation:       setLevel rejects unknown levels; formatting errors never throw (falls back to raw args).
	Error handling:   A failing sink is caught and reported once through `warn` so logging never breaks callers.
	Performance notes: Level check happens before string formatting; disabled levels cost one table lookup.
]]

local CoreTypes = require("../Types/Core")

export type LogLevel = CoreTypes.LogLevel
export type LogSink = CoreTypes.LogSink
export type Logger = CoreTypes.Logger

local LEVEL_ORDER: { [string]: number } = {
	debug = 1,
	info = 2,
	warn = 3,
	error = 4,
}

local currentLevel: LogLevel = "info"
local currentThreshold = LEVEL_ORDER.info

local function defaultSink(level: LogLevel, scope: string, message: string)
	local line = `[{scope}] {message}`
	if level == "warn" then
		warn(line)
	elseif level == "error" then
		warn("[ERROR] " .. line)
	else
		print(line)
	end
end

local sink: LogSink = defaultSink
local sinkFailureReported = false

local function formatMessage(fmt: string, ...: any): string
	if select("#", ...) == 0 then
		return fmt
	end
	local ok, result = pcall(string.format, fmt, ...)
	if ok then
		return result
	end
	local parts = { fmt }
	local args = table.pack(...)
	for i = 1, args.n do
		table.insert(parts, tostring(args[i]))
	end
	return table.concat(parts, " ")
end

local function emit(level: LogLevel, scope: string, fmt: string, ...: any)
	if LEVEL_ORDER[level] < currentThreshold then
		return
	end
	local message = formatMessage(fmt, ...)
	local ok, err = pcall(sink :: any, level, scope, message)
	if not ok and not sinkFailureReported then
		sinkFailureReported = true
		warn(`[Log] sink failed: {err}`)
	end
end

local LoggerClass = {}
LoggerClass.__index = LoggerClass

function LoggerClass.debug(self: Logger, fmt: string, ...: any)
	emit("debug", self.name, fmt, ...)
end

function LoggerClass.info(self: Logger, fmt: string, ...: any)
	emit("info", self.name, fmt, ...)
end

function LoggerClass.warn(self: Logger, fmt: string, ...: any)
	emit("warn", self.name, fmt, ...)
end

function LoggerClass.error(self: Logger, fmt: string, ...: any)
	emit("error", self.name, fmt, ...)
end

local Log = {}

--- Returns a logger whose messages are tagged with `name`.
function Log.scope(name: string): Logger
	assert(type(name) == "string" and name ~= "", "Log.scope: name must be a non-empty string")
	local logger = setmetatable({ name = name }, LoggerClass)
	return (logger :: any) :: Logger
end

--- Sets the minimum level that reaches the sink.
function Log.setLevel(level: LogLevel)
	local threshold = LEVEL_ORDER[level]
	if threshold == nil then
		error(`Log.setLevel: unknown level "{tostring(level)}" (expected debug|info|warn|error)`, 2)
	end
	currentLevel = level
	currentThreshold = threshold
end

function Log.getLevel(): LogLevel
	return currentLevel
end

--- True when messages at `level` currently reach the sink (use to skip expensive debug work).
function Log.isEnabled(level: LogLevel): boolean
	local threshold = LEVEL_ORDER[level]
	return threshold ~= nil and threshold >= currentThreshold
end

--- Replaces the sink (nil restores the default). Returns the previous sink so callers can restore it.
function Log.setSink(fn: LogSink?): LogSink
	local previous = sink
	sink = fn or defaultSink
	sinkFailureReported = false
	return previous
end

return Log
