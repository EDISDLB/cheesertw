# 07: QA Regression Catalogue. World of Tanks fix-note defect classes (2018–2026) and Roblox multiplayer bug classes, turned into HULLDOWN regression tests

Research date: 2026-10-05. Written for the HULLDOWN studio team (QA, gameplay, platform).
Scope:
- (1) Defects that World of Tanks (WoT, PC, Wargaming) has fixed or listed as known issues, grouped into 22 categories.
- (2) A generic Given/When/Then regression test for every defect or cluster, tagged by HULLDOWN subsystem and automation level.
- (3) Common Roblox multiplayer bug and exploit classes, with exact platform limits from the local Roblox creator-docs and a regression test for each.

We do **not** assume any of these bugs exist in HULLDOWN. Each one is a known failure mode for a game of this shape, so each one becomes a test we run against our own systems.

> **Evidence caveat (read first).** This report could not quote WoT patch notes line by line. The reasons:
> - **Web search:** the session's shared budget was already exhausted (200 of 200 calls) before this task started. Every WebSearch call returned "budget exhausted".
> - **Blocked domains:** the egress proxy blocks worldoftanks.eu/.com/.asia, wargaming.net, worldoftanks.fandom.com, thearmoredpatrol.com, ftr.wot-news.com, store.steampowered.com (and the Steam news API), en.wikipedia.org, idcgames.com and web.archive.org. Each was tested once.
> - **GitHub:** it is reachable, but its repository search found no mirror of WoT release notes. It found only decompiled client dumps (e.g. "WorldOfTanks-Decompiled"), which are **excluded by policy**.
>
> Each WoT catalogue entry therefore carries a provenance tag:
> - **[S] Sourced.** The fact appears in an official Wargaming article or another source already cited (from search results) by HULLDOWN research docs 01, 02, 05 and 06. The link is given. Those pages were not re-opened in this session.
> - **[R] Recalled.** A specific WoT incident or change the author remembers from official notes or news. It was not re-verified. Confidence Low–Medium.
> - **[P] Pattern.** A wording family that recurs across many WoT "Fixed issues", "Known issues", "Map changes" and "Collision model changes" lists. It **deliberately names no vehicle, map square or version**. It is a test seed, never a historical citation.
>
> Roblox facts in §4 come from the **local clone of the official Roblox creator-docs**, which is authoritative. Each is cited by file path. Confidence is High unless stated.
>
> Every number that is not sourced is labelled **OUR DESIGN CHOICE**.

**Automation legend** (column "Auto"):
- **H**: headless. Pure Luau logic run by `lune run tests/run.luau` with `tests/Harness` mocks, `HeightmapWorld` and `FakeClock`. No Roblox engine.
- **E**: in-engine, automated. It needs real Roblox engine behavior (geometry raycasts against the built map, GUI layout, audio graph, streaming). Run it in Studio test sessions or a private live server. Only **static, server-side scans** can run through **Open Cloud Luau Execution** against a published place version, because those tasks run with no client, with `IsRunning = false`, and with a 5-minute default timeout (see R-QA-4) (corrected by fact-check).
- **M**: manual or visual check.
- "H+E" means the logic is tested headlessly and an engine smoke test complements it.

**Subsystem tags:** VehicleSim, Armor/Penetration, Projectile, Spotting, Minimap, HUD, Reticle, Garage, Carousel, TechTree, Crew, Equipment, Consumables, Matchmaking, Platoon, BattleLifecycle, Results/Rewards, Data/Persistence, Audio, Map, UI/Input, Controller/Mobile. Two extra tags are used in §4: Net/Security and Platform.

---

## Summary

1. **Evidence quality.** The catalogue has **183 WoT-derived entries** in 22 categories:
   - **14** are tied to an official source ([S], or [S] mixed with [R] or [P]);
   - **6** are specific recollections ([R]);
   - **163** are recurring fix-note patterns ([P]), stated generically.

   §4 adds **18 Roblox bug/exploit classes**, all sourced to local official docs. They cover all 12 classes requested, plus malformed arguments, MemoryStore/Messaging and text filtering. The WoT side needs a verification pass with web access before anyone quotes it as history (see Open questions). The test ideas do not depend on that pass.
2. **Test count.** The catalogue defines **204 regression tests**: 164 from the WoT catalogue and 40 from the Roblox classes. By automation level:
   - **180 (88%) are fully headless (H)**;
   - 8 are headless plus an engine smoke test (H+E);
   - 13 are engine-automated (E, or E/M);
   - 3 are manual (M).

   This is possible because the HULLDOWN architecture keeps gameplay rules in pure `Shared` modules.
3. **The most frequent WoT defect families** (by how often the wording family recurs across years of notes):
   - (a) map geometry: stuck spots, unreachable or exploit positions, invisible walls, shoot-through props, minimap/map mismatch;
   - (b) vehicle collision models that let shells pass through gaps, or that disagree with published armor;
   - (c) **stale UI state** after returning from battle or switching vehicle;
   - (d) markers, minimap icons and sounds that **outlive the entity** (destroyed or unspotted vehicles);
   - (e) results and rewards edge cases: first win, premium, disconnects, missions counted twice or never;
   - (f) replay incompatibility and desync.
4. **Architecture removes some classes, which still need tests.** Server-authoritative movement makes speed, fly and teleport hacks impossible by construction. Custom replication makes wall-hacks pointless. Server ballistics makes damage spoofing impossible. Each guarantee gets a **P0 property test**, because a single refactor can silently break it. Examples:
   - REG-SPT-08 checks the replication filter on every tick of every headless battle;
   - REG-NET-03 statically rejects any C2S remote that carries damage, HP or hit results.
5. **Prefer invariants over examples.** Run a shared `Invariants.check(battle)` after **every tick** of every headless battle and soak test:
   - no NaN or inf in any state;
   - HP within [0, maxHp];
   - hull bottom at or above `groundAt − 0.05 m` unless falling;
   - inside map bounds;
   - ammo ≥ 0;
   - spotted set equals replicated set;
   - damage ledger sum equals HP lost;
   - capture progress within [0, 100].

   One invariant suite catches dozens of WoT-style bugs at once.
6. **Map QA must be a pipeline, not playtesting.** WoT shipped map fixes for stuck spots and exploit positions for years. HULLDOWN should run four scanners on every map change:
   - a **reachability flood-fill** from spawns using the real `VehicleSim` climb limits (2 m grid);
   - a **bot soak** with a stuck detector (|throttle| ≥ 0.5 and < 1 m of displacement in 5 s);
   - a **collision/visual parity** raycast scan (≤ 0.25 m);
   - a **border-sealing** check.

   All thresholds are OUR DESIGN CHOICE.
7. **"Shell went through the tank" becomes a watertightness test.** Fire 10,000 seeded rays at every vehicle blueprint (each turret config, gun at max elevation and max depression). Every ray that enters the visual hull must hit an armor face first. The required leak count is zero.
8. **Determinism enables replays and bug reproduction.** If `(matchSeed, input log, content hash)` deterministically reproduces the event-stream hash, then every bug report becomes a replayable fixture. Iterate entities by sorted id, never `pairs` order, and never read wall-clock time in `Shared`. WoT refuses replays across versions; we should do the same, keyed on the content hash.
9. **Results and Rewards.**
   - The report must be computed by the *same* `Scoring` output that `RewardService` applies (golden ledger tests).
   - Rewards are idempotent by battleId.
   - First-win and premium status are evaluated at a defined instant, with tests at the UTC boundary.
10. **Audio leaks are a lifecycle bug.** Every looping voice is owned by an entity scope (Trove). The test: when `VehicleDestroyed` or `BattleEnded` fires, all of that entity's loops stop within one frame, and the voice count never exceeds the 32-voice budget (doc 06).
11. **DataStore.**
    - Use session locking through `UpdateAsync`. Retries must be **ordered per key**.
    - Never save default data after a failed load.
    - Treat a failed write as "outcome unknown" (`cloud-services/data-stores/error-codes-and-limits.md`).
    - Server budget for Read (Get/Update) and Write (Set/Increment/Update): **60 + numPlayers × 40 requests/min** each. This is the default per-server limit; `DataStoreService:SetRateLimitForRequestType()` can change it. The experience-wide limits bind first in aggregate: Read **300 + CCU × 40**, Write **300 + CCU × 20** per minute. `UpdateAsync` uses both the read and the write budget (clarified by fact-check). Request queues hold **30**, then drop.
    - Each key holds at most **4,194,304 characters**. GetAsync is cached for **4 s**.
12. **BindToClose.** The engine waits **30 s**, then shuts down regardless (`DataModel.yaml`). Our `Stop()` budget is 25 s. Saves must run **in parallel**, and stale queued writes are skipped to the last one enqueued.
13. **ProcessReceipt.**
    - Grant and record the `PurchaseId` in the profile, then **save, then** return `PurchaseGranted`.
    - The callback may run **on two servers at once**, runs only while the user is on the server, has no timeout, and pending receipts arrive in non-deterministic order (`MarketplaceService.yaml`).
    - Session locking plus a processed-receipt ring makes double grants impossible. Test it with duplicate and concurrent callbacks.
14. **Remotes.**
    - About **500 requests/s per client**, shared by all remotes of one type. Excess RemoteEvents are **processed later, not dropped**, so the server must rate-limit itself. Excess UnreliableRemoteEvents are dropped.
    - UnreliableRemoteEvent payloads over **1,000 bytes** are dropped; we cap at 900.
    - Exploiters can send **NaN and ±inf**. Both pass `typeof == "number"`. NaN also fails every comparison, so a check written as "reject if x > max" lets it through. inf is caught by a correct bound check but breaks arithmetic (corrected by fact-check: the earlier text said both pass every comparison). Validate with `math.isfinite`.
15. **Teleports.**
    - `TeleportAsync` is server-only, takes **≤ 50 players per call**, and can fail silently through `TeleportInitFailed`. The doc sample makes up to **5 attempts** (the first call plus 4 retries), 1 s apart. Its `TeleportInitFailed` handler waits 15 s on `Flooded` and 1 s on `Failure`, then re-teleports. It raises an error for every other result (corrected by fact-check: the earlier text said "retries 5×").
    - Teleport data is client-visible and spoofable. Battle servers must read their manifest from MemoryStore, never from TeleportData.
16. **Memory leaks.** The engine **does not destroy `Player` objects or characters** on leave unless `Workspace.PlayerCharacterDestroyBehavior` is set to `Enabled`. That property is **NotScriptable**: scripts can neither set nor read it, so set it in the place file through Studio or the Rojo project (corrected by fact-check). Connections and per-player tables leak on long-running servers. The test: after 1,000 headless join/leave cycles, every per-player registry is empty.
17. **Streaming and joins.**
    - With StreamingEnabled, `FindFirstChild` returns nil for streamed-out instances, and `ChildAdded`/CollectionService signals fire on stream-in/out.
    - `PlayerAdded` misses players who joined before the connection was made.
    - Because battle vehicles are not characters, recommend `Players.CharacterAutoLoads = false` in battle places and setting `Player.ReplicationFocus` to the vehicle's anchor. This removes the character fling, noclip and physics surface entirely.
18. **Release gating** (OUR DESIGN CHOICE):
    - **P0** headless suite (data, economy, receipts, net security, armor pipeline, replication filter) on every commit;
    - **P1** nightly: bot soaks, map scanners and fuzzers. Static-geometry E-tests run through Open Cloud Luau Execution. Client, rendering and soak E-tests run in Studio test sessions or a private live server, because Luau Execution has no client, runs with `IsRunning = false` and has a 5-minute default timeout (corrected by fact-check);
    - **P2** per-release manual checklist for UI, audio and devices.

---

## Detailed findings

### 1. Method, evidence and provenance

**Current behavior (method).**
- Each WoT entry is a defect class that WoT's official release notes have repeatedly fixed or listed under "Known issues", or a specific incident tagged [S] or [R].
- Each test is generic and targets HULLDOWN's architecture (`docs/ARCHITECTURE.md` §§5–13).
- Roblox items were taken from the local creator-docs (`refs/creator-docs/content/en-us`, the same clone dated 2026-10-02 that doc 06 uses).

**Where to verify WoT items once web access is available.** These are the official release-notes and announcement pages, as cited by other HULLDOWN research docs:

- Release notes: [RN-0.8.6], [RN-9.5], [RN-9.14], [RN-9.15], [RN-9.16 (wiki)], [RN-9.17.1], [RN-1.0 (wiki)], [RN-1.10], [RN-1.12], [RN-1.18.1], [RN-1.26], [RN-2.0].
- Common Test announcements: [CT-1.26], [CT-2.2].
- Feature articles: [A-9.4-ram], [A-9.16-spot], [A-9.14-sound], [A-9.16-sound], [A-9.16-compare], [A-9.17.1-compare], [A-1.0-music], [A-1.10-comm], [A-1.10-eq], [A-1.13-HE], [A-1.14-FM], [A-1.18.1-6S], [A-1.26-crew], [A-1.26-cons], [A-2.0-hub], [A-2.4-vfx], [A-xp-conv], [TAP-GSOR1008], [FTR-9.3-ricochet].

**Confidence.**
- High that the 22 defect families recur in WoT's notes. The author's familiarity with the notes' structure, plus the [S] items, support this.
- Low for any individual [P] instance. None is claimed.
- High for all Roblox facts, after the corrections listed in the Verification log.

[RN-0.8.6]: https://worldoftanks.eu/en/content/docs/release_notes/release-notes-86/
[RN-9.5]: https://worldoftanks.com/en/content/docs/release_notes/95-updatenotes/
[RN-9.14]: https://worldoftanks.com/en/content/docs/release_notes/914-updatenotes/
[RN-9.15]: https://worldoftanks.com/en/content/docs/release_notes/915-updatenotes/
[RN-9.16 (wiki)]: https://wiki.wargaming.net/en/Tank:Update_9.16
[RN-9.17.1]: https://worldoftanks.com/en/content/docs/release_notes/9171-updatenotes/
[RN-1.0 (wiki)]: https://wiki.wargaming.net/en/Tank:Update_1.0
[RN-1.10]: https://worldoftanks.com/en/content/docs/release_notes/update-1-10-list-of-changes/
[RN-1.12]: https://worldoftanks.com/en/content/docs/release_notes/update-1-12-list-of-changes/
[RN-1.18.1]: https://worldoftanks.eu/en/content/docs/release_notes/release-notes-1-18-1/
[RN-1.26]: https://worldoftanks.com/en/content/docs/release_notes/release-notes-1-26/
[RN-2.0]: https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/
[CT-1.26]: https://worldoftanks.com/en/news/updates/1-26-CT1/
[CT-2.2]: https://worldoftanks.eu/en/news/updates/2-2-CT/
[A-9.4-ram]: https://worldoftanks.eu/en/news/general-news/update94-changes-ramming
[A-9.16-spot]: https://worldoftanks.eu/en/news/general-news/version-916-spotting-improvement/
[A-9.14-sound]: https://worldoftanks.com/en/news/general-news/914-improved-sounds/
[A-9.16-sound]: https://worldoftanks.com/en/news/general-news/9-16-sound/
[A-9.16-compare]: https://worldoftanks.com/en/news/general-news/916-comparison/
[A-9.17.1-compare]: https://worldoftanks.eu/en/news/general-news/917-1-vehicle-comparison/
[A-1.0-music]: https://worldoftanks.com/en/news/general-news/update-1-0-new-music/
[A-1.10-comm]: https://worldoftanks.eu/en/news/general-news/1-10-battle-communication/
[A-1.10-eq]: https://worldoftanks.com/news/updates/update-1-10-equipment-2-0/
[A-1.13-HE]: https://worldoftanks.eu/en/news/general-news/1-13-HE-shells/
[A-1.14-FM]: https://worldoftanks.com/en/news/updates/update-1-14-field-modification/
[A-1.18.1-6S]: https://worldoftanks.eu/en/news/general-news/1-18-1-sixth-sense-perk/
[A-1.26-crew]: https://worldoftanks.com/en/news/general-news/new-crew-perks-1-26/
[A-1.26-cons]: https://thearmoredpatrol.com/2024/08/11/wot-1-26-common-test-consumables-update/
[A-2.0-hub]: https://worldoftanks.eu/en/news/updates/2-0-hub/
[A-2.4-vfx]: https://worldoftanks.eu/en/news/general-news/2-4-upgraded-vfx-sfx/
[A-xp-conv]: https://worldoftanks.eu/en/news/specials/xp-conversion-july-2024/
[TAP-GSOR1008]: https://thearmoredpatrol.com/2020/12/23/gsor-1008-apcr-shell-penetration-issue/
[FTR-9.3-ricochet]: http://ftr.wot-news.com/2014/09/15/9-3-ricochet-mechanics-explained/

### 2. How WoT reports fixes, and what that teaches our QA process

**Current behavior (R/P).** A WoT major update's release notes typically contain these sections:
- feature sections;
- **"Changes to maps"**, often listing map squares where vehicles could get stuck or reach unintended positions;
- **vehicle and collision-model changes**;
- **"Fixed issues"/"Fixes"**;
- **"Known issues"**.

Small client patches (numbered x.y.z.n) follow the major update and fix regressions. Major features first go through public **Common Tests** ([CT-1.26], [CT-2.2]) and sometimes a **Sandbox**.

**Exact values.** None are applicable.

**History.**
- Very large reworks reset many systems at once, and each was followed by fix waves:
  - 9.14 (10 Mar 2016): physics and Wwise sound ([RN-9.14], [A-9.14-sound]);
  - 1.0 (Mar 2018): HD remaster of every map and new music ([RN-1.0 (wiki)], [A-1.0-music]);
  - 1.10 (4 Aug 2020): Equipment 2.0 and battle communication ([RN-1.10]);
  - 1.26 (Sep 2024): crew perks and consumables ([RN-1.26]);
  - 2.0 (3 Sep 2025): garage, results and rebalance ([RN-2.0], [A-2.0-hub]).
- Lesson for HULLDOWN: **a regression suite must exist before each rework**, not after.

**Confidence.** Medium (structure: R; dates: S, via docs 01, 02, 05 and 06).

**HULLDOWN lessons.**
- Keep our own release notes in the same shape, with "Fixed" items carrying the test ID that now guards them.
- Never close a bug without adding a `tests/Regression` spec.
- Run a public "test server" place (our CT equivalent) for big reworks.

---

### 3. WoT defect catalogue and HULLDOWN regression tests

Every subsection gives four things:
- the WoT behavior or defect family;
- a defect table, with version/date shown only when sourced or recalled;
- confidence and sources;
- the regression tests.

Config names refer to `Shared/Config/*` as defined in `docs/ARCHITECTURE.md` §9 and research docs 01 and 02.

**Default rating for every subsection unless it states otherwise:**
- **Confidence:** Medium that the defect *class* recurs in WoT notes; Low for any individual [P] row (none is claimed).
- **Sources:** "pattern"; verify against the release-notes pages listed in §1.
- **History:** where none is given, no sourced version history was available in this session.
- **Exact values:** the numbers in the tests come from HULLDOWN research docs 01, 02, 05 and 06, or are marked OUR DESIGN CHOICE.

#### 3.1 Minimap

**Current WoT behavior.** The minimap shows:
- allies;
- spotted enemies;
- last-known positions: markers added in 9.5, set to "Always" by default since 9.15;
- view-range, max-spotting (445 m) and draw-range (564 m) circles, added in 9.14. The current in-game manual gives the draw range as 565 m; the 1 m difference does not matter (doc 02 fact-check);
- pings and commands: left-click "attention", right-click "moving to", since 1.10.

It is resizable with = and −. Sources: doc 06 §12 ([RN-9.5], [RN-9.14], [RN-9.15], [A-1.10-comm]) and doc 02.

| ID | Defect (as reported or fixed) | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| MINI-01 | A destroyed vehicle's marker stayed on the minimap, or kept its "alive" icon | — | [P] · Low | pattern |
| MINI-02 | The minimap image did not match the map geometry after a map rework (roads or buildings offset or missing) | after the 1.0 HD remaster, Mar 2018 (remaster [S]; mismatch [P]) | [S]/[P] · Low | [RN-1.0 (wiki)] |
| MINI-03 | View-range circle radius wrong or stale: not updated after equipment or crew changes, or when binoculars activated | circles added 9.14 [S] | [P] · Low | [RN-9.14] |
| MINI-04 | Last-known-position marker not cleared, not faded, or duplicated after the enemy was re-spotted elsewhere | markers 9.5 [S], default 9.15 [S] | [P] · Low | [RN-9.5], [RN-9.15] |
| MINI-05 | Ping or command placed at the wrong spot (offset), especially near map edges or after resizing the minimap | — | [P] · Low | pattern |
| MINI-06 | Minimap size reset after a battle or a mode switch | — | [P] · Low | pattern |
| MINI-07 | Heading arrow or camera cone pointed the wrong way (in SPG strategic view or after respawn) | — | [P] · Low | pattern |
| MINI-08 | The grid square named in a chat or ping message did not match where the ping appeared | — | [P] · Low | pattern |
| MINI-09 | Allies or enemies beyond the 564 m draw range shown inconsistently between the 3D view and the minimap | draw range 564 m since 9.12 [S] | [P] · Low | doc 02 §1 |

**History.** The 9.5 → 9.14 → 9.15 → 1.10 feature growth is [S]. Each step added state the minimap must clean up.

**Confidence.** Medium for the features, Low for individual defects.

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-MINI-01 | MINI-01, MRK-02 | Minimap | H | **Given** a minimap model fed by `BattleView` with enemy V spotted. **When** `VehicleDestroyed(V)` arrives in any of 3 orders (before, after or in the same snapshot as `Unspotted(V)`). **Then** V's entry becomes `Wreck` in that frame, and no later frame ever shows V as alive. |
| REG-MINI-02 | MINI-02, MAP-10 | Minimap, Map | H+E | **Given** a map's `MapLayout` and the world bounds declared for the minimap texture. **When** 1,000 seeded random points round-trip `worldToMinimap → minimapToWorld`. **Then** the error is ≤ 0.5 m (H). **And** (E) every part tagged `MinimapLandmark` projects within 2 px of its pixel on a 512 px generated minimap. CI fails if the minimap's source hash differs from the map content hash. |
| REG-MINI-03 | MINI-03, SPT-09 | Minimap, Spotting | H | **Given** a vehicle with effective view range VR from `StatsCalculator`. **When** binoculars arm (after `STATIONARY_ARM_S` = 3 s), the commander is injured, or equipment changes. **Then** the view-range circle equals the new VR within 1 tick, the max-spotting circle stays 445 m, and the draw circle stays 564 m. |
| REG-MINI-04 | MINI-04, MINI-09 | Minimap, Spotting | H | **Given** V unspotted at t0. **Then** exactly one last-known marker sits at V's *last replicated* position. It is removed at t0 + `LAST_KNOWN_MARKER_S` (60 s), or immediately when V is re-spotted. It never shows a position that was not replicated to the observer's team (no info leak). |
| REG-MINI-05 | MINI-05, MINI-08, CMD-07 | Minimap, UI/Input | H | **Given** minimap sizes 1–5 and a click at a normalized point p. **When** p is converted to a world position. **Then** the result is the same at every size (± one texel), the grid label in the chat line equals `MapLayout.gridLabel(worldPos)`, and corner clicks clamp inside the map bounds. |
| REG-MINI-06 | MINI-06, RET-08 | Minimap, UI/Input | H | **Given** minimap size step k and a sniper zoom level z in `Settings`. **When** the battle ends, a new battle starts, or the player rejoins. **Then** k and z are restored from persisted settings. |
| REG-MINI-07 | MINI-07 | Minimap | H | **For** hull yaw and camera yaw in 0..359° (step 1°) in every camera mode. **Then** icon rotation equals hull yaw, the cone equals camera yaw, and North-up is preserved. |

#### 3.2 Vehicle positioning, collision, stuck, overturn, falling through terrain

**Current WoT behavior.**
- Vehicles are physics-simulated (reworked in 9.14).
- They can overturn, and overturned vehicles stay immobile until destroyed or pushed back by others (R).
- They take fall and ram damage ([A-9.4-ram], doc 01 §7).
- They drown when submerged long enough (R).
- Map-change notes routinely list map squares where vehicles could get stuck (P).

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| VEH-01 | Vehicles got stuck on specific objects or terrain seams; notes listed affected map squares | recurring | [P] · Medium (as a class) | pattern |
| VEH-02 | Vehicles fell through the terrain or under the map at specific spots | — | [P] · Low | pattern |
| VEH-03 | After the 9.14 physics update, vehicles climbed steeper slopes and reached positions that were previously unreachable; later map passes sealed them | 9.14, Mar 2016 (physics [S]; consequence [R]) | [S]/[R] · Low-Med | [RN-9.14] |
| VEH-04 | A vehicle was launched or bounced into the air after hitting a vehicle or object (impulse spike) | — | [P] · Low | pattern |
| VEH-05 | Wheeled vehicles overturned or behaved erratically on small obstacles; tuned in later updates | wheeled vehicles from 1.4 (2019) | [R] · Low | — |
| VEH-06 | Vehicle overturned on flat ground with no visible cause, or stayed stuck in the overturned state | — | [P] · Low | pattern |
| VEH-07 | Wreck collision did not match the wreck's visual model (invisible blocker or pass-through) | — | [P] · Low | pattern |
| VEH-08 | Rubber-banding: visual and server position diverged at high speed or after reconnect | — | [P] · Low | pattern |
| VEH-09 | A vehicle passed through a destructible without destroying it, or the object was destroyed for one client but still blocked others | — | [P] · Low | pattern |
| VEH-10 | A vehicle spawned inside another vehicle or object (overlapping spawn points) | — | [P] · Low | pattern |
| VEH-11 | A vehicle drowned in water shallower than expected, or failed to drown when fully submerged | — | [P] · Low | pattern |
| VEH-12 | Fall damage inconsistent: large damage from small drops, and upside-down landings much worse | anecdote, doc 01 §7.2 | [R] · Low | doc 01 |

**Exact values.** HULLDOWN's own model (doc 01 R6):
- ram damage is 0 below `v_rel` 3 m/s, `k_ram` = 0.10;
- fall damage applies above `v_y` 7 m/s: `D = 0.6·m·(v_y − 7)²` with m in tonnes, ×2 when landing upside-down.

**Confidence.** Medium (class) / Low (instances).

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-VEH-01 | VEH-01, BTL-05 | VehicleSim, Map | H | **Given** 30 bots (15v15) on each map's `HeightmapWorld` export, seeded. **When** they drive random lane waypoints for 30 simulated minutes. **Then** there are **0 stuck events**. A stuck event is \|throttle\| ≥ 0.5 and planar displacement < 1.0 m over 5.0 s, with no vehicle contact and no overturn (thresholds are OUR DESIGN CHOICE). Each event is reported with its map cell for map QA. |
| REG-VEH-02 | VEH-02 | VehicleSim | H | **Invariant, every tick:** hull bottom y ≥ `groundAt(x,z) − 0.05 m` unless the state is `Falling`. No vehicle is below the kill-plane. A position outside the map bounds is clamped and logged as an error. |
| REG-VEH-03 | VEH-03, MAP-02 | VehicleSim, Map | H | **Given** synthetic slopes from 0° to 60° (step 1°). **When** full throttle is applied uphill for 60 s. **Then** altitude gain is 0 above `Movement.MAX_CLIMB_DEG`. The map reachability scan (REG-MAP-02) reports no `OutOfBounds` or `Roof` cell. |
| REG-VEH-04 | VEH-04 | VehicleSim | H | **Given** random pairs of vehicles (mass 10–80 t, speed 0–70 km/h, random angles), 10,000 cases. **When** `CollisionSystem` resolves the contact. **Then** the pair's total kinetic energy after the contact is ≤ before (no energy creation), and no vertical velocity is created on flat ground. |
| REG-VEH-05 | VEH-05, VEH-06 | VehicleSim | H | **Given** flat ground with no obstacles. **When** random throttle and steer inputs run for 10 simulated minutes per vehicle. **Then** no vehicle overturns. **And given** roll > `Movement.OVERTURN_DEG` for at least `OVERTURN_TIME_S`, the state becomes `Overturned` and follows the configured rule (e.g. self-recover or timed destruction) deterministically. |
| REG-VEH-06 | VEH-07 | VehicleSim | H | **When** a vehicle is destroyed. **Then** the wreck's collision box equals the live hull box exactly, and the wreck renders from the same blueprint (parity by construction). |
| REG-VEH-07 | VEH-08 | VehicleSim | H | **Given** client prediction at 150 ms RTT with ±50 ms jitter and 5% input loss, for 60 s of scripted driving. **Then** the p99 position error after reconciliation is < 0.5 m. No correction exceeds 3 m unless the server flagged a `Teleport` event. (Thresholds are OUR DESIGN CHOICE.) |
| REG-VEH-08 | VEH-09, PRJ-03 | VehicleSim, Map | H | **When** the server calls `destroyObject(id)`. **Then** its collision is gone for every later sim step, and a client joining later receives `destroyedObjects` in its first snapshot. |
| REG-VEH-09 | VEH-10 | Map, BattleLifecycle | H | **For** every map and team (15 spawns each). **Then** spawns are separated by at least hull length + 2 m, lie on ground with slope below the climb limit, and intersect no collision box. |
| REG-VEH-10 | VEH-11 | VehicleSim | H | Table test: the drowning timer starts only when depth ≥ the vehicle's `drownDepth` and resets on exit. Depths are tested at drownDepth −0.01, ±0 and +0.01 m. |
| REG-VEH-11 | VEH-12 | VehicleSim, Armor/Penetration | H | `v_y` = 7.0 m/s gives 0 damage. `v_y` = 10 m/s with m = 40 t gives 0.6·40·3² = **216 HP**; upside-down gives 432. Golden values are taken from doc 01 R6. |

#### 3.3 Map issues: invisible walls, unreachable positions, exploit spots, broken collision

**Current WoT behavior.** Maps have a red-line border, capture circles, spawns, foliage (soft cover) and hard cover. Map-change notes routinely list invisible collision, shoot-through props and unintended positions (P).

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| MAP-01 | Invisible walls: a shell or vehicle was blocked where no object was visible (and the reverse: a visible object had no collision) | recurring | [P] · Medium (class) | pattern |
| MAP-02 | Unintended or exploit positions on roofs, rocks or beyond the play area gave unfair firing spots | recurring | [P] · Medium (class) | pattern |
| MAP-03 | Shells passed through visually solid props (walls, rocks), allowing shots through cover | — | [P] · Low | pattern |
| MAP-04 | Foliage concealed after it was visually destroyed, or did not conceal when present (vegetation LOD mismatch) | — | [P] · Low | pattern |
| MAP-05 | Vehicles drove past the map border in certain squares | — | [P] · Low | pattern |
| MAP-06 | The capture circle used by the rules did not match the visible flag area | — | [P] · Low | pattern |
| MAP-07 | Spawn exposure: one team could be spotted or shot on spawn, fixed by map balance passes | — | [P] · Low | pattern |
| MAP-08 | Terrain or LOD seams let players see through terrain or exposed holes | — | [P] · Low | pattern |
| MAP-09 | Water depth did not match the visuals | — | [P] · Low | pattern |
| MAP-10 | The full map remaster created a whole-map regression surface, with follow-up fixes over several patches | 1.0, Mar 2018 [S] | [S]/[R] · Medium | [RN-1.0 (wiki)] |

**Confidence.** Medium (class).

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-MAP-01 | MAP-01, MAP-03, MAP-08 | Map | E | **Given** the built map in a published place version, scanned through Open Cloud Luau Execution. **When** 1,000 seeded line segments per km² are cast in "Shell" mode and in "Sight" mode. **Then** the results agree except where foliage or smoke is tagged. No part with `CanCollide`/`CanQuery` and `Transparency` ≥ 0.95 is inside the play area unless tagged `BoundaryWall`. Each prop's collision bounds are within **0.25 m** of its visual bounds (OUR DESIGN CHOICE). |
| REG-MAP-02 | MAP-02, MAP-05, VEH-03 | Map, VehicleSim | H | **Given** a 2 m grid (OUR DESIGN CHOICE) over the map's heightfield and boxes. **When** a flood-fill runs from every spawn using `VehicleSim` climb and step limits. **Then** no reachable cell lies outside the `PlayArea` polygon or in a `NoGo` volume, and every capture zone and lane waypoint is reachable by both teams. |
| REG-MAP-03 | MAP-04, SPT-10 | Map, Spotting | H | **When** `destroyObject(foliageId)` is called. **Then** `sightLine` concealment through it drops to the configured fallen or zero value in the same tick, and the client's foliage-state event matches. |
| REG-MAP-04 | MAP-06, BTL-01 | Map, BattleLifecycle | H | **Given** a capture zone of radius r from map data. **Then** a vehicle at r − 0.1 m counts and one at r + 0.1 m does not. The flag ring mesh is generated from the same r. |
| REG-MAP-05 | MAP-07 | Map, Spotting | H | **For** every pair of opposing spawn points within `MAX_SPOT_RANGE_M` (445 m). **Then** `sightLine` is blocked, i.e. spawns are not mutually visible. |
| REG-MAP-06 | MAP-09, VEH-11 | Map | E | At 500 sample points, `waterDepthAt` (map data) matches the terrain water depth within 0.25 m. |
| REG-MAP-07 | MAP-10 | Map, Data/Persistence | H | `ContentRegistry.validate()` passes: every map has spawns, zones and lanes per class. The minimap texture hash matches. The map content hash is bumped on every geometry change. |

#### 3.4 Damage and penetration

**Current WoT behavior.** Covered in doc 01:
- normalization 5°/2°;
- 2- and 3-caliber rules;
- ricochet thresholds 70°/85°;
- one ricochet that continues flying (since 9.3);
- ±25% RNG;
- AP/APCR penetration loss over distance;
- HE rework in 1.13;
- modules, fire and ammo rack.

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| DMG-01 | Shells passed through a vehicle with no hit, via gaps in the collision model (turret ring, mantlet, tracks); notes say "collision model of X corrected" | recurring | [P] · Medium (class) | pattern |
| DMG-02 | Collision-model armor values differed from published or intended values on certain plates | recurring | [P] · Low | pattern |
| DMG-03 | The damage log or ribbons showed the wrong outcome, e.g. "critical hit" with no module damaged | — | [P] · Low | pattern |
| DMG-04 | After the HE rework, the display and log of spall and non-pen damage needed follow-up | rework 1.13, Jun 2021 [S] | [S]/[R] · Low | [A-1.13-HE] |
| DMG-05 | Ram or fall module damage not applied, or applied twice | — | [P] · Low | pattern |
| DMG-06 | Ammo rack destruction and detonation inconsistent | — | [P] · Low | pattern |
| DMG-07 | Fire kept dealing damage after being extinguished, or fire damage was not credited to the shooter | — | [P] · Low | pattern |
| DMG-08 | Ricochet edge cases: a continued ricochet hit the wrong vehicle, or a second ricochet did not delete the shell | continued ricochet since 9.3, Sep 2014 [S] | [P] · Low | [FTR-9.3-ricochet] |
| DMG-09 | Penetration consumed incorrectly by tracks or spaced armor (HEAT after a track hit) | — | [P] · Low | pattern |
| DMG-10 | Overmatch not applied on plates with wrong nominal thickness | — | [P] · Low | pattern |
| DMG-11 | **"APCR shell penetration issue"** over distance, discussed by Wargaming's GSOR 1008 | Dec 2020 | [S] · Medium | [TAP-GSOR1008] |
| DMG-12 | Damage dealt to an already-destroyed vehicle (overkill) counted in stats, or a roll appeared outside ±25% | — | [P] · Low | pattern |
| DMG-13 | Team-damage penalties applied to damage that an ally's ricochet or fire caused indirectly | — | [P] · Low | pattern |

**Confidence.** Medium (class).

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-ARM-01 | DMG-01 | Armor/Penetration | H | **For** each vehicle × turret config × gun at max elevation and max depression. **When** 10,000 seeded rays are fired from random directions at random points on the visual blueprint surface. **Then** every ray hits an `ArmorGeometry` face before exiting the vehicle's bounding box. **0 leaks** allowed; failures print the ray and the nearest faces. |
| REG-ARM-02 | DMG-02 | Armor/Penetration, Garage | H | **For** every armor face. **Then** the data-file thickness, the `ArmorGeometry` face thickness and the Armor Inspector's displayed nominal thickness are equal, and the displayed effective thickness is `T/cos(max(0, θ − n))` (doc 01). |
| REG-ARM-03 | DMG-10 | Armor/Penetration | H | Table test at caliber/T = 1.99, 2.00, 2.01, 2.99, 3.00, 3.01. Overmatch (never ricochet) applies only when caliber > 3T. The normalization boost applies only when caliber > 2T. Inputs equal to the threshold are exclusive. |
| REG-ARM-04 | DMG-08 | Armor/Penetration, Projectile | H | Only 1 ricochet is allowed; a 2nd ricochet deletes the shell. The continued shell can hit any vehicle except the shooter (OUR DESIGN CHOICE). A hit on an ally follows the team-damage rule. Penetration after a ricochet is −25% (doc 01 R2). The −25% and the one-ricochet cap are OUR DESIGN CHOICE, because WoT's current post-ricochet rule is unverified (corrected by fact-check: the earlier text cited doc 01 R7 and implied WoT parity). |
| REG-ARM-05 | DMG-09 | Armor/Penetration | H | Golden tests: HEAT loses 5% per 10 cm after any plate; HE through screens or tracks loses 3× that plate's thickness (doc 01 §4 and R4; corrected by fact-check: doc 01 has no §11). |
| REG-ARM-06 | DMG-11 | Armor/Penetration | H | Property test: for AP and APCR, penetration(d) is non-increasing in d and equals nominal for d ≤ 100 m. It is linear between 100 and 500 m and constant beyond. For HEAT, HE and HESH, penetration(d) is constant. Tested over 10,000 random guns from `Content/Guns`. |
| REG-ARM-07 | DMG-12 | Armor/Penetration, Results/Rewards | H | 100,000 rolls stay within ±25% of the mean, and the sample mean is within 0.5% of nominal. Damage applied is ≤ remaining HP. "Damage dealt" stats never exceed the HP removed. |
| REG-ARM-08 | DMG-06 | Armor/Penetration | H | **Given** ammo rack HP 0. **Then** detonation is decided by `Combat.AMMO_RACK_*` rules. With 0 shells stored, there is no detonation (OUR DESIGN CHOICE, flagged for the design review). |
| REG-ARM-09 | DMG-07 | Armor/Penetration, Consumables | H | Extinguishing stops fire damage in the same tick. Fire damage is credited to the player who started it. Fire never ticks on a destroyed vehicle. |
| REG-ARM-10 | DMG-05, VEH-12 | Armor/Penetration, VehicleSim | H | Each ram or fall contact event (with a unique id) applies HP and module damage exactly once, even if the contact persists across ticks. |
| REG-ARM-11 | DMG-13 | Armor/Penetration, Results/Rewards | H | Damage to allies from ricochets, fire or rams goes to the team-damage ledger only. It never counts toward enemy damage or rewards, and penalties follow `Config.Economy`. |
| REG-ARM-12 | DMG-03 | HUD, Armor/Penetration | H | **For** every `ShotResult`. **Then** the HUD log type (pen / non-pen / ricochet / blocked / crit) equals the server outcome, and a "crit" appears only if module or crew state changed. |
| REG-ARM-13 | DMG-04 | Armor/Penetration | H | HE non-pen damage uses the nominal armor at the impact point, and spall damages only modules inside the configured radius (doc 01 §4 and R4 golden cases; reference corrected by fact-check). |

#### 3.5 Projectiles and hit registration

**Current WoT behavior.**
- The client shows a predicted reticle, and the server decides the result.
- An option to show the server reticle exists (R).
- "Ghost shells", where a visual hit is not registered, are a long-running player complaint (R).

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| PRJ-01 | "Ghost shells": a visual hit with no server hit, caused by client and server reticle or position divergence | long-running | [R] · Low | — |
| PRJ-02 | The tracer or arc drawn did not match the server shell path (notably artillery arcs) | — | [P] · Low | pattern |
| PRJ-03 | A shell collided with an object that was already destroyed (destructible desync) | — | [P] · Low | pattern |
| PRJ-04 | A shell hit a wreck or ally it visually missed | — | [P] · Low | pattern |
| PRJ-05 | Shells disappeared before or after their maximum range | — | [P] · Low | pattern |
| PRJ-06 | Autoloader or dual-gun: more shots fired than the magazine holds, or a volley counted as one shot | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-PRJ-01 | PRJ-01 | Projectile, Reticle | H | **Given** the same input stream on client prediction and server, at 150 ms RTT. **Then** after the aim time the gun directions differ by < 0.1°. The shot origin and direction come from server state. The predicted tracer is replaced by the server tracer within 1 snapshot (50 ms). An optional "server reticle" overlay renders the server gun direction. |
| REG-PRJ-02 | PRJ-02 | Projectile | H | Client tracer samples lie within 0.5 m of the server trajectory: both use `Ballistics` with identical gravity and velocity per shell. |
| REG-PRJ-03 | PRJ-03, VEH-09 | Projectile, Map | H | A ram and a shell destroy the same object in one tick: the tick order is fixed (objects are destroyed before projectiles step) and the outcome is identical across 100 seeds. |
| REG-PRJ-04 | PRJ-05 | Projectile | H | The shell is removed when its travelled distance reaches the configured max range, ± one tick of travel. |
| REG-PRJ-05 | PRJ-06 | Projectile, BattleLifecycle | H | Shots per clip ≤ magazine size. A fire request during the intra-clip delay or the clip reload is rejected server-side. A dual-gun volley consumes 2 shells and logs 2 `ShotFired`. |
| REG-PRJ-06 | PRJ-04, DMG-01 | Projectile | H | Swept test: a shell at 1,500 m/s at 30 Hz moves 50 m per tick, yet still hits a 0.2 m plate and a 1.5 m-wide hull placed anywhere along its path (no tunneling). |

#### 3.6 Spotting and visibility

**Current WoT behavior.** Covered in doc 02:
- spot distance `min(445, VR − (VR − 50)·camo)`;
- 50 m proximity;
- staggered checks;
- 10 s linger;
- the 15 m foliage rule;
- Sixth Sense after 3 s (built in since 1.18.1);
- draw range 564 m since 9.12 (565 m in the current in-game manual, per the doc 02 fact-check).

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| SPT-01 | Spotted vehicles appeared with a delay, especially beyond 300 m; the visibility server code was rewritten to show them faster | 9.16 (2016) | [S] · High | [A-9.16-spot] |
| SPT-02 | A vehicle was not spotted despite a clear line of sight (ports or checkpoints occluded by its own parts or small props) | — | [P] · Low | pattern |
| SPT-03 | A vehicle was spotted through solid objects (missing occluder) | — | [P] · Low | pattern |
| SPT-04 | A vehicle stayed invisible after firing (after-shot camo not applied), or the camo net worked while moving | — | [P] · Low | pattern |
| SPT-05 | The Sixth Sense indicator was missing, late, or shown when not spotted; its sound was missing or doubled | built in from 1.18.1, Oct 2022 [S] | [P] · Low | [A-1.18.1-6S] |
| SPT-06 | Enemies flickered in and out at the edge of spot distance | — | [P] · Low | pattern |
| SPT-07 | Spotting-assist damage not credited (multiple spotters, or spotter destroyed) | — | [P] · Low | pattern |
| SPT-08 | Spotted but not rendered within draw range, or rendered beyond it | 564 m since 9.12 [S] | [P] · Low | doc 02 |
| SPT-09 | Binocular bonus stayed active after moving, or activated before 3 s | 3 s arming [S] | [P] · Low | [A-1.10-eq] |
| SPT-10 | Fallen or destroyed foliage concealment handled incorrectly | fallen trees conceal [S] | [P] · Low | doc 02 §7 |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-SPT-01 | SPT-01 | Spotting | H | **Given** random target positions crossing into spot range at 50, 150, 300 and 445 m. **Then** the target is spotted within the scheduled interval (≤ `CHECK_INTERVAL_MAX_S` = 1.0 s) + 1 tick (33 ms). Each event check (shot, stop, spawn) completes in the same tick. |
| REG-SPT-02 | SPT-02 | Spotting | H | `sightLine` from observer ports to target checkpoints ignores both vehicles' own hulls. A clear LOS in open terrain within the spot distance always spots (10,000 random pairs). |
| REG-SPT-03 | SPT-03 | Spotting, Map | H | **Given** a wall box between pairs at > 50 m. **Then** they are never spotted (10,000 random pairs). At ≤ 50 m they are always spotted (proximity). |
| REG-SPT-04 | SPT-04, EQP-06 | Spotting, Equipment | H | After firing, camo is multiplied by `gun.camoAtShot` for `SHOT_CAMO_PENALTY_S` = 3 s. Camo net and binoculars work only after 3 s with hull speed < `STOP_SPEED_KMH` (0.5), and drop the tick the hull exceeds it. |
| REG-SPT-05 | SPT-05, SND-09 | Spotting, HUD, Audio | H | **Given** the player is first spotted at t. **Then** exactly one Sixth Sense event fires at t + 3.0 s (± 1 tick) if still spotted. The lamp shows for 10 s. Exactly one cue plays. A new episode starts only after an unspotted period. |
| REG-SPT-06 | SPT-06 | Spotting | H | **Given** a target oscillating ±1 m across its spot distance at 1 Hz for 60 s. **Then** the client visibility state changes at most once per `SPOT_LINGER_S` (10 s) window. |
| REG-SPT-07 | SPT-07, RES-09 | Spotting, Results/Rewards | H | **Given** a target spotted by A and B, and damaged by C. **Then** spotting-assist credit follows `Config.Economy` split rules, including after A is destroyed (OUR DESIGN CHOICE: still credited, within the 10 s spot window). |
| REG-SPT-08 | SPT-08 | Spotting, Net/Security | H | **P0 anti-wallhack property.** On every tick of 20 seeded headless battles, each observer's snapshot contains full enemy state only if the enemy is spotted by the observer's team **and** ≤ 564 m away. Minimap-only records cover team-spotted enemies beyond 564 m. Unspotted enemies produce **no** record or event (including sounds and tracer origins). |
| REG-SPT-09 | SPT-09 | Spotting, Equipment | H | Binoculars are inactive for t < 3.0 s stationary and active at t ≥ 3.0 s. Any movement above the stop threshold deactivates them in the same tick. |
| REG-SPT-10 | SPT-10, MAP-03 | Spotting, Map | H | See REG-MAP-03. Concealment also follows the 15 m observer and shooter rules (`FOLIAGE_*_CLEAR_M` = 15). |

#### 3.7 Reticle and aiming

**Current WoT behavior.**
- Dispersion is a 2σ circle (since 0.8.6).
- The aim time constant is e-folding.
- Bloom comes from movement and traverse.
- The penetration indicator colors the reticle red, yellow or green (doc 06).
- Gun depression and elevation limits apply.

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| RET-01 | The reticle did not shrink after stopping, or bloom was applied twice | — | [P] · Low | pattern |
| RET-02 | Reticle or camera jitter in sniper mode at high zoom | — | [P] · Low | pattern |
| RET-03 | The penetration indicator used the wrong shell after an ammo switch | — | [P] · Low | pattern |
| RET-04 | The marker allowed aim where the gun could not reach (depression limits); gun marker and aim point diverged | — | [P] · Low | pattern |
| RET-05 | The reload timer on the reticle was wrong after loader injury, ammo switch or autoloader state change | — | [P] · Low | pattern |
| RET-06 | SPG strategic view: wrong aim height on bridges or multilevel terrain | — | [P] · Low | pattern |
| RET-07 | Auto-aim lock stayed on a destroyed or unspotted target | — | [P] · Low | pattern |
| RET-08 | Zoom settings reset between battles | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-RET-01 | RET-01 | Reticle | H | After the vehicle stops, dispersion decays by a factor e per aim time and is within 5% of base after 3 aim times. One shared `Dispersion` module runs on client and server, and bloom per source is applied once per tick (asserted by counting calls). |
| REG-RET-02 | RET-02 | Reticle, UI/Input | E | **In** a Studio test with fixed input at max zoom while stationary. **Then** camera angular jitter is < 0.05° RMS over 10 s (OUR DESIGN CHOICE). |
| REG-RET-03 | RET-03 | Reticle, HUD | H | The indicator color uses the **loaded** shell; after an ammo switch it changes when the new shell finishes loading (OUR DESIGN CHOICE). Thresholds, with pen taken at the current distance and T_eff including angle, normalization and spaced armor: **green** if T_eff ≤ 0.875·pen; **yellow** if 0.875·pen < T_eff < 1.125·pen (±12.5%, half the ±25% roll); **red** if T_eff ≥ 1.125·pen or a ricochet is predicted (doc 06 §13). Table test at 0.874, 0.875, 0.876, 1.124, 1.125 and 1.126 × pen. (Corrected by fact-check: the earlier text used the superseded "red if pen < 0.75·T_eff, yellow within ±25%" rule, which doc 06's own fact-check replaced.) |
| REG-RET-04 | RET-04 | Reticle, VehicleSim | H | **Given** aim points beyond the depression or elevation limits. **Then** the gun marker shows the clamped gun direction plus a "limit" state, and the server and client clamp identically (shared `TurretSim`). |
| REG-RET-05 | RET-05, CRW-04 | Reticle, HUD, Crew | H | The displayed reload equals `GunState.remaining` ± 1 tick after loader injury and heal, ammo switch, clip end, or intra-clip delay. |
| REG-RET-06 | RET-06 | Reticle | H+E | The strategic aim point is the first hit of the camera-ray cast against `World`. Test on a bridge fixture: aiming at the deck hits the deck, not the ground below. |
| REG-RET-07 | RET-07 | Reticle | H | The auto-aim lock is released in the tick its target is destroyed or unspotted. |

#### 3.8 Vehicle markers (3D)

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| MRK-01 | Marker showed outdated HP after damage, or the wrong max HP after a configuration change | — | [P] · Low | pattern |
| MRK-02 | Marker stayed over a destroyed or unspotted vehicle | — | [P] · Low | pattern |
| MRK-03 | Wrong vehicle name or class icon in the marker | — | [P] · Low | pattern |
| MRK-04 | Platoon indicator missing on markers or roster | — | [P] · Low | pattern |
| MRK-05 | Z-order or overlap: ally markers hid enemy markers, or markers drew over menus | — | [P] · Low | pattern |
| MRK-06 | Floating damage numbers attached to the wrong vehicle | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-MRK-01 | MRK-01 | HUD | H | Marker HP equals the last replicated HP, and maxHp equals `VehicleStats.maxHp` of the battle loadout. HP is non-increasing unless a configured heal event exists. |
| REG-MRK-02 | MRK-02 | HUD | H | The REG-MINI-01 property, applied to 3D markers. |
| REG-MRK-03 | MRK-03 | HUD, Data/Persistence | H | Every vehicle in `ContentRegistry` has a class icon key, a short name ≤ 12 characters (OUR DESIGN CHOICE) in each locale, and a tier. Markers resolve them by defId from the battle manifest. |
| REG-MRK-04 | MRK-04, PLT-04 | HUD, Platoon | H | Platoon members carry a `platoonId` in the manifest. The allied marker and team list show the badge for exactly those members. |
| REG-MRK-05 | MRK-05 | HUD | E | `ScreenGui.DisplayOrder` ordering: world markers < HUD < modals. When an enemy and an ally marker overlap, the enemy renders above. |
| REG-MRK-06 | MRK-06 | HUD | H | Damage numbers are keyed by target entityId, never by marker or pool index. Reusing a pool slot clears the old binding. |

#### 3.9 Command wheel, radial menu, battle communication

**Current WoT behavior.** Since 1.10 (4 Aug 2020), the T key places context-sensitive markers on terrain, allies, enemies and bases. On the minimap, left-click means "attention to position" and right-click means "moving to position". There are reply/acknowledge flows ([A-1.10-comm], doc 06 §12). [S]

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| CMD-01 | The radial menu could not open or close in some camera modes, or while chat input was focused | after 1.10 [S feature] | [P] · Low | [A-1.10-comm] |
| CMD-02 | Command markers ("attacking", "defending") stayed after the target was destroyed or the base was captured | — | [P] · Low | pattern |
| CMD-03 | Context command picked the wrong target (ally vs enemy) when objects overlapped | — | [P] · Low | pattern |
| CMD-04 | Command spam was not limited | — | [P] · Low | pattern |
| CMD-05 | Acknowledgements credited to the wrong player, or counted wrongly | — | [P] · Low | pattern |
| CMD-06 | Commands from muted or blacklisted players were still shown | — | [P] · Low | pattern |
| CMD-07 | A command appeared on the minimap but not in 3D, or vice versa | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-CMD-01 | CMD-01 | UI/Input, Controller/Mobile | H | Availability matrix: {Arcade, Sniper, Strategic, Spectator} × {MouseKeyboard, Gamepad, Touch} × {textFocused true/false}. The menu opens only where the spec says, and closing it always restores the previous input context. |
| REG-CMD-02 | CMD-02 | HUD, Minimap | H | A command marker is removed when its target is destroyed, its zone is captured or reset, the issuer is destroyed (OUR DESIGN CHOICE), or after the TTL of 15 s (OUR DESIGN CHOICE). |
| REG-CMD-03 | CMD-03 | UI/Input | H | Resolution priority: enemy vehicle > ally vehicle > objective > terrain. Ties break by screen distance. Table-driven over overlapping fixtures. |
| REG-CMD-04 | CMD-04 | Net/Security | H | Server rate limit: a burst of 4, refilling 1 per 1.25 s, per player (OUR DESIGN CHOICE). Excess is dropped with a soft strike. Commands replicate only to the issuer's team. |
| REG-CMD-05 | CMD-05 | HUD | H | Acknowledgements are deduplicated per userId. The displayed count equals the number of unique acknowledgers. |
| REG-CMD-06 | CMD-06 | UI/Input, Platform | H+E | Commands from users the viewer has blocked or muted are hidden for that viewer only (the client-side filter is fed by the block list). |
| REG-CMD-07 | CMD-07 | Minimap, HUD | H | Both views read the same store entry, and removing it removes both in the same frame. |

#### 3.10 UI state: garage, carousel, filters, tech tree, dialogs

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| UI-01 | The garage stats panel showed the previous vehicle's values after switching | — | [P] · Low | pattern |
| UI-02 | A vehicle still showed "in battle" after the battle ended, or showed as available while still in battle | — | [P] · Low | pattern |
| UI-03 | Carousel filters reset after a battle or restart; an empty filtered list gave no reset hint | — | [P] · Low | pattern |
| UI-04 | Carousel scroll position or selection jumped after a purchase or sale | — | [P] · Low | pattern |
| UI-05 | Tech-tree node state was wrong (research or buy buttons enabled incorrectly) | — | [P] · Low | pattern |
| UI-06 | XP in the tech tree did not update after a battle until relog | — | [P] · Low | pattern |
| UI-07 | Currency counters were stale or flickered after a purchase | — | [P] · Low | pattern |
| UI-08 | Vehicle comparison ignored crew, equipment, consumables, camo and ammo; 9.17.1 added these | 9.16 → 9.17.1 (2016–2017) | [S] · High | [A-9.16-compare], [A-9.17.1-compare] |
| UI-09 | Switching loadout setups showed the wrong loadout or charged incorrectly | — | [P] · Low | pattern |
| UI-10 | Notification badges did not clear after viewing | — | [P] · Low | pattern |
| UI-11 | Customization preview did not revert after leaving without buying | — | [P] · Low | pattern |
| UI-12 | The garage 3D model did not match the selected configuration (stock vs top turret) | — | [P] · Low | pattern |
| UI-13 | Dialogs stacked, or a closed modal kept blocking input | — | [P] · Low | pattern |
| UI-14 | Text overflowed or was truncated in some languages | — | [P] · Low | pattern |
| UI-15 | The full garage and results rework created a large UI regression surface | 2.0, 3 Sep 2025 [S] | [S] · High (rework) | [A-2.0-hub], [RN-2.0] |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-UI-01 | UI-01, UI-12 | Garage | H | The stats panel and model config are pure selectors of `(selectedVehicleId, ProfileView)`. Over 1,000 random selection changes, the panel equals `StatsCalculator(selected)` and the model's config hash equals the selected config. |
| REG-UI-02 | UI-02, MMK-06 | Garage, Carousel, Matchmaking | H | Vehicle lock lifecycle `Idle → Queued → InBattle → Idle` (the lock is held until rewards are applied, or the battle is aborted or its TTL expires). Covers teleport failure, battle-server crash (lock TTL, OUR DESIGN CHOICE 20 min) and rejoin. A locked vehicle cannot be sold or modified. |
| REG-UI-03 | UI-03 | Carousel | H | Filter and sort state persist in `Settings` across battles and rejoin. An empty result shows a "Reset filters" action. Sort is stable (ties broken by vehicleId). |
| REG-UI-04 | UI-04 | Carousel | H | Selection is keyed by vehicleId. After buy, sell or re-sort, the selected id is unchanged, or falls back to its nearest neighbour if the vehicle was sold. |
| REG-UI-05 | UI-05 | TechTree | H | Node state = pure `ResearchGraph(profile)`. A button is enabled iff the dry-run of the matching `Transactions` call returns Ok. Checked for every node of every tree on 50 random profiles. |
| REG-UI-06 | UI-06, UI-07 | Data/Persistence, Garage | H | **Given** random sequences of committed transactions with `ProfilePatch` messages dropped, duplicated or reordered. **Then** the client applies patches by sequence number, any gap triggers a full resync, and the final `ProfileView` equals the server's sanitized view. |
| REG-UI-07 | UI-08 | Garage | H | Compare and parameter screens call `StatsCalculator` with the full loadout (crew, equipment, consumables, field mods), on the same code path as the battle. Asserted with identical outputs for 200 random loadouts. |
| REG-UI-08 | UI-09, EQP-04 | Equipment, Garage | H | Switching setups never charges. Moving items between setups of one vehicle is free. Demount pricing follows a table. Total item count is conserved. |
| REG-UI-09 | UI-10 | UI/Input | H | Badge count = unread items. Viewing marks items read, and the count updates within one patch. |
| REG-UI-10 | UI-11 | Garage | H | Leaving the customization preview without buying restores the applied cosmetics exactly (deep-equals before and after). |
| REG-UI-11 | UI-13 | UI/Input | H | Router invariant: at most one blocking modal. Closing it returns focus to the opener. No orphan full-screen input sinks remain after any sequence of 500 random open/close actions. |
| REG-UI-12 | UI-14 | UI/Input | E | **For** each locale × each label key, rendered at the Compact and Regular layouts. **Then** `TextFits` is true, or the label is explicitly allowed to truncate. |
| REG-UI-13 | UI-15 | Garage, UI/Input | M | Manual pre-release flow checklist: garage → research → buy → mount → queue → battle → results → back, on PC, gamepad and phone. |

#### 3.11 Battle results and rewards

**Current WoT behavior.**
- Results screens list XP, credits, medals and mission progress.
- First-victory bonuses, premium-account multipliers and dailies apply.
- Since 2.0, results are full-screen (doc 06).
- Our economy model is in doc 05.

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| RES-01 | Results missing or delayed ("being processed") for a long time | — | [P] · Low | pattern |
| RES-02 | XP or credits in the detailed report differed from what was credited | — | [P] · Low | pattern |
| RES-03 | Medal not awarded although its conditions were met | — | [P] · Low | pattern |
| RES-04 | Medal awarded in a mode where it should not count | — | [P] · Low | pattern |
| RES-05 | First-victory multiplier not applied, or applied twice | — | [P] · Low | pattern |
| RES-06 | Premium bonus shown but not credited, e.g. premium expired mid-battle | — | [P] · Low | pattern |
| RES-07 | Results for disconnected or rejoined players were wrong | — | [P] · Low | pattern |
| RES-08 | Mission or battle-pass progress not counted, or counted twice | — | [P] · Low | pattern |
| RES-09 | Assisted (spotting/tracking) or blocked damage stats inaccurate | — | [P] · Low | pattern |
| RES-10 | The team table showed the wrong vehicle or tier for a player | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-RES-01 | RES-01 | Results/Rewards, BattleLifecycle | H | Headless: results are produced ≤ 5 s after the battle-end tick (OUR DESIGN CHOICE). If the hub is unreachable, results are kept in a per-player pending record and delivered on the next login (see R-DATA-3). |
| REG-RES-02 | RES-02 | Results/Rewards | H | **Golden ledger.** The report's line items come from the same `Scoring` output that `RewardService` applies, and the sum of lines equals the profile delta. Checked on 1,000 random ledgers plus 20 hand-written golden battles. |
| REG-RES-03 | RES-03, RES-04 | Results/Rewards | H | Each medal predicate is tested at threshold −1, threshold and threshold +1, with every mode exclusion. |
| REG-RES-04 | RES-05 | Results/Rewards | H | First win ×2 is applied once per vehicle per UTC day. Tests at 23:59:59.999 and 00:00:00.000 at the configured reset hour, plus two battles ending in the same second (race). |
| REG-RES-05 | RES-06 | Results/Rewards | H | Premium status is snapshotted at battle start (OUR DESIGN CHOICE). Expiry mid-battle still applies the bonus. The displayed amount equals the credited amount. |
| REG-RES-06 | RES-07, BTL-04 | Results/Rewards, BattleLifecycle | H | **Given** a disconnect at t, with or without a rejoin. **Then** the ledger is retained, rewards are applied at battle end, and they are idempotent: applying the same battleId twice changes nothing. |
| REG-RES-07 | RES-08 | Results/Rewards | H | Mission progress events are deduplicated by (battleId, missionId) and applied once, even if `RewardService` runs twice. |
| REG-RES-08 | RES-09 | Results/Rewards, Spotting | H | The sum of assisted damage equals the damage dealt to targets under spotting or tracking credit windows. Blocked damage equals the sum of non-penetrating hits' potential damage. Both are cross-checked against the event stream. |
| REG-RES-09 | RES-10 | Results/Rewards | H | Team table rows come from the battle manifest (the vehicle actually used), not the current garage selection. |

#### 3.12 Replays

**Current WoT behavior (R).**
- WoT records replay files on the client.
- After an update, replays from older versions do not play.
- Replays can desync.

HULLDOWN replays are optional. The tests apply if they are built.

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| RPL-01 | Replays from a previous game version cannot be played after an update | long-standing | [R] · Medium | — |
| RPL-02 | Replay desync: shells or vehicles behaved differently than live, or the camera jumped | — | [P] · Low | pattern |
| RPL-03 | Playback speed, seek or rewind broke state or crashed | — | [P] · Low | pattern |
| RPL-04 | Replay missing chat or commands, or showing info the recorder never had | — | [P] · Low | pattern |
| RPL-05 | Replay not saved when the client crashed or exited at battle end | — | [P] · Low | pattern |
| RPL-06 | Replays from the test server incompatible with live | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-RPL-01 | RPL-01, RPL-06 | BattleLifecycle | H | The replay header carries the build id and content hash. A mismatch is refused with a clear message, never a crash. |
| REG-RPL-02 | RPL-02 | BattleLifecycle, VehicleSim | H | **Determinism.** Re-simulating `(seed, input log)` reproduces the live event-stream hash for 20 seeded bot battles of 7 minutes each. A static check forbids `os.clock`, `tick` and `DateTime` in `Shared` (except `Clock`) and unsorted `pairs` iteration in sim loops. |
| REG-RPL-03 | RPL-03 | BattleLifecycle | H | Keyframes every 10 s (OUR DESIGN CHOICE). Seeking to t gives a state equal to linear playback to t, for 100 random t. |
| REG-RPL-04 | RPL-04 | Spotting, Net/Security | H | A per-player replay contains only what was replicated to that player (REG-SPT-08 filter). Full-information server replays are available only after the battle ends (anti-ghosting). |
| REG-RPL-05 | RPL-05 | BattleLifecycle | H | Recording is server-side, so it is finalized at battle end regardless of client state. |

#### 3.13 Sound and music

**Current WoT behavior.**
- 9.14 (10 Mar 2016): FMOD → Wwise, more simultaneous sources.
- 9.16: calibre classes, autoloader clip-state sounds, received-damage tiers.
- 1.0 (Mar 2018): per-map dynamic music with winning and losing culmination variants and result themes.
- 2.4 (Sep 2026): gunshot reflections for 5 environment types.

Sources: doc 06; [A-9.14-sound], [A-9.16-sound], [A-1.0-music], [A-2.4-vfx]. [S]

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| SND-01 | Engine or track sound continued after the vehicle was destroyed or the player left the battle | — | [P] · Low | pattern |
| SND-02 | Wrong engine sound (another vehicle's), or none after respawn | — | [P] · Low | pattern |
| SND-03 | Sound missing for a specific outcome (ricochet or non-pen) or a specific gun | — | [P] · Low | pattern |
| SND-04 | Music did not switch to the culmination variant, or played the wrong result theme | music system 1.0 [S] | [P] · Low | [A-1.0-music] |
| SND-05 | Garage music overlapped the battle loading music | — | [P] · Low | pattern |
| SND-06 | Crew voice-over repeated or stale (e.g. "ammo rack damaged" after repair) | — | [P] · Low | pattern |
| SND-07 | Volume settings applied only after restart | — | [P] · Low | pattern |
| SND-08 | Autoloader clip-state cue played at the wrong shell count | cues added 9.16 [S] | [P] · Low | [A-9.16-sound] |
| SND-09 | Sixth Sense sound missing or doubled | — | [P] · Low | pattern |
| SND-10 | A large VFX/SFX refresh created a broad audio regression surface | 2.4, Sep 2026 [S] | [S] · High (refresh) | [A-2.4-vfx] |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-SND-01 | SND-01 | Audio | H | `AudioEngine` voices are owned by entity scopes (Trove). On `VehicleDestroyed(V)` or `BattleEnded`, every loop owned by V stops within 1 frame, with a fade ≤ 0.2 s. After the return to the garage, the count of battle-scoped voices is 0. Run against a mock audio backend. |
| REG-SND-02 | SND-02 | Audio, Data/Persistence | H | The engine sound bank resolves from the vehicle's `engineId`. Every engine has a sound key or a declared fallback (`ContentRegistry`). Re-binding happens on respawn. |
| REG-SND-03 | SND-03 | Audio | H | Exhaustive: every `ShotResult` outcome × calibre class × distance band maps to a cue or a declared fallback. |
| REG-SND-04 | SND-04 | Audio | H | Music state machine: Loading → Start → Mid → Culmination (win or lose, chosen by score lead) → Result (win, loss or draw). Table-driven transitions. Never more than 2 music voices, and only during a crossfade (≤ 1.5 s, OUR DESIGN CHOICE). |
| REG-SND-05 | SND-05 | Audio | H | Garage music fully stops before battle-loading music starts (exclusive Music bus). |
| REG-SND-06 | SND-06 | Audio, Crew | H | Voice-over queue max 3 entries with a TTL of 2.0 s (OUR DESIGN CHOICE). A message whose condition is no longer true (module repaired) is dropped before playback. |
| REG-SND-07 | SND-07 | Audio | H | A settings change updates bus volumes in the same frame. |
| REG-SND-08 | SND-08 | Audio | H | The clip-state cue is driven by `GunState` counts: "last shell" plays exactly when remaining = 1. |
| REG-SND-09 | SND-10 | Audio | M | Listening checklist per environment type and calibre class before each audio release. |
| REG-SND-10 | SND-01, SND-10 | Audio | H | The voice budget never exceeds 32 (doc 06). The quietest and lowest-priority voice is stolen first, with per-category caps. Stress test: 30 vehicles firing for 60 s. |

#### 3.14 Crew

**Current WoT behavior.**
- The crew skills and perks rework in 1.26 (Sep 2024) was followed by further changes in 2.2 (2026).
- Sixth Sense has been built in since 1.18.1 (Oct 2022).
- Injuries apply until the crew is healed.

Sources: docs 01 and 05; [A-1.26-crew], [A-1.18.1-6S].

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| CRW-01 | Crew skill bonus not applied, or shown wrongly in vehicle parameters | — | [P] · Low | pattern |
| CRW-02 | Crew not moved to the barracks when the vehicle was sold, or a wrong barracks count | — | [P] · Low | pattern |
| CRW-03 | Retraining showed the wrong cost, or lost skill XP | — | [P] · Low | pattern |
| CRW-04 | Injury effects persisted after healing, or injured crew were not penalized | — | [P] · Low | pattern |
| CRW-05 | Mass conversion of skills to perks; class of bugs where perks reset or doubled after conversion | 1.26, Sep 2024 [S] | [S]/[P] · Medium | [A-1.26-crew] |
| CRW-06 | A mandatory perk became built-in, with refund or compensation for the old perk and directive | 1.18.1, Oct 2022 [S] | [S]/[P] · Medium | [A-1.18.1-6S] |
| CRW-07 | Crew books or XP applied to the wrong member, or over the cap | — | [P] · Low | pattern |
| CRW-08 | Crew assigned to an incompatible vehicle after a swap | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-CRW-01 | CRW-01 | Crew, Garage | H | Table-driven crew contributions in `StatsCalculator`. A group perk applies iff every crew member has it. Displayed stats equal battle stats (shared function). |
| REG-CRW-02 | CRW-02, CRW-08 | Crew | H | Selling a vehicle moves its crew to the barracks, or fails with a clear error if the barracks is full. Crew count is conserved across sell, buy and swap. A role/vehicle incompatible assignment is rejected. |
| REG-CRW-03 | CRW-03 | Crew, Results/Rewards | H | Retrain cost and XP retention follow `Config.Progression`. All values are integers, and total XP never drops by more than the configured penalty. |
| REG-CRW-04 | CRW-04 | Crew | H | Injury → heal state machine; effects are removed in the heal tick. |
| REG-CRW-05 | CRW-05, CRW-06 | Crew, Data/Persistence | H | Each `Migrations` step vN → vN+1 has golden fixtures. Total crew XP is conserved or explicitly compensated. Re-running a migration is a no-op (idempotent). A downgrade attempt is refused. |
| REG-CRW-06 | CRW-07 | Crew | H | Books and XP target exactly the chosen member(s) and are capped at the configured maximum; any remainder is refunded or carried over per config. |

#### 3.15 Equipment

**Current WoT behavior.**
- Equipment 2.0 (1.10, 4 Aug 2020) added category slots with bonuses, setups and conditional items (binoculars and camo net after 3 s stationary).
- Field Modification arrived in 1.14 (2021).

Sources: docs 02 and 05; [A-1.10-eq], [A-1.14-FM].

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| EQP-01 | Equipment bonus not applied, or applied twice when stacking with consumables or crew | — | [P] · Low | pattern |
| EQP-02 | Bonus shown in the garage but not active in battle (or the reverse) | — | [P] · Low | pattern |
| EQP-03 | Category slot bonus applied to the wrong category, or lost when switching setups | Equipment 2.0, 1.10 [S] | [S]/[P] · Low | [A-1.10-eq] |
| EQP-04 | Demount cost charged when it should not be, or not charged when required | — | [P] · Low | pattern |
| EQP-05 | Equipment duplicated or lost when selling a vehicle | — | [P] · Low | pattern |
| EQP-06 | Conditional equipment activated while moving | — | [P] · Low | pattern |
| EQP-07 | Field Modification choices reset, or their bonuses not applied | 1.14 [S] | [S]/[P] · Low | [A-1.14-FM] |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-EQP-01 | EQP-01, EQP-02 | Equipment | H | Stacking rules are table-driven (additive vs multiplicative, caps). One `StatsCalculator` is used by garage and server; outputs match exactly for every vehicle × 50 random loadouts. |
| REG-EQP-02 | EQP-03 | Equipment | H | The slot bonus applies only to an item of the matching category. Switching setups recomputes the bonus within the same transaction. |
| REG-EQP-03 | EQP-04, EQP-05 | Equipment, Data/Persistence | H | Conservation: depot count + mounted count stays constant across mount, demount, setup switch and vehicle sale. A sale returns each mounted item to the depot exactly once. |
| REG-EQP-04 | EQP-06 | Equipment, Spotting | H | See REG-SPT-04 and REG-SPT-09. |
| REG-EQP-05 | EQP-07 | Equipment, Data/Persistence | H | Field-mod or upgrade choices persist across save and load. Their stat effects appear in `StatsCalculator`. A paid reset is charged once. |

#### 3.16 Consumables

**Current WoT behavior.** Since 1.26 (2024), the small repair and first-aid kits fix all modules and crew. The large kits and the automatic fire extinguisher have a 60 s cooldown, previously 90 s (doc 01; [A-1.26-cons]). Small kits and the manual extinguisher keep 90 s. [S] for the source link only. **Confidence for the values is Medium:** docs 01 and 05 could not re-open the 1.26 pages in their fact-checks, and this pass could not either (downgraded by fact-check).

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| CON-01 | Automatic fire extinguisher did not trigger | — | [P] · Low | pattern |
| CON-02 | Repair kit did not repair every module, or its cooldown was not displayed | — | [P] · Low | pattern |
| CON-03 | Cooldown persisted into the next battle, or reset incorrectly | — | [P] · Low | pattern |
| CON-04 | Auto-replenish charged credits incorrectly, or did not replenish | — | [P] · Low | pattern |
| CON-05 | Hotkey activated the wrong slot after a loadout change | — | [P] · Low | pattern |
| CON-06 | Consumable usable while destroyed or during the countdown | — | [P] · Low | pattern |
| CON-07 | Consumable rework changed cooldowns (90 → 60 s), a config-migration risk | 1.26, 2024 [S] | [S] · Medium | [A-1.26-cons] |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-CON-01 | CON-01 | Consumables | H | With the auto-extinguisher equipped, a fire is extinguished in the tick it starts (or per config delay) and a charge is consumed. |
| REG-CON-02 | CON-02, CON-07 | Consumables, HUD | H | The kit repairs or heals per `Config.Consumables` (all-modules mode if adopted). Cooldown = config value (golden 60 s). The HUD cooldown equals the server cooldown ± 1 tick. |
| REG-CON-03 | CON-03 | Consumables, BattleLifecycle | H | All battle-scoped cooldowns and durations are reset at battle start. Nothing battle-scoped is persisted to the profile. |
| REG-CON-04 | CON-04 | Consumables, Results/Rewards | H | Auto-replenish is a transaction. It charges only when it buys. Insufficient funds means no purchase plus a notification. The balance never goes negative. |
| REG-CON-05 | CON-05 | Consumables, UI/Input | H | Hotkey → slot mapping is derived from the current loadout order and recomputed on every loadout change. Covers the gamepad and touch mappings. |
| REG-CON-06 | CON-06 | Consumables | H | Activation is rejected when destroyed, in countdown, after battle end, or while a "cannot use" state is active. |

#### 3.17 Matchmaking

**Current WoT behavior.**
- 9.18 (2017) introduced template-based matchmaking (3/5/7 tier templates) and class limits. The 9.18 release is confirmed by the XVM changelog ("World of Tanks 9.18 worldwide release"). The template content rests on the doc 03 fact-check (Medium-High) (upgraded from R by fact-check).
- Players complain about map repetition; map exclusion and rotation have been adjusted over the years (R).

HULLDOWN's matchmaker is a pure algorithm (`ARCHITECTURE.md` §8).

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| MMK-01 | Teams unequal in class counts | — | [P] · Low | pattern |
| MMK-02 | Templates violated at low population | templates 9.18, 2017 | [R] · Medium (version sourced; defect is a pattern) | doc 03 §1.2; [XVM changelog](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md) |
| MMK-03 | The same map came up repeatedly; rotation and exclusion features were adjusted | — | [R] · Low | — |
| MMK-04 | A platoon was matched outside the tier spread rules | — | [P] · Low | pattern |
| MMK-05 | Queue stuck on "searching" after a reconnect, or the queue timer was wrong | — | [P] · Low | pattern |
| MMK-06 | A player entered battle with a vehicle sold or locked during the queue | — | [P] · Low | pattern |
| MMK-07 | Battle started short of players after load-time disconnects | — | [P] · Low | pattern |
| MMK-08 | Players matched across incompatible regions or clusters | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-MMK-01 | MMK-01, MMK-02 | Matchmaking | H | **For** populations 1, 2, 5, 10, 15, 29, 30, 31, 60 and 100 (`ARCHITECTURE.md` §13) × 50 seeds. **Then** every match meets the template, tier spread, class mirroring and limits, and team-size invariants. Bot fill is used only per policy. |
| REG-MMK-02 | MMK-03 | Matchmaking | H | With a map pool ≥ 3, no player gets the same map in 3 consecutive battles (OUR DESIGN CHOICE: ≤ 2). Checked over 10,000 simulated battles. |
| REG-MMK-03 | MMK-04, PLT-06 | Matchmaking, Platoon | H | Platoon members are always on the same team and within the platoon tier rule. |
| REG-MMK-04 | MMK-05 | Matchmaking, Data/Persistence | H+E | Tickets have a TTL (OUR DESIGN CHOICE: 120 s, refreshed by heartbeat). Leaving the hub removes the ticket. On leader fail-over (MemoryStore lock with TTL), no ticket is matched twice. Duplicate `MessagingService` notifications are idempotent. |
| REG-MMK-05 | MMK-06 | Matchmaking, Garage | H | Queuing locks the vehicle (REG-UI-02). Sell or modify during the queue is rejected. Leaving the queue unlocks it. |
| REG-MMK-06 | MMK-07 | Matchmaking, BattleLifecycle | H | If players fail to arrive within the load window (OUR DESIGN CHOICE 45 s), the bot-fill or abort policy is applied. A battle never starts with a team-size difference above `Config.Matchmaking`. |
| REG-MMK-07 | MMK-08 | Matchmaking | H | A ticket's region field is respected unless the relaxation schedule allows otherwise. |

#### 3.18 Platoon

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| PLT-01 | Invitation could not be accepted, or expired invites were still shown | — | [P] · Low | pattern |
| PLT-02 | Leader could not start after a member changed vehicle (stale ready state) | — | [P] · Low | pattern |
| PLT-03 | A member who left still appeared in the platoon UI | — | [P] · Low | pattern |
| PLT-04 | Platoon not marked for allies in battle | — | [P] · Low | pattern |
| PLT-05 | Platoon bonuses not applied | — | [P] · Low | pattern |
| PLT-06 | Platoon members split across teams | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-PLT-01 | PLT-01 | Platoon | H | Invite TTL is 60 s (OUR DESIGN CHOICE). Expired invites are removed from both sides. Accepting an expired or revoked invite fails with a clear error and no state change. |
| REG-PLT-02 | PLT-02 | Platoon | H | Any member vehicle change resets that member's ready flag. The leader can start iff all members are ready and valid per `PlatoonRules`. |
| REG-PLT-03 | PLT-03 | Platoon | H+E | Leave or disconnect updates the roster for all members within one message. Cross-server state is in MemoryStore with TTL. A lost message is fixed by a periodic reconcile (OUR DESIGN CHOICE: every 10 s). |
| REG-PLT-04 | PLT-05 | Platoon, Results/Rewards | H | Platoon reward modifiers (if any) apply exactly to members who started the battle in the platoon. |

#### 3.19 Battle lifecycle

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| BTL-01 | Capture progress not reset when the capturer was damaged | — | [P] · Low | pattern |
| BTL-02 | Battle did not end correctly when the last vehicles died simultaneously | — | [P] · Low | pattern |
| BTL-03 | Battle timer drifted between client and server | — | [P] · Low | pattern |
| BTL-04 | Reconnect after a crash failed, or returned the player to the wrong state | — | [P] · Low | pattern |
| BTL-05 | Inactivity detection penalized players who were stuck or overturned | — | [P] · Low | pattern |
| BTL-06 | Movement or firing possible during the countdown | — | [P] · Low | pattern |
| BTL-07 | A mutual kill was credited incorrectly | — | [P] · Low | pattern |
| BTL-08 | Shells in flight at battle end counted inconsistently | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-BTL-01 | BTL-01 | BattleLifecycle | H | Damage to a capturer resets or reduces its contribution per `Config.Battle`. Progress stays clamped to [0, 100]. Mixed-team presence pauses capture. |
| REG-BTL-02 | BTL-02, BTL-07 | BattleLifecycle | H | Victory is evaluated after all damage in the tick is applied. A mutual kill credits both kills. A last-pair mutual kill gives a draw (or the configured rule). Covered for every ordering of entity ids. |
| REG-BTL-03 | BTL-03 | BattleLifecycle, HUD | H | The client timer equals `serverEndTime − estimatedServerNow`. Drift is < 0.5 s after 15 min with simulated clock skew of ±2%. |
| REG-BTL-04 | BTL-04 | BattleLifecycle | H+E | Rejoining a battle server within the window gives back control of the same vehicle if it is alive, otherwise spectator mode. The rejoin snapshot contains everything the player's team knows. |
| REG-BTL-05 | BTL-05 | BattleLifecycle | H | AFK = no input for N s (OUR DESIGN CHOICE 90 s). Players who are stuck or overturned while still sending input are never flagged. |
| REG-BTL-06 | BTL-06 | BattleLifecycle | H | During the countdown, movement and fire are rejected. Turret rotation is allowed (OUR DESIGN CHOICE). |
| REG-BTL-07 | BTL-08 | BattleLifecycle, Projectile | H | Hits resolved on or before the end tick count. Projectiles in flight at the end tick are discarded (OUR DESIGN CHOICE). The outcome is deterministic. |

#### 3.20 Loading, crashes, client stability

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| LDR-01 | Crash when loading a specific map or vehicle | — | [P] · Low | pattern |
| LDR-02 | Freeze on the loading screen when joining late | — | [P] · Low | pattern |
| LDR-03 | Memory growth over long sessions, then a crash | — | [P] · Low | pattern |
| LDR-04 | Crash or hitch opening a screen with many items | — | [P] · Low | pattern |
| LDR-05 | Crash or broken UI after alt-tab or a resolution or display-mode change | — | [P] · Low | pattern |
| LDR-06 | Login loops or "server unavailable" loops | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-LDR-01 | LDR-01 | Data/Persistence, Map | H+E | (H) `ContentRegistry.validate()` builds every blueprint and map layout. (E) A nightly Open Cloud task builds every vehicle model and map in the engine and fails on any error or warning. |
| REG-LDR-02 | LDR-02 | BattleLifecycle | E | A late joiner receives the full snapshot. The loading screen closes when the snapshot is applied. After 20 s with no snapshot, it retries and then returns to the hub (OUR DESIGN CHOICE). |
| REG-LDR-03 | LDR-03 | Platform | E/M | Client soak of 30 consecutive battles: memory growth after warm-up < 10% (OUR DESIGN CHOICE). Developer Console LuaHeap and InstanceCount are tracked (see RBX-17). |
| REG-LDR-04 | LDR-04 | UI/Input | H | `VirtualList` with 1,000 items creates ≤ visible rows + 2 instances. Scrolling to the end and back leaks no instances. |
| REG-LDR-05 | LDR-05 | UI/Input | M | Resize and resolution change: `Layout` recomputes on `AbsoluteSize` change, with no overlapping HUD elements. |
| REG-LDR-06 | LDR-06 | Data/Persistence | H | A profile load failure gives a kick with a clear message after bounded retries: the first attempt, then 5 retries after 1, 2, 4, 8 and 16 s, so 6 attempts over 31 s (OUR DESIGN CHOICE, same schedule as R-DATA-1). Never an infinite loop and never a default profile save. (Corrected by fact-check: "5 attempts" with 5 backoff delays did not add up, and did not match R-DATA-1.) |

#### 3.21 Economy and persistence (garage transactions)

**Current WoT behavior.** Doc 05 covers purchases, research, XP conversion events ([A-xp-conv]), sale values, and timed or rental items.

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| ECO-01 | Credits deducted twice on a slow connection or double click | — | [P] · Low | pattern |
| ECO-02 | Purchase completed but the item appeared only after relog | — | [P] · Low | pattern |
| ECO-03 | XP or free-XP conversion rounding errors | — | [P] · Low | pattern |
| ECO-04 | Event discount applied outside its window | XP-conversion events [S] | [P] · Low | [A-xp-conv] |
| ECO-05 | Wrong sale value for a vehicle with mounted premium items | — | [P] · Low | pattern |
| ECO-06 | Rental or trial items not removed at expiry | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-ECO-01 | ECO-01 | Data/Persistence, Net/Security | H | The same `requestId` sent twice, concurrently or sequentially, applies once and returns the same result. Covered for every mutating remote. |
| REG-ECO-02 | ECO-02 | Data/Persistence | H | After a commit, the `ProfilePatch` is sent before the request's response (or in the same message). See REG-UI-06. |
| REG-ECO-03 | ECO-03 | Results/Rewards | H | Currencies are integers. Conversions floor and refund the remainder per config. Property: the sum of all balances × rates is conserved within ± 1 unit per transaction. |
| REG-ECO-04 | ECO-04 | Data/Persistence | H | Event windows are `[startUtc, endUtc)`. Tests at end − 1 ms and at end. |
| REG-ECO-05 | ECO-05 | Garage | H | Sale value follows the formula table, and mounted items are returned per REG-EQP-03. |
| REG-ECO-06 | ECO-06 | Data/Persistence | H | Timed items expire at the exact UTC instant on the next load or tick. There is no grace period to exploit. A battle started before expiry completes normally. |
| REG-ECO-07 | doc 05 "never stuck" | Results/Rewards | H | The auto-repair floor keeps the balance from ever going negative, and debt above the floor is waived (doc 05). |

#### 3.22 Controller and mobile input

WoT's PC client has little controller support. The console edition (Modern Armor) and Blitz (mobile) do; they are cited in docs 05 and 06. Entries here are generic [P].

| ID | Defect | Version / date | Prov. · Conf. | Source |
|---|---|---|---|---|
| INP-01 | Controller focus lost in menus after a dialog closed | — | [P] · Low | pattern |
| INP-02 | Button prompts or glyphs did not switch when the input device changed | — | [P] · Low | pattern |
| INP-03 | Sensitivity or aim-assist settings not applied | — | [P] · Low | pattern |
| INP-04 | Touch controls overlapped the HUD on small screens or notches | — | [P] · Low | pattern |
| INP-05 | Key rebind conflicts accepted silently | — | [P] · Low | pattern |

| Test | Covers | Subsystem | Auto | Given / When / Then |
|---|---|---|---|---|
| REG-INP-01 | INP-01 | Controller/Mobile | H+E | In Gamepad mode, after any modal open or close, `Focus` has a valid selected element (E: `GuiService.SelectedObject ~= nil`). |
| REG-INP-02 | INP-02 | Controller/Mobile | H | A change in `PreferredInput` (Touch, KeyboardAndMouse or Gamepad) switches `InputMode`, glyph sets and the HUD layout within 1 frame (`input/index.md`). |
| REG-INP-03 | INP-03 | Controller/Mobile | H | Sensitivity settings scale camera and aim deltas linearly. Applied live. |
| REG-INP-04 | INP-04 | Controller/Mobile, HUD | E | At each resolution in R-UI-1, the touch HUD controls do not overlap each other or the minimap, and lie inside `ScreenInsets.CoreUISafeInsets`. |
| REG-INP-05 | INP-05 | UI/Input | H | Binding a key already in use prompts to swap or cancel and never leaves two actions on one key in one context. |

---

### 4. Roblox multiplayer bug and exploit classes

All facts are from the local creator-docs:
`refs/creator-docs/content/en-us/...`, written below as `docs:` paths. Confidence is High unless stated. HULLDOWN's countermeasures follow `ARCHITECTURE.md` §§5, 7 and 12.

#### 4.1 RBX-01: DataStore stale overwrite and data loss (session locking)

**Current behavior.**
- If one player's data is in memory on two servers, the older server can save stale data over newer data. This causes data loss and **item duplication**.
- Typical triggers:
  - slow or retried final saves;
  - throttled `UpdateAsync` queues;
  - yields in `PlayerRemoving` before the save;
  - degraded servers;
  - **rapid disconnect and reconnect, e.g. teleports**.
- The fix is a lock written into the key's metadata atomically in `UpdateAsync`. The lock is refreshed by autosave, and taken over only after it expires.
- The Roblox sample auto-saves every **180 s** (`AUTO_SAVE_INTERVAL`). Its loop is **shared and not offset**: it saves every loaded player in parallel, so servers that start at the same time flush together. The doc **recommends** adding a random first-save offset per player within the interval (`task.wait(math.random() * AUTO_SAVE_INTERVAL)`), and HULLDOWN should do that (corrected by fact-check: the earlier text said the sample already offsets). Docs: the autosave interval must be **shorter than any session-lock expiration**.

**Sources.** `docs: cloud-services/data-stores/player-data-purchasing.md` (Session locking), `cloud-services/data-stores/best-practices.md`.

**Tests.**

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-DATA-01 | Data/Persistence | H | **Given** `MockDataStore` and servers A and B. **When** A loads user U (lock = A) and B tries to load U. **Then** B is refused while A's lock is fresh. A's autosave refreshes the lock. After A stops refreshing for `LOCK_STALE_S`, B takes over, and **A's next save is rejected** because A no longer holds the lock. |
| REG-DATA-02 | Data/Persistence | H | **Teleport hand-off.** U leaves hub A for battle server C. **Then** C never takes U's profile lock (R-DATA-3), or waits until A has released. No write sequence across A and C loses an increment. Checked with 1,000 randomized interleavings and injected latencies of 0–10 s. |

#### 4.2 RBX-02: Saving default data after a failed load

**Current behavior.** "Special care is needed to ensure fallback data doesn't later overwrite 'real' data." The sample marks such a profile as **errored** and never saves it. Purchases must be blocked while `hasErrored` is set. HULLDOWN's architecture instead **kicks with a message** (`ARCHITECTURE.md` §7). Both are valid; the invariant is "never write".

**Sources.** `docs: cloud-services/data-stores/player-data-purchasing.md` (Error handling, Load player data).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-DATA-03 | Data/Persistence | H | **When** every load attempt fails (MockDataStore error injection). **Then** no write call is ever issued for that key, the player is kicked with a localized message (or the profile is flagged errored), and purchase prompts are disabled. |

#### 4.3 RBX-03: Out-of-order retries and unknown write outcomes

**Current behavior.**
- Naive retry loops can apply an older write after a newer one. Retries must be processed **in order per key**.
- A failed write call "does not always guarantee that the backend write did not occur". Verify with a read that bypasses the cache (`UseCache = false`). By default, `GetAsync` caches for **4 s**.
- The `UpdateAsync` transform **may run multiple times**, **cannot yield**, and cancels the write if it returns `nil`.

**Sources.** `docs: cloud-services/data-stores/player-data-purchasing.md` (Retries); `error-codes-and-limits.md` (lines 8, 469–471); `versioning-listing-and-caching.md` (lines 223–257); `reference/engine/classes/GlobalDataStore.yaml` (UpdateAsync).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-DATA-04 | Data/Persistence | H | **Given** write A that fails and is retried, then write B. **Then** the per-key queue applies A then B, and the final value is B. |
| REG-DATA-05 | Data/Persistence | H | **Given** a mock that commits the write but reports failure. **When** the retry runs. **Then** idempotency rings (`processed.battles`, `processed.receipts`, `requestId`) prevent double application. |
| REG-DATA-06 | Data/Persistence | H | The transform function is pure and side-effect free: calling it 3× on the same input gives identical output and no external effects. It never yields (asserted via a mock that errors on yield). |

#### 4.4 RBX-04: DataStore limits and throttling

**Exact values.**

| Limit | Value |
|---|---|
| Server request budget (Read: Get / Update; Write: Set / Increment / Update; Remove) | **60 + numPlayers × 40 per minute** each. These are defaults: they can be changed with `DataStoreService:SetRateLimitForRequestType()`, and servers get a one-time startup burst. List is **5 + numPlayers × 2** |
| `UpdateAsync` budget use | consumes read **and** write budget |
| Experience-wide Read and Remove | **300 + concurrentUsers × 40 per minute** |
| Experience-wide Write | **300 + concurrentUsers × 20 per minute** |
| Experience-wide List | **300 + concurrentUsers × 2 per minute** |
| Throttled request queues | **30 requests each**; beyond that, requests are **dropped** with errors 301–306 |
| Per-key throughput | **25 MB/min read**, **4 MB/min write** |
| Value size | **4,194,304 characters** per key |
| Key name, data store name, scope | **50 characters** each |
| User metadata | **300 characters** total |
| String validity | must be valid **UTF-8** |
| Open Cloud | shares the same budget |

**Sources.** `docs: cloud-services/data-stores/error-codes-and-limits.md`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-DATA-07 | Data/Persistence | H | **Given** 30 players on a battle or hub server with autosave every 60 s ± 10 s jitter, join and leave saves, and battle rewards. **Then** simulated per-minute Get and Update counts stay < 50% of `60 + 30 × 40 = 1,260` (OUR DESIGN CHOICE: 50% headroom). **And** the experience-wide write rate per concurrent user stays < 50% of its 20/min share of `300 + CCU × 20`, i.e. ≤ 10 writes per user per minute, counting every `UpdateAsync` as both a read and a write (added by fact-check). Per-key writes are ≤ 1 per 6 s (OUR DESIGN CHOICE; the old 6 s per-key write cooldown is not in the current limits page, which instead caps per-key throughput at 4 MB/min write and 25 MB/min read). |
| REG-DATA-08 | Data/Persistence | H | The serialized profile (`JSONEncode` length) of a maxed-out fixture profile (all vehicles, max crew, full history rings) is < **512 KB** (OUR DESIGN CHOICE: warn at 512 KB, hard fail at 2 MB, 50% under the 4,194,304 limit). All strings are valid UTF-8 (`utf8.len` ≠ nil). Keys are ≤ 50 characters. |

#### 4.5 RBX-05: BindToClose save timing

**Exact values.**
- Bound functions run **in parallel**. The server waits **30 seconds**, then shuts down even if they are still running.
- Teleports are disabled during moderation shutdowns.
- The sample saves every player in parallel and clears stale queued requests (`skipAllQueuesToLastEnqueued`).
- HULLDOWN `ServiceLoader` budget: **25 s** for `Stop()` in reverse dependency order.

**Sources.** `docs: reference/engine/classes/DataModel.yaml` (BindToClose); `player-data-purchasing.md` (Save player data).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-DATA-09 | Data/Persistence, BattleLifecycle | H | **Given** 30 loaded profiles, a mock store with 0.5–8 s latency per write, and 2 failures injected. **When** close fires. **Then** all saves start within 100 ms (parallel), stale queued writes are skipped to the last one, every lock is released, and the whole flow finishes ≤ 25 s on `FakeClock`. If `PlayerRemoving` and close both fire for one player, there is exactly one final save. |
| REG-DATA-10 | BattleLifecycle | H | A battle server closing mid-battle writes pending results for every participant (R-DATA-3) before the deadline, so rewards are not lost. |

#### 4.6 RBX-06: Purchase receipt double grant or lost purchase

**Current behavior.**
- `ProcessReceipt` is called for unresolved purchases on purchase and when the user **joins a server**.
- It has **no time-based retry** and **no timeout**.
- It may run **on two servers at the same time**.
- Pending receipts are handled in **non-deterministic order**.
- The user must be on the server for the callback to run.
- `PurchaseGranted` may still fail to be recorded on the backend, in which case the purchase stays unresolved.
- If no callback is set, receipts are auto-acknowledged and cannot be recovered.

The required sequence is:
1. Check that the `PurchaseId` was not already handled.
2. Grant the purchase in memory.
3. Record the `PurchaseId`.
4. **Save.**
5. Return `PurchaseGranted` only on a successful save, otherwise `NotProcessedYet`.

Also:
- If the player data has not loaded yet, wait, but stop waiting if the player leaves.
- Never trust `PromptProductPurchaseFinished`.
- `UserOwnsGamePassAsync` is **cached**. It updates on `PromptGamePassPurchaseFinished`, and purchases made outside the experience may take minutes to show.

**Sources.** `docs: reference/engine/classes/MarketplaceService.yaml` (ProcessReceipt; UserOwnsGamePassAsync caching); `cloud-services/data-stores/player-data-purchasing.md` (Developer Product processing); `scripting/security/client-server-boundary.md` (MarketplaceService).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-PAY-01 | Data/Persistence, Platform | H | The same `receiptInfo` is delivered 3× (sequentially and concurrently). It is granted once, and every later call returns `PurchaseGranted` without a re-grant. |
| REG-PAY-02 | Data/Persistence | H | The save fails after the in-memory grant, so the callback returns `NotProcessedYet`. The next call finds the `PurchaseId` recorded but unsaved and returns `NotProcessedYet` until a save succeeds, then `PurchaseGranted`. Exactly one grant is persisted. |
| REG-PAY-03 | Data/Persistence | H | The callback arrives before the profile has loaded. It waits for the load. If the player leaves first, it returns `NotProcessedYet` promptly; the thread never dangles. |
| REG-PAY-04 | Data/Persistence | H | Two servers run the callback for the same purchase. Because of the session lock, only the lock holder can save, so the second returns `NotProcessedYet`. One grant in total. |
| REG-PAY-05 | Platform | H | `processed.receipts` ring capacity is 200 (OUR DESIGN CHOICE) and survives migration. Unknown product ids return `NotProcessedYet` and are logged, never `PurchaseGranted`. |
| REG-PAY-06 | Platform | H | Game-pass entitlements update immediately on `PromptGamePassPurchaseFinished` (server re-check). A client signal alone grants nothing. |

#### 4.7 RBX-07: Teleport failures (hub ↔ battle)

**Current behavior.**
- `TeleportAsync` is **server-only** and accepts **≤ 50 players per call**.
- It can throw, and it can also fail after initiating, through **`TeleportInitFailed`** with an `Enum.TeleportResult`: Success, Failure, GameNotFound, GameEnded, GameFull, Unauthorized, **Flooded**, IsTeleporting.
- The doc's `SafeTeleport` makes up to **5 attempts** (`ATTEMPT_LIMIT = 5`, i.e. the first call plus 4 retries) **1 s apart** (`RETRY_DELAY = 1`). Its `handleFailedTeleport` waits **15 s on Flooded** (`FLOOD_DELAY = 15`), 1 s on `Failure`, then calls `SafeTeleport` again. It raises an error for every other result: GameNotFound, GameEnded, GameFull, Unauthorized and IsTeleporting (corrected by fact-check: the earlier text said "retries 5 times").
- Teleport data is **unencrypted, client-visible and spoofable**. Do not use it for secure data.
- TeleportService does not work in Studio playtests, so test it with mocks or published places.

**Sources.** `docs: projects/teleport.md` (Handle failed teleports, teleport data); `reference/engine/classes/TeleportService.yaml` (Group Teleport Limitations; GetLocalPlayerTeleportData); `reference/engine/enums/TeleportResult.yaml`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-TP-01 | Matchmaking, Platform | H | `TeleportAdapter` mock: 4 throws then success → teleported, 5 attempts. `TeleportInitFailed(Flooded)` → waits 15 s, then retries. `GameFull`, `Unauthorized`, `GameNotFound` or `GameEnded` → no retry: the ticket is re-queued and the vehicle unlocked. `IsTeleporting` → no new call is issued. 51 players → exactly 2 calls (50 + 1), never one call of more than 50 (corrected by fact-check: the earlier "33 players" case never needed a split, so it tested nothing). |
| REG-TP-02 | Matchmaking, Net/Security | H | The battle server ignores TeleportData for anything trusted. The participant list and loadouts come from the MemoryStore manifest written by the matchmaker. A joining user not in the manifest is kicked. |
| REG-TP-03 | Matchmaking | H | If a reserved battle server never receives a player within 45 s (OUR DESIGN CHOICE), that player's slot is bot-filled or the battle is aborted per policy, and the hub restores the player's vehicle and queue state. |

#### 4.8 RBX-08: RemoteEvent spam and flood

**Exact values.**
- `RemoteEvent` and `UnreliableRemoteEvent` C2S traffic: **about 500 requests per second per client**, shared among **all remotes of the same type**.
- Excess reliable events are **processed later, not dropped**, in order. A spammer therefore creates a growing server-side backlog.
- Excess unreliable events are **dropped**. Unreliable payloads over **1,000 bytes** are dropped.
- For a reliable `RemoteEvent`, messages that arrive while no handler is connected are **queued**. The queue is limited in count and memory, and messages beyond it are discarded. An `UnreliableRemoteEvent` with no handler **discards the message immediately** (clarified by fact-check).
- Handler start order is guaranteed; completion order is not, if handlers yield.

**Sources.** `docs: reference/engine/classes/RemoteEvent.yaml` (Throttling); `reference/engine/classes/UnreliableRemoteEvent.yaml`; `scripting/events/remote.md` (Delivery guarantees); `scripting/security/client-server-boundary.md` (Rate limiting, token bucket).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-NET-01 | Net/Security | H | One fake client fires 10,000 events in 1 s at each C2S remote. Handler invocations are ≤ burst + rate × t per the remote's `rate`. Excess calls cost **zero** handler work (dropped before decode beyond a cheap size check). Strikes accumulate, and the kick threshold is reached. Server memory per player stays bounded (no unbounded queue). |
| REG-NET-02 | Net/Security | H | `InputPacket` codec: ≤ 900 bytes (assert on max-size fixtures). Packets with sequence numbers older than the latest processed are ignored. Duplicate inputs (the redundancy of 3) are applied once. |
| REG-NET-03 | Net/Security | H | **Static P0:** the `Net/Remotes` registry contains no C2S argument named or typed like `damage`, `hp`, `hit*`, `target*Result`, `reward*`, `credits`, `xp` or `position` (except the bounded aim point). This guards against client-trusted damage (RBX-10). |
| REG-NET-04 | Net/Security | H | Handlers that run before Start (queued messages) are covered: remotes are created in `Init` and handlers connected before the client is signalled ready, so nothing relies on the engine queue. |

#### 4.9 RBX-09: Malformed arguments (NaN, inf, mixed tables, metatables)

**Current behavior.**
- NaN is of type "number" yet fails every comparison, which bypasses range checks. ±inf is also a valid number. Validate with `math.isfinite` (Roblox `math` library, `reference/engine/libraries/math.yaml`). The headless runner is Lune 0.10.4 (`rokit.toml`), and nobody has checked that its bundled Luau includes `math.isfinite`. If it does not, the shared validator needs a fallback: `x == x and x ~= math.huge and x ~= -math.huge` (added by fact-check).
- Non-string table indices are converted to strings.
- Mixed numeric and string keys, and `nil` holes, are unsafe.
- Functions arrive as nil, and metatables are stripped.
- Non-replicated instances arrive as nil.
- DataStores reject invalid UTF-8, NaN or nil indices, and Instances.

**Sources.** `docs: scripting/security/client-server-boundary.md` (Value validation, The danger of NaN, Data store manipulation); `scripting/events/remote.md` (Argument limitations).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-NET-05 | Net/Security | H | **Fuzzer.** For each C2S remote schema, 10,000 generated hostile argument sets: NaN, ±inf, −0, 2^53+1, huge strings (1 MB), invalid UTF-8, deep tables (depth 100), mixed tables, nil holes, wrong types, extra args, Instances, booleans for numbers. **Then** the schema rejects every invalid value, the handler never sees one, no error escapes `pcall`, and no NaN reaches any `VehicleState` (checked by REG-INV invariants). |
| REG-NET-06 | Net/Security | H | `InputValidator`: throttle and steer are clamped to [−1, 1]. Aim direction is renormalized, and a zero or NaN vector is rejected. A fire request is validated against alive state, reload, ammo, gun state, countdown and battle-ended. |

#### 4.10 RBX-10: Client-trusted damage and hit claims

**Current behavior.**
- Docs: "never trust the client". Exploiters can fire remotes "at any frequency with arbitrary arguments", decompile client scripts, and change their local DataModel.
- For hit claims, the docs recommend validating:
  - the origin is near the shooter;
  - the hit is near the target;
  - there is no static obstruction;
  - the fire rate, ammo, team and alive state.
- HULLDOWN goes further: **the server computes ballistics**, so clients never claim hits.

**Sources.** `docs: scripting/security/security-tactics.md`; `client-server-boundary.md` (Weapon targeting).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-SEC-01 | Net/Security, Projectile | H | A fire request carries only `{requestId, ammoSlot?}`. The server derives origin and direction from its own `TurretSim` state. A forged client aim beyond the turret limits is clamped. 100 forged requests during reload produce 0 shots. |

#### 4.11 RBX-11: Physics flinging and network-ownership abuse

**Current behavior.**
- A client that owns parts (including its own character) can teleport them and set velocities to extreme values, including **Inf/NaN in CFrames**. This can **fling other players' parts**.
- Owners can also manipulate `Touched` events.
- The engine auto-assigns ownership of unanchored parts near a character.
- The server always owns anchored parts.
- `SetNetworkOwner(nil)` gives the server ownership of critical parts, at the cost of jitter.

**Sources.** `docs: scripting/security/network-ownership.md`; `physics/network-ownership.md`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-SEC-02 | Platform, Map | E | Runtime scan in battle places: every `BasePart` under `Workspace.Map` is `Anchored`. There are no unanchored server-created gameplay parts; debris VFX are client-only. `Players.CharacterAutoLoads == false` in battle places (R-SEC-2), so no client owns any assembly. |
| REG-SEC-03 | Platform | H | No gameplay logic subscribes to `Touched` on the server (static check over `ServerScriptService`). |

#### 4.12 RBX-12: Speed, fly, teleport and noclip exploits

**Current behavior.**
- With client-owned characters, exploiters can set `WalkSpeed` locally, fly, teleport and noclip, and the server sees only the replicated result.
- Server-side movement validation is hard: it needs latency tolerance and leaky-bucket accumulators.
- "Server authority" (beta) moves physics to the server.
- HULLDOWN simulates vehicles on the server from inputs, which makes this class impossible by construction (`ARCHITECTURE.md` §12).

**Sources.** `docs: scripting/security/network-ownership.md` (Movement validation).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-SEC-04 | VehicleSim, Net/Security | H | **Given** worst-case legal inputs (full throttle and steer every tick) for 10 min on every map. **Then** speed ≤ `stats.maxSpeed` × (1 + slope bonus cap) on every tick, there is no position change without simulation, and server-flagged teleports occur only at spawn or respawn. The client cannot send a position. |

#### 4.13 RBX-13: Memory leaks (connections, player tables)

**Current behavior.**
- Connections are never garbage-collected while connected.
- **`Player` objects and character models are not destroyed automatically when a user leaves** unless `Workspace.PlayerCharacterDestroyBehavior` is `Enabled`. The enum values are `Default` (engine default), `Disabled` and `Enabled`. Connections on these objects leak. The property is tagged **NotScriptable**, so set it in the place file. The docs' scriptable alternative is `task.defer(player.Destroy, player)` on `PlayerRemoving`, plus `task.defer(character.Destroy, character)` on `CharacterRemoving` (corrected by fact-check).
- Tables keyed by player leak if not cleared on leave.
- Watch **LuaHeap**, **InstanceCount** and **PlaceScriptMemory**.
- `Destroy()` disconnects all connections and locks `Parent`.
- With deferred signals, `Disconnect()` drops pending invocations, while `Destroy()` still runs them.

**Sources.** `docs: performance-optimization/improve.md` (Script memory usage); `reference/engine/classes/Workspace.yaml` (PlayerCharacterDestroyBehavior); `reference/engine/classes/Instance.yaml` (Destroy); `scripting/events/deferred.md`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-MEM-01 | Platform | H | `MockPlayers`: 1,000 join/leave cycles, each with a profile load, battle queue, platoon invite and rate-limiter bucket. **Then** every per-player registry is empty (rate-limiter buckets, Net strikes, Trove counts, Data sessions, Queue tickets, platoon membership) and the live `Trove` count returns to baseline. |
| REG-MEM-02 | Platform | E | Server soak in a private live server or a Studio test session (not Luau Execution): 2 h of bot battles. After a 10 min warm-up, LuaHeap and InstanceCount growth is < 10% (OUR DESIGN CHOICE). `Workspace.PlayerCharacterDestroyBehavior = Enabled` is asserted by a **CI lint of the place/Rojo project file**, because the property is NotScriptable and cannot be read at boot. The scriptable `task.defer(player.Destroy, player)` fallback on `PlayerRemoving` is asserted by REG-MEM-01 (corrected by fact-check). |

#### 4.14 RBX-14: UI not scaling, safe areas, input modes

**Current behavior.**
- Use `Scale` sizing with `AnchorPoint`, and adapt layouts with `GuiService.ViewportDisplaySize`.
- Constrain text with `UITextSizeConstraint`.
- `ScreenGui.ScreenInsets` options:
  - `CoreUISafeInsets` (default) keeps UI clear of the top bar and cutouts, and is recommended for interactive UI;
  - `DeviceSafeInsets` avoids only notches;
  - `TopbarSafeInsets`;
  - `None`, for non-interactive backgrounds only.
- `UserInputService.PreferredInput` reports the player's current primary input.

**Sources.** `docs: includes/ui/screen-insets.md`; `projects/cross-platform.md`; `ui/size-modifiers.md`; `input/index.md`. Doc 06 covers layout tokens.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-UIX-01 | UI/Input, Controller/Mobile | E | Render every screen at the R-UI-1 resolution matrix. **Then** no interactive `GuiObject` lies outside the safe area, no two interactive elements overlap, touch targets are ≥ 48×48 px on the Compact layout (OUR DESIGN CHOICE, matching the doc 06 layout tokens), and no clipped text without explicit truncation. (Corrected by fact-check: the earlier 44×44 px contradicted doc 06. Roblox docs do mention a size: the UI-design tutorial cites the W3C/WCAG touch-target guidance of at least 9×9 mm, in `tutorials/curriculums/user-interface-design/choose-an-art-style.md`.) |
| REG-UIX-02 | UI/Input | H | Static check: no `ScreenGui` with interactive children uses `ScreenInsets.None`, and no Screen module sets literal pixel sizes outside `Layout` tokens. |

#### 4.15 RBX-15: StreamingEnabled nil-instance errors

**Current behavior.**
- With streaming, indexing a non-streamed `Workspace` descendant with `.` **throws**, and `FindFirstChild` returns **nil**.
- `WaitForChild` can yield forever, so give it a timeout.
- A streamed-out instance is parented to nil, not destroyed.
- `ChildAdded`/`ChildRemoved` and CollectionService signals **fire on stream in and out**, indistinguishable from real spawns.
- Recommended settings: `StreamingIntegrityMode.PauseOutsideLoadedArea`, `StreamOutBehavior.Opportunistic`, `StreamingTargetRadius` 1,024 (default), target radius > min radius.
- Persistent models need `Workspace.PersistentLoaded`.
- `Player.ReplicationFocus` defaults to the character's `PrimaryPart` when nil.

**Sources.** `docs: workspace/streaming/index.md`; `workspace/streaming/techniques.md`; `reference/engine/classes/Player.yaml` (ReplicationFocus).

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-STR-01 | Map, UI/Input | H | Static lint: client code never indexes `workspace.<Map>...` with `.`, and only uses `MapIndex` lookups, which tolerate nil. `WaitForChild` always has a timeout argument in client code. |
| REG-STR-02 | Map | E | Streaming test in a published battle place: the camera teleports across the map 50× in 60 s. **Then** there are no client errors, map-tag handlers fire balanced add and remove counts, and `ReplicationFocus` follows the player's vehicle anchor part. |

#### 4.16 RBX-16: Race conditions on PlayerAdded and CharacterAdded; deferred signals

**Current behavior.**
- `PlayerAdded` does not fire for players already present when the handler connects (e.g. solo playtest, late-required scripts). The docs recommend a shared `onPlayerAdded` that is also called for existing players.
- `CharacterAdded` fires **before the character is parented to Workspace**, and accessories arrive later.
- With `SignalBehavior.Deferred` (recommended, and the future default), handlers run at the next resumption point. The re-entrancy depth limit is **10**. `SignalBehavior.Default` currently behaves as `Immediate`, while new template places are set to `Deferred`. `Workspace.SignalBehavior` is NotScriptable, so set it in the place file (clarified by fact-check).
- `RemoteFunction` and `RemoteEvent` have no relative ordering guarantee; use sequence numbers.

**Sources.** `docs: reference/engine/classes/Players.yaml` (PlayerAdded); `Player.yaml` (CharacterAdded); `scripting/events/deferred.md`; `scripting/events/remote.md`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-RACE-01 | Platform | H | `MockPlayers` adds 3 players **before** `Start`, and 3 more during `Start` while handlers connect. Each is initialized exactly once (no double init when both paths fire). |
| REG-RACE-02 | Platform | E | The full client and server suites run in a place with `Workspace.SignalBehavior = Deferred` and pass with no ordering-dependent failures. |

#### 4.17 RBX-17: MemoryStore and MessagingService in matchmaking

**Exact values.**

| Item | Value |
|---|---|
| MemoryStore memory quota | **64 KB + 1.2 KB × users** |
| MemoryStore request units | **1,000 + 120 × CCU per minute** |
| Per-partition throttling | from about **30,000 units/min**. The docs call this an estimate that can change |
| Per data structure | **100,000 request units/min** (`DataStructureRequestsOverLimit`) (added by fact-check) |
| Hash-map item limits | about **5,000 write and 15,000 read request units per min** per item key |
| Value size | **32 KB** max |
| Default expiration | **45 days** for `MemoryStoreQueue:AddAsync` and `MemoryStoreSortedMap:SetAsync`; the maximum is 3,888,000 s, which is also 45 days (set it short) |
| Queue invisibility timeout | defaults to **30 s**; items must be removed with `RemoveAsync` before it expires |
| MessagingService delivery | **best effort, not guaranteed** |
| MessagingService message size | **1 kB** |
| Messages sent per server | **600 + 240 × players per min** |
| Messages received per topic | **(40 + 80 × servers) per min** |
| Messages received for the entire game | **(400 + 200 × servers) per min** (added by fact-check) |
| Subscriptions per server | **20 + 8 × players** |
| Subscribe requests per server | **240 per min** (added by fact-check) |

**Sources.** `docs: cloud-services/memory-stores/index.md`; `reference/engine/classes/MemoryStoreQueue.yaml`; `reference/engine/classes/MessagingService.yaml`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-MQ-01 | Matchmaking | H | `MockMemoryStore` with invisibility expiry: if the matchmaker reads tickets and crashes before `RemoveAsync`, the tickets reappear after 30 s and are matched once. Ticket TTL is ≤ 120 s, never the 45-day default. |
| REG-MQ-02 | Matchmaking, Platoon | H | 20% of `MessagingService` messages dropped and 5% duplicated: hubs still converge through periodic MemoryStore polling (every 5 s, OUR DESIGN CHOICE), and duplicate "match ready" messages teleport once. |

#### 4.18 RBX-18: Unfiltered player text

**Current behavior.** The developer must filter any displayed text not under their control. Use `TextService:FilterStringAsync` with `GetNonChatStringForBroadcastAsync` or `GetNonChatStringForUserAsync`. Text stored in DataStores must be filtered on retrieval. Do not filter per keystroke. Experiences that fail to filter are removed until fixed.

**Sources.** `docs: ui/text-filtering.md`.

| Test | Subsystem | Auto | Given / When / Then |
|---|---|---|---|
| REG-TXT-01 | UI/Input, Platform | H | Every remote that accepts free text (platoon name, loadout preset name, custom emblem text) routes through `TextFilterAdapter` before storing or broadcasting, and re-filters on display. Checked statically against the `Remotes` registry schema type `UserText`. |

---

## Implementation recommendations for HULLDOWN (Roblox)

**R-QA-1. Layout, naming and traceability.**
- One spec per regression ID group: `tests/Regression/<Subsystem>/<ID>.spec.luau`, e.g. `tests/Regression/Spotting/REG-SPT-08.spec.luau`.
- Each spec header names the catalogue entries it covers (e.g. `-- covers: SPT-08 (doc 07 §3.6)`).
- Each fixed HULLDOWN bug gets an ID `HD-<n>` and a spec.
- Our own release notes list "Fixed: … (guarded by REG-xxx)".

**R-QA-2. Priority tiers** (OUR DESIGN CHOICE).

| Tier | When it runs | Contents |
|---|---|---|
| **P0** | every commit, inside `scripts/check.sh` | all H tests in Data/Persistence, Net/Security, Armor/Penetration, Results/Rewards and the economy (Transactions), plus REG-SPT-08 and REG-NET-03. Must finish in < 3 min. |
| **P1** | nightly | headless bot soaks (REG-VEH-01, 30 bots × 30 sim-min × every map); map scanners (REG-MAP-02); fuzzers (REG-NET-05 at 100k cases; P0 runs it at 10k); determinism (REG-RPL-02). Static E-tests run through Open Cloud Luau Execution: REG-MAP-01, REG-MAP-06, REG-LDR-01 and REG-SEC-02. All other E-tests run in a Studio test session or a private live server with a test-runner hook (corrected by fact-check, see R-QA-4) |
| **P2** | per release | the M checklist: UI flows on PC, gamepad and phone; audio listening; device matrix |

**R-QA-3. A shared invariant harness** (`tests/Harness/Invariants.luau`). Run it after every tick of every headless battle and soak. It checks:
- no NaN or inf anywhere in `VehicleEntity`;
- `0 ≤ hp ≤ maxHp`;
- module states are valid enums;
- ammo ≥ 0;
- reload ≥ 0;
- hull bottom ≥ ground − 0.05 m unless falling;
- the vehicle is inside map bounds;
- the spotted set equals the set of vehicles replicated to each team;
- the damage ledger sum equals total HP lost;
- capture progress is within [0, 100];
- no input is accepted from a destroyed vehicle;
- the voice-registry count per destroyed entity is 0 (client harness).

Rationale: most WoT [P] defects violate one of these invariants. One harness covers dozens of them at once.

**R-QA-4. Engine tests through Open Cloud Luau Execution.**
- The local OpenAPI exposes `POST /cloud/v2/universes/{universe_id}/places/{place_id}/versions/{version_id}/luau-execution-session-tasks`, with logs and an optional binary output. Its task timeout **defaults to 5 minutes** (`refs/.../reference/cloud/openapi.json`).
- Per the `RunService` context table, it runs with `IsServer = true` and `IsRunning = false`. That suits static geometry scans: REG-MAP-01, REG-MAP-06, REG-LDR-01 and REG-SEC-02.
- The API key lives in CI secrets, never in the repo, per `ARCHITECTURE.md` §11.
- **Unverified:** whether `WorldRoot:Raycast` against a fully built map behaves identically when the simulation is not running. Smoke-test this first; see Open questions.
- **Not suitable for Luau Execution** (added by fact-check). The task has `IsClient = false` and `IsRunning = false`, and its timeout defaults to 5 minutes. So any test that needs connected clients, rendering, a running simulation or a long soak must run elsewhere: REG-MEM-02 (2 h soak), REG-STR-02, REG-RACE-02, REG-LDR-02, REG-LDR-03, REG-RET-02, REG-MRK-05, REG-UI-12, REG-UIX-01 and REG-INP-04.

**R-QA-5. Determinism contract** (enables REG-RPL-02 and bug repro).
- `Shared` code must not read wall-clock time (only the injected `Clock`).
- Randomness comes only from the match-seeded `RNG` with per-system substreams.
- Entity iteration is by sorted id.
- Every headless battle emits an event-stream hash.
- A bug report from a live server can include `(buildId, contentHash, seed, inputLog)`, which turns it into a replay fixture.

**R-MAP-1. Map QA pipeline.** Run it on every change to `Content/Maps/*`:
- (1) REG-MAP-02 reachability flood-fill on a 2 m grid;
- (2) REG-VEH-01 stuck soak, with stuck = |throttle| ≥ 0.5 and < 1.0 m displacement over 5.0 s;
- (3) REG-MAP-01 collision/visual parity (0.25 m tolerance) and invisible-blocker scan;
- (4) border sealing;
- (5) spawn exposure, REG-MAP-05;
- (6) minimap regeneration with a hash check, REG-MINI-02.

All are OUR DESIGN CHOICE thresholds. Rationale: in WoT, map-change sections listing stuck spots and exploit positions are the most persistent fix family. We generate maps from data, so these checks are cheap and fully automatable.

**R-ARM-1. Armor watertightness** (REG-ARM-01). Run it for every vehicle on every content change. Zero leaks allowed out of 10,000 rays per configuration. Because `ArmorGeometry` and the visual `VehicleRenderer` both derive from one `Blueprint`, the test enforces the property WoT has had to patch per vehicle: the collision model matches the visual model.

**R-UI-1. Resolution and device matrix** (OUR DESIGN CHOICE).
- Desktop: 1280×720, 1366×768, 1920×1080, 2560×1440, 3840×2160.
- Phone landscape (logical px): 667×375, 844×390, 932×430.
- Tablet: 1024×768, 1180×820.
- TV: 1920×1080 with a 5% safe margin (doc 06 TV layout).

Run REG-UIX-01 and REG-INP-04 over this matrix in Studio's device emulator (E or M). The client store pattern removes the "stale value" family:
- screens read only selectors over `ClientStore`;
- `ProfilePatch` messages carry sequence numbers, and a gap triggers a resync (REG-UI-06).

**R-DATA-1. Session lock parameters** (OUR DESIGN CHOICE, consistent with the docs' rule that autosave must be shorter than lock expiry).
- Autosave and lock refresh: every **60 s ± 10 s** jitter, as in `ARCHITECTURE.md`. Offset each player's first save randomly within the interval. The Roblox sample does **not** do this, but its docs recommend it (corrected by fact-check).
- `LOCK_STALE_S` = **180 s** (3 missed refreshes) before another server may steal the lock.
- On a lock conflict at load, publish a best-effort `MessagingService` "release request" to the holder's jobId, then retry the load with backoff 1, 2, 4, 8 and 16 s.
- After the retries, kick with a clear message; the player can rejoin once the lock is stale.
- Budget check: 30 players × 1 write per minute ≪ `60 + 30 × 40` = 1,260 per minute (server limit). The aggregate check is the experience-wide Write limit, `300 + CCU × 20` per minute: 1 `UpdateAsync` per player per minute uses about 5% of each user's 20/min share, and the same call also uses the Read budget (added by fact-check).

**R-DATA-2. Idempotency rings.**
- `processed.receipts` holds 200 `PurchaseId`s.
- `processed.battles` holds 200 battleIds.
- `requestId` keeps the last 50 per session.

All are OUR DESIGN CHOICE sizes. They cover pending-receipt replays (which happen on rejoin) and duplicate reward application.

**R-DATA-3. Battle servers do not take profile locks** (OUR DESIGN CHOICE; it refines `ARCHITECTURE.md` §7, so coordinate with the architecture owner).
- The battle server reads loadouts from the matchmaker's MemoryStore manifest.
- At battle end, it writes each participant's rewards to a pending-results record, using `UpdateAsync` on a per-user `Pending_<UserId>` key appended by battleId.
- The hub that holds the profile lock applies pending results idempotently by battleId.

Rationale: teleports are the scenario the docs name as most prone to stale-save races. This removes lock hand-offs on every battle, and it also covers the case where a player never returns to a hub.

**R-SEC-1. Net layer.**
- Token bucket per player per remote.
- Schema validation with `math.isfinite` on every number.
- Strings: UTF-8 check plus a length cap.
- Table shapes are checked (no mixed or holey tables).
- All of the above runs before any handler.
- Unreliable payloads ≤ 900 bytes (engine drop limit: 1,000).
- Fuzz with REG-NET-05.

**R-SEC-2. No characters in battle places.**
- Set `Players.CharacterAutoLoads = false`.
- Drive camera and streaming focus with `Player.ReplicationFocus` set to a server-anchored focus part that follows the vehicle.
- Set `Workspace.PlayerCharacterDestroyBehavior` = Enabled in every place **file** (Studio properties or the Rojo project). The property is NotScriptable, so no script can set or check it. Guard it with a CI lint of the project file, and also call `task.defer(player.Destroy, player)` on `PlayerRemoving` as a scriptable backstop (corrected by fact-check).

Rationale: this removes the character-based fly, noclip and fling surface, and the player and character leak class. **Needs an engine check** that streaming and camera behave well without characters (Open questions).

**R-SEC-3. Teleport adapter.**
- Up to 5 attempts, 1 s apart (the doc sample's `ATTEMPT_LIMIT = 5`). Wait 15 s on `Flooded` and 1 s on `Failure`. No retry on `GameFull`, `Unauthorized`, `GameNotFound` or `GameEnded`. On `IsTeleporting`, issue no new call (corrected by fact-check).
- Overall deadline **40 s**, then re-queue and unlock the vehicle (OUR DESIGN CHOICE). This must stay shorter than the battle server's 45 s arrival window (REG-TP-03, REG-MMK-06), so the hub gives up before the battle server bot-fills or aborts the slot. (Corrected by fact-check: the earlier 60 s deadline outlasted the 45 s window, so a player could arrive after their slot had been filled.)
- Use `TeleportOptions.ReservedServerAccessCode` from the matchmaker manifest.
- Never trust TeleportData.

**R-AUD-1. Scope-bound voices.**
- `AudioEngine.play(scope, cue)` requires a scope (entity, battle, screen). Destroying the scope stops its loops.
- 32-voice budget with stealing (doc 06).
- The music state machine is table-driven (REG-SND-04).

---

## Open questions / uncertain items

1. **The WoT catalogue is not verified line by line.** 163 of 183 entries are [P] patterns and 6 are [R] recollections. A further 3 are [S]/[R]: the feature is sourced but the defect is recalled.
   - *Action:* with web access, open the release-notes pages listed in §1 for every version from 1.0 to 2.4. Copy concrete "Fixed issues" lines (vehicle, map, square, version) into a companion table, and map each to an existing REG test.
   - Expected effect: the test list changes little; the evidence column gets stronger.
2. **WoT version and date attributions tagged [R]:**
   - wheeled vehicles in 1.4 (2019). Partly corroborated by fact-check: the XVM changelog lists a WoT 1.4.0.1 micropatch dated 2019.03.06. Its build for WoT 1.3.0 already added wheeled-vehicle hint options, so the exact release version is still open;
   - matchmaking templates in 9.18 (2017). The 9.18 release is now sourced (XVM changelog), and the template content is Medium-High per the doc 03 fact-check;
   - map-repetition adjustments;
   - replays incompatible across versions;
   - the server-reticle option and the "ghost shells" explanation.

   Each needs a source.
3. **GSOR 1008 (Dec 2020) details.** We know only the title ("APCR shell penetration issue"); its content was not read. Does it describe a bug or a design change in APCR drop-off?
4. **Overturn and drowning rules for HULLDOWN** (REG-VEH-05, REG-VEH-10) depend on `Config.Movement` values not yet chosen: self-recovery vs timed destruction. The test is written against config either way.
5. **Ammo-rack detonation with 0 stored shells** (REG-ARM-08) is a design choice. The WoT behavior was not verified.
6. **Spotting linger.** Doc 02's fact-check now confirms WoT's 10 s default (High). The earlier text here said Medium, which was out of date (corrected by fact-check). REG-SPT-06 still uses whatever `SPOT_LINGER_S` is configured.
7. **Open Cloud Luau Execution.** It runs with `IsRunning = false`. We need to confirm that spatial queries (`Raycast`, `Blockcast`) against the built map behave identically to a running server. If not, run E-tests in a Studio test session or a live private server with a test-runner hook.
8. **Characterless battle places** (R-SEC-2). Confirm in the engine that camera control, `StreamingEnabled` with a custom `ReplicationFocus`, proximity voice or chat (if used) and core UI behave without a character. Confirm that `PauseOutsideLoadedArea` does not misfire when no character exists.
9. **R-DATA-3 versus `ARCHITECTURE.md` §7.** The architecture says `RewardService` applies rewards idempotently, but it does not say on which server role. If rewards are applied on battle servers, we need lock hand-off tests (REG-DATA-02) instead of the pending-results design.
10. **Touch target size.** We use 48×48 px on Compact, the doc 06 token (corrected by fact-check: the earlier figure was 44×44 px). The Roblox UI tutorial cites WCAG's ≥ 9×9 mm, which depends on the device's px-per-mm. Confirm with mobile playtests in the Device Simulator's "Physical size" mode.
11. **Replays** are optional for HULLDOWN. §3.12 tests apply only if replays are built. The determinism contract (R-QA-5) is recommended regardless, for bug reproduction.
12. **Remote throttle** is "approximately 500 requests per second, per client" and shared per remote type (docs). Exact behavior under sustained overload (backlog limits) is undocumented. REG-NET-01 therefore enforces our own limits far below it.

---

## Verification log

Adversarial fact-check pass on 2026-10-05. Each claim was assumed wrong until a source confirmed it.
- **Roblox claims** were checked by grep against the local creator-docs clone, `refs/creator-docs/content/en-us/` (shown as `docs:` below).
- **WoT claims:** the session's WebSearch budget was exhausted (200 of 200), and the egress proxy blocks WoT, Wargaming, wiki, news and search domains. GitHub raw files were reachable. WoT items were therefore checked against GitHub where possible, and otherwise against the fact-checked sibling docs 01, 02, 03, 05 and 06.

**Result: 15 claims checked. 8 Confirmed, 6 Corrected, 1 Unverified.**

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | DataStore server budget **60 + numPlayers × 40/min** for Get/Set/Update; experience-wide Read 300 + CCU × 40, Write 300 + CCU × 20, List 300 + CCU × 2; `UpdateAsync` uses read and write budget | **Confirmed** (clarified: server values are configurable defaults with a startup burst, and the experience-wide Write limit binds first in aggregate; REG-DATA-07 and R-DATA-1 now check it) | `docs: cloud-services/data-stores/error-codes-and-limits.md` (Access limits: Experience limits, Server limits) |
| 2 | Throttle queues hold **30** requests, then drop with errors **301–306**; value ≤ **4,194,304** chars; name/key/scope ≤ **50**; metadata ≤ **300**; strings must be UTF-8 | **Confirmed** ("≤ 1 write per 6 s per key" in REG-DATA-07 is not in the current docs; relabelled OUR DESIGN CHOICE) | `docs: cloud-services/data-stores/error-codes-and-limits.md` (Limits, Data limits, Metadata limits, Throughput limits); `reference/engine/classes/GlobalDataStore.yaml` (UpdateAsync, UTF-8) |
| 3 | `GetAsync` caches for **4 s**, bypassed with `UseCache = false`; a failed write may still have committed; the `UpdateAsync` transform may rerun, cannot yield, and cancels on `nil` | **Confirmed** | `docs: cloud-services/data-stores/versioning-listing-and-caching.md` (Caching); `error-codes-and-limits.md` (top note); `reference/engine/classes/GlobalDataStore.yaml` (UpdateAsync) |
| 4 | The Roblox session-lock sample autosaves every 180 s **and offsets each player's first save randomly** | **Corrected**: the sample's loop is shared and **not** offset; the doc *recommends* adding the offset. The autosave interval must be shorter than the lock expiry (confirmed) | `docs: cloud-services/data-stores/player-data-purchasing.md` (Save player data, `AUTO_SAVE_INTERVAL = 180`); `best-practices.md` |
| 5 | `BindToClose`: bound functions run in parallel; the server waits **30 s**, then shuts down | **Confirmed** | `docs: reference/engine/classes/DataModel.yaml` (BindToClose); `player-data-purchasing.md` |
| 6 | `ProcessReceipt`: no time-based retry, no timeout, may run on two servers at once, non-deterministic order, user must be on the server, auto-acknowledged if unset; `UserOwnsGamePassAsync` is cached and updated on `PromptGamePassPurchaseFinished` | **Confirmed** | `docs: reference/engine/classes/MarketplaceService.yaml` (ProcessReceipt; UserOwnsGamePassAsync caching) |
| 7 | Remotes: ~**500 req/s per client**, shared per remote type; excess reliable events are processed later; excess unreliable events are dropped; unreliable payloads over **1,000 bytes** are dropped; messages with no handler are queued | **Corrected** (nuance): queuing with no handler applies to `RemoteEvent` only, and `UnreliableRemoteEvent` discards immediately. All numbers confirmed | `docs: reference/engine/classes/RemoteEvent.yaml`, `UnreliableRemoteEvent.yaml` (Throttling); `scripting/events/remote.md` (Delivery guarantees) |
| 8 | NaN and inf "pass `typeof == "number"` **and every comparison**"; validate with `math.isfinite` | **Corrected**: only NaN fails every comparison, while inf is a valid number that a correct bound check catches. `math.isfinite` exists in the Roblox `math` library. Its presence in Lune 0.10.4 is unverified, so a fallback was added | `docs: scripting/security/client-server-boundary.md` (Value validation, The danger of NaN); `reference/engine/libraries/math.yaml` |
| 9 | `TeleportAsync` is server-only with ≤ **50** players per call; the `SafeTeleport` sample "retries 5× at 1 s" and waits 15 s on `Flooded`; the `TeleportResult` values | **Corrected**: the sample makes **5 attempts** (the first call + 4 retries), 1 s apart; its handler retries `Failure` after 1 s and raises an error for every other result. REG-TP-01's 33-player split case was replaced by 51 → 2 calls. The 50 limit, server-only rule and enum list are confirmed | `docs: projects/teleport.md` (Handle failed teleports, `ATTEMPT_LIMIT = 5`); `reference/engine/classes/TeleportService.yaml` (Server-Only, Group Teleport Limitations); `reference/engine/enums/TeleportResult.yaml` |
| 10 | `Workspace.PlayerCharacterDestroyBehavior` = Enabled makes the engine destroy Player and character on leave, and can be "asserted at boot" | **Corrected**: the property exists (enum Default/Disabled/Enabled) but is tagged **NotScriptable**, so set it in the place file and lint it in CI. The scriptable fallback is `task.defer(player.Destroy, player)`. `Workspace.SignalBehavior` and the Streaming* properties are also NotScriptable | `docs: reference/engine/classes/Workspace.yaml` (PlayerCharacterDestroyBehavior, SignalBehavior tags); `reference/engine/enums/PlayerCharacterDestroyBehavior.yaml`; `performance-optimization/improve.md` |
| 11 | MemoryStore: 64 KB + 1.2 KB × users; 1,000 + 120 × CCU units/min; ~30,000 units/min per partition; ~5,000 write / 15,000 read per hash-map key; 32 KB values; 45-day default expiration; 30 s queue invisibility. MessagingService: 1 kB, 600 + 240 × players sent, (40 + 80 × servers) per topic, 20 + 8 × players subscriptions, best effort | **Confirmed** (added: 100,000 units/min per data structure; (400 + 200 × servers)/min game-wide receive; 240 subscribe requests/min; partition figures are estimates) | `docs: cloud-services/memory-stores/index.md`; `cloud-services/memory-stores/queue.md`; `reference/engine/classes/MemoryStoreQueue.yaml`; `reference/engine/classes/MessagingService.yaml` |
| 12 | Open Cloud Luau Execution: `POST /cloud/v2/universes/{universe_id}/places/{place_id}/versions/{version_id}/luau-execution-session-tasks`; timeout defaults to **5 minutes**; runs with `IsServer = true`, `IsRunning = false` | **Confirmed**. The recommendations that routed *all* E-tests through it (Summary 18, R-QA-2) contradicted these limits and were corrected | `refs/creator-docs/content/en-us/reference/cloud/openapi.json` (paths; `LuauExecutionSessionTask.timeout`, `enableBinaryOutput`); `docs: reference/engine/classes/RunService.yaml` (context table, "Luau Execution" row) |
| 13 | Streaming and signals: `.` indexing of non-streamed instances throws and `FindFirstChild` returns nil; `StreamingTargetRadius` default 1,024; `PauseOutsideLoadedArea` and `Opportunistic` recommended; `ReplicationFocus` defaults to the character's `PrimaryPart`; deferred re-entrancy limit **10**; `PlayerAdded` misses pre-existing players; `CharacterAdded` fires before parenting | **Confirmed** | `docs: workspace/streaming/index.md`; `workspace/streaming/techniques.md`; `reference/engine/classes/Player.yaml` (ReplicationFocus, CharacterAdded); `scripting/events/deferred.md`; `reference/engine/classes/Players.yaml` (PlayerAdded) |
| 14 | WoT penetration-indicator thresholds used in REG-RET-03: "red if pen < 0.75·T_eff, yellow within ±25%" | **Corrected** to green ≤ 87.5%, yellow 87.5–112.5% (±12.5%), red ≥ 112.5% of pen or a predicted ricochet. The old rule had already been superseded in the fact-checked doc 06 | [06-ui-ux-audio.md §13](06-ui-ux-audio.md) (fact-checked against the 2.4 client logic) |
| 15 | WoT [S] values: draw range **564 m since 9.12**; **1.26** consumable cooldowns 90 → 60 s (large kits and auto-extinguisher); templates from **9.18**; release dates 9.14 (10 Mar 2016), 1.10 (4 Aug 2020), 2.0 (3 Sep 2025), 2.4 (Sep 2026) | **Unverified** in this pass (no web access). Partial: the 9.18 release is confirmed by the XVM changelog (MMK-02 upgraded to Medium); the doc 02 fact-check reports the current manual says 565 m (noted in §3.1 and §3.6); the 1.26 cooldowns were downgraded to Medium (§3.16); the dates match docs 03 and 06 (2.0 corroborated there by IGN and a client-mirror date; the 2.4 date is Medium in doc 06) | [XVM ChangeLog-en.md](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md) ("World of Tanks 9.18 worldwide release"; "1.4.0.1 micropatch 2019.03.06"); [02-spotting-camouflage.md](02-spotting-camouflage.md) §1 and log row 4; [05-progression-economy-crew-equipment.md](05-progression-economy-crew-equipment.md) Summary 10; [03-vehicles-classes-roles-mechanics.md](03-vehicles-classes-roles-mechanics.md) §1.2 and log row 13; [06-ui-ux-audio.md](06-ui-ux-audio.md) Summary 7 and 10 |

**Internal-consistency fixes** (findings vs. Implementation recommendations, and cross-doc references):
- **Summary 18, R-QA-2 and the automation legend** sent all E-tests through Luau Execution. They are now limited to static scans: REG-MAP-01, REG-MAP-06, REG-LDR-01 and REG-SEC-02. R-QA-4 lists the tests that need clients, rendering or a long soak.
- **R-SEC-3** had a 60 s hub teleport deadline, longer than the 45 s battle-server arrival window in REG-TP-03 and REG-MMK-06. It is now 40 s, and the no-retry list now matches the doc sample.
- **R-SEC-2 and REG-MEM-02** asserted a NotScriptable property at runtime. Both now use a place-file lint plus a scriptable fallback.
- **REG-LDR-06** ("5 attempts" with 5 delays) disagreed with R-DATA-1. Both now use 1 attempt + 5 retries over 31 s.
- **R-DATA-1** now adds the per-player random first-save offset and checks the experience-wide Write limit.
- **REG-UIX-01 and Open question 10** used 44×44 px, against doc 06's 48×48 px. Now 48×48 px.
- **References fixed:**
  - REG-ARM-04: doc 01 **R2** (not R7); the −25% post-ricochet penalty is OUR DESIGN CHOICE;
  - REG-ARM-05 and REG-ARM-13: doc 01 **§4/R4** (doc 01 has no §11);
  - Open question 6: doc 02 now rates the 10 s linger High.
- **Counts re-derived** from the tables: 183 WoT entries (14 sourced / 6 recalled / 163 pattern) and 204 tests (180 H, 8 H+E, 13 E or E/M, 3 M). All match the Summary.
