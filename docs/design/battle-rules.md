# Battle rules and ledger

> Package `battlerules`. Pure Shared modules under `src/ReplicatedStorage/Shared/Battle/Rules/` and
> `src/ReplicatedStorage/Shared/Battle/Ledger/`, tuned by `Config/Battle.luau`. Values come from
> `docs/research/00-DECISIONS.md` §9 (battle rules and lifecycle), §5 (spotting assist), §2 (friendly fire, fire
> credit, drowning), §7.2 (Role Score inputs), §19 (stale access codes) and §21 #22. Every item marked **O** is our own
> design choice; the reason is given next to it.

## 1. Purpose

These modules decide **how a battle runs and what it records**:

- the lifecycle, from server boot to close;
- what players may do in each phase;
- base capture;
- who wins;
- who drives each vehicle (player or bot);
- the ledger, which turns the event stream into `BattleStats` and a `BattleResult` (`Types/Battle`).

Rewards and medals are filled in later by `Battle/Scoring` and `Battle/Medals` (economy team). Nothing here touches
Roblox services, the scheduler or the wall clock. Time is always passed in as an argument, so the modules run unchanged
in Lune. The server's `BattleInstance` owns one state record per module and drives them in the tick order of §8.

| Module | Role |
|---|---|
| `Rules/ModeRules` | One frozen rule snapshot per battle (mode + battle type + live config) |
| `Rules/Phases` | Lifecycle state machine, arrival and admission, stale-access-code check, allowed actions, timer |
| `Rules/Capture` | Capture zones: per-vehicle points, max contributors, resets, grace, freeze, defense points |
| `Rules/Outcome` | Victory / defeat / draw evaluation, including same-tick edge cases |
| `Rules/Connection` | Connection states, bot takeover, reconnect, AFK, leaving, strike ladder |
| `Ledger/Attribution` | Live assist attribution (spotters, trackers, stunners) for each `DamageEvent` |
| `Ledger/KillCredit` | One rule for who gets a kill |
| `Ledger/Ledger` | Event-stream accumulation into `BattleStats`, the kill feed, interactions and the `BattleResult` |

## 2. Rule snapshot (`Rules/ModeRules`)

```lua
ModeRules.resolve(mode: string, battleType: string?, options: { durationS: number? }?) -> Result<ModeSettings>
ModeRules.defaults(mode, battleType?, options?) -> ModeSettings      -- raises on invalid input
ModeRules.with(settings, patch) -> ModeSettings                      -- frozen copy, merges `capture`
ModeRules.MODES / ModeRules.BATTLE_TYPES
```

How each value is chosen, highest priority first:

1. `options.durationS` (`EventModeDefinition.durationS`), which applies to the duration only;
2. `Config.Battle.MODES[mode].KEY`;
3. `TIMER_S[battleType]`, which applies to the duration only;
4. the top-level `Config.Battle.KEY`.

Mode flags default to `true`.

The result is deep-frozen. It is resolved **once per battle**, so a live override never changes a running battle
(00-DECISIONS §19 "Live config"). Cross-key rules are enforced here: the AFK warning time is at most the takeover time,
capture points are at least 1, and non-finite config values fall back to safe defaults.

| Mode | Countdown | Load timeout | Duration | Objectives | AFK |
|---|---|---|---|---|---|
| Random Standard / Encounter | 20 s | 30 s | 720 s | wipe + capture | on |
| Random Assault | 20 s | 30 s | 480 s | wipe + capture, defender wins on timeout | on |
| Training (**O**: friends load slower; no strikes in private rooms) | 20 s | 45 s | battle type | wipe + capture | off |
| Bootcamp (**O**: tutorial pacing; newcomers are never struck) | 10 s | 30 s | 600 s | wipe + capture | off |
| Practice (**O**: shooting range / map explorer) | 3 s | 30 s | 1800 s | none (timeout only) | off |
| Event | 20 s | 30 s | `EventModeDefinition.durationS` or battle type | wipe + capture | on |

## 3. Lifecycle (`Rules/Phases`)

```
Preparing ──markReady──▶ Loading ──all loaded / LOAD_TIMEOUT──▶ Countdown ──COUNTDOWN──▶ Active ──finish──▶ Ending
    │ PREPARE_TIMEOUT        │ fewer than MIN_HUMANS arrived                                          │ END_BANNER_S
    └────────abort───────────┴──────────────────────────abort─────────────────────────────▶ Ending ──▶ Results
                                                                         delivered / RESULTS_TIMEOUT ──▶ Closed
```

**Timers.**

- `now` is the server clock. Battle time is `t = now − goAt`, where 0 is GO. Every `BattleEvent.t` uses this base.
- Transition times are exact; they are not the tick that happened to notice them:
  - `countdownAt` is `max(readyAt, last human resolved)` on an early start, or `readyAt + LOAD_TIMEOUT_S` on a
    timeout;
  - `goAt = countdownAt + COUNTDOWN_S`;
  - `endsAt = goAt + durationS`.
- As a result, the timeline is identical at any step cadence (tested at 1/30 s, 0.37 s and 5 s).
- Clients show `endsAt − estimated server now` (REG-BTL-03). `endsAt` never moves once set.

**Arrivals.**

- The arrival window (`ARRIVAL_WINDOW_S` = 45 s) counts from **server creation**. A reserved server starts when its
  first player arrives, which is after the Hub began teleporting. So the Hub's 40 s teleport deadline always expires
  first, as ARCHITECTURE §2.1 requires.
- `admit(state, userId, now, fromHub)` checks, in order:
  1. the battle is not over (`BATTLE_OVER`);
  2. the user is on the roster (`NOT_IN_ROSTER`);
  3. the user arrived from a Hub `SourcePlaceId` (`FOREIGN_SOURCE`);
  4. for a first arrival, the arrival window is still open (`ARRIVAL_WINDOW_CLOSED`).
- Every rejection is `NOT_ALLOWED` with the detail in parentheses.
- A user who arrived before may come back at any time until the battle ends ("Return to battle", REG-BTL-04).
- Humans still missing after the window are reported in `out.expired`. Their slot stays a bot, and the Hub re-queues
  them (REG-TP-03, REG-MMK-06).

**Early start.** The countdown starts as soon as every roster human has either loaded, left the server, or expired.

**Abort reasons.**

| Reason | When |
|---|---|
| `TooFewHumans` | At the gate, fewer than `MIN_HUMANS` humans have arrived (default 1; set it to 0 for bot-only test battles) |
| `PrepareTimeout` | Preparing lasted longer than `PREPARE_TIMEOUT_S` (90 s) |
| `StaleAccessCode` | The caller passes it after `checkAccess` fails |
| `ServerClosing` | `BindToClose` |
| `Internal` | Any other server failure |

An abort jumps to Ending with `Outcome.aborted`: reason `"Aborted"`, every team `Draw`, and no win or loss recorded.

**Stale-access-code hook.** `checkAccess(info) -> Result` runs at battle-server boot. It fails in these cases:

| Condition | Code | Detail |
|---|---|---|
| `PrivateServerId` is empty | `NOT_ALLOWED` | `NO_PRIVATE_SERVER` |
| `PrivateServerOwnerId ≠ 0` | `NOT_ALLOWED` | `PLAYER_OWNED_SERVER` |
| The manifest is missing | `NOT_FOUND` | `MANIFEST_MISSING` |
| The manifest is tombstoned | `NOT_ALLOWED` | `MANIFEST_ENDED` |
| `MatchmakingType ≠ manifest.mmType` | `NOT_ALLOWED` | `MATCHMAKING_TYPE_MISMATCH` |

On failure the caller sends everyone back to the Hub and calls `abort(state, "StaleAccessCode", now)`. The Dev role
skips the check.

**Allowed actions** (`allows(state, action)`, REG-BTL-06):

| Phase | Move | Fire | Turret | Consumable | Chat |
|---|---|---|---|---|---|
| Preparing, Loading, Ending, Results | — | — | — | — | ✓ |
| Countdown | — | — | ✓ | — | ✓ |
| Active | ✓ | ✓ | ✓ | ✓ | ✓ |
| Closed | — | — | — | — | — |

**API.**

```lua
Phases.new(settings, roster: {{participantId, team, userId?}}, now) -> PhaseState
Phases.newOutput() -> PhaseOutput            Phases.clearOutput(out)
Phases.checkAccess(info: AccessInfo) -> Result<boolean>
Phases.admit(state, userId, now, fromHub: boolean) -> Result<EntityId>
Phases.markReady(state, now, out?) -> boolean       Phases.markLoaded(state, userId, now) -> boolean
Phases.markGone(state, userId, now) -> boolean
Phases.step(state, now, out?) -> Phase              -- may cross several phases; emits "Started" at GO
Phases.finish(state, outcome, now, out?) -> boolean -- Active only, first outcome wins, end clamped to endsAt; "Ended"
Phases.abort(state, reason, now, out?) -> boolean   Phases.markResultsDelivered(state, now, out?) -> boolean
Phases.battleTime(state, now) / timeLeft(state, now) / isTimeUp(state, now) / isOver(state) / allows(state, action)
Phases.arrivedCount(state) / human(state, userId)
```

Active never ends on its own. Each tick the caller evaluates `Outcome`, passing `timeUp = isTimeUp(now)`, and then
calls `finish`.

## 4. Base capture (`Rules/Capture`)

Every capper inside the circle accrues its own points each tick:

```
points_v += RATE[type] · rateMul_v · dt · min(1, MAX_COUNTED / n)        n = eligible cappers of that team inside
progress  = Σ points_v   (capped at POINTS; the last increment is scaled so Σ = POINTS exactly)
```

**Capture times.**

- **Standard and Assault** (rate 1.0 pt/s): 100 s alone, 50 s with two, 33.3 s with three. More than three cappers
  still earn points, but the team rate stays capped.
- **Encounter** (0.5 pt/s): 200 s alone, 66.7 s with three.

**Who may capture.**

| Battle type | Base owner | Capturing teams |
|---|---|---|
| Standard | The team in `CaptureBase.team` | The other team |
| Encounter | Neutral (`team` is nil) | Every team |
| Assault | The defending team in `CaptureBase.team` | The attackers only |

- Bases whose `battleType` differs from the battle's are dropped.
- With `CAPTURE = false` (Practice), the state is inert.

**Inside.**

- A vehicle is inside when its planar (x, z) distance is at most the radius. Height never matters.
- Positions are in studs (sim space). Base centres and radii are in metres in map content and are converted once
  (REG-MAP-04: a vehicle at r − 0.1 m counts, one at r + 0.1 m does not).
- Dead vehicles and vehicles with `canCapture = false` (overturned) never count as inside. An alive enemy does contest
  the base.

**Freeze.** `CONTESTED_FREEZES[type]` is true for Encounter only. While it applies, any alive vehicle of another team
inside freezes the base. Points are kept but nothing accrues. Standard defenders inside do **not** stop a capture
(parity).

**Resets** (REG-BTL-01):

- When an **enemy** damages a capper, that capper's points go to 0 and the team's progress drops by the same amount.
  The capper keeps capping from 0.
- Which damage resets is set by config:
  - HP damage resets (`RESET_ON_HP_DAMAGE`);
  - a module crit or crew injury without HP damage also resets (`RESET_ON_MODULE_CRIT`, **O**: tracking a capper
    resets it);
  - stun does not reset (`RESET_ON_STUN = false`, **O**).
- Allies, self-damage and the environment never reset (**O**: friendly fire is off, and a fall is not a defense).
- The attacker earns the removed points as **defense points**, and a `CaptureReset{base, by, capper, points}` event is
  emitted.
- `resetVehicle` clears a vehicle's points without credit. It is used for overturning (00-DECISIONS §2) and for
  destruction by the environment.

**Leaving.** A capper outside the circle keeps its points for `LEAVE_GRACE_S` (1 s, **O**, absorbs boundary jitter),
then loses them without defense credit.

**Completion.**

- At `POINTS` (100) the base is captured, a `BaseCaptured` event is emitted, and the capping vehicles' points are
  **banked**.
- `step` returns every team that completed on that step, so a double capture reaches `Outcome` together.

**Events.**

- `CaptureProgress` is emitted when progress crosses a multiple of `PROGRESS_EVENT_STEP` (5), on every drop, and at
  completion.
- The HUD reads `snapshot()` rather than the events.

**Capture points per vehicle.** `participantPoints()` returns banked points plus points still held at the time of the
call; call it at the end. These are **net** points: points taken back by defenders or forfeited by leaving do not count.
That matches "capture points contributed" and the decision "capture XP only while advancing" (frozen bases never accrue).

**Invariants.** Progress always stays in [0, 100] and equals Σ capper points (property test). Vehicles are visited in
ascending id order, so the floating-point sums never depend on the caller's ordering.

```lua
Capture.new(settings, bases: {BaseSpec}, roster: {{participantId, team}}) -> CaptureState
Capture.step(state, vehicles: {CaptureVehicle}, dt, t, events?) -> {TeamId}   -- reused array
Capture.onDamage(state, target, attacker?, kind: "Hp"|"Crit"|"Stun", t, events?) -> number
Capture.applyDamageEvent(state, damage: DamageEvent, events?) -> number
Capture.resetVehicle(state, id, t, events?) -> number
Capture.isInside(base, position) / progress(state, baseId, team) / capperPoints(state, baseId, id)
Capture.isFrozen(state, baseId, team) / defenderTeam(state) / participantPoints(state) / defensePoints(state)
Capture.snapshot(state, out?) -> {BaseSnapshot}
```

## 5. Outcome (`Rules/Outcome`)

`Outcome.evaluate(input) -> BattleOutcome?` is called once per tick, after **every** damage event of the tick and after
`Capture.step` (REG-BTL-02, REG-BTL-07). The input is `{settings, teams, rosterByTeam, aliveByTeam, captured?, timeUp,
defender?}`. The rules apply in priority order:

1. **Wipe** (`wipeVictory`).
   - A team with a non-empty roster and 0 vehicles alive is wiped.
   - If every non-empty team is wiped on the same tick, the result is a draw `Simultaneous`. If there is only one
     non-empty team, it is a draw `Destruction`.
   - An empty team is never "wiped". This covers solo Practice and an empty bot team.
2. **Claims.**
   - When every other team is wiped, the surviving team claims `Destruction`.
   - Each team in `captured` claims `Capture`.
   - Two different claimants make a draw `Simultaneous`. This covers a double capture, and a team capturing while being
     wiped.
   - A single claimant wins. If it claimed both, the reason is `SAME_TICK_WIPE_AND_CAPTURE_REASON` (**O**: `Capture`,
     so the cappers keep their Invader and capture credit).
3. **Time up.**
   - When `TIMEOUT_RESULT[type]` is `DefenderWin` and a defender exists, the defender wins with `DefenderHeld`
     (Assault).
   - Otherwise the result is a draw `Timeout`.
   - A wipe or capture on the final tick beats the timeout.

| Same-tick case | Result |
|---|---|
| Last vehicles of both teams destroyed (mutual kill, any id or event order) | Draw `Simultaneous`; both kills credited |
| Both bases captured | Draw `Simultaneous` |
| Team A captures and team A wipes B | A wins, `Capture` |
| Team A captures and team B wipes A | Draw `Simultaneous` |
| Capture or wipe on the timeout tick | The capture or wipe result |
| Double wipe on the Assault timeout tick | Draw `Simultaneous` |

Helpers: `make(winner?, reason, teams)`, `draw`, `aborted`, `timeout(settings, teams, defender?)`, `resultFor`, `isWin`.
`BattleOutcome.teams` is always listed in ascending team order.

## 6. Connection, bots and AFK (`Rules/Connection`)

| Situation | Effect | `ControlChanged` |
|---|---|---|
| Human not connected at GO | A bot drives from t = 0 | `Bot / Disconnect` at t = 0 |
| First arrival after GO (inside the window) | The player takes over | `Player / Arrived` |
| Never arrives inside the window (`expire`) | The slot stays a bot; Hub re-queues | — |
| Disconnected for `DISCONNECT_BOT_DELAY_S` (5 s) | A bot drives | `Bot / Disconnect` |
| Reconnects before the end | Control comes back at once (spectator if destroyed) | `Player / Reconnect` |
| No meaningful input for `AFK_WARN_S` (60 s) | Warning notice | — |
| No meaningful input for `AFK_TAKEOVER_S` (90 s) | A bot drives, plus an AFK strike (XP 0) | `Bot / Afk` |
| Input after an AFK takeover | Control comes back; the strike stays | `Player / Reconnect` |
| Leaves while alive (confirmed) | A bot drives at once; no win bonus; strike | `Bot / Left` |
| Leaves during the countdown | Same, at GO | `Bot / Left` at t = 0 |

- **Input, not movement.** Only meaningful **input** counts as activity: throttle or steer ≠ 0, a turret or aim
  change, fire, or a consumable. A stuck or overturned player who keeps pressing keys is therefore never flagged
  (REG-BTL-05).
- **After death.** Destroyed vehicles never change controller.
- **Modes.** `BOT_TAKEOVER = false` restores WoT's idle tank and also disables AFK takeover. `AFK = false` modes never
  warn or strike.
- **Strike ladder.** `strikePenalty(strikesIn24h)` is applied by the Hub (00-DECISIONS §9): 1 strike means no rewards,
  2 strikes add a 10 min queue lock, 3 or more add a 60 min lock (`AFK_STRIKE_LOCK_S`).

```lua
Connection.new(settings, roster: {{participantId, userId?}}, now) -> ConnectionState
Connection.start(state, goAt, events?, notices?)          Connection.step(state, now, events?, notices?)
Connection.arrive / disconnect / leave / activity (state, participantId, now, events?, notices?) -> boolean
Connection.destroyed(state, id) / expire(state, id) / finish(state)
Connection.controller(state, id) / isBotControlled(state, id) / get(state, id)
Connection.strikePenalty(strikes) -> { noRewards: boolean, queueLockS: number }
```

## 7. Ledger

### 7.1 Attribution (`Ledger/Attribution`)

The producer feeds it the information the event stream cannot carry continuously. Before emitting each `DamageEvent`,
it calls `fill(state, damage)`, which writes `assistSpotters`, `assistTrackers` and `assistStunners`. The lists are
written in place, sorted ascending and deduplicated.

The same rules apply to all three lists:

- only allies of the attacker are listed, never the attacker itself;
- damage from an ally or from the environment gets empty lists.

| Assist | Who is listed |
|---|---|
| Spotting | Every ally whose **own** spotting check saw the target at most `ASSIST_SPOT_WINDOW_S` (10 s = the spotting linger, 00-DECISIONS §5) ago. Spotters destroyed meanwhile still count until their window lapses (REG-SPT-07, **O**). |
| Tracking | The latest attacker that destroyed each still-destroyed track side (`TrackLeft`/`TrackRight`). Wheeled targets only count with `WHEELED_TRACK_ASSIST` (**O**, default off: a wheeled vehicle is slowed, not stopped). Repairs clear the side. |
| Stun | Every ally whose stun on the target is still running. `clearStun` handles a Medkit. A re-stun can extend a stun but never shorten it. |

```lua
Attribution.new(roster: {{participantId, team, wheeled?}}, settings?) -> AttributionState
Attribution.noteSeen(state, observer, target, t)        -- on EVERY successful per-observer spotting check
Attribution.noteModuleState(state, target, module, moduleState, attacker?)
Attribution.noteStun(state, target, stunner, t, durationS)   Attribution.clearStun(state, target)
Attribution.noteDestroyed(state, target)                Attribution.observe(state, event)  -- Spotted/ModuleState/Stunned/Destroyed
Attribution.fill(state, damage) -> DamageEvent          Attribution.isTracked(state, target)
```

### 7.2 Kill credit (`Ledger/KillCredit`)

| Cause | Credited to |
|---|---|
| Shell, Splash, Ram, AmmoRack | The attacker. For an ammo-rack detonation, that is the shooter whose hit caused it. |
| Fire | The attacker of the fire damage, which is the igniter (00-DECISIONS §2) |
| Fall | The attacker when there is one (landing on a vehicle). Otherwise the last enemy that dealt HP damage within `FALL_CREDIT_WINDOW_S` (5 s, **O**: ramming someone off a cliff is a kill). |
| Drown | Nobody (00-DECISIONS §2) |

The attacker must be a known participant of the other team. A dead attacker keeps the credit, which covers shells in
flight and mutual kills. `KillCredit.resolve` is the single rule: the Ledger uses it, and `BattleInstance` uses it
through `Ledger.deathRecord` when it fills the `Destroyed` event, so the two always agree.

### 7.3 Counting rules (`Ledger/Ledger`)

Feed every `BattleEvent` in stream order with `apply`, then call `finalize` once at the end. "Enemy" means a
participant of the other team.

| `BattleStats` field | Source |
|---|---|
| `damageDealt` / `damageReceived` | HP removed. Damage received also includes the environment (falls, drowning, self). |
| `damageBlocked` | Σ max(0, potential − damage) of enemy **Shell** hits whose result is NonPenetration, Ricochet or Absorbed. Kinetic non-pens deal 0, so their full potential counts (REG-RES-08). For HE/HESH non-pens that deal partial damage, only the part the armor stopped counts (**O**). |
| `potentialDamageReceived` | Σ potential of enemy Shell and Splash events |
| `hits`, `penetrations` (+ received) | Enemy Shell events (any result); Penetration results |
| `ricochetsReceived` / `nonPensReceived` | Ricochet / NonPenetration + Absorbed |
| `criticalHits` | Enemy Shell or Splash events with a module hit dealing damage > 0, or a crew injury |
| `assistSpotting/Tracking/Stun` | `+damage` for every validated listed ally. Each gets the full amount, for display (report 02 R8). Scoring splits the 50 % reward pool. |
| `kills`, `killedBy`, `deathCause`, `firstBlood` | KillCredit on the first death signal (`Damage.killed` or `Destroyed`). `firstBlood` goes to the first credited kill in stream order. |
| `spotted` | `Spotted` events with `first = true`, counted once per (team, target) |
| `shotsFired`, `stuns`, `firesStarted` | `Shot`, `Stunned` and `Fire(burning = true)` events with an enemy attacker |
| `defensePoints` | `CaptureReset.points` credited to `by` |
| `capturePoints` | `finalize({ capturePoints = Capture.participantPoints(capture) })`. There is no per-vehicle capture event. |
| `ramDamageDealt` | Ram damage dealt |
| `distanceM` | `Ledger.addDistance(ledger, id, meters)`, sim-side |
| `timeAliveS`, `survived` | The death time, otherwise the end time |
| `firstContactDamage` | Damage dealt with t ≤ `FIRST_CONTACT_WINDOW_S` (180 s, Role Score) |
| `soleSpotterDamaged` | Distinct targets damaged by allies while this vehicle was the **only** listed spotter (Patrol Duty) |
| `hitsOnLaterKilled` | Distinct targets this vehicle damaged that someone else got credit for destroying (Confederate) |
| `byTargetClass` | `damageDealt`, `kills`, `spotted` and `assist` (spotting + tracking + stun), split by enemy class |
| `roleScore`, `teamXpRank` | `nil`; Scoring fills them |

**Control share.**

- Humans start as `Player` at t = 0, and `ControlChanged` events move them between `Player` and `Bot`.
- `controlShare = human-controlled seconds / seconds alive`, clamped to [0, 1]. Bots have 0. A human that dies at t = 0
  gets 1 if they were in control at that moment, otherwise 0.
- `botShare` = Σ(bot ? 1 : 1 − controlShare) / participants. Leaderboards and `pvpOnly` achievements exclude battles
  above 0.5.
- `Ledger.flags(id)` exposes `afkStrike` (from `Afk`), `leftAlive` (from `Left`), `botTakeovers` and `returns`.

**Defensive filtering.**

- **Friendly fire is off.** `AllyBlocked` events with 0 damage are accepted silently. Any other damage between allies
  is ignored and counted under `anomalies().AllyDamage`.
- These events are also ignored and counted under `anomalies()`:
  - malformed events;
  - events naming unknown participants;
  - damage to a destroyed vehicle;
  - duplicate first spots;
  - unknown event types;
  - anything after `Ended`, so hits resolved on or before the end tick count and later ones do not (REG-BTL-07).
- Assist lists are re-validated. Only allies of the attacker count, never the attacker or the target, and duplicates
  are dropped.

**Result.**

- `finalize` produces a `BattleResult` with participants in ascending order, `medals = {}` and `rewards = nil`.
- The outcome comes from the `Ended` event, or from `options.outcome`, or else `Aborted`.
- `durationS` comes from the `Ended` t, or from `options.endT`, or else the last event t.
- `finalize` never mutates the ledger and never aliases the caller's participants, so it is repeatable.
- The same event stream always produces an equal result, whatever the roster order (property test, 40 seeds).

```lua
Ledger.new(spec: LedgerSpec) -> LedgerState
Ledger.apply(state, event) -> boolean          Ledger.applyAll(state, events) -> number
Ledger.addDistance(state, id, meters) -> boolean
Ledger.resolveKill(state, victim, cause, attacker?, t) -> (EntityId?, {EntityId})
Ledger.deathRecord(state, victim) -> KillFeedEntry?        Ledger.killFeed(state) -> {KillFeedEntry}
Ledger.stats(state, id) -> BattleStats?        Ledger.isAlive(state, id)
Ledger.aliveByTeam(state) / rosterByTeam(state) / teams(state)
Ledger.flags(state, id) -> ParticipantFlags?   Ledger.interactions(state, id) -> {Interaction}
Ledger.consumedAmmo(state, id) -> {{shell, count}}   Ledger.consumedConsumables(state, id) -> {ConsumableId}
Ledger.anomalies(state) -> {[string]: number}
Ledger.finalize(state, { endT?, outcome?, capturePoints? }?) -> BattleResult
```

The live view returned by `Ledger.stats` lacks the fields that only `finalize` fills: `capturePoints`,
`soleSpotterDamaged`, `hitsOnLaterKilled`, and `survived`/`timeAliveS` for vehicles still alive.

## 8. Data flow: the BattleInstance tick (ARCHITECTURE §6.1)

`tests/Unit/ReplicatedStorage/Shared/Battle/Rules/Scenario.spec.luau` runs exactly this recipe end to end.

```
boot:   Phases.checkAccess → (fail: abort StaleAccessCode) ; settings = ModeRules.resolve(mode, type, {durationS})
        phases/conn/capture/attribution/ledger = X.new(...)
join:   Phases.admit → Connection.arrive ; MapReady ack → Phases.markLoaded ; leave → markGone + Connection.disconnect/leave
tick:   Phases.step(now, out)          -- at Active entry: Connection.start(goAt, events); forward out.events / out.expired
        Connection.step(now, events)   -- inputs: Connection.activity for meaningful input only; Phases.allows gates input
        spotting checks → Attribution.noteSeen(observer, target, t)
        for each DamageEvent: Attribution.fill(d) → Capture.applyDamageEvent(d, events) → emit {type="Damage"}
          on death: Ledger.deathRecord → emit Destroyed{attacker = killer, assisters}; Attribution.noteDestroyed;
                    Connection.destroyed; Capture.resetVehicle when no enemy credit (drown / environment)
        ModuleState / Stunned → Attribution.observe ; Medkit → Attribution.clearStun ; overturn → Capture.resetVehicle
        completed = Capture.step(vehicles, dt, t, events)
        Ledger.apply(each event in order)
        outcome = Outcome.evaluate{aliveByTeam = Ledger.aliveByTeam, rosterByTeam, captured = completed,
                                   timeUp = Phases.isTimeUp(now), defender = Capture.defenderTeam}
        outcome → Phases.finish(outcome, now, out) ; Connection.finish ; Ledger.apply(Ended)
end:    result = Ledger.finalize{capturePoints = Capture.participantPoints(capture)} → Scoring → inbox
        → Phases.markResultsDelivered
```

## 9. Config keys (`Config/Battle.luau`)

Existing keys are kept. `DURATION_S` changed from 900 to 720 and `COUNTDOWN_S` from 30 to 20, to match the decisions.
All numeric keys below are live-overridable inside their `BOUNDS`.

| Key | Default | Source |
|---|---|---|
| `TICK_RATE`, `SNAPSHOT_RATE`, `TEAM_SIZE`, `INTERPOLATION_DELAY_S` | 30, 20, 15, 0.1 | ARCH §6 (unchanged) |
| `DURATION_S` / `TIMER_S.{Standard,Encounter,Assault}` | 720 / 720, 720, 480 | §9 Timers |
| `COUNTDOWN_S`, `LOAD_TIMEOUT_S`, `ARRIVAL_WINDOW_S` | 20, 30, 45 | §9 Load, §21 #22 |
| `END_BANNER_S`, `RESULTS_TIMEOUT_S`, `PREPARE_TIMEOUT_S` | 6, 60 (**O**), 90 (**O**) | §9 End |
| `MIN_HUMANS` | 1 | §8 Relaxation (≥ 1 human) |
| `MODES.<mode>.{COUNTDOWN_S, LOAD_TIMEOUT_S, DURATION_S, EARLY_START, WIPE_VICTORY, CAPTURE, BOT_TAKEOVER, AFK}` | see §2 | **O** |
| `CAPTURE.POINTS`, `RADIUS_M`, `MAX_COUNTED` | 100, 50 m, 3 | §9 Capture |
| `CAPTURE.RATE.{Standard,Encounter,Assault}` | 1.0, 0.5, 1.0 | §9 Capture |
| `CAPTURE.CONTESTED_FREEZES.*` | Encounter only | §9 Capture |
| `CAPTURE.RESET_ON_HP_DAMAGE` / `_MODULE_CRIT` / `_STUN` | true / true / false | §9 Capture |
| `CAPTURE.LEAVE_GRACE_S`, `PROGRESS_EVENT_STEP` | 1 s, 5 | §9 / **O** |
| `TIMEOUT_RESULT.*`, `SAME_TICK_WIPE_AND_CAPTURE_REASON` | Draw / Draw / DefenderWin, `Capture` | §9 Victory / **O** |
| `DISCONNECT_BOT_DELAY_S`, `AFK_WARN_S`, `AFK_TAKEOVER_S` | 5, 60, 90 | §9 Disconnect / AFK |
| `AFK_STRIKE_WINDOW_S`, `AFK_STRIKE_LOCK_S` | 86400, {0, 600, 3600} | §9 AFK |
| `LEDGER.ASSIST_SPOT_WINDOW_S`, `FIRST_CONTACT_WINDOW_S` | 10, 180 | §5, §7.2 |
| `LEDGER.FALL_CREDIT_WINDOW_S`, `WHEELED_TRACK_ASSIST` | 5 (**O**), false (**O**) | §2 |

The timeout watch from §9 applies unchanged: if more than 5 % of battles time out, override `TIMER_S.*` to 900 or
`CAPTURE.RATE.Standard` to 1.25. No code change is needed.

## 10. Tests (`tests/Unit/ReplicatedStorage/Shared/Battle/**`, 130 tests)

| Spec | Covers |
|---|---|
| ModeRules (12) | Decided values per mode/type; overrides; validation; frozen snapshot vs live overrides; BOUNDS |
| Phases (21) | Per-mode timelines; early start; load timeout; arrival window/expiry (REG-TP-03, REG-MMK-06); reconnect admission (REG-BTL-04); abort rules; stale codes; allowed actions (REG-BTL-06); timer invariants (REG-BTL-03); cadence independence |
| Capture (18) | REG-MAP-04 radius; 100/50/33.3/33.3 s; Encounter 200/66.7 s; freeze; defenders don't block; Assault; resets and defense points (REG-BTL-01); crit/stun/ally/env rules; grace; overturn; events; double capture; rateMul; determinism; property test ([0, 100], Σ points = progress) |
| Outcome (13) | Wipe; Simultaneous (REG-BTL-02, every ordering); capture; double capture; capture + wipe; timeouts; final-tick precedence (REG-BTL-07); Practice; empty teams; 3 teams |
| Connection (14) | GO absentees; late arrival; disconnect → bot → reconnect (REG-BTL-04); AFK warn/takeover/return; stuck-but-pressing never flagged (REG-BTL-05); leave; modes without AFK; BOT_TAKEOVER off; strike ladder |
| KillCredit (7) | Every cause; allies/self/env; fall window boundary; drowning |
| Attribution (14) | Spot window boundary and refresh; REG-SPT-07; tracker sides/repair/re-track; wheeled; stun expiry/clear/extend; array reuse; ally/env |
| Ledger (28) | Damage, blocked (REG-RES-08), crits, FF off, environment, first contact, assists, sole spotter, kills and the kill feed, fire, ammo rack, mutual ram, falls/drowning, REG-BTL-02 orderings, spotting, ammo, capture/defense, control share and flags (REG-RES-06), REG-BTL-07, header/sorting, purity, anomalies, 40-seed property test (conservation, determinism, roster-order independence) |
| Scenario (3) | The §8 recipe end to end: capture win with a reset, determinism, disconnect → bot share |

## 11. Known limitations and requests

The contract types belong to other teams, so each gap is worked around locally:

| Gap | Effect / workaround | Request |
|---|---|---|
| `Shot` has no target | `Interaction.shotsAt` = shells that reached the vehicle | Optional `target: EntityId?` on `Shot` (the locked or aimed target) |
| No per-vehicle capture event | `capturePoints` is passed to `finalize` from `Capture.participantPoints` | A `contributors` field on `CaptureProgress`/`BaseCaptured`, or a `CaptureContribution` event |
| `ControlChanged.reason` has no "Absent" or "AfkReturn" | Absent at GO is `Disconnect`; returning from AFK is `Reconnect` | — |
| No stun-cleared event | The producer calls `Attribution.clearStun` on a Medkit | — |
| `BattleParticipant` lacks the leave and AFK flags | Exposed through `Ledger.flags` | Scoring needs `leftAlive` (no win bonus); `RewardInboxEntry.afkStrike` exists |
| No specific error codes for admission | `NOT_ALLOWED`/`NOT_FOUND` + detail | Add `STALE_ACCESS_CODE`, `NOT_IN_ROSTER`, `ARRIVAL_WINDOW_CLOSED` to `ErrorCodes` |

Other limitations:

- **Respawn event modes** (`EventModeDefinition.respawns`) need alive counts that include respawns still pending. The
  caller can pass `alive + pending` to `Outcome`.
- **Spotting assist** relies on the spotting system calling `noteSeen` on every successful per-observer check. The
  `Spotted` event alone covers only the first detection.

## 12. Needs in-engine verification

1. A reserved server's start time relative to the first arrival. The arrival window counts from server creation.
2. Whether `game.MatchmakingType` (an Enum) compares equal to the manifest's `mmType` encoding. The check uses `==`, so
   both sides must use the same encoding (for example `Enum.Value`).
3. Telling a teleport-out (`Left`) apart from a disconnect on `PlayerRemoving`.
4. The server closes when its last human leaves. The `BindToClose` → `abort("ServerClosing")` path must write the inbox
   within 25 s.
5. Client timer drift against real clock skew (REG-BTL-03 client half).
6. The capture ring visual matches the 50 m radius.
