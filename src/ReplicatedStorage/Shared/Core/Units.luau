--!strict
--[[
	Units — conversions between real-world config units and Roblox studs.

	Purpose:          Config is authored in real units (m, km/h, m/s, deg, kg); simulation converts at the boundary.
	Dependencies:     None.
	State:            Constants only.
	Validation:       None (pure arithmetic; NaN in -> NaN out).
	Error handling:   None.
	Performance notes: Plain multiplications, safe in hot loops.

	1 stud = 1/3 m (Units.STUDS_PER_METER = 3): a 7 m tank is 21 studs. Workspace.Gravity = 9.81 * 3 = 29.43.
]]

local Units = {}

Units.STUDS_PER_METER = 3
Units.METERS_PER_STUD = 1 / 3
Units.GRAVITY_MPS2 = 9.81
Units.GRAVITY_STUDS = 9.81 * 3
Units.KMH_PER_MPS = 3.6

function Units.mToStuds(m: number): number
	return m * 3
end

function Units.studsToM(studs: number): number
	return studs / 3
end

function Units.kmhToMps(kmh: number): number
	return kmh / 3.6
end

function Units.mpsToKmh(mps: number): number
	return mps * 3.6
end

function Units.kmhToStudsPerSec(kmh: number): number
	return kmh / 3.6 * 3
end

function Units.studsPerSecToKmh(v: number): number
	return v / 3 * 3.6
end

function Units.mpsToStudsPerSec(mps: number): number
	return mps * 3
end

function Units.studsPerSecToMps(v: number): number
	return v / 3
end

function Units.degToRad(d: number): number
	return d * (math.pi / 180)
end

function Units.radToDeg(r: number): number
	return r * (180 / math.pi)
end

function Units.tonnesToKg(t: number): number
	return t * 1000
end

function Units.kgToTonnes(kg: number): number
	return kg / 1000
end

return Units
