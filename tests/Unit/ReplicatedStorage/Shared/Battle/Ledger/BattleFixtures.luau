--!strict
--[[
	BattleFixtures — participants, damage events and ledger specs shared by the Battle/Rules and Battle/Ledger specs
	(not a spec).

	Purpose:          Compact builders with sensible defaults so each spec states only what it tests.
	Dependencies:     Types/Battle (shapes only).
	State:            None (every call builds fresh tables).
	Validation:       N/A (test-only).
	Error handling:   N/A.
	Performance notes: Test-only.
]]

local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type BattleParticipant = BattleTypes.BattleParticipant
type DamageEvent = BattleTypes.DamageEvent
type BattleEvent = BattleTypes.BattleEvent

export type Slot = { id: number, team: number, bot: boolean?, class: string?, maxHp: number? }

local Fixtures = {}

--- A participant: humans get userId 1000 + id, bots a botId.
function Fixtures.participant(
	id: number,
	team: number,
	opts: { bot: boolean?, class: string?, maxHp: number? }?
): BattleParticipant
	local o = opts or {}
	local bot = o.bot == true
	return {
		participantId = id,
		userId = if bot then nil else 1000 + id,
		botId = if bot then string.format("bot_%02d", id) else nil,
		isBot = bot,
		botSkill = if bot then "Regular" else nil,
		name = if bot then `Bot {id}` else `Player {id}`,
		team = team,
		platoonId = nil,
		vehicleId = "iu_test_mt",
		tier = 5,
		class = (o.class or "medium") :: any,
		role = "medium_versatile",
		faction = "iron_union",
		premiumVehicle = false,
		maxHp = o.maxHp or 1000,
		controlShare = 1,
		rewardContext = nil,
	} :: any
end

--- Participants from compact slots.
function Fixtures.roster(slots: { Slot }): { BattleParticipant }
	local out = {}
	for _, slot in slots do
		table.insert(
			out,
			Fixtures.participant(slot.id, slot.team, { bot = slot.bot, class = slot.class, maxHp = slot.maxHp })
		)
	end
	return out
end

--- A LedgerSpec around `participants`.
function Fixtures.ledgerSpec(participants: { BattleParticipant }, overrides: { [string]: any }?): any
	local spec: { [string]: any } = {
		battleId = "battle_test_0001",
		mode = "Random",
		battleType = "Standard",
		mapId = "proving_grounds",
		startedAt = 1_790_000_000,
		contentHash = "0123456789abcdef",
		buildVersion = "test",
		participants = participants,
	}
	if overrides then
		for key, value in overrides do
			spec[key] = value
		end
	end
	return spec
end

--- A DamageEvent with defaults: Shell, Penetration, potential = damage, no modules/crew, no assists.
function Fixtures.damage(fields: { [string]: any }): DamageEvent
	local d: { [string]: any } = {
		t = 10,
		attacker = nil,
		target = 0,
		kind = "Shell",
		shellId = "iu_ap_75",
		shellKind = "AP",
		result = "Penetration",
		damage = 0,
		potentialDamage = nil,
		modulesHit = {},
		crewInjured = {},
		fireStarted = false,
		killed = false,
		assistSpotters = {},
		assistTrackers = {},
		assistStunners = {},
	}
	for key, value in fields do
		d[key] = value
	end
	if d.potentialDamage == nil then
		d.potentialDamage = d.damage
	end
	if d.kind ~= "Shell" and d.kind ~= "Splash" and fields.result == nil then
		d.result = nil
		d.shellId = nil
		d.shellKind = nil
	end
	return d :: any
end

--- A "Damage" BattleEvent wrapping Fixtures.damage(fields).
function Fixtures.hit(fields: { [string]: any }): BattleEvent
	local d = Fixtures.damage(fields)
	return { type = "Damage", t = d.t, damage = d }
end

--- Battle events of a given type in a list.
function Fixtures.ofType(events: { BattleEvent }, kind: string): { any }
	local out = {}
	for _, event in events do
		if event.type == kind then
			table.insert(out, event)
		end
	end
	return out
end

return Fixtures
