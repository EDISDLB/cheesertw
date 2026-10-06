-- Modifiers: StatModifier aggregation (content-schema §7: per stat (base + Σ add) × Π mul), module qualifiers,
-- share scaling (training, crew share, category slot), validation, condition rules and the allocation-free
-- accumulator. Regression ids: REG-EQP-01 (stacking rules are table-driven: additive vs multiplicative).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect
local fs = require("@lune/fs")

local Modifiers = require("@game/ReplicatedStorage/Shared/Vehicle/Modifiers")
local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local function mod(stat: string, op: string, value: number, extra: any?): any
	local m: any = { stat = stat, op = op, value = value }
	if extra then
		for k, v in extra do
			m[k] = v
		end
	end
	return m
end

-- String literals of a union type declared in Types/Content.luau, in declaration order.
local function unionMembers(typeName: string, nextType: string): { string }
	local source = fs.readFile("src/ReplicatedStorage/Shared/Types/Content.luau")
	local start = string.find(source, "export type " .. typeName .. " =", 1, true)
	local stop = string.find(source, "export type " .. nextType, start, true)
	assert(start and stop, "type not found")
	local body = string.sub(source, start :: number, (stop :: number) - 1)
	local out = {}
	for line in string.gmatch(body, "[^\n]+") do
		local code = string.gsub(line, "%-%-.*$", "")
		for literal in string.gmatch(code, '"([%w_]+)"') do
			table.insert(out, literal)
		end
	end
	return out
end

describe("Modifiers: key sets", function()
	it("STAT_KEYS mirrors Types/Content StatKey (order included)", function()
		expect(Modifiers.STAT_KEYS).toEqual(unionMembers("StatKey", "StatOp"))
	end)

	it("MODULE_KINDS mirrors InternalModuleKind and DamageModel's order", function()
		expect(Modifiers.MODULE_KINDS).toEqual(unionMembers("InternalModuleKind", "ArmorZone"))
		expect(Modifiers.MODULE_KINDS).toEqual(DamageModel.MODULE_KINDS)
	end)

	it("only moduleHp, repairTime and damagedModulePenalty take a module qualifier", function()
		expect(Modifiers.QUALIFIED_STATS).toEqual({ "moduleHp", "repairTime", "damagedModulePenalty" })
		expect(Modifiers.isQualified("moduleHp")).toBe(true)
		expect(Modifiers.isQualified("hp")).toBe(false)
		expect(Modifiers.statIndex("damage")).toBe(1)
		expect(Modifiers.statIndex("nope")).toBeNil()
	end)
end)

describe("Modifiers: aggregation (table-driven, REG-EQP-01)", function()
	it("table: (base + Σ add) × Π mul", function()
		local rows = {
			-- base, modifiers, expected
			{ 10, {}, 10 },
			{ 10, { mod("hp", "add", 2), mod("hp", "add", 3) }, 15 },
			{ 10, { mod("hp", "mul", 1.1), mod("hp", "mul", 0.5) }, 5.5 },
			{ 10, { mod("hp", "add", 2), mod("hp", "mul", 1.1), mod("hp", "add", 3), mod("hp", "mul", 0.5) }, 8.25 },
			{ 0, { mod("hp", "mul", 3) }, 0 },
			{ 0, { mod("hp", "add", 4), mod("hp", "mul", 0.5) }, 2 },
			{ 10, { mod("damage", "mul", 9) }, 10 }, -- other stat: untouched
		}
		for i, row in rows do
			local acc = Modifiers.newAccumulator()
			for _, m in row[2] do
				Modifiers.push(acc, m)
			end
			local got = Modifiers.apply(acc, "hp", row[1])
			if math.abs(got - row[3]) > 1e-12 then
				error(`row {i}: got {got}, expected {row[3]}`)
			end
			expect(Modifiers.resolve(row[1], "hp", row[2])).toBeCloseTo(row[3], 1e-12)
		end
	end)

	it("module qualifiers combine the every-module slot with the named module's slot", function()
		local acc = Modifiers.newAccumulator()
		Modifiers.push(acc, mod("moduleHp", "mul", 1.08))
		Modifiers.push(acc, mod("moduleHp", "mul", 2.5, { module = "Engine" }))
		Modifiers.push(acc, mod("moduleHp", "add", 10, { module = "AmmoRack" }))
		expect(Modifiers.apply(acc, "moduleHp", 100, "Engine")).toBeCloseTo(270, 1e-9)
		expect(Modifiers.apply(acc, "moduleHp", 100, "AmmoRack")).toBeCloseTo(118.8, 1e-9)
		expect(Modifiers.apply(acc, "moduleHp", 100, "Optics")).toBeCloseTo(108, 1e-9)
		expect(Modifiers.apply(acc, "moduleHp", 100)).toBeCloseTo(108, 1e-9) -- unqualified read: every-module slot
		expect(Modifiers.touches(acc, "moduleHp", "Engine")).toBe(true)
		expect(Modifiers.touches(acc, "repairTime", "Engine")).toBe(false)
		-- resolve() is the unqualified one-shot: qualified modifiers are ignored there
		expect(Modifiers.resolve(100, "moduleHp", { mod("moduleHp", "mul", 2, { module = "Gun" }) })).toBe(100)
	end)

	it("share scaling changes the delta: add × s, mul 1 + (v − 1) × s, floored at 0", function()
		expect(Modifiers.scaledValue(mod("reloadTime", "mul", 0.90), 1.15)).toBeCloseTo(0.885, 1e-12) -- category slot
		expect(Modifiers.scaledValue(mod("crewLevel", "add", 5), 0.5)).toBe(2.5) -- half crew share
		expect(Modifiers.scaledValue(mod("camoStationary", "mul", 1.8), 0.25)).toBeCloseTo(1.2, 1e-12)
		expect(Modifiers.scaledValue(mod("reloadTime", "mul", 0.5), 3)).toBe(0) -- over-scaled reduction floors at 0
		expect(Modifiers.scaledValue(mod("hp", "mul", 1.1), 0 / 0)).toBeCloseTo(1.1, 1e-12) -- bad scale = 1
		expect(Modifiers.scaledValue(mod("hp", "mul", 1.1), nil)).toBeCloseTo(1.1, 1e-12)
		local acc = Modifiers.newAccumulator()
		Modifiers.push(acc, mod("viewRange", "mul", 1.10), 1.15)
		expect(Modifiers.apply(acc, "viewRange", 400)).toBeCloseTo(400 * 1.115, 1e-9)
	end)

	it("scaledCopy keeps every qualifier and scales the value", function()
		local m = mod("reloadTime", "mul", 0.9, { condition = "NearEnemy", rangeM = 50, durationS = 3 })
		local c = Modifiers.scaledCopy(m, 0.5)
		expect(c).toEqual({
			stat = "reloadTime",
			op = "mul",
			value = 0.95,
			condition = "NearEnemy",
			rangeM = 50,
			durationS = 3,
		})
		local q = Modifiers.scaledCopy(mod("moduleHp", "add", 10, { module = "Engine" }), 2)
		expect(q.module).toBe("Engine")
		expect(q.value).toBe(20)
	end)

	it("invalid modifiers are ignored and counted", function()
		local acc = Modifiers.newAccumulator()
		local bad = {
			mod("nonsense", "mul", 2),
			mod("hp", "pow", 2),
			mod("hp", "mul", 0 / 0),
			mod("hp", "add", math.huge),
			mod("hp", "mul", 2, { module = "Engine" }), -- qualifier on a stat that takes none
			mod("moduleHp", "mul", 2, { module = "Radio" }),
			mod("hp", "mul", 2, { condition = "Sometimes" }),
		}
		for _, m in bad do
			expect(Modifiers.isValid(m)).toBe(false)
			expect(Modifiers.push(acc, m)).toBe(false)
		end
		expect(acc.ignored).toBe(#bad)
		expect(acc.applied).toBe(0)
		expect(Modifiers.apply(acc, "hp", 7)).toBe(7)
		expect(Modifiers.isValid(nil :: any)).toBe(false)
	end)

	it("pushList selects by condition; reset restores the identity", function()
		local list = {
			mod("hp", "add", 1),
			mod("hp", "add", 10, { condition = "Always" }),
			mod("hp", "add", 100, { condition = "Moving" }),
		}
		local acc = Modifiers.newAccumulator()
		expect(Modifiers.pushList(acc, list)).toBe(2)
		expect(Modifiers.apply(acc, "hp", 0)).toBe(11)
		Modifiers.reset(acc)
		expect(acc.applied).toBe(0)
		expect(Modifiers.pushList(acc, list, nil, "conditional")).toBe(1)
		expect(Modifiers.apply(acc, "hp", 0)).toBe(100)
		Modifiers.reset(acc)
		expect(Modifiers.pushList(acc, list, 2, "all")).toBe(3)
		expect(Modifiers.apply(acc, "hp", 0)).toBe(222)
		expect(Modifiers.pushList(acc, nil)).toBe(0)
		Modifiers.reset(acc)
		for _, key in Modifiers.STAT_KEYS do
			expect(Modifiers.touches(acc, key)).toBe(false)
		end
	end)

	it("partition splits a list by stat set", function()
		local inside, outside = Modifiers.partition({
			mod("reloadTime", "mul", 0.85),
			mod("aimTime", "mul", 0.85),
		}, { reloadTime = true })
		expect(#inside).toBe(1)
		expect(inside[1].stat).toBe("reloadTime")
		expect(#outside).toBe(1)
		expect(outside[1].stat).toBe("aimTime")
		local a, b = Modifiers.partition(nil, {})
		expect(a).toEqual({})
		expect(b).toEqual({})
	end)

	it("property: the result is order-independent and equals the naive formula (seeded)", function()
		local rng = RNG.new(4242)
		local stats = { "hp", "viewRange", "reloadTime", "camoMoving" }
		for _ = 1, 200 do
			local list = {}
			for _ = 1, rng:int(0, 12) do
				local op = if rng:chance(0.5) then "add" else "mul"
				local value = if op == "add" then rng:range(-20, 20) else rng:range(0.5, 1.5)
				table.insert(list, mod(rng:pick(stats), op, value))
			end
			local base = rng:range(0, 500)
			for _, stat in stats do
				local add, mul = 0, 1
				for _, m in list do
					if m.stat == stat then
						if m.op == "add" then
							add += m.value
						else
							mul *= m.value
						end
					end
				end
				local want = (base + add) * mul
				local acc = Modifiers.newAccumulator()
				Modifiers.pushList(acc, list)
				local shuffled = table.clone(list)
				rng:shuffle(shuffled)
				local acc2 = Modifiers.newAccumulator()
				Modifiers.pushList(acc2, shuffled)
				expect(Modifiers.apply(acc, stat :: any, base)).toBeCloseTo(want, 1e-9)
				expect(Modifiers.apply(acc2, stat :: any, base)).toBeCloseTo(want, 1e-9)
			end
		end
	end)

	it("push / apply / reset allocate nothing", function()
		local acc = Modifiers.newAccumulator()
		local list =
			{ mod("hp", "mul", 1.1), mod("moduleHp", "add", 3, { module = "Gun" }), mod("viewRange", "add", 10) }
		local sink = 0
		local function tick()
			Modifiers.reset(acc)
			Modifiers.pushList(acc, list, 0.5)
			sink += Modifiers.apply(acc, "hp", 100) + Modifiers.apply(acc, "moduleHp", 50, "Gun")
		end
		for _ = 1, 200 do
			tick()
		end
		local zero = 0
		for _ = 1, 20 do
			local before = collectgarbage("count")
			for _ = 1, 200 do
				tick()
			end
			if collectgarbage("count") == before then
				zero += 1
			end
		end
		expect(zero >= 18).toBe(true)
		expect(sink > 0).toBe(true)
	end)
end)

describe("Modifiers: conditions (Types/Content StatCondition)", function()
	it("table: each condition and its boundaries", function()
		local arm = Config.Spotting.STATIONARY_ARM_S
		-- condition, extra fields, conditions patch, expected
		local rows: { { any } } = {
			{ nil, nil, {}, true },
			{ "Always", nil, {}, true },
			{ "Stationary", nil, { moving = false }, true },
			{ "Stationary", nil, { moving = true }, false },
			{ "StationaryArmed", nil, { moving = false, stationaryForS = arm - 0.001 }, false },
			{ "StationaryArmed", nil, { moving = false, stationaryForS = arm }, true },
			{ "StationaryArmed", nil, { moving = true, stationaryForS = 99 }, false },
			{ "Moving", nil, { moving = true }, true },
			{ "TurretTraversing", nil, { turretTraversing = true }, true },
			{ "TurretTraversing", nil, {}, false },
			{ "AfterShot", { durationS = 3 }, { sinceShotS = 0 }, true },
			{ "AfterShot", { durationS = 3 }, { sinceShotS = 2.999 }, true },
			{ "AfterShot", { durationS = 3 }, { sinceShotS = 3 }, false }, -- half-open window
			{ "AfterShot", { durationS = 3 }, {}, false }, -- never fired
			{ "AfterShot", nil, { sinceShotS = 0 }, false }, -- no duration
			{ "AfterTakingDamage", { durationS = 5 }, { sinceDamageS = 4 }, true },
			{ "AfterSpotting", { durationS = 5 }, { sinceSpottingS = 5 }, false },
			{ "NearEnemy", { rangeM = 50 }, { nearestEnemyM = 50 }, true }, -- inclusive
			{ "NearEnemy", { rangeM = 50 }, { nearestEnemyM = 50.01 }, false },
			{ "NearEnemy", nil, { nearestEnemyM = 1 }, false }, -- no range
			{ "Spotted", nil, { spotted = true }, true },
			{ "LowHp", nil, { hpFraction = 0.25 }, true },
			{ "LowHp", nil, { hpFraction = 0.2501 }, false },
			{ "MechanicActive", nil, { mechanicActive = true }, true },
			{ "MechanicActive", nil, {}, false },
			{ "Bogus", nil, {}, false },
		}
		for i, row in rows do
			local extra = row[2] or {}
			if row[1] ~= nil then
				extra.condition = row[1]
			end
			local m = mod("hp", "mul", 2, extra)
			local c: any = Modifiers.newConditions()
			for k, v in row[3] do
				c[k] = v
			end
			if Modifiers.holds(m, c) ~= row[4] then
				error(`row {i} ({tostring(row[1])}): expected {tostring(row[4])}`)
			end
		end
	end)

	it("pushHolding folds only the modifiers whose condition holds", function()
		local c = Modifiers.newConditions()
		c.moving = true
		local acc = Modifiers.newAccumulator()
		local n = Modifiers.pushHolding(acc, {
			mod("camoMoving", "mul", 1.5, { condition = "Moving" }),
			mod("camoStationary", "mul", 1.5, { condition = "Stationary" }),
			mod("camoMoving", "add", 0.01),
		}, c)
		expect(n).toBe(2)
		expect(Modifiers.apply(acc, "camoMoving", 0.1)).toBeCloseTo(0.165, 1e-12)
		expect(Modifiers.apply(acc, "camoStationary", 0.1)).toBe(0.1)
		expect(Modifiers.pushHolding(acc, nil, c)).toBe(0)
	end)
end)
