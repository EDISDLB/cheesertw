--!strict
--[[
	Vehicle/GunState — the server-authoritative gun: reload state machines for every ReloadSpec kind (Single,
	Magazine, Autoreloader, DualGun), shell selection and swap rules, ammo accounting, the fire trigger (press, hold,
	release), the GunState-placed mechanics (ChargedShot, ActiveCooling, AdaptiveMagazine) and the HUD/replication
	snapshot (00-DECISIONS §4; ARCHITECTURE §6.1 step 3, §12 "reload bypass impossible").

	Purpose:          canFire / fire / setTrigger decide every shot; reload progress runs on exact absolute times with
	                  a runtime reload multiplier (loader injured, ammo rack damaged, stun, conditional skills) and
	                  ActiveCooling windows, so the outcome never depends on the tick rate.
	Dependencies:     Config (optional VehicleStats section, see DEFAULTS), Combat/DamageModel (setAmmoStored),
	                  Mechanics/Common, Mechanics/ChargedShot, Mechanics/ActiveCooling, Types/Vehicle, Types/Content,
	                  Types/Combat (type-only).
	State:            One GunState record per vehicle (timers, magazine/barrels, ammo slots, trigger, mechanics, a
	                  reused ShotInfo record). No module-level state.
	Validation:       Times that are NaN/±inf or earlier than the state's clock are ignored (time never runs
	                  backwards); reload multipliers are clamped to [MIN_RELOAD_MUL, MAX_RELOAD_MUL]; ammo counts are
	                  floored to whole rounds >= 0 and capped at ammoCapacity; unknown shells in the loadout are dropped.
	Error handling:   No throws. Refusals return (nil | false, reason) with reasons DEAD, GUN_DESTROYED, OVERTURNED,
	                  RELOADING, INTRA_CLIP, SALVO_DELAY, EMPTY, NO_AMMO, UNKNOWN_SHELL, FULL, NOT_SUPPORTED,
	                  NO_MECHANIC, ACTIVE, COOLDOWN (mapped to NOT_ALLOWED at the remote boundary).
	Performance notes: Every call advances event-to-event (at most a few timer completions per tick); no table is
	                  allocated after new(): shots reuse `state.shot`, snapshots write into a caller-owned record.

	Rules (exact values in docs/design/vehicle-stats.md §4):
	  * Timers hold remaining BASE seconds (GunStats values, crew/equipment already applied). Real time = base ×
	    reloadMul × ActiveCooling factor, re-evaluated at every change, so an injury mid-reload slows only the rest.
	  * Single: one chambered round; reload starts when it fires. Magazine: intraClipS between shots, full reloadS when
	    empty (a manual reload of a partial magazine costs the full reloadS). Autoreloader: one round at a time, the
	    refill of magazine slot k (k = rounds + 1) takes perShellReloadS[k]; firing never resets a running refill.
	    DualGun: two barrels reloading independently (reloadEachS), salvoDelayS between single shots, hold-to-volley.
	  * Shell swap (00-DECISIONS §4 "ammo swap when loaded = full reload"): selecting another shell while a round of
	    the old one is loaded unloads it back to the rack and starts a full reload of the new shell with every timer
	    × swapFactor (= GunStats.shellSwapS ÷ one reload, so Intuition shortens it). Switching while nothing is
	    loaded only changes what the running reload loads (progress kept). Running out of the selected shell selects
	    the next shell with rounds (hotkey order).
	  * Trigger: Single/Magazine/Autoreloader fire on press. DualGun (ui-ux H-05): a press shorter than DUAL_GUN_TAP_S
	    fires one barrel on release; holding with both barrels loaded charges a volley that fires automatically
	    chargeTimeS after the later of the press and the second barrel loading; releasing a charging volley cancels
	    it. ChargedShot: hold charges while loaded, release fires (bonus only at full charge).
	  * Death freezes everything; a timer that completes exactly at the death time counts as completed (inclusive),
	    but nothing fires after kill(). A destroyed gun or an overturned vehicle (00-DECISIONS §2 "gun off") blocks
	    firing and cancels charges; reloads keep running (the crew still loads).
	  * DamageModel's ammo-rack detonation needs >= 1 stored shell: storedAmmo() = rounds not in the gun (rack and
	    rounds being loaded); syncAmmoStored() writes it after every change (shot, swap, reload start).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
local Common = require("./Mechanics/Common")
local ChargedShot = require("./Mechanics/ChargedShot")
local ActiveCooling = require("./Mechanics/ActiveCooling")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")

type VehicleCombatState = CombatTypes.VehicleCombatState
type GunStats = VehicleTypes.GunStats
type ShellStats = VehicleTypes.ShellStats
type AmmoLoad = VehicleTypes.AmmoLoad
type SpecialMechanic = ContentTypes.SpecialMechanic
type StatModifier = ContentTypes.StatModifier

export type ReloadKind = "Single" | "Magazine" | "Autoreloader" | "DualGun"
export type GunPhase = "Ready" | "Reloading" | "IntraClip" | "Charging" | "Empty" | "Disabled" | "Dead"

--- One loadout ammo entry (hotkey order = Loadout.ammo order).
export type AmmoSlot = {
	shell: ShellStats,
	id: string,
	total: number, -- rounds of this shell left anywhere (rack + gun); only firing lowers it
	rack: number, -- rounds stored and not reserved by a running reload
}

--- A reload timer: `work` = remaining base seconds, `total` = base seconds of the whole cycle.
export type Timer = {
	active: boolean,
	work: number,
	total: number,
	slot: number, -- ammo slot being loaded (0 for clip / salvo timers)
	rounds: number, -- rounds reserved from the rack for this load
}

--- Emitted for every shot (one record reused per GunState: copy what you keep).
export type ShotInfo = {
	time: number, -- exact shot time (an auto-fired volley carries its own instant)
	slot: number,
	shellId: string,
	shell: ShellStats,
	rounds: number, -- 1, or 2 for a dual-gun volley (spawn two projectiles, REG-PRJ-05)
	barrel: number, -- DualGun single: 1 or 2; volley: 0; other guns: 1
	volley: boolean,
	charged: boolean, -- ChargedShot released at full charge
	dispersionMul: number, -- × aiming radius for this shot (volley, charged Accuracy)
	damageMul: number, -- × alpha for this shot (charged Damage)
	ammoLeft: number, -- rounds of this shell left after the shot (rack + gun)
	magazineLeft: number, -- rounds ready in the gun after the shot
}

--- HUD / replication view (caller-owned; GunState.newSnapshot sizes the arrays).
export type GunSnapshot = {
	kind: ReloadKind,
	phase: GunPhase,
	alive: boolean,
	enabled: boolean,
	overturned: boolean,
	canFire: boolean,
	selectedSlot: number,
	loadedSlot: number, -- shell slot of the round(s) ready in the gun (0 = none)
	reloadProgress: number, -- 0..1 of the main reload timer (1 = nothing loading and rounds ready)
	reloadRemainingS: number, -- real seconds left on the main reload timer (0 when none runs)
	reloadDurationS: number, -- real seconds of the whole main timer at the current rate
	nextShotS: number, -- seconds until fire() would succeed (0 = now, math.huge = not without help)
	intraClipRemainingS: number, -- Magazine/Autoreloader clip timer, DualGun salvo delay
	roundsLoaded: number, -- Single 0/1, magazine rounds, loaded barrels
	magazineSize: number,
	toppingOff: boolean, -- AdaptiveMagazine top-off running
	refillSlotIndex: number, -- Autoreloader: magazine position being refilled (0 = none)
	chargeProgress: number, -- volley / charged-shot charge 0..1
	reloadMul: number, -- effective multiplier on reload timers now (runtime × ActiveCooling)
	ammo: { number }, -- per slot: rounds left (rack + gun)
	totalAmmo: number,
	barrelProgress: { number }, -- DualGun: per barrel 0..1 (1 = loaded); empty for other kinds
}

export type GunStateOptions = {
	now: number?, -- battle time at creation (default 0)
	mechanics: { SpecialMechanic }?, -- VehicleStats.mechanics (ChargedShot, ActiveCooling, AdaptiveMagazine are used)
	startLoaded: boolean?, -- default DEFAULTS.START_LOADED
	resetChargeOnMove: boolean?, -- ChargedShot movement rule (default DEFAULTS.CHARGED_SHOT_RESET_ON_MOVE)
	reloadMul: number?, -- initial runtime reload multiplier (default 1)
}

export type GunState = {
	kind: ReloadKind,
	gun: GunStats,
	slots: { AmmoSlot },
	selected: number, -- slot the next load uses (0 = no ammo slots)
	time: number,
	alive: boolean,
	enabled: boolean, -- gun module working (not Destroyed)
	overturned: boolean, -- vehicle overturned: gun off until righted
	reloadMul: number,
	swapFactor: number,
	-- resolved reload numbers (base seconds)
	reloadS: number, -- Single reloadS / Magazine reloadS / DualGun reloadEachS / Autoreloader perShell[1]
	intraClipS: number,
	size: number, -- rounds the gun holds ready: 1, magazine size, 2 barrels
	perShell: { number },
	salvoS: number,
	volleyChargeS: number,
	volleyDispersionMul: number,
	-- contents
	loadedSlot: number, -- Single
	loadedAt: number,
	mag: number, -- Magazine / Autoreloader rounds ready
	magSlot: number,
	barrelSlot: { number }, -- DualGun (0 = empty)
	barrelAt: { number },
	-- timers (fixed iteration order in `timers`)
	load: Timer,
	refill: Timer,
	barrel1: Timer,
	barrel2: Timer,
	clip: Timer,
	salvo: Timer,
	timers: { Timer },
	topOff: boolean,
	swapCycle: boolean, -- Autoreloader refills × swapFactor until the magazine is full again
	-- trigger
	triggerHeld: boolean,
	triggerAt: number,
	triggerConsumed: boolean,
	moving: boolean,
	-- mechanics
	charged: ChargedShot.State?,
	cooling: ActiveCooling.State?,
	adaptiveFactor: number, -- AdaptiveMagazine partialReloadFactor (0 = no AdaptiveMagazine)
	ctx: Common.Context,
	-- output
	shot: ShotInfo,
	pending: boolean, -- an auto-fired volley waits in `shot` for the next update / setTrigger / fire
	shotsFired: number,
	roundsFired: number,
}

local GunState = {}

--- Tunables. Read through `Config.VehicleStats` when that section exists (live-overridable), else these defaults.
local DEFAULTS = table.freeze({
	--- DualGun: a press shorter than this fires one barrel on release; longer holds charge a volley (ui-ux H-05).
	DUAL_GUN_TAP_S = 0.25,
	--- ChargedShot: hull movement above the stop speed resets the charge to 0; it resumes when the hull stops
	--- (roster §2.7 signature rules + ui-ux H-05: "a positional commitment, never a free brawling buff").
	CHARGED_SHOT_RESET_ON_MOVE = true,
	--- Guns start the battle loaded (magazines full).
	START_LOADED = true,
	--- Clamp of the runtime reload multiplier (stacked injuries/stun cannot freeze or invert a reload).
	MIN_RELOAD_MUL = 0.05,
	MAX_RELOAD_MUL = 20,
	--- Shortest timer (base seconds): guards zero-length reload data against event storms.
	MIN_TIMER_S = 0.001,
})
GunState.DEFAULTS = DEFAULTS

local function setting(key: string): any
	local section = (Config :: any).VehicleStats
	if type(section) == "table" then
		local v = section[key]
		if v ~= nil then
			return v
		end
	end
	return (DEFAULTS :: any)[key]
end

local EPS = Common.EPS
local WORK_EPS = 1e-9
local MAX_STEPS = 64

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function positive(x: any, default: number): number
	return if finite(x) and x > 0 then x else default
end

local function newTimer(): Timer
	return { active = false, work = 0, total = 0, slot = 0, rounds = 0 }
end

--------------------------------------------------------------------------------
-- Ammo
--------------------------------------------------------------------------------

-- First slot with rack rounds, starting at `preferred` and continuing in hotkey order (wrapping). 0 = none.
local function pickSlot(state: GunState, preferred: number): number
	local n = #state.slots
	if n == 0 then
		return 0
	end
	local start = if preferred >= 1 and preferred <= n then preferred else 1
	for i = 0, n - 1 do
		local index = ((start - 1 + i) % n) + 1
		if state.slots[index].rack > 0 then
			return index
		end
	end
	return 0
end

local function totalAmmo(state: GunState): number
	local sum = 0
	for _, slot in state.slots do
		sum += slot.total
	end
	return sum
end

local function release(state: GunState, timer: Timer)
	if timer.rounds > 0 and timer.slot > 0 then
		local slot = state.slots[timer.slot]
		slot.rack += timer.rounds
	end
	timer.active = false
	timer.work = 0
	timer.total = 0
	timer.slot = 0
	timer.rounds = 0
end

local function start(timer: Timer, work: number, slot: number, rounds: number)
	local w = math.max(setting("MIN_TIMER_S"), work)
	timer.active = true
	timer.work = w
	timer.total = w
	timer.slot = slot
	timer.rounds = rounds
end

local function roundsLoaded(state: GunState): number
	local kind = state.kind
	if kind == "Single" then
		return if state.loadedSlot ~= 0 then 1 else 0
	elseif kind == "DualGun" then
		return (if state.barrelSlot[1] ~= 0 then 1 else 0) + (if state.barrelSlot[2] ~= 0 then 1 else 0)
	end
	return state.mag
end

--------------------------------------------------------------------------------
-- Starting reloads
--------------------------------------------------------------------------------

local function startLoad(state: GunState, factor: number)
	local slot = pickSlot(state, state.selected)
	if slot == 0 then
		return
	end
	state.selected = slot
	state.slots[slot].rack -= 1
	start(state.load, state.reloadS * factor, slot, 1)
end

local function startFullReload(state: GunState, factor: number)
	local slot = pickSlot(state, state.selected)
	if slot == 0 then
		return
	end
	state.selected = slot
	local ammo = state.slots[slot]
	local n = math.min(state.size, ammo.rack)
	ammo.rack -= n
	state.topOff = false
	start(state.refill, state.reloadS * factor, slot, n)
end

local function startRefillAuto(state: GunState)
	if state.refill.active or state.mag >= state.size then
		return
	end
	local slot
	if state.mag == 0 then
		slot = pickSlot(state, state.selected)
	else
		slot = if state.slots[state.magSlot].rack > 0 then state.magSlot else 0
	end
	if slot == 0 then
		return
	end
	state.selected = if state.mag == 0 then slot else state.selected
	state.slots[slot].rack -= 1
	local index = math.clamp(state.mag + 1, 1, #state.perShell)
	local factor = if state.swapCycle then state.swapFactor else 1
	start(state.refill, state.perShell[index] * factor, slot, 1)
end

local function startBarrel(state: GunState, barrel: number, factor: number)
	local timer = if barrel == 1 then state.barrel1 else state.barrel2
	if timer.active or state.barrelSlot[barrel] ~= 0 then
		return
	end
	local slot = pickSlot(state, state.selected)
	if slot == 0 then
		return
	end
	state.selected = slot
	state.slots[slot].rack -= 1
	start(timer, state.reloadS * factor, slot, 1)
end

--------------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------------

local function coolingFactor(state: GunState): number
	local cooling = state.cooling
	if cooling ~= nil and cooling.phase == "On" then
		return cooling.reloadFactor
	end
	return 1
end

local function effectiveMul(state: GunState): number
	return state.reloadMul * coolingFactor(state)
end

-- Real seconds needed for `work` base seconds from the current time (exact across an ActiveCooling window end).
local function realTime(state: GunState, work: number): number
	local mul = state.reloadMul
	local cooling = state.cooling
	if cooling ~= nil and cooling.phase == "On" then
		local fast = mul * cooling.reloadFactor
		local window = math.max(0, cooling.phaseEnd - state.time)
		if work * fast <= window then
			return work * fast
		end
		return window + (work - window / fast) * mul
	end
	return work * mul
end

-- The gun may fire / charge (alive, gun module working, vehicle not overturned).
local function armed(state: GunState): boolean
	return state.alive and state.enabled and not state.overturned
end

local function chargingVolley(state: GunState): boolean
	return state.kind == "DualGun"
		and state.triggerHeld
		and not state.triggerConsumed
		and armed(state)
		and state.barrelSlot[1] ~= 0
		and state.barrelSlot[1] == state.barrelSlot[2]
end

local function volleyStart(state: GunState): number
	return math.max(state.triggerAt, state.barrelAt[1], state.barrelAt[2])
end

-- Absolute time of the automatic volley, or math.huge.
local function volleyEventTime(state: GunState): number
	if not chargingVolley(state) then
		return math.huge
	end
	return volleyStart(state) + state.volleyChargeS
end

local function writeShot(
	state: GunState,
	slot: number,
	rounds: number,
	barrel: number,
	volley: boolean,
	charged: boolean,
	dispersionMul: number,
	damageMul: number,
	time: number
): ShotInfo
	local ammo = state.slots[slot]
	ammo.total = math.max(0, ammo.total - rounds)
	local s = state.shot
	s.time = time
	s.slot = slot
	s.shellId = ammo.id
	s.shell = ammo.shell
	s.rounds = rounds
	s.barrel = barrel
	s.volley = volley
	s.charged = charged
	s.dispersionMul = dispersionMul
	s.damageMul = damageMul
	s.ammoLeft = ammo.total
	s.magazineLeft = roundsLoaded(state)
	state.shotsFired += 1
	state.roundsFired += rounds
	return s
end

local function fireVolley(state: GunState, time: number)
	local slot = state.barrelSlot[1]
	state.barrelSlot[1] = 0
	state.barrelSlot[2] = 0
	state.triggerConsumed = true
	writeShot(state, slot, 2, 0, true, false, state.volleyDispersionMul, 1, time)
	startBarrel(state, 1, 1)
	startBarrel(state, 2, 1)
	state.pending = true
end

-- Completion handlers (timer already deactivated by the caller).
local function onLoaded(state: GunState, timer: Timer)
	local kind = state.kind
	if kind == "Single" then
		state.loadedSlot = timer.slot
		state.loadedAt = state.time
		local charged = state.charged
		if charged ~= nil and state.triggerHeld and not state.triggerConsumed and armed(state) then
			ChargedShot.begin(charged, state.time, state.ctx)
		end
	elseif kind == "Magazine" then
		if state.topOff then
			state.mag += timer.rounds
		else
			state.mag = timer.rounds
			state.magSlot = timer.slot
		end
		state.topOff = false
	elseif kind == "Autoreloader" then
		state.mag += timer.rounds
		state.magSlot = timer.slot
		if state.mag >= state.size then
			state.swapCycle = false
		end
	else
		local barrel = if timer == state.barrel1 then 1 else 2
		state.barrelSlot[barrel] = timer.slot
		state.barrelAt[barrel] = state.time
	end
end

local function completeTimers(state: GunState)
	for _, timer in state.timers do
		if timer.active and timer.work <= WORK_EPS then
			timer.active = false
			timer.work = 0
			if timer.slot ~= 0 then
				onLoaded(state, timer) -- hands the reserved rounds (timer.slot, timer.rounds) to the gun
			end
			timer.slot = 0
			timer.rounds = 0
		end
	end
	if state.kind == "Autoreloader" then
		startRefillAuto(state)
	end
end

-- Advances every timer to `now`, stopping at each completion, ActiveCooling window end and automatic volley.
local function advance(state: GunState, now: number)
	if not finite(now) or now <= state.time then
		return
	end
	if not state.alive then
		state.time = now
		return
	end
	for _ = 1, MAX_STEPS do
		local t = state.time
		local cooling = state.cooling
		if cooling ~= nil then
			ActiveCooling.update(cooling, t, state.ctx)
		end
		local volleyAt = volleyEventTime(state)
		if volleyAt <= t + EPS then
			fireVolley(state, t)
			continue
		end
		if t >= now then
			break
		end
		local segEnd = math.min(now, volleyAt)
		if cooling ~= nil and cooling.phase == "On" and cooling.phaseEnd < segEnd then
			segEnd = math.max(t, cooling.phaseEnd)
		end
		local mul = effectiveMul(state)
		local minWork = math.huge
		for _, timer in state.timers do
			if timer.active and timer.work < minWork then
				minWork = timer.work
			end
		end
		local span = segEnd - t
		if minWork * mul <= span + EPS then
			for _, timer in state.timers do
				if timer.active then
					timer.work = math.max(0, timer.work - minWork)
				end
			end
			state.time = math.min(now, t + minWork * mul)
			completeTimers(state)
		else
			local used = span / mul
			for _, timer in state.timers do
				if timer.active then
					timer.work = math.max(0, timer.work - used)
				end
			end
			state.time = segEnd
		end
	end
	if state.time < now then
		state.time = now -- MAX_STEPS guard (pathological data): never let the clock lag
	end
	local cooling = state.cooling
	if cooling ~= nil then
		ActiveCooling.update(cooling, state.time, state.ctx)
	end
end

local function takePending(state: GunState): ShotInfo?
	if state.pending then
		state.pending = false
		return state.shot
	end
	return nil
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function buildSlots(gun: GunStats, ammo: { AmmoLoad }?): { AmmoSlot }
	local slots: { AmmoSlot } = {}
	local capacity = if finite(gun.ammoCapacity) then math.max(0, math.floor(gun.ammoCapacity)) else math.huge
	local used = 0
	local seen: { [string]: boolean } = {}
	if ammo == nil then
		return slots
	end
	for _, load in ammo do
		if type(load) ~= "table" or type(load.shell) ~= "string" or seen[load.shell] then
			continue
		end
		local shell: ShellStats? = nil
		for _, s in gun.shells do
			if s.id == load.shell then
				shell = s
				break
			end
		end
		if shell == nil then
			continue
		end
		seen[load.shell] = true
		local count = if finite(load.count) then math.max(0, math.floor(load.count)) else 0
		count = math.min(count, capacity - used)
		used += count
		table.insert(slots, { shell = shell, id = load.shell, total = count, rack = count })
	end
	return slots
end

--- A gun at battle start. `ammo` = the loadout's ammo list (hotkey order); shells the gun does not fire are
--- dropped and counts are capped at ammoCapacity in list order.
function GunState.new(gun: GunStats, ammo: { AmmoLoad }?, opts: GunStateOptions?): GunState
	local o: GunStateOptions = opts or {}
	local now = if finite(o.now) then o.now :: number else 0
	local reload = gun.reload
	local kind: ReloadKind = reload.kind
	local reloadS, intraClipS, size, salvoS, chargeS, volleyMul = 1, 0, 1, 0, 1, 1
	local perShell: { number } = {}
	if reload.kind == "Single" then
		reloadS = positive(reload.reloadS, 1)
	elseif reload.kind == "Magazine" then
		reloadS = positive(reload.reloadS, 1)
		intraClipS = positive(reload.intraClipS, 0)
		size = math.max(1, math.floor(positive(reload.size, 1)))
	elseif reload.kind == "Autoreloader" then
		intraClipS = positive(reload.intraClipS, 0)
		size = math.max(1, math.floor(positive(reload.size, 1)))
		for i = 1, size do
			local t = reload.perShellReloadS[i] or reload.perShellReloadS[#reload.perShellReloadS]
			perShell[i] = positive(t, 1)
		end
		reloadS = perShell[1]
	elseif reload.kind == "DualGun" then
		reloadS = positive(reload.reloadEachS, 1)
		salvoS = positive(reload.salvoDelayS, 0)
		chargeS = positive(reload.chargeTimeS, 1)
		volleyMul = positive(reload.volleyDispersionMul, 1)
		size = 2
	end
	local swapFactor = 1
	if finite(gun.shellSwapS) and gun.shellSwapS > 0 then
		swapFactor = gun.shellSwapS / reloadS
	end

	local charged: ChargedShot.State? = nil
	local cooling: ActiveCooling.State? = nil
	local adaptive = 0
	if o.mechanics ~= nil then
		local resetOnMove = if o.resetChargeOnMove ~= nil
			then o.resetChargeOnMove
			else setting("CHARGED_SHOT_RESET_ON_MOVE") == true
		for _, spec in o.mechanics do
			if spec.kind == "ChargedShot" and kind == "Single" then
				charged = ChargedShot.new(spec, now, { resetOnMove = resetOnMove })
			elseif spec.kind == "ActiveCooling" then
				cooling = ActiveCooling.new(spec, now)
			elseif spec.kind == "AdaptiveMagazine" and kind == "Magazine" then
				adaptive = math.clamp(positive(spec.partialReloadFactor, 1), 0.05, 1)
			end
		end
	end

	local load, refill, barrel1, barrel2, clip, salvo =
		newTimer(), newTimer(), newTimer(), newTimer(), newTimer(), newTimer()
	local slots = buildSlots(gun, ammo)
	local selected = 0
	for i, slot in slots do
		if slot.total > 0 then
			selected = i
			break
		end
	end
	if selected == 0 and #slots > 0 then
		selected = 1
	end
	local state: GunState = {
		kind = kind,
		gun = gun,
		slots = slots,
		selected = selected,
		time = now,
		alive = true,
		enabled = true,
		overturned = false,
		reloadMul = 1,
		swapFactor = swapFactor,
		reloadS = reloadS,
		intraClipS = intraClipS,
		size = size,
		perShell = perShell,
		salvoS = salvoS,
		volleyChargeS = chargeS,
		volleyDispersionMul = volleyMul,
		loadedSlot = 0,
		loadedAt = now,
		mag = 0,
		magSlot = selected,
		barrelSlot = { 0, 0 },
		barrelAt = { now, now },
		load = load,
		refill = refill,
		barrel1 = barrel1,
		barrel2 = barrel2,
		clip = clip,
		salvo = salvo,
		timers = { load, refill, barrel1, barrel2, clip, salvo },
		topOff = false,
		swapCycle = false,
		triggerHeld = false,
		triggerAt = now,
		triggerConsumed = false,
		moving = false,
		charged = charged,
		cooling = cooling,
		adaptiveFactor = adaptive,
		ctx = Common.newContext(),
		shot = {
			time = now,
			slot = 0,
			shellId = gun.shells[1].id,
			shell = gun.shells[1],
			rounds = 0,
			barrel = 0,
			volley = false,
			charged = false,
			dispersionMul = 1,
			damageMul = 1,
			ammoLeft = 0,
			magazineLeft = 0,
		},
		pending = false,
		shotsFired = 0,
		roundsFired = 0,
	}
	state.ctx.stationaryForS = math.huge -- stationary until setMoving says otherwise
	GunState.setReloadMul(state, if o.reloadMul ~= nil then o.reloadMul else 1, now)

	local startLoaded = if o.startLoaded ~= nil then o.startLoaded else setting("START_LOADED") == true
	if startLoaded then
		if kind == "Single" then
			local slot = pickSlot(state, selected)
			if slot ~= 0 then
				state.slots[slot].rack -= 1
				state.loadedSlot = slot
				state.selected = slot
			end
		elseif kind == "Magazine" or kind == "Autoreloader" then
			local slot = pickSlot(state, selected)
			if slot ~= 0 then
				local n = math.min(size, state.slots[slot].rack)
				state.slots[slot].rack -= n
				state.mag = n
				state.magSlot = slot
				state.selected = slot
			end
			if kind == "Autoreloader" then
				startRefillAuto(state)
			end
		else
			for barrel = 1, 2 do
				local slot = pickSlot(state, state.selected)
				if slot ~= 0 then
					state.slots[slot].rack -= 1
					state.barrelSlot[barrel] = slot
					state.selected = slot
				end
			end
		end
	else
		if kind == "Single" then
			startLoad(state, 1)
		elseif kind == "Magazine" then
			startFullReload(state, 1)
		elseif kind == "Autoreloader" then
			startRefillAuto(state)
		else
			startBarrel(state, 1, 1)
			startBarrel(state, 2, 1)
		end
	end
	return state
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

local function fireCheck(state: GunState): (boolean, string?)
	if not state.alive then
		return false, "DEAD"
	elseif not state.enabled then
		return false, "GUN_DESTROYED"
	elseif state.overturned then
		return false, "OVERTURNED"
	end
	local kind = state.kind
	if kind == "Single" then
		if state.loadedSlot ~= 0 then
			return true, nil
		end
		return false, if state.load.active then "RELOADING" else "EMPTY"
	elseif kind == "DualGun" then
		if state.barrelSlot[1] ~= 0 or state.barrelSlot[2] ~= 0 then
			if state.salvo.active then
				return false, "SALVO_DELAY"
			end
			return true, nil
		end
		return false, if state.barrel1.active or state.barrel2.active then "RELOADING" else "EMPTY"
	end
	if state.mag > 0 then
		if state.clip.active then
			return false, "INTRA_CLIP"
		end
		return true, nil
	end
	return false, if state.refill.active then "RELOADING" else "EMPTY"
end

--- Whether a single shot could fire at `now` (advances the state to `now`). Returns (ok, reason).
function GunState.canFire(state: GunState, now: number): (boolean, string?)
	advance(state, now)
	return fireCheck(state)
end

--- Rounds of slot `slot` left (rack + gun).
function GunState.ammoOf(state: GunState, slot: number): number
	local s = state.slots[slot]
	return if s ~= nil then s.total else 0
end

--- Every round left (rack + gun): DamageModel's `ammoStored` (detonation needs >= 1).
function GunState.totalAmmo(state: GunState): number
	return totalAmmo(state)
end

--- Rounds stored outside the gun (rack + rounds a running reload is loading): DamageModel's ammo-rack detonation
--- count (00-DECISIONS §2: detonation if >= 1 shell stored).
function GunState.storedAmmo(state: GunState): number
	return math.max(0, totalAmmo(state) - roundsLoaded(state))
end

--- Writes storedAmmo() into the vehicle's combat state (DamageModel.setAmmoStored). Returns the count written.
function GunState.syncAmmoStored(state: GunState, combat: VehicleCombatState): number
	local stored = GunState.storedAmmo(state)
	DamageModel.setAmmoStored(combat, stored)
	return stored
end

--- Rounds ready to fire (Single 0/1, magazine rounds, loaded barrels).
function GunState.roundsLoaded(state: GunState): number
	return roundsLoaded(state)
end

--- Effective multiplier on reload timers right now (runtime × ActiveCooling).
function GunState.currentReloadMul(state: GunState): number
	return effectiveMul(state)
end

--------------------------------------------------------------------------------
-- Firing
--------------------------------------------------------------------------------

local function fireOne(state: GunState, charged: boolean, dispersionMul: number, damageMul: number): ShotInfo
	local time = state.time
	local kind = state.kind
	if kind == "Single" then
		local slot = state.loadedSlot
		state.loadedSlot = 0
		local shot = writeShot(state, slot, 1, 1, false, charged, dispersionMul, damageMul, time)
		startLoad(state, 1)
		shot.magazineLeft = roundsLoaded(state)
		return shot
	elseif kind == "DualGun" then
		local barrel = if state.barrelSlot[1] ~= 0 then 1 else 2
		local slot = state.barrelSlot[barrel]
		state.barrelSlot[barrel] = 0
		local shot = writeShot(state, slot, 1, barrel, false, false, 1, 1, time)
		startBarrel(state, barrel, 1)
		if state.salvoS > 0 then
			start(state.salvo, state.salvoS, 0, 0)
		end
		return shot
	end
	-- Magazine / Autoreloader
	local slot = state.magSlot
	state.mag -= 1
	if kind == "Magazine" and state.topOff then
		release(state, state.refill) -- firing cancels a top-off; the reserved rounds go back (roster §2.7)
		state.topOff = false
	end
	local shot = writeShot(state, slot, 1, 1, false, false, 1, 1, time)
	if state.mag > 0 then
		if state.intraClipS > 0 then
			start(state.clip, state.intraClipS, 0, 0)
		end
	elseif kind == "Magazine" then
		startFullReload(state, 1)
	end
	if kind == "Autoreloader" then
		startRefillAuto(state)
	end
	return shot
end

--- Fires one round now if the gun can (single barrel for DualGun, uncharged for ChargedShot; a running charge is
--- dropped). Returns (shot, nil) or (nil, reason). A volley that auto-fired earlier and was not collected yet is
--- returned instead.
function GunState.fire(state: GunState, now: number): (ShotInfo?, string?)
	advance(state, now)
	local pendingShot = takePending(state)
	if pendingShot ~= nil then
		return pendingShot, nil
	end
	local ok, reason = fireCheck(state)
	if not ok then
		return nil, reason
	end
	local charged = state.charged
	if charged ~= nil then
		ChargedShot.cancel(charged)
	end
	return fireOne(state, false, 1, 1), nil
end

local function onPress(state: GunState): ShotInfo?
	local kind = state.kind
	if kind == "DualGun" then
		return nil -- tap vs hold is decided on release / by the volley charge
	end
	local charged = state.charged
	if charged ~= nil then
		if state.loadedSlot ~= 0 and armed(state) then
			ChargedShot.begin(charged, state.time, state.ctx)
		end
		return nil
	end
	state.triggerConsumed = true
	local ok = fireCheck(state)
	if ok then
		return fireOne(state, false, 1, 1)
	end
	return nil
end

local function onRelease(state: GunState): ShotInfo?
	if state.triggerConsumed then
		return nil
	end
	local kind = state.kind
	local charged = state.charged
	if charged ~= nil then
		local full = ChargedShot.release(charged, state.time)
		if fireCheck(state) then
			local dispersionMul, damageMul = ChargedShot.shotMultipliers(charged, full)
			return fireOne(state, full, dispersionMul, damageMul)
		end
		return nil
	end
	if kind == "DualGun" then
		local held = state.time - state.triggerAt
		if held >= setting("DUAL_GUN_TAP_S") - EPS and chargingVolley(state) then
			return nil -- releasing a charging volley cancels it: no shot, nothing consumed
		end
		if fireCheck(state) then
			return fireOne(state, false, 1, 1)
		end
	end
	return nil
end

--- The fire trigger at `now` (call every tick with InputCommand.fire). Returns the shot this call produced, if any:
--- press fires Single/Magazine/Autoreloader guns; DualGun and ChargedShot act on hold/release (see header).
function GunState.setTrigger(state: GunState, held: boolean, now: number): ShotInfo?
	advance(state, now)
	local result = takePending(state)
	local charged = state.charged
	if charged ~= nil then
		ChargedShot.update(charged, state.time, state.ctx)
	end
	if held and not state.triggerHeld then
		state.triggerHeld = true
		state.triggerAt = state.time
		state.triggerConsumed = false
		if result == nil then
			result = onPress(state)
		end
		-- a volley whose charge is already complete cannot exist yet (it needs chargeTimeS from now)
	elseif not held and state.triggerHeld then
		if result == nil then
			result = onRelease(state)
		end
		state.triggerHeld = false
		state.triggerConsumed = false
		if charged ~= nil then
			ChargedShot.cancel(charged)
		end
	end
	return result
end

--- Advances the gun to `now`. Returns an automatically fired volley (DualGun trigger held through its charge).
function GunState.update(state: GunState, now: number): ShotInfo?
	advance(state, now)
	local charged = state.charged
	if charged ~= nil then
		ChargedShot.update(charged, state.time, state.ctx)
	end
	return takePending(state)
end

--------------------------------------------------------------------------------
-- Shell selection, manual reload, mechanics
--------------------------------------------------------------------------------

local function dropCharges(state: GunState)
	local charged = state.charged
	if charged ~= nil then
		ChargedShot.cancel(charged)
	end
	if state.triggerHeld then
		state.triggerConsumed = true -- a charging volley / charged shot is cancelled without firing
	end
end

--- Selects ammo slot `slot` (hotkey) at `now` (00-DECISIONS §4 swap rule, header). Returns (ok, reason).
function GunState.selectShell(state: GunState, slot: number, now: number): (boolean, string?)
	advance(state, now)
	if not state.alive then
		return false, "DEAD"
	end
	local ammo = state.slots[slot]
	if ammo == nil then
		return false, "UNKNOWN_SHELL"
	end
	local kind = state.kind
	-- Is a round of another shell loaded (swap = full reload) or is the gun already on this shell?
	local loadedOther, loadedSame = false, false
	if kind == "Single" then
		loadedOther = state.loadedSlot ~= 0 and state.loadedSlot ~= slot
		loadedSame = state.loadedSlot == slot
	elseif kind == "DualGun" then
		for barrel = 1, 2 do
			local b = state.barrelSlot[barrel]
			if b ~= 0 and b ~= slot then
				loadedOther = true
			elseif b == slot then
				loadedSame = true
			end
		end
	else
		loadedOther = state.mag > 0 and state.magSlot ~= slot
		loadedSame = state.mag > 0 and state.magSlot == slot
	end
	if not loadedOther and ammo.rack <= 0 and not loadedSame then
		-- nothing of this shell can be loaded (its last rounds may already be in a running reload)
		local reserved = false
		for _, timer in state.timers do
			if timer.active and timer.slot == slot then
				reserved = true
			end
		end
		if not reserved then
			return false, "NO_AMMO"
		end
	end
	if loadedOther and ammo.rack <= 0 then
		return false, "NO_AMMO"
	end
	if slot == state.selected and not loadedOther then
		return true, nil
	end
	dropCharges(state)
	state.selected = slot
	if kind == "Single" then
		if loadedOther then
			state.slots[state.loadedSlot].rack += 1
			state.loadedSlot = 0
			startLoad(state, state.swapFactor)
		elseif state.load.active and state.load.slot ~= slot then
			-- mid-reload: the running reload loads the new shell instead (progress kept)
			state.slots[state.load.slot].rack += 1
			ammo.rack -= 1
			state.load.slot = slot
		elseif not state.load.active and state.loadedSlot == 0 then
			startLoad(state, 1)
		end
	elseif kind == "Magazine" then
		if loadedOther then
			state.slots[state.magSlot].rack += state.mag
			state.mag = 0
			release(state, state.clip)
			release(state, state.refill)
			state.topOff = false
			startFullReload(state, state.swapFactor)
		elseif state.refill.active and not state.topOff and state.refill.slot ~= slot then
			local refill = state.refill
			state.slots[refill.slot].rack += refill.rounds
			local n = math.min(state.size, ammo.rack)
			ammo.rack -= n
			refill.slot = slot
			refill.rounds = n
		elseif not state.refill.active and state.mag == 0 then
			startFullReload(state, 1)
		end
	elseif kind == "Autoreloader" then
		if loadedOther then
			state.slots[state.magSlot].rack += state.mag
			state.mag = 0
			release(state, state.clip)
			release(state, state.refill)
			state.swapCycle = true
			startRefillAuto(state)
		elseif state.refill.active and state.mag == 0 and state.refill.slot ~= slot then
			local refill = state.refill
			state.slots[refill.slot].rack += refill.rounds
			ammo.rack -= 1
			refill.slot = slot
			refill.rounds = 1
		elseif not state.refill.active then
			startRefillAuto(state)
		end
	else
		if loadedOther then
			for barrel = 1, 2 do
				local b = state.barrelSlot[barrel]
				if b ~= 0 then
					state.slots[b].rack += 1
					state.barrelSlot[barrel] = 0
				end
			end
			release(state, state.barrel1)
			release(state, state.barrel2)
			release(state, state.salvo)
			startBarrel(state, 1, state.swapFactor)
			startBarrel(state, 2, state.swapFactor)
		else
			for barrel = 1, 2 do
				local timer = if barrel == 1 then state.barrel1 else state.barrel2
				if timer.active and timer.slot ~= slot and ammo.rack > 0 then
					state.slots[timer.slot].rack += 1
					ammo.rack -= 1
					timer.slot = slot
				elseif not timer.active and state.barrelSlot[barrel] == 0 then
					startBarrel(state, barrel, 1)
				end
			end
		end
	end
	return true, nil
end

--- Alias of selectShell (brief / HUD naming).
GunState.switchShell = GunState.selectShell

--- Selects the slot holding `shellId`.
function GunState.selectShellById(state: GunState, shellId: string, now: number): (boolean, string?)
	for i, slot in state.slots do
		if slot.id == shellId then
			return GunState.selectShell(state, i, now)
		end
	end
	advance(state, now)
	return false, "UNKNOWN_SHELL"
end

--- Manual reload: a partial Magazine is unloaded and fully reloaded (costs the full reloadS); with AdaptiveMagazine
--- it is topped off instead in reloadS × (f + (1 − f) × missing ÷ size) (roster §2.7). Other kinds: NOT_SUPPORTED.
function GunState.reload(state: GunState, now: number): (boolean, string?)
	advance(state, now)
	if not state.alive then
		return false, "DEAD"
	end
	if state.kind ~= "Magazine" then
		return false, "NOT_SUPPORTED"
	end
	if state.refill.active then
		return false, "RELOADING"
	end
	if state.mag >= state.size then
		return false, "FULL"
	end
	if state.mag == 0 then
		return false, "EMPTY"
	end
	local f = state.adaptiveFactor
	if f > 0 then
		local ammo = state.slots[state.magSlot]
		local n = math.min(state.size - state.mag, ammo.rack)
		if n <= 0 then
			return false, "NO_AMMO"
		end
		ammo.rack -= n
		state.topOff = true
		start(state.refill, state.reloadS * (f + (1 - f) * n / state.size), state.magSlot, n)
		return true, nil
	end
	if pickSlot(state, state.selected) == 0 then
		return false, "NO_AMMO"
	end
	dropCharges(state)
	state.slots[state.magSlot].rack += state.mag
	state.mag = 0
	release(state, state.clip)
	startFullReload(state, 1)
	return true, nil
end

--- The vehicle's mechanic key when GunState owns the mechanic: starts ActiveCooling or an AdaptiveMagazine top-off.
function GunState.mechanicKey(state: GunState, now: number): (boolean, string?)
	if state.cooling ~= nil then
		return GunState.activateCooling(state, now)
	elseif state.adaptiveFactor > 0 then
		return GunState.reload(state, now)
	end
	advance(state, now)
	return false, "NO_MECHANIC"
end

--- Starts ActiveCooling at `now` (allowed mid-reload: the rest of the reload runs at the cooled rate).
function GunState.activateCooling(state: GunState, now: number): (boolean, string?)
	advance(state, now)
	local cooling = state.cooling
	if cooling == nil then
		return false, "NO_MECHANIC"
	end
	return ActiveCooling.activate(cooling, state.time, state.ctx)
end

--- The GunState mechanic modifiers StatsCalculator's runtime should apply now (ActiveCooling minus reloadTime,
--- which GunState applies itself), else nil.
function GunState.mechanicModifiers(state: GunState): { StatModifier }?
	local cooling = state.cooling
	if cooling ~= nil then
		return ActiveCooling.runtimeModifiers(cooling)
	end
	return nil
end

--- "MechanicActive" for GunState-owned mechanics (cooling window, charging shot).
function GunState.mechanicActive(state: GunState): boolean
	local cooling = state.cooling
	return cooling ~= nil and cooling.phase == "On"
end

--------------------------------------------------------------------------------
-- Runtime inputs
--------------------------------------------------------------------------------

--- Sets the runtime reload multiplier (DamageModel effects.reloadTimeMul × runtime modifiers) from `now` on;
--- reload progress so far is kept. Non-finite or non-positive values reset it to 1; clamped to the DEFAULTS range.
function GunState.setReloadMul(state: GunState, mul: number, now: number)
	advance(state, now)
	local m = if finite(mul) and mul > 0 then mul else 1
	state.reloadMul = math.clamp(m, setting("MIN_RELOAD_MUL"), setting("MAX_RELOAD_MUL"))
end

--- Gun module working (EffectMultipliers.canFire). Disabling blocks firing and cancels charges; reloads continue.
function GunState.setEnabled(state: GunState, enabled: boolean, now: number)
	advance(state, now)
	if state.enabled and not enabled then
		dropCharges(state)
	end
	state.enabled = enabled
end

--- Vehicle overturned (VehicleSimState.overturned): blocks firing and cancels charges until righted; reloads keep
--- running.
function GunState.setOverturned(state: GunState, overturned: boolean, now: number)
	advance(state, now)
	if overturned and not state.overturned then
		dropCharges(state)
	end
	state.overturned = overturned
end

--- Applies the StatsCalculator runtime (RuntimeStats.reloadMul / canFire) from `now` on.
function GunState.applyRuntime(state: GunState, runtime: { reloadMul: number, canFire: boolean }, now: number)
	GunState.setReloadMul(state, runtime.reloadMul, now)
	GunState.setEnabled(state, runtime.canFire, now)
end

--- Hull moving (ChargedShot reset-on-move rule only).
function GunState.setMoving(state: GunState, moving: boolean, now: number)
	advance(state, now)
	state.moving = moving
	state.ctx.stationaryForS = if moving then 0 else math.huge
	local charged = state.charged
	if charged ~= nil then
		ChargedShot.update(charged, state.time, state.ctx)
	end
end

--- The vehicle was destroyed at `now`: everything up to `now` (inclusive) completes, then the gun freezes.
function GunState.kill(state: GunState, now: number)
	advance(state, now)
	dropCharges(state)
	state.alive = false
	state.ctx.alive = false
	state.triggerConsumed = true
	local cooling = state.cooling
	if cooling ~= nil then
		ActiveCooling.update(cooling, state.time, state.ctx)
	end
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------

--- A snapshot record sized for this gun (allocate once per vehicle / HUD).
function GunState.newSnapshot(state: GunState): GunSnapshot
	return {
		kind = state.kind,
		phase = "Ready",
		alive = true,
		enabled = true,
		overturned = false,
		canFire = false,
		selectedSlot = 0,
		loadedSlot = 0,
		reloadProgress = 1,
		reloadRemainingS = 0,
		reloadDurationS = 0,
		nextShotS = 0,
		intraClipRemainingS = 0,
		roundsLoaded = 0,
		magazineSize = state.size,
		toppingOff = false,
		refillSlotIndex = 0,
		chargeProgress = 0,
		reloadMul = 1,
		ammo = table.create(#state.slots, 0),
		totalAmmo = 0,
		barrelProgress = if state.kind == "DualGun" then { 0, 0 } else {},
	}
end

local function timerProgress(timer: Timer): number
	if not timer.active or not (timer.total > 0) then
		return 1
	end
	return math.clamp(1 - timer.work / timer.total, 0, 1)
end

--- Writes the HUD/replication view at `now` into `out` (advances the state to `now`).
function GunState.snapshot(state: GunState, now: number, out: GunSnapshot?): GunSnapshot
	advance(state, now)
	local s = out or GunState.newSnapshot(state)
	local kind: ReloadKind = state.kind
	local ok = fireCheck(state)
	s.kind = kind
	s.alive = state.alive
	s.enabled = state.enabled
	s.overturned = state.overturned
	s.canFire = ok
	s.selectedSlot = state.selected
	s.roundsLoaded = roundsLoaded(state)
	s.magazineSize = state.size
	s.toppingOff = state.topOff
	s.reloadMul = effectiveMul(state)
	s.refillSlotIndex = 0
	s.intraClipRemainingS = 0
	-- main timer
	local main: Timer? = nil
	if kind == "Single" then
		main = state.load
		s.loadedSlot = state.loadedSlot
	elseif kind == "DualGun" then
		local b1, b2 = state.barrel1, state.barrel2
		if b1.active and b2.active then
			main = if b1.work <= b2.work then b1 else b2
		elseif b1.active then
			main = b1
		elseif b2.active then
			main = b2
		end
		s.loadedSlot = if state.barrelSlot[1] ~= 0 then state.barrelSlot[1] else state.barrelSlot[2]
		s.barrelProgress[1] = if state.barrelSlot[1] ~= 0 then 1 else (if b1.active then timerProgress(b1) else 0)
		s.barrelProgress[2] = if state.barrelSlot[2] ~= 0 then 1 else (if b2.active then timerProgress(b2) else 0)
		if state.salvo.active then
			s.intraClipRemainingS = realTime(state, state.salvo.work)
		end
	else
		main = state.refill
		s.loadedSlot = if state.mag > 0 then state.magSlot else 0
		if state.clip.active then
			s.intraClipRemainingS = realTime(state, state.clip.work)
		end
		if kind == "Autoreloader" and state.refill.active then
			s.refillSlotIndex = state.mag + 1
		end
	end
	local mul = effectiveMul(state)
	if main ~= nil and main.active then
		s.reloadProgress = timerProgress(main)
		s.reloadRemainingS = realTime(state, main.work)
		s.reloadDurationS = main.total * mul
	else
		s.reloadProgress = if s.roundsLoaded > 0 then 1 else 0
		s.reloadRemainingS = 0
		s.reloadDurationS = 0
	end
	-- next shot (math.huge = not without help: blocked, or empty with nothing loading)
	s.nextShotS = math.huge
	if armed(state) then
		if ok then
			s.nextShotS = 0
		elseif s.roundsLoaded > 0 then
			s.nextShotS = s.intraClipRemainingS
		elseif main ~= nil and main.active then
			s.nextShotS = s.reloadRemainingS
		end
	end
	-- charge
	s.chargeProgress = 0
	local charged = state.charged
	if charged ~= nil then
		s.chargeProgress = ChargedShot.progress(charged, state.time)
	elseif chargingVolley(state) then
		local startT = volleyStart(state)
		s.chargeProgress = math.clamp((state.time - startT) / state.volleyChargeS, 0, 1)
	end
	-- ammo
	local total = 0
	for i, slot in state.slots do
		s.ammo[i] = slot.total
		total += slot.total
	end
	s.totalAmmo = total
	-- phase
	if not state.alive then
		s.phase = "Dead"
	elseif not state.enabled or state.overturned then
		s.phase = "Disabled"
	elseif s.chargeProgress > 0 then
		s.phase = "Charging"
	elseif ok then
		s.phase = "Ready"
	elseif s.roundsLoaded > 0 then
		s.phase = "IntraClip"
	elseif main ~= nil and main.active then
		s.phase = "Reloading"
	else
		s.phase = "Empty"
	end
	return s
end

--- Mechanic snapshot of the GunState-owned keyed mechanic (ActiveCooling) or the ChargedShot charge; nil when the
--- gun has neither.
function GunState.mechanicSnapshot(state: GunState, now: number, out: Common.Snapshot?): Common.Snapshot?
	advance(state, now)
	local cooling = state.cooling
	if cooling ~= nil then
		return ActiveCooling.snapshot(cooling, state.time, out)
	end
	local charged = state.charged
	if charged ~= nil then
		return ChargedShot.snapshot(charged, state.time, out)
	end
	return nil
end

return GunState
