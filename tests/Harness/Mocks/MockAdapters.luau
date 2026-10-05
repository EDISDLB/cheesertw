--[[
	MockAdapters — one-call construction of a full Types.Adapters bundle of mocks for integration tests.

	Purpose:          `local adapters = MockAdapters.new({ clock = clock })` -> players, dataStore, memoryStore,
	                  messaging, teleport, marketplace (+ optional world).
	Dependencies:     Mock*Adapter modules, Harness/FakeClock.
	State:            None beyond the created mocks.
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: Test-only.
]]

local FakeClock = require("../FakeClock")
local MockPlayersAdapter = require("./MockPlayersAdapter")
local MockDataStoreAdapter = require("./MockDataStoreAdapter")
local MockMemoryStoreAdapter = require("./MockMemoryStoreAdapter")
local MockMessagingAdapter = require("./MockMessagingAdapter")
local MockTeleportAdapter = require("./MockTeleportAdapter")
local MockMarketplaceAdapter = require("./MockMarketplaceAdapter")

local MockAdapters = {}

export type Options = { clock: any?, bus: any?, world: any?, playersService: any? }

function MockAdapters.new(options: Options?)
	local opts = options or {}
	local clock = opts.clock or FakeClock.new(1.7e9)
	return {
		players = MockPlayersAdapter.new(opts.playersService),
		dataStore = MockDataStoreAdapter.new({ clock = clock }),
		memoryStore = MockMemoryStoreAdapter.new({ clock = clock }),
		messaging = MockMessagingAdapter.new({ bus = opts.bus }),
		teleport = MockTeleportAdapter.new(),
		marketplace = MockMarketplaceAdapter.new(),
		world = opts.world,
	}
end

return MockAdapters
