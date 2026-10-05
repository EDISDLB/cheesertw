--!strict
--[[
	Remotes — the single registry of every RemoteEvent / UnreliableRemoteEvent / RemoteFunction (ARCHITECTURE §5.2).

	Purpose:          Declares name, kind, direction, rate limit and argument validators for each remote. NetServer
	                  creates instances from it; NetClient and NetServer refuse names that are not registered.
	Dependencies:     Types/Net (RemoteSpec), Core/Freeze, Net/Protocol, Net/RemoteDefs/*.
	State:            Frozen registry built at module load.
	Validation:       Each entry is validated at load (unique name, valid kind/direction, Function remotes are C2S
	                  only, C2S remotes get Protocol.DEFAULT_RATE when `rate` is omitted, args are validators).
	                  A malformed entry makes require() fail loudly (caught by tests).
	Error handling:   Registry errors are thrown at load (programming mistakes).
	Performance notes: get(name) is a table lookup.

	Adding a remote: add a spec to the owning system's file in Net/RemoteDefs/ (Foundation, Battle, Progression, Store,
	Social, Matchmaking, Settings, Debug). C2S remotes MUST declare `args` validators (use `{}` for no arguments) —
	unvalidated input never reaches handlers. Names must be unique across all domain files (checked at load).
]]

local NetTypes = require("../Types/Net")
local Freeze = require("../Core/Freeze")
local Protocol = require("./Protocol")

export type RemoteSpec = NetTypes.RemoteSpec

local registry: { [string]: RemoteSpec } = {}
local names: { string } = {}

local VALID_KINDS = { Event = true, Unreliable = true, Function = true }
local VALID_DIRECTIONS = { C2S = true, S2C = true }

--- Validates a spec; returns (true) or (false, message). Exposed for tests and tooling.
local function validateSpec(spec: RemoteSpec): (boolean, string?)
	if type(spec) ~= "table" then
		return false, "spec must be a table"
	end
	if type(spec.name) ~= "string" or not string.match(spec.name, "^[%a][%w_]*$") then
		return false, `invalid remote name {tostring(spec.name)}`
	end
	if not VALID_KINDS[spec.kind] then
		return false, `{spec.name}: invalid kind {tostring(spec.kind)}`
	end
	if not VALID_DIRECTIONS[spec.direction] then
		return false, `{spec.name}: invalid direction {tostring(spec.direction)}`
	end
	if spec.kind == "Function" and spec.direction ~= "C2S" then
		return false, `{spec.name}: Function remotes must be C2S (the server never invokes clients)`
	end
	if spec.direction == "C2S" and spec.args == nil then
		return false, `{spec.name}: C2S remotes must declare args validators (use an empty table for none)`
	end
	if spec.args ~= nil then
		for i, validator in spec.args do
			if type(validator) ~= "function" then
				return false, `{spec.name}: args[{i}] is not a validator function`
			end
		end
	end
	if spec.rate ~= nil then
		local rate = spec.rate
		local perSecond, burst = rate.perSecond, rate.burst
		-- NaN passes `< 0` / `< 1` comparisons, so it is rejected explicitly (it would make RateLimiter throw later).
		if
			type(perSecond) ~= "number"
			or type(burst) ~= "number"
			or perSecond ~= perSecond
			or burst ~= burst
			or perSecond < 0
			or burst < 1
		then
			return false, `{spec.name}: rate must have perSecond >= 0 and burst >= 1`
		end
	end
	return true, nil
end

local function define(spec: RemoteSpec)
	local ok, err = validateSpec(spec)
	if not ok then
		error(`Remotes: {err}`, 2)
	end
	if registry[spec.name] ~= nil then
		error(`Remotes: duplicate remote "{spec.name}"`, 2)
	end
	local entry = table.clone(spec)
	if entry.direction == "C2S" and entry.rate == nil then
		entry.rate = Protocol.DEFAULT_RATE
	end
	registry[entry.name] = Freeze.deep(entry)
	table.insert(names, entry.name)
end

--------------------------------------------------------------------------------
-- Domain definition files (one per owning system; see RemoteDefs/*.luau)
--------------------------------------------------------------------------------

-- Order is fixed so registry iteration is deterministic. Each file returns a list of RemoteSpec tables.
local DOMAINS: { { RemoteSpec } } = {
	require("./RemoteDefs/Foundation"),
	require("./RemoteDefs/Battle"),
	require("./RemoteDefs/Progression"),
	require("./RemoteDefs/Store"),
	require("./RemoteDefs/Social"),
	require("./RemoteDefs/Matchmaking"),
	require("./RemoteDefs/Settings"),
	require("./RemoteDefs/Debug"),
}
for _, specs in DOMAINS do
	for _, spec in specs do
		define(spec)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

table.sort(names)
table.freeze(registry)
table.freeze(names)

local Remotes = {}

--- Spec for `name`, or nil when not registered.
function Remotes.get(name: string): RemoteSpec?
	return registry[name]
end

--- Spec for `name`; errors when not registered (programming mistake).
function Remotes.spec(name: string): RemoteSpec
	local spec = registry[name]
	if spec == nil then
		error(`Remotes: unknown remote "{tostring(name)}"`, 2)
	end
	return spec
end

--- All specs sorted by name.
function Remotes.all(): { RemoteSpec }
	local out = {}
	for _, name in names do
		table.insert(out, registry[name])
	end
	return out
end

--- Sorted remote names.
function Remotes.names(): { string }
	return names
end

Remotes.validateSpec = validateSpec

--- Instance class used for each kind.
function Remotes.className(kind: NetTypes.RemoteKind): string
	if kind == "Event" then
		return "RemoteEvent"
	elseif kind == "Unreliable" then
		return "UnreliableRemoteEvent"
	end
	return "RemoteFunction"
end

return table.freeze(Remotes)
