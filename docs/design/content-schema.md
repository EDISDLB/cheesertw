# HULLDOWN content schema — authoring guide

Status: v1 (schema frozen for Phase B–E; additive changes only, through the Lead Systems Designer).
Owner: Lead Systems Designer / data architecture.
Source of truth for types: `src/ReplicatedStorage/Shared/Types/Content.luau` (authored data),
`Types/Vehicle.luau` (resolved stats, loadout, input, armor model), `Types/Battle.luau` (battle ledger),
`Types/Profile.luau` (player save v1). This guide explains them; if the two ever disagree the type file wins and this
guide is the bug.

Related: `docs/research/00-DECISIONS.md` (numbers and rules), `docs/design/roster.md` (vehicle ids, names, roles,
branches, builder presets), `docs/design/brand-art.md` (icons, colours), `docs/design/audio.md` (sound keys),
`docs/ARCHITECTURE.md` §9 (content pipeline).

---

## 0. Map of the files

| Path | What it holds |
|---|---|
| `Shared/Types/Content.luau` | Every authored kind (23 `ContentKind`s), enums, value types, authoring aliases |
| `Shared/Types/Vehicle.luau` | `VehicleStats` (resolved per battle), `Loadout`, `InputCommand`, `ArmorModel` + `VehiclePivots` (studs) |
| `Shared/Types/Battle.luau` | Battle events, `DamageEvent`, `BattleStats`, reward ledger, `BattleResult` / `BattleSummary` |
| `Shared/Types/Profile.luau` | `Profile` v1, `SCHEMA_VERSION`, ring `LIMITS` |
| `Shared/Config/ContentRegistry.luau` | Index, getters, derived views, `validate()`, `contentHash()`, ordinals |
| `Shared/Config/Content/init.luau` | The manifest: explicit registration lists (no instance scanning) |
| `Shared/Config/Content/*.luau` | One file per kind (`Factions`, `Classes`, `Roles`, `Tiers`, `TechTree`, `Equipment`, …) |
| `Shared/Config/Content/{Shells,Guns,Turrets,Engines,Tracks}/<Faction>.luau` | Shared modules, one file per faction |
| `Shared/Config/Content/Vehicles/<Faction>/<Vehicle>.luau` | One vehicle per file (`IronUnion/IuKolmal.luau`) |
| `Shared/Config/Content/Maps/<Map>.luau` | One map per file |
| `tests/Unit/.../Config/ContentRegistry.spec.luau` | Shipped-content validation + one failing case per validator |
| `tests/Unit/.../Types/*.spec.luau` | Enum mirrors, example shapes, profile size budget |

Gameplay code never `require`s a content file. It asks the registry:

```lua
local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
local content = ContentRegistry.get()          -- shipped content, built + frozen on first call
local kolmal = content:getVehicle("iu_kolmal")
local gun = content:getModule("Gun", kolmal.top.gun)
```

---

## 1. Conventions

**Ids.** Lowercase snake_case, `^[a-z][a-z0-9_]*$`, at most 48 characters, unique per kind. Ids never encode a tier
(vehicles move tiers; ids must not). Module ids are unique **across** guns, turrets, engines and tracks because
research is global (`profile.researchedModules` is one set). Tiers are keyed by their number.

**Faction prefixes.** Every faction declares `idPrefix` (`iu`, `ci`, `ea`, `dc`, `mr`, `nf` — roster.md §0.2).
Vehicle ids and branch ids must start with `<idPrefix>_` (`iu_kolmal`, `iu_bulwark`); module and shell ids follow the
same habit (`iu_gun_45mm`, `iu_45mm_ap`) so a grep finds a faction's whole kit.

**Registry ids vs engine enums.** Things that are rows in a registry (factions, classes, roles, branches, every
authored definition) use snake_case ids that double as icon file names (`classes/heavy`, `roles/heavy_assault`).
Closed sets that code branches on are PascalCase literal unions (`"Commander"`, `"Magazine"`, `"Heavy"` lane,
`"HullUpperFront"`).

**Units are real-world** everywhere in content and in `VehicleStats`: armour mm, sizes and distances m, speeds km/h,
shell velocity m/s (in-game = 0.6 × real), angles degrees (depression and elevation are positive magnitudes), time s,
mass kg, power hp. Studs appear only in `Types/Vehicle` `ArmorModel`/`VehiclePivots` (3 studs per metre,
`Core/Units`). Map positions are metres in map space (`Vec2 {x, z}`: origin = map centre, +x east, +z south).

**Optional fields** (`?`) have a documented default (class, tier, `Config.Combat`, `Config.Spotting`). Write only
what differs from the default; the comment beside each field in `Types/Content.luau` names the default.

**Text** is English source text in sentence case (brand-art §2). Localisation keys derive from ids; never put
keys in text fields. `lore` is original fiction — no real-world units, conflicts, manufacturers or people.

**Authoring list aliases.** Luau's checker cannot infer a list of string literals or tagged tables through an
**optional** field. Those fields use an alias and you write a checked cast (a typo inside still fails `types`):

```lua
crew = {
	{ role = "Commander", also = { "Gunner", "Loader" } :: Content.CrewRoles },
	{ role = "Driver" },
},
mechanics = { { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 } } :: Content.Mechanics,
```

Aliases: `CrewRoles, Rewards, VehicleClasses, RoleIds, FactionIds, BattleModes, BattleTypes, Modifiers, Mechanics,
MechanicKinds, ReloadKinds, InternalVolumes, CrewSeats, FieldKit, EventModes, EventAbilities, MapRandomEvents`. Required lists
need no cast. Typical casts in new fields: `MapPosition.classes = { "td" } :: Content.VehicleClasses`,
`EventModeDefinition.battleTypes = { "Standard" } :: Content.BattleTypes`, ladder `rewards = {...} :: Content.Rewards`.
Maps keyed by an enum (`classCaps = { artillery = 0 }`, `effectsByClass = { td = {...} }`) need no cast.

**Unknown fields are errors, at every depth.** The old Luau solver does not flag extra keys in table literals, so the
registry does (`UNKNOWN_FIELD`): a misspelt optional field (`reverseKMH`, `bloom.movmentPerKmh`,
`mechanics[1].autoEngage`, `spawns.team1[3].reer`) fails validation instead of silently using the default. Every
nested table is checked against its known-field set (`ContentRegistry.FIELDS`, `MECHANIC_FIELDS` per mechanic kind);
`Types/Content.spec` fails if a set drifts from its type declaration, so add a field to the type and the set together.

**Local ids** (capture bases, lanes, positions, water bodies, variants, random events, event modes and abilities,
ladder ranks, pass chapters, Apex nodes, Field Kit options, exclusive groups, campaign ids) follow the same
snake_case rule as registry ids, because they travel in battle events, codecs and profile keys.

---

## 2. The registry

### 2.1 Building

| Call | Use |
|---|---|
| `ContentRegistry.get()` | Shipped content (lazy, memoised, deep-frozen). Runtime code uses only this. |
| `ContentRegistry.shippedBundle()` | A fresh, mutable deep copy of the shipped content as a flat `ContentBundle` (tests, tools). |
| `ContentRegistry.fromBundle(bundle)` | Registry over any bundle (test fixtures, balance tools). |
| `ContentRegistry.fromSources(sources)` / `.flatten(sources)` | Manifest shape → registry / bundle. |

Construction never throws on bad data: invalid ids, duplicates and missing required lists become issues
(`buildIssues()`), the first definition of a duplicated id wins, getters return `nil` for unknown ids.

### 2.2 Getters and views

Getters: `getFaction, getClass, getRole, getTier(n), getShell, getGun, getTurret, getEngine, getTracks,
getModule(kind, id)` (kind-checked), `getAnyModule(id)`, `getVehicle, getEquipment, getConsumable, getSkill,
getCrewBook, getBooster, getCustomization, getMission, getAchievement, getMap, getStoreItem, getEvent, getSeason,
getBranch`.

Views (all return frozen arrays in a stable order; `table.clone` one before sorting it another way — an in-place
`table.sort` on a view raises instead of silently reordering the shared registry):

| Call | Returns |
|---|---|
| `list(kind)` | Every definition of a kind in registration order |
| `allVehicles()`, `allMaps()` | Shortcuts |
| `vehiclesByFaction(f)`, `vehiclesByTier(t)`, `vehiclesByClass(c)` | Sorted by faction order, tier, tree row, id |
| `rolesByClass(c)` | In the class's `roles` order |
| `branchesByFaction(f)` | Branches in `TechTree.luau` order |
| `techTreeEdges(faction?)` | `{ from, to, requires, xp }` flattened from every vehicle's `unlocks` (`xp` = target `researchXp`) |
| `parentsOf(id)`, `childrenOf(id)` | Incoming / outgoing edges of one vehicle |
| `configurationMassKg(vehicleId, config)` | Hull + gun + turret + engine + tracks mass, or nil |
| `checkConfiguration(vehicleId, config)` | `Result<number>` (mass): every module belongs to the vehicle, the turret mounts the gun, mass ≤ tracks load limit. `NOT_FOUND` / `INVALID_ARGS` with a readable detail. Research and ownership are not checked (Transactions does that against `profile.researchedModules`). |
| `checkLoadout(loadout, { eventItems? })` | `Result<true>`: content legality of a whole `Loadout` (§8.1). The garage offers only legal loadouts, the Hub runs it before writing a loadout into the match manifest and the battle server runs it again on arrival. |
| `ordinal(kind, id)` / `idAt(kind, n)` | 1-based index over the sorted ids, for compact codecs. Only valid between two parties with the same `contentHash()` (adding an id shifts every later ordinal), so ordinals are never persisted |
| `contentHash()` | 16 hex chars over a canonical encoding of the whole bundle. Battle servers and lobbies compare it so a battle never mixes content versions; replays store it. |

`ContentRegistry.ENUMS` exposes the frozen enum sets the validator uses (UI filters, debug tools);
`ContentRegistry.FIELDS` / `MECHANIC_FIELDS` the known-field sets.

### 2.3 Validation

```lua
local result = content:validate({ iconKeys = iconCatalog, soundKeys = soundCatalog })
-- Ok({ errors = {}, warnings = {...} })  or  Err("INVALID_ARGS", { errors = {...}, warnings = {...} })
print(ContentRegistry.formatIssues(report))
```

- `validate()` reports **every** problem in one pass; each issue is `{ code, path, message, severity }` with a path
  such as `vehicles[3](iu_bulmal).modules.guns(iu_gun_76mm)` or `maps[1](proving_grounds).spawns.team2[4].at`.
- Errors fail the build (`ContentRegistry.spec` asserts zero errors **and** zero warnings for shipped content).
  Warnings flag legal-but-suspicious data (orphan modules, optional tracks upgrade, module tier far from vehicle
  tier); shipped content must silence them by fixing the data or, for balance, with `balanceException`.
- `iconKeys`/`soundKeys` are optional catalogues; when given, every `IconKey` / `SoundKey` must exist (`ASSET_KEY`).
  The asset pipeline test passes them; plain unit tests omit them. `achievementRules` (the evaluator keys
  `Shared/Progression/Achievements` implements) works the same way for `AchievementDefinition.rule` (`DANGLING_REF`).
- Issue codes and what they mean: §11.

---

## 3. Factions, classes, roles, tiers, branches

These are **locked sets** (`LOCKED_SET`): exactly the six factions, five classes, seventeen roles and eleven tiers
of 00-DECISIONS §0/§7. You edit their copy and numbers, never their membership.

### 3.1 Faction (`Factions.luau`)

| Field | Notes |
|---|---|
| `id` | One of the six `FactionId`s |
| `name`, `shortName` | "Iron Union", "IU" |
| `idPrefix` | Vehicle/branch id prefix (`iu`), unique across factions |
| `motto`, `description`, `focus` (2–4 bullets) | Garage and tech-tree copy |
| `emblem` | `factions/<id>` |
| `order` | 1..6, tree and filter order |
| `palette {primary, secondary, textTint}` | UI colours (brand-art §3.7) |
| `vehiclePaint {base, secondary, accent, camo}` | Default paint and the faction camouflage colours |
| `kit` | Faction kit multipliers (00-DECISIONS §7.3). **Balance lint only, never applied at runtime**: authors bake the kit into module numbers |
| `signatures` | Mechanics the faction is known for (UI chips, balance report) |
| `builderPreset` | Default Blueprint shape grammar (`iu_foundry`) |

### 3.2 Class (`Classes.luau`)

`id` (`light | medium | heavy | td | artillery`), names, `icon` (`classes/<id>`), `minimapIcon`, `order`, `tiers`
(artillery IV–X), `roles` (UI order), `baseline` (class multipliers vs the Medium baseline, lint only), `camo`
(turreted default) and `camoCasemate` (TD casemate default), `viewRangeMul` (applied at runtime), `afterShotBloom`
(default gun bloom), `terrainResistance` (default for new tracks), `signalRangeM` (only used when signal relay is
enabled in special modes; Random battles use direct spotting, 00-DECISIONS §5).

### 3.3 Role (`Roles.luau`)

Seventeen roles, `<class>_<role>` (`heavy_breakthrough`, `artillery_area_control`). Each carries garage copy
(`description`, `playstyle`, exactly three `tips`), `statEmphasis` (2–4 `StatKey`s the garage highlights), `trims`
(lint), `categorySlot` (Tier VI+ specialised equipment slot, +15 %), `roleScore` weights (sum to 1; feed the
post-battle Role Score), `group` (soft matchmaking mirror group), `badge` (`roles/<id>`), and an optional role
`fieldKit` (Tier VI–X free-swap options: two per level, option ids unique within the role because loadouts store
them).

### 3.4 Tier (`Tiers.luau`)

`tier` 1..11, `numeral`, `name` ("Apex" for XI), `badge`, `matchmaking` range (two vehicles may share a battle only
when each range contains the other's tier; ranges must be written mutually, so V is IV–VII and VI is V–VIII because
III and IV only meet ±1 — `TIER_RANGE`), `baseline` (the Medium reference row of 00-DECISIONS §7.4, lint),
`economy` (research XP, price, module XP, repair, shell price, premium Bullion and credit coefficient — authoring
targets; `Config.Economy` owns live formulas), `equipmentSlots`, `consumableSlots`, `categorySlot` (true exactly
from VI), `equipmentBand` (C/B/A), `fieldKit` (exactly VI–X), `stunMaxS`, `moduleHpRefAlpha` (module HP = k × this,
crew HP = 0.8 × this).

### 3.5 Branch (`TechTree.luau`)

```lua
{ id = "iu_bulwark", faction = "iron_union", name = "Bulwark heavy line",
  description = "The spine: from riveted box to pike nose to twin-gun wall.",
  classes = { "heavy" }, tiers = { min = 4, max = 11 }, row = 2 }
```

A branch is identity and layout only (tree headers, filter chips). Research **edges are not in branches**: they live
on vehicles (`unlocks`), and `techTreeEdges()` derives the graph, so no fact is written twice. A vehicle joins a branch
with `tree.branch`; the validator checks faction, class, tier and row against the branch (`BRANCH`). `row` is the
branch's fixed lane (roster.md §2.11: row 2 is every faction's spine), so later waves never move a node. A vehicle id
never equals a branch id (`BAD_VALUE`).

---

## 4. Ammunition and modules

### 4.1 Shells (`Shells/<Faction>.luau`)

| Field | Notes |
|---|---|
| `kind` | `AP`, `APCR`, `HEAT`, `HE`, `HESH` |
| `special` | Premium-grade round (more pen or utility), 2.5 × credit price |
| `caliberMm` | Must equal every gun that lists the shell (`SHELL_CALIBER`) |
| `damage` | Mean alpha, rolled ±25 % by Combat |
| `penetrationMm` | Mean pen at ≤ 100 m |
| `velocityMps` | In-game muzzle velocity (0.6 × real) |
| `priceCredits` | Standard shells use the tier shell price |
| optional | `moduleDamage`, `penetrationAt500Mm` (AP/APCR only — other kinds do not lose pen, `SHELL_KIND`), `gravityMps2`, `maxRangeM` (required ≥ 900 on every shell of an indirect gun: the 600 m default is the direct-fire despawn), `explosionRadiusM` (HE/HESH only), `normalizationDeg`, `ricochetAngleDeg` (not on HE/HESH: they never ricochet), `stun` (HE/HESH, and only on shells of indirect guns — `SHELL_KIND`), `tracer`, `icon` |

Authoring defaults (00-DECISIONS §1): special pen = 1.30 × AP, same alpha; HE alpha = 1.30 × AP alpha, HE pen =
calibre / 2; APCR velocity = 1.25 × AP.

### 4.2 Common module fields

Guns, turrets, engines and tracks share: `id`, `kind` (`"Gun" | "Turret" | "Engine" | "Tracks"`), `name`, `tier`
(the tier it is balanced for), `massKg` (counts against the tracks' load limit), `priceCredits`, `researchXp`.

Modules are **shared** between vehicles. Research is global: researching the 45 mm on the Kolmal also researches it
on the Ostmal, where it is stock. Price and research XP therefore sit on the module, not on the vehicle. A module
used only as stock has `researchXp = 0` and `priceCredits = 0`.

Each module carries its own **visual** (barrel, turret shape, track links, exhausts), so mounting the upgraded
turret changes both the model and the armour model.

### 4.3 Gun

| Field | Notes |
|---|---|
| `caliberMm` | |
| `shells` | 1..3 unique shell ids; the first is the standard (non-special) round (`SHELL_COUNT`, `SHELL_ORDER`) |
| `reload` | Tagged union (below); base times at crew level 100 |
| `dispersionM100` | Aiming-circle radius in m at 100 m, fully aimed |
| `aimTimeS` | Convergence time constant |
| `arcs {depressionDeg, elevationDeg}` | Positive magnitudes |
| `ammoCapacity` | At least one Magazine/Autoreloader clip (`size ≤ ammoCapacity`), at least 2 for a DualGun volley |
| `bloom?` | Overrides of movement / hull / turret / after-shot / damaged bloom |
| `camoAfterShotMul?`, `shellSwapS?` | Defaults from calibre / one reload |
| `indirect?` | Artillery howitzer: required for artillery vehicles, never on others; elevates ≥ 45°; fires HE/HESH only (standard + special HE, roster.md §0.2) |
| `visual` | `barrelLengthM`, `muzzleBrake`, `mantlet`, optional diameter, fume extractor, thermal sleeve, mantlet width |
| `audio` | Gun sound family (`small_20_45mm` …) |

Reload kinds (00-DECISIONS §4):

```lua
reload = { kind = "Single", reloadS = 2.4 }
reload = { kind = "Magazine", size = 4, intraClipS = 2, reloadS = 18 }        -- not on heavy_assault
reload = { kind = "Autoreloader", size = 3, perShellReloadS = { 9, 7, 6 }, intraClipS = 2 } -- medium / td; refill order, longest first
reload = { kind = "DualGun", reloadEachS = 12, salvoDelayS = 1.5, chargeTimeS = 1.0, volleyDispersionMul = 1.5 } -- heavy VII–X
```

Placement rules are checked against every vehicle that lists the gun (`MECHANIC`). Tier XI guns are Single, or
Magazine together with the `AdaptiveMagazine` signature (roster §2.7: an Apex carries no Tier I–X mechanic).

### 4.4 Turret

`mount` (`"Turret"` or `"Casemate"`), `armor {front, side, rear, roof, mantlet, cupola?}`, `traverseDegS`,
`viewRangeM` (base, before class factor/crew/equipment), `hpBonus` (added to hull HP), `guns` (guns it can mount, ≥ 1,
no duplicates), `yawLimitsDeg?` (positive magnitudes: `left` counter-clockwise, `right` clockwise from hull-forward),
`visual {style, lengthM, widthM, heightM, bustleLengthM?, frontAngleDeg?, sideAngleDeg?, rearAngleDeg?, cupola?}`.

**Casemates (one model, so the Blueprint and Combat agree).** A turretless TD or SPG keeps its fighting compartment
in the **hull**: either `visual.hull.superstructure` (armour `hull.armor.superstructureFront/Side`, zones
`Superstructure*`) or `hull.style = "Casemate"` (the whole hull is the compartment). Its `Casemate` "turret" module
is only the **gun mount** set into the compartment's front: `visual` (style `Casemate`) sizes the gun housing,
`armor.front` is the gun shield and `armor.mantlet` the mantlet; it sits at `turretRing`, never yaws, and the gun
yaws inside the required `yawLimitsDeg`. `MOUNT` errors: a Casemate mount without a compartment, a rotating turret on
a `Casemate` hull, Casemate style on a rotating turret (and the reverse), one vehicle mixing both mounts, a casemate
on a class other than TD/SPG. A rotating turret's footprint covers its ring (`VISUAL`).

### 4.5 Engine

`powerHp` (a gameplay value tuned to the class power-to-weight target, not a real-world rating), `fuel` (Petrol 20 %
/ Diesel 12 % / Turbine 15 % default fire chance per engine hit), `fireChance?`, `audio` (engine family), `visual?`
(exhaust count and placement).

### 4.6 Tracks

`loadLimitKg` (total vehicle mass incl. these tracks must not exceed it), `traverseDegS` (hull traverse),
`terrainResistance {hard ≤ medium ≤ soft}`, `armorMm` (spaced), `bloomMul?`, `wheeled?` (requires the Wheeled
mechanic), `visual?`.

**Physical research order.** Stock tracks are authored with 1–3 % spare load over the stock configuration, so the top
turret and gun only fit after the tracks upgrade. This enforces WoT's Tracks → Turret → Gun order through physics
instead of a rule; `LOAD_ORDER` warns when stock tracks can already carry the top configuration, `OVER_LOAD_LIMIT`
fails a `stock`/`top` configuration that is too heavy. The module tree (`requires`) states the same order for the UI.

There is **no radio module**: spotting is direct in Random battles (00-DECISIONS §2, §5), so a radio would be a
module with no gameplay. `signalRangeM` on classes is reserved for special modes.

---

## 5. Vehicles

One file per vehicle, `Vehicles/<Faction>/<PascalId>.luau`, returning one `VehicleDefinition`. The Iron Union
Foundry trunk (`iu_kolmal` I → `iu_ostmal` II → `iu_bulmal` III, roster.md §2.1) is the complete exemplar.

### 5.1 Identity

| Field | Rule |
|---|---|
| `id` | `<idPrefix>_<name>` (`iu_kolmal`) — roster.md is authoritative for ids |
| `name` (≤ 32), `shortName` (≤ 12) | Garage / markers and kill feed |
| `faction`, `tier`, `class`, `role` | `role` must belong to `class` (`ROLE_CLASS`); class must exist at the tier (`TIER_RANGE`) |
| `acquisition` | `TechTree`, `Premium`, `Reward`, `Event` |
| `description`, `lore`, `strengths` (1–4), `weaknesses` (1–4) | Garage copy |
| `tags?`, `hidden?`, `icon?` | `icon` defaults to `vehicles/<id>` (silhouette rendered from the blueprint) |

### 5.2 Hull, mobility, crew

```lua
hull = {
	hp = 280,          -- turret.hpBonus is added on top
	massKg = 6900,     -- bare hull; modules add theirs
	armor = { upperFront = 20, lowerFront = 16, side = 15, rear = 15, roof = 10, floor = 8, engineDeck = 8 },
},
mobility = { forwardKmh = 36, reverseKmh = 13 },  -- top speed is a hull property; pivot defaults true for tracks
```

`HullArmor` holds **nominal** thickness per zone; effective thickness comes from the plate angles in `visual.hull`.
`superstructureFront/Side` exist exactly when the hull has a superstructure, `skirts` exactly when
`visual.hull.skirts` is not `"None"` (`ARMOR`, both directions: a forgotten visual is as wrong as a forgotten plate).
`reverseKmh` never exceeds `forwardKmh`.

Crew: 2..6 seats, exactly one Commander (always a primary role), exactly one Driver seat, Gunner and Loader duties
covered by a primary or an `also`; the Driver never doubles up and nobody drives as a secondary duty
(`CREW_COMPOSITION`). Four crew roles only — radio duties fold into the Commander (00-DECISIONS §12). Seat order is
the profile crew slot order.

### 5.3 Modules, configurations, module tree

```lua
modules = { guns = { "iu_gun_37mm", "iu_gun_45mm" }, turrets = { "iu_turret_kolmal" },
            engines = { "iu_engine_d120" }, tracks = { "iu_tracks_kolmal" } },
stock = { gun = "iu_gun_37mm", turret = "iu_turret_kolmal", engine = "iu_engine_d120", tracks = "iu_tracks_kolmal" },
top   = { gun = "iu_gun_45mm", turret = "iu_turret_kolmal", engine = "iu_engine_d120", tracks = "iu_tracks_kolmal" },
moduleTree = { { module = "iu_gun_45mm" } },
```

- Every module listed must exist and be of the right kind (`DANGLING_REF`, `WRONG_KIND`); every gun must fit at least
  one of the vehicle's turrets and every turret must mount one of its guns (`TURRET_GUNS`).
- `stock` and `top` must be valid configurations within the load limit (`CONFIG_INVALID`, `OVER_LOAD_LIMIT`). `top`
  is required: the balance lint and the Compare screen read it, so wherever the vehicle lists a researchable module
  for a slot, `top` mounts one of them (`CONFIG_INVALID` warning).
- `moduleTree` lists every non-stock module exactly once; `requires` names modules of this vehicle researched first.
  No stock modules in the tree, no foreign modules, no cycles (`MODULE_TREE`, `MODULE_UNREACHABLE`, `MODULE_CYCLE`).
  A module in a tree is researched, so it has `researchXp > 0` and `priceCredits > 0`.
- **Mountable when researched** (`MODULE_TREE`): with only the stock modules plus everything a node requires
  (directly or through its prerequisites), some configuration must contain the node, mount the gun in the turret and
  fit the tracks' load limit. A gun that only the upgraded turret carries must require that turret; a turret too
  heavy for the stock tracks must require the tracks. Bulmal example: tracks m2 → turret m2 → 76 mm; engine d250
  independent (it fits the stock tracks).

### 5.4 Research, unlocks, price, acquisition

```lua
unlocks = { { vehicle = "iu_ostmal", requires = "iu_gun_45mm" } },  -- on the PARENT
researchXp = 350,                                                   -- on the TARGET (XP to research it)
price = { credits = 35000 },
tree = { row = 2, branch = "iu_foundry" },
```

| Acquisition | Rules (`ACQUISITION`, `UNLOCK_EDGE`) |
|---|---|
| `TechTree` | Tier I: `researchXp` nil, `credits = 0`, no parent. Tier II+: `researchXp` and credits > 0, reachable from a Tier I vehicle of its faction (`UNREACHABLE_VEHICLE`). Priced in credits only. Belongs to a branch (`tree.branch`, `BRANCH`) |
| `Premium` | Tiers II–IX, priced in Bullion only, no research, no module tree (arrives fully upgraded, so every listed module is stock and `stock == top`) |
| `Reward`, `Event` | Not sold (`price = {}`), not researched, no module tree |

Store items may grant Premium and Event vehicles only; a TechTree or Reward vehicle in any store grant is a `STORE`
error (it would bypass research or the reward).

Unlock edges go to the same faction, same or next tier, tech-tree targets only, no duplicates, `requires` must be a
module of the parent (a stock one warns: the unlock would need no research). The tree is acyclic
(`TECH_TREE_CYCLE`) and every faction has a Tier I root (`NO_ROOT`). A tech-tree vehicle is never a reward
(`REWARD`), and every Reward/Event vehicle must be handed out by a reward, a store grant or an event mode's rental
list (`ORPHAN` warning).
`tree.row` is unique per faction + tier for tech-tree vehicles (`TREE_POSITION`); premium and reward vehicles sit in
the side panel.

### 5.5 Mechanics, arcs, slots, economy

- `mechanics?` (`Content.Mechanics`): `SiegeMode` (TD Sniper and Support only, 00-DECISIONS §4), `Hydropneumatic`
  (medium), `Wheeled` (light; needs wheeled tracks, and wheeled tracks need it). `Turbo`, `RocketBoost`,
  `ChargedShot`, `ActiveCooling`, `AdaptiveMagazine` (needs a Magazine gun) and `ReserveTracks` (destroyed tracks
  replaced after `repairS`, `charges` per battle; not assigned to a launch Apex) are Tier XI signatures (or Event
  vehicles). Runtime placement: VehicleSim runs SiegeMode, Hydropneumatic, Wheeled, Turbo, RocketBoost,
  ReserveTracks; GunState runs ChargedShot, ActiveCooling, AdaptiveMagazine and the reload kinds. At most one of
  SiegeMode, Wheeled, Turbo, RocketBoost and ActiveCooling per vehicle: `InputCommand.mechanic` is one key. A
  `ChargedShot` sets only the factor of its `effect` (`dispersionMul` or `damageMul`) and rides the fire trigger, so
  every gun of its vehicle is a `Single` reload gun. `Wheeled` comes as a set: wheeled tracks, the `"Wheeled"`
  suspension visual with `roadWheels = wheelPairs`, and no `mobility.pivot` (and the Wheeled suspension never
  appears without the mechanic). Wheel damage is per side (`TrackLeft`/`TrackRight`): `lostPairSpeedMul` applies per
  destroyed side and never immobilises.
- Roster lint (`MECHANIC` warning): once there are ≥ 20 Tier I–X vehicles, at most 20 % may be special (a
  non-Single top gun or SiegeMode / Hydropneumatic / Wheeled).
- `arcSectors?`: per-yaw depression/elevation limits (rear-deck hump). Yaw 0 = forward, + = clockwise, and a sector
  is swept **clockwise from `fromDeg` to `toDeg`** (`{150, -150}` is the 60° rear arc through 180; `fromDeg ≠ toDeg`).
  A sector only limits: its depression/elevation never exceed any of the vehicle's guns' arcs.
- `slots?`, `economy?`, `camouflage?`, `audio?`: overrides of tier/role/class/engine defaults (`slots.categorySlot`
  only from Tier VI).
- **Field Kits** (`FIELD_KIT`): a Tier VI–X vehicle's role must define at least as many `fieldKit` levels as the tier
  grants (VI–VII 3, VIII 4, IX–X 5). There is no class-wide fallback.
- `balanceException?`: written reason a stat may leave the lint envelope.

### 5.6 Tier XI (Apex)

Exactly one signature mechanic and no Tier I–X mechanic (no SiegeMode / Hydropneumatic / Wheeled, no DualGun or
Autoreloader gun), a single configuration (`stock == top`, one module per kind), no module tree, and an `apex` track
of exactly 6 Small, 3 Large and 1 Final node (`APEX`, an error). Nodes carry `StatModifier`s and XP costs; the final
node upgrades the signature through the `mechanic*` StatKeys (`mechanicChargeTime`, `mechanicCooldown`,
`mechanicDuration`, `mechanicCharges`, `mechanicFactor`), which StatsCalculator applies to the resolved copy in
`VehicleStats.mechanics`.

---

## 6. Visuals, armour and weak points

The Blueprint (vehicle builder) turns `visual` + the mounted modules' visuals into the rendered model **and** the
`ArmorModel` that Combat ray-tests. Authors never place parts.

```lua
visual = {
	hull = { lengthM = 4.4, widthM = 2.3, heightM = 1.4, groundClearanceM = 0.35, style = "Boxy",
	         upperFrontAngleDeg = 50, lowerFrontAngleDeg = 30, upperFrontFraction = 0.5, rearAngleDeg = 10,
	         turretRing = { positionFraction = 0.42, diameterM = 1.0 },
	         engineDeck = "Louvered", fenders = true, skirts = "None" },
	running = { roadWheels = 4, wheelDiameterM = 0.7, returnRollers = 0, sprocket = "Rear",
	            trackWidthM = 0.35, suspension = "Leaf" },
	details = { exhausts = 2, toolboxes = 1, headlights = 1, towCables = true },
	layout = { engine = "Rear", transmission = "Rear", ammoRacks = { "HullMiddle" }, fuel = "Rear" },
	hooks = { "tractor_chassis" },
},
```

- **Shape.** `hull.style` + angles + `superstructure?` + `sponsons?` define the hull; the turret module's `visual`
  defines the turret; the gun module's `visual` the barrel and mantlet. `preset?` overrides the faction
  `builderPreset` (shape grammar: `iu_foundry` = low faceted domes, block mantlets, no bustle). `hooks?` names
  silhouette features from roster.md's "visual hook" column (`pike_nose`, `drum_bulge`); keys are snake_case and
  unknown keys are ignored by the Blueprint, so authors can add the roster hook before the builder implements it.
- **Armour** comes from `hull.armor` and `turret.armor` thicknesses applied to the faces the shape produces; angles
  give effective thickness, so the same 20 mm plate is strong at 50° and weak at 10°. Tracks (`tracks.armorMm`) and
  skirts are spaced armour.
- **Weak points emerge from layout.** `layout` places the internal module volumes: a front transmission sits behind
  the lower plate (it is an `Engine` volume: transmission hits damage the engine and can start fires), `Bustle` racks
  sit in the turret overhang (requires a turret with `bustleLengthM`, `LAYOUT`), `Sponsons` racks run along the hull
  sides above the tracks (inside the sponsons when `hull.sponsons`, against the side walls otherwise), `Sides` fuel
  sits behind the side plates, the cupola optics are a thin-roofed bump. Several racks or tanks are several volumes
  of ONE module (one HP pool). Crew seats follow the roles (driver hull-front, turret crew in the turret, all-hull for
  casemates). `layout.overrides` (explicit `InternalVolumeSpec`s) and `crewSeats` (`CrewSeatSpec`: each seat placed
  at most once; `group` "Hull"/"Turret" picks the space of `centerM`, default Hull for the Driver and casemates,
  Turret otherwise; the Driver never sits in the turret and casemates have no turret seats, `LAYOUT`) are for the rare
  vehicle a preset cannot express.
- **Sanity** (`VISUAL`): clearance below the roof, ring narrower than the hull, superstructure shorter than the hull,
  detail counts in range.

### 6.1 Coordinate conventions (`Types/Vehicle.luau`)

- Hull space: origin = centre of the hull footprint at ground contact; **−Z forward**, +Y up, +X right.
- Turret space: origin = turret-ring centre at the ring plane.
  `world = hullCFrame * pivots.turretRing * CFrame.Angles(0, -yaw, 0) * p` (yaw radians, + = clockwise).
- Gun space: origin = trunnion, −Z = barrel at elevation 0.
  `world = turretWorld * pivots.gunTrunnion * CFrame.Angles(elevation, 0, 0) * p`.
- Casemate: turret group fixed (yaw 0); the gun yaws within `yawLimitsDeg` about the trunnion Y axis, then elevates:
  `world = hullCFrame * pivots.turretRing * pivots.gunTrunnion * CFrame.Angles(0, -gunYaw, 0) * CFrame.Angles(elevation, 0, 0) * p`.
- Yaw bearings (arc sectors, yaw limits) are hull-relative degrees in (−180, 180], 0 = forward, + = clockwise; arc
  sectors sweep clockwise from `fromDeg` to `toDeg`; `yawLimitsDeg {left, right}` are positive magnitudes.
- `ArmorModel`/`VehiclePivots` are in **studs**; `InternalVolumeSpec` (authored) is in metres with the same axes.
- `ArmorFace`: points inside satisfy `normal:Dot(p) <= distance`; a volume is the intersection of its faces (≥ 4).

### 6.2 How Combat walks the armour model (`ArmorVolumeKind`)

| Kind | What it is | A shell that hits it |
|---|---|---|
| `Armor` | The body of a group: hull box, sponsons, superstructure, turret shell, cupola. The vehicle's interior is the union of these | Penetration = inside: rolled HP damage + the internal path (Module/Crew volumes within max(0.5 m, 10 cal)). From inside, Armor faces end the path (shells never exit) |
| `Layered` | Main armour outside the body: gun mantlet, appliqué plates | Must be penetrated, then the body behind it (pen −= T_eff, continue). Penetrating only it: no HP damage. HE/HESH stopped here: non-penetration damage from its nominal thickness |
| `Spaced` | Screens, skirts, tracks/wheels, the gun barrel | pen −= T_eff (HE/HESH: 3 T), continue; never HP damage on its own; `module` names the external module it damages |
| `Module`, `Crew` | Internal volumes (thickness 0) | Reached only on the post-penetration path |

Faces shared by two adjoining Armor volumes cannot be reached from outside. `ArmorFace.spaced` mirrors
`volume.kind == "Spaced"` for face-level consumers. The Armor Inspector reads the same volumes (zone, thickness,
label, module) as Combat, so what it shows is what the server resolves.

---

## 7. From content to `VehicleStats`

`StatsCalculator` (combat-owned) resolves a `Loadout` into one `VehicleStats` per battle; hot loops only read it.

1. **Configuration base.** `hp = hull.hp + turret.hpBonus`; `massKg` = `configurationMassKg`; power, fuel and fire
   chance from the engine; `specificPowerHpT = power / (mass / 1000)`; speeds and pivot from `mobility`; hull
   traverse, terrain resistance and load limit from the tracks; mount, traverse, yaw limits, armour from the turret;
   gun stats from the gun (+ `arcSectors`); base view range = `turret.viewRangeM × class.viewRangeMul`; camo from
   `vehicle.camouflage`, else the class `camoCasemate` for a casemate mount when the class has one (TD), else the
   class `camo` (artillery uses its class camo); module HP from `tier.moduleHpRefAlpha`, crew HP 0.8 × the same
   (`CrewSlotStats.maxHp`).
2. **Crew.** Level L = 100 (+ ventilation, rations, Brothers in Arms; injured 50). Reload × 0.875/(0.00375·L + 0.5)
   averaged over everyone with Loader duty; f(L) = 0.57 + 0.0043·L multiplies view range and traverse and divides
   aim time, dispersion and repair time, each taken from the member holding that duty (00-DECISIONS §4).
3. **Always-on modifiers** from equipment (category-slot match uses `categorySlotEffects` or × 1.15 on each delta),
   crew skills (scaled by training; Group skills by crew share), passive consumables, Field Kit choices and Apex
   nodes. Per stat: `adds` sum in the stat's unit, `muls` multiply; result = (base + Σadd) × Πmul. Items sharing an
   `exclusiveGroup` never stack (the loadout validator rejects the second).
4. **Conditional modifiers** (`condition ~= "Always"`) are copied into `VehicleStats.conditionalModifiers` and applied
   by the system that owns the stat at the moment the condition holds (Spotting for `StationaryArmed` nets, GunState
   for `AfterShot`, VehicleSim for `MechanicActive`).
5. Faction kits, class baselines and role trims are **not** applied: they are already baked into the authored numbers
   and only the balance lint reads them.
6. `VehicleStats.mechanics` holds resolved copies of the vehicle's mechanics with the Apex `mechanic*` StatKeys
   applied (final node: charge 1.5 → 1.2 s is `{ stat = "mechanicChargeTime", op = "mul", value = 0.8 }`).
7. **Every StatKey has exactly one home** (table in the `VehicleStats` comment, checked by `Types/Vehicle.spec`):
   e.g. `damageRollMin` / `penetrationRollMin` → `gun.damageRollMinAdd` / `penetrationRollMinAdd` (fraction of the
   mean added to the roll's lower bound), `damagedModulePenalty` → `modules[kind].damagedPenaltyMul`, `crewXp` →
   `crewXpMul` (Scoring reads it). A new StatKey needs a home in the same change.

Crew-perk mapping (00-DECISIONS §12 starters) — every starter is expressible with today's StatKeys: Recon
`viewRange` + `damagedModulePenalty` (module `Optics`), Practicality `consumableCooldown`, Mentor `crewXp`, Snap Shot
`bloomTurretTraverse`, Deadeye `dispersion` with `StationaryArmed`, Quick Aiming `aimTime` + `turretTraverse`, Clutch
Braking `hullTraverse`, Smooth Ride `ramDamageDealt` / `ramDamageTaken`, Engineer `topSpeed` / `reverseSpeed` +
`damagedModulePenalty` (module `Engine`), Intuition `shellSwapTime`, Close Combat `reloadTime` with `NearEnemy`
(`rangeM = 50`), Ammo Tuck `damageRollMin` + `penetrationRollMin`. The `module` qualifier is valid only on
`moduleHp`, `repairTime` and `damagedModulePenalty` (`BAD_VALUE`).

---

## 8. Loadout items, cosmetics, missions, achievements, live-ops

All of these registries ship **empty** in v1 (with a commented example entry per file); the spec builds valid
fixtures of each to prove the validators.

| Kind | Key rules |
|---|---|
| `EquipmentDefinition` | `categories` 1–4, `grade` Standard (credit price) / Refined (Campaign Token price), `tiers` band inside ONE `equipmentBand` (C/B/A), `exclusiveGroup`, `effects` (non-empty unless `effectsByClass`), `compatibility` (classes, roles, turret, mass with min ≤ max, `excludeMechanics`, `excludeReload` — rammers exclude `Magazine`), price never Bullion-only (`PRICE`) |
| `ConsumableDefinition` | `activation` Manual/Automatic/Passive; Manual/Automatic need `cooldownS` (and `durationS` when they have `effects`); only Automatic has `triggerDelayS`; `charges` = uses per battle (nil = unlimited, never on Passive); RepairKit/MedKit/Extinguisher repair modules/crew/fire; Smoke is `eventOnly`; always a credit price > 0 (`PRICE`); Bullion never undercuts credits at 1:200 |
| `CrewSkillDefinition` | `roles`, `kind` Individual/Group, `effects` at 100 % training (perk mapping: §7) |
| `CrewBookDefinition`, `BoosterDefinition` | Booster needs `durationS` or `battles` |
| `CustomizationDefinition` | `kind` Paint, Camouflage, Emblem, Inscription, Decal, Attachment (3-D add-on, never armour), Effect (shot/tracer/destruction), Style, GunSleeve, StatTracker; `rarity`, `scope`, `source`; `colors` for Paint/Camouflage; `camoBonus` (flat paint camo bonus, 0 in competitive modes) only on Paint/Camouflage/Style |
| `MissionDefinition` | `cadence`; `difficulty` exactly on Daily missions; `match` All/Any over `conditions` (`stat` + `atLeast`/`atMost`, `aggregate` SingleBattle/Cumulative; `teamXpRank` is SingleBattle + `atMost` only, `roleScore` SingleBattle only; `against.classes` only on damageDealt, kills, spotted, assistTotal, damagePlusAssist; `medal` narrows stat `medals` to one BattleMedal), `scope`, `rewards`, `honors?`; Campaign missions need a `campaign` block whose (campaign, operation, series, index) slot is unique; Event missions name their event and the event lists them — both directions (`MISSION`). `BattleStatKey` names every `BattleStats` counter (hits/pens/ricochets received, stuns, fires, time alive, Role Score, sole-spotter and later-killed counts…) |
| `AchievementDefinition` | `rule` names an evaluator in `Shared/Progression/Achievements` (checked when `validate({ achievementRules })` gets the catalogue), `stat` + `params` its arguments, `thresholds` strictly increase (required for Milestone and Streak), Mastery/Marks are `perVehicle` and filed under the category of the same name, `scope` tiers ordered, `rewards` (`{}` when none) |
| `Reward` | `{ kind, id?, amount }`; `id` required for item kinds and `EventTokens`, and must reference the right kind; a Vehicle is granted with `amount = 1` and is never a tech-tree vehicle (`REWARD`) |
| `StoreItem` | Exactly one of `price` or `robux` (Robux prices are never stored — Managed Pricing); Bullion packs are `DeveloperProduct`s; a `GamePass` is owned once, so only `purchaseLimit = 1` items use one; each kind grants what it sells (BullionPack → Bullion, PremiumTime → PremiumDays, PremiumVehicle → exactly one Premium vehicle, …); vehicles granted by any item are Premium or Event only; an event-token price means the item is in that event's shop; fixed grants only, no paid random items (`STORE`) |
| `EventDefinition` | Window `startsAt < endsAt`, `shopClosesAt ≥ endsAt`; missions/maps/vehicles/shop refs; every shop item is priced in this event's tokens (`STORE`); `modes` with unique ids, mode-only abilities with unique ids (never on vehicles), `battleTypes` the mode plays (its maps must have them, `SCHEDULE`), `competitive` (never allows artillery in `classCaps`), `classCaps`; kind `Ranked` = exactly one mode with a `ladder`, and only Ranked events have one (`SEASON`) |
| `RankLadder` (in a Ranked mode) | `ranks` lowest first (unique ids; every rank but the top needs `pointsToAdvance > 0`, the top has 0; `protected` ranks cannot be lost; per-rank promotion `rewards`), `points` by team XP rank (ascending, `loss` may be negative), `finalRewards`. Player standing: `Profile.events[eventId].ranked` |
| `SeasonDefinition` | Chapters (unique ids), ascending `pointsByRank`, stages within the chapter, one reward per (stage, track), Paid rewards only with a `paidUnlock` that is a SeasonPass store item; seasons never overlap (`Profile.pass` tracks one) (`SEASON`) |

---

### 8.1 Loadout legality (`checkLoadout`)

`registry:checkLoadout(loadout, { eventItems? })` returns `Ok(true)` or the first problem as
`Err(NOT_FOUND | INVALID_ARGS, "path: problem")`:

- `checkConfiguration` passes; `ammo` holds ≤ 3 distinct shells of the mounted gun, whole counts, Σ ≤ `ammoCapacity`.
- `equipment` / `consumables`: distinct slots within the vehicle's slot count (`slots` override, else the tier's),
  known items, one item per `exclusiveGroup`, inside the item's tier band and compatibility; event-only consumables
  only with `eventItems = true`.
- `crew`: one member per seat with the seat's role and secondary duties, level 1..200, ≤ 5 distinct known skills that
  suit one of the member's duties, training 0..1; `crewPerkEfficiency` 0.75..1.
- `customization`: each slot holds a cosmetic of that kind whose `scope` admits the vehicle; ≤ 4 distinct attachments.
- `fieldKit`: at most the tier's Field Kit levels, each an option id of that level of the role's `fieldKit`;
  `apexNodes`: distinct node ids of the vehicle's Apex track.

Ownership, research and inventory counts are deliberately not checked here: Transactions owns them. Note that Tier I
has two equipment slots but the C band starts at Tier II, so nothing mounts there until a band covers Tier I.

## 9. Maps

One file per map. `Maps/ProvingGrounds.luau` is the exemplar (800 m, Tiers I–III, Standard).

| Field | Rule |
|---|---|
| `sizeM`, `skirtM?` | Playable square side (1000; 800 for city / Tier I–III); scenery skirt beyond the red line (150) |
| `tierRange`, `battleTypes`, `modes` | Matchmaking pools |
| `terrain` | Seeded recipe: `noise` octaves, `features` (Hill, Ridge, Valley, …; Road and Riverbed along polylines of ≥ 2 points), `materials` (first matching rule wins; exactly one `Default`, which takes no bounds; Slope/Height rules need `min` and/or `max`, Feature rules a `feature`; `MAP_TERRAIN`), `waterLevelM?` |
| `spawns.team1/team2` | ≥ 15 slots each, ≥ 3 `rear` (SPG/TD), ≥ 10 m apart, inside the playable square and outside every water body, team centroids ≥ 0.7 × `sizeM` apart (`MAP_SPAWNS`, `MAP_BOUNDS`, `MAP_SEPARATION`) |
| `bases` | Per declared battle type: Standard one per team, Encounter one neutral, Assault one defender base; ≥ 60 m inside the edge; a team's base lies nearer its own spawn centroid than the enemy's; an Encounter base should be equidistant ±5 % (warning) (`MAP_BASES`) |
| `lanes` | At least one `Heavy`, one `Flex`, one `Open` (`MAP_LANES`) |
| `positions` | Tactical points (`HullDown`, `Brawl`, `Sniper`, `Scout`, `Flank`, `Artillery`) with `facingDeg`, owning `team` (nil = contested), optional `lane` and `classes`. Per team at least 3 HullDown, 1 Sniper and 1 Scout, plus 1 Artillery pit when SPGs can play the map (Random, tiers meeting IV–X) (`MAP_POSITIONS`). Bots, minimap hints and map QA read them |
| `foliage` | Analytic concealment volumes for Spotting (sphere or capsule), never engine geometry |
| `props`, `water?` | Builder props (`PropKind` owned by the map builder; bridges, large buildings and rocks are `destructible = "Permanent"` structures), water bodies |
| `variants` | ≥ 1 cosmetic lighting/weather variant (no gameplay weather) |
| `randomEvents?` | Reserved layout-event hook (none at launch); its props are validated like map props |
| `audio`, `thumbnail?`, `minimap?`, `tips`, `revision` | `minimap` = top-down image of the playable square (nil = rendered from the terrain recipe). Bump `revision` on every geometry change |

Local ids (bases, lanes, positions, water bodies, variants, random events) are unique within their list. Encounter
and Assault start at Tier IV in Random battles, so a map below Tier IV that lists them warns unless an event mode
plays that battle type on it (`MAP_BASES` warning).

Spawn facing: 0° = north (−z), clockwise.

---

## 10. Recipes

### 10.1 Add a vehicle

1. Check roster.md for the id, name, class, role, branch, row and visual hook.
2. Add any new modules to `Guns/Turrets/Engines/Tracks/<Faction>.luau` and shells to `Shells/<Faction>.luau`
   (reuse the parent's top modules as stock where the roster carries them over).
3. Copy the nearest exemplar to `Vehicles/<Faction>/<PascalId>.luau`; set identity, hull, mobility, crew, modules,
   `stock`, `top`, `moduleTree`, `unlocks` (usually empty until the child exists), `researchXp`, `price`, `visual`,
   `tree`.
4. On the parent, add `{ vehicle = "<id>", requires = "<parent top gun>" }` to `unlocks`.
5. Add one line to `vehicles` in `Content/init.luau`.
6. Run `scripts/check.sh --only test -- ContentRegistry`. Fix every issue; shipped content allows no warnings.

Balance targets: tier baseline row × class baseline × role trim × faction kit, within ±8 % unless
`balanceException` explains why (00-DECISIONS §7). Masses: stock configuration at 97–99 % of the stock tracks'
`loadLimitKg`.

### 10.2 Add a module only

Add it to the faction file, list it in each vehicle's `modules`, add a `moduleTree` node (with `requires`) on each
vehicle where it is researched, and give it `researchXp`/`priceCredits` (0 if only ever stock). An unused module
raises `ORPHAN`.

### 10.3 Add a map

Copy `ProvingGrounds.luau`, keep 15 spawns per team with ≥ 3 rear, mirror or balance lanes, place each team's
positions (3 hull-down, a sniper and a scout spot, an artillery pit from Tier IV), declare the battle types you
placed bases for, add the file to `maps` in `Content/init.luau`, run the registry spec.

### 10.4 Add a mission, achievement, store item or event

Write the entry in its registry file (each file shows a commented example), referencing existing ids only. Rewards
use `Reward` records; event-token prices and rewards name the event.

---

## 11. Issue codes

| Code | Severity | Meaning |
|---|---|---|
| `INVALID_ID` | E | Id not snake_case, too long, or the wrong type |
| `DUPLICATE_ID` | E | Id used twice in a kind (module ids: across all four module kinds) |
| `MISSING_FIELD` | E | Required field absent |
| `UNKNOWN_FIELD` | E | Field not in the schema at any depth (typo protection) |
| `BAD_VALUE` | E/W | Out of range, wrong enum, not snake_case (registry or local id), duplicate local id, bad or reused prefix, non-finite number, Field Kit outside VI–X, category slot (tier or vehicle override) below VI, clip larger than the ammo rack, dual gun with < 2 rounds, arc sector wider than the gun or with equal ends, reverse faster than forward, module qualifier on a stat without modules, equipment spanning two price bands, inverted compatibility masses, non-event smoke, competitive mode with artillery, Mastery/Marks kind and category apart, vehicle id equal to a branch id; autoreloader whose first refill is not the longest (W) |
| `DANGLING_REF` | E | Reference to an id that does not exist (incl. a position's lane, an achievement rule missing from the supplied catalogue) |
| `WRONG_KIND` | E | Reference resolves to the wrong kind (a turret listed as a gun) |
| `LOCKED_SET` | E | Factions/classes/roles/tiers differ from the locked sets |
| `ROLE_CLASS` | E | Role does not belong to the class |
| `ROLE_SCORE` | E | Role Score weights do not sum to 1 |
| `TIER_RANGE` | E/W | Class or branch outside its tier range; one-sided tier matchmaking range; module tier more than one tier from the vehicle's (W) |
| `SHELL_KIND` | E | Field not valid for the shell kind or gun (HE falloff, AP explosion radius, ricochet angle on HE/HESH, stun on a direct-fire gun's shell, artillery shell without maxRangeM ≥ 900, kinetic/HEAT shell on an artillery gun) |
| `SHELL_COUNT` | E | Gun has 0 or more than 3 shells, or duplicates |
| `SHELL_CALIBER` | E | Shell calibre differs from the gun's |
| `SHELL_ORDER` | E | The first shell is a special round (the first must be the standard round) |
| `ORPHAN` | W | Shell or module nothing uses; Reward/Event vehicle nothing hands out |
| `MOUNT` | E | Casemate without yaw limits or Casemate style (or Casemate style on a rotating turret); casemate on a vehicle that is not TD/SPG; casemate mount without a superstructure or Casemate hull; rotating turret on a Casemate hull; one vehicle mixing both mounts |
| `CONFIG_INVALID` | E/W | `stock`/`top` names a module not on the vehicle or a gun the turret cannot mount; `top` keeps a stock module although an upgrade exists (W) |
| `OVER_LOAD_LIMIT` | E | Configuration heavier than its tracks' load limit |
| `LOAD_ORDER` | W | Stock tracks can already carry the top turret + gun, or have more than 5 % spare load on the stock configuration |
| `MODULE_TREE` | E | Tree node is not one of the vehicle's modules, is stock, appears twice, costs no research XP / credits, `requires` itself / a foreign module, or cannot be mounted with the stock modules + its prerequisites |
| `MODULE_UNREACHABLE` | E | A listed module is neither stock nor in `moduleTree` |
| `MODULE_CYCLE` | E | Module tree has a cycle |
| `TURRET_GUNS` | E | A gun fits none of the vehicle's turrets, or a turret mounts none of its guns |
| `UNLOCK_EDGE` | E/W | Cross-faction, tier skip, non-tech-tree target, duplicate, bad `requires`; `requires` a stock module (W) |
| `TECH_TREE_CYCLE` | E | Research graph has a cycle |
| `NO_ROOT` | E | A faction with vehicles has no Tier I tech-tree vehicle |
| `UNREACHABLE_VEHICLE` | E | Tech-tree vehicle not reachable from a Tier I root of its faction |
| `TREE_POSITION` | E | Two tech-tree vehicles share faction + tier + row |
| `BRANCH` | E | Vehicle's branch belongs to another faction, lacks its class, excludes its tier, or sits on another row; tech-tree vehicle without a branch |
| `FIELD_KIT` | E | A Tier VI–X vehicle's role defines fewer Field Kit levels than the tier grants |
| `CREW_COMPOSITION` | E | Seat count, Commander count, Driver seat count, duty coverage, Driver doubling or driving as a secondary duty |
| `ACQUISITION` | E/W | Research/price/currency rules per acquisition kind (§5.4) |
| `MECHANIC` | E/W | Mechanic on the wrong class/role/tier, duplicate, wheeled mismatch (tracks, suspension visual, wheel pairs vs road wheels, pivot), reload kind not allowed, Tier I–X mechanic on an Apex, AdaptiveMagazine without a Magazine gun, ChargedShot on a non-Single gun, two mechanics on the one mechanic key, ChargedShot factor of the other effect; roster special share > 20 % (W) |
| `APEX` | E | Tier XI track missing/misshapen (exactly 6 Small, 3 Large, 1 Final), an apex track below XI, more than one module per kind or a module tree at XI |
| `VISUAL` | E/W | Impossible proportions (incl. a rotating turret smaller than its ring); detail counts out of range |
| `ARMOR` | E | Skirts or superstructure without their armour, or their armour without them |
| `LAYOUT` | E | Ammo racks or internal volumes the shape cannot hold (bustle rack without a bustle); crew seat placed twice, Driver or casemate crew seated in the turret |
| `PRICE` | E | Bullion-only equipment, Standard equipment without credits, Refined without Campaign Tokens, consumable without a credit price, Bullion undercutting credits |
| `REWARD` | E | Reward kind without the id it needs, id of the wrong kind, vehicle granted more than once, tech-tree vehicle granted |
| `MISSION` | E | Condition without bounds, inverted bounds or tiers, rank/Role Score stat counted cumulatively, `against` on a stat that cannot be split, `medal` filter off stat `medals` or naming a non-medal, difficulty on the wrong cadence, missing campaign/event block, campaign slot reused, event ↔ mission link one-sided |
| `MAP_SPAWNS` | E | Too few slots or rear slots, slots closer than 10 m, slot inside a water body |
| `MAP_BOUNDS` | E | Spawn, base, lane or foliage point outside the playable square; terrain feature, prop or water point outside the square plus skirt |
| `MAP_SEPARATION` | E | Team spawn centroids closer than 0.7 × size |
| `MAP_BASES` | E/W | Missing/extra bases for a battle type, base within 60 m of the edge, base on the enemy's side; Encounter base not equidistant (W); Encounter/Assault on a map below Tier IV that no event mode plays (W) |
| `MAP_LANES` | E | Missing Heavy, Flex or Open lane |
| `MAP_POSITIONS` | E | A team without 3 HullDown / 1 Sniper / 1 Scout positions (+ 1 Artillery pit when SPGs play), bad team, duplicate id |
| `MAP_TERRAIN` | E | Not exactly one Default material rule, bad or missing rule bounds, single-point road/riverbed |
| `STORE` | E | Not exactly one of price/robux; Bullion pack not a developer product; GamePass on an item without `purchaseLimit = 1`; item not granting what its kind sells; TechTree/Reward vehicle sold; event-token price outside that event's shop or shop item not in its tokens |
| `SCHEDULE` | E | Window inverted, token shop closing before the event ends, event mode on a map without its battle type |
| `SEASON` | E | Pass/ladder points not ascending, reward stage beyond the chapter, stage rewarded twice, Paid reward without a paid unlock, bad paid unlock, duplicate chapter/rank id, ladder on a non-Ranked event or a Ranked event without exactly one ladder, ladder top rank with points to advance, overlapping seasons |
| `ASSET_KEY` | E | Icon or sound key malformed, or missing from the supplied catalogue |

`ContentRegistry.spec` has a "covers every issue code" test: adding a new code without a failing test case fails the
build.

---

## 12. Player and battle records

**Profile v1** (`Types/Profile.luau`): one DataStore key per player. Collections that grow forever are rings with a
fixed maximum (`Profile.LIMITS`): 20 battle-history entries, 200 processed battle ids, 200 processed receipts, 50
request ids, 10 pending battles, 500 claimed missions, 50 purchases, 10 active boosters, 400 crews, 5 skills per crew
member, 2 blacklisted maps. Besides garage, crews, inventory, missions, pass and achievements it stores the
matchmaking preferences (`matchmaking.mapBlacklist`, `battleTypeOptOuts`), the Plus state (`account.plusVehicleId`,
the daily Plus crew-XP counter) and, per Ranked event, the ladder standing (`events[id].ranked`). Each vehicle record
keeps the non-stock modules already bought for it (`ownedModules`: remounting is free, a module is paid once per
vehicle), and each joined event records when its end-of-event settlement ran (`settledAt`: Ranked final rewards and
token conversion are granted exactly once). Crew members store skill ids plus total crew XP (training is derived), which keeps a vehicle record at
≈ 2.8 KB. A maxed profile with 150 vehicles encodes to ≈ 480 KB (target 200 KB, warn 512 KB, fail 2 MB — the profile
spec measures this every run). Migrations bump `SCHEMA_VERSION`.

**Battle ledger** (`Types/Battle.luau`): the battle server emits `BattleEvent`s (Started, Spotted, Shot with the
shooter's `ammoLeft`, Damage with the first plate's zone / effective armour / rolled pen, ModuleState, CrewInjured,
Fire, Stunned, Destroyed, ConsumableUsed, Capture*, ControlChanged, Ended), accumulates `BattleStats` per participant
(including `byTargetClass` for missions with `against`) and produces a `BattleResult` whose `RewardBreakdown` lists
every credit/XP line (`LedgerLine`) so the results screen shows exactly how rewards were computed.

- Each `BattleParticipant` carries `maxHp` and, for humans, the `RewardContext` the Hub snapshotted at enqueue
  (Premium Time, Plus and its boosted vehicle, Roblox Premium, first win available, active boosters, events): battle
  servers never read profiles, so this is how Scoring fills the bonus lines.
- Credit boosters have their own line (`boosterBonus`, `BoosterCredits`); FreeXP/CrewXP boosters and the crew's
  `crewXpMul` are folded into `freeXp` / `crewXp`, whose lines carry the multiplier. `ResultRow.platoonId` drives the
  Team tab's platoon badges.
- `CreditReport` splits ownership: the battle server fills earnings and `repairCost`; the Hub's RewardService fills
  `missionRewards`, `ammoCost` / `consumableCost` (resupply depends on depot stock and auto-resupply) and
  `debtWaived` (credit balance), appends their lines and recomputes `net`.
- `RewardInboxEntry` = summary + rewards + `roster` (`ResultRow` per participant, the Team tab) + `interactions`
  (per-enemy hits for the player) + consumed ammo/consumables + AFK strike. `BattleSummary` (with `botShare`,
  `eventId`/`eventModeId`) is the compact copy kept in profile history; roster and interactions are shown in the
  session that applies the entry and are not stored in the profile.
