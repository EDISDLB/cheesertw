--!strict
--[[
	Vehicle/Blueprint/Types — the Blueprint contract: render primitives, LOD tiers, palette slots and part counts
	produced by Blueprint.build (ARCHITECTURE §6.3), plus the minimal registry adapter the builder reads.

	Purpose:          Shared shape of a procedural vehicle blueprint for its consumers: the server (ArmorModel only),
	                  the client VehicleRenderer (primitives + LOD lists + palette), the Armor Inspector (Armor and
	                  Module layers) and QA tools (surface samplers, part counts).
	Dependencies:     Types/Content, Types/Vehicle (type-only).
	State:            None (type-only).
	Validation:       Producers (Blueprint/*) guarantee the invariants documented per field.
	Error handling:   N/A.
	Performance notes: Erased at runtime.

	Spaces (studs, Types/Vehicle conventions): a primitive's `cframe` is in the space of its `group`:
	  Hull, TrackL, TrackR, WheelsL, WheelsR -> hull space (origin = footprint centre at ground level, -Z forward)
	  Turret -> turret space (origin = turret-ring centre at the ring plane; casemates: the fixed gun-mount frame)
	  Gun    -> gun space (origin = trunnion, -Z = barrel at elevation 0)
	The renderer welds TrackL/TrackR/WheelsL/WheelsR parts to the hull root; they are separate groups only so tracks
	can scroll and wheels can spin.

	Shapes follow Roblox part geometry in the primitive's local frame (half sizes hx, hy, hz):
	  Block       = the box.
	  Wedge       = WedgePart: right angle along the bottom-back edge (y = -hy, z = +hz); the slope runs from the
	                bottom-front edge (y = -hy, z = -hz) to the top-back edge (y = +hy, z = +hz).
	  CornerWedge = CornerWedgePart: square pyramid with its apex at (+hx, +hy, -hz) above the base corner
	                (+hx, -hy, -hz); vertical faces x = +hx and z = -hz. (Convention to verify in engine: see
	                docs/design/vehicle-visuals.md §9.)
	  Cylinder    = Part.Shape Cylinder: axis = local X (length size.X), diameter = min(size.Y, size.Z).
	  Ball        = Part.Shape Ball: diameter = min(size).
]]

local Content = require("../../Types/Content")
local Vehicle = require("../../Types/Vehicle")

export type PrimitiveShape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"
export type PrimitiveGroup = "Hull" | "Turret" | "Gun" | "TrackL" | "TrackR" | "WheelsL" | "WheelsR"
--- Armor  = exact tiling of an Armor / Layered / Spaced volume (`volumeId`): what you see is what Combat hits.
--- Module = inspector X-ray geometry of a Module / Crew volume (never rendered in a LOD tier).
--- Visual = silhouette parts that are not a tiling (wheels, track belts, fenders, hooks); with `volumeId` they lie
---          inside that volume, without it they are unarmored attachments shells pass through.
--- Detail = small LOD0 decoration (tools, rivets, lights, antennas); never armor.
export type PrimitiveLayer = "Armor" | "Module" | "Visual" | "Detail"
export type ColorSlot = "Base" | "Secondary" | "Accent" | "Metal" | "Rubber" | "Dark" | "Glass" | "Light"

export type Primitive = {
	id: number, -- 1..n = index in Blueprint.primitives (stable for a given vehicle + configuration)
	shape: PrimitiveShape,
	size: Vector3, -- studs (Roblox Part.Size)
	cframe: CFrame, -- in the space of `group` (see header)
	group: PrimitiveGroup,
	layer: PrimitiveLayer,
	material: string, -- Enum.Material name ("SmoothPlastic", "Metal", "DiamondPlate", "Glass", "Neon")
	colorSlot: ColorSlot,
	--- LOD tiers that show the primitive: lodMin..lodMax (0 = full detail, 1 = medium, 2 = far). Module-layer
	--- primitives are inspector-only and appear in no tier.
	lodMin: number,
	lodMax: number,
	--- Budget priority inside a tier: 0 = essential silhouette (never dropped); higher numbers are dropped first
	--- when a tier exceeds its part budget.
	priority: number,
	tags: { string }, -- semantic tags: "hull", "glacis", "wheel", "track", "hook:<key>", "detail:<kind>", ...
	volumeId: number?, -- the ArmorVolume this primitive tiles (Armor/Module layers) or lies inside (Visual)
	zone: Content.ArmorZone?, -- Armor layer: zone of the volume face the primitive's outer face lies on
	thicknessMm: number?, -- Armor layer: nominal thickness of that face
	module: Content.InternalModuleKind?, -- Module layer (and external-module tilings: tracks, barrel)
	crewSlot: number?, -- Module layer, crew seats
}

export type LodTier = {
	tier: number, -- 0, 1, 2
	maxParts: number, -- 00-DECISIONS §18 budget (400 / 80 / 16)
	maxDistanceStuds: number, -- camera distance ÷ zoom up to which this tier is used (150 / 600 / 2400)
	primitives: { number }, -- ids of the primitives rendered in this tier (ascending)
}

export type PartCounts = {
	lod0: number,
	lod1: number,
	lod2: number,
	render: number, -- distinct render primitives (Armor + Visual + Detail layers)
	inspector: number, -- Module-layer primitives
	volumes: number, -- ArmorModel volumes
	byGroup: { [PrimitiveGroup]: number }, -- LOD0 parts per group
	byLayer: { [PrimitiveLayer]: number }, -- all primitives per layer
}

export type PaletteSlots = { [ColorSlot]: Color3 }

export type Blueprint = {
	vehicleId: string,
	configuration: Content.Configuration,
	key: string, -- "<vehicleId>|<gun>|<turret>|<engine>|<tracks>" (cache key)
	preset: string, -- shape grammar used (VisualSpec.preset or the faction builderPreset)
	casemate: boolean, -- the turret module is a Casemate gun mount (Turret group never yaws)
	primitives: { Primitive },
	armorModel: Vehicle.ArmorModel,
	pivots: Vehicle.VehiclePivots, -- same table as armorModel.pivots
	lod: { LodTier }, -- [1] = LOD0, [2] = LOD1, [3] = LOD2
	paletteSlots: PaletteSlots,
	materials: { string }, -- distinct render materials, sorted (<= Config MAX_MATERIALS)
	partCounts: PartCounts,
	hooks: { string }, -- hook keys that were drawn (unknown keys are ignored, 00 content-schema §6)
	warnings: { string }, -- clamps applied to impossible proportions (content still validates; see doc §7)
}

export type BuildOptions = {
	--- Skip Detail-layer primitives (server builds that only need the ArmorModel). Default false.
	skipDetails: boolean?,
	--- Bypass the memo cache (tests, tools that mutate fixtures). Default false.
	noCache: boolean?,
}

--- The registry reads Blueprint needs (ContentRegistry satisfies it). Methods are called with `:`.
export type BlueprintRegistry = {
	getGun: (self: any, id: string) -> Content.GunDefinition?,
	getTurret: (self: any, id: string) -> Content.TurretDefinition?,
	getEngine: (self: any, id: string) -> Content.EngineDefinition?,
	getTracks: (self: any, id: string) -> Content.TracksDefinition?,
	getFaction: (self: any, id: string) -> Content.FactionDefinition?,
}

return {}
