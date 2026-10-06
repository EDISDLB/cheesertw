--!strict
--[[
	Kit/State — reactive primitives for the UI kit: Value, Computed, Observer, effect, batch, keyed lists.

	Purpose:          A small, glitch-free reactive graph that every screen and component binds to. `Value<T>` holds
	                  state, `Computed<T>` derives state with AUTOMATIC dependency tracking (every `:get()` made while
	                  a Computed/effect runs is recorded; `:peek()` / `State.peek` read without tracking), `Observer`
	                  / `onChange` / `effect` run side effects, `batch` coalesces many sets into one flush.
	Dependencies:     Core/Log (error reporting), Core/Trove (scopes), Types/Core (Connection). Pure: no Roblox
	                  services, no scheduler, so the whole graph runs unchanged in Lune.
	State:            Module-level tracking context, effect queue, batch depth and the set of live (rooted) effects.
	                  Each node: value, version, status (clean/check/dirty), sources (+ versions seen), observers
	                  (weak-keyed).
	Validation:       Setting a Value inside a Computed raises; a Computed that reads itself (directly or through
	                  others) raises "cyclic dependency"; flushes are capped (MAX_FLUSH_RUNS) to catch effect loops.
	Error handling:   A throwing Computed logs the error and keeps its previous value; a throwing effect/observer
	                  callback is logged and the flush continues (one bad binding never breaks a screen).
	Performance notes: Push-pull propagation (the "Reactively" algorithm): a set marks dependents CHECK/DIRTY in
	                  O(edges) without computing; Computeds recompute lazily on read, at most once per change, only if
	                  a source's version really changed. Effects flush in creation order. No per-read allocation
	                  outside tracking runs.

	Semantics (see docs/systems/ui-kit.md §State):
	  * Equality: Value:set / a Computed result only notifies when `equals(old, new)` is false. The default treats
	    NaN as equal to NaN and TABLES AS ALWAYS CHANGED (so in-place mutation + set re-notifies). Pass
	    `{ equals = State.shallowEqual }` or `State.referenceEqual` to change it per node.
	  * Glitch-free: observers never see a mix of old and new values; in a diamond (a -> b, a -> c, b+c -> d) d
	    recomputes once with consistent inputs.
	  * Laziness: a Computed computes on first read and then only when read after a source changed.
	  * Leak-free: observer edges from a source to its dependents are WEAK, so an unreferenced Computed is collected
	    even if never destroyed. Effects/Observers are rooted until destroyed/disconnected (like a connection):
	    pass `{ scope = trove }` (or add the returned object/connection to a Trove) and they die with the scope.
	  * Batching: `State.batch(fn)` defers effects until fn returns (nested batches flush once at the outermost).
]]

local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")
local CoreTypes = require("@game/ReplicatedStorage/Shared/Types/Core")

type Trove = Trove.Trove
export type Connection = CoreTypes.Connection
export type Scope = Trove

export type State<T> = {
	get: (self: State<T>) -> T,
	peek: (self: State<T>) -> T,
	onChange: (self: State<T>, callback: (new: T, old: T) -> ()) -> Connection,
	Destroy: (self: State<T>) -> (),
}

export type Value<T> = {
	get: (self: State<T>) -> T,
	peek: (self: State<T>) -> T,
	onChange: (self: State<T>, callback: (new: T, old: T) -> ()) -> Connection,
	Destroy: (self: State<T>) -> (),
	--- Sets the value; dependents update only if `equals(old, new)` is false (or `force` is true).
	set: (self: Value<T>, value: T, force: boolean?) -> (),
	--- `value:update(function(v) return v + 1 end)`.
	update: (self: Value<T>, transform: (current: T) -> T) -> (),
}

export type Computed<T> = State<T>

--- A prop that may be a constant or reactive: components accept `CanBeState<T>` and read it with State.get/peek.
export type CanBeState<T> = T | State<T>

export type Options<T> = {
	--- Change detection (default: NaN-safe `==`, tables always considered changed).
	equals: ((old: T, new: T) -> boolean)?,
	--- Trove that destroys the node when cleaned.
	scope: Trove?,
	--- Computed only: called with a value when it is replaced by a new one and on Destroy (e.g. destroy instances).
	cleanup: ((value: T) -> ())?,
	--- Debug label used in error logs.
	name: string?,
}

export type EffectOptions = {
	scope: Trove?,
	name: string?,
}

export type ObserveOptions = {
	scope: Trove?,
	--- Also call the callback immediately with (current, current).
	immediate: boolean?,
}

export type Observer<T> = {
	--- Calls `callback(new, old)` after every change of the source (after batches flush).
	onChange: (self: Observer<T>, callback: (new: T, old: T) -> ()) -> Connection,
	--- Like onChange but also calls `callback(current, current)` immediately.
	onBind: (self: Observer<T>, callback: (new: T, old: T) -> ()) -> Connection,
	Destroy: (self: Observer<T>) -> (),
}

export type ListOptions<T> = {
	scope: Trove?,
	name: string?,
}

--- Bundle of constructors whose nodes are all added to one scope (`State.scoped(trove)`).
export type Scoped = {
	Value: <T>(initial: T, options: Options<T>?) -> Value<T>,
	Computed: <T>(compute: (previous: T?) -> T, options: Options<T>?) -> Computed<T>,
	effect: (fn: () -> (() -> ())?) -> Connection,
	observe: <T>(source: State<T>, callback: (new: T, old: T) -> (), immediate: boolean?) -> Connection,
}

local log = Log.scope("UI.State")

local KIND_VALUE = 1
local KIND_COMPUTED = 2
local KIND_EFFECT = 3

local CLEAN = 0
local CHECK = 1
local DIRTY = 2

local MAX_FLUSH_RUNS = 10000

local WEAK_KEYS = { __mode = "k" }

-- Internal node shape shared by every kind (fields unused by a kind stay nil).
type Node = {
	_kind: number,
	_id: number,
	_name: string?,
	_value: any,
	_hasValue: boolean,
	_version: number,
	_status: number,
	_observers: { [Node]: boolean }?,
	_sources: { Node },
	_sourceVersions: { number },
	_fn: any,
	_equals: (any, any) -> boolean,
	_cleanup: ((any) -> ())?,
	_effectCleanup: (() -> ())?,
	_running: boolean,
	_destroyed: boolean,
	_rooted: boolean,
	-- Strong reference kept alive with this node (State.list keeps its reconciling effect here).
	_owned: any,
	_onDestroy: (() -> ())?,
}

local nextId = 0

-- Tracking context of the Computed/effect currently running (nil = untracked).
local currentObserver: Node? = nil
local currentSources: { Node } = {}
local currentSourceVersions: { number } = {}
local currentSourceSet: { [Node]: number } = {}

local batchDepth = 0
local flushing = false
local effectQueue: { Node } = {}
-- Strong roots for effects created by user code (released on Destroy/disconnect).
local liveEffects: { [Node]: boolean } = {}
local liveEffectCount = 0

local function defaultEquals(a: any, b: any): boolean
	if type(a) == "table" or type(b) == "table" then
		return false
	end
	return a == b or (a ~= a and b ~= b)
end

local function referenceEqual(a: any, b: any): boolean
	return rawequal(a, b) or (a ~= a and b ~= b)
end

local function shallowEqual(a: any, b: any): boolean
	if rawequal(a, b) then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b or (a ~= a and b ~= b)
	end
	for k, v in a do
		local other = b[k]
		if not (rawequal(v, other) or (v ~= v and other ~= other)) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function onError(err: any): string
	return debug.traceback(tostring(err), 2)
end

-- xpcall with a traceback handler; always returns (ok, resultOrError) whatever `fn` returns.
local function safeCall(fn: any, ...: any): (boolean, any)
	return xpcall(fn, onError, ...)
end

local function label(node: Node): string
	return node._name or `#{node._id}`
end

local NodeClass = {}
NodeClass.__index = NodeClass

local function newNode(kind: number, name: string?): Node
	nextId += 1
	local node: Node = setmetatable({
		_kind = kind,
		_id = nextId,
		_name = name,
		_value = nil,
		_hasValue = false,
		_version = 0,
		_status = if kind == KIND_VALUE then CLEAN else DIRTY,
		_observers = nil,
		_sources = {},
		_sourceVersions = {},
		_fn = nil,
		_equals = defaultEquals,
		_cleanup = nil,
		_effectCleanup = nil,
		_running = false,
		_destroyed = false,
		_rooted = false,
		_owned = nil,
		_onDestroy = nil,
	}, NodeClass) :: any
	return node
end

local function isNode(value: any): boolean
	return type(value) == "table" and getmetatable(value) == NodeClass
end

--------------------------------------------------------------------------------
-- Graph maintenance
--------------------------------------------------------------------------------

local function addObserver(source: Node, observer: Node)
	local observers = source._observers
	if observers == nil then
		observers = setmetatable({}, WEAK_KEYS) :: any
		source._observers = observers
	end
	(observers :: { [Node]: boolean })[observer] = true
end

local function removeObserver(source: Node, observer: Node)
	local observers = source._observers
	if observers ~= nil then
		observers[observer] = nil
	end
end

local function unlinkAll(node: Node)
	for _, source in node._sources do
		removeObserver(source, node)
	end
	node._sources = {}
	node._sourceVersions = {}
end

local function markStale(node: Node, status: number)
	if node._status >= status or node._destroyed then
		return
	end
	local wasClean = node._status == CLEAN
	node._status = status
	if wasClean and node._kind == KIND_EFFECT then
		table.insert(effectQueue, node)
	end
	local observers = node._observers
	if observers ~= nil then
		for observer in observers do
			markStale(observer, CHECK)
		end
	end
end

local function track(node: Node)
	if currentObserver == nil then
		return
	end
	local index = currentSourceSet[node]
	if index ~= nil then
		currentSourceVersions[index] = node._version
		return
	end
	table.insert(currentSources, node)
	table.insert(currentSourceVersions, node._version)
	currentSourceSet[node] = #currentSources
end

-- Runs `fn(arg)` as `node` with dependency tracking; relinks sources afterwards. Returns xpcall results.
local function runTracked(node: Node, fn: (any) -> any, arg: any): (boolean, any)
	local prevObserver, prevSources, prevVersions, prevSet =
		currentObserver, currentSources, currentSourceVersions, currentSourceSet
	currentObserver = node
	currentSources = {}
	currentSourceVersions = {}
	currentSourceSet = {}
	node._running = true
	local ok, result = safeCall(fn, arg)
	node._running = false
	local newSources, newVersions, newSet = currentSources, currentSourceVersions, currentSourceSet
	currentObserver, currentSources, currentSourceVersions, currentSourceSet =
		prevObserver, prevSources, prevVersions, prevSet
	if node._destroyed then
		-- Destroyed while running (e.g. an effect that destroys itself): never re-link.
		for _, source in newSources do
			removeObserver(source, node)
		end
		return ok, result
	end
	for _, source in node._sources do
		if newSet[source] == nil then
			removeObserver(source, node)
		end
	end
	for _, source in newSources do
		addObserver(source, node)
	end
	node._sources = newSources
	node._sourceVersions = newVersions
	if node._kind == KIND_EFFECT and node._status == CLEAN then
		-- A source changed AFTER this run read it (typically the effect's own write on its first run, before the
		-- observer edge existed, so the set could not mark it): it would stay CLEAN on a stale read until some other
		-- change. Re-queue it like any stale effect (MAX_FLUSH_RUNS still catches an effect that writes forever).
		for i, source in newSources do
			if source._version ~= newVersions[i] then
				node._status = DIRTY
				table.insert(effectQueue, node)
				break
			end
		end
	end
	return ok, result
end

local updateIfNecessary: (node: Node) -> ()

local function recompute(node: Node)
	local ok, result = runTracked(node, node._fn, node._value)
	if not ok then
		log:error("Computed %s failed (keeping previous value): %s", label(node), tostring(result))
		return
	end
	if node._hasValue and node._equals(node._value, result) then
		-- The new result is discarded (the old one stays published): it still owns whatever it holds (e.g.
		-- instances built by the compute function), so it gets the cleanup the published value would get.
		local discardCleanup = node._cleanup
		if discardCleanup ~= nil and not rawequal(node._value, result) then
			local okCleanup, err = safeCall(discardCleanup, result)
			if not okCleanup then
				log:error("Computed %s cleanup failed: %s", label(node), tostring(err))
			end
		end
		return
	end
	local old, hadValue = node._value, node._hasValue
	node._value = result
	node._hasValue = true
	node._version += 1
	local cleanup = node._cleanup
	if cleanup ~= nil and hadValue and not rawequal(old, result) then
		local okCleanup, err = safeCall(cleanup, old)
		if not okCleanup then
			log:error("Computed %s cleanup failed: %s", label(node), tostring(err))
		end
	end
end

local function runEffect(node: Node)
	local previousCleanup = node._effectCleanup
	if previousCleanup ~= nil then
		node._effectCleanup = nil
		local prevObserver = currentObserver
		currentObserver = nil
		local okCleanup, err = safeCall(previousCleanup)
		currentObserver = prevObserver
		if not okCleanup then
			log:error("effect %s cleanup failed: %s", label(node), tostring(err))
		end
	end
	local ok, result = runTracked(node, node._fn, nil)
	if not ok then
		log:error("effect %s failed: %s", label(node), tostring(result))
		return
	end
	if type(result) == "function" then
		if node._destroyed then
			local okCleanup, err = safeCall(result)
			if not okCleanup then
				log:error("effect %s cleanup failed: %s", label(node), tostring(err))
			end
		else
			node._effectCleanup = result
		end
	end
end

function updateIfNecessary(node: Node)
	if node._destroyed then
		node._status = CLEAN
		return
	end
	if node._status == CHECK then
		local sources, versions = node._sources, node._sourceVersions
		for i, source in sources do
			if source._kind == KIND_COMPUTED then
				updateIfNecessary(source)
			end
			if source._version ~= versions[i] then
				node._status = DIRTY
				break
			end
		end
	end
	if node._status == DIRTY then
		-- Mark clean first: a run that re-dirties this node (a set inside its own effect) re-queues it.
		node._status = CLEAN
		if node._kind == KIND_COMPUTED then
			recompute(node)
		else
			runEffect(node)
		end
		return
	end
	node._status = CLEAN
end

local function flush()
	if flushing or batchDepth > 0 then
		return
	end
	flushing = true
	local runs = 0
	while #effectQueue > 0 do
		local queue = effectQueue
		effectQueue = {}
		table.sort(queue, function(a: Node, b: Node)
			return a._id < b._id
		end)
		for _, effect in queue do
			runs += 1
			if runs > MAX_FLUSH_RUNS then
				effectQueue = {}
				flushing = false
				error(
					`State: more than {MAX_FLUSH_RUNS} effect runs in one flush (an effect keeps re-triggering itself)`
				)
			end
			if not effect._destroyed then
				updateIfNecessary(effect)
			end
		end
	end
	flushing = false
end

--------------------------------------------------------------------------------
-- Node methods (shared by Value / Computed; effects are internal)
--------------------------------------------------------------------------------

local function readNode(node: Node, tracked: boolean): any
	if node._kind == KIND_COMPUTED then
		if node._running then
			error(`State: cyclic dependency (Computed {label(node)} reads itself)`, 3)
		end
		if node._status ~= CLEAN then
			updateIfNecessary(node)
		end
	end
	if tracked then
		track(node)
	end
	return node._value
end

function NodeClass.get(self: Node): any
	return readNode(self, true)
end

function NodeClass.peek(self: Node): any
	return readNode(self, false)
end

local function setValue(node: Node, value: any, force: boolean?)
	if node._kind ~= KIND_VALUE then
		error("State: only Values can be set", 3)
	end
	local observer = currentObserver
	if observer ~= nil and observer._kind == KIND_COMPUTED then
		error(`State: cannot set a Value inside Computed {label(observer)} (derive it instead)`, 3)
	end
	if not force and node._equals(node._value, value) then
		return
	end
	node._value = value
	node._version += 1
	local observers = node._observers
	if observers ~= nil then
		for dependent in observers do
			markStale(dependent, DIRTY)
		end
	end
	flush()
end

function NodeClass.set(self: Node, value: any, force: boolean?)
	setValue(self, value, force)
end

function NodeClass.update(self: Node, transform: (any) -> any)
	setValue(self, transform(self._value), false)
end

local function destroyNode(node: Node)
	if node._destroyed then
		return
	end
	node._destroyed = true
	unlinkAll(node)
	local onDestroy = node._onDestroy
	if onDestroy ~= nil then
		node._onDestroy = nil
		local ok, err = safeCall(onDestroy)
		if not ok then
			log:error("%s destroy hook failed: %s", label(node), tostring(err))
		end
	end
	if node._kind == KIND_VALUE then
		node._observers = nil
	elseif node._kind == KIND_COMPUTED then
		node._status = CLEAN
		local cleanup = node._cleanup
		if cleanup ~= nil and node._hasValue then
			local ok, err = safeCall(cleanup, node._value)
			if not ok then
				log:error("Computed %s cleanup failed: %s", label(node), tostring(err))
			end
		end
	else
		if node._rooted then
			node._rooted = false
			liveEffects[node] = nil
			liveEffectCount -= 1
		end
		local effectCleanup = node._effectCleanup
		node._effectCleanup = nil
		if effectCleanup ~= nil then
			local ok, err = safeCall(effectCleanup)
			if not ok then
				log:error("effect %s cleanup failed: %s", label(node), tostring(err))
			end
		end
	end
end

function NodeClass.Destroy(self: Node)
	destroyNode(self)
end

-- Effect node driving a list of listeners (shared by Observer, onChange and State.observe).
type ObserverImpl = {
	_source: Node,
	_effect: Node?,
	_listeners: { { fn: (any, any) -> (), connected: boolean } },
	_last: any,
	_scope: Trove?,
	_destroyed: boolean,
}

local ObserverClass = {}
ObserverClass.__index = ObserverClass

type ListEntry = { item: Value<any>, index: Value<number>, scope: Trove, output: any }

local function newEffect(fn: () -> any, name: string?, rooted: boolean): Node
	local node = newNode(KIND_EFFECT, name)
	node._fn = fn
	if rooted then
		node._rooted = true
		liveEffects[node] = true
		liveEffectCount += 1
	end
	-- Initial run establishes dependencies (outside any batch it runs immediately).
	node._status = CLEAN
	runEffect(node)
	-- A first run that wrote one of its own sources re-queued itself (runTracked): settle it now (no-op inside a flush
	-- or a batch, which settle it themselves).
	if node._status ~= CLEAN then
		flush()
	end
	return node
end

local function makeConnection(disconnect: () -> ()): Connection
	local connection = { Connected = true }
	function connection.Disconnect(self: any)
		if not self.Connected then
			return
		end
		self.Connected = false
		disconnect()
	end
	return (connection :: any) :: Connection
end

local function observerEnsureEffect(self: ObserverImpl)
	if self._effect ~= nil or self._destroyed then
		return
	end
	local source = self._source
	local initialized = false
	self._effect = newEffect(function()
		-- The first run only records the dependency; later runs happen only after the source's version changed.
		local new = readNode(source, true)
		if not initialized then
			initialized = true
			self._last = new
			return nil
		end
		local old = self._last
		self._last = new
		local prevObserver = currentObserver
		currentObserver = nil
		for _, listener in table.clone(self._listeners) do
			if listener.connected then
				local ok, err = safeCall(listener.fn, new, old)
				if not ok then
					log:error("observer callback failed: %s", tostring(err))
				end
			end
		end
		currentObserver = prevObserver
		return nil
	end, "Observer", true)
end

local function observerRemoveListener(self: ObserverImpl, entry: { fn: (any, any) -> (), connected: boolean })
	entry.connected = false
	local index = table.find(self._listeners, entry)
	if index ~= nil then
		table.remove(self._listeners, index)
	end
	if #self._listeners == 0 and self._effect ~= nil then
		destroyNode(self._effect :: Node)
		self._effect = nil
	end
end

function ObserverClass.onChange(self: ObserverImpl, callback: (any, any) -> ()): Connection
	if type(callback) ~= "function" then
		error("Observer:onChange expects a function", 2)
	end
	if self._destroyed then
		return makeConnection(function() end)
	end
	local entry = { fn = callback, connected = true }
	table.insert(self._listeners, entry)
	observerEnsureEffect(self)
	return makeConnection(function()
		observerRemoveListener(self, entry)
	end)
end

function ObserverClass.onBind(self: ObserverImpl, callback: (any, any) -> ()): Connection
	local connection = ObserverClass.onChange(self, callback)
	local current = readNode(self._source, false)
	local prevObserver = currentObserver
	currentObserver = nil
	local ok, err = safeCall(callback, current, current)
	currentObserver = prevObserver
	if not ok then
		log:error("observer callback failed: %s", tostring(err))
	end
	return connection
end

function ObserverClass.Destroy(self: ObserverImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, listener in self._listeners do
		listener.connected = false
	end
	self._listeners = {}
	if self._effect ~= nil then
		destroyNode(self._effect :: Node)
		self._effect = nil
	end
end

local function newObserver(source: Node, scope: Trove?): ObserverImpl
	local self: ObserverImpl = setmetatable({
		_source = source,
		_effect = nil,
		_listeners = {},
		_last = nil,
		_scope = scope,
		_destroyed = false,
	}, ObserverClass) :: any
	if scope ~= nil then
		scope:Add(self, "Destroy")
	end
	return self
end

function NodeClass.onChange(self: Node, callback: (any, any) -> ()): Connection
	local observer = newObserver(self, nil)
	local connection = ObserverClass.onChange(observer, callback)
	return makeConnection(function()
		connection:Disconnect()
		ObserverClass.Destroy(observer)
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local State = {}

State.defaultEquals = defaultEquals
--- `==` for everything including tables (same table reference = unchanged); NaN equals NaN.
State.referenceEqual = referenceEqual
--- One-level table comparison (same keys, rawequal values); non-tables compare with `==`.
State.shallowEqual = shallowEqual

local function applyOptions(node: Node, options: Options<any>?)
	if options == nil then
		return
	end
	if options.equals ~= nil then
		node._equals = options.equals
	end
	if options.cleanup ~= nil then
		node._cleanup = options.cleanup
	end
	if options.scope ~= nil then
		options.scope:Add(node, "Destroy")
	end
end

--- Creates a settable state. `local health = State.Value(100)`; `health:set(80)`; `health:get()`.
function State.Value<T>(initial: T, options: Options<T>?): Value<T>
	local node = newNode(KIND_VALUE, if options then options.name else nil)
	node._value = initial
	node._hasValue = true
	applyOptions(node, options :: any)
	return (node :: any) :: Value<T>
end

--- Creates derived state. Every `:get()` made inside `compute` becomes a dependency (dynamic: re-collected on every
--- run). `compute` receives the previous value (nil on the first run) and must not yield or set Values.
function State.Computed<T>(compute: (previous: T?) -> T, options: Options<T>?): Computed<T>
	if type(compute) ~= "function" then
		error("State.Computed expects a function", 2)
	end
	local node = newNode(KIND_COMPUTED, if options then options.name else nil)
	node._fn = compute
	applyOptions(node, options :: any)
	return (node :: any) :: Computed<T>
end

--- Shorthand for a Computed over one state (or constant): `State.map(health, function(h) return h / 100 end)`.
local function mapImpl(source: any, transform: (any) -> any, options: Options<any>?): any
	return State.Computed(function(): any
		return transform(State.get(source))
	end, options)
end

--- Creates an Observer on `source`; add listeners with `:onChange(fn)` / `:onBind(fn)`. The observer stays alive
--- while it has listeners; `:Destroy()` (or the scope) disconnects everything.
function State.Observer<T>(source: State<T>, options: EffectOptions?): Observer<T>
	if not isNode(source) then
		error("State.Observer expects a Value or Computed", 2)
	end
	return (newObserver(source :: any, if options then options.scope else nil) :: any) :: Observer<T>
end

--- `State.observe(value, function(new, old) ... end)` -> Connection. Callbacks run after batches flush and only
--- when the value really changed (per its equality). Untracked: reads inside the callback add no dependencies.
function State.observe<T>(source: State<T>, callback: (new: T, old: T) -> (), options: ObserveOptions?): Connection
	local observer = newObserver(source :: any, nil)
	local connection = if options and options.immediate
		then ObserverClass.onBind(observer, callback :: any)
		else ObserverClass.onChange(observer, callback :: any)
	local wrapped = makeConnection(function()
		connection:Disconnect()
		ObserverClass.Destroy(observer)
	end)
	if options and options.scope then
		options.scope:Add(wrapped, "Disconnect")
	end
	return wrapped
end

--- Runs `fn` now and again whenever any state it read changes (auto-tracked). `fn` may return a cleanup function
--- that runs before the next run and when the effect is disconnected.
function State.effect(fn: () -> (() -> ())?, options: EffectOptions?): Connection
	if type(fn) ~= "function" then
		error("State.effect expects a function", 2)
	end
	local node = newEffect(fn, if options then options.name else "effect", true)
	local connection = makeConnection(function()
		destroyNode(node)
	end)
	if options and options.scope then
		options.scope:Add(connection, "Disconnect")
	end
	return connection
end

--- Internal-grade effect that is NOT rooted globally: it lives exactly as long as the caller keeps the returned
--- disconnect function (Create uses it for instance bindings so a binding dies with its instance).
function State.bindEffect(fn: () -> (), name: string?): () -> ()
	local node = newEffect(fn, name or "binding", false)
	return function()
		destroyNode(node)
	end
end

--- Defers every effect until `fn` returns, then flushes once. Nested batches flush at the outermost end. Reads
--- inside the batch see the new values immediately (Computeds are pulled on demand).
function State.batch(fn: () -> ())
	batchDepth += 1
	local ok, err = safeCall(fn)
	batchDepth -= 1
	if batchDepth == 0 then
		flush()
	end
	if not ok then
		error(err, 0)
	end
end

--- True if `value` is a Value or Computed created by this module.
function State.isState(value: any): boolean
	return isNode(value) and (value._kind == KIND_VALUE or value._kind == KIND_COMPUTED)
end

local function getImpl(value: any): any
	if isNode(value) then
		return readNode(value :: any, true)
	end
	return value
end

local function peekImpl(value: any): any
	if isNode(value) then
		return readNode(value :: any, false)
	end
	return value
end

-- Overloaded signatures: a State<T> argument binds T to its value type, a CanBeState<T> prop to T.
type ReadFn = (<T>(value: State<T>) -> T) & (<T>(value: CanBeState<T>) -> T)
type MapFn =
	(<T, U>(source: State<T>, transform: (T) -> U, options: Options<U>?) -> Computed<U>)
	& (<T, U>(source: CanBeState<T>, transform: (T) -> U, options: Options<U>?) -> Computed<U>)
type OfFn = (<T>(value: State<T>) -> State<T>) & (<T>(value: CanBeState<T>) -> State<T>)

--- Tracked read of a maybe-state (use inside Computed/effect): constants are returned as-is.
State.get = (getImpl :: any) :: ReadFn

--- Untracked read of a maybe-state (always up to date, never adds a dependency).
State.peek = (peekImpl :: any) :: ReadFn

--- Derived state over one State or constant: `State.map(health, function(h) return h / 100 end)`.
State.map = (mapImpl :: any) :: MapFn

--- Runs `fn` without dependency tracking and returns its result.
function State.untracked<T>(fn: () -> T): T
	local prevObserver = currentObserver
	currentObserver = nil
	local ok, result = safeCall(fn)
	currentObserver = prevObserver
	if not ok then
		error(result, 0)
	end
	return result
end

--- Type helper: exposes a Value as read-only State (no runtime cost).
function State.readonly<T>(value: Value<T>): State<T>
	return (value :: any) :: State<T>
end

local function ofImpl(value: any): any
	if isNode(value) then
		return value
	end
	return State.Value(value)
end

--- Wraps a constant as a State (so code that needs a State can accept constants); States pass through.
State.of = (ofImpl :: any) :: OfFn

--- Keyed list rendering: returns a State array of render outputs in item order. An output is created once per key
--- with `render(item, index, scope)`, which receives per-entry Values (a changed item with the same key updates its
--- bindings in place instead of re-rendering); when a key disappears its scope is destroyed (an Instance returned
--- by render is destroyed with it). nil/duplicate keys fall back to the item index with a warning.
--- Lifetime: the list lives while the returned State is referenced (e.g. bound as Create Children); `:Destroy()`
--- (or `options.scope`) destroys every entry immediately.
local function listImpl<T, R>(
	source: CanBeState<{ T }>,
	keyOf: (item: T, index: number) -> any,
	render: (item: Value<T>, index: Value<number>, scope: Trove) -> R,
	options: ListOptions<T>?
): State<{ R }>
	local name = if options and options.name then options.name else "list"
	local entries: { [any]: ListEntry } = {}
	local output = newNode(KIND_VALUE, name)
	output._value = {}
	output._hasValue = true

	local reconcile = newEffect(function()
		local items: { T } = State.get(source) or {}
		local seen: { [any]: boolean } = {}
		local outputs: { R } = {}
		local updates: { { entry: ListEntry, item: T, index: number } } = {}
		local prevObserver = currentObserver
		currentObserver = nil
		for index, item in items do
			local key = keyOf(item, index)
			if key == nil or seen[key] then
				log:warn(
					"State.list %s: %s key at index %d; using the index",
					name,
					if key == nil then "nil" else "duplicate",
					index
				)
				key = `__index_{index}`
			end
			seen[key] = true
			local entry = entries[key]
			if entry == nil then
				local scope = Trove.new()
				local itemValue = State.Value(item)
				local indexValue = State.Value(index)
				local ok, result = safeCall(render :: any, itemValue, indexValue, scope)
				if not ok then
					log:error("State.list %s render failed: %s", name, tostring(result))
				elseif typeof(result) == "Instance" then
					scope:Add(result)
				end
				entry = { item = itemValue, index = indexValue, scope = scope, output = result }
				entries[key] = entry
			else
				table.insert(updates, { entry = entry, item = item, index = index })
			end
			local current = entry :: ListEntry
			if current.output ~= nil then
				table.insert(outputs, current.output :: R)
			end
		end
		for key, entry in pairs(entries) do
			if not seen[key] then
				entries[key] = nil
				entry.scope:Destroy()
			end
		end
		currentObserver = prevObserver
		State.batch(function()
			for _, change in updates do
				(change.entry.item :: Value<T>):set(change.item)
				change.entry.index:set(change.index)
			end
			setValue(output, outputs, true)
		end)
		return nil
	end, name, false)

	output._owned = reconcile
	output._onDestroy = function()
		destroyNode(reconcile)
		for key, entry in pairs(entries) do
			entries[key] = nil
			entry.scope:Destroy()
		end
	end
	if options and options.scope then
		options.scope:Add(output, "Destroy")
	end
	return (output :: any) :: State<{ R }>
end

type ListFn =
	(<T, R>(
		source: State<{ T }>,
		keyOf: (item: T, index: number) -> any,
		render: (item: Value<T>, index: Value<number>, scope: Trove) -> R,
		options: ListOptions<T>?
	) -> State<{ R }>)
	& (<T, R>(
		source: CanBeState<{ T }>,
		keyOf: (item: T, index: number) -> any,
		render: (item: Value<T>, index: Value<number>, scope: Trove) -> R,
		options: ListOptions<T>?
	) -> State<{ R }>)

State.list = (listImpl :: any) :: ListFn

--- Constructors bound to `scope`: every node/effect they create is destroyed when the scope is cleaned.
function State.scoped(scope: Trove): Scoped
	return {
		Value = function<T>(initial: T, options: Options<T>?): Value<T>
			local opts: Options<T> = if options then table.clone(options) else {}
			opts.scope = scope
			return State.Value(initial, opts)
		end,
		Computed = function<T>(compute: (previous: T?) -> T, options: Options<T>?): Computed<T>
			local opts: Options<T> = if options then table.clone(options) else {}
			opts.scope = scope
			return State.Computed(compute, opts)
		end,
		effect = function(fn: () -> (() -> ())?): Connection
			return State.effect(fn, { scope = scope })
		end,
		observe = function<T>(source: State<T>, callback: (new: T, old: T) -> (), immediate: boolean?): Connection
			return State.observe(source, callback, { scope = scope, immediate = immediate })
		end,
	}
end

--- Diagnostics for leak tests: number of rooted effects/observers currently alive.
function State.stats(): { liveEffects: number, queued: number, batchDepth: number }
	return { liveEffects = liveEffectCount, queued = #effectQueue, batchDepth = batchDepth }
end

return State
