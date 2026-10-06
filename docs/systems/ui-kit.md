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
| `UIInput` | The `KitUI` Input Action System context: Back, TabPrev, TabNext |
| `Router` | Layers (ScreenGuis), screen stack, modals, transitions, Back, deep links |
| `Motion` | Tweens/loops that honour reduced motion; count-ups; springs |
| `Format` | Numbers, deltas, compact amounts, time, roman tiers |
| `Layers` | Where overlays go (`Layers.parentFor("Tooltip")`) |
| `Sound` | UI sound keys (`ui_click`, ...) routed to the audio system |
| `Components/*` | Button, IconButton, Toggle, Slider, Dropdown, TabBar, Chip, Panel, Card, Modal, ConfirmDialog, Tooltip, Toast, ToastStack, ProgressBar, StatBar, CurrencyLabel, Badge, Icon, KeyPrompt, VirtualList, VirtualGrid, ScrollFrame, Spinner, Skeleton, Divider, EmptyState, Text, Chamfer, Shadow, FocusRing |

## Booting the kit (client Main)

```lua
local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")
local stopKit = Kit.start({ soundPlayer = Audio.playUi })   -- input mode, layout, accessibility, KitUI, focus
local router = Kit.Router.new({ app = app })                  -- creates the 8 layer ScreenGuis
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
							variant = "primary",
							icon = "currency/vehicle_xp",
							onActivated = function()
								-- send GarageRequest ...
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
* Settings: `Theme.set({ scheme, highContrast, textScale, uiScale, reducedMotion })` (validated/clamped),
  `Theme.state.*` (read-only States), `Theme.changed` (Snapshot). `Theme.setSystem` is for Layout/bindEngine.
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
* Scale: Regular `clamp(vh/1080, 0.75, 1.5)`, Compact `clamp(vh/390, 0.92, 1.25)`, TV ×1.25 with a 5 % safe margin,
  all × the player's UI scale (0.8–1.2). `Layout.state.{viewport, breakpoint, scale, platform, tenFoot}`,
  `Layout.isCompact`. Layout pushes `renderScale`, `platform` and `layout` (`regular|compact|tv`) into Theme.
* Helpers: `Layout.padding(n | {x, y, top, ...})`, `Layout.list({direction, gap, align, justify, wraps})`,
  `Layout.grid({cell, gap, maxCells})`, `Layout.flex({grow, shrink, fill})`, `Layout.sizeConstraint`, `Layout.aspect`.
* Layers (one ScreenGui each, `ResetOnSpawn` off, `ZIndexBehavior.Sibling`, `SafeAreaCompatibility.None`):
  Background3D 0 · HUD 10 · Screens 20 · TopBar 25 (`TopbarSafeInsets`) · Modals 30 · Toasts 40 · Tooltip 50 ·
  Debug 90. Interactive layers use `ScreenInsets.CoreUISafeInsets`; Background3D/Debug ignore insets.
* Touch: `Common.touchHeight(h)` raises controls to 44 px on touch (48 authored on Compact). Components do this
  already.

## Input modes and glyphs

`InputMode.mode` is `"MouseKeyboard" | "Gamepad" | "Touch"` (from `UserInputService.PreferredInput`). UI actions
(`Confirm`, `Back`, `Secondary`, `Tertiary`, `TabPrev`, `TabNext`, `PagePrev`, `PageNext`, `Scoreboard`; add more
with `InputMode.registerAction`) map to keyboard keys and gamepad buttons; `InputMode.glyph(action)` /
`KeyPrompt.new({ action, label })` show the right prompt (Xbox/PlayStation art from `GetImageForKeyCode`, keycaps on
keyboard, nothing on touch). `KeyPrompt.hintBar({ hints })` is the footer hint row.

* Reserved, never bound: Esc, ButtonStart, F9, F11, F12, PrintScreen (`InputMode.isReserved`).
* Menus use only the Input Action System (`UIInput`: context `KitUI`, priority 3100). Back is ignored while a TextBox
  has focus.
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

* LB/RB: the top scope's `onShoulder` handler (Router screens: `onShoulder`), else the newest `TabBar` visible inside
  the top scope (`Focus.registerShoulder`). TabBar shows the shoulder glyphs (Q/E keycaps on keyboard).
* Lists: `Focus.chain(list, "horizontal" | "vertical", wrap?)`, `Focus.grid(list, columns, wrap?)` set explicit
  neighbours; carousels/grids do not wrap (ui-ux §1.13). Scroll containers (`ScrollFrame`, `VirtualList`) reveal the
  selected element with 48 px of context (`Focus.revealOffset`).
* Disabled controls stay selectable (so their reason tooltip is reachable); activating them plays `ui_error`.

## Router

* `router:push(name, params)`, `pop()`, `replace`, `reset`, `openModal(name, params)`, `closeModal()`,
  `closeAllModals()`, `back()` (top screen's `onBack` first, then close modal / pop), `navigate("Garage/TechTree?faction=iron_union")`,
  `current()`, `history()`, `canGoBack()`, `layer(name)`, `layerRoot(name)`, `changed` (current, previous).
* Register options: `{ layer = "Screens", modal = false, dismissible = true, keepAlive = false, transition = "slide" |
  "fade" | "pop" | "none", focus = true }`.
* Screen contract (custom modules): `mount(parent)`, `show(params, { reason = "push" | "return" | "replace" | "reset",
  previous })`, `hide()`, `destroy()`, optional `onBack(): boolean?`, `initialFocus(): GuiObject?`,
  `onShoulder(direction)`. The new screen is built before the old one hides, so a failing build leaves the old screen
  up (errors are logged, never thrown into the caller).
* Transitions: screens slide 24 px + veil fade (none under reduced motion); modals pop (0.92 → 1).

## Motion

`Motion.tween(inst, props, { duration = "base", easing = "standard", kind = "move" | "scale" | "fade" | "color" })`
and the presets `fadeIn/fadeOut`, `slideIn/slideOut(gui, "right", 24)`, `pop`, `pulse` (returns stop), `shake`,
`countUp(from, to, onStep)`, `follow(state, scope)` (critically damped spring), `loop(step)` (Heartbeat),
`onComplete(tween, fn)`. Durations: `hover` 80 ms, `fast` 120, `base` 150, `slow` 200, `toast` 160, `flourish` 400,
`countUp` 600. Calm, ease-out, nothing bounces (brand-art §8.1).

Reduced motion (the player's setting OR `GuiService.ReducedMotionEnabled`) removes movement (slides, pops, pulses,
shakes, springs, count-ups jump) and caps fades/colour changes at 0.1 s. Always animate through Motion so this holds.

## Components

All components take the layout props `Name, Position, AnchorPoint, Size, LayoutOrder, ZIndex, Visible, Parent`
(any of them may be a State, `Parent` is applied last) plus their own props; text/number props accept States.
`children`/`actions` are typed `{ any }` (Luau tables are invariant, so `{ Text.body(...), Button.new(...) }` would not
check against `{ Instance }`).

| Component | Constructor and key props |
|---|---|
| Text | `Text.new({ text, role, color, align, wrap, truncate, autoSize, maxWidth, upper })`; shortcuts `Text.h1(text, opts)` … `Text.display/h1/h2/h3/h4/bodyLarge/body/bodySmall/label/caption/numXL/numL/numM/mono/micro/titleSmall` |
| Button | `Button.new({ text, variant = "primary"|"secondary"|"ghost"|"danger"|"battle", size = "large"|"medium"|"compact", icon, iconRight, hint, disabled, loading, onActivated, width = n|"fill"|"auto", sound, tooltip })` |
| IconButton | `IconButton.new({ icon, label (tooltip), variant = "ghost"|"secondary"|"primary", size = 44, disabled, selected, onActivated })` |
| Toggle | `Toggle.new({ label, value = Value<boolean> } | { checked, onChanged }, disabled)` |
| Slider | `Slider.new({ label, value = Value<number>, min, max, step, format, onChanged, disabled })` — d-pad/stick steps while focused |
| Dropdown | `Dropdown.new({ options = {{ value, label, icon, disabled }}, selected = Value, onChanged, placeholder, width, disabled })` |
| TabBar | `TabBar.new({ tabs = {{ id, label, icon, badge, disabled }}, selected = Value<string>, onChanged, variant = "top"|"segmented", shoulder })` |
| Chip | `Chip.new({ label, icon, tone, selected, disabled, onActivated, removable, onRemove })`, `Chip.tag(label, tone)` |
| Panel | `Panel.new({ title, number, icon, actions, variant = "default"|"raised"|"inset"|"hero", padding, autoHeight, list, children })`, `Panel.content(panel)` |
| Card | `Card.new({ onActivated, selected, disabled, rarity, padding, list, children, sound })` |
| Modal | `Modal.new({ title, icon, body, children, actions = {{ text, variant, id, icon, hint, disabled, onActivated, keepOpen, focus }}, size = "s"|"m"|"l", dismissible, onClose, banner })` (card for Router modal screens); `Modal.open(props + { onResult, anchor, initialFocus }) -> { close(result), isOpen(), closed, root, dialog }` |
| ConfirmDialog | `ConfirmDialog.open({ title, body, icon, confirmLabel, cancelLabel, destructive, size, children, onConfirm, onCancel })` — destructive: hazard band, danger button, focus on Cancel |
| Tooltip | `Tooltip.attach(target, "text" | { title, body }, { placement, delay }) -> detach`; `Tooltip.show/hide/owner`; `Tooltip.place` (pure) |
| Toast | `Toast.show({ title, body, tone, icon, action = { text, onActivated }, duration, sticky, key, sound }) -> id?`, `Toast.dismiss(id)` |
| ToastStack | `ToastStack.new({ parent, max = 3, position, anchorPoint })` → `:push(spec)`, `:dismiss(id)`, `:clear()`, `:ids()`, `:count()`, `:destroy()`; `ToastStack.default()` |
| ProgressBar | `ProgressBar.new({ value (0..1), indeterminate, ghost, color, height = 6, segments, animate = true })` |
| StatBar | `StatBar.new({ label, value, max, compare, lowerIsBetter, unit, decimals, format, bar })` |
| CurrencyLabel | `CurrencyLabel.new({ currency, amount, size = "s"|"m"|"l", style = "plain"|"panel", countUp, showDelta, compact, insufficient, prefix })` |
| Badge | `Badge.new({ kind = "tier"|"class"|"premium"|"new"|"count"|"text", tier, class, premium, elite, count, text, tone, size, compact })`, `Badge.tier(n)` |
| Icon | `Icon.new({ key, size = 24, color, transparency, forceGlyph })` (also `Kit/Components/Icon`) |
| KeyPrompt | `KeyPrompt.new({ action, label, size })`, `KeyPrompt.hintBar({ hints = {{ action, label }}, align })` |
| VirtualList | `local frame, controller = VirtualList.new({ items, render(item, index), itemSize, gap, padding, direction = "vertical"|"horizontal", crossSize, overscan = 2, revealPadding = 48, animate })` |
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
item while it stays in the window. The controller: `scrollToIndex(i, animate?)`, `selectIndex(i)` (gamepad),
`indexOf(instance)`, `slotFor(i)`, `range()`, `poolSize()`, `slotCount()`, `lanes()`, `refresh()`.

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
* Glyph sets: classes (+ minimap markers), tiers 1–11, currencies, ammo, modules (normal/damaged/destroyed, fire,
  repair), crew (+ injured), hit results, pings/commands, HUD spotted, UI glyphs. `Icons/Glyph` has the primitives
  (rect, circle, ring with arc, triangle, wedge, hexagon, chamfer rect, chevron, arrow, text, check, cross, ...).
* New feature glyph: `Icon.register("vehicles/iu_forge", { build = function(c, p) Glyph.rect(c, 8, 20, 48, 24, p.fg) end, color = "brand.bone" })`
  (64-unit canvas). It is declared to the resolver so `resolveImage` reports a glyph instead of "missing".
* `AssetManifest.luau` is **generated by tools/assets** (never hand-edit); `AssetResolver.default()` reads it.
  `resolver:image(key)`, `resolveImage(key) -> { kind = "image"|"glyph"|"badge"|"missing", ... }`, `sound(key)`,
  `has`, `hasFallback`, `validateKeys(keys, { kind, allowFallback })`, `missing()`. Unknown keys warn once.

## Accessibility checklist (every screen)

- [ ] Every interactive element is reachable and operable with mouse, touch **and** gamepad; `initialFocus` set;
      nothing is reachable only by hover.
- [ ] Back (B / Backspace / Esc menu) always does something sensible: closes the top popup/drawer/modal, then pops.
- [ ] Text uses typography roles only (no `TextScaled`, no literal sizes); layouts survive text scale 1.5 and
      Compact (844×390) without clipping — check in the gallery with the text-scale slider.
- [ ] Colours come from tokens; meaning is never colour-only (icons, signs, labels); team colours read correctly in
      all four schemes and with high contrast (gallery header toggles).
- [ ] Touch targets ≥ 44 rendered px (48 authored on Compact), ≥ 8 px apart.
- [ ] Motion goes through Kit/Motion (reduced motion respected); no flashing faster than 3 Hz.
- [ ] Disabled controls explain why (tooltip / inline reason) and stay focusable.
- [ ] Destructive or expensive actions use `ConfirmDialog` with `destructive = true` (focus starts on Cancel).
- [ ] Lists have empty states; loads show skeletons/spinners; numbers use `Format` (U+2212 minus, grouping).
- [ ] Toast content is also reachable from the screen or the notification centre (toasts never take focus).

## Gallery

`Client/UI/Dev/KitGallery.luau` is a Router screen (`KitGallery.register(router)`; `router:push("KitGallery")`)
with sections Foundations (colour tokens, team colours per scheme, typography, surfaces, spacing), Buttons, Inputs,
Surfaces (panels, cards, dividers, dialogs), Feedback (toasts, progress, spinners, skeletons, empty state, tooltip),
Data (stat bars, currencies, badges), Icons (every registry key, virtualised) and Lists (500-row VirtualList). The
header switches scheme, high contrast, reduced motion, text scale and the input-mode preview (global on purpose).

## Testing UI

Specs live under `tests/Unit/ReplicatedStorage/Client/UI/...`. `KitTestSupport.install()` defines the GUI mock
classes and fake services (TweenService that completes instantly or on `env:completeTweens()` with
`env.deferTweens = true`, UserInputService with Xbox key names, GuiService selection, RunService `env:step(dt)` for
Heartbeat-driven timers). Helpers: `Support.find`, `Support.click`, `Support.fire`, `Support.select(guiService, obj)`,
`Support.input{...}`, and `Support.validateTree(root)`, which checks every assigned property against the Roblox API
dump (`$HULLDOWN_TOOLS/API-Dump.json`: property exists, value type/enum matches, not read-only) — call it on
everything you build. Engine-owned values (AbsoluteSize, AbsolutePosition) are set with
`rawget(inst, "_props").AbsoluteSize = v` (+ firing the property signal) so they do not count as script writes.

## Strict-mode typing notes

* String-literal unions widen to `string` when iterated (`for _, v in {"a", "b"}`) or passed through generics; use an
  indexed loop, annotate the local (`local role: Theme.TypeRole = ...`) or cast at the call (`v :: any`).
* Component props are flat types (no `&` intersections) so table literals check; keep it that way when adding props.
* `State.get/peek/map/of/list` are overloaded (`State<T>` and `CanBeState<T>`), so passing either works.
