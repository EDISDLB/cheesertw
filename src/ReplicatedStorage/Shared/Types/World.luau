--!strict
--[[
	Types/World — the map query interface used by simulation (ARCHITECTURE §6.4).

	Purpose:          Shared simulation never touches Workspace; it queries a `World` (RobloxWorld on servers/clients,
	                  HeightmapWorld in headless tests).
	Dependencies:     None (type-only).
	State:            None.
	Validation:       N/A (types only). Implementations must return finite values and unit normals.
	Error handling:   N/A.
	Performance notes: Implementations are called from hot loops; they must not allocate per call beyond the result.

	Conventions (all implementations):
	  * Positions/directions are in studs. `raycast` direction is a displacement: its magnitude is the max distance.
	  * mode "Shell": map geometry incl. destructibles; "Sight": geometry that blocks vision (not foliage/smoke);
	    "Ground": terrain + solid static props, excluding destructibles (vehicles crush them).
	  * `WorldHit.distance` is measured from the query origin along the ray/sweep.
	  * `sightLine` sums the concealment of every foliage volume crossed before the first blocking hit.
	  * `waterDepthAt(p)` is how far `p` lies below the water surface at its x/z (0 when not in water).
	  * Geometry that contains a ray's origin is not hit (Roblox raycast semantics).
	  * `sweepBox` reports an initial overlap as a hit at distance 0 (RobloxWorld checks overlap first).
]]

export type RaycastMode = "Shell" | "Sight" | "Ground"

export type WorldHit = {
	position: Vector3,
	normal: Vector3,
	distance: number,
	material: string,
	objectId: string?,
	destructible: boolean,
}

export type SightResult = {
	blocked: boolean,
	foliage: number,
	smoke: boolean,
}

export type World = {
	raycast: (self: World, origin: Vector3, direction: Vector3, mode: RaycastMode) -> WorldHit?,
	groundAt: (self: World, x: number, z: number, fromY: number) -> WorldHit?,
	sweepBox: (self: World, cframe: CFrame, size: Vector3, displacement: Vector3) -> WorldHit?,
	sightLine: (self: World, from: Vector3, to: Vector3) -> SightResult,
	waterDepthAt: (self: World, position: Vector3) -> number,
	destroyObject: (self: World, objectId: string) -> (),
}

return {}
