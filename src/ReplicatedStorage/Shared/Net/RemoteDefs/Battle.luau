--!strict
--[[
	RemoteDefs/Battle — remote specs owned by the battle runtime: inputs, discrete actions, the loading handshake,
	leave/spectate, snapshots, reliable events, battle state and the end banner (docs/systems/battle-protocol.md).

	Purpose:          Declares this domain's remotes; aggregated and validated by Net/Remotes.
	Dependencies:     Types/Net, Core/Schema, Net/Codecs/Battle/{InputCodec, Actions, Messages, Chunker, EventCodec}.
	State:            None (returns a list of specs).
	Validation:       Net/Remotes validates every spec at load (unique names, kinds, directions, args, rates).
	                  Every C2S remote has a tight token bucket (00-DECISIONS §19) and strict validators: BattleInput
	                  checks the exact binary layout, BattleAction dispatches on `kind` to strict structs. S2C specs
	                  carry validators too (not enforced by NetClient; used by tests and defensive clients).
	Error handling:   Malformed specs make require() fail loudly (programming mistake).
	Performance notes: Loaded once.

	No C2S argument carries damage, HP, hit results, rewards, currency, XP or vehicle positions (REG-NET-03); the only
	world points a client sends are the bounded aim point (BattleInput) and 2-D map designations (BattleAction).
]]

local NetTypes = require("../../Types/Net")
local Schema = require("../../Core/Schema")
local InputCodec = require("../Codecs/Battle/InputCodec")
local Actions = require("../Codecs/Battle/Actions")
local Messages = require("../Codecs/Battle/Messages")
local Chunker = require("../Codecs/Battle/Chunker")
local EventCodec = require("../Codecs/Battle/EventCodec")

type RemoteSpec = NetTypes.RemoteSpec

local specs: { RemoteSpec } = {
	-- Client -> server ------------------------------------------------------------------------------------------
	{
		name = "BattleInput",
		kind = "Unreliable",
		direction = "C2S",
		description = "30 Hz input packet: buffer = tick + newest 3 InputCommands (InputCodec, <= 40 bytes).",
		-- 00-DECISIONS §19: InputPacket 40/s, burst 60 (30 Hz plus jitter bursts after a hitch).
		rate = { perSecond = 40, burst = 60 },
		args = { InputCodec.validate },
	},
	{
		name = "BattleAction",
		kind = "Event",
		direction = "C2S",
		description = "Discrete action { kind = Fire|SwitchShell|UseConsumable|ActivateMechanic|QuickCommand|MapPing }; "
			.. "per-action buckets via Actions.admit.",
		rate = Actions.REMOTE_RATE,
		args = { Actions.validate },
	},
	{
		name = "BattleReady",
		kind = "Function",
		direction = "C2S",
		description = "Client finished loading: { protocol, contentHash } -> Result<BattleBootstrap>. Idempotent.",
		rate = { perSecond = 1, burst = 3 },
		args = { Messages.READY_REQUEST },
	},
	{
		name = "BattleLeave",
		kind = "Function",
		direction = "C2S",
		description = "Leave the battle (alive: bot takes over + strike; destroyed: back to the Hub): { requestId } -> Result.",
		rate = { perSecond = 1, burst = 2 },
		args = { Messages.LEAVE_REQUEST },
	},
	{
		name = "BattleSpectate",
		kind = "Event",
		direction = "C2S",
		description = "Destroyed players pick the ally to follow: { targetId? } (nil = next).",
		rate = { perSecond = 1, burst = 3 },
		args = { Messages.SPECTATE_REQUEST },
	},
	-- Server -> client ------------------------------------------------------------------------------------------
	{
		name = "BattleSnapshot",
		kind = "Unreliable",
		direction = "S2C",
		description = "20 Hz per-observer snapshot chunk (SnapshotCodec over Chunker, <= 900 bytes each).",
		args = { Schema.buffer({ minLen = Chunker.HEADER_BYTES + 1, maxLen = Chunker.MAX_PACKET_BYTES }) },
	},
	{
		name = "BattleEvents",
		kind = "Event",
		direction = "S2C",
		description = "Batched reliable battle events for one observer (EventCodec, <= 2048 bytes per batch).",
		args = { Schema.buffer({ minLen = EventCodec.HEADER_BYTES + 2, maxLen = EventCodec.MAX_BATCH_BYTES }) },
	},
	{
		name = "BattleState",
		kind = "Event",
		direction = "S2C",
		description = "Phase, timers, team scores, capture bases and (when changed) the roster: BattleStateMessage.",
		args = { Messages.STATE_MESSAGE },
	},
	{
		name = "BattleResults",
		kind = "Event",
		direction = "S2C",
		description = "End-of-battle banner: BattleResultsMessage (full results arrive in the Hub).",
		args = { Messages.RESULTS_MESSAGE },
	},
}

return specs
