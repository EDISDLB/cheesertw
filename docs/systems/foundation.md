# Foundation layer — developer guide

The foundation is the code every other system builds on: `Shared/Core`, `Shared/Types`, `Shared/Net`,
`Shared/Security`, `Shared/Config` (Battle, Places, DevAccess), the server/client bootstraps, the platform adapters and
the Lune test harness. The contract is `docs/ARCHITECTURE.md` (§2–5, §13); this page is the practical how-to.

## Running checks

```sh
scripts/check.sh                      # fmt, lint, types (luau-lsp + Roblox defs), tests, rojo build
scripts/check.sh --only test          # one gate: fmt | lint | types | test | build
scripts/check.sh --only test -- Signal NetServer   # only spec files whose path contains a filter (case-insensitive)
scripts/check.sh --fix --only fmt     # apply StyLua
lune run tests/run.luau -- Config     # run tests directly
```

Set `HULLDOWN_TOOLS=/path/to/binaries` if the toolchain is not on `PATH` (`rokit install` pins it). `NO_COLOR=1`
disables colors. Everything must pass before a commit. `tests/Regression/SourceConventions.spec.luau` enforces the
§3 rules on every file in `src/` (`--!strict`, header block, string requires, no bare `print`, Shared purity).

## Adding a server service

1. Create `src/ServerScriptService/Server/Services/MyService.luau` (or `MyService/init.luau`). The module's `Name`
   must equal the file/folder name (Main checks it).

```lua
--!strict
--[[ (header: Purpose / Dependencies / State / Validation / Error handling / Performance notes) ]]
local Types = require("@game/ReplicatedStorage/Shared/Types")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")

local MyService = {
	Name = "MyService",
	Roles = { "Hub", "Dev" },              -- omit = every role
	Dependencies = { "HealthService" },    -- Init/Start run after these
	_ctx = (nil :: any) :: Types.ServiceContext,
}

function MyService.Init(self: typeof(MyService), ctx: Types.ServiceContext)
	self._ctx = ctx                         -- MUST NOT yield (no DataStore calls, no task.wait)
	ctx.net:onInvoke("MyRequest", function(player: Player, args: any): Types.Result<any>
		return Result.ok(true)
	end)
end

function MyService.Start(self: typeof(MyService)) end  -- may yield; runs in its own thread
function MyService.Stop(self: typeof(MyService)) end   -- optional; reverse order on BindToClose, 25 s budget

return MyService
```

* `ctx` = `{ role, services, net, config, log (scoped to the service), clock, adapters, isStudio, server, lifecycle }`.
  Other services: `ctx.services.DataService` (only declared dependencies are guaranteed initialized).
* Never call Roblox platform services directly: use `ctx.adapters.dataStore / memoryStore / messaging / teleport /
  marketplace / players` (their `*Async` methods return `(ok, valueOrErr)` and never throw).
* Adapter signals (`PlayerAdded`...) are plain synchronous `Signal`s: spawn (`task.spawn`) before yielding inside a
  handler. Players already present before you connect are not replayed — iterate `ctx.adapters.players:getPlayers()`
  in `Start`.
* An Init that errors or yields marks the service `Failed` and skips its dependents; HealthService reports it and
  `Hello` returns `healthy = false`.
* Developer console commands: `ctx.services.DebugService:registerCommand("name", { description, handler =
  function(player, args) return Result.ok("text") end })` (declare `DebugService` as a dependency).

## Adding a client controller

Create `src/ReplicatedStorage/Client/Controllers/MyController.luau` with the same shape. `Roles` filter by the
server role received from the `Hello` handshake. The context is `{ role, services (controllers), net (NetClient),
config, log, clock, isStudio, player, lifecycle, hello }`. `net:on` never yields; `net:invoke` yields (call it from
`Start` or a spawned thread, never `Init`).

## Adding a remote

Append a `define({...})` to `src/ReplicatedStorage/Shared/Net/Remotes.luau`:

```lua
define({
	name = "ResearchModule",
	kind = "Function",                 -- "Event" | "Unreliable" | "Function" (Functions are C2S only)
	direction = "C2S",
	rate = { perSecond = 2, burst = 5 },  -- default Protocol.DEFAULT_RATE for C2S
	args = {                           -- REQUIRED for C2S; one validator per argument; extra arguments are rejected
		Schema.struct({
			requestId = Schema.string({ minLen = 1, maxLen = 40 }),
			moduleId = Schema.string({ maxLen = 64 }),
		}),
	},
})
```

Server: `ctx.net:on(name, fn(player, ...))` (C2S events) / `ctx.net:onInvoke(name, fn(player, ...) -> Result)` /
`ctx.net:fire(name, player, ...)`, `fireAll`, `fireList`. NetServer enforces rate limit -> devOnly gate -> schema ->
pcall; violations go to the handler installed with `net:setViolationHandler(fn(player, reason, weight, detail))`
(AntiExploitService). Function remotes always answer a `Result` (`RATE_LIMITED`, `INVALID_ARGS` with a path such as
`arg1.loadout[3].count: expected integer, got 2.5`, `NOT_ALLOWED`, `NOT_READY` before a handler exists, `INTERNAL` on
handler errors). Client: `net:fire`, `net:on`, `net:invoke` / `net:invokeWithTimeout` (always returns a Result:
`TIMEOUT`, `NOT_FOUND`, `INVALID_ARGS` (validated locally first), `INTERNAL`).

Binary payloads: build them with `Net/Codecs/BufferWriter` and read them with `BufferReader` (bounds-checked; wrap
decoding in `pcall`), send over an `Unreliable` remote with `args = { Schema.buffer({ maxLen = 900 }) }`.

New error codes go in `Net/ErrorCodes.luau` (`NAME = "NAME"` + a default message).

## Adding config

* Tunables: create `Config/<Section>.luau` returning a plain table in real-world units, then add it to the `Config`
  table and `SECTIONS` in `Config/init.luau`. Read `Config.<Section>.<KEY>` at use time (sections are deep-frozen;
  live overrides replace the section table).
* Live-overridable keys are declared in the section's `BOUNDS` table: `BOUNDS = { SNAPSHOT_RATE = { min = 5, max =
  30, integer = true }, ["Capture.RATE"] = { min = 0, max = 10 } }`. Overrides are read at server boot from DataStore
  `HulldownConfig/LiveOverrides` (a nested table like `{ Battle = { SNAPSHOT_RATE = 15 } }`) and applied
  all-or-nothing by `Config.applyOverrides(patch) -> Result<{ "Battle.SNAPSHOT_RATE" }>`. Tests assert every declared
  default lies inside its bounds (`Config.validateBounds()`).
* Place ids: `Config/Places.luau` (`HUB_PLACE_ID`, `BATTLE_PLACE_ID`, `DEV_PLACE_ID`; 0 = unpublished). Studio and
  unmapped places resolve to `"Dev"`. Developer access: `Config/DevAccess.luau` (`USER_IDS`, `GROUP_ID`,
  `MIN_GROUP_RANK`; Studio always allowed).

## Adding types

Declare the type in the domain module (`Shared/Types/<Domain>.luau`) and re-export it from `Types/init.luau`.
Domain modules may only require other `Types/*` modules. `Content.luau`, `Battle.luau` and `Profile.luau` are
placeholders owned by the content, combat and services teams.

## Writing tests

```lua
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

describe("Thing", function()
	Test.beforeEach(function() end)          -- also afterEach, beforeAll, afterAll
	it("works", function()
		expect(value).toEqual({ a = 1 })    -- .never.<matcher> inverts
	end)
	it.skip("later", function() end)       -- it.only / describe.only / describe.skip
end)
```

Matchers: `toBe`, `toEqual` (deep, readable diff), `toBeCloseTo(n|Vector3|CFrame, eps?)`, `toBeNil`, `toBeTruthy`,
`toBeFalsy`, `toBeGreaterThan(OrEqual)`, `toBeLessThan(OrEqual)`, `toContain`, `toHaveLength`, `toThrow(substring?)`
(plain substring), `toBeOk()`, `toBeErr(code?)`, `toBeType`, `toMatch`. `Test.spy(impl?)` records calls.

* Location: `tests/Unit/<src path>/<Module>.spec.luau` (e.g. `tests/Unit/ReplicatedStorage/Shared/Core/RNG.spec.luau`),
  services in `tests/Integration/ServerScriptService/Server/...`, bug repros in `tests/Regression/`.
* Every spec file gets a fresh module cache and a fresh mock `game` (`MockGame`): module state never leaks between
  files. Tests that yield are supported (15 s timeout per test). Logs are captured per file and printed only when the
  file fails; use `LogCapture.start()` / `capture:find("error", "text")` / `capture:stop()` to assert on logs.
* Harness toolbox (`@tests/Harness/...`):
  * `FakeClock.new(t)` — `now/advance/set` plus `schedule(delay, fn)` / `cancel(id)`.
  * `Mocks/MockAdapters.new({ clock })` — full `Types.Adapters` bundle. Every mock supports
    `failNext(method, count?, message?)`, `failAlways`, `clearFailures` and records calls (`injector.calls`).
    DataStore: Roblox error codes, budgets (`setBudget`), version history, `injectConcurrentWrite` (UpdateAsync
    re-runs its transform). MemoryStore: TTL on the injected clock, Roblox sort order, `simulateConflict`.
    Messaging: shared/deferred buses (`newBus`, `bus:flush()`). Teleport: `simulateTeleportFailure`.
    Marketplace: `simulatePurchase`, `redeliverPending`. Players: `addPlayer`, `removePlayer`, `setGroupRank`.
  * `ServerHarness.boot({ role?, isStudio?, modules, config? })` — real `Bootstrap` + NetServer on mocks; `h.invoke(
    player, "Remote", ...)`, `h.remote(name)`, `h.shutdown()`.
  * `HeightmapWorld.new({ height, groundMaterial, waterLevel, boxes, foliage, smoke })` — analytic `Types.World`.
  * Mock instances: `Instance.new` returns `MockInstance`s; remotes loop back in-process (`remote:FireServer` arrives as
    `OnServerEvent(LocalPlayer, ...)`, `remote:_simulateFireServer(player, ...)` / `_simulateInvokeServer(player,
    ...)` act as other clients, `remote._sent` records server sends). `game:GetService("RunService")` has
    `setServer/setClient/setStudio` and `step(dt)`; `game:GetService("Players")` has `addPlayer/setLocalPlayer`;
    `game:setService(name, fake)` installs fakes; `game:close()` runs BindToClose callbacks.

## Core API quick reference (beyond ARCHITECTURE §4)

| Module | Additions / exact semantics |
|---|---|
| Signal | FIFO synchronous dispatch; handler errors are logged and do not stop other handlers; connect-during-fire runs next Fire; `Signal.is(v)`, `signal:Destroy()` (= DisconnectAll). Handlers must not yield. |
| Trove | Cleans LIFO; `Remove(obj)` removes **and cleans**; adding to a destroyed trove cleans immediately; threads are cancelled with `task.cancel`. |
| Log | `Log.getLevel()`, `Log.isEnabled(level)`, `Log.setSink(fn?) -> previousSink` (nil restores default). Default level `info` (Main uses `debug` in Studio). |
| RNG | PCG-XSH-RR 64/32, bit-exact with the C reference. `RNG.new(seed, stream?)` (default stream 54), `rng:getState()`, `RNG.fromState(state)`. `fork(salt)` does not advance the parent. `chance` always consumes one draw. Float transforms (`normal`) depend on libm. |
| Units | `+ METERS_PER_STUD, GRAVITY_STUDS, kmhToMps, mpsToKmh, studsPerSecToMps, tonnesToKg, kgToTonnes` |
| TableUtil | `sortedKeys` (numbers, strings, booleans); `map/filter/find` operate on arrays; `diff` emits sets in ascending key order then deletes in descending order; `applyPatches` mutates and returns the target, deep-copies values, errors on malformed patches. |
| MathUtil | `smoothDamp(current, target, velocity, smoothTime, dt, maxSpeed?) -> (value, velocity)`, `wrapDeg` -> (-180, 180], `approachAngleDeg`, `round(n, step?)` (halves away from zero), `expDecay(current, target, rate, dt)`, `sign`, `isFinite`. |
| Schema | `Schema.boolean` / `Schema.any` are validators (no call). `+ buffer({minLen,maxLen})`, `instance(className?)`, `describe(v)`; `struct(fields, { allowExtra })`; strings must be valid UTF-8 unless `allowInvalidUtf8`; numbers must be finite. `Schema.check(v, value, label?)`. |
| Result | `+ isErr, unwrap, unwrapOr, Result.is(value)` |
| Clock | `Clock.wall()` (unix seconds, for persisted timestamps); FakeClock `:set(t)`. |
| ServiceLoader | `new({ role?, context?, spawn?, cancel?, wait?, clock?, log?, kind?, failFast? })`, `register`, `registerMany`, `resolveOrder` (Kahn, ties by name), `init`, `start`, `boot`, `stop(budget?) -> { stopped, timedOut, failed, elapsed }`, `getStatus(es)`, `getOrder`, `getServices`, `getLifecycle`, signal `ServiceFailed(name, phase, err)`. |
