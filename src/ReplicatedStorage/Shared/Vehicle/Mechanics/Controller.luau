--!strict
--[[
	Vehicle/Mechanics/Controller — owns a vehicle's VehicleSim-side special mechanics (the keyed SiegeMode / Turbo /
	RocketBoost machine, passive Hydropneumatic, automatic ReserveTracks) and drives VehicleSim's EXTERNAL mechanic
	mode (docs/design/movement.md §4.10: `state.mechanic.external = true`, the owner writes phase / timer / charges /
	hydroActive every tick and VehicleSim only applies the mobility effects of that phase).

	Purpose:          One object per vehicle that the battle tick (and client prediction) runs instead of VehicleSim's
	                  built-in copy, so auto-engage, per-charge RocketBoost recharges, exact phase times, HUD
	                  snapshots and the non-mobility modifiers (siege aim/dispersion → StatsCalculator runtime
	                  SOURCE.Mechanic) come from the one machine.
	Dependencies:     Core/Units, Mechanics/{Common, SiegeMode, Turbo, RocketBoost, Hydropneumatic, ReserveTracks},
	                  Types/Vehicle, Types/VehicleSim, Types/Content (type-only).
	State:            One Controller record per vehicle (machines, context, key edge state).
	Validation:       Machines validate their own numbers (Common helpers). A vehicle with the Wheeled mechanic keeps
	                  VehicleSim's built-in machine (this module has no Wheeled machine): `owns` is false and attach()
	                  leaves `external` off. GunState-placed mechanics (ChargedShot, ActiveCooling, AdaptiveMagazine)
	                  are ignored here.
	Error handling:   No throws; key presses that a machine rejects return (false, reason).
	Performance notes: Allocation-free after new(); O(1) per tick.

	Tick order (server and predicting client): input(pressed, now) → readSim(sim) → update(now) → writeSim(sim) →
	VehicleSim.step. ReserveTracks: call onTrackDestroyed / onTrackRepaired from the module system; update() reports
	(leftReplaced, rightReplaced) for the caller to restore those modules.
]]

local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local Common = require("./Common")
local SiegeMode = require("./SiegeMode")
local Turbo = require("./Turbo")
local RocketBoost = require("./RocketBoost")
local Hydropneumatic = require("./Hydropneumatic")
local ReserveTracks = require("./ReserveTracks")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local SimTypes = require("@game/ReplicatedStorage/Shared/Types/VehicleSim")

type SpecialMechanic = ContentTypes.SpecialMechanic
type StatModifier = ContentTypes.StatModifier
type InternalModuleKind = ContentTypes.InternalModuleKind
type VehicleSimState = SimTypes.VehicleSimState
type Context = Common.Context
type Snapshot = Common.Snapshot

export type KeyedKind = "SiegeMode" | "Turbo" | "RocketBoost" | ""

export type Controller = {
	keyedKind: KeyedKind,
	siege: SiegeMode.State?,
	turbo: Turbo.State?,
	rocket: RocketBoost.State?,
	hydro: Hydropneumatic.State?,
	reserve: ReserveTracks.State?,
	wheeled: boolean, -- the vehicle has Wheeled: VehicleSim's built-in machine keeps running
	owns: boolean, -- drives VehicleSim's external mode (keyed and/or Hydropneumatic machines, no Wheeled)
	ctx: Context,
	lastInput: boolean,
	time: number,
}

export type ControllerOptions = {
	autoEngage: boolean?, -- SiegeMode auto-engage player option (default: on when the spec defines autoEngageS)
}

local Controller = {}

--- Builds the machines for `mechanics` (VehicleStats.mechanics: resolved copies) at battle time `now`.
function Controller.new(mechanics: { SpecialMechanic }?, now: number?, opts: ControllerOptions?): Controller
	local t = Common.time(now, 0)
	local ctrl: Controller = {
		keyedKind = "",
		siege = nil,
		turbo = nil,
		rocket = nil,
		hydro = nil,
		reserve = nil,
		wheeled = false,
		owns = false,
		ctx = Common.newContext(),
		lastInput = false,
		time = t,
	}
	if mechanics ~= nil then
		for _, spec in mechanics do
			if spec.kind == "Wheeled" then
				ctrl.wheeled = true
			elseif spec.kind == "Hydropneumatic" and ctrl.hydro == nil then
				ctrl.hydro = Hydropneumatic.new(spec, t)
			elseif spec.kind == "ReserveTracks" and ctrl.reserve == nil then
				ctrl.reserve = ReserveTracks.new(spec, t)
			elseif ctrl.keyedKind == "" then
				-- the first keyed mechanic wins (content allows one per vehicle; VehicleSim picks the same one)
				if spec.kind == "SiegeMode" then
					ctrl.siege = SiegeMode.new(spec, t, { autoEngage = if opts ~= nil then opts.autoEngage else nil })
					ctrl.keyedKind = "SiegeMode"
				elseif spec.kind == "Turbo" then
					ctrl.turbo = Turbo.new(spec, t)
					ctrl.keyedKind = "Turbo"
				elseif spec.kind == "RocketBoost" then
					ctrl.rocket = RocketBoost.new(spec, t)
					ctrl.keyedKind = "RocketBoost"
				end
			end
		end
	end
	ctrl.owns = not ctrl.wheeled and (ctrl.keyedKind ~= "" or ctrl.hydro ~= nil)
	return ctrl
end

--- Hands VehicleSim's mechanic machine to this controller (external mode) when it owns one; otherwise leaves the
--- built-in machine in charge. Call once after VehicleSim.newState.
function Controller.attach(ctrl: Controller, sim: VehicleSimState)
	sim.mechanic.external = ctrl.owns
	if ctrl.owns then
		Controller.writeSim(ctrl, sim)
	end
end

--- Fills the context from the hull state of the last sim step: alive = not wrecked, mobile = not immobilized
--- (engine / tracks destroyed, overturned, drowned …), grounded, |speed| in km/h, stationary time.
function Controller.readSim(ctrl: Controller, sim: VehicleSimState)
	local ctx = ctrl.ctx
	ctx.alive = not sim.wrecked
	ctx.mobile = not sim.immobilized
	ctx.grounded = sim.grounded
	ctx.speedKmh = math.abs(Units.studsPerSecToKmh(sim.speed))
	ctx.stationaryForS = sim.stillTime
end

--- The caller-owned context (fill it directly when there is no VehicleSimState, e.g. tests or bots).
function Controller.context(ctrl: Controller): Context
	return ctrl.ctx
end

local function press(ctrl: Controller, now: number): (boolean, string?)
	local siege, turbo, rocket = ctrl.siege, ctrl.turbo, ctrl.rocket
	if siege ~= nil then
		return SiegeMode.toggle(siege, now, ctrl.ctx)
	elseif turbo ~= nil then
		return Turbo.activate(turbo, now, ctrl.ctx)
	elseif rocket ~= nil then
		return RocketBoost.activate(rocket, now, ctrl.ctx)
	end
	return false, "NO_MECHANIC"
end

--- The mechanic key (InputCommand.mechanic) at `now`, edge-triggered: a press acts once; holding does nothing.
--- Returns (acted, reason) for the press edge, (false, nil) otherwise.
function Controller.input(ctrl: Controller, pressed: boolean, now: number): (boolean, string?)
	local edge = pressed and not ctrl.lastInput
	ctrl.lastInput = pressed
	if not edge then
		return false, nil
	end
	return press(ctrl, Common.time(now, ctrl.time))
end

--- Presses the key once (remote command / bots) regardless of the held state.
function Controller.press(ctrl: Controller, now: number): (boolean, string?)
	return press(ctrl, Common.time(now, ctrl.time))
end

--- Advances every machine to `now` with the current context. Returns (changed, leftReplaced, rightReplaced):
--- `changed` = a keyed/hydro phase or charge changed; the booleans report ReserveTracks jobs that completed.
function Controller.update(ctrl: Controller, now: number): (boolean, boolean, boolean)
	local t = Common.time(now, ctrl.time)
	if t < ctrl.time then
		t = ctrl.time
	end
	ctrl.time = t
	local ctx = ctrl.ctx
	local changed = false
	local siege, turbo, rocket, hydro, reserve = ctrl.siege, ctrl.turbo, ctrl.rocket, ctrl.hydro, ctrl.reserve
	if siege ~= nil then
		changed = SiegeMode.update(siege, t, ctx) or changed
	end
	if turbo ~= nil then
		changed = Turbo.update(turbo, t, ctx) or changed
	end
	if rocket ~= nil then
		changed = RocketBoost.update(rocket, t, ctx) or changed
	end
	if hydro ~= nil then
		changed = Hydropneumatic.update(hydro, t, ctx) or changed
	end
	local left, right = false, false
	if reserve ~= nil then
		left, right = ReserveTracks.update(reserve, t, ctx)
	end
	return changed, left, right
end

local function keyedState(ctrl: Controller): any
	return ctrl.siege or ctrl.turbo or ctrl.rocket
end

--- Writes phase / timer / charges / hydroActive into VehicleSim's mechanic runtime (external mode only).
function Controller.writeSim(ctrl: Controller, sim: VehicleSimState)
	if not ctrl.owns then
		return
	end
	local mech = sim.mechanic
	local keyed = keyedState(ctrl)
	if keyed ~= nil then
		mech.phase = keyed.phase
		local left = keyed.phaseEnd - ctrl.time
		mech.timer = if left > 0 and left < math.huge then left else 0
		local rocket = ctrl.rocket
		mech.charges = if rocket ~= nil then rocket.charges else math.huge
	else
		mech.phase = "Off"
		mech.timer = 0
	end
	local hydro = ctrl.hydro
	mech.hydroActive = hydro ~= nil and Hydropneumatic.isActive(hydro)
end

--- StatCondition "MechanicActive" of the keyed mechanic (siege engaged, turbo/boost burning).
function Controller.isActive(ctrl: Controller): boolean
	local siege, turbo, rocket = ctrl.siege, ctrl.turbo, ctrl.rocket
	if siege ~= nil then
		return SiegeMode.isActive(siege)
	elseif turbo ~= nil then
		return Turbo.isActive(turbo)
	elseif rocket ~= nil then
		return RocketBoost.isActive(rocket)
	end
	return false
end

--- The keyed machine's modifiers while active (StatsCalculator runtime SOURCE.Mechanic; the runtime skips the
--- mobility/arc stats VehicleSim applies itself), else nil.
function Controller.modifiers(ctrl: Controller): { StatModifier }?
	local siege, turbo, rocket = ctrl.siege, ctrl.turbo, ctrl.rocket
	if siege ~= nil then
		return SiegeMode.modifiers(siege)
	elseif turbo ~= nil then
		return Turbo.modifiers(turbo)
	elseif rocket ~= nil then
		return RocketBoost.modifiers(rocket)
	end
	return nil
end

--- Earliest scheduled change of any machine (math.huge = none): lets a server skip idle vehicles.
function Controller.nextChange(ctrl: Controller): number
	local soonest = math.huge
	local siege, turbo, rocket, hydro, reserve = ctrl.siege, ctrl.turbo, ctrl.rocket, ctrl.hydro, ctrl.reserve
	if siege ~= nil then
		soonest = math.min(soonest, SiegeMode.nextChange(siege))
	end
	if turbo ~= nil then
		soonest = math.min(soonest, Turbo.nextChange(turbo))
	end
	if rocket ~= nil then
		soonest = math.min(soonest, RocketBoost.nextChange(rocket))
	end
	if hydro ~= nil then
		soonest = math.min(soonest, Hydropneumatic.nextChange(hydro))
	end
	if reserve ~= nil then
		soonest = math.min(soonest, ReserveTracks.nextChange(reserve))
	end
	return soonest
end

--- HUD view of the keyed mechanic (else the Hydropneumatic settle), nil when the vehicle has neither.
function Controller.snapshot(ctrl: Controller, now: number, out: Snapshot?): Snapshot?
	local siege, turbo, rocket, hydro = ctrl.siege, ctrl.turbo, ctrl.rocket, ctrl.hydro
	if siege ~= nil then
		return SiegeMode.snapshot(siege, now, out)
	elseif turbo ~= nil then
		return Turbo.snapshot(turbo, now, out)
	elseif rocket ~= nil then
		return RocketBoost.snapshot(rocket, now, out)
	elseif hydro ~= nil then
		return Hydropneumatic.snapshot(hydro, now, out)
	end
	return nil
end

--- A track was destroyed (module system): true when ReserveTracks took the replacement over.
function Controller.onTrackDestroyed(ctrl: Controller, side: InternalModuleKind, now: number): boolean
	local reserve = ctrl.reserve
	if reserve == nil then
		return false
	end
	return ReserveTracks.onTrackDestroyed(reserve, side, now, ctrl.ctx)
end

--- A track left the Destroyed state by other means (repair kit, field repair).
function Controller.onTrackRepaired(ctrl: Controller, side: InternalModuleKind, now: number)
	local reserve = ctrl.reserve
	if reserve ~= nil then
		ReserveTracks.onTrackRepaired(reserve, side, now)
	end
end

return Controller
