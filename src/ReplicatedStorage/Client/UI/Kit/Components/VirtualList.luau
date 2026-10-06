--!strict
--[[
	Components/VirtualList — windowed lists and grids for hundreds of items (vehicles, inventory, replays).

	Purpose:          Only the items inside the viewport (plus `overscan` rows on each side) have instances. A fixed
	                  pool of slots is built once from `render(item, index)` — `item` and `index` are States the slot
	                  binds to — and slots are re-bound as the list scrolls with ring assignment (slot = index mod
	                  pool), so a one-row scroll re-binds one row and a selected slot keeps its item while it stays
	                  in the window. Works vertically or horizontally; grids fill lanes across the cross axis
	                  (columns for vertical grids). Gamepad: overscan keeps the next row selectable, and when
	                  selection lands on a slot the list scrolls it fully into view with `revealPadding` of context
	                  (Focus.revealOffset). The controller (second return) scrolls/selects by index.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Focus, Kit/InputMode, Kit/Motion, Kit/Services,
	                  Components/Common, Core/Trove.
	State:            The slot pool, current window and lane count per list.
	Validation:       itemSize/cell must be positive; overscan is clamped to 0..10.
	Error handling:   A failing `render` raises at construction (programming error).
	Performance notes: Instances = pool size (viewport rows + 1 + 2 × overscan) × lanes, independent of item count;
	                  refresh is O(pool) and runs on scroll, resize and item changes only.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Focus = require("../Focus")
local InputMode = require("../InputMode")
local Motion = require("../Motion")
local Services = require("../Services")
local Common = require("./Common")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

type CanBeState<T> = State.CanBeState<T>
type State<T> = State.State<T>

export type Direction = "vertical" | "horizontal"
export type Render = (item: State<any>, index: State<number>) -> GuiObject

export type VirtualListProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	items: CanBeState<{ any }>,
	--- Builds one pooled slot. `item`/`index` are States re-bound as the list scrolls (never nil); the engine
	--- owns the slot's Position, Size and Visible.
	render: Render,
	--- Main-axis size of an item in px (row height, or column width when horizontal).
	itemSize: number,
	--- Cross-axis size in px (default: fill the list minus padding).
	crossSize: number?,
	gap: number?,
	--- Content padding in px on all sides (default 0).
	padding: number?,
	direction: Direction?,
	--- Extra rows built beyond each edge (default 2).
	overscan: number?,
	--- Context kept around a gamepad-selected item when revealing it (default 48, ui-ux §1.13).
	revealPadding: number?,
	--- Animate reveal / scrollToIndex (default true).
	animate: boolean?,
}

export type VirtualGridProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	items: CanBeState<{ any }>,
	render: Render,
	cell: Vector2,
	gap: (number | Vector2)?,
	padding: number?,
	--- Scroll axis (default "vertical": columns fill the width, rows scroll).
	direction: Direction?,
	--- Lane cap (columns for vertical grids).
	maxLanes: number?,
	overscan: number?,
	revealPadding: number?,
	animate: boolean?,
}

export type Controller = {
	--- Scrolls so `index` is fully visible (with reveal padding).
	scrollToIndex: (index: number, animate: boolean?) -> (),
	--- Scrolls to `index` and gives its slot gamepad selection (when in gamepad mode). Returns the slot.
	selectIndex: (index: number) -> GuiObject?,
	--- Item index currently bound to a slot (or any descendant of it).
	indexOf: (object: Instance) -> number?,
	--- The slot showing `index`, if it is inside the window.
	slotFor: (index: number) -> GuiObject?,
	--- Current window (first, last); (1, 0) when empty.
	range: () -> (number, number),
	--- Slot capacity (ring size).
	poolSize: () -> number,
	--- Slots built so far (<= poolSize; slots are built on first use).
	slotCount: () -> number,
	lanes: () -> number,
	refresh: () -> (),
}

local VirtualList = {}

VirtualList.DEFAULT_OVERSCAN = 2

--------------------------------------------------------------------------------
-- Pure windowing math (content coordinates, px)
--------------------------------------------------------------------------------

--- Start of row `index` (1-based) along the main axis.
function VirtualList.itemOffset(index: number, itemExtent: number, gap: number, paddingStart: number): number
	return paddingStart + (index - 1) * (itemExtent + gap)
end

--- Total content length for `count` rows.
function VirtualList.contentExtent(
	count: number,
	itemExtent: number,
	gap: number,
	paddingStart: number,
	paddingEnd: number
): number
	if count <= 0 then
		return paddingStart + paddingEnd
	end
	return paddingStart + count * itemExtent + (count - 1) * gap + paddingEnd
end

--- Rows intersecting [offset, offset + viewExtent), widened by `overscan` rows each side and clamped to 1..count.
--- Returns (first, last); (1, 0) when there is nothing to show.
function VirtualList.window(
	count: number,
	itemExtent: number,
	gap: number,
	paddingStart: number,
	offset: number,
	viewExtent: number,
	overscan: number
): (number, number)
	if count <= 0 or itemExtent <= 0 then
		return 1, 0
	end
	local stride = itemExtent + gap
	local first = math.floor((offset - paddingStart - itemExtent) / stride) + 2 - overscan
	local last = math.ceil((offset + math.max(viewExtent, 0) - paddingStart) / stride) + overscan
	first = math.clamp(first, 1, count)
	last = math.clamp(last, 0, count)
	if last < first then
		return 1, 0
	end
	return first, last
end

--- Lanes (columns of a vertical grid) that fit across `crossExtent`.
function VirtualList.lanesFor(
	crossExtent: number,
	cellCross: number,
	gap: number,
	paddingTotal: number,
	maxLanes: number?
): number
	if cellCross <= 0 then
		return 1
	end
	local lanes = math.floor((crossExtent - paddingTotal + gap) / (cellCross + gap))
	lanes = math.max(1, lanes)
	if maxLanes ~= nil then
		lanes = math.min(lanes, math.max(1, maxLanes))
	end
	return lanes
end

--- (row, lane) of item `index` (1-based) in a grid with `lanes` lanes.
function VirtualList.cellOf(index: number, lanes: number): (number, number)
	local zero = index - 1
	return zero // lanes + 1, zero % lanes + 1
end

--- Item index range for a row window.
function VirtualList.itemRange(firstRow: number, lastRow: number, lanes: number, itemCount: number): (number, number)
	if lastRow < firstRow or itemCount <= 0 then
		return 1, 0
	end
	return (firstRow - 1) * lanes + 1, math.min(lastRow * lanes, itemCount)
end

--- Slots needed to cover any window: (visible rows + 1 + 2 × overscan) × lanes.
function VirtualList.poolSizeFor(
	viewExtent: number,
	itemExtent: number,
	gap: number,
	overscan: number,
	lanes: number
): number
	local stride = math.max(1, itemExtent + gap)
	local rows = math.ceil(math.max(viewExtent, 0) / stride) + 1 + 2 * overscan
	return math.max(1, rows * lanes)
end

--- Ring assignment: the pool slot that shows `index`.
function VirtualList.slotIndex(index: number, poolSize: number): number
	return (index - 1) % poolSize + 1
end

--------------------------------------------------------------------------------
-- Engine
--------------------------------------------------------------------------------

type Slot = {
	item: State.Value<any>,
	index: State.Value<number>,
	gui: GuiObject,
	assigned: number?,
}

type EngineConfig = {
	props: any,
	render: Render,
	direction: Direction,
	mainExtent: number,
	--- nil = fill the cross axis (lists).
	crossExtent: number?,
	mainGap: number,
	crossGap: number,
	padding: number,
	grid: boolean,
	maxLanes: number?,
}

local function build(config: EngineConfig): (ScrollingFrame, Controller)
	local props = config.props
	local vertical = config.direction ~= "horizontal"
	local overscan = math.clamp(math.floor(props.overscan or VirtualList.DEFAULT_OVERSCAN), 0, 10)
	local revealPadding = props.revealPadding or 48
	local animate = props.animate ~= false
	local pad = config.padding
	local scope = Trove.new()

	local frame = Create.ScrollingFrame({
		Name = props.Name or (if config.grid then "VirtualGrid" else "VirtualList"),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		ScrollingDirection = if vertical then Enum.ScrollingDirection.Y else Enum.ScrollingDirection.X,
		ScrollBarThickness = State.Computed(function(): number
			local mode = InputMode.mode:get()
			if mode == "Gamepad" then
				return Theme.sizes.scrollBar.gamepad
			elseif mode == "Touch" then
				return Theme.sizes.scrollBar.touch
			end
			return Theme.sizes.scrollBar.mouse
		end),
		ScrollBarImageColor3 = Theme.color("accent.steel"),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.new(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	})
	Create.apply(frame, Common.layout(props, {}))

	local items: { any } = State.peek(props.items) or {}
	-- Sparse: slot numbers 1..poolCount, each created the first time an item is assigned to it.
	local pool: { [number]: Slot } = {}
	local poolCount = 0
	local lanes = 1
	local first, last = 1, 0
	local refreshing = false
	local revealTween: Tween? = nil

	local function viewSize(): Vector2
		local window = (frame :: any).AbsoluteWindowSize
		local size = if typeof(window) == "Vector2"
				and window.X > 0
				and window.Y > 0
			then window
			else frame.AbsoluteSize
		local scale = Common.effectiveScale(frame)
		return Vector2.new(size.X / scale, size.Y / scale)
	end

	local function mainOf(v: Vector2): number
		return if vertical then v.Y else v.X
	end
	local function crossOf(v: Vector2): number
		return if vertical then v.X else v.Y
	end

	local function rowCount(): number
		return math.ceil(#items / lanes)
	end

	-- Slots are created with their first item, so `render` never sees a nil item.
	local function newSlot(item: any, index: number): Slot
		local itemValue = State.Value(item, { scope = scope })
		local indexValue = State.Value(index, { scope = scope })
		local gui = config.render(itemValue, indexValue)
		gui:SetAttribute("VirtualIndex", index)
		gui.Parent = frame
		return { item = itemValue, index = indexValue, gui = gui, assigned = index }
	end

	local function place(slot: Slot, index: number)
		local row, lane = VirtualList.cellOf(index, lanes)
		local main = VirtualList.itemOffset(row, config.mainExtent, config.mainGap, pad)
		local gui = slot.gui
		if config.crossExtent == nil then
			gui.Position = if vertical then UDim2.fromOffset(pad, main) else UDim2.fromOffset(main, pad)
			gui.Size = if vertical
				then UDim2.new(1, -2 * pad, 0, config.mainExtent)
				else UDim2.new(0, config.mainExtent, 1, -2 * pad)
		else
			local crossExtent = config.crossExtent :: number
			local cross = pad + (lane - 1) * (crossExtent + config.crossGap)
			gui.Position = if vertical then UDim2.fromOffset(cross, main) else UDim2.fromOffset(main, cross)
			gui.Size = if vertical
				then UDim2.fromOffset(crossExtent, config.mainExtent)
				else UDim2.fromOffset(config.mainExtent, crossExtent)
		end
	end

	local function refresh()
		if refreshing then
			return
		end
		refreshing = true
		local view = viewSize()
		if config.grid then
			lanes =
				VirtualList.lanesFor(crossOf(view), config.crossExtent or 1, config.crossGap, 2 * pad, config.maxLanes)
		else
			lanes = 1
		end
		local rows = rowCount()
		local extent = VirtualList.contentExtent(rows, config.mainExtent, config.mainGap, pad, pad)
		frame.CanvasSize = if vertical then UDim2.fromOffset(0, extent) else UDim2.fromOffset(extent, 0)
		local wanted = VirtualList.poolSizeFor(mainOf(view), config.mainExtent, config.mainGap, overscan, lanes)
		wanted = math.min(wanted, math.max(#items, 1))
		-- Growing the pool changes the ring mapping, so every visible index is re-assigned below.
		local resized = wanted > poolCount
		if resized then
			poolCount = wanted
		end
		local offset = mainOf(frame.CanvasPosition)
		local firstRow, lastRow =
			VirtualList.window(rows, config.mainExtent, config.mainGap, pad, offset, mainOf(view), overscan)
		first, last = VirtualList.itemRange(firstRow, lastRow, lanes, #items)
		-- Keep the window within the pool (very tall viewports before the pool grows).
		if last - first + 1 > poolCount then
			last = first + poolCount - 1
		end
		local used: { [number]: boolean } = {}
		State.batch(function()
			for index = first, last do
				local slotNumber = VirtualList.slotIndex(index, poolCount)
				local slot = pool[slotNumber]
				used[slotNumber] = true
				if slot == nil then
					slot = newSlot(items[index], index)
					pool[slotNumber] = slot
				elseif slot.assigned ~= index or resized then
					slot.assigned = index
					slot.item:set(items[index])
					slot.index:set(index)
					slot.gui:SetAttribute("VirtualIndex", index)
				elseif slot.item:peek() ~= items[index] then
					slot.item:set(items[index])
				end
				local placed = slot :: Slot
				place(placed, index)
				placed.gui.Visible = true
			end
			for slotNumber, slot in pool do
				if not used[slotNumber] and slot.assigned ~= nil then
					slot.assigned = nil
					slot.gui.Visible = false
					slot.gui:SetAttribute("VirtualIndex", nil)
				end
			end
		end)
		refreshing = false
	end

	local function setOffset(target: number, smooth: boolean)
		if revealTween ~= nil then
			revealTween:Cancel()
			revealTween = nil
		end
		local position = if vertical
			then Vector2.new(frame.CanvasPosition.X, target)
			else Vector2.new(target, frame.CanvasPosition.Y)
		if smooth then
			revealTween = Motion.tween(frame, { CanvasPosition = position }, { duration = "fast", kind = "move" })
			if revealTween == nil then
				refresh()
			end
		else
			frame.CanvasPosition = position
			refresh()
		end
	end

	local function revealIndex(index: number, smooth: boolean)
		if index < 1 or index > #items then
			return
		end
		local row = VirtualList.cellOf(index, lanes)
		local start = VirtualList.itemOffset(row, config.mainExtent, config.mainGap, pad)
		local view = mainOf(viewSize())
		local offset = mainOf(frame.CanvasPosition)
		local target = Focus.revealOffset(start, config.mainExtent, offset, view, revealPadding)
		local content = VirtualList.contentExtent(rowCount(), config.mainExtent, config.mainGap, pad, pad)
		target = math.clamp(target, 0, math.max(0, content - view))
		if target ~= offset then
			setOffset(target, smooth)
		end
	end

	local function indexOf(object: Instance): number?
		for _, slot in pool do
			if slot.assigned ~= nil and (object == slot.gui or object:IsDescendantOf(slot.gui)) then
				return slot.assigned
			end
		end
		return nil
	end

	local function slotFor(index: number): GuiObject?
		if poolCount == 0 then
			return nil
		end
		local slot = pool[VirtualList.slotIndex(index, poolCount)]
		return if slot ~= nil and slot.assigned == index then slot.gui else nil
	end

	local controller: Controller = {
		scrollToIndex = function(index: number, smooth: boolean?)
			revealIndex(index, if smooth == nil then animate else smooth)
		end,
		selectIndex = function(index: number): GuiObject?
			revealIndex(index, false)
			refresh()
			local gui = slotFor(index)
			if gui ~= nil and InputMode.mode:peek() == "Gamepad" then
				pcall(function()
					Services.gui().SelectedObject = gui
				end)
			end
			return gui
		end,
		indexOf = indexOf,
		slotFor = slotFor,
		range = function(): (number, number)
			return first, last
		end,
		poolSize = function(): number
			return poolCount
		end,
		slotCount = function(): number
			local count = 0
			for _ in pool do
				count += 1
			end
			return count
		end,
		lanes = function(): number
			return lanes
		end,
		refresh = refresh,
	}

	scope:Add(frame:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh))
	scope:Add(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh))
	scope:Add(frame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refresh))
	local ok, guiService = pcall(Services.gui)
	if ok then
		scope:Add(guiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			local selected = guiService.SelectedObject
			if selected == nil or not selected:IsDescendantOf(frame) then
				return
			end
			local index = indexOf(selected)
			if index ~= nil then
				revealIndex(index, animate)
			end
		end))
	end
	if State.isState(props.items) then
		State.observe(props.items, function(newItems: { any })
			items = newItems or {}
			refresh()
		end, { scope = scope })
	end
	scope:Add(function()
		if revealTween ~= nil then
			revealTween:Cancel()
		end
	end)
	Create.onDestroy(frame, scope)
	refresh()
	return Common.parent(frame, props), controller
end

--- Vertical (default) or horizontal list. Returns the ScrollingFrame and its controller.
function VirtualList.new(props: VirtualListProps): (ScrollingFrame, Controller)
	if type(props.itemSize) ~= "number" or props.itemSize <= 0 then
		error("VirtualList: itemSize must be a positive number", 2)
	end
	local gap = props.gap or 0
	return build({
		props = props,
		render = props.render,
		direction = props.direction or "vertical",
		mainExtent = props.itemSize,
		crossExtent = props.crossSize,
		mainGap = gap,
		crossGap = 0,
		padding = props.padding or 0,
		grid = false,
		maxLanes = 1,
	})
end

--- Grid of fixed cells; lanes fit the cross axis. Returns the ScrollingFrame and its controller.
function VirtualList.grid(props: VirtualGridProps): (ScrollingFrame, Controller)
	local cell = props.cell
	if typeof(cell) ~= "Vector2" or cell.X <= 0 or cell.Y <= 0 then
		error("VirtualGrid: cell must be a positive Vector2", 2)
	end
	local vertical = props.direction ~= "horizontal"
	local gap = props.gap or 0
	local gapVector = if typeof(gap) == "Vector2" then gap :: Vector2 else Vector2.new(gap :: number, gap :: number)
	return build({
		props = props,
		render = props.render,
		direction = props.direction or "vertical",
		mainExtent = if vertical then cell.Y else cell.X,
		crossExtent = if vertical then cell.X else cell.Y,
		mainGap = if vertical then gapVector.Y else gapVector.X,
		crossGap = if vertical then gapVector.X else gapVector.Y,
		padding = props.padding or 0,
		grid = true,
		maxLanes = props.maxLanes,
	})
end

return VirtualList
