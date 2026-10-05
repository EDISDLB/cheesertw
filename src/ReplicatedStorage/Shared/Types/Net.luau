--!strict
--[[
	Types/Net — remote registry entries, protocol payloads and the NetServer/NetClient interfaces.

	Purpose:          Shapes shared by Net/Remotes, NetServer (server), NetClient (client) and their tests.
	Dependencies:     Types/Core (Validator, Result, Connection).
	State:            None (type-only).
	Validation:       N/A (Remotes.luau validates registry entries at load).
	Error handling:   N/A.
	Performance notes: Erased at runtime.
]]

local CoreTypes = require("./Core")

type Validator = CoreTypes.Validator
type Result<T> = CoreTypes.Result<T>
type Connection = CoreTypes.Connection

export type RemoteKind = "Event" | "Unreliable" | "Function"
export type RemoteDirection = "C2S" | "S2C"

--- Token bucket: `burst` tokens max, refilled at `perSecond`. One call costs one token.
export type RateSpec = { perSecond: number, burst: number }

export type RemoteSpec = {
	name: string,
	kind: RemoteKind,
	direction: RemoteDirection,
	rate: RateSpec?,
	args: { Validator }?,
	devOnly: boolean?,
	description: string?,
}

--- Violation reasons reported to the violation handler (AntiExploitService:strike).
export type ViolationReason = "RATE_LIMITED" | "INVALID_ARGS" | "NOT_ALLOWED" | "PROTOCOL_VIOLATION"
export type ViolationHandler = (player: Player, reason: ViolationReason, weight: number, detail: string?) -> ()

export type EventHandler = (player: Player, ...any) -> ()
export type InvokeHandler = (player: Player, ...any) -> Result<any>

export type NetServer = {
	--- Handles a C2S Event/Unreliable remote (one handler per remote). Handler errors are caught and logged.
	on: (self: NetServer, name: string, handler: EventHandler) -> Connection,
	--- Handles a C2S Function remote; the handler must return a Result (errors become Err INTERNAL).
	onInvoke: (self: NetServer, name: string, handler: InvokeHandler) -> Connection,
	fire: (self: NetServer, name: string, player: Player, ...any) -> (),
	fireAll: (self: NetServer, name: string, ...any) -> (),
	fireList: (self: NetServer, name: string, players: { Player }, ...any) -> (),
	setViolationHandler: (self: NetServer, handler: ViolationHandler?) -> (),
	setDeveloperCheck: (self: NetServer, check: (player: Player) -> boolean) -> (),
	--- Current developer check result for `player` (false if the check errors).
	isDeveloper: (self: NetServer, player: Player) -> boolean,
	getRemote: (self: NetServer, name: string) -> Instance?,
	forgetPlayer: (self: NetServer, player: Player) -> (),
	destroy: (self: NetServer) -> (),
}

export type NetClient = {
	waitForRemotes: (self: NetClient, timeout: number?) -> boolean,
	fire: (self: NetClient, name: string, ...any) -> (),
	invoke: (self: NetClient, name: string, ...any) -> Result<any>,
	invokeWithTimeout: (self: NetClient, name: string, timeout: number, ...any) -> Result<any>,
	on: (self: NetClient, name: string, handler: (...any) -> ()) -> Connection,
	destroy: (self: NetClient) -> (),
}

--- Payloads of the foundation remotes.
export type HelloRequest = { clientVersion: string, protocol: number }
export type HelloResponse = {
	role: CoreTypes.ServerRole,
	version: string,
	protocol: number,
	serverTime: number,
	healthy: boolean,
	isDeveloper: boolean,
}
export type ServerNoticeKind = "Info" | "Warning" | "Shutdown"
export type ServerNotice = { kind: ServerNoticeKind, message: string, at: number }

return {}
