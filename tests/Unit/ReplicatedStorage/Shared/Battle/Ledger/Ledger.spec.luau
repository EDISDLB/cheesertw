local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local TableUtil = require("@game/ReplicatedStorage/Shared/Core/TableUtil")
local Ledger = require("@game/ReplicatedStorage/Shared/Battle/Ledger/Ledger")
local Outcome = require("@game/ReplicatedStorage/Shared/Battle/Rules/Outcome")
local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Fixtures = require("./BattleFixtures")

local hit = Fixtures.hit

-- Team 1: 1 medium (human), 2 light (human), 3 td (bot). Team 2: 11 heavy (human), 12 artillery (bot), 13 medium.
local SLOTS = {
	{ id = 1, team = 1, class = "medium" },
	{ id = 2, team = 1, class = "light" },
	{ id = 3, team = 1, class = "td", bot = true },
	{ id = 11, team = 2, class = "heavy" },
	{ id = 12, team = 2, class = "artillery", bot = true },
	{ id = 13, team = 2, class = "medium" },
}

local function newLedger(slots: { any }?)
	return Ledger.new(Fixtures.ledgerSpec(Fixtures.roster(slots or SLOTS)))
end

local function statsOf(result, id: number)
	for _, p in result.participants do
		if p.participant.participantId == id then
			return p.stats, p.participant
		end
	end
	error("no participant " .. id)
end

local function ended(t: number, outcome)
	return { type = "Ended", t = t, outcome = outcome or Outcome.draw("Timeout", { 1, 2 }) }
end

describe("Ledger — damage accounting", function()
	it("a penetration fills dealt/received, hits/pens, potential, byTargetClass and interactions", function()
		local ledger = newLedger()
		expect(Ledger.apply(ledger, hit({ t = 10, attacker = 1, target = 11, damage = 300 }))).toBe(true)
		local a = Ledger.stats(ledger, 1)
		local v = Ledger.stats(ledger, 11)
		expect(a.damageDealt).toBe(300)
		expect(a.hits).toBe(1)
		expect(a.penetrations).toBe(1)
		expect(a.firstContactDamage).toBe(300)
		expect(a.byTargetClass).toEqual({ heavy = { damageDealt = 300, kills = 0, spotted = 0, assist = 0 } })
		expect(v.damageReceived).toBe(300)
		expect(v.hitsReceived).toBe(1)
		expect(v.penetrationsReceived).toBe(1)
		expect(v.potentialDamageReceived).toBe(300)
		expect(v.damageBlocked).toBe(0)
		expect(Ledger.interactions(ledger, 1)).toEqual({
			{
				other = 11,
				shotsAt = 1,
				hitsOn = 1,
				pensOn = 1,
				critsOn = 0,
				damageDealt = 300,
				spottedIt = false,
				killedIt = false,
				hitsFrom = 0,
				damageReceived = 0,
				killedBy = false,
			},
		})
		expect(Ledger.interactions(ledger, 11)[1].hitsFrom).toBe(1)
		expect(Ledger.interactions(ledger, 11)[1].damageReceived).toBe(300)
	end)

	it("blocked damage = potential of non-pens/ricochets/absorbed hits received (REG-RES-08)", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({ attacker = 1, target = 11, damage = 0, potentialDamage = 320, result = "Ricochet" }),
			hit({ attacker = 1, target = 11, damage = 0, potentialDamage = 280, result = "NonPenetration" }),
			hit({ attacker = 2, target = 11, damage = 0, potentialDamage = 150, result = "Absorbed" }),
			-- HE non-pen dealing partial damage: only the part the armor stopped counts as blocked.
			hit({
				attacker = 1,
				target = 11,
				damage = 40,
				potentialDamage = 300,
				result = "NonPenetration",
				shellKind = "HE",
			}),
			-- Splash without a direct hit: potential received, never a hit or blocked.
			hit({ attacker = 1, target = 11, kind = "Splash", result = "Splash", damage = 30, potentialDamage = 100 }),
		})
		local v = Ledger.stats(ledger, 11)
		expect(v.damageBlocked).toBe(320 + 280 + 150 + 260)
		expect(v.potentialDamageReceived).toBe(320 + 280 + 150 + 300 + 100)
		expect(v.hitsReceived).toBe(4)
		expect(v.ricochetsReceived).toBe(1)
		expect(v.nonPensReceived).toBe(3)
		expect(v.penetrationsReceived).toBe(0)
		expect(v.damageReceived).toBe(70)
		expect(Ledger.stats(ledger, 1).hits).toBe(3)
		expect(Ledger.stats(ledger, 1).penetrations).toBe(0)
		expect(Ledger.stats(ledger, 2).hits).toBe(1)
	end)

	it("criticals count module damage and crew injuries from shells and splash", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({
				attacker = 1,
				target = 11,
				damage = 0,
				result = "Absorbed",
				modulesHit = { { module = "TrackLeft", damage = 80, state = "Destroyed" } },
			}),
			hit({ attacker = 1, target = 11, damage = 100, crewInjured = { { slot = 2, role = "Gunner" } } }),
			hit({
				attacker = 1,
				target = 11,
				damage = 100,
				modulesHit = { { module = "Engine", damage = 0, state = "Ok" } },
			}),
			hit({
				attacker = 1,
				target = 11,
				kind = "Splash",
				result = "Splash",
				damage = 10,
				modulesHit = { { module = "Optics", damage = 10, state = "Ok" } },
			}),
			hit({
				attacker = 1,
				target = 11,
				kind = "Ram",
				damage = 50,
				modulesHit = { { module = "TrackRight", damage = 30, state = "Damaged" } },
			}),
		})
		expect(Ledger.stats(ledger, 1).criticalHits).toBe(3)
		expect(Ledger.stats(ledger, 1).ramDamageDealt).toBe(50)
		expect(Ledger.interactions(ledger, 1)[1].critsOn).toBe(3)
	end)

	it("friendly fire is off: ally-blocked shells are accepted silently, ally damage is ignored", function()
		local ledger = newLedger()
		expect(
			Ledger.apply(
				ledger,
				hit({ attacker = 1, target = 2, damage = 0, result = "AllyBlocked", potentialDamage = 300 })
			)
		).toBe(true)
		expect(Ledger.apply(ledger, hit({ attacker = 1, target = 2, damage = 120 }))).toBe(false)
		expect(Ledger.apply(ledger, hit({ attacker = 11, target = 13, kind = "Ram", damage = 40 }))).toBe(false)
		expect(Ledger.anomalies(ledger)).toEqual({ AllyDamage = 2 })
		for _, id in { 1, 2, 11, 13 } do
			local s = Ledger.stats(ledger, id)
			expect(s.damageDealt).toBe(0)
			expect(s.damageReceived).toBe(0)
			expect(s.potentialDamageReceived).toBe(0)
			expect(s.hits).toBe(0)
		end
	end)

	it("environment damage (no attacker or self) is received, never dealt", function()
		local ledger = newLedger()
		Ledger.apply(ledger, hit({ attacker = nil, target = 1, kind = "Fall", damage = 70 }))
		Ledger.apply(ledger, hit({ attacker = 1, target = 1, kind = "AmmoRack", damage = 30 }))
		expect(Ledger.stats(ledger, 1).damageReceived).toBe(100)
		expect(Ledger.stats(ledger, 1).damageDealt).toBe(0)
		expect(Ledger.stats(ledger, 1).hitsReceived).toBe(0)
	end)

	it("first-contact damage counts the first 180 s only", function()
		local ledger = newLedger()
		Ledger.apply(ledger, hit({ t = 180, attacker = 1, target = 11, damage = 100 }))
		Ledger.apply(ledger, hit({ t = 180.5, attacker = 1, target = 11, damage = 100 }))
		expect(Ledger.stats(ledger, 1).firstContactDamage).toBe(100)
		expect(Ledger.stats(ledger, 1).damageDealt).toBe(200)
	end)
end)

describe("Ledger — assists (00-DECISIONS §5; REG-RES-08, REG-SPT-07)", function()
	it(
		"every validated listed ally gets the full damage; attacker, enemies, unknowns and duplicates are dropped",
		function()
			local ledger = newLedger()
			Ledger.apply(
				ledger,
				hit({
					t = 20,
					attacker = 1,
					target = 11,
					damage = 200,
					assistSpotters = { 2, 3, 1, 11, 12, 99, 2 },
					assistTrackers = { 3, 3, 13 },
				})
			)
			expect(Ledger.stats(ledger, 2).assistSpotting).toBe(200)
			expect(Ledger.stats(ledger, 3).assistSpotting).toBe(200)
			expect(Ledger.stats(ledger, 3).assistTracking).toBe(200)
			expect(Ledger.stats(ledger, 1).assistSpotting).toBe(0)
			expect(Ledger.stats(ledger, 12).assistSpotting).toBe(0)
			expect(Ledger.stats(ledger, 3).byTargetClass.heavy.assist).toBe(400)
			local total = 0
			for _, id in { 1, 2, 3, 11, 12, 13 } do
				total += Ledger.stats(ledger, id).assistSpotting
			end
			expect(total).toBe(200 * 2)
		end
	)

	it("stun assist goes to the artillery whose stun was running; stuns are counted", function()
		local ledger = newLedger()
		Ledger.apply(ledger, { type = "Stunned", t = 30, target = 1, attacker = 12, durationS = 10 })
		Ledger.apply(ledger, hit({ t = 33, attacker = 13, target = 1, damage = 150, assistStunners = { 12 } }))
		expect(Ledger.stats(ledger, 12).stuns).toBe(1)
		expect(Ledger.stats(ledger, 12).assistStun).toBe(150)
		expect(Ledger.stats(ledger, 12).byTargetClass.medium.assist).toBe(150)
		expect(Ledger.apply(ledger, { type = "Stunned", t = 30, target = 13, attacker = 12, durationS = 10 })).toBe(
			false
		)
	end)

	it("0-damage hits credit no assist", function()
		local ledger = newLedger()
		Ledger.apply(
			ledger,
			hit({
				attacker = 1,
				target = 11,
				damage = 0,
				result = "Ricochet",
				potentialDamage = 200,
				assistSpotters = { 2 },
			})
		)
		expect(Ledger.stats(ledger, 2).assistSpotting).toBe(0)
	end)

	it("soleSpotterDamaged counts distinct targets damaged while this vehicle was the only spotter", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({ attacker = 1, target = 11, damage = 50, assistSpotters = { 2 } }),
			hit({ attacker = 3, target = 11, damage = 50, assistSpotters = { 2 } }),
			hit({ attacker = 1, target = 13, damage = 50, assistSpotters = { 2, 3 } }),
			hit({ attacker = 1, target = 12, damage = 50, assistSpotters = { 3, 1 } }),
		})
		local result = Ledger.finalize(ledger)
		expect(statsOf(result, 2).soleSpotterDamaged).toBe(1)
		expect(statsOf(result, 3).soleSpotterDamaged).toBe(1)
	end)
end)

describe("Ledger — kills and the kill feed", function()
	it("killing blow, killedBy, deathCause, firstBlood, assisters and Confederate counting", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({ t = 30, attacker = 1, target = 11, damage = 500 }),
			hit({ t = 40, attacker = 2, target = 11, damage = 500, killed = true, assistSpotters = { 3 } }),
		})
		local record = Ledger.deathRecord(ledger, 11)
		expect(record).toEqual({ t = 40, victim = 11, killer = 2, cause = "Shell", assisters = { 1, 3 } })
		-- The producer fills the Destroyed event from the record; applying it changes nothing.
		expect(
			Ledger.apply(
				ledger,
				{ type = "Destroyed", t = 40, target = 11, attacker = 2, cause = "Shell", assisters = { 1, 3 } }
			)
		).toBe(true)
		expect(#Ledger.killFeed(ledger)).toBe(1)
		local result = Ledger.finalize(ledger, { endT = 100 })
		local killer = statsOf(result, 2)
		expect(killer.kills).toBe(1)
		expect(killer.firstBlood).toBe(true)
		expect(killer.byTargetClass.heavy.kills).toBe(1)
		expect(killer.hitsOnLaterKilled).toBe(0)
		expect(statsOf(result, 1).hitsOnLaterKilled).toBe(1)
		expect(statsOf(result, 1).firstBlood).toBe(false)
		local victim = statsOf(result, 11)
		expect(victim.killedBy).toBe(2)
		expect(victim.deathCause).toBe("Shell")
		expect(victim.survived).toBe(false)
		expect(victim.timeAliveS).toBe(40)
		expect(statsOf(result, 13).survived).toBe(true)
		expect(statsOf(result, 13).timeAliveS).toBe(100)
		local pair = Ledger.interactions(ledger, 2)[1]
		expect(pair.killedIt).toBe(true)
		expect(Ledger.interactions(ledger, 11)[2].killedBy).toBe(true)
	end)

	it("a Destroyed event alone registers the death; later damage to the wreck is ignored", function()
		local ledger = newLedger()
		Ledger.apply(ledger, hit({ t = 10, attacker = 1, target = 13, damage = 900 }))
		Ledger.apply(ledger, { type = "Destroyed", t = 11, target = 13, attacker = 1, cause = "Shell", assisters = {} })
		expect(Ledger.isAlive(ledger, 13)).toBe(false)
		expect(Ledger.stats(ledger, 1).kills).toBe(1)
		expect(Ledger.apply(ledger, hit({ t = 12, attacker = 2, target = 13, damage = 100 }))).toBe(false)
		expect(
			Ledger.apply(
				ledger,
				{ type = "Destroyed", t = 13, target = 13, attacker = 2, cause = "Shell", assisters = {} }
			)
		).toBe(true)
		expect(Ledger.stats(ledger, 2).kills).toBe(0)
		expect(Ledger.anomalies(ledger)).toEqual({ DeadTarget = 1 })
	end)

	it("fire kills are credited to the igniter; fires started are counted", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({ t = 50, attacker = 2, target = 13, damage = 200, fireStarted = true }),
			{ type = "Fire", t = 50, target = 13, burning = true, attacker = 2 },
			hit({ t = 51, attacker = 2, target = 13, kind = "Fire", damage = 25 }),
			hit({ t = 52, attacker = 2, target = 13, kind = "Fire", damage = 25, killed = true }),
		})
		expect(Ledger.stats(ledger, 2).firesStarted).toBe(1)
		expect(Ledger.stats(ledger, 2).kills).toBe(1)
		expect(Ledger.stats(ledger, 13).deathCause).toBe("Fire")
		expect(Ledger.stats(ledger, 13).killedBy).toBe(2)
	end)

	it("ammo-rack detonations are credited to the shooter", function()
		local ledger = newLedger()
		Ledger.apply(
			ledger,
			hit({ t = 60, attacker = 1, target = 11, kind = "AmmoRack", damage = 1000, killed = true })
		)
		expect(Ledger.stats(ledger, 1).kills).toBe(1)
		expect(Ledger.stats(ledger, 1).damageDealt).toBe(1000)
		expect(Ledger.stats(ledger, 11).deathCause).toBe("AmmoRack")
	end)

	it("a mutual ram kill credits both rammers (REG-BTL-02)", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({ t = 70, attacker = 1, target = 11, kind = "Ram", damage = 1000, killed = true }),
			hit({ t = 70, attacker = 11, target = 1, kind = "Ram", damage = 1000, killed = true }),
		})
		expect(Ledger.stats(ledger, 1).kills).toBe(1)
		expect(Ledger.stats(ledger, 11).kills).toBe(1)
		expect(Ledger.stats(ledger, 1).ramDamageDealt).toBe(1000)
		expect(Ledger.stats(ledger, 1).firstBlood).toBe(true)
		expect(Ledger.stats(ledger, 11).firstBlood).toBe(false)
	end)

	it("falls credit the last enemy damager within 5 s; drowning credits nobody", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			hit({ t = 50, attacker = 1, target = 11, kind = "Ram", damage = 100 }),
			hit({ t = 53, target = 11, kind = "Fall", damage = 900, killed = true }),
			hit({ t = 50, attacker = 2, target = 13, damage = 100 }),
			hit({ t = 60, target = 13, kind = "Fall", damage = 900, killed = true }),
			hit({ t = 61, attacker = 3, target = 12, damage = 100 }),
			hit({ t = 62, target = 12, kind = "Drown", damage = 900, killed = true }),
		})
		expect(Ledger.stats(ledger, 11).killedBy).toBe(1)
		expect(Ledger.stats(ledger, 13).killedBy).toBeNil()
		expect(Ledger.stats(ledger, 12).killedBy).toBeNil()
		expect(Ledger.stats(ledger, 12).deathCause).toBe("Drown")
		expect(Ledger.stats(ledger, 1).kills).toBe(1)
		expect(Ledger.stats(ledger, 2).kills).toBe(0)
		expect(Ledger.stats(ledger, 3).kills).toBe(0)
		local killer, assisters = Ledger.resolveKill(ledger, 11, "Fall", nil, 53)
		expect(killer).toBe(1)
		expect(assisters).toEqual({})
	end)

	it("REG-BTL-02: simultaneous last kills credit both and draw, for every event and roster ordering", function()
		local slots = { { id = 5, team = 1 }, { id = 9, team = 2 } }
		local killA = hit({ t = 90, attacker = 5, target = 9, damage = 1000, killed = true })
		local killB = hit({ t = 90, attacker = 9, target = 5, damage = 1000, killed = true })
		local results = {}
		for _, order in { { killA, killB }, { killB, killA } } do
			for _, rosterOrder in { { 1, 2 }, { 2, 1 } } do
				local ledger = newLedger({ slots[rosterOrder[1]], slots[rosterOrder[2]] })
				Ledger.applyAll(ledger, TableUtil.deepCopy(order))
				expect(Ledger.stats(ledger, 5).kills).toBe(1)
				expect(Ledger.stats(ledger, 9).kills).toBe(1)
				local outcome = Outcome.evaluate({
					settings = ModeRules.defaults("Random", "Standard"),
					teams = Ledger.teams(ledger),
					rosterByTeam = Ledger.rosterByTeam(ledger),
					aliveByTeam = Ledger.aliveByTeam(ledger),
					timeUp = false,
				})
				expect(outcome.reason).toBe("Simultaneous")
				Ledger.apply(ledger, ended(90, outcome))
				local result = Ledger.finalize(ledger)
				-- firstBlood depends on stream order only; everything else is order-free.
				for _, p in result.participants do
					p.stats.firstBlood = false
				end
				table.insert(results, result)
			end
		end
		for i = 2, #results do
			expect(results[i]).toEqual(results[1])
		end
	end)
end)

describe("Ledger — spotting, shots, consumables, capture, distance", function()
	it("first detections count once per (team, target); repeats only mark the interaction", function()
		local ledger = newLedger()
		Ledger.applyAll(ledger, {
			{ type = "Spotted", t = 5, spotter = 2, target = 11, first = true },
			{ type = "Spotted", t = 6, spotter = 1, target = 11, first = false },
			{ type = "Spotted", t = 7, spotter = 13, target = 2, first = true },
		})
		expect(Ledger.apply(ledger, { type = "Spotted", t = 8, spotter = 3, target = 11, first = true })).toBe(false)
		expect(Ledger.apply(ledger, { type = "Spotted", t = 8, spotter = 3, target = 2, first = true })).toBe(false)
		expect(Ledger.stats(ledger, 2).spotted).toBe(1)
		expect(Ledger.stats(ledger, 2).byTargetClass.heavy.spotted).toBe(1)
		expect(Ledger.stats(ledger, 3).spotted).toBe(0)
		expect(Ledger.stats(ledger, 1).spotted).toBe(0)
		expect(Ledger.stats(ledger, 13).spotted).toBe(1)
		expect(Ledger.interactions(ledger, 1)[1].spottedIt).toBe(true)
		expect(Ledger.anomalies(ledger)).toEqual({ Duplicate = 1, Invalid = 1 })
	end)

	it("shots, consumed ammo (sorted) and consumables", function()
		local ledger = newLedger()
		for i = 1, 3 do
			Ledger.apply(ledger, { type = "Shot", t = i, shooter = 1, shellId = "iu_ap_75", ammoLeft = 40 - i })
		end
		Ledger.apply(ledger, { type = "Shot", t = 4, shooter = 1, shellId = "iu_he_75", ammoLeft = 10 })
		Ledger.apply(ledger, { type = "ConsumableUsed", t = 5, participant = 1, consumable = "repair_kit" })
		Ledger.apply(ledger, { type = "ConsumableUsed", t = 6, participant = 1, consumable = "medkit" })
		expect(Ledger.stats(ledger, 1).shotsFired).toBe(4)
		expect(Ledger.consumedAmmo(ledger, 1)).toEqual({
			{ shell = "iu_ap_75", count = 3 },
			{ shell = "iu_he_75", count = 1 },
		})
		expect(Ledger.consumedConsumables(ledger, 1)).toEqual({ "repair_kit", "medkit" })
		expect(Ledger.consumedAmmo(ledger, 99)).toEqual({})
	end)

	it("defense points from CaptureReset, capture points from finalize, distance from addDistance", function()
		local ledger = newLedger()
		expect(
			Ledger.apply(ledger, { type = "CaptureReset", t = 40, base = "base1", by = 11, capper = 1, points = 40 })
		).toBe(true)
		expect(
			Ledger.apply(ledger, { type = "CaptureReset", t = 41, base = "base1", by = 13, capper = 11, points = 5 })
		).toBe(false)
		Ledger.apply(ledger, { type = "CaptureProgress", t = 41, base = "base2", team = 1, points = 35 })
		Ledger.apply(ledger, { type = "BaseCaptured", t = 70, base = "base2", team = 1 })
		expect(Ledger.addDistance(ledger, 1, 120.5)).toBe(true)
		expect(Ledger.addDistance(ledger, 1, 0 / 0)).toBe(false)
		expect(Ledger.addDistance(ledger, 99, 10)).toBe(false)
		local result = Ledger.finalize(ledger, { endT = 70, capturePoints = { [1] = 61.5, [2] = 0 / 0 } })
		expect(statsOf(result, 11).defensePoints).toBe(40)
		expect(statsOf(result, 1).capturePoints).toBe(61.5)
		expect(statsOf(result, 2).capturePoints).toBe(0)
		expect(statsOf(result, 1).distanceM).toBe(120.5)
	end)
end)

describe("Ledger — control share, AFK and leaving (REG-RES-06)", function()
	it("controlShare = human-controlled seconds / seconds alive; botShare weights bot control", function()
		local ledger = newLedger()
		local function cc(t, id, controller, reason)
			return { type = "ControlChanged", t = t, participant = id, controller = controller, reason = reason }
		end
		Ledger.applyAll(ledger, {
			{ type = "Started", t = 0 },
			cc(0, 2, "Bot", "Disconnect"), -- absent at GO
			cc(30, 2, "Player", "Arrived"),
			cc(90, 13, "Bot", "Afk"),
			cc(100, 11, "Bot", "Left"),
			cc(105, 1, "Bot", "Disconnect"),
			cc(205, 1, "Player", "Reconnect"),
			hit({ t = 300, attacker = 1, target = 13, damage = 1000, killed = true }),
			cc(310, 13, "Player", "Reconnect"), -- dead: ignored
			cc(50, 3, "Player", "Reconnect"), -- bot slot: ignored
			ended(400),
		})
		local result = Ledger.finalize(ledger)
		local function share(id)
			local _, p = statsOf(result, id)
			return p.controlShare
		end
		expect(share(1)).toBeCloseTo(300 / 400, 1e-12)
		expect(share(2)).toBeCloseTo(370 / 400, 1e-12)
		expect(share(11)).toBeCloseTo(100 / 400, 1e-12)
		expect(share(13)).toBeCloseTo(90 / 300, 1e-12)
		expect(share(3)).toBe(0)
		expect(share(12)).toBe(0)
		local expected = (1 + 1 + (1 - 0.75) + (1 - 0.925) + (1 - 0.25) + (1 - 0.3)) / 6
		expect(result.botShare).toBeCloseTo(expected, 1e-12)
		expect(Ledger.flags(ledger, 13)).toEqual({ afkStrike = true, leftAlive = false, botTakeovers = 1, returns = 0 })
		expect(Ledger.flags(ledger, 11)).toEqual({ afkStrike = false, leftAlive = true, botTakeovers = 1, returns = 0 })
		expect(Ledger.flags(ledger, 1)).toEqual({ afkStrike = false, leftAlive = false, botTakeovers = 1, returns = 1 })
		expect(Ledger.flags(ledger, 99)).toBeNil()
		-- A disconnected player's stats are kept (REG-RES-06).
		expect(statsOf(result, 1).kills).toBe(1)
	end)

	it("a human that never arrives has controlShare 0; dying at t = 0 keeps the controller at that time", function()
		local ledger = newLedger({ { id = 1, team = 1 }, { id = 2, team = 1 }, { id = 11, team = 2 } })
		Ledger.applyAll(ledger, {
			{ type = "ControlChanged", t = 0, participant = 2, controller = "Bot", reason = "Disconnect" },
			hit({ t = 0, attacker = 2, target = 11, damage = 1000, killed = true }),
			ended(200),
		})
		local result = Ledger.finalize(ledger)
		local _, p2 = statsOf(result, 2)
		local _, p11 = statsOf(result, 11)
		local _, p1 = statsOf(result, 1)
		expect(p2.controlShare).toBe(0)
		expect(p11.controlShare).toBe(1)
		expect(p1.controlShare).toBe(1)
	end)
end)

describe("Ledger — end of battle and BattleResult", function()
	it("REG-BTL-07: hits applied before Ended count, anything after it is ignored", function()
		local ledger = newLedger()
		local outcome = Outcome.make(1, "Destruction", { 1, 2 })
		Ledger.apply(ledger, hit({ t = 300, attacker = 1, target = 11, damage = 100 }))
		Ledger.apply(ledger, ended(300, outcome))
		expect(Ledger.apply(ledger, hit({ t = 300, attacker = 1, target = 11, damage = 100 }))).toBe(false)
		expect(Ledger.addDistance(ledger, 1, 5)).toBe(false)
		local result = Ledger.finalize(ledger)
		expect(statsOf(result, 1).damageDealt).toBe(100)
		expect(result.durationS).toBe(300)
		expect(result.outcome).toEqual(outcome)
		expect(Ledger.anomalies(ledger)).toEqual({ AfterEnd = 1 })
	end)

	it("builds the header, sorts participants, leaves medals/rewards to Scoring", function()
		local shuffled = Fixtures.roster({ SLOTS[5], SLOTS[2], SLOTS[6], SLOTS[1], SLOTS[4], SLOTS[3] })
		local spec = Fixtures.ledgerSpec(shuffled, { battleType = "Encounter", eventId = nil })
		local ledger = Ledger.new(spec)
		Ledger.apply(ledger, ended(321.5, Outcome.make(2, "Capture", { 1, 2 })))
		local result = Ledger.finalize(ledger)
		expect(result.battleId).toBe("battle_test_0001")
		expect(result.mode).toBe("Random")
		expect(result.battleType).toBe("Encounter")
		expect(result.mapId).toBe("proving_grounds")
		expect(result.startedAt).toBe(1_790_000_000)
		expect(result.contentHash).toBe("0123456789abcdef")
		expect(result.durationS).toBe(321.5)
		local ids = {}
		for _, p in result.participants do
			table.insert(ids, p.participant.participantId)
			expect(p.medals).toEqual({})
			expect(p.rewards).toBeNil()
			expect(p.stats.roleScore).toBeNil()
		end
		expect(ids).toEqual({ 1, 2, 3, 11, 12, 13 })
		expect(result.botShare).toBeCloseTo(2 / 6, 1e-12)
		-- The result never aliases the caller's participants.
		expect(statsOf(result, 1) ~= nil).toBe(true)
		local _, p1 = statsOf(result, 1)
		expect(p1 == shuffled[4]).toBe(false)
	end)

	it("finalize is pure and repeatable; without Ended it reports an aborted battle at the last t", function()
		local ledger = newLedger()
		Ledger.apply(ledger, hit({ t = 42, attacker = 1, target = 11, damage = 100 }))
		local a = Ledger.finalize(ledger)
		local b = Ledger.finalize(ledger)
		expect(a).toEqual(b)
		expect(a.outcome).toEqual(Outcome.aborted({ 1, 2 }))
		expect(a.durationS).toBe(42)
		local c = Ledger.finalize(ledger, { endT = 50, outcome = Outcome.draw("Timeout", { 1, 2 }) })
		expect(c.durationS).toBe(50)
		expect(c.outcome.reason).toBe("Timeout")
		expect(Ledger.stats(ledger, 13).timeAliveS).toBe(0) -- live view untouched
	end)

	it("counts malformed and unknown events as anomalies", function()
		local ledger = newLedger()
		expect(Ledger.apply(ledger, { type = "Shot", t = 0 / 0, shooter = 1, shellId = "x", ammoLeft = 1 } :: any)).toBe(
			false
		)
		expect(Ledger.apply(ledger, "nope" :: any)).toBe(false)
		expect(Ledger.apply(ledger, { type = "Teleported", t = 1 } :: any)).toBe(false)
		expect(Ledger.apply(ledger, hit({ attacker = 77, target = 11, damage = 10 }))).toBe(false)
		expect(Ledger.apply(ledger, hit({ attacker = 1, target = 77, damage = 10 }))).toBe(false)
		expect(Ledger.apply(ledger, hit({ attacker = 1, target = 11, damage = -5 }))).toBe(false)
		expect(Ledger.apply(ledger, { type = "Shot", t = 1, shooter = 77, shellId = "x", ammoLeft = 1 })).toBe(false)
		expect(
			Ledger.apply(
				ledger,
				{ type = "ControlChanged", t = 1, participant = 77, controller = "Bot", reason = "Afk" }
			)
		).toBe(false)
		expect(Ledger.anomalies(ledger)).toEqual({ Invalid = 3, UnknownEvent = 1, UnknownParticipant = 4 })
	end)

	it("aliveByTeam / rosterByTeam / teams feed Outcome", function()
		local ledger = newLedger()
		Ledger.apply(ledger, hit({ attacker = 1, target = 11, damage = 1000, killed = true }))
		expect(Ledger.aliveByTeam(ledger)).toEqual({ [1] = 3, [2] = 2 })
		expect(Ledger.rosterByTeam(ledger)).toEqual({ [1] = 3, [2] = 3 })
		expect(Ledger.teams(ledger)).toEqual({ 1, 2 })
	end)
end)

-- Random but realistic event streams (HP-tracked kills, assists, control changes, invalid noise).
local function randomStream(seed: number)
	local rng = RNG.new(seed)
	local slots = {}
	for i = 1, 8 do
		table.insert(slots, {
			id = i * 3,
			team = if i <= 4 then 1 else 2,
			bot = rng:chance(0.3),
			class = rng:pick({ "light", "medium", "heavy", "td", "artillery" }),
		})
	end
	local hp, alive, controller = {}, {}, {}
	for _, s in slots do
		hp[s.id] = 1000
		alive[s.id] = true
		controller[s.id] = "Player"
	end
	local events = { { type = "Started", t = 0 } }
	local t = 0
	for _ = 1, 400 do
		t += rng:range(0, 2)
		local a = rng:pick(slots)
		local b = rng:pick(slots)
		local roll = rng:next()
		if roll < 0.55 and alive[b.id] then
			local enemy = a.team ~= b.team
			local kind = rng:pick({ "Shell", "Shell", "Shell", "Splash", "Fire", "Ram", "Fall", "AmmoRack" })
			local result = if kind == "Shell"
				then rng:pick({ "Penetration", "NonPenetration", "Ricochet", "Absorbed" })
				elseif kind == "Splash" then "Splash"
				else nil
			local potential = rng:int(50, 400)
			local dmg = if result == "Ricochet" or result == "Absorbed"
				then 0
				else math.min(hp[b.id], rng:int(0, potential))
			local attacker: number? = if kind == "Fall" and rng:chance(0.7) then nil else a.id
			if not enemy and attacker ~= nil then
				-- allies only ever block (sometimes a producer bug sneaks damage through)
				result = "AllyBlocked"
				dmg = if rng:chance(0.1) then 10 else 0
				kind = "Shell"
			end
			local spotters = {}
			for _ = 1, rng:int(0, 3) do
				table.insert(spotters, rng:pick(slots).id)
			end
			local killed = false
			if attacker == nil or enemy then
				hp[b.id] -= dmg
				killed = hp[b.id] <= 0
				if killed then
					alive[b.id] = false
				end
			end
			table.insert(
				events,
				hit({
					t = t,
					attacker = attacker,
					target = b.id,
					kind = kind,
					result = result,
					damage = dmg,
					potentialDamage = potential,
					killed = killed,
					assistSpotters = spotters,
					assistTrackers = if rng:chance(0.2) then { rng:pick(slots).id } else {},
					modulesHit = if rng:chance(0.2)
						then { { module = "Engine", damage = 20, state = "Damaged" } }
						else {},
				})
			)
		elseif roll < 0.7 then
			table.insert(events, { type = "Spotted", t = t, spotter = a.id, target = b.id, first = rng:chance(0.5) })
		elseif roll < 0.85 then
			table.insert(
				events,
				{ type = "Shot", t = t, shooter = a.id, shellId = rng:pick({ "s1", "s2" }), ammoLeft = 5 }
			)
		elseif not a.bot and alive[a.id] then
			local to = if controller[a.id] == "Player" then "Bot" else "Player"
			controller[a.id] = to
			table.insert(events, {
				type = "ControlChanged",
				t = t,
				participant = a.id,
				controller = to,
				reason = if to == "Bot" then rng:pick({ "Disconnect", "Afk", "Left" }) else "Reconnect",
			})
		end
	end
	table.insert(events, ended(t + 1))
	return slots, events
end

describe("Ledger — properties (seeded random streams)", function()
	it("invariants hold and results are deterministic for 40 seeds", function()
		local coverage = { kills = 0, spotAssist = 0, allyDamage = 0, blocked = 0, botControl = 0 }
		for seed = 1, 40 do
			local slots, events = randomStream(seed * 7919)
			local ledger = Ledger.new(Fixtures.ledgerSpec(Fixtures.roster(slots)))
			Ledger.applyAll(ledger, TableUtil.deepCopy(events))
			local result = Ledger.finalize(ledger)

			local dealt, receivedFromEnemies, hits, hitsReceived, pens, pensReceived = 0, 0, 0, 0, 0, 0
			local kills, deaths, spotAssist, expectedSpotAssist = 0, 0, 0, 0
			for _, p in result.participants do
				local s = p.stats
				dealt += s.damageDealt
				hits += s.hits
				hitsReceived += s.hitsReceived
				pens += s.penetrations
				pensReceived += s.penetrationsReceived
				kills += s.kills
				spotAssist += s.assistSpotting
				if not s.survived then
					deaths += 1
				else
					expect(s.timeAliveS).toBe(result.durationS)
				end
				expect(p.participant.controlShare >= 0 and p.participant.controlShare <= 1).toBe(true)
				expect(s.damageBlocked >= 0).toBe(true)
				for _, value in s do
					if type(value) == "number" then
						expect(value == value and math.abs(value) ~= math.huge).toBe(true)
					end
				end
			end
			-- Recompute what the ledger should have credited from the raw stream.
			local teamOf, isAlive = {}, {}
			for _, s in slots do
				teamOf[s.id] = s.team
				isAlive[s.id] = true
			end
			for _, e in events do
				if e.type == "Damage" and isAlive[e.damage.target] then
					local d = e.damage
					local attacker = if d.attacker == d.target then nil else d.attacker
					if attacker == nil or teamOf[attacker] ~= teamOf[d.target] then
						if attacker ~= nil then
							receivedFromEnemies += d.damage
							if d.damage > 0 then
								local seen = {}
								for _, id in d.assistSpotters do
									if teamOf[id] == teamOf[attacker] and id ~= attacker and not seen[id] then
										seen[id] = true
										expectedSpotAssist += d.damage
									end
								end
							end
						end
						if d.killed then
							isAlive[d.target] = false
						end
					end
				end
			end
			expect(dealt).toBe(receivedFromEnemies)
			expect(hits).toBe(hitsReceived)
			expect(pens).toBe(pensReceived)
			expect(spotAssist).toBe(expectedSpotAssist)
			expect(kills <= deaths).toBe(true)
			expect(#Ledger.killFeed(ledger)).toBe(deaths)
			coverage.kills += kills
			coverage.spotAssist += spotAssist
			coverage.allyDamage += Ledger.anomalies(ledger).AllyDamage or 0
			for _, p in result.participants do
				coverage.blocked += p.stats.damageBlocked
				if not p.participant.isBot and p.participant.controlShare < 1 then
					coverage.botControl += 1
				end
			end

			-- Replays and roster order never change the result.
			local again = Ledger.new(Fixtures.ledgerSpec(Fixtures.roster(slots)))
			Ledger.applyAll(again, TableUtil.deepCopy(events))
			expect(Ledger.finalize(again)).toEqual(result)
			local reversed = {}
			for i = #slots, 1, -1 do
				table.insert(reversed, slots[i])
			end
			local other = Ledger.new(Fixtures.ledgerSpec(Fixtures.roster(reversed)))
			Ledger.applyAll(other, TableUtil.deepCopy(events))
			expect(Ledger.finalize(other)).toEqual(result)
		end
		-- The generator really exercises kills, assists, blocked hits, FF noise and bot hand-overs.
		for key, value in coverage do
			if value <= 0 then
				error(`random streams never exercised {key}`)
			end
		end
	end)
end)
