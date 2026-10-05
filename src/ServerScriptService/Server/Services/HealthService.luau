--!strict
--[[
	HealthService — role-agnostic server health, the Hello handshake and server-wide notices.

	Purpose:          Tracks service lifecycle failures (via ctx.lifecycle), exposes getStatus() for tooling/debug
	                  commands, answers the client "Hello" handshake (role, versions, health, developer flag) and
	                  broadcasts "ServerNotice" (including a shutdown notice on Stop).
	Dependencies:     ctx.net (NetServer), ctx.lifecycle, ctx.clock; Net/Protocol, Net/ErrorCodes, Core/Result.
	State:            Boot time, ready flag (set in Start), failure log (bounded to MAX_FAILURES entries).
	Validation:       Hello arguments are schema-validated by NetServer; protocol mismatches are rejected with
	                  VERSION_MISMATCH.
	Error handling:   Hello answers NOT_READY until Start has run (all services initialized). Never throws.
	Performance notes: O(services) status snapshot; Hello is rate-limited by the registry (1/s, burst 5).
]]

local Types = require("@game/ReplicatedStorage/Shared/Types")
local Protocol = require("@game/ReplicatedStorage/Shared/Net/Protocol")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")

type ServiceContext = Types.ServiceContext

export type FailureRecord = { service: string, phase: Types.LifecyclePhase, err: string, at: number }
export type HealthStatus = {
	healthy: boolean,
	ready: boolean,
	role: Types.ServerRole,
	uptime: number,
	failures: { FailureRecord },
	services: { Types.ServiceStatusInfo },
}

local MAX_FAILURES = 50

local HealthService = {
	Name = "HealthService",
	Roles = { "Hub", "Battle", "Dev" },
	Dependencies = {},
	_ctx = (nil :: any) :: ServiceContext,
	_bootedAt = 0,
	_ready = false,
	_failures = {} :: { FailureRecord },
	_connections = {} :: { Types.Connection },
}

local function recordFailure(service: string, phase: Types.LifecyclePhase, err: string)
	local failures = HealthService._failures
	table.insert(failures, { service = service, phase = phase, err = err, at = HealthService._ctx.clock:now() })
	if #failures > MAX_FAILURES then
		table.remove(failures, 1)
	end
end

local function hello(player: Player, request: Types.HelloRequest): Types.Result<Types.HelloResponse>
	local ctx = HealthService._ctx
	if not HealthService._ready then
		return Result.err(ErrorCodes.NOT_READY, "server is starting")
	end
	if request.protocol ~= Protocol.PROTOCOL_VERSION then
		return Result.err(
			ErrorCodes.VERSION_MISMATCH,
			`server protocol {Protocol.PROTOCOL_VERSION}, client protocol {request.protocol}`
		)
	end
	return Result.ok({
		role = ctx.role,
		version = Protocol.GAME_VERSION,
		protocol = Protocol.PROTOCOL_VERSION,
		serverTime = ctx.clock:now(),
		healthy = HealthService:isHealthy(),
		isDeveloper = ctx.net:isDeveloper(player),
	})
end

function HealthService.Init(self: typeof(HealthService), ctx: ServiceContext)
	self._ctx = ctx
	self._bootedAt = ctx.clock:now()
	self._ready = false
	self._failures = {}
	self._connections = {}
	-- Failures that happened before this Init (earlier in the boot order) are already in lifecycle statuses.
	for _, info in ctx.lifecycle.getStatuses() do
		if info.status == "Failed" and info.phase ~= nil then
			recordFailure(info.name, info.phase, info.err or "unknown error")
		end
	end
	table.insert(self._connections, ctx.lifecycle.ServiceFailed:Connect(recordFailure))
	table.insert(
		self._connections,
		ctx.net:onInvoke("Hello", function(player: Player, request: any): Types.Result<any>
			return hello(player, request)
		end)
	)
end

function HealthService.Start(self: typeof(HealthService))
	self._ready = true
	self._ctx.log:info(
		"server ready (role %s, %d services, healthy=%s)",
		self._ctx.role,
		#self._ctx.lifecycle.getOrder(),
		tostring(self:isHealthy())
	)
end

function HealthService.Stop(self: typeof(HealthService))
	self._ready = false
	self:notify("Shutdown", "This server is restarting. Please rejoin in a moment.")
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

--- True when no service has failed since boot.
function HealthService.isHealthy(self: typeof(HealthService)): boolean
	return #self._failures == 0
end

function HealthService.isReady(self: typeof(HealthService)): boolean
	return self._ready
end

--- Snapshot for tooling, debug commands and tests.
function HealthService.getStatus(self: typeof(HealthService)): HealthStatus
	local ctx = self._ctx
	return {
		healthy = self:isHealthy(),
		ready = self._ready,
		role = ctx.role,
		uptime = ctx.clock:now() - self._bootedAt,
		failures = table.clone(self._failures),
		services = ctx.lifecycle.getStatuses(),
	}
end

--- Broadcasts a ServerNotice to every player (or only `players` when given).
function HealthService.notify(
	self: typeof(HealthService),
	kind: Types.ServerNoticeKind,
	message: string,
	players: { Player }?
)
	local notice: Types.ServerNotice = { kind = kind, message = message, at = self._ctx.clock:now() }
	if players ~= nil then
		self._ctx.net:fireList("ServerNotice", players, notice)
	else
		self._ctx.net:fireAll("ServerNotice", notice)
	end
end

return HealthService
