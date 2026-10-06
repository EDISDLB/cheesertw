--!strict
--[[
	VehicleSim — deterministic kinematic tracked/wheeled vehicle model shared by server authority and client prediction
	(ARCHITECTURE §6.1 step 2, §6.2).

	Purpose:          newState(spawnCFrame, options?) / step(state, input, stats, world, dt) -> events. Power-to-weight
	                  acceleration with terrain resistance and traction (00-DECISIONS §6), slope gravity and the climb
	                  limit, top/reverse caps, service and engine braking, hull traverse (pivot, speed and terrain
	                  scaling, wheeled turn radius), module effects (tracks/engine via state.modifiers), ground fit of
	                  pitch/roll from the track contact samples, side slip, falling + Landed events, static obstacles
	                  through world:sweepBox with sliding, map bounds, fording and drowning, overturn rules, and the
	                  sim-placed mechanics (SiegeMode, Hydropneumatic, Wheeled speed mode, Turbo, RocketBoost).
	                  Also: input sanitising for untrusted InputCommands, hull CFrame/velocity helpers, state copies for
	                  prediction/reconciliation and impulse/displacement hooks for the server CollisionSystem.
	Dependencies:     Config (Movement section), Core/Units, Security/InputValidator, Types/Vehicle, Types/VehicleSim,
	                  Types/World. World queries go through the injected `World` only (pure module).
	State:            None at module level except allocation-free scratch numbers; every vehicle owns a VehicleSimState
	                  (kinematics, timers, flags, runtime modifiers, mechanic runtime, pooled events, scratch arrays).
	Validation:       Inputs are sanitised every step (axes clamped to [-1, 1], NaN -> 0); stats are guarded (non-finite
	                  or non-positive mass/power/speeds fall back to safe values); dt is clamped to (0, MAX_DT_S].
	Error handling:   Never throws on finite input. A non-finite result restores the pre-step state, zeroes the
	                  velocities and increments state.nanResets (Invariants assert it stays 0).
	Performance notes: Per step: one ground probe per contact sample (8 + centre; recast only for samples that start
	                  inside geometry), 0–2 sweepBox calls and one waterDepthAt; a resting vehicle re-probes only every
	                  REST_REPROBE_S. No Lua tables are allocated per step: events come from a per-state pool and
	                  scratch arrays live in the state (Vector3/CFrame are value types in Roblox).

	Units: state in studs/radians (see Types/VehicleSim), config and events in real units. Conventions and formulas:
	docs/design/movement.md.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Units = require("../Core/Units")
local InputValidator = require("../Security/InputValidator")
local VehicleTypes = require("../Types/Vehicle")
local SimTypes = require("../Types/VehicleSim")
local WorldTypes = require("../Types/World")

type VehicleStats = VehicleTypes.VehicleStats
type InputCommand = VehicleTypes.InputCommand
type ModuleState = VehicleTypes.ModuleState
type VehiclePivots = VehicleTypes.VehiclePivots
type World = WorldTypes.World
type WorldHit = WorldTypes.WorldHit
type VehicleSimState = SimTypes.VehicleSimState
type VehicleSimOptions = SimTypes.VehicleSimOptions
type VehicleSimModifiers = SimTypes.VehicleSimModifiers
type SimEvent = SimTypes.SimEvent
type SimEventKind = SimTypes.SimEventKind
type MapBounds = SimTypes.MapBounds
type TerrainClass = SimTypes.TerrainClass
type ImmobileReason = SimTypes.ImmobileReason
type MechanicPhase = SimTypes.MechanicPhase

local VehicleSim = {}

local SPM = Units.STUDS_PER_METER -- studs per metre
local KMH = 1 / 3.6 -- km/h -> m/s
local DEG = math.pi / 180
local EVENT_POOL_SIZE = 12
local EPS = 1e-9
local SPEED_EPS = 1e-4 -- m/s: below this a speed is zero
local MAX_SLOPE = 20 -- ground-fit gradient clamp (≈ 87°)

local sin, cos, abs, sqrt, atan, atan2, exp = math.sin, math.cos, math.abs, math.sqrt, math.atan, math.atan2, math.exp
local min, max = math.min, math.max

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function finite(x: number): boolean
	return x == x and x - x == 0
end

local function finiteVector(v: Vector3): boolean
	return finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function positiveOr(x: number?, default: number): number
	if type(x) == "number" and x > 0 and finite(x) then
		return x
	end
	return default
end

local function nonNegativeOr(x: number?, default: number): number
	if type(x) == "number" and x >= 0 and finite(x) then
		return x
	end
	return default
end

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function sign(x: number): number
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	end
	return 0
end

local function axis(x: unknown): number
	if type(x) ~= "number" or not finite(x) then
		return 0
	end
	return clamp(x, -1, 1)
end

-- Wraps radians to (-pi, pi].
local function wrapPi(a: number): number
	local w = (a + math.pi) % (2 * math.pi) - math.pi
	if w == -math.pi then
		return math.pi
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

--- Resistance class of a ground material (Config.Movement.MATERIAL_CLASS; unknown -> DEFAULT_TERRAIN_CLASS).
function VehicleSim.terrainClassOf(material: string?): TerrainClass
	local M = Config.Movement
	local cls = if material ~= nil then M.MATERIAL_CLASS[material] else nil
	if cls == nil then
		cls = M.DEFAULT_TERRAIN_CLASS
	end
	if cls == "hard" then
		return "hard"
	elseif cls == "soft" then
		return "soft"
	end
	return "medium"
end

local function tractionOf(cls: TerrainClass): number
	local t = Config.Movement.TRACTION
	if cls == "hard" then
		return t.hard
	elseif cls == "soft" then
		return t.soft
	end
	return t.medium
end

local function resistanceOf(stats: VehicleStats, cls: TerrainClass): number
	local r = stats.terrainResistance
	if cls == "hard" then
		return positiveOr(r.hard, 1)
	elseif cls == "soft" then
		return positiveOr(r.soft, 1.9)
	end
	return positiveOr(r.medium, 1.1)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function newEvent(): SimEvent
	return {
		kind = "Landed",
		t = 0,
		speedMps = 0,
		normal = Vector3.zero,
		position = Vector3.zero,
		objectId = nil,
		destructible = false,
		inverted = false,
	}
end

--- Neutral runtime modifiers (all modules OK, no multipliers).
function VehicleSim.newModifiers(): VehicleSimModifiers
	return {
		engine = "Ok",
		trackLeft = "Ok",
		trackRight = "Ok",
		lostWheelPairs = 0,
		powerMul = 1,
		topSpeedMul = 1,
		topSpeedBonusKmh = 0,
		reverseSpeedMul = 1,
		speedCapKmh = math.huge,
		hullTraverseMul = 1,
		immobilized = false,
	}
end

--- Square map bounds of `sizeM` metres centred on the origin, in studs.
function VehicleSim.boundsFromSize(sizeM: number): MapBounds
	local half = positiveOr(sizeM, Config.Movement.DEFAULT_MAP_SIZE_M) * SPM / 2
	return { minX = -half, maxX = half, minZ = -half, maxZ = half }
end

local function clampToBounds(p: Vector3, b: MapBounds): Vector3
	local x, z = p.X, p.Z
	if x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ then
		return p
	end
	return Vector3.new(clamp(x, b.minX, b.maxX), p.Y, clamp(z, b.minZ, b.maxZ))
end

--- Creates a state at `spawnCFrame` (position = hull origin; heading from its LookVector, pitch/roll ignored). The
--- vehicle settles onto the ground on its first step (or call VehicleSim.settle).
function VehicleSim.newState(spawnCFrame: CFrame, options: VehicleSimOptions?): VehicleSimState
	local opts: VehicleSimOptions = options or {}
	local look = spawnCFrame.LookVector
	local yaw = 0
	if finite(look.X) and finite(look.Z) and abs(look.X) + abs(look.Z) > 1e-6 then
		yaw = atan2(look.X, -look.Z)
	end
	local bounds = opts.bounds or VehicleSim.boundsFromSize(Config.Movement.DEFAULT_MAP_SIZE_M)
	local position = spawnCFrame.Position
	if not finiteVector(position) then
		position = Vector3.zero
	end
	position = clampToBounds(position, bounds)
	local pool = table.create(EVENT_POOL_SIZE)
	for i = 1, EVENT_POOL_SIZE do
		pool[i] = newEvent()
	end
	local state: VehicleSimState = {
		position = position,
		yaw = yaw,
		pitch = 0,
		roll = 0,
		speed = 0,
		lateralSpeed = 0,
		yawRate = 0,
		verticalVelocity = 0,
		grounded = true,
		groundPitch = 0,
		groundRoll = 0,
		terrainClass = "medium",
		terrainResistance = 1,
		traction = Config.Movement.TRACTION.medium,
		material = "",
		waterDepthM = 0,
		airborneTime = 0,
		submergedTime = 0,
		tiltTime = 0,
		overturnedTime = 0,
		overturned = false,
		drowned = false,
		wrecked = false,
		immobilized = false,
		immobileReason = nil,
		mechanicActive = false,
		gunDepressionBonusDeg = 0,
		gunElevationBonusDeg = 0,
		stillTime = 0,
		modifiers = VehicleSim.newModifiers(),
		mechanic = { kind = "", phase = "Off", timer = 0, charges = 0, lastInput = false },
		bounds = bounds,
		lastInputSeq = 0,
		tick = 0,
		nanResets = 0,
		events = table.create(EVENT_POOL_SIZE),
		_options = opts,
		_geometryReady = false,
		_settled = false,
		_size = Vector3.one,
		_contactX = {},
		_contactZ = {},
		_drownDepthM = 2,
		_sampleH = {},
		_sampleU = {},
		_sampleW = {},
		_sampleOk = {},
		_contact = {},
		_eventPool = pool,
		_restTimer = 0,
		_resting = false,
		_restPosition = position,
		_restYaw = yaw,
		_hydroSettle = 0,
		_mechanicIndex = 0,
		_hydroIndex = 0,
	}
	return state
end

-- Default contact samples: 4 per side on the track centre lines, spread over 85 % of the hull length.
local function defaultContacts(size: Vector3, xs: { number }, zs: { number })
	local tx = size.X * Config.Movement.TRACK_CENTRELINE_FRACTION
	local half = size.Z * 0.5 * 0.85
	for side = -1, 1, 2 do
		for k = 0, 3 do
			table.insert(xs, side * tx)
			table.insert(zs, -half + 2 * half * k / 3)
		end
	end
end

-- Resolves per-vehicle geometry once (collision box, contact samples, drown depth, mechanic indices).
local function ensureGeometry(state: VehicleSimState, stats: VehicleStats)
	if state._geometryReady then
		return
	end
	local M = Config.Movement
	local opts = state._options
	local dims = stats.dimensionsM
	local w = if typeof(dims) == "Vector3" then positiveOr(dims.X, 3) else 3
	local h = if typeof(dims) == "Vector3" then positiveOr(dims.Y, 2) else 2
	local l = if typeof(dims) == "Vector3" then positiveOr(dims.Z, 6) else 6
	local size = Vector3.new(w * SPM, h * SPM, l * SPM)
	local pivots = opts.pivots
	if pivots ~= nil then
		local hs = pivots.hullSize
		if typeof(hs) == "Vector3" and finiteVector(hs) and hs.X > 0 and hs.Y > 0 and hs.Z > 0 then
			size = hs
		end
	end
	state._size = size

	local xs: { number } = {}
	local zs: { number } = {}
	if pivots ~= nil and pivots.trackContacts ~= nil then
		for _, list in { pivots.trackContacts.left, pivots.trackContacts.right } do
			for _, p in list do
				if typeof(p) == "Vector3" and finite(p.X) and finite(p.Z) then
					table.insert(xs, p.X)
					table.insert(zs, p.Z)
				end
			end
		end
	end
	if #xs < 3 then
		table.clear(xs)
		table.clear(zs)
		defaultContacts(size, xs, zs)
	end
	-- Last sample = hull centre (support only: keeps the origin above crests narrower than the sample spacing).
	table.insert(xs, 0)
	table.insert(zs, 0)
	state._contactX = xs
	state._contactZ = zs
	local n = #xs
	state._sampleH = table.create(n, 0)
	state._sampleU = table.create(n, 0)
	state._sampleW = table.create(n, 0)
	state._sampleOk = table.create(n, false)
	state._contact = table.create(n, false)

	local drown = opts.drownDepthM
	if type(drown) == "number" and drown > 0 and finite(drown) then
		state._drownDepthM = drown
	elseif pivots ~= nil and typeof(pivots.turretRing) == "CFrame" and typeof(pivots.viewPoint) == "Vector3" then
		local roof = (pivots.turretRing.Position.Y + pivots.viewPoint.Y) / SPM
		state._drownDepthM = if roof > 0 and finite(roof) then roof else h + M.DEFAULT_TURRET_HEIGHT_M
	else
		state._drownDepthM = h + M.DEFAULT_TURRET_HEIGHT_M
	end

	-- Mechanics placed in VehicleSim (00-DECISIONS §4): one keyed mechanic + passive Hydropneumatic.
	local mech = state.mechanic
	mech.kind = ""
	mech.phase = "Off"
	mech.timer = 0
	mech.charges = 0
	state._mechanicIndex = 0
	state._hydroIndex = 0
	if type(stats.mechanics) == "table" then
		for i, spec in stats.mechanics do
			local kind = spec.kind
			if kind == "Hydropneumatic" then
				if state._hydroIndex == 0 then
					state._hydroIndex = i
				end
			elseif kind == "SiegeMode" or kind == "Wheeled" or kind == "Turbo" or kind == "RocketBoost" then
				if state._mechanicIndex == 0 then
					state._mechanicIndex = i
					mech.kind = kind
					mech.charges = math.huge
					if spec.kind == "RocketBoost" then
						mech.charges = nonNegativeOr(spec.charges, 0)
					end
				end
			end
		end
	end
	state.terrainResistance = resistanceOf(stats, state.terrainClass)
	state._geometryReady = true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function pushEvent(state: VehicleSimState, kind: SimEventKind): SimEvent
	local events = state.events
	local n = #events
	local pool = state._eventPool
	local e: SimEvent
	if n >= EVENT_POOL_SIZE then
		e = pool[EVENT_POOL_SIZE] -- unreachable in practice (≤ 7 events per step); overwrite the last record
	else
		e = pool[n + 1]
		events[n + 1] = e
	end
	e.kind = kind
	e.t = 0
	e.speedMps = 0
	e.normal = Vector3.zero
	e.position = state.position
	e.objectId = nil
	e.destructible = false
	e.inverted = false
	return e
end

--------------------------------------------------------------------------------
-- Ground probing and fitting
--------------------------------------------------------------------------------

-- Per-step scratch shared by the helpers below (single-threaded module; reset before use).
local probeResistance = 0
local probeTraction = 0
local probeTrack = 0
local probeHardCount = 0
local probeMediumCount = 0
local probeSoftCount = 0
local probeCentreMaterial = ""

-- Samples the ground under every contact for a pose. Writes H/U/W/Ok scratch; returns the number of valid samples.
local function probe(
	state: VehicleSimState,
	stats: VehicleStats,
	world: World,
	px: number,
	py: number,
	pz: number,
	yaw: number,
	pitch: number,
	roll: number,
	probeUp: number,
	recastUp: number
): number
	local xs, zs = state._contactX, state._contactZ
	local H, U, W, OK = state._sampleH, state._sampleU, state._sampleW, state._sampleOk
	local n = #xs
	local cy, sy = cos(yaw), sin(yaw)
	local sp, cp = sin(pitch), cos(pitch)
	local sr, cr = sin(roll), cos(roll)
	local valid = 0
	probeResistance, probeTraction, probeTrack = 0, 0, 0
	probeHardCount, probeMediumCount, probeSoftCount = 0, 0, 0
	probeCentreMaterial = ""
	for i = 1, n do
		local x, z = xs[i], zs[i]
		-- Hull-space (x, 0, z) rotated by Rx(pitch)·Rz(roll), expressed in the yaw frame (right, up, back).
		local lx = x * cr
		local ly = x * sr * cp - z * sp
		local lz = x * sr * sp + z * cp
		local wx = px + cy * lx - sy * lz
		local wz = pz + sy * lx + cy * lz
		U[i] = lx
		W[i] = lz
		local fromY = py + ly + probeUp
		local hit = world:groundAt(wx, wz, fromY)
		if hit == nil then
			-- The probe started inside geometry (terrain wall, rising bank) or above a void: look from high up.
			hit = world:groundAt(wx, wz, fromY + recastUp)
		end
		if hit ~= nil and finite(hit.position.Y) then
			H[i] = hit.position.Y
			OK[i] = true
			valid += 1
			if i < n then
				local cls: TerrainClass = VehicleSim.terrainClassOf(hit.material)
				probeResistance += resistanceOf(stats, cls)
				probeTraction += tractionOf(cls)
				probeTrack += 1
				if cls == "hard" then
					probeHardCount += 1
				elseif cls == "soft" then
					probeSoftCount += 1
				else
					probeMediumCount += 1
				end
			else
				probeCentreMaterial = hit.material
			end
		else
			OK[i] = false
			H[i] = 0
		end
	end
	return valid
end

-- Height the hull origin must have so no valid sample is above its contact point, for attitude (pitch, roll).
local function restHeight(state: VehicleSimState, pitch: number, roll: number): number
	local xs, zs = state._contactX, state._contactZ
	local H, OK = state._sampleH, state._sampleOk
	local sp, cp, sr = sin(pitch), cos(pitch), sin(roll)
	local best = -math.huge
	for i = 1, #xs do
		if OK[i] then
			local ly = xs[i] * sr * cp - zs[i] * sp
			local y = H[i] - ly
			if y > best then
				best = y
			end
		end
	end
	return best
end

-- Least-squares plane h = h0 + gx·u + gz·w through the track samples in contact (valid and not more than `range`
-- below their predicted contact height). Returns (hasGx, gx, hasGz, gz).
local function fitPlane(
	state: VehicleSimState,
	predictedY: number,
	pitch: number,
	roll: number,
	range: number
): (boolean, number, boolean, number)
	local xs, zs = state._contactX, state._contactZ
	local H, U, W, OK, C = state._sampleH, state._sampleU, state._sampleW, state._sampleOk, state._contact
	local n = #xs - 1 -- the centre sample supports but does not orient the hull
	local sp, cp, sr = sin(pitch), cos(pitch), sin(roll)
	local m, su, sw, sh = 0, 0, 0, 0
	for i = 1, n do
		local inContact = false
		if OK[i] then
			local ly = xs[i] * sr * cp - zs[i] * sp
			if H[i] >= predictedY + ly - range then
				inContact = true
				m += 1
				su += U[i]
				sw += W[i]
				sh += H[i]
			end
		end
		C[i] = inContact
	end
	if m < 2 then
		return false, 0, false, 0
	end
	local mu, mw, mh = su / m, sw / m, sh / m
	local suu, sww, suw, suh, swh = 0, 0, 0, 0, 0
	for i = 1, n do
		if C[i] then
			local du, dw, dh = U[i] - mu, W[i] - mw, H[i] - mh
			suu += du * du
			sww += dw * dw
			suw += du * dw
			suh += du * dh
			swh += dw * dh
		end
	end
	local spread = 1e-4
	local hasU, hasW = suu > spread, sww > spread
	if hasU and hasW and m >= 3 then
		local det = suu * sww - suw * suw
		if det > 1e-6 * suu * sww then
			local gx = (suh * sww - swh * suw) / det
			local gz = (swh * suu - suh * suw) / det
			return true, clamp(gx, -MAX_SLOPE, MAX_SLOPE), true, clamp(gz, -MAX_SLOPE, MAX_SLOPE)
		end
	end
	-- Degenerate contact set (one side only, one row only): orient along the axis that is determined.
	if hasW and not hasU then
		return false, 0, true, clamp(swh / sww, -MAX_SLOPE, MAX_SLOPE)
	elseif hasU and not hasW then
		return true, clamp(suh / suu, -MAX_SLOPE, MAX_SLOPE), false, 0
	end
	return false, 0, false, 0
end

-- Tait-Bryan YXZ attitude of a plane with gradients (gx right, gz back): pitch = atan(-gz),
-- roll = atan(gx / sqrt(1 + gz²)) (see docs/design/movement.md "Ground fit").
local function attitudeOf(gx: number, gz: number): (number, number)
	return atan(-gz), atan(gx / sqrt(1 + gz * gz))
end

-- Updates the cached terrain coefficients from the last probe.
local function applyTerrain(state: VehicleSimState, stats: VehicleStats)
	if probeTrack > 0 then
		state.terrainResistance = probeResistance / probeTrack
		state.traction = probeTraction / probeTrack
		if probeHardCount >= probeMediumCount and probeHardCount >= probeSoftCount then
			state.terrainClass = "hard"
		elseif probeSoftCount > probeMediumCount then
			state.terrainClass = "soft"
		else
			state.terrainClass = "medium"
		end
	end
	if probeCentreMaterial ~= "" then
		state.material = probeCentreMaterial
	end
	local M = Config.Movement
	if state.waterDepthM >= M.WATER_EFFECT_MIN_DEPTH_M then
		state.terrainResistance = resistanceOf(stats, "soft") * M.WATER_RESISTANCE_MUL
		state.traction = tractionOf("soft")
	end
end

local function updateWater(state: VehicleSimState, world: World)
	local depth = world:waterDepthAt(state.position)
	if type(depth) ~= "number" or not finite(depth) or depth < 0 then
		depth = 0
	end
	state.waterDepthM = depth / SPM
end

-- Places the vehicle on the ground under its current x/z (spawn, teleports): attitude snaps to the fit.
local function settle(state: VehicleSimState, stats: VehicleStats, world: World)
	local M = Config.Movement
	local p = state.position
	local up = M.SETTLE_PROBE_UP_M * SPM
	state._settled = true
	local pitch, roll = 0, 0
	-- Every valid sample counts as a contact (the spawn height is not trusted). The samples' horizontal offsets
	-- depend on the attitude, so the fit is iterated until probe and attitude agree.
	for _ = 1, 3 do
		local valid = probe(state, stats, world, p.X, p.Y, p.Z, state.yaw, pitch, roll, up, up)
		if valid == 0 then
			state.grounded = false
			return
		end
		local hasGx, gx, hasGz, gz = fitPlane(state, restHeight(state, pitch, roll), pitch, roll, math.huge)
		pitch, roll = attitudeOf(if hasGx then gx else 0, if hasGz then gz else 0)
	end
	state.pitch, state.roll = pitch, roll
	state.groundPitch, state.groundRoll = pitch, roll
	state.position = Vector3.new(p.X, restHeight(state, pitch, roll), p.Z)
	state.grounded = true
	state.verticalVelocity = 0
	updateWater(state, world)
	applyTerrain(state, stats)
	state._resting = false
end

--- Snaps the vehicle onto the ground at its current x/z (spawns, teleports). step() does this automatically on the
--- first call; call it explicitly to place a vehicle before its first tick.
function VehicleSim.settle(state: VehicleSimState, stats: VehicleStats, world: World)
	ensureGeometry(state, stats)
	settle(state, stats, world)
end

--------------------------------------------------------------------------------
-- Mechanics (SiegeMode, Hydropneumatic, Wheeled speed mode, Turbo, RocketBoost)
--------------------------------------------------------------------------------

-- Mobility modifier accumulator for the current step (reset by resetMobility; allocation-free).
local accPowerMul = 1
local accTopAdd = 0
local accTopMul = 1
local accRevAdd = 0
local accRevMul = 1
local accTravAdd = 0
local accTravMul = 1
local accDepAdd = 0
local accElevAdd = 0
local accSpeedCap = math.huge
local accExtraAccel = 0
local accSteerMul = 1
local accTravelReverseRatio = 0 -- SiegeMode travel mode: reverse = forward × ratio (0 = unused)

local function resetMobility()
	accPowerMul, accTopAdd, accTopMul, accRevAdd, accRevMul = 1, 0, 1, 0, 1
	accTravAdd, accTravMul, accDepAdd, accElevAdd = 0, 1, 0, 0
	accSpeedCap, accExtraAccel, accSteerMul, accTravelReverseRatio = math.huge, 0, 1, 0
end

-- Folds the mobility-relevant StatModifiers of `list` (all of them, or only those with `condition`).
local function accumulate(list: { any }?, condition: string?)
	if type(list) ~= "table" then
		return
	end
	for _, m in list do
		local cond = m.condition or "Always"
		if condition == nil or cond == condition then
			local value = m.value
			if type(value) == "number" and finite(value) then
				local stat, add = m.stat, m.op == "add"
				if stat == "enginePower" then
					if add then
						accPowerMul += value -- additive power shares (e.g. +0.05) behave as multipliers here
					else
						accPowerMul *= value
					end
				elseif stat == "topSpeed" then
					if add then
						accTopAdd += value
					else
						accTopMul *= value
					end
				elseif stat == "reverseSpeed" then
					if add then
						accRevAdd += value
					else
						accRevMul *= value
					end
				elseif stat == "hullTraverse" then
					if add then
						accTravAdd += value
					else
						accTravMul *= value
					end
				elseif stat == "gunDepression" and add then
					accDepAdd += value
				elseif stat == "gunElevation" and add then
					accElevAdd += value
				end
			end
		end
	end
end

local function setPhase(state: VehicleSimState, phase: MechanicPhase, timer: number)
	local mech = state.mechanic
	if mech.phase ~= phase then
		mech.phase = phase
		mech.timer = timer
		local e = pushEvent(state, "MechanicChanged")
		e.t = timer
	else
		mech.timer = timer
	end
end

-- Advances the keyed mechanic (edge-triggered by InputCommand.mechanic) and the passive Hydropneumatic settle, and
-- accumulates their mobility/gun effects for this step.
local function updateMechanics(state: VehicleSimState, stats: VehicleStats, pressed: boolean, dt: number)
	resetMobility()
	local mech = state.mechanic
	local edge = pressed and not mech.lastInput
	mech.lastInput = pressed
	state.mechanicActive = false
	local mechanics = stats.mechanics
	local spec = if state._mechanicIndex > 0 and type(mechanics) == "table"
		then mechanics[state._mechanicIndex]
		else nil
	if spec ~= nil then
		local phase = mech.phase
		if spec.kind == "SiegeMode" or spec.kind == "Wheeled" then
			local onS, offS
			if spec.kind == "SiegeMode" then
				onS, offS = nonNegativeOr(spec.engageS, 2), nonNegativeOr(spec.disengageS, 1.25)
			else
				onS = nonNegativeOr(spec.toggleS, 1)
				offS = onS
			end
			if phase == "Off" then
				if edge and not state.wrecked then
					setPhase(state, "Engaging", onS)
				end
			elseif phase == "On" then
				if edge then
					setPhase(state, "Disengaging", offS)
				end
			elseif phase == "Engaging" or phase == "Disengaging" then
				mech.timer -= dt
			end
			if mech.phase == "Engaging" and mech.timer <= EPS then
				setPhase(state, "On", 0)
			elseif mech.phase == "Disengaging" and mech.timer <= EPS then
				setPhase(state, "Off", 0)
			end
			local p = mech.phase
			state.mechanicActive = p == "On"
			if spec.kind == "SiegeMode" then
				if p ~= "Off" then
					accSpeedCap = min(accSpeedCap, positiveOr(spec.maxSpeedKmh, 10))
				else
					local ratio = spec.travelReverseRatio
					if type(ratio) == "number" and ratio > 0 and finite(ratio) then
						accTravelReverseRatio = ratio
					end
				end
				if p == "On" then
					accumulate(spec.modifiers, nil)
				end
			end
		elseif spec.kind == "Turbo" or spec.kind == "RocketBoost" then
			if phase == "Off" then
				if edge and not state.wrecked and mech.charges >= 1 then
					if spec.kind == "RocketBoost" then
						mech.charges -= 1
					end
					setPhase(state, "On", nonNegativeOr(spec.durationS, 0))
				end
			elseif phase == "On" then
				mech.timer -= dt
				if mech.timer <= EPS then
					setPhase(state, "Cooldown", nonNegativeOr(spec.cooldownS, 0))
				end
			elseif phase == "Cooldown" then
				mech.timer -= dt
				if mech.timer <= EPS then
					setPhase(state, "Off", 0)
				end
			end
			if mech.phase == "On" then
				state.mechanicActive = true
				if spec.kind == "Turbo" then
					accPowerMul *= positiveOr(spec.powerMul, 1)
				else
					accTopAdd += nonNegativeOr(spec.speedBonusKmh, 0)
					accExtraAccel += Config.Movement.ROCKET_BOOST_ACCEL_MPS2
				end
			end
		end
	end
	-- Passive Hydropneumatic: gun bonuses after `settleS` stationary.
	local hydro = if state._hydroIndex > 0 and type(mechanics) == "table" then mechanics[state._hydroIndex] else nil
	if hydro ~= nil and hydro.kind == "Hydropneumatic" then
		if state.stillTime >= nonNegativeOr(hydro.settleS, 0.75) - EPS and state.grounded then
			accDepAdd += nonNegativeOr(hydro.depressionBonusDeg, 0)
			accElevAdd += nonNegativeOr(hydro.elevationBonusDeg, 0)
		end
	end
	-- Conditional modifiers owned by the sim ("MechanicActive" mobility stats).
	if state.mechanicActive then
		accumulate(stats.conditionalModifiers, "MechanicActive")
	end
	-- Wheeled speed mode steering.
	if spec ~= nil and spec.kind == "Wheeled" and mech.phase == "On" then
		local wheeled = stats.wheeled
		accSteerMul = if wheeled ~= nil
			then positiveOr(wheeled.speedModeSteeringMul, 1)
			else positiveOr(spec.speedModeSteeringMul, 1)
	end
	state.gunDepressionBonusDeg = accDepAdd
	state.gunElevationBonusDeg = accElevAdd
end

--------------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------------

local function immobileReasonOf(state: VehicleSimState, stats: VehicleStats): ImmobileReason?
	if state.wrecked then
		return if state.drowned then "Drowned" else "Wrecked"
	elseif state.drowned then
		return "Drowned"
	elseif state.overturned then
		return "Overturned"
	end
	local mods = state.modifiers
	if mods.engine == "Destroyed" then
		return "Engine"
	end
	local wheeled = stats.wheeled
	if wheeled == nil then
		if mods.trackLeft == "Destroyed" or mods.trackRight == "Destroyed" then
			return "Tracks"
		end
	elseif mods.lostWheelPairs >= positiveOr(wheeled.wheelPairs, 4) then
		return "Tracks"
	end
	if mods.immobilized then
		return "External"
	end
	return nil
end

--- Forward (top) and reverse speed caps in m/s for the current modifiers, mechanic and water.
local function speedCaps(state: VehicleSimState, stats: VehicleStats): (number, number)
	local M = Config.Movement
	local mods = state.modifiers
	local top = nonNegativeOr(stats.topSpeedKmh, 0)
	local rev = stats.reverseSpeedKmh
	if not (type(rev) == "number" and rev > 0 and finite(rev)) then
		rev = clamp(top * M.REVERSE_DEFAULT_RATIO, M.REVERSE_MIN_KMH, M.REVERSE_MAX_KMH)
	end
	local wheeled = stats.wheeled
	local mech = state.mechanic
	if wheeled ~= nil and mech.kind == "Wheeled" and mech.phase == "On" then
		top = nonNegativeOr(wheeled.speedModeTopSpeedKmh, top)
		rev = nonNegativeOr(wheeled.speedModeReverseKmh, rev)
	end
	if accTravelReverseRatio > 0 then
		rev = top * accTravelReverseRatio -- SiegeMode travel mode
	end
	top = (top + accTopAdd + nonNegativeOr(mods.topSpeedBonusKmh, 0)) * accTopMul * nonNegativeOr(mods.topSpeedMul, 1)
	rev = (rev + accRevAdd) * accRevMul * nonNegativeOr(mods.reverseSpeedMul, 1)
	if wheeled ~= nil and mods.lostWheelPairs > 0 then
		local f = nonNegativeOr(wheeled.lostPairSpeedMul, 0.75) ^ mods.lostWheelPairs
		top *= f
		rev *= f
	end
	if state.waterDepthM >= M.WATER_EFFECT_MIN_DEPTH_M then
		top *= M.WATER_SPEED_MUL
		rev *= M.WATER_SPEED_MUL
	end
	local cap = min(nonNegativeOr(mods.speedCapKmh, math.huge), accSpeedCap, M.ABSOLUTE_MAX_SPEED_KMH)
	top = clamp(top, 0, cap)
	rev = clamp(rev, 0, cap)
	return top * KMH, rev * KMH
end

local function enginePowerWatts(state: VehicleSimState, stats: VehicleStats): number
	local M = Config.Movement
	local mods = state.modifiers
	if mods.engine == "Destroyed" then
		return 0
	end
	local p = nonNegativeOr(stats.enginePowerHp, 0) * M.WATTS_PER_HP * nonNegativeOr(mods.powerMul, 1) * accPowerMul
	if mods.engine == "Damaged" then
		p *= M.ENGINE_DAMAGED_POWER_MUL
	end
	return max(0, p)
end

--------------------------------------------------------------------------------
-- Dynamics
--------------------------------------------------------------------------------

-- Longitudinal speed (m/s along the hull forward axis) after dt on the ground (00-DECISIONS §6):
--   a = min(P/(m·max(|v|, v0)), μ·g·cosθ) − g·(0.10·R·cosθ + sinθ), capped by the speed caps.
local function longitudinal(
	state: VehicleSimState,
	stats: VehicleStats,
	throttle: number,
	brake: boolean,
	immobile: boolean,
	topCap: number,
	revCap: number,
	dt: number
): number
	local M = Config.Movement
	local g = M.GRAVITY_MPS2
	local v = state.speed / SPM
	if abs(v) < SPEED_EPS then
		v = 0
	end
	local pitch = state.pitch
	local sp, cp = sin(pitch), cos(pitch)
	local cpAbs = abs(cp)
	local gAlong = -g * sp
	local tractionMax = state.traction * g * cpAbs
	local resist = g * M.ROLLING_RESISTANCE * state.terrainResistance * cpAbs
	local mass = positiveOr(stats.massKg, 1000)
	local drive = 0 -- signed tractive acceleration
	local opposing = resist -- magnitude opposing the motion
	local dir = sign(throttle)
	local driving = false
	local cap = 0
	if immobile or brake then
		opposing += min(M.BRAKE_DECEL_MPS2, tractionMax)
	elseif dir ~= 0 then
		if v * dir < 0 then
			opposing += min(M.BRAKE_DECEL_MPS2 * abs(throttle), tractionMax)
		else
			cap = (if dir > 0 then topCap else revCap) * abs(throttle)
			local climbLimit = M.MAX_CLIMB_DEG * DEG
			local uphill = dir * state.groundPitch
			if uphill > climbLimit or dir * pitch > climbLimit then
				-- Too steep to climb: no drive force uphill (REG-VEH-03); the tracks still hold.
				cap = 0
			end
			if abs(v) < cap then
				local power = enginePowerWatts(state, stats)
				local a = power / (mass * max(abs(v), M.MIN_POWER_SPEED_MPS))
				drive = dir * (min(a, tractionMax) + (if dir > 0 then accExtraAccel else 0))
				driving = true
			elseif abs(v) > cap + SPEED_EPS then
				opposing += min(M.ENGINE_BRAKE_DECEL_MPS2, tractionMax)
			end
		end
	else
		opposing += min(M.ENGINE_BRAKE_DECEL_MPS2, tractionMax)
	end

	local vNew: number
	if v ~= 0 then
		local a = drive + gAlong - sign(v) * opposing
		vNew = v + a * dt
		if sign(vNew) ~= sign(v) then
			vNew = 0 -- the opposing forces stop the vehicle; static hold is evaluated next step
		end
		-- Driving never overshoots the throttle cap; engine braking toward it never undershoots it.
		local overshoot = driving and dir * vNew > cap and dir * v <= cap + SPEED_EPS
		local undershoot = not driving and dir ~= 0 and dir * v > cap and dir * vNew < cap
		if overshoot or undershoot then
			vNew = dir * cap
		end
	else
		local net = drive + gAlong
		-- Static hold: rolling resistance must be overcome to start; when the net force acts against the throttle
		-- (stalled uphill) or nothing drives, the locked tracks also hold up to their traction.
		local hold = resist
		if not driving or sign(net) ~= dir then
			hold += tractionMax
		end
		if abs(net) <= hold then
			vNew = 0
		else
			vNew = (net - sign(net) * hold) * dt
			if driving and dir * vNew > cap then
				vNew = dir * cap
			end
		end
	end
	-- Hard caps ("capped by top speeds"): gravity never pushes a vehicle past them.
	return clamp(vNew, -revCap, topCap) * SPM
end

-- Side slip (m/s along the hull right axis): gravity across the slope against track friction.
local function lateral(state: VehicleSimState, dt: number): number
	local M = Config.Movement
	local g = M.GRAVITY_MPS2
	local v = state.lateralSpeed / SPM
	if abs(v) < SPEED_EPS then
		v = 0
	end
	local gSide = -g * sin(state.roll) * cos(state.pitch)
	local friction = state.traction * g * abs(cos(state.roll) * cos(state.pitch)) * M.LATERAL_FRICTION_MUL
	local vNew: number
	if v ~= 0 then
		vNew = v + (gSide - sign(v) * friction) * dt
		if sign(vNew) ~= sign(v) then
			vNew = 0
		end
	elseif abs(gSide) > friction then
		vNew = (gSide - sign(gSide) * friction) * dt
	else
		vNew = 0
	end
	local limit = M.ABSOLUTE_MAX_SPEED_KMH * KMH
	return clamp(vNew, -limit, limit) * SPM
end

-- Yaw rate (rad/s) after dt: tracks pivot at the full rate, scaled by terrain (R_hard / R) and speed (×1 → ×0.6 at
-- top speed); wheels turn on their radius.
local function yawDynamics(
	state: VehicleSimState,
	stats: VehicleStats,
	steer: number,
	brake: boolean,
	immobile: boolean,
	topCap: number,
	dt: number
): number
	local M = Config.Movement
	local base = nonNegativeOr(stats.hullTraverseDegS, 0) * DEG
	local mods = state.modifiers
	local traverseMul = nonNegativeOr(mods.hullTraverseMul, 1) * accTravMul
	local baseRate = max(0, base * traverseMul + accTravAdd * DEG)
	local target = 0
	if not immobile and not brake and steer ~= 0 then
		local rHard = resistanceOf(stats, "hard")
		local terrainMul = clamp(rHard / max(state.terrainResistance, 1e-3), 0, 1)
		local v = abs(state.speed / SPM)
		local speedFrac = if topCap > 0 then clamp(v / topCap, 0, 1) else 0
		local speedMul = 1 + (M.HULL_TRAVERSE_TOP_SPEED_MUL - 1) * speedFrac
		local maxRate = baseRate * terrainMul * speedMul * accSteerMul
		local wheeled = stats.wheeled
		if wheeled ~= nil then
			local radius = positiveOr(wheeled.turnRadiusM, 8)
			maxRate = min(maxRate, v / radius)
		end
		target = steer * maxRate
	end
	local accel = max(baseRate, base) / max(M.HULL_TRAVERSE_RESPONSE_S, 1e-3)
	return moveToward(state.yawRate, target, accel * dt)
end

--------------------------------------------------------------------------------
-- Movement and collisions
--------------------------------------------------------------------------------

local function hullCFrameOf(position: Vector3, yaw: number, pitch: number, roll: number): CFrame
	return CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, -yaw, roll)
end

-- Obstacle sweep box: the hull footprint from STEP_HEIGHT_M up to the hull roof (lower boxes are driven over).
local function sweepFrame(state: VehicleSimState, position: Vector3, yaw: number, stepUp: number): (CFrame, Vector3)
	local size = state._size
	local bottom = min(stepUp, size.Y * 0.8)
	local height = size.Y - bottom
	local cf = hullCFrameOf(position, yaw, state.pitch, state.roll) * CFrame.new(0, bottom + height / 2, 0)
	return cf, Vector3.new(size.X, height, size.Z)
end

local function horizontalUnit(v: Vector3): Vector3?
	local x, z = v.X, v.Z
	local len = sqrt(x * x + z * z)
	if len < 1e-6 or not finite(len) then
		return nil
	end
	return Vector3.new(x / len, 0, z / len)
end

-- Removes (or for destructibles, mostly keeps) the velocity component into an obstacle with horizontal normal `n`.
-- Returns the closing speed in m/s (0 when moving away).
local function obstacleResponse(state: VehicleSimState, n: Vector3, keep: number): number
	local yaw = state.yaw
	local cy, sy = cos(yaw), sin(yaw)
	local cp = cos(state.pitch)
	local vH = state.speed * cp
	local lat = state.lateralSpeed
	local vx = sy * vH + cy * lat
	local vz = -cy * vH + sy * lat
	local vn = vx * n.X + vz * n.Z
	if vn >= 0 then
		return 0
	end
	local remove = vn * (1 - keep)
	vx -= n.X * remove
	vz -= n.Z * remove
	local fwd = vx * sy - vz * cy
	state.speed = fwd / max(cp, 0.05)
	state.lateralSpeed = vx * cy + vz * sy
	return -vn / SPM
end

local function reportObstacle(state: VehicleSimState, n: Vector3, closing: number, hit: WorldHit?)
	local M = Config.Movement
	local destructible = hit ~= nil and hit.destructible == true
	if destructible or closing >= M.OBSTACLE_EVENT_MIN_MPS then
		local e = pushEvent(state, "Obstacle")
		e.normal = n
		e.speedMps = closing
		e.position = if hit ~= nil then hit.position else state.position
		e.objectId = if hit ~= nil then hit.objectId else nil
		e.destructible = destructible
	end
end

-- Moves the hull horizontally by `disp` at heading `newYaw`, sweeping static obstacles (with one slide) and the map
-- edge. Mutates state.position (x/z), state.yaw, speeds; returns nothing.
local function moveHorizontal(state: VehicleSimState, world: World, disp: Vector3, newYaw: number, dt: number)
	local M = Config.Movement
	local stepUp = M.STEP_HEIGHT_M * SPM
	local skin = M.OBSTACLE_SKIN_M * SPM
	local pos = state.position
	local yaw = state.yaw
	local len = disp.Magnitude
	local rotating = newYaw ~= yaw
	if len < 1e-6 and not rotating then
		return
	end
	local cf, size = sweepFrame(state, pos, newYaw, stepUp)
	local hit = world:sweepBox(cf, size, disp)
	if hit ~= nil and hit.distance <= 0 and rotating then
		-- Overlapping at the new heading: if the old heading is free, the rotation is what collides.
		local cfOld = sweepFrame(state, pos, yaw, stepUp)
		local hitOld = world:sweepBox(cfOld, size, disp)
		if hitOld == nil or hitOld.distance > 0 then
			newYaw = yaw
			state.yawRate = 0
			hit = hitOld
		end
	end
	state.yaw = wrapPi(newYaw)
	if hit == nil then
		pos += disp
	elseif hit.distance <= 0 then
		-- Already overlapping (pushed in by another vehicle, object appeared): allow motion away and push out.
		local n = horizontalUnit(hit.normal) or (if len > 1e-6 then -disp / len else Vector3.xAxis)
		local d = disp
		local into = d.X * n.X + d.Z * n.Z
		if into < 0 then
			d -= n * into
		end
		pos += d + n * (M.DEPENETRATION_SPEED_MPS * SPM * dt)
		local closing = obstacleResponse(state, n, if hit.destructible then M.DESTRUCTIBLE_SPEED_KEEP else 0)
		reportObstacle(state, n, closing, hit)
	else
		local dir = disp / len
		local travel = max(0, hit.distance - skin)
		pos += dir * travel
		local n = horizontalUnit(hit.normal) or -dir
		local keep = if hit.destructible then M.DESTRUCTIBLE_SPEED_KEEP else 0
		local closing = obstacleResponse(state, n, keep)
		reportObstacle(state, n, closing, hit)
		if not hit.destructible then
			-- Slide: the rest of the displacement without its component into the obstacle.
			local rem = disp - dir * travel
			local into = rem.X * n.X + rem.Z * n.Z
			if into < 0 then
				rem -= n * into
			end
			local remLen = rem.Magnitude
			if remLen > 1e-4 then
				local cf2, size2 = sweepFrame(state, pos, state.yaw, stepUp)
				local hit2 = world:sweepBox(cf2, size2, rem)
				if hit2 == nil then
					pos += rem
				elseif hit2.distance > 0 then
					pos += rem / remLen * max(0, hit2.distance - skin)
					local n2 = horizontalUnit(hit2.normal) or -rem / remLen
					local closing2 = obstacleResponse(state, n2, 0)
					reportObstacle(state, n2, closing2, hit2)
				end
			end
		end
	end
	-- Map edge (red line): clamp and cancel the outward velocity.
	local b = state.bounds
	if pos.X < b.minX then
		pos = Vector3.new(b.minX, pos.Y, pos.Z)
		obstacleResponse(state, Vector3.xAxis, 0)
	elseif pos.X > b.maxX then
		pos = Vector3.new(b.maxX, pos.Y, pos.Z)
		obstacleResponse(state, -Vector3.xAxis, 0)
	end
	if pos.Z < b.minZ then
		pos = Vector3.new(pos.X, pos.Y, b.minZ)
		obstacleResponse(state, Vector3.zAxis, 0)
	elseif pos.Z > b.maxZ then
		pos = Vector3.new(pos.X, pos.Y, b.maxZ)
		obstacleResponse(state, -Vector3.zAxis, 0)
	end
	state.position = pos
end

--------------------------------------------------------------------------------
-- Status timers (water, overturn, stillness)
--------------------------------------------------------------------------------

local function updateDrowning(state: VehicleSimState, dt: number)
	local M = Config.Movement
	if state.waterDepthM >= state._drownDepthM then
		if state.submergedTime <= 0 then
			local e = pushEvent(state, "Drowning")
			e.t = M.DROWN_TIME_S
		end
		state.submergedTime += dt
		if state.submergedTime >= M.DROWN_TIME_S - 1e-6 then
			state.drowned = true
			state.wrecked = true
			pushEvent(state, "Drowned")
		end
	elseif state.submergedTime > 0 then
		state.submergedTime = 0
		pushEvent(state, "DrowningEnded")
	end
end

local function tiltDeg(pitch: number, roll: number): number
	return math.acos(clamp(cos(pitch) * cos(roll), -1, 1)) / DEG
end

local function updateOverturn(state: VehicleSimState, dt: number)
	if state.wrecked then
		return
	end
	local M = Config.Movement
	local destroyRule = M.OVERTURN_RULE == "Destroy"
	if not state.overturned then
		if tiltDeg(state.pitch, state.roll) > M.OVERTURN_DEG then
			state.tiltTime += dt
		else
			state.tiltTime = 0
		end
		if state.tiltTime >= M.OVERTURN_TIME_S - 1e-6 then
			state.overturned = true
			state.overturnedTime = 0
			local e = pushEvent(state, "Overturned")
			e.t = if destroyRule then M.OVERTURN_DESTROY_S else M.SELF_RIGHT_S
		end
	else
		state.overturnedTime += dt
		if destroyRule then
			if state.overturnedTime >= M.OVERTURN_DESTROY_S - 1e-6 then
				state.wrecked = true
				pushEvent(state, "OverturnDestroyed")
			end
		elseif state.overturnedTime >= M.SELF_RIGHT_S - 1e-6 then
			state.overturned = false
			state.overturnedTime = 0
			state.tiltTime = 0
			state.pitch = state.groundPitch
			state.roll = state.groundRoll
			state.speed = 0
			state.lateralSpeed = 0
			state.yawRate = 0
			state._resting = false
			pushEvent(state, "Righted")
		end
	end
end

local function updateStill(state: VehicleSimState, dt: number)
	local M = Config.Movement
	local still = abs(state.speed / SPM) < M.STILL_SPEED_KMH * KMH and abs(state.yawRate) < M.STILL_YAW_DEGS * DEG
	if still and state.grounded then
		state.stillTime += dt
	else
		state.stillTime = 0
	end
end

--------------------------------------------------------------------------------
-- Step
--------------------------------------------------------------------------------

local function stateFinite(state: VehicleSimState): boolean
	return finiteVector(state.position)
		and finite(state.yaw)
		and finite(state.pitch)
		and finite(state.roll)
		and finite(state.speed)
		and finite(state.lateralSpeed)
		and finite(state.yawRate)
		and finite(state.verticalVelocity)
		and finite(state.groundPitch)
		and finite(state.groundRoll)
end

--- Advances the vehicle by `dt` seconds with `input`. Returns the events of this step (pooled list owned by the
--- state: read it before stepping the same vehicle again).
function VehicleSim.step(
	state: VehicleSimState,
	input: InputCommand,
	stats: VehicleStats,
	world: World,
	dt: number
): { SimEvent }
	local events = state.events
	table.clear(events)
	if state.wrecked or not (dt > 0) then
		return events
	end
	local M = Config.Movement
	if dt > M.MAX_DT_S then
		dt = M.MAX_DT_S
	end
	ensureGeometry(state, stats)
	if not state._settled then
		settle(state, stats, world)
	end
	state.tick += 1

	-- Pre-step snapshot for the NaN guard.
	local p0, yaw0, pitch0, roll0 = state.position, state.yaw, state.pitch, state.roll
	local vy0 = state.verticalVelocity
	local gp0, gr0, grounded0 = state.groundPitch, state.groundRoll, state.grounded

	-- Input (sanitised every step: the server may feed client inputs directly).
	local throttle = axis(input.throttle)
	local steer = axis(input.steer)
	local brake = input.brake == true
	local seq = input.seq
	if type(seq) == "number" and finite(seq) then
		state.lastInputSeq = seq
	end

	updateMechanics(state, stats, input.mechanic == true, dt)
	local reason: ImmobileReason? = immobileReasonOf(state, stats)
	local immobile = reason ~= nil
	state.immobilized = immobile
	state.immobileReason = reason
	if immobile then
		throttle, steer = 0, 0
	end

	-- Resting shortcut: nothing moves and nothing asks to move -> skip probes until the next re-probe.
	local resting = state._resting
		and state.grounded
		and throttle == 0
		and steer == 0
		and state.speed == 0
		and state.lateralSpeed == 0
		and state.yawRate == 0
		and state.position == state._restPosition
		and state.yaw == state._restYaw
		and state._restTimer + dt < M.REST_REPROBE_S
	if resting then
		state._restTimer += dt
	else
		state._resting = false
		local topCap, revCap = speedCaps(state, stats)
		local dts = dt
		local pos = state.position
		local yaw = state.yaw
		local g = M.GRAVITY_MPS2 * SPM

		-- Dynamics.
		local predictedY: number
		if state.grounded then
			state.speed = longitudinal(state, stats, throttle, brake, immobile, topCap, revCap, dts)
			state.lateralSpeed = lateral(state, dts)
			state.yawRate = yawDynamics(state, stats, steer, brake, immobile, topCap, dts)
			predictedY = pos.Y + state.speed * sin(state.pitch) * dts
			state.verticalVelocity = state.speed * sin(state.pitch)
			state.airborneTime = 0
		else
			local vy = state.verticalVelocity
			local vyNew = max(vy - g * dts, -M.MAX_FALL_SPEED_MPS * SPM)
			predictedY = pos.Y + (vy + vyNew) / 2 * dts
			state.verticalVelocity = vyNew
			state.airborneTime += dts
			local limit = M.ABSOLUTE_MAX_SPEED_KMH * KMH * SPM
			state.speed = clamp(state.speed, -limit, limit)
		end

		-- Horizontal motion (heading first, then translation along the new heading).
		local newYaw = yaw + state.yawRate * dts
		local cy, sy = cos(newYaw), sin(newYaw)
		local vH = state.speed * cos(state.pitch)
		local lat = state.lateralSpeed
		local disp = Vector3.new((sy * vH + cy * lat) * dts, 0, (-cy * vH + sy * lat) * dts)
		local wheeled = stats.wheeled
		if
			stats.pivot ~= true
			and wheeled == nil
			and state.grounded
			and state.yawRate ~= 0
			and abs(state.speed / SPM) < M.NON_PIVOT_SPEED_KMH * KMH
		then
			-- No neutral steer: turn in place about the inner track centre line.
			local offset = state._size.X * M.TRACK_CENTRELINE_FRACTION * sign(state.yawRate)
			local c0, s0 = cos(yaw), sin(yaw)
			local cx, cz = pos.X + c0 * offset, pos.Z + s0 * offset
			local dx, dz = pos.X - cx, pos.Z - cz
			local delta = newYaw - yaw
			local cd, sd = cos(delta), sin(delta)
			disp += Vector3.new(cx + dx * cd - dz * sd - pos.X, 0, cz + dz * cd + dx * sd - pos.Z)
		end
		moveHorizontal(state, world, disp, newYaw, dts)
		local moved = state.position
		local movedYaw = state.yaw

		-- Ground under the new pose.
		local probeUp = (M.STEP_HEIGHT_M + M.GROUND_PROBE_UP_M) * SPM
		local probeBase = if state.grounded then predictedY else max(pos.Y, predictedY)
		local valid = probe(
			state,
			stats,
			world,
			moved.X,
			probeBase,
			moved.Z,
			movedYaw,
			state.pitch,
			state.roll,
			probeUp,
			M.GROUND_RECAST_UP_M * SPM
		)
		local snap = M.GROUND_SNAP_M * SPM
		local blocked = false
		if valid > 0 and state.grounded then
			-- Terrain step/wall check: a rise above the step height in one tick blocks the move.
			local rise = restHeight(state, state.pitch, state.roll) - predictedY
			local horizontalMove = (moved - pos).Magnitude
			if rise > M.STEP_HEIGHT_M * SPM and (horizontalMove > 1e-5 or movedYaw ~= yaw) then
				blocked = true
				local n = horizontalUnit(pos - moved)
				state.position = pos
				state.yaw = yaw
				state.yawRate = 0
				if n ~= nil then
					local closing = obstacleResponse(state, n, 0)
					reportObstacle(state, n, closing, nil)
				end
				state.speed = 0
				state.lateralSpeed = 0
			end
		end

		if not blocked then
			local x, z = moved.X, moved.Z
			if valid == 0 then
				if state.grounded then
					state.grounded = false
					state.verticalVelocity = state.speed * sin(state.pitch)
				end
				state.position = Vector3.new(x, predictedY, z)
			else
				local hasGx, gx, hasGz, gz = fitPlane(state, probeBase, state.pitch, state.roll, snap)
				local tp, tr = attitudeOf(if hasGx then gx else 0, if hasGz then gz else 0)
				if not hasGz then
					tp = state.groundPitch
				end
				if not hasGx then
					tr = state.groundRoll
				end
				if hasGx or hasGz then
					state.groundPitch, state.groundRoll = tp, tr
				end
				if state.grounded then
					local k = 1 - exp(-M.GROUND_FIT_RATE * dts)
					state.pitch += (state.groundPitch - state.pitch) * k
					state.roll += (state.groundRoll - state.roll) * k
				end
				local yRest = restHeight(state, state.pitch, state.roll)
				if state.grounded then
					if predictedY - yRest > snap then
						state.grounded = false
						state.verticalVelocity = state.speed * sin(state.pitch)
						state.position = Vector3.new(x, predictedY, z)
					else
						state.position = Vector3.new(x, yRest, z)
					end
				elseif predictedY <= yRest then
					-- Landing: vertical impact speed from energy (exact for constant g between ticks).
					local vy = vy0
					local drop = pos.Y - yRest
					local impact = sqrt(max(0, vy * vy + 2 * g * drop)) / SPM
					state.grounded = true
					state.position = Vector3.new(x, yRest, z)
					state.verticalVelocity = 0
					state.airborneTime = 0
					if impact >= M.LANDED_EVENT_MIN_MPS then
						local e = pushEvent(state, "Landed")
						e.speedMps = impact
						e.inverted = state.overturned or cos(state.pitch) * cos(state.roll) < 0
					end
				else
					state.position = Vector3.new(x, predictedY, z)
				end
			end
			applyTerrain(state, stats)
		end

		-- Kill plane: falling with nothing below.
		if not state.grounded and state.position.Y < M.KILL_PLANE_Y_M * SPM then
			state.position = Vector3.new(state.position.X, M.KILL_PLANE_Y_M * SPM, state.position.Z)
			state.wrecked = true
			state.verticalVelocity = 0
			state.speed = 0
			state.lateralSpeed = 0
			state.yawRate = 0
			state.immobilized = true
			state.immobileReason = "FellOut"
			pushEvent(state, "FellOut")
		end

		updateWater(state, world)
		if state.waterDepthM >= M.WATER_EFFECT_MIN_DEPTH_M then
			applyTerrain(state, stats)
		end
		state._restTimer = 0
	end

	-- Status timers.
	if not state.wrecked then
		updateDrowning(state, dt)
	end
	updateOverturn(state, dt)
	updateStill(state, dt)

	-- NaN guard: restore the pre-step state rather than propagate garbage.
	if not stateFinite(state) then
		state.position, state.yaw, state.pitch, state.roll = p0, yaw0, pitch0, roll0
		state.speed, state.lateralSpeed, state.yawRate, state.verticalVelocity = 0, 0, 0, 0
		state.groundPitch, state.groundRoll, state.grounded = gp0, gr0, grounded0
		if not stateFinite(state) then
			state.position = clampToBounds(Vector3.zero, state.bounds)
			state.yaw, state.pitch, state.roll, state.groundPitch, state.groundRoll = 0, 0, 0, 0, 0
		end
		state.nanResets += 1
		state._resting = false
	end

	-- Resting detection for the next step.
	if
		not resting
		and state.grounded
		and state.speed == 0
		and state.lateralSpeed == 0
		and state.yawRate == 0
		and abs(state.pitch - state.groundPitch) < 1e-6
		and abs(state.roll - state.groundRoll) < 1e-6
	then
		state._resting = true
		state._restPosition = state.position
		state._restYaw = state.yaw
	end
	return events
end

--------------------------------------------------------------------------------
-- Helpers for consumers
--------------------------------------------------------------------------------

--- Hull CFrame (hull space -> world) of a state.
function VehicleSim.hullCFrame(state: VehicleSimState): CFrame
	return hullCFrameOf(state.position, state.yaw, state.pitch, state.roll)
end

--- World velocity in studs/s (forward along the slope + side slip + vertical while airborne).
function VehicleSim.velocity(state: VehicleSimState): Vector3
	local cy, sy = cos(state.yaw), sin(state.yaw)
	local sp, cp = sin(state.pitch), cos(state.pitch)
	local vH = state.speed * cp
	local lat = state.lateralSpeed
	local vy = if state.grounded then state.speed * sp else state.verticalVelocity
	return Vector3.new(sy * vH + cy * lat, vy, -cy * vH + sy * lat)
end

--- Hull speed in km/h (signed, + forward).
function VehicleSim.speedKmh(state: VehicleSimState): number
	return state.speed / SPM * 3.6
end

--- Collision OBB size in studs (width, height, length) once the state has seen its stats.
function VehicleSim.hullSize(state: VehicleSimState, stats: VehicleStats): Vector3
	ensureGeometry(state, stats)
	return state._size
end

--- Drown depth (m over the hull bottom) resolved for this vehicle.
function VehicleSim.drownDepthM(state: VehicleSimState, stats: VehicleStats): number
	ensureGeometry(state, stats)
	return state._drownDepthM
end

--- Applies a world-space velocity change (studs/s) from a vehicle contact (Collision.resolveVelocities): split into
--- the hull forward (along the slope), side slip and, while airborne, vertical components.
function VehicleSim.applyVelocityChange(state: VehicleSimState, dv: Vector3)
	if not finiteVector(dv) then
		return
	end
	local cy, sy = cos(state.yaw), sin(state.yaw)
	local cp = cos(state.pitch)
	local fwd = dv.X * sy - dv.Z * cy
	state.speed += fwd / max(cp, 0.05)
	state.lateralSpeed += dv.X * cy + dv.Z * sy
	if not state.grounded then
		state.verticalVelocity += dv.Y
	end
	state._resting = false
end

--- Moves the hull by a world offset (studs) to separate vehicles (Collision.separation) or let allies push an
--- overturned vehicle. Grounded vehicles ignore the vertical part (the ground fit owns it). Clamped to the bounds.
function VehicleSim.displace(state: VehicleSimState, offset: Vector3)
	if not finiteVector(offset) then
		return
	end
	local dy = if state.grounded then 0 else offset.Y
	state.position = clampToBounds(state.position + Vector3.new(offset.X, dy, offset.Z), state.bounds)
	state._resting = false
end

--- Teleports the hull origin to `position` (x/z, heading optional) and re-settles it on the ground next step.
function VehicleSim.teleport(state: VehicleSimState, position: Vector3, yaw: number?)
	if not finiteVector(position) then
		return
	end
	state.position = clampToBounds(position, state.bounds)
	if type(yaw) == "number" and finite(yaw) then
		state.yaw = wrapPi(yaw)
	end
	state.speed, state.lateralSpeed, state.yawRate, state.verticalVelocity = 0, 0, 0, 0
	state._settled = false
	state._resting = false
end

local function copyModifiers(src: VehicleSimModifiers, dst: VehicleSimModifiers)
	dst.engine = src.engine
	dst.trackLeft = src.trackLeft
	dst.trackRight = src.trackRight
	dst.lostWheelPairs = src.lostWheelPairs
	dst.powerMul = src.powerMul
	dst.topSpeedMul = src.topSpeedMul
	dst.topSpeedBonusKmh = src.topSpeedBonusKmh
	dst.reverseSpeedMul = src.reverseSpeedMul
	dst.speedCapKmh = src.speedCapKmh
	dst.hullTraverseMul = src.hullTraverseMul
	dst.immobilized = src.immobilized
end

--- Copies every simulated field of `src` into `dst` (or a new state) for prediction/reconciliation. Immutable
--- geometry (contact samples, bounds, options) is shared; modifiers, mechanic runtime and scratch stay per state.
function VehicleSim.copyState(src: VehicleSimState, dst: VehicleSimState?): VehicleSimState
	local out = dst or VehicleSim.newState(CFrame.new(src.position), src._options)
	out.position = src.position
	out.yaw = src.yaw
	out.pitch = src.pitch
	out.roll = src.roll
	out.speed = src.speed
	out.lateralSpeed = src.lateralSpeed
	out.yawRate = src.yawRate
	out.verticalVelocity = src.verticalVelocity
	out.grounded = src.grounded
	out.groundPitch = src.groundPitch
	out.groundRoll = src.groundRoll
	out.terrainClass = src.terrainClass
	out.terrainResistance = src.terrainResistance
	out.traction = src.traction
	out.material = src.material
	out.waterDepthM = src.waterDepthM
	out.airborneTime = src.airborneTime
	out.submergedTime = src.submergedTime
	out.tiltTime = src.tiltTime
	out.overturnedTime = src.overturnedTime
	out.overturned = src.overturned
	out.drowned = src.drowned
	out.wrecked = src.wrecked
	out.immobilized = src.immobilized
	out.immobileReason = src.immobileReason
	out.mechanicActive = src.mechanicActive
	out.gunDepressionBonusDeg = src.gunDepressionBonusDeg
	out.gunElevationBonusDeg = src.gunElevationBonusDeg
	out.stillTime = src.stillTime
	copyModifiers(src.modifiers, out.modifiers)
	local m, d = src.mechanic, out.mechanic
	d.kind, d.phase, d.timer, d.charges, d.lastInput = m.kind, m.phase, m.timer, m.charges, m.lastInput
	out.bounds = src.bounds
	out.lastInputSeq = src.lastInputSeq
	out.tick = src.tick
	out.nanResets = src.nanResets
	table.clear(out.events)
	out._options = src._options
	out._settled = src._settled
	out._restTimer = src._restTimer
	out._resting = src._resting
	out._restPosition = src._restPosition
	out._restYaw = src._restYaw
	out._hydroSettle = src._hydroSettle
	out._mechanicIndex = src._mechanicIndex
	out._hydroIndex = src._hydroIndex
	if src._geometryReady then
		out._size = src._size
		out._contactX = src._contactX
		out._contactZ = src._contactZ
		out._drownDepthM = src._drownDepthM
		local n = #src._contactX
		if #out._sampleH ~= n then
			out._sampleH = table.create(n, 0)
			out._sampleU = table.create(n, 0)
			out._sampleW = table.create(n, 0)
			out._sampleOk = table.create(n, false)
			out._contact = table.create(n, false)
		end
		out._geometryReady = true
	else
		out._geometryReady = false
	end
	return out
end

--------------------------------------------------------------------------------
-- Input sanitising (server feeds client inputs directly; ARCHITECTURE §12)
--------------------------------------------------------------------------------

--- Neutral input (no throttle/steer, aim straight ahead of the origin).
function VehicleSim.neutralInput(out: InputCommand?): InputCommand
	local cmd: InputCommand = out
		or {
			seq = 0,
			throttle = 0,
			steer = 0,
			aimPoint = Vector3.zero,
			fire = false,
			holdTurret = false,
			brake = false,
			mechanic = false,
		}
	cmd.seq = 0
	cmd.throttle = 0
	cmd.steer = 0
	cmd.aimPoint = Vector3.zero
	cmd.fire = false
	cmd.holdTurret = false
	cmd.brake = false
	cmd.mechanic = false
	return cmd
end

--- Sanitises an untrusted InputCommand into `out` (or a new table): throttle/steer clamped to [-1, 1] (NaN -> 0),
--- seq a finite non-negative integer, aimPoint finite and clamped to the map bounds grown by AIM_POINT_MARGIN_M
--- (invalid -> `fallbackAim`), flags strictly boolean. Returns (command, valid) where `valid` is false if anything
--- had to be replaced or clamped (feed AntiExploitService strikes with it).
function VehicleSim.sanitizeInput(
	raw: unknown,
	out: InputCommand?,
	bounds: MapBounds?,
	fallbackAim: Vector3?
): (InputCommand, boolean)
	local cmd = VehicleSim.neutralInput(out)
	local fallback = if fallbackAim ~= nil and finiteVector(fallbackAim) then fallbackAim else Vector3.zero
	cmd.aimPoint = fallback
	if type(raw) ~= "table" then
		return cmd, false
	end
	local r = raw :: any
	local valid = true
	local seq = r.seq
	if InputValidator.isFiniteNumber(seq) and seq >= 0 and seq == math.floor(seq) and seq <= 2 ^ 31 then
		cmd.seq = seq
	else
		valid = false
	end
	local throttle, steer = r.throttle, r.steer
	if InputValidator.isFiniteNumber(throttle) then
		valid = valid and throttle >= -1 and throttle <= 1
		cmd.throttle = clamp(throttle, -1, 1)
	else
		valid = false
	end
	if InputValidator.isFiniteNumber(steer) then
		valid = valid and steer >= -1 and steer <= 1
		cmd.steer = clamp(steer, -1, 1)
	else
		valid = false
	end
	local aim = r.aimPoint
	if typeof(aim) == "Vector3" and finiteVector(aim) then
		local M = Config.Movement
		local b = bounds or VehicleSim.boundsFromSize(M.DEFAULT_MAP_SIZE_M)
		local margin = M.AIM_POINT_MARGIN_M * SPM
		local maxY = M.MAX_AIM_HEIGHT_M * SPM
		local x = clamp(aim.X, b.minX - margin, b.maxX + margin)
		local y = clamp(aim.Y, -maxY, maxY)
		local z = clamp(aim.Z, b.minZ - margin, b.maxZ + margin)
		if x ~= aim.X or y ~= aim.Y or z ~= aim.Z then
			valid = false
		end
		cmd.aimPoint = Vector3.new(x, y, z)
	else
		valid = false
	end
	local fire, hold, brake, mechanic = r.fire, r.holdTurret, r.brake, r.mechanic
	valid = valid
		and (fire == nil or type(fire) == "boolean")
		and (hold == nil or type(hold) == "boolean")
		and (brake == nil or type(brake) == "boolean")
		and (mechanic == nil or type(mechanic) == "boolean")
	cmd.fire = fire == true
	cmd.holdTurret = hold == true
	cmd.brake = brake == true
	cmd.mechanic = mechanic == true
	return cmd, valid
end

return VehicleSim
