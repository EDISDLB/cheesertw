-- Wire codes of the battle enums: stable, unique, round-trip, and aligned with the runtime lists other modules use.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Enums = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Enums")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local ALL = {
	Enums.ImmobileReason,
	Enums.MechanicPhase,
	Enums.MechanicKind,
	Enums.ModuleState,
	Enums.ModuleKind,
	Enums.CrewRole,
	Enums.ReloadKind,
	Enums.GunPhase,
	Enums.ShellKind,
	Enums.ShotResult,
	Enums.DamageKind,
	Enums.CaliberClass,
	Enums.QuickCommand,
	Enums.PingKind,
	Enums.RibbonKind,
	Enums.NoticeKind,
	Enums.EventType,
}

describe("Enums", function()
	it("every enum round-trips value <-> code with 1-based codes and 0 reserved", function()
		for _, enum in ALL do
			expect(#enum.values >= 1 and #enum.values <= 255).toBe(true)
			for code, value in enum.values do
				expect(Enums.encode(enum, value)).toBe(code)
				expect(Enums.decode(enum, code)).toBe(value)
			end
			expect(Enums.decode(enum, 0)).toBeNil()
			expect(Enums.decode(enum, #enum.values + 1)).toBeNil()
		end
	end)

	it("raises on unknown values when encoding and maps nil/'' to 0 for optional fields", function()
		expect(function()
			Enums.encode(Enums.ShellKind, "Laser")
		end).toThrow("unknown value Laser")
		expect(Enums.encodeOptional(Enums.ImmobileReason, nil)).toBe(0)
		expect(Enums.encodeOptional(Enums.MechanicKind, "")).toBe(0)
		expect(Enums.encodeOptional(Enums.MechanicKind, "Turbo")).toBe(4)
	end)

	it("pins the codes of the protocol (append-only; changing one needs a Protocol bump)", function()
		expect(Enums.EventType.values).toEqual({
			"ShotFired",
			"ShotHeard",
			"ShotResult",
			"ModuleState",
			"CrewInjured",
			"Damage",
			"Destroyed",
			"Spotted",
			"Lost",
			"SixthSense",
			"Fire",
			"Stunned",
			"ConsumableUsed",
			"Command",
			"Ping",
			"Ribbon",
			"Notice",
		})
		expect(Enums.ModuleState.values).toEqual({ "Ok", "Damaged", "Destroyed" })
		expect(#Enums.QuickCommand.values).toBe(12) -- 00-DECISIONS §9: 12 presets
		expect(#Enums.ModuleKind.values <= 15).toBe(true) -- packed into 4 bits by SnapshotCodec
	end)

	it("covers every mechanic the vehicle mechanics module knows", function()
		for kind in Common.KEYED do
			expect(Enums.MechanicKind.codes[kind]).never.toBeNil()
		end
		for kind in Common.EXOTIC do
			expect(Enums.MechanicKind.codes[kind]).never.toBeNil()
		end
	end)

	it("is frozen", function()
		expect(table.isfrozen(Enums)).toBe(true)
		expect(table.isfrozen(Enums.ShellKind.values)).toBe(true)
		expect(table.isfrozen(Enums.ShellKind.codes)).toBe(true)
	end)
end)
