--!strict
--[[
	Config/Places — PlaceId -> server role mapping (ARCHITECTURE §2.1).

	Purpose:          One build is published to every place; the server bootstrap resolves its role from PlaceId.
	Dependencies:     Types/Core (ServerRole).
	State:            Constant place ids (0 = not yet published; filled in by the release owner).
	Validation:       0 ids are ignored when building the lookup (PlaceId 0 is an unpublished Studio place).
	Error handling:   Unknown places resolve to "Dev" (never fail boot).
	Performance notes: Lookup table built once.

	Roles: "Hub" (public garage servers), "Battle" (reserved battle servers), "Dev" (Studio or any unmapped place:
	hub + in-process battle host + debug tools for developers).
]]

local CoreTypes = require("../Types/Core")

export type ServerRole = CoreTypes.ServerRole

local Places = {
	--- Published place ids. Replace the 0 placeholders when the universe is created.
	HUB_PLACE_ID = 0,
	BATTLE_PLACE_ID = 0,
	--- Optional dedicated test place that should behave like Dev even when published.
	DEV_PLACE_ID = 0,
	ROLES = { "Hub", "Battle", "Dev" } :: { ServerRole },
}

local function buildLookup(): { [number]: ServerRole }
	local lookup: { [number]: ServerRole } = {}
	if Places.HUB_PLACE_ID ~= 0 then
		lookup[Places.HUB_PLACE_ID] = "Hub"
	end
	if Places.BATTLE_PLACE_ID ~= 0 then
		lookup[Places.BATTLE_PLACE_ID] = "Battle"
	end
	if Places.DEV_PLACE_ID ~= 0 then
		lookup[Places.DEV_PLACE_ID] = "Dev"
	end
	return lookup
end

local lookup = buildLookup()

--- Role for this server. Studio is always "Dev"; unmapped place ids are "Dev".
function Places.resolveRole(placeId: number, isStudio: boolean): ServerRole
	if isStudio then
		return "Dev"
	end
	return lookup[placeId] or "Dev"
end

--- Place id hosting `role` (0 when unpublished; Dev has no dedicated place unless DEV_PLACE_ID is set).
function Places.placeIdFor(role: ServerRole): number
	if role == "Hub" then
		return Places.HUB_PLACE_ID
	elseif role == "Battle" then
		return Places.BATTLE_PLACE_ID
	end
	return Places.DEV_PLACE_ID
end

return Places
