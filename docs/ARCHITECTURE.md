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
      Types.luau                ALL cross-module data types (single source of truth)
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
`game.PlaceId` → role. The server bootstrap decides which services start.

| Role | Where | Hosts |
|---|---|---|
| `Hub` | public servers of the Hub place | Garage, profile, store, tech tree, missions, platoons, matchmaking queue + (leader-elected) global matchmaker |
| `Battle` | reserved servers of the Battle place | exactly one `BattleInstance` (Random, Training, Bootcamp, Practice, Event) |
| `Dev` | Roblox Studio or any unmapped PlaceId | Hub **and** an in-process battle host; local matchmaking with bot fill; debug tools enabled for the developer |

Battle handoff: Hub matchmaker → `TeleportService:ReserveServer(battlePlaceId)` returns
`(accessCode, privateServerId)` → match manifest stored in MemoryStore under
`match:<privateServerId>` → players teleported with `TeleportOptions.ReservedServerAccessCode`.
The battle server reads `match:<game.PrivateServerId>`; teleport data from clients is **never** trusted.
After results, players are teleported back to the Hub (Dev: returned to the garage in-process).

---

## 3. Coding conventions (enforced by review + `scripts/check.sh`)

1. Every file starts with `--!strict`. luau-lsp (Roblox definitions, strict) must report **zero** diagnostics.
2. **Requires are strings only.** Cross-container: `require("@game/ReplicatedStorage/Shared/Core/Signal")`.
   Same subtree: relative `require("./Sibling")`, `require("../Folder/Module")`. Children of an `init.luau`
   module: `require("@self/Child")`. Remember: inside `Folder/init.luau`, `./X` means a **sibling of Folder**.
   Never use instance requires, `_G`, `shared`, or `getfenv`.
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
10. Every Shared module has a spec in `tests/Unit/<same path>/<Module>.spec.luau`. Server services get integration
    specs using mocks. Bugs get a regression spec in `tests/Regression/`.
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

`Shared/Types.luau` exports every cross-module type (content definitions, profile, battle entities, net packets, World
interface, adapters). Modules import types with `local Types = require("@game/ReplicatedStorage/Shared/Types")` and
`type VehicleDefinition = Types.VehicleDefinition`.

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
`ServiceContext = { role, services: {[string]: any}, net: NetServer, config: Config, log: Logger, clock: Clock, adapters: Adapters, isStudio: boolean }`.
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
  (payload ≤ 900 bytes; split if needed): `InputPacket` (C2S 30 Hz, carries last 3 inputs for loss tolerance) and
  `SnapshotPacket` (S2C 20 Hz, per-observer filtered). Everything else is reliable `RemoteEvent`.
* Request/response from client uses `Function` remotes **C2S only** (server never invokes clients). Every mutating
  request carries a client-generated `requestId` (string ≤ 40) for idempotency.
* Profile replication: `DataSync` sends a full sanitized profile view on join, then `ProfilePatch` lists produced by
  `TableUtil.diff(old, new)` after each committed transaction. The client store applies patches in order (sequence numbers; gap ⇒ request full resync).

### 5.3 Adapters (dependency injection)

All Roblox platform calls that tests must fake go through adapters defined as types in `Types.luau` and implemented in
`Server/Adapters`: `World` (raycasts/ground/LOS on the map), `DataStoreAdapter`, `MemoryStoreAdapter`, `MessagingAdapter`,
`TeleportAdapter`, `MarketplaceAdapter`, `PlayersAdapter`. Tests use `tests/Harness/Mocks/*` with failure injection.

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
5. **Projectiles** — `ProjectileSystem` steps ballistic shells (gravity per shell, max range), casts against the map
   (`World:raycast`) and vehicle armor (`ArmorGeometry` in each vehicle's local space, broadphase by bounding sphere),
   resolves hits with `Penetration` + `DamageModel` (sequential armor layers, spaced armor, ricochet continuation,
   overmatch, normalization, post-penetration module/crew path, HE splash).
6. **Damage over time & effects** — fire, module repair timers, crew injury effects, consumable cooldowns/durations.
7. **Spotting** — `SpottingSystem` (staggered pair checks, proximity, view range, camo, foliage via LOS query, firing
   penalties, signal-range relay, spotted timers, last-known positions).
8. **Objectives** — `BattleRules` capture progress/reset, victory/defeat/draw evaluation, timer.
9. **Replication** — per observer: own vehicle (full state + `lastProcessedInputTick`), allies (always), enemies only if
   spotted by the observer's team; reliable event stream (`ShotFired`, `ShotResult`, `ModuleEvent`, `VehicleDestroyed`,
   `Spotted/Unspotted`, `CaptureUpdate`, `ChatCommand`…).

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
* Client: `Client/Render/VehicleRenderer` builds Roblox models from the same blueprint (cached per vehicle definition,
  cloned per entity), with LOD tiers (Detail layer culled first) and customization (paint/camo/emblem/inscription).
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
collision groups and attributes (`Foliage`, `Destructible`, `Water`, `SmokeVolume`). `tests/Harness/HeightmapWorld`
implements it analytically (heightfield + boxes + foliage spheres) so whole battles run headless in Lune.

---

## 7. Garage, progression and economy

* `Shared/Progression/ProfileSchema` defines profile **v1** + `Migrations` (each migration `vN -> vN+1`, pure, tested).
* `Shared/Progression/Transactions` implements every economic action as a **pure function**
  `(profile, args, content, now) -> Result<{ profile: Profile, events: {DomainEvent} }>` operating on a copy:
  purchase/sell vehicle, research module/vehicle (vehicle XP then free XP), mount module/equipment/ammo/consumables,
  convert XP, train/retrain crew, learn skill, buy/apply customization, claim mission/achievement reward, garage slot,
  store purchase. Validation errors use codes from `Net/ErrorCodes`.
* Server `ProgressionService` resolves the player's session profile, runs the transaction, commits via `DataService`,
  publishes the domain events (to Missions/Achievements/Notifications) and lets `DataSync` patch the client.
* `Shared/Battle/Scoring` turns a battle ledger into per-player XP/credits/crew XP/free XP with the economy config;
  `RewardService` applies them **idempotently** (`profile.processed.battles` ring) and writes battle history.

### Data persistence (`DataService`)
Session-locked profiles (ProfileStore-style) on `DataStoreAdapter`: `UpdateAsync` lock `{jobId, placeId, at}`,
lock steal after timeout, autosave every 60 s with jitter, save + release on leave, `BindToClose` flush,
exponential backoff with budget awareness, schema migration on load, `validateAndRepair` for corrupted/partial data,
kick-with-message on unrecoverable load failure (never play on a default profile that could overwrite real data).
Developer-product receipts and battle rewards are idempotent through the profile's `processed` rings.

---

## 8. Matchmaking

* `Shared/Matchmaking/Matchmaker` is a **pure** algorithm: `(tickets, now, config, rng) -> { matches, remaining }`.
  Tickets: `{ ticketId, members: {userId}, platoonId?, vehicle: {defId, tier, class, role}, mode, region, enqueuedAt }`.
  It honors team size (15v15), tier spread & templates, class mirroring/limits, platoon constraints, wait-time
  relaxation and **bot fill** for low population.
* Hub `QueueService` stores tickets in MemoryStore (`MemoryStoreAdapter`), a leader-elected `MatchmakerService`
  (lock with TTL) runs the algorithm, reserves battle servers, writes manifests, and notifies hubs via `MessagingAdapter`;
  hubs teleport their players (`TeleportAdapter`) with retry → requeue on failure.
* Dev role: the same algorithm runs in-process and starts a local `BattleInstance`.

---

## 9. Configuration & content (Shared/Config)

```
Config/
  init.luau            aggregates + freezes everything; applies LiveOverrides (validated) on the server
  Places.luau          PlaceId -> role
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
    Shells.luau  Guns/  Turrets/  Engines/  Tracks/  Radios/        (modules may be shared across vehicles)
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
* UI is code-built (no Studio-authored GUIs), themed by `Theme` tokens only (no literal colors in screens).
* Every interactive element is reachable by gamepad (Focus groups, explicit NextSelection where needed) and touch.
* `InputMode` (`MouseKeyboard`|`Gamepad`|`Touch`) switches prompts/glyphs and the mobile battle layout.
* Accessibility settings (colorblind palettes, UI scale, text scale, reduced effects, subtitles, audio sliders, camera
  and aim sensitivity) are read through `Settings` and applied centrally (Theme, Layout, Effects, AudioEngine).

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
* Economy: all mutations via `Transactions` on the server with validation + idempotency; purchases via `ProcessReceipt`
  idempotent by receipt id; rewards idempotent by battle id; no client-supplied amounts are ever trusted.
* `AntiExploitService` aggregates strikes (rate-limit, schema failures, impossible requests) → warn/kick thresholds,
  structured logs. Debug remotes reject non-developers (`Config.DevAccess`) and are disabled outside Studio unless the
  user is allow-listed.

---

## 13. Testing standard

* `lune run tests/run.luau [-- filter]` runs all `*.spec.luau` files with a custom loader that resolves string
  requires (`@game`, relative, `@self`) and injects Roblox datatypes (from `@lune/roblox`) plus mocks (`game`, services).
* Required coverage: every Shared module (unit), every server service with logic beyond plumbing (integration with
  mocks), headless end-to-end battle (bots on `HeightmapWorld` → results → rewards → profile → research), data QA
  (join/leave/rejoin/shutdown/DataStore failure/duplicate reward/purchase/corrupted data), matchmaker QA
  (1, 2, 5, 10, 15, 29, 30, 31, 60, 100 players, platoons, leaves, timeouts), combat edge cases, and regression
  specs derived from `docs/research/07-qa-regression-catalogue.md`.
* `scripts/check.sh` must pass before every commit. Reports must state honestly what was tested headlessly vs what
  requires in-engine verification.
