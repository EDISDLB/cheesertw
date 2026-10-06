local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local Focus = require("@game/ReplicatedStorage/Client/UI/Kit/Focus")
local UIInput = require("@game/ReplicatedStorage/Client/UI/Kit/UIInput")
local Layers = require("@game/ReplicatedStorage/Client/UI/Kit/Layers")
local Sound = require("@game/ReplicatedStorage/Client/UI/Kit/Sound")
local Format = require("@game/ReplicatedStorage/Client/UI/Kit/Format")
local Modal = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Modal")
local ConfirmDialog = require("@game/ReplicatedStorage/Client/UI/Kit/Components/ConfirmDialog")
local Toast = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Toast")
local ToastStack = require("@game/ReplicatedStorage/Client/UI/Kit/Components/ToastStack")
local ProgressBar = require("@game/ReplicatedStorage/Client/UI/Kit/Components/ProgressBar")
local StatBar = require("@game/ReplicatedStorage/Client/UI/Kit/Components/StatBar")
local CurrencyLabel = require("@game/ReplicatedStorage/Client/UI/Kit/Components/CurrencyLabel")
local Badge = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Badge")
local Divider = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Divider")
local EmptyState = require("@game/ReplicatedStorage/Client/UI/Kit/Components/EmptyState")
local Skeleton = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Skeleton")
local ScrollFrame = require("@game/ReplicatedStorage/Client/UI/Kit/Components/ScrollFrame")
local Panel = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Panel")
local Card = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Card")
local Spinner = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Spinner")
local Icon = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Icon")
local Button = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Button")

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
	env.deferTweens = false
end

local function steps(seconds: number)
	local frames = math.ceil(seconds * 60)
	for _ = 1, frames do
		env:step(1 / 60)
	end
end

describe("Modal and ConfirmDialog", function()
	Test.beforeEach(reset)

	it("sizes dialogs by name", function()
		expect(Modal.width("s")).toBe(480)
		expect(Modal.width("m")).toBe(640)
		expect(Modal.width("l")).toBe(880)
		expect(Modal.width(nil)).toBe(640)
	end)

	it("builds the card with header, body, actions and close button", function()
		local closed = 0
		local card = Modal.new({
			title = "Crew",
			icon = "crew/commander",
			body = "Assign a commander.",
			actions = { { text = "Cancel" }, { text = "Assign" } },
			onClose = function()
				closed += 1
			end,
		})
		expect(card.Size).toEqual(UDim2.fromOffset(640, 0))
		expect(Support.find(card, "Title").Text).toBe("CREW")
		expect(Support.find(card, "BodyText").Text).toBe("Assign a commander.")
		expect(Support.find(card, "Action2")).never.toBeNil()
		Support.click(Support.find(card, "Close"))
		expect(closed).toBe(1)
		Support.validateTree(card)
		local plain = Modal.new({ title = "Locked", dismissible = false })
		expect(Support.find(plain, "Close")).toBeNil()
		card:Destroy()
		plain:Destroy()
	end)

	it("opens with trapped focus, closes on Back and reports the result", function()
		local gui = registerLayers()
		InputMode.set("Gamepad")
		local stop = Focus.install({ playerGui = env.playerGui, startInput = false, skipGuiService = true })
		local outside = Create("TextButton", { Name = "Outside", Parent = gui })
		local resultCalls, lastResult = 0, "unset" :: any
		local handle = Modal.open({
			title = "Leave battle?",
			body = "You will not receive rewards.",
			actions = { { text = "Stay", id = "stay" }, { text = "Leave", id = "leave", variant = "danger" } },
			onResult = function(result: any)
				resultCalls += 1
				lastResult = result
			end,
		})
		expect(handle.isOpen()).toBe(true)
		expect(handle.root.Parent).toBe(Layers.get("Modals"))
		-- Initial focus: the last action.
		expect(env.guiService.SelectedObject).toBe(Support.find(handle.dialog, "Action2"))
		-- Trapped: moving selection outside is pulled back in.
		Support.select(env.guiService, outside)
		expect(Focus.contains(handle.dialog, env.guiService.SelectedObject)).toBe(true)
		-- Back closes a dismissible dialog with nil.
		expect(UIInput.interceptBackNow()).toBe(true)
		expect(handle.isOpen()).toBe(false)
		expect(handle.root.Parent).toBeNil()
		expect(resultCalls).toBe(1)
		expect(lastResult).toBeNil()
		handle.close("late")
		expect(resultCalls).toBe(1)
		-- Actions close with their id; the handle's signal fires once.
		local signalled = {}
		local second =
			Modal.open({ title = "Sell?", actions = { { text = "No", id = false }, { text = "Yes", id = true } } })
		second.closed:Connect(function(result: any)
			table.insert(signalled, result)
		end)
		Support.click(Support.find(second.dialog, "Action2"))
		second.close("again")
		expect(signalled).toEqual({ true })
		stop()
		gui:Destroy()
	end)

	it("keeps non-dismissible dialogs open on Back and swallows it", function()
		local gui = registerLayers()
		local handle = Modal.open({
			title = "Updating",
			dismissible = false,
			actions = { { text = "Retry", keepOpen = true }, { text = "Quit", id = "quit" } },
		})
		expect(UIInput.interceptBackNow()).toBe(true)
		expect(handle.isOpen()).toBe(true)
		Support.click(Support.find(handle.root, "Scrim"))
		expect(handle.isOpen()).toBe(true)
		Support.click(Support.find(handle.dialog, "Action1"))
		expect(handle.isOpen()).toBe(true)
		handle.close()
		expect(handle.isOpen()).toBe(false)
		expect(UIInput.interceptBackNow()).toBe(false)
		gui:Destroy()
	end)

	it("raises without a Modals layer", function()
		expect(function()
			Modal.open({ title = "x" })
		end).toThrow("no Modals layer")
	end)

	it("confirms and cancels, with a hazard band and safe focus for destructive actions", function()
		local gui = registerLayers()
		InputMode.set("Gamepad")
		local log = {}
		local handle = ConfirmDialog.open({
			title = "Sell vehicle?",
			body = "Sell T-34 for 120,000 credits.",
			confirmLabel = "Sell",
			destructive = true,
			onConfirm = function()
				table.insert(log, "confirm")
			end,
			onCancel = function()
				table.insert(log, "cancel")
			end,
		})
		expect(Support.find(handle.dialog, "HazardBand")).never.toBeNil()
		-- Destructive: gamepad focus starts on Cancel.
		expect(env.guiService.SelectedObject).toBe(Support.find(handle.dialog, "Action1"))
		Support.validateTree(handle.root)
		-- Gamepad: a tap does nothing; holding A on the danger button for the hold time confirms (ui-ux §1.6).
		local confirm = Support.find(handle.dialog, "Action2")
		Support.click(confirm)
		expect(log).toEqual({})
		Support.select(env.guiService, confirm)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.ButtonA }), true)
		for _ = 1, 30 do
			env:step(1 / 60)
		end
		local fill = Support.find(confirm, "HoldFill")
		expect(fill.Visible).toBe(true)
		expect(fill.Size.X.Scale).toBeCloseTo(0.5 / 1.2, 0.02)
		-- Releasing early resets.
		env.userInputService.InputEnded:Fire(Support.input({ KeyCode = Enum.KeyCode.ButtonA }), true)
		expect(fill.Visible).toBe(false)
		expect(log).toEqual({})
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.ButtonA }), true)
		for _ = 1, 80 do
			env:step(1 / 60)
		end
		expect(log).toEqual({ "confirm" })
		expect(handle.isOpen()).toBe(false)
		local results = {}
		local second = ConfirmDialog.open({
			title = "Apply?",
			onCancel = function()
				table.insert(log, "cancel")
			end,
		})
		second.closed:Connect(function(result: any)
			table.insert(results, result)
		end)
		expect(Support.find(second.dialog, "HazardBand")).toBeNil()
		expect(env.guiService.SelectedObject).toBe(Support.find(second.dialog, "Action2"))
		UIInput.interceptBackNow()
		expect(log).toEqual({ "confirm", "cancel" })
		expect(results).toEqual({})
		gui:Destroy()
	end)

	it("confirms destructive actions with a plain click on mouse and keyboard", function()
		local gui = registerLayers()
		InputMode.set("MouseKeyboard")
		local confirmed = 0
		local handle = ConfirmDialog.open({
			title = "Sell vehicle?",
			destructive = true,
			onConfirm = function()
				confirmed += 1
			end,
		})
		Support.click(Support.find(handle.dialog, "Action2"))
		expect(confirmed).toBe(1)
		expect(Button.holdProgress(0.6, 1.2)).toBeCloseTo(0.5)
		expect(Button.holdProgress(5, 1.2)).toBe(1)
		expect(Button.holdProgress(0.1, 0)).toBe(1)
		gui:Destroy()
	end)
end)

describe("Toasts", function()
	Test.beforeEach(reset)

	it("computes icons, holds and evictions (pure)", function()
		expect(Toast.iconFor({ title = "x", tone = "success" })).toBe("ui/check")
		expect(Toast.iconFor({ title = "x", tone = "danger" })).toBe("ui/error")
		expect(Toast.iconFor({ title = "x", icon = "currency/credits" })).toBe("currency/credits")
		expect(Toast.holdFor({ title = "x" })).toBe(4)
		expect(Toast.holdFor({ title = "x", action = { text = "Undo", onActivated = function() end } })).toBe(8)
		expect(Toast.holdFor({ title = "x", sticky = true })).toBeNil()
		local function live(spec: { boolean }): { any }
			local out = {}
			for id, action in spec do
				table.insert(out, { id = id, action = action })
			end
			return out
		end
		expect(ToastStack.evictions(live({ false, false, false }), 3)).toEqual({ 1 })
		expect(ToastStack.evictions(live({ false, false }), 3)).toEqual({})
		-- The oldest toast without an action leaves first; all-action stacks evict the oldest.
		expect(ToastStack.evictions(live({ true, false, true }), 3)).toEqual({ 2 })
		expect(ToastStack.evictions(live({ true, true, true }), 3)).toEqual({ 1 })
		expect(ToastStack.evictions(live({ true, false, false, true }), 3)).toEqual({ 2, 3 })
	end)

	it("stacks at most three, newest first, and times them out", function()
		local holder = Create("Frame", { Name = "Holder" })
		local stack = ToastStack.new({ parent = holder })
		local a = stack:push({ title = "Saved" })
		local b = stack:push({ title = "Research complete", tone = "success" })
		local c = stack:push({ title = "Low ammo", tone = "warning", body = "4 rounds of HEAT left." })
		expect(stack:count()).toBe(3)
		local d = stack:push({ title = "Crew injured", tone = "danger" })
		expect(stack:ids()).toEqual({ b, c, d })
		expect(Support.find(stack.frame, "Toast_" .. a)).toBeNil()
		expect(
			Support.find(stack.frame, "Toast_" .. d).LayoutOrder < Support.find(stack.frame, "Toast_" .. c).LayoutOrder
		).toBe(true)
		-- Four toasts in one burst share one notification cue (ui-ux §1.16).
		expect(Sound.counts()[Sound.KEYS.notification]).toBe(1)
		Support.validateTree(stack.frame)
		steps(3.9)
		expect(stack:count()).toBe(3)
		steps(0.2)
		expect(stack:count()).toBe(0)
		stack:destroy()
	end)

	it("pauses while hovered, extends action toasts, replaces by key and dismisses on click", function()
		local stack = ToastStack.new({ parent = Create("Frame", { Name = "Holder" }) })
		local hover = stack:push({ title = "Hover me" })
		local hoverCard = Support.find(Support.find(stack.frame, "Toast_" .. hover), "Toast")
		Support.fire(hoverCard, "MouseEnter")
		steps(5)
		expect(stack:ids()).toEqual({ hover })
		Support.fire(hoverCard, "MouseLeave")
		steps(4.1)
		expect(stack:count()).toBe(0)
		local undone = 0
		local action = stack:push({
			title = "Module sold",
			action = {
				text = "Undo",
				onActivated = function()
					undone += 1
				end,
			},
		})
		steps(5)
		expect(stack:ids()).toEqual({ action })
		Support.click(Support.find(Support.find(stack.frame, "Toast_" .. action), "Action"))
		expect(undone).toBe(1)
		expect(stack:count()).toBe(0)
		local closable = stack:push({ title = "Close me", body = "A body line." })
		local card = Support.find(Support.find(stack.frame, "Toast_" .. closable), "Toast")
		expect(Support.find(card, "Body"):FindFirstChildOfClass("UISizeConstraint")).never.toBeNil()
		Support.click(Support.find(card, "Close"))
		expect(stack:count()).toBe(0)
		local first = stack:push({ title = "Saving...", key = "save", sticky = true })
		local second = stack:push({ title = "Saved", key = "save" })
		expect(stack:ids()).toEqual({ second })
		Support.click(Support.find(Support.find(stack.frame, "Toast_" .. second), "Toast"))
		expect(stack:count()).toBe(0)
		expect(first ~= second).toBe(true)
		stack:destroy()
		expect(function()
			stack:push({ title = "late" })
		end).toThrow("after destroy")
	end)

	it("rate-limits the notification cue and builds reward toasts", function()
		local now = 100
		ToastStack.setClock(function()
			return now
		end)
		Sound.resetCounts()
		local stack = ToastStack.new({ parent = Create("Frame", { Name = "Holder" }) })
		stack:push({ title = "A" })
		now += 1
		stack:push({ title = "B" })
		expect(Sound.counts()[Sound.KEYS.notification]).toBe(1)
		now += ToastStack.SOUND_GAP
		stack:push({ title = "C" })
		expect(Sound.counts()[Sound.KEYS.notification]).toBe(2)
		stack:push({ title = "Bought", sound = "ui_purchase" })
		expect(Sound.counts().ui_purchase).toBe(1)
		stack:clear()
		local id = stack:push({ title = "Mission complete", reward = { currency = "bullion", amount = 1000 } })
		local card = Support.find(Support.find(stack.frame, "Toast_" .. id), "Toast")
		expect(Support.find(card, "Amount").Text).toBe("+1,000")
		expect(Support.find(card, "Amount").TextColor3).toEqual(Theme.peekColor("currency.bullion"))
		expect(Support.find(card, "Title").Text).toBe("Mission complete")
		expect(Support.find(card, "Shimmer")).never.toBeNil()
		expect(Toast.iconFor({ title = "x", reward = { currency = "credits", amount = 5 } })).toBe("currency/credits")
		Support.validateTree(card)
		stack:destroy()
		ToastStack.setClock(nil)
	end)

	it("slides out before removal when tweens run", function()
		local stack = ToastStack.new({ parent = Create("Frame", { Name = "Holder" }) })
		local id = stack:push({ title = "Hello" })
		env.deferTweens = true
		stack:dismiss(id)
		expect(stack:count()).toBe(1)
		env:completeTweens()
		expect(stack:count()).toBe(0)
		env.deferTweens = false
		stack:destroy()
	end)

	it("Toast.show uses the shared stack in the Toasts layer", function()
		expect(Toast.show({ title = "No layer" })).toBeNil()
		local gui = registerLayers()
		local id = Toast.show({ title = "Hello" })
		expect(id).never.toBeNil()
		local shared = ToastStack.default()
		expect(shared.frame.Parent).toBe(Layers.get("Toasts"))
		Toast.dismiss(id :: number)
		expect(shared:count()).toBe(0)
		gui:Destroy()
	end)
end)

describe("ProgressBar, StatBar, CurrencyLabel, Badge", function()
	Test.beforeEach(reset)

	it("ProgressBar clamps, segments, ghosts and switches to indeterminate", function()
		expect(ProgressBar.clamp(1.4)).toBe(1)
		expect(ProgressBar.clamp(-2)).toBe(0)
		expect(ProgressBar.clamp(0 / 0)).toBe(0)
		expect(ProgressBar.clamp(nil)).toBe(0)
		expect(ProgressBar.separators(4)).toEqual({ 0.25, 0.5, 0.75 })
		local value = State.Value(0.5)
		local busy = State.Value(false)
		local bar = ProgressBar.new({
			value = value,
			ghost = 0.8,
			segments = 4,
			animate = false,
			indeterminate = busy,
			color = "currency.vehicle_xp",
		})
		local fill = Support.find(bar, "Fill")
		expect(fill.Size).toEqual(UDim2.fromScale(0.5, 1))
		expect(fill.BackgroundColor3).toEqual(Theme.peekColor("currency.vehicle_xp"))
		expect(Support.find(bar, "Ghost").Size).toEqual(UDim2.fromScale(0.8, 1))
		expect(Support.find(bar, "Separator3")).never.toBeNil()
		value:set(7)
		expect(fill.Size).toEqual(UDim2.fromScale(1, 1))
		busy:set(true)
		expect(fill.Visible).toBe(false)
		expect(Support.find(bar, "Sweep").Visible).toBe(true)
		Theme.set({ reducedMotion = true })
		busy:set(false)
		busy:set(true)
		expect(Support.find(bar, "Sweep").Size).toEqual(UDim2.fromScale(1, 1))
		Support.validateTree(bar)
		bar:Destroy()
	end)

	it("ProgressBar springs to the value and snaps under reduced motion", function()
		local value = State.Value(0)
		local bar = ProgressBar.new({ value = value })
		local fill = Support.find(bar, "Fill")
		value:set(1)
		steps(0.05)
		local midway = fill.Size.X.Scale
		expect(midway > 0 and midway < 1).toBe(true)
		steps(2)
		expect(fill.Size).toEqual(UDim2.fromScale(1, 1))
		Theme.set({ reducedMotion = true })
		value:set(0.25)
		env:step(1 / 60)
		expect(fill.Size).toEqual(UDim2.fromScale(0.25, 1))
		bar:Destroy()
	end)

	it("StatBar shows comparison segments and toned deltas", function()
		expect(StatBar.segments(50, nil, 100)).toEqual({
			base = 0.5,
			deltaStart = 0.5,
			deltaEnd = 0.5,
			increase = false,
		})
		expect(StatBar.segments(50, 75, 100)).toEqual({ base = 0.5, deltaStart = 0.5, deltaEnd = 0.75, increase = true })
		expect(StatBar.segments(50, 25, 100)).toEqual({
			base = 0.25,
			deltaStart = 0.25,
			deltaEnd = 0.5,
			increase = false,
		})
		expect(StatBar.segments(500, 600, 0).base).toBe(1)
		local compare = State.Value(nil :: number?)
		local row = StatBar.new({
			label = "Reload",
			value = 7.4,
			max = 12,
			compare = compare,
			lowerIsBetter = true,
			unit = "s",
			decimals = 1,
		})
		expect(Support.find(row, "Value").Text).toBe("7.4 s")
		expect(Support.find(row, "Delta").Visible).toBe(false)
		compare:set(6.9)
		local delta = Support.find(row, "Values"):FindFirstChild("Delta")
		expect(delta.Visible).toBe(true)
		expect(delta.Text).toBe(Format.MINUS .. "0.5 s")
		expect(delta.TextColor3).toEqual(Theme.peekColor("state.success"))
		compare:set(8)
		expect(delta.TextColor3).toEqual(Theme.peekColor("state.danger"))
		local bar = Support.find(row, "Bar")
		expect(bar:FindFirstChild("Delta").Visible).toBe(true)
		Support.validateTree(row)
		row:Destroy()
	end)

	it("CurrencyLabel formats, counts up and floats the delta", function()
		expect(CurrencyLabel.text(1234567)).toBe("1,234,567")
		expect(CurrencyLabel.text(12400, true)).toBe("12.4K")
		expect(CurrencyLabel.text(5, false, "×")).toBe("×5")
		local amount = State.Value(1000)
		local insufficient = State.Value(false)
		local label = CurrencyLabel.new({
			currency = "credits",
			amount = amount,
			showDelta = true,
			insufficient = insufficient,
			style = "panel",
		})
		local text = Support.find(label, "Amount")
		expect(text.Text).toBe("1,000")
		amount:set(2500)
		steps(0.1)
		local mid = tonumber((string.gsub(text.Text, ",", "")))
		expect(mid > 1000 and mid < 2500).toBe(true)
		expect(Support.find(label, "Delta").Text).toBe("+1,500")
		expect(Support.find(label, "Delta").Visible).toBe(true)
		steps(1.3)
		expect(text.Text).toBe("2,500")
		expect(Support.find(label, "Delta").Visible).toBe(false)
		insufficient:set(true)
		expect(text.TextColor3).toEqual(Theme.peekColor("state.danger"))
		Theme.set({ reducedMotion = true })
		amount:set(100)
		expect(text.Text).toBe("100")
		Support.validateTree(label)
		label:Destroy()
		local static = CurrencyLabel.new({ currency = "bullion", amount = 250, size = "l", compact = true })
		expect(Support.find(static, "Amount").Text).toBe("250")
		static:Destroy()
	end)

	it("Badge builds every kind", function()
		expect(Badge.countText(0)).toBe("")
		expect(Badge.countText(7)).toBe("7")
		expect(Badge.countText(140)).toBe("99+")
		expect(Badge.tierKey(8)).toBe("tiers/tier_08")
		expect(Badge.tierKey(40)).toBe("tiers/tier_11")
		local count = State.Value(0)
		local counter = Badge.new({ kind = "count", count = count })
		expect(counter.Visible).toBe(false)
		count:set(120)
		expect(counter.Visible).toBe(true)
		expect(Support.find(counter, "Label").Text).toBe("99+")
		local premium = Badge.new({ kind = "premium" })
		expect(Support.find(premium, "Label").Text).toBe("PREMIUM")
		local class = Badge.new({ kind = "class", class = "heavy", premium = true })
		expect(class:GetAttribute("BadgeKind")).toBe("class")
		local tier = Badge.tier(8)
		expect(tier:FindFirstChild("Glyph"):GetAttribute("IconKey")).toBe("tiers/tier_08")
		local newBadge = Badge.new({ kind = "new" })
		local text = Badge.new({ kind = "text", text = "ELITE", tone = "warning" })
		for _, badge in { counter, premium, class, tier, newBadge, text } do
			Support.validateTree(badge)
			badge:Destroy()
		end
		expect(function()
			Badge.new({ kind = "shiny" :: any })
		end).toThrow("unknown kind")
	end)
end)

describe("Layout helpers and placeholders", function()
	Test.beforeEach(reset)

	it("Divider, EmptyState, Skeleton, Spinner, Panel and Card build valid trees", function()
		local labelled = Divider.new({ label = "or" })
		expect(Support.find(labelled, "RuleLeft")).never.toBeNil()
		local ridge = Divider.new({ variant = "ridge", direction = "vertical" })
		expect(ridge.Size).toEqual(UDim2.new(0, 2, 1, 0))
		local acted = 0
		local empty = EmptyState.new({
			icon = "ui/search",
			title = "No vehicles match",
			body = "Clear filters to see the whole hangar.",
			action = {
				text = "Clear filters",
				onActivated = function()
					acted += 1
				end,
			},
		})
		Support.click(Support.find(empty, "Action"))
		expect(acted).toBe(1)
		local lines = Skeleton.new({ shape = "lines", lines = 3 })
		expect(Support.find(lines, "Line3").Size).toEqual(UDim2.new(0.6, 0, 0, 12))
		local circle = Skeleton.new({ shape = "circle", Size = UDim2.fromOffset(40, 40) })
		local panel = Panel.new({
			title = "Crew",
			number = "02",
			icon = "crew/gunner",
			variant = "hero",
			children = { Spinner.new({ size = 32 }) },
		})
		local card = Card.new({ rarity = "epic", selected = true, children = { Icon.new({ key = "classes/td" }) } })
		for _, root in { labelled, ridge, empty, lines, circle, panel, card } do
			Support.validateTree(root)
			root:Destroy()
		end
	end)

	it("Skeleton shimmer is static under reduced motion", function()
		Theme.set({ reducedMotion = true })
		local block = Skeleton.new({ Size = UDim2.fromOffset(200, 20) })
		local shimmer = block:FindFirstChild("Shimmer")
		expect(shimmer.Offset).toEqual(Vector2.new(0, 0))
		block:Destroy()
	end)

	it("ScrollFrame computes reveal positions and scrolls selection into view", function()
		local axes = ScrollFrame.revealPosition(
			Vector2.new(0, 900),
			Vector2.new(100, 60),
			Vector2.new(0, 0),
			Vector2.new(400, 500),
			16,
			"y"
		)
		expect(axes).toEqual(Vector2.new(0, 900 + 60 + 16 - 500))
		expect(
			ScrollFrame.revealPosition(
				Vector2.new(50, 50),
				Vector2.new(10, 10),
				Vector2.new(0, 0),
				Vector2.new(400, 500),
				16,
				"xy"
			)
		).toEqual(Vector2.new(0, 0))
		local item = Create("TextButton", { Name = "Item" })
		local frame = ScrollFrame.new({ list = { gap = 8 }, padding = 8, children = { item } })
		expect(frame.AutomaticCanvasSize).toBe(Enum.AutomaticSize.Y)
		rawget(frame, "_props").AbsoluteSize = Vector2.new(400, 300)
		rawget(item, "_props").AbsolutePosition = Vector2.new(0, 700)
		rawget(item, "_props").AbsoluteSize = Vector2.new(400, 56)
		Support.select(env.guiService, item)
		-- Default context is 48 px (ui-ux §1.13).
		expect(frame.CanvasPosition).toEqual(Vector2.new(0, 700 + 56 + 48 - 300))
		InputMode.set("Gamepad")
		expect(frame.ScrollBarThickness).toBe(Theme.sizes.scrollBar.gamepad)
		Support.select(env.guiService, nil)
		Support.validateTree(frame)
		frame:Destroy()
	end)
end)

describe("Component lifetimes", function()
	Test.beforeEach(reset)

	it("releases every rooted effect when components are destroyed", function()
		local baseline = State.stats().liveEffects
		local holder = Create("Frame", { Name = "Holder" })
		local amount = State.Value(10)
		ProgressBar.new({ value = State.Value(0.3), indeterminate = State.Value(false), Parent = holder })
		CurrencyLabel.new({ currency = "credits", amount = amount, showDelta = true, Parent = holder })
		Button.new({ text = "OK", tooltip = "Confirm", Parent = holder })
		StatBar.new({ label = "Speed", value = State.Value(60), compare = 70, max = 80, Parent = holder })
		expect(State.stats().liveEffects > baseline).toBe(true)
		holder:Destroy()
		expect(State.stats().liveEffects).toBe(baseline)
		amount:set(20)
	end)
end)
