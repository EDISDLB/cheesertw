# HULLDOWN — Technical Architecture Contract

> Status: **authoritative**. Every module in this repository must conform to this document.
> If an implementation needs to deviate, update this document in the same change and explain why.

HULLDOWN is an original Roblox armored-warfare game that reproduces the *systems depth* of a modern
tank MMO (garage → research → loadout → matchmaking → battle → results → economy) with original
branding, factions, vehicles, maps, art and audio. This document defines **how** the game is built.
Game design (what and why) lives in `docs/design/`, research in `docs/research/`.

---

## 1. Design pillars that drive the architecture

| Pillar | Architectural consequence |
|---|---|
| Information warfare (spotting) is core | **Custom replication.** The server never sends an enemy's state to a client whose team cannot see it. Vehicles are **not** Roblox physics assemblies in `Workspace`. |
| Fair, cheat-resistant combat | **Server-authoritative simulation.** Clients send *inputs* only (throttle, steer, aim point, fire). Movement, aiming, reload, ballistics, armor and damage all run on the server. |
| Depth must be testable | Gameplay rules live in **pure Luau modules** (`ReplicatedStorage/Shared`) that never touch Roblox services and run unchanged in Lune tests. |
| Live balancing | Every tunable lives in `Shared/Config` in **real-world units**; nothing is hard-coded in gameplay code. Live overrides can be patched at server boot. |
| Expandability | Data-driven content (vehicles, modules, maps, missions…) with a validating `ContentRegistry`; services are plug-ins loaded by a dependency-ordered `ServiceLoader`. |
| Roblox-native presentation | Procedural, modular part-based vehicles and maps built from the same data that drives simulation; LOD and pooling everywhere. |

---

## 2. Repository layout

The `src/` tree **mirrors the Roblox DataModel** so that string requires (`@game/...`) resolve
identically in Roblox, in Lune (via `.luaurc` alias `game -> ./src`) and in luau-lsp.

```
default.project.json            Rojo project (single build used for Hub, Battle and Dev places)
.luaurc                         strict mode + "@game" alias for tooling
selene.toml / hulldown.yml      lint config (Roblox globals std)
stylua.toml                     formatter config
rokit.toml                      pinned toolchain
scripts/check.sh                THE quality gate: fmt, lint, types, tests, build
src/
  ReplicatedFirst/              loading screen bootstrap (client)
  ReplicatedStorage/
    Shared/                     pure, deterministic, engine-agnostic logic + data (server AND client)
      Core/                     Signal, Trove, Log, RNG, Units, Freeze, TableUtil, MathUtil, Schema, Result, Clock
      Types/                    ALL cross-module data types (single source of truth): init.luau re-exports
                                Core, World, Adapters, Net, Service, Content, Battle, Profile domain modules
      Config/                   balance + content data (see §9)
      Net/                      remote registry, binary codecs, protocol constants
      Combat/                   ArmorGeometry, Ballistics, Penetration, Dispersion, DamageModel, HE, Fire
      Vehicle/                  VehicleSim, TurretSim, StatsCalculator, Blueprint (procedural vehicle blueprint), GunState
      Spotting/                 VisibilityModel (camo/view-range math), SpottingSystem (LOS-injected)
      Battle/                   BattleRules (capture, victory), Scoring, Medals, BattleTypes
      Progression/              ProfileSchema, Migrations, Transactions, ResearchGraph, Economy, Missions, Achievements, Crew
      Matchmaking/              Matchmaker (pure algorithm), PlatoonRules, Templates
      Security/                 RateLimiter, InputValidator
      Map/                      MapLayout helpers shared by builder, minimap and bots (lanes, zones, spawns)
      Assets/                   AssetManifest (generated) + AssetResolver
    Client/                     client-only code (controllers, UI, rendering, audio, VFX)
  ServerScriptService/
    Server/
      Main.server.luau          server bootstrap
      Services/                 Roblox-facing services (one folder per service)
      Adapters/                 thin wrappers over Roblox APIs implementing interfaces in Types (World, DataStore, MemoryStore, Teleport, Messaging, Marketplace)
      Battle/                   BattleInstance + systems (server-only orchestration of Shared logic)
  StarterPlayer/StarterPlayerScripts/
    ClientBootstrap.client.luau tiny: waits for game.Loaded then requires @game/ReplicatedStorage/Client/Main
tests/
  run.luau                      Lune test runner (custom loader injecting Roblox globals + mocks)
  Harness/                      Loader, Expect, Mocks (MockGame, MockDataStore, MockMemoryStore, MockPlayers...), HeightmapWorld, FakeClock
  Unit/  Integration/  Regression/   *.spec.luau suites mirroring src paths
tools/                          offline pipelines (Python/Lune/Node): icons, audio synthesis, music, map thumbnails, asset upload, balance report
assets/                         ORIGINAL source assets: brand/, icons/, audio/, music/, textures/ + manifest.json
docs/                           ARCHITECTURE (this), design/, research/, systems/, qa/, FINAL_REPORT
```

### 2.1 Places and server roles

One Rojo build is published to every place in the universe. `Shared/Config/Places.luau` maps
`game.PlaceId` → `{ role, mapId? }`. The server bootstrap decides which services start.

| Role | Where | Hosts |
|---|---|---|
| `Hub` | public servers of the Hub place (MaxPlayers 50) | Garage, profile (the **only** role that opens profile sessions), store and receipts, tech tree, missions, platoons, matchmaking queue + (leader-elected) global matchmaker, reward-inbox draining |
| `Battle` | reserved servers of the Battle place (MaxPlayers 32, access "Secure within universe only") | exactly one `BattleInstance` (Random, Training, Bootcamp, Practice, Event). v1 uses one Battle place and builds the map from `Content/Maps` at boot, before players arrive; `Places.luau` may later map per-map Battle places if join-time map replication proves too slow |
| `Dev` | Roblox Studio or any unmapped PlaceId | Hub **and** an in-process battle host; local matchmaking with bot fill; debug tools enabled for the developer |

Battle handoff (values in `docs/research/00-DECISIONS.md` §19):
1. Hub matchmaker → `TeleportService:ReserveServerAsync(battlePlaceId)` returns `(accessCode, privateServerId)`
   (`ReserveServer` is deprecated).
2. Match manifest (≤ 8 KB) written to the MemoryStore hash map `match` under key `<privateServerId>`: match id, mode,
   map, place, `mmType` (the Hub's `game.MatchmakingType`), roster with team, ticket and a compact **loadout snapshot**
   per human (taken by the Hub at enqueue while the vehicle is locked), bot seed and bot slots.
3. Each Hub teleports its own players with `TeleportOptions.ReservedServerAccessCode` (≤ 50 per `TeleportAsync`,
   5 attempts, 40 s deadline, then re-queue at the original `enqueuedAt`) and records `profile.activeBattle` for
   "Return to battle".
4. The battle server reads `match:<game.PrivateServerId>`. Access codes never expire, and reusing one starts a fresh
   empty server, so it **rejects stale codes**: if `PrivateServerId` is empty, `PrivateServerOwnerId ≠ 0`, the manifest
   is missing or tombstoned, or `game.MatchmakingType ≠ manifest.mmType`, everyone is sent back to the Hub. It admits
   only roster UserIds arriving from a Hub `SourcePlaceId`. Teleport data is **never** trusted. Slots still empty after
   the 45 s arrival window are played by bots.
5. Battle servers **never open profile sessions**: everything they need (roster, loadouts) is in the manifest, read-only.
   At battle end they append a reward entry keyed by battle id to each human's reward inbox (§7), tombstone the
   manifest (`{ended = true}`), and teleport players back to the Hub, where the results screen opens. The Hub applies
   inbox entries idempotently under its session lock (Dev: same flow in-process).

Place settings shared by every place (required in `default.project.json`, because several are NotScriptable or
PluginSecurity and scripts cannot set them): `Workspace.StreamingEnabled = false` for Hub and Battle in v1 (there is no character, so
streaming would need a server-side `ReplicationFocus` Part per player that leaks positions; client prediction and
445–564 m sightlines need the whole map, which is static and not secret; revisit only if the client memory gate in
00-DECISIONS §18 fails); characters off (`Players.CharacterAutoLoads = false`, nothing in `StarterGui`,
`Workspace.PlayerCharacterDestroyBehavior = Enabled`, `StarterPlayer.CreateDefaultPlayerModule = false`,
`EnableMouseLockOption = false`); `Lighting.LightingStyle = Realistic` with `PrioritizeLightingQuality = false`
(`Lighting.Technology` is deprecated and not scriptable; Rojo 7.4.4 needs explicit typed values for both);
`SoundService.DefaultListenerLocation = None`. Players.BanningEnabled and "Allow Third Party Teleports = off" are set in
Studio / Creator Dashboard.

---

## 3. Coding conventions (enforced by review + `scripts/check.sh`)

1. Every file starts with `--!strict`. luau-lsp (Roblox definitions, strict) must report **zero** diagnostics.
2. **Requires are strings only.** Cross-container: `require("@game/ReplicatedStorage/Shared/Core/Signal")`.
   Same subtree: relative `require("./Sibling")`, `require("../Folder/Module")`. Children of an `init.luau`
   module: `require("@self/Child")`. Remember: inside `Folder/init.luau`, `./X` means a **sibling of Folder**.
   Never use instance requires, `_G`, `shared`, or `getfenv`. The single exception is plug-in discovery in
   `Server/Main.server.luau` and `Client/Main.luau` (children of `Services/` / `Controllers/` are required through a
   local `dynamicRequire` alias). `tests/Regression/SourceConventions.spec.luau` enforces rules 1, 2, 3, 7, 9 and 10.
3. **Shared modules are pure**: no `game:GetService`, no `workspace`, no `task.wait`/`task.spawn`, no `os.clock()`/`tick()`.
   Time comes in as a `now: number` argument or an injected `Clock`. World queries come in through the `World`
   interface (`Types.World`). Randomness comes from `Core/RNG` (seeded, deterministic). This keeps them testable in Lune.
   Roblox *datatypes* (`Vector3`, `CFrame`, `Color3`, `UDim2`, `Enum`…) are allowed everywhere.
4. Units: config values are in **real-world units** — armor `mm`, distances `m`, speeds `km/h`, velocities `m/s`,
   angles `deg`, times `s`, mass `kg` or `t`, power `hp`. Convert at the boundary with `Core/Units`
   (`Units.STUDS_PER_METER = 3`: 1 stud = 1/3 m; a 7 m tank is 21 studs).
5. Data/config tables are deep-frozen (`Core/Freeze.deep`) after construction. Never mutate config at runtime.
6. Fallible operations return a `Result` (`{ ok = true, value = ... }` / `{ ok = false, err = "CODE", detail = ... }`) —
   see `Core/Result`. Error codes are `SCREAMING_SNAKE` strings listed in `Shared/Net/ErrorCodes.luau`. Never throw
   across a remote boundary; service handlers are wrapped in `pcall` by `NetServer`.
7. Logging: `local log = Log.scope("CombatService")`; `log:info/warn/error/debug(fmt, ...)`. No bare `print` in `src/`
   (tests/tools may print). Debug level is off in production.
8. Names: modules/types `PascalCase`, functions/locals `camelCase`, constants `SCREAMING_SNAKE`, private fields `_prefixed`.
   One module per file. Folder modules use `init.luau`.
9. Every module has a header comment: **Purpose, Dependencies, State, Validation, Error handling, Performance notes**
   (one line each is fine for small modules).
10. Every Shared module has a spec in `tests/Unit/<same path>/<Module>.spec.luau` (folder modules:
    `<Folder>/<Folder>.spec.luau`; type-only and data-only modules without functions are covered by their
    consumers). Server services get integration specs using mocks. Bugs get a regression spec in `tests/Regression/`.
11. Performance: no per-frame table allocation in hot loops (sim, projectiles, spotting, rendering); reuse buffers;
    use `--!native` only on proven hot math modules; stagger expensive work across ticks.
12. Formatting: StyLua (tabs, 120 cols). Lint: Selene clean.

---

## 4. Core library (Shared/Core) — exact APIs

These are the only general-purpose utilities. Do not create alternatives elsewhere.

```lua
-- Signal.luau
Signal.new<T...>(): Signal<T...>
signal:Connect(fn: (T...) -> ()): Connection        -- Connection: { Connected: boolean, Disconnect: (self) -> () }
signal:Once(fn): Connection
signal:Fire(...: T...)                               -- synchronous, safe against disconnect-during-fire
signal:Wait(): T...                                  -- coroutine-based; only in Roblox runtime code
signal:DisconnectAll()

-- Trove.luau  (cleanup bag)
Trove.new(): Trove
trove:Add<T>(obj: T, cleanupMethod: string?): T      -- functions, Instances (:Destroy), connections (:Disconnect), tables with Destroy/Disconnect, threads
trove:Connect(signal, fn): Connection                -- works with Signal and RBXScriptSignal
trove:Extend(): Trove                                -- child trove cleaned with parent
trove:Remove(obj): boolean
trove:Clean()   trove:Destroy()

-- Log.luau
Log.scope(name: string): Logger                      -- logger:debug/info/warn/error(fmt: string, ...any)
Log.setLevel(level: "debug"|"info"|"warn"|"error")
Log.setSink(fn: (level, scope, message) -> ())       -- tests capture logs; default sink prints/warns

-- RNG.luau  (deterministic PCG32; identical sequences in Roblox and Lune)
RNG.new(seed: number): RNG
rng:nextU32(): number   rng:next(): number [0,1)   rng:range(min, max): number   rng:int(min, max): number (inclusive)
rng:normal(mean, stddev): number   rng:truncatedNormal(mean, stddev, limitSigma): number
rng:chance(p): boolean   rng:pick<T>(list: {T}): T   rng:shuffle<T>(list: {T})   rng:fork(salt: number): RNG
RNG.hash(...: number|string): number                 -- stable 32-bit hash for seeding

-- Units.luau
Units.STUDS_PER_METER = 3
Units.mToStuds(m)  Units.studsToM(s)  Units.kmhToStudsPerSec(kmh)  Units.studsPerSecToKmh(v)
Units.mpsToStudsPerSec(mps)  Units.degToRad(d)  Units.radToDeg(r)  Units.GRAVITY_MPS2 = 9.81

-- Freeze.luau      Freeze.deep<T>(t: T): T  (idempotent; returns same table)
-- TableUtil.luau   copy, deepCopy, deepEqual, merge, keys, values, count, filter, map, find, diff(old,new)->{Patch}, applyPatches
-- MathUtil.luau    clamp, lerp, inverseLerp, remap, approach(current,target,maxDelta), angleDiffDeg, wrapDeg, smoothDamp, round(n, step), expDecay
-- Schema.luau      runtime validators for remote args & content:  Schema.number({min,max,integer}), string({maxLen,pattern}), boolean, enum({...}),
--                  vector3({maxMagnitude}), optional(s), array(s,{maxLen}), map(k,v,{maxLen}), struct({...}), oneOf(...), literal(v), any
--                  validator(value) -> (ok: boolean, err: string?)   Schema.check(validator, value) -> Result
-- Result.luau      Result.ok(v), Result.err(code, detail?), Result.isOk(r)
-- Clock.luau       Clock.real() -> Clock (wraps os.clock, Roblox-only usage),  Clock.fake(start) -> FakeClock (tests: :advance(dt))
--                  type Clock = { now: (self) -> number }
```

`Shared/Types` (folder: `init.luau` + one module per domain) exports every cross-module type (content definitions,
profile, battle entities, net packets, World interface, adapters). Modules import types with
`local Types = require("@game/ReplicatedStorage/Shared/Types")` and `type VehicleDefinition = Types.VehicleDefinition`.
Domain modules only require other `Types/*` modules, so they can never form require cycles with implementations.
Additive helpers beyond the list above (e.g. `RNG.new(seed, stream?)`, `rng:getState()`, `Signal.is`,
`TableUtil.sortedKeys`, `MathUtil.approachAngleDeg`, `Schema.buffer/instance`, `Result.unwrap`, `Clock.wall`) are
documented in `docs/systems/foundation.md`.

---

## 5. Server framework

### 5.1 ServiceLoader

```lua
-- A service module returns a table:
local MyService = {
    Name = "MyService",
    Roles = { "Hub", "Dev" },          -- which server roles start it
    Dependencies = { "DataService" },  -- started after these
}
function MyService:Init(ctx: Types.ServiceContext) end   -- wire state, create remotes; MUST NOT yield
function MyService:Start() end                            -- begin work; may spawn threads
function MyService:Stop() end                             -- optional; called on BindToClose (reverse order)
return MyService
```
`ServiceContext = { role, services: {[string]: any}, net: NetServer, config: Config, log: Logger, clock: Clock, adapters: Adapters, isStudio: boolean, server: ServerInfo, lifecycle: Lifecycle }`
(`log` is scoped to the service name; `server` = PlaceId/JobId/PrivateServerId; `lifecycle` = read-only loader view
used by HealthService). An Init that errors or yields marks the service `Failed` and skips its dependents (degraded
boot, surfaced by HealthService); missing dependencies and cycles abort the boot.
`ServerScriptService/Server/Main.server.luau` discovers `Services/*` modules, filters by role, topologically sorts by
`Dependencies` (cycle = boot error), calls `Init` in order, then `Start` in order (each in its own thread, errors logged
and surfaced to the `HealthService`). `game:BindToClose` → `Stop` in reverse order with a 25 s budget.

### 5.2 Networking (Shared/Net)

* `Net/Remotes.luau` is the **single registry** of every remote:
  `{ name, kind = "Event"|"Unreliable"|"Function", direction = "C2S"|"S2C", rate = {perSecond, burst}?, args = {Schema validators}? }`.
* `NetServer` (Server) creates instances in `ReplicatedStorage.Remotes` at boot; for every C2S remote it enforces:
  token-bucket rate limit per player per remote → schema validation of every argument → `pcall` around the handler.
  Violations are reported to `AntiExploitService:strike(player, reason, weight)`; they never reach handlers.
* `NetClient` (Client) waits for the remotes folder and exposes typed `fire/invoke/on`.
* High-frequency traffic uses **binary codecs** in `Net/Codecs/*` (Luau `buffer`) over `UnreliableRemoteEvent`
  (payload ≤ 900 bytes, a margin under the engine's 1,000-byte drop limit; split if needed): `InputPacket` (C2S 30 Hz,
  ≤ 64 B, carries last 3 inputs for loss tolerance) and `SnapshotPacket` (S2C 20 Hz, per-observer filtered).
  Everything else is reliable `RemoteEvent`. Every C2S remote declares a token bucket in the registry (budgets in
  00-DECISIONS §19); the engine's ≈ 500 requests/s per client is a ceiling, not a control. Number validators reject
  NaN/±inf (`math.isfinite`). Target bandwidth per client: ≤ 20 KB/s average, ≤ 40 KB/s peak S2C, ≤ 3 KB/s C2S.
* Request/response from client uses `Function` remotes **C2S only** (server never invokes clients). Every mutating
  request carries a client-generated `requestId` (string ≤ 40) for idempotency.
* Profile replication: `DataSync` sends a full sanitized profile view on join, then `ProfilePatch` lists produced by
  `TableUtil.diff(old, new)` after each committed transaction. The client store applies patches in order (sequence numbers; gap ⇒ request full resync).

### 5.3 Adapters (dependency injection)

All Roblox platform calls that tests must fake go through adapters defined as types in `Types.luau` and implemented in
`Server/Adapters`: `World` (raycasts/ground/LOS on the map), `DataStoreAdapter`, `MemoryStoreAdapter`, `MessagingAdapter`,
`TeleportAdapter` (`ReserveServerAsync`, `TeleportAsync`), `MarketplaceAdapter` (`BindReceiptHandler`, subscription
status), `PlayersAdapter`. Tests use `tests/Harness/Mocks/*` with failure injection. `RobloxWorld` builds its
`RaycastParams` with `IncludeInstances`/`ExcludeInstances` (they supersede `FilterDescendantsInstances`).

---

## 6. Battle simulation (server-authoritative, custom replication)

### 6.1 Entities and the tick

`Server/Battle/BattleInstance` owns a battle: map, teams, `vehicles: {[VehicleId]: VehicleEntity}`, projectiles,
capture zones, timers, stats, an `RNG` seeded from the match id, and a `World` adapter. It is driven by a fixed-step
accumulator at **30 Hz** (`Config.Battle.TICK_RATE`). Tick order:

1. **Inputs** — apply the latest validated `InputCommand` per vehicle (players via `InputPacket`, bots via `BotBrain`).
2. **Vehicle simulation** — `Shared/Vehicle/VehicleSim.step(state, input, stats, world, dt)` (kinematic tracked-vehicle
   model: power-to-weight acceleration, terrain resistance, slope, hull traverse, pivot, ground-fit pitch/roll from track
   contact samples, static-obstacle collision via world casts, falling + fall damage, water depth/drowning, overturn).
   Vehicle–vehicle collision + ramming damage is resolved by `Server/Battle/Systems/CollisionSystem` (oriented boxes).
3. **Turret & gun** — `TurretSim` rotates turret/gun toward the aim point within traverse speed and limits
   (yaw arcs for casemate TDs, depression/elevation incl. rear depression), `GunState` advances reload/magazines/specials.
4. **Aiming** — `Dispersion` updates the server-side aiming circle from movement/rotation/shots.
5. **Projectiles** — `ProjectileSystem` steps ballistic shells (gravity per shell, max range; a swept segment per
   tick, so no sub-stepping), casts against the map
   (`World:raycast`) and vehicle armor (`ArmorGeometry` in each vehicle's local space, broadphase by bounding sphere),
   resolves hits with `Penetration` + `DamageModel` (sequential armor layers, spaced armor, ricochet continuation,
   overmatch, normalization, post-penetration module/crew path, HE splash).
6. **Damage over time & effects** — fire, module repair timers, crew injury effects, consumable cooldowns/durations.
7. **Spotting** — `SpottingSystem` (staggered pair checks, proximity, view range, camo, foliage via LOS query, firing
   penalties, signal-range relay, spotted timers, last-known positions).
8. **Objectives** — `BattleRules` capture progress/reset, victory/defeat/draw evaluation, timer.
9. **Replication** — per observer: own vehicle (full state + `lastProcessedInputTick`), allies (always), enemies only if
   spotted by the observer's team (full state within 564 m, minimap-only records at 2 Hz beyond); reliable event stream
   (`ShotFired`, `ShotResult`, `ModuleEvent`, `VehicleDestroyed`, `Spotted/Unspotted`, `CaptureUpdate`, `ChatCommand`…).
   Shots by enemies the observer's team cannot see never reveal the shooter: they arrive as an anonymous `ShotHeard`
   (calibre class, position snapped to 50 m with bearing noise) and a tracer for only the last ≤ 100 m of flight.

`VehicleEntity` holds: definition id, resolved loadout + computed `VehicleStats`, sim state, turret state, gun state,
ammo counts, HP, modules `{[ModuleKind]: {hp, maxHp, state = "Ok"|"Damaged"|"Destroyed", repairT}}`, crew
`{[slot]: {role(s), injured}}`, fire state, consumables, spotting state, camo state, battle stats, damage ledger
(who damaged whom — for assists and rewards), controller (`Player` | `Bot`), connection state.

### 6.2 Client prediction

The owning client runs the **same** `VehicleSim`/`TurretSim` on its own inputs against a Roblox `World` adapter over the
same map geometry, keeps an input history, and reconciles when a snapshot with `lastProcessedInputTick` arrives
(reset to server state, replay unacknowledged inputs, smooth the visual error). Remote vehicles are interpolated
100 ms behind. Shots: the shooter sees a predicted muzzle flash immediately; tracers/impacts come from server events.

### 6.3 Models and rendering

`Shared/Vehicle/Blueprint` turns a vehicle's `VisualSpec` + armor data into a **Blueprint**: a list of primitives
(block, wedge, corner-wedge, cylinder, prism) with group (Hull/Turret/Gun/TrackL/TrackR/Wheels), layer
(`Armor`|`Module`|`Visual`|`Detail`), material, color, and for armor/module primitives their thickness/zone or module kind,
plus pivots (turret ring, gun trunnion, muzzle, view point, camo points, exhausts, track contact points).
* Server: builds `ArmorGeometry` (convex polyhedra with per-face thickness/zone/spaced flag) and module volumes from
  the blueprint — **no Instances**.
* Client: `Client/Render/VehicleRenderer` builds Roblox models from the same blueprint (one template per vehicle
  definition and LOD tier, cloned per entity) with customization (paint/camo/emblem/inscription). Each vehicle model has
  **one anchored, invisible, non-colliding root part**; the active LOD model is welded to it, the turret and gun hang on
  `Motor6D` joints (write `Transform`, fallback `C0`), and every visible root is moved by a single
  `workspace:BulkMoveTo(roots, cframes, Enum.BulkMoveMode.FireCFrameChanged)` per frame. Visual parts are massless with
  `CanCollide`/`CanQuery`/`CanTouch` off and live under a client-created `Workspace.ClientVehicles` folder (they never
  stream out and never replicate). LOD by camera distance ÷ zoom with 10 % hysteresis; a switch reparents one tier
  model: LOD0 ≤ 400 parts (< 150 studs; at most 4/3/2 vehicles on High/Medium/Low), LOD1 ≤ 80 parts (≤ 600 studs),
  LOD2 ≤ 16 parts (≤ 2,400 studs), LOD3 = 2-D marker only. Budgets: ≤ 3,000 rendered vehicle parts on PC, ≤ 1,500 on
  mobile; full table in 00-DECISIONS §18. Markers are one pooled screen-space overlay, not per-vehicle `BillboardGui`s.
* Armor Inspector uses `ArmorGeometry` + `Penetration` to show thickness, effective thickness and outcome at the cursor.

### 6.4 The World interface (`Types.World`)

```lua
type World = {
  raycast: (self, origin: Vector3, direction: Vector3, mode: "Shell"|"Sight"|"Ground") -> WorldHit?,  -- map only
  groundAt: (self, x: number, z: number, fromY: number) -> WorldHit?,
  sweepBox: (self, cframe: CFrame, size: Vector3, displacement: Vector3) -> WorldHit?,   -- static obstacles
  sightLine: (self, from: Vector3, to: Vector3) -> SightResult,  -- { blocked: boolean, foliage: number (summed concealment), smoke: boolean }
  waterDepthAt: (self, position: Vector3) -> number,
  destroyObject: (self, objectId: string) -> (),  -- destructibles
}
WorldHit = { position: Vector3, normal: Vector3, distance: number, material: string, objectId: string?, destructible: boolean }
```
`Server/Adapters/RobloxWorld` implements it with `workspace:Raycast/Blockcast` over the map folder + Terrain using
collision groups and attributes (`Destructible`, `Water`). `groundAt` is a bilinear lookup in a heightfield `buffer`
baked from the map's terrain recipe (1 sample per 2 studs; structures and bridges fall back to a raycast), and the
foliage/smoke part of `sightLine` is evaluated **analytically** from the map's authored concealment volumes (a 16 m
grid of spheres/capsules), never from engine geometry, so client graphics settings cannot change spotting.
`tests/Harness/HeightmapWorld` implements the same interface analytically (heightfield + boxes + the same foliage
volumes) so whole battles run headless in Lune. Budget: ≤ 600 world queries per 30 Hz tick.

---

## 7. Garage, progression and economy

* `Shared/Progression/ProfileSchema` defines profile **v1** + `Migrations` (each migration `vN -> vN+1`, pure, tested).
* `Shared/Progression/Transactions` implements every economic action as a **pure function**
  `(profile, args, content, now) -> Result<{ profile: Profile, events: {DomainEvent} }>` operating on a copy:
  purchase/sell vehicle, research module/vehicle (vehicle XP then free XP), mount module/equipment/ammo/consumables,
  convert XP, train/retrain crew, learn perk, buy/apply customization, claim mission/achievement reward,
  store purchase (garage slots are unlimited, so there is no slot purchase). Validation errors use codes from
  `Net/ErrorCodes`.
* Server `ProgressionService` resolves the player's session profile, runs the transaction, commits via `DataService`,
  publishes the domain events (to Missions/Achievements/Notifications) and lets `DataSync` patch the client.
* `Shared/Battle/Scoring` turns a battle ledger into per-player XP/credits/crew XP/free XP plus the results-screen ledger
  lines with the economy config. It runs on the **battle server**, which cannot touch profiles: it appends one entry
  `{battleId, issuedAt, rewards, stats}` per human to the DataStore `RewardInbox_v1`, key `u_<UserId>` (`UpdateAsync`,
  ≤ 20 entries, no-op if the battle id is already there) **before** teleporting players back.
* `RewardService` runs **in the Hub only**, under the session lock: on profile load and every 30 s while
  `profile.pendingBattles` is non-empty it reads the inbox fresh, applies each entry whose battle id is not in
  `profile.processed.battles` (ring of 200), unlocks the vehicle and records battle history, **saves the profile**, and
  only then removes the consumed inbox entries. A crash between steps is safe because the ring makes re-application a
  no-op. Vehicles locked for a battle that never reports are unlocked after 30 min.

### Data persistence (`DataService`, Hub and Dev only)
Session-locked profiles (ProfileStore-style) on `DataStoreAdapter`, store `Profiles_v1`, key `Player_<UserId>`. The lock
lives in the value as `MetaData.ActiveSession = {placeId, jobId, sessionGuid, at}` and every write goes through
`UpdateAsync`, which re-checks `sessionGuid` (a server whose lock was stolen aborts and kicks its copy). Autosave every
60 s with a random first offset; save + release on leave; on a conflicting lock send a MessagingService release request,
retry at 5 s then every 10 s and steal after 40 s; a lock not refreshed for 300 s is taken immediately. Per-key serial
write queue with exponential backoff and budget awareness (`GetRequestBudgetForRequestType`), `BindToClose` parallel
flush within 25 s, schema migration on load, `validateAndRepair` for corrupted/partial data, kick-with-message after
120 s of failed loading (never play on a default profile that could overwrite real data). Battle servers never open
sessions. Idempotency rings: `processed.receipts` (200 purchase ids), `processed.battles` (200), `requestId` (last 50
per session).

### Purchases
Developer products are granted by `MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, handler)`
in the Hub, with a `ProcessReceipt` fallback that returns `NotProcessedYet`; Battle places bind a handler that always
returns `NotProcessedYet` (the receipt is redelivered in the Hub) and hide the experience shop. The handler waits for the
profile, runs the `Transactions` grant and records the `PurchaseId` in **one** `UpdateAsync`, and returns
`Enum.ReceiptDecision.Processed` only after that write succeeds (one receipt can be processed on two servers at once).
Prices use Managed Pricing: the client displays `GetProductInfoAsync` prices and never hard-codes Robux amounts.
Subscription status (HULLDOWN Plus) is read on the server (`GetUserSubscriptionStatusAsync`,
`Players.UserSubscriptionStatusChanged`). No paid random items.

---

## 8. Matchmaking

* `Shared/Matchmaking/Matchmaker` is a **pure** algorithm: `(tickets, now, config, rng) -> { matches, remaining }`.
  Tickets: `{ ticketId, members: {userId}, platoonId?, vehicle: {defId, tier, class, role}, mode, region, mmType,
  hubJobId, enqueuedAt }`, where `mmType` is the Hub's `game.MatchmakingType`. Pools are keyed by
  `(mode, regionBucket, mmType)`; `mmType` is never relaxed, because cross-play-disabled console players cannot share a
  server with others. It honors team size (15v15), tier spread & templates, class mirroring/limits, platoon
  constraints, wait-time relaxation and **bot fill** for low population.
* Hub `QueueService` stores tickets in MemoryStore sorted maps (one per bucket; TTL 120 s refreshed every 30 s with a
  state-guarded `UpdateAsync`), a leader-elected `MatchmakerService` (hash-map lease with a 15 s TTL) runs the algorithm
  every 3 s, claims tickets atomically (state Q → M), reserves battle servers (`ReserveServerAsync`), writes manifests
  (≤ 8 KB) and assignment records, and notifies hubs via `MessagingAdapter` (best effort: hubs also poll their
  assignments); hubs teleport their players (`TeleportAdapter`) with retry → requeue on failure.
* MemoryStore is small at low CCU (memory 64 KB + 1.2 KB × users; 1,000 + 120 × CCU request units per minute), hence
  the 8 KB manifest cap, short TTLs, explicit removal and an index of non-empty buckets (empty scans still cost).
* Dev role: the same algorithm runs in-process and starts a local `BattleInstance`.

---

## 9. Configuration & content (Shared/Config)

```
Config/
  init.luau            aggregates + freezes everything; applies LiveOverrides (validated, read once per battle from
                       Experience Configs so values never change mid-battle) on the server
  Places.luau          PlaceId -> { role, mapId? }
  Battle.luau          tick rate, timers, team size, capture rules, victory rules, snapshot rates
  Combat.luau          penetration/normalization/ricochet/overmatch rules, RNG ranges, HE/HEAT rules, fire, ramming, fall damage
  Spotting.luau        view range cap, proximity radius, check intervals, camo rules, foliage, firing penalties, spotted timers
  Movement.luau        terrain resistance by material, slope limits, water/drowning, overturn rules
  Economy.luau         reward formulas, costs multipliers, premium account multipliers, free-XP share, repair/ammo pricing
  Progression.luau     account levels, crew XP curves, skill costs
  Matchmaking.luau     templates, spreads, class limits, relaxation schedule, bot fill policy
  Audio.luau / Vfx.luau  mix buses, distance bands, pool sizes (client tunables)
  Content/
    Factions.luau  Classes.luau  Roles.luau  Tiers.luau
    Shells.luau  Guns/  Turrets/  Engines/  Tracks/                 (modules may be shared across vehicles; no radio module)
    Vehicles/<Faction>/<VehicleId>.luau                              (one file per vehicle)
    TechTree.luau  (branches & unlock edges; validated as a DAG)
    Equipment.luau  Consumables.luau  CrewSkills.luau  Customization.luau
    Missions.luau  Achievements.luau  Store.luau  Events.luau  BattlePass.luau
    Maps/<MapId>.luau                                                (layout, terrain recipe, props, lanes, zones, spawns, weather, audio)
  ContentRegistry.luau   indexes everything by id, cross-validates references at boot and in tests
```
`ContentRegistry.validate()` must pass in tests: every reference resolves, tech tree is a DAG reachable from tier-I roots,
every vehicle has a stock + top configuration within load limits, every icon/sound key exists in the asset manifest
(or has a declared fallback), every map has valid spawns/zones/lanes for every class.

---

## 10. Client architecture (ReplicatedStorage/Client)

```
Client/
  Main.luau                     boots controllers (same ServiceLoader pattern: Init/Start, Dependencies)
  Controllers/                  Input, Camera, Vehicle (prediction/interp), Battle, Garage, Audio, Effects, Lod,
                                Minimap, Settings, Notification, Social, Tutorial, Debug
  State/                        ClientStore: ProfileView (patched), BattleView, Settings, Session — built on UI/Kit/State
  UI/
    Kit/                        Create (declarative instances), State (Value/Computed/Observer), Theme (tokens),
                                Router (screen stack + transitions), Focus (gamepad navigation), InputMode, Layout (responsive/UIScale),
                                Components/ (Button, IconButton, Tab, Panel, Modal, Tooltip, Toast, ProgressBar, StatBar, Slider,
                                Toggle, Dropdown, VirtualList, CurrencyLabel, VehicleCard, Icon, Badge…)
    Icons/                      Icon registry: asset image when uploaded, otherwise vector "glyph" built from GUI primitives
    Screens/                    MainMenu, Garage, Carousel, TechTree, Research, Crew, Equipment, Ammo, Consumables, Exterior,
                                Missions, Achievements, Store, Profile, Settings, Platoon, Compare, ArmorInspector, Notifications,
                                BattleLoading, Countdown, BattleHUD/*, RadialMenu, Results/*, Tutorial
  Render/                       VehicleRenderer, HangarScene, MapEnvironment (lighting/weather), Markers
  Audio/                        AudioEngine (buses, voices, priority, ducking, distance variants, occlusion), Banks
  Effects/                      pooled VFX (muzzle, tracer, impacts, ricochet, fire, smoke, explosion, dust, tracks, wrecks)
```
* UI is code-built (no Studio-authored GUIs), themed by `Theme` tokens only (no literal colors in screens). Tokens come
  from `docs/design/brand-art.md`; engine StyleSheets are not used in v1 (Lune cannot evaluate them). Root
  `UIScale = clamp(viewportHeight / 1080, 0.75, 1.5)` (× 1.25 on TV); the Compact layout is chosen by viewport height
  < 600 px; no `TextScaled` on body text, so `PreferredTextSize` works.
* Every interactive element is reachable by gamepad (Focus groups, explicit NextSelection where needed) and touch.
* **Input** uses the Input Action System only (`InputContext` → `InputAction` → `InputBinding`, contexts Battle, Sniper,
  Menu, Spectate, Garage; on-screen buttons bind through `InputBinding.UIButton`). `InputMode`
  (`MouseKeyboard`|`Gamepad`|`Touch`) follows `UserInputService.PreferredInput` and switches prompts/glyphs
  (`GetImageForKeyCode`) and the mobile battle layout. Reserved inputs are never bound: Esc/ButtonStart, F9, F11, F12,
  PrintScreen. No `ContextActionService` touch buttons.
* **Camera**: `CameraType.Scriptable`, one `BindToRenderStep` at `Enum.RenderPriority.Camera.Value + 1`; there are no
  characters, so the default PlayerModule controls are off.
* **Audio**: `Audio/AudioEngine` builds the graph client-side with the modular Audio API only — `AudioPlayer` →
  `AudioEmitter`/`AudioListener` → `Wire` → per-bus `AudioFader` (+ `AudioFilter`, `AudioEqualizer`, sidechain
  `AudioCompressor`) → master `AudioCompressor` → `AudioLimiter` → `AudioDeviceOutput`; never `Sound`/`SoundGroup`.
  Buses follow `docs/design/audio.md` (3-D buses are listeners on the camera grouped by `AudioInteractionGroup`);
  pooled voices with a 32-voice budget (20 on mobile) and priority stealing; every loop is owned by an entity scope;
  speed-of-sound delays and music quantisation use `Play(atTime)` against `SoundService:GetMixerTime()`; acoustic
  simulation is off in v1 (raycast occlusion instead). The server never plays SFX.
* Accessibility settings (colorblind schemes from brand-art §3.4, UI scale, text scale, reduced effects, subtitles,
  audio sliders, camera and aim sensitivity) are read through `Settings` and applied centrally (Theme, Layout, Effects,
  AudioEngine).

---

## 11. Assets pipeline

Original source assets live in `assets/`. `tools/` scripts render SVG → PNG, synthesize audio/music → OGG, render map
thumbnails from map data, and upload via Roblox Open Cloud (`tools/upload_assets`, API key from env, never committed),
writing `assets/manifest.json` and the generated `Shared/Assets/AssetManifest.luau`. At runtime `AssetResolver`
returns the uploaded id or a declared fallback (vector glyph icons; silent + one-time warning for sounds). No ripped or
third-party game assets anywhere.

---

## 12. Security model

* Client sends only: bounded inputs (throttle/steer ∈ [-1,1], unit aim direction or bounded aim point), fire requests
  (validated against server reload/ammo/alive/gun state), UI requests (validated, rate-limited, idempotent).
* Speed/teleport/fly/noclip are impossible by construction (server simulates movement); damage/penetration/target
  spoofing impossible (server computes ballistics); reload bypass impossible (server `GunState`).
* Economy: all mutations via `Transactions` on the server with validation + idempotency; purchases via
  `BindReceiptHandler` in the Hub, idempotent by `PurchaseId`; rewards idempotent by battle id through the reward inbox;
  no client-supplied amounts are ever trusted.
* Characters are disabled in every place, which removes the character fly/noclip/fling and network-ownership exploit
  classes. Battle places accept only server-initiated teleports ("Secure within universe only") and reject stale or
  foreign access codes (§2.1).
* `AntiExploitService` aggregates strikes (rate-limit, schema failures, impossible requests) → warn/kick thresholds,
  structured logs. Debug remotes reject non-developers (`Config.DevAccess`) and are disabled outside Studio unless the
  user is allow-listed.

---

## 13. Testing standard

* `lune run tests/run.luau [-- filter]` runs all `*.spec.luau` files with a custom loader that resolves string
  requires (`@game`, `@tests`, relative, `@self`) and injects Roblox datatypes (from `@lune/roblox`) plus mocks (`game`,
  services, `Instance.new` -> MockInstance with loopback remotes). Specs mirror src paths:
  `tests/Unit/ReplicatedStorage/Shared/Core/Signal.spec.luau`, `tests/Integration/ServerScriptService/Server/...`.
* Required coverage: every Shared module (unit), every server service with logic beyond plumbing (integration with
  mocks), headless end-to-end battle (bots on `HeightmapWorld` → results → rewards → profile → research), data QA
  (join/leave/rejoin/shutdown/DataStore failure/duplicate reward/purchase/corrupted data), matchmaker QA
  (1, 2, 5, 10, 15, 29, 30, 31, 60, 100 players, platoons, leaves, timeouts), combat edge cases, and regression
  specs derived from `docs/research/07-qa-regression-catalogue.md`.
* **Must-pass invariants.** `tests/Harness/Invariants.check(battle)` runs after every tick of every headless battle and
  soak and fails on: any NaN/±inf in vehicle, projectile or capture state; hp outside [0, maxHp], invalid module state,
  negative ammo or reload; hull below ground − 0.05 m unless falling, or outside map bounds; an observer's snapshot or
  event stream carrying an enemy that the observer's team does not see (full state only when team-visible and ≤ 564 m;
  never an unspotted enemy's identity or exact position); damage-ledger sum ≠ HP lost; capture progress outside
  [0, 100]; input accepted from a destroyed vehicle or after the battle ended. The client harness asserts no voices or
  effects remain on destroyed entities and the voice count stays within budget.
* **P0 (every commit, inside `scripts/check.sh`, < 3 min):** all headless Data/Persistence, Net/Security,
  Armor/Penetration, Results/Rewards and Transactions specs, including: no C2S remote carries damage, HP, hit results,
  rewards, currency or positions (REG-NET-03); schema fuzzing (NaN, inf, huge strings, deep tables); armor
  watertightness (10,000 rays per configuration, 0 leaks); the same battle id or `PurchaseId` applied twice, even
  concurrently, changes the profile once; a failed load never writes; a stolen lock rejects the old server's saves;
  `BindToClose` finishes within 25 s; `MatchmakingType` is never mixed; determinism (`seed + input log + content hash`
  reproduces the event-stream hash, so Shared code never reads wall-clock time and iterates entities in sorted order).
  Nightly (P1): 30-bot soaks on every map with zero stuck events, map scanners, 100k-case fuzzing. Per release (P2): UI,
  audio and device checklist.
* `scripts/check.sh` must pass before every commit. Reports must state honestly what was tested headlessly vs what
  requires in-engine verification (the list lives in `docs/research/00-DECISIONS.md` §22).
