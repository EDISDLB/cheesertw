--!strict
--[[
	Types/Core — foundational cross-module types shared by every layer.

	Purpose:          Single source of truth for Result, Patch, Clock, Logger, Signal/Connection and Validator shapes.
	Dependencies:     None (type-only module; must never require implementation modules to avoid cycles).
	State:            None.
	Validation:       N/A (types only).
	Error handling:   N/A.
	Performance notes: Erased at runtime; returns an empty table.
]]

--- Result: fallible operations return `{ ok = true, value = v }` or `{ ok = false, err = "CODE", detail = ... }`.
export type Ok<T> = { ok: true, value: T }
export type Err = { ok: false, err: string, detail: any }
export type Result<T> = Ok<T> | Err

--- Patch: one change produced by TableUtil.diff and consumed by TableUtil.applyPatches.
export type PathKey = string | number
export type PatchOp = "set" | "delete"
export type Patch = { path: { PathKey }, value: any, op: PatchOp }

--- Clock: injected time source. `now()` is monotonic seconds for the real clock.
export type Clock = { now: (self: Clock) -> number }
export type FakeClock = Clock & {
	advance: (self: FakeClock, dt: number) -> number,
	set: (self: FakeClock, t: number) -> (),
}

--- Logging.
export type LogLevel = "debug" | "info" | "warn" | "error"
export type LogSink = (level: LogLevel, scope: string, message: string) -> ()
export type Logger = {
	name: string,
	debug: (self: Logger, fmt: string, ...any) -> (),
	info: (self: Logger, fmt: string, ...any) -> (),
	warn: (self: Logger, fmt: string, ...any) -> (),
	error: (self: Logger, fmt: string, ...any) -> (),
}

--- Signals (Core/Signal implements these; Roblox RBXScriptConnection is structurally compatible with Connection).
export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

--- Server role (ARCHITECTURE §2.1): Hub servers, reserved Battle servers, Dev (Studio / unmapped places).
export type ServerRole = "Hub" | "Battle" | "Dev"

--- Schema validator: returns (true, nil) when valid, (false, message) otherwise.
export type Validator = (value: unknown) -> (boolean, string?)

return {}
