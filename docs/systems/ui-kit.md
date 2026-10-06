# UI kit — developer guide

The kit is the client UI layer every HULLDOWN screen is built on: `src/ReplicatedStorage/Client/UI/Kit` (core +
components), `Client/UI/Icons` (icon registry and primitive glyphs), `Shared/Assets` (asset manifest + resolver) and
`Client/UI/Dev/KitGallery` (every component in every state). The visual rules come from `docs/design/brand-art.md`,
the screen rules from `docs/design/ui-ux.md`; this page is the practical how-to.

```lua
local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")   -- everything: Kit.State, Kit.Button, ...
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State") -- single modules (use these for types)
```

| Module | What it is for |
|---|---|
| `State` | Reactive values (`Value`, `Computed`, `effect`, `observe`, `list`, `batch`) that UI binds to |
| `Create` | Instance builder: props (static or State), children, events, cleanup |
| `Theme` / `Tokens` | Colour/typography/spacing/motion tokens and the accessibility settings |
| `Layout` | Root scaling, Regular/Compact/TV, safe area, list/grid/padding helpers |
| `InputMode` | Current input (MouseKeyboard / Gamepad / Touch), UI actions and their glyphs |
| `Focus` | Gamepad selection scopes, traps, shoulder (LB/RB) routing, scroll-into-view math |
| `UIInput` | The `KitUI` Input Action System context: Back, TabPrev/TabNext, PagePrev/PageNext, Secondary, Tertiary |
| `Router` | Layers (ScreenGuis), screen stack, modals, transitions, Back, deep links |
| `Motion` | Tweens/loops that honour reduced motion; count-ups; springs |
| `Format` | Numbers, deltas, compact amounts, clocks, cooldowns, durations, dates, relative time, roman tiers |
| `Layers` | Where overlays go (`Layers.parentFor("Tooltip")`) |
| `Sound` | UI sound keys (`ui_click`, ...) routed to the audio system |
| `Components/*` | Button, IconButton, Toggle, Slider, Dropdown, TabBar, Chip, Panel, Card, Modal, ConfirmDialog, Tooltip, Toast, ToastStack, ProgressBar, StatBar, CurrencyLabel, Badge, Icon, KeyPrompt, VirtualList, VirtualGrid, ScrollFrame, Spinner, Skeleton, Divider, EmptyState, Text, Chamfer, Shadow, FocusRing |

## Booting the kit (client Main)

```lua
local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")
local stopKit = Kit.start({ soundPlayer = Audio.playUi })   -- input mode, layout, accessibility, KitUI, focus
local router = Kit.Router.new({                               -- creates the 9 layer ScreenGuis
	app = app,
	onRootBack = function() router:openModal("GameMenu") end,  -- Back on the Garage root (ui-ux §1.2)
})
router:register("Garage", require(Screens.Garage))
router:register("Settings", require(Screens.Settings))
router:register("SellConfirm", require(Screens.SellConfirm), { modal = true })
router:push("Garage")
```

`Kit.start` = `InputMode.start()` + `Layout.start()` + `Theme.bindEngine()` + `Focus.install()` (which starts
`UIInput`). Call it once; it returns `stop()`.

## Building a screen

A screen is a module `{ new(ctx) -> Screen }`. `Router.define` turns a build function into one; most screens need
nothing else. Everything the screen creates belongs to `ctx.scope` (a Trove) and is destroyed with the screen.

```lua
--!strict
--[[ (ARCHITECTURE §3 header: Purpose / Dependencies / State / Validation / Error handling / Performance notes) ]]
local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")
local State, Create, Theme, Layout = Kit.State, Kit.Create, Kit.Theme, Kit.Layout
local Panel, Button, Text, TabBar, VirtualList, StatBar = Kit.Panel, Kit.Button, Kit.Text, Kit.TabBar, Kit.VirtualList, Kit.StatBar

return Kit.Router.define({
	build = function(ctx: Kit.ScreenContext): GuiObject
		local scope = ctx.scope
		local tab = State.Value("modules", { scope = scope })
		local vehicles = State.Value({} :: { any }, { scope = scope })   -- filled from the profile store
		local selected = State.Value(nil :: any, { scope = scope })
		local researching = State.Value(false, { scope = scope })

		-- Screen-level gamepad/keyboard actions (X / F): also reachable through an on-screen button. ctx.on fires only
		-- while this screen is the active one (never from under a drill-in, a modal or an open dropdown).
		ctx.on("Secondary", function()
			ctx.router:push("Compare", { vehicle = selected:peek() })
		end)

		local list, listController = VirtualList.new({
			items = vehicles,
			itemSize = 72,
			gap = 4,
			render = function(item, index)
				return Kit.Card.new({
					onActivated = function()
						selected:set(item:peek())
					end,
					selected = State.Computed(function(): boolean
						return selected:get() == item:get()
					end),
					list = { direction = "x", gap = Theme.space(3), align = "center" },
					children = {
						Kit.Badge.new({ kind = "tier", tier = State.map(item, function(v) return v.tier end) }),
						Text.body(State.map(item, function(v) return v.name end)),
					},
				})
			end,
			Size = UDim2.new(0, 420, 1, 0),
		})

		return Create.Frame({
			Name = "Research",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			[Create.Children] = {
				Layout.padding({ x = Theme.space(6), y = Theme.space(5) }),
				Layout.list({ direction = "x", gap = Theme.space(5) }),
				list,
				Panel.new({
					title = "Modules",
					number = "02",
					Size = UDim2.new(1, -440, 1, 0),
					list = { gap = Theme.space(3) },
					children = {
						TabBar.new({
							tabs = { { id = "modules", label = "Modules" }, { id = "crew", label = "Crew" } },
							selected = tab,
						}),
						StatBar.new({ label = "Reload", value = 7.4, compare = 6.9, max = 12, unit = "s", decimals = 1, lowerIsBetter = true }),
						Button.new({
							text = "Research",
							loadingText = "Researching",       -- ui-ux §1.8 pending state, keeps its width
							loading = researching,
							variant = "primary",
							icon = "currency/vehicle_xp",
							onActivated = function()
								researching:set(true)
								-- send GarageRequest ...; the profile patch updates the view, then:
								-- researching:set(false)
							end,
						}),
					},
				}),
			},
		})
	end,
	initialFocus = function(ctx)   -- REQUIRED for every screen (ui-ux §1.13)
		return nil                 -- return the first card / the primary button
	end,
	onBack = function(ctx)         -- optional: return true to consume Back (close a drawer, cancel a preview)
		return false
	end,
})
```

Rules of thumb:

* **Never write literal colours, fonts or sizes.** Colours come from `Theme.color("bg.panel")` (a live State that
  follows the colour-blind scheme and high contrast), text from `Text.*` / `Theme.typography(role)`, spacing from
  `Theme.space(n)`, durations from `Motion`/`Theme.duration`. The only literals allowed are layout offsets in the
  1920×1080 (or 844×390 Compact) reference canvas.
* **Every screen root goes into the Router.** Overlays go to `Layers.parentFor("Modals" | "Toasts" | "Tooltip")` —
  never into a screen frame (they would be clipped and scaled twice).
* **Bind, don't poll.** Put data in `State.Value`s and bind instance props to them; never loop to refresh UI.
* **One primary CTA per screen** (`variant = "primary"`; the battle CTA uses `"battle"`).
* **Give every list an EmptyState and every async load a Skeleton/Spinner** (ui-ux §1.8).
* Prefer `VirtualList`/`VirtualGrid` for anything that can exceed ~40 rows.
* Show contextual actions in a `KeyPrompt.hintBar` along the bottom safe edge (gamepad only; reserve its 48 px while
  it is visible) and give each one an on-screen button for mouse and touch.

## State

```lua
local count = State.Value(0)                         -- :get() tracks, :peek() doesn't, :set(v, force?), :update(fn)
local label = State.Computed(function(): string      -- lazy, cached, glitch-free
	return Kit.Format.integer(count:get()) .. " credits"
end)
State.effect(function()                              -- runs now and on change; may return a cleanup
	print(label:get())
	return nil
end, { scope = ctx.scope })
State.observe(count, function(new, old) end, { scope = ctx.scope })   -- change callback (immediate = true to fire now)
State.batch(function() a:set(1); b:set(2) end)       -- one flush
local rows = State.list(items, function(item) return item.id end, function(item, index, scope) return Row(item) end)
```

* Equality: primitives by value (NaN-safe), **tables always count as changed** (set a new table, or pass
  `equals = State.shallowEqual`).
* Lifetimes: effects/observers live until destroyed — always give them `scope = ctx.scope` (or use
  `State.scoped(scope)`). Bindings made by `Create` die with their instance. `State.stats().liveEffects` exposes leaks
  in tests.
* `State.get(x)` / `State.peek(x)` / `State.map(x, fn)` accept plain values or States (`CanBeState<T>`), which is how
  every component accepts both.
* Setting a Value inside a Computed raises; cyclic reads raise (and are logged).
* An effect may write a Value it reads (normalise-and-render, clamping): it re-runs until it reads what is stored,
  including on its very first run. An effect that writes on every run is a loop and raises after
  `MAX_FLUSH_RUNS` runs instead of hanging.

## Create

```lua
Create.Frame({
	Name = "Row",
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundColor3 = Theme.color("bg.raised"),              -- State props are bound
	Visible = State.map(items, function(t) return #t > 0 end),
	[Create.On("MouseEnter")] = function() end,               -- events
	[Create.Change("AbsoluteSize")] = function(size) end,     -- property change
	[Create.Attribute("VehicleId")] = id,                     -- attributes
	[Create.Tag] = { "Selectable" },
	[Create.Ref] = rowRef,                                    -- a State.Value receives the instance
	[Create.Cleanup] = { connection, trove, function() end }, -- destroyed with the instance
	[Create.Children] = { Layout.list(), child, State.list(...) },  -- arrays flatten; States re-parent
	Parent = parent,                                          -- always applied last
})
Create.apply(existing, { Visible = shown })                  -- hydrate an existing instance
Create.onDestroy(instance, thing)                            -- tie anything to an instance's lifetime
```

Errors name the class and the key (`Create: Frame.Sizee is not a property`).

## Theme and tokens

* Colours: `Theme.color(token)` (State), `Theme.peekColor`, `Theme.team("ally" | "enemy" | "platoon" | "self" |
  "neutral" | "destroyed")`, `Theme.rarity`, `Theme.currency`, `Theme.tone("success" | "warning" | "danger" | "info" |
  "neutral")`, `Theme.mix(a, b, t)`, `Theme.faction(id)`, `Theme.material(name)`, `Theme.tokenTransparency("bg.scrim")`.
* Colour-blind schemes change **team colours only** (`default`, `deuteranopia`, `protanopia`, `tritanopia`).
  High contrast promotes secondary text/borders one step and darkens the scrim. Never encode meaning in colour alone:
  pair it with an icon, sign or label (StatBar prints `+`/`−`, toasts carry a glyph).
* Typography roles: `display.hero`, `h1`–`h4`, `body.l`, `body`, `body.s`, `label`, `caption`, `num.xl`, `num.l`,
  `num.m`, `mono`, `micro`, `button`, `button.cta`, `button.battle`, `tab`, `badge`, `title.s`. Sizes are reactive:
  role size, raised to the layout minimum (Compact/TV, `Tokens.layoutTypeMinimums`), × the player's text scale
  (0.8–1.5), raised so the **rendered** size meets the platform minimum (brand-art §4.2). No `TextScaled`.
* Settings: `Theme.set({ scheme, highContrast, textScale, uiScale, reducedMotion, holdSeconds, twoStepConfirm,
  hudScale })` (validated/clamped), `Theme.state.*` (read-only States), `Theme.changed` (Snapshot). `Theme.setSystem`
  is for Layout/bindEngine (`renderScale`, `platform`, `layout`, `reducedMotionSystem`, `preferredTransparency`,
  `preferredTextSize`).
  * `reducedMotion`: `true` (always reduced), `false` (always full motion) or `"system"` (default: follow
    `GuiService.ReducedMotionEnabled`) — ui-ux §1.15 "honours ReducedMotionEnabled, or override On/Off".
    `Theme.state.reducedMotion` is the effective value; `Theme.resolveReducedMotion(setting, engine)` is the rule.
  * `holdSeconds`: hold-to-confirm duration, 0.6–2.0 s (default 1.2; `a11y.holdConfirm`).
  * `twoStepConfirm`: the `a11y.holdConfirm` "Two-step" choice — hold-to-confirm buttons arm on the first press (full
    fill, label `armedText`, default "Confirm?") and confirm on a second press within `Button.ARM_WINDOW` (4 s);
    focus leaving the button or the timeout disarms (ui-ux §1.15).
  * `hudScale`: the battle `hud.scale` (0.8–1.5), applied through `Layout.state.hudScale`.
  * `bindEngine` also follows `GuiService.PreferredTextSize` (`Theme.state.preferredTextSize`): measured widths
    (auto-width buttons, tabs) re-measure when the player changes Roblox's text size.
* High contrast also makes backgrounds opaque (`Theme.backgroundTransparency(base)` → 0; otherwise it multiplies by
  `PreferredTransparency`) and borders 2 px (`Theme.borderWidth()` — Panel, Card, Modal, Button, Tooltip and Toast
  borders are bound to it; bind your own borders to it too).
* Shapes: `Theme.space(0..8)` = 0 4 8 12 16 24 32 48 64; `Theme.chamfer("s"|"m"|"l")` = 4/8/9; `Theme.radius`,
  `Theme.stroke`, `Theme.layer`, `Theme.z`, `Theme.sizes` (button heights, touch minimums, icon sizes, widths).

### Tokens

`Kit/Tokens.luau` holds every token as data. The block between `-- BEGIN GENERATED` and `-- END GENERATED` mirrors
`assets/brand/tokens.json` 1:1 and is guarded by `Theme.spec` (it fails when they drift). After a brand change
(`tools/art/hdart/tokens.py` writes tokens.json), regenerate the block and format:

```sh
python3 - assets/brand/tokens.json src/ReplicatedStorage/Client/UI/Kit/Tokens.luau <<'EOF'
import json, re, sys
tokens_json, target = sys.argv[1], sys.argv[2]
d = json.load(open(tokens_json))
out = ["\t-- BEGIN GENERATED (assets/brand/tokens.json) --", "\tcolors = {"]
out += [f'\t\t["{k}"] = "{v}",' for k, v in d["ui"].items()]
out += ["\t},", "\tteamSchemes = {"]
for scheme, roles in d["team_cvd"].items():
    out.append(f"\t\t{scheme} = {{")
    out += [f'\t\t\t["{k}"] = "{v}",' for k, v in roles.items()]
    out.append("\t\t},")
out += ["\t},", "\tfactions = {"]
for fid, f in d["factions"].items():
    out.append(f'\t\t{fid} = {{ name = "{f["name"]}", primary = "{f["primary"]}", secondary = "{f["secondary"]}", tint = "{f["tint"]}" }},')
out += ["\t},", "\tmaterials = {"]
for mid, m in d["materials"].items():
    out.append(f'\t\t{mid} = {{ highlight = "{m["highlight"]}", base = "{m["base"]}", shade = "{m["shade"]}" }},')
out += ["\t},", f'\tink = "{d["ink"]}",', "\t-- END GENERATED --"]
src = open(target).read()
new, n = re.subn(r"\t-- BEGIN GENERATED.*?-- END GENERATED --", lambda _: "\n".join(out), src, flags=re.S)
assert n == 1, "GENERATED markers not found"
open(target, "w").write(new)
EOF
stylua src/ReplicatedStorage/Client/UI/Kit/Tokens.luau
scripts/check.sh --only test -- Theme
```

New UI colour tokens also need the `Theme.ColorToken` union updated. Tokens outside the block (typography, spacing,
motion, layers, sizes, extra colours, high-contrast aliases) are edited by hand.

## Layout, scale and safe area

* Authoring canvases: **1920×1080** (Regular) and **844×390** (Compact, viewport height < 600). Each layer root is a
  `Layout.root()` frame sized `1/scale` with a `UIScale` (`RootScale`), so offsets are reference px everywhere.
* Scale: Regular `clamp(vh/1080, 0.75, 1.5)` (capped at 1.2 on tablets), Compact `clamp(vh/390, 0.92, 1.25)`, TV
  ×1.25 with a 5 % safe margin. The player's UI scale (0.8–1.2; 1.0–1.2 on touch) multiplies Regular only — Compact
  is fixed at 100 % — and is lowered automatically until the canvas is at least 1280 × 800
  (`Layout.effectiveUserScale(viewport, opts) -> (scale, limited)`; `Layout.state.scaleLimited` drives the settings
  slider's "Limited by this display", ui-ux §1.1.1 / §1.15). TV (`Layout.isTv`) = `GuiService:IsTenFootInterface()`
  **only** (ui-ux §1.1 / §5.4 #3): a PC with a gamepad or on a `DisplaySize.Large` screen stays Regular, so switching
  between mouse and pad never rescales the UI; the console text minimums apply only on TV.
  `Layout.state.{viewport, breakpoint, scale, scaleLimited, hudScale, hudLimited, platform, tenFoot, gamepad, tv}`,
  `Layout.isCompact`. Layout pushes `renderScale`, `platform` and `layout` (`regular|compact|tv`) into Theme.
  `Layout.setEnvironment({ viewport, tenFoot, displaySize, gamepad })` overrides the environment (tests, gallery);
  `Layout.environment()` snapshots it so a preview can restore it.
* Battle HUD scale (ui-ux §1.1.1, §S31): the `HUD` and `HUDInput` layer roots use `Layout.state.hudScale`, never the
  menu UI scale — Regular = device scale × `hud.scale` (`Theme.set({ hudScale })`, 0.8–1.5) capped so the HUD canvas
  stays ≥ 1360 × 720 (1448 wide in event modes: `Layout.setHudAbilities(true)`), e.g. 1080p at 150 % → 141 %;
  Compact battle root `min(1.25, vh/390)`; touch on a Regular display (tablets) `vh/700`. Pure rule:
  `Layout.computeHudScale(viewport, { tenFoot, tablet, hudScale, abilities }) -> (scale, limited)`. A custom root can
  opt in with `Layout.root({ scale = "hud" })`.
* Helpers: `Layout.padding(n | {x, y, top, ...})`, `Layout.list({direction, gap, align, justify, wraps})`,
  `Layout.grid({cell, gap, maxCells})`, `Layout.flex({grow, shrink, fill})`, `Layout.sizeConstraint`, `Layout.aspect`.
* Layers (ui-ux §1.1; one ScreenGui each, `ResetOnSpawn` off, `ZIndexBehavior.Sibling`, `SafeAreaCompatibility.None`):

  | Layer | DisplayOrder | ScreenInsets | Holds |
  |---|---|---|---|
  | Background3D | 0 | None (+ IgnoreGuiInset) | vignettes, letterbox (non-interactive) |
  | HUD | 10 | DeviceSafeInsets | battle gauges (may use the top-bar row); HUD scale |
  | HUDInput | 11 | CoreUISafeInsets | battle touch controls, minimap, H-10 bar; HUD scale |
  | Screens | 20 | CoreUISafeInsets | menu screens, drawers |
  | TopBar | 25 | TopbarSafeInsets | the garage top bar (no TV margin) |
  | Modals | 30 | CoreUISafeInsets | modals, sheets, `Modal.open` |
  | Toasts | 40 | CoreUISafeInsets | toasts, banners |
  | Tooltip | 50 | CoreUISafeInsets | the shared tooltip, **dropdown lists** (above modals) |
  | Debug | 90 | None (+ IgnoreGuiInset) | dev overlays |
* Touch: `Common.touchHeight(h)` raises controls to 44 px on touch (48 authored on Compact). Components do this
  already — buttons, chips (and their remove cross), segmented tabs, dropdown fields and option rows, slider tracks
  (the hit area grows upward, the drawn track stays put) and icon buttons (a 32 px toast close keeps its 32 px plate
  but takes 44 px).
* Overlays placed at an element (tooltips, dropdown lists, your own popovers) convert screen px with
  `Layers.toLocal(layerRoot, point)`, which honours the root's UIScale **and** its TV-safe UIPadding.

## Input modes and glyphs

`InputMode.mode` is `"MouseKeyboard" | "Gamepad" | "Touch"` (from `UserInputService.PreferredInput`). UI actions
(`Confirm`, `Back`, `Secondary`, `Tertiary`, `TabPrev`, `TabNext`, `PagePrev`, `PageNext`, `Scoreboard`; add more
with `InputMode.registerAction`) map to keyboard keys and gamepad buttons; `InputMode.glyph(action)` /
`KeyPrompt.new({ action, label })` show the right prompt (Xbox/PlayStation art from `GetImageForKeyCode`, keycaps on
keyboard, nothing on touch). `KeyPrompt.hintBar({ hints })` is the footer hint row.

* Reserved, never bound: Esc, ButtonStart, F9, F11, F12, PrintScreen (`InputMode.isReserved`).
* Menus use only the Input Action System (`UIInput`: context `KitUI`, priority 3100, `Sink = false`). Actions: Back,
  TabPrev/TabNext (LB/RB, Q/E), PagePrev/PageNext (LT/RT, Z/C), Secondary (X/F), Tertiary (Y/G). Confirm stays with
  the engine (A activates the selected GuiButton). Screens listen with `ctx.on("Secondary", fn)`: it fires only while
  the screen is active (top of the stack and owner of focus — `ctx.isActive()`). `UIInput.on` is global (it would also
  fire for a keepAlive screen hidden under a drill-in, or under a dialog); use it only outside screens. Actions are
  ignored while a TextBox has focus.
* Remapping: `InputMode.registerAction(name, { keyboard, gamepad })` replaces an action's keys at any time; the
  `KitUI` context rebinds (`InputMode.actionsChanged`) and every `KeyPrompt`/`glyphState` refreshes.
* Controller family: prompts also refresh when a gamepad connects or disconnects (`InputMode.start` listens; an Xbox
  pad swapped for a PlayStation pad switches A/B/X/Y to ✕/○/□/△ and the button art). `InputMode.refreshGlyphs()`
  forces it.
* `KeyPrompt.hintBar({ hints, keyboard? })` (48 px) shows on gamepad only unless `keyboard = true` (setting
  `ui.hintsKbm`); never on touch. Bind the screen's 48 px bottom reservation to `KeyPrompt.hintBarShown(keyboard)`.
  Keycaps are chamfered `bg.inset` plates with a Builder Mono (`keycap`) label.
* Hover effects must also appear on gamepad focus; every mouse-only affordance needs a gamepad and touch path
  (tooltips: hover 0.4 s / focus 0.6 s / long-press).

## Focus (gamepad) rules

* `GuiService.AutoSelectGuiEnabled = false`, `GuiNavigationEnabled = true`; the selection ring is the kit FocusRing
  (2 px `accent.dusk_hi` + pulsing brackets; danger buttons get the danger ring).
* The Router gives every screen a **focus scope** over its root (modals: `trap = true`). The top scope owns
  `GuiService.SelectedObject`: entering gamepad mode selects the screen's `initialFocus` (or the remembered element
  when returning); leaving gamepad mode clears selection.
* Popups you open yourself (`Dropdown`, `Modal.open`) create trapped scopes and intercept Back with
  `UIInput.interceptBack(fn)` so the screen below never pops. Do the same for drawers:

```lua
local scope = Focus.scope(drawer, { name = "FilterDrawer", trap = true, initial = firstChip })
scope:activate()
local removeBack = UIInput.interceptBack(function(): boolean
	closeDrawer()      -- also scope:Destroy() and removeBack()
	return true
end)
```

* LB/RB: the top scope's `onShoulder` handler (Router screens: only when the screen defines `onShoulder`), else the
  newest `TabBar` visible inside the top scope (`Focus.registerShoulder`) — a screen with a TabBar needs no handler.
  TabBar shows the shoulder glyphs (Q/E keycaps on keyboard).
* LT/RT: the top scope's `onPage` handler (Router screens: `onPage`, e.g. tech-tree zoom), else `Focus.page` scrolls
  the nearest **scrollable, visible** ScrollingFrame around the focused element (else the scope's first one) by one
  viewport minus 10 % and focuses the first element fully inside the new page (`Focus.pageOffset` is the pure
  rule). Lists on hidden tab pages and frames with `ScrollingEnabled = false` (fixed carousels) are skipped.
* Right stick scrolls that region smoothly (900 px/s at full deflection, 0.25 dead zone; `Focus.stickScrollStep`).
  Screens where it orbits the camera register with `{ stickScroll = false }` (Router option / scope option). The
  scroll loop only exists while the top scope can stick-scroll in gamepad mode (battle camera input starts nothing)
  and caches its region until the selection or the top scope changes.
* Returning to a screen restores the remembered element; if it was destroyed meanwhile (sold, filtered out) focus
  goes to the **nearest selectable sibling** in the same list, else `initialFocus` (ui-ux §1.13 rule 2).
* Lost focus is repaired (REG-INP-01): when the engine resets `SelectedObject` to nil in gamepad mode (the focused
  row was destroyed, its tab hidden, a VirtualList slot recycled away), Focus selects the top scope's best target one
  frame later — remembered element, its nearest sibling, `initialFocus`, then the first selectable. A burst of drops
  (each within `Focus.REPAIR_WINDOW` 0.5 s) is repaired at most `Focus.MAX_REPAIRS` (3) times and an element the
  engine keeps dropping is skipped; separate incidents (selling row after row) are always repaired.
* Select programmatically with `Focus.select(object)` (or `scope:focus(object)`): no hover tick, gamepad mode only.
* `ui_hover` ticks only for player moves (never for programmatic focus such as initial focus or restoration) and at
  most 6 per second (ui-ux §1.16). Pointer hovers and focus moves share that budget through `Sound.hover()` (use it
  for custom hover sounds). Programmatic focus stays silent under `Workspace.SignalBehavior = Deferred` too (the
  queued `SelectedObject` events of a restore all read the final target).
* Lists: `Focus.chain(list, "horizontal" | "vertical", wrap?)`, `Focus.grid(list, columns, wrap?)` set explicit
  neighbours; carousels/grids do not wrap (ui-ux §1.13). Scroll containers (`ScrollFrame`, `VirtualList`) reveal the
  selected element with 48 px of context (`Focus.revealOffset`).
* Disabled controls stay selectable (so their reason tooltip is reachable); activating them plays `ui_error`.

## Router

* `router:push(name, params)`, `pop()`, `replace`, `reset`, `openModal(name, params)`, `closeModal()`,
  `closeAllModals()`, `back()` (top screen's `onBack` first, then close modal / pop), `navigate("Garage/TechTree?faction=iron_union")`,
  `current()`, `history()`, `canGoBack()`, `layer(name)`, `layerRoot(name)`, `changed` (current, previous).
* Register options: `{ layer = "Screens", modal = false, dismissible = true, keepAlive = false, transition = "slide" |
  "fade" | "pop" | "sheet" | "none", focus = true, stickScroll = true }`. Default transition
  (`Router.transitionFor`): modals pop, a `reset` root fades, pushed drill-ins slide; register rail **sections** with
  `transition = "fade"` (ui-ux §1.3: sections never slide). A keepAlive screen has one cached instance: pushing it
  while it is already on the stack builds a second one, which is destroyed (not cached) when popped. `Router.new({ parent, app, name,
  backSignal, registerLayers, onRootBack })`; `router.rootBack` fires (root name) when Back has nothing to close or
  pop — wire the Game menu there (ui-ux §1.2 step 5).
* Screen contract (custom modules): `mount(parent)`, `show(params, { reason = "push" | "return" | "replace" | "reset",
  previous })`, `hide()`, `destroy()`, optional `onBack(): boolean?`, `initialFocus(): GuiObject?`,
  `onShoulder(direction)`, `onPage(direction)`. `Router.define({ build, onShow, onHide, onBack, initialFocus,
  onShoulder, onPage })` builds one from functions. The new screen is built before the old one hides, so a failing build leaves the old screen
  up (errors are logged, never thrown into the caller). A screen may navigate from inside `show` (a redirect such as
  the Garage pushing pending Battle Results): the covered screen then skips its entrance and does not take focus.
* Screen context: `ctx.router`, `ctx.name`, `ctx.layer`, `ctx.params` (Value), `ctx.scope` (Trove), `ctx.app`,
  `ctx.on(action, fn)` (screen-scoped KitUI action) and `ctx.isActive()`.
* Transitions: drill-ins slide 24 px + veil fade (none under reduced motion); roots and sections fade; modals pop
  (`Motion.POP_FROM` 0.98 → 1, ui-ux §1.3); sheets slide up 64 px. Exits are cuts by design (the screen's lifecycle stays synchronous): the revealed screen plays its "return"
  entrance (slide from the left) and the modal scrim fades out.

## Motion

`Motion.tween(inst, props, { duration = "base", easing = "standard", kind = "move" | "scale" | "fade" | "color" })`
and the presets `fadeIn/fadeOut`, `slideIn/slideOut(gui, "right", 24)`, `pop`, `pulse` (returns stop), `shake`,
`countUp(from, to, onStep)`, `follow(state, scope)` (critically damped spring), `loop(step)` (Heartbeat),
`onComplete(tween, fn)`. Durations: `hover` 80 ms, `fast` 120, `base` 150, `slow` 200, `toast` 160, `flourish` 400,
`countUp` 600. Calm, ease-out, nothing bounces (brand-art §8.1).

Reduced motion (the player's setting OR `GuiService.ReducedMotionEnabled`) removes movement (slides, pops, pulses,
shakes, springs, count-ups jump) and caps fades/colour changes at 0.1 s. Always animate through Motion so this holds.
Motion reads the setting when an animation starts; anything that **loops** (`repeatCount = -1`) must also follow the
setting live — bind it in an effect on `Theme.state.reducedMotion` that cancels/restarts the tween (Spinner,
Skeleton shimmer, ProgressBar sweep and the focus-ring pulse do).

## Components

All components take the layout props `Name, Position, AnchorPoint, Size, LayoutOrder, ZIndex, Visible, Parent`
(any of them may be a State, `Parent` is applied last) plus their own props; text/number props accept States.
`children`/`actions` are typed `{ any }` (Luau tables are invariant, so `{ Text.body(...), Button.new(...) }` would not
check against `{ Instance }`).

| Component | Constructor and key props |
|---|---|
| Text | `Text.new({ text, role, color, align, wrap, truncate, autoSize, maxWidth, upper })`; shortcuts `Text.h1(text, opts)` … `Text.display/h1/h2/h3/h4/bodyLarge/body/bodySmall/label/caption/numXL/numL/numM/mono/micro/titleSmall` |
| Button | `Button.new({ text, variant = "primary"|"secondary"|"ghost"|"danger"|"premium"|"battle", size = "large"|"medium"|"compact", icon, iconRight, hint, disabled, loading, loadingText, hold = true|seconds, armedText, onActivated, width = n|"fill"|"auto", sound, tooltip })`. `loadingText` swaps the label for the "-ING" verb while loading and keeps the width; `hold` = hold-to-confirm on gamepad (hold A while focused) and touch (hold the finger), with a fill sweep; mouse/keyboard click; with `Theme.state.twoStepConfirm` it arms on the first press (`armedText`) and confirms on the second. `Button.holdController(guiButton, { seconds, enabled, onComplete })` adds the hold to any button (inactive in two-step mode). The loading spinner only runs while loading. |
| IconButton | `IconButton.new({ icon, label (tooltip), variant = "ghost"|"secondary"|"primary", size = 44, disabled, selected, onActivated })` |
| Toggle | `Toggle.new({ label, value = Value<boolean> } | { checked, onChanged }, disabled)` — `checked` as a State is controlled (update it from `onChanged`); as a plain boolean it is just the initial value |
| Slider | `Slider.new({ label, value = Value<number>, min, max, step, format, onChanged, disabled })` — d-pad/arrows/stick step while focused and repeat while held (`Slider.REPEAT_DELAY` 0.35 s, then every `REPEAT_INTERVAL` 0.08 s) |
| Dropdown | `Dropdown.new({ options = {{ value, label, icon, disabled }}, selected = Value, onChanged, placeholder, width, disabled })` — the list opens in the Tooltip layer, so dropdowns inside modals work |
| TabBar | `TabBar.new({ tabs = {{ id, label, icon, badge, disabled }}, selected = Value<string>, onChanged, variant = "top"|"segmented", shoulder })` |
| Chip | `Chip.new({ label, icon, tone, selected, disabled, onActivated, removable, onRemove })`, `Chip.tag(label, tone)` |
| Panel | `Panel.new({ title, number, icon, actions, variant = "default"|"raised"|"inset"|"hero", padding, autoHeight, list, children })`, `Panel.content(panel)` |
| Card | `Card.new({ onActivated, selected, disabled, rarity, padding, list, children, sound })` |
| Modal | `Modal.new({ title, icon, body, children, actions = {{ text, variant, id, icon, hint, disabled, onActivated, keepOpen, focus }}, size = "s"|"m"|"l", dismissible, onClose, banner })` (card for Router modal screens); `Modal.open(props + { onResult, anchor, initialFocus, scope }) -> { close(result), isOpen(), closed, root, dialog }`. **Pass `scope = ctx.scope`**: the dialog then closes (result nil) with the screen instead of covering the next one. A dialog whose layer is destroyed (router teardown) closes itself and releases Back and focus. |
| ConfirmDialog | `ConfirmDialog.open({ title, body, icon, confirmLabel, cancelLabel, destructive, hold, size, children, onConfirm, onCancel, scope })` — destructive: hazard band, danger button that must be **held** on gamepad/touch (`Theme.state.holdSeconds`, or two presses with `twoStepConfirm`; `hold = false` opts out), focus on Cancel; cleaning `scope` cancels |
| Tooltip | `Tooltip.attach(target, "text" | { title, body }, { placement, delay }) -> detach`; `Tooltip.show/hide/owner`; `Tooltip.place` (pure). A touch long-press shows the tooltip and never activates the target (kit buttons, cards, chips, toggles and dropdowns check `Common.consumeLongPress`; do the same in custom buttons that carry a tooltip). Activating, hiding or removing the target hides it, and so does covering its screen (a per-frame visibility watch runs only while a tip is shown, since a still pointer fires no MouseLeave). |
| Toast | `Toast.show({ title, body, tone, icon, action = { text, onActivated }, duration, sticky, key, sound = true|false|"ui_purchase", reward = { currency, amount } }) -> id?`, `Toast.reward({ currency, amount, title, sound })`, `Toast.dismiss(id)`. `ui_notification` plays at most once per 1.5 s (bursts share one cue). Toast buttons are never selectable (toasts never take gamepad focus). |
| ToastStack | `ToastStack.new({ parent, max = 3, position, anchorPoint })` → `:push(spec)`, `:dismiss(id)`, `:clear()`, `:ids()`, `:count()`, `:destroy()`; `ToastStack.default()` |
| ProgressBar | `ProgressBar.new({ value (0..1), indeterminate, ghost, color, height = 6, segments, animate = true })` |
| StatBar | `StatBar.new({ label, value, max, compare, lowerIsBetter, unit, decimals, format, bar })` |
| CurrencyLabel | `CurrencyLabel.new({ currency, amount, size = "s"|"m"|"l", style = "plain"|"panel", countUp, showDelta, compact, insufficient, prefix })` |
| Badge | `Badge.new({ kind = "tier"|"class"|"premium"|"new"|"count"|"text", tier, class, premium, elite, count, text, tone, size, compact })`, `Badge.tier(n)` |
| Icon | `Icon.new({ key, size = 24, color, transparency, forceGlyph })` (also `Kit/Components/Icon`) |
| KeyPrompt | `KeyPrompt.new({ action, label, size })`, `KeyPrompt.hintBar({ hints = {{ action, label }}, align, keyboard })` |
| VirtualList | `local frame, controller = VirtualList.new({ items, render(item, index), itemSize, gap, padding, direction = "vertical"|"horizontal", crossSize, overscan = 2 (min 1), revealPadding = 48, animate })` |
| VirtualGrid | `VirtualGrid.new({ items, render, cell = Vector2, gap, padding, direction, maxLanes, overscan })` |
| ScrollFrame | `ScrollFrame.new({ direction = "x"|"y"|"xy", list, grid, padding, children, reveal = true, revealPadding = 48 })`, `ScrollFrame.reveal(frame, object)` |
| Spinner / Skeleton | `Spinner.new({ size, color })`; `Skeleton.new({ shape = "block"|"lines"|"circle", lines, lineHeight })` |
| Divider / EmptyState | `Divider.new({ direction, variant = "line"|"ridge", label, color, inset })`; `EmptyState.new({ icon, title, body, action = { text, onActivated } })` |
| Chamfer / Shadow / FocusRing | the HULLDOWN cut surface (`Chamfer.new({ corners, size, fill, gradient, border, bevel })`), the one elevation shadow, the focus ring templates |

### Virtual lists

`render(item, index)` runs **once per pooled slot**; `item` and `index` are States that are re-bound as the list
scrolls (never nil). Bind everything to them (`State.map(item, ...)`), keep per-row state in the item, and do not
cache instances by item. The engine owns each slot's `Position`, `Size` and `Visible`. The pool holds
(visible rows + 1 + 2 × overscan) × lanes slots and they are re-used by ring assignment, so a selected slot keeps its
item while it stays in the window. Only slots whose index (or the lane count) changed are re-positioned, so a
one-row scroll writes one slot. `overscan` is at least 1: with none, a viewport edge on a row boundary leaves no
instantiated row below the last visible one and gamepad navigation cannot move on. The controller:
`scrollToIndex(i, animate?)`, `selectIndex(i)` (gamepad), `indexOf(instance)`, `slotFor(i)`, `range()`,
`poolSize()`, `slotCount()`, `lanes()`, `refresh()`, `stats()` (`{ rebinds, placements }` for perf tests).

### The HULLDOWN cut (chamfers)

Panels, buttons and plates use 45° corner cuts (8 px top-left + bottom-right on panels/CTAs, 4 px on tags) instead of
rounded corners. Until 9-slice art is uploaded, `Chamfer.new` builds them from primitives: the fill is a middle frame
plus edge strips, each cut corner is a square with a `UIGradient` (Rotation 45/135, hard 0.5 step in Transparency)
that keeps one triangle; borders are 1 px strips plus a rotated 1 px bar across each cut. Gradient fills (the CTA)
use per-piece Color sequences sampled at the piece's position so the vertical gradient is continuous. Cost: ~10–20
Frames per surface — fine for panels and buttons, but use plain frames (or uploaded 9-slices) inside long lists.

## Icons and assets

* `Icon.new({ key = "classes/heavy" })` resolves through `Shared/Assets/AssetResolver`: an uploaded image (one
  tinted ImageLabel; sheet rects supported) → a dedicated primitive glyph from `Icons/Registry` → the generic
  category badge (tinted per category). Keys follow `assets/icons/<folder>/<name>.svg`.
* **Glyph keys are the asset keys** (`assets/icons/<folder>/<file stem>`), so uploaded art replaces a glyph with no
  code change. Battle glyphs therefore live under `battle/*`: `battle/hit_penetration|critical|blocked|ricochet|kill|
  fire|track`, `battle/ping_attack|defend|help|position|spotted`, `battle/cmd_*` (the decided radial presets),
  `battle/spotted_warning`, `battle/spotted_enemy` and the minimap markers `battle/self|last_seen|base_ally|
  base_enemy|capture_point|objective`. Glyphs whose art is still to come are listed in
  `FallbackKeys.awaitingArt` (`cmd_hold`, `cmd_focus_fire`, `cmd_moving`, `cmd_thanks`, `hit_absorbed`, `hit_splash`,
  `hit_detonation`); the Icons spec fails if any other glyph key has no SVG, or if an awaited SVG lands without the
  key leaving the list.
* Glyph sets follow brand-art §6 as far as primitives allow: class symbols (eye, flat-top hexagon with slot, shield,
  low casemate with muzzle ring, arch over impact) + minimap twins; tier data plates I–XI (material and plate features
  escalate; numerals pinned with a UITextSizeConstraint so PreferredTextSize never overflows the plate); currencies
  (credits hex token with stencil C, bullion ingot, XP chevrons, campaign token); ammo (gunmetal case; nose silhouette
  is the type; `_special` = gold case + gold rim); modules per §6.8 outlines (piston and crank, clamp rack, hooped drum
  with a drop, elevated barrel on a cradle, internally toothed ring with pinion, two lens barrels, track run with its
  front slope) with **shape-changing states** (damaged = amber + a V bite at the top-right with a crack; destroyed =
  signal + a jagged break band; cut-outs are ink, which reads as a gap on the dark panels these sit on); crew (olive
  helmet + bone role tool — pennant, crosshair, wheel, shell; injured = signal + first-aid badge); the battle set
  (pin-family pings, commands, hit callouts, crest-chevron alerts, minimap markers); and ~40 UI glyphs covering the nav
  rail and top bar (menu, home, garage, tech tree, crew, missions, store, profile dog tag, friends, bell, premium sun
  over the ridge, favourite ribbon, filter, sort, refresh, help, clock, research, HP angular heart, damage, battle...).
  Anything else draws the tinted category badge.
* `Icons/Glyph` primitives (64-unit grid, scale with the icon size): rect, box (rotatable), circle, ring (UIStroke,
  half-arc masks), halfDisc, line/polyline, triangle (UIGradient diagonal mask), wedge, hexagon, chamferRect, octagon,
  chevron, arrow, drop (teardrop), text (numerals only), bang, cross, check. A builder receives a palette
  (`fg/detail/highlight/base/shade/ink/accent` + `tinted` when the caller passed a colour).
* New feature glyph: `Icon.register("vehicles/iu_forge", { build = function(c, p) Glyph.rect(c, 8, 20, 48, 24, p.fg) end, color = "brand.bone" })`
  (64-unit canvas). It is declared to the resolver so `resolveImage` reports a glyph instead of "missing".
* `AssetManifest.luau` is **generated by tools/assets** (never hand-edit); `AssetResolver.default()` reads it.
  `resolver:image(key)`, `resolveImage(key) -> { kind = "image"|"glyph"|"badge"|"missing", ... }`, `sound(key)`,
  `has`, `hasFallback`, `validateKeys(keys, { kind, allowFallback })`, `missing()`. Unknown keys warn once.

## Accessibility checklist (every screen)

- [ ] Every interactive element is reachable and operable with mouse, touch **and** gamepad; `initialFocus` set;
      nothing is reachable only by hover.
- [ ] Back (B / Backspace; Esc is Roblox's) always does something sensible: closes the top popup/drawer/modal, then
      pops; on the root the Router's `onRootBack` opens the Game menu.
- [ ] Text uses typography roles only (no `TextScaled`, no literal sizes); layouts survive text scale 1.5 and
      Compact (844×390) without clipping — check in the gallery with the text-scale slider.
- [ ] Colours come from tokens; meaning is never colour-only (icons, signs, labels); team colours read correctly in
      all four schemes and with high contrast (gallery header toggles).
- [ ] Touch targets ≥ 44 rendered px (48 authored on Compact), ≥ 8 px apart.
- [ ] Motion goes through Kit/Motion (reduced motion respected); no flashing faster than 3 Hz.
- [ ] Disabled controls explain why (tooltip / inline reason) and stay focusable.
- [ ] Destructive or expensive actions use `ConfirmDialog` with `destructive = true` (focus starts on Cancel; the
      danger button is held on gamepad/touch). Every Bullion spend uses a purchase confirm (ui-ux §1.6).
- [ ] Screen-level actions (X/Y, LT/RT) have on-screen buttons too and show in the hint bar on gamepad.
- [ ] Lists have empty states; loads show skeletons/spinners; numbers use `Format` (U+2212 minus, grouping).
- [ ] Toast content is also reachable from the screen or the notification centre (toasts never take focus).

## Gallery

`Client/UI/Dev/KitGallery.luau` is a Router screen (`KitGallery.register(router)`; `router:push("KitGallery")`)
with sections Foundations (colour tokens, team colours per scheme, typography, surfaces, spacing), Buttons, Inputs,
Surfaces (panels, cards, dividers, dialogs), Feedback (toasts, progress, spinners, skeletons, empty state, tooltip),
Data (stat bars, currencies, badges), Icons (every registry key, virtualised) and Lists (500-row VirtualList). The
header switches scheme, high contrast, reduced motion, text scale, the input-mode preview and a layout preview
(Compact 844×390 / Regular / TV; the live layout comes back when the gallery closes) — global on purpose. Buttons
include the premium variant, the "-ING" pending label and hold-to-confirm; Feedback includes reward toasts.

## Known limitations (verify in Studio)

Everything above is exercised headlessly in Lune against MockInstances and the real Roblox API dump; these engine
behaviours cannot be observed there:

* The HULLDOWN cut (Chamfer): UIGradient hard-step masks on 45°/135° rotated gradients and 1 px rotated border bars —
  check for seams/aliasing at 0.75–1.5 UIScale; swap to 9-slice art when uploaded.
* Glyph fallbacks: hairline seams between adjacent primitive frames at small sizes (reviewed only as SVG renders).
* `SelectionImageObject` = the kit FocusRing template: centring via AnchorPoint/Position relative to the selected
  object, the pulse (UIScale on the template) and the danger variant per button.
* Selection activation: gamepad A on a selected button fires `Activated` once; hold-to-confirm listens to
  `UserInputService` ButtonA while selected (is it marked processed? does `Activated` fire on press or release?).
* Focus repair: that the engine resets `SelectedObject` to nil when the selected object is destroyed, hidden or goes
  off screen (the docs say "may reset to nil if the object is off screen"), and that the one-frame repair does not
  flicker the ring.
* Touch long-press: whether `Activated` fires on release after `TouchLongPress` (the kit suppresses it either way) and
  whether `InputEnded` reaches a hold button after the finger slides off it.
* `Layers.toLocal`: UIPadding scale measured against the root's post-UIScale `AbsoluteSize` (TV tooltip/dropdown
  placement on a console).
* HUD text minimums: Theme's text minimums use the menu render scale; HUD text at a lower `hud.scale` renders smaller
  (check the 80 % HUD on a phone/console against brand-art §4.2).
* `CanvasPosition` units under an ancestor UIScale (the kit treats them as unscaled canvas units, like
  `AbsoluteWindowSize / scale`) for paging, right-stick scrolling and VirtualList windows; whether the engine's own
  gamepad selection also auto-scrolls or right-stick-scrolls ScrollingFrames (double scrolling).
* `ScreenInsets` per layer (DeviceSafeInsets HUD, TopbarSafeInsets row height on phones), `IgnoreGuiInset` write
  order, TV 5 % margin on a real TV.
* `UITextSizeConstraint` keeping glyph numerals fixed under PreferredTextSize Largest; text measurement with the
  legacy `Enum.Font` twins (`Common.measureText`) vs FontFace rendering for auto-width buttons/tabs.
* Input Action System: `KitUI` (priority 3100, Sink false) coexisting with the gameplay contexts and with GuiService
  navigation (B/LB/RB/LT/RT not swallowed), rebinding after remapping, and `GetImageForKeyCode` art for Xbox and
  PlayStation.
* TV detection rule (`GuiService:IsTenFootInterface()` only; a PC with a pad or on a Large display stays Regular) on
  PC + controller and on console.
* `Workspace.SignalBehavior`: the kit is written to work under Immediate (today's `Default`) and Deferred (the
  announced future default): play-test both, especially focus restore after dialogs, REG-INP-01 repair and the
  hover tick.
* First focus on a freshly mounted screen: `Focus.firstSelectable` orders by `AbsolutePosition`; check that layouts
  (UIListLayout/UIGridLayout) have resolved positions when the scope activates, or give the screen `initialFocus`.
* Held left stick on a Slider: the repeat is Heartbeat-timed because a steady stick sends no InputChanged; confirm the
  stick's dead-zone noise does not restart the repeat delay on real pads.

## Format

`Format.integer(12400)` "12,400" · `number(n, decimals)` · `signed` "+1,240" / "−0.4" (U+2212) ·
`delta(v, { decimals, unit, lowerIsBetter })` → `{ text, tone, sign }` · `compact` "12.4K" (never for prices) ·
`percent(0.524, 1)` · `unit(54, "km/h")` · `seconds(7.4)` "7.4 s" · `clock(720, ceil?)` "12:00" · `timer` ·
`cooldown(41.2)` "42" · `duration(s)` "6d 4h" / "12m 30s" / "45 s" · `date(unix, now?)` "5 Oct" / "5 Oct 2025" ·
`relative(then, now)` "just now" / "5 min ago" / "3 h ago" / "Yesterday" / date · `roman(7)` "VII" · `tier(7)`
"Tier VII". Everything is pure: pass the clock in (`Clock.wall()` on the client), never read it in Format.

## Testing UI

Specs live under `tests/Unit/ReplicatedStorage/Client/UI/...`. `KitTestSupport.install()` defines the GUI mock
classes and fake services (TweenService that completes instantly or on `env:completeTweens()` with
`env.deferTweens = true`, UserInputService with Xbox key names, GuiService selection, RunService `env:step(dt)` for
Heartbeat-driven timers). Helpers: `Support.find`, `Support.click`, `Support.fire`, `Support.select(guiService, obj)`,
`Support.input{...}`, and `Support.validateTree(root)`, which checks every assigned property against the Roblox API
dump (`$HULLDOWN_TOOLS/API-Dump.json`: property exists, value type/enum matches, not read-only) — call it on
everything you build. Engine-owned values (AbsoluteSize, AbsolutePosition) are set with
`rawget(inst, "_props").AbsoluteSize = v` (+ firing the property signal) so they do not count as script writes.

* `Components/Lifecycle.spec` builds and destroys every component with State-bound props and fails if any rooted
  effect/observer survives (`State.stats().liveEffects`) — add new components to it.
* `Kit/ReviewRegressions.spec` holds the adversarial regressions from the kit reviews (round 1: shoulder routing,
  focus repair, TV rule, HUD scale, touch targets, long-press, overlays, two-step confirm, ...; round 2: hidden
  scroll regions, stick-loop churn, deferred-signal hover ticks, pointer hover rate, redirect from `show`, controller
  family prompts, lingering tooltips, slider hold-repeat, VirtualList placement/overscan, live reduced motion for
  looping placeholders); each failed against the kit it was written for.
* Rate limits and timers take injectable clocks in tests: `Focus.setClock(fn)` (hover ticks), `ToastStack.setClock(fn)`
  (notification cue); Heartbeat-driven loops advance with `env:step(dt)`.
* Harness gaps patched test-side in KitTestSupport (the shared harness is not modified): `inst.Parent` reads, GUI
  classes/signals, `FindFirstAncestorWhichIsA` / `FindFirstAncestorOfClass`. Moving these into
  `tests/Harness/Mocks/MockInstance` would let other client specs use them.

## Strict-mode typing notes

* String-literal unions widen to `string` when iterated (`for _, v in {"a", "b"}`) or passed through generics; use an
  indexed loop, annotate the local (`local role: Theme.TypeRole = ...`) or cast at the call (`v :: any`).
* Component props are flat types (no `&` intersections) so table literals check; keep it that way when adding props.
* `State.get/peek/map/of/list` are overloaded (`State<T>` and `CanBeState<T>`), so passing either works.
