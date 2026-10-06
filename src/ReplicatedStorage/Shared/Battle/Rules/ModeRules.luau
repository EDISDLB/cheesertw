--!strict
--[[
	Battle/Rules/ModeRules — resolves the rule set of ONE battle (timers, objectives, capture, connection/AFK) for a
	mode + battle type from Config.Battle, once, at battle creation (00-DECISIONS §9, §19 "Live config: one snapshot
	per battle").

	Purpose:          Phases, Capture, Outcome and Connection all read a ModeSettings value instead of Config, so a
	                  live override applied mid-battle never changes a running battle and specs can build rule sets
	                  without touching Config.
	Dependencies:     Config (Battle), Core/Freeze, Core/Result, Net/ErrorCodes, Types/Battle (types only).
	State:            None (every call returns a fresh deep-frozen table).
	Validation:       Unknown mode / battle type and non-finite or non-positive duration overrides are rejected
	                  (INVALID_ARGS). Config numbers that are not finite fall back to safe defaults; cross-key rules
	                  are enforced here: AFK warning ≤ takeover, countdown/banner ≥ 0, capture points ≥ 1.
	Error handling:   resolve() returns a Result; defaults() raises on invalid input (tests / trusted callers only).
	Performance notes: Called once per battle; a few dozen table reads.

	Precedence for numeric keys: options.durationS (event mode) > Config.Battle.MODES[mode].KEY > TIMER_S[battleType]
	(duration only) > Config.Battle.KEY. Mode flags default to true when absent.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type BattleMode = BattleTypes.BattleMode
type BattleType = BattleTypes.BattleType
type Result<T> = Result.Result<T>

export type TimeoutResult = "Draw" | "DefenderWin"
export type WipeAndCaptureReason = "Capture" | "Destruction"

export type CaptureSettings = {
	points: number, -- points to capture (100)
	radiusM: number, -- default radius when the map base has none
	maxCounted: number, -- vehicles that add speed (3)
	rate: number, -- points per second per vehicle for this battle type
	contestedFreezes: boolean, -- enemy presence freezes the base (Encounter)
	resetOnHpDamage: boolean,
	resetOnModuleCrit: boolean,
	resetOnStun: boolean,
	leaveGraceS: number,
	progressEventStep: number,
}

export type ModeSettings = {
	mode: BattleMode,
	battleType: BattleType,
	-- lifecycle (seconds)
	durationS: number,
	countdownS: number,
	loadTimeoutS: number,
	arrivalWindowS: number,
	prepareTimeoutS: number,
	endBannerS: number,
	resultsTimeoutS: number,
	minHumans: number,
	earlyStart: boolean,
	-- objectives
	wipeVictory: boolean,
	captureEnabled: boolean,
	timeoutResult: TimeoutResult,
	wipeAndCaptureReason: WipeAndCaptureReason,
	capture: CaptureSettings,
	-- connection / AFK
	botTakeover: boolean,
	disconnectBotDelayS: number,
	afkEnabled: boolean,
	afkWarnS: number,
	afkTakeoverS: number,
	-- ledger
	assistSpotWindowS: number,
	firstContactWindowS: number,
	fallCreditWindowS: number,
	wheeledTrackAssist: boolean,
}

export type ResolveOptions = {
	--- Event modes: EventModeDefinition.durationS replaces the battle-type timer.
	durationS: number?,
}

local MODES: { BattleMode } = { "Random", "Training", "Bootcamp", "Practice", "Event" }
local BATTLE_TYPES: { BattleType } = { "Standard", "Encounter", "Assault" }

local ModeRules = {}

ModeRules.MODES = table.freeze(table.clone(MODES))
ModeRules.BATTLE_TYPES = table.freeze(table.clone(BATTLE_TYPES))

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A finite number >= min, or the fallback.
local function num(value: any, fallback: number, min: number): number
	if isFiniteNumber(value) and value >= min then
		return value
	end
	return fallback
end

local function flag(value: any, default: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return default
end

-- Mode override of a top-level key, else the top-level value.
local function pick(modeTable: { [string]: any }, battle: { [string]: any }, key: string): any
	local value = modeTable[key]
	if value ~= nil then
		return value
	end
	return battle[key]
end

--- Resolves the rules of one battle. `battleType` defaults to "Standard" (non-Random modes may omit it).
function ModeRules.resolve(mode: string, battleType: string?, options: ResolveOptions?): Result<ModeSettings>
	if type(mode) ~= "string" or table.find(MODES, mode :: any) == nil then
		return Result.err(ErrorCodes.INVALID_ARGS, `unknown battle mode {tostring(mode)}`)
	end
	local bt: string = if battleType == nil then "Standard" else battleType
	if type(bt) ~= "string" or table.find(BATTLE_TYPES, bt :: any) == nil then
		return Result.err(ErrorCodes.INVALID_ARGS, `unknown battle type {tostring(battleType)}`)
	end
	local overrideDuration = if options then options.durationS else nil
	if overrideDuration ~= nil and not (isFiniteNumber(overrideDuration) and overrideDuration > 0) then
		return Result.err(ErrorCodes.INVALID_ARGS, `durationS must be a positive finite number`)
	end

	local B = Config.Battle :: any
	local modeTable: { [string]: any } = (B.MODES and B.MODES[mode]) or {}
	local timers: { [string]: any } = B.TIMER_S or {}
	local cap: { [string]: any } = B.CAPTURE or {}
	local ledger: { [string]: any } = B.LEDGER or {}
	local capRates: { [string]: any } = cap.RATE or {}
	local capFreezes: { [string]: any } = cap.CONTESTED_FREEZES or {}
	local timeoutResults: { [string]: any } = B.TIMEOUT_RESULT or {}

	local duration: number
	if overrideDuration ~= nil then
		duration = overrideDuration
	elseif modeTable.DURATION_S ~= nil then
		duration = num(modeTable.DURATION_S, 720, 1)
	elseif timers[bt] ~= nil then
		duration = num(timers[bt], 720, 1)
	else
		duration = num(B.DURATION_S, 720, 1)
	end

	local timeoutResult: TimeoutResult = if timeoutResults[bt] == "DefenderWin" then "DefenderWin" else "Draw"
	local wipeAndCapture: WipeAndCaptureReason = if B.SAME_TICK_WIPE_AND_CAPTURE_REASON == "Destruction"
		then "Destruction"
		else "Capture"

	local afkTakeover = num(pick(modeTable, B, "AFK_TAKEOVER_S"), 90, 1)
	local afkWarn = math.min(num(pick(modeTable, B, "AFK_WARN_S"), 60, 0), afkTakeover)

	local settings: ModeSettings = {
		mode = mode :: BattleMode,
		battleType = bt :: BattleType,
		durationS = duration,
		countdownS = num(pick(modeTable, B, "COUNTDOWN_S"), 20, 0),
		loadTimeoutS = num(pick(modeTable, B, "LOAD_TIMEOUT_S"), 30, 0),
		arrivalWindowS = num(pick(modeTable, B, "ARRIVAL_WINDOW_S"), 45, 0),
		prepareTimeoutS = num(pick(modeTable, B, "PREPARE_TIMEOUT_S"), 90, 1),
		endBannerS = num(pick(modeTable, B, "END_BANNER_S"), 6, 0),
		resultsTimeoutS = num(pick(modeTable, B, "RESULTS_TIMEOUT_S"), 60, 0),
		minHumans = math.floor(num(pick(modeTable, B, "MIN_HUMANS"), 1, 0)),
		earlyStart = flag(modeTable.EARLY_START, true),
		wipeVictory = flag(modeTable.WIPE_VICTORY, true),
		captureEnabled = flag(modeTable.CAPTURE, true),
		timeoutResult = timeoutResult,
		wipeAndCaptureReason = wipeAndCapture,
		capture = {
			points = num(cap.POINTS, 100, 1),
			radiusM = num(cap.RADIUS_M, 50, 0.1),
			maxCounted = math.max(1, math.floor(num(cap.MAX_COUNTED, 3, 1))),
			rate = num(capRates[bt], 1, 0),
			contestedFreezes = flag(capFreezes[bt], bt == "Encounter"),
			resetOnHpDamage = flag(cap.RESET_ON_HP_DAMAGE, true),
			resetOnModuleCrit = flag(cap.RESET_ON_MODULE_CRIT, true),
			resetOnStun = flag(cap.RESET_ON_STUN, false),
			leaveGraceS = num(cap.LEAVE_GRACE_S, 1, 0),
			progressEventStep = math.max(1, num(cap.PROGRESS_EVENT_STEP, 5, 1)),
		},
		botTakeover = flag(modeTable.BOT_TAKEOVER, true),
		disconnectBotDelayS = num(pick(modeTable, B, "DISCONNECT_BOT_DELAY_S"), 5, 0),
		afkEnabled = flag(modeTable.AFK, true),
		afkWarnS = afkWarn,
		afkTakeoverS = afkTakeover,
		assistSpotWindowS = num(ledger.ASSIST_SPOT_WINDOW_S, 10, 0),
		firstContactWindowS = num(ledger.FIRST_CONTACT_WINDOW_S, 180, 0),
		fallCreditWindowS = num(ledger.FALL_CREDIT_WINDOW_S, 5, 0),
		wheeledTrackAssist = flag(ledger.WHEELED_TRACK_ASSIST, false),
	}
	return Result.ok(Freeze.deep(settings))
end

--- resolve() that raises on invalid input. For specs and callers whose inputs are already validated.
function ModeRules.defaults(mode: string, battleType: string?, options: ResolveOptions?): ModeSettings
	return Result.unwrap(ModeRules.resolve(mode, battleType, options))
end

--- A copy of `settings` with fields replaced (specs and event tooling). The copy is deep-frozen; nested `capture`
--- fields are merged, not replaced.
function ModeRules.with(settings: ModeSettings, patch: { [string]: any }): ModeSettings
	local copy: { [string]: any } = table.clone(settings :: any)
	local capture: { [string]: any } = table.clone(settings.capture :: any)
	for key, value in patch do
		if key == "capture" and type(value) == "table" then
			for capKey, capValue in value do
				capture[capKey] = capValue
			end
		else
			copy[key] = value
		end
	end
	copy.capture = capture
	return Freeze.deep(copy :: any) :: ModeSettings
end

return ModeRules
