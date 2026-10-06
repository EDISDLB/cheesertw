--!strict
--[[
	CombatFixtures — synthetic armor model, shells and vehicle stats shared by the Combat specs (not a spec).

	Purpose:          A closed hull + turret ArmorModel with every volume kind (Armor, Layered mantlet, Spaced
	                  barrel / tracks / skirts, Module and Crew volumes in both groups) whose numbers are easy to
	                  hand-compute, plus representative shells and a DamageModelInit.
	Dependencies:     Types (shapes only).
	State:            None (every call builds fresh tables).
	Validation:       ArmorGeometry.validate(model) must return no problems (checked by ArmorGeometry.spec).
	Error handling:   N/A.
	Performance notes: Test-only.

	Geometry (hull space, studs; −Z forward, +X right, +Y up; 3 studs = 1 m):
	  Hull body (Armor): x ∈ [−4.5, 4.5], y ∈ [1.5, 6], z ∈ [−9, 9]; lower front plate z = −9 (60 mm) up to y = 4;
	    upper glacis from (y 4, z −9) to (y 6, z −3), normal (0, 6, −2)/√40 (80 mm, 71.57° from a horizontal shot);
	    sides 40, roof 20, floor 15, rear 30.
	  Tracks (Spaced, 20 mm): x ∈ ±[4.5, 6], y ∈ [0, 3], z ∈ [−9.5, 9.5]; skirts (Spaced, 10 mm): x ∈ ±[5.9, 6.0],
	    y ∈ [3, 5.5], z ∈ [−8, 8] (air gap 1.4 studs = 0.467 m to the hull side).
	  Turret (Armor) on the ring at hull (0, 6, 0): x, z ∈ [−3.5, 3.5], y ∈ [0, 3] (front 100, sides 60, rear 50,
	    roof 25; bottom face = hull roof 20). Gun trunnion at turret (0, 1.5, −3.5): mantlet (Layered 80) gun-space
	    z ∈ [−0.6, 0], x ∈ [−1.5, 1.5], y ∈ [−1, 1]; barrel (Spaced 20, module Gun) z ∈ [−9.6, −0.6], |x|,|y| <= 0.25.
	  Modules: hull Engine x ∈ [−3, 3], y ∈ [2, 5], z ∈ [4, 8]; FuelTank x ∈ [−4.2, −3.2], y ∈ [2, 5], z ∈ [0, 4];
	    AmmoRack x ∈ [−2, 2], y ∈ [2, 3.5], z ∈ [−2, 2]; TurretRing x, z ∈ [−3, 3], y ∈ [5.2, 5.9]; Driver (crew 1)
	    x ∈ [1.5, 3.5], y ∈ [2, 4], z ∈ [−8, −6]. Turret: AmmoRack (bustle) x ∈ [−2, 2], y ∈ [0.5, 2], z ∈ [2, 3.2];
	    Gun breech x ∈ [−0.8, 0.8], y ∈ [1, 2], z ∈ [−3, −1]; Optics x ∈ [−2.5, −1.5], y ∈ [2.4, 2.9],
	    z ∈ [−0.5, 0.5]; Gunner (2) x ∈ [1, 2.8], y ∈ [0.3, 2.2], z ∈ [−2.5, −0.5]; Commander (3) x ∈ [−2.8, −1],
	    y ∈ [0.3, 2.2], z ∈ [−1, 1]; Loader (4) x ∈ [1, 2.8], y ∈ [0.3, 2.2], z ∈ [0, 2].
]]

local Fixtures = {}

local SQRT40 = math.sqrt(40)
Fixtures.GLACIS_NORMAL = Vector3.new(0, 6 / SQRT40, -2 / SQRT40)
Fixtures.GLACIS_D = (6 / SQRT40) * 4 + (2 / SQRT40) * 9

local function face(normal: Vector3, distance: number, thicknessMm: number, zone: string, spaced: boolean): any
	return { normal = normal, distance = distance, thicknessMm = thicknessMm, zone = zone, spaced = spaced }
end

--- Axis-aligned box volume. `t` = { right, left, top, bottom, back, front } thickness; `z` the same for zones
--- (a string applies to every face).
function Fixtures.box(spec: {
	id: number,
	group: string,
	kind: string,
	min: Vector3,
	max: Vector3,
	thickness: any,
	zone: any,
	module: string?,
	crewSlot: number?,
	label: string?,
}): any
	local mn, mx = spec.min, spec.max
	local spaced = spec.kind == "Spaced"
	local function pick(v: any, key: string): any
		if type(v) == "table" then
			return v[key]
		end
		return v
	end
	local faces = {
		face(Vector3.new(1, 0, 0), mx.X, pick(spec.thickness, "right"), pick(spec.zone, "right"), spaced),
		face(Vector3.new(-1, 0, 0), -mn.X, pick(spec.thickness, "left"), pick(spec.zone, "left"), spaced),
		face(Vector3.new(0, 1, 0), mx.Y, pick(spec.thickness, "top"), pick(spec.zone, "top"), spaced),
		face(Vector3.new(0, -1, 0), -mn.Y, pick(spec.thickness, "bottom"), pick(spec.zone, "bottom"), spaced),
		face(Vector3.new(0, 0, 1), mx.Z, pick(spec.thickness, "back"), pick(spec.zone, "back"), spaced),
		face(Vector3.new(0, 0, -1), -mn.Z, pick(spec.thickness, "front"), pick(spec.zone, "front"), spaced),
	}
	local center = (mn + mx) / 2
	return {
		id = spec.id,
		group = spec.group,
		kind = spec.kind,
		faces = faces,
		center = center,
		radius = (mx - center).Magnitude + 1e-3,
		module = spec.module,
		crewSlot = spec.crewSlot,
		label = spec.label or `{spec.kind} {spec.id}`,
	}
end

local function hullBody(): any
	return {
		id = 1,
		group = "Hull",
		kind = "Armor",
		faces = {
			face(Vector3.new(1, 0, 0), 4.5, 40, "HullSide", false),
			face(Vector3.new(-1, 0, 0), 4.5, 40, "HullSide", false),
			face(Vector3.new(0, 1, 0), 6, 20, "HullRoof", false),
			face(Vector3.new(0, -1, 0), -1.5, 15, "HullFloor", false),
			face(Vector3.new(0, 0, 1), 9, 30, "HullRear", false),
			face(Vector3.new(0, 0, -1), 9, 60, "HullLowerFront", false),
			face(Fixtures.GLACIS_NORMAL, Fixtures.GLACIS_D, 80, "HullUpperFront", false),
		},
		center = Vector3.new(0, 3.75, 0),
		radius = 10.5,
		label = "Hull",
	}
end

--- The full synthetic vehicle (ids 1..20).
function Fixtures.model(): any
	local box = Fixtures.box
	local volumes = {
		hullBody(),
		box({
			id = 2,
			group = "Turret",
			kind = "Armor",
			min = Vector3.new(-3.5, 0, -3.5),
			max = Vector3.new(3.5, 3, 3.5),
			thickness = { right = 60, left = 60, top = 25, bottom = 20, back = 50, front = 100 },
			zone = {
				right = "TurretSide",
				left = "TurretSide",
				top = "TurretRoof",
				bottom = "HullRoof",
				back = "TurretRear",
				front = "TurretFront",
			},
			label = "Turret",
		}),
		box({
			id = 3,
			group = "Gun",
			kind = "Layered",
			min = Vector3.new(-1.5, -1, -0.6),
			max = Vector3.new(1.5, 1, 0),
			thickness = 80,
			zone = "Mantlet",
			label = "Mantlet",
		}),
		box({
			id = 4,
			group = "Gun",
			kind = "Spaced",
			min = Vector3.new(-0.25, -0.25, -9.6),
			max = Vector3.new(0.25, 0.25, -0.6),
			thickness = 20,
			zone = "GunBarrel",
			module = "Gun",
			label = "Barrel",
		}),
		box({
			id = 5,
			group = "Hull",
			kind = "Spaced",
			min = Vector3.new(4.5, 0, -9.5),
			max = Vector3.new(6, 3, 9.5),
			thickness = 20,
			zone = "Track",
			module = "TrackRight",
			label = "Right track",
		}),
		box({
			id = 6,
			group = "Hull",
			kind = "Spaced",
			min = Vector3.new(-6, 0, -9.5),
			max = Vector3.new(-4.5, 3, 9.5),
			thickness = 20,
			zone = "Track",
			module = "TrackLeft",
			label = "Left track",
		}),
		box({
			id = 7,
			group = "Hull",
			kind = "Spaced",
			min = Vector3.new(5.9, 3, -8),
			max = Vector3.new(6, 5.5, 8),
			thickness = 10,
			zone = "Skirt",
			label = "Right skirt",
		}),
		box({
			id = 8,
			group = "Hull",
			kind = "Spaced",
			min = Vector3.new(-6, 3, -8),
			max = Vector3.new(-5.9, 5.5, 8),
			thickness = 10,
			zone = "Skirt",
			label = "Left skirt",
		}),
		box({
			id = 9,
			group = "Hull",
			kind = "Module",
			min = Vector3.new(-3, 2, 4),
			max = Vector3.new(3, 5, 8),
			thickness = 0,
			zone = "HullRear",
			module = "Engine",
		}),
		box({
			id = 10,
			group = "Hull",
			kind = "Module",
			min = Vector3.new(-4.2, 2, 0),
			max = Vector3.new(-3.2, 5, 4),
			thickness = 0,
			zone = "HullSide",
			module = "FuelTank",
		}),
		box({
			id = 11,
			group = "Hull",
			kind = "Module",
			min = Vector3.new(-2, 2, -2),
			max = Vector3.new(2, 3.5, 2),
			thickness = 0,
			zone = "HullSide",
			module = "AmmoRack",
		}),
		box({
			id = 12,
			group = "Hull",
			kind = "Module",
			min = Vector3.new(-3, 5.2, -3),
			max = Vector3.new(3, 5.9, 3),
			thickness = 0,
			zone = "HullRoof",
			module = "TurretRing",
		}),
		box({
			id = 13,
			group = "Hull",
			kind = "Crew",
			min = Vector3.new(1.5, 2, -8),
			max = Vector3.new(3.5, 4, -6),
			thickness = 0,
			zone = "HullUpperFront",
			crewSlot = 1,
		}),
		box({
			id = 14,
			group = "Turret",
			kind = "Module",
			min = Vector3.new(-2, 0.5, 2),
			max = Vector3.new(2, 2, 3.2),
			thickness = 0,
			zone = "TurretRear",
			module = "AmmoRack",
		}),
		box({
			id = 15,
			group = "Turret",
			kind = "Module",
			min = Vector3.new(-0.8, 1, -3),
			max = Vector3.new(0.8, 2, -1),
			thickness = 0,
			zone = "TurretFront",
			module = "Gun",
		}),
		box({
			id = 16,
			group = "Turret",
			kind = "Module",
			min = Vector3.new(-2.5, 2.4, -0.5),
			max = Vector3.new(-1.5, 2.9, 0.5),
			thickness = 0,
			zone = "TurretRoof",
			module = "Optics",
		}),
		box({
			id = 17,
			group = "Turret",
			kind = "Crew",
			min = Vector3.new(1, 0.3, -2.5),
			max = Vector3.new(2.8, 2.2, -0.5),
			thickness = 0,
			zone = "TurretSide",
			crewSlot = 2,
		}),
		box({
			id = 18,
			group = "Turret",
			kind = "Crew",
			min = Vector3.new(-2.8, 0.3, -1),
			max = Vector3.new(-1, 2.2, 1),
			thickness = 0,
			zone = "TurretSide",
			crewSlot = 3,
		}),
		box({
			id = 19,
			group = "Turret",
			kind = "Crew",
			min = Vector3.new(1, 0.3, 0),
			max = Vector3.new(2.8, 2.2, 2),
			thickness = 0,
			zone = "TurretSide",
			crewSlot = 4,
		}),
	}
	return {
		volumes = volumes,
		boundsCenter = Vector3.new(0, 4, 0),
		boundsRadius = 15,
		pivots = {
			turretRing = CFrame.new(0, 6, 0),
			gunTrunnion = CFrame.new(0, 1.5, -3.5),
			muzzle = CFrame.new(0, 0, -9.6),
			viewPoint = Vector3.new(-2, 3, 0),
			camoPoints = {},
			trackContacts = { left = {}, right = {} },
			exhausts = {},
			hullSize = Vector3.new(12, 6, 19),
		},
	}
end

--- A pose (hull at the origin unless given).
function Fixtures.pose(hullCFrame: CFrame?, turretYawDeg: number?, gunPitchDeg: number?, gunYawDeg: number?): any
	return {
		hullCFrame = hullCFrame or CFrame.new(),
		turretYawDeg = turretYawDeg or 0,
		gunPitchDeg = gunPitchDeg or 0,
		gunYawDeg = gunYawDeg,
	}
end

--- Shells (CombatShell; overrides merged in).
function Fixtures.shell(kind: string, overrides: { [string]: any }?): any
	local base: { [string]: any }
	if kind == "AP" then
		base = {
			kind = "AP",
			caliberMm = 75,
			damage = 115,
			moduleDamage = 57.5,
			penetrationMm = 100,
			penetrationAt500Mm = 90,
			velocityMps = 480,
			gravityMps2 = 19.62,
			maxRangeM = 600,
			explosionRadiusM = 0,
			normalizationDeg = 5,
			ricochetAngleDeg = 70,
		}
	elseif kind == "APCR" then
		base = {
			kind = "APCR",
			caliberMm = 75,
			damage = 115,
			moduleDamage = 57.5,
			penetrationMm = 130,
			penetrationAt500Mm = 97.5,
			velocityMps = 600,
			gravityMps2 = 19.62,
			maxRangeM = 600,
			explosionRadiusM = 0,
			normalizationDeg = 2,
			ricochetAngleDeg = 70,
		}
	elseif kind == "HEAT" then
		base = {
			kind = "HEAT",
			caliberMm = 75,
			damage = 115,
			moduleDamage = 57.5,
			penetrationMm = 130,
			penetrationAt500Mm = 130,
			velocityMps = 408,
			gravityMps2 = 19.62,
			maxRangeM = 600,
			explosionRadiusM = 0,
			normalizationDeg = 0,
			ricochetAngleDeg = 85,
		}
	elseif kind == "HE" or kind == "HESH" then
		base = {
			kind = kind,
			caliberMm = 75,
			damage = 150,
			moduleDamage = 112.5,
			penetrationMm = if kind == "HE" then 38 else 120,
			penetrationAt500Mm = if kind == "HE" then 38 else 120,
			velocityMps = 480,
			gravityMps2 = 19.62,
			maxRangeM = 600,
			explosionRadiusM = 0.75,
			normalizationDeg = 0,
			ricochetAngleDeg = 90,
		}
	else
		error("unknown fixture shell " .. kind)
	end
	if overrides then
		for k, v in overrides do
			base[k] = v
		end
	end
	return base
end

--- A DamageModelInit (tier VI-like: module ref alpha 160, crew of 4).
function Fixtures.init(overrides: { [string]: any }?): any
	local init: { [string]: any } = {
		hp = 1000,
		massKg = 40000,
		modules = {
			Engine = { maxHp = 160, repairS = 14 },
			AmmoRack = { maxHp = 144, repairS = 10 },
			FuelTank = { maxHp = 160, repairS = 10 },
			Gun = { maxHp = 160, repairS = 12 },
			TurretRing = { maxHp = 160, repairS = 12 },
			Optics = { maxHp = 128, repairS = 8 },
			TrackLeft = { maxHp = 224, repairS = 10 },
			TrackRight = { maxHp = 224, repairS = 10 },
		},
		crew = {
			{ slot = 1, role = "Driver", also = {}, level = 100, maxHp = 128 },
			{ slot = 2, role = "Gunner", also = {}, level = 100, maxHp = 128 },
			{ slot = 3, role = "Commander", also = {}, level = 100, maxHp = 128 },
			{ slot = 4, role = "Loader", also = {}, level = 100, maxHp = 128 },
		},
		crewLevels = { Commander = 100, Gunner = 100, Driver = 100, Loader = 100 },
		fireChance = 0.15,
		fireDurationS = 8,
		spallFactor = 1,
		crewInjuryChanceMul = 1,
		stunDurationMul = 1,
		ramDamageDealtMul = 1,
		ramDamageTakenMul = 1,
		fallDamageMul = 1,
	}
	if overrides then
		for k, v in overrides do
			init[k] = v
		end
	end
	return init
end

--- An RNG stand-in whose draws are scripted (normal() returns `normals` in turn, next() returns `uniforms`).
function Fixtures.scriptedRng(normals: { number }?, uniforms: { number }?): any
	local n, u = 0, 0
	local rng = {}
	function rng.normal(_self: any, mean: number, sd: number): number
		n += 1
		local list = normals or { 0 }
		return mean + sd * list[((n - 1) % #list) + 1]
	end
	function rng.next(_self: any): number
		u += 1
		local list = uniforms or { 0 }
		return list[((u - 1) % #list) + 1]
	end
	function rng.chance(self: any, p: number): boolean
		return self:next() < p
	end
	function rng.range(self: any, a: number, b: number): number
		return a + (b - a) * self:next()
	end
	function rng.int(self: any, a: number, b: number): number
		return math.min(b, a + math.floor((b - a + 1) * self:next()))
	end
	return rng
end

return Fixtures
