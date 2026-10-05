--[[
	Serialization — Roblox storage serialization rules shared by the DataStore/MemoryStore/Messaging mocks.

	Purpose:          Reject values Roblox cannot store (functions, Instances, Roblox datatypes, mixed/sparse tables,
	                  non-string dictionary keys, NaN/inf, invalid UTF-8, cycles) and measure JSON size for limits.
	Dependencies:     @lune/serde.
	State:            None.
	Validation:       validate(value) -> (ok, message) with a path to the offending element.
	Error handling:   Never throws.
	Performance notes: Test-only (full traversal + JSON encode per write).
]]

local serde = require("@lune/serde")

local Serialization = {}

local function check(value: any, path: string, seen: { [any]: boolean }): (boolean, string?)
	local t = type(value)
	if t == "nil" or t == "boolean" then
		return true, nil
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, `{path}: cannot store non-finite number`
		end
		return true, nil
	elseif t == "string" then
		if utf8.len(value) == nil then
			return false, `{path}: strings must be valid UTF-8`
		end
		return true, nil
	elseif t == "buffer" then
		return true, nil
	elseif t == "table" then
		if getmetatable(value) ~= nil then
			return false, `{path}: cannot store tables with metatables`
		end
		if seen[value] then
			return false, `{path}: cyclic table`
		end
		seen[value] = true
		local n = #value
		local count = 0
		local hasString, hasNumber = false, false
		for k, v in value do
			count += 1
			if type(k) == "string" then
				hasString = true
			elseif type(k) == "number" then
				hasNumber = true
				if k < 1 or k > n or k ~= math.floor(k) then
					return false, `{path}: sparse or non-integer array key {k}`
				end
			else
				return false, `{path}: invalid key type {typeof(k)}`
			end
			local ok, err = check(v, `{path}.{tostring(k)}`, seen)
			if not ok then
				return false, err
			end
		end
		if hasString and hasNumber then
			return false, `{path}: mixed array/dictionary table`
		end
		if hasNumber and count ~= n then
			return false, `{path}: array has holes`
		end
		seen[value] = nil
		return true, nil
	end
	return false, `{path}: cannot store value of type {typeof(value)}`
end

function Serialization.validate(value: any): (boolean, string?)
	return check(value, "value", {})
end

--- JSON-encoded size in bytes (buffers are counted by their length).
function Serialization.jsonSize(value: any): number
	local ok, encoded = pcall(serde.encode, "json", value)
	if ok then
		return #encoded
	end
	return 0
end

function Serialization.copy(value: any): any
	if type(value) == "buffer" then
		local copy = buffer.create(buffer.len(value))
		buffer.copy(copy, 0, value)
		return copy
	end
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = Serialization.copy(v)
	end
	return out
end

return Serialization
