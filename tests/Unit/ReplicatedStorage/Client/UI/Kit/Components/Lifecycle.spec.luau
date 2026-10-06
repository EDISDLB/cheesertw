--[[
	Leak regression for every kit component: building and destroying a component (with State-bound props) must leave
	no rooted effect or observer behind (State.stats().liveEffects returns to its baseline). Each builder runs once
	first so module-level caches (Theme tokens, focus-ring templates) exist before the measurement.
]]

local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local Focus = require("@game/ReplicatedStorage/Client/UI/Kit/Focus")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local Layers = require("@game/ReplicatedStorage/Client/UI/Kit/Layers")
local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

type Builder = () -> Instance

local function builders(): { [string]: Builder }
	local items = State.Value({ 1, 2, 3, 4, 5 })
	local function row(item: State.State<any>, _index: State.State<number>): GuiObject
		return Kit.Text.body(State.map(item, tostring))
	end
	return {
		Badge = function()
			return Kit.Badge.new({ kind = "tier", tier = State.Value(5) })
		end,
		BadgeCount = function()
			return Kit.Badge.new({ kind = "count", count = State.Value(3) })
		end,
		Button = function()
			return Kit.Button.new({
				text = State.Value("Research"),
				loadingText = "Researching",
				loading = State.Value(false),
				disabled = State.Value(false),
				hold = true,
				icon = "ui/check",
				hint = "Tertiary",
				tooltip = "Reason",
			})
		end,
		ButtonDanger = function()
			return Kit.Button.new({ text = "Sell", variant = "danger" })
		end,
		Card = function()
			return Kit.Card.new({ selected = State.Value(true), rarity = State.Value("epic" :: any) })
		end,
		Chip = function()
			return Kit.Chip.new({ label = "Filter", selected = State.Value(false), removable = true })
		end,
		CurrencyLabel = function()
			return Kit.CurrencyLabel.new({ currency = "credits", amount = State.Value(100), showDelta = true })
		end,
		Divider = function()
			return Kit.Divider.new({ label = "Section" })
		end,
		Dropdown = function()
			return Kit.Dropdown.new({
				options = { { value = 1, label = "One" }, { value = 2, label = "Two" } },
				selected = State.Value(1),
			})
		end,
		EmptyState = function()
			return Kit.EmptyState.new({
				title = "Nothing",
				body = "Empty",
				action = { text = "Go", onActivated = function() end },
			})
		end,
		HintBar = function()
			return Kit.KeyPrompt.hintBar({ hints = State.Value({ { action = "Back", label = "Back" } }) })
		end,
		Icon = function()
			return Kit.Icon.new({ key = State.Value("ui/close"), size = State.Value(24) })
		end,
		IconButton = function()
			return Kit.IconButton.new({ icon = "ui/settings", label = "Settings", selected = State.Value(false) })
		end,
		KeyPrompt = function()
			return Kit.KeyPrompt.new({ action = "Back", label = "Back" })
		end,
		Modal = function()
			return Kit.Modal.new({ title = "Title", body = "Body", actions = { { text = "Cancel" }, { text = "OK" } } })
		end,
		Panel = function()
			return Kit.Panel.new({ title = "Panel", number = "01", variant = "hero" })
		end,
		ProgressBar = function()
			return Kit.ProgressBar.new({ value = State.Value(0.4), indeterminate = State.Value(true) })
		end,
		ScrollFrame = function()
			return Kit.ScrollFrame.new({ children = { Kit.Text.body("Row") } })
		end,
		Skeleton = function()
			return Kit.Skeleton.new({ shape = "lines", lines = 3 })
		end,
		Slider = function()
			return Kit.Slider.new({ value = State.Value(0.5), min = 0, max = 1, step = 0.1, label = "Volume" })
		end,
		Spinner = function()
			return Kit.Spinner.new({ size = 24 })
		end,
		StatBar = function()
			return Kit.StatBar.new({ label = "Reload", value = State.Value(7.4), compare = State.Value(6.9), max = 12 })
		end,
		TabBar = function()
			return Kit.TabBar.new({
				tabs = State.Value({ { id = "a", label = "A" }, { id = "b", label = "B" } }),
				selected = State.Value("a"),
			})
		end,
		Text = function()
			return Kit.Text.h3(State.Value("Title"))
		end,
		Toast = function()
			return Kit.Toast.new({ title = "Hello", body = "World", reward = { currency = "bullion", amount = 10 } })
		end,
		ToastStack = function()
			local stack = Kit.ToastStack.new({})
			stack:push({ title = "One" })
			return stack.frame
		end,
		Toggle = function()
			return Kit.Toggle.new({ label = "Toggle", value = State.Value(true) })
		end,
		ToggleControlled = function()
			return Kit.Toggle.new({ label = "Toggle", checked = State.Value(false) })
		end,
		VirtualGrid = function()
			local frame = Kit.VirtualGrid.new({ items = items, render = row, cell = Vector2.new(100, 40) })
			return frame
		end,
		VirtualList = function()
			local frame = Kit.VirtualList.new({ items = items, render = row, itemSize = 40 })
			return frame
		end,
	}
end

describe("Component lifecycle", function()
	Test.beforeEach(function()
		Theme.reset()
		Focus.reset()
		Layers.clear()
		InputMode.set("MouseKeyboard")
	end)

	it("leaves no Heartbeat loops or global input listeners after Destroy", function()
		local function listeners(): number
			local count = 0
			for _, signal in
				{
					env.runService.Heartbeat,
					env.userInputService.InputBegan,
					env.userInputService.InputEnded,
					env.userInputService.InputChanged,
				}
			do
				count += #rawget(signal, "_connections")
			end
			return count
		end
		local gui = Create("ScreenGui", { Name = "Loops", Parent = env.playerGui })
		local leaks = {}
		InputMode.set("Gamepad")
		for name, build in builders() do
			build():Destroy()
			local before = listeners()
			local instance = build()
			instance.Parent = gui
			-- Exercise the selection-driven listeners (Slider stepping, hold-to-confirm).
			local selectable = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if selectable ~= nil then
				Support.select(env.guiService, selectable)
			end
			env:step(1 / 60)
			Support.select(env.guiService, nil)
			instance:Destroy()
			env:step(1 / 60)
			local after = listeners()
			if after ~= before then
				table.insert(leaks, `{name}: {after - before} listeners left`)
			end
		end
		table.sort(leaks)
		expect(leaks).toEqual({})
		gui:Destroy()
	end)

	it("leaves no rooted effects or observers after Destroy", function()
		local gui = Create("ScreenGui", { Name = "Leaks", Parent = env.playerGui })
		local leaks = {}
		for name, build in builders() do
			-- Warm-up: module caches are created on first use.
			build():Destroy()
			local before = State.stats().liveEffects
			for _ = 1, 3 do
				local instance = build()
				instance.Parent = gui
				instance:Destroy()
			end
			local after = State.stats().liveEffects
			if after ~= before then
				table.insert(leaks, `{name}: {after - before} rooted effects left`)
			end
		end
		table.sort(leaks)
		expect(leaks).toEqual({})
		gui:Destroy()
	end)

	it("does not keep updating destroyed instances from shared theme state", function()
		local label = Kit.Text.body("Text")
		local before = label.TextColor3
		label:Destroy()
		Theme.set({ highContrast = true })
		-- The binding died with the instance: no update after Destroy.
		expect(label.TextColor3).toEqual(before)
	end)
end)
