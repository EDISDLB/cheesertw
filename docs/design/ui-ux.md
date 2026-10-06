# HULLDOWN: UI/UX Specification

> Status: **authoritative** for every screen, flow, HUD element, input mapping and UI behaviour of the game client.
> Owner: Lead UI/UX Design. Audience: UI engineering (Phase E), content, level, audio, QA.
>
> **Precedence.** `docs/research/00-DECISIONS.md` (values and rules) > this document > research reports.
> `docs/ARCHITECTURE.md` rules code structure and data flow; `docs/design/brand-art.md` rules every colour, glyph,
> font and copy rule (this document only *applies* its tokens); `docs/design/audio.md` owns sound keys.
> When this document needs a value those documents do not fix, it states one and tags it **O** (our UI choice).
> To change a rule here, change it in the same commit as the UI code that depends on it.
>
> **Implementation target.** Roblox, code-built UI through the in-house kit (`Client/UI/Kit`: `Create`, `State`,
> `Theme`, `Tokens`, `Router`, `Focus`, `UIInput`, `InputMode`, `Layout`, `Motion`, `Format`, `Layers`, `Sound`),
> no Studio-authored GUIs, no engine StyleSheets in v1, no `TextScaled` body text, no `BillboardGui` markers,
> Input Action System only. Platforms: PC (keyboard and mouse), console and PC gamepad, phone and tablet (touch).
>
> **IP rule.** Every name, string, layout and icon here is original. Player-facing copy never uses another tank
> game's mode, screen, medal, perk or feature names (§0.3 lists the display names to use instead).
>
> **Revision 2 (Game Director review, 2026-10-06).** This revision adds the canvas-anchoring rules (§1.1.1) and
> the verified HUD density tiers (§S31). It replaces the phone battle layout (§S39) with one that has been checked
> at every phone width, and adds the economy modals (§1.6.1). It also aligns the following with 00-DECISIONS,
> roster.md, content-schema.md and `Types/*`:
> * the Debrief tab set;
> * Field Kit swaps;
> * booster pricing;
> * the `camoBonus` price rule;
> * cosmetic kinds;
> * sample numbers;
> * IP-sensitive display names.
>
> The geometry checks are reproducible from the rules in this document. Every rectangle table states its anchors.

---

## Contents

0. [Conventions, vocabulary and data contracts](#0-conventions-vocabulary-and-data-contracts)
1. [Global framework](#1-global-framework)
2. [Screen specifications](#2-screen-specifications) (S01–S40)
3. [Motion and feedback language](#3-motion-and-feedback-language)
4. [Screen inventory for implementation](#4-screen-inventory-for-implementation)
5. [Cross-team requests, IP flags and open questions](#5-cross-team-requests-ip-flags-and-open-questions)

---

## 0. Conventions, vocabulary and data contracts

### 0.1 Notation

| Notation | Meaning |
|---|---|
| `px` | Reference pixels on the **1920 × 1080** canvas (Regular) or the **844 × 390** canvas (Compact). The kit's root `UIScale` maps them to the device (§1.1). Rendered sizes are always stated as "rendered px". |
| `(x, y, w, h)` | A rectangle in reference px, origin top-left of the layer's safe area, written for the 1920 × 1080 (or 844 × 390) canvas. At run time the canvas size varies; §1.1.1 says how each rectangle is anchored. `W` / `H` in a formula = the run-time canvas width / height. Wireframes are **not to scale**: the rectangle tables are authoritative. |
| `token.name` | A `Theme` token from brand-art (`bg.panel`, `accent.dusk`, `h3`, `num.m`, motion `base`…). Screens never use literal colours or font sizes. |
| `PV.x.y` | Field of the client `ProfileView` (sanitized `Types/Profile.Profile`, patched by `DataSync`). |
| `BV.x` | Field of the client `BattleView` (§0.5). `SS.x` = client `Session` store. `ST.key` = a setting (§S22). `CR` = `ContentRegistry`. |
| `→ Op` | A garage transaction sent through `GarageRequest` with `op = Op` (§0.6). `→ Remote` = another remote. |
| `[A]` `[B]` `[X]` `[Y]` `[LB]` `[RB]` `[LT]` `[RT]` `[L3]` `[R3]` `[View]` `[D↑]` | Gamepad buttons (Xbox naming in this doc; PlayStation art comes from `GetImageForKeyCode`). |
| `[Bksp]` `[Enter]` `[Tab]` `[1]`… `[LMB]` `[RMB]` `[Wheel]` | Keyboard and mouse. |
| **O** / **D§n** / **B§n** / **A§n** / **AU§n** | Our UI choice / 00-DECISIONS § / brand-art § / ARCHITECTURE § / audio.md §. |
| P0 / P1 / P2 | Implementation priority: P0 = needed for the first playable vertical slice, P1 = launch, P2 = post-launch polish. |

### 0.2 Spec template used by every screen in §2

Each screen lists: **Purpose · Entry / exit · Wireframe (1920 × 1080) · Layout table · Compact (844 × 390) and TV notes ·
Components · Data bindings · Actions · States · Controller map · Acceptance criteria.** Components named in
`PascalCase` are kit components (`Client/UI/Kit/Components/*`); the ones that do not exist yet are listed in §4.2.

### 0.3 Player-facing vocabulary (copy deck, IP-safe)

Internal ids stay as they are in code and content. The UI shows only the right-hand column (brand §2 casing).

| Internal id / research term | UI display (headings · body) | Notes |
|---|---|---|
| Mode `Random` | `OPEN TRIALS` · Open Trials | Lore: the Ridge Accord's Trials (roster §0.4). 15 v 15 with labelled bots. |
| Mode `Practice` | `DRILL` · Drill | Versus bots only, normal rewards ×0.75 when no human enemies (D§8). |
| Mode `Bootcamp` | `PROVING FIELD` · Proving Field | Guided first battles (§S27). |
| Mode `Training` | `PRIVATE TRIAL` · Private trial | Custom rooms (P2). |
| Mode `Event` | Event's own `name` | From `EventModeDefinition.name`. |
| Battle type `Standard` | `CONTEST` · Contest | Two bases; capture or destroy. |
| Battle type `Encounter` | `CROSSROADS` · Crossroads | One neutral base. |
| Battle type `Assault` | `BREACH` · Breach | One side defends. |
| "About Vehicle" | `INSPECT` | §S08 |
| "My Vehicles" grid | `MOTOR POOL` | §S05 |
| "Playlists" | `LINEUPS` | §S05 |
| Armor Inspector | `ARMOR` tab · "Armor view" | Code name `ArmorInspector` (A§10). |
| Sixth Sense (D§5) | `SPOTTED` alert · Settings "Spotted alert" | The mechanic name never appears in UI. |
| Battle Heroes (D§14) | `FIELD HONOURS` | Medal display names in §5.3 (the decided internal names match another game's medals and must not be shown). |
| Gun Marks (D§14) | `BARREL BANDS` | Bands painted on the gun barrel (rendered as a `GunSleeve`-style mark). They are not the mastery badge's kill rings (B§6.13). |
| Mastery Ace / I / II / III | `RIDGE MASTERY` · `GOLD MASTERY` · `SILVER MASTERY` · `BRONZE MASTERY` | Named after the badge materials (B§6.13: III bronze, II silver, I gold, Ace obsidian with the dusk ridge). "Ace" and "First / Second / Third Class" are another game's mastery names and are never shown. |
| Barracks (unassigned crews) | `RESERVE` · Crew reserve | Code may keep `Barracks`; the label is never "Barracks". |
| Depot (spare items and shells) | `SPARES` · Spare equipment / spare shells | The label is never "Depot". |
| Crew books 5k / 25k / 60k (D§12, D§14 "Booklet", "Guide") | `FIELD NOTES` · `DRILL MANUAL` · `CREW CODEX` | Internal ids unchanged. |
| Premium Time | `PREMIUM TIME` | Account-wide booster bought with Bullion (D§11). |
| HULLDOWN Plus | `HULLDOWN PLUS` | Robux subscription (D§11, D§15). |
| Field Kits | `FIELD KITS` | Elite vehicle upgrades (D§11). |
| Free XP | `Free XP` | Currency name (D§0). |
| Platoon | `PLATOON` | Generic military term, used by brand and decisions. |
| Battle results | `DEBRIEF` (screen title), tabs per §S38 | |
| Garage | `GARAGE` (brand lockup `COMMAND GARAGE`) | |

### 0.4 Client stores (A§10 `Client/State`)

| Store | Source | Contents used by UI | Update rule |
|---|---|---|---|
| `ProfileView` (`PV`) | `DataSync` full view on join, then `ProfilePatch` lists with sequence numbers | Everything in `Types/Profile` except `processed`, `moderation` internals (strike count and `queueLockedUntil` are exposed) | Patches applied in order; a gap triggers a full resync (REG-UI-06). Screens bind **selectors**, never copy values. |
| `Session` (`SS`) | Client controllers + S2C pushes | `selectedVehicleId`, `queue` (§S06), `platoon` (§S23), `plusActive`, `robloxPremium`, `policy` (PolicyService result), `notifications[]`, `compareList[]`, `inputMode`, `layout` (`Regular`/`Compact`/`TV`), `resultsCache[battleId]`, `pendingPurchases`, `friends` | Not persisted, except the keys mirrored into settings (selected vehicle, filters). |
| `Settings` (`ST`) | `PV.settings` (≤ 128 keys, D: `LIMITS.SETTINGS`) | §S22 key table | Written through `SettingsSet` (debounced 1.5 s, batched). Device-class keys carry a `.pc` / `.mob` / `.con` suffix. |
| `BattleView` (`BV`) | `SnapshotPacket` (20 Hz), reliable battle event stream, client prediction (A§6.2) | §0.5 | Read-only for UI. HUD widgets subscribe to the narrowest field. |
| `ContentRegistry` (`CR`) | Shared config | Vehicle, module, shell, equipment, mission, store definitions | Frozen. UI derives stats with `StatsCalculator` (same path as battle, REG-UI-07). |

### 0.5 BattleView fields the HUD binds to (contract for the Battle client team)

```
BV.phase            "Loading" | "Countdown" | "Running" | "Ended"
BV.countdownEndsAt  number (client clock)          BV.timeLeftS  number          BV.mode / BV.battleType / BV.mapId
BV.teams[1|2]       { alive, total, hp, hpMax, kills, baseIds }
BV.capture[baseId]  { team, points (0..100), cappers, contested, owner }
BV.own              { entityId, hp, hpMax, speedKmh, gear ("F"|"N"|"R"), modules[kind] {state, repairT, repairTotal},
                      crew[slot] {role, also, injured}, burning, stunnedUntil, gun { state ("Loading"|"Ready"|"Disabled"),
                      reloadLeft, reloadTotal, magazine {left, size, perShell[]}?, dual { charging, barrels[] }?,
                      charge? }, ammo[slot] {shellId, count}, selectedShell, queuedShell, consumables[slot]
                      {id, cooldownLeft, cooldownTotal, active, durationLeft}, mechanic {kind, state, cooldownLeft}?,
                      spottedAt? (client time of the last "you are spotted" event), sniper, zoom, alive }
BV.aim              { point (Vector3), dispersionNow, dispersionTarget, serverDispersion?, penState? (§S31 H-06),
                      target? (entityId under the reticle), lock? (entityId) }
BV.vehicles[id]     visible entities only (spotting-filtered by the server): { team, class, tier, vehicleId, name,
                      isBot, platoonPip?, hp, hpMax, alive, lastSeenAt, screenPos (overlay), distanceM }
BV.minimap          { records[] (2 Hz far records), lastKnown[] (≤ 30 s), pings[], arty rings[] }
BV.feed / BV.log    bounded rings fed by the event stream (kill feed 5, damage log 8, ribbons 3)
BV.roster           both teams' participants (name, vehicle, tier, class, isBot, platoon, alive) from the manifest
```
Every enemy field is present **only** when the server sent it (A§6.1 step 9); the HUD never infers enemy identity
or position from anything else (REG-SPT-08). Shots from unseen enemies arrive as anonymous `ShotHeard` events and
feed only sound and sound visualisation (§1.15), never a marker; a hit on the player drives the hit-direction
indicator from the shell's own path (H-13), not from the shooter's position.

### 0.6 Remote contract proposals (owners finalize names in `Shared/Net/RemoteDefs/*`)

All mutating requests carry a client `requestId` (≤ 40 chars, A§5.2). The profile patch arrives **before** the
response (REG-ECO-02), so the UI never applies results from the response itself; it only resolves the pending state.

| Remote (proposed) | Kind / dir | Domain file | Rate (D§19) | Used by |
|---|---|---|---|---|
| `GarageRequest` `{op, requestId, payload}` → `Result` | Function C2S | Progression | 5/s | Every garage transaction. `op` ∈ `ResearchVehicle, ResearchModule, BuyVehicle, SellVehicle, BuybackVehicle, MountModule, SetEquipment, DemountEquipment, BuyEquipment, SetAmmo, SetConsumables, SetAutoResupply, AssignCrew, RecruitCrew, RetrainCrew, LearnPerk, ResetPerks, UseCrewBook, ConvertXP, ExchangeBullion, BuyCustomization, ApplyCustomization, ClaimMission, RerollDaily, ClaimPassStage, BuyPassPaid, SetFavorite, SelectFieldKit, ResearchApexNode, ActivateBooster, BuyStoreItem, BuyPremiumTime, AckFlag, SetTutorialStep, SetMatchmakingPrefs, SetPlusVehicle` (each = one `Transactions` function, A§7; `AckFlag` sets `PV.account.flags.*`; `ClaimPassStage` and `ClaimMission` take a list of ≤ 30 keys so `CLAIM ALL` is one request inside the 5/s bucket). |
| `QueueJoin` `{mode, vehicleId, requestId}` / `QueueLeave` / `QueueStartWithBots` | Function C2S | Matchmaking | 1/s | §S06 |
| `QueueState` | Event S2C | Matchmaking | – | `SS.queue` |
| `MatchFound` `{mapId, mode, battleType, etaS}` / `TeleportStatus` | Event S2C | Matchmaking | – | §S06, §S28 |
| `ReturnToBattle` `{requestId}` | Function C2S | Matchmaking | 1/s | Garage CTA when `PV.activeBattle` |
| `PlatoonInvite` / `PlatoonRespond` / `PlatoonLeave` / `PlatoonKick` / `PlatoonPromote` | Function C2S | Social | 0.2/s (invites), 1/s others **O** | §S23 |
| `PlatoonReady` `{ready, vehicleId}` | Event C2S | Social | 1/s | §S23 |
| `PlatoonState` | Event S2C | Social | – | `SS.platoon` |
| `JoinFriend` `{userId}` | Function C2S | Social | 0.2/s | §S24 (server teleports to the friend's Hub server) |
| `SettingsSet` `{changes}` | Event C2S | Settings | 1/s | §S22 |
| `GetResult` `{battleId}` → `ResultsView` | Function C2S | Progression | 2/s | §S38 |
| `ResultsReady` `{battleId}` / `RewardApplied` | Event S2C | Progression | – | §S38, notifications |
| `PurchaseGranted` `{purchaseId, storeItemId, grants}` | Event S2C | Store | – | Reward toast after a Robux receipt (D§15) |
| `ServerNotice` | Event S2C | Foundation (exists) | – | System banners (§1.5) |
| Battle: `InputPacket` (exists in plan), `SelectShell`, `UseConsumable`, `ActivateMechanic` | C2S | Battle | 4/s each | HUD |
| `CommandSend` `{command, targetEntity?, position?}` | Event C2S | Battle | markers 3/5 s, ≤ 12/min; chat presets 1/10 s | §S33 |
| `LeaveBattle` / `SpectateTarget` | Event C2S | Battle | 1/s | §S35, §S36 |

Robux purchases never use a custom remote: the client calls `MarketplaceService:PromptProductPurchase` (or
`PromptSubscriptionPurchase` for Plus), the Hub's `BindReceiptHandler` grants, and `PurchaseGranted` drives the toast.

---

## 1. Global framework

### 1.1 Canvas, grid, layouts and layers

**Layouts** (D§16, kit `Layout`):

| Layout | Trigger | Authoring canvas | Root scale | Extras |
|---|---|---|---|---|
| **Regular** | viewport height ≥ 600 | 1920 × 1080 | `clamp(vh / 1080, 0.75, 1.5)` × user UI scale (`ui.scale` 0.8–1.2; touch devices 1.0–1.2) | Desktop and tablets |
| **Compact** | viewport height < 600 | 844 × 390 | `clamp(vh / 390, 0.92, 1.25)`; **no user UI scale** (it would push touch targets under the minimum or break the 390 px layout) | Phones (landscape only) |
| **TV** | `GuiService:IsTenFootInterface()` (kit `Layout.state.tenFoot`) | 1920 × 1080 | Regular × 1.25 | 5 % inner safe margin (96 / 54 px). A PC with a gamepad stays Regular. |

**Grid (Regular):** 8 px unit; spacing tokens `space.1…8` = 4, 8, 12, 16, 24, 32, 48, 64. Twelve columns of
130 px with 24 px gutters and 48 px outer margins (screens without the rail). Garage-type screens reserve the left
**nav rail (120 px)**. Their content grid runs x 144–1896: twelve 124 px columns with 24 px gutters, a 24 px gap after
the rail and a 24 px right margin, so content is 1,752 px wide **O**. That width is used by the strip, the carousel,
the tech-tree canvas and the Debrief.

**Grid (Compact):** 4 px unit; 24 px outer margins (device safe insets added on top); the nav rail is 64 px.

**Type on Compact.** Theme clamps to brand minimums (B§4.2: phone sentence 16, labels 14 rendered). At the 0.92
floor scale, authored tokens must therefore be at least: `body` 18, `body.s` 18, `label` 16, `caption` 18 (it carries
sentences, so it needs 16 rendered), `micro` 16, `h4` 20, `h3` 24, `h2` 28, `h1` 32, `num.m` 20. The Compact theme
uses this override table instead of letting the clamp overflow layouts. **TV** uses `label` / `micro` 15 authored
(= 18.75 rendered at × 1.25, ≥ 18 for labels) and `caption` / `body.s` 16 (= 20, the console sentence minimum, B§4.2).

**Layers** (kit `Tokens.layers`, one `ScreenGui` each; interactive layers use `ScreenInsets.CoreUISafeInsets`):

| Layer | DisplayOrder | Insets | Holds |
|---|---|---|---|
| `Background3D` | 0 | None (non-interactive) | Hangar vignette, cinematic letterbox, header backing band |
| `HUD` | 10 | `DeviceSafeInsets` for gauges; touch controls in a second `HUDInput` gui with `CoreUISafeInsets` | Battle HUD |
| `Screens` | 20 | CoreUISafeInsets | All menu screens and drawers |
| `TopBar` (**new, O**) | 25 | `TopbarSafeInsets` | The garage top bar (§1.4). Fallback below. |
| `Modals` | 30 | CoreUISafeInsets | Modals, sheets, pickers |
| `Toasts` | 40 | CoreUISafeInsets | Toasts, system banners |
| `Tooltip` | 50 | CoreUISafeInsets | Tooltips, dropdown lists |
| `Debug` | 90 | None | Dev overlays (developers only) |
| Loading (ReplicatedFirst) | 100 | None | Boot screen, teleport GUI |

`TopBar` sits in the engine's top-bar row (`GuiService.TopbarInset`), to the right of Roblox's own buttons, so the
header costs no extra height. Its content is authored for a **56 px** row. If the engine row is shorter than 44
rendered px (some phones), the top bar moves into the `Screens` layer as a 48 px band under the core row. This is
an in-engine verification item (§5.5).

#### 1.1.1 Canvas range and anchoring (applies to every rectangle table)

Each layer root is `Layout.root()`, sized `1 / scale`. So the run-time canvas is **W × H = viewport ÷ scale**, not
1920 × 1080. The range to support is:

| Layout | Canvas height H | Canvas width W | Typical cases |
|---|---|---|---|
| Regular (menus) | 800–1,800. The effective `ui.scale` is lowered automatically until the canvas is at least **1,280 × 800**, and the setting shows "Limited by this display". | 1,280 (4:3 and 5:4) to 3,440+ (21:9) | 1280 × 720 → 1,707 × 960 · 1024 × 768 → 1,365 × 1,024 · 4K → 2,560 × 1,440 |
| Regular battle HUD | Effective height `E = H ÷ hud.scale`, 720–1,800. `hud.scale` is capped so that E ≥ 720 and the effective width is ≥ 1,360 (≥ 1,448 in event modes with abilities). | as above ÷ `hud.scale` | 1080p at 150 % → 1,280 × 720 is not allowed (width 1,280 < 1,360), so the cap lowers the scale to 141 % → 1,360 × 765 |
| Compact (phones) | 390–480. The battle HUD uses `min(1.25, vh / 390)` so it never has H < 390. | 693 (16:9) to 870 (20:9) | 667 × 375 → 695 × 390 · 844 × 390 → 844 × 390 · 932 × 430 → 845 × 390 |
| Touch on a Regular display (tablets), battle only | fixed **700** (HUD root = vh / 700) | 933–1,120 | 1024 × 768 → 933 × 700 · 1180 × 820 → 1,007 × 700 |

**Anchoring rule.** Each rectangle keeps its offsets from an anchor.
* **Horizontal:** a rectangle whose centre lies in the left third of the reference canvas is left-anchored; one in the
  right third is right-anchored (`x = W − (1920 − x₀)`); one in the middle third is centred
  (`x = W/2 + (x₀ − 960)`).
* **Vertical:** the same rule by thirds of the height.
* **Stretch:** a rectangle that spans more than two thirds of an axis stretches and keeps both margins. For example,
  the Garage carousel is `(144, H − 200, W − 168, 104)`.
* **Exceptions:** tables give explicit anchors or formulas where the thirds rule would be wrong (the Garage stack,
  §S04; the HUD, §S31; touch controls, §S39). Explicit entries always win.
* **Larger canvases:** when the canvas is larger than the reference, edge-anchored regions stay at their edges,
  stretch regions grow and centred groups stay centred. The extra space goes to the 3D hangar or battle view.

**Narrow and short canvases (Regular menus).** These rules switch on by canvas size and are tested at 1,280 × 800,
1,365 × 1,024, 1,707 × 960 and 1,920 × 1,080:

| Condition | Screen | Rule |
|---|---|---|
| W < 1,496 | Garage (§S04) | Right column hidden (dailies via the Missions rail and its badge); the battle cluster stays centred |
| W < 1,600 | Inspect (§S08) | View switch becomes icon-only, 4 × 64 |
| W < 1,600 | Debrief (§S38) | Vehicle card hidden |
| W < 1,600 | Store (§S20) | Hero spans the content width |
| W < 1,880 | Settings (§S22) | Description column hidden; its text shows as a `caption` under the focused row and the preview opens with `[X]` / the info button |
| W < 1,880 | Compare (§S11) | Vehicle columns scroll horizontally; the label column stays sticky |
| W < 1,920 | Research (§S09) | Load bar width = W − 1,020 (min 260) beside the footer |
| W < 1,840 | Missions daily cards (§S18) | Cards width = (W − 240) / 4 |
| H < 1,080 | Garage | Stats panel and right column shrink (§S04 formulas) |
| H < 1,080 | Screens with full-height panels (Inspect, Tech Tree, Settings, Crew, Exterior) | Panels stretch: y 72 to H − 128 |
| H < 1,000 | Garage | Two carousel rows are not offered (`garage.rows` falls back to 1) |

Modals (≤ 880 wide) and toasts (360 wide, right-anchored) fit every supported canvas unchanged.

### 1.2 Navigation model

```
 ┌ Roblox core row ─────────┬──────────────────── TopBar (§1.4) ────────────────────────────────────────┐
 │ [≡ Roblox][chat]         │ [‹ BACK] GARAGE │ vehicle identity │ currencies │ [friends][bell][profile]│
 ├──────┬───────────────────┴──────────────────────────────────────────────────────────────────────────┤
 │ ▣ GAR│                                                                                               │
 │ ▤ TEC│                         current section (Screens layer)                                       │
 │ ◉ CRW│                                                                                               │
 │ ✎ MIS│                                                                                               │
 │ ▲ PAS│                                                                                               │
 │ ⛟ STO│                                                                                               │
 │ ⌂ PRF│                                                                                               │
 │ ⚙ SET│                                                                                               │
 └──────┴───────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Left nav rail** (D§16 order). 120 px wide, full height under the top bar. Each item is 120 × 80: glyph 32 px
(`ui/garage`, `ui/tech_tree`, `ui/crew`, `ui/missions`, `missions/battle_pass`, `ui/store`, `ui/profile`,
`ui/settings`) over a `micro` label (`GARAGE`, `TECH TREE`, `CREW`, `MISSIONS`, `PASS`, `STORE`, `PROFILE`,
`SETTINGS`). Active item: `bg.selected` fill, 3 px dusk left edge with the crest notch, label `text.primary`.
Badges (§1.5.3) sit at the glyph's top-right. Hovering or focusing the rail for 300 ms expands it to 280 px over the
content (labels in `body` beside the glyphs, no reflow of the page). Compact: 64 px rail, glyphs only, no expansion;
labels appear in a tooltip on long-press. Pressing an item **resets** the stack to `[Garage, Section]` (§1.3).

**Universal Back.** Esc and ButtonStart are reserved by Roblox (D§16), so Back is: the top-bar `‹ BACK` button,
`[Bksp]`, `[B]`, and on touch the same button. Back order: (1) close the top tooltip / dropdown / popover,
(2) the top screen's `onBack` (closes an open drawer, cancels a preview, leaves a sub-view), (3) close the top modal
if dismissible, (4) pop the stack, (5) on the Garage root, open the **Game menu** (§S26). Back never discards unsaved
changes silently: screens with a pending change (Exterior cart, Ammo edits) ask with a confirm modal.

**Game menu.** On the Garage root the Back button shows `ui/menu` instead of the chevron and opens §S26.
In battle, Back opens the **Field menu** (§S36): `[Bksp]`, gamepad `[B]` held 0.6 s (tap is the vehicle mechanic),
or the on-screen menu button (touch).

### 1.3 Screen stack, transitions and deep links

| Entry type | Router call | Back behaviour | Transition (enter / exit) | Reduced motion |
|---|---|---|---|---|
| **Root** (Garage) | `reset("Garage")` | Opens Game menu | fade 200 ms | fade 100 ms |
| **Section** (rail items) | `reset("Garage")` + `push(section)` | Pops to Garage | fade `slow` 200 ms in, 120 ms out; no slide (sections are siblings) | fade ≤ 100 ms |
| **Drill-in** (Inspect, Armor, Compare, Research from a section) | `push(name, params)` | Pops one level | slide 24 px from the right + fade, `enter` easing 200 ms; exit 120 ms `exit` easing | fade ≤ 100 ms |
| **Drawer** (service strip items, filters) | in-screen panel; `onBack` closes it | Closes drawer | slide from its edge 200 ms; scrim 0→40 % on Compact only | fade |
| **Modal** | `openModal(name, params)` | Closes if dismissible | `pop`: scale 0.98→1 + fade 150 ms | fade |
| **Sheet** (Compact modal) | `openModal` with `sheet = true` | Closes | slide up 200 ms | fade |
| **Overlay** (Deploying, Battle loading, Results) | `reset(name)` | Results: Back → Garage; others not dismissible | fade 300 ms through `bg.abyss` | fade |

* At most **one blocking modal**; closing it returns focus to the opener (REG-UI-11).
* Expensive screens are `keepAlive`: Garage, TechTree, Store, Settings. They rebuild only on content change.
* The 3D hangar (`Render/HangarScene`) is shared. Each screen declares a **camera preset**; switching presets
  tweens the camera 450 ms with `emphasized` easing (cut under reduced motion): `hero` (Garage), `inspect`
  (free orbit), `xray` (Inspect modules/crew), `armor`, `exterior` (closer orbit, slow auto-rotate off), `crew`
  (side cutaway), `lineup` (Missions/Store: vehicle at 30 % width, out of focus by 6 % darker vignette).
* **Deep links** (`Router.navigate`): `Garage`, `Garage?vehicle=<id>&drawer=ammo`, `Garage/Inspect?vehicle=<id>&tab=armor`,
  `Garage/TechTree?faction=<id>&focus=<vehicleId>`, `Garage/Research?vehicle=<id>`, `Garage/Crew?vehicle=<id>`,
  `Garage/Missions?tab=daily|weekly|campaigns|special|event|pass`, `Garage/Store?section=<id>&item=<id>`,
  `Garage/Profile?tab=battles`, `Garage/Settings?cat=accessibility`, `Garage/Results?battle=<id>`,
  `Garage/Notifications`. Notification actions and tutorial steps navigate only through these links.

### 1.4 Top bar

56 px row in the `TopBar` layer (§1.1). Slots left to right at 1920 px (widths include 35 % label slack, B§2):

| Slot | Width | Content | Binding | Action |
|---|---|---|---|---|
| Back | 56 | `ui/back` (or `ui/menu` on the Garage root), 44 × 44 hit area | Router depth | Back (§1.2) |
| Section title | 220 | `h3` 28 UPPER, stencil index `01` in `text.tertiary` (B§8.2) | current section | – |
| **Center slot** | 640 | Garage and its drawers: faction emblem 28, tier plate 28, class glyph 24, vehicle name `h3`, role chip `label`, vehicle XP bar 200 × 6 (`currency.vehicle_xp` fill on `bg.inset`) + `mono` "12,400 / 21,000". Other sections: section sub-title or breadcrumbs (`Tech Tree › Iron Union`). | `SS.selectedVehicleId`, `PV.vehicles[id].xp`, next research cost from `ResearchGraph` | Click: Inspect (§S08) |
| Currencies | 4 × 128 | Credits, Bullion, Free XP, Campaign Tokens: icon 24 + `num.m` 22 in `text.primary` (B§3.6). Bullion and Credits carry a 24 px `ui/plus` button. | `PV.currencies.*` | Bullion `+` → Store Bullion section; Credits `+` → Exchange modal (1 BUL → 200 CR, D§11); Free XP click → Convert XP modal; Tokens click → Token Shop |
| Social | 48 | `ui/friends` + online-friends count `micro` | `SS.friends` | Social (§S24) |
| Notifications | 48 | `ui/notifications` + badge | unread count | Notifications (§S25) |
| Profile chip | 240 | rank insignia 32 (`ranks/rank_NN`), display name `body.s` Bold, status line `caption`: `Premium · 6d 4h` (dusk sun glyph `ui/premium`) / `Plus` / `Standard account` | `PV.account.rank`, `PV.account.premiumUntil`, `SS.plusActive` | Profile (§S21); status line → Store Premium section |

* Values animate with a count-up (`countUp` 600 ms) and a 400 ms currency-coloured flash on change (§3).
* **Collapse order.** The row's available width is the `TopBar` layer's `AbsoluteSize.X`, which already excludes
  Roblox's core buttons. The full set needs 1,820 px: the slots above plus seven 8 px gaps. While it does not fit,
  the bar collapses in this order:
  1. The profile chip becomes the rank insignia only (48 px; status line in its tooltip) → 1,628.
  2. Free XP and Campaign Tokens fold into a `…` wallet button (48 px) → 1,420.
  3. The centre slot drops the XP bar text (440 px) → 1,220.
  4. The section title keeps only the stencil index (120 px) → 1,120.

  The 1,280-wide minimum canvas (§1.1.1) always fits step 4. Compact shows Credits and Bullion plus the wallet
  button. The wallet opens a sheet with every account currency (Credits, Bullion, Free XP, Campaign Tokens) and any
  event tokens.
* Premium Time under 24 h shows the timer in `state.warning`; expired shows nothing (no nagging).

### 1.5 Notification system

#### 1.5.1 Channels

| Channel | Where | Lifetime | Use |
|---|---|---|---|
| **Toast** | Toasts layer, top-right under the top bar: x 1536–1896, stacking downward from y 72, 360 px wide (B§8.5) | 4 s, 8 s with an action, 30 s for invites; max 3 visible; hover / focus pauses the timer | Things that just happened |
| **Reward toast** | same stack | 4 s + 400 ms dusk shimmer | Currency, XP, item grants |
| **System banner** | Full-width strip under the top bar, 40 px, `state.warning` 4 px left stripe | Until resolved | Server restart countdown, version mismatch, purchase still processing |
| **Notification center** | §S25 | Session + derived entries (last 100) | History of every toast and every actionable item |
| **Badges** | Rail items, tabs, service strip tiles, carousel cards | While the condition holds | Pending actions |
| **HUD channels** (battle) | §S31 | – | Battle never shows garage toasts; only system banners (server shutdown) and platoon/friend events are queued to the center |

Toast anatomy (B§8.5): `bg.panel` 95 %, 4 px left stripe in the state colour, 24 px state icon, title `title.s`
(Builder Sans Bold 16), body `caption` `text.secondary` (≤ 2 lines, truncated with ellipsis), optional action button
(secondary, compact 36 px), close `ui/close` 24. Slides 24 px from the right in 160 ms (`toast`), exits by fade 120 ms.
Overflow beyond 3: the oldest non-action toast leaves early; if all three have actions, new ones go straight to the
center and the bell pulses once.

**Do-not-disturb rules.** While `SS.queue.state ∈ {Queued, Found, Deploying}` only actionable platoon toasts and
system banners show (setting `ntf.dndQueue`, default on). During tutorial steps, toasts wait until the step closes.

#### 1.5.2 Catalogue

| Type | Toast | Center | Badge | Sound | Action (deep link) |
|---|---|---|---|---|---|
| `ResultsReady` | info "Debrief ready: Victory on Cinder Valley" | yes | bell | `ui_notification` | VIEW → `Garage/Results?battle=` |
| `RewardGranted` (purchase, mission, pass, inbox) | reward toast `+1,000 [Bullion]` | yes | – | `ui_purchase` (purchase) / `ui_confirm` | – |
| `ResearchAffordable` (first time a vehicle's XP covers the next node) | success "Tukktund can be researched" | yes | Tech Tree rail | `ui_notification` | RESEARCH → `Garage/TechTree?focus=` |
| `ResearchComplete` / `VehicleBought` | success | yes | – | `ui_research_complete` / `ui_vehicle_unlocked` | – |
| `MissionComplete` | success with mission icon | yes | Missions rail + tab | `ui_mission_complete` | CLAIM → `Garage/Missions` |
| `PassStageReached` | success "Stage 12 reached" | yes | Pass rail | `ui_level_up` | – |
| `AchievementEarned` | reward toast with badge art | yes | Profile rail | `ui_achievement_unlocked` | – |
| `CrewPerkReady` | – | yes | Crew rail + service tile | – | – |
| `PlatoonInvite` | actionable, 30 s, ACCEPT / DECLINE | yes | bell | `ui_notification` + `hangar_pa_chime` | §S23 |
| `FriendOnline` | info (setting, default off) | yes | – | none | INVITE |
| `PremiumExpiring` (24 h left, once) | warning | yes | – | `ui_notification` | EXTEND → Store |
| `QueueLocked` (AFK strikes, D§9) | danger "Queue locked for 10 min. Reason: inactive in battle." | yes | – | `ui_error` | – |
| `VehicleReleased` (30 min lock expiry, A§7) | info | yes | – | – | – |
| `PurchasePending` | system banner "Purchase is processing. Bullion will arrive shortly." | yes | – | – | – |
| `ServerRestart` (`ServerNotice`) | system banner with countdown | yes | – | `ui_notification` | – |
| `VersionMismatch` | system banner "A new version is available. Rejoin when convenient." | yes | – | – | – |
| `Error` (transient request failure) | danger, copy from §1.9 | no | – | `ui_error` | RETRY if idempotent |

#### 1.5.3 Badges

Chamfered dusk tag, min 18 × 18, Oswald SemiBold 13 `text.inverse` (B§8.5); `99+` cap; a 10 × 10 **dot** variant
for "new, uncounted". Badge counts are pure selectors over `PV`/`SS` (REG-UI-09: viewing marks items read and the
count updates within one patch). "Seen" markers live in `ST.seen` (one encoded key holding each area's last-seen
ids and timestamps).

| Badge on | Count = |
|---|---|
| Missions rail | claimable missions + claimable campaign rewards |
| Pass rail | claimable pass stages (free + paid owned) |
| Tech Tree rail | researchable-and-affordable nodes not yet seen |
| Crew rail / Crew tile | crew members with an unspent perk slot (training ≥ 100 % on the slot's predecessor) |
| Profile rail | unseen achievements |
| Store rail | dot only: new store items since last visit (never a count, never on a timer) |
| Bell | unread notification center entries |
| Social | pending platoon invites |
| Carousel card | dot: vehicle can be researched forward / elite / has an unclaimed vehicle mission |

### 1.6 Modals, confirmations and sheets

| Kind | Width | Content | Buttons (primary rightmost, B§8.5) | Dismiss |
|---|---|---|---|---|
| Info | 480 | `h3` title, `body` text, optional icon 48 | `OK`-type verb ("GOT IT") | Back, scrim |
| Confirm | 480 | title states the action, body states consequences and costs | `CANCEL` · verb (`MOUNT`, `RESEARCH`) | Back, scrim |
| **Purchase confirm** | 640 | item art 96, name, what you get (grants list), price with icon, balance → balance after (`num.m`), shortfall line in `state.danger` with the fix action | `CANCEL` · `BUY FOR [icon] 3,500` | Back |
| **Destructive** | 640 | hazard band (B§8.2) 6 px at the top, title names the thing (`SELL TUKKHALD`), list of what is lost or refunded | `CANCEL` · destructive button with **hold-to-confirm 1.2 s** on gamepad and touch (ring fills), click on KBM | Back |
| Blocking progress | 480 | spinner-free progress bar or step list | none, or `CANCEL` when safe | not dismissible |
| Picker | 880 | search field + virtual grid | `CANCEL` · `SELECT` | Back |
| **Sheet** (Compact) | full width, ≤ 80 % height | same content as the modal, drag handle | same | swipe down, Back |

Rules: every Bullion spend uses Purchase confirm (never one-click); spends of Credits ≥ 50 % of the balance or
≥ 500,000 also confirm; equal-cost reversible actions (mount owned module, assign crew) never confirm. Modal
focus is trapped; initial focus is the **safe** button (Cancel) for destructive kinds and the primary button
otherwise.

#### 1.6.1 Economy modals (every one is a `GarageRequest` op with a dry-run preview)

| Modal (kind, width) | Opened from | Content | Op |
|---|---|---|---|
| **Exchange** (Purchase confirm, 640) | Credits `+` in the top bar; `EXCHANGE BULLION` fix action (§1.9) | Bullion amount stepper (step 1, 10, 100) and slider; Credits received = BUL × 200 (D§11) in `num.l`; balances before → after; pre-filled with the exact shortfall when opened from an error | `ExchangeBullion` |
| **Convert XP** (Purchase confirm, 640) | Free XP in the top bar; Research footer (§S09) | List of elite vehicles with banked XP (checkbox each); total XP; Bullion cost = ceil(XP / 10) (D§11); Free XP after. Non-elite vehicles are listed greyed with the reason "Research everything on this vehicle first" | `ConvertXP` |
| **Sell vehicle** (Destructive, 640) | Inspect overflow `⋯` → `SELL` (the gamepad path); carousel card context menu (`[RMB]` / long-press 0.5 s: `INSPECT`, `FAVOURITE`, `MAKE PLUS VEHICLE`, `SELL`) | Title `SELL <NAME>`. Refund lines: tech-tree 50 % of the Credit price; premium 50 % × BUL price × 200 CR (D§11). Mounted equipment, shells and consumables go to Spares for free. Crew goes to the Reserve (or `DISMISS CREW` checkbox, off by default). "You can buy it back for 72 h at +10 %." Blocked, with the reason shown, while the vehicle is locked or queued, while it is the selected Plus vehicle, and when it is the last owned vehicle (**O**: the player always keeps one vehicle to play) | `SellVehicle` |
| **Buy back** (Purchase confirm, 640) | Tech Tree node `BUYBACK +10 %` (§S10); Store vehicle page for sold premiums | Price = sell refund × 1.10 in the original currency; time left `Format.duration`; same buy options as §S10 | `BuybackVehicle` |
| **Plus vehicle** (Picker, 880) | Store › Premium & Plus card; carousel card overflow `MAKE PLUS VEHICLE` | Tech-tree vehicles you own (premiums excluded, D§11 "+20 % on one tech-tree vehicle"); the current one marked; changing it is allowed once per 24 h (**O**, so the bonus cannot follow every vehicle; Economy to confirm, §5.6) with the cooldown shown | `SetPlusVehicle` |
| **Boosters** (sheet / panel 640) | Store › Boosters; the active-booster chip on the profile chip | Owned boosters (count, effect, duration or battles) with `ACTIVATE` (vehicle picker for vehicle-bound ones); active boosters with time / battles left; at most `LIMITS.ACTIVE_BOOSTERS` active | `ActivateBooster` |
| **Map preferences** (Picker, 880) | Mode selector `MAP PREFERENCES ›` (§S06) | Grid of map cards (512 × 288 art, name, climate strip, B§9); toggle "Avoid" on up to 1 map (2 with Premium Time, `LIMITS.MAP_BLACKLIST`); hidden until ≥ 8 maps exist (D§8); battle-type opt-out toggles for Crossroads and Breach (Tier IV+) | `SetMatchmakingPrefs` |

### 1.7 Tooltips

* **Mouse:** appears after `tooltipDelay` 0.4 s of hover (setting: 0.2 / 0.4 / 0.8 s), follows placement priority
  right → left → below → above, 8 px offset, never covers the hovered element, max width 320, `bg.panel` + shadow.
* **Gamepad:** focus + 0.6 s shows the tooltip docked beside the focused element; `[X]` "Details" toggles a pinned
  tooltip that stays while focus moves within the same list (used in Equipment, Crew perks, Tech Tree).
* **Touch:** long-press 0.5 s (`longPress`) shows it while the finger stays down; every stat row also has a
  24 px `ui/info` button (44 px hit area) that toggles it.
* **Content types:** plain (one sentence) · **stat** (value, then a breakdown table: base, faction kit, role, crew,
  equipment, consumables, Field Kit, final; deltas with `Format.delta`) · **item** (name, rarity pip, effect lines,
  price, owned count) · **disabled reason** (why + fix, e.g. "Research Reinforced Tracks first").
* Disabled controls stay focusable so the reason tooltip can be read; activating them plays `ui_error` and shows the
  reason inline.

### 1.8 Loading states, skeletons and pending actions

| Situation | Treatment |
|---|---|
| Screen data not ready | Skeleton blocks in `bg.raised` matching the final layout; one shimmer sweep every 1.2 s (static under reduced motion). Skeletons appear only after **150 ms** to avoid flashes. |
| Profile not yet synced (join) | Boot screen (§S01); no garage screen renders on partial data. |
| Request in flight | The pressed button keeps its width, swaps its label for a 16 px progress bar sweep plus the verb in `-ING` form (`RESEARCHING`), and becomes non-interactive. Other controls stay usable unless they touch the same object. |
| Request > 8 s | Toast "Still working on it…" (no cancel; idempotent). Response timeout at 20 s → `TIMEOUT` copy with RETRY reusing the **same** `requestId`. |
| Robux price unknown | Price slot shows `R$ ···` skeleton; buy button disabled with tooltip "Fetching price". Failure after 2 retries: "Price unavailable" + RETRY. |
| Images (vehicle side art, map art) | Class glyph + tier placeholder until `ContentProvider:PreloadAsync` resolves; fade in 120 ms. |
| Results pending (inbox not drained) | Results skeleton with a 3-step checklist: "Battle finished ✓ · Rewards calculated ✓ · Applying to your profile…". |

No optimistic UI for anything that costs or grants currency; optimistic updates are allowed only for local
preferences (favourite toggle, filters, settings) and roll back with a toast on failure.

### 1.9 Error states

Copy follows B§2: the title says what happened; the body says why and what to do next. Defaults come from
`Net/ErrorCodes.message(code)`; the UI overrides them per context with the table below.

| Code / condition | Title | Body | Action |
|---|---|---|---|
| `INSUFFICIENT_FUNDS` (Credits) | Not enough Credits | You need **12,400** more Credits. | `EXCHANGE BULLION` (if Bullion covers it) · `PLAY A LOWER TIER` hint (D§11) |
| `INSUFFICIENT_FUNDS` (XP) | Not enough XP | You need **2,300** more XP. Use Free XP or earn it in battle. | `USE FREE XP` when it covers the gap |
| `INSUFFICIENT_FUNDS` (Bullion) | Not enough Bullion | You need **400** more Bullion. | `GET BULLION` → Store |
| `CONFLICT` | That changed in the meantime | Your garage was updated elsewhere. We refreshed it. | auto-resync, then RETRY |
| `NOT_ALLOWED` (vehicle locked) | Vehicle in battle | Tukkhald is locked until its battle ends (about 7 min). | `RETURN TO BATTLE` if active |
| `RATE_LIMITED` | Slow down | Please wait a moment and try again. | auto-enabled after the bucket refills |
| `TIMEOUT` / `UNAVAILABLE` | Server busy | The request didn't finish. Nothing was charged. | `RETRY` (same requestId) |
| `LIMIT_REACHED` (purchase limit) | Purchase limit reached | You already own the maximum of this item. | – |
| `VERSION_MISMATCH` | Update available | A new version is out. Rejoin to get it. | system banner |
| Teleport failed (D§19) | Couldn't reach the battle | You're back in the queue at your original place. | automatic re-queue |
| Profile load failed | (server kick message) | "We couldn't load your profile safely. Your data is untouched. Please rejoin in a minute." | Roblox rejoin |
| Disconnect | Roblox's own dialog | – | – |

Inline field errors (text inputs: lineup names, search) appear under the field in `state.danger` with the
`ui/error` glyph; the field border turns `state.danger`.

### 1.10 Empty states

Centered block: 48 px glyph in `text.tertiary`, `h4` title, one `body.s` line, at most one secondary button.

| Where | Title | Line | Action |
|---|---|---|---|
| Carousel / Motor Pool with filters | No vehicles match | Try fewer filters. | `RESET FILTERS` (REG-UI-03) |
| Crew reserve | Reserve empty | Crews you unassign wait here. | – |
| Spare equipment | No spare equipment | Buy equipment or demount it from another vehicle. | `BROWSE` |
| Missions (event tab, no event) | No event running | Check back soon. | – |
| Battle history | No battles yet | Your last 20 battles appear here. | `TO BATTLE` (secondary style) |
| Notifications | All caught up | – | – |
| Friends in HULLDOWN | No friends online here | Invite a friend to join you. | `INVITE` (Roblox prompt) |
| Compare | Nothing to compare | Add up to 6 vehicles. | `ADD VEHICLE` |
| Lineups | No lineups yet | Save the current filter as a lineup. | `NEW LINEUP` |

### 1.11 Number, unit and time formatting (kit `Format`)

| Kind | Rule | Example |
|---|---|---|
| Integers (Credits, XP, HP, damage) | `Format.integer`, comma groups | `12,400` · `1,350` |
| Compact amounts | `Format.compact` only where space is short: carousel badges, Compact top bar, minimap labels. **Never** for prices, ledger lines, HP in the HUD or anything inside a confirmation | `12.4K` · `1.25M` |
| Prices | Icon + full integer; Robux from `GetProductInfoAsync` with the platform Robux glyph | `[B] 3,500` · `R$ 449` |
| Deltas | `Format.delta` with typographic minus (U+2212) and tone; `lowerIsBetter` for reload, aim time, dispersion | `+18 mm` · `−0.4 s` |
| Percent | `Format.percent`, 0 decimals; 1 decimal for win rate and pen chance under 10 % | `64%` · `52.4%` · `3.5%` |
| Units | metric, one space, fixed precision per stat (below) | `54 km/h` · `212 mm` |
| Tier | roman numeral; `Format.tier` in text | `VIII` · `Tier VIII` |
| Battle clock | `Format.clock`, ceil | `11:42` · `0:09` |
| Short timers (reload, cooldown, capture) | `Format.seconds`: one decimal under 10 s, whole above; cooldown slots show whole seconds, ceil | `7.4 s` · `42` |
| Durations | two largest units | `6d 4h` · `4h 12m` · `12m 30s` · `45 s` |
| Relative time | < 60 s `just now`; < 60 min `5 min ago`; < 24 h `3 h ago`; yesterday `Yesterday`; else date | `5 Oct` · `5 Oct 2025` (other years) |
| Clock time | local, 24 h default (setting `ui.clock12h`) | `18:40` |
| Resets | always relative | `Resets in 4h 12m` |
| Large stat counts | full integer up to 9,999,999; compact above in profile cards only | `1,240,512` |

**Stat precision table** (Inspect, Compare, tooltips): HP 0 dp · damage 0 · penetration `mm` 0 · reload `s` 2 dp
under 10 s, 1 dp above · DPM 0 · aim time `s` 2 · dispersion `m` 2 · speed `km/h` 0 · power-to-weight `hp/t` 1 ·
traverse `°/s` 1 · view range `m` 0 · camo `%` 1 · armor `mm` 0 · shell velocity `m/s` 0 · weight `t` 1.

### 1.12 Input model and glyph prompts

**Contexts** (A§10, Input Action System only): `KitUI` (priority 3100, menus: Confirm/Back/Secondary/Tertiary/
TabPrev/TabNext/PagePrev/PageNext/Scoreboard as registered in `InputMode`), `Garage` (1500), `Battle` (2000),
`Sniper` (2100), `Spectate` (2000), `Menu` (3000, modal open). Reserved inputs are never bound: Esc, ButtonStart,
F9, F11, F12, PrintScreen (D§16); F10 is avoided too (Roblox graphics-level hotkey) **O**.

**Menu actions (all screens):**

| Action | KBM | Gamepad | Touch |
|---|---|---|---|
| Confirm / activate | `[Enter]`, `[LMB]` | `[A]` | tap |
| Back | `[Bksp]` | `[B]` | top-bar Back |
| Secondary (screen-defined, e.g. Details) | `[F]` | `[X]` | button |
| Tertiary (screen-defined, e.g. Motor Pool) | `[G]` (`[Space]` on Garage) | `[Y]` | button |
| Tabs prev / next | `[Q]` / `[E]` | `[LB]` / `[RB]` | tap tab, swipe tab bar |
| Page / scroll prev / next | `[Z]` / `[C]`, `[Wheel]`, `[PgUp]`/`[PgDn]` | `[LT]` / `[RT]` (page), right stick (smooth) | drag |
| Navigate | arrows / mouse | left stick, D-pad | – |

**Glyph prompts.** `InputMode.glyph(action)` resolves the current binding: gamepad buttons from
`UserInputService:GetImageForKeyCode` (Xbox or PlayStation art, text fallback), keys as a chamfered keycap
(`bg.inset` fill, 1 px `border.strong`, Builder Mono `label`), mouse as `ui/mouse_*` glyphs (requested, §5.1).
Glyphs swap within one frame of a `PreferredInput` change (REG-INP-02). Touch shows no glyphs.

**Hint bar.** Gamepad and TV only (KBM optional via `ui.hintsKbm`): a 48 px bar along the bottom safe edge,
right-aligned, `label` text, up to 5 hints in priority order (`[A] Select · [B] Back · [X] Details · [Y] Motor pool ·
[LB][RB] Tabs`). It never covers interactive content: screens reserve 48 px at the bottom when it is visible.

**Contexts in the Battle place.** `KitUI` would otherwise sink battle keys: its priority is above `Battle`, and it
binds `[C]` (page), `[Q]` / `[E]` (tabs) and `[F]` / `[G]`. So in the Battle place `KitUI` is enabled only while a
menu has focus (Field menu, Settings subset, a focused Scoreboard, a modal). The rest of the time `Battle`, `Sniper`
or `Spectate` owns every key, and `[Bksp]` / pad `[B]` hold open the Field menu from the `Battle` context. In the Hub,
`Battle` is never enabled. Back is ignored while a `TextBox` has focus, so `[Bksp]` deletes text.

**Roblox core UI (both places, set once on the client at start).**
* `StarterGui:SetCoreGuiEnabled` turns `PlayerList` off, because `[Tab]` is our scoreboard key. It also turns
  `Backpack`, `Health` and `EmotesMenu` off.
* `SetCore("ResetButtonCallback", false)`: there are no characters.
* Chat in the Battle place: `ChatWindowConfiguration.Enabled` on (H-19 slot) and
  `ChatInputBarConfiguration.KeyboardKeyCode = Return`.
* Chat in the Hub: the core chat window is off, so it never covers the rail or the stats panel. The platoon channel
  renders in the Platoon modal (§S23) through `TextChannel` messages, filtered by Roblox, and the core input bar keeps
  its default `/` key. `[Enter]` therefore stays the menu Confirm key in the Hub.

This list is checked in-engine (§5.5).

### 1.13 Controller focus rules

1. `GuiService.GuiNavigationEnabled = true`, `AutoSelectGuiEnabled = false`; focus always starts explicitly.
2. Every screen declares `initialFocus` (listed per screen). Returning to a screen (`show` with reason `return`)
   **restores** the last focused element; if it no longer exists, the nearest sibling in the same list, else
   `initialFocus` (REG-INP-01: after any modal open or close, `SelectedObject ~= nil`).
3. Focus ring (B§8.3): 2 px `accent.dusk_hi` ring offset 2 px plus animated corner brackets (`focusPulse` 0.9 s,
   static under reduced motion); `SelectionImageObject` is the kit `FocusRing` on every selectable.
4. Movement: spatial by default; explicit `NextSelection*` (`Focus.chain` / `Focus.grid`) for carousels, grids,
   tech-tree nodes and tab bars; carousels and grids **do not wrap** horizontally (they page), vertical lists wrap
   only in pickers.
5. **Shoulders (`[LB]`/`[RB]`) switch the screen's top-level tabs** (or faction tabs in the Tech Tree, categories in
   Settings; on the tab-less Garage they select the previous / next vehicle); prompts show shoulder glyphs at both ends of the tab bar (B§8.4). **Triggers (`[LT]`/`[RT]`) page
   the main scroll region** (one viewport minus 10 %), carousels one page of cards; in the Tech Tree they zoom out / in
   (the tree is a canvas, so its "scroll" is panning with the right stick).
6. Right stick scrolls the focused scroll container smoothly (900 px/s at full deflection); on the Garage and
   Inspect screens it orbits the vehicle instead.
7. Scroll-into-view keeps 48 px of context around the focused element (`Focus.revealOffset`).
8. Modals trap focus; drawers trap focus while open (Back closes and returns focus to the tile that opened them).
9. A Studio QA script BFS-walks every screen from `initialFocus` and fails if any selectable is unreachable.

### 1.14 Compact (phone) layout rules

* Compact is chosen **only** by viewport height < 600 px (D§16), never by `DisplaySize.Small` alone; tablets
  stay Regular (with UIScale capped at 1.2).
* Landscape only; the Hub and Battle use `LandscapeSensor`.
* **Touch targets:** menus ≥ 44 rendered px (author 48 at Compact: 44.2 at the 0.92 floor); battle controls
  ≥ 48 rendered px (author **56**: 51.5 at the floor; 52 would render 47.8 and fail). Minimum gap between targets is
  8 rendered px, so author **9**. These follow D§21 #16; REG-UIX-01's 48 px wording applies to battle controls only.
  `hud.scale` and `touch.fireSize` never shrink a touch control below these sizes: below 100 % only the gauges scale.
* Screens collapse in this order: right column → drawer-as-sheet → secondary panels behind a `DETAILS` button →
  two-pane lists become list → detail push.
* Tab bars scroll horizontally with a fade mask; the active tab is scrolled into view.
* Hover-only affordances are forbidden; every tooltip has a tap path (§1.7).
* No interactive element sits under `GuiService.TopbarInset` or outside `CoreUISafeInsets` (REG-UIX-02).
* Text inputs open the platform keyboard; screens shift content up so the field stays visible.

### 1.15 Accessibility

| Feature | Behaviour | Setting / engine |
|---|---|---|
| Colour-vision schemes | Team, platoon and self colours from B§3.4 (default, deuteranopia, protanopia, tritanopia); offered at first launch (§S02). Penetration and module colours switch to the proposed `pen.cb.*` set under a CVD scheme (D§21 #14, pending brand approval). **Shapes never change** (class glyphs, self arrow, platoon pip numbers, ring segment counts, module crack / break outlines). | `a11y.scheme` |
| High contrast | Opaque panels (`PreferredTransparency` forced 0), `text.secondary` → `text.primary`, borders 2 px `border.strong`, HUD plates on 70 % ink backing, markers get 2 px ink outlines, minimap terrain darkened 30 %. | `a11y.highContrast` |
| UI scale | 80–120 % menus (kit), HUD 80–150 % separately (D§16). | `ui.scale`, `hud.scale` |
| Text size | Follows Roblox `PreferredTextSize`; extra in-game boost Follow / +15 % / +30 % applied in Theme to body and labels (never via `TextScaled`). All screens must pass layout tests at +30 % with the largest Roblox preference. | `a11y.textBoost` |
| Transparency | Honours `PreferredTransparency`; in-game panel opacity override 60–100 %. | `ui.panelOpacity` |
| Reduced motion | Honours `ReducedMotionEnabled` (or override On/Off): no slides, pops, pulses, count-ups, camera tweens or shakes; fades ≤ 100 ms (kit `Motion`). | `a11y.reducedMotion` |
| Reduced effects | No camera shake or recoil kick, no full-screen flashes, low-HP vignette capped at 20 %, particle budget −50 % for own vehicle effects, "reduce effects while aiming" forced on. Never more than **3 flashes per second** anywhere (D§16). | `a11y.reducedEffects` |
| Captions | Crew callouts and radio commands captioned (D§17): bottom-centre, max 2 lines, 30 % ink backing, speaker glyph (crew role or radio), 4 s each, queue of 3 mirroring the callout queue. Offered at first launch. | `a11y.captions` Off / Crew / Crew + radio |
| Sound visualisation | Directional edge glyphs for audible gunfire ≤ 300 m (calibre class glyph size S/M/L), shell flybys (near-miss arc), incoming artillery (1 s warning ring), capture alarm (flashing base marker). Never for sounds the player could not hear, and never for engines of unspotted vehicles (D§16, AU§4.7). | `a11y.soundViz` |
| Visual twins | Every gameplay-critical sound has a visual event (AU§7): spotted alert → crest chevron (not a lamp, D§21 #12); armor result → callout text; low HP → vignette; reload complete → reticle arc flash. | always |
| Mono audio, night mode, device preset | AU§7. | `audio.*` |
| Input | Full remapping (KBM and gamepad), hold/toggle for sniper, free look and info overlay; sensitivities; invert Y; FOV 60–90; deadzones (§S22). | `ctl.*`, `pad.*` |
| Hold-to-confirm | Duration 1.2 s, adjustable 0.6–2.0 s; can be replaced by a two-step confirm. | `a11y.holdConfirm` |
| Focus visibility | Focus ring always visible on gamepad and keyboard navigation; never colour-only. | always |
| Timing | No UI requires a response faster than 3 s, except battle gameplay. Platoon invites last 30 s and stay in the center afterwards. | always |

### 1.16 UI sound mapping (keys from AU§10; kit `Sound`)

| UI event | Key | Rule |
|---|---|---|
| Pointer or gamepad focus enters an interactive element | `ui_hover` | 1 voice, restart (AU§3.2); not on initial focus, not while scrolling faster than 6 items/s |
| Button press | `ui_click` | Not for buttons that play their own result sound |
| Back / cancel / dismiss | `ui_back` | |
| Confirm / apply / mount / assign | `ui_confirm` | |
| Error, disabled activation, insufficient funds | `ui_error` | |
| Toggle on / off | `ui_toggle_on` / `ui_toggle_off` | |
| Tab or carousel page change | `ui_tab_switch` | |
| Slider step | `ui_slider_tick` | ≤ 30/s (AU§3.2) |
| Drawer, modal, panel open / close | `ui_open_panel` / `ui_close_panel` | |
| Toast arrives | `ui_notification` | One per 1.5 s max; batched toasts share one |
| Purchase complete (any currency) | `ui_purchase` | |
| Research complete (module or vehicle) | `ui_research_complete` | |
| Vehicle bought / unlocked | `ui_vehicle_unlocked` | Ducks music (AU§3.3) |
| Crew perk slot ready, pass stage, account rank up | `ui_level_up` | |
| Mission complete / claimed | `ui_mission_complete` | |
| Achievement earned | `ui_achievement_unlocked` | |
| Battle found | `ui_battle_found` + `hangar_pa_chime` | |
| Countdown seconds 3, 2, 1 / GO | `ui_countdown_tick` / `ui_countdown_go` | GO aligned with the music downbeat (AU§11) |

Battle cues (`cue_*`) and radio commands (`radio_cmd_*`) are mapped in §S31–§S33. UI sounds never play from
programmatic state changes (patches, resyncs), only from the player's own actions and from arriving events.

### 1.17 UI performance budgets **O** (inside D§18 frame budgets)

| Budget | Mobile | PC / console |
|---|---|---|
| UI Luau per frame in battle (HUD + markers overlay) | ≤ 1.5 ms | ≤ 0.8 ms |
| UI Luau per frame in garage (excluding hangar render) | ≤ 2.0 ms | ≤ 1.2 ms |
| Live `GuiObject`s, garage screen | ≤ 1,800 | ≤ 3,000 |
| Live `GuiObject`s, battle HUD (incl. 30 pooled markers) | ≤ 900 | ≤ 1,400 |
| `ViewportFrame`s (D§18) | ≤ 2 | ≤ 6 |
| `CanvasGroup`s (D§18) | ≤ 1 | ≤ 3 |
| HUD numeric refresh | 10 Hz for timers and counters; per frame only for reticle, markers and reload arc | same |

Rules: no per-frame table allocation in HUD code (A§3.11); list views use `VirtualList` (pool = visible + 4);
markers are one pooled overlay updated in `PreRender` (D§16); 3D in UI is the shared hangar scene, not
`ViewportFrame`s, except crew portraits fallback and the Results vehicle card (§S38).

---

## 2. Screen specifications

Rectangles are in **full-screen reference px** (1920 × 1080 or 844 × 390). On Regular screens the `TopBar` row is
y 0–56 and the `Screens` safe area starts below it; on Compact the core row is about 44–48 px. "Hint bar" means the
48 px gamepad hint strip (§1.12), reserved only when visible.

### S01 Boot and profile load (`ReplicatedFirst/Loading`, Loading layer)

**Purpose.** Cover the join from Roblox's loading screen to a fully synced `ProfileView`, honestly reporting the
session-lock wait (D§19). **Entry:** join. **Exit:** First launch (§S02) if flags are unset, else Main menu (§S03),
else straight to Garage when arriving from a battle (`TeleportService:GetLocalPlayerTeleportData` carries no trust,
only the hint "returning").

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                              │
│                        [ loading_logo.svg: ridge, dusk sun, turret, HULLDOWN ]               │
│                                                                                              │
│                                                                                              │
│                         ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬            │
│                         Loading your profile…                         64%                    │
│                                                                                              │
│                  TIP  Angle your hull 20–30° to a threat: thicker effective armor.           │
│ v0.9.3 · EU                                                                       [tool glyph]│
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Element | Rect | Notes |
|---|---|---|
| Backdrop | full | `bg.abyss` + 25 % ink vignette |
| Logo | (448, 180, 1024, 360) | `loading_logo.svg`, never below 640 px wide (B§5.3) |
| Progress bar | (560, 640, 800, 4) | `accent.dusk` on `bg.inset`; determinate while preloading, indeterminate sweep while waiting on the server |
| Status line | (560, 656, 800, 24) | `body`, percentage right-aligned in `mono` |
| Tip | (360, 760, 1200, 56) | `body.s` `text.secondary`, `label` "TIP" in `brand.khaki`; rotates every 6 s |
| Version / region | (24, 1036, 400, 20) | `caption` `text.tertiary` |

**States (status line copy):** `Connecting` → `Loading assets` (fonts, icon atlases, UI sounds,
`ContentProvider:PreloadAsync`) → `Loading your profile` → *lock conflict* `Another server is still saving your
profile. Waiting (12 s)…` → *after 40 s* `Taking over your session…` → `Ready`. A profile that fails to load is
never played on (D§19): the server kicks at 120 s with the copy in §1.9. Compact: logo 560 wide, the tip hides.
**Acceptance:** the screen never shows a percentage that goes backwards; the lock-wait timer matches the server's
attempt schedule (5 s, then every 10 s); no garage UI is visible before the full `DataSync` view applied; cold join
to Garage interactive ≤ 8 s p50 on PC and ≤ 14 s p50 on the mobile baseline (excluding Roblox's own join).

### S02 First launch (`Screens/FirstLaunch`, modal sequence)

**Purpose.** Set the two accessibility choices D§16 requires before the first battle, then offer the Proving Field.
Shown once per account (flags `colorSchemePrompted`, `captionsPrompted`; `→ AckFlag`).

1. **Team colours.** Four cards 400 × 300 in a row (Default, Deuteranopia, Protanopia, Tritanopia). Each card
   shows the same static mini-scene: three ally markers, two enemy markers, one platoon marker with pip `2`, the self
   arrow, and a minimap crop, all tinted with that scheme. Title "Choose team colours", body "You can change this any
   time in Settings › Accessibility." Initial focus: Default. `[A]` selects; `CONTINUE` primary.
2. **Captions.** Two cards: "Captions on" (sample caption "[Crew] Engine damaged") / "Captions off". Default off.
3. **Controls check** (gamepad or touch detected): one panel showing the detected scheme with `CHANGE` and `CONTINUE`.
4. **Proving Field offer** (`PV.account.flags.bootcampCompleted == false`): "New to armored command? Three short drills
   teach driving, firing and spotting." `START PROVING FIELD` (primary) · `GO TO GARAGE`.

**Acceptance:** each step is skippable with Back except step 1 (Back = keep Default and continue); choices persist
to `ST` before the next step renders; the whole sequence is reachable by gamepad and touch.

### S03 Main menu / title (`Screens/MainMenu`)

**Purpose.** A brief branded arrival over the cinematic hangar; it is not a login (Roblox authenticates).
**Entry:** after Boot on a fresh join (setting `ui.titleScreen`, default on). **Exit:** Garage, Proving Field,
Settings, or Return to battle.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ [Roblox row]                                                                                 │
│                         (camera dolly: hangar door opening onto the dusk ridge)              │
│      ╔═══════════════════════╗                                                               │
│      ║ HULLDOWN logo_primary ║                                                               │
│      ╚═══════════════════════╝                                                               │
│                                                                                              │
│      ▶ [ PLAY                ]   ← primary (or RETURN TO BATTLE)                             │
│        [ PROVING FIELD       ]   Recommended for new commanders                              │
│        [ SETTINGS            ]                                                               │
│        [ ABOUT               ]                                                               │
│                                                                                              │
│      Signed in as RidgeRunner_07 · Region EU                                                 │
│ v0.9.3                                                                    [A] Select [B] Menu │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Element | Rect | Notes |
|---|---|---|
| Letterbox bars | (0, 0, 1920, 96) and (0, 984, 1920, 96) | `bg.abyss`, removed when Garage loads (300 ms) |
| Logo | (120, 220, 640, 160) | `logo_primary.svg` with a `bg.scrim` band behind (B§5.4) |
| Menu list | (120, 440, 440, 4 × 64) | Primary CTA 440 × 56 first, then secondary buttons 440 × 48, 16 px gaps. `ABOUT` opens credits and licences (never labelled "Credits", which is a currency name) |
| Account line | (120, 760, 640, 24) | `caption` |

**Camera:** a 12 s scripted dolly from the hangar interior to the open door and the selected vehicle, then a slow
idle orbit; reduced motion uses a static hero frame. Music `GARAGE` cue starts here (AU§11).
**Return to battle:** when `PV.activeBattle` is set and its manifest is still live, PLAY becomes `RETURN TO BATTLE`
(primary, dusk) with the line "Your Tukkhald is still fighting on Cinder Valley (6:12 left)" (`→ ReturnToBattle`).
**Controller:** initial focus = first button; `[A]` activate; `[B]` = no-op (top level).
**Compact:** logo 320 wide at (24, 56); buttons 300 × 48 stacked at (24, 160); letterbox off.
**Acceptance:** any input skips the dolly to its last frame within 1 frame; PLAY works within 200 ms of the profile
being ready (the Garage is pre-mounted behind the title).

### S04 Garage hub (`Screens/Garage`, keepAlive, camera preset `hero`)

**Purpose.** The home screen: see and select the vehicle, service it, see what to do today, and launch a battle.

```
┌[Roblox]──┬[‹]GARAGE ┊[⚙][VIII][⬢] TUKKHALD  Versatile ▬▬▬▬▬▬▬▬▱▱ 12,400/21,000 ┊[C]12,400,550[+][B]3,250[+][FX]18,240[T]310┊👥3 🔔2 [rank]RidgeRunner ┐
├──────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┬──────────────────────┤
│▣ GARAGE  │            [ OPEN TRIALS ▾ ]  [■■■■ TO BATTLE ■■■■]  [you][ + ][ + ]                                       │ DAILY      Resets 4h │
│▤ TECH    │                              ×2 first win available                                                          │ ┌─────────────────┐  │
│◉ CREW  • │ ┌ VEHICLE ─────────────┐                                                                                     │ │◆ Easy  Deal 1,500│  │
│✎ MISSIONS│ │ Heavy · Versatile    │                                                                                     │ │  ▬▬▬▱▱  900/1,500│  │
│▲ PASS  3 │ │ HP          1,620    │                    (3D hangar: the selected vehicle, hero camera)                   │ └─────────────────┘  │
│⛟ STORE • │ │ Damage    358 ×2     │                                                                                     │  … Medium, Hard      │
│⌂ PROFILE │ │ Penetration  195 mm  │                                                                                     │ PASS  Stage 12 ▬▬▱  │
│⚙ SETTINGS│ │ Reload      25.7 s   │                                                                                     │ EVENT  Ember Week    │
│          │ │ Aim time    2.9 s    │                                                                                     │                      │
│          │ │ Speed       40 km/h  │                                                                                     │                      │
│          │ │ View range  361 m    │                                                                                     │                      │
│          │ │ DETAILS ›            │                                                                                     │                      │
│          │ └──────────────────────┘                                                                                     │                      │
│          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────┴──────────────────────┤
│          │ [⚙ MODULES  Top config] [▣ EQUIPMENT 3/3] [▮ AMMO 42/45 · Auto] [✚ CONSUMABLES 3/3] [◉ CREW 4/4 • perk] [✎ APPEARANCE]            │
│          ├───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│          │ [⫶ FILTERS 23/89] [Iron Union ×] [VIII ×]  [Sort: Tier ▾] [▤ 1 row]  [LINEUPS ▾]                       [⊞ MOTOR POOL  Space]   │
│          │ ‹ [card][card][CARD▌][card][card][card][card][card][card][car ›                                                                    │
└──────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Layout (1 carousel row, Regular).** Rectangles at 1920 × 1080; the formulas give the run-time position for any
canvas W × H (§1.1.1) and reproduce the 1080p values exactly.

| Region | Rect at 1080p | Anchored formula | Content |
|---|---|---|---|
| Top bar | (0, 0, 1920, 56) | full width, `TopBar` layer | §1.4, center slot = vehicle identity |
| Nav rail | (0, 56, 120, 1024) | (0, 56, 120, H − 56) | §1.2 |
| Battle cluster | (604, 72, 728, 64) | centred on TO BATTLE | Mode selector (W/2 − 356, 72, 208, 64) · TO BATTLE (W/2 − 140, 72, 280, 64) · platoon strip (W/2 + 148, 72, 224, 64). Details in §S06. |
| Queue / bonus line | (820, 140, 280, 24) | (W/2 − 140, 140, 280, 24) | `caption` centred: `×2 first win available` (XP glyph) / queue status / disabled reason |
| Carousel cards | (144, 880, 1752, 104) | (144, H − 200, W − 168, 104) | §S05 |
| Carousel header | (144, 832, 1752, 40) | (144, cardsY − 48, W − 168, 40) | Filters button, active filter chips, sort, rows toggle, lineups, Motor Pool |
| Service strip | (144, 744, 1752, 72) | (144, stripY = cardsY − 136, W − 168, 72) | 6 tiles, width (W − 238) / 6 (280 at 1080p), 14 px gaps (§S04.2) |
| Stats panel | (144, 248, 360, 456) | top = max(stripY − 496, 180); bottom = stripY − 40 | §S04.1; rows shown = min(8, ⌊(height − 72) / 48⌋), ≥ 3 at the 800 px minimum |
| Right column | (1560, 72, 336, 656) | (W − 360, 72, 336, stripY − 88); hidden when W < 1,496 | Dailies 360 · Pass card 112 · Event card 152, 16 px gaps; cards that do not fit drop from the bottom (event, then pass) |
| Hint bar | (0, 1032, 1920, 48) | (0, H − 48, W, 48) | gamepad only; cards end 48 px above it |

**Two carousel rows** (`garage.rows = 2`, offered when H ≥ 1,000): cards (144, H − 312, W − 168, 216); the strip
and stats panel follow the same formulas. At 1080p that puts the strip at y 632, gives the stats panel 7 rows, and
leaves dailies + pass in the right column. These formulas were checked for overlaps at H 800–1,800 and aspect
ratios 5:4 to 21:9 (one and two rows).

**Service strip vs D§16.** D§16 says the six strip items open drawers. Modules, Equipment, Ammo and Consumables do.
**Crew** (perk board, reserve) and **Appearance** (preview, cart) open full screens (**O**), because a 624 px
drawer cannot hold them. Tapping the tile is still the only step.

#### S04.1 Stats panel

`Panel` with title `label` "VEHICLE" and the class · role line (`body.s`, class glyph 20, role badge). Eight
`StatRow`s (48 px): label `label` `text.secondary`, value `num.m`, a 120 × 4 bar normalised to the tier/class range
(min..max of the same tier and class in `CR`). Rows: HP · Damage (α; magazines show `358 ×4`, dual guns `358 ×2`) ·
Penetration (standard shell at 100 m) · Reload (or DPM toggle by clicking the label) · Aim time · Dispersion at
100 m · Top speed · View range. Each row has a stat tooltip (§1.7) with the full breakdown. Values come from
`StatsCalculator(vehicle, PV loadout incl. crew, equipment, consumables, Field Kit)` (REG-UI-01, REG-UI-07). If the
mounted configuration is not the top one, a `caption` link "Stock modules mounted · RESEARCH ›" appears in
`state.warning`. `DETAILS ›` opens Inspect (§S08).

#### S04.2 Service strip tiles

| Tile | Glyph | Status line (binding) | Opens | Badge / warning |
|---|---|---|---|---|
| MODULES | `ui/upgrade` | `Top configuration` / `2 upgrades available` (`ResearchGraph`) | Modules drawer (§S07) → Research (§S09) | dot when an upgrade is researchable |
| EQUIPMENT | `ui/equipment` | `3/3` mounted (`PV.vehicles[id].equipment`) | Equipment drawer (§S14) | `state.warning` when a slot is empty |
| AMMO | `ui/ammo` | `42/45 · Auto` (loaded / capacity, auto-resupply) | Ammo drawer (§S15) | `state.danger` when 0 shells (blocks battle) |
| CONSUMABLES | `ui/consumables` | `3/3` | Consumables drawer (§S16) | `state.warning` when empty slots |
| CREW | `ui/crew` | `4/4 · perk ready` | Crew (§S13, full screen) | badge = members with a free perk slot; `state.danger` "No crew" blocks battle |
| APPEARANCE | `ui/exterior` | style or paint name | Exterior (§S17, full screen) | – |

Each tile is 280 × 72: glyph 32 at left, `label` title, `caption` status; hover lifts to `bg.selected`; focus ring;
the tile whose drawer is open gets the 2 px dusk left edge (B§8.2 selected card).

#### S04.3 Right column

* **Dailies:** header `label` `DAILY` + `caption` "Resets in 4h 12m"; three `MissionCard`s 336 × 96 (difficulty pip,
  name `body.s` Bold, condition line, progress bar 200 × 4 + `mono` value, reward icons 20 px). A claimable mission
  shows `CLAIM` (secondary, compact) and the mission-complete verdant tick. Missions whose scope excludes the selected
  vehicle are dimmed to 60 % with a `caption` "Needs Tier V+ medium" (scope from `MissionDefinition.scope`). Bonus
  mission appears as a fourth card when unlocked. Click → Missions (§S18).
* **Pass card:** season name, stage `num.m` "12 / 90", progress to the next stage, claimable count badge.
* **Event card:** only while an event runs; event art 336 × 96, name, "Ends in 3d 4h", `VIEW`.

**Data bindings:** `SS.selectedVehicleId` (persisted to `ST.garage.selected`), `PV.vehicles`, `PV.crews`,
`PV.currencies`, `PV.missions.daily`, `PV.pass`, `CR` events, `SS.queue`, `SS.platoon`, `PV.activeBattle`.

**States.** `Ready` · `Queued` (§S06: the queued vehicle is locked; selecting another vehicle while queued asks
"Leave the queue to switch vehicles?") ·
`InBattle` (vehicle locked: lock glyph over the card, service tiles read-only with tooltip "Locked until its battle
ends", REG-UI-02) · `NoCrew` · `NoAmmo` · `Loading` (skeleton for panels on first mount only).

**Controller map:**

| Input | Action |
|---|---|
| Left stick / D-pad | Move focus: battle cluster ↔ stats ↔ service strip ↔ carousel ↔ right column |
| `[A]` | Activate focused element |
| `[Y]` | Motor Pool (§S05) |
| `[X]` | Details: Inspect for the selected vehicle |
| `[LT]` / `[RT]` | Carousel page left / right (from anywhere on the screen) |
| `[LB]` / `[RB]` | Previous / next vehicle in carousel order (selection changes, focus stays) |
| Right stick | Orbit the hangar camera (yaw ±180°, pitch −5…+35°); `[R3]` resets |
| `[View]` | Open Notifications |
| `[B]` | Game menu |

**Initial focus:** `TO BATTLE` when enabled, else the blocking service tile (Crew or Ammo).

**Compact (844 × 390; W = 693–870):** rail 64 px; top bar center slot shows name + tier only; no right column
(missions via rail).
* Stats sit behind a `STATS` button (72, 56, 96, 48) that opens a sheet.
* The service strip is six 48 × 48 icon buttons at (72, 229), with 9 px gaps.
* Carousel: one row of 128 × 80 cards at (72, 286, W − 293, 80), i.e. 551 wide at 844 (4 cards) and 400 at 693
  (3 cards).
* Right-anchored launcher (D§16): mode selector (W − 212, 253, 188, 48), `TO BATTLE` (W − 212, 310, 188, 56) and a
  `PLATOON 1/3` button (W − 269, 253, 48, 48), all with 9 px gaps.
* The Compact bottom margin is 24 px.
**TV:** same as Regular at × 1.25 with 5 % margins; the right column drops the event card; carousel shows 7 cards.

**Acceptance criteria.**
1. Stats panel equals `StatsCalculator(selected, loadout)` for 1,000 random selection changes (REG-UI-01).
2. Selecting a vehicle updates the 3D model, name, stats and service tiles in one frame after the model is ready;
   the model swap completes ≤ 250 ms on PC (template clone) with the previous model kept until then.
3. A locked vehicle cannot be sold, modified or queued again (REG-UI-02).
4. Every interactive element is reachable from `initialFocus` with the D-pad (QA BFS script).
5. No element overlaps another at any R-UI-1 resolution; Compact touch targets ≥ 44 rendered px.
6. Currency counters reflect a patch within one frame of applying it; count-ups never show a value above the final.

### S05 Carousel, filters and Motor Pool (`Screens/Carousel`, `Screens/Carousel/MotorPool`)

**Carousel card** (`VehicleCard`, 168 × 104 Regular, 128 × 80 Compact):

```
┌────────────────────────┐   tier plate 20 (top-left) · class glyph 16 + faction emblem 16 (top-right)
│VIII             ⬢ ⚙   │   side silhouette 152 × 56 (assets/vehicles/<id>_side.png, §5.1; fallback class glyph)
│     ▄▄█████▄▄▄═══      │   name: body.s Bold, 1 line, ellipsis; premium = name in currency.bullion tint,
│   ◉◉◉◉◉◉◉◉◉◉          │         class glyph gold (B§6.5); elite = class glyph dusk
│TUKKHALD          🔖 ×2 │   bottom-right: favourite ribbon, first-win ×2 chip, mastery badge 16
└────────────────────────┘   overlays: lock (in battle / queued), "!" no crew, ammo empty, research dot
```

States: default `bg.raised` · hover `bg.selected` + `border.strong` · **selected** `bg.selected` + 2 px dusk left
edge · not owned (researched or locked, shown only when the filter includes them) 60 % opacity with price or XP cost
replacing the name row · in battle: 40 % ink veil + `ui/lock` + `mono` time left.

**Filters drawer** (`[⫶ FILTERS 23/89]`, opens upward over the carousel, 880 × 480, Regular):

| Group | Control | Options |
|---|---|---|
| Faction | 6 toggle chips with emblem + name | the six factions |
| Tier | 11 toggle chips I–XI | multi-select; `I–V`, `VI–VIII`, `IX–XI` quick chips |
| Class | 5 chips with class glyphs | Light, Medium, Heavy, Destroyer, Artillery |
| Ownership | segmented: `OWNED` (default) · `RESEARCHED` · `ALL` | `ALL` includes locked ones |
| Type | toggles | Premium · Elite · Favourites · Ready (crew + ammo, not locked) · First win ×2 available |
| Search | text field | name contains (case-insensitive) |
| Footer | `RESET` (tertiary) · `SAVE AS LINEUP` (secondary) · count "23 of 89" | |

**Sorts** (dropdown): Tier (desc, default) · Class · Faction · Name · Last played · Battles played · Mastery.
Ties break by vehicleId so the order is stable (REG-UI-03). Filter and sort state persist in `ST.garage.filters`
(encoded string) across battles and rejoin.

**Lineups** (D§16 "share-code playlists"): up to **5** user lineups, each a name (≤ 24 chars, filtered with
`TextService:FilterStringAsync` before display to others; lineups are private, so filtering applies only when shared)
and ≤ 100 vehicle ids. Stored as `ST.garage.lineup1..5` share codes: `HDL1:` + base64 of the ordered short ids. Menu:
apply · rename · delete · `COPY CODE` (copies to a read-only text box the player can select; Roblox has no
clipboard API) · `IMPORT CODE` (paste into a text box; invalid ids are dropped with a count "3 vehicles not
available").

**Virtualization.** `VirtualList` horizontal: pool of visible + 4 cards (≈ 15 on PC), recycled by index; the scroll
position snaps to card boundaries; selection is keyed by `vehicleId` and survives buy, sell and re-sort; a sold
selected vehicle falls back to its nearest neighbour (REG-UI-04). Paging buttons `‹ ›` at both ends (32 × 104).

**Motor Pool** (`[Space]` / `[Y]` / button; full-screen drill-in): a grid of the same cards at 8 columns on
1920 (Compact: 5 columns of 128 × 80), filters as a left panel (360 px, always open), sort and search in the
header, a footer showing the selected vehicle and `SELECT` (primary). Initial focus: the selected vehicle's card.
`[LT]/[RT]` page the grid; `[X]` Inspect; `[Y]` toggles favourite.

**Acceptance:** 200 vehicles scroll at 60 FPS on PC and 30 FPS on the mobile baseline with ≤ 20 live cards;
filters and sorts persist through a battle and rejoin; empty result shows `RESET FILTERS`; import of a code with
unknown ids never errors.

### S06 Battle launcher: mode selector, queue and platoon strip (part of `Screens/Garage`)

**Mode selector** (208 × 64, secondary style with `chevron_down`): opens a dropdown panel 480 × auto:

| Row | Content | Availability |
|---|---|---|
| `OPEN TRIALS` | 15 v 15, "Contest, Crossroads, Breach" + battle-type opt-out toggles (Crossroads and Breach from Tier IV, D§8; opt-outs lower their weight, never remove them; binds `PV.matchmaking.battleTypeOptOuts`) and `MAP PREFERENCES ›` (modal §1.6.1: blacklist 1 slot, 2 with Premium Time, once ≥ 8 maps exist; binds `PV.matchmaking.mapBlacklist`, `LIMITS.MAP_BLACKLIST`). Both write `→ SetMatchmakingPrefs`. | always |
| `DRILL` | "Versus bots. Rewards ×0.75." | always |
| `PROVING FIELD` | "Guided drills" | always; badge until completed |
| Event mode(s) | event name, art strip, time left; Ranked events add the player's ladder rank chip (`PV.events[id].ranked.rank`) | while live |
| `PRIVATE TRIAL` | "Create or join a room" | P2 |

Selecting a row closes the dropdown and updates the button label. The selection persists in `ST.gp.mode`.

**TO BATTLE button** (280 × 64, primary CTA, B§8.3) state machine:

| State | Label / look | Line under (820, 140) | Action |
|---|---|---|---|
| `Ready` | `TO BATTLE` dusk | `×2 first win available` if the vehicle has it | `→ QueueJoin` |
| `Blocked` | disabled, `bg.raised` | reason + fix: `Assign a crew` · `Load ammunition` · `Platoon not ready (1/3)` · `Platoon tiers differ` · `Queue locked 8:12` (D§9) | focus shows tooltip; `[A]` jumps to the fix (opens Crew / Ammo / Platoon) |
| `Joining` | `TO BATTLE` with progress sweep | `Joining queue…` | – |
| `Queued` | `CANCEL` (secondary style, same size) + `mono` elapsed `0:23` inside the button's right side | `Est. wait 0:40 · Bots fill after 0:45` | `CANCEL` → `QueueLeave` |
| `Queued ≥ 15 s` | as above | + `START NOW WITH BOTS` tertiary link (D§8 "Start now with bots from 15 s") | `→ QueueStartWithBots` |
| `Found` | `BATTLE FOUND` (dusk, non-interactive) | map name + battle type | `ui_battle_found`, `hangar_pa_chime`; 1.0 s later → Deploying (§S28) |
| `Requeued` | back to `Queued` | toast "Couldn't reach the battle. You're back in the queue at your original place." | automatic (D§19) |
| `ReturnToBattle` | `RETURN TO BATTLE` dusk | "Cinder Valley · 6:12 left" | `→ ReturnToBattle` |

Queue state comes from `QueueState` (`state, enqueuedAt, estimateS, botFillAt, canStartWithBots`); the elapsed
timer is computed locally from `enqueuedAt`. While queued, the vehicle card shows the lock, the service strip is
read-only, and `[B]` on the Garage root asks "Leave the queue?" before opening the Game menu.

**Platoon strip** (3 slots 64 × 64, 16 px gaps): slot 1 = you; empty slots show `ui/plus` "Invite". Occupied
slots: Roblox headshot (`Players:GetUserThumbnailAsync`, 48 px, chamfer mask), leader circlet (`ui/crown_leader`)
on the leader, ready glyph (`ui/ready` verdant / `ui/not_ready` `text.tertiary`) bottom-right, tier numeral + class
glyph of their selected vehicle below (`micro`). Rule violations (D§8: ≤ 3, same tier, ≤ 1 artillery) outline the
offending slot in `state.warning` with a tooltip. Click → Platoon panel (§S23). Only the leader's TO BATTLE is
active; members see `READY` / `NOT READY` toggle in its place (`→ PlatoonReady`).

**Acceptance:** the button's state is a pure function of `(SS.queue, SS.platoon, selected vehicle record,
PV.moderation.queueLockedUntil, PV.activeBattle)`; every blocked state names its fix; queue cancel is available
within 100 ms of joining; the elapsed timer never resets on requeue (it uses the original `enqueuedAt`).

### S07 Service drawers (pattern for Modules, Equipment, Ammo, Consumables)

Drawers slide in from the right edge over the right column, below the battle cluster and above the service strip,
leaving the vehicle, the strip and the carousel visible.

| Property | Regular | Compact |
|---|---|---|
| Rect | (1272, 152, 624, 584) | bottom sheet (0, 120, 844, 270) |
| Header | 64 px: tile glyph 32, `h3` title, vehicle name `caption`, close `ui/close` | 48 px |
| Body | scroll region, 24 px padding | scroll region |
| Footer | 80 px: totals / cost line left, buttons right | 56 px |

* Drawers that edit a **batch** (Ammo) have `APPLY` (primary) and `REVERT`; leaving with unapplied changes asks.
* Drawers that perform **immediate** actions (mount, buy, demount) apply per item with a per-item pending state.
* The camera preset stays `hero` but pans 12 % left so the vehicle is not under the drawer.
* Back closes the drawer (screen `onBack`); focus returns to the tile. Initial focus is the first slot.
* Only one drawer at a time; opening another tile swaps the drawer content with a 120 ms cross-fade.

### S08 Vehicle Inspect (`Screens/VehicleInspect`, drill-in; camera presets `inspect`, `xray`)

**Purpose.** Everything about one vehicle: stats with configuration comparison, rotate/zoom, internal module and
crew positions, armor (§S12), research (§S09), lore. Opened from the stats panel, the top-bar center slot, the
carousel (`[X]`), the Tech Tree node panel, Compare and Results. Works for **any** vehicle in `CR`, owned or not.

```
┌[‹] INSPECT ┊ [⚙][VIII][⬢] TUKKHALD · Heavy · Versatile · Iron Union ┊ …currencies…                         ┐
├────────────────────────┬───────────────────────────────────────────────────────────────┬──────────────────┤
│ CONFIG [STOCK|CURRENT|TOP]│                                                            │ OVERVIEW         │
│ FIREPOWER              │                                                               │ Twin-gun debut:  │
│  Damage   358 ×2  +40  │                                                               │ strong turret…   │
│  Pen      195/244/179  │             (3D vehicle, free orbit / x-ray)                 │                  │
│  Reload   25.7 s       │                                                               │ MECHANIC         │
│  DPM      1,671        │                                                               │ Dual gun: …      │
│ SURVIVABILITY          │                                                               │                  │
│  HP 1,620 · Hull 136/80/50│                                                            │ RESEARCH         │
│ MOBILITY               │                                                               │ From: Varrhald   │
│  40 km/h · 13.9 hp/t   │                                                               │ Leads to: …      │
│ SPOTTING               │                                                               │                  │
│  VR 361 m · Camo 5.0%  │                                                               │ [COMPARE] [⚙ RESEARCH]│
├────────────────────────┴─────────[ EXTERIOR | MODULES | CREW | ARMOR ]──────────────────┴──────────────────┤
│                                                [ BUY [C] 1,400,000 ] or [ RESEARCH [XP] 13,500 ]           │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Stats panel | (144, 72, 440, 880) | Config segmented control (`STOCK` / `CURRENT` (owned only) / `TOP`); four groups with `StatRow`s; deltas vs the other config in `Format.delta` with ▲/▼ glyphs (B§3.3 never colour-only) |
| Viewport | full screen behind; interactive zone (600, 72, 920, 880) | Orbit: drag / right stick; zoom: wheel / pinch / `[LT]`-`[RT]`; double-click / `[R3]` reset |
| Info panel | (1536, 72, 360, 880) | Tabs `OVERVIEW` (combat identity, mechanic, role, faction kit), `LORE` (roster lore), `RESEARCH` (parents, children, module status) |
| View switch | (760, 968, 600, 48) | Segmented: `EXTERIOR` · `MODULES` · `CREW` · `ARMOR` (ARMOR pushes §S12 in place) |
| CTA | (1536, 968, 360, 56) | One primary: `BUY` (researched, not owned) / `RESEARCH` / `SELECT` (owned, not selected) / `BUY BACK` (sold < 72 h) / none; an overflow `⋯` 44 × 44 left of it holds `SELL`, `MAKE PLUS VEHICLE` (subscribers), `FAVOURITE` (§1.6.1) |

**Stats groups and rows** (full set; Garage shows 8): *Firepower*: damage (per shell type), penetration (each shell,
at 100 m and 500 m for AP/APCR falloff), reload / DPM, magazine (shells, intra-clip, reload), aim time, dispersion
at 100 m, dispersion modifiers (moving, hull traverse, turret traverse, after shot), gun depression / elevation,
shell velocity. *Survivability*: HP, hull armor F/S/R, turret armor F/S/R, module HP highlights, fire chance (engine
type). *Mobility*: top speed fwd/rev, power, power-to-weight, hull traverse, turret traverse, terrain resistance
(hard/medium/soft), weight / load limit. *Spotting*: view range, concealment still / moving / after firing.

**MODULES view (x-ray).** Exterior parts fade to 20 % (client-side transparency on the Visual layer), internal module
volumes render as tinted solids from the Blueprint (`layer = Module`): engine, ammo rack, fuel tank, gun breech,
turret ring, optics, plus both track runs. Each module gets a callout: module glyph 24 (B§6.8 normal state), name,
HP. Hover / focus a callout: tooltip with HP, "Damaged: power ×0.5 · Destroyed: immobile" (D§2 effects), repair time
from destroyed (D§2), fire chance for engine and fuel. Gamepad: D-pad cycles callouts.

**CREW view.** Same x-ray with crew seat markers: role glyph 32 (B§6.8 crew), member name; tooltip with role(s),
perks and training; `OPEN CREW ›` pushes §S13.

**Controller:** initial focus = config control; `[LB]/[RB]` cycle the view switch; `[X]` toggles the info tabs;
`[Y]` Compare (adds to `SS.compareList` and opens §S11).
**Compact:** stats become a sheet behind a `STATS` button; the info panel becomes a second sheet; view switch as
icon-only segmented control 4 × 48 at the bottom-left; CTA bottom-right 188 × 52.
**Acceptance:** stats for STOCK / TOP equal `StatsCalculator` with the stock / top configuration and the current
crew (REG-UI-07); x-ray module positions come from the same Blueprint the server uses (no separate authoring);
opening Inspect for an unowned vehicle never mounts or buys anything.

### S09 Research: module tree, Field Kits and Apex nodes (`Screens/Research`, drill-in)

**Purpose.** Research and mount a vehicle's modules (Gun, Turret where meaningful, Engine, Tracks; no radio, D§7.4)
and unlock the next vehicles; then Field Kits (elite) or Apex nodes (Tier XI). **Entry:** Modules drawer
`OPEN RESEARCH`, Inspect info panel, Tech Tree node panel. **Exit:** Back.

```
┌[‹] RESEARCH ┊ TUKKHALD · Tier VIII ┊ [XP] 12,400 on vehicle · [FX] 18,240 Free XP                          ┐
├──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ [ MODULES | FIELD KITS ]                                                                                  │
│                                                                                                           │
│  TRACKS   [■ Stock tracks ✓ MOUNTED]──▶[□ Reinforced tracks  ✓ RESEARCHED  [C] 84,000  BUY & MOUNT]       │
│                                                     │                                                     │
│  TURRET   [■ Stock turret ✓]───────────────────────▶[□ Late turret  [XP] 7,000]                          │
│                                                                    │                                      │
│  GUN      [■ 2×100 mm twin ✓]──────────────────────────────────────▶[□ 2×122 mm twin  [XP] 9,800  🔒 needs turret]│
│                                                                                     │                     │
│  ENGINE   [■ 800 hp ✓]──▶[□ 950 hp  [XP] 5,400]                                       ▼                     │
│                                                                           NEXT  [TUKKTUND  IX  [XP] 21,000]│
│                                                                                 [TUNDMAL  IX (engine)]    │
│ Load: ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▱ 97% of 54.0 t                 Stock ≈ 85% effectiveness · ELITE when all done │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Tabs | (144, 72, 480, 48) | `MODULES` · `FIELD KITS` (elite VI–X) or `APEX NODES` (Tier XI) |
| Graph canvas | (144, 136, 1752, 760) | Rows = module kinds (Tracks, Turret, Gun, Engine, in research order D§7.4), columns = research depth; next-vehicle nodes at the far right |
| Load bar | (144, 912, 900, 24) | weight vs load limit of the mounted tracks; > 100 % blocks the mount with "Mount Reinforced tracks first" |
| Footer | (1080, 904, 816, 56) | elite status, `CONVERT XP` (elite only), XP sources |

**Module node** (`ResearchNode`, 240 × 88): module glyph 32 (`modules/gun|engine|track|turret_ring`, steel), name
`body.s` Bold, key stat line with delta vs mounted (`Pen 244 mm  +49`), cost line. States (shape cue + colour):
`Locked` (lock glyph, 50 % opacity, "Requires 2×100 mm twin") · `Researchable` (XP cost in `currency.vehicle_xp`;
dusk top edge when affordable) · `Researched` (credit price, `BUY & MOUNT`) · `Owned` (`MOUNT`) · `Mounted` (verdant
check, 2 px dusk left edge) · `Load-blocked` (warning triangle, "Needs Reinforced tracks").
Edges: 2 px; researched → `text.secondary` solid, next available → `accent.dusk` solid, locked → `border.strong`
dashed 8/6.

**Research modal** (Confirm, 640), shared by modules and next vehicles; example "Research Tukktund" · cost 21,000 XP
· sources: `Vehicle XP 12,400` (all of Tukkhald's) + `Free XP 8,600` with a checkbox **Use Free XP** (default **off**;
offered only when vehicle XP alone does not cover the cost) · balances after. Research then mount is offered as one chained action: `RESEARCH & MOUNT` when credits cover the module price
(6 % of the vehicle, D§11). `→ ResearchModule`, then `→ MountModule` (two requests, one button, two pending steps).

**Next vehicle node:** tier, class glyph, name, XP cost; `RESEARCH` uses the same modal; afterwards the node offers
`OPEN IN TECH TREE`.

**Field Kits** (elite VI–X, D§11): a row of level nodes (3/4/5 levels), each with **two choices** shown as paired
cards (effect lines); cost per level from D§11 (VI 1,000 XP … X 5,500 XP), paid once per level; a chosen option
shows `SWAP`, which is **free at any time outside battle** (D§11 "two free-swap choices"; report 05: swapped freely)
and needs no confirm. Levels unlock in order. `→ SelectFieldKit`. **Apex nodes** (XI): 10 nodes in three bands (6 × 4,000 · 3 × 8,000 · 1 × 12,000,
D§11), Free XP allowed, the signature node last with the mechanic's icon. `→ ResearchApexNode`.

**XP conversion** (elite only, footer button): the Convert XP modal of §1.6.1 (10 XP per Bullion, D§11).
`→ ConvertXP`.

**Controller:** initial focus = the leftmost researchable node, else the mounted gun; D-pad moves along edges, up/down
between rows; `[LB]/[RB]` tabs; `[A]` node action; `[X]` node tooltip pin; `[LT]/[RT]` pan the canvas by one column.
**Compact:** rows become collapsible sections (one per module kind) with nodes as horizontal chips 200 × 72; next
vehicles as a final section. **Acceptance:** node state is a pure function of `ResearchGraph(PV)`; a button is enabled
iff the dry run of the matching transaction returns Ok (REG-UI-05); the Free XP checkbox is never pre-ticked when
vehicle XP alone covers the cost.

### S10 Tech Tree (`Screens/TechTree`, section, keepAlive)

**Purpose.** Show each faction's full research tree I–XI with states and costs, plan the path, research and buy.

```
┌[‹] TECH TREE ┊ Tech Tree › Iron Union ┊ [XP] Free 18,240 · Best vehicle XP 12,400 (Tukkhald) ┊ currencies ┐
├─[◎ IRON UNION]─[CROWN INDUSTRIES]─[EASTERN ARMOR]─[DESERT CORPS]─[MOUNTAIN REP.]─[NORTHERN FED.]─ [LB][RB]┤
│   I        II        III        IV        V         VI        VII       VIII       IX         X       XI   │← sticky ruler
│ ┌──────┐  ┌──────┐  ┌──────┐                                                                           │
│ │Kolmal│─▶│Ostmal│─▶│Bulmal│─┐ ┌───────┐ ┌────────┐ ┌───────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌───────┐ ┌──────┐│
│ │ ✓    │  │ ✓    │  │ ✓    │ └▶│Osthald│▶│Brakkhald│▶│Kolhald│▶│Varrhald│▶│Tukkhald│▶│Tukktund│▶│Durhald│▶│Gorr- ││
│ └──────┘  └──────┘  └──────┘   │ ✓     │ │ ✓      │ │ ✓     │ │ ✓      │ │ ✓ ELITE│ │XP 21,000│ │🔒     │ │tund  ││
│                                └───────┘ └────────┘ └───────┘ └────────┘ └────────┘ └────────┘ └───────┘ └──────┘│
│                                                                              └─(engine)▶┌───────┐ ┌───────┐    │
│                                                                                         │Tundmal│▶│Brakkmal│   │
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ PREMIUM ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┌────────┐                       │
│                                                                       │Tammvarr│ [B] 3,500                      │
│ Legend: ✓ in garage · XP researchable · [C] researched · 🔒 locked · gold frame premium   Zoom 100% [−][+]     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Faction tabs | (120, 56, 1800, 56) | 6 tabs: emblem 28 + name (`tab` style, faction text tint B§3.7); the active tab adds the faction primary 2 px top edge and a 6 % wash over the canvas (B§8.2) |
| Tier ruler | (144, 120, 1752, 32) | roman numerals `label`, sticky during vertical pan; clicking a numeral pans to that column |
| Canvas | (144, 152, 1752, 808) | pan / zoom (60 %, 80 %, 100 %); content size = 11 columns × 232 px pitch + lanes × 120 px pitch |
| Node panel | (1520, 152, 376, 808) | slides in over the canvas when a node is selected (§ below); the canvas recentres so the node stays visible |
| Legend + zoom | (144, 968, 1752, 40) | legend chips with the same shapes as nodes; zoom buttons |

**Node** (`TechNode`, 176 × 96): side silhouette 136 × 44, tier plate 18 top-left, class glyph 18 top-right (gold for
premium, dusk for elite), name `body.s` Bold, state line. States, each with a **shape cue**:

| State | Frame / fill | State line | Shape cue |
|---|---|---|---|
| Locked | `bg.inset`, silhouette 40 % | XP cost in `text.disabled` | `ui/lock` 16 |
| Researchable | `bg.raised` | `[XP] 21,000` (`currency.vehicle_xp` when affordable with parent XP + Free XP) | dusk 3 px top edge + dot badge when affordable |
| Researched, not owned | `bg.raised` | `[C] 1,800,000` (`currency.credits` if affordable, else `text.secondary`) | `ui/unlocked` 16 |
| Purchasable | as researched | price in currency colour + `BUY` chip on hover / focus | cart chip |
| Owned | `bg.selected` | `IN GARAGE` | `ui/check` verdant 16 |
| Elite | `bg.selected` | `ELITE` `micro` chip | class glyph dusk |
| Premium | 1 px `currency.bullion` frame | `[B] 3,500` | gold class glyph; premium lane |
| Apex (XI) | obsidian frame + dusk glow (B§6.6 tier XI) | `[XP] 47,000` | crest |
| Sold within 72 h | as researched | `BUYBACK +10 %` | `ui/refresh` |

**Edges:** right-angled orthogonal routing in the column gutters (56 px), 2 px: both ends researched → `text.secondary`;
parent researched and child researchable → `accent.dusk`; otherwise `border.strong` dashed. Cross-class or non-gun
unlocks carry a `caption` label at the bend ("via engine"). Premium vehicles sit in a separate lane under a dashed
`PREMIUM` divider and have no edges.

**Node panel** (376 wide): silhouette 320 × 104, name `h3`, class · role · tier, combat identity line (roster), 6 key
stats with deltas vs its parent, unlock requirements ("Research 2×122 mm twin on Tukkhald"), XP sources (parent XP,
Free XP), CTA (`RESEARCH` / `BUY` / `SELECT IN GARAGE` / `VIEW IN STORE`), secondary `INSPECT`, `COMPARE`,
`RESEARCH MODULES` (for owned).

**Research / buy flows.** RESEARCH opens the research modal of §S09 (vehicle XP of the parent that unlocks it, then
optional Free XP). BUY opens Purchase confirm with the **buy options**: crew (`NEW CREW` free, trained recruits D§12 /
`FROM RESERVE` matching faction + class, retrain cost shown), `LOAD STANDARD AMMO` (default on, cost shown), `MOUNT
OWNED EQUIPMENT` none; total; `BUY FOR [C] 1,400,000`. After buying: `ui_vehicle_unlocked`, toast, and the node panel
offers `SELECT IN GARAGE`. `→ ResearchVehicle`, `→ BuyVehicle`.

**Panning and zoom.**

| Input | Pan | Zoom | Node focus |
|---|---|---|---|
| Mouse | drag with LMB on empty canvas; `[Shift]`+wheel horizontal | wheel (to cursor) | click |
| Keyboard | – | `[−]` `[=]` | arrow keys along edges |
| Gamepad | right stick (1,200 px/s at 100 %) | `[LT]` out / `[RT]` in (3 steps) | left stick / D-pad: along edges, up / down to sibling lanes; the canvas auto-pans to keep focus 120 px from edges |
| Touch | drag | pinch (60–100 %) | tap |

**Initial focus:** the node of `focus` param, else the selected vehicle if it belongs to this faction, else the most
advanced owned node of the faction, else its Tier I root. The faction tab defaults to the selected vehicle's faction.
**Controller:** `[LB]/[RB]` factions · `[A]` node panel / CTA · `[X]` Inspect · `[Y]` Compare add · `[B]` closes the node
panel, then leaves.
**Compact:** faction tabs as a dropdown; canvas zoom 60–80 %; node panel becomes a bottom sheet; nodes 144 × 80.
**Acceptance:** the graph renders from `CR` `TechTree.luau` with zero hand-placed coordinates (lanes computed from the
DAG: branch order from content, then a deterministic lane assignment); node states equal `ResearchGraph(PV)` for every
node on 50 random profiles (REG-UI-05); 90+ nodes pan at 60 FPS on PC and 30 FPS on mobile (nodes are static images +
text, ≤ 12 GuiObjects each; edges are 2 px Frames, ≤ 300 segments per faction).

### S11 Vehicle comparison (`Screens/Compare`, drill-in)

**Purpose.** Compare up to **6** vehicles (D§16) side by side in chosen configurations.

```
┌[‹] COMPARE ┊ 4 of 6 vehicles ┊ currencies                                                                 ┐
├──────────────────────┬────────────┬────────────┬────────────┬────────────┬────────────┬────────────┤
│                      │ [art]      │ [art]      │ [art]      │ [art]      │   [ + ]    │            │
│                      │ TUKKHALD   │ TUKKTUND   │ REGNION    │ DUNELIGHT  │ ADD        │            │
│ Config               │ [CURRENT▾] │ [TOP ▾]    │ [TOP ▾]    │ [STOCK ▾]  │            │            │
├─FIREPOWER────────────┼────────────┼────────────┼────────────┼────────────┤            │            │
│ Damage               │ 358 ×2     │ 440 ×2 ▲   │ 390        │ 260 ▼      │            │            │
│ Penetration (std)    │ 195        │ 225 ▲      │ 220        │ 190 ▼      │            │            │
│ DPM                  │ 1,671 ▼    │ 1,906      │ 2,120 ▲    │ 2,050      │            │            │
│ …                    │            │            │            │            │            │            │
├─SURVIVABILITY────────┤ …          │            │            │            │            │            │
│ [□ Show only differences]   [□ Highlight vs first column]                               [CLEAR ALL]     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Label column | (144, 72, 280, 880) | stat names grouped (Firepower, Survivability, Mobility, Spotting) with collapsible group headers |
| Vehicle columns | 6 × (240 wide) from x 432 | header 200 px: silhouette, tier, class, name, config dropdown (`STOCK` / `TOP` / `CURRENT` (owned) ), remove `ui/close` |
| Footer | (144, 968, 1752, 48) | toggles and `CLEAR ALL` |

* Values `mono` 16 right-aligned; **best** per row: `state.success` + ▲ glyph; **worst**: `state.danger` + ▼ glyph
  (only when ≥ 3 vehicles; with 2, the better one gets ▲); "Highlight vs first column" switches to deltas vs column 1.
* Rows where higher is worse (reload, aim time, dispersion) invert. Ties get no glyph.
* Add: `ADD` slot opens the vehicle picker (Picker modal, filters as §S05, all of `CR`). The list lives in
  `SS.compareList` (session only).
* Controller: focus moves by cell; `[LB]/[RB]` jump columns; `[LT]/[RT]` page rows; `[X]` on a header = Inspect;
  `[Y]` = remove. Initial focus: first vehicle header.
* Compact: 2 vehicle columns visible, horizontal swipe; label column 160 px sticky.
* **Acceptance:** all values come from `StatsCalculator` on the stated configuration and the player's current crew
  for owned vehicles / a trained 100 L crew for others (REG-UI-07); 6 columns fit 1920 without horizontal scroll.

### S12 Armor Inspector (`Screens/ArmorInspector`, drill-in from Inspect `ARMOR`; camera preset `armor`)

**Purpose.** Show where a vehicle is strong and weak against a chosen attacker, gun and shell, using the **same**
`ArmorGeometry` and `Penetration` code as the server (A§6.3, D§16).

```
┌[‹] ARMOR ┊ TUKKTUND · Heavy · Tier IX ┊                                                                   ┐
├─ATTACKER──────────────┬──────────────────────────────────────────────────────────────┬─LEGEND─────────────┤
│ [art] Your Tukkhald ▾ │                                               ┌──────────────────────────────┐     │
│ Gun  2×122 mm twin ▾  │          (vehicle, heatmap; cursor probe)     │ HULL UPPER FRONT             │     │
│ Shell [AP][APCR*][HE] │                                ⊕──────────────▶ Nominal        110 mm       │     │
│ Pen 244 mm @ 100 m    │                                               │ Angle   58°  (norm. −5°)     │     │
│ Distance ──●──── 250 m│                                               │ Effective      180 mm        │     │
│  → 230 mm (falloff)   │                                               │ vs AP   230 mm @ 250 m       │     │
│                       │                                               │ Chance  94%   ◔◔◔ 3 segments │     │
│ MODE                  │                                               │ Ricochet no · Overmatch no   │     │
│ (THICKNESS|EFFECTIVE| │                                               └──────────────────────────────┘     │
│  VS SHELL)            │                                                                  ■ ≥ 1.125 pen   │
│ SHOW                  │                                                                  ▨ ±12.5 %       │
│ [✓] Spaced armor      │                                                                  □ ≤ 0.875 pen   │
│ [ ] Modules  [ ] Crew │                                                                                    │
│ WEAK POINTS           │                                                                                    │
│ · Lower front  41 mm  │                                                                                    │
│ · Cupola       88 mm  │                                                                                    │
├───────────────────────┴───[FRONT][FRONT 30°][SIDE][REAR][TOP]────────────────────────────────────────────┤
```

| Region | Rect | Content |
|---|---|---|
| Attacker panel | (144, 72, 400, 880) | vehicle picker (default **your selected vehicle**; alt "Reference medium Tier N" = the D§7.4 MT baseline of the target's tier), gun dropdown (its guns), shell segmented control (shell icons 32, special rounds with the gold rim B§6.10), penetration at 100 m, distance slider 0–500 m step 25 m (AP/APCR falloff, D§1; hidden for HEAT/HE/HESH), mode, toggles, weak points list |
| Viewport | full; interactive (560, 72, 960, 880) | orbit / zoom like Inspect; probe at cursor or at the screen centre on gamepad (a crosshair appears) |
| Probe tooltip | follows the probe, 320 wide | §S12.1 |
| Legend | (1536, 600, 360, 352) | depends on mode |
| View presets | (640, 968, 640, 48) | camera snaps: FRONT, FRONT 30°, SIDE, REAR, TOP |

**Modes and legends.**

| Mode | Plate colour | Legend |
|---|---|---|
| `THICKNESS` | Nominal mm in 7 bands: ≤ 20 · 20–40 · 40–75 · 75–120 · 120–180 · 180–250 · > 250 on the proposed sequential ramp `armor.ramp.1…7` (§5.1; luminance-monotonic, CVD-safe) | 7 swatches with mm ranges |
| `EFFECTIVE` | Effective mm along the current camera direction (normalization for the selected shell), same 7 bands | same + "Angle from your view" |
| `VS SHELL` (default) | Outcome vs the selected shell at the chosen distance: T_eff ≤ 0.875 pen → `state.success` **solid**; within ±12.5 % → `state.warning` **diagonal stripes**; ≥ 1.125 pen or ricochet → `state.danger` **cross-hatch** (patterns via `Texture` overlays so they read without colour; CVD schemes use `pen.cb.*`) | 3 swatches with the reticle's segment glyph (3 / 2 / 1 segments, B§8.7) so armor view and reticle speak one language |

Spaced armor, screens and tracks get a dashed `accent.steel` outline overlay (toggle). Modules / crew toggles draw the
x-ray volumes of §S08 at 60 % opacity over the heatmap.

#### S12.1 Probe tooltip (the effective-armor-at-cursor readout)

Rows (only those that apply): zone name (`ArmorZone` humanised, `label`) · Nominal `mm` · Impact angle and the
normalization used · 2-calibre / 3-calibre rule note ("Overmatch: shell > 3× plate, never ricochets") · Effective `mm`
· Spaced layers along the path ("Screen 20 mm ahead · HEAT loses 35 %") · Pen at distance · **Penetration chance**
`num.m` with the segment glyph · Ricochet yes/no with the threshold (70° kinetic, 85° HEAT) · for HE/HESH: "Expected
damage if not penetrating: 96" from the D§1 HE formula.

**Chance** = P(rolled pen ≥ required pen) under the D§1 roll (truncated normal, σ = 0.125 × mean pen, ±25 % bound).
*Required pen* is the smallest initial roll that still defeats every layer on the path. The shared path code computes
it: the sum of T_eff for kinetic rounds, and for HEAT the spaced-gap loss inverted (D§1). The pure helper
`Penetration.chance(meanPenMm, requiredPenMm)` lives in Shared (requested, §5.4) so the UI and tests share it. A
ricochet gives 0 % with the label "Ricochet"; overmatch (> 3 cal) never ricochets. The probe raycasts the analytic `ArmorGeometry` in vehicle space (one ray per
pointer move, ≤ 60/s), never Roblox parts.

**Weak points.** Plates whose effective thickness at 0° yaw (front arc for frontal zones) is ≤ 0.875 × the selected
shell's penetration at the chosen distance, merged per zone, sorted by thickness, max 6 rows. Selecting a row flies the
camera to it (450 ms) and pins the probe there.

**Controller:** initial focus = shell control; right stick orbit; left stick moves the probe crosshair when the
viewport has focus (toggle focus with `[Y]`); `[LT]/[RT]` zoom; `[LB]/[RB]` cycle modes; `[X]` pin / unpin the probe.
**Compact:** attacker panel as a sheet (`ATTACKER` button), legend collapses to a 3-chip strip, probe = tap-and-hold
on the model (the tooltip docks to the top of the screen so the finger does not cover it).
**Acceptance:** for 10,000 random probe rays per golden vehicle, the tooltip's effective thickness and outcome equal
the server `Penetration` result for the same ray and shell (shared code, REG-ARM goldens); heatmap recolouring never
rebuilds geometry (recolour only); the armor model respects the D§18 part budget.

### S13 Crew (`Screens/Crew`, section or drill-in; camera preset `crew`)

**Purpose.** View and manage the selected vehicle's crew (Commander, Gunner, Driver, Loader; small vehicles double up,
D§12), learn perks, use books, retrain, reset, and manage the crew reserve.

```
┌[‹] CREW ┊ TUKKHALD · crew 4/4 ┊ [CX] Crew XP …                                                            ┐
├─[ VEHICLE CREW | RESERVE ]───────────────────────────────────────────────────────────────────────────────┤
│ ┌[portrait] Cmdr  Vela Korrin ┐  ┌─PERKS · Vela Korrin · Commander ───────────────────────────────────┐    │
│ │ ◉ ▬▬▬▬▬▱ slot 3 64%  •      │  │ SLOTS  [① Long Watch ✓][② Field Tutor ✓][③ ···· 64%][④ —][⑤ —] │    │
│ └─────────────────────────────┘  │ 12k ✓      24k ✓      48k 30,720/48,000                             │    │
│ ┌[portrait] Gunner  Aldo Fenn ┐  │                                                                     │    │
│ └─────────────────────────────┘  │ COMMANDER PERKS                       GROUP PERKS (all crew)        │    │
│ ┌[portrait] Driver  …         ┐  │ [icon][icon][icon]                    [icon][icon][icon]             │    │
│ └─────────────────────────────┘  │ [icon][icon][icon]                                                  │    │
│ ┌[portrait] Loader  …         ┐  │ selected: name · effect · "Works from 1 %, full at 100 %" [LEARN]   │    │
│ └─────────────────────────────┘  └─────────────────────────────────────────────────────────────────────┘    │
│ Trained for Tukkhald · 100%      [ RETRAIN ] [ RESET PERKS ] [ USE BOOK ] [ SEND TO RESERVE ]                │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Tabs | (144, 72, 480, 48) | `VEHICLE CREW` · `RESERVE` |
| Member list | (144, 136, 400, 4 × 128) | `CrewCard` 400 × 120: portrait 96 (generated set, `CrewName.portrait`; fallback role helmet glyph), role glyph(s) (B§6.8, two when doubled), name `h4`, current slot progress, perk-ready badge, injured state never shown here (battle-only, D§12) |
| Perk board | (568, 136, 1328, 640) | slot row (5 slots with costs 12k/24k/48k/96k/192k, D§12), role perk grid (6 individual), group perk grid (3), detail strip |
| Crew summary | (144, 664, 400, 120) | trained-for vehicle, efficiency (100 %, or retrain penalty "75 % → 100 % in 14,200 XP"), XP overflow note "Extra crew XP converts to Free XP at 10:1" |
| Actions | (568, 792, 1328, 56) | `RETRAIN`, `RESET PERKS`, `USE BOOK`, `SEND TO RESERVE` (secondary) |

**Perk tile** 120 × 120: perk icon 48 (requested set, §5.1), name `caption` (2 lines), states: learned (slot number
badge `①`, verdant edge), training (progress ring), available (focusable, `LEARN` when a slot is free), not for this
role (hidden; doubled roles show both grids with a role switch). Selecting a tile fills the detail strip with the
effect at 1 %, 50 % and 100 % training and the "scales with crew share" note for group perks. `→ LearnPerk`.

**Modals.** *Retrain* (D§12, same faction + class only): two option cards — `CREDITS 5 %` "[C] 70,000 · −25 % perk
efficiency, recovered over 20,000 crew XP" and `BULLION` "[B] 100 · no penalty"; cross-class shows "Keeps 90 % of crew
XP" and is offered only by the rules in content. *Reset perks*: first reset free, then [C] 50,000 (free within 7 days
of buying the vehicle); lists perks that will be unlearned; Destructive kind. *Use book*: inventory books (5k / 25k /
60k) → choose crew → confirm. `→ RetrainCrew`, `→ ResetPerks`, `→ UseCrewBook`, `→ AssignCrew`, `→ RecruitCrew`.

**Reserve tab** (code name `Barracks`): `VirtualList` of unassigned crews (faction emblem, class glyph, trained-for vehicle, total perks),
filters faction / class / trained-for, `ASSIGN TO TUKKHALD` (retrain modal when needed), `DISMISS` (Destructive).
Empty state §1.10.

**Controller:** initial focus = first member card (or the member with a free slot); `[LB]/[RB]` tabs; within the perk
board D-pad; `[X]` pins tooltips; `[Y]` = next member. **Compact:** member list as a horizontal strip of 4 portraits
(64 px) at the top; perk board below with 4 tiles per row; actions in an overflow menu.
**Acceptance:** slot training displayed equals `clamp((xp − Σcost[1..k−1]) / cost[k], 0, 1)` (Types/Profile); learning
order is enforced (slot k before k+1); no action shows a price that differs from the transaction dry run.

### S14 Equipment drawer (`Screens/Equipment`, §S07 drawer)

```
┌ EQUIPMENT · Tukkhald ──────────────────────────────────────────── [×] ┐
│ SLOTS  [▣ FIREPOWER +15%  Rammer Assist ⌐¬][▣ Spall Lining][ + empty ]│
│ ───────────────────────────────────────────────────────────────────── │
│ [ALL | FIREPOWER | SURVIVABILITY | MOBILITY | SCOUTING]               │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │[icon] Rammer Assist        Class A   Owned 1   −10 % reload      │  │
│ │        in a Firepower slot: −11.5 %                 [ MOUNT ]    │  │
│ ├──────────────────────────────────────────────────────────────────┤  │
│ │[icon⌐¬] Rammer Assist · Refined  ×1.2   [T] 3,000    [ BUY ]     │  │
│ └──────────────────────────────────────────────────────────────────┘  │
│ Demount: free with Plus · else [B] 5 or 10 % of price                 │
└───────────────────────────────────────────────────────────────────────┘
```

* **Slots:** 2 at I–III, 3 at IV–XI (D§13). At VI+ slot 1 carries the vehicle's **role category** (D§7.2): a category
  tile chip (`equip.*` colour + bone glyph, B§6.11) and `+15 %`; a matching item shows both values ("−10 % → −11.5 %").
* **Items:** compatible list filtered by class rules from content; row 72 px: icon 48 with grade overlay (Standard =
  none; **Refined** = `grade_improved` silver brackets **O**: brand's `grade_experimental` stays reserved), name, class
  (C/B/A by tier, D§13), owned count (`PV.inventory.equipment`), effect, price (Credits; Refined in Campaign Tokens).
  Never Bullion-only (D§13).
* **Actions:** `MOUNT` (owned), `BUY & MOUNT`, `DEMOUNT` (modal: free with Plus, else choose `[B] 5` or `[C] 10 %`;
  REG-UI-08: moving between setups is free, item counts are conserved). `→ SetEquipment`, `→ BuyEquipment`,
  `→ DemountEquipment`.
* Mounting into an occupied slot opens a swap confirm that shows where the old item goes (Spares) and the demount cost.
* **Controller:** initial focus = first empty slot, else slot 1; `[LB]/[RB]` category filter; `[X]` tooltip.
* **Acceptance:** the drawer never allows two copies of the same item, or two items of one `exclusiveGroup`, on one
  vehicle; category bonus shown equals
  `StatsCalculator`'s applied value.

### S15 Ammunition drawer (`Screens/Ammo`, §S07 drawer, batch edit)

```
┌ AMMUNITION · Tukkhald ────────────────────────────────── [×] ┐
│ CAPACITY  ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▱▱▱  42 / 45      │
│           (AP ■■■■■■■■■■■■ | APCR* ▨▨▨▨ | HE ▤▤▤)            │
│ ① [AP shell]   Standard AP     Dmg 358  Pen 195/176  [−][ 30 ][+] ▬▬▬●▬▬  [C] 900 ea│
│ ② [APCR*]      Special APCR    Dmg 358  Pen 254/191  [−][  6 ][+]          [C] 2,250 ea│
│ ③ [HE shell]   HE              Dmg 465  Pen 61       [−][  6 ][+]          [C] 900 ea │
│ PRESET [Balanced ▾]      Spares: 12 AP                                               │
│ [✓] Auto-resupply after battle                                                       │
│ Cost to fill: [C] 21,400                        [ REVERT ]  [ APPLY ]                 │
└──────────────────────────────────────────────────────────────┘
```

* Capacity bar 576 × 12, segmented by shell type in `ammo.*` colours **and** the shell silhouettes at segment starts;
  unused capacity hatched `bg.inset`.
* One row per shell the mounted gun carries (2–3, D§1 families; HESH for Crown VIII+ HT/TD): order = battle keys
  1–3 (drag handle on mouse; `[X]` "Move up" on gamepad), shell icon 48 (special rounds gold case + rim, B§6.10), name,
  damage, penetration at 100 m / 500 m (AP/APCR falloff), velocity in the tooltip, per-shell price (special = 2.5 ×
  standard, credits only, D§11), count stepper + slider (`ui_slider_tick`), spare stock (`PV.inventory.shells`).
* Presets: `Balanced` (≈ 70 / 20 / 10), `Standard only`, `Mirror last battle`; custom edits switch the label to
  `Custom`.
* Footer: cost to fill (net of spares), auto-resupply toggle (`PV.vehicles[id].autoResupply.ammo`), `REVERT`, `APPLY`
  (`→ SetAmmo`, `→ SetAutoResupply`). 0 total shells is allowed only with the warning "This vehicle can't battle with
  no ammunition" (blocks TO BATTLE, §S06).
* **Controller:** D-pad up/down rows; left/right adjusts count by 1, `[LT]/[RT]` by 5; `[Y]` apply.
* **Acceptance:** the sum never exceeds capacity (steppers clamp, others don't move automatically); closing with
  unapplied changes asks; the cost line equals the dry-run cost.

### S16 Consumables drawer (`Screens/Consumables`, §S07 drawer)

* 3 slots (D§13). Groups: **Repair** (Repair Kit, Large Repair Kit), **Medical** (Medkit, Large Medkit), **Fire**
  (Extinguisher, Automatic Extinguisher), **Passive** (Rations, Quality Fuel). Row: icon 48 (B§6.5 3/4 objects; large =
  two units), name, cooldown ("90 s cd · reusable"), effect, activation (`Manual` / `Automatic` / `Passive`), price
  (Credits; large ones also show `[B] 100`), owned count.
* Rules surfaced in the UI: no duplicate item on one vehicle; "Resupply is charged once per battle if used" (D§13);
  auto-resupply falls back to the cheapest kits (tooltip).
* Slot order = battle keys 4–6; reorder like ammo. `→ SetConsumables`, `→ SetAutoResupply`.
* **Acceptance:** each slot shows the key it will use in battle in the current input mode (`[4]` / D-pad radial
  position / touch position).

### S17 Exterior (`Screens/Exterior`, full screen from the strip; camera preset `exterior`)

**Purpose.** Preview, buy and apply cosmetics. Cosmetics never change combat stats except the flat paint camo bonus
items flagged `camoBonus` (D§5; 0 in ranked), which say so explicitly.

```
┌[‹] APPEARANCE ┊ TUKKHALD ┊ currencies                                                                     ┐
├─────────────┬─────────────────────────────────────────────────────────────────────────┬────────────────────┤
│ STYLES      │                                                                         │ CHANGES            │
│ PAINT     ● │                 (vehicle preview, orbit; hotspots for emblem slots)     │ Paint  Ash Grey  [C] 40,000│
│ CAMOUFLAGE  │                          ◎ turret L     ◎ hull R                        │ Camo   Ridge Split  owned │
│ EMBLEMS     │                                                                         │ Emblem Anvil  [T] 300 │
│ INSCRIPTIONS│                                                                         │ ─────────────────  │
│ DECALS      │                                                                         │ Total [C] 40,000   │
│ ATTACHMENTS │                                                                         │       [T] 300      │
│             │ [Season: Summer|Winter|Desert]  [□ Show only owned]                     │ [ BUY & APPLY ]    │
├─────────────┴─[item][item][item][item][item][item][item][item][item][item] ›──────────────────────────────────┤
```

| Region | Rect | Content |
|---|---|---|
| Category rail | (144, 72, 240, 760) | `STYLES` (full sets), `PAINT`, `CAMOUFLAGE`, `EMBLEMS`, `INSCRIPTIONS`, `DECALS`, `ATTACHMENTS` (gun sleeves, stat trackers, stowage); a dot marks categories with pending changes |
| Preview | full; interactive (400, 72, 1100, 760) | orbit/zoom; emblem/inscription/decal **slot hotspots** (hull L/R, turret L/R, front) as 32 px rings, select a slot then an item |
| Cart | (1536, 72, 360, 760) | every pending change with price or `owned`, totals per currency, `BUY & APPLY` primary / `APPLY` when all owned, `DISCARD` |
| Item strip | (144, 848, 1752, 160) | `CosmeticCard` 136 × 136: art, rarity 3 px top edge + pip (B§3.5, never a full fill), name, price / `OWNED` / source chip (`PASS`, `EVENT`, `MISSION`), scope lock ("Iron Union only") |
| Filters | (400, 784, 1100, 40) | season variant (for paints/camo), owned only, rarity |

* Selecting an item **previews** it at once (local renderer only); nothing is bought until `BUY & APPLY` (Purchase
  confirm listing every item). Leaving with pending changes asks; leaving without buying restores the applied
  cosmetics exactly (REG-UI-10). `→ BuyCustomization`, `→ ApplyCustomization`.
* `camoBonus` items show a `caption` "+4 % concealment in Open Trials (not ranked)" with the scouting glyph.
* Content kinds today: `Paint`, `Camouflage`, `Emblem`, `Inscription`, `Style`, `GunSleeve`, `StatTracker`. `DECALS`
  and stowage `ATTACHMENTS` need new kinds (`Decal`, `Attachment`), requested in §5.4; until then the Decals tab is
  hidden and Attachments lists gun sleeves and stat trackers.
* **Controller:** initial focus = first item of the active category; `[LB]/[RB]` categories; `[LT]/[RT]` page items;
  right stick orbit; `[X]` toggle slot hotspot mode; `[Y]` jump to cart.
* **Compact:** category rail = icon tabs on top; cart = `CART (3)` button opening a sheet; item strip 96 × 96 cards.
* **Acceptance:** preview → leave restores deep-equal state (REG-UI-10); no purchase without a confirm listing all
  items; scope-locked items cannot be applied to other vehicles.

### S18 Missions and Pass (`Screens/Missions`, section; Pass rail item deep-links `?tab=pass`)

**Purpose.** All objectives in one place: daily, weekly, campaigns, special (class and vehicle), event, and the season
pass track (D§14). Tabs: `DAILY` · `WEEKLY` · `CAMPAIGNS` · `SPECIAL` · `EVENT` (only while an event runs) · `PASS`.

```
┌[‹] MISSIONS ┊ Daily resets in 4h 12m ┊ currencies                                                         ┐
├─[ DAILY ]─[ WEEKLY ]─[ CAMPAIGNS ]─[ SPECIAL ]─[ EVENT ]─[ PASS ]──────────────────────────── [LB][RB] ───┤
│ ┌─ EASY ───────────────┐ ┌─ MEDIUM ─────────────┐ ┌─ HARD ───────────────┐ ┌─ BONUS ── 🔒 ─────────┐  │
│ │ [daily] Hold the line│ │ [daily] Eyes forward │ │ [daily] Spearhead    │ │ Complete all three    │  │
│ │ Block 1,000 damage   │ │ Spot 4 enemies       │ │ Deal 2,500 damage    │ │ to unlock             │  │
│ │ ▬▬▬▬▬▬▬▱▱▱ 640/1,000 │ │ ▬▬▬▬▬▬▬▬▬▬ 4/4 ✓     │ │ in one battle, win   │ │                       │  │
│ │ Any vehicle IV+      │ │                      │ │ ▬▱▱▱▱▱ best 1,120    │ │                       │  │
│ │ [C] 6,000 [FX] 150   │ │ [C] 8,000 [FX] 300 📖│ │ [C] 11,000 [FX] 500 [T] 30│ │ [C] 14,000 [FX] 1,000 ✚│ │
│ │ [ REROLL (1 free) ]  │ │ [ CLAIM ]            │ │ [ REROLL ]           │ │                       │  │
│ └──────────────────────┘ └──────────────────────┘ └──────────────────────┘ └───────────────────────┘  │
│ Daily total today: up to [C] 39,000 · Pass +15 points per daily                                       │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Tab | Layout | Content and rules |
|---|---|---|
| DAILY | 4 `MissionCard`s 400 × 560 at (144, 136) with 24 px gaps | Easy / Medium / Hard + Bonus (locked until the three are complete, `PV.missions.daily.bonusUnlocked`). Conditions (`MissionCondition`) as rows with progress bars; "in one battle" vs cumulative shown explicitly; scope line from `MissionScope` ("Medium or heavy, Tier IV+"); rewards (scaled by top owned tier, D§14). `REROLL` uses `PV.missions.daily.rerollsUsed` (1 free, +1 with Premium Time) → `RerollDaily`; `CLAIM` → `ClaimMission` (reward toast + `ui_mission_complete`). |
| WEEKLY | 3 cards 560 × 400 + a strip "Complete all 3: Guide (crew book)" | 5–10 battles each; rewards Booklet + 10 Tokens + 60 pass points (D§14); no credits. |
| CAMPAIGNS | Operation selector (3) · series tabs `ASSAULT` / `OVERWATCH` / `SUPPORT` · a 10-node path on a khaki operations-map panel (B§6.5 missions) · detail panel 520 px | Node = counter 56 px with index; states locked / active / complete / complete with honours (second notch). Detail: primary conditions, `WITH HONOURS` conditions, rewards, unique reward preview (3D lineup camera for vehicles/cosmetics). One active mission per series, `TRACK` toggle (tracked missions show in the battle scoreboard, §S34). |
| SPECIAL | List of `MissionRow`s 1,200 × 96, filter chips `ALL` · `CLASS` (scope.classes) · `VEHICLE` (scope.vehicles) | Class missions show the class glyph; vehicle missions show the vehicle silhouette and also put a dot on that carousel card. |
| EVENT | Event header 1,752 × 200 (art, name, ends in, token balance `PV.currencies.eventTokens[id]`, `EVENT SHOP ›`) + mission list | Ranked events show ladder rank and points (`PV.events[id].ranked`). |
| PASS | §S18.1 | |

#### S18.1 Pass track

```
┌─[ CHAPTER I | CHAPTER II | CHAPTER III ]─────── Season: Ember Run · ends in 23d ─────────────────────────────┐
│ STAGE 12 ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▱▱▱▱▱ 18/30 pts                    [ CLAIM ALL (3) ]   [ UNLOCK PAID TRACK [B] … ]   │
│        10        11        12        13        14        15        16        17        18        …   30   │
│ FREE  [✓ ][     ][ ◆ ][     ][ ◆ ][     ][ ◆ ][     ][ ◆ ]                                  [final]     │
│ PAID  [🔒][ 🔒 ][ 🔒][ 🔒 ][ 🔒][ 🔒 ][ 🔒][ 🔒 ][ 🔒]                                  [final]     │
│ How to earn: top 3 on your team 8 (win) / 6 (loss) · 4–10: 6 / 4 · others 3 / 2 · daily mission +15        │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

* 3 chapters × 30 stages × 30 points (D§14). Stage nodes 104 × 120 (reward icon 48, amount, state: claimed tick,
  claimable dusk edge + glow-free pulse, locked). Horizontal `VirtualList`; the current stage is centred on open.
* `CLAIM ALL` claims every claimable stage in one request sequence (`→ ClaimPassStage` per stage, one toast summary).
* Paid track: **fixed rewards only** (D§14, no random items); unlock = Purchase confirm for the `SeasonPass` store
  item (`→ BuyPassPaid`).
* **Controller:** `[LB]/[RB]` tabs (chapters are a segmented control above, `[X]` cycles them); `[LT]/[RT]` page 10
  stages; `[A]` claim focused stage; initial focus = current stage.

**Missions controller map:** `[LB]/[RB]` tabs; D-pad between cards; `[A]` primary card action; `[X]` card details
(full conditions tooltip); `[Y]` reroll on daily cards. Initial focus: first claimable card, else the first card.
**Compact:** cards become a vertical list of 96 px rows with an expand chevron; pass track rows 72 px nodes.
**Acceptance:** progress values equal `Missions` evaluation of `PV.missions` (no client-side derivation); a reroll
never discards progress silently ("Progress 640/1,000 will be lost" in the confirm); claim buttons appear only when
the server marked `completed`; reset timers use the server reset time from `PV.missions.daily.resetAt`.

### S19 Achievements (`Screens/Achievements`, Profile tab and drill-in)

* Left category list (280 px): `FIELD HONOURS` (battle medals, §5.3 names), `EPIC`, `MASTERY`, `BARREL BANDS`,
  `MILESTONES`, `SERIES`, `EVENT`, `COMMEMORATIVE` (from `AchievementCategory`), each with "earned / total".
* Grid of 96 px badges (frame + emblem composited at the same size, B§6.13), 10 columns at 1080p; earned = full colour
  + count chip (`×14` for repeatables); not earned = 30 % steel silhouette; milestones show a progress ring; hidden
  achievements show a `???` frame until earned.
* Detail panel (480 px): art 192, name `h3`, description, how to earn (rule text from content), first and last earned
  (relative time), rewards, rarity. Mastery and barrel bands show per-vehicle tables (vehicle, level, progress to next
  percentile window, "last 7 days" note).
* New achievements are marked with a dot until viewed (`ST.seen`).
* Controller: grid focus; `[LB]/[RB]` categories; initial focus = most recent unseen, else the first badge.
* Acceptance: counts equal `PV.achievements`; hidden ones never leak names or descriptions before being earned.

### S20 Store (`Screens/Store`, section, keepAlive)

**Purpose.** Sell clearly and calmly: Bullion, Premium Time and Plus, premium vehicles, cosmetics, supplies, boosters,
token and event shops. **No paid random items, no timed combat offers, no countdown pressure** (D§15).

```
┌[‹] STORE ┊ currencies                                                                                     ┐
├────────────────┬─────────────────────────────────────────────────────────────────────────────────────────┤
│ FEATURED     ● │ ┌──────────────── HERO (1,176 × 360) ──────────────────┐ ┌─ PREMIUM TIME ─┐            │
│ BULLION        │ │  DUNELIGHT · Tier VIII premium medium                 │ │ +50 % XP & CR  │            │
│ PREMIUM & PLUS │ │  Autoloader · earns ×1.5 credits                      │ │ 7 days [B]1,250│            │
│ VEHICLES       │ │                              [ VIEW ]                 │ └────────────────┘            │
│ COSMETICS      │ └───────────────────────────────────────────────────────┘                               │
│ SUPPLIES       │ [tile 280×200] [tile] [tile] [tile]                                                      │
│ BOOSTERS       │ [tile 280×200] [tile] [tile] [tile]                                                      │
│ TOKEN SHOP     │                                                                                          │
│ EVENT SHOP     │ Prices in Robux are set by Roblox for your region.                                       │
└────────────────┴─────────────────────────────────────────────────────────────────────────────────────────┘
```

| Section | Content | Purchase path |
|---|---|---|
| FEATURED | 1 hero + max 8 tiles (`StoreItem.featured`, `sortOrder`) | per item |
| BULLION | 6 packs (D§15 base 49 … 1,999 R$; bonus % from config), tile shows Bullion amount (`num.l`), bonus chip, Robux price from `GetProductInfoAsync` | `PromptProductPurchase` → receipt → `PurchaseGranted` toast |
| PREMIUM & PLUS | Premium Time 1 d 250 / 7 d 1,250 / 30 d 2,000 BUL (D§11) with the benefit list; HULLDOWN Plus card (benefits from D§11, Robux price, "Manage in Roblox" when subscribed) shown only if `IsEligibleToPurchaseSubscription` | `→ BuyPremiumTime`; Plus via `PromptSubscriptionPurchase` |
| VEHICLES | premium vehicles (D§15 prices II 250 … VIII 3,500 BUL), filters tier / class / faction; tile = silhouette, name, tier, class, price; detail shows **facts**: credit multiplier, crew rule (any same faction + class crew), "No preferential matchmaking", stat summary vs tech-tree peers, `INSPECT`, `PREVIEW IN GARAGE` | `→ BuyStoreItem` with crew options (as §S10 buy) |
| COSMETICS | styles, paints, camos, emblems with `PREVIEW` (opens Exterior with the item pre-selected) | Bullion / Credits |
| SUPPLIES | consumables, equipment, crew books for Credits (and Tokens) | `→ BuyStoreItem` |
| BOOSTERS | XP / Free XP / crew XP / credit boosters (fixed effect, battles or duration) | `→ BuyStoreItem`, then `ACTIVATE` in inventory |
| TOKEN SHOP | Campaign Token items (Refined equipment, books, cosmetics, D§11) | Tokens |
| EVENT SHOP | event-token items while the shop is open (`shopClosesAt`, shown as a calm date "Shop open until 12 Nov") | event tokens |

**Rules.** Every tile pairs icon and amount (B§2); every product detail lists **exactly what you get** (`grants`);
"bonus" claims only compare against the same product's base amount; purchase limits shown ("1 per account");
owned items show `OWNED`, never hidden; a `PolicyService` result that restricts a category hides it entirely. Robux
amounts are never hard-coded (D§15): skeleton until `GetProductInfoAsync` returns, cache 10 min per productId.
Battle places never show the store (D§15).

**Purchase flow (Robux).** `BUY` → (Roblox prompt) → on `PromptProductPurchaseFinished` with `isPurchased`, the tile
shows "Processing…" and `SS.pendingPurchases` holds it; `PurchaseGranted` → reward toast + count-up; no grant within
30 s → system banner "Purchase is processing. Bullion will arrive shortly." (receipts may redeliver, D§15). Never
grant or show balances from the client side.

**Controller:** rail focus first; `[RB]` / `[LB]` cycle sections; `[A]` opens product detail (modal 880); `[X]`
preview. Initial focus: first rail item on first visit, last section afterwards.
**Compact:** rail → horizontal chips; hero 796 × 200; 2 tiles per row.
**Acceptance:** no tile shows a Robux number not fetched at runtime; no countdown appears on any non-event item; each
Bullion spend passes the Purchase confirm; buying a premium vehicle that is already owned is impossible in the UI.

### S21 Profile (`Screens/Profile`, section)

Tabs `SUMMARY` · `BATTLES` · `VEHICLES` · `ACHIEVEMENTS` (embeds §S19).

| Tab | Content | Bindings |
|---|---|---|
| SUMMARY | Rank insignia 128 (`ranks/rank_NN`), rank title, account level progress; 10 stat tiles 280 × 120 (`num.l` value + `label`): Battles, Win rate, Avg damage, Avg XP, Survival rate, Hit rate, Penetration rate, Avg spotted, Max damage, Max kills; class split bars (5 classes, glyph + bar + battles); most-played vehicle card | `PV.account`, `PV.stats` (rates computed: wins / battles etc., 1 dp) |
| BATTLES | Last 20 battles (`PV.battleHistory`, D§14): date (relative), map, mode / battle type, vehicle, outcome chip (VICTORY verdant tick / DEFEAT danger bang / DRAW steel dash), damage, kills, XP, net credits; row → Results (§S38: full if `SS.resultsCache` has it, else summary-only view) | `PV.battleHistory` |
| VEHICLES | Sortable table: vehicle, tier, class, battles, win rate, avg damage, max damage, mastery badge, barrel bands, last played | `PV.vehicles[*].stats` |
| ACHIEVEMENTS | §S19 | `PV.achievements` |

Profiles of **other** players are shown only as the Results player card (§S38) and the platoon member card (§S23); a
full public profile is P2 (needs a server read of another profile).
**Acceptance:** rates never divide by zero (show `—`); every number uses §1.11.

### S22 Settings (`Screens/Settings`, section, keepAlive)

```
┌[‹] SETTINGS ┊ Changes save automatically ┊                                                                  ┐
├────────────────┬───────────────────────────────────────────────────────────────┬────────────────────────────┤
│ GRAPHICS       │ QUALITY PRESET          [ Low | Medium | High | Custom ]       │ QUALITY PRESET             │
│ AUDIO          │ Vehicle detail          [ ◂ High ▸ ]                           │ Sets vehicle detail,       │
│ MUSIC          │ Effects quality         [ ◂ Medium ▸ ]                         │ effects and shadows for    │
│ EFFECTS        │ Shadows                 [■■ On ]                                │ this device type (PC).     │
│ INTERFACE      │ Brightness              ───────●──── +2                        │ [preview image]            │
│ HUD            │ …                                                              │                            │
│ CONTROLS       │                                                                │                            │
│ CONTROLLER     │                                                                │                            │
│ TOUCH          │                                                                │                            │
│ CAMERA         │                                                                │                            │
│ ACCESSIBILITY  │                                                                │                            │
│ NOTIFICATIONS  │                                                                │                            │
│ MINIMAP        │                                                                │                            │
│ GAMEPLAY       │                                                                │                            │
│ PERFORMANCE    │                       [ RESET CATEGORY TO DEFAULTS ]           │                            │
└────────────────┴───────────────────────────────────────────────────────────────┴────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Category list | (144, 72, 320, 920) | 15 categories; Compact = top chips |
| Settings list | (488, 72, 920, 920) | `SettingRow` 64 px: label `body`, control right-aligned 360 wide |
| Description | (1432, 72, 464, 920) | name `h4`, explanation `body.s`, preview art or live sample (colour schemes, reticle, minimap), default value |

Controls: `Toggle`, `Slider` (with numeric field; `ui_slider_tick`), `Stepper` (◂ value ▸), `Segmented`, `Dropdown`,
`KeyBind`. Every change applies **live** (no Apply button) and is saved by `SettingsSet` (1.5 s debounce). Settings
read only by the battle client apply on the next frame there too. Controller: `[LB]/[RB]` categories; D-pad rows; left
/ right adjusts; `[X]` reset the focused row; `[Y]` reset category (confirm). In battle, the Field menu exposes AUDIO,
HUD, CAMERA, CONTROLS / CONTROLLER / TOUCH sensitivities and ACCESSIBILITY only.

**Keys.** Stored in `PV.settings` (≤ 128 keys). Device-class keys end in `.pc`, `.mob` or `.con`. Encoded keys hold a
compact string. This table defines **117 keys**; a new setting must join an encoded key if the total would exceed 120.

| Category | Setting → key · control · values · **default** |
|---|---|
| GRAPHICS | Quality preset → `gfx.preset.<dc>` · segmented · Low / Medium / High / Custom · **Auto** (first launch picks Low on mobile, High on PC/console). Custom values → `gfx.custom.<dc>` (encoded): vehicle detail Low/Med/High (LOD0 2/3/4, LOD1 3/8/12, D§18) · effects quality Low/Med/High (particle caps D§18) · shadows On/Off · post-processing On/Off · weather effects On/Off · track marks On/Off · dust and exhaust On/Off · brightness −10…+10 (ColorCorrection, **0**). (6 keys) |
| AUDIO | Master, Music, Ambience, Vehicles, Weapons, Impacts, Interface, Voice → `audio.master` … `audio.voice` · sliders 0–100 · **80, 60, 70, 80, 85, 85, 70, 90** · Device preset `audio.device` Speakers / Headphones / Phone · **Speakers (Phone on mobile)** · Mono `audio.mono` **Off** · Night mode `audio.night` **Off** · Reduced audio fatigue `audio.fatigue` **Off** (AU§7). (12) |
| MUSIC | `music.flags` (encoded): garage music On · battle music On · dynamic intensity On · results music On (AU§11). Volume lives in AUDIO. (1) |
| EFFECTS | Camera shake `fx.shake` 0–100 **60** · Recoil kick `fx.recoil` **On** · Hit flashes `fx.flash` **On** · Low-HP vignette `fx.vignette` 0–100 **70** (cap 35 % opacity, §3) · Damage numbers `fx.damageNumbers` Off / Floating / On marker **Floating** · Hit callout text `fx.callouts` **On** · Reduce effects while aiming `fx.aimReduce` **Off**. (7) |
| INTERFACE | UI scale `ui.scale` 80–120 % **100** · Panel opacity `ui.panelOpacity` Follow Roblox / 60–100 % **Follow** · Tooltips `ui.tooltips` **On** · Tooltip delay `ui.tooltipDelay` Short / Normal / Long **Normal** · Title screen `ui.titleScreen` **On** · Open debrief after battle `ui.resultsAuto` **On** · 12-hour clock `ui.clock12h` **Off** · Keyboard hints bar `ui.hintsKbm` **Off**. (8) |
| HUD | HUD scale `hud.scale` 80–150 % **100** · Team panels `hud.teamPanels` Hidden / Compact / Full **Full** · Team HP `hud.teamHp` Full / Bar only / % only / None **Full** · Damage log `hud.damageLog` Off / 4 / 8 lines **8** · Kill feed `hud.killFeed` **On** · Battle chat `hud.chat` **On** (forced Off on console) · Marker names `hud.markerNames` On Alt / Always / Never **On Alt** · Marker HP numbers `hud.markerHp` On Alt / Always **On Alt** · Reticle size `hud.reticleSize` 80–120 % **100** · Server reticle `hud.serverReticle` Off / On / Both **Off** (D§3) · Effective armor at reticle `hud.effArmor` **Off** · Ribbons `hud.ribbons` **On**. (12) |
| CONTROLS | Bindings `ctl.bind` (encoded; §S40 defaults) · Mouse sensitivity arcade `ctl.sensArcade` 0.1–3.0 **1.0** · sniper `ctl.sensSniper` **0.8** (× tan(FOV/2) scaling, D§16) · Invert Y `ctl.invertY` **Off** · Sniper `ctl.sniperMode` Toggle / Hold **Toggle** · Free look `ctl.freeLook` Hold / Toggle **Hold** · Info overlay `ctl.info` Hold / Toggle **Hold** · Wheel past min zoom enters sniper `ctl.wheelSniper` **On**. (8) |
| CONTROLLER | Bindings `pad.bind` (encoded) · Look sensitivity arcade `pad.sensArcade` **1.0** · sniper `pad.sensSniper` **0.7** · Response curve `pad.curve` Linear / Default (2.0) / Aggressive (3.0) **Default** · Deadzone left `pad.deadzoneL` 5–30 % **12** · right `pad.deadzoneR` **10** · Invert Y `pad.invertY` **Off** · Vibration `pad.haptics` 0–100 **70** · Cruise control on L3 `pad.cruise` **On** · Sniper `pad.sniperMode` Toggle / Hold **Hold**. (10) |
| TOUCH | Aim sensitivity `touch.sens` **1.0** · sniper `touch.sensSniper` **0.7** · Fire button size `touch.fireSize` 90–120 % **100** · Custom layout `touch.layout` (encoded positions, `CUSTOMIZE LAYOUT` editor P2) · Movement stick `touch.stickMode` Dynamic / Fixed **Dynamic** · Vibration `touch.haptics` **Off**. (6) |
| CAMERA | Field of view `cam.fov` 60–90 **70** (D§16) · Starting distance `cam.distance` Near / Mid / Far **Mid** · Sniper horizontal stabilisation `cam.sniperStab` **On** · Zoom steps `cam.zoomSteps` (multi-select of ×2/×4/×8/×16/×25, optics-limited) **×2 ×4 ×8** · Free look returns `cam.freeLookReturn` Instantly / Smoothly **Smoothly**. (5) |
| ACCESSIBILITY | Team colours `a11y.scheme` Default / Deuteranopia / Protanopia / Tritanopia **Default** (live preview card) · High contrast `a11y.highContrast` **Off** · Text size boost `a11y.textBoost` Follow Roblox / +15 % / +30 % **Follow** · Reduced motion `a11y.reducedMotion` Follow Roblox / On / Off **Follow** · Reduced effects `a11y.reducedEffects` **Off** · Captions `a11y.captions` Off / Crew / Crew + radio **(first-launch choice)** · Caption size `a11y.captionSize` Normal / Large **Normal** · Sound visualisation `a11y.soundViz` **Off** · Hold-to-confirm `a11y.holdConfirm` 0.6–2.0 s / Two-step **1.2 s**. (9) |
| NOTIFICATIONS | Categories `ntf.categories` (encoded: rewards, research, missions, social, store; all **On**) · Toast duration `ntf.duration` Normal / Long (×2) **Normal** · Notification sound `ntf.sound` **On** · Quiet while queued `ntf.dndQueue` **On** · Friend online alerts `ntf.friendOnline` **Off** · Platoon invites from `ntf.invitesFrom` Everyone in this server / Friends / Nobody **Everyone**. System notices cannot be turned off. (6) |
| MINIMAP | Size `map.size` 224 / 288 / 352 / 416 / 480 **352** (D§16) · Opacity `map.opacity` 40–100 % **90** · Rotate with camera `map.rotate` **Off** · Circles `map.circles` (encoded: view range On, 445 m spotting limit On, 564 m draw limit Off) · Last-known markers `map.lastKnown` **On** (30 s, D§21 #11) · Grid labels `map.grid` **On** · Names on minimap `map.names` Off / Platoon / All **Platoon** · Camera cone `map.cone` **On**. (8) |
| GAMEPLAY | Last mode `gp.mode` (internal) · Region `gp.region` Auto / NA / SA / EU / APAC / OCE **Auto** (D§8 pool key) · Auto-spectate after destruction `gp.autoSpectate` **On** · Offer "start now with bots" `gp.botsPrompt` **On** · Platoon auto-ready `gp.autoReady` **Off**. Battle-type opt-outs and map blacklist live in `PV.matchmaking` (§S06), not here. (5) |
| PERFORMANCE | `perf.<dc>` (encoded): stats overlay Off / FPS / FPS + ping **Off** · low-memory mode **Off** (mobile < 4 GB: **On**) · garage scene Full / Static **Full** · pause hangar animation behind full screens **On**. (3) |
| (internal) | `garage.selected`, `garage.rows` (1/2), `garage.filters`, `garage.sort`, `garage.lineup1` … `garage.lineup5`, `seen` (encoded per area), `tut.hints` (encoded coach-mark flags). (11) |

**Acceptance:** every setting applies within one frame (audio within one mixer block); the key count stays ≤ 120;
keyboard rebinding rejects reserved keys and prompts to swap on conflicts (REG-INP-05); "reset category" restores
the defaults in this table exactly.

### S23 Platoon (`Screens/Platoon`, modal 880 from the platoon strip; Compact sheet)

```
┌ PLATOON  2 / 3 ─────────────────────────────────────────────────────────────────────────── [×] ┐
│ ┌[avatar] RidgeRunner ♛ ┐ ┌[avatar] OkraTank      ┐ ┌ [ + ]  INVITE      ┐                    │
│ │ Section Leader         │ │ Gun Sergeant          │ │                    │                    │
│ │ VIII ◈ Tukkhald  READY │ │ VIII ⬢ Tundmal NOT RDY│ │                    │                    │
│ └────────────────────────┘ └───────────────────────┘ └────────────────────┘                    │
│ ⚠ Same tier required · max 1 artillery · 3 players                                               │
│ INVITE  [ IN THIS GARAGE | FRIENDS | RECENT ]   [search name…]                                    │
│  [avatar] Vellmar_9     In this garage      VII  [ INVITE ]                                       │
│  [avatar] Pinewatch     Friend · other server     [ INVITE ]                                      │
│ PLATOON CHAT  ……………………………………………………………… [type a message]                                     │
│                                   [ LEAVE ]  [ DISBAND ]                    [ READY ]             │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

* **Member card** 264 × 120: Roblox headshot, display name, rank title, selected vehicle (tier, class glyph, name),
  ready state; leader circlet (`ui/crown_leader`); leader-only overflow on other cards: `KICK`, `MAKE LEADER`.
* **Rules line** (D§8): ≤ 3, same tier, ≤ 1 artillery; violations name the member ("OkraTank: Tier IX, others Tier
  VIII"). The leader's TO BATTLE stays blocked until all members are ready and rules pass.
* **Invite lists:** players in this Hub server (Roblox `Players`), friends (`GetFriendsOnline`, with location), recent
  platoonmates (`PV.social.recentPlatoonmates`); blocked users never appear (`PV.social.blocked`). Invites respect the
  receiver's `ntf.invitesFrom`.
* **Invite lifecycle:** `INVITE` (`→ PlatoonInvite`, 0.2/s) → button shows "Invited · 0:30" countdown → receiver gets an
  actionable toast (30 s; also in the center) → `ACCEPT`: same server = joins at once; other server = "Joining
  RidgeRunner's garage…" overlay, the server teleports the receiver to the leader's Hub server, where the platoon join
  completes on arrival → toast "Joined RidgeRunner's platoon". Expired / declined → sender toast.
* **Platoon chat:** a `TextChatService` channel per platoon (server-created, filtered by Roblox); hidden on console
  (chat window disabled).
* **States:** none (strip shows invite slots) · forming · ready check · queued (cards locked, `CANCEL` only for the
  leader) · in battle.
* **Controller:** initial focus = first empty slot (`INVITE`); `[LB]/[RB]` invite list tabs; `[Y]` ready toggle.
* **Acceptance:** a member leaving mid-queue cancels the platoon's ticket and shows why; promoting a leader is
  immediate for all members within one `PlatoonState` push; no invite can be sent faster than the rate limit (the
  button shows the cooldown).

### S24 Social (`Screens/Social`, drill-in from the top bar)

* Tabs `FRIENDS` · `RECENT` · `BLOCKED`. Friend rows 64 px: headshot, display name, presence chip — `In this garage`
  (verdant), `In HULLDOWN` (other Hub server), `In battle` (lock; join disabled), `Online` (other experience),
  offline friends hidden behind "Show offline (24)".
* Actions per row: `INVITE TO PLATOON` · `JOIN` (other Hub server, `→ JoinFriend`, confirm "You'll move to their
  garage server.") · `INVITE TO HULLDOWN` (Roblox `SocialService:PromptGameInvite`, only if
  `CanSendGameInviteAsync`) · overflow: `BLOCK` (Roblox `PromptBlockPlayer` for in-server players + our list).
* Add friend for in-server players: Roblox `PromptSendFriendRequest`. Reporting uses Roblox's own menu (copy:
  "To report a player, open the Roblox menu").
* Acceptance: presence refreshes every 30 s and on open; no friend data is shown for users the player blocked.

### S25 Notification center (`Screens/Notifications`, drill-in from the bell or `[View]`)

* Right-side panel 560 × 960 (Compact sheet). Filter chips `ALL` · `BATTLES` · `REWARDS` · `SOCIAL` · `SYSTEM`;
  `MARK ALL READ`.
* Entries 88 px grouped `TODAY` / `EARLIER`: type icon 32, title `body.s` Bold, body `caption` (2 lines), relative
  time, unread dot, action button (deep link, §1.3) or inline `ACCEPT` / `DECLINE` for invites still valid.
* Session-scoped plus derived entries (pending results, claimable missions, invites); max 100, oldest dropped.
* Viewing the panel marks visible entries read (REG-UI-09).

### S26 Game menu (`Screens/GameMenu`, modal 480; Garage root Back)

Buttons (secondary, 432 × 52): `RESUME` (initial focus) · `SETTINGS` · `CONTROLS` (key/button reference cards for
the current input mode, generated from bindings) · `PROVING FIELD` · `HELP & TIPS` (searchable tip cards) · `ABOUT &
LICENCES`. Footer `caption`: version, region, server id short hash, and "To leave, open the Roblox menu
([Esc] / [≡])" — the game never binds or imitates the Roblox menu.

### S27 Tutorial overlays and Proving Field (`Screens/Tutorial`)

**Coach mark** (`CoachMark` component, Tooltip layer): scrim `bg.scrim` at 60 % with a cut-out around the target
(4 rectangles + a 2 px dusk outline with chamfered corners), callout card 360 wide placed beside the target (same
placement rules as tooltips): step counter `micro` ("2 / 6"), title `h4`, body `body.s` (≤ 3 lines), `NEXT` /
`SKIP TUTORIAL` (tertiary). Steps that require an action ("Press RESEARCH") hide `NEXT` and restrict focus and clicks to
the target. Glyph prompts use the current input mode. Reduced motion: no scrim fade-in movement.

**Garage chain** (`PV.account.flags.tutorialStep`, `→ SetTutorialStep`), each step shown once, skippable as a whole:

| Step | Trigger | Target | Message |
|---|---|---|---|
| 1 | first Garage show | TO BATTLE | "This starts a battle with the selected vehicle." |
| 2 | after first battle's debrief | top-bar XP bar | "XP earned in battle stays on this vehicle." |
| 3 | vehicle XP ≥ cheapest module | MODULES tile | "Research better modules here." |
| 4 | first module researched | Research node `MOUNT` | "Mount it to use it." |
| 5 | XP ≥ next vehicle cost | Tech Tree rail | "A new vehicle is ready to research." |
| 6 | first vehicle bought | carousel card | "Select it here. Each vehicle keeps its own crew." |
| 7 | first crew perk slot ready | CREW tile | "Your crew can learn a perk." |
| 8 | Tier III reached | EQUIPMENT tile | "Equipment improves one stat. Match the slot's category for +15 %." |
| 9 | first Credits shortfall | error toast | "Lower tiers earn more Credits per battle." |

Contextual one-time hints (`ST.tut.hints`): first artillery battle, first wheeled vehicle, first magazine / dual gun /
siege mode, first Tier XI.

**Proving Field** (mode `Bootcamp`): three drills on the proving-grounds map versus Recruit bots, each with an
objective card top-centre 560 × 88 (`h4` objective, `caption` sub-goal, progress pips), large glyph prompts 48 px at
bottom-centre ("[W][A][S][D] Drive", "[RMB] hold to look around", "[Shift] sniper view"), and a between-drill summary
card. Drills: **1 Drive and look** (reach 3 markers, use sniper view), **2 Fire and armor** (shoot plates showing the
3/2/1 reticle segments, angle your hull against a bot, read the damage panel, use a repair kit), **3 Spot and capture**
(stay hidden in bushes, spot with the team, capture a base). Completion sets `bootcampCompleted` and grants the
content-defined reward (reward toast in the Garage). Every drill can be restarted or skipped from the Field menu.

**Acceptance:** coach marks never trap the player (Back always offers "Skip tutorial"); no tutorial step blocks a
purchase confirm or the queue; the chain resumes at the stored step after a rejoin.

### S28 Deploying and returning (`Screens/Deploying`, Loading layer during teleports)

**Out (Hub → Battle).** On `MatchFound` the Garage shows `BATTLE FOUND` for 1.0 s, then this overlay fades in over
300 ms: map art full-bleed (512 × 288 card upscaled only if the 1280 × 720 export is not loaded yet) with a 40 % ink
scrim, map name (B§9 overlay style: Oswald Bold UPPER on a `bg.panel` plate with the dusk ridge underline), battle type
chip, and a step list (`label`): `Battle reserved ✓` · `Deploying…`. The same frame is handed to
`TeleportService:SetTeleportGui` so the picture persists through the teleport and into the Battle place's
`ReplicatedFirst` (which reads `GetArrivingTeleportGui`) without a black gap. Not cancellable after `Found`.
Teleport failure (D§19: 5 attempts, 40 s Hub deadline) → fade back to Garage, `Queued` state at the original
`enqueuedAt`, toast (§S06).

**Back (Battle → Hub).** After the 6 s end banner (§S37) the battle client hands a teleport GUI with the outcome word
(`VICTORY` / `DEFEAT` / `DRAW`, `h1`), map name and "Returning to garage…". In the Hub, Boot (§S01) shows its short
form (no tips) until `DataSync`; the Garage then opens with the Debrief (§S38) on top as soon as `ResultsReady`
arrives (setting `ui.resultsAuto`), or a `ResultsReady` toast if the player has already navigated elsewhere.

### S29 Battle loading (`Screens/BattleLoading`, Battle place)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ (map art, 40 % scrim)                                                                                    │
│ ┌─ YOUR TEAM ──────────────────┐        ╔══════════════════════════════╗        ┌─ ENEMY TEAM ───────────┐│
│ │◈ VIII Tukkhald   RidgeRunner●│        ║ CINDER VALLEY                ║        │⬢ VIII Regnion  Vellmar_9││
│ │⬢ VIII Tundmal    OkraTank  ②│        ║ ▔▔▔ (dusk ridge underline)   ║        │◈ IX Sovrion    BOT      ││
│ │◉ VII  Gardelle   BOT        │        ║ OPEN TRIALS · CONTEST        ║        │…                        ││
│ │…  15 rows                    │        ║ Capture the enemy base or    ║        │                         ││
│ │                              │        ║ destroy every enemy vehicle. ║        │                         ││
│ └──────────────────────────────┘        ╚══════════════════════════════╝        └─────────────────────────┘│
│                       TIP  Hits on the lower front plate often penetrate heavies.                         │
│        ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▱▱▱▱▱▱  Loading map 72%                                       │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Element | Rect | Content / binding |
|---|---|---|
| Map art | full | `Maps/<id>` 1280 × 720 thumbnail (B§9), 40 % ink scrim, climate strip along the bottom edge |
| Ally list | (48, 120, 520, 15 × 40) | `RosterRow` 40 px: class glyph 20 (ally colour), tier `label`, vehicle name `body.s` Bold, player name `caption` (or `BOT` chip with skill: Recruit / Regular / Veteran, D§8), platoon pip number, self row with `team.self` text and 2 px white left edge. Sorted by tier desc, then class order heavy, medium, TD, light, artillery. `BV.roster` |
| Enemy list | (1352, 120, 520, 600) | same, enemy colour |
| Map card | (640, 160, 640, 300) | map name `h1`, dusk ridge underline, mode · battle type `label`, objective sentence `body.l` (per battle type, §S29.1), team size "15 v 15" |
| Tip | (360, 860, 1200, 48) | class- and vehicle-aware tips (e.g. artillery, magazines) |
| Progress | (560, 940, 800, 4) + status (560, 952, 800, 24) | `Loading map` (map build + `MapReady`, D§10) → `Loading vehicles` → `Waiting for players 27/30 · bots take over in 0:31` (45 s arrival window, D§9) → hands over to §S30 |

#### S29.1 Objective copy (original)

| Battle type | Objective sentence |
|---|---|
| Contest | Capture the enemy base or destroy every enemy vehicle. |
| Crossroads | Hold the central base or destroy every enemy vehicle. Capturing stops while both teams are inside. |
| Breach (attackers) | Capture the defenders' base before time runs out, or destroy every defender. |
| Breach (defenders) | Hold your base until time runs out, or destroy every attacker. |
| Drill | Practice against bots. Rewards are reduced. |

**Music:** `LOADING` cue (AU§11). **Compact:** lists collapse to class glyph + tier + vehicle (24 px rows), map card
on top, tip hidden. **Acceptance:** rosters render the moment `BV.roster` arrives (no waiting for the map); the
progress line never claims "ready" before `MapReady`; bot rows are always labelled.

### S30 Pre-battle countdown (`Screens/Countdown`, over the HUD)

The 3D scene and HUD are live; the player can look around, aim and enter sniper view, but cannot move or fire
(server-enforced until GO). Duration **20 s** (D§9).

| Element | Rect | Content |
|---|---|---|
| Countdown block | (760, 260, 400, 140) | `label` "BATTLE STARTS IN" + `num.xl` clock `0:14` (`Format.clock`, ceil) |
| Objective card | (660, 420, 600, 64) | battle-type objective (§S29.1), `body` on a `bg.scrim` plate |
| Waiting line | (660, 492, 600, 24) | "Waiting for 2 players · bots drive their vehicles until they arrive" when arrivals are late (D§9) |
| Final 3 s | centre (860, 390, 200, 200) | `display.hero` numerals 3 · 2 · 1 then `GO`; the countdown block, objective card and waiting line fade out at T−3 |

**3-2-1-GO sequence:** at T−3, −2, −1 each numeral fades in at 115 % scale and settles to 100 % over 200 ms
(`enter` easing, no overshoot), holds, and fades out over the last 150 ms; `ui_countdown_tick` on each. At T = 0
`GO` appears in `accent.dusk` with the dusk ridge underline drawing left-to-right in 400 ms, `ui_countdown_go` and the
music downbeat scheduled with `Play(atTime)` against `GetMixerTime()` (AU§11), then the block fades over 600 ms.
Reduced motion: no scale or sweep, fades only. The countdown clock is driven by `BV.countdownEndsAt` (server time
offset), so all clients show the same second. **Acceptance:** the GO frame is within 1 frame of input unlock on the
local client (server tick latency aside); team panels and minimap are visible from the first countdown frame.

### S31 Battle HUD (`Screens/BattleHUD/*`, HUD layer)

**Layout (Regular, 1920 × 1080, HUD scale 100 %; `T` = bottom of the engine top-bar row in HUD space, ≈ 56):**

```
┌─[Roblox]───────────────────┬──────────── H-01 SCORE ────────────┬──────────────────────────────────────────┐
│ H-03 ALLIES                │   7  ███████████ 11:42 ██████████  5 │                              H-03 ENEMIES │
│ ◈ VIII Tukkhald  Ridge…  ▬ │      14,250          ⏱        11,980 │ ▬ Vellmar_9   Regnion VIII ⬢            │
│ ⬢ VIII Tundmal   OkraT…② ▬ │  H-02 [◎ CAPTURING ENEMY BASE ▬▬▬▱ 64 ×3]                     …            │
│ …                          │           H-14 [^ spotted]                                    H-12 KILL FEED │
│                            │                                                                  ▸ ▸ ▸     │
│ H-19 CHAT                  │                 H-07 [⬢ VIII Regnion ▬▬▬▬ 1,120  212 m]                      │
│ [Radio] OkraTank: Attack   │                                                                              │
│                            │                      ( ◜ ⊙ ◝ )  7.4    ← H-05 reticle + reload               │
│ H-11 DAMAGE LOG            │                      H-15 [DAMAGE 358] ribbons                              │
│ −358 [AP] Regnion ⚙Engine  │                                                                              │
│ BLOCKED [APCR] unseen      │                H-20 captions [Crew] Engine damaged                           │
│ H-09 ▣ 2,340 ◇ 860 ▤ 1,200 │                                                         ┌── H-04 MINIMAP ──┐│
│ ┌ H-09 DAMAGE PANEL ──────┐│        H-10 [⚙][1 AP 30][2 APCR 6][3 HE 6] [4 ✚][5 ✚][6 ⛑]   │ A B C D E F G H J K││
│ │ ♥ 1,240 / 1,620  38 km/h││                                                          │ 1    ◈   ▲         ││
│ │ ⚙ ▮ ◍ ⌐ ◎ ◉ ▭ ▭  ◉◉◉◉ 🔥 ││                                                          │ …                  ││
│ └─────────────────────────┘│                                                          └────────────────────┘│
└────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┘
```

| Id | Element | Rect | Gui (insets) |
|---|---|---|---|
| H-01 | Score bar | (640, 8, 640, 88) | `HUD` (Device) |
| H-02 | Capture bars | (720, 104, 480, 28) each, max 2 stacked | `HUD` |
| H-03 | Team panels | allies (16, T+8, 320, 360) · enemies (1584, T+8, 320, 360) | `HUD` |
| H-04 | Minimap | (1552, 712, 352, 352) default; sizes 224 / 288 / 352 / 416 / 480 anchored bottom-right | `HUDInput` (Core) |
| H-05 | Reticle and reload | centre | overlay |
| H-06 | Penetration indicator | reticle ring segments | overlay |
| H-07 | Target card | (840, 404, 240, 44) | `HUD` |
| H-08 | Vehicle markers | world-projected | pooled overlay (`PreRender`) |
| H-09 | Damage panel + efficiency strip | (16, 864, 360, 200) + strip (16, 832, 360, 24) | `HUD` |
| H-10 | Mechanic, ammo, consumables bar | (704, 984, 512, 80), centred; 664 wide when event abilities show | `HUDInput` |
| H-11 | Damage log | (16, 624, 440, 8 × 24) | `HUD` |
| H-12 | Kill feed | (1504, 440, 400, 5 × 28) | `HUD` |
| H-13 | Hit direction | ring r 220 around centre | overlay |
| H-14 | Spotted alert | (928, 176, 64, 64) (+ ripples to 128) | `HUD` |
| H-15 | Ribbons | (810, 660, 300, 3 × 40) | `HUD` |
| H-16 | Kill and hit callouts | (760, 616, 400, 32) | `HUD` |
| H-17 | Status banner | (660, 296, 600, 48) | `HUD` |
| H-18 | Low-HP vignette | full screen edges | `HUD` |
| H-19 | Chat | slot (16, 440, 440, 176) | engine chat window (TextChatService) |
| H-20 | Captions | (560, 880, 800, 56) | `HUD` |
| H-21 | Sound visualisation | ring r 300 around centre | overlay |
| H-22 | Incoming artillery warning | (896, 352, 128, 44) | `HUD` |
| H-23 | Perf overlay | (1784, T+8, 120, 20) when enabled (moves the enemy panel down 28) | `HUD` |

`HUD` is the gauges gui (`DeviceSafeInsets`, non-interactive, never under the Roblox buttons: top-left items start
at `T`); `HUDInput` holds anything clickable or touchable (`CoreUISafeInsets`). HUD scale (80–150 %) scales every
element about its anchor; at > 120 % the damage log drops to 4 lines and the kill feed to 3 so nothing overlaps.

#### H-01 Score bar

Row 1 (y 8–64): ally score `num.l` (enemies destroyed by the allied team, ally colour) · battle clock `num.xl`
(`Format.clock` ceil) · enemy score. Row 2 (y 68–96): two team-HP bars 260 × 10 (`bg.inset` track, team fill, 1 px ink
outline) growing outward from the clock, with `mono` totals under each ("14,250"). Team HP mode (`hud.teamHp`):
Full / Bar only / % only / None (D§16). Timer states: normal `text.primary`; < 2:00 `state.warning` + `ui/timer`
glyph; < 0:30 `state.danger` + a 1 Hz scale pulse 1.00 → 1.06 (none under reduced motion; the glyph carries it).
Binding: `BV.teams`, `BV.timeLeftS`. Team HP of the enemy team is the sum the server sends for the scoreboard
(public), not derived from spotted vehicles.

#### H-02 Objective and capture bars

Shown only while a base has points. Bar 480 × 28: capture-point glyph (`battle/capture_point`, contested variant
when contested) · label `label` ("CAPTURING ENEMY BASE", "ENEMY CAPTURING YOUR BASE", "CROSSROADS BASE" + owner) ·
progress fill 0–100 in the capturing team's colour · `mono` points · cappers `×3`. While the player's own base is being
captured: `cue_capture_warning_loop` (halved after 10 s with `audio.fatigue`), the base marker on the minimap flashes
at 1 Hz (the sound's visual twin). A reset flashes the bar white 80 ms, then drains 300 ms; resetting it yourself
fires a `DEFENSE` ribbon. Contested Crossroads shows "CONTESTED · capture paused" (D§9). `BV.capture`.

#### H-03 Team panels

Modes (`hud.teamPanels`, cycle with `[Tab]` tap / `[D→]` on pad): **Full** row 24 px: class glyph 16 · tier `micro`
· vehicle name `body.s` (14 rendered min) · player name `caption` · kills `mono`, HP as a 2 px team-colour line along
the row bottom; **Compact**: glyph · tier · HP bar 64 × 4; **Hidden**. Self row: `team.self` text + 2 px white left
edge; platoon: numbered pip (B§8.6); bots: `BOT` `micro` chip; destroyed: 50 % opacity, `team.destroyed` glyph with
the ink X, name struck through. Enemy rows show identity from the roster (public at load) but HP and alive state **only
as last received** from the server: currently spotted rows carry a 2 px enemy-colour left tick; not currently spotted
rows show the last known HP at 60 % opacity and a `battle/last_seen` glyph. The panel never reveals anything the
client was not sent (REG-SPT-08).

#### H-04 Minimap

Map image (generated top-down render per map, hash-checked, REG-MINI-02), grid `A–K` (no I) × `1–9, 0` labels in
`micro` along two edges (D§10), red-line border. Layers bottom to top: bases (ally ring, enemy ring + four target
ticks, capture points as four heavy ring segments, B§6.12) · view-range circle (`view_range_ring`, white 40 %), 445 m
spotting limit (`accent.steel` 30 %), optional 564 m draw limit (`map.circles`) · camera cone (white 35 %) ·
last-known ghosts (thin dashed ring + dot, opacity 100 % → 30 % over 30 s, then removed, D§5) · far records (2 Hz,
glyph at 80 %) · enemy glyphs 14 px · ally glyphs 14 px (+ platoon pip) · destroyed (60 %, X) · artillery shooter
rings (5 s, D§7.4) · pings (pin family `battle/ping_*`, 3 s pulse, max 12 visible) · self arrow (white, 20 px, always on
top). Hover / focus a glyph (big map only) shows vehicle and player name. **Input:** `[LMB]` on the minimap = "Enemy
spotted here" ping (`ping_spotted`), `[RMB]` = "Moving here" (`ping_position`) (D§9); `[-]`/`[=]` size; touch: tap to
open the big map (§S34). Rotation: north-up (default) or camera-up (`map.rotate`). Updates in `PreRender`; the image
is static.

#### H-05 Reticle, dispersion and reload

Pieces from `assets/icons/battle/reticle_*` (B§8.7), all white with ink keylines, tinted at runtime:

* **Centre dot** `reticle_center` 8 px, always `team.self` white.
* **Dispersion ring**: three `reticle_dispersion_segment` copies (100° arcs, 20° gaps) whose **radius** is the current
  aiming circle projected at the aim point: `r_px = (R_m × dist / 100) / (2 × dist × tan(FOV/2)) × viewportHeight`,
  where `R_m` is `BV.aim.dispersionNow` (client prediction, D§3). Minimum radius 12 px. The ring **shrinks smoothly**
  as aim converges (it is the convergence feedback). Server reticle option (`hud.serverReticle`): a 1 px `accent.steel`
  ring at `BV.aim.serverDispersion`.
* **Reload arc**: four `reticle_reload_arc_segment` quarter arcs at radius 44 (outside the minimum dispersion ring),
  progress masked by `UIGradient`, `text.secondary`, turning `accent.dusk` for the last 0.5 s; `mono` timer
  (`Format.seconds`) at (1032, 528). Gun ready: arc completes, flashes white 80 ms, settles to 20 % opacity;
  `cue_reload_complete`. Gun disabled (gun destroyed): the centre dot becomes an ink-keyed `state.danger` X with
  `micro` "GUN DESTROYED"; reload shows the repair timer instead.
* **Magazine / autoreloader / dual gun / charge** (D§4): pips row under the reticle at (928, 592, 64, 12): magazine = one 8 px
  chamfered pip per shell (filled = loaded) + intra-clip timer; autoreloader = per-slot mini bars filling
  independently; dual gun = two barrel pips L / R with their own reload rings, volley charge = a dusk arc filling around
  the dispersion ring for 1.0 s, then "1.5 s" between barrels; charged shot = the same charge arc (1.5 s) with "×0.6
  dispersion" or "+10 % damage" label per vehicle.
* **Target lock**: four `reticle_lock_bracket`s around the locked target's marker, dusk when locked;
  `cue_target_locked` / `cue_target_unlocked`.
* **Gun limits**: when the aim point is outside the gun's traverse or elevation arc (casemates ±11°, D§3), a short white
  arrow on the ring points toward the limit and the ring dims to 60 %.

#### H-06 Penetration indicator (D§16, B§8.7)

When the reticle ray hits a **visible** enemy vehicle, the client runs the **shared** `Penetration` code on the aimed
face (angle, normalization, 2/3-calibre, ricochet, spaced layers, HEAT gap, distance falloff) for the selected
(loaded) shell, at most 30 times per second:

| Result | Segments lit | Colour (secondary cue) | Target card note |
|---|---|---|---|
| T_eff ≤ 0.875 × pen | 3 | `state.success` (CVD: `pen.cb.yes`) | – |
| 0.875 < T_eff / pen < 1.125 | 2 | `state.warning` (`pen.cb.maybe`) | – |
| ≥ 1.125 × pen, or ricochet predicted | 1 | `state.danger` (`pen.cb.no`) | "Ricochet" when that is the cause |
| Ally under reticle | ring hollow (outlines only), fire feedback suppressed | – | "Ally" |
| Terrain / sky / not visible | 3 segments white 80 % (neutral) | – | – |

Unlit segments are white at 35 %. HE / HESH use the same thresholds against their own penetration; when they would not
penetrate, the target card adds "Splash damage only". Effective thickness readout in the target card is optional
(`hud.effArmor`).

#### H-07 Target card

240 × 44 above the reticle, shown while the reticle is over a visible vehicle or a vehicle is locked: class glyph 20
(team colour), tier, vehicle name `body.s` Bold, player name `caption` (or `BOT`), HP bar 200 × 4 + `mono`
"1,120 / 1,350", distance `mono` "212 m", optional "Eff. 186 mm". Fades out 300 ms after the target leaves.

#### H-08 Vehicle markers (B§8.6; one pooled overlay, no `BillboardGui`)

Marker = backing plate (marker frame art, ink 55 %) + class glyph 20 in team colour + tier `micro` + HP bar 64 × 6.
Name on `[Alt]` / `[A]` hold (or always / never per `hud.markerNames`); HP numbers likewise (`hud.markerHp`). Damage
chunks flash white 80 ms then drain over 300 ms. Scale 100 % at ≤ 100 m down to 70 % at 564 m. Allies are always
drawn (always replicated); enemies only while visible; platoon mates show the number tab; destroyed = class glyph 60 %
in `team.destroyed` with the 1.5 px ink X (no HP bar). Enemy markers never appear off-screen (minimap only). Marker
projection runs in `PreRender` for ≤ 30 markers with no allocations; occluded vehicles keep their markers (markers
mean "spotted", not "in line of sight").

#### H-09 Damage panel and efficiency strip

```
┌──────────────────────────────────────┐  efficiency strip above: [damage] 2,340 · [assist] 860 · [blocked] 1,200
│ ♥ 1,240 / 1,620              38 km/h │  HP num.xl + max num.m; speed mono + gear chip (F / N / R)
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▱▱▱▱▱▱▱▱ │  HP bar 328 × 10 (ally fill; damage chunk white flash 80 ms → drain 300 ms)
│ ⚙ ▮ ◍ ⌐ ◎ ◉  ▭ ▭                     │  modules 32 px: engine, ammo rack, fuel, gun, turret ring, optics, track L, track R
│ ◉ ◉ ◉ ◉        🔥 FIRE   ⚡ 6.2 s     │  crew 32 px: commander, gunner, driver, loader; fire; stun timer
└──────────────────────────────────────┘
```

* Module and crew glyphs use the brand state grammar (B§6.8): OK = steel at 40 % opacity (positions learnable, not
  distracting), **damaged** = amber with the V-notch outline, **destroyed** = signal with the broken outline,
  **injured** crew = signal helmet with the first-aid badge. State changes pop to 100 % and scale 1.15 → 1.0 over 200 ms.
* **Repair**: a progress ring around a destroyed module's glyph and `micro` seconds (D§2 repair times ÷ f(L)); a
  repaired-to-damaged module stays amber.
* **Fire**: `modules/fire` 32 px flashing at 2 Hz (≤ 3 flashes/s), `FIRE` `label`, and the extinguisher slot in H-10
  gets a `state.danger` outline with its key glyph. Stun: `battle/stun` + countdown; the medkit slot highlights.
* Doubled crew roles show one glyph per seat with both tool marks (B§6.8).
* Efficiency strip: damage dealt, assist (spotting + tracking + stun), blocked, from own `BV` counters (own events
  only; never inferred from enemy state).
* Low HP (H-18): HP number turns `state.danger` below 25 %.

#### H-10 Mechanic, ammunition and consumables bar

```
 [⚙ X]   [1 ▲AP 30][2 ▲APCR 6][3 ▲HE 6]   [4 ✚ 42][5 ✚][6 ⛑ AUTO]   [7 event][8 event]
 mechanic        ammunition (keys 1–3)          consumables (keys 4–6)      event abilities (event modes only)
```

* Slots 64 × 64, 8 px gaps, 16 px between groups: icon 48; key glyph `micro` top-left (current input mode); count
  `num.m` bottom-right (ammo); special rounds keep the gold case + rim (B§6.10).
* **Ammo states:** *selected next* = 2 px dusk outline; *loaded* = 48 × 4 `text.primary` bar under the slot; *empty* =
  40 % + count 0 in `state.danger`. Pressing a shell key while reloading queues it (outline moves); pressing the
  selected key again within 0.5 s, or pressing it while the gun is loaded, **swaps now** with a full reload (D§4); a
  1.5 s hint "[2] again to swap now" appears after the first press while loaded.
* **Consumables:** cooldown = dark sweep clockwise + whole seconds `num.m` centred; active duration = verdant ring
  draining; `PASSIVE` / `AUTO` `micro` labels for rations, fuel and the automatic extinguisher; contextual highlight as
  in H-09. Use with no valid target (nothing to repair) plays `ui_error` and shows "Nothing to repair" for 1 s.
* **Mechanic slot** (when the vehicle has one, D§4): Siege mode (state + 2.0 s / 1.25 s transition ring), Wheeled speed
  mode (state + 1 s toggle), Hydropneumatic (passive: lights when the +4° / +3° bonus is active after 0.75 s still),
  Tier XI signature (RocketBoost charges, Turbo, ActiveCooling: duration ring then cooldown). Key `[X]` / pad `[B]` tap.
* Event abilities (`EventAbility`, event modes only, keys 7–8) appear right of the consumables with charges.
* Binding: `BV.own.ammo`, `selectedShell`, `queuedShell`, `consumables`, `mechanic`. Requests: `SelectShell`,
  `UseConsumable`, `ActivateMechanic` (4/s each).

#### H-11 Damage log (received)

Up to 8 lines (`hud.damageLog`), newest at the bottom, each fades after 12 s; `mono` 16 on a 50 % ink plate:

| Event | Line example |
|---|---|
| Penetration received | `−358  [AP] Regnion · Vellmar_9   ⚙ Engine` |
| Blocked / absorbed | `BLOCKED  [APCR] Regnion   290 blocked` (white) |
| Ricochet | `RICOCHET  [AP] Sovrion` |
| HE splash | `−61  [HE] splash · BOT Sovrion` |
| Fire / ram / fall / drown | `−40  FIRE` · `−86  RAM · Tundmal` · `−24  FALL` |
| Unseen attacker | `−358  [AP] unseen` — identity is shown **only** if the attacker was visible to the player's team at that moment (REG-SPT-08) |

The shell tag uses the `ammo.*` colour plus the 12 px shell silhouette; crits append the module / crew glyph.

#### H-12 Kill feed

5 lines × 6 s, newest on top, 28 px rows: `[class glyph] Name  ▸ [cause] ▸  [class glyph] Name`, names in team
colours, causes = shell silhouette, `hit_fire`, ammo-rack glyph, ram, drown, fall. Rows involving the player get a
`bg.panel` plate with a 2 px white left edge. A killer the player's team could not see is shown as `[?] Unseen` (no
identity, REG-SPT-08); the Debrief later reveals everything. `cue_ally_destroyed` / `cue_enemy_destroyed` (+3 dB when
it is the player's kill).

#### H-13 Hit direction indicators

`damage_direction` wedges at radius 220 around the screen centre, rotated to the hit's incoming bearing relative to the
camera yaw; arc width by damage share of max HP (D§16): ≤ 10 % → 24°, 10–30 % → 40°, > 30 % → 60°; `state.danger` fill
for damage, white hollow for blocked or ricochet. Life 4 s (fade over the last 1 s); hits within 15° merge and refresh.
The bearing is the shell's own path (the impact reveals it), not the shooter's position.

#### H-14 Spotted alert

The dusk crest chevron with two expanding ripple arcs at (928, 176), 2 s (D§5, D§21 #12), plus `cue_sixth_sense`
(ducks other buses 4 dB, AU§3.3). It fires 3 s after the server reports the player first team-visible to the enemy;
it does not fire while the commander is injured (the damage panel shows the injured commander), and there is no
"unspotted" cue. Reduced motion: the chevron fades in and out without ripples.

#### H-15 Ribbons

Max 3 stacked ribbons 300 × 36 (glyph 24 + `label` + `num.m` value), 2.5 s each; the same type merges and increments
within 2.5 s: `DAMAGE 358`, `CRITICAL`, `BLOCKED 290`, `SPOTTED ×2`, `ASSIST 120`, `DESTROYED`, `FIRE STARTED`,
`CAPTURE 12`, `DEFENSE 30`. Enter: slide 16 px up + fade 160 ms; exit fade 200 ms. Setting `hud.ribbons`.

#### H-16 Hit callouts and kill confirmation

On the player's own shots, a 0.9 s callout under the reticle (`label` + `battle/hit_*` glyph, colours from B§10.2):
`PENETRATED` (dusk), `CRITICAL · ENGINE` (amber + module glyph), `BLOCKED` (steel `#C9D1D8`), `RICOCHET` (ice),
`ABSORBED` (layered plate), `ALLY` (white, no damage). A kill shows `DESTROYED` with `hit_kill` in signal for 1.2 s.
These are the visual twins of the armor-result sounds (AU§6.8). Setting `fx.callouts`.

#### H-17 Status banner

One at a time, `state.warning` 4 px left stripe, `body` text, 48 px: `Overturned · self-righting in 7 s` (D§2) ·
`Drowning · 8 s to escape` (D§2) · `Immobilized` (tracks or engine destroyed) · `No input · a bot takes over in 0:30`
(D§9: warn at 60 s, bot at 90 s) · `Reconnected · control returned` · `Spectating Vellmar_9`.

#### H-18 Low HP

Below 25 % HP: `cue_low_hp_alarm` once and a `state.danger` edge vignette fading in over 400 ms at ≤ 35 % opacity
(D§16, `fx.vignette` scales it; 20 % cap under reduced effects); below 15 %: `cue_low_hp_heartbeat_loop` and the
vignette breathes at the heartbeat's 75 bpm between 25 % and 35 % (static under reduced motion).

#### H-19 Chat

Roblox `TextChatService` team channel (`RBXTeam`, all-chat off, D§9), using the engine chat window configured by
`ChatWindowConfiguration` (left-aligned, vertically centred, width and height scales chosen to fit the (16, 440, 440,
176) slot — exact fit is an in-engine verification item) and `ChatInputBarConfiguration.KeyboardKeyCode = Return`.
Command presets appear as `[Radio] OkraTank: Attack`. Hidden on console (chat window disabled) and by `hud.chat`.

#### H-20 Captions

Bottom-centre, max 2 lines, `body` on a 30 % ink plate, speaker glyph (crew role or radio), 4 s, queue of 3 mirroring
the callout queue priorities P0–P3 (D§17). Examples: `[Crew] Engine damaged`, `[Crew] Fire on board`,
`[Radio] OkraTank: Need help` (no exclamation marks, B§2).

#### H-21 Sound visualisation (`a11y.soundViz`)

Edge glyphs at radius 300: gunfire heard ≤ 300 m (calibre class S / M / L as glyph size 16 / 24 / 32) at the
**fuzzed** bearing of `ShotHeard` (D§17: snapped position + ±15° noise), shell flyby near-miss arcs, 1.5 s each.
Never for unspotted engines and never with identity.

#### H-22 Incoming artillery

When an artillery shell will land within its splash radius of the player, 1 s before impact (D§7.4): artillery class
glyph in `state.danger` + `micro` "INCOMING" at (896, 352) and a short ring pulse around the reticle.

### S32 Sniper and artillery overlays (`Screens/BattleHUD/Sniper`)

**Sniper view** (`Sniper` input context; own model hidden, D§16):

* Dark corner brackets frame at 92 % of the screen (`brand.khaki` 60 %, 2 px) and a horizontal mil-scale under the
  reticle (ticks every 1 mil, labelled every 5 in `micro`), both original; no full-screen scope mask (keeps peripheral
  information).
* Zoom readout `×4` `num.m` at (880, 528) left of the reticle; range to the aim point `mono` "312 m" at (1000, 556)
  (client raycast against the map; vehicle distance in the target card).
* Zoom steps ×2 / ×4 / ×8 (+ ×16 / ×25 by optics) from `cam.zoomSteps`; the wheel steps; past the minimum zoom the
  wheel returns to arcade view (`ctl.wheelSniper`).
* Team panels collapse to Compact, chat fades to 30 %, kill feed and ribbons stay; HUD elements at the screen edges dim
  to 70 % so the centre reads.
* Optional "reduce effects while aiming" (`fx.aimReduce`): hides own muzzle smoke and dust in sniper view.

**Artillery view** (B§8.7): top-down camera 100–200 m (D§16); ellipse reticle in `team.self` white sized to the
dispersion footprint on the ground; dashed `accent.steel` trajectory arc from the gun to the aim point (in the
side-profile inset 320 × 120 at (800, 920)); `mono` flight time readout "3.4 s" (minimum flight 2.5 s, D§7.4);
"Team-spotted targets only" note when aiming at an unspotted area. Reload and pen rules as above (artillery uses the
HE splash note).

### S33 Radial command menu (`Screens/RadialMenu`)

```
                         ATTACK
              NEED HELP    ▲     FOLLOW ME
                      ╲    │    ╱
           NEGATIVE ───  [ MAP ]  ─── AFFIRMATIVE
                      ╱  [ PING ]╲
           HOLD POSITION   │     RELOADING
                         DEFEND BASE
```

* Ring Ø 480 (Regular) / 300 (Compact, around the thumb), inner hub Ø 120; eight 45° sectors, `bg.panel` at 92 %;
  the hovered sector fills `bg.selected` with a dusk 3 px outer edge. Each sector: glyph 40 (`battle/cmd_*`) and a
  `label` name. Opens in 120 ms (fade + 0.96 → 1.0 scale; fade only under reduced motion); the battle continues.
* **Eight commands (D§9 presets):** N `ATTACK` · NE `FOLLOW ME` · E `AFFIRMATIVE` · SE `RELOADING` · S `DEFEND
  BASE` · SW `HOLD POSITION` · W `NEGATIVE` · NW `NEED HELP`. **Hub: `MAP PING`** opens the big map (§S34) in ping mode.
* **Context ping** (`[T]`, pad `[Y]` tap, touch Comms tap) uses what the reticle points at: visible enemy → `FOCUS FIRE`
  on that vehicle (target brackets on allies' screens) · ally → `THANKS` · own base → `DEFEND BASE` · enemy base →
  `ATTACK` · ground within 30 m of a visible or last-known enemy → `ENEMY SPOTTED HERE` · other ground → `MOVING HERE`.
  Together with the radial this covers all 12 presets.
* **Replies:** `AFFIRMATIVE` / `NEGATIVE` sent within 10 s of an ally's command attach to that command as a ✓ / ✗ pip on
  its marker (marker-only replies, D§9); otherwise they post as a chat preset.
* **Selection:** KBM hold `[C]`, move the mouse toward a sector (cursor locked; 40 px of travel selects), release to
  send, release in the hub to cancel; pad hold `[Y]` ≥ 250 ms, right stick direction (deadzone 0.5), release to send,
  `[A]` on the hub = map ping, neutral release cancels; touch hold Comms 250 ms, slide, release.
* **Rate limits** (D§9): markers 3 per 5 s and 12 per minute, chat presets 1 per 10 s. Limited sectors show a
  cooldown sweep and play `ui_error` if chosen.
* **Delivery on allies' screens:** minimap pin (pin family), world marker at the target or position (3 s), chat line
  `[Radio] Name: Command`, radio sound and caption (`a11y.captions`).

| Command | Glyph | Sound | Marker |
|---|---|---|---|
| Attack | `cmd_attack` | `radio_cmd_attack` | `ping_attack` at reticle ground point / enemy base |
| Defend base | `cmd_defend` | `radio_cmd_defend` | `ping_defend` on own base |
| Need help | `cmd_help` | `radio_cmd_help` | `ping_help` on sender |
| Follow me | `cmd_follow_me` | `radio_cmd_follow` | on sender |
| Hold position | `cmd_hold` (requested) | `radio_cmd_hold` (requested; interim `radio_static`) | `ping_position` on sender |
| Reloading | `cmd_reloading` | requested `radio_cmd_reloading` (interim `radio_static`) | on sender + remaining reload `mono` |
| Affirmative / Negative | `cmd_affirmative` / `cmd_negative` | requested keys (interim `radio_static`) | reply pip |
| Focus fire (context) | `cmd_focus_fire` (requested; interim `target_lock`) | `radio_cmd_attack` | brackets on target |
| Enemy spotted here (context, minimap LMB) | `cmd_enemy_spotted` | `radio_cmd_spotted` | `ping_spotted` |
| Moving here (context, minimap RMB) | `cmd_moving` (requested; interim `ping_position`) | requested (interim `radio_static`) | `ping_position` |
| Thanks (context on ally) | `cmd_thanks` (requested) | requested (interim `radio_static`) | on the ally |

### S34 Scoreboard and big map (`Screens/BattleHUD/Scoreboard`, `Screens/BattleHUD/BigMap`)

* **Scoreboard** (hold `[Tab]` / `[View]`; touch toggle button): centred panel 1400 × 800 at 92 % `bg.panel`. Two
  15-row tables (40 px rows): class glyph, tier, vehicle, player (`BOT`, platoon pip), kills, alive / destroyed. No
  damage numbers for others mid-battle **O** (they appear in the Debrief). Centre column 280 px: map, battle type,
  objective, clock, team HP. Bottom strip: the player's damage / assist / blocked / spotted, and tracked missions with
  **estimated** progress ("estimated · confirmed after battle"), `cue_objective_update` when an estimate completes.
* **Big map** (`[M]`, `[D←]`, minimap tap): 800 × 800 centred map with all minimap layers, larger glyphs (20 px) and
  names on hover; pings by click / cursor + `[A]` (pad moves a cursor with the left stick); legend strip below.
  The battle continues; the player's vehicle keeps its last input released (throttle 0) while the map is open on
  touch and gamepad **O**.

### S35 Destroyed and spectating (`Screens/BattleHUD/Spectate`)

* Banner (560, 200, 800, 120): `VEHICLE DESTROYED` `h2` + cause line "Regnion · Vellmar_9 · AP · ammo rack" — the
  attacker's identity only if it was visible to the player's team (else "Unseen enemy · AP"). Sound: the
  vehicle-destruction sound only (no UI cue; allies hear `cue_ally_destroyed`).
* After 4 s (or at once with `SPECTATE`), the camera follows the nearest living ally (`gp.autoSpectate`). Cycle allies
  with `[Q]`/`[E]` or `[LB]`/`[RB]`, touch arrows 56 px. The HUD switches to the spectated ally's damage panel and
  reticle (no pen indicator); the minimap stays the team's view. Music −6 dB + 2 kHz low-pass (D§17).
* `RETURN TO GARAGE` (secondary): "Your Tukkhald stays locked until the battle ends. Rewards arrive afterwards." (D§9)
  — no strike when destroyed.

### S36 Field menu (`Screens/BattleHUD/FieldMenu`, modal 560, `Menu` context; the battle never pauses)

Opened by `[Bksp]`, pad `[B]` held 0.6 s (a ring fills around a menu glyph bottom-right while holding), or the touch
menu button. Buttons: `RESUME` (initial focus) · `SETTINGS` (battle subset, §S22) · `CONTROLS` · `LEAVE BATTLE`
(destructive). Leave while alive: Destructive modal "Your vehicle is still fighting. If you leave, a bot takes over:
no victory bonus, and it counts as a strike (1 of 3 today)." with hold-to-confirm (D§9). Leave after destruction: plain
confirm, no strike. Proving Field adds `RESTART DRILL` and `SKIP DRILL`.

### S37 Battle end banner (`Screens/BattleHUD/EndBanner`)

On `Ended`: input locks, a full-width band (0, 380, 1920, 240) of `bg.scrim` slides in from both edges over 300 ms
(fade under reduced motion), `display.hero` `VICTORY` (`text.brand` with the dusk ridge underline) / `DEFEAT`
(`text.primary`) / `DRAW` (`text.secondary`), `battle_logo` above, and the reason line (`body.l`): "All enemy vehicles
destroyed" · "Enemy base captured" · "Your base was captured" · "Your team was destroyed" · "Time ran out" · "The
defenders held" · "Both sides fell at once". Stays **6 s** (D§9), then "Returning to garage…" and §S28. Music switches
to the `RESULTS_*` cue at the banner (AU§11).

### S38 Debrief / Results (`Screens/Results/*`, Hub, overlay over the Garage)

**Purpose.** Explain the battle and its rewards, line by line from the server ledger, and get the player back into
battle in one press (D§14). **Entry:** automatically after returning (`ui.resultsAuto`), the `ResultsReady` toast, the
notification center, or Profile › Battles. **Exit:** `TO BATTLE` (re-queues the same vehicle and mode), `GARAGE`, Back.

```
┌[‹] DEBRIEF ┊ Cinder Valley · Open Trials · Contest · 8:42 ┊ currencies                                         ┐
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  VICTORY                                              ┌──────── vehicle card (ViewportFrame 640 × 300) ───────┐ │
│  ▔▔▔▔▔ Enemy base captured                            │                 TUKKHALD · Tier VIII                  │ │
│  First win of the day ×2                              └───────────────────────────────────────────────────────┘ │
├─[ SUMMARY ]─[ PERSONAL ]─[ TEAM ]─[ REPORT ]─[ PROGRESS ]─────────────────────────────────────────── [LB][RB] ──┤
│ ┌DAMAGE──┐┌ASSIST──┐┌BLOCKED─┐┌SPOTTED─┐┌DESTROYED┐    ┌ VEHICLE XP ─┐┌ CREDITS ─────┐┌ FREE XP ┐┌ CREW XP ┐ │
│ │ 2,340  ││  860   ││ 1,200  ││   3    ││   2     │    │ 1,624  ×2   ││ +48,210 net  ││  81     ││ 1,624   │ │
│ └────────┘└────────┘└────────┘└────────┘└─────────┘    └─────────────┘└──────────────┘└─────────┘└─────────┘ │
│ ROLE SCORE ▬▬▬▬▬▬▬▬▬▬|▬▬ 1.24× class median   HONOURS [badge][badge]   TEAM XP RANK 3 / 15   PASS +8         │
│                                                                          [ GARAGE ]   [■■■ TO BATTLE ■■■]      │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Rect | Content |
|---|---|---|
| Header | (144, 72, 1752, 220) | outcome `display.hero` (VICTORY `text.brand` + dusk ridge underline / DEFEAT `text.primary` / DRAW `text.secondary`, never colour alone: the word carries it), reason `body.l`, first-win ×2 chip, AFK strike notice in `state.danger` if `afkStrike` ("Inactive in battle: no rewards", D§9) |
| Vehicle card | (1216, 72, 640, 300) | one `ViewportFrame` with the player's vehicle model (LOD1) in its cosmetics over the darkened map art (B§9) |
| Tabs | (144, 308, 1752, 48) | five tabs, shoulder glyphs |
| Tab body | (144, 372, 1752, 580) | per tab below |
| CTA row | (1400, 968, 496, 56) | `GARAGE` (secondary) · `TO BATTLE` (primary, same vehicle and mode, D§14 "battle again" on every tab) |

| Tab | Content | Data |
|---|---|---|
| **SUMMARY** | five stat tiles 200 × 140 (`num.l`): damage, assist (spotting + tracking + stun), blocked, spotted, destroyed; four reward tiles 280 × 140: vehicle XP (with ×2), net Credits (sign + colour + icon), Free XP, Crew XP; Role Score bar (D§7.2; 1.0 = class × tier median, marker at the value); honours earned (badges 64 + names, §5.3); team XP rank; pass points | `summary.stats`, `rewards.xp`, `rewards.credits.net`, `summary.medals`, `stats.roleScore`, `stats.teamXpRank`, `rewards.passPoints` |
| **PERSONAL** | own detail table (shots fired / hits / penetrations / criticals, damage received / blocked / ricochets / non-pens, capture and defense points, distance, time alive, cause of destruction) + **per-enemy exchanges** table: enemy (class glyph, vehicle, player), shots at · hits · pens · crits · damage dealt · spotted · destroyed | `summary.stats`, `interactions[]` |
| **TEAM** | two sortable tables (allies, enemies), rows 40 px: platoon pip, name (`BOT` chip), vehicle (tier + class glyph), damage, assist, blocked, destroyed, spotted, XP, Role Score, honours count, survived glyph; own row highlighted; default sort XP desc; row → **player card** | `roster[]` (`ResultRow`) |
| **REPORT** | ledger in three groups — Credits, XP, Other — rendering `rewards.lines` **verbatim** in their given order (D§14, A§7): label from `LedgerLineKey` copy table, `detail`, multiplier chip (`×2`), signed amount with currency icon; group totals; **net Credits** row; negative net in `state.danger` with a `WHY?` button (modal explaining repair and ammo costs at Tiers IX–XI, the auto-repair floor `DebtWaived`, and "play a lower tier to earn Credits") | `rewards.lines`, `rewards.credits` |
| **PROGRESS** | before → after bars with deltas: daily / weekly / campaign missions touched (completions get a CLAIM shortcut), pass points and stage, research progress to the next module or vehicle (`4,200 / 9,800 XP · RESEARCH ›`), crew perk training per member, barrel band progress (`marksProgress`), mastery reached, achievements earned | `RewardApplied` deltas (Hub-computed), `PV` |

**Player card** (modal 640): name, `BOT` chip or platoon, vehicle art + name + tier, their row stats, honours, the
player's own exchanges with them (from `interactions`), actions for humans in the same Hub server only: `INVITE TO
PLATOON`, `ADD FRIEND` (Roblox prompt), `BLOCK`.

**Older battles.** `SS.resultsCache` holds full `ResultsView`s (inbox entry: summary, rewards, roster, interactions)
for this session. Entries from `PV.battleHistory` (earlier sessions) open with SUMMARY and a REPORT of totals only;
the other tabs show "Team details are kept for battles from this session."

**Motion and sound:** SUMMARY tiles count up in sequence (60 ms stagger, 600 ms each, `countUp`), reward tiles last
with a 400 ms dusk shimmer; honours pop with `ui_achievement_unlocked`; music `RESULTS_WIN / LOSE / EVEN` (AU§11).
Reduced motion: final values immediately. **Controller:** `[LB]/[RB]` tabs, `[Y]` TO BATTLE, `[B]` Garage, `[X]` player
card on a focused row, `[LT]/[RT]` page tables. Initial focus: `TO BATTLE`.
**Compact:** header 120 px (no vehicle card), tiles in a 2 × 3 grid, tables show name / damage / XP with row expand.
**Acceptance:** every currency and XP number shown equals the ledger (lines sum to totals, REG-RES goldens); nothing
is recomputed client-side; enemy identities appear (the battle is over); TO BATTLE works from every tab and re-queues
within 200 ms.

### S39 Mobile battle layout (Compact HUD, 844 × 390)

```
┌[≡][💬] core row ────────── H-01 ▮7 ▬▬ 11:42 ▬▬ 5▮ ───────────────────────────────────────────────┐
│┌MINIMAP 160┐ [COMMS]   H-09 ♥ 1,240 ▬▬▬▬ ⚙! ◉!      [^]spotted                     [✚] 4      │
││           │ [SCORE]   H-12 kill feed (3) / target card                            [✚] 5      │
││           │ [MENU ]                                                                [⛑] 6      │
│└───────────┘                              ◜ ⊙ ◝  7.4                  [+] (SNIPER)  [3]          │
│                                                                       [−]       [2]            │
│                          ribbons                                 [MECH]     [1]   ( FIRE )     │
│      ( ○ ) stick ghost                                                             (  104 )    │
│                    captions                                                                    │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
  left 40 %: dynamic movement stick          right 60 %: aim drag zone (outside buttons)
```

| Element | Rect (x, y, w, h) at 844 × 390, full-screen reference | Notes |
|---|---|---|
| Movement stick | dynamic in x 0–338 below y 230 (and anywhere in x 0–338 not covered by buttons) | base Ø 128 (spawns under the thumb), knob Ø 56, idle ghost centred (120, 290); `touch.stickMode` Fixed pins it there; feeds `Drive` via `InputBinding:Fire()` (D§16) |
| Aim zone | x 338–844 minus buttons | drag = aim (`touch.sens`, × zoom factor); tap a visible enemy marker = target lock toggle |
| Fire | (716, 262, 104, 104) | D§16: 104 px, 24 px from safe edges; reload progress ring 4 px around it; hold = dual-gun volley / charged shot charge |
| Ammo ×3 | centres (644, 303), (666, 243), (716, 202), Ø 56 | arc left of Fire (r 124 from its centre); tap = select next shell; long-press 0.5 s = swap now (full reload); count badge |
| Sniper | (563, 160, 72, 72) | toggles sniper; shows the zoom (`×4`) |
| Zoom − / + | (499, 204, 48, 48) / (499, 148, 48, 48) | sniper view only; pinch in the aim zone also zooms |
| Mechanic | (491, 268, 56, 56) | only when the vehicle has one |
| Consumables ×3 | (764, 52, 56, 56), (764, 116, 56, 56), (764, 180, 56, 56) | right edge (D§16); cooldown sweep; highlight rules of H-10 |
| Minimap | (12, 52, 160, 160) | D§16; tap = big map (60 % of the screen, centred) with tap-to-ping |
| Comms | (184, 52, 56, 56) | tap = context ping; hold 250 ms = radial (Ø 300 around the thumb) |
| Field menu | (184, 172, 48, 48) | opens §S36 |
| Scoreboard | (184, 116, 48, 48) | toggle |
| Score bar | (272, 4, 300, 40) | non-interactive, in the device-safe top band |
| Damage panel | (272, 48, 300, 44) | HP `num.m` + bar 160 + up to 6 chips (24 px) for non-OK modules / crew / fire / stun only |
| Kill feed | (272, 96, 300, 66) | 3 lines × 22 |
| Spotted alert | (580, 52, 48, 48) | right of the damage panel on Compact (top-centre is taken) |
| Reticle | centre (422, 195) | the target card (272, 96, 300, 32) replaces the kill feed while a target is under the reticle |
| Ribbons | (272, 236, 200, 2 × 28) | max 2 |
| Captions | (200, 334, 400, 40) | non-interactive |

Hidden on Compact: team panels (scoreboard instead), damage log (2 latest lines appear for 4 s under the damage panel
instead), chat (opened from the Field menu), efficiency strip (in the scoreboard). Touch targets: every battle control
≥ 48 rendered px at the 0.92 floor scale (authored ≥ 52); 8 px minimum gaps (REG-INP-04 checks overlap and safe area at
667 × 375, 844 × 390, 932 × 430). Multi-touch: stick, aim and one button may be held at once (fire while steering and
aiming). Optional layout editor (`touch.layout`, P2) lets players drag Fire, Sniper, ammo and consumables within
snapping zones; positions are validated against overlap before saving.

**Tablets** (Regular layout, touch input): the Regular HUD with touch controls scaled × 1.15 and positioned with the
same anchors (Fire bottom-right 24 px from the edges, consumables on the right edge); team panels Compact.

### S40 Battle input maps (console controller and keyboard / mouse)

**Gamepad** (`Battle` context; HUD is not navigable, menus use the §1.12 map):

| Button | Tap / press | Hold |
|---|---|---|
| Left stick | Drive (deadzone `pad.deadzoneL`) | – |
| Right stick | Aim / look (response curve `pad.curve`) | – |
| `[R2]` | Fire (D§16) | Dual-gun volley / charged shot (release fires) |
| `[L2]` | Sniper view (hold by default, `pad.sniperMode`) | – |
| `[L1]` | Target lock on / off (D§16 "L1 lock") | Free look (turret holds its heading) |
| `[R1]` | Next shell to load (D§16); double-tap within 0.5 s = swap now (full reload, D§4) | Ammo radial (3 shells; release on a shell to queue it, `[A]` while open = swap now) |
| `[Y]` | Context ping (§S33) | Command radial (D§16 "Y radial") |
| `[X]` | Smart consumable: extinguisher if burning → repair kit if a module is destroyed → medkit if crew injured or stunned → repair kit if damaged | Consumable radial (slots 4–6 + event abilities) |
| `[B]` | Vehicle mechanic (< 250 ms, on release) | Field menu (0.6 s) |
| `[A]` | – | Info overlay: names and HP numbers on markers (`ctl.info` toggle option) |
| `[D↑]` / `[D↓]` | Sniper: zoom in / out · Arcade: minimap size up / down | – |
| `[D←]` | Big map toggle | – |
| `[D→]` | Team panel mode cycle | Scoreboard (fallback if `[View]` is captured by the engine, §5.5) |
| `[L3]` | Cruise control cycle: off → ½ → full (client throttle hold; any stick input cancels) | – |
| `[R3]` | Arcade: camera distance cycle near / mid / far · Sniper: next zoom step | – |
| `[View]` | Scoreboard (hold, D§16) | – |
| `[Start]` | Roblox menu (reserved) | – |

Console HUD: TV layout (× 1.25, 5 % safe margin), chat hidden, damage log 4 lines, hint glyphs shown in radial
menus and on H-10 slots (`[X]` glyph on the smart-consumable target slot). Haptics per §3.3, scaled by `pad.haptics`.

**Keyboard and mouse** (`ctl.bind` defaults, all remappable except reserved keys):

| Key | Action | Key | Action |
|---|---|---|---|
| `[W][A][S][D]` | Drive | Mouse | Aim |
| `[LMB]` | Fire (hold = volley / charge) | `[RMB]` | Tap: target lock · Hold: free look |
| `[Shift]` | Sniper view (toggle; `ctl.sniperMode`) | `[Wheel]` | Zoom; past min / max switches view |
| `[1]`–`[3]` | Shells (press twice = swap now) | `[4]`–`[6]` | Consumables |
| `[7]`–`[8]` | Event abilities | `[X]` | Vehicle mechanic |
| `[C]` hold | Command radial | `[T]` | Context ping |
| `[Tab]` | Hold: scoreboard · Tap: team panel mode | `[M]` | Big map |
| `[Alt]` hold | Info overlay | `[-]` / `[=]` | Minimap size |
| `[Enter]` | Chat (engine chat bar; `/` also works) | `[R]` | Cruise control cycle |
| `[Bksp]` | Field menu | `[Q]` / `[E]` | Spectate: previous / next ally |
| `[F]` | Smart consumable (same rule as pad `[X]`) | `[V]` | Camera distance cycle |

Never bound: Esc, F9, F10 (Roblox graphics hotkey), F11, F12, PrintScreen (D§16).

**HUD acceptance (S31–S40).**
1. With 30 vehicles and 120 shells in flight the HUD's Luau time stays within §1.17 (mobile ≤ 1.5 ms, PC ≤ 0.8 ms)
   and allocates no tables per frame (HUD client harness).
2. No HUD element ever shows an enemy's identity, HP or position that the server did not send to that client; kill feed
   and damage log use "Unseen" for invisible attackers (REG-SPT-08, invariant 4).
3. Penetration indicator equals the shared `Penetration` result for 10,000 random aimed faces (same code path).
4. A `PreferredInput` change swaps the HUD layout and glyphs within one frame (REG-INP-02).
5. Touch controls do not overlap each other or the minimap and stay inside `CoreUISafeInsets` at every R-UI-1 phone
   size (REG-INP-04); battle targets ≥ 48 rendered px.
6. Flashing elements (fire icon, timer pulse, low-HP breathing) never exceed 3 flashes per second (D§16).
7. Every gameplay-critical cue has a visible twin (H-14, H-16, H-18, H-02, H-13, H-21), testable with audio muted.

---

## 3. Motion and feedback language

### 3.1 Principles and tokens

Calm, mechanical, readable (B§8.1): **120–200 ms ease-out for UI, nothing bounces, one 400 ms flourish for rewards.**
Exits are faster than entrances. Motion distances are short (16–24 px). Camera moves may take 450 ms; count-ups
600 ms; the GO sweep 400 ms. Stagger at most 30 ms per item and 8 items (60 ms for the Debrief tiles).

| Token (`Tokens.motion`) | s | Use | Easing (`Tokens.easings`) | Use |
|---|---|---|---|---|
| `instant` | 0 | state snaps | `standard` Quad Out | hovers, colour, generic |
| `hover` | 0.08 | hover fill / border | `enter` Cubic Out | screens, drawers, toasts in |
| `fast` | 0.12 | exits, tab underline | `exit` Quad In | screens, toasts out |
| `base` | 0.15 | modals, tooltips | `linear` | progress, sweeps, timers |
| `slow` | 0.2 | screen enter, drawers | `emphasized` Quart Out | camera, hero numbers |
| `toast` | 0.16 | toast slide | | |
| `flourish` | 0.4 | reward shimmer, GO sweep | | |
| `countUp` | 0.6 | number count-ups | | |
| `tooltipDelay` | 0.4 · `longPress` 0.5 · `toastHold` 4 · `toastHoldAction` 8 · `focusPulse` 0.9 | | | |

### 3.2 Transition catalogue

| Transition | Motion | Duration / easing | Sound | Reduced motion |
|---|---|---|---|---|
| Section switch (rail) | cross-fade | 200 in `enter` / 120 out `exit` | `ui_tab_switch` | fade 100 |
| Drill-in push / pop | slide 24 px + fade | 200 `enter` / 120 `exit` | `ui_open_panel` / `ui_back` | fade 100 |
| Drawer open / close | slide from edge (full width of the drawer) + 40 % scrim on Compact | 200 `enter` / 150 `exit` | `ui_open_panel` / `ui_close_panel` | fade 100 |
| Modal | scale 0.98 → 1 + fade, scrim 0 → 80 % | 150 `standard` | `ui_open_panel` | fade 100 |
| Toast | slide 24 px from the right + fade | 160 `enter`, out 120 fade | `ui_notification` | fade 100 |
| Tooltip | fade + 4 px offset | 120 after the delay | none | fade |
| Tab switch | underline slides to the new tab, content cross-fades | 120 | `ui_tab_switch` | instant underline |
| Carousel page | scroll animation | 250 `standard` | `ui_tab_switch` | instant |
| Hangar camera preset | camera tween | 450 `emphasized` | none | cut |
| Selected vehicle swap | old model fades 120, new model fades in 200 after load | – | `ui_click` | same |
| Currency change | count-up + 400 ms currency-colour flash on the label | 600 | `ui_purchase` when caused by a purchase | final value + flash only |
| Badge appears | scale 0.6 → 1 | 150 `enter` | none | fade |
| Focus ring move | instant reposition, brackets pulse | `focusPulse` loop | `ui_hover` | static |

### 3.3 Event → feedback matrix

**Garage**

| Event | Visual | Sound | Haptic (pad / touch) |
|---|---|---|---|
| Button press | 1 px press offset, fill `accent.dusk_lo` (primary) | `ui_click` | – |
| Request pending | progress sweep in the button, `-ING` label | – | – |
| Purchase complete | reward toast + count-up + item tile flashes verdant edge 400 ms | `ui_purchase` | light / light |
| Research complete | node fills, dusk edge sweep along the new edges 400 ms | `ui_research_complete` | light |
| Vehicle bought | node and carousel card shimmer; toast with `SELECT` | `ui_vehicle_unlocked` | medium |
| Mount / apply | slot flashes verdant edge 200 ms | `ui_confirm` | – |
| Mission claimed / completed | card tick draws 200 ms + reward toast | `ui_mission_complete` | light |
| Perk slot ready / pass stage / rank up | badge pop + toast | `ui_level_up` | light |
| Achievement | toast with the badge art, 400 ms shimmer | `ui_achievement_unlocked` | light |
| Error | 2 px `state.danger` border flash 200 ms (no shake) + message | `ui_error` | – |
| Queue join / leave | button morph (label cross-fade 120) | `ui_confirm` / `ui_back` | – |
| Battle found | `BATTLE FOUND` + hangar lights dim 30 % over 1 s | `ui_battle_found`, `hangar_pa_chime` | medium |

**Battle** (scaled by `fx.shake`, `fx.flash`, `pad.haptics`; "RE" = reduced effects alternative)

| Event | Visual | Sound | Haptic | RE |
|---|---|---|---|---|
| Own shot fired | muzzle flash, recoil kick (pitch 0.3–0.8° by calibre, 250 ms recovery), dispersion bloom | gun family (AU§6.3) | Large motor 0.4 / 80 ms | no kick |
| Reload complete | reload arc completes, white 80 ms flash on the arc | `cue_reload_complete` | Small 0.2 / 40 ms | – |
| Own shot penetrates | `PENETRATED` callout + damage number + marker chunk flash | `armor_penetration` (2D, prio 95) | Small 0.3 / 60 ms | – |
| Own shot crit | `CRITICAL · ENGINE` amber + module glyph | `armor_critical` | – | – |
| Own shot blocked / ricochet | `BLOCKED` / `RICOCHET` callout | `armor_blocked` / `armor_ricochet` | – | – |
| Enemy destroyed by you | `DESTROYED` callout 1.2 s + kill-feed highlight + `DESTROYED` ribbon | `cue_enemy_destroyed` +3 dB | Small 0.3 × 2 pulses | – |
| Hit taken, penetrated | HP chunk white 80 ms → drain 300 ms, hit arc, 120 ms `state.danger` edge flash ≤ 20 %, camera shake 0.6° / 200 ms | `armor_hit_taken_pen` | Large 0.8 / 150 ms | no flash, no shake |
| Hit taken, blocked / ricochet | white hollow hit arc, damage log line | `armor_hit_taken_blocked` / `_ricochet` | Small 0.5 / 80 ms | – |
| Module damaged / destroyed | glyph pops to amber / signal, scale 1.15 → 1 | `dmg_module_damaged`, `dmg_engine_damaged`, `dmg_track_broken` | Small 0.4 / 100 ms | no scale |
| Crew injured | crew glyph to injured state + caption | `dmg_crew_injured` | – | – |
| Fire start / out | fire glyph flashing 2 Hz + extinguisher slot outline / glyph clears | `dmg_fire_ignition` → `dmg_fire_loop` / `dmg_fire_extinguished` | Large 0.3 / 300 ms | glyph steady |
| Spotted | crest chevron + ripples 2 s | `cue_sixth_sense` | Small 0.3 × 2 | no ripples |
| Enemy newly spotted by team | minimap glyph appears with a 300 ms ring | `cue_enemy_spotted` | – | no ring |
| Ally destroyed | kill feed row, panel row greys | `cue_ally_destroyed` | – | – |
| Capture on own base | H-02 bar + minimap base flash 1 Hz | `cue_capture_warning_loop` | – | flash → steady outline |
| Base captured | end banner | `cue_capture_complete` | medium | – |
| Low HP < 25 % / < 15 % | vignette / breathing vignette | `cue_low_hp_alarm` / `cue_low_hp_heartbeat_loop` | Small 0.2 at 75 bpm (< 15 %) | static vignette 20 %, no haptic loop |
| Timer < 2:00 / < 0:30 | warning colour / danger + pulse | – | – | no pulse |
| Battle end | §S37 band | music `ENDGAME_*` → `RESULTS_*` | medium | fade |

### 3.4 Damage numbers and hit callouts

* **Dealt damage only** (the player's own shots, splash, fire they started, rams they caused); allies' damage shows
  only as marker HP drain. Received damage never floats (damage panel, log and hit arcs carry it).
* **Floating style** (`fx.damageNumbers = Floating`): Oswald SemiBold `num.m` 22 (`num.l` 32 when the hit removed
  ≥ 30 % of the target's max HP), `text.primary` with a 1.5 px ink `UIStroke` outline (never used as fake bold, B§4),
  prefixed with a typographic minus (`−358`). Spawns at the top of the target marker's HP bar, rises 28 px over 700 ms
  (`standard`), fades over the last 250 ms; consecutive numbers on one target stack 20 px upward. A critical prefixes
  the 16 px amber module glyph; a kill shows the number in `state.danger` with the `hit_kill` glyph. Fire damage the
  player caused aggregates every 1 s as `−40` with the 16 px flame glyph.
* **No number** for zero-damage results: the result word appears instead in its B§10.2 colour (`BLOCKED`
  `#C9D1D8`, `RICOCHET` `#E6F4FF`, `ABSORBED` `#7FA7C9`), 18 px `label`, 500 ms.
* **On marker** mode: the number appears inside the marker plate right of the HP bar for 1.2 s without motion.
* Reduced motion: numbers fade in place (no rise).

### 3.5 Reduced motion and reduced effects mapping

| Feature | Reduced motion (`a11y.reducedMotion` / `ReducedMotionEnabled`) | Reduced effects (`a11y.reducedEffects`) |
|---|---|---|
| Screen / drawer / toast slides | fades ≤ 100 ms | – |
| Count-ups | final value at once | – |
| Pulses, ripples, breathing | off (static glyphs carry meaning) | off |
| Camera preset tweens, dolly | cuts | – |
| Camera shake, recoil kick | – | off |
| Full-screen / edge flashes | – | off |
| Low-HP vignette | static | capped 20 % |
| Particles on own vehicle | – | −50 % |
| Haptic loops | – | off (single pulses keep) |
| Focus bracket animation | static | – |

---

## 4. Screen inventory for implementation

### 4.1 Screens

Paths are under `src/ReplicatedStorage/Client/UI/Screens/` (A§10). "Router" = registration kind (§1.3). Owning data
= the stores and remotes the screen reads and writes. P0 = first playable slice, P1 = launch, P2 = post-launch.

| Id | Screen | Module path | Router | Owning data | Priority |
|---|---|---|---|---|---|
| S01 | Boot and profile load | `ReplicatedFirst/Loading` (not under Screens) | Loading layer | Hello / `DataSync` status, preload list | P0 |
| S02 | First launch | `Screens/FirstLaunch` | modal sequence | `PV.account.flags`, `ST.a11y.*`; `AckFlag` | P1 |
| S03 | Main menu | `Screens/MainMenu` | root (pre-Garage) | `PV.activeBattle`, `ST.ui.titleScreen`; `ReturnToBattle` | P1 |
| S04 | Garage hub | `Screens/Garage` | root, keepAlive | `SS.selectedVehicleId`, `PV.vehicles/crews/currencies/missions/pass`, `SS.queue/platoon` | P0 |
| S05 | Carousel | `Screens/Carousel` | component of Garage | `PV.vehicles`, `CR`, `ST.garage.*` | P0 |
| S05b | Motor Pool | `Screens/Carousel/MotorPool` | drill-in | same | P1 |
| S06 | Battle launcher (mode, queue, platoon strip) | `Screens/Garage/Launcher` | component | `SS.queue`, `SS.platoon`, `PV.matchmaking`, `PV.moderation`; `QueueJoin/Leave/StartWithBots`, `SetMatchmakingPrefs` | P0 |
| S07 | Drawer frame | `Screens/Garage/Drawer` | component | – | P0 |
| S08 | Vehicle Inspect | `Screens/VehicleInspect` | drill-in | `CR`, `StatsCalculator`, Blueprint | P1 |
| S09 | Research | `Screens/Research` | drill-in | `ResearchGraph(PV)`; `ResearchModule`, `MountModule`, `ResearchVehicle`, `SelectFieldKit`, `ResearchApexNode`, `ConvertXP` | P0 |
| S10 | Tech Tree | `Screens/TechTree` | section, keepAlive | `CR TechTree`, `ResearchGraph(PV)`; `ResearchVehicle`, `BuyVehicle` | P0 |
| S11 | Compare | `Screens/Compare` | drill-in | `SS.compareList`, `StatsCalculator` | P1 |
| S12 | Armor Inspector | `Screens/ArmorInspector` | drill-in | `ArmorGeometry`, `Penetration`, Blueprint | P1 |
| S13 | Crew | `Screens/Crew` | section / drill-in | `PV.crews`, `PV.inventory.crewBooks`; `LearnPerk`, `ResetPerks`, `RetrainCrew`, `UseCrewBook`, `AssignCrew`, `RecruitCrew` | P0 |
| S14 | Equipment | `Screens/Equipment` | drawer | `PV.vehicles[id].equipment`, `PV.inventory.equipment`; `SetEquipment`, `BuyEquipment`, `DemountEquipment` | P1 |
| S15 | Ammunition | `Screens/Ammo` | drawer | `PV.vehicles[id].ammo`, `PV.inventory.shells`; `SetAmmo`, `SetAutoResupply` | P0 |
| S16 | Consumables | `Screens/Consumables` | drawer | `PV.vehicles[id].consumables`; `SetConsumables` | P1 |
| S17 | Exterior | `Screens/Exterior` | drill-in | `PV.vehicles[id].customization`, `PV.inventory.customization`; `BuyCustomization`, `ApplyCustomization` | P2 (paint + camo P1) |
| S18 | Missions and Pass | `Screens/Missions` (+ `Screens/Missions/Pass`) | section | `PV.missions`, `PV.pass`, `CR` missions / season; `ClaimMission`, `RerollDaily`, `ClaimPassStage`, `BuyPassPaid` | P1 (daily P0) |
| S19 | Achievements | `Screens/Achievements` | tab / drill-in | `PV.achievements`, `ST.seen` | P1 |
| S20 | Store | `Screens/Store` | section, keepAlive | `CR Store`, `SS.policy`, product info cache; `BuyStoreItem`, `BuyPremiumTime`, Marketplace prompts, `PurchaseGranted` | P1 |
| S21 | Profile | `Screens/Profile` | section | `PV.stats`, `PV.battleHistory`, `PV.vehicles[*].stats`, `PV.account` | P1 |
| S22 | Settings | `Screens/Settings` | section, keepAlive | `ST` (§S22 keys); `SettingsSet` | P0 (audio, controls, a11y scheme), P1 rest |
| S23 | Platoon | `Screens/Platoon` | modal | `SS.platoon`; `PlatoonInvite/Respond/Leave/Kick/Promote/Ready` | P1 |
| S24 | Social | `Screens/Social` | drill-in | `SS.friends`, `PV.social`; `JoinFriend` | P2 (friends list P1) |
| S25 | Notification center | `Screens/Notifications` | drill-in / panel | `SS.notifications`, `ST.seen` | P1 |
| S26 | Game menu | `Screens/GameMenu` | modal | – | P0 |
| S27 | Tutorial and Proving Field overlays | `Screens/Tutorial` | Tooltip layer + battle overlay | `PV.account.flags`, `ST.tut.hints`; `SetTutorialStep`, `AckFlag` | P1 |
| S28 | Deploying / returning | `Screens/Deploying` | overlay + teleport GUI | `SS.queue`, `MatchFound`, `TeleportStatus` | P0 |
| S29 | Battle loading | `Screens/BattleLoading` | Battle place, Loading layer | `BV.roster`, map content, load phase | P0 |
| S30 | Pre-battle countdown | `Screens/Countdown` | HUD overlay | `BV.phase`, `BV.countdownEndsAt` | P0 |
| S31 | Battle HUD | `Screens/BattleHUD/*` (`ScoreBar`, `TeamPanels`, `Minimap`, `Reticle`, `TargetCard`, `Markers`, `DamagePanel`, `AmmoBar`, `DamageLog`, `KillFeed`, `HitDirection`, `Alerts`, `Ribbons`, `Callouts`, `StatusBanner`, `Captions`, `SoundViz`) | HUD layer | `BV.*` | P0 (score, reticle, pen, damage panel, ammo bar, minimap, markers); P1 rest |
| S32 | Sniper and artillery overlays | `Screens/BattleHUD/Sniper` | HUD | `BV.own.sniper/zoom`, `BV.aim` | P0 sniper, P1 artillery |
| S33 | Radial command menu | `Screens/RadialMenu` | HUD overlay | `CommandSend`, rate state | P1 |
| S34 | Scoreboard and big map | `Screens/BattleHUD/Scoreboard`, `Screens/BattleHUD/BigMap` | HUD overlay | `BV.roster`, `BV.teams`, `BV.minimap` | P1 |
| S35 | Destroyed / spectate | `Screens/BattleHUD/Spectate` | HUD | `BV.own.alive`, allies; `SpectateTarget`, `LeaveBattle` | P1 |
| S36 | Field menu | `Screens/BattleHUD/FieldMenu` | modal (`Menu` context) | `ST` subset; `LeaveBattle` | P0 |
| S37 | Battle end banner | `Screens/BattleHUD/EndBanner` | HUD | `BV.phase`, outcome event | P0 |
| S38 | Debrief / Results | `Screens/Results/*` (`Summary`, `Personal`, `Team`, `Report`, `Progress`, `PlayerCard`) | overlay over Garage | `SS.resultsCache`, `GetResult`, `ResultsReady`, `RewardApplied` | P0 (Summary + Report), P1 rest |
| S39 | Mobile battle layout | `Screens/BattleHUD/Touch` | `HUDInput` | `BV.*`, `ST.touch.*` | P0 |
| S40 | Battle input maps | `Client/Controllers/Input` bindings (+ `Screens/BattleHUD/Radials`) | – | `ST.ctl.bind`, `ST.pad.bind` | P0 |

`VehicleInspect`, `Social`, `GameMenu`, `Deploying`, `FirstLaunch`, `Carousel/MotorPool` and the BattleHUD
sub-screens extend the A§10 screen list; the ARCHITECTURE owner should add them in the same change as the code.

### 4.2 Kit components to build (beyond `Chamfer`, `FocusRing`)

| Component | Used by | Notes |
|---|---|---|
| `Button` (primary / secondary / tertiary / destructive / premium; pending state) · `IconButton` · `HoldButton` | all | B§8.3 sizes 56 / 44 / 36; hold-to-confirm ring |
| `TabBar` (shoulder glyphs) · `Segmented` · `Chip` / `ChipFilter` | all | B§8.4 |
| `Panel` · `Drawer` · `Modal` · `Sheet` · `Scrim` / `Spotlight` | all | B§8.2, §1.6 |
| `Toast` · `SystemBanner` · `Badge` (tag / dot) · `NotificationRow` | §1.5 | |
| `Tooltip` (plain / stat / item / reason) | §1.7 | |
| `SkeletonBlock` · `ProgressBar` · `ProgressRing` · `CountUpLabel` · `CurrencyLabel` · `CurrencyCounter` | many | |
| `StatRow` · `DataTable` (sortable, virtual) · `LedgerTable` | Garage, Inspect, Compare, Results | |
| `VirtualList` / `VirtualGrid` (horizontal + vertical) | Carousel, Motor Pool, Crew reserve, Pass | pool = visible + 4 |
| `CanvasPanZoom` | Tech Tree, Research | input map §S10 |
| `VehicleCard` · `TechNode` · `ResearchNode` · `MissionCard` / `MissionRow` · `CrewCard` · `PerkTile` · `CosmeticCard` · `RosterRow` · `StoreTile` | screens | |
| `Slider` · `Stepper` · `Toggle` · `Dropdown` · `KeyBind` · `SearchField` · `SettingRow` | Settings, Ammo | |
| `HintBar` · `KeyGlyph` | §1.12 | glyph from `InputMode` |
| `CoachMark` | §S27 | |
| `RadialMenu` | §S33, ammo / consumable radials | |
| `MarkerOverlay` · `ReticleView` · `MinimapView` · `DamagePanel` · `AmmoBar` | HUD | no per-frame allocation |
| `ArmorProbe` | §S12 | |

---

## 5. Cross-team requests, IP flags and open questions

### 5.1 Art and brand (owner: Art Direction)

1. **Command icons** missing for decided presets: `battle/cmd_hold`, `battle/cmd_focus_fire`, `battle/cmd_moving`,
   `battle/cmd_thanks` (§S33). `cmd_capture`, `cmd_retreat`, `cmd_need_assistance` are unused by the decided preset list
   (D§9) and can stay as reserves.
2. **Mouse glyphs** for prompts: `ui/mouse_left`, `ui/mouse_right`, `ui/mouse_wheel`, `ui/mouse_move`.
3. **Vehicle side art** `assets/vehicles/<id>_side.png` (256 × 128, side profile gun right, B§6.3) rendered from the
   Blueprints for carousel, tech tree and store; fallback class glyph + tier.
4. **Minimap renders** per map (top-down, generated, hash-checked) and **map art** 1280 × 720 / 512 × 288 (B§9).
5. **Crew portrait set** (`CrewName.portrait` index) and **perk icon set** (all perks, flat symbols on the 64 grid).
6. **Armor ramp tokens** `armor.ramp.1…7` (proposal, luminance-monotonic, to validate with `check_palette.py`):
   `#3B2A63`, `#36508C`, `#2F7D9A`, `#2FA38A`, `#6CC067`, `#C9D44A`, `#F6E86A`; and stripe / cross-hatch overlay
   textures for VS SHELL mode.
7. **`pen.cb.*` approval** (D§21 #14): proposed `#3DDBD9` / `#FFD84D` / `#D62AD0`.
8. **Grade mapping:** decisions have Standard and Refined only; this spec maps Refined → `grade_improved` (silver
   brackets) and keeps `grade_experimental` unused. Confirm.
9. **Touch control art:** stick base / knob, Fire button plate, chamfered keycap 9-slice.

### 5.2 Audio (owner: Audio)

1. Radio keys for presets without a sound: `radio_cmd_affirmative`, `radio_cmd_negative`, `radio_cmd_reloading`,
   `radio_cmd_thanks`, `radio_cmd_hold`, `radio_cmd_moving`, `radio_cmd_focus` (interim `radio_static`).
2. AU§7's visual-twin table still says "sixth sense | lamp icon"; per D§21 #12 and B§8.8 it is the dusk crest chevron.

### 5.3 Content and IP (owner: Content + Brand)

Player-facing copy must not reuse another tank game's names. The decided internal values are fine as ids, but these
display names are required:

| Internal (D§14 / D§12) | Proposed display name |
|---|---|
| Top Gun (most kills ≥ 6) | **Ridge Breaker** |
| Steel Wall (most damage blocked) | **Unbroken Plate** |
| Defender (≥ 70 capture points reset) | **Gatekeeper** |
| Invader (≥ 80 points in a won capture) | **Line Crosser** |
| Scout (most detections ≥ 9) | **Far Sight** |
| Patrol Duty (sole spotter of ≥ 6) | **Lone Watch** |
| Confederate (≥ 6 hit, later destroyed by allies) | **Shoulder to Shoulder** |
| High Caliber (most damage, ≥ 20 % of enemy HP) | **Heavy Hand** |
| "Battle Heroes" group | **Field Honours** |
| Gun Marks / Mastery classes | **Barrel Bands** / Ace · First · Second · Third Class |
| Crew starters Recon · Practicality · Mentor | Long Watch · Field Economy · Field Tutor |
| Snap Shot · Deadeye · Quick Aiming | Quick Lay · Plate Reader · Steady Hand |
| Clutch Braking · Smooth Ride · Engineer | Pivot Hand · Level Ride · Engine Tuner |
| Intuition · Close Combat · Ammo Tuck | Quick Swap · Breach Drill · Rack Guard |
| Brothers in Arms · Concealment (group) | Tight Crew · Low Profile |
| Sixth Sense | "Spotted alert" (no perk name) |
| Random Battle / Encounter / Assault / Boot Camp / About Vehicle / My Vehicles / Playlists | Open Trials / Crossroads / Breach / Proving Field / Inspect / Motor Pool / Lineups (§0.3) |

### 5.4 Engineering and data (owners named)

1. **Shared:** add `Penetration.requiredPen(path, shell)` and `Penetration.chance(meanPenMm, requiredPenMm)`
   (truncated-normal CDF of the D§1 roll) with Lune specs; used by §S12, H-06 and tests (Combat).
2. **Content / renderer:** `CustomizationKind` already has `Decal`, `Attachment` and `Effect` (`Types/Content`). The
   Exterior preview needs the client renderer to place decals and attachments at the slot hotspots (§S17)
   (Render).
3. **Kit:** add the `TopBar` layer (`TopbarSafeInsets`, DisplayOrder 25) with the fallback in §1.1 (UI kit).
4. **Net:** register the §0.6 remotes in `RemoteDefs/*` with the stated rate limits; `RewardApplied` must carry the
   mission / pass / research deltas the PROGRESS tab shows (Progression, Matchmaking, Social, Battle).
5. **BattleView contract** (§0.5) including enemy team HP for the score bar and the visibility flag on received damage
   events (so the log can print "unseen") (Battle client).
6. **QA docs:** REG-UIX-01 asks for 48 px targets on Compact; D§21 #16 decides 44 px for menus and 48 px for battle.
   This spec follows the decision; update REG-UIX-01's wording (QA).
7. **ARCHITECTURE §10** screen list additions (§4.1) (Architecture owner).

### 5.5 In-engine verification items (add to D§22)

1. `ScreenInsets.TopbarSafeInsets` row height on PC, console and phones; whether our top bar fits beside the core
   buttons, else the §1.1 fallback.
2. `ChatWindowConfiguration` alignment and scale reaching the H-19 slot; console chat disabled.
3. `[View]` (`ButtonSelect`) reaching our Scoreboard action with `AutoSelectGuiEnabled = false` (fallback `[D→]` hold).
4. `GetImageForKeyCode` art for PlayStation and Xbox for every bound button; keycap fallback text otherwise.
5. `SetTeleportGui` / `GetArrivingTeleportGui` continuity for reserved-server teleports both ways.
6. `Texture` stripe overlays on armor primitives readable at 1080p and on phones.
7. Robux price glyph rendering in Builder Sans; `GetProductInfoAsync` latency and caching.
8. `HapticService` motor support per controller; touch haptics availability.
9. Landscape lock (`LandscapeSensor`) on phones in Hub and Battle.

### 5.6 Open questions

1. Should enemy damage numbers in the scoreboard stay hidden mid-battle (current **O**) or show for allies only?
2. Cruise control (`[L3]` / `[R]`) is input-only; confirm with the Vehicle team that VehicleSim needs no change.
3. Public profiles of other players (P2) need a server read path for non-session profiles; out of scope for v1.
4. Lineup share codes are typed or selected manually (no clipboard API on Roblox); confirm acceptable for console
   (where text entry is awkward, import is hidden on console in v1).
