-- covers: 30-vehicle randomized soak (00-DECISIONS §18 budget, §20 invariant 4 / REG-SPT-08 filter consistency),
-- REG-SPT-02/-03 (independent brute-force oracle on random static scenes), REG-SPT-07 (dead spotters), determinism
-- (ARCHITECTURE §13 P0: same seed + inputs → same event stream), battle-rules §7.1 (the ledger's Attribution receives
-- every successful check; team visibility ⇔ an ally's ledger sighting within the window).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Attribution = require("@game/ReplicatedStorage/Shared/Battle/Ledger/Attribution")
local HeightmapWorld = require("@tests/Harness/HeightmapWorld")
local SpottingSystem = require("@game/ReplicatedStorage/Shared/Spotting/SpottingSystem")
local VisibilityModel = require("@game/ReplicatedStorage/Shared/Spotting/VisibilityModel")
local F = require("./SpottingFixtures")

local S = F.S
local TICK = F.DT
local EPS = 1e-6

-- Rolling hills (studs in, studs out): up to ±7.5 m, wavelengths 200–450 m.
local function hills(x: number, z: number): number
	local xm, zm = x / S, z / S
	return S * (5 * math.sin(xm / 70) * math.cos(zm / 55) + 2.5 * math.sin((xm + zm) / 35))
end

local KINDS = { "LightBush", "Hedgerow", "DenseBush", "TreeCrown", "FelledTree", "Thicket" }

-- Map: hills (optional), buildings and foliage spheres, all in a 900 m square.
local function makeWorld(rng: any, hilly: boolean, buildings: number, bushes: number, half: number): any
	local world = HeightmapWorld.new({
		height = if hilly then hills else nil,
		step = if hilly then 15 else 4000,
	})
	local ground = function(xm: number, zm: number): number
		return world:heightAt(xm * S, zm * S) / S
	end
	for i = 1, buildings do
		local x, z = rng:range(-half, half), rng:range(-half * 0.6, half * 0.6)
		local sx, sz, sy = rng:range(8, 40), rng:range(8, 40), rng:range(6, 15)
		F.addWall(
			world,
			{ x = x, y = ground(x, z) + sy / 2 - 1, z = z, sx = sx, sy = sy, sz = sz, yawDeg = rng:range(0, 90) },
			`b{i}`
		)
	end
	for i = 1, bushes do
		local x, z = rng:range(-half, half), rng:range(-half, half)
		local kind = KINDS[rng:int(1, #KINDS)]
		world:addFoliage({
			id = `f{i}`,
			center = Vector3.new(x * S, (ground(x, z) + rng:range(0.5, 3)) * S, z * S),
			radius = rng:range(2, 6) * S,
			concealment = VisibilityModel.foliageConcealment(kind),
		})
	end
	return world, ground
end

local CLASS_CAMO = {
	{ stationary = 0.18, moving = 0.18, net = 0.10 },
	{ stationary = 0.12, moving = 0.07, net = 0.10 },
	{ stationary = 0.05, moving = 0.025, net = 0.05 },
	{ stationary = 0.28, moving = 0.16, net = 0.15 },
	{ stationary = 0.18, moving = 0.11, net = 0.15 },
}

type Agent = { v: any, x: number, z: number, wx: number, wz: number, heading: number, stopUntil: number, deadAt: number? }

local function makeAgents(rng: any, ground: (number, number) -> number): { Agent }
	local agents = {}
	for team = 1, 2 do
		for i = 1, 15 do
			local id = (team - 1) * 100 + i
			local x = rng:range(-300, 300)
			local z = if team == 1 then rng:range(80, 330) else rng:range(-330, -80)
			local c = CLASS_CAMO[rng:int(1, #CLASS_CAMO)]
			local v = F.vehicle(id, team, x, z, {
				yM = ground(x, z),
				viewRangeM = rng:range(300, 440),
				camo = F.camo({
					stationary = c.stationary,
					moving = c.moving,
					net = c.net,
					afterShotMul = rng:range(0.15, 0.3),
					paint = if rng:chance(0.3) then 0.04 else 0,
				}),
				turretYawRad = rng:range(-math.pi, math.pi),
			})
			table.insert(agents, {
				v = v,
				x = x,
				z = z,
				wx = rng:range(-350, 350),
				wz = rng:range(-350, 350),
				heading = 0,
				stopUntil = 0,
				deadAt = nil,
			})
		end
	end
	return agents
end

-- Moves every agent one tick (8 m/s toward its waypoint, random stops, shots, deaths).
local function stepAgents(agents: { Agent }, rng: any, ground: (number, number) -> number, now: number)
	for _, a in agents do
		local v = a.v
		if not v.alive then
			continue
		end
		if now > 5 and rng:chance(0.0006) then
			v.alive = false
			v.moving = false
			a.deadAt = now
			continue
		end
		if now < a.stopUntil then
			v.moving = false
		else
			local dx, dz = a.wx - a.x, a.wz - a.z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist < 5 then
				a.wx, a.wz = rng:range(-350, 350), rng:range(-350, 350)
				if rng:chance(0.4) then
					a.stopUntil = now + rng:range(1, 6)
				end
				v.moving = false
			else
				local step = 8 * TICK
				a.x += dx / dist * step
				a.z += dz / dist * step
				a.heading = math.atan2(dx, -dz)
				v.moving = true
			end
		end
		v.turretYawRad += rng:range(-0.05, 0.05)
		v.cframe = CFrame.new(a.x * S, ground(a.x, a.z) * S, a.z * S) * CFrame.Angles(0, -a.heading, 0)
		if rng:chance(0.004) then
			v.lastShotAt = now
		end
	end
end

local function contains(list: { number }, id: number): boolean
	return table.find(list, id) ~= nil
end

-- Per-tick invariants of the spotting state vs the inputs and the event stream.
local function checkInvariants(
	sys: any,
	attribution: any,
	agents: { Agent },
	events: { any },
	mirror: any,
	episodes: any,
	now: number
)
	local linger = sys:lingerS()
	expect(linger).toBe(attribution.windowS)
	local byId = {}
	for _, a in agents do
		byId[a.v.id] = a
	end
	-- event stream → client mirror (REG-MINI-01: deaths leave silently)
	for _, e in events do
		if e.kind == "Spotted" then
			expect(mirror[e.team][e.target]).toBeNil()
			mirror[e.team][e.target] = true
			local spotter = byId[e.spotter]
			expect(spotter.v.team).toBe(e.team)
			expect(spotter.v.alive).toBe(true)
			expect(sys:lastSeenBy(e.spotter, e.target)).toBe(now)
		elseif e.kind == "Lost" then
			expect(mirror[e.team][e.target]).toBe(true)
			mirror[e.team][e.target] = nil
		elseif e.kind == "SixthSense" then
			local target = byId[e.target]
			expect(target.v.alive).toBe(true)
			expect(e.team).toBe(target.v.team)
			expect(sys:isExposed(e.target)).toBe(true)
			expect(episodes[e.target]).toBeNil() -- one alert per exposure episode
			episodes[e.target] = now
		end
	end
	for _, team in { 1, 2 } do
		local set = sys:visibleSet(team)
		for i = 2, #set do
			expect(set[i] > set[i - 1]).toBe(true)
		end
		local mirrorCount = 0
		for _ in mirror[team] do
			mirrorCount += 1
		end
		expect(mirrorCount).toBe(#set)
		for _, a in agents do
			local v = a.v
			local inSet = contains(set, v.id)
			if v.team == team or not v.alive then
				-- allies and wrecks: always visible, never listed
				expect(inSet).toBe(false)
				expect(sys:isVisibleTo(team, v.id)).toBe(true)
			else
				expect(sys:isVisibleTo(team, v.id)).toBe(inSet)
				expect(mirror[team][v.id] == true).toBe(inSet)
				-- visible ⇔ justified by a sighting of the team within the linger window, and the ledger agrees
				-- (every sighting reached Attribution.noteSeen with the same time; dead spotters still count)
				local justified, credited = false, false
				for _, o in agents do
					if o.v.team == team then
						local seen = sys:lastSeenBy(o.v.id, v.id)
						expect(attribution.seen[v.id][o.v.id]).toBe(seen)
						if seen ~= nil and now - seen <= linger + EPS then
							justified = true
						end
						local ledger = attribution.seen[v.id][o.v.id]
						if ledger ~= nil and now - ledger <= attribution.windowS + EPS then
							credited = true
						end
					end
				end
				expect(justified).toBe(inSet)
				expect(credited).toBe(inSet)
				-- replication filter agrees with isVisibleTo for every observer of the team
				for _, o in agents do
					if o.v.team == team then
						expect(sys:replicationTier(o.v.id, v.id) ~= "None").toBe(inSet)
					end
				end
			end
		end
	end
	for _, a in agents do
		local v = a.v
		-- dead observers never spot
		if a.deadAt ~= nil then
			for _, t in agents do
				local seen = sys:lastSeenBy(v.id, t.v.id)
				if seen ~= nil then
					expect(seen < a.deadAt).toBe(true)
				end
			end
		end
		-- attribution = exactly the enemies that saw the target within the assist window
		if v.alive then
			local expected = {}
			for _, o in agents do
				if o.v.team ~= v.team then
					local seen = sys:lastSeenBy(o.v.id, v.id)
					if seen ~= nil and now - seen <= linger + EPS then
						table.insert(expected, o.v.id)
					end
				end
			end
			table.sort(expected)
			expect(sys:spottersOf(v.id, now)).toEqual(expected)
			if not sys:isExposed(v.id) then
				episodes[v.id] = nil
			end
		end
	end
	local stats = sys:stats()
	expect(stats.pairsChecked + stats.pairsDeferred).toBe(stats.pairsDue)
end

-- `overrides` is a Config.applyOverrides patch (Spotting and/or Battle sections).
local function soak(
	seed: number,
	seconds: number,
	overrides: { [string]: any }?,
	withChecks: boolean
): (number, number, { string }, { [string]: number })
	if overrides ~= nil then
		expect(Config.applyOverrides(overrides)).toBeOk()
	end
	local limit = Config.Spotting.MAX_RAYS_PER_TICK
	local rng = RNG.new(seed)
	local inner, ground = makeWorld(rng, true, 14, 45, 380)
	local world = F.counting(inner)
	local agents = makeAgents(rng, ground)
	local vehicles = {}
	local roster = {}
	for _, a in agents do
		table.insert(vehicles, a.v)
		table.insert(roster, { participantId = a.v.id, team = a.v.team })
	end
	local attribution = Attribution.new(roster)
	local sys = SpottingSystem.new(nil, attribution)
	local mirror = { [1] = {}, [2] = {} }
	local episodes = {}
	local peak, total = 0, 0
	local log = {}
	local counts = { Spotted = 0, Lost = 0, SixthSense = 0 }
	local lastCheck = {}
	for tick = 1, math.floor(seconds * 30) do
		local now = tick * TICK
		stepAgents(agents, rng, ground, now)
		for _, a in agents do
			if not a.v.alive then
				for team = 1, 2 do
					mirror[team][a.v.id] = nil
				end
			end
		end
		world:reset()
		local events = sys:update(now, vehicles, world)
		expect(world.calls <= limit).toBe(true)
		expect(sys:stats().rays).toBe(world.calls)
		peak = math.max(peak, world.calls)
		total += world.calls
		for _, e in events do
			table.insert(log, `{tick}:{e.kind}:{e.team}:{e.target}:{tostring(e.spotter)}`)
			counts[e.kind] += 1
		end
		if not withChecks then
			continue
		end
		checkInvariants(sys, attribution, agents, events, mirror, episodes, now)
		-- fairness: every live pair is (re)checked within a bounded time, even under a tight budget
		for _, o in agents do
			for _, t in agents do
				if o.v.team ~= t.v.team and o.v.alive and t.v.alive then
					local info = sys:pairInfo(o.v.id, t.v.id)
					local key = o.v.id * 1000 + t.v.id
					if info.lastCheck ~= nil then
						lastCheck[key] = info.lastCheck
					end
					if now > 1 then
						expect(now - (lastCheck[key] or 0) <= 5).toBe(true)
					end
				end
			end
		end
	end
	return peak, total, log, counts
end

local SHORT_LINGER = { Spotting = { SPOT_LINGER_S = 3 }, Battle = { LEDGER = { ASSIST_SPOT_WINDOW_S = 3 } } }

describe("Spotting soak", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	it("30 vehicles on hills for 10 s: ray budget and every invariant hold each tick", function()
		-- linger (= the ledger's spot-assist window) shortened to 3 s so 10 s exercise many Spotted / Lost / marker /
		-- Sixth Sense cycles
		local peak, total, _, counts = soak(1337, 10, SHORT_LINGER, true)
		expect(peak <= Config.Spotting.MAX_RAYS_PER_TICK).toBe(true)
		expect(total > 0).toBe(true)
		-- the scenario actually exercises spotting, linger expiry and Sixth Sense
		expect({ counts.Spotted > 20, counts.Lost > 0, counts.SixthSense > 5 }).toEqual({ true, true, true })
	end)

	it("the same soak under a 48-ray budget defers gracefully and starves no pair", function()
		local peak = soak(4242, 5, { Spotting = { MAX_RAYS_PER_TICK = 48 } }, true)
		expect(peak <= 48).toBe(true)
	end)

	it("is deterministic: the same seed reproduces the event stream and ray counts", function()
		local peakA, totalA, logA = soak(1337, 4, SHORT_LINGER, false)
		local peakB, totalB, logB = soak(1337, 4, SHORT_LINGER, false)
		expect(#logA > 0).toBe(true)
		expect(peakB).toBe(peakA)
		expect(totalB).toBe(totalA)
		expect(logB).toEqual(logA)
	end)

	describe("brute-force oracle on random static scenes (REG-SPT-02 / REG-SPT-03)", function()
		local function centre(v: any): Vector3
			return v.cframe:PointToWorldSpace(Vector3.new(0, v.pivots.hullSize.Y / 2, 0))
		end

		local function ports(v: any): { Vector3 }
			local piv = v.pivots
			local top = piv.hullSize.Y
			top = math.max(top, piv.turretRing:PointToWorldSpace(piv.viewPoint).Y)
			for _, p in piv.camoPoints do
				top = math.max(top, p.Y)
			end
			return {
				(v.cframe * piv.turretRing * CFrame.Angles(0, -v.turretYawRad, 0)):PointToWorldSpace(piv.viewPoint),
				v.cframe:PointToWorldSpace(Vector3.new(0, top, 0)),
			}
		end

		-- Independent per-volume implementation of the 15 m rules (the system subtracts sums instead).
		local function foliageOn(world: any, from: Vector3, to: Vector3, shooterClear: number): number
			local offset = to - from
			local length = offset.Magnitude
			local dir = offset / length
			local observerClear = Config.Spotting.FOLIAGE_OBSERVER_CLEAR_M * S
			local sum = 0
			for _, f in world._foliage do
				local m = from - f.center
				local b = m:Dot(dir)
				local c = m:Dot(m) - f.radius * f.radius
				local disc = b * b - c
				if disc > 0 then
					local root = math.sqrt(disc)
					local t1 = math.max(0, -b - root)
					local t2 = math.min(length, -b + root)
					if t2 > t1 then
						local nearObserver = t1 < observerClear
						local nearShooter = shooterClear > 0 and t2 > length - shooterClear
						if not nearObserver and not nearShooter then
							sum += f.concealment
						end
					end
				end
			end
			return sum
		end

		local function oracle(world: any, o: any, t: any, now: number): boolean
			local C = Config.Spotting
			local distM = (centre(t) - centre(o)).Magnitude / S
			if distM <= C.PROXIMITY_RADIUS_M then
				return true
			end
			local fired = t.lastShotAt ~= nil and now - t.lastShotAt < C.SHOT_FOLIAGE_PENALTY_S
			local body = t.camo.stationary * (if fired then t.camo.afterShotMul else 1) + t.camo.paint
			local shooterClear = if fired then C.FOLIAGE_SHOOTER_CLEAR_M * S else 0
			for _, port in ports(o) do
				for _, hp in t.pivots.camoPoints do
					local cp = t.cframe:PointToWorldSpace(hp)
					if not world:sightLine(port, cp).blocked then
						local foliage = foliageOn(world, port, cp, shooterClear)
						local camo = math.min(C.CAMO_TOTAL_CAP, body + math.min(C.FOLIAGE_STACK_CAP, foliage))
						if distM <= VisibilityModel.spotDistance(o.viewRangeM, camo) then
							return true
						end
					end
				end
			end
			return false
		end

		local function scenes(count: number, hilly: boolean, seed: number): (number, number)
			local rng = RNG.new(seed)
			local seen, hidden = 0, 0
			for scene = 1, count do
				local world, ground = makeWorld(rng, hilly, 16, 50, 200)
				local vehicles = {}
				for i = 1, 6 do
					local team = if i <= 3 then 1 else 2
					local x, z = rng:range(-150, 150), rng:range(-180, 180)
					table.insert(
						vehicles,
						F.vehicle(i, team, x, z, {
							yM = ground(x, z),
							headingDeg = rng:range(-180, 180),
							turretYawRad = rng:range(-math.pi, math.pi),
							viewRangeM = rng:range(200, 480),
							camo = F.camo({
								stationary = rng:range(0, 0.5),
								afterShotMul = rng:range(0.1, 0.4),
								paint = if rng:chance(0.5) then 0.04 else 0,
								net = 0,
							}),
							lastShotAt = if rng:chance(0.3) then 0 else nil,
						})
					)
				end
				-- static scene: update until every pair has completed one check (spawn forcing + deferral)
				local sys = SpottingSystem.new()
				local now = 0
				for tick = 1, 30 do
					now = tick * TICK
					sys:update(now, vehicles, world)
					if sys:stats().pairsDeferred == 0 then
						break
					end
				end
				expect(sys:stats().pairsDeferred).toBe(0)
				for _, t in vehicles do
					for _, team in { 1, 2 } do
						if t.team ~= team then
							local expected = false
							for _, o in vehicles do
								if o.team == team and oracle(world, o, t, now) then
									expected = true
									break
								end
							end
							local got = sys:isVisibleTo(team, t.id)
							if got ~= expected then
								error(`scene {scene}: team {team} sees {t.id}: system {got}, oracle {expected}`)
							end
							if got then
								seen += 1
							else
								hidden += 1
							end
						end
					end
				end
			end
			return seen, hidden
		end

		it("100 flat scenes with buildings and foliage agree exactly with the oracle", function()
			local seen, hidden = scenes(100, false, 5150)
			-- both outcomes are well represented (600 team/target cases)
			expect({ seen > 100, hidden > 100 }).toEqual({ true, true })
		end)

		it("20 hilly scenes (terrain occlusion) agree exactly with the oracle", function()
			local seen, hidden = scenes(20, true, 6161)
			expect({ seen > 20, hidden > 20 }).toEqual({ true, true })
		end)
	end)
end)
