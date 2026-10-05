local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Units = require("@game/ReplicatedStorage/Shared/Core/Units")

describe("Units", function()
	it("uses 3 studs per meter", function()
		expect(Units.STUDS_PER_METER).toBe(3)
		expect(Units.mToStuds(7)).toBe(21)
		expect(Units.studsToM(21)).toBe(7)
	end)

	it("converts speeds", function()
		expect(Units.kmhToStudsPerSec(36)).toBeCloseTo(30)
		expect(Units.studsPerSecToKmh(30)).toBeCloseTo(36)
		expect(Units.mpsToStudsPerSec(10)).toBe(30)
		expect(Units.studsPerSecToMps(30)).toBe(10)
		expect(Units.kmhToMps(72)).toBeCloseTo(20)
		expect(Units.mpsToKmh(20)).toBeCloseTo(72)
	end)

	it("converts angles and masses", function()
		expect(Units.degToRad(180)).toBeCloseTo(math.pi)
		expect(Units.radToDeg(math.pi / 2)).toBeCloseTo(90)
		expect(Units.tonnesToKg(35)).toBe(35000)
		expect(Units.kgToTonnes(500)).toBe(0.5)
	end)

	it("matches Workspace gravity", function()
		expect(Units.GRAVITY_MPS2).toBe(9.81)
		expect(Units.GRAVITY_STUDS).toBeCloseTo(29.43)
	end)

	it("round-trips", function()
		for _, v in { 0, 1, 12.5, -3, 1e6 } do
			expect(Units.studsToM(Units.mToStuds(v))).toBeCloseTo(v)
			expect(Units.studsPerSecToKmh(Units.kmhToStudsPerSec(v))).toBeCloseTo(v, 1e-9)
			expect(Units.radToDeg(Units.degToRad(v))).toBeCloseTo(v, 1e-9)
		end
	end)
end)
