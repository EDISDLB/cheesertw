-- covers: 00-DECISIONS §5; research 02-R2/R11; REG-SPT-01, -02, -03, -04, -05, -06, -07, -09, -10 (15 m rules),
-- REG-SPT-08 (filter API), REG-MINI-01 (wreck ordering), REG-MINI-03 (VR readout within 1 tick); battle-rules §7.1
-- (Attribution.noteSeen on every successful check, linger = LEDGER.ASSIST_SPOT_WINDOW_S)
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Attribution = require("@game/ReplicatedStorage/Shared/Battle/Ledger/Attribution")
local SpottingSystem = require("@game/ReplicatedStorage/Shared/Spotting/SpottingSystem")
local VisibilityModel = require("@game/ReplicatedStorage/Shared/Spotting/VisibilityModel")
local F = require("./SpottingFixtures")

local TICK = 1 / 30

-- Observer 1 (team 1) at the origin facing −Z; target 2 (team 2) `d` metres down −Z facing the observer.
local function duel(d: number, observerOpts: any?, targetOpts: any?)
	local o = F.vehicle(1, 1, 0, 0, observerOpts)
	local tOpts = targetOpts or {}
	if tOpts.headingDeg == nil then
		tOpts.headingDeg = 180
	end
	local t = F.vehicle(2, 2, 0, -d, tOpts)
	return o, t
end

local function kinds(events)
	local out = {}
	for _, e in events do
		table.insert(out, `{e.kind}:{e.team}:{e.target}`)
	end
	return out
end

describe("SpottingSystem", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	describe("basics", function()
		it("two vehicles in the open spot each other on the first update (spawn check)", function()
			local world = F.flatWorld()
			local a, b = duel(300)
			local sys = SpottingSystem.new()
			local events = F.filter(sys:update(TICK, { a, b }, world), "Spotted")
			expect(#events).toBe(2)
			expect(events[1]).toEqual({ kind = "Spotted", t = TICK, team = 1, target = 2, spotter = 1, first = true })
			expect(events[2]).toEqual({ kind = "Spotted", t = TICK, team = 2, target = 1, spotter = 2, first = true })
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			expect(sys:isVisibleTo(2, 1)).toBe(true)
			expect(sys:visibleSet(1)).toEqual({ 2 })
			expect(sys:isVisibleTo(1, 1)).toBe(true) -- own / allies always
			expect(sys:isVisibleTo(1, 99)).toBe(false) -- unknown id
			expect(sys:isVisibleTo(7, 2)).toBe(false) -- unknown team
			expect(sys:visibleSet(7)).toEqual({})
			expect(sys:isExposed(1)).toBe(true)
			expect(sys:stats().rays).toBe(2) -- first ray of each direction succeeds
		end)

		it("hand-computed edge: VR 400, camo 0.12 → spot distance 358 m", function()
			local world = F.flatWorld()
			for _, case in { { 357.5, true }, { 358.5, false } } do
				local a, b = duel(case[1], nil, { viewRangeM = 0 })
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				expect(sys:isVisibleTo(1, 2)).toBe(case[2])
			end
		end)

		it("pairs beyond 445 m or beyond the capped formula cost no rays", function()
			local world = F.counting(F.flatWorld())
			local a, b = duel(450, { viewRangeM = 2000 }, { viewRangeM = 2000, camo = F.camo({ stationary = 0 }) })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 90)
			expect(world.total).toBe(0)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			expect(sys:stats().cheapRejects >= 0).toBe(true)
			-- formula reject: VR 300 vs camo 0.5 → 175 m < 200 m
			local c, d = duel(200, { viewRangeM = 300 }, { viewRangeM = 0, camo = F.camo({ stationary = 0.5 }) })
			local sys2 = SpottingSystem.new()
			local w2 = F.counting(F.flatWorld())
			F.run(sys2, { c, d }, w2, 1, 90)
			expect(w2.total).toBe(0)
		end)
	end)

	describe("proximity (REG-SPT-03)", function()
		local wall = { x = 0, y = 5, z = -25, sx = 60, sy = 10, sz = 1 }

		it("49 m through a wall is spotted, 51 m is not", function()
			local world = F.flatWorld({ boxes = { wall } })
			local a, b = duel(49)
			local sys = SpottingSystem.new()
			sys:update(TICK, { a, b }, world)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			expect(sys:isVisibleTo(2, 1)).toBe(true)
			expect(sys:stats().rays).toBe(0)
			local c, d = duel(51)
			local sys2 = SpottingSystem.new()
			sys2:update(TICK, { c, d }, world)
			expect(sys2:isVisibleTo(1, 2)).toBe(false)
			expect(sys2:stats().rays).toBe(24) -- 2 ports × 6 checkpoints, both directions, all blocked
		end)

		it("10,000 random pairs behind a wall: never spotted beyond 50 m, always within", function()
			local world = F.flatWorld({ boxes = { { x = 0, y = 15, z = 0, sx = 1200, sy = 30, sz = 1 } } })
			local rng = RNG.new(303)
			local seen, unseen = 0, 0
			for i = 1, 10000 do
				local near = i % 2 == 0
				local d = if near then rng:range(10, 50) else rng:range(50.01, 445)
				local x = rng:range(-150, 150)
				local a = F.vehicle(1, 1, x, d / 2, {
					viewRangeM = 2000,
					headingDeg = rng:range(-180, 180),
					turretYawRad = rng:range(-math.pi, math.pi),
				})
				local b = F.vehicle(2, 2, x, -d / 2, {
					viewRangeM = 0,
					camo = F.camo({ stationary = 0 }),
					headingDeg = rng:range(-180, 180),
				})
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				local visible = sys:isVisibleTo(1, 2)
				if visible then
					seen += 1
				else
					unseen += 1
				end
				if visible ~= near then
					error(`pair {i} at {d} m: visible = {visible}`)
				end
			end
			expect(seen).toBe(5000)
			expect(unseen).toBe(5000)
		end)
	end)

	describe("clear LOS (REG-SPT-02)", function()
		it("10,000 random open-field pairs: spotted iff within the spot distance", function()
			local world = F.flatWorld()
			local rng = RNG.new(202)
			for i = 1, 10000 do
				local vr = rng:range(150, 700)
				local camoValue = rng:range(0, 0.6)
				local spotDist = VisibilityModel.spotDistance(vr, camoValue)
				local inside = i % 2 == 1
				local d = if inside then rng:range(50.5, spotDist) else rng:range(spotDist + 0.01, 500)
				local bearing = rng:range(-math.pi, math.pi)
				local a = F.vehicle(1, 1, 0, 0, {
					viewRangeM = vr,
					headingDeg = rng:range(-180, 180),
					turretYawRad = rng:range(-math.pi, math.pi),
				})
				local b = F.vehicle(2, 2, d * math.sin(bearing), d * math.cos(bearing), {
					viewRangeM = 0,
					camo = F.camo({ stationary = camoValue }),
					headingDeg = rng:range(-180, 180),
				})
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				if sys:isVisibleTo(1, 2) ~= inside then
					error(`pair {i}: VR {vr} camo {camoValue} d {d} spotDist {spotDist}`)
				end
			end
		end)
	end)

	describe("scheduling (REG-SPT-01, 02-R2)", function()
		it("a target crossing into spot range is spotted within CHECK_INTERVAL_MAX_S + 1 tick", function()
			local rng = RNG.new(101)
			local world = F.flatWorld()
			for _, edge in { 50, 150, 300, 445 } do
				for trial = 1, 12 do
					-- Observer VR 1000 (uncapped) and target camo chosen so the spot distance is exactly `edge`.
					local camoValue = if edge >= 445 then 0 elseif edge <= 50 then 0.9 else (1000 - edge) / 950
					local observerVr = if edge <= 50 then 0 else 1000
					local bearing = rng:range(-math.pi, math.pi)
					local speed = rng:range(5, 15)
					local startD = edge + 25 + rng:range(0, 10)
					local a = F.vehicle(1, 1, 0, 0, { viewRangeM = observerVr })
					local b = F.vehicle(2, 2, startD * math.sin(bearing), startD * math.cos(bearing), {
						viewRangeM = 0,
						moving = true,
						camo = F.camo({ stationary = camoValue, moving = camoValue }),
					})
					local sys = SpottingSystem.new()
					local crossT, spotT = nil, nil
					local d = startD
					for tick = 1, 30 * 12 do
						local now = tick * TICK
						d = startD - speed * (now - TICK)
						F.place(b, d * math.sin(bearing), d * math.cos(bearing))
						if crossT == nil and d <= edge then
							crossT = now
						end
						for _, e in sys:update(now, { a, b }, world) do
							if e.kind == "Spotted" and e.team == 1 then
								spotT = now
							end
						end
						if spotT ~= nil then
							break
						end
					end
					expect(crossT ~= nil and spotT ~= nil).toBe(true)
					local delay = spotT - crossT
					if delay < -1e-9 or delay > Config.Spotting.CHECK_INTERVAL_MAX_S + TICK + 1e-6 then
						error(`edge {edge} trial {trial}: delay {delay}`)
					end
					if edge <= 50 then
						expect(delay).toBeCloseTo(0, 1e-9) -- proximity is evaluated every update
					end
				end
			end
		end)

		it(
			"schedules distance-based intervals with pair jitter (200 m → 0.708 s, 350 m → clamped 1.0 s)",
			function()
				for _, case in { { 200, 0.7083 }, { 350, 1.0 } } do
					local world =
						F.counting(F.flatWorld({ boxes = { { x = 0, y = 10, z = -100, sx = 60, sy = 20, sz = 1 } } }))
					local a, b = duel(
						case[1],
						{ viewRangeM = 2000 },
						{ viewRangeM = 0, camo = F.camo({ stationary = 0 }) }
					)
					local sys = SpottingSystem.new()
					local lastCheck, gaps, checks = nil, {}, 0
					F.run(sys, { a, b }, world, 1, 30 * 20, function()
						local info = sys:pairInfo(1, 2)
						if info.lastCheck ~= lastCheck then
							if lastCheck ~= nil then
								table.insert(gaps, info.lastCheck - lastCheck)
							end
							lastCheck = info.lastCheck
							checks += 1
							-- scheduled interval within [(1 − J) i, i]
							local scheduled = info.nextCheck - info.lastCheck
							local J = Config.Spotting.CHECK_JITTER_FRACTION
							expect(scheduled <= case[2] + 1e-3).toBe(true)
							expect(scheduled >= case[2] * (1 - J) - 1e-3).toBe(true)
						end
					end)
					expect(sys:isVisibleTo(1, 2)).toBe(false)
					-- every check costs 12 blocked rays; the reverse direction is a cheap reject (VR 0)
					expect(world.total).toBe(12 * checks)
					for _, g in gaps do
						-- quantised to ticks: at most one tick late
						expect(g <= case[2] + TICK + 1e-6).toBe(true)
					end
					expect(#gaps >= math.floor(20 / case[2]) - 1).toBe(true)
				end
			end
		)

		it("forced checks complete in the same tick: shot, stop, spawn", function()
			local world = F.flatWorld()
			-- TD-like target: 0.30 camo → 295 m spot distance from VR 400; after a shot 0.30 × 0.15 → 384 m.
			local a, b = duel(300, nil, { viewRangeM = 0, camo = F.camo({ stationary = 0.30, afterShotMul = 0.15 }) })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 45)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			local tick = 46
			while sys:pairInfo(1, 2).nextCheck <= tick * TICK + 0.1 do
				sys:update(tick * TICK, { a, b }, world)
				tick += 1
			end
			-- not due now: only the forced shot check can reveal it this tick
			local now = tick * TICK
			b.lastShotAt = now
			local events = F.filter(sys:update(now, { a, b }, world), "Spotted")
			expect(#events).toBe(1)
			expect(events[1].t).toBe(now)
			expect(sys:pairInfo(1, 2).lastCheck).toBe(now)
			expect(sys:pairInfo(1, 2).forced).toBe(false)

			-- stop: both roles are re-checked the tick the hull stops
			a.moving = true
			F.run(sys, { a, b }, world, tick + 1, tick + 10)
			a.moving = false
			local stopNow = (tick + 11) * TICK
			sys:update(stopNow, { a, b }, world)
			expect(sys:pairInfo(1, 2).lastCheck).toBe(stopNow)
			expect(sys:pairInfo(2, 1).lastCheck).toBe(stopNow)

			-- spawn: a newcomer is checked both ways on its first update
			local c = F.vehicle(3, 1, 30, 0)
			local spawnNow = (tick + 12) * TICK
			sys:update(spawnNow, { a, b, c }, world)
			expect(sys:pairInfo(3, 2).lastCheck).toBe(spawnNow)
			expect(sys:pairInfo(2, 3).lastCheck).toBe(spawnNow)
		end)

		it("forceCheck re-checks every pair of the vehicle at the next update", function()
			local world = F.flatWorld()
			local a, b = duel(300)
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 5)
			sys:forceCheck(2)
			sys:update(6 * TICK, { a, b }, world)
			expect(sys:pairInfo(1, 2).lastCheck).toBe(6 * TICK)
			expect(sys:pairInfo(2, 1).lastCheck).toBe(6 * TICK)
		end)
	end)

	describe("ray budget and deferral", function()
		-- 15 v 15 face to face across a wall: every check casts 12 blocked rays.
		local function crowd()
			local vehicles = {}
			for i = 1, 15 do
				table.insert(vehicles, F.vehicle(i, 1, -70 + 10 * (i - 1), 0, { viewRangeM = 2000 }))
				table.insert(
					vehicles,
					F.vehicle(100 + i, 2, -70 + 10 * (i - 1), -100, {
						viewRangeM = 2000,
						headingDeg = 180,
						camo = F.camo({ stationary = 0 }),
					})
				)
			end
			local world = F.counting(F.flatWorld({ boxes = { { x = 0, y = 10, z = -50, sx = 400, sy = 20, sz = 1 } } }))
			return vehicles, world
		end

		it("never exceeds MAX_RAYS_PER_TICK, serves forced pairs nearest first, and starves no pair", function()
			expect(Config.applyOverrides({ Spotting = { MAX_RAYS_PER_TICK = 48 } })).toBeOk()
			local vehicles, world = crowd()
			for _, v in vehicles do
				v.camo = F.camo({ stationary = 0 })
			end
			local sys = SpottingSystem.new()
			-- first tick: 450 forced pairs, budget for 4 checks (48 / 12) → the nearest (100 m apart) go first
			world:reset()
			sys:update(TICK, vehicles, world)
			expect(world.calls).toBe(48)
			expect(sys:stats().pairsChecked).toBe(4)
			expect(sys:stats().pairsDeferred).toBe(446)
			local checkedNearest = 0
			for _, v in vehicles do
				for _, other in vehicles do
					local info = sys:pairInfo(v.id, other.id)
					if info ~= nil and info.lastCheck ~= nil then
						expect(info.distanceM).toBeCloseTo(100, 1e-6)
						checkedNearest += 1
					end
				end
			end
			expect(checkedNearest).toBe(4)
			world:reset()
			-- sustained overload for 15 s: budget always respected, every pair checked repeatedly (FIFO for deferred)
			local maxGap = 0
			local last = {}
			F.run(sys, vehicles, world, 2, 30 * 15, function(_, now)
				expect(world.calls <= 48).toBe(true)
				world:reset()
				for _, v in vehicles do
					for _, other in vehicles do
						local info = sys:pairInfo(v.id, other.id)
						if info ~= nil then
							local key = v.id * 1000 + other.id
							local prev = last[key] or 0
							if info.lastCheck ~= nil and info.lastCheck ~= prev then
								last[key] = info.lastCheck
							end
							maxGap = math.max(maxGap, now - (last[key] or 0))
						end
					end
				end
			end)
			expect(sys:stats().peakRays).toBe(48)
			-- 450 pairs × 12 rays / 48 per tick = 112.5 ticks per full round (3.75 s) plus scheduling slack
			expect(maxGap < 6).toBe(true)
		end)

		it("the default budget (400) holds in the same crowd", function()
			local vehicles, world = crowd()
			local sys = SpottingSystem.new()
			F.run(sys, vehicles, world, 1, 60, function()
				expect(world.calls <= 400).toBe(true)
				expect(sys:stats().rays).toBe(world.calls)
				world:reset()
			end)
		end)
	end)

	describe("camouflage, caps and foliage", function()
		it("body camo + dense bush is capped at 0.90: 85 m spotted, 95 m not (VR 445)", function()
			for _, case in { { 85, true }, { 95, false } } do
				local d = case[1]
				local world = F.flatWorld({ foliage = { { x = 0, y = 1, z = -d, r = 5, c = 0.5 } } })
				local a, b = duel(d, { viewRangeM = 445 }, { viewRangeM = 0, camo = F.camo({ stationary = 0.43 }) })
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				expect(sys:isVisibleTo(1, 2)).toBe(case[2])
			end
			-- with WoT's cap (1.0) the same 85 m target hides (0.93 → 77.65 m)
			expect(Config.applyOverrides({ Spotting = { CAMO_TOTAL_CAP = 1 } })).toBeOk()
			local world = F.flatWorld({ foliage = { { x = 0, y = 1, z = -85, r = 5, c = 0.5 } } })
			local a, b = duel(85, { viewRangeM = 445 }, { viewRangeM = 0, camo = F.camo({ stationary = 0.43 }) })
			local sys = SpottingSystem.new()
			sys:update(TICK, { a, b }, world)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
		end)

		it("two dense bushes stack to 0.80, not 1.0: spot distance 129 m", function()
			for _, case in { { 125, true }, { 135, false } } do
				local d = case[1]
				local world = F.flatWorld({
					foliage = {
						{ x = 0, y = 1, z = -d, r = 5, c = 0.5 },
						{ x = 0, y = 1.5, z = -(d - 40), r = 5, c = 0.5 },
					},
				})
				local a, b = duel(d, { viewRangeM = 445 }, { viewRangeM = 0, camo = F.camo({ stationary = 0 }) })
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				expect(sys:isVisibleTo(1, 2)).toBe(case[2])
			end
		end)

		it("best ray wins: a bush hiding only the hull checkpoints leaves the turret rays deciding", function()
			-- hull-height sphere 10 m in front of the target: covers the 4 hull-face rays, not turret roof/mantlet
			local hullBush = { x = 0, y = -2, z = -290, r = 4.2, c = 0.5 }
			local world = F.counting(F.flatWorld({ foliage = { hullBush } }))
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			sys:update(TICK, { a, b }, world)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			-- the turret-roof ray (first checkpoint) is clear: one ray
			expect(world.total).toBe(1)
			-- hide the turret too: nothing gets through (0.12 + 0.5 → 183 m)
			local world2 = F.flatWorld({ foliage = { hullBush, { x = 0, y = 2.7, z = -290, r = 3, c = 0.5 } } })
			local sys2 = SpottingSystem.new()
			sys2:update(TICK, { a, b }, world2)
			expect(sys2:isVisibleTo(1, 2)).toBe(false)
			-- the bush really hides the hull rays: a target with hull checkpoints only stays hidden
			local hullOnly = table.clone(F.PIVOTS)
			hullOnly.camoPoints =
				{ F.PIVOTS.camoPoints[3], F.PIVOTS.camoPoints[4], F.PIVOTS.camoPoints[5], F.PIVOTS.camoPoints[6] }
			local c = F.vehicle(2, 2, 0, -300, { viewRangeM = 0, headingDeg = 180, pivots = hullOnly })
			local sys3 = SpottingSystem.new()
			sys3:update(TICK, { a, c }, F.flatWorld({ foliage = { hullBush } }))
			expect(sys3:isVisibleTo(1, 2)).toBe(false)
		end)

		it("observer side 15 m rule: a bush 10 m in front is see-through, at 20 m it conceals (REG-SPT-10)", function()
			for _, case in { { 10, true }, { 20, false } } do
				local world =
					F.counting(F.flatWorld({ foliage = { { x = 0, y = 2.5, z = -case[1], r = 3, c = 0.5 } } }))
				local a, b = duel(300, nil, { viewRangeM = 0 })
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				expect(sys:isVisibleTo(1, 2)).toBe(case[2])
				if case[2] then
					-- one sightLine finds 0.5 foliage, one sub-segment query proves it lies within 15 m
					expect(world.total).toBe(2)
				end
			end
		end)

		it("the analytic foliage probe gives the same answers without extra rays", function()
			for _, case in { { 10, true }, { 20, false } } do
				local world =
					F.counting(F.flatWorld({ foliage = { { x = 0, y = 2.5, z = -case[1], r = 3, c = 0.5 } } }), true)
				local a, b = duel(300, nil, { viewRangeM = 0 })
				local sys = SpottingSystem.new()
				sys:update(TICK, { a, b }, world)
				expect(sys:isVisibleTo(1, 2)).toBe(case[2])
				expect(sys:stats().foliageProbes > 0).toBe(true)
				expect(sys:stats().rays).toBe(world.total)
				if case[2] then
					expect(world.total).toBe(1)
				end
			end
		end)

		it("shooter side 15 m rule: firing 10 m behind a bush reveals for 3 s; 22 m behind keeps cover", function()
			for _, case in { { 10, true }, { 22, false } } do
				local world = F.flatWorld({ foliage = { { x = 0, y = 2, z = -(300 - case[1]), r = 3, c = 0.5 } } })
				-- afterShotMul 1 isolates the foliage rule from the after-shot camo multiplier
				local a, b = duel(300, nil, { viewRangeM = 0, camo = F.camo({ stationary = 0.12, afterShotMul = 1 }) })
				local sys = SpottingSystem.new()
				F.run(sys, { a, b }, world, 1, 30)
				expect(sys:isVisibleTo(1, 2)).toBe(false)
				local shotAt = 31 * TICK
				b.lastShotAt = shotAt
				sys:update(shotAt, { a, b }, world)
				expect(sys:isVisibleTo(1, 2)).toBe(case[2])
				if case[2] then
					-- seen while the 3 s penalty lasts, never after; lost 10 s after the last success
					local lostAt = nil
					F.run(sys, { a, b }, world, 32, 31 + 30 * 16, function(_, now, events)
						for _, e in events do
							if e.kind == "Lost" and e.team == 1 then
								lostAt = now
							end
						end
					end)
					local lastSeen = sys:lastSeenBy(1, 2)
					expect(lastSeen < shotAt + 3).toBe(true)
					expect(lastSeen >= shotAt + 3 - Config.Spotting.CHECK_INTERVAL_MAX_S - TICK - 1e-6).toBe(true)
					expect(lostAt).toBeCloseTo(lastSeen + 10, TICK + 1e-6)
				end
			end
		end)

		it("smoke blocks LOS and costs the observer inside 30 % VR", function()
			local world = F.flatWorld({ smoke = { { x = 0, y = 2, z = -150, r = 10 } } })
			local a, b = duel(300, { inSmoke = true }, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			sys:update(TICK, { a, b }, world)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			expect(sys:viewRangeOf(1)).toBeCloseTo(280, 1e-9)
		end)
	end)

	describe("stationary arming (REG-SPT-04, REG-SPT-09, REG-MINI-03)", function()
		it("net and mast arm after 3 s stationary and drop the tick the hull moves", function()
			local world = F.flatWorld()
			local mast = { stat = "viewRange", op = "mul", value = 1.25, condition = "StationaryArmed" }
			local a = F.vehicle(1, 1, 0, 0, {
				moving = true,
				camo = F.camo({ stationary = 0.12, moving = 0.07, net = 0.10 }),
				conditionalModifiers = { mast },
			})
			local b = F.vehicle(2, 2, 0, -600, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 10)
			expect(sys:bodyCamoOf(1)).toBeCloseTo(0.07, 1e-12)
			a.moving = false -- stops at tick 11
			F.run(sys, { a, b }, world, 11, 11 + 89)
			expect(sys:bodyCamoOf(1)).toBeCloseTo(0.12, 1e-12) -- 2.967 s
			expect(sys:viewRangeOf(1)).toBe(400)
			sys:update((11 + 90) * TICK, { a, b }, world) -- 3.0 s
			expect(sys:bodyCamoOf(1)).toBeCloseTo(0.22, 1e-12)
			expect(sys:viewRangeOf(1)).toBeCloseTo(500, 1e-9)
			a.moving = true
			sys:update((11 + 91) * TICK, { a, b }, world)
			expect(sys:bodyCamoOf(1)).toBeCloseTo(0.07, 1e-12)
			expect(sys:viewRangeOf(1)).toBe(400)
		end)

		it("after-shot camo applies for 3 s (REG-SPT-04)", function()
			local world = F.flatWorld()
			local a, b = duel(600, nil, { camo = F.camo({ stationary = 0.2, afterShotMul = 0.25 }) })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 30)
			b.lastShotAt = 31 * TICK
			sys:update(31 * TICK, { a, b }, world)
			expect(sys:bodyCamoOf(2)).toBeCloseTo(0.05, 1e-12)
			F.run(sys, { a, b }, world, 32, 31 + 89)
			expect(sys:bodyCamoOf(2)).toBeCloseTo(0.05, 1e-12)
			sys:update((31 + 90) * TICK, { a, b }, world)
			expect(sys:bodyCamoOf(2)).toBeCloseTo(0.2, 1e-12)
		end)
	end)

	describe("linger and last-known markers", function()
		it("stays visible 10 s after the last success, then Lost once with a 30 s marker", function()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 30)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			world:addBox({
				id = "wall",
				destructible = true,
				cframe = CFrame.new(0, 30, -450),
				size = Vector3.new(180, 60, 3),
			})
			local lastSeen = sys:lastSeenBy(1, 2)
			local losts, spotted = {}, 0
			local lostTick = nil
			F.run(sys, { a, b }, world, 31, 30 * 15, function(tick, now, events)
				for _, e in events do
					if e.kind == "Lost" then
						table.insert(losts, { t = now, team = e.team, target = e.target, position = e.position })
						lostTick = tick
					elseif e.kind == "Spotted" then
						spotted += 1
					end
				end
				if lostTick == nil then
					expect(sys:isVisibleTo(1, 2)).toBe(true)
				else
					expect(sys:isVisibleTo(1, 2)).toBe(false)
				end
			end)
			expect(spotted).toBe(0)
			expect(#losts).toBe(1)
			expect(losts[1].team).toBe(1)
			expect(losts[1].target).toBe(2)
			expect(losts[1].t - lastSeen > 10).toBe(true)
			expect(losts[1].t - lastSeen <= 10 + TICK + 1e-6).toBe(true)
			expect(losts[1].position).toBeCloseTo(b.cframe.Position, 1e-9)
			local pos, at = sys:lastKnown(1, 2)
			expect(pos).toBeCloseTo(b.cframe.Position, 1e-9)
			expect(at).toBe(losts[1].t)
			expect(sys:lastKnownIds(1)).toEqual({ 2 })
			-- the marker expires 30 s after the loss
			local lostT = losts[1].t
			local tick = 30 * 15 + 1
			while tick * TICK <= lostT + 30 - TICK do
				sys:update(tick * TICK, { a, b }, world)
				tick += 1
			end
			expect(sys:lastKnown(1, 2) ~= nil).toBe(true)
			F.run(sys, { a, b }, world, tick, tick + 2)
			expect(sys:lastKnown(1, 2)).toBeNil()
			-- re-spot: wall destroyed → Spotted again (not first), marker cleared
			world:destroyObject("wall")
			local again = nil
			F.run(sys, { a, b }, world, tick + 3, tick + 40, function(_, _, events)
				for _, e in F.filter(events, "Spotted") do
					again = e
				end
			end)
			expect(again ~= nil).toBe(true)
			expect(again.first).toBe(false)
			expect(sys:lastKnownIds(1)).toEqual({})
		end)

		it("re-spotting during the marker clears it", function()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 5)
			world:addBox({
				id = "w",
				destructible = true,
				cframe = CFrame.new(0, 30, -450),
				size = Vector3.new(180, 60, 3),
			})
			F.run(sys, { a, b }, world, 6, 30 * 12)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			expect(sys:lastKnownIds(1)).toEqual({ 2 })
			world:destroyObject("w")
			F.run(sys, { a, b }, world, 30 * 12 + 1, 30 * 14)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			expect(sys:lastKnownIds(1)).toEqual({})
		end)

		it(
			"edge flicker: oscillating ±1 m across the spot distance changes visibility at most once per 10 s (REG-SPT-06)",
			function()
				local world = F.flatWorld()
				local edge = VisibilityModel.spotDistance(400, 0.12) -- 358 m
				local a = F.vehicle(1, 1, 0, 0)
				local b = F.vehicle(2, 2, 0, -edge, { viewRangeM = 0, moving = true })
				local sys = SpottingSystem.new()
				local transitions = {}
				F.run(sys, { a, b }, world, 1, 30 * 60, function(_, now, events)
					F.place(b, 0, -(edge + math.sin(2 * math.pi * now)))
					for _, e in events do
						if e.team == 1 and (e.kind == "Spotted" or e.kind == "Lost") then
							table.insert(transitions, now)
						end
					end
				end)
				expect(#transitions >= 1).toBe(true)
				for i = 2, #transitions do
					expect(transitions[i] - transitions[i - 1] >= 10 - 1e-6).toBe(true)
				end
			end
		)
	end)

	describe("Sixth Sense (REG-SPT-05)", function()
		it("fires once, 3 s after the first team-visible tick, and re-arms after an unspotted period", function()
			expect(Config.applyOverrides({ Spotting = { SPOT_LINGER_S = 1 } })).toBeOk()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			local alerts = {}
			local function collect(_, now, events)
				for _, e in events do
					if e.kind == "SixthSense" then
						table.insert(alerts, { t = now, team = e.team, target = e.target })
					end
				end
			end
			F.run(sys, { a, b }, world, 1, 30 * 8, collect)
			expect(#alerts).toBe(1)
			expect(alerts[1].target).toBe(2)
			expect(alerts[1].team).toBe(2) -- delivered to the spotted vehicle's own team
			expect(alerts[1].t).toBeCloseTo(TICK + 3, 1e-6)
			-- hidden: lost after the 1 s linger, then re-spotted → a second alert 3 s after the re-spot
			world:addBox({
				id = "w",
				destructible = true,
				cframe = CFrame.new(0, 30, -450),
				size = Vector3.new(180, 60, 3),
			})
			F.run(sys, { a, b }, world, 30 * 8 + 1, 30 * 12, collect)
			expect(sys:isExposed(2)).toBe(false)
			world:destroyObject("w")
			local respotAt = nil
			F.run(sys, { a, b }, world, 30 * 12 + 1, 30 * 20, function(tick, now, events)
				for _, e in events do
					if e.kind == "Spotted" and respotAt == nil then
						respotAt = now
					end
				end
				collect(tick, now, events)
			end)
			expect(#alerts).toBe(2)
			expect(alerts[2].t - respotAt).toBeCloseTo(3, 1e-6)
		end)

		it("no alert when the vehicle is unspotted before 3 s", function()
			expect(Config.applyOverrides({ Spotting = { SPOT_LINGER_S = 1 } })).toBeOk()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			sys:update(TICK, { a, b }, world)
			world:addBox({ cframe = CFrame.new(0, 30, -450), size = Vector3.new(180, 60, 3) })
			local alerts = 0
			F.run(sys, { a, b }, world, 2, 30 * 6, function(_, _, events)
				alerts += #F.filter(events, "SixthSense")
			end)
			expect(alerts).toBe(0)
		end)

		it("suppressed while the commander is injured; fires on recovery if still spotted", function()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0, sixthSense = false })
			local sys = SpottingSystem.new()
			local alerts = {}
			F.run(sys, { a, b }, world, 1, 150, function(_, now, events)
				if #F.filter(events, "SixthSense") > 0 then
					table.insert(alerts, now)
				end
			end)
			expect(#alerts).toBe(0)
			b.sixthSense = true
			F.run(sys, { a, b }, world, 151, 300, function(_, now, events)
				if #F.filter(events, "SixthSense") > 0 then
					table.insert(alerts, now)
				end
			end)
			expect(#alerts).toBe(1)
			expect(alerts[1]).toBeCloseTo(151 * TICK, 1e-9)
		end)
	end)

	describe("attribution and destroyed vehicles (REG-SPT-07)", function()
		local function scene()
			local world = F.flatWorld()
			local a = F.vehicle(1, 1, -20, 0)
			local b = F.vehicle(2, 1, 20, 0)
			local c = F.vehicle(3, 1, 60, 0, { viewRangeM = 0 }) -- blind ally
			local t = F.vehicle(10, 2, 0, -200, { viewRangeM = 0, headingDeg = 180 })
			return world, a, b, c, t
		end

		it("spottersOf lists the allies who saw the target within 10 s, incl. a destroyed spotter", function()
			local world, a, b, c, t = scene()
			local sys = SpottingSystem.new()
			local events = F.filter(sys:update(TICK, { a, b, c, t }, world), "Spotted")
			expect(#events).toBe(1)
			expect(events[1].spotter).toBe(1) -- simultaneous: lowest id
			expect(events[1].first).toBe(true)
			F.run(sys, { a, b, c, t }, world, 2, 60)
			expect(sys:spottersOf(10, 2)).toEqual({ 1, 2 })
			expect(sys:spottersOf(10, 2, 1)).toEqual({ 1, 2 })
			expect(sys:spottersOf(10, 2, 2)).toEqual({})
			local out = { 99 }
			expect(sys:spottersOf(10, 2, nil, out)).toEqual({ 1, 2 })
			expect(out).toEqual({ 1, 2 })
			-- A is destroyed at 2 s: still credited for 10 s after its last sighting, never again after
			a.alive = false
			F.run(sys, { a, b, c, t }, world, 61, 90)
			local lastA = sys:lastSeenBy(1, 10)
			expect(lastA <= 2 + 1e-9).toBe(true)
			expect(sys:spottersOf(10, lastA + 9.9)).toEqual({ 1, 2 })
			expect(sys:spottersOf(10, lastA + 10.1)).toEqual({ 2 })
			F.run(sys, { a, b, c, t }, world, 91, 400)
			expect(sys:lastSeenBy(1, 10)).toBe(lastA) -- dead observers never spot
			expect(sys:pairInfo(1, 10).lastCheck <= 2 + 1e-9).toBe(true)
			expect(sys:isVisibleTo(1, 10)).toBe(true) -- B keeps it lit
		end)

		it("a dead spotter's sighting lingers for the rest of the 10 s, then the target is lost", function()
			local world, a, _b, c, t = scene()
			local sys = SpottingSystem.new()
			F.run(sys, { a, c, t }, world, 1, 30)
			expect(sys:isVisibleTo(1, 10)).toBe(true)
			a.alive = false
			local lostAt = nil
			F.run(sys, { a, c, t }, world, 31, 30 * 13, function(_, now, events)
				if #F.filter(events, "Lost") > 0 then
					lostAt = now
				end
			end)
			expect(lostAt).toBeCloseTo(sys:lastSeenBy(1, 10) + 10, TICK + 1e-6)
		end)

		it("wrecks are visible to every team, leave the visible set silently and never observe", function()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local hidden = F.vehicle(3, 2, 0, -420, { viewRangeM = 0, camo = F.camo({ stationary = 0.5 }) })
			local sys = SpottingSystem.new()
			F.run(sys, { a, b, hidden }, world, 1, 30)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			expect(sys:isVisibleTo(1, 3)).toBe(false)
			b.alive = false
			hidden.alive = false
			local events = sys:update(31 * TICK, { a, b, hidden }, world)
			expect(kinds(events)).toEqual({})
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			expect(sys:isVisibleTo(1, 3)).toBe(true) -- never spotted, but a wreck
			expect(sys:visibleSet(1)).toEqual({})
			expect(sys:replicationTier(1, 3)).toBe("Full")
			expect(sys:lastKnownIds(1)).toEqual({})
			-- a wreck observer sees nothing
			a.alive = false
			local c = F.vehicle(4, 2, 0, -200, { viewRangeM = 0 })
			F.run(sys, { a, b, hidden, c }, world, 32, 60)
			expect(sys:visibleSet(1)).toEqual({})
			expect(sys:pairInfo(1, 4).lastCheck).toBeNil()
		end)

		it("a revived vehicle starts unseen and is checked at once", function()
			local world = F.flatWorld({ boxes = { { x = 0, y = 10, z = -150, sx = 60, sy = 20, sz = 1 } } })
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new()
			F.place(b, 0, -40) -- proximity first
			F.run(sys, { a, b }, world, 1, 10)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			b.alive = false
			sys:update(11 * TICK, { a, b }, world)
			b.alive = true
			F.place(b, 0, -300) -- behind the wall
			sys:update(12 * TICK, { a, b }, world)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			expect(sys:pairInfo(1, 2).lastCheck).toBe(12 * TICK)
		end)

		it("a vehicle missing from the list is removed and Lost by teams that saw it", function()
			local world = F.flatWorld()
			local a, b = duel(300)
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 5)
			local events = F.filter(sys:update(6 * TICK, { a }, world), "Lost")
			-- team 1 loses the removed vehicle; team 2 loses what only the removed vehicle was seeing
			expect(#events).toBe(2)
			expect(events[1].team).toBe(1)
			expect(events[1].target).toBe(2)
			expect(events[1].position).toBeCloseTo(b.cframe.Position, 1e-9)
			expect(events[2].team).toBe(2)
			expect(events[2].target).toBe(1)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			expect(sys:pairInfo(1, 2)).toBeNil()
			expect(sys:stats().pairs).toBe(0)
		end)
	end)

	describe("battle ledger attribution (Attribution.noteSeen, battle-rules §7.1, REG-SPT-07)", function()
		local function rosterOf(vehicles: { any }): { any }
			local roster = {}
			for _, v in vehicles do
				table.insert(roster, { participantId = v.id, team = v.team })
			end
			return roster
		end

		local function damageAt(attacker: number, target: number, t: number): any
			return {
				t = t,
				attacker = attacker,
				target = target,
				kind = "Shell",
				damage = 100,
				potentialDamage = 100,
				modulesHit = {},
				crewInjured = {},
				fireStarted = false,
				killed = false,
				assistSpotters = {},
				assistTrackers = {},
				assistStunners = {},
			}
		end

		it("every successful check (LOS and proximity) reaches noteSeen with the same time, every tick", function()
			-- A sees T over 200 m of open ground (scheduled checks); B sits 40 m from T (proximity, every update);
			-- C is behind a wall 200 m from T (never); U is 600 m away (cheap reject, never).
			local world = F.flatWorld({ boxes = { { x = 100, y = 10, z = -200, sx = 3, sy = 20, sz = 100 } } })
			local a = F.vehicle(1, 1, 0, 0)
			local b = F.vehicle(2, 1, 0, -160)
			local c = F.vehicle(3, 1, 200, -200)
			local t = F.vehicle(10, 2, 0, -200, { headingDeg = 180, moving = true })
			local u = F.vehicle(11, 2, 0, -600, { headingDeg = 180 })
			local vehicles = { a, b, c, t, u }
			local attribution = Attribution.new(rosterOf(vehicles))
			local sys = SpottingSystem.new(nil, attribution)
			local distinctA = {}
			F.run(sys, vehicles, world, 1, 30 * 6, function(_, now)
				F.place(t, 2 * math.sin(now), -200) -- keeps the scene live; distances barely change
				for _, o in vehicles do
					for _, x in vehicles do
						if o.team ~= x.team then
							expect(attribution.seen[x.id][o.id]).toBe(sys:lastSeenBy(o.id, x.id))
						end
					end
				end
				expect(attribution.seen[10][2]).toBe(now) -- proximity: a success every update
				distinctA[attribution.seen[10][1]] = true
			end)
			local successesA = 0
			for _ in distinctA do
				successesA += 1
			end
			expect(successesA >= 6).toBe(true) -- A's scheduled checks (<= 1 s apart) each reached the ledger
			expect(attribution.seen[10][3]).toBeNil() -- behind the wall
			expect(attribution.seen[11][1]).toBeNil() -- beyond 445 m
			expect(attribution.seen[11][2]).toBeNil()
			expect(attribution.seen[1][10]).toBe(sys:lastSeenBy(10, 1)) -- the other direction too
			expect(attribution.seen[1][10] ~= nil).toBe(true)
		end)

		it(
			"Attribution.fill lists exactly the allies whose own check saw the target, dead spotters included",
			function()
				local world = F.flatWorld()
				local a = F.vehicle(1, 1, -20, 0)
				local b = F.vehicle(2, 1, 20, 0)
				local c = F.vehicle(3, 1, 60, 0, { viewRangeM = 0 }) -- blind ally (no own sighting)
				local t = F.vehicle(10, 2, 0, -200, { viewRangeM = 0, headingDeg = 180 })
				local vehicles = { a, b, c, t }
				local attribution = Attribution.new(rosterOf(vehicles))
				local sys = SpottingSystem.new(nil, attribution)
				F.run(sys, vehicles, world, 1, 60)
				expect(Attribution.fill(attribution, damageAt(3, 10, 2)).assistSpotters).toEqual({ 1, 2 })
				expect(sys:spottersOf(10, 2, 1)).toEqual({ 1, 2 }) -- the same set from the spotting side
				expect(Attribution.fill(attribution, damageAt(2, 10, 2)).assistSpotters).toEqual({ 1 }) -- not the shooter
				expect(Attribution.fill(attribution, damageAt(10, 1, 2)).assistSpotters).toEqual({}) -- T's team is blind
				-- A dies at 2 s: credited until 10 s after its last own sighting (REG-SPT-07), never refreshed again
				a.alive = false
				F.run(sys, vehicles, world, 61, 90)
				local lastA = sys:lastSeenBy(1, 10)
				expect(attribution.seen[10][1]).toBe(lastA)
				expect(lastA <= 2 + 1e-9).toBe(true)
				expect(Attribution.fill(attribution, damageAt(3, 10, lastA + 9.9)).assistSpotters).toEqual({ 1, 2 })
				expect(Attribution.fill(attribution, damageAt(3, 10, lastA + 10.1)).assistSpotters).toEqual({ 2 })
			end
		)

		it("the linger IS the ledger window: overriding LEDGER.ASSIST_SPOT_WINDOW_S moves the loss", function()
			expect(Config.applyOverrides({ Battle = { LEDGER = { ASSIST_SPOT_WINDOW_S = 4 } } })).toBeOk()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local attribution = Attribution.new(rosterOf({ a, b }))
			local sys = SpottingSystem.new(nil, attribution)
			expect(sys:lingerS()).toBe(4)
			expect(SpottingSystem.new():lingerS()).toBe(Config.Spotting.SPOT_LINGER_S) -- standalone: 10
			F.run(sys, { a, b }, world, 1, 30)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
			world:addBox({ id = "wall", cframe = CFrame.new(0, 30, -450), size = Vector3.new(180, 60, 3) })
			local lastSeen = sys:lastSeenBy(1, 2)
			local lostAt = nil
			F.run(sys, { a, b }, world, 31, 30 * 8, function(_, now, events)
				if #F.filter(events, "Lost") > 0 then
					lostAt = now
				end
				-- team-visible ⇔ some ally's ledger sighting is inside the window
				local seen = attribution.seen[2][1]
				local credited = seen ~= nil and now - seen <= attribution.windowS + 1e-6
				expect(sys:isVisibleTo(1, 2)).toBe(credited)
			end)
			expect(lostAt ~= nil).toBe(true)
			expect(lostAt - lastSeen > 4).toBe(true)
			expect(lostAt - lastSeen <= 4 + TICK + 1e-6).toBe(true)
			expect(sys:spottersOf(2, lastSeen + 3.9)).toEqual({ 1 })
			expect(sys:spottersOf(2, lastSeen + 4.1)).toEqual({})
		end)
	end)

	describe("replication filter (REG-SPT-08 API)", function()
		it("allies Full; visible enemies Full ≤ 564 m, Minimap beyond; unspotted None", function()
			local world = F.flatWorld()
			local a = F.vehicle(1, 1, 0, 0)
			local farAlly = F.vehicle(2, 1, 0, 700)
			local e = F.vehicle(10, 2, 0, -300, { viewRangeM = 0, headingDeg = 180 })
			local hidden = F.vehicle(11, 2, 200, -400, { viewRangeM = 0, camo = F.camo({ stationary = 0.6 }) })
			local sys = SpottingSystem.new()
			F.run(sys, { a, farAlly, e, hidden }, world, 1, 30)
			expect(sys:replicationTier(1, 2)).toBe("Full")
			expect(sys:replicationTier(1, 10)).toBe("Full")
			expect(sys:replicationTier(2, 10)).toBe("Minimap") -- team-visible, 1,000 m from the far ally
			expect(sys:replicationTier(1, 11)).toBe("None")
			expect(sys:replicationTier(10, 11)).toBe("Full") -- ally
			expect(sys:replicationTier(10, 1)).toBe("None") -- team 2 is blind
			expect(sys:replicationTier(1, 99)).toBe("None")
		end)
	end)

	describe("robustness", function()
		it("rejects structural mistakes", function()
			local world = F.flatWorld()
			local a, b = duel(300)
			local sys = SpottingSystem.new()
			expect(function()
				sys:update(0 / 0, { a, b }, world)
			end).toThrow("finite")
			sys:update(1, { a, b }, world)
			expect(function()
				sys:update(0.5, { a, b }, world)
			end).toThrow("backwards")
			expect(function()
				sys:update(2, { a, a }, world)
			end).toThrow("duplicate")
			local moved = F.vehicle(2, 1, 0, -300)
			expect(function()
				sys:update(3, { a, moved }, world)
			end).toThrow("changed team")
			expect(function()
				SpottingSystem.new():update(1, { { id = 1, team = 1 } }, world)
			end).toThrow("cframe")
			expect(function()
				SpottingSystem.new({ visibilityMult = -1 })
			end).toThrow("visibilityMult")
			expect(function()
				SpottingSystem.new(nil, { windowS = 10 } :: any)
			end).toThrow("AttributionState")
			expect(function()
				sys:setVisibilityMult(0 / 0)
			end).toThrow("finite")
		end)

		it("a non-finite pose skips the vehicle's pairs without errors", function()
			local world = F.flatWorld()
			local a, b = duel(300)
			b.cframe = CFrame.new(0 / 0, 0, 0)
			local sys = SpottingSystem.new()
			F.run(sys, { a, b }, world, 1, 30)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			expect(sys:isVisibleTo(2, 1)).toBe(false)
			b.cframe = CFrame.new(0, 0, -900) * CFrame.Angles(0, math.pi, 0)
			sys:update(31 * TICK, { a, b }, world)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
		end)

		it("visibilityMult scales VR (weather hook)", function()
			local world = F.flatWorld()
			local a, b = duel(300, nil, { viewRangeM = 0 })
			local sys = SpottingSystem.new({ visibilityMult = 0.5 })
			sys:update(TICK, { a, b }, world)
			expect(sys:viewRangeOf(1)).toBe(200)
			expect(sys:isVisibleTo(1, 2)).toBe(false)
			sys:setVisibilityMult(1)
			sys:forceCheck(1)
			sys:update(2 * TICK, { a, b }, world)
			expect(sys:viewRangeOf(1)).toBe(400)
			expect(sys:isVisibleTo(1, 2)).toBe(true)
		end)

		it("reuses event records between updates", function()
			local world = F.flatWorld()
			local a, b = duel(300)
			local sys = SpottingSystem.new()
			local first = sys:update(TICK, { a, b }, world)
			local record = first[1]
			local second = sys:update(2 * TICK, { a, b }, world)
			expect(first == second).toBe(true)
			expect(#second).toBe(0)
			b.alive = false
			sys:update(3 * TICK, { a, b }, world)
			b.alive = true
			local third = sys:update(4 * TICK, { a, b }, world)
			expect(third[1] == record).toBe(true)
		end)
	end)

	describe("determinism", function()
		local function scenario(order: { number }, seed: number): ({ string }, { number })
			local world = F.flatWorld({
				boxes = { { x = 30, y = 5, z = -150, sx = 40, sy = 10, sz = 2 } },
				foliage = {
					{ x = -40, y = 1.5, z = -160, r = 6, c = 0.5 },
					{ x = 10, y = 1.5, z = -30, r = 4, c = 0.25 },
				},
			})
			local base = {}
			for i = 1, 8 do
				local team = if i <= 4 then 1 else 2
				base[i] = F.vehicle(i * 7, team, -90 + 25 * i, if team == 1 then 0 else -250, {
					headingDeg = if team == 1 then 0 else 180,
					camo = F.camo({ stationary = 0.05 * i, moving = 0.03 * i, afterShotMul = 0.3, net = 0.1 }),
				})
			end
			local vehicles = {}
			for i, idx in order do
				vehicles[i] = base[idx]
			end
			local rng = RNG.new(seed)
			local log, rays = {}, {}
			local sys = SpottingSystem.new()
			for tick = 1, 30 * 20 do
				local now = tick * TICK
				for i = 1, 8 do
					local v = base[i]
					local z = (if i <= 4 then 0 else -250) + 120 * math.sin(now * 0.3 + i)
					local x = -90 + 25 * i + 20 * math.cos(now * 0.2 * i)
					F.place(v, x, z)
					v.moving = (tick + i) % 90 < 60
					if rng:chance(0.004) then
						v.lastShotAt = now
					end
				end
				for _, e in sys:update(now, vehicles, world) do
					table.insert(log, `{tick}:{e.kind}:{e.team}:{e.target}:{tostring(e.spotter)}:{tostring(e.first)}`)
				end
				table.insert(rays, sys:stats().rays)
			end
			return log, rays
		end

		it("the same inputs in any list order give the same event stream and ray counts", function()
			local logA, raysA = scenario({ 1, 2, 3, 4, 5, 6, 7, 8 }, 9)
			local logB, raysB = scenario({ 8, 3, 5, 1, 7, 2, 6, 4 }, 9)
			expect(#logA > 4).toBe(true)
			expect(logB).toEqual(logA)
			expect(raysB).toEqual(raysA)
		end)
	end)
end)
