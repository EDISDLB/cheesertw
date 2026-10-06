--[[
	ReviewRegressions — adversarial regressions from the UI-kit review (one describe per defect). Each test failed
	against the kit as first delivered and passes with the fix; see docs/systems/ui-kit.md for the behaviour.
]]

local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local Format = require("@game/ReplicatedStorage/Client/UI/Kit/Format")
local Motion = require("@game/ReplicatedStorage/Client/UI/Kit/Motion")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local Focus = require("@game/ReplicatedStorage/Client/UI/Kit/Focus")
local Layers = require("@game/ReplicatedStorage/Client/UI/Kit/Layers")
local Router = require("@game/ReplicatedStorage/Client/UI/Kit/Router")
local Sound = require("@game/ReplicatedStorage/Client/UI/Kit/Sound")
local Button = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Button")
local IconButton = require("@game/ReplicatedStorage/Client/UI/Kit/Components/IconButton")
local Slider = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Slider")
local TabBar = require("@game/ReplicatedStorage/Client/UI/Kit/Components/TabBar")
local Tooltip = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Tooltip")
local Toast = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Toast")
local ConfirmDialog = require("@game/ReplicatedStorage/Client/UI/Kit/Components/ConfirmDialog")
local Modal = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Modal")
local Dropdown = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Dropdown")
local Chip = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Chip")
local StatBar = require("@game/ReplicatedStorage/Client/UI/Kit/Components/StatBar")
local CurrencyLabel = require("@game/ReplicatedStorage/Client/UI/Kit/Components/CurrencyLabel")
local UIInput = require("@game/ReplicatedStorage/Client/UI/Kit/UIInput")
local KeyPrompt = require("@game/ReplicatedStorage/Client/UI/Kit/Components/KeyPrompt")
local Toggle = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Toggle")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

local function setAbsolute(object: any, position: Vector2?, size: Vector2?)
	local props = rawget(object, "_props")
	if position ~= nil then
		props.AbsolutePosition = position
	end
	if size ~= nil then
		props.AbsoluteSize = size
	end
end

local function reset()
	Theme.reset()
	Focus.reset()
	Layers.clear()
	Sound.resetCounts()
	InputMode.set("MouseKeyboard")
	env.deferTweens = false
	env:completeTweens()
	env.guiService.SelectedObject = nil
end

-- A ScreenGui with registered overlay layers (plain frames, no UIScale/padding unless the test adds them).
local function overlayLayers(): any
	local gui = Create("ScreenGui", { Name = "Layers", Parent = env.playerGui })
	for _, name in { "Modals", "Toasts", "Tooltip" } do
		Layers.register(name :: any, Create("Frame", { Name = name, Size = UDim2.fromScale(1, 1), Parent = gui }))
	end
	return gui
end

describe("Router: LB/RB reach a TabBar inside a screen", function()
	Test.beforeEach(reset)

	it("does not shadow the TabBar's shoulder handler with an empty screen handler", function()
		InputMode.set("Gamepad")
		local stopInstall = Focus.install({ playerGui = env.playerGui, startInput = false })
		local router = Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		local tab = State.Value("modules")
		router:register(
			"Research",
			Router.define({
				build = function(_ctx)
					return Create.Frame({
						Name = "ResearchRoot",
						Size = UDim2.fromScale(1, 1),
						[Create.Children] = {
							TabBar.new({
								tabs = {
									{ id = "modules", label = "Modules" },
									{ id = "crew", label = "Crew" },
								},
								selected = tab,
							}),
						},
					})
				end,
			})
		)
		local pages = {}
		router:register(
			"TechTree",
			Router.define({
				build = function(_ctx)
					return Create.Frame({ Name = "TreeRoot" })
				end,
				onShoulder = function(_ctx, direction: number)
					table.insert(pages, direction)
				end,
			})
		)
		router:push("Research")
		expect(Focus.shoulder(1)).toBe(true)
		expect(tab:peek()).toBe("crew")
		expect(Focus.shoulder(1)).toBe(true)
		expect(tab:peek()).toBe("modules")
		-- A screen that defines onShoulder still owns LB/RB.
		router:push("TechTree")
		expect(Focus.shoulder(-1)).toBe(true)
		expect(pages).toEqual({ -1 })
		expect(tab:peek()).toBe("modules")
		router:destroy()
		stopInstall()
	end)
end)

describe("Router: battle HUD layers use hud.scale, not the menu UI scale", function()
	Test.beforeEach(reset)

	it("roots HUD and HUDInput on Layout.state.hudScale", function()
		local Layout = require("@game/ReplicatedStorage/Client/UI/Kit/Layout")
		Layout.setEnvironment({
			viewport = Vector2.new(1920, 1080),
			tenFoot = false,
			displaySize = Enum.DisplaySize.Medium,
		})
		Theme.set({ uiScale = 1.2, hudScale = 0.8 })
		local router = Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		for _, name in { "HUD", "HUDInput" } do
			expect(router:layerRoot(name :: any):FindFirstChildOfClass("UIScale").Scale).toBeCloseTo(0.8, 1e-9)
		end
		expect(router:layerRoot("Screens"):FindFirstChildOfClass("UIScale").Scale).toBeCloseTo(1.2, 1e-9)
		router:destroy()
	end)
end)

describe("Router: keepAlive screens never leak a second instance", function()
	Test.beforeEach(reset)

	it("destroys every instance of a keepAlive screen pushed while already on the stack", function()
		local created, destroyed = 0, 0
		local store = {
			new = function(_ctx: any): any
				created += 1
				local screen: any = {}
				function screen.mount(_self: any, parent: any)
					Create.Frame({ Name = "StoreRoot", Parent = parent })
				end
				function screen.show() end
				function screen.hide() end
				function screen.destroy()
					destroyed += 1
				end
				return screen
			end,
		}
		local router = Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		router:register(
			"Garage",
			Router.define({
				build = function()
					return Create.Frame({ Name = "GarageRoot" })
				end,
			})
		)
		router:register("Store", store, { keepAlive = true })
		router:push("Garage")
		router:push("Store")
		router:push("Store")
		expect(created).toBe(2)
		router:pop()
		router:pop()
		expect(destroyed).toBe(1)
		-- The cached one is reused, not rebuilt.
		router:push("Store")
		expect(created).toBe(2)
		router:destroy()
		expect(destroyed).toBe(2)
	end)
end)

describe("Router: screen actions fire only for the active screen", function()
	local gui: any
	Test.beforeEach(function()
		reset()
		gui = overlayLayers()
	end)
	Test.afterEach(function()
		gui:Destroy()
	end)

	it("routes ctx.on(Secondary) to the top screen, never to covered screens or under dialogs", function()
		local hits = {}
		local function screen(name: string): any
			return Router.define({
				build = function(ctx)
					ctx.on("Secondary", function()
						table.insert(hits, name)
					end)
					return Create.Frame({
						Name = name .. "Root",
						[Create.Children] = {
							Create("TextButton", { Name = "Action" }),
						},
					})
				end,
			})
		end
		local router = Router.new({ parent = env.playerGui, backSignal = Signal.new(), registerLayers = false })
		router:register("Garage", screen("Garage"), { keepAlive = true })
		router:register("Inspect", screen("Inspect"))
		router:push("Garage")
		UIInput.secondary:Fire()
		expect(hits).toEqual({ "Garage" })
		router:push("Inspect")
		UIInput.secondary:Fire()
		expect(hits).toEqual({ "Garage", "Inspect" })
		router:pop()
		UIInput.secondary:Fire()
		expect(hits).toEqual({ "Garage", "Inspect", "Garage" })
		-- A self-managed dialog above the screen owns the input.
		local dialog = Modal.open({ title = "Info" })
		UIInput.secondary:Fire()
		expect(#hits).toBe(3)
		dialog.close()
		UIInput.secondary:Fire()
		expect(#hits).toBe(4)
		-- A drawer scope inside the screen is still the screen.
		local garageRoot = Support.find(router:layerRoot("Screens"), "GarageRoot")
		local drawer = Focus.scope(garageRoot, { name = "Drawer", trap = true })
		drawer:activate()
		UIInput.secondary:Fire()
		expect(#hits).toBe(5)
		drawer:Destroy()
		router:destroy()
		-- Destroyed screens are disconnected.
		UIInput.secondary:Fire()
		expect(#hits).toBe(5)
	end)
end)

describe("Router: transitions follow ui-ux §1.3", function()
	Test.beforeEach(reset)

	it("fades roots (reset), slides drill-ins (push) and pops modals", function()
		expect(Router.transitionFor({}, false, "reset")).toBe("fade")
		expect(Router.transitionFor({}, false, "push")).toBe("slide")
		expect(Router.transitionFor({}, false, "return")).toBe("slide")
		expect(Router.transitionFor({}, true, "push")).toBe("pop")
		expect(Router.transitionFor({ transition = "fade" }, false, "push")).toBe("fade")
		local router = Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		local function screen(name: string): any
			return Router.define({
				build = function(_ctx)
					return Create.Frame({ Name = name })
				end,
			})
		end
		router:register("Garage", screen("Garage"))
		router:register("Inspect", screen("Inspect"))
		env.deferTweens = true
		router:reset("Garage")
		local garageHost = Support.find(router:layerRoot("Screens"), "Screen_Garage")
		expect(garageHost.Position).toEqual(UDim2.new())
		router:push("Inspect")
		local inspectHost = Support.find(router:layerRoot("Screens"), "Screen_Inspect")
		expect(inspectHost.Position).toEqual(UDim2.fromOffset(24, 0))
		env:completeTweens()
		expect(inspectHost.Position).toEqual(UDim2.new())
		router:destroy()
	end)

	it("pops modals from 0.98 (not 0.92)", function()
		env.deferTweens = true
		local frame = Create.Frame({ Name = "Dialog" })
		Motion.pop(frame)
		expect(Motion.POP_FROM).toBe(0.98)
		expect(frame:FindFirstChild("MotionScale").Scale).toBe(0.98)
		env:completeTweens()
		expect(frame:FindFirstChild("MotionScale").Scale).toBe(1)
		frame:Destroy()
	end)
end)

describe("Focus: selection the engine drops is repaired (REG-INP-01)", function()
	local stopInstall: () -> ()
	local gui: any
	local now = 0
	Test.beforeEach(function()
		reset()
		now = 0
		Focus.setClock(function(): number
			return now
		end)
		InputMode.set("Gamepad")
		stopInstall = Focus.install({ playerGui = env.playerGui, startInput = false })
		gui = Create("ScreenGui", { Name = "FocusRepair", Parent = env.playerGui })
	end)
	Test.afterEach(function()
		stopInstall()
		gui:Destroy()
		Focus.setClock(nil)
		reset()
	end)

	local function button(name: string, parent: any, y: number): any
		local b = Create("TextButton", { Name = name, Parent = parent })
		setAbsolute(b, Vector2.new(0, y))
		return b
	end

	it("moves focus to the nearest sibling one frame after the focused element is destroyed", function()
		local root = Create("Frame", { Name = "Root", Parent = gui })
		local list = Create("Frame", { Name = "List", Parent = root })
		local a = button("A", list, 0)
		local b = button("B", list, 50)
		local c = button("C", list, 80)
		local scope = Focus.scope(root, { name = "Garage" })
		scope:activate()
		expect(env.guiService.SelectedObject).toBe(a)
		Support.select(env.guiService, b)
		-- The engine: the focused row is sold/destroyed and SelectedObject resets to nil.
		b:Destroy()
		env.guiService.SelectedObject = nil
		expect(env.guiService.SelectedObject).toBeNil()
		env:step(1 / 60)
		expect(env.guiService.SelectedObject).toBe(c)
		scope:Destroy()
	end)

	it("keeps repairing separate incidents (removing row after row without moving)", function()
		local root = Create("Frame", { Name = "Root", Parent = gui })
		local list = Create("Frame", { Name = "List", Parent = root })
		local rows = {}
		for i = 1, 6 do
			table.insert(rows, button("Row" .. i, list, i * 50))
		end
		local scope = Focus.scope(root, { name = "Inventory" })
		scope:activate()
		expect(env.guiService.SelectedObject).toBe(rows[1])
		for i = 1, 5 do
			-- "Sell" the focused row with a contextual action: no player move between incidents.
			rows[i]:Destroy()
			env.guiService.SelectedObject = nil
			now += 1
			env:step(1 / 60)
			expect(env.guiService.SelectedObject).toBe(rows[i + 1])
		end
		scope:Destroy()
	end)

	it("falls back to the first selectable when the whole list is hidden (tab switch)", function()
		local root = Create("Frame", { Name = "Root", Parent = gui })
		local tabs = button("TabButton", root, 0)
		local list = Create("Frame", { Name = "List", Parent = root })
		local row = button("Row", list, 100)
		local scope = Focus.scope(root, { name = "Crew" })
		scope:activate()
		Support.select(env.guiService, row)
		list.Visible = false
		env.guiService.SelectedObject = nil
		env:step(1 / 60)
		expect(env.guiService.SelectedObject).toBe(tabs)
		scope:Destroy()
	end)

	it("does not fight an engine that keeps dropping the same element, and never repairs for mouse/touch", function()
		local root = Create("Frame", { Name = "Root", Parent = gui })
		local only = button("Only", root, 0)
		local scope = Focus.scope(root, { name = "Lonely" })
		scope:activate()
		expect(env.guiService.SelectedObject).toBe(only)
		env.guiService.SelectedObject = nil
		env:step(1 / 60)
		expect(env.guiService.SelectedObject).toBe(only)
		-- Dropped again (off screen): no ping-pong.
		env.guiService.SelectedObject = nil
		for _ = 1, 5 do
			env:step(1 / 60)
		end
		expect(env.guiService.SelectedObject).toBeNil()
		-- Mouse mode: a nil selection is correct and stays.
		InputMode.set("MouseKeyboard")
		now += 1
		env.guiService.SelectedObject = nil
		env:step(1 / 60)
		expect(env.guiService.SelectedObject).toBeNil()
		scope:Destroy()
	end)
end)

describe("Spinner: no engine tween while hidden", function()
	Test.beforeEach(reset)

	local function rotationTweens(): { any }
		local out = {}
		for _, tween in env.tweens do
			if tween.Props.Rotation == 360 then
				table.insert(out, tween)
			end
		end
		return out
	end

	it("runs the rotation only while the button is loading and motion is not reduced", function()
		env.deferTweens = true
		local before = #rotationTweens()
		local loading = State.Value(false)
		local button = Button.new({ text = "Research", loading = loading })
		expect(#rotationTweens()).toBe(before)
		loading:set(true)
		local spinning = rotationTweens()
		expect(#spinning).toBe(before + 1)
		local tween = spinning[#spinning]
		expect(tween.PlaybackState).toBe(Enum.PlaybackState.Playing)
		loading:set(false)
		expect(tween.PlaybackState).toBe(Enum.PlaybackState.Cancelled)
		-- Reduced motion switched on later stops a running spinner too.
		loading:set(true)
		local again = rotationTweens()
		local second = again[#again]
		expect(second.PlaybackState).toBe(Enum.PlaybackState.Playing)
		Theme.set({ reducedMotion = true })
		expect(second.PlaybackState).toBe(Enum.PlaybackState.Cancelled)
		button:Destroy()
		env:completeTweens()
	end)
end)

describe("Tooltip: touch long-press and lingering", function()
	local gui: any
	Test.beforeEach(function()
		reset()
		gui = overlayLayers()
	end)
	Test.afterEach(function()
		Tooltip.hide()
		gui:Destroy()
	end)

	it("never activates the button whose tooltip a long-press opened", function()
		local count = 0
		local button = Button.new({
			text = "Sell",
			tooltip = "Refunds 50 % of the price",
			onActivated = function()
				count += 1
			end,
			Parent = gui,
		})
		InputMode.set("Touch")
		local touch = Support.input({ UserInputType = Enum.UserInputType.Touch })
		Support.fire(button, "InputBegan", touch)
		Support.fire(button, "TouchLongPress", {}, Enum.UserInputState.Begin)
		expect(Tooltip.owner()).toBe(button)
		Support.fire(button, "TouchLongPress", {}, Enum.UserInputState.End)
		Support.click(button)
		expect(count).toBe(0)
		-- The next plain tap activates.
		Support.fire(button, "InputBegan", touch)
		Support.click(button)
		expect(count).toBe(1)
		-- A long-press whose release never activated (finger slid off) does not eat the next tap.
		Support.fire(button, "InputBegan", touch)
		Support.fire(button, "TouchLongPress", {}, Enum.UserInputState.Begin)
		Support.fire(button, "InputBegan", touch)
		Support.click(button)
		expect(count).toBe(2)
		button:Destroy()
	end)

	it("hides when its target is activated, hidden or removed", function()
		local host = Create("Frame", { Name = "Host", Parent = gui })
		local target = Create("TextButton", { Name = "Target", Parent = host })
		local detach = Tooltip.attach(target, "Opens the store")
		Tooltip.show(target, "Opens the store")
		expect(Tooltip.owner()).toBe(target)
		Support.click(target)
		expect(Tooltip.owner()).toBeNil()
		-- A covered screen (host Visible = false) never shows or keeps a tooltip.
		Tooltip.show(target, "Opens the store")
		host.Visible = false
		Tooltip.show(target, "Opens the store")
		expect(Tooltip.owner()).toBeNil()
		host.Visible = true
		Tooltip.show(target, "Opens the store")
		expect(Tooltip.owner()).toBe(target)
		target.Parent = nil
		expect(Tooltip.owner()).toBeNil()
		detach()
	end)

	it("places overlays inside the TV-safe padding of the layer root", function()
		Layers.clear()
		local root = Create("Frame", { Name = "TooltipRoot", Size = UDim2.fromScale(1, 1), Parent = gui })
		setAbsolute(root, Vector2.new(0, 0), Vector2.new(1920, 1080))
		Create("UIScale", { Scale = 1.25, Parent = root })
		Create("UIPadding", {
			PaddingLeft = UDim.new(0.05, 0),
			PaddingTop = UDim.new(0.05, 0),
			PaddingRight = UDim.new(0.05, 0),
			PaddingBottom = UDim.new(0.05, 0),
			Parent = root,
		})
		Layers.register("Tooltip", root)
		-- Pure conversion: screen (96 + 125, 54 + 250) is (100, 200) inside the padded, scaled content.
		local point = Layers.toLocal(root, Vector2.new(96 + 125, 54 + 250))
		expect(point.X).toBeCloseTo(100, 1e-9)
		expect(point.Y).toBeCloseTo(200, 1e-9)
		local target = Create("TextButton", { Name = "Target", Parent = gui })
		setAbsolute(target, Vector2.new(500, 300), Vector2.new(100, 40))
		Tooltip.show(target, "Reload 7.4 s")
		local tip = Support.find(root, "KitTooltip")
		-- Right of the target: screen x = 500 + 100 + 8, y centred = 300 (tip mock is 100 x 40).
		expect(tip.Position).toEqual(
			UDim2.fromOffset(math.floor((608 - 96) / 1.25 + 0.5), math.floor(246 / 1.25 + 0.5))
		)
		Tooltip.hide()
	end)
end)

describe("Touch targets reach 44 px", function()
	Test.beforeEach(reset)

	it("Slider: the hit area grows on touch, the drawn track stays put", function()
		local slider = Slider.new({ value = State.Value(5), min = 0, max = 10, label = "Volume" })
		local track = Support.find(slider, "Track")
		expect(track.Size.Y.Offset).toBe(24)
		InputMode.set("Touch")
		expect(track.Size.Y.Offset).toBe(Theme.sizes.touchMin)
		expect(track.Position).toEqual(UDim2.new(0, 0, 1, -Theme.sizes.touchMin))
		expect(Support.find(track, "Bar").Position).toEqual(UDim2.new(0, 0, 1, -12))
		expect(Support.find(track, "Thumb").Position).toEqual(UDim2.new(0.5, 0, 1, -12))
		Support.validateTree(slider)
		slider:Destroy()
	end)

	it("IconButton: a 32 px button keeps its 32 px plate but takes 44 px on touch", function()
		local button = IconButton.new({ icon = "ui/close", label = "Dismiss", size = 32 })
		expect(button.Size).toEqual(UDim2.fromOffset(32, 32))
		InputMode.set("Touch")
		expect(button.Size).toEqual(UDim2.fromOffset(Theme.sizes.touchMin, Theme.sizes.touchMin))
		expect(Support.find(button, "Plate").Size).toEqual(UDim2.fromOffset(32, 32))
		Support.validateTree(button)
		button:Destroy()
	end)

	it("Toast: reserves the grown close button and never takes gamepad focus", function()
		InputMode.set("Touch")
		local card = Toast.new({ title = "Invite", action = { text = "Join", onActivated = function() end } })
		local texts = Support.find(card, "Texts")
		expect(texts.Size).toEqual(UDim2.new(1, -(24 + Theme.sizes.touchMin + 2 * 12 + 112 + 12), 0, 0))
		for _, descendant in card:GetDescendants() do
			if descendant:IsA("GuiButton") then
				expect({ name = descendant.Name, selectable = descendant.Selectable }).toEqual({
					name = descendant.Name,
					selectable = false,
				})
			end
		end
		expect(card.Selectable).toBe(false)
		card:Destroy()
	end)
end)

describe("Hint bar reservation", function()
	Test.beforeEach(reset)

	it("exposes the hint bar's visibility so screens can reserve its 48 px", function()
		local shown = KeyPrompt.hintBarShown(false)
		local kbm = State.Value(false)
		local shownKbm = KeyPrompt.hintBarShown(kbm)
		expect(shown:peek()).toBe(false)
		InputMode.set("Gamepad")
		expect(shown:peek()).toBe(true)
		InputMode.set("MouseKeyboard")
		expect(shownKbm:peek()).toBe(false)
		kbm:set(true)
		expect(shownKbm:peek()).toBe(true)
		InputMode.set("Touch")
		expect(shownKbm:peek()).toBe(false)
		local bar = KeyPrompt.hintBar({ hints = { { action = "Back", label = "Back" } }, keyboard = kbm })
		expect(bar.Visible).toBe(false)
		InputMode.set("MouseKeyboard")
		expect(bar.Visible).toBe(true)
		bar:Destroy()
	end)
end)

describe("Text scale reaches measured widths", function()
	Test.beforeEach(reset)

	it("grows fixed text rows (StatBar, Modal title, CurrencyLabel) at 150 % text", function()
		local stat = StatBar.new({ label = "Reload", value = 7.4, compare = 6.9, max = 12, unit = "s", decimals = 1 })
		local modal = Modal.new({ title = "Sell vehicle", body = "Refund 50 %" })
		local wallet = CurrencyLabel.new({ currency = "credits", amount = 12400 })
		expect(Support.find(stat, "Label").Size.Y.Offset).toBe(20)
		expect(stat.Size.Y.Offset).toBe(32)
		Theme.set({ textScale = 1.5 })
		local bodySize = Theme.textSize("body.s"):peek()
		local labelHeight = Support.find(stat, "Label").Size.Y.Offset
		expect(labelHeight).toBeGreaterThanOrEqual(bodySize)
		expect(Support.find(stat, "Values").Size.Y.Offset).toBe(labelHeight)
		-- The bar sits below the taller row and the stat grows with it.
		expect(Support.find(stat, "Bar").Position.Y.Offset).toBeGreaterThan(labelHeight)
		expect(stat.Size.Y.Offset).toBeGreaterThan(Support.find(stat, "Bar").Position.Y.Offset)
		local title = Support.find(modal, "Title")
		expect(title.Size.Y.Offset).toBeGreaterThanOrEqual(Theme.textSize("h3"):peek())
		expect(Support.find(modal, "Header").Size.Y.Offset).toBeGreaterThanOrEqual(title.Size.Y.Offset)
		expect(wallet.AutomaticSize).toBe(Enum.AutomaticSize.XY)
		expect(Support.find(wallet, "Content").AutomaticSize).toBe(Enum.AutomaticSize.XY)
		Theme.set({ textScale = 1 })
		expect(stat.Size.Y.Offset).toBe(32)
		Support.validateTree(stat)
		Support.validateTree(modal)
		Support.validateTree(wallet)
		stat:Destroy()
		modal:Destroy()
		wallet:Destroy()
	end)

	it("re-measures tabs when the text scale changes", function()
		local bar = TabBar.new({
			tabs = { { id = "modules", label = "Modules" }, { id = "crew", label = "Crew" } },
			selected = State.Value("modules"),
		})
		local tab = Support.find(bar, "Tab_modules")
		local before = tab.Size.X.Offset
		Theme.set({ textScale = 1.5 })
		expect(tab.Size.X.Offset).toBeGreaterThan(before)
		Theme.set({ textScale = 1 })
		expect(tab.Size.X.Offset).toBe(before)
		bar:Destroy()
	end)
end)

describe("Dialogs die with their screen", function()
	local gui: any
	Test.beforeEach(function()
		reset()
		gui = overlayLayers()
	end)
	Test.afterEach(function()
		gui:Destroy()
	end)

	it("closes Modal.open / ConfirmDialog.open when the owning scope is cleaned", function()
		local scope = Trove.new()
		local cancelled = 0
		local handle = ConfirmDialog.open({
			title = "Sell",
			body = "Refund 50 %",
			destructive = true,
			scope = scope,
			onCancel = function()
				cancelled += 1
			end,
		})
		expect(handle.isOpen()).toBe(true)
		local modalScope = Trove.new()
		local results = {}
		local plain = Modal.open({
			title = "Info",
			scope = modalScope,
			onResult = function(result: any)
				table.insert(results, if result == nil then "nil" else result)
			end,
		})
		modalScope:Destroy()
		expect(plain.isOpen()).toBe(false)
		expect(results).toEqual({ "nil" })
		scope:Destroy()
		expect(handle.isOpen()).toBe(false)
		expect(cancelled).toBe(1)
		expect(handle.root.Parent).toBeNil()
	end)
end)

describe("Overlays whose layer is destroyed release Back and focus", function()
	Test.beforeEach(reset)

	it("Modal.open (non-dismissible) and an open Dropdown list survive router:destroy() cleanly", function()
		InputMode.set("Gamepad")
		local router = Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		local results = {}
		local handle = Modal.open({
			title = "Leave battle?",
			dismissible = false,
			onResult = function(result: any)
				table.insert(results, if result == nil then "nil" else result)
			end,
		})
		expect(Focus.top()).never.toBeNil()
		local field = Dropdown.new({
			options = { { value = 1, label = "One" }, { value = 2, label = "Two" } },
			selected = State.Value(1),
			Parent = router:layerRoot("Screens"),
		})
		Support.click(field)
		expect(Support.find(router:layerRoot("Tooltip"), "DropdownPopup")).never.toBeNil()
		-- Teleport: the router (and with it every layer) goes away while both are open.
		router:destroy()
		expect(handle.isOpen()).toBe(false)
		expect(results).toEqual({ "nil" })
		expect(UIInput.interceptBackNow()).toBe(false)
		expect(Focus.top()).toBeNil()
		field:Destroy()
	end)
end)

describe("More touch targets", function()
	local gui: any
	Test.beforeEach(function()
		reset()
		gui = overlayLayers()
	end)
	Test.afterEach(function()
		gui:Destroy()
	end)

	it("Dropdown rows, segmented tabs and chip remove crosses are >= 44 px on touch", function()
		InputMode.set("Touch")
		local field = Dropdown.new({
			options = { { value = 1, label = "One" }, { value = 2, label = "Two" } },
			selected = State.Value(1),
			Parent = gui,
		})
		Support.click(field)
		local popup = Support.find(Layers.get("Tooltip") :: any, "DropdownPopup")
		expect(Support.find(popup, "Option1").Size.Y.Offset).toBe(Theme.sizes.touchMin)
		expect(Support.find(popup, "List").Size.Y.Offset).toBe(2 * (Theme.sizes.touchMin + 2) + 8)
		Support.click(Support.find(popup, "Catcher"))
		local segmented = TabBar.new({
			tabs = { { id = "a", label = "All" }, { id = "b", label = "Owned" } },
			selected = State.Value("a"),
			variant = "segmented",
		})
		expect(segmented.Size.Y.Offset).toBe(Theme.sizes.touchMin)
		local chip = Chip.new({ label = "Heavy", removable = true, onActivated = function() end })
		expect(Support.find(chip, "Remove").Size).toEqual(UDim2.fromOffset(Theme.sizes.touchMin, Theme.sizes.touchMin))
		InputMode.set("MouseKeyboard")
		expect(segmented.Size.Y.Offset).toBe(36)
		expect(Support.find(chip, "Remove").Size).toEqual(UDim2.fromOffset(20, 20))
		field:Destroy()
		segmented:Destroy()
		chip:Destroy()
	end)
end)

describe("PreferredTextSize re-measures auto widths", function()
	Test.beforeEach(reset)

	it("re-measures an auto-width button when the player's Roblox text size changes", function()
		-- TextService measurements honour PreferredTextSize (TextService:GetTextSize reference).
		local factor = { Medium = 1, Large = 1.15, Larger = 1.3, Largest = 1.5 }
		game:setService("TextService", {
			GetTextSize = function(_self: any, text: string, size: number, _font: any, _frame: Vector2): Vector2
				local scale = factor[env.guiService.PreferredTextSize.Name] or 1
				return Vector2.new(#text * size * 0.6 * scale, size * scale)
			end,
		})
		local stop = Theme.bindEngine()
		local button = Button.new({ text = "Research everything", variant = "secondary" })
		local before = button.Size.X.Offset
		env.guiService.PreferredTextSize = Enum.PreferredTextSize.Largest
		expect(button.Size.X.Offset).toBeGreaterThan(before)
		expect(Theme.snapshot().preferredTextSize).toBe("Largest")
		env.guiService.PreferredTextSize = Enum.PreferredTextSize.Medium
		expect(button.Size.X.Offset).toBe(before)
		stop()
		button:Destroy()
	end)
end)

describe("Two-step confirm (a11y.holdConfirm = Two-step)", function()
	Test.beforeEach(reset)

	it("arms on the first press, confirms on the second, and disarms on timeout or focus loss", function()
		Theme.set({ twoStepConfirm = true })
		InputMode.set("Touch")
		local count = 0
		local button = Button.new({
			text = "Sell",
			variant = "danger",
			hold = true,
			onActivated = function()
				count += 1
			end,
		})
		local fill = Support.find(button, "HoldFill")
		local label = Support.find(button, "Label")
		-- Holding does nothing in two-step mode.
		Support.fire(button, "InputBegan", Support.input({ UserInputType = Enum.UserInputType.Touch }))
		for _ = 1, 120 do
			env:step(1 / 60)
		end
		expect(count).toBe(0)
		Support.fire(button, "InputEnded", Support.input({ UserInputType = Enum.UserInputType.Touch }))
		Support.click(button)
		expect(count).toBe(0)
		expect(fill.Visible).toBe(true)
		expect(fill.Size).toEqual(UDim2.fromScale(1, 1))
		expect(label.Text).toBe("Confirm?")
		Support.click(button)
		expect(count).toBe(1)
		expect(fill.Visible).toBe(false)
		expect(label.Text).toBe("Sell")
		-- Timeout.
		Support.click(button)
		for _ = 1, math.ceil(Button.ARM_WINDOW * 60) + 2 do
			env:step(1 / 60)
		end
		expect(fill.Visible).toBe(false)
		Support.click(button)
		expect(count).toBe(1)
		-- Focus moving away disarms.
		Support.fire(button, "SelectionLost")
		Support.click(button)
		expect(count).toBe(1)
		Support.click(button)
		expect(count).toBe(2)
		-- Mouse/keyboard still click once.
		InputMode.set("MouseKeyboard")
		Support.click(button)
		expect(count).toBe(3)
		button:Destroy()
	end)
end)

describe("Toggle with a constant `checked`", function()
	Test.beforeEach(reset)

	it("treats the constant as the initial value instead of freezing the switch", function()
		local changes = {}
		local toggle = Toggle.new({
			label = "Invert Y",
			checked = false,
			onChanged = function(value: boolean)
				table.insert(changes, value)
			end,
		})
		local knob = Support.find(toggle, "Knob")
		local offPosition = knob.Position
		Support.click(toggle)
		Support.click(toggle)
		Support.click(toggle)
		expect(changes).toEqual({ true, false, true })
		expect(knob.Position).never.toEqual(offPosition)
		-- A State stays controlled: the owner decides.
		local owned = State.Value(false)
		local controlledChanges = {}
		local controlled = Toggle.new({
			checked = owned,
			onChanged = function(value: boolean)
				table.insert(controlledChanges, value)
			end,
		})
		Support.click(controlled)
		Support.click(controlled)
		expect(controlledChanges).toEqual({ true, true })
		expect(owned:peek()).toBe(false)
		toggle:Destroy()
		controlled:Destroy()
	end)
end)

describe("State: discarded Computed results are cleaned", function()
	it("runs cleanup on a new result that equals the published one", function()
		local source = State.Value(1)
		local cleaned = {}
		local computed = State.Computed(function(): { n: number }
			return { n = source:get() }
		end, {
			equals = function(_a: any, _b: any): boolean
				return true
			end,
			cleanup = function(value: { n: number })
				table.insert(cleaned, value)
			end,
		})
		local first = computed:get()
		source:set(2)
		expect(computed:get()).toBe(first)
		expect(#cleaned).toBe(1)
		expect(cleaned[1]).never.toBe(first)
		expect(cleaned[1].n).toBe(2)
		computed:Destroy()
		expect(cleaned[2]).toBe(first)
	end)
end)

describe("Format.compact rounding carries into the next unit", function()
	it("prints 1M, not 1,000K", function()
		expect(Format.compact(999950)).toBe("1M")
		expect(Format.compact(-999950)).toBe("−1M")
		expect(Format.compact(999.6)).toBe("1K")
		expect(Format.compact(999499)).toBe("999K")
		expect(Format.compact(9999)).toBe("10K")
		expect(Format.compact(999999999)).toBe("1B")
		expect(Format.compact(12400)).toBe("12.4K")
		expect(Format.compact(950)).toBe("950")
	end)
end)
