--!strict
--[[
	RemoteDefs/Foundation — remote specs owned by the foundation layer (handshake, notices, developer console).

	Purpose:          Declares this domain's remotes; aggregated and validated by Net/Remotes.
	Dependencies:     Types/Net, Core/Schema.
	State:            None (returns a list of specs).
	Validation:       Net/Remotes validates every spec at load (unique names, kinds, directions, args, rates).
	Error handling:   Malformed specs make require() fail loudly (programming mistake).
	Performance notes: Loaded once.
]]

local NetTypes = require("../../Types/Net")
local Schema = require("../../Core/Schema")

type RemoteSpec = NetTypes.RemoteSpec

local specs: { RemoteSpec } = {
	{
		name = "Hello",
		kind = "Function",
		direction = "C2S",
		description = "Client handshake: returns HelloResponse (server role, versions, health, dev flag).",
		rate = { perSecond = 1, burst = 5 },
		args = {
			Schema.struct({
				clientVersion = Schema.string({ maxLen = 32 }),
				protocol = Schema.number({ integer = true, min = 0, max = 65535 }),
			}),
		},
	},
	{
		name = "ServerNotice",
		kind = "Event",
		direction = "S2C",
		description = "Server-wide notices (info, warnings, shutdown) as ServerNotice payloads.",
	},
	{
		name = "DebugCommand",
		kind = "Function",
		direction = "C2S",
		devOnly = true,
		description = "Developer console command: (command, args?) -> Result<string>. Rejected for non-developers.",
		rate = { perSecond = 5, burst = 10 },
		args = {
			Schema.string({ minLen = 1, maxLen = 64, pattern = "^[%w_%.%-]+$" }),
			Schema.optional(
				Schema.array(
					Schema.oneOf(Schema.string({ maxLen = 200 }), Schema.number(), Schema.boolean),
					{ maxLen = 16 }
				)
			),
		},
	},
}

return specs
