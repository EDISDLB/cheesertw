--!strict
--[[
	Matchmaking/Rules — the matchmaking rules as small pure functions: tier spread, templates per team size, class
	caps, relaxation stages, region reach, bot skill, bot class mix and the soft role-mirror error.

	Purpose:          One implementation of 00-DECISIONS §8 shared by Tickets, BotFill, MapSelect and Matchmaker (and the
	                  QA invariant checks in tests).
	Dependencies:     Types/Matchmaking (types only).
	State:            None (CLASSES / CLASS_INDEX are frozen constants).
	Validation:       Callers pass validated settings (Config.Matchmaking); functions assume integer tiers.
	Error handling:   None (pure; unknown classes/regions yield the documented fallbacks).
	Performance notes: Called per candidate / per unit; no allocation except templatesFor / stage (cached by callers)
	                  and roleError (two small count maps per call).
]]

local MatchmakingTypes = require("@game/ReplicatedStorage/Shared/Types/Matchmaking")

type MatchmakingSettings = MatchmakingTypes.MatchmakingSettings
type TemplateSpec = MatchmakingTypes.TemplateSpec
type ModeRules = MatchmakingTypes.ModeRules

local Rules = {}

--- Vehicle classes in index order (counts are arrays indexed by this order everywhere in Matchmaking).
Rules.CLASSES = table.freeze({ "light", "medium", "heavy", "td", "artillery" })
Rules.CLASS_INDEX = table.freeze({ light = 1, medium = 2, heavy = 3, td = 4, artillery = 5 }) :: { [string]: number }
Rules.LIGHT = 1
Rules.MEDIUM = 2
Rules.HEAVY = 3
Rules.TD = 4
Rules.ARTILLERY = 5
Rules.CLASS_COUNT = 5
--- Effectively unlimited per-team cap (heavy / medium).
Rules.UNCAPPED = 1e6

export type Stage = {
	index: number, -- RELAX_STAGES index reached by the wait
	relax: number,
	maxBots: number, -- per battle, before team-size scaling
	regionReach: number, -- 0 own, 1 adjacent, 2 global
	startNow: boolean, -- full fill granted by "Start now with bots"
}

--- Spread of tier t (0 for tiers outside the table).
function Rules.spreadOf(settings: MatchmakingSettings, tier: number): number
	return settings.TIER_SPREAD[tier] or 0
end

--- True when vehicles of tiers a and b may share a battle: |a − b| <= min(spread[a], spread[b]).
function Rules.tiersMeet(settings: MatchmakingSettings, a: number, b: number): boolean
	local spread = settings.TIER_SPREAD
	local sa, sb = spread[a], spread[b]
	if sa == nil or sb == nil then
		return false
	end
	return math.abs(a - b) <= math.min(sa, sb)
end

--- True when every pair of tiers in [top − rows + 1, top] meets (the band of a `rows`-row template topped by `top`).
function Rules.bandValid(settings: MatchmakingSettings, top: number, rows: number): boolean
	local bottom = top - rows + 1
	if bottom < settings.TIER_MIN or top > settings.TIER_MAX then
		return false
	end
	for a = bottom, top do
		for b = a + 1, top do
			if not Rules.tiersMeet(settings, a, b) then
				return false
			end
		end
	end
	return true
end

--- Tier range a vehicle of `tier` can meet (garage "battle tiers"): [min, max] of tiers b with tiersMeet(tier, b).
function Rules.meetRange(settings: MatchmakingSettings, tier: number): (number, number)
	local lo, hi = tier, tier
	for b = settings.TIER_MIN, settings.TIER_MAX do
		if Rules.tiersMeet(settings, tier, b) then
			lo = math.min(lo, b)
			hi = math.max(hi, b)
		end
	end
	return lo, hi
end

--- Templates for a team size: TEMPLATES counts scaled by teamSize / TEAM_SIZE (round each row, the bottom row takes
--- the remainder). Templates with an empty or negative row are dropped. Order and ids are preserved.
function Rules.templatesFor(settings: MatchmakingSettings, teamSize: number): { TemplateSpec }
	local out: { TemplateSpec } = {}
	for _, tpl in settings.TEMPLATES do
		local counts: { number } = {}
		local base = 0
		for _, c in tpl.counts do
			base += c
		end
		if base <= 0 then
			continue
		end
		local used = 0
		local ok = true
		for i, c in tpl.counts do
			local n
			if i == #tpl.counts then
				n = teamSize - used
			else
				n = math.floor(c * teamSize / base + 0.5)
			end
			if n <= 0 then
				ok = false
				break
			end
			counts[i] = n
			used += n
		end
		if ok then
			table.insert(out, { id = tpl.id, counts = counts, weight = tpl.weight })
		end
	end
	return out
end

--- Per-team cap of a class index for a team size and mode (Rules.UNCAPPED for heavy / medium).
function Rules.classCap(settings: MatchmakingSettings, classIndex: number, teamSize: number, mode: ModeRules): number
	local class = Rules.CLASSES[classIndex]
	local override = if mode.classCaps then mode.classCaps[class] else nil
	if override ~= nil then
		return override
	end
	if classIndex == Rules.ARTILLERY and mode.competitive then
		return 0
	end
	local base = settings.CLASS_CAPS[class]
	if base == nil then
		return Rules.UNCAPPED
	end
	local cap = math.ceil(base * teamSize / settings.TEAM_SIZE)
	if classIndex == Rules.ARTILLERY and teamSize <= settings.SMALL_TEAM_SIZE then
		cap = math.min(cap, settings.SMALL_TEAM_ARTILLERY_CAP)
	end
	return cap
end

--- All five per-team caps (array in CLASSES order).
function Rules.classCaps(settings: MatchmakingSettings, teamSize: number, mode: ModeRules): { number }
	local caps = table.create(Rules.CLASS_COUNT, 0)
	for i = 1, Rules.CLASS_COUNT do
		caps[i] = Rules.classCap(settings, i, teamSize, mode)
	end
	return caps
end

--- Per-team wheeled cap for a team size.
function Rules.wheeledCap(settings: MatchmakingSettings, teamSize: number): number
	return math.ceil(settings.WHEELED_CAP * teamSize / settings.TEAM_SIZE)
end

--- Relaxation stage for a ticket that has waited `waitS` (RELAX_TIME_SCALE applied). A startWithBots ticket that
--- waited START_WITH_BOTS_AFTER_S gets the last stage's relax and bot allowance; its region reach follows its wait.
function Rules.stage(settings: MatchmakingSettings, waitS: number, startWithBots: boolean): Stage
	local stages = settings.RELAX_STAGES
	local scale = settings.RELAX_TIME_SCALE
	local index = 1
	for i, s in stages do
		if waitS >= s.fromS * scale then
			index = i
		end
	end
	local s = stages[index]
	if startWithBots and waitS >= settings.START_WITH_BOTS_AFTER_S then
		local last = stages[#stages]
		return { index = index, relax = last.relax, maxBots = last.maxBots, regionReach = s.regionReach, startNow = true }
	end
	return { index = index, relax = s.relax, maxBots = s.maxBots, regionReach = s.regionReach, startNow = false }
end

--- Bots allowed in one battle at a stage, scaled to the team size and capped so >= MIN_HUMANS humans remain.
function Rules.maxBots(settings: MatchmakingSettings, stage: Stage, teamSize: number, mode: ModeRules): number
	if not mode.botFill then
		return 0
	end
	local scaled = math.floor(stage.maxBots * teamSize / settings.TEAM_SIZE + 1e-9)
	return math.max(0, math.min(scaled, 2 * teamSize - settings.MIN_HUMANS))
end

--- Class mirror tolerance for a relax value.
function Rules.classTolerance(settings: MatchmakingSettings, relax: number, mode: ModeRules): number
	if mode.competitive then
		return 0
	end
	return if relax >= settings.CLASS_MIRROR_RELAX_AT then settings.CLASS_MIRROR_TOLERANCE else 0
end

--- 0 = same bucket, 1 = adjacent (REGION_ADJACENT, either direction), 2 = anything else.
function Rules.regionDistance(settings: MatchmakingSettings, a: string, b: string): number
	if a == b then
		return 0
	end
	local adjA = settings.REGION_ADJACENT[a]
	if adjA and table.find(adjA, b) then
		return 1
	end
	local adjB = settings.REGION_ADJACENT[b]
	if adjB and table.find(adjB, a) then
		return 1
	end
	return 2
end

--- Bot skill for a battle (00-DECISIONS §8 "Bots"): Recruit for new accounts, Veteran from VETERAN_MIN_TIER.
function Rules.botSkill(settings: MatchmakingSettings, avgBattles: number, topTier: number): "Recruit" | "Regular" | "Veteran"
	if avgBattles < settings.BOT_SKILL.RECRUIT_MAX_AVG_BATTLES then
		return "Recruit"
	elseif topTier >= settings.BOT_SKILL.VETERAN_MIN_TIER then
		return "Veteran"
	end
	return "Regular"
end

--- Default per-team class mix (array in CLASSES order) for a battle's top tier; artillery is always 0.
function Rules.classMix(settings: MatchmakingSettings, topTier: number): { number }
	local mix = table.create(Rules.CLASS_COUNT, 0)
	for _, entry in settings.BOT_CLASS_MIX do
		if topTier >= entry.minTier then
			for class, n in entry.mix do
				local i = Rules.CLASS_INDEX[class]
				if i ~= nil and i ~= Rules.ARTILLERY then
					mix[i] = n
				end
			end
			break
		end
	end
	return mix
end

--- Soft role-mirror error of ONE class: roles of team A vs team B are paired, exact roles first (EXACT each), then
--- same RoleGroup (GROUP each), then any (OTHER each). Unpaired surplus is the class mirror's job (classErr).
function Rules.roleError(
	settings: MatchmakingSettings,
	rolesA: { string },
	rolesB: { string },
	groups: { [string]: string }
): number
	local na, nb = #rolesA, #rolesB
	if na == 0 or nb == 0 then
		return 0
	end
	local pairsTotal = math.min(na, nb)
	-- exact pairs: multiset intersection of roles
	local countB: { [string]: number } = {}
	for _, r in rolesB do
		countB[r] = (countB[r] or 0) + 1
	end
	local leftA: { string } = {}
	local exact = 0
	for _, r in rolesA do
		local n = countB[r]
		if n ~= nil and n > 0 then
			countB[r] = n - 1
			exact += 1
		else
			table.insert(leftA, r)
		end
	end
	-- group pairs among leftovers
	local groupB: { [string]: number } = {}
	for r, n in countB do
		if n > 0 then
			local g = groups[r] or r
			groupB[g] = (groupB[g] or 0) + n
		end
	end
	local grouped = 0
	for _, r in leftA do
		local g = groups[r] or r
		local n = groupB[g]
		if n ~= nil and n > 0 then
			groupB[g] = n - 1
			grouped += 1
		end
	end
	local other = math.max(0, pairsTotal - exact - grouped)
	local m = settings.ROLE_MATCH
	return exact * m.EXACT + grouped * m.GROUP + other * m.OTHER
end

return Rules
