--!strict
--[[
	TableUtil — table helpers plus structural diff/patch used for profile replication.

	Purpose:          copy, deepCopy, deepEqual, merge, keys/sortedKeys, values, count, filter, map, find,
	                  diff(old, new) -> {Patch}, applyPatches(target, patches).
	Dependencies:     Types/Core (Patch).
	State:            None.
	Validation:       diff requires two tables and rejects cyclic data and non string/number keys (which
	                  applyPatches would refuse); applyPatches validates op/path and refuses to traverse non-tables.
	Error handling:   Malformed patches raise descriptive errors (callers on the client pcall and request a resync).
	Performance notes: diff walks both trees once; keys are visited in a deterministic sorted order so identical
	                  inputs always produce identical patch lists (important for tests and sequence numbers).

	Patch semantics:
	  * { op = "set", path = {...}, value = v }  -> target[path...] = deepCopy(v) (intermediate tables created)
	  * { op = "delete", path = {...} }          -> target[path...] = nil (missing intermediates are a no-op)
	  * An empty path addresses the root: "set" replaces the root's contents in place, "delete" clears it.
	  * Within one table level, sets/recursions come first (ascending keys), then deletes (descending keys) so
	    array tails shrink from the end.
]]

local CoreTypes = require("../Types/Core")

export type Patch = CoreTypes.Patch
export type PathKey = CoreTypes.PathKey

local TableUtil = {}

local TYPE_RANK: { [string]: number } = { number = 1, string = 2, boolean = 3 }

local function keyLess(a: any, b: any): boolean
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return (TYPE_RANK[ta] or 9) < (TYPE_RANK[tb] or 9)
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	if ta == "boolean" then
		return (not a) and b
	end
	return tostring(a) < tostring(b)
end

function TableUtil.copy<K, V>(t: { [K]: V }): { [K]: V }
	return table.clone(t)
end

local function deepCopyValue(value: any, memo: { [any]: any }): any
	if type(value) ~= "table" then
		return value
	end
	local existing = memo[value]
	if existing ~= nil then
		return existing
	end
	local copy = {}
	memo[value] = copy
	for k, v in value do
		copy[deepCopyValue(k, memo)] = deepCopyValue(v, memo)
	end
	local mt = getmetatable(value)
	if type(mt) == "table" then
		setmetatable(copy, mt)
	end
	return copy
end

--- Deep copy (cycle-safe, keeps metatables, result is never frozen).
function TableUtil.deepCopy<T>(value: T): T
	return deepCopyValue(value, {})
end

local function deepEqualValue(a: any, b: any, seen: { [any]: { [any]: boolean } }): boolean
	if a == b then
		return true
	end
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return false
	end
	if ta == "number" then
		return a ~= a and b ~= b
	end
	if ta ~= "table" then
		return false
	end
	local pairsSeen: { [any]: boolean } = seen[a] or {}
	if pairsSeen[b] then
		return true
	end
	seen[a] = pairsSeen
	pairsSeen[b] = true
	for k, v in a do
		local other = b[k]
		if other == nil or not deepEqualValue(v, other, seen) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

--- Structural equality (NaN equals NaN; metatables are ignored).
function TableUtil.deepEqual(a: any, b: any): boolean
	return deepEqualValue(a, b, {})
end

--- Shallow merge into a new table; later tables win. nil arguments are skipped.
function TableUtil.merge(...: { [any]: any }?): { [any]: any }
	local out = {}
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if t ~= nil then
			for k, v in t do
				out[k] = v
			end
		end
	end
	return out
end

function TableUtil.keys<K, V>(t: { [K]: V }): { K }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

--- Keys in deterministic order: numbers ascending, then strings ascending, then booleans, then others.
function TableUtil.sortedKeys<K, V>(t: { [K]: V }): { K }
	local out = TableUtil.keys(t)
	table.sort(out, keyLess)
	return out
end

function TableUtil.values<K, V>(t: { [K]: V }): { V }
	local out = {}
	for _, v in t do
		table.insert(out, v)
	end
	return out
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

--- Array filter preserving order.
function TableUtil.filter<T>(list: { T }, predicate: (T, number) -> boolean): { T }
	local out = {}
	for i, v in list do
		if predicate(v, i) then
			table.insert(out, v)
		end
	end
	return out
end

--- Array map; results keep the same indices (a nil result leaves a hole, so prefer non-nil mappers).
function TableUtil.map<T, U>(list: { T }, fn: (T, number) -> U): { U }
	local out = table.create(#list)
	for i, v in list do
		out[i] = fn(v, i)
	end
	return out
end

--- First array element matching `predicate`, with its index.
function TableUtil.find<T>(list: { T }, predicate: (T, number) -> boolean): (T?, number?)
	for i, v in list do
		if predicate(v, i) then
			return v, i
		end
	end
	return nil, nil
end

local function isPlainTable(value: any): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function pathToString(path: { PathKey }): string
	local parts = {}
	for _, k in path do
		table.insert(parts, tostring(k))
	end
	return "/" .. table.concat(parts, "/")
end

local function appendPath(path: { PathKey }, key: PathKey): { PathKey }
	-- applyPatches only accepts string/number path elements: refuse to emit a patch the receiver must reject
	-- (on the client that would turn into an endless full-resync loop).
	local keyType = type(key)
	if keyType ~= "string" and keyType ~= "number" then
		error(`TableUtil.diff: unsupported key type {keyType} at {pathToString(path)}`, 0)
	end
	local child = table.clone(path)
	table.insert(child, key)
	return child
end

local function diffInto(
	old: { [any]: any },
	new: { [any]: any },
	path: { PathKey },
	out: { Patch },
	active: { [any]: { [any]: boolean } }
)
	-- Cyclic data cannot be replicated as patches: the same (old, new) pair recurring on the recursion path means
	-- both trees loop. Fail fast instead of recursing until the stack overflows.
	local pairsOfOld = active[old]
	if pairsOfOld == nil then
		pairsOfOld = {}
		active[old] = pairsOfOld
	elseif pairsOfOld[new] then
		error(`TableUtil.diff: cyclic table at {pathToString(path)}`, 0)
	end
	pairsOfOld[new] = true
	for _, key in TableUtil.sortedKeys(new) do
		local newValue = new[key]
		local oldValue = old[key]
		if rawequal(newValue, oldValue) then
			continue -- same value or same table reference: nothing changed below this key
		elseif isPlainTable(newValue) and isPlainTable(oldValue) then
			diffInto(oldValue, newValue, appendPath(path, key), out, active)
		elseif oldValue == nil or not deepEqualValue(oldValue, newValue, {}) then
			table.insert(out, { op = "set", path = appendPath(path, key), value = deepCopyValue(newValue, {}) })
		end
	end
	local removed = {}
	for key in old do
		if new[key] == nil then
			table.insert(removed, key)
		end
	end
	table.sort(removed, function(a, b)
		return keyLess(b, a)
	end)
	for _, key in removed do
		table.insert(out, { op = "delete", path = appendPath(path, key), value = nil })
	end
	pairsOfOld[new] = nil
end

--- Minimal ordered patch list that transforms `old` into `new` (values in patches are deep copies).
function TableUtil.diff(old: { [any]: any }, new: { [any]: any }): { Patch }
	if type(old) ~= "table" or type(new) ~= "table" then
		error("TableUtil.diff: both arguments must be tables", 2)
	end
	local out: { Patch } = {}
	local ok, err: any = pcall(function()
		diffInto(old, new, {}, out, {})
	end)
	if not ok then
		error(err, 2)
	end
	return out
end

--- Applies patches in order, mutating `target` in place; returns `target`.
function TableUtil.applyPatches<T>(target: T, patches: { Patch }): T
	if type(target) ~= "table" then
		error("TableUtil.applyPatches: target must be a table", 2)
	end
	local root = target :: any
	for index, patch in patches do
		if type(patch) ~= "table" or type(patch.path) ~= "table" then
			error(`TableUtil.applyPatches: patch #{index} is malformed`, 2)
		end
		local op = patch.op
		if op ~= "set" and op ~= "delete" then
			error(`TableUtil.applyPatches: patch #{index} has unknown op "{tostring(op)}"`, 2)
		end
		local path = patch.path
		local depth = #path
		for i = 1, depth do
			local k = path[i]
			if type(k) ~= "string" and type(k) ~= "number" then
				error(`TableUtil.applyPatches: patch #{index} path element {i} must be a string or number`, 2)
			end
		end
		if depth == 0 then
			table.clear(root)
			if op == "set" then
				if type(patch.value) ~= "table" then
					error(`TableUtil.applyPatches: patch #{index} sets the root to a non-table`, 2)
				end
				for k, v in deepCopyValue(patch.value, {}) do
					root[k] = v
				end
			end
			continue
		end
		local node = root
		local missing = false
		for i = 1, depth - 1 do
			local k = path[i]
			local nextNode = node[k]
			if nextNode == nil then
				if op == "delete" then
					missing = true
					break
				end
				nextNode = {}
				node[k] = nextNode
			elseif type(nextNode) ~= "table" then
				error(
					`TableUtil.applyPatches: patch #{index} path {pathToString(path)} traverses a non-table at element {i}`,
					2
				)
			end
			node = nextNode
		end
		if not missing then
			local last = path[depth]
			if op == "set" then
				node[last] = deepCopyValue(patch.value, {})
			else
				node[last] = nil
			end
		end
	end
	return target
end

return TableUtil
