--!strict
--[[
	Result — tagged success/failure values for fallible operations.

	Purpose:          `Result.ok(v)` / `Result.err("CODE", detail?)`; never throw across module or remote boundaries.
	Dependencies:     Types/Core (Result, Ok, Err).
	State:            None.
	Validation:       err() requires a non-empty string code (codes live in Shared/Net/ErrorCodes).
	Error handling:   unwrap() is the only throwing helper (use in tests / invariants only).
	Performance notes: One small table per result.
]]

local CoreTypes = require("../Types/Core")

export type Result<T> = CoreTypes.Result<T>
export type Ok<T> = CoreTypes.Ok<T>
export type Err = CoreTypes.Err

local Result = {}

function Result.ok<T>(value: T): Result<T>
	return { ok = true, value = value }
end

function Result.err<T>(code: string, detail: any?): Result<T>
	if type(code) ~= "string" or code == "" then
		error("Result.err: code must be a non-empty string", 2)
	end
	return { ok = false, err = code, detail = detail }
end

function Result.isOk<T>(result: Result<T>): boolean
	return result.ok == true
end

function Result.isErr<T>(result: Result<T>): boolean
	return result.ok == false
end

--- Returns the value or `default` when the result is an error.
function Result.unwrapOr<T>(result: Result<T>, default: T): T
	if result.ok then
		return result.value
	end
	return default
end

--- Returns the value or throws "CODE: detail". For tests and invariants only.
function Result.unwrap<T>(result: Result<T>): T
	if result.ok then
		return result.value
	end
	local detail = result.detail
	error(if detail ~= nil then `{result.err}: {tostring(detail)}` else result.err, 2)
end

--- True when `value` has the shape of a Result (used when validating data that crossed a boundary).
function Result.is(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local t = value :: { [any]: any }
	if t.ok == true then
		return true
	end
	return t.ok == false and type(t.err) == "string"
end

return Result
