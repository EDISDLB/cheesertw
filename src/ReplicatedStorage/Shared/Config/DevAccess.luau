--!strict
--[[
	Config/DevAccess — who may use developer tools (DebugCommand remote, debug UI) outside Studio.

	Purpose:          Allow-list of user ids plus an optional group rank threshold (ARCHITECTURE §12).
	Dependencies:     None.
	State:            Constants.
	Validation:       isAllowed treats missing group rank as 0.
	Error handling:   N/A.
	Performance notes: O(#USER_IDS) lookup; called once per player join.

	Studio sessions are always allowed (local testing); live servers require the allow-list or group rank.
]]

local DevAccess = {
	--- Roblox user ids allowed to use developer tools on live servers.
	USER_IDS = {} :: { number },
	--- Group whose members at or above MIN_GROUP_RANK are developers (0 = disabled).
	GROUP_ID = 0,
	MIN_GROUP_RANK = 254,
}

--- True when a user may access developer tools. `groupRank` is the user's rank in DevAccess.GROUP_ID (if known).
function DevAccess.isAllowed(userId: number, groupRank: number?, isStudio: boolean): boolean
	if isStudio then
		return true
	end
	if table.find(DevAccess.USER_IDS, userId) ~= nil then
		return true
	end
	if DevAccess.GROUP_ID ~= 0 and groupRank ~= nil and groupRank >= DevAccess.MIN_GROUP_RANK then
		return true
	end
	return false
end

return DevAccess
