# Research 04: Matchmaking, battle modes, battle rules, maps and map design

> Reference game: World of Tanks PC (Wargaming EU/NA/Asia), state as of 2025–2026 (Update 2.0 on 3 Sep 2025 → Update 2.4
> "Overdrive" in Sep 2026). Prepared for HULLDOWN, an original Roblox game. No WoT assets, client files or datamined
> values are used. Research date: 2026-10-05.
>
> **Read this evidence caveat first.**
> - **No web searches were possible this session.** The shared WebSearch budget was exhausted (200 of 200) before this
>   task started. The egress proxy blocks every WoT/Wargaming domain and Wikipedia, the Internet Archive, Google, Bing,
>   DuckDuckGo and GameSpot. It also blocks the GitHub search API; only repository-scoped GitHub endpoints work.
> - **The evidence comes from four places:**
>   1. **Search-surfaced findings already recorded by the sibling research docs** (01, 02, 05 and 06 in this folder).
>      Where a claim depends on these, the sibling doc and its source links are cited.
>   2. **Domain knowledge** (recollection of patch notes, official articles and long-standing community references).
>      These claims are labelled *(domain knowledge)* and their confidence is capped at **Medium**, except for a few
>      facts that every source agrees on and that have not changed in a decade (for example, 15 v 15 Random Battles).
>   3. **The local clone of the official Roblox creator-docs** (`refs/creator-docs`, snapshot 2026-10-02), which is
>      authoritative for the Roblox platform facts.
>   4. **Reasoning from design principles**, always labelled **OUR DESIGN CHOICE**.
> - Source links marked "(not fetched)" are reference pages given for the team to verify later. They were not opened
>   in this session.
> - Everything that needs online verification is listed under *Open questions*.
>
> **Fact-check pass (2026-10-05).** 17 implementation-critical claims were re-checked independently; see the
> **Verification log** at the end. Web search was exhausted and WoT/Wargaming, Wikipedia, fandom, TAP, Steam, mmos and
> MassivelyOP hosts were blocked, so the check used GitHub-hosted material only: narration captions of WG's official
> "Update 2.0: Overview" video, a mirrored Wikipedia extract (retrieved 2026-07-04), RSS/YouTube metadata archives, WG-wiki
> tank-page text dumps, mod-catalog changelogs, community reimplementation docs, and the Roblox creator-docs repository.
> WoT client-source mirrors (`wot-src`) surfaced in search but were deliberately **not** used (no-datamined-data rule).
> Edits from this pass are marked "(corrected by fact-check)". The most important corrections: WoT **does** use bots to
> fill gaps in Random Battles; the 2.0 matchmaker **does** mirror vehicle roles; Random Battle maps **do** have "random
> events" since before 2.0; preferential MM is not mostly a Tier VIII thing.

---

## Summary

1. **Random Battles are up to 15 v 15.** WoT's Random matchmaker (MM) does **not** use skill, win rate or rating. It
   balances **tiers, vehicle classes and platoons**, and since 2.0 also **vehicle roles** (see item 5). (High for 15 v 15
   as the maximum and for "not skill-based". Wikipedia's 2026 text says a random battle "includes up to 15v15 players;
   bots may be used to fill gaps", so "always exactly 15 v 15 humans" is not safe (corrected by fact-check).)
2. **The template MM has run since Update 9.18 (May 2017).** Each team is built from one of three fixed tier templates:
   **3/5/7** (3 top, 5 middle, 7 bottom tier), **5/10** (two tiers) and **15** (single tier). Both teams mirror each
   other. The **maximum spread is 2 tiers**. Before 9.18 the MM used vehicle "weights" and allowed spreads of 3 or more
   for some scout light tanks. (High for the templates and for 9.18. Medium for the month, which the fact-check could
   not re-confirm. Medium for the pre-9.18 details.)
3. **"Preferential MM" premium vehicles are capped at +1 tier** (they never meet vehicles two tiers above). They exist at
   several tiers (WG-wiki tank pages list Tier III, V and VII examples), not only Tier VIII (corrected by fact-check).
   (High historically. Medium for the 2026 vehicle list.)
4. **WoT 2.0 (3 Sep 2025) tightened the MM** toward ±1 battles. WG's official 2.0 overview says "teams are more often
   built with a one tier difference" and that "teams are limited to **three light tanks and five tank destroyers**
   each". Tier XI only meets Tier X–XI. The other reported caps, **at most 1 wheeled vehicle** and **at most 3 SPGs**,
   are not in the official narration. Update 2.4 (Sep 2026) split light tanks into sub-roles and is reported to cap
   **light tanks at 2 per team**. (High for LT 3 / TD 5 and the ±1 direction (corrected by fact-check). Medium for
   SPG 3. Medium-Low for wheeled 1 and for the 2.4 LT 2 cap, which come only from search summaries in doc 05.)
5. **The MM mirrors classes and, since 2.0, vehicle roles.** WG's 2.0 overview: "vehicle roles are taken into
   account … the matchmaker will put a Badger against a T110E3, not against a Grill 15" (both assault TDs, not a sniper
   TD). Roles (assault, break-through, support, sniper and so on) are therefore a matchmaking input, not only a UI label
   (corrected by fact-check; previously "no source says the MM balances them"). The exact tolerance is not published.
   (Medium-High for role mirroring, Low for its strictness.)
6. **Platoons are 2–3 players** and both teams get the same number of platoons (±1). Whether Random Battles force
   **same-tier platoon vehicles** is not verified: WG-wiki tank pages warn that platooning a preferential-MM tank with a
   normal one drags it into higher battles, which implies mixed-tier platoons were allowed, at least historically.
   (High for the size. Low-Medium for the same-tier rule (corrected by fact-check).)
7. **There is a map blacklist.** Every player can exclude **1 map**, and **WoT Premium Account gives 2** (from the 1.5
   Premium rework in 2019). The MM also avoids giving you the same map repeatedly. (Medium: only sibling doc 05
   supports the slot counts, so the fact-check lowered this from Medium-High.)
8. **Random Battles can contain bots.** Wikipedia's 2026 text says a random battle "includes up to 15v15 players; bots
   may be used to fill gaps" (corrected by fact-check; this doc previously said "Random Battles have no bots"). Which
   tiers, accounts or queue times trigger bot fill is not verified (Low). Bots also appear in the tutorial
   (*Bootcamp*), in PvE events and in the 2.0 solo story mission. Low population is otherwise handled by **template
   fallback** (3/5/7 → 5/10 → 15) and longer queues. (Medium that gap-filling bots exist; Low for their scope.)
9. **Battle rules have barely changed in a decade.** Standard and Encounter battles last **15 min**, Assault **10 min**.
   There is a pre-battle countdown (**30 s**, Medium). A team wins by destroying all enemies or by capturing the base
   (**100 capture points**). When time runs out, Standard and Encounter end in a **draw** and Assault is a **defender
   win**. (High for the win conditions, which Wikipedia confirms: destroy all enemies, or capture the base "by staying
   in it for long enough without being damaged". Medium-High for the 15/10 min timers and timeout results, which no
   reachable source re-confirmed (corrected by fact-check). Medium for the countdown.)
10. **Base capture works per vehicle.** Each vehicle in the circle accumulates its own points. **Only 3 vehicles add
    speed.** Any damage to a capturing vehicle **removes that vehicle's points**. In **Encounter**, the neutral base
    **stops progressing while both teams are inside it**. The commonly cited rate is about **1 point per second per
    vehicle** in Standard: about 100 s for one vehicle and about 34 s for three. Encounter capture is slower. (High
    for the structure. Low–Medium for the exact rates.)
11. **Players can opt out of Encounter and Assault in Settings.** Neither mode appears at the lowest tiers. Grand Battles
    (30 v 30, Tier X) exist but their 2025–2026 status is unverified. (Medium)
12. **Other modes in 2023–2026:**
    - **Onslaught** (internal name "Comp7"): 7 v 7, competitive and seasonal.
    - **Frontline**: 30 v 30 on a 3 × 3 km (9 km²) map, with attack/defend, respawns and combat reserves. Runs as
      periodic episodes.
    - **Steel Hunter**: battle royale, seasonal, current status unclear.
    - **Ranked Battles**: 10 v 10, Tier X. Ran 2018–2022 and has effectively been superseded by Onslaught.
    - **Training Rooms**: permanent.
    - **PvE events**: Halloween modes and the 2.0 story mission (WG's overview calls it a "solo mission",
      Operation Boiling Point on Nordskar; GameSpot's headline calls it a "PvE campaign") (corrected by fact-check).

    (Medium overall)
13. **Map conventions:**
    - Standard maps are about **1 km × 1 km**. City maps are smaller (roughly 600–850 m). Frontline is 3 × 3 km.
    - The minimap grid is **10 × 10**, with rows **A–K skipping I** and columns **1–9 then 0**. Each square is
      one tenth of the map side, so 100 m on a 1 km map.
    - The playable edge is a hard **red-line** boundary.

    (High for 1 km and the 9 km² Frontline map. Medium for the grid labels, which no independent source confirmed
    (corrected by fact-check; was Medium-High).)
14. **Maps follow a "lanes" pattern.** Typically there are **3 main directions**:
    - a close-quarters heavy lane (city or rocks);
    - a ridge or flex lane for mediums (hull-down positions);
    - an open field for light-tank scouting and TD sniping.

    SPGs sit in the rear. WoT reworks maps to fix spawn win-rate imbalance and "open-field sniper/arty" problems. Those
    reworks drew long-running community criticism that maps became **"corridors"** that remove flanking. Maps with
    unfixable problems were **removed**. Dragon Ridge is the best-known example (steep terrain). (Medium)
15. **Destructible objects and physics.**
    - Fences, trees, small houses, walls and cars are destructible. Large buildings, rocks and bridges are not.
    - Fallen trees still give concealment (see doc 02).
    - Vehicle physics, including fall damage, arrived in **8.0 (2012)**.
    - Vehicles **drown** in deep water.
    - Weather and time-of-day map variants are **cosmetic only** (doc 02).
    - Random Battle maps have **no spawn protection**.
    - Some Random Battle maps **do have "random events"** (corrected by fact-check; this doc previously said "no dynamic
      gameplay events"). WG's 2.0 overview: "Update 2.0 brings random events to **four more** maps", for example a
      bunker passage on The Yards, **periodically passing trains** on Ensk that "create dynamic cover", a downed
      airship's wreck on Redshire and bridge debris in southern Paris. "Four more" means some maps had them before 2.0.

    (Medium-High; High for the existence of random events.)
16. **Battle lifecycle.**
    - Loading screen: map, mode, objective, both team rosters and a tip.
    - Then the countdown. Update 2.4 adds a pre-battle "Spotlight".
    - On disconnect the vehicle **stays in battle, uncontrolled**, and you can **reconnect**.
    - A destroyed player can leave. The vehicle and its crew stay **locked until the battle ends**, and rewards arrive
      then. Leaving while alive counts as **desertion or AFK** and is penalised.
    - Team damage exists in Random Battles. It is tracked with "blue" team-killer status and automatic penalties.

    (High for the structure. Medium for the penalty details.)
17. **Communication.** Update **1.10 (2020)** introduced context "smart pings": **T** places a marker on whatever the
    reticle is pointing at, minimap **left-click** means "attention to position" and **right-click** means "moving to
    position". Teammates can **reply** to a command (for example "Affirmative"), and replies are shown on the marker.
    Team chat is the default. Chat with the enemy is off by default. (High for 1.10 as summarised in doc 06. Medium for
    the rest.)
18. **The Roblox platform puts hard rules on our comms and matchmaking.**
    - A **preset/command wheel** must have **12 presets or fewer**, a **10 s per-send rate limit**, **no terminal
      punctuation**, a "system preset" label and `TextService:FilterStringAsync`.
    - At most **50 players per `TeleportAsync`**.
    - Reserved-server access codes **never expire**. The battle place must refuse finished battles.
    - Xbox and PlayStation players with cross-play disabled get a **different `MatchmakingType`** and **cannot share a
      server** with other players. The queue must be partitioned by it.

    (High: local Roblox docs)
19. **Recommended HULLDOWN defaults** (all are OUR DESIGN CHOICE unless marked as parity):
    - **15 v 15** with **bot fill** that switches on progressively from 10 s to 45 s of waiting, and a guaranteed start
      by 45 s.
    - Templates **15 / 5-10 / 3-5-7**, preferring ±1. Max spread 2. Platoons of up to 3, same tier.
    - Timers: **12 min** (Standard/Encounter), **8 min** (Assault). Countdown **20 s** after a 30 s load gate.
    - Capture: **100 pts at 1.0 pt/s per vehicle, max 3 counted** (Standard/Assault). **0.5 pt/s and blocked when
      contested** (Encounter). Capture radius **50 m**.
    - Maps **1000 × 1000 m (3000 × 3000 studs)**; **800 m** for city maps and Tiers I–III; **3 lanes**; spawn
      centroids **≥ 0.7 × map side** apart (700 m on 1 km maps, 560 m on 800 m maps) (corrected by fact-check: a flat
      700 m cannot fit an 800 m map with a rear band behind each spawn, see R8).
    - Bot fill, role mirroring and per-battle map events are listed as deliberate choices in R12.
    - **No friendly-fire damage** (shells are still blocked by allies).
    - **Bot takeover** on disconnect or AFK, with reconnect.
20. **This doc and sibling doc 05 disagree on team size.** Doc 05 assumed **10 v 10** and **6-minute** battles for its
    Battle Heroes thresholds. The architecture doc commits to **15 v 15**, and so does this doc's recommendation. Doc 05's
    thresholds should be rescaled to 15 v 15, or made proportional to team size (see R1).

---

## Detailed findings

### 1. Random Battle matchmaker

#### 1.1 Team size and battle population

- **Modern behaviour:**
  - Random Battles are **15 v 15**.
  - A battle starts only when both teams can be filled according to a template.
  - The MM ignores player skill and statistics. WG has repeatedly stated that Random Battles are deliberately not
    skill-based. This is why third-party "XVM"-style stats overlays became popular, and why "MM is rigged" complaints
    persist.
- **Low population:** the MM falls back to narrower or simpler templates (see 1.3) and queues get longer. Wikipedia's
  2026 text says a random battle "includes up to 15v15 players; bots may be used to fill gaps" (corrected by
  fact-check). So WoT does fill gaps with bots in at least some Random Battles; the conditions (tiers, new accounts,
  wait time) were not found (Low). Historical reports of smaller-than-15 teams on low-population servers could not be
  verified for 2025–2026 (Low).
- **Exact values:** at most 15 per team; 30 vehicles per battle. Grand Battles are 30 v 30 and Frontline is 30 v 30
  (see §3).
- **History:** 15 v 15 since launch (2010).
- **Confidence:** High for 15 v 15 as the maximum and for "not skill-based". Medium that gap-filling bots exist; Low
  for their scope and for team shrinking.
- **Sources:**
  - [WG wiki: Matchmaker](https://wiki.wargaming.net/en/Matchmaker) (not fetched)
  - [Fandom: Battle Mechanics](https://worldoftanks.fandom.com/wiki/Battle_Mechanics) (surfaced in doc 05)
  - Wikipedia "World of Tanks", Gameplay section, via the mirrored extract in [Nice9Tian/stable-query-latent](https://github.com/Nice9Tian/stable-query-latent) `VICReg_review/wiki_descriptions/1407200_World of Tanks.txt` (retrieved 2026-07-04) (fact-check)
  - Domain knowledge.

#### 1.2 Tier spread and "battle levels"

- **Modern behaviour:**
  - Most vehicles meet vehicles **up to 2 tiers above or below**: their "battle level" range is [T−2, T+2], limited
    by the tiers that exist.
  - **Preferential-MM** vehicles meet at most **+1 / −1**. These are premiums at several tiers. WG-wiki tank pages
    list, for example, the Tier III M3 Light (Lend-Lease), the Tier V SU-85I and the Tier VII E 25 ("never sees tier 9
    battles"), besides the well-known Tier VIII "pref MM" heavies (corrected by fact-check; previously "a set of Tier
    VIII premiums").
  - The lowest tiers use narrower ranges.
  - **WoT 2.0** shifted the distribution toward **±1** ("mostly ±1 tier, with some ±2 for variety"). **Tier XI** only
    meets **Tier X–XI**.
- **Exact values:**

  | Vehicle | Possible enemy tiers | Confidence |
  |---|---|---|
  | Standard Tier T (IV–IX) | T−2 … T+2 | High (since 9.18) |
  | Tier X | VIII–X (2.0: also XI as top tier in X–XI battles) | High / Medium |
  | Tier XI (2.0+) | X–XI | Medium (doc 05) |
  | Preferential-MM premium (several tiers, best known at VIII) (corrected by fact-check) | T−1 … T+1 | High (historic), Medium (2026 list) |
  | Tiers I–III | narrower; Tier I mostly with I–II | Medium |

- **History:**
  - **Pre-9.18:**
    - The MM used per-vehicle "battle tier" tables and team "weight" sums.
    - Scout light tanks could meet vehicles **+3** above their tier (for example Tier V scouts in Tier VIII battles).
    - Templates did not exist, so a lone top-tier vehicle facing a team of bottom tiers was possible.
    - Community frustration was intense ("bottom tier every battle").
  - **9.18 (May 2017):**
    - Fixed ±2 for all classes, with light tanks normalised. 9.18 also added Tier VIII–X light tanks.
    - Introduced the templates (see 1.3).
    - WG's stated aims were predictability and fewer battles where you are the only bottom-tier vehicle.
  - **2.0 (3 Sep 2025):** added Tier XI with a narrow X–XI range and moved toward more ±1 battles. WG's 2.0 overview
    video: the core was "almost completely rewritten", and "teams are more often built with a one tier difference".
- **Confidence:** High for ±2 and 9.18. Medium-High for the 2.0 ±1 direction, now backed by WG's own narration
  (corrected by fact-check; was Medium). The exact ±1 / ±2 mix is not published.
- **Sources:**
  - [Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/) (surfaced in doc 05)
  - [mmos.com 2.0 overview](https://mmos.com/news/world-of-tanks-update-2-0-brings-first-ever-tier-xi-tanks-and-a-full-systems-overhaul) (surfaced in doc 05)
  - [WG wiki: Matchmaker](https://wiki.wargaming.net/en/Matchmaker) (not fetched)
  - Domain knowledge for 9.18.

#### 1.3 The template matchmaker (3/5/7, 5/10, 15)

- **Modern behaviour (since 9.18):**
  - Each team is assembled from one of these templates. Both teams use the same one, with the same per-tier counts.

    | Template | Per team (top / mid / bottom) | Tiers in battle | Share of each team at bottom tier |
    |---|---|---|---|
    | **3/5/7** | 3 at T, 5 at T−1, 7 at T−2 | 3 | 7/15 = 46.7% |
    | **5/10** | 5 at T, 10 at T−1 | 2 | 10/15 = 66.7% |
    | **15** | 15 at T | 1 | n/a |

  - The MM prefers 3/5/7. It falls back to 5/10 and then to 15 when the queue at the relevant tiers cannot fill 3/5/7.
    The shape of each tier's queue (too many players at one tier, too few at the tiers around it) decides which
    template is used.
  - Single-tier (15) battles are common at tiers where one tier dominates the queue (historically Tier VIII and X).
    Pre-2.0 community statistics suggested that 3/5/7 was the plurality template for most tiers (Low: no numbers
    retrieved).
- **Generalised formula** (OUR DESIGN CHOICE for other team sizes N):
  - `top = round(0.2·N)`, `mid = round(N/3)`, `bottom = N − top − mid`, which gives 3/5/7 at N = 15 and 2/3/5 at N = 10.
  - `top2 = round(N/3)`, `bottom2 = N − top2`, which gives 5/10 at N = 15 and 3/7 (or 4/6) at N = 10.
- **History:**
  - 9.18 (May 2017): introduced. Templates are mirror-symmetric, so both teams have identical tier counts.
  - Later 1.x patches tuned the template weights and queue logic. The exact changes were not retrieved.
  - 2.0 made ±1 more common (see 1.2).
- **Why:**
  - Predictability: a player is never the only bottom-tier vehicle.
  - Fairness: identical tier composition on both sides.
  - Population: templates degrade gracefully.
- **Confidence:** High for the template shapes and the date. Medium for the fallback order. Low for how often each
  template is used.
- **Sources:**
  - [WG wiki: Matchmaker](https://wiki.wargaming.net/en/Matchmaker) (not fetched)
  - Domain knowledge (9.18 developer articles and release notes).

#### 1.4 Class composition and limits

- **Modern behaviour:**
  - The MM **mirrors vehicle classes** between teams. The aim is the same number of HT/MT/TD/LT/SPG on both sides,
    with a small tolerance at each template level (Medium).
  - The **hard caps per team**, as recorded for WoT 2.0 by sibling doc 05 and re-checked by the fact-check against WG's
    official "Update 2.0: Overview" video ("teams are limited to three light tanks and five tank destroyers each"):

    | Class | Max per team | Since | Confidence |
    |---|---|---|---|
    | SPG | **3** | At least 9.18 (2017); not mentioned in the 2.0 narration | Medium (a community reimplementation of the Random MM also uses 0–3 SPGs per team) |
    | Light tank | **3** (2.0) → **2** (2.4, with light-tank sub-roles) | 2.0 / 2.4 | **High** for 3 in 2.0 (corrected by fact-check; was Medium) / Medium-Low for 2 in 2.4 |
    | Wheeled vehicles (a light-tank sub-type) | **1** | Reported for 2.0. The cap was higher when wheeled vehicles arrived in 1.4 (Mar 2019) | Medium-Low (not in the official narration), Low (history) |
    | Tank destroyer | **5** | 2.0 | **High** (corrected by fact-check; was Medium-Low) |
    | Heavy / Medium | no cap found | n/a | n/a |

  - SPGs are spread evenly between the teams, with a difference of at most 1. Wheeled vehicles are mirrored.
- **Why:** SPG caps exist because SPG-heavy battles are the most-complained-about experience. That complaint drove the
  9.18 SPG rework, with stun and lower alpha damage, and the cap at the same time. The wheeled cap exists because many
  fast wheeled scouts produce chaotic, unfun battles. The 2.4 light-tank cap goes with the sub-role split, and its aim
  appears to be fewer pure-scout mirror-matches.
- **Confidence:** see the table.
- **Sources:**
  - Doc 05 §1.7, citing [Under the Hatch of Tier XI](https://worldoftanks.com/en/news/general-news/update-2-0-tier-11-overview/), [Update 2.4: Overdrive](https://worldoftanks.com/en/news/updates/wot-2-4/) and [MassivelyOP on 2.4](https://massivelyop.com/2026/08/16/world-of-tanks-biggest-update-of-2026-is-coming-with-wait-for-it-more-tanks/)
  - Domain knowledge for 9.18 and 1.4.

#### 1.5 Role and sub-role balancing

- **Modern behaviour:**
  - Since about **2021** (Medium-Low), each vehicle has a displayed **role**. Examples:
    - heavy: Assault / Break-through / Support / Versatile;
    - medium: Assault / Support / Versatile / Sniper;
    - TD: Assault / Sniper / Support;
    - light: Recon / Wheeled and, from 2.4, scout / versatile / support sub-classes;
    - SPG.
  - Roles feed missions (the 2.0 Personal Missions are done "in vehicles of corresponding roles") and, in
    **Onslaught**, role-specific abilities.
  - **The 2.0 Random MM takes roles into account** (corrected by fact-check; this section previously said no source
    showed it). WG's 2.0 overview: "vehicle roles are taken into account", "the matchmaker will put a Badger against a
    T110E3, not against a Grill 15". Badger and T110E3 are assault TDs; Grill 15 is a sniper TD. So within a class the
    MM tries to mirror roles as well. How strict this is (hard mirror or soft preference) is not published.
  - 2.4 adds light-tank sub-classes and is reported to cap light tanks at 2 per team (doc 05, unverified).
- **Confidence:** Medium-High for role mirroring in 2.0. Low for its tolerance. Medium-Low for the 2.4 details.
- **Sources:**
  - WG "Update 2.0: Overview" video narration, minutes 8–9, as captioned in [Heinz217/TraceAV-Bench-Submission](https://github.com/Heinz217/TraceAV-Bench-Submission) `intermediate/step2_audio_visual_fusion/per_minute_fusion_captions/video129.json` (fact-check)
  - Doc 05 (2.4 light-tank sub-roles)
  - Domain knowledge.

#### 1.6 Platoons

- **Modern behaviour:**
  - Random Battle platoons have **2–3 players**.
  - The MM keeps the **number of platoons per team equal, within ±1**. Members are always on the same team.
  - Current Random Battles are *believed* to require **all platoon vehicles to be the same tier**, but this is
    unverified. WG-wiki tank pages advise players not to platoon a preferential-MM tank with friends in normal tanks,
    "or you will be facing tier 6", which shows mixed-tier platoons were allowed at least when those pages were written
    (corrected by fact-check). Mixed-tier "failtoons" drew heavy criticism before 9.18.
  - WoT Premium Account gives platoon credit bonuses: the account holder gets +15% and platoon-mates without Premium
    get +10% (doc 05).
- **Confidence:** High for the size (Wikipedia: "groups of two or three players who are put into the same team").
  Low-Medium for the same-tier rule (corrected by fact-check; was Medium). Medium for platoon balancing.
- **Sources:**
  - Doc 05 §1.5, citing [1.5 WoT Premium Account](https://worldoftanks.eu/news/general-news/1-5-wot-prem-account/)
  - Wikipedia extract (see 1.1) and WG-wiki tank-page dumps in [aa-tolmachev/django-qa](https://github.com/aa-tolmachev/django-qa) `homepage/data/all tanks/J22 Type 95.txt` (fact-check)
  - Domain knowledge.

#### 1.7 Queue time and relaxation

- **Modern behaviour:**
  - The client shows a queue timer and an exit button.
  - Low-population tiers and hours wait longer. The MM falls back across templates and does not expand beyond ±2.
    Bots "may be used to fill gaps" (Wikipedia), but when that kicks in is not published (corrected by fact-check).
  - WG's 2.0 overview says the rewritten MM "adapts better" to player numbers and vehicle distribution, looking for
    "the best compromise between reducing wait times and assembling the two most balanced teams".
  - WG has not published a relaxation schedule (the seconds at which each constraint loosens).
- **Confidence:** Low for any timing values. None are given here.
- **Sources:** Domain knowledge.

#### 1.8 Map rotation, selection and blacklist

- **Modern behaviour:**
  - Each map has a **range of battle levels** it is used for. Small maps are used for low tiers, and some maps are
    excluded at Tiers I–III.
  - Each map also lists the **modes** it supports (Standard, Encounter, Assault).
  - The MM picks the map after forming the teams.
  - It avoids repeating maps you played recently (a "map variety" improvement in 1.x; version not verified).
  - **Map blacklist** ("map exclusion"): **1 slot for everyone, 2 with WoT Premium Account**. It was part of the
    Premium rework in **Update 1.5 (2019)**. There is a cooldown on changing an excluded map, but its value was not
    verified.
- **Confidence:** Medium for 1 + 1 slots (lowered from Medium-High by fact-check: no source independent of doc 05).
  Medium for the tier ranges. Low for the cooldown and the
  anti-repeat algorithm.
- **Sources:**
  - Doc 05 §1.5, citing [1.5 WoT Premium Account](https://worldoftanks.eu/news/general-news/1-5-wot-prem-account/) and [Release notes 1.5](https://worldoftanks.asia/content/docs/release_notes/15/)
  - Domain knowledge.

#### 1.9 Server regions and peripheries

- **Modern behaviour:**
  - Wargaming runs three realms: **EU, NA and Asia**. Each realm has several **peripheries** (server clusters). Players
    pick one, or let the client choose by ping.
  - The MM runs per periphery, so population per periphery drives queue times.
  - In 2022 the former CIS realm passed to **Lesta Games** as **Mir Tankov**, which has diverged since in content and
    mechanics. This doc follows the WG realms.
- **Confidence:** Medium. The periphery names and locations were not verified.
- **Sources:** Domain knowledge.

#### 1.10 Bots

- **Modern behaviour:**
  - **Random Battles: bots may fill gaps** (corrected by fact-check; this section previously said "no bots").
    Wikipedia's 2026 text: "A random battle includes up to 15v15 players; bots may be used to fill gaps." The
    conditions are not known: reports point to brand-new accounts and the lowest tiers, and Lesta's Mir Tankov also
    added "battles with bots", but neither detail could be verified for WG realms (Low).
  - Bots also appear in:
    - **Bootcamp**, the tutorial (since about 2017, Medium-Low);
    - **PvE event modes**, such as Halloween modes;
    - the **2.0 story mission**. WG's overview calls it a "solo mission" (Operation Boiling Point on Nordskar); a
      GameSpot headline called it a "new PvE campaign" (Medium).
- **Why WoT keeps bots marginal in Random:** a large population, a "real opponents" promise, and economy and anti-farm
  concerns.
- **Why this matters for us:** Roblox launch population will be far smaller. WoT already accepts bots as gap fillers;
  HULLDOWN's deviation is the **scale** of bot fill (any tier, progressive from 10 s, labelled), see R1.
- **Confidence:** Medium that WoT uses gap-filling bots. Low for when and where.
- **Sources:**
  - [GameSpot: 2.0 adds Tier XI tanks, new PvE campaign](https://www.gamespot.com/articles/world-of-tanks-2-0-adds-tier-xi-tanks-new-pve-campaign-and-more-next-month/1100-6534078/) (title surfaced in doc 06)
  - Wikipedia extract (see 1.1) and the WG 2.0 overview narration (see 1.5) (fact-check)
  - Domain knowledge.

---

### 2. Battle rules

#### 2.1 Battle types in Random Battles

| Type | Objective | Timer | When the timer expires | Availability |
|---|---|---|---|---|
| **Standard** | Each team has a base. Win by destroying all enemies or by capturing the enemy base | **15:00** | **Draw** | All tiers; the default |
| **Encounter** | One **neutral** base. Win by destroying all enemies or by capturing it | **15:00** | **Draw** | Mid and high tiers; can be turned off in Settings |
| **Assault** | One team defends a base. Attackers win by destroying all enemies or capturing it. Defenders win by destroying all attackers or **surviving until the timer ends** | **10:00** | **Defenders win** | Mid and high tiers; can be turned off |
| **Grand Battle** | Standard-like rules, **30 v 30**, on larger maps | n/a | n/a | Tier X (introduced around 2017). Current status unverified |

- **Confidence:** High for the objectives (Wikipedia: win by destroying all opposing vehicles or by capturing the base
  "by staying in it for long enough without being damaged"). Medium-High for the 15/10 min timers, which no reachable
  source re-confirmed (corrected by fact-check; was High). Medium for the tier availability and the opt-out toggles.
  Low for Grand Battles in 2025–2026.
- **Sources:**
  - [Fandom: Battle Mechanics](https://worldoftanks.fandom.com/wiki/Battle_Mechanics) (surfaced in doc 05)
  - [Getting Started](https://worldoftanks.com/content/guide/newcomers-guide/getting_started/) (surfaced in doc 06)
  - Domain knowledge.

#### 2.2 Base capture mechanics

- **Modern behaviour:**
  - Each team's capture progress runs from 0 to **100 points**. Reaching 100 ends the battle immediately.
  - Each vehicle inside the circle **accumulates its own capture points**.
  - **At most 3 vehicles add speed.** A 4th or 5th vehicle in the circle does not make capture faster.
  - **Damage removes points.** Any HP damage to a capturing vehicle, from any enemy (or, historically, an ally), resets
    that vehicle's accumulated points. The team's progress drops by that amount.
  - Defenders earn **"capture points reset"** credit. This feeds the Defender medal (≥ 70 points reset) and XP (doc 05).
  - Capturers earn **capture points**. These feed the Invader medal (≥ 80 points in a successful capture) and XP.
  - **Leaving the circle** forfeits that vehicle's points (Medium).
  - **Standard:** defenders standing in the circle **do not** stop the capture. Only damage resets it (Medium-High).
  - **Encounter:** the neutral base **freezes while vehicles of both teams are inside it** (Medium-High). It also caps
    more slowly than a Standard base (Medium).
  - Whether **stun** or **module-only critical hits** (with no HP damage) reset capture points is not verified (Low).
    The usual understanding is that HP damage resets and stun does not.
- **Exact values (as far as known):**

  | Parameter | Value | Confidence |
  |---|---|---|
  | Points to capture | 100 | Medium-High (not re-confirmed by fact-check; was High) |
  | Vehicles counted toward speed | 3 | Medium-High (not re-confirmed by fact-check; was High) |
  | Standard rate | ~1 pt/s per vehicle → ~100 s alone, ~34 s with 3 | Low–Medium (community recollection) |
  | Encounter rate | noticeably slower than Standard; recollection is "about 2–2.5× longer" | Low |
  | Capture circle radius | not retrieved. Visually tens of metres across | — |

- **History:** the structure is unchanged since the early game. 9.x tweaks to reset behaviour (crits, stun) were not
  verified.
- **Sources:**
  - Doc 05 §2.1 and §8 (Defender/Invader thresholds)
  - [Fandom: Battle Mechanics](https://worldoftanks.fandom.com/wiki/Battle_Mechanics)
  - Domain knowledge.

#### 2.3 Victory, defeat and draw

| Situation | Standard | Encounter | Assault |
|---|---|---|---|
| All enemies destroyed | Win | Win | Win (either side) |
| Base captured (100 pts) | Capturing team wins | Capturing team wins | Attackers win |
| Timer expires | **Draw** | **Draw** | **Defenders win** |
| Last vehicles of both teams destroyed together | Draw (Medium) | Draw (Medium) | Medium (unverified) |

Draws pay out like a loss (no win bonus). Confidence: High for the main rows, Medium for the edge cases.

#### 2.4 Team damage, "blue" status and penalties

- **Modern behaviour:**
  - Random Battles **have team damage**: shells, HE splash and ramming can hurt allies.
  - Each case is tracked automatically:
    - The offender pays compensation for the victim's repair and loses reward.
    - Repeat offenders are shown **blue** to teammates in later battles.
    - Severe or repeated cases bring temporary bans.
  - Some special modes disable team damage (Medium-Low).
  - Doc 01 lists ally ramming as still present (not re-verified).
  - Other sources say WoT Console removed friendly fire; this was not verified (Low).
- **Confidence:** High that team damage exists. Medium for the penalty structure. Low for exact values.
- **Sources:**
  - Doc 01 (open question 14)
  - Domain knowledge.

#### 2.5 AFK, desertion and inactivity

- **Modern behaviour:**
  - An automatic system flags inactive players (no movement or damage) and players who leave while alive.
  - Penalties escalate: zero or reduced rewards, then temporary bans from Random Battles of increasing length.
  - Players can also **report** others after battle, with a daily cap on reports.
  - Doc 05 records an **XP clamp to zero for AFK players**, detected when movement plus damage stays below a threshold
    for **90 s**. That is a HULLDOWN design value in doc 05, not a WoT fact.
- **Confidence:** Medium for the structure. Low for thresholds and ban lengths.
- **Sources:** Domain knowledge; doc 05 R-section.

---

### 3. Other modes: status in 2024–2026

| Mode | Format | Status 2024–2026 | Confidence |
|---|---|---|---|
| **Random Battles** (Standard / Encounter / Assault) | Up to 15 v 15; bots may fill gaps (corrected by fact-check) | Permanent, the core mode | High |
| **Training Rooms** | Custom rooms. Any map and mode, up to 15 v 15. Usable solo to learn maps | Permanent | Medium |
| **Bootcamp** | Scripted tutorial against bots | Permanent onboarding (since about 2017) | Medium |
| **"Topography" / map practice** | Solo map exploration | Clearly reported for Mir Tankov (Lesta). Not verified for WG realms. On WG realms, solo Training Rooms fill this role | Low |
| **Ranked Battles** | 10 v 10, Tier X, leagues and divisions | Seasonal 2018–2022. Effectively replaced by Onslaught | Medium |
| **Onslaught** ("Comp7") | **7 v 7**, competitive with ranks, mostly Tier X (later seasons varied). Point control plus **role abilities** | Seasonal since 2023. Still running alongside 2.x (WoT Plus Gold Reserve is earned "in Random, Onslaught and Frontline") | Medium |
| **Frontline** | **30 v 30**, attack/defend on a **3 × 3 km (9 km²)** map. Capture sectors, then destroy gun emplacements. Respawns, timer extensions, ranks and **combat reserves** (smoke: 5 grenades over 200 × 50 m for 50 s; airstrike; artillery) | Periodic episodes and seasons since 2018–2019. Originally Tier VIII | High (format), Medium (current status) |
| **Steel Hunter** | Battle royale: solo (20 players) or duos. Special vehicles that level up, loot, a shrinking zone | Seasonal events 2019/2020 – ~2023. Current status unclear | Low-Medium |
| **Grand Battles** | 30 v 30 Tier X on larger maps | Introduced around 2017. Current status unclear | Low |
| **Clan modes** | Strongholds: 7 v 7 skirmishes and 15 v 15 advances. Global Map Clan Wars: 15 v 15 campaigns | Permanent or campaign-based | Medium |
| **PvE events** | Halloween modes (for example Mirny-13), arcade events, and the **2.0 solo story mission** (Operation Boiling Point on Nordskar; corrected by fact-check, was "campaign") | Limited-time, except the 2.0 story mission | Medium |

**Lesson for us:** WoT keeps exactly one permanent PvP queue (Random). Every other mode is seasonal so that the Random
population is not split. A low-population Roblox game has even more reason to do the same.

**Sources:**
- [Frontline Rules & Regulations](https://worldoftanks.asia/en/content/frontline-regulations/) and [Frontline: combat reserves guide](https://worldoftanks.eu/en/news/general-news/frontlines-reserves-guide/) (surfaced in doc 02)
- [WoT Plus guide](https://worldoftanks.eu/en/news/general-news/wot-plus-guide/) (surfaced in doc 05)
- [GameSpot 2.0 PvE campaign](https://www.gamespot.com/articles/world-of-tanks-2-0-adds-tier-xi-tanks-new-pve-campaign-and-more-next-month/1100-6534078/) (doc 06)
- Domain knowledge.

---

### 4. Maps and map design

#### 4.1 Size

| Map class | Typical size | Confidence |
|---|---|---|
| Standard Random map | **1000 × 1000 m** (1 km²) | High |
| City or compact maps | ~600–850 m per side | Medium |
| Low-tier pool (I–III) | Subset of smaller maps | Medium |
| Grand Battle maps | ~1.4 × 1.4 km | Low-Medium |
| Frontline | **3 × 3 km** (9 km²) | High |

These sizes fit the spotting model in doc 02. The max spotting range is 445 m and the draw radius is 564 m. On a 1 km
map you therefore cannot see across the whole map, but you can see across the middle third.

#### 4.2 The lane principle

- **Modern practice (Medium).** Maps are built around **3 main directions (flanks)** plus rear positions:

  | Lane | Purpose | Terrain | Typical engagement distance |
  |---|---|---|---|
  | **Heavy lane** | Brawling and armour play | City blocks, rock clusters, ravines; hard cover; short sightlines | 30–150 m |
  | **Medium/flex lane** | Hull-down and mobility | Ridges, hills, rolling terrain with reverse slopes | 100–300 m |
  | **Open field / LT-TD lane** | Spotting and sniping | Open field with bushes and few hard-cover islands; long sightlines | 200–450 m |
  | **Rear / SPG zone** | Artillery and fallback | Behind the spawn, protected from direct fire by terrain | n/a |

- Lanes connect through a few transitions near the middle, so a won flank can rotate onto the base or into the back
  of another flank. That is the core strategic loop.
- **Community criticism (Medium).** Reworks in the late 9.x to 1.x era added cover and narrowed sightlines to curb
  open-field sniping and SPG dominance. The result is often described as **"corridor maps"**: fewer viable routes, more
  predictable lane-locked games and less room for flanking or light-tank play. WG's position was that the goal is
  balanced spawns and varied engagement distances.
- **Sources:** Domain knowledge (WG map-design developer diaries and community analysis).

#### 4.3 How WG designs and balances maps

- **Process (Medium):**
  1. Concept: setting and gameplay goals.
  2. Grey-box prototype.
  3. Internal and Supertest playtests, measured with **heat maps** of positions, shots and deaths.
  4. Balance by **win rate per spawn**, broken down by tier and mode.
  5. Art pass.
  6. Live monitoring.
- **What triggers a rework or removal:**
  - a significant spawn win-rate gap;
  - one lane deciding most battles;
  - SPG-safe or camp-safe zones;
  - terrain that excludes vehicles, such as slopes that punish poor gun depression.
- **Examples (Medium-Low):**
  - **Dragon Ridge** was removed (around 2015): extreme verticality, and vehicles with poor gun depression were
    useless.
  - Several maps were reworked to add cover across open fields (the Malinovka-type and Prokhorovka-type fields).
  - Several maps were removed and later re-released in reworked form.
- **1.0 (20 Mar 2018):** all maps were remastered in HD, re-authoring vegetation and visuals. Doc 02 found no rule
  change.
- **Exact numbers:** WG's spawn win-rate acceptance threshold was not retrieved.
- **Sources:** Domain knowledge; doc 02 (1.0 remaster).

#### 4.4 Destructible objects

- **Modern behaviour (Medium-High):**
  - Destructible: fences, small walls, sheds and small houses (partially), trees, poles and civilian vehicles. They are
    knocked down by ramming and by shells.
  - Not destructible: large buildings, rocks, terrain and bridges. They are permanent hard cover.
  - Fallen trees still give foliage concealment (doc 02).
  - Destroyed objects stop blocking line of sight and shells.
- **Sources:** Doc 02 (foliage); domain knowledge.

#### 4.5 Water, falls and overturning

- **Modern behaviour (Medium):**
  - Shallow water slows vehicles.
  - A vehicle **drowns** when it is submerged deeply enough. The commonly cited trigger is the water reaching the top
    of the turret (the roof of the fighting compartment). A warning and a short delay come first.
  - **Falls cause damage**: physics arrived in **8.0 (Sep 2012)**.
  - Overturned vehicles are immobilised, and allies can push them back.
- **Exact values** for drowning depth, delay and fall-damage formula were not retrieved (see doc 01 and the movement
  research).
- **Confidence:** Medium for the structure. Low for the numbers.

#### 4.6 Map boundaries

- The playable area ends at a **hard boundary**. It is shown as a **red line** on the minimap and as a translucent
  barrier when you drive up to it.
- Terrain continues visually beyond it.
- Confidence: High (domain knowledge).

#### 4.7 Elevation and height maps

- Maps are heightmap terrain plus placed objects.
- Relief varies from flat steppe to mountain maps with large vertical differences.
- Gun depression and elevation interact with terrain, so ridge lines and reverse slopes are designed on purpose.
- Exact elevation ranges were not retrieved. Confidence: Medium.

#### 4.8 Minimap representation

- **Grid:** 10 × 10 squares. Rows are labelled **A B C D E F G H J K** (I is skipped) and columns **1 2 3 4 5 6 7 8 9 0**.
  Players call squares like "E5" or "J0". (Medium: domain knowledge, and doc 06 also rates it Medium. The fact-check
  found no independent source, so it was lowered from Medium-High.)
- **Overlays:**
  - Since **9.5**: last-spotted positions, view vector and SPG arc.
  - Since **9.14**: circles for view range, max spotting range and draw range.
  - Since **9.15**: last-spotted markers are on by default.
- **Pings:** since **1.10**, minimap left-click means "attention" and right-click means "moving here".
- **Sources:**
  - [9.5 update notes](https://worldoftanks.com/en/content/docs/release_notes/95-updatenotes/)
  - [9.14 update notes](https://worldoftanks.com/en/content/docs/release_notes/914-updatenotes/)
  - [9.15 update notes](https://worldoftanks.com/en/content/docs/release_notes/915-updatenotes/)
  - [1.10 battle communication](https://worldoftanks.eu/en/news/general-news/1-10-battle-communication/)

  (all surfaced in doc 06)

#### 4.9 Spawns and spawn protection

- **Modern behaviour (Medium):**
  - Each team has a spawn area of fixed slots near its map edge or corner. SPGs typically spawn at the rear.
  - There is **no invulnerability or spawn protection** in Random Battles. Protection comes from geometry: distance,
    and terrain that blocks sightlines into the spawn.
  - Frontline respawns let you choose a sector, but its spawn protection was not verified.
- **Exact values:** spawn separation is not published. On 1 km maps the two spawns are roughly ½ to ¾ of the map side
  or diagonal apart.

#### 4.10 Weather, time of day and map events

- **Weather and time:** some maps have alternative visual variants (winter, night or dusk, burning-city variants and
  so on). They are **cosmetic only** and do not change view range or camo (doc 02). Random Battles have **no
  gameplay weather**.
- **Random events (corrected by fact-check).** This section previously said Random Battle maps are static with no
  gameplay events. That is wrong for 2.x. WG's "Update 2.0: Overview" video: "Update 2.0 brings random events to four
  more maps":
  - The Yards: "a bunker with a passage";
  - Ensk: "periodically passing trains that create dynamic cover for moving forward or changing position";
  - Redshire: "a downed airship's wreckage provides cover";
  - southern Paris: bridge debris "creates new tactical opportunities".

  "Four more" means some maps already had random events before 2.0 (which maps and since which version was not
  found). Most of these look like per-battle layout changes (cover appears or a passage opens). The Ensk trains are
  a true in-battle dynamic element. How often each event is rolled per battle is not published.
- Other dynamic gameplay elements exist in special modes:
  - Frontline: airstrike and artillery reserves, gun emplacements, timer extensions;
  - Steel Hunter: shrinking zone and air drops;
  - Halloween PvE: scripted waves.
- **Confidence:** High that random events exist on some Random Battle maps (official narration). Low for their
  frequency and the full map list. Medium for the special-mode details.
- **Sources:** WG 2.0 overview narration, minutes 15–16, captioned in [Heinz217/TraceAV-Bench-Submission](https://github.com/Heinz217/TraceAV-Bench-Submission) `intermediate/step2_audio_visual_fusion/per_minute_fusion_captions/video129.json` (fact-check).

#### 4.11 Loading screen

- **Current behaviour:**
  - Map name and art, battle type, an **objective sentence**, **complete rosters for both teams** (player, vehicle,
    class and tier, platoon markers) and a **gameplay tip**.
  - **2.4 (Sep 2026)** adds a pre-battle **"Spotlight"** for Tier V+ Random Battles. Its length adapts to loading time.
- **Confidence:** High for rosters and objective (doc 06). Low for the content of Spotlight.
- **Sources:**
  - [Getting Started](https://worldoftanks.com/content/guide/newcomers-guide/getting_started/)
  - [2.4 Spotlight](https://worldoftanks.eu/en/news/general-news/2-4-spotlight/)

  (both surfaced in doc 06)

---

### 5. Battle lifecycle

| Phase | WoT behaviour | Confidence |
|---|---|---|
| Queue | Select vehicle, press Battle, queue with a timer and an exit option. Platoon leader queues for the platoon | High |
| Loading | Loading screen (§4.11). In 2.4, Spotlight first | High / Low |
| Pre-battle countdown | **30 s** in Random Battles. Vehicles cannot move or fire, but players can look around, check the minimap and chat | Medium |
| Battle | Up to 15:00 (Assault 10:00) | High |
| Disconnect | **The vehicle stays in the battle, stationary and uncontrolled**, and can be destroyed. **You can reconnect** to the same battle from the garage. No AI takes over | High |
| Destroyed | You can spectate or **leave to the garage**. **That vehicle and its crew stay locked ("in battle") until the battle ends.** You can play other vehicles | High |
| Leaving while alive | Allowed, but the vehicle stays uncontrolled. Counts toward **desertion/AFK penalties**; you forfeit your contribution | Medium |
| End | Victory/defeat/draw banner, then back to the garage | High |
| Results | Processed server-side and delivered when the battle ends, even if you left early. 2.0 shows them full-screen: **General / Team Result / Financial Report**, with a score table overlay and a "next battle" button | High (doc 06) |

**Sources:**
- [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/) (doc 06)
- [Getting Started](https://worldoftanks.com/content/guide/newcomers-guide/getting_started/)
- Domain knowledge.

---

### 6. Communication

- **The battle-communication system of 1.10 (2020)** (High, as summarised in doc 06):
  - **T** places a context marker on whatever the reticle is pointing at:
    - on an enemy: "attacking / focus fire on";
    - on an ally: help or support related;
    - on terrain: "attention to position";
    - on your own base: "defending base";
    - on the enemy base: "attacking base".
  - Minimap left-click means **"attention to this position"** and right-click means **"moving to this position"**.
    SPGs get artillery-specific commands.
  - **Replies:** teammates acknowledge a command, for example with "Affirmative". The marker shows who acknowledged.
    This turns pings into lightweight coordination without typing.
- **Command menu:** a radial menu (hold key) and F-key quick commands cover the fixed set. Typical entries are
  Affirmative / Negative / Help / Reloading / Thanks / Attack / Defend base / Hold position / Follow me. The exact
  2026 list and key bindings were not verified (Medium-Low).
- **Chat:** team chat by default. Enemy ("All") chat is **off by default** and can be enabled in settings. Chat bans and
  anti-spam exist (Medium).
- **Sources:**
  - [1.10 battle communication](https://worldoftanks.eu/en/news/general-news/1-10-battle-communication/)
  - [In-game communication guide](https://worldoftanks.eu/en/content/guide/newcomers-guide/communication/)
  - [1.10 list of changes](https://worldoftanks.com/en/content/docs/release_notes/update-1-10-list-of-changes/)

  (all surfaced in doc 06)

---

### 7. Roblox platform facts that constrain this topic (authoritative: local creator-docs, 2026-10-02)

| Fact | Consequence for HULLDOWN | Doc |
|---|---|---|
| `TeleportService:TeleportAsync()`: "No more than **50 players** can be teleported with a single call." Server-only. Teleports can fail; the docs recommend retries | A 30-player battle fits in one call per hub. Each hub teleports its own players and retries (5 attempts in the docs' `SafeTeleport` sample) | [TeleportService](https://create.roblox.com/docs/reference/engine/classes/TeleportService), [Teleport between places](https://create.roblox.com/docs/projects/teleport) |
| `ReserveServerAsync` access codes "remain valid **indefinitely**". A new server starts if none is running | A late reconnect after the battle ended would start an **empty new battle server**. The battle place must read the manifest, see `status = Finished` and send the player back to the Hub | same |
| Xbox and PlayStation players with cross-play disabled "arrive in a different server". `DataModel.MatchmakingType` (`Default` / `XboxOnly` / `PlayStationOnly`); "players with different MatchmakingTypes **cannot be in or teleport to the same server**" | The queue must be **partitioned by MatchmakingType**, or a match can split into two half-empty servers that share one `PrivateServerId` | [DataModel.MatchmakingType](https://create.roblox.com/docs/reference/engine/classes/DataModel), `Enum.MatchmakingType` |
| MemoryStore quota: **1000 + 120 × CCU** request units per minute, memory **64 KB + 1.2 KB × users**. Sorted maps and queues each sit on one partition, which throttles at about **30k RU/min**. Max 100 MB / 1M items per structure. Default TTL 45 days; set it short | Short-TTL tickets (120 s) refreshed by heartbeats. One sorted map per pool. A leader tick every 2 s | [Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores) |
| Roblox's built-in server matchmaking scores *public* servers by signals (latency, location, age group, custom attributes). The latency score is `1 − min(100, Δping)/100`. Reserved servers are excluded from it | Battle servers are reserved, so we must do **our own region bucketing**. Built-in custom attributes can still help Hub placement (for example grouping players by tier band to shorten queues) | [Matchmaking](https://create.roblox.com/docs/matchmaking), [Attributes and signals](https://create.roblox.com/docs/matchmaking/attributes-and-signals) |
| `LocalizationService:GetCountryRegionForPlayerAsync` returns a country code from IP geolocation | Coarse region bucketing (NA / SA / EU / APAC / OCE) | [LocalizationService](https://create.roblox.com/docs/reference/engine/classes/LocalizationService) |
| **Preset system guidelines** for command wheels: **≤ 12 presets**; **rate limit 10 s per send**; **no terminal punctuation** ("!", "?", "."); UI labelled **"system preset"** when shown in chat; visually distinct from free chat; **filtered with `TextService:FilterStringAsync()`**; tactical commands such as "Attack", "Defend", "Hold Position", "Reloading" and "Thanks" are explicitly allowed; question/answer structures and encodings are forbidden | Our command wheel must have ≤ 12 entries with no "!" and must rate-limit chat-visible presets to one per 10 s per player | [Preset system guidelines](https://create.roblox.com/docs/chat/preset-system-guidelines) |
| `TextChatService` default channels include **`RBXTeam`** (team tab) | Team chat comes from the platform, with age-based chat rules applied automatically | [Chat window](https://create.roblox.com/docs/chat/chat-window) |
| `TeleportService:SetTeleportGui` / `GetArrivingTeleportGui` and `ReplicatedFirst:RemoveDefaultLoadingScreen` | A seamless Hub → Battle loading screen that can show rosters before the battle place finishes loading | [Loading screens](https://create.roblox.com/docs/players/loading-screens) |

---

## Implementation recommendations for HULLDOWN (Roblox)

Units follow `docs/ARCHITECTURE.md`: config is in metres, and `Units.STUDS_PER_METER = 3`. Every value below is a
`Shared/Config` default that can be tuned live. **Parity** means it copies WoT. **OUR DESIGN CHOICE** means it
deliberately differs from or extends WoT.

### R1. Team size and bot-fill policy

- **Random Battles stay 15 v 15** (parity; already in the architecture doc).
  - Lanes, spotting radii (doc 02) and capture tuning all assume about 5 vehicles per lane.
  - Bot fill makes team size independent of population, so shrinking teams gains us nothing.
  - 30 vehicles at 30 Hz with 450 directed spotting pairs fits the server budget (doc 02).
- **Bot fill (OUR DESIGN CHOICE: the main deviation from WoT in scale, not in kind).** WoT itself lets bots "fill
  gaps" in some Random Battles (§1.10, corrected by fact-check), but only marginally. HULLDOWN uses bot fill at every
  tier and as the normal way a battle reaches 15 v 15. Roblox launch CCU will be tiny compared with WoT. With 15 v 15
  and 11 tiers, a humans-only queue would never pop.
  - Humans are distributed so that `|humansA − humansB| ≤ 1`. Platoons count as a unit.
  - Bots take **template slots**, so they have the slot's tier and a class (and role, see R3) that keeps the mirror.
  - Bots are **never** in platoons.
  - Bots are labelled honestly: a bot icon in the roster and a "Bot" suffix on markers. Roblox players accept
    labelled bots, and hidden bots damage trust.
  - **Bot skill** scales with the average experience of the battle's humans:
    - new accounts (< 20 battles) get "Recruit" bots;
    - most battles get "Regular" bots;
    - Tier VIII+ battles get "Veteran" bots.
  - **Rewards:** damage and kills on bots pay normal XP and credits. Low-population players should not be punished for
    the population. Bot-heavy battles (more than 50% bots) are **excluded from leaderboards, ranked modes and
    "vs-players" achievements**. The results record `botShare` for analytics.
  - **Anti-farm:**
    - Bots use the same economy as everyone else.
    - A battle with **0 human enemies** caps rewards at the "PvE" rate. Default **×0.75** (OUR DESIGN CHOICE; align with
      doc 05).
    - The AFK rules in R9 apply.
- **Doc 05 should be reconciled.** Express Battle Heroes and other thresholds as fractions of team size, or rescale its
  10 v 10 numbers by 1.5.

### R2. Tier spread and templates

```lua
-- Shared/Config/Matchmaking.luau (proposed defaults)
TEAM_SIZE = 15,
TIER_MIN = 1, TIER_MAX = 11,
MAX_SPREAD = 2,                          -- hard cap (parity since 9.18)
TEMPLATES = {                            -- per team, top tier first
	{ id = "T1", counts = { 15 } },
	{ id = "T2", counts = { 5, 10 } },
	{ id = "T3", counts = { 3, 5, 7 } },
},
TEMPLATE_WEIGHT = { T1 = 1.0, T2 = 1.0, T3 = 0.6 }, -- OUR DESIGN: prefer ±1 (WoT 2.0 direction)
LOW_TIER_MAX_SPREAD = { [1] = 1, [2] = 1, [3] = 1 }, -- tiers I–III: only T1/T2 templates
TIER_RANGE_OVERRIDE = { [11] = { 10, 11 } },        -- top tier meets only X–XI (parity with 2.0)
PREFERENTIAL_MM_ALLOWED = false,         -- OUR DESIGN: no pay-for-easier-MM; content may set mmSpreadOverride later
BOTTOM_TIER_STREAK_PROTECTION = 2,       -- OUR DESIGN: after 2 bottom-tier battles in a row, prefer a non-bottom slot
```

- **Template scoring** (OUR DESIGN CHOICE). For every feasible candidate `(topTier, template)`:

  `score = 10·humans − 6·bots·(1 − relax) − 7.5·(1 − TEMPLATE_WEIGHT[template]) − 2·classMirrorError − 1·roleMirrorError − platoonImbalance`

  Here `relax ∈ [0, 1]` rises with the oldest ticket's wait (R4). The template term reads `TEMPLATE_WEIGHT`, so there
  is one tuning knob: with the defaults it is 0 for T1/T2 and −3 for T3 (corrected by fact-check: the formula
  previously hard-coded `−3·[template = T3]` beside an unused `TEMPLATE_WEIGHT`). `roleMirrorError` is the soft role
  term from R3.
  - Humans are placed by queue age.
  - When a template has spare slots at several tiers, humans go to the **upper** slots and bots to the bottom slots.
    This is cheap with bots, it removes WoT's most-hated experience (always bottom tier), and it never makes a human
    face a human two tiers higher without a reason.
- **Why ±1 is preferred:** WoT itself moved that way in 2.0. In a bot-filled game, the population argument for the
  3/5/7 template is weaker. 3/5/7 is used when it lets **more humans** into the same battle.

### R3. Class limits, mirroring and platoons

```lua
CLASS_LIMITS = { LT = 3, LT_WHEELED = 1, TD = 5, SPG = 2 },  -- per team; HT/MT uncapped
CLASS_MIRROR_TOLERANCE = 0,              -- strict at relax 0; becomes 1 at relax ≥ 0.5
ROLE_MIRROR = "soft",                    -- parity in spirit with WoT 2.0 ("vehicle roles are taken into account")
PLATOON = { MAX_SIZE = 3, SAME_TIER = true, MAX_PLATOON_COUNT_DIFF = 1, MAX_SPG_PER_PLATOON = 1 },
```

- **LT 3 / TD 5:** parity with WoT 2.0, confirmed by WG's 2.0 overview. **Wheeled 1:** parity with the *reported* 2.0
  value, unverified (corrected by fact-check).
- **Role mirroring (soft)** (corrected by fact-check; R3 previously had no role term). WoT 2.0 mirrors roles within a
  class, for example assault TD against assault TD. `roleMirrorError` counts, per class, the vehicles whose role has
  no counterpart on the other team. It is a score penalty (R2), never a hard block, so it cannot lengthen queues.
  Bots fill slots with the role that reduces the error.
- **`SAME_TIER = true` is OUR DESIGN CHOICE**, not confirmed parity: WoT's current platoon tier rule is unverified
  (§1.6). Same-tier platoons keep the template slots simple and avoid "failtoons".
- **SPG = 2** (OUR DESIGN CHOICE; WoT uses 3). It applies only if HULLDOWN ships an SPG class. SPG pressure feels
  worse on mobile, where repositioning is slower, and it hurts readability. Raise the limit only if the data says so.
- **Bots fill in the missing classes to complete the mirror.** For example, if team A has 2 human TDs and team B has 1,
  team B gets a bot TD.
- **Light-tank sub-roles:** if we adopt 2.4-style sub-roles, start with `LT = 3` and watch per-role win rates before
  adopting WoT's 2-LT cap.

### R4. Queue relaxation schedule (OUR DESIGN CHOICE)

Wait is measured on the **oldest** ticket in a candidate match. Roblox players expect fast starts, so every stage is
short.

| Wait (s) | `relax` | Bots allowed per battle | Class mirror | Region | Templates |
|---|---|---|---|---|---|
| 0–10 | 0.0 | 0 | exact | own bucket | all (scored) |
| 10–25 | 0.33 | ≤ 10 of 30 | exact | own + adjacent | all |
| 25–45 | 0.66 | ≤ 20 of 30 | ±1 | global | all |
| ≥ 45 | 1.0 | 30 − humans (minimum 1 human) | ±1 | global | all |

- From **15 s**, the UI offers **"Start now with bots"** for a solo player or one platoon. It immediately creates a
  1–3-human battle with the same template rules. This keeps the lowest-population hours playable.
- The leader runs the matchmaker every **2 s** (`MATCHMAKER_TICK_S = 2`).
- Ticket TTL is **120 s**, refreshed by a heartbeat every **10 s**.
- A teleport failure re-queues the ticket with its original `enqueuedAt`, so the player keeps their priority.

### R5. Map and mode selection

```lua
MAP_SELECTION = {
	RECENT_HISTORY = 5,          -- avoid maps any human played in their last 5 battles (soft penalty)
	RECENT_PENALTY = 0.25,       -- weight multiplier per recent occurrence
	BLACKLIST_SLOTS = 1,         -- reported parity (WoT: 1, Premium 2; unverified by fact-check)
	BLACKLIST_SLOTS_PREMIUM = 2, -- reported parity; convenience only, not power
	BLACKLIST_MIN_POOL = 8,      -- OUR DESIGN: blacklist disabled until the battle-level pool has >= 8 maps
	BLACKLIST_COOLDOWN_S = 0,    -- OUR DESIGN: no cooldown at launch (small pool); revisit
},
MODE_WEIGHTS = { Standard = 0.70, Encounter = 0.20, Assault = 0.10 }, -- OUR DESIGN; WoT's weights are not published
MODE_MIN_TIER = { Encounter = 4, Assault = 4 },                      -- OUR DESIGN, in WoT's spirit
```

- The map is picked **after** the teams are formed (parity). Mode and map are then chosen together from the pairs that
  are valid for the battle level.
- **Opt-out toggles** for Encounter and Assault (parity) reduce a mode's weight for the battle by the share of humans
  who opted out. They **never split the queue**: this is OUR DESIGN CHOICE, because population matters more than strict
  preferences.
- **Blacklists** are hard exclusions when the remaining candidate set has 3 or more maps. Otherwise the map that hits
  the fewest blacklists is used.

### R6. Regions and Roblox server specifics

- **The pool key is `(mode, regionBucket, MatchmakingType)`.**
  - `regionBucket` comes from `GetCountryRegionForPlayerAsync` mapped to NA / SA / EU / APAC / OCE.
  - Relax to adjacent buckets at 10 s and to global at 25 s (R4).
  - **`MatchmakingType` is never relaxed**: the platform forbids mixing.
- **Manifest:** `match:<privateServerId>` with TTL equal to the battle length plus 10 min, holding
  `status ∈ {Forming, Loading, Live, Finished}`.
  - The battle server refuses joins and bounces players to the Hub when `status == Finished` or the manifest is
    missing. This is needed because access codes never expire.
- **Teleport groups:** one `TeleportAsync` per Hub server per match (≤ 50, which always holds for ≤ 30 humans).
  `SafeTeleport`-style retries with 5 attempts and backoff.
- **`active:<userId>`** stores `{privateServerId, accessCode, team, vehicleId}`, with a TTL equal to the remaining
  battle time. The Hub uses it to show **"Return to battle"** and to lock the vehicle (parity).

### R7. Battle rules configuration

```lua
-- Shared/Config/Battle.luau (proposed defaults)
TIMER_S = { Standard = 720, Encounter = 720, Assault = 480 }, -- OUR DESIGN: WoT is 900/900/600 (×0.8)
LOAD_TIMEOUT_S = 30,         -- OUR DESIGN: countdown starts when all humans load, or at 30 s
COUNTDOWN_S = 20,            -- OUR DESIGN: WoT 30 s (Medium); shorter for Roblox session pacing
CAPTURE = {
	POINTS_TO_WIN = 100,     -- parity
	RADIUS_M = 50,           -- OUR DESIGN (WoT radius not retrieved); 150 studs
	MAX_COUNTED = 3,         -- parity
	RATE_PER_VEHICLE = { Standard = 1.0, Assault = 1.0, Encounter = 0.5 }, -- pts/s; Standard ≈ WoT recollection
	CONTESTED_BLOCKS = { Standard = false, Assault = false, Encounter = true }, -- parity
	RESET_ON_HP_DAMAGE = true,     -- parity
	RESET_ON_MODULE_CRIT = true,   -- OUR DESIGN (WoT unverified): tracking a capper also resets it
	RESET_ON_STUN = false,         -- OUR DESIGN
	LEAVE_GRACE_S = 1.0,           -- OUR DESIGN: absorbs boundary jitter; then that vehicle's points are lost
},
TIMEOUT_RESULT = { Standard = "Draw", Encounter = "Draw", Assault = "DefenderWin" }, -- parity
SIMULTANEOUS_RESULT = "Draw",      -- both bases captured on the same tick, or both teams wiped out
FRIENDLY_FIRE = { SHELL = 0, SPLASH = 0, RAM = 0, SHELLS_BLOCKED_BY_ALLIES = true }, -- OUR DESIGN
```

- **Capture math:**
  - `teamProgress = min(100, Σ_{v in circle, not reset} points_v)`.
  - Each tick: `points_v += rate · dt · min(1, 3 / nCappers)`. The total speed is therefore capped at 3 vehicles while
    every capper still earns points.
  - Standard capture times: 100 s alone, 50 s with two, **33.3 s** with three or more.
  - Encounter capture times: 200 s alone, **66.7 s** with three.
- **Why the timers are shorter:**
  - WoT's 15 min cap rarely binds: most battles end well before it (Low confidence on WoT's average; doc 05 assumes
    about 6 min).
  - On Roblox the worst case matters more: mobile sessions and younger players.
  - With bots pushing the action, stalemates are rarer.
  - Watch the draw rate. If timeouts exceed **5%** of battles, raise the timer to 15 min or the Standard capture rate to
    1.25.
- **Friendly fire is off** (OUR DESIGN CHOICE; WoT has team damage).
  - Allies still **block shells**: the shell is consumed and does 0 damage. Lines of fire still matter.
  - Griefing on Roblox is cheap and moderation tools are thin. With bots and fewer humans, one griefer ruins a
    larger share of a battle.
  - Blue-status bookkeeping goes away.

### R8. Map specification

```lua
-- Content/Maps/<MapId>.luau (key fields; validated by ContentRegistry)
size_m = 1000,               -- standard; 800 for city/compact and for the Tier I–III pool
boundaryInset_m = 0,         -- red line at the playable edge
visualSkirt_m = 150,         -- non-playable scenery beyond the boundary (horizon)
grid = { rows = "ABCDEFGHJK", cols = "1234567890" }, -- parity; cell = size_m / 10 (100 m = 300 studs)
tierRange = { 4, 11 },
modes = { "Standard", "Encounter", "Assault" },
lanes = { { id, kind = "Heavy" | "Flex" | "Open", polyline, width_m } }, -- exactly 3 primary lanes
zones = { spawns = { A = {slots...}, B = {slots...} }, bases = { Standard = {...}, Encounter = {...}, Assault = {...} },
          spgRear = {...} },
water = { { volume, depth_m } },
variants = { { id, lighting, weather = "cosmetic" } },  -- cosmetic only (parity)
```

- **Size:** **1000 × 1000 m = 3000 × 3000 studs** (parity).
  - A ±1500-stud playable area is far inside Roblox's float-precision comfort zone.
  - Max spotting (445 m = 1335 studs) and draw range (564 m = 1692 studs) from doc 02 then behave as in WoT.
  - City or compact maps and the Tier I–III pool use **800 × 800 m**.
  - If mobile performance forces a smaller map, scale spotting with `map.spottingScale` as doc 02 describes.
- **Lanes:** **3 primary lanes**.

  | Lane | Width | Cover | Sightline target |
  |---|---|---|---|
  | Heavy | 200–300 m | ≥ 60% of the lane has hard cover within 30 m | ≤ 150 m |
  | Flex/ridge | 200–350 m | ≥ 3 hull-down positions per side | 100–300 m |
  | Open | 300–400 m | foliage islands, few hard covers | 200–445 m |

  - Plus a rear SPG/TD band 100–150 m deep behind each spawn.
  - **At least 2 lane-to-lane transitions per map half**, so a won flank can rotate.
- **Spawns:**
  - 15 slots per team, of which ≥ 3 are at the rear for SPG/TD.
  - The two spawn centroids are **≥ 0.7 × `size_m`** apart: 700 m on 1000 m maps, 560 m on 800 m maps (corrected by
    fact-check). A flat 700 m was infeasible on 800 m maps laid out side to side: with the 100–150 m rear band behind
    each spawn, at most 800 − 2 × 100 = 600 m of separation is left. The proportional rule also matches §4.9 (WoT spawns
    sit about ½–¾ of the side or diagonal apart).
  - **No line of sight** from any spawn slot to any enemy spawn slot. A validator raycasts on the `HeightmapWorld`.
  - **First-contact time ≥ 40 s** for the fastest class driving the shortest route.
  - No invulnerability (parity): protection comes from geometry.
- **Bases:**
  - Standard bases sit 100–200 m in front of their spawn.
  - The Encounter base is equidistant from both spawns, with path-length difference ≤ 5%.
  - The Assault base is the defenders' Standard base.
  - Every base circle is fully ≥ 60 m inside the boundary.
- **Fairness metrics** (OUR DESIGN CHOICE, in the spirit of WG's spawn-win-rate practice):
  - Path-length asymmetry per lane between the two spawns is **≤ 10%** (static validator).
  - Live **per-spawn win rate within 47–53%** over at least 1000 battles per battle level. Outside that range the map
    is flagged for a rework.
- **Relief:**
  - Total relief **≤ 80 m** on standard maps.
  - Any slope too steep to drive must be marked impassable (movement config).
  - Avoid Dragon-Ridge-style verticality that makes gun depression decisive everywhere.
- **Water:**
  - `depth_m ≤ 1.0` is fordable at a speed penalty.
  - Deeper water drowns a vehicle when the water line is above its turret roof for **10 s** (OUR DESIGN; WoT values
    unverified), with a HUD warning.
  - Drowned vehicles count as destroyed, with no credit to the enemy.
- **Destructibles:** three strength classes (OUR DESIGN CHOICE):

  | Class | Examples | Breaks when |
  |---|---|---|
  | Light | fences, small trees, poles | any contact |
  | Medium | sheds, garden walls, large trees | contact at ≥ 15 t × 10 km/h impulse, or one HE hit |
  | Heavy | houses | partial, on ramming by ≥ 40 t, or after 2 HE hits |

  - Large buildings, rocks and bridges are permanent.
  - Destroyed pieces are removed from the server `MapSolid` LOS set (doc 02).
- **No gameplay weather (parity) and no map events in Random Battles at launch (OUR DESIGN CHOICE; deviation)**
  (corrected by fact-check: this was labelled parity, but WoT 2.x has per-map "random events", §4.10). Keep the
  `variants` hook and add an optional `randomEvents = { { id, chance, layoutDelta } }` field, so per-battle layout
  changes in the WoT 2.0 style (a passage opens, a wreck adds cover) can be added later. Every event state must pass
  the same spawn, LOS and path-asymmetry validators as the base layout.

### R9. Battle lifecycle

1. **Queue → match formed:** the Hub shows "Battle found" and teleports with `SetTeleportGui`. That GUI carries the map
   name and art, the mode and the objective sentence.
2. **Battle place loading:** the custom loading screen in `ReplicatedFirst` shows **both rosters** (name, vehicle, class
   icon, tier, platoon colour, bot icon), map, mode, objective and one tip. This is parity with WoT; the tip pool is
   ours.
3. **Load gate:** the countdown (20 s) starts when every human has loaded, or after `LOAD_TIMEOUT_S = 30`. Humans who
   have not arrived by then have their vehicle **bot-controlled until they arrive** (OUR DESIGN CHOICE).
4. **Battle:** timers per R7.
5. **Disconnect** (OUR DESIGN CHOICE: deviation):
   - After **5 s** without a connection, a bot takes over the vehicle.
   - The player can **reconnect until the battle ends**: Hub → "Return to battle" → `active:<userId>`.
   - Control returns at the next tick.
   - Rewards count only the human-controlled share of the player's actions.
   - **Why:** mobile disconnects are common on Roblox, and an idle tank is a free kill that hurts 14 teammates. WoT
     leaves the tank idle.
6. **Destroyed:** the player can spectate allies or return to the Hub. The vehicle stays **locked until the battle
   ends**, with crew too if crews are per vehicle (parity). The player can battle in another vehicle.
7. **Leaving alive:** a confirmation dialog appears, then a bot takes over. The player forfeits the win bonus and gets
   an AFK strike.
8. **AFK** (OUR DESIGN CHOICE):
   - No throttle, turret or fire input for **60 s** → on-screen warning.
   - **90 s** → bot takeover plus an AFK strike. This matches doc 05's 90 s XP clamp.
   - The strike ladder within a 24 h window:
     - strike 1: no rewards for that battle;
     - strike 2: 10 min queue lock;
     - strike 3: 60 min queue lock.
   - Strikes decay after 24 h.
9. **End:** a 6 s result banner, then teleport to the Hub. **Rewards are applied idempotently by battle id**
   (architecture §7), including for players who left early. Results use the 2.0-style full screen (doc 06).

### R10. Communication

- **Command wheel: 12 presets, no punctuation**, to comply with Roblox's preset guidelines:
  1. Attack
  2. Defend base
  3. Need help
  4. Affirmative
  5. Negative
  6. Reloading
  7. Thanks
  8. Hold position
  9. Follow me
  10. Enemy spotted here
  11. Moving here
  12. Focus fire

  Opened with a key on PC, LB-hold on a gamepad (doc 06) or a HUD button on mobile.
- **Context ping:**
  - **T** (PC) on the thing under the reticle:
    - enemy → Focus fire;
    - ally → Need help;
    - terrain → Attention here;
    - own base → Defend base;
    - enemy base → Attack.
  - Minimap left-click means attention; right-click means moving here. This copies the 1.10 interaction pattern.
- **Rate limits:**
  - Any preset that writes a chat line: **1 per 10 s per player** (Roblox requirement). It is labelled "system preset"
    and its text is filtered.
  - Map and minimap markers without a chat line: **3 per 5 s** (doc 06). **Flag this for Roblox policy review.** If
    review says markers count as presets, use 1 per 10 s for everything.
- **Replies:** pressing Affirmative or Negative within 10 s of a teammate's command attaches the reply to that marker,
  with a counter and names (parity with 1.10). Replies also count against the 10 s preset limit.
  **Flag for Roblox policy review** (added by fact-check): the preset guidelines forbid "Question/answer structures
  ('Why?', 'Because')". A command followed by Affirmative/Negative is not a question, and it is not free text, but if
  review reads a reply chain as a Q/A structure, keep the replies as **marker-only acknowledgements** (a tick and a
  counter on the marker) and do not write them as chat lines.
- **Chat:**
  - `TextChatService` with the **`RBXTeam`** channel as the in-battle default.
  - All-chat is **off by default** (parity).
  - Platform age-based chat rules apply automatically.
- **Bots** respond to "Attack", "Defend base", "Follow me" and "Focus fire" from humans on their team. This is OUR
  DESIGN CHOICE: it makes comms useful in bot-heavy battles and teaches new players the wheel.

### R11. Modes roadmap (OUR DESIGN CHOICE, following WoT's "one permanent queue" lesson)

| Phase | Modes | Notes |
|---|---|---|
| Launch | **Random** (Standard / Encounter / Assault), **Bootcamp** (3 scripted battles vs bots), **Practice** (solo map explorer and shooting range; a "Topography" equivalent), **Training Room** (private: reserved server plus join code, up to 15 v 15, bots optional) | One public PvP queue |
| CCU > ~500 sustained | **7 v 7 competitive** (Onslaught-like) at one tier band, seasonal | Only when it will not starve Random |
| Events | PvE wave modes with bots; limited-time map variants | Uses the `variants` and bot systems |
| Later | 30 v 30 on 3 × 3 km (Frontline-like) | 9000 × 9000 studs is still fine for precision. Needs streaming and LOD work |

### R12. Summary of deliberate deviations

| WoT | HULLDOWN | Reason |
|---|---|---|
| Bots only fill gaps in some Random Battles (corrected by fact-check; was "No bots in Random") | Labelled bot fill at every tier, a ≤ 45 s guaranteed start and "start now with bots" | Roblox population; queue times |
| Idle tank on disconnect or AFK | Bot takeover plus reconnect | Mobile disconnects; team fairness |
| Team damage plus blue penalties | 0 friendly damage, but allies block shells | Griefing; moderation cost; keeps lines-of-fire tactics |
| 15 / 15 / 10 min timers, 30 s countdown | 12 / 12 / 8 min, 20 s countdown after a load gate | Roblox session pacing |
| Templates prefer 3/5/7 (pre-2.0) | Scored; prefer ±1; humans placed in upper slots | Bots make fill cheap; avoids "always bottom tier" |
| Preferential-MM premiums | None | Fairness; no pay-for-MM |
| ≤ 3 SPG | ≤ 2 SPG (if SPGs ship) | Mobile readability and frustration |
| Free-form quick commands | 12 presets, no punctuation, 1 per 10 s chat lines | Roblox preset-system rules |
| Map blacklist always on | Enabled once a battle-level pool has ≥ 8 maps | Small launch map pool |
| Per-map "random events" (2.x) | None at launch; `randomEvents` hook (R8) (added by fact-check) | Smaller map pool; every layout state must be validated |

Role mirroring (R3) is **not** a deviation: it follows WoT 2.0 as a soft score term (added by fact-check).

---

## Open questions / uncertain items

1. **Capture rates.** WoT's exact per-vehicle rate for Standard (believed ~1 pt/s) and Encounter, the capture circle
   radius, whether module-only crits and stun reset capture, and the grace or decay on leaving the circle. All need a
   check against the WG wiki or Battle Mechanics pages.
2. **WoT 2.0 / 2.4 MM specifics.** Partly resolved by the fact-check: the ±1 direction, LT 3, TD 5 and role mirroring
   are confirmed by WG's 2.0 overview. Still open: wheeled 1, SPG 3 under 2.0, the 2.4 LT 2 cap, whether 2.4 balances
   light-tank sub-roles across teams, and how strict role mirroring is. Confirm from the 2.0 and 2.4 release notes.
3. **Platoon tier rule.** Same tier required, or a ±1 tolerance? Is there a per-platoon SPG limit? (WG-wiki tank pages
   imply mixed-tier platoons were allowed at some point.)
4. **Bots in WG Random Battles.** Wikipedia says bots "may be used to fill gaps"; at which tiers, for which accounts
   and after what wait? Also, do WG realms have a "Topography" mode or only Lesta's Mir Tankov?
5. **Pre-battle countdown.** It is 30 s in WoT (Medium). How does 2.4's Spotlight change total pre-battle time?
6. **Encounter and Assault in 2025–2026.** Are they still opt-out toggles? At which tiers? Are Grand Battles still live?
7. **Status of Steel Hunter, Frontline and Onslaught in 2026** (seasonal calendar).
8. **Map blacklist cooldown** and whether WoT Plus or 2.0 changed the slot counts.
9. **Drowning and overturn rules** (depth trigger and delay) and fall-damage formula. Coordinate with the movement and
   combat research.
10. **Roblox policy.** Do icon-only map markers count as "presets" under the preset guidelines (10 s limit)? Ask during
    game review or devforum. The devforum is blocked from this sandbox.
11. **Roblox reserved-server placement.** Which data centre hosts a reserved server for a mixed-region group? The local
    docs do not say. This affects whether cross-region relaxation should happen at 25 s or later. Measure ping in live
    tests.
12. **Cross-doc consistency.** Doc 05's 10 v 10 Battle Heroes thresholds and 6 min battle assumption against the
    15 v 15 / 12 min recommendation here. Decide in the architecture doc.
13. **Random events on maps** (added by fact-check). Which maps have them, since which version, and how often each is
    rolled per battle?

---

## Verification log

Fact-check pass of 2026-10-05.

- **Totals:** 17 claims checked. **8 Confirmed** (rows 2 and 8 each have an unverified sub-claim), **5 Corrected**
  (rows 1, 7, 9, 10 and 11) and **4 Unverified** (rows 6, 13, 14 and 15). The checker also fixed 6 internal
  contradictions in the Implementation recommendations and flagged 1 policy risk, listed in the second table.
- **Method:** each claim was assumed wrong until a source independent of this doc and its siblings confirmed it.
  Web search was exhausted. WoT/Wargaming, Wikipedia, fandom, TAP, Steam, mmos.com and MassivelyOP were blocked, so
  every WoT check used GitHub-hosted material (code search, then raw fetches).
- **Excluded evidence:** the `izeberg/wot-src` client mirror came up in search. It was deliberately **not** used (the
  team's no-datamined-data rule). The same goes for community tools whose map data is read from client files.
- **Weak evidence is labelled.** Video captions are machine-generated summaries with quoted narration ("vehicle
  rolls" is a transcription of "vehicle roles"). The Wikipedia text is a mirrored extract. The WG-wiki tank pages are
  undated dumps.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Random Battles are always 15 v 15, with no bots; low population never adds bots | **Corrected** (15 v 15 maximum confirmed; "no bots" wrong) | Wikipedia "World of Tanks", Gameplay section, retrieved 2026-07-04: "A random battle includes up to 15v15 players; bots may be used to fill gaps." Mirrored at [Nice9Tian/stable-query-latent](https://github.com/Nice9Tian/stable-query-latent/blob/main/VICReg_review/wiki_descriptions/1407200_World%20of%20Tanks.txt) |
| 2 | Template MM 3/5/7, 5/10, 15 (mirrored per team), introduced in 9.18 (May 2017) | **Confirmed** for the templates and 9.18; the month is **Unverified** | Reddit post (undated, from the new-MM discussion) in a public corpus: "MM is now in three forced formats with tiering. You will either have 3/5/7 ; 5/10 or pure tiered battle" ([smdp2000/Estimating-Levels-of-Depression](https://github.com/smdp2000/Estimating-Levels-of-Depression) `csv_data_2020/subject3135.csv`); saved search snippet "Matchmaker tank distribution – Update 9.18 … Pattern-based matchmaker" ([WithinAmnesia/Art](https://github.com/WithinAmnesia/Art)); a Random-MM reimplementation uses "15-player 3/5/7, 5/10, or one-tier slots" and cites WG's 9.18 release announcement ([pengw0048/wot-offline-battles](https://github.com/pengw0048/wot-offline-battles/blob/main/docs/testing/094-match-spg-contact-radio.md)) |
| 3 | WoT 2.0 released 3 Sep 2025 | **Confirmed** | IGN YouTube entry, 19 Aug 2025: "World of Tanks Update 2.0 is launching on September 3 for PC" ([rumca-js/RSS-Link-Database-2025](https://github.com/rumca-js/RSS-Link-Database-2025) `2025/08/2025-08-19/…UCKy1dAqELo0zrOtPkf0eTMw_entries.json`); Mailand video description: "Update 2.0 am 03. September" ([gpsyrou/tube-virality](https://github.com/gpsyrou/tube-virality) `assets/meta/trending/trending_videos_DE_20250821.json`) |
| 4 | 2.0 MM moved toward ±1 ("mostly ±1, some ±2") | **Confirmed** (direction); the exact mix is **Unverified** | WG "Update 2.0: Overview" narration, minutes 8–9: core "almost completely rewritten"; "Teams are more often built with a … one tier difference" (captions cut mid-sentence). [Heinz217/TraceAV-Bench-Submission](https://github.com/Heinz217/TraceAV-Bench-Submission) `intermediate/step2_audio_visual_fusion/per_minute_fusion_captions/video129.json` |
| 5 | 2.0 caps per team: LT 3, TD 5 | **Confirmed**; confidence raised to High | Same narration: "teams are limited to three light tanks and five tank destroyers each" |
| 6 | 2.0 caps per team: wheeled 1, SPG 3 | **Unverified** (wheeled lowered to Medium-Low; SPG kept at Medium) | Not in the official narration. The reimplementation above uses "a feasible 0..3 SPG count", which supports ≤ 3 SPG historically. Doc 05 is the only source for wheeled 1 and is not independent |
| 7 | The Random MM does not balance vehicle roles (except 2.4 LTs) | **Corrected** | Same narration: "vehicle roles are taken into account"; "the matchmaker will put a Badger against a T110E3, not against a Grill 15" |
| 8 | Update 2.4 "Overdrive" in Sep 2026; 2.4 caps light tanks at 2 per team | **Confirmed** for the date; the LT 2 cap is **Unverified** | Mod catalog entries of 2026-09-03: "added support for World of Tanks 2.4.0.0" and "Update 2.4.0.0"; 2026-09-18: "UPDATE 2.4.0b … Compatible Wot 2.4.0.1" ([orik007/stars-mod-installer-hub](https://github.com/orik007/stars-mod-installer-hub) `history/v2026.09.007/catalog-changelog.json`). No source independent of doc 05 for the LT cap |
| 9 | Preferential MM is capped at ±1 and is "mostly Tier VIII" | **Corrected** (±1 confirmed; "mostly Tier VIII" wrong) | WG-wiki tank-page dumps ([aa-tolmachev/django-qa](https://github.com/aa-tolmachev/django-qa) `homepage/data/all tanks/`): E 25 (Tier VII) "Preferential matchmaking; never sees tier 9 battles"; M3 Light (LL) (Tier III) "never sees tier 5 tanks"; SU-85I (Tier V) "never sees tier 7 tanks" |
| 10 | Random Battle maps are static, with no dynamic gameplay events (High) | **Corrected** | WG 2.0 overview narration, minutes 15–16: "Update 2.0 brings random events to four more maps"; The Yards bunker passage; Ensk "periodically passing trains that create dynamic cover"; Redshire airship wreck; southern Paris bridge debris (same captions file) |
| 11 | Platoons are up to 3 players, and current Random Battles require same-tier platoons | **Confirmed** for size; **Corrected** (downgraded) for the same-tier rule | Wikipedia (row 1): "platoons, groups of two or three players who are put into the same team". Type 95 page in the WG-wiki dump: do not platoon "with friends who aren't using preferential matchmaking tanks or you will be facing tier 6", which shows mixed-tier platoons were allowed when it was written. Same-tier lowered to Low-Medium |
| 12 | Win by destroying all enemies or capturing the base; HP damage resets capture | **Confirmed** | Wikipedia (row 1): won "by destroying all vehicles on the opposing team or capturing the opposing team's base by staying in it for long enough without being damaged by another tank" |
| 13 | Timers 15:00 Standard/Encounter and 10:00 Assault; timeout = draw / defenders win; 30 s countdown | **Unverified**; the timers were lowered from High to Medium-High | No reachable source. Only an essay page (bedwards/hex-index) mentions "fifteen minutes", which is not counted as evidence |
| 14 | Capture: 100 points, 3 vehicles counted, ~1 pt/s per vehicle, Encounter blocked when contested | **Unverified**; 100 points and 3 vehicles lowered from High to Medium-High | No reachable independent source. The 2.0 narration does not cover capture. Rates stay Low–Medium |
| 15 | Map blacklist: 1 slot for all, 2 with WoT Premium (since 1.5); minimap grid A–K without I, 1–0 | **Unverified**; both were lowered from Medium-High to Medium | Doc 05 records the "second map exclusion" for Premium, but it is a sibling, not an independent source. GitHub code searches for both found nothing usable |
| 16 | Roblox teleport and server facts: ≤ 50 players per `TeleportAsync`; reserved access codes valid indefinitely; `MatchmakingType` (Default / XboxOnly / PlayStationOnly) cannot share or teleport to one server; `SafeTeleport` sample with 5 attempts; reserved servers excluded from built-in matchmaking; latency score `1 − min(100, Δping)/100`; MemoryStore 64 KB + 1.2 KB × users, 1000 + 120 × CCU RU/min, ~30k RU/min per partition, 45-day default TTL; `RBXTeam` default channel | **Confirmed** | [Roblox/creator-docs](https://github.com/Roblox/creator-docs) `content/en-us/`: `reference/engine/classes/TeleportService.yaml` ("No more than 50 players…", "Access codes remain valid indefinitely"); `reference/engine/classes/DataModel.yaml` and `reference/engine/enums/MatchmakingType.yaml`; `projects/teleport.md` (`ATTEMPT_LIMIT = 5`); `matchmaking/index.md` (filters out "private, reserved" servers); `matchmaking/attributes-and-signals.md` (latency formula); `cloud-services/memory-stores/index.md`; `chat/chat-window.md` |
| 17 | Roblox preset guidelines: ≤ 12 presets, 10 s per send, no terminal punctuation, "system preset" label, `FilterStringAsync`, Q/A structures and encodings forbidden | **Confirmed** | `content/en-us/chat/preset-system-guidelines.md` in [Roblox/creator-docs](https://github.com/Roblox/creator-docs) ("Limit the number of presets displayed to 12 or less", "Add a rate-limit (10 seconds per send)", "Question/answer structures ('Why?', 'Because')") |

**Implementation recommendations: internal consistency check**

| Item | Verdict | Fix |
|---|---|---|
| R1 / R12 "Bot fill is the main deviation; WoT: No bots in Random" | **Corrected** | WoT bots can fill gaps (row 1). The deviation is now stated as one of **scale** (every tier, the normal way to fill), and the R12 row was reworded. |
| R2 score `−3·[template = T3]` beside an unused `TEMPLATE_WEIGHT` config | **Corrected** | The term is now `−7.5·(1 − TEMPLATE_WEIGHT[t])`, which gives the same −3 for T3 with the defaults but leaves only one knob. |
| R3 had no role term, while the findings now show WoT 2.0 mirrors roles | **Corrected** | Added `ROLE_MIRROR = "soft"` and a `roleMirrorError` score term (penalty only, never a hard block). Bots fill slots with the role that reduces it. |
| R3 "LT 3 / wheeled 1 / TD 5: parity" and `PLATOON.SAME_TIER = true` presented as parity | **Corrected** | LT 3 / TD 5 are confirmed parity. Wheeled 1 is reported parity (unverified). Same-tier platoons are now labelled OUR DESIGN CHOICE. The blacklist slot comments in R5 now say "reported parity (unverified)". |
| R8 "spawn centroids ≥ 700 m apart" for all maps, including 800 m maps with a 100–150 m rear band | **Corrected** | Infeasible side to side on 800 m maps (800 − 2 × 100 = 600 m < 700 m). Now `≥ 0.7 × size_m` (560 m on 800 m maps), consistent with §4.9. Summary item 19 was updated to match. |
| R8 / R12 "No map events in Random Battles (parity)" | **Corrected** | WoT 2.x has per-map random events (row 10). It is now OUR DESIGN CHOICE for launch, with a validated `randomEvents` hook and a new R12 row. |
| R10 Affirmative/Negative replies vs. the preset rule against Q/A structures | **Flagged** | Added a policy-review note, with a fallback to marker-only acknowledgements. |
| R4 / R6 relaxation times, R7 capture arithmetic (100 / 50 / 33.3 s Standard; 200 / 66.7 s Encounter), R7 timers 720 / 480 s = 0.8 × 900 / 600, R1 450 directed spotting pairs (2 × 15 × 15) | **Confirmed** | Re-computed. R4 and R6 agree on adjacent buckets at 10 s and global at 25 s. |
