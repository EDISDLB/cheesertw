# HULLDOWN: Faction & Vehicle Roster Bible

> **Status:** authoritative for the launch roster, tech-tree topology, vehicle ids, display names, roles,
> branch identities, visual hooks and vehicle lore. Owner: Lead Vehicle & Progression Design.
> **Precedence:** `docs/research/00-DECISIONS.md` wins on every number and rule (class multipliers §7.1, roles
> §7.2, faction kits §7.3, MT baseline §7.4, mechanics §4, economy §11, matchmaking §8). `docs/design/brand-art.md`
> wins on colour, iconography and copy tone. `docs/ARCHITECTURE.md` wins on data layout
> (`Shared/Config/Content/Vehicles/<Faction>/<VehicleId>.luau`, `TechTree.luau`, `Blueprint`/`VisualSpec`), and
> `docs/design/content-schema.md` with `Types/Content.luau` wins on field names and validator rules (this document
> names the schema field wherever a roster feature maps to one).
> This document chooses *which* vehicles exist and *what each one is for*; content authors fill exact numbers inside
> the bands of §5 and the balance lint (§7.4 of the decisions doc, made operational in §5.1) decides pass/fail.
> **Change control:** a vehicle id, class, role, tier, mechanic, research edge or tree row changes here and in the
> data in one commit: research edges and rows live on the vehicle files (`unlocks`, `tree`), branches in
> `Content/TechTree.luau`. Display names and lore may change freely before launch, never after (ids are permanent).
> Once a vehicle file exists, its `name` and `lore` are canonical and §4.3 is updated to match in the same commit.

---

## 0. Scope, conventions and the launch-wave arithmetic

### 0.1 Why the launch roster is 89 vehicles (≈ 84 target)

The decisions doc fixes three things that size the roster: **one Tier XI Apex per faction at launch** (§7.4), an
Apex is researched **on a Tier X** of its faction (§11), and every vehicle must be reachable from its faction's Tier I
root (`ContentRegistry.validate`). So each faction needs one complete I → X line (60 vehicles) plus 6 Apexes before
anything else exists. A pure 6 × 14 = 84 roster therefore leaves 18 nodes: one premium and two more per faction.

We spend them where players spend their time. With the §11 battle counts, Tiers VIII–X are 162 of the ≈ 260 battles
from Tier I to the first Apex (62 %) and IX–X alone are 47 %. So every faction gets a **second branch at IX–X**
(a cross-class split from its Tier VIII), which doubles launch Tier X variety to 12 vehicles. The one exception is
`desert_corps`, which instead carries the game's only launch **artillery line (IV–X)**, because §7.4 ships SPGs at
IV–X and an SPG line cannot be built from two nodes. Result:

| Faction | Tech tree I–X | Premium | Apex XI | Total | What the extra nodes buy |
|---|---|---|---|---|---|
| `iron_union` | 12 | 1 | 1 | **14** | MT IX–X brawler branch |
| `crown_industries` | 12 | 1 | 1 | **14** | TD IX–X precision branch |
| `eastern_armor` | 12 | 1 | 1 | **14** | Wheeled LT IX–X branch |
| `desert_corps` | 17 | 1 | 1 | **19** | SPG line IV–X (the +5 over 84) |
| `mountain_republic` | 12 | 1 | 1 | **14** | Siege TD IX–X branch |
| `northern_federation` | 12 | 1 | 1 | **14** | HT IX–X branch |
| **Total** | **77** | **6** | **6** | **89** | 12 Tier X, 6 Tier XI, 1 SPG line |

The **second branches are designed in full** as branches (identity, tier range, row, every future edge and its
unlocking module; §1, §2.11, §6.1) but their lower tiers ship later. Wave 1 (W1) ships the IX–X top of each second
branch, reached by a cross-class unlock from Tier VIII. Wave 2 (W2, one season ≈ 8 weeks later) or Wave 3 (W3, the
season after) ships the class-pure lower body, whose Tier VIII then also unlocks the same Tier IX, so no node is ever
orphaned or re-homed. The reserved W2/W3 slots and their priorities are in §6.1. Nothing in W1 is a dead end: every W1
tech-tree vehicle either unlocks another W1 vehicle or is a Tier X/XI.

### 0.2 Identifier and data conventions

| Item | Convention | Example |
|---|---|---|
| Vehicle id | `<faction prefix>_<name>` in snake_case, ASCII, permanent (`^[a-z][a-z0-9_]*$`, ≤ 48 chars, never encodes a tier; content-schema §1). A vehicle id never equals a branch id | `iu_tukkhald` |
| Vehicle file | `Content/Vehicles/<FactionPascal>/<PascalId>.luau` (content-schema §0) | `Vehicles/IronUnion/IuTukkhald.luau` |
| Faction prefix | `iu` Iron Union · `ci` Crown Industries · `ea` Eastern Armor Group · `dc` Desert Armor Corps · `mr` Mountain Republic · `nf` Northern Federation | |
| Class | `Types/Content.VehicleClass` ids `light` `medium` `heavy` `td` `artillery` (= brand §6.6 icon ids); tables abbreviate them LT, MT, HT, TD, SPG | `heavy` |
| Role id | `Types/Content.RoleId`, `<class>_<role>`: `light_scout` `light_support` `light_versatile` · `medium_assault` `medium_sniper` `medium_support` `medium_versatile` · `heavy_assault` `heavy_breakthrough` `heavy_support` `heavy_versatile` · `td_assault` `td_sniper` `td_support` `td_versatile` · `artillery_support` `artillery_area_control` | `heavy_assault` |
| Branch id | `<prefix>_<branch>` snake_case (`TechTree.luau`; content-schema §3.5). Tables below write the part after the prefix (`bulwark`) | `iu_bulwark` |
| Mechanic id | Gun reload kinds (`GunDefinition.reload.kind`): `Magazine` `Autoreloader` `DualGun`. Vehicle mechanics (`VehicleDefinition.mechanics`): `SiegeMode` `Hydropneumatic` `Wheeled`; Tier XI signatures `ChargedShot` `ActiveCooling` `Turbo` `RocketBoost` `AdaptiveMagazine`. `AdaptiveMagazine` rides on a `Magazine` gun, which is its carrier, not a second mechanic. Parameters: §2.10 | `DualGun` |
| Visual preset | `VisualSpec.preset` defaults to the faction `builderPreset` (one per faction, §1.x builder table). Silhouette features map to schema fields first; only what no field expresses is a `VisualSpec.hooks` key (§2.9) | `iu_foundry`, `{"twin_mantlet", "cheek_wedges"}` |
| Tree position | `tree = { row, branch }`; rows per faction in §2.11 (unique per faction + tier; premiums sit in the premium lane) | `{ row = 2, branch = "iu_bulwark" }` |
| Shell kit | Direct-fire guns carry three shells in this order (content-schema §4.3): **standard**, **special** and **HE**, with the families of the faction table below. "Premium = same family" in decisions §1 means a special round is one of the five ordinary families with more pen, never a sixth mechanic; it does **not** mean the special repeats the standard's family (the shipped Iron guns are AP + APCR + HE). Special: alpha = standard alpha, pen = 1.30 × standard pen. HE: alpha = 1.30 × standard alpha (capped by §5.2), pen = calibre ÷ 2. `crown_industries` VIII+ HT/TD replace HE with **HESH** (pen 1.6 × calibre; decisions §1). Declared howitzers (R15): standard HE (α ≤ 1.60 × the AP gun's α of that vehicle, pen calibre ÷ 2) + special HEAT (α and pen = the AP gun's standard α and 1.30 × its pen), two shells only. SPG guns: standard HE and a special HE (pen ×1.30), no kinetic round. Every direct-fire shell obeys the per-tier alpha cap of §5.2 | `iu_45mm_ap`, `iu_45mm_apcr`, `iu_45mm_he` |

**Shell families per faction** (O: each family's decisions §1 behaviour fits the faction's fighting distance; velocity
APCR 1.25 × and HEAT 0.85 × the gun's AP-equivalent muzzle velocity, AP and APCR pen fall off linearly from 100 m to
×0.90 / ×0.75 at 500 m, HEAT keeps its pen but loses it to spaced armor):

| Faction | Standard | Special | Third | Why |
|---|---|---|---|---|
| `iron_union` | AP | APCR | HE | Corner trades under 150 m: AP's 5° normalisation; APCR's faster shell for the last-second snap |
| `crown_industries` | AP | HEAT | HE (HESH on VIII+ HT/TD) | Hull-down duels at 300 m+: HEAT keeps its pen at range; HESH for thin and flat plates |
| `eastern_armor` | APCR | HEAT | HE | Flank shots on the move under 250 m: the fastest standard shell is the easiest to lead |
| `desert_corps` | AP | HEAT | HE | Long sightlines: AP loses only 10 % by 500 m, HEAT none |
| `mountain_republic` | APCR (LT, MT) · AP (siege TD) | HEAT | HE | Crest peeks of a second or two: a fast shell lands before the target reacts; the siege snipers shoot at 400 m+, where AP keeps ≥ 90 % |
| `northern_federation` | AP | APCR | HE | Frontal attrition at short range, like Iron |

In the tables, roles are written without the class prefix (the class column supplies it). "P" marks a premium.
★ marks a Tier XI Apex. Tiers are always roman numerals (brand §2).

### 0.3 Research rules this roster obeys (from decisions §7.4 and §11)

* **Unlock costs** are per tier, not per vehicle: research XP II 350 · III 750 · IV 1,550 · V 3,000 · VI 5,200 ·
  VII 8,600 · VIII 13,500 · IX 21,000 · X 31,000 · XI 47,000 (on the parent X) and the §11 credit prices.
  Cross-class unlocks cost the same as same-class ones.
* **Modules:** Gun, Turret (only where meaningful), Engine, Tracks; no radio. Upgrades: II–III 1–2, IV–IX 2–4,
  X arrives elite, XI uses the 10-node track. Order Tracks → Turret → Gun; stock ≈ 85 % effectiveness.
* **Next vehicle hangs off the top gun** unless the roster table names another module (cross-class splits usually
  hang off the engine or the top turret, because the receiving class uses a different gun family). `requires` must
  be a module of the parent (content-schema §5.4); the hull is not a module.
* **Premiums** sit outside the lines (store, Bullion: V 1,000 · VI 1,600 · VIII 3,500), earn credits ×1.35 (V–VI) or
  ×1.5 (VIII) and crew XP ×1.5, accept any crew of the same faction **and** class, and get no preferential MM.
* **Special mechanics** are capped at 20 % of the Tier I–X roster. W1 uses **15 of 83 (18.1 %)**: DualGun 3,
  Magazine 2, Wheeled 2, Autoreloader 3, Hydropneumatic 3, SiegeMode 2. W2 must keep the ratio (§6.1).

### 0.4 World frame (shared lore canon)

The game's world is the **Concord Reach**, a continent whose six great powers signed the **Ridge Accord**: disputes
over water, rail and passes are settled by sanctioned armored contests called the **Trials**, fought on cleared
proving fields under neutral **Marshals**. Crews are drilled, armored and recovered; the Accord's first article is
that every crew comes home (decisions §2: crews are injured, never killed). Each faction's engineering culture
comes from its land, and the lore always explains a vehicle by **the problem its makers were solving**, never by a
real war, nation or politician. Places used in lore: the **Cinderbelt** (Iron Union foundry valleys), the **Gilt
Coast** guild cities (Crown Industries), the **Long Grass** plains (Eastern Armor Group), the **Amberline Erg**
(Desert Armor Corps), the **High Cantons** (Mountain Republic), the **Rime Coast** and **Pale Reaches** (Northern
Federation), and the neutral **Marshal's Fields** where the Trials are held.

Tone (brand §2): calm, specific, a little proud of the engineering. No gore, no real conflicts, no memes. Verbs:
"destroyed", "disabled", "spotted". Lore never mentions real calibres as real-world designations; calibres may be
stated as plain numbers ("a 105 mm gun") because they are data, not names.

### 0.5 The launch tree at a glance

| Faction | Spine (complete I–X line) | Second branch (W1 top) | Premium | Apex XI (signature) |
|---|---|---|---|---|
| Iron Union | MT I–III → **HT IV–X** (DualGun VIII–X) | MT IX–X brawlers | `iu_tammvarr` TD VIII | `iu_gorrtund` HT, ChargedShot (+10 % damage) |
| Crown Industries | LT I–II → MT III–IV → **HT V–X** (HESH VIII+) | TD IX–X snipers (HESH) | `ci_calibine` TD VI | `ci_aurelline` TD, ActiveCooling |
| Eastern Armor Group | **LT I–X** (Magazine IX–X) | Wheeled LT IX–X | `ea_sevzar` LT V | `ea_lirvesh` LT, AdaptiveMagazine |
| Desert Armor Corps | MT I–III → **MT IV–X** (Autoreloader VIII–X) | SPG IV–X (from MT III) | `dc_dunelight` MT VIII | `dc_zenith` MT, ChargedShot (dispersion ×0.6) |
| Mountain Republic | LT I–III → **MT IV–X** (Hydropneumatic VIII–X) | Siege TD IX–X | `mr_highstag` LT VIII | `mr_updraft` MT, RocketBoost |
| Northern Federation | MT I → **TD II–X** (assault casemates) | HT IX–X | `nf_thawbreaker` HT VIII | `nf_rimeburst` HT, active Turbo |

Apex classes: HT 2, MT 2, TD 1, LT 1 (WoT 2.0 launched 7/5/3/1; we keep one of each non-SPG class and lean
heavy/medium like it). No SPG at XI (decisions §7.4).

---

## 1. Factions

Every faction section has the same parts: identity and doctrine, design language and builder preset, stat profile
(the decisions §7.3 kit plus what it means per class), strengths and weaknesses, branches, the W1 tree, and the
progression arc of each branch. Faction kits multiply on top of class × role (decisions §7.1–7.3) and are inside
the lint baseline, so a kit never counts as a balance exception.

**Shared builder rules (all factions).** Silhouettes are chunky, chamfered and honest (brand §1): no soft blobs,
45° chamfers on every hull edge visible in profile, side profile with the gun to the right for tech-tree art
(brand §6.3). Budgets (decisions §18): LOD0 ≤ 400 parts, LOD1 ≤ 80, LOD2 ≤ 16, ≤ 4 materials per vehicle (a Neon
glow part, e.g. `heater_stacks`, counts as one of the four). Every "visual hook" cell in §2 leads with a feature
that survives at LOD2: a *silhouette* feature (turret position, hull length and nose shape, gun length or furniture,
casemate shape, the wheels of a wheeled vehicle), never a decal. Details named after it (road-wheel counts of
tracked vehicles, rivets, hoods, tools, stowage) are LOD0/LOD1 only, as §2.9 marks them. The Blueprint spends the 16
LOD2 parts like this:

| LOD2 group | Tracked | Wheeled |
|---|---|---|
| Hull (body, glacis or nose wedge, superstructure or skirt slab) | 3 | 2 |
| Turret or casemate (body, mantlet, bustle or cupola) | 3 | 2 |
| Gun (barrel, muzzle device; a DualGun's second barrel) | 2 | 1 |
| Running gear | 2 track blocks | 8 wheel cylinders |
| Signature hooks (pike nose ridge, drum bulge, recoil spades, rocket pods, open-top frame …) | ≤ 3 | ≤ 2 |
| Reserve | 3 | 1 |

**Vehicle paint** is a muted field colour per
faction (below) with the faction **enamel** (brand §3.7 primary) only on a turret band or hatch ring (≤ 5 % of the
visible area) and the faction emblem decal; team identity never goes on the paint (brand §10). The `paint.*` hexes
below are a proposal to the brand owner for a brand §3.7 extension and must pass `check_palette.py` before use; they
are already mirrored in `Factions.luau` `vehiclePaint` (`base` = field, `accent` = enamel, `secondary` = trim).

| Faction | `paint.<id>.field` (proposal) | Enamel band | Trim metal |
|---|---|---|---|
| Iron Union | `#5B4C43` iron-oxide grey | `#B8492A` rust | gunmetal `#59616A` |
| Crown Industries | `#4A4553` plum slate | `#5A3D8C` royal purple | brass `#D6AA4E` |
| Eastern Armor Group | `#3F5553` sea-grass grey | `#1C8582` teal | bone `#E9DFC6` |
| Desert Armor Corps | `#A38C63` dune khaki | `#C8933A` ochre | umber `#7A5530` |
| Mountain Republic | `#495B4C` lichen green | `#3C7650` pine | snow `#F2F5F7` |
| Northern Federation | `#7D8A94` frost grey | `#4F8FCB` glacier | ice white `#EEF6FC` |

### 1.1 IRON UNION (`iron_union`) — industry and armor

**Identity.** The Union of Forges is a federation of foundry towns along the Cinderbelt, where whole valleys glow at
night. Its engineers trust mass, casting and rivets, and they build vehicles the way they build furnaces: thick,
simple and hard to stop. Emblem: an anvil on rust enamel inside a gear (brand §6.6).

**Doctrine: "hold the line, hit hardest."** Iron Union crews take the heavy lane and win the first exchange. Big
alpha decides corner trades; strong turrets absorb return fire on flat ground. They are poor at ridge fighting
(−5° depression), so they fight in towns, in hollows and on open flats, and they advance as a wall.

**Design language and builder preset `iu_foundry`**

| Part | Rule (silhouette first, survives at LOD2) |
|---|---|
| Hull | Low and wide (width ÷ height ≥ 1.6). I–VI: riveted boxes with flat, stepped or plain sloped fronts (`hull.style` `Boxy` / `Stepped` / `Sloped`; `iu_bulmal` ships `Sloped`); VII+: **pike-nose prow**, two wedges meeting on a centre ridge (`Pike`). Side-skirt slabs from V (`skirts = "Plates"`) |
| Turret | **Faceted dome** (`FacetedDome`): octagonal prism + corner wedges, low, centred or slightly forward; heavy block mantlet; no bustle, so Iron ammo never sits in the turret rear. Exception: the IV–V heavies carry welded **box** turrets (`Box`) cut from boiler plate; the cast dome returns on the heavies at VI |
| Gun | Short-to-medium, thick barrel, **double-baffle muzzle brake** (`muzzleBrake = "Double"`) on every gun from II (Tier I guns: `None`). DualGun = two barrels side by side in one wide mantlet (`twin_mantlet`) |
| Running gear | 4–6 **large** road wheels (4 at I), **no return rollers** (`returnRollers = 0` + `sagging_track`), rear exhaust stacks |
| Detail kit | Rivet rows (LOD0 only), tow cables, spare track links on the glacis |
| Engine family | Diesel (engine fire chance 12 %, decisions §2) |

**Stat profile (kit, decisions §7.3):** alpha ×1.10, reload ×1.10 (DPM neutral), turret armor ×1.10, dispersion
×1.06, aim time ×1.05, gun depression **−5°** (default −8°).

| Class at Tier X (class × role × kit) | HP | Alpha | Reload | DPM | Pen | Notes |
|---|---|---|---|---|---|---|
| HT Assault (`iu_durhald`, DualGun) | 2,340 | 550 per barrel | 30.5 s per barrel | ≈ 2,160 (0.87 × class) | 263 | volley 1,100; turret clamp 1.45 P (§5.5 R3) |
| MT Assault (`iu_brakkmal`) | 2,048 | 440 | 10.5 s | 2,526 | 255 | hull ×1.15, turret ×1.10 ×1.15 |
| TD Versatile (`iu_tammvarr`, VIII P; target → premium, §2.8) | 1,148 | 386 → 374 | 12.76 → 12.88 s | 1,815 → 1,742 | 230 → 221 | 360° turret (α ×0.9); the only Iron TD in W1 |

* **Strengths:** highest alpha per shot of any faction; heavy turret faces (1.27–1.45 P after kit and clamp) bounce
  same-tier HT and most TD standard rounds; diesel fires are rare; wins most trades under 150 m.
* **Weaknesses:** −5° means no ridge play; worst accuracy and slowest aim, so poor beyond 300 m; long reload windows
  (13–30 s at X) are punished by flankers; the Foundry trunk is unhurried (the Ostmal's Assault trim is ×0.92
  speed, and no Iron vehicle has a speed bonus to escape a bad position).
* **Intended counterplay:** shoot lower plates and cupolas, bait a shot then push inside the reload, or fight them
  on a crest they cannot depress over.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `iu_foundry` | Foundry trunk | MT | I–III | I–III | Slow, sturdy starter mediums that teach "angle and trade" |
| `iu_bulwark` | Bulwark heavy line | HT | IV–X → XI | IV–X | The spine: from riveted box to pike-nose to twin-gun wall |
| `iu_hammer` | Hammer brawler mediums | MT | IX–X | IV–X (IV–VIII in W3) | Turret-strong, high-alpha mediums that fight like light heavies |
| `iu_ram` | Ram destroyer line | TD | premium VIII only | IV–X (W2) | Rear-casemate, very high alpha, poor arcs |

Splits and merges: Foundry III splits to Bulwark IV (top gun) and, in W2, Ram IV (top engine). Bulwark VIII splits
to Hammer IX through its top engine (W1). In W3 the Hammer lower body (IV–VIII) branches from Foundry III (top
turret) and **merges** into the existing Hammer IX (Hammer IX gets two parents). The premium `iu_tammvarr` trains TD
crews for W2.

```
I            II           III          IV            V               VI             VII             VIII             IX              X              XI
iu_kolmal → iu_ostmal → iu_bulmal → iu_osthald → iu_brakkhald → iu_kolhald → iu_varrhald → iu_tukkhald² → iu_tukktund² → iu_durhald² → iu_gorrtund★
  MT          MT          MT          HT            HT              HT             HT              HT        │       HT              HT             HT
                                                                                                            └(engine)→ iu_tundmal → iu_brakkmal
                                                                                                                        MT            MT
Store: iu_tammvarr (TD VIII, P)                                                     ² DualGun   ★ ChargedShot
```

**Progression arc: Bulwark (HT).** Each step adds a new verb, not just numbers.
* **IV `iu_osthald` (Versatile):** first heavy; tall riveted box with a flat front and a welded box turret. Lesson:
  *you are the wall, so show the front and never the side.*
* **V `iu_brakkhald` (Assault):** thick slab front, very slow. Its two top guns are the first real choice: a long AP
  gun or a stubby high-explosive howitzer (per-gun override: HE alpha ×1.6 of the AP gun, reload ×1.35). Lesson:
  *alpha against reliability.*
* **VI `iu_kolhald` (Support):** the first heavy with a cast faceted dome (the Foundry mediums had small ones) and a
  long, comparatively accurate gun; −7° (kit −5°, role +2°), the only Iron heavy that can use small bumps. Lesson:
  *turret first.*
* **VII `iu_varrhald` (Breakthrough):** the pike-nose prow appears; +15 % speed and power. Lesson: *angle by
  geometry, lead the push.*
* **VIII `iu_tukkhald` (Versatile, DualGun):** two barrels. Lesson: *single shots to poke, the volley to commit.*
* **IX `iu_tukktund` (Assault, DualGun):** heavier dome, side skirts; the volley is a corner-trade weapon.
* **X `iu_durhald` (Assault, DualGun):** the full wall: three quarters of the turret face at the 1.45 P clamp (the
  R3 maximum), 2 × 550 volley delivered in 1.5 s, the most damage any Tier X lands in that time.
* **XI `iu_gorrtund` (Assault, ChargedShot +10 % damage):** gives up the twin burst for one enormous charged shot.

**Progression arc: Hammer (MT).** IX `iu_tundmal` (Versatile) is a heavy's gun and turret on a medium hull;
X `iu_brakkmal` (Assault) has the strongest medium turret in the game, bought with the worst depression of any
medium. Both teach "medium speed, heavy manners".

**Progression arc: Foundry trunk (MT).** I `iu_kolmal` (Versatile) is a forgiving tractor-chassis tank whose
riveted front, angled 30° or more, bounces most Tier I standard rounds (it sits inside the same starter envelope as
the other five Tier I vehicles, §3.4 rule 7). II `iu_ostmal` (Assault) introduces a short high-alpha gun. III
`iu_bulmal` (Versatile) carries the Union's first one-piece cast dome (`FacetedDome` top turret), the first turret
that bounces shots: a preview of the heavy line.

### 1.2 CROWN INDUSTRIES (`crown_industries`) — precision

**Identity.** Crown Industries is a chartered manufacturing house of the Gilt Coast guild cities, run by a
hereditary board whose seal is the crown. It builds vehicles like instruments: measured tolerances, superb optics,
guns bored and lapped by hand. Emblem: a brass crown with a purple cog jewel (brand §6.6).

**Doctrine: "shoot first, shoot straight, shoot from cover."** Crown crews take ridges and hull-down positions
(−10° depression) and win by accuracy and steady fire rather than big hits. From Tier VIII its heavies and
destroyers carry **HESH**: pen 1.6 × calibre, never ricochets and deals ×1.15 non-pen damage, so it wrecks thin and
flat plates and anything a bad angle would bounce AP off; skirts and spaced armor smother it (3T per screen,
decisions §1), which is when the AP round comes back out.

**Design language and builder preset `ci_guild`**

| Part | Rule |
|---|---|
| Hull | **Tall and upright**: slab sides, a steep flat front, full-length stowage bins on the track guards |
| Turret | **Box turret with a long rear bustle**, flat faces, wide flat mantlet, set high (this is where the depression comes from); brass periscope hoods |
| Gun | Long and slim with a **bore evacuator** (a short cylinder at ≈ 60 % of the barrel length) on every gun from III; small or no muzzle brake |
| Running gear | 6–7 medium road wheels, 3 return rollers per side, high track run |
| Detail kit | Brass trim on hatches and periscopes (`brass` material), tool racks on the bins |
| Engine family | Petrol (engine fire chance 20 %) |

**Stat profile (kit):** dispersion ×0.93, aim time ×0.94, alpha ×0.92, reload ×0.92 (DPM neutral), depression
**−10°**. Shell kit: VIII+ HT and TD replace HE with HESH (pen 1.6 × calibre, non-pen damage ×1.15, never
ricochets; decisions §1).

| Class at Tier X | HP | Alpha | Reload | DPM | Pen | Notes |
|---|---|---|---|---|---|---|
| HT Support (`ci_tesselion`) | 2,340 | 460 | 11.1 s | 2,486 | 276 | dispersion ≈ 0.33, −12°, armor ×0.85 |
| TD Sniper (`ci_vernine`) | 1,658 | 580 | 12.7 s | ≈ 2,740 | 301 | dispersion ≈ 0.26 (0.34 × 0.92 × 0.9 × 0.93), casemate ≤ 0.45 P |
| TD Sniper Apex (`ci_aurelline`, XI) | 1,870 | 638 | 13.1 s | ≈ 2,930 | 325 | ActiveCooling: reload and aim ×0.85 for 5 s |

* **Strengths:** the best accuracy and aim in the game; ridge and hull-down fighting; high sustained DPM; HESH
  punishes thin or flat armor and light vehicles and never bounces.
* **Weaknesses:** tall silhouettes are easy to hit; low alpha loses corner trades; petrol engines burn; on every
  turreted Crown vehicle the **ammunition rack sits in the turret bustle** (`layout.ammoRacks = {"Bustle"}`), so
  rear-turret hits risk detonation. Vernier casemates have no bustle; their racks sit in the hull sides
  (`"Sponsons"`), behind side plates only ≈ 0.2–0.3 P thick.
* **Intended counterplay:** close the distance, force short brawls, shoot the bustle or a casemate's flank, set
  fires.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `ci_guild` | Guild trunk | LT → MT | I–IV | I–IV | Precision from the first battle |
| `ci_warden` | Warden heavy line | HT | V–X | V–X | Hull-down heavies; HESH from VIII |
| `ci_vernier` | Vernier destroyer line | TD | IX–X → XI | IV–X (IV–VIII in W2) | Low precision casemates with HESH |
| `ci_herald` | Herald light line | LT | — | V–X (W3) | Fast, accurate scouts with poor alpha |

Splits and merges: Guild II (LT) → Guild III (MT) is a class switch inside the trunk. Guild IV → Warden V (top gun).
Warden VIII → Vernier IX (the HESH gun carries over). In W2 the Vernier lower body branches from Guild III and its
Tier VIII also unlocks Vernier IX (merge). The premium `ci_calibine` (TD VI) trains Vernier crews.

```
I             II            III          IV              V             VI            VII           VIII            IX             X               XI
ci_vernelle → ci_gardelle → ci_ordant → ci_calibrant → ci_gardion → ci_sterion → ci_ordion → ci_regnion → ci_sovrion → ci_tesselion
  LT            LT            MT          MT              HT            HT            HT            HT     │       HT             HT
                                                                                                         └(gun)→ ci_precine → ci_vernine → ci_aurelline★
                                                                                                                  TD            TD            TD
Store: ci_calibine (TD VI, P)                                                           HESH: VIII+ HT/TD   ★ ActiveCooling
```

**Progression arc: Warden (HT).**
* **V `ci_gardion` (Breakthrough):** the first Crown heavy is fast and thin, a heavy gun on a quick hull. Lesson:
  *Crown heavies win with the gun, not the plate.*
* **VI `ci_sterion` (Versatile):** the tall box turret debuts with −10°. Lesson: *find a crest before you shoot.*
* **VII `ci_ordion` (Support):** long-bustle turret, best heavy accuracy at VII, −12°. Lesson: *second-line fire
  that keeps the push alive.*
* **VIII `ci_regnion` (Support, HESH):** HESH arrives. Lesson: *pick the shell for the plate*: HESH on thin or flat
  plates, AP on thick, sloped or spaced armor.
* **IX `ci_sovrion` (Versatile, HESH):** longer hull, skirts, a turret (1.15–1.35 P) thick enough to hold a ridge
  against Tier IX MT and HT standard rounds while hull-down; TD rounds (1.18 P) still beat its lower half.
* **X `ci_tesselion` (Support, HESH):** the most accurate heavy in the game. Its turret is only medium-thick
  (×0.85: 0.98–1.15 P), so it peeks, shoots and hides.

**Progression arc: Vernier (TD).** IX `ci_precine` (Sniper) is a low front casemate with a ±12° yaw arc and HESH as
its third round (after AP and HEAT); X `ci_vernine` (Sniper) adds the longest gun in the faction and the best dispersion of any
Tier X; XI `ci_aurelline` adds ActiveCooling, so it can win a 5-second firefight it would normally lose.

**Progression arc: Guild trunk.** I `ci_vernelle` (LT Versatile) has an unusually accurate small gun. II
`ci_gardelle` (LT Scout) has a tall periscope mast (view range +10 m). III `ci_ordant` (MT Sniper) is the first
−10° hull-down medium. IV `ci_calibrant` (MT Support) fires quickly and teaches sustained DPM before the heavies.

### 1.3 EASTERN ARMOR GROUP (`eastern_armor`) — mobility and alpha strike

**Identity.** The Eastern Armor Group is a consortium of clan workshops on the Long Grass, plains so wide that a
convoy can drive for a day without seeing a hill. Distance shaped everything: vehicles are light, fast and built to
be repaired from a toolbox. Emblem: a bone spearhead rising from teal wings (brand §6.6).

**Doctrine: "see first, strike fast, be gone."** Eastern crews spot, flank and burst. From Tier IX their lights
carry magazines that empty a clip into a distracted target and then vanish; their wheeled outriders reposition
faster than anything else on the field. They never trade shots face to face.

**Design language and builder preset `ea_windward`**

| Part | Rule |
|---|---|
| Hull | **Long, narrow and low** (length ÷ width ≥ 1.9), one sharp wedge nose, engine at the rear, flared wing-like mudguards |
| Turret | Small, all-round sloped wedge turret **set forward**; magazine vehicles add a **drum bulge** across the turret rear |
| Gun | Long, slim barrel with a **slotted cylindrical muzzle brake** (ring details) |
| Running gear | Tracked: 4–5 large, widely spaced road wheels, no skirts. Wheeled: **4 wheels per side** with visible axle hubs and a raised, boat-shaped hull |
| Detail kit | Bone-trim hatch rings, quick-release stowage nets |
| Engine family | Petrol (fire 20 %) |

**Stat profile (kit):** power-to-weight ×1.10, top speed ×1.06, turret armor ×0.80.

| Class at Tier X | HP | Alpha | Reload | DPM | Speed | Notes |
|---|---|---|---|---|---|---|
| LT Versatile, Magazine (`ea_talzarett`) | 1,560 | 340 × 3 | 1.8 s intra, 28.3 s magazine | 1,921 sustained (0.85) | 70 km/h | burst 1,020 in 3.6 s |
| LT Scout, Wheeled (`ea_lirvari`) | 1,560 | 306 | 9.0 s | ≈ 2,030 | 70 / **91** km/h speed mode | camo +0.03, view range +10 m |
| LT Support Apex (`ea_lirvesh`, XI) | 1,760 | 393 × 4 | 2.2 s intra, 37.3 s full magazine | ≈ 2,150 sustained | 67 km/h | AdaptiveMagazine (§2.7) |

* **Strengths:** the best acceleration in every bracket (power-to-weight ×1.10 on the light class's ×1.6); the
  fastest vehicles in the game (Wheeled speed mode, 91 km/h); the most scouts at VIII–X; burst damage that can
  delete a damaged vehicle; the wheeled outriders cross a 1 km map in ≈ 45 s on hard ground.
* **Weaknesses:** paper turrets (×0.80) make hull-down impossible; long magazine reloads leave them helpless for
  28–33 s; petrol fires; top speed only ×1.06 (Mountain lights are faster on a straight); a wheeled vehicle loses
  25 % top speed per destroyed wheel side (each side's four wheels are one `TrackLeft`/`TrackRight` module; both
  sides down = ×0.56, never immobile; content-schema §5.5).
* **Intended counterplay:** track the tracked ones, shoot the wheel sides of the wheeled ones, count their shells and push while the magazine is empty
  (3 shells at X, 4 at IX), deny bush lines with your own scouts.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `ea_skirmish` | Skirmish light line | LT | I–X → XI | I–X | The spine: scouts and flankers, Magazine at IX–X |
| `ea_outrider` | Outrider wheeled line | LT (Wheeled) | IX–X | VII–X (VII–VIII in W2) | The fastest vehicles in the game: information, not trades |
| `ea_gale` | Gale medium line | MT | — | V–X (W2) | Fast, thin, high-alpha single-shot mediums (no mechanic: Magazine stays on one branch per faction, roster rule R9) |

Splits and merges: Skirmish VIII → Outrider IX through the engine (the wheeled hull reuses the engine). In W2 the
Outrider lower body branches from Skirmish VI and its VIII also unlocks Outrider IX (merge); Gale branches from
Skirmish IV (class switch LT → MT). Premium `ea_sevzar` trains LT crews for the spine.

```
I           II          III          IV          V           VI          VII          VIII         IX            X               XI
ea_kirett → ea_essett → ea_veshett → ea_talett → ea_sevett → ea_venett → ea_lirett → ea_silett → ea_zarett ᴹ → ea_talzarett ᴹ → ea_lirvesh★
  LT          LT          LT           LT          LT          LT          LT           LT    │      LT              LT               LT
                                                                                              └(engine)→ ea_rhuvari ᵂ → ea_lirvari ᵂ
                                                                                                         LT             LT
Store: ea_sevzar (LT V, P)                                       ᴹ Magazine   ᵂ Wheeled   ★ AdaptiveMagazine
```

**Progression arc: Skirmish (LT).**
* **I `ea_kirett` (Versatile):** tiny and quick, with a choice of a fast-firing or a harder-hitting gun.
* **II `ea_essett` (Scout):** the lowest silhouette at Tier II. Lesson: *passive spotting from a bush.*
* **III `ea_veshett` (Scout):** faster, turret moved forward. Lesson: *active spotting: show, then break contact.*
* **IV `ea_talett` (Support):** the biggest gun on any Tier IV light. Lesson: *a light can deal damage from a flank.*
* **V `ea_sevett` (Versatile):** first Eastern light to reach 60+ km/h with a fast turret. Lesson: *circle and
  track.*
* **VI `ea_venett` (Scout):** long, very low hull, best light camouflage at VI. Lesson: *view range and patience.*
* **VII `ea_lirett` (Support):** a high-penetration gun on a fast hull. Lesson: *flank damage without being seen.*
* **VIII `ea_silett` (Scout):** the fastest tech-tree tracked light at VIII (70 km/h) and the quickest to get there
  (≈ 32 hp/t). Lesson: *win the first 60 seconds of map control.*
* **IX `ea_zarett` (Support, Magazine 4):** 4 × 286 alpha (Support ×1.05), 2.0 s apart. Lesson: *burst, then
  disappear.*
* **X `ea_talzarett` (Versatile, Magazine 3):** fewer, harder shells with a quicker intra-clip (1.8 s). Lesson: *pick
  the moment; a wasted clip is 28 seconds of uselessness.*
* **XI `ea_lirvesh` (Support, AdaptiveMagazine):** the magazine can be topped off at any time for part of the
  reload, so a half-spent drum is never a forced 37-second wait.

**Progression arc: Outrider (Wheeled LT).** IX `ea_rhuvari` (Versatile) teaches the speed-mode toggle as a
relocation tool (cruise to fight, speed mode to move). X `ea_lirvari` (Scout) is the fastest vehicle in the game and
the best spotter at Tier X, with the weakest gun of any Tier X: it wins by information and harassment.

### 1.4 DESERT ARMOR CORPS (`desert_corps`) — long range

**Identity.** The Desert Armor Corps is the standing force of the caravan cities that cross the Amberline Erg.
Every Corps officer is a navigator first; their sightlines run to the horizon, so their guns are built to reach it.
They also field the only artillery at launch: the Sunfall batteries. Emblem: a compass-sun over two dunes (brand
§6.6; the rays are wedges, never a ray field).

**Doctrine: "own the long sightline."** Desert crews sit hull-down on dune crests (−10°), aim fast and hit at
400 m. Their turrets are strong (×1.08) and their lower plates weak (×0.85), so they fight from cover and avoid
cresting into close range. Autoreloaders from Tier VIII give them a two- or three-shell burst from a hull-down spot.

**Design language and builder preset `dc_caravan`**

| Part | Rule |
|---|---|
| Hull | Long, medium height, **full sand skirts** hiding the upper track run (flat slab), forward-sloped upper glacis above a **tall, flat lower plate** (the weak spot reads in silhouette) |
| Turret | Elongated hexagonal prism, mid-mounted, with a **tall commander cupola**; autoreloaders add a boxy magazine bustle |
| Gun | Long, thin, with 1–4 **thermal-sleeve bands** (count set by barrel length, §2.9) and a small single-baffle brake |
| Running gear | 5–6 road wheels behind the skirts, raised front idler |
| Detail kit | Jerrycan racks, mesh stowage baskets, a sunshade canopy frame on I–III |
| SPG family | Open-top howitzer carriage (IV–VI) → half-enclosed fighting compartment (VII–VIII) → fully enclosed turret with rear recoil spades (IX–X); barrel length grows each tier |
| Engine family | Diesel (fire 12 %) |

**Stat profile (kit):** aim time ×0.94, reload ×0.95 (DPM ×1.05), turret armor ×1.08, lower plate ×0.85,
depression **−10°**.

| Class at Tier X | HP | Alpha | Reload / magazine | DPM | Pen | Notes |
|---|---|---|---|---|---|---|
| MT Sniper, Autoreloader (`dc_sunward`) | 1,950 | 400 × 3 | refills 12.5 / 9.4 / 9.0 s, 2.0 s intra | ≈ 2,330 sustained (0.92) | 273 | aim 2.07 s, dispersion ≈ 0.31 |
| SPG Support (`dc_noonfall`) | 585 | 800 HE | 36.1 s | ≈ 1,330 | 64 | splash 7.65 m (155 mm), stun ≤ 16 s, direct hit ≤ 877 |
| MT Sniper Apex (`dc_zenith`, XI) | 2,200 | 440 | 9.8 s | ≈ 2,700 | 294 | ChargedShot: 1.5 s charge, dispersion ×0.6 |

* **Strengths:** long-range accuracy and fast aim; strong hull-down turrets; the best DPM kit; artillery support.
* **Weaknesses:** weak lower plates and tall cupolas punish any crest-to-crest duel at close range; the
  autoreloader's first refill after emptying is the longest (12.5 s at X); artillery is fragile and reveals itself
  for 5 s after each shot (decisions §7.4).
* **Intended counterplay:** flank or close in so they must crest; shoot the lower plate the moment they climb;
  hunt the SPG from its minimap ring.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `dc_caravan` | Caravan trunk | MT | I–III | I–III | Quick-aiming starter mediums |
| `dc_longshot` | Longshot medium line | MT | IV–X → XI | IV–X | The spine: hull-down long-range mediums, Autoreloader VIII–X |
| `dc_sunfall` | Sunfall artillery line | SPG | IV–X | IV–X | The launch artillery: alternating stun Support and AreaControl roles |
| `dc_glint` | Glint destroyer line | TD | — | V–X (W2) | Autoreloader casemates (decisions §7.3 signature "Autoreloader MT/TD") |

Splits and merges: Caravan III splits to Longshot IV (top gun) and Sunfall IV (engine; the SPG reuses the
caravan chassis). W2: Glint V branches from Longshot IV (class switch MT → TD). Premium `dc_dunelight` (MT VIII)
trains Longshot crews.

```
I            II           III             IV            V            VI            VII            VIII           IX            X             XI
dc_waymark → dc_bearing → dc_sandglass → dc_parallax → dc_azimuth → dc_meridian → dc_longsight → dc_sextant ᴬ → dc_dawnfix ᴬ → dc_sunward ᴬ → dc_zenith★
  MT           MT           MT      │        MT            MT           MT            MT             MT             MT            MT            MT
                                    └(engine)→ dc_dustfall → dc_ashfall → dc_sparkfall → dc_glassfall → dc_flarefall → dc_dewfall → dc_noonfall
                                                 SPG           SPG          SPG            SPG            SPG            SPG           SPG
Store: dc_dunelight (MT VIII, P)                                                 ᴬ Autoreloader   ★ ChargedShot (dispersion)
```

**Progression arc: Longshot (MT).**
* **IV `dc_parallax` (Versatile):** first tall-cupola turret with −10°. Lesson: *a dune crest is armor.*
* **V `dc_azimuth` (Sniper):** a long gun, sniper dispersion (×0.9) and the fastest aim of any Tier V medium
  (×0.94). Lesson: *shoot at 300 m+.*
* **VI `dc_meridian` (Assault):** thicker turret (Assault ×1.15 on the ×1.08 kit). Lesson: *hold a ridge under
  fire, not just snipe from it.*
* **VII `dc_longsight` (Sniper):** best Tier VII medium dispersion and +10 m view range. Lesson: *spot for yourself.*
* **VIII `dc_sextant` (Versatile, Autoreloader 2):** the double tap. Lesson: *peek, fire twice, drop back.*
* **IX `dc_dawnfix` (Assault, Autoreloader 3):** three shells from the strongest hull-down turret in the faction.
  Lesson: *burst from cover, then manage the long first refill.*
* **X `dc_sunward` (Sniper, Autoreloader 3):** the flagship long-range medium.
* **XI `dc_zenith` (Sniper, ChargedShot):** single gun; hold fire 1.5 s to tighten dispersion ×0.6 (≈ 0.18 m at
  100 m, ≈ 0.9 m at 500 m).

**Progression arc: Sunfall (SPG).** Roles alternate so each tier asks for a different habit:
* **IV `dc_dustfall` (AreaControl):** open-top light howitzer, no stun (decisions: stun from V). Lesson: *arcs and
  ≥ 2.5 s flight time.*
* **V `dc_ashfall` (Support):** first stun (6 s). Lesson: *stun the push your team is fighting.*
* **VI `dc_sparkfall` (AreaControl):** fast light carriage, small splash, quicker reload (AreaControl ×0.90).
  Lesson: *move after every shot; your minimap ring gives you away for 5 s.*
* **VII `dc_glassfall` (Support):** heavy howitzer, big splash. Lesson: *stun groups at chokepoints.*
* **VIII `dc_flarefall` (AreaControl):** long gun-howitzer: flatter arc, faster shell (×1.15), smaller splash; the
  most reliable direct hits in the line. Lesson: *lead moving targets.*
* **IX `dc_dewfall` (Support):** enclosed 360° turret. Lesson: *cover two lanes without moving.*
* **X `dc_noonfall` (Support):** the flagship howitzer, slow and enclosed, 16 s maximum stun.

**Sunfall gun table** (authoring targets; SPG class ×2.0 HE alpha, ×4.0 reload, Desert reload ×0.95, role trims of
§2.4; splash R = 3 + 0.03 × calibre m, decisions §7.4; direct-hit damage clamped to 0.45 × same-tier MT HP; stun
maximum from `Tiers.luau`, ×0.5 at the splash edge; every shell flies ≥ 2.5 s):

| Tier | Vehicle | Role | Calibre | HE α | HE pen | Reload | Splash R | Direct-hit clamp | Stun max | Shell velocity |
|---|---|---|---|---|---|---|---|---|---|---|
| IV | `dc_dustfall` | AreaControl | 105 mm | 170 | 21 mm | 11.6 s | 5.2 m | 238 | 0 s | ×1.15 |
| V | `dc_ashfall` | Support | 120 mm | 230 | 25 mm | 16.0 s | 6.6 m | 288 | 6 s | ×1.0 |
| VI | `dc_sparkfall` | AreaControl | 105 mm | 320 | 33 mm | 19.2 s | 5.2 m | 369 | 4 s | ×1.15 |
| VII | `dc_glassfall` | Support | 155 mm | 440 | 40 mm | 28.1 s | 7.65 m | 477 | 10 s | ×1.0 |
| VIII | `dc_flarefall` | AreaControl | 130 mm | 520 | 49 mm | 27.4 s | 5.9 m | 607 | 6 s | ×1.15 |
| IX | `dc_dewfall` | Support | 155 mm | 640 | 56 mm | 32.7 s | 7.65 m | 742 | 14 s | ×1.0 |
| X | `dc_noonfall` | Support | 155 mm | 800 | 64 mm | 36.1 s | 7.65 m | 877 | 16 s | ×1.0 |

HE pen is the SPG class target (0.25 × P), authored as a per-gun override of the decisions §1 default of calibre ÷ 2,
which would fail the lint by up to ×2.5 (a 155 mm shell would get 77 mm); the special HE gets ×1.30. Every
direct-hit clamp is below the HP of the weakest light the gun can meet (§5.2), so no SPG one-shots a full-HP light. Turret: open carriages and half-enclosed compartments traverse ±15° (`yawLimitsDeg`); IX–X turrets are 360°.

### 1.5 MOUNTAIN REPUBLIC (`mountain_republic`) — terrain

**Identity.** The Mountain Republic is a federation of valley communes in the High Cantons, where every road is a
switchback and every field is a slope. Its vehicles are built to climb, crest and hide, and its crews read ground
better than anyone. Emblem: three snow-capped peaks breaking out of a steel ring (brand §6.6).

**Doctrine: "the mountain is the armor."** Mountain crews fight from reverse slopes: crest, fire, drop back. They
have the best gun depression in the game (−12°, −16° with hydropneumatics, −20° in siege) and the highest speed of
any kit, paid for with paper hulls (×0.60). Their siege destroyers lock down a lane from overwatch.

**Design language and builder preset `mr_highland`**

| Part | Rule |
|---|---|
| Hull | **Very low**, long track run with **7–8 small road wheels**, raised front idler for climbing |
| Turret | Low turret **mounted at the rear**, so the gun overhangs the bow and the hull stays below the crest |
| Hydropneumatic MTs | Visible suspension struts between road-wheel stations that extend when the mechanic settles. The bonus is a **gun-arc** bonus (+4° depression, +3° elevation in every turret direction, as `VehicleSim` already applies it); the hull frame never pitches for it, so the bonus is not counted twice through the hull angle and the server armor and the rendered hull stay identical (decisions §10 parity). The struts are running-gear parts with no armor |
| Siege TDs | **Turretless rear gun block**: a low, steeply sloped casemate set at the rear of the very low hull (the medium line's rear-turret position), the long gun reaching over the bow; two **outrigger legs** folded along the rear hull sides swing down to the ground while sieged (cosmetic, no armor or collision, driven by the replicated siege phase so every observer sees the transition). Never a whole-hull casemate with a bow-fixed gun and dozer blade: that silhouette reads as a real vehicle (R17) |
| Gun | Slim barrel with a **short conical flash hider** and a breech counterweight collar |
| Detail kit | Spare road wheels on the hull sides, rope coils, snow-white hatch trim |
| Engine family | Diesel (fire 12 %) |

**Stat profile (kit):** top speed ×1.15, depression **−12°**, hull armor ×0.60.

| Class at Tier X | HP | Alpha | Reload | DPM | Speed | Notes |
|---|---|---|---|---|---|---|
| MT Versatile, Hydropneumatic (`mr_cragline`) | 1,950 | 400 | 9.5 s | 2,526 | 63 km/h | −16° after 0.75 s still; hull 0.30–0.42 P |
| TD Support, SiegeMode (`mr_peakhold`) | 1,658 | 600 | 12.4 s | ≈ 2,900 | 56 km/h travel, ≤ 10 siege | siege: aim ×0.4, dispersion ×0.85, −20° |
| MT Versatile Apex (`mr_updraft`, XI) | 2,200 | 440 | 9.8 s | 2,694 | 64 (+20 boost) km/h | RocketBoost 2 × 2.5 s, 30 s cooldown |

* **Strengths:** unmatched depression; the highest top speed of any kit (×1.15); in siege, the most accurate gun
  at Tier IX (0.25) and within 2 % of the best at X; they choose every engagement on broken ground.
* **Weaknesses:** almost every hull hit penetrates; on flat ground or in towns they have nothing to hide behind;
  siege transitions (2.0 s on, 1.25 s off) and the 0.75 s hydropneumatic delay punish surprise.
* **Intended counterplay:** flank before siege engages, catch them on flats and in transitions, aim at the hull the
  moment they crest.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `mr_pathfinder` | Pathfinder trunk | LT | I–III | I–III | Nimble climbing scouts |
| `mr_ridgeline` | Ridgeline medium line | MT | IV–X → XI | IV–X | The spine: reverse-slope mediums, Hydropneumatic VIII–X |
| `mr_bastion` | Bastion siege line | TD | IX–X | IV–X (IV–VIII in W3) | Turretless siege casemates |
| `mr_scree` | Scree light line | LT | — | IV–X (W2) | Climbing scouts that spot from peaks |

Splits and merges: Pathfinder III → Ridgeline IV (class switch LT → MT, top gun). Ridgeline VIII → Bastion IX
(the gun carries over into the hull). W2: Scree IV branches from Pathfinder III. W3: the Bastion lower body branches
from Pathfinder III and its VIII also unlocks Bastion IX (merge). Premium `mr_highstag` (LT VIII) trains Scree crews.

```
I              II               III            IV         V              VI           VII        VIII            IX              X               XI
mr_screehare → mr_cairnhopper → mr_ridgewren → mr_talus → mr_saddleback → mr_cornice → mr_scarp → mr_highcol ᴴ → mr_tarnwatch ᴴ → mr_cragline ᴴ → mr_updraft★
  LT             LT               LT             MT         MT              MT           MT         MT      │       MT              MT               MT
                                                                                                          └(gun)→ mr_tarnhold ˢ → mr_peakhold ˢ
                                                                                                                   TD             TD
Store: mr_highstag (LT VIII, P)                                ᴴ Hydropneumatic   ˢ SiegeMode   ★ RocketBoost
```

**Progression arc: Ridgeline (MT).**
* **IV `mr_talus` (Versatile):** the rear turret appears. Lesson: *only the turret crosses the crest.*
* **V `mr_saddleback` (Sniper):** long gun, −12°, very fast. Lesson: *shoot from the saddle between two hills.*
* **VI `mr_cornice` (Versatile):** quick turret, good speed. Lesson: *rotate between ridges faster than the enemy
  can re-aim.*
* **VII `mr_scarp` (Support):** reload ×0.92, camouflage +0.02. Lesson: *sustain fire from a hidden crest.*
* **VIII `mr_highcol` (Sniper, Hydropneumatic):** the settled suspension gives the gun −16°. Lesson: *stop for
  0.75 s before you crest.*
* **IX `mr_tarnwatch` (Sniper, Hydropneumatic):** longer gun, better view range. Lesson: *spot and shoot from the
  same peak.*
* **X `mr_cragline` (Versatile, Hydropneumatic):** the flagship generalist, fast enough to switch flanks.
* **XI `mr_updraft` (Versatile, RocketBoost):** two rocket bursts to sprint up to a crest or out of a crossfire.
  The boost adds speed, not lift: it never beats `MAX_CLIMB_DEG` 35° or leaves the ground (§2.7).

**Progression arc: Bastion (TD).** IX `mr_tarnhold` (Sniper, SiegeMode) teaches the siege rhythm: travel fast,
stop, deploy, fire with aim ×0.4. X `mr_peakhold` (Support, SiegeMode) reloads faster (Support ×0.9) and travels
faster, so it trades the sniper's precision for tempo.

**Progression arc: Pathfinder trunk (LT).** I `mr_screehare` (Scout) is the most agile Tier I. II
`mr_cairnhopper` (Versatile) climbs 35° slopes at speed. III `mr_ridgewren` (Scout) introduces the rear-turret
silhouette that the medium line inherits.

### 1.6 NORTHERN FEDERATION (`northern_federation`) — survival

**Identity.** The Northern Federation is a compact of coastal settlements on the Rime Coast and the Pale Reaches,
where winter lasts eight months and whiteouts close the roads for days. Its vehicles are shelters as much as weapons:
heated, enclosed, deep-hulled and thick. Emblem: a six-armed ice crystal with a snow-white hex core (brand §6.6).

**Doctrine: "outlast."** Northern crews lead with assault destroyers that bounce the first shots and win the
attrition that follows. Extra HP, thicker hulls and accurate guns make them the faction that is still there at the
end of the battle. Their heavies at IX–X are breakthrough machines that carry the push the destroyers start.

**Design language and builder preset `nf_rimeworks`**

| Part | Rule |
|---|---|
| Hull | Massive and deep, **heavily chamfered** on every upper edge (a faceted ice block), wide tracks with grouser detail |
| TD casemate | **Front, full-width casemate**: the glacis flows into the casemate face as one continuous slope; boxed mantlet |
| HT turret | **Hexagonal prism** turret (echoing the emblem's hex core), set at mid-hull |
| Gun | Medium-long barrel with a **box muzzle brake** (a rectangular block) |
| Running gear | 6 road wheels behind full-depth skirts, wide idlers |
| Detail kit | Exhaust heater boxes at the rear, ice cleats on the track guards, enclosed engine grilles |
| Engine family | Diesel (fire 12 %) |

**Stat profile (kit):** HP ×1.05, hull armor ×1.06, dispersion ×0.94, power-to-weight ×0.94.

| Class at Tier X | HP | Alpha | Reload | DPM | Speed | Notes |
|---|---|---|---|---|---|---|
| TD Assault (`nf_winterwall`) | 1,741 | 600 | 13.8 s | 2,613 | 37 km/h | casemate 1.17–1.48 P → clamp 1.45 P; camo −0.08 |
| HT Breakthrough (`nf_deepwinter`) | 2,457 | 500 | 12.1 s | 2,486 | 46 km/h | hp/t ≈ 16.6; armor ×0.95 ×1.06 |
| HT Breakthrough Apex (`nf_rimeburst`, XI) | 2,772 | 550 | 12.4 s | 2,652 | 46 km/h | active Turbo: power ×1.25 for 6 s, 40 s cooldown |

* **Strengths:** the most HP of any faction in every class they field (kit ×1.05); assault casemates out-armor
  heavies from the front;
  accurate guns for their class; they survive long enough to win the late game.
* **Weaknesses:** turretless casemates lose to flanks; sluggish acceleration (×0.94); Assault camouflage −0.08 makes
  them easy to spot; huge silhouettes.
* **Intended counterplay:** flank and circle, track them, shoot the cupola and lower plate, refuse the frontal trade.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `nf_frontier` | Frontier trunk | MT | I | I | One rugged starter |
| `nf_glacis` | Glacis destroyer line | TD | II–X | II–X | The spine: from ambush carriages to assault casemates |
| `nf_rimeguard` | Rimeguard heavy line | HT | IX–X → XI | IV–X (IV–VIII in W2) | Survival heavies that become breakthrough machines |
| `nf_aurora` | Aurora artillery line | SPG | — | IV–X (W3) | The second artillery line, stun Support only |

Splits and merges: Frontier I → Glacis II (class switch MT → TD, top engine). Glacis VIII → Rimeguard IX (top
engine; the heavy reuses the casemate's hull casting). W2: the Rimeguard lower body branches from Glacis III and its VIII also unlocks Rimeguard IX (merge). The
premium `nf_thawbreaker` (HT VIII) trains Rimeguard crews.

```
I              II           III         IV             V             VI            VII           VIII           IX            X              XI
nf_hoarling → nf_icepick → nf_sleet → nf_hailstone → nf_rimecrag → nf_floewall → nf_rimewall → nf_hoarwall → nf_driftwall → nf_winterwall
  MT            TD           TD         TD             TD            TD            TD            TD      │     TD             TD
                                                                                                         └(engine)→ nf_whiteout → nf_deepwinter → nf_rimeburst★
                                                                                                                      HT            HT              HT
Store: nf_thawbreaker (HT VIII, P)                                                             ★ active Turbo
```

**Progression arc: Glacis (TD).**
* **II `nf_icepick` (Support):** open-top gun carriage, quick reload, fragile. Lesson: *ambush, then relocate.*
* **III `nf_sleet` (Sniper):** low casemate, best TD camouflage at III. Lesson: *wait until the target commits.*
* **IV `nf_hailstone` (Versatile):** a turreted destroyer (360°, alpha ×0.9). Lesson: *a destroyer can track a
  moving target.*
* **V `nf_rimecrag` (Assault):** the first assault casemate (1.17–1.45 P) bounces Tier V MT and HT standard rounds
  frontally. Lesson:
  *lead from the front, but the gun arc is only ±11°: point the hull, not the turret.*
* **VI `nf_floewall` (Assault):** heavier casemate, bigger gun. Lesson: *hold the heavy lane with the heavies.*
* **VII `nf_rimewall` (Support):** lighter and faster, reload ×0.9. Lesson: *rotate and support instead of
  anchoring.*
* **VIII `nf_hoarwall` (Assault):** the continuous glacis-to-casemate slope. Lesson: *wall up beside your heavies.*
* **IX `nf_driftwall` (Assault):** 75 % of the casemate face sits at the 1.45 P clamp (the R3 maximum), the largest
  clamped frontal area at Tier IX; the rest of the face is ≤ 1.30 P, and a deliberately weak cupola and lower plate
  (≤ 0.70 P, together ≥ 8 % of the frontal silhouette, the cupola alone ≥ 3 %) keep it beatable hull-down (R3).
* **X `nf_winterwall` (Assault):** the flagship assault destroyer, 600 alpha behind 1.45 P.

**Progression arc: Rimeguard (HT).** IX `nf_whiteout` (Versatile) carries the hex turret and the most HP of any
Tier IX heavy; X `nf_deepwinter` (Breakthrough) trades armor for speed (+15 % speed and power); XI
`nf_rimeburst` adds the active Turbo, a 6-second shove that turns a held line into a breach.

---

## 2. Launch roster (W1: 89 vehicles)

**Columns.** *Combat identity* is the one line every stat decision must serve; when a number fights it, the number
loses. *Mechanic* lists only identity mechanics (decisions §4) with the proposed parameters; blank means a single-shot
gun. *Visual hook* is the silhouette feature the procedural builder must produce (survives at LOD2). *Parent* is the
research parent and the module that unlocks the vehicle (top gun unless stated); premiums show their store price.
Numbers in identities are targets derived from §5 (class × role × kit × tier); the lint (§5.1) is the judge.

### 2.1 Iron Union (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `iu_kolmal` | Kolmal | I | MT | Versatile | foundry | | Forgiving starter: sloped riveted front that rewards angling, unhurried (speed at the starter floor, ratio 0.97 = 39 km/h), choice of a quick or a hard-hitting gun | | Tractor-chassis box hull, tiny faceted dome, 4 large wheels, no return rollers | starter (free) |
| `iu_ostmal` | Ostmal | II | MT | Assault | foundry | | Short high-alpha gun with a slow reload; thickest Tier II front, soft sides | | Stepped riveted front, turret forward, stubby barrel with the first double-baffle brake | `iu_kolmal` |
| `iu_bulmal` | Bulmal | III | MT | Versatile | foundry | | First dome turret that bounces Tier III standard rounds; −5°; best medium alpha at III | | Longer hull, 5 large wheels, sagging track, dome centred | `iu_ostmal` |
| `iu_osthald` | Osthald | IV | HT | Versatile | bulwark | | First heavy: flat riveted front at ≈ 1.0 P, small welded box turret, weak hull sides, 34 km/h | | Tall riveted box hull with a vertical front, small welded box turret | `iu_bulmal` |
| `iu_brakkhald` | Brakkhald | V | HT | Assault | bulwark | | The slab wall: thick front, 31 km/h; top-gun choice of long AP or a stubby HE howitzer (α ×1.6, reload ×1.35) | | Thick slab glacis, hull-length side slabs, turret forward; howitzer = short fat barrel | `iu_osthald` |
| `iu_kolhald` | Kolhald | VI | HT | Support | bulwark | | First heavy with a cast dome; long, comparatively accurate gun (pen ×1.05); −7°; thinner hull (×0.85) | | Faceted dome on a lower hull, long barrel with double-baffle brake | `iu_brakkhald` |
| `iu_varrhald` | Varrhald | VII | HT | Breakthrough | bulwark | | Pike-nose prow (≈ 1.1 P at 0° yaw, lower prow 0.6 P), +15 % speed and power, leads the push | | First pike nose: two glacis wedges on a centre ridge; long low dome | `iu_kolhald` |
| `iu_tukkhald` | Tukkhald | VIII | HT | Versatile | bulwark | | Twin-gun debut: strong turret, average hull; singles to poke, volley to commit | DualGun 2 × 358, volley 716, charge 1.0 s, 1.5 s between barrels, ≈ 25.7 s per barrel | Wide twin mantlet on a dome turret, pike nose, side skirts | `iu_varrhald` |
| `iu_tukktund` | Tukktund | IX | HT | Assault | bulwark | | Thickest Tier IX turret face, 34 km/h; the volley is a corner-trade weapon | DualGun 2 × 440, volley 880, ≈ 27.6 s per barrel | Taller dome with cheek wedges, twin barrels, full skirts | `iu_tukkhald` |
| `iu_durhald` | Durhald | X | HT | Assault | bulwark | | Turret face at the 1.45 P clamp on the R3 maximum of 75 %, weak cupola and lower prow; lowest Tier X heavy DPM (0.87) for the most damage any Tier X lands in 1.5 s | DualGun 2 × 550, volley 1,100, ≈ 30.5 s per barrel | Longest Iron hull, massive twin mantlet, double-baffle brakes on both barrels, 6 wheels | `iu_tukktund` |
| `iu_tundmal` | Tundmal | IX | MT | Versatile | hammer | | A heavy's turret on a medium hull: turret ×1.10, α 352, −5°, 55 km/h | | Medium hull with an oversized faceted dome, short thick gun | `iu_tukkhald` (engine) |
| `iu_brakkmal` | Brakkmal | X | MT | Assault | hammer | | Strongest medium turret in the game, HP 2,048, α 440; worst medium depression | | Wide dome with cheek plates on a pike-nose medium hull, side slabs | `iu_tundmal` |
| `iu_tammvarr` | Tammvarr | VIII | TD | Versatile | (ram) | P | Iron's only W1 destroyer: 360° open-roof turret (α ×0.9), α 374, 12.88 s, DPM 1,742 (below the TD VIII median), thin turret; credits ×1.5; trains W2 Ram crews | | Open-roof faceted turret at the rear of a low hull, very long gun | Store 3,500 BUL |
| `iu_gorrtund` | Gorrtund | XI | HT | Assault | bulwark | | One enormous gun: α 605 (666 charged), HP 2,640, pen 283; slow and deliberate | ★ ChargedShot (+10 % damage) | Largest dome in the game with cheek armor, one very thick barrel with a triple-baffle brake | `iu_durhald` (47,000 XP) |

### 2.2 Crown Industries (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `ci_vernelle` | Vernelle | I | LT | Versatile | guild | | Unusually accurate small gun (dispersion ×0.93), quick, tall | | Tall narrow hull, box turret with a bustle stub, thin long barrel | starter (free) |
| `ci_gardelle` | Gardelle | II | LT | Scout | guild | | View range +10 m and camo +0.03, weak gun (α ×0.9) | | Tall box turret with a static periscope mast, 6 small wheels | `ci_vernelle` |
| `ci_ordant` | Ordant | III | MT | Sniper | guild | | First −10° medium: low alpha, best Tier III accuracy | | Slab hull, high-set box turret with a long bustle, bore evacuator debut | `ci_gardelle` (engine) |
| `ci_calibrant` | Calibrant | IV | MT | Support | guild | | DPM leader at IV (reload ×0.92 kit and role), thin armor | | Lower hull, wide box turret, short bore-evacuated quick-firing gun | `ci_ordant` |
| `ci_gardion` | Gardion | V | HT | Breakthrough | warden | | Fast first heavy (≈ 41 km/h), thin for a heavy (×0.95), Crown accuracy | | Slab-sided heavy on a long medium-style running gear, box turret | `ci_calibrant` |
| `ci_sterion` | Sterion | VI | HT | Versatile | warden | | Tall box turret with −10°: the hull-down heavy; petrol fires | | Big box turret set high with a long bustle, tall slab hull | `ci_gardion` |
| `ci_ordion` | Ordion | VII | HT | Support | warden | | −12°, best heavy accuracy at VII, turret only medium-thick | | Longest bustle in the line, turret set far back on a tall hull | `ci_sterion` |
| `ci_regnion` | Regnion | VIII | HT | Support | warden | | HESH debut: HESH for thin or flat plates, AP for thick, sloped or spaced armor; bustle ammo rack is the weak spot | HESH shell kit | Wide flat mantlet, long bore-evacuated gun, brass periscope hoods, side bins | `ci_ordion` |
| `ci_sovrion` | Sovrion | IX | HT | Versatile | warden | | Skirts and a thicker box turret that holds a ridge against Tier IX standard rounds; HESH | HESH shell kit | Long hull with full skirts, broad box turret | `ci_regnion` |
| `ci_tesselion` | Tesselion | X | HT | Support | warden | | The most accurate heavy (≈ 0.33), −12°, α 460, HESH; peek, shoot, hide | HESH shell kit | Tallest Crown turret, very long barrel with the line's largest bore evacuator | `ci_sovrion` |
| `ci_precine` | Precine | IX | TD | Sniper | vernier | | Low front casemate, ±12° yaw, camo +0.04, armor ≤ 0.45 P; HESH as the third round (AP + HEAT + HESH) | HESH shell kit | Low front casemate with a flat brass-trimmed face, long gun | `ci_regnion` |
| `ci_vernine` | Vernine | X | TD | Sniper | vernier | | Best Tier X dispersion (≈ 0.26), α 580, HESH; paper armor | HESH shell kit | Casemate set mid-hull, the faction's longest gun with a bore evacuator | `ci_precine` |
| `ci_calibine` | Calibine | VI | TD | Support | (vernier) | P | Fast-firing low-alpha casemate: α 214, 6.79 s, DPM 1,892, 46 km/h (Support speed ×1.1); credits ×1.35; trains Vernier crews | | Small sloped casemate, short bore-evacuated gun, brass trim | Store 1,600 BUL |
| `ci_aurelline` | Aurelline | XI | TD | Sniper | vernier | | HP 1,870, α 638, pen 325, HESH; ActiveCooling wins the 5-second duel it would otherwise lose | ★ ActiveCooling | Low casemate with radiator louvres along its sides, the longest gun in the game | `ci_vernine` (47,000 XP) |

### 2.3 Eastern Armor Group (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `ea_kirett` | Kirett | I | LT | Versatile | skirmish | | Best Tier I acceleration (≈ 21 hp/t) at ≈ 51 km/h; a quick-firing or a harder-hitting gun | | Tiny wedge hull, forward wedge turret, 4 big wheels | starter (free) |
| `ea_essett` | Essett | II | LT | Scout | skirmish | | Lowest Tier II silhouette (Scout camo +0.03, view range +10 m), weak gun | | Lower, longer wedge hull, very small turret | `ea_kirett` |
| `ea_veshett` | Veshett | III | LT | Scout | skirmish | | 57 km/h with a forward turret: show, spot, break contact | | Long narrow hull, forward turret, slotted brake debut | `ea_essett` |
| `ea_talett` | Talett | IV | LT | Support | skirmish | | Biggest gun on a Tier IV light (α and pen ×1.05), speed ×0.95 | | Barrel overhanging the nose, wedge turret | `ea_veshett` |
| `ea_sevett` | Sevett | V | LT | Versatile | skirmish | | 64 km/h and the fastest turret at V: circle and track | | Longer hull, 5 wide-spaced wheels, wing mudguards | `ea_talett` |
| `ea_venett` | Venett | VI | LT | Scout | skirmish | | Lowest light silhouette at VI, camo +0.03; weak gun | | Very low hull, turret nearly flush with the deck | `ea_sevett` |
| `ea_lirett` | Lirett | VII | LT | Support | skirmish | | High-pen gun (pen ×1.05) on a fast hull: unseen flank damage | | Long gun with slotted brake, turret forward | `ea_venett` |
| `ea_silett` | Silett | VIII | LT | Scout | skirmish | | Fastest tech-tree tracked light at VIII (70 km/h) and the quickest to reach it (≈ 32 hp/t); Scout camo +0.03 | | Longest Eastern tracked hull, tiny turret | `ea_lirett` |
| `ea_zarett` | Zarett | IX | LT | Support | skirmish | | 4 × 286 in 6 s, then 32.5 s helpless; paper turret | Magazine 4, 2.0 s intra, 32.5 s reload, burst 1,144 (≤ 0.85 × 1,650) | Drum bulge across the turret rear | `ea_silett` |
| `ea_talzarett` | Talzarett | X | LT | Versatile | skirmish | | 3 × 340 with a quick intra-clip; pick the moment or waste 28 s | Magazine 3, 1.8 s intra, 28.3 s reload, burst 1,020 in 3.6 s | Larger wedge turret with a drum bulge, long gun | `ea_zarett` |
| `ea_rhuvari` | Rhuvari | IX | LT | Versatile | outrider | | Cruise to fight, speed mode to relocate (70 → 91 km/h); −25 % top speed per destroyed wheel side, never immobilised | Wheeled: 4 wheel pairs, speed mode +30 %, steering ×0.6, reverse ×0.7, 1.0 s toggle, moving dispersion ×1.15, turn radius 8 m, −25 % top speed per destroyed wheel side | 4 wheels per side, boat-shaped hull, small centred turret | `ea_silett` (engine) |
| `ea_lirvari` | Lirvari | X | LT | Scout | outrider | | Fastest vehicle in the game and best Tier X spotter, weakest Tier X gun (α 306) | Wheeled (as above; turn radius 9 m) | Longer 8-wheel boat hull, low centred turret, exposed axle hubs | `ea_rhuvari` |
| `ea_sevzar` | Sevzar | V | LT | Support | (skirmish) | P | Brawler light: the Support gun (α 100, pen 91, DPM 1,485) at 60 km/h (Sevett: α 98, 64 km/h); credits ×1.35; trains Skirmish crews | | Short hull with an oversized wedge turret | Store 1,000 BUL |
| `ea_lirvesh` | Lirvesh | XI | LT | Support | skirmish | | 4 × 393 with top-off reloads (full magazine 37.3 s); HP 1,760 | ★ AdaptiveMagazine (§2.7) | Drum bulge merged into a larger wedge turret, longest Eastern hull | `ea_talzarett` (47,000 XP) |

### 2.4 Desert Armor Corps (19)

SPG role trims are not in decisions §7.2 (only the names), and `Roles.luau` currently ships both artillery roles
with empty `trims` and identical Role Score weights. Proposal (O·L, tune by telemetry): **`artillery_support`** full
stun, splash radius ×1.0; **`artillery_area_control`** stun ×0.5, reload ×0.90, shell velocity ×1.15, splash radius
×0.85, so the two roles reward different play. Alpha stays 2 × MT alpha for both, and the direct-hit clamp (0.45 ×
same-tier MT HP) applies to both. Per-tier numbers: the Sunfall gun table in §1.4. **Role Score stays as decisions
§7.2 fixes it for both roles (stun 0.5 / damage 0.4 / kills 0.1)** until the decisions doc changes: an AreaControl
weighting of damage 0.6 / stun 0.3 / kills 0.1 is proposed to its owner (§6.3), because Role Score is normalised per
class and tier, so a half-stun role would otherwise score low on the stun component and miss defeat protection.

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `dc_waymark` | Waymark | I | MT | Versatile | caravan | | Quick aim (×0.94) and −10° from the first battle | | Boxy little hull under a sunshade canopy frame, small hexagonal turret | starter (free) |
| `dc_bearing` | Bearing | II | MT | Support | caravan | | Fast reload; teaches sustained fire | | Short sand skirts debut, hexagonal turret | `dc_waymark` |
| `dc_sandglass` | Sandglass | III | MT | Sniper | caravan | | Long gun with the highest Tier III sniper DPM (reload ×0.95); tall cupola weak spot | | Tall cupola, long thin gun with sleeve bands | `dc_bearing` |
| `dc_parallax` | Parallax | IV | MT | Versatile | longshot | | Hull-down turret (×1.08) over a weak lower plate (×0.85) | | Full sand skirts, sloped glacis over a tall flat lower plate | `dc_sandglass` |
| `dc_azimuth` | Azimuth | V | MT | Sniper | longshot | | Long gun, sniper dispersion and pen (×0.9, ×1.07), the fastest Tier V medium aim (×0.94), view range +10 m | | Longest barrel at V with 2 sleeve bands | `dc_parallax` |
| `dc_meridian` | Meridian | VI | MT | Assault | longshot | | Thick turret (×1.08 × 1.15), HP ×1.05, speed ×0.92: holds a ridge under fire | | Wider hex turret with cheek plates | `dc_azimuth` |
| `dc_longsight` | Longsight | VII | MT | Sniper | longshot | | Best Tier VII medium dispersion (≈ 0.34), view range +10 m | | Turret with rangefinder ears (a small cylinder on each side) | `dc_meridian` |
| `dc_sextant` | Sextant | VIII | MT | Versatile | longshot | | The double tap from cover | Autoreloader 2 × 260, refills 9.0 / 7.5 s (in refill order after empty; first is longest), 2.0 s intra, sustained 0.92 | Boxy magazine bustle on the hex turret | `dc_longsight` |
| `dc_dawnfix` | Dawnfix | IX | MT | Assault | longshot | | Three shells from the strongest Desert turret; manage the long first refill | Autoreloader 3 × 320, refills 11.0 / 8.0 / 7.6 s, 2.0 s intra | Heavy hex turret with cheek plates and magazine bustle | `dc_sextant` |
| `dc_sunward` | Sunward | X | MT | Sniper | longshot | | Flagship long-range medium: pen 273, aim 2.07 s | Autoreloader 3 × 400, refills 12.5 / 9.4 / 9.0 s, 2.0 s intra | Longest Desert gun with 3 sleeve bands, magazine bustle | `dc_dawnfix` |
| `dc_dustfall` | Dustfall | IV | SPG | AreaControl | sunfall | | Light open-top 105 mm howitzer, HE 170, no stun (stun starts at V) | | Open-top carriage on the caravan chassis, short howitzer, rear spade | `dc_sandglass` (engine) |
| `dc_ashfall` | Ashfall | V | SPG | Support | sunfall | | First stun (≤ 6 s), HE 230, 120 mm, splash 6.6 m | | Open-top, longer howitzer behind crew shield plates | `dc_dustfall` |
| `dc_sparkfall` | Sparkfall | VI | SPG | AreaControl | sunfall | | Fast light carriage, 105 mm, HE 320, 19.2 s, small splash (5.2 m), stun ≤ 4 s, quick relocation | | Low open-top carriage, small howitzer, 5 wheels | `dc_ashfall` |
| `dc_glassfall` | Glassfall | VII | SPG | Support | sunfall | | Heavy 155 mm howitzer, HE 440, splash 7.65 m, stun ≤ 10 s | | Half-enclosed box compartment, fat short howitzer | `dc_sparkfall` |
| `dc_flarefall` | Flarefall | VIII | SPG | AreaControl | sunfall | | Long 130 mm gun-howitzer: flatter arc, shell ×1.15, HE 520, stun ≤ 6 s; the most reliable direct hits in the line | | Half-enclosed compartment, very long barrel | `dc_glassfall` |
| `dc_dewfall` | Dewfall | IX | SPG | Support | sunfall | | Enclosed 360° turret covers two lanes, HE 640, stun ≤ 14 s | | Enclosed rear turret, long hull, rear recoil spades | `dc_flarefall` |
| `dc_noonfall` | Noonfall | X | SPG | Support | sunfall | | Flagship howitzer: HE 800, 155 mm, stun ≤ 16 s, slow and fragile | | Fully enclosed turret, longest howitzer, recoil spades, 6 wheels | `dc_dewfall` |
| `dc_dunelight` | Dunelight | VIII | MT | Support | (longshot) | P | Single-shot DPM medium: α 252, 7.06 s, DPM 2,142, no autoreloader, armor ×0.9; credits ×1.5; trains Longshot crews | | Short hex turret, mid-length gun, skirts hung with jerrycan racks | Store 3,500 BUL |
| `dc_zenith` | Zenith | XI | MT | Sniper | longshot | | HP 2,200, α 440, pen 294: the long-range duel winner if allowed to charge | ★ ChargedShot (dispersion ×0.6) | Tallest cupola, the game's longest medium gun with 4 sleeve bands, no magazine bustle | `dc_sunward` (47,000 XP) |

### 2.5 Mountain Republic (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `mr_screehare` | Screehare | I | LT | Scout | pathfinder | | Fastest Tier I (≈ 55 km/h), camo +0.03, −12° | | Tiny low hull, rear turret, 6 small wheels | starter (free) |
| `mr_cairnhopper` | Cairnhopper | II | LT | Versatile | pathfinder | | Climbs 35° slopes at speed; hull hits always penetrate | | Long low hull, raised front idler, rear turret | `mr_screehare` |
| `mr_ridgewren` | Ridgewren | III | LT | Scout | pathfinder | | Best Tier III ridge spotter: rear turret plus −12° | | Rear-turret silhouette on 7 small wheels | `mr_cairnhopper` |
| `mr_talus` | Talus | IV | MT | Versatile | ridgeline | | Only the turret crosses the crest; 54 km/h, hull ×0.60 | | Low hull, rear turret, gun overhanging the bow | `mr_ridgewren` |
| `mr_saddleback` | Saddleback | V | MT | Sniper | ridgeline | | Long gun, −12°, 58 km/h, paper hull | | Longer gun with the flash-hider cone, 8 small wheels | `mr_talus` |
| `mr_cornice` | Cornice | VI | MT | Versatile | ridgeline | | Fast turret and 60 km/h: rotate between ridges faster than enemies re-aim | | Wider rear turret, spare road wheels on the hull sides | `mr_saddleback` |
| `mr_scarp` | Scarp | VII | MT | Support | ridgeline | | Reload ×0.92, camo +0.02; the thinnest medium at VII | | Lowest Mountain medium, small rear turret | `mr_cornice` |
| `mr_highcol` | Highcol | VIII | MT | Sniper | ridgeline | | Stop 0.75 s, then −16°: shoots over crests no one else can | Hydropneumatic +4° depression / +3° elevation after 0.75 s still | Visible suspension struts that extend when settled, rear turret | `mr_scarp` |
| `mr_tarnwatch` | Tarnwatch | IX | MT | Sniper | ridgeline | | Longer gun, view range +10 m: spot and shoot from one peak | Hydropneumatic | Long gun, suspension cylinders, rear turret | `mr_highcol` |
| `mr_cragline` | Cragline | X | MT | Versatile | ridgeline | | Flagship generalist, 63 km/h, −16°, hull 0.30–0.42 P | Hydropneumatic | Longest Mountain hull, 8 wheels, cylinders, rear turret | `mr_tarnwatch` |
| `mr_tarnhold` | Tarnhold | IX | TD | Sniper | bastion | | Travel fast, stop, deploy, fire with aim ×0.4; any hit penetrates | SiegeMode: on 2.0 s / off 1.25 s, aim ×0.4, dispersion ×0.85, +8° dep / +6° elev, ≤ 10 km/h, hull traverse ×0.5 | Low rear gun block, long gun over the bow, folded outrigger legs | `mr_highcol` (gun) |
| `mr_peakhold` | Peakhold | X | TD | Support | bastion | | Tempo siege destroyer: reload ×0.9, 56 km/h in travel, −20° in siege | SiegeMode (as above) | Longer hull, taller rear gun block with twin side periscopes, outrigger legs | `mr_tarnhold` |
| `mr_highstag` | Highstag | VIII | LT | Scout | (scree) | P | Climbing scout: −12°, 74 km/h but slower to get there than Silett (≈ 29 vs 32 hp/t), α 193; credits ×1.5; trains W2 Scree crews | | Rear-turret light with a tall, narrow hull nose | Store 3,500 BUL |
| `mr_updraft` | Updraft | XI | MT | Versatile | ridgeline | | HP 2,200, α 440, 64 km/h, two bursts to take a crest first | ★ RocketBoost (2 × 2.5 s, +20 km/h, 30 s cooldown per charge) | Rear turret, two rocket pods on the rear hull flanks | `mr_cragline` (47,000 XP) |

### 2.6 Northern Federation (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `nf_hoarling` | Hoarling | I | MT | Assault | frontier | | Thickest Tier I hull (×1.06 × 1.15), slow, generous HP | | Deep chamfered block hull, small hex turret | starter (free) |
| `nf_icepick` | Icepick | II | TD | Support | glacis | | Open-top gun carriage (casemate mount, ±11°): quick reload, fragile; ambush and relocate | | Low chassis with an open gun shield | `nf_hoarling` (engine) |
| `nf_sleet` | Sleet | III | TD | Sniper | glacis | | Best TD camouflage at III, accurate (×0.94 kit) | | Low enclosed casemate, box muzzle brake debut | `nf_icepick` |
| `nf_hailstone` | Hailstone | IV | TD | Versatile | glacis | | Turreted (360°, α ×0.9): tracks moving targets | | Hexagonal open-top turret on a deep hull | `nf_sleet` |
| `nf_rimecrag` | Rimecrag | V | TD | Assault | glacis | | First assault casemate (1.17–1.45 P front after kit and clamp), ±11° arc, camo −0.08 | | Front full-width casemate, continuous glacis slope | `nf_hailstone` |
| `nf_floewall` | Floewall | VI | TD | Assault | glacis | | Heavier casemate and bigger gun: anchors the heavy lane | | Taller casemate, wide skirts | `nf_rimecrag` |
| `nf_rimewall` | Rimewall | VII | TD | Support | glacis | | Lighter and faster (×1.1), reload ×0.9, armor ≤ 0.45 P: rotate and support | | Smaller casemate set mid-hull | `nf_floewall` |
| `nf_hoarwall` | Hoarwall | VIII | TD | Assault | glacis | | Wall up beside the heavies; the slope is the armor | | One continuous slope from nose to casemate roof | `nf_rimewall` |
| `nf_driftwall` | Driftwall | IX | TD | Assault | glacis | | 75 % of the casemate face at the 1.45 P clamp (the R3 maximum, the largest clamped area at IX); deliberately weak cupola and lower plate | | Massive chamfered casemate with a raised cupola | `nf_hoarwall` |
| `nf_winterwall` | Winterwall | X | TD | Assault | glacis | | 600 alpha behind 1.45 P, HP 1,741, the slowest Tier X destroyer (37 km/h) | | Longest Northern hull, huge box brake | `nf_driftwall` |
| `nf_whiteout` | Whiteout | IX | HT | Versatile | rimeguard | | Most HP of any Tier IX heavy (2,079), accurate, sluggish | | Hexagonal turret at mid-hull on a deep chamfered hull | `nf_hoarwall` (engine) |
| `nf_deepwinter` | Deepwinter | X | HT | Breakthrough | rimeguard | | 46 km/h heavy, armor ×0.95; carries the push the destroyers start | | Lower, longer hull, hex turret set back | `nf_whiteout` |
| `nf_thawbreaker` | Thawbreaker | VIII | HT | Assault | (rimeguard) | P | Slow armored heavy: HP 1,701, α 315, DPM 1,842, armor at 0.97 of its target; credits ×1.5; trains Rimeguard crews | | Squat hex turret, deep hull, wide skirts | Store 3,500 BUL |
| `nf_rimeburst` | Rimeburst | XI | HT | Breakthrough | rimeguard | | HP 2,772, α 550; Turbo turns a held line into a breach | ★ active Turbo (power ×1.25, 6 s, 40 s cooldown) | Hex turret, twin exhaust-heater stacks that glow during Turbo | `nf_deepwinter` (47,000 XP) |

### 2.7 Tier XI Apex specification

All six follow decisions §7.4. **Stats** = the MT baseline **XI row** (which already applies the Apex multipliers
X × HP 1.13, α 1.10, pen 1.08, DPM 1.07) × class × role × kit; the §1 tables and §5.2–5.3 use that row, so every
Apex number in this document is reproducible from one table. One signature, matched only in X–XI battles, one
configuration (`stock == top`), and the 10-node track below (content-schema §5.6). Apexes carry **no** Tier I–X
mechanic (no DualGun, Autoreloader, Hydropneumatic, SiegeMode, Wheeled), so the signature is the only thing new on
the HUD; the one carve-out is `ea_lirvesh`, whose `Magazine` gun is the carrier the AdaptiveMagazine signature
modifies (R9, R16).

| Apex | Class / role | Signature (base, schema fields) | Activation | Final-node upgrade (`StatKey`) | HUD widget | Why this faction |
|---|---|---|---|---|---|---|
| `iu_gorrtund` | HT Assault | `ChargedShot { chargeTimeS = 1.5, effect = "Damage", damageMul = 1.10 }` | Hold Fire ≥ 1.5 s, release to fire | `mechanicChargeTime` 1.5 → 1.25 s | Charge ring on the reticle | The alpha faction gets the biggest single hit in the game |
| `ci_aurelline` | TD Sniper | `ActiveCooling { durationS = 5, cooldownS = 45, modifiers = { reloadTime ×0.85, aimTime ×0.85 } }` | Mechanic key `[X]` / pad `[B]` | `mechanicCooldown` 45 → 38 s | Duration ring, then cooldown sweep | Precision turned into a short window of tempo |
| `ea_lirvesh` | LT Support | `AdaptiveMagazine { partialReloadFactor = 0.35 }` on a `Magazine { size = 4, intraClipS = 2.2, reloadS = 37.3 }` gun | Mechanic key tops off; empty → automatic full reload | `mechanicFactor` 0.35 → 0.30 | Magazine pips + top-off ring on the next empty pip (ui-ux H-05) | The magazine faction's magazine perfected |
| `dc_zenith` | MT Sniper | `ChargedShot { chargeTimeS = 1.5, effect = "Accuracy", dispersionMul = 0.6 }` | Hold Fire ≥ 1.5 s, release to fire | `mechanicChargeTime` 1.5 → 1.25 s | Charge ring | Long range made reliable |
| `mr_updraft` | MT Versatile | `RocketBoost { charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 }` | Mechanic key, one charge per press | `mechanicCooldown` 30 → 25 s per charge | Two boost pips with cooldown sweeps | Terrain mobility turned into tempo |
| `nf_rimeburst` | HT Breakthrough | `Turbo { powerMul = 1.25, durationS = 6, cooldownS = 40 }` | Mechanic key | `mechanicDuration` 6 → 7 s | Duration ring, then cooldown sweep | Survival heavies that refuse to be pinned |

**Signature rules (all Apexes).** The server owns every signature state; the client predicts the widget only. A
final-node upgrade improves exactly one parameter by at most 20 %. **ChargedShot** (fire semantics per ui-ux H-05):
the charge builds only while a shell is **loaded** and the trigger is held; holding through a reload starts the
charge the moment loading completes, so a charged shot always costs its 1.5 s on top of the reload (charged DPM
≈ uncharged DPM: `iu_gorrtund` 666 every 15.2 s ≈ 2,630 vs 605 every 13.7 s ≈ 2,650). A tap fires a normal shot on
release; releasing before full charge fires a normal shot with no penalty. Hull movement above 0.5 km/h resets the
charge to 0 and it resumes when the hull stops (turret traverse is allowed and blooms as usual), so the bonus is a
positional commitment, never a free brawling buff; Combat sets `CHARGED_SHOT_RESET_ON_MOVE = true` (GunState default
today is `false`, §6.3). The charge works with every shell and is cancelled without firing by an ammo swap, a
destroyed gun or the vehicle's destruction; R1 includes the ×1.10 damage. **RocketBoost / Turbo:** both run in `VehicleSim`
(as built today). Turbo multiplies engine power, which stays traction-limited (μ·g·cos θ, decisions §6); the
top-speed cap is unchanged. RocketBoost raises the top-speed cap by `speedBonusKmh` and adds a forward thrust of
`Config.Movement.ROCKET_BOOST_ACCEL_MPS2` (3.0 m/s²) on top of the traction-limited engine drive (a rocket does not
push through the tracks) while a charge burns; when it ends, speed above the normal cap is shed by engine braking
(`ENGINE_BRAKE_DECEL_MPS2`, 3.5 m/s²), never clamped instantly. Neither can beat `MAX_CLIMB_DEG` 35° (above it every
drive force, boost included, is zero), lift the vehicle or push it through map bounds; a destroyed engine or tracks
cancels an active boost and blocks new activations until repaired.
**ActiveCooling:** while active, reload progress runs at 1 ÷ 0.85 speed and the aim-time constant is ×0.85
(`modifiers` = `reloadTime` mul 0.85, `aimTime` mul 0.85); it may be started mid-reload.

**`AdaptiveMagazine`** (the decisions doc names it without numbers, so these are O·L proposals for the combat
owner): a 4-shell magazine, 2.2 s between shells, full reload `T_m` = 37.3 s, which sets the sustained DPM on full
empties to 0.85 × class (4 × 393 × 60 ÷ (37.3 + 3 × 2.2) ≈ 2,150), the decisions §4 Magazine factor. The magazine
can be topped off at any time with the mechanic key; a top-off takes `T_m × (f + (1 − f) × spent ÷ size)` with
`f = partialReloadFactor` = 0.35, so one missing shell costs 19.1 s (51 % of `T_m`) and three cost 31.2 s. Topping
off never beats full empties on DPM (one-shell top-offs sustain ≈ 1,230 DPM); it buys readiness, not damage. Firing
during a top-off cancels it and keeps the shells already in the magazine (the refill is all-or-nothing, so there are
no free shells). Burst 4 × 393 = 1,572 ≤ 0.85 × Tier XI MT HP (1,870), R2.

**Apex node track** (decisions §11: 6 × 4,000 XP small nodes at +2 %, 3 × 8,000 XP large nodes at +4 %, 1 × 12,000
XP final node; 60,000 XP, Free XP allowed). One stat per node; no stat gains more than +6 % from nodes, inside the
+12 % ceiling of R16:

| Node | XP | All Apexes | Class-specific |
|---|---|---|---|
| S1–S6 | 4,000 each | S1 `aimTime` ×0.98 · S2 `dispersion` ×0.98 · S3 `hullTraverse` ×1.02 · S4 `turretTraverse` (turret or casemate gun) ×1.02 · S5 `viewRange` ×1.02 · S6 `hp` ×1.02 | – |
| L1 | 8,000 | `reloadTime` ×0.96 | – |
| L2 | 8,000 | `enginePower` ×1.04 | – |
| L3 | 8,000 | – | HT `hp` ×1.04 · MT `aimTime` ×0.96 · TD `dispersion` ×0.96 · LT `viewRange` ×1.04 |
| Final | 12,000 | signature upgrade (table above) | – |

### 2.8 Premium summary

| Premium | Tier / class / role | BUL | Credits | Alternative playstyle (never strictly better) | Crew it trains |
|---|---|---|---|---|---|
| `ea_sevzar` | V LT Support | 1,000 | ×1.35 | Brawler light in a scouting faction | Eastern LT (Skirmish spine) |
| `ci_calibine` | VI TD Support | 1,600 | ×1.35 | Fast-firing, low-alpha destroyer in an accuracy faction | Crown TD (Vernier IX–X) |
| `iu_tammvarr` | VIII TD Versatile | 3,500 | ×1.5 | Turreted destroyer in an alpha faction: arcs and comfort instead of DPM | Iron TD (W2 Ram line) |
| `dc_dunelight` | VIII MT Support | 3,500 | ×1.5 | Single-shot DPM medium instead of an autoreloader | Desert MT (Longshot) |
| `mr_highstag` | VIII LT Scout | 3,500 | ×1.5 | Climbing scout in a medium-and-siege faction | Mountain LT (W2 Scree) |
| `nf_thawbreaker` | VIII HT Assault | 3,500 | ×1.5 | Armored heavy in a destroyer faction | Northern HT (Rimeguard IX–X) |

**Power rules, made operational** (decisions §7.4 and §15: 40th–55th percentile, nothing above tech-tree P60, no
pay-for-power). The "envelope" of a stat is the lint band [0.85, 1.15] × the vehicle's own target (§5.1), read
linearly as percentiles: P40 = ratio 0.97, P55 = 1.015, P60 = 1.03. Premium rules:

1. HP, top speed, power-to-weight, hull traverse, dispersion, aim time and effective front armor sit at ratio
   0.97–1.015 (P40–P55); alpha at 0.97–1.0; DPM and standard pen at 0.95–0.97, just under P40, which is what the
   premium pays for its credit multiplier. The mean ratio over these ten stats is 0.97–1.015, so the vehicle as a
   whole sits at P40–P55 (decisions §7.4). Mobility and comfort (gun arcs, turret, camouflage) carry the
   compensation; armor and alpha never exceed 1.0.
2. No core stat above ratio 1.03 (the P60 ceiling).
3. **Dominance check (R8):** a premium must not beat **every** same-tier, same-class tech-tree vehicle of the live
   roster on both sustained DPM and effective front armor.
4. No special mechanic; no Tier IX–XI premium in W1. A nerf of more than 5 % opens the 14-day Bullion refund window.
   Lint flag `premium = true` runs rules 1–3.

**Authoring targets** (top = stock, content-schema §5.4):

| Premium | HP | α | Pen | Reload | DPM | Speed | Same-tier tech-tree comparison (rule 3) |
|---|---|---|---|---|---|---|---|
| `ea_sevzar` | 512 | 100 | 91 | 4.04 s | 1,485 | 60 km/h | `ea_sevett`: α 98, DPM 1,474, 64 km/h, same armor: not better on armor |
| `ci_calibine` | 697 | 214 | 147 | 6.79 s | 1,892 | 46 km/h | `nf_floewall`: DPM 1,773 but 1.17–1.45 P front vs ≤ 0.45 P |
| `iu_tammvarr` | 1,148 | 374 | 221 | 12.88 s | 1,742 | 44 km/h | `nf_hoarwall`: DPM 2,017 and far thicker: worse on both |
| `dc_dunelight` | 1,350 | 252 | 187 | 7.06 s | 2,142 | 55 km/h | `dc_sextant` (sustained 1,889, 2-shell burst) has the stronger turret; `mr_highcol` 1,857 |
| `mr_highstag` | 1,080 | 193 | 169 | 7.68 s | 1,508 | 74 km/h | `ea_silett`: DPM 1,571, accelerates faster (32 vs 29 hp/t) |
| `nf_thawbreaker` | 1,701 | 315 | 193 | 10.26 s | 1,842 | 34 km/h | `ci_regnion`: DPM 1,919, so not better than every heavy on DPM |

### 2.9 Visual features: schema fields first, hooks second

A "visual hook" in §2 is built from `VisualSpec`, turret and gun module `visual` fields wherever the schema has one
(content-schema §6, `Types/Content.luau`); a `VisualSpec.hooks` key is used only for what no field expresses. Unknown
keys are ignored by the Blueprint, so a key may ship before the builder draws it. Every hook marked LOD0 or LOD1 is
detail only; all others are silhouette features that must survive at LOD2 (§1 budget).

**LOD2 cost of a hook** (so the 16-part budget of §1 always closes):

| Cost | Hooks | Rule |
|---|---|---|
| 0 parts (reshapes a part already counted) | `tractor_chassis` `sagging_track` `twin_mantlet` `triple_baffle_brake` `wing_mudguards` `boat_hull` `tall_cupola` `raised_idler` `magazine_bustle` `half_enclosed` `flash_hider` `tall_nose` `chamfered_edges` `box_brake` `continuous_glacis` `open_hex_turret` `raised_cupola` | Free at every LOD |
| 1–2 parts | `stepped_front` (1) `cheek_wedges` (2) `periscope_mast` (1) `drum_bulge` (1) `sunshade_frame` (1) `rangefinder_ears` (2) `cheek_plates` (2) `crew_shield` (1) `recoil_spades` (2) `outrigger_legs` (2) `rocket_pods` (2) `heater_stacks` (2, Neon) | ≤ 3 parts per vehicle at LOD2 (≤ 2 wheeled); every W1 vehicle fits |
| Detail only | LOD1: `stowage_bins` `radiator_louvres` `spare_wheels` `spare_track_glacis` · LOD0: `riveted_plates` `brass_hoods` `axle_hubs` `side_periscopes` `ice_cleats` | Dropped below the LOD named |

| Preset | Roster feature → schema field | Hook keys (only these) |
|---|---|---|
| `iu_foundry` | riveted box `hull.style "Boxy"` · stepped front `"Stepped"` · pike nose `"Pike"` · side slabs `skirts "Plates"` · dome turret `style "FacetedDome"` · IV–V box turret `"Box"` · Tammvarr open rear turret `"Open"`, ring `positionFraction` 0.65 · double baffle `muzzleBrake "Double"` · howitzer: short `barrelLengthM`, wide `barrelDiameterM` · no return rollers `returnRollers 0` · track links `details.spareTracks` | `tractor_chassis` `stepped_front` (lip; used by `iu_ostmal`) `spare_track_glacis` (LOD1) `sagging_track` `cheek_wedges` `twin_mantlet` `triple_baffle_brake` `riveted_plates` (LOD0) |
| `ci_guild` | slab hull `"Slab"` · box turret with bustle `style "Box"` + `bustleLengthM` · set high `turretRing.heightOffsetM` 0.15–0.25 · bore evacuator `fumeExtractor true` · small brake `"None"`/`"Single"` · skirts `"Full"` · casemates: mount `Casemate`, `superstructure.positionFraction` ≤ 0.35 (front) or 0.45–0.55 (mid) · `returnRollers 3` | `stowage_bins` (LOD1) `periscope_mast` `radiator_louvres` (LOD1) `brass_hoods` (LOD0) |
| `ea_windward` | wedge nose `"Wedge"` · wedge turret `style "Wedge"` · forward turret `positionFraction` 0.25–0.35 · centred 0.5 · flush turret `heightM` ≤ 0.5 · slotted brake `"Slotted"` · wheeled `suspension "Wheeled"`, `roadWheels 4` | `wing_mudguards` `drum_bulge` `boat_hull` `axle_hubs` (LOD0) |
| `dc_caravan` | sloped glacis over a tall lower plate `"Sloped"`, `upperFrontFraction` 0.40–0.45 · sand skirts `"Full"` · hex turret `"Hexagonal"` + `cupola true` · sleeve bands `thermalSleeve true` (bands = clamp(round(barrelLengthM ÷ 2), 1, 4): Azimuth 2, Sunward 3, Zenith 4) · single baffle `"Single"` · jerrycans `details.jerrycans` · SPG open carriage `style "Open"`, IX–X enclosed `"Box"` (360°) | `sunshade_frame` `tall_cupola` `raised_idler` `rangefinder_ears` `cheek_plates` `magazine_bustle` · SPG `crew_shield` `half_enclosed` `recoil_spades` |
| `mr_highland` | very low hull `"LowProfile"` · rear turret `positionFraction` 0.65–0.75 · small wheels `roadWheels` 6–8, `wheelDiameterM` ≤ 0.5 · hydropneumatics `suspension "Hydro"` (the preset draws the struts; the bonus is gun arcs only, the hull never pitches for it) · siege TD `hull.style "LowProfile"`, mount `Casemate` in a rear `superstructure` (`positionFraction` 0.65–0.75, `heightM` ≤ 0.6, `frontAngleDeg` ≥ 55) · brake `"None"` | `raised_idler` `flash_hider` `spare_wheels` (LOD1) `outrigger_legs` `side_periscopes` (LOD0) `rocket_pods` `tall_nose` |
| `nf_rimeworks` | deep hull `"Sloped"`, `sideSlopeDeg` ≥ 15 · casemate mount `Casemate`, `superstructure.positionFraction` ≤ 0.35 (front) or 0.5 (Rimewall) · HT hex turret `"Hexagonal"` · open shield / open turret `style "Open"` · skirts `"Full"` · box brake `muzzleBrake "Single"` drawn as a block by the hook | `chamfered_edges` `box_brake` `continuous_glacis` `open_hex_turret` `raised_cupola` `heater_stacks` (Neon, glows during Turbo) `ice_cleats` (LOD0) |

**Hooks per vehicle** (W1):

| Faction | On every vehicle | Additions |
|---|---|---|
| Iron Union | `sagging_track`; `riveted_plates` I–VI | `iu_kolmal` `tractor_chassis` · `iu_ostmal` `stepped_front` `spare_track_glacis` · `iu_tukkhald` `twin_mantlet` · `iu_tukktund`, `iu_durhald` `twin_mantlet` `cheek_wedges` · `iu_tundmal`, `iu_brakkmal` `cheek_wedges` · `iu_gorrtund` `cheek_wedges` `triple_baffle_brake` |
| Crown Industries | `stowage_bins` `brass_hoods` (turreted vehicles) | `ci_gardelle` `periscope_mast` · `ci_aurelline` `radiator_louvres` |
| Eastern Armor Group | `wing_mudguards` (tracked) | `ea_zarett`, `ea_talzarett`, `ea_lirvesh` `drum_bulge` · `ea_rhuvari`, `ea_lirvari` `boat_hull` `axle_hubs` |
| Desert Armor Corps | MTs: `tall_cupola` `raised_idler` | `dc_waymark`, `dc_bearing`, `dc_sandglass` `sunshade_frame` · `dc_meridian` `cheek_plates` · `dc_longsight` `rangefinder_ears` · `dc_sextant`, `dc_sunward` `magazine_bustle` · `dc_dawnfix` `magazine_bustle` `cheek_plates` · `dc_dustfall`, `dc_dewfall`, `dc_noonfall` `recoil_spades` · `dc_ashfall` `crew_shield` · `dc_glassfall`, `dc_flarefall` `half_enclosed` |
| Mountain Republic | `raised_idler` `flash_hider`; `spare_wheels` on MTs | `mr_tarnhold`, `mr_peakhold` `outrigger_legs`; `mr_peakhold` also `side_periscopes` · `mr_highstag` `tall_nose` · `mr_updraft` `rocket_pods` |
| Northern Federation | `chamfered_edges` `ice_cleats`; `box_brake` from III | `nf_hailstone` `open_hex_turret` · `nf_rimecrag`, `nf_floewall`, `nf_hoarwall`, `nf_driftwall`, `nf_winterwall` `continuous_glacis` · `nf_driftwall`, `nf_winterwall` `raised_cupola` · `nf_rimeburst` `heater_stacks` |

### 2.10 Tier I–X mechanic parameters (schema fields)

| Mechanic | Vehicles | Parameters (decisions §4; content-schema §4.3, §5.5) |
|---|---|---|
| `DualGun` (gun reload) | `iu_tukkhald`, `iu_tukktund`, `iu_durhald` | `reloadEachS` 25.7 / 27.6 / 30.5 (2.3 × class reload × Iron kit), `salvoDelayS` 1.5, `chargeTimeS` 1.0, `volleyDispersionMul` 1.5. Fire semantics per ui-ux H-05: a press < 0.25 s fires one loaded barrel on release; a longer hold charges the volley, which needs **both** barrels loaded and fires itself when the charge completes; releasing early cancels it (no shot, no reload spent) |
| `Magazine` (gun reload) | `ea_zarett`, `ea_talzarett` | `size` 4 / 3, `intraClipS` 2.0 / 1.8, `reloadS` 32.5 / 28.3; no rammer |
| `Autoreloader` (gun reload) | `dc_sextant`, `dc_dawnfix`, `dc_sunward` | `size` 2 / 3 / 3, `perShellReloadS` {9.0, 7.5} / {11.0, 8.0, 7.6} / {12.5, 9.4, 9.0} in refill order after the magazine empties, `intraClipS` 2.0; firing never resets a slot |
| `Wheeled` | `ea_rhuvari`, `ea_lirvari` | `wheelPairs` 4, `speedModeTopSpeedMul` 1.30, `speedModeSteeringMul` 0.60, `speedModeReverseMul` 0.70, `toggleS` 1.0, `lostPairSpeedMul` 0.75 (per destroyed wheel **side**: each side's wheels are one `TrackLeft`/`TrackRight` module, content-schema §5.5), `movingDispersionMul` 1.15, `turnRadiusM` 8 / 9; `visual.running.roadWheels` = 4, no `mobility.pivot` |
| `Hydropneumatic` | `mr_highcol`, `mr_tarnwatch`, `mr_cragline` | `depressionBonusDeg` 4, `elevationBonusDeg` 3, `settleS` 0.75 (bonus after 0.75 s with hull speed < 0.5 km/h, lost the moment it moves; gun arcs only, the hull never pitches, §1.5) |
| `SiegeMode` | `mr_tarnhold`, `mr_peakhold` | `engageS` 2.0, `disengageS` 1.25, `maxSpeedKmh` 10, `autoEngageS` 0.5 (player option), `travelReverseRatio` 0.9, `modifiers` while sieged (`StatModifier`s): `aimTime` mul 0.4, `dispersion` mul 0.85, `gunDepression` add 8, `gunElevation` add 6, `hullTraverse` mul 0.5. The outrigger-leg visual follows the replicated siege phase (§1.5) |

The Wheeled speed mode multiplies the forward top speed **after** equipment (Turbo Kit +5 km/h slotted), so the
fastest legal case is (70 + 5) × 1.30 = 97.5 km/h (R6).

### 2.11 Tech-tree layout (`tree.row`)

Rows are fixed per faction for every designed branch, including W2/W3 ones, so later waves never move a W1 node
(ui-ux §S10 lanes). Row 2 is always the spine; the Iron Foundry trunk already ships as row 2.

| Faction | Row 1 | Row 2 (spine) | Row 3 |
|---|---|---|---|
| Iron Union | `iu_ram` TD IV–X (W2) | `iu_foundry` I–III → `iu_bulwark` IV–XI | `iu_hammer` MT IV–X (IX–X in W1) |
| Crown Industries | `ci_herald` LT V–X (W3) | `ci_guild` I–IV → `ci_warden` V–X | `ci_vernier` TD IV–XI (IX–XI in W1) |
| Eastern Armor Group | `ea_gale` MT V–X (W2) | `ea_skirmish` I–XI | `ea_outrider` LT VII–X (IX–X in W1) |
| Desert Armor Corps | `dc_glint` TD V–X (W2) | `dc_caravan` I–III → `dc_longshot` IV–XI | `dc_sunfall` SPG IV–X |
| Mountain Republic | `mr_scree` LT IV–X (W2) | `mr_pathfinder` I–III → `mr_ridgeline` IV–XI | `mr_bastion` TD IV–X (IX–X in W1) |
| Northern Federation | `nf_aurora` SPG IV–X (W3) | `nf_frontier` I → `nf_glacis` II–X | `nf_rimeguard` HT IV–XI (IX–XI in W1) |

Premiums sit in the separate premium lane under the dashed divider (ui-ux §S10) and carry no `tree.row` collision:
their files set `tree = { row = 4 }` and **no** `branch` (the parenthesised branch in the §2 tables is the crew line
the premium trains, shown on its Store page, not tech-tree membership). Apexes sit on their parent's row in the XI
column (`iu_gorrtund`, `ea_lirvesh`, `dc_zenith`, `mr_updraft` row 2; `ci_aurelline`, `nf_rimeburst` row 3).

### 2.12 Internal layout and ammunition (where each faction's weak points live)

`VisualSpec.layout` decides which hits detonate, burn or immobilise (decisions §2 modules; R14 makes every one of
them visible in the Armor Inspector). Each faction has a **must / never** rule; anything not named is the author's
choice. The shipped Iron I–III files comply.

| Faction | Must | Never | The weak point players learn |
|---|---|---|---|
| Iron Union | engine `Rear`; racks in the hull (`HullMiddle`, `Sponsons` or `Floor`) | `Turret`, `Bustle` racks | Side and sponson pens detonate; the turret never does |
| Crown Industries | racks `Bustle` on turreted vehicles, `Sponsons` on casemates | `Floor` racks | Bustle and casemate-flank pens detonate (§1.2) |
| Eastern Armor Group | engine `Rear`, fuel `Front`; racks `Turret` (the drum on magazine vehicles) | `Floor` racks | Frontal pens start fires; ×0.80 turrets put the rack at risk |
| Desert Armor Corps | fuel `Front`, behind the ×0.85 lower plate; racks `Bustle` on autoreloaders, else `HullMiddle` | — | A lower-plate pen burns; the magazine bustle detonates |
| Mountain Republic | engine `Front` (the rear turret or gun block leaves the bow free), fuel `Sides` | `Bustle` racks | A frontal hull pen hits the engine: cresting carelessly costs mobility |
| Northern Federation | racks `Floor`; engine and fuel `Rear` | `Turret`, `Bustle` racks | The safest racks in the game; rear and engine-deck hits burn |
| Sunfall SPGs | engine `Front`; racks `HullMiddle` (IV–VIII), `Turret` (IX–X) | — | Fragile anyway (HP ×0.30); flank hits stop the gun |

**Ammunition capacity** (O, authoring band for `GunDefinition.ammoCapacity`): at least
`max(25, ⌈5 × MT HP(T) ÷ standard α⌉)` and at most 4 × that minimum, so a vehicle can always deal five times a
same-tier medium's HP and never carries an unlimited supply. Magazine and Autoreloader capacities are whole
multiples of the magazine size; DualGun capacities are even; SPG howitzers carry 20–40 shells. Examples: `iu_gun_37mm`
(α 40) 35–140, shipped 120; `iu_gun_76mm` (α 75) 30–120, shipped 70.

---

## 3. Class and role coverage, matchmaking implications

### 3.1 Class × tier supply (W1, premiums included)

| Tier | LT | MT | HT | TD | SPG | Total | Thin cells (1 vehicle) |
|---|---|---|---|---|---|---|---|
| I | 3 | 3 | – | – | – | 6 | – |
| II | 3 | 2 | – | 1 | – | 6 | TD |
| III | 2 | 3 | – | 1 | – | 6 | TD |
| IV | 1 | 3 | 1 | 1 | 1 | 7 | LT, HT, TD, SPG |
| V | 2 | 2 | 2 | 1 | 1 | 8 | TD, SPG |
| VI | 1 | 2 | 2 | 2 | 1 | 8 | LT, SPG |
| VII | 1 | 2 | 2 | 1 | 1 | 7 | LT, TD, SPG |
| VIII | 2 | 3 | 3 | 2 | 1 | 11 | SPG |
| IX | 2 | 3 | 3 | 3 | 1 | 12 | SPG |
| X | 2 | 3 | 3 | 3 | 1 | 12 | SPG |
| XI | 1 | 2 | 2 | 1 | – | 6 | LT, TD |
| **Total** | **20** | **28** | **18** | **16** | **7** | **89** | |

Heavies start at Tier IV by roster choice (`Classes.luau` allows III, but no Tier III heavy is designed, so none can
appear there), destroyers at II and artillery at IV (decisions §7.4); Tier I has only lights and mediums. Every class
exists at every tier where the roster fields it, so the class mirror (decisions §8) can always be completed by bots.

### 3.2 Role coverage (who can fill a role-mirrored bot slot)

Faction codes: IU, CI, EA, DC, MR, NF; P = premium; W = Wheeled.

| Tier | LT | MT | HT | TD | SPG |
|---|---|---|---|---|---|
| I | Vers CI, EA · Scout MR | Vers IU, DC · Assault NF | – | – | – |
| II | Scout CI, EA · Vers MR | Assault IU · Support DC | – | Support NF | – |
| III | Scout EA, MR | Vers IU · Sniper CI, DC | – | Sniper NF | – |
| IV | Support EA | Support CI · Vers DC, MR | Vers IU | Vers NF (turret) | AreaControl |
| V | Vers EA · Support EA-P | Sniper DC, MR | Assault IU · Breakthrough CI | Assault NF | Support |
| VI | Scout EA | Assault DC · Vers MR | Support IU · Vers CI | Assault NF · Support CI-P | AreaControl |
| VII | Support EA | Sniper DC · Support MR | Breakthrough IU · Support CI | Support NF | Support |
| VIII | Scout EA, MR-P | Vers DC · Sniper MR · Support DC-P | Vers IU · Support CI · Assault NF-P | Assault NF · Vers IU-P (turret) | AreaControl |
| IX | Support EA · Vers EA-W | Vers IU · Assault DC · Sniper MR | Assault IU · Vers CI, NF | Sniper CI, MR · Assault NF | Support |
| X | Vers EA · Scout EA-W | Assault IU · Sniper DC · Vers MR | Assault IU · Support CI · Breakthrough NF | Sniper CI · Support MR · Assault NF | Support |
| XI | Support EA | Sniper DC · Vers MR | Assault IU · Breakthrough NF | Sniper CI | – |

All 17 roles appear in W1. Role mirroring is soft (decisions §8), so a missing exact role costs only the
`roleErr` penalty. For that penalty the bot picker should use the `RoleGroup` of each role in `Roles.luau`:
*Frontline* (medium/heavy/td assault, heavy breakthrough) · *Ranged* (medium and td sniper) · *Support* (all four
support roles) · *Versatile* (all four versatile roles) · *Recon* (light scout) · *Indirect* (both artillery roles).
Proposed scoring for `Matchmaking.luau`: exact role 0, same group 0.5, otherwise 1.

### 3.3 Supply per battle bracket

A battle draws from up to three tiers (templates 3/5/7, 5/10, 15; spread rules decisions §8), so the real pool is
larger than one tier column. Vehicles available to a battle whose top tier is T, using the widest legal template:

| Top tier (tiers in battle) | LT | MT | HT | TD | SPG | Pool |
|---|---|---|---|---|---|---|
| I (I only) | 3 | 3 | – | – | – | 6 |
| II (II only) | 3 | 2 | – | 1 | – | 6 |
| III (III only; II is single-tier) | 2 | 3 | – | 1 | – | 6 |
| IV (IV–III) | 3 | 6 | 1 | 2 | 1 | 13 |
| V (V–IV; III–IV vehicles are ±1) | 3 | 5 | 3 | 2 | 2 | 15 |
| VI (VI–V) | 3 | 4 | 4 | 3 | 2 | 16 |
| VII (VII–V) | 4 | 6 | 6 | 4 | 3 | 23 |
| VIII (VIII–VI) | 4 | 7 | 7 | 5 | 3 | 26 |
| IX (IX–VII) | 5 | 8 | 8 | 6 | 3 | 30 |
| X (X–VIII) | 6 | 9 | 9 | 8 | 3 | 35 |
| XI (XI–X) | 3 | 5 | 5 | 4 | 1 | 18 |

### 3.4 Matchmaking and bot-fill rules this roster needs

1. **Caps are always satisfiable.** LT ≤ 3 with Wheeled ≤ 1: Wheeled LTs exist only at IX–X, and each of those
   tiers also has a tracked LT (`ea_zarett`, `ea_talzarett`), so a bot never needs a second Wheeled vehicle.
   TD ≤ 4 and SPG ≤ 2 are within supply at every bracket.
2. **Bots never introduce artillery.** A bot takes an SPG slot only to mirror a human SPG on the other team.
   With one SPG per tier, that bot is the same vehicle the human drives; that is intended (a true mirror).
3. **Default bot class mix** when no human constrains a team (proposal), per 15, sized to supply so a thin cell is
   not copied four times: Tier VIII+ MT 5, HT 4, TD 3, LT 3 · VI–VII MT 6, HT 3, TD 3, LT 3 · IV–V MT 7, HT 2,
   TD 3, LT 3 · II–III MT 10, LT 3, TD 2 · I MT 12, LT 3 (the LT cap of 3 binds). SPG slots appear only to mirror
   a human SPG (rule 2) and replace one MT. Humans' classes replace these slots one for one; class slots are placed
   on the tier rows of the template where that class exists (HT never on a Tier III row).
4. **Variety:** within a team, bots field at most 2 copies of one vehicle while another vehicle of the same tier,
   class and role group exists; the hard cap per vehicle is max(3, ⌈class slots ÷ vehicles of that class in the
   template⌉), which is 4 for Tier I mediums (12 slots, 3 vehicles) and Tier III-only mediums (10 slots,
   3 vehicles), 5 for Tier II mediums (10 slots, 2 vehicles) and 3 everywhere else. When the cap blocks a slot, the bot takes the same class one tier lower inside the template, else
   the nearest legal class. Bots pick factions uniformly at random among eligible vehicles and may use premiums
   (they are inside the balance envelope and never get MM preference).
5. **Thin cells to watch** (single vehicle at that tier and class): TD II–V and VII, LT IV/VI/VII, HT IV, all SPG,
   LT and TD at XI. Telemetry per (tier, class): human pick share, bot duplicate rate and win rate. If a thin cell
   carries more than 30 % of the class's bot fills at its tier, it goes up the W2 priority list (§6.1).
6. **Tier XI** meets only X–XI. A human XI LT is mirrored by a bot `ea_lirvesh`; once the class mirror relaxes to
   ±1 (decisions §8), an LT in a Tier X slot may stand in.
7. **Starter spread:** all six Tier I starters are free and balanced to the same envelope (every core stat at lint
   ratio 1.00 ± 0.03 of its own class × role × kit target, §5.4); they differ by class, role and kit, never by
   power level, so a new player's faction choice is a matter of taste. Tier I–II MM is single-tier (decisions §8),
   so supply per battle at I is 6 vehicles; bots there use Recruit skill for the first 20 battles.

---

## 4. Naming conventions and lore

### 4.1 Rules for every name

* **Shape:** one word, 4–11 letters, Title Case, pronounceable on first sight by a ten-year-old reader. No digits,
  no letter-number designations, no "Mk", no hyphenated codes. The id is the lowercase name with the faction
  prefix (`iu_tukkhald`), so names are unique game-wide. `shortName` = `name` for every W1 vehicle (the longest,
  *Cairnhopper* and *Thawbreaker*, have 11 characters, inside the 12-character marker and kill-feed limit, content-schema §5.1).
* **Three constructed tongues, three English patterns.** Iron Union, Crown Industries and Eastern Armor Group use
  invented morphology (exotic flavour); Desert, Mountain and Northern use English compound patterns (instant
  readability). Every name follows its faction's morphology so a player can guess the faction, and often the
  class, from the name alone.
* **IP screen (brand §1.1, mandatory before a name ships):** no real vehicle names or nicknames (including animal
  and myth names commonly used by real or game vehicles: big cats, badgers, bulldogs, rhinos, mythic beasts,
  famous knights and rulers), no real designations, no real places, people, units or operations, no WoT map
  names, no real star names, and nothing primarily known as a brand, product, title or place, real or fictional
  (ordinary dictionary words such as *Zenith*, *Meridian* or *Talus* are allowed because their main meaning is the
  word itself; *Emberfall* was dropped because it is best known as a fictional kingdom, and *Starfall* because it is a
  fictional castle and a game spell). Search the exact name plus
  "tank" and plus "game" before approval. Constructed words must not be common words, names or trademarks in a major
  language (dictionary lookup); obscure technical terms with no unwanted meaning are tolerated (*Calibrant* is a
  laboratory term).
* **No collisions:** a vehicle name never repeats a branch name (the Sunfall line's VIII is *Flarefall*, the Glacis
  line's IX is *Driftwall*), so "the Sunfall" always means one thing in UI and chat.
* **Localisation:** names are proper nouns and are never translated; lore is translated. Reserve 35 % slack for
  lore lines (brand §2).
* **UI:** names in body text are Title Case; destructive confirmations use UPPERCASE (`SELL TUKKHALD`). Brand §2's
  `SELL AVR-4 LANCER` and `T-IV` are layout placeholders; shipped names follow this section.

### 4.2 Faction tongues

**Iron Union: Forgecant (constructed).** Closed, heavy syllables; stops k g t d b with r and l; vowels a o u;
doubled finals allowed (kk, rr, ll); never ends in -ov, -ev, -in, -sk, -ski or -grad (keeps it clear of real-language
look-alikes). Order: modifier + head; the **head marks the class**. A morpheme may also stand as a modifier
(*Varrhald* "ram wall", *Tundmal* "anvil hammer"), so only the last morpheme carries the class.

| Morpheme | Gloss | Morpheme | Gloss |
|---|---|---|---|
| kol | coal | mal | hammer (head: **MT**) |
| ost | rivet | hald | wall (head: **HT**) |
| bul | bellows | varr | ram (head: **TD**) |
| brakk | iron | tukk | twin (prefix: the first two DualGun heavies; the Tier X keeps the plain *Durhald*) |
| tund | anvil (head: **HT**, the heaviest of a line: the IX twin-gun and the Apex) | gorr | furnace (prefix: **Apex**) |
| dur | enduring | tamm | tempered (prefix: **premium**) |

Examples: *Tukkhald* "twin wall", *Tukktund* "twin anvil", *Gorrtund* "furnace anvil", *Tammvarr* "tempered ram".

**Crown Industries: Guildtongue (constructed, Latinate).** Soft, polished, open syllables (v l r n s d); never a
real Latin word or a brand. The **ending marks the class**: -elle LT, -ant MT, -ion HT, -ine TD; Apex prefix
*Aurel-*.

| Morpheme | Gloss | Morpheme | Gloss |
|---|---|---|---|
| vern | true | calib | gauge |
| gard | keep, guard | ster | steady |
| ord | order | regn | rule |
| sov | high | tessel | inlay |
| prec | exact | aurel | gilded (Apex) |

Examples: *Tesselion* "the inlaid bastion", *Precine* "the exact one", *Aurelline* "the gilded one".

**Eastern Armor Group: Windtongue (constructed).** Light syllables with k z v s l r and the vowels i e a; modifier
first. Suffixes: **-ett** "little one" (LT), **-vari** "roller" (Wheeled), **-zar** "strike" (premium), **-ane**
reserved for mediums (W2). The **Apex carries no class suffix** (*Lirvesh* "sky-swift"); *lir* "sky" also appears
as an ordinary modifier (*Lirett*, *Lirvari*), so the missing suffix, not the prefix, marks the Apex.

| Morpheme | Gloss | Morpheme | Gloss |
|---|---|---|---|
| kir | wing | sev | spear |
| ess | feather | ven | wind-shadow |
| vesh | swift | sil | glide |
| tal | talon | rhu | gust |
| zar | strike | lir | sky |

Examples: *Talzarett* "little talon-strike", *Rhuvari* "gust roller", *Lirvesh* "sky-swift".

**Desert Armor Corps: Navigator's cant (English).** Survey, navigation and sky words: tanks are instruments and
fixes (*Waymark, Bearing, Sandglass, Parallax, Azimuth, Meridian, Longsight, Sextant, Dawnfix, Sunward*), the Apex
is the top of the sky (*Zenith*), artillery is **"-fall"**, what comes down from the sky (*Dustfall, Ashfall, Sparkfall, Glassfall, Flarefall,
Dewfall, Noonfall*),
premiums are light words (*Dunelight*). W2 destroyers will use glare words (*-glint*).

**Mountain Republic: Highland cant (English).** Lights are a landform plus a nimble animal (*Screehare,
Cairnhopper, Ridgewren, Highstag*); mediums are single landform terms (*Talus, Saddleback, Cornice, Scarp, Highcol,
Tarnwatch, Cragline*); siege destroyers end in **"-hold"** (*Tarnhold, Peakhold*); the Apex is moving air
(*Updraft*).

**Northern Federation: Rimespeech (English).** Weather and ice: the starter is a **"-ling"** (*Hoarling*); the
II–IV destroyers are small ice and weather (*Icepick, Sleet, Hailstone*); the V–X casemates are **"-crag/-wall"**
(*Rimecrag, Floewall, Rimewall, Hoarwall, Driftwall, Winterwall*); heavies are storms (*Whiteout, Deepwinter*);
premiums are **"-breaker"** (*Thawbreaker*); the Apex is **"Rime-"** plus a verb (*Rimeburst*), while "Rime-" plus a
noun is a casemate.

### 4.3 Lore snippets

Lore appears in the About Vehicle overview and the tech-tree tooltip (`vehicle.<id>.lore`). Two or three
sentences, present tense for what the vehicle does, past tense for how it came to be (§0.4 tone).

**Iron Union**
* `iu_kolmal` — The first Cinderbelt foundries bolted armor plate onto plough tractors to clear the proving fields. The Kolmal kept the tractor's patience and its stubbornness, and every Iron Union crew still learns to angle in one.
* `iu_ostmal` — Foundry crews wanted a tank that could knock down a gate in one blow. The Ostmal's short gun and stepped glacis were cast in the same shop that made the furnace doors of the Cinderbelt.
* `iu_bulmal` — Bulmal crews were the first to trust a cast dome. The foundry poured it in one piece, and the Marshals of the Trials logged it turning away shot after shot on the open flats.
* `iu_osthald` — When the Trials first admitted heavy classes, the Union welded its thickest boiler plate into a box and called it a wall. The Osthald is that box, honest and slow, and it taught a generation to keep its front toward the enemy.
* `iu_brakkhald` — The Slagmasters' council argued for a year about the Brakkhald's gun and then fitted both candidates. Its crews still argue about which one was right.
* `iu_kolhald` — The Kolhald brought the cast dome to the heavies, a turret the foundries could pour in a single night shift. It also carried the longest gun yet fitted to a Union heavy, which made its gunners briefly famous for hitting things at range.
* `iu_varrhald` — The pike nose came from a shipwright who joined the Cinderbelt works and asked why tanks were flat at the front. The Varrhald proved him right, and every Union heavy since has kept the ridge.
* `iu_tukkhald` — Two guns on one mantlet was a foundry joke until the Tukkhald's trials crew landed both shells on the same plate. The joke became doctrine within a season.
* `iu_tukktund` — The Tukktund adds cheek armor and a heavier dome to the twin-gun idea, at the cost of almost everything else. Its crews say it does not need to move fast, because the enemy comes to it.
* `iu_durhald` — The Durhald is the Union's answer to every question asked at the Marshal's Fields: thicker, heavier, twice. Both barrels come from the same pour, so they wear and shoot as one.
* `iu_tundmal` — Tundmal crews describe it as a heavy that forgot to stop growing. A medium chassis carries a turret cast for something much bigger, and the Union never saw a reason to apologise.
* `iu_brakkmal` — The Brakkmal was built to break the line itself, not to wait behind it. Its turret is the heaviest ever mounted on a Union medium, which is why it cannot look down a slope to save its life.
* `iu_tammvarr` — The Tammvarr is an export pattern: lighter, quicker, with a rotating mount for buyers who did not want to point the whole vehicle. Union crews call it soft and secretly love the turret.
* `iu_gorrtund` — Furnace Number One at Kolvenn was relit for a single casting: the Gorrtund's gun. It takes a breath before it fires, and so does everyone in front of it.

**Crown Industries**
* `ci_vernelle` — Every Crown apprentice starts in the Vernelle, a polished little scout whose gun was bored on the lathes that make the guild's survey instruments. It is the most accurate thing at its tier, and it knows it.
* `ci_gardelle` — The Gardelle's periscope mast was borrowed from the Gilt Coast lighthouse service. It spots the enemy first and leaves the shooting to someone better armed.
* `ci_ordant` — The Ordant was the first Crown vehicle built around a single rule: the gun clears the crest before the hull does. Its tall turret looks awkward in the hangar and perfect on a ridge.
* `ci_calibrant` — Calibrant gunners train to a metronome. The guild measured that a steady stream of small shells wins more Trials than one big one, and built a tank to prove the sums.
* `ci_gardion` — The board asked for a heavy; the engineers delivered a fast one and called the armor "sufficient". The Gardion has been winning arguments about speed ever since.
* `ci_sterion` — The Sterion's turret is so tall that the guild had to raise the gates of its own assembly hall. In exchange it can tuck its hull behind almost any crest on the Gilt Coast.
* `ci_ordion` — An Ordion's long bustle holds its ammunition, the gunner's range tables and the crew's tea kit. Crews guard it accordingly, because a hit there ends the day.
* `ci_regnion` — The Regnion carried the first Crown squash-head rounds, shells that flatten against a plate and shake it from the inside. Its crews learned to read the armor before they chose the shell.
* `ci_sovrion` — The Sovrion added skirts and a thicker turret after the board watched one too many Wardens give up a ridge. It holds a crest now, politely and for a long time.
* `ci_tesselion` — The Tesselion's gun is inlaid along its length with the names of every machinist who fitted it, a guild tradition for flagship work. It is the most accurate heavy gun on the continent.
* `ci_precine` — The Precine is "a measuring instrument with a gun attached", or so its designers said at the unveiling. It sits low, waits, and puts its first shell exactly where the gunner intended.
* `ci_vernine` — The Vernine was built to settle disputes at the longest range the Marshals allow. Its armor is a formality; its optics took three years to grind.
* `ci_calibine` — The Calibine began as a guild training piece for destroyer gunners and proved too pleasant to retire. It fires fast, hits lightly and pays its way.
* `ci_aurelline` — The Aurelline's casemate sides open into cooling louvres that let the gun fire faster for a few seconds without warping. The board approved it on condition that it is never called a prototype in public.

**Eastern Armor Group**
* `ea_kirett` — The Kirett was a herder's runabout until a clan workshop bolted a gun to it. It is still the quickest way across a Long Grass pasture.
* `ea_essett` — Essett means "little feather", and it moves like one: low, quiet and gone before the grass stops swaying.
* `ea_veshett` — The Veshett moved its turret forward so the driver could see past it. That made it faster to read the ground, and faster to leave it.
* `ea_talett` — Clan gunsmiths fitted the Talett with the biggest gun its frame could carry and dared anyone to call it a scout. It is a scout that bites.
* `ea_sevett` — The Sevett was the first Eastern light to outrun the plains' spring winds at full throttle. Its turret turns quicker than an enemy can follow.
* `ea_venett` — The Venett hides in the wind-shadow behind a hill, where the grass lies still. Crews say you can lose one in a field you are standing in.
* `ea_lirett` — The Lirett's long gun was designed to fire from the flank of a convoy at whatever was chasing it. It rarely fires twice from the same place.
* `ea_silett` — The Silett was built for the Long Grass relays, where crews carry orders across a hundred kilometres before noon. In the Trials it simply arrives first.
* `ea_zarett` — The Zarett carries four shells in a drum and fires them before its target has finished turning. Then it runs, because the drum takes half a minute to refill.
* `ea_talzarett` — The Talzarett gives up one shell of its drum for a heavier gun and a quicker hand between rounds. Eastern crews call the volley "the stoop", after a falcon's dive.
* `ea_rhuvari` — Clan engineers asked why a scout needed tracks on roads that run for days. The Rhuvari rolls on eight wheels and shifts into a road gear that leaves tracked vehicles behind.
* `ea_lirvari` — The Lirvari is the fastest vehicle ever entered in the Trials; the Marshals timed it twice to be sure. It sees everything and carries a gun mostly for emergencies.
* `ea_sevzar` — The Sevzar is a clan champion's personal machine: a scout hull under an oversized turret, with the attitude to match. It suits crews who prefer to finish what they spot.
* `ea_lirvesh` — The Lirvesh's drum can be topped up whenever its loader chooses, so it never sits out a full reload with shells still to spare. The clans call it "the sky that does not blink".

**Desert Armor Corps**
* `dc_waymark` — Caravan guards built the Waymark from a supply tractor and a canvas sunshade. Its gunner sights from the shade, which is the first lesson of the Erg.
* `dc_bearing` — The Bearing was the Corps' first purpose-built tank, made to keep up a steady fire while the caravan moved on. Its short skirts keep sand out of the running gear.
* `dc_sandglass` — Named for the timer every Corps navigator carries, the Sandglass was the first to put a long gun on a small hull. Its tall cupola lets the commander see over the dunes, and lets the enemy see the commander.
* `dc_parallax` — The Parallax introduced the Corps' signature turret: strong enough to hold a dune crest, set over a hull that should never crest one. Its crews learn to read sand slopes before they learn to drive.
* `dc_azimuth` — Azimuth crews compete in the Erg range trials, where targets stand five hundred metres out in shimmering air. The best of them chalk their hits on the barrel.
* `dc_meridian` — The Meridian thickened the turret so a crew could stay on a crest under fire instead of ducking after every shot. It is the Corps' answer to anyone who calls them timid.
* `dc_longsight` — The Longsight carries two rangefinder arms that its crews call its ears. It finds its own targets and rarely needs a second shot.
* `dc_sextant` — The Sextant's two-round loader lets a gunner fire, re-sight and fire again before dropping below the crest. The Corps calls it "taking two bearings".
* `dc_dawnfix` — Dawnfix crews attack at first light with the sun behind them and three shells ready in the bustle. The loader works through the long refill afterwards, in the shade.
* `dc_sunward` — The Sunward is the Corps flagship, built to own any sightline on the Amberline Erg. Three thermal sleeves keep its barrel true in the noon heat.
* `dc_dustfall` — The Dustfall is a light howitzer on a caravan chassis, open to the sky. Its shells raise more dust than damage, which is exactly what its first crews wanted.
* `dc_ashfall` — The Ashfall's shells leave a ringing that slows a crew for a few seconds. The Marshals call it "stun" and allow it; the receiving crews have other words.
* `dc_sparkfall` — Sparkfall batteries fire and move before the dust settles, because every shot tells the enemy where they are. Crews time each relocation with the sand timer on the dashboard.
* `dc_glassfall` — The Glassfall's heavy shells fuse sand into glass where they land, leaving glittering craters across the Erg ranges. It is slow, loud and impossible to ignore.
* `dc_flarefall` — The Flarefall's long barrel throws a flatter, faster shell that can catch a moving target. Its crews track vehicles across the dunes the way navigators track a star.
* `dc_dewfall` — Corps gunners named it for the cold hour before dawn, when dew settles on the Erg and the night batteries go to work. The Dewfall puts its howitzer in a turret that turns all the way round, so one battery can watch two valleys, and it is the first Corps gun its crews describe as comfortable.
* `dc_noonfall` — The Noonfall is the heaviest howitzer the Corps brings to the Trials; its crews say you hear it before the shadow of the shell arrives. It never stays in one place for long.
* `dc_dunelight` — The Dunelight is an escort tank sold to the caravan houses: simpler than the Corps' loaders and cheaper to run. Escort crews like that it fires as fast as they can feed it.
* `dc_zenith` — The Zenith holds its breath before the shot while a stabilised mount settles the barrel. At the top of the sky, the Corps says, nothing can hide.

**Mountain Republic**
* `mr_screehare` — Valley postmen built the first Screehare to carry mail up scree slopes no mule would try. It still climbs like it has somewhere to be.
* `mr_cairnhopper` — Cairnhopper crews mark their routes with stone cairns, a habit as old as the Cantons. Its raised idler takes a 35-degree slope at speed.
* `mr_ridgewren` — The Ridgewren moved its turret to the back of the hull so the gun could look over a crest while the rest of it hid. Every Republic medium since has copied the trick.
* `mr_talus` — Talus is the loose rock at the foot of a cliff, and the Talus is just as hard to pin down. It is the first Republic medium, and its armor is mostly an apology.
* `mr_saddleback` — The Saddleback fights from the low pass between two peaks, where it can shoot down either valley. Its crews know every saddle in the High Cantons by name.
* `mr_cornice` — A cornice is the lip of snow on a ridge, and the Cornice likes to sit just behind one. It shifts between ridges faster than an enemy can re-aim.
* `mr_scarp` — The Scarp was built for long sentry duty on the cliff roads, firing steadily from hidden ledges. It is the thinnest medium in the Trials and the hardest to find.
* `mr_highcol` — The Highcol's suspension settles and lets its gun dip lower than any other medium's, so it can reach the valley floor from the crest. Crews call the move "bowing to the valley".
* `mr_tarnwatch` — Tarnwatch crews keep watch over the mountain lakes from rock shelves high above them. Long guns and longer patience make them the Republic's favourite overwatch.
* `mr_cragline` — The Cragline is the Republic's flagship medium, fast enough to cross a valley between shots and low enough to vanish on the far side. Its hull is thin, so its crews never let anyone see it.
* `mr_tarnhold` — The Tarnhold has no turret: its gun sits in a low armored block at the back of the hull and reaches far over the bow. In travel it runs; in siege it plants its two legs and settles like a boulder that shoots.
* `mr_peakhold` — The Peakhold was designed to hold a pass alone for an afternoon. It reloads quickly, deploys quickly, and leaves quickly when the afternoon is over.
* `mr_highstag` — The Highstag is a mountain guide's machine sold to Canton patrols, built to reach a peak first and report what it sees. Its narrow nose threads trails no other vehicle can.
* `mr_updraft` — The Updraft carries two rocket pods that drive the tank up a slope in seconds. The Republic's engineers call it "cheating the mountain", and they are proud of it.

**Northern Federation**
* `nf_hoarling` — Every Federation settlement keeps a Hoarling to clear its roads after a storm. It was the first vehicle the Federation sent to the Trials, and it still pushes through anything.
* `nf_icepick` — The Icepick is a field gun bolted to a sled-hauler chassis, built to guard supply routes across the frozen bays. It fires quickly and expects to move.
* `nf_sleet` — The Sleet closed its gun crew into a low steel box against the wind. Dug into a snowdrift, it is almost invisible until it fires.
* `nf_hailstone` — Hailstone crews wanted a destroyer that could turn its gun without turning in the snow. The answer was an open hexagonal turret that tracks targets across the ice.
* `nf_rimecrag` — The Rimecrag was the first Federation casemate meant to lead from the front. Its sloped face copies the shape of a pressure ridge on the sea ice.
* `nf_floewall` — The Floewall is named for the walls of pack ice that close a harbour each winter. In the Trials it closes lanes the same way.
* `nf_rimewall` — The Rimewall is the Federation's lighter casemate, built to move between positions the heavier walls cannot reach. It trades armor for a quick hand at the breech.
* `nf_hoarwall` — The Hoarwall's glacis runs in one unbroken slope from nose to roof, so snow and shells slide off alike. Its crew compartment is heated, which its crews mention often.
* `nf_driftwall` — The Driftwall is named for the snowdrifts that bank metres deep against the Pale Reaches sea walls each midwinter. Its casemate face is the thickest the Marshals accept at its weight; its one weakness is the cupola, which the commander refuses to give up.
* `nf_winterwall` — The Winterwall is the Federation's flagship destroyer: slow, enormous and almost impossible to stop from the front. Federation crews say winter always wins in the end, and so do they.
* `nf_whiteout` — The Whiteout's hexagonal turret is cast to the pattern of the Federation crest. Built for blizzards, it shrugs off damage that would stop any other heavy of its weight.
* `nf_deepwinter` — The Deepwinter trades the Federation's thickest plates for an engine that keeps moving in the worst storms. It breaks the lines the walls have held.
* `nf_thawbreaker` — Thawbreakers clear the river ice each spring and fight in the Trials for the rest of the year. Slow and sturdy, it is sold to crews who like to come home.
* `nf_rimeburst` — The Rimeburst's engine can run past its limit for a few seconds, its exhaust heaters glowing white. In that moment nothing in the Trials is harder to stop.

---

## 5. Balance intent per tier

### 5.1 How a content author derives a vehicle's numbers

```
target(stat, vehicle) = MT_baseline(stat, tier)          -- decisions §7.4 table
                      × class multiplier                  -- §7.1
                      × role trim                         -- §7.2 (SPG trims: §2.4 proposal)
                      × faction kit                       -- §7.3
                      × mechanic factor                   -- Magazine 0.85 / Autoreloader 0.92 sustained DPM; DualGun per-barrel 2.3 × reload
```

Tier XI uses the MT baseline's XI row (§2.7). Kits and role trims are **lint-only** (`Factions.luau` `kit`,
`Roles.luau` `trims`, content-schema §3.1): authors bake them into module and hull numbers; nothing multiplies them
at runtime.

Author the **top configuration** to the target. The stock configuration is then derived (top ÷ stock): standard pen
×1.20, power-to-weight ×1.15, aim time ×0.95, dispersion ×0.95, turret traverse ×1.10, hull traverse ×1.08, HP ×1.05
where a turret upgrade exists; speed unchanged; stock gun alpha 0.85–1.0 × top. **Stock effectiveness** is the mean
of (stock ÷ top standard pen) and (stock ÷ top power-to-weight) = (0.833 + 0.870) ÷ 2 ≈ 0.85, the decisions §7.4
"stock ≈ 85 %"; R12 bounds it.

The balance lint divides each core stat (HP, alpha, pen, DPM, speed, hull traverse, dispersion) by the target:
outside **[0.85, 1.15] fails**, outside [0.92, 1.08] warns unless the vehicle declares `balanceException` with a
reason. Every "combat identity" claim in §2 that needs a stat beyond ±8 % (for example `iu_durhald`'s 0.87 DPM, which
comes from the DualGun factor and is therefore *inside* the target) must be traceable to a multiplier, never to a
hand-tuned number. **Percentiles** of the envelope are read linearly on the lint ratio: P40 = 0.97, P45 = 0.985,
P55 = 1.015, P60 = 1.03. Premiums (`premium = true`) follow §2.8; vehicles alone in their (tier, class) cell follow
R13; every other tech-tree vehicle may use the whole warn band.

### 5.2 Firepower bands (class baselines before role and kit)

**Standard-shell alpha** (special shells same alpha; HE = min(1.30 × standard alpha, the shell cap below); HESH as HE)

| Tier | LT | MT | HT | TD | SPG (HE) |
|---|---|---|---|---|---|
| I | 34 | 40 | – | – | – |
| II | 43 | 50 | – | 75 | – |
| III | 51 | 60 | – | 90 | – |
| IV | 72 | 85 | 106 | 128 | 170 |
| V | 98 | 115 | 144 | 173 | 230 |
| VI | 136 | 160 | 200 | 240 | 320 |
| VII | 187 | 220 | 275 | 330 | 440 |
| VIII | 221 | 260 | 325 | 390 | 520 |
| IX | 272 | 320 | 400 | 480 | 640 |
| X | 340 | 400 | 500 | 600 | 800 |
| XI | 374 | 440 | 550 | 660 | – |

**Single-shell alpha cap** (red flag R1). The maximum roll (×1.25) of any one direct-fire shell, after ChargedShot,
must stay below the HP of the weakest light it can meet, i.e. the base LT HP at the bottom of its tier's matchmaking
spread (I–II single tier, III meets III–IV, IV meets III–V, V meets IV–VII, VI meets V because Tier IV vehicles stay
within ±1, VII–X meet T − 2, XI meets X). Cap =
⌊(LT HP − 1) ÷ 1.25⌋. Bursts (DualGun volleys, magazines, autoreloaders) are bounded by R2 instead, and artillery by
its direct-hit clamp (§1.4).

| Tier | I | II | III | IV | V | VI | VII | VIII | IX | X | XI |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Weakest LT met (HP) | I (224) | II (288) | III (352) | III (352) | IV (424) | V (512) | V (512) | VI (656) | VII (848) | VIII (1,080) | X (1,560) |
| Shell alpha cap | 178 | 229 | 280 | 280 | 338 | 408 | 408 | 524 | 677 | 863 | 1,247 |

The cap binds only on destroyer HE: TD HE rounds from Tier VII up are authored at min(1.30 × AP, cap). In W1 that
is `nf_rimewall` (VII: 330 × 1.30 = 429 → 408, 1.24 × AP); in W2/W3 it also hits TD Snipers at VII–VIII
(VIII: 410 × 1.30 = 533 → 524) and Iron TDs at IX–X (X Sniper: 693 × 1.30 = 901 → 863). Every other W1 shell,
including the howitzer of `iu_brakkhald` (253) and the charged HE of `iu_gorrtund` (865), is under its cap.

**DPM** (single-shot guns; `60 × alpha ÷ reload`) and **reload** in seconds

| Tier | LT DPM / s | MT DPM / s | HT DPM / s | TD DPM / s | SPG DPM / s |
|---|---|---|---|---|---|
| I | 1,130 / 1.8 | 1,263 / 1.9 | – | – | – |
| II | 1,167 / 2.2 | 1,304 / 2.3 | – | 1,349 / 3.3 | – |
| III | 1,239 / 2.5 | 1,385 / 2.6 | – | 1,433 / 3.8 | – |
| IV | 1,342 / 3.2 | 1,500 / 3.4 | 1,476 / 4.3 | 1,552 / 4.9 | 750 / 13.6 |
| V | 1,470 / 4.0 | 1,643 / 4.2 | 1,617 / 5.3 | 1,700 / 6.1 | 821 / 16.8 |
| VI | 1,534 / 5.3 | 1,714 / 5.6 | 1,687 / 7.1 | 1,773 / 8.1 | 857 / 22.4 |
| VII | 1,596 / 7.0 | 1,784 / 7.4 | 1,756 / 9.4 | 1,846 / 10.7 | 892 / 29.6 |
| VIII | 1,745 / 7.6 | 1,950 / 8.0 | 1,919 / 10.2 | 2,017 / 11.6 | 975 / 32.0 |
| IX | 1,998 / 8.2 | 2,233 / 8.6 | 2,198 / 10.9 | 2,310 / 12.5 | 1,117 / 34.4 |
| X | 2,260 / 9.0 | 2,526 / 9.5 | 2,486 / 12.1 | 2,613 / 13.8 | 1,263 / 38.0 |
| XI | 2,410 / 9.3 | 2,694 / 9.8 | 2,652 / 12.4 | 2,787 / 14.2 | – |

**Standard penetration** (mm at ≤ 100 m; special shell ×1.30; AP falls linearly to ×0.90 and APCR to ×0.75 between
100 and 500 m, flat beyond; HEAT, HE and HESH keep their pen)

| Tier | I | II | III | IV | V | VI | VII | VIII | IX | X | XI |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P = MT | 45 | 55 | 65 | 85 | 100 | 130 | 160 | 195 | 225 | 255 | 275 |
| LT (×0.90) | 41 | 50 | 59 | 77 | 90 | 117 | 144 | 176 | 203 | 230 | 248 |
| HT (×1.03) | – | – | – | 88 | 103 | 134 | 165 | 201 | 232 | 263 | 283 |
| TD (×1.18) | – | 65 | 77 | 100 | 118 | 153 | 189 | 230 | 266 | 301 | 325 |
| SPG (×0.25) | – | – | – | 21 | 25 | 33 | 40 | 49 | 56 | 64 | – |

**Calibre bands** (mm, top gun; O: authoring bands so overmatch, HE splash `R = calibre ÷ 100` m, camo-at-shot and the
gun sound family are predictable. The stock gun is one step smaller or the same calibre. SPG calibres are in the §1.4
gun table. R5 reads "the largest same-tier direct-fire calibre" as the top of the tier's widest band below.)

| Tier | I | II | III | IV | V | VI | VII | VIII | IX | X | XI |
|---|---|---|---|---|---|---|---|---|---|---|---|
| LT | 20–37 | 37–45 | 37–57 | 45–75 | 57–76 | 75–85 | 75–90 | 76–100 | 85–105 | 90–105 | 100–105 |
| MT | 37–45 | 40–65 | 47–76 | 57–85 | 75–90 | 75–100 | 85–100 | 90–105 | 100–120 | 105–120 | 120–125 |
| HT | – | – | – | 75–100 | 85–105 | 90–122 | 100–122 | 105–130 | 120–135 | 120–152 | 130–152 |
| TD | – | 47–76 | 57–85 | 75–100 | 85–105 | 90–122 | 100–128 | 105–130 | 120–135 | 120–155 | 130–155 |
| R5 floor (⅓ of the top) | 15 | 26 | 29 | 34 | 35 | 41 | 43 | 44 | 45 | 52 | 52 |

Iron's shipped I–III guns (37/45, 45/63, 63/76 mm) sit inside these bands.

### 5.3 Survivability and mobility bands

**Hit points**

| Tier | I | II | III | IV | V | VI | VII | VIII | IX | X | XI |
|---|---|---|---|---|---|---|---|---|---|---|---|
| LT (×0.80) | 224 | 288 | 352 | 424 | 512 | 656 | 848 | 1,080 | 1,320 | 1,560 | 1,760 |
| MT | 280 | 360 | 440 | 530 | 640 | 820 | 1,060 | 1,350 | 1,650 | 1,950 | 2,200 |
| HT (×1.20) | – | – | – | 636 | 768 | 984 | 1,272 | 1,620 | 1,980 | 2,340 | 2,640 |
| TD (×0.85) | – | 306 | 374 | 451 | 544 | 697 | 901 | 1,148 | 1,403 | 1,658 | 1,870 |
| SPG (×0.30) | – | – | – | 159 | 192 | 246 | 318 | 405 | 495 | 585 | – |

**Effective frontal armor at 0° yaw** (mm, the decisions §7.4 rule applied to P). The HT, MT and LT columns are
class bands: multiply them by role and kit armor factors. The two TD columns are already role bands (decisions
§7.4): multiply them by the kit only; TD Versatile (turreted) uses the Sniper/Support column. Then apply the 1.45 P
clamp of red flag R3.

| Tier | HT turret 1.15–1.35 P | HT upper .95–1.15 P | HT weak ≤ .55–.70 P | MT turret .85–1.0 P | MT hull .50–.70 P | TD Assault 1.1–1.4 P | TD Sniper/Support ≤ .45 P | LT ≤ .35 P | Sides HT .35–.45 / others .2–.3 P | Rear .2–.3 P | Clamp 1.45 P |
|---|---|---|---|---|---|---|---|---|---|---|---|
| I | – | – | – | 38–45 | 23–32 | – | – | 16 | – / 9–14 | 9–14 | 65 |
| II | – | – | – | 47–55 | 28–39 | – | 25 | 19 | – / 11–17 | 11–17 | 80 |
| III | – | – | – | 55–65 | 33–46 | – | 29 | 23 | – / 13–20 | 13–20 | 94 |
| IV | 98–115 | 81–98 | 47–60 | 72–85 | 43–60 | 94–119 | 38 | 30 | 30–38 / 17–26 | 17–26 | 123 |
| V | 115–135 | 95–115 | 55–70 | 85–100 | 50–70 | 110–140 | 45 | 35 | 35–45 / 20–30 | 20–30 | 145 |
| VI | 150–176 | 124–150 | 72–91 | 111–130 | 65–91 | 143–182 | 59 | 46 | 46–59 / 26–39 | 26–39 | 189 |
| VII | 184–216 | 152–184 | 88–112 | 136–160 | 80–112 | 176–224 | 72 | 56 | 56–72 / 32–48 | 32–48 | 232 |
| VIII | 224–263 | 185–224 | 107–137 | 166–195 | 98–137 | 215–273 | 88 | 68 | 68–88 / 39–59 | 39–59 | 283 |
| IX | 259–304 | 214–259 | 124–158 | 191–225 | 113–158 | 248–315 | 101 | 79 | 79–101 / 45–68 | 45–68 | 326 |
| X | 293–344 | 242–293 | 140–179 | 217–255 | 128–179 | 281–357 | 115 | 89 | 89–115 / 51–77 | 51–77 | 370 |
| XI | 316–371 | 261–316 | 151–193 | 234–275 | 138–193 | 303–385 | 124 | 96 | 96–124 / 55–83 | 55–83 | 399 |

**Mobility** (top speed km/h · power-to-weight hp/t)

| Tier | LT (×1.20 · ×1.6) | MT | HT (×0.72 · ×0.77) | TD (×0.80 · ×0.80) | SPG (×0.75 · ×0.80) |
|---|---|---|---|---|---|
| I | 48 · 19 | 40 · 12 | – | – | – |
| II | 50 · 21 | 42 · 13 | – | 34 · 10.4 | – |
| III | 54 · 22 | 45 · 14 | – | 36 · 11.2 | – |
| IV | 56 · 24 | 47 · 15 | 34 · 11.6 | 38 · 12.0 | 35 · 12.0 |
| V | 60 · 26 | 50 · 16 | 36 · 12.3 | 40 · 12.8 | 38 · 12.8 |
| VI | 62 · 27 | 52 · 17 | 37 · 13.1 | 42 · 13.6 | 39 · 13.6 |
| VII | 65 · 27 | 54 · 17 | 39 · 13.1 | 43 · 13.6 | 41 · 13.6 |
| VIII | 66 · 29 | 55 · 18 | 40 · 13.9 | 44 · 14.4 | 41 · 14.4 |
| IX | 66 · 30 | 55 · 19 | 40 · 14.6 | 44 · 15.2 | 41 · 15.2 |
| X | 66 · 32 | 55 · 20 | 40 · 15.4 | 44 · 16.0 | 41 · 16.0 |
| XI | 67 · 34 | 56 · 21 | 40 · 16.2 | 45 · 16.8 | – |

Hull traverse = MT column (38–46 °/s) × LT 1.18, HT 0.60, TD 0.67, SPG 0.55; turret traverse = 40–44 °/s × LT 1.15,
HT 0.65, turreted TD 0.50. Gun arcs default −8° / +20° with the kit depression replacing −8°; casemate yaw ±11°
(Crown Vernier casemates ±12° in `yawLimitsDeg`, a per-vehicle arc decisions §3 allows; no `balanceException` needed). View range = base (300 → 410 m) × class factor
(decisions §5).

### 5.4 What each tier is for (intent)

| Tiers | Intent | Content rules |
|---|---|---|
| I–III | Learn to move, aim, angle and spot. Six free-feeling starters; no heavies, no artillery, no mechanics | Single-tier MM at I–II. Stock standard pen ≥ 0.72 P so stock vehicles still penetrate same-tier medium hulls (≤ 0.70 P). Tier I starters at lint ratio 1.00 ± 0.03 on every core stat (they differ by class, role and kit only) |
| IV–V | Classes become real: first heavies, first artillery, first assault casemate | Heavies must have an obvious lower-plate weak spot; SPG IV has no stun |
| VI–VII | Faction identities peak: depression, turret armor, precision, assault casemates | No special mechanics in W1; identity comes from kits and roles only. From W2 a second branch may start its mechanic at VII (Outrider Wheeled, W3 Bastion SiegeMode) so it is learned before IX |
| VIII | Mechanics arrive (DualGun, Autoreloader, Hydropneumatic) and premiums concentrate | One mechanic per vehicle; premiums per §2.8 |
| IX–X | Endgame variety: two Tier X per faction, Magazine/Wheeled/Siege, 12 Tier X total | Every Tier X has a written counter in its faction section |
| XI | Veteran showcase; X–XI only | Signature only; nodes ≤ +6 % per stat (§2.7), ≤ +12 % ceiling (R16) |

### 5.5 Balance red flags (review blockers)

Any of these blocks a vehicle from shipping until fixed or signed off by the lead designer with a written
`balanceException`.

| # | Red flag | Test | Why |
|---|---|---|---|
| R1 | **One-shell kill of a full-HP light** | Max-roll damage (×1.25) of any single direct-fire shell (AP/APCR/HEAT/HE/HESH, ChargedShot included) must stay below the base LT HP at the bottom of the vehicle's matchmaking spread: alpha ≤ the §5.2 cap. Checked: `iu_gorrtund` charged HE 865 ≤ 1,247; `iu_durhald` HE 715 ≤ 863; `nf_rimewall` HE capped at 408. Bursts are R2's job; artillery is clamped (§1.4) | Fast TTK on Roblox reads as unfair (decisions §7.1 chose TD α 1.50 for "no LT one-shots") |
| R2 | **Burst overflow** | Magazine, Autoreloader or DualGun burst ≤ 0.85 × same-tier MT HP | Decisions §4 burst cap |
| R3 | **Impenetrable fronts** | No frontal zone above **1.45 P** effective at 0° yaw (same-tier TD special round = 1.53 P must always work); at most **75 %** of a turret's or casemate's frontal silhouette above **1.30 P** (the same-tier MT special round; HT special = 1.34 P), so the rest is beatable by every class's special round; every vehicle shows a frontal weak spot ≤ 0.70 P covering ≥ 8 % of its frontal silhouette, and every turret or casemate face has one ≤ 0.90 P covering ≥ 3 % (cupola, vision block, mantlet edge) that stays exposed when the hull is down | Stacked kit × role armor (Iron HT Assault turret up to 1.71 P, Northern Assault casemate 1.48 P) would otherwise create hull-down invulnerability; a 1.45 P turret behind a town wall must still give a medium tank a real target |
| R4 | **Multiplier stacking** | Any non-armor, non-camo core stat whose role × kit product (on top of the class multiplier) falls outside [0.75, 1.35] needs review. Current extremes: Crown MT Support reload 0.92 × 0.92 = 0.85, Mountain TD Support speed 1.10 × 1.15 = 1.27 (armor products such as Mountain MT Support hull 0.60 × 0.90 are exempt) | Kits were designed independently of roles |
| R5 | **Angling made useless** | No HT, MT Assault or TD Assault upper frontal plate nominally thinner than ⅓ of the largest same-tier direct-fire calibre (the §5.2 "R5 floor" row; the 3-calibre rule means a thinner plate could never ricochet) | Keeps decisions §1 overmatch rules meaningful |
| R6 | **Depression and speed outliers** | Depression never beyond −20° (Mountain siege); top speed including equipment never above 100 km/h (worst legal case: Wheeled speed mode with a slotted Turbo Kit, (70 + 5) × 1.30 = 97.5; RocketBoost 64 + 20 + 5 = 89) | Prediction (2.7 studs per 30 Hz tick at 97.5 km/h), sweep collision and camera limits |
| R7 | **Invisible vehicles** | Best still body camo (authored base incl. role add, × full Concealment perk 1.8, + slotted net + paint) ≤ 0.80. Worst W1 case: turretless TD Sniper (0.28 + 0.04) × 1.8 + 0.1725 + 0.04 = 0.79; any new camo source needs a review | Decisions §5: the 0.90 cap with foliage is the only way to reach the floor spot distance; no invisible TDs |
| R8 | **Premium creep** | Any premium outside the §2.8 rules: a core stat above ratio 1.03 (P60); a premium that beats **every** same-tier, same-class tech-tree vehicle on both sustained DPM and front armor; any premium with a special mechanic | Decisions §7.4 and §15: no pay-for-power |
| R9 | **Mechanic creep** | More than 20 % of Tier I–X vehicles with a mechanic (W1: 18.1 %), more than one mechanic per vehicle (an Apex's AdaptiveMagazine and its carrier `Magazine` gun count as one), any Tier XI signature below XI, a second Magazine or DualGun branch in one faction | Decisions §4 (DualGun: one line); one Magazine branch per faction is a roster rule that keeps the burst identity rare |
| R10 | **Class collapse** | An LT with HT-band armor; a TD faster than the same-tier LT class baseline (§5.3); a non-Breakthrough HT faster than the same-tier MT baseline; an MT with higher alpha than the same-tier TD; an SPG direct hit above 0.45 × same-tier MT HP | Classes must stay readable |
| R11 | **Flat progression** | Within a branch, each next vehicle must change at least one identity axis (role, armor scheme, gun family or furniture, mechanic, silhouette) and never lose top-gun standard penetration across a research edge (artillery exempt); between same-class tiers HP grows 12–35 % (MT baseline steps run +18 % to +29 %, role HP trims stretch that to +12.6 % for `dc_dawnfix` → `dc_sunward` and +35 % for `iu_kolmal` → `iu_ostmal`, the Apex step is +12.8 %); class switches are exempt | The "not just a stat bump" rule of §1 |
| R12 | **Stock trap** | Stock effectiveness (§5.1) outside [0.80, 0.90], stock gun alpha below 0.85 × top, or stock standard pen below 0.72 P (artillery exempt) | Decisions §7.4 stock ≈ 85 %; new players must still penetrate same-tier medium hulls (≤ 0.70 P) |
| R13 | **Thin-cell dominance** | A vehicle that is alone in its (tier, class) cell (§3.1) sits at the 45th–55th percentile of its envelope (lint ratio 0.985–1.015) on every core stat, never at the edge | Bots mirror with it; any outlier is multiplied across many battles |
| R14 | **Hidden weaknesses** | Every detonation-prone ammo location (Crown bustles, casemate side racks) and every weak spot must be visible in the Armor Inspector and readable at LOD1 | Counterplay must be learnable |
| R15 | **Shell abuse** | HE and HESH alpha ≤ 1.30 × AP alpha and ≤ the §5.2 cap, except declared howitzer guns (HE ≤ 1.60 × AP, reload ≥ 1.35 × the AP gun's), which never appear below Tier IV | Low-tier HE one-shots ruin onboarding |
| R16 | **Apex overreach** | A fully noded Apex with any stat above its XI target × 1.12, or carrying an I–X mechanic other than the `Magazine` gun that carries `AdaptiveMagazine` | Decisions §7.4 and §11 |
| R17 | **Silhouette confusion and IP look-alikes** | Two vehicles of different classes in one faction that are indistinguishable at LOD2, or any silhouette a reviewer can name as a real tank | Brand §1.1 and readability |

---

## 6. Appendix

### 6.1 Reserved slots for Waves 2 and 3

What is reserved now is the **topology**: branch ids (already in `TechTree.luau`), tree rows (§2.11), the parent
and unlocking module of every future edge, and mechanic slots. Vehicle ids are **not** reserved: the validator cannot
check edges to vehicles that do not exist, and a placeholder id would become permanent. W2/W3 vehicles get names and
ids in their own design pass, following §4 morphology, never reusing a W1 vehicle id or any branch id. Each wave must
keep the special-mechanic share at or below 20 % of the Tier I–X roster.

| Wave | Faction | Branch (class) | Tiers | Count | Joins W1 at (unlocking module on the parent) | Mechanics and role constraints | Why this priority |
|---|---|---|---|---|---|---|---|
| W2 | Iron Union | `iu_ram` (TD) | IV–X | 7 | `iu_bulmal` III → Ram IV (top engine) | none; rear casemates, so no turreted Versatile; HE capped (§5.2) | Mid-tier TD supply; premium `iu_tammvarr` crews |
| W2 | Crown Industries | `ci_vernier` lower body (TD) | IV–VIII | 5 | `ci_ordant` III → IV (top engine); Vernier VIII → `ci_precine` (top gun, merge) | none; HESH at VIII | Mid-tier TD supply |
| W2 | Eastern Armor Group | `ea_outrider` lower body (Wheeled LT) | VII–VIII | 2 | `ea_venett` VI → VII (top engine); Outrider VIII → `ea_rhuvari` (top gun, merge) | Wheeled ×2 (LT only, ≤ 1 per team) | Wheeled play before IX |
| W2 | Eastern Armor Group | `ea_gale` (MT) | V–X | 6 | `ea_talett` IV → Gale V (top engine) | none (Magazine stays on Skirmish, R9) | Medium supply at V–VII |
| W2 | Desert Armor Corps | `dc_glint` (TD) | V–X | 6 | `dc_parallax` IV → Glint V (top engine) | Autoreloader VIII–X ×3 (TD) | Faction signature "Autoreloader TD" |
| W2 | Mountain Republic | `mr_scree` (LT) | IV–X | 7 | `mr_ridgewren` III → Scree IV (top engine) | none | LT supply at IV–VII (thinnest class); premium `mr_highstag` crews |
| W2 | Northern Federation | `nf_rimeguard` lower body (HT) | IV–VIII | 5 | `nf_sleet` III → IV (top engine); Rimeguard VIII → `nf_whiteout` (top gun, merge) | none | HT supply at IV |
| W3 | Iron Union | `iu_hammer` lower body (MT) | IV–VIII | 5 | `iu_bulmal` III → IV (top turret); Hammer VIII → `iu_tundmal` (top gun, merge) | none | Complete the Hammer line |
| W3 | Crown Industries | `ci_herald` (LT) | V–X | 6 | `ci_calibrant` IV → Herald V (top engine; MT → LT) | none | Second LT line to X |
| W3 | Mountain Republic | `mr_bastion` lower body (TD) | IV–VIII | 5 | `mr_ridgewren` III → Bastion IV (top turret); Bastion VIII → `mr_tarnhold` (top gun, merge) | SiegeMode VII–VIII ×2, roles Sniper or Support only (decisions §4) | Complete the siege line |
| W3 | Northern Federation | `nf_aurora` (SPG) | IV–X | 7 | `nf_sleet` III → Aurora IV (top tracks) | none; stun Support role only | Second artillery line (stun Support) |

After W2 the roster is 89 + 38 = 127 (Tier I–X 121, mechanics 20 = 16.5 %); after W3, 150 (I–X 144, mechanics 22 =
15.3 %). Further Apexes (a second per faction) follow the X lines added in W2–W3, never before their parent ships.

### 6.2 Per-vehicle authoring checklist (Content team)

1. File `Content/Vehicles/<FactionPascal>/<PascalId>.luau` (`IronUnion/IuTukkhald.luau`) with: id, name,
   shortName, faction, tier, class, role, `acquisition`, `tree = { row, branch }` (§2.11), `mechanics` (§2.10, or
   nil) and the gun's `reload.kind`, `visual` (§2.9 fields + `hooks`), crew seats, engine fuel (petrol or diesel per
   faction table), `visual.layout` (§2.12 must / never), modules (stock + top within the load limit; top-gun
   calibre in the §5.2 band, `ammoCapacity` in the §2.12 band), shells (§0.2 shell kit and faction families). Crew: 2–6 seats, every
   role covered, the Driver never doubles (content-schema §5.2); guideline 2–3 seats at Tier I, 4 from Tier IV,
   a second Loader only when alpha ≥ the MT alpha of the tier.
2. Numbers from §5 × role × kit × mechanic factor (baked in; kits are lint-only); run the balance report; no fail,
   warnings explained; R1 shell cap and R12 stock rules checked.
3. Armor authored against P(T) per §5.3 with the R3 clamp and weak spots; check in the Armor Inspector.
4. `unlocks` on the parent named in §2 with the unlocking module, `researchXp` on this vehicle;
   `ContentRegistry.validate()` green with zero warnings.
5. Silhouette review at LOD0/1/2 against the visual hook, the LOD2 budget of §1 and R17; tech-tree side profile with
   the gun to the right.
6. Localisation keys `vehicle.<id>.name`, `.lore` (§4.3), `role.<role>.hint`; IP screen of the name (§4.1).
7. Garage tooltip for any mechanic: burst, sustained DPM, time to full aim (decisions §4 readability rule).

### 6.3 Open questions (owner in brackets)

1. SPG role trims (§2.4) are proposals: confirm or replace in `Roles.luau` [Combat + Design]. The AreaControl
   Role Score weighting (damage 0.6 / stun 0.3 / kills 0.1) needs a decisions §7.2 amendment first; until then both
   artillery roles keep stun 0.5 / damage 0.4 / kills 0.1 [Game Director].
2. `AdaptiveMagazine` numbers (§2.7) need a combat-owner pass and a `GunState` test [Combat].
3. Vehicle paint hexes (§1) need brand-owner approval and a `check_palette.py` run [Brand].
4. Role-group mirror scoring and the default bot class mix (§3.2, §3.4) need the Matchmaking owner's sign-off [MM].
5. W1 is 89 vehicles against an ≈ 84 brief because of the artillery line; if scope must be cut, drop the
   second-branch Tier IX–X pair of one faction (−2), never the SPG line or an Apex parent [Production].
6. Turretless share is 87 % of TDs (14 of 16; decisions §7.1 target 80 %); a W2 Vernier or Glint TD Versatile
   with a turret brings it back toward 80 % [Design].
7. The premium percentile reading of §2.8 (envelope ratios P40 = 0.97 … P60 = 1.03, plus the dominance check) is
   this document's operational form of decisions §7.4; confirm with the economy owner. Known edge: `mr_highstag`
   (74 km/h) is the fastest tracked Tier VIII in W1 until W2 Scree VIII ships; watch its win rate [Economy +
   Balance].
8. The single-shell cap of §5.2 extends the decisions §7.1 "no LT one-shots" rationale to the bottom of the
   matchmaking spread; it lowers TD HE alpha from Tier VII. Confirm in `Config.Combat` defaults [Combat].
9. `ChargedShot`, `RocketBoost`, `Turbo` and `ActiveCooling` behaviour rules (§2.7) need `GunState` and
   `VehicleSim` tests. The HUD side is specified (ui-ux H-05 charge arc and top-off ring, H-10 mechanic slot).
   `GunState` must flip `CHARGED_SHOT_RESET_ON_MOVE` to `true`: this document now matches ui-ux H-05 (hull movement
   resets the charge) instead of the earlier "moving allowed" [Combat].
10. The ×1.15 shell velocity and ×0.90 reload of `artillery_area_control` (§2.4) change the Sunfall reload column
    if rejected [Combat].
11. Shipped Iron files vs this document: `IuKolmal.luau` has `forwardKmh = 36` (ratio 0.90, a lint warning and
    outside the ±0.03 starter envelope of §3.4 rule 7); author it at 39 km/h (0.975) or justify a
    `balanceException` here first. Its file header still says "slow by design" [Content].
12. Shell families per faction (§0.2) and calibre bands (§5.2) are new authoring rules; the shipped Iron I–III
    guns already comply (AP + APCR + HE; 37–76 mm) [Content + Combat].
13. R3's "≤ 75 % of a turret or casemate face above 1.30 P" rule is new; check `iu_durhald`, `iu_tukktund`,
    `nf_driftwall` and `nf_winterwall` in the Armor Inspector when they are authored [Balance].
14. Mountain siege TDs were redrawn as rear gun blocks with outrigger legs (§1.5) and `dozer_blade` was retired,
    because a turretless whole-hull casemate with a bow-fixed gun and a dozer blade reads as a real vehicle (R17).
    The legs need the siege phase in the replicated vehicle state; confirm it is in the snapshot [Rendering + Net].
