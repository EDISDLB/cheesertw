--!strict
--[[
	Battle/Rules/Capture — base capture zones (00-DECISIONS §9 "Capture"; report 04 §2.2 and R7; REG-BTL-01,
	REG-MAP-04).

	Purpose:          Per base and capturing team: each capper inside the circle accumulates its own points,
	                    points_v += rate · rateMul_v · dt · min(1, MAX_COUNTED / n)        (n = cappers inside)
	                  team progress = Σ points_v, capped at POINTS (100) → BaseCaptured. Standard: one base per team,
	                  captured by the enemy, defenders inside do NOT stop it; Encounter: one neutral base, frozen
	                  while both teams are inside, half rate; Assault: the defender's base, captured by attackers.
	                  Enemy HP damage (and, by config, a module crit) resets that capper's points; the attacker earns
	                  them as defense points (CaptureReset). A capper outside the circle keeps its points for
	                  LEAVE_GRACE_S, then loses them. Overturn resets without credit (resetVehicle).
	Dependencies:     Rules/ModeRules (settings), Core/Units, Core/MathUtil, Types/Battle + Types/Content (types).
	State:            CaptureState records owned by the caller (one per battle). Events (CaptureProgress,
	                  CaptureReset, BaseCaptured) are appended to an optional events list.
	Validation:       Bases whose battleType differs from the battle's are ignored. Non-positive / non-finite dt is
	                  ignored; non-finite rateMul counts as 0; dead vehicles and vehicles with canCapture = false
	                  never count as inside (but an alive enemy still contests). Allies, self and environment
	                  damage never reset. Progress stays in [0, POINTS] (Invariants: capture ∈ [0, 100]).
	Error handling:   No throws.
	Performance notes: O(bases × vehicles) per step (≤ 2 × 30); capper tables are created once per vehicle and base;
	                  per-step scratch arrays are reused. Vehicles are visited in ascending id order for deterministic
	                  floating-point sums whatever the caller's order.

	Positions: vehicles in studs (sim space); bases in metres from map content, converted once here. Inside means
	planar (x, z) distance ≤ radius, so height never matters.
]]

local ModeRules = require("./ModeRules")
local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local MathUtil = require("@game/ReplicatedStorage/Shared/Core/MathUtil")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type ModeSettings = ModeRules.ModeSettings
type CaptureSettings = ModeRules.CaptureSettings
type EntityId = BattleTypes.EntityId
type TeamId = BattleTypes.TeamId
type BattleEvent = BattleTypes.BattleEvent
type DamageEvent = BattleTypes.DamageEvent
type BattleType = ContentTypes.BattleType

--- A map capture base (Content.CaptureBase): center/radius in metres. `team` = owner (Standard), defender
--- (Assault) or nil (Encounter, neutral).
export type BaseSpec = {
	id: string,
	battleType: BattleType?,
	team: number?,
	center: { x: number, z: number },
	radiusM: number?,
}
export type RosterEntry = { participantId: EntityId, team: TeamId }
--- One vehicle as the capture step sees it this tick.
export type CaptureVehicle = {
	id: EntityId,
	team: TeamId,
	position: Vector3, -- studs
	alive: boolean,
	canCapture: boolean?, -- false while overturned (counts as outside); default true
	rateMul: number?, -- per-vehicle rate multiplier (event modes / future mechanics); default 1
}
export type ResetKind = "Hp" | "Crit" | "Stun"

export type Capper = { id: EntityId, points: number, outsideS: number }
export type TeamTrack = {
	team: TeamId,
	progress: number,
	cappers: { [EntityId]: Capper },
	capperIds: { EntityId }, -- ascending
	inside: { EntityId }, -- scratch: capturing vehicles inside this step (ascending)
	frozen: boolean,
	contested: boolean,
	lastEmitted: number,
	banked: boolean, -- points moved to CaptureState.banked (base captured)
}
export type BaseState = {
	id: string,
	owner: TeamId?,
	cx: number, -- studs
	cz: number,
	radiusStuds: number,
	radiusSq: number,
	tracks: { TeamTrack }, -- one per capturing team, ascending team
	capturedBy: TeamId?,
	capturedAt: number?,
}
export type CaptureState = {
	enabled: boolean,
	settings: CaptureSettings,
	battleType: BattleType,
	bases: { BaseState }, -- ascending id
	teamOf: { [EntityId]: TeamId },
	banked: { [EntityId]: number }, -- points of cappers whose base was captured
	defense: { [EntityId]: number }, -- points reset by this vehicle
	completed: { TeamId }, -- scratch returned by step
	_sorted: { CaptureVehicle }, -- scratch
}
export type BaseSnapshot = {
	base: string,
	team: TeamId,
	progress: number,
	frozen: boolean,
	contested: boolean,
	cappers: number,
	capturedBy: TeamId?,
}

local EPS = 1e-6

local Capture = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Per-vehicle rate multiplier: default 1, invalid (NaN, ±inf, negative) counts as 0.
local function rateMulOf(v: CaptureVehicle): number
	local mul = v.rateMul or 1
	if not isFinite(mul) or mul < 0 then
		return 0
	end
	return mul
end

local function byVehicleId(a: CaptureVehicle, b: CaptureVehicle): boolean
	return a.id < b.id
end

local function byBaseId(a: BaseState, b: BaseState): boolean
	return a.id < b.id
end

local function insertSorted(list: { EntityId }, id: EntityId)
	local i = #list
	while i >= 1 and list[i] > id do
		i -= 1
	end
	table.insert(list, i + 1, id)
end

--- Builds the capture state of one battle. Bases not matching settings.battleType are dropped; with
--- settings.captureEnabled = false the state has no bases (every call is a no-op).
function Capture.new(settings: ModeSettings, bases: { BaseSpec }, roster: { RosterEntry }): CaptureState
	local teamOf: { [EntityId]: TeamId } = {}
	local teams: { TeamId } = {}
	for _, entry in roster do
		teamOf[entry.participantId] = entry.team
		if table.find(teams, entry.team) == nil then
			table.insert(teams, entry.team)
		end
	end
	table.sort(teams)

	local cs = settings.capture
	local list: { BaseState } = {}
	if settings.captureEnabled then
		for _, spec in bases do
			if spec.battleType ~= nil and spec.battleType ~= settings.battleType then
				continue
			end
			local radiusM = spec.radiusM
			if radiusM == nil or not isFinite(radiusM) or radiusM <= 0 then
				radiusM = cs.radiusM
			end
			local radiusStuds = Units.mToStuds(radiusM :: number)
			local tracks: { TeamTrack } = {}
			for _, team in teams do
				-- Owned bases (Standard owner / Assault defender) are captured by the other teams only.
				if spec.team == nil or spec.team ~= team then
					table.insert(tracks, {
						team = team,
						progress = 0,
						cappers = {},
						capperIds = {},
						inside = {},
						frozen = false,
						contested = false,
						lastEmitted = 0,
						banked = false,
					})
				end
			end
			table.insert(list, {
				id = spec.id,
				owner = spec.team,
				cx = Units.mToStuds(spec.center.x),
				cz = Units.mToStuds(spec.center.z),
				radiusStuds = radiusStuds,
				radiusSq = radiusStuds * radiusStuds,
				tracks = tracks,
				capturedBy = nil,
				capturedAt = nil,
			})
		end
		table.sort(list, byBaseId)
	end

	return {
		enabled = settings.captureEnabled and #list > 0,
		settings = cs,
		battleType = settings.battleType,
		bases = list,
		teamOf = teamOf,
		banked = {},
		defense = {},
		completed = {},
		_sorted = {},
	}
end

--- True when `position` (studs) is inside the base circle (planar distance ≤ radius).
function Capture.isInside(base: BaseState, position: Vector3): boolean
	local dx = position.X - base.cx
	local dz = position.Z - base.cz
	return dx * dx + dz * dz <= base.radiusSq
end

local function emitProgress(
	state: CaptureState,
	base: BaseState,
	track: TeamTrack,
	t: number,
	events: { BattleEvent }?,
	force: boolean
)
	local progress = track.progress
	local last = track.lastEmitted
	local step = state.settings.progressEventStep
	local dropped = progress < last - EPS
	local crossed = math.floor((progress + EPS) / step) > math.floor((last + EPS) / step)
	if force or dropped or crossed then
		track.lastEmitted = progress
		if events then
			table.insert(events, {
				type = "CaptureProgress",
				t = t,
				base = base.id,
				team = track.team,
				points = MathUtil.round(progress, 0.01),
			})
		end
	end
end

-- Removes `points` of one capper from its track; keeps progress consistent (exact 0 when nobody holds points).
local function removePoints(track: TeamTrack, capper: Capper): number
	local removed = capper.points
	capper.points = 0
	if removed > 0 then
		track.progress = math.max(0, track.progress - removed)
		local anyone = false
		for _, id in track.capperIds do
			if track.cappers[id].points > 0 then
				anyone = true
				break
			end
		end
		if not anyone then
			track.progress = 0
		end
	end
	return removed
end

local function dropCapper(track: TeamTrack, index: number)
	local id = track.capperIds[index]
	table.remove(track.capperIds, index)
	track.cappers[id] = nil
end

--- Advances every base by `dt` at battle time `t`. `vehicles` = every vehicle this tick (any order). Returns the
--- teams that completed a capture on this step (ascending, reused array: copy it to keep it). Emits
--- CaptureProgress / BaseCaptured into `events`.
function Capture.step(
	state: CaptureState,
	vehicles: { CaptureVehicle },
	dt: number,
	t: number,
	events: { BattleEvent }?
): { TeamId }
	local completed = state.completed
	table.clear(completed)
	if not state.enabled or not (dt > 0) or not isFinite(dt) then
		return completed
	end
	local cs = state.settings

	local sorted = state._sorted
	table.clear(sorted)
	for _, v in vehicles do
		table.insert(sorted, v)
	end
	table.sort(sorted, byVehicleId)

	for _, base in state.bases do
		if base.capturedBy ~= nil then
			continue
		end
		for _, track in base.tracks do
			table.clear(track.inside)
			track.contested = false
			for _, v in sorted do
				if not v.alive or not Capture.isInside(base, v.position) then
					continue
				end
				if v.team == track.team then
					if v.canCapture ~= false then
						table.insert(track.inside, v.id)
					end
				else
					track.contested = true
				end
			end
			track.frozen = track.contested and cs.contestedFreezes

			-- Existing cappers: leave grace / forfeit.
			local dropped = false
			local i = 1
			while i <= #track.capperIds do
				local id = track.capperIds[i]
				local capper = track.cappers[id]
				if table.find(track.inside, id) ~= nil then
					capper.outsideS = 0
					i += 1
				else
					capper.outsideS += dt
					if capper.outsideS > cs.leaveGraceS + EPS then
						if removePoints(track, capper) > 0 then
							dropped = true
						end
						dropCapper(track, i)
					else
						i += 1
					end
				end
			end
			if dropped then
				emitProgress(state, base, track, t, events, false)
			end

			-- New cappers.
			for _, id in track.inside do
				if track.cappers[id] == nil then
					track.cappers[id] = { id = id, points = 0, outsideS = 0 }
					insertSorted(track.capperIds, id)
				end
			end

			-- Accrual.
			local n = #track.inside
			if n > 0 and not track.frozen and cs.rate > 0 then
				local factor = cs.rate * dt * math.min(1, cs.maxCounted / n)
				local total = 0
				for _, v in sorted do
					if v.team == track.team and table.find(track.inside, v.id) ~= nil then
						total += factor * rateMulOf(v)
					end
				end
				if total > 0 then
					local remaining = cs.points - track.progress
					local scale = if total > remaining then remaining / total else 1
					for _, v in sorted do
						if v.team == track.team and table.find(track.inside, v.id) ~= nil then
							local capper = track.cappers[v.id]
							capper.points += factor * rateMulOf(v) * scale
						end
					end
					track.progress = math.min(cs.points, track.progress + total * scale)
					if track.progress >= cs.points - EPS then
						track.progress = cs.points
					end
					emitProgress(state, base, track, t, events, track.progress >= cs.points)
				end
			end
		end

		-- Completion (after every track of the base advanced, so simultaneous completions are all reported: two
		-- teams finishing one neutral base on the same step both claim it and Outcome makes it a draw).
		for _, track in base.tracks do
			if track.progress >= cs.points and not track.banked then
				if base.capturedBy == nil then
					base.capturedBy = track.team
				end
				base.capturedAt = t
				track.banked = true
				for _, id in track.capperIds do
					local pts = track.cappers[id].points
					if pts > 0 then
						state.banked[id] = (state.banked[id] or 0) + pts
					end
				end
				if events then
					table.insert(events, { type = "BaseCaptured", t = t, base = base.id, team = track.team })
				end
				if table.find(completed, track.team) == nil then
					table.insert(completed, track.team)
				end
			end
		end
	end
	table.sort(completed)
	return completed
end

-- Clears `target`'s points on every live base; returns the total removed and emits per-base events.
local function resetEverywhere(
	state: CaptureState,
	target: EntityId,
	by: EntityId?,
	t: number,
	events: { BattleEvent }?
): number
	local total = 0
	for _, base in state.bases do
		if base.capturedBy ~= nil then
			continue
		end
		for _, track in base.tracks do
			local capper = track.cappers[target]
			if capper ~= nil and capper.points > 0 then
				local removed = removePoints(track, capper)
				total += removed
				if by ~= nil then
					state.defense[by] = (state.defense[by] or 0) + removed
					if events then
						table.insert(events, {
							type = "CaptureReset",
							t = t,
							base = base.id,
							by = by,
							capper = target,
							points = MathUtil.round(removed, 0.01),
						})
					end
				end
				emitProgress(state, base, track, t, events, false)
			end
		end
	end
	return total
end

--- A capper took damage of `kind` from `attacker` at battle time `t`. Resets its points on every base when the
--- config says so and the attacker is an enemy (allies, self and environment never reset). Returns the points
--- removed (credited to the attacker as defense points, CaptureReset event).
function Capture.onDamage(
	state: CaptureState,
	target: EntityId,
	attacker: EntityId?,
	kind: ResetKind,
	t: number,
	events: { BattleEvent }?
): number
	if not state.enabled or attacker == nil or attacker == target then
		return 0
	end
	local cs = state.settings
	if
		(kind == "Hp" and not cs.resetOnHpDamage)
		or (kind == "Crit" and not cs.resetOnModuleCrit)
		or (kind == "Stun" and not cs.resetOnStun)
	then
		return 0
	end
	local targetTeam = state.teamOf[target]
	local attackerTeam = state.teamOf[attacker]
	if targetTeam == nil or attackerTeam == nil or targetTeam == attackerTeam then
		return 0
	end
	return resetEverywhere(state, target, attacker, t, events)
end

--- Convenience: classifies a DamageEvent (HP damage > 0 → "Hp"; else a damaged module or injured crew → "Crit")
--- and applies onDamage. Returns the points removed.
function Capture.applyDamageEvent(state: CaptureState, damage: DamageEvent, events: { BattleEvent }?): number
	local kind: ResetKind? = nil
	if damage.damage > 0 then
		kind = "Hp"
	else
		if #damage.crewInjured > 0 then
			kind = "Crit"
		else
			for _, hit in damage.modulesHit do
				if hit.damage > 0 then
					kind = "Crit"
					break
				end
			end
		end
	end
	if kind == nil then
		return 0
	end
	return Capture.onDamage(state, damage.target, damage.attacker, kind, damage.t, events)
end

--- Removes `id`'s points everywhere without defense credit (overturned, drowned, destroyed by the environment).
function Capture.resetVehicle(state: CaptureState, id: EntityId, t: number, events: { BattleEvent }?): number
	if not state.enabled then
		return 0
	end
	return resetEverywhere(state, id, nil, t, events)
end

local function findTrack(state: CaptureState, baseId: string, team: TeamId): (BaseState?, TeamTrack?)
	for _, base in state.bases do
		if base.id == baseId then
			for _, track in base.tracks do
				if track.team == team then
					return base, track
				end
			end
			return base, nil
		end
	end
	return nil, nil
end

--- Progress of `team` on base `baseId` (0 when the team cannot capture it).
function Capture.progress(state: CaptureState, baseId: string, team: TeamId): number
	local _, track = findTrack(state, baseId, team)
	return if track then track.progress else 0
end

--- Points currently held by capper `id` on `baseId` for its team (0 when not capping there).
function Capture.capperPoints(state: CaptureState, baseId: string, id: EntityId): number
	local team = state.teamOf[id]
	if team == nil then
		return 0
	end
	local _, track = findTrack(state, baseId, team)
	if track == nil then
		return 0
	end
	local capper = track.cappers[id]
	return if capper then capper.points else 0
end

--- True when `team`'s capture of `baseId` is frozen by enemy presence this step (Encounter).
function Capture.isFrozen(state: CaptureState, baseId: string, team: TeamId): boolean
	local _, track = findTrack(state, baseId, team)
	return track ~= nil and track.frozen
end

--- The Assault defending team (owner of the battle's base), or nil for other battle types.
function Capture.defenderTeam(state: CaptureState): TeamId?
	if state.battleType ~= "Assault" then
		return nil
	end
	for _, base in state.bases do
		if base.owner ~= nil then
			return base.owner
		end
	end
	return nil
end

--- Capture points per participant for BattleStats.capturePoints: points banked by completed captures plus points
--- still held at the time of the call (call it at the end of the battle). Fresh table.
function Capture.participantPoints(state: CaptureState): { [EntityId]: number }
	local out: { [EntityId]: number } = table.clone(state.banked)
	for _, base in state.bases do
		for _, track in base.tracks do
			if not track.banked then
				for _, id in track.capperIds do
					local pts = track.cappers[id].points
					if pts > 0 then
						out[id] = (out[id] or 0) + pts
					end
				end
			end
		end
	end
	return out
end

--- Defense points per participant (points reset by hitting cappers). Fresh table.
function Capture.defensePoints(state: CaptureState): { [EntityId]: number }
	return table.clone(state.defense)
end

--- HUD / replication view: one row per (base, capturing team), ascending. Rows are appended to `out` (cleared).
function Capture.snapshot(state: CaptureState, out: { BaseSnapshot }?): { BaseSnapshot }
	local rows = out or {}
	table.clear(rows)
	for _, base in state.bases do
		for _, track in base.tracks do
			table.insert(rows, {
				base = base.id,
				team = track.team,
				progress = track.progress,
				frozen = track.frozen,
				contested = track.contested,
				cappers = #track.inside,
				capturedBy = base.capturedBy,
			})
		end
	end
	return rows
end

return Capture
