# Ballistics, Armor, Penetration, Damage, Modules, Crew, Aiming and Reload: World of Tanks reference research for HULLDOWN

Research date: 2026-10-05. Scope: World of Tanks PC (Wargaming EU/NA/Asia). Lesta's *Mir Tankov* fork was not analysed (see Open questions).
Method: the egress proxy blocked WoT/Wargaming/fandom/tanks.gg/Reddit and most community sites. Evidence therefore comes mainly from web-search result summaries of official pages (patch notes, news, support articles, official wiki) and reputable community analysis. The session's web-search budget ran out partway through. Items marked **(recollection)** come from the author's prior knowledge of the official wiki and community material, and could not be re-verified in this session. Every number that is not backed by a source is labelled **OUR DESIGN CHOICE**. No datamined or extracted client files were used.

Fact-check pass (2026-10-05): see the **Verification log** at the end. Web search was exhausted and almost every web host was blocked, so the fact-check used Wargaming's public Tankopedia API snapshot mirrored on GitHub (2017, the same kind of source doc 05 uses), open-source community code (BlitzKit for WoT Blitz, tanktionary), the local Roblox creator-docs, arithmetic, and cross-checks with sibling research docs. A public mirror of WoT client sources exists on GitHub; it was deliberately **not** consulted, per the team's no-datamined-data policy. Claims the fact-check could not re-verify were downgraded from High to Medium.

Confidence key: **High** means several official or consistent sources agree. **Medium** means one good source, or several secondary sources. **Low** means recollection only, or conflicting sources.

---

## Summary

1. **Shell families.** WoT uses five shell mechanics: AP, APCR (which also covers APDS), HEAT, HE and HESH. "Premium" shells are not a separate mechanic. They are one of these families with better penetration, usually the **same alpha as standard AP**. HE has the highest alpha, typically **about 1.33x the AP alpha** of the same gun, with a range of **about 1.2 to 1.6x** (corrected by fact-check; e.g. many 75 mm guns are 110/175 = 1.59x). HE penetration is about **caliber / 2** in mm. (Medium for the family list; the alpha and pen ratios are confirmed against WG's public API.)
2. **Normalization.** AP turns **5°** toward the plate normal and APCR **2°**. HEAT, HE and HESH get **0°**. (Medium after fact-check: not independently re-verified; one independent secondary doc agrees.)
3. **Two-caliber rule.** If an AP or APCR shell's caliber is more than **2x the nominal plate thickness**, normalization is boosted to `n × 1.4 × caliber / (2 × T)`. Sources disagree on whether the divisor is `2T` or `T` (see 2.2). An open-source WoT Blitz tool implements `/(2T)`. (Medium)
4. **Three-caliber rule.** If an AP or APCR shell's caliber is more than **3x the nominal thickness**, it cannot ricochet at any angle. HEAT lost the 3-caliber rule in 2013. HE and HESH never ricochet. (Medium after fact-check: the strict `caliber > 3T` test is corroborated by a WoT Blitz tool; PC was not re-verified.)
5. **Auto-ricochet angles.** AP and APCR ricochet above **70°**, measured from the normal. HEAT ricochets above **85°**. HEAT ricochet was introduced at **80°** in 0.8.6 (2013) and the current documented value is 85°. (Medium after fact-check: not independently re-verified. One secondary source dates the 85° value to 0.8.9.)
6. **Ricochets continue flying** (since 9.3, Sept 2014). The shell flies on and can hit another plate or another vehicle. Only one ricochet is allowed; a second one deletes the shell. Per the 9.3 explainer, AP and APCR lose 25% of base penetration after a ricochet and HEAT keeps its penetration. (Low after fact-check: the 25% loss and the one-ricochet cap could not be re-verified, and one secondary source claims later versions keep full penetration after a ricochet.)
7. **Effective thickness** is `T_eff = T / cos(max(0, θ − n))`. A plate is penetrated when the rolled penetration is at least `T_eff`. Spaced plates subtract their own `T_eff` from the penetration that remains. (High)
8. **RNG.** Penetration and damage both roll **±25% around the mean**, reportedly using a normal distribution truncated at ±25%. The standard deviation has not been published. Wargaming experimented with reduced RNG on Console in 2019. No mode-specific RNG was found on PC. (High for the ±25% bounds: confirmed against all 2,816 shell entries in WG's public API. Medium-Low for the normal shape (corrected by fact-check): it was not re-verified, and one secondary source models it as uniform.)
9. **Penetration loss over distance.** Only **AP and APCR** lose penetration with distance. The loss is linear, starts beyond about 100 m and continues to about 500 m. APCR loses much more than AP. HEAT, HE and HESH lose **nothing** with distance. (Medium; exact per-gun drop values were not verifiable.)
10. **HEAT after a plate.** After HEAT penetrates any plate, including spaced armor and tracks, it loses **about 5% penetration per 10 cm** of travel. That is roughly 50% per metre of air gap. This rule was introduced in 0.8.6. (Medium)
11. **HE rework.** The **Update 1.13 (June 2021) HE rework is live**. It is not the 2020 Sandbox version. The rules are:
    - HE keeps a penetration stat.
    - On a non-penetration, damage is computed **at the impact point** and depends on the **nominal** armor there.
    - HE can pass through screens, tracks, wheels and external modules, losing **3x that plate's thickness** in penetration.
    - It loses **1x** the thickness of destructible objects.
    - Spall inside the hull (radius equal to the old burst radius) damages modules and crew.
    - The Sandbox "alternative HE" and the "no penetration stat" HE were **not** released. (Medium after fact-check: no primary source was reachable to re-verify.)
12. **HE splash formula.** The long-standing community formula is `0.5·D·(1 − d/R) − 1.1·T·K_spall`. Since 1.13, a direct hit uses d ≈ 0 and T = nominal armor at the impact point. Wargaming states that HE that reaches the armor "will deal damage". (Medium)
13. **Modules.** Each module has HP, a *damaged* state (yellow, degraded) and a *destroyed* state (red, non-functional). The crew field-repairs a destroyed module back to *damaged*. A repair kit restores it fully. A destroyed ammo rack means the vehicle **detonates**. A destroyed fuel tank means **fire**. Engine hits roll a fire chance of **about 10 to 20%**: 20% for gasoline engines and 10–15% for diesels (confirmed against WG's public API). (High for the states and the fire chances, Medium for the other numbers)
14. **Post-penetration path.** After penetrating, a shell travels **up to 10 calibers, and at least 0.5 m**, inside the vehicle. It damages each module and crew member it passes through, each with a per-module hit chance. (Medium)
15. **Crew injuries.** Any crew member can be injured. Effects: commander gives a view-range penalty and the 10% commander bonus is lost; driver affects mobility; gunner affects aim time, dispersion and turret traverse; loader affects reload; radio operator affects signal range. Sources conflict on whether an injured crew member drops to **50%** or **0%** skill. **Since Update 1.26 (2024)**, the small repair and first-aid kits fix **all** modules and crew. Large kits and the Automatic Fire Extinguisher have a **60 s** cooldown (previously 90 s). (Medium)
16. **Aiming.** Dispersion is the reticle radius in metres at **100 m** and scales linearly with distance. Shells are normally distributed with the **reticle edge at 2σ**; this changed from 1.3σ in **0.8.6 (2013)**. The published edge percentages (19.4% at 1.3σ, 4.6% at 2σ) are one-dimensional tail probabilities. They describe a normal **radial miss distance**, not an isotropic 2D normal, which would put 13.5% of shots beyond 2σ (corrected by fact-check; see 8.1). Aim time is the time for the reticle to shrink by a factor of **e (~2.72, "about one third")**. Bloom sources are movement, hull traverse, turret traverse, shooting and a damaged gun. (Medium for 2σ after fact-check, because the 0.8.6 article could not be re-accessed. Medium for the rest.)
17. **Reload and crew skill.** Reload scales with crew skill as `base × 0.875 / (0.00375·L + 0.5)`, which gives exactly 1.0 at L = 100%. Multiple loaders use the average skill. Other weapon types are autoloader (magazine), autoreloader (per-shell timers) and dual-gun (single shots or a charged volley). (High for the formula, which an independent community tool implements identically.)
18. **HULLDOWN recommendation.** Reproduce the WoT armor pipeline nearly verbatim, because it is the core skill expression. Then deviate in five places:
    - simpler and more readable HE (direct-hit formula plus a guaranteed minimum on a direct hit);
    - an exposed σ (σ = R/2 on the radial miss distance, re-roll outside 2σ);
    - shell gravity and velocity scaled for Roblox engagement ranges;
    - a capped ricochet chain (one ricochet, 25% penetration loss). This follows the 2014 9.3 explainer; WoT's current rule is unverified, so treat it as our choice (corrected by fact-check);
    - a fully specified, original fire, ramming and fall-damage model, since WoT does not publish its own.

---

## Detailed findings

### 1. Shell types and their relationships

#### 1.1 Modern behavior

| Family | Mechanic | Normalization | Auto-ricochet | Pen loss with distance | Spaced-armor behavior | Non-pen damage |
|---|---|---|---|---|---|---|
| **AP** | Kinetic | 5° | >70° (none if caliber >3T) | Yes, small | Subtracts the plate's T_eff and continues | 0 |
| **APCR** (incl. APDS) | Kinetic, faster and higher pen | 2° | >70° (none if caliber >3T) | Yes, large | Subtracts the plate's T_eff and continues | 0 |
| **HEAT** | Chemical jet | 0° | >85° (no 3-caliber rule) | None | Loses ~5% per 10 cm after any penetrated plate (tracks count) | 0 |
| **HE** | Blast and spall | 0° | Never | None | Since 1.13: −3×T for screens, tracks, wheels and external modules; −1×T for destructibles | Yes: impact-point formula plus spall |
| **HESH** | HE rules, much higher pen | 0° | Never | None | As HE (Low: not explicitly confirmed post-1.13) | Yes, as HE |

**Premium shells.** These are standard families with improved stats: APCR or HEAT with more penetration, and sometimes HE with more penetration or alpha. For most guns, **premium APCR and HEAT have the same alpha as standard AP**. Some guns use APCR as their *standard* round (many US, UK and modern guns), and British guns use HESH as a standard or premium HE substitute. (Medium, recollection plus [WG wiki Ammo](https://wiki.wargaming.net/en/Ammo))

#### 1.2 Typical numeric relationships for the same gun

These are approximate patterns, not exact rules (Medium/Low, recollection). **Fact-check:** the first four rows were checked against WG's public Tankopedia API snapshot (2017; 394 non-SPG vehicles whose default loadout is AP + premium + HE). The ratios are p10–p90 across those vehicles.

| Relationship | Typical value | Examples (WoT, recollection) |
|---|---|---|
| HE alpha / AP alpha | **≈1.33 median (p10–p90 1.20–1.59)** (corrected by fact-check; was "range 1.2–1.4") | 75 mm: 135/175 and, very commonly, 110/175; 100 mm: 250/330; 105 mm: 320/420; 120 mm: 400/515; 122 mm: 390/530 (all confirmed in the API) |
| Premium APCR/HEAT alpha / AP alpha | **1.0** (98% of the 394 loadouts; confirmed) | Most tier VIII–X guns |
| Premium pen / standard AP pen | **≈1.35 median (p10–p90 1.19–1.73)** (corrected by fact-check; was "≈1.25–1.35") | 120 mm: 258 AP vs 340 HEAT (confirmed) |
| HE pen (standard) | **≈ caliber_mm / 2** (median 0.505 × caliber; confirmed) | 75 mm → ~38, 105 mm → ~53, 120 mm → ~60, 122 mm → ~61 |
| HESH pen | Far above HE pen of the same caliber (≈2–4× HE) | British 120/183 mm guns |
| APCR velocity / AP velocity | **≈1.25** | Very common pattern |
| HE velocity / AP velocity | ≈1.0 (sometimes 0.8) | — |
| HEAT velocity / AP velocity | ≈0.8–1.0 | — |
| Premium shell credit cost / standard | **≈3–4×** | Tier X standard ~1.1k–1.4k credits; premium ~4.4k–5.6k credits |

Velocity ordering is confirmed qualitatively: APCR is fastest, AP is in the middle, and HEAT and HE are slower ([WG wiki Ammo](https://wiki.wargaming.net/en/Ammo), [WoT Console ammo article](https://modernarmor.worldoftanks.com/support/en/products/wotx/article/301/)).

#### 1.3 History

- Premium ammo was originally gold-only and was later made purchasable for credits (2012-era; exact version not re-verified, Low).
- A 2018–2019 Sandbox tested nerfing premium shells (lower alpha). It was **not released** (Low, recollection).

**Confidence:** High for the alpha and HE-pen relationships (confirmed against the API by the fact-check). Medium for the velocity relationships. Low for the cost ratios.
**Sources:** [WG wiki: Ammo](https://wiki.wargaming.net/en/Ammo), [WoT Console: What is Ammo](https://modernarmor.worldoftanks.com/support/en/products/wotx/article/301/), [Fandom: Gunnery & Armor Penetration](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration)

---

### 2. Normalization, overmatch and ricochet

#### 2.1 Modern behavior and exact values

| Rule | AP | APCR | HEAT | HE/HESH |
|---|---|---|---|---|
| Base normalization `n` | **5°** | **2°** | 0° | 0° |
| Auto-ricochet if impact angle θ (from the normal) exceeds | **70°** | **70°** | **85°** | never |
| 3-caliber rule (caliber > 3 × nominal T → no ricochet) | yes | yes | **no** (removed 2013) | n/a |
| 2-caliber rule (caliber > 2 × nominal T → boosted normalization) | yes | yes | no | no |
| Pen after ricochet (9.3 explainer, 2014; current rule unverified) | −25% of base | −25% of base | unchanged | n/a |
| Max ricochets per shell | 1 (a second ricochet deletes the shell) | 1 | 1 | – |

**Order of operations (Medium; this is the community-standard reading):**

```
θ   = angle between the reversed shell direction and the plate normal (degrees)
if family can ricochet and not (kinetic and caliber > 3*T) and θ > ricochetAngle:
    → ricochet (reflect, apply post-ricochet pen rule, shell continues)
n'  = n
if kinetic and caliber > 2*T:  n' = n * 1.4 * caliber / (2*T)        -- see 2.2
θn  = max(0, θ - n')
T_eff = T / cos(θn)
penetrate if penRoll >= T_eff
```

The ricochet test uses the raw impact angle, before normalization (Medium, recollection). Normalization does not move the 70° auto-bounce threshold.

#### 2.2 Discrepancy in the 2-caliber formula

- The WG Blitz support article and the fandom wiki write the formula as "n × 1.4 × caliber / 2 × armor thickness". Read with the intended parentheses, that is `n·1.4·cal/(2T)`. At exactly caliber = 2T it gives 1.4n, a moderate step up.
- A HyperX guide gives `n·1.4·cal/T`, with the worked example 60TP 152.4 mm against 75 mm: (5·1.4·152.4)/75 = 14.2°. That version gives a jump to 2.8n at the threshold.
- **We recommend `/(2T)`.** It matches the primary-source wording and has no large discontinuity.
- Fact-check: BlitzKit, an open-source WoT Blitz tool, implements `(1.4 · n · cal) / (2 · T)` when `cal > 2T`, and suppresses ricochet when `cal > 3T` ([BlitzKit armor shader](https://github.com/blitzkit/blitzkit/blob/c70fae81622c6e55593d425bc387b159fb41d387/packages/website/src/components/Armor/components/PrimaryArmorSceneComponent/shaders/fragment.glsl)). That supports the `/(2T)` reading in Wargaming's engine family. Blitz is a separate game, so PC remains unverified.

#### 2.3 History

| Version / date | Change |
|---|---|
| 0.8.6 (2013) | HEAT ricochet introduced at **≥80°**, with no pen loss on ricochet ([Release Notes 8.6](https://worldoftanks.eu/en/content/docs/release_notes/release-notes-86/)) |
| 2013 (after 8.6) | 3-caliber no-ricochet rule removed for HEAT ([FTR, 2013-10-30](http://ftr.wot-news.com/2013/10/30/why-was-3-caliber-rule-removed-for-heat/)) |
| 0.9.3 (Sept 2014) | Ricocheted shells keep flying on a new trajectory and can hit other vehicles. AP and APCR lose 25% of base pen, HEAT keeps its pen. Only one ricochet ([FTR 9.3 explainer](http://ftr.wot-news.com/2014/09/15/9-3-ricochet-mechanics-explained/)) |
| Later (version not found) | HEAT ricochet threshold is now documented as **85°** ([WG wiki Ammo](https://wiki.wargaming.net/en/Ammo), [Blitz support](https://wargaming.net/support/en/products/wotb/article/15409/)) |

**Confidence:** Medium for 5°/2°/70°/85° and the 3-caliber rule, downgraded from High because the fact-check could not re-access the sources. Medium for the 2-caliber formula. Low for the current post-ricochet pen loss and the one-ricochet cap.
**Sources:** [WG support (Blitz): Armor Penetration Mechanics](https://wargaming.net/support/en/products/wotb/article/15409/), [Fandom: Gunnery & Armor Penetration](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration), [HyperX: Overmatch, Normalization, and Ricochet](https://ag.hyperxgaming.com/article/5706/world-of-tanks-overmatch-normalization-and-ricochet-guide), [FTR 9.3 ricochet](http://ftr.wot-news.com/2014/09/15/9-3-ricochet-mechanics-explained/), [FTR HEAT 3-cal removal](http://ftr.wot-news.com/2013/10/30/why-was-3-caliber-rule-removed-for-heat/), [Release Notes 8.6](https://worldoftanks.eu/en/content/docs/release_notes/release-notes-86/)

---

### 3. Effective thickness, RNG, distance, gravity and range

#### 3.1 Effective thickness

```
T_eff = T_nominal / cos(θn)          θn = impact angle after normalization
```

- With spaced armor, the shell is normalized again at **each** plate. The shell continues along its normalized path.
- Remaining pen = rolled pen − Σ T_eff(spaced plates). That remainder is then tested against the main armor ([Fandom](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration)).

**Confidence:** High.

#### 3.2 Penetration and damage RNG

- Both roll **±25%** around the nominal value, reportedly using a **normal (Gaussian) distribution truncated at ±25%**.
- Example: a 390-alpha gun deals 293–488 damage; 200 mm of pen rolls 150–250 mm.
- Fact-check: WG's public Tankopedia API publishes every shell's damage and penetration as [min, avg, max]. In all 2,816 entries of the 2017 snapshot, min = round(0.75 × avg) and max = round(1.25 × avg), with no exceptions. The API does not reveal the distribution's shape.
- The σ is not published. A common community modelling assumption is that ±25% equals ±2σ (σ = 12.5%), but that is unverified.
- Note: tanks.gg's penetration-chance overlay assumes a *flat* distribution, while the game uses a normal one ([13disciple via search](https://www.13disciple.stream/penetration-mechanics.html)).
- **Modes:** no PC mode with different RNG was found. WoT **Console** ran a 2019 "Loaded Dice" event that reworked damage and penetration RNG ([TAP, 2019-08-01](https://thearmoredpatrol.com/2019/08/01/wot-console-loaded-dice-event-reworked-damage-and-penetration-mechanics/)).

**Confidence:** High for the ±25% bounds. Medium-Low for the normal shape (corrected by fact-check: not re-verified, and one secondary implementation doc assumes a uniform roll). Low for σ.

#### 3.3 Penetration loss over distance

- Only **AP and APCR** lose penetration. **HE, HESH and HEAT** do not ([Fandom](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration)).
- The displayed value applies at short range, with no loss inside ~100 m. The loss is linear out to ~500 m. Our reading is that it stays flat beyond 500 m, but that is uncertain.
- APCR loses much more than AP, except on guns where APCR is the default round ([Fandom](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration)).
- A secondary source gives ~4% per 100 m for AP and ~6% per 100 m for APCR. That is low quality and unverified.
- Wargaming's own GSOR 1008 (Dec 2020) discussed an "APCR shell penetration issue" over distance ([TAP](https://thearmoredpatrol.com/2020/12/23/gsor-1008-apcr-shell-penetration-issue/)), which suggests per-gun values are tuned individually.

**Confidence:** Medium for which shells lose pen and the linear shape. Low for magnitudes and the exact distance bounds.

#### 3.4 Gravity, arc, max range and travel time

- Shells are true projectiles with travel time and a ballistic drop. WoT uses gameplay-tuned (exaggerated) gravity per shell so arcs are visible at its compressed map scale (Medium, recollection).
- There is no air drag on velocity; distance penalties are expressed through the pen-loss table above.
- **Max range:** shells are deleted beyond a maximum flight distance. One secondary source says tank shells fly up to **~744 m** in total. Others cite ~720 m. Maps are ~1 km × 1 km and draw distance is ~564 m (Low).

**Sources:** [Fandom](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration), [secondary battle-mechanics guide (744 m claim)](https://portal.yandex.com.tr/yaozet/games/world-of-tanks-battle-mechanics-guide-IcdL8BJi), [WG wiki Camo and Spotting](https://wiki.wargaming.net/en/Camo_and_Spotting)

---

### 4. Spaced armor, tracks, HEAT and HE

#### 4.1 Spaced armor and tracks (modern)

- **Spaced armor**, meaning screens, side skirts, add-on plates and *tracks/wheels*, is non-HP armor. Hitting it alone never deals HP damage.
- **Kinetic shells (AP/APCR):** subtract the plate's T_eff, normalize again, and continue.
- **HEAT:**
  - Since **0.8.6 (2013)**, after any successful penetration the jet loses **5% of penetration per 10 cm** of travel.
  - Tracks count as spaced armor.
  - Wording differs between sources. Some say "5% of remaining per 10 cm" (compounding, ~40% per metre). Blitz support says "50% per 1 m of screen-to-armor clearance" (linear).
  - Fact-check: BlitzKit (WoT Blitz) applies `pen −= 0.5 × pen × gap_m` to the pen left after the screen. That is the linear 50%-per-metre reading used in R2. The PC rule was not re-verified.
  - In practice, HEAT hitting tracks or skirts rarely deals damage.
- **HE (since 1.13):**
  - HE can pass through screens, tracks, wheels, external modules and insignificant/destructible obstacles at the point of impact.
  - Pen loss equals **3 × the screen/track/wheel/external-module thickness**, or **1 × the thickness** of destructible objects.
  - Common Test 1 used 1× for screens. **Common Test 2 changed it to 3×**, which shipped. Example from the official article: 100 mm of HE pen through 20 mm of screen leaves 40 mm (it was 80 mm in CT1).
  - If HE gets through a screen and explodes on the main armor, "the spall mechanic takes effect and is guaranteed to cause damage".

#### 4.2 HE: what is live now

**History:**

| Date | Event |
|---|---|
| Pre-2021 | HE exploded at the first contact. Splash damage used a burst sphere: `0.5·D·(1 − d/R) − 1.1·T·K` over the thinnest armor reachable within R. Tracks and screens "absorbed" HE. |
| Feb 2020 Sandbox ("New Balance") | First HE/arty iteration. |
| Oct 2020 Sandbox ("HE Shells Revision") | Tested an "alternative HE" with **+50% pen, +10% damage, half the burst radius (a quarter of the area)** next to standard HE. Players found the iteration "incomprehensible and unpredictable". Wargaming acknowledged it was "a mistake to remove penetration from HE shell parameters". |
| 2021 Sandbox | Reworked iteration. Wargaming judged that it worked and announced its release ([Sandbox results](https://worldoftanks.eu/en/news/general-news/sandbox-he-shells-spg-rebalancing-results/)). |
| **Update 1.13 (June 2021)** | **Released:** see the list below. |

What Update 1.13 released:
- HE keeps its penetration stat.
- On a penetration, full damage as before.
- On a non-penetration, damage is computed **at the point of contact**. It depends on the **nominal** armor thickness at the impact point: thinner armor means more damage.
- Spall inside the vehicle damages modules, crew and HP. The spall radius equals the old burst radius.
- Screen and track penetration rules as in 4.1.
- Frontal HE damage against heavily armored vehicles is **reduced**.
- The Spall Liner works on the same principles as before.

**Why it changed:** to cut excessive HE damage to heavily armored vehicles (especially frontal hits and SPG splash), and to make HE results more predictable ([1.13 HE guide](https://worldoftanks.eu/en/news/general-news/1-13-HE-shells/), [1.13 CT2 changes](https://worldoftanks.eu/en/news/general-news/1-13-CT2-new-and-future-changes/), [Sandbox HE FAQ](https://worldoftanks.eu/en/news/general-news/sandbox-he-shells-faq/), [Sandbox October 2020](https://worldoftanks.eu/en/news/general-news/sandbox-october/)).

#### 4.3 HE damage formula (best available reconstruction)

The classic community formula, documented pre-1.13:

```
D_nonpen = 0.5 · D · (1 − d / R) − 1.1 · T · K_spall
   D = HE alpha (after the ±25% roll), d = distance from the burst to the armor point, R = splash radius,
   T = armor thickness, K_spall = 1.0 none / 1.2 light / 1.25 medium / 1.3 heavy / 1.5 superheavy (old spall-liner classes)
```

([13disciple Hull Damage via search](https://www.13disciple.stream/hull-damage-mechanics.html); used by Wargaming's [Sandbox Oct-2020 article](https://worldoftanks.eu/en/news/general-news/sandbox-october/) as the baseline.)

Fact-check: the structure `0.5·D·(1 − d/R) − 1.1·T` is corroborated by BlitzKit's WoT Blitz model, which subtracts 1.1 × (normalized main-plate thickness + spaced-armor thickness). The `K_spall` values above were **not** re-verified.

- **Post-1.13 direct hit (reconstruction, Medium-Low):** d ≈ 0 and T = **nominal** armor at the impact point, so `D_nonpen ≈ 0.5·D − 1.1·T_nominal·K`, with an apparent non-zero floor ("will deal damage").
- **Splash on other nearby vehicles:** still sphere-based. It hits allies as well.
- **Equipment 2.0 Spall Liner (1.10, 2020):** "+50% HE-shell and ramming damage reduction, +50% crew protection" (+60% in a bonus slot), in Light/Medium/Heavy/Superheavy weight classes. How that maps to `K_spall` is not published ([WG wiki Equipment](https://wiki.wargaming.net/en/Equipment)).
- **Splash radius:** each shell has its own published "explosion radius". Tank-gun HE radii are a fraction of a metre to ~1.5 m. SPG radii are much larger. Exact per-caliber values were not verified (Low).
- **HE versus modules and crew:**
  - HE is the classic de-tracking and crew-injuring round. Splash damages external modules (tracks, gun, optics) inside R.
  - Post-1.13 spall damages internal modules and crew inside the spall radius, even on a non-penetration.
  - The Spall Liner reduces crew injuries.
- **"Shell absorption":**
  - External modules (tracks, wheels, the gun barrel/mantlet module) and spaced armor can stop a shell completely: module damage happens with zero HP damage.
  - Before 1.13, HE was routinely "absorbed" by tracks and screens. After 1.13, HE pushes through them with the 3× penalty.

**Confidence:** Medium that 1.13 HE is live and for the 3× and 1× coefficients, downgraded from High because the fact-check could not re-access any 1.13 source. The worked example's arithmetic is consistent (100 − 3 × 20 = 40; 100 − 20 = 80). Medium-Low for the exact post-1.13 formula and floor.

---

### 5. Damage application, modules, fire and ammo rack

#### 5.1 HP damage

- Penetration (AP/APCR/HEAT/HE/HESH) deals **full alpha × RNG**. Armor does not reduce it.
- A non-penetration deals 0 HP damage, except HE/HESH (section 4).
- Damage is capped at the target's remaining HP.
- There is **no damage falloff with distance** (Medium, recollection).
- A **"critical hit"** in WoT means module damage or a crew injury, and does not necessarily involve HP damage ([gamepressure](https://guides.gamepressure.com/worldoftanks/guide.asp?ID=16342)).

#### 5.2 Module model

From the official support article [What Happens When a Shell Hits a Vehicle?](https://wargaming.net/support/en/products/wot/article/15762/):
- Every module has HP.
- At **50% damage** it turns **yellow** (damaged, degraded function).
- At **100%** it turns **red** (destroyed, critical).
- The crew automatically restores a destroyed module to the damaged (yellow) state.
- A **repair kit** restores full HP and normal state. Since 1.26 the small kit also repairs **all** modules.
- One secondary source says field repair restores to 75% HP while keeping the "damaged" status ([13disciple Module Damage](https://www.13disciple.stream/module-damage-mechanics.html)). The official article says 50%. Treat the exact restore percentage as uncertain.

| Module | Damaged (yellow) | Destroyed (red) | Notes |
|---|---|---|---|
| Engine | Reduced power/acceleration | Vehicle cannot move | **Fire chance on every engine hit**, regardless of remaining HP. Per-engine value **10–20%**. Confirmed by the fact-check against 511 engine modules in WG's public API: 20% for gasoline engines (307 modules, e.g. Maybach HL, M-17), and 15% (126), 12% (58) or 10% (20) for diesels such as V-2 and 12150L |
| Ammo rack | **Reload time increased** | **Detonation: vehicle destroyed** | Wet Ammo Rack (+50% ammo-rack HP) is a **legacy item**. Equipment 2.0 (Update 1.10, Aug 2020) folded its role into Improved Configuration, at +150% ammo-rack, fuel-tank and engine durability per doc 05 §4.2 (Medium) (corrected by fact-check) |
| Fuel tank(s) | Higher fire chance | **Fire** | — |
| Gun | Dispersion and aim penalties | Cannot fire | — |
| Turret ring (rotation mechanism) | Turret traverse reduced | Turret cannot traverse | — |
| Observation device (optics) | View range reduced | View range heavily reduced | — |
| Radio | Signal range reduced | Signal range heavily reduced | Low gameplay impact |
| Tracks / wheels | — | Tracked: immobilized until repaired. Wheeled: loses wheels, keeps partial mobility | Tracks act as spaced armor (section 4). Hits at the leading or rearmost wheel de-track most reliably |

- **Module damage per shell:** each shell has a separate module-damage value besides alpha. HE is the strongest against modules. Per-shell values were not verifiable (Low).
- **Per-module "chance to be damaged"** on a shell pass is per module type. Community wiki-era values (Low, recollection) are: engine ~45%, fuel tank ~45%, radio ~45%, turret ring ~45%, gun ~33%, crew ~33%, **ammo rack ~27%**. Ammo-rack detonation therefore requires (a) the shell's path to cross the rack, (b) a successful hit roll, and (c) enough module damage to take the rack's HP to 0 ([HyperX ammo rack](https://ag.hyperxgaming.com/article/5397/easy-ammo-rack-targets-in-world-of-tanks)).

#### 5.3 Post-penetration shell path

- After penetrating, the shell continues **up to 10 calibers, but not less than 0.5 m**. A 100 mm shell continues ~1 m.
- It damages every internal module and crew member it crosses. Internal modules and crew have no armor, so they are always reached if any pen remains.
- HEAT keeps losing pen per 10 cm after the first plate.

**Confidence:** Medium ([Blitz support: How do shells deal damage?](https://wargaming.net/support/en/products/wotb/article/15412/), [Fandom](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration)).

#### 5.4 Fire

- **Sources of fire:** an engine hit rolls the engine's fire chance (~10–20%), and a destroyed fuel tank causes fire automatically. Flamethrower vehicles exist in event modes.
- **While burning:** the vehicle takes continuous HP damage plus module and crew damage. The burn rate is per vehicle and **not shown in game**. Duration and DPS values were not verifiable.
- **Mitigation:**
  - Fire Extinguisher / Automatic Fire Extinguisher consumables. The automatic one extinguishes on its own and passively cuts fire chance by ~10%.
  - Crew skills: Fire Fighting (faster extinguishing) and Preventative Maintenance (−25% engine fire chance).
  - **Update 1.26 (Common Test Aug 2024; released Sept 2024 per doc 05):** Automatic Fire Extinguisher cooldown cut from **90 s to 60 s**. The manual extinguisher, a "small" consumable, stays at 90 s (doc 05 §5). This matches doc 05 but was not independently re-verified.

**Confidence:** Medium for sources and mitigation. Low for duration and damage numbers.
**Sources:** [Fandom Battle Mechanics](https://worldoftanks.fandom.com/wiki/Battle_Mechanics), [WG support (Blitz) All About Fire](https://wargaming.net/support/en/products/wotb/article/15410/), [Update 1.26 CT1](https://worldoftanks.com/en/news/updates/1-26-CT1/), [TAP 1.26 consumables](https://thearmoredpatrol.com/2024/08/11/wot-1-26-common-test-consumables-update/), [Release Notes 1.26](https://worldoftanks.com/en/content/docs/release_notes/release-notes-1-26/)

---

### 6. Crew injuries

- **Who can be injured:** any of the 2–6 crew (commander, gunner(s), driver, radio operator(s), loader(s)). Crew are internal "modules" hit by the post-penetration path, by HE spall and by fire.
- **Effects:**

| Crew role | Effect when injured |
|---|---|
| Commander | View range reduced; the commander's **+10% bonus to the rest of the crew** is lost |
| Driver | Movement and hull traverse speed reduced |
| Gunner | Aim time increased; accuracy and turret traverse decreased. Fandom describes the bloom "as if the gun itself was damaged" |
| Loader | Reload time increased. Fandom describes it "as if the ammo rack was damaged" |
| Radio operator | Signal range reduced |

- **How much skill an injured crew member loses is disputed.** Fandom says injured crew drop to **50%**, explicitly "not 0%". A summary of the official support article says the major qualification drops to **0%**. Using the reload formula in section 9, a 50% loader gives **×1.27** reload and a 0% loader gives **×1.75** (Low).
- **Jack of All Trades:** the commander can partly cover one knocked-out role, up to 50%.
- **Medical consumables (since Update 1.26, 2024):**
  - The **Small First Aid Kit now heals all injured crew**; before, it healed one crew member.
  - The **Large First Aid Kit** heals and restores all crew, with its cooldown cut from **90 to 60 s**.
  - Standard consumable cooldown is ~90 s.
- **Crew system churn (2024–2026):**
  - Crew interface rework in 1.22.1.
  - Crew QoL update in April 2024.
  - 1.26 perk update.
  - Feb 2026 "crew rework complete: new perks and final improvements", which shipped as Update 2.2 in March 2026 per doc 05.
  - Injury and skill math may have shifted. Re-verify before copying numbers.

**Confidence:** High that roles and effects are as described. Low for the injured skill percentage.
**Sources:** [WG support: What Happens When a Shell Hits a Vehicle?](https://wargaming.net/support/en/products/wot/article/15762/), [Fandom Crew](https://worldoftanks.fandom.com/wiki/Crew), [Wargaming fandom Crew (WoT)](https://wargaming.fandom.com/wiki/Crew_(WoT)), [Vehicle Crew guide](https://worldoftanks.com/en/content/guide/game-mechanics-and-achievements/vehicle-crew/), [Crew Update April 2024](https://worldoftanks.com/en/news/general-news/crew-update-april-2024/), [TAP 2026 crew rework](https://thearmoredpatrol.com/2026/02/27/wot-crew-rework-complete-new-perks-final-improvements/)

---

### 7. Ramming and fall damage

#### 7.1 Ramming

**Official factors** ([Update 9.4 ramming changes](https://worldoftanks.eu/en/news/general-news/update94-changes-ramming)):
- vehicle mass;
- speeds at the moment of collision;
- Spall Liner;
- "Controlled Impact" skill;
- **armor thickness at the point of damage application**;
- side skirts and spaced armor.

Ramming the enemy's weak spots **with your own armored front** deals more damage to them and less to you.

**Community model** (Medium-Low, [HyperX ramming guide](https://blog.hyperx.com/article/5740/world-of-tanks-penetration-damage-modules-and-ramming)):

```
E = 0.5 · (m1 + m2) · v_rel²                       -- collision "energy"
share_i = 1 − m_i / (m1 + m2)                       -- lighter tank takes the larger share
D_i ≈ HE-like non-pen formula applied at the contact point with an equivalent alpha from E·share_i,
      minus 1.1 · T_contact · K_spall
```

- Example: a 7.5 t tank hitting a 2.5 t tank takes only **25%** of the damage.
- Controlled Impact shifts up to ~15% of the damage onto the opponent.
- The Spall Liner reduces ramming damage received.
- Team damage from ramming allies exists in Random Battles (blue penalties). Its current treatment was not re-verified.

#### 7.2 Fall damage

- No published formula was found.
- Observed behavior: damage grows with fall height (impact speed) and vehicle mass. Landing upside down deals much more (one anecdote: ~1,300 vs ~600 HP for the same drop). Suspension and tracks can be damaged.
- Landing on an enemy deals damage to it, as with ramming (the "Death From Above" achievement).

**Confidence:** Low. Our own model is in the recommendations.

---

### 8. Aiming and accuracy

#### 8.1 Dispersion definition and distribution

- **Gun dispersion `A`** is the radius of the fully aimed reticle in metres **at 100 m**. It scales linearly with distance: `R(d) = A · d / 100`.
- **Distribution:** normal, with the **reticle edge at 2σ**, so `σ = R / 2`. See the radial-versus-2D note below (corrected by fact-check; this line said "2D normal").
  - Before 0.8.6 the edge was at **1.3σ**, which put ~19.4% of shots on the circle's edge.
  - **0.8.6 (2013)** moved the edge to **2σ** (~4.6% at the edge) and "eliminated the spike on the edge". That implies outliers are re-rolled or redistributed rather than clamped to the rim.
  - **Radial versus 2D (corrected by fact-check).** 19.4% and 4.6% are the two-sided tails of a *one-dimensional* normal: P(|Z| > 1.3) = 19.4% and P(|Z| > 2) = 4.55%. An isotropic 2D normal has Rayleigh-distributed radius, and would put **43%** of shots beyond 1.3σ and **13.5%** beyond 2σ. The published figures therefore describe the **radial miss distance** as normal: radius `|N(0, σ)|` with a uniform direction. That model packs shots much more tightly around the centre than a 2D normal. WoT's actual sampling code was not verified.
  - Why: shots felt too random, and too many landed on the rim ([WoT news: Big Changes Coming With 8.6](https://worldoftanks.com/en/news/general-news/some-changes-coming-86-update/)).
  - **No later change** to the distribution was found up to 2026 (Medium).

#### 8.2 Aim time and bloom

- **Aim time `τ`** is the time for the current dispersion to shrink by a factor of **e (~2.72)**. Guides paraphrase this as "to about 1/3". Real time to a full aim is often 1.5–2× the listed value because bloom typically starts at more than 2.72× ([gamepressure accuracy guide](https://guides.gamepressure.com/worldoftanks/guide.asp?ID=16340), [WoT Console aiming time](https://modernarmor.worldoftanks.com/en/cms/guides/aiming-time/)).
- Implied model: `R(t) = max(R_target, R_0 · e^(−t/τ))`, so time to full aim is `τ · ln(R_0 / R_target)`.
- **Bloom sources** (each vehicle has its own factors, as displayed on tanks.gg-style sites):
  - movement (per unit of speed);
  - hull traverse (per deg/s);
  - turret traverse (per deg/s);
  - **after-shot** bloom (a multiplier, typically several ×);
  - **damaged gun** (a multiplier);
  - an injured gunner (a skill reduction).
- **How the bloom factors combine:** the community-documented model is a **root-sum-square** combination: `R = A · √(1 + Σ(k_i·x_i)²)` (Low-Medium). We could not verify it against a primary source in this session.
- Crew skill and equipment affect `A` and `τ` with the same skill curve as reload (section 9). The vertical stabilizer reduces movement and traverse bloom.

#### 8.3 Gun elevation and depression

- These are per-vehicle arcs. Many vehicles have **reduced depression over the rear or sides** of the hull.
- Typical values (recollection): depression **−5° (poor) to −10° (excellent)**, elevation **+15° to +25°**.
- Hydropneumatic vehicles (e.g. Swedish TDs, some modern mediums) have siege or pitch modes that change depression.

#### 8.4 Server reticle versus client reticle

- The server is authoritative for aim and the dispersion roll.
- The client reticle is a smoothed local prediction. An optional **"server reticle"** setting shows the authoritative circle, which lags by ping.
- Shots are resolved by the server (Medium, recollection).

**Confidence:** Medium for the 2σ change, downgraded from High because the 8.6 article could not be re-accessed. The quoted percentages are arithmetically consistent with a radial normal. Medium for the aim-time definition. Low-Medium for the combination formula.
**Sources:** [WoT 8.6 changes](https://worldoftanks.com/en/news/general-news/some-changes-coming-86-update/), [13disciple Shooting Mechanics (via search)](https://www.13disciple.stream/shooting-mechanics.html), [gamepressure](https://guides.gamepressure.com/worldoftanks/guide.asp?ID=16340), [WoT Console aiming time](https://modernarmor.worldoftanks.com/en/cms/guides/aiming-time/)

---

### 9. Reload, autoloaders, autoreloaders and dual guns

#### 9.1 Single-shot reload

- **Crew skill curve** (also used for aim time, dispersion and other crew-driven stats):

```
stat_actual = stat_base × 0.875 / (0.00375 · L + 0.5)
L = effective major-qualification level (%) including commander bonus (+10% of commander level), food, vents, BiA
  L = 100 → ×1.000 | L = 110 → ×0.959 | L = 50 → ×1.273 | L = 0 → ×1.750
```

  Worked example: 30 s × 0.875 / (0.00375 × 103.67 + 0.5) = 29.54 s.

  Fact-check: the same curve, `× 0.875 / (0.5 + 0.00375 · skill)`, is used for reload and terrain resistance by an independent community tool ([tanktionary measure.cpp](https://github.com/IronCrossEnterprises/tanktionary/blob/bbf3fba95631b4673f61c5ff15e661af0babdb8b/wotparser/measure.cpp)). The table values and the worked example were recomputed and are correct. Caveat: per doc 05, crews have been at 100% major qualification since April 2024, so in practice L sits at about 100–120%.
- **Several loaders:** the average of their levels is used.
- **Displayed stats** assume 100% crew.
- **Modifiers:**
  - injured loader (see section 6);
  - **damaged ammo rack** increases reload time (multiplier not published);
  - Rammer equipment (about −10%; not available on autoloaders);
  - crew perks.

#### 9.2 Autoloader (magazine)

- Parameters: `clipSize n`, `intraClip t_i` (time between shells), `magReload T_m`.
- `Burst = n · alpha`.
- `DPM = 60 · n · alpha / (T_m + (n − 1)·t_i)`.
- Manually reloading a partly empty magazine costs a full `T_m`.
- Rammer equipment is not compatible with autoloaders.

#### 9.3 Autoreloader

- Introduced with the Italian medium branch (2018–2019 era, Medium-Low).
- The magazine refills **one shell at a time**, and each slot has its own reload timer `t_1…t_n`.
- Firing does not reset a shell that is already loading.
- Sustained DPM is `60 · n · alpha / Σ t_k`. The burst is the full magazine.
- Exact timer ordering conventions per vehicle were not verified.

#### 9.4 Dual-gun

- Introduced with the Soviet dual-barrel heavies (ST-II line), late 2020. The version, 1.10.1 or 1.11, was not re-verified.
- **Single fire:** each barrel fires separately, with a short interval between barrels.
- **Volley fire:** holding fire charges a volley for about 1 s and then fires both barrels for double alpha.
- After both barrels have fired, a long full reload follows. Volleys have extra dispersion.

**Confidence:** High for the crew formula. Medium for the autoloader formulas. Low-Medium for the autoreloader and dual-gun specifics.
**Sources:** [Fandom Battle Mechanics](https://worldoftanks.fandom.com/wiki/Battle_Mechanics), [Crew Training guide](https://worldoftanks.com/en/content/guide/game-mechanics-and-achievements/crew-training/), [WG wiki Equipment](https://wiki.wargaming.net/en/Equipment)

---

### 10. Per-tier gun calibration table

The **WoT band** columns are approximate ranges for typical non-derp tank guns, recalled from well-known WoT vehicles. They were **not re-verified this session** and are for calibration only. Do not copy them as stats. Derp guns, SPGs and big TD guns exceed these bands.

| Tier | Caliber (mm) | AP alpha | HE alpha | AP pen | Premium pen | HE pen | Reload (s) | DPM | Dispersion @100 m | Aim time (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| **I** (WoT band) | 20–45 | 30–55 | 40–70 | 30–55 | 45–90 | 10–23 | 1.3–2.6 | ~1,200–1,700 | 0.43–0.55 | 1.5–2.3 |
| **III** | 37–76 | 35–110 | 45–175 | 45–90 | 65–125 | 18–38 | 1.7–4.0 | ~1,300–1,800 | 0.40–0.50 | 1.7–2.3 |
| **V** | 57–85 | 75–160 | 100–210 | 75–145 | 110–190 | 30–43 | 2.5–6.5 | ~1,500–2,100 | 0.37–0.46 | 1.9–2.5 |
| **VII** | 75–105 | 150–390 | 200–520 | 130–200 | 175–260 | 38–61 | 4.5–13 | ~1,600–2,300 | 0.33–0.46 | 1.7–3.0 |
| **VIII** | 85–122 | 200–390 | 270–530 | 170–235 | 210–300 | 43–61 | 5–13 | ~1,700–2,700 | 0.32–0.46 | 1.6–3.4 |
| **IX** | 100–130 | 240–440 | 320–580 | 200–260 | 250–330 | 50–65 | 6–14 | ~2,000–3,000 | 0.30–0.42 | 1.6–3.0 |
| **X** | 105–130 | 300–490 | 400–640 | 240–290 | 300–400 | 53–68 | 6–14 | ~2,300–3,600 | 0.27–0.40 | 1.5–3.0 |

**Fact-check against WG's public API (2017 snapshot).** The figures are p10–p90 of the top gun on each non-premium, non-SPG vehicle, excluding derp guns, with stock aim and dispersion values:

| Tier | Dispersion | Aim time (s) | AP pen | Premium pen | DPM |
|---|---|---|---|---|---|
| I | 0.43–0.54 | 1.7–2.5 | 27–51 | 38–88 | ~720–1,840 |
| V | 0.34–0.43 | 1.7–2.9 | 100–150 | 130–202 | ~1,510–2,080 |
| VIII | 0.31–0.42 | 2.1–3.4 | 175–258 | 216–329 | ~1,790–3,560 |
| X | 0.33–0.42 | 2.3–3.4 | 246–303 | 280–375 | ~1,990–3,770 |

Pen and DPM bands broadly match the table above. The tier X dispersion band (0.27–0.40) and the aim-time bands are too optimistic.

Patterns worth copying:
- **DPM roughly doubles from tier I to tier X**, while alpha grows about 10× (confirmed).
- **Dispersion improves only modestly, from ~0.45–0.50 at tier I to ~0.35–0.40 at tier X** (corrected by fact-check; was "~0.50 to ~0.32"). The median medium tank goes from 0.43 to 0.39.
- **Aim time stays roughly flat or rises slightly**: the median medium tank sits at ~2.3 s at every tier, and the band moves from ~1.7–2.5 s at tier I to ~2.3–3.4 s at tier X (corrected by fact-check; was "flat at 1.5–3.0 s").
- **AP pen grows about 6×** (45 to 260).
- Premium pen is about **1.3×** AP pen.

HULLDOWN's own baseline is in Recommendations R10.

---

## Implementation recommendations for HULLDOWN (Roblox)

All values below are **OUR DESIGN CHOICE** unless they are marked "= WoT". Simulation units are mm (armor and pen), m, m/s and degrees. Convert at the Roblox boundary using the documented scale **1 stud = 0.28 m** (equivalently 1 m/s = 3.57 studs/s; local docs `physics/units.md`). Keep every constant in one `CombatConfig` ModuleScript so balancing never touches code.

### R1. Shell family table (= WoT rules, with our multipliers)

```lua
ShellFamilies = {
  AP   = { norm = 5, ricochet = 70, threeCal = true,  twoCal = true,  penLoss = "AP",   explodes = false },
  APCR = { norm = 2, ricochet = 70, threeCal = true,  twoCal = true,  penLoss = "APCR", explodes = false },
  HEAT = { norm = 0, ricochet = 85, threeCal = false, twoCal = false, penLoss = nil,    explodes = false, gapLossPerM = 0.50 },
  HE   = { norm = 0, ricochet = nil, explodes = true, screenPenMult = 3.0, destructiblePenMult = 1.0 },
  HESH = { norm = 0, ricochet = nil, explodes = true, screenPenMult = 3.0, destructiblePenMult = 1.0, nonPenBonus = 1.15 }, -- OUR: small identity bonus
}
-- HESH screenPenMult = 3.0 is OUR choice: whether WoT applies the 1.13 HE screen rule to HESH is unconfirmed (Low, see 1.1).
-- Per-gun derivation defaults (designers override per gun):
--   HE alpha = round(1.30 * AP alpha); premium alpha = AP alpha; premium pen = 1.30 * AP pen
--   HE pen = caliber/2;  HESH pen = 1.6 * caliber (OUR); APCR v = 1.25 * AP v; HE v = AP v; HEAT v = 0.85 * AP v
--   Premium credit cost = 3.5 * standard (economy doc owns the final value)
```

### R2. Armor resolution pipeline (= WoT, with a deterministic order)

1. `θ = acos(dot(-dir, normal))`. Use `RaycastResult.Normal`.
2. **Ricochet check:** applies if the family can ricochet, and is not a kinetic shell with caliber > 3T, and θ > threshold. On a ricochet:
   - reflect `dir` about the normal;
   - kinetic pen ×0.75, HEAT ×1.0. This is **OUR DESIGN CHOICE**, taken from the 2014 9.3 explainer. It was labelled "= WoT 9.3 rule", but the current WoT rule is unverified (Low) and the Summary lists it as a deviation (corrected by fact-check);
   - set `ricochets = 1`, so a second ricochet destroys the shell;
   - grant **no HP damage** and **no module damage**, except to an *external* module that was hit.
3. **Normalization:** `n' = n`. If kinetic and caliber > 2T, `n' = n·1.4·cal/(2T)`. Then `θn = max(0, θ − n')`.
4. `T_eff = T / cos(θn)`. Clamp `cos` at ≥ 0.05 to avoid infinities.
5. Pen roll and distance:
   - `pen = basePen · distanceFactor(family, d) · truncNormal(±25%)`;
   - roll **once per shell** at the first impact, then subtract plates from that value;
   - the truncNormal roll happens at the first impact **before** the step-2 ricochet test, so the ×0.75 ricochet penalty applies to the rolled value (order clarified by fact-check: step 2 previously ran before any roll existed).
6. **If the plate is spaced/track/external-module:**
   - Kinetic: `pen −= T_eff`. If pen stays above 0, rotate `dir` by n' toward the normal and continue raycasting.
   - HEAT: same subtraction, then `pen *= max(0, 1 − 0.5·gap_m)` for the gap to the next plate. This is the linear reading of the WoT 5%/10 cm rule, chosen because it is easier to explain.
   - HE/HESH: `pen −= 3·T`. If pen ≤ 0, explode at that point.
7. **If the plate is main hull/turret armor:**
   - `pen ≥ T_eff` → penetration: full damage roll plus the internal path (R5).
   - Otherwise a non-penetration: 0 HP damage for kinetic and HEAT; the HE formula (R4) for HE/HESH.
8. Limit the loop to **8 iterations** per shell. Use `RaycastParams.FilterDescendantsInstances` to exclude parts already hit.

### R3. RNG (= WoT range, with a published σ)

- `truncNormal(spread=0.25)`: σ = 0.125 (±2σ = ±25%). Re-roll outside ±25%, with a max of 8 attempts before falling back to clamping. Use one server `Random.new(seed)` per match.
- Use the **same RNG for damage and penetration**.
- Add an optional `CompetitiveMode` profile with **±10%** spread. This is our deviation for tournaments and ranked play, and is easy to explain in UI.

### R4. HE / HESH (readable version of the 1.13 rules)

- **Direct-hit penetration:** full alpha × RNG, plus an internal spall sphere of radius `R_spall` that rolls module and crew damage (R5).
- **Direct-hit non-penetration:**
  - `D = max(floor, 0.5·α_rolled − 1.1·T_nominal·K_spall) · (HESH ? 1.15 : 1.0)`;
  - `floor = 0.05·α`. WoT says HE that reaches the armor always deals damage, but the floor value is ours;
  - plus spall-sphere module and crew rolls at ×0.5 module damage.
- **Splash** on every other vehicle within `R_splash`:
  - `D = max(0, 0.5·α·(1 − d/R) − 1.1·T_min·K_spall)`, where T_min is the thinnest armor part whose surface lies inside R;
  - get T_min with `WorldRoot:GetPartBoundsInRadius` on the "Armor" collision group, then the nearest point per part;
  - external modules (tracks, gun, optics) inside R take module damage;
  - **friendly splash = 50%** (our choice).
- **Radius:** `R_splash (m) = caliber_mm / 100`. That gives 75 mm → 0.75 m, 105 mm → 1.05 m and 152 mm → 1.52 m, which is readable in Roblox. `R_spall = R_splash`.
- `K_spall` from equipment: none 1.0, light 1.2, medium 1.3, heavy 1.5. This is **OUR DESIGN CHOICE**. It was described as "tidied WoT-era classes", but it differs from the WoT-era table in 4.3 (medium 1.25, heavy 1.3, superheavy 1.5), and that table is itself unverified (corrected by fact-check).

### R5. Modules, crew and the internal path

- Post-penetration path length is `max(0.5 m, 10·caliber)`. The 10-caliber length is = WoT (Medium); the 0.5 m floor is unverified. Shapecast or Raycast against the **"Modules"** collision group, using parts with `CanCollide=false, CanQuery=true`.
- **Per-module hit chance** (WoT-style defaults; tune later):

  | Engine | Fuel | Radio | Turret ring | Gun | Optics | Crew | Ammo rack | Tracks |
  |---|---|---|---|---|---|---|---|---|
  | 0.45 | 0.45 | 0.45 | 0.45 | 0.33 | 0.45 | 0.33 | 0.27 | 1.0 (external) |

- **Module damage per shell:** `md = 0.5·α` for kinetic and HEAT, `0.75·α` for HE and HESH, capped at `1.2 × module max HP`. This makes one same-tier hit usually *damage* a module, and two hits destroy it.
- **Module HP:** `HP = k · tierRefAlpha`, using the tier reference alpha from R10.
  - k values: engine 1.0, ammo rack 0.9, fuel 1.0, gun 1.0, turret ring 1.0, optics 0.8, radio 0.7, tracks 1.4.
  - Crew have HP `0.8 · tierRefAlpha`. When it reaches 0 the crew member is injured. Crew members are never "killed" mid-match; we chose this for readability.
- **States:** above 50% HP is OK. 50% or below is **Damaged** (yellow). 0 is **Destroyed** (red).
  - Field repair moves Destroyed to Damaged at 50% HP. Base times: tracks 10 s, engine 14 s, gun 12 s, turret ring 12 s, optics/radio 8 s, fuel 10 s.
  - Times scale with the crew curve (R9). A repair kit sets the module to 100%.
- **Effects:**

  | Module | Damaged | Destroyed |
  |---|---|---|
  | Engine | power ×0.5 | immobile |
  | Ammo rack | reload ×1.25 | **detonation, vehicle destroyed** |
  | Fuel | fire chance ×1.5 | fire |
  | Gun | dispersion ×1.5, aim time ×1.25 | cannot fire |
  | Turret ring | traverse ×0.5 | no traverse |
  | Optics | view range ×0.8 | view range ×0.5 |
  | Radio | signal range ×0.7 | signal range ×0.3 |
  | Tracks | — | immobilized; wheeled vehicles lose 25% top speed per lost wheel pair |

- **Fire:**
  - **15%** per engine hit (gasoline 20%, diesel 12%). A destroyed fuel tank gives 100%.
  - Burns **8 s** at **2.5% of max HP per second**: 20% of max HP if left alone. Crew and modules in the engine bay also take damage.
  - Fire Fighting perk: −25% duration. Manual extinguisher: instant, **90 s** cooldown. Automatic extinguisher: triggers after 0.5 s, gives −10% fire chance, and has a 60 s cooldown. This matches WoT 1.26 (section 5.4) and doc 05 R9 (corrected by fact-check; the manual extinguisher was 60 s here).
- **Crew injuries:**
  - An injured crew member's skill becomes **50%**: the readable choice, resolving the WoT ambiguity toward Fandom's value.
  - Commander injured: −10% view range, and the +10% crew bonus is lost.
  - First-aid kit: heals **all** crew, 90 s cooldown (small) or 60 s (large), matching WoT 1.26.

### R6. Ramming and fall damage (original formulas)

- **Ramming:**
  - `v_rel` = closing speed along the contact normal (m/s), with masses in tonnes. **No damage below `v_rel < 3 m/s`** (≈11 km/h).
  - Damage to B: `D_B = max(0, k_ram·0.5·m_A·v_rel² − 1.1·T_B_contact·K_spall_B)`. The symmetric expression applies to A.
  - This is algebraically the WoT "split energy by mass share" model.
  - `k_ram = 0.10`. Example: a 50 t heavy at 40 km/h (11.1 m/s) rams a 20 t light's 40 mm side for **~265 HP**. The heavy, hitting with a 150 mm front, takes 0.
  - Front-armor bonus: if the contact point is on the rammer's front arc, its damage taken is ×0.5.
  - Allies take ×0.25.
  - Rams roll track damage on both vehicles.
- **Fall:**
  - On landing, take vertical impact speed `v_y`. If `v_y > 7 m/s` (≈2.5 m drop at g = 9.81): `D = k_fall·m·(v_y − 7)²`, with `k_fall = 0.6` and m in tonnes.
  - Upside-down landing ×2.
  - Roll track/suspension damage with chance `min(1, (v_y − 7)/5)`.
  - Landing on another tank: apply the ramming formula with `v_rel = v_y`.

### R7. Ballistics on Roblox (deliberate deviations)

- **Server-authoritative projectile sim** on `RunService.Heartbeat`.
  - Each step, raycast the swept segment `prevPos → pos` with `WorldRoot:Raycast`. Direction length is ≤15,000 studs, which is never an issue per step.
  - Raycast is Parallel-Luau safe. Batch shells in an Actor if counts grow.
  - Clients render tracers from a replicated (origin, velocity, seed, t0).
- **Velocity scale ×0.6 versus real-world muzzle velocities.** Example: AP 800 m/s becomes 480 m/s, about 1,714 studs/s or ~29 studs per 60 Hz step.
  - Why: Roblox engagement ranges (50–400 m) are shorter than WoT's, and slower shells keep leading targets and tracers readable.
- **Shell gravity `g_shell = 9.81 × 2.0 m/s²`, independent of `Workspace.Gravity`.** Roblox's default 196.2 studs/s² is ≈54.9 m/s², which is unsuitable for shells. WoT also exaggerates arcs.
- **Max shell flight 600 m.** Shells despawn after that, or HE detonates on terrain.
- **Pen-loss table** (linear, then flat):

  | Family | Loss between 100 m and 500 m | Pen at ≥500 m |
  |---|---|---|
  | AP | 10% total (2.5%/100 m) | ×0.90 |
  | APCR | 25% total (6.25%/100 m) | ×0.75 |
  | HEAT / HE / HESH | none | ×1.00 |

- **Armor geometry:**
  - Use invisible Box/Wedge parts in collision group "Armor", with attributes `ArmorMm` and `PlateKind` (Hull, Turret, Spaced, Track, Mantlet, External). Their normals are exact.
  - Visual meshes are separate and use `CanQuery=false`.
  - Avoid precise-convex-decomposition MeshParts for armor, because of cost and normal noise.

### R8. Aiming model (= WoT definitions, with explicit constants)

- `σ = R/2`. Sample the **radial miss distance** as `|N(0, σ)|` with a uniform direction, and **re-roll when it exceeds 2σ** (4.55% of draws). This reproduces the percentages WoT published for 0.8.6.
  - This line used to say "sample a 2D normal (= WoT 0.8.6 behavior)". An isotropic 2D normal re-rolls 13.5% of draws and spreads shots more evenly, so it does not match the published figures (corrected by fact-check).
  - Keep `dispersionModel = "radial" | "gauss2d"` in `CombatConfig` so designers can switch. WoT's internal sampling is unverified either way.
- Bloom: `M_target = √(1 + (k_mv·v_kmh)² + (k_hull·ω_hull)² + (k_tur·ω_tur)²) · (gunDamaged and 1.5 or 1)`.
  - Defaults: `k_mv = 0.07` (≈3.6× at 50 km/h), `k_hull = 0.075` per °/s, `k_tur = 0.03` per °/s.
- On firing: `M_current = max(M_current, M_target) · shotBloom`. Defaults: `shotBloom` 3.0 for mediums/TDs, 3.5 for heavies, 4.0 for derp guns.
- Decay: `M_current = max(M_target, M_current · e^(−Δt/τ))`, with τ = aim time (= WoT "factor e").
- Gunner skill affects A and τ through the crew curve.
- **Server computes the shot.** The client shows a predicted reticle, and the UI offers a "server reticle" toggle that shows the authoritative circle.
- Depression and elevation are per vehicle, defaulting to −8°/+20°, with optional per-yaw-sector limits (rear deck).

### R9. Reload (= WoT crew curve)

- `reload = base × 0.875/(0.00375·L + 0.5)`. L includes commander +10%. Multiple loaders are averaged.
- Damaged ammo rack ×1.25. Rammer −10% (not on autoloaders).
- Autoloader, autoreloader and dual-gun are implemented exactly as in section 9.
- Dual-gun defaults: inter-barrel 1.5 s, volley charge 1.0 s, volley dispersion ×1.5.
- Expose "time to full aim" and "burst / DPM" in the garage UI.

### R10. HULLDOWN baseline gun per tier (generalist medium; original values)

| Tier | Cal | AP α | HE α | AP pen | Prem pen | HE pen | Reload | DPM | Disp | Aim | Ref module HP basis |
|---|---|---|---|---|---|---|---|---|---|---|---|
| I | 37 | 40 | 52 | 45 | 65 | 19 | 1.9 | 1,263 | 0.48 | 1.9 | 40 |
| III | 47 | 60 | 78 | 65 | 90 | 24 | 2.6 | 1,385 | 0.45 | 2.0 | 60 |
| V | 75 | 115 | 150 | 100 | 135 | 38 | 4.2 | 1,643 | 0.42 | 2.2 | 115 |
| VII | 90 | 220 | 285 | 160 | 210 | 45 | 7.4 | 1,784 | 0.38 | 2.3 | 220 |
| VIII | 100 | 260 | 340 | 195 | 250 | 50 | 8.0 | 1,950 | 0.37 | 2.3 | 260 |
| IX | 105 | 320 | 420 | 225 | 290 | 53 | 8.6 | 2,233 | 0.35 | 2.2 | 320 |
| X | 120 | 400 | 515 | 255 | 330 | 60 | 9.5 | 2,526 | 0.34 | 2.2 | 400 |

Role modifiers (OUR DESIGN CHOICE):

| Role | Alpha | Reload | Pen | Dispersion | Aim time | DPM |
|---|---|---|---|---|---|---|
| Heavy | ×1.15 | ×1.2 | — | ×1.1 | ×1.15 | ≈0.96 |
| Tank destroyer | ×1.25 | ×1.15 | ×1.15 | ×0.9 | — | — |
| Light | ×0.75 | ×0.7 | ×0.9 | ×1.1 | ×0.85 | — |
| Derp | ×2.2 (HE-centred) | ×2.4 | — | — | — | — |

Check: `DPM = α·60/reload`.

---

## Open questions / uncertain items

1. **The 2-caliber normalization divisor** (`/(2T)` vs `/T`). Primary wording suggests `/(2T)`. We need an authoritative confirmation.
2. **Post-ricochet pen.** Is the 25% AP/APCR loss from 9.3 still current, or is full pen retained? This could not be re-verified. One secondary source claims later versions retain full pen.
3. **The HEAT ricochet change from 80° to 85°.** Version unknown. Also, is HEAT gap loss compounding (5% of remaining per 10 cm) or linear (50%/m)?
4. **The exact post-1.13 non-penetrating HE formula**, the minimum-damage floor, and how the Equipment-2.0 Spall Liner "+50%" maps to `K_spall`. Also whether HESH follows HE's 3× screen rule.
5. **Distance pen loss.** Exact start and end distances (50/100 m to 500 m?) and typical drop magnitudes per family.
6. **Max shell range:** ~720 m or ~744 m.
7. **Dispersion combination formula** (root-sum-square vs additive) and per-factor units. Also the 2σ outlier handling (re-roll vs redistribution), and whether WoT samples a radial normal (which the published 19.4%/4.6% figures imply) or a 2D normal.
8. **Injured crew skill:** 50% vs 0%. The 2024–2026 crew rework may have changed it.
9. **Fire:** duration, DPS, and how Fire Fighting and the extinguishers scale. Also the numeric damaged-ammo-rack reload penalty and the field-repair restore percentage (50% vs 75%).
10. **Module hit chances and module-damage values.** Ours are recalled community wiki-era values. Treat them as design defaults.
11. **Release versions** of dual-gun (1.10.1 or 1.11) and of the autoreloader introduction. Neither affects the design.
12. **Whether WoT 2.0-era updates (2025–2026) changed any core ballistics.** No evidence was found, but the search budget ran out before a full 2025–2026 patch-note sweep.
13. **Lesta / Mir Tankov divergences** (post-2022). Not researched.
14. **Team damage and ramming of allies** in current PC Random Battles. Not re-verified.

### Roblox engine references (local)

All four entries were re-checked against the local creator-docs copy by the fact-check. Raycast is documented as `thread_safety: Safe`.

- `physics/units.md`: 1 stud = 0.28 m; default gravity 196.2 studs/s² ≈ 54.9 m/s²; realistic gravity is 35 studs/s².
- `reference/engine/classes/WorldRoot.yaml`: `Raycast` (direction ≤15,000 studs, thread-safe), `Spherecast`, `Shapecast`, `GetPartBoundsInRadius`.
- `reference/engine/datatypes/RaycastParams.yaml`, `RaycastResult.yaml` and `Random.yaml`.

---

## Verification log

Fact-check date: 2026-10-05. Scope: the 15 claims that matter most for implementation. Method and constraints:

- **No reachable source:** the web-search budget was exhausted. WebFetch was blocked for WoT, Wargaming, fandom, FTR, TAP, 13disciple, gamepressure, Wikipedia and HyperX. Only GitHub and the local Roblox docs were reachable.
- **Unverified is not refuted:** "Unverified" means no independent source could be reached. It does not mean the claim is wrong. Those claims keep the author's evidence and were downgraded to Medium or Low.
- **Blitz evidence:** "Blitz tool" evidence comes from WoT Blitz, a separate game built on the same Wargaming rule family. It corroborates a claim but does not confirm it for PC.
- **API snapshot:** "WG API" means Wargaming's public Tankopedia API responses mirrored on GitHub (asia server, static version 2.55.0, May 2017). That data predates 1.13, Equipment 2.0 and the 2.0 rebalance.

| # | Claim | Verdict | Evidence (source links) |
|---|---|---|---|
| 1 | Normalization AP 5°, APCR 2°, HEAT/HE/HESH 0°. Auto-ricochet at >70° for AP/APCR and >85° for HEAT (80° when introduced in 0.8.6) | **Unverified** (High → Medium) | Author's sources could not be re-accessed. An independent secondary implementation doc gives the same 5°/2°/70°/85°, but dates 85° to 0.8.9 ([Claude-of-Tanks armor-penetration.md](https://github.com/Kevin-Liu-01/Claude-of-Tanks/blob/efd68c1b5249fb293f4d452874ba782728e7dd18/docs/history/research/armor-penetration.md)) |
| 2 | 3-caliber rule (`cal > 3T`: no ricochet; not for HEAT). 2-caliber rule normalization `n·1.4·cal/(2T)` | **Unverified** for PC (corroborated) | The Blitz tool implements exactly `cal > 3T` and `(1.4·n·cal)/(2·T)` for `cal > 2T` ([BlitzKit shader](https://github.com/blitzkit/blitzkit/blob/c70fae81622c6e55593d425bc387b159fb41d387/packages/website/src/components/Armor/components/PrimaryArmorSceneComponent/shaders/fragment.glsl)). The secondary doc above uses `/T`, so the conflict remains for PC |
| 3 | Ricochets keep flying (since 9.3). AP/APCR lose 25% of base pen. One-ricochet cap | **Unverified** (Medium → Low) | FTR 9.3 explainer unreachable. The secondary doc above claims full pen is retained in later versions (conflicting, unsourced). R2 relabelled as our design choice |
| 4 | Penetration and damage roll ±25% around the mean | **Confirmed** (bounds only) | [WG API vehicle dumps](https://github.com/aki33524/wotdatabase/tree/a024cafc1293db72521928fc5362e228377723da/API/vehicles): 2,816 [min, avg, max] entries, all with min = round(0.75·avg) and max = round(1.25·avg). The **normal shape** is unverified and was downgraded to Medium-Low; the secondary doc above assumes a uniform roll |
| 5 | Only AP/APCR lose pen with distance, linearly from ~100 m to ~500 m, with APCR losing more | **Unverified** | No reachable source. The secondary doc above agrees qualitatively. Kept at Medium/Low |
| 6 | HEAT loses ~5% pen per 10 cm (≈50%/m) after penetrating a plate | **Unverified** for PC (corroborated) | The Blitz tool applies `pen −= 0.5·pen·gap_m` after a screen ([BlitzKit shader](https://github.com/blitzkit/blitzkit/blob/c70fae81622c6e55593d425bc387b159fb41d387/packages/website/src/components/Armor/components/PrimaryArmorSceneComponent/shaders/fragment.glsl)), which is the same linear reading as R2 |
| 7 | 1.13 HE rework (June 2021) is live: screens cost 3×T and destructibles 1×T; non-pen damage uses the nominal armor at the impact point; damage is guaranteed after a screen | **Unverified** (High → Medium) | All 1.13 and Sandbox articles were unreachable. The worked example's arithmetic is consistent (100 − 3×20 = 40; CT1 100 − 20 = 80) |
| 8 | HE non-pen formula `0.5·D·(1 − d/R) − 1.1·T·K`, and R4's `K_spall` described as "tidied WoT-era classes" | **Corrected** | Formula structure corroborated by the Blitz tool (`0.5·D·(1 − d/R) − 1.1·(T_eff + T_spaced)`, same link as #6). The K table was not verified. R4's K values (1.2/1.3/1.5) contradict 4.3 (1.2/1.25/1.3/1.5), so R4 was relabelled OUR DESIGN CHOICE |
| 9 | Shell ratios (HE/AP alpha 1.2–1.4; premium alpha = AP; premium pen 1.25–1.35×; HE pen ≈ cal/2) and the tier patterns (dispersion ~0.50 → ~0.32; aim time flat at 1.5–3.0 s) | **Corrected** | [WG API vehicles and guns](https://github.com/aki33524/wotdatabase/tree/a024cafc1293db72521928fc5362e228377723da/API). HE/AP alpha median 1.33 with p10–p90 **1.20–1.59** (many 75 mm guns are 110/175). Premium alpha = AP on 98%. Premium pen median **1.35** (p10–p90 1.19–1.73). HE pen 0.505×cal. Examples 75/100/105/120/122 mm confirmed. Dispersion p10–p90 is 0.43–0.54 at tier I and **0.33–0.42** at tier X. Aim time is 1.7–2.5 s at tier I and **2.3–3.4 s** at tier X |
| 10 | Engine fire chance ~10–20%, higher for gasoline | **Confirmed** | [WG API engine modules](https://github.com/aki33524/wotdatabase/tree/a024cafc1293db72521928fc5362e228377723da/API/modules/engines): 511 engines. 20% = gasoline (307, e.g. Maybach HL, M-17); 15% (126), 12% (58) and 10% (20) = diesels (V-2, Mitsubishi, 12150L, MB 838) |
| 11 | "Wet Ammo Rack: +50% ammo-rack HP" presented as current equipment | **Corrected** | Legacy item: Equipment 2.0 (Update 1.10, Aug 2020) replaced it with Improved Configuration (+150% ammo-rack, fuel and engine durability), per [doc 05 §4.2](05-progression-economy-crew-equipment.md) (Medium; sibling doc, not independent) |
| 12 | Crew-skill curve `base × 0.875 / (0.00375·L + 0.5)`, giving ×1.000 at 100%, ×0.959 at 110%, ×1.273 at 50% and ×1.750 at 0% | **Confirmed** | Identical formula in an independent community tool ([tanktionary measure.cpp](https://github.com/IronCrossEnterprises/tanktionary/blob/bbf3fba95631b4673f61c5ff15e661af0babdb8b/wotparser/measure.cpp)). All table values and the 29.54 s worked example were recomputed |
| 13 | Dispersion is a "2D normal" with the edge at 2σ (1.3σ before 0.8.6; ~19.4% → ~4.6% at the edge). R8 claimed "2D normal + re-roll = WoT 0.8.6 behavior" | **Corrected** | Arithmetic: P(\|Z\| > 1.3) = 19.36% and P(\|Z\| > 2) = 4.55% are 1D tails. A 2D isotropic normal gives e^(−k²/2) = 43.0% and 13.5%. The published figures therefore imply a normal *radial* miss distance. 8.1, Summary #16 and R8 were fixed. The 8.6 article itself was unreachable (High → Medium) |
| 14 | Consumable cooldowns: 1.26 cut the large kits and the automatic extinguisher from 90 s to 60 s, and small items stay at 90 s. R5 gave the manual extinguisher 60 s | **Corrected** | R5 contradicted section 5.4 and [doc 05 §5 and R9](05-progression-economy-crew-equipment.md) (manual 90 s), so it was fixed to 90 s. The 1.26 date was harmonised to "CT Aug 2024, release Sept 2024". The WoT-side numbers match doc 05 but were not independently re-verified (TAP and WoT pages unreachable) |
| 15 | Roblox: 1 stud = 0.28 m; default gravity 196.2 studs/s² ≈ 54.9 m/s²; realistic gravity 35 studs/s²; Raycast direction ≤ 15,000 studs and thread-safe | **Confirmed** | Local creator-docs copy: [physics/units.md](https://github.com/Roblox/creator-docs/blob/main/content/en-us/physics/units.md) (28 cm, 196.2, 35 studs/s²) and [WorldRoot.yaml](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/WorldRoot.yaml) (`Raycast`: 15,000 studs, `thread_safety: Safe`). Derived numbers recomputed: 480 m/s = 1,714 studs/s ≈ 28.6 studs per 60 Hz step |

**Tally:** 15 claims checked. 4 confirmed, 5 corrected, 6 unverified.

**Internal contradictions fixed in "Implementation recommendations":**
- **R2, ricochet penalty:** the post-ricochet ×0.75 was labelled "= WoT 9.3 rule", while Summary #18 called it a deviation. It is now OUR DESIGN CHOICE.
- **R2, roll order:** the pen roll now happens before the step-2 ricochet test, so the ×0.75 has a value to act on.
- **R4:** `K_spall` was relabelled as our choice, because it disagrees with 4.3.
- **R5:** the post-penetration path keeps "= WoT" only for the 10-caliber length; the 0.5 m floor is flagged as unverified.
- **R5, extinguisher:** the manual extinguisher cooldown went from 60 s to 90 s, matching 5.4 and doc 05.
- **R8:** "2D normal = WoT" was replaced with radial sampling plus a config switch.
- **R1:** HESH's 3× screen multiplier is flagged as our choice.

**Arithmetic checks that passed:**
- R6 ramming example: 0.1 × 0.5 × 50 × 11.1² − 44 = 264 HP. The heavy takes 0. The "algebraically the mass-share model" identity holds.
- R6 fall threshold: 7 m/s ≈ 2.5 m.
- R10: the DPM column equals α·60/reload; role-modifier DPM for heavies is 0.96.
- R8 bloom example: √(1 + (0.07·50)²) = 3.64×.
