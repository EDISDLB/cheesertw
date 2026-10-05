--!strict
--[[
	Schema — composable runtime validators for remote arguments and content data.

	Purpose:          Build validators once (`Schema.struct({ id = Schema.string({ maxLen = 40 }) })`) and run them on
	                  untrusted input. A validator is `(value) -> (ok: boolean, err: string?)`.
	Dependencies:     Types/Core (Validator, Result), Core/Result, Net/ErrorCodes.
	State:            None (validators are closures over their options).
	Validation:       Numbers must be finite (NaN/inf always rejected); strings must be valid UTF-8 unless
	                  `allowInvalidUtf8`; arrays must have keys exactly 1..n; structs reject unknown keys unless
	                  `allowExtra`.
	Error handling:   Never throws on bad input; returns messages with paths, e.g. `.loadout[3].ammo: expected
	                  integer, got 2.5`. Schema.check prefixes a root label: `value.loadout[3]...`.
	Performance notes: No allocation on success paths except array/map key scans; build validators at module load,
	                  never per call.

	Note: `Schema.boolean` and `Schema.any` ARE validators (no call); every other entry is a constructor.
]]

local CoreTypes = require("../Types/Core")
local Result = require("./Result")
local ErrorCodes = require("../Net/ErrorCodes")

export type Validator = CoreTypes.Validator

export type NumberOptions = { min: number?, max: number?, integer: boolean? }
export type StringOptions = { minLen: number?, maxLen: number?, pattern: string?, allowInvalidUtf8: boolean? }
export type LengthOptions = { minLen: number?, maxLen: number? }
export type Vector3Options = { maxMagnitude: number? }
export type StructOptions = { allowExtra: boolean? }

local Schema = {}

--- Human-readable type of a value for error messages ("nil", "NaN", "Vector3", "string"...).
function Schema.describe(value: unknown): string
	local t = typeof(value)
	if t == "number" then
		local n = value :: number
		if n ~= n then
			return "NaN"
		elseif n == math.huge or n == -math.huge then
			return tostring(n)
		end
		return tostring(n)
	elseif t == "string" then
		local s = value :: string
		if #s > 24 then
			return string.format("string %q...", string.sub(s, 1, 24))
		end
		return string.format("string %q", s)
	end
	return t
end

local function typeName(value: unknown): string
	local t = typeof(value)
	if t == "number" and (value :: number) ~= (value :: number) then
		return "NaN"
	end
	return t
end

local function nest(segment: string, err: string): string
	local first = string.sub(err, 1, 1)
	if first == "." or first == "[" then
		return segment .. err
	end
	return segment .. ": " .. err
end

local function keySegment(key: any): string
	if type(key) == "string" then
		if string.match(key, "^[%a_][%w_]*$") then
			return "." .. key
		end
		return string.format("[%q]", key)
	end
	return "[" .. tostring(key) .. "]"
end

local function isFiniteNumber(value: unknown): boolean
	if type(value) ~= "number" then
		return false
	end
	local n = value :: number
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Schema.number(options: NumberOptions?): Validator
	local opts: NumberOptions = options or {}
	local min, max, integer = opts.min, opts.max, opts.integer == true
	return function(value: unknown): (boolean, string?)
		if not isFiniteNumber(value) then
			return false, `expected {if integer then "integer" else "finite number"}, got {typeName(value)}`
		end
		local n = value :: number
		if integer and n ~= math.floor(n) then
			return false, `expected integer, got {n}`
		end
		if min ~= nil and n < min then
			return false, `expected >= {min}, got {n}`
		end
		if max ~= nil and n > max then
			return false, `expected <= {max}, got {n}`
		end
		return true, nil
	end
end

function Schema.string(options: StringOptions?): Validator
	local opts: StringOptions = options or {}
	local minLen, maxLen, pattern = opts.minLen, opts.maxLen, opts.pattern
	local checkUtf8 = opts.allowInvalidUtf8 ~= true
	return function(value: unknown): (boolean, string?)
		if type(value) ~= "string" then
			return false, `expected string, got {typeName(value)}`
		end
		local s = value :: string
		if maxLen ~= nil and #s > maxLen then
			return false, `expected at most {maxLen} bytes, got {#s}`
		end
		if minLen ~= nil and #s < minLen then
			return false, `expected at least {minLen} bytes, got {#s}`
		end
		if checkUtf8 and utf8.len(s) == nil then
			return false, "expected valid UTF-8 string"
		end
		if pattern ~= nil and string.find(s, pattern) == nil then
			return false, `string does not match pattern {pattern}`
		end
		return true, nil
	end
end

Schema.boolean = function(value: unknown): (boolean, string?)
	if type(value) ~= "boolean" then
		return false, `expected boolean, got {typeName(value)}`
	end
	return true, nil
end :: Validator

Schema.any = function(_value: unknown): (boolean, string?)
	return true, nil
end :: Validator

function Schema.enum(values: { any }): Validator
	assert(type(values) == "table" and #values > 0, "Schema.enum: values must be a non-empty array")
	local set: { [any]: boolean } = {}
	local shown = {}
	for _, v in values do
		set[v] = true
		table.insert(shown, if type(v) == "string" then string.format("%q", v) else tostring(v))
	end
	local listText = table.concat(shown, ", ")
	return function(value: unknown): (boolean, string?)
		if value ~= nil and set[value :: any] then
			return true, nil
		end
		return false, `expected one of {listText}, got {Schema.describe(value)}`
	end
end

function Schema.literal(expected: any): Validator
	return function(value: unknown): (boolean, string?)
		if value == expected then
			return true, nil
		end
		return false, `expected {Schema.describe(expected)}, got {Schema.describe(value)}`
	end
end

function Schema.vector3(options: Vector3Options?): Validator
	local maxMagnitude = if options then options.maxMagnitude else nil
	return function(value: unknown): (boolean, string?)
		if typeof(value) ~= "Vector3" then
			return false, `expected Vector3, got {typeName(value)}`
		end
		local v = value :: Vector3
		if not (isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)) then
			return false, "expected finite Vector3 components"
		end
		if maxMagnitude ~= nil and v.Magnitude > maxMagnitude then
			return false, `expected magnitude <= {maxMagnitude}, got {v.Magnitude}`
		end
		return true, nil
	end
end

function Schema.buffer(options: LengthOptions?): Validator
	local opts: LengthOptions = options or {}
	return function(value: unknown): (boolean, string?)
		if type(value) ~= "buffer" then
			return false, `expected buffer, got {typeName(value)}`
		end
		local len = buffer.len(value :: buffer)
		if opts.maxLen ~= nil and len > opts.maxLen then
			return false, `expected at most {opts.maxLen} bytes, got {len}`
		end
		if opts.minLen ~= nil and len < opts.minLen then
			return false, `expected at least {opts.minLen} bytes, got {len}`
		end
		return true, nil
	end
end

--- Accepts an Instance (optionally of a class, checked with IsA).
function Schema.instance(className: string?): Validator
	return function(value: unknown): (boolean, string?)
		if typeof(value) ~= "Instance" then
			return false, `expected Instance, got {typeName(value)}`
		end
		if className ~= nil and not (value :: Instance):IsA(className) then
			return false, `expected {className}, got {(value :: Instance).ClassName}`
		end
		return true, nil
	end
end

function Schema.optional(inner: Validator): Validator
	return function(value: unknown): (boolean, string?)
		if value == nil then
			return true, nil
		end
		return inner(value)
	end
end

function Schema.array(element: Validator, options: LengthOptions?): Validator
	local opts: LengthOptions = options or {}
	return function(value: unknown): (boolean, string?)
		if type(value) ~= "table" then
			return false, `expected array, got {typeName(value)}`
		end
		local t = value :: { [any]: any }
		local n = #t
		local count = 0
		for k in t do
			count += 1
			if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
				return false, `expected array, found non-sequential key {Schema.describe(k)}`
			end
		end
		if count ~= n then
			return false, "expected array without holes"
		end
		if opts.maxLen ~= nil and n > opts.maxLen then
			return false, `expected at most {opts.maxLen} elements, got {n}`
		end
		if opts.minLen ~= nil and n < opts.minLen then
			return false, `expected at least {opts.minLen} elements, got {n}`
		end
		for i = 1, n do
			local ok, err = element(t[i])
			if not ok then
				return false, nest(`[{i}]`, err or "invalid")
			end
		end
		return true, nil
	end
end

function Schema.map(key: Validator, val: Validator, options: LengthOptions?): Validator
	local opts: LengthOptions = options or {}
	return function(value: unknown): (boolean, string?)
		if type(value) ~= "table" then
			return false, `expected table, got {typeName(value)}`
		end
		local t = value :: { [any]: any }
		local count = 0
		for k, v in t do
			count += 1
			if opts.maxLen ~= nil and count > opts.maxLen then
				return false, `expected at most {opts.maxLen} entries`
			end
			local okKey, errKey = key(k)
			if not okKey then
				return false, `key {Schema.describe(k)}: {errKey or "invalid"}`
			end
			local okVal, errVal = val(v)
			if not okVal then
				return false, nest(keySegment(k), errVal or "invalid")
			end
		end
		if opts.minLen ~= nil and count < opts.minLen then
			return false, `expected at least {opts.minLen} entries, got {count}`
		end
		return true, nil
	end
end

function Schema.struct(fields: { [string]: Validator }, options: StructOptions?): Validator
	local allowExtra = options ~= nil and options.allowExtra == true
	local names = {}
	for name in fields do
		table.insert(names, name)
	end
	table.sort(names)
	return function(value: unknown): (boolean, string?)
		if type(value) ~= "table" then
			return false, `expected table, got {typeName(value)}`
		end
		local t = value :: { [any]: any }
		for _, name in names do
			local ok, err = fields[name](t[name])
			if not ok then
				return false, nest(keySegment(name), err or "invalid")
			end
		end
		if not allowExtra then
			for k in t do
				if type(k) ~= "string" or fields[k] == nil then
					return false, `unexpected key {Schema.describe(k)}`
				end
			end
		end
		return true, nil
	end
end

function Schema.oneOf(...: Validator): Validator
	local options = { ... }
	assert(#options > 0, "Schema.oneOf: at least one validator required")
	return function(value: unknown): (boolean, string?)
		local errors = {}
		for i, validator in options do
			local ok, err = validator(value)
			if ok then
				return true, nil
			end
			table.insert(errors, `({i}) {err or "invalid"}`)
		end
		return false, "no alternative matched: " .. table.concat(errors, "; ")
	end
end

--- Runs `validator` and wraps the outcome in a Result (Err code INVALID_ARGS, detail = "label<path>: message").
function Schema.check(validator: Validator, value: unknown, label: string?): Result.Result<any>
	local ok, err = validator(value)
	if ok then
		return Result.ok(value)
	end
	local message = err or "invalid"
	local root = label or "value"
	local first = string.sub(message, 1, 1)
	local detail = if first == "." or first == "[" then root .. message else root .. ": " .. message
	return Result.err(ErrorCodes.INVALID_ARGS, detail)
end

return Schema
