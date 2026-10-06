--!strict
--[[
	Matchmaking/BotFill — per-team fill state, class-mirror feasibility, the bot class plan (which class goes on which
	template row of which team) and the bot vehicle picks (role mirror, variety, factions).

	Purpose:          Turns a candidate's human teams into two complete teams (00-DECISIONS §8 "Mirror", "Caps/team",
	                  "Platoons" — bots never platooned; roster.md §3.4 rules 1-4):
	                    * mirror bots close each class gap (exact, or within the stage tolerance), preferring the row
	                      of the human they mirror; bots add artillery ONLY to mirror a human SPG;
	                    * filler bots complete both teams with identical classes per pair of slots, steering toward
	                      BOT_CLASS_MIX and only where the pool has that class at the row's tier;
	                    * vehicles: per class, bots facing an unmatched human role take that role (else its RoleGroup);
	                      paired fillers mirror each other's role; per team <= SOFT_COPIES copies preferred, a hard copy
	                      cap, tracked lights only unless the wheeled cap has room; uniform random among equals.
	Dependencies:     Types/Matchmaking, Core/RNG (type), Matchmaking/Rules, Matchmaking/Tickets (Unit type),
	                  Matchmaking/Pools (availability).
	State:            TeamState / Candidate records owned by the caller; module-level scratch buffers for the
	                  feasibility check (single-threaded, not re-entrant).
	Validation:       Callers pass consistent states (rows match the candidate). plan() returns nil when no bot plan
	                  satisfies caps / availability / tolerance.
	Error handling:   No throws; infeasibility is a nil plan; a vehicle pick that must exceed the copy cap is counted
	                  in the returned overflow number.
	Performance notes: mirrorFeasible is the greedy fill's inner check: O(classes + 2^k·rows) with k <= 5 classes in
	                  deficit, no allocation. plan() allocates O(team size); materialize() runs once per committed match.
]]

local MatchmakingTypes = require("@game/ReplicatedStorage/Shared/Types/Matchmaking")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Rules = require("./Rules")
local Tickets = require("./Tickets")

type MatchmakingSettings = MatchmakingTypes.MatchmakingSettings
type MatchmakerConfig = MatchmakingTypes.MatchmakerConfig
type TemplateSpec = MatchmakingTypes.TemplateSpec
type BotVehicle = MatchmakingTypes.BotVehicle
type BotSlot = MatchmakingTypes.BotSlot
type Unit = Tickets.Unit
type RNG = RNG.RNG

local CLASS_COUNT = Rules.CLASS_COUNT
local ARTILLERY = Rules.ARTILLERY

local BotFill = {}

--- One team being assembled. Arrays: row[r], class[c], cr[(r − 1)·5 + c] (humans per row and class).
export type TeamState = {
	humans: number,
	platoons: number,
	weight: number,
	row: { number },
	class: { number },
	cr: { number },
	wheeled: number,
	streakBottom: number, -- humans with a bottom-tier streak placed on the bottom row (rows > 1)
	bottomness: number, -- Σ humans (row − 1) / (rows − 1)
	units: { Unit },
	rolesByClass: { { string } }, -- [class] human roles
}

--- A (top tier, template) candidate with everything per-row precomputed.
export type Candidate = {
	key: string,
	top: number,
	rows: number,
	tiers: { number }, -- [row] tier, top first
	counts: { number }, -- [row] per-team slots
	template: TemplateSpec,
	teamSize: number,
	caps: { number }, -- [class] per-team cap
	wheeledCap: number,
	avail: { { boolean } }, -- [row][class] bots can field the class at that tier
	mix: { number }, -- [class] BOT_CLASS_MIX for the top tier
	poolPerClass: { number }, -- [class] distinct pool vehicles across the template's tiers
}

export type SlotPlan = { row: number, class: number, mirror: boolean }
export type ClassPlan = {
	slots: { { SlotPlan } }, -- [team]
	final: { { number } }, -- [team][class] humans + bots
	classErr: number,
	tolerance: number, -- smallest tolerance that worked (0 = exact mirror)
}

function BotFill.newTeam(rows: number): TeamState
	local roles = table.create(CLASS_COUNT)
	for c = 1, CLASS_COUNT do
		roles[c] = {}
	end
	return {
		humans = 0,
		platoons = 0,
		weight = 0,
		row = table.create(rows, 0),
		class = table.create(CLASS_COUNT, 0),
		cr = table.create(rows * CLASS_COUNT, 0),
		wheeled = 0,
		streakBottom = 0,
		bottomness = 0,
		units = {},
		rolesByClass = roles,
	}
end

--- Adds (sign 1) or removes (sign −1) a unit's COUNTS on a team (no roles / unit list): used for trial placements.
function BotFill.addCounts(team: TeamState, unit: Unit, row: number, sign: number)
	team.humans += sign * unit.size
	if unit.size > 1 then
		team.platoons += sign
	end
	team.row[row] += sign * unit.size
	local base = (row - 1) * CLASS_COUNT
	local vec = unit.classVec
	for c = 1, CLASS_COUNT do
		local n = vec[c]
		if n ~= 0 then
			team.class[c] += sign * n
			team.cr[base + c] += sign * n
		end
	end
	team.wheeled += sign * unit.wheeled
end

--- Commits a unit to a team: counts, roles, weight, position terms and the unit list.
function BotFill.addUnit(team: TeamState, unit: Unit, row: number, cand: Candidate, settings: MatchmakingSettings)
	BotFill.addCounts(team, unit, row, 1)
	table.insert(team.units, unit)
	for _, m in unit.ticket.members do
		table.insert(team.rolesByClass[Rules.CLASS_INDEX[m.vehicle.class]], m.vehicle.role)
	end
	local below = cand.rows - row
	team.weight += unit.size * (1 + settings.TEAM_WEIGHT_TIER_STEP * below)
	if cand.rows > 1 then
		team.bottomness += unit.size * (row - 1) / (cand.rows - 1)
		if row == cand.rows then
			team.streakBottom += unit.streak
		end
	end
end

-- Scratch buffers for mirrorFeasible (not re-entrant).
local needBuf = table.create(CLASS_COUNT, 0)
local needClasses = table.create(CLASS_COUNT, 0)

--- Can bots still close every class gap within `tol` on both teams (free slots, rows where the class exists)?
--- Hall's condition over the classes in deficit: every subset's need fits the free slots of the rows it can use.
function BotFill.mirrorFeasible(teams: { TeamState }, cand: Candidate, tol: number): boolean
	local rows = cand.rows
	for x = 1, 2 do
		local t, o = teams[x], teams[3 - x]
		local free = cand.teamSize - t.humans
		if free < 0 then
			return false
		end
		local total, k = 0, 0
		for c = 1, CLASS_COUNT do
			local n = o.class[c] - t.class[c] - tol
			if n > 0 then
				total += n
				k += 1
				needClasses[k] = c
				needBuf[k] = n
			end
		end
		if total > free then
			return false
		end
		if k > 0 then
			for mask = 1, bit32.lshift(1, k) - 1 do
				local need, rowMask = 0, 0
				for i = 1, k do
					if bit32.btest(mask, bit32.lshift(1, i - 1)) then
						need += needBuf[i]
						local c = needClasses[i]
						for r = 1, rows do
							if cand.avail[r][c] then
								rowMask = bit32.bor(rowMask, bit32.lshift(1, r - 1))
							end
						end
					end
				end
				local room = 0
				for r = 1, rows do
					if bit32.btest(rowMask, bit32.lshift(1, r - 1)) then
						room += cand.counts[r] - t.row[r]
					end
				end
				if need > room then
					return false
				end
			end
		end
	end
	return true
end

local function fillerRank(settings: MatchmakingSettings, c: number): number
	local idx = table.find(settings.BOT_FILLER_ORDER, Rules.CLASSES[c])
	return idx or 100
end

local function tryPlan(teams: { TeamState }, cand: Candidate, settings: MatchmakingSettings, tol: number): ClassPlan?
	local rows = cand.rows
	local final = { table.clone(teams[1].class), table.clone(teams[2].class) }
	local rowFree = { table.create(rows, 0), table.create(rows, 0) }
	for x = 1, 2 do
		for r = 1, rows do
			rowFree[x][r] = cand.counts[r] - teams[x].row[r]
			if rowFree[x][r] < 0 then
				return nil
			end
		end
	end
	local slots: { { SlotPlan } } = { {}, {} }

	-- 1. Mirror bots, most row-constrained class first.
	for x = 1, 2 do
		local t, o = teams[x], teams[3 - x]
		local order: { number } = {}
		for c = 1, CLASS_COUNT do
			if o.class[c] - t.class[c] - tol > 0 then
				table.insert(order, c)
			end
		end
		local function usable(c: number): number
			local n = 0
			for r = 1, rows do
				if cand.avail[r][c] then
					n += 1
				end
			end
			return n
		end
		table.sort(order, function(a: number, b: number): boolean
			local ua, ub = usable(a), usable(b)
			if ua ~= ub then
				return ua < ub
			end
			return a < b
		end)
		for _, c in order do
			local n = o.class[c] - t.class[c] - tol
			-- same row as the mirrored humans first
			for r = 1, rows do
				if n <= 0 then
					break
				end
				if cand.avail[r][c] and rowFree[x][r] > 0 then
					local idx = (r - 1) * CLASS_COUNT + c
					local k = math.min(n, rowFree[x][r], math.max(0, o.cr[idx] - t.cr[idx]))
					for _ = 1, k do
						table.insert(slots[x], { row = r, class = c, mirror = true })
					end
					rowFree[x][r] -= k
					n -= k
				end
			end
			-- then the usable row with the most room (bottom row on ties)
			while n > 0 do
				local best, bestFree = 0, 0
				for r = rows, 1, -1 do
					if cand.avail[r][c] and rowFree[x][r] > bestFree then
						best, bestFree = r, rowFree[x][r]
					end
				end
				if best == 0 then
					return nil
				end
				table.insert(slots[x], { row = best, class = c, mirror = true })
				rowFree[x][best] -= 1
				n -= 1
			end
			final[x][c] = o.class[c] - tol
		end
	end

	-- 2. Filler pairs: identical class on both teams, steering toward the mix.
	local freeList = { {}, {} }
	for x = 1, 2 do
		for r = 1, rows do
			for _ = 1, rowFree[x][r] do
				table.insert(freeList[x], r)
			end
		end
	end
	local caps, mix = cand.caps, cand.mix
	local pairs = math.min(#freeList[1], #freeList[2])
	for i = 1, pairs do
		local ra, rb = freeList[1][i], freeList[2][i]
		local best, bestScore, bestRank = 0, -math.huge, math.huge
		for c = 1, CLASS_COUNT do
			if c ~= ARTILLERY and cand.avail[ra][c] and cand.avail[rb][c] and final[1][c] < caps[c] and final[2][c] < caps[c] then
				local score = mix[c] - math.max(final[1][c], final[2][c])
				local rank = fillerRank(settings, c)
				if score > bestScore or (score == bestScore and rank < bestRank) then
					best, bestScore, bestRank = c, score, rank
				end
			end
		end
		if best == 0 then
			return nil
		end
		table.insert(slots[1], { row = ra, class = best, mirror = false })
		table.insert(slots[2], { row = rb, class = best, mirror = false })
		final[1][best] += 1
		final[2][best] += 1
	end

	-- 3. Leftover slots (tolerance plans): close the gap first, then the mix.
	for x = 1, 2 do
		local list = freeList[x]
		for i = pairs + 1, #list do
			local r = list[i]
			local other = final[3 - x]
			local best, bestGap, bestScore, bestRank = 0, -math.huge, -math.huge, math.huge
			for c = 1, CLASS_COUNT do
				local gap = other[c] - final[x][c]
				local allowed = cand.avail[r][c] and final[x][c] < caps[c] and (c ~= ARTILLERY or gap > 0)
				if allowed then
					local score = mix[c] - final[x][c]
					local rank = fillerRank(settings, c)
					if
						gap > bestGap
						or (gap == bestGap and score > bestScore)
						or (gap == bestGap and score == bestScore and rank < bestRank)
					then
						best, bestGap, bestScore, bestRank = c, gap, score, rank
					end
				end
			end
			if best == 0 then
				return nil
			end
			table.insert(slots[x], { row = r, class = best, mirror = bestGap > 0 })
			final[x][best] += 1
		end
	end

	local classErr = 0
	for c = 1, CLASS_COUNT do
		local d = math.abs(final[1][c] - final[2][c])
		if d > tol then
			return nil
		end
		classErr += d
	end
	return { slots = slots, final = final, classErr = classErr, tolerance = tol }
end

--- Bot class plan for two human teams: exact mirror if possible, else the smallest tolerance up to `tol`.
--- nil when no plan respects caps, row availability and the tolerance.
function BotFill.plan(teams: { TeamState }, cand: Candidate, settings: MatchmakingSettings, tol: number): ClassPlan?
	for t = 0, tol do
		local p = tryPlan(teams, cand, settings, t)
		if p then
			return p
		end
	end
	return nil
end

--- Role error between the HUMANS of both teams (candidate scoring estimate; bots usually close the rest).
function BotFill.humanRoleError(teams: { TeamState }, settings: MatchmakingSettings, groups: { [string]: string }): number
	local err = 0
	for c = 1, CLASS_COUNT do
		err += Rules.roleError(settings, teams[1].rolesByClass[c], teams[2].rolesByClass[c], groups)
	end
	return err
end

-- Unmatched roles of `a` against `b` (exact pairs, then same group), keeping a's order.
local function unmatched(a: { string }, b: { string }, groups: { [string]: string }): { string }
	local countB: { [string]: number } = {}
	for _, r in b do
		countB[r] = (countB[r] or 0) + 1
	end
	local left: { string } = {}
	for _, r in a do
		local n = countB[r]
		if n and n > 0 then
			countB[r] = n - 1
		else
			table.insert(left, r)
		end
	end
	local groupB: { [string]: number } = {}
	for r, n in countB do
		if n > 0 then
			local g = groups[r] or r
			groupB[g] = (groupB[g] or 0) + n
		end
	end
	local out: { string } = {}
	for _, r in left do
		local g = groups[r] or r
		local n = groupB[g]
		if n and n > 0 then
			groupB[g] = n - 1
		else
			table.insert(out, r)
		end
	end
	return out
end

type PickState = {
	copies: { [string]: number },
	wheeled: number,
	slotsOfClass: { number },
}

local function roleCost(settings: MatchmakingSettings, groups: { [string]: string }, role: string, desired: string?): number
	if desired == nil or role == desired then
		return settings.ROLE_MATCH.EXACT
	end
	local g1, g2 = groups[role], groups[desired]
	if g1 ~= nil and g1 == g2 then
		return settings.ROLE_MATCH.GROUP
	end
	return settings.ROLE_MATCH.OTHER
end

-- Picks a vehicle for (tier, class); returns (vehicle, overflowed).
local function pickVehicle(
	config: MatchmakerConfig,
	cand: Candidate,
	tier: number,
	c: number,
	desired: string?,
	state: PickState,
	rng: RNG,
	ignoreCap: boolean
): BotVehicle?
	local settings = config.settings
	local list = config.index[tier][c]
	local variety = settings.BOT_VARIETY
	local pool = math.max(1, cand.poolPerClass[c])
	local hardCap = math.max(variety.HARD_COPIES_MIN, math.ceil(state.slotsOfClass[c] / pool))
	local bestCost = math.huge
	local ties: { BotVehicle } = {}
	for _, v in list do
		if v.wheeled and state.wheeled >= cand.wheeledCap then
			continue
		end
		local copies = state.copies[v.defId] or 0
		if copies >= hardCap and not ignoreCap then
			continue
		end
		local cost = roleCost(settings, config.roleGroups, v.role, desired)
		if copies >= variety.SOFT_COPIES then
			cost += variety.SOFT_PENALTY
		end
		if ignoreCap then
			cost += copies -- spread the overflow
		end
		if cost < bestCost - 1e-9 then
			bestCost = cost
			table.clear(ties)
			table.insert(ties, v)
		elseif math.abs(cost - bestCost) <= 1e-9 then
			table.insert(ties, v)
		end
	end
	if #ties == 0 then
		return nil
	end
	return ties[rng:int(1, #ties)]
end

--- Turns a class plan into bot slots (vehicle, role, faction) per team. Returns ({ team1 bots, team2 bots },
--- overflows). botId is left "" and `team` is the plan's team index: the caller assigns both after the final side
--- order. Raises only if the plan names a (tier, class) the pool cannot field (plan / availability mismatch).
function BotFill.materialize(
	plan: ClassPlan,
	teams: { TeamState },
	cand: Candidate,
	config: MatchmakerConfig,
	skill: "Recruit" | "Regular" | "Veteran",
	rng: RNG
): ({ { BotSlot } }, number)
	local groups = config.roleGroups
	local states: { PickState } = {}
	for x = 1, 2 do
		local slotsOfClass = table.create(CLASS_COUNT, 0)
		for _, s in plan.slots[x] do
			slotsOfClass[s.class] += 1
		end
		states[x] = { copies = {}, wheeled = teams[x].wheeled, slotsOfClass = slotsOfClass }
	end
	local out: { { BotSlot } } = { {}, {} }
	local overflows = 0

	local function place(x: number, s: SlotPlan, desired: string?): string
		local tier = cand.tiers[s.row]
		local st = states[x]
		local v = pickVehicle(config, cand, tier, s.class, desired, st, rng, false)
		if v == nil then
			v = pickVehicle(config, cand, tier, s.class, desired, st, rng, true)
			overflows += 1
		end
		if v == nil then
			error(`BotFill: no {Rules.CLASSES[s.class]} vehicle at tier {tier} (plan/availability mismatch)`)
		end
		st.copies[v.defId] = (st.copies[v.defId] or 0) + 1
		if v.wheeled then
			st.wheeled += 1
		end
		table.insert(out[x], {
			botId = "",
			team = x,
			defId = v.defId,
			tier = v.tier,
			class = v.class,
			role = v.role,
			faction = v.faction,
			wheeled = v.wheeled,
			skill = skill,
			mirror = s.mirror,
		})
		return v.role
	end

	for c = 1, CLASS_COUNT do
		local bySide: { { SlotPlan } } = { {}, {} }
		for x = 1, 2 do
			for _, s in plan.slots[x] do
				if s.class == c then
					table.insert(bySide[x], s)
				end
			end
			table.sort(bySide[x], function(a: SlotPlan, b: SlotPlan): boolean
				if a.mirror ~= b.mirror then
					return a.mirror
				end
				return a.row < b.row
			end)
		end
		if #bySide[1] == 0 and #bySide[2] == 0 then
			continue
		end
		-- Desired roles: the other team's humans of this class that have no counterpart.
		local wantA = unmatched(teams[2].rolesByClass[c], teams[1].rolesByClass[c], groups)
		local wantB = unmatched(teams[1].rolesByClass[c], teams[2].rolesByClass[c], groups)
		local nextA, nextB = 1, 1
		local restA, restB = {}, {}
		for _, s in bySide[1] do
			if nextA <= #wantA then
				place(1, s, wantA[nextA])
				nextA += 1
			else
				table.insert(restA, s)
			end
		end
		for _, s in bySide[2] do
			if nextB <= #wantB then
				place(2, s, wantB[nextB])
				nextB += 1
			else
				table.insert(restB, s)
			end
		end
		-- Remaining slots in pairs: team 2 mirrors team 1's pick.
		local n = math.max(#restA, #restB)
		for i = 1, n do
			local sa, sb = restA[i], restB[i]
			local role: string? = nil
			if sa then
				role = place(1, sa, nil)
			end
			if sb then
				place(2, sb, role)
			end
		end
	end
	return out, overflows
end

--- Final class and role mirror errors over complete rosters (humans + bots).
function BotFill.rosterErrors(
	teams: { TeamState },
	bots: { { BotSlot } },
	settings: MatchmakingSettings,
	groups: { [string]: string }
): (number, number)
	local classErr, roleErr = 0, 0
	for c = 1, CLASS_COUNT do
		local lists: { { string } } = {}
		for x = 1, 2 do
			local list = table.clone(teams[x].rolesByClass[c])
			for _, b in bots[x] do
				if Rules.CLASS_INDEX[b.class] == c then
					table.insert(list, b.role)
				end
			end
			lists[x] = list
		end
		classErr += math.abs(#lists[1] - #lists[2])
		roleErr += Rules.roleError(settings, lists[1], lists[2], groups)
	end
	return classErr, roleErr
end

return BotFill
