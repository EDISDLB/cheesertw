--!strict
--[[
	ServiceLoader — dependency-ordered lifecycle for server services and client controllers.

	Purpose:          register(module) -> filter by role -> topological sort by Dependencies -> Init in order (must not
	                  yield) -> Start in order (each in its own thread) -> Stop in reverse order within a time budget.
	Dependencies:     Types/Service, Types/Core, Core/Signal, Core/Log, Core/Clock.
	State:            Registered modules, resolved order, per-service status/error/timing, ServiceFailed signal.
	Validation:       Module shape (Name string, optional Roles/Dependencies arrays, Init/Start/Stop functions),
	                  duplicate names, missing dependencies (with "registered but not enabled for role" hints),
	                  dependency cycles (reported as the full chain). These are boot errors (boot() throws).
	Error handling:   Init errors or yields mark the service Failed and Skip every service that depends on it
	                  (transitively); Start errors mark it Failed, also after Start yielded (a Start that yields,
	                  e.g. a long-running loop, is reported Started once it has begun). Each failure fires
	                  ServiceFailed(name, phase, err) and is logged. Stop errors/timeouts are reported in the stop()
	                  result. `failFast` rethrows Init failures instead (useful in tests).
	Performance notes: Boot-time only. No scheduler access: `spawn`, `cancel` and `wait` are injected
	                  (Main passes task.spawn/task.cancel/task.wait; tests pass deterministic fakes).

	Each service receives a shallow copy of the base context with `log` scoped to its Name and `services` (shared
	table, filled with every active module by name) and `lifecycle` (read-only loader view).
]]

local CoreTypes = require("../Types/Core")
local ServiceTypes = require("../Types/Service")
local Signal = require("./Signal")
local Log = require("./Log")
local Clock = require("./Clock")

type Clock = CoreTypes.Clock
type Logger = CoreTypes.Logger
type Signal<T...> = CoreTypes.Signal<T...>
export type ServiceModule = ServiceTypes.ServiceModule
export type ServiceStatus = ServiceTypes.ServiceStatus
export type ServiceStatusInfo = ServiceTypes.ServiceStatusInfo
export type LifecyclePhase = ServiceTypes.LifecyclePhase
export type Lifecycle = ServiceTypes.Lifecycle

export type LoaderOptions = {
	--- Active role; modules whose Roles do not include it are ignored. nil = accept every module.
	role: string?,
	--- Base context table; each module gets a shallow copy (see header).
	context: { [string]: any }?,
	--- Runs fn in a new thread (default: coroutine.create + resume).
	spawn: ((fn: () -> ()) -> thread)?,
	--- Cancels a suspended thread (default: coroutine.close).
	cancel: ((thread: thread) -> ())?,
	--- Yields the current thread for `seconds` (needed for stop() to wait on yielding Stop methods).
	wait: ((seconds: number) -> ())?,
	clock: Clock?,
	log: Logger?,
	--- Noun used in messages ("Service" / "Controller").
	kind: string?,
	--- Rethrow Init failures instead of degrading.
	failFast: boolean?,
}

export type StopReport = {
	stopped: { string },
	timedOut: { string },
	failed: { [string]: string },
	elapsed: number,
}

type Record = {
	module: ServiceModule,
	name: string,
	status: ServiceStatus,
	phase: LifecyclePhase?,
	err: string?,
	initMs: number?,
	active: boolean,
}

local STOPPABLE: { [string]: boolean } = { Initialized = true, Starting = true, Started = true }

local LoaderClass = {}
LoaderClass.__index = LoaderClass

type LoaderState = {
	_options: LoaderOptions,
	_records: { [string]: Record },
	_registrationOrder: { string },
	_order: { string }?,
	_kind: string,
	_log: Logger,
	_clock: Clock,
	_spawn: (fn: () -> ()) -> thread,
	_cancel: (thread: thread) -> (),
	_context: { [string]: any },
	_services: { [string]: any },
	_lifecycle: Lifecycle,
	_phase: "Idle" | "Initialized" | "Started" | "Stopped",
	ServiceFailed: Signal<string, LifecyclePhase, string>,
}

export type ServiceLoader = typeof(setmetatable({} :: LoaderState, LoaderClass))

local function defaultSpawn(fn: () -> ()): thread
	local thread = coroutine.create(fn)
	local ok, err = coroutine.resume(thread)
	if not ok then
		error(err, 0)
	end
	return thread
end

local function defaultCancel(thread: thread)
	if coroutine.status(thread) == "suspended" then
		coroutine.close(thread)
	end
end

local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function isStringArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local n = #value
	local count = 0
	for k, v in value do
		count += 1
		if type(k) ~= "number" or type(v) ~= "string" then
			return false
		end
	end
	return count == n
end

local ServiceLoader = {}

function ServiceLoader.new(options: LoaderOptions?): ServiceLoader
	local opts: LoaderOptions = options or {}
	local kind = opts.kind or "Service"
	local context: { [string]: any } = opts.context or {}
	local self: ServiceLoader = setmetatable(
		{
			_options = opts,
			_records = {},
			_registrationOrder = {},
			_order = nil,
			_kind = kind,
			_log = opts.log or Log.scope(kind .. "Loader"),
			_clock = opts.clock or Clock.real(),
			_spawn = opts.spawn or defaultSpawn,
			_cancel = opts.cancel or defaultCancel,
			_context = context,
			_services = {},
			_lifecycle = (nil :: any) :: Lifecycle,
			_phase = "Idle",
			ServiceFailed = Signal.new() :: Signal<string, LifecyclePhase, string>,
		} :: LoaderState,
		LoaderClass
	)
	self._lifecycle = table.freeze({
		ServiceFailed = self.ServiceFailed,
		getStatuses = function()
			return LoaderClass.getStatuses(self)
		end,
		getOrder = function()
			return table.clone(self._order or {})
		end,
	})
	local contextServices = context.services
	if type(contextServices) == "table" then
		self._services = contextServices
	end
	return self
end

--- Registers a module. Errors on malformed modules or duplicate names.
function LoaderClass.register(self: ServiceLoader, module: ServiceModule)
	if self._phase ~= "Idle" or self._order ~= nil then
		error(`{self._kind}Loader: cannot register after boot started`, 2)
	end
	if type(module) ~= "table" then
		error(`{self._kind}Loader: module must be a table, got {typeof(module)}`, 2)
	end
	local name = module.Name
	if type(name) ~= "string" or name == "" then
		error(`{self._kind}Loader: module is missing a string Name`, 2)
	end
	if self._records[name] ~= nil then
		error(`{self._kind}Loader: duplicate {self._kind} name "{name}"`, 2)
	end
	if module.Roles ~= nil and not isStringArray(module.Roles) then
		error(`{self._kind} {name}: Roles must be an array of strings`, 2)
	end
	if module.Dependencies ~= nil and not isStringArray(module.Dependencies) then
		error(`{self._kind} {name}: Dependencies must be an array of strings`, 2)
	end
	for _, method in { "Init", "Start", "Stop" } do
		local fn = module[method]
		if fn ~= nil and type(fn) ~= "function" then
			error(`{self._kind} {name}: {method} must be a function`, 2)
		end
	end
	local active = true
	local role = self._options.role
	if role ~= nil and module.Roles ~= nil then
		active = table.find(module.Roles :: { string }, role) ~= nil
	end
	self._records[name] = {
		module = module,
		name = name,
		status = "Registered",
		phase = nil,
		err = nil,
		initMs = nil,
		active = active,
	}
	table.insert(self._registrationOrder, name)
end

function LoaderClass.registerMany(self: ServiceLoader, modules: { ServiceModule })
	for _, module in modules do
		LoaderClass.register(self, module)
	end
end

--- Resolves the active modules into dependency order (deterministic: ties broken by name). Throws on missing
--- dependencies or cycles.
function LoaderClass.resolveOrder(self: ServiceLoader): { string }
	if self._order ~= nil then
		return table.clone(self._order)
	end
	local active = {}
	for _, name in self._registrationOrder do
		if self._records[name].active then
			table.insert(active, name)
		end
	end
	table.sort(active)

	local problems = {}
	for _, name in active do
		local deps: { string } = self._records[name].module.Dependencies or {}
		for _, dep in deps do
			local depRecord: Record? = self._records[dep]
			if depRecord == nil then
				table.insert(problems, `{name} depends on missing {self._kind} "{dep}"`)
			elseif not depRecord.active then
				table.insert(
					problems,
					`{name} depends on "{dep}", which is registered but not enabled for role "{self._options.role}"`
				)
			end
		end
	end
	if #problems > 0 then
		error(`{self._kind}Loader: {table.concat(problems, "; ")}`, 2)
	end

	-- Kahn's algorithm; among ready modules the smallest name goes first (stable, layered order).
	local order: { string } = {}
	local placed: { [string]: boolean } = {}
	local function depsOf(name: string): { string }
		local declared: { string } = self._records[name].module.Dependencies or {}
		local deps = table.clone(declared)
		table.sort(deps)
		return deps
	end
	local function isReady(name: string): boolean
		for _, dep in depsOf(name) do
			if not placed[dep] then
				return false
			end
		end
		return true
	end
	while #order < #active do
		local picked: string? = nil
		for _, name in active do
			if not placed[name] and isReady(name) then
				picked = name
				break
			end
		end
		if picked == nil then
			-- Every remaining module waits on another remaining module: walk unplaced dependencies to a cycle.
			local path: { string } = {}
			local current: string? = nil
			for _, name in active do
				if not placed[name] then
					current = name
					break
				end
			end
			while current ~= nil and table.find(path, current) == nil do
				table.insert(path, current)
				local nextName: string? = nil
				for _, dep in depsOf(current) do
					if not placed[dep] then
						nextName = dep
						break
					end
				end
				current = nextName
			end
			local start = if current ~= nil then table.find(path, current) or 1 else 1
			local cycle = table.move(path, start, #path, 1, {})
			table.insert(cycle, current or "?")
			error(`{self._kind}Loader: dependency cycle: {table.concat(cycle, " -> ")}`, 0)
		end
		placed[picked] = true
		table.insert(order, picked)
	end
	for _, name in self._registrationOrder do
		if not self._records[name].active then
			self._records[name].status = "Skipped"
			self._records[name].err = `not enabled for role "{self._options.role}"`
		end
	end
	self._order = order
	return table.clone(order)
end

local function fail(self: ServiceLoader, record: Record, phase: LifecyclePhase, err: string)
	record.status = "Failed"
	record.phase = phase
	record.err = err
	self._log:error("%s %s failed during %s: %s", self._kind, record.name, phase, err)
	self.ServiceFailed:Fire(record.name, phase, err)
end

local function contextFor(self: ServiceLoader, name: string): { [string]: any }
	local ctx = table.clone(self._context)
	ctx.services = self._services
	ctx.lifecycle = self._lifecycle
	ctx.log = Log.scope(name)
	return ctx
end

local function dependsOnFailed(self: ServiceLoader, record: Record): string?
	local deps: { string } = record.module.Dependencies or {}
	for _, dep in deps do
		local depRecord = self._records[dep]
		if depRecord.status == "Failed" or depRecord.status == "Skipped" then
			return dep
		end
	end
	return nil
end

--- Calls Init on every active module in dependency order. Init must not yield.
function LoaderClass.init(self: ServiceLoader)
	if self._phase ~= "Idle" then
		error(`{self._kind}Loader: init() called twice`, 2)
	end
	local order = LoaderClass.resolveOrder(self)
	for _, name in order do
		self._services[name] = self._records[name].module
	end
	for _, name in order do
		local record = self._records[name]
		local blocker = dependsOnFailed(self, record)
		if blocker ~= nil then
			record.status = "Skipped"
			record.err = `dependency "{blocker}" failed`
			self._services[name] = nil
			self._log:warn("%s %s skipped: dependency %s failed", self._kind, name, blocker)
			continue
		end
		local initFn = record.module.Init
		if initFn ~= nil then
			local started = self._clock:now()
			local ctx = contextFor(self, name)
			local thread = coroutine.create(function()
				return xpcall(initFn, traceback, record.module, ctx)
			end)
			local resumed, ok, err = coroutine.resume(thread)
			local failure: string? = nil
			if not resumed then
				failure = tostring(ok)
			elseif coroutine.status(thread) ~= "dead" then
				self._cancel(thread)
				failure = "Init yielded (Init must not yield; move yielding work to Start)"
			elseif not ok then
				failure = tostring(err)
			end
			record.initMs = (self._clock:now() - started) * 1000
			if failure ~= nil then
				self._services[name] = nil
				fail(self, record, "Init", failure)
				if self._options.failFast then
					error(`{self._kind} {name} failed during Init: {failure}`, 0)
				end
				continue
			end
		end
		record.status = "Initialized"
	end
	self._phase = "Initialized"
end

--- Calls Start on every initialized module in order, each in its own thread.
function LoaderClass.start(self: ServiceLoader)
	if self._phase ~= "Initialized" then
		error(`{self._kind}Loader: start() requires init() first`, 2)
	end
	local order: { string } = self._order or {}
	for _, name in order do
		local record = self._records[name]
		if record.status ~= "Initialized" then
			continue
		end
		local startFn = record.module.Start
		if startFn == nil then
			record.status = "Started"
			continue
		end
		record.status = "Starting"
		local began = false
		self._spawn(function()
			began = true
			local ok, err = xpcall(startFn :: any, traceback, record.module)
			if ok then
				-- Cast: the solver keeps the outer refinement inside this closure, but Start may have run long.
				if (record.status :: ServiceStatus) == "Starting" then
					record.status = "Started"
				end
			else
				fail(self, record, "Start", tostring(err))
			end
		end)
		-- A Start that yielded (e.g. a long-running loop) has begun its work: report it as Started rather than
		-- "Starting" forever. A later error still marks it Failed.
		if began and (record.status :: ServiceStatus) == "Starting" then
			record.status = "Started"
		end
	end
	self._phase = "Started"
end

--- Resolves, initializes and starts everything. Throws on configuration errors (missing deps, cycles).
function LoaderClass.boot(self: ServiceLoader)
	LoaderClass.init(self)
	LoaderClass.start(self)
end

--- Stops initialized modules in reverse order. Yielding Stop methods are awaited (via the injected `wait`) until
--- the shared budget runs out; without `wait`, yielding stops continue in the background.
function LoaderClass.stop(self: ServiceLoader, budgetSeconds: number?): StopReport
	local budget = budgetSeconds or 25
	local startedAt = self._clock:now()
	local deadline = startedAt + budget
	local report: StopReport = { stopped = {}, timedOut = {}, failed = {}, elapsed = 0 }
	if self._phase == "Stopped" then
		return report
	end
	local waitFn = self._options.wait
	local order: { string } = self._order or {}
	for i = #order, 1, -1 do
		local name = order[i]
		local record = self._records[name]
		if not STOPPABLE[record.status] then
			continue
		end
		local stopFn = record.module.Stop
		if stopFn == nil then
			record.status = "Stopped"
			table.insert(report.stopped, name)
			continue
		end
		record.status = "Stopping"
		local done = false
		local stopErr: string? = nil
		self._spawn(function()
			local ok, err = xpcall(stopFn :: any, traceback, record.module)
			if not ok then
				stopErr = tostring(err)
			end
			done = true
		end)
		if not done and waitFn ~= nil then
			while not done and self._clock:now() < deadline do
				waitFn(math.min(0.05, math.max(0, deadline - self._clock:now())))
			end
		end
		if not done then
			table.insert(report.timedOut, name)
			self._log:warn("%s %s Stop did not finish within the shutdown budget", self._kind, name)
		elseif stopErr ~= nil then
			report.failed[name] = stopErr
			record.status = "Failed"
			record.phase = "Stop"
			record.err = stopErr
			self._log:error("%s %s failed during Stop: %s", self._kind, name, stopErr)
			self.ServiceFailed:Fire(name, "Stop", stopErr)
		else
			record.status = "Stopped"
			table.insert(report.stopped, name)
		end
	end
	self._phase = "Stopped"
	report.elapsed = self._clock:now() - startedAt
	return report
end

--- Snapshot of every registered module's status (registration order).
function LoaderClass.getStatuses(self: ServiceLoader): { ServiceStatusInfo }
	local out = {}
	for _, name in self._registrationOrder do
		local record = self._records[name]
		table.insert(out, {
			name = name,
			status = record.status,
			phase = record.phase,
			err = record.err,
			initMs = record.initMs,
		})
	end
	return out
end

function LoaderClass.getStatus(self: ServiceLoader, name: string): ServiceStatus?
	local record = self._records[name]
	return if record then record.status else nil
end

--- Resolved dependency order (empty before resolveOrder/boot).
function LoaderClass.getOrder(self: ServiceLoader): { string }
	return table.clone(self._order or {})
end

--- The shared services table (name -> module) given to every context.
function LoaderClass.getServices(self: ServiceLoader): { [string]: any }
	return self._services
end

function LoaderClass.getLifecycle(self: ServiceLoader): Lifecycle
	return self._lifecycle
end

return ServiceLoader
