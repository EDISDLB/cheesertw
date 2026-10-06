--!strict
--[[
	Codecs/Battle/Messages — Schema validators for the table payloads of the reliable battle remotes:
	BattleReady (request + bootstrap response), BattleLeave, BattleSpectate (C2S) and BattleState, BattleResults
	(S2C). Shapes: Types/BattleNet.

	Purpose:          C2S validators run in NetServer before any handler (strict structs: unknown keys, wrong types,
	                  NaN/±inf, oversized strings and arrays are rejected). S2C validators document the contract and
	                  let server tests (and a defensive client) check outgoing/incoming payloads.
	Dependencies:     Core/Schema.
	State:            Frozen validators built at load.
	Validation:       Every string and array has a maxLen; numbers are finite and bounded.
	Error handling:   Validators never throw on hostile input.
	Performance notes: Built once; one struct pass per message.
]]

local Schema = require("../../../Core/Schema")

type Validator = Schema.Validator

local MAX_U32 = 4294967295

local entityId = Schema.number({ integer = true, min = 1, max = 255 })
local teamId = Schema.number({ integer = true, min = 1, max = 2 })
local tick = Schema.number({ integer = true, min = 0, max = MAX_U32 })
local small = Schema.number({ integer = true, min = 0, max = 255 })
local hitPoints = Schema.number({ min = 0, max = 10000000 })
local seconds = Schema.number({ min = 0, max = 86400 })
local id64 = Schema.string({ minLen = 1, maxLen = 64 })

local PHASES = { "Preparing", "Loading", "Countdown", "Active", "Ending", "Results", "Closed" }
local MODES = { "Random", "Training", "Bootcamp", "Practice", "Event" }
local BATTLE_TYPES = { "Standard", "Encounter", "Assault" }
local CLASSES = { "light", "medium", "heavy", "td", "artillery" }
local END_REASONS = { "Destruction", "Capture", "Timeout", "DefenderHeld", "Simultaneous", "Aborted" }
local OUTCOMES = { "Victory", "Defeat", "Draw" }

local Messages = {}

Messages.PHASES = table.freeze(PHASES)

--------------------------------------------------------------------------------
-- C2S
--------------------------------------------------------------------------------

--- BattleReady arg: { protocol, contentHash } (ContentRegistry:contentHash() is 16 hex characters).
Messages.READY_REQUEST = Schema.struct({
	protocol = Schema.number({ integer = true, min = 0, max = 65535 }),
	contentHash = Schema.string({ minLen = 1, maxLen = 64, pattern = "^%x+$" }),
})

--- BattleLeave arg: { requestId } (idempotent leave while alive; 00-DECISIONS §9 "Leaving alive").
Messages.LEAVE_REQUEST = Schema.struct({
	requestId = Schema.string({ minLen = 1, maxLen = 40 }),
})

--- BattleSpectate arg: { targetId? } (nil = next available ally).
Messages.SPECTATE_REQUEST = Schema.struct({
	targetId = Schema.optional(entityId),
})

--------------------------------------------------------------------------------
-- S2C
--------------------------------------------------------------------------------

Messages.TEAM_VIEW = Schema.struct({
	team = teamId,
	alive = small,
	total = small,
	hp = hitPoints,
	maxHp = hitPoints,
	kills = small,
})

Messages.BASE_VIEW = Schema.struct({
	base = id64,
	team = teamId,
	progress = Schema.number({ min = 0, max = 100 }),
	frozen = Schema.boolean,
	contested = Schema.boolean,
	cappers = small,
	capturedBy = Schema.optional(teamId),
})

Messages.ROSTER_ENTRY = Schema.struct({
	entityId = entityId,
	team = teamId,
	name = Schema.string({ maxLen = 64 }),
	userId = Schema.optional(Schema.number({ integer = true, min = 1, max = 2 ^ 53 })),
	isBot = Schema.boolean,
	controller = Schema.enum({ "Player", "Bot" }),
	vehicleId = id64,
	tier = Schema.number({ integer = true, min = 1, max = 11 }),
	class = Schema.enum(CLASSES),
	maxHp = Schema.number({ min = 1, max = 1000000 }),
	platoon = Schema.optional(Schema.number({ integer = true, min = 1, max = 15 })),
	alive = Schema.boolean,
})

Messages.STATE_MESSAGE = Schema.struct({
	seq = tick,
	tick = tick,
	phase = Schema.enum(PHASES),
	phaseEndsAtTick = Schema.optional(tick),
	timeLeftS = Schema.optional(seconds),
	teams = Schema.array(Messages.TEAM_VIEW, { maxLen = 2 }),
	bases = Schema.array(Messages.BASE_VIEW, { maxLen = 8 }),
	roster = Schema.optional(Schema.array(Messages.ROSTER_ENTRY, { maxLen = 64 })),
})

--- BattleReady response value (inside the Result).
Messages.BOOTSTRAP = Schema.struct({
	protocol = Schema.number({ integer = true, min = 0, max = 65535 }),
	battleId = id64,
	mapId = id64,
	mode = Schema.enum(MODES),
	battleType = Schema.optional(Schema.enum(BATTLE_TYPES)),
	eventId = Schema.optional(id64),
	entityId = Schema.optional(entityId),
	team = Schema.optional(teamId),
	tickRate = Schema.number({ integer = true, min = 1, max = 120 }),
	snapshotRate = Schema.number({ integer = true, min = 1, max = 60 }),
	serverTick = tick,
	state = Messages.STATE_MESSAGE,
})

Messages.PERSONAL_RESULT = Schema.struct({
	survived = Schema.boolean,
	damageDealt = hitPoints,
	assist = hitPoints,
	damageBlocked = hitPoints,
	kills = small,
	spotted = small,
})

Messages.RESULTS_MESSAGE = Schema.struct({
	battleId = id64,
	winner = Schema.optional(teamId),
	reason = Schema.enum(END_REASONS),
	outcome = Schema.enum(OUTCOMES),
	durationS = seconds,
	endedAtTick = tick,
	personal = Schema.optional(Messages.PERSONAL_RESULT),
})

return table.freeze(Messages)
