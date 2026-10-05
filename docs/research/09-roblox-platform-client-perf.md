# 09 — Roblox Platform Research for HULLDOWN: Client, Rendering, UI, Input, Camera, Audio, Performance and Luau

> **Date:** 2026-10-05.
> **Primary source:** the Roblox creator-docs snapshot at commit `9f840b1` (2026-10-02), API reference generated for
> Studio `0.741.19.7411056` (`CD/reference/engine/STUDIO_VERSION`).
> **Path convention:** `CD/<path>` = `creator-docs/content/en-us/<path>` in that snapshot. A guide `CD/x/y.md` is published at
> `https://create.roblox.com/docs/x/y`. An API page `CD/reference/engine/classes/Foo.yaml` is published at
> `https://create.roblox.com/docs/reference/engine/classes/Foo`.
> **History method:** "History" dates in this report come from `git log -S/-G` over the creator-docs repository
> (history deepened to 2,167 commits, back to the 2023-08-29 open-source import). They give **the date the docs first
> described a feature**. That is a proxy for release, not a release date: betas are often documented later or earlier.
> Dates of `2023-11-02` usually mean "already documented when that reference folder entered the repo".
> **Other evidence:**
> - Luau RFCs fetched from `raw.githubusercontent.com/luau-lang/rfcs/master/docs/*.md`.
> - Roblox client content-folder listing from a depth-1 clone of `github.com/MaximumADHD/Roblox-Client-Tracker`
>   (branch `roblox`, commit `fcd6994`, client `0.741.19.7411056`, 2026-09-29). This is the Roblox client's own file
>   list (it is **not** a WoT datamine), used only to enumerate built-in `rbxasset://` textures.
> - Library tags via `git ls-remote` (Fusion, Vide, react-lua, Roact).
> - **The session-wide WebSearch budget (200 calls) was exhausted before this report started**, and DevForum and
>   create.roblox.com are proxy-blocked. Claims not backed by the sources above are marked **[prior knowledge, not
>   re-verified]**.
> **Fact-check:** adversarially re-verified on 2026-10-05 against the same local snapshot, git history of the
> creator-docs repo, Luau RFCs and the client-tracker file list. Corrections are marked "(corrected by fact-check)";
> see "## Verification log" at the end.
> **Confidence scale:**
> - **High**: stated verbatim in the current docs or spec.
> - **Medium**: inferred from docs, or from well-established community practice.
> - **Low**: prior knowledge that could not be re-checked.
> **HULLDOWN context (`docs/ARCHITECTURE.md`):**
> - Vehicles are **not** Roblox physics assemblies. The server runs a custom 30 Hz simulation and replicates per
>   observer.
> - Clients build vehicle models from a shared **Blueprint** with LOD tiers, and interpolate remote vehicles 100 ms behind.
> - UI is code-built with an in-house `UI/Kit`.
> - String requires (`@game/...`, `./`, `@self/`) and `--!strict` everywhere.
> - `Units.STUDS_PER_METER = 3`.
> - Sibling reports:
>   - `06-ui-ux-audio.md` covers UI style and the audio mix in depth.
>   - `08-roblox-platform-backend.md` covers networking and persistence.
>
> This report does not repeat those; it cross-references them.

---

## Summary

1. **String requires work in live games, as our architecture assumes.**
   - `require("./X")` resolves from `script.Parent`, `../` from `script.Parent.Parent`, `@self/` from `script`, and
     `@game/` from `game`. Resolution is **non-blocking**: it errors if the target does not exist yet.
   - The old `Init`/`init` child fallback was removed from the docs on 2025-05-19. Rojo's `init.luau` → ModuleScript
     mapping is therefore required.
   - `@game/` was documented on 2026-01-13.
   - `require()` is **forbidden in a desynchronized (parallel) phase**.
2. **Type system.**
   - `--!strict`, `--!nonstrict` and `--!nocheck` are the documented modes.
   - The new type solver is a place setting, `Workspace.UseNewLuauTypeSolver` (a `RolloutState`, documented 2025-06-11).
   - User-defined `type function`s exist (RFC status "Implemented") but need the new solver.
   - **Do not use type functions in shipped code** until Studio, luau-lsp and Lune all agree.
3. **Native code generation is documented for server scripts only** (guide re-edited 2026-07-07, still "server-side").
   - Enable it with `--!native` per script or `@native` per function.
   - Hard limits: 64K instructions per block, 32K blocks per function, 1M instructions per module, plus a global
     memory cap. `debug.dumpcodesize()` reports usage.
   - Use it on server hot math only: ballistics, armor geometry, spotting, the heightfield sampler.
4. **Parallel Luau.**
   - `WorldRoot:Raycast`, `Spherecast`, `Blockcast`, `GetPartBoundsInBox/InRadius` and `GetPartsInPart` are
     **Safe** in parallel. `Shapecast` is **Unsafe**.
   - The tools are Actors, `task.desynchronize()`/`task.synchronize()`, `ConnectParallel`, `Actor:SendMessage` /
     `BindToMessageParallel` and `SharedTable`.
   - The docs recommend "64 Actors and more" for raycast-validation-style work.
   - Our plan: start serial, and move spotting line-of-sight (LOS) batches into ~16 Actors **only if** the
     MicroProfiler shows more than 2 ms per tick.
5. **`buffer` and `vector`.**
   - A `buffer` is at most **1 GiB**, little-endian, and has `readbits`/`writebits` (documented 2025-03-31). It is
     copied when sent through remotes and cannot be shared across Actors.
   - The `vector` library was documented 2025-01-13. On Roblox, `vector` values are `Vector3`s **[Medium]**.
6. **UI primitives.**
   - Layout: `UIListLayout` flex (`HorizontalFlex`, `VerticalFlex`, `Wraps`, `ItemLineAlignment`) plus `UIFlexItem`
     (`FlexMode`, `GrowRatio`, `ShrinkRatio`), `UIGridLayout`, `UIPageLayout`, `AutomaticSize`.
   - The engine's **UI styling system** (`StyleSheet`, `StyleRule`, `StyleDerive`, `StyleLink`; `StyleQuery` documented
     2026-03-05, built-in queries 2026-04-07) ships built-in queries: `@PreferredInputTouch/Gamepad/KeyboardAndMouse`,
     `@ViewportDisplaySizeSmall/Medium/Large` and `@ReducedMotionEnabledTrue/False`.
   - **Beta caveats:** per-corner `UICorner` radii are **beta**. The new `UIStroke` properties (`BorderOffset`,
     `BorderStrokePosition`, `StrokeSizingMode`, `ZIndex`) "may require" the Improved UIStrokes beta. Do not depend on
     either in live builds.
7. **Safe areas.**
   - `ScreenGui.ScreenInsets` defaults to `CoreUISafeInsets` (recommended for interactive UI). The other values are
     `DeviceSafeInsets`, `TopbarSafeInsets` and `None`.
   - `ClipToDeviceSafeArea` defaults to `true`.
   - `SafeAreaCompatibility` defaults to `FullscreenExtension`; the docs advise against it for new work, so set it to
     `None`.
   - `IgnoreGuiInset=true` switches `CoreUISafeInsets` to `DeviceSafeInsets`.
8. **`Highlight`.**
   - The client renders **at most 255 simultaneous Highlights** (raised from 31; class reference updated 2025-11-17,
     guide on 2026-04-03).
   - The first visible Highlight costs "up to 1 ms of GPU time on mobile". Adding or removing one triggers a geometry
     rebuild, while changing its properties is cheap.
9. **Input.**
   - The **Input Action System** (`InputContext` → `InputAction` → `InputBinding`, guide published without a beta
     flag 2025-08-06) is now the documented cross-platform path.
   - `UserInputService.PreferredInput` (`KeyboardAndMouse`, `Gamepad`, `Touch`, `MicroGamepad`; documented 2025-06-02)
     replaces `LastInputType` heuristics.
   - `InputActionLabel` (automatic glyphs) is **beta**.
   - `ContextActionService` creates at most **7** touch buttons.
   - `Esc`/`ButtonStart` (Roblox menu), `F9`, `F11`, `F12` and `PrintScreen` are reserved and cannot be overridden
     (`CD/includes/default-bindings.md`; added by fact-check, §3.3a).
   - `HapticEffect` (types `UIHover`, `UIClick`, `UINotification`, `GameplayExplosion`, `GameplayCollision`, `Custom`)
     covers Xbox and PlayStation pads and haptic phones.
10. **Camera.**
    - `FieldOfView` is vertical, clamped to **1–120°**, default **70°**. Zoom levels ×2, ×4, ×8, ×16 and ×25 map to
      38.59°, 19.86°, 10.0°, 5.01° and 3.21°.
    - Use `CameraType.Scriptable` and `BindToRenderStep` at `Enum.RenderPriority.Camera.Value + 1` (201, as in
      R6.1; `Camera` itself is 200) (corrected by fact-check: aligned with R6.1).
    - Camera collision via `Spherecast`: radius ≤ **256** studs, distance ≤ **1,024** studs. Rays are capped at
      **15,000** studs.
11. **Rendering facts.**
    - The docs' example device budget is "below **1,000 draw calls** and **1,000,000 triangles**".
    - Instancing collapses identical `MeshContent` with identical `SurfaceAppearance`, texture or material into one
      draw call. Decals, Textures and particles batch poorly.
    - Shadows are disabled at graphics quality **below 4**.
    - `MeshPart.RenderFidelity=Automatic` switches detail at **250** and **500 studs**.
    - **SLIM** model LOD needs `StreamingEnabled`, a cloud-published place and **static** models. **It cannot be used
      for our runtime-built tanks.**
    - `Lighting.Technology` is deprecated in favour of `LightingStyle` (`Realistic`/`Soft`) plus
      `PrioritizeLightingQuality`.
12. **Effects limits.**
    - `ParticleEmitter`: ≤ **400 particles/s per emitter (100/s on mobile)**, `Lifetime` capped at **20 s**,
      flipbook ≤ **30 fps**.
    - `Trail.Lifetime` is 0.01–20 s. `Beam.Segments` defaults to 10.
    - "Property changes to ParticleEmitters can have a dramatic impact on performance".
    - Built-in particle textures exist at `rbxasset://textures/particles/*` (fire, smoke, sparkles, explosion01_*,
      forcefield_*, `SquareParticle.png`). They need no upload.
13. **EditableImage and EditableMesh are restricted.**
    - In published games, the owner must be **13+ and ID-verified** and enable the dashboard toggle.
    - Images are at most 1024×1024. Meshes are capped at 60,000 vertices and 20,000 triangles.
    - Client memory budgets are strict, and only one displayed EditableImage updates per frame.
    - **Not part of the baseline.**
14. **Audio.**
    - `Sound`, `SoundGroup` and `SoundEffect` are "now discouraged" (docs 2025-05-22). Use `AudioPlayer` →
      `AudioEmitter` … `AudioListener` → `AudioDeviceOutput` via `Wire`s.
    - The docs state **no polyphony cap**, so we need our own voice manager. One `AudioPlayer` is one playhead, so pool
      players for overlapping one-shots.
    - Upload limits: < 20 MB, < 7 min, ≤ 48 kHz. The audio guide's quota is 2,000 per 30 days (ID-verified) or 100
      (unverified); it was raised from 100/10 on 2026-03-17 and lists Open Cloud as an import channel. The Open Cloud
      guide's "100 per month (verified), 10 (unverified)" is the **pre-raise figure** (that text dates from 2025-02-28)
      (corrected by fact-check). **Upload from an ID-verified account**, and budget the Open Cloud pipeline at 100 per
      month until a real upload run shows the higher quota applies.
15. **Device reality** (`CD/performance-optimization/*`).
    - Android is ~65% of a typical player base, and ~60% of those devices have **2–4 GB RAM**.
    - More than 50% of players are on devices scoring 10,000–20,000 on Passmark.
    - The client is capped at 60 FPS by default (up to 240 on Windows). Server heartbeat is capped at 60 Hz.
    - Server memory is `6.25 GiB + 100 MiB × peak players`, which is 9.18 GiB for 30 players. Stay below 50%.
    - Investigate client crash rates above 2–3%.
16. **Character-less games.**
    - With `Players.CharacterAutoLoads=false`, StarterGui is **not cloned** until `LoadCharacterAsync`. We build UI in
      code anyway.
    - Streaming focuses on the character's `PrimaryPart`, so set `Player.ReplicationFocus` (server-only) if streaming is
      on.
    - Put the audio listener on the camera.
    - Disable default controls: `GuiService.TouchControlsEnabled`, `DevTouchMovementMode=Scriptable`, or remove the
      PlayerModule.
    - Show chat bubbles with `TextChatService:DisplayBubble(part, msg)` (client-only).
17. **Frustum streaming** (`Player.FrustumStreaming` = `Automatic`, documented 2026-10-01) streams instances in the
    camera frustum when the field of view narrows (scopes). It only matters if the Battle place uses instance
    streaming. **Default decision:** the Battle place runs with `StreamingEnabled=false` behind a memory gate (§R7).
18. **Budgets (OUR DESIGN CHOICE).** See §R11 for the full table.
    - Baseline Android: ≤ 1,000 draw calls and ≤ 1M triangles. PC high: ≤ 2,500 draw calls.
    - Visible tank parts ≤ 3,000 in total, with LOD0 (≤ 400 parts) limited to the 4 nearest tanks. Mobile: ≤ 1,500,
      with LOD0 ≤ 2 and LOD1 ≤ 3 (corrected by fact-check, R8.4).
    - Live particles ≤ 600 on mobile and ≤ 2,000 on PC.
    - Concurrent voices ≤ 20 on mobile and ≤ 32 on PC.
    - Server simulation ≤ 6 ms average per 30 Hz tick, with ≤ 600 world queries per tick.

---

## Detailed findings

### 1. Luau language and runtime on Roblox

#### 1.1 Require-by-string semantics

**Current behavior** (`CD/reference/engine/globals/LuaGlobals.yaml`, `require`):
- `require(module: ModuleScript | string | number)`. A string is "resolved to a ModuleScript relative to the script that
  called `require()`, mimicking the Unix-like semantics of Luau's `require()` expression".
- Prefixes:
  - `./` begins resolution at `script.Parent`.
  - `../` begins at `script.Parent.Parent`.
  - `@self/` begins at `script`.
  - `@game/` begins at `game`.
- Every later path component is a **child** (`FindFirstChild`-like) of the previous one. `..` means the parent.
- **Non-blocking**: "If the desired ModuleScript is not present at the time that require() is called, the call will fail
  and throw an error … it does not implicitly wait."
- Caching:
  - A module runs once per side (client and server have separate caches).
  - Later requires return the same reference.
  - A circular require throws "Requested module was required recursively" (`CD/scripting/module.md`).
- Requiring by asset ID (`MainModule`) works on the server only.
- Parallel Luau: "You can't use `require()` in a desynchronized parallel phase. Require scripts you want to use first in a
  serial context" (`CD/scripting/multithreading.md`).

**Consequences for HULLDOWN:**
- ARCHITECTURE §3.2 is valid on Roblox: `@game/ReplicatedStorage/...`, `./Sibling`, and `@self/Child` inside an
  `init.luau` module.
- Inside `Folder/init.luau` (a ModuleScript named `Folder`), `./X` is a sibling of `Folder`. This matches the docs.
- Because requires do not wait, client code must only require after replication. `ClientBootstrap` already waits for
  `game.Loaded`.
- `@game/ServerScriptService/...` cannot resolve on clients, because that container is not replicated.
- Arbitrary `.luaurc` aliases are **not** documented as supported on Roblox. Only `@self` and `@game` are. Our `.luaurc`
  `game -> ./src` alias is tooling-only and mirrors Roblox's built-in `@game`.

**History:**
- 2025-01-22: string paths first documented, `./` and `../` only, with an `Init`/`init` child fallback.
- 2025-05-19: rewritten. `@self/` added, the Init fallback removed, `..` components defined.
- 2026-01-13: `@game/` documented.

**Confidence:** High.
**Sources:**
- `CD/reference/engine/globals/LuaGlobals.yaml`
- `CD/scripting/module.md`
- `CD/scripting/multithreading.md`
- Luau RFC `new-require-by-string-semantics.md` (raw.githubusercontent.com/luau-lang/rfcs)

#### 1.2 Type system

**Current behavior:**
- Modes (`CD/luau/type-checking.md`):
  - `--!nocheck`;
  - `--!nonstrict` (only explicit annotations are asserted; unannotated values are `any`);
  - `--!strict` (all inferred and annotated types are asserted).
- Supported features: literal types, casts (`::`), function types, table types, variadics, unions and intersections,
  `typeof(...)` types, generics, `export type`.
- `Workspace.LuauTypeCheckMode` sets the default mode.
- **`Workspace.UseNewLuauTypeSolver`** (`RolloutState`, NotScriptable) selects the new solver. `Default` "follows the
  current engine-wide rollout state".
- User-defined **type functions** (`type function f(...) ... end`) are "Implemented" per the Luau RFC, which states they
  are a feature of "the new Luau type inference engine".
- The local Roblox guide does not document type functions at all.
- Native codegen *reads* parameter annotations ("Luau type annotations on function arguments are checked"). The docs
  single out `Vector3`: annotate those parameters to get vector-specialized code (`CD/luau/native-code-gen.md`). No other
  datatype (for example `CFrame`) is named as getting specialized code.

**History:** `UseNewLuauTypeSolver` documented 2025-06-11.
**Confidence:**
- High for modes and the property.
- Medium for type-function availability in Studio. It depends on the solver rollout state, which the docs do not state.

**Sources:**
- `CD/luau/type-checking.md`
- `CD/reference/engine/classes/Workspace.yaml` (`UseNewLuauTypeSolver`)
- RFC `user-defined-type-functions.md`

#### 1.3 `buffer` and `vector` libraries; `task` library

**`buffer`** (`CD/reference/engine/libraries/buffer.yaml`):
- A fixed-size mutable byte block. `buffer.create(size)` takes sizes up to **1 GiB (1,073,741,824 bytes)**.
- Functions:
  - integer read/write: `readi8/u8/i16/u16/i32/u32`;
  - float read/write: `readf32/f64`;
  - `readstring`/`writestring`, `readbits`/`writebits`;
  - `copy`, `fill`, `len`, `fromstring`, `tostring`.
- Encoding is **little-endian**. Out-of-range access throws.
- "When passed through Roblox APIs, including … custom events, the identity of the buffer object is not preserved and the
  target will receive a copy … the same buffer object cannot be used from multiple Actor scripts."

**`vector`** (`CD/reference/engine/libraries/vector.yaml`):
- Members: `zero`, `one`, `create(x,y,z?)` (z defaults to 0), `magnitude`, `normalize`, `cross`, `dot`, `angle`,
  `floor`, `ceil`, `abs`, `sign`, `clamp`, `lerp`, `max`, `min`.
- Values are immutable. The `Vector3` page says "Alternatively to `Vector3`, consider using the methods and properties
  of the `vector` library".
- That on Roblox `vector` values *are* `Vector3` values is **[Medium]**: implied by the docs, not stated.

**`task`** (`CD/reference/engine/libraries/task.yaml`, `CD/scripting/scheduler.md`):
- Functions: `spawn`, `defer`, `delay`, `wait`, `cancel`, `desynchronize`, `synchronize`.
- `task.wait()` "does not throttle" and resumes on the first Heartbeat after the duration.
- The legacy `wait`, `spawn` and `delay` are discouraged.

**History:**
- `vector` library documented 2025-01-13.
- `buffer.readbits`/`writebits` documented 2025-03-31.

**Confidence:** High, except the `vector`/`Vector3` identity (Medium).

#### 1.4 Native code generation

**Current behavior** (`CD/luau/native-code-gen.md`):
- "server-side scripts in your game can be compiled directly into the machine code". The text is unchanged in the
  2026-07-07 revision.
- Enable it with `--!native` at the top of a script, or `@native` on a single function.
- Only functions benefit. Top-level code runs once.
- Drawbacks:
  - longer server startup;
  - extra memory;
  - "a limit on the total allowed amount of natively compiled code in a game".
- Things that de-optimize:
  - `getfenv`/`setfenv`;
  - math builtins called with non-numbers;
  - **arguments that mismatch their type annotations**.
- **Limits:**
  - 64K instructions per code block;
  - 32K internal blocks per function;
  - 1M instructions per module ("total module instruction limit");
  - a global memory limit ("Memory allocation limit reached for native code generation").
- `debug.dumpcodesize()` (Command Bar, Server view) prints per-function native size and the percentage of the limit.
- The Script Profiler marks native functions with `<native>`. A breakpoint disables native execution of that function.

**History:** guide edits in 2024-05, 2024-06, 2024-07, 2025-01, 2025-09, 2025-10, 2026-02 and 2026-07. The scope has
always read "server-side".
**Confidence:** High for the server. Unknown for the client: the docs are silent. The directive is a comment, so it is
harmless on the client.

#### 1.5 Parallel Luau

**Current behavior** (`CD/scripting/multithreading.md`, `CD/reference/engine/datatypes/SharedTable.yaml`):
- **Actors.** Scripts under an `Actor` can run in parallel. "Scripts that are part of the same actor always execute
  sequentially with respect to each other", so you need multiple Actors.
- **Phases.** `task.desynchronize()` moves to the parallel phase and `task.synchronize()` returns to serial.
  `RBXScriptSignal:ConnectParallel(fn)` runs the callback in parallel.
- **Thread-safety levels:**
  - Unsafe;
  - Read Parallel;
  - Local Safe (read/write within the same Actor);
  - Safe.
  - Members with no tag default to **Unsafe**.
  - Writing instance properties in parallel is generally blocked.
- **`WorldRoot` safety** (parsed from `WorldRoot.yaml`):
  - **Safe:** `Raycast`, `Spherecast`, `Blockcast`, `GetPartBoundsInBox`, `GetPartBoundsInRadius`, `GetPartsInPart`.
  - **Unsafe:** `Shapecast`, `BulkMoveTo`, `StepPhysics`, collision-group APIs, legacy `FindPartOnRay*`.
- **Communication between Actors:**
  - `Actor:SendMessage(topic, ...)` is asynchronous;
  - `Actor:BindToMessage` / `BindToMessageParallel`;
  - `SharedTable` is atomic, visible to all Actors and clonable with structural sharing. Keys are strings or integers
    < 2³². Values are boolean, number, vector, string, SharedTable or serializable datatypes.
  - `SharedTableRegistry` lets scripts share tables by name.
- **Best practice:**
  - "Avoid long computations" even in parallel.
  - "it's reasonable to use 64 Actors and more instead of just 4, even if you're targeting 4-core systems."
  - WriteVoxels "must be called in the serial phase".

**Confidence:** High.

**HULLDOWN fit:**
- `Shared/*` modules are pure and can be required inside an Actor in the serial phase.
- The `World` adapter's `Raycast`/`Blockcast` are parallel-safe, which suits spotting LOS fan-out.
- Each Actor gets its own module instances. Do not assume module-level state is shared **[Medium; implied by the
  per-Actor buffer restriction]**.

---

### 2. UI

#### 2.1 `ScreenGui` containers and safe areas

**Current behavior** (`CD/reference/engine/classes/ScreenGui.yaml`, `CD/includes/ui/screen-insets.md`,
`CD/ui/on-screen-containers.md`):
- **`ScreenInsets`** (`Enum.ScreenInsets`):
  - `CoreUISafeInsets` (default; "recommended if the ScreenGui contains interactive UI elements");
  - `DeviceSafeInsets` (clear of notches, but not of the top bar);
  - `TopbarSafeInsets` (between the top-bar controls and the right edge, flexing with top-bar content);
  - `None` ("only … non-interactive content like background images").
- **`IgnoreGuiInset`**: setting it to `true` while ScreenInsets is `CoreUISafeInsets` switches ScreenInsets to
  `DeviceSafeInsets`.
- **`ClipToDeviceSafeArea`** defaults to `true` (clips descendants to the device safe area). It is ignored when
  `ScreenInsets=None`.
- **`SafeAreaCompatibility`** defaults to `FullscreenExtension`, which auto-extends "fullscreen" descendants on screens
  with cutouts. The docs: "it's recommended that you avoid fullscreen extensions for new work". So use `None` and
  explicit insets.
- **Ordering and reset:**
  - `DisplayOrder` (int) orders ScreenGuis. `ZIndexBehavior` is per LayerCollector.
  - `ResetOnSpawn` (default `true`) re-clones the gui on character respawn.
  - A disabled ScreenGui (`Enabled=false`) does "not render, process user input, or update".
- **Character-less caveat:** "If `Players.CharacterAutoLoads` is disabled, the contents of StarterGui will not be cloned
  until `Player:LoadCharacterAsync()` is called."
- **`GuiService` helpers:**
  - `GetGuiInset()`;
  - `GetInsetArea(Enum.ScreenInsets)` returns a `Rect` relative to `CoreUISafeInsets`;
  - `TopbarInset` is a `Rect` of the free top-bar area.
- **`GuiService.ViewportDisplaySize`** (`DisplaySize`):
  - `Small`: most phones and tablets;
  - `Medium`: laptops and monitors;
  - `Large`: TVs.

**Console TV-safe area** (`CD/production/publishing/console-guidelines.md`): "some TVs will not show content fully to the
edges … put UI elements in TV‑safe areas". The docs give **no percentage**.

**History:**
- `SafeAreaCompatibility` documented by 2023-11.
- `ViewportDisplaySize` documented 2025-07-10.

**Confidence:** High.

#### 2.2 Layout and sizing primitives

**Current behavior** (class YAMLs under `CD/reference/engine/classes/`, plus `CD/ui/list-flex-layouts.md`,
`CD/ui/size-modifiers.md`):

**`UIListLayout`:**
- `FillDirection`, `Padding` (UDim), `SortOrder`, `HorizontalAlignment` / `VerticalAlignment`.
- **Flex:** `HorizontalFlex` / `VerticalFlex` (`UIFlexAlignment`: `None`, `Fill`, `SpaceAround`, `SpaceBetween`,
  `SpaceEvenly`), `Wraps` (bool), `ItemLineAlignment` (`Automatic`, `Start`, `Center`, `End`, `Stretch`).

**`UIFlexItem`** (child of a list item):
- `FlexMode` (`None`, `Grow`, `Shrink`, `Fill`, `Custom`).
- `GrowRatio` and `ShrinkRatio` (used with `Custom`).
- `ItemLineAlignment`.

**`UIGridLayout`:**
- `CellSize` and `CellPadding` (UDim2), `FillDirectionMaxCells`, `StartCorner`.
- Read-only `AbsoluteCellSize` and `AbsoluteCellCount`.

**`UIPageLayout`:**
- Properties: `Animated`, `Circular`, `EasingStyle` / `EasingDirection`, `TweenTime`, `Padding`, and
  **`GamepadInputEnabled`** (overrides `NextSelection*`; default true), `ScrollWheelInputEnabled`, `TouchInputEnabled`.
- Methods: `JumpTo`, `JumpToIndex`, `Next`, `Previous`.
- Events: `PageEnter`, `PageLeave`, `Stopped`.

**`UIScale.Scale`:** a multiplier on the subtree.

**`UIPadding`:** `PaddingTop/Bottom/Left/Right` (UDim).

**`UIAspectRatioConstraint`:** `AspectRatio`, `AspectType`, `DominantAxis`.

**`UISizeConstraint`:** `MinSize` / `MaxSize`.

**`UITextSizeConstraint`:**
- `MinTextSize` / `MaxTextSize`.
- The docs warn: "**Do not use MinTextSize values lower than 9**".

**`GuiObject.AutomaticSize`:** `None`, `X`, `Y`, `XY`. The docs recommend `AutomaticSize` over `TextScaled`, and say
not to combine the two.

**`ScrollingFrame`:**
- `AutomaticCanvasSize`, `CanvasSize`, `ScrollingDirection`, `ElasticBehavior`, scrollbar insets.
- Use it for the tech tree and lists.

**`Path2D`** (2D splines in a ScreenGui or SurfaceGui):
- `Thickness`, `Color3`, `Closed`, `ZIndex`.
- `SetControlPoints`, `GetPositionOnCurve`.
- `GetMaxControlPoints()` exists, but the maximum value is not given in the docs.
- Useful for tech-tree edges and minimap routes.

**`UIDragDetector`** exists for draggable UI (`CD/ui/ui-drag-detectors.md`).

**History:** `UIFlexItem` was documented by 2023-11.
**Confidence:** High.

#### 2.3 Appearance modifiers, `CanvasGroup`, and their costs

**`UICorner`:**
- `CornerRadius` (UDim).
- **`TopLeftRadius`, `TopRightRadius`, `BottomLeftRadius`, `BottomRightRadius` are BETA**: "enable **New UI
  Capabilities** in Studio's beta features window" (documented 2026-05-07).

**`UIStroke`:**
- `Color`, `Thickness`, `Transparency`, `LineJoinMode`, `ApplyStrokeMode` (`Contextual`/`Border`), `Enabled`.
- Plus `BorderOffset` (UDim), `BorderStrokePosition` (`Outer`/`Center`/`Inner`), `StrokeSizingMode`
  (`FixedSize`/`ScaledSize`) and `ZIndex`. The class header says "Some properties may require enabling the Improved
  UIStrokes beta" (devforum topic 3958036).
- `BorderOffset` was documented 2025-09-24.
- `UIGradient` can tint a stroke.

**`UIGradient`:**
- `Color` (ColorSequence), `Transparency` (NumberSequence), `Rotation`, `Offset`, `Enabled`.
- Plus **`Type`** (`Linear`/`Radial`/`Conical`), `Scale` and `TileMode` (`Type` documented 2026-09-03; not flagged
  beta).

**`CanvasGroup`:**
- Renders its subtree into a texture, with `GroupTransparency` and `GroupColor3`.
- Always clips. Flattening needs `ZIndexBehavior=Sibling`.
- "Consumes extra texture memory. The quality … and total memory usage is limited by the `Enum.QualityLevel`. When
  exceeding the memory cap, CanvasGroup will render as a blank texture."
- "Use CanvasGroup with static sizes."

**MicroProfiler guidance** (`CD/performance-optimization/microprofiler/tag-table.md`):
- `Perform/fillGuiVertices` shows a "gui count" label. "If there are too many **Process GuiEffect** labels, consider
  reducing the use of `UIGradient` and `UICorner` on text labels."
- `Perform/Scene/UI`: "Using CanvasGroups can help at the expense of increased memory use."
- Adorns (BillboardGuis, name labels) are a separate scope: "Reduce the number of visible adorned objects."

**Confidence:** High, except the exact beta state of the UIStroke properties (Medium).

#### 2.4 Engine UI styling (StyleSheets)

**Current behavior** (`CD/ui/styling/index.md`, `CD/ui/styling/css-comparisons.md`, `StyleQuery.yaml`):
- Concepts:
  - `StyleSheet`: rules, with tokens as attributes;
  - `StyleRule`: a `Selector` plus property overrides;
  - `StyleDerive`: inherit tokens and themes;
  - `StyleLink`: attaches one sheet to a ScreenGui tree ("Only one StyleSheet can apply to a given tree").
- Selectors match:
  - class (`Frame`);
  - CollectionService tag (`.Tag`);
  - name (`#Name`);
  - pseudo-instances (`::UICorner`, `::UIStroke`);
  - **state** (`Enum.GuiState`: `Idle`, `Hover`, `Press`, `NonInteractable`);
  - **queries** with an `@` prefix.
- `StyleQuery` conditions include `MinSize`/`MaxSize` (container) and `PreferredInput`.
- **Built-in queries** need no StyleQuery instance:

| Built-in query | Condition |
|---|---|
| `@ViewportDisplaySizeSmall` | Small display |
| `@ViewportDisplaySizeMedium` | Medium display |
| `@ViewportDisplaySizeLarge` | Large display |
| `@PreferredInputKeyboardAndMouse` | Preferred input is keyboard and mouse |
| `@PreferredInputTouch` | Preferred input is touch |
| `@PreferredInputGamepad` | Preferred input is gamepad |
| `@ReducedMotionEnabledTrue` / `@ReducedMotionEnabledFalse` | Reduced-motion setting |

- All styling classes can be created from scripts (`Instance.new`).

**History:**
- `StyleSheet` documented by 2023-11.
- `StyleQuery` documented 2026-03-05.
- Built-in queries documented 2026-04-07.
- The styling guides import a `BetaAlert` component but no longer render it.

**Confidence:** High that it exists and is non-beta. Medium on maturity (recent).

#### 2.5 Text, fonts and rich text

**Fonts** (`CD/reference/engine/datatypes/Font.yaml`, `enums/Font.yaml`):
- Construct with `Font.new(familyAssetId, weight?, style?)`, `Font.fromName(name, …)`, `Font.fromEnum(Enum.Font.X)` or
  `Font.fromId(assetId, …)`.
- The 40 built-in families (`rbxasset://fonts/families/<Name>.json`) are:
  - Accanthis ADF Std, Amatic SC, Arimo, Balthazar, Bangers;
  - **Builder Extended, Builder Mono, Builder Sans**;
  - Comic Neue Angular, Creepster, Denk One, Fondamento, Fredoka One, Grenze Gotisch, Guru, **Highway Gothic**;
  - Inconsolata, Indie Flower, Josefin Sans, **Jura**, Kalam, Luckiest Guy, Merriweather, **Michroma**;
  - **Montserrat**, Nunito, **Oswald**, Patrick Hand, Permanent Marker, Press Start 2P;
  - **Roboto, Roboto Condensed, Roboto Mono**, Roman Antique, **Sarpanch**, Source Sans Pro, Special Elite;
  - **Titillium Web**, Ubuntu, **Zekton**.
- Licensing for Builder Sans and the Gotham → Montserrat mapping: see `06-ui-ux-audio.md` §28.

**`TextLabel` / `TextButton`:**
- `TextScaled` ignores `TextSize`, forces `TextWrapped`, and is **not** scaled by the player's `PreferredTextSize`.
- `TextFits` (read-only).
- `MaxVisibleGraphemes` (−1 means no limit; good for typewriter effects).
- `RichText`.
- `TextSize` is a line height in offsets.

**Player text-size setting:**
- `GuiService.PreferredTextSize` takes `Medium` (default), `Large`, `Larger` or `Largest`. The engine applies it
  **automatically** "through the engine's font rendering pipeline".
- `AutomaticSize` elements grow with it, and `TextService:GetTextSize()`/`GetTextBoundsAsync()` honor it.
- It is overridden by `UITextSizeConstraint` limits and by `TextScaled`.

**Rich text** (`CD/ui/rich-text.md`):
- Tags: `<font color|size|face|family|weight|transparency>`, `<stroke>`, `<b>`, `<i>`, `<u>`, `<s>`, `<br/>`,
  `<uppercase>`/`<uc>`, `<smallcaps>`/`<sc>`, `<mark>`, `<!-- -->`.
- Escapes are required (`&lt;` …).

**Confidence:** High.

#### 2.6 Gamepad and console navigation

**Current behavior** (`GuiService.yaml`, `GuiObject.yaml`, `GuiBase2d.yaml`, `GamepadService.yaml`,
`CD/production/publishing/console-guidelines.md`):

**`GuiService`:**
- `SelectedObject` (the current focus).
- `GuiNavigationEnabled`.
- `AutoSelectGuiEnabled`: when true, the gamepad **Select** button or Backslash auto-selects a GUI. When false,
  navigation still works but you must set `SelectedObject` yourself.
- `CoreGuiNavigationEnabled`.
- **`GuiService:Select(parent)`** selects the visible, selectable descendant with the **smallest `SelectionOrder`**.
- Selection groups: `AddSelectionParent(name, parent)`, `AddSelectionTuple(name, ...)`, `RemoveSelectionGroup(name)`.
- `IsTenFootInterface()` reports console UI.

**`GuiObject`:**
- `Selectable`, `SelectionOrder` (default 0; affects only the initial pick and `Select()`, not directional moves).
- `NextSelectionUp/Down/Left/Right` (explicit graph edges).
- `SelectionImageObject` (custom focus adornment).
- `Interactable`.
- Events `SelectionGained` / `SelectionLost`.

**`GuiBase2d`:**
- `SelectionGroup` (bool) with `SelectionBehaviorUp/Down/Left/Right` (`Escape` = default, prefer inside then leave;
  `Stop` = trap focus inside).
- `SelectionChanged` event.

**Virtual cursor:** `GamepadService:EnableGamepadCursor()` / `DisableGamepadCursor()`, `GamepadCursorEnabled`, and
`StarterGui.VirtualCursorMode` (`Default`/`Enabled`/`Disabled`).

**Console guidelines** (no numeric minimums given):
- Players sit **8–10 ft** away.
- Use relative sizes plus `UISizeConstraint`, and design for `ViewportDisplaySize.Large`.
- Respect the TV-safe area.
- "Make sure players can reach all UI elements using these basic navigation controls" (four directions, select, back).
- Minimize controller moves and add shortcuts.
- **Disable the chat window on console.**
- Use dynamic button icons. `UserInputService:GetImageForKeyCode()` returns Xbox, PlayStation or Windows glyphs.
  `GetStringForKeyCode()` maps keyboard layouts.
- Haptics and UI sounds are recommended.
- Content-maturity info is required for console release.

**Confidence:** High for the APIs. "No keyboard-only flows" follows directly from the reachability rule (High).

#### 2.7 `ViewportFrame` and `WorldModel`

**`ViewportFrame` caveats** (`CD/reference/engine/classes/ViewportFrame.yaml`, `CD/ui/viewport-frames.md`):
- No shadows and no post-processing.
- `Neon` and `Glass` render at the lowest quality.
- No nested GuiObjects.
- Environment lighting acts as if both scales are 0, unless a `Sky` child is used as a reflection cubemap.
- Has `Ambient` (default 200,200,200) and `CurrentCamera`. "When you want to update the view … update the camera, not
  the objects."

**`WorldModel`** (child of a ViewportFrame):
- Enables raycasts and other spatial queries plus animation of its parts, with no simulation.
- "To avoid possible performance issues, make sure to only create WorldModels when you want to show them and to delete
  WorldModels that are currently not in use."

**Cost:** no numeric guidance is given.

**Confidence:** High for the caveats. Cost is an Open question.

#### 2.8 World-space UI: `BillboardGui`, `SurfaceGui`, `Highlight`

**`BillboardGui`:**
- `Adornee`, `AlwaysOnTop`, `MaxDistance`, `DistanceLowerLimit`, `DistanceUpperLimit`, `DistanceStep`,
  `CurrentDistance`, `LightInfluence`, `Brightness`, `StudsOffset[WorldSpace]`, `ExtentsOffset[WorldSpace]`, `SizeOffset`,
  `PlayerToHideFrom`, `Size` (UDim2: scale is in studs, offset in pixels).

**`SurfaceGui`:**
- `Face`, `Adornee`, `CanvasSize`, `PixelsPerStud`, `SizingMode`, `AlwaysOnTop`, `LightInfluence`, `MaxDistance`,
  `ZOffset`.

**`Highlight`** (`CD/effects/highlighting.md`, `Highlight.yaml`):
- Properties: `Adornee`, `DepthMode` (`AlwaysOnTop`/`Occluded`), `FillColor`/`FillTransparency`,
  `OutlineColor`/`OutlineTransparency`, `Enabled`.
- **Limit: 255 simultaneous on the client.** Extras are "silently ignored". A Highlight with `Enabled=false` still takes
  one of the 255 slots, so the docs advise deleting, not disabling, a Highlight you are permanently done with.
- **Perf:**
  - add/remove "can cause a geometry rebuilding step … performance spikes and extra draw calls", while property
    changes are "lightweight";
  - "The first Highlight … incurs most of the performance cost (up to 1 millisecond of GPU time on mobile devices)";
  - on mobile, cost scales with screen coverage;
  - invisible highlights cost nothing.

**History:**
- The 31 → 255 change was announced on the DevForum ("Lights, Camera, More Highlights", topic 4061534).
- Class reference updated 2025-11-17; guide fixed 2026-04-03 (PR #1483).

**Confidence:** High.

---

### 3. Input

#### 3.1 Input Action System (IAS)

**Current behavior** (`CD/input/input-action-system.md`, `InputContext.yaml`, `InputAction.yaml`,
`InputBinding.yaml`):

**`InputContext`:**
- `Enabled`, `Priority` (higher runs first), `Sink` (consume bound keys for lower-priority contexts).
- The guide suggests `Priority=2000` plus `Sink` to pre-empt the default PlayerScripts contexts.

**`InputAction`:**
- `Type` (`Bool`, `Direction1D`, `Direction2D`, `Direction3D`, `ViewportPosition`), `Enabled`, `DisplayName`.
- **`PreferredBinding`** is the binding matching the current device.
- `GetState()`, `Fire()`.
- Events `Pressed`, `Released` (Bool only) and `StateChanged`.

**`InputBinding`:**
- `KeyCode`, composite `Up/Down/Left/Right/Forward/Backward`, `PrimaryModifier`/`SecondaryModifier`.
- **`UIButton`** links a `GuiButton` as a touch binding. `UIModifier` also exists.
- `Scale`, `Vector2Scale`, `Vector3Scale`, `ClampMagnitudeToOne`.
- `PressedThreshold` (default **0.5**) and `ReleasedThreshold` (default **0.2**) for analog triggers.
- **`ResponseCurve`** (1–10, default 1; quadratic thumbstick curve, for `Direction2D` on `Thumbstick1/2`).
- `DisplayName` / `DisplayImage`, `Type`, `Fire()`.
- Mouse look uses `KeyCode=MouseDelta` with `Scale=0.01`. Touch look uses `TouchDelta`.

**`InputActionLabel`** (**beta**, documented 2026-07-29): a GuiObject that shows the correct glyph for an action.

**Engine wiring:** `Workspace.PlayerScriptsUseInputActionSystem` (RolloutState) moves the default player scripts onto
IAS. `StarterPlayer.CreateDefaultPlayerModule=false` (only visible with that flag) removes the default camera and
control scripts.

All IAS classes can be created from code.

**History:**
- `InputAction` documented 2025-02-19.
- Guide published 2025-08-06 with no beta banner.

**Confidence:** High.

#### 3.2 Input-type detection

**`UserInputService.PreferredInput`** (`Enum.PreferredInput`):
- `KeyboardAndMouse`, `Gamepad`, `Touch`, `MicroGamepad` (thumbstick-less remotes).
- "changes based on built‑in device inputs and the player's most recent interaction with a connected gamepad or
  keyboard/mouse".
- Examples: a phone with a BT keyboard → KeyboardAndMouse; a tablet with a BT pad → Gamepad; a console with a keyboard
  most recently used → KeyboardAndMouse.

**Other signals:**
- `GamepadEnabled`, `KeyboardEnabled`, `MouseEnabled`, `TouchEnabled`, `TouchScreenEnabled` (true hardware capability).
- `GetLastInputType()` / `LastInputTypeChanged`.
- `GamepadConnected` / `GamepadDisconnected`.

**Glyph helpers:**
- `UserInputService:GetImageForKeyCode(keyCode)` returns a ContentId for Xbox, PlayStation or Windows.
- `GetStringForKeyCode()`.
- The client content folder ships generic glyphs at `rbxasset://textures/ui/Controls/DefaultController/ButtonA.png` …
  `ButtonStart.png` (@2x, @3x variants).

**History:** `PreferredInput` documented 2025-06-02.
**Confidence:** High.

#### 3.3 `ContextActionService` (legacy but supported)

- `BindAction(name, fn, createTouchButton, ...inputs)` and `BindActionAtPriority`.
- Touch buttons go into the `ContextActionGui/ContextButtonFrame` ScreenGui. **Max 7 touch buttons.**
- Customize them with `GetButton`, `SetImage`, `SetTitle`, `SetPosition` and `SetDescription`.

**Confidence:** High (`ContextActionService.yaml`).

#### 3.3a Default and reserved bindings (added by fact-check)

`CD/includes/default-bindings.md` (included in `CD/input/index.md` and `CD/input/input-action-system.md`):
- "the **reserved** inputs cannot be overridden and will always operate with their intended purpose":
  - Open Roblox menu: `Esc` / **`ButtonStart`**;
  - Developer Console `F9`, fullscreen `F11`, record video `F12`, screenshot `PrintScreen`.
- Reserved "unless you disable the respective feature" (`CD/players/disable-ui.md`):
  - text chat `/`; players list `Tab`; backpack `` ` ``;
  - tools: `0`–`9`, `ButtonL1`/`ButtonR1` (swap), `ButtonR2` (use), `Backspace` (drop);
  - UI selection mode: toggle with `\` / **`ButtonSelect`**, navigate with arrows/WASD/`Thumbstick1`/D-pad, activate
    with `Enter` / `ButtonR2`, scroll with `Thumbstick2` (footnote: "If `GuiService.GuiNavigationEnabled` is enabled
    (default)").
- Default camera and controls: `Shift` toggles mouse lock "If `StarterPlayer.EnableMouseLockOption` is enabled
  (default)"; right mouse drag, mouse wheel and `I`/`O` drive the default camera.

**Confidence:** High (verbatim table). The Xbox guide and PlayStation buttons are system-level and not listed.

#### 3.4 Haptics

**`HapticEffect`** (instance):
- `Type` (`Custom`, `UIHover`, `UIClick`, `UINotification`, `GameplayExplosion`, `GameplayCollision`).
- `Looped`.
- `Position` + `Radius` (which motors to drive).
- `SetWaveformKeys()` (custom waveform), `Play()`, `Stop()`, `Ended`.

**Supported devices:** "Android and iOS phones supporting haptics including most iPhone, Pixel, and Samsung Galaxy
devices; PlayStation gamepads; Xbox gamepads; Quest Touch controller."

**Legacy API:** `HapticService:SetMotor/GetMotor/IsMotorSupported/IsVibrationSupported`.

**History:** `HapticEffect` documented 2024-08-14.
**Confidence:** High.

#### 3.5 Mobile specifics

**Orientation** (`CD/input/mobile.md`):
- `StarterGui.ScreenOrientation` (`LandscapeSensor` default, `Sensor`, `LandscapeLeft`, `LandscapeRight`, `Portrait`).
- Runtime control via `PlayerGui.ScreenOrientation`. `PlayerGui.CurrentScreenOrientation` reports the current state.

**Default touch controls:**
- `GuiService.TouchControlsEnabled` (default true) hides or shows them.
- `UserInputService.ModalEnabled` hides the character controls.
- Gestures: `TouchPan`, `TouchPinch`, `TouchRotate`, `TouchSwipe`, `TouchTap`, `TouchLongPress`, `TouchTapInWorld`.

**Device testing guidance** (`CD/performance-optimization/test-on-hardware.md`):
- Test touch targets on real 5-inch screens.
- Check that thumbsticks are "within comfortable reach zones".
- Watch for thermal throttling over **10–15 min** sessions.

**Confidence:** High.

#### 3.6 Mouse lock

- `UserInputService.MouseBehavior` takes `Default`, `LockCenter` or `LockCurrentPosition`.
- `GetMouseDelta()` reports deltas even while locked.
- A visible `GuiButton.Modal` overrides the lock, unless the right mouse button is down.
- `MouseIconEnabled` and `MouseIconContent`.
- "shift-lock related APIs are in the process of being deprecated … use `UserInputService.MouseBehavior` instead"
  (`StarterPlayer.EnableMouseLockOption`).

**Confidence:** High.

---

### 4. Camera

**Current behavior** (`Camera.yaml`, `CD/workspace/camera/index.md`, `RunService.yaml`, `WorldRoot.yaml`):

**Scriptable camera:**
- `Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable` gives full control.
- Set `CFrame` and **update `Focus` every frame** ("certain visuals are more detailed depending on how close they are
  to the focus point").

**`FieldOfView`:**
- **Vertical**, clamped **1–120°**, default **70°**.
- `FieldOfViewMode` (`Vertical`/`Diagonal`/`MaxAxis`), `DiagonalFieldOfView`, `MaxAxisFieldOfView`.
- `ViewportSize` is the device safe area.

**Conversions:**
- At 16:9, vertical 60/70/80/90° equals horizontal **91.5/102.4/112.3/121.3°**.
- At a 19.5:9 phone, it is 102.7/113.2/122.4/130.4°.

**Zoom (magnification M):** `FOV = 2·atan(tan(FOV₀/2)/M)`. With FOV₀ = 70°:

| Zoom | Vertical FOV |
|---|---|
| ×2 | 38.59° |
| ×4 | 19.86° |
| ×8 | 10.00° |
| ×16 | 5.01° |
| ×25 | 3.21° |

**Render-step ordering:**
- `RunService:BindToRenderStep(name, priority, fn)`.
- Default player scripts use Input = **100** and Camera = **200**.
- `Enum.RenderPriority`: First 0, Input 100, Camera 200, Character 300, Last 2000.
- `PreRender` is the event equivalent.

**Collision:**
- The Scriptable camera has **no** built-in occlusion handling. `DevCameraOcclusionMode` (Zoom/Invisicam) applies to
  the default camera scripts only.
- `Camera:GetPartsObscuringTarget()` and `GetLargestCutoffDistance()` exist.
- Use `WorldRoot:Spherecast(origin, radius ≤ 256, direction with |d| ≤ 1024, params)`.
  - It does not detect parts that initially intersect the sphere.
  - It is parallel-Safe.
- `Raycast` direction is limited to **15,000 studs**. `Blockcast` size is ≤ 512 studs and distance ≤ 1,024.

**Projection helpers:**
- `WorldToViewportPoint` (no GUI inset) and `WorldToScreenPoint` (with inset).
- `ViewportPointToRay` and `ScreenPointToRay`.

**Confidence:** High.

---

### 5. Rendering and performance

#### 5.1 Draw calls, instancing, parts vs meshes

**Draw calls** (`CD/performance-optimization/improve.md` §Rendering, `design.md`):
- Instancing groups meshes "with the same `MeshContent`" when the `SurfaceAppearance` is identical, or else the
  `TextureContent`, or else the **Material**.
- "Objects like decals, textures, and particles don't batch well and introduce additional draw calls."
- "Too many parts in a Model could cause rebuilds more often."
- The MicroProfiler has an instanced-geometry scope ("geometry that uses instanced rendering such as parts", with
  **Clusters**/**Instances** labels).

**Example baseline** (`design.md`): "stay below **1,000 draw calls and 1,000,000 triangles** for the game to run well on
your baseline device". That is an *example* method, not a platform rule.

**`MeshPart.RenderFidelity`:**
- `Automatic` (default): highest detail below **250 studs**, medium for **250–500**, lowest at **≥ 500**.
- Also `Precise` and `Performance`.
- Too many `Precise` meshes is a listed problem.

**`CollisionFidelity`:**
- Values: `Default`, `Hull`, `Box`, `PreciseConvexDecomposition`, `Tunable`.
- Precise is the most expensive in CPU and memory. Use Box or Hull for small or medium objects.
- Collision geometry is stored even with `CanCollide=false`.

**Per-part switches** (`BasePart`):
- `CastShadow`, `CanCollide`, `CanQuery` (spatial queries), `CanTouch`, `AudioCanCollide` (acoustic simulation),
  `Anchored`, `Massless`, `LocalTransparencyModifier`.

**Transparency:** "Avoid transparency values other than 0 and 1" because of overdraw.

**Materials:** "Built-in materials use far less memory than custom textures."
- 45 `Enum.Material` values (corrected by fact-check; was 46), counting the non-part `Air` and `Water`. They include
  `Metal`, `DiamondPlate`, `CorrodedMetal`, `SmoothPlastic`, `Concrete`, `Fabric`, `Rubber`.

**`SurfaceAppearance`** applies to `MeshPart`s only and needs uploaded PBR maps. Texture maps are capped at
**1024×1024** (`CD/art/modeling/texture-specifications.md`).

**Moving many parts:**
- When one part of an assembly is anchored, "that part becomes the root part and all of the other parts become
  implicitly anchored with it" (`CD/physics/assemblies.md`).
- `WorldRoot:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` is "a very fast way to move large numbers
  of parts". It is serial-only.

**Confidence:** High.

#### 5.2 Model LOD, instance streaming, SLIM and frustum streaming

**`Model.LevelOfDetail`:**
- `Automatic` (= Disabled today).
- `StreamingMesh` (legacy colored imposter, no textures).
- `Disabled`.
- **`SLIM`**: cloud-transcoded composite meshes with multiple LODs.

**SLIM prerequisites** (`CD/workspace/streaming/slim.md`):
- `StreamingEnabled`.
- A place **saved to Roblox**.
- **Team Create** enabled.

**SLIM limitations:**
- "**Static models only** — does not support models modified at runtime (parts added/removed, properties changed) or
  models that play animations".
- Excludes Humanoids.
- Initial generation takes about 1–2 minutes.
- Unsupported platforms fall back to `Disabled`.

**Streaming settings** (`CD/workspace/streaming/techniques.md`, `index.md`). All are non-scriptable (set in Studio or the
place file). Recommended values:
- `ModelStreamingBehavior=Improved`;
- `StreamingIntegrityMode=PauseOutsideLoadedArea`;
- `StreamingMinRadius=64` (default);
- `StreamingTargetRadius=1024` (default);
- `StreamOutBehavior=Opportunistic`.

**Model guidance:**
- Keep models under ~64 cubic studs.
- `ModelStreamingMode`: `Default`, `Atomic`, `Persistent`, `PersistentPerPlayer`, `Nonatomic`.
- Minimize persistent models.

**Replication focus:**
- Streaming centers on the character's `PrimaryPart`.
- `Player.ReplicationFocus` (server-only) overrides it. `AddReplicationFocus` / `RemoveReplicationFocus` add extra foci
  (each one costs server work).
- Client physics and prediction "only occurs in streamed areas".

**Frustum streaming** (`CD/workspace/streaming/frustum.md`, documented 2026-10-01):
- `Player.FrustumStreaming` (server-only) takes `Default` (= Disabled), `Disabled`, `Automatic` or `Enabled`.
- `Automatic` activates on a narrow FOV (scopes), on high velocity toward the view direction, or when the camera is far
  from the focus.
- It streams to the lesser of draw distance and an engine maximum. It has the same budget as a replication focus.
- With `Opportunistic` stream-out, instances outside the view linger **1.5 s** before collection.
- It is disabled automatically when draw distance ≤ the target radius.
- No occlusion awareness. During fast rotation the frustum "narrows to a beam".

**Confidence:** High (frustum streaming is brand new; maturity is Medium).

#### 5.3 Lighting, atmosphere and post-processing

**Lighting** (`CD/environment/lighting.md`, `Lighting.yaml`):
- **`Lighting.Technology` is deprecated** in favour of:
  - **`LightingStyle`**: `Realistic` = most advanced lighting and shadows; `Soft` = flat retro look.
  - **`PrioritizeLightingQuality`**: `true` keeps shadows and shaders at the expense of view distance; `false` keeps
    view distance.
- `GlobalShadows`; `ShadowSoftness` (0–1, Realistic only).
- `Ambient`, `OutdoorAmbient`, `Brightness`, `ExposureCompensation`, `EnvironmentDiffuseScale` /
  `EnvironmentSpecularScale`, `ClockTime`, `GeographicLatitude`.

**Shadow cost:**
- "the engine automatically degrades shadow quality as client graphics quality level decreases, eventually disabling
  shadows altogether at quality levels below 4."
- Mitigations: `CastShadow=false` on small or distant parts, disable shadows on moving objects, `Light.Shadows=false`,
  limit light range and angle, fewer lights.

**Local lights:**
- `PointLight` (`Range`), `SpotLight` (`Range`, `Angle` ≤ 180, `Face`), `SurfaceLight`.
- Shared: `Color`, `Brightness`, `Shadows`, `Enabled`.
- The current docs give **no numeric maximum** for `Range`, nor a light-count cap.
- MicroProfiler: `computeLightingPerform/LightGridCPU` (voxel lighting at lower quality) and `ShadowMapSystem`.

**Atmosphere** (in `Lighting`): `Density`, `Offset`, `Color`, `Decay`, `Glare`, `Haze`.

**Clouds:** render only when parented under `Terrain`. Properties: `Cover`, `Density`, `Color`, `Enabled`.

**Post-processing:**
- Effects: `BloomEffect` (`Intensity`, `Size`, `Threshold`), `BlurEffect`, `ColorCorrectionEffect` (`Brightness`,
  `Contrast`, `Saturation`, `TintColor`), `DepthOfFieldEffect` (`FarIntensity`, `FocusDistance`, `InFocusRadius`,
  `NearIntensity`), `SunRaysEffect` (`Intensity`, `Spread`), `ColorGradingEffect` (`TonemapperPreset` =
  `Default`/`Retro`).
- Placement: under `Lighting` = all players; under `Camera` = per player. Some effects are hidden at low Studio quality
  levels.

**History:** `LightingStyle` documented 2024-12-05.
**Confidence:** High.

#### 5.4 Particles, beams, trails and legacy effects

**`ParticleEmitter`** (`CD/effects/particle-emitters.md`):
- **Rate ≤ 400 particles/s per emitter (100/s on mobile).**
- **Lifetime capped at 20 s.**
- Flipbook `Grid2x2`/`Grid4x4`/… with framerate **≤ 30 fps**.
- Fill rate (size) and overdraw (count) drive GPU cost.
- Flipbooks are auto-disabled on low-memory clients.
- `Emit(n)` for bursts.
- Property changes are expensive (`improve.md`).

**MicroProfiler:** `UpdateView/updateParticles` and `updateParticleBoundings`. Remedy: "Reduce the number of
ParticleEmitters, emission rates, lifetimes … limit the movement of emitters."

**`Beam`:** `Segments` (default 10; ≥ n−1 segments are needed for n color or transparency keypoints). Without a
`Texture`, a beam renders as a solid line.

**`Trail`:** `Lifetime` 0.01–20 s (default 2), `MinLength` / `MaxLength`.

**Legacy one-liners:** `Fire`, `Smoke`, `Sparkles` (not deprecated). `Explosion` has `Visible`, `BlastPressure`,
`BlastRadius`, `DestroyJointRadiusPercent`, `TimeScale`, `ExplosionType`. A visual-only explosion uses `BlastPressure=0`
and `DestroyJointRadiusPercent=0`.

**Built-in textures** (client content, `rbxasset://`; no upload, no moderation; shipped with every client build;
Roblox can change them). Under `textures/particles/`:
- `SquareParticle.png`, `common_alpha.dds`;
- `explosion01_core_alpha.png`, `explosion01_core_main.dds`, `explosion01_implosion_color.png`,
  `explosion01_implosion_main.dds`, `explosion01_shockwave_main.dds`;
- `explosion01_smoke_alpha.dds`, `explosion01_smoke_color_new.dds`, `explosion01_smoke_main.dds`;
- `explosion_alpha.dds`, `explosion_color.dds`;
- `fire_alpha.dds`, `fire_color.dds`, `fire_main.dds`, `fire_sparks_color.dds`, `fire_sparks_main.dds`;
- `forcefield_alpha.dds`, `forcefield_glow_alpha.dds`, `forcefield_glow_color.dds`, `forcefield_glow_main.dds`,
  `forcefield_vortex_color.dds`, `forcefield_vortex_main.dds`;
- `legacy_fire_alpha_color.dds`, `smoke_color.dds`, `smoke_main.dds`, `sparkles_color.dds`, `sparkles_main.dds`.

**Confidence:** High for the docs limits. Medium for using `rbxasset` paths in live games: they work because they ship
with the client, but they are unversioned and could change.

#### 5.5 EditableImage and EditableMesh

**Current behavior** (`EditableImage.yaml`, `EditableMesh.yaml`, `AssetService.yaml`):
- Created via `AssetService:CreateEditableImage()` / `CreateEditableImageAsync()` and the mesh equivalents.
- Used with `Content.fromObject(...)`.
- **Published games:** "using EditableImage fails by default … you must be **13+ age verified and ID verified** … toggle
  on **Enable Mesh / Image APIs**".
- Loading existing assets requires ownership or sharing permissions.
- `EditableImage.Size` is at most **1024×1024** and immutable.
- "Only a single EditableImage can be updated per frame on the display side."
- "**strict client-side memory budgets**". Creation fails when the device budget is exhausted.
- `EditableMesh`: **60,000 vertices and 20,000 triangles**.

**History:** the ID-verification requirement was documented 2024-11-18.
**Confidence:** High.

#### 5.6 Terrain

**Current behavior** (`Terrain.yaml`, `CD/parts/terrain.md`):
- Voxels are **4×4×4 studs**.
- `ReadVoxels`, `WriteVoxels`, `ReadVoxelChannels` and `WriteVoxelChannels` (channels `SolidMaterial`, `SolidOccupancy`,
  `LiquidOccupancy`) require grid alignment, `resolution=4`, and a region of **≤ 4,194,304 voxels** (e.g., 256×64×256).
- Shape fills: `FillBlock`, `FillBall`, `FillCylinder`, `FillWedge`, `FillRegion`. Also `ReplaceMaterial`,
  `CopyRegion`/`PasteRegion` (`TerrainRegion`).
- `WriteVoxels` must run in the serial phase.
- **Speed is not documented.**

**Materials:** 22 terrain materials:
- Asphalt, Basalt, Brick, Cobblestone, Concrete, Cracked Lava, Glacier, Grass, Ground, Ice, Leafy Grass;
- Limestone, Mud, Pavement, Rock, Salt, Sand, Sandstone, Slate, Snow, Water, Wood Planks.

**Grass:**
- `Terrain.Decoration` (animated grass on the `Grass` material only) is **NotScriptable**. It cannot be a runtime
  graphics option.
- `GrassLength` is 0.1–1. Wind via `Workspace.GlobalWind`.
- Reduce Motion slows the grass.

**Water:**
- `WaterColor`, `WaterReflectance`, `WaterTransparency`, `WaterWaveSize`, `WaterWaveSpeed`.
- `RaycastParams.IgnoreWater`.
- Buoyancy uses density relative to water (1 RMU/stud³). `BasePart.SpecificGravity` is exposed. `BuoyancySensor`
  reports `FullySubmerged` and related values.
- **Irrelevant for our kinematic vehicles**, which use `World:waterDepthAt`.

**Units** (`CD/physics/units.md`): Roblox defines **1 stud = 28 cm**. HULLDOWN deliberately uses 1 stud = 1/3 m.

**Confidence:** High.

#### 5.7 Memory, device mix and profiling

**Device mix** (`CD/performance-optimization/test-on-hardware.md`):
- Android ≈ 65% of a typical player base.
- Of those Android players: 60% have 2–4 GB RAM, 35% have 4–8 GB, 5% have more than 8 GB.
- More than 50% of players are on devices with Passmark 10k–20k.
- Suggested Android test set: Infinix Smart 9, Moto G05, Oppo A18, Fire HD 10 (2023), Galaxy S22 Ultra.

**Memory and performance facts** (`identify.md`, `design.md`):
- Studio memory readings are inflated, because it runs client and server together. Measure on the device.
- Client `PlaceMemory` labels: `GraphicsMeshParts`, `GraphicsTexture`, `Sounds`.
- Investigate crash rates above **2–3%**.
- Client default FPS cap is 60 (240 on Windows). Server heartbeat is capped at **60**.
- Server memory = **6.25 GiB + 100 MiB × peak players**. Keep usage below 50%.

**Script hygiene:**
- Disconnect connections.
- Use `Workspace.PlayerCharacterDestroyBehavior`.
- Spread work (5 ms per frame, then `task.wait()`).
- Event-driven code over per-frame code.
- Do not put server-only assets in `ReplicatedStorage`.

**MicroProfiler:**
- Ctrl+Alt+F6 on the client. The phone web UI shows the last 30 frames by default (`/90` in the URL for more).
- **Server dumps**: Dev Console (Ctrl+F9) → MicroProfiler → Server, **≤ 60 frames, ≤ 4 s delay**.
- Bar colors:
  - orange = jobs-bound;
  - blue = render-bound;
  - red = GPU wait > 2.5 ms.
- Label your own code with `debug.profilebegin/profileend`.
- Studio's Assistant and the Studio MCP can analyse paused captures.

**Physics:**
- Adaptive timestepping steps at 60/120/240 Hz. Fixed mode steps at 240 Hz.
- Anchor everything that need not simulate.

**Confidence:** High.

---

### 6. Audio

**Current behavior.** The full property tables are in `06-ui-ux-audio.md` §25–27, verified against the same docs.
Performance-relevant points:

**API status:**
- `CD/audio/objects.md`: "`Sound`, `SoundGroup`, and `SoundEffect` objects are now discouraged in favor of the more
  robust functionality of audio objects" (documented 2025-05-22).
- `CD/sound/index.md` carries a "newer set of audio objects" warning.

**Graph:**
- 3D: `AudioPlayer` → `Wire` → `AudioEmitter` … `AudioListener` → `Wire` → `AudioDeviceOutput`.
- 2D: `AudioPlayer` → `Wire` → `AudioDeviceOutput`.
- `SoundService.DefaultListenerLocation`:
  - `Camera` auto-creates the listener and output;
  - `None` lets scripts create their own;
  - `Character` needs a character, so it is unusable for us.

**Attenuation:**
- `AudioEmitter.DistanceAttenuationMode`: `Custom` (default), `Inverse`, `InverseTapered`, `Linear`, `LinearSquared`.
  Documented 2026-08-11.
- `DistanceAttenuationBounds` default `[4, 10000]`.
- `SetDistanceAttenuation({[distance]=volume})`: ≤ **400** points, linear interpolation. An empty curve means
  inverse-square.
- `SetAngleAttenuation` handles directionality.
- `AudioInteractionGroup` routes emitters to matching listeners.
- `GetAudibilityFor(listener)` returns 0–1.

**Acoustic simulation** (occlusion, diffraction, reverb):
- `SoundService.AcousticSimulationEnabled` (global; documented 2025-11-20) and the per-emitter/listener
  `AcousticSimulationEnabled`.
- `BasePart.AudioCanCollide` controls which parts occlude or reflect.
- Cost per emitter is **not documented**.

**Playback:**
- `AudioPlayer:Play()` "plays … from wherever its TimePosition is", optionally scheduled at `atTime` against
  `SoundService:GetMixerTime()`.
- One AudioPlayer = one playhead, so overlapping one-shots need several players.

**Profiling:**
- MicroProfiler `Sound` and `Sound/stepInstances`: "Reduce the amount of sounds in active playback".
- Audio memory is visible in Scene Analysis.

**Legacy `Sound`:**
- `RollOffMode`: `Inverse` (default), `Linear`, `InverseTapered`, `LinearSquare`.
- `RollOffMinDistance`/`RollOffMaxDistance` apply only to sounds parented to a BasePart or Attachment.
- `Volume` 0–10; the docs warn rarely to go above 2.
- Effects: `EqualizerSoundEffect`, `ReverbSoundEffect`, `CompressorSoundEffect`, `ChorusSoundEffect`,
  `DistortionSoundEffect`, `EchoSoundEffect`, `FlangeSoundEffect`, `PitchShiftSoundEffect`, `TremoloSoundEffect`.
- `SoundService` settings: `AmbientReverb`, `RolloffScale`, `DopplerScale`, `DistanceFactor`, `SetListener`.

**Voice limit:** **not documented** in either API.

**Upload rules** (`CD/audio/assets.md`, `CD/cloud/guides/usage-assets.md`):
- `.mp3`, `.ogg`, `.wav` or `.flac`; < 20 MB; < 7 min; ≤ 48 kHz; mono, stereo, 3.0 or 5.1.
- Quota per the audio guide: 2,000 per 30 days (ID-verified) or 100 (unverified). The guide says imports through the
  Asset Manager, the Creator Dashboard **and the Open Cloud API** fall under it.
- **Open Cloud guide: "Up to 100 uploads per month if you're ID-verified; up to 10 … if you aren't"**, and audio cannot
  be updated through Open Cloud.
- **History (corrected by fact-check):** the audio guide itself said "100 … per 30 days (verified), 10 (unverified)"
  until commit `5690416a` (2026-03-17) raised it to 2,000/100. The Open Cloud row was last changed on 2025-02-28
  (`e5f98f48`). The "conflict" is therefore most likely a stale Open Cloud page, not two different quotas.

**Confidence:** High for the format limits. Medium for the quota: the newer figure is 2,000 per 30 days, but the Open
Cloud page has not been updated to match.

---

### 7. Assets and VFX without uploads

**Content URIs** (`CD/projects/assets/index.md`):
- `rbxassetid://` points to uploaded assets.
- `rbxasset://` points to the client content folder (e.g. `rbxasset://textures/face.png`).
- `rbxthumb://`, `rbxgameasset://`.

**No-upload building blocks:**
- 45 built-in `Enum.Material`s (corrected by fact-check; was 46), of which `Air` and `Water` are not part materials.
- Part shapes: Block, Wedge, CornerWedge, Cylinder, Ball.
- Untextured `Beam` and `Trail`.
- `ParticleEmitter`s with the `textures/particles/*` list in §5.4.
- `Fire`, `Smoke`, `Sparkles`, `Explosion`.
- `Highlight`.
- 40 font families.
- `Path2D`, `UIGradient`, `UIStroke`, `UICorner` for vector-style UI icons.
- Controller glyphs via `GetImageForKeyCode`, or the `rbxasset://textures/ui/Controls/DefaultController/*` files.

**Upload limits** (`CD/cloud/guides/usage-assets.md`):
- Decal and Image: `.png`, `.jpeg`, `.bmp`, `.tga`, **smaller than 8000×8000 px**; cannot be updated via Open Cloud.
  The display resolution limit is still 1024×1024.
- Audio: see §6.
- Model: `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx`; becomes a Model of MeshParts, uploaded as packages.
- Mesh: Roblox-format only, from asset delivery.
- Everything uploaded goes through moderation.

**Confidence:** High.

---

### 8. Character-less (vehicle-only) games

**Current behavior:**
- `Players.CharacterAutoLoads=false` means characters spawn only after `Player:LoadCharacterAsync()`.
  (`Player:LoadCharacter()` is deprecated in favour of `LoadCharacterAsync`.)
- **StarterGui is not cloned** without a character (`on-screen-containers.md`), so build UI in code under `PlayerGui`.
- `ResetOnSpawn` becomes irrelevant. Set it to `false` anyway.
- **Camera:** without a character, the default camera has no subject. Set `CameraType=Scriptable` on join.
- **Controls:**
  - With `Workspace.PlayerScriptsUseInputActionSystem=Enabled`, set `StarterPlayer.CreateDefaultPlayerModule=false` to
    remove the default camera and control scripts entirely.
  - Otherwise use `StarterPlayer.DevTouchMovementMode=Scriptable`, `DevComputerMovementMode=Scriptable`, and/or
    `GuiService.TouchControlsEnabled=false`.
  - `PlayerModule:GetControls():Disable()` is common practice **[prior knowledge, not re-verified; the docs do not
    mention `GetControls`]**.
- **Streaming focus:** the default focus is the character's PrimaryPart. With streaming on, the server must set
  `Player.ReplicationFocus` to a part that follows the player's vehicle or camera.
- **Audio:** `SoundService.DefaultListenerLocation = Camera`, or `None` with our own listener.
- **Chat bubbles:** `TextChatService:DisplayBubble(partOrCharacter, message)` works on any part (client-only). Chat
  window configuration: disable it on console.
- **Core UI:** `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.X, false)` for `PlayerList`, `Health`, `Backpack`,
  `Chat`, `EmotesMenu`, `SelfView`, `Captures`, `AvatarSwitcher`, `ExperienceShop`.
- **Leak hygiene:** `Workspace.PlayerCharacterDestroyBehavior` destroys `Player` objects after leave.

**Confidence:** High, except where marked.

---

## Implementation recommendations for HULLDOWN (Roblox)

Everything below is **OUR DESIGN CHOICE** unless a section cites a doc fact. Numbers are starting budgets, to be
re-measured on the baseline devices in §R14.

### R1. Luau usage rules (additions to ARCHITECTURE §3)

1. **Requires.** Keep string requires exactly as ARCHITECTURE §3.2 specifies; they are valid on Roblox (§1.1).
   - Client entry points must not require anything before `game.Loaded`, because requires are non-blocking.
   - Never require `@game/ServerScriptService/...` from code that can run on the client.
   - Add a test in `tests/` that fails if any `Client/` module requires a server path.
2. **Types.**
   - `--!strict` everywhere. luau-lsp strict is the gate.
   - **Do not use `type function`s** or other new-solver-only features. Leave `Workspace.UseNewLuauTypeSolver` at
     `Default`.
   - Annotate every parameter in hot modules. Native codegen checks argument annotations, and the docs single out
     `Vector3` as getting vector-specialized code; `CFrame` specialization is not documented (corrected by fact-check).
3. **Native code (`--!native`).** Allow-list only, re-checked with `debug.dumpcodesize()` before each release. Keep
   total native size **≤ 50%** of the reported limit.
   - Allowed modules:
     - `Shared/Combat/Ballistics`, `ArmorGeometry`, `Penetration`, `DamageModel`;
     - `Shared/Spotting/VisibilityModel`;
     - `Shared/Vehicle/VehicleSim`, `TurretSim`;
     - `Shared/Net/Codecs/*` (buffer-heavy);
     - the server heightfield sampler (R7.4).
   - The client gain is undocumented. The annotation is harmless there.
4. **Parallel Luau: staged.**
   - **Phase 1: serial.** Wrap each tick system in `debug.profilebegin("HD/<System>")`.
   - **Phase 2**, only if server MicroProfiler dumps show **Spotting > 2.0 ms per tick** or **Projectiles > 1.5 ms per
     tick** on average in a 30-bot battle:
     - Create **16 worker Actors**, each running the same worker script.
     - The main serial tick sends each Actor one `SendMessage("LOS", requestBuffer)`. Each Actor runs
       `BindToMessageParallel` and does its raycasts (`Raycast` and `Blockcast` are parallel-Safe).
     - Each Actor writes results into a per-Actor `SharedTable`. The main loop consumes them on the **next** tick.
       Spotting is already staggered (100 ms or more per pair, see `02`), so one tick of latency is acceptable.
     - Workers `require` their Shared modules at startup, in the serial phase.
   - Never use `Shapecast` in workers (Unsafe).
5. **Scheduling.**
   - Use only the `task.*` functions. No per-frame allocations in hot loops, per ARCHITECTURE §3.11.
   - Prefer `buffer` and pre-sized arrays.
   - A `buffer` handed to an Actor is copied: build one per Actor.

### R2. UI framework approach

**Decision: keep the in-house `UI/Kit`** (ARCHITECTURE §10): `Create`, `State` (Value/Computed/Observer), `Theme`,
`Router`, `Focus`, `InputMode`, `Layout`. Do not vendor a library.

**Why not a library:**
- Fusion's newest tag is still `v0.3-beta`. Roact is archived at `v1.4.4`.
- react-lua (`v17.2.1`) is large and needs a reconciler, scheduler and polyfills.
- Vide (`0.4.1`) is small but pre-1.0. (Tags come from `git ls-remote` on 2026-10-05.)
- An in-house kit of about 600 lines stays `--!strict`, stays Lune-testable (the State graph is pure) and adds no
  third-party upgrade risk.

**Engine StyleSheets:** not in v1. The Luau `Theme` stays the single source of tokens, because Lune cannot evaluate
engine styling, which would break the "depth must be testable" pillar. Revisit after launch to use
`@PreferredInput*`/`@ViewportDisplaySize*` queries for designer-tunable variants.

**Component rules:**
- **No `TextScaled`.** Use fixed `TextSize` tokens with `AutomaticSize` and `UITextSizeConstraint`, so the player's
  `PreferredTextSize` setting works.
- Minimum body text is **14 px** at UIScale 1 on Small displays and **18 px** on Large. Never below 9, per the docs.
- One root `UIScale` per ScreenGui, driven by `Layout`:
  - `scale = clamp(min(vw/1280, vh/720), 0.75, 1.6)`;
  - multiplied by **1.25** when `ViewportDisplaySize=Large` (10-ft UI);
  - multiplied by the user's UI-scale setting (0.8–1.2).
- Keep `UICorner`, `UIGradient` and `UIStroke` off high-churn text labels (the GuiEffect cost noted in §2.3). Put them
  on containers instead.
- Use a `CanvasGroup` only for fades of static-size panels, with at most 3 alive at a time.
- Do not use beta UI properties: per-corner `UICorner` radii, and the new `UIStroke` `BorderOffset`,
  `BorderStrokePosition`, `StrokeSizingMode` and `ZIndex`. `Theme` exposes a `useBetaUi=false` flag for when they
  graduate.
- Draw tech-tree edges with `Path2D` (fallback: rotated thin Frames), and build lists with `ScrollingFrame` plus
  `AutomaticCanvasSize`.
- `VirtualList` recycles rows: render at most visible + 4 rows.

**ScreenGui layering.** All guis are created by code under `PlayerGui` with `ResetOnSpawn=false` and
`SafeAreaCompatibility=None`.

| ScreenGui | DisplayOrder | ScreenInsets | Notes |
|---|---|---|---|
| `World` (vignette, scope overlay, damage flash) | 0 | `None` | non-interactive only |
| `Markers` (vehicle markers, hit markers) | 5 | `DeviceSafeInsets` | projected markers, clamped to screen edge |
| `HUD` | 10 | `CoreUISafeInsets` | interactive touch controls live here |
| `Screens` (garage/menus) | 20 | `CoreUISafeInsets` | inactive screens use `Enabled=false` |
| `Modals` | 30 | `CoreUISafeInsets` | `SelectionGroup` with `Stop` behavior |
| `Toasts` | 40 | `CoreUISafeInsets` | |
| `Loading` | 100 | `None` background plus an inner `CoreUISafeInsets` frame | |

On Large displays, add an extra **5% inner padding** (`UIPadding` 0.05 scale) to stay inside the TV-safe area. The
docs give no percentage, so this is our choice.

### R3. Controller navigation strategy

- **Global settings:** `GuiService.GuiNavigationEnabled=true`, `AutoSelectGuiEnabled=false`. We want the View/Select
  button for the scoreboard and map, and we always start focus explicitly.
  - **[Medium, added by fact-check]** The default-bindings table (§3.3a) lists `ButtonSelect` as the reserved UI
    selection toggle while `GuiNavigationEnabled` is on. `AutoSelectGuiEnabled=false` should stop Select from grabbing
    focus, but that it fully frees the button is not stated. Verify in Studio (R14); the fallback scoreboard binding is
    holding `DPadRight` in battle (unused in R5; `DPadUp`/`DPadDown` are sniper zoom).
- **Focus manager (`UI/Kit/Focus`):**
  - On `Router.push(screen)`: mark the screen root `SelectionGroup=true` (behavior `Escape` for panels, `Stop` for
    modals), then call `GuiService:Select(screenRoot)`. Focus goes to the lowest `SelectionOrder`.
  - Remember the last focused element per screen and restore it on `pop`.
  - Use explicit `NextSelection*` only where the spatial heuristic fails: tech-tree columns and carousel ends.
  - Set `SelectionImageObject` to a themed focus ring (a 2 px stroke plus 4% scale-up) for every `Selectable`.
- **Button map:**
  - A = activate, B = back (`Router.pop`);
  - LB/RB = top-level tabs, LT/RT = sub-tabs or page;
  - X/Y = contextual secondary/tertiary actions shown in the footer hint bar;
  - Start (`ButtonStart`) is **reserved**: it always opens the Roblox menu and cannot be overridden (§3.3a). Our
    pause/options menu opens from an on-screen button and from B on a top-level screen (corrected by fact-check: was
    "Start = our pause menu", which contradicted R5's reserved-input rule);
  - View = scoreboard (see the caveat above);
  - D-pad mirrors the left stick.
- **Hint bar:** built from `InputAction.PreferredBinding` plus `GetImageForKeyCode`. Do not use `InputActionLabel` while
  it is beta.
- **Reachability test:** a Studio-only QA script BFS-walks `NextSelection` and the engine's directional results from the
  initial focus on every screen. It fails if any `Selectable` is unreachable. This enforces the console rule "reach all
  UI elements using these basic navigation controls".
- **Battle HUD:** not navigable. Consumables and commands use a thumbstick radial menu (hold Y).
- **Feedback:** UI audio ticks on focus change. Use the `HapticEffect` `UIClick` type only on confirm, off by default
  on phones.

### R4. Mobile layout (battle)

- **Orientation:** `LandscapeSensor` (default). Hide the default touch UI with `GuiService.TouchControlsEnabled=false`.
- **Movement:** a dynamic virtual stick that spawns where the left thumb touches, anywhere in the left 40% of the
  screen. It feeds the `Drive` action through a programmatic `InputBinding:Fire()`.
- **Aim:** drag on the right 60% of the screen (`TouchDelta`). Sensitivity is scaled by the zoom factor (R6.4).
- **Button sizes and positions** (logical px at UIScale 1, Small display):

| Element | Size | Position |
|---|---|---|
| Fire | **104 px** | bottom-right, 24 px from the safe-area edges |
| Sniper toggle | 72 px | above Fire |
| Ammo selectors | 3 × 56 px | in an arc left of Fire |
| Consumables | 3 × 56 px | right edge, vertical |
| Minimap | 160 px | top-left, tap to expand |
| Damage panel | 120 × 64 px | bottom-left, above the stick zone |

- **Touch-target minimum: 48 px.** This is the industry norm (Material 48 dp, Apple 44 pt) **[prior knowledge]**; the
  Roblox docs give no number.
- **Wiring:** every on-screen button is wired with `InputBinding.UIButton`, so touch, mouse and gamepad drive the same
  `InputAction`s.
- **Tablets** (`Small` display at ≥ 1000 px width): keep the same layout with UIScale capped at 1.2.

### R5. Input map (Input Action System)

**Contexts** (all created in code under `ReplicatedStorage/Inputs` on the client):

| Context | Priority | Sink | Enabled when |
|---|---|---|---|
| `Battle` | 2000 | true | in battle |
| `Sniper` | 2100 | true | in sniper mode |
| `Menu` | 3000 | true | a modal is open |
| `Spectate` | 2000 | true | spectating |
| `Garage` | 1500 | false | in the garage |

**Bindings.** Final keybind assignments belong to design docs `03`/`06`. `Esc`, `ButtonStart`, `F9`, `F11`, `F12` and
`PrintScreen` are reserved by Roblox and cannot be overridden; never bind them (corrected by fact-check: confirmed in
`CD/includes/default-bindings.md`, previously marked prior knowledge). Feature-conditional reservations (§3.3a) are
cleared by R12: disabling `PlayerList` frees `Tab`, and disabling `Backpack` frees `1`–`6`, `ButtonR1` and `ButtonR2`.
`LeftShift` (Sniper) collides with shift-lock while the default PlayerModule exists and
`StarterPlayer.EnableMouseLockOption` is `true` (the default), so R12.4 sets it to `false`.

| Action (type) | Keyboard & mouse | Gamepad | Touch |
|---|---|---|---|
| `Drive` (Direction2D) | `W`/`A`/`S`/`D` composite (`Up`/`Left`/`Down`/`Right`) | `Thumbstick1` (deadzone in sim) | virtual stick (programmatic `InputBinding:Fire`) |
| `Aim` (Direction2D) | `MouseDelta`, Scale 0.01 × sensitivity | `Thumbstick2`, **ResponseCurve 2.0** | `TouchDelta`, Scale 0.01 |
| `Fire` (Bool) | `MouseLeftButton` | `ButtonR2` (Pressed 0.5 / Released 0.2) | Fire button (`UIButton`) |
| `Sniper` (Bool, toggle) | `LeftShift` / wheel past min zoom | `ButtonL2` | button |
| `Zoom` (Direction1D) | `MouseWheel` | `DPadUp`/`DPadDown` while in sniper | `TouchPinch` |
| `TurretLock` (Bool, hold) | `MouseRightButton` | `ButtonL1` (hold) | — (auto) |
| `AmmoNext` / `Ammo1..3` (Bool) | `One`/`Two`/`Three` | `ButtonR1` cycles | buttons |
| `Consumable1..3` (Bool) | `Four`/`Five`/`Six` | hold `ButtonY` → radial | buttons |
| `Scoreboard` (Bool, hold) | `Tab` | `ButtonSelect` | button |
| `MapToggle` (Bool) | `M` | — (in scoreboard) | minimap tap |
| `Chat/Commands` (Bool) | `Return` / `T` | `DPadLeft` → command wheel | button |

**Glyphs:** read from `PreferredBinding`. React to `UserInputService:GetPropertyChangedSignal("PreferredInput")` to swap
the HUD layout (KBM, Gamepad or Touch). Ignore `MicroGamepad`: we do not support thumbstick-less remotes.

### R6. Camera

1. **Ownership.**
   - On client start, set `CameraType=Scriptable`.
   - Register one `BindToRenderStep("HD.Camera", Enum.RenderPriority.Camera.Value + 1, step)`. Input aggregation runs at
     `RenderPriority.Input`.
   - Every frame: set `Camera.CFrame` and `Camera.Focus` (the aim point, or the pivot).
2. **Arcade mode.**
   - Pivot = turret ring + (0, 1.5 studs, 0).
   - Orbit distance **15–75 studs** (5–25 m) on the wheel or pinch, default 36.
   - Pitch −35° to +60°.
   - Position smoothing `alpha = 1 − exp(−14·dt)`. Rotation is raw for mouse, and smoothed with `exp(−20·dt)` for the
     gamepad.
3. **Collision.**
   - `workspace:Spherecast(pivot, 0.6, desired − pivot, params)`. The params exclude all vehicle models, markers and
     effects, and use the `CameraBlock` collision group (foliage has `CanQuery=false`).
   - On a hit: distance = `hit.Distance − 0.3`, snapped in immediately. Ease back out at 12 studs/s.
   - One spherecast per frame.
4. **Sniper mode.**
   - Base FOV = the user's FOV setting (vertical 60–90, default 70). Zoom steps are ×2, ×4 and ×8, plus ×16/×25 when the
     vehicle's optics allow (design data). FOV follows the formula in §4 (the ×8 step is 10.0° at a 70° base).
   - Aim sensitivity is multiplied by `tan(FOV/2)/tan(FOV₀/2)`.
   - The scope overlay sits in the `World` ScreenGui (`ScreenInsets=None`).
   - The **own** vehicle is hidden from the gunner view by un-parenting its tier model while in sniper mode. This is one
     operation, instead of writing `LocalTransparencyModifier` on ~400 parts.
   - If the Battle place ever streams, the server sets `player.FrustumStreaming = Automatic` (§R7).
5. **Artillery view** (SPGs): a top-down Scriptable camera at 300–600 studs altitude, FOV 50.
6. **Effects.** Trauma-based shake (amplitude ≤ 0.6°) and a hit `BlurEffect` (Size ≤ 6, 0.25 s) under `Camera`. Both
   are disabled when `GuiService.ReducedMotionEnabled` or the "reduced effects" setting is on.

### R7. Battle place: streaming, map, environment

1. **`StreamingEnabled=false` on the Battle place by default**, with a hard memory gate. Reasons:
   - We need sight to roughly 2,100 studs (700 m at 3 studs/m). The default target radius is 1,024 studs (341 m).
   - We have no character, so streaming would need a server-maintained `ReplicationFocus` part per player.
   - Client prediction needs reliable local geometry.
   - Our tanks are client-built and never streamed, so streaming would only help map memory.
   - **Gate:** after map load on the baseline Android device (3–4 GB RAM), total client memory must be **≤ 1,100 MB**,
     with `GraphicsTexture` ≤ 150 MB and `GraphicsMeshParts` ≤ 120 MB.
   - **If the gate fails**, enable streaming with:
     - `StreamingTargetRadius=2048`;
     - `StreamOutBehavior=Opportunistic`;
     - `ModelStreamingBehavior=Improved`;
     - map chunks as `Atomic` models of about 64 studs;
     - a server-owned invisible focus part per player via `Player.ReplicationFocus`, moved to the vehicle each tick;
     - `Player.FrustumStreaming=Automatic`;
     - maps baked into the place file (Lune can write `.rbxm`) so static props can use `LevelOfDetail=SLIM`, which needs
       a published place and Team Create.
2. **Map budgets per map:**
   - ≤ **20,000** BaseParts, all anchored;
   - ≤ 150 unique mesh assets and ≤ 48 unique textures (≤ 1024², prefer 512²);
   - ≤ 1.5M triangles in total (the engine culls by frustum and occlusion);
   - prefer built-in materials.
   - Decoration props get `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `CastShadow=false` when smaller than
     4 studs, and `CollisionFidelity=Box`.
   - Cover-relevant meshes use `Hull`, and `PreciseConvexDecomposition` only for large irregular cover (rocks, ruins)
     where shells and LOS must match the silhouette.
3. **Terrain.**
   - Playable area ≤ 3,072 × 3,072 studs. Height ≤ 256 studs, which is ≤ 64 voxel layers.
   - That is 768 × 64 × 768 ≈ 37.7M voxels, written in **≥ 9 `WriteVoxels` calls** of ≤ 4,194,304 voxels (e.g.
     256 × 64 × 256 chunks).
   - Generate on the server during battle preload, while players are still teleporting, yielding between chunks.
   - Clients wait for a `MapReady` attribute **and** spot-check sample heights with 8 downward raycasts before leaving
     the loading screen.
   - **`Terrain.Decoration=false`.** It is NotScriptable, and client-only grass could hide tanks inconsistently with the
     server's analytic concealment model (fairness).
4. **Heightfield.**
   - Bake a per-map `buffer` heightfield: f32, 1 sample per 2 studs, 1,536² samples ≈ 9.4 MB.
   - Bake it on both server and client from the same terrain recipe. `World:groundAt` then becomes a native bilinear
     lookup instead of a raycast.
   - Structures and bridges fall back to `World:raycast`.
   - This removes about 240 ground raycasts per tick (30 vehicles × 8 contact samples).
5. **Lighting** (place properties):
   - `LightingStyle=Realistic`.
   - **`PrioritizeLightingQuality=false`**: view distance matters more than shadow quality in a spotting game.
   - `GlobalShadows=true`, `ShadowSoftness=0.2`.
   - `Atmosphere.Density` ≤ 0.30 and `Haze` ≤ 1.5, for long-range readability.
   - Post FX under `Lighting`: `ColorCorrection` (±0.1), `Bloom` (Intensity ≤ 0.4, Threshold ≥ 1.5), `SunRays`
     (Intensity ≤ 0.08).
   - No `DepthOfField` in battle; it hurts target readability. DOF is allowed in the garage.
   - `Clouds` (under Terrain) is allowed on PC and console only. Disable it via a client setting where clients can
     toggle `Clouds.Enabled`.
6. **Draw-distance risk.** The engine reduces draw distance at low quality levels and does not document the values.
   - **Spotted enemies must always have a 2D marker** in the `Markers` gui.
   - The 3D model is cosmetic beyond about 1,000 studs.

### R8. Vehicle rendering and LOD

1. **Templates.** `VehicleRenderer` builds **one template per vehicle definition, per LOD tier** from the Blueprint, at
   battle load or first sight. Each entity is a clone.
2. **Rig.**

   ```
   Model "Vehicle_<id>"
     Root (Part, Anchored, Transparency 1, CanCollide/CanQuery/CanTouch=false, 1×1×1)
     LOD0 / LOD1 / LOD2 (Model; exactly one parented under Vehicle at a time)
       Hull parts            -- WeldConstraint → Root
       TurretBase            -- Motor6D(Part0=Root, C0 = turret-ring pivot)
         turret parts        -- WeldConstraint → TurretBase
         GunMantlet          -- Motor6D(Part0=TurretBase, C0 = trunnion)
           gun parts         -- WeldConstraint → GunMantlet
       TrackL/TrackR, wheels -- WeldConstraint → Root (wheel spin is fake: texture/rotation only at LOD0)
   ```

   - Moving the anchored `Root` moves the whole implicitly anchored assembly (§5.1).
   - **Per frame:** one `workspace:BulkMoveTo(roots, cframes, Enum.BulkMoveMode.FireCFrameChanged)` for all visible
     vehicles. Then write `Motor6D.Transform` for turret yaw and gun pitch, only when the change exceeds 0.05°.
   - **[Medium: verify in Studio that `Motor6D.Transform` updates on an anchored-root assembly without an Animator. The
     fallback is to write `C0`.]**
3. **Visual parts.**
   - `Anchored=false` (except Root), `Massless=true`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`,
     `AudioCanCollide=false`.
   - `CastShadow=true` only on the ≤ 12 largest hull and turret parts.
   - Use ≤ 4 materials (`Metal`, `SmoothPlastic`, `DiamondPlate`, `Rubber`) and ≤ 6 colors per vehicle, to maximize
     instancing.
   - The Armor Inspector uses `ArmorGeometry`, never parts, so no part needs `CanQuery`.
4. **LOD tiers.** Selection distance = camera distance ÷ current zoom factor, with 10% hysteresis and at most one switch
   per vehicle every 0.25 s. A tier switch reparents one tier Model: one operation instead of hundreds of property
   writes.

| Tier | Content | Parts | Distance (studs) | Max simultaneous |
|---|---|---|---|---|
| LOD0 | all Blueprint layers incl. `Detail`; emblem/inscription Decals | ≤ 400 | < 150 | **4** on High, 3 Medium, 2 Low (nearest; the rest demoted) |
| LOD1 | `Armor` + `Visual` merged primitives, no `Detail`, no Decals | ≤ 80 | 150–600 | 12 on High, 8 Medium, 3 Low |
| LOD2 | silhouette: hull, turret, gun, 2 tracks (+ ≤ 11 boxes) | ≤ 16 | 600–2,400 | unlimited (≤ 29) |
| LOD3 | model hidden; 2D marker only | 0 | > 2,400, or when the engine culls | — |

   - **Worst case (High), all 30 vehicles visible, own vehicle in one of the 4 LOD0 slots:** 4×400 + 12×80 + 14×16 =
     **2,784 vehicle parts**, under the 3,000 budget (corrected by fact-check: the earlier 4×400 + 12×80 + 13×16 =
     2,768 counted only 29 vehicles).
   - **Low preset caps (corrected by fact-check):** LOD0 ≤ 2 and **LOD1 ≤ 3**, giving 2×400 + 3×80 + 25×16 = **1,440**,
     inside the R11 mobile budget of 1,500. With LOD1 left at 12, the Low worst case was 2×400 + 12×80 + 16×16 = 2,016,
     which broke that budget. Medium uses LOD0 ≤ 3 and LOD1 ≤ 8.
   - The own vehicle is always LOD0, and is hidden in sniper view.
5. **Wrecks.** Swap to a darkened LOD1 wreck variant. Keep at most 10 wrecks at LOD1, then LOD2.
6. **Markers.**
   - One pooled-Frame overlay updated in `PreRender` with `WorldToViewportPoint`, at most 29 entries.
   - No per-vehicle `BillboardGui`. This avoids the adorn-pass cost and allows clamping markers to the screen edge.
7. **Highlights.**
   - Two persistent instances: `TargetOutline` (aimed enemy, `DepthMode=Occluded`) and `AllyOutline` (optional,
     `AlwaysOnTop`).
   - Retarget them by changing `Adornee`; never create or destroy per frame.
   - A Highlight applies to a single `Adornee` instance. An ally outline covering several allies at once therefore
     needs either one instance per ally (counted against the cap below) or a shared parent instance as `Adornee`
     (verify in Studio) (clarified by fact-check).
   - Never more than 16 in use on PC and 2 on mobile (R11), far below the 255 cap. Disabled Highlights still hold a slot,
     which does not matter at these counts.
8. **Later options** (not v1):
   - Replace road wheels and sprockets with one uploaded `MeshPart` wheel, so identical `MeshContent` instances collapse
     into single draw calls.
   - `EditableMesh` merging of LOD1 is blocked by the 13+ and ID-verification requirement, memory budgets and the
     20k-triangle cap.

### R9. Effects pooling

1. **Pool setup.** At battle load, create one invisible anchored `FxAnchor` part at the origin. Under it, create pools of
   `Attachment`s carrying pre-configured emitters (`Enabled=false`).
   - **To play an effect:** set `attachment.WorldCFrame`, then call `emitter:Emit(n)`.
   - **No property writes** on emitters in the hot path (the docs warn about this).
   - Return the attachment to the pool after `maxLifetime + 0.1 s`.
2. **Pool sizes** (High / Low quality):

| Effect | Kind | High | Low |
|---|---|---|---|
| Muzzle flash + blast | Emit bursts + pooled `PointLight` (Shadows=false, Range ≤ 12 studs, 60 ms) | 16 | 8 (no light) |
| Muzzle smoke | Emit | 16 | 6 |
| Tracer | `Beam` (untextured, LightEmission 1) between two pooled Attachments | 48 | 24 |
| Impact on armor (pen / non-pen / ricochet) | Emit | 24 | 12 |
| Impact on ground (dirt, stone, wood, water) | Emit | 4 × 12 | 4 × 6 |
| HE / ammo-rack explosion | Emit + light | 12 | 6 |
| Vehicle fire / burning wreck | Rate-based | 8 | 4 |
| Smoke screen | Rate-based | 4 | 2 |
| Track dust | Rate-based, 2 per visible vehicle at LOD ≤ 1 | 32 | 0–8 |
| Exhaust | Rate-based, 1 per vehicle at LOD ≤ 1 | 16 | 0 |

3. **Particle governor.**
   - Estimate live particles as Σ(rate × mean lifetime) plus the burst counts.
   - Caps: **600** (Low/mobile), **1,200** (Medium), **2,000** (High).
   - Shed effects in this order: exhaust → dust → muzzle smoke → ground impacts of other players.
   - Never shed the local player's tracers, impacts or hit feedback.
   - Rate-based emitters stay ≤ 100/s even on PC, which keeps parity with the mobile limit.
4. **Textures.**
   - v1 uses the built-in `rbxasset://textures/particles/*` set (`fire_main.dds`, `smoke_main.dds`,
     `explosion01_*.dds`, `sparkles_main.dds`, `SquareParticle.png`) through `AssetResolver` fallbacks.
   - Our own flipbooks replace them once they are uploaded (≤ 512², `Grid4x4`, ≤ 30 fps).
   - Avoid many unique flipbooks: clients disable them under memory pressure.
5. **Lights.** At most **6** simultaneous dynamic effect lights on PC and **0** on Low. Never `Shadows=true` on effect
   lights.

### R10. Audio

1. **New Audio API only**, as in `06` §27.
   - `SoundService.DefaultListenerLocation=None`. Its read/write security is `PluginSecurity`, so set it as a place
     property in the Rojo project; game scripts cannot change it at runtime (added by fact-check).
   - The client creates **three `AudioListener`s parented to the Camera**, one per `AudioInteractionGroup`:
     - `World`: other vehicles, shots, impacts;
     - `Own`: own engine, gun and track;
     - `Ambience`.
   - Each listener chains: `Wire` → bus `AudioFader` → master `AudioCompressor` → `AudioLimiter` (`MaxLevel −1 dB`) →
     `AudioDeviceOutput`.
   - 2D players (UI, music, voice-over) wire straight into their bus fader.
2. **Voice manager.**
   - Pool "voices" of (`AudioPlayer`, `AudioEmitter`, `Wire`).
   - Global cap: **32** on PC and console, **20** on mobile.
   - Category caps: engines 6 nearest, shots 8, impacts 8, UI 4, voice-over 2, ambience 2.
   - When full, steal the voice with the lowest `priority × audibility × recency`, where audibility comes from
     `AudioEmitter:GetAudibilityFor(listener)`.
   - Overlapping one-shots use separate voices; one `AudioPlayer` is one playhead.
3. **Attenuation.** Use `SetDistanceAttenuation` curves with about 8 points. The `DistanceAttenuationMode` presets are
   only two months old in the docs (2026-08-11), so do not depend on them yet.
   - Gunfire is audible to about 2,400 studs.
   - Engines are audible to about 450 studs.
   - Use angle curves for muzzle and exhaust directivity.
4. **Acoustic simulation: off in v1** (`SoundService.AcousticSimulationEnabled=false`). Its CPU cost is undocumented.
   - Fake occlusion with an `AudioFilter` low-pass driven by our own sight test, at most 4 per second per voice.
   - If it is ever enabled, keep `AudioCanCollide=false` on all vehicle and decoration parts.
5. **Loading and memory.**
   - Preload the battle bank with `ContentProvider:PreloadAsync` during the loading screen.
   - Keep the `Sounds` memory budget ≤ 48 MB on the client.
   - Upload from an **ID-verified** account (unverified accounts get 100 per 30 days via import, or 10 per month per the
     Open Cloud page). Consolidate variants into round-robin sets of 3–4, so the total bank is ≤ 250 assets.
   - Budget the Open Cloud pipeline at 100 per month (≈ 3 months for the full bank) until a real run shows the 2,000
     per 30 days in the newer audio guide applies to Open Cloud; if uploads are refused at 100, bulk-import the rest
     through the Asset Manager, which the audio guide puts under the 2,000 quota (corrected by fact-check: §6).

### R11. Performance budgets

**Client targets:**
- Frame rate: 60 FPS on PC and console. **≥ 30 FPS sustained for 15 minutes** on the baseline Android device, which
  also covers the thermal-throttling test in the docs.
- Our Luau per frame: **≤ 3 ms** on PC/console, **≤ 6 ms** on baseline mobile. Measure it with `debug.profilebegin`
  labels per controller.

**Per-platform budgets:**

| Budget | Baseline mobile (Low) | PC / console (High) | Basis |
|---|---|---|---|
| Draw calls (scene) | ≤ 1,000 | ≤ 2,500 | the docs' example baseline method |
| Triangles on screen | ≤ 1.0 M | ≤ 3.0 M | same |
| Vehicle parts rendered | ≤ 1,500 (LOD0 max 2, LOD1 max 3; corrected by fact-check) | ≤ 3,000 (LOD0 max 4, LOD1 max 12) | R8 |
| Map BaseParts (total) | ≤ 20,000 | ≤ 20,000 | R7 |
| Live particles | ≤ 600 | ≤ 2,000 | R9; emitter cap 100/s on mobile |
| Active rate-based emitters | ≤ 24 | ≤ 64 | R9 |
| Dynamic effect lights | 0 | ≤ 6, no shadows | §5.3 |
| Highlights in use | ≤ 2 | ≤ 16 | first one ≤ 1 ms GPU on mobile |
| Concurrent voices | ≤ 20 | ≤ 32 | R10 |
| ScreenGuis enabled in battle | ≤ 5 | ≤ 5 | GuiEffect cost |
| CanvasGroups alive | ≤ 1 | ≤ 3 | texture memory |
| ViewportFrames visible | ≤ 2 | ≤ 6 (garage carousel only) | WorldModel guidance; cost undocumented |
| Client spatial queries per frame | ≤ 16 | ≤ 32 | camera 1, aim 2, misc |
| Client memory after map load | ≤ 1,100 MB | ≤ 2,500 MB | R7 gate; 60% of Android devices have 2–4 GB |
| Textures / Sounds memory | ≤ 150 MB / ≤ 48 MB | ≤ 300 MB / ≤ 96 MB | `PlaceMemory` labels |

**Server, 30 Hz battle tick, 30 vehicles (15v15), up to 120 shells in flight:**
- Simulation time: **≤ 6 ms average, ≤ 12 ms p99** per tick. Heartbeat is 60 Hz, so a 30 Hz tick should fit inside one
  16.7 ms frame with room for replication.
- World queries: **≤ 600 per tick**, made up of:
  - projectiles ≤ 120 casts;
  - vehicle obstacle `sweepBox` ≤ 60 (2 per vehicle);
  - spotting ≤ 400 sight rays (cap per `02`; typically 50–90);
  - ground via the heightfield, so about 0 raycasts, plus ≤ 30 fallback raycasts on structures.
- Memory: with peak 30 players the server has 9.18 GiB (6.25 GiB + 30 × 100 MiB). Keep usage **below 4.5 GiB**,
  including the map and heightfield.
- Measurement protocol: server MicroProfiler dumps (60 frames) every 2 minutes of a 30-bot soak test.
  `debug.profilebegin` labels per tick system. Fail CI-like soak checks when averages exceed the budget.

### R12. Character-less bootstrap checklist

1. `Players.CharacterAutoLoads=false` (place property, set in the Rojo project). Never call `LoadCharacterAsync` in
   battle or hub.
2. Nothing lives in `StarterGui`. `Client/Main` creates all ScreenGuis under `PlayerGui` (`ResetOnSpawn=false`).
3. Disable core UI with `StarterGui:SetCoreGuiEnabled`: `Backpack`, `Health`, `EmotesMenu`, `PlayerList` (we have our
   own scoreboard). Chat stays enabled on PC and mobile; on console, disable the chat window.
4. Remove the default controls. Prefer `Workspace.PlayerScriptsUseInputActionSystem=Enabled` plus
   `StarterPlayer.CreateDefaultPlayerModule=false`. Otherwise use:
   - `DevComputerMovementMode=Scriptable`, `DevTouchMovementMode=Scriptable`;
   - `GuiService.TouchControlsEnabled=false`;
   - `UserInputService.ModalEnabled=true`;
   - `StarterPlayer.EnableMouseLockOption=false`, so `LeftShift` (Sniper, R5) does not toggle shift-lock (added by
     fact-check; §3.3a).
5. `CameraType=Scriptable` set on start, and re-asserted on `CurrentCamera` changes.
6. Audio listener via R10. `DefaultListenerLocation=None`.
7. Team chat bubbles over vehicles: `TextChatService:DisplayBubble(vehicleRootPart, text)` on the client, for allies
   only.
8. If streaming is ever enabled: a server-side `ReplicationFocus` part per player (R7.1).
9. `Workspace.PlayerCharacterDestroyBehavior` enabled, plus Trove cleanup per player.

### R13. Settings exposed to players

- Graphics preset: Low/Medium/High.
  - Drives the R9 particle caps, LOD0 count (2/3/4), LOD1 count (3/8/12; added by fact-check, see R8.4), track dust,
    exhaust, effect lights, clouds and post-FX intensity.
- Reduced effects. FOV (60–90). UI scale (0.8–1.2).
- Camera sensitivity: separate values for arcade, sniper, gamepad and touch.
- Invert Y. Haptics on/off.
- Audio: 6 buses.
- Colorblind palette (see `06`).
- `PreferredTextSize` and `ReducedMotionEnabled` are honored automatically; do not duplicate them as settings.

### R14. Verification plan

- **Baseline devices:** one 3–4 GB Android (Moto G05-class), one mid iPhone, one Xbox, and a PC with a gamepad.
  This mirrors the docs' guidance.
- **Per milestone:**
  - client MicroProfiler captures in a 15v15 bot battle at the most effect-heavy moment;
  - Dev Console memory after map load;
  - a 15-minute thermal run;
  - a controller reachability test (R3);
  - a touch-target audit (R4).
- **Studio-only checks for things that cannot be tested in Lune:**
  - `BulkMoveTo` plus `Motor6D` behavior;
  - `Spherecast` camera collision;
  - `GetImageForKeyCode` glyphs;
  - safe-area behavior on notched device emulation;
  - `TouchControlsEnabled`;
  - `CreateDefaultPlayerModule`;
  - whether `ButtonSelect` reaches our `Scoreboard` action with `AutoSelectGuiEnabled=false`, and which button
    activates a selected `GuiButton` (the default-bindings table lists `ButtonR2`; R3 assumes A) (added by fact-check).

---

## Open questions / uncertain items

1. **Native codegen on clients.** The docs (rev. 2026-07-07) describe server scripts only. Is `--!native` honored by
   clients at all? Impact: client prediction cost. Default: assume no gain.
2. **Raycast, Spherecast and Blockcast cost per call** on Roblox servers is undocumented. Our 600 queries per tick budget
   must be validated by MicroProfiler. If one query costs more than about 8 µs on average, cut the spotting cap from
   400 to 200 rays per tick.
3. **Polyphony cap.** Neither the new Audio API nor `Sound` documents a maximum number of simultaneous voices. Our 20/32
   caps are self-imposed.
4. **Light limits.**
   - Current docs give **no maximum `Range`** for Point/Spot/Surface lights and no light-count cap. Historically the
     Range cap was 60 studs **[prior knowledge, Low]**.
   - Shadow-casting light limits per quality level are undocumented.
5. **Draw distance per graphics quality level** is undocumented. Tanks beyond it disappear; markers (R7.6) mitigate
   this.
6. **ViewportFrame cost.** The docs give no numbers on re-render frequency or GPU cost. This limits the garage carousel
   design: our default is ≤ 6 visible, static camera, LOD1 models.
7. **`Motor6D.Transform` on an anchored-root, Animator-less assembly** (R8.2). Expected to work; verify. The fallback is
   writing `C0`.
8. **Part instancing granularity.** Do Parts of identical shape, material and color batch like MeshParts? The docs only
   mention "geometry that uses instanced rendering such as parts". Measure draw calls with 30 tanks at LOD1.
9. **Audio upload quota conflict.** `audio/assets.md` says 2,000 per 30 days (ID-verified); the Open Cloud guide says
   100 per month (ID-verified) and 10 (unverified). The audio guide's figure is the newer one (raised from 100/10 on
   2026-03-17; the Open Cloud text dates from 2025-02-28), so the Open Cloud page is probably stale (corrected by
   fact-check). Confirm with a real Open Cloud upload run; until then budget 100 per month there (R10.5).
10. **Type functions and the new solver.** The rollout state of `UseNewLuauTypeSolver=Default` is not stated in the
    docs. Keep shipped code solver-agnostic.
11. **Terrain throughput.** `WriteVoxels` and `FillBlock` speed is undocumented, and so is the bandwidth and time to
    replicate a 3,072² terrain to joining clients. Measure during R7.3. If it is too slow, shrink the terrain footprint
    and use parts for flat ground.
12. **Reserved buttons.** Mostly answered (corrected by fact-check: it *is* in the local docs).
    `CD/includes/default-bindings.md` reserves `Esc`/`ButtonStart` (Roblox menu), `F9`, `F11`, `F12` and `PrintScreen`
    outright, plus feature-conditional keys (§3.3a). Still open: the Xbox guide and PlayStation buttons (system-level),
    and the exact `ButtonSelect` behavior with `AutoSelectGuiEnabled=false` (R3, R14).
13. **Console text-size minimum.** The docs give a 9 px floor for `MinTextSize` but no console 10-ft minimum. Our
    18 px Large-display floor is a design choice.
14. **TV-safe margin percentage** is not given. Our 5% is a design choice.
15. **Frustum streaming maturity.** It was documented only on 2026-10-01. Use it only if the R7 memory gate forces
    streaming.
16. **Beta UI features.** When will per-corner `UICorner` radii and the Improved UIStrokes properties leave beta? Track
    the release notes.
17. **SLIM for runtime-built content.** The docs exclude models modified at runtime. Tanks will never get SLIM, and
    runtime-built maps probably will not either. Only baked, published, static map models qualify.
18. **`PlayerModule:GetControls()` API** is not in the local docs. Prefer `CreateDefaultPlayerModule=false` and the
    documented `TouchControlsEnabled`.
19. **`vector` vs `Vector3` identity** on Roblox is implied, not stated. It matters for typed code shared with Lune.

---

## Sources (local doc paths and fetched files)

**Luau:**
- `CD/reference/engine/globals/LuaGlobals.yaml`
- `CD/scripting/module.md`
- `CD/luau/type-checking.md`
- `CD/luau/native-code-gen.md`
- `CD/scripting/multithreading.md`
- `CD/scripting/scheduler.md`
- `CD/reference/engine/libraries/{buffer,vector,task}.yaml`
- `CD/reference/engine/datatypes/{SharedTable,Vector3,Font}.yaml`
- `CD/reference/engine/classes/{Workspace,WorldRoot,Actor}.yaml`
- Luau RFCs: `user-defined-type-functions.md`, `new-require-by-string-semantics.md`, `vector-library.md`
  (raw.githubusercontent.com/luau-lang/rfcs/master/docs/)

**UI:**
- `CD/ui/{on-screen-containers,list-flex-layouts,size-modifiers,appearance-modifiers,rich-text,viewport-frames,2D-paths,ui-drag-detectors}.md`
- `CD/ui/styling/{index,css-comparisons}.md`
- `CD/includes/ui/screen-insets.md`
- `CD/reference/engine/classes/{ScreenGui,LayerCollector,GuiService,GuiObject,GuiBase2d,UIListLayout,UIFlexItem,UIGridLayout,UIGridStyleLayout,UIPageLayout,UIScale,UIPadding,UICorner,UIStroke,UIGradient,CanvasGroup,ViewportFrame,WorldModel,BillboardGui,SurfaceGui,SurfaceGuiBase,Highlight,TextLabel,StyleQuery,Path2D,ScrollingFrame,GamepadService,StarterGui}.yaml`
- `CD/effects/highlighting.md`
- `CD/production/publishing/{console-guidelines,accessibility,adaptive-design}.md`
- `CD/projects/cross-platform.md`

**Input:**
- `CD/input/{index,input-action-system,gamepad,mobile}.md`
- `CD/includes/default-bindings.md` (reserved inputs; added by fact-check)
- `CD/reference/engine/classes/{UserInputService,ContextActionService,HapticService,HapticEffect,InputContext,InputAction,InputBinding,StarterPlayer}.yaml`
- `CD/reference/engine/enums/{PreferredInput,InputActionType,HapticEffectType,DisplaySize,PreferredTextSize,SelectionBehavior}.yaml`

**Camera:**
- `CD/workspace/camera/index.md`
- `CD/reference/engine/classes/{Camera,RunService}.yaml`
- `CD/reference/engine/enums/RenderPriority.yaml`
- `CD/workspace/raycasting.md`

**Rendering and performance:**
- `CD/performance-optimization/{design,identify,improve,test-on-hardware}.md`
- `CD/performance-optimization/microprofiler/{index,tag-table}.md`
- `CD/workspace/streaming/{index,techniques,slim,frustum}.md`
- `CD/physics/{assemblies,units}.md`
- `CD/environment/{lighting,atmosphere,clouds,post-processing-effects}.md`
- `CD/effects/{light-sources,particle-emitters,beams,trails}.md`
- `CD/parts/terrain.md`
- `CD/art/modeling/texture-specifications.md`
- `CD/reference/engine/classes/{BasePart,MeshPart,Model,Lighting,Terrain,ParticleEmitter,Beam,Trail,Fire,Smoke,Sparkles,Explosion,EditableImage,EditableMesh,AssetService,BuoyancySensor,Player}.yaml`
- `CD/reference/engine/enums/{ModelLevelOfDetail,ModelStreamingMode,RenderFidelity,CollisionFidelity,Material,LightingStyle,FrustumStreamingMode}.yaml`

**Audio:**
- `CD/audio/{index,objects,effects,assets}.md`
- `CD/sound/{index,objects,groups,dynamic-effects}.md`
- `CD/reference/engine/classes/{AudioPlayer,AudioEmitter,AudioListener,Wire,AudioFader,AudioFilter,AudioEqualizer,AudioCompressor,AudioReverb,AudioLimiter,SoundService,Sound}.yaml`
- `CD/reference/engine/enums/{DistanceAttenuationMode,AudioFilterType,AudioSimulationFidelity}.yaml`

**Assets:**
- `CD/projects/assets/index.md`
- `CD/cloud/guides/usage-assets.md`
- `CD/audio/assets.md`
- Roblox client content listing: `github.com/MaximumADHD/Roblox-Client-Tracker` @ `fcd6994` (`textures/particles/*`,
  `textures/ui/Controls/DefaultController/*`)

**Character-less:**
- `CD/reference/engine/classes/{Players,Player,TextChatService,StarterGui,StarterPlayer}.yaml`
- `CD/reference/engine/enums/CoreGuiType.yaml`

**History:**
- `git log -S/-G` over `github.com/Roblox/creator-docs` (commits cited inline: `7da18231` 2026-04-03 Highlight 31→255,
  `ef278ba8` 2025-05-19 require rewrite, `d6b68cfd` 2026-01-13 `@game`, `55dea496` 2025-08-06 IAS guide)

**Libraries:**
- `git ls-remote --tags` for `dphfox/Fusion` (v0.3-beta), `centau/vide` (0.4.1), `jsdotlua/react-lua` (v17.2.1),
  `Roblox/roact` (v1.4.4)

---

## Verification log

Adversarial fact-check, 2026-10-05. `CD/` = the local creator-docs snapshot (`9f840b1`, 2026-10-02). History commits
are from `git log -S` on that repository. WebSearch was unavailable (session budget spent) and luau.org, DevForum and
create.roblox.com are proxy-blocked, so web-only claims could not be re-checked.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | String `require`: `./` → `script.Parent`, `../` → `script.Parent.Parent`, `@self/` → `script`, `@game/` → `game`; non-blocking; forbidden in a desynchronized phase; `@self` added 2025-05-19, `@game` 2026-01-13 | Confirmed | `CD/reference/engine/globals/LuaGlobals.yaml` L615–625; `CD/scripting/multithreading.md` L53; commits `ef278ba8` (2025-05-19), `d6b68cfd` (2026-01-13) |
| 2 | Native codegen is documented for server scripts; limits 64K instructions/block, 32K blocks/function, 1M instructions/module, global memory cap; `debug.dumpcodesize()` in Server view | Confirmed | `CD/luau/native-code-gen.md` L6, L109–154 |
| 3 | R1.2: native codegen specializes on `Vector3` **and `CFrame`** annotations | Corrected | `CD/luau/native-code-gen.md` L61–80 names only `Vector3` ("especially recommended to annotate Vector3 arguments"); no `CFrame` mention |
| 4 | Parallel safety: `Raycast`, `Spherecast`, `Blockcast`, `GetPartBoundsInBox/InRadius`, `GetPartsInPart` Safe; `Shapecast`, `BulkMoveTo`, `StepPhysics` Unsafe | Confirmed | `thread_safety` fields parsed from `CD/reference/engine/classes/WorldRoot.yaml` |
| 5 | `Spherecast` radius ≤ 256, distance ≤ 1,024, misses initially intersecting parts; `Blockcast` size ≤ 512, distance ≤ 1,024; `Raycast` ≤ 15,000 studs | Confirmed | `WorldRoot.yaml` L96, L103, L276, L1093, L1270–1305 |
| 6 | `Highlight`: 255 simultaneous on client (raised from 31); first one up to 1 ms GPU on mobile; add/remove triggers rebuild | Confirmed (nuance added: disabled Highlights still take a slot) | `Highlight.yaml` L49–57; `CD/effects/highlighting.md` L32, L147–160; commit `7da18231` (2026-04-03, "31 --> 255") |
| 7 | `Camera.FieldOfView` clamped 1–120°, default 70°; `RenderPriority` First 0 / Input 100 / Camera 200 / Character 300 / Last 2000; zoom FOVs 38.59/19.86/10.00/5.01/3.21° and 16:9 conversions | Confirmed (math recomputed) | `Camera.yaml` L268–269; `CD/reference/engine/enums/RenderPriority.yaml`; recomputed with `2·atan(tan(35°)/M)` |
| 8 | Example budget "below 1,000 draw calls and 1,000,000 triangles"; shadows not performed below quality level 4; `RenderFidelity.Automatic` switches at 250/500 studs | Confirmed | `CD/performance-optimization/design.md` L14; `improve.md` L418; `microprofiler/tag-table.md` L230, L267; `enums/RenderFidelity.yaml` L26–34 |
| 9 | SLIM needs `StreamingEnabled`, a place saved to Roblox and Team Create; static models only, no Humanoids | Confirmed | `CD/workspace/streaming/slim.md` L42–44, L214–222, L248–252 |
| 10 | `ParticleEmitter`: ≤ 400 particles/s per emitter (100/s on mobile); `Lifetime` capped at 20 s; flipbook ≤ 30 fps; flipbooks dropped on low memory | Confirmed | `CD/effects/particle-emitters.md` L194, L207, L405, L420 |
| 11 | `EditableImage`: published use needs 13+ age and ID verification plus dashboard toggle; ≤ 1024×1024; one displayed update per frame. `EditableMesh`: 60,000 vertices / 20,000 triangles | Confirmed | `EditableImage.yaml` L35, L41–45, L88; `EditableMesh.yaml` L289 |
| 12 | Android ≈ 65%, 60% of those 2–4 GB; client FPS cap 60 (240 on Windows); server heartbeat cap 60; server memory `6.25 GiB + 100 MiB × peak players` (= 9.18 GiB at 30); investigate crash rate > 2–3% | Confirmed | `CD/performance-optimization/test-on-hardware.md` L27–31; `identify.md` L77, L91, L112–114, L133 |
| 13 | Audio quota: "2,000/30 days (audio guide) vs 100/month verified, 10 unverified (Open Cloud) — plan for the lower figure" | Corrected | `CD/audio/assets.md` L30–39 (lists Open Cloud as an import channel); commit `5690416a` (2026-03-17) raised the audio guide from 100/10 to 2,000/100; Open Cloud row unchanged since `e5f98f48` (2025-02-28), `CD/cloud/guides/usage-assets.md` L76–79. Open Cloud page is likely stale; Medium confidence |
| 14 | Reserved inputs are "not in the local docs" / "[prior knowledge]" | Corrected | `CD/includes/default-bindings.md`: `Esc`/`ButtonStart`, `F9`, `F11`, `F12`, `PrintScreen` reserved and cannot be overridden; `Tab`, `/`, `` ` ``, `0`–`9`, `ButtonSelect` etc. reserved while their feature is on; `Shift` = shift-lock while `EnableMouseLockOption` is true |
| 15 | "46 `Enum.Material` values" | Corrected (45, counting `Air` and `Water`) | `CD/reference/engine/enums/Material.yaml` (45 items) |
| 16 | `--!native` gives no benefit on clients | Unverified | Docs are silent (`native-code-gen.md` says "server-side" only); web sources unreachable. Kept as Open question 1 |

**Also spot-checked and confirmed:** `buffer` ≤ 1 GiB, little-endian, copied across Actors (`buffer.yaml` L23–43);
`SharedTable` keys < 2³²; the "64 Actors and more" advice (`multithreading.md` L333); `ContextActionService` max 7
touch buttons (`ContextActionService.yaml` L199); `InputBinding` `PressedThreshold` 0.5, `ReleasedThreshold` 0.2,
`ResponseCurve` 1–10 (`InputBinding.yaml`); IAS `Priority=2000` + `Sink` (`input-action-system.md` L33);
`InputActionLabel` beta (`input-action-system.md` L484); `ScreenInsets`/`SafeAreaCompatibility`/`IgnoreGuiInset`
semantics (`ScreenGui.yaml`); `StreamingTargetRadius` 1024 and `StreamingMinRadius` 64 (`Workspace.yaml`);
`Player.FrustumStreaming` server-only (`CD/workspace/streaming/frustum.md` L39); `WriteVoxels` ≤ 4,194,304 voxels at
resolution 4 and `Terrain.Decoration` NotScriptable (`Terrain.yaml` L27–37, L792–803); `Lighting.Technology`
superseded by `LightingStyle` + `PrioritizeLightingQuality` (`Lighting.yaml`); `AudioEmitter` attenuation curves ≤ 400
points, bounds default `[4, 10000]` (`AudioEmitter.yaml` L149, L457); server MicroProfiler dumps ≤ 60 frames, ≤ 4 s
delay (`microprofiler/index.md` L232); all 28 `textures/particles/*` files and the `DefaultController` glyphs exist in
`MaximumADHD/Roblox-Client-Tracker` @ `fcd6994` (`git ls-tree`); library tags Fusion `v0.3-beta`, Vide `0.4.1`,
react-lua `v17.2.1`, Roact `v1.4.4` (`git ls-remote`); type-functions RFC status "Implemented" and tied to the new solver
(raw.githubusercontent.com/luau-lang/rfcs). Arithmetic re-run: voxel count 768 × 64 × 768 = 37,748,736 = 9 × 4,194,304;
heightfield 1,536² × 4 B = 9.44 MB.

**Fixes to the Implementation recommendations (internal contradictions):**
- **R3 vs R5:** R3 mapped Start to our pause menu while R5 forbade binding the platform menu button. `ButtonStart` is
  reserved, so R3 now opens the pause menu from the UI and B.
- **R5 vs R12:** `LeftShift` (Sniper) collided with default shift-lock. R12.4 now sets `EnableMouseLockOption=false`.
- **R8.4 vs R11:** the Low preset kept LOD1 at 12, so the mobile worst case was 2,016 parts against a 1,500 budget.
  Low now caps LOD1 at 3 (1,440 parts), and R13 exposes the LOD1 count. The High worst case is now counted over 30
  vehicles (2,784, previously 2,768 over 29).
- **R8.7 vs R11:** "two persistent instances" vs "≤ 16 in use" is clarified: one Highlight covers one `Adornee`.
- **Summary 10 vs R6.1:** render-step priority is aligned to `Camera.Value + 1`.
- **R1.2:** `CFrame` annotation specialization is removed (not documented).
- **R10.1:** `DefaultListenerLocation` is `PluginSecurity`, so it is set as a place property.
- **R10.5 / Open question 9:** the quota guidance is updated to match row 13.
