--!strict
--[[
	Types/Profile — persistent player profile shapes.

	Purpose:          PLACEHOLDER owned by the Services/Progression team; extend in place and re-export from Types/init.
	Dependencies:     None yet.
	State:            None (type-only).
	Validation:       N/A (ProfileSchema validates data).
	Error handling:   N/A.
	Performance notes: Erased at runtime.
]]

-- TODO(services-team): Profile v1 (currencies, vehicles, research, crew, missions, processed rings...) — §7.
export type UserId = number
export type ProfileVersion = number
export type Currency = "credits" | "gold" | "freeXp"

return {}
