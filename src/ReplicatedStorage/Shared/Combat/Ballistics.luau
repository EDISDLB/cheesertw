--!strict
--[[
	Combat/Ballistics — shell flight (analytic gravity arc), the per-tick swept segment for the server
	ProjectileSystem, distance-based penetration falloff, and the elevation / time-of-flight solver used by the
	reticle and bots.

	Purpose:          One flight model shared by server (authoritative hits) and client (tracers, predicted reticle),
	                  so tracer samples match the server path (REG-PRJ-02).
	Dependencies:     Config (Combat), Core/Units, Types/Combat.
	State:            None (Projectile records are owned by the caller and mutated in place).
	Validation:       Non-finite inputs never propagate: launch() with a bad direction/speed returns an expired
	                  projectile; step() on an expired projectile returns a zero-length segment.
	Error handling:   No throws on numeric input; solveElevation returns nil when the target is out of reach.
	Performance notes: step() allocates nothing but the Vector3 values it returns; positions are evaluated
	                  analytically (no integration drift, any tick rate gives the same arc).

	Units: positions/velocities in the Projectile are STUDS and studs/s (gravity studs/s² along −Y); shells and
	config are real-world (m/s, m/s², m). Flight follows 00-DECISIONS §1: no drag, shell gravity 19.62 m/s² (not
	Workspace.Gravity), direct fire despawns after MAX_RANGE_M of path length (chord sum, ± one tick of travel).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")

type Projectile = CombatTypes.Projectile
type CombatShell = CombatTypes.CombatShell

local Ballistics = {}

local STUDS = Units.STUDS_PER_METER

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteVector(v: Vector3): boolean
	return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

--------------------------------------------------------------------------------
-- Authoring helpers (content defaults; StatsCalculator / ContentRegistry)
--------------------------------------------------------------------------------

--- In-game muzzle velocity (m/s) from a real-world figure (× VELOCITY_SCALE).
function Ballistics.authoredVelocityMps(realMps: number): number
	return realMps * Config.Combat.VELOCITY_SCALE
end

--- Default velocity (m/s) of a family on a gun whose AP shell flies at `apVelocityMps`.
function Ballistics.familyVelocityMps(kind: string, apVelocityMps: number): number
	local ratio = (Config.Combat.VELOCITY_RATIO :: any)[kind]
	return apVelocityMps * (if type(ratio) == "number" then ratio else 1)
end

--- Default penetration at the end of the falloff (AP × 0.90, APCR × 0.75, others unchanged).
function Ballistics.defaultPenetrationAt500(kind: string, penetrationMm: number): number
	local ratio = (Config.Combat.FALLOFF_AT_END :: any)[kind]
	return penetrationMm * (if type(ratio) == "number" then ratio else 1)
end

--------------------------------------------------------------------------------
-- Penetration falloff
--------------------------------------------------------------------------------

--- Mean penetration (mm) at `distanceM` from the muzzle: AP/APCR nominal up to FALLOFF_START_M, linear to
--- penetrationAt500Mm at FALLOFF_END_M, flat beyond; HEAT/HE/HESH constant (00-DECISIONS §1 "Falloff").
function Ballistics.penetrationAt(shell: CombatShell, distanceM: number): number
	local C = Config.Combat
	local pen = shell.penetrationMm
	if not (C.KINETIC :: any)[shell.kind] then
		return pen
	end
	local d = if distanceM == distanceM then distanceM else 0
	local startM, endM = C.FALLOFF_START_M, C.FALLOFF_END_M
	if d <= startM then
		return pen
	end
	local far = shell.penetrationAt500Mm
	if d >= endM or endM <= startM then
		return far
	end
	return pen + (far - pen) * ((d - startM) / (endM - startM))
end

--------------------------------------------------------------------------------
-- Flight
--------------------------------------------------------------------------------

--- Speed (studs/s), gravity (studs/s²) and max range (studs) of a shell.
function Ballistics.flightParams(shell: CombatShell): (number, number, number)
	local C = Config.Combat
	local gravity = if isFinite(shell.gravityMps2) and shell.gravityMps2 >= 0
		then shell.gravityMps2
		else C.SHELL_GRAVITY_MPS2
	local range = if isFinite(shell.maxRangeM) and shell.maxRangeM > 0 then shell.maxRangeM else C.MAX_RANGE_M
	return shell.velocityMps * STUDS, gravity * STUDS, range * STUDS
end

--- A new projectile leaving `origin` (world studs) along `direction` (any length). Reuses `out` when given.
--- Bad input (zero / non-finite direction, origin or speed) yields an already-expired projectile.
function Ballistics.launch(origin: Vector3, direction: Vector3, shell: CombatShell, out: Projectile?): Projectile
	local speed, gravity, range = Ballistics.flightParams(shell)
	local p: Projectile = out
		or {
			origin = origin,
			velocity0 = Vector3.zero,
			gravity = gravity,
			t = 0,
			position = origin,
			traveled = 0,
			maxRange = range,
			expired = false,
		}
	local mag = direction.Magnitude
	local ok = finiteVector(origin) and mag > 0 and isFinite(mag) and isFinite(speed) and speed > 0
	p.origin = origin
	p.position = origin
	p.velocity0 = if ok then direction * (speed / mag) else Vector3.zero
	p.gravity = gravity
	p.t = 0
	p.traveled = 0
	p.maxRange = range
	p.expired = not ok
	return p
end

--- Position (world studs) `t` seconds after the projectile's current origin.
function Ballistics.positionAt(p: Projectile, t: number): Vector3
	local v = p.velocity0
	local g = p.gravity
	return Vector3.new(p.origin.X + v.X * t, p.origin.Y + v.Y * t - 0.5 * g * t * t, p.origin.Z + v.Z * t)
end

--- Velocity (studs/s) `t` seconds after the projectile's current origin.
function Ballistics.velocityAt(p: Projectile, t: number): Vector3
	local v = p.velocity0
	return Vector3.new(v.X, v.Y - p.gravity * t, v.Z)
end

--- Advances the projectile by `dt` and returns this tick's swept segment (from, to) plus `expired`. When the path
--- length reaches maxRange the segment is cut at the remaining length (along the chord) and the projectile expires.
function Ballistics.step(p: Projectile, dt: number): (Vector3, Vector3, boolean)
	local from = p.position
	if p.expired or not (dt > 0) or not isFinite(dt) then
		return from, from, p.expired
	end
	local t1 = p.t + dt
	local to = Ballistics.positionAt(p, t1)
	if not finiteVector(to) then
		p.expired = true
		return from, from, true
	end
	local chord = (to - from).Magnitude
	local remaining = p.maxRange - p.traveled
	if chord >= remaining then
		local f = if chord > 0 then math.max(0, remaining) / chord else 0
		to = from + (to - from) * f
		p.t += dt * f
		p.traveled = p.maxRange
		p.position = to
		p.expired = true
		return from, to, true
	end
	p.t = t1
	p.traveled += chord
	p.position = to
	return from, to, false
end

--- Re-bases the projectile at `point` flying along `direction` (ricochet continuation): keeps the current speed
--- (or `speed` studs/s when given), the travelled distance and the range budget.
function Ballistics.redirect(p: Projectile, point: Vector3, direction: Vector3, speed: number?)
	local current = speed or Ballistics.velocityAt(p, p.t).Magnitude
	local mag = direction.Magnitude
	if not (mag > 0 and isFinite(mag) and isFinite(current)) or not finiteVector(point) then
		p.expired = true
		return
	end
	p.origin = point
	p.position = point
	p.velocity0 = direction * (current / mag)
	p.t = 0
end

--- Straight-line distance in metres between two world points in studs (falloff distance muzzle -> impact).
function Ballistics.distanceM(a: Vector3, b: Vector3): number
	return (b - a).Magnitude / STUDS
end

--------------------------------------------------------------------------------
-- Aiming solver
--------------------------------------------------------------------------------

--- Launch elevation (radians above horizontal) and time of flight (s) to hit `target` from `origin` (world studs)
--- with muzzle speed `speed` (studs/s) under `gravity` (studs/s²). Low arc by default, high arc when `highArc`.
--- Returns nil when the target is out of reach (or inputs are not finite).
function Ballistics.solveElevation(
	origin: Vector3,
	target: Vector3,
	speed: number,
	gravity: number,
	highArc: boolean?
): (number?, number?)
	if not (finiteVector(origin) and finiteVector(target) and isFinite(speed) and speed > 0 and isFinite(gravity)) then
		return nil, nil
	end
	local delta = target - origin
	local x = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
	local y = delta.Y
	if gravity <= 0 then
		local distance = delta.Magnitude
		return math.atan2(y, x), distance / speed
	end
	if x < 1e-9 then
		-- Straight up / down.
		if y >= 0 then
			if speed * speed < 2 * gravity * y then
				return nil, nil
			end
			local tUp = (speed - math.sqrt(speed * speed - 2 * gravity * y)) / gravity
			return math.pi / 2, tUp
		end
		local tDown = (-speed + math.sqrt(speed * speed + 2 * gravity * -y)) / gravity
		return -math.pi / 2, tDown
	end
	local v2 = speed * speed
	local disc = v2 * v2 - gravity * (gravity * x * x + 2 * y * v2)
	if disc < 0 then
		return nil, nil
	end
	local root = math.sqrt(disc)
	local tanTheta = if highArc then (v2 + root) / (gravity * x) else (v2 - root) / (gravity * x)
	local theta = math.atan(tanTheta)
	local tof = x / (speed * math.cos(theta))
	return theta, tof
end

--- Unit launch direction and time of flight for `shell` from `origin` to `target` (world studs), or nil when out of
--- reach or beyond the shell's max range.
function Ballistics.aimDirection(
	origin: Vector3,
	target: Vector3,
	shell: CombatShell,
	highArc: boolean?
): (Vector3?, number?)
	local speed, gravity, range = Ballistics.flightParams(shell)
	local theta, tof = Ballistics.solveElevation(origin, target, speed, gravity, highArc)
	if theta == nil or tof == nil then
		return nil, nil
	end
	local delta = target - origin
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local horizontal = if flat.Magnitude > 1e-9 then flat.Unit else Vector3.new(0, 0, -1)
	local dir = horizontal * math.cos(theta) + Vector3.new(0, math.sin(theta), 0)
	-- Path length check (chord approximation is enough to reject impossible shots).
	if delta.Magnitude > range then
		return nil, nil
	end
	return dir.Unit, tof
end

--- Flat-ground maximum reach (studs) at 45° for a speed/gravity pair (v² / g).
function Ballistics.maxReach(speed: number, gravity: number): number
	if not (gravity > 0) then
		return math.huge
	end
	return speed * speed / gravity
end

return Ballistics
