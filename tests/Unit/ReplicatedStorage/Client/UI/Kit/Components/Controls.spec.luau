local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local Focus = require("@game/ReplicatedStorage/Client/UI/Kit/Focus")
local UIInput = require("@game/ReplicatedStorage/Client/UI/Kit/UIInput")
local Layers = require("@game/ReplicatedStorage/Client/UI/Kit/Layers")
local Layout = require("@game/ReplicatedStorage/Client/UI/Kit/Layout")
local Sound = require("@game/ReplicatedStorage/Client/UI/Kit/Sound")
local Button = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Button")
local IconButton = require("@game/ReplicatedStorage/Client/UI/Kit/Components/IconButton")
local Toggle = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Toggle")
local Slider = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Slider")
local Dropdown = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Dropdown")
local TabBar = require("@game/ReplicatedStorage/Client/UI/Kit/Components/TabBar")
local Chip = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Chip")
local Tooltip = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Tooltip")
local KeyPrompt = require("@game/ReplicatedStorage/Client/UI/Kit/Components/KeyPrompt")
local Text = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Text")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

local function registerLayers(): any
	local gui = Create("ScreenGui", { Name = "TestLayers", Parent = env.playerGui })
	for _, name in { "Modals", "Toasts", "Tooltip" } do
		Layers.register(name :: any, Create("Frame", { Name = name, Size = UDim2.fromScale(1, 1), Parent = gui }))
	end
	return gui
end

local function reset()
	Theme.reset()
	Focus.reset()
	Layers.clear()
	Sound.resetCounts()
	InputMode.set("MouseKeyboard")
	UIInput.setEnabled(true)
	Support.select(env.guiService, nil)
end

describe("Button", function()
	Test.beforeEach(reset)

	it("derives the visual state and width rules (pure)", function()
		expect(Button.visualState(true, true, true)).toBe("disabled")
		expect(Button.visualState(false, true, true)).toBe("pressed")
		expect(Button.visualState(false, false, true)).toBe("hover")
		expect(Button.visualState(false, false, false)).toBe("idle")
		-- Minimum 2.5 x height; battle minimum 280.
		expect(Button.computeWidth("secondary", 44, 10, 0)).toBe(110)
		expect(Button.computeWidth("secondary", 44, 200, 0)).toBe(232)
		expect(Button.computeWidth("battle", 64, 10, 0)).toBe(280)
	end)

	it("activates, plays sounds and blocks when disabled or loading", function()
		local count = 0
		local disabled = State.Value(false)
		local loading = State.Value(false)
		local button = Button.new({
			text = "Research",
			variant = "primary",
			disabled = disabled,
			loading = loading,
			onActivated = function()
				count += 1
			end,
		})
		Support.click(button)
		expect(count).toBe(1)
		expect(Sound.counts()[Sound.KEYS.confirm]).toBe(1)
		disabled:set(true)
		Support.click(button)
		expect(count).toBe(1)
		expect(Sound.counts()[Sound.KEYS.error]).toBe(1)
		expect(Support.find(button, "FillDisabled").Visible).toBe(true)
		expect(Support.find(button, "FillIdle").Visible).toBe(false)
		disabled:set(false)
		loading:set(true)
		Support.click(button)
		expect(count).toBe(1)
		expect(Support.find(button, "Spinner").Visible).toBe(true)
		Support.validateTree(button)
		button:Destroy()
	end)

	it("shows hover/pressed surfaces and moves the label down when pressed", function()
		local button = Button.new({ text = "Battle", variant = "battle" })
		expect(button.Size.Y.Offset).toBe(64)
		expect(button.Size.X.Offset >= 280).toBe(true)
		Support.fire(button, "MouseEnter")
		expect(Support.find(button, "FillHover").Visible).toBe(true)
		expect(Support.find(button, "Glow").Visible).toBe(true)
		Support.fire(button, "MouseButton1Down")
		expect(Support.find(button, "FillPressed").Visible).toBe(true)
		expect(Support.find(button, "Content").Position).toEqual(UDim2.fromOffset(0, 1))
		Support.fire(button, "MouseButton1Up")
		Support.fire(button, "MouseLeave")
		expect(Support.find(button, "FillIdle").Visible).toBe(true)
		button:Destroy()
	end)

	it("raises compact buttons to the touch minimum on touch (48 authored on Compact)", function()
		local button = Button.new({ text = "Sell", size = "compact" })
		expect(button.Size.Y.Offset).toBe(36)
		InputMode.set("Touch")
		expect(button.Size.Y.Offset).toBe(44)
		Layout.setEnvironment({ viewport = Vector2.new(844, 390) })
		expect(button.Size.Y.Offset).toBe(48)
		Layout.setEnvironment({ viewport = Vector2.new(1920, 1080) })
		expect(button.Size.Y.Offset).toBe(44)
		button:Destroy()
	end)

	it("follows theme changes without rebuilding (high contrast)", function()
		local button = Button.new({ text = "Details", variant = "ghost" })
		local label = Support.find(button, "Label")
		expect(label.TextColor3).toEqual(Theme.peekColor("text.secondary"))
		Theme.set({ highContrast = true })
		expect(label.TextColor3).toEqual(Theme.peekColor("text.primary"))
		button:Destroy()
	end)

	it("swaps to the -ING label while loading but keeps its width", function()
		local loading = State.Value(false)
		local button = Button.new({ text = "Research", loadingText = "Researching", loading = loading })
		local label = Support.find(button, "Label")
		local width = button.Size.X.Offset
		expect(label.Text).toBe("Research")
		loading:set(true)
		expect(label.Text).toBe("Researching")
		expect(button.Size.X.Offset).toBe(width)
		loading:set(false)
		expect(label.Text).toBe("Research")
		button:Destroy()
	end)

	it("premium buttons take a Bullion border on hover and gamepad focus", function()
		local button = Button.new({ text = "1,250", variant = "premium", icon = "currency/bullion" })
		local edge = Support.find(Support.find(button, "Fill"), "EdgeTop")
		expect(edge.BackgroundColor3).toEqual(Theme.peekColor("border.strong"))
		Support.fire(button, "MouseEnter")
		expect(edge.BackgroundColor3).toEqual(Theme.peekColor("currency.bullion"))
		Support.fire(button, "MouseLeave")
		Support.select(env.guiService, button)
		expect(edge.BackgroundColor3).toEqual(Theme.peekColor("currency.bullion"))
		Support.select(env.guiService, nil)
		-- High contrast thickens the border.
		expect(edge.Size.Y.Offset).toBe(1)
		Theme.set({ highContrast = true })
		expect(edge.Size.Y.Offset).toBe(2)
		button:Destroy()
	end)

	it("hold-to-confirm: touch hold completes, release cancels, mouse clicks", function()
		local count = 0
		local button = Button.new({
			text = "Sell",
			variant = "danger",
			hold = 0.5,
			onActivated = function()
				count += 1
			end,
		})
		Support.click(button)
		expect(count).toBe(1)
		InputMode.set("Touch")
		Support.click(button)
		expect(count).toBe(1)
		Support.fire(button, "InputBegan", Support.input({ UserInputType = Enum.UserInputType.Touch }))
		for _ = 1, 12 do
			env:step(1 / 60)
		end
		Support.fire(button, "InputEnded", Support.input({ UserInputType = Enum.UserInputType.Touch }))
		expect(count).toBe(1)
		expect(Support.find(button, "HoldFill").Visible).toBe(false)
		Support.fire(button, "InputBegan", Support.input({ UserInputType = Enum.UserInputType.Touch }))
		for _ = 1, 40 do
			env:step(1 / 60)
		end
		expect(count).toBe(2)
		button:Destroy()
	end)

	it("builds every variant with valid properties", function()
		for _, variant in { "primary", "secondary", "ghost", "danger", "premium", "battle" } do
			for _, size in { "large", "medium", "compact" } do
				local button = Button.new({
					text = "Label",
					variant = variant :: any,
					size = size :: any,
					icon = "ui/check",
					iconRight = "ui/chevron_right",
					hint = "Tertiary",
				})
				Support.validateTree(button)
				button:Destroy()
			end
		end
		expect(function()
			Button.new({ text = "x", variant = "fancy" :: any })
		end).toThrow("unknown variant")
	end)
end)

describe("IconButton, Toggle, Slider, Chip", function()
	Test.beforeEach(reset)

	it("IconButton activates unless disabled", function()
		local count = 0
		local disabled = State.Value(false)
		local button = IconButton.new({
			icon = "ui/settings",
			label = "Settings",
			disabled = disabled,
			onActivated = function()
				count += 1
			end,
		})
		Support.click(button)
		disabled:set(true)
		Support.click(button)
		expect(count).toBe(1)
		Support.validateTree(button)
		button:Destroy()
	end)

	it("Toggle flips its bound value and reports changes", function()
		local value = State.Value(false)
		local changes = {}
		local toggle = Toggle.new({
			label = "Invert Y",
			value = value,
			onChanged = function(checked: boolean)
				table.insert(changes, checked)
			end,
		})
		Support.click(toggle)
		expect(value:peek()).toBe(true)
		Support.click(toggle)
		expect(value:peek()).toBe(false)
		expect(changes).toEqual({ true, false })
		expect(Sound.counts()[Sound.KEYS.toggleOn]).toBe(1)
		expect(Sound.counts()[Sound.KEYS.toggleOff]).toBe(1)
		Support.validateTree(toggle)
		toggle:Destroy()
	end)

	it("Toggle with `checked` is controlled by the caller", function()
		local checked = State.Value(true)
		local toggle = Toggle.new({
			checked = checked,
			onChanged = function(next: boolean)
				checked:set(next)
			end,
		})
		Support.click(toggle)
		expect(checked:peek()).toBe(false)
		toggle:Destroy()
	end)

	it("Slider snaps and maps fractions (pure)", function()
		expect(Slider.snap(0.34, 0, 1, 0.1)).toBe(0.3)
		expect(Slider.snap(0.35, 0, 1, 0.1)).toBe(0.4)
		expect(Slider.snap(7, 0, 5, 1)).toBe(5)
		expect(Slider.snap(0 / 0, 2, 5, 1)).toBe(2)
		expect(Slider.snap(0.1 + 0.2, 0, 1, 0.1)).toBe(0.3)
		expect(Slider.fraction(75, 50, 150)).toBe(0.25)
		expect(Slider.fraction(1, 1, 1)).toBe(0)
		expect(Slider.fromFraction(0.5, 0.8, 1.5, 0.05)).toBe(1.15)
	end)

	it("Slider steps with the d-pad while selected (even when navigation marks it processed)", function()
		InputMode.set("Gamepad")
		local value = State.Value(1)
		local slider = Slider.new({ label = "Text size", value = value, min = 0.8, max = 1.5, step = 0.1 })
		local track = Support.find(slider, "Track")
		Support.select(env.guiService, track)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.DPadRight }), true)
		expect(value:peek()).toBe(1.1)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.Left }), true)
		expect(value:peek()).toBe(1.1)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.Left }), false)
		expect(value:peek()).toBe(1)
		Support.select(env.guiService, nil)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.DPadRight }), true)
		expect(value:peek()).toBe(1)
		Support.validateTree(slider)
		slider:Destroy()
	end)

	it("Chip toggles, removes and builds static tags", function()
		local selected = State.Value(false)
		local removed = 0
		local filter = Chip.new({
			label = "Heavy",
			icon = "classes/heavy",
			selected = selected,
			onActivated = function()
				selected:set(not selected:peek())
			end,
		})
		Support.click(filter)
		expect(selected:peek()).toBe(true)
		expect(Support.find(filter, "Label").TextColor3).toEqual(Theme.peekColor("text.primary"))
		local token = Chip.new({
			label = "Tier VIII",
			removable = true,
			onRemove = function()
				removed += 1
			end,
		})
		Support.click(Support.find(token, "Remove"))
		-- Gamepad: activating a removable chip without onActivated removes it.
		Support.click(token)
		expect(removed).toBe(2)
		local tag = Chip.tag("HEAT", "warning")
		expect(tag.Selectable).toBe(false)
		expect(Support.find(tag, "Dot")).never.toBeNil()
		for _, chip in { filter, token, tag } do
			Support.validateTree(chip)
			chip:Destroy()
		end
	end)
end)

describe("Dropdown", function()
	Test.beforeEach(reset)

	local options = {
		{ value = "low", label = "Low" },
		{ value = "medium", label = "Medium" },
		{ value = "high", label = "High", icon = "ui/warning" },
		{ value = "ultra", label = "Ultra", disabled = true },
	}

	it("labels the selection and places the popup (pure)", function()
		expect({ Dropdown.labelFor(options, "high") }).toEqual({ "High", true })
		expect({ Dropdown.labelFor(options, "nope", "Pick one") }).toEqual({ "Pick one", false })
		-- Below the field when it fits.
		expect(Dropdown.popupPosition(Vector2.new(100, 100), Vector2.new(240, 44), 200, Vector2.new(1920, 1080))).toEqual(
			Vector2.new(100, 148)
		)
		-- Flipped above near the bottom edge.
		expect(Dropdown.popupPosition(Vector2.new(100, 900), Vector2.new(240, 44), 200, Vector2.new(1920, 1080))).toEqual(
			Vector2.new(100, 696)
		)
	end)

	it("opens a trapped list in the Tooltip layer (above modals), selects, and closes on Back", function()
		local gui = registerLayers()
		InputMode.set("Gamepad")
		local selected = State.Value("medium")
		local changes = {}
		local field = Dropdown.new({
			options = options,
			selected = selected,
			onChanged = function(value: any)
				table.insert(changes, value)
			end,
			Parent = gui,
		})
		expect(Support.find(field, "Value").Text).toBe("Medium")
		Support.click(field)
		local popup = Support.find(Layers.get("Tooltip"), "DropdownPopup")
		expect(popup).never.toBeNil()
		-- Focus starts on the selected option and is trapped in the list.
		expect(env.guiService.SelectedObject).toBe(Support.find(popup, "Option2"))
		expect(Focus.top().trap).toBe(true)
		-- Disabled options are inert.
		Support.click(Support.find(popup, "Option4"))
		expect(selected:peek()).toBe("medium")
		Support.click(Support.find(popup, "Option3"))
		expect(selected:peek()).toBe("high")
		expect(changes).toEqual({ "high" })
		expect(Support.find(Layers.get("Tooltip"), "DropdownPopup")).toBeNil()
		expect(Support.find(field, "Value").Text).toBe("High")
		-- Back closes the popup instead of reaching the router.
		Support.click(field)
		expect(Support.find(Layers.get("Tooltip"), "DropdownPopup")).never.toBeNil()
		expect(UIInput.interceptBackNow()).toBe(true)
		expect(Support.find(Layers.get("Tooltip"), "DropdownPopup")).toBeNil()
		expect(UIInput.interceptBackNow()).toBe(false)
		expect(Focus.top()).toBeNil()
		-- Destroying the field while open closes the popup.
		Support.click(field)
		field:Destroy()
		expect(Support.find(Layers.get("Tooltip"), "DropdownPopup")).toBeNil()
		gui:Destroy()
	end)

	it("ignores activation while disabled", function()
		local gui = registerLayers()
		local field = Dropdown.new({ options = options, selected = State.Value(nil), disabled = true, Parent = gui })
		expect(Support.find(field, "Value").Text).toBe("Select")
		Support.click(field)
		expect(Support.find(Layers.get("Tooltip"), "DropdownPopup")).toBeNil()
		Support.validateTree(field)
		gui:Destroy()
	end)
end)

describe("TabBar", function()
	Test.beforeEach(reset)

	local tabs = {
		{ id = "garage", label = "Garage" },
		{ id = "research", label = "Research", icon = "ui/search", badge = 3 },
		{ id = "store", label = "Store", disabled = true },
		{ id = "battlepass", label = "Season" },
	}

	it("cycles ids with wrap-around, skipping disabled tabs (pure)", function()
		expect(TabBar.cycle(tabs, "garage", 1)).toBe("research")
		expect(TabBar.cycle(tabs, "research", 1)).toBe("battlepass")
		expect(TabBar.cycle(tabs, "battlepass", 1)).toBe("garage")
		expect(TabBar.cycle(tabs, "garage", -1)).toBe("battlepass")
		expect(TabBar.cycle(tabs, "unknown", 1)).toBe("garage")
		expect(TabBar.cycle({}, "x", 1)).toBeNil()
		expect(TabBar.cycle({ { id = "a", label = "A", disabled = true } }, "a", 1)).toBeNil()
	end)

	it("selects on click, shows the active underline and routes shoulder presses", function()
		local selected = State.Value("garage")
		local changes = {}
		local root = Create("Frame", { Name = "ScreenRoot" })
		local bar = TabBar.new({
			tabs = tabs,
			selected = selected,
			onChanged = function(id: string)
				table.insert(changes, id)
			end,
			Parent = root,
		})
		local garage = Support.find(bar, "Tab_garage")
		local research = Support.find(bar, "Tab_research")
		expect(Support.find(garage, "Underline").Visible).toBe(true)
		expect(Support.find(research, "Underline").Visible).toBe(false)
		expect(Support.find(research, "Badge")).never.toBeNil()
		Support.click(research)
		expect(selected:peek()).toBe("research")
		expect(Support.find(research, "Underline").Visible).toBe(true)
		Support.click(Support.find(bar, "Tab_store"))
		expect(selected:peek()).toBe("research")
		expect(Sound.counts()[Sound.KEYS.error]).toBe(1)
		-- LB/RB through Kit/Focus while the bar is inside the top scope.
		local scope = Focus.scope(root, { name = "Screen" })
		scope:activate()
		expect(Focus.shoulder(1)).toBe(true)
		expect(selected:peek()).toBe("battlepass")
		expect(Focus.shoulder(-1)).toBe(true)
		expect(selected:peek()).toBe("research")
		expect(changes).toEqual({ "research", "battlepass", "research" })
		-- Shoulder glyphs: keycaps on keyboard, hidden on touch.
		local prompts = {}
		for _, d in bar:GetChildren() do
			if d.Name == "KeyPrompt" then
				table.insert(prompts, d)
			end
		end
		expect(#prompts).toBe(2)
		expect(prompts[1].Visible).toBe(true)
		InputMode.set("Touch")
		expect(prompts[1].Visible).toBe(false)
		Support.validateTree(bar)
		bar:Destroy()
		expect(Focus.shoulder(1)).toBe(false)
		scope:Destroy()
	end)

	it("builds the segmented variant and reacts to tab list changes", function()
		local list = State.Value({ { id = "a", label = "All" }, { id = "b", label = "Owned" } })
		local selected = State.Value("a")
		local bar = TabBar.new({ tabs = list, selected = selected, variant = "segmented" })
		expect(Support.find(bar, "Segment_a")).never.toBeNil()
		expect(Support.find(bar, "KeyPrompt")).toBeNil()
		list:set({ { id = "b", label = "Owned" }, { id = "c", label = "Premium" } })
		expect(Support.find(bar, "Segment_a")).toBeNil()
		expect(Support.find(bar, "Segment_c")).never.toBeNil()
		Support.click(Support.find(bar, "Segment_c"))
		expect(selected:peek()).toBe("c")
		Support.validateTree(bar)
		bar:Destroy()
	end)
end)

describe("Tooltip", function()
	Test.beforeEach(reset)

	it("follows the right > left > below > above priority, flips and clamps (pure)", function()
		local viewport = Vector2.new(1920, 1080)
		local tip = Vector2.new(200, 60)
		local position, side = Tooltip.place(Vector2.new(500, 500), Vector2.new(100, 40), tip, viewport)
		expect(side).toBe("right")
		expect(position).toEqual(Vector2.new(608, 490))
		-- No room on the right: left.
		position, side = Tooltip.place(Vector2.new(1800, 500), Vector2.new(100, 40), tip, viewport)
		expect(side).toBe("left")
		expect(position).toEqual(Vector2.new(1800 - 8 - 200, 490))
		-- A full-width target: below, then above.
		position, side = Tooltip.place(Vector2.new(0, 500), Vector2.new(1920, 40), tip, viewport)
		expect(side).toBe("bottom")
		expect(position).toEqual(Vector2.new(860, 548))
		position, side = Tooltip.place(Vector2.new(0, 1000), Vector2.new(1920, 60), tip, viewport)
		expect(side).toBe("top")
		-- An explicit side flips only to its opposite.
		position, side = Tooltip.place(Vector2.new(500, 20), Vector2.new(100, 40), tip, viewport, "top")
		expect(side).toBe("bottom")
		expect(position).toEqual(Vector2.new(450, 68))
		-- Nothing fits: the first candidate is clamped into the viewport.
		position = Tooltip.place(Vector2.new(0, 0), Vector2.new(1920, 1080), tip, viewport)
		expect(position.X >= 0 and position.X <= 1720).toBe(true)
	end)

	it("shows after the hover delay, on gamepad selection, and hides on leave", function()
		local gui = registerLayers()
		local target = Create("TextButton", { Name = "Target", Parent = gui })
		local detach = Tooltip.attach(target, { title = "Reload", body = "7.4 s" })
		Support.fire(target, "MouseEnter")
		expect(Tooltip.owner()).toBeNil()
		for _ = 1, 30 do
			env:step(1 / 60)
		end
		expect(Tooltip.owner()).toBe(target)
		local view = Support.find(Layers.get("Tooltip"), "KitTooltip")
		expect(view.Visible).toBe(true)
		expect(Support.find(view, "Title").Text).toBe("Reload")
		expect(Support.find(view, "Body").Text).toBe("7.4 s")
		Support.fire(target, "MouseLeave")
		expect(Tooltip.owner()).toBeNil()
		expect(view.Visible).toBe(false)
		-- Leaving before the delay cancels the pending show.
		Support.fire(target, "MouseEnter")
		Support.fire(target, "MouseLeave")
		for _ = 1, 40 do
			env:step(1 / 60)
		end
		expect(Tooltip.owner()).toBeNil()
		-- Gamepad focus shows it after 0.6 s.
		Support.fire(target, "SelectionGained")
		for _ = 1, 30 do
			env:step(1 / 60)
		end
		expect(Tooltip.owner()).toBeNil()
		for _ = 1, 10 do
			env:step(1 / 60)
		end
		expect(Tooltip.owner()).toBe(target)
		detach()
		expect(Tooltip.owner()).toBeNil()
		Support.validateTree(view)
		gui:Destroy()
	end)
end)

describe("Text and KeyPrompt", function()
	Test.beforeEach(reset)

	it("applies typography roles, case and colour tokens", function()
		local label = Text.label("Hull points")
		expect(label.Text).toBe("HULL POINTS")
		expect(label.TextSize).toBe(Theme.textSize("label"):peek())
		expect(label.AutomaticSize).toBe(Enum.AutomaticSize.XY)
		local body = Text.body("Long sentence", { Size = UDim2.new(1, 0, 0, 0), color = "text.secondary" })
		expect(body.TextWrapped).toBe(true)
		expect(body.AutomaticSize).toBe(Enum.AutomaticSize.Y)
		expect(body.TextColor3).toEqual(Theme.peekColor("text.secondary"))
		Theme.set({ textScale = 1.5 })
		expect(label.TextSize).toBe(Theme.textSize("label"):peek())
		Support.validateTree(label)
		Support.validateTree(body)
	end)

	it("hint bar shows on gamepad, on keyboard only when asked, never on touch", function()
		local bar = KeyPrompt.hintBar({ hints = { { action = "Back", label = "Back" } } })
		local kbm = KeyPrompt.hintBar({ hints = { { action = "Back", label = "Back" } }, keyboard = true })
		expect(bar.Size.Y.Offset).toBe(48)
		expect(bar.Visible).toBe(false)
		expect(kbm.Visible).toBe(true)
		InputMode.set("Gamepad")
		expect(bar.Visible).toBe(true)
		InputMode.set("Touch")
		expect(bar.Visible).toBe(false)
		expect(kbm.Visible).toBe(false)
		local keycap = Support.find(KeyPrompt.new({ action = "Back" }), "Keycap")
		InputMode.set("MouseKeyboard")
		expect(Support.find(keycap, "Text").FontFace.Family).toBe(Theme.font("keycap").Family)
		Support.validateTree(bar)
		bar:Destroy()
		kbm:Destroy()
	end)

	it("KeyPrompt follows the input mode and respects the caller's Visible", function()
		local shown = State.Value(true)
		local prompt = KeyPrompt.new({ action = "Confirm", label = "Select", Visible = shown })
		expect(prompt.Visible).toBe(true)
		expect(Support.find(prompt, "Keycap").Visible).toBe(true)
		InputMode.set("Gamepad")
		expect(Support.find(prompt, "ButtonImage").Visible).toBe(true)
		shown:set(false)
		expect(prompt.Visible).toBe(false)
		shown:set(true)
		InputMode.set("Touch")
		expect(prompt.Visible).toBe(false)
		Support.validateTree(prompt)
		prompt:Destroy()
	end)
end)
