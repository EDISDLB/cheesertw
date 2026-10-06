-- Mechanics/ReserveTracks: destroyed tracks replaced after repairS, one charge per job, cooldown between jobs; the
-- other side joins a running job; a job repaired by other means is cancelled without spending the charge
-- (content-schema §5.5).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ReserveTracks = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/ReserveTracks")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local SPEC: any = { kind = "ReserveTracks", charges = 2, repairS = 6, cooldownS = 30 }

describe("Mechanics/ReserveTracks", function()
	it("a destroyed track is replaced exactly repairS later; the charge is spent at completion", function()
		local s = ReserveTracks.new(SPEC, 0)
		expect(ReserveTracks.isArmed(s)).toBe(true)
		expect(ReserveTracks.onTrackDestroyed(s, "TrackLeft", 10)).toBe(true)
		expect(ReserveTracks.isActive(s)).toBe(true)
		expect(s.charges).toBe(2)
		expect(ReserveTracks.onTrackDestroyed(s, "TrackRight", 12)).toBe(true) -- joins the running job
		local left, right = ReserveTracks.update(s, 15.999)
		expect(left).toBe(false)
		left, right = ReserveTracks.update(s, 16)
		expect(left).toBe(true)
		expect(right).toBe(true)
		expect(s.charges).toBe(1)
		expect(s.phase).toBe("Cooldown")
		expect(ReserveTracks.onTrackDestroyed(s, "TrackLeft", 20)).toBe(false) -- cooling down: field repair applies
		ReserveTracks.update(s, 46)
		expect(ReserveTracks.isArmed(s)).toBe(true)
	end)

	it("a job whose tracks were repaired by other means is cancelled without spending a charge", function()
		local s = ReserveTracks.new(SPEC, 0)
		ReserveTracks.onTrackDestroyed(s, "TrackLeft", 0)
		ReserveTracks.onTrackDestroyed(s, "TrackRight", 1)
		ReserveTracks.onTrackRepaired(s, "TrackLeft", 2)
		expect(ReserveTracks.isActive(s)).toBe(true)
		ReserveTracks.onTrackRepaired(s, "TrackRight", 3)
		expect(s.phase).toBe("Off")
		expect(s.charges).toBe(2)
		ReserveTracks.onTrackRepaired(s, "TrackRight", 4) -- no job: no-op
		expect(s.phase).toBe("Off")
	end)

	it("rejections: out of charges, dead, not a track; automatic only", function()
		local one = ReserveTracks.new({ kind = "ReserveTracks", charges = 1, repairS = 6, cooldownS = 0 } :: any, 0)
		ReserveTracks.onTrackDestroyed(one, "TrackLeft", 0)
		ReserveTracks.update(one, 6)
		ReserveTracks.update(one, 6)
		expect(one.charges).toBe(0)
		expect(ReserveTracks.isArmed(one)).toBe(false)
		expect(ReserveTracks.onTrackDestroyed(one, "TrackLeft", 7)).toBe(false)
		local s = ReserveTracks.new(SPEC, 0)
		expect(ReserveTracks.onTrackDestroyed(s, "Engine", 0)).toBe(false)
		local ctx = Common.newContext()
		ctx.alive = false
		expect(ReserveTracks.onTrackDestroyed(s, "TrackLeft", 0, ctx)).toBe(false)
		expect(select(2, ReserveTracks.activate(s, 0))).toBe("AUTOMATIC")
		expect(select(2, ReserveTracks.deactivate(s, 0))).toBe("AUTOMATIC")
		expect(ReserveTracks.modifiers(s)).toBeNil()
	end)

	it("snapshot shows charges, the job and the cooldown", function()
		local s = ReserveTracks.new(SPEC, 0)
		ReserveTracks.onTrackDestroyed(s, "TrackRight", 0)
		local snap = ReserveTracks.snapshot(s, 3)
		expect(snap.active).toBe(true)
		expect(snap.progress).toBe(0.5)
		expect(snap.charges).toBe(2)
		expect(snap.cooldownRemainingS).toBe(33)
		expect(ReserveTracks.nextChange(s)).toBe(6)
	end)
end)
