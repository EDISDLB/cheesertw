# 08 — Roblox Platform & Backend Research for HULLDOWN (networking, persistence, monetization, social, policy)

> **Date:** 2026-10-05.
> **Primary source:** the Roblox creator-docs snapshot at commit `9f840b1`, dated 2026-10-02.
> **Path convention:** `CD/<path>` means `creator-docs/content/en-us/<path>` in that snapshot. A guide `CD/x/y.md` is published at
> `https://create.roblox.com/docs/x/y`. An API page `CD/reference/engine/classes/Foo.yaml` is published at
> `https://create.roblox.com/docs/reference/engine/classes/Foo`.
> The Open Cloud figures (scopes, rate limits, size limits) come from the machine-readable spec at
> `CD/reference/cloud/openapi.json`.
> **Web evidence:** the session-wide WebSearch budget (200 calls) ran out before this report started. Help-center, Wikipedia and DevForum
> fetches are proxy-blocked. Every claim not backed by the local docs is marked **[prior knowledge, not re-verified]**,
> with Low or Medium confidence.
> **Fact-check (2026-10-05):** the 20 most implementation-critical claims were re-verified against the same local
> creator-docs snapshot (`9f840b17`, 2026-10-02) and the ProfileStore source on GitHub. Corrections are marked
> "(corrected by fact-check)". See the **Verification log** at the end.
> **Confidence scale:**
> - **High**: stated verbatim in the current docs or spec.
> - **Medium**: inferred from docs, or from well-established community practice.
> - **Low**: prior knowledge that could not be re-checked.
> **HULLDOWN context:** the authoritative contract is `docs/ARCHITECTURE.md`. Key points:
> - custom server-authoritative simulation at 30 Hz;
> - no vehicles as physics assemblies;
> - per-observer replication;
> - Hub plus Battle places;
> - a MemoryStore matchmaker;
> - ProfileStore-style profiles.
>
> This report confirms most of it and lists the required deltas in §R13.

---

## Summary

1. **Remotes.**
   - `RemoteEvent` is reliable and ordered across **all** RemoteEvent instances, per direction and per connection.
   - `UnreliableRemoteEvent` has no ordering and no delivery guarantee. It **drops payloads > 1,000 bytes** and drops
     client sends over the throttle.
   - Both types share a client→server limit of **~500 requests/s per client, per remote type**, across all instances.
   - `buffer` is a supported, engine-compressed argument type.
   - Our 900-byte cap on unreliable packets (ARCHITECTURE §5.2) is a sensible 10% margin. Keep it.
2. **Never use `InvokeClient`**:
   - a client that errors re-throws on the server;
   - a client that disconnects throws;
   - a client that never returns yields forever (documented).

   The server only *answers* `InvokeServer`.
3. **Hiding information.** Everything under `Workspace`/`ReplicatedStorage`/`ReplicatedFirst`, and children of `Player`,
   replicates to all clients. `PlayerGui` is the only built-in per-player replicated container (tag `PlayerReplicated`).
   `ServerStorage`/`ServerScriptService` never replicate. Our design is correct: enemy state only through per-observer
   `FireClient`, no vehicle Instances on the server, no secrets in `ReplicatedStorage/Shared`.
4. **Roblox's engine "Server Authority" model** (client prediction plus rollback via `BindToSimulation`, `AuthorityMode`) is
   **still beta** ("currently in beta and will be released soon").
   - It requires StreamingEnabled, NextGenerationReplication, the Input Action System, Deferred signals and fixed simulation.
   - It replicates all predicted state to everyone, which is incompatible with spotting secrecy.
   - **Stay with our custom simulation.**
5. **Spatial queries.**
   - `Raycast` max length is **15,000 studs**.
   - `Blockcast` max size is **512 studs**. `Spherecast` max radius is **256 studs**. The max cast distance is **1,024 studs**.
   - `Raycast`/`Blockcast`/`Spherecast` are **parallel-safe**; `Shapecast` is not.
   - `RaycastParams.ExcludeInstances`/`IncludeInstances` **supersede** `FilterDescendantsInstances`/`FilterType` (they can
     be mixed, and exclusion wins).
   - `RaycastResult.Material` returns the terrain material at the hit.
6. **StreamingEnabled.**
   - Defaults: `StreamingMinRadius` 64, `StreamingTargetRadius` 1,024.
   - Client-created instances never stream out unless parented under a server-created instance.
   - Streaming centres on the character or `Player.ReplicationFocus` (a server-set **Part**). For a character-less tank
     game, a focus Part in Workspace **would leak positions**.
   - New features: per-player **Frustum streaming** (good for sniper zoom) and **SLIM** distant LOD.
   - Recommendation: **StreamingEnabled = false in Battle places (v1)**, with a strict map budget (§R8).
7. **MemoryStore quotas** (per experience):
   - **memory = 64 KB + 1.2 KB × users** (tiny at low CCU: about 124 KB at 50 users);
   - **requests = 1,000 + 120 × CCU request units/min**.

   Other limits:
   - value ≤ **32 KB**; key and sort key ≤ **128 chars**;
   - max expiry **3,888,000 s (45 d)**;
   - ≤ **1 M items / 100 MB** per sorted map or queue;
   - ~**30,000 RU/min** per partition (a sorted map or queue = 1 partition);
   - hash-map key ~**5,000 write / 15,000 read** RU/min.

   **Keep the match manifest ≤ 8 KB.**
8. **MessagingService**:
   - message ≤ **1 kB**, delivered in about 1–2 s, **best effort**;
   - send **600 + 240 × players/min per server**;
   - receive **40 + 80 × servers/min per topic**;
   - **20 + 8 × players subscriptions per server**.

   Use it only as a latency hint; correctness must come from MemoryStore polling.
9. **TeleportService.**
   - `ReserveServer` is **deprecated**; use **`ReserveServerAsync(placeId)` → `(accessCode, PrivateServerId)`**.
   - Access codes stay valid **indefinitely**: re-using a code after the battle ended **starts a fresh empty server**, which
     must bounce players back.
   - `TeleportAsync` takes at most **50 players per call**. Server-only.
   - `TeleportAsyncResult` returns `PrivateServerId` + `ReservedServerAccessCode`.
   - Retry through `TeleportInitFailed`, which hands back ready-made `TeleportOptions`.
   - TeleportService does **not** work in Studio.
10. **Cross-play trap.** Console players with cross-play off get **separate server instances with the same
    `PrivateServerId`** (distinguish with `game.MatchmakingType`). The matchmaker must never mix `MatchmakingType`s.
11. **Teleport data is not trusted.**
    - `Player:GetJoinData()` guarantees only that the data was sent by a Roblox server in the last **48 h**, with this player,
      from a verifiable `SourcePlaceId`.
    - Docs say sensitive data must travel via MemoryStore.
    - The manifest keyed by `game.PrivateServerId` is the correct design.
12. **DataStore limits**:
    - value **4,194,304 chars**; name, key and scope **50 chars** each; metadata ≤ **300 chars** total;
    - per-key throughput **25 MB/min read**, **4 MB/min write**;
    - per-server defaults: **Read/Write 60 + 40 × players/min**, **List 5 + 2 × players**;
    - experience-wide: **Read 300 + 40 × CCU**, **Write 300 + 20 × CCU per minute**, shared with Open Cloud;
    - per-type request queue **30 deep** (errors 301–306);
    - `GetAsync` cache **4 s**;
    - old versions kept **30 days**;
    - `BindToClose` budget **30 s**;
    - storage **500 MB + 1 MB × lifetime users**.
13. **Session locking.**
    - Roblox's reference implementation writes a `LockId` into key **metadata** inside `UpdateAsync`.
    - ProfileStore (loleris) instead stores `MetaData.ActiveSession = {PlaceId, JobId, sessionId}` in the value. Its defaults:
      - auto-save 300 s;
      - steal after 40 s of conflict;
      - "assume dead" after 630 s;
      - a MessagingService fast-release ping.
    - Our 60 s jittered autosave is affordable.
14. **Purchases.**
    - New **`MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, fn, filter?)`** returns
      `Enum.ReceiptDecision.Processed / NotProcessedYet`. It takes precedence over the legacy `ProcessReceipt`.
    - Receipts can run **concurrently on two servers**; there is no timeout and no time-based retry. A receipt is
      redelivered on the next purchase or on rejoin.
    - Idempotency must come from `PurchaseId` + session lock + a successful save before returning `Processed`.
    - **Cross-game product and pass sales were disabled from 2026-05-30.**
15. **Monetization policy.**
    - **Managed Pricing** is the default for new items: regional prices are 30–100% of the base price, plus price-optimization tests.
    - Every displayed price must therefore be fetched dynamically with a client-side `GetProductInfoAsync`.
    - Subscriptions: Robux-priced at ≥ 49 R$, or fixed local-currency tiers from $2.99 to $14.99. No mutually exclusive tiers.
    - **Paid random items** need full odds and must honour `PolicyService.ArePaidRandomItemsRestricted`. **We should have none.**
16. **Audience gating changed in 2026.**
    - Account tiers: **Roblox Kids (5–8)**, **Roblox Select (9–15)** and **Roblox (16+)**.
    - Minimal/Mild-rated games can reach Kids and Select; Moderate reaches Select and 16+; Restricted is 18+ only.
    - Reaching under-16s requires:
      - a creator age check (government ID if 18+, facial age estimation if under 18) and 2FA;
      - a 1,000 R$ refundable fee **or** 2 months of Plus/Premium;
      - **250 unique plays by highly-engaged age-checked users within 60 days**.
    - HULLDOWN should target a **Mild** label: repeated, unrealistic, bloodless vehicle violence.
17. **Chat/social.**
    - Kids accounts have chat off by default, and self-declared Select accounts have chat off.
    - Roblox explicitly allows **gameplay-intent preset systems** ("Need help", "Defending") for all ages.
    - Build WoT-style quick commands and map pings as presets.
    - Use `TextChatService` team channels; Team-coloured `RBXTeam<Color>` channels are created automatically.
    - Filter any custom text with `TextService:FilterStringAsync`, which requires the author to be **on the current server**.
18. **Open Cloud for tooling.** Endpoints, scopes and limits:

    | Purpose | Endpoint / scope | Limits |
    |---|---|---|
    | Assets | `POST /assets/v1/assets` (`asset:read`/`asset:write`) | 120/min per key owner, 20 MB per file. Audio ≤ 7 min, ≤ 48 kHz. |
    | Place publish | `POST /universes/v1/{u}/places/{p}/versions` (`universe-places:write`) | 30/min. The spec's size limit is **10,485,760 bytes**. |
    | Data/memory stores | `cloud/v2` data-store and memory-store endpoints | — |
    | Messaging | `:publishMessage` | 5,000/min |
    | Server restart | `:restartServers` | 30/min |
    | Bans | user-restrictions | 150/s per API-key owner (30/s via OAuth2), **plus per-universe caps: update 10/s, get/list 50/s, and at most 2 updates/min for the same user** (corrected by fact-check) |

19. **Anti-cheat reality.** Current Roblox docs still assume a fully compromised client: exploiters can decompile any
    replicated script and fire any remote at any rate with any argument. Hyperion (Byfron) is a desktop-client anti-tamper
    layer **[prior knowledge]**. It does nothing for game-logic validation. Our server-authoritative design remains mandatory.
20. **Ops tools worth adopting:**
    - **Experience Configs** (`ConfigService`): live keys, strings/JSON up to 100,000 chars, published in about 15 s–1 min,
      snapshot semantics so values never change mid-battle;
    - the **Ban API** (`Players:BanAsync`);
    - **"Secure within universe only"** place access, so Battle places accept only server-initiated teleports;
    - **automated right-to-be-forgotten deletion templates** (`{UserId}` key patterns, up to 100 templates).

---

## Detailed findings

### F1. Remotes, replication and bandwidth

#### F1.1 `RemoteEvent` (reliable, ordered)

**Current behavior**
- A RemoteEvent provides one-way, non-yielding messaging:
  - `FireServer(args)` → `OnServerEvent(player, args)`;
  - `FireClient(player, args)` / `FireAllClients(args)` → `OnClientEvent(args)`.
- **Reliable and ordered.** Lost packets are retransmitted while the recipient stays connected. Messages arrive in fire
  order **across different RemoteEvent instances** for one connection and one direction (A, B, A arrives as A, B, A).
- If no handler is connected, messages are queued (count- and memory-limited) and delivered in order once a handler connects.
  Overflow is discarded and logs a `Remote event invocation` error.
- Messages are lost if the recipient disconnects.
- Ordering applies to when a handler **starts**. A yielding handler lets later messages start first.
- There is **no ordering relationship** between RemoteEvents and RemoteFunctions. With `NextGenerationReplication`, do not
  rely on ordering between property/attribute replication and remote events.
- Excess client sends over the throttle are **delayed, not dropped**, and keep their order.

**Sources:** `CD/scripting/events/remote.md` (sections "Delivery guarantees" and "Throttling and size limits");
`CD/reference/engine/classes/RemoteEvent.yaml`; `CD/reference/engine/classes/Workspace.yaml` (`NextGenerationReplication`);
`CD/projects/server-authority/index.md` ("Remote events" warning).

**Confidence:** High.

#### F1.2 `UnreliableRemoteEvent`

**Current behavior and exact limits**
- No delivery or ordering guarantee, and no ordering relative to other remote types. A message can be dropped when:
  - it is lost in transit;
  - it waits too long because of network congestion;
  - its **payload is > 1,000 bytes**;
  - the client exceeds the throttle (**dropped**, unlike RemoteEvent);
  - no handler is connected (discarded immediately).
- In Studio, the Output shows by how many bytes a dropped event exceeded the limit.
- The engine "encodes and compresses certain object types, such as buffers". This makes the final size hard to predict
  before firing.
- Methods: `FireServer`, `FireClient`, `FireAllClients`. Each carries the 1,000-byte limit.
- Guidance: include a sequence number or timestamp and ignore stale packets.

**History:**
- The current docs say 1,000 bytes. ARCHITECTURE §5.2 uses ≤ 900 bytes, which may come from the limit at launch.
- **[prior knowledge, not re-verified]** The class shipped in 2023/24.
- The current figure in the docs is authoritative.

**Sources:** `CD/reference/engine/classes/UnreliableRemoteEvent.yaml`; `CD/scripting/events/remote.md`.

**Confidence:** High for the current limits; Low for the history.

#### F1.3 `RemoteFunction` pitfalls

- `InvokeServer` yields until the callback returns. Only the **last** assigned `OnServerInvoke` is used. Responses can come back
  out of order if callbacks yield. Invocations are queued while no callback is set.
- `InvokeClient` is dangerous. The docs list three failure modes:
  - a client error is re-thrown on the server;
  - a disconnect during the call throws;
  - **a client that never returns makes the server yield forever**.
- There is no engine timeout on `InvokeServer` either. Client code that needs a timeout must wrap the call itself
  (OUR DESIGN CHOICE: our `NetClient.invoke` races a `task.delay(10)` timeout).

**Sources:** `CD/scripting/events/remote.md` ("Server → client → server" and "RemoteFunctions").

**Confidence:** High.

#### F1.4 Throttling and rate limits

| Item | Value | Source |
|---|---|---|
| Client→server rate, RemoteEvent | ≈ **500 requests/s per client**, **shared among all RemoteEvents** | `RemoteEvent.yaml` "Throttling" |
| Client→server rate, UnreliableRemoteEvent | ≈ **500/s per client**, shared among all UnreliableRemoteEvents (a separate pool) | `UnreliableRemoteEvent.yaml` |
| Over-limit behavior | Reliable: queued and delayed, order kept. Unreliable: dropped | `remote.md` |
| Server→client | No documented per-message cap. Bounded by replication queues: data ping rises when the server produces more than the link carries | `CD/performance-optimization/identify.md` (data ping) |
| Server outbound HTTP | **500 external HTTP requests/min per server**. Open Cloud calls made through HttpService have a **separate limit of 2,500/min per server** and "do **not** consume" the 500/min budget (corrected by fact-check). `rate-limits.md` still says they count toward the 500; that is a docs conflict, so budget the combined traffic under 500/min to be safe | `CD/reference/engine/classes/HttpService.yaml` ("Limitations"), `CD/cloud-services/http-service.md` ("Rate limits"); conflicting: `CD/cloud/reference/rate-limits.md` |

**Confidence:** High, except whether in-game Open Cloud calls share the 500/min HTTP budget (Medium: the docs conflict).

**Important:** the engine throttle is **not a security control**. An exploiter can still send about 500 calls/s to *every*
handler. Per-remote token buckets on the server are mandatory (`CD/scripting/security/client-server-boundary.md`
"Rate limiting", which includes a reference `TokenBucket`).

#### F1.5 Argument types (including `buffer`)

- Any Luau value or Roblox datatype can be passed: numbers, strings, booleans, tables, `buffer`, `Vector3`, `CFrame`,
  `Color3`, EnumItems, and Instances.
- Caveats from `remote.md` "Argument limitations":
  - **Non-string table keys** (Instances, userdata, functions) are converted to strings.
  - **Functions** arrive as `nil`.
  - **Mixed tables** (array plus dictionary keys) misbehave. Avoid `nil` holes.
  - Tables are **copied**: identity is not preserved and **metatables are lost**.
  - An Instance the recipient cannot see (for example in `ServerStorage`, or client-created) arrives as **`nil`**.
- `buffer`: a fixed-size mutable byte block of at most **1 GiB** (`CD/reference/engine/libraries/buffer.yaml`), compressed by
  the remote encoder. It is the right carrier for our `InputPacket` and `SnapshotPacket` codecs.
- Security consequence: a client can send a *table shaped like an Instance*. Validate with `typeof(x) == "Instance"` plus
  `x:IsDescendantOf(expectedFolder)`. Reject NaN and ±inf with `math.isfinite`. (Docs include an explicit "danger of NaN"
  example: NaN fails every comparison, so range checks pass silently.) Source: `CD/scripting/security/client-server-boundary.md`.

**Confidence:** High.

#### F1.6 Bandwidth and latency guidance

- **What the docs give:**
  - "Most players on Roblox game between **100–300 ms** of network latency." Playtest with **50–150 ms** inbound **and**
    outbound simulated delay (`CD/projects/client-server.md`).
  - Network ping versus data ping: data ping includes replication-queue time. If data ping ≫ network ping, the server is
    over-producing (`CD/performance-optimization/identify.md`).
  - Mitigations (`CD/performance-optimization/improve.md` "Networking and replication"):
    - send only changes, at a lower frequency;
    - throttle input-driven replication;
    - avoid server-side `TweenService`;
    - chunk large instance trees;
    - build VFX on clients.
- **What the docs do NOT give:** no current page states a per-player KB/s budget.
  - **[prior knowledge, not re-verified]** Community guidance has long quoted about **50 KB/s** per client as the point
    where problems start.
  - Treat that as an upper bound, not a target.
- **Server heartbeat is capped at 60 FPS.** The client default cap is 60 FPS, and users can raise it to 240 on Windows
  (`identify.md`).

**Confidence:**
- High for the documented latency figures.
- Low for the 50 KB/s figure.

#### F1.7 What replicates, and how to keep information from specific clients

| Container | Replication | Source |
|---|---|---|
| `Workspace` | To all clients (with streaming: by distance from the focus). **StreamingEnabled is not a secrecy tool.** | `CD/projects/data-model.md`, `CD/scripting/security/access-control.md` |
| `ReplicatedStorage`, `ReplicatedFirst` | To all clients. Scripts and ModuleScripts there **can be decompiled even if never run** | `access-control.md` "Script decompilation" |
| `ServerStorage`, `ServerScriptService` | Never replicated. Cannot be decompiled | `data-model.md`, `access-control.md` |
| `Players.<Player>` children (for example `leaderstats`, attributes on Player) | Visible to all clients | **[Medium — standard engine behavior]** |
| `PlayerGui` | **Only to that player** (class tag `PlayerReplicated`, the only class carrying it in the API dump) | `CD/reference/engine/classes/PlayerGui.yaml` |
| `PlayerScripts` | Client-only. The server cannot see it | `PlayerScripts.yaml` |
| Client-created instances | Never replicate to the server or to others. Never stream out unless parented under a server-created instance | `CD/workspace/streaming/index.md` |
| Remote payloads | Only to the targeted client(s) (`FireClient`) | `remote.md` |

**Hiding techniques:**
1. Keep secret state in server memory or `ServerStorage`. Send each observer only what it may know (`FireClient`).
2. Use `PlayerGui` only for per-player UI, never for gameplay secrets the owner should not see.
3. Do not ship unreleased content in production builds. Feature flags do not hide replicated data, and clients can reach any
   subplace unless "Secure within universe only" is set (`access-control.md`).
4. Avoid predictable remote names, and never put server logic in shared modules.

**Confidence:** High, except the Player-children row (Medium).

#### F1.8 Roblox "Server Authority" model (engine prediction)

**Current behavior**
- Enabled with `Workspace.AuthorityMode = Server`. That forces:
  - `NextGenerationReplication`;
  - `PlayerScriptsUseInputActionSystem`;
  - `SignalBehavior = Deferred`;
  - `UseFixedSimulation`;
  - `StreamingEnabled`.
- Gameplay runs in `RunService:BindToSimulation()` callbacks, which may only touch properties labelled "Simulation Access".
  Custom state lives in attributes.
- The client predicts ahead, then rolls back and resimulates on misprediction.
- Inputs go through the Input Action System, with `InputContext` under the Player.
- Instance "stitching" uses deterministic GUIDs.

**Exact limits:** replicated attributes on predicted instances must be:
- among the **first 64** attributes;
- with a **name ≤ 50 chars**;
- with a **string value ≤ 50 chars**.

**Status:** "Server authority is **currently in beta** and will be released soon"
(`CD/scripting/security/network-ownership.md`). Templates exist (Racing, Soccer, Laser Tag).

**Fit for HULLDOWN:** poor for core combat.
- Predicted instances replicate to every client, which defeats spotting secrecy.
- The system depends on a beta feature.
- Its attribute and string limits are tight.

Our custom 30 Hz simulation plus per-observer snapshots (ARCHITECTURE §6) remains correct. Revisit the feature for
friendly-only effects after GA.

**Sources:** `CD/projects/server-authority/index.md`, `techniques.md`; `CD/reference/engine/classes/RunService.yaml`,
`Workspace.yaml`.

**Confidence:** High.

---

### F2. Spatial queries

**Current API (`WorldRoot`, available on `Workspace` and `WorldModel`)**

| Method | Exact limits | Thread safety |
|---|---|---|
| `Raycast(origin, direction, params?)` | Direction length ≤ **15,000 studs** | **Safe** (parallel) |
| `Blockcast(cframe, size, direction, params?)` | Size ≤ **512 studs** per axis. Distance ≤ **1,024 studs** | Safe |
| `Spherecast(position, radius, direction, params?)` | Radius ≤ **256 studs**. Distance ≤ **1,024 studs** | Safe |
| `Shapecast(part, direction, params?)` | Uses the real part geometry. Distance ≤ **1,024**. No Terrain parts | **Unsafe** |
| `GetPartBoundsInBox` / `GetPartBoundsInRadius` / `GetPartsInPart` | Overlap queries (`OverlapParams`) | Safe (all three) |
| `BulkMoveTo(parts, cframes, mode)` | Fast mass CFrame set without per-part Changed events | Unsafe |

- Shape casts **do not detect parts that initially intersect** the shape.
- `RaycastResult` has the fields `Instance`, `Position`, `Normal`, `Distance` and **`Material`**. For Terrain, `Material` is
  the voxel material at the hit (`RaycastResult.yaml`). That gives ground type for mobility and ricochet surfaces with
  no extra lookup.
- **`RaycastParams` (current):**
  - `ExcludeInstances` / `IncludeInstances` are the new arrays. They can be used together and **exclusions win**.
    `IncludeInstances = nil` includes everything; `{}` includes nothing.
  - `FilterDescendantsInstances` + `FilterType` (`Enum.RaycastFilterType.Include/Exclude`) and `AddToFilter` are
    documented as **superseded**.
  - Other fields: `IgnoreWater`, `CollisionGroup` (parts in groups that do not collide with it are ignored),
    `RespectCanCollide` (use `CanCollide` instead of `CanQuery`), and `BruteForceAllSlow` (never in production).
  - `RaycastParams` is mutable and reusable.
- `BasePart.CanQuery = false` exempts a part from all queries.
- Under streaming, a client may not have distant parts streamed in. **Imposter/SLIM terrain and models are not raycastable.**
- **WorldModel outside Workspace.**
  - `WorldModel` inherits `WorldRoot`. Docs: parts under a WorldModel "can be animated and spatially queried (for example
    by raycasts) but … **not** simulated". `UseWorkspaceCollisionGroups` chooses shared or independent collision groups.
  - The docs describe it in a `ViewportFrame` context and do **not** state that a WorldModel in `ServerStorage` can be
    queried on the server.
  - **[Medium — community practice, not re-verified]** It works, because the queries run on the WorldModel's own physics world.
  - HULLDOWN does not need it: armor is analytic and map geometry sits in Workspace. Verify with an in-engine self-test before relying on it.
- **Performance guidance:**
  - The docs give no per-call cost numbers.
  - The documented levers are: reuse params, restrict `IncludeInstances`, use collision groups, set `CanQuery = false` on
    decor, and run raycast validation in parallel Luau (`CD/scripting/multithreading.md`, "Server-side raycasting
    validation").

**History:** `FilterDescendantsInstances`/`FilterType` superseded by Include/Exclude arrays. The date was not verifiable here.

**Sources:**
- `CD/reference/engine/classes/WorldRoot.yaml`, `WorldModel.yaml`;
- `CD/reference/engine/datatypes/RaycastParams.yaml`, `RaycastResult.yaml`;
- `CD/workspace/raycasting.md`.

**Confidence:** High, except the server-side WorldModel point (Medium).

---

### F3. StreamingEnabled

**Current behavior:**
- **Scope:** only `Workspace` descendants stream. Atomic models under `ReplicatedStorage` are *not* atomic.
- `StreamingEnabled` is on by default for new places and **cannot be set from scripts**.
- **Stream-in:** at join, non-BasePart instances replicate. BaseParts and Atomic/Persistent models, plus Nonatomic models
  under `ModelStreamingBehavior = Improved`, are deferred and streamed by priority around the replication foci.
- **Stream-out:**
  - Governed by `StreamOutBehavior`. `LowMemory` (default) streams out only beyond the min radius under memory pressure.
    `Opportunistic` may drop content beyond the target radius at any time.
  - Content inside `StreamingMinRadius` never streams out.
  - Streamed-out instances are parented to `nil`, not destroyed. Local-only property changes can be lost.
- **Assemblies** stream in as complete units. Anchored assemblies are the exception.
- **Model controls (`Model.ModelStreamingMode`):**
  - `Nonatomic` (default);
  - `Atomic` (all descendants together);
  - `Persistent` (sent at join before `Workspace.PersistentLoaded`, never streamed out; "not intended to circumvent streaming");
  - `PersistentPerPlayer` (persistent only for players added with `Model:AddPersistentPlayer`).
- **Properties, all set in Studio only:**
  - `StreamingMinRadius`, default **64** (recommended);
  - `StreamingTargetRadius`, default **1,024** (recommended). Must be > min, because the band between them is a buffer;
  - `StreamOutBehavior`;
  - `ModelStreamingBehavior` (`Legacy` by default, or `Improved`);
  - `StreamingIntegrityMode` (`PauseOutsideLoadedArea` recommended);
  - `PredictiveStreamingMode` (opt-in: pre-fetches spawn areas and areas recently left);
  - `EnableSLIMAvatars`.
- **Replication focus:**
  - Defaults to the character's `PrimaryPart`.
  - `Player.ReplicationFocus` is a **server-set Instance/Part**.
  - `Player:AddReplicationFocus(part)` adds extra foci (each one costs as much as roughly one more moving player).
  - `Player:RequestStreamAroundAsync(pos, timeout)` pre-fetches.
  - Client physics, including server-authority prediction, only simulates in streamed areas.
- **Frustum streaming (new):**
  - Set per player with `Player.FrustumStreaming = Enum.FrustumStreamingMode.Default|Disabled|Automatic|Enabled`, on the
    server only.
  - Streams what is inside the camera view beyond the radius.
  - `Automatic` triggers on a narrow FOV (scopes), on fast motion toward the view, or when the camera is far from the focus.
  - Uses the same bandwidth and instance budgets as a replication focus.
- **SLIM (new):** cloud-generated composite LOD for models and avatars. Requires a place saved to Roblox and Team Create.
  Streamed-out SLIM models stay visible as stand-ins.

**Implications for HULLDOWN** (2,500–3,500-stud square maps, character-less, client-rendered vehicles):
1. A 3,000-stud map is about 3× the default target radius. With streaming on, distant terrain and buildings would arrive
   as imposters or nothing, which hurts long-range sniping and LOS readability. Frustum streaming in `Automatic` helps.
2. **There is no character**, so streaming needs a `ReplicationFocus` Part following each player's vehicle. If that Part
   is in Workspace it **replicates its CFrame to every client within streaming range, which is a wall-hack leak**. Whether
   a focus Part kept in a non-replicated container works is undocumented. See Open questions.
3. Client-rendered vehicle models created by LocalScripts are exempt from streaming-out, as long as they are not
   parented under server-created instances. Put them under a client-created Folder.
4. Client prediction raycasts against local map geometry need that geometry present around the vehicle.

**Sources:**
- `CD/workspace/streaming/index.md`, `frustum.md`, `slim.md`, `techniques.md`;
- `CD/reference/engine/classes/Player.yaml` (`ReplicationFocus`, `AddReplicationFocus`, `RequestStreamAroundAsync`).

**Confidence:** High for the facts; Medium for the leak analysis (the mechanism follows from the docs).

---

### F4. MemoryStoreService, MessagingService, leader election

#### F4.1 Data structures and quotas

| Item | Value |
|---|---|
| Structures | **Queue** (`GetQueue(name, invisibilityTimeout = 30)`), **SortedMap** (`GetSortedMap`), **HashMap** (`GetHashMap`). Names are global in the experience |
| Memory quota (experience) | **64 KB + 1.2 KB × users**. Grows immediately, shrinks only after an **8-day** traceback. Over quota, all size-increasing writes fail |
| Request quota (experience) | **1,000 + 120 × CCU request units (RU)/min** |
| RU costs | Most calls cost 1 RU. Exceptions: `SortedMap:GetRangeAsync` costs RU = items returned (min 1). `Queue:ReadAsync` costs items returned **plus 1 RU per 2 s** of waiting. `HashMap:UpdateAsync` costs **≥ 2**. `HashMap:ListItemsAsync` costs partitions scanned + items |
| Per structure (SortedMap, Queue) | ≤ **1,000,000 items**, ≤ **100 MB**. The status table also lists `DataStructureRequestsOverLimit` at **100,000 RU/min** per structure |
| Per partition | Throttling starts at about **30,000 RU/min**. A SortedMap or Queue is **one partition**. HashMaps spread across partitions |
| Per hash-map key | About **5,000 write RU/min** and **15,000 read RU/min** |
| Item value | ≤ **32 KB** (`ItemValueSizeTooLarge`) |
| Key / sort key | ≤ **128 chars**. A sort key is a number or a string. Numeric sort keys order before string ones, and both before none |
| Expiration | 0 – **3,888,000 s (45 days)** (`InvalidExpirationTime`). The default for `AddAsync`/`SetAsync` is 45 days. Always pass a short TTL |
| Queue `ReadAsync(count, allOrNothing, waitTimeout)` | `count` ≤ **100**. Read items become invisible for the invisibility timeout and must be `RemoveAsync(id)`'d before it expires. A `waitTimeout` of −1 waits forever. Polls every 2 s |
| SortedMap `GetRangeAsync` | `count` ≤ **200** per call |
| UpdateAsync contention | Retried automatically until success, a `nil` return from the callback (abort), or max retries (`UpdateConflict`) |
| `SortedMap:UpdateAsync(key, transformFunction, expiration)` | **`expiration` is a required parameter**, and the transform receives `(oldValue, oldSortKey)` and must return **`(newValue, newSortKey)`**. Return the old sort key unchanged to keep FIFO position (corrected by fact-check: R3 originally omitted both). `HashMap:UpdateAsync(key, fn, expiration)` also takes an expiration |
| Studio | Data is isolated from production. Quotas are the same, so they are tiny with one user. Latency and errors are slightly higher |
| Extended Services | Paid overage: **$0.003 per 1 M requests**, **$0.10 per GB-hour**. Requires an ID-verified 18+ owner in a supported country |

**Sources:**
- `CD/cloud-services/memory-stores/index.md`, `queue.md`, `sorted-map.md`, `hash-map.md`, `best-practices.md`;
- `CD/reference/engine/classes/MemoryStoreQueue.yaml`, `MemoryStoreSortedMap.yaml`, `MemoryStoreService.yaml`;
- `CD/cloud-services/extended-services.md`.

**Confidence:** High.

**Matchmaking patterns:**
- Docs' canonical pattern: "Save user information, such as skill level, in a shared **queue** among servers, and use
  lobby servers to run matchmaking periodically."
- A Queue cannot cancel an arbitrary item; you must read it first. A **SortedMap** keyed by `ticketId`, with
  `sortKey = enqueue time`, supports cancel (`RemoveAsync`), atomic claim (`UpdateAsync`) and FIFO scans (`GetRangeAsync`).
  The price is that a scan costs one RU per item.
- Shard by bucket to stay under the 30k RU/min partition limit.

#### F4.2 MessagingService

| Limit | Value |
|---|---|
| Topic name | 1–80 chars |
| Message size | **1 kB** |
| Latency / guarantee | Typically **1–2 s**. **Best effort, not guaranteed** |
| Sent per server | **600 + 240 × players-in-server** per minute |
| Received per topic | **40 + 80 × number-of-servers** per minute |
| Received for the whole game | **400 + 200 × servers** per minute |
| Subscriptions per server | **20 + 8 × players-in-server** |
| Subscribe requests per server | **240/min** |
| Open Cloud publish | `POST /cloud/v2/universes/{id}:publishMessage` (scope `universe-messaging-service:publish`), **5,000/min** |

**Sources:** `CD/reference/engine/classes/MessagingService.yaml`; `CD/cloud-services/cross-server-messaging.md`; `openapi.json`.

**Confidence:** High.

#### F4.3 Leader election (global matchmaker)

There is no Roblox primitive for this.

**Standard lease pattern [Medium: derived from the documented UpdateAsync semantics]:**
- Run `HashMap:UpdateAsync("lease", fn, ttl)`.
- The callback takes the lease when it is absent, or when `holder == game.JobId`. It returns `nil` (abort) otherwise.
- The item's own **TTL is the lease expiry**. This avoids cross-server clock skew, because no wall-clock comparison is needed.
- Tag each acquisition with a fresh GUID `term`. A numeric epoch would restart after expiry.

Two leaders can overlap briefly when a renewal is slow. All irreversible actions must therefore be guarded by per-ticket
atomic claims (see §R3).

---

### F5. TeleportService (place-to-place inside one universe)

**Current behavior and exact values**
- **`TeleportService:ReserveServerAsync(placeId)`**:
  - Returns a **tuple**: the access code and the server's **`PrivateServerId`**. Server only.
  - **`ReserveServer` is tagged Deprecated** in favor of `ReserveServerAsync`. ARCHITECTURE §2.1 still names the deprecated call.
  - A server starts when the code is first used.
  - **"Access codes remain valid indefinitely"**: joining after the old instance closed **starts a new server**.
  - `PrivateServerId` is constant across all instances for that code; `JobId` is not.
  - Detecting a reserved server: `game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0`. `PrivateServerOwnerId`
    is the buyer's UserId for paid private servers and **0** for reserved servers.
- **`TeleportAsync(placeId, players, teleportOptions?)`**:
  - Server only. At most **50 players per call**. Group teleports only within one experience.
  - Returns a **`TeleportAsyncResult`** (`PrivateServerId`, `ReservedServerAccessCode`) when options are passed.
  - **`TeleportOptions`** fields: `ReservedServerAccessCode`, `ShouldReserveServer` (create a new reserved server),
    `ServerInstanceId` (a specific public server), and `SetTeleportData(table)`.
  - Conflicting combinations throw "Incompatible Parameters":
    - code + instance id;
    - reserve + instance id;
    - reserve + code.
  - Other documented errors:
    - Invalid placeId;
    - Players empty;
    - a non-Player in the list;
    - wrong options type;
    - called from the client.
- **Failure handling:**
  - Wrap the call in `pcall` and retry; this is especially recommended for reserved servers.
  - A call can succeed and the teleport still fail late. `TeleportInitFailed(player, TeleportResult, errorMessage, placeId,
    teleportOptions)` then fires on client and server, **once per player** for group teleports.
  - It supplies a **new `TeleportOptions` preset to retry to the exact same destination**. When a reserve was requested,
    that includes the generated code.
  - `Enum.TeleportResult` values: `Success`, `Failure`, `GameNotFound`, `GameEnded`, `GameFull`, `Unauthorized`,
    `Flooded`, `IsTeleporting`.
  - The doc's sample `SafeTeleport` uses `ATTEMPT_LIMIT = 5`, `RETRY_DELAY = 1 s`, `FLOOD_DELAY = 15 s`. It retries on
    `Failure` and `Flooded` and errors on everything else.
- **Teleport data trust model:**
  - `SetTeleportData` content is "visible to the client and unencrypted".
  - Allowed: primitives, value types and plain tables. Instances, functions, SharedTable and RaycastParams are stripped.
    The only size limit is "a reasonable depth and size".
  - Server-side `Player:GetJoinData().TeleportData` is only returned when it was sent by a Roblox server **within 48 h**,
    with **this player**. `SourcePlaceId`/`SourceGameId` are guaranteed.
  - Docs: it "can still potentially be abused… Sensitive data … should be transmitted via … **Memory Stores**".
  - `GetJoinData` also includes `Members` (group teleport), `LaunchData` (invites and share links), `ReferredByPlayerId`
    and `GameJoinContext`.
- **Place access security:**
  - Creator Dashboard → Access Control for Places offers:
    - **Fully open**;
    - **Limited to same universe** (client and server teleports);
    - **Secure within universe only** (non-start places accept **only server-initiated** teleports). Docs recommend this
      "for places that exclusively use reserved servers".
  - Without it, any client can teleport to any subplace and receive its replicated content before a kick can run.
- **Cross-play:**
  - Xbox and PlayStation players with cross-play off "arrive in a different server", so **multiple servers can share one
    `PrivateServerId`**. Check `game.MatchmakingType` (`Default`, `XboxOnly`, `PlayStationOnly`; valid on the server only).
  - Players with different `MatchmakingType`s cannot be in, or teleport to, the same server.
- **Studio limitation:** TeleportService does not run in Studio playtests. Publish and test in the client.
- **Custom loading screen:** `TeleportService:SetTeleportGui(screenGui)` on the client. Scripts inside it do not run.

**Sources:**
- `CD/projects/teleport.md`;
- `CD/reference/engine/classes/TeleportService.yaml`, `TeleportOptions.yaml`, `TeleportAsyncResult.yaml`, `DataModel.yaml`,
  `Player.yaml` (`GetJoinData`);
- `CD/reference/engine/enums/TeleportResult.yaml`, `MatchmakingType.yaml`;
- `CD/scripting/security/access-control.md`.

**Confidence:** High.

**Reserved server lifetime:** an instance runs while players are in it. The docs only say private servers "can have
multiple server instances … over time … no server instance is running when nobody is playing". The exact
idle-shutdown delay is **not documented** (Low).

---

### F6. DataStoreService

#### F6.1 Limits

| Category | Value | Source |
|---|---|---|
| Data store name / key / scope | **50 chars** each | `error-codes-and-limits.md` "Data limits" |
| Value | **4,194,304 chars** per key (stored as a JSON string, must be valid UTF-8) | same; `GlobalDataStore.yaml` |
| User metadata | Key ≤ 50, value ≤ 250, **total ≤ 300 chars** | same |
| Per-key throughput | Read **25 MB/min**, write **4 MB/min** (sliding 60 s, every request rounded up to 1 KB) | "Throughput limits" |
| Experience limits (standard stores; game servers + Open Cloud **shared**) | Read **300 + 40 × CCU**, Write **300 + 20 × CCU**, List **300 + 2 × CCU**, Remove **300 + 40 × CCU** per minute | "Experience Limits" |
| Experience limits (ordered stores) | Same shape: Read 300 + 40 × CCU, Write 300 + 20 × CCU, List (`GetSortedAsync`) 300 + 2 × CCU, Remove 300 + 40 × CCU | same |
| Per-server defaults (standard) | `StandardRead` **60 + 40 × players**, `StandardWrite` **60 + 40 × players**, `StandardList` **5 + 2 × players**, `StandardRemove` **60 + 40 × players**, `RemoveVersionAsync` 5 + 2 × players (deprecated) | "Server limits" |
| Per-server defaults (ordered) | `OrderedRead` 60 + 40 × players, **`OrderedWrite` 30 + 5 × players**, `OrderedList` 5 + 2 × players, `OrderedRemove` 30 + 5 × players | same |
| Startup | "One-time startup burst of additional request budget" for new servers | same |
| `UpdateAsync` | Consumes **both** the read and the write budget | same |
| Tuning | `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.X)`. `SetRateLimitForRequestType(type, base, perPlayer)`: call once at init. Not allowed for `UpdateAsync` or `OnUpdate` | `DataStoreService.yaml` |
| Throttle queues | Set / ordered set / get / ordered get queues of **30 requests** each. Overflow fails with codes **301–306**. Throttled keys are skipped temporarily | "Limits" |
| Storage | **500 MB + 1 MB × lifetime users**. Counts the compressed latest version only. Don't pre-compress (DataStores compress automatically) | "Storage limits" |
| Cache | `GetAsync` caches for **4 s** per DataStore object. Cached hits do not count toward limits. Version and list APIs are uncached | `versioning-listing-and-caching.md` |
| Versioning | Old versions expire **30 days** after being overwritten. The latest version never expires. Deleted stores have a 30-day undo window | same; `best-practices.md` |
| Studio | Run-mode requests have separate static (lower) limits. Use Team Create to test rate limits | "Server limits" |

**Discrepancies to note:**
- `CD/cloud-services/extended-services.md` lists defaults of **250 + CCU × 40** (Get) and **250 + CCU × 20** (Set),
  **10 + CCU × 2** (List), **100 + CCU × 40** (Remove), and storage of **100 MB + 1 MB × lifetime players**.
- The limits page (300 + …, 500 MB + …) is the more specific source.
- Design to the **lower** of the two.

**Confidence:** High for each figure, Medium for which variant is live.

#### F6.2 Semantics

- **`UpdateAsync(key, transform)`**:
  - Reads the latest value plus `DataStoreKeyInfo`.
  - The transform returns `(newValue, userIds?, metadata?)`. Returning `nil` cancels.
  - It is re-invoked if another server wrote in between.
  - The callback **cannot yield**.
  - You must pass through `keyInfo:GetUserIds()` and `GetMetadata()`, or they are cleared.
  - Ordered stores do not version: an update overwrites.
- `SetAsync` counts against writes only and is unsafe across servers.

**GDPR / right to be forgotten:**
- Associate `userIds` on every write.
- **Automated RTBF (new):** declare up to **100 deletion templates** using a case-sensitive `{UserId}` token in the data
  store name, scope or key (for example key `Player_{UserId}`).
- Templates can be configured in the Data Stores Manager or via the Configs API (`universe:read` + `universe:write`).
- Roblox then deletes the matching keys automatically. Whole-store deletion applies to standard stores only.

**Session locking (reference implementation):**
- Every operation goes through `UpdateAsync`. A `LockId` GUID is written into the key's **metadata**, and the operation is
  abandoned if a foreign, unexpired `LockId` is present, or if the server's own lock has been replaced.
- The lock is refreshed by the periodic save loop. Its sample autosave is **180 s**, randomly offset per player.
- The final save also unlocks, on leave and in `BindToClose`.
- On load failure, the sample plays with default data marked "errored" and **never saves it**.
- Saves for one key must be **ordered**, so naive concurrent retries can overwrite newer data. The sample uses a per-key
  serial queue with exponential backoff and jitter (base 2 s, cap 32 s, 5 attempts).

**`BindToClose`:** callbacks get **30 s** total (`DataModel.yaml`). Save in parallel and skip stale queued writes.

**ProfileStore (loleris, MAD STUDIO; source fetched from GitHub):**
- Session stored in the value: `MetaData.ActiveSession = {PlaceId, JobId, unique_session_id}`, plus `SessionLoadCount`,
  `LastUpdate` and `ForceLoadSession`.
- Constants:
  - `AUTO_SAVE_PERIOD = 300`;
  - `FIRST_LOAD_REPEAT = 5`;
  - `LOAD_REPEAT_PERIOD = 10`;
  - `SESSION_STEAL = 40`;
  - `ASSUME_DEAD = 630`;
  - `START_SESSION_TIMEOUT = 120` s.
- It publishes to the MessagingService topic `"PS_" .. sessionId` to ask the current owner to end the session quickly.
- It refuses to be used for leaderboards or global state.

**Leaderboards:**
- `OrderedDataStore` values must be **integers**. `GetSortedAsync(ascending, pageSize ≤ 100, min?, max?)`.
- `BatchGetAsync` is currently supported on ordered stores only.
- The built-in PlayerList now has **Here / Friends / Global** views. Friends and Global come from an ordered data store you
  register in Creator Hub (`CD/players/leaderboards.md`).

**Sources:**
- `CD/cloud-services/data-stores/*.md`;
- `CD/reference/engine/classes/GlobalDataStore.yaml`, `DataStoreService.yaml`, `OrderedDataStore.yaml`, `DataModel.yaml`;
- `https://raw.githubusercontent.com/MadStudioRoblox/ProfileStore/main/ProfileStore.luau` (fetched 2026-10-05).

**Confidence:** High.

---

### F7. Monetization: MarketplaceService, PolicyService, pricing

**Developer products (repeatable purchases):**
- Price **1 – 1,000,000,000 Robux**. Icon 512×512 (jpg, png or bmp).
- Prompt with `PromptProductPurchase(player, id)`. List products with `GetDeveloperProductsAsync()`, and get info with
  `GetProductInfoAsync(id, Enum.InfoType.Product)`.
- **Never grant on `PromptProductPurchaseFinished`.**

**Receipt handling:**
- **`ProcessReceipt` guarantees.** It is called for every unresolved purchase:
  - when the user completes a purchase;
  - when a successful purchase prompt appears;
  - **when the user joins a server**.
- **No time-based retry and no timeout.** A yielding callback is still honoured whenever it returns.
- Called again only on the next purchase or a rejoin.
- Multiple pending receipts arrive in **non-deterministic order**.
- **The same purchase can run on two servers at once** if the user joins a second server before the first returns.
- `PurchaseGranted` can still fail to record, leaving the purchase unresolved.
- If no handler exists, receipts are **auto-acknowledged** and lost to you.
- `receiptInfo` fields: `PurchaseId`, `PlayerId`, `ProductId`, `PlaceIdWherePurchased`, `CurrencySpent`, `CurrencyType`
  (Robux), and `ProductPurchaseChannel`.
- **New: `MarketplaceService:BindReceiptHandler(Enum.ReceiptType, handler, filter?)`**:
  - Returns an `RBXScriptConnection`. The handler returns **`Enum.ReceiptDecision.Processed` or `NotProcessedYet`**.
  - Filtered handlers (by product ID) and one catch-all per type.
  - Bound handlers take precedence over `ProcessReceipt`.
  - Also handles `RobuxTransferSender` and `RobuxTransferReceiver` receipts.
- The official "atomic purchase" algorithm, in order:
  1. Verify the profile is loaded and session-locked.
  2. Check that the `PurchaseId` is not already recorded.
  3. Grant in memory.
  4. Record the `PurchaseId`.
  5. Save.
  6. Return granted only if the save succeeded. If the ID is recorded but not yet saved, return `NotProcessedYet`.

  (`CD/cloud-services/data-stores/player-data-purchasing.md`.)

**Passes (one-time):**
- Check with `UserOwnsGamePassAsync(userId, passId)` on join. Prompt with `PromptGamePassPurchase`.
- Grant on `PromptGamePassPurchaseFinished` (server).
- Roblox does not keep per-user pass purchase history for you.

**Cross-game sales:** "**Starting May 30, 2026, cross-game developer product [and pass] sales will be disabled**." Use
Robux transfers instead (not relevant to us).

**Subscriptions:**
- Monthly and auto-renewing.
- **Robux** pricing (≥ **49 R$**, regional pricing forced on, 70% payout) **or local currency** at **$2.99, $4.99, $7.99,
  $9.99 or $14.99**:
  - 70% in month 1, then 100%;
  - requires an ID- or phone-verified creator;
  - Web, App Store and Google Play only;
  - unavailable in AR, CN, CO, IN, ID, JP, RU, TW, TR, AE, UA and VN.
- Rules:
  - **no mutually exclusive tiers**;
  - same benefits on every platform;
  - never revoke benefits mid-term;
  - no steering to off-platform purchases;
  - battle passes are allowed.
- APIs: `PromptSubscriptionPurchase`, `GetUserSubscriptionStatusAsync`, `GetUserSubscriptionDetailsAsync`,
  `Players.UserSubscriptionStatusChanged`, `PolicyService…IsEligibleToPurchaseSubscription`.

**Managed Pricing (new umbrella):**
- **Regional pricing:**
  - Price bounded at **30%–100% of the default price**.
  - Determined by the user's "economic location" (VPN, billing and history signals).
  - On by default for passes and for Robux-priced subscriptions. Opt-in for developer products.
  - Requires dynamic prices and `GetUsersPriceLevelsAsync` for gifting/trading.
- **Price optimization:**
  - Needs about **60,000 transactions per 30 days**.
  - Tests take about **3 weeks** and re-run at least every 90 days.
  - Prices are applied only if total revenue rises.
- **Hard-coded prices in the UI are wrong.** Roblox charges the regional or test price, so fetch prices with
  `GetProductInfoAsync` **from a client script**. A **Dynamic Price Check** tool detects hard-coded prices.
- New games and items are **enrolled by default**.

**Shop (Roblox-owned UI):**
- Lists all passes and eligible products. A product can be unlisted; passes cannot.
- Surfaces items outside the game, so `ProcessReceipt` must be correct.
- Hide it in-game with `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.ExperienceShop, false)`.

**Roblox Plus:**
- Subscribers get **10% off** (rising to **20%** from month 3). **Roblox covers the discount**, so creator earnings are unchanged.
- Up to **750 R$** for each Plus subscriber you convert via `PromptRobloxSubscriptionPurchase`.
- Up to 100 R$ per subscriber for ≥ 60 min/month in your paid private servers.

**DevEx:** **$0.0038 per earned Robux** (30,000 R$ = $114). **$0.0054** for qualifying purchases by age-verified US 18+ users.

**Paid random items:**
- Must show **every outcome and its numeric odds**, summing to 100%, before purchase. This includes items bought with
  currency that was bought with Robux, and luck boosts.
- Users with `ArePaidRandomItemsRestricted == true` must get one of:
  - a free path;
  - a deterministic order;
  - direct purchase;
  - hiding or blocking the item.
- `IsPaidItemTradingAllowed` gates trading of paid items.

**PolicyService `GetPolicyInfoForPlayerAsync(player)`** returns:
- `AreAdsAllowed`;
- `ArePaidRandomItemsRestricted`;
- `IsContentSharingAllowed`;
- `IsEligibleToPurchaseCommerceProduct`;
- `IsEligibleToPurchaseSubscription`;
- `IsPaidItemTradingAllowed`;
- `IsPhotoToAvatarAllowed`;
- `IsSubjectToChinaPolicies`;
- `AllowedExternalLinkReferences` (legacy, always empty);
- `IsEndlessContentLoadAllowed`;
- `IsEndlessContentAutoplayAllowed`.

It must be wrapped in `pcall`, and errors if more than 100 calls are in flight.

**Robux pricing norms:** the docs publish no benchmark. Market norms could not be verified this session (Low). See §R7 for
OUR DESIGN CHOICE price points.

**Sources:**
- `CD/production/monetization/{developer-products, passes, subscriptions, regional-pricing, managed-pricing,
  price-optimization, shop, roblox-plus, developer-exchange, paid-random-items}.md`;
- `CD/reference/engine/classes/MarketplaceService.yaml`, `PolicyService.yaml`.

**Confidence:** High.

---

### F8. Social: invites, parties, chat, text filtering

**Invites:**
- Call `SocialService:CanSendGameInviteAsync(player)` first, then `SocialService:PromptGameInvite(player,
  experienceInviteOptions?)`. The options object `ExperienceInviteOptions` has:
  - `PromptMessage`: hidden if it overflows the UI;
  - `InviteUser`: a specific friend's UserId;
  - `InviteMessageId`: a Notification asset ID from Creator Dashboard → Engagement → Notifications. It must contain
    `{experienceName}` and may use `{displayName}`;
  - `LaunchData`: **≤ 200 chars**, read by the invitee via `Player:GetJoinData().LaunchData`.
- Events: `GameInvitePromptClosed`. Also available: `PromptLinkSharing(Async)` and `ReferredByPlayerId` in join data.

**Parties (Roblox platform parties):**
- `Player.PartyId` is a string, `""` when not in a party, and not replicated.
- `SocialService:GetPlayersByPartyId(partyId)` returns members on this server.
- `SocialService:GetPartyAsync(partyId)` returns members **across servers** with `UserId`, `PlaceId`, `JobId`,
  `PrivateServerId` and **`ReservedServerAccessCode`**, ordered by join time.
- Studio has a **Party Simulator**.

**Following:**
- With Battle places set to "Secure within universe only", friends who "join" a player in battle land in the **start place**
  (Hub) instead.
- This follows from the access-control docs: "players who try to join their friends in non-start places will instead join
  your game's start place" (stated for the non-"Fully open" settings).

**TextChatService:**
- **Channels:**
  - `CreateDefaultTextChannels` creates `RBXGeneral` and `RBXSystem`.
  - **`RBXTeam<BrickColorName>`** is auto-created for every team colour in use, with TextSources for non-neutral players
    of that colour.
  - Custom `TextChannel`s must be parented to TextChatService. Add users with `TextChannel:AddUserAsync(userId)`.
- **Routing:** `TextChannel.ShouldDeliverCallback` (server) decides per recipient. `OnIncomingMessage` callbacks are client
  only. `DisplaySystemMessage` posts system lines.
- **Filtering:** chat is filtered automatically, per recipient.

**Custom text (platoon names, notes):**
- `TextService:FilterStringAsync(text, fromUserId, context)` → `TextFilterResult:GetNonChatStringForBroadcastAsync()`
  (everyone) or `GetNonChatStringForUserAsync(userId)`.
- **Throws if `fromUserId` is not on the current server.** It retries internally, so do not retry on error.
- If filtering fails, show nothing.
- Filter on submit, never per keystroke.
- Unfiltered user text is grounds for **removal of the game**.
- Example in docs: a 60 s rate limit on a public text input.

**Preset systems (quick commands):** allowed for all ages if:
- each preset is **gameplay intent** ("Need help", "Defending this area", "Reloading", "Enemy nearby");
- presets are standalone and context-bound;
- presets have no social or identity meaning and cannot combine into "say anything slower".

**Age and chat:**
- Roblox Kids: chat off by default, enableable through a linked parent once age-checked.
- Select (9–15): off for self-declared accounts, introduced gradually once age-checked.
- 16+: on by default where available.

**Sources:**
- `CD/reference/engine/classes/SocialService.yaml`, `ExperienceInviteOptions.yaml`, `Player.yaml`, `TextChatService.yaml`,
  `TextService.yaml`;
- `CD/production/promotion/invite-prompts.md`;
- `CD/chat/in-experience-text-chat.md`, `CD/chat/preset-system-guidelines.md`, `CD/chat/examples/rate-limit-public-text-inputs.md`;
- `CD/ui/text-filtering.md`;
- `CD/production/publishing/kids-and-select.md`.

**Confidence:** High. Voice is out of scope.

---

### F9. Security model

**What exploiters can do (docs, 2026):**
- decompile any replicated LocalScript or ModuleScript, even disabled or never required;
- take network ownership of their character and nearby unanchored parts, then teleport, fly, fling, or spam `Touched` and
  ProximityPrompts at any range;
- **fire any remote at any frequency with arbitrary arguments** (except the first Player argument);
- change their local DataModel silently;
- teleport to **any subplace** in the universe unless secure teleports are on, and receive its replicated content before
  a server kick can run.

**Exploit categories relevant to us, and the documented mitigation:**

| Category | Mitigation (docs) | HULLDOWN status |
|---|---|---|
| Movement / physics (speed, fly, noclip, fling) | Server authority. Until then, heuristics with leaky buckets on the XZ plane | **Eliminated by design**: no character in battle, no physics vehicles; the server simulates movement |
| Remote abuse (spam, malformed, NaN/inf, giant strings, fake-Instance tables) | Context/permission, type/structure and value validation. Token bucket per player | `NetServer` schema plus token bucket (ARCHITECTURE §5.2) |
| Hit spoofing | Server checks shot origin near shooter, hit near target, static LOS, fire rate, ammo, team, alive, state | Server computes ballistics; the client only requests "fire" |
| Economy (duping, negative prices, replay) | Server prices, idempotency, session locks | `Transactions` plus requestId plus processed rings |
| Info leaks (wallhack, content datamining) | Don't replicate secrets. Avoid predictable names. Separate dev universes | Per-observer snapshots. No vehicle Instances on the server |
| Subplace access | **"Secure within universe only"** | Required for Battle places |
| Automation / macros | Heuristics: fastest-completion, rate-of-gain, action-cadence variance. Suspicion score. Honeypot remotes. Direction-misuse detection | Add to `AntiExploitService` |

**Consequences:**
- The docs prescribe a ladder: silent log → quiet mitigation → temporary restriction → kick, temp ban or ban.
- Delay visible consequences.
- Use the **Ban API**: `Players:BanAsync` (`Players.BanningEnabled`), with universe or place scope, duration,
  `DisplayReason` ≤ **400 chars**, and alt-account exclusion.
- Open Cloud `user-restrictions` allows 150 req/s per API-key owner, but the spec adds per-universe caps (update 10 req/s,
  get/list 50 req/s) and **at most 2 updates per minute for the same user** (corrected by fact-check).

**Engine anti-cheat — Hyperion/Byfron [prior knowledge, not re-verified; Low-Medium]:**
- Roblox acquired Byfron Technologies in 2022 and shipped the "Hyperion" anti-tamper with the 64-bit Windows desktop client
  in 2023. The Microsoft Store/UWP client, which lacked it, was later retired.
- It hardens the **client process** against injection, memory editing and debugging.
- It does **not**:
  - validate game logic or remote arguments;
  - stop macro or auto-clicker input;
  - stop exploits on platforms or emulators where protection differs;
  - prevent reading data you replicate;
  - fix server bugs.
- The current docs still say "assume every piece of data sent from the client has been manipulated". Treat Hyperion as
  defence-in-depth only.

**Sources:**
- `CD/scripting/security/{security-tactics, client-server-boundary, access-control, network-ownership,
  server-side-detection, defensive-design}.md`;
- `CD/reference/engine/classes/Players.yaml` (`BanAsync`);
- `openapi.json`.

**Confidence:** High for the docs content; Low-Medium for Hyperion specifics.

---

### F10. Content maturity, age guidelines, war themes

**Labels:**

| Label | Meaning (from the docs) |
|---|---|
| **Minimal** | Occasional mild violence and/or light unrealistic blood |
| **Mild** | **Repeated mild violence**, heavy unrealistic blood, mild fear, mild crude humor |
| **Moderate** | Moderate violence, light realistic blood, moderate fear, moderate crude humor, unplayable gambling |
| **Restricted** | Strong violence, heavy realistic blood, romance, alcohol, strong language. 18+ age-verified only. Unplayable in KR, SA and TR |

**Violence intensity:**
- **Mild:** "implied or unrealistic depictions of violence, such as bodies disappearing the moment their health reaches zero".
- **Moderate:** "non-graphic, realistic-looking depictions of violence and/or death".
- The consequence decides the rating: **a single realistic consequence moves the game up to Moderate.**
- Frequency is **Occasional** or **Repeated** (repeated if even one part repeats).

**Prohibited regardless of label:** "the depiction, support, or glorification of **war crimes** or human rights
violations".

**Sensitive issues** (must be disclosed if they are the **primary theme**, then 16+ only):
- Polarizing current political or social issues.
- "Guns in a first-person shooter" do **not** count.
- A fictional-faction tank game is not a sensitive issue. A game themed on a specific real current conflict likely would be
  (inference, Medium).

**Other questionnaire items:**
- paid random items and paid item trading (with the PolicyService questions);
- media sharing and feeds;
- generative-AI interaction;
- social hangout and free-form creation (16+).

Retake the questionnaire whenever the content changes. Without a questionnaire, playability is restricted.

**Audience tiers (2026):**
- Minimal/Mild reach **Roblox Kids (5–8)** and **Roblox Select (9–15)**.
- Moderate reaches **Select** and **16+**.
- Restricted is **18+**.
- Reaching under-16s requires:
  - an age-checked creator, ID verification (18+) or facial age estimation (under 18), and **2FA**;
  - a **1,000 R$ refundable publishing fee** **or** 2 consecutive months of Plus/Premium. The refund terms conflict in the
    docs (corrected by fact-check): `publish-games-and-places.md` says the fee is refunded if the game keeps **25 highly
    engaged players for 60 days**, while the `kids-and-select.md` FAQ says it is refunded **automatically 90 days after the
    game becomes eligible** (or 90 days after payment if it never does). Either way it is lost on permanent moderation.
    The optional **50,000 R$** expedited review is refundable on request after 90 days;
  - an **evaluation**: trial with age-checked 16+ users, then **250 unique plays by highly-engaged age-checked users within
    60 days**, plus a safety review.
- Progress is shown on the **Audience Reach** dashboard.

**Assets:** realistic violence or gore in uploaded images or meshes can be moderated regardless of label.

**Genre taxonomy:** relevant options are *Shooter → Deathmatch Shooter / PvE Shooter* and *Simulation → Vehicle Sim*.

**Sources:**
- `CD/production/promotion/content-maturity.md`, `experience-guidelines.md`;
- `CD/production/publishing/kids-and-select.md`, `publish-games-and-places.md`, `experience-genres.md`.

**Confidence:** High, except the publishing-fee refund condition (Medium: the two docs pages disagree).

**Not verifiable this session:** the exact Community Standards text on real-world extremist symbols and historical military
insignia. The help center is proxy-blocked. **[prior knowledge]** Hate and extremist symbols (for example Nazi
iconography) are prohibited. Use only original faction insignia.

---

### F11. Open Cloud (asset pipeline and admin tools)

**Auth and operations:**
- API keys go in the `x-api-key` header. Keys are user- or group-owned.
- Options per key: CIDR IP allow-lists (**not** when the key is used from Roblox servers) and an expiry.
- Docs recommend a dedicated alt account for group automation.
- OAuth 2.0 is the third-party alternative.
- On HTTP 429, honour `retry-after`, else back off exponentially.
- Rate limits are applied across **all keys of an owner**.

| Purpose | Endpoint | Scope | Limit |
|---|---|---|---|
| Upload asset | `POST https://apis.roblox.com/assets/v1/assets` (multipart: `request` JSON `{assetType, displayName, description, creationContext:{creator:{userId|groupId}}}` + `fileContent`) | `asset:read`, `asset:write` | **120/min**, BETA |
| Poll upload | `GET /assets/v1/operations/{operationId}` → `done`, `response`, `moderationResult.moderationState` | same | 300/min |
| Update or rollback asset | `PATCH /assets/v1/assets/{id}` (content: **FBX only**; metadata via `updateMask`), `POST …/versions:rollback` | same | 120/min, 100/min |
| Asset permissions | `PATCH /asset-permissions-api/v1/assets/permissions` | — | 100/min |
| Publish place | `POST /universes/v1/{universeId}/places/{placeId}/versions?versionType=Published\|Saved` (`.rbxl` octet-stream or `.rbxlx` XML) → `{versionNumber}` | `universe-places:write` | **30/min**. Spec `x-roblox-size-limit` = **10,485,760 bytes** |
| Data stores v2 | `/cloud/v2/universes/{u}/data-stores/{ds}/entries[/{id}]` (+ scopes, `:increment`, `:listRevisions`, `:snapshot`) | `universe-datastores.objects:{read,create,update,delete,list}`, `.versions:list`, `.control:{list,delete,snapshot}` | **Shares the in-game experience budget** (F6) |
| Ordered data stores v2 | `/cloud/v2/universes/{u}/ordered-data-stores/{ods}/scopes/{s}/entries…` | `universe.ordered-data-store.scope.entry:{read,write}` | as above |
| Memory stores v2 | `/cloud/v2/universes/{u}/memory-store/queues/{q}/items` (`:read`, `:discard`), `/sorted-maps/{m}/items[/{id}]`, `memory-store:flush` | `memory-store.queue:{add,dequeue,discard}`, `memory-store.sorted-map:{read,write}`, `memory-store:flush` | Counts toward MemoryStore RU |
| Messaging | `POST /cloud/v2/universes/{u}:publishMessage` | `universe-messaging-service:publish` | 5,000/min |
| Restart servers | `POST /cloud/v2/universes/{u}:restartServers` | `universe:write` | 30/min |
| Bans | `/cloud/v2/universes/{u}/user-restrictions[...]` | `universe.user-restriction:{read,write}` | 150/s per key owner; per universe: update 10/s, get/list 50/s; ≤ 2 updates/min per user (corrected by fact-check) |
| Luau execution (CI tests in a real server) | `POST /cloud/v2/universes/{u}/places/{p}[/versions/{v}]/luau-execution-session-tasks` | `universe.place.luau-execution-session:write` | **5/min** |
| Server list and logs | `GET /server-management/v1/universes/{u}/places/{p}/versions/{n}/game-servers[/{jobId}/logs]` | `universe:read` | 100/min, BETA |
| Products and passes admin | `/developer-products/v2/universes/{u}/developer-products…`, `/game-passes/v1/universes/{u}/game-passes…` | `developer-product:*`, `game-pass:*` | 3–10/s, BETA |
| Secrets | `/cloud/v2/universes/{u}/secrets` | `universe.secret:{read,write}` | 120/min |

**Upload limits:**
- One asset per call, **≤ 20 MB**.
- **Audio:**
  - `.mp3`, `.ogg`, `.wav` or `.flac`; ≤ **7 min**; sample rate ≤ **48 kHz**; mono, stereo, 3.0 or 5.1;
  - not updatable (a new ID for each version).
  - Quota is **inconsistent in the docs**. `usage-assets.md` says 100 uploads/month ID-verified and 10 unverified.
    `audio/assets.md` says **2,000 per 30 days verified, 100 unverified**. Plan for the lower figure.
- **Images/Decals:** png, jpeg, bmp or tga, < 8000×8000, not updatable.
- **Models:** fbx, gltf, glb, rbxm or rbxmx, uploaded as packages.
- **Video:** ≤ 5 min, ≤ 4096×2160, ≤ 3.75 GB, 20/day (13+ and ID-verified).
- Uploads enter **moderation**.

**Privacy:**
- Asset Privacy applies only to **Images, Decals and Meshes**: opt in to make them "Restricted" by default. **Open Use is
  irreversible.** Game grants are permanent.
- Audio, Video, Models and Animations have their own defaults. Audio is private to the uploader until access is granted to
  games or friends.
- Your own assets always work in your own games.
- Audio is auto-classified as SFX or song. Songs can appear on the game page if eligible.

**Place size context (added by fact-check):** Studio supports places up to **100 MB (104,857,600 bytes)**
(`CD/includes/place-size-limit.md`). The **10,485,760-byte** `x-roblox-size-limit` applies only to the Open Cloud publish
endpoint (also in `CD/reference/cloud/universes-api/v1.json`), so a place between 10 MiB and 100 MB can still be published
from Studio, but not by our CI.

**Place publishing limitations:** the API does not update `EditableImage`, `EditableMesh`, `PartOperation`,
`SurfaceAppearance` or `BaseWrap`. Publish those from Studio.

**Sources:**
- `CD/cloud/guides/usage-assets.md`, `usage-place-publishing.md`;
- `CD/cloud/reference/rate-limits.md`, `scopes.md`;
- `CD/cloud/auth/api-keys.md`;
- `CD/cloud/guides/data-stores/throttling.md`;
- `CD/audio/assets.md`;
- `CD/projects/assets/privacy.md`;
- `CD/reference/cloud/openapi.json`.

**Confidence:** High, except the audio quota conflict.

---

### F12. Platform facts that size our servers

**Server memory:** **6.25 GiB + 100 MiB × peak connected players**. It never shrinks while running. Keep usage
**< 50%** (`identify.md`).
- 30 players: about 9.18 GiB.
- 50 players: about 11.13 GiB.

**`Players.MaxPlayers`:** set per place in Creator Dashboard. Read-only in scripts.

**`Players.CharacterAutoLoads = false`:** `StarterGui` is **not copied** into `PlayerGui` until `LoadCharacterAsync`. In a
character-less battle, UI must be created by client scripts (`PlayerGui.yaml`).

**Experience Configs (`ConfigService`):**
- Server-only. `GetConfigAsync()` / `GetConfigForPlayerAsync()` return **snapshots**, which do not auto-update. That is
  ideal for "change between battles".
- Limits:
  - string and JSON ≤ **100,000 chars**;
  - **100 conditions per game**, 20 per key;
  - publish in about **15 s – 1 min** (or a gradual 15 min).
- Studio `SetTestingValue`. Publish-as to another universe (staging → live).

**MatchmakingService:**
- Engine matchmaking for **public** servers only (custom attributes and signal weights). It excludes reserved servers.
- Useful only for Hub server selection (for example by language or latency).

**HttpService:** 500 external requests/min per server, plus a separate 2,500/min per server for Open Cloud calls
(corrected by fact-check; see F1.4 for the docs conflict).

**Sources:**
- `CD/performance-optimization/identify.md`;
- `CD/reference/engine/classes/{Players, PlayerGui, ConfigService, MatchmakingService}.yaml`;
- `CD/production/configs.md`;
- `CD/matchmaking/index.md`.

**Confidence:** High.

---

## Implementation recommendations for HULLDOWN (Roblox)

### R1. Universe and place layout

| Place | Type | Access | MaxPlayers | Key settings |
|---|---|---|---|---|
| **Hub** (start place) | Public servers | Start place | **50** (OUR DESIGN CHOICE: about 11.1 GiB server memory. UI-centric garage, so CPU is light) | `CharacterAutoLoads = false` (garage is UI + client-built 3D scene; removes all character exploits). **StreamingEnabled = false**, or on only with a server-set `Player.ReplicationFocus` on a static garage anchor Part (corrected by fact-check: with no character there is no `PrimaryPart` to stream around, see F3; hub positions are not secret, so the focus Part is harmless here). Hosts profiles, store, receipts, queue, matchmaker leader |
| **Battle_<MapId>** (one place per map, or per map group) | **Reserved servers only** | **Secure within universe only** | **32** (30 + 2 slack) | `CharacterAutoLoads = false`. **StreamingEnabled = false** (v1, see R8). Map authored statically in Workspace. No purchase prompts. `ExperienceShop` CoreGui hidden |
| Dev / staging | **Separate private universe** | — | — | Docs: the only reliable confidentiality for unreleased content |

**Reasons for the layout:**
- **One battle place per map** avoids cloning a large map at runtime ("creation of complex instance trees … very network
  intensive").
- It keeps each `.rbxl` small. The Open Cloud place-publish spec caps uploads at 10,485,760 bytes; multi-map places risk
  hitting it.
- It allows per-map tuning.
- `Shared/Config/Places.luau` maps every Battle placeId to `{role = "Battle", mapId}`.

**Settings checklist:**
- Creator Dashboard → Access Control for Places = **Secure within universe only**.
- Studio → Security → **Allow Third Party Teleports = off**.
- Enable Studio access to API services for dev only.
- `Players.BanningEnabled = true` in every place. It is `NotScriptable`, so set it in Studio's Players properties.

### R2. Networking contract

- Keep the ARCHITECTURE registry. Add the **per-remote budgets** below (token bucket = `rate/s`, `burst`).
- Violations go to `AntiExploitService:strike`.
- The engine's ~500/s shared limit is a ceiling, not a control.

| Remote | Kind / direction | Payload | Rate (rate/s, burst) |
|---|---|---|---|
| `InputPacket` | Unreliable C2S | buffer ≤ 64 B (seq u16, last 3 inputs: throttle i8, steer i8, aim yaw/pitch quantised i16 ×2, flags u8) | 40/s, 60 (sent at 30 Hz) |
| `SnapshotPacket` | Unreliable S2C, `FireClient` per observer | buffer ≤ **900 B** (split into numbered parts if larger) | sent at 20 Hz |
| `FireRequest` | Reliable C2S | `{seq, aimHint}` | 6/s, 8. Server enforces reload anyway |
| `ConsumableRequest` / `AmmoSwitch` / `ModuleRepair` | Reliable C2S | small enum ids | 4/s, 6 |
| `QuickCommand` / `MapPing` | Reliable C2S → team S2C | enum + quantised XZ | **1/s, 3**, plus **12/min** cap |
| `QueueJoin` / `QueueLeave` | Reliable C2S | `{requestId, vehicleId, mode}` | 1/s, 3 |
| `GarageTransaction` (buy, research, mount, etc.) | Function C2S | `{requestId, op, args}` | 5/s, 10. Idempotent by `requestId` |
| `PlatoonInvite` / `PlatoonRespond` | Reliable C2S | userId / inviteId | 0.2/s, 3 |
| `ReportPlayer` | Reliable C2S | userId + enum | 1/30 s, 2 |
| `SettingsSave` | Reliable C2S | ≤ 2 KB table | 0.1/s, 2 |
| Honeypot remotes (2–3, plausible names) | — | — | any call means a high-confidence flag |

**Snapshot budget (OUR DESIGN CHOICE):**
- Own vehicle: about 40 B.
- Allies: 14 × about 20 B.
- Spotted enemies: up to 15 × about 20 B.
- Header: about 12 B.
- Worst case: about 630 B × 20 Hz ≈ **13 KB/s** S2C per client.
- Add reliable events. **Target ≤ 20 KB/s average and ≤ 40 KB/s peak S2C per client, and ≤ 3 KB/s C2S.** This is well
  under the (unverified) 50 KB/s folk ceiling.
- Measure **data ping vs network ping** in live servers. A sustained gap > 100 ms means we are over-producing.
- Validate every C2S argument:
  - type;
  - finite numbers (`math.isfinite`);
  - ranges (inputs ∈ [−1, 1]);
  - string length ≤ 40 for `requestId`;
  - table size and depth caps;
  - no Instances, except validated `IsDescendantOf` checks.
- Never call `InvokeClient`. `NetClient.invoke` has a 10 s client-side timeout.

### R3. Matchmaking pipeline over MemoryStore (OUR DESIGN CHOICES with documented limits)

**Data structures:**

| Name | Structure | Key | Value (≤ 32 KB) | TTL |
|---|---|---|---|---|
| `mmq:<mode>:<tierBand>:<mmType>` | **SortedMap** (one per bucket, so one partition each) | `ticketId` | Compact ticket JSON ≤ 600 B: `{v, members, platoonId, vehicle:{defId, tier, class}, hubJobId, enq, state:"Q"}` | 600 s (the hub refreshes the TTL every 120 s while queued, using `UpdateAsync` that returns `nil` unless `state == "Q"`, never `SetAsync`, which could overwrite a claim; corrected by fact-check) |
| `mm` | **HashMap** | `lease` | `{holder=JobId, term=GUID}` | **15 s** |
| `mm` | HashMap | `asg:<ticketId>` | `{matchId, placeId, code, psid, team}` | 180 s |
| `match` | HashMap | `<privateServerId>` | **Manifest ≤ 8 KB**: `{matchId, mode, mapId, placeId, mmType, createdAt, term, roster:[{u, team, ticket, loadout}], botSeed, botSlots}` | 1,800 s; replaced by a tombstone `{ended=true}` (TTL 7,200 s) at battle end |

`mmType` = `game.MatchmakingType` of the hub (F5 cross-play trap). Never mix types.

**Flow:**
1. **Enqueue (Hub).**
   - Validate the request (vehicle owned, repaired, not locked in a battle).
   - `SortedMap:SetAsync(ticketId, ticket, 600, sortKey = enqueueMillis)`.
   - Store the ticket in the hub's memory.
   - Platoons form **one** ticket.
2. **Leader lease.**
   - Each Hub server runs `HashMap:UpdateAsync("lease", fn, 15)` every **5 s** while it holds the lease, or every
     **10 s ± 3 s jitter** when it does not.
   - `fn(old)`:
     - if `old == nil` (expired), return `{holder = JobId, term = HttpService:GenerateGUID(false)}`;
     - if `old.holder == JobId`, return `old` (renewal);
     - otherwise return `nil`.
   - The item TTL is the expiry, so no cross-server clock compare is needed.
   - A numeric epoch cannot stay monotonic across TTL expiry, so `term` is a fresh GUID per acquisition. It is used for
     audit and logs only. Correctness comes from the per-ticket claims in step 3.
   - Leader cost is about 24 RU/min. Each contender costs about 12 RU/min.
3. **Match tick (leader, every 3 s).**
   - For each non-empty bucket, page `GetRangeAsync(Ascending, 200)`. This costs RU = tickets.
   - Run the pure `Matchmaker`.
   - For each formed match, **claim each ticket** with `SortedMap:UpdateAsync(ticketId, fn, 600)` (corrected by
     fact-check: `expiration` is required). `fn(old, oldSortKey)` returns `nil` unless `old.state == "Q"`; otherwise it
     sets `state = "M"` plus `matchId` and returns `(new, oldSortKey)` so the ticket keeps its sort key.
   - If any claim fails (cancelled, or claimed by an overlapping leader), roll back the claimed ones to `"Q"` and drop the match.
4. **Reserve and manifest.**
   - `ReserveServerAsync(battlePlaceId)` returns `(code, psid)`.
   - Write the manifest `match:<psid>`, including the leader `term`.
   - Write `asg:<ticketId>` for each ticket.
   - `RemoveAsync` the claimed tickets from the bucket.
5. **Notify.**
   - Publish one MessagingService message per hub, on topic `"hub:" .. hubJobId`, carrying the ticket ids (≤ 1 kB).
   - Hubs **also poll** `asg:<ticketId>` every 3 s for their queued tickets. MessagingService is best effort.
6. **Teleport (each hub).**
   - Call `TeleportAsync(placeId, playersOfThisHub, opts{ReservedServerAccessCode = code})` in batches of ≤ 50.
   - TeleportData carries `{matchId}` only, as a hint.
   - On `TeleportInitFailed`, retry with the supplied options:
     - `Failure`: up to 3 attempts, 1 s apart;
     - `Flooded`: wait 15 s;
     - anything else: give up.
   - On final failure, write `match:<psid>:noshow:<userId>` (or rely on the battle's join timeout), un-lock the vehicle and
     re-queue the player at the front (`sortKey = original enq`).
7. **Cancel (Hub).** `SortedMap:UpdateAsync(ticketId, fn, 60)`: if `state == "Q"`, set `state = "C"` atomically, then
   `RemoveAsync(ticketId)`; otherwise report "already matched". (Corrected by fact-check: a transform cannot delete, and a
   separate check-then-`RemoveAsync` would race with the leader's claim. A `"C"` ticket can never be claimed in step 3.)

**Wait-time relaxation and bot fill** live in the pure algorithm (ARCHITECTURE §8).

**Budget check (corrected by fact-check):** the original figures paired 200 queued tickets with CCU = 100 and 100 tickets
with 50 CCU. Queued tickets can never exceed hub players, which are fewer than CCU. The original total also counted the
`asg:` polls at about 2,000 RU/min when they cost as much as the scans.
- **CCU = 100** (1,000 + 120 × 100 = 13,000 RU/min): at most about 100 queued tickets.
  - Scans: 100 × 20/min = 2,000.
  - `asg:` polls: 100 tickets × 20/min = 2,000.
  - Lease, TTL refreshes, claims, removes and `asg:` writes: about 400.
  - Total **≈ 4,400 RU/min (about 34%)**.
- **200 queued tickets** needs CCU ≥ about 200 (≥ 25,000 RU/min). Scans 4,000 + polls 4,000 + about 800 gives
  **≈ 8,800 RU/min (about 35%)**.
- Per-partition: the busiest bucket at 200 tickets × 20 scans/min = 4,000 RU/min, far below 30k.
- **Empty buckets still cost RU.** `GetRangeAsync` bills at least 1 RU per call. With, for example, 45 buckets (modes ×
  tier bands × `mmType`s) scanned every 3 s, empty scans alone cost 900 RU/min. That is about 41% of the 2,200 RU/min
  quota at CCU = 10. Keep a small HashMap index of non-empty buckets, or scan rarely-used buckets less often.
- **Memory at 50 CCU is only about 124 KB.** Example usage: 2 live manifests × 8 KB + at most 50 tickets × 0.6 KB +
  assignments ≈ **55 KB**. Hence the 8 KB manifest cap, short TTLs, and explicit removal.
- Below about 30 CCU, cut the scan to every 5 s and prefer bot-filled battles.

### R4. Battle handoff and manifest validation

On Battle server start:
1. `psid = game.PrivateServerId`.
   - If it is empty, or `PrivateServerOwnerId ~= 0`, this is not a reserved battle: send everyone to the Hub.
2. Read `match:<psid>`, retrying with backoff for up to 30 s.
   - If it is missing, or `ended == true`, this is a **stale-code restart** (codes never expire): teleport arrivals back to the Hub.
3. Check `game.MatchmakingType == manifest.mmType`. Otherwise bounce the player (a cross-play split instance).
4. **Admit only roster UserIds.** Kick others before any gameplay replication; the map content is non-secret.
   `GetJoinData().SourcePlaceId` must be a Hub placeId.
5. Join window: **60 s** (OUR DESIGN CHOICE). Then missing slots become bots (`botSeed`). The battle starts with a 30 s countdown.
6. Reconnect:
   - The Hub's profile keeps `activeBattle = {psid, code, placeId, battleId, until}`.
   - The Hub's "Return to battle" teleports with the same code while the manifest is not ended.
7. End of battle:
   - Compute results.
   - Write reward inboxes (R6) **before** teleporting players back.
   - Set the tombstone `{ended = true}`.
   - Show results for 10 s, then `TeleportAsync(hubPlaceId, players)` (≤ 50/call).
8. `BindToClose`: if the battle is still running, award "battle aborted" consolation inboxes, using the 30 s budget.

Never read gameplay facts from TeleportData.

### R5. Profiles and session locking

Adopt the ProfileStore model, matching ARCHITECTURE "ProfileStore-style", with these constants (OUR DESIGN CHOICES):

| Constant | Value | Reason |
|---|---|---|
| Store / key | DataStore `Profiles_v1`, key `Player_{UserId}` | RTBF template-compatible. Name and key ≤ 50 chars |
| Lock location | `MetaData.ActiveSession = {placeId, jobId, sessionGuid, at}` inside the value | Visible in Data Stores Manager. Proven by ProfileStore |
| Autosave | **60 s ± random(0, 60) first offset** | Within budget: writes ≈ CCU/min vs **250 + 20 × CCU/min** experience-wide (the lower documented variant, per F6.1; corrected by fact-check, was 300 + …). A hub with 50 players uses about 50 of its **2,060/min** `StandardWrite` budget (60 + 40 × 50); each `UpdateAsync` also spends one `StandardRead` |
| Stale lock ("assume dead") | **300 s** (5 × autosave) | ProfileStore uses 630 s with a 300 s autosave |
| Conflict handling | Poll at 5 s, then every 10 s. Send a MessagingService release ping to `"ps:" .. sessionGuid`. **Steal after 40 s** | Safe: every save re-verifies `sessionGuid` in `UpdateAsync`, so a stolen-from server's later writes abort. That server must kick its copy |
| Load failure | Kick with message after `START_SESSION_TIMEOUT = 120 s`. Never play on default data | ARCHITECTURE §7 |
| Writes | All through `UpdateAsync`, with a per-key serial queue and backoff (2 s base, 32 s cap, 5 attempts, jitter). Pass `{userId}` as userIds | `player-data-purchasing.md` |
| BindToClose | Parallel final saves, skip stale queued writes, **25 s** budget (engine 30 s) | ARCHITECTURE §5.1 |
| Size | Profile ≤ **200 KB** JSON; alert at 1 MB (hard limit 4 MB) | Per-key 4 MB/min write throughput is ample |
| Budget awareness | Before non-critical writes, check `GetRequestBudgetForRequestType(StandardWrite)`. Defer if it is < 10 | — |

**Battle servers never open profile sessions.** Everything they need is in the manifest. This removes all lock churn on
teleports.

### R6. Reward idempotency (battle results)

**Inbox pattern (OUR DESIGN CHOICE).** A player who leaves a battle early is back in the Hub, which holds the lock, so the
battle server cannot write the profile directly.
- DataStore `RewardInbox_v1`, key `u_{UserId}` (RTBF template).
- Value: `{entries = [{battleId, issuedAt, rewards: {xp, credits, crewXp, freeXp, ...}, stats}]}`, capped at 20 entries.
- Battle server end: `UpdateAsync` appends the entry to each human's inbox.
  - That is 30 writes per battle, against a battle-server budget of 60 + 40 × 30 = **1,260/min**.
  - It is a no-op if the `battleId` is already present.
- Hub consumer, on profile load and every 30 s while `profile.pendingBattles` is non-empty:
  1. `UpdateAsync` reads the inbox fresh (no 4 s cache issue).
  2. For each entry with `battleId ∉ profile.processed.battles` (ring of the last **200**), apply `RewardService`, add the
     `battleId` to the ring, and clear `pendingBattles[battleId]` and the vehicle lock.
  3. **Save the profile**, then remove the consumed entries from the inbox.

  A crash between steps is safe: the ring makes a re-apply a no-op.
- The vehicle lock set at assignment carries `until = now + 30 min`. After that, unlock with no rewards (crashed battle).
- Optional speed-up: the battle server publishes `{battleId}` on topic `battle-ended`. Hubs that hold affected players poll
  immediately.

### R7. Purchases and monetization decisions

**Receipts:**
- Use **`BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, handler)`** as a catch-all in the **Hub only**.
- Keep a `ProcessReceipt` fallback that returns `NotProcessedYet`.
- In Battle places, bind a handler that **always returns `NotProcessedYet`**, so the receipt is redelivered on the next join
  to the Hub. Also hide `ExperienceShop`.
- Handler, in order:
  1. Wait for the profile to load. Stop if the player leaves.
  2. If the `PurchaseId` is in `processed.receipts` (ring of **100**) and saved, return `Processed`.
  3. Grant through the `Transactions` function.
  4. Record the `PurchaseId`.
  5. Force-save via `UpdateAsync`.
  6. Return `Processed` on success, `NotProcessedYet` otherwise.

**Prices:** show every price via `GetProductInfoAsync` / `GetDeveloperProductsAsync` **on the client**. Managed Pricing is
on by default. Never hard-code R$ in the UI.

**Product catalogue (OUR DESIGN CHOICE; price points to be tuned with price optimization once at 60k transactions/30 d):**
- Premium-currency packs ("Gold") as developer products: 49, 99, 249, 499, 999, 1,999 R$, with bonus percentages rising
  with size.
- **HULLDOWN Premium** as a **Robux subscription** (≥ 49 R$; for example 149–249 R$/month). It plays the WoT
  premium-account role (+50% XP/credits). Identical on every platform, with no tiers.
- Optional passes for permanent conveniences (extra garage slots pack, crew-skill reset discount). **No gameplay power for
  Robux beyond WoT-equivalent premium vehicles.**
- **No paid random items** (no crates bought with Gold). This avoids odds disclosure and `ArePaidRandomItemsRestricted`
  branches, and keeps the questionnaire clean.
- **No trading.**
- Still call `PolicyService:GetPolicyInfoForPlayerAsync` on join. Gate subscription prompts on
  `IsEligibleToPurchaseSubscription`, and immersive ads (if added) on `AreAdsAllowed`.
- Consider `PromptRobloxSubscriptionPurchase` (Roblox Plus referral, up to 750 R$ per conversion) from a non-intrusive
  store tile.

### R8. Maps, streaming and spatial queries

**Battle places: `StreamingEnabled = false` (v1).** Reasons:
- no character, so streaming would need a server `ReplicationFocus` Part, which would leak positions (F3);
- client prediction and sniper LOS need full map geometry;
- the map is static and non-secret.

**Budgets (OUR DESIGN CHOICE, verify on a baseline 3–4 GB phone):**
- ≤ **25,000 BaseParts** per map;
- ≤ **150 unique MeshParts**;
- built-in materials preferred;
- crash rate < 2–3% (docs threshold).

**If the memory budget fails, Option B:**
- `StreamingEnabled = true`, `ModelStreamingBehavior = Improved`, `StreamingMinRadius = 512`,
  `StreamingTargetRadius = 2048`, `StreamOutBehavior = LowMemory`.
- Map chunks as **Atomic** models. SLIM on large structures.
- `Player.FrustumStreaming = Automatic` (server-set) for sniper zoom.
- Use it **only if** an in-engine test shows a `ReplicationFocus` Part held in a non-replicated container still drives
  streaming. Otherwise use coarse 256-stud-grid focus parts and accept the coarse leak. Not recommended.

**Hub place:** `CharacterAutoLoads = false` leaves no character to stream around. Either set `StreamingEnabled = false`
(the garage scene is client-built anyway), or keep streaming with default radii **and** a server-set
`Player.ReplicationFocus` on a static garage anchor Part (corrected by fact-check; was "streaming on, default radii",
which contradicted F3 and R1).

**Client vehicle models:**
- Create them under a **client-created** `Workspace.ClientVehicles` Folder (never under server instances), so they never
  stream out.
- Anchored, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`.

**Server raycasts (`RobloxWorld` adapter):**
- Reuse one `RaycastParams` per mode, using **`IncludeInstances`** (not the superseded `FilterDescendantsInstances`):
  - **Shell:** `{Map.Solid, workspace.Terrain}`, `IgnoreWater = false` (shells stop in water);
  - **Ground:** `{Map.Solid, Terrain}`, `IgnoreWater = true` (depth via a second water cast);
  - **Sight:** `{Map.Solid, Terrain}` blocks. Foliage is handled by a separate `IncludeInstances = {Map.Foliage}` query
    accumulating concealment.
- Decor has `CanQuery = false`.
- Use `RaycastResult.Material` for terrain-type mobility and ricochet sounds.
- Per-tick cast budget at 30 Hz (OUR DESIGN CHOICE, to profile with the MicroProfiler):
  - about 120 ground samples (30 vehicles × 4);
  - ≤ 60 projectile segments (each ≤ 1,024 studs for blockcasts, ≤ 15,000 for rays);
  - about 15 staggered spotting LOS rays;
  - total **≤ 250 casts/tick**.
- `Raycast`, `Blockcast` and `Spherecast` are parallel-safe, so spotting LOS can move to an Actor (`task.desynchronize`) if needed.
- Do not use `Shapecast` there.

**WorldModel** in `ServerStorage` stays a fallback for non-replicated server geometry. Add a boot self-test (raycast
against a known part) before any use.

### R9. Social and chat

**Platoons:**
- Integrate **Roblox Parties**: on queue, if `player.PartyId ~= ""`, offer "Queue as platoon" with
  `SocialService:GetPlayersByPartyId`. Cross-server party members come from `GetPartyAsync`. Use their `JobId` or
  `ReservedServerAccessCode` to gather them.
- Keep our own hub-local platoon invites for non-party friends.

**Invites:**
- "Invite friends" button → `CanSendGameInviteAsync` → `PromptGameInvite` with `ExperienceInviteOptions`:
  - `InviteMessageId` (a localized Notification asset);
  - `LaunchData = "p:" .. platoonCode` (≤ 200 chars).
- The Hub reads `GetJoinData().LaunchData` and `ReferredByPlayerId`, which feed referral rewards.

**Battle chat:**
- Use `TextChatService` with Teams → `RBXTeam<Color>` channels are created automatically.
- `ShouldDeliverCallback` on `RBXGeneral` disables all-chat during the battle (WoT-like). Team chat only, plus system
  messages via `DisplaySystemMessage`.

**Quick commands and map pings:**
- Implement as a **preset system** (allowed for every age): "Attack!", "Defend base!", "Need help!", "Affirmative",
  "Negative", "Reloading", "Enemy spotted", plus a ping on a map grid square.
- Rate-limited at 1/s, burst 3, max 12/min.
- No free text and no combinable fragments.

**Custom text:**
- v1 has **no free text** besides Roblox chat. Platoon and loadout names are chosen from lists.
- If added later, apply `FilterStringAsync` on submit (author online) → `GetNonChatStringForBroadcastAsync`. Store the
  filtered string plus `authorId`. Rate limit 1/60 s.

### R10. Security checklist (delta to ARCHITECTURE §12)

1. "Secure within universe only". Dev content in a separate universe. Nothing unreleased in `Shared/Config` of production builds.
2. Server-only logic (matchmaker weights, anti-cheat heuristics, economy secrets) lives in `ServerScriptService`, never in
   `ReplicatedStorage/Shared`, which is decompilable.
3. Remote validation pipeline (type, finite, range, size, IsDescendantOf) with per-remote buckets (R2), plus honeypots and
   direction-misuse detection.
4. Heuristics in `AntiExploitService`:
   - fire cadence variance (macro);
   - impossible aim slew;
   - rate-of-gain per day (economy);
   - repeated idempotency-key reuse.

   Correlate into a suspicion score. Use the ladder: log → mitigate → restrict matchmaking → kick → `BanAsync`. Delay
   visible actions.
5. Characters disabled in both places, which removes the whole network-ownership class.
6. Rate limit every DataStore-touching request path. The engine's 30-deep queue (301–306 errors) must never be reachable
   from a client action.

### R11. Compliance: target label **Mild**

Questionnaire answers:

| Category | Answer |
|---|---|
| Violence | **Yes; Mild; Repeated**. Vehicles are destroyed with no human bodies; crew are "knocked out", never "killed" or depicted |
| Blood | **No** |
| Fear | No |
| Crude humor | No |
| Gambling | No |
| Strong language | No |
| Romance | No |
| Alcohol | No |
| Social hangout | No |
| Free-form creation | No |
| Sensitive issue | **No**: fictional factions; no real current conflict as theme |
| Paid random items | **No** |
| Paid item trading | **No** |
| Media sharing | No |
| Generative AI | No |

This makes HULLDOWN eligible for **Kids and Select**, which requires:
- an age-checked creator (government ID if 18+, facial age estimation if under 18) plus 2FA;
- the 1,000 R$ refundable fee or 2 months of Plus/Premium;
- passing the evaluation: a 16+ trial, 250 unique plays by highly-engaged age-checked users within 60 days, **and a
  safety review**. The label makes the game a candidate; it does not grant eligibility by itself.

**Art rules:**
- No real-world insignia or extremist symbols.
- No gore textures.
- Fire and smoke are fine.
- Retake the questionnaire on every content change.

**Genre:** Shooter → Deathmatch Shooter (team PvP), or Simulation → Vehicle Sim. Choose Shooter for discovery.

### R12. Open Cloud tooling

**`tools/upload_assets`:**
- Uses `POST /assets/v1/assets` with an **API key** (scopes `asset:read`, `asset:write`), group creator ID, and CI IP
  allow-list. The key belongs to a **dedicated automation account**.
- Polls `operations/{id}` until `done`, then records `moderationResult`.
- Client-side limit of ≤ 100 req/min, under the 120/min server limit.
- Audio: pre-transcode to **OGG ≤ 48 kHz**, stereo, ≤ 7 min.
- Budget about **100 audio uploads/month** (the lower documented quota). Batch SFX into fewer assets where possible.
- After upload, grant the asset to the universe (asset permissions API) so Hub and Battle places can load it.

**Place deploy:** `POST /universes/v1/{u}/places/{p}/versions?versionType=Published` per place from one Rojo build (30/min).
Assert each `.rbxl` < 10 MiB.

**Admin console (internal):**
- Data stores v2 (`universe-datastores.objects:read/update`) for support fixes. Never during the player's live session:
  check `MetaData.ActiveSession`.
- Memory store v2 for queue inspection and flush.
- `:publishMessage` for broadcast notices.
- `:restartServers` for hotfix rollouts.
- `user-restrictions` for bans.
- `server-management` logs (beta).

**CI:** optionally run headless smoke tests in a real server via **Luau Execution** (5 tasks/min).

**Live tuning:** move economy and matchmaking knobs to **Experience Configs**. Read a `ConfigSnapshot` at battle creation so
values never change mid-battle.

### R13. Required edits to `docs/ARCHITECTURE.md` (for the architecture owner)

1. §2.1: `ReserveServer` → **`ReserveServerAsync`** (deprecated API). Add the stale-code and `MatchmakingType` checks (R4).
2. §2.1: Battle places use **"Secure within universe only"** and `CharacterAutoLoads = false`. Note the `StarterGui`-not-copied gotcha.
3. §5.2: keep the 900 B cap; note that the docs now state 1,000 B. Add the per-remote budget table (R2). Note the
   RemoteEvent and attribute ordering caveat under `NextGenerationReplication`.
4. §6.4: `RobloxWorld` uses `RaycastParams.IncludeInstances` / `ExcludeInstances`.
5. §7 Data persistence: inbox-based reward delivery (R6). Battle servers do not open profile sessions. Lock stale after 300 s.
6. §12: receipts via `BindReceiptHandler` (Hub). The Battle place returns `NotProcessedYet`.
7. §8: MemoryStore memory quota (64 KB + 1.2 KB × users), so manifests ≤ 8 KB. Never mix `MatchmakingType`s.

---

## Open questions / uncertain items

1. **ReplicationFocus outside Workspace.** Does a `Player.ReplicationFocus` Part parented to `ServerStorage` (or
   `PlayerGui`) still drive streaming without replicating to others? Undocumented. It decides whether Option B in R8 is
   viable. Needs an in-engine test.
2. **Server-side `WorldModel` queries in `ServerStorage`.** Believed to work (Medium), not documented. Only needed if we
   move geometry off Workspace. Needs a boot self-test.
3. **Per-client bandwidth ceiling.** The docs give no KB/s figure. The 50 KB/s folk number is unverified. Our 20/40 KB/s
   target needs field telemetry: data ping vs network ping, and Shift+F3 network stats.
4. **UnreliableRemoteEvent size accounting.** It is unclear whether the 1,000-byte limit applies before or after the engine's
   compression of `buffer`s. Keep raw ≤ 900 B and measure drops in Studio Output. (Fact-check note: `UnreliableRemoteEvent.yaml`
   says encoding and compression "shrinks the payload size and can make it difficult to verify whether you are under
   the limit prior to firing". That implies the check runs on the encoded payload, but it is not stated outright.)
5. **Conflicting doc numbers:**
   - DataStore experience limits: 300 + … (limits page) vs 250 + … (Extended Services page);
   - storage: 500 MB vs 100 MB base;
   - Open Cloud audio upload quota: 100/month vs 2,000/30 days;
   - in-game Open Cloud calls: separate 2,500/min (`HttpService.yaml`, `http-service.md`) vs counted in the 500/min HTTP
     budget (`rate-limits.md`) (added by fact-check);
   - Kids/Select publishing-fee refund: 25 highly engaged players for 60 days vs automatic after 90 days (added by
     fact-check).

   Design to the lower figures. Re-check on the live docs.
6. **Place publish size.** The `openapi.json` `x-roblox-size-limit` is 10,485,760 bytes. The fact-check confirmed it is
   endpoint-specific: Studio's documented place limit is 100 MB. Verify with a real Open Cloud upload of the largest map
   place.
7. **Reserved-server idle shutdown delay** and **max concurrent reserved servers** are undocumented. Instrument them
   (server-management API, beta).
8. **Hyperion coverage per platform** (Mac, mobile, console) and the 2025–26 changes could not be re-verified (web budget
   exhausted). This does not change our design, which treats every client as compromised.
9. **Server Authority GA date.** Still "beta" in the docs. Re-evaluate for cosmetic or friendly-only prediction when it
   ships, without breaking per-observer secrecy.
10. **Community Standards text on military themes and real insignia.** The help center is proxy-blocked. Have a human
    review it before the first public build.
11. **Robux price norms** for currency packs and subscriptions in the tank/shooter genre: no verified benchmark. Rely on
    Managed Pricing tests once volume reaches about 60k transactions per 30 days.
12. **Kids/Select evaluation for a PvP shooter.** It is unclear whether the safety review treats realistic-looking (but
    bloodless) tanks as Mild. Get a human read of the Mild vs Moderate examples before launch. The fallback is the
    Moderate label (Select 9–15 and 16+ only).

---

## Verification log

Adversarial fact-check run on 2026-10-05. Every claim was treated as wrong until it was confirmed against the local
creator-docs snapshot (commit `9f840b17`, 2026-10-02; `CD/` = `creator-docs/content/en-us/`) or the primary source on
GitHub. WebSearch was unavailable (session budget exhausted), so items with no local or GitHub source stay
**Unverified**.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | `UnreliableRemoteEvent` drops payloads > 1,000 bytes. Both remote types are throttled at ≈ 500 req/s per client, shared across all instances of the same type. Reliable sends over the limit are delayed, unreliable ones dropped | Confirmed | `CD/reference/engine/classes/UnreliableRemoteEvent.yaml` ("payloads larger than 1000 bytes are dropped"); `RemoteEvent.yaml` "Throttling"; `CD/scripting/events/remote.md` "Delivery guarantees" |
| 2 | `Raycast` ≤ 15,000 studs. `Blockcast` size ≤ 512, `Spherecast` radius ≤ 256, cast distance ≤ 1,024. `Raycast`/`Blockcast`/`Spherecast` are thread-safe, `Shapecast` is not. `RaycastParams.ExcludeInstances`/`IncludeInstances` supersede `FilterDescendantsInstances`/`FilterType`, and exclusions win | Confirmed | `CD/reference/engine/classes/WorldRoot.yaml` (`thread_safety: Safe/Unsafe` per method); `CD/reference/engine/datatypes/RaycastParams.yaml` |
| 3 | `StreamingMinRadius` defaults to 64 and `StreamingTargetRadius` to 1,024. `Player.FrustumStreaming` (`Default`/`Disabled`/`Automatic`/`Enabled`) is server-only. `ReplicationFocus` defaults to the character's `PrimaryPart` | Confirmed | `CD/reference/engine/classes/Workspace.yaml`; `CD/workspace/streaming/index.md`, `frustum.md`; `CD/reference/engine/classes/Player.yaml`; `CD/reference/engine/enums/FrustumStreamingMode.yaml` |
| 4 | MemoryStore limits: memory 64 KB + 1.2 KB × users; 1,000 + 120 × CCU RU/min; value ≤ 32 KB; key and sort key ≤ 128 chars; expiry ≤ 3,888,000 s; ≤ 1 M items and 100 MB per structure; ~30k RU/min per partition; hash-map key ~5k write and 15k read RU/min; `GetRangeAsync` ≤ 200; `ReadAsync` ≤ 100 | Confirmed | `CD/cloud-services/memory-stores/index.md`, `sorted-map.md`, `hash-map.md`, `per-partition-limits.md`; `MemoryStoreSortedMap.yaml`, `MemoryStoreQueue.yaml` |
| 5 | R3 ticket claim and cancel called as `SortedMap:UpdateAsync(ticketId, fn)` | **Corrected** | The `expiration` parameter is required. The transform takes and returns `(value, sortKey)`. Cancel needs an atomic state flip before `RemoveAsync`. `CD/reference/engine/classes/MemoryStoreSortedMap.yaml` (`UpdateAsync` parameters) |
| 6 | MessagingService: message 1 kB; 600 + 240 × players/min sent per server; 40 + 80 × servers/min per topic; 400 + 200 × servers game-wide; 20 + 8 × players subscriptions; 240 subscribe requests/min; best effort, 1–2 s | Confirmed | `CD/reference/engine/classes/MessagingService.yaml` |
| 7 | `ReserveServer` is deprecated in favor of `ReserveServerAsync`, which returns `(accessCode, PrivateServerId)`. Codes stay valid indefinitely. `TeleportAsync` takes ≤ 50 players. Cross-play splits share one `PrivateServerId` (check `MatchmakingType`). `GetJoinData` teleport data is guaranteed only within 48 h, and sensitive data should travel via MemoryStore | Confirmed | `CD/reference/engine/classes/TeleportService.yaml` (`ReserveServer` tagged Deprecated; `TeleportAsync` "Group Teleport Limitations"); `DataModel.yaml` (`MatchmakingType`); `Player.yaml` (`GetJoinData`); `CD/reference/engine/enums/TeleportResult.yaml`; `CD/projects/teleport.md` |
| 8 | DataStore limits: value 4,194,304 chars; name, key and scope 50 chars; metadata 300; per key 25 MB/min read and 4 MB/min write; per server 60 + 40 × players (Read/Write/Remove) and 5 + 2 × players (List); experience-wide 300 + 40 × CCU read and 300 + 20 × CCU write; queues 30 deep (301–306); `GetAsync` cache 4 s; versions kept 30 d; storage 500 MB + 1 MB × lifetime users; `BindToClose` 30 s | Confirmed (the 250 + … Extended Services variant also confirmed, so the conflict stands) | `CD/cloud-services/data-stores/error-codes-and-limits.md`, `versioning-listing-and-caching.md`; `CD/cloud-services/extended-services.md`; `CD/reference/engine/classes/DataModel.yaml` (`BindToClose`); `DataStoreService.yaml`; `CD/reference/engine/enums/DataStoreRequestType.yaml` |
| 9 | ProfileStore constants: `AUTO_SAVE_PERIOD` 300, `FIRST_LOAD_REPEAT` 5, `LOAD_REPEAT_PERIOD` 10, `SESSION_STEAL` 40, `ASSUME_DEAD` 630, `START_SESSION_TIMEOUT` 120. Session lives in `MetaData.ActiveSession`. Fast release uses topic `"PS_" .. sessionId` | Confirmed | https://raw.githubusercontent.com/MadStudioRoblox/ProfileStore/main/ProfileStore.luau (lines 170–175, 951, 1340, 1585; fetched 2026-10-05) |
| 10 | `MarketplaceService:BindReceiptHandler(Enum.ReceiptType, handler, filter?)` returns an `RBXScriptConnection`. The handler returns `Enum.ReceiptDecision.Processed`/`NotProcessedYet`, and bound handlers take precedence over `ProcessReceipt`. `ProcessReceipt` can run on two servers at once, with no timeout or retry. Cross-game product and pass sales are disabled from 2026-05-30 | Confirmed | `CD/reference/engine/classes/MarketplaceService.yaml` (`BindReceiptHandler`, `ProcessReceipt` "Retries and Timeouts"); `CD/reference/engine/enums/ReceiptType.yaml`, `ReceiptDecision.yaml`; `CD/production/monetization/developer-products.md`, `passes.md` |
| 11 | Subscriptions: Robux price ≥ 49 R$ (70% payout) or local currency at $2.99/$4.99/$7.99/$9.99/$14.99 (70% then 100%); no mutually exclusive tiers. Regional prices are 30–100% of the default. New games and items are enrolled in Managed Pricing by default. Price optimization needs ~60k transactions per 30 d. DevEx pays $0.0038 (or $0.0054) per Robux | Confirmed | `CD/production/monetization/subscriptions.md`, `managed-pricing.md`, `regional-pricing.md`, `price-optimization.md`, `developer-exchange.md` |
| 12 | Kids (5–8) / Select (9–15) / 16+ tiers. Under-16 reach needs 2FA, an age-checked creator, a 1,000 R$ fee or 2 months of Plus/Premium, and 250 unique highly-engaged plays in 60 days. The fee is refunded if the game keeps 25 highly engaged players for 60 days | **Corrected** (refund terms conflict: the FAQ says automatic refund 90 days after eligibility or payment; creator verification means ID if 18+ or facial estimation if under 18; a safety review is also required). The rest is confirmed | `CD/production/publishing/kids-and-select.md` (requirements table, evaluation steps, FAQ); `CD/production/publishing/publish-games-and-places.md` ("Optional fees") |
| 13 | Open Cloud: asset upload 120/min and ≤ 20 MB; place publish 30/min with `x-roblox-size-limit` 10,485,760 bytes; `:publishMessage` 5,000/min; `:restartServers` 30/min; Luau execution 5/min | Confirmed (spec). Context added: Studio places go up to 100 MB, so the 10 MiB cap is endpoint-specific | `CD/reference/cloud/openapi.json`, `CD/reference/cloud/universes-api/v1.json`; `CD/cloud/guides/usage-assets.md`; `CD/includes/place-size-limit.md` |
| 14 | "Server outbound HTTP (includes Open Cloud via HttpService): 500 requests/min per server" | **Corrected** | Open Cloud calls from game servers have a separate 2,500/min limit and do not consume the 500/min budget (`CD/reference/engine/classes/HttpService.yaml` "Limitations"; `CD/cloud-services/http-service.md` "Rate limits"). `CD/cloud/reference/rate-limits.md` still says they count toward 500, which is a docs conflict, now listed in Open questions §5 |
| 15 | Open Cloud bans (`user-restrictions`): 150 req/s | **Corrected** (incomplete) | 150/s per API-key owner (30/s OAuth2), plus per-universe caps: update 10/s, get/list 50/s, and ≤ 2 updates/min per user. `CD/reference/cloud/openapi.json` (`x-roblox-rate-limits` on `/cloud/v2/universes/{universe_id}/user-restrictions*`) |
| 16 | Server memory = 6.25 GiB + 100 MiB × peak players (30 players ≈ 9.18 GiB); keep usage < 50%; server heartbeat capped at 60 FPS | Confirmed | `CD/performance-optimization/identify.md` |
| 17 | `ConfigService` is server-only and returns snapshots. Strings and JSON go up to 100,000 chars; publish takes ~15 s–1 min (or 15 min gradual); 100 conditions per game, 20 per key | Confirmed | `CD/production/configs.md`; `CD/reference/engine/classes/ConfigService.yaml` |
| 18 | The engine Server Authority model is "currently in beta and will be released soon". Predicted attributes must be among the first 64, with names ≤ 50 chars and string values ≤ 50 chars. `Workspace.AuthorityMode` and `RunService:BindToSimulation` exist | Confirmed | `CD/scripting/security/network-ownership.md`; `CD/projects/server-authority/index.md`; `Workspace.yaml`; `RunService.yaml`; `CD/reference/engine/enums/AuthorityMode.yaml` |
| 19 | Hyperion/Byfron: acquired 2022, shipped on 64-bit Windows in 2023, UWP client retired | Unverified (no local docs; WebSearch budget exhausted). Kept at Low-Medium. It does not affect the design | — |
| 20 | ~50 KB/s per-client bandwidth "folk ceiling" | Unverified (no current doc gives a KB/s figure). Kept at Low; the design targets ≤ 20/40 KB/s | `CD/performance-optimization/identify.md`, `improve.md` (no figure) |

**Consistency fixes in "Implementation recommendations"** (all marked "corrected by fact-check" inline):
- **R1/R8 Hub streaming.** The Hub had "StreamingEnabled on, default radii" together with `CharacterAutoLoads = false`.
  That contradicts F3: with no character there is nothing to stream around. Fix: either disable streaming in the Hub, or
  set a server-side `ReplicationFocus` on a static anchor Part.
- **R1 `Players.BanningEnabled`** is `NotScriptable`, so it must be set in Studio. The row said "Battle places … everywhere".
- **R3 budget.** It paired 200 queued tickets with CCU = 100 and 100 tickets with 50 CCU, which is impossible because
  tickets ≤ hub players < CCU. It also under-counted the `asg:` polls (which cost as much as the scans) and ignored the
  1-RU cost of each empty-bucket scan. The scenarios are recomputed above (≈ 34–35% of quota). Empty-bucket cost is
  flagged as the real low-CCU risk.
- **R3 TTL refresh.** "Hub re-sets every 120 s" via `SetAsync` could overwrite a leader's `"M"` claim. It now uses a
  state-guarded `UpdateAsync`.
- **R3 cancel** was a non-atomic check-then-remove. It now flips the state atomically to `"C"` first.
- **R5 autosave budget** cited the 300 + 20 × CCU write limit, although F6.1 says to design to the lower 250 + 20 × CCU
  variant. Corrected.
- **R11** said Kids/Select needs an "ID-verified creator", and implied the label alone makes the game eligible. Corrected
  to "age-checked creator" plus the evaluation, including the safety review.
