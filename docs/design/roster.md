# HULLDOWN: Faction & Vehicle Roster Bible

> **Status:** authoritative for the launch roster, tech-tree topology, vehicle ids, display names, roles,
> branch identities, visual hooks and vehicle lore. Owner: Lead Vehicle & Progression Design.
> **Precedence:** `docs/research/00-DECISIONS.md` wins on every number and rule (class multipliers §7.1, roles
> §7.2, faction kits §7.3, MT baseline §7.4, mechanics §4, economy §11, matchmaking §8). `docs/design/brand-art.md`
> wins on colour, iconography and copy tone. `docs/ARCHITECTURE.md` wins on data layout
> (`Shared/Config/Content/Vehicles/<Faction>/<VehicleId>.luau`, `TechTree.luau`, `Blueprint`/`VisualSpec`).
> This document chooses *which* vehicles exist and *what each one is for*; content authors fill exact numbers inside
> the bands of §5 and the balance lint (§7.4 of the decisions doc) decides pass/fail.
> **Change control:** a vehicle id, class, role, tier, mechanic or research edge changes here and in
> `Content/TechTree.luau` in one commit. Display names and lore may change freely before launch, never after
> (ids are permanent).

---

## 0. Scope, conventions and the launch-wave arithmetic

### 0.1 Why the launch roster is 89 vehicles (≈ 84 target)

The decisions doc fixes three things that size the roster: **one Tier XI Apex per faction at launch** (§7.4), an
Apex is researched **on a Tier X** of its faction (§11), and every vehicle must be reachable from its faction's Tier I
root (`ContentRegistry.validate`). So each faction needs one complete I → X line (60 vehicles) plus 6 Apexes before
anything else exists. A pure 6 × 14 = 84 roster therefore leaves about two extra nodes per faction.

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

The **second branches are designed in full** (all tiers, §1) but their lower tiers ship later. Wave 1 (W1) ships the
IX–X top of each second branch, reached by a cross-class unlock from Tier VIII. Wave 2 (W2, one season ≈ 8 weeks
later) ships the class-pure lower body, which then also unlocks the same Tier IX, so no node is ever orphaned or
re-homed. The reserved W2/W3 slots and their priorities are in §6.1. Nothing in W1 is a dead end: every W1 vehicle
either unlocks another W1 vehicle or is a Tier X/XI.

### 0.2 Identifier and data conventions

| Item | Convention | Example |
|---|---|---|
| Vehicle id | `<faction prefix>_<name>` in snake_case, ASCII, permanent | `iu_tukkhald` |
| Faction prefix | `iu` Iron Union · `ci` Crown Industries · `ea` Eastern Armor Group · `dc` Desert Armor Corps · `mr` Mountain Republic · `nf` Northern Federation | |
| Class | `Types.VehicleClass` codes `LT` `MT` `HT` `TD` `SPG`; icon ids `light` `medium` `heavy` `td` `artillery` (brand §6.6) | `HT` |
| Role id | `<class><Role>` (proposed `Roles.luau` ids): `LTScout` `LTSupport` `LTVersatile` · `MTAssault` `MTSniper` `MTSupport` `MTVersatile` · `HTAssault` `HTBreakthrough` `HTSupport` `HTVersatile` · `TDAssault` `TDSniper` `TDSupport` `TDVersatile` · `SPGSupport` `SPGAreaControl` | `HTAssault` |
| Branch id | `<prefix>.<branch>` | `iu.bulwark` |
| Mechanic id | Decisions §4 placement names: `Magazine` `Autoreloader` `DualGun` `SiegeMode` `Hydropneumatic` `Wheeled`; Tier XI `ChargedShot` `ActiveCooling` `Turbo` `RocketBoost` `AdaptiveMagazine` (a `Magazine` variant) | `DualGun` |
| Visual preset | `VisualSpec.preset = "<prefix>_<style>"`, one per faction (§1.x builder table); per-vehicle overrides in `VisualSpec.hooks` | `iu_foundry` |
| Shell kit | Every gun carries AP (or APCR/HEAT standard), a premium-family round and HE. `crown_industries` VIII+ HT/TD replace HE with **HESH** (decisions §1) | |

In the tables, roles are written without the class prefix (the class column supplies it). "P" marks a premium.
★ marks a Tier XI Apex. Tiers are always roman numerals (brand §2).

### 0.3 Research rules this roster obeys (from decisions §7.4 and §11)

* **Unlock costs** are per tier, not per vehicle: research XP II 350 · III 750 · IV 1,550 · V 3,000 · VI 5,200 ·
  VII 8,600 · VIII 13,500 · IX 21,000 · X 31,000 · XI 47,000 (on the parent X) and the §11 credit prices.
  Cross-class unlocks cost the same as same-class ones.
* **Modules:** Gun, Turret (only where meaningful), Engine, Tracks; no radio. Upgrades: II–III 1–2, IV–IX 2–4,
  X arrives elite, XI uses the 10-node track. Order Tracks → Turret → Gun; stock ≈ 85 % effectiveness.
* **Next vehicle hangs off the top gun** unless the roster table names another module (cross-class splits usually
  hang off the engine or the hull, because the receiving class uses a different gun family).
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
(brand §6.3). Budgets (decisions §18): LOD0 ≤ 400 parts, LOD1 ≤ 80, LOD2 ≤ 16, ≤ 4 materials per vehicle. Every
"visual hook" in §2 must survive at LOD2 (16 parts): it is a *silhouette* feature (turret position, hull length,
gun length or furniture, casemate shape, wheel count), never a decal. **Vehicle paint** is a muted field colour per
faction (below) with the faction **enamel** (brand §3.7 primary) only on a turret band or hatch ring (≤ 5 % of the
visible area) and the faction emblem decal; team identity never goes on the paint (brand §10). The `paint.*` hexes
below are a proposal to the brand owner for a brand §3.7 extension and must pass `check_palette.py` before use.

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
| Hull | Low and wide (width ÷ height ≥ 1.6). IV–VI: riveted vertical slabs with a stepped front; VII+: **pike-nose prow** (two wedges meeting on a centre ridge). Side-skirt slabs from VIII |
| Turret | **Faceted dome**: octagonal prism + corner wedges, low, centred or slightly forward; heavy block mantlet; no bustle |
| Gun | Short-to-medium, thick barrel, **double-baffle muzzle brake** (two flat plates) on every gun from IV. DualGun = two barrels side by side in one wide mantlet |
| Running gear | 5–6 **large** road wheels, **no return rollers** (sagging upper track run), rear exhaust stacks |
| Detail kit | Rivet rows (LOD0 only), tow cables, spare track links on the glacis |
| Engine family | Diesel (engine fire chance 12 %, decisions §2) |

**Stat profile (kit, decisions §7.3):** alpha ×1.10, reload ×1.10 (DPM neutral), turret armor ×1.10, dispersion
×1.06, aim time ×1.05, gun depression **−5°** (default −8°).

| Class at Tier X (class × role × kit) | HP | Alpha | Reload | DPM | Pen | Notes |
|---|---|---|---|---|---|---|
| HT Assault (`iu_durhald`, DualGun) | 2,340 | 550 per barrel | 30.5 s per barrel | ≈ 2,160 (0.87 × class) | 263 | volley 1,100; turret clamp 1.45 P (§5.4 R3) |
| MT Assault (`iu_brakkmal`) | 2,048 | 440 | 10.5 s | 2,526 | 255 | hull ×1.15, turret ×1.10 ×1.15 |
| TD Versatile (`iu_tammvarr`, VIII P) | 1,148 | ≈ 386 | — | 40–55th pct | 230 | turreted; the only Iron TD in W1 |

* **Strengths:** highest alpha per shot of any faction; turret faces bounce same-tier standard rounds; diesel fires
  are rare; wins every trade under 150 m.
* **Weaknesses:** −5° means no ridge play; worst accuracy and slowest aim, so poor beyond 300 m; long reload windows
  (13–30 s at X) are punished by flankers; the low-tier trunk is slow.
* **Intended counterplay:** shoot lower plates and cupolas, bait a shot then push inside the reload, or fight them
  on a crest they cannot depress over.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `iu.foundry` | Foundry trunk | MT | I–III | I–III | Slow, sturdy starter mediums that teach "angle and trade" |
| `iu.bulwark` | Bulwark heavy line | HT | IV–X → XI | IV–X | The spine: from riveted box to pike-nose to twin-gun wall |
| `iu.hammer` | Hammer brawler mediums | MT | IX–X | IV–X (IV–VIII in W3) | Turret-strong, high-alpha mediums that fight like light heavies |
| `iu.ram` | Ram destroyer line | TD | premium VIII only | IV–X (W2) | Rear-casemate, very high alpha, poor arcs |

Splits and merges: Foundry III splits to Bulwark IV (top gun) and, in W2, Ram IV (engine). Bulwark VIII splits to
Hammer IX through its top engine (W1). In W3 the Hammer lower body (IV–VIII) branches from Foundry III and **merges**
into the existing Hammer IX (Hammer IX gets two parents). The premium `iu_tammvarr` trains TD crews for W2.

```
I            II           III          IV            V               VI             VII             VIII             IX              X              XI
iu_kolmal → iu_ostmal → iu_bulmal → iu_osthald → iu_brakkhald → iu_kolhald → iu_varrhald → iu_tukkhald² → iu_tukktund² → iu_durhald² → iu_gorrtund★
  MT          MT          MT          HT            HT              HT             HT              HT        │       HT              HT             HT
                                                                                                            └(engine)→ iu_tundmal → iu_brakkmal
                                                                                                                        MT            MT
Store: iu_tammvarr (TD VIII, P)                                                     ² DualGun   ★ ChargedShot
```

**Progression arc: Bulwark (HT).** Each step adds a new verb, not just numbers.
* **IV `iu_osthald` (Versatile):** first heavy; tall riveted box with a flat front. Lesson: *you are the wall, so
  show the front and never the side.*
* **V `iu_brakkhald` (Assault):** thick slab front, very slow. Its two top guns are the first real choice: a long AP
  gun or a stubby high-explosive howitzer (per-gun override: HE alpha ×1.6 of the AP gun, reload ×1.35). Lesson:
  *alpha against reliability.*
* **VI `iu_kolhald` (Support):** first faceted dome turret and a long, comparatively accurate gun; −7° (kit −5°,
  role +2°), the only Iron heavy that can use small bumps. Lesson: *turret first.*
* **VII `iu_varrhald` (Breakthrough):** the pike-nose prow appears; +15 % speed and power. Lesson: *angle by
  geometry, lead the push.*
* **VIII `iu_tukkhald` (Versatile, DualGun):** two barrels. Lesson: *single shots to poke, the volley to commit.*
* **IX `iu_tukktund` (Assault, DualGun):** heavier dome, side skirts; the volley is a corner-trade weapon.
* **X `iu_durhald` (Assault, DualGun):** the full wall: thickest Iron turret, 2 × 550 volley.
* **XI `iu_gorrtund` (Assault, ChargedShot +10 % damage):** gives up the twin burst for one enormous charged shot.

**Progression arc: Hammer (MT).** IX `iu_tundmal` (Versatile) is a heavy's gun and turret on a medium hull;
X `iu_brakkmal` (Assault) has the strongest medium turret in the game, bought with the worst depression of any
medium. Both teach "medium speed, heavy manners".

**Progression arc: Foundry trunk (MT).** I `iu_kolmal` (Versatile) is a forgiving tractor-chassis tank with armor
no Tier I gun reliably defeats at an angle. II `iu_ostmal` (Assault) introduces a short high-alpha gun. III
`iu_bulmal` (Versatile) is the first turret that bounces shots: a preview of the heavy line.

### 1.2 CROWN INDUSTRIES (`crown_industries`) — precision

**Identity.** Crown Industries is a chartered manufacturing house of the Gilt Coast guild cities, run by a
hereditary board whose seal is the crown. It builds vehicles like instruments: measured tolerances, superb optics,
guns bored and lapped by hand. Emblem: a brass crown with a purple cog jewel (brand §6.6).

**Doctrine: "shoot first, shoot straight, shoot from cover."** Crown crews take ridges and hull-down positions
(−10° depression) and win by accuracy and steady fire rather than big hits. From Tier VIII its heavies and
destroyers carry **HESH**, which wrecks flat, thin or spaced plates that AP cannot angle through.

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
| TD Sniper (`ci_vernine`) | 1,658 | 580 | 12.7 s | ≈ 2,740 | 301 | dispersion ≈ 0.27, casemate ≤ 0.45 P |
| TD Sniper Apex (`ci_aurelline`, XI) | 1,873 | 638 | 13.0 s | ≈ 2,940 | 325 | ActiveCooling −15 % reload/aim for 5 s |

* **Strengths:** the best accuracy and aim in the game; ridge and hull-down fighting; high sustained DPM; HESH
  punishes flat or spaced armor and light vehicles.
* **Weaknesses:** tall silhouettes are easy to hit; low alpha loses corner trades; petrol engines burn; the
  **ammunition rack sits in the turret bustle**, so rear-turret hits risk detonation.
* **Intended counterplay:** close the distance, force short brawls, shoot the bustle, set fires.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `ci.guild` | Guild trunk | LT → MT | I–IV | I–IV | Precision from the first battle |
| `ci.warden` | Warden heavy line | HT | V–X | V–X | Hull-down heavies; HESH from VIII |
| `ci.vernier` | Vernier destroyer line | TD | IX–X → XI | IV–X (IV–VIII in W2) | Low precision casemates with HESH |
| `ci.herald` | Herald light line | LT | — | V–X (W3) | Fast, accurate scouts with poor alpha |

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
* **VIII `ci_regnion` (Support, HESH):** HESH arrives. Lesson: *pick the shell for the plate*: HESH on flat, thin or
  spaced armor, AP on sloped armor.
* **IX `ci_sovrion` (Versatile, HESH):** longer hull, skirts, a turret thick enough to hold a ridge against Tier IX
  standard rounds while hull-down.
* **X `ci_tesselion` (Support, HESH):** the most accurate heavy in the game. Its turret is only medium-thick, so it
  peeks, shoots and hides.

**Progression arc: Vernier (TD).** IX `ci_precine` (Sniper) is a low front casemate with a ±12° yaw arc and HESH as
its alternative round; X `ci_vernine` (Sniper) adds the longest gun in the faction and the best dispersion of any
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
| LT Versatile, Magazine (`ea_talzarett`) | 1,560 | 340 × 3 | 2.5 s intra, 26.9 s magazine | 1,919 sustained (0.85) | 70 km/h | burst 1,020 in 5 s |
| LT Scout, Wheeled (`ea_lirvari`) | 1,560 | 306 | 9.0 s | ≈ 2,030 | 70 / **91** km/h speed mode | camo +0.03, view range +10 m |
| LT Support Apex (`ea_lirvesh`, XI) | 1,763 | 393 × 4 | 2.2 s intra | ≈ 2,160 sustained | 67 km/h | AdaptiveMagazine (§2.7) |

* **Strengths:** the fastest vehicles in every bracket; best spotting at VIII–X; burst damage that can delete a
  damaged vehicle; the wheeled outriders redeploy across a 1 km map in under 40 s.
* **Weaknesses:** paper turrets (×0.80) make hull-down impossible; long magazine reloads leave them helpless for
  25–30 s; petrol fires; the lowest HP in their class brackets; wheeled vehicles lose 25 % speed per destroyed pair.
* **Intended counterplay:** track or de-wheel them, push them while their magazine is empty (the reloading sound is
  audible, audio.md), deny bush lines with your own scouts.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `ea.skirmish` | Skirmish light line | LT | I–X → XI | I–X | The spine: scouts and flankers, Magazine at IX–X |
| `ea.outrider` | Outrider wheeled line | LT (Wheeled) | IX–X | VII–X (VII–VIII in W2) | The fastest vehicles in the game: information, not trades |
| `ea.gale` | Gale medium line | MT | — | V–X (W2) | Fast, thin, high-alpha single-shot mediums (no mechanic: Magazine stays on one branch, decisions §4) |

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
* **II `ea_essett` (Scout):** the best camouflage at Tier II. Lesson: *passive spotting from a bush.*
* **III `ea_veshett` (Scout):** faster, turret moved forward. Lesson: *active spotting: show, then break contact.*
* **IV `ea_talett` (Support):** the biggest gun on any Tier IV light. Lesson: *a light can deal damage from a flank.*
* **V `ea_sevett` (Versatile):** first Eastern light to reach 60+ km/h with a fast turret. Lesson: *circle and
  track.*
* **VI `ea_venett` (Scout):** long, very low hull, best light camouflage at VI. Lesson: *view range and patience.*
* **VII `ea_lirett` (Support):** a high-penetration gun on a fast hull. Lesson: *flank damage without being seen.*
* **VIII `ea_silett` (Scout):** the fastest tracked vehicle in W1. Lesson: *win the first 60 seconds of map
  control.*
* **IX `ea_zarett` (Support, Magazine 4):** 4 × 272 alpha. Lesson: *burst, then disappear.*
* **X `ea_talzarett` (Versatile, Magazine 3):** fewer, harder shells with a quicker intra-clip. Lesson: *pick the
  moment; a wasted clip is 27 seconds of uselessness.*
* **XI `ea_lirvesh` (Support, AdaptiveMagazine):** the magazine can be topped off, so a partial burst no longer
  wastes the reload.

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
| Gun | Long, thin, with 2–3 **thermal-sleeve bands** and a small single-baffle brake |
| Running gear | 5–6 road wheels behind the skirts, raised front idler |
| Detail kit | Jerrycan racks, mesh stowage baskets, a sunshade canopy frame on I–III |
| SPG family | Open-top howitzer carriage (IV–VI) → half-enclosed fighting compartment (VII–VIII) → fully enclosed turret with rear recoil spades (IX–X); barrel length grows each tier |
| Engine family | Diesel (fire 12 %) |

**Stat profile (kit):** aim time ×0.94, reload ×0.95 (DPM ×1.05), turret armor ×1.08, lower plate ×0.85,
depression **−10°**.

| Class at Tier X | HP | Alpha | Reload / magazine | DPM | Pen | Notes |
|---|---|---|---|---|---|---|
| MT Sniper, Autoreloader (`dc_sunward`) | 1,950 | 400 × 3 | refills 12.5 / 9.4 / 9.0 s | ≈ 2,330 sustained (0.92) | 273 | aim 2.07 s, dispersion ≈ 0.31 |
| SPG Support (`dc_noonfall`) | 585 | 800 HE | 36.1 s | ≈ 1,330 | 64 | splash 7.65 m (155 mm), stun ≤ 16 s, direct hit ≤ 878 |
| MT Sniper Apex (`dc_zenith`, XI) | 2,200 | 440 | 9.8 s | ≈ 2,700 | 295 | ChargedShot: 1.5 s charge, dispersion ×0.6 |

* **Strengths:** long-range accuracy and fast aim; strong hull-down turrets; the best DPM kit; artillery support.
* **Weaknesses:** weak lower plates and tall cupolas punish any crest-to-crest duel at close range; the
  autoreloader's first refill after emptying is the longest (12.5 s at X); artillery is fragile and reveals itself
  for 5 s after each shot (decisions §7.4).
* **Intended counterplay:** flank or close in so they must crest; shoot the lower plate the moment they climb;
  hunt the SPG from its minimap ring.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `dc.caravan` | Caravan trunk | MT | I–III | I–III | Quick-aiming starter mediums |
| `dc.longshot` | Longshot medium line | MT | IV–X → XI | IV–X | The spine: hull-down long-range mediums, Autoreloader VIII–X |
| `dc.sunfall` | Sunfall artillery line | SPG | IV–X | IV–X | The launch artillery: alternating stun Support and AreaControl roles |
| `dc.glint` | Glint destroyer line | TD | — | V–X (W2) | Autoreloader casemates (decisions §7.3 signature "Autoreloader MT/TD") |

Splits and merges: Caravan III splits to Longshot IV (top gun) and Sunfall IV (engine; the SPG reuses the
caravan chassis). W2: Glint V branches from Longshot IV (class switch MT → TD). Premium `dc_dunelight` (MT VIII)
trains Longshot crews.

```
I            II           III             IV            V            VI            VII            VIII           IX            X             XI
dc_waymark → dc_bearing → dc_sandglass → dc_parallax → dc_azimuth → dc_meridian → dc_longsight → dc_sextant ᴬ → dc_dawnfix ᴬ → dc_sunward ᴬ → dc_zenith★
  MT           MT           MT      │        MT            MT           MT            MT             MT             MT            MT            MT
                                    └(engine)→ dc_dustfall → dc_ashfall → dc_emberfall → dc_glassfall → dc_sunfall → dc_starfall → dc_noonfall
                                               SPG           SPG          SPG            SPG            SPG          SPG           SPG
Store: dc_dunelight (MT VIII, P)                                                 ᴬ Autoreloader   ★ ChargedShot (dispersion)
```

**Progression arc: Longshot (MT).**
* **IV `dc_parallax` (Versatile):** first tall-cupola turret with −10°. Lesson: *a dune crest is armor.*
* **V `dc_azimuth` (Sniper):** a long gun and the best Tier V medium dispersion. Lesson: *shoot at 300 m+.*
* **VI `dc_meridian` (Assault):** thicker turret (Assault ×1.15 on the ×1.08 kit). Lesson: *hold a ridge under
  fire, not just snipe from it.*
* **VII `dc_longsight` (Sniper):** best Tier VII medium dispersion and +10 m view range. Lesson: *spot for yourself.*
* **VIII `dc_sextant` (Versatile, Autoreloader 2):** the double tap. Lesson: *peek, fire twice, drop back.*
* **IX `dc_dawnfix` (Assault, Autoreloader 3):** three shells from the strongest hull-down turret in the faction.
  Lesson: *burst from cover, then manage the long first refill.*
* **X `dc_sunward` (Sniper, Autoreloader 3):** the flagship long-range medium.
* **XI `dc_zenith` (Sniper, ChargedShot):** single gun; hold fire to tighten dispersion to ×0.6 at 500 m.

**Progression arc: Sunfall (SPG).** Roles alternate so each tier asks for a different habit:
* **IV `dc_dustfall` (AreaControl):** open-top light howitzer, no stun (decisions: stun from V). Lesson: *arcs and
  ≥ 2.5 s flight time.*
* **V `dc_ashfall` (Support):** first stun (6 s). Lesson: *stun the push your team is fighting.*
* **VI `dc_emberfall` (AreaControl):** fast light carriage, small splash, quicker reload. Lesson: *move after every
  shot; your minimap ring gives you away for 5 s.*
* **VII `dc_glassfall` (Support):** heavy howitzer, big splash. Lesson: *stun groups at chokepoints.*
* **VIII `dc_sunfall` (AreaControl):** long gun-howitzer: flatter arc, faster shell, smaller splash, the highest
  direct-hit damage in the line. Lesson: *lead moving targets.*
* **IX `dc_starfall` (Support):** enclosed 360° turret. Lesson: *cover two lanes without moving.*
* **X `dc_noonfall` (Support):** the flagship howitzer, slow and enclosed, 16 s maximum stun.

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
| Hull | **Very low**, long track run with **7–8 small road wheels**, raised front idler for climbing; TDs carry a small dozer blade |
| Turret | Low turret **mounted at the rear**, so the gun overhangs the bow and the hull stays below the crest |
| Hydropneumatic MTs | Visible suspension cylinders between road-wheel stations; the hull model pitches with the mechanic |
| Siege TDs | **Turretless, no superstructure**: the whole hull is the casemate, gun fixed in the hull front, twin side periscopes |
| Gun | Slim barrel with a **short conical flash hider** and a breech counterweight collar |
| Detail kit | Spare road wheels on the hull sides, rope coils, snow-white hatch trim |
| Engine family | Diesel (fire 12 %) |

**Stat profile (kit):** top speed ×1.15, depression **−12°**, hull armor ×0.60.

| Class at Tier X | HP | Alpha | Reload | DPM | Speed | Notes |
|---|---|---|---|---|---|---|
| MT Versatile, Hydropneumatic (`mr_crestline`) | 1,950 | 400 | 9.5 s | 2,526 | 63 km/h | −16° after 0.75 s still; hull 0.30–0.42 P |
| TD Support, SiegeMode (`mr_peakhold`) | 1,658 | 600 | 12.4 s | ≈ 2,900 | 56 km/h travel, ≤ 10 siege | siege: aim ×0.4, dispersion ×0.85, −20° |
| MT Versatile Apex (`mr_updraft`, XI) | 2,200 | 440 | 9.8 s | 2,694 | 64 (+20 boost) km/h | RocketBoost 2 × 2.5 s, 30 s cooldown |

* **Strengths:** unmatched depression; fastest kit; siege destroyers are the most accurate guns at their tiers;
  they choose every engagement on broken ground.
* **Weaknesses:** almost every hull hit penetrates; on flat ground or in towns they have nothing to hide behind;
  siege transitions (2.0 s on, 1.25 s off) and the 0.75 s hydropneumatic delay punish surprise.
* **Intended counterplay:** flank before siege engages, catch them on flats and in transitions, aim at the hull the
  moment they crest.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `mr.pathfinder` | Pathfinder trunk | LT | I–III | I–III | Nimble climbing scouts |
| `mr.ridgeline` | Ridgeline medium line | MT | IV–X → XI | IV–X | The spine: reverse-slope mediums, Hydropneumatic VIII–X |
| `mr.bastion` | Bastion siege line | TD | IX–X | IV–X (IV–VIII in W3) | Turretless siege casemates |
| `mr.scree` | Scree light line | LT | — | IV–X (W2) | Climbing scouts that spot from peaks |

Splits and merges: Pathfinder III → Ridgeline IV (class switch LT → MT, top gun). Ridgeline VIII → Bastion IX
(the gun carries over into the hull). W2: Scree IV branches from Pathfinder III. W3: the Bastion lower body branches
from Ridgeline IV and its VIII also unlocks Bastion IX (merge). Premium `mr_highstag` (LT VIII) trains Scree crews.

```
I              II               III            IV         V              VI           VII        VIII            IX              X               XI
mr_screehare → mr_cairnhopper → mr_ridgewren → mr_talus → mr_saddleback → mr_cornice → mr_scarp → mr_highcol ᴴ → mr_tarnwatch ᴴ → mr_crestline ᴴ → mr_updraft★
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
* **VIII `mr_highcol` (Sniper, Hydropneumatic):** the suspension tilts the hull for −16°. Lesson: *stop for
  0.75 s before you crest.*
* **IX `mr_tarnwatch` (Sniper, Hydropneumatic):** longer gun, better view range. Lesson: *spot and shoot from the
  same peak.*
* **X `mr_crestline` (Versatile, Hydropneumatic):** the flagship generalist, fast enough to switch flanks.
* **XI `mr_updraft` (Versatile, RocketBoost):** two rocket bursts to jump onto a crest or out of a crossfire.

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
| HT Breakthrough Apex (`nf_rimeburst`, XI) | 2,772 | 550 | 12.4 s | 2,660 | 46 km/h | active Turbo: power ×1.25 for 6 s, 40 s cooldown |

* **Strengths:** the most HP in every bracket they play; assault casemates out-armor heavies from the front;
  accurate guns for their class; they survive long enough to win the late game.
* **Weaknesses:** turretless casemates die to flanks; sluggish acceleration (×0.94); Assault camouflage −0.08 makes
  them easy to spot; huge silhouettes.
* **Intended counterplay:** flank and circle, track them, shoot the cupola and lower plate, refuse the frontal trade.

**Branches**

| Branch | Name | Class | W1 | Full design | Identity |
|---|---|---|---|---|---|
| `nf.frontier` | Frontier trunk | MT | I | I | One rugged starter |
| `nf.glacis` | Glacis destroyer line | TD | II–X | II–X | The spine: from ambush carriages to assault casemates |
| `nf.rimeguard` | Rimeguard heavy line | HT | IX–X → XI | IV–X (IV–VIII in W2) | Survival heavies that become breakthrough machines |
| `nf.aurora` | Aurora artillery line | SPG | — | IV–X (W3) | The second artillery line, stun Support only |

Splits and merges: Frontier I → Glacis II (class switch MT → TD). Glacis VIII → Rimeguard IX (engine and hull
casting). W2: the Rimeguard lower body branches from Glacis III and its VIII also unlocks Rimeguard IX (merge). The
premium `nf_thawbreaker` (HT VIII) trains Rimeguard crews.

```
I              II           III         IV             V             VI            VII           VIII           IX            X              XI
nf_hoarling → nf_icepick → nf_sleet → nf_hailstone → nf_rimecrag → nf_floewall → nf_rimewall → nf_hoarwall → nf_glacis → nf_winterwall
  MT            TD           TD          TD             TD            TD            TD            TD     │      TD            TD
                                                                                                        └(engine)→ nf_whiteout → nf_deepwinter → nf_rimeburst★
                                                                                                                   HT            HT              HT
Store: nf_thawbreaker (HT VIII, P)                                                             ★ active Turbo
```

**Progression arc: Glacis (TD).**
* **II `nf_icepick` (Support):** open-top gun carriage, quick reload, fragile. Lesson: *ambush, then relocate.*
* **III `nf_sleet` (Sniper):** low casemate, best TD camouflage at III. Lesson: *wait until the target commits.*
* **IV `nf_hailstone` (Versatile):** a turreted destroyer (360°, alpha ×0.9). Lesson: *a destroyer can track a
  moving target.*
* **V `nf_rimecrag` (Assault):** the first assault casemate bounces Tier V standard rounds frontally. Lesson:
  *lead from the front, but the gun arc is only ±11°: point the hull, not the turret.*
* **VI `nf_floewall` (Assault):** heavier casemate, bigger gun. Lesson: *hold the heavy lane with the heavies.*
* **VII `nf_rimewall` (Support):** lighter and faster, reload ×0.9. Lesson: *rotate and support instead of
  anchoring.*
* **VIII `nf_hoarwall` (Assault):** the continuous glacis-to-casemate slope. Lesson: *wall up beside your heavies.*
* **IX `nf_glacis` (Assault):** the thickest frontal armor in the game (at the 1.45 P clamp) with a deliberately
  weak cupola.
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
Numbers in identities are targets derived from §5 (class × role × kit × tier); the lint (§5.3) is the judge.

### 2.1 Iron Union (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `iu_kolmal` | Kolmal | I | MT | Versatile | foundry | | Forgiving starter: sloped riveted front that rewards angling, slow, choice of a quick or a hard-hitting gun | | Tractor-chassis box hull, tiny faceted dome, 4 large wheels, no return rollers | starter (free) |
| `iu_ostmal` | Ostmal | II | MT | Assault | foundry | | Short high-alpha gun with a slow reload; thickest Tier II front, soft sides | | Stepped riveted front, turret forward, stubby barrel with the first double-baffle brake | `iu_kolmal` |
| `iu_bulmal` | Bulmal | III | MT | Versatile | foundry | | First dome turret that bounces Tier III standard rounds; −5°; best medium alpha at III | | Longer hull, 5 large wheels, sagging track, dome centred | `iu_ostmal` |
| `iu_osthald` | Osthald | IV | HT | Versatile | bulwark | | First heavy: flat riveted front at ≈ 1.0 P, tall box turret, weak hull sides, 34 km/h | | Tall riveted box hull with a vertical front, small box turret, decorative side blister | `iu_bulmal` |
| `iu_brakkhald` | Brakkhald | V | HT | Assault | bulwark | | The slab wall: thick front, 31 km/h; top-gun choice of long AP or a stubby HE howitzer (α ×1.6, reload ×1.35) | | Thick slab glacis, hull-length side slabs, turret forward; howitzer = short fat barrel | `iu_osthald` |
| `iu_kolhald` | Kolhald | VI | HT | Support | bulwark | | First cast dome; long, comparatively accurate gun (pen ×1.05); −7°; thinner hull (×0.85) | | Faceted dome on a lower hull, long barrel with double-baffle brake | `iu_brakkhald` |
| `iu_varrhald` | Varrhald | VII | HT | Breakthrough | bulwark | | Pike-nose prow (≈ 1.1 P at 0° yaw, lower prow 0.6 P), +15 % speed and power, leads the push | | First pike nose: two glacis wedges on a centre ridge; long low dome | `iu_kolhald` |
| `iu_tukkhald` | Tukkhald | VIII | HT | Versatile | bulwark | | Twin-gun debut: strong turret, average hull; singles to poke, volley to commit | DualGun 2 × 358, volley 716, charge 1.0 s, 1.5 s between barrels, ≈ 25.7 s per barrel | Wide twin mantlet on a dome turret, pike nose, side skirts | `iu_varrhald` |
| `iu_tukktund` | Tukktund | IX | HT | Assault | bulwark | | Thickest Tier IX turret face, 34 km/h; the volley is a corner-trade weapon | DualGun 2 × 440, volley 880, ≈ 27.7 s per barrel | Taller dome with cheek wedges, twin barrels, full skirts | `iu_tukkhald` |
| `iu_durhald` | Durhald | X | HT | Assault | bulwark | | Turret at the 1.45 P clamp, weak cupola and lower prow; lowest Tier X heavy DPM (0.87) for the biggest burst | DualGun 2 × 550, volley 1,100, ≈ 30.5 s per barrel | Longest Iron hull, massive twin mantlet, double-baffle brakes on both barrels, 6 wheels | `iu_tukktund` |
| `iu_tundmal` | Tundmal | IX | MT | Versatile | hammer | | A heavy's turret on a medium hull: turret ×1.10, α 352, −5°, 55 km/h | | Medium hull with an oversized faceted dome, short thick gun | `iu_tukkhald` (engine) |
| `iu_brakkmal` | Brakkmal | X | MT | Assault | hammer | | Strongest medium turret in the game, HP 2,048, α 440; worst medium depression | | Wide dome with cheek plates on a pike-nose medium hull, side slabs | `iu_tundmal` |
| `iu_tammvarr` | Tammvarr | VIII | TD | Versatile | (ram) | P | Iron's only turreted destroyer: α ≈ 386, quicker reload, thin open turret; credits ×1.5; trains W2 Ram crews | | Open-roof faceted turret at the rear of a low hull, very long gun | Store 3,500 BUL |
| `iu_gorrtund` | Gorrtund | XI | HT | Assault | bulwark | | One enormous gun: α 605 (666 charged), HP 2,644, pen 284; slow and deliberate | ★ ChargedShot (+10 % damage) | Largest dome in the game with cheek armor, one very thick barrel with a triple-baffle brake | `iu_durhald` (47,000 XP) |

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
| `ci_regnion` | Regnion | VIII | HT | Support | warden | | HESH debut: HESH for flat or spaced plates, AP for slopes; bustle ammo rack is the weak spot | HESH shell kit | Wide flat mantlet, long bore-evacuated gun, brass periscope hoods, side bins | `ci_ordion` |
| `ci_sovrion` | Sovrion | IX | HT | Versatile | warden | | Skirts and a thicker box turret that holds a ridge against Tier IX standard rounds; HESH | HESH shell kit | Long hull with full skirts, broad box turret | `ci_regnion` |
| `ci_tesselion` | Tesselion | X | HT | Support | warden | | The most accurate heavy (≈ 0.33), −12°, α 460, HESH; peek, shoot, hide | HESH shell kit | Tallest Crown turret, very long barrel with the line's largest bore evacuator | `ci_sovrion` |
| `ci_precine` | Precine | IX | TD | Sniper | vernier | | Low front casemate, ±12° yaw, camo +0.04, armor ≤ 0.45 P; HESH alternative round | HESH shell kit | Low front casemate with a flat brass-trimmed face, long gun | `ci_regnion` |
| `ci_vernine` | Vernine | X | TD | Sniper | vernier | | Best Tier X dispersion (≈ 0.27), α 580, HESH; paper armor | HESH shell kit | Casemate set mid-hull, the faction's longest gun with a bore evacuator | `ci_precine` |
| `ci_calibine` | Calibine | VI | TD | Support | (vernier) | P | Fast-firing low-alpha casemate (α ≈ 221), speed ×1.1; credits ×1.35; trains Vernier crews | | Small sloped casemate, short bore-evacuated gun, brass trim | Store 1,600 BUL |
| `ci_aurelline` | Aurelline | XI | TD | Sniper | vernier | | HP 1,873, α 638, pen 325; ActiveCooling wins the 5-second duel it would otherwise lose | ★ ActiveCooling | Low casemate with radiator louvres along its sides, the longest gun in the game | `ci_vernine` (47,000 XP) |

### 2.3 Eastern Armor Group (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `ea_kirett` | Kirett | I | LT | Versatile | skirmish | | Fastest Tier I (≈ 51 km/h); a quick-firing or a harder-hitting gun | | Tiny wedge hull, forward wedge turret, 4 big wheels | starter (free) |
| `ea_essett` | Essett | II | LT | Scout | skirmish | | Best camouflage at Tier II, view range +10 m, weak gun | | Lower, longer wedge hull, very small turret | `ea_kirett` |
| `ea_veshett` | Veshett | III | LT | Scout | skirmish | | 57 km/h with a forward turret: show, spot, break contact | | Long narrow hull, forward turret, slotted brake debut | `ea_essett` |
| `ea_talett` | Talett | IV | LT | Support | skirmish | | Biggest gun on a Tier IV light (α and pen ×1.05), speed ×0.95 | | Barrel overhanging the nose, wedge turret | `ea_veshett` |
| `ea_sevett` | Sevett | V | LT | Versatile | skirmish | | 64 km/h and the fastest turret at V: circle and track | | Longer hull, 5 wide-spaced wheels, wing mudguards | `ea_talett` |
| `ea_venett` | Venett | VI | LT | Scout | skirmish | | Lowest light silhouette at VI, camo +0.03; weak gun | | Very low hull, turret nearly flush with the deck | `ea_sevett` |
| `ea_lirett` | Lirett | VII | LT | Support | skirmish | | High-pen gun (pen ×1.05) on a fast hull: unseen flank damage | | Long gun with slotted brake, turret forward | `ea_venett` |
| `ea_silett` | Silett | VIII | LT | Scout | skirmish | | Fastest tracked vehicle in W1 (70 km/h), best light camo at VIII | | Longest Eastern tracked hull, tiny turret | `ea_lirett` |
| `ea_zarett` | Zarett | IX | LT | Support | skirmish | | 4 × 286 in 6 s, then 32.5 s helpless; paper turret | Magazine 4, 2.0 s intra, 32.5 s reload, burst 1,144 (≤ 0.85 × 1,650) | Drum bulge across the turret rear | `ea_silett` |
| `ea_talzarett` | Talzarett | X | LT | Versatile | skirmish | | 3 × 340 with a quick intra-clip; pick the moment or waste 27 s | Magazine 3, 2.5 s intra, 26.9 s reload, burst 1,020 | Larger wedge turret with a drum bulge, long gun | `ea_zarett` |
| `ea_rhuvari` | Rhuvari | IX | LT | Versatile | outrider | | Cruise to fight, speed mode to relocate (70 → 91 km/h); −25 % speed per lost wheel pair | Wheeled: speed mode +30 %, steering ×0.6, reverse ×0.7, 1.0 s toggle, moving dispersion ×1.15 | 4 wheels per side, boat-shaped hull, small centred turret | `ea_silett` (engine) |
| `ea_lirvari` | Lirvari | X | LT | Scout | outrider | | Fastest vehicle in the game and best Tier X spotter, weakest Tier X gun (α 306) | Wheeled (as above) | Longer 8-wheel boat hull, low centred turret, exposed axle hubs | `ea_rhuvari` |
| `ea_sevzar` | Sevzar | V | LT | Support | (skirmish) | P | Brawler scout: bigger gun, speed ×0.95, credits ×1.35; trains Skirmish crews | | Short hull with an oversized wedge turret | Store 1,000 BUL |
| `ea_lirvesh` | Lirvesh | XI | LT | Support | skirmish | | 4 × 393 with top-off reloads; HP 1,763 | ★ AdaptiveMagazine (§2.7) | Drum bulge merged into a larger wedge turret, longest Eastern hull | `ea_talzarett` (47,000 XP) |

### 2.4 Desert Armor Corps (19)

SPG role trims are not in decisions §7.2 (only the names). Proposal for `Roles.luau` (O·L, tune by telemetry):
**SPGSupport** full stun, splash radius ×1.0; **SPGAreaControl** stun ×0.5, shell velocity ×1.15, splash radius
×0.85. Alpha stays 2 × MT alpha for both, so the direct-hit cap (≤ 45 % of same-tier MT HP) holds.

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `dc_waymark` | Waymark | I | MT | Versatile | caravan | | Quick aim (×0.94) and −10° from the first battle | | Boxy little hull under a sunshade canopy frame, round turret | starter (free) |
| `dc_bearing` | Bearing | II | MT | Support | caravan | | Fast reload; teaches sustained fire | | Short sand skirts debut, hexagonal turret | `dc_waymark` |
| `dc_sandglass` | Sandglass | III | MT | Sniper | caravan | | Best Tier III medium dispersion; tall cupola weak spot | | Tall cupola, long thin gun with sleeve bands | `dc_bearing` |
| `dc_parallax` | Parallax | IV | MT | Versatile | longshot | | Hull-down turret (×1.08) over a weak lower plate (×0.85) | | Full sand skirts, sloped glacis over a tall flat lower plate | `dc_sandglass` |
| `dc_azimuth` | Azimuth | V | MT | Sniper | longshot | | Long gun, best Tier V dispersion, view range +10 m | | Longest barrel at V with 2 sleeve bands | `dc_parallax` |
| `dc_meridian` | Meridian | VI | MT | Assault | longshot | | Thick turret (×1.08 × 1.15), HP ×1.05, speed ×0.92: holds a ridge under fire | | Wider hex turret with cheek plates | `dc_azimuth` |
| `dc_longsight` | Longsight | VII | MT | Sniper | longshot | | Best Tier VII medium dispersion, view range +10 m, low alpha | | Turret with rangefinder ears (a small cylinder on each side) | `dc_meridian` |
| `dc_sextant` | Sextant | VIII | MT | Versatile | longshot | | The double tap from cover | Autoreloader 2 × 260, refills 9.0 / 7.5 s (first after empty longest), sustained 0.92 | Boxy magazine bustle on the hex turret | `dc_longsight` |
| `dc_dawnfix` | Dawnfix | IX | MT | Assault | longshot | | Three shells from the strongest Desert turret; manage the long first refill | Autoreloader 3 × 320, refills 11.0 / 8.0 / 7.6 s | Heavy hex turret with cheek plates and magazine bustle | `dc_sextant` |
| `dc_sunward` | Sunward | X | MT | Sniper | longshot | | Flagship long-range medium: pen 273, aim 2.07 s | Autoreloader 3 × 400, refills 12.5 / 9.4 / 9.0 s | Longest Desert gun with 3 sleeve bands, magazine bustle | `dc_dawnfix` |
| `dc_dustfall` | Dustfall | IV | SPG | AreaControl | sunfall | | Light open-top howitzer, HE 170, no stun (stun starts at V) | | Open-top carriage on the caravan chassis, short howitzer, rear spade | `dc_sandglass` (engine) |
| `dc_ashfall` | Ashfall | V | SPG | Support | sunfall | | First stun (≤ 6 s), HE 230, 120 mm, splash 6.6 m | | Open-top, longer howitzer behind crew shield plates | `dc_dustfall` |
| `dc_emberfall` | Emberfall | VI | SPG | AreaControl | sunfall | | Fast light carriage, HE 320, small splash, quick relocation | | Low open-top carriage, small howitzer, 5 wheels | `dc_ashfall` |
| `dc_glassfall` | Glassfall | VII | SPG | Support | sunfall | | Heavy 155 mm howitzer, HE 440, splash 7.65 m, stun ≤ 10 s | | Half-enclosed box compartment, fat short howitzer | `dc_emberfall` |
| `dc_sunfall` | Sunfall | VIII | SPG | AreaControl | sunfall | | Long gun-howitzer: flatter arc, faster shell, HE 520, best direct hits in the line | | Half-enclosed compartment, very long barrel | `dc_glassfall` |
| `dc_starfall` | Starfall | IX | SPG | Support | sunfall | | Enclosed 360° turret covers two lanes, HE 640, stun ≤ 14 s | | Enclosed rear turret, long hull, rear recoil spades | `dc_sunfall` |
| `dc_noonfall` | Noonfall | X | SPG | Support | sunfall | | Flagship howitzer: HE 800, 155 mm, stun ≤ 16 s, slow and fragile | | Fully enclosed turret, longest howitzer, recoil spades, 6 wheels | `dc_starfall` |
| `dc_dunelight` | Dunelight | VIII | MT | Support | (longshot) | P | Single-shot DPM medium (reload ×0.92), no autoreloader, armor ×0.9; credits ×1.5; trains Longshot crews | | Short hex turret, mid-length gun, skirts hung with jerrycan racks | Store 3,500 BUL |
| `dc_zenith` | Zenith | XI | MT | Sniper | longshot | | HP 2,200, α 440, pen 295: the long-range duel winner if allowed to charge | ★ ChargedShot (dispersion ×0.6) | Tallest cupola, the game's longest medium gun with 4 sleeve bands, no magazine bustle | `dc_sunward` (47,000 XP) |

### 2.5 Mountain Republic (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `mr_screehare` | Screehare | I | LT | Scout | pathfinder | | Most agile Tier I, camo +0.03, −12° | | Tiny low hull, rear turret, 6 small wheels | starter (free) |
| `mr_cairnhopper` | Cairnhopper | II | LT | Versatile | pathfinder | | Climbs 35° slopes at speed; hull hits always penetrate | | Long low hull, raised front idler, rear turret | `mr_screehare` |
| `mr_ridgewren` | Ridgewren | III | LT | Scout | pathfinder | | Best Tier III ridge spotter: rear turret plus −12° | | Rear-turret silhouette on 7 small wheels | `mr_cairnhopper` |
| `mr_talus` | Talus | IV | MT | Versatile | ridgeline | | Only the turret crosses the crest; 54 km/h, hull ×0.60 | | Low hull, rear turret, gun overhanging the bow | `mr_ridgewren` |
| `mr_saddleback` | Saddleback | V | MT | Sniper | ridgeline | | Long gun, −12°, 58 km/h, paper hull | | Longer gun with the flash-hider cone, 8 small wheels | `mr_talus` |
| `mr_cornice` | Cornice | VI | MT | Versatile | ridgeline | | Fast turret and 60 km/h: rotate between ridges faster than enemies re-aim | | Wider rear turret, spare road wheels on the hull sides | `mr_saddleback` |
| `mr_scarp` | Scarp | VII | MT | Support | ridgeline | | Reload ×0.92, camo +0.02; the thinnest medium at VII | | Lowest Mountain medium, small rear turret | `mr_cornice` |
| `mr_highcol` | Highcol | VIII | MT | Sniper | ridgeline | | Stop 0.75 s, then −16°: shoots over crests no one else can | Hydropneumatic +4° depression / +3° elevation after 0.75 s still | Visible suspension cylinders, hull visibly pitches | `mr_scarp` |
| `mr_tarnwatch` | Tarnwatch | IX | MT | Sniper | ridgeline | | Longer gun, view range +10 m: spot and shoot from one peak | Hydropneumatic | Long gun, suspension cylinders, rear turret | `mr_highcol` |
| `mr_crestline` | Crestline | X | MT | Versatile | ridgeline | | Flagship generalist, 63 km/h, −16°, hull 0.30–0.42 P | Hydropneumatic | Longest Mountain hull, 8 wheels, cylinders, rear turret | `mr_tarnwatch` |
| `mr_tarnhold` | Tarnhold | IX | TD | Sniper | bastion | | Travel fast, stop, deploy, fire with aim ×0.4; any hit penetrates | SiegeMode: on 2.0 s / off 1.25 s, aim ×0.4, dispersion ×0.85, +8° dep / +6° elev, ≤ 10 km/h, hull traverse ×0.5 | Turretless hull-casemate, gun fixed in the bow, dozer blade | `mr_highcol` (gun) |
| `mr_peakhold` | Peakhold | X | TD | Support | bastion | | Tempo siege destroyer: reload ×0.9, 56 km/h in travel, −20° in siege | SiegeMode (as above) | Longer hull-casemate, twin side periscopes | `mr_tarnhold` |
| `mr_highstag` | Highstag | VIII | LT | Scout | (scree) | P | Climbing scout with −12°, credits ×1.5; trains W2 Scree crews | | Rear-turret light with a tall, narrow hull nose | Store 3,500 BUL |
| `mr_updraft` | Updraft | XI | MT | Versatile | ridgeline | | HP 2,200, α 440, 64 km/h, two bursts to take a crest first | ★ RocketBoost (2 × 2.5 s, +20 km/h, 30 s cooldown per charge) | Rear turret, two rocket pods on the rear hull flanks | `mr_crestline` (47,000 XP) |

### 2.6 Northern Federation (14)

| id | Name | T | Cls | Role | Branch | P | Combat identity | Mechanic | Visual hook | Parent |
|---|---|---|---|---|---|---|---|---|---|---|
| `nf_hoarling` | Hoarling | I | MT | Assault | frontier | | Thickest Tier I hull (×1.06 × 1.15), slow, generous HP | | Deep chamfered block hull, small hex turret | starter (free) |
| `nf_icepick` | Icepick | II | TD | Support | glacis | | Open-top gun carriage: quick reload, fragile; ambush and relocate | | Low chassis with an open gun shield | `nf_hoarling` (engine) |
| `nf_sleet` | Sleet | III | TD | Sniper | glacis | | Best TD camouflage at III, accurate (×0.94 kit) | | Low enclosed casemate, box muzzle brake debut | `nf_icepick` |
| `nf_hailstone` | Hailstone | IV | TD | Versatile | glacis | | Turreted (360°, α ×0.9): tracks moving targets | | Hexagonal open-top turret on a deep hull | `nf_sleet` |
| `nf_rimecrag` | Rimecrag | V | TD | Assault | glacis | | First assault casemate (1.1–1.4 P front), ±11° arc, camo −0.08 | | Front full-width casemate, continuous glacis slope | `nf_hailstone` |
| `nf_floewall` | Floewall | VI | TD | Assault | glacis | | Heavier casemate and bigger gun: anchors the heavy lane | | Taller casemate, wide skirts | `nf_rimecrag` |
| `nf_rimewall` | Rimewall | VII | TD | Support | glacis | | Lighter and faster (×1.1), reload ×0.9, armor ≤ 0.45 P: rotate and support | | Smaller casemate set mid-hull | `nf_floewall` |
| `nf_hoarwall` | Hoarwall | VIII | TD | Assault | glacis | | Wall up beside the heavies; the slope is the armor | | One continuous slope from nose to casemate roof | `nf_rimewall` |
| `nf_glacis` | Glacis | IX | TD | Assault | glacis | | Thickest frontal armor in the game (1.45 P clamp), deliberately weak cupola | | Massive chamfered casemate with a raised cupola | `nf_hoarwall` |
| `nf_winterwall` | Winterwall | X | TD | Assault | glacis | | 600 alpha behind 1.45 P, HP 1,741, the slowest Tier X destroyer (37 km/h) | | Longest Northern hull, huge box brake | `nf_glacis` |
| `nf_whiteout` | Whiteout | IX | HT | Versatile | rimeguard | | Most HP of any Tier IX heavy (2,079), accurate, sluggish | | Hexagonal turret at mid-hull on a deep chamfered hull | `nf_hoarwall` (engine) |
| `nf_deepwinter` | Deepwinter | X | HT | Breakthrough | rimeguard | | 46 km/h heavy, armor ×0.95; carries the push the destroyers start | | Lower, longer hull, hex turret set back | `nf_whiteout` |
| `nf_thawbreaker` | Thawbreaker | VIII | HT | Assault | (rimeguard) | P | Slow armored heavy with Northern HP; DPM at the 45th percentile; credits ×1.5; trains Rimeguard crews | | Squat hex turret, deep hull, wide skirts | Store 3,500 BUL |
| `nf_rimeburst` | Rimeburst | XI | HT | Breakthrough | rimeguard | | HP 2,772, α 550; Turbo turns a held line into a breach | ★ active Turbo (power ×1.25, 6 s, 40 s cooldown) | Hex turret, twin exhaust-heater stacks that glow during Turbo | `nf_deepwinter` (47,000 XP) |

### 2.7 Tier XI Apex specification

All six follow decisions §7.4: stats = Tier X baseline × (HP 1.13, α 1.10, pen 1.08, DPM 1.07) × role × kit, one
signature, matched only in X–XI battles, 10-node track (≤ +12 %; the final 12,000 XP node upgrades the
signature). Apexes carry **no** Tier I–X mechanic (no DualGun, Autoreloader, Hydropneumatic), so the signature is
the only thing new on the HUD.

| Apex | Class / role | Signature (base) | Final-node upgrade (proposal) | HUD widget | Why this faction |
|---|---|---|---|---|---|
| `iu_gorrtund` | HT Assault | ChargedShot, +10 % damage after 1.5 s; cancels on hull movement | charge 1.5 → 1.2 s | Charge ring on the reticle | The alpha faction gets the biggest single hit in the game |
| `ci_aurelline` | TD Sniper | ActiveCooling: reload and aim ×0.85 for 5 s, 45 s cooldown | cooldown 45 → 38 s | Cooling gauge with cooldown sweep | Precision turned into a short window of tempo |
| `ea_lirvesh` | LT Support | AdaptiveMagazine (below) | refill floor 0.35 → 0.30 | Magazine pips + per-pip refill bar | The magazine faction's magazine perfected |
| `dc_zenith` | MT Sniper | ChargedShot, dispersion ×0.6 after 1.5 s | charge 1.5 → 1.2 s | Charge ring | Long range made reliable |
| `mr_updraft` | MT Versatile | RocketBoost: 2 charges × 2.5 s, +20 km/h within 1 s, 30 s per charge | +1 charge (3) | Two boost pips | Terrain mobility taken vertical |
| `nf_rimeburst` | HT Breakthrough | active Turbo: power ×1.25 for 6 s, 40 s cooldown | duration 6 → 7.5 s | Turbo gauge | Survival heavies that refuse to be pinned |

**`AdaptiveMagazine`** (a `GunState.Magazine` variant; the decisions doc names it without numbers, so these are
O·L proposals for the combat owner): size 4, intra-clip 2.2 s; the magazine may be reloaded at any time and the
reload takes `T_m × (0.35 + 0.65 × spent / size)` (so topping off one shell costs 51 % of a full reload instead of
100 %); burst 4 × 393 = 1,572 ≤ 0.85 × the Tier XI MT HP (1,870); sustained DPM stays at 0.85 × class at full
empties, rising to ≈ 0.92 when topped off optimally. Partial reloads are interrupted by firing (no free shells).

### 2.8 Premium summary

| Premium | Tier / class / role | BUL | Credits | Alternative playstyle (never strictly better) | Crew it trains |
|---|---|---|---|---|---|
| `ea_sevzar` | V LT Support | 1,000 | ×1.35 | Brawler scout in a scouting faction | Eastern LT (Skirmish spine) |
| `ci_calibine` | VI TD Support | 1,600 | ×1.35 | Fast-firing, low-alpha destroyer in an accuracy faction | Crown TD (Vernier IX–X) |
| `iu_tammvarr` | VIII TD Versatile | 3,500 | ×1.5 | Turreted, DPM-leaning destroyer in an alpha faction | Iron TD (W2 Ram line) |
| `dc_dunelight` | VIII MT Support | 3,500 | ×1.5 | Single-shot DPM medium instead of an autoreloader | Desert MT (Longshot) |
| `mr_highstag` | VIII LT Scout | 3,500 | ×1.5 | Climbing scout in a medium-and-siege faction | Mountain LT (W2 Scree) |
| `nf_thawbreaker` | VIII HT Assault | 3,500 | ×1.5 | Armored heavy in a destroyer faction | Northern HT (Rimeguard IX–X) |

Power rules (decisions §7.4): every core stat at the 40th–55th percentile of its class × role × tier envelope and
nothing above the tech-tree P60; DPM and pen target 0.95–0.97 of the same-tier tech-tree median, compensated by
mobility or comfort (handling, camouflage) rather than by armor or alpha. None at IX–XI. A nerf of more than 5 %
opens the 14-day Bullion refund window. Lint flag `premium = true` enables the percentile check.

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

Heavies start at Tier IV and artillery at IV (decisions §7.4); Tier I has only lights and mediums. Every class
exists at every tier where it can appear, so the class mirror (decisions §8) can always be completed by bots.

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
`roleErr` penalty. For that penalty the bot picker should use these **role groups** (proposal for
`Matchmaking.luau`): *Frontline* (HT Assault, HT Breakthrough, MT Assault, TD Assault) · *Ranged* (MT Sniper,
TD Sniper, HT Support, TD Support, MT Support) · *Flexible* (all Versatile) · *Recon* (LT Scout) · *Skirmish*
(LT Support) · *Indirect* (SPG). Exact role match scores 0, same group 0.5, otherwise 1.

### 3.3 Supply per battle bracket

A battle draws from up to three tiers (templates 3/5/7, 5/10, 15; spread rules decisions §8), so the real pool is
larger than one tier column. Vehicles available to a battle whose top tier is T, using the widest legal template:

| Top tier (tiers in battle) | LT | MT | HT | TD | SPG | Pool |
|---|---|---|---|---|---|---|
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
3. **Default bot class mix** when no human constrains a team (proposal): per 15 at Tier IV+, MT 5, HT 4, TD 3,
   LT 3; at II–III, MT 9, LT 3, TD 3; at I, MT 12, LT 3 (the LT cap of 3 binds). Humans' classes replace these
   slots one for one.
4. **Variety:** within a team, bots field at most 2 copies of one vehicle while another vehicle of the same tier,
   class and role group exists; otherwise duplicates are allowed. Bots pick factions uniformly at random among
   eligible vehicles and may use premiums (they are inside the balance envelope and never get MM preference).
5. **Thin cells to watch** (single vehicle at that tier and class): TD II–V and VII, LT IV/VI/VII, HT IV, all SPG,
   LT and TD at XI. Telemetry per (tier, class): human pick share, bot duplicate rate and win rate. If a thin cell
   carries more than 30 % of the class's bot fills at its tier, it goes up the W2 priority list (§6.1).
6. **Tier XI** meets only X–XI. An XI human LT is mirrored by `ea_lirvesh` or, after relaxation (±1 class), any LT X.
7. **Starter spread:** all six Tier I starters are free and equal in power; a new player's faction choice is a
   matter of taste, never of strength. Tier I–II MM is single-tier (decisions §8), so supply per battle at I is
   6 vehicles; bots there use Recruit skill for the first 20 battles.

