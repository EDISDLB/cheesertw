-- GunState: every reload kind as table-driven timelines, shell swap rules, trigger semantics, mechanics
-- (ChargedShot, ActiveCooling, AdaptiveMagazine), death/gun-destroyed edge cases, snapshots, invariants and
-- allocation. Regression ids: REG-PRJ-05 (shots per clip, rejected fire during intra-clip/reload, volley = 2
-- shells), REG-RET-05 (displayed reload = GunState remaining after injury/heal, swap, clip end, intra-clip),
-- REG-SND-08 (clip counts), REG-SEC-01 (fire requests during reload produce no shot), REG-NET-06 (fire validated
-- against alive/reload/ammo/gun state).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local GunState = require("@game/ReplicatedStorage/Shared/Vehicle/GunState")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local function shell(id: string, kind: string): any
	return {
		id = id,
		kind = kind,
		special = kind == "APCR",
		caliberMm = 76,
		damage = 100,
		moduleDamage = 50,
		penetrationMm = 100,
		penetrationAt500Mm = 90,
		velocityMps = 500,
		gravityMps2 = 19.62,
		maxRangeM = 600,
		explosionRadiusM = 0,
		normalizationDeg = 5,
		ricochetAngleDeg = 70,
		priceCredits = 0,
		tracer = "AP",
	}
end

local SHELLS = { shell("ap", "AP"), shell("apcr", "APCR"), shell("he", "HE") }

local function oneReload(reload: any): number
	if reload.kind == "Single" or reload.kind == "Magazine" then
		return reload.reloadS
	elseif reload.kind == "Autoreloader" then
		return reload.perShellReloadS[1]
	end
	return reload.reloadEachS
end

local function gun(reload: any, swapS: number?, capacity: number?): any
	return {
		id = "test_gun",
		caliberMm = 76,
		reload = reload,
		dispersionM100 = 0.4,
		aimTimeS = 2,
		bloom = {
			movementPerKmh = 0.07,
			hullTraversePerDegS = 0.075,
			turretTraversePerDegS = 0.03,
			afterShot = 3,
			damagedMul = 1.5,
		},
		depressionDeg = 8,
		elevationDeg = 20,
		arcSectors = {},
		shells = SHELLS,
		ammoCapacity = capacity or 100,
		camoAfterShotMul = 0.3,
		shellSwapS = swapS or oneReload(reload),
		indirect = false,
		damageRollMinAdd = 0,
		penetrationRollMinAdd = 0,
	}
end

local function ammo(a: number, b: number?, c: number?): any
	return { { shell = "ap", count = a }, { shell = "apcr", count = b or 0 }, { shell = "he", count = c or 0 } }
end

local SINGLE = { kind = "Single", reloadS = 2 }
local MAGAZINE = { kind = "Magazine", size = 4, intraClipS = 2, reloadS = 18 }
local AUTO = { kind = "Autoreloader", size = 3, perShellReloadS = { 9, 7, 6 }, intraClipS = 2 }
local DUAL = { kind = "DualGun", reloadEachS = 12, salvoDelayS = 1.5, chargeTimeS = 1.0, volleyDispersionMul = 1.5 }

-- Runs a timeline: each step is { t, action, arg?, expect = value | { ok, reason } }.
-- Actions: "fire" (expects slot fired or false), "can" (expects true/false[, reason]), "trigger" (arg = held,
-- expects slot fired / nil), "update" (expects volley rounds or nil), "select" (arg = slot), "mag" (expects rounds
-- loaded), "ammo" (arg = slot, expects total), "reload".
local function run(state: any, steps: { any })
	for i, step in steps do
		local t, action, arg, want = step[1], step[2], step[3], step[4]
		local label = `step {i} @ {t}s {action}`
		if action == "fire" then
			local shot, reason = GunState.fire(state, t)
			if want == false then
				if shot ~= nil then
					error(`{label}: expected no shot, fired slot {shot.slot}`)
				end
				if arg ~= nil then
					expect(reason).toBe(arg)
				end
			else
				if shot == nil then
					error(`{label}: expected a shot, got {tostring(reason)}`)
				end
				expect(shot.slot).toBe(want)
				expect(shot.time).toBeCloseTo(t, 1e-9)
			end
		elseif action == "can" then
			local ok, reason = GunState.canFire(state, t)
			if ok ~= want then
				error(`{label}: canFire {tostring(ok)} ({tostring(reason)}), expected {tostring(want)}`)
			end
			if arg ~= nil then
				expect(reason).toBe(arg)
			end
		elseif action == "trigger" then
			local shot = GunState.setTrigger(state, arg, t)
			if want == nil then
				if shot ~= nil then
					error(`{label}: unexpected shot (slot {shot.slot}, rounds {shot.rounds})`)
				end
			else
				if shot == nil then
					error(`{label}: expected a shot`)
				end
				expect(shot.rounds).toBe(want)
			end
		elseif action == "update" then
			local shot = GunState.update(state, t)
			if want == nil then
				expect(shot).toBeNil()
			else
				if shot == nil then
					error(`{label}: expected an automatic shot`)
				end
				expect(shot.rounds).toBe(want)
			end
		elseif action == "select" then
			local ok, reason = GunState.selectShell(state, arg, t)
			if want ~= nil then
				if ok ~= want[1] then
					error(`{label}: select {tostring(ok)} ({tostring(reason)})`)
				end
				expect(reason).toBe(want[2])
			end
		elseif action == "mag" then
			GunState.update(state, t)
			expect(GunState.roundsLoaded(state)).toBe(want)
		elseif action == "ammo" then
			GunState.update(state, t)
			expect(GunState.ammoOf(state, arg)).toBe(want)
		elseif action == "reload" then
			local ok, reason = GunState.reload(state, t)
			expect(ok).toBe(want[1])
			expect(reason).toBe(want[2])
		else
			error("unknown action " .. tostring(action))
		end
	end
end

local function checkInvariants(state: any, initial: number)
	local total, rack = 0, 0
	for _, slot in state.slots do
		expect(slot.rack >= 0).toBe(true)
		expect(slot.rack <= slot.total).toBe(true)
		expect(slot.total >= 0).toBe(true)
		total += slot.total
		rack += slot.rack
	end
	expect(total).toBe(initial - state.roundsFired)
	-- every round is either in the rack, ready in the gun or reserved by exactly one running reload
	local reserved = 0
	for _, timer in state.timers do
		if timer.active then
			reserved += timer.rounds
			expect(timer.work >= 0).toBe(true)
		end
	end
	expect(rack + reserved + GunState.roundsLoaded(state)).toBe(total)
	expect(GunState.roundsLoaded(state) <= state.size).toBe(true)
end

describe("GunState: Single", function()
	it("fires on a loaded gun, reloads reloadS, rejects fire while reloading (REG-PRJ-05, REG-SEC-01)", function()
		local state = GunState.new(gun(SINGLE), ammo(10, 2, 0))
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 0, "can", "RELOADING", false },
			{ 1.999, "fire", "RELOADING", false },
			{ 2.0, "can", nil, true },
			{ 2.0, "fire", nil, 1 },
			{ 4.5, "fire", nil, 1 },
			{ 4.5, "ammo", 1, 7 },
		})
		expect(state.shotsFired).toBe(3)
	end)

	it("100 forged fire requests during a reload produce no shot (REG-SEC-01)", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		GunState.fire(state, 0)
		local fired = 0
		for i = 1, 100 do
			if GunState.fire(state, i * 0.0199) ~= nil then
				fired += 1
			end
		end
		expect(fired).toBe(0)
		expect(GunState.ammoOf(state, 1)).toBe(9)
	end)

	it("a reload multiplier change mid-reload rescales only the remaining time (REG-RET-05)", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 10 }), ammo(10))
		GunState.fire(state, 0)
		GunState.setReloadMul(state, 2, 5) -- loader injured at 5 s: 5 base s left → 10 real s
		local snap = GunState.snapshot(state, 5)
		expect(snap.reloadRemainingS).toBeCloseTo(10, 1e-9)
		expect(snap.reloadProgress).toBeCloseTo(0.5, 1e-9)
		GunState.setReloadMul(state, 1, 10) -- healed at 10 s: 2.5 base s left
		expect(GunState.snapshot(state, 10).reloadRemainingS).toBeCloseTo(2.5, 1e-9)
		expect(GunState.canFire(state, 12.4999)).toBe(false)
		expect(GunState.canFire(state, 12.5)).toBe(true)
	end)

	it("clamps hostile reload multipliers", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		GunState.setReloadMul(state, 0 / 0, 0)
		expect(state.reloadMul).toBe(1)
		GunState.setReloadMul(state, -3, 0)
		expect(state.reloadMul).toBe(1)
		GunState.setReloadMul(state, 1e9, 0)
		expect(state.reloadMul).toBe(GunState.DEFAULTS.MAX_RELOAD_MUL)
		GunState.setReloadMul(state, 1e-9, 0)
		expect(state.reloadMul).toBe(GunState.DEFAULTS.MIN_RELOAD_MUL)
	end)

	it("swapping away from a loaded round is a full reload × swapFactor; the round goes back to the rack", function()
		-- Intuition-style swap: shellSwapS = 0.6 × reload
		local state = GunState.new(gun(SINGLE, 1.2), ammo(10, 5))
		expect(state.swapFactor).toBeCloseTo(0.6, 1e-12)
		run(state, {
			{ 1, "select", 2, { true, nil } },
			{ 1, "can", "RELOADING", false },
			{ 1, "ammo", 1, 10 }, -- unloaded AP is back in the rack
			{ 2.1999, "can", nil, false },
			{ 2.2, "fire", nil, 2 },
		})
		expect(GunState.ammoOf(state, 2)).toBe(4)
	end)

	it("switching while nothing is loaded keeps the reload progress (only the loading shell changes)", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 10 }), ammo(10, 5))
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 6, "select", 2, { true, nil } },
			{ 9.999, "can", nil, false },
			{ 10, "fire", nil, 2 },
		})
		-- the AP round that was being loaded at 6 s went back: 10 − 1 fired = 9 AP; APCR 5 − 1 = 4
		expect(GunState.ammoOf(state, 1)).toBe(9)
		expect(GunState.ammoOf(state, 2)).toBe(4)
	end)

	it("rejects unknown and empty shells; reselecting the current shell is a no-op", function()
		local state = GunState.new(gun(SINGLE), ammo(10, 0, 3))
		run(state, {
			{ 0, "select", 9, { false, "UNKNOWN_SHELL" } },
			{ 0, "select", 2, { false, "NO_AMMO" } },
			{ 0, "select", 1, { true, nil } },
			{ 0, "can", nil, true },
		})
		local ok, reason = GunState.selectShellById(state, "he", 0)
		expect(ok).toBe(true)
		expect(reason).toBeNil()
		expect(state.selected).toBe(3)
		expect((GunState.selectShellById(state, "nope", 0))).toBe(false)
	end)

	it("running out of the selected shell loads the next one in hotkey order, then empties", function()
		local state = GunState.new(gun(SINGLE), ammo(1, 0, 1))
		run(state, {
			{ 0, "fire", nil, 1 }, -- last AP: auto-selects HE and loads it (normal reload)
			{ 2, "fire", nil, 3 },
			{ 4, "fire", "EMPTY", false },
		})
		local snap = GunState.snapshot(state, 4)
		expect(snap.phase).toBe("Empty")
		expect(snap.totalAmmo).toBe(0)
		expect(snap.nextShotS).toBe(math.huge)
		expect(snap.reloadProgress).toBe(0)
	end)

	it("a destroyed gun cannot fire but keeps reloading; repaired it fires at once", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		run(state, { { 0, "fire", nil, 1 } })
		GunState.setEnabled(state, false, 0.5)
		run(state, { { 3, "fire", "GUN_DESTROYED", false } })
		local snap = GunState.snapshot(state, 3)
		expect(snap.phase).toBe("Disabled")
		expect(snap.roundsLoaded).toBe(1) -- the reload completed at 2 s while disabled
		GunState.setEnabled(state, true, 3)
		run(state, { { 3, "fire", nil, 1 } })
	end)

	it("death mid-reload freezes the gun", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 10 }), ammo(10))
		GunState.fire(state, 0)
		GunState.kill(state, 4)
		local snap = GunState.snapshot(state, 100)
		expect(snap.phase).toBe("Dead")
		expect(snap.reloadProgress).toBeCloseTo(0.4, 1e-9)
		expect(snap.canFire).toBe(false)
		expect(snap.nextShotS).toBe(math.huge)
		run(state, { { 100, "fire", "DEAD", false } })
		expect((GunState.selectShell(state, 1, 100))).toBe(false)
	end)

	it("a reload completing exactly at the death time completes, but nothing fires after kill()", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		GunState.fire(state, 0)
		GunState.kill(state, 2.0)
		expect(GunState.roundsLoaded(state)).toBe(1)
		expect(GunState.snapshot(state, 2).reloadProgress).toBe(1)
		run(state, { { 2.0, "fire", "DEAD", false } })
		-- the other order in the same instant: the shot (tick step 3) precedes the kill (tick step 5)
		local other = GunState.new(gun(SINGLE), ammo(10))
		GunState.fire(other, 0)
		run(other, { { 2.0, "fire", nil, 1 } })
		GunState.kill(other, 2.0)
		expect(other.roundsFired).toBe(2)
	end)

	it("time never runs backwards; NaN/inf times are ignored", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		GunState.fire(state, 5)
		expect((GunState.canFire(state, 1))).toBe(false) -- earlier than the clock: still reloading
		expect((GunState.canFire(state, 0 / 0))).toBe(false)
		expect((GunState.canFire(state, math.huge))).toBe(false)
		expect(state.time).toBe(5)
		expect((GunState.canFire(state, 7))).toBe(true)
	end)

	it("press fires once; holding never refires; a press during the reload does nothing", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		run(state, {
			{ 0, "trigger", true, 1 },
			{ 0.5, "trigger", true, nil },
			{ 2.5, "trigger", true, nil }, -- still held after the reload: no auto-fire
			{ 2.6, "trigger", false, nil },
			{ 3.0, "trigger", true, 1 },
			{ 3.1, "trigger", false, nil },
			{ 3.2, "trigger", true, nil }, -- reloading
			{ 3.3, "trigger", false, nil },
		})
	end)

	it("drops shells the gun cannot fire and caps the load at ammoCapacity", function()
		local state = GunState.new(gun(SINGLE, nil, 12), {
			{ shell = "ap", count = 10 },
			{ shell = "foreign", count = 5 },
			{ shell = "he", count = 10.7 },
			{ shell = "ap", count = 3 },
		})
		expect(#state.slots).toBe(2)
		expect(GunState.ammoOf(state, 1)).toBe(10)
		expect(GunState.ammoOf(state, 2)).toBe(2)
		expect(GunState.totalAmmo(state)).toBe(12)
		local empty = GunState.new(gun(SINGLE), {})
		expect(GunState.canFire(empty, 0)).toBe(false)
		expect(GunState.snapshot(empty, 0).phase).toBe("Empty")
	end)

	it("can start unloaded (reload from the first instant)", function()
		local state = GunState.new(gun(SINGLE), ammo(10), { startLoaded = false, now = 3 })
		run(state, { { 4.99, "can", "RELOADING", false }, { 5, "fire", nil, 1 } })
	end)
end)

describe("GunState: Magazine", function()
	it("intra-clip, full magazine reload and the per-clip shot cap (REG-PRJ-05, REG-SND-08)", function()
		local state = GunState.new(gun(MAGAZINE), ammo(20))
		run(state, {
			{ 0, "mag", nil, 4 },
			{ 0, "fire", nil, 1 },
			{ 1.999, "fire", "INTRA_CLIP", false },
			{ 2, "fire", nil, 1 },
			{ 4, "fire", nil, 1 },
			{ 6, "fire", nil, 1 }, -- last round: full reload 6 → 24
			{ 6, "mag", nil, 0 },
			{ 7, "fire", "RELOADING", false },
			{ 23.999, "can", nil, false },
			{ 24, "mag", nil, 4 },
			{ 24, "fire", nil, 1 },
		})
		local snap = GunState.snapshot(state, 25)
		expect(snap.roundsLoaded).toBe(3)
		expect(snap.intraClipRemainingS).toBeCloseTo(1, 1e-9)
		expect(snap.phase).toBe("IntraClip")
		expect(snap.nextShotS).toBeCloseTo(1, 1e-9)
		expect(snap.magazineSize).toBe(4)
	end)

	it("a short rack loads a partial magazine, then the next shell", function()
		local state = GunState.new(gun(MAGAZINE), ammo(6, 0, 2))
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 2, "fire", nil, 1 },
			{ 4, "fire", nil, 1 },
			{ 6, "fire", nil, 1 },
			{ 24, "mag", nil, 2 }, -- only 2 AP left
			{ 24, "fire", nil, 1 },
			{ 26, "fire", nil, 1 }, -- AP gone: HE loads next
			{ 44, "mag", nil, 2 },
			{ 44, "fire", nil, 3 },
		})
	end)

	it("a manual reload of a partial magazine costs the full reload; plain guns cannot top off", function()
		local state = GunState.new(gun(MAGAZINE), ammo(20))
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 2, "fire", nil, 1 }, -- 2 left
			{ 3, "reload", nil, { true, nil } },
			{ 3, "mag", nil, 0 },
			{ 3, "ammo", 1, 18 },
			{ 20.999, "can", nil, false },
			{ 21, "mag", nil, 4 },
			{ 21, "reload", nil, { false, "FULL" } },
		})
		local single = GunState.new(gun(SINGLE), ammo(5))
		expect(select(2, GunState.reload(single, 0))).toBe("NOT_SUPPORTED")
	end)

	it("swapping with rounds in the magazine unloads them and reloads the new shell × swapFactor", function()
		local state = GunState.new(gun(MAGAZINE, 9), ammo(20, 8)) -- swap = half a magazine reload
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 1, "select", 2, { true, nil } },
			{ 1, "ammo", 1, 19 },
			{ 1, "mag", nil, 0 },
			{ 9.999, "can", nil, false },
			{ 10, "mag", nil, 4 },
			{ 10, "fire", nil, 2 },
		})
	end)

	it("switching during the magazine reload keeps progress and reserves the new shell", function()
		local state = GunState.new(gun(MAGAZINE), ammo(4, 8))
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 2, "fire", nil, 1 },
			{ 4, "fire", nil, 1 },
			{ 6, "fire", nil, 1 }, -- AP gone, magazine reload would pick APCR anyway; switch to HE impossible
			{ 6, "select", 3, { false, "NO_AMMO" } },
		})
		local state2 = GunState.new(gun(MAGAZINE), ammo(8, 8))
		run(state2, {
			{ 0, "fire", nil, 1 },
			{ 2, "fire", nil, 1 },
			{ 4, "fire", nil, 1 },
			{ 6, "fire", nil, 1 }, -- reload 6 → 24 with AP
			{ 10, "select", 2, { true, nil } },
			{ 10, "ammo", 1, 4 },
			{ 24, "mag", nil, 4 },
			{ 24, "fire", nil, 2 },
		})
	end)

	it(
		"AdaptiveMagazine top-off: T_m × (f + (1 − f) × missing ÷ size), cancelled by firing (roster §2.7)",
		function()
			local mags = { kind = "Magazine", size = 4, intraClipS = 2.2, reloadS = 37.3 }
			local mech = { { kind = "AdaptiveMagazine", partialReloadFactor = 0.35 } }
			local state = GunState.new(gun(mags), ammo(40), { mechanics = mech })
			run(state, {
				{ 0, "fire", nil, 1 },
				{ 3, "reload", nil, { true, nil } }, -- one missing: 37.3 × 0.5125 = 19.11625 s
			})
			local snap = GunState.snapshot(state, 3)
			expect(snap.toppingOff).toBe(true)
			expect(snap.reloadRemainingS).toBeCloseTo(19.11625, 1e-9)
			run(state, {
				{ 22.1162, "mag", nil, 3 },
				{ 22.11625, "mag", nil, 4 },
				{ 23, "fire", nil, 1 },
				{ 25.2, "fire", nil, 1 },
				{ 27.4, "fire", nil, 1 }, -- 1 left, 3 missing
			})
			local ok = GunState.mechanicKey(state, 28) -- the mechanic key tops off: 37.3 × 0.8375 = 31.23875 s
			expect(ok).toBe(true)
			expect(GunState.snapshot(state, 28).reloadRemainingS).toBeCloseTo(31.23875, 1e-9)
			run(state, {
				{ 30, "fire", nil, 1 }, -- firing cancels the top-off; the reserved rounds go back
				{ 30, "mag", nil, 0 },
			})
			expect(GunState.snapshot(state, 30).toppingOff).toBe(false)
			expect(GunState.ammoOf(state, 1)).toBe(40 - 5)
			-- the empty magazine reloads automatically (full T_m)
			run(state, { { 67.2999, "can", nil, false }, { 67.3, "mag", nil, 4 } })
		end
	)
end)

describe("GunState: Autoreloader", function()
	it("refill k takes perShellReloadS[k] and firing never resets a running refill", function()
		local state = GunState.new(gun(AUTO), ammo(30))
		run(state, {
			{ 0, "fire", nil, 1 }, -- 2 left: refill of slot 3 (6 s) runs 0 → 6
			{ 1.999, "fire", "INTRA_CLIP", false },
			{ 2, "fire", nil, 1 },
			{ 4, "fire", nil, 1 }, -- empty; the slot-3 refill keeps running
			{ 5.999, "mag", nil, 0 },
			{ 6, "mag", nil, 1 }, -- then slot 2 (7 s) → 13
			{ 12.999, "mag", nil, 1 },
			{ 13, "mag", nil, 2 }, -- then slot 3 (6 s) → 19
			{ 19, "mag", nil, 3 },
		})
		local snap = GunState.snapshot(state, 19)
		expect(snap.refillSlotIndex).toBe(0)
		expect(snap.reloadProgress).toBe(1)
	end)

	it("from empty the first refill is the longest (t1), then t2, t3", function()
		local state = GunState.new(gun(AUTO), ammo(30), { startLoaded = false })
		local snap = GunState.snapshot(state, 0)
		expect(snap.refillSlotIndex).toBe(1)
		expect(snap.reloadRemainingS).toBe(9)
		run(state, {
			{ 8.999, "mag", nil, 0 },
			{ 9, "mag", nil, 1 },
			{ 16, "mag", nil, 2 },
			{ 22, "mag", nil, 3 },
		})
	end)

	it("fires early with a partial magazine and stops refilling when the rack runs dry", function()
		local state = GunState.new(gun(AUTO), ammo(4))
		run(state, {
			{ 0, "fire", nil, 1 },
			{ 2, "fire", nil, 1 },
			{ 4, "fire", nil, 1 }, -- 1 AP left in the rack: slot-3 refill (0 → 6)
			{ 6, "mag", nil, 1 },
			{ 6, "fire", nil, 1 },
			{ 100, "mag", nil, 0 },
			{ 100, "fire", "EMPTY", false },
		})
	end)

	it("swapping with rounds loaded unloads them and restarts the refill (× swapFactor until full)", function()
		local state = GunState.new(gun(AUTO, 4.5), ammo(10, 10)) -- swapFactor 0.5
		run(state, {
			{ 0, "select", 2, { true, nil } },
			{ 0, "mag", nil, 0 },
			{ 0, "ammo", 1, 10 },
			{ 4.5, "mag", nil, 1 }, -- 9 × 0.5
			{ 8, "mag", nil, 2 }, -- 7 × 0.5
			{ 11, "mag", nil, 3 }, -- 6 × 0.5
			{ 11, "fire", nil, 2 },
		})
		expect(state.swapCycle).toBe(false)
		run(state, { { 16.999, "mag", nil, 2 }, { 17, "mag", nil, 3 } }) -- normal timers again (6 s)
	end)
end)

describe("GunState: DualGun", function()
	it("a tap fires one barrel on release; salvo delay; barrels reload independently", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		run(state, {
			{ 0, "mag", nil, 2 },
			{ 0, "trigger", true, nil },
			{ 0.1, "trigger", false, 1 }, -- barrel 1 at 0.1, salvo to 1.6, reload to 12.1
			{ 1.0, "trigger", true, nil },
			{ 1.1, "trigger", false, nil }, -- SALVO_DELAY: no shot
			{ 1.6, "can", nil, true },
			{ 1.6, "trigger", true, nil },
			{ 1.7, "trigger", false, 1 }, -- barrel 2
			{ 12.099, "mag", nil, 0 },
			{ 12.1, "mag", nil, 1 },
			{ 13.7, "mag", nil, 2 },
		})
		expect(state.shot.barrel).toBe(2)
	end)

	it("holding charges a volley that fires automatically at the exact charge end (2 rounds, × dispersion)", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		run(state, {
			{ 0, "trigger", true, nil },
			{ 0.5, "trigger", true, nil },
		})
		expect(GunState.snapshot(state, 0.5).chargeProgress).toBeCloseTo(0.5, 1e-9)
		expect(GunState.snapshot(state, 0.5).phase).toBe("Charging")
		local shot = GunState.setTrigger(state, true, 1.0333) -- next tick after the 1.0 s charge
		expect(shot).never.toBeNil()
		local s = shot :: any
		expect(s.time).toBeCloseTo(1.0, 1e-9)
		expect(s.rounds).toBe(2)
		expect(s.volley).toBe(true)
		expect(s.barrel).toBe(0)
		expect(s.dispersionMul).toBe(1.5)
		expect(GunState.ammoOf(state, 1)).toBe(18)
		run(state, {
			{ 2, "trigger", false, nil }, -- release after the volley: nothing more
			{ 12.999, "mag", nil, 0 },
			{ 13, "mag", nil, 2 }, -- both barrels reload from the volley instant
		})
	end)

	it("releasing a charging volley cancels it: no shot, nothing consumed", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		run(state, {
			{ 0, "trigger", true, nil },
			{ 0.5, "trigger", false, nil },
			{ 0.5, "mag", nil, 2 },
			{ 0.5, "ammo", 1, 20 },
		})
	end)

	it("a volley that completes between calls is delivered by update() with its own time", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		GunState.setTrigger(state, true, 0)
		local snap = GunState.snapshot(state, 5) -- a query passes the charge end: the volley waits
		expect(snap.roundsLoaded).toBe(0)
		local shot = GunState.update(state, 5)
		expect(shot).never.toBeNil()
		expect((shot :: any).time).toBeCloseTo(1, 1e-9)
		expect(GunState.update(state, 5.1)).toBeNil()
	end)

	it("the volley charge starts when the second barrel loads while held", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		run(state, {
			{ 0, "trigger", true, nil },
			{ 0.1, "trigger", false, 1 }, -- barrel 1 reloads 0.1 → 12.1
			{ 11, "trigger", true, nil }, -- held with one barrel: no charge yet
			{ 12.5, "trigger", true, nil },
			{ 13.0999, "update", nil, nil },
			{ 13.1, "update", nil, 2 }, -- 12.1 + 1.0
		})
	end)

	it("holding with only one barrel loaded fires that barrel on release", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		run(state, {
			{ 0, "trigger", true, nil },
			{ 0.1, "trigger", false, 1 },
			{ 2, "trigger", true, nil },
			{ 3, "trigger", false, 1 },
		})
	end)

	it("a destroyed gun or a swap cancels a charging volley; release then does nothing", function()
		local state = GunState.new(gun(DUAL), ammo(20, 20))
		GunState.setTrigger(state, true, 0)
		GunState.setEnabled(state, false, 0.5)
		GunState.setEnabled(state, true, 0.6)
		expect(GunState.setTrigger(state, true, 2)).toBeNil()
		expect(GunState.setTrigger(state, false, 2.1)).toBeNil()
		expect(GunState.roundsLoaded(state)).toBe(2)
		GunState.setTrigger(state, true, 3)
		expect((GunState.selectShell(state, 2, 3.5))).toBe(true)
		expect(GunState.setTrigger(state, true, 5)).toBeNil()
		expect(GunState.setTrigger(state, false, 5.1)).toBeNil()
		expect(GunState.ammoOf(state, 1)).toBe(20) -- both AP rounds went back to the rack
		run(state, { { 14.999, "mag", nil, 0 }, { 15.5, "mag", nil, 2 } }) -- swap = full reload of both barrels
	end)
end)

describe("GunState: ChargedShot", function()
	local CHARGED = { { kind = "ChargedShot", chargeTimeS = 1.5, effect = "Accuracy", dispersionMul = 0.6 } }

	it("an early release fires a normal shot; a full charge carries the bonus (boundary inclusive)", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 3 }), ammo(20), { mechanics = CHARGED })
		expect(GunState.setTrigger(state, true, 0)).toBeNil()
		local shot = GunState.setTrigger(state, false, 1.0) :: any
		expect(shot.charged).toBe(false)
		expect(shot.dispersionMul).toBe(1)
		-- pressed while reloading (loaded at 4.0): the charge starts at 4.0
		expect(GunState.setTrigger(state, true, 3.0)).toBeNil()
		expect(GunState.snapshot(state, 4.75).chargeProgress).toBeCloseTo(0.5, 1e-9)
		local charged = GunState.setTrigger(state, false, 5.5) :: any
		expect(charged.charged).toBe(true)
		expect(charged.dispersionMul).toBe(0.6)
		expect(charged.damageMul).toBe(1)
		GunState.setTrigger(state, true, 9)
		local early = GunState.setTrigger(state, false, 10.4999) :: any
		expect(early.charged).toBe(false)
	end)

	it("the Damage effect multiplies alpha; a swap or a destroyed gun cancels without firing", function()
		local dmg = { { kind = "ChargedShot", chargeTimeS = 1.5, effect = "Damage", damageMul = 1.10 } }
		local state = GunState.new(gun({ kind = "Single", reloadS = 3 }), ammo(20, 5), { mechanics = dmg })
		GunState.setTrigger(state, true, 0)
		local shot = GunState.setTrigger(state, false, 2) :: any
		expect(shot.damageMul).toBe(1.10)
		expect(shot.dispersionMul).toBe(1)
		GunState.setTrigger(state, true, 5)
		GunState.selectShell(state, 2, 5.5)
		expect(GunState.setTrigger(state, false, 7)).toBeNil()
		GunState.setTrigger(state, true, 10)
		GunState.setEnabled(state, false, 10.5)
		expect(GunState.setTrigger(state, false, 12)).toBeNil()
		expect(state.shotsFired).toBe(1)
	end)

	it("resetOnMove holds the charge at 0 while the hull moves (ui-ux H-05 option)", function()
		local state = GunState.new(
			gun({ kind = "Single", reloadS = 3 }),
			ammo(20),
			{ mechanics = CHARGED, resetChargeOnMove = true }
		)
		GunState.setTrigger(state, true, 0)
		GunState.setMoving(state, true, 1)
		GunState.setMoving(state, false, 2)
		expect(GunState.snapshot(state, 3).chargeProgress).toBeCloseTo(1 / 1.5, 1e-9)
		local shot = GunState.setTrigger(state, false, 3.4) :: any
		expect(shot.charged).toBe(false)
	end)

	it("by default hull movement resets the charge (roster §2.7, ui-ux H-05); the option can turn it off", function()
		expect(GunState.DEFAULTS.CHARGED_SHOT_RESET_ON_MOVE).toBe(true)
		local state = GunState.new(gun({ kind = "Single", reloadS = 3 }), ammo(20), { mechanics = CHARGED })
		GunState.setTrigger(state, true, 0)
		GunState.setMoving(state, true, 1.4) -- moving just before the full charge: back to 0
		expect(GunState.snapshot(state, 1.6).chargeProgress).toBe(0)
		GunState.setMoving(state, false, 2) -- resumes from 0 at the stop
		local early = GunState.setTrigger(state, false, 3.4) :: any
		expect(early.charged).toBe(false)
		local free = GunState.new(
			gun({ kind = "Single", reloadS = 3 }),
			ammo(20),
			{ mechanics = CHARGED, resetChargeOnMove = false }
		)
		GunState.setTrigger(free, true, 0)
		GunState.setMoving(free, true, 1)
		local shot = GunState.setTrigger(free, false, 1.5) :: any
		expect(shot.charged).toBe(true)
	end)

	it("a direct fire() drops the charge and fires a normal shot", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 3 }), ammo(20), { mechanics = CHARGED })
		GunState.setTrigger(state, true, 0)
		local shot = GunState.fire(state, 2) :: any
		expect(shot.charged).toBe(false)
		expect(GunState.setTrigger(state, false, 2.5)).toBeNil()
	end)
end)

describe("GunState: ActiveCooling", function()
	local COOLING = {
		{
			kind = "ActiveCooling",
			durationS = 5,
			cooldownS = 45,
			modifiers = {
				{ stat = "reloadTime", op = "mul", value = 0.85 },
				{ stat = "aimTime", op = "mul", value = 0.85 },
			},
		},
	}

	it("started mid-reload, the rest of the window runs at 1 ÷ 0.85 speed, exactly across its end", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 10 }), ammo(20), { mechanics = COOLING })
		GunState.fire(state, 0)
		local ok = GunState.mechanicKey(state, 2)
		expect(ok).toBe(true)
		-- base done by 7 s: 2 + 5 / 0.85; remaining base 8 − 5/0.85 at rate 1 after the window
		local expected = 7 + (8 - 5 / 0.85)
		local snap = GunState.snapshot(state, 2)
		expect(snap.reloadRemainingS).toBeCloseTo(expected - 2, 1e-9)
		expect(snap.reloadMul).toBeCloseTo(0.85, 1e-12)
		expect(GunState.canFire(state, expected - 1e-4)).toBe(false)
		expect(GunState.canFire(state, expected)).toBe(true)
		expect(GunState.currentReloadMul(state)).toBe(1)
	end)

	it("cooldown gates reactivation; runtime modifiers exclude reloadTime", function()
		local state = GunState.new(gun(SINGLE), ammo(20), { mechanics = COOLING })
		expect(GunState.mechanicModifiers(state)).toBeNil()
		expect((GunState.activateCooling(state, 0))).toBe(true)
		local mods = GunState.mechanicModifiers(state) :: any
		expect(#mods).toBe(1)
		expect(mods[1].stat).toBe("aimTime")
		expect(GunState.mechanicActive(state)).toBe(true)
		expect(select(2, GunState.activateCooling(state, 1))).toBe("ACTIVE")
		expect(select(2, GunState.activateCooling(state, 10))).toBe("COOLDOWN")
		expect(GunState.mechanicActive(state)).toBe(false)
		local snap = GunState.mechanicSnapshot(state, 10) :: any
		expect(snap.phase).toBe("Cooldown")
		expect(snap.cooldownRemainingS).toBeCloseTo(40, 1e-9)
		expect((GunState.activateCooling(state, 50))).toBe(true)
		local plain = GunState.new(gun(SINGLE), ammo(20))
		expect(select(2, GunState.mechanicKey(plain, 0))).toBe("NO_MECHANIC")
		expect(GunState.mechanicSnapshot(plain, 0)).toBeNil()
	end)

	it("an injured loader and cooling compose: rate = reloadMul × 0.85", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 10 }), ammo(20), { mechanics = COOLING })
		GunState.fire(state, 0)
		GunState.setReloadMul(state, 1.25, 0)
		GunState.activateCooling(state, 0)
		-- 0..5: rate 1.0625 s per base s → 4.70588 base done; then 5.29412 × 1.25
		local expected = 5 + (10 - 5 / 1.0625) * 1.25
		expect(GunState.snapshot(state, 0).reloadRemainingS).toBeCloseTo(expected, 1e-9)
		expect(GunState.canFire(state, expected - 1e-4)).toBe(false)
		expect(GunState.canFire(state, expected)).toBe(true)
	end)
end)

describe("GunState: invariants and performance", function()
	it("random action sequences keep ammo conserved and clips capped (seeded property test)", function()
		local kinds = {
			SINGLE,
			MAGAZINE,
			AUTO,
			DUAL,
			{ kind = "Magazine", size = 3, intraClipS = 1, reloadS = 9 },
		}
		local rng = RNG.new(20261006)
		for _ = 1, 60 do
			local reload = kinds[rng:int(1, #kinds)]
			local mechanics = if reload.kind == "Magazine" and rng:chance(0.5)
				then { { kind = "AdaptiveMagazine", partialReloadFactor = 0.35 } }
				else nil
			local counts = { rng:int(0, 15), rng:int(0, 6), rng:int(0, 6) }
			local initial = counts[1] + counts[2] + counts[3]
			local state = GunState.new(
				gun(reload, rng:range(0.5, 1.5) * oneReload(reload)),
				ammo(counts[1], counts[2], counts[3]),
				{
					mechanics = mechanics,
					startLoaded = rng:chance(0.8),
				}
			)
			local t = 0
			local clipShots, lastShotCount = 0, 0
			for _ = 1, 200 do
				t += rng:range(0, 3)
				local roll = rng:int(1, 8)
				if roll <= 3 then
					GunState.fire(state, t)
				elseif roll == 4 then
					GunState.selectShell(state, rng:int(1, 3), t)
				elseif roll == 5 then
					GunState.setTrigger(state, rng:chance(0.5), t)
				elseif roll == 6 then
					GunState.reload(state, t)
				elseif roll == 7 then
					GunState.setReloadMul(state, rng:range(0.8, 1.6), t)
				else
					GunState.update(state, t)
				end
				checkInvariants(state, initial)
				-- REG-PRJ-05: no more shots than the gun held + what it reloaded
				expect(state.roundsFired <= initial).toBe(true)
				if state.shotsFired ~= lastShotCount then
					clipShots += state.shotsFired - lastShotCount
					lastShotCount = state.shotsFired
				end
			end
			GunState.kill(state, t + 1)
			checkInvariants(state, initial)
		end
	end)

	it("snapshots stay in range during a long fight", function()
		local state = GunState.new(gun(AUTO), ammo(40, 10))
		local snap = GunState.newSnapshot(state)
		for i = 1, 600 do
			local t = i / 30
			GunState.setTrigger(state, i % 7 == 0, t)
			GunState.snapshot(state, t, snap)
			expect(snap.reloadProgress >= 0 and snap.reloadProgress <= 1).toBe(true)
			expect(snap.chargeProgress >= 0 and snap.chargeProgress <= 1).toBe(true)
			expect(snap.reloadRemainingS >= 0).toBe(true)
			expect(snap.roundsLoaded <= snap.magazineSize).toBe(true)
			expect(snap.ammo[1] + snap.ammo[2]).toBe(snap.totalAmmo)
		end
	end)

	it("the 30 Hz loop allocates nothing (update, trigger, snapshot, fire)", function()
		for _, reload in { SINGLE, MAGAZINE, AUTO, DUAL } do
			local state = GunState.new(gun(reload), ammo(500, 500), { mechanics = nil })
			local snap = GunState.newSnapshot(state)
			local i = 0
			local function tick()
				i += 1
				local t = i / 30
				GunState.setTrigger(state, i % 11 < 5, t)
				GunState.update(state, t + 0.01)
				GunState.fire(state, t + 0.02)
				GunState.snapshot(state, t + 0.02, snap)
				if i % 97 == 0 then
					GunState.selectShell(state, 1 + (i % 2), t + 0.02)
				end
			end
			for _ = 1, 300 do
				tick() -- warm up
			end
			-- Luau only exposes collectgarbage("count"): without allocation the heap size is exactly constant, so
			-- nearly every short window must show zero growth (an allocating loop almost never nets exactly 0).
			local zero, windows = 0, 20
			for _ = 1, windows do
				local before = collectgarbage("count")
				for _ = 1, 150 do
					tick()
				end
				if collectgarbage("count") == before then
					zero += 1
				end
			end
			if zero < windows - 2 then
				error(`{reload.kind}: only {zero}/{windows} allocation-free windows`)
			end
		end
	end)
end)

describe("GunState: blocking, ammo-rack sync and runtime inputs", function()
	local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
	local StatsCalculator = require("@game/ReplicatedStorage/Shared/Vehicle/StatsCalculator")
	local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")

	it("an overturned vehicle cannot fire; the reload keeps running; righted it fires at once", function()
		local state = GunState.new(gun(SINGLE), ammo(10))
		run(state, { { 0, "fire", nil, 1 } })
		GunState.setOverturned(state, true, 0.5)
		run(state, { { 3, "fire", "OVERTURNED", false }, { 3, "can", "OVERTURNED", false } })
		local snap = GunState.snapshot(state, 3)
		expect(snap.phase).toBe("Disabled")
		expect(snap.overturned).toBe(true)
		expect(snap.roundsLoaded).toBe(1)
		expect(snap.nextShotS).toBe(math.huge)
		GunState.setOverturned(state, false, 4)
		run(state, { { 4, "fire", nil, 1 } })
		expect(GunState.snapshot(state, 4).overturned).toBe(false)
	end)

	it("overturning cancels a charging volley; the gun destroyed reason takes precedence", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		GunState.setTrigger(state, true, 0)
		GunState.setOverturned(state, true, 0.5)
		expect(GunState.update(state, 2)).toBeNil()
		expect(GunState.setTrigger(state, false, 2.1)).toBeNil()
		expect(GunState.ammoOf(state, 1)).toBe(20)
		GunState.setEnabled(state, false, 3)
		local _, reason = GunState.canFire(state, 3)
		expect(reason).toBe("GUN_DESTROYED")
		GunState.kill(state, 4)
		_, reason = GunState.canFire(state, 4)
		expect(reason).toBe("DEAD")
	end)

	it("storedAmmo excludes rounds in the gun and keeps DamageModel's detonation count in sync", function()
		local combat = DamageModel.new({
			hp = 100,
			massKg = 10000,
			modules = { AmmoRack = { maxHp = 50, repairS = 10 } },
			crew = {},
			crewLevels = {},
			fireChance = 0,
			fireDurationS = 8,
			spallFactor = 1,
			crewInjuryChanceMul = 1,
			stunDurationMul = 1,
			ramDamageDealtMul = 1,
			ramDamageTakenMul = 1,
			fallDamageMul = 1,
		})
		local single = GunState.new(gun(SINGLE), ammo(3))
		expect(GunState.storedAmmo(single)).toBe(2) -- one round chambered
		expect(GunState.syncAmmoStored(single, combat)).toBe(2)
		expect(combat.ammoStored).toBe(2)
		GunState.fire(single, 0) -- 2 left: one being loaded (still outside the gun), one in the rack
		expect(GunState.syncAmmoStored(single, combat)).toBe(2)
		GunState.fire(single, 2)
		GunState.update(single, 4) -- last round chambered, rack empty
		expect(GunState.syncAmmoStored(single, combat)).toBe(0)
		expect(combat.ammoStored).toBe(0) -- a destroyed rack can no longer detonate
		local mag = GunState.new(gun(MAGAZINE), ammo(10))
		expect(GunState.storedAmmo(mag)).toBe(6) -- 4 in the magazine
		local dual = GunState.new(gun(DUAL), ammo(5))
		expect(GunState.storedAmmo(dual)).toBe(3)
	end)

	it("applyRuntime feeds the StatsCalculator runtime into the reload and the trigger", function()
		local state = GunState.new(gun({ kind = "Single", reloadS = 10 }), ammo(10))
		GunState.fire(state, 0)
		GunState.applyRuntime(state, { reloadMul = 1.25, canFire = true }, 4) -- 4 base s done, 6 left at ×1.25
		expect(GunState.snapshot(state, 4).reloadRemainingS).toBeCloseTo(7.5, 1e-9)
		GunState.applyRuntime(state, { reloadMul = 1, canFire = false }, 6) -- 1.6 base s done, 4.4 left
		run(state, { { 10.4, "can", "GUN_DESTROYED", false } })
		expect(GunState.roundsLoaded(state)).toBe(1)
	end)

	it("a magazine reload completing exactly at the death time fills the magazine; nothing fires", function()
		local state = GunState.new(gun(MAGAZINE), ammo(10))
		for i = 0, 3 do
			GunState.fire(state, i * 2)
		end
		-- empty at 6 s → full reload until 24 s
		GunState.kill(state, 24)
		local snap = GunState.snapshot(state, 30)
		expect(snap.roundsLoaded).toBe(4)
		expect(snap.phase).toBe("Dead")
		run(state, { { 30, "fire", "DEAD", false } })
		-- a death one instant earlier leaves the magazine empty and the reload frozen
		local early = GunState.new(gun(MAGAZINE), ammo(10))
		for i = 0, 3 do
			GunState.fire(early, i * 2)
		end
		GunState.kill(early, 23.999)
		expect(GunState.snapshot(early, 30).roundsLoaded).toBe(0)
	end)

	it("an autoreloader refill completing at the death time counts; the next refill never starts", function()
		local state = GunState.new(gun(AUTO), ammo(10))
		GunState.fire(state, 0) -- refill of slot 3 starts: 6 s
		GunState.kill(state, 6)
		expect(GunState.roundsLoaded(state)).toBe(3)
		local snap = GunState.snapshot(state, 20)
		expect(snap.refillSlotIndex).toBe(0)
		expect(snap.phase).toBe("Dead")
	end)

	it("death while a volley charges: no volley, ever", function()
		local state = GunState.new(gun(DUAL), ammo(20))
		GunState.setTrigger(state, true, 0)
		GunState.kill(state, 0.9)
		expect(GunState.update(state, 5)).toBeNil()
		expect(GunState.ammoOf(state, 1)).toBe(20)
	end)

	it("table: out-of-ammo transitions for every kind", function()
		local rows = {
			{
				"Single",
				SINGLE,
				ammo(1),
				{ { 0, "fire", nil, 1 }, { 10, "can", "EMPTY", false }, { 10, "mag", nil, 0 } },
			},
			{
				"Magazine (2 rounds < size)",
				MAGAZINE,
				ammo(2),
				{ { 0, "mag", nil, 2 }, { 0, "fire", nil, 1 }, { 2, "fire", nil, 1 }, { 100, "can", "EMPTY", false } },
			},
			{
				"Autoreloader (3 rounds = size)",
				AUTO,
				ammo(3),
				{
					{ 0, "fire", nil, 1 },
					{ 2, "fire", nil, 1 },
					{ 4, "fire", nil, 1 },
					{ 4, "can", "EMPTY", false },
					{ 50, "mag", nil, 0 },
				},
			},
			{
				"DualGun (1 round)",
				DUAL,
				ammo(1),
				{ { 0, "mag", nil, 1 }, { 0, "fire", nil, 1 }, { 30, "can", "EMPTY", false } },
			},
			{
				"Single falls through to the next shell",
				SINGLE,
				ammo(1, 1),
				{ { 0, "fire", nil, 1 }, { 2, "fire", nil, 2 }, { 4, "can", "EMPTY", false } },
			},
		}
		for _, row in rows do
			local state = GunState.new(gun(row[2]), row[3])
			local ok, err = pcall(run, state, row[4])
			if not ok then
				error(`{row[1]}: {tostring(err)}`)
			end
			expect(GunState.totalAmmo(state)).toBe(0)
		end
	end)

	it("drives a real VehicleStats gun: crew-scaled reload and an Intuition-shortened swap", function()
		local registry = ContentRegistry.get()
		local def = registry:getVehicle("iu_bulmal") :: any
		local stats = (StatsCalculator.compute(def, def.top, nil, registry) :: any).value
		local load = {
			{ shell = "iu_76mm_ap", count = 30 },
			{ shell = "iu_76mm_apcr", count = 10 },
			{ shell = "iu_76mm_he", count = 10 },
		}
		local state = GunState.new(stats.gun, load)
		local shot = GunState.fire(state, 0) :: any
		expect(shot.shell.damage).toBe(75)
		expect((GunState.canFire(state, 2.999))).toBe(false)
		expect((GunState.canFire(state, 3.0))).toBe(true)
		-- swap away from the loaded AP: full reload × shellSwapS / reloadS (= 1 without skills)
		GunState.selectShell(state, 2, 3)
		expect(GunState.snapshot(state, 3).reloadRemainingS).toBeCloseTo(3.0, 1e-9)
		local fast = table.clone(stats.gun)
		fast.shellSwapS = 1.8 -- Intuition on both loaders (× 0.6)
		local quick = GunState.new(fast, load)
		GunState.selectShell(quick, 3, 0)
		expect(GunState.snapshot(quick, 0).reloadRemainingS).toBeCloseTo(1.8, 1e-9)
		expect(GunState.snapshot(quick, 0).loadedSlot).toBe(0)
		expect(GunState.ammoOf(quick, 1)).toBe(30) -- the unloaded AP went back to the rack
	end)
end)
