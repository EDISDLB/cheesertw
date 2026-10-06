--!strict
--[[
	Config/Spotting — tunables of server-authoritative spotting (00-DECISIONS §5; research 02-R1…R10): spot-distance
	formula and caps, proximity, draw radius, check scheduling and ray budget, ports/checkpoints, camouflage
	composition, foliage and the 15 m rules, linger and last-known markers, Sixth Sense, smoke and attribution.

	Purpose:          Every spotting number lives here in REAL units (m, s, km/h, deg, 0..1 factors); Spotting/*
	                  converts to studs at the boundary (Units.STUDS_PER_METER = 3). Values follow 00-DECISIONS §5;
	                  keys marked OUR DESIGN CHOICE are documented in docs/design/spotting.md.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides);
	                  the VisibilityModel spec asserts every default lies inside its bounds.
	Error handling:   N/A.
	Performance notes: Read via Config.Spotting once per SpottingSystem:update / per VisibilityModel call (live overrides
	                  replace the section table, so never cache it across updates).
]]

local Spotting = {
	----------------------------------------------------------------------------
	-- Ranges (00-DECISIONS §5 "Formula", "Ranges")
	----------------------------------------------------------------------------

	--- Hard cap on the spot distance (m): spotDist = min(MAX_SPOT_RANGE_M, VR − (VR − FORMULA_FLOOR_M)·camo). View
	--- range itself is NOT capped (VR above 445 m eats into camouflage). Distances are hull centre to hull centre (3-D).
	MAX_SPOT_RANGE_M = 445,
	--- The "50" in the formula: a target with camo 1 would be seen only at this distance.
	FORMULA_FLOOR_M = 50,
	--- Targets within this hull-centre distance are always spotted, through any cover (no LOS ray is cast).
	PROXIMITY_RADIUS_M = 50,
	--- Full enemy state is replicated only within this radius of the receiving vehicle; team-visible enemies beyond
	--- it are sent as minimap records (MINIMAP_RECORD_HZ). Anti-wallhack invariant REG-SPT-08.
	ENEMY_DRAW_RANGE_M = 564,
	--- Rate of minimap-only records for team-visible enemies beyond ENEMY_DRAW_RANGE_M (consumed by replication).
	MINIMAP_RECORD_HZ = 2,

	----------------------------------------------------------------------------
	-- Camouflage composition (00-DECISIONS §5 "Formula", "Body camo", "Paint / shot")
	----------------------------------------------------------------------------

	--- Total camo cap per ray: camo = min(CAMO_TOTAL_CAP, body + foliage). OUR DESIGN CHOICE (WoT 1.0): no invisible
	--- TDs — a 445 m VR observer always spots at >= 89.5 m.
	CAMO_TOTAL_CAP = 0.90,
	--- Hull speed (km/h) above which a vehicle counts as moving (moving camo, nets/masts disarm) and below which it is
	--- stopped (EVENT_CHECK_ON_STOP). StatCondition "Stationary".
	STOP_SPEED_KMH = 0.5,
	--- Hull yaw rate (deg/s) above which a vehicle counts as moving even at zero speed (pivoting). Turret traverse alone
	--- never counts.
	MOVING_YAW_RATE_DEG_S = 2,
	--- Stationary time (s) before camo nets and masts arm (StatCondition "StationaryArmed"); they drop the tick the
	--- hull moves (REG-SPT-04 / REG-SPT-09).
	STATIONARY_ARM_S = 3,
	--- How long (s) after a shot the body camo is multiplied by GunStats.camoAfterShotMul (CamoStats.afterShotMul).
	SHOT_CAMO_PENALTY_S = 3,
	--- Default after-shot camo multiplier by calibre (used by StatsCalculator when a gun has no explicit value):
	--- camoAtShot = clamp(SHOT_CAMO_MUL_MAX − SHOT_CAMO_MUL_PER_MM·(calibre − SHOT_CAMO_REF_CALIBER_MM),
	--- SHOT_CAMO_MUL_MIN, SHOT_CAMO_MUL_MAX): 75 mm → 0.2625, 120 mm → 0.15, >= 160 mm → 0.05.
	SHOT_CAMO_MUL_MAX = 0.40,
	SHOT_CAMO_MUL_MIN = 0.05,
	SHOT_CAMO_MUL_PER_MM = 0.0025,
	SHOT_CAMO_REF_CALIBER_MM = 20,
	--- Flat camo bonus of a paint/camouflage/style with `camoBonus` (StatsCalculator folds it into CamoStats.paint).
	--- OUR DESIGN CHOICE: small and flat so cosmetics are never pay-for-stealth; 0 in ranked/competitive queues.
	PAINT_CAMO_BONUS = 0.04,
	PAINT_CAMO_BONUS_COMPETITIVE = 0,

	----------------------------------------------------------------------------
	-- Foliage (00-DECISIONS §5 "Foliage", "15 m rules")
	----------------------------------------------------------------------------

	--- Default concealment per Content.FoliageKind (a FoliageVolume.concealment overrides it). Grass gives none.
	FOLIAGE_CONCEALMENT = {
		LightBush = 0.25,
		Hedgerow = 0.40,
		DenseBush = 0.50,
		TreeCrown = 0.30,
		FelledTree = 0.30,
		Thicket = 0.60,
	} :: { [string]: number },
	--- No single foliage volume may conceal more than this (research 02-R5: "never above 0.64").
	FOLIAGE_CONCEALMENT_MAX = 0.64,
	--- Foliage stacks additively along a ray up to this cap (after the 15 m discounts).
	FOLIAGE_STACK_CAP = 0.80,
	--- Observer side: foliage the ray crosses within this distance (m) of the observer's port never conceals.
	FOLIAGE_OBSERVER_CLEAR_M = 15,
	--- Shooter side: for SHOT_FOLIAGE_PENALTY_S after firing, foliage the ray crosses within this distance (m) of the
	--- shooter's checkpoint stops concealing the shooter.
	FOLIAGE_SHOOTER_CLEAR_M = 15,
	--- OUR DESIGN CHOICE (WoT duration unpublished): longer than CHECK_INTERVAL_MAX_S, so every shot is seen by at
	--- least one scheduled check plus the forced shot check.
	SHOT_FOLIAGE_PENALTY_S = 3,

	----------------------------------------------------------------------------
	-- Check scheduling and budget (00-DECISIONS §5 "Schedule", "LOS points"; §18 server budget)
	----------------------------------------------------------------------------

	--- Pair check interval (s) by hull distance (m), piecewise linear between anchors {distanceM, intervalS},
	--- constant outside them, then clamped to CHECK_INTERVAL_MAX_S.
	CHECK_INTERVAL_CURVE = {
		{ 50, 0.10 },
		{ 150, 0.50 },
		{ 270, 1.00 },
		{ 445, 2.00 },
	} :: { { number } },
	--- OUR DESIGN CHOICE: clamp WoT's 2.0 s tail (late pop-in reads as a bug on Roblox).
	CHECK_INTERVAL_MAX_S = 1.0,
	--- Pair jitter: each scheduled interval is shortened by up to this fraction (deterministic golden-ratio sequence
	--- seeded by the pair), spreading checks across ticks without ever exceeding CHECK_INTERVAL_MAX_S.
	CHECK_JITTER_FRACTION = 0.2,
	--- Forced (immediate, highest-priority) checks: every pair where the shooter is the target on a shot; every pair
	--- of a vehicle that stops (< STOP_SPEED_KMH) or spawns/revives.
	EVENT_CHECK_ON_SHOT = true,
	EVENT_CHECK_ON_STOP = true,
	EVENT_CHECK_ON_SPAWN = true,
	--- World queries (World:sightLine) per tick. Due pairs are served forced first, then pairs deferred for
	--- DEFER_PRIORITY_S or more, then nearest first; the rest wait for the next tick. 00-DECISIONS §22 Q3: drop to 200
	--- if a Roblox raycast costs > 8 µs. Minimum = one worst-case pair (2 ports × MAX_CHECKPOINTS × 3 queries).
	MAX_RAYS_PER_TICK = 400,
	--- A due pair that has waited this long (s) past its scheduled time is served before nearer pairs (no starvation).
	DEFER_PRIORITY_S = 0.5,
	--- Visibility checkpoints used per target (VehiclePivots.camoPoints, 6 by convention); extras are ignored so the
	--- per-pair worst case stays bounded.
	MAX_CHECKPOINTS = 8,

	----------------------------------------------------------------------------
	-- Persistence, notifications, attribution (00-DECISIONS §5 "Linger", "Sixth Sense", "Rewards")
	----------------------------------------------------------------------------

	--- A target stays team-visible this long (s) after the last successful check by any observer of the team.
	SPOT_LINGER_S = 10,
	--- Faded last-known marker kept this long (s) after a target is lost (00-DECISIONS §21 #11: 30 s, not 60).
	LAST_KNOWN_MARKER_S = 30,
	--- Sixth Sense: one alert this long (s) after a vehicle first becomes team-visible to the enemy; no unspotted
	--- cue; suppressed while the commander is injured (SpottingVehicle.sixthSense == false).
	SIXTH_SENSE_DELAY_S = 3,
	--- How long the HUD shows the alert (brand chevron, 00-DECISIONS §16 / §21 #12). UI-only; Spotting does not use it.
	SIXTH_SENSE_ALERT_S = 2,
	--- Spotting-assist window (s): allies who saw the target within this window share the assist pool.
	ASSIST_WINDOW_S = 10,
	--- OUR DESIGN CHOICE (REG-SPT-07): a destroyed spotter still earns assist credit within ASSIST_WINDOW_S.
	DEAD_SPOTTER_ASSIST_CREDIT = true,
	--- OUR DESIGN CHOICE: the information a spotter relayed before dying keeps its targets lit for the rest of the
	--- linger (dead observers never start new sightings either way).
	DEAD_SPOTTER_KEEPS_LINGER = true,

	----------------------------------------------------------------------------
	-- Signal relay, smoke, weather (00-DECISIONS §5 "Signal range", "Smoke/weather")
	----------------------------------------------------------------------------

	--- Team-wide shared vision (no radio). Relay chains are reserved for special modes and NOT implemented in v1:
	--- SpottingSystem.new raises if this is true.
	SIGNAL_RELAY_ENABLED = false,
	--- Event smoke on a ray blocks it (Random battles have no smoke).
	SMOKE_BLOCKS_LOS = true,
	--- View range multiplier for an observer inside smoke.
	SMOKE_INSIDE_VR_MULT = 0.70,
	--- Default per-map-variant view range multiplier (weather/night hook for event modes; Random = 1).
	VISIBILITY_MULT_DEFAULT = 1,

	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {
		MAX_SPOT_RANGE_M = { min = 100, max = 1000 },
		FORMULA_FLOOR_M = { min = 0, max = 100 },
		PROXIMITY_RADIUS_M = { min = 0, max = 100 },
		ENEMY_DRAW_RANGE_M = { min = 200, max = 1500 },
		MINIMAP_RECORD_HZ = { min = 0.5, max = 10 },
		CAMO_TOTAL_CAP = { min = 0, max = 1 },
		STOP_SPEED_KMH = { min = 0, max = 5 },
		MOVING_YAW_RATE_DEG_S = { min = 0, max = 30 },
		STATIONARY_ARM_S = { min = 0, max = 10 },
		SHOT_CAMO_PENALTY_S = { min = 0, max = 10 },
		SHOT_CAMO_MUL_MAX = { min = 0, max = 1 },
		SHOT_CAMO_MUL_MIN = { min = 0, max = 1 },
		SHOT_CAMO_MUL_PER_MM = { min = 0, max = 0.05 },
		SHOT_CAMO_REF_CALIBER_MM = { min = 0, max = 200 },
		PAINT_CAMO_BONUS = { min = 0, max = 0.10 },
		PAINT_CAMO_BONUS_COMPETITIVE = { min = 0, max = 0.10 },
		["FOLIAGE_CONCEALMENT.LightBush"] = { min = 0, max = 0.64 },
		["FOLIAGE_CONCEALMENT.Hedgerow"] = { min = 0, max = 0.64 },
		["FOLIAGE_CONCEALMENT.DenseBush"] = { min = 0, max = 0.64 },
		["FOLIAGE_CONCEALMENT.TreeCrown"] = { min = 0, max = 0.64 },
		["FOLIAGE_CONCEALMENT.FelledTree"] = { min = 0, max = 0.64 },
		["FOLIAGE_CONCEALMENT.Thicket"] = { min = 0, max = 0.64 },
		FOLIAGE_CONCEALMENT_MAX = { min = 0, max = 1 },
		FOLIAGE_STACK_CAP = { min = 0, max = 1 },
		FOLIAGE_OBSERVER_CLEAR_M = { min = 0, max = 50 },
		FOLIAGE_SHOOTER_CLEAR_M = { min = 0, max = 50 },
		SHOT_FOLIAGE_PENALTY_S = { min = 0, max = 10 },
		CHECK_INTERVAL_MAX_S = { min = 0.1, max = 2 },
		CHECK_JITTER_FRACTION = { min = 0, max = 0.5 },
		MAX_RAYS_PER_TICK = { min = 48, max = 2000, integer = true },
		DEFER_PRIORITY_S = { min = 0, max = 5 },
		MAX_CHECKPOINTS = { min = 1, max = 8, integer = true },
		SPOT_LINGER_S = { min = 0, max = 30 },
		LAST_KNOWN_MARKER_S = { min = 0, max = 120 },
		SIXTH_SENSE_DELAY_S = { min = 0, max = 10 },
		SIXTH_SENSE_ALERT_S = { min = 0, max = 10 },
		ASSIST_WINDOW_S = { min = 0, max = 30 },
		SMOKE_INSIDE_VR_MULT = { min = 0, max = 1 },
		VISIBILITY_MULT_DEFAULT = { min = 0.1, max = 2 },
	},
}

return Spotting
