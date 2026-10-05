--!strict
--[[
	Freeze — recursive table.freeze for config/content data.

	Purpose:          `Freeze.deep(t)` makes a data tree immutable so runtime code can never mutate config.
	Dependencies:     None.
	State:            None (a visited set per call handles shared sub-tables and cycles).
	Validation:       Non-table input is returned unchanged.
	Error handling:   Tables with a locked metatable that cannot be frozen are skipped (not an error).
	Performance notes: O(n) over the tree; idempotent (already-frozen tables are still descended once).
]]

local Freeze = {}

local function freezeTable(t: { [any]: any }, visited: { [any]: boolean })
	if visited[t] then
		return
	end
	visited[t] = true
	for k, v in t do
		if type(k) == "table" then
			freezeTable(k, visited)
		end
		if type(v) == "table" then
			freezeTable(v, visited)
		end
	end
	if not table.isfrozen(t) then
		pcall(table.freeze, t)
	end
end

--- Deep-freezes `value` in place and returns the same reference (idempotent).
function Freeze.deep<T>(value: T): T
	if type(value) == "table" then
		freezeTable(value :: any, {})
	end
	return value
end

--- True when `value` and every nested table are frozen.
function Freeze.isDeepFrozen(value: unknown): boolean
	if type(value) ~= "table" then
		return true
	end
	local visited: { [any]: boolean } = {}
	local function check(t: { [any]: any }): boolean
		if visited[t] then
			return true
		end
		visited[t] = true
		if not table.isfrozen(t) then
			return false
		end
		for k, v in t do
			if type(k) == "table" and not check(k) then
				return false
			end
			if type(v) == "table" and not check(v) then
				return false
			end
		end
		return true
	end
	return check(value :: any)
end

return Freeze
