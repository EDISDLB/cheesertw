--!strict
--[[
	RemoteDefs/Progression — remote specs owned by the progression/garage systems (research, purchases, loadout, crew, customization, missions, achievements).

	Purpose:          Declares this domain's remotes; aggregated and validated by Net/Remotes.
	Dependencies:     Types/Net (add Core/Schema when defining specs).
	State:            None (returns a list of specs).
	Validation:       Net/Remotes validates every spec at load (unique names, kinds, directions, args, rates).
	Error handling:   Malformed specs make require() fail loudly (programming mistake).
	Performance notes: Loaded once.
]]

local NetTypes = require("../../Types/Net")

type RemoteSpec = NetTypes.RemoteSpec

local specs: { RemoteSpec } = {}

return specs
