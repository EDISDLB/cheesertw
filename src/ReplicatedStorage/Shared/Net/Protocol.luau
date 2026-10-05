--!strict
--[[
	Protocol — wire-level constants shared by server and client.

	Purpose:          Version numbers for the Hello handshake, instance/attribute names and payload limits.
	Dependencies:     None.
	State:            Frozen constants.
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: Constant lookups.

	Bump PROTOCOL_VERSION whenever a remote's arguments or a binary codec layout changes incompatibly; the server
	rejects clients whose protocol differs (they are told to rejoin).
]]

local Protocol = table.freeze({
	PROTOCOL_VERSION = 1,
	GAME_VERSION = "0.1.0",
	--- Folder created by NetServer under ReplicatedStorage.
	REMOTES_FOLDER = "Remotes",
	--- Max UnreliableRemoteEvent payload we allow ourselves (Roblox limit is ~1000 bytes).
	MAX_UNRELIABLE_BYTES = 900,
	--- Attributes on the LocalPlayer used to talk to the ReplicatedFirst loading screen.
	ATTR_CLIENT_READY = "HulldownClientReady",
	ATTR_LOADING_STATUS = "HulldownLoadingStatus",
	--- Default client invoke timeout (seconds).
	INVOKE_TIMEOUT = 10,
	--- Default C2S rate when a registry entry omits `rate`.
	DEFAULT_RATE = table.freeze({ perSecond = 10, burst = 20 }),
})

return Protocol
