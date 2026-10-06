--!strict
--[[
	Config/Combat — every combat tunable: shell families, normalization / overmatch / ricochet, penetration and
	damage RNG, distance falloff, shell flight, HEAT and HE/HESH rules, splash, modules, internal path, fire, crew
	injuries and crew curves, ramming, falls, drowning, stun and dispersion (aiming).

	Purpose:          Single source of the numbers in docs/research/00-DECISIONS.md §1–§4 (values marked there as
	                  W/O/P) consumed by Shared/Combat/* and the StatsCalculator authoring defaults. Design notes:
	                  docs/design/combat.md (each key is referenced there with its formula).
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides);
	                  tests assert every default lies inside its bounds (Config.validateBounds).
	Error handling:   N/A.
	Performance notes: Read via `Config.Combat` at use time (live overrides replace the section table, so cached
	                  references go stale). Combat modules read the section once per call, never per inner loop step.

	Units are real-world (mm, m, m/s, m/s², deg, s, kg/t); Combat converts to studs at the boundary (Core/Units).
	Shell kinds: AP, APCR, HEAT, HE, HESH. "Kinetic" = AP/APCR, "explosive" = HE/HESH.
]]

local Combat = {
	----------------------------------------------------------------------------------------------------------------
	-- Shell families (00-DECISIONS §1 "Families", "Defaults")
	----------------------------------------------------------------------------------------------------------------

	--- Kinetic families: 2-/3-calibre rules, ricochet pen penalty, distance falloff.
	KINETIC = { AP = true, APCR = true, HEAT = false, HE = false, HESH = false },
	--- Explosive families: never ricochet, 3 T screen cost, non-penetration blast damage, splash.
	EXPLOSIVE = { AP = false, APCR = false, HEAT = false, HE = true, HESH = true },
	--- Base normalization n (deg) toward the plate normal (authoring default for ShellStats.normalizationDeg).
	NORMALIZATION_DEG = { AP = 5, APCR = 2, HEAT = 0, HE = 0, HESH = 0 },
	--- Auto-ricochet when the raw impact angle θ (from the normal) is strictly greater (deg). 90 = never.
	RICOCHET_ANGLE_DEG = { AP = 70, APCR = 70, HEAT = 85, HE = 90, HESH = 90 },

	--- 2-calibre rule: kinetic shells with caliber > TWO_CALIBER_RATIO × T (strict) get
	--- n' = n × TWO_CALIBER_FACTOR × caliber / (TWO_CALIBER_RATIO × T).
	TWO_CALIBER_RATIO = 2,
	TWO_CALIBER_FACTOR = 1.4,
	--- 3-calibre rule (overmatch): kinetic shells with caliber > THREE_CALIBER_RATIO × T (strict) never ricochet.
	THREE_CALIBER_RATIO = 3,
	--- T_eff = T / max(EFFECTIVE_COS_FLOOR, cos(max(0, θ − n'))).
	EFFECTIVE_COS_FLOOR = 0.05,
	--- Plates (spaced + layered + main) walked per shell before it is consumed.
	MAX_PLATES = 8,

	--- Ricochet continuation (00-DECISIONS §1 "Continuation", OUR DESIGN CHOICE): at most RICOCHET_MAX ricochets
	--- per shell; the next one deletes it. Remaining pen × RICOCHET_PEN_MUL[kind] after each ricochet.
	RICOCHET_MAX = 1,
	RICOCHET_PEN_MUL = { AP = 0.75, APCR = 0.75, HEAT = 1.0 },
	--- The reflected ray starts this far outside the plate (studs) so it never re-hits the face it bounced off.
	RICOCHET_SURFACE_OFFSET_STUDS = 0.01,

	--- Authoring defaults (00-DECISIONS §1 "Defaults"): special pen = AP × SPECIAL_PEN_RATIO (same alpha);
	--- HE alpha = AP alpha × HE_ALPHA_RATIO; HE pen = caliber × HE_PEN_PER_CALIBER; HESH pen = caliber × 1.6.
	SPECIAL_PEN_RATIO = 1.30,
	HE_ALPHA_RATIO = 1.30,
	HE_PEN_PER_CALIBER = 0.5,
	HESH_PEN_PER_CALIBER = 1.6,

	----------------------------------------------------------------------------------------------------------------
	-- Penetration / damage RNG (00-DECISIONS §1 "RNG")
	----------------------------------------------------------------------------------------------------------------

	--- Rolls are a normal truncated at ±ROLL_SPREAD of the mean, with ROLL_SPREAD = ROLL_SPREAD_SIGMAS × σ
	--- (σ = 0.125 × mean). Out-of-range draws are re-rolled up to ROLL_RESAMPLE_TRIES times, then clamped.
	ROLL_SPREAD = 0.25,
	ROLL_SPREAD_SIGMAS = 2,
	ROLL_RESAMPLE_TRIES = 8,
	--- Spread used when the battle mode asks for reduced RNG (`COMPETITIVE_SPREAD` mode, off in Random).
	COMPETITIVE_SPREAD = 0.10,

	----------------------------------------------------------------------------------------------------------------
	-- Distance falloff and shell flight (00-DECISIONS §1 "Falloff", "Velocity", "Gravity / range")
	----------------------------------------------------------------------------------------------------------------

	--- AP/APCR pen is nominal up to FALLOFF_START_M, linear to the 500 m value at FALLOFF_END_M, flat beyond.
	FALLOFF_START_M = 100,
	FALLOFF_END_M = 500,
	--- Authoring default of ShellStats.penetrationAt500Mm as a fraction of penetrationMm (other kinds: 1.0).
	FALLOFF_AT_END = { AP = 0.90, APCR = 0.75 },

	--- In-game muzzle velocity = VELOCITY_SCALE × the authored real-world figure (ShellDefinition is already scaled).
	VELOCITY_SCALE = 0.6,
	--- Authoring default velocity per family as a fraction of the gun's AP velocity.
	VELOCITY_RATIO = { AP = 1.0, APCR = 1.25, HEAT = 0.85, HE = 1.0, HESH = 1.0 },
	--- Shell gravity (m/s²), independent of Workspace.Gravity (19.62 m/s² = 58.86 studs/s²).
	SHELL_GRAVITY_MPS2 = 19.62,
	--- Direct-fire shells despawn after this path length (m); HE bursts where it ends on terrain.
	MAX_RANGE_M = 600,
	--- Indirect (artillery) shells need at least this max range (m).
	ARTILLERY_MIN_RANGE_M = 900,

	----------------------------------------------------------------------------------------------------------------
	-- HEAT (00-DECISIONS §1 "HEAT spaced")
	----------------------------------------------------------------------------------------------------------------

	--- After any plate the jet keeps pen × max(0, 1 − HEAT_GAP_LOSS_PER_M × gap_m) across the air gap to the next
	--- plate (and along the internal path).
	HEAT_GAP_LOSS_PER_M = 0.5,

	----------------------------------------------------------------------------------------------------------------
	-- HE / HESH (00-DECISIONS §1 "HE (1.13 adapted)", "Splash"; §21 #30)
	----------------------------------------------------------------------------------------------------------------

	--- Screens, tracks and external modules cost HE_SCREEN_PEN_MUL × T (nominal); destructibles 1 × T.
	HE_SCREEN_PEN_MUL = 3.0,
	HE_DESTRUCTIBLE_PEN_MUL = 1.0,
	--- Non-penetrating direct hit: D = max(HE_NONPEN_FLOOR × α, HE_NONPEN_ALPHA_FACTOR × α_rolled
	---   − HE_ARMOR_FACTOR × T_nominal × K_spall) × (HESH: HESH_NONPEN_MUL).
	HE_NONPEN_ALPHA_FACTOR = 0.5,
	HE_ARMOR_FACTOR = 1.1,
	HE_NONPEN_FLOOR = 0.05,
	HESH_NONPEN_MUL = 1.15,
	--- Module/crew damage from the spall sphere of a NON-penetrating HE hit is × HE_SPALL_MODULE_MUL.
	HE_SPALL_MODULE_MUL = 0.5,
	--- Direct-fire splash/spall radius R (m) = caliber_mm × SPLASH_RADIUS_M_PER_MM (authoring default).
	SPLASH_RADIUS_M_PER_MM = 0.01,
	--- Artillery radius R (m) = ARTILLERY_SPLASH_BASE_M + ARTILLERY_SPLASH_PER_MM × caliber_mm.
	ARTILLERY_SPLASH_BASE_M = 3,
	ARTILLERY_SPLASH_PER_MM = 0.03,
	--- Splash on other vehicles: D = max(0, SPLASH_ALPHA_FACTOR × α_rolled × (1 − d/R) − HE_ARMOR_FACTOR × T_min ×
	--- K_spall). External modules inside R take moduleDamage × (1 − d/R) × SPLASH_MODULE_MUL.
	SPLASH_ALPHA_FACTOR = 0.5,
	SPLASH_MODULE_MUL = 1.0,
	--- K_spall without Spall Lining (VehicleStats.spallFactor = 1 + lining bonus).
	SPALL_FACTOR_BASE = 1.0,

	----------------------------------------------------------------------------------------------------------------
	-- Modules and crew (00-DECISIONS §2 "Modules", "HP", "States", "Internal path", "Module dmg", "Repair")
	----------------------------------------------------------------------------------------------------------------

	--- Module max HP = k × Tier.moduleHpRefAlpha (StatsCalculator); crew HP = CREW_HP_K × the same.
	MODULE_HP_K = {
		Engine = 1.0,
		AmmoRack = 0.9,
		FuelTank = 1.0,
		Gun = 1.0,
		TurretRing = 1.0,
		Optics = 0.8,
		TrackLeft = 1.4,
		TrackRight = 1.4,
	},
	CREW_HP_K = 0.8,
	--- Ok while hp > MODULE_DAMAGED_FRACTION × maxHp; Damaged at or below; Destroyed at 0.
	MODULE_DAMAGED_FRACTION = 0.5,
	--- Post-penetration path length = max(INTERNAL_PATH_MIN_M, INTERNAL_PATH_CALIBERS × caliber).
	INTERNAL_PATH_MIN_M = 0.5,
	INTERNAL_PATH_CALIBERS = 10,
	--- Chance that a Module volume crossed by the internal path / inside the spall sphere is damaged.
	MODULE_HIT_CHANCE = {
		Engine = 0.45,
		FuelTank = 0.45,
		TurretRing = 0.45,
		Optics = 0.45,
		Gun = 0.33,
		AmmoRack = 0.27,
		TrackLeft = 1.0,
		TrackRight = 1.0,
	},
	CREW_HIT_CHANCE = 0.33,
	--- External modules (Spaced volumes with a `module`: tracks, gun barrel) are damaged on every hit.
	EXTERNAL_HIT_CHANCE = 1.0,
	--- Authoring default ShellStats.moduleDamage = factor × alpha.
	MODULE_DAMAGE_FACTOR = { AP = 0.5, APCR = 0.5, HEAT = 0.5, HE = 0.75, HESH = 0.75 },
	--- One hit never removes more than MODULE_DAMAGE_CAP_MUL × the module's max HP.
	MODULE_DAMAGE_CAP_MUL = 1.2,
	--- Field repair Destroyed -> Damaged at REPAIR_RESTORE_FRACTION × maxHp after this many seconds (base, before
	--- crew level and equipment; StatsCalculator writes the scaled value into ModuleStats.repairS).
	REPAIR_S = {
		TrackLeft = 10,
		TrackRight = 10,
		Engine = 14,
		Gun = 12,
		TurretRing = 12,
		Optics = 8,
		FuelTank = 10,
		AmmoRack = 10, -- only reachable with 0 shells stored (no detonation); OUR DESIGN CHOICE
	},
	REPAIR_RESTORE_FRACTION = 0.5,

	--- Damaged / Destroyed module effects (00-DECISIONS §2 "Effects").
	ENGINE_DAMAGED_POWER_MUL = 0.5,
	AMMO_DAMAGED_RELOAD_MUL = 1.25,
	FUEL_DAMAGED_FIRE_MUL = 1.5,
	GUN_DAMAGED_AIM_MUL = 1.25,
	RING_DAMAGED_TRAVERSE_MUL = 0.5,
	OPTICS_DAMAGED_VR_MUL = 0.80,
	OPTICS_DESTROYED_VR_MUL = 0.50,
	--- Wheeled vehicles: each destroyed side (all wheel pairs on it) × this top speed instead of immobilising.
	WHEELED_LOST_SIDE_SPEED_MUL = 0.75,
	--- A destroyed ammo rack detonates the vehicle when at least this many shells are stored (REG-ARM-08).
	AMMO_RACK_DETONATION_MIN_SHELLS = 1,

	----------------------------------------------------------------------------------------------------------------
	-- Fire (00-DECISIONS §2 "Fire")
	----------------------------------------------------------------------------------------------------------------

	--- Fire chance per engine hit by fuel (EngineDefinition.fireChance default); destroyed fuel tank = 100 %.
	FIRE_CHANCE = { Petrol = 0.20, Diesel = 0.12, Turbine = 0.15 },
	FIRE_CHANCE_DEFAULT = 0.15,
	--- Burn time (s) and HP loss per second as a fraction of max HP (8 s × 2.5 % = 20 %).
	FIRE_DURATION_S = 8,
	FIRE_DAMAGE_PER_S = 0.025,
	--- Fire damage is applied in whole-HP chunks every FIRE_TICK_S seconds (fractional HP carries over).
	FIRE_TICK_S = 1.0,
	--- Engine-bay modules lose this fraction of their max HP per second while burning (OUR DESIGN CHOICE).
	FIRE_MODULE_DAMAGE_PER_S = 0.05,
	--- Each fire tick, one random uninjured crew member is hit with this chance for this fraction of crew max HP
	--- (OUR DESIGN CHOICE: "bay modules/crew hit").
	FIRE_CREW_HIT_CHANCE = 0.10,
	FIRE_CREW_DAMAGE_FRACTION = 0.25,
	--- Equipment / skill references for StatsCalculator: Fire Fighting −25 % duration, Damage Control Suite −65 %
	--- chance, Automatic Extinguisher −10 % chance.
	FIRE_FIGHTING_DURATION_MUL = 0.75,
	DCS_FIRE_CHANCE_MUL = 0.35,
	AUTO_EXTINGUISHER_FIRE_CHANCE_MUL = 0.90,
	--- An armed Automatic Extinguisher puts the fire out this long after ignition (s).
	AUTO_EXTINGUISHER_DELAY_S = 0.5,

	----------------------------------------------------------------------------------------------------------------
	-- Crew (00-DECISIONS §2 "Crew injury", §4 "L", "Reload", "Other stats")
	----------------------------------------------------------------------------------------------------------------

	--- Healthy crew level; an injured member works at CREW_INJURED_LEVEL; an injured commander costs every other
	--- member COMMANDER_INJURED_PENALTY levels and turns Sixth Sense off.
	CREW_BASE_LEVEL = 100,
	CREW_INJURED_LEVEL = 50,
	COMMANDER_INJURED_PENALTY = 10,
	--- Reload × RELOAD_CURVE_NUMERATOR / (RELOAD_CURVE_PER_LEVEL × L + RELOAD_CURVE_BASE) (= 1 at L 100).
	RELOAD_CURVE_NUMERATOR = 0.875,
	RELOAD_CURVE_PER_LEVEL = 0.00375,
	RELOAD_CURVE_BASE = 0.5,
	--- f(L) = STAT_CURVE_BASE + STAT_CURVE_PER_LEVEL × L (= 1 at L 100): × view range, hull/turret traverse;
	--- ÷ aim time, dispersion, repair time.
	STAT_CURVE_BASE = 0.57,
	STAT_CURVE_PER_LEVEL = 0.0043,

	----------------------------------------------------------------------------------------------------------------
	-- Ramming, falls, drowning (00-DECISIONS §2 "Ramming", "Falls", "Drowning")
	----------------------------------------------------------------------------------------------------------------

	--- D_B = max(0, RAM_ENERGY_FACTOR × m_A[t] × v² − RAM_ARMOR_FACTOR × T_B × K_spall_B), symmetric, only when the
	--- closing speed along the contact normal is >= RAM_MIN_SPEED_MPS. Damage taken on the front arc × 0.5.
	RAM_MIN_SPEED_MPS = 3,
	RAM_ENERGY_FACTOR = 0.05,
	RAM_ARMOR_FACTOR = 1.1,
	RAM_FRONT_ARC_TAKEN_MUL = 0.5,
	--- Contact bearings within ±RAM_FRONT_ARC_HALF_DEG of the hull's forward axis count as the front arc.
	RAM_FRONT_ARC_HALF_DEG = 45,
	--- Each party rolls RAM_TRACK_HIT_CHANCE for the track on the contact side; the track takes
	--- RAM_TRACK_DAMAGE_MUL × the raw energy term (before armor). OUR DESIGN CHOICE ("both roll tracks").
	RAM_TRACK_HIT_CHANCE = 0.5,
	RAM_TRACK_DAMAGE_MUL = 0.5,
	--- Landing with vertical speed v_y > FALL_MIN_SPEED_MPS: D = FALL_DAMAGE_FACTOR × m[t] × (v_y − 7)²,
	--- × FALL_INVERTED_MUL upside down; a random track is destroyed with chance min(1, (v_y − 7) / FALL_TRACK_SPAN_MPS).
	FALL_MIN_SPEED_MPS = 7,
	FALL_DAMAGE_FACTOR = 0.6,
	FALL_INVERTED_MUL = 2,
	FALL_TRACK_SPAN_MPS = 5,
	--- Water over the turret roof for DROWN_TIME_S (reset on exit) destroys the vehicle, no kill credit.
	DROWN_TIME_S = 10,
	--- Ram/fall contact ids remembered per vehicle so a persisting contact applies once (REG-ARM-10).
	CONTACT_MEMORY = 32,

	----------------------------------------------------------------------------------------------------------------
	-- Stun (artillery HE splash; 00-DECISIONS §7.4 "SPG")
	----------------------------------------------------------------------------------------------------------------

	STUN_RELOAD_MUL = 1.25,
	STUN_AIM_TIME_MUL = 1.25,
	STUN_DISPERSION_MUL = 1.20,
	STUN_TRAVERSE_MUL = 0.80,
	STUN_SPEED_MUL = 0.85,
	STUN_VIEW_RANGE_MUL = 0.90,

	----------------------------------------------------------------------------------------------------------------
	-- Aiming (00-DECISIONS §3)
	----------------------------------------------------------------------------------------------------------------

	--- "radial": miss radius = |N(0, σ)| at a uniform angle; "gauss2d": isotropic 2-D normal. Both re-roll beyond
	--- DISPERSION_EDGE_SIGMAS × σ, σ = R / DISPERSION_EDGE_SIGMAS (the circle edge is 2σ).
	DISPERSION_MODEL = "radial",
	DISPERSION_EDGE_SIGMAS = 2,
	DISPERSION_RESAMPLE_TRIES = 8,
	--- Bloom: M_target = √(1 + (k_mv·v_kmh)² + (k_hull·ω_hull)² + (k_tur·ω_tur)²) × damagedMul if the gun is damaged
	--- (authoring defaults of GunStats.bloom).
	BLOOM_MOVEMENT_PER_KMH = 0.07,
	BLOOM_HULL_TRAVERSE_PER_DEGS = 0.075,
	BLOOM_TURRET_TRAVERSE_PER_DEGS = 0.03,
	BLOOM_DAMAGED_MUL = 1.5,
	--- After a shot M = max(M, M_target) × afterShot (class default; derp/SPG 4.0).
	AFTER_SHOT_BLOOM = { light = 3.0, medium = 3.0, td = 3.0, heavy = 3.5, artillery = 4.0 },
	DERP_AFTER_SHOT_BLOOM = 4.0,
	--- Extra M_target multipliers: wheeled vehicle moving, stunned.
	WHEELED_MOVING_BLOOM_MUL = 1.15,
	--- References for StatsCalculator: Gyro Stabiliser × k, Snap Shot × k_tur.
	GYRO_BLOOM_MUL = 0.80,
	SNAP_SHOT_TURRET_BLOOM_MUL = 0.925,
	--- Sanity clamp on the dispersion multiplier M (guards against runaway inputs).
	DISPERSION_MAX_MULTIPLIER = 40,

	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {
		["NORMALIZATION_DEG.AP"] = { min = 0, max = 15 },
		["NORMALIZATION_DEG.APCR"] = { min = 0, max = 15 },
		["RICOCHET_ANGLE_DEG.AP"] = { min = 45, max = 90 },
		["RICOCHET_ANGLE_DEG.APCR"] = { min = 45, max = 90 },
		["RICOCHET_ANGLE_DEG.HEAT"] = { min = 45, max = 90 },
		TWO_CALIBER_RATIO = { min = 1, max = 5 },
		TWO_CALIBER_FACTOR = { min = 1, max = 3 },
		THREE_CALIBER_RATIO = { min = 1, max = 10 },
		EFFECTIVE_COS_FLOOR = { min = 0.01, max = 0.5 },
		MAX_PLATES = { min = 1, max = 16, integer = true },
		RICOCHET_MAX = { min = 0, max = 3, integer = true },
		["RICOCHET_PEN_MUL.AP"] = { min = 0, max = 1 },
		["RICOCHET_PEN_MUL.APCR"] = { min = 0, max = 1 },
		["RICOCHET_PEN_MUL.HEAT"] = { min = 0, max = 1 },
		ROLL_SPREAD = { min = 0, max = 0.5 },
		COMPETITIVE_SPREAD = { min = 0, max = 0.5 },
		ROLL_RESAMPLE_TRIES = { min = 1, max = 64, integer = true },
		FALLOFF_START_M = { min = 0, max = 400 },
		FALLOFF_END_M = { min = 100, max = 1000 },
		SHELL_GRAVITY_MPS2 = { min = 1, max = 100 },
		MAX_RANGE_M = { min = 100, max = 2000 },
		HEAT_GAP_LOSS_PER_M = { min = 0, max = 5 },
		HE_SCREEN_PEN_MUL = { min = 0, max = 10 },
		HE_NONPEN_ALPHA_FACTOR = { min = 0, max = 1 },
		HE_ARMOR_FACTOR = { min = 0, max = 5 },
		HE_NONPEN_FLOOR = { min = 0, max = 0.5 },
		HESH_NONPEN_MUL = { min = 0.5, max = 2 },
		HE_SPALL_MODULE_MUL = { min = 0, max = 1 },
		SPLASH_ALPHA_FACTOR = { min = 0, max = 1 },
		SPLASH_MODULE_MUL = { min = 0, max = 2 },
		["MODULE_HIT_CHANCE.Engine"] = { min = 0, max = 1 },
		["MODULE_HIT_CHANCE.FuelTank"] = { min = 0, max = 1 },
		["MODULE_HIT_CHANCE.TurretRing"] = { min = 0, max = 1 },
		["MODULE_HIT_CHANCE.Optics"] = { min = 0, max = 1 },
		["MODULE_HIT_CHANCE.Gun"] = { min = 0, max = 1 },
		["MODULE_HIT_CHANCE.AmmoRack"] = { min = 0, max = 1 },
		CREW_HIT_CHANCE = { min = 0, max = 1 },
		EXTERNAL_HIT_CHANCE = { min = 0, max = 1 },
		INTERNAL_PATH_MIN_M = { min = 0, max = 5 },
		INTERNAL_PATH_CALIBERS = { min = 0, max = 30 },
		MODULE_DAMAGE_CAP_MUL = { min = 0.5, max = 5 },
		MODULE_DAMAGED_FRACTION = { min = 0.05, max = 0.95 },
		REPAIR_RESTORE_FRACTION = { min = 0.05, max = 1 },
		ENGINE_DAMAGED_POWER_MUL = { min = 0, max = 1 },
		AMMO_DAMAGED_RELOAD_MUL = { min = 1, max = 3 },
		FUEL_DAMAGED_FIRE_MUL = { min = 1, max = 5 },
		GUN_DAMAGED_AIM_MUL = { min = 1, max = 3 },
		RING_DAMAGED_TRAVERSE_MUL = { min = 0, max = 1 },
		OPTICS_DAMAGED_VR_MUL = { min = 0, max = 1 },
		OPTICS_DESTROYED_VR_MUL = { min = 0, max = 1 },
		WHEELED_LOST_SIDE_SPEED_MUL = { min = 0, max = 1 },
		AMMO_RACK_DETONATION_MIN_SHELLS = { min = 0, max = 1000, integer = true },
		FIRE_DURATION_S = { min = 1, max = 60 },
		FIRE_DAMAGE_PER_S = { min = 0, max = 0.2 },
		FIRE_TICK_S = { min = 0.1, max = 2 },
		FIRE_MODULE_DAMAGE_PER_S = { min = 0, max = 0.5 },
		FIRE_CREW_HIT_CHANCE = { min = 0, max = 1 },
		FIRE_CREW_DAMAGE_FRACTION = { min = 0, max = 1 },
		AUTO_EXTINGUISHER_DELAY_S = { min = 0, max = 5 },
		CREW_INJURED_LEVEL = { min = 0, max = 100 },
		COMMANDER_INJURED_PENALTY = { min = 0, max = 50 },
		RAM_MIN_SPEED_MPS = { min = 0, max = 20 },
		RAM_ENERGY_FACTOR = { min = 0, max = 1 },
		RAM_ARMOR_FACTOR = { min = 0, max = 5 },
		RAM_FRONT_ARC_TAKEN_MUL = { min = 0, max = 1 },
		RAM_TRACK_HIT_CHANCE = { min = 0, max = 1 },
		RAM_TRACK_DAMAGE_MUL = { min = 0, max = 5 },
		FALL_MIN_SPEED_MPS = { min = 0, max = 30 },
		FALL_DAMAGE_FACTOR = { min = 0, max = 10 },
		FALL_INVERTED_MUL = { min = 1, max = 5 },
		FALL_TRACK_SPAN_MPS = { min = 0.1, max = 30 },
		DROWN_TIME_S = { min = 1, max = 60 },
		DISPERSION_EDGE_SIGMAS = { min = 1, max = 4 },
		BLOOM_MOVEMENT_PER_KMH = { min = 0, max = 1 },
		BLOOM_HULL_TRAVERSE_PER_DEGS = { min = 0, max = 1 },
		BLOOM_TURRET_TRAVERSE_PER_DEGS = { min = 0, max = 1 },
		BLOOM_DAMAGED_MUL = { min = 1, max = 5 },
		WHEELED_MOVING_BLOOM_MUL = { min = 1, max = 3 },
		STUN_DISPERSION_MUL = { min = 1, max = 3 },
		STUN_RELOAD_MUL = { min = 1, max = 3 },
		STUN_AIM_TIME_MUL = { min = 1, max = 3 },
		DISPERSION_MAX_MULTIPLIER = { min = 5, max = 200 },
	},
}

return Combat
