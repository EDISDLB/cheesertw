--!strict
--[[
	Combat/Fire — the vehicle fire state machine (00-DECISIONS §2 "Fire"): ignition chance per engine hit, burn
	timer, damage-over-time in whole-HP ticks with a fractional carry, extinguishing.

	Purpose:          Used by DamageModel (ignition from engine hits / destroyed fuel, DoT in update, consumables).
	Dependencies:     Config (Combat), Types/Combat.
	State:            None (FireState records are owned by VehicleCombatState).
	Validation:       Non-positive or non-finite dt is ignored; chances are clamped to [0, 1].
	Error handling:   No throws.
	Performance notes: Arithmetic only; tick() loops at most once per FIRE_TICK_S elapsed.

	Model: burning for `durationS` (FIRE_DURATION_S × Fire Fighting etc., from VehicleStats.fireDurationS); every
	FIRE_TICK_S the vehicle loses FIRE_DAMAGE_PER_S × maxHp × tick seconds (the last tick is partial), fractional HP
	carried to the next tick so the total over a full burn is exactly 20 % of max HP at the defaults. Ignition while
	already burning changes nothing (the first igniter keeps the credit).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")

type FireState = CombatTypes.FireState
type AttackerId = CombatTypes.AttackerId

local Fire = {}

--- A fresh, not-burning fire state.
function Fire.newState(): FireState
	return { burning = false, remainingS = 0, tickAccum = 0, carry = 0, elapsedS = 0, igniter = nil }
end

--- Fire chance of one engine hit: the vehicle's chance × FUEL_DAMAGED_FIRE_MUL while the fuel tank is Damaged
--- (or Destroyed), clamped to [0, 1].
function Fire.engineHitChance(baseChance: number, fuelState: string?): number
	local chance = if baseChance == baseChance then baseChance else 0
	if fuelState == "Damaged" or fuelState == "Destroyed" then
		chance *= Config.Combat.FUEL_DAMAGED_FIRE_MUL
	end
	return math.clamp(chance, 0, 1)
end

--- Starts a fire burning for `durationS` credited to `igniter`. Returns true only when it was not burning already.
function Fire.ignite(fire: FireState, durationS: number, igniter: AttackerId?): boolean
	if fire.burning then
		return false
	end
	fire.burning = true
	fire.remainingS = if durationS > 0 and durationS < math.huge then durationS else Config.Combat.FIRE_DURATION_S
	fire.tickAccum = 0
	fire.carry = 0
	fire.elapsedS = 0
	fire.igniter = igniter
	return true
end

--- Puts the fire out immediately. Returns true when it was burning.
function Fire.extinguish(fire: FireState): boolean
	if not fire.burning then
		return false
	end
	fire.burning = false
	fire.remainingS = 0
	fire.tickAccum = 0
	fire.carry = 0
	return true
end

--- Advances the fire by `dt`. Returns (whole HP lost this call, fire ticks elapsed, burnedOut). The caller applies
--- the HP and per-tick module/crew damage and must not call tick() on a destroyed vehicle.
function Fire.tick(fire: FireState, dt: number, maxHp: number): (number, number, boolean)
	if not fire.burning or not (dt > 0) or dt == math.huge then
		return 0, 0, false
	end
	local C = Config.Combat
	local tickS = C.FIRE_TICK_S
	fire.elapsedS += dt
	fire.tickAccum += dt
	local hp, ticks = 0, 0
	while fire.burning and fire.tickAccum >= tickS - 1e-9 do
		fire.tickAccum -= tickS
		ticks += 1
		local burnS = math.min(tickS, fire.remainingS)
		fire.carry += C.FIRE_DAMAGE_PER_S * maxHp * burnS
		local whole = math.floor(fire.carry + 1e-9)
		fire.carry -= whole
		hp += whole
		fire.remainingS -= tickS
		if fire.remainingS <= 1e-9 then
			fire.burning = false
			fire.remainingS = 0
			fire.tickAccum = 0
			fire.carry = 0
			return hp, ticks, true
		end
	end
	return hp, ticks, false
end

return Fire
