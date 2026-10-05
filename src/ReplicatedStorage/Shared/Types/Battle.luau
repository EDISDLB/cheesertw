--!strict
--[[
	Types/Battle — battle entities, packets and results.

	Purpose:          PLACEHOLDER owned by the Combat/Battle team; extend in place and re-export from Types/init.
	Dependencies:     None yet.
	State:            None (type-only).
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: Erased at runtime.
]]

-- TODO(combat-team): VehicleEntity, InputCommand, SnapshotPacket, ShotResult, BattleLedger, ... (ARCHITECTURE §6).
export type BattleId = string
export type EntityId = number
export type TeamId = number
export type BattleMode = "Random" | "Training" | "Bootcamp" | "Practice" | "Event"

return {}
