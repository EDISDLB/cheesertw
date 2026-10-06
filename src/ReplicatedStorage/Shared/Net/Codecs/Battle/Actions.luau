--!strict
--[[
	Codecs/Battle/Actions — the BattleAction payload (C2S RemoteEvent, one table): strict validator, per-action
	token buckets and the admission helper the battle server applies after NetServer's per-remote bucket
	(00-DECISIONS §19 "Fire 6/s · consumable/ammo 4/s · ping 3/5 s", §9 comms).

	Purpose:          `Actions.validate` is the registry arg validator (dispatches on `kind`, then a strict struct:
	                  unknown keys, wrong types, NaN/±inf, out-of-range slots/ids/coordinates are rejected before any
	                  handler runs). `Actions.admit(limiter, player, kind)` enforces the per-action buckets on top of
	                  the remote's envelope bucket (REMOTE_RATE = the sum, so legitimate play never hits it).
	Dependencies:     Core/Schema, Codecs/Battle/Enums, Security/RateLimiter (type), Types/Net, Types/BattleNet.
	State:            Frozen validators and rate tables built at load.
	Validation:       See Purpose. Map points are 2-D designations bounded to ±MAP_COORD_LIMIT studs (the server
	                  clamps them to the map); QuickCommand needs both mapX and mapZ or neither.
	Error handling:   validate never throws on hostile input (Schema validators are total); admit never throws.
	Performance notes: One struct validation per action; admit does at most two bucket peeks + consumes.

	Bucket semantics (token bucket: `burst` tokens, refilled at `perSecond`; at most burst + perSecond × T calls in
	any window of T seconds):
	  Fire          6/s, burst 6                         (00-DECISIONS §19)
	  Loadout       4/s, burst 4  shared by SwitchShell, UseConsumable, ActivateMechanic ("consumable/ammo 4/s")
	  Marker        0.6/s, burst 3   ("markers 3/5 s")    } QuickCommand and MapPing consume both
	  MarkerMinute  0.1/s, burst 6   (<= 12 in any 60 s) }
	  ChatLine      0.1/s, burst 1   ("chat presets 1/10 s"): a QuickCommand also prints a team-chat line only
	                when this bucket has a token and the command is not a reply (replies are marker-only, §9).
]]

local Schema = require("../../../Core/Schema")
local Enums = require("./Enums")
local RateLimiter = require("../../../Security/RateLimiter")
local NetTypes = require("../../../Types/Net")
local BattleNet = require("../../../Types/BattleNet")

type Validator = Schema.Validator
type RateSpec = NetTypes.RateSpec
type RateLimiter = RateLimiter.RateLimiter
type ActionKind = BattleNet.ActionKind
type QuickCommandId = BattleNet.QuickCommandId

export type Bucket = { name: string, rate: RateSpec }

local MAX_SHELL_SLOTS = 3
local MAX_CONSUMABLE_SLOTS = 3
local MAP_COORD_LIMIT = 32767

local Actions = {}

--- Ammo slots per gun (Types/Content GunDefinition.shells: 1..3).
Actions.MAX_SHELL_SLOTS = MAX_SHELL_SLOTS
--- Consumable slots per vehicle (ContentRegistry bounds slots.consumables to 0..3).
Actions.MAX_CONSUMABLE_SLOTS = MAX_CONSUMABLE_SLOTS
--- |mapX|, |mapZ| limit in studs (the i16 grid of the Command / Ping events).
Actions.MAP_COORD_LIMIT = MAP_COORD_LIMIT
Actions.KINDS = table.freeze({
	"Fire",
	"SwitchShell",
	"UseConsumable",
	"ActivateMechanic",
	"QuickCommand",
	"MapPing",
} :: { ActionKind })

local function kindIs(kind: string): Validator
	return Schema.literal(kind)
end

local entityId = Schema.number({ integer = true, min = 1, max = 255 })
local mapCoord = Schema.number({ min = -MAP_COORD_LIMIT, max = MAP_COORD_LIMIT })

local VALIDATORS: { [string]: Validator } = {
	Fire = Schema.struct({
		kind = kindIs("Fire"),
		seq = Schema.number({ integer = true, min = 0, max = 65535 }),
	}),
	SwitchShell = Schema.struct({
		kind = kindIs("SwitchShell"),
		slot = Schema.number({ integer = true, min = 1, max = MAX_SHELL_SLOTS }),
	}),
	UseConsumable = Schema.struct({
		kind = kindIs("UseConsumable"),
		slot = Schema.number({ integer = true, min = 1, max = MAX_CONSUMABLE_SLOTS }),
	}),
	ActivateMechanic = Schema.struct({
		kind = kindIs("ActivateMechanic"),
		mechanic = Schema.enum(Enums.MechanicKind.values),
	}),
	QuickCommand = Schema.struct({
		kind = kindIs("QuickCommand"),
		command = Schema.enum(Enums.QuickCommand.values),
		targetId = Schema.optional(entityId),
		mapX = Schema.optional(mapCoord),
		mapZ = Schema.optional(mapCoord),
	}),
	MapPing = Schema.struct({
		kind = kindIs("MapPing"),
		ping = Schema.enum(Enums.PingKind.values),
		mapX = mapCoord,
		mapZ = mapCoord,
	}),
}

--- Registry validator for the BattleAction remote. Passes only by returning exactly true.
function Actions.validate(value: unknown): (boolean, string?)
	if type(value) ~= "table" then
		return false, `expected table, got {Schema.describe(value)}`
	end
	local t = value :: { [any]: any }
	local kind = t.kind
	if type(kind) ~= "string" then
		return false, `.kind: expected string, got {Schema.describe(kind)}`
	end
	local validator = VALIDATORS[kind]
	if validator == nil then
		return false, `.kind: unknown action {Schema.describe(kind)}`
	end
	local ok, err = validator(value)
	if not ok then
		return false, err
	end
	if kind == "QuickCommand" and (t.mapX == nil) ~= (t.mapZ == nil) then
		return false, ".mapX/.mapZ: give both or neither"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Rates
--------------------------------------------------------------------------------

local function bucket(name: string, perSecond: number, burst: number): Bucket
	return table.freeze({ name = name, rate = table.freeze({ perSecond = perSecond, burst = burst }) })
end

local FIRE = bucket("BattleAction.Fire", 6, 6)
local LOADOUT = bucket("BattleAction.Loadout", 4, 4)
local MARKER = bucket("BattleAction.Marker", 0.6, 3)
local MARKER_MINUTE = bucket("BattleAction.MarkerMinute", 0.1, 6)

Actions.BUCKETS = table.freeze({
	Fire = FIRE,
	Loadout = LOADOUT,
	Marker = MARKER,
	MarkerMinute = MARKER_MINUTE,
})

--- Buckets each action kind consumes (all must have a token).
Actions.KIND_BUCKETS = table.freeze({
	Fire = table.freeze({ FIRE }),
	SwitchShell = table.freeze({ LOADOUT }),
	UseConsumable = table.freeze({ LOADOUT }),
	ActivateMechanic = table.freeze({ LOADOUT }),
	QuickCommand = table.freeze({ MARKER, MARKER_MINUTE }),
	MapPing = table.freeze({ MARKER, MARKER_MINUTE }),
} :: { [string]: { Bucket } })

--- Envelope bucket of the BattleAction remote (NetServer, per player): the sum of the per-action buckets, so only
--- floods beyond what the action buckets could ever admit earn RATE_LIMITED strikes.
Actions.REMOTE_RATE = table.freeze({ perSecond = 11, burst = 13 })

--- Team-chat line accompanying a QuickCommand (cosmetic; over budget -> marker only).
Actions.CHAT_LINE = bucket("BattleAction.ChatLine", 0.1, 1)

--- Commands that answer someone else's call: marker-only, never a chat line (00-DECISIONS §9 "replies
--- marker-only"; OUR DESIGN CHOICE for which presets count as replies).
Actions.REPLY_COMMANDS = table.freeze({ Affirmative = true, Negative = true, Thanks = true } :: { [string]: boolean })

--- Consumes one token from every bucket of `kind` when all of them have one (atomic: nothing is consumed
--- otherwise). Returns false for unknown kinds or when any bucket is empty (drop the action; no strike needed,
--- the remote's envelope bucket already strikes floods).
function Actions.admit(limiter: RateLimiter, owner: any, kind: string): boolean
	local buckets = Actions.KIND_BUCKETS[kind]
	if buckets == nil then
		return false
	end
	for _, b in buckets do
		if limiter:remaining(owner, b.name, b.rate) < 1 then
			return false
		end
	end
	for _, b in buckets do
		limiter:consume(owner, b.name, b.rate)
	end
	return true
end

--- Whether an admitted QuickCommand also prints a team-chat line (consumes the ChatLine token when it does).
function Actions.takeChatLine(limiter: RateLimiter, owner: any, command: QuickCommandId): boolean
	if Actions.REPLY_COMMANDS[command] then
		return false
	end
	return limiter:consume(owner, Actions.CHAT_LINE.name, Actions.CHAT_LINE.rate)
end

return table.freeze(Actions)
