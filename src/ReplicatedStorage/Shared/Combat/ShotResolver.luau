--!strict
--[[
	Combat/ShotResolver — walks one shell through one target's armor crossings and reports what it did: spaced
	armor, sequential plates, ricochet continuation (reflected ray, may hit another part of the same vehicle),
	post-penetration internal path (Module / Crew volumes), the HE/HESH model (non-pen blast at the impact point,
	screen bursts, spall sphere, splash on nearby vehicles) and the damage roll.

	Purpose:          The single authoritative shot resolution used by the server ProjectileSystem (and by tests /
	                  bots / replays with the same seed). Team-agnostic: friendly-fire policy (allies consume shells
	                  for 0 damage, splash/rams never hurt allies) is applied by the caller.
	Dependencies:     Config (Combat), Core/Units, Core/RNG (type), Combat/ArmorGeometry, Combat/Penetration,
	                  Combat/Ballistics, Combat/HE, Types/Vehicle, Types/Combat, Types/Battle.
	State:            Module scratch buffers (two crossing buffers, one near-volume buffer, one plate result), reused
	                  per call; the resolver never yields and is not re-entrant.
	Validation:       Bad rays (zero / non-finite) are a Miss; non-finite rolls are treated as 0; a target whose
	                  state is destroyed yields a no-op outcome (geometry only) — never damage on a wreck.
	Error handling:   No throws on numeric input.
	Performance notes: One ArmorGeometry.raycast per call (plus one per ricochet that stays on the vehicle and one
	                  sphere query per HE burst / splash candidate). The outcome table is reusable via `out`;
	                  hit lists (modules, crew, splash) allocate small records only when something is hit.

	Order (00-DECISIONS §1 "Order"): roll pen once at the first impact (after falloff) and roll damage → for each
	plate in ray order: ricochet test (raw angle) → normalization → Spaced/Layered subtract T_eff (HE 3 T) and
	continue, HEAT loses 50 %/m across each air gap → main plate (the body): pen >= T_eff penetrates. <= MAX_PLATES
	plates. Ricochet: reflect about the normal, pen × 0.75 (HEAT × 1), at most RICOCHET_MAX (the next deletes the
	shell), no HP damage (an external module struck is still damaged); the reflected ray is re-cast against the same
	vehicle first, and only if it misses is a RicochetRay returned for the caller to keep flying.
	Internal path: from the body entry along the shell's ray, max(0.5 m, 10 cal) (HEAT also stops where the jet
	reaches 0), ending where the ray leaves the union of Armor volumes; each Module/Crew volume entered rolls its
	hit chance. HE/HESH: penetration = rolled α + spall sphere (R) rolling modules/crew at full module damage;
	non-pen on main armor = HE.nonPenDamage + spall rolls × 0.5; burst on a screen = splash on its own body
	(distance along the ray to the next main plate) + external module damage. Every HE burst splashes the caller's
	`nearby` list. A shell that only passes through spaced volumes and leaves the vehicle is consumed (absorbed).
	RNG draw order (deterministic): pen roll, damage roll, then hit-chance draws in ray / distance order.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local RNGModule = require("@game/ReplicatedStorage/Shared/Core/RNG")
local ArmorGeometry = require("./ArmorGeometry")
local Penetration = require("./Penetration")
local Ballistics = require("./Ballistics")
local HE = require("./HE")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type RNG = RNGModule.RNG
type ArmorModel = VehicleTypes.ArmorModel
type ArmorVolumeKind = VehicleTypes.ArmorVolumeKind
type CombatShell = CombatTypes.CombatShell
type Crossing = CombatTypes.Crossing
type CrossingBuffer = CombatTypes.CrossingBuffer
type PlateKind = CombatTypes.PlateKind
type ShotTarget = CombatTypes.ShotTarget
type ShotInput = CombatTypes.ShotInput
type ShotOutcome = CombatTypes.ShotOutcome
type SplashCandidate = CombatTypes.SplashCandidate
type SplashHit = CombatTypes.SplashHit
type ModuleHitRecord = CombatTypes.ModuleHitRecord
type VehicleCombatState = CombatTypes.VehicleCombatState
type VehiclePose = CombatTypes.VehiclePose
type InternalModuleKind = ContentTypes.InternalModuleKind

local ShotResolver = {}

local STUDS = Units.STUDS_PER_METER

local bufA = ArmorGeometry.newBuffer()
local bufB = ArmorGeometry.newBuffer()
local nearBuf = ArmorGeometry.newNearBuffer()
local plate = Penetration.newPlateResult()

local SPACED_ONLY: { [ArmorVolumeKind]: boolean } = { Spaced = true }

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteVector(v: Vector3): boolean
	return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

local function wholeHp(x: number): number
	if not (x > 0) or not isFinite(x) then
		return 0
	end
	return math.floor(x + 0.5)
end

--- A fresh, empty outcome (reuse it through the `out` argument of resolve()).
function ShotResolver.newOutcome(): ShotOutcome
	return {
		result = "Miss",
		hit = false,
		noop = false,
		absorbed = false,
		deleted = false,
		damage = 0,
		potentialDamage = 0,
		penetrationMm = 0,
		penetrationRemainingMm = 0,
		effectiveArmorMm = 0,
		decidingZone = nil,
		plates = 0,
		ricochets = 0,
		impact = nil,
		modulesHit = {},
		crewHit = {},
		engineHit = false,
		ricochetRay = nil,
		burstPoint = nil,
		splash = {},
		fireStarted = false,
		ammoRackDetonation = false,
		damageApplied = 0,
		killed = false,
	}
end

local function reset(o: ShotOutcome)
	o.result = "Miss"
	o.hit = false
	o.noop = false
	o.absorbed = false
	o.deleted = false
	o.damage = 0
	o.potentialDamage = 0
	o.penetrationMm = 0
	o.penetrationRemainingMm = 0
	o.effectiveArmorMm = 0
	o.decidingZone = nil
	o.plates = 0
	o.ricochets = 0
	o.impact = nil
	table.clear(o.modulesHit)
	table.clear(o.crewHit)
	o.engineHit = false
	o.ricochetRay = nil
	o.burstPoint = nil
	table.clear(o.splash)
	o.fireStarted = false
	o.ammoRackDetonation = false
	o.damageApplied = 0
	o.killed = false
end

local function firstHitIndex(buf: CrossingBuffer, from: number): number
	for i = from, buf.count do
		local rec = buf.items[i]
		if
			rec.entering and (rec.volumeKind == "Armor" or rec.volumeKind == "Layered" or rec.volumeKind == "Spaced")
		then
			return i
		end
	end
	return 0
end

-- Context shared by the helpers of one resolve() call.
type Ctx = {
	o: ShotOutcome,
	shell: CombatShell,
	rng: RNG,
	state: VehicleCombatState?,
	alpha: number, -- rolled alpha
	moduleBase: number, -- module damage scaled by the damage roll
	crewChanceMul: number,
	kSpall: number,
}

local function capModuleDamage(ctx: Ctx, kind: string, damage: number): number
	local state = ctx.state
	if state ~= nil then
		local m = (state.modules :: any)[kind]
		if m ~= nil then
			local cap = Config.Combat.MODULE_DAMAGE_CAP_MUL * m.maxHp
			if damage > cap then
				return wholeHp(cap)
			end
		end
	end
	return damage
end

local function addModuleHit(ctx: Ctx, kind: any, damage: number, external: boolean, volumeId: number)
	local dmg = capModuleDamage(ctx, kind, wholeHp(damage))
	if dmg <= 0 then
		return
	end
	table.insert(ctx.o.modulesHit, { kind = kind, damage = dmg, external = external, volumeId = volumeId })
	if kind == "Engine" then
		ctx.o.engineHit = true
	end
end

-- Rolls hit chances for one internal Module/Crew volume (internal path or spall sphere).
local function rollInternal(
	ctx: Ctx,
	kind: ArmorVolumeKind,
	module: any,
	crewSlot: number?,
	volumeId: number,
	mul: number
)
	local C = Config.Combat
	if kind == "Module" and module ~= nil then
		local chance = (C.MODULE_HIT_CHANCE :: any)[module]
		if type(chance) ~= "number" then
			chance = 0
		end
		if ctx.rng:chance(chance) then
			addModuleHit(ctx, module, ctx.moduleBase * mul, false, volumeId)
		end
	elseif kind == "Crew" and crewSlot ~= nil then
		if ctx.rng:chance(C.CREW_HIT_CHANCE * ctx.crewChanceMul) then
			local dmg = wholeHp(ctx.moduleBase * mul)
			if dmg > 0 then
				table.insert(ctx.o.crewHit, { slot = crewSlot, damage = dmg, volumeId = volumeId })
			end
		end
	end
end

-- Spall sphere of an HE burst at `point`: every Module/Crew volume within R rolls its hit chance.
local function spallSphere(ctx: Ctx, armor: ArmorModel, pose: VehiclePose, point: Vector3, mul: number)
	local radius = HE.radiusM(ctx.shell) * STUDS
	if not (radius > 0) then
		return
	end
	ArmorGeometry.volumesNear(armor, pose, point, radius, nil, nearBuf)
	for i = 1, nearBuf.count do
		local v = nearBuf.items[i].volume
		rollInternal(ctx, v.kind, v.module, v.crewSlot, v.id, mul)
	end
end

local function splashAt(
	shell: CombatShell,
	point: Vector3,
	alpha: number,
	nearby: { SplashCandidate }?,
	out: { SplashHit }
)
	if nearby == nil then
		return
	end
	local C = Config.Combat
	local radiusM = HE.radiusM(shell)
	if not (radiusM > 0) then
		return
	end
	local radius = radiusM * STUDS
	local moduleBase = if shell.damage > 0 then shell.moduleDamage * (alpha / shell.damage) else shell.moduleDamage
	for index, candidate in nearby do
		local state = candidate.state
		if state ~= nil and state.destroyed then
			continue
		end
		local found, dStuds, tMin = ArmorGeometry.nearestArmor(candidate.armor, candidate.pose, point, radius)
		if not found then
			continue
		end
		local dM = dStuds / STUDS
		local k = candidate.spallFactor or (if state ~= nil then state.spallFactor else nil) or C.SPALL_FACTOR_BASE
		local damage = HE.splashDamage(alpha, dM, radiusM, tMin, k)
		local stunS = HE.stunDuration(shell, dM, radiusM, if state ~= nil then state.stunDurationMul else nil)
		local modules: { ModuleHitRecord } = {}
		ArmorGeometry.volumesNear(candidate.armor, candidate.pose, point, radius, SPACED_ONLY, nearBuf)
		for i = 1, nearBuf.count do
			local near = nearBuf.items[i]
			local kind: InternalModuleKind? = near.volume.module
			if kind ~= nil then
				local dmg = HE.splashModuleDamage(moduleBase, near.distance / STUDS, radiusM)
				if state ~= nil then
					local m = (state.modules :: any)[kind]
					if m ~= nil then
						dmg = math.min(dmg, wholeHp(C.MODULE_DAMAGE_CAP_MUL * m.maxHp))
					end
				end
				if dmg > 0 then
					table.insert(modules, { kind = kind, damage = dmg, external = true, volumeId = near.volume.id })
				end
			end
		end
		if damage > 0 or stunS > 0 or #modules > 0 then
			table.insert(out, {
				index = index,
				id = candidate.id,
				damage = damage,
				distanceM = dM,
				thicknessMm = tMin,
				stunS = stunS,
				modulesHit = modules,
			})
		end
	end
end

local function finishHE(ctx: Ctx, input: ShotInput, point: Vector3)
	ctx.o.burstPoint = point
	splashAt(ctx.shell, point, ctx.alpha, input.nearby, ctx.o.splash)
end

-- Distance (studs) from crossing index `i` to the next main-plate entry (Armor or Layered) outside the body.
local function nextMainPlate(buf: CrossingBuffer, i: number): Crossing?
	for j = i + 1, buf.count do
		local rec = buf.items[j]
		if rec.entering and (rec.volumeKind == "Armor" or rec.volumeKind == "Layered") then
			return rec
		end
	end
	return nil
end

-- Internal path after the body was penetrated at buf.items[i].
local function internalPath(ctx: Ctx, buf: CrossingBuffer, i: number)
	local C = Config.Combat
	local entry = buf.items[i]
	local pathM = math.max(C.INTERNAL_PATH_MIN_M, C.INTERNAL_PATH_CALIBERS * ctx.shell.caliberMm / 1000)
	if ctx.shell.kind == "HEAT" and C.HEAT_GAP_LOSS_PER_M > 0 then
		pathM = math.min(pathM, 1 / C.HEAT_GAP_LOSS_PER_M)
	end
	local endDistance = entry.distance + pathM * STUDS
	local inside = 1
	for j = i + 1, buf.count do
		local rec = buf.items[j]
		if rec.distance > endDistance then
			break
		end
		local kind = rec.volumeKind
		if kind == "Armor" then
			if rec.entering then
				inside += 1
			else
				inside -= 1
				if inside <= 0 then
					break
				end
			end
		elseif (kind == "Module" or kind == "Crew") and rec.entering then
			rollInternal(ctx, kind, rec.module, rec.crewSlot, rec.volumeId, 1)
		end
	end
end

--- Resolves one shell against one target. `input.origin`/`direction` are world studs; the first plate struck must
--- lie within `input.maxDistance` (the caller's swept segment) or the result is a Miss. Reuses `out` when given.
function ShotResolver.resolve(target: ShotTarget, input: ShotInput, rng: RNG, out: ShotOutcome?): ShotOutcome
	local C = Config.Combat
	local o = out or ShotResolver.newOutcome()
	reset(o)
	local shell = input.shell
	local armor, pose = target.armor, target.pose
	local direction = input.direction
	local origin = input.origin
	local mag = direction.Magnitude
	if not (mag > 0 and isFinite(mag)) or not finiteVector(origin) then
		return o
	end
	local dir = direction / mag

	local buf = bufA
	ArmorGeometry.raycast(armor, pose, origin, dir, nil, buf)
	local i = firstHitIndex(buf, 1)
	local maxFirst = input.maxDistance or math.huge
	if i == 0 or not (buf.items[i].distance <= maxFirst) then
		return o
	end
	local first = buf.items[i]
	o.hit = true
	o.impact = {
		point = first.point,
		normal = first.normal,
		distance = first.distance,
		zone = first.zone,
		thicknessMm = first.thicknessMm,
		effectiveMm = 0,
		angleDeg = ArmorGeometry.impactAngleDeg(dir, first.normal),
		volumeId = first.volumeId,
		volumeKind = first.volumeKind,
		group = first.group,
	}
	local state = target.state
	if state ~= nil and state.destroyed then
		o.noop = true
		o.result = "NonPenetration"
		return o
	end

	-- Rolls (once per shell; continuations carry them).
	local spread = input.spread or C.ROLL_SPREAD
	local pen = input.penetrationMm
	if pen == nil then
		local firedFrom = input.firedFrom or origin
		pen =
			Penetration.roll(Ballistics.penetrationAt(shell, Ballistics.distanceM(firedFrom, first.point)), rng, spread)
	end
	local alpha = input.damage
	if alpha == nil then
		alpha = Penetration.rollDamage(shell.damage, rng, spread)
	end
	local penNow: number = if isFinite(pen :: number) then pen :: number else 0
	local alphaNow: number = if isFinite(alpha :: number) and (alpha :: number) > 0 then alpha :: number else 0
	o.penetrationMm = penNow
	o.potentialDamage = alphaNow

	local ctx: Ctx = {
		o = o,
		shell = shell,
		rng = rng,
		state = state,
		alpha = alphaNow,
		moduleBase = if shell.damage > 0 then shell.moduleDamage * (alphaNow / shell.damage) else shell.moduleDamage,
		crewChanceMul = target.crewInjuryChanceMul or (if state ~= nil then state.crewInjuryChanceMul else nil) or 1,
		kSpall = target.spallFactor or (if state ~= nil then state.spallFactor else nil) or C.SPALL_FACTOR_BASE,
	}
	local explosive = Penetration.isExplosive(shell.kind)
	local heat = shell.kind == "HEAT"
	local ricochets = input.ricochets or 0
	o.ricochets = ricochets
	local curDir = dir
	local inside = 0
	local gapFrom: number? = nil
	local plates = 0
	local decided = false
	local lastSpaced: Crossing? = nil
	local lastSpacedBuf: CrossingBuffer = buf
	local lastSpacedIndex = 0

	while i <= buf.count do
		local c = buf.items[i]
		local kind = c.volumeKind
		local plateKind: PlateKind? = nil
		if kind == "Armor" then
			if c.entering then
				if inside == 0 then
					plateKind = "Main"
				end
				inside += 1
			else
				inside = math.max(0, inside - 1)
			end
		elseif (kind == "Spaced" or kind == "Layered") and inside == 0 then
			if c.entering then
				plateKind = kind :: PlateKind
			elseif heat then
				gapFrom = c.distance
			end
		end

		if plateKind == nil then
			i += 1
			continue
		end

		plates += 1
		o.plates = plates
		if plates > C.MAX_PLATES then
			o.result = if explosive then "HEBlast" else "NonPenetration"
			o.absorbed = true
			if explosive then
				finishHE(ctx, input, c.point)
			end
			decided = true
			break
		end
		if heat and gapFrom ~= nil then
			penNow *= Penetration.heatGapFactor(math.max(0, c.distance - gapFrom) / STUDS)
			gapFrom = nil
		end
		local angle = ArmorGeometry.impactAngleDeg(curDir, c.normal)
		Penetration.resolvePlate(shell, plateKind, c.thicknessMm, angle, penNow, plate)
		local impact = o.impact
		if plates == 1 and impact ~= nil then
			impact.effectiveMm = plate.effectiveMm
			impact.angleDeg = angle
		end
		if plateKind == "Spaced" and c.module ~= nil then
			-- External module (track, barrel): damaged by every hit, including ricochets and absorbed shells.
			if rng:chance(C.EXTERNAL_HIT_CHANCE) then
				addModuleHit(ctx, c.module, ctx.moduleBase, true, c.volumeId)
			end
		end

		if plate.outcome == "Ricochet" then
			ricochets += 1
			o.ricochets = ricochets
			o.effectiveArmorMm = plate.effectiveMm
			o.decidingZone = c.zone
			penNow = plate.penAfter
			if ricochets > C.RICOCHET_MAX then
				o.result = "Ricochet"
				o.deleted = true
				decided = true
				break
			end
			local newDir = ArmorGeometry.reflect(curDir, c.normal)
			if newDir.Magnitude > 0 then
				newDir = newDir.Unit
			end
			local newOrigin = c.point + c.normal * C.RICOCHET_SURFACE_OFFSET_STUDS
			local other = if buf == bufA then bufB else bufA
			ArmorGeometry.raycast(armor, pose, newOrigin, newDir, nil, other)
			local nextIndex = firstHitIndex(other, 1)
			if nextIndex ~= 0 then
				buf = other
				i = nextIndex
				curDir = newDir
				inside = 0
				gapFrom = nil
				lastSpaced = nil
				continue
			end
			o.result = "Ricochet"
			o.ricochetRay = {
				origin = newOrigin,
				direction = newDir,
				penetrationMm = penNow,
				damage = alphaNow,
				ricochets = ricochets,
			}
			decided = true
			break
		end

		if plate.outcome == "Stopped" then
			o.effectiveArmorMm = plate.effectiveMm
			o.decidingZone = c.zone
			penNow = plate.penAfter
			if explosive then
				o.result = "HEBlast"
				if plateKind == "Spaced" then
					-- Burst on the screen: splash on this vehicle's body behind it, no guaranteed damage.
					o.absorbed = true
					local mainPlate = nextMainPlate(buf, i)
					if mainPlate ~= nil then
						local dM = (mainPlate.distance - c.distance) / STUDS
						o.damage = HE.splashDamage(alphaNow, dM, HE.radiusM(shell), mainPlate.thicknessMm, ctx.kSpall)
					end
				else
					o.damage = HE.nonPenDamage(shell.damage, alphaNow, c.thicknessMm, ctx.kSpall, shell.kind)
					spallSphere(ctx, armor, pose, c.point, C.HE_SPALL_MODULE_MUL)
				end
				finishHE(ctx, input, c.point)
			else
				o.result = "NonPenetration"
				o.absorbed = plateKind == "Spaced"
			end
			decided = true
			break
		end

		-- Penetrated
		penNow = plate.penAfter
		if plateKind == "Main" then
			o.effectiveArmorMm = plate.effectiveMm
			o.decidingZone = c.zone
			o.result = "Penetration"
			o.damage = alphaNow
			if explosive then
				spallSphere(ctx, armor, pose, c.point, 1)
				finishHE(ctx, input, c.point)
			else
				internalPath(ctx, buf, i)
			end
			decided = true
			break
		end
		-- Spaced / Layered penetrated: keep going (HEAT measures the gap from where it leaves this plate).
		if heat then
			gapFrom = c.distance
		end
		if plateKind == "Spaced" then
			lastSpaced = c
			lastSpacedBuf = buf
			lastSpacedIndex = i
		end
		i += 1
	end

	if not decided then
		-- Passed through spaced/layered plates and left the vehicle without reaching the body: consumed.
		o.absorbed = true
		if explosive then
			o.result = "HEBlast"
			local burst = lastSpaced
			if burst ~= nil then
				local mainPlate = nextMainPlate(lastSpacedBuf, lastSpacedIndex)
				if mainPlate ~= nil then
					local dM = (mainPlate.distance - burst.distance) / STUDS
					o.damage = HE.splashDamage(alphaNow, dM, HE.radiusM(shell), mainPlate.thicknessMm, ctx.kSpall)
				end
				finishHE(ctx, input, burst.point)
			elseif o.impact ~= nil then
				finishHE(ctx, input, (o.impact :: any).point)
			end
		else
			o.result = "NonPenetration"
		end
	end
	o.penetrationRemainingMm = if isFinite(penNow) and penNow > 0 then penNow else 0
	if not isFinite(o.damage) or o.damage < 0 then
		o.damage = 0
	end
	return o
end

--- HE/HESH burst that did not strike a vehicle (terrain, max range): splash on `nearby`. `damage` = the rolled
--- alpha when already known (else rolled here with `rng`).
function ShotResolver.burst(
	shell: CombatShell,
	point: Vector3,
	nearby: { SplashCandidate },
	rng: RNG,
	damage: number?,
	spread: number?
): { SplashHit }
	local out: { SplashHit } = {}
	if not Penetration.isExplosive(shell.kind) or not finiteVector(point) then
		return out
	end
	local alpha = damage or Penetration.rollDamage(shell.damage, rng, spread)
	splashAt(shell, point, alpha, nearby, out)
	return out
end

--- The candidate a ray strikes first within `maxDistance` studs: (index, distance) or nil. Candidates listed in
--- `skip` (e.g. the shooter) are ignored. Ties keep the lower index (callers pass candidates in a stable order).
function ShotResolver.nearestTarget(
	candidates: { ShotTarget },
	origin: Vector3,
	direction: Vector3,
	maxDistance: number?,
	skip: { [ShotTarget]: boolean }?
): (number?, number?)
	local bestIndex: number? = nil
	local bestDistance = math.huge
	for index, candidate in candidates do
		if skip ~= nil and skip[candidate] then
			continue
		end
		local d = ArmorGeometry.firstHitDistance(candidate.armor, candidate.pose, origin, direction, maxDistance)
		if d ~= nil and d < bestDistance then
			bestIndex = index
			bestDistance = d
		end
	end
	if bestIndex == nil then
		return nil, nil
	end
	return bestIndex, bestDistance
end

--- The ledger / HUD result kind (Types/Battle ShotResultKind) of an outcome; nil for a Miss. Ally and splash-only
--- kinds ("AllyBlocked", "Splash") are the caller's to assign.
function ShotResolver.toShotResultKind(o: ShotOutcome): BattleTypes.ShotResultKind?
	if o.result == "Miss" then
		return nil
	elseif o.result == "Penetration" then
		return "Penetration"
	elseif o.result == "Ricochet" then
		return "Ricochet"
	end
	return if o.absorbed and o.damage <= 0 then "Absorbed" else "NonPenetration"
end

return ShotResolver
