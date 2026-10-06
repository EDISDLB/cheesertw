--!strict
--[[
	Combat/DamageModel — a vehicle's combat state (HP, modules, crew, fire, stun, drowning, destruction) and every
	way it changes: shot outcomes and splash, module thresholds, fire start / DoT / extinguish, ammo-rack
	detonation, crew injuries, field repair timers, repair-kit / medkit / extinguisher hooks, ramming, falls and
	drowning; plus the runtime effect multipliers the owning systems apply on top of VehicleStats.

	Purpose:          Authoritative state transitions for BattleInstance (00-DECISIONS §2). ShotResolver computes a
	                  hit; apply() decides its consequences against the CURRENT state (so two shells resolved in the
	                  same tick apply in order and the second sees the first's result).
	Dependencies:     Config (Combat), Core/RNG (type), Combat/Fire, Combat/CrewEffects, Types/Content,
	                  Types/Vehicle, Types/Combat, Types/Battle.
	State:            VehicleCombatState records (one per vehicle, owned by the caller). No module state.
	Validation:       0 <= hp <= maxHp and module hp in [0, maxHp] always hold; damage is clamped to the remaining
	                  HP (the ledger sums to HP lost); non-finite or negative damage counts as 0; a destroyed vehicle
	                  ignores everything (no overkill, no fire ticks, no repairs); ram/fall contact ids apply once.
	Error handling:   No throws on numeric input; unknown module kinds in hits are ignored.
	Performance notes: apply/update iterate fixed small lists (<= 8 modules, <= 6 crew). Events are appended to a
	                  caller-owned array only when something changes (fire DoT emits one Damage event per tick).

	RNG draws (deterministic, injected): apply() — one fire roll per Engine hit, in hit order; update() — one crew
	roll per fire tick (+ one pick when it hits); applyRam() — track roll (+ side pick when no side is given);
	applyFall() — track roll (+ side pick).
	Tick usage: call consumable hooks (extinguish / useRepairKit / useMedkit) before update() in a tick so an
	extinguished fire deals no damage that tick (REG-ARM-09).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNGModule = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fire = require("./Fire")
local CrewEffects = require("./CrewEffects")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type RNG = RNGModule.RNG
type InternalModuleKind = ContentTypes.InternalModuleKind
type DamageKind = BattleTypes.DamageKind
type AttackerId = CombatTypes.AttackerId
type VehicleCombatState = CombatTypes.VehicleCombatState
type ModuleCombatState = CombatTypes.ModuleCombatState
type CrewCombatState = CombatTypes.CrewCombatState
type DamageModelInit = CombatTypes.DamageModelInit
type ShotOutcome = CombatTypes.ShotOutcome
type SplashHit = CombatTypes.SplashHit
type CombatEvent = CombatTypes.CombatEvent
type EffectMultipliers = CombatTypes.EffectMultipliers
type RamParty = CombatTypes.RamParty
type FireReason = CombatTypes.FireReason
type ModuleState = VehicleTypes.ModuleState

local DamageModel = {}

--- Re-exported for StatsCalculator / GunState (crew curves and the crew-injury effects table).
DamageModel.CrewEffects = CrewEffects
DamageModel.INJURY_EFFECTS = CrewEffects.INJURY_EFFECTS

local MODULE_KINDS: { InternalModuleKind } = {
	"Engine",
	"AmmoRack",
	"FuelTank",
	"Gun",
	"TurretRing",
	"Optics",
	"TrackLeft",
	"TrackRight",
}
local FUEL_TANK: InternalModuleKind = "FuelTank"
--- Module kinds in deterministic iteration order.
DamageModel.MODULE_KINDS = table.freeze(MODULE_KINDS)

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function wholeHp(x: number): number
	if not (x > 0) or not isFinite(x) then
		return 0
	end
	return math.floor(x + 0.5)
end

local function emit(events: { CombatEvent }?, event: CombatEvent)
	if events ~= nil then
		table.insert(events, event)
	end
end

--------------------------------------------------------------------------------
-- Construction and authoring helpers
--------------------------------------------------------------------------------

--- Module max HP = MODULE_HP_K[kind] × the tier's moduleHpRefAlpha (StatsCalculator helper).
function DamageModel.moduleHpFor(kind: InternalModuleKind, tierRefAlpha: number): number
	local k = (Config.Combat.MODULE_HP_K :: any)[kind]
	return wholeHp((if type(k) == "number" then k else 1) * tierRefAlpha)
end

--- Crew member max HP = CREW_HP_K × the tier's moduleHpRefAlpha.
function DamageModel.crewHpFor(tierRefAlpha: number): number
	return wholeHp(Config.Combat.CREW_HP_K * tierRefAlpha)
end

--- A fresh combat state from VehicleStats (or any DamageModelInit). `opts.ammoStored` = shells in the rack at
--- spawn (default 1, so a destroyed rack detonates unless GunState reports an empty rack).
function DamageModel.new(
	init: DamageModelInit,
	opts: { ammoStored: number?, autoExtinguisher: boolean? }?
): VehicleCombatState
	local C = Config.Combat
	local hp = math.max(0, if isFinite(init.hp) then init.hp else 0)
	local modules: { [InternalModuleKind]: ModuleCombatState } = {}
	local order: { InternalModuleKind } = {}
	for _, kind: InternalModuleKind in MODULE_KINDS do
		local spec = init.modules[kind]
		if spec ~= nil then
			local maxHp = math.max(0, if isFinite(spec.maxHp) then spec.maxHp else 0)
			modules[kind] = {
				kind = kind,
				hp = maxHp,
				maxHp = maxHp,
				state = "Ok",
				repairS = math.max(0, if isFinite(spec.repairS) then spec.repairS else 0),
				repairRemainingS = 0,
			}
			table.insert(order, kind)
		end
	end
	local crew: { CrewCombatState } = {}
	for _, seat in init.crew do
		table.insert(crew, {
			slot = seat.slot,
			role = seat.role,
			also = table.clone(seat.also or {}),
			level = seat.level,
			hp = seat.maxHp,
			maxHp = seat.maxHp,
			injured = false,
		})
	end
	local ammoStored = if opts ~= nil then opts.ammoStored else nil
	local autoExtinguisher = if opts ~= nil then opts.autoExtinguisher else nil
	return {
		hp = hp,
		maxHp = hp,
		destroyed = false,
		cause = nil,
		killer = nil,
		modules = modules,
		moduleOrder = order,
		crew = crew,
		crewLevels = table.clone(init.crewLevels or {}),
		fire = Fire.newState(),
		stunRemainingS = 0,
		stunAttacker = nil,
		drownS = 0,
		ammoStored = ammoStored or 1,
		autoExtinguisher = autoExtinguisher == true,
		fireChance = if isFinite(init.fireChance) then init.fireChance else C.FIRE_CHANCE_DEFAULT,
		fireDurationS = if isFinite(init.fireDurationS) and init.fireDurationS > 0
			then init.fireDurationS
			else C.FIRE_DURATION_S,
		spallFactor = if isFinite(init.spallFactor) and init.spallFactor > 0
			then init.spallFactor
			else C.SPALL_FACTOR_BASE,
		crewInjuryChanceMul = if isFinite(init.crewInjuryChanceMul) then init.crewInjuryChanceMul else 1,
		stunDurationMul = if isFinite(init.stunDurationMul) then init.stunDurationMul else 1,
		ramDamageDealtMul = if isFinite(init.ramDamageDealtMul) then init.ramDamageDealtMul else 1,
		ramDamageTakenMul = if isFinite(init.ramDamageTakenMul) then init.ramDamageTakenMul else 1,
		fallDamageMul = if isFinite(init.fallDamageMul) then init.fallDamageMul else 1,
		massKg = if isFinite(init.massKg) then init.massKg else 0,
		wheeled = init.wheeled ~= nil,
		contacts = {},
		contactRing = {},
		contactNext = 1,
	}
end

--- Keeps the stored-shell count in sync with GunState (ammo-rack detonation needs >= AMMO_RACK_DETONATION_MIN_SHELLS).
function DamageModel.setAmmoStored(state: VehicleCombatState, shells: number)
	state.ammoStored = if isFinite(shells) and shells > 0 then shells else 0
end

--------------------------------------------------------------------------------
-- Primitive transitions
--------------------------------------------------------------------------------

local function destroy(state: VehicleCombatState, cause: DamageKind, attacker: AttackerId?, events: { CombatEvent }?)
	if state.destroyed then
		return
	end
	state.destroyed = true
	state.hp = 0
	state.cause = cause
	state.killer = attacker
	if Fire.extinguish(state.fire) then
		emit(events, { type = "Fire", burning = false, reason = "Destroyed", attacker = nil })
	end
	state.stunRemainingS = 0
	emit(events, { type = "Destroyed", cause = cause, attacker = attacker })
end

--- Removes up to `amount` HP (whole, clamped to what remains); destroys at 0. Returns the HP removed.
function DamageModel.applyDamage(
	state: VehicleCombatState,
	kind: DamageKind,
	amount: number,
	attacker: AttackerId?,
	events: { CombatEvent }?
): number
	if state.destroyed then
		return 0
	end
	local removed = math.min(wholeHp(amount), state.hp)
	if removed <= 0 then
		return 0
	end
	state.hp -= removed
	emit(events, { type = "Damage", kind = kind, damage = removed, attacker = attacker })
	if state.hp <= 0 then
		destroy(state, kind, attacker, events)
	end
	return removed
end

local function stateFor(m: ModuleCombatState): ModuleState
	if m.hp <= 0 then
		return "Destroyed"
	elseif m.hp <= Config.Combat.MODULE_DAMAGED_FRACTION * m.maxHp then
		return "Damaged"
	end
	return "Ok"
end

--- Damages one module (capped at MODULE_DAMAGE_CAP_MUL × maxHp per hit). Returns (old state, new state) or nil
--- when the vehicle has no such module / is destroyed.
function DamageModel.damageModule(
	state: VehicleCombatState,
	kind: InternalModuleKind,
	damage: number,
	attacker: AttackerId?,
	events: { CombatEvent }?
): (string?, string?)
	local m = state.modules[kind]
	if m == nil or state.destroyed then
		return nil, nil
	end
	local before = m.state
	local amount = math.min(wholeHp(damage), wholeHp(Config.Combat.MODULE_DAMAGE_CAP_MUL * m.maxHp))
	if amount <= 0 or m.hp <= 0 then
		return before, before
	end
	m.hp = math.max(0, m.hp - amount)
	local after: ModuleState = stateFor(m)
	m.state = after
	if after ~= before then
		if after == "Destroyed" then
			m.repairRemainingS = math.max(m.repairS, 1e-6)
		end
		emit(events, { type = "ModuleState", module = kind, state = after, attacker = attacker })
	end
	return before, after
end

--- Damages one crew member (by slot); 0 HP = injured (never killed). Returns true when this injured them.
function DamageModel.damageCrew(
	state: VehicleCombatState,
	slot: number,
	damage: number,
	attacker: AttackerId?,
	events: { CombatEvent }?
): boolean
	if state.destroyed then
		return false
	end
	for _, member in state.crew do
		if member.slot == slot then
			if member.injured then
				return false
			end
			member.hp = math.max(0, member.hp - wholeHp(damage))
			if member.hp <= 0 then
				member.injured = true
				emit(events, { type = "CrewInjured", slot = slot, role = member.role, attacker = attacker })
				return true
			end
			return false
		end
	end
	return false
end

local function ignite(state: VehicleCombatState, attacker: AttackerId?, events: { CombatEvent }?): boolean
	if state.destroyed then
		return false
	end
	if Fire.ignite(state.fire, state.fireDurationS, attacker) then
		emit(events, { type = "Fire", burning = true, reason = "Ignited", attacker = attacker })
		return true
	end
	return false
end

--- Sets the vehicle on fire (credited to `attacker`). Returns true when it was not burning already.
function DamageModel.ignite(state: VehicleCombatState, attacker: AttackerId?, events: { CombatEvent }?): boolean
	return ignite(state, attacker, events)
end

local function extinguish(state: VehicleCombatState, reason: FireReason, events: { CombatEvent }?): boolean
	if Fire.extinguish(state.fire) then
		emit(events, { type = "Fire", burning = false, reason = reason, attacker = nil })
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Shots and splash
--------------------------------------------------------------------------------

-- Module + crew records of a hit, then fire / detonation decisions. Returns true when the ammo rack detonates.
local function applyHitRecords(
	state: VehicleCombatState,
	modulesHit: { CombatTypes.ModuleHitRecord },
	crewHit: { CombatTypes.CrewHitRecord }?,
	rng: RNG,
	attacker: AttackerId?,
	events: { CombatEvent }?,
	rollFire: boolean
): (boolean, boolean)
	local C = Config.Combat
	local detonate = false
	local fireStarted = false
	for _, hit in modulesHit do
		local kind: InternalModuleKind = hit.kind
		if state.modules[kind] == nil then
			continue
		end
		local before, after = DamageModel.damageModule(state, kind, hit.damage, attacker, events)
		if rollFire and kind == "Engine" then
			local fuel = state.modules[FUEL_TANK]
			local chance = Fire.engineHitChance(state.fireChance, if fuel ~= nil then fuel.state else nil)
			if rng:chance(chance) and ignite(state, attacker, events) then
				fireStarted = true
			end
		end
		if after == "Destroyed" and before ~= "Destroyed" then
			if kind == "FuelTank" and ignite(state, attacker, events) then
				fireStarted = true
			elseif kind == "AmmoRack" and state.ammoStored >= C.AMMO_RACK_DETONATION_MIN_SHELLS then
				detonate = true
			end
		end
	end
	if crewHit ~= nil then
		for _, hit in crewHit do
			DamageModel.damageCrew(state, hit.slot, hit.damage, attacker, events)
		end
	end
	return detonate, fireStarted
end

--- Applies a ShotResolver outcome to the target's state and fills outcome.fireStarted / ammoRackDetonation /
--- damageApplied / killed. Order: modules (engine fire rolls, fuel fire, rack detonation) -> crew -> HP. A
--- destroyed target, a no-op or a Miss changes nothing. Returns the HP removed.
function DamageModel.apply(
	state: VehicleCombatState,
	outcome: ShotOutcome,
	rng: RNG,
	attacker: AttackerId?,
	events: { CombatEvent }?
): number
	outcome.fireStarted = false
	outcome.ammoRackDetonation = false
	outcome.damageApplied = 0
	outcome.killed = false
	if state.destroyed or outcome.noop or outcome.result == "Miss" then
		return 0
	end
	local detonate, fireStarted =
		applyHitRecords(state, outcome.modulesHit, outcome.crewHit, rng, attacker, events, true)
	local removed
	if detonate then
		removed = state.hp
		if removed > 0 then
			emit(events, { type = "Damage", kind = "AmmoRack", damage = removed, attacker = attacker })
		end
		destroy(state, "AmmoRack", attacker, events)
	else
		removed = DamageModel.applyDamage(state, "Shell", outcome.damage, attacker, events)
	end
	outcome.ammoRackDetonation = detonate
	outcome.fireStarted = fireStarted and not state.destroyed
	outcome.damageApplied = removed
	outcome.killed = state.destroyed
	return removed
end

--- Applies one SplashHit (HP, external modules, stun). Splash never rolls engine fires. Returns the HP removed.
function DamageModel.applySplash(
	state: VehicleCombatState,
	hit: SplashHit,
	rng: RNG,
	attacker: AttackerId?,
	events: { CombatEvent }?
): number
	if state.destroyed then
		return 0
	end
	local detonate = applyHitRecords(state, hit.modulesHit, nil, rng, attacker, events, false)
	if detonate then
		local removed = state.hp
		emit(events, { type = "Damage", kind = "AmmoRack", damage = removed, attacker = attacker })
		destroy(state, "AmmoRack", attacker, events)
		return removed
	end
	if hit.stunS > 0 then
		DamageModel.applyStun(state, hit.stunS, attacker, events)
	end
	return DamageModel.applyDamage(state, "Splash", hit.damage, attacker, events)
end

--- Stuns the vehicle for `durationS` (already scaled by the target's stunDurationMul); a longer stun replaces a
--- shorter one.
function DamageModel.applyStun(
	state: VehicleCombatState,
	durationS: number,
	attacker: AttackerId?,
	events: { CombatEvent }?
)
	if state.destroyed or not (durationS > 0) or durationS == math.huge then
		return
	end
	if durationS > state.stunRemainingS then
		state.stunRemainingS = durationS
		state.stunAttacker = attacker
		emit(events, { type = "Stunned", durationS = durationS, attacker = attacker })
	end
end

--------------------------------------------------------------------------------
-- Time: fire, repairs, stun
--------------------------------------------------------------------------------

local crewScratch: CrewEffects.CrewMultipliers = {
	reloadTime = 1,
	aimTime = 1,
	dispersion = 1,
	turretTraverse = 1,
	hullTraverse = 1,
	viewRange = 1,
	repairTime = 1,
	sixthSense = true,
}

local FIRE_BAY: { InternalModuleKind } = { "Engine", "FuelTank" }
local TRACK_SIDES: { InternalModuleKind } = { "TrackLeft", "TrackRight" }

--- Advances fire (DoT credited to the igniter, engine-bay module and crew damage, Automatic Extinguisher), field
--- repairs (Destroyed -> Damaged at REPAIR_RESTORE_FRACTION after repairS × driver-injury ratio) and stun.
--- Returns the HP lost to fire during this call.
function DamageModel.update(state: VehicleCombatState, dt: number, rng: RNG, events: { CombatEvent }?): number
	if state.destroyed or not (dt > 0) or dt == math.huge then
		return 0
	end
	local C = Config.Combat
	local lost = 0
	local fire = state.fire
	if fire.burning then
		local burnDt = dt
		local auto = false
		if state.autoExtinguisher then
			local untilAuto = C.AUTO_EXTINGUISHER_DELAY_S - fire.elapsedS
			if untilAuto <= dt then
				burnDt = math.max(0, untilAuto)
				auto = true
			end
		end
		local hp, ticks, burnedOut = Fire.tick(fire, burnDt, state.maxHp)
		local igniter = fire.igniter
		for _ = 1, ticks do
			if state.destroyed then
				break
			end
			for _, kind: InternalModuleKind in FIRE_BAY do
				local m = state.modules[kind]
				if m ~= nil then
					DamageModel.damageModule(
						state,
						kind,
						C.FIRE_MODULE_DAMAGE_PER_S * C.FIRE_TICK_S * m.maxHp,
						igniter,
						events
					)
				end
			end
			if #state.crew > 0 and rng:chance(C.FIRE_CREW_HIT_CHANCE) then
				local candidates = {}
				for _, member in state.crew do
					if not member.injured then
						table.insert(candidates, member)
					end
				end
				if #candidates > 0 then
					local member = candidates[rng:int(1, #candidates)]
					DamageModel.damageCrew(
						state,
						member.slot,
						C.FIRE_CREW_DAMAGE_FRACTION * member.maxHp,
						igniter,
						events
					)
				end
			end
		end
		if hp > 0 then
			lost += DamageModel.applyDamage(state, "Fire", hp, igniter, events)
		end
		if not state.destroyed then
			if burnedOut then
				emit(events, { type = "Fire", burning = false, reason = "BurnedOut", attacker = nil })
			elseif auto and fire.burning then
				extinguish(state, "AutoExtinguisher", events)
				state.autoExtinguisher = false
			end
		end
	end
	if state.destroyed then
		return lost
	end

	-- Field repair (driver injury slows it).
	local repairMul = 1
	for _, member in state.crew do
		if member.injured then
			repairMul = CrewEffects.multipliers(state.crew, state.crewLevels, crewScratch).repairTime
			break
		end
	end
	for _, kind: InternalModuleKind in state.moduleOrder do
		local m = state.modules[kind]
		if m.state == "Destroyed" and m.repairRemainingS > 0 then
			m.repairRemainingS -= dt / repairMul
			if m.repairRemainingS <= 0 then
				m.repairRemainingS = 0
				m.hp = math.max(1, wholeHp(C.REPAIR_RESTORE_FRACTION * m.maxHp))
				m.state = stateFor(m)
				emit(events, { type = "ModuleState", module = kind, state = m.state, attacker = nil })
			end
		end
	end

	if state.stunRemainingS > 0 then
		state.stunRemainingS = math.max(0, state.stunRemainingS - dt)
		if state.stunRemainingS == 0 then
			state.stunAttacker = nil
		end
	end
	return lost
end

--------------------------------------------------------------------------------
-- Consumable hooks
--------------------------------------------------------------------------------

--- Fire Extinguisher: puts the fire out now. Returns true when a fire was burning.
function DamageModel.extinguish(state: VehicleCombatState, events: { CombatEvent }?): boolean
	if state.destroyed then
		return false
	end
	return extinguish(state, "Extinguished", events)
end

--- Arms / disarms the Automatic Extinguisher (it fires AUTO_EXTINGUISHER_DELAY_S after ignition, then disarms;
--- the consumable system re-arms it after its cooldown).
function DamageModel.armAutoExtinguisher(state: VehicleCombatState, armed: boolean)
	state.autoExtinguisher = armed
end

--- Repair Kit: every module back to full HP and Ok, field repairs cancelled. Returns true when anything changed.
function DamageModel.useRepairKit(state: VehicleCombatState, events: { CombatEvent }?): boolean
	if state.destroyed then
		return false
	end
	local changed = false
	for _, kind: InternalModuleKind in state.moduleOrder do
		local m = state.modules[kind]
		local wasOk = m.state == "Ok"
		if m.hp < m.maxHp or not wasOk then
			changed = true
			m.hp = m.maxHp
			m.state = "Ok"
			m.repairRemainingS = 0
			if not wasOk then
				emit(events, { type = "ModuleState", module = kind, state = "Ok", attacker = nil })
			end
		end
	end
	return changed
end

--- Medkit: heals every crew member (injury cleared, full HP) and clears stun. Returns true when anything changed.
function DamageModel.useMedkit(state: VehicleCombatState, events: { CombatEvent }?): boolean
	if state.destroyed then
		return false
	end
	local changed = false
	for _, member in state.crew do
		if member.injured or member.hp < member.maxHp then
			changed = true
			local wasInjured = member.injured
			member.injured = false
			member.hp = member.maxHp
			if wasInjured then
				emit(events, { type = "CrewHealed", slot = member.slot, role = member.role })
			end
		end
	end
	if state.stunRemainingS > 0 then
		changed = true
		state.stunRemainingS = 0
		state.stunAttacker = nil
	end
	return changed
end

--------------------------------------------------------------------------------
-- Effects (multipliers for the systems that own each stat)
--------------------------------------------------------------------------------

local function stateOf(modules: { [InternalModuleKind]: ModuleCombatState }, kind: InternalModuleKind): string
	local mod = modules[kind]
	return if mod ~= nil then mod.state else "Ok"
end

--- An EffectMultipliers record with every multiplier at 1.
function DamageModel.newEffects(): EffectMultipliers
	return {
		enginePowerMul = 1,
		topSpeedMul = 1,
		canMove = true,
		hullTraverseMul = 1,
		turretTraverseMul = 1,
		reloadTimeMul = 1,
		canFire = true,
		aimTimeMul = 1,
		dispersionMul = 1,
		gunDamaged = false,
		viewRangeMul = 1,
		repairTimeMul = 1,
		fireChanceMul = 1,
		sixthSense = true,
		stunned = false,
		burning = false,
	}
end

--- Runtime multipliers from module states, crew injuries and stun (00-DECISIONS §2 "Effects", §4, §7.4 stun).
--- The damaged-gun bloom (× BLOOM_DAMAGED_MUL) is NOT in dispersionMul: pass `gunDamaged` to Dispersion.
function DamageModel.effects(state: VehicleCombatState, out: EffectMultipliers?): EffectMultipliers
	local C = Config.Combat
	local e = out or DamageModel.newEffects()
	local crew = CrewEffects.multipliers(state.crew, state.crewLevels, crewScratch)
	local m = state.modules
	e.enginePowerMul = if stateOf(m, "Engine") == "Damaged" then C.ENGINE_DAMAGED_POWER_MUL else 1
	e.topSpeedMul = 1
	e.canMove = stateOf(m, "Engine") ~= "Destroyed"
	for _, side: InternalModuleKind in TRACK_SIDES do
		if stateOf(m, side) == "Destroyed" then
			if state.wheeled then
				e.topSpeedMul *= C.WHEELED_LOST_SIDE_SPEED_MUL
			else
				e.canMove = false
			end
		end
	end
	local ring = stateOf(m, "TurretRing")
	e.turretTraverseMul = (
		if ring == "Destroyed" then 0 elseif ring == "Damaged" then C.RING_DAMAGED_TRAVERSE_MUL else 1
	) * crew.turretTraverse
	e.hullTraverseMul = crew.hullTraverse
	local gun = stateOf(m, "Gun")
	e.canFire = gun ~= "Destroyed"
	e.gunDamaged = gun ~= "Ok"
	e.aimTimeMul = (if gun ~= "Ok" then C.GUN_DAMAGED_AIM_MUL else 1) * crew.aimTime
	e.dispersionMul = crew.dispersion
	e.reloadTimeMul = (if stateOf(m, "AmmoRack") ~= "Ok" then C.AMMO_DAMAGED_RELOAD_MUL else 1) * crew.reloadTime
	local optics = stateOf(m, "Optics")
	e.viewRangeMul = (
		if optics == "Destroyed"
			then C.OPTICS_DESTROYED_VR_MUL
			elseif optics == "Damaged" then C.OPTICS_DAMAGED_VR_MUL
			else 1
	) * crew.viewRange
	e.fireChanceMul = if stateOf(m, "FuelTank") ~= "Ok" then C.FUEL_DAMAGED_FIRE_MUL else 1
	e.repairTimeMul = crew.repairTime
	e.sixthSense = crew.sixthSense
	e.burning = state.fire.burning
	e.stunned = state.stunRemainingS > 0
	if e.stunned then
		e.reloadTimeMul *= C.STUN_RELOAD_MUL
		e.aimTimeMul *= C.STUN_AIM_TIME_MUL
		e.dispersionMul *= C.STUN_DISPERSION_MUL
		e.turretTraverseMul *= C.STUN_TRAVERSE_MUL
		e.hullTraverseMul *= C.STUN_TRAVERSE_MUL
		e.topSpeedMul *= C.STUN_SPEED_MUL
		e.viewRangeMul *= C.STUN_VIEW_RANGE_MUL
	end
	if state.destroyed then
		e.canMove = false
		e.canFire = false
	end
	return e
end

--------------------------------------------------------------------------------
-- Ramming, falls, drowning
--------------------------------------------------------------------------------

local function remember(state: VehicleCombatState, contactId: any): boolean
	if contactId == nil then
		return true
	end
	if state.contacts[contactId] then
		return false
	end
	local size = Config.Combat.CONTACT_MEMORY
	local slot = state.contactNext
	local old = state.contactRing[slot]
	if old ~= nil then
		state.contacts[old] = nil
	end
	state.contactRing[slot] = contactId
	state.contacts[contactId] = true
	state.contactNext = (slot % size) + 1
	return true
end

--- True when a world contact point lies on the hull's front arc (bearing within ±RAM_FRONT_ARC_HALF_DEG of −Z).
function DamageModel.isFrontArc(hullCFrame: CFrame, contactPoint: Vector3): boolean
	local p = hullCFrame:PointToObjectSpace(contactPoint)
	if not (p.X == p.X and p.Z == p.Z) or (p.X == 0 and p.Z == 0) then
		return false
	end
	local bearing = math.deg(math.atan2(p.X, -p.Z))
	return math.abs(bearing) <= Config.Combat.RAM_FRONT_ARC_HALF_DEG
end

--- Ram damage dealt by `source` to `victim` at closing speed `closingSpeedMps` (along the contact normal):
--- max(0, 0.05 · m_source[t] · v² · dealtMul − 1.1 · T_victim · K_victim) × (victim front arc ½) × takenMul.
--- Returns (whole HP, raw energy term before armor). 0 below RAM_MIN_SPEED_MPS.
function DamageModel.ramDamage(source: RamParty, victim: RamParty, closingSpeedMps: number): (number, number)
	local C = Config.Combat
	local v = closingSpeedMps
	if not (v >= C.RAM_MIN_SPEED_MPS) or v == math.huge then
		return 0, 0
	end
	local raw = C.RAM_ENERGY_FACTOR * (source.massKg / 1000) * v * v * (source.ramDamageDealtMul or 1)
	if not (raw > 0) or raw == math.huge then
		return 0, 0
	end
	local k = victim.spallFactor or C.SPALL_FACTOR_BASE
	local d = raw - C.RAM_ARMOR_FACTOR * victim.contactThicknessMm * k
	if victim.frontArc then
		d *= C.RAM_FRONT_ARC_TAKEN_MUL
	end
	d *= victim.ramDamageTakenMul or 1
	return wholeHp(d), raw
end

--- Symmetric ram: (damage to A, damage to B, raw term on A, raw term on B).
function DamageModel.resolveRam(a: RamParty, b: RamParty, closingSpeedMps: number): (number, number, number, number)
	local toB, rawB = DamageModel.ramDamage(a, b, closingSpeedMps)
	local toA, rawA = DamageModel.ramDamage(b, a, closingSpeedMps)
	return toA, toB, rawA, rawB
end

local function trackSide(rng: RNG, side: InternalModuleKind?): InternalModuleKind
	if side == "TrackLeft" or side == "TrackRight" then
		return side
	end
	return if rng:chance(0.5) then "TrackLeft" else "TrackRight"
end

--- Applies one ram contact (unique `contactId`; repeats are ignored, REG-ARM-10): HP damage `damage` and a track
--- roll (RAM_TRACK_HIT_CHANCE) for `side` (nil = random) taking RAM_TRACK_DAMAGE_MUL × `rawTerm`.
--- Returns the HP removed.
function DamageModel.applyRam(
	state: VehicleCombatState,
	contactId: any,
	damage: number,
	rawTerm: number,
	rng: RNG,
	attacker: AttackerId?,
	events: { CombatEvent }?,
	side: InternalModuleKind?
): number
	if state.destroyed or not remember(state, contactId) then
		return 0
	end
	local C = Config.Combat
	if rawTerm > 0 and rng:chance(C.RAM_TRACK_HIT_CHANCE) then
		DamageModel.damageModule(state, trackSide(rng, side), C.RAM_TRACK_DAMAGE_MUL * rawTerm, attacker, events)
	end
	return DamageModel.applyDamage(state, "Ram", damage, attacker, events)
end

--- Fall damage (whole HP) for a landing at vertical speed `vyMps`: 0.6 · m[t] · (v_y − 7)² (× 2 inverted) × mul.
function DamageModel.fallDamage(massKg: number, vyMps: number, inverted: boolean?, mul: number?): number
	local C = Config.Combat
	local v = math.abs(vyMps)
	if not (v > C.FALL_MIN_SPEED_MPS) or v == math.huge then
		return 0
	end
	local excess = v - C.FALL_MIN_SPEED_MPS
	local d = C.FALL_DAMAGE_FACTOR * (massKg / 1000) * excess * excess
	if inverted then
		d *= C.FALL_INVERTED_MUL
	end
	return wholeHp(d * (mul or 1))
end

--- Applies one landing (unique `contactId`): fall damage with the vehicle's mass and fallDamageMul, and a track
--- destroyed with chance min(1, (v_y − 7) / FALL_TRACK_SPAN_MPS). No kill credit. Returns the HP removed.
function DamageModel.applyFall(
	state: VehicleCombatState,
	contactId: any,
	vyMps: number,
	inverted: boolean,
	rng: RNG,
	events: { CombatEvent }?
): number
	if state.destroyed or not remember(state, contactId) then
		return 0
	end
	local C = Config.Combat
	local v = math.abs(vyMps)
	if not (v > C.FALL_MIN_SPEED_MPS) or v == math.huge then
		return 0
	end
	local chance = math.min(1, (v - C.FALL_MIN_SPEED_MPS) / C.FALL_TRACK_SPAN_MPS)
	if rng:chance(chance) then
		local kind: InternalModuleKind = trackSide(rng, nil)
		local track = state.modules[kind]
		if track ~= nil then
			DamageModel.damageModule(state, kind, track.hp, nil, events)
		end
	end
	return DamageModel.applyDamage(
		state,
		"Fall",
		DamageModel.fallDamage(state.massKg, v, inverted, state.fallDamageMul),
		nil,
		events
	)
end

--- Drowning timer: while `submerged` (water over the turret roof) it runs; DROWN_TIME_S destroys the vehicle with
--- no kill credit; leaving the water resets it. Returns true when this call destroyed the vehicle.
function DamageModel.updateDrowning(
	state: VehicleCombatState,
	submerged: boolean,
	dt: number,
	events: { CombatEvent }?
): boolean
	if state.destroyed then
		return false
	end
	local C = Config.Combat
	if not submerged then
		if state.drownS > 0 then
			state.drownS = 0
			emit(events, { type = "Drowning", active = false, remainingS = C.DROWN_TIME_S })
		end
		return false
	end
	if not (dt >= 0) or dt == math.huge then
		return false
	end
	if state.drownS == 0 then
		emit(events, { type = "Drowning", active = true, remainingS = C.DROWN_TIME_S })
	end
	state.drownS += dt
	if state.drownS >= C.DROWN_TIME_S then
		local removed = state.hp
		if removed > 0 then
			emit(events, { type = "Damage", kind = "Drown", damage = removed, attacker = nil })
		end
		destroy(state, "Drown", nil, events)
		return true
	end
	return false
end

return DamageModel
