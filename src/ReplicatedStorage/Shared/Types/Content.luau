--!strict
--[[
	Types/Content — content definition types (vehicles, modules, shells, maps, missions...).

	Purpose:          PLACEHOLDER owned by the Content/Combat teams; extend in place and re-export from Types/init.
	Dependencies:     None yet.
	State:            None (type-only).
	Validation:       N/A (ContentRegistry validates data).
	Error handling:   N/A.
	Performance notes: Erased at runtime.
]]

-- TODO(content-team): replace these minimal aliases with full definitions (VehicleDefinition, GunDefinition,
-- ShellDefinition, MapDefinition, ...). Keep ids as strings so they serialize cleanly.
export type ContentId = string
export type FactionId = string
export type VehicleId = string
export type VehicleClass = "LT" | "MT" | "HT" | "TD" | "SPG"
export type Tier = number

return {}
