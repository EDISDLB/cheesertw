local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Focus = require("@game/ReplicatedStorage/Client/UI/Kit/Focus")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local UIInput = require("@game/ReplicatedStorage/Client/UI/Kit/UIInput")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local Sound = require("@game/ReplicatedStorage/Client/UI/Kit/Sound")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

local function button(name: string, props: { [string]: any }?): any
	local p: { [any]: any } = { Name = name }
	for k, v in props or {} do
		p[k] = v
	end
	return Create("TextButton", p)
end

local function setPosition(object: any, x: number, y: number)
	rawget(object, "_props").AbsolutePosition = Vector2.new(x, y)
end

describe("Focus pure helpers", function()
	it("computes chain neighbours with and without wrap", function()
		expect(Focus.chainIndices(3)).toEqual({ { next = 2 }, { prev = 1, next = 3 }, { prev = 2 } })
		expect(Focus.chainIndices(3, true)).toEqual({
			{ prev = 3, next = 2 },
			{ prev = 1, next = 3 },
			{ prev = 2, next = 1 },
		})
		expect(Focus.chainIndices(1, true)).toEqual({ {} })
		expect(Focus.chainIndices(0)).toEqual({})
	end)

	it("computes grid neighbours including a short last row", function()
		local g = Focus.gridIndices(7, 3)
		-- 1 2 3
		-- 4 5 6
		-- 7
		expect(g[1]).toEqual({ down = 4, right = 2 })
		expect(g[2]).toEqual({ down = 5, left = 1, right = 3 })
		expect(g[5]).toEqual({ up = 2, down = 7, left = 4, right = 6 })
		expect(g[6]).toEqual({ up = 3, down = 7, left = 5 })
		expect(g[7]).toEqual({ up = 4 })
		local wrapped = Focus.gridIndices(4, 2, true)
		expect(wrapped[1]).toEqual({ down = 3, left = 2, right = 2 })
		expect(wrapped[4]).toEqual({ up = 2, left = 3, right = 3 })
	end)

	it("computes reveal offsets", function()
		expect(Focus.revealOffset(100, 50, 0, 400)).toBe(0)
		expect(Focus.revealOffset(500, 50, 0, 400)).toBe(150)
		expect(Focus.revealOffset(500, 50, 0, 400, 8)).toBe(158)
		expect(Focus.revealOffset(40, 50, 100, 400, 8)).toBe(32)
		expect(Focus.revealOffset(2, 50, 100, 400, 8)).toBe(0)
	end)
end)

describe("Focus selection queries", function()
	it("checks selectability through visibility, containment and LayerCollectors", function()
		local gui = Create("ScreenGui", {})
		local root = Create("Frame", { Name = "Root", Parent = gui })
		local panel = Create("Frame", { Parent = root })
		local a = button("A", { Parent = panel })
		local outside = button("Outside", { Parent = gui })
		expect(Focus.isSelectable(a, root)).toBe(true)
		expect(Focus.isSelectable(outside, root)).toBe(false)
		expect(Focus.isSelectable(nil, root)).toBe(false)
		expect(Focus.isSelectable(panel, root)).toBe(false)
		panel.Visible = false
		expect(Focus.isSelectable(a, root)).toBe(false)
		panel.Visible = true
		a.Selectable = false
		expect(Focus.isSelectable(a, root)).toBe(false)
		a.Selectable = true
		gui.Enabled = false
		expect(Focus.isSelectable(a)).toBe(false)
		gui.Enabled = true
		a.Interactable = false
		expect(Focus.isSelectable(a, root)).toBe(false)
	end)

	it("picks the first selectable by SelectionOrder, then position", function()
		local root = Create("Frame", {})
		local a = button("A", { Parent = root })
		local b = button("B", { Parent = root })
		local c = button("C", { Parent = root })
		setPosition(a, 200, 100)
		setPosition(b, 10, 100)
		setPosition(c, 0, 300)
		expect(Focus.firstSelectable(root)).toBe(b)
		c.SelectionOrder = -1
		expect(Focus.firstSelectable(root)).toBe(c)
		expect(Focus.firstSelectable(Create("Frame", {}))).toBeNil()
	end)

	it("sets selection groups, neighbours, chains and grids", function()
		local root = Create("Frame", {})
		Focus.setGroup(root, true)
		expect(root.SelectionGroup).toBe(true)
		expect(root.SelectionBehaviorLeft).toBe(Enum.SelectionBehavior.Stop)
		Focus.setGroup(root, false)
		expect(root.SelectionBehaviorUp).toBe(Enum.SelectionBehavior.Escape)
		local items = { button("1"), button("2"), button("3") }
		Focus.chain(items, "horizontal", true)
		expect(items[1].NextSelectionLeft).toBe(items[3])
		expect(items[2].NextSelectionRight).toBe(items[3])
		Focus.chain(items, "vertical")
		expect(items[1].NextSelectionDown).toBe(items[2])
		expect(items[3].NextSelectionDown).toBeNil()
		local cells = { button("g1"), button("g2"), button("g3"), button("g4") }
		Focus.grid(cells, 2)
		expect(cells[1].NextSelectionDown).toBe(cells[3])
		expect(cells[4].NextSelectionUp).toBe(cells[2])
		expect(cells[3].NextSelectionRight).toBe(cells[4])
		Support.validateTree(root)
	end)
end)

describe("Focus scopes", function()
	local stopInstall: () -> ()
	Test.beforeEach(function()
		Focus.reset()
		env.guiService.SelectedObject = nil
		InputMode.set("Gamepad")
		stopInstall = Focus.install({ playerGui = env.playerGui, startInput = false })
	end)
	Test.afterEach(function()
		stopInstall()
		Focus.reset()
		InputMode.set("MouseKeyboard")
	end)

	it("configures GuiService and the brand selection ring on install", function()
		expect(env.guiService.AutoSelectGuiEnabled).toBe(false)
		expect(env.guiService.GuiNavigationEnabled).toBe(true)
		expect(env.playerGui.SelectionImageObject.Name).toBe("KitFocusRing")
		Support.validateTree(env.playerGui.SelectionImageObject)
	end)

	it("focuses the initial element, remembers moves and restores after a modal", function()
		local screen = Create("Frame", { Name = "Screen" })
		local a = button("A", { Parent = screen })
		local b = button("B", { Parent = screen })
		local scope = Focus.scope(screen, {
			initial = function()
				return b
			end,
		})
		scope:activate()
		expect(env.guiService.SelectedObject).toBe(b)
		expect(screen.SelectionGroup).toBe(true)
		Support.select(env.guiService, a)
		expect(scope:remembered()).toBe(a)

		local modal = Create("Frame", { Name = "Modal" })
		local ok = button("OK", { Parent = modal })
		local modalScope = Focus.scope(modal, { trap = true })
		modalScope:activate()
		expect(Focus.top()).toBe(modalScope)
		expect(env.guiService.SelectedObject).toBe(ok)
		expect(modal.SelectionBehaviorDown).toBe(Enum.SelectionBehavior.Stop)

		-- Selection escaping a trapped modal is pulled back.
		Support.select(env.guiService, b)
		expect(env.guiService.SelectedObject).toBe(ok)

		modalScope:Destroy()
		expect(env.guiService.SelectedObject).toBe(a)
		expect(Focus.top()).toBe(scope)
		scope:deactivate()
		expect(#Focus.stack()).toBe(0)
	end)

	it("clears selection for mouse/touch and repairs it when the gamepad returns", function()
		local screen = Create("Frame", {})
		local a = button("A", { Parent = screen })
		local b = button("B", { Parent = screen })
		local scope = Focus.scope(screen)
		scope:activate()
		Support.select(env.guiService, b)
		InputMode.set("MouseKeyboard")
		expect(env.guiService.SelectedObject).toBeNil()
		InputMode.set("Gamepad")
		expect(env.guiService.SelectedObject).toBe(b)
		b.Visible = false
		env.guiService.SelectedObject = nil
		Focus.ensureValid()
		expect(env.guiService.SelectedObject).toBe(a)
		scope:Destroy()
	end)

	it("remembers explicit focus requests made while not on top", function()
		local screen = Create("Frame", {})
		local a = button("A", { Parent = screen })
		local b = button("B", { Parent = screen })
		local scope = Focus.scope(screen, { initial = a })
		local other = Focus.scope(Create("Frame", { [Create.Children] = { button("X") } }))
		scope:activate()
		other:activate()
		scope:focus(b)
		expect(scope:remembered()).toBe(b)
		expect(scope:isActive()).toBe(true)
		expect(scope:isTop()).toBe(false)
		other:Destroy()
		expect(env.guiService.SelectedObject).toBe(b)
		scope:focus()
		expect(env.guiService.SelectedObject).toBe(b)
		scope:Destroy()
	end)

	it("routes shoulder buttons to the top scope and toggles the UI input context", function()
		local seen = {}
		local screen = Create("Frame", { [Create.Children] = { button("A") } })
		local scope = Focus.scope(screen, {
			onShoulder = function(direction)
				table.insert(seen, direction)
			end,
		})
		expect(UIInput.isEnabled()).toBe(false)
		expect(UIInput.trigger("TabNext")).toBe(false)
		scope:activate()
		expect(UIInput.isEnabled()).toBe(true)
		UIInput.trigger("TabNext")
		UIInput.trigger("TabPrev")
		expect(seen).toEqual({ 1, -1 })
		scope:setShoulderHandler(nil)
		expect(Focus.shoulder(1)).toBe(false)
		scope:Destroy()
		expect(UIInput.isEnabled()).toBe(false)
		expect(function()
			Focus.push(scope)
		end).toThrow("destroyed")
	end)

	it("ticks for player moves only (not programmatic focus) and rate-limits fast scrolling", function()
		local now = 0
		Focus.setClock(function()
			return now
		end)
		Sound.resetCounts()
		local screen = Create("Frame", {})
		local a = button("A", { Parent = screen })
		local b = button("B", { Parent = screen })
		local c = button("C", { Parent = screen })
		local scope = Focus.scope(screen, { initial = a })
		scope:activate()
		-- Initial focus was set by Focus itself: its SelectionChanged is not a player move.
		expect(env.guiService.SelectedObject).toBe(a)
		expect(Sound.counts().ui_hover or 0).toBe(0)
		Support.select(env.guiService, b)
		expect(Sound.counts().ui_hover).toBe(1)
		-- Faster than HOVER_SOUND_RATE moves per second: silent.
		now += 0.05
		Support.select(env.guiService, c)
		expect(Sound.counts().ui_hover).toBe(1)
		now += 1 / Focus.HOVER_SOUND_RATE
		Support.select(env.guiService, a)
		expect(Sound.counts().ui_hover).toBe(2)
		-- scope:focus() is programmatic too.
		now += 1
		scope:focus(b)
		expect(Sound.counts().ui_hover).toBe(2)
		scope:Destroy()
		Focus.setClock(nil)
	end)

	it("restores to the nearest sibling when the remembered element is gone", function()
		local screen = Create("Frame", { Name = "Screen" })
		local list = Create("Frame", { Name = "List", Parent = screen })
		local rows = {}
		for i = 1, 4 do
			rows[i] = button("Row" .. i, { Parent = list })
			setPosition(rows[i], 0, i * 50)
		end
		local header = button("Header", { Parent = screen })
		setPosition(header, 0, 0)
		local scope = Focus.scope(screen, { initial = header })
		scope:activate()
		Support.select(env.guiService, rows[3])
		local modal = Focus.scope(Create("Frame", { [Create.Children] = { button("OK") } }), { trap = true })
		modal:activate()
		-- While the modal is up, the remembered row is removed (e.g. the item was sold).
		rows[3]:Destroy()
		modal:Destroy()
		expect(env.guiService.SelectedObject).toBe(rows[2])
		expect(Focus.nearestIndex({ Vector2.new(0, 0), Vector2.new(0, 10) }, Vector2.new(0, 8))).toBe(2)
		expect(Focus.nearestIndex({}, Vector2.new(0, 0))).toBeNil()
		scope:Destroy()
	end)

	it("scrolls the focused region with the right stick (dead zone, speed, clamp, opt-out)", function()
		expect(Focus.stickScrollStep(100, 0.2, 1, 500, 2000)).toBe(100)
		expect(Focus.stickScrollStep(100, -1, 0.5, 500, 2000)).toBe(550)
		expect(Focus.stickScrollStep(100, 1, 1, 500, 2000)).toBe(0)
		expect(Focus.stickScrollStep(1400, -1, 1, 500, 2000)).toBe(1500)
		local screen = Create("Frame", { Name = "Screen" })
		local scroller = Create("ScrollingFrame", { Name = "Scroller", Parent = screen })
		local props = rawget(scroller, "_props")
		props.AbsoluteWindowSize = Vector2.new(400, 500)
		props.AbsoluteCanvasSize = Vector2.new(400, 2000)
		props.CanvasPosition = Vector2.new(0, 0)
		props.ScrollingDirection = Enum.ScrollingDirection.Y
		local row = button("Row", { Parent = scroller })
		InputMode.set("Gamepad")
		local scope = Focus.scope(screen)
		scope:activate()
		expect(env.guiService.SelectedObject).toBe(row)
		Focus.setStick(Vector2.new(0, -1))
		env:step(0.1)
		expect(scroller.CanvasPosition.Y).toBeCloseTo(90, 1e-6)
		Focus.setStick(Vector2.new(0, 0))
		env:step(0.1)
		expect(scroller.CanvasPosition.Y).toBeCloseTo(90, 1e-6)
		scope:Destroy()
		local orbit = Focus.scope(screen, { stickScroll = false })
		orbit:activate()
		Focus.setStick(Vector2.new(0, -1))
		env:step(0.1)
		expect(scroller.CanvasPosition.Y).toBeCloseTo(90, 1e-6)
		Focus.setStick(Vector2.new(0, 0))
		orbit:Destroy()
	end)

	it("pages the focused scroll region by one viewport minus 10 % and focuses the new page", function()
		expect(Focus.pageOffset(0, 500, 2000, 1)).toBe(450)
		expect(Focus.pageOffset(450, 500, 2000, -1)).toBe(0)
		expect(Focus.pageOffset(1400, 500, 2000, 1)).toBe(1500)
		expect(Focus.pageOffset(0, 500, 300, 1)).toBe(0)

		local screen = Create("Frame", { Name = "Screen" })
		local scroller = Create("ScrollingFrame", { Name = "Scroller", Parent = screen })
		local props = rawget(scroller, "_props")
		props.AbsoluteWindowSize = Vector2.new(400, 500)
		props.AbsoluteCanvasSize = Vector2.new(400, 2000)
		props.AbsolutePosition = Vector2.new(0, 0)
		props.CanvasPosition = Vector2.new(0, 0)
		props.ScrollingDirection = Enum.ScrollingDirection.Y
		local rows = {}
		for i = 1, 20 do
			rows[i] = button("Row" .. i, { Parent = scroller })
			rawget(rows[i], "_props").AbsoluteSize = Vector2.new(400, 90)
		end
		local function layout()
			local offset = scroller.CanvasPosition.Y
			for i, row in rows do
				setPosition(row, 0, (i - 1) * 100 - offset)
			end
		end
		layout()
		local scope = Focus.scope(screen)
		scope:activate()
		Support.select(env.guiService, rows[1])
		expect(Focus.page(1)).toBe(true)
		expect(scroller.CanvasPosition).toEqual(Vector2.new(0, 450))
		layout()
		env:step()
		env:step()
		-- Row 6 starts at 500 - 450 = 50: the first row fully inside the new page.
		expect(env.guiService.SelectedObject).toBe(rows[6])
		-- A screen handler replaces the default paging (e.g. tech-tree zoom).
		local pages = {}
		scope:setPageHandler(function(direction)
			table.insert(pages, direction)
		end)
		UIInput.trigger("PageNext")
		UIInput.trigger("PagePrev")
		expect(pages).toEqual({ 1, -1 })
		expect(scroller.CanvasPosition).toEqual(Vector2.new(0, 450))
		scope:Destroy()
		expect(Focus.page(1)).toBe(false)
	end)

	it("rejects non-GuiObject roots", function()
		expect(function()
			Focus.scope(Instance.new("Folder") :: any)
		end).toThrow("GuiObject root")
	end)
end)

describe("UIInput", function()
	Test.afterEach(function()
		UIInput.setEnabled(false)
	end)

	it("builds an Input Action System context bound to the action keys", function()
		local stop = UIInput.start()
		local inputs = game:GetService("ReplicatedStorage"):FindFirstChild("Inputs")
		local context = inputs:FindFirstChild(UIInput.CONTEXT_NAME)
		expect(context.ClassName).toBe("InputContext")
		expect(context.Priority).toBe(UIInput.DEFAULT_PRIORITY)
		expect(context.Sink).toBe(false)
		local back = context:FindFirstChild("Back")
		expect(back:FindFirstChild("ButtonB").KeyCode).toBe(Enum.KeyCode.ButtonB)
		expect(back:FindFirstChild("Backspace").KeyCode).toBe(Enum.KeyCode.Backspace)
		UIInput.setEnabled(true)
		expect(context.Enabled).toBe(true)
		local fired = 0
		local connection = UIInput.back:Connect(function()
			fired += 1
		end)
		back.Pressed:Fire()
		rawset(env.userInputService, "_focusedTextBox", Create("TextBox", {}))
		back.Pressed:Fire()
		rawset(env.userInputService, "_focusedTextBox", nil)
		expect(fired).toBe(1)
		Support.validateTree(context)
		stop()
		expect(inputs:FindFirstChild(UIInput.CONTEXT_NAME)).toBeNil()
		connection:Disconnect()
	end)

	it("exposes every KitUI menu action as a signal (and binds them in the context)", function()
		local stop = UIInput.start()
		local context =
			game:GetService("ReplicatedStorage"):FindFirstChild("Inputs"):FindFirstChild(UIInput.CONTEXT_NAME)
		for _, name in UIInput.ACTIONS do
			expect(context:FindFirstChild(name)).never.toBeNil()
		end
		expect(context:FindFirstChild("Secondary"):FindFirstChild("ButtonX").KeyCode).toBe(Enum.KeyCode.ButtonX)
		expect(context:FindFirstChild("PageNext"):FindFirstChild("ButtonR2").KeyCode).toBe(Enum.KeyCode.ButtonR2)
		-- Confirm stays with the engine's selection activation.
		expect(context:FindFirstChild("Confirm")).toBeNil()
		UIInput.setEnabled(true)
		local fired = {}
		local connections = {
			UIInput.on("Secondary", function()
				table.insert(fired, "secondary")
			end),
			UIInput.on("Tertiary", function()
				table.insert(fired, "tertiary")
			end),
		}
		context:FindFirstChild("Secondary").Pressed:Fire()
		UIInput.trigger("Tertiary")
		expect(fired).toEqual({ "secondary", "tertiary" })
		expect(UIInput.signal("PagePrev")).toBe(UIInput.pagePrev)
		expect(function()
			UIInput.signal("Jump" :: any)
		end).toThrow("unknown action")
		for _, connection in connections do
			connection:Disconnect()
		end
		stop()
	end)

	it("rebinds the context and refreshes glyphs when an action is remapped", function()
		local stop = UIInput.start()
		local back = game:GetService("ReplicatedStorage")
			:FindFirstChild("Inputs")
			:FindFirstChild(UIInput.CONTEXT_NAME)
			:FindFirstChild("Back")
		local glyph = InputMode.glyphState("Back")
		InputMode.set("MouseKeyboard")
		expect(glyph:get().keyCode).toBe(Enum.KeyCode.Backspace)
		InputMode.registerAction("Back", { keyboard = { Enum.KeyCode.Delete }, gamepad = { Enum.KeyCode.ButtonB } })
		expect(back:FindFirstChild("Backspace")).toBeNil()
		expect(back:FindFirstChild("Delete").KeyCode).toBe(Enum.KeyCode.Delete)
		expect(back:FindFirstChild("ButtonB")).never.toBeNil()
		expect(glyph:get().keyCode).toBe(Enum.KeyCode.Delete)
		InputMode.registerAction("Back", { keyboard = { Enum.KeyCode.Backspace }, gamepad = { Enum.KeyCode.ButtonB } })
		expect(back:FindFirstChild("Backspace")).never.toBeNil()
		stop()
	end)

	it("falls back to UserInputService when asked", function()
		local stop = UIInput.start({ useFallback = true })
		UIInput.setEnabled(true)
		local fired = {}
		local a = UIInput.tabPrev:Connect(function()
			table.insert(fired, "prev")
		end)
		local b = UIInput.back:Connect(function()
			table.insert(fired, "back")
		end)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.ButtonL1 }), false)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.Backspace }), true)
		env.userInputService.InputBegan:Fire(Support.input({ KeyCode = Enum.KeyCode.ButtonB }), false)
		expect(fired).toEqual({ "prev", "back" })
		stop()
		a:Disconnect()
		b:Disconnect()
		expect(function()
			UIInput.trigger("Jump" :: any)
		end).toThrow("unknown action")
	end)
end)
