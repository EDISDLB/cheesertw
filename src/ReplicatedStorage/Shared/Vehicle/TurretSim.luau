--!strict
--[[
	TurretSim — turret yaw and gun elevation toward a world aim point (ARCHITECTURE §6.1 step 3, §6.2).

	Purpose:          Rotates the turret (or a casemate gun inside its yaw arc) and elevates the gun toward the
	                  direction that puts the selected shell on the aim point: ballistic solution (low arc, high arc
	                  for indirect guns), traverse speed with turret-ring damage and crew multipliers, yaw limits,
	                  depression/elevation limits evaluated in the hull frame (so hull pitch is compensated: a nose-up
	                  hull on a reverse slope cannot depress as far in world terms), per-bearing arc sectors (rear
	                  deck), mechanic bonuses (SiegeMode/Hydropneumatic through the VehicleSim state), hold (free
	                  look). Reports the bearing speed for Dispersion (ω_tur) and builds the muzzle aim ray from the
	                  VehiclePivots. Also suggests a hull steer for casemates aiming outside their arc.
	Dependencies:     Config (Movement section), Core/Units, Types/Vehicle, Types/VehicleSim. Pure: no services.
	State:            None at module level; every vehicle owns a TurretSimState (angles, speeds, aim diagnostics and
	                  runtime modifiers).
	Validation:       Non-finite aim points keep the previous desired angles; dt <= 0 or NaN is a no-op; limits come
	                  from VehicleStats.gun (+ arc sectors) and are always enforced on the actual gun pitch.
	Error handling:   Never throws on finite input; a non-finite result restores the pre-step angles.
	Performance notes: A handful of CFrame operations per step (value types in Roblox); no table allocation.

	Conventions (Types/Vehicle): bearings are hull-relative degrees, 0 = forward, + = clockwise, in (-180, 180];
	elevation + = up. world = hullCFrame * turretRing * CFrame.Angles(0, -yaw, 0) * gunTrunnion
	* CFrame.Angles(elevation, 0, 0) * muzzle; casemates: hullCFrame * turretRing * gunTrunnion
	* CFrame.Angles(0, -gunYaw, 0) * CFrame.Angles(elevation, 0, 0) * muzzle.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Units = require("../Core/Units")
local VehicleTypes = require("../Types/Vehicle")
local SimTypes = require("../Types/VehicleSim")

type VehicleStats = VehicleTypes.VehicleStats
type VehiclePivots = VehicleTypes.VehiclePivots
type TurretSimState = SimTypes.TurretSimState
type TurretSimModifiers = SimTypes.TurretSimModifiers
type VehicleSimState = SimTypes.VehicleSimState
type TurretEffects = SimTypes.TurretEffects

local TurretSim = {}

local SPM = Units.STUDS_PER_METER
local DEG = math.pi / 180
local abs, sqrt, atan, atan2, min, max = math.abs, math.sqrt, math.atan, math.atan2, math.min, math.max

local function finite(x: number): boolean
	return x == x and x - x == 0
end

local function finiteVector(v: Vector3): boolean
	return finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function nonNegativeOr(x: number?, default: number): number
	if type(x) == "number" and x >= 0 and finite(x) then
		return x
	end
	return default
end

-- Wraps degrees to (-180, 180].
local function wrapDeg(d: number): number
	local w = (d + 180) % 360 - 180
	if w == -180 then
		return 180
	end
	return w
end

local function moveToward(current: number, target: number, maxDelta: number): number
	local d = target - current
	if abs(d) <= maxDelta then
		return target
	end
	return current + (if d > 0 then maxDelta else -maxDelta)
end

local function approachAngle(current: number, target: number, maxDelta: number): number
	local d = wrapDeg(target - current)
	if abs(d) <= maxDelta then
		return wrapDeg(current + d)
	end
	return wrapDeg(current + (if d > 0 then maxDelta else -maxDelta))
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- Neutral modifiers: modules OK, no multipliers, enabled, straight-line aiming until a shell is selected.
function TurretSim.newModifiers(): TurretSimModifiers
	return {
		ring = "Ok",
		gun = "Ok",
		traverseMul = 1,
		elevationSpeedMul = 1,
		depressionBonusDeg = 0,
		elevationBonusDeg = 0,
		enabled = true,
		shellVelocityMps = 0,
		shellGravityMps2 = 0,
		highArc = nil,
	}
end

--- Turret/gun at rest: bearing 0, elevation 0.
function TurretSim.newState(): TurretSimState
	return {
		turretYawDeg = 0,
		gunYawDeg = 0,
		gunPitchDeg = 0,
		bearingSpeedDegS = 0,
		pitchSpeedDegS = 0,
		desiredBearingDeg = 0,
		desiredPitchDeg = 0,
		aimErrorDeg = 0,
		outOfArc = false,
		outOfElevation = false,
		reachable = true,
		modifiers = TurretSim.newModifiers(),
	}
end

--- Maps DamageModel.effects (Types/Combat.EffectMultipliers.turretTraverseMul: ring damage, gunner injury and stun
--- combined) onto the modifiers. Use this OR modifiers.ring, never both: the ring state is reset to "Ok" here.
function TurretSim.applyEffects(turret: TurretSimState, effects: TurretEffects)
	local mods = turret.modifiers
	mods.ring = "Ok"
	mods.traverseMul = nonNegativeOr(effects.turretTraverseMul, 1)
end

--- Selects the shell the gun is laid for (ballistic aiming); velocity 0 aims the barrel straight at the point.
function TurretSim.setShell(turret: TurretSimState, velocityMps: number, gravityMps2: number)
	local mods = turret.modifiers
	mods.shellVelocityMps = nonNegativeOr(velocityMps, 0)
	mods.shellGravityMps2 = nonNegativeOr(gravityMps2, 0)
end

--------------------------------------------------------------------------------
-- Limits
--------------------------------------------------------------------------------

--- Hull-relative yaw range of the turret (or casemate gun): (limited, left, right) as positive magnitudes.
function TurretSim.yawRange(stats: VehicleStats): (boolean, number, number)
	local lim = stats.yawLimitsDeg
	local left, right
	if lim ~= nil then
		left, right = abs(lim.left), abs(lim.right)
	elseif stats.turretMount == "Casemate" then
		local d = Config.Movement.CASEMATE_DEFAULT_YAW_DEG
		left, right = d, d
	else
		return false, 180, 180
	end
	if not (finite(left) and finite(right)) or left + right >= 360 then
		return false, 180, 180
	end
	return true, min(left, 180), min(right, 180)
end

local function inSector(bearing: number, fromDeg: number, toDeg: number): boolean
	local span = (toDeg - fromDeg) % 360
	local offset = (bearing - fromDeg) % 360
	return offset <= span
end

--- Depression and elevation limits (positive magnitudes, degrees, relative to the hull) at a hull-relative bearing:
--- the gun's arcs, overridden by every arc sector containing the bearing (most restrictive wins), plus bonuses.
function TurretSim.limitsAt(
	stats: VehicleStats,
	bearingDeg: number,
	depressionBonusDeg: number?,
	elevationBonusDeg: number?
): (number, number)
	local gun = stats.gun
	local dep = nonNegativeOr(gun.depressionDeg, 0)
	local elev = nonNegativeOr(gun.elevationDeg, 0)
	local sectors = gun.arcSectors
	if type(sectors) == "table" and #sectors > 0 then
		local b = wrapDeg(bearingDeg)
		local sDep, sElev = math.huge, math.huge
		for _, s in sectors do
			if inSector(b, s.fromDeg, s.toDeg) then
				if s.depressionDeg ~= nil then
					sDep = min(sDep, nonNegativeOr(s.depressionDeg, 0))
				end
				if s.elevationDeg ~= nil then
					sElev = min(sElev, nonNegativeOr(s.elevationDeg, 0))
				end
			end
		end
		if sDep < math.huge then
			dep = sDep
		end
		if sElev < math.huge then
			elev = sElev
		end
	end
	local db = depressionBonusDeg or 0
	local eb = elevationBonusDeg or 0
	if not finite(db) then
		db = 0
	end
	if not finite(eb) then
		eb = 0
	end
	return clamp(dep + db, 0, 90), clamp(elev + eb, 0, 90)
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function isCasemate(stats: VehicleStats): boolean
	return stats.turretMount == "Casemate"
end

--- Turret frame (turret space -> world) for the current bearing (casemates: the fixed superstructure).
function TurretSim.turretCFrame(
	turret: TurretSimState,
	hullCFrame: CFrame,
	stats: VehicleStats,
	pivots: VehiclePivots
): CFrame
	local ring = hullCFrame * pivots.turretRing
	if isCasemate(stats) then
		return ring
	end
	return ring * CFrame.Angles(0, -turret.turretYawDeg * DEG, 0)
end

--- Gun frame (gun space -> world): trunnion with yaw and elevation applied. -Z = barrel direction.
function TurretSim.gunCFrame(
	turret: TurretSimState,
	hullCFrame: CFrame,
	stats: VehicleStats,
	pivots: VehiclePivots
): CFrame
	local ring = hullCFrame * pivots.turretRing
	local elevation = CFrame.Angles(turret.gunPitchDeg * DEG, 0, 0)
	if isCasemate(stats) then
		return ring * pivots.gunTrunnion * CFrame.Angles(0, -turret.gunYawDeg * DEG, 0) * elevation
	end
	return ring * CFrame.Angles(0, -turret.turretYawDeg * DEG, 0) * pivots.gunTrunnion * elevation
end

--- Muzzle frame in the world (-Z = shot direction).
function TurretSim.muzzleCFrame(
	turret: TurretSimState,
	hullCFrame: CFrame,
	stats: VehicleStats,
	pivots: VehiclePivots
): CFrame
	return TurretSim.gunCFrame(turret, hullCFrame, stats, pivots) * pivots.muzzle
end

--- Shot ray: (origin = muzzle position in studs, direction = unit barrel direction). Dispersion is applied by the
--- shooter around this direction.
function TurretSim.aimRay(
	turret: TurretSimState,
	hullCFrame: CFrame,
	stats: VehicleStats,
	pivots: VehiclePivots
): (Vector3, Vector3)
	local muzzle = TurretSim.muzzleCFrame(turret, hullCFrame, stats, pivots)
	return muzzle.Position, muzzle.LookVector
end

--------------------------------------------------------------------------------
-- Aiming
--------------------------------------------------------------------------------

--- World direction (unit) that puts a shell fired from `origin` at `target` (studs) with muzzle velocity `v` (m/s)
--- and gravity `g` (m/s²); low arc unless `highArc`. Returns (direction, reachable); out of range = the 45° direction.
--- v or g <= 0 aims straight at the target.
function TurretSim.ballisticDirection(
	origin: Vector3,
	target: Vector3,
	v: number,
	g: number,
	highArc: boolean?
): (Vector3, boolean)
	local delta = target - origin
	local dx, dz = delta.X, delta.Z
	local horizStuds = sqrt(dx * dx + dz * dz)
	local len = delta.Magnitude
	if len < 1e-6 then
		return Vector3.new(0, 0, -1), true
	end
	if not (v > 0 and g > 0 and finite(v) and finite(g)) or horizStuds < 1e-4 then
		return delta / len, true
	end
	local x = horizStuds / SPM
	local y = delta.Y / SPM
	local v2 = v * v
	local disc = v2 * v2 - g * (g * x * x + 2 * y * v2)
	local theta: number
	local reachable = true
	if disc < 0 then
		theta = math.pi / 4
		reachable = false
	else
		local root = sqrt(disc)
		theta = if highArc then atan((v2 + root) / (g * x)) else atan((v2 - root) / (g * x))
	end
	local c, s = math.cos(theta), math.sin(theta)
	return Vector3.new(dx / horizStuds * c, s, dz / horizStuds * c), reachable
end

-- Direction in a frame -> (bearing deg, elevation deg).
local function anglesOf(d: Vector3): (number, number)
	local horiz = sqrt(d.X * d.X + d.Z * d.Z)
	return atan2(d.X, -d.Z) / DEG, atan2(d.Y, horiz) / DEG
end

-- Barrel direction in the bearing frame (ring for turrets, trunnion for casemates) for given angles.
local function barrelDirection(bearingDeg: number, pitchDeg: number): Vector3
	local b, p = bearingDeg * DEG, pitchDeg * DEG
	local cp = math.cos(p)
	return Vector3.new(math.sin(b) * cp, math.sin(p), -math.cos(b) * cp)
end

--- Rotates the turret/gun toward `aimPoint` (world studs) for `dt` seconds. `hold` keeps the hull-relative angles
--- (free look). `vehicle` (optional) freezes the turret while overturned/wrecked and adds its mechanic gun bonuses.
--- Returns the bearing speed in deg/s (Dispersion ω_tur).
function TurretSim.step(
	turret: TurretSimState,
	aimPoint: Vector3,
	hold: boolean,
	hullCFrame: CFrame,
	stats: VehicleStats,
	pivots: VehiclePivots,
	dt: number,
	vehicle: VehicleSimState?
): number
	if not (dt > 0) then
		turret.bearingSpeedDegS = 0
		turret.pitchSpeedDegS = 0
		return 0
	end
	local M = Config.Movement
	if dt > M.MAX_DT_S then
		dt = M.MAX_DT_S
	end
	local mods = turret.modifiers
	local casemate = isCasemate(stats)
	local frozen = not mods.enabled
	local depBonus = if finite(mods.depressionBonusDeg) then mods.depressionBonusDeg else 0
	local elevBonus = if finite(mods.elevationBonusDeg) then mods.elevationBonusDeg else 0
	if vehicle ~= nil then
		frozen = frozen or vehicle.overturned or vehicle.wrecked
		depBonus += vehicle.gunDepressionBonusDeg
		elevBonus += vehicle.gunElevationBonusDeg
	end
	local yaw0, gunYaw0, pitch0 = turret.turretYawDeg, turret.gunYawDeg, turret.gunPitchDeg
	local oldBearing = yaw0 + gunYaw0

	-- Desired direction (expressed in the frame the bearing is measured in).
	local ring = hullCFrame * pivots.turretRing
	local baseFrame: CFrame
	local trunnionWorld: CFrame
	if casemate then
		trunnionWorld = ring * pivots.gunTrunnion
		baseFrame = trunnionWorld
	else
		trunnionWorld = ring * CFrame.Angles(0, -yaw0 * DEG, 0) * pivots.gunTrunnion
		baseFrame = ring
	end
	local desiredLocal: Vector3? = nil
	if typeof(aimPoint) == "Vector3" and finiteVector(aimPoint) and finiteVector(trunnionWorld.Position) then
		local highArc = mods.highArc
		if highArc == nil then
			highArc = stats.gun.indirect == true
		end
		-- The shell leaves the muzzle, which lies on the barrel axis `muzzleLength` beyond the trunnion: solve from
		-- the trunnion, then re-solve from the muzzle point that direction implies (drop is quadratic in range).
		local trunnionPos = trunnionWorld.Position
		local muzzleLength = max(0, -pivots.muzzle.Position.Z)
		local origin = trunnionPos
		local dir, reachable = Vector3.zero, true
		for _ = 1, 2 do
			dir, reachable =
				TurretSim.ballisticDirection(origin, aimPoint, mods.shellVelocityMps, mods.shellGravityMps2, highArc)
			if muzzleLength <= 0 then
				break
			end
			origin = trunnionPos + dir * muzzleLength
		end
		local d = baseFrame:VectorToObjectSpace(dir)
		if finiteVector(d) then
			desiredLocal = d
			local bearing, pitch = anglesOf(d)
			if not casemate then
				-- Elevation is measured in the trunnion frame at that bearing (trunnions are usually level).
				local t = (CFrame.Angles(0, -bearing * DEG, 0) * pivots.gunTrunnion.Rotation):VectorToObjectSpace(d)
				local _, p = anglesOf(t)
				pitch = p
			end
			turret.desiredBearingDeg = wrapDeg(bearing)
			turret.desiredPitchDeg = pitch
			turret.reachable = reachable
		end
	end

	-- Traverse.
	local limited, left, right = TurretSim.yawRange(stats)
	local desiredBearing = turret.desiredBearingDeg
	turret.outOfArc = limited and (desiredBearing < -left or desiredBearing > right)
	local rate = nonNegativeOr(stats.turretTraverseDegS, 0) * nonNegativeOr(mods.traverseMul, 1)
	if mods.ring == "Damaged" then
		rate *= M.TURRET_RING_DAMAGED_MUL
	elseif mods.ring == "Destroyed" then
		rate = 0
	end
	if not frozen and not hold then
		local target = desiredBearing
		if limited then
			if target < -left or target > right then
				-- Outside the arc: stop at the nearer limit (angular distance).
				local toLeft = abs(wrapDeg(target + left))
				local toRight = abs(wrapDeg(target - right))
				target = if toLeft < toRight then -left else right
			end
			if casemate then
				turret.gunYawDeg = moveToward(clamp(gunYaw0, -left, right), target, rate * dt)
				turret.turretYawDeg = 0
			else
				turret.turretYawDeg = moveToward(clamp(yaw0, -left, right), target, rate * dt)
				turret.gunYawDeg = 0
			end
		elseif casemate then
			turret.gunYawDeg = approachAngle(gunYaw0, target, rate * dt)
			turret.turretYawDeg = 0
		else
			turret.turretYawDeg = approachAngle(yaw0, target, rate * dt)
			turret.gunYawDeg = 0
		end
	end

	-- Elevation within the limits at the new bearing (the deck lifts the gun even while frozen).
	local bearing = turret.turretYawDeg + turret.gunYawDeg
	local dep, elev = TurretSim.limitsAt(stats, bearing, depBonus, elevBonus)
	local desiredPitch = turret.desiredPitchDeg
	turret.outOfElevation = desiredPitch < -dep or desiredPitch > elev
	if not frozen and not hold then
		local speed = M.GUN_ELEVATION_SPEED_DEGS * nonNegativeOr(mods.elevationSpeedMul, 1)
		if mods.gun == "Damaged" then
			speed *= M.GUN_DAMAGED_ELEVATION_MUL
		end
		turret.gunPitchDeg = moveToward(pitch0, clamp(desiredPitch, -dep, elev), speed * dt)
	end
	turret.gunPitchDeg = clamp(turret.gunPitchDeg, -dep, elev)

	-- Guard, speeds, aim error.
	if not (finite(turret.turretYawDeg) and finite(turret.gunYawDeg) and finite(turret.gunPitchDeg)) then
		turret.turretYawDeg, turret.gunYawDeg, turret.gunPitchDeg = yaw0, gunYaw0, pitch0
	end
	local newBearing = turret.turretYawDeg + turret.gunYawDeg
	turret.bearingSpeedDegS = abs(wrapDeg(newBearing - oldBearing)) / dt
	turret.pitchSpeedDegS = abs(turret.gunPitchDeg - pitch0) / dt
	if desiredLocal ~= nil then
		local barrel: Vector3
		if casemate then
			barrel = barrelDirection(turret.gunYawDeg, turret.gunPitchDeg)
		else
			barrel = (CFrame.Angles(0, -turret.turretYawDeg * DEG, 0) * pivots.gunTrunnion.Rotation):VectorToWorldSpace(
				barrelDirection(0, turret.gunPitchDeg)
			)
		end
		local unit = desiredLocal.Unit
		turret.aimErrorDeg = math.acos(clamp(barrel:Dot(unit), -1, 1)) / DEG
	end
	return turret.bearingSpeedDegS
end

--- True when the barrel is within Config.Movement.ON_TARGET_DEG of the desired direction.
function TurretSim.onTarget(turret: TurretSimState): boolean
	return turret.aimErrorDeg <= Config.Movement.ON_TARGET_DEG
end

--- Suggested hull steer in [-1, 1] for a yaw-limited gun whose desired bearing is outside its arc (casemate TDs turn
--- the hull toward the aim when the player is not steering). 0 when the aim is inside the arc.
function TurretSim.autoHullSteer(turret: TurretSimState, stats: VehicleStats): number
	if not turret.outOfArc then
		return 0
	end
	local limited, left, right = TurretSim.yawRange(stats)
	if not limited then
		return 0
	end
	local desired = turret.desiredBearingDeg
	local excess: number
	if desired > right then
		excess = desired - right
	elseif desired < -left then
		excess = desired + left
	else
		return 0
	end
	return clamp(excess / max(Config.Movement.AUTO_HULL_TURN_FULL_DEG, 1e-3), -1, 1)
end

--- Copies the angles, diagnostics and modifiers of `src` into `dst` (or a new state) for prediction.
function TurretSim.copyState(src: TurretSimState, dst: TurretSimState?): TurretSimState
	local out = dst or TurretSim.newState()
	out.turretYawDeg = src.turretYawDeg
	out.gunYawDeg = src.gunYawDeg
	out.gunPitchDeg = src.gunPitchDeg
	out.bearingSpeedDegS = src.bearingSpeedDegS
	out.pitchSpeedDegS = src.pitchSpeedDegS
	out.desiredBearingDeg = src.desiredBearingDeg
	out.desiredPitchDeg = src.desiredPitchDeg
	out.aimErrorDeg = src.aimErrorDeg
	out.outOfArc = src.outOfArc
	out.outOfElevation = src.outOfElevation
	out.reachable = src.reachable
	local a, b = src.modifiers, out.modifiers
	b.ring = a.ring
	b.gun = a.gun
	b.traverseMul = a.traverseMul
	b.elevationSpeedMul = a.elevationSpeedMul
	b.depressionBonusDeg = a.depressionBonusDeg
	b.elevationBonusDeg = a.elevationBonusDeg
	b.enabled = a.enabled
	b.shellVelocityMps = a.shellVelocityMps
	b.shellGravityMps2 = a.shellGravityMps2
	b.highArc = a.highArc
	return out
end

return TurretSim
