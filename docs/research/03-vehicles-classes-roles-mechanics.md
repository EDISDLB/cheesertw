# Vehicle Classes, Roles, Tiers (incl. Tier XI), Stat Ranges, Module Trees and Special Mechanics: World of Tanks reference research for HULLDOWN

Research date: 2026-10-05. Reference game: World of Tanks PC (Wargaming EU/NA/Asia). The live version is 2.4 "Overdrive" (September 2026) per report 05. Lesta's *Mir Tankov* was not analysed. Its version numbers have diverged: XVM's changelog lists "Mir Tankov 1.36" alongside "World of Tanks 1.29.1.1 → 2.0".

**Evidence note (read first).**
- The egress proxy blocked worldoftanks.\*, wargaming.net, Wikipedia, fandom, tanks.gg, reddit, archive.org and the news sites. This session's web-search budget was already used up (200/200) when the task started.
- The evidence therefore comes in four kinds, and every claim is tagged with one:

| Tag | Meaning | How much to trust it |
|---|---|---|
| **[API]** | Numbers I computed from **Wargaming's public Tankopedia web API** (`/wot/encyclopedia/vehicles/` and `/vehicleprofile/`) responses mirrored on GitHub. These are official, published data, not datamined client files. | High *for that snapshot's date* |
| **[Sib]** | Facts that sibling reports [01](01-ballistics-armor-damage.md), [02](02-spotting-camouflage.md) and [05](05-progression-economy-crew-equipment.md) obtained from official WG pages through web search. The URLs are theirs; **I did not re-verify them**. | As rated there (mostly Medium–High) |
| **[Comm]** | Community GitHub repositories: unicum.gg (a stats site), the XVM changelog, and a Wikipedia-text mirror. | Medium |
| **[Rec]** | My recollection of long-standing official or community material, **not re-verified this session**. | Low–Medium, as rated |

- Anything that is not a WoT fact is labelled **OUR DESIGN CHOICE**.
- I deliberately did **not** use extracted client sources (e.g. `wot-src` mirrors), even though code search surfaced them.
- **Fact-check pass (2026-10-05).** 15 implementation-critical claims were re-checked; see the **Verification log** at the end. Every [API] number re-checked was recomputed from fresh copies of the three GitHub mirrors. The snapshot dates were wrong and have been fixed throughout: every "≈2022" label now reads **Aug 2021** and every "2017–18" label now reads **May 2017** (corrected by fact-check). Inline edits are marked "(corrected by fact-check)".

**API snapshots used**

| Snapshot | Content | Date (inferred from the roster) | Use |
|---|---|---|---|
| `GuilleHoardings/wot_tank_data/wot_data.csv` | 708 vehicles × every module configuration (14,691 rows): HP, weight, speeds, engine hp, standard-shell alpha/pen, fire rate, DPM, aim time. Queried from `api.worldoftanks.eu/.../vehicleprofile/` | **Aug 2021** (corrected by fact-check; was "≈ late 2022"): the repo's data commit is "Update data for patch 1.14" (2021-08-16) and its last commit is 2021-08-31. Contains Vz. 55, Rinoceronte, Kampfpanzer 07 RH; no Minotauro, Concept 5 or Obj. 452K | Top/stock combat and mobility stats |
| `aki33524/wotdatabase/API/vehicles/1..6` | 508 vehicles, **stock** `default_profile`: nominal armor, traverse, view range, dispersion, arcs, load limit, **siege profile**, **SPG stun durations**, module research graph | **May 2017** (corrected by fact-check; was "≈ 2017–18"): all four commits are dated 2017-05-16. Static 2.55.0; already 9.18-era (Tier X LTs, stun) | Armor, handling, stun, siege, module dependencies |
| `Roexoe/guesswot/wottanks.json` | 917 vehicles: tier, class, nation, premium flag, weight, speed | ≈ 2024–25 (static 2.76.0). Has Concept 5, Obj. 452K, TL-7; **no Tier XI** | Roster composition and premium share |

---

## Summary

1. **There are five classes.** Their WoT identities are clear in the data. Medians of class ÷ medium tank at Tiers VI–X [API]:

   | Class | HP | Alpha | Reload | Pen | DPM | Top speed | Hull traverse | Hull-front armor | Other |
   |---|---|---|---|---|---|---|---|---|---|
   | Heavy | 1.17 | 1.26 | 1.28 | 1.04 | 0.94 | 0.73 | 0.57 | 1.60 | |
   | Tank destroyer | 0.80 | 1.68 | 1.50 | 1.19 | 1.04 | 0.78 | | | dispersion 0.92; 83% turretless |
   | Light | 0.77 | 0.85 | | 0.88 | 0.86 | 1.18 | 1.18 | 0.50 | power-to-weight 1.77 |
   | SPG | 0.29 | 2.56 | 4.56 | | 0.61 | | | | dispersion 1.75; view range 0.74 |

2. **View range is nearly flat across classes at a given tier.** Stock medians are 280 m at Tier I and 400–405 m at Tier X, and every class except SPGs is within ±3% [API]. The scouting identity comes from **camouflage** and equipment, not from base view range. Report 02's light-tank view-range bonus is therefore a deliberate deviation, not WoT parity.
3. **Vehicle roles exist and are still first-class in 2.x.** WoT tags every vehicle with a role token. Role names [Comm, Medium; date and version are Low, Rec]:

   | Class | Roles |
   |---|---|
   | Heavy | Assault, Breakthrough, Support, Versatile |
   | Medium | Assault, Sniper, Support, Versatile |
   | Tank destroyer | Assault, Sniper, Support, Versatile |
   | Light | Wheeled; by 2.4 also Scout, Support, Versatile |
   | SPG | none (single SPG role) |

   Roles arrived around Update 1.10/1.10.1 (2020). XVM 13.0.0 for WoT 2.0 added a `{{v.role}}` macro.
4. **What roles do today:**
   - The specialised Equipment-2.0 slot is set per vehicle by role [Sib].
   - The later Field Modification choices are role-specific (1.14, 2021) [Sib, Comm].
   - Personal Missions 3.0 (2.0) has role series (Vanguard, Ambush, Assistance) [Sib].
   - **Matchmaking takes roles into account since 2.0.** WG's official 2.0 overview says "vehicle roles are taken into account", e.g. "a Badger against a T110E3, not against a Grill 15" (corrected by fact-check; this previously said only 2.4 light tanks feed matchmaking). A precursor, 9.20.1 (2017), already balanced Tier VIII–X "combat subroles" [Sib 04 fact-check; Comm].
   - Since 2.4, light-tank subclasses are reported to cap light tanks at **at most 2 per team** [Sib, **unverified**].
   - A role badge appears in the tech tree, carousel and tooltips.
   - The 2020 "role action points" for defeat-XP mitigation is **unverified** [Rec, Low].
5. **Tier XI is live.** It came with **Update 2.0 (3 Sept 2025)** [Sib]:
   - 16 vehicles at launch: 7 heavy, 5 medium, 3 TD and 1 light. Every nation except Italy has at least one [Comm].
   - Unlock: **325,000 XP earned on a Tier X, then 7,400,000 credits** [Sib; **unverified**, Medium (corrected by fact-check)].
   - Progression is a node track that replaces Field Modification, then Elite levels (confirmed by WG's 2.0 overview narration). "Up to 25 nodes" costing 10k / 20k / final 25k XP is [Sib; **unverified**, Medium].
   - Each Tier XI has a signature mechanic: secondary guns, charge-up accuracy, rocket boosters, direct drive [Sib].
   - More Tier XIs arrived in 2.1.1 (Jan 2026) and 2.4 (Sept 2026), the latter with adaptive autoloaders, alternative fire modes, rocket assist and recon systems [Sib].
6. **Matchmaking in 2.x** [Sib]:
   - Mostly ±1 tier, with some ±2 (direction confirmed; exact mix unverified).
   - Class caps: ≤3 light and ≤5 TD (**confirmed** by WG's 2.0 narration via the sibling 04 fact-check); ≤1 wheeled and ≤3 SPG (**unverified** for 2.0); since 2.4, ≤2 light (**unverified**) (corrected by fact-check).
   - Roles are balanced too (item 4).
   - The ≤3 SPG cap and the 3/5/7, 5/10 and single-tier templates date from **9.18 (2017)** [Rec → Medium-High after fact-check: a community Random-MM reimplementation uses 0–3 SPGs and these templates and cites WG's 9.18 announcement].
7. **Tier stat ladder (medium tanks, top configuration, Aug 2021)** [API]:

   | Tier | HP | Std pen (mm) | Alpha | DPM |
   |---|---|---|---|---|
   | I | 300 | 45 | 50–70 | ≈ 930–1,170 |
   | V | 600 | 124 | 115 | ≈ 1,600 |
   | VIII | 1,400 | 212 | 250 | ≈ 2,000 |
   | X | 1,950 | 263 | 390 | ≈ 2,750 |

   - HP grows ×1.15–1.40 per tier from Tier V up, ×1.27 on average.
   - Pen grows about +30 mm per tier from VI to IX, then flattens at X.
8. **Stock and top configurations differ in firepower and power-to-weight, almost never in top speed** [API]. Only 1 of 708 vehicles (IS-2) has a module-dependent top speed (corrected by fact-check; this said "never"). Medians, top ÷ stock, Tiers II–IX:

   | Stat | Ratio |
   |---|---|
   | HP | ×1.00–1.10, from the turret |
   | Power-to-weight | ×1.10–1.29 |
   | Std pen | ×1.03–1.97 (up to ×2.7 on low-tier heavies) |
   | DPM | ≈ ×1.0 |
   | Top speed | **×1.00** (1 exception in 708) |

   Tier X tech-tree vehicles are effectively sold fully upgraded: the median vehicle has 1 configuration.
9. **The research graph is mostly linear chains per module type** [API, May 2017]:
   - Gun→gun (470 edges), radio→radio (457), engine→engine (411), suspension→suspension (314), turret→gun (138: **top guns need the upgraded turret**), gun→turret (69).
   - Next vehicles are unlocked mainly by **guns**: 230 of 357 unlocks (64%), then turrets (54), engines (34), suspensions (21) and radios (18). These are recounted for Tiers II–X; they were 222 / 51 / 34 / 21 / 16 = 344 (corrected by fact-check).
   - Weight dependency is implicit: **stock suspensions sit at a median of only 1.4–3.2% spare load capacity** (Tiers II–IX), so heavier turrets or guns usually require the suspension first.
10. **WoT has spent 2024–2025 simplifying modules** [Sib]:
    - 1.26 left rebalanced lines with a single (top) radio.
    - 2.0 "streamlined" radios and suspensions and made stock vehicles stronger.
    - **HULLDOWN should launch with that simplified model:** no radio module and 2–4 meaningful upgrades.
11. **Special mechanics in Random Battles:**
    - autoloader (magazine), autoreloader (per-shell timers), dual-gun (single shot or charged volley);
    - Swedish siege mode, hydropneumatic suspension, wheeled vehicles with drive modes;
    - Tier XI signature mechanics.
    - Mode-only abilities are confined to Steel Hunter, Frontline, Strongholds and events: airstrikes, smoke, minefields, "acid shells", flame effects, respawn and so on [Comm, Sib].
12. **Siege mode, official API numbers (Strv 103B)** [API]:
    - Aim time 3.0 → **1.0 s** and dispersion 0.30 → **0.25**.
    - Reverse speed 45 → **10 km/h**. The hull is **not** locked: the gun is fixed, so the hull turns to aim. The API's siege `suspension_traverse_speed` is `1`, against 35 °/s in travel; its unit is unclear (corrected by fact-check; this said "hull traverse is locked").
    - Transition **2.0 s** in, **1.25 s** out.
13. **SPG stun (introduced 9.18).** Each SPG HE shell carries a stun duration range `[min, max]` [API]:

    | Shell | Stun range |
    |---|---|
    | Low-tier ≤105 mm guns | `[0, 0]`, no stun |
    | Mid-tier 150–155 mm | 4.3–10.5 s |
    | Tier VII–IX | 7.2–28 s |
    | Tier X | 13.0–35 s |

    - `min ≈ 0.45–0.65 × max`; larger guns have a lower ratio.
    - Tier X SPG HE: 750–1,300 alpha, 45–60 mm pen, 32–52 s reload, 0.59–1.08 dispersion.
14. **Premiums are stat-neutral to slightly weaker than tech-tree vehicles, by design** [API, Tier VIII medians, premium ÷ tech tree]:

    | Class | HP | DPM | Pen | Notes |
    |---|---|---|---|---|
    | Medium | 0.96 | 0.94 | 0.97 | |
    | Heavy | 0.97 | 0.95 | 1.00 | alpha ×1.12, reload ×1.20 |
    | Tank destroyer | 1.02 | 0.96 | 0.97 | faster: speed ×1.28 |

    - The money advantage is economic: higher credit coefficient, +50% crew XP, crew-trainer flexibility, and preferential matchmaking on some Tier VIIIs [Sib, Rec].
    - Tier VIII holds **184 of the 429** premium or reward vehicles in the 2024–25 roster [API].
15. **National flavor is measurable** [API, Tiers V–X, normalised by class and tier]:

    | Nation | Pattern |
    |---|---|
    | USSR, China | Poor depression (**−5°** median), worse accuracy (USSR dispersion ×1.08), big alpha (China ×1.12) |
    | US | −10° depression, fast aim (×0.93) |
    | UK | Accurate (×0.92), low alpha (×0.91), fast reload |
    | Germany | Accurate (×0.95), more HP and armor (×1.05 / ×1.08), sluggish (power-to-weight ×0.95) |
    | Japan | Bulky: HP ×1.08, armor ×1.15, slow (×0.82) |
    | Sweden | Fast (×1.28), **−12°** depression, paper hull (×0.49) |
    | Poland | Alpha ×1.23, reload ×1.24 |
    | Czech | Fast (power-to-weight ×1.15), thin armor (×0.71) |
    | France | Mobile, thin turrets (×0.73), autoloaders |
    | Italy | Autoreloaders |

16. **HULLDOWN recommendations (OUR DESIGN CHOICE; detail in the implementation section):**
    - Keep the five classes. Ship artillery as a capped, low-damage, stun-centred support class with hard counterplay.
    - Use WoT-shaped roles (4 per class) as a UI badge, slot specialisation, a Role Score for rewards and defeat-XP protection, and soft matchmaking balancing.
    - Tiers I–X plus a small Tier XI "Apex" tier, matched X–XI only.
    - 2–4 module upgrades per vehicle; the stock-to-top delta is capped at about 15% effectiveness; no radios.
    - Mechanics are data-driven: Magazine, Autoreloader, DualGun, SiegeMode, Hydropneumatic, Wheeled, Turbo, RocketBoost, ChargedShot. Exotic ones are reserved for Tier XI and event modes.
    - Premiums are power-neutral (40th–55th percentile) and earnings-positive.
    - Faction identities are built from the nation patterns above, as ±5–12% stat "kits".

---

## Detailed findings

### 1. The five classes: design intent, strengths and weaknesses

#### 1.1 Modern behavior

| Class | Design intent (WoT, 2025–26) | Strengths (data) | Weaknesses (data) |
|---|---|---|---|
| **Light (LT)** | Spotting and information, flanking, harassment, finishing damaged targets, capping and resetting. Wheeled LTs are extreme mobility scouts. Since 2.4, LTs come in Scout, Versatile and Support subclasses, reportedly capped at 2 per team [Sib, unverified]. | Top speed ×1.18, hull traverse ×1.18, turret traverse ×1.16. Highest power-to-weight: Tier X median 42 hp/t versus MT 19. Best camo. LT moving camo equals stationary camo [Sib 02]. | HP ×0.77; hull armor ×0.5, overmatched by almost everything; DPM ×0.86; pen ×0.88. Tier X LT median reload is 10.7 s, against 8.5 s for MTs. |
| **Medium (MT)** | A generalist: mid-range trading, rotating between flanks, DPM and accuracy, holding ridges. Roles are Assault, Sniper, Support and Versatile. | The best balance. Highest sustained DPM among turreted tanks at Tier X (2,752 median). Good accuracy (0.35 at X). | No single dominant trait. Armor is reliable only on some turrets (Tier X turret front 182 mm nominal, but the median hull is 105 mm). |
| **Heavy (HT)** | The front line: absorbing damage, brawling, pushing chokepoints. Assault means slow and very armored; Breakthrough means mobile; Support means a lighter heavy with a strong gun; Versatile means a balanced heavy. | HP ×1.17 (Tier X 2,350); alpha ×1.26 (Tier X 490); hull front ×1.6 and sides ×1.78 (Tier X nominal 185/120/88); turret front 245 mm. | Speed ×0.73; hull traverse ×0.57; turret traverse ×0.63; aim time ×1.23; reload ×1.28. |
| **Tank destroyer (TD)** | Damage dealing from concealment: holding lanes, punishing exposed targets, ambushing. Armored "assault" TDs act as pseudo-heavies. 83% are turretless, with a median ±11° gun arc. | Alpha ×1.68 (Tier X 750, up to 1,020); pen ×1.19 (Tier X 294); best accuracy (×0.92); highest camo [Sib 02]. | HP ×0.80; speed ×0.78; a limited firing arc means flanking is lethal; slow turret on the few turreted TDs (×0.45); long reload ×1.50 (Tier X 17 s). |
| **SPG (artillery)** | Indirect fire over cover. Since 9.18 its job is area denial and **stun support**: a team-play multiplier rather than one-shot kills. | Alpha ×2.56 (HE splash); can hit targets behind cover; stun assist pays XP and credits. | HP ×0.29 (Tier X ≈ 510); view range ×0.74; dispersion ×1.75; reload ×4.6 (Tier X ≈ 39 s); depends on allied spotting; pen ×0.25, so HE only. |

**Confidence.** High for the numeric ratios, which come from the [API] snapshots: medians of per-tier ratios at Tiers VI–X; armor, traverse and view range use stock data from May 2017. Medium for the design-intent wording [Rec, Sib].

#### 1.2 History

**9.18 (2017).** This update reshaped two classes [Rec, Medium → **Medium-High** after fact-check: the XVM 6.6.0 build for "World of Tanks 9.18 worldwide release" added a stun marker. The May 2017 API dump already has Tier X LTs and per-shell stun. A community MM reimplementation cites WG's 9.18 announcement for 0–3 SPGs and the 3/5/7, 5/10 and single-tier templates]:
- **Light tanks:** branches were extended to Tier X. Before that, light tanks topped out at Tier VIII and used "scout matchmaking" that placed them in battles up to 3 tiers above.
- **SPGs:** the stun mechanic was added and per-team caps were introduced.
- **Why:** WG wanted light tanks to stop being "spotting-only, tier-crushed" vehicles and wanted to cut arty's one-shot frustration.
- **Corroboration:** the May 2017 API snapshot already contains Tier X LTs (T-100 LT, Rheinmetall Panzerwagen, Sheridan, AMX 13 105, WZ-132-1) and per-shell stun data.

**Wheeled light tanks** (French branch, Update 1.4, 2019) [Rec, Medium; **unverified**]. The fact-check found only that XVM 7.7.8, built for the WoT **1.3** client, already added hints for "changing the driving mode (for wheeled vehicles)". That fits a 1.3/1.4 arrival but does not pin the version.

**2.4 (2026):** LT subclasses arrive, with the ≤2 LT cap [Sib; the cap is unverified].

**Sources.**
- [API]: [wot_tank_data](https://github.com/GuilleHoardings/wot_tank_data), [wotdatabase](https://github.com/aki33524/wotdatabase), [guesswot roster](https://github.com/Roexoe/guesswot)
- [WG API docs (encyclopedia)](https://developers.wargaming.net/reference/all/wot/encyclopedia/vehicles/)
- [Sib 05 → Update 2.4 Overdrive](https://worldoftanks.com/en/news/updates/wot-2-4/)
- [Sib 02 camo](02-spotting-camouflage.md)

---

### 2. The vehicle ROLE system

#### 2.1 Modern behavior

**Roles per class.** WoT exposes a role token per vehicle: `role_HT_assault`, `role_MT_sniper`, `role_ATSPG_support`, `role_LT_wheeled`, and so on, with `role_SPG` for artillery. Community tooling that tracks the game lists these English display names, "WoT's own English names" [Comm]: `assault` → **Assault**, `break` → **Breakthrough**, `support` → **Support**, `universal` → **Versatile**, `sniper` → **Sniper**, `wheeled` → **Wheeled**. `scout` for light tanks appears only in the same site's Field Modification keys (`role_LT_scout_pair_*`), not in its role-label list (clarified by fact-check).

The role-keyed Field Modification strings on the same site show which roles exist per class:

| Class | Roles (role token suffix) | Typical vehicle archetype [Rec] |
|---|---|---|
| Heavy (`HT`) | **Assault** (`assault`), **Breakthrough** (`break`), **Support** (`support`), **Versatile** (`universal`) | Assault: slow, super-armored. Breakthrough: fast, armored and aggressive. Support: weaker armor, strong gun and depression. Versatile: balanced. |
| Medium (`MT`) | **Assault**, **Sniper**, **Support**, **Versatile** | Assault: armored brawler medium. Sniper: accurate, high pen, poor brawling. Support: high DPM, second line. Versatile: generalist. |
| Tank destroyer (`ATSPG`) | **Assault**, **Sniper**, **Support**, **Versatile** | Assault: heavily armored casemate. Sniper: concealed long-range glass cannon. Support: fast, high DPM. Versatile: turreted or balanced. |
| Light (`LT`) | **Wheeled**, **Scout**, **Support**, **Versatile** | Wheeled: extreme mobility. Scout: spotting specialist. Support: better gun. Versatile: balanced. The 2.4 news describes the LT subclasses as scout / versatile / support [Sib]. |
| SPG | **SPG** (`role_SPG`), no subrole | — |

**How roles affect gameplay (2025–26):**
1. **Presentation.** Each role has an 18×18 badge glyph shown in the tech tree, vehicle tooltip, carousel and Tankopedia [Comm: "the badge shown in the tech tree"].
2. **Equipment slot specialisation.** Under Equipment 2.0, Tier VI–X vehicles have one specialised slot (Firepower, Survivability, Mobility or Scouting) that gives about +15% of the item's effect. The slot category is **set per vehicle by role** [Sib 05].
3. **Field Modification** (Tier VI–X, Update 1.14, 2021) [Sib 05, Comm].
   - Each step is a binary choice of two tweaks.
   - The **early steps are class-wide**. Community key structure: `role_heavyTank_pair_1..3`, i.e. pairs 1–3.
   - The **later steps are role-specific**: `role_HT_break_pair_4..5`, `role_MT_sniper_pair_4..5`, and so on.
   - Example names [Comm]:

     | Role | Pair names |
     |---|---|
     | HT Breakthrough | "Reinforced/Lightweight Platform" |
     | TD Sniper | "PTO Tuning / Electric Aiming Drive" |
     | LT Wheeled | "Recon Kit / Assault Kit" |

4. **Missions.** Personal Missions 3.0 (2.0) is organised in **role series**: Vanguard, Ambush, Assistance [Sib 05].
5. **Matchmaking.** Role-level balancing **does** exist for all classes. WG's official "Update 2.0: Overview" narration says "vehicle roles are taken into account", and that "the matchmaker will put a Badger against a T110E3, not against a Grill 15". This was found by the sibling 04 fact-check, in captions mirrored on GitHub. An earlier form appeared in 9.20.1 (2017), whose "matchmaker improvements" added Tier VIII–X "combat subroles", per a community Random-MM reimplementation that cites that WG article. (Corrected by fact-check: this previously said "no evidence was found of role-level balancing for other classes".) Since **2.4**, light-tank subclasses are reported to cap LTs at **2 per team** [Sib 05, **unverified**]. Class caps remain (Summary item 6, §8.1).
6. **Role-specific actions ("action points") and XP in defeat** [Rec, **Low**]. My recollection of the 2020 role release:
   - each role had a list of "priority actions" (e.g. absorbing damage for an Assault heavy, spotting for a scout);
   - those actions earned points used to rank the losing team's best players for reduced defeat-XP loss.
   - **I could not verify that this system still exists in 2.x, or how it is computed.** HULLDOWN should treat it as inspiration only (see R2).

#### 2.2 History

| When | What | Confidence |
|---|---|---|
| 1.10 (4 Aug 2020) | Equipment 2.0 and specialised slots [Sib] | High |
| 1.10–1.10.1 (Aug–Oct 2020) | Vehicle roles introduced. **Why:** to give each tank a clear intended playstyle, to support role-based slots, Field Modification and missions, and to give players actionable guidance. | **Low** for the exact version |
| 1.14 (2021) | Role-based Field Modification [Sib] | Medium-High |
| 2.0 (Sept 2025) | Roles carried into the 2.0 client. XVM 13.0.0 (the 2.0-compatible build) added `{{v.role}}` / `{{v.role_l}}` macros [Comm, confirmed by fact-check]. The rewritten matchmaker takes roles into account (corrected by fact-check). Personal Missions 3.0 uses role series [Sib]. | Medium-High |
| 2.4 (Sept 2026) | LT role subclasses (scout / versatile / support) with a ≤2-LT team cap [Sib]. The 2.4 date is confirmed by mod-catalog and client-mirror dates (2.4.0.0, 2–3 Sept 2026). The subclasses and the cap are **unverified**. | Medium (date High) |

**Sources.**
- [unicum.gg role constants (VEHICLE_ROLE_LABEL)](https://github.com/unicum-gg/unicum.gg/blob/main/packages/shared/src/constants/tanks.ts)
- [unicum.gg Field Modification role keys (en locale)](https://github.com/unicum-gg/unicum.gg/blob/main/apps/web/src/locales/en/game/equipment.json)
- [XVM ChangeLog (13.0.0 for WoT 2.0)](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md)
- [Sib 05 → WG support: How Equipment 2.0 works](https://wargaming.net/support/en/products/wot/article/33291/)
- [Sib 05 → Field Modification 1.14](https://worldoftanks.com/en/news/updates/update-1-14-field-modification/)
- [Sib 05 → PM 3.0](https://worldoftanks.eu/en/news/general-news/update-2-0-personal-battle-missions-3-0/)
- [Sib 05 → 2.4](https://worldoftanks.com/en/news/updates/wot-2-4/)

---

### 3. Tiers I–X: stat ranges per class (calibration tables)

#### 3.1 Method

- **(A) tables.** From the EU API `vehicleprofile` dump, Aug 2021:
  - Tech-tree vehicles only (premium and gift excluded).
  - **Top configuration** = the configuration that maximises (HP, standard-shell pen, engine power, DPM), in that order.
  - Alpha and pen are the **standard (first) shell's average**.
  - `DPM = fire_rate × alpha`, using the API's `fire_rate`. For autoloaders and autoreloaders that is WG's effective rate.
  - Power-to-weight is `engine hp ÷ weight in tonnes`. WoT's weights and horsepower are **gameplay values**. For example, the API lists the T-100 LT at 15.0 t and 720 hp. Only the ratio is meaningful.
- **(B) tables.** From the May 2017 API dump:
  - **stock** configuration, so turret armor, view range and hull traverse are a little lower than with top modules;
  - hull armor is the same in stock and top;
  - armor is the API's **nominal** thickness of the main plate (front/side/rear). Effective thickness from slope is higher, especially on heavy-tank hulls and turrets;
  - for turretless TDs the "turret" armor columns are blank or ambiguous;
  - turret-traverse medians include only vehicles with 360° turrets.
- **Camouflage is not in the API.** Use report 02's class defaults (§3.4).
- Medians are shown with P10–P90 in brackets.

#### 3.2 Tables
**Light tanks (A): top configuration, tech tree, EU API, Aug 2021.** Cells are median (P10–P90).

| Tier | n | HP | Top speed km/h | hp/t | Alpha (std shell) | Pen mm (std) | DPM | Reload s | Aim s |
|---|---|---|---|---|---|---|---|---|---|
| I | 11 | 245 (235–280) | 25 | 10.7 | 40 (30–50) | 40 (33–45) | 900 (720–968) | 2.8 | 2.0 |
| II | 19 | 340 (318–360) | 40 | 13.9 | 40 (24–47) | 48 (40–56) | 960 (704–1226) | 2.3 | 1.9 |
| III | 18 | 418 (390–445) | 49 | 20.0 | 48 (29–70) | 64 (52–81) | 1213 (947–1436) | 2.5 | 2.0 |
| IV | 10 | 520 (508–541) | 55 | 22.5 | 65 (39–78) | 74 (58–88) | 1452 (1051–1712) | 2.3 | 2.1 |
| V | 7 | 550 (520–568) | 60 | 26.6 | 70 (58–162) | 96 (82–111) | 1737 (1312–1896) | 2.3 | 1.9 |
| VI | 8 | 670 (647–680) | 61 | 27.0 | 115 (100–121) | 128 (117–140) | 1647 (1427–1919) | 4.1 | 1.9 |
| VII | 8 | 855 (813–886) | 62 | 25.9 | 160 (135–206) | 152 (144–166) | 1610 (1432–1860) | 6.0 | 2.0 |
| VIII | 7 | 1050 (968–1100) | 65 | 34.0 | 230 (170–244) | 180 (170–204) | 1870 (1493–2016) | 7.7 | 2.1 |
| IX | 7 | 1250 (1180–1400) | 65 | 35.3 | 240 (240–278) | 212 (197–225) | 2057 (1714–2212) | 7.4 | 2.2 |
| X | 7 | 1500 (1360–1600) | 68 | 42.4 | 390 (312–390) | 236 (214–247) | 2164 (1839–2401) | 10.7 | 1.9 |

**Light tanks (B): armor and handling, stock configuration, API, May 2017.** Cells are medians. Armor is nominal mm, front/side/rear.

| Tier | n | Hull F/S/R | Turret F/S | Hull trav °/s | Turret trav °/s | View range m | Dispersion m@100 | Depression / elevation ° |
|---|---|---|---|---|---|---|---|---|
| I | 8 | 15/15/15 | 15/15 | 45 | 34 | 280 | 0.54 | −8 / +25 |
| II | 18 | 25/16/16 | 16/15 | 36 | 32 | 285 | 0.51 | −10 / +20 |
| III | 16 | 30/20/15 | 30/15 | 40 | 38 | 310 | 0.46 | −10 / +20 |
| IV | 10 | 30/27/25 | 38/31 | 39 | 44 | 330 | 0.42 | −10 / +20 |
| V | 5 | 37/30/30 | 38/30 | 40 | 44 | 360 | 0.42 | −8 / +18 |
| VI | 6 | 38/25/21 | 38/28 | 44 | 44 | 360 | 0.40 | −8 / +20 |
| VII | 6 | 38/21/20 | 42/26 | 43 | 45 | 370 | 0.40 | −8 / +20 |
| VIII | 5 | 40/25/20 | 25/25 | 46 | 48 | 380 | 0.38 | −6 / +15 |
| IX | 5 | 50/25/19 | 40/25 | 38 | 44 | 390 | 0.38 | −6 / +18 |
| X | 5 | 50/30/15 | 40/20 | 54 | 43 | 400 | 0.42 | −8 / +15 |

**Medium tanks (A): top configuration, tech tree, EU API, Aug 2021.** Cells are median (P10–P90).

| Tier | n | HP | Top speed km/h | hp/t | Alpha (std shell) | Pen mm (std) | DPM | Reload s | Aim s |
|---|---|---|---|---|---|---|---|---|---|
| I | 1 | 300 (300–300) | 24 | 7.6 | 70 (70–70) | 45 (45–45) | 933 (933–933) | 4.5 | 2.3 |
| II | 5 | 380 (356–392) | 32 | 11.3 | 50 (42–73) | 48 (31–55) | 1167 (1088–1644) | 2.3 | 2.0 |
| III | 6 | 455 (392–490) | 42 | 14.0 | 52 (42–62) | 65 (58–68) | 1278 (1091–1636) | 2.2 | 1.8 |
| IV | 13 | 540 (478–540) | 42 | 16.2 | 75 (56–110) | 92 (71–111) | 1680 (1514–1943) | 2.5 | 2.2 |
| V | 15 | 600 (590–630) | 48 | 17.3 | 115 (95–135) | 124 (110–135) | 1607 (1305–1675) | 4.8 | 2.3 |
| VI | 15 | 840 (820–896) | 54 | 16.6 | 135 (115–240) | 145 (128–156) | 1920 (1740–2091) | 4.2 | 2.3 |
| VII | 13 | 1100 (1100–1250) | 55 | 17.2 | 240 (135–300) | 160 (145–175) | 1800 (1545–2128) | 8.0 | 2.3 |
| VIII | 13 | 1400 (1300–1450) | 50 | 17.0 | 250 (240–352) | 212 (190–222) | 2000 (1765–2192) | 8.0 | 2.2 |
| IX | 15 | 1700 (1620–1780) | 55 | 19.9 | 390 (320–408) | 248 (223–268) | 2398 (2013–2650) | 9.6 | 2.2 |
| X | 16 | 1950 (1825–2025) | 55 | 19.0 | 390 (320–440) | 263 (250–273) | 2752 (2367–3021) | 8.5 | 2.1 |

**Medium tanks (B): armor and handling, stock configuration, API, May 2017.** Cells are medians. Armor is nominal mm, front/side/rear.

| Tier | n | Hull F/S/R | Turret F/S | Hull trav °/s | Turret trav °/s | View range m | Dispersion m@100 | Depression / elevation ° |
|---|---|---|---|---|---|---|---|---|
| I | 1 | 6/6/6 | 6/6 | 35 | 32 | 280 | 0.45 | −7 / +16 |
| II | 4 | 20/14/12 | 18/18 | 36 | 32 | 300 | 0.49 | −12 / +20 |
| III | 6 | 28/22/18 | 30/25 | 35 | 40 | 310 | 0.46 | −10 / +20 |
| IV | 11 | 50/30/30 | 30/30 | 35 | 34 | 325 | 0.46 | −10 / +20 |
| V | 11 | 51/30/30 | 50/35 | 35 | 39 | 330 | 0.42 | −10 / +20 |
| VI | 13 | 60/40/38 | 76/51 | 34 | 36 | 350 | 0.41 | −10 / +20 |
| VII | 11 | 75/45/40 | 80/64 | 36 | 44 | 360 | 0.41 | −8 / +22 |
| VIII | 10 | 83/56/42 | 115/76 | 39 | 38 | 380 | 0.38 | −8 / +20 |
| IX | 12 | 101/64/39 | 111/73 | 39 | 38 | 390 | 0.36 | −8 / +19 |
| X | 12 | 105/64/35 | 182/105 | 51 | 40 | 405 | 0.35 | −8 / +18 |

**Heavy tanks (A): top configuration, tech tree, EU API, Aug 2021.** Cells are median (P10–P90).

| Tier | n | HP | Top speed km/h | hp/t | Alpha (std shell) | Pen mm (std) | DPM | Reload s | Aim s |
|---|---|---|---|---|---|---|---|---|---|
| III | 1 | 445 (445–445) | 25 | 12.4 | 70 (70–70) | 81 (81–81) | 2000 (2000–2000) | 2.1 | 2.1 |
| IV | 3 | 670 (662–670) | 30 | 10.0 | 70 (58–102) | 67 (66–70) | 1750 (1607–1950) | 2.4 | 2.2 |
| V | 5 | 920 (848–920) | 30 | 12.0 | 135 (119–208) | 128 (122–141) | 1917 (1657–1984) | 4.8 | 2.3 |
| VI | 10 | 980 (956–1110) | 35 | 12.9 | 240 (135–309) | 164 (150–179) | 1810 (1413–1966) | 8.6 | 2.9 |
| VII | 12 | 1375 (1232–1495) | 35 | 12.5 | 300 (240–384) | 195 (175–206) | 1714 (1606–1966) | 10.0 | 2.5 |
| VIII | 17 | 1550 (1430–1700) | 38 | 13.9 | 320 (292–402) | 220 (210–229) | 1962 (1735–2131) | 10.0 | 2.7 |
| IX | 19 | 1900 (1790–2010) | 40 | 14.1 | 440 (390–536) | 252 (246–258) | 2102 (1861–2262) | 12.3 | 2.8 |
| X | 20 | 2350 (2090–2720) | 40 | 15.0 | 490 (400–605) | 258 (249–264) | 2331 (2105–2777) | 11.6 | 2.5 |

**Heavy tanks (B): armor and handling, stock configuration, API, May 2017.** Cells are medians. Armor is nominal mm, front/side/rear.

| Tier | n | Hull F/S/R | Turret F/S | Hull trav °/s | Turret trav °/s | View range m | Dispersion m@100 | Depression / elevation ° |
|---|---|---|---|---|---|---|---|---|
| III | 1 | 20/15/15 | 20/20 | 30 | 30 | 330 | 0.48 | −12 / +20 |
| IV | 3 | 50/50/50 | 40/40 | 28 | 32 | 330 | 0.53 | −10 / +20 |
| V | 7 | 75/60/60 | 82/75 | 20 | 28 | 320 | 0.46 | −10 / +20 |
| VI | 8 | 101/65/60 | 95/80 | 18 | 24 | 330 | 0.45 | −8 / +20 |
| VII | 9 | 120/80/60 | 100/90 | 20 | 26 | 350 | 0.40 | −8 / +20 |
| VIII | 11 | 130/80/60 | 152/89 | 25 | 27 | 380 | 0.38 | −8 / +15 |
| IX | 11 | 140/120/60 | 215/150 | 26 | 24 | 390 | 0.38 | −8 / +16 |
| X | 12 | 185/120/88 | 245/156 | 29 | 25 | 400 | 0.36 | −8 / +16 |

**Tank destroyers (A): top configuration, tech tree, EU API, Aug 2021.** Cells are median (P10–P90).

| Tier | n | HP | Top speed km/h | hp/t | Alpha (std shell) | Pen mm (std) | DPM | Reload s | Aim s |
|---|---|---|---|---|---|---|---|---|---|
| II | 7 | 240 (220–250) | 40 | 15.9 | 55 (43–72) | 64 (59–77) | 1435 (1065–1449) | 2.5 | 1.9 |
| III | 5 | 285 (265–291) | 50 | 18.0 | 85 (75–110) | 110 (101–111) | 1375 (1225–1582) | 4.0 | 2.1 |
| IV | 12 | 415 (400–429) | 43 | 16.5 | 110 (75–156) | 110 (107–128) | 1768 (1604–1996) | 3.8 | 1.7 |
| V | 10 | 465 (457–527) | 46 | 17.1 | 150 (111–246) | 144 (119–173) | 1918 (1662–2166) | 4.7 | 2.0 |
| VI | 11 | 670 (640–730) | 42 | 16.8 | 240 (150–250) | 175 (160–212) | 1875 (1601–2132) | 8.0 | 1.9 |
| VII | 11 | 850 (800–900) | 52 | 16.2 | 280 (240–390) | 210 (175–231) | 2132 (1870–2465) | 7.7 | 2.3 |
| VIII | 12 | 1125 (1000–1495) | 39 | 13.3 | 420 (390–553) | 252 (246–271) | 2458 (2010–2628) | 11.7 | 2.3 |
| IX | 11 | 1650 (1500–2000) | 38 | 14.4 | 560 (400–750) | 276 (259–290) | 2502 (2156–2946) | 14.4 | 2.5 |
| X | 12 | 2000 (1805–2100) | 39 | 15.2 | 750 (408–1020) | 294 (258–308) | 2572 (2295–3308) | 17.0 | 2.5 |

**Tank destroyers (B): armor and handling, stock configuration, API, May 2017.** Cells are medians. Armor is nominal mm, front/side/rear.

| Tier | n | Hull F/S/R | Turret F/S | Hull trav °/s | Turret trav °/s | View range m | Dispersion m@100 | Depression / elevation ° |
|---|---|---|---|---|---|---|---|---|
| II | 6 | 14/13/10 | –/– | 32 | – | 290 | 0.41 | −7 / +18 |
| III | 6 | 28/15/14 | –/– | 34 | – | 305 | 0.41 | −5 / +18 |
| IV | 9 | 50/20/15 | 38/25 | 32 | 18 | 310 | 0.43 | −9 / +20 |
| V | 9 | 38/20/20 | 38/22 | 30 | 16 | 340 | 0.39 | −8 / +22 |
| VI | 10 | 68/32/24 | 57/25 | 30 | 16 | 350 | 0.36 | −10 / +20 |
| VII | 10 | 84/51/39 | 89/32 | 30 | 16 | 350 | 0.36 | −10 / +16 |
| VIII | 11 | 120/51/40 | 116/76 | 26 | 18 | 370 | 0.35 | −6 / +15 |
| IX | 10 | 111/78/48 | 206/111 | 25 | 17 | 380 | 0.36 | −6 / +17 |
| X | 11 | 187/76/40 | 112/83 | 26 | 22 | 390 | 0.35 | −5 / +15 |

**SPGs (artillery) (A): top configuration, tech tree, EU API, Aug 2021.** Cells are median (P10–P90).

| Tier | n | HP | Top speed km/h | hp/t | Alpha (std shell) | Pen mm (std) | DPM | Reload s | Aim s |
|---|---|---|---|---|---|---|---|---|---|
| II | 5 | 160 (148–172) | 34 | 13.7 | 175 (165–318) | 21 (19–25) | 1167 (986–1318) | 9.0 | 5.0 |
| III | 7 | 230 (195–250) | 40 | 15.8 | 350 (178–410) | 27 (20–30) | 1230 (1089–1554) | 20.0 | 5.5 |
| IV | 7 | 275 (227–296) | 45 | 12.6 | 410 (322–424) | 27 (25–35) | 1640 (1224–1808) | 15.5 | 5.5 |
| V | 5 | 300 (281–402) | 42 | 15.4 | 480 (447–530) | 38 (29–38) | 1224 (1107–2019) | 23.5 | 6.0 |
| VI | 5 | 315 (300–327) | 56 | 18.9 | 550 (470–618) | 39 (32–39) | 1365 (1169–1843) | 22.0 | 5.7 |
| VII | 6 | 350 (345–355) | 34 | 16.4 | 615 (575–900) | 40 (37–52) | 1202 (1026–1317) | 29.4 | 5.3 |
| VIII | 5 | 410 (394–436) | 35 | 12.5 | 900 (662–900) | 52 (41–53) | 1224 (1170–1336) | 44.1 | 5.3 |
| IX | 5 | 450 (444–484) | 45 | 15.6 | 900 (748–900) | 52 (47–53) | 1360 (1287–1382) | 39.0 | 5.2 |
| X | 5 | 510 (494–542) | 40 | 14.7 | 900 (728–1060) | 53 (46–60) | 1386 (1317–1622) | 39.0 | 4.8 |

**SPGs (artillery) (B): armor and handling, stock configuration, API, May 2017.** Cells are medians. Armor is nominal mm, front/side/rear.

| Tier | n | Hull F/S/R | Turret F/S | Hull trav °/s | Turret trav °/s | View range m | Dispersion m@100 | Depression / elevation ° |
|---|---|---|---|---|---|---|---|---|
| II | 5 | 16/14/15 | –/– | 18 | – | 250 | 0.80 | −4 / +45 |
| III | 7 | 30/15/15 | –/– | 20 | – | 260 | 0.80 | −5 / +45 |
| IV | 7 | 20/15/15 | 20/15 | 23 | – | 255 | 0.77 | −5 / +43 |
| V | 5 | 25/15/13 | –/– | 22 | – | 260 | 0.82 | −4 / +45 |
| VI | 5 | 30/20/15 | –/– | 20 | – | 265 | 0.74 | −4 / +45 |
| VII | 6 | 45/29/20 | –/– | 21 | – | 272 | 0.69 | −4 / +45 |
| VIII | 5 | 51/30/20 | –/– | 18 | – | 270 | 0.66 | −5 / +55 |
| IX | 5 | 51/51/51 | –/– | 20 | – | 275 | 0.63 | −4 / +48 |
| X | 5 | 75/50/30 | –/– | 20 | – | 300 | 0.76 | −3 / +45 |

#### 3.3 Observations that matter for calibration [API]

**Per-tier growth (medium tanks, top configuration, Tiers V→X)**

| Stat | Growth |
|---|---|
| HP | ×1.27 per tier on average (600 → 1,950) |
| Standard pen | +28 mm per tier (124 → 263), flattening at IX–X |
| Alpha | Steps rather than a curve: 115 → 135 → 240 → 250 → 390 → 390. The big calibre jumps fall at VI→VII and VIII→IX. |
| DPM | +11% per tier (1,607 → 2,752) |
| View range (stock) | +15 m per tier (330 → 405) |
| Dispersion | 0.42 → 0.35 |

**Hull traverse is almost tier-independent within a class:**

| Class | Hull traverse |
|---|---|
| Medium | 34–51 °/s |
| Heavy | 18–29 °/s |
| Tank destroyer | 25–34 °/s |
| Light | 36–54 °/s |
| SPG | 18–23 °/s |

**Top speed is set by the hull and almost never changes with modules** (1 exception in 708 vehicles, the IS-2; corrected by fact-check). Typical medians by class:

| Class | Top speed |
|---|---|
| Light | 60–68 km/h from Tier V |
| Medium | 48–55 km/h |
| Heavy | 30–40 km/h |
| Tank destroyer | 38–52 km/h |
| SPG | 34–56 km/h |

**Reverse speed:**

| Class | Reverse speed |
|---|---|
| Light | about 20–25 km/h |
| Medium | 20 km/h |
| Heavy | 10–15 km/h |
| Tank destroyer | 12–15 km/h |
| Exceptions | Swedish casemate TDs reverse at 45 km/h; wheeled vehicles at 40–65 km/h |

**Gun arcs:**
- **Depression** is −5° to −10° for most classes (class medians −6° to −10°). SPGs are −3° to −5°.
- **Elevation** is +15° to +22°. SPGs reach +45° to +55°.
- National deviations are large; see §9.

**Tier X tech-tree TDs have bimodal alpha.** P10–P90 is 408–1,020. Very large guns at 750–1,020 sit next to DPM TDs at about 400. **HULLDOWN should cap TD alpha (R3).**

**SPG alpha** in the Aug 2021 snapshot is 900 median at VIII–X (900 is the most common value), with 39–44 s reloads.

#### 3.4 Camouflage and view range: reference to report 02

- Camo values are not published in the API. Report 02 gives the qualitative ordering, turretless TDs > LTs > MTs > SPGs and HTs, and adopts these HULLDOWN class defaults as stationary / moving camo factor:

  | Class | Stationary | Moving |
  |---|---|---|
  | Light | 0.18 | 0.18 |
  | Medium | 0.12 | 0.07 |
  | Heavy | 0.05 | 0.025 |
  | TD, turretless | 0.28 | 0.16 |
  | TD, turreted | 0.18 | 0.11 |
  | SPG | 0.10 | 0.05 |

- **This report agrees with those values.**
- **The data shows one thing 02 does not:** WoT's base view range is about the same for LT, MT, HT and TD at a given tier, at a ratio of 0.97–1.00 [API]. Report 02's spread (LT 400–460, HT 340–390) is an intentional readability deviation. Keep it only if light tanks need a scouting crutch on our smaller maps (see R3).

#### 3.5 Confidence and sources

- **Confidence:** High for the snapshot values; Medium for transfer to 2025–26.
  - The 1.26 and 2.0 rebalances changed many vehicles [Sib]. They target individual vehicles, so class-level medians should move only a few percent. That is an inference, not verified.
- **Sources:**
  - [wot_tank_data CSV + extractor (queries api.worldoftanks.eu vehicleprofile)](https://github.com/GuilleHoardings/wot_tank_data)
  - [wotdatabase API dumps](https://github.com/aki33524/wotdatabase)
  - [Sib 05 → Update 2.0: The Biggest Vehicle Rebalance](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)
  - [Sib 02 → Widespread Vehicle Rebalancing in 1.26](https://worldoftanks.eu/en/news/general-news/vehicle-rebalances-1-26/)

---

### 4. Tier XI (WoT 2.0, 2025–2026)

#### 4.1 Modern behavior

**Live since Update 2.0 on 3 September 2025** [Sib 05; corroborated by Wikipedia-text mirror [Comm]: "with all but Italy hosting at least one Tier XI tank, as of the World of Tanks Update 2.0"]. **Confirmed by fact-check:** the Wikipedia sentence was re-read in the mirror. The date matches IGN's listing ("launching on September 3 for PC") and the 2.0.0.0 client-mirror date of 2025-09-03 (sibling 04 and 02 fact-checks).

**Launch roster** [Sib 05]:
- **16 vehicles:** 7 heavy, 5 medium, 3 TD and 1 light. There was no Tier XI SPG at launch; no SPG was mentioned. **Confirmed:** WG's official "Update 2.0: Overview" narration says "Seven heavy tanks, five medium tanks, three tank destroyers, and one light tank" (sibling 05 fact-check).
- **15 are researchable.** The 16th, **"Black Rock"**, is the reward for Personal Missions 3.0 (Sector 3).
- I could **not** retrieve the full vehicle names. None are listed here, to avoid inventing them.

**How to get one** [Sib 05; **unverified**, Medium (corrected by fact-check)]:
- Earn **325,000 XP on a Tier X** of the line; Free XP can also be used. Then pay **7,400,000 credits**. Every cited page was unreachable during both fact-checks. The official narration only says "research it for XP and purchase it".
- Researching and buying all 15 researchable vehicles costs 4,875,000 XP and 111,000,000 credits.

**Progression after unlock** [Sib 05]:
- Tier XI does **not** use Field Modification. **Confirmed:** the official narration calls it an "upgraded system exclusive to Tier 11, replacing field modifications", and lists the Elite rewards as "a stat tracker, volumetric 2D styles and gun sleeves". The node counts and XP below are **unverified** (Medium). It uses a **linear upgrade-node track of up to 25 nodes**:
  - small nodes: **10,000 XP**, a stat increase;
  - large nodes: **20,000 XP**, a bigger stat increase or a mechanic upgrade;
  - final node: **25,000 XP**, a major upgrade to the special mechanic.
- Upgrades are "purely positive", with no trade-offs.
- When every node is done the vehicle is **Elite**. Further play raises its **Elite level**, which unlocks cosmetics: stat trackers, 2D styles, gun sleeves.

**Signature mechanics:**
- At 2.0, each Tier XI has one, described as "offence and mobility gimmicks": **secondary guns, charge-up accuracy, rocket boosters, direct drive** [Sib 02].
- **2.1.1 (January 2026)** added more Tier XIs [Sib 05].
- **2.4 "Overdrive" (September 2026)** adds about 5–6 more, each with its own mechanic: **adaptive autoloaders, alternative fire modes, rocket assist, recon systems** [Sib 05].

**Matchmaking (2.0)** [Sib 05]:
- Mostly ±1 tier, with some ±2 "for variety".
- **Whether Tier XI can meet Tier IX was not verified.** Tier XI-scoped missions use "VIII–XI" vehicle scope, which says nothing about matchmaking spread.

**Tier XI stat values: not found.** No HP, alpha or pen figures were retrievable.

#### 4.2 History and why

**Why:**
- WoT 2.0 ("biggest update") paired Tier XI with a free fully researched Tier VI–X branch for every player, plus a vehicle rebalance [Sib 05].
- My inference: Tier XI gives veterans who own everything a new long-term sink (325k XP and 7.4M credits per vehicle, plus node XP) and a showcase for new mechanics. Those mechanics are kept off Tiers I–X, which protects the readability of the core game.

**Before 2.0:**
- **Lesta's Mir Tankov** took a different path (its own lines and version numbering). It was not analysed.
- **Earlier proposals:** Tier XI had been debated by the community for years. No pre-2025 official announcement was verified.

#### 4.3 Confidence and sources

- **Confidence (revised by fact-check):** High that Tier XI exists, that it shipped on 3 Sept 2025, for the 16-vehicle 7/5/3/1 split, and that it replaces Field Modification. **Medium** for the unlock cost (325k XP / 7.4M credits) and the node costs (25 nodes; 10k/20k/25k XP); these were High and are now unverified (corrected by fact-check). Medium for the 2.1.1 and 2.4 additions. **Not found:** vehicle names and stats, and the exact matchmaking spread.
- **Sources:**
  - [Sib 05/02 → Update 2.0: Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/)
  - [Sib 05 → TAP: XP needed for Tier XI upgrades](https://thearmoredpatrol.com/2025/09/01/wot-how-much-experience-is-needed-for-tier-xi-upgrades/)
  - [Sib 05 → mmos.com 2.0 overview](https://mmos.com/news/world-of-tanks-update-2-0-brings-first-ever-tier-xi-tanks-and-a-full-systems-overhaul)
  - [Sib 05 → MassivelyOP on 2.4](https://massivelyop.com/2026/08/16/world-of-tanks-biggest-update-of-2026-is-coming-with-wait-for-it-more-tanks/)
  - [Wikipedia text mirror (GitHub)](https://github.com/Nice9Tian/stable-query-latent/blob/main/VICReg_review/wiki_descriptions/1407200_World%20of%20Tanks.txt)

---

### 5. Module and upgrade trees

#### 5.1 Modern behavior

**Module types.**

| Module | What it changes |
|---|---|
| **Gun** | Alpha, pen, reload, accuracy, shells, arcs |
| **Turret** | Turret armor, traverse, view range, available guns, a small HP bonus |
| **Engine** | Horsepower and fire chance |
| **Suspension / tracks** | Load limit, hull traverse, terrain resistance |
| **Radio** | Signal range |

- In the May 2017 API, every vehicle has a **stock** module per type (`is_default`). Researchable modules have an XP and credit price, and lists of `next_modules` and `next_tanks` [API].
- Median module counts per vehicle (Tiers II–X, tech tree): **guns 3, turrets 1, engines 2, suspensions 2, radios 2** [API].

**Research dependencies (May 2017 graph, 508 vehicles)** [API]:

| Edge (module A unlocks module B) | Count | Meaning |
|---|---|---|
| Gun → gun | 470 | Guns are a chain; the top gun comes last |
| Radio → radio | 457 | Chain |
| Engine → engine | 411 | Chain |
| Suspension → suspension | 314 | Chain |
| **Turret → gun** | **138** | **The heavier or top gun needs the upgraded turret first** |
| Turret → turret | 95 | Chain |
| Gun → turret | 69 | Some turrets unlock after an intermediate gun |
| Suspension → turret or gun | 0 | **No explicit edge.** The suspension dependency is enforced by **weight** (below) |

The module→module edge counts above reproduce exactly for Tiers II–X; gun→gun is 479 if Tier I is included (fact-check).

**Next-vehicle unlocks** come from: gun 230, turret 54, engine 34, suspension 21, radio 18, a total of 357 for Tiers II–X [API] (corrected by fact-check; the original 222 / 51 / 34 / 21 / 16 = 344 could not be reproduced under any tier filter. Including Tier I gives gun 263 of 390). Either way, guns account for about two-thirds. Vehicle research is usually gated on getting the line's key gun.

**Weight and load limit:**
- Each suspension has a `load_limit` (kg), and the vehicle's weight is the sum of hull and modules.
- **Stock vehicles sit almost at their stock suspension's limit.** Median free capacity is **1.4–3.2%** at Tiers II–IX (II 3.2, III 1.9, IV 2.0, V 1.5, VI 1.8, VII 2.2, VIII 1.7, IX 1.4), and the minimum is 0% [API; recomputed by fact-check, where IX is 1.4, not ≥1.5].
- The heavier upgraded turret or gun therefore usually cannot be **mounted** until the upgraded suspension is installed, even though it can be **researched**.
- This gives the classic WoT order: suspension → turret → gun [Rec, High; consistent with the API margins].

**Stock vs top (median top ÷ stock, tech tree, Aug 2021)** [API]:

| Tier | HP | Power-to-weight | Alpha | Std pen | DPM | Top speed | Median configs per vehicle (MT/HT) |
|---|---|---|---|---|---|---|---|
| II–IV | ×1.00–1.06 | ×1.11–1.20 | ×0.70–1.60 | ×1.12–2.70 | ×0.81–1.33 | ×1.00 | 12–60 |
| V–VII | ×1.00–1.10 | ×1.05–1.29 | ×0.77–1.39 | ×1.13–1.97 | ×0.78–1.18 | ×1.00 | 38–63 |
| VIII–IX | ×1.00–1.07 | ×1.08–1.25 | ×1.00–1.58 | ×1.03–1.40 | ×1.00–1.11 | ×1.00 | 36–54 |
| X | ×1.00 | ×1.00 | — | — | — | ×1.00 | **1** (sold fully upgraded) |

- **Penetration is the biggest stock handicap.** Power-to-weight comes second.
- DPM often stays the same or even drops, because top guns trade reload for alpha and pen.

**Elite status.** A vehicle becomes Elite once **all its modules and all follow-on vehicles** are researched. XP earned on it can then be converted to Free XP, and Tier VI–X vehicles open Field Modification [Sib 05].

**Module XP cost** (median per researchable module, May 2017) [API]:

| Tier | Gun | Turret | Engine | Suspension | Radio |
|---|---|---|---|---|---|
| IV | 2,075 | 1,200 | 765 | 1,100 | 1,480 |
| V | 3,775 | 2,465 | 1,500 | 2,150 | 3,800 |
| VI | 5,800 | 5,175 | 5,425 | 5,075 | 4,020 |
| VII | 15,000 | 9,850 | 11,100 | 8,600 | 5,050 |
| VIII | 18,900 | 15,500 | 18,000 | 15,157 | 8,700 |
| IX | 59,000 | 24,275 | 27,550 | 23,500 | 9,000 |

Report 05 gives the totals per vehicle.

#### 5.2 History

| When | What | Confidence |
|---|---|---|
| 2010–2023 | The classic tree: 4–7 researchable modules per vehicle at Tiers II–IX. Stock grinds were notorious, because module XP ≈ next-vehicle XP [Sib 05]. | High |
| **1.26 (2024)** | Rebalanced lines from Tier VI up have **one radio module, the top one**, because older radios "often did not provide a noticeable improvement" [Sib 02]. | Medium-High |
| **2.0 (Sept 2025)** | "Rebalance 2.0" **streamlined radio and suspension modules** (low-impact ones removed) and made stock vehicles stronger. Early tiers progress faster [Sib 02, 05]. | Medium-High |

- **Why:** to cut a grind that new players hated.
- **Not found:** exact post-2.0 module counts and costs.

**Sources:**
- [API] (above)
- [Sib 05 → 2.0 Hub](https://worldoftanks.eu/en/news/updates/2-0-hub/)
- [Sib 02 → Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
- [Sib 02 → 1.26 rebalances](https://worldoftanks.eu/en/news/general-news/vehicle-rebalances-1-26/)

---

### 6. Special vehicle mechanics

Report 01 §9 has the reload formulas for magazine, autoreloader and dual-gun. Here: rules, numbers and history, plus whether each mechanic appears in Random Battles.

| Mechanic | Where (Random?) | Rules | Known numbers | Introduced / changed | Confidence |
|---|---|---|---|---|---|
| **Autoloader (magazine)** | Random. Mostly French, some Chinese, Czech, US, Soviet and German vehicles [Rec] | `n` shells per magazine, intra-clip interval `t_i`, full magazine reload `T_m`. Reloading a partly empty magazine costs the full `T_m`. Rammer not allowed [Sib 01]. Burst = `n·α` | `DPM = 60·n·α/(T_m+(n−1)·t_i)` [Sib 01]. Tier X LT/MT examples use 3–6 shells [Rec] | Early French tanks (≈2011–12) [Rec, Low on version] | High (rules) |
| **Autoreloader** | Random. Italian MT/HT/TD; several others (e.g. the "Type 71" and "M-V-Y" rewards appear in the 2024–25 roster) [API roster, Rec] | Each magazine slot refills **one shell at a time** on its own timer `t_1…t_n`. Firing does not reset a shell already loading. You can fire early with a partial magazine | Sustained `DPM = 60·n·α/Σt_k` [Sib 01] | Italian branch, ≈2018 [Rec, Low on version] | Medium |
| **Dual-gun** | Random. Soviet dual-barrel heavies (ST-II line); ST-II at Tier X has 2,500 HP and 440 alpha per barrel [API 2021] | **Single fire:** each barrel fires separately, with a short delay between barrels. **Volley:** hold fire, charge (~1 s), both barrels fire together for 2× alpha with extra dispersion. Long full reload after both barrels have fired | Report 01 defaults: inter-barrel 1.5 s, charge 1.0 s, volley dispersion ×1.5 (OUR) | Late 2020, 1.10.1 or 1.11 [Sib 01] | Low-Medium |
| **Siege mode** (Swedish casemate TDs) | Random | Hydropneumatic suspension. In siege the gun is fixed to the hull (aim by turning the hull) and the vehicle is nearly immobile. Out of siege it is a fast vehicle with a high reverse speed. Manual toggle or auto-engage when stationary [Rec] | **Strv 103B, travel → siege** [API]: aim 3.0 → **1.0 s**; dispersion 0.30 → **0.25**; reverse 45 → **10 km/h**; transition on **2.0 s**, off **1.25 s**. Same pattern on Strv S1 and Strv 103-0. **UDES 03 differs:** off-transition 2.0 s, siege reverse 5 km/h, travel speeds 70/50 km/h (corrected by fact-check). The siege `suspension_traverse_speed` is `1` (travel 35 °/s), with no unit given; the hull still turns to aim, so do not read it as "locked". The API's arc fields for these vehicles (travel −1/+1, siege 2/9) do not look like the commonly quoted in-game arcs; use with caution | Swedish TDs, early 2017 (9.17.1) [Rec, Low-Medium]. Existence by May 2017 is confirmed: the May 2017 API dump has siege profiles for all four, and XVM 6.7.0 (WoT 9.19) has a siege/marching-mode hint option | High (API numbers) |
| **Hydropneumatic suspension** (Swedish mediums such as UDES 15/16 and Strv K) | Random | Hull pitch is adjusted to add gun depression or elevation, with a transition time [Rec] | Not retrieved | ≈2019 [Rec, Low] | Low |
| **Wheeled vehicles** | Random; **≤1 per team** [Sib 05; **unverified** for 2.0, Medium-Low] | Wheels are separate modules. Losing wheels degrades mobility but rarely immobilises (report 01: −25% top speed per lost wheel pair, OUR). Two drive modes: a manoeuvring / cruise mode and a **speed mode** with higher top speed and less steering [Rec] | API lists **cruise-mode** speeds: EBR 105 at 70 km/h forward and **50 km/h reverse**; EBR 90 at 65/65 [API]. Speed mode is higher (≈90 km/h, [Rec, Low]). Firepower trades off: EBR 105 has 190 mm pen against a 236 mm Tier X LT median [API] | French wheeled LTs, **Update 1.4 (2019)**; later nerfs to moving accuracy and spotting [Rec, Medium] | Medium |
| **Turbo / engine boost** | Random only as **equipment**: Turbocharger +7.5% / +10% engine power, +4 / +5 km/h top speed [Sib 05]. **Active** boosts (`nitro` "Turbocharger" ability) are mode-only [Comm] | — | — | Equipment 2.0 (1.10, 2020) | Medium |
| **Rocket boosters** | **Tier XI** signature mechanic in 2.0; "rocket assist" in 2.4 [Sib]. Tier I–X usage not verified | Short thrust burst, limited charges [Sib, wording] | Not retrieved | 2.0 / 2.4 | Medium (exists), Low (details) |
| **Charge-up accuracy / charged shot** | **Tier XI** (2.0) [Sib 02] | Holding fire improves the shot | Not retrieved | 2.0 | Medium (exists) |
| **Secondary guns, direct drive** | **Tier XI** (2.0) [Sib 02] | — | Not retrieved | 2.0 | Medium (exists) |
| **Adaptive autoloaders, alternative fire modes, recon systems** | **Tier XI** additions in 2.4 [Sib 05] | — | — | 2.4 | Medium (exists) |
| **Mode-only abilities** | **Not in Random.** Steel Hunter (battle royale), Frontline combat reserves, Strongholds, Halloween and other events [Comm, Sib] | Names visible in community game-term lists [Comm]: Airstrike, Artillery Strike, Smoke Screen, Minefield, Respawn, Recovery, Corrosive Mist, Inspire, Recon Flight, Engineering, Illumination Flare, Divisional Radar, Ring of Fire, Electric Discharge, Acid Shell, Fireball, Battlefield Robot, Adaptive Armor, Sentinel, Target Tracking, Berserker | Frontline smoke: 5 grenades over a 200 × 50 m area for 50 s; enemies inside get −30% view range and −15% crew [Sib 02] | Various | Medium (existence) |
| **Flamethrowers** | Event modes only [Sib 01] | — | Not retrieved | — | Low |

**Sources:**
- [API] Strv profiles and EBR/ST-II rows
- [Sib 01 §9](01-ballistics-armor-damage.md)
- [Sib 05 Equipment 2.0](05-progression-economy-crew-equipment.md)
- [unicum.gg game-term list](https://github.com/unicum-gg/unicum.gg/blob/main/apps/web/src/locales/en/game/equipment.json)
- [Sib 02 → Frontline reserves guide](https://worldoftanks.eu/en/news/general-news/frontlines-reserves-guide/)

---

### 7. Premium vehicle philosophy

#### 7.1 Modern behavior

**Economic advantages** [Sib 05, Rec]:
- a **higher credit coefficient**. Tier VIII premiums are the intended "credit farmers", while Tier IX–X tech-tree vehicles are a deliberate credit sink;
- **+50% crew XP**;
- **no modules to research**, so the vehicle is "Elite" from day one and its XP can be converted;
- **crew-trainer flexibility**: classically, a crew of the same nation and class can man a premium without penalty [Rec, Medium; post-crew-rework behavior not re-verified];
- **preferential matchmaking** on some premiums (at most +1 tier) [Sib 05]. It is not only Tier VIII: WG-wiki dumps show it on Tier III, V and VII premiums too (sibling 04 fact-check) (corrected by fact-check).

**Combat balance, measured** [API, Aug 2021]. Tier VIII medians, premium ÷ tech tree:

| Class (tech-tree n / premium n) | HP | Top speed | Power-to-weight | Alpha | Pen | DPM | Reload |
|---|---|---|---|---|---|---|---|
| Medium (13 / 48) | 0.96 | 1.00 | 1.04 | 1.00 | 0.97 | **0.94** | 1.00 |
| Heavy (17 / 43) | 0.97 | 0.97 | 1.03 | 1.12 | 1.00 | **0.95** | 1.20 |
| Tank destroyer (12 / 19) | 1.02 | 1.28 | 1.22 | 0.95 | 0.97 | **0.96** | 0.88 |
| Light (7 / 10) | 1.02 | 1.08 | 0.88 | 0.87 | 1.01 | 1.07 | 0.79 |

- The typical premium is **slightly weaker in DPM and pen (−3 to −6%)** and sometimes more mobile. That fits WG's long-stated rule that premiums should not be better than tech-tree equivalents.
- Outliers exist. Community criticism has focused on individual over-performing premiums ("pay-to-win" debates) and on power creep [Rec].

**Roster share (2024–25)** [API]:
- 429 of 917 vehicles are premium or reward vehicles. The API flag lumps them together.
- **184 are at Tier VIII**, 55 at Tier IX and 36 at Tier X; the Tier IX and X entries are rewards or collector vehicles. 34–39 sit at each of Tiers V–VI.

**Policy evolution:**
- **Pre-2019 [Rec, Medium]:** a de facto "no-nerf" promise. Over-performing premiums were withdrawn from sale rather than nerfed.
- **2019–2024:** WG reserved the right to rebalance premiums and published "premium vehicle improvements" buff passes [Sib 05].
- **2.0 (2025):** premiums were included in the biggest rebalance. Tier VIII–IX premium gold prices were cut by about 10%, and Tier IX premiums gained credit income to cover their higher repair and ammo costs [Sib 05].

**Confidence:** High for the measured stat parity in the snapshot. Medium for the economic advantages. Low for the policy timeline wording.

**Sources:**
- [API] (above)
- [Sib 05 → Premium vehicle improvements](https://worldoftanks.com/en/news/general-news/premium-vehicle-improvements/)
- [Sib 05 → Survival Guide: Premium Tanks](https://worldoftanks.com/en/content/player-guide/written-guide/suvival-guide-premium-tank/)
- [Sib 05 → 2.0 rebalance](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)

---

### 8. Artillery (SPG): modern design

#### 8.1 Modern behavior

**Fire control.**
- SPGs fire HE (sometimes AP, HEAT or alternative HE) on high arcs.
- The player uses a top-down **strategic view** with an indicator of whether the arc can reach the target, plus an alternative **trajectory view** [Rec, High].
- Handling is poor. Tier X: dispersion 0.59–1.08 m@100, aim 4.5–6.1 s, reload 32–52 s; view range is about 0.74× other classes; HP is about 0.29× a medium [API].

**Damage and splash.**
- Tier X HE alpha is **750–1,300**, with **45–60 mm pen** [API May 2017]. The Aug 2021 snapshot has a median of 900.
- Splash radii are much larger than tank HE. The exact per-gun radii were not retrieved [Sib 01].
- Direct hits on thin armor deal near-full alpha. Splash damage is reduced by armor and spall liners (report 01 §3).

**Stun** (since 9.18) [API, values; Rec, rules]:
- Every SPG HE shell has a **stun duration range `[min, max]` in seconds**. Vehicles caught in the splash are stunned, and the duration falls from max at the centre toward min at the edge [Rec, Medium].
- Stunned crews perform worse, so reload, aiming, traverse and movement all slow down. **The exact penalty was not verified** (community figures say about a 25% crew-skill drop; Low).
- **Measured ranges (stock HE, May 2017):**

  | SPG tier / calibre | Stun `[min–max]` s | min/max |
  |---|---|---|
  | II–IV, 75–122 mm | 0 / 0 (no stun) | — |
  | III–V, 150 mm (Bison, Sturmpanzer II, Grille) | 4.29–6.6 | 0.65 |
  | V–VI, 150–155 mm (M41 HMC, M44, Hummel, AMX 13 F3) | 6.76–10.5 | 0.65 |
  | VII (S-51, Lorraine 155 50, M12, G.W. Panther, SU-14-1) | 7.15–23.0 | 0.55–0.65 |
  | VIII–IX (SU-14-2, M40/M43, FV207, G.W. Tiger (P), Bat.-Chât. 155 55) | 12.1–28.0 | 0.50–0.60 |
  | X (Obj. 261, Bat.-Chât. 155 58, G.W. E 100, Conqueror GC, T92 HMC) | 13.05–35.0 | **0.45–0.50** |

**Stun counterplay.**
- **Spall Liner** cuts HE splash damage by 50/60% and stun duration by 10/15% [Sib 05].
- The commander perk "Emergency" gives −10% stun (1.26) [Sib 05].
- First-aid kits treat stunned crews [Rec].
- Stun inflicted pays **stun assist** XP and credits [Sib 05].

**Matchmaking.** At most **3 SPGs per team** since 9.18 (Medium-High: a community Random-MM reimplementation citing WG's 9.18 announcement uses 0–3). "Still ≤3 in 2.0" is **unverified**: WG's 2.0 narration names only the LT 3 and TD 5 caps [Rec, Sib 05].

**Why 9.18 changed arty** [Rec, Medium]:
- The goal was to replace "one-shot from the sky" with **lower, more consistent damage plus a team-wide debuff (stun)**, and to cap SPG numbers.
- Arty remained the most criticised class anyway. Players complain that stun is still frustrating and gives no counterplay in the open.

**Further arty adjustments in 2019–2023** (e.g. Sandbox tests of alternative SPG shell types) **were not verified** (Open question 6).

#### 8.2 Counterplay available to the target

- Break line of sight to allied spotters. Arty needs a spotted target unless it blind-fires.
- Keep moving; flight time is several seconds.
- Use cover against the arc: reverse slopes, buildings.
- Equip a Spall Liner and carry first-aid kits.
- Have scouts or teammates hunt the SPG, which reveals itself via shot tracers [Rec].

#### 8.3 Should HULLDOWN have indirect fire?

Yes, but as a **capped, low-damage, stun-centred support class with hard counterplay**. Details are in R6. Reasons:
- The class adds strategic depth: it punishes static camping and breaks stalemates.
- The architecture and content schema already reserve `Artillery`, with roles `ArtySupport` and `ArtyAreaControl`.
- WoT's own history shows the risk: one-shots from players the victim cannot see. The 2017 rework moved away from that, and so must we.

**Sources:**
- [API] SPG ammo `stun.duration`, gun stats
- [Sib 05 → Equipment 2.0 Spall Liner](05-progression-economy-crew-equipment.md)
- [Sib 01 HE/splash](01-ballistics-armor-damage.md)
- [XVM 9.1.0 "high_explosive_stun" shell type](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md) (corroborates a distinct stun-HE shell type)

---

### 9. Nation and branch design patterns (inspiration only)

#### 9.1 Measured national tendencies [API]

- Tiers V–X, tech tree, LT/MT/HT/TD.
- Each value is the median of (vehicle stat ÷ class-and-tier median), so 1.00 means average.
- Depression is the raw median in degrees.
- Columns from HP to Aim use the Aug 2021 top-configuration data. Columns from Depression to View range use May 2017 stock data, which predates the Italian and Polish trees.

| Nation (n) | HP | Speed | hp/t | Alpha | Pen | DPM | Reload | Aim | Depression | Dispersion | Hull F armor | Turret F armor | View range |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| USSR (53) | 1.00 | 1.00 | 1.00 | 1.00 | 0.99 | 1.01 | 1.00 | 1.07 | **−5°** | **1.08** | 1.00 | 1.05 | 0.97 |
| China (22) | 1.00 | 0.99 | 0.98 | **1.12** | 1.00 | 1.01 | 1.13 | 1.06 | **−5°** | 1.02 | 0.88 | **1.18** | 0.97 |
| Germany (46) | **1.05** | 1.00 | 0.95 | 1.00 | 1.00 | 1.00 | 1.00 | 0.98 | −8° | **0.95** | **1.08** | 1.00 | 1.00 |
| USA (37) | 1.00 | 1.00 | 0.98 | 1.00 | 0.98 | 1.03 | 0.94 | **0.93** | **−10°** | 1.03 | 1.02 | 1.00 | 1.00 |
| UK (33) | 1.02 | **0.91** | 0.96 | **0.91** | 1.02 | 1.01 | **0.92** | 1.00 | **−10°** | **0.92** | 1.01 | 1.00 | 1.00 |
| France (31) | 0.94 | 1.03 | **1.08** | 1.00 | 1.01 | 0.94 | 1.02 | 1.05 | −8° | 1.00 | 0.96 | **0.73** | 1.00 |
| Japan (12) | **1.08** | **0.82** | **0.84** | 1.00 | 1.00 | 1.06 | 0.92 | 1.00 | −10° | 1.00 | **1.15** | 0.99 | 1.01 |
| Sweden (15) | 0.97 | **1.28** | **1.15** | 1.00 | 1.00 | 0.94 | 1.10 | 1.05 | **−12°** | 0.99 | **0.49** | 0.80 | 0.97 |
| Czech (10) | 0.98 | 1.10 | **1.15** | 0.98 | 1.00 | 0.97 | 0.97 | 0.96 | −9° | 0.97 | **0.71** | 0.78 | 1.00 |
| Poland (12) | 1.00 | 1.00 | 1.03 | **1.23** | 1.01 | 1.00 | **1.24** | 1.09 | – | – | – | – | – |
| Italy (10) | 0.98 | 1.06 | 1.03 | 0.96 | 1.02 | 0.86* | 1.07 | 1.04 | – | – | – | – | – |

\*Italian DPM uses the API's effective fire rate for autoreloaders. Treat it with caution.

Fact-check note on Sweden's −12°: it reproduces only when the four siege-mode TDs are excluded. Their travel-mode API arcs are −1/0, which looks like a placeholder. Including them, the Swedish median is −10° (n = 12). The other depression medians reproduce as stated: USSR and China −5°, USA, UK and Japan −10°, Germany and France −8°, Czech −9°.

#### 9.2 Qualitative patterns

These are long-standing community knowledge [Rec] and agree with the table:
- **Soviet and Chinese:** high alpha, strong turrets ("pike nose", dome turrets), poor gun depression (−5°), mediocre accuracy and aim. Built to fight on flat ground and to trade blows.
- **German:** accurate guns, large and boxy but well-armored (angled heavies), lots of HP, heavy and sluggish. Rewards careful long-range play.
- **American:** excellent depression (−10°) and strong turrets for **hull-down** play, quick aim, good DPM. Weak lower plates and cupolas.
- **British:** fast-firing, accurate, low-alpha guns; good depression; often slow or with weak armor. Specialty: HESH.
- **French:** autoloaders and speed; thin armor. Wheeled scouts.
- **Swedish:** siege-mode casemates and hydropneumatic mediums; huge depression; paper armor; very mobile.
- **Japanese:** huge heavies with big HE guns; slow.
- **Polish:** big alpha with long reloads.
- **Czech:** fast, thin, often autoloading.
- **Italian:** autoreloaders and good depression.

**Confidence:** High for the measured table. Medium for the narrative.

**Sources:** [API].

---

## Implementation recommendations for HULLDOWN (Roblox)

All values are **OUR DESIGN CHOICE** unless marked "= WoT".
- Units follow `ARCHITECTURE.md`: config in real-world units (mm, m, km/h, s, kg, hp), converted at the boundary with `Units.STUDS_PER_METER = 3`.
- Content goes in `Shared/Config/Content/{Classes,Roles,Tiers}.luau` and `Vehicles/<Faction>/<Id>.luau`.
- Matchmaking constants go in `Config/Matchmaking.luau`.
- Names follow the draft content schema (`VehicleClass`, `Role`, `SpecialMechanic`).

### R1. Classes (`Classes.luau`)

Keep WoT's five classes, with the identities measured in §1. Class multipliers relative to a **Medium baseline** (R3) at the same tier are given below.

**Derivation:**
- "Data" is the WoT median at Tiers VI–X [API].
- Where we deviate, the reason is given.
- These multipliers are **class-level**. Report 01 R10's "Role modifiers" table had approximated them (e.g. HT alpha ×1.15, TD ×1.25, LT ×0.75). The table below supersedes that table for class calibration, because it is measured.
- Roles (R2) then add trims on top: ±5–15% on core stats, and larger multipliers on armor (×0.6–×1.6) and camo (corrected by fact-check; this said "±10%", which R2's own table exceeds).

| Stat | Light | Medium | Heavy | TD | Artillery | Notes |
|---|---|---|---|---|---|---|
| HP | 0.80 (data 0.77) | 1.00 | 1.20 (1.17) | 0.85 (0.80) | 0.30 (0.29) | TD +5% versus data to soften glass-cannon frustration in 15v15 |
| Alpha (standard shell) | 0.85 (0.85) | 1.00 | 1.25 (1.26) | **1.50 (data 1.68)** | 2.0 (2.56), HE only | **TD capped**: WoT's 750–1,020-alpha tier X TDs one-shot lights. On Roblox with a fast TTK this reads as unfair |
| Standard pen | 0.90 (0.88) | 1.00 | 1.03 (1.04) | 1.18 (1.19) | 0.25 | = WoT |
| Reload | 0.95 (0.96) | 1.00 | 1.27 (1.28) | 1.45 (1.50) | 4.0 (4.6) | Implied DPM ≈ LT 0.89, HT 0.98, TD 1.03, Arty 0.50 |
| Aim time | 0.90 | 1.00 | 1.20 (1.23) | 1.05 (1.07) | 2.3 (2.36) | = WoT |
| Dispersion | 1.05 | 1.00 | 1.05 (1.03) | 0.92 (0.92) | 1.75 (1.75) | = WoT |
| Top speed | 1.20 (1.18) | 1.00 | 0.72 (0.73) | 0.80 (0.78) | 0.75 (0.73) | = WoT |
| Power-to-weight | 1.6 (1.77) | 1.00 | 0.77 | 0.80 | 0.80 | Our physics uses real masses. Set engine hp to hit the ratio, not "realistic" hp (WoT does the same) |
| Hull traverse | 1.18 | 1.00 | 0.60 (0.57) | 0.67 | 0.55 (0.51) | = WoT |
| Turret traverse | 1.15 | 1.00 | 0.65 (0.63) | 0.50, turreted TDs only | — | = WoT |
| Hull-front nominal armor | 0.50 | 1.00 | 1.60 | 1.1 (by role: Assault ≈1.75, Sniper ≈0.65 = 1.1 × the R2 trims ×1.6 / ×0.6) | 0.6 | See the R3 armor rule. (Corrected by fact-check: Sniper was 0.4, which contradicted R2's TDSniper armor ×0.6.) |
| View range | per report 02 R4 | | | | | WoT is flat (≈1.0) across classes; 02 adds an LT bonus on purpose |
| Camouflage | per report 02 R3 | | | | | = 02 |

- **Turretless TDs:** 80% of TDs should be turretless, matching WoT's 83%. Gun yaw arc defaults to **±11°** (= WoT median), with a −5° to −8° depression range.
- **Artillery** has its own handling rules (R6).

### R2. Roles (`Roles.luau`)

**Role list.**
- Adopt WoT's shape, 4 roles per direct-fire class:
  - **Light:** Scout, Versatile, Support, plus the `Wheeled` *mechanic flag*. Wheeled is a mechanic, not a role.
  - **Medium:** Assault, Versatile, Support, Sniper.
  - **Heavy:** Assault, Breakthrough, Versatile, Support.
  - **TD:** Assault, Sniper, Support, **Versatile**.
  - **Artillery:** Support (stun) and AreaControl (damage), as in the draft schema.
- **Note:** the draft schema has no `TDVersatile`. WoT has one (`ATSPG_universal`). **Add `TDVersatile`** for turreted or balanced TDs.

**Role stat trims.** Applied on top of the class multipliers; small enough that class identity dominates.

| Role | Trims |
|---|---|
| HeavyAssault | armor ×1.15, speed ×0.85, hull traverse ×0.9 |
| HeavyBreakthrough | speed ×1.15, power-to-weight ×1.15, armor ×0.95 |
| HeavySupport | armor ×0.85, pen ×1.05, depression +2°, aim ×0.9 |
| HeavyVersatile | — |
| MediumAssault | armor ×1.15, HP ×1.05, speed ×0.92 |
| MediumSniper | dispersion ×0.9, pen ×1.07, view range +10 m, reload ×1.05 |
| MediumSupport | reload ×0.92, camo +0.02, armor ×0.9 |
| MediumVersatile | — |
| TDAssault | armor ×1.6, speed ×0.85, camo −0.08 |
| TDSniper | camo +0.04, dispersion ×0.9, alpha ×1.05, armor ×0.6 |
| TDSupport | reload ×0.9, speed ×1.1 |
| TDVersatile | 360° turret, alpha ×0.9 |
| LightScout | camo +0.03, view range +10 m, alpha ×0.9 |
| LightSupport | pen ×1.05, alpha ×1.05, speed ×0.95 |
| LightVersatile | — |

**Role Score.** WoT-inspired; our own version of "role actions". Each role weights the battle-stat ledger that `BattleInstance` already keeps. The Role Score is shown on the results screen as "Role performance".

| Role group | Weighted actions (weights sum to 1) |
|---|---|
| Heavy Assault / Breakthrough | damage dealt 0.4, damage blocked 0.3, base capture or defence 0.1, first-contact damage (first 3 min) 0.2 |
| Heavy Support / Versatile | damage 0.6, blocked 0.2, assist 0.2 |
| Medium (any) | damage 0.6, assist (spot + track) 0.25, capture/defence 0.15 |
| TD (any) | damage 0.75, assist 0.15, kills 0.10 |
| Light Scout | spotting assist 0.6, first detections 0.15, damage 0.15, capture/defence 0.1 |
| Light Support / Versatile | damage 0.4, spotting assist 0.4, track assist 0.2 |
| Artillery | stun assist 0.5, damage 0.4, kills 0.1 |

- Normalise each component by the same-tier class expectation (e.g. a rolling 30-day median per class and tier, from `AnalyticsService`) so roles are comparable.
- **Use 1: defeat protection.** In a defeat, the **top 5 losing players by Role Score** get the defeat XP penalty halved (e.g. the win bonus is lost but they get +25% XP). It rewards good play in a loss. It is **inspired by** the role-action defeat-XP mitigation recalled in §2.1 item 6. That WoT system is unverified [Rec, Low], so this is OUR DESIGN CHOICE, not parity (corrected by fact-check).
- **Use 2: missions.** Role-specific dailies and the Role series, mirroring PM 3.0.

**UI.**
- Show a role badge (original glyph set) next to the class icon in the tech tree, garage carousel, loading screen and roster.
- Add a one-line playstyle hint and three bullet "do this" tips per role (localisation keys `role.<id>.hint`, `role.<id>.tips[1..3]`).

**Equipment slot specialisation.**
- From Tier VI up, one equipment slot is specialised by role, giving +15% item effect (= WoT, Equipment 2.0 [Sib 05]).
- Defaults:

  | Specialisation | Roles |
  |---|---|
  | Firepower | TD Sniper/Support, Medium Sniper/Support, Heavy Support |
  | Survivability | Heavy Assault/Breakthrough, Medium Assault, TD Assault |
  | Mobility | Light Versatile/Support, Medium Versatile, Heavy Versatile, TD Versatile |
  | Scouting | Light Scout, Artillery |

**Matchmaking interaction** (`Matchmaking.luau`). 15v15 defaults:
- Class caps per team: Light ≤3 (of which Wheeled ≤1), TD ≤4, Artillery ≤2 (≤1 when team size ≤10).
- Class counts mirrored between teams within ±1. Role groups (Assault-type vs Sniper-type) mirrored within ±1 as a *soft* constraint that relaxes after 30 s.
- These are slightly stricter than WoT's 2.0 caps of ≤3 LT and ≤5 TD (confirmed) and ≤3 SPG (unverified for 2.0) [Sib]. Smaller Roblox maps make camping TDs and arty more oppressive.
- **Cross-doc conflict (flagged by fact-check):** report 04 R3 sets `CLASS_LIMITS = { LT = 3, LT_WHEELED = 1, TD = 5, SPG = 2 }`, which has **TD = 5**. This section says TD ≤4. `Matchmaking.luau` must have one owner; report 04 owns matchmaking constants, so resolve it there.
- WoT 2.0 also mirrors **roles** in matchmaking (§2.1 item 5), so the soft role mirroring above is close to WoT parity, not an invention (corrected by fact-check).
- Since 2.4 WoT reportedly caps LTs at 2 (unverified). We keep 3 because Roblox matches often fill with bots, and bots playing LT generate useful spotting.

### R3. Tiers and stat ladder (`Tiers.luau`)

**Tier structure.**
- **Tiers I–X**, plus **Tier XI "Apex"**: about 1 per faction at launch, added later if content bandwidth is limited. Report 05's economy already includes Tier XI.
- Matchmaking spread:

  | Tiers | Spread |
  |---|---|
  | I–II | 0 |
  | III–IV | ±1 |
  | V–X | ±2 using WoT-style templates (3/5/7), **capped at Tier X**. Tier IX never meets XI; Tier X meets XI only in X–XI battles (corrected by fact-check: a plain ±2 would put IX with XI, contradicting the XI row) |
  | XI | **X–XI only** (±1) |

**Medium baseline per tier.** Gun columns adopt report 01 R10 so the two docs agree, with Tiers II, IV and VI interpolated. Other columns are smoothed WoT medians [API].

| Tier | HP | Alpha | Std pen | Reload s | DPM | Aim s | Dispersion m@100 | Top speed km/h | hp/t | Hull trav °/s | Turret trav °/s | Base view range m | Hull F/S/R mm | Turret F mm |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I | 280 | 40 | 45 | 1.9 | 1,263 | 1.9 | 0.48 | 40 | 12 | 38 | 40 | 300 | 20/15/15 | 25 |
| II | 360 | 50 | 55 | 2.3 | 1,304 | 1.95 | 0.47 | 42 | 13 | 38 | 40 | 310 | 25/20/15 | 30 |
| III | 440 | 60 | 65 | 2.6 | 1,385 | 2.0 | 0.45 | 45 | 14 | 37 | 40 | 320 | 30/25/20 | 35 |
| IV | 530 | 85 | 85 | 3.4 | 1,500 | 2.1 | 0.44 | 47 | 15 | 36 | 40 | 330 | 45/30/25 | 45 |
| V | 640 | 115 | 100 | 4.2 | 1,643 | 2.2 | 0.42 | 50 | 16 | 36 | 40 | 340 | 50/35/30 | 55 |
| VI | 820 | 160 | 130 | 5.6 | 1,714 | 2.25 | 0.40 | 52 | 17 | 37 | 40 | 355 | 60/40/35 | 75 |
| VII | 1,060 | 220 | 160 | 7.4 | 1,784 | 2.3 | 0.38 | 54 | 17 | 38 | 42 | 370 | 75/45/40 | 85 |
| VIII | 1,350 | 260 | 195 | 8.0 | 1,950 | 2.3 | 0.37 | 55 | 18 | 40 | 42 | 380 | 85/55/40 | 110 |
| IX | 1,650 | 320 | 225 | 8.6 | 2,233 | 2.2 | 0.35 | 55 | 19 | 42 | 42 | 390 | 100/60/40 | 130 |
| X | 1,950 | 400 | 255 | 9.5 | 2,526 | 2.2 | 0.34 | 55 | 20 | 45 | 42 | 400 | 105/65/40 | 160 |
| XI (Apex) | 2,200 | 440 | 275 | 9.8 | 2,694 | 2.1 | 0.33 | 56 | 21 | 46 | 44 | 410 | 115/70/45 | 180 |

- **Absolute view range.** Report 02's LT 400–460 and MT 370–410 apply at Tiers VIII–XI. Scale lower tiers by the base-view-range column ratio.
- **Pen versus WoT.** Our gun pens are up to 24 mm under WoT's MT medians. The gaps are V −24 (100 vs 124), VI −15, VII 0 (160 vs 160), VIII −17 (195 vs 212), IX −23 and X −8 (corrected by fact-check; this said "15–25 mm at V–IX", but VII matches). **Armor must therefore be authored against our pen, not copied from WoT.** Use the rule below.

**Armor-authoring rule.** It ties armor to our pen. Let `P_std(T)` be the Medium baseline standard pen at tier `T`. Target **effective** thickness, after slope, against a frontal shot at 0° yaw:

| Class / zone | Effective armor target | Intended result |
|---|---|---|
| Heavy turret face (excluding weak spots) | 1.15–1.35 × P_std(T) | Bounces same-tier standard shells; premium shells penetrate |
| Heavy upper front plate | 0.95–1.15 × P_std(T) | Coin-flip at same tier, safe against T−1 |
| Heavy lower plate, cupola, hatch | 0.55–0.70 × P_std(T) | The weak spots that reward aim |
| Medium turret face | 0.85–1.0 × P_std(T) | |
| Medium hull | 0.50–0.70 × P_std(T) | |
| TD Assault casemate | 1.1–1.4 × P_std(T) | |
| TD Sniper / Support casemate | ≤ 0.45 × P_std(T) | |
| Light (any) | ≤ 0.35 × P_std(T) | Overmatched by guns ≥ 2× its thickness |
| Sides | 0.35–0.45 × P_std(T) for heavies, 0.2–0.3 for others | |
| Rear | 0.2–0.3 × P_std(T) | |

**Balance lint** (`tools/` "balance report", ContentRegistry test):
- For every vehicle, compute its stats ÷ (class × role × tier baseline × **faction kit**, R9). Without the faction kit in the baseline, R9's ×0.90–1.15 kits would trip the [0.92, 1.08] warning on whole factions (corrected by fact-check).
- **Fail** the build if any core stat (HP, alpha, pen, DPM, speed, hull traverse, dispersion) falls outside **[0.85, 1.15]**.
- **Warn** outside [0.92, 1.08] unless `balanceException` names a reason.
- This replaces WoT's P10–P90 spread with a reviewed envelope.

### R4. Modules and research (`Guns/`, `Turrets/`, `Engines/`, `Tracks/`, `TechTree.luau`)

**Module types and counts.**
- Use **4 module types: Gun, Turret, Engine, Tracks. Drop Radio entirely** (WoT 1.26 and 2.0 direction; report 02 shows relay is irrelevant). The draft schema's `RadioDefinition` can stay for future modes, but vehicles should not research radios.
- Upgrades per tech-tree vehicle:

  | Tiers | Upgrades |
  |---|---|
  | I | 0 |
  | II–III | 1–2 |
  | IV–IX | 2–4 |
  | X | 0 (arrives Elite, = WoT) |
  | XI | node track (R5) |

  Typical Tier IV–IX set: Tracks → Turret → Gun (top), plus Engine.

**Stock handicap**, as top ÷ stock:

| Stat | Ratio |
|---|---|
| HP (turret) | ×1.05 |
| hp/t | ×1.15 |
| Std pen | ×1.20 |
| Aim time | ×0.95 |
| Dispersion | ×0.95 |
| Turret traverse | ×1.10 |
| Hull traverse | ×1.08 |
| Top speed | ×1.00 (= WoT) |

- Overall, stock ≈ 85% effectiveness. Pen ×1.20 is softer than WoT's per-vehicle median top ÷ stock pen at Tiers II–VII (≈ ×1.2–1.7, more for low-tier heavies). It is **about equal** at VIII–IX (≈ ×1.1–1.3), per §5.1 and a fact-check recount. It follows WoT 2.0's "stronger stock vehicles" (corrected by fact-check; the "×1.13–1.67" range did not match §5.1).
- **Carry-over rule:** if the previous vehicle in the line already researched a module (e.g. a shared gun), it arrives pre-researched. This is WoT behavior [Rec] and saves grind.

**Dependencies, as explicit edges in `moduleTree`:**
- `Tracks(top) → Turret(top) → Gun(top)`; `Engine` is independent.
- Next-vehicle unlocks hang off the **top gun** (WoT's dominant pattern: about two-thirds of unlocks, 230 of 357 at Tiers II–X; corrected by fact-check, was "222 of 344").

**Weight rule** (validated in ContentRegistry, = WoT mechanic):
- `stockWeight ≤ stockTracks.loadLimitKg` and `topWeight ≤ topTracks.loadLimitKg`.
- Additionally `stockHull + stockTracks + topTurret + topGun + stockEngine > stockTracks.loadLimitKg`, so the order is enforced physically as well as by edges.
- Author stock tracks with **1–3% spare capacity** (= WoT median).

**Elite.** All modules plus all next vehicles researched → Elite. This unlocks Free-XP conversion and Field-Mod-lite. Report 05 owns the economy numbers.

### R5. Tier XI "Apex" vehicles

- **Count:** 1 per faction at launch (5–6 vehicles). Every Apex vehicle gets **one signature mechanic** from the R7 exotic list (RocketBoost, ChargedShot, active Turbo, ActiveCooling, or an adaptive `MagazineSpec` variant; ActiveCooling was added for consistency with R7 by fact-check).
- **Unlock:** report 05 sets the economy. OUR default: 47,000 XP on the Tier X, plus credits. The node track is **10 nodes**: 6 small (+2% to one stat), 3 large (+4% or a mechanic tier), 1 final (signature upgrade). Total node gain ≤ +12% effectiveness.
- **Stats:** Tier XI baseline = Tier X × (HP 1.13, alpha 1.10, pen 1.08, DPM 1.07), per R3. Apex vehicles fight only Tiers X–XI.
- **Why:** this mirrors WoT 2.0's long-term veteran sink, but keeps flashy mechanics out of Tiers I–X, so the core game stays readable.

### R6. Artillery (indirect fire)

**Ship it, under these rules:**

| Parameter | Default | Basis |
|---|---|---|
| Per-team cap (15v15) | **2**; **1** if team size ≤10; **0** in small or competitive modes | WoT ≤3 |
| Tiers | IV–X; no Tier XI artillery | WoT had none at 2.0 launch |
| HE alpha | 2.0 × MT baseline alpha (Tier X: 800) | WoT Tier X 750–1,300, median 900 (corrected by fact-check; was "≈ 900–1,300") |
| Direct-hit cap | ≤ 45% of the same-tier MT HP (Tier X: ≤ 880) | Prevents one-shots |
| Splash radius | `R = 3 + 0.03·caliber_mm` m (155 mm → 7.65 m) | Readable on our maps |
| Splash damage | `D(d) = 0.5·α·(1 − d/R)`, minus armor/spall as in report 01 | |
| **Stun** | `stun(d) = lerp(stunMax, stunMin, d/R)`, with `stunMin = 0.5 × stunMax` | **= WoT ratio 0.45–0.65** |
| `stunMax` by tier | IV 0, V 6 s, VI 8, VII 10, VIII 12, IX 14, X 16 s | **≈ 45–60% of WoT's per-tier maxima at VII–X (23–35 s)**; higher at V–VI (6 / 8 s against 6.6–10.5 s) (corrected by fact-check; was "45–60% of 10.4–35 s") |
| Stun effects | reload ×1.25, aim time ×1.25, dispersion ×1.20, hull and turret traverse ×0.80, top speed ×0.85, view range ×0.90 | WoT's exact debuff unverified |
| Stun resistance | Spall Liner −30% duration; first-aid kit clears stun and gives 5 s immunity; stun does not stack (refresh to max) | |
| Reload / aim / dispersion | 4.0× / 2.3× / 1.75× MT baseline (Tier X: 38 s, 5.1 s, 0.60) | = WoT ratios |
| Shell flight | `g_shell` per report 01 R7; minimum flight time ≥ 2.5 s beyond 200 m | Gives targets time to react |
| Targeting | Requires a target spotted by an ally **or** the shooter (no blind fire on unspotted vehicles in Random) | |
| Camera | Top-down strategic view with arc reachability colouring (green: arc clear, red: blocked by terrain or buildings), plus a trajectory view | = WoT UX |

**Counterplay we add beyond WoT (because Roblox players skew younger):**
- **Incoming-fire warning:** if a shell's predicted impact is within `R + 5` m of you, play a whistle and flash a directional indicator **1.0 s before impact**.
- **Tracer reveal:** every artillery shot reveals the shooter's position on the enemy minimap for **5 s**, as a ring of radius 50 m.
- **Rewards:** stun assist pays like track assist, which makes arty a team-play class. Kills by artillery give 0.8× the normal kill XP.

**Why:**
- Indirect fire breaks camping and corner stalemates, and it is a distinct fantasy players expect from a WoT-like game.
- The caps, damage ceiling, warnings and reveal answer the core WoT complaint: being damaged by an unseen enemy with no counterplay.

### R7. Special mechanics (data-driven `SpecialMechanic` / gun specs)

| Mechanic (schema) | Tiers / where | Defaults | Notes |
|---|---|---|---|
| `MagazineSpec` (autoloader) | Random, any class except heavy assault; max 1 branch per faction | `size 3–5`, `intraClipS 1.5–3.0`, `reloadS` chosen so that sustained DPM = **0.85 × class baseline DPM**; burst `n·α ≤ 0.85 ×` same-tier MT HP | Burst cap keeps "full clip = dead Tier X medium" out. Rammer not allowed (= WoT) |
| `AutoreloaderSpec` | Random, mediums and TDs | `size 2–4`; `perShellReloadS` listed in **refill order**; the **first refill after the magazine empties is the longest**; sustained DPM = **0.92 × baseline** | Firing never resets a loading slot (= WoT) |
| `DualGunSpec` | Random, Tier VII+ heavies only (≤1 line) | Per report 01 R9: `salvoDelayS 1.5`, `chargeTimeS 1.0`, volley dispersion ×1.5, `reloadEachS = 2.3 ×` class reload | Charge is cancelled by releasing fire early |
| `SiegeMode` | Random, TD Sniper and TD Support casemates | `transitionS on 2.0 / off 1.25` (= WoT API). In siege: aim ×0.4, dispersion ×0.85, depression +8°, elevation +6°, max speed 10 km/h, hull traverse ×0.5. Travel mode: reverse speed = forward × 0.9. Auto-engage after 0.5 s stationary (player option) | WoT Strv 103B: aim ×0.33, dispersion ×0.83, reverse 45→10 (confirmed by fact-check). Hull traverse ×0.5 is OUR choice; WoT's siege traverse value (`1`, unit unknown) is unclear and the hull is not locked |
| `Hydropneumatic` | Random, Medium Sniper/Versatile | `depressionBonusDeg 4`, `elevationBonusDeg 3`, applied after 0.75 s stationary | Simplified WoT mechanic |
| `Wheeled` (flag) | Random, Light only; ≤1 per team | Cruise mode: top speed = class baseline; **Speed mode**: +30% top speed, steering ×0.6, reverse ×0.7, toggled with a 1.0 s transition. Wheels are modules (report 01: −25% top speed per lost wheel pair). Moving dispersion ×1.15 | = WoT shape |
| `Turbo` | **Equipment** in Random (+7.5% / +10% power, +4 / +5 km/h, matching §6 and report 05; corrected by fact-check, which found the high power value paired with the low speed value). As an **active** ability, Tier XI and event modes only | Active: `powerMultiplier 1.25`, `durationS 6`, `cooldownS 40` | |
| `RocketBoost` | Tier XI, events | `charges 2`, `durationS 2.5`, thrust giving +20 km/h within 1 s, `cooldownS 30` per charge | WoT Tier XI mechanic; numbers ours |
| `ChargedShot` | Tier XI, events | `chargeTimeS 1.5`; full charge gives dispersion ×0.6 **or** +10% damage (pick one per vehicle); charging cancels on hull movement | WoT "charge-up accuracy" |
| `ActiveCooling` | Tier XI, events | `durationS 5`, `cooldownS 45`; reload ×0.85, aim ×0.85 | — |
| Mode abilities (airstrike, smoke, minefield, repair zone) | **Event modes only** | Put in `Events.luau`, never in vehicle definitions | WoT keeps these out of Random |

**Readability rules:**
- Every non-standard mechanic gets a HUD widget: magazine pips, per-shell timers, a charge ring, a siege indicator, a speed-mode icon.
- It also gets a garage tooltip with burst, sustained DPM and time-to-full-aim.
- A launch roster should have **≤20% of Tier I–X vehicles** with any special mechanic.

### R8. Premium vehicles (bought with Robux / Bullion)

**Power rules:**
- Combat stats must sit at the **40th–55th percentile** of the class×role×tier envelope. No core stat may exceed the tech-tree P60.
- This is enforced in the balance lint with a `premium` flag. It matches WoT's measured −3 to −6% DPM/pen.

**Earnings:**
- credit multiplier **×1.35** at Tiers V–VII and **×1.5** at VIII;
- crew XP **×1.5** (= WoT +50%);
- **no** XP bonus beyond that;
- **crew-trainer rule:** any crew of the same faction **and** class can operate it without penalty (= WoT classic).

**Allowed tiers:**
- Tiers II–VIII, with **VIII as the core**. One or two Tier IX premiums at most.
- **None at Tier X or XI** (= WoT: no Tier X premiums are *sold*. The 36 non-tech-tree Tier X vehicles in §7.1 are rewards or collector vehicles. Wording corrected by fact-check).
- **No preferential matchmaking** at launch. It complicates the template matchmaker and invites "my premium is obsolete" complaints.

**Rebalance policy, published:**
- We may rebalance premiums.
- If a premium is nerfed more than 5% in effectiveness, the owner gets either a **full Bullion refund window of 14 days** or a free equivalent swap.
- This is clearer than WoT's historical "no-nerf" ambiguity.

**Rationale:** Roblox audiences are very sensitive to pay-to-win. Premiums sell convenience and economy, not power.

### R9. Faction identities: original kits inspired by §9

Each faction is a **±5–15% kit on core stats** (armor and gun arcs may deviate further, e.g. hull armor ×0.60) applied to the class×role baseline, plus at most two signature mechanics. (Corrected by fact-check: this said ±5–12%, but the table below uses ×0.60–×1.15. The R3 balance lint now includes the faction kit in its baseline.) Names here are placeholders; the content team names factions.

| Archetype kit | Multipliers | Signature mechanics | WoT inspiration (do not copy names or lore) |
|---|---|---|---|
| **"Iron Front"** (brawler bloc) | alpha ×1.10, reload ×1.10, turret armor ×1.10, dispersion ×1.06, aim ×1.05, depression −5° | Dual-gun heavy line | USSR / China |
| **"Precision Works"** | dispersion ×0.94, HP ×1.05, hull armor ×1.06, hp/t ×0.94 | — | Germany |
| **"Ridgeline Union"** | depression −10°, aim ×0.94, reload ×0.95, turret armor ×1.08, lower plate ×0.85 | — | USA |
| **"Crown Arsenal"** | dispersion ×0.93, alpha ×0.92, reload ×0.92, speed ×0.93, depression −10° | HESH shells (report 01) | UK |
| **"Swift Republic"** | hp/t ×1.10, speed ×1.06, turret armor ×0.80 | Magazine; Wheeled light line | France / Czech |
| **"Northwind"** (optional 6th) | speed ×1.15, depression −12°, hull armor ×0.60 | SiegeMode TDs; Hydropneumatic mediums | Sweden |

Each faction should field all five classes, but "flavour lines" need not exist at every tier.

---

## Open questions / uncertain items

1. **Role release version and "action points".** Was it 1.10 or 1.10.1 (2020)? Does the role-action defeat-XP mitigation still exist in 2.x, and how is it computed? (Low; recollection only.)
2. **Tier XI roster and stats.** Vehicle names, HP, alpha and pen per Tier XI; Tier XI matchmaking spread (X–XI, or IX–XI?); whether any Tier XI SPG exists after 2.1.1 or 2.4.
3. **2.4 light-tank subclasses.** Is the ≤2 LT cap per team or per class mix? How do Scout, Versatile and Support map onto existing LTs?
4. **Post-2.0 module counts.** How many modules does a 2.0 Tier V–IX vehicle have, and what are the new costs? Were suspensions removed entirely from some lines?
5. **Stun debuff magnitude.** WoT's exact stat penalty while stunned (−25% crew skill?), and how the duration scales between `min` and `max` (distance, damage, or both). Whether the first-aid kit's interaction changed after 1.26.
6. **Arty history after 9.18.** Any shipped changes such as alternative SPG shells, tracer changes or count limits? Only the 9.18 rework and the ≤3 cap are reasonably established here.
7. **Wheeled speed-mode numbers.** The API exposes only one speed (EBR 105: 70/50). Speed-mode top speed (≈90 km/h?) and the steering penalty are unverified.
8. **Rocket booster origin.** Did any Tier I–X tech-tree vehicle have rocket boosters before 2.0, and with what charges and thrust? Same question for Tier XI "direct drive".
9. **Overheating ("temperature") guns.** A community key `role_MT_support_temperatureGun` suggests some support mediums have a heat or overheat gun mechanic. Unverified, so not included above.
10. **Siege-mode arcs.** The API's siege `move_down_arc` / `move_up_arc` values (2 / 9 for the Strv 103B) do not match the commonly cited in-game arcs. The meaning of those fields for hydropneumatic vehicles is unclear.
11. **Snapshot drift.** Class medians come from Aug 2021 (combat) and May 2017 (armor and handling) (corrected by fact-check). The 1.26 and 2.0 rebalances may have shifted medians by a few percent. A fresh `vehicleprofile` dump would close this if the API becomes reachable.
12. **Premium credit coefficients.** WG has never published exact values; we use our own ×1.35 / ×1.5.
13. **Mir Tankov divergence.** Not analysed (roles, tiers, mechanics).

---

## Source index

**Primary data (official API, mirrored)**
- [Wargaming Developer API: encyclopedia/vehicles](https://developers.wargaming.net/reference/all/wot/encyclopedia/vehicles/)
- [GuilleHoardings/wot_tank_data: `wot_data.csv` and extractor querying `api.worldoftanks.eu/wot/encyclopedia/vehicleprofile/`](https://github.com/GuilleHoardings/wot_tank_data)
- [aki33524/wotdatabase: API/vehicles/1..6 (May 2017)](https://github.com/aki33524/wotdatabase)
- [Roexoe/guesswot: `wottanks.json` (API static 2.76.0, 2024–25)](https://github.com/Roexoe/guesswot)

**Community repositories**
- [unicum.gg role constants](https://github.com/unicum-gg/unicum.gg/blob/main/packages/shared/src/constants/tanks.ts)
- [unicum.gg game-term locale (Field Modification role keys, mode abilities)](https://github.com/unicum-gg/unicum.gg/blob/main/apps/web/src/locales/en/game/equipment.json)
- [XVM changelog (WoT 1.29 → 2.0, `{{v.role}}`, stun shell type)](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md)
- [Wikipedia text mirror](https://github.com/Nice9Tian/stable-query-latent/blob/main/VICReg_review/wiki_descriptions/1407200_World%20of%20Tanks.txt)

**Official pages cited via sibling reports (not re-fetched here)**
- [Update 2.0: Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/)
- [Update 2.0: The Biggest Vehicle Rebalance](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)
- [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
- [2.0 Hub](https://worldoftanks.eu/en/news/updates/2-0-hub/)
- [Update 2.4](https://worldoftanks.com/en/news/updates/wot-2-4/)
- [1.26 rebalances](https://worldoftanks.eu/en/news/general-news/vehicle-rebalances-1-26/)
- [Equipment 2.0 (WG support)](https://wargaming.net/support/en/products/wot/article/33291/)
- [1.10 list of changes](https://worldoftanks.com/en/content/docs/release_notes/update-1-10-list-of-changes/)
- [Field Modification 1.14](https://worldoftanks.com/en/news/updates/update-1-14-field-modification/)
- [Personal Missions 3.0](https://worldoftanks.eu/en/news/general-news/update-2-0-personal-battle-missions-3-0/)
- [Premium vehicle improvements](https://worldoftanks.com/en/news/general-news/premium-vehicle-improvements/)
- [Survival Guide: Premium Tanks](https://worldoftanks.com/en/content/player-guide/written-guide/suvival-guide-premium-tank/)
- [Frontline reserves guide](https://worldoftanks.eu/en/news/general-news/frontlines-reserves-guide/)

**Sibling reports**
- [01 Ballistics/armor/damage](01-ballistics-armor-damage.md)
- [02 Spotting/camouflage](02-spotting-camouflage.md)
- [05 Progression/economy/crew/equipment](05-progression-economy-crew-equipment.md)

---

## Verification log

Fact-check pass, 2026-10-05 (adversarial; each claim was assumed wrong until it was re-derived or independently sourced).

**Method and limits.**
- **No web search:** the session's web-search budget was exhausted (200/200). WebFetch was blocked for every non-GitHub host tried, including thearmoredpatrol.com, mmos.com and massivelyop.com, on top of the hosts already listed in the evidence note.
- **What was reachable:**
  - **API recomputation.** Fresh `git clone`s of the three Tankopedia-API mirrors, then every [API] number below was recomputed with the report's stated method: tech tree only, top configuration = max(HP, pen, engine hp, DPM), and medians.
  - **Community GitHub sources:** unicum.gg, the XVM changelog, the Wikipedia text mirror, and a Random-MM reimplementation.
  - **Sibling fact-checks:** evidence in reports 02, 04 and 05 that came from official WG video narration and listings mirrored on GitHub. It is independent of this report's author but was not re-read here, so it is labelled "sibling fact-check".
- **Excluded evidence:** decompiled or extracted client sources (`izeberg/wot-src`, `WorldOfTanks-Decompiled`) surfaced in code search and were **not** used, per this report's rule.
- **Unverified is not refuted:** "Unverified" means no independent source could be reached. The claim keeps the author's evidence, with lowered confidence.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | API snapshot dates: `wot_tank_data` "≈ late 2022"; `wotdatabase` "≈ 2017–18" | **Corrected** to **Aug 2021** and **May 2017**, everywhere in the report | Git history: [wot_tank_data](https://github.com/GuilleHoardings/wot_tank_data/commits/647b05d34e896551725c53147201df0b994875f0) "Update data for patch 1.14" on 2021-08-16, last commit 2021-08-31. [wotdatabase](https://github.com/aki33524/wotdatabase/commits/a024cafc1293db72521928fc5362e228377723da): all 4 commits on 2017-05-16. [guesswot](https://github.com/Roexoe/guesswot/blob/3d2b4280c67cf1b4f525cfa3362fceb8b2d80fa1/wottanks.json): last commit 2025-06-19, consistent with "2024–25" |
| 2 | Class ÷ MT ratios (HT HP 1.17 / alpha 1.26 / reload 1.28; TD alpha 1.68 / reload 1.50 / pen 1.19; LT hp/t 1.77 / speed 1.18; SPG HP 0.29 / alpha 2.56 / reload 4.56). The MT tier ladder (I 300 HP … X 1,950 HP / 263 pen / 2,752 DPM). Tier X medians (LT reload 10.7 s; HT 2,350 / 490; TD 2,000 / 750 / 294 / 17 s; SPG 510 / 900 / 39 s). Spot values: T-100 LT 15.0 t / 720 hp, ST-II 2,500 HP / 440 alpha, EBR 105 70 / 50 km/h and 190 pen, EBR 90 65 / 65 | **Confirmed** (every value reproduced exactly) | Recomputed from [wot_data.csv](https://github.com/GuilleHoardings/wot_tank_data/blob/647b05d34e896551725c53147201df0b994875f0/wot_data.csv): 14,691 rows, 708 vehicles |
| 3 | "Stock and top never differ in top speed" / "×1.00 always" | **Corrected** to "almost never" | Same CSV: 1 of 708 vehicles (IS-2) has configuration-dependent top speed |
| 4 | Research graph: gun→gun 470, radio 457, engine 411, suspension 314, turret→gun 138, turret→turret 95, gun→turret 69. Next-vehicle unlocks gun 222 / turret 51 / engine 34 / suspension 21 / radio 16 (344). Stock suspension spare capacity 1.5–3.2% | **Corrected** (unlock counts); edges and margins **confirmed** | [wotdatabase `API/vehicles`](https://github.com/aki33524/wotdatabase/tree/a024cafc1293db72521928fc5362e228377723da/API/vehicles) `modules_tree`. Edges reproduce exactly for Tiers II–X (gun→gun is 479 with Tier I). Unlocks recount to gun **230** / turret 54 / engine 34 / suspension 21 / radio 18 = **357** (no tier filter gives 344). Spare capacity medians II–IX are **1.4**–3.2% |
| 5 | Strv 103B siege: aim 3.0→1.0, dispersion 0.30→0.25, reverse 45→10, on 2.0 s / off 1.25 s; "hull traverse is locked"; "same pattern on UDES 03" | **Corrected** (numbers confirmed; "locked" and the UDES 03 claim are wrong) | wotdatabase `default_profile.siege`: Strv 103B `switch_on_time 2.0`, `switch_off_time 1.25`, `speed_backward 10`, `suspension_traverse_speed 1` (travel `traverse_speed 35`); UDES 03 `switch_off_time 2.0`, `speed_backward 5`. §6's own rule text says the hull turns to aim |
| 6 | SPG stun ranges per tier (Tier X 13.05–35 s, min/max 0.45–0.50) and Tier X SPG HE 750–1,300 alpha, 45–60 pen, 32–52 s reload, 0.59–1.08 dispersion, 4.5–6.1 s aim | **Confirmed** | wotdatabase ammo `stun.duration`: Obj. 261 [13.05, 29.0], T92 HMC [15.75, 35.0], G.W. E 100 [13.95, 31.0], Conqueror GC [14.85, 33.0], B-C 155 58 [13.5, 27.0]; HE damage 750–1,300 and pen 45–60 |
| 7 | Premium Tier VIII ÷ tech tree (MT HP 0.96 / DPM 0.94 / pen 0.97; HT 0.97 / 0.95 / 1.00, alpha 1.12, reload 1.20; TD 1.02 / 0.96 / 0.97, speed 1.28). Roster 917 vehicles, 429 premium or reward, 184 at Tier VIII | **Confirmed** | wot_data.csv (n = 13 / 48, 17 / 43, 12 / 19 as stated); [wottanks.json](https://github.com/Roexoe/guesswot/blob/3d2b4280c67cf1b4f525cfa3362fceb8b2d80fa1/wottanks.json): 917 entries, 429 `is_premium`, tiers V 39 / VI 34 / VIII 184 / IX 55 / X 36 |
| 8 | Nation depression medians (USSR/China −5°, US −10°, Sweden −12°) and flat view range (Tier I 280 m, Tier X 400–405 m, SPG 300) | **Confirmed**, with a caveat | wotdatabase: all medians reproduce. Sweden is −12° only when the 4 siege TDs (travel arcs −1/0) are excluded; it is −10° with them. A note was added under §9.1 |
| 9 | Role tokens and English names (`break` → Breakthrough, `universal` → Versatile, …); Field Modification pairs 1–3 class-wide and 4–5 role-specific; example pair names; `role_MT_support_temperatureGun`; XVM 13.0.0 (WoT 2.0) added `{{v.role}}`; XVM 9.1.0 `high_explosive_stun`; "Mir Tankov 1.36" beside WoT 1.29.1.1 | **Confirmed**; one clarification: `scout` is only in FM keys, not in unicum's role-label list | [unicum.gg tanks.ts](https://github.com/unicum-gg/unicum.gg/blob/main/packages/shared/src/constants/tanks.ts), [unicum.gg equipment.json](https://github.com/unicum-gg/unicum.gg/blob/main/apps/web/src/locales/en/game/equipment.json) (`role_HT_break_pair_5_1` "Reinforced Platform", `role_ATSPG_sniper_pair_5_1` "PTO Tuning", `role_LT_wheeled_pair_5_1` "Recon Kit", `role_LT_scout_pair_*`), [XVM ChangeLog-en.md](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md) (lines 1–19 and 345–355) |
| 10 | Tier XI shipped with Update 2.0 on 3 Sept 2025: 16 vehicles (7 HT / 5 MT / 3 TD / 1 LT), replaces Field Modification, Elite cosmetics; every nation but Italy has one | **Confirmed** | [Wikipedia text mirror](https://github.com/Nice9Tian/stable-query-latent/blob/main/VICReg_review/wiki_descriptions/1407200_World%20of%20Tanks.txt) ("all but Italy hosting at least one Tier XI tank, as of … Update 2.0"), re-read. Sibling fact-checks: WG "Update 2.0: Overview" narration ([Heinz217/TraceAV-Bench-Submission](https://github.com/Heinz217/TraceAV-Bench-Submission), report 05 row 3), IGN listing "launching on September 3" (report 04 row 3), 2.0.0.0 mirror date 2025-09-03 (report 02 row 19) |
| 11 | Tier XI unlock 325,000 XP + 7,400,000 credits; up to 25 nodes at 10k / 20k / 25k XP | **Unverified**; confidence lowered High → Medium in Summary 5 and §4 | TAP, mmos and WoT pages unreachable (EGRESS_BLOCKED). The official narration says only "research it for XP and purchase it". Report 05 is the only other source, so it is not independent |
| 12 | 2.x matchmaking: caps ≤3 LT, ≤5 TD, ≤1 wheeled, ≤3 SPG; "no evidence of role-level balancing for other classes" | **Corrected**: WoT 2.0 MM **does** take roles into account. LT 3 / TD 5 **confirmed**; wheeled 1 / SPG 3 **unverified** for 2.0 | Sibling 04 fact-check (rows 5–7), citing WG's 2.0 narration: "teams are limited to three light tanks and five tank destroyers each"; "vehicle roles are taken into account"; "a Badger against a T110E3, not against a Grill 15". Precursor: [wot-offline-battles MM notes](https://github.com/pengw0048/wot-offline-battles/blob/main/docs/testing/094-match-spg-contact-radio.md) cite WG's 9.20.1 "matchmaker improvements" adding "VIII-X combat subroles" |
| 13 | 9.18 (2017): stun, Tier X LTs, ±2 templates (3/5/7), ≤3 SPG | **Confirmed** (Rec → Medium-High) | XVM 6.6.0 "World of Tanks 9.18 worldwide release" added a stun marker ([XVM changelog](https://github.com/modxvm/XVM/blob/master/release/doc/ChangeLog-en.md)). The May 2017 API dump has Tier X LTs and stun. The MM reimplementation above uses "3/5/7, 5/10, or one-tier slots" and "0..3 SPG", citing WG's 9.18 release announcement |
| 14 | 2.4 "Overdrive" in Sept 2026; LT Scout / Versatile / Support subclasses; ≤2 LT per team | **Unverified** (cap and subclasses); the **date is confirmed** | Date: 2.4.0.0 client-mirror date 2026-09-02 (report 02 row 19); mod catalog "added support for World of Tanks 2.4.0.0" on 2026-09-03 (report 04 row 8). No source independent of report 05 for the cap. FM keys `role_LT_scout/support/universal` exist but are undated |
| 15 | Introduction versions: roles 1.10 / 1.10.1 (2020), Field Modification 1.14 (2021), wheeled LTs 1.4 (2019), dual-gun 1.10.1 / 1.11 | **Unverified** | No reachable first-party source; a GitHub code search for "field modernization" plus "1.14" found nothing. Weak corroboration: XVM 7.7.8 for the WoT **1.3** client already hides "changing the driving mode (for wheeled vehicles)" hints. That fits 1.3/1.4 but does not pin the version. Confidence left at Low–Medium as stated |

**Tally:** 15 claims checked. **7 confirmed** (#2, 6, 7, 8, 9, 10, 13), **5 corrected** (#1, 3, 4, 5, 12), **3 unverified** (#11, 14, 15).

**Implementation recommendations: internal consistency check**

| Item | Verdict | Fix |
|---|---|---|
| R1 "Roles (R2) then add ±10% trims" vs. R2 trims of speed ×0.85 / ×1.15 and armor ×0.6 / ×1.6 | **Corrected** | Now "±5–15% on core stats; larger on armor and camo". |
| R1 TD hull-front "Sniper 0.4" vs. R2 `TDSniper` armor ×0.6 on a 1.1 class value, which gives 0.66 | **Corrected** | R1 now derives Assault ≈1.75 and Sniper ≈0.65 from the R2 trims. |
| R2 defeat protection "the role-action payoff WoT experimented with", stated as fact, while §2.1 item 6 rates it Low and unverified | **Corrected** | Relabelled "inspired by", OUR DESIGN CHOICE. |
| R2 matchmaking TD ≤4 vs. report 04 R3 `CLASS_LIMITS.TD = 5` | **Flagged** (cross-doc) | A note says report 04 owns `Matchmaking.luau` constants; reconcile there. The ≤3 SPG and 2.4 ≤2 LT parity claims are now marked unverified. R2's soft role mirroring is now noted as close to WoT 2.0 parity. |
| R3 spread "V–X ±2" vs. "XI: X–XI only": ±2 would put Tier IX with XI | **Corrected** | ±2 is capped at Tier X; only X–XI battles contain XI. |
| R3 "our pens at V–IX are 15–25 mm under WoT" vs. its own table (VII 160 = WoT 160) | **Corrected** | Per-tier gaps listed: −24 / −15 / 0 / −17 / −23 / −8. |
| R3 balance lint baseline (class × role × tier) vs. R9 faction kits of up to ×1.15 / ×0.90, which would trip the [0.92, 1.08] warning on every faction vehicle | **Corrected** | The faction kit is now part of the lint baseline. |
| R4 "softer than WoT's classic pen ×1.13–1.67" vs. §5.1 (×1.03–1.97; VIII–IX ×1.03–1.40) | **Corrected** | Softer at II–VII, about equal at VIII–IX. "222 of 344" is now "230 of 357 (≈ ⅔)". |
| R6 "WoT ≈ 900–1,300" HE alpha and "45–60% of WoT maxima (10.4–35 s)" | **Corrected** | Now 750–1,300 (median 900). The stun ratio holds at VII–X only; V–VI are higher; 10.4 is now 10.5. |
| R7 Turbo "(+10% power, +4 km/h)" vs. §6 and report 05 "+7.5 / +10%, +4 / +5 km/h" | **Corrected** | Values now paired as in §6. |
| R7 SiegeMode "hull traverse ×0.5" presented next to WoT values, while the summary said WoT "locks" the hull | **Corrected** | Labelled OUR choice; WoT's siege traverse value is unclear and the hull is not locked. |
| R5 exotic list omitted `ActiveCooling`, which R7 defines as Tier XI | **Corrected** | Added. |
| R8 "= WoT tech-tree-only Tier X" vs. §7.1's 36 non-tech-tree Tier X vehicles | **Corrected** (wording) | Now "no Tier X premiums are sold; Tier X extras are rewards". |
| R9 "±5–12% stat kit" vs. kits with hull armor ×0.60, turret armor ×0.80 and speed ×1.15 | **Corrected** | Now "±5–15% on core stats; armor and arcs may deviate further". |
| R3 DPM column (= α·60/reload for all 11 rows); R5 Tier XI ÷ X ratios (1.13 / 1.10 / 1.08 / 1.07); R6 Tier X values (800, ≤880, 38 s, 5.1 s, 0.60); R2 Role Score weights sum to 1 | **Confirmed** | Recomputed by hand. |
