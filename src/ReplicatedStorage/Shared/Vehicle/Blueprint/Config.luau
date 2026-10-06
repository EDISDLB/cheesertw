--!strict
--[[
	Vehicle/Blueprint/Config — tunables of the procedural vehicle builder in REAL-WORLD units (m, deg, mm).

	Purpose:          Every number the Blueprint uses to turn content (VisualSpec + module visuals + armor) into
	                  geometry: LOD budgets (00-DECISIONS §18), running-gear proportions, internal-layout presets,
	                  detail sizes, palette defaults and materials. Converted to studs at the boundary (Core/Units).
	Dependencies:     Core/Freeze.
	State:            Constant table (deep-frozen at load).
	Validation:       Blueprint.spec checks the LOD budgets against 00-DECISIONS §18 and that every builder reads
	                  its keys from here.
	Error handling:   N/A.
	Performance notes: Read at build time only (a build happens once per vehicle + configuration).

	Owned by the Blueprint package. It lives beside the builder because the package may not edit Config/init;
	the lead may promote it to Config/Vehicle (or Config/Vfx) without changing a key name.
]]

local Freeze = require("../../Core/Freeze")

local BlueprintConfig = {
	--------------------------------------------------------------------------------------------------------------
	-- LOD (00-DECISIONS §18, ARCHITECTURE §6.3)
	--------------------------------------------------------------------------------------------------------------
	LOD_MAX_PARTS = { 400, 80, 16 }, -- LOD0, LOD1, LOD2 part budgets
	LOD_MAX_DISTANCE_STUDS = { 150, 600, 2400 }, -- camera distance ÷ zoom per tier (LOD3 = 2-D marker beyond)
	MAX_MATERIALS = 4, -- distinct render materials per vehicle (a Neon glow part counts as one)

	--------------------------------------------------------------------------------------------------------------
	-- Geometry tolerances
	--------------------------------------------------------------------------------------------------------------
	--- Largest distance between an Armor-kind volume's exposed surface and the visual tiling of it (REG-ARM-01
	--- parity). Exact tilings are within 1e-3 studs; oblique faces (pike noses, octagonal and hexagonal turrets)
	--- are approximated from inside and must stay within this.
	VISUAL_TOLERANCE_M = 0.15,
	--- Overlap of adjoining armor bodies (superstructure on the roof, sponsons on the core, bustle in the turret).
	BODY_OVERLAP_M = 0.1,
	--- Module and crew volumes stay this far inside their parent armor volume.
	INTERIOR_MARGIN_M = 0.03,
	--- Plate runs (front, rear, turret faces) are clamped so the flat core keeps at least this share of the length.
	MIN_CORE_FRACTION = 0.12,

	--------------------------------------------------------------------------------------------------------------
	-- Hull shape grammar
	--------------------------------------------------------------------------------------------------------------
	TRACK_GAP_M = 0.04, -- air gap between a track's inner edge and the hull side
	PIKE_HALF_ANGLE_DEG = 25, -- each pike-nose plate is yawed this far from the transverse direction
	WEDGE_TAPER_DEG = 16, -- Wedge style: plan taper of the front hull sides
	WEDGE_TAPER_FRACTION = 0.22, -- share of the hull length that tapers
	SLOPED_REAR_KNEE_FRACTION = 0.35, -- Sloped style: undercut lower rear plate up to this share of the height
	SLOPED_REAR_UNDERCUT_DEG = 45,
	CHAMFER_FRACTION = 0.14, -- Rounded style / chamfered_edges hook: chamfer depth as a share of hull height
	CHAMFER_DEG = 45,
	STEP_HEIGHT_FRACTION = 0.32, -- Stepped style: share of the hull height taken by the cab above the lip
	STEP_LIP_M = 0.12, -- Stepped style: ledge between the glacis top and the driver's plate
	STEP_PLATE_DEG = 12, -- Stepped style: driver's plate slope
	ENGINE_BAY_FRACTION = 0.3, -- engine compartment length / hull length
	RAISED_DECK_M = 0.16, -- engineDeck "Raised": deck above the roof
	RAISED_DECK_CHAMFER_DEG = 50,
	SUPERSTRUCTURE_REAR_DEG = 8,
	SIDE_SLOPE_MIN_BAND_M = 0.12, -- a side slope needs at least this much vertical band above its start

	--------------------------------------------------------------------------------------------------------------
	-- Running gear
	--------------------------------------------------------------------------------------------------------------
	TRACK_THICKNESS_M = 0.07,
	SPROCKET_DIAMETER_RATIO = 0.85, -- × road-wheel diameter
	IDLER_DIAMETER_RATIO = 0.8,
	END_WHEEL_RAISE_RATIO = 0.25, -- sprocket/idler axle above the road-wheel axle, × road-wheel radius
	RAISED_IDLER_RATIO = 0.35, -- raised_idler hook: extra idler raise, × road-wheel radius
	RETURN_ROLLER_DIAMETER_M = 0.22,
	RETURN_ROLLER_CLEARANCE_M = 0.05, -- gap between road-wheel tops and the rollers
	SAG_M = 0.05, -- sagging_track hook: dip of the top run between road wheels
	WHEEL_THICKNESS_RATIO = 0.42, -- road-wheel width / track width
	TIRE_WIDTH_M = 0.32, -- wheeled vehicles
	HUB_DIAMETER_RATIO = 0.42,
	AXLE_HUB_DIAMETER_RATIO = 0.6, -- axle_hubs hook
	GROUSER_SPACING_M = 0.45, -- Grousered / Chevron link detail spacing on the top run (LOD0)
	SKIRT_THICKNESS_M = 0.04, -- visual / geometric thickness of a skirt plate (penetration uses hull.armor.skirts)
	SKIRT_GAP_M = 0.03,
	SKIRT_PANELS = 4, -- "Plates" skirts: panels per side
	FULL_SKIRT_GROUND_M = 0.15, -- "Full" skirts end this far above the ground
	FENDER_THICKNESS_M = 0.03,
	FENDER_LIFT_M = 0.04, -- fender above the track top

	--------------------------------------------------------------------------------------------------------------
	-- Turret and gun
	--------------------------------------------------------------------------------------------------------------
	--- Default face slopes per turret style (deg from vertical) when TurretVisual omits them: { front, side, rear }.
	TURRET_DEFAULT_ANGLES = {
		Box = { 10, 8, 5 },
		Welded = { 15, 10, 5 },
		Cast = { 25, 18, 15 },
		Wedge = { 60, 25, 15 },
		Hexagonal = { 15, 12, 10 },
		Dome = { 20, 20, 20 },
		FacetedDome = { 20, 15, 15 },
		Oscillating = { 15, 10, 10 },
		Casemate = { 5, 5, 0 },
		Open = { 10, 8, 5 },
	},
	TURRET_CHAMFER_DEG = 55, -- top chamfer band of Welded / Cast / FacetedDome
	DOME_BAND_DEG = { 45, 68 }, -- Dome: slopes of the upper two bands
	FACET_CORNER_FRACTION = 0.28, -- FacetedDome: corner cut (plan) as a share of the smaller half-extent
	HEX_POINT_FRACTION = 0.3, -- Hexagonal: share of the length taken by each pointed end
	HEX_NOSE_WIDTH_RATIO = 1.15, -- Hexagonal: flat nose width = mantlet width × this
	OPEN_WALL_THICKNESS_M = 0.06, -- Open style: visual wall thickness (the roof face is open: 0 mm)
	BUSTLE_HEIGHT_FRACTION = { 0.18, 0.92 }, -- bustle spans this share of the turret height
	CUPOLA_DIAMETER_M = 0.6,
	CUPOLA_HEIGHT_M = 0.22,
	TALL_CUPOLA_MUL = 1.7, -- tall_cupola hook
	RAISED_CUPOLA_MUL = 1.45, -- raised_cupola hook
	CUPOLA_OFFSET = { -0.24, 0.18 }, -- (x, z) as shares of turret (width, length): left-rear
	COLLAR_MIN_M = 0.04, -- ring collar drawn when the ring floats at least this far above the hull
	BASKET_MIN_RADIUS_M = 0.3, -- below this the turret crew sit in the turret body
	BASKET_OVERLAP_M = 0.32, -- basket top reaches this far into the turret body
	BASKET_FLOOR_M = 0.08, -- basket bottom above the hull floor
	OSCILLATING_SPLIT_FRACTION = 0.45, -- trunnion height / turret height
	OSCILLATING_EXTRA_DEG = 12, -- elevation margin over the gun arcs (mechanic bonuses) for the collar overlap
	TRUNNION_HEIGHT_FRACTION = 0.48, -- gun axis height / turret height
	CASEMATE_GUN_HEIGHT_FRACTION = 0.5, -- gun axis on the compartment front plate (share of its height)
	CASEMATE_PROTRUSION = 0.5, -- share of the housing length in front of the compartment plate
	BARREL_DIAMETER_PER_CALIBER = 2.2, -- default barrel outer diameter × calibre
	MIN_BARREL_DIAMETER_M = 0.06,
	BARREL_WALL_PER_CALIBER = 0.25, -- barrel spaced-armor thickness (mm) = calibre (mm) × this
	MANTLET_WIDTH_PER_CALIBER = 6, -- default mantlet width × calibre
	MANTLET_MIN_WIDTH_M = 0.3,
	MANTLET_HEIGHT_RATIO = { Box = 0.62, Rounded = 0.6, Pig = 0.7, Narrow = 1.25, Cast = 0.66 },
	MANTLET_WIDTH_RATIO = { Box = 1, Rounded = 1, Pig = 0.85, Narrow = 0.55, Cast = 1.05 },
	MANTLET_DEPTH_M = { 0.12, 0.38 }, -- clamp range; default = 0.3 × mantlet width
	MANTLET_BACK_RATIO = 0.6, -- depth reaching back into the turret face, × mantlet depth
	BRAKE_DIAMETER_RATIO = 1.45, -- muzzle brake / barrel diameter
	BRAKE_LENGTH_RATIO = 2.6, -- muzzle brake length / barrel diameter
	FUME_DIAMETER_RATIO = 1.6,
	FUME_POSITION = 0.6, -- bore evacuator centre at this share of the barrel length
	FUME_LENGTH_M = { 0.22, 0.6 }, -- clamp; default 0.12 × barrel length
	SLEEVE_DIAMETER_RATIO = 1.12,
	SLEEVE_BAND_M = 0.16,
	TWIN_BARREL_SPACING_RATIO = 2.4, -- DualGun / twin_mantlet: barrel centre spacing / barrel diameter
	BREECH_LENGTH_PER_CALIBER = 9, -- breech module length × calibre (m per m)
	BREECH_MIN_M = { 0.3, 0.25, 0.45 }, -- (width, height, length) floor

	--------------------------------------------------------------------------------------------------------------
	-- Internal layout presets: boxes in normalized hull coordinates u (0 front .. 1 rear), v (-1 left .. 1 right,
	-- of the hull half-width), w (0 floor .. 1 roof), each { min, max }. Turret presets use the turret's own extents.
	--------------------------------------------------------------------------------------------------------------
	LAYOUT = {
		engine = {
			Rear = { u = { 0.73, 0.96 }, v = { -0.68, 0.68 }, w = { 0.08, 0.78 } },
			Front = { u = { 0.04, 0.27 }, v = { -0.1, 0.8 }, w = { 0.08, 0.78 } },
			Middle = { u = { 0.42, 0.62 }, v = { -0.6, 0.6 }, w = { 0.06, 0.62 } },
		},
		transmission = {
			Front = { u = { 0.03, 0.15 }, v = { -0.72, 0.72 }, w = { 0.06, 0.42 } },
			Rear = { u = { 0.93, 0.985 }, v = { -0.72, 0.72 }, w = { 0.06, 0.42 } },
		},
		fuel = {
			Rear = { u = { 0.74, 0.95 }, v = { 0.74, 0.95 }, w = { 0.12, 0.72 }, mirror = true },
			Front = { u = { 0.06, 0.26 }, v = { 0.38, 0.9 }, w = { 0.1, 0.62 } },
			Sides = { u = { 0.3, 0.64 }, v = { 0.8, 0.96 }, w = { 0.16, 0.86 }, mirror = true },
			Middle = { u = { 0.4, 0.6 }, v = { -0.55, 0.55 }, w = { 0.03, 0.18 } },
		},
		ammo = {
			HullFront = { u = { 0.08, 0.3 }, v = { 0.35, 0.9 }, w = { 0.08, 0.7 } },
			HullMiddle = { u = { 0.36, 0.62 }, v = { 0.66, 0.92 }, w = { 0.06, 0.6 }, mirror = true },
			Sponsons = { u = { 0.2, 0.64 }, v = { 0.82, 0.97 }, w = { 0.45, 0.9 }, mirror = true },
			Floor = { u = { 0.28, 0.6 }, v = { -0.6, 0.6 }, w = { 0.02, 0.16 } },
		},
		--- Turret racks in the turret's own normalized box (u front..rear, v left..right, w ring..roof).
		turretAmmo = { u = { 0.6, 0.92 }, v = { 0.55, 0.9 }, w = { 0.15, 0.75 }, mirror = true },
		bustleAmmo = { u = { 0.08, 0.9 }, v = { -0.85, 0.85 }, w = { 0.12, 0.85 } },
		hullOptics = { u = { 0.1, 0.2 }, v = { -0.75, -0.35 }, w = { 0.84, 0.96 } },
		turretOptics = { u = { 0.18, 0.32 }, v = { -0.7, -0.35 }, w = { 0.78, 0.94 } },
		ring = { height = 0.12, depth = 0.04 }, -- turret-ring module: slab under the ring plane (m)
	},
	--- Crew seat box (m) and preset placements (normalized as above; Turret group seats use the basket / turret).
	CREW_SEAT_M = { 0.48, 0.82, 0.5 }, -- (width, height, length)
	CREW_SEATS = {
		Driver = { u = 0.18, v = -0.5 },
		hullGunner = { u = 0.2, v = 0.5 }, -- casemate gunner beside the driver
		hullCommander = { u = 0.4, v = -0.45 },
		hullLoader = { u = 0.44, v = 0.45 },
		hullLoader2 = { u = 0.6, v = 0 },
		-- turret seats: (x share of basket radius, z share): commander left-rear, gunner left-front, loader right
		turretCommander = { x = -0.45, z = 0.35 },
		turretGunner = { x = -0.45, z = -0.4 },
		turretLoader = { x = 0.48, z = 0 },
		turretLoader2 = { x = 0.45, z = 0.48 },
	},

	--------------------------------------------------------------------------------------------------------------
	-- Details (DetailVisual + engine visual) and hooks
	--------------------------------------------------------------------------------------------------------------
	EXHAUST_DIAMETER_M = 0.14,
	EXHAUST_LENGTH_M = 0.32,
	ANTENNA_LENGTH_M = 1.6,
	ANTENNA_DIAMETER_M = 0.025,
	TOOLBOX_M = { 0.55, 0.2, 0.25 },
	JERRYCAN_M = { 0.17, 0.34, 0.25 },
	FUEL_DRUM_DIAMETER_M = 0.44,
	FUEL_DRUM_LENGTH_M = 0.68,
	HEADLIGHT_DIAMETER_M = 0.16,
	SMOKE_DISCHARGER_M = { 0.07, 0.24 }, -- (diameter, length), three per side
	SPARE_LINK_M = { 0.38, 0.05, 0.16 }, -- (width, thickness, length) of one spare track link
	RIVET_DIAMETER_M = 0.04,
	RIVET_SPACING_M = 0.22,
	MAX_RIVETS = 64,
	TOW_CABLE_DIAMETER_M = 0.035,
	LOG_DIAMETER_M = 0.18,
	MG_LENGTH_M = 0.7,
	LOUVRE_SLATS = 5,
	STOWAGE_M = { 0.9, 0.22, 0.4 },
	CAMO_NET_DIAMETER_M = 0.26,

	--------------------------------------------------------------------------------------------------------------
	-- Palette and materials
	--------------------------------------------------------------------------------------------------------------
	DEFAULT_PAINT = {
		Base = Color3.fromRGB(91, 96, 82),
		Secondary = Color3.fromRGB(89, 97, 106),
		Accent = Color3.fromRGB(184, 73, 42),
	},
	FIXED_SLOTS = {
		Metal = Color3.fromRGB(74, 79, 85),
		Rubber = Color3.fromRGB(30, 30, 31),
		Dark = Color3.fromRGB(42, 43, 45),
		Glass = Color3.fromRGB(159, 196, 217),
		Light = Color3.fromRGB(244, 227, 177),
	},
	--- Material per role (Enum.Material names). Glass falls back to SmoothPlastic when a Neon glow part would
	--- make a fifth material.
	MATERIALS = {
		Paint = "SmoothPlastic",
		Metal = "Metal",
		Track = "DiamondPlate",
		Glass = "Glass",
		Glow = "Neon",
	},
}

return Freeze.deep(BlueprintConfig)
