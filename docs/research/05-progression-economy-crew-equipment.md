# 05 — Progression, Economy, Crew, Equipment, Consumables, Missions, Achievements & Post-Battle (WoT reference → HULLDOWN)

Research date: 2026-10-05. Reference game: World of Tanks PC (Wargaming), live version **2.4 "Overdrive"** (released September 2026).
Scope: how WoT progression and economy work in 2025–2026, with history where it explains a design decision, and a concrete economy model for HULLDOWN on Roblox.
No WoT assets, names of WoT-specific items, or client-datamined data are used. Vehicle price and XP statistics come only from **Wargaming's public Tankopedia web API** responses mirrored on GitHub (see §1.3).

> **Evidence note (read first).** The network proxy blocked direct fetches of worldoftanks.*, wargaming.net, tanks.gg, reddit and the community wikis. Almost all WoT facts below come from **web-search result summaries of official WoT/WG pages**, plus a few reputable community sites. These summaries are sometimes imprecise. Each item has a confidence rating. Values marked **OUR DESIGN CHOICE** are proposals for HULLDOWN, not WoT facts. Roblox platform facts come from the local creator-docs clone, which is authoritative.

> **Fact-check pass (2026-10-05).** 15 implementation-critical claims were re-checked independently; see **Verification log** at the end. The Roblox claims were re-checked against the local creator-docs, and the Tier II–X price/XP medians were re-computed from the API dumps. Most other WoT pages (and the community mirrors) could not be opened during the fact-check, so several WoT values below are marked **unverified** and their confidence is lowered. Edits from this pass are marked "(corrected by fact-check)".

> **Corrections to the brief's premises:**
> - **"Crew 2.0" never shipped.** It was a 2021 Sandbox test that was dropped after feedback. The crew rework actually shipped in stages: 1.18.1 → 1.20.1 → 1.22.1 → April 2024 QoL → **1.26 perk system** → **2.2 (March 2026) "Crew Rework Complete"**. There was no "Update 1.25 crew rework".
> - **Field Modification went live with Update 1.14 in 2021, not 1.18.**
> - **Tier XI is real.** It arrived in **Update 2.0 (3 Sept 2025)** and has its own economy (325,000 XP and 7,400,000 credits per vehicle) and an upgrade-node system.

---

## Summary

1. **Free XP = 5% of base XP earned in each battle.** Specials and Personal Reserves can raise this. Combat XP on Elite vehicles converts to Free XP at **25 XP per 1 gold**. Gold → credits is **1 : 400**. *(High)*
2. **WoT Premium Account gives +50% credits, +50% combat XP and +50% crew XP.** It also adds three daily Premium missions, a "Reserve Stock" vault (10% of credits earned, up to 750,000 paid out every 7 days), a ×3 multiplier on the latest victory up to 5 times a day, a second map exclusion and platoon credit bonuses. 30 days = **2,500 gold**. *(High for +50%; Medium for the extras)*
3. **First victory of the day gives ×2 XP once per vehicle per day.** Events raise it to ×3–×5. **Winning adds +50% XP for each tank on the winning team.** *(High / Medium)*
4. **Price and research curve per tier (WG public API, tech-tree vehicles, median values):**

   | Tier | Research XP | Credits |
   |---|---|---|
   | II | 275 | 3,600 |
   | III | 1,300 | 41,500 |
   | IV | 3,725 | 140,000 |
   | V | 13,500 | 395,000 |
   | VI | 28,600 | 920,000 |
   | VII | 53,300 | 1,380,000 |
   | VIII | 97,400 | 2,530,000 |
   | IX | 168,700 | 3,520,000 |
   | X | 219,800 | **6,100,000 (every tier X)** |
   | XI | **325,000** | **7,400,000** |

   *(High for II–X, re-computed from the API dumps during the fact-check. Tier XI: **Medium** (corrected by fact-check). The Tier XI figures come only from search summaries of WoT 2.0 articles and could not be checked independently.)*
5. **Selling a vehicle refunds 50% of its price.** Premium vehicles are refunded in credits at half their gold value. A garage slot costs **300 gold**. *(High / Medium)*
6. **Tier IX–X are a deliberate credit sink.** WoT's economy expects roughly break-even at VIII and a loss at IX–X without Premium. Tier VIII Premium vehicles are the intended "credit farmers". WoT 2.0 cut Tier VIII–IX Premium gold prices by about 10% and raised Tier IX Premium credit income. *(Medium)*
7. **Tier XI (WoT 2.0) uses linear upgrade nodes instead of Field Modification.** Each vehicle has up to 25 nodes: small 10,000 XP, large 20,000 XP, final 25,000 XP. After all nodes are researched, the vehicle becomes "Elite" and gains Elite levels that unlock cosmetics. 2.0 launched 16 vehicles; Update 2.4 adds more. *(High for the 16-vehicle roster, node tree replacing Field Modification, and Elite cosmetics, all confirmed by fact-check. **Medium** for the node XP values and the 25-node count, which are unverified (corrected by fact-check).)*
8. **Crew today (1.26 + 2.2):**
   - Each crew member has at most **6 perks, including the zero perk**.
   - Each major qualification offers **6 individual perks + 3 group perks**. Update 2.2 added 2 more per role.
   - A secondary qualification trains up to 3 bonus perks at half speed.
   - Perks work from 1% training (since 1.20.1).
   - Since April 2024, crew efficiency is always 100%. A free recruit is fully trained.
   - Perk reset costs **100,000 credits** (was 200 gold).
   - Retraining for **200 gold** has no penalty. The credit option applies a perk-efficiency penalty that is recovered with Crew XP.
   - Classic perk XP curve: first perk ≈ **210,064 XP**, doubling for each perk after that. *(High for structure. **Medium** for the 2.2 values, such as the 100,000-credit reset, which are unverified (corrected by fact-check).)*
9. **Equipment 2.0 (Update 1.10, 4 Aug 2020):**
   - Four categories: Firepower, Survivability, Mobility, Scouting.
   - On Tier VI–X, the first slot is specialised and gives a bonus when the equipment category matches. Example: Rammer −10% reload, or −11.5% in a matching slot.
   - Equipment classes by tier: Class 3 costs **50,000 credits** (II–IV), Class 2 **300,000** (V–VII), Class 1 **600,000** (VIII–X).
   - Quality grades: Standard → Bounty → Improved (bonds); Experimental has upgrade levels I–III.
   - Demounting standard equipment costs **10 gold** (free with WoT Plus). *(High for categories and slot rules. **Medium** for the class prices, which are unverified (corrected by fact-check).)*
10. **Consumables have been reusable since 9.18.** Repair kit, first-aid kit and extinguisher have cooldowns. In **1.26**, small kits repair or heal **everything** with a **90 s** cooldown. Large kits and the automatic extinguisher have a **60 s** cooldown and passive bonuses. Small kits cost **3,000 credits**; large kits and food cost **20,000 credits or 50 gold**. *(High for 9.18 reusability. **Medium** for the 1.26 cooldowns and the prices, which are unverified (corrected by fact-check).)*
11. **Missions:**
    - **Daily:** 3 missions of rising difficulty, plus a Bonus mission. Rerolls are allowed. WoT Premium adds 3 sequential Premium missions.
    - **Personal Missions:** operations of 5 class sets × 15 missions. **Sector 3 (2.0)** has 3 operations × 3 role series (Vanguard / Ambush / Assistance) × 15 missions.
    - **Battle Pass:** 3 chapters × 50 stages × 50 points = **7,500 points**, with tokens redeemable for exclusive vehicles. *(High / Medium)*
12. **Achievements:**
    - **Mastery** compares a battle's **base XP** with the same-vehicle distribution over the last **7 days**: Ace = top 1%, I = top 5%, II = top 20%, III = top 50%.
    - **Marks of Excellence** (Tier V–X) use an exponential moving average of "combined damage" with k = 2/101, against **65 / 85 / 95** percentile thresholds over 14 days.
    - Battle Heroes have hard minimums, for example Top Gun ≥ 6 kills and Steel Wall ≥ 11 hits and ≥ 1,000 HP. *(High / Medium)*
13. **Post-battle screen (2.0):** a full-screen hangar view with these tabs: **General**, **Team Result** (detailed per-player efficiency), **Financial Report** (now has a WoT Plus line) and **Mission Progress** (Personal, daily and special missions, Tech Tree research, crew perk progress). *(High)*
14. **Monetization patterns:**
    - Premium vehicles: Tier II–IX, VIII is the core.
    - Premium Account bought in days.
    - **WoT Plus** subscription: Core about $8.99 per month, plus a Pro tier. It gives a 500 gold reserve every 7 days, free demounting, passive crew XP and a +35% XP/credits booster on one chosen tank.
    - Battle Pass (Improved Pass).
    - Holiday Ops loot boxes. These are not sold in Belgium, and every 50th box guarantees a vehicle. *(High / Medium)*
15. **Roblox constraints that change the design:**
    - **Paid random items** must disclose numerical odds, and players flagged by `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` must be given an alternative.
    - **Subscriptions** are priced either in Robux (at least 49 Robux; Regional Pricing is always on and cannot be turned off; price can change once every 60 days) or in local currency ($2.99 / $4.99 / $7.99 / $9.99 / $14.99; **price can never be changed**). *(corrected by fact-check)*
    - Purchases must be granted through `MarketplaceService.ProcessReceipt`, deduplicated by `receiptInfo.PurchaseId`.
    - DataStore values are limited to **4,194,304 characters** per key. The default per-server budgets are **60 + 40×players requests per minute**, with **separate** Read and Write budgets (`UpdateAsync` uses both), and can be changed with `DataStoreService:SetRateLimitForRequestType()`. Each key across all servers is also limited to 25 MB/min read and 4 MB/min write throughput, with each request rounded up to 1 KB. *(corrected by fact-check)*
16. **Recommended HULLDOWN model:**
    - Currencies: **Credits**, **Bullion** (premium, bought with Robux), **Vehicle XP**, **Free XP (5%)**, **Crew XP**, **Merit** (earned skill currency, the "bonds" role) and **Event Tokens**.
    - About **260 average battles** from Tier I to the first Tier XI unlock, using a compressed curve (Tier X research 31,000 XP and 2,600,000 credits; Tier XI 47,000 XP and 3,600,000 credits).
    - Tier IX–XI are a soft credit sink without Premium and profitable with it.
    - No paid random items.
17. **Keep from WoT:** 5% Free XP, first-win ×2, +50% win bonus, 50% sell refund, base-XP-percentile Mastery, damage+assist MoE, and reusable consumables.
18. **Drop or soften:** long credit walls, retraining penalties, gold-gated perk resets, gold demount fees and loot boxes. These are the parts WoT itself has been removing since 2023.

---

## Detailed findings

### 1. Research & progression

#### 1.1 Vehicle XP vs Free XP vs Crew XP
- **Current behavior:**
  - **Combat XP (vehicle XP)** is earned per vehicle. It researches that vehicle's modules and the next vehicles in the line.
  - **Free XP** is universal. It can research any standard vehicle or module, speed up crew training, and pay for Field Modification and Tier XI nodes. Since 2.0, Tier XI nodes "use XP".
  - **Crew XP** is earned by the crew and trains perks.
- **Values:**
  - **5% of base XP** earned in a battle becomes Free XP. Specials and Personal Reserves can raise the percentage.
  - Conversion: **25 Combat XP + 1 gold = 25 Free XP**. Only XP on **Elite** and Premium vehicles can be converted.
  - XP-conversion specials ("XP Fever", conversion discounts) run regularly.
- **History:** the 5% rule has been unchanged for many years.
- **Confidence:** High.
- **Sources:**
  - [XP conversion July 2024 (WoT EU)](https://worldoftanks.eu/en/news/specials/xp-conversion-july-2024/)
  - [Types of Experience (WoT Asia)](https://worldoftanks.asia/en/news/specials/xp-conversion-july-2024)
  - [Currency Exchange and Resource Conversion (WoT EU)](https://worldoftanks.eu/en/content/guide/wot_economy/conversion/)
  - [Economy in World of Tanks](https://worldoftanks.eu/content/guide/economy/currency-and-resources/)

#### 1.2 Modules, elite status, research flow
- **Current behavior:**
  - Each tech-tree vehicle has researchable modules: gun, turret, engine, suspension and radio. Some modules unlock the next vehicles.
  - Once **all modules and all follow-on vehicles** are researched, the vehicle becomes **Elite**. Its XP can then be converted to Free XP, and on Tier VI–X Field Modification opens.
  - Before 2.0, the median Tier II–IX vehicle had **4–7 researchable modules**; Tier X vehicles generally had none left to research.
  - **WoT 2.0 "streamlined" modules**: stock vehicles are stronger, clutter modules were removed and early tiers progress faster. The exact new module counts and costs were not found.
- **Module XP per vehicle** (median total, WG public API snapshot from before 2.0):

  | Tier | II | III | IV | V | VI | VII | VIII | IX |
  |---|---|---|---|---|---|---|---|---|
  | Module XP | 670 | 7,475 | 12,630 | 20,865 | 39,857 | 62,560 | 111,735 | 155,150 |

  So in classic WoT, module XP was **comparable to or larger than** the cost of the next vehicle. Stock grind was a major time sink, and 2.0 explicitly reduced it.
- **Confidence:** High for the classic numbers. Low for the post-2.0 module costs, which were not retrieved.
- **Sources:**
  - [2.0 Hub](https://worldoftanks.eu/en/news/updates/2-0-hub/)
  - [WoT 2.0 Tech Tree explained (nerdschalk)](https://nerdschalk.com/world-of-tanks-2-0-tech-tree-explained-free-branch-tier-xi-and-new-mechanics/)
  - [Update 2.0: The Biggest Vehicle Rebalance](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)
  - API data per §1.3

#### 1.3 Research cost and purchase price per tier
**Method.**
- I took Wargaming's **public Tankopedia API** (`/wot/encyclopedia/vehicles/`) responses mirrored on GitHub:
  - `aki33524/wotdatabase/API/vehicles/1..6`: 508 vehicles; static asset version 2.55.0. The repo's last commit is May 2017, so this is a **2017** snapshot (corrected by fact-check).
  - `GuilleHoardings/wot_tank_data/wot_data.csv`: 441 distinct tech-tree vehicles. The last commit is Aug 2021, "patch 14.0.2", so this is a **2021** snapshot (corrected by fact-check).
- I filtered to non-premium, non-gift vehicles.
- **Research XP** is the lowest `prices_xp` entry over the vehicle's parents.
- The two snapshots agree to within about 2% on prices. Tech-tree credit prices have historically been very stable; Tier X has been 6,100,000 for every vehicle for many years.

| Tier | Research XP min / **median** / max | Credit price min / **median** / max | Premium gold price, median (n) |
|---|---|---|---|
| I | starter (free) | 0 | — |
| II | 220 / **275** / 280 | 3,000 / **3,600** / 4,200 | 750 (1) |
| III | 1,000 / **1,300** / 1,750 | 30,000 / **41,500** / 53,000 | 900 (4) |
| IV | 2,300 / **3,725** / 5,250 | 110,000 / **140,000** / 185,000 | 1,000 (1) |
| V | 10,200 / **13,500** / 19,340 | 315,000 / **395,000** / 445,000 | 1,500 (7) |
| VI | 13,000 / **28,600** / 49,050 | 875,000 / **920,000** / 975,000 | 3,600 (6) |
| VII | 22,200 / **53,300** / 93,000 | 1,300,000 / **1,380,000** / 1,490,000 | 6,625 (4) |
| VIII | 53,000 / **97,400** / 118,600 | 2,350,000 / **2,530,000** / 2,730,000 | 8,750 (13); typical 7,200–7,450 |
| IX | 110,000 / **168,720** / 217,500 | 3,400,000 / **3,520,000** / 3,700,000 | — (2.0: Tier IX Premiums exist; prices cut about 10%) |
| X | 160,000 / **219,830** / 301,000 | **6,100,000** (all) | — |
| **XI (2.0)** | **325,000** (earned on a Tier X) | **7,400,000** | — |

- **Shape of the curve.**
  - Credits grow about **×2.5–3.5 per tier at II–V** and about **×1.4–1.8 per tier at VI–X**. The step from IX to X is **×1.73**.
  - XP grows about **×1.7–3.6 per tier**.
  - Researching and buying all **15 researchable** Tier XI vehicles costs 4,875,000 XP and 111,000,000 credits (15 × 325k and 15 × 7.4M). The 16th Tier XI is the Personal-Missions reward vehicle.
- Recently added branches can deviate. One 2025 US medium branch reportedly costs Tier VIII 100,000, Tier IX 180,000–300,000 and Tier X 250,000–600,000 XP (Medium).
- **Confidence:** High for the classic curve; the fact-check re-computed every Tier II–X min/median/max from the dumps and all of them match. **Medium** for the Tier XI numbers (corrected by fact-check). The "several independent sources" were search summaries that could not be opened, and sibling doc 03 cites this doc for the same figures, so it is not independent. Medium on whether 2.0 changed Tier II–X prices: no evidence that it did, apart from the module streamlining.
- **Sources:**
  - [aki33524/wotdatabase (GitHub, WG API dumps)](https://github.com/aki33524/wotdatabase)
  - [GuilleHoardings/wot_tank_data (GitHub, WG API CSV)](https://github.com/GuilleHoardings/wot_tank_data)
  - [Update 2.0: Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/)
  - [Tier XI guide (nerdschalk)](https://nerdschalk.com/world-of-tanks-2-0-tier-xi-tanks/)
  - [XP for new USA medium branch (TAP)](https://thearmoredpatrol.com/2025/12/18/wot-xp-required-to-research-the-new-%F0%9F%87%BA%F0%9F%87%B8-usa-medium-tank-branch/)
  - [Update 2.0 vehicle rebalance (premium prices)](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)

#### 1.4 Selling, buyback, garage slots
- **Selling:**
  - Tech-tree vehicles sell for **50%** of their credit price.
  - Premium vehicles sell for credits equal to half their gold value at 400 credits per gold. Example from WG: a 10,000-gold tank sells for 2,000,000 credits.
- **Restoration (buyback):**
  - Premium vehicles can be restored for **72 h** after sale.
  - Rare vehicles can be restored at any time, but only one every 3 days. The restore price is the sell value plus a fee; one source says +10% (Medium).
- **Garage slots:** **300 gold** for 1 slot. I could not confirm whether any purchase bundles a free slot (Low).
- **Confidence:** High for 50%; Medium for the other details.
- **Sources:**
  - [Economy in WoT (Asia)](https://worldoftanks.asia/content/guide/wot_economy/)
  - [WG support 23827](https://eu.wargaming.net/support/en/products/wot/article/23827)
  - [Gold Economy (WG wiki PL)](https://wiki.wargaming.net/pl/Gold_Economy)

#### 1.5 Premium Account (WoT Premium) and WoT Plus
- **WoT Premium Account** (reworked in Update 1.5, 2019):
  - **+50% combat XP, +50% crew XP and +50% credits.**
  - A chain of **3 Premium daily missions**.
  - An **extra ×3 multiplier on XP from the latest victorious Random Battle, up to 5 times a day**.
  - **2 map exclusions** instead of 1.
  - **Reserve Stock:** 10% of credits earned go to a vault, paid out up to 750,000 within 7 days.
  - **Platoon:** the PA holder gets +15% credits; platoon-mates without PA get +10%.
- **WoT Premium prices** (gold):

  | Days | 1 | 3 | 7 | 30 | 180 | 360 |
  |---|---|---|---|---|---|---|
  | Gold | 250 | 650 | 1,250 | **2,500** | 13,500 | 24,000 |

  Real-money prices on NA are reported as 30 d ≈ $12.59, 90 d ≈ $33.89, 180 d ≈ $57.49 and 360 d ≈ $96.49 (Medium; these change).
- **WoT Plus** (subscription, introduced 1.20.1, 2023):
  - **Gold Reserve:** up to **500 gold every 7 days**, earned in Random, Onslaught and Frontline.
  - **Free demounting** of equipment, except Improved and Experimental level II–III.
  - **Passive crew XP:** 40 Crew XP every 5 minutes for one vehicle's crew, even while offline.
  - Exclusive Tier VIII and IX vehicles.
  - A **Core** tier at about **$8.99/month**, and a **Pro** tier at about $90 for 6 months or $150 for 12 months. Pro adds a **+35% XP and credits "Pro Boost"** on one chosen Tier I–X vehicle and extra Battle Pass points.
- **Confidence:** High for +50%. Medium for the extras and prices.
- **Sources:**
  - [1.5 WoT Premium Account](https://worldoftanks.eu/news/general-news/1-5-wot-prem-account/)
  - [Release notes 1.5](https://worldoftanks.asia/content/docs/release_notes/15/)
  - [Survival Guide: Premium Time](https://worldoftanks.com/en/content/player-guide/written-guide/survival-guide-premium-time/)
  - [WoT Plus guide](https://worldoftanks.eu/en/news/general-news/wot-plus-guide/)
  - [Introducing WoT Plus](https://worldoftanks.com/news/general-news/1-20-1-subscription-wotplus/)

#### 1.6 Credit income vs costs per tier; the Tier X credit sink
- **Current behavior:**
  - Income scales with damage, spotting and assist. Costs are **repair**, which is proportional to HP lost (full price if destroyed), **ammo** (a standard shell costs more than 1,000 credits at Tier X), and **consumables**.
  - Community and official guidance: Tier V–VII earn the most for a tech-tree tank. An average Tier V–VI battle without Premium nets about **10–15k credits**, and a good one 20–40k.
  - **Tier VIII Premiums** net about **30–40k on an average battle**.
  - **Tier IX–X lose credits on average without Premium** (by design). A typical Tier X credit coefficient of about 0.5 is cited (Low confidence).
- **WoT 2.0:** Tier IX Premiums now "earn more credits per battle to match their greater repair and ammo costs". No general repair-cost change was found.
- **Confidence:** Medium for the qualitative structure. Low for specific coefficients and per-tier repair figures, which were not retrieved from an official source.
- **Sources:**
  - [Steam discussion on Tier VIII–X ammo](https://steamcommunity.com/app/1407200/discussions/0/591769703346667294/)
  - [Economy guide 2026 (gametruth)](https://www.gametruth.com/guides/world-of-tanks-economy-guide-2026-credit-farming-bonds-and-free-xp/)
  - [Money-making tanks (gamepressure)](https://www.gamepressure.com/worldoftanks/money-making-tanks/z2715e)
  - [Update 2.0 rebalance](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)

#### 1.7 Tier XI economy (WoT 2.0, Sept 2025 → 2.4, Sept 2026)
- **Unlock:**
  - Earn **325,000 XP on a Tier X** (Free XP can also be used), then pay **7,400,000 credits**.
  - At 2.0 launch there were **16 vehicles**: 7 heavy, 5 medium, 3 TD and 1 light. One of them is the PM 3.0 reward "Black Rock".
  - **Update 2.1.1** (January 2026) added more Tier XIs. **Update 2.4 "Overdrive"** (September 2026) adds about 5–6 more, each with its own mechanic (adaptive autoloaders, alternative fire modes, rocket assist, recon systems).
- **Progression after unlock:**
  - A **linear upgrade-node track of up to 25 nodes**: **small 10,000 XP** (stat increase), **large 20,000 XP** (bigger stat increase or mechanic upgrade) and a **final node of 25,000 XP** (major special-mechanic upgrade). Upgrades are "purely positive", with no trade-offs.
  - When every node is done, the vehicle becomes **Elite**. Further battles then raise its **Elite level**, which unlocks stat trackers, volumetric 2D styles and gun sleeves.
- **Matchmaking in 2.0:**
  - Mostly **±1 tier**, with some ±2 for variety.
  - Class limits: at most 3 LT (at most 1 wheeled), 5 TD and 3 SPG.
  - In 2.4, light tanks get role subclasses (scout / versatile / support), with **at most 2 LTs per team**.
- **No Tier XI repair or ammo figures were found.**
- **Confidence:** **Medium** for unlock costs and node XP, which are unverified (corrected by fact-check; previously High). **High** for the launch roster (16 vehicles: 7 HT, 5 MT, 3 TD, 1 LT), the upgrade tree replacing Field Modification, and the Elite rewards (stat tracker, volumetric 2D styles, gun sleeves). These are confirmed by the narration of WG's official "Update 2.0: Overview" video. Medium for node counts per vehicle and the 2.4 numbers.
- **Sources:**
  - [Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/)
  - [TAP: XP needed for Tier XI upgrades](https://thearmoredpatrol.com/2025/09/01/wot-how-much-experience-is-needed-for-tier-xi-upgrades/)
  - [Tier XI progression nodes (gaminggearguru)](https://gaminggearguru.com/tier-xi-progression-nodes-upgrades/)
  - [mmos.com 2.0 overview](https://mmos.com/news/world-of-tanks-update-2-0-brings-first-ever-tier-xi-tanks-and-a-full-systems-overhaul)
  - [Update 2.4: Overdrive](https://worldoftanks.com/en/news/updates/wot-2-4/)
  - [MassivelyOP on 2.4](https://massivelyop.com/2026/08/16/world-of-tanks-biggest-update-of-2026-is-coming-with-wait-for-it-more-tanks/)

#### 1.8 Update 2.0 "gift" and onboarding
- Update 2.0 gave each player a **free, fully researched Tier VI–X tech-tree branch**. Veterans got 1 branch plus resources; newcomers got 2 branches plus premium tanks.
- **Lesson for us:** WoT itself now treats the classic grind as too long for retention and hands out a full branch.
- **Confidence:** Medium.
- **Sources:**
  - [Claim the Biggest Gift](https://worldoftanks.com/en/news/general-news/update-2-0-gift/)
  - [nerdschalk 2.0 launch](https://nerdschalk.com/world-of-tanks-2-0-launches-free-tech-trees-tier-xi-tanks-and-a-major-overhaul/)

### 2. Base XP / credit formulas

#### 2.1 What earns XP and credits
- **Current behavior.** XP and credits come from:
  - **damage dealt**, with more for higher-tier targets;
  - **critical hits on modules and crew**;
  - **spotting enemies**, with extra for spotting SPGs;
  - **damage allies deal to targets you spotted** (spotting assist);
  - **damage dealt to tracked targets** (track assist);
  - **stun assist** (SPG);
  - **kills**;
  - **base capture points**, proportional to time spent in the circle;
  - **base defence**: resetting capture points by damaging cappers;
  - a **win bonus of +50%** applied to each tank on the winning team.
- A classic rule: damage to enemies that teammates are spotting, but you are not, gives reduced XP (cited as 50%). This is an older community-wiki claim (Low).
- **Blocked damage:** no official source states that damage blocked by armour gives base XP or credits directly. It feeds missions and achievements (Steel Wall, "deal + block X HP" missions). Treat any direct reward as **unconfirmed** (Low).
- **Exact formula:** WG has never published one; only coefficients per action are community-estimated. I am **not** quoting coefficients.
- **Confidence:** High for the list of sources. Low for any exact coefficient.
- **Sources:**
  - [Battle Mechanics (WoT fandom, community)](https://worldoftanks.fandom.com/wiki/Battle_Mechanics)
  - [WoT Console: how to earn XP](https://modernarmor.worldoftanks.com/support/en/products/wotx/article/313/)
  - [WoT EU "choose your difficulty" missions (deal + block)](https://worldoftanks.eu/en/news/specials/experience-the-battle-special/)

#### 2.2 Multipliers
- **First victory of the day** is ×2 XP **per vehicle per day**. Specials raise it to ×3 or ×5 (anniversaries, Golden Week), sometimes with limits such as "up to 30 times per account".
- **Premium Account:** +50% XP, crew XP and credits; plus the ×3 "latest victory" bonus up to 5 times a day.
- **Personal Reserves** last 1 hour. Standard versions give **+50% combat XP**, **+200% Free XP or Crew XP** and **+50% credits**; "Improved" versions are stronger (values not retrieved).
- **WoT Plus Pro Boost:** +35% XP and credits on one chosen vehicle.
- **Premium vehicles:** a higher credit coefficient and **+50% crew XP**. Lower-tier Premiums historically got larger XP coefficient bonuses. Some Tier VIII Premiums have **preferential matchmaking** (at most +1 tier).
  - Premium vehicles have no modules to research. "Accelerated Crew Training" routes the vehicle's XP to the crew member with the least XP.
- **Confidence:** High for the first win and Premium Account. Medium for the rest.
- **Sources:**
  - [XP Fever: Bonuses Edition](https://worldoftanks.eu/en/news/specials/xp-fever-november-bonus/)
  - [Personal Reserves](https://worldoftanks.eu/en/content/guide/economy/personal-reserves/)
  - [1.18.1 improved personal reserves](https://worldoftanks.eu/en/news/general-news/1-18-1-improved-personal-reserves/)
  - [Premium vehicle improvements](https://worldoftanks.com/en/news/general-news/premium-vehicle-improvements/)
  - [Survival Guide: Premium Tanks](https://worldoftanks.com/en/content/player-guide/written-guide/suvival-guide-premium-tank/)

### 3. Crew

#### 3.1 Classic system (≈2010–2022) and why it changed
- **Classic behavior:**
  - Each crew member had a **major qualification**: 50% (free), 75% (20,000 credits, "Regimental School") or 100% (200 gold, "Tank Academy").
  - Training was XP-driven up to 100%. **Skills and perks** were then trained in sequence: the first at about **210,064 XP**, with each later one costing **double**.
  - **Skills** (Repairs, Camouflage) worked proportionally to training. **Perks** (Sixth Sense, Brothers in Arms) only worked at 100%.
  - The Commander gave +10% to the other crew members' qualification. Food, Ventilation and Brothers in Arms each added more.
  - Retraining to another vehicle cost a penalty (−10/−20% qualification by vehicle type for credits, and so on).
- **Pain points that WG acknowledged in later news posts:**
  - Sixth Sense was mandatory.
  - The zero-perk was locked.
  - Retraining penalties discouraged playing new vehicles.
  - Too many clicks.
  - Crew XP beyond the perk cap was wasted.
- **Crew 2.0 (2021 Sandbox):**
  - Proposed crew levels, an "Instructor" layer and a talent tree. **Not released.**
  - Players objected to: zero-perk XP not counting in the conversion, no bonus for a fully trained commander, random instructor skills, skill effectiveness compared with the old system, and leftover old crews.
- **Confidence:** High for structure. Medium for the exact penalty percentages.
- **Sources:**
  - [Crew Training (WoT)](https://worldoftanks.com/en/content/guide/general/crew_training/)
  - [How crew training works (13DISCIPLE)](https://www.13disciple.stream/crew-training.html)
  - [Sandbox 2021: Crew 2.0 results](https://worldoftanks.com/news/updates/crew-2-0-results/)
  - [Crew 2.0 feedback (Asia)](https://worldoftanks.asia/news/general-news/sandbox-crew-2-0-feedback/)
  - [Storm on crew retraining (FTR 2015)](http://ftr.wot-news.com/2015/02/02/crew-role-retrain-to-cost-500-gold-storm-explains/)

#### 3.2 The staged rework (what actually shipped)

| Update / date | Change |
|---|---|
| **1.18.1** (2022) | **Sixth Sense became a built-in commander feature.** A commander whose zero-perk was Sixth Sense can pick any other zero perk. |
| **1.20.1** (2023) | **All perks work from 1% training** and scale with training. The major qualification level affects nearly all perks (not Brothers in Arms). **No XP penalty for ending a battle with injured crew.** WoT Plus launched. |
| **1.22.1** (Oct 2023) | Crew interface rework with fewer clicks. Training options: Rapid Courses = 50% free, Regimental School = 75% for 20,000 credits, Tank Academy = 100% for 200 gold. Universal crew books added: **Booklet 20,000 XP** and **Guide 100,000 XP** per member. Several books can be used at once. |
| **April 2024 crew update** | All crew members between 50% and 100% were raised to **100%**. **Free recruitment of fully trained crew** (first perk can be trained at once). **No penalty when retraining for 200 gold** or with retraining orders. A credit retrain applies a perk-efficiency penalty recovered through a **100,000 Crew XP "perk efficiency pool"**. A crew member covering two seats can re-specialise without losing perks. |
| **1.26** (Sept 2024) | New perk system, detailed below. |
| **2.2 "Power Up!"** (March 2026) | **10 new perks**, 2 per major qualification. Perk reset now costs **100,000 credits** (was 200 gold), with no XP loss. A barracks button dismisses crew who are too inexperienced to have a first perk. Some sources also mention Tank Academy retraining for credits. |

- **Confidence:** High for the order of events. Medium for the 2.2 values (100,000-credit reset, 10 new perks), which are unverified (corrected by fact-check). Medium for the 2.2 retraining details, where sources conflict. One TAP article describes a 40% perk-efficiency penalty recovered over 40,000 Crew XP for one method; another says a 20,000-credit option with −10% perk XP.
- **Sources:**
  - [1.18.1 Sixth Sense](https://worldoftanks.eu/en/news/general-news/1-18-1-sixth-sense-perk/)
  - [1.20.1 Crew Improvements](https://worldoftanks.com/en/news/general-news/crew-perk-system/)
  - [1.22.1 Crew Interface Rework](https://worldoftanks.com/en/news/general-news/crew-interface-rework/)
  - [Crew Update April 2024](https://worldoftanks.com/en/news/general-news/crew-update-april-2024/)
  - [Crew Perks Update 1.26](https://worldoftanks.com/en/news/general-news/new-crew-perks-1-26/)
  - [Release Notes 1.26](https://worldoftanks.com/en/content/docs/release_notes/release-notes-1-26/)
  - [Crew Rework Complete (2.2)](https://worldoftanks.asia/en/news/general-news/crew-perks-expansion-2026/)
  - [Steam news 2.2](https://store.steampowered.com/news/app/1407200/view/519737782627730067)
  - [TAP 2.2 crew details](https://thearmoredpatrol.com/2026/02/13/wot-10-new-skills-and-crew-system-improvements-in-update-2-2/)

#### 3.3 Current perk structure (1.26 + 2.2)
- **Structure:**
  - Each crew member can train **up to 6 perks, including zero perks**.
  - XP previously invested in perks beyond 6 was compensated as national crew books at **"tanker XP ÷ 4.5"**.
  - Directives can no longer grant a 7th perk.
  - Each **major qualification** chooses from **6 individual perks + 3 group perks** (1.26); **2.2 adds 2 individual perks per qualification**.
  - **Group perks** (Brothers in Arms, Repairs, Concealment) reach 100% effect only when **every crew member** has them fully trained.
  - **Shared-qualification rule:** if two crew share a qualification (for example two Loaders), both must train a perk for it to reach 100%.
  - **Bonus perks:** a crew member with additional qualifications trains up to **3 bonus perks** at **50% speed**, with no Crew XP cost.
  - **Each percentage point of crew efficiency above 100% amplifies every perk except Brothers in Arms.**
  - Resetting perks now includes zero perks. After the 1.26 launch there was a 30-day period of unlimited free resets; after that each crew member gets one free reset, then a paid reset (100,000 credits since 2.2).
- **Perk values (fully trained) that were sourced:**

  | Role | Perk | Effect |
  |---|---|---|
  | Commander | Recon | +2% view range; −20% penalty from damaged observation devices |
  | Commander | Practicality | −10% consumable cooldown |
  | Commander | Emergency | 1.26: SPG-fire alert with a 0.1 s delay and shot direction; −10% stun effect. 2.2 sources describe it, or a sibling perk, as "+5% crew efficiency bonus for 15 s after taking damage" (conflicting) |
  | Commander | Mentor | +20% XP for all crew members (2.2 sources). Sources also mention letting the Commander replace knocked-out members at 65% effectiveness |
  | Gunner | Snap Shot | −7.5% dispersion during turret rotation |
  | Gunner | Deadeye | −3.5% dispersion when stationary, starting 3 s after stopping |
  | Gunner | Quick Aiming | +2.5% aiming speed and turret traverse |
  | Gunner | Coordination (2.2) | +12.5% aiming speed for 15 s after you spot an enemy |
  | Driver | Clutch Braking | +5% hull traverse |
  | Driver | Smooth Ride | +20% ramming damage dealt; −25% ramming damage taken; −50% suspension ram damage |
  | Driver | Engineer | +1 km/h top forward and reverse speed; −20% damaged-engine penalty |
  | Loader | Intuition | −60% time to change the loaded shell type |
  | Loader | Close Combat | −2.5% reload within 50 m of an enemy |
  | Loader | Ammo Tuck | +2% to minimum potential damage and penetration |
  | Loader | The Second Chance (2.2) | −2.5% reload for the next shell if the previous shot did no damage |
  | Radio Operator | Situational Awareness | +3% view range |
  | Radio Operator | Firefighting | Now an individual Radio Operator perk; +80% extinguishing speed |
  | Group (1.26) | Brothers in Arms | +5% crew-efficiency bonus when the whole crew has it |
  | Group (1.26) | Concealment | Sources say "+80% concealment" when full, which is probably mis-summarised (Low) |
  | Group (1.26) | Repairs | Value not retrieved |
  | New in 2.2 | Hold the Line | +5% crew-efficiency bonus while the enemy has 3 or more vehicles more than your team |
  | New in 2.2 | Bulletproof | +2.5% crew-efficiency bonus once blocked damage exceeds your starting HP |

- **Confidence:** High for the structure. Medium for individual values, because summaries sometimes merge the 1.26 and 2.2 text.
- **Sources:** as in 3.2, plus [TAP 1.26 CT](https://thearmoredpatrol.com/2024/08/10/wot-1-26-common-test-crew-evolution-new-perk-system/).

#### 3.4 Crew XP, books, injuries, directives
- **Crew XP:**
  - A battle's crew XP equals the vehicle's earned XP. The Premium Account adds +50% and Premium vehicles add +50%.
  - "Mentor" and Personal Reserves (+200%) increase it further.
  - Elite or Premium vehicles can route XP through accelerated training.
- **Crew books:**
  - **Booklet 20,000 XP** and **Guide 100,000 XP**, each to every crew member. Both have national and universal versions.
  - **Manual 250,000 XP** to each member.
  - A **Personal Training Manual** goes to a single chosen member.
  - Books come from events, Rewards for Merit, missions and the shop; some can be bought for credits.
- **Injuries:** an injured crew member works at reduced or zero effectiveness until healed by a first-aid kit. Since 1.20.1, **injuries no longer reduce post-battle XP**.
- **Directives** (since 9.19, 2017):
  - One-battle boosters for **Tier V–X**.
  - **Crew directives** boost a trained perk, or activate it if untrained. They are sold for credits (current); older sources say bonds.
  - **Equipment directives** boost mounted equipment and are sold for **bonds**.
  - Original 9.19 price range: **2–12 bonds**. Improved equipment cost 3,000–5,000 bonds.
- **Confidence:** High for books. Medium for directive pricing.
- **Sources:**
  - [1.5.1 Crew Books](https://worldoftanks.eu/en/news/general-news/1-5-1-crew-books/)
  - [1.22.1 rework](https://worldoftanks.com/en/news/general-news/crew-interface-rework/)
  - [Directives guide](https://worldoftanks.com/en/content/guide/general/directives/)
  - [9.19 directives (mmos.com)](https://mmos.com/news/world-tanks-release-update-9-19-improved-equipment-directives)

### 4. Equipment

#### 4.1 Equipment 2.0 (Update 1.10, released 4 Aug 2020)
- **Categories:** **Firepower, Survivability, Mobility, Scouting.** Exceptions:
  - Improved Rotation Mechanism counts as both Mobility and Firepower.
  - Improved Ventilation counts as all four.
- **Specialised slots:**
  - On **Tier VI–X**, the **first** equipment slot has a category.
  - Matching equipment gets a larger bonus, typically **+15% of the base effect**: 10% → 11.5%, 25% → 27.5%.
  - Vehicles have 3 slots. Under 2.0 the slot specialisation is set per vehicle by role.
- **Class-dependent values:** some items scale by vehicle class. For example, the camo net is strongest on TDs.
- **Equipment classes** (by vehicle tier and price):

  | Class | Price | Mounts on |
  |---|---|---|
  | 3 | **50,000 credits** | Tier II–IV and some higher |
  | 2 | **300,000 credits** | Tier V–VII and some higher |
  | 1 | **600,000 credits** | Tier VIII–X |

  Spall Liner and Camouflage Net are exceptions. Spall Liner comes in Light, Medium, Heavy and Superheavy versions by class and weight: for example, Heavy is for HT/TD under 75 t and Superheavy for over 75 t.
- **Quality grades:**
  - **Standard** (credits).
  - **Bounty** (event or Battle Pass): Tier II effect level.
  - **Improved / Trophy** (bonds, 3,000–5,000): Tier III effect level.
  - **Experimental** (Steel Hunter and other events): has **upgrade levels I–III**. Level I = standard, II = bounty, III = improved.
    - Upgrade costs: I→II **400 components**; II→III **2,000 components**.
    - Disassembly yields 100 / 400 / 1,600 components for levels I / II / III.
    - Experimental items combine two stat sets, e.g. "Fire-Control System" = gun-laying drive + vertical stabiliser.
- **Demounting:**
  - Standard and bounty items: **10 gold**, a **Demounting Kit**, or **free with WoT Plus**.
  - Improved items: demounted for **bonds**; 200 bonds is cited (Medium).
  - Destroying an item is free.
- **Why WG made Equipment 2.0:** it replaced the old "every tank runs Rammer + Vents + GLD/VStab" monoculture with category choice. It made equipment cheaper on low and mid tiers and added new items such as Turbocharger, Improved Hardening and Improved Configuration.
- **Confidence:** High for the categories, specialised slots and grades. **Medium** for the class prices (50k / 300k / 600k) and the Experimental component costs, which are unverified (corrected by fact-check).
- **Sources:**
  - [1.10 list of changes](https://worldoftanks.com/en/content/docs/release_notes/update-1-10-list-of-changes/)
  - [How Equipment 2.0 works (WG support)](https://www.wargaming.net/support/en/products/wot/article/33291/)
  - [Equipment guide](https://worldoftanks.com/en/content/guide/game-mechanics-and-achievements/equipment/)
  - [Sandbox results](https://worldoftanks.com/en/news/updates/sandbox-equipment-2-0-results/)
  - [1.10 Equipment 2.0](https://worldoftanks.eu/en/news/general-news/1-10-equipment-2-0/)
  - [Demount/destroy (WG support)](https://www.wargaming.net/support/en/products/wot/article/15010/)
  - [Experimental Equipment guide](https://worldoftanks.eu/en/news/general-news/experimental-equipment-guide/)
  - [dsogaming 1.10](https://www.dsogaming.com/news/world-of-tanks-update-1-10-detailed-will-be-the-biggest-update-to-date/)

#### 4.2 Equipment effects
Values are given as standard / in a matching (bonus) slot, or by tier class.

| Equipment | Category | Effect | Conf. |
|---|---|---|---|
| Gun Rammer | Firepower | **−10% / −11.5% reload time** | High |
| Enhanced Gun Laying Drive | Firepower | Faster aiming; exact 2.0 value not retrieved | Low |
| Improved Aiming | Firepower | **−5% / −7% aiming-circle size** (summary) | Medium |
| Vertical Stabilizer | Firepower | **−20% dispersion while moving or traversing** (reported −23% in bonus slot; one source says it has no bonus) | Medium |
| Improved Rotation Mechanism | Mobility + Firepower | **+10% / +12.5%** turret (or casemate gun) traverse and hull traverse; **−10% / −12.5%** movement and turret-rotation dispersion | Medium |
| Improved Ventilation | All four | **+5% / +6% crew efficiency** | High |
| Coated Optics | Scouting | **+10% / +11.5% view range** | High |
| Binocular Telescope | Scouting | **+25% / +27.5% view range** after the hull has been stationary 3 s | High |
| Camouflage Net | Scouting | Bonus after 3 s stationary. **TD +15%, LT/MT +10%, HT/SPG +5%** (one source gives +5% / +7.5% by class) | Medium |
| Commander's Vision System | Scouting | **−15% / −20%** concealment of enemies behind foliage; **−10% / −12.5%** concealment of moving enemies | Medium |
| Low Noise Exhaust System | Scouting | Reduces the camo loss from moving (a 55% figure was reported) | Low |
| Turbocharger | Mobility | **+7.5% / +10% engine power**; **+4 / +5 km/h** top forward speed; **+2 / +3 km/h** reverse | Medium |
| Improved Hardening | Survivability | **+8% / +10% vehicle HP**; +10% load capacity; **+50% / +65%** suspension durability; −50% / −65% hull damage from suspension hits; +15% / +20% suspension repair speed; full suspension HP after repair | Medium |
| Improved Configuration ("Modified Configuration") | Survivability | **+45% repair speed**; **+150%** ammo rack, fuel tank and engine durability; **−65%** loading and engine-power penalties from damaged modules; **−65%** engine fire chance | Medium |
| Spall Liner (4 weight versions) | Survivability | **+50% / +60% protection** from HE and ramming damage; **−10% / −15%** stun duration; −20% / −25% additional stun duration | Medium |

- **Sources:**
  - [Equipment guide](https://worldoftanks.com/en/content/guide/game-mechanics-and-achievements/equipment/)
  - [Sandbox results](https://worldoftanks.com/en/news/updates/sandbox-equipment-2-0-results/)
  - [WG support 33291](https://www.wargaming.net/support/en/products/wot/article/33291/)
  - [Bounty Equipment (WG wiki)](https://wiki.wargaming.net/en/Bounty_Equipment_(WoT))
  - [TAP: Equipment 2.0 conversion](https://thearmoredpatrol.com/2020/07/31/equipment-2-0-is-here-what-will-happen-to-your-current-equipment/)

#### 4.3 Field Modification (Tier VI–X; live since Update 1.14, 2021)
- **Current behavior:**
  - Opens once the vehicle is **Elite**.
  - Each level is a binary choice between two small stat tweaks, which can be swapped freely at any time. The tweaks depend on the vehicle's combat role.
  - Levels are unlocked with Combat XP or Free XP.
  - Some steps are **dual modifications**, bought with credits, that trade one stat for another.
- **Levels:** Tier VI–VII have **4**, Tier VIII **6**, Tier IX–X **8**.
- **Reported XP per level:**

  | Tier | VI | VII | VIII | IX | X |
  |---|---|---|---|---|---|
  | XP per level | 3,500 | 7,000 | 11,500 | 20,000 | 28,000 |

  These come from a community guide. Treat them as the per-level step cost (Medium).
- **Tier XI** replaces Field Modification with upgrade nodes (§1.7).
- **Confidence:** Medium.
- **Sources:**
  - [Improved Field Modification: How It Works (1.14)](https://worldoftanks.com/en/news/updates/update-1-14-field-modification/)
  - [Field Modification sandbox](https://worldoftanks.eu/en/news/general-news/sandbox-field-modification/)
  - [Field Mods explained (overtankpro)](https://www.overtankpro.com/guides/field-modifications-explained)

### 5. Consumables
- **Reusability:**
  - Since **9.18**, repair kits, first-aid kits and fire extinguishers are **reusable within a battle**, subject to a cooldown.
  - All other consumables trigger automatically and last the whole battle.
  - You pay to resupply a consumable once if it was used, however many times it activated.
- **Update 1.26 (Sept 2024):**
  - **Small** repair and first-aid kits now **repair all modules or heal all crew** on use, with a **90 s cooldown**.
  - **Large** repair and first-aid kits and the **automatic** fire extinguisher dropped from 90 s to **60 s**.
  - Only **large** consumables have passive bonuses:
    - Large Repair Kit: **+10% repair speed**.
    - Large First Aid Kit: **+15% resistance to crew injury** from penetrations.
  - Speed Governor, 100/105-octane fuel and Lend-Lease/Quality oil were removed. **Quality Fuel** and **Excellent Fuel** were added for all nations.
- **Prices (classic):**
  - Small Repair Kit, Small First Aid Kit and manual fire extinguisher: **3,000 credits**.
  - Large kits, automatic extinguisher and food: **20,000 credits or 50 gold**.
  - Food ("combat rations" by nation): **+10% crew qualification for the whole battle**. One source gives the example 75% → 85%.
- **Auto-resupply:** per-vehicle toggles for auto-repair, auto-resupply of ammo and auto-resupply of consumables. The cost of each appears as a separate line in the post-battle financial report (§8).
- **Confidence:** High for 9.18 reusability. **Medium** for the 1.26 cooldowns (90 s / 60 s), passive bonuses and the classic prices, which are unverified (corrected by fact-check). Medium for current price changes, which were not checked against 2.x.
- **Sources:**
  - [Consumables (WoT EU)](https://worldoftanks.eu/en/content/guide/game-mechanics-and-achievements/consumables/)
  - [TAP 1.26 consumables update](https://thearmoredpatrol.com/2024/08/11/wot-1-26-common-test-consumables-update/)
  - [1.26 CT1](https://worldoftanks.com/en/news/updates/1-26-CT1/)
  - [Consumables (WG wiki)](https://wiki.wargaming.net/en/Consumables)
  - [HyperX consumables guide](https://blog.hyperx.com/article/5051/world-of-tanks-complete-consumables-guide)

### 6. Missions

#### 6.1 Daily missions (introduced 1.8, reworked 1.10.1)
- **Structure:**
  - **3 Standard missions** at difficulty tiers I, II and III. They run in parallel and can span any number of battles.
  - Each mission persists until it is completed or **re-rolled**. Rerolls are limited and renew daily.
  - Completing all three unlocks a **Bonus mission**.
  - Rewards: credits, Free XP, consumables, bonds, crew books and blueprint fragments.
- **Premium daily missions:** WoT Premium adds **3 sequential Premium missions**. They do not count toward the Bonus mission but speed up an "Epic Reward" track.
- **Typical conditions** (from mission news):
  - "Deal + block 3,000 HP in one battle (Tier IV–X, Random, 3× per day)"
  - "Block 10,000 HP over any number of battles"
  - "Destroy N vehicles"
  - "Spot N enemies"
  - "Finish in the top 10 by XP"
- **Confidence:** High for structure. Medium for examples.
- **Sources:**
  - [Daily Missions guide](https://worldoftanks.com/en/content/guide/general/daily_missions/)
  - [1.10.1 reworked dailies](https://worldoftanks.com/en/news/updates/update-1-10-1-reworked-daily-missions/)
  - [1.8 dailies](https://worldoftanks.eu/en/news/general-news/1-8-daily-missions/)

#### 6.2 Personal Missions
- **Campaigns 1–2 (since 9.18–1.2):**
  - Each **Operation** has **5 Sets**, one per class (LT, MT, HT, TD, SPG), with **15 missions** each.
  - Each mission has a **Primary** objective (completes it) and an optional **Secondary** objective ("with Honors"), which gives extra rewards and commendations.
  - Operations unlock in sequence; final reward vehicles include Object 260 (Tier VI–X operation).
- **Sector 3 / Personal Missions 3.0 (Update 2.0):**
  - **3 Operations:**

    | Operation | Reward | Eligible tiers |
    |---|---|---|
    | Windhund | Tier VIII | VI–XI |
    | Dravec | Tier X | VII–XI |
    | Black Rock | Tier XI | VIII–XI |

  - Each operation has **3 role series × 15 missions = 45 missions**:
    - **Vanguard:** armoured assault — heavies, some mediums and TDs.
    - **Ambush:** second-line snipers and support.
    - **Assistance:** all LTs and SPGs; spotting and assist.
  - Example conditions:
    - Black Rock Vanguard-3: "destroy an enemy TD, dealing it ≥ 1,000 HP".
    - Black Rock Ambush-8: "destroy an enemy LT in the first 3 min, **or** deal 2,750 HP to LT/MT".
- **Confidence:** High.
- **Sources:**
  - [Personal Missions (WG wiki)](https://wiki.wargaming.net/en/Campaign)
  - [Update 2.0: Personal Missions—Sector 3](https://worldoftanks.eu/en/news/general-news/update-2-0-personal-battle-missions-3-0/)

#### 6.3 Battle Pass (since 2020)
- **Structure:**
  - Seasons of about 3 months; the 2026 seasons are XIX–XXI.
  - **3 chapters × 50 stages × 50 points = 7,500 points** for the main track.
  - Free and paid tracks. The **Improved Pass** has been reported at **2,500 gold per chapter** (Medium; it varies).
  - **Battle Pass Tokens** accumulate across seasons and are exchanged for exclusive Tier IX vehicles (2026: KB-52, Saryuda). 2026 tokens stay valid until 12 Dec 2026.
- **Points per battle:**
  - Based on **result and position in the team's XP ranking**.
  - Official guides from earlier seasons, Tier VI–X Random: **top 3 → 7 points on a win / 5 on a loss; top 10 → 5 / 3**. Lower positions get less.
  - **Daily missions also grant points.** WoT Plus Pro grants extra points.
- **Confidence:** High for structure. Medium for current point values.
- **Sources:**
  - [Battle Pass Guide (overtankpro)](https://www.overtankpro.com/guides/battle-pass-guide)
  - [TAP BP Season 19](https://thearmoredpatrol.com/2026/05/18/battle-pass-season-19-in-wot-points-dates-and-tokens/)
  - [BP Season VI guide](https://worldoftanks.com/en/news/general-news/battle-pass-season-6/)
  - [What is Battle Pass (WG support)](https://wargaming.net/support/en/products/wot/article/33094/)
  - [WoT Monthly Sept 2026](https://worldoftanks.com/en/news/general-news/wot-monthly-september-2026/)

#### 6.4 Event missions
- **XP Fever:** first-win multipliers.
- **Mid-Week Medal Hunts:** for example "earn Patrol Duty", "earn Confederate", with rewards.
- **Weekend challenges.**
- Holiday Ops, Steel Hunter and Onslaught carry their own mission chains and **event tokens**.
- **Confidence:** Medium.
- **Sources:**
  - [Mid-Week Medal Hunt: Patrol Duty](https://worldoftanks.eu/en/news/specials/mid-week-medal-hunt-patrol-duty/)
  - [Weekend challenge](https://worldoftanks.eu/en/news/specials/weekend-challenge-july22/)

### 7. Achievements

#### 7.1 Mastery badges (per vehicle)
- A battle's **base XP** (no Premium, first-win or reserve multipliers) is compared with the **same vehicle's** recent distribution over the **last 7 days**:

  | Badge | Requirement |
  |---|---|
  | **Ace Tanker** | Beat 99% |
  | **1st Class** | Beat 95% |
  | **2nd Class** | Beat 80% |
  | **3rd Class** | Beat 50% |

  The comparison is against the "average highest XP" of players in that vehicle. That wording comes from WG's Blitz support article; PC uses the same model.
- Only the best badge earned on each vehicle is kept.
- **Confidence:** High.
- **Sources:**
  - [Mastery Badge (WG support, Blitz)](https://wargaming.net/support/en/products/wotb/article/10221/)
  - [Achievements guide (WoT EU)](https://worldoftanks.eu/content/guide/general/achievements)

#### 7.2 Marks of Excellence (Tier V–X, per vehicle)
- **Metric:** "combined damage" = direct damage + **the highest single assist stream** (spotting, tracking or stun) − team damage.
- **Rolling value:** an exponential moving average after every battle: `EMA ← EMA + (2/101) × (CD − EMA)`.
- **Thresholds:** marks at the **65th / 85th / 95th** percentile of that vehicle's server distribution, recomputed **daily from 14 days** of data. They differ by region.
- Marks are **permanent** once earned. Mark-tracking percentages are shown in battle.
- **Confidence:** High for the 65 / 85 / 95 thresholds over 14 days, confirmed by fact-check against two independent community tools (see Verification log). Medium for the EMA constant, which comes from community reverse-engineering and was not re-verified.
- **Sources:**
  - [How MoE works (13DISCIPLE)](https://www.13disciple.stream/how-moe-work.html)
  - [wg-watch MoE](https://wg-watch.com/en/article/marks-of-excellence-world-of-tanks)
  - [gaminggearguru MoE](https://gaminggearguru.com/world-of-tanks-marks-of-excellenc/)

#### 7.3 Heroes of Battle (Random Battles; one per team unless noted)

| Award | Condition |
|---|---|
| **Top Gun** | Destroy the most enemies on your team, **at least 6** |
| **High Caliber** | Deal the most damage, **≥ 20% of the enemy team's total HP and ≥ 1,000**, with no direct hits on allies |
| **Steel Wall** | Most damage blocked by armour on the team, with **≥ 11 hits** received and **≥ 1,000 HP** blocked or received, and **survive**. Ties go to highest potential damage |
| **Defender** | Reset **≥ 70** enemy capture points on your base |
| **Invader** | Contribute **≥ 80** capture points to a **successful** base capture |
| **Scout** | Spot the most enemies, **≥ 9** |
| **Patrol Duty** | Be the **only** spotter for **≥ 6** enemies that allies then damaged. Ties go to more XP |
| **Confederate** | Hit the most enemies (**≥ 6**) that someone else later destroyed. Ties go to XP |
| **Sniper** | (≥ 85% hits of ≥ 10 shots, ≥ 1,000 potential damage) **Removed in 0.8.11** |

**Other single-battle examples:**
- **Master Gunner:** ≥ 5 penetrating hits in a row.
- **Sharpshooter:** ≥ 10 consecutive hits, which can carry across battles.
- **Spartan:** survive a non-penetrating hit with < 10% HP.
- **Lucky:** survive when an enemy is destroyed within 10 m of you by another enemy (partially quoted).

**Epic medals:**

| Medal | Condition |
|---|---|
| **Kolobanov's** | Alone against **≥ 5** enemies, and win |
| **Raseiniai Heroes** | Destroy **≥ 14** enemies |
| **Pool's** | **10–13** kills (Tier V+) |
| **Radley-Walters'** | **8–9** kills (Tier V+) |
| **Fadin's** | Destroy the **last enemy with the last shell** in your ammo rack |

All epic medals are earned in Random Battles only.

- **Confidence:** High for Top Gun, Steel Wall, Defender, Invader, Scout, Patrol Duty, Confederate and the epics. Medium for High Caliber and Lucky.
- **Sources:**
  - [worldoftanksguide achievements](https://www.worldoftanksguide.com/ref-achievements.shtml)
  - [Achievements (WG wiki)](https://wiki.wargaming.net/en/achievements)
  - [Achievements guide (WoT EU)](https://worldoftanks.eu/content/guide/general/achievements)
  - [Story behind epic medals (HyperX)](https://blog.hyperx.com/article/5218/the-story-behind-all-epic-medals-in-world-of-tanks)
  - [Steel Wall (TrueAchievements)](https://www.trueachievements.com/a204168/steel-wall-achievement)

### 8. Post-battle results screen
- **Current (2.0+):** the screen is **full-screen inside the hangar**. It shows your vehicle with styles over the battle map background.
- **Tabs:**
  1. **General:** result, main performance, earned XP and credits. Per-enemy combat effectiveness was moved to a **Space-key** overlay.
  2. **Team Result:** a per-player table. Clicking your name shows the old **"Detailed Report"** efficiency data.
  3. **Financial Report:** larger fonts, and a new **WoT Plus bonus** line.
  4. **Mission Progress:** progress in **Personal, daily and special missions**, plus **Tech Tree research progress** and **crew perk advancement**. This is where Battle Pass progress appears too.
- **Classic financial report lines** (pre-2.0 layout, recalled from the long-standing UI; **verify against current screenshots**):
  - **Credits column:** credits for the battle; Premium Account bonus; battle-achievement awards; penalty for damaging allies; compensation for damage from allies; Personal-reserve and Premium-vehicle bonuses; mission rewards; then deductions for **automatic repair**, **automatic resupply of ammunition**, **automatic resupply of consumables** (and equipment where relevant); then **Total**.
  - **XP / Free XP / Crew XP columns:** base, Premium bonus, first-victory multiplier, reserves.
  - **Reserve Stock:** the 10% Reserve Stock contribution appears for Premium Account users.
- **Confidence:** High for the 2.0 tab structure. Medium for the exact line names.
- **Sources:**
  - [TAP: New post-battle screen in 2.0](https://thearmoredpatrol.com/2025/09/01/wot-new-post-battle-statistics-screen-in-update-2-0/)
  - [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
  - Console PBRS for comparison: [WoT Console PBRS](https://modernarmor.worldoftanks.com/support/en/products/wotx/article/34024/)

### 9. Store and monetization patterns
- **Premium vehicles:**
  - Sold for gold or in bundles. Tier VIII is the core (about 7,200–12,500 gold in the classic API snapshot), and Tier IX Premiums exist.
  - WoT 2.0 cut Tier VIII–IX Premium gold prices by about 10% and raised Tier IX Premium credit income.
  - Selling refunds credits, not gold (§1.4).
- **Time-based:** Premium Account in days (§1.5) and the **WoT Plus** subscription (§1.5).
- **Battle Pass:** Improved Pass per chapter; bundles add levels and styles.
- **Bundles and weekly offers:** credits, Premium days, consumables, crew books, Personal Reserves.
- **Bonds:** a non-purchasable skill currency (Ranked, Frontline, Clan Wars) used for Improved Equipment and directives.
- **Loot boxes ("Large Boxes", Holiday Ops):**
  - Contain gold, Premium days, styles and a vehicle chance. **Every 50th box guarantees a vehicle.**
  - Odds are disclosed. Examples quoted: a 2.4% chance of a Tier VIII–X vehicle in one box type, and 11.66% for a Tier II–V vehicle in another (context unclear).
  - **Not sold in Belgium** under local gambling law; the Netherlands requires odds disclosure.
- **Confidence:** Medium.
- **Sources:**
  - [Holiday Ops 2026 Large Boxes](https://worldoftanks.asia/en/news/general-news/holiday-ops-2026-large-boxes/)
  - [Regulations on microtransactions (Wikipedia)](https://en.wikipedia.org/wiki/Regulations_protecting_consumers_from_microtransactions)
  - [Update 2.0 rebalance](https://worldoftanks.com/en/news/general-news/update-2-0-rebalance/)

### 10. Roblox platform facts that constrain the economy (authoritative local docs)
Paths below are relative to `refs/creator-docs/content/en-us/`.

- **Paid random items** (`production/monetization/paid-random-items.md`):
  - Any random outcome bought **directly or indirectly with Robux** must show **all outcomes and numerical odds that sum to 100%**. This includes chests, wheels, pity systems and luck boosts, and keys bought with Robux-purchasable currency.
  - Players with `ArePaidRandomItemsRestricted = true` must get an alternative: an earnable path, a disclosed fixed order, direct purchase, hiding the item, or a blocking message.
  - **Free randomized rewards earned through play do not need odds.**
  - Policy is read with `PolicyService:GetPolicyInfoForPlayerAsync()` (`reference/engine/classes/PolicyService.yaml`). It also returns `IsPaidItemTradingAllowed` and `IsEligibleToPurchaseSubscription`.
- **Subscriptions** (`production/monetization/subscriptions.md`):
  - Each subscription has **one** payment method at a time: Robux or local currency. It can be switched later, but only new subscribers are affected.
  - Price in Robux must be **≥ 49 Robux**. Local-currency tiers are **$2.99, $4.99, $7.99, $9.99 or $14.99**.
  - **Regional Pricing is on by default** for Robux subscriptions **and cannot be turned off**. It is not available for local-currency subscriptions. *(corrected by fact-check)*
  - Payout: 70% for Robux subscriptions; for local currency, 70% in the first month and 100% afterwards.
  - At most 50 subscriptions per game, active and inactive combined.
  - **Only Robux-priced subscriptions can change price**, at most once every 60 days, with 30 days' notice for increases. A **local-currency price can never be changed**; the subscription must be deleted and recreated, and deleting refunds all current subscribers. *(corrected by fact-check)*
  - Benefits must be identical across platforms and cannot be revoked mid-term. "Battle passes" may be sold as subscriptions.
  - Status is read with `MarketplaceService:GetUserSubscriptionStatusAsync` and `Players.UserSubscriptionStatusChanged`.
- **Developer products** (`production/monetization/developer-products.md`):
  - Price range 1 to 1,000,000,000 Robux.
  - **Must** be granted through `MarketplaceService.ProcessReceipt`, returning `Enum.ProductPurchaseDecision.PurchaseGranted` or `Enum.ProductPurchaseDecision.NotProcessedYet`. Do not use `PromptProductPurchaseFinished`.
  - Facts from `reference/engine/classes/MarketplaceService.yaml` that matter for granting (added by fact-check):
    - Set the callback once, in one server Script.
    - `receiptInfo.PurchaseId` uniquely identifies a purchase.
    - The callback for one purchase **can run on two servers at the same time**.
    - A `PurchaseGranted` result can still fail to record, leaving the purchase unresolved, and there is no time-based retry.
    - Without a callback, receipts are auto-acknowledged and cannot be recovered.
  - Cross-game developer product sales have been **disabled since 30 May 2026**, so this is already in effect.
- **Roblox Plus** (`production/monetization/roblox-plus.md`): subscribers get a 10–20% discount on dev products, passes and subscriptions, **subsidised by Roblox**, so creator revenue is unchanged.
- **Roblox Premium engagement payouts** (`production/monetization/engagement-based-payouts.md`): `player.MembershipType == Enum.MembershipType.Premium` can gate small perks.
- **DataStores** (`cloud-services/data-stores/error-codes-and-limits.md`):
  - **4,194,304 characters per key** (corrected by fact-check: the docs give a character limit on the serialized value, not bytes). Key names and data-store names are at most 50 characters.
  - Standard stores: **Read** (`GetAsync`, `UpdateAsync`) and **Write** (`SetAsync`, `IncrementAsync`, `UpdateAsync`) each default to **60 + numPlayers × 40 requests per minute** per server. These are separate budgets, and `UpdateAsync` draws from both. List requests get 5 + numPlayers × 2.
  - Defaults can be changed with `DataStoreService:SetRateLimitForRequestType()`. Check the remaining budget with `GetRequestBudgetForRequestType()`.
  - Ordered-store writes: **30 + numPlayers × 5**.
  - **Per-key throughput** applies across all servers: 25 MB/min read and **4 MB/min write**. Each request is rounded up to the next 1 KB. Exceeding it returns `KeyThrottled`. *(added by fact-check)*
  - Storage limit: 500 MB + 1 MB × lifetime users.
- **MemoryStore** (`cloud-services/memory-stores/index.md`):
  - Memory quota **64 KB + 1.2 KB × users**.
  - **1,000 + 120 × concurrent users request units per minute**.
  - Partitions throttle at about 30,000 RU/min. Useful for live percentile histograms and event leaderboards.

---

## Implementation recommendations for HULLDOWN (Roblox)

All numbers in this section are **OUR DESIGN CHOICE** unless they cite a WoT value. They are starting points for a spreadsheet and server-side economy simulator, and should be tuned with telemetry. Put all values in one `EconomyConfig` ModuleScript (shared, read-only), and do all grants on the server.

### R1. Currencies

| Currency | Earned by | Spent on | Notes |
|---|---|---|---|
| **Credits (CR)** | Battles, missions, selling | Vehicles, modules, equipment, consumables, ammo, repairs, crew retrain or reset | The main soft currency and sink |
| **Bullion (BUL)** — premium | Robux developer products; small amounts from Battle Pass and events | Premium vehicles, Premium Time, XP conversion, instant crew retrain, Battle Pass, cosmetics | Never sold as random items |
| **Vehicle XP** | Battles, per vehicle | Modules, next vehicles, Tier VI–X field mods, Tier XI nodes | |
| **Free XP** | **5% of base XP** (as WoT), missions, conversion | Any research | Kept at 5% for fidelity and as a "catch-up" pool |
| **Crew XP** | = vehicle XP earned (×1.5 on premium vehicles) | Perks | |
| **Merit (MER)** — earned skill currency (the "bonds" role) | Mastery badges, Battle Heroes, ranked/event placements, daily bonus mission | Improved-grade equipment, directives | Not purchasable. Rewards skill without paywalls |
| **Event Tokens** | Event missions and battles | Event shop | Per-event; shop stays open 7 days after the event ends; leftovers convert to Credits at a posted rate |

- **Conversions:**
  - **1 BUL = 200 CR** (one-way).
  - **Elite-vehicle XP → Free XP at 10 XP per 1 BUL.** This is cheaper than WoT's 25:1 in relative terms because our XP numbers are about 7× smaller.
  - Bullion pack pegs to Robux, e.g. **100 Robux → 250 BUL**, with +10% on large packs. Tune with `price-optimization` and regional pricing.

### R2. Battle rewards formula (server-authoritative)

```
baseXP      = Σ(action_i × xpCoef_i) × tierScaleXP[tier]
              actions: damage dealt (per HP), module/crew crits, spotting (first detection per enemy),
                       spotting-assist damage, tracking-assist damage, kills, capture points, capture-reset points
              win: ×1.5 (WoT +50%); draw ×1.0
              survival: +5%   (OUR DESIGN CHOICE; rewards staying alive in short matches)
              blocked damage: +0.25 × blockedHP × xpCoef_damage   (OUR DESIGN CHOICE; WoT gives none directly)
totalXP     = baseXP × firstWin(×2, per vehicle per day) × premiumTime(×1.5) × reserve × premiumVehicleXP
freeXP      = 0.05 × baseXP × (premiumTime ? 1.5 : 1) × freeXPReserve
crewXP      = totalXP × (premiumVehicle ? 1.5 : 1) × crewReserve
grossCR     = Σ(action_i × crCoef_i) × tierScaleCR[tier] × vehicleCreditCoef × (win ? 1.5 : 1)
              × (premiumTime ? 1.5 : 1)
serviceCost = repairFull[tier] × (HPlost / HPmax) + Σ shellsFired×shellPrice + consumablesUsed
netCR       = grossCR − serviceCost  (+ mission/achievement rewards)
```

- **Free XP base (fact-check note):** the `freeXP` line above deliberately leaves out the first-win multiplier. The fact-check could not verify whether WoT applies first-victory and reserve multipliers to its 5% Free XP. Treat the exclusion as **OUR DESIGN CHOICE** and keep it as an explicit `EconomyConfig` flag (`freeXPIncludesFirstWin = false`), so it can be flipped if telemetry shows Free XP is too scarce.
- **Coefficient guidance:**
  - Damage is about 55% of average XP.
  - Spotting and assist are about 25%. They count at 50% of damage XP per HP, so scouts earn a fair share.
  - Kills about 10%; capture and defence about 5%; crits about 5%.
- **Anti-farming:**
  - No XP for team damage.
  - Spotting XP only on the first detection of each enemy.
  - Capture XP only while the capture timer is advancing.
  - XP is clamped to zero for AFK players, detected when movement plus damage is below a threshold for 90 s.

### R3. Per-tier progression table (compressed curve for shorter Roblox sessions)

**Assumptions:**
- About **6 min** average battle and about **4 battles per session**.
- "B" = number of average battles played at a tier to research its modules and the next vehicle, without Premium.
- From Tier I to the first Tier XI unlock takes **≈ 260 battles ≈ 26 h of battle time ≈ 65 sessions**.
- WoT needs thousands of battles for the same path, and WoT itself handed out a free branch in 2.0 to shorten it.

| Tier | Avg base XP/battle | B (battles at tier) | Module XP total (on this vehicle) | Research XP for this tier's vehicle | Price (CR) | Full repair (CR) | Std shell (CR) | Avg gross CR/battle | Avg service CR | **Avg net CR (no Premium)** | Net with Premium (+50% gross) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| I | 150 | 3 | 100 | — (starter) | 0 | 0 | 0 | 15,000 | 0 | 15,000 | 22,500 |
| II | 200 | 5 | 250 | 350 | 35,000 | 3,000 | 50 | 22,000 | 2,000 | 20,000 | 31,000 |
| III | 260 | 8 | 500 | 750 | 100,000 | 6,000 | 100 | 30,000 | 4,000 | 26,000 | 41,000 |
| IV | 330 | 12 | 1,000 | 1,550 | 220,000 | 11,000 | 200 | 40,000 | 8,000 | 32,000 | 52,000 |
| V | 410 | 17 | 1,750 | 3,000 | 400,000 | 18,000 | 300 | 52,000 | 14,000 | 38,000 | 64,000 |
| VI | 500 | 23 | 2,900 | 5,200 | 650,000 | 28,000 | 450 | 65,000 | 23,000 | 42,000 | 74,500 |
| VII | 600 | 30 | 4,500 | 8,600 | 1,000,000 | 42,000 | 650 | 80,000 | 36,000 | 44,000 | 84,000 |
| VIII | 700 | 40 | 7,000 | 13,500 | 1,400,000 | 60,000 | 900 | 95,000 | 53,000 | 42,000 | 89,500 |
| IX | 800 | 52 | 10,500 | 21,000 | 1,800,000 | 85,000 | 1,200 | 110,000 | 80,000 | 30,000 | 85,000 |
| X | 900 | 70 | 16,000 | 31,000 | 2,600,000 | 115,000 | 1,600 | 125,000 | 115,000 | 10,000 | 72,500 |
| XI | 1,000 | — | 60,000 (upgrade nodes, R6) | **47,000** (on a Tier X) | **3,600,000** | 150,000 | 2,000 | 140,000 | 155,000 | **−15,000** | 55,000 |

**Checks and rationale:**
- **XP closes per tier.** B × avg XP ≈ module XP + next vehicle XP. Example: Tier VI 23 × 500 = 11,500 = 2,900 + 8,600.
- **Credits close up to Tier IX.**
  - Net CR × B ≈ next price. Example: Tier VII 44,000 × 30 = 1.32M, next price 1.4M.
  - **Tier X needs a top-up:** selling the IX gives 50% (900k), plus daily missions.
  - **Tier XI is a deliberate wall.** It needs about (3.6M − 0.7M) ÷ 44k ≈ 65 battles of Tier VII credit farming, or Premium Time. Daily-mission surplus during the Tier X stage brings this to about 60 battles. This mirrors WoT's VIII-profitable / IX–X-sink design, but is softer.
  - **Module credit purchases are not in the closure above.** At 3 modules × 6% = 18% of the vehicle price, they are paid from daily-mission credits.
    - A tier step spans about 1–18 play days at 4 battles per day.
    - Modules therefore need about **5k CR per play day at Tier II, rising to about 27k at Tier X** (0.18 × price ÷ (B ÷ 4)).
    - Dailies give about **15k–45k CR per day** (R10), which covers modules plus the Tier X top-up.
  - *(corrected by fact-check)* The earlier daily figure, 225k–350k CR per day, contradicted this table. Over the ≈ 65 play days from Tier I to XI, it adds up to 14.6M–22.8M CR. That is more than every tech-tree vehicle price from Tier II to XI combined (≈ 11.8M CR), so battle income and the Tier IX–XI credit sink would stop mattering.
- **Ratios against WoT:**
  - Our X/II price ratio is 74× (WoT about 1,700×) and the XI/X research ratio is 1.5× (WoT 1.48×).
  - Tier XI costs 1.38× Tier X in credits (WoT 1.21×). We keep XI more premium because XI is the long-term goal tier.
- **Never let a player get stuck:**
  - Tier I–II have **zero repair** at I and trivial repair at II.
  - If a player's credits are below the cost of 1 battle of service at their chosen tier, show a "play a lower tier / use auto-free repair" hint.
  - Add an **auto-repair floor**: the repair bill is capped so the balance never goes negative. The remaining debt is waived.
- **Premium vehicles** (tiers II–VIII only):
  - Credit coefficient **×1.35**, Crew XP **×1.5**, same matchmaking spread as everything else.
  - **Never stronger** than tech-tree vehicles of the same tier.
  - Bullion prices:

    | Tier | II | III | IV | V | VI | VII | VIII |
    |---|---|---|---|---|---|---|---|
    | BUL | 250 | 400 | 600 | 1,000 | 1,600 | 2,400 | 3,500 |

- **Selling:** **50%** refund (as WoT). Premium vehicles refund **50% × BUL price × 200 CR** in credits. Buyback is possible within 72 h at the sell price plus 10%.
- **Garage:** **unlimited slots.** WoT charges 300 gold per slot, but on Roblox this is pure friction. Data cost is tiny: a vehicle record is under 1 KB against the 4 MB per-key limit.

### R4. Modules and research UX
- **Up to 3 researchable modules per vehicle:** gun, engine and suspension. Turret only where it is meaningful. **No radio.** This follows WoT 2.0's module streamlining.
- **Stock vehicles must be battle-viable,** as WoT 2.0 now makes them.
- **Module credit price** = 6% of the vehicle price each.
- **Elite** = all modules and child vehicles researched. Elite unlocks XP→Free XP conversion and (Tier VI–X) **Field Kits**.
- **Field Kits** are our field modification:
  - Levels: Tier VI–VII **3**, VIII **4**, IX–X **5**.
  - XP per level: Tier VI 1,000, VII 1,800, VIII 2,800, IX 4,000, X 5,500.
  - Each level offers two small choices, which can be swapped free at any time, as in WoT.

### R5. Daily first win, Premium Time, subscriptions
- **First win of the day:** ×2 XP **per vehicle per day**, resetting at a fixed UTC hour. Events can run ×3. This gives a natural "play several tanks" loop that suits short sessions.
- **Premium Time** (a Bullion purchase of days, which avoids subscription constraints):
  - **+50% XP, +50% credits, +50% crew XP**, matching WoT.
  - **+1 daily mission reroll.**
  - **No** combat stats.
  - Prices: 1 day 250 BUL, 7 days 1,250, 30 days 2,000.
- **HULLDOWN Plus** (Roblox **Subscription**). A subscription has one payment method at a time, and the earlier wording mixed the two *(corrected by fact-check)*:
  - **Recommended: price it in Robux at about 449 Robux/month.** Regional Pricing is forced on, the payout is 70% every month, and the price can be tuned once every 60 days.
  - The alternative is the **$4.99 local-currency tier**. The payout is 70% in the first month and 100% after that, but the price can **never** be changed without deleting the subscription and refunding every subscriber.
  - Benefits:
    - **+25 BUL per day of play.**
    - **Free equipment demounting.**
    - **Passive crew XP**: 100 per 5 minutes online for 1 chosen crew, capped at 3,000 per day.
    - A **+20% XP/CR boost on one chosen tech-tree vehicle**.
  - Every benefit must be identical on all platforms and must not be revoked mid-term (Roblox guideline).
  - Check `IsEligibleToPurchaseSubscription` before prompting. Check subscription status on the server with `MarketplaceService:GetUserSubscriptionStatusAsync` and listen to `Players.UserSubscriptionStatusChanged`.
- **Roblox Premium members:** +10% credits, cosmetic only otherwise. This rewards Premium playtime (engagement payouts) without pay-to-win.

### R6. Tier XI
- **Unlock:** 47,000 XP on the Tier X + 3,600,000 CR.
- **Each Tier XI has one signature mechanic** (WoT 2.0 pattern).
- **Upgrade track of 10 nodes:**

  | Node type | Count | XP each |
  |---|---|---|
  | Small | 6 | 4,000 |
  | Large | 3 | 8,000 |
  | Final | 1 | 12,000 |

  Total **60,000 XP ≈ 60 battles**. All upgrades are positive; Free XP is allowed.
- After all nodes, **Elite levels** (every 25 battles) unlock cosmetics only: stat trackers, gun sleeves and decals.
- **Matchmaking:** Tier XI meets only Tier X–XI (±1). This is **stricter** than WoT 2.0, which uses mostly ±1 with some ±2 (§1.7) (corrected by fact-check; it previously said "consistent with").

### R7. Crew (simplified version of WoT post-2024)
- **Crew roles:** **4 roles** — Commander, Gunner, Driver, Loader. The radio operator's perks fold into the Commander. Vehicles with fewer seats double up roles, as WoT does.
- **Learn from April 2024 and 2.2:**
  - **No qualification levels**; every crew is effectively at 100%.
  - **Free fully trained recruits.**
  - Perks work from 1% and scale linearly (WoT 1.20.1).
- **Perk slots:** **5 per crew member** (WoT has 6).
  - Crew XP per perk: **12,000 / 24,000 / 48,000 / 96,000 / 192,000**. This doubles like WoT's 210,064-based curve, rescaled to our XP.
  - At 700 XP per battle, the first perk takes about 17 battles and all five about 530 battles. A long-term goal, but each perk works partially from 1% training.
- **Perk catalogue:**
  - **6 individual perks per role plus 3 group perks**: Brothers in Arms (+5% crew efficiency when everyone has it), Field Repairs, Concealment.
  - Group perks work at (number of crew with the perk ÷ crew size) strength, which keeps WoT's "all crew" rule but makes it gradual.
  - Starter set, using WoT-like magnitudes:
    - **Commander:** Recon (+2% view), Practicality (−10% consumable cooldown), Mentor (+10% crew XP), built-in 3 s "spotted" indicator (WoT made Sixth Sense free in 1.18.1).
    - **Gunner:** Snap Shot (−7.5% turret-rotation dispersion), Deadeye (−3.5% stationary dispersion after 3 s), Quick Aiming (+2.5% aim speed).
    - **Driver:** Clutch Braking (+5% hull traverse), Smooth Ride (ram), Engineer (+1 km/h).
    - **Loader:** Intuition (−60% shell-swap time), Close Combat (−2.5% reload within 50 m), Ammo Tuck (+2% minimum damage roll).
- **Zero perk:** reward crews (Battle Pass, events) come with 1 pre-trained perk that counts toward the 5.
- **Perk reset:**
  - **First reset free**, then **50,000 CR** (WoT 2.2 moved this from gold to credits). Never Bullion-only.
  - Within 7 days of the first purchase of a vehicle, resets are free.
- **Retrain to another vehicle of the same nation and class:**
  - **Credits:** 5% of the target vehicle's price. Applies a **−25% perk-efficiency penalty**, recovered linearly over the next **20,000 Crew XP**. This mirrors WoT's 100,000-XP pool, rescaled.
  - **Bullion:** 100 BUL, no penalty.
  - Cross-class retraining keeps 90% of perk XP.
- **Crew books:**

  | Book | Crew XP each | How obtained |
  |---|---|---|
  | Booklet | 5,000 | Credits: 60,000 CR |
  | Guide | 25,000 | Missions and Battle Pass |
  | Manual | 60,000 | Events |

- **Injuries:** in-battle effect only (crew efficiency −50% for the role while injured). **No post-battle XP penalty** (WoT 1.20.1).
- **Overflow:** Crew XP beyond the 5th perk converts to Free XP at 10:1, so XP is never wasted. This was a key complaint in WoT's Crew 2.0 feedback.

### R8. Equipment (WoT 2.0-style categories, original item names)
- **Slots:** Tier I–III have **2** slots; Tier IV–XI have **3**.
- **Category slot:** from Tier VI, slot 1 is a category slot (Firepower, Survivability, Mobility or Scouting, chosen per vehicle role). A matching item gives **+15% of its base effect**, the same as WoT's 10% → 11.5% pattern.
- **Grades and prices:**

  | Grade | Tier band | Price |
  |---|---|---|
  | C | II–IV | 25,000 CR |
  | B | V–VII | 150,000 CR |
  | A | VIII–XI | 300,000 CR |
  | "Refined" | — | 3,000 Merit; about 1.2× the standard effect |

  There is **no Bullion-exclusive equipment**.
- **Item list** (standard / category-slot values; follows WoT magnitudes, our names):

  | Item | Category | Effect |
  |---|---|---|
  | Rammer Assist | Firepower | −10% / −11.5% reload |
  | Laying Drive | Firepower | +10% / +11.5% aim speed |
  | Gyro Stabiliser | Firepower | −20% / −23% move/traverse dispersion |
  | Traverse Gearing | Mobility + Firepower | +10% / +12.5% traverse |
  | Crew Ventilation | All | +5% / +6% crew efficiency |
  | Coated Lenses | Scouting | +10% / +11.5% view |
  | Periscope Mast | Scouting | +25% / +27.5% view after 3 s stationary |
  | Cam Netting | Scouting | +15% (TD) / +10% (LT, MT) / +5% (HT) concealment after 3 s stationary |
  | Turbo Kit | Mobility | +7.5% / +10% engine power, +4 / +5 km/h top speed |
  | Reinforced Torsion Bars | Survivability | +8% / +10% HP, +50% suspension durability |
  | Damage Control Suite | Survivability | +45% repair speed, +150% ammo-rack/engine durability, −65% fire chance |
  | Spall Lining | Survivability | +50% / +60% HE and ram protection |

- **Demount:** **free with HULLDOWN Plus, or 5 BUL, or 10% of the item's credit price.** WoT's 10-gold demount is a pay-friction lever we deliberately avoid gating behind Bullion only.

### R9. Consumables (WoT 1.26 model, tuned for 6-minute matches)

| Item | Price | Behavior |
|---|---|---|
| Field Repair Kit (small) | 3,000 CR | Repairs **all** modules; 90 s cooldown; reusable |
| Medkit (small) | 3,000 CR | Heals **all** crew; 90 s cooldown |
| Fire Extinguisher (manual) | 3,000 CR | Puts out fire; 90 s cooldown |
| Large Repair Kit | 20,000 CR or 100 BUL (corrected by fact-check) | 60 s cooldown; passive +10% repair speed |
| Large Medkit | 20,000 CR or 100 BUL (corrected by fact-check) | 60 s cooldown; passive +15% crew-injury resistance |
| Automatic Extinguisher | 20,000 CR or 100 BUL (corrected by fact-check) | Fires automatically; 60 s cooldown |
| Rations | 20,000 CR | +10% crew efficiency for the whole battle |
| Quality Fuel | 20,000 CR | +5% engine power |

- **Bullion prices must respect the R1 peg** of 1 BUL = 200 CR. 20,000 CR is therefore 100 BUL, matching WoT, where 50 gold = 20,000 CR at 1:400. *(corrected by fact-check)* The earlier 25 BUL undercut the credit price by 4×, which would make Bullion the default way to buy every large kit.
- **Resupply charging:** you pay to resupply once if the item was used at all, whatever the number of activations (as WoT).
- **Auto-resupply** for ammo and consumables is **ON by default**. If credits are short, fall back to the cheapest kits and warn in the post-battle report.
- **Premium (Bullion-price) shells:** not sold. Instead, special ammo costs **2.5× credits**, so ammo is a credit sink rather than a paywall.

### R10. Missions & Battle Pass
- **Daily missions:**
  - 3 at once (Easy, Medium, Hard), plus a Bonus mission when all 3 are done. 1 free reroll per day; Premium Time adds a second.
  - Rewards scale with highest owned tier. Credit ranges run from Tier I–II to Tier IX–XI *(credits corrected by fact-check; see R3)*:

    | Mission | Credits | XP / Free XP | Other |
    |---|---|---|---|
    | Easy | 2k–8k CR | 150 Free XP | — |
    | Medium | 3k–10k CR | 300 Free XP | 1 Booklet |
    | Hard | 5k–12k CR | 500 Free XP | 30 Merit |
    | Bonus | 5k–15k CR | 1,000 Free XP | Large Repair Kit |

  - Daily total is 15k–45k CR. The previous 225k–350k CR per day paid for the whole tech tree on its own and contradicted R3's credit closure and the Tier IX–XI sink.

  - Targets must be completable in **1–3 battles** for short sessions.
- **Campaigns (our Personal Missions):**
  - **3 operations × 3 role series** (Assault, Overwatch, Support — similar in spirit to WoT's Sector 3 roles) **× 10 missions**.
  - Each mission has a primary and a "with honors" secondary objective.
  - Example: "Deal ≥ 1,000 damage to a TD and destroy it."
  - Final rewards are unique premium-grade vehicles or cosmetics. They are not sold.
- **Season Pass** (Bullion, or a Roblox Subscription marketed as a pass, which the guidelines allow):
  - 8-week seasons, **3 chapters × 30 stages × 30 points = 2,700 points**. Roblox seasons are shorter than WoT's 7,500.
  - **Points per battle:**

    | Team rank by XP | Win | Loss |
    |---|---|---|
    | Top 3 | 8 | 6 |
    | 4–10 | 6 | 4 |
    | Rest | 3 | 2 |

  - Plus **+15 per daily mission**.
  - A battle averages about 4.5 points, so a 4-battle session plus 3 dailies earns about 63 points. A 900-point chapter therefore takes about 14–15 sessions.
  - **Season Tokens** carry over seasons for an exclusive vehicle, as WoT does.

### R11. Achievements
- **Mastery (Ace/I/II/III):**
  - Thresholds at the **99 / 95 / 80 / 50th percentile of base XP** for that vehicle over the **last 7 days**, as WoT.
  - **Implementation:** per-vehicle 50-XP-bucket histograms in a sharded DataStore key (`mastery/<vehicleId>/<dayIndex>`). A daily job recomputes thresholds into a small config key that every server reads at start.
    - *(corrected by fact-check)* Do **not** write to the shared key after every battle. Each server should collect histogram deltas in memory and flush them with one `UpdateAsync` per vehicle-day key about every 60 s.
    - The reason is that a key's write throughput is 4 MB/min across **all** servers, with each request rounded up to 1 KB, and every `UpdateAsync` uses both the server's Read and Write budgets.
    - Alternative: aggregate live in a `MemoryStoreHashMap` (about 5,000 write RU/min per item key; shard the item keys) and flush once a day.
    - Key names must stay at or under 50 characters.
  - **Fallback:** if a vehicle has fewer than 300 samples in 7 days, use the pooled tier+class histogram. The Roblox player base per vehicle will be much smaller than WoT's.
- **Gun Marks** (Tier V–XI):
  - EMA with **k = 2/101** of (damage + max(spotting assist, tracking assist)).
  - **65 / 85 / 95** percentile thresholds over 14 days, using the same histogram method with a tier+class fallback pool.
- **Battle Heroes** (WoT thresholds scaled to our team size; assume **10 v 10**, about 2/3 of WoT's 15 v 15):

  | Award | Condition |
  |---|---|
  | Top Gun | Most kills, ≥ 4 |
  | Steel Wall | Most blocked damage, ≥ 8 hits received, ≥ 1,000 blocked, survive |
  | Defender | ≥ 50 capture points reset |
  | Invader | ≥ 60 capture points in a successful capture |
  | Scout | Most spotted, ≥ 6 |
  | Patrol Duty | ≥ 4 enemies damaged only by your spotting |
  | Confederate | ≥ 4 hits on enemies later killed by others |
  | High Caliber | Most damage, ≥ 20% of enemy team HP and ≥ 1,000, no ally hits |

  Epics: **Last Stand** (alone vs ≥ 4 and win), **Ace Hunter** (≥ 7 kills), **Last Round** (final kill with the final shell).
  - Each award grants **Merit**: Battle Hero 10, epic 50, Ace badge 25. Cosmetic ribbons only.

### R12. Post-battle screen

**Tabs:**
1. **Summary:** result, map, your vehicle render, kills, damage, assist, blocked, spotted, XP and CR totals, awards earned.
2. **Team:** per-player table. Click a row to see detailed hits, crits and damage per enemy.
3. **Report:** XP and credits ledger.
4. **Progress:** daily, campaign and season-pass deltas; research bar to the next module or vehicle; crew perk progress; Gun Mark %; Mastery threshold reached.

**Report ledger lines.** Every line is a server-computed entry in `BattleResult.ledger[]`, so the UI never derives economy values:

**XP:**

```
Base XP for battle
+ Win bonus (included in base)
× First win of the day (x2)
+ Premium Time bonus (+50%)
+ Reserve bonus
= Total vehicle XP | Free XP (5%) | Crew XP
```

**Credits:**

```
Credits for battle
+ Premium Time bonus
+ Premium-vehicle/Roblox Premium bonus
+ Award rewards
− Penalty for damaging allies
+ Compensation for ally damage received
− Automatic repair
− Ammo resupply
− Consumables resupply
= Net credits
```

- Show the net in red when it is negative, with an "Why?" tooltip explaining Tier IX–XI costs.
- **Persist** the last 20 battle results per player in their profile key, with fields trimmed so the record stays well under 4 MB.

### R13. Monetization guardrails
- **No paid random items at launch.** Event crates come **only from free gameplay**; under Roblox policy, odds are then not required.
  - *(corrected by fact-check)* A crate counts as a **paid random item** if it comes from the paid Season Pass track or Premium Time, is bought or rerolled with Bullion, or has its odds improved by any paid item. Roblox treats these as indirect purchases.
  - In that case the crate needs full odds disclosure and the `ArePaidRandomItemsRestricted` alternative.
  - The paid Season Pass track (R10) must therefore contain only fixed rewards.
- If boxes are ever sold:
  - disclose itemized odds that sum to 100%;
  - show a **"guaranteed vehicle every N boxes"** pity rule numerically;
  - gate with `ArePaidRandomItemsRestricted`, offering direct purchase at expected value.
- **Grant every Robux purchase via `MarketplaceService.ProcessReceipt`.**
  - Write the grant and an idempotency record keyed by `receiptInfo.PurchaseId` in the **same atomic `UpdateAsync`** on the player's profile key.
  - Return `Enum.ProductPurchaseDecision.PurchaseGranted` only after that write succeeds; otherwise return `NotProcessedYet`.
  - *(corrected by fact-check)* The engine docs say the callback for one purchase can run on two servers at once. A separate "check, then write" is therefore not enough.
- **Prohibited:**
  - Bullion-only combat power. Premium vehicles must not outclass tech-tree vehicles.
  - Bullion-only equipment.
  - Time-limited FOMO purchases of combat items.
- **Allowed:** cosmetics, time savers (Premium Time, XP conversion), premium vehicles at parity, and the season pass.

---

## Open questions / uncertain items
1. **Exact WoT XP and credit coefficients per action**, including whether blocked damage pays directly. WG has never published these; only community estimates exist, and none were retrieved. HULLDOWN's coefficients are our own.
2. **Per-tier repair and ammo costs and credit coefficients** for tech-tree vs premium vehicles in 2.x, including the actual Tier X average net. Not retrieved; the Tier X coefficient of about 0.5 is a low-confidence community claim.
3. **Whether WoT 2.0 changed Tier II–X research XP and credit prices.** The API data predates 2.0. I found evidence of module streamlining and premium price cuts, but not of changes to tech-tree vehicle prices.
4. **Tier XI repair and ammo costs and the per-vehicle node count.** "Up to 25 nodes" is confirmed; whether every Tier XI has 25 is not. Also Tier XI earnings.
5. **Crew 1.26/2.2 numbers:**
   - XP cost per perk under the new system (the doubling curve is classic).
   - The exact effect of the Concealment and Repairs group perks.
   - The full list of 10 new 2.2 perks.
   - The exact credit retrain penalty in 2.2 (40% penalty over 40,000 XP vs a 100,000 XP pool vs −10% perk XP; sources conflict).
6. **Equipment 2.0 exact values** for Enhanced Gun Laying Drive, Low Noise Exhaust and Vertical Stabilizer's category bonus, plus any 2.x retunes. Also Improved/Trophy demount pricing (200 bonds is unconfirmed).
7. **Field Modification XP per level.** Community figures; not confirmed whether 3,500–28,000 is per level or a total.
8. **Current Battle Pass points per battle and Improved Pass price** in the 2026 seasons. The 7/5/5/3 points are from earlier official guides.
9. **WoT Premium "×3 latest victory, 5×/day"** and the Reserve Stock specifics. These come from 1.5-era text and may have been revised since.
10. **Post-battle Financial Report line names** in 2.0. The structure is confirmed; the exact line labels are recalled from the classic UI and should be checked against a current screenshot.
11. **HULLDOWN-specific:**
    - Validate the table in R3 with an offline Monte-Carlo economy simulator: distribution of player skill, win rate 50%, Premium Time penetration 0–30%.
    - Confirm the 6-minute battle and 10 v 10 assumptions with the combat and matchmaking research docs.
    - Confirm the Bullion-to-Robux peg with a price-optimization test.
12. **Unverified after the fact-check (2026-10-05):**
    - Tier XI unlock cost and node XP.
    - The 2.2 perk-reset price.
    - The 1.26 consumable cooldowns.
    - Equipment class prices.
    - Free XP / Premium Account values.
    - Whether WoT's 5% Free XP is taken before or after the first-victory multiplier.

    The first-party pages were unreachable, so re-check these when a browser or a working search is available.

---

## Verification log

Fact-check pass of 2026-10-05.
- **Totals:** 15 claims checked. **6 Confirmed, 2 Corrected, 7 Unverified.** The checker also found and fixed 6 internal contradictions in the Implementation recommendations, listed in the second table.
- **Roblox claims** were checked against the local creator-docs clone. Paths are relative to `refs/creator-docs/content/en-us/`.
- **WoT first-party pages** (worldoftanks.\*, wargaming.net), TAP, nerdschalk, mmos, Wikipedia, Steam and the community wikis were all unreachable from this environment, and the web-search budget had run out. WoT claims could therefore only be confirmed from GitHub-hosted material.
- **Excluded evidence:** client-datamined localization files, such as the `wot-src` mirrors, were deliberately **not** used, in line with this report's no-datamined-data rule.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Tech-tree Tier II–X research-XP and credit medians (e.g. II 275 XP / 3,600 CR; VIII 97,400 / 2,530,000; X 219,830 / **6,100,000 for every Tier X**); Premium gold medians | **Confirmed**; the snapshot dates were corrected to 2017 and 2021 | Every min/median/max was re-computed from local copies of the WG Tankopedia API dumps [aki33524/wotdatabase](https://github.com/aki33524/wotdatabase) (last commit May 2017; 508 vehicles) and [GuilleHoardings/wot_tank_data](https://github.com/GuilleHoardings/wot_tank_data) (last commit Aug 2021, patch 14.0.2). Tier X is 6,100,000 for all 45 and all 59 vehicles. The two dumps agree within about 2%. |
| 2 | Tier XI unlock = 325,000 XP on a Tier X, then 7,400,000 credits | **Unverified**; confidence lowered from High to Medium | Every cited page was unreachable. The official 2.0 video narration only says "research it for XP and purchase it". Sibling doc 03 cites this doc, so it is not independent. |
| 3 | Tier XI at 2.0 launch: 16 vehicles (7 HT, 5 MT, 3 TD, 1 LT); upgrade tree replaces Field Modification; Elite rewards are a stat tracker, volumetric 2D styles and gun sleeves | **Confirmed** | Narration captions of WG's official "Update 2.0: Overview" video ("16 brand new vehicles", "Seven heavy tanks, five medium tanks, three tank destroyers, and one light tank", "upgraded system exclusive to Tier 11, replacing field modifications", "a stat tracker, volumetric 2D styles and gun sleeves") in [Heinz217/TraceAV-Bench-Submission](https://github.com/Heinz217/TraceAV-Bench-Submission), `intermediate/step3_agentic_question_generation/event_blocks/video129.json` |
| 4 | Tier XI nodes: up to 25 per vehicle; small 10,000 / large 20,000 / final 25,000 XP | **Unverified**; confidence lowered from High to Medium | Cited sources unreachable (TAP, gaminggearguru, WoT). No GitHub-hosted corroboration found. |
| 5 | Free XP = 5% of base XP; Elite XP converts at 25 XP per 1 gold; 1 gold = 400 credits | **Unverified** (long-standing values; confidence kept) | First-party economy pages unreachable. A 2012 Habr article mirrored on GitHub ([BlancLoup/weekly-geekly](https://github.com/BlancLoup/weekly-geekly.github.io), `articles/138519`) supports "5% of earned XP" only qualitatively. Open point: is the 5% taken before or after the first-win and Premium multipliers? R2 now makes this an explicit config flag. |
| 6 | WoT Premium Account +50% XP, credits and crew XP; 30 days = 2,500 gold | **Unverified** (confidence kept) | First-party pages unreachable; no independent source found. |
| 7 | Equipment 2.0 class prices: Class 3 50,000 / Class 2 300,000 / Class 1 600,000 credits | **Unverified**; confidence lowered from High to Medium | Release notes and WG support pages unreachable; no GitHub corroboration. |
| 8 | 1.26 consumables: small kits fix or heal everything with a 90 s cooldown; large kits and automatic extinguisher 60 s; prices 3,000 / 20,000 CR or 50 gold | **Unverified**; confidence lowered from High to Medium | TAP and WoT pages unreachable. |
| 9 | 2.2 "Crew Rework Complete": perk reset 100,000 credits (was 200 gold); 10 new perks | **Unverified**; confidence lowered to Medium | WoT Asia, Steam and TAP pages unreachable. |
| 10 | Marks of Excellence: 65 / 85 / 95 percentile thresholds over 14 days; EMA constant k = 2/101 | **Confirmed** for the thresholds and the 14-day window; the EMA constant is **Unverified** | [unicum-gg/unicum.gg](https://github.com/unicum-gg/unicum.gg) `packages/core/src/moe/poliroid.ts` (code comment: "65th / 85th / 95th combined-damage percentiles … over the last 14 days"); [drizzer14/moe-calculator](https://github.com/drizzer14/moe-calculator) README (65% / 85% / 95% milestones) |
| 11 | Top Gun: most kills, at least 6. Steel Wall: at least 11 hits and at least 1,000 HP, and survive | **Confirmed** (console trophy wording, same award) | WoT console PSN trophy list NPWR10017_00 in [FlexBy420/sce-tmdb-scraper](https://github.com/FlexBy420/sce-tmdb-scraper), `trophies/en/NPWR10017_00.json`: "Top Gun … (at least 6)"; "Steel Wall … surviving at least 11 hits for 1,000 potential HP" |
| 12 | DataStore: "4 MB / 4,194,304 bytes per key; 60 + 40×players read/write requests per minute" | **Corrected** | `cloud-services/data-stores/error-codes-and-limits.md`. The limit is 4,194,304 **characters**. Read and Write are **separate** budgets of 60 + 40×n each, and `UpdateAsync` draws from both. Budgets can be changed with `SetRateLimitForRequestType()`. Per-key throughput is 25 MB/min read and 4 MB/min write, with 1 KB rounding. Ordered writes are 30 + 5×n (confirmed). |
| 13 | MemoryStore: memory 64 KB + 1.2 KB × users; 1,000 + 120 × CCU request units per minute; about 30,000 RU/min per partition | **Confirmed** | `cloud-services/memory-stores/index.md`, which also gives about 5,000 write and 15,000 read RU/min per hash-map item key |
| 14 | Subscriptions: at least 49 Robux; $2.99–$14.99 local tiers; Regional Pricing by default; payout 70% (Robux) or 70%→100% (local); 50 per game; "price can change once every 60 days" | **Corrected** | `production/monetization/subscriptions.md`. Only **Robux** subscriptions can change price (once per 60 days, 30 days' notice for increases). A **local-currency price can never be changed**. Regional Pricing cannot be turned off for Robux subscriptions. Each subscription has one payment method at a time. |
| 15 | Monetization API names and rules (see the list below) | **Confirmed**; exact names were added: `Enum.ProductPurchaseDecision.*` and `receiptInfo.PurchaseId`, plus the caveat that one receipt can be processed on two servers at once | `reference/engine/classes/MarketplaceService.yaml`, `reference/engine/classes/PolicyService.yaml`, `production/monetization/developer-products.md` (line 47: "Starting May 30, 2026, cross-game developer product sales will be disabled"), `production/monetization/paid-random-items.md`, `production/monetization/subscriptions.md` |

Claim 15 covers these names and rules:
- `MarketplaceService.ProcessReceipt`, returning `PurchaseGranted` or `NotProcessedYet`. Do not use `PromptProductPurchaseFinished`.
- `PolicyService:GetPolicyInfoForPlayerAsync()` fields: `ArePaidRandomItemsRestricted`, `IsPaidItemTradingAllowed` and `IsEligibleToPurchaseSubscription`.
- `MarketplaceService:GetUserSubscriptionStatusAsync` and `Players.UserSubscriptionStatusChanged`.
- Paid-random-item odds must sum to 100%, including indirect purchases. Free earned rewards are exempt.
- Cross-game developer product sales are disabled from 30 May 2026.

**Implementation recommendations — internal consistency check**

| Item | Verdict | Evidence / fix |
|---|---|---|
| R3/R10 daily-mission credits of 225k–350k CR per day vs. the R3 credit closure and the Tier IX–XI sink | **Corrected** to 15k–45k CR per day | Over ≈ 65 play days, 225k–350k per day gives 14.6M–22.8M CR. That is more than the sum of all vehicle prices from Tier II to XI (11.8M CR), so dailies alone would buy the tree. The modules that dailies must fund cost about 5k–27k CR per play day (0.18 × price ÷ (B ÷ 4)). |
| R9 large consumables at 25 BUL vs. the R1 peg of 1 BUL = 200 CR | **Corrected** to 100 BUL | 20,000 CR ÷ 200 = 100 BUL. This matches WoT's parity of 50 gold = 20,000 CR at 1:400. |
| R5 "about 449 Robux/month; pick the local-currency tier $4.99" | **Corrected** | A subscription has a single payment method. The section now recommends Robux pricing, so the price can be tuned. Local-currency prices cannot be changed. |
| R13 "idempotency record (purchaseId) … before returning PurchaseGranted" | **Corrected** | The grant and the `PurchaseId` record are now written in one atomic `UpdateAsync`, because `ProcessReceipt` can run on two servers at once. R13 also now says that crates from the paid pass or from Bullion count as paid random items. |
| R11 Mastery histograms written to a shared DataStore key after every battle | **Corrected** | Writes are now batched per server, about every 60 s, or aggregated in a MemoryStore hash map. This respects the 4 MB/min per-key write throughput and the Read+Write budget cost of `UpdateAsync`. |
| R6 "Tier XI X–XI only, consistent with WoT 2.0" | **Corrected** wording | §1.7 says WoT 2.0 is mostly ±1 with some ±2, so HULLDOWN is *stricter*. |
| R3 arithmetic: per-tier XP closure, 260 battles / 26 h / 65 sessions, the "Net with Premium" column, ratios 74× / 1.5× / 1.38× (WoT 1,694× / 1.48× / 1.21×), R6 node total of 60,000 XP, R7 17 and 531 battles per perk, R10 Season Pass 63 points per session | **Confirmed** | Re-computed by hand. Every row closes, for example Tier VIII 40 × 700 = 28,000 = 7,000 + 21,000, and Tier X net with Premium 187,500 − 115,000 = 72,500. |
