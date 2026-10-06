local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local VirtualList = require("@game/ReplicatedStorage/Client/UI/Kit/Components/VirtualList")
local VirtualGrid = require("@game/ReplicatedStorage/Client/UI/Kit/Components/VirtualGrid")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

-- Sets an engine-owned property on a mock without recording a script write, then fires its change signal.
local function engineSet(inst: any, property: string, value: any)
	rawget(inst, "_props")[property] = value
	inst:GetPropertyChangedSignal(property):Fire()
end

local function scrollTo(frame: any, offset: number, horizontal: boolean?)
	frame.CanvasPosition = if horizontal then Vector2.new(offset, 0) else Vector2.new(0, offset)
end

local function numbers(count: number): { number }
	local out = {}
	for i = 1, count do
		table.insert(out, i * 10)
	end
	return out
end

local renders = 0
local function render(item: any, index: any): any
	renders += 1
	return Create("TextButton", {
		Name = "Row",
		Text = State.Computed(function(): string
			return `{index:get()}:{tostring(item:get())}`
		end),
	})
end

local function visibleSlots(frame: any): { [number]: any }
	local out = {}
	for _, child in frame:GetChildren() do
		if child.Visible and child:GetAttribute("VirtualIndex") ~= nil then
			out[child:GetAttribute("VirtualIndex")] = child
		end
	end
	return out
end

describe("VirtualList windowing math", function()
	it("computes row offsets and content extent", function()
		expect(VirtualList.itemOffset(1, 40, 8, 16)).toBe(16)
		expect(VirtualList.itemOffset(3, 40, 8, 16)).toBe(16 + 2 * 48)
		expect(VirtualList.contentExtent(0, 40, 8, 16, 16)).toBe(32)
		expect(VirtualList.contentExtent(1, 40, 8, 0, 0)).toBe(40)
		expect(VirtualList.contentExtent(250, 40, 8, 16, 16)).toBe(16 + 250 * 40 + 249 * 8 + 16)
	end)

	it("returns exactly the intersecting rows without overscan", function()
		-- Rows of 40 with 10 gap: row i spans [50(i-1), 50(i-1)+40).
		expect({ VirtualList.window(100, 40, 10, 0, 0, 100, 0) }).toEqual({ 1, 2 })
		-- Offset 45: row 1 ends at 40 (hidden), row 2 starts at 50.
		expect({ VirtualList.window(100, 40, 10, 0, 45, 100, 0) }).toEqual({ 2, 3 })
		-- Offset 39.5: row 1 still shows half a pixel.
		expect({ VirtualList.window(100, 40, 10, 0, 39.5, 100, 0) }).toEqual({ 1, 3 })
		-- Viewport edge exactly at a row start does not include that row.
		expect({ VirtualList.window(100, 40, 10, 0, 0, 50, 0) }).toEqual({ 1, 1 })
	end)

	it("widens by overscan and clamps to the list", function()
		expect({ VirtualList.window(100, 40, 10, 0, 500, 100, 2) }).toEqual({ 9, 14 })
		expect({ VirtualList.window(100, 40, 10, 0, 0, 100, 3) }).toEqual({ 1, 5 })
		expect({ VirtualList.window(12, 40, 10, 0, 450, 200, 3) }).toEqual({ 7, 12 })
		expect({ VirtualList.window(0, 40, 10, 0, 0, 100, 2) }).toEqual({ 1, 0 })
		expect({ VirtualList.window(5, 0, 10, 0, 0, 100, 2) }).toEqual({ 1, 0 })
		-- Padding shifts the rows.
		expect({ VirtualList.window(100, 40, 10, 100, 0, 90, 0) }).toEqual({ 1, 0 })
		expect({ VirtualList.window(100, 40, 10, 100, 0, 120, 0) }).toEqual({ 1, 1 })
	end)

	it("computes lanes, cells, item ranges, pool sizes and ring slots", function()
		expect(VirtualList.lanesFor(1000, 220, 12, 32)).toBe(4) -- (1000 - 32 + 12) / 232 = 4.2
		expect(VirtualList.lanesFor(100, 220, 12, 0)).toBe(1)
		expect(VirtualList.lanesFor(1000, 220, 12, 0, 3)).toBe(3)
		expect({ VirtualList.cellOf(1, 4) }).toEqual({ 1, 1 })
		expect({ VirtualList.cellOf(4, 4) }).toEqual({ 1, 4 })
		expect({ VirtualList.cellOf(5, 4) }).toEqual({ 2, 1 })
		expect({ VirtualList.itemRange(2, 3, 4, 10) }).toEqual({ 5, 10 })
		expect({ VirtualList.itemRange(3, 3, 4, 9) }).toEqual({ 9, 9 })
		expect({ VirtualList.itemRange(2, 1, 4, 9) }).toEqual({ 1, 0 })
		expect(VirtualList.poolSizeFor(300, 40, 10, 2, 1)).toBe(6 + 1 + 4)
		expect(VirtualList.poolSizeFor(300, 40, 10, 2, 3)).toBe(33)
		expect(VirtualList.slotIndex(1, 11)).toBe(1)
		expect(VirtualList.slotIndex(12, 11)).toBe(1)
		expect(VirtualList.slotIndex(11, 11)).toBe(11)
	end)

	it("never needs more slots than the pool for any scroll position", function()
		for _, view in { 37, 100, 333, 1080 } do
			for _, overscan in { 0, 2, 5 } do
				local pool = VirtualList.poolSizeFor(view, 40, 10, overscan, 1)
				for offset = 0, 5000, 7 do
					local first, last = VirtualList.window(250, 40, 10, 8, offset, view, overscan)
					local size = last - first + 1
					if size > pool then
						error(`window {first}..{last} exceeds pool {pool} (view {view}, overscan {overscan})`)
					end
				end
			end
		end
	end)
end)

describe("VirtualList component", function()
	Test.beforeEach(function()
		renders = 0
		Theme.reset()
		InputMode.set("MouseKeyboard")
	end)

	it("builds a bounded pool for 250 items and binds the visible window", function()
		local frame, controller = VirtualList.new({ items = numbers(250), render = render, itemSize = 40, gap = 10 })
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 300))
		expect(controller.poolSize()).toBe(VirtualList.poolSizeFor(300, 40, 10, 2, 1))
		-- Slots are built on first use: only the 8 rows of the first window so far.
		expect(renders).toBe(8)
		expect(controller.slotCount()).toBe(8)
		expect(frame.CanvasSize).toEqual(UDim2.fromOffset(0, VirtualList.contentExtent(250, 40, 10, 0, 0)))
		local first, last = controller.range()
		expect({ first, last }).toEqual({ 1, 8 })
		local slots = visibleSlots(frame)
		expect(slots[1].Text).toBe("1:10")
		expect(slots[8].Text).toBe("8:80")
		expect(slots[3].Position).toEqual(UDim2.fromOffset(0, 100))
		expect(slots[3].Size).toEqual(UDim2.new(1, 0, 0, 40))
		Support.validateTree(frame)
		frame:Destroy()
	end)

	it("re-binds only the slots that change when scrolling (ring assignment)", function()
		local frame, controller = VirtualList.new({ items = numbers(250), render = render, itemSize = 40, gap = 10 })
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 300))
		local before = visibleSlots(frame)
		scrollTo(frame, 50) -- one row down
		local first, last = controller.range()
		expect({ first, last }).toEqual({ 1, 9 })
		local after = visibleSlots(frame)
		for index = 1, 8 do
			expect(after[index]).toBe(before[index])
		end
		expect(after[9].Text).toBe("9:90")
		scrollTo(frame, 5000)
		first, last = controller.range()
		expect({ first, last }).toEqual({ 99, 108 })
		expect(controller.slotFor(100).Text).toBe("100:1000")
		expect(controller.slotFor(5)).toBeNil()
		expect(controller.indexOf(controller.slotFor(100))).toBe(100)
		-- Never more slots than the ring, however far it scrolls (slot 10 was never needed here).
		expect(renders).toBe(controller.slotCount())
		expect(renders <= controller.poolSize()).toBe(true)
		expect(renders).toBe(10)
		frame:Destroy()
	end)

	it("follows item changes and shrinking lists", function()
		local items = State.Value(numbers(250))
		local frame, controller = VirtualList.new({ items = items, render = render, itemSize = 40, gap = 10 })
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 300))
		scrollTo(frame, 2000)
		items:set({ "a", "b", "c" })
		expect(frame.CanvasSize).toEqual(UDim2.fromOffset(0, 140))
		frame.CanvasPosition = Vector2.new(0, 0)
		local first, last = controller.range()
		expect({ first, last }).toEqual({ 1, 3 })
		local slots = visibleSlots(frame)
		expect(slots[2].Text).toBe("2:b")
		local count = 0
		for _ in slots do
			count += 1
		end
		expect(count).toBe(3)
		items:set({})
		expect({ controller.range() }).toEqual({ 1, 0 })
		expect(next(visibleSlots(frame))).toBeNil()
		frame:Destroy()
	end)

	it("grows the pool when the viewport grows", function()
		local frame, controller = VirtualList.new({ items = numbers(250), render = render, itemSize = 40, gap = 10 })
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 300))
		local small = controller.poolSize()
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 900))
		expect(controller.poolSize() > small).toBe(true)
		local first, last = controller.range()
		expect({ first, last }).toEqual({ 1, 20 })
		expect(visibleSlots(frame)[20].Text).toBe("20:200")
		frame:Destroy()
	end)

	it("lays out horizontally", function()
		local frame, controller = VirtualList.new({
			items = numbers(60),
			render = render,
			itemSize = 100,
			gap = 20,
			padding = 10,
			direction = "horizontal",
		})
		engineSet(frame, "AbsoluteSize", Vector2.new(500, 120))
		expect(frame.ScrollingDirection).toBe(Enum.ScrollingDirection.X)
		expect(frame.CanvasSize).toEqual(UDim2.fromOffset(VirtualList.contentExtent(60, 100, 20, 10, 10), 0))
		local slot = controller.slotFor(2)
		expect(slot.Position).toEqual(UDim2.fromOffset(10 + 120, 10))
		expect(slot.Size).toEqual(UDim2.new(0, 100, 1, -20))
		-- Column 11 starts at 10 + 10 * 120 = 1210 (first visible); 2 columns of overscan before it.
		scrollTo(frame, 1200, true)
		local first = controller.range()
		expect(first).toBe(9)
		frame:Destroy()
	end)

	it("reveals the gamepad-selected slot and scrolls by index", function()
		InputMode.set("Gamepad")
		local frame, controller = VirtualList.new({
			items = numbers(250),
			render = render,
			itemSize = 40,
			gap = 10,
			revealPadding = 10,
			animate = false,
		})
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 300))
		-- Row 7 spans [300, 340): selecting it scrolls so its bottom + padding is in view.
		Support.select(env.guiService, controller.slotFor(7))
		expect(frame.CanvasPosition).toEqual(Vector2.new(0, 340 + 10 - 300))
		-- Selecting a row above the view scrolls up to it.
		frame.CanvasPosition = Vector2.new(0, 400)
		Support.select(env.guiService, controller.slotFor(8))
		expect(frame.CanvasPosition).toEqual(Vector2.new(0, 350 - 10))
		local selected = controller.selectIndex(200)
		expect(selected).never.toBeNil()
		expect(env.guiService.SelectedObject).toBe(selected)
		expect(selected:GetAttribute("VirtualIndex")).toBe(200)
		expect(frame.CanvasPosition).toEqual(Vector2.new(0, 199 * 50 + 40 + 10 - 300))
		controller.scrollToIndex(1)
		expect(frame.CanvasPosition).toEqual(Vector2.new(0, 0))
		Support.select(env.guiService, nil)
		frame:Destroy()
	end)

	it("stops reacting after destroy", function()
		local items = State.Value(numbers(50))
		local frame, controller = VirtualList.new({ items = items, render = render, itemSize = 40 })
		engineSet(frame, "AbsoluteSize", Vector2.new(400, 300))
		local pool = controller.poolSize()
		frame:Destroy()
		items:set(numbers(500))
		expect(controller.poolSize()).toBe(pool)
	end)

	it("validates its arguments", function()
		expect(function()
			VirtualList.new({ items = {}, render = render, itemSize = 0 })
		end).toThrow("itemSize")
		expect(function()
			VirtualGrid.new({ items = {}, render = render, cell = Vector2.new(0, 10) })
		end).toThrow("cell")
	end)
end)

describe("VirtualGrid component", function()
	it("fills columns across the width and windows by rows", function()
		local frame, controller = VirtualGrid.new({
			items = numbers(300),
			render = render,
			cell = Vector2.new(200, 100),
			gap = 10,
			padding = 10,
		})
		engineSet(frame, "AbsoluteSize", Vector2.new(860, 330))
		-- (860 - 20 + 10) / 210 = 4.04 -> 4 columns; 75 rows.
		expect(controller.lanes()).toBe(4)
		expect(frame.CanvasSize).toEqual(UDim2.fromOffset(0, VirtualList.contentExtent(75, 100, 10, 10, 10)))
		local first, last = controller.range()
		-- Rows 1..3 visible (+2 overscan below) -> items 1..20.
		expect({ first, last }).toEqual({ 1, 20 })
		local slot = controller.slotFor(6)
		expect(slot.Position).toEqual(UDim2.fromOffset(10 + 210, 10 + 110))
		expect(slot.Size).toEqual(UDim2.fromOffset(200, 100))
		expect(controller.poolSize()).toBe(VirtualList.poolSizeFor(330, 100, 10, 2, 4))
		frame.CanvasPosition = Vector2.new(0, 1100)
		first, last = controller.range()
		expect(first).toBe((9 - 1) * 4 + 1)
		-- Narrowing the view drops to 2 columns and re-lays out.
		engineSet(frame, "AbsoluteSize", Vector2.new(440, 330))
		expect(controller.lanes()).toBe(2)
		frame:Destroy()
	end)

	it("respects maxLanes and horizontal grids", function()
		local frame, controller = VirtualGrid.new({
			items = numbers(40),
			render = render,
			cell = Vector2.new(100, 100),
			gap = Vector2.new(4, 8),
			direction = "horizontal",
			maxLanes = 2,
		})
		engineSet(frame, "AbsoluteSize", Vector2.new(600, 500))
		expect(controller.lanes()).toBe(2)
		-- Item 3 is column 2 (main axis X), lane 1 (cross axis Y).
		expect(controller.slotFor(3).Position).toEqual(UDim2.fromOffset(104, 0))
		expect(controller.slotFor(4).Position).toEqual(UDim2.fromOffset(104, 108))
		frame:Destroy()
	end)
end)
