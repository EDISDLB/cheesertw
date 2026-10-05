# Research 02: Spotting, view range, camouflage, signal range and information warfare

> Reference game: World of Tanks PC (Wargaming EU/NA/Asia), state as of 2025–2026 (Updates 2.0 → 2.2). The live PC
> client at the research date is **2.4.0** (2.3 went live around June 2026 and 2.4 around September 2026). Neither update
> was researched here. The fact-check compared the claims with 2.4.0 player-visible text (corrected by fact-check).
> Prepared for HULLDOWN (an original Roblox game). No WoT assets, client files or datamined values are used.
> Research date: 2026-10-05.
>
> **Fact-check (2026-10-05).** An adversarial pass checked the implementation-critical claims again. Its evidence:
> - **player-visible UI text** of the WoT 2.4.0 EU client: the in-game manual, parameter tooltips, equipment and perk
>   descriptions. It was read from a public GitHub mirror, used only as evidence, and nothing from it goes into HULLDOWN.
>   No numeric game-data files were used;
> - Roblox's official `creator-docs` repository;
> - community sources reachable through GitHub.
>
> The web-search budget was exhausted, and most WoT and community sites are blocked by the proxy. Claims that could not
> be checked again are marked **Unverified** in the *Verification log* at the end. Inline changes are marked
> "(corrected by fact-check)" or "(downgraded by fact-check)".
>
> **Method and evidence quality.** The sandbox egress proxy blocked direct page fetches for every WoT, wiki and
> community domain tried (worldoftanks.*, wargaming.net, fandom, wotlytics, tankr.live, thearmoredpatrol, 13disciple,
> overtankpro and others). The evidence is therefore **search-engine result summaries** of the pages linked below, plus
> clearly labelled prior knowledge. The session's web-search budget ran out partway through, so a few items could not be
> cross-checked a second time. They are marked **Low** or **Medium** and listed under *Open questions*. Values marked
> **OUR DESIGN CHOICE** are HULLDOWN decisions, not WoT facts.

---

## Summary

1. **Spotting is server-side and binary per observer–target pair.** A target is spotted when it is within **50 m**
   (proximity, ignores line of sight), **or** when it is inside the observer's *effective spotting distance* and at
   least one ray from one of the observer's **2 view ports** reaches one of the target's **6 visibility checkpoints**
   without hitting hard cover. (High for the 50 m rule, LOS and the 2 ports. **Medium for "6 checkpoints"**: a 2025
   community debug mod shows 5 hull/turret "bounding" points, and the 2 view ports also act as points. Downgraded by
   fact-check.)
2. **The core formula has not changed for years:**
   `spotDist = min(445, VR − (VR − 50) × camo)`, which is the same as `50 + (VR − 50)(1 − camo)` with a 445 m cap.
   `camo` is the target's total concealment (0..1), and VR is *not* clamped before the formula. (High)
3. **445 m is the maximum spotting range. 564 m is the render/draw radius.** View range above 445 m is still useful
   because it eats into enemy camouflage. The draw radius has been a **564 m circle** since **Update 9.12**; before that
   it was a 1000 m square (500 m straight, 707 m diagonal). The current in-game manual gives the radius as **565 m**;
   the 1 m difference does not matter (corrected by fact-check). Enemies spotted by allies beyond the draw circle appear
   only on the minimap. (High)
4. **Visibility checks are staggered by distance:** every 0.1 s at 50 m, 0.5 s at 150 m, 1 s at 270 m and 2 s at
   445 m. The two ports are checked alternately, and extra immediate checks run when a vehicle **fires** and when it
   **stops**. (**Medium**: the values come only from search summaries of one Wargaming support article and could not
   be checked again. Downgraded by fact-check. The interpolation between them is our assumption.)
5. **Spotted status lingers for 10 s by default.** The 2.4 client's parameter tooltips say: "the duration enemies are
   visible after they leave your visibility range. The default value is 10 seconds". The tooltip for your own vehicle
   gives the same 10 s. In current WoT this is a **per-vehicle stat**: the *Improved Radio Set* equipment and the
   radio-operator perk *Jamming* change it. Rewards for spotting assistance follow the same window. (High; corrected
   by fact-check, previously Medium "5–10 s")
6. **Camouflage = vehicle base (moving vs stationary) × crew concealment skill × after-shot factor + paint + camo net +
   foliage**, capped at 1.0 (community formula). Light tanks usually keep the same camo when moving. Every gun has its
   own after-shot camo multiplier, and it is still a published and tuned stat in 2026 balance notes. The client now
   **shows** stationary, moving and after-firing concealment (%) in vehicle parameters (corrected by fact-check).
   The paint/style bonus **depends on vehicle class** (in-game text), not a flat +5% (corrected by fact-check).
   (Medium-High)
7. **Foliage is semi-transparent concealment, not hard cover.** Bushes and tree crowns, standing or **fallen**, add
   concealment to targets behind them. Contributions stack additively up to a cap (community reports: 80%). Single
   objects are reported at 25–50% (up to ~64% for the densest). Terrain, rocks and buildings block line of sight
   completely. Grass gives no concealment (in-game manual: "any type of vegetation (except grass)"; added by
   fact-check). (Medium for the structure. The numeric bush values and the cap are unverified.)
8. **The 15 m rule.** (a) An observer sees through foliage within 15 m of itself. (b) When you fire, foliage within
   15 m of you briefly stops concealing you, while foliage further than 15 m keeps working. This makes possible the
   "double-bush" or "sit 15 m behind the bush" sniping technique and its trade-off: the bush is then opaque to your own
   view too. (High for the rule. Low for the exact after-shot duration.)
9. **Sixth Sense has been built into every commander since Update 1.18.1 (Oct 2022).** It shows an alert
   **3 s** after you are spotted (**2 s** with the *Increased Focus* directive, "Sixth Sense is activated 1 s
   earlier"). It never tells you when you are no longer spotted. It is disabled while the commander is injured. The
   radio-operator perk *Signal Interception* shortens the delay (added by fact-check). (High. Whether *Increased Focus*
   is still sold was not checked.)
10. **2020–2026 changes affected modifiers only, not the formula.** Equipment 2.0 (1.10, Aug 2020): Coated Optics
    +10% (11.5% in a matching slot), Binocular Telescope +25% (27.5%) after 3 s stationary, and Camo Net
    +5/10/15% by class (+7.5/12.5/17.5%). Crew perks rework (1.26, 2024): *Recon* +2% VR and −20% penalty from
    damaged observation devices; the *Concealment* group perk gives +80% concealment when trained on the whole crew.
    Update 2.1.1 (announced Dec 2025; the EU client mirror first shows it on 2026-01-14): the bond *Telescopic
    Observation System* gives +27.5%, active after 1.5 s. Update 2.2 (Feb–Mar 2026): the radio-operator perk
    ***Threat Search*** raises VR "for 5 s after receiving the Sixth Sense alert". (Medium, downgraded by fact-check.
    The 2.4 UI confirms the 3 s and 1.5 s activations, Coated Optics +10%, Telescopic Observation System +27.5% and
    Threat Search's 5 s. The perk percentages, binocular 25/27.5%, optics 11.5% and the camo-net class values appear in
    the UI only as placeholders and stay **unverified**. The bond *Experimental Optics* gives **+13.5%**, not 12.5%:
    corrected by fact-check.)
11. **Signal range is now vestigial.** The old rule was that two vehicles share spotting information if their distance
    is at most the sum of their radio ranges, relayed through chains of allies. Wargaming cut radios to a single
    top-range module in rebalanced lines (1.26) and "streamlined" radio modules in Rebalance 2.0 (2025). In Random
    Battles everyone effectively shares the whole team's vision. (Medium)
12. **Random Battles have no smoke, weather or time-of-day effect on visibility.** Smoke exists only in special modes,
    e.g. the Frontline *Smoke Screen* reserve: 5 grenades over a 200×50 m area for 50 s. In-game text says it
    "conceals **all** vehicles inside and behind the smoke". Enemies inside get reduced VR and crew performance, which
    lasts through a "wind down time" after they leave (corrected by fact-check; previously "conceals allies inside").
    The −30% VR / −15% crew figures are **unverified**. Other special modes do change spotting: Map Box "Local
    Weather" zones block spotting across their boundary, and Onslaught "Night Maps" use modified spotting (added by
    fact-check). (Medium-High for Random Battles; Low-Medium for the smoke numbers)
13. **Spotting pays.** There is a small first-detection bonus per enemy (doubled for SPGs), and spotters earn a share
    of the XP and credits from damage allies deal to targets they spot. The long-standing community description is
    50% of the shooter's reward, split among the spotters. "Assisted damage (spotting)" is a headline stat for light
    tanks. (Medium for the exact split)
14. **Visibility is server-authoritative.** Unspotted enemies are never sent to the client, so wallhacks have nothing
    to reveal. Clients see outlines through walls only for tanks that are already spotted. HULLDOWN's architecture
    already adopts this with custom replication and no vehicle assemblies in `Workspace`. (High)
15. **HULLDOWN recommendation.** Implement the WoT model closely. All tunables go in `Shared/Config/Spotting.luau`, in
    metres. Deliberate deviations:
    - cap the long-range check interval at **1.0 s** instead of 2.0 s;
    - cap total camo at **0.90** instead of 1.0, so there are no truly invisible TDs;
    - foliage is evaluated **analytically** from map data rather than by physics raycasts;
    - signal relay is **off** by default;
    - the after-shot foliage penalty lasts an explicit **3 s**.

---

## Detailed findings

### 1. View range, spotting cap and draw distance

**Modern behaviour**
- Every vehicle has a **view range (VR)** stat, typically a few hundred metres. VR is used *only* as an input to
  the spotting formula; it is not a rendering distance.
- **Maximum spotting range: 445 m.** You can never personally spot anything further than 445 m. VR above 445 m is
  not wasted, because the formula subtracts enemy camo *from the full VR* before the cap is applied.
- **Draw distance: 564 m circle.** Vehicles spotted by your team are rendered in 3D only within 564 m of you. Spotted
  enemies further away (possible because allies elsewhere spot them) appear on the minimap only.

**Exact values**

| Quantity | Value | Since |
|---|---|---|
| Max spotting range | 445 m | long-standing |
| Draw (render) radius | 564 m circle (565 m in the current in-game manual: corrected by fact-check) | Update 9.12 |
| Pre-9.12 draw area | 1000 m square (500 m straight, 707 m diagonal) | before 9.12 |
| Proximity spotting radius | 50 m | long-standing |

**History.** *Update 9.12 (2015)* replaced the 1000 m draw **square** with a **564 m circle**. 564 m gives roughly the
same area as the square (π·564² ≈ 0.999 km²). The goal was to "provide for a proportional distribution of spotting
along the whole circle and eliminate the irregularity". Straight-ahead draw distance rose about 13% (+64 m), while
diagonal distance shrank. The 445 m cap was not changed.

**Confidence:** High.

**Sources:** [WG support: About Spotting and Concealment](https://wargaming.net/support/en/products/wot/article/10222/) ·
[View Range Changes in Update 9.12 (WoT NA)](https://worldoftanks.com/en/news/general-news/view-range-changes-10-0/) ·
[In Development: Spotting Range Changes (WoT Asia)](https://worldoftanks.asia/en/news/general-news/in-development-view-range-changes/) ·
[wiki.wargaming.net: Camo and Spotting](https://wiki.wargaming.net/en/Camo_and_Spotting) ·
[Fandom: View Range & Camouflage](https://worldoftanks.fandom.com/wiki/View_Range_%26_Camouflage) ·
[wotlytics: Spotting & Camouflage](https://wotlytics.com/mechanics/spotting/)

### 2. Observation ports (where you look from) and visibility checkpoints (what is looked at)

**Modern behaviour**
- The observer has **two view-range ports**:
  - one **static** port fixed to the hull;
  - one **dynamic** port that moves with the turret (for turretless vehicles it sits on the superstructure).
- The target has **six visibility checkpoints**, distributed over the hull, turret and gun mount.
- Line of sight exists when a ray from **at least one port** reaches **at least one checkpoint** without being
  blocked by terrain or buildings. Foliage on the way reduces visibility rather than blocking it (§4).
- Ports are checked **in turn, not simultaneously** (see §5).
- Consequences that players exploit:
  - **Hull-down:** only the turret checkpoints are exposed, so the hull checkpoints are blocked.
  - **"Tracks are not checkpoints"** (community claim): showing only running gear does not get you spotted.
  - **Ridge peeking:** the high turret port can see over crests that hide the observer's hull.

**Exact values:** 2 ports and 6 checkpoints. Exact positions per vehicle are not publicly documented; they are
vehicle-model data.

**Fact-check note (corrected by fact-check).** The 2025 community debug mod *wotstat-debug-utils* draws these points.
It shows a different layout from "6 checkpoints".

Five **bounding (checkpoint) points**:
1. on the gun-elevation axis, with the turret at zero rotation;
2. the centre of the hull bounding box's front face;
3. the centre of its rear face;
4. the centre of its left face, raised to the height of point 1;
5. the centre of its right face, raised to the height of point 1.

Two **view points (ports)**, which also count as bounding points:
- a **static** port at the vehicle pivot, raised to the top of the hull+turret bounding box;
- a **dynamic** port at point 1 that follows turret rotation.

The mod notes that the ports "coincide with and overlap the visibility checkpoints".

So the checkpoint count is 5 to 7, depending on how the ports are counted, and none of the points sit at track level.
This supports the "tracks are not checkpoints" claim. HULLDOWN's own layout (Open question 3) is unaffected because
it is a design choice.

**History:** The port/checkpoint model is old (it predates 9.x). *Update 9.16 (2016)*, "Visibility System Improvements",
rewrote the server visibility code in a more efficient language "while keeping all previous operating rules", and sped
up the client display of newly spotted vehicles, "particularly noticeable … at a distance of more than 300 m". Wargaming
noted the gameplay effects:
- long-range spotters gained a little time to shoot;
- vehicles crossing short open gaps became harder to sneak past.

**Confidence:** High for 2 ports. Medium for the count of 6 checkpoints (downgraded by fact-check). Low-Medium for
exact positions (community mod only).

**Sources:** [Update 9.16: Visibility System Improvements (EU)](https://worldoftanks.eu/en/news/general-news/version-916-spotting-improvement/) ·
[Visibility System Improvements in 9.16 (NA)](https://worldoftanks.com/en/news/general-news/916-spotting/) ·
[WG support 10222](https://wargaming.net/support/en/products/wot/article/10222/) ·
[HyperX: View, Spotting & Signal Range guide](https://ag.hyperxgaming.com/article/5710/world-of-tanks-view-spotting-and-signal-range-guide) ·
[13DISCIPLE: Vision Mechanics](https://www.13disciple.stream/vision-mechanics.html)

### 3. The detection formula

**Modern behaviour.** For an observer with effective view range `VR` and a target with total camouflage factor
`camo ∈ [0, 1]`:

```
spotDist = min(445, VR − (VR − 50) × camo)        -- ≡ 50 + (VR − 50)·(1 − camo), capped at 445
spotted  = (d ≤ 50)                                -- proximity: no LOS needed
        or (d ≤ spotDist and LOS(port → checkpoint) exists)
```
- With `camo = 0` the target is spotted at the full VR (capped at 445 m).
- With `camo = 1` it is spotted only at 50 m.
- The cap is applied **after** the subtraction. With VR 520 and camo 0.10: 520 − 470×0.10 = 473 → 445 m.

**Worked examples** (these become unit tests, see Recommendations R11):

| Observer VR | Target camo | spotDist |
|---|---|---|
| 445 | 0.00 | 445.0 |
| 445 | 0.12 | 397.6 |
| 445 | 1.00 | 50.0 |
| 500 | 0.43 (TD 0.28 + net 0.15) | 306.5 |
| 500 | 0.93 (above + dense bush 0.50) | 81.5 (WoT) / 95.0 with our 0.90 cap |
| 520 | 0.10 | 445 (capped) |
| 300 | 0.18 | 255.0 |

**History.** The formula is unchanged in all sources from the 2010s to 2026. Later reworks changed only the inputs
(equipment, perks, camo values).

**Fact-check.** A Korean wiki from about 2015 gives independent worked examples:
- VR 500 m spots everything with camo below about 12% at 445 m;
- VR 550 m spots everything with camo below about 21% at 445 m.

These match `VR − (VR−50)·camo` (0.122 and 0.21). They do not match `VR·(1−camo)`, which gives 0.11 and 0.19.

The 2.4 tooltip "to view range (up to 445 m), increasing the parameter over 445 m allows for more effective spotting
of enemies" confirms the cap and that VR is not clamped. The in-game manual confirms the 50 m term: "You always spot
enemy vehicles within 50 meters, regardless of cover".

**Confidence:** High.

**Sources:** [levvvel: How does camo work](https://levvvel.com/how-does-camo-work-in-world-of-tanks/) ·
[iyouxin: WoT spotting mechanics](https://iyouxin.eu/info) ·
[Fandom: View Range & Camouflage](https://worldoftanks.fandom.com/wiki/View_Range_%26_Camouflage) ·
[wiki.wargaming.net: Camo and Spotting](https://wiki.wargaming.net/en/Camo_and_Spotting)

### 4. Camouflage factor: composition, per-class bases, firing, crew, net and paint

**Community formula (WoT wiki / fandom, as surfaced by search):**
```
camoFactor = baseCamo × (0.00375 × camoSkill + 0.5) × camoAtShot
           + camoPattern + camoNet + environmentCamo          -- clamped to ≤ 1.0
```
- `baseCamo` is a per-vehicle value, with separate **stationary** and **moving** values.
- `camoSkill` is the crew's average concealment skill as a percentage. The multiplier is 0.5 at 0% and 0.875 at 100%,
  i.e. **+75%** relative to an untrained crew.
- `camoAtShot` is the gun-specific after-shot multiplier: 1.0 when not firing, below 1 right after a shot.
- `camoPattern` is the paint/style bonus, `camoNet` the net bonus, and `environmentCamo` is foliage (§6).

**Per-class base values**

What is confirmed:
- Each vehicle has developer-assigned stationary and moving values.
- **Moving camo is lower than stationary, except for most light tanks, where they are equal.** This is the light
  tank's defining scouting advantage.
- ~~Base camo values are not shown in-game.~~ The 2.4 client shows "Concealment of Stationary/Moving Vehicle (%)"
  and "concealment after firing" in vehicle parameters (corrected by fact-check). Community sites still publish
  derived per-vehicle tables.
- A 2013 overview listed light tanks at roughly 12.8–20.4%. That data is old.

What is not confirmed this session: current per-class ranges. tanks.gg was unreachable. The qualitative ordering
(turretless TDs > LTs > MTs > SPGs/HTs) is well established. Our numeric defaults are in R3.

**After-shot penalty**
- The firing camo multiplier is a per-gun stat. Larger calibres have a bigger penalty.
- It is still actively balanced. A May 2026 change list for the Polish TD *Husarz* shows "Penalty to camouflage upon
  fire: 24.30% → 26.10%" alongside changed "camouflage after firing" values for moving and stationary.
- Firing also forces an **immediate visibility check** (§5) and applies the 15 m foliage rule (§6).
- The **duration** of the penalty is not published in anything we could reach (Open question).

**Crew**
- Before 1.26, the trainable **Camouflage** skill, averaged over all crew, gave +75% at 100%.
- Since **Update 1.26 (Aug–Sep 2024)**, the **Concealment** group perk is described officially as "when fully trained
  for all crew members, increases vehicle concealment by 80%". It is not confirmed whether it uses exactly the same
  base as the old formula.
  - *Fact-check:* the 2.4 UI shows this text with a placeholder (`%(maskingFactor)s`), so **80% is unverified**.
  - The in-game manual adds that Improved Ventilation, Brothers in Arms and consumables raise concealment "only if
    the Concealment perk is trained".
  - The *Natural Cover* directive grants the perk at 100%, or "an additional 10%" if it is already trained.
  - The EU client mirror first shows 1.26 on 2024-09-04.

**Camouflage Net (Equipment 2.0, since 1.10)**
- Becomes active after the hull has been **stationary for 3 s**.
- Bonus by class:

| Class | Standard | In matching slot |
|---|---|---|
| Heavy tanks, SPGs | +5% | +7.5% |
| Light and medium tanks | +10% | +12.5% |
| Tank destroyers | +15% | +17.5% |

- The bonus is additive in the community formula. (Medium)
- *Fact-check:* the 2.4 UI confirms "Increases the concealment of a stationary vehicle **3 s** after it stops" and
  "effectiveness depends on the vehicle type". The per-class percentages and the matching-slot values are
  **unverified**, because the UI shows only placeholders. (Downgraded to Low-Medium.)

**Paint / styles**
- Camouflage paint gives a concealment bonus. The customization guide summary says "**+5%**".
- Some styles are quoted at +2–4% depending on vehicle type. Those figures may be Console/Blitz contamination.
- **Corrected by fact-check:** the 2.4 PC UI states the bonus is class-dependent.
  - Seasonal camouflage: "Bonus to concealment depending on the vehicle type when applying the camouflage to a
    vehicle's hull". It applies on the matching summer/winter/desert map type.
  - Styles: "Bonus to concealment depending on the vehicle type on all map types".
  - So PC does **not** use a flat +5% for every class. The per-class values were not found (Unverified).

**Confidence:** Medium-High for the structure. Low-Medium for the net values (downgraded by fact-check). Low for exact
class bases and for the paint percentages. High that paint is class-dependent.

**Sources:** [Fandom: View Range & Camouflage](https://worldoftanks.fandom.com/wiki/View_Range_%26_Camouflage) ·
[FTR: Vehicle camouflage overview (2013)](http://ftr.wot-news.com/2013/12/18/vehicle-camouflage-overview/) ·
[The Armored Patrol: WoT Changes to Vehicles (2026-05-26)](https://thearmoredpatrol.com/2026/05/26/wot-changes-to-vehicles/) ·
[Crew Perks Update: A Revolutionary New System (1.26)](https://worldoftanks.com/en/news/general-news/new-crew-perks-1-26/) ·
[Crew Rework Complete (2.2)](https://worldoftanks.asia/en/news/general-news/crew-perks-expansion-2026/) ·
[Equipment 2.0 in Update 1.10](https://worldoftanks.com/news/updates/update-1-10-equipment-2-0/) ·
[WG support: How Equipment 2.0 works](https://wargaming.net/support/en/products/wot/article/33291/) ·
[Exterior Customization guide](https://worldoftanks.eu/content/guide/general/customization-guide/)

### 5. View-range modifiers: crew, equipment, perks, consumables, damage

| Modifier | Effect | Since | Conf. |
|---|---|---|---|
| Coated Optics | +10% VR, always on (+11.5% in a matching slot) | 1.10 (Aug 2020) | High for +10% (UI text); 11.5% unverified |
| Binocular Telescope | +25% VR after **3 s** hull stationary (+27.5% in slot); lost immediately on moving | 1.10 | High for 3 s (UI text); Medium for 25/27.5% (unverified) |
| *Experimental Optics* (bond item) | **+13.5% VR** (corrected by fact-check; was "+12.5%") | Equipment 2.0 era | High (UI text) |
| Telescopic Observation System (bond binoculars) | +27.5% VR stationary, active after **1.5 s** | 2.1.1 (announced Dec 2025; live by Jan 2026) | High (UI text) |
| Optics + binoculars together | Do **not** stack: optics apply while moving, binoculars replace them once stationary | — | **Low**: no source found in this or the fact-check pass (downgraded by fact-check) |
| *Recon* (commander perk) | +2% VR; −20% to the penalty from damaged observation devices | 1.26 | Medium. Effects confirmed by UI text; values are UI placeholders (downgraded by fact-check) |
| Radio-operator perk ***Threat Search*** | +2% VR "for 5 s after receiving the Sixth Sense alert" | 2.2 (Feb–Mar 2026) | High for the name and 5 s (UI text; name corrected by fact-check); +2% unverified |
| *Situational Awareness* (radio operator) | Increases VR (historically about +3%) | **current perk in 2.4**, not legacy (corrected by fact-check) | High that it exists; value unverified |
| *Jamming* (radio operator) | Reduces "the time your vehicle remains spotted" | current (2.4) | High that it exists; value unverified (added by fact-check) |
| *Signal Interception* (radio operator) | Shortens the Sixth Sense delay | current (2.4) | High that it exists; value unverified (added by fact-check) |
| *Improved Radio Set* (equipment) | Increases how long an enemy stays spotted after leaving your view range; reduces how long you stay spotted | current (2.4) | High that it exists; value unverified (added by fact-check) |
| Crew skill, commander qualification | VR scales with the commander's effective skill. Food consumables (+10% crew skill), commander bonus and ventilation push effective skill above 100% and so VR above nominal | legacy | Medium (exact curve unconfirmed) |
| Damaged observation devices or injured commander | Reduce VR. The size of the penalty is not confirmed this session (commonly quoted around −50% for devices) | legacy | Low |

**Sources:** [Fandom: Coated Optics](https://worldoftanks.fandom.com/wiki/Coated_Optics) ·
[Equipment 2.0 Sandbox results](https://worldoftanks.com/en/news/updates/sandbox-equipment-2-0-results/) ·
[TAP: New Bond Equipment in 2.1.1](https://thearmoredpatrol.com/2025/12/18/wot-new-bond-equipment-in-update-2-1-1/) ·
[TAP: 10 New Skills in 2.2](https://thearmoredpatrol.com/2026/02/13/wot-10-new-skills-and-crew-system-improvements-in-update-2-2/) ·
[Crew Perks Update 1.26](https://worldoftanks.com/en/news/general-news/new-crew-perks-1-26/)

### 6. Vegetation and hard cover

**Modern behaviour**
- **Hard cover** blocks the LOS ray completely: terrain, rocks, buildings and intact destructible walls.
  - When a destructible object is destroyed, it stops blocking.
  - Whether **vehicles** block spotting rays is not confirmed. Community belief is that they do not (Open question).
- **Foliage** (bushes, tree crowns, **fallen trees**) is semi-transparent concealment:
  - Each foliage object on the ray adds its concealment value to the target's camo **for that ray**.
  - Reported values are **25% or 50%** per bush depending on density, and up to **~64%** for the densest objects.
  - **Stacking is additive**, with a reported cap of **80%** total from foliage.
  - Trees give concealment **whether standing or knocked over**.
  - Vehicles drive through bushes; trees fall when rammed and keep concealing.
- **The 15 m rule** (two halves):
  1. *Observer side.* Foliage within 15 m of the observer is transparent to that observer. You can spot out of the
     bush you are sitting in. The client also renders that foliage semi-transparent.
  2. *Shooter side.* When you fire, foliage within 15 m of you loses its concealment for you for a short time. Foliage
     more than 15 m away keeps its full value. That is why snipers sit ≥15 m *behind* a bush.
     - The trade-off: at that distance the bush is no longer within 15 m of you, so it is **opaque to your own view**
       as well. You need an ally to keep the target lit (the "double bush" technique).
- One guide (probably Blitz-derived) instead says that after a shot only the densest bush within 15 m counts, at 30% of
  its value. This is **not** adopted as the PC rule (Low).
- Foliage concealment is generally understood to apply whether the hider is moving or stationary; the hider's
  *base* camo switches to its moving value. (Medium)

**Exact values:** 15 m threshold (High). Per-bush 25%/50% and 80% stack cap (Medium-Low, community). Duration of the
after-shot foliage loss: not found (Low; described only as "several seconds").

**Fact-check.**
- The 2.4 in-game manual confirms the shooter side of the 15 m rule: "Firing removes all vehicle concealment bonuses
  within a 15-meter radius. Make sure your vehicle is 15 meters away if you want to fire from behind bushes."
- The manual also says "any type of vegetation (except grass) conceals your vehicle". **Grass gives no concealment.**
- In-game tips confirm that "fallen trees conceal your vehicle" and that trees and bushes "will not block incoming
  shells".
- The Korean wiki (c. 2015) confirms the observer side: bushes further than 15 m are drawn opaque in sniper mode and
  block your own view.
- The per-bush values and the 80% cap were **not** confirmed. They stay community-reported.

**History:** The 15 m rule and foliage stacking predate 1.0. The 1.0 HD-map remaster (2018) re-authored vegetation, but
we found no evidence that the rules changed.

**Confidence:** High for the 15 m rule. Medium-Low for the numeric bush values.

**Sources:** [wotlytics](https://wotlytics.com/mechanics/spotting/) ·
[tankr.live spotting guide](https://tankr.live/wot-guide/spotting) ·
[13DISCIPLE: Bush Sniping](https://www.13disciple.stream/bush-sniping.html) ·
[WoT NA: Survival Guide: Playing Without Sixth Sense](https://worldoftanks.com/en/content/player-guide/written-guide/survival-guide-crew-skills/) ·
[Fandom: View Range & Camouflage](https://worldoftanks.fandom.com/wiki/View_Range_%26_Camouflage)

### 7. Proximity, check frequency, linger and last-known positions

**Proximity spotting.** A target **within 50 m** is spotted whether or not there is LOS ("proxy spotting"). This is how
a light tank behind a building can spot a heavy tank around the corner. (High)

**Check frequency**

| Distance | Check interval |
|---|---|
| ≤ 50 m | 0.1 s |
| 150 m | 0.5 s |
| 270 m | 1.0 s |
| 445 m | 2.0 s |

- Checks run **from each port in turn**.
- There are **two additional event checks**: when a vehicle **fires** and when it **stops**.
- Consequences:
  - A camouflaged vehicle can pop out, fire and retreat between long-range checks. The shot check reduces this, but at
    long range a fast vehicle can still cover ~40 m between checks.
  - Stopping triggers a check, so the switch to stationary camo, and to the net or binoculars after 3 s, takes effect
    promptly.

Values between the anchors are not published. Piecewise-linear interpolation is our assumption. (Values: **Medium**.
Only one search-summarised Wargaming support article supports them, and the fact-check could not confirm them
independently. Downgraded by fact-check.)

**Linger and "spotted time"**
- Wargaming's support text, as surfaced by search: "After the tank's visibility checkpoints have disappeared from the
  line of sight, the tank remains visible for a further **10 seconds**."
- Some guides give "5–10 s".
- Community notes about spotting assistance use the same 10 s window: if an enemy stays unseen for 10 s and is then
  re-spotted by someone else, the original spotter loses credit.
- ~~**Medium** confidence.~~ **High** (corrected by fact-check). The 2.4 PC client's parameter tooltips say:
  - "This parameter shows the duration enemies are visible after they leave your visibility range. The default value
    is 10 seconds."
  - "...the duration your vehicle is visible to enemies after you leave their view range. The default value is 10 s."
- Both durations are now per-vehicle stats:
  - *Improved Radio Set* lengthens the enemy duration and shortens your own;
  - the radio-operator perk *Jamming* shortens your own;
  - a "Target Designation" mechanic extends it for marked targets.

  HULLDOWN may later want separate `enemySpottedTime` and `ownSpottedTime` modifiers. The default stays 10 s.

**Last-known positions.** After the spot expires, the minimap keeps a faded marker at the last known position.
Long-standing community mods extended this, and the base client now shows it. How long the marker persists was not
confirmed (Low).

**Sources:** [WG support 10222](https://wargaming.net/support/en/products/wot/article/10222/) ·
[WG support (Blitz) 15414](https://wargaming.net/support/en/products/wotb/article/15414/) ·
[HyperX spotting guide](https://ag.hyperxgaming.com/article/5710/world-of-tanks-view-spotting-and-signal-range-guide) ·
[boostroom: spotting mechanics](https://boostroom.com/blog/spotting-mechanics-made-simple-view-range-camo-bushes-proxy-spot) ·
[Steam discussion on assist credit](https://steamcommunity.com/app/1407200/discussions/0/4027970580230660098)

### 8. Sixth Sense and spotted notifications

**Modern behaviour**
- **Since Update 1.18.1 (Oct 2022), Sixth Sense is a built-in "special commander feature".** It is no longer a
  trainable perk: every commander has it from their first battle, including newly recruited ones.
- The alert (lamp icon plus sound) fires **3 s after you become spotted**.
- The *Increased Focus* directive cuts the delay to **2 s**. It has not been sold since 1.18.1; existing stock still
  works.
- There is **no "unspotted" notification**. Players infer their status from the alert timing and the 10 s linger.
  Popular mods add a countdown after the alert.
- Update 2.2 (Feb 2026) added a radio-operator perk that triggers on detection: +2% VR for 5 s (§5). Its name is
  *Threat Search*, and the +2% is unverified (corrected by fact-check).
- 2.4 UI text: Sixth Sense "is a special Commander feature that does not require training and is available to the
  Commander by default". It "is disabled while the Commander is injured". *Signal Interception* (radio operator)
  reduces its activation time. *Increased Focus* makes it "activated 1 s earlier" (added by fact-check).
- Crew-perk churn (1.22.1 interface rework; 1.26 perk overhaul; 2.2 "crew rework complete" with 10 new perks) left
  Sixth Sense built in.

**History:**
- Before 1.18.1, Sixth Sense was a commander perk that worked only at 100% training. It was so mandatory that
  Wargaming made it universal; its "Survival Guide: Playing Without Sixth Sense" article had existed for new players.
- Rationale stated: everyone had to train it first, so it was a tax on new crews.

**Confidence:** High for 3 s / 2 s and built-in status.

**Sources:** [Sixth Sense: A Special Commander Feature (1.18.1)](https://worldoftanks.eu/en/news/general-news/1-18-1-sixth-sense-perk/) ·
[Release Notes 1.18.1](https://worldoftanks.eu/en/content/docs/release_notes/release-notes-1-18-1/) ·
[TAP: Sixth Sense (2022-10-07)](https://thearmoredpatrol.com/2022/10/07/wot-sixth-sense-a-special-commander-feature/) ·
[Update 1.22.1 crew interface rework](https://worldoftanks.com/en/news/general-news/crew-interface-rework/) ·
[Crew Rework Complete (2.2)](https://worldoftanks.asia/en/news/general-news/crew-perks-expansion-2026/)

### 9. Signal range / radio

**Rule as documented**
- Two friendly vehicles "communicate" when their distance is **≤ the sum of their radio ranges**. For example, ranges
  of 300 m and 500 m connect up to 800 m apart.
- Vehicles in communication share everything either of them spots, relayed through chains of allies.
- ~~The radio-operator perk *Signal Boosting* increases signal range (up to +20%).~~ **Corrected by fact-check:** the
  2.4 radio-operator perk list has no *Signal Boosting*. The list is Battle Tempered, Communications Expert,
  Situational Awareness, Jamming, Call for Vengeance, Side By Side, Signal Interception and Threat Search. According
  to the in-game manual, signal range now depends on:
  - the radio module ("Signal Range: up to N m");
  - the radio operator: an injured operator reduces it;
  - radio damage: a destroyed radio "halves your signal range".

**Modern relevance**
- Practically nil in Random Battles. Top radios cover most of a ~1 km map, and team chains connect everyone.
- Wargaming's own changes confirm the de-emphasis:
  - **1.26:** rebalanced lines from Tier VI up have **one radio module, the top one**. Older radios "often did not
    provide a noticeable improvement in vehicle performance".
  - **Rebalance 2.0 (Update 2.0, Sept 2025):** radio and suspension modules were "streamlined", i.e. low-impact
    modules removed.
- We found no evidence that the relay rule was formally deleted. It simply no longer matters.

**Confidence:** Medium. The rule is documented; the practical irrelevance is inferred from Wargaming's module changes
and from map size.

**Sources:** [HyperX guide](https://ag.hyperxgaming.com/article/5710/world-of-tanks-view-spotting-and-signal-range-guide) ·
[Fandom: Radio](https://worldoftanks.fandom.com/wiki/Radio) ·
[Widespread Vehicle Rebalancing in 1.26](https://worldoftanks.eu/en/news/general-news/vehicle-rebalances-1-26/) ·
[Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)

### 10. Smoke, weather, time of day, terrain

**Random Battles**
- There is no smoke consumable.
- Weather and time-of-day map variants are cosmetic only and do not change VR or camo.
- Terrain matters only as hard cover and through the height advantage of ports.
- We found no 2.0–2.2 change that alters this. (Medium-High; nothing surfaced to the contrary.)
- *Special-mode exceptions (added by fact-check, 2.4 UI text):*
  - Map Box **"Local Weather"**: "Vehicles within a local weather zone cannot spot vehicles outside the zone and vice
    versa".
  - Onslaught **"Night Maps"**: "modified spotting mechanics".

**Frontline mode, *Smoke Screen* combat reserve**
- Fires 5 smoke grenades over a 200 × 50 m area that lasts **50 s**. (The counts, area and duration are unverified:
  the UI lists them only as parameters.)
- ~~The smoke blocks enemy view and conceals allies inside.~~ **Corrected by fact-check:** the UI says "Smoke
  conceals **all** vehicles in/behind it". Allies inside get "Inside smoke: concealed", with no VR penalty.
- **Enemies inside** suffer **−30% VR** and **−15% crew skills** (unverified). After leaving, they keep reduced VR and
  crew performance through a **"wind down time"** (added by fact-check).
- Smoke colour shows the owner: grey is allied, dark orange is enemy.
- Steel Hunter (battle royale) has its own smoke abilities. Their values were not researched.

**Tier XI special mechanics (Update 2.0).** These are offence and mobility gimmicks: secondary guns, charge-up accuracy,
rocket boosters, direct drive. None surfaced that alters the spotting rules.

**Confidence:** Medium-High.

**Sources:** [Frontline: What Combat Reserves to Go For](https://worldoftanks.eu/en/news/general-news/frontlines-reserves-guide/) ·
[Frontline Rules & Regulations](https://worldoftanks.asia/en/content/frontline-regulations/) ·
[Update 2.0: Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/)

### 11. Spotting rewards and the scout role

**Modern behaviour**
- **First detection** of each enemy vehicle gives a small flat XP and credit bonus. It is **doubled for SPGs**.
- **Spotting assistance** ("damage upon your spotting")
  - Damage allies deal to a target that *you* currently keep visible gives you a share of the XP and credits.
  - Community description: the spotter gets **50% of what the shooter would earn**, **divided among the spotters**.
  - Credit lapses after the 10 s unseen window (§7).
  - An older mechanic halved the shooter's own reward when firing at targets they did not spot themselves. It may be
    historical and **is not recommended** for us.
- Tracking and stun assistance are separate assisted-damage categories (out of scope here).
- The post-battle screen shows "enemies spotted" and "assisted damage". Light tanks are judged largely on assisted
  damage, by players and by Wargaming's role-oriented missions and medals.

**Confidence:** Medium. The exact split and the current shooter rules were not re-verified.

**Sources:** [Fandom: Battle Mechanics](https://worldoftanks.fandom.com/wiki/Battle_Mechanics) ·
[Steam: assisted damage discussion](https://steamcommunity.com/app/1407200/discussions/0/4027970580230660098)

### 12. Server authority and anti-wallhack

**Modern behaviour**
- Visibility is computed on the server. Clients receive state **only for vehicles their team currently spots**.
  - Allies are always sent.
  - Vehicles spotted by the team but beyond the 564 m draw radius are sent as minimap data only.
- Client mods cannot reveal unspotted enemies; true wallhacks do not exist.
- What clients *can* see through walls is the outline of vehicles that are **already** spotted. Wargaming renders this
  itself.
- Remaining client-side "information" cheats (aim helpers, last-known-position memory) work only with data the client
  has legitimately received.

**Confidence:** High.

**Sources:** [FTR: Cheating in World of Tanks](http://ftr.wot-news.com/2015/01/14/cheating-in-world-of-tanks/) ·
[Update 9.16 visibility article](https://worldoftanks.eu/en/news/general-news/version-916-spotting-improvement/)

### 13. Timeline of spotting-related changes

| Version (date) | Change | Why (if stated) |
|---|---|---|
| 9.12 (2015) | Draw area changed from 1000 m square to 564 m circle | Even spotting in all directions; remove diagonal irregularity |
| 9.16 (2016) | Visibility server code rewritten; spotted vehicles shown faster, especially beyond 300 m | Lower server load; responsiveness |
| 1.0 (Mar 2018) | HD map remaster with re-authored vegetation. No rule change found | Graphics |
| 1.10 (Aug 2020) | Equipment 2.0: Coated Optics 10/11.5%, Binoculars 25/27.5% after 3 s, Camo Net 5/10/15% (+2.5 in slot), specialization slots (percentages other than optics 10% unverified by fact-check) | Equipment depth and choice |
| 1.18.1 (Oct 2022; EU client mirror first shows it 2022-10-12) | Sixth Sense built into every commander (3 s); Increased Focus directive (2 s) removed from sale (removal from sale unverified) | Remove a mandatory perk tax |
| 1.22.1 (2023) | Crew interface rework (UI only) | Usability |
| 1.26 (Aug–Sep 2024; EU client mirror first shows it 2024-09-04) | New perk system: Recon +2% VR / −20% device penalty; Concealment group perk +80% (values unverified by fact-check). Rebalanced lines get one (top) radio from Tier VI | Simplify the crew system; radios had little impact |
| 2.0 (Sept 2025; EU client mirror 2025-09-03) | Tier XI, Rebalance 2.0, radio and suspension modules streamlined | Simplify progression |
| 2.1.1 (announced Dec 2025; live by 2026-01-14 per EU client mirror, corrected by fact-check) | Bond binoculars (Telescopic Observation System) +27.5%, 1.5 s activation | Bond equipment variety |
| 2.2 (late Feb / early Mar 2026; EU client mirror first shows it 2026-03-04) | "Crew rework complete": 10 new perks, including the radio-operator *Threat Search* (VR bonus for 5 s after the Sixth Sense alert) | Situational perks over flat stats |
| May 2026 balance | Per-gun "penalty to camouflage upon fire" values still being tuned (e.g. Husarz) | Balance |
| 2.3 (≈ June 2026), 2.4 (≈ Sept 2026) | Not researched. 2.4.0 is the live client at the research date (added by fact-check) | — |

### 14. Divergent branches (excluded from our model)

- **Lesta (Mir Tankov), forked 2022.** Its spotting changes were not researched; the search budget was exhausted
  (Open question).
- **WoT Blitz and WoT Console / Modern Armor** have different spotting rules and values. Several search hits came from
  them (e.g. Blitz paint bonuses of 2/3/4% by class, and Blitz bush-firing behaviour). We excluded those numbers.

---

## Implementation recommendations for HULLDOWN (Roblox)

These fit `docs/ARCHITECTURE.md`:
- server-authoritative 30 Hz `BattleInstance`;
- tick step 7 runs `SpottingSystem`;
- tick step 9 does per-observer replication;
- pure `Shared` modules plus the `World` adapter;
- config in metres, with `Units.STUDS_PER_METER = 3`.

### R1. `Shared/Config/Spotting.luau` defaults

```lua
-- All distances in metres, times in seconds, factors 0..1. Freeze after construction.
return {
	-- Ranges
	MAX_SPOT_RANGE_M      = 445,   -- WoT parity. 1335 studs (well under Raycast's 15,000-stud limit)
	ENEMY_DRAW_RANGE_M    = 564,   -- WoT parity (9.12 figure; current WoT manual says 565, immaterial): full 3D replication/render radius
	PROXIMITY_RADIUS_M    = 50,    -- WoT parity: spotted regardless of LOS
	FORMULA_FLOOR_M       = 50,    -- the "50" in VR - (VR-50)*camo

	-- Check scheduling (piecewise-linear on 3D distance; staggered by pair hash)
	CHECK_INTERVAL_CURVE  = { {50, 0.10}, {150, 0.50}, {270, 1.00}, {445, 2.00} }, -- WoT anchors (Medium confidence)
	CHECK_INTERVAL_MAX_S  = 1.00,  -- OUR DESIGN CHOICE: clamp WoT's 2.0 s tail (see R10)
	ALTERNATE_PORTS       = false, -- OUR DESIGN CHOICE: test both ports each check (WoT alternates)
	EVENT_CHECK_ON_SHOT   = true,  -- WoT parity
	EVENT_CHECK_ON_STOP   = true,  -- WoT parity
	EVENT_CHECK_ON_SPAWN  = true,
	STOP_SPEED_KMH        = 0.5,   -- OUR DESIGN CHOICE: hull speed below this counts as stopped
	MAX_RAYS_PER_TICK     = 400,   -- perf guard; overflow is deferred, nearest pairs first

	-- Persistence
	SPOT_LINGER_S         = 10,    -- WoT default 10 s (High; confirmed by fact-check). Keep configurable;
	                               -- WoT also lets equipment/perks modify it per vehicle (enemy vs own duration)
	LAST_KNOWN_MARKER_S   = 60,    -- OUR DESIGN CHOICE: faded minimap marker after linger expires

	-- Camouflage
	CAMO_TOTAL_CAP        = 0.90,  -- OUR DESIGN CHOICE (WoT effectively 1.0)
	FOLIAGE_STACK_CAP     = 0.80,  -- community-reported WoT cap
	FOLIAGE_OBSERVER_CLEAR_M = 15, -- WoT 15 m rule (observer side)
	FOLIAGE_SHOOTER_CLEAR_M  = 15, -- WoT 15 m rule (shooter side)
	SHOT_FOLIAGE_PENALTY_S   = 3.0,-- OUR DESIGN CHOICE (WoT duration unpublished)
	SHOT_CAMO_PENALTY_S      = 3.0,-- OUR DESIGN CHOICE: how long gun.camoAtShot applies
	STATIONARY_ARM_S         = 3.0,-- WoT: net/binoculars activate after 3 s hull-stationary

	-- Sixth Sense
	SIXTH_SENSE_DELAY_S   = 3.0,   -- WoT parity (built-in for every commander)
	SIXTH_SENSE_FAST_S    = 2.0,   -- WoT directive value; for a future perk/consumable
	SIXTH_SENSE_LAMP_S    = 10.0,  -- OUR DESIGN CHOICE: lamp + ring shown for the minimum spotted time

	-- Signal / relay
	SIGNAL_RELAY_ENABLED  = false, -- OUR DESIGN CHOICE: team-wide shared vision in standard modes

	-- Vehicles and LOS
	VEHICLES_BLOCK_LOS    = false, -- OUR DESIGN CHOICE (WoT behaviour unconfirmed); wrecks likewise

	-- Smoke (special modes / future consumable)
	SMOKE_BLOCKS_LOS      = true,
	SMOKE_ENEMY_INSIDE_VR_MULT = 0.70, -- Frontline "-30% VR" (value unverified by fact-check; treat as OUR DESIGN CHOICE)
	SMOKE_ENEMY_WINDDOWN_S     = 0,    -- WoT keeps the penalty for a "wind down time" after leaving (duration unknown); 0 = off
}
```

### R2. SpottingSystem algorithm (pure module plus `World` adapter)

```
for each directed pair (observer o, target t), o and t on opposite teams, both alive:
  if now < pair.nextCheck and not pair.forced: continue
  d = |o.hullCenter - t.hullCenter|                         -- 3D, metres
  pair.nextCheck = now + clampInterval(curve(d)) + jitter(pairHash)   -- jitter spreads load across ticks
  if d <= PROXIMITY_RADIUS_M: markSeen(o, t, now); continue
  if d > MAX_SPOT_RANGE_M: continue
  VR    = o.effectiveVR(now)                                 -- R4
  camoB = t.bodyCamo(now)                                    -- base x crew x shot + paint + net (R3)
  if VR - (VR - 50) * min(CAMO_TOTAL_CAP, camoB) < d: continue   -- cheap reject: even with zero foliage, out of range
                                                             -- (corrected by fact-check: must use the capped camo,
                                                             --  otherwise camoB > 0.90 rejects targets that the
                                                             --  R10 cap guarantees are spotted at >= ~90 m)
  for port in o.ports (turret port first):                   -- 2 ports
    for cp in t.checkpoints (turret roof, mantlet, then hull faces):   -- 6 points
      if World:raycast(port, cp, SightLineParams) hits hard cover: continue
      if smokeBlocks(port, cp): continue
      foliage = min(FOLIAGE_STACK_CAP, sum(f.concealment for f on segment(port, cp)
                    if dist(f, port) > FOLIAGE_OBSERVER_CLEAR_M
                       and not (t.firedRecently and dist(f, t) <= FOLIAGE_SHOOTER_CLEAR_M)))
                    -- (fact-check: use the R1 constants, not a literal 15; firedRecently = now - t.lastShotT < SHOT_FOLIAGE_PENALTY_S)
      camo = min(CAMO_TOTAL_CAP, camoB + foliage)
      if d <= min(MAX_SPOT_RANGE_M, VR - (VR - 50) * camo): markSeen(o, t, now); goto nextPair
markSeen(o,t,now): seen[o][t] = now
teamVisible(team, t) = exists o in team: now - seen[o][t] <= SPOT_LINGER_S
on teamVisible transition false->true: emit Spotted(t) to team; schedule SixthSense(t) at now + SIXTH_SENSE_DELAY_S
on transition true->false: emit Unspotted(t); start last-known marker (position at that moment)
```

**Notes**
- `forced` is set on `ShotFired` (for every pair where the shooter is the *target*), on hull stop and on spawn.
- **Hard cover** is checked with one `World:raycast` per (port, checkpoint) and a dedicated collision group. The group
  `SightLine` collides with `MapSolid` and `Terrain` only. Foliage parts and decorative clutter use `CanQuery = false`,
  or a group that does not collide with `SightLine`.
- **Foliage and smoke are analytic**, not engine raycasts:
  - map content exports a list of foliage volumes (spheres or capsules with `concealment`);
  - store them in a 2D uniform grid with 16 m cells;
  - for each ray, walk the grid cells along the segment and run segment-vs-sphere/capsule tests.
  - This is pure Luau (unit-testable in Lune), deterministic, independent of client graphics, and lets felled trees
    update state (a standing capsule becomes a lying capsule with the same concealment).
- The camo used is evaluated **per ray**: the best ray wins. This reproduces WoT exploits such as a bush covering the
  hull but not the turret.
- **Distance** is measured hull-centre to hull-centre. The (port, checkpoint) pair matters only for LOS and foliage.

### R3. Camouflage composition and class defaults (OUR DESIGN CHOICE, WoT-shaped)

```
bodyCamo = baseCamo[stationary|moving] × crewConcealmentMult × shotMult
         + paintBonus + (netArmed and netBonus or 0)
crewConcealmentMult = 1 + 0.80 × concealmentPerkTraining  -- 0..1 crew-wide; mirrors WoT 1.26 "+80%" (WoT value
                                                          -- unverified by fact-check: treat 0.80 as OUR DESIGN CHOICE)
shotMult = gun.camoAtShot if now - lastShotT < SHOT_CAMO_PENALTY_S else 1
"moving" = |hull linear speed| > STOP_SPEED_KMH or hull yaw rate > 2 deg/s; turret traverse alone does not count
netArmed = hull stationary for >= STATIONARY_ARM_S
```

**Class defaults.** Values are the effective camo factor with a trained crew and no perk. They follow the WoT ordering
and the LT moving = stationary rule; the exact WoT numbers are unconfirmed.

| Class | Stationary | Moving | Net bonus | Rationale |
|---|---|---|---|---|
| Light | 0.18 | 0.18 | 0.10 | LT moving = stationary, as in WoT |
| Medium | 0.12 | 0.07 | 0.10 | |
| Heavy | 0.05 | 0.025 | 0.05 | |
| Tank destroyer (turretless) | 0.28 | 0.16 | 0.15 | |
| Tank destroyer (turreted) | 0.18 | 0.11 | 0.15 | |
| SPG / artillery (if added) | 0.10 | 0.05 | 0.05 | |

Further defaults:
- `paintBonus = 0.04` for every class. This is a **flat** value by design (OUR DESIGN CHOICE). WoT PC's camouflage
  and style bonus is **class-dependent**, with exact values unverified, rather than the "+5%" reported earlier
  (corrected by fact-check). We keep it small so that cosmetic monetisation is not pay-for-stealth. Better still,
  **0 in ranked/competitive queues**.
- **Gun after-shot multiplier, by calibre** (OUR DESIGN CHOICE; per-gun overrides allowed in content):
  `camoAtShot = clamp(0.40 − 0.0025 × (calibre_mm − 20), 0.05, 0.40)`, giving 75 mm → 0.26, 105 mm → 0.19,
  120 mm → 0.15 and **≥160 mm → 0.05** (corrected by fact-check: the formula reaches the 0.05 floor at 160 mm, not
  180 mm). Calibres of 20 mm or less get 0.40.
- **Size scaling:** each vehicle may have ±0.03 "silhouette" adjustments in data. Do not derive camo from model
  volume; it is a balance lever.

### R4. View-range composition

```
VR = baseVR × crewFactor(commanderEffectiveSkill)
          × (1 + optics%)            -- coated optics +10% (moving or stationary), OR binoculars +25% once
                                     -- stationary >= 3 s; never both (OUR DESIGN CHOICE: WoT stacking behaviour
                                     -- is unverified; corrected by fact-check, was "WoT parity")
          × (1 + perk%)              -- Recon +2%, Threat Search +2% for 5 s after own Sixth Sense alert
                                     -- (WoT has these perks; the % values are unverified -> OUR DESIGN CHOICE)
          × damageMult               -- observation devices damaged: 0.60 (OUR DESIGN CHOICE; WoT value unconfirmed);
                                     -- commander KO handled via crewFactor
          × smokeMult                -- 0.70 when inside enemy smoke
crewFactor(s) = 0.57 + 0.0043 × s    -- s in % (100 → 1.00); community-recalled curve, unverified -> OUR DESIGN CHOICE
```

- Base VR ranges per class (OUR DESIGN CHOICE):
  - LT 400–460
  - MT 370–410
  - HT 340–390
  - TD 330–390
  - SPG 300–340
- A spec-slot style bonus (+15% of the item's effect) is optional and should only be added with an equipment-slot
  system.

### R5. Map-content rules for foliage and cover

- Foliage types (OUR DESIGN CHOICE, WoT-shaped):

| Type | Concealment |
|---|---|
| Light bush | 0.25 |
| Dense bush | 0.50 |
| Hedgerow segment | 0.40 |
| Tree crown | 0.30 |
| Felled tree | 0.30 |
| Very dense thicket | 0.60 (never above 0.64) |

  Tree trunks are not concealment and not hard cover. Both are cheap to leave out.
- Every foliage visual must have a matching data volume. A lint test in content validation fails the build if a
  foliage-tagged model has no volume.
- Destructible hard cover (fences, sheds, walls) is in `MapSolid` until destroyed, then removed from the server
  collision group immediately.
- Client: fade foliage within 15 m of the local vehicle's ports with `LocalTransparencyModifier`. This mirrors the WoT
  see-through rule visually. Also show a small "bush cover" indicator when the local vehicle has ≥ 0.25 foliage
  between itself and the nearest known enemy (optional readability aid).

### R6. Replication and anti-wallhack on Roblox

Already mandated by ARCHITECTURE §1 and §6.1:
- Enemies are sent only while `teamVisible`. **Full state** goes only to observers within `ENEMY_DRAW_RANGE_M` of the
  receiving player. Others get **minimap-only** records at 2 Hz: quantised XZ plus heading.
- Spotted and Unspotted go over the reliable event stream. Positions go over `UnreliableRemoteEvent` snapshots, which
  have a 1000-byte payload limit (confirmed by fact-check: larger events are dropped), so pack with `buffer`.
  ARCHITECTURE §5.2 budgets ≤ 900 bytes per packet, which leaves headroom.
- Do **not** place server vehicle hitboxes in `Workspace`. Everything there replicates (StreamingEnabled only filters
  by distance), so it would leak positions. `ArmorGeometry` is analytic per the architecture, which avoids this.
- Client vehicle models are created locally on Spotted and pooled on Unspotted. They fade out over 0.3 s; do not pop.
- The client never receives camo, foliage or VR values for enemies. Only allies' and the player's own values are sent,
  for the UI.

### R7. Sixth Sense and readability UI

- Sixth Sense lamp:
  - shown `SIXTH_SENSE_DELAY_S` (3 s) after the owner's vehicle becomes team-visible to the enemy;
  - plays a distinct sound;
  - draws a 10 s ring labelled as a minimum. There is no "unspotted" signal (WoT parity; preserves uncertainty).
  - Optional WoT parity, if crew injuries are modelled: suppress the lamp while the commander is injured, as WoT does
    (added by fact-check).
- Enemy markers: name, class icon and HP bar over every spotted enemy.
- Silhouettes behind obstacles: a `Highlight` with `DepthMode = Occluded` and an outline only, for spotted enemies
  behind cover. The client limit is 255 Highlights, which is ample for 15 enemies.
- Minimap:
  - live icons for spotted enemies;
  - faded last-known markers for 60 s;
  - your own VR circle, the 445 m circle and the 564 m circle, all toggleable (WoT-standard circles).
- Team panel: an "eye" icon next to each enemy that is currently spotted.

### R8. Reward hooks (handed to the Economy research)

- Per enemy:
  - `firstSpot` gives flat XP and credits to the first spotter, ×2 for SPGs;
  - the `enemiesSpotted` count is incremented.
- On every damage event against target `t` by shooter `s`, find `spotters = { o in s.team, o ≠ s, now − seen[o][t] ≤ SPOT_LINGER_S }`:
  - each spotter's `assistedSpottingDamage` stat gets `+damage` (full amount, for display);
  - the reward pool is `0.5 × damageReward(s, t)`, split equally among the spotters (community WoT model);
  - the shooter keeps 100% of their own reward (OUR DESIGN CHOICE; avoid the old WoT halving).
- The damage ledger already exists in `VehicleEntity` (ARCHITECTURE §6.1). Store `seen[o][t]` timestamps there for
  attribution.

### R9. Performance budget (estimate; profile in Studio)

- With 15v15 there are 2 × 15 × 15 = **450 directed pairs**.
- With the interval curve clamped at 1.0 s, the average is about 0.6–0.8 s, i.e. **≈ 600–750 pair checks/s**.
  - Cheap rejects (formula range, proximity) remove a large share.
  - The surviving checks cost 1–12 rays, about 3 with early exit, so typically **≈ 1.5–2.5k rays/s** and at worst
    ≈ 9k rays/s.
- At 30 Hz that is **≈ 50–90 rays per tick**, with `MAX_RAYS_PER_TICK = 400` as the safety cap.
- `WorldRoot:Raycast` is marked thread-**Safe**, so if profiling shows the sim ticks are over budget, spotting can move
  to Parallel Luau (an Actor with `task.desynchronize`) later.
- Foliage tests are analytic: grid lookup plus about 10 sphere tests per ray.

### R10. Deliberate deviations from WoT

| WoT | HULLDOWN | Reason |
|---|---|---|
| Long-range checks every 2.0 s, ports alternate (WoT values Medium confidence; downgraded by fact-check) | Max 1.0 s, both ports per check | WoT's interval was a 2010-era server optimisation. Roblox adds ~100–200 ms client latency, and late pop-in reads as a bug to Roblox players. The cost is affordable at our player counts (R9) |
| Total camo up to 1.0 (spotted only at 50 m) | Cap at 0.90 (a 445 VR observer always spots at ≥ ~90 m) | Removes the "invisible TD" frustration while keeping bush play strong; improves readability on mobile |
| Foliage via engine geometry | Analytic foliage volumes authored with the map | Deterministic, testable, independent of client graphics quality, cheap |
| After-shot penalty duration unpublished | Explicit 3 s for camoAtShot and foliage loss | Needs a number; 3 s exceeds the 1 s max check interval, so a shot is always "seen" by at least one scheduled check plus the forced shot check |
| Radio relay exists but is irrelevant | Off (team-wide sharing); config flag for special modes | Removes a dead stat; simpler UI |
| Paint/style bonus is class-dependent; values unverified (corrected by fact-check; was "about +5%") | Flat +4%, 0 in ranked | Fairness and simplicity of cosmetics |
| Shooter penalised when firing at others' spots (historic) | No penalty; spotters share a 50% pool | Clear incentives for teamwork |
| No weather effects | Same, plus a per-map-variant `visibilityMult` hook (default 1.0) for event modes | Readability first; extensibility |
| Maps ~1 km, 445/564 m | Same metres; if a map is smaller, scale `MAX_SPOT_RANGE_M` and `ENEMY_DRAW_RANGE_M` by `map.spottingScale` (keep 50 m and 15 m fixed) | Roblox/mobile maps may be smaller (1 km = 3000 studs at 3 studs/m). The vehicle-scale constants should not scale |

### R11. Unit tests to write (`tests/Unit/Shared/Spotting/*.spec.luau`)

- **Formula:** reproduce every row of the §3 worked-example table, including the clamp to 445 and both cap variants.
- **Cap vs cheap reject** (added by fact-check): a VR 445 observer with a clear LOS spots a target at 85 m whose body
  camo `camoB` is 0.95. With the 0.90 cap the spot distance is 89.5 m, so the R2 cheap reject must not drop this pair.
- **Gun after-shot curve:** 75 mm → 0.2625, 160 mm → 0.05, 200 mm → 0.05, 20 mm → 0.40.
- **Interval curve:**

| Distance | Interval |
|---|---|
| 30 m | 0.10 s |
| 100 m | 0.30 s |
| 200 m | 0.708 s |
| 350 m | 1.457 s raw, 1.0 s clamped |
| 445 m | 2.0 s raw, 1.0 s clamped |

- **Proximity:** a target at 49 m behind a solid wall is spotted; at 51 m it is not.
- **15 m rule:**
  - an observer 10 m behind a bush sees through it;
  - at 20 m the bush adds concealment;
  - a shooter 10 m behind a bush loses that bush's value for 3 s after firing, and keeps it at 20 m.
- **Stacking:** two dense bushes give 0.80, not 1.0. A bush on the hull ray but not the turret ray means the turret ray
  decides.
- **Linger:** the target is visible until 10.0 s after the last success, then Unspotted fires once and a last-known
  marker is created.
- **Sixth Sense:**
  - the alert fires exactly 3 s after the first team-visible transition;
  - no new alert while visibility continues;
  - a new alert after an unspot followed by a re-spot.
- **Equipment:**
  - binoculars activate only after 3 s stationary and drop on movement;
  - optics and binoculars never stack (our design choice; WoT behaviour unverified);
  - the net arms after 3 s.
- **Rewards:** 2 spotters plus 1 shooter: each spotter gets 25% of the shooter's damage reward; the shooter gets 100%.

---

## Open questions / uncertain items

1. ~~**Linger duration (10 s).**~~ **Resolved by fact-check.** The 2.4 PC client's parameter tooltips state "The
   default value is 10 seconds", both for enemies after they leave your range and for your own vehicle. Equipment and
   perks modify it per vehicle. Keep `SPOT_LINGER_S` configurable.
2. **Duration of the after-shot camo and foliage penalty.** Not published in any source we could reach. We use 3 s.
3. **Exact checkpoint and port positions.** Wargaming does not publish them. Our layout (turret roof, mantlet,
   4 hull-face centres at 80% hull height, inset 0.1 m) is a design choice. *Fact-check:* the community debug mod
   (§2 note) shows WoT's layout:
   - points: gun-axis point, front/rear hull-face centres, and left/right face centres at gun-axis height;
   - ports: a static port at the top of the vehicle and a dynamic port at the gun axis.

   Our layout is close to this, and the checkpoint count (5–7 vs 6) is unconfirmed.
4. **Do vehicles or wrecks block spotting rays in WoT?** Unconfirmed. We default to no.
5. **Bush values and stack cap** (25/50/64%, 80%) are community-reported, not official. Our foliage table is a design
   choice.
6. **Paint bonus on PC today:** partly resolved by fact-check. It is **class-dependent**, according to 2.4 UI text.
   The per-class percentages are still unknown. HULLDOWN uses a flat 0.04 by design.
7. **Concealment perk (+80%):** is it applied to the same base as the old +75% Camouflage skill? Does it multiply only
   the vehicle base (as the community formula implies) or the total? *Fact-check:* the 2.4 UI shows the value only
   as a placeholder, so 80% itself is unverified.
8. **Crew-skill → VR curve** (`0.57 + 0.0043·s`) is recalled community knowledge. It was not verified this session.
9. **Damaged observation device penalty** (commonly said to be −50%) was not verified. We chose 0.60× VR.
10. **Signal relay:** is it still computed at all in PC Random Battles after 2.0? This does not matter for us because
    relay is off, but it is worth confirming for completeness.
11. **Lesta / Mir Tankov divergence** after 2022 was not researched.
12. **Spotting-assist reward split** (50% of the shooter's reward ÷ spotters) and the first-spot bonus amounts are
    community descriptions without current official numbers. The Economy research should set our own numbers.
13. **Roblox client render distance on low graphics quality.** Verify that client-spawned enemy models and markers at
    up to 564 m (≈1692 studs) remain visible on low-end mobile. If not, rely on billboard markers beyond the device's
    render distance; never on the mesh.
14. **Check-interval anchors** (0.1/0.5/1/2 s at 50/150/270/445 m) were not confirmed independently by the fact-check
    (added by fact-check). They do not block HULLDOWN, which clamps at 1.0 s anyway.
15. **Do Coated Optics and Binocular Telescope stack in WoT?** Unverified (added by fact-check). HULLDOWN's "never
    both" is a design choice.
16. **Equipment and perk percentages**: binoculars 25/27.5%, optics 11.5% in slot, camo net 5/10/15% (+slot), Recon
    +2%/−20%, Threat Search +2%. The 2.4 UI shows them only as placeholders (added by fact-check). They need a
    reachable official source, or they should be treated as design values.
17. **Frontline Smoke Screen numbers** (5 grenades, 200×50 m, 50 s, −30% VR, −15% crew, wind-down duration) are
    unverified (added by fact-check).

---

## Verification log

Fact-check pass, 2026-10-05.

**Evidence types.**
- **[UI]**: player-visible text of the WoT **2.4.0.2 EU** client: the in-game manual, tooltips, and equipment and perk
  descriptions. It was read from the public mirror
  [izeberg/wot-src](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/version.xml).
  Only localisation strings were read; no numeric game-data files were used. Where the UI shows a number only as a
  placeholder (e.g. `%(maskingFactor)s`), the number stays **Unverified**.
- **[Mirror dates]**: the dates when that mirror first published each client version. They are a proxy for EU release
  dates.
- **[Mod]**: the community debug mod
  [wotstat-debug-utils](https://github.com/wotstat/wotstat-debug-utils/blob/main/README_EN.md).
- **[KoWiki]**: a Korean wiki dump from about 2015 that predates 9.12:
  [equipment page](https://github.com/forkwikiman/enha_monimarkup/blob/4f42347f38d7bc190acc1517637bc4d57b172ed3/%EC%9B%94%EB%93%9C%20%EC%98%A4%EB%B8%8C%20%ED%83%B1%ED%81%AC/%EC%9E%A5%EB%B9%84%ED%92%88.wiki)
  and
  [crew page](https://github.com/forkwikiman/enha_monimarkup/blob/4f42347f38d7bc190acc1517637bc4d57b172ed3/%EC%9B%94%EB%93%9C%20%EC%98%A4%EB%B8%8C%20%ED%83%B1%ED%81%AC/%EC%8A%B9%EB%AC%B4%EC%9B%90.wiki).
- **[Roblox]**: the official [Roblox/creator-docs](https://github.com/Roblox/creator-docs) repository.

**Limits of this pass.** WebSearch was unavailable because the session budget was exhausted. WebFetch was blocked for
worldoftanks.\*, wargaming.net, fandom, wotlytics, levvvel, boostroom, thearmoredpatrol and tanks.gg.

UI files cited below, all under `sources/res/text/lc_messages/` at commit `088b9cc`:
[manual.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/manual.po) ·
[menu.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/menu.po) ·
[artefacts.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/artefacts.po) ·
[crew_perks.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/crew_perks.po) ·
[tank_setup.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/tank_setup.po) ·
[vehicle_customization.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/vehicle_customization.po) ·
[tips.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/tips.po) ·
[ingame_help.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/ingame_help.po) ·
[epic_battle.po](https://github.com/izeberg/wot-src/blob/088b9cc0e9b6d4c890a5cbfa1147216bf6fcece9/sources/res/text/lc_messages/epic_battle.po)

### Factual claims

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | `spotDist = min(445, VR − (VR−50)·camo)`; VR is not clamped before the formula | **Confirmed** | [KoWiki] worked examples (VR 500 → camo < 12%, VR 550 → camo < 21% at 445 m) match this formula, not `VR·(1−camo)`. [UI] tank_setup.po: "to view range (up to 445 m)—increasing the parameter over 445 m allows for more effective spotting of enemies" |
| 2 | Maximum spotting range is 445 m | **Confirmed** | [UI] manual.po ch.5 lesson 11: "445 meters is the maximum value". [UI] artefacts.po: binocular texts say "(up to 445 m)". [KoWiki] |
| 3 | Proximity spotting within 50 m ignores LOS | **Confirmed** | [UI] manual.po ch.5 lesson 13: "You always spot enemy vehicles within 50 meters, regardless of cover or obstacles". The minimap's "smallest circle is the distance where enemies are detected, regardless of concealment" |
| 4 | Draw/render radius is a 564 m circle | **Corrected** (minor): the current in-game manual says **565 m**. The 564 m figure (from 9.12) is equivalent. The 9.12 version itself was not checked again | [UI] manual.po ch.5 lesson 12: "The value of this parameter is always 565 meters". [KoWiki] M48 page confirms the pre-change 500 m square |
| 5 | 2 view ports and 6 visibility checkpoints | **Unverified** (2 ports supported; the count of 6 is not). Downgraded to Medium | [Mod] README: 5 bounding points plus 2 view/bounding points (a static port at the top of the bounding box and a dynamic port at the gun axis). Ports "coincide with and overlap the visibility checkpoints" |
| 6 | Check intervals of 0.1/0.5/1/2 s at 50/150/270/445 m; event checks on fire and stop | **Unverified**. Downgraded to Medium | No independent source was reachable. Only the original researcher's search summary of WG support article 10222 supports it |
| 7 | Spotted status lingers 10 s after LOS is lost | **Confirmed**. Upgraded to High; now a modifiable per-vehicle stat | [UI] menu.po `extraParams/name/vehicleEnemySpottingTime`: "...duration enemies are visible after they leave your visibility range. The default value is 10 seconds". `vehicleOwnSpottingTime`: "...The default value is 10 s". artefacts.po: *Improved Radio Set*. crew_perks.po: *Jamming* |
| 8 | Sixth Sense is built in, alerts after 3 s; *Increased Focus* gives 2 s | **Confirmed**. Built in since 1.18.1 is consistent with mirror dates; whether the directive is still sold is unverified | [UI] artefacts.po: "Activates 3 s after your vehicle is spotted"; *Increased Focus*: "Sixth Sense is activated 1 s earlier". crew_perks.po: "does not require training and is available to the Commander by default". [Mirror dates] [1.18.1.0, 2022-10-12](https://github.com/izeberg/wot-src/commit/ea6b06bca48e577af2323ffea375851a1b65876e) |
| 9 | 15 m rule: firing removes the concealment of foliage within 15 m; foliage within 15 m of the observer is see-through | **Confirmed** | [UI] manual.po ch.6 lesson 19: "Firing removes all vehicle concealment bonuses within a 15-meter radius. Make sure your vehicle is 15 meters away if you want to fire from behind bushes". [KoWiki] equipment page: bushes beyond 15 m are drawn opaque and block your own view. [UI] tips.po: fallen trees conceal; trees and bushes do not block shells |
| 10 | Per-bush values of 25/50% (≤64%) and an 80% foliage stack cap | **Unverified** | Nothing reachable. [UI] only says vegetation "except grass" conceals and distinguishes "isolated and grouped foliage" (menu.po `demaskFoliageFactor`) |
| 11 | Camouflage paint gives about +5%, possibly flat for all classes | **Corrected**: it is class-dependent on PC. Seasonal camouflage applies on the matching map type; styles apply on all map types. Exact values are unknown | [UI] vehicle_customization.po: "Bonus to concealment depending on the vehicle type when applying the camouflage to a vehicle's hull" and "...depending on the vehicle type on all map types" |
| 12 | Base camo values are not shown in-game | **Corrected**: the client shows them | [UI] menu.po: "Concealment of Moving/Stationary Vehicle (%)", `vehicleInvisibilityAfterShot` "the concealment after firing" |
| 13 | Binoculars and camo net activate after 3 s stationary; Coated Optics +10%; Telescopic Observation System +27.5%, active after 1.5 s | **Confirmed** | [UI] artefacts.po: `stereoscope/battleDescr` "3 s after it stops", `camouflageNet/battleDescr` "3 s after it stops", Experimental Optics text "Coated Optics (+10% to view range)", `deluxeStereoscope` "Telescopic Observation System ... +27.5% ... activates 1.5 seconds after the vehicle stops moving" |
| 14 | Improved/"Experimental" Optics +12.5% | **Corrected** to **+13.5%** (bond item *Experimental Optics*) | [UI] artefacts.po `deluxCoatedOptics`: "An improved version of Coated Optics (+10% to view range) that provides a stronger effect: +13.5% to view range"; `deluxCoatedOptics/name` = "Experimental Optics" |
| 15 | Percentages: binoculars 25/27.5%; optics 11.5% in slot; camo net 5/10/15% (+slot); Concealment perk +80%; Recon +2% / −20%; Threat Search +2% | **Unverified** | [UI] these appear only as placeholders (`%(maskingFactor)s`, `%(circularVisionRadius)s`, `%(vehicleCircularVisionRadius)s`). The perks and their effects exist (crew_perks.po) |
| 16 | Radio-operator perks: "Threat Detection/Threat Search" (2.2); *Situational Awareness* is legacy; *Signal Boosting* +20% signal range | **Corrected**. The name is ***Threat Search*** ("for 5 s after receiving the Sixth Sense alert"). *Situational Awareness* is a **current** perk. *Signal Boosting* is **not** in the 2.4 perk list. *Jamming* and *Signal Interception* were added | [UI] crew_perks.po: radio-operator perks are Battle Tempered, Communications Expert, Situational Awareness, Jamming, Call for Vengeance, Side By Side, Signal Interception, Threat Search. manual.po: a destroyed radio "halves your signal range" |
| 17 | Frontline *Smoke Screen*: blocks enemy view and conceals allies inside; −30% VR and −15% crew for enemies inside; 5 grenades, 200×50 m, 50 s | **Corrected** (qualitative): it "conceals **all** vehicles inside and behind the smoke", and enemies keep the penalty during a "wind down time" after leaving. The numbers are unverified | [UI] artefacts.po `smoke/longDescr` and `smoke/shortDescr`; epic_battle.po `statusNotificationTimers/smoke/*` ("Inside smoke: concealed.", "Wind down time. View range and crew performance decreased."); the parameters are listed without values |
| 18 | "Random Battles have no weather/time-of-day effect"; special modes are smoke-only | **Corrected** (scope): two special modes change spotting. The Random Battles statement itself was not contradicted | [UI] ingame_help.po / tips.po: Map Box "Local Weather" zones ("cannot spot vehicles outside the zone and vice versa"); Onslaught "Night Maps ... modified spotting mechanics" |
| 19 | Current state is Updates 2.0 → 2.2; 2.1.1 shipped in Dec 2025; 2.2 on 25 Feb 2026 | **Corrected**: **2.4.0** is live (2.3 ≈ June 2026, 2.4 ≈ Sept 2026). 2.1.1 went live between 2025-12-18 and 2026-01-14 (it was *announced* in Dec 2025). The 2.2 date fits the window (2.1.1 still live on 02-19; 2.2 seen on 03-04). The dates for 1.26 (Sept 2024) and 2.0 (Sept 2025) are consistent | [Mirror dates] [2.1.0.2 on 2025-12-18](https://github.com/izeberg/wot-src/commit/9198073bded3c77482df5596913c8be06e1ac999) · [2.1.1.0 on 2026-01-14](https://github.com/izeberg/wot-src/commit/a084d0315413f5cac40b95f4e62f277e45d65188) · [2.1.1.2 on 2026-02-19](https://github.com/izeberg/wot-src/commit/8e2ae480022e90ccb991fa783691f26e618a1243) · [2.2.0.0 on 2026-03-04](https://github.com/izeberg/wot-src/commit/dff0079d804aaaa5a56db572516f71703fb37242) · [2.3.0.0 on 2026-06-03](https://github.com/izeberg/wot-src/commit/4f41abadabac913f7979d3beda0799e8f35b4ec4) · [2.4.0.0 on 2026-09-02](https://github.com/izeberg/wot-src/commit/ece6441c85a6a03068cca1614f90d36f6c18da1e) · [1.26.0.0 on 2024-09-04](https://github.com/izeberg/wot-src/commit/76bd41ded16ac0c22997e94e0b497150ab5e101c) · [2.0.0.0 on 2025-09-03](https://github.com/izeberg/wot-src/commit/7fac5e1a2cbca4aaf9b35e851786402d66c91059) |
| 20 | Roblox: Raycast ray length up to 15,000 studs and `Raycast` is thread-Safe; `UnreliableRemoteEvent` payload ≤ 1000 bytes (larger is dropped); 255 Highlights on the client | **Confirmed** | [Roblox] [WorldRoot.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/WorldRoot.yaml) ("The maximum length of the direction vector is 15,000 studs"; thread_safety: Safe) · [UnreliableRemoteEvent.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UnreliableRemoteEvent.yaml) ("Events with payloads larger than 1000 bytes are dropped") · [Highlight.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Highlight.yaml) ("255 simultaneous Highlight instances"; disabled ones still count) |

**Tally (factual claims):** 20 checked.
- 8 confirmed: #1, 2, 3, 7, 8, 9, 13, 20.
- 8 corrected: #4, 11, 12, 14, 16, 17, 18, 19.
- 4 unverified: #5, 6, 10, 15.

In addition, 10 arithmetic and consistency items in the recommendations were checked: 3 confirmed and 7 fixed.

### Arithmetic and internal consistency of the recommendations

| Item | Verdict | Note |
|---|---|---|
| §3 worked-example table (397.6, 306.5, 81.5/95.0, 445 capped, 255.0), π·564² ≈ 0.999 km², 445 VR at camo 0.90 → 89.5 m | **Confirmed** | Recomputed |
| R11 interval curve (100 m → 0.30 s, 200 m → 0.708 s, 350 m → 1.457 s) and R9 budget (450 pairs, 600–750 checks/s, ≈ 50–90 rays/tick, worst case ≈ 9k rays/s) | **Confirmed** | Recomputed |
| R2 cheap reject used uncapped `camoB` | **Corrected** | It contradicted R10's "always spots at ≥ ~90 m" whenever `camoB > 0.90`. It now uses `min(CAMO_TOTAL_CAP, camoB)`, and an R11 test was added |
| R2 foliage test used a literal `15` | **Corrected** | It now uses `FOLIAGE_OBSERVER_CLEAR_M` / `FOLIAGE_SHOOTER_CLEAR_M` from R1, and `firedRecently` is defined with `SHOT_FOLIAGE_PENALTY_S` |
| R3 `camoAtShot` "≥180 mm → 0.05" | **Corrected** | The clamp floor is reached at 160 mm. An R11 test was added |
| R1 `SPOT_LINGER_S` "Medium, playtest 6–10" | **Corrected** | WoT's default of 10 s is confirmed; the comment was updated |
| R3/R10 paint "smaller than WoT's +5%" | **Corrected** | WoT's bonus is class-dependent; the flat 0.04 is kept as a design choice |
| R4 "never both (WoT parity)" for optics + binoculars, and perk percentages | **Corrected** | Relabelled OUR DESIGN CHOICE, because the WoT behaviour and values are unverified |
| R1 smoke multiplier "Frontline parity" | **Corrected** | Relabelled unverified. An optional `SMOKE_ENEMY_WINDDOWN_S` (default 0) mirrors WoT's wind-down |
| R6 1000-byte limit vs ARCHITECTURE §5.2 "≤ 900 bytes" | **Confirmed** (consistent) | 900 is a budget under the 1000-byte engine limit. A note was added |
