local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local KillCredit = require("@game/ReplicatedStorage/Shared/Battle/Ledger/KillCredit")

-- 1, 2 team 1; 11, 12 team 2.
local TEAMS = { [1] = 1, [2] = 1, [11] = 2, [12] = 2 }
local WINDOW = 5

local function credit(cause, attacker, lastDamager, lastT, t)
	return KillCredit.resolve(cause, attacker, 11, t or 100, TEAMS, lastDamager, lastT, WINDOW)
end

describe("KillCredit.resolve (00-DECISIONS §2)", function()
	it("shell, splash, ram, ammo rack and fire credit the enemy attacker (fire = igniter)", function()
		for _, cause in { "Shell", "Splash", "Ram", "AmmoRack", "Fire" } do
			expect(credit(cause, 1)).toBe(1)
		end
	end)

	it("never credits allies, the victim itself, unknown ids or the environment", function()
		for _, cause in { "Shell", "Splash", "Ram", "AmmoRack", "Fire", "Fall" } do
			expect(credit(cause, 12)).toBeNil()
			expect(credit(cause, 11)).toBeNil()
			expect(credit(cause, 99)).toBeNil()
			expect(credit(cause, nil)).toBeNil()
		end
	end)

	it("drowning credits nobody, not even an attacker or a recent damager", function()
		expect(credit("Drown", 1, 2, 99)).toBeNil()
		expect(credit("Drown", nil, 2, 99)).toBeNil()
	end)

	it("falls: the attacker when present, else the last enemy damager inside the window", function()
		expect(credit("Fall", 2, 1, 99)).toBe(2)
		expect(credit("Fall", nil, 1, 95)).toBe(1) -- exactly 5 s
		expect(credit("Fall", nil, 1, 94.99)).toBeNil()
		expect(credit("Fall", nil, 12, 99)).toBeNil() -- ally of the victim
		expect(credit("Fall", nil, 1, 101)).toBeNil() -- damage "after" the death is ignored
		expect(credit("Fall", nil, nil, nil)).toBeNil()
	end)

	it("only falls use the last-damager fallback", function()
		for _, cause in { "Shell", "Fire", "AmmoRack", "Ram" } do
			expect(credit(cause, nil, 1, 99)).toBeNil()
		end
		expect(credit("Meteor" :: any, 1)).toBeNil()
	end)

	it("isEnemy", function()
		expect(KillCredit.isEnemy(TEAMS, 1, 11)).toBe(true)
		expect(KillCredit.isEnemy(TEAMS, 1, 2)).toBe(false)
		expect(KillCredit.isEnemy(TEAMS, 1, 1)).toBe(false)
		expect(KillCredit.isEnemy(TEAMS, nil, 1)).toBe(false)
		expect(KillCredit.isEnemy(TEAMS, 1, 77)).toBe(false)
	end)

	it("documents the rule per kind", function()
		expect(KillCredit.RULES).toEqual({
			Shell = "Attacker",
			Splash = "Attacker",
			Ram = "Attacker",
			AmmoRack = "Attacker",
			Fire = "Attacker",
			Fall = "AttackerOrLastDamager",
			Drown = "None",
		})
	end)
end)
