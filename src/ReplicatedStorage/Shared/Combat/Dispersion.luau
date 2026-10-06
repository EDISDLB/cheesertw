--!strict
--[[
	Combat/Dispersion — the aiming circle (00-DECISIONS §3): bloom target from hull speed / hull traverse / turret
	traverse (root-sum-square) × damaged gun, convergence by aim time (e-fold), after-shot bloom, the circle radius
	at a distance, and shot direction sampling with the decided 2σ radial model (gauss2d kept as an option).

	Purpose:          Server-authoritative aim state per vehicle (rolled shots) and the client predicted reticle
	                  (same math, REG-PRJ-01). Bots use radiusAt / timeToAim.
	Dependencies:     Config (Combat), Core/RNG (type), Types/Vehicle, Types/Combat.
	State:            AimState records (owned by the caller, mutated in place). No module state.
	Validation:       Non-finite or negative factors count as 0; dt <= 0 or non-finite does not decay; M is clamped
	                  to [1, DISPERSION_MAX_MULTIPLIER]; a zero aim time snaps to the target.
	Error handling:   No throws.
	Performance notes: update()/onShot() are allocation-free; sampleDirection() builds 3–4 Vector3 values.

	Model: M_target = √(1 + (k_mv·v_kmh)² + (k_hull·ω_hull)² + (k_tur·ω_tur)²) × (damagedMul if the gun is damaged)
	× WHEELED_MOVING_BLOOM_MUL (wheeled, moving) × STUN_DISPERSION_MUL (stunned);
	M ← max(M_target, M · e^(−Δt/τ)) with τ = aimTime × aimTimeMul; on a shot M ← max(M, M_target) × afterShot.
	Radius at 100 m = dispersionM100 × M × dispersionMul; radius at d m = that × d / 100 (linear in distance).
	Sampling: σ = R / 2 (the circle edge is 2σ). "radial": miss distance |N(0, σ)| at a uniform angle, re-rolled
	beyond 2σ; "gauss2d": x, y ~ N(0, σ), re-rolled beyond 2σ. After DISPERSION_RESAMPLE_TRIES the miss is clamped
	to the rim. The angular miss is atan(r100 / 100) — independent of the target distance.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNGModule = require("@game/ReplicatedStorage/Shared/Core/RNG")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")

type RNG = RNGModule.RNG
type BloomStats = VehicleTypes.BloomStats
type AimState = CombatTypes.AimState
type AimFactors = CombatTypes.AimFactors
type DispersionModel = CombatTypes.DispersionModel

local Dispersion = {}

local function nonNegative(n: number?): number
	if n == nil or not (n > 0) or n == math.huge then
		return 0
	end
	return n
end

local function positive(n: number?, default: number): number
	if n == nil or not (n > 0) or n == math.huge then
		return default
	end
	return n
end

--- Default bloom factors from Config (authoring defaults of GunStats.bloom; afterShot by class).
function Dispersion.defaultBloom(class: string?): BloomStats
	local C = Config.Combat
	local afterShot = if class ~= nil then (C.AFTER_SHOT_BLOOM :: any)[class] else nil
	return {
		movementPerKmh = C.BLOOM_MOVEMENT_PER_KMH,
		hullTraversePerDegS = C.BLOOM_HULL_TRAVERSE_PER_DEGS,
		turretTraversePerDegS = C.BLOOM_TURRET_TRAVERSE_PER_DEGS,
		afterShot = if type(afterShot) == "number" then afterShot else C.AFTER_SHOT_BLOOM.medium,
		damagedMul = C.BLOOM_DAMAGED_MUL,
	}
end

--- A new aim state for a gun (GunStats: dispersionM100, aimTimeS, bloom), fully aimed (M = 1).
function Dispersion.new(gun: { dispersionM100: number, aimTimeS: number, bloom: BloomStats }): AimState
	return {
		baseRadiusM100 = nonNegative(gun.dispersionM100),
		aimTimeS = nonNegative(gun.aimTimeS),
		bloom = gun.bloom,
		multiplier = 1,
		target = 1,
		extraMul = 1,
	}
end

--- M_target for the given factors (≥ 1).
function Dispersion.targetMultiplier(bloom: BloomStats, factors: AimFactors): number
	local C = Config.Combat
	local mv = nonNegative(bloom.movementPerKmh) * math.abs(factors.hullSpeedKmh or 0)
	local hull = nonNegative(bloom.hullTraversePerDegS) * math.abs(factors.hullTraverseDegS or 0)
	local tur = nonNegative(bloom.turretTraversePerDegS) * math.abs(factors.turretTraverseDegS or 0)
	if mv ~= mv or mv == math.huge then
		mv = 0
	end
	if hull ~= hull or hull == math.huge then
		hull = 0
	end
	if tur ~= tur or tur == math.huge then
		tur = 0
	end
	local m = math.sqrt(1 + mv * mv + hull * hull + tur * tur)
	if factors.gunDamaged then
		m *= positive(bloom.damagedMul, C.BLOOM_DAMAGED_MUL)
	end
	if factors.wheeledMoving then
		m *= C.WHEELED_MOVING_BLOOM_MUL
	end
	if factors.stunned then
		m *= C.STUN_DISPERSION_MUL
	end
	return math.clamp(m, 1, C.DISPERSION_MAX_MULTIPLIER)
end

--- Advances the aim by `dt` seconds: M = max(M_target, M · e^(−dt/τ)).
function Dispersion.update(state: AimState, dt: number, factors: AimFactors)
	local target = Dispersion.targetMultiplier(state.bloom, factors)
	state.target = target
	state.extraMul = positive(factors.dispersionMul, 1)
	local tau = state.aimTimeS * positive(factors.aimTimeMul, 1)
	local m = state.multiplier
	if dt > 0 and dt < math.huge then
		if tau > 0 then
			m *= math.exp(-dt / tau)
		else
			m = target
		end
	end
	if not (m >= target) then
		m = target
	end
	state.multiplier = math.min(m, Config.Combat.DISPERSION_MAX_MULTIPLIER)
end

--- After-shot bloom: M = max(M, M_target) × afterShot (`afterShotOverride` for volleys / special guns).
function Dispersion.onShot(state: AimState, afterShotOverride: number?)
	local C = Config.Combat
	local bloom = positive(afterShotOverride or state.bloom.afterShot, C.AFTER_SHOT_BLOOM.medium)
	state.multiplier = math.min(math.max(state.multiplier, state.target) * bloom, C.DISPERSION_MAX_MULTIPLIER)
end

--- Resets to fully aimed (spawn, respawn after a stop of the simulation).
function Dispersion.reset(state: AimState)
	state.multiplier = 1
	state.target = 1
end

--- Current circle radius in metres at 100 m.
function Dispersion.radiusM100(state: AimState): number
	return state.baseRadiusM100 * state.multiplier * state.extraMul
end

--- Circle radius in metres at `distanceM` (linear in distance).
function Dispersion.radiusAt(state: AimState, distanceM: number): number
	return Dispersion.radiusM100(state) * nonNegative(distanceM) / 100
end

--- Seconds until fully aimed at the current target with no new bloom: τ · ln(M / M_target).
function Dispersion.timeToAim(state: AimState, aimTimeMul: number?): number
	local tau = state.aimTimeS * positive(aimTimeMul, 1)
	if state.multiplier <= state.target or tau <= 0 then
		return 0
	end
	return tau * math.log(state.multiplier / state.target)
end

--- Samples a miss offset inside a circle of radius `radius` (any unit): returns (x, y) in the same unit.
function Dispersion.sampleOffset(radius: number, rng: RNG, model: DispersionModel?): (number, number)
	local C = Config.Combat
	if not (radius > 0) or radius == math.huge then
		return 0, 0
	end
	local edge = C.DISPERSION_EDGE_SIGMAS
	local sigma = radius / edge
	local chosen = model or (C.DISPERSION_MODEL :: DispersionModel)
	local tries = C.DISPERSION_RESAMPLE_TRIES
	if chosen == "gauss2d" then
		local x, y = 0, 0
		for _ = 1, tries do
			x = rng:normal(0, sigma)
			y = rng:normal(0, sigma)
			if x * x + y * y <= radius * radius then
				return x, y
			end
		end
		local r = math.sqrt(x * x + y * y)
		return x / r * radius, y / r * radius
	end
	local r = radius
	for _ = 1, tries do
		local z = math.abs(rng:normal(0, sigma))
		if z <= radius then
			r = z
			break
		end
	end
	local phi = rng:range(0, 2 * math.pi)
	return r * math.cos(phi), r * math.sin(phi)
end

--- The shot direction: `aimDirection` deviated by a miss sampled in a circle of `radiusM100` metres at 100 m.
--- Returns a unit vector (the aim direction itself when the radius is 0 or the input is degenerate).
function Dispersion.sampleDirection(
	aimDirection: Vector3,
	radiusM100: number,
	rng: RNG,
	model: DispersionModel?
): Vector3
	local mag = aimDirection.Magnitude
	if not (mag > 0) or mag == math.huge or mag ~= mag then
		return Vector3.new(0, 0, -1)
	end
	local forward = aimDirection / mag
	local x, y = Dispersion.sampleOffset(radiusM100, rng, model)
	if x == 0 and y == 0 then
		return forward
	end
	local up = if math.abs(forward.Y) < 0.99 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local right = forward:Cross(up).Unit
	local trueUp = right:Cross(forward)
	-- Offset in the plane 100 m ahead (both in metres): direction = forward·100 + right·x + up·y.
	return (forward * 100 + right * x + trueUp * y).Unit
end

return Dispersion
