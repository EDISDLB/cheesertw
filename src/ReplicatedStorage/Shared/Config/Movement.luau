--!strict
--[[
	Config/Movement — tunables of the shared vehicle simulation (VehicleSim, TurretSim, Collision): terrain resistance
	and traction by ground material, power-to-weight acceleration, slope limits, braking, hull traverse, ground fit,
	falling, obstacles, water/drowning, overturn, turret/gun drives and vehicle–vehicle contacts.

	Purpose:          Every movement number lives here in REAL units (m, m/s, m/s², km/h, deg, s); the sims convert to
	                  studs at the boundary (Units.STUDS_PER_METER = 3). Values follow docs/research/00-DECISIONS.md §2
	                  (drowning, overturn) and §6 (movement); the rest is OUR DESIGN CHOICE, documented in
	                  docs/design/movement.md and calibrated by playtest.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides);
	                  the Movement spec asserts every default lies inside its bounds.
	Error handling:   N/A.
	Performance notes: Read via Config.Movement once per step (live overrides replace the section table).
]]

local Movement = {
	----------------------------------------------------------------------------
	-- Terrain (00-DECISIONS §6)
	----------------------------------------------------------------------------

	--- Ground material -> resistance class. The first 16 entries are 00-DECISIONS §6; the rest (man-made props,
	--- bridges, extra Terrain materials) are OUR DESIGN CHOICE. Unknown materials use DEFAULT_TERRAIN_CLASS.
	MATERIAL_CLASS = {
		Concrete = "hard",
		Asphalt = "hard",
		Pavement = "hard",
		Cobblestone = "hard",
		Brick = "hard",
		Slate = "hard",
		Rock = "hard",
		Basalt = "hard",
		Grass = "medium",
		LeafyGrass = "medium",
		Ground = "medium",
		Sandstone = "medium",
		Sand = "soft",
		Mud = "soft",
		Snow = "soft",
		Glacier = "soft",
		-- OUR DESIGN CHOICE: structures and remaining Terrain materials.
		Wood = "hard",
		WoodPlanks = "hard",
		Metal = "hard",
		DiamondPlate = "hard",
		CorrodedMetal = "hard",
		Plastic = "hard",
		SmoothPlastic = "hard",
		Granite = "hard",
		Marble = "hard",
		Limestone = "hard",
		CrackedLava = "hard",
		Pebble = "medium",
		Salt = "medium",
		Ice = "soft",
	} :: { [string]: string },
	DEFAULT_TERRAIN_CLASS = "medium",

	--- Track/ground friction coefficient μ per class: caps tractive and braking acceleration at μ·g·cos θ and sets
	--- the side-slip limit (00-DECISIONS §6: .75/.70/.60).
	TRACTION = { hard = 0.75, medium = 0.70, soft = 0.60 },
	--- Rolling-resistance coefficient: a_resist = g · ROLLING_RESISTANCE · R · cos θ, R = the tracks' terrain
	--- resistance for the class (00-DECISIONS §6 formula "0.10·R").
	ROLLING_RESISTANCE = 0.10,
	--- Power term floor: a_drive = P / (m · max(v, MIN_POWER_SPEED_MPS)) (00-DECISIONS §6).
	MIN_POWER_SPEED_MPS = 1.0,
	--- Mechanical horsepower -> watts.
	WATTS_PER_HP = 745.7,
	--- Gravity for vehicles (m/s²). Shells use their own g (00-DECISIONS §1).
	GRAVITY_MPS2 = 9.81,
	--- Steepest slope a vehicle can drive up (00-DECISIONS §6; REG-VEH-03). Above it there is no uphill drive force.
	MAX_CLIMB_DEG = 35,

	----------------------------------------------------------------------------
	-- Speed caps, braking (00-DECISIONS §6; OUR DESIGN CHOICE values)
	----------------------------------------------------------------------------

	--- Default reverse speed when VehicleStats.reverseSpeedKmh is missing: clamp(ratio × forward, min, max).
	REVERSE_DEFAULT_RATIO = 0.35,
	REVERSE_MIN_KMH = 12,
	REVERSE_MAX_KMH = 25,
	--- Service brakes (throttle against the motion, or the brake input), capped by traction.
	BRAKE_DECEL_MPS2 = 8.0,
	--- Engine braking while coasting or above the throttle-scaled speed cap, capped by traction.
	ENGINE_BRAKE_DECEL_MPS2 = 3.5,
	--- Engine module Damaged: power × this (00-DECISIONS §2 "Engine power ×.5"). Destroyed = immobile.
	ENGINE_DAMAGED_POWER_MUL = 0.5,
	--- Absolute speed clamp (km/h), whatever the stats/modifiers say (NaN/exploit guard).
	ABSOLUTE_MAX_SPEED_KMH = 160,

	----------------------------------------------------------------------------
	-- Hull traverse (00-DECISIONS §6)
	----------------------------------------------------------------------------

	--- Hull traverse multiplier at top speed (linear from 1 at standstill): "down to ×.6 at top speed".
	HULL_TRAVERSE_TOP_SPEED_MUL = 0.6,
	--- Time to reach the full traverse rate from rest (and to stop from it). OUR DESIGN CHOICE.
	HULL_TRAVERSE_RESPONSE_S = 0.15,
	--- Tracked vehicles without neutral steer (pivot = false) turn in place about the inner track centre line,
	--- this fraction of the hull width from the centre. Below NON_PIVOT_SPEED_KMH they use it.
	TRACK_CENTRELINE_FRACTION = 0.4,
	NON_PIVOT_SPEED_KMH = 2,

	----------------------------------------------------------------------------
	-- Ground fit and falling (OUR DESIGN CHOICE)
	----------------------------------------------------------------------------

	--- Exponential rate (1/s) at which pitch/roll follow the ground-fit plane.
	GROUND_FIT_RATE = 10,
	--- Ground within this distance below the hull keeps it grounded (snapped); samples further below are not in
	--- contact (cliff edges, crests at speed) and do not tilt the hull.
	GROUND_SNAP_M = 0.3,
	--- Highest step (kerb, rubble, terrain seam) the tracks climb in one tick; a higher rise is a wall. Static boxes
	--- lower than this are driven over, taller ones block (the obstacle sweep starts at this height).
	STEP_HEIGHT_M = 0.6,
	--- Ground probes start this far above the step height over the predicted contact point.
	GROUND_PROBE_UP_M = 1.0,
	--- A probe that starts inside geometry is recast from this far above (distinguishes walls from holes).
	GROUND_RECAST_UP_M = 60,
	--- Spawn settle probes start this far above the spawn point.
	SETTLE_PROBE_UP_M = 100,
	--- While resting (no input, no motion) the ground is re-probed at this period only.
	REST_REPROBE_S = 0.5,
	--- Stationary thresholds (hull speed / yaw rate) for stillTime and Hydropneumatic settling.
	STILL_SPEED_KMH = 0.5,
	STILL_YAW_DEGS = 2,
	--- Side slip: lateral friction = μ · g · cos(tilt) × this. Vehicles slide off side slopes steeper than atan(μ).
	LATERAL_FRICTION_MUL = 1.0,
	--- Terminal fall speed clamp (m/s).
	MAX_FALL_SPEED_MPS = 60,
	--- Landed events below this vertical impact speed are not emitted (fall damage starts at 7 m/s, combat-owned).
	LANDED_EVENT_MIN_MPS = 1.0,
	--- Falling below this height (m) with no ground under the vehicle loses it (FellOut).
	KILL_PLANE_Y_M = -150,

	----------------------------------------------------------------------------
	-- Static obstacles (world:sweepBox; OUR DESIGN CHOICE)
	----------------------------------------------------------------------------

	--- Gap kept between the hull box and an obstacle after a blocked move.
	OBSTACLE_SKIN_M = 0.01,
	--- Obstacle events for non-destructibles only above this closing speed (destructibles always report).
	OBSTACLE_EVENT_MIN_MPS = 1.0,
	--- Share of the closing velocity kept on a destructible contact (the server decides whether it breaks).
	DESTRUCTIBLE_SPEED_KEEP = 0.85,
	--- Push-out speed when the hull starts a step already overlapping an obstacle.
	DEPENETRATION_SPEED_MPS = 2.0,

	----------------------------------------------------------------------------
	-- Water (00-DECISIONS §2 drowning, §6 fording)
	----------------------------------------------------------------------------

	--- Fording penalties apply from this depth over the hull bottom.
	WATER_EFFECT_MIN_DEPTH_M = 0.2,
	--- In water: terrain resistance = soft × this, top/reverse speed × WATER_SPEED_MUL ("soft ×1.5, speed ×.5").
	WATER_RESISTANCE_MUL = 1.5,
	WATER_SPEED_MUL = 0.5,
	--- Water at or over the turret roof for this long destroys the vehicle (warning at the start, reset on exit).
	DROWN_TIME_S = 10,
	--- Fallback turret-roof height above the hull roof when no pivots are given (drown depth = hull height + this).
	DEFAULT_TURRET_HEIGHT_M = 0.9,

	----------------------------------------------------------------------------
	-- Overturn (00-DECISIONS §2; REG-VEH-05)
	----------------------------------------------------------------------------

	--- Tilt from upright (combined pitch/roll) beyond which the overturn timer runs.
	OVERTURN_DEG = 70,
	--- Time tilted beyond OVERTURN_DEG before the vehicle counts as overturned (immobile, gun off).
	OVERTURN_TIME_S = 3,
	--- "SelfRight": back on its tracks after SELF_RIGHT_S, no HP loss (00-DECISIONS). "Destroy": lost after
	--- OVERTURN_DESTROY_S (special modes).
	OVERTURN_RULE = "SelfRight",
	SELF_RIGHT_S = 10,
	OVERTURN_DESTROY_S = 10,

	----------------------------------------------------------------------------
	-- Map bounds and input sanitising
	----------------------------------------------------------------------------

	--- Default playable square (m) when newState gets no bounds (maps pass ±sizeM/2).
	DEFAULT_MAP_SIZE_M = 1000,
	--- Aim points are clamped to the map bounds grown by this margin, and to ±MAX_AIM_HEIGHT_M vertically.
	AIM_POINT_MARGIN_M = 1000,
	MAX_AIM_HEIGHT_M = 2000,
	--- Longest step simulated at once (s); longer dt values are clamped (hitches never tunnel).
	MAX_DT_S = 0.1,

	----------------------------------------------------------------------------
	-- Vehicle mechanics run by VehicleSim (00-DECISIONS §4 placement)
	----------------------------------------------------------------------------

	--- RocketBoost extra forward thrust while active (on top of +speedBonusKmh to the cap).
	ROCKET_BOOST_ACCEL_MPS2 = 3.0,

	----------------------------------------------------------------------------
	-- Turret and gun drives (TurretSim; OUR DESIGN CHOICE where not in content)
	----------------------------------------------------------------------------

	--- Gun elevation drive speed (deg/s); content has no per-gun value.
	GUN_ELEVATION_SPEED_DEGS = 20,
	--- Turret ring Damaged: traverse × this (00-DECISIONS §2 "Ring traverse ×.5"); Destroyed: no traverse.
	TURRET_RING_DAMAGED_MUL = 0.5,
	--- Gun Damaged: elevation speed × this (00-DECISIONS lists no effect; kept as a tuning hook).
	GUN_DAMAGED_ELEVATION_MUL = 1.0,
	--- Barrel within this angle of the desired direction = on target.
	ON_TARGET_DEG = 0.1,
	--- Casemate auto hull turn (TurretSim.autoHullSteer): full steer when the aim is this far outside the arc.
	AUTO_HULL_TURN_FULL_DEG = 5,
	--- Gun yaw limit of a casemate mount whose stats carry no yawLimitsDeg (00-DECISIONS §3 "casemate yaw ±11°").
	CASEMATE_DEFAULT_YAW_DEG = 11,

	----------------------------------------------------------------------------
	-- Vehicle–vehicle contacts (Collision; REG-VEH-04)
	----------------------------------------------------------------------------

	--- Restitution of vehicle contacts along the normal (0 = fully inelastic; <= 1 never creates energy).
	COLLISION_RESTITUTION = 0.1,

	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {
		["TRACTION.hard"] = { min = 0.1, max = 1.5 },
		["TRACTION.medium"] = { min = 0.1, max = 1.5 },
		["TRACTION.soft"] = { min = 0.1, max = 1.5 },
		ROLLING_RESISTANCE = { min = 0, max = 0.5 },
		MIN_POWER_SPEED_MPS = { min = 0.1, max = 5 },
		MAX_CLIMB_DEG = { min = 10, max = 60 },
		REVERSE_DEFAULT_RATIO = { min = 0.1, max = 1 },
		REVERSE_MIN_KMH = { min = 1, max = 40 },
		REVERSE_MAX_KMH = { min = 1, max = 80 },
		BRAKE_DECEL_MPS2 = { min = 0.5, max = 20 },
		ENGINE_BRAKE_DECEL_MPS2 = { min = 0, max = 15 },
		ENGINE_DAMAGED_POWER_MUL = { min = 0, max = 1 },
		ABSOLUTE_MAX_SPEED_KMH = { min = 20, max = 300 },
		HULL_TRAVERSE_TOP_SPEED_MUL = { min = 0.1, max = 1 },
		HULL_TRAVERSE_RESPONSE_S = { min = 0.01, max = 2 },
		TRACK_CENTRELINE_FRACTION = { min = 0, max = 0.5 },
		NON_PIVOT_SPEED_KMH = { min = 0, max = 20 },
		GROUND_FIT_RATE = { min = 0.5, max = 60 },
		GROUND_SNAP_M = { min = 0.05, max = 2 },
		STEP_HEIGHT_M = { min = 0.1, max = 2 },
		GROUND_PROBE_UP_M = { min = 0.1, max = 10 },
		GROUND_RECAST_UP_M = { min = 5, max = 500 },
		SETTLE_PROBE_UP_M = { min = 5, max = 1000 },
		REST_REPROBE_S = { min = 0, max = 5 },
		STILL_SPEED_KMH = { min = 0, max = 5 },
		STILL_YAW_DEGS = { min = 0, max = 20 },
		LATERAL_FRICTION_MUL = { min = 0.1, max = 3 },
		MAX_FALL_SPEED_MPS = { min = 10, max = 200 },
		LANDED_EVENT_MIN_MPS = { min = 0, max = 10 },
		KILL_PLANE_Y_M = { min = -2000, max = 0 },
		OBSTACLE_SKIN_M = { min = 0, max = 0.2 },
		OBSTACLE_EVENT_MIN_MPS = { min = 0, max = 10 },
		DESTRUCTIBLE_SPEED_KEEP = { min = 0, max = 1 },
		DEPENETRATION_SPEED_MPS = { min = 0.1, max = 20 },
		WATER_EFFECT_MIN_DEPTH_M = { min = 0, max = 2 },
		WATER_RESISTANCE_MUL = { min = 1, max = 5 },
		WATER_SPEED_MUL = { min = 0.05, max = 1 },
		DROWN_TIME_S = { min = 1, max = 120 },
		DEFAULT_TURRET_HEIGHT_M = { min = 0, max = 5 },
		OVERTURN_DEG = { min = 30, max = 179 },
		OVERTURN_TIME_S = { min = 0, max = 30 },
		SELF_RIGHT_S = { min = 0, max = 120 },
		OVERTURN_DESTROY_S = { min = 0, max = 120 },
		DEFAULT_MAP_SIZE_M = { min = 100, max = 5000 },
		AIM_POINT_MARGIN_M = { min = 0, max = 5000 },
		MAX_AIM_HEIGHT_M = { min = 100, max = 10000 },
		MAX_DT_S = { min = 0.01, max = 0.5 },
		ROCKET_BOOST_ACCEL_MPS2 = { min = 0, max = 20 },
		GUN_ELEVATION_SPEED_DEGS = { min = 1, max = 120 },
		TURRET_RING_DAMAGED_MUL = { min = 0, max = 1 },
		GUN_DAMAGED_ELEVATION_MUL = { min = 0, max = 1 },
		ON_TARGET_DEG = { min = 0, max = 5 },
		AUTO_HULL_TURN_FULL_DEG = { min = 0.5, max = 45 },
		CASEMATE_DEFAULT_YAW_DEG = { min = 1, max = 180 },
		COLLISION_RESTITUTION = { min = 0, max = 1 },
	},
}

return Movement
