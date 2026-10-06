local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Outcome = require("@game/ReplicatedStorage/Shared/Battle/Rules/Outcome")

local STANDARD = ModeRules.defaults("Random", "Standard")
local ENCOUNTER = ModeRules.defaults("Random", "Encounter")
local ASSAULT = ModeRules.defaults("Random", "Assault")
local PRACTICE = ModeRules.defaults("Practice")

local function input(settings, alive1: number, alive2: number, extra)
	local i = {
		settings = settings,
		teams = { 1, 2 },
		rosterByTeam = { [1] = 15, [2] = 15 },
		aliveByTeam = { [1] = alive1, [2] = alive2 },
		captured = nil,
		timeUp = false,
		defender = nil,
	}
	if extra then
		for k, v in extra do
			i[k] = v
		end
	end
	return i
end

local function summary(outcome): string?
	if outcome == nil then
		return nil
	end
	local rows = {}
	for _, row in outcome.teams do
		table.insert(rows, `{row.team}={row.outcome}`)
	end
	return `{tostring(outcome.winner)}|{outcome.reason}|{table.concat(rows, ",")}`
end

describe("Outcome.evaluate (00-DECISIONS §9, REG-BTL-02)", function()
	it("nothing ends a battle with both teams alive, no capture and time left", function()
		expect(Outcome.evaluate(input(STANDARD, 3, 1))).toBeNil()
	end)

	it("wiping every enemy wins by destruction", function()
		expect(summary(Outcome.evaluate(input(STANDARD, 2, 0)))).toBe("1|Destruction|1=Victory,2=Defeat")
		expect(summary(Outcome.evaluate(input(STANDARD, 0, 5)))).toBe("2|Destruction|1=Defeat,2=Victory")
	end)

	it("both teams wiped on the same tick is a Simultaneous draw, whatever the team order", function()
		local a = Outcome.evaluate(input(STANDARD, 0, 0))
		expect(summary(a)).toBe("nil|Simultaneous|1=Draw,2=Draw")
		local b = Outcome.evaluate(input(STANDARD, 0, 0, { teams = { 2, 1 } }))
		expect(b).toEqual(a)
		-- Assault: a double wipe beats the defender's timeout rule.
		expect(summary(Outcome.evaluate(input(ASSAULT, 0, 0, { timeUp = true, defender = 2 })))).toBe(
			"nil|Simultaneous|1=Draw,2=Draw"
		)
	end)

	it("a completed capture wins; a double capture on one tick is a draw", function()
		expect(summary(Outcome.evaluate(input(STANDARD, 4, 4, { captured = { 2 } })))).toBe(
			"2|Capture|1=Defeat,2=Victory"
		)
		expect(summary(Outcome.evaluate(input(STANDARD, 4, 4, { captured = { 1, 2 } })))).toBe(
			"nil|Simultaneous|1=Draw,2=Draw"
		)
		expect(summary(Outcome.evaluate(input(STANDARD, 4, 4, { captured = { 2, 2 } })))).toBe(
			"2|Capture|1=Defeat,2=Victory"
		)
	end)

	it("capture-complete and wipe on the same tick", function()
		-- Same team: victory, reason per config ("Capture" by default).
		expect(summary(Outcome.evaluate(input(STANDARD, 1, 0, { captured = { 1 } })))).toBe(
			"1|Capture|1=Victory,2=Defeat"
		)
		local alt = ModeRules.with(STANDARD, { wipeAndCaptureReason = "Destruction" })
		expect(summary(Outcome.evaluate(input(alt, 1, 0, { captured = { 1 } })))).toBe(
			"1|Destruction|1=Victory,2=Defeat"
		)
		-- Opposite claims (team 1 captures while being wiped): Simultaneous draw.
		expect(summary(Outcome.evaluate(input(STANDARD, 0, 3, { captured = { 1 } })))).toBe(
			"nil|Simultaneous|1=Draw,2=Draw"
		)
	end)

	it("timeout: Standard/Encounter draw, Assault defender holds", function()
		expect(summary(Outcome.evaluate(input(STANDARD, 3, 3, { timeUp = true })))).toBe("nil|Timeout|1=Draw,2=Draw")
		expect(summary(Outcome.evaluate(input(ENCOUNTER, 3, 3, { timeUp = true })))).toBe("nil|Timeout|1=Draw,2=Draw")
		expect(summary(Outcome.evaluate(input(ASSAULT, 3, 3, { timeUp = true, defender = 2 })))).toBe(
			"2|DefenderHeld|1=Defeat,2=Victory"
		)
		expect(summary(Outcome.evaluate(input(ASSAULT, 3, 3, { timeUp = true })))).toBe("nil|Timeout|1=Draw,2=Draw")
	end)

	it("hits and captures resolved on the final tick beat the timeout (REG-BTL-07)", function()
		expect(summary(Outcome.evaluate(input(STANDARD, 2, 0, { timeUp = true })))).toBe(
			"1|Destruction|1=Victory,2=Defeat"
		)
		expect(summary(Outcome.evaluate(input(ASSAULT, 2, 2, { timeUp = true, defender = 2, captured = { 1 } })))).toBe(
			"1|Capture|1=Victory,2=Defeat"
		)
	end)

	it("Assault: either side wins by destruction", function()
		expect(summary(Outcome.evaluate(input(ASSAULT, 0, 2, { defender = 2 })))).toBe(
			"2|Destruction|1=Defeat,2=Victory"
		)
		expect(summary(Outcome.evaluate(input(ASSAULT, 2, 0, { defender = 2 })))).toBe(
			"1|Destruction|1=Victory,2=Defeat"
		)
	end)

	it("Practice ignores wipes and captures; only the timer ends it", function()
		expect(Outcome.evaluate(input(PRACTICE, 1, 0, { captured = { 1 } }))).toBeNil()
		expect(summary(Outcome.evaluate(input(PRACTICE, 1, 0, { timeUp = true })))).toBe("nil|Timeout|1=Draw,2=Draw")
	end)

	it("an empty team is never 'wiped' (solo or empty bot team)", function()
		local solo = input(STANDARD, 1, 0, { rosterByTeam = { [1] = 1, [2] = 0 } })
		expect(Outcome.evaluate(solo)).toBeNil()
		solo.aliveByTeam[1] = 0
		expect(summary(Outcome.evaluate(solo))).toBe("nil|Destruction|1=Draw,2=Draw")
	end)

	it("three teams: the last team standing wins, two survivors keep playing", function()
		local i = input(STANDARD, 0, 2, { teams = { 1, 2, 3 }, rosterByTeam = { [1] = 5, [2] = 5, [3] = 5 } })
		i.aliveByTeam[3] = 1
		expect(Outcome.evaluate(i)).toBeNil()
		i.aliveByTeam[3] = 0
		expect(summary(Outcome.evaluate(i))).toBe("2|Destruction|1=Defeat,2=Victory,3=Defeat")
	end)

	it("every ordering of simultaneous claims yields the same outcome", function()
		local orders = { { 1, 2 }, { 2, 1 } }
		local first = nil
		for _, teams in orders do
			for _, captured in { { 1, 2 }, { 2, 1 } } do
				local r = Outcome.evaluate(input(STANDARD, 1, 1, { teams = teams, captured = captured }))
				if first == nil then
					first = r
				end
				expect(r).toEqual(first)
			end
		end
	end)
end)

describe("Outcome helpers", function()
	it("make / draw / aborted / resultFor / isWin", function()
		local win = Outcome.make(2, "Capture", { 2, 1, 2 })
		expect(win.teams).toEqual({ { team = 1, outcome = "Defeat" }, { team = 2, outcome = "Victory" } })
		expect(Outcome.resultFor(win, 1)).toBe("Defeat")
		expect(Outcome.resultFor(win, 2)).toBe("Victory")
		expect(Outcome.resultFor(win, 9)).toBe("Draw")
		expect(Outcome.isWin(win, 2)).toBe(true)
		expect(Outcome.isWin(win, 1)).toBe(false)
		local aborted = Outcome.aborted({ 1, 2 })
		expect(aborted.winner).toBeNil()
		expect(aborted.reason).toBe("Aborted")
		expect(Outcome.isWin(aborted, 1)).toBe(false)
		expect(Outcome.timeout(ASSAULT, { 1, 2 }, 1).reason).toBe("DefenderHeld")
		expect(Outcome.timeout(ASSAULT, { 1, 2 }, 5).reason).toBe("Timeout")
	end)
end)
