# 06 — UI/UX Patterns and Audio Design: World of Tanks (2025–2026) → HULLDOWN on Roblox

Researcher brief for the HULLDOWN studio team. Written 2026-10-05.
Scope: (1) how World of Tanks (WoT, PC, Wargaming) currently presents its garage, meta-screens, battle HUD, loading/results flow and accessibility options; (2) how WoT's audio works and how it changed over time; (3) general UI/audio best practice; (4) what Roblox's engine (docs snapshot dated 2026-10-02) offers to build it; (5) concrete, numeric decisions for HULLDOWN.

HULLDOWN is an original game. Nothing here means we should copy WoT art, icons, names, voice lines, music or layouts pixel-for-pixel. We copy **information design patterns** (what the player needs to know, and when) and build our own presentation.

> **Evidence caveat (read first).** The sandbox egress proxy blocked every WoT/Wargaming domain, Wikipedia, PCGamingWiki, The Armored Patrol, learn.microsoft.com (Xbox Accessibility Guidelines), gameaccessibilityguidelines.com and audiokinetic.com. The web-search budget for the session ran out partway through. WoT facts below therefore come from **search-engine result summaries of official Wargaming pages and reputable fan sites**, not from full page reads. Each item has a confidence rating. Roblox facts come from the **local clone of the official Roblox creator-docs** (commit `9f840b17`, 2026-10-02), which is authoritative. Industry best-practice items marked "domain knowledge" were not re-verified online in this session.

---

## Summary

1. **WoT 2.0 (3 Sep 2025) rebuilt the garage.** The main menu moved from a horizontal top bar to a **vertical menu on the left**. All vehicle servicing (modules/equipment/ammo/consumables) now sits **in one strip above an expandable carousel**. Daily missions and events sit on the right, and vehicle name and XP sit at top-centre. A universal **Back button** is top-left, and the Game Menu moved to the **bottom-right**. Pressing **Space** opens a full-screen "My Vehicles" grid. Filters absorbed the old side buttons and gained **Playlists** (user, editable and importable vehicle lists). (High)
2. **WoT 2.0 added a first-party "About Vehicle" screen with an Armor Inspector.** Hovering shows nominal thickness, impact angle and effective thickness (including spaced armour), with colour-coded plates. Update 2.2 (2026) added a choice of **attacker vehicle, gun and shell** plus a **penetration-chance tooltip**. (High)
3. **WoT 2.0 post-battle results became full-screen.** The player's own 3D tank appears over the battle map. Tabs are General / Team Result / Financial Report. The score table is an overlay toggled with **Space**, and **every tab has a "next battle / ready" button**. (High)
4. **The battle HUD is mature and changes slowly.** Its key reference points:
   - Penetration indicator colours: red = predicted not to penetrate (effective armour ≥ 112.5 % of penetration, or a ricochet is predicted), yellow = effective armour within **±12.5 %** of penetration (half of the ±25 % penetration roll), green = effective armour ≤ 87.5 % of penetration. It **does** account for impact angle, normalisation, ricochet and spaced armour. (corrected by fact-check; Medium-High, from the decompiled 2.4 client, see item 13)
   - Team total-HP counter added in **1.12** (2021). (High)
   - Minimap view-range, max-spotting and draw-range circles added in **9.14**, and last-spotted markers in **9.5** (default "Always" since 9.15). (High)
   - Hit-direction indicators in three widths: **1–10 % / 11–30 % / 30 %+ of max HP** (9.17.1). (High; the thresholds were confirmed in the 2.4 client code by fact-check.)
   - Sixth-Sense lamp after **3 s** of being spotted, free for every commander since **1.18.1** (Oct 2022). (Medium-High)
5. **The WoT console edition (2025) shows a good pattern for an optional team-health bar.** It has four display modes: Full / Bar only / % only / None. (High, console source)
6. **WoT's colour-blind mode is a single Graphics checkbox.** It turns enemy red into purple and changes hit-marker colours. WoT's default ally colour is green, so it needs that mode. **HULLDOWN should default to ally-blue / enemy-red.** Our simulation gives a CIELAB ΔE of 93 / 68 / 129 between ally and enemy under deutan / protan / tritan vision, so no mode switch is needed for team identity.
7. **WoT's green/amber/red penetration palette fails for colour-blind players.** The smallest ΔE is about 20 under protan simulation. HULLDOWN must **add shape coding (solid / dashed / crossed reticle)** and offer a cyan / yellow / magenta preset, whose smallest ΔE is about 34.
8. **WoT audio history:**
   - FMOD was replaced by **Audiokinetic Wwise in 9.14 (10 Mar 2016)**. That update added 10–30 simultaneous distinct sources, proving-ground recordings, and gearbox, suspension and transmission sounds. (High)
   - **9.16** (late 2016) added five calibre classes in tier 8–10 battles, autoloader clip-state sounds, received-damage sound tiers (0–17 % / 18–35 % / 35 %+), per-module damage sounds and a "gun cannot fire" cue. (High)
   - A Night mode, Bass boost and Low-quality preset exist. (Medium)
9. **WoT music is dynamic, per-map and state-driven.** Update 1.0 (Mar 2018) added 60+ pieces by Andrius Klimka and Andrey Kulik. Each map has loading, start, mid-battle and culmination music, with **winning versus losing endgame variants** and **result-dependent closing themes**. (High)
10. **WoT 2.4 "Overdrive" (1–2 Sep 2026) brought the biggest VFX/SFX refresh since 2018.** It reworked close gunshots for all calibres, added **gunshot reflections for five environment types** (open terrain, near mountains, dense urban, tunnels, large hangars), redid the penetrating / non-penetrating / ricochet effects, and added a setting that reduces effects while aiming. (High for the content. The live dates are Medium, downgraded by fact-check because they rest on search summaries only.)
11. **On Roblox, the new modular Audio API is the right choice.** The docs explicitly say `Sound` / `SoundGroup` / `SoundEffect` are **"now discouraged"**. The new API adds:
    - arbitrary routing with `Wire`
    - a **sidechain compressor** for ducking
    - 12-type `AudioFilter`, including 6/12/24/48 dB low-pass
    - per-emitter custom distance curves (≤ 400 points) and angle curves
    - **multiple listeners via `AudioInteractionGroup`**, which give us real 3D sub-buses
    - built-in **acoustic simulation** (occlusion, diffraction, reverb) with per-material `AcousticAbsorption`
    - **sample-accurate `Play(atTime)` / `Stop(atTime)`** against `SoundService:GetMixerTime()`, for music and speed-of-sound delays
12. **Gaps in the Roblox Audio API.** There is no documented Doppler on `AudioEmitter`. Legacy `Sound` keeps `DopplerScale` and `DistanceFactor` = 3.33 studs/m, and the docs say `DistanceFactor` "does not impact" `AudioPlayer` or `AudioEmitter`. There is no documented voice or polyphony cap, so **we must write our own voice manager**. All audio processing is disabled on the server, so the audio graph is built **client-side**.
13. **Roblox upload limits:** `.mp3/.ogg/.wav/.flac`, < 20 MB, < 7 min, ≤ 48 kHz, mono/stereo/3.0/5.1. ID-verified accounts get **2,000 uploads per 30 days**, unverified accounts 100. The Open Cloud `assets/v1` endpoint supports a CI pipeline.
14. **Roblox UI platform facts:**
    - Gotham fonts are **removed** and map to Montserrat.
    - **Builder Sans / Builder Extended / Builder Mono** are first-party, licensed for Roblox UGC.
    - Engine-level **StyleSheet tokens, themes, and state and query selectors** exist: `GuiState` Idle/Hover/Press/NonInteractable, and `StyleQuery` MinSize/MaxSize/PreferredInput.
    - Built-in player preferences: `PreferredTextSize`, `PreferredTransparency`, `ReducedMotionEnabled`.
    - `ScreenInsets.CoreUISafeInsets` and `GuiService.TopbarInset` cover safe areas.
    - `ViewportDisplaySize` reports Small / Medium / Large.
15. **HULLDOWN UI decision:**
    - 1920×1080 reference, 8 px spacing unit, 12-column grid (130 px columns, 24 px gutters, 48 px margins).
    - Three layouts: Compact for phones, Regular for desktop and tablet, TV (Regular plus a 5 % safe margin and +20 % text). Compact is selected by viewport height, not by `DisplaySize.Small`, because Roblox classes most tablets as Small too (corrected by fact-check; see A1).
    - Fonts: Oswald for headings, Builder Sans for UI text, Builder Mono for all changing numbers.
    - Dark "gunmetal" surfaces with **amber** accent, **ally blue `#4DB8FF`**, **enemy red `#FF4F4F`** and platoon gold.
    - All text tokens reach at least 4.5:1 contrast on `bg`, `surface.1` and `surface.2`. To make this true, `state.destroyed` was lightened to `#87919A`, because the original `#7D8790` measured 4.09:1 on `surface.2` (corrected by fact-check).
16. **HULLDOWN audio decision:**
    - Buses: Master (glue compressor → limiter −1 dB) ← UI, Crew-VO, Critical-cues, Music, and four 3D listener-buses (Own-vehicle, Weapons, Vehicles, Ambience).
    - Sidechain ducking: VO ducks Music by 6 dB, Weapons duck Ambience and Music by 4–6 dB.
    - 2–3 distance layers per gunshot, chosen when the shot fires, with distance low-pass and speed-of-sound delay through `atTime`.
    - Hybrid occlusion: built-in acoustic simulation on the nearest emitters, raycast fallback elsewhere.
    - **32-voice budget** with per-category caps.
    - Crew callouts run as a priority queue of one voice, with captions.

---

## Detailed findings

### UI/UX — Garage and meta-game

#### 1. Garage / hangar layout (pre-2.0 vs 2.0+)

**Current behaviour (2.0 onward, Sep 2025):**
- The garage scene is redesigned as a **tank factory or assembly hall**. Vehicles appear at different stages of assembly and outfitting.
- The main menu **changed from a horizontal to a vertical layout and moved to the left side** of the screen.
- **All tank servicing sits in one place, above the tank carousel.** This covers modules, equipment, shells, consumables and other loadout items.
- **Daily missions and game events sit on the right.** The **tank's name and XP are at top-centre**.
- A **universal Back button** sits in the top-left of interface screens. Navigation also includes buttons that open event guides and tutorials.
- The **Game Menu button**, which leads to Settings and Combat Intelligence, moved from **top-left to bottom-right**.
- Visual refresh: new vehicle-type icons, currency icons, shell-type icons, vehicle-panel elements, tooltips and UI icons.

**Pre-2.0 layout, as background (1.x era):** a horizontal header with the Battle button and mode selector at top-centre, section tabs (Garage, Store, Missions, Tech Tree, Barracks and so on), and currencies plus Premium status on the right. Below that were the vehicle-parameters panel and the loadout bar, with the carousel along the bottom. This is domain knowledge, Medium confidence. We did not verify where 2.0 places the Battle button.

**History:**
- 9.17.1 (2017) added the garage "technical characteristics" display.
- 1.10 (Aug 2020) reworked the loadout UI with Equipment 2.0.
- 2.0 (3 Sep 2025) was the full garage and UI overhaul, called "the biggest update in the game's history". Its stated goal was "streamlined, functional and informative" menus and "quicker access to vehicle, crew, and upgrade information".

**Confidence:** High for the 2.0 items (several independent sources agree). Medium for the pre-2.0 description.

**Sources:**
- [WoT Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
- [TAP: Screenshots of the New Garage Interface in 2.0](https://thearmoredpatrol.com/2025/08/20/wot-express-screenshots-of-the-new-garage-interface-in-update-2-0/)
- [TAP: New Main Garage Screenshots](https://thearmoredpatrol.com/2025/08/21/wot-express-new-main-garage-screenshots-in-update-2-0/)
- [GamingTrend: 2.0 arrives](https://gamingtrend.com/news/world-of-tanks-2-0-update-arrives/)
- [MMOs.com: 2.0 overhaul](https://mmos.com/news/world-of-tanks-update-2-0-brings-first-ever-tier-xi-tanks-and-a-full-systems-overhaul)
- [Wargaming: 2.0 reveal](https://wargaming.com/en/news/world-of-tanks-2-0-update/)
- [WoT 2.0 Hub](https://worldoftanks.eu/en/news/updates/2-0-hub/)

#### 2. Carousel, filters, sorting, playlists, "My Vehicles"

**Current behaviour (2.0):**
- The carousel is **expandable**.
- The filter buttons that used to sit left of the vehicle panel are now **inside the vehicle filter**. The filter also **selects the current Playlist**, which is a grouping of vehicles.
- The filter button shows **"selected / total"** vehicle counts when a user-created or imported playlist is active.
- The panel expands to a **full-screen "My Vehicles" screen** through a button next to the filter or the **Space** key.
- On My Vehicles, a top-left dropdown switches, creates, edits or **imports** playlists.

**Pre-2.0:** an optional two-row carousel, plus filters for nation, type, tier, premium, elite, rented and favourites and a name search. This is domain knowledge, Medium confidence. A popular mod restored the "classic" carousel, which shows that layout changes create player friction: [GitHub: classic hangar carousel mod](https://github.com/ticzz/world-of-tanks-mod-hangar-carousel-classic).

**Confidence:** High for 2.0. Medium for the pre-2.0 details.

**Sources:**
- [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
- [WG support: Vehicles Filter in the Garage](https://wargaming.net/support/en/products/wot/article/15020/)

#### 3. Tech tree and module research

**Current behaviour:**
- One tree per nation. Tiers run in columns (I–X, plus **Tier XI since 2.0**), with nodes linked by research lines that carry XP costs.
- Premium and special vehicles sit outside the research lines.
- The About Vehicle screen (see item 5) opens from the Tech Tree and from a vehicle's context menu.
- A per-vehicle **module research** view shows gun, turret, engine, suspension and radio. Each module has an XP cost and a link to the next vehicles it unlocks.

Tier XI arrived with 2.0: 16 new vehicles and a new progression system. We do not have its exact UI layout.

**Confidence:** Medium. These are long-standing patterns from domain knowledge. The Tier XI fact is High.

**Sources:**
- [GameSpot: 2.0 adds Tier XI](https://www.gamespot.com/articles/world-of-tanks-2-0-adds-tier-xi-tanks-new-pve-campaign-and-more-next-month/1100-6534078/)
- [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)

#### 4. Vehicle comparison

**Current behaviour:** compare **up to 20 vehicles at a time**, from any nation, class, type or tier, including vehicles you do not own. Each can use a **standard, current or custom configuration**.

**History:**
- Added in **9.16** (2016). Before that it existed only as a mod.
- **9.17.1** (2017) added crew skills and perks, equipment, consumables, camouflage and ammo, and also put tech specs in the garage.

**Confidence:** High.

**Sources:**
- [9.16 comparison](https://worldoftanks.com/en/news/general-news/916-comparison/)
- [9.16 compare vehicles (ASIA)](https://worldoftanks.asia/en/news/general-news/update-916-compare-vehicles-garage/)
- [9.17.1 comparison and tech-spec display](https://worldoftanks.eu/en/news/general-news/917-1-vehicle-comparison/)

#### 5. About Vehicle screen and armour inspection

**Current behaviour:**
- 2.0 added an **About Vehicle** screen. It opens from the garage vehicle menu, the Tech Tree, or a vehicle's context menu, and gathers all key information "from multiple perspectives".
- Its **Armor tab** is the **Armor Inspector**. Hovering a plate shows **nominal thickness, impact angle and effective thickness** (angle and spaced armour included). Plates are **colour-coded by protection level and screen thickness**.
- **2.2** added the choice of **attacker vehicle, gun and shell type**, showing their effect on effective armour and **penetration chance** in the hover tooltip.

**Third-party precedent:** for years the community relied on external 3D armour viewers: web tools such as tanks.gg's armour viewer, the older "Tank Inspector" viewers, and the mobile app "Armor Inspector" ([Uptodown listing](https://armor-inspector.en.uptodown.com/android)). The first-party feature in 2.0 shows the demand was real. We did not check exact third-party feature lists (Medium-Low).

**Confidence:** High for the 2.0 and 2.2 features.

**Sources:**
- [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
- [TAP: Armor Model Viewer in 2.0](https://thearmoredpatrol.com/2025/08/22/wot-express-tank-armor-model-viewer-in-update-2-0/)
- [Update 2.2 Common Test](https://worldoftanks.eu/en/news/updates/2-2-CT/)

#### 6. Crew UI ("Crew 2.0" and what actually shipped)

**History:**
- "Crew 2.0" ran as a **Sandbox test in 2021** and **never shipped as tested**. Parts of it arrived in stages.
- **1.18.1 (Oct 2022):** Sixth Sense became a free **commander feature** for every commander.
- **1.20.1 (Apr 2023):** crew rework covering perks, XP penalties and the UI.
- **1.22.1:** a "massive crew interface rework" that made the screens "simpler, clearer, more user-friendly". Sixth Sense is shown on every commander's profile.
- **1.26 (Sep 2024):** perk-system revamp, **capped at 6 perks** for a crew member's main role.

**Confidence:** High for the dates and versions as summarised. Medium for the 1.22.1 date (late 2023, not verified).

**Sources:**
- [Crew 2.0 Sandbox FAQ](https://worldoftanks.com/en/news/updates/sandbox-2021-crew-2-0-faq/)
- [1.18.1 Sixth Sense commander feature](https://worldoftanks.eu/en/news/general-news/1-18-1-sixth-sense-perk/)
- [1.22.1 crew interface rework](https://worldoftanks.asia/en/news/general-news/crew-interface-rework/)

#### 7. Equipment / ammo / consumables loadout UI

**History:**
- **1.10 (Aug 2020), Equipment 2.0:** reworked equipment and consumables UI. It added four slot categories (Firepower, Survivability, Mobility, Scouting) with bonuses when matching equipment is mounted, on Tier VI–X vehicles.
- The configuration screen shows **shell prices and clearer ammo-type indicators**, with **drag-and-drop to reorder shells** in the ammo rack.
- New, simpler resupply windows for ammunition and consumables.

**2.0:** the loadout is reached from the single servicing strip above the carousel.

**Confidence:** High for 1.10 as summarised. We could not confirm the release version or UI of "setups" (switchable loadout presets) in this session.

**Sources:**
- [Update 1.10 list of changes](https://worldoftanks.com/en/content/docs/release_notes/update-1-10-list-of-changes/)
- [1.10 Equipment conversion](https://worldoftanks.asia/en/news/general-news/1-10-equipment-2-0-conversion/)

#### 8. Missions and Battle Pass UI

**Current behaviour (2.0):** **daily missions and events sit in a right-hand column of the garage**, always visible. Battle Pass and Personal Missions are their own sections. We have no verified layout details or progression numbers for them from this session.

**Confidence:** Medium for the placement. **Low** for anything else, so we state nothing numeric.

**Sources:** [TAP 2.0 garage screenshots](https://thearmoredpatrol.com/2025/08/20/wot-express-screenshots-of-the-new-garage-interface-in-update-2-0/)

### UI/UX — Battle HUD

#### 9. Damage panel (own vehicle status)

**Current behaviour:**
- Usually bottom-left: a vehicle silhouette with an HP number and bar, plus speed.
- **Module icons:** engine, ammo rack, fuel tanks, radio, gun, turret traverse, observation devices, left and right tracks.
- **Crew icons:** commander, gunner, driver, radio operator, loader(s).
- States: normal, **damaged (yellow)**, **destroyed or injured (red)**, plus a fire indicator.
- Repair, first-aid and extinguisher consumables act on these states.

**Confidence:** Medium-High (long-standing and well known; not re-verified in this session).

**Sources:** domain knowledge; [WoT console HUD guide](https://modernarmor.worldoftanks.com/en/cms/guides/game-hud/) describes the equivalent console HUD.

#### 10. Ammo panel, consumables bar, reload timer

**Current behaviour:**
- Shell slots with counts on keys **1–3**; consumable slots with cooldown overlays (traditionally keys **4–6**).
- A reload timer by the reticle; for autoloaders, a clip-state display.
- Since 9.16, audio backs up autoloader clip state: shells left, **last shell**, clip empty (see item 26).

**Confidence:** Medium-High (key bindings are domain knowledge).

**Sources:** [9.16 sound](https://worldoftanks.com/en/news/general-news/9-16-sound/), domain knowledge.

#### 11. Team panels ("ears"), score/frag counter, team HP, battle timer

**Current behaviour:**
- **Ally list top-left, enemy list top-right.** Each row shows vehicle-type icon, vehicle name, player name and kills. Destroyed vehicles are greyed. Several display widths are switchable.
- **Top-centre:** the frag score (kills per team) and, **since 1.12, a counter for each team's total hit points**.
- **Battle timer at top-right.** Random battles last 15 minutes (domain knowledge; [newcomer guide](https://worldoftanks.com/content/guide/newcomers-guide/getting_started/) confirms 15 min for Grand Battles).

**Console reference pattern (WoT Modern Armor, 1 Apr 2025):** a **Team Health** bar showing each team's remaining-HP **percentage** (100 % → 0 %) in the Team Composition Bar. It is opt-out, with modes **Full / Bar Only / % Only / None**. Console also added a **time-out tie-breaker**: most kills first, then the higher remaining-health %. This is console-only and **not** a PC rule.

**History:**
- Before 1.12, PC players used mods for team HP, such as "Battle Observer" and "Total score HP".
- 1.12 made it first-party.

**Confidence:** High for 1.12 and the console modes.

**Sources:**
- [Update 1.12 list of changes](https://worldoftanks.com/en/content/docs/release_notes/update-1-12-list-of-changes/)
- [Modern Armor update notes 1 Apr 2025](https://modernarmor.worldoftanks.com/en/cms/news/update-notes-april-1/)
- [Modern Armor HUD guide](https://modernarmor.worldoftanks.com/en/cms/guides/game-hud/)

#### 12. Minimap

**Current behaviour and history:**
- **Resizing:** `=` / `-` on PC grows and shrinks the minimap. We could not confirm the number of size steps.
- **9.5:** added the **view vector**, **SPG arc of fire**, **vehicle names** and **the last-spotted position of enemy vehicles**, all toggled in Settings → General.
- **9.14:** added circles for **current view range**, **maximum spotting range** and **vehicle draw (render) range**. Community guides describe the view-range circle (green), the fixed max-spotting circle (white) and the render-range limit (yellow).
- **9.15:** "show last-spotted location" became **"Always" by default**, overriding players who had chosen "Never".
- **Grid:** maps use a lettered and numbered square grid that players read out as callouts (for example "E5"). The exact labels (A–K without I, numbers 1–0) are domain knowledge, Medium confidence.
- **1.10 (2020) battle communication:** the **T** key places context-sensitive markers on terrain, allies, enemies, bases and existing markers. Minimap **left-click = "attention to this position"**, **right-click = "moving to this position"**. Commands differ for SPGs.

**Confidence:** High for 9.5, 9.14, 9.15 and 1.10 as summarised. Medium for the circle colours and grid labels.

**Sources:**
- [9.5 update notes](https://worldoftanks.com/en/content/docs/release_notes/95-updatenotes/)
- [9.14 update notes](https://worldoftanks.com/en/content/docs/release_notes/914-updatenotes/)
- [9.15 update notes](https://worldoftanks.com/en/content/docs/release_notes/915-updatenotes/)
- [HyperX: minimap circles](https://blog.hyperx.com/article/4612/world-of-tanks-minimap-and-circles-explained)
- [WOTInspector minimap mod](https://wotinspector.com/en/mods/minimap/)
- [1.10 battle communication](https://worldoftanks.eu/en/news/general-news/1-10-battle-communication/)
- [In-game communication guide](https://worldoftanks.eu/en/content/guide/newcomers-guide/communication/)

#### 13. Reticle and penetration indicator

**Current behaviour:**
- The penetration indicator is an option on the gun marker and is **on by default**.
- **(corrected by fact-check)** The original text said yellow = armour within ±25 % of penetration and that the indicator ignores impact angle. That follows old wiki and guide text. The current client logic is different. The decompiled 2.4 client (`AvatarInputHandler/gun_marker_ctrl.py`, `_CrosshairShotResults`, enabled by `_IS_EXTENDED_GUN_MARKER_ENABLED = True`, already on in 1.0.0) works as follows:
  - Effective armour = nominal ÷ cos(impact angle after shell normalisation). The normalisation boost for overmatching calibres is included.
  - A ricochet check runs first, including the 3× calibre overmatch rule. A predicted ricochet shows red.
  - Spaced armour and module layers are walked in order along the shot line, subtracting penetration each time. HEAT loses penetration per metre after the first plate.
  - Penetration is taken at the current distance.
  - The thresholds use `_PP_RANDOM_ADJUSTMENT_MIN/MAX = 0.5` × the shell's `piercingPowerRandomization`. The default for that is 0.25 (`component_constants.DEFAULT_PIERCING_POWER_RANDOMIZATION`).
- **Green** (`GREAT_PIERCED`): effective armour ≤ **87.5 %** of penetration.
- **Yellow** (`LITTLE_PIERCED`): effective armour between **87.5 % and 112.5 %** of penetration, which is ±12.5 %, half of the ±25 % penetration roll.
- **Red** (`NOT_PIERCED`): effective armour ≥ 112.5 %, or a ricochet is predicted. The shot-result-to-colour mapping is inferred from the enum names; the Flash side was not inspected.
- A green indicator can still fail. Possible causes: a low penetration roll (the roll goes down to 75 %), latency or server-side differences, and hits on non-damaging parts that only cause critical damage.
- Some guides call the middle state "orange".
- The console edition uses a different scheme, so do not mix the two sources.

**Confidence:** Medium-High for the corrected logic. The source is the community-decompiled client scripts ([StranikS-Scan/WorldOfTanks-Decompiled, branch 2.4_EU](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/tree/2.4_EU)), not an official statement. The old "±25 %, ignores angle" wiki text is **superseded**.

**Sources:**
- [WG wiki: Gunnery & Armor Penetration](https://wiki.wargaming.net/de/Gunnery_%26_Armor_Penetration_(WoT))
- [Fandom: Gunnery & Armor Penetration](https://worldoftanks.fandom.com/wiki/Gunnery_%26_Armor_Penetration)
- [Dignitas armour guide](https://dignitas.gg/articles/wot-beginners-guide-part-2-armor-and-penetration-explained)

#### 14. Vehicle markers

**Current behaviour:** floating markers over vehicles show name, vehicle, an HP bar and floating damage numbers. They have a separate **Alt-held mode** and are **configurable per team** in settings (ally and enemy separately). Colour-blind players can also change markers. ([vintageisthenewold FAQ](https://www.vintageisthenewold.com/faq/how-do-you-turn-on-colorblind-mode-in-world-of-tanks))

**Confidence:** Medium-High.

#### 15. Damage log, hit-direction indicators, efficiency feedback

**Current behaviour (9.17.1, 2017):**
- **Fire-direction indicators** show the **amount of damage received or blocked**, **which enemy fired**, and that enemy's marker and name if it was spotted.
- An optional **dynamic width** (off by default) scales the indicator with damage: **Small 1–10 %, Medium 11–30 %, Large 30 %+ of total HP**. The 2.4 client code confirms this. `indicators.py` sets `_MARKER_SMALL_SIZE_THRESHOLD = 0.1` and `_MARKER_LARGE_SIZE_THRESHOLD = 0.3`, and the ratio is damage ÷ the player vehicle's **max** HP. Small is ≤ 10 %, Medium is > 10 % and ≤ 30 %, and Large is > 30 %. With dynamic width off, every hit uses Small.
- The **battle log**, bottom-left by default and **movable**, reports damage received, critical hits, the attacker's vehicle and type, and the **ammo type used**, with premium shells in a different colour.
- Players can turn individual blocks on and off in Settings.

On-screen **efficiency ribbons** (damage, blocked, spotting, assist, kill and so on) appear under the reticle. These are domain knowledge, Medium confidence.

**Confidence:** High (9.17.1 official summary).

**Sources:**
- [9.17.1: New and improved battle indicators](https://worldoftanks.eu/en/news/general-news/update-917-1-damage-log/)
- [9.17.1 list of changes](https://worldoftanks.com/en/content/docs/release_notes/9171-updatenotes/)

#### 16. Sixth Sense and the "spotted" indicator

**Current behaviour:**
- A lamp icon appears near the reticle, with a sound cue, when **your vehicle has been spotted**.
- The icon is **delayed 3 s** after detection. With latency, a player may be targeted for up to about 5 s before realising.
- Since **1.18.1** this is a free, permanent commander feature that works the same way as before.
- One forum source claims a 1 s delay; we treat the official 3 s as correct.

**Confidence:** Medium-High for the 3 s delay; High for 1.18.1. The fact-check could not re-verify the 3 s delay independently. It is a server-side value, absent from the decompiled client scripts, and the web-search budget was exhausted. It agrees with the fact-checked `02-spotting-camouflage.md`.

**Sources:**
- [Tank Coach: spotting](https://worldoftanks.eu/en/content/guide/tank-coach-video-guides/tank-coach-spotting/)
- [1.18.1 Sixth Sense](https://worldoftanks.eu/en/news/general-news/1-18-1-sixth-sense-perk/)
- [Survival guide without 6th sense](https://worldoftanks.com/en/content/player-guide/written-guide/survival-guide-crew-skills/)

#### 17. Kill feed and chat

**Current behaviour:** WoT has **no prominent FPS-style kill feed**. Kills appear as crossed-out or greyed rows in the team panels, as system lines in the chat and battle log, and as the frag counter. Chat sits bottom-left with team and all channels.

**Confidence:** Medium (domain knowledge).

### UI/UX — Flow screens

#### 18. Battle loading screen and pre-battle countdown

**Current behaviour:**
- After clicking Battle!, the **loading screen** shows **complete rosters for both teams** and the **battle objective**, plus the map and tips.
- Once loaded, a **pre-battle countdown** runs. Domain knowledge puts it at 30 s in Random Battles; **not verified** this session.
- **2.4 (Sep 2026) added "Spotlight"** in Random Battles for Tier V+ vehicles. It is a pre-battle presentation whose **duration adapts to the battle loading time** and is followed by the standard pre-battle screen with countdown. Its content is not verified (Low). The title "Make Your Mark Before Battle" suggests it showcases players.

**Sources:**
- [Getting Started](https://worldoftanks.com/content/guide/newcomers-guide/getting_started/)
- [2.4 Spotlight](https://worldoftanks.eu/en/news/general-news/2-4-spotlight/)

#### 19. Post-battle results screen

**Current behaviour (2.0):**
- **Full-screen** results.
- The **player's vehicle appears as a 3D model** with its applied style, against **the battle map** as background, integrated into the garage.
- Tabs include **General, Team Result, Financial Report**.
- The **battle performance table** is an **overlay panel at the bottom of the Overview tab** (click or **Space**).
- **All tabs** have a button to **enter a new battle** or confirm or cancel platoon readiness.

**Confidence:** High.

**Sources:**
- [Release Notes 2.0](https://worldoftanks.com/en/content/docs/release_notes/release-notes-2-0/)
- [TAP: new post-battle statistics screen](https://thearmoredpatrol.com/2025/09/01/wot-new-post-battle-statistics-screen-in-update-2-0/)

### UI/UX — Accessibility

#### 20. What WoT offers

- **Colour-blind mode:** one checkbox under **Settings → Graphics**. It changes enemy **red to purple or blue** and hit markers from red to white. ([vintageisthenewold](https://www.vintageisthenewold.com/faq/how-do-you-change-the-color-blind-setting-in-world-of-tanks))
- **Marker customisation:** separate ally and enemy marker configurations; Alt mode.
- **HUD customisation:** movable battle log, toggleable indicator blocks, minimap size, team-panel widths. Reticle shape and colour options are domain knowledge, Medium.
- **Audio:** Night mode, Low-quality and Bass-boost presets, a choice of playback device (speakers, headphones or laptop), and volume sliders (see item 27). National crew voices exist (domain knowledge, Medium).
- **2.4:** an "Effect and 3D Attachment Visibility" setting **reduces visual effects in aiming mode**, a clarity aid.
- **Not confirmed:** subtitles or captions for crew voice lines, sound-visualisation features, a reduced-motion option. We found no evidence either way (Low).

**Confidence:** Medium overall.

#### 21. Best-practice accessibility guidelines relevant to HULLDOWN

These are domain knowledge. The guideline sites were blocked, so links were not re-checked.

- **WCAG 2.x contrast:** **4.5:1** for body text (SC 1.4.3), **3:1** for large text and essential UI graphics and states (SC 1.4.11). **Three flashes per second** maximum (SC 2.3.1, photosensitivity). (High, well-established.)
- **Xbox Accessibility Guidelines (XAG)**, the items relevant here:
  - **Text display:** adjustable size, readable minimums at TV distance.
  - **Contrast:** backgrounds behind text.
  - **Additional channels for visual and audio cues:** every important sound has a visual equivalent and the other way round.
  - **Subtitles and captions:** speaker label, background, size options.
  - **Audio accessibility:** separate volume sliders, mono option.
  - **Input:** full remapping, hold or toggle.
  - **UI navigation:** gamepad navigation with no dead-ends, clear focus.
  - **Time limits.**
  - **Visual distractions and motion:** reduce or turn off screen shake and camera bob.
  - **Photosensitivity.**
  
  XAG numbering (101+) and exact pixel minimums were **not verified** this session. A commonly cited console minimum is about 26 px at 1080p; treat it as an assumption.
- **Game Accessibility Guidelines (gameaccessibilityguidelines.com):** no essential information by **colour alone** or **sound alone**; separate volume controls; subtitles for important speech; remappable controls; large, well-spaced interactive elements.
- **Touch targets:** Apple HIG ≥ **44×44 pt**, Material ≥ **48×48 dp**.
- **Roblox's own guidelines** (local docs, authoritative), from `production/publishing/accessibility.md`:
  - **Text size:** honour `GuiService.PreferredTextSize` (Medium / Large / Larger / Largest). `TextScaled` text is **not** scaled by it. Text under a `UITextSizeConstraint` still scales, but it is **clamped** to `MinTextSize`/`MaxTextSize` "regardless of the player's text size setting" (corrected by fact-check: the original said this text ignores the setting entirely). Use `AutomaticSize` and `TextWrapped`, which grow with the setting.
  - **Contrast.**
  - **Colour non-reliance:** "over 5 % of people" have colour blindness; use symbols.
  - **Sound non-reliance.**
  - **Preferred transparency:** multiply `BackgroundTransparency` by `GuiService.PreferredTransparency` (1 = default, 0 = opaque).
  - **Reduced motion:** `GuiService.ReducedMotionEnabled`; set tween time to 0 or use a fade instead.
  - **Volume controls per group** (SFX / music / speech).
- **Roblox adaptive and console guidance** (`production/publishing/adaptive-design.md`, `console-guidelines.md`):
  - input fluidity across gamepad, touch, keyboard/mouse and VR
  - responsive layout and dynamic sizing
  - TV players sit **8–10 ft** away
  - keep UI in **TV-safe areas**
  - make every element reachable with 4-way navigation plus select and back
  - **disable the chat window on console**
  - show device-matched button glyphs (`InputActionLabel`, `UserInputService:GetImageForKeyCode()`)
- **Testing:** the Roblox performance docs warn that **mobile speakers have a limited frequency range**, so cues that are clear on headphones "can be muddy or inaudible on a phone speaker" (`performance-optimization/test-on-hardware.md`).

### AUDIO — World of Tanks

#### 22. Technology history

| Version | Date | What changed | Why / notes |
|---|---|---|---|
| 9.14 | **10 Mar 2016** | FMOD replaced by **Audiokinetic Wwise**. Sound processed on a **separate CPU core**. **10–30 distinct simultaneous sound sources**. New recordings of **authentic vehicles on real proving grounds**. Added sounds for **gearbox shifts, suspension and transmission**, track clatter, **shells whizzing by**, new shell hits and enemy engine sounds. | The old engine made new sound effects "time-consuming" and often "sub-par". Wwise is "more resource-friendly". |
| 9.16 | late 2016 | Calibre classes extended so **5 calibres instead of 3** are played in Tier 8–10 battles. **Autoloader clip sounds**: shells left in the clip, last shell, clip empty. **Received-damage sound tiers 0–17 % / 18–35 % / 35 %+**. **Damaged-engine sound**. **"Gun cannot fire" notification**. **Individual sounds for damage to each module**. Gear, acceleration and manoeuvring sounds. | Make damage amounts and vehicle state "even clearer" by ear. |
| 9.14/9.16 era | 2016 | Audio presets: **Night mode** (one-button volume reduction that "considerably decreases the volume of the loudest sounds and … low frequencies"), **Low quality** (fewer simultaneous sounds, the quietest removed first), **Bass boost**. Choice of **speakers / headphones / laptop**. | Device and context adaptation. Exact version: Medium confidence. |
| 1.0 | **20 Mar 2018** | New engine and graphics. **New soundtrack, 60+ pieces** by **Andrius Klimka and Andrey Kulik**, with folk instruments and local musicians per region. **Dynamic battle music**: per-map start, mid-battle and culmination music, a per-map loading-screen tune, **result-dependent closing themes**. | Authentic "tank" music per map. Music reflects the course of battle. |
| 2.4 "Overdrive" | **1 Sep (Asia, Americas) / 2 Sep (EU) 2026** | **"Biggest refresh of visual and sound effects since 2018"**. **Close gunshot sounds for all calibres reworked and rebalanced**. **Secondary gunshot reflections for 5 environment types** (open terrain, near mountains, dense urban, tunnels, large hangars) on all maps. Gunfire, echoes and reflections adapt to surroundings. New shot, penetrating, non-penetrating and ricochet effects and hit decals. New "Effect and 3D Attachment Visibility" setting. | Combat feedback clarity: "every shot, ricochet, penetration and impact tells you more". |

**Confidence:** High for the version and date facts. The Prague Symphony Orchestra recording claim appeared in only one search summary (Medium). The fact-check confirmed the FMOD → Wwise switch in 9.14 from client code. The 0.9.13 `SoundGroups.py` imports `FMOD`, and the 0.9.14 version imports `WWISE` and reads `wwise_language`. The **2.4 live dates are downgraded to Medium**: they come from search summaries only, and the decompiled-client mirror shows only a 2.4 Common Test build dated 2026-08-29.

**Sources:**
- [9.14 improved sounds](https://worldoftanks.com/en/news/general-news/914-improved-sounds/)
- [9.14 improved audio environment (ASIA)](https://worldoftanks.asia/en/news/general-news/914_improved_sound/)
- [In Development: physics and sounds](https://worldoftanks.asia/en/news/general-news/in-development-improved-vehicle-physics-sounds/)
- [HardcoreGamer 9.14 live 10 Mar 2016](https://hardcoregamer.com/2016/03/10/world-of-tanks-update-9-14-improves-sound-physics-adds-new-maps/197200)
- [MMO Culture 9.14](https://mmoculture.com/news/world-of-tanks-update-9-14-arrives-with-upgraded-physics-and-sound/)
- [9.16 new sound (EU)](https://worldoftanks.eu/en/news/general-news/ver-916-sound-changes/)
- [9.16 new sounds (NA)](https://worldoftanks.com/en/news/general-news/9-16-sound/)
- [WG wiki: Update 9.16](https://wiki.wargaming.net/en/Tank:Update_9.16)
- [1.0 new war music](https://worldoftanks.com/en/news/general-news/update-1-0-new-music/)
- [1.0 brand new war music (ASIA)](https://worldoftanks.asia/en/news/general-news/update-1-0-brand-new-war-music/)
- [WG wiki: Update 1.0](https://wiki.wargaming.net/en/Tank:Update_1.0)
- [2.4 upgraded VFX/SFX](https://worldoftanks.eu/en/news/general-news/2-4-upgraded-vfx-sfx/)
- [Update 2.4: Overdrive](https://worldoftanks.com/en/news/updates/wot-2-4/)
- [IDC Games: 2.4 dates](https://idcgames.com/en/world-of-tanks/news/world-of-tanks-update-2.4-brings-six-tier-xi-vehicles,-a-new-german-heavy-line-and-a-battlefield-overhaul-2026-09-03-07-45-13751)
- [YouTube: 2.4 CT old vs new gun sounds](https://www.youtube.com/watch?v=gY0EO65dwHI)

#### 23. Audio layers (what WoT communicates by ear)

| Layer | WoT behaviour | Confidence |
|---|---|---|
| Engine | RPM- and load-dependent. Since 9.14: gear shifts, transmission, suspension. Since 9.16: a distinct damaged-engine sound. | High |
| Tracks | Clatter (9.14). Per-surface variation is domain knowledge. | Medium |
| Turret traverse | Mechanical traverse loop for your own tank. | Medium (domain) |
| Gunshot | Calibre classes (3 → 5 in 9.16). Close shots reworked in 2.4. **Environment-dependent reflections (5 types)** in 2.4. Separate near and far rendering is implied by "close gunshot sounds" plus reflection tails. | High / Medium |
| Shell flyby | "Shells whizzing by" since 9.14. | High |
| Impacts | Distinct audio and visual feedback for **penetration / non-penetration / ricochet**, critical (module) hits, and per-module damage sounds (9.16). | High |
| Received damage | Three sound tiers by % of HP (9.16): 0–17 / 18–35 / 35 %+. | High |
| Crew voice | Callouts for shot results ("Ricochet!", "We didn't penetrate their armor", "Critical hit!", target destroyed), own-vehicle state (fire, module and crew damage), spotting, reload. National-language voice option. | Medium (snippet-level) |
| Autoloader | Clip-state cues: N shells left, last shell, empty (9.16). | High |
| "Gun cannot fire" | Notification sound (9.16). | High |
| Sixth Sense | Lamp icon plus sound cue, 3 s after being spotted. | Medium-High |
| Low HP warning | No dedicated WoT low-HP alarm was found (Low). | Low |
| Music | Dynamic per map: loading → start → mid → culmination, with winning or losing variants, then a result-dependent closing theme (1.0). Garage music exists (domain). | High / Medium |

The "Critical hit" voice has a precise meaning in WoT. It plays when a shell **damages a module or crew member without dealing HP damage**, or penetrates spaced armour but not the main armour. "We didn't penetrate" plays for a non-penetrating hit on main armour ([worldoftanksguide crew voices](https://www.worldoftanksguide.com/ref-crew-voices.shtml), snippet only). HULLDOWN should make the callout text describe the **outcome exactly**, not approximately.

### AUDIO — General best practices for gameplay communication

#### 24. Principles

Domain knowledge; industry talks named for follow-up, links not re-verified.

1. **Information hierarchy beats realism.** Priority order: threats to me (incoming fire, being spotted, nearby enemy shots) > my own action feedback (shot results, reload) > teammates > ambience and music. Blizzard's GDC 2016 talk *"Overwatch: The Elusive Goal — Play by Sound"* (Lawlor and Neumann) is the canonical reference. It describes prioritising threatening sounds and keeping footsteps and abilities informative.
2. **Dynamic range management and "HDR" mixing.** Loud events temporarily lower quieter categories so the important sound reads. This is DICE/Frostbite "HDR audio" and Wwise HDR. On Roblox, approximate it with **sidechain compressors** between buses.
3. **Ducking.** Speech (crew callouts) ducks music and ambience by about 4–8 dB, with attack ≤ 20 ms and release 300–800 ms. Use long releases to avoid "pumping".
4. **Distance cues.** Combine (a) the volume curve, (b) **low-pass filtering with distance** (air absorption removes highs), (c) **distance variants** (near crack versus far boom and rumble), (d) a reverb or reflection tail whose proportion grows with distance, and (e) optionally the **speed-of-sound delay** (343 m/s).
5. **Occlusion and obstruction.** When geometry blocks the path, apply low-pass plus attenuation. Diffraction around corners keeps sound present but muffled.
6. **Spatialisation.** Keep spatialised sources mono so panning and HRTF can work. Use stereo only for 2D beds and music.
7. **Voice management.** Use a fixed budget with priorities. Steal the quietest and least important voice first. Use virtual voices (track but do not render) for inaudible loops. Cap instances per sound.
8. **Anti-spam.** Use 3–6 **variants** per frequent sound in round-robin with no immediate repeats. Add ±3–5 % pitch and ±1–2 dB volume randomisation, minimum retrigger intervals, cooldowns per callout line, and combine bursts ("multi-hit" sounds).
9. **Consistency of meaning.** One sound means one thing. Penetration, non-penetration and ricochet must be distinguishable **by ear alone** within about 150 ms, from different spectral and envelope shapes.
10. **Accessibility.** Every gameplay-critical sound needs a **visual twin**: captions for speech, directional indicators for important sounds. Fortnite's "Visualize Sound Effects" is a well-known reference. Offer separate sliders and mono output.
11. **Device reality.** Phone speakers cut sub-bass, so keep important cues with energy around 1–4 kHz (see the Roblox hardware-testing doc).

### AUDIO — Roblox implementation options

All facts here come from the local docs under `.../creator-docs/content/en-us/`.

#### 25. New modular Audio API (`audio/*.md`, `reference/engine/classes/Audio*.yaml`, `Wire.yaml`)

**Status:**
- `audio/objects.md` says: *"`Sound`, `SoundGroup`, and `SoundEffect` objects are now discouraged in favor of the more robust functionality of audio objects."*
- `SoundService.CharacterSoundsUseNewApi` lets core scripts use the new API for default character sounds.
- The API is still evolving: `AudioPlayer.AssetId` is deprecated in favour of `Asset`, and `AudioEmitter/Listener.SimulationFidelity` is deprecated in favour of `AcousticSimulationEnabled`.

**Objects:**
- **Producers:** `AudioPlayer`, `AudioDeviceInput`, `AudioTextToSpeech`.
- **Consumers:** `AudioEmitter`, `AudioDeviceOutput`, `AudioAnalyzer`, `AudioRecorder`, `AudioSpeechToText`.
- **Modifiers:** `AudioFilter`, `AudioEqualizer`, `AudioCompressor`, `AudioLimiter`, `AudioGate`, `AudioReverb`, `AudioEcho`, `AudioChorus`, `AudioFlanger`, `AudioDistortion`, `AudioPitchShifter`, `AudioTremolo`, `AudioFader`, `AudioChannelMixer`, `AudioChannelSplitter`.
- **Carrier:** `Wire` (`SourceInstance` / `SourceName` pin → `TargetInstance` / `TargetName` pin). Wires can also connect `VideoPlayer` and `VideoDisplay`.

**2D chain:** `AudioPlayer → Wire → AudioDeviceOutput`.

**3D chain:** `AudioPlayer → Wire → AudioEmitter` …(world)… `AudioListener → Wire → AudioDeviceOutput`.

**Key properties and limits:**

| Object | Property / method | Range / behaviour |
|---|---|---|
| `AudioPlayer` | `Asset`, `Volume`, `Looping`, `PlaybackSpeed` (also changes pitch), `PlaybackRegion`, `LoopRegion`, `TimePosition`, `AutoLoad`, `IsReady`, `GetWaveformAsync()` | `Play(atTime?)` / `Stop(atTime?)` **schedule against `SoundService:GetMixerTime()`** for "sample-accurate, framerate-independent timing" and return an action id. `Cancel(actionId)` cancels a scheduled action. `Play` replicates server → client. |
| `AudioEmitter` | `DistanceAttenuationMode` | Presets `Custom` (default), `Inverse` (min/d), `InverseTapered` (min of Inverse and LinearSquared), `Linear` ((max−d)/(max−min)), `LinearSquared` (square of Linear). |
|  | `DistanceAttenuationBounds` | Default **[4, 10000]** studs; used by the presets. |
|  | `SetDistanceAttenuation({[d]=v})` | Custom curve, keys ≥ 0, values 0..1, **≤ 400 points**, linear interpolation, flat beyond the endpoints. An empty curve means **inverse-square**. |
|  | `SetAngleAttenuation({[deg]=v})` | 0..180°, ≤ 400 points (directional sources such as gun muzzles and exhausts). |
|  | `AudioInteractionGroup` | An emitter is heard **only by listeners sharing the group string**. |
|  | `PositionType` | `Parent` or `Instance` (`PositionInstance`). |
|  | `GetAudibilityFor(listener)` | 0..1 including distance and angle attenuation. **Use it for voice-stealing decisions.** |
|  | `AcousticSimulationEnabled` | Occlusion ("muffled through walls"), diffraction ("bending around corners") and reverberation. Requires the emitter, the listener **and** `SoundService.AcousticSimulationEnabled` to be true. |
| `AudioListener` | `SetDistanceAttenuation` / `SetAngleAttenuation`, `GetAudibilityFor`, `AudioInteractionGroup`, `PositionType` (`Enum.ListenerPositionType`) / `PositionInstance`, `GetInteractingEmitters()`. It has **no** `DistanceAttenuationMode` or `DistanceAttenuationBounds`; those presets exist on `AudioEmitter` only (corrected by fact-check). | With `PositionType = Parent`, the parent must be an Attachment, Camera or PVInstance, or the listener "effectively hears nothing". |
| `SoundService` | `DefaultListenerLocation` | `Default` / `None` / `Character` / `Camera`. `Camera` auto-creates Listener + DeviceOutput + Wire. `Character` puts the listener on the character's PrimaryPart, facing the camera. |
|  | `AcousticSimulationEnabled` | Global switch. |
| `PhysicalProperties` | `AcousticAbsorption` | 0..1 per material: how much sound energy the surface absorbs. |
| `AudioFilter` | `FilterType` | Peak, LowShelf, HighShelf, **Lowpass6/12/24/48 dB**, Highpass12/24/48 dB, Bandpass, Notch. `Frequency` **20–22000 Hz**, `Gain` −30..30 dB, `Q` 0.1–10. |
| `AudioEqualizer` | 3 bands | `LowGain` / `MidGain` / `HighGain` −80..+10 dB. `MidRange` crossovers 200–20000 Hz. |
| `AudioCompressor` | Pins Input, **Sidechain**, Output | `Threshold` −60..0 dB, `Ratio` 1–50, `Attack` 0.0001–0.5 s, `Release` 0.01–5 s, `MakeupGain` −30..30 dB. "If any Wires are connected to the Sidechain pin … this can be used to duck the volume of one stream in response to another." |
| `AudioLimiter` | `MaxLevel` | **−12..0 dB**, `Release` 0.001–1 s. |
| `AudioGate` | `Threshold` | NumberRange (hysteresis), `Attack` / `Release` 0.001–5 s. |
| `AudioFader` | `Volume` | **0–3** (linear multiplier). Our bus fader. |
| `AudioReverb` | Decay and diffusion parameters | `DecayTime` 0.1–20 s, `Density` and `Diffusion` 0.1–1, `DryLevel` / `WetLevel` −80..20 dB, `EarlyDelayTime` 0–0.3 s, `LateDelayTime` 0–0.1 s, `HighCutFrequency` 20–20000 Hz, and more. |
| `AudioEcho` | Echo parameters | `DelayTime` 0.001–5 s, `Feedback` 0–1, `Dry` / `Wet` −80..10 dB. |
| `AudioPitchShifter` | `Pitch` | 0.5–2 without changing speed. Frequency-domain processing, so artefacts at extremes. |
| `AudioAnalyzer` | Metering | `PeakLevel`, `RmsLevel`, `GetSpectrum()`. **Server always returns 0: "all audio processing is disabled on the server".** |
| `AudioChannelMixer` / `Splitter` | Channel layouts | Mono … **7.1.4** (12 channels). |
| `AudioDeviceOutput` | `Player` | Optional: restrict who hears the stream. |
| `AudioTextToSpeech` | `Text`, `VoiceId` | **300 characters per request**. Voices 1–11 (English variants, retro, host) plus 101–1002 (es, de, it, fr, zh, hi, ja, ar, ko, pt male and female). Must follow Community Standards. |

**Tooling:** `SoundService:OpenAttenuationCurveEditor()` and `OpenDirectionalCurveEditor()` open Studio's curve editors.

**Performance and memory:**
- The microprofiler tag "Sound" covers acoustic simulation and active playback updates.
- `Sound/stepInstances` covers updating active sounds; the documented remedy is "reduce the amount of sounds in active playback" (`performance-optimization/microprofiler/tag-table.md`).
- Audio memory shows in Scene Analysis. "Deleting all instances that refer to an audio track allows that memory to unload" (`scene-analysis.md`).
- Preload with `ContentProvider:PreloadAsync()` (`improve.md`).

**Not documented:**
- Doppler on `AudioEmitter`.
- Any engine polyphony or voice cap.
- The CPU cost of acoustic simulation per emitter.

**Assets** (`audio/assets.md`):
- Formats `.mp3/.ogg/.wav/.flac`, single track, **< 20 MB, < 7 min, ≤ 48 kHz**, mono / stereo / 3.0 / 5.1.
- **2,000 uploads per 30 days if ID-verified, 100 if not.**
- Upload through the Asset Manager, the Dashboard, or Open Cloud `POST https://apis.roblox.com/assets/v1/assets` (`assetType: "Audio"`).
- Moderation applies. Uploads are auto-classified as sound effect or song.

#### 26. Legacy Sound API (`sound/*.md`, `Sound.yaml`, `SoundGroup.yaml`, `SoundService.yaml`)

- **`Sound`:**
  - `Volume` 0–10 (default 0.5).
  - `RollOffMode` Inverse / Linear / LinearSquare / InverseTapered with `RollOffMinDistance` / `RollOffMaxDistance`.
  - `PlaybackSpeed`, `PlaybackRegion` / `LoopRegion`, `PlaybackLoudness` 0–1000.
  - `PlayOnRemove`.
  - **Doppler** for sounds parented to parts or attachments (`SoundService.DopplerScale`, `DistanceFactor` **3.33 studs per metre**).
- **`SoundGroup`:** volume multiplier 0–10. A sound belongs to **one** group. Groups can nest. Child `SoundEffect`s apply to the group.
- **Effects:** Chorus, Compressor (with `SideChain` to a Sound or SoundGroup), Distortion, Echo, Equalizer, Flange, PitchShift, Reverb, Tremolo.
- **Global settings:** `SoundService.AmbientReverb` uses **FMOD presets** (`ReverbType`: Hangar, City, Mountains, Forest, Plain and others) for all Sounds. `RolloffScale`. A **single listener** (`SetListener`).
- **No** angle attenuation, multiple listeners, acoustic simulation, scheduled playback or arbitrary routing.

#### 27. Comparison and recommendation

| Need for HULLDOWN | New Audio API | Legacy Sound |
|---|---|---|
| Category buses for 3D sounds | **Yes**: one listener per `AudioInteractionGroup` → per-bus `AudioFader` | Partial: SoundGroups (one group per sound) |
| Sidechain ducking | Yes (`Sidechain` pin) | Yes (`CompressorSoundEffect.SideChain`) |
| Distance low-pass | Yes (`AudioFilter` LP 6–48 dB, script-driven) | EQ effect per sound only |
| Occlusion and diffraction | **Built-in acoustic simulation** plus manual filter | Manual only |
| Custom distance curves | 400-point curve or presets | 4 modes plus min/max |
| Directional sources | Angle curves | No |
| Sample-accurate music transitions and delays | **`Play(atTime)`** | No |
| Doppler | Not documented | Yes |
| Metering | `AudioAnalyzer` (client) | `PlaybackLoudness` |
| Boilerplate per voice | Higher (Player + Emitter + Wire, plus Filter and Wire) | Lower (one instance) |
| Platform direction | **Recommended** | **Discouraged** |

**Decision: use the new Audio API exclusively.** Build all graphs in client code under one `AudioMixer` module. Add shell-flyby pitch bends manually with `PlaybackSpeed` envelopes to stand in for Doppler. Confidence: High. The trade-off is more instances per voice, which pooling handles (see Recommendation B5).

### Roblox UI platform facts used by the style guide

#### 28. Fonts (`reference/engine/enums/Font.yaml`, `datatypes/Font.yaml`, `resources/builder-font-license.md`)

- **Gotham, GothamMedium, GothamBold and GothamBlack are "removed"** and map to **Montserrat**. Arial maps to **Arimo**.
- **Builder Sans** has enum values Regular, Medium, Bold and ExtraBold (`Enum.Font.BuilderSans*`). Font families also include **Builder Extended** and **Builder Mono** (`rbxasset://fonts/families/BuilderSans.json`, `BuilderExtended.json`, `BuilderMono.json`).
- **Licence:** use is limited to creating and publishing Roblox UGC and digital promotions of that UGC. Other use needs written permission.
- **Other families:** Oswald, Roboto / Roboto Condensed / Roboto Mono, Titillium Web, Michroma, Sarpanch, Zekton, Jura, Montserrat, Source Sans Pro, Inconsolata, Press Start 2P and more.
- `Datatype.Font` supports weight and style. Setting `Weight` at SemiBold or above sets `Bold = true`.
- The Roblox chat UI uses BuilderSansMedium and BuilderSansBold.

#### 29. Styling, states and safe areas

- **Engine stylesheets** (`ui/styling/index.md`):
  - `StyleSheet` with **tokens** (attributes), **themes** (swappable token sets), `StyleDerive`, `StyleLink` (one sheet per tree).
  - `StyleRule` selectors: class, `.tag`, `#name`, `::` pseudo-instances (UICorner, UIStroke), **state selectors from `Enum.GuiState` = Idle, Hover, Press, NonInteractable**.
  - **`StyleQuery`** conditions such as `MinSize` / `MaxSize` (container size) and `PreferredInput`, for responsive and cross-input styling. Conditions are set with `StyleQuery:SetCondition(s)` or `SetProperty` on a `::StyleQuery` pseudo-instance rule. `ui/styling/compatibility.md` also lists `AspectRatioRange`, `ViewportDisplaySize` and a reduced-motion condition, and there are built-in queries such as `@ViewportDisplaySizeSmall`. The docs disagree on the input condition's name: the class reference says `PreferredInput` and `compatibility.md` says `PreferredInputType`. Test both in Studio. (added by fact-check)
- **`ScreenGui.ScreenInsets`:** `None`, `DeviceSafeInsets`, **`CoreUISafeInsets`** (recommended for interactive UI) and `TopbarSafeInsets`. `GuiService.TopbarInset` (a `Rect`) is the free area in the top bar, and it changes dynamically.
- **`GuiService.ViewportDisplaySize`:** Small (phones and tablets), Medium (laptops and monitors), Large (TVs).
- **`UserInputService.PreferredInput`:** KeyboardAndMouse, Gamepad, Touch, MicroGamepad.
- **3D in UI:**
  - `ViewportFrame` for garage and armour views; `WorldModel` inside a ViewportFrame **enables raycasts** against its parts.
  - `BillboardGui` (`AlwaysOnTop`, `MaxDistance`, `DistanceLowerLimit` / `UpperLimit`) for vehicle markers.
  - `Highlight` for outlines; the client shows **at most 255** at once.
- **Chat:** `TextChatService` with default channels, including **RBXTeam**. Messages must go through `TextChannel` for filtering. Disable the chat window on console (`chat/*.md`).

---

## Implementation recommendations for HULLDOWN (Roblox)

Items labelled **OUR DESIGN CHOICE** are our proposals, not WoT facts.

### A. UI style guide

**A1. Reference frame and scaling (OUR DESIGN CHOICE)**
- **Reference canvas: 1920×1080.** Every desktop and tablet layout is authored on it.
- **Layouts** are switched with `StyleQuery` (`MaxSize` on the root ScreenGui) and `GuiService.ViewportDisplaySize`:
  - **Compact** (phones): viewport height < 600 px, as a `StyleQuery` `MaxSize` on the root container. Authored at **844×390**. **(corrected by fact-check)** Do **not** use `DisplaySize.Small` alone as the trigger. Roblox defines Small as "most tablet/mobile/handheld devices", so tablets would get Compact, which contradicts "Regular for desktop and tablet". Use Small only together with the height test.
  - **Regular:** `UIScale = clamp(viewportHeight / 1080, 0.67, 2.0)`.
  - **TV** (`DisplaySize.Large`, or Gamepad as preferred input on a large display): Regular plus a **5 % safe margin (96 / 54 px at 1080p)** plus **text +20 %**.
- **Effective text size floor:** never below **14 px** after scaling on desktop, **16 px** on TV, **13 pt** on Compact. If a computed scale would break this, switch layouts rather than shrink.
- Interactive ScreenGuis use `ScreenInsets = CoreUISafeInsets`. HUD gauges may use `DeviceSafeInsets`, but nothing interactive may sit under `GuiService.TopbarInset`.

**A2. Grid and spacing (OUR DESIGN CHOICE)**
- 8 px base unit. Spacing tokens: `space.1=4, .2=8, .3=12, .4=16, .5=24, .6=32, .7=48, .8=64`.
- **12-column grid** at 1920: 48 px outer margins, 24 px gutters, **130 px columns**.
- Garage split: left vertical nav = 1 column (130 px collapsed, icons only; 260 px expanded). Centre stage = 8 columns. Right column (missions and events) = 3 columns.
- **Corner radius:** `radius.s=2, .m=4, .l=8` (industrial, almost square). Stroke 1 px `UIStroke`.
- **Touch targets:** ≥ **48×48 px** on Compact, matching the 44 pt and 48 dp norms. Desktop clickable rows ≥ 32 px tall.

**A3. Typography (OUR DESIGN CHOICE)**

| Token | Font | Weight | Size / line (px @1080p) | Use |
|---|---|---|---|---|
| `type.display` | Oswald | Bold | 56 / 64 | VICTORY / DEFEAT, mode titles |
| `type.h1` | Oswald | SemiBold | 32 / 40 | Screen titles (uppercase) |
| `type.h2` | Builder Sans | Bold | 24 / 32 | Panel titles |
| `type.h3` | Builder Sans | Medium | 20 / 28 | Sub-sections, card titles |
| `type.body` | Builder Sans | Regular | 18 / 26 | Body text, tooltips |
| `type.label` | Builder Sans | Medium | 16 / 22 | Buttons, tabs, list rows |
| `type.caption` | Builder Sans | Regular | 14 / 20 | Secondary info (minimum on desktop) |
| `type.num.l` | Builder Mono | Bold | 28 / 32 | HP, battle timer |
| `type.num.m` | Builder Mono | Medium | 18 / 22 | Ammo counts, stats, prices |
| `type.num.s` | Builder Mono | Regular | 14 / 18 | Table numbers |

Rules:
- Use **monospaced figures for any number that changes** (timers, HP, reload, counts) so text does not jitter.
- **Do not use `TextScaled`** for body or labels, because it ignores `PreferredTextSize`. Use fixed sizes with `AutomaticSize` and `TextWrapped`. A `UITextSizeConstraint` is allowed only on HUD numerics, where overflow would break the layout. It clamps the player's text-size preference at `MaxTextSize`, so leave headroom between the token size and `MaxTextSize`. The docs do not publish the scale factor for each `PreferredTextSize` step (corrected by fact-check: the constraint clamps the preference rather than ignoring it).
- **Avoid Gotham**, which is removed.
- The **Builder licence** limits Builder fonts to Roblox UGC and its digital promotion. Marketing outside the game (store pages, trailers) should use Oswald or Roboto, which come with the engine.

**A4. Colour tokens (OUR DESIGN CHOICE)**

Contrast ratios computed with WCAG relative luminance:

| Token | Hex | On `bg` #0E1317 | On `surface.2` #1F2830 | Use |
|---|---|---|---|---|
| `bg` | #0E1317 | — | — | Screen background |
| `surface.1` | #161D23 | — | — | Panels |
| `surface.2` | #1F2830 | — | — | Raised cards, HUD plates |
| `surface.3` | #2A353F | — | — | Hover fill |
| `stroke` | #3A4752 | 1.96 | 1.57 | Decorative dividers only (not essential) |
| `text.primary` | #E9EEF2 | **15.99** | **12.80** | Primary text |
| `text.secondary` | #A7B3BD | 8.74 | 7.00 | Secondary text |
| `text.disabled` | #66727C | 3.79 | 3.04 | Disabled (exempt from 4.5:1, never essential) |
| `accent` | #F2B233 | 9.96 | 7.97 | Primary CTA fill (text on it: `bg`, **9.96:1**), focus ring |
| `team.ally` | #4DB8FF | 8.55 | 6.85 | Allies (markers, panels, minimap) |
| `team.enemy` | #FF4F4F | 5.77 | 4.62 | Enemies |
| `team.platoon` | #FFD84D | 13.50 | 10.81 | Platoon mates |
| `team.self` | #FFFFFF | — | — | Own vehicle |
| `state.destroyed` | #87919A | 5.82 | 4.66 | Dead vehicles (plus a strike-through icon). (corrected by fact-check: the original #7D8790 gave 5.11 / **4.09**, which fails 4.5:1 for dead-player names on `surface.2` panels.) |
| `status.ok` | #5ED37A | 9.85 | 7.89 | Healthy module, positive delta |
| `status.warn` | #FFB020 | 10.21 | 8.18 | Damaged module |
| `status.crit` | #FF5A4F | 6.07 | 4.86 | Destroyed module, fire |
| `pen.yes` | #4CD964 | 10.16 | 8.13 | Reticle: will penetrate |
| `pen.maybe` | #FFB000 | 10.20 | 8.16 | Reticle: borderline |
| `pen.no` | #FF3B30 | 5.27 | 4.22 | Reticle: will not penetrate |

**Colour-vision checks:**
- We used CIELAB ΔE after Machado-2009 deuteranopia, protanopia and tritanopia simulation.
- **Ally blue versus enemy red:** ΔE 112 normal, **93 deutan, 68 protan, 129 tritan**. Team identity needs **no** colour-blind swap. This is a deliberate improvement on WoT's green-ally default.
- **Default penetration palette, green / amber / red:** the smallest pair is **20** (protan, green versus amber) and 21 (deutan, green versus red). That is not safe on its own.
- **Colour-blind preset `pen.cb` (OUR DESIGN CHOICE):** yes `#3DDBD9`, maybe `#FFD84D`, no `#D62AD0`. The smallest pair is **34** under deutan (yes versus no). Every other pair under deutan, protan and tritan is between 56 and 147.
- **Shape coding is always on**, whatever the palette:
  - **pen.yes** = solid ring with a centre dot
  - **pen.maybe** = dashed ring
  - **pen.no** = ring with an × through it
- `status.ok` and `status.crit` (green / red) also fail deutan (ΔE 18). Module icons therefore change **shape and overlay**: healthy = outline, damaged = outline plus a "!" badge with a striped fill, destroyed = filled with an × badge. Colour is only reinforcement.

**A5. Component states (OUR DESIGN CHOICE)**

Map `Enum.GuiState` through StyleRule state selectors:

| State | Fill | Stroke | Text | Other |
|---|---|---|---|---|
| Idle | `surface.2` | `stroke` | `text.primary` | — |
| Hover | `surface.3` | `accent` at 60 % | `text.primary` | 80 ms tween; 0 ms when `ReducedMotionEnabled` |
| Press | `surface.1` | `accent` | `text.primary` | Content offset 1 px down |
| NonInteractable (disabled) | `surface.1` | — | `text.disabled` | Disabled reason shown in a tooltip |

Additional states:
- **Selected / focused** (gamepad `GuiService.SelectedObject`): **2 px `accent` outline plus 4 px outer glow**. Never shown by colour alone.
- **Primary CTA ("BATTLE")**: `accent` fill, `bg` text, `type.h2`. Size 280×64 px desktop, 220×72 px Compact.

**A6. Motion (OUR DESIGN CHOICE)**
- Standard 150 ms ease-out for panels, 80 ms for hover, 300–600 ms count-ups on the results screen.
- With `ReducedMotionEnabled`: no slides (fades only), no count-ups (show final values), **no camera shake or recoil kick**.
- Never more than 3 full-screen flashes per second (WCAG 2.3.1). Damage vignette ≤ 35 % opacity, fading over ≥ 400 ms.

**A7. Iconography:** an original monoline icon set on a 24 px grid with a 2 px stroke. Vehicle-class icons must differ by **silhouette shape**, not colour. (Asset production belongs to Phase F.)

### B. Screen-by-screen guidance

**B1. Garage (OUR DESIGN CHOICE, informed by WoT 2.0)**
- **Top bar (64 px):**
  - Left: Back button (universal, as in WoT 2.0) and section title.
  - Centre: selected vehicle name, tier, class icon, XP-to-next bar (2.0 put name and XP top-centre).
  - Right: currencies (exact names per the economy research doc) with "+" buttons, premium timer, profile.
- **Left vertical nav** (2.0 pattern): Garage · Tech Tree · Crew · Missions · Season Pass · Store · Profile · Settings. Collapsed icons are 56 px tall with text on hover or focus.
- **Right column:** daily missions (3 cards) and event cards.
- **BATTLE button and mode selector:**
  - Desktop: top-centre below the vehicle title, a WoT-familiar location. The selector is a chevron on the button.
  - Compact: bottom-right thumb zone.
  - Show queue state and estimated wait on the button itself.
- **Service strip** (2.0 pattern: everything in one place) directly above the carousel: Modules · Equipment (slots) · Ammo (with counts and auto-resupply toggle) · Consumables · Crew · Appearance. Each item opens a side drawer, not a new screen.
- **Carousel:**
  - Cards 168×104 px (Regular); 1 or 2 rows (setting); horizontal scroll with gamepad shoulder paging.
  - A **filter button with a "selected / total" badge** (2.0 pattern).
  - Filters: nation or faction, class, tier, owned, premium, elite, favourites, plus **Playlists**: user lists with **share-code import and export** as a string. That suits Roblox better than file import.
  - **Space** (keyboard) or **Y** (gamepad) opens **My Vehicles**, a full-screen grid.
  - Sort by tier / class / name / recently played.
- **About Vehicle** (2.0 pattern), tabs:
  - **Overview:** stats with ▲/▼ deltas against the current configuration.
  - **Modules:** research graph.
  - **Armor:** inspector in a ViewportFrame with a WorldModel, so hover raycasts work. It shows nominal, angle and effective thickness. Selecting an attacker, gun and shell (the 2.2 pattern) recolours plates with the **same `pen.*` tokens and shapes as the reticle**: one visual language.
  - **Compare.**
- **Compare:** up to **6 vehicles** side by side (WoT allows 20; 6 fit 1080p without horizontal scroll). Rows highlight best and worst with an icon as well as colour. Configurations: stock / current / custom (the 9.16 and 9.17.1 patterns).
- **Tech tree:**
  - Columns per tier; nodes 176×96 px; research lines 2 px.
  - Node states: Locked (padlock), Researchable (XP cost), Researched (price), Owned, Elite (star).
  - Pan, zoom and gamepad 4-way navigation along lines.

**B2. Battle HUD, Regular layout at 1080p (OUR DESIGN CHOICE)**

| Element | Position / size | Behaviour |
|---|---|---|
| Score bar | Top-centre, 560×56 | Frags `A : B`; two **team-HP bars** (240 px each) with numbers. A setting mirrors the console modes: **Full / Bar only / % only / None**. |
| Battle timer | Under the score bar, `type.num.l` | `mm:ss`. Turns `status.warn` under 2:00 and `status.crit` under 0:30, **plus a pulsing frame** (no colour-only signal). |
| Team panels ("ears") | Top-left (ally), top-right (enemy), rows 22 px | Modes: Hidden / Compact (class icon, HP bar) / Full (name, vehicle, HP, frags). **Tab** cycles; hold **Tab** for the full scoreboard. Dead = `state.destroyed` plus strike-through. |
| Minimap | Bottom-right | Sizes **224 / 288 / 352 / 416 / 480 px** on `-` / `=` (default 352). Grid 10×10 with labelled squares. Circles: view range, max spotting, render limit. **Last-known enemy positions on by default**, fading after 30 s (OUR DESIGN). Pings on click. Opacity setting. |
| Damage panel | Bottom-left, 360×200 | Silhouette, HP number (`type.num.l`) and bar, speed. Module and crew icons with **shape-coded** states. Fire badge. |
| Damage log | Above the damage panel, max 8 lines | Received, blocked and critical events with attacker vehicle and ammo type. Movable. Each line fades after 12 s. |
| Ammo and consumables | Bottom-centre, 6 slots × 64 px, 8 px gap | Keys 1–3 ammo, 4–6 consumables. Cooldown sweep plus seconds text. Selected shell has an `accent` outline. |
| Reticle | Centre | Penetration indicator (`pen.*` plus shape); reload ring radius 28 px plus seconds text to the right; autoloader clip pips. **(corrected by fact-check)** WoT's indicator is angle-aware (see item 13). If we copy the pattern, evaluate **effective** armour: angle and normalisation, ricochet, spaced layers. Put the yellow band at ± half of our penetration-roll spread, which is ±12.5 % for a ±25 % roll. The combat doc owns the final thresholds. |
| Spotted ("sixth sense") | 160 px above the reticle, 64 px icon | Shows when the server reports we have been spotted (delay per the spotting doc; WoT uses 3 s). Holds 3 s, then fades. A **sound cue** plays alongside. |
| Hit-direction indicators | Ring radius 220 px around the centre | Arc width by damage tier: **small ≤ 10 %, medium > 10–30 %, large > 30 % of max HP**. These are WoT's thresholds (boundaries corrected by fact-check to match the client's `<=` comparisons), used as a reasonable default. Separate "blocked" style with a hollow arc. |
| Efficiency ribbons | 120 px below the reticle | Max 3 stacked, 2.5 s each: Damage, Blocked, Spotted, Assist, Kill, Crit. |
| Kill feed | Right side under the enemy panel | **OUR DESIGN CHOICE (not WoT):** compact, max 5 lines, 6 s each. The Roblox audience expects it. |
| Chat | Bottom-left above the damage log | `TextChatService`, **RBXTeam** by default. All-chat optional. Hidden on console. |
| Vehicle markers | `BillboardGui`, 160×40 | Name and class icon; HP bar 80×6; damage pop-ups. **Alt** shows full HP numbers. Team colour plus shape: allies get a downward chevron, enemies a red diamond. |
| Comms | — | **T** opens a context ping on what the reticle points at (1.10 pattern). Minimap left-click = "attention", right-click = "moving there". Rate limit 3 pings per 5 s per player (OUR DESIGN). |

**B3. Compact (phone) and gamepad HUD (OUR DESIGN CHOICE)**
- **Compact layout:**
  - Left thumb: movement joystick.
  - Right thumb: aim drag area plus a **96 px fire button**.
  - Ammo and consumables: vertical stack of 56 px buttons on the right edge.
  - Minimap top-left at 180 px (tap to enlarge to 60 % of the screen).
  - Score bar top-centre; compact damage panel top-right.
  - Team panels hidden behind a swipe-down scoreboard.
- **Gamepad:**
  - LB / RB hold opens **radial menus** for ammo, consumables and comms.
  - D-pad cycles minimap sizes.
  - Glyphs come from `InputActionLabel` / `GetImageForKeyCode`.

**B4. Loading → pre-battle → results (OUR DESIGN CHOICE)**
- **Loading screen:** map art and name, mode, **objective sentence**, both rosters (name, class, tier), one gameplay tip, progress. Preload map audio and VFX here with `ContentProvider:PreloadAsync`.
- **Pre-battle countdown: 20 s** (OUR DESIGN). WoT is believed to use 30 s, unverified. Roblox sessions favour shorter waits. Run a music build-up whose **downbeat is scheduled with `Play(atTime)`** to land on "GO".
- **Results** (2.0 pattern): full-screen over a 3D garage or map backdrop. Tabs:
  - **Overview:** outcome, XP, credits, damage, assist, blocked, spotted, kills, achievements.
  - **Team:** sortable table; Space toggles an overlay.
  - **Economy.**
  - **Details:** per-enemy hit log.
  
  **"Battle again" with the same vehicle on every tab.** Count-ups are skipped when reduced motion is on.

**B5. Accessibility settings menu (OUR DESIGN CHOICE)**
- **Colour-blind preset:** Off / Red-green (deutan and protan) / Blue-yellow (tritan). It changes the `pen.*` and `status.*` tokens; team colours stay put. Shape coding is always on.
- **HUD scale:** 80–150 %, applied as a UIScale multiplier on HUD only.
- **Text:** honours `PreferredTextSize`.
- **Panel opacity:** honours `PreferredTransparency`, plus our own 0–100 % slider.
- **Reduced motion:** honours `ReducedMotionEnabled`. It also disables camera shake, recoil camera kick and UI slides.
- **Callout captions:** prompted on first launch, then a setting. Two lines maximum, 30 % black backing, speaker icon (crew role).
- **Sound visualisation (parity aid):**
  - Directional HUD glyphs for **audible** gunfire within 300 m, shell flybys, and incoming hits.
  - Never for sounds the player could not hear.
  - Never for unspotted-vehicle engines, which the client should not even know about.
- **Mono audio** toggle.
- **Remapping** through the Input Action System; **hold or toggle** for sniper zoom and free-look.

### C. Audio architecture and mix-bus plan (OUR DESIGN CHOICE unless cited)

**C1. Graph** (all client-side; `SoundService.DefaultListenerLocation = None`; we build our own)

```
[2D buses]
 UI players ─────────────► Fader UI (−6 dB, 0.501) ──────────────┐
 Crew-VO player (1 voice) ► Fader VO (−3 dB, 0.708) ─┬───────────┤
 Critical cues (spotted,   ► Fader CRIT (0 dB, 1.0) ─┼───────────┤   (never ducked)
   hit-received, can't fire)                         │           │
 Music players ──► Compressor MUS(sidechain ← VO, ← WPN) ► Fader MUSIC (−12 dB battle / −6 dB garage)
                                                                  │
[3D buses = one AudioListener per AudioInteractionGroup, all parented to the camera]
 Listener "own"  ─► Fader OWN (0 dB)  ─────────────────────────────┤
 Listener "wpn"  ─► Fader WPN (0 dB)  ─┬───────────────────────────┤  (sidechain source)
 Listener "veh"  ─► Compressor VEH(sc ← WPN) ► Fader VEH (−6 dB) ──┤
 Listener "amb"  ─► Compressor AMB(sc ← WPN, ← VO) ► Fader AMB (−12 dB)
                                                                  ▼
      Fader MASTER (user) ► Compressor GLUE (thr −18 dB, ratio 2, att 0.01 s, rel 0.25 s)
                          ► AudioLimiter (MaxLevel −1 dB, Release 0.1 s) ► AudioDeviceOutput
```

- **Sub-buses for 3D sounds** work through `AudioInteractionGroup`: an emitter is heard only by listeners with the same group. Each category listener therefore feeds its own fader and effects. Each emitter belongs to exactly one group.
- **Ducking settings** stay within documented ranges:

  | Sidechain | Threshold | Ratio | Attack | Release | Target reduction |
  |---|---|---|---|---|---|
  | VO → Music | −30 dB | 4 | 0.01 s | 0.6 s | ≈ 6 dB |
  | WPN → Ambience | −24 dB | 3 | 0.005 s | 0.8 s | ≈ 6 dB |
  | WPN → Vehicles | −24 dB | 2 | 0.005 s | 0.4 s | ≈ 3 dB |
  | WPN → Music | −24 dB | 2 | 0.01 s | 1.0 s | ≈ 4 dB |

  Tune by ear using `AudioAnalyzer` meters on each bus in a debug overlay.
- **Player sliders** map to bus faders: Master, Music, World SFX (WPN + VEH), Own vehicle, Crew voice, UI, Ambience.
- **Presets** (WoT-inspired):
  - **Night mode:** master glue compressor threshold −30 dB, ratio 4; master `AudioEqualizer` LowGain −6 dB.
  - **Bass boost:** LowShelf +4 dB at 120 Hz on OWN and WPN.
  - **Phone speaker:** HighPass12dB at 120 Hz, +3 dB Peak at 2.5 kHz on CRIT and VO.

**C2. Voice budget and pooling**
- **Global cap: 32 rendered voices.** WoT's Wwise upgrade cited 10–30 distinct simultaneous sources.

  | Category | Cap |
  |---|---|
  | Weapons | 12 |
  | Impacts | 8 |
  | Flyby | 3 |
  | Vehicle loops (nearest by `GetAudibilityFor`) | 8 |
  | Ambience loops | 6 |
  | UI | 4 |
  | Crit cues | 3 |
  | VO | 1 (+ queue 3) |

  Totals are enforced globally.
- **(clarified by fact-check)** A voice means one sounding `AudioPlayer`. A gunshot that plays 2 distance layers plus an environment tail (C3) therefore uses **3** voices from the Weapons cap of 12. Budget about 4 full-detail distant shots at once, and drop the tail first when the cap is reached. Each slot below has one `AudioPlayer`, so a layered shot takes several slots. The alternative is giving each slot a second player for the tail, as C3 describes, and counting that player as a voice.
- **Pool:** pre-create **48** "voice slots" at battle load. Each slot is an `AudioPlayer`, an `AudioFilter` (low-pass), an `AudioEmitter` (`PositionType=Instance` pointing at a pooled `Attachment` under `workspace.Terrain`), and 2 Wires. Playing a sound means moving the attachment, setting `Asset`, the filter frequency, `Volume` and `PlaybackSpeed`, and the emitter's `AudioInteractionGroup`, then calling `Play()`. Release the slot on `Ended`.
- **Stealing order:** lowest `priority × audibility`. Own-vehicle, CRIT and VO are never stolen.
- **Instance caps per asset:**
  - same impact asset ≤ 4 at once
  - same gunshot asset from the same shooter ≥ 80 ms apart
  - 3–6 variants per frequent sound in round-robin with no immediate repeat
  - ±4 % pitch and ±1.5 dB volume randomisation

**C3. Distance rendering for gunshots and impacts**
- **Scale:** distances below are in metres. Convert with the project's scale constant. 3.33 studs/m is the default of `SoundService.DistanceFactor`, and we can borrow the number if the core doc adopts it. The property itself only drives legacy `Sound` Doppler and "does not impact" `AudioPlayer`/`AudioEmitter`. Our code must apply the conversion when building curves and computing delays (clarified by fact-check).
- **Three layers per calibre class** (four classes in HULLDOWN, OUR DESIGN). Weights are computed when the shot fires, and at most the 2 highest-weight layers play:
  - **Near** (sharp transient and mechanism): full at 0–60 m, gone by 150 m.
  - **Mid** (body): ramps 30→60 m, full to 250 m, gone by 400 m.
  - **Far** (low boom plus tail): ramps 200→300 m, full to 600 m, zero by 1000 m.
- Emitter custom curves are set to match, so moving listeners stay consistent. In studs at 3.33/m, for example Near = `{[0]=1, [200]=1, [500]=0}`.
- **Air absorption:** Lowpass12dB at 20 kHz (0 m) → 8 kHz (200 m) → 3 kHz (600 m) → 1.5 kHz (1000 m), log-interpolated.
- **Speed-of-sound delay** for shots beyond 100 m: `Play(SoundService:GetMixerTime() + d/343)`. That is 0.29 s at 100 m and 0.87 s at 300 m. The muzzle flash leads the sound, which is realistic and helps judge distance. A setting can turn it off.
- **Environment tails** (inspired by 2.4's five environment types): map designers tag zones `Open / Forest / Urban / Canyon / Enclosed`. A tail one-shot (a separate asset per zone) fires from the shooter's zone at −6 dB relative, sharing the voice slot's emitter through a second player. Its weight rises with distance.

**C4. Occlusion (hybrid)**
- **Tier 1:** `AcousticSimulationEnabled = true` on the **8 highest-priority emitters** (own tank, plus the nearest enemy shots and engines within 150 m), on **every category listener whose interaction group those emitters use** (OWN, WPN and VEH in C1), and on SoundService. The docs require the emitter, the listener and the global switch to be true together. The original said "the listener", which does not fit the four-listener graph in C1 (corrected by fact-check). **Gate this behind a performance flag.** First profile the "Sound" microprofiler label on low-end mobile; the cost is not documented.
- **Tier 2 (fallback and everything else):** one `workspace:Raycast` from listener to source at trigger time for one-shots, or at 10 Hz for loops. Use a collision group "AcousticBlockers" (terrain and buildings). If occluded: −6 dB and low-pass min(current, 1200 Hz), with 150 ms smoothing.
- **Materials:** set `PhysicalProperties.AcousticAbsorption` on custom materials: foliage 0.7, concrete 0.1, metal 0.05 (OUR DESIGN starting values).

**C5. Vehicle sound model**
- **Engine** (own tank: full model; others: LOD):
  - 3 loops (idle / mid / high), crossfaded by normalised RPM `r`: idle `1−r/0.35`, mid a triangle peaking at 0.5, high from 0.6→1.
  - `PlaybackSpeed = 0.85 + 0.3·band-local r`.
  - Throttle-off: `AudioEqualizer` HighGain −6 dB.
  - Gear-shift "clunk" one-shot plus a short RPM dip (9.14 idea).
  - Damaged-engine sputter layer (9.16 idea).
  - Remote tanks: one mid loop with pitch. Silent beyond 300 m and **never for unspotted tanks**, because the server must not reveal them.
- **Tracks:** a speed-scaled loop (volume ∝ speed, pitch 0.9–1.15). The surface is picked from the `Enum.Material` under the hull and maps to groups: soft (Grass, LeafyGrass, Ground), mud, sand (Sand, Sandstone), hard (Concrete, Asphalt, Pavement, Cobblestone, Brick, Slate, Rock, Basalt), snow and ice, water. Crossfade 0.3 s.
- **Turret traverse:** start / loop / stop with volume ∝ traverse rate. Own tank always; other tanks within 50 m (OUR DESIGN).
- **Shell flyby:** for enemy shells whose closest approach to the listener's hull is < 15 m and that miss. Plays a whoosh at the closest-approach point, with a ±8 % `PlaybackSpeed` sweep that imitates Doppler. Cap 3.
- **Impacts (own shots):**
  - penetration: torn-metal crunch
  - non-penetration: dull heavy clang
  - ricochet: whine plus spark
  - module critical: "tick" plus a mechanical break
  - kill: secondary explosion
  
  Each is designed so the **spectral shape differs**, recognisable without VO.
- **Received hits:** three tiers by % of max HP, **≤ 10 / > 10–30 / > 30 %**, aligned with the visual indicator tiers (boundaries corrected by fact-check to match B2). This is deliberately not WoT's 9.16 audio split of 0–17 / 18–35 / 35 %+. Blocked hit: a separate "clang inside" sound. Ricochet received: an inside whine.
- **Reload:** own gun "loaded" clack. Autoloader: per-shell click, "last shell" double-click, "clip empty" cue (9.16 pattern). "Cannot fire" dry click when the gun is destroyed or reloading.

**C6. Crew callouts (VO)**
- One voice, priority queue of 3, TTL 1.5 s, per-line cooldown 3 s. P0 interrupts.
- **Priorities:**
  - **P0:** fire, ammo rack damaged, crew member KO, engine destroyed, low HP (< 25 %, once).
  - **P1:** own-shot result (pen, no pen, ricochet, crit, kill).
  - **P2:** first spotting of an enemy, track broken.
  - **P3:** reload ready (heavy guns only), module repaired.
- **Lines are original HULLDOWN copy** (for example "Through!", "No pen!", "Bounced!", "Module hit!", "Target down!", "We're burning!"). Text must state the outcome exactly (see the "Critical hit" ambiguity in item 23).
- **Captions** mirror each line with a role icon.
- **Prototyping:** `AudioTextToSpeech` (300-character limit; `VoiceId` "1"–"11" for English, and the property is typed `string`, per fact-check) can generate placeholder lines. Final lines are recorded or pre-baked, uploaded as assets, and played as normal `AudioPlayer` voices so runtime latency stays predictable.

**C7. Music state machine (inspired by WoT 1.0 dynamic music)**
- **States:** `GARAGE` → `LOADING` (per-biome intro) → `PREBATTLE` (build-up; downbeat at "GO" via `atTime`) → `EARLY` → `COMBAT` (vertical layers driven by intensity = shots within 150 m in the last 10 s) → `ENDGAME_WIN | ENDGAME_LOSE | ENDGAME_EVEN` → `RESULTS_VICTORY | RESULTS_DEFEAT | RESULTS_DRAW`.
- **Endgame trigger:** alive vehicles ≤ 6 total, **or** time left ≤ 120 s, **or** |team-HP share difference| ≥ 0.4. Win variant if our HP share ≥ 0.55, lose if ≤ 0.45, otherwise even.
- **On own death:** music −6 dB plus low-pass at 2 kHz while spectating.
- **Transitions** quantised to the bar using `GetMixerTime()` and the track's BPM metadata, with a 2-bar crossfade.
- Battle music bus default **−12 dB**. Music is the first thing players turn off, so it must never mask cues.

**C8. Network and authority**
- The server sends compact **audio-relevant events**: shot (shooter id, calibre class, muzzle position if visible to the receiver), hit result (for the shooter and the target), spotted state, module and crew damage. Clients synthesise everything.
- **Never** send audio events that would reveal unspotted positions. Sounds from unspotted shooters are a gameplay decision for the spotting and visibility doc (see Open questions).
- No `AudioPlayer:Play()` from the server for SFX. It replicates server → client and would bypass the client voice manager.

**C9. Asset pipeline and loudness**
- One-shots: **mono** 48 kHz WAV or FLAC source, uploaded as OGG (smaller) once quality is checked. Loops: seamless, with `LoopRegion` where needed. Music: stereo.
- **Loudness targets (pre-fader, OUR DESIGN):** SFX peak −1 dBFS; VO −16 LUFS-I with peaks ≤ −1 dBTP; music −18 LUFS-I.
- **Upload budget:** at about 600 SFX and 40 music files at launch, ID verification is required (2,000 per 30 days). Batch through the Open Cloud `assets/v1` endpoint in CI. Keep an `AudioManifest` module mapping logical names to asset ids and variants.

### D. Module and file suggestions for Phase E

- `Client/Audio/AudioMixer.luau`: builds the graph, bus faders, presets, sliders.
- `Client/Audio/VoicePool.luau`: slot pool, stealing, caps.
- `Client/Audio/WeaponAudio.luau`, `VehicleAudio.luau`, `ImpactAudio.luau`, `CrewVoice.luau`, `MusicDirector.luau`.
- `Shared/Audio/AudioManifest.luau`: asset ids, variants, calibre classes, BPM metadata.
- `Client/UI/Theme/Tokens.luau` plus a `StyleSheet` builder: the tokens above, themes Default and ColorblindRG / ColorblindBY, layout queries Compact / Regular / TV.
- `Client/UI/Hud/*`: one module per HUD element in table B2. Each reads only the replicated battle state.

---

## Open questions / uncertain items

1. **Pre-battle countdown length in WoT Random Battles.** We believe it is 30 s but did not verify it. We chose 20 s regardless.
2. **What "Spotlight" (2.4) shows.** Only its existence and its adaptive timing (Tier V+, Random Battles) are confirmed.
3. **WoT 2.0 Battle-button placement and the minimap size steps.** Neither was verified. Our layout does not depend on them.
4. **Whether WoT captions crew voice lines, and whether it has any low-HP audio warning.** We found no evidence either way. We add both, with options to turn them off.
5. **Dates of 9.16 (late 2016), 1.22.1 (late 2023) and 2.2 (early 2026).** These are approximate. The fact-check found that the decompiled-client repo added its 2.2 Common Test branch on 2026-02-25, which fits "early 2026". The same repo's 2.4 branch is still at the Common Test build (2026-08-29), so the 2.4 live dates (1–2 Sep 2026) remain **unverified**.
6. **Cost of Roblox acoustic simulation per emitter on low-end mobile.** It is undocumented, so we must benchmark it before enabling Tier 1 occlusion widely.
7. **Doppler on `AudioEmitter`.** It is not documented. If the engine adds it, we can drop the manual flyby pitch sweep.
8. **Whether a single `AudioEmitter` can belong to several interaction groups.** The docs describe one string. We assume one group per emitter (one bus per emitter).
9. **Should the reticle show a numeric penetration-chance percentage?** WoT 2.2 shows it only in the Armor Inspector tooltip. This is a gameplay-balance decision for the combat doc.
10. **How to handle shots from unspotted enemies.** Options: no audio, a fuzzed position, or a direction-only cue. The spotting and visibility doc owns this, and it affects the sound-visualisation accessibility feature.
11. **XAG numbering and exact pixel minimums.** These need checking against the Microsoft site from an environment without the egress block.
12. **Interaction between Builder font licence and off-platform marketing.** Legal should confirm that "digital promotions incorporating such UGC" covers store-page screenshots and trailers. The text implies yes.

---

### Local Roblox doc paths used

Paths are under `/tmp/claude-0/-home-user-cheesertw/3147a7aa-8d79-5f7c-921b-d6e4443e2034/scratchpad/refs/creator-docs/content/en-us/`.

- **Audio guides:** `audio/index.md`, `audio/objects.md`, `audio/effects.md`, `audio/assets.md`, `sound/groups.md`, `sound/dynamic-effects.md`, `tutorials/use-case-tutorials/audio/add-3D-audio.md`, `resources/beyond-the-dark/sound-design.md`.
- **Audio class references:** `reference/engine/classes/{AudioPlayer, AudioEmitter, AudioListener, AudioFilter, AudioCompressor, AudioFader, AudioEqualizer, AudioReverb, AudioLimiter, AudioGate, AudioEcho, AudioPitchShifter, AudioAnalyzer, AudioChannelMixer, AudioDeviceOutput, Wire, SoundService, Sound, SoundGroup}.yaml`.
- **Audio enums:** `reference/engine/enums/{DistanceAttenuationMode, AudioFilterType, ListenerLocation, EmitterPositionType, AudioSimulationFidelity, AudioChannelLayout, RollOffMode, ReverbType}.yaml`; `reference/engine/datatypes/PhysicalProperties.yaml`.
- **Fonts and UI classes:** `reference/engine/enums/Font.yaml`, `reference/engine/datatypes/Font.yaml`, `resources/builder-font-license.md`, `reference/engine/classes/{GuiService, ScreenGui, StyleQuery, WorldModel, Highlight, BillboardGui}.yaml`, `reference/engine/enums/{ScreenInsets, PreferredTextSize, PreferredInput, DisplaySize, GuiState}.yaml`.
- **UI guides:** `ui/styling/index.md`, `ui/styling/css-comparisons.md`, `ui/viewport-frames.md`.
- **Publishing and performance guidelines:** `production/publishing/accessibility.md`, `production/publishing/adaptive-design.md`, `production/publishing/console-guidelines.md`, `performance-optimization/{microprofiler/tag-table.md, scene-analysis.md, improve.md, test-on-hardware.md}`.
- **Chat:** `chat/chat-window.md`.

---

## Verification log

The adversarial fact-check ran on 2026-10-05. Each claim was treated as wrong until a source confirmed it.

**Method:**
- **Roblox claims** were checked by grepping the local creator-docs clone (commit `9f840b17`, 2026-10-02). Paths below are relative to `/tmp/claude-0/-home-user-cheesertw/3147a7aa-8d79-5f7c-921b-d6e4443e2034/scratchpad/refs/creator-docs/content/en-us/`.
- **WoT web pages could not be used.** The web-search budget was exhausted, and the egress proxy blocks WoT/WG, fandom, idcgames and hardcoregamer.
- **WoT claims** were therefore checked against the community-decompiled WoT client scripts on GitHub ([StranikS-Scan/WorldOfTanks-Decompiled](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled)), one branch per game version. This is a data-mined mirror, not an official Wargaming source.
- **Colour maths** was recomputed locally: WCAG 2.x relative luminance, and CIELAB ΔE76 after Machado-2009 simulation at 100 % severity via `colorspacious`.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | WoT penetration indicator: yellow = armour within ±25 % of penetration; it ignores impact angle | **Corrected** | The current indicator is angle-aware. It applies normalisation, the ricochet and 3-calibre rule, spaced layers and HEAT jet loss. Yellow is 87.5–112.5 % of penetration (±12.5 %), green ≤ 87.5 %, red ≥ 112.5 % or a ricochet. Evidence: [gun_marker_ctrl.py @2.4_EU](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/2.4_EU/source/res/scripts/client/AvatarInputHandler/gun_marker_ctrl.py) (`_IS_EXTENDED_GUN_MARKER_ENABLED = True`, `_CrosshairShotResults._computePenetrationArmor`, `_shouldRicochet`, `_PP_RANDOM_ADJUSTMENT_MIN/MAX = 0.5`); [component_constants.py @2.4_EU](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/2.4_EU/source/res/scripts/common/items/components/component_constants.py) (`DEFAULT_PIERCING_POWER_RANDOMIZATION = 0.25`). The same flag is already `True` in [1.0.0](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/1.0.0/source/res/scripts/client/AvatarInputHandler/gun_marker_ctrl.py). Consistent with ±25 % RNG in `01-ballistics-armor-damage.md`. |
| 2 | Hit-direction widths 1–10 / 11–30 / 30 %+ of max HP; vehicle comparison up to 20 vehicles | Confirmed | [indicators.py @2.4_EU](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/2.4_EU/source/res/scripts/client/gui/Scaleform/daapi/view/battle/shared/indicators.py) sets `_MARKER_SMALL_SIZE_THRESHOLD = 0.1` and `_MARKER_LARGE_SIZE_THRESHOLD = 0.3`, with damage ÷ `getPlayerVehicleMaxHP()`. [veh_comparison_basket.py @2.4_EU](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/2.4_EU/source/res/scripts/client/gui/game_control/veh_comparison_basket.py) sets `MAX_VEHICLES_TO_COMPARE_COUNT = 20`. The B2/C5 tier boundaries were aligned to `<=`. |
| 3 | Team total-HP counter first-party in 1.12; WoT 2.0 released 3 Sep 2025 | Confirmed | The classic `frag_correlation_bar.py` has no HP code in [1.11.1](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/1.11.1/source/res/scripts/client/gui/Scaleform/daapi/view/battle/classic/frag_correlation_bar.py). It gains `SHOW_HP_BAR`, `SHOW_HP_VALUES` and `updateTeamHealth` in [1.12](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/1.12/source/res/scripts/client/gui/Scaleform/daapi/view/battle/shared/frag_correlation_bar.py). One nuance: 1.11.1 already had a percentage team-health bar, but it was limited to some modes by `BONUS_CAPS.TEAM_HEALTH_BAR` (`avatar_components/team_healthbar_mechanic.py`). The mirror's `2.0_EU` branch has the commit "2.0.0.0: Release" dated 2025-09-03. |
| 4 | 9.14 replaced FMOD with Wwise (10 Mar 2016) | Confirmed (engine switch); day-date not re-verified | `SoundGroups.py` imports `FMOD` in [0.9.13](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/0.9.13/source/res/scripts/client/SoundGroups.py) and `WWISE` in [0.9.14](https://github.com/StranikS-Scan/WorldOfTanks-Decompiled/blob/0.9.14/source/res/scripts/client/SoundGroups.py). The date rests on the HardcoreGamer URL (`/2016/03/10/`), which could not be fetched because egress is blocked. |
| 5 | Sixth Sense lamp delayed 3 s; 2.4 "Overdrive" live 1–2 Sep 2026 | **Unverified** | The 3 s delay is server-side and not in the client scripts. It agrees with fact-checked `02-spotting-camouflage.md`. The mirror's 2.4 branch holds only a Common Test build (2026-08-29). The 2.4 date confidence was downgraded to Medium in Summary 10 and item 22. |
| 6 | `Sound`/`SoundGroup`/`SoundEffect` are "now discouraged"; `Play(atTime)`/`Stop(atTime)` schedule against `SoundService:GetMixerTime()` and return an id for `Cancel` | Confirmed | `audio/objects.md` line 18; `reference/engine/classes/AudioPlayer.yaml` (`AudioPlayer:Play`, `:Stop`, `:Cancel`, "sample-accurate"); `reference/engine/classes/SoundService.yaml` (`SoundService:GetMixerTime`). |
| 7 | `AudioFilter`: 12 types including Lowpass6/12/24/48dB and Highpass12/24/48dB; `Frequency` 20–22000, `Gain` −30..30, `Q` 0.1–10 | Confirmed | `reference/engine/enums/AudioFilterType.yaml` (12 items, with no Highpass6dB); `reference/engine/classes/AudioFilter.yaml`. |
| 8 | `AudioEmitter` curves ≤ 400 points, empty curve = inverse-square, `DistanceAttenuationBounds` default [4, 10000]; `AudioListener` has the "same attenuation API" | **Corrected** (listener part) | The emitter facts are confirmed in `reference/engine/classes/AudioEmitter.yaml` (`SetDistanceAttenuation`, `SetAngleAttenuation`, `DistanceAttenuationBounds`). `AudioListener.yaml` has no `DistanceAttenuationMode` or `DistanceAttenuationBounds`, and its position enum is `ListenerPositionType`. |
| 9 | `AudioCompressor` Threshold −60..0 dB, Ratio 1–50, Attack 0.0001–0.5 s, Release 0.01–5 s, Sidechain pin ducks; `AudioLimiter.MaxLevel` −12..0; `AudioFader.Volume` 0–3 | Confirmed | `reference/engine/classes/AudioCompressor.yaml`, `AudioLimiter.yaml`, `AudioFader.yaml`. Every C1 ducking, glue, limiter and Night-mode value lies within these ranges. |
| 10 | Acoustic simulation needs emitter, listener **and** `SoundService.AcousticSimulationEnabled`; server audio processing disabled; no documented Doppler or voice cap for the new API; `DistanceFactor` = 3.33 | Confirmed | `AudioEmitter.yaml` (`AcousticSimulationEnabled`), `SoundService.yaml` (`AcousticSimulationEnabled`, and `DistanceFactor`, which "does not impact" `AudioPlayer`/`AudioEmitter`), `AudioAnalyzer.yaml` line 14. A grep finds "doppler" only in the `Sound`/`SoundService`/`VideoFrame` and `scripting/services.md` docs. C3 and C4 were clarified. C4 had named a single listener despite C1's four listeners. |
| 11 | Audio upload: mp3/ogg/wav/flac, < 20 MB, < 7 min, ≤ 48 kHz, mono/stereo/3.0/5.1; 2,000 (ID-verified) or 100 per 30 days; Open Cloud `assets/v1`; TTS 300 chars, VoiceId 1–11 English | Confirmed | `audio/assets.md` lines 34–39 and 89; `reference/engine/classes/AudioTextToSpeech.yaml` (300 chars; `VoiceId` typed `string`); `audio/objects.md` voice table. |
| 12 | `TextScaled` **and** `UITextSizeConstraint` text ignore `PreferredTextSize` | **Corrected** | `production/publishing/accessibility.md` "Preferred text size": the constraint **clamps** text to Min/MaxTextSize, while `TextScaled` text is not scaled. Item 21 and the A3 rule were fixed. |
| 13 | A1: Compact layout triggered by `DisplaySize.Small`, while Regular covers tablets | **Corrected** (internal contradiction) | `reference/engine/enums/DisplaySize.yaml` and `GuiService.yaml` (`ViewportDisplaySize`): Small = "most tablet/mobile/handheld devices". Compact is now height-based. |
| 14 | Colour-token WCAG ratios and CVD ΔE values; "all text tokens ≥ 4.5:1" | Confirmed numbers; **Corrected** one token | All 15 listed ratios and all ΔE figures reproduce exactly. Examples: ally/enemy 112/93/68/129; pen protan minimum 20.2; cb-preset deutan minimum 34.4; ok/crit deutan 18.4. `state.destroyed` #7D8790 is 4.09:1 on `surface.2`, which contradicts the 4.5:1 rule for dead-player names, so it was changed to #87919A (5.82 / 4.66). |
| 15 | UI platform: `GuiState` Idle/Hover/Press/NonInteractable; `ScreenInsets` None/DeviceSafe/CoreUISafe/TopbarSafe; Gotham removed → Montserrat; Builder Sans/Extended/Mono; `Highlight` max 255 on the client; `StyleQuery` MinSize/MaxSize/PreferredInput | Confirmed | `reference/engine/enums/{GuiState,ScreenInsets,Font,PreferredTextSize,PreferredInput}.yaml`; `reference/engine/datatypes/Font.yaml`; `reference/engine/classes/{Highlight,StyleQuery,GuiService}.yaml`; `effects/highlighting.md`. The docs disagree on `PreferredInput` vs `PreferredInputType` (`ui/styling/compatibility.md`); this is noted in item 29. |

**Totals:** 15 claims checked. 9 confirmed, 5 corrected, 1 unverified.

**Fixes made in the implementation recommendations for internal contradictions:**
- A1: Compact selection by `DisplaySize`.
- A4 and Summary 15: `state.destroyed` contrast.
- A3: `UITextSizeConstraint` rationale.
- B2: the reticle logic note, and the hit-tier boundaries; C5 tier boundaries aligned with B2.
- C2/C3: each distance layer and tail counts as a voice.
- C3: `DistanceFactor` scope.
- C4: acoustic simulation must be enabled on each category listener.
