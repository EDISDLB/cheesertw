local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Attribution = require("@game/ReplicatedStorage/Shared/Battle/Ledger/Attribution")
local Fixtures = require("./BattleFixtures")

-- Team 1: 1 (shooter), 2, 3, 4. Team 2: 11 (target), 12 (wheeled), 13.
local ROSTER = {
	{ participantId = 1, team = 1 },
	{ participantId = 2, team = 1 },
	{ participantId = 3, team = 1 },
	{ participantId = 4, team = 1 },
	{ participantId = 11, team = 2 },
	{ participantId = 12, team = 2, wheeled = true },
	{ participantId = 13, team = 2 },
}

local function new(settings)
	return Attribution.new(ROSTER, settings)
end

local function lists(state, attacker, target, t)
	local d = Attribution.fill(state, Fixtures.damage({ attacker = attacker, target = target, t = t, damage = 100 }))
	return { spot = d.assistSpotters, track = d.assistTrackers, stun = d.assistStunners }
end

describe("Attribution — spotting assist (00-DECISIONS §5, report 02 R8)", function()
	it("allies of the shooter who saw the target ≤ 10 s ago are listed (boundary inclusive)", function()
		local state = new()
		Attribution.noteSeen(state, 2, 11, 5)
		expect(lists(state, 1, 11, 14.9).spot).toEqual({ 2 })
		expect(lists(state, 1, 11, 15).spot).toEqual({ 2 })
		expect(lists(state, 1, 11, 15.01).spot).toEqual({})
	end)

	it("a refreshing check extends the window; older timestamps never shorten it", function()
		local state = new()
		Attribution.noteSeen(state, 2, 11, 5)
		Attribution.noteSeen(state, 2, 11, 12)
		Attribution.noteSeen(state, 2, 11, 7)
		expect(lists(state, 1, 11, 21).spot).toEqual({ 2 })
		expect(lists(state, 1, 11, 22.5).spot).toEqual({})
	end)

	it("the attacker is never its own spotter; several spotters are sorted and unique", function()
		local state = new()
		for _, observer in { 4, 1, 2, 2 } do
			Attribution.noteSeen(state, observer, 11, 10)
		end
		expect(lists(state, 1, 11, 11).spot).toEqual({ 2, 4 })
	end)

	it("REG-SPT-07: a destroyed spotter is still credited inside its 10 s window", function()
		local state = new()
		Attribution.noteSeen(state, 2, 11, 5)
		Attribution.noteSeen(state, 3, 11, 5)
		Attribution.observe(
			state,
			{ type = "Destroyed", t = 6, target = 2, cause = "Shell", attacker = 11, assisters = {} }
		)
		expect(lists(state, 4, 11, 12).spot).toEqual({ 2, 3 })
		expect(lists(state, 4, 11, 15.5).spot).toEqual({})
	end)

	it("sightings of the future, of allies and by unknown ids are ignored", function()
		local state = new()
		Attribution.noteSeen(state, 2, 11, 30)
		expect(lists(state, 1, 11, 20).spot).toEqual({})
		Attribution.noteSeen(state, 2, 3, 10)
		Attribution.noteSeen(state, 99, 11, 10)
		Attribution.noteSeen(state, 2, 11, 0 / 0)
		expect(lists(state, 1, 11, 31).spot).toEqual({ 2 })
	end)

	it("Spotted events count as successful checks", function()
		local state = new()
		Attribution.observe(state, { type = "Spotted", t = 3, spotter = 3, target = 13, first = true })
		expect(lists(state, 1, 13, 8).spot).toEqual({ 3 })
	end)

	it("the window comes from the settings", function()
		local state = new(ModeRules.with(ModeRules.defaults("Random", "Standard"), { assistSpotWindowS = 3 }))
		Attribution.noteSeen(state, 2, 11, 5)
		expect(lists(state, 1, 11, 8).spot).toEqual({ 2 })
		expect(lists(state, 1, 11, 8.1).spot).toEqual({})
	end)
end)

describe("Attribution — tracking and stun assist", function()
	it("the destroyer of a still-destroyed track side is listed until the repair", function()
		local state = new()
		Attribution.noteModuleState(state, 11, "TrackLeft", "Destroyed", 2)
		expect(Attribution.isTracked(state, 11)).toBe(true)
		expect(lists(state, 1, 11, 10).track).toEqual({ 2 })
		Attribution.noteModuleState(state, 11, "TrackLeft", "Damaged", nil)
		expect(lists(state, 1, 11, 11).track).toEqual({})
		expect(Attribution.isTracked(state, 11)).toBe(false)
	end)

	it("both sides by different allies → both; re-tracking a side moves it to the latest destroyer", function()
		local state = new()
		Attribution.observe(
			state,
			{ type = "ModuleState", t = 1, target = 11, module = "TrackRight", state = "Destroyed", attacker = 4 }
		)
		Attribution.observe(
			state,
			{ type = "ModuleState", t = 2, target = 11, module = "TrackLeft", state = "Destroyed", attacker = 2 }
		)
		expect(lists(state, 1, 11, 3).track).toEqual({ 2, 4 })
		Attribution.noteModuleState(state, 11, "TrackLeft", "Destroyed", 3)
		expect(lists(state, 1, 11, 4).track).toEqual({ 3, 4 })
		-- The tracker itself shooting is not its own assist.
		expect(lists(state, 4, 11, 5).track).toEqual({ 3 })
		-- Environment-destroyed tracks immobilise but credit nobody.
		Attribution.noteModuleState(state, 13, "TrackLeft", "Destroyed", nil)
		expect(lists(state, 1, 13, 5).track).toEqual({})
	end)

	it("wheeled targets give no tracking assist unless WHEELED_TRACK_ASSIST", function()
		local state = new()
		Attribution.noteModuleState(state, 12, "TrackLeft", "Destroyed", 2)
		expect(lists(state, 1, 12, 5).track).toEqual({})
		local permissive = new(ModeRules.with(ModeRules.defaults("Random", "Standard"), { wheeledTrackAssist = true }))
		Attribution.noteModuleState(permissive, 12, "TrackLeft", "Destroyed", 2)
		expect(lists(permissive, 1, 12, 5).track).toEqual({ 2 })
	end)

	it("stunners are listed while their stun runs; medkit clears; re-stun extends", function()
		local state = new()
		Attribution.observe(state, { type = "Stunned", t = 10, target = 11, attacker = 3, durationS = 8 })
		Attribution.noteStun(state, 11, 2, 12, 4)
		expect(lists(state, 1, 11, 15).stun).toEqual({ 2, 3 })
		expect(lists(state, 1, 11, 17).stun).toEqual({ 3 })
		expect(lists(state, 1, 11, 18.01).stun).toEqual({})
		Attribution.noteStun(state, 11, 3, 20, 8)
		Attribution.noteStun(state, 11, 3, 21, 1) -- shorter re-stun never shortens
		expect(lists(state, 1, 11, 27).stun).toEqual({ 3 })
		Attribution.clearStun(state, 11)
		expect(lists(state, 1, 11, 22).stun).toEqual({})
		Attribution.noteStun(state, 11, 3, 30, 0 / 0)
		Attribution.noteStun(state, 11, 3, 30, -1)
		expect(lists(state, 1, 11, 30).stun).toEqual({})
	end)

	it("a destroyed target loses its track and stun records", function()
		local state = new()
		Attribution.noteModuleState(state, 11, "TrackLeft", "Destroyed", 2)
		Attribution.noteStun(state, 11, 3, 1, 10)
		Attribution.noteDestroyed(state, 11)
		local l = lists(state, 1, 11, 2)
		expect(l.track).toEqual({})
		expect(l.stun).toEqual({})
	end)
end)

describe("Attribution.fill", function()
	it("reuses the event's arrays and clears stale entries", function()
		local state = new()
		local d = Fixtures.damage({ attacker = 1, target = 11, t = 5, damage = 50 })
		local spotters = d.assistSpotters
		table.insert(spotters, 99)
		Attribution.noteSeen(state, 2, 11, 4)
		Attribution.fill(state, d)
		expect(d.assistSpotters).toBe(spotters)
		expect(d.assistSpotters).toEqual({ 2 })
		local bare = Fixtures.damage({ attacker = 1, target = 11, t = 5 })
		bare.assistTrackers = nil :: any
		Attribution.fill(state, bare)
		expect(bare.assistTrackers).toEqual({})
	end)

	it("ally damage, self damage and environment damage get empty lists", function()
		local state = new()
		Attribution.noteSeen(state, 2, 11, 4)
		Attribution.noteSeen(state, 12, 3, 4)
		for _, pair in { { 2, 3 }, { 11, 11 }, { nil, 11 }, { 99, 11 } } do
			local l = lists(state, pair[1], pair[2], 5)
			expect(l.spot).toEqual({})
			expect(l.track).toEqual({})
			expect(l.stun).toEqual({})
		end
		-- Observers on the target's side are never listed for the other side's damage.
		expect(lists(state, 1, 11, 5).spot).toEqual({ 2 })
	end)
end)
