--!strict
--[[
	Battle/Rules/Outcome — victory / defeat / draw evaluation (00-DECISIONS §9 "Victory"; REG-BTL-02, REG-BTL-07).

	Purpose:          Called by BattleInstance once per tick in the Objectives step, AFTER every damage event of the
	                  tick has been applied and after Capture.step, so simultaneous last kills and same-tick captures
	                  are seen together. Returns the BattleOutcome that ends the battle, or nil to keep playing.
	Dependencies:     Rules/ModeRules (types), Types/Battle (types only).
	State:            None (pure functions; results are fresh tables).
	Validation:       Teams with no vehicles at all can never be "wiped" (solo Practice, empty bot team). Duplicate
	                  team ids in `captured` are ignored. Unknown teams in `captured` still count as claims.
	Error handling:   No throws.
	Performance notes: O(teams) per call; allocates only when a result is produced.

	Rules (priority order):
	  1. Wipe (settings.wipeVictory): a team whose roster is non-empty and has 0 alive is wiped. Every non-empty team
	     wiped on the same tick → draw "Simultaneous" (one non-empty team only → draw "Destruction").
	  2. The remaining non-wiped team (when all others are wiped) claims "Destruction"; every team in `captured`
	     (settings.captureEnabled) claims "Capture". Two or more different claimants → draw "Simultaneous" (double
	     capture, or one side capturing while being wiped). One claimant → its victory; if it claimed both, the
	     reason is settings.wipeAndCaptureReason.
	  3. Time up: timeoutResult "DefenderWin" with a defender → defender victory "DefenderHeld"; otherwise draw
	     "Timeout". Wipes and captures on the final tick win over the timeout (hits resolved on the end tick count).
]]

local ModeRules = require("./ModeRules")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type ModeSettings = ModeRules.ModeSettings
type TeamId = BattleTypes.TeamId
type BattleOutcome = BattleTypes.BattleOutcome
type BattleOutcomeKind = BattleTypes.BattleOutcomeKind
type BattleEndReason = BattleTypes.BattleEndReason
type TeamOutcome = BattleTypes.TeamOutcome

export type OutcomeInput = {
	settings: ModeSettings,
	teams: { TeamId }, -- every team of the battle (any order; outcomes are listed ascending)
	rosterByTeam: { [TeamId]: number }, -- vehicles each team started with
	aliveByTeam: { [TeamId]: number }, -- vehicles alive after every damage event of this tick
	captured: { TeamId }?, -- teams that completed a capture on this tick (Capture.step)
	timeUp: boolean, -- Phases.isTimeUp
	defender: TeamId?, -- Assault: the defending team (Capture.defenderTeam)
}

local Outcome = {}

local function sortedTeams(teams: { TeamId }): { TeamId }
	local list: { TeamId } = {}
	for _, team in teams do
		if table.find(list, team) == nil then
			table.insert(list, team)
		end
	end
	table.sort(list)
	return list
end

--- Builds an outcome: `winner` gets Victory and every other team Defeat; nil winner = Draw for everyone.
function Outcome.make(winner: TeamId?, reason: BattleEndReason, teams: { TeamId }): BattleOutcome
	local list = sortedTeams(teams)
	local rows: { TeamOutcome } = {}
	for _, team in list do
		local kind: BattleOutcomeKind = if winner == nil then "Draw" elseif team == winner then "Victory" else "Defeat"
		table.insert(rows, { team = team, outcome = kind })
	end
	return { winner = winner, reason = reason, teams = rows }
end

--- Draw for every team with `reason`.
function Outcome.draw(reason: BattleEndReason, teams: { TeamId }): BattleOutcome
	return Outcome.make(nil, reason, teams)
end

--- Server-failure / abort outcome: no win or loss is recorded (reason "Aborted", every team Draw).
function Outcome.aborted(teams: { TeamId }): BattleOutcome
	return Outcome.make(nil, "Aborted", teams)
end

--- The result kind of `team` (Draw when the team is not listed).
function Outcome.resultFor(outcome: BattleOutcome, team: TeamId): BattleOutcomeKind
	for _, row in outcome.teams do
		if row.team == team then
			return row.outcome
		end
	end
	return "Draw"
end

--- True when `team` won.
function Outcome.isWin(outcome: BattleOutcome, team: TeamId): boolean
	return outcome.winner ~= nil and outcome.winner == team
end

--- The outcome a timeout produces for these settings (draw, or the Assault defender's "DefenderHeld" win).
function Outcome.timeout(settings: ModeSettings, teams: { TeamId }, defender: TeamId?): BattleOutcome
	if settings.timeoutResult == "DefenderWin" and defender ~= nil and table.find(teams, defender) ~= nil then
		return Outcome.make(defender, "DefenderHeld", teams)
	end
	return Outcome.draw("Timeout", teams)
end

--- Evaluates the end conditions of this tick. nil = the battle continues.
function Outcome.evaluate(input: OutcomeInput): BattleOutcome?
	local settings = input.settings
	local teams = sortedTeams(input.teams)

	local destructionWinner: TeamId? = nil
	if settings.wipeVictory then
		local nonEmpty, wiped = 0, 0
		local survivor: TeamId? = nil
		local survivors = 0
		for _, team in teams do
			local roster = input.rosterByTeam[team] or 0
			if roster > 0 then
				nonEmpty += 1
				if (input.aliveByTeam[team] or 0) <= 0 then
					wiped += 1
				else
					survivors += 1
					survivor = team
				end
			end
		end
		if wiped > 0 and survivors == 0 then
			return Outcome.draw(if nonEmpty >= 2 then "Simultaneous" else "Destruction", teams)
		end
		if wiped > 0 and survivors == 1 then
			destructionWinner = survivor
		end
	end

	local claimants: { TeamId } = {}
	local byCapture: { [TeamId]: boolean } = {}
	if destructionWinner ~= nil then
		table.insert(claimants, destructionWinner)
	end
	if settings.captureEnabled and input.captured ~= nil then
		for _, team in input.captured do
			byCapture[team] = true
			if table.find(claimants, team) == nil then
				table.insert(claimants, team)
			end
		end
	end
	if #claimants >= 2 then
		return Outcome.draw("Simultaneous", teams)
	elseif #claimants == 1 then
		local winner = claimants[1]
		local reason: BattleEndReason
		if byCapture[winner] and destructionWinner == winner then
			reason = settings.wipeAndCaptureReason
		elseif byCapture[winner] then
			reason = "Capture"
		else
			reason = "Destruction"
		end
		local allTeams = teams
		if table.find(allTeams, winner) == nil then
			allTeams = sortedTeams({ winner, table.unpack(teams) })
		end
		return Outcome.make(winner, reason, allTeams)
	end

	if input.timeUp then
		return Outcome.timeout(settings, teams, input.defender)
	end
	return nil
end

return Outcome
