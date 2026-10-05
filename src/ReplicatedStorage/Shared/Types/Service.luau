--!strict
--[[
	Types/Service — server service / client controller module shapes and the context they receive.

	Purpose:          Contract between ServiceLoader, Server/Main, Client/Main and every service or controller.
	Dependencies:     Types/Core, Types/Net, Types/Adapters.
	State:            None (type-only).
	Validation:       ServiceLoader validates module shapes at register time.
	Error handling:   N/A.
	Performance notes: Erased at runtime.
]]

local CoreTypes = require("./Core")
local NetTypes = require("./Net")
local AdapterTypes = require("./Adapters")

type Logger = CoreTypes.Logger
type Clock = CoreTypes.Clock
type Signal<T...> = CoreTypes.Signal<T...>

export type ServerRole = CoreTypes.ServerRole

--- Lifecycle phases reported by ServiceLoader.ServiceFailed.
export type LifecyclePhase = "Init" | "Start" | "Stop"
export type ServiceStatus =
	"Registered"
	| "Skipped"
	| "Initialized"
	| "Starting"
	| "Started"
	| "Failed"
	| "Stopping"
	| "Stopped"

export type ServiceStatusInfo = {
	name: string,
	status: ServiceStatus,
	phase: LifecyclePhase?,
	err: string?,
	initMs: number?,
}

--- Read-only view of the loader handed to services (HealthService, DebugService).
export type Lifecycle = {
	ServiceFailed: Signal<string, LifecyclePhase, string>,
	getStatuses: () -> { ServiceStatusInfo },
	getOrder: () -> { string },
}

--- Identity of the running server (DataModel properties, injectable for tests).
export type ServerInfo = {
	placeId: number,
	gameId: number,
	jobId: string,
	privateServerId: string,
	privateServerOwnerId: number,
}

export type ServiceContext = {
	role: ServerRole,
	services: { [string]: any },
	net: NetTypes.NetServer,
	config: { [string]: any },
	log: Logger,
	clock: Clock,
	adapters: AdapterTypes.Adapters,
	isStudio: boolean,
	server: ServerInfo,
	lifecycle: Lifecycle,
}

--- Context handed to client controllers (same loader; `services` holds controllers).
export type ControllerContext = {
	role: ServerRole,
	services: { [string]: any },
	net: NetTypes.NetClient,
	config: { [string]: any },
	log: Logger,
	clock: Clock,
	isStudio: boolean,
	player: Player?,
	lifecycle: Lifecycle,
	--- The server's Hello handshake response (role, versions, health, developer flag).
	hello: NetTypes.HelloResponse,
}

--- A service/controller module. Roles nil = every role. Init must not yield; Start may; Stop is optional.
export type ServiceModule = {
	Name: string,
	Roles: { string }?,
	Dependencies: { string }?,
	Init: ((self: any, ctx: any) -> ())?,
	Start: ((self: any) -> ())?,
	Stop: ((self: any) -> ())?,
	[any]: any,
}

return {}
