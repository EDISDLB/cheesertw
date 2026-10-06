--!strict
--[[
	Kit/Focus — gamepad navigation: focus scopes per screen/modal, initial focus, restoration, trapping, neighbours.

	Purpose:          Every screen (and modal, dropdown...) owns a FocusScope over its root. Scopes form a stack: the
	                  top scope owns GuiService.SelectedObject. Activating a scope makes its root a SelectionGroup
	                  (behaviour Escape, or Stop on all sides for trapped modals) and, in Gamepad mode, selects its
	                  remembered element, else (when that element is gone) the nearest selectable sibling in the same
	                  list, else its initial element, else the first selectable (lowest SelectionOrder, then
	                  top-left). Popping a scope restores the scope below exactly where it was. Selection that
	                  escapes a trapped scope is pulled back. Switching input mode to Gamepad repairs an invalid
	                  selection; switching away clears it (no stray focus ring for mouse/touch). When the engine drops
	                  the selection (focused element destroyed, hidden or scrolled away) it is repaired one frame later
	                  (REG-INP-01; bounded so an engine that keeps dropping it is not fought). LB/RB (and Q/E) go to
	                  the top scope's shoulder handler (tab bars); LT/RT (Z/C) page the focused scroll region by one
	                  viewport minus 10 % and move focus into the new page (or the scope's own onPage handler); the
	                  right stick scrolls that region smoothly (900 px/s at full deflection) unless the scope opts out.
	                  The ui_hover tick plays for player moves only: never for programmatic focus, and at most
	                  HOVER_SOUND_RATE per second while scrolling fast (ui-ux §1.16). Helpers set explicit
	                  NextSelection* neighbours.
	Dependencies:     Kit/InputMode, Kit/UIInput, Kit/Services, Kit/Sound, Kit/Motion, Components/FocusRing,
	                  Core/Log.
	State:            Module-level scope stack (top = last) and the install() connections.
	Validation:       Scope roots must be GuiObjects; neighbour helpers ignore nil entries.
	Error handling:   Engine property writes are guarded; failures are logged, never thrown into input handlers.
	Performance notes: Selection validation walks ancestors (depth ~10) on selection changes only; firstSelectable
	                  scans the scope's descendants once per activation.

	GuiService.AutoSelectGuiEnabled is set to false (research 09 R3): focus always starts explicitly through this
	module, and View/Select stays free for the scoreboard.
]]

local InputMode = require("./InputMode")
local UIInput = require("./UIInput")
local Services = require("./Services")
local Sound = require("./Sound")
local Motion = require("./Motion")
local FocusRing = require("./Components/FocusRing")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

export type ScopeOptions = {
	name: string?,
	--- Modal behaviour: selection cannot leave the root (SelectionBehavior Stop + guard).
	trap: boolean?,
	--- Element (or function returning one) to focus when the scope activates without a remembered element.
	initial: (GuiObject | () -> GuiObject?)?,
	--- Remember the last focused element and restore it on re-activation (default true).
	remember: boolean?,
	--- LB/RB handler (-1 = previous, +1 = next) while this scope is on top.
	onShoulder: ((direction: number) -> ())?,
	--- LT/RT handler (-1 = page back, +1 = page forward); replaces the default scroll paging (e.g. tech-tree zoom).
	onPage: ((direction: number) -> ())?,
	--- Right stick scrolls the focused scroll region (default true; false where it orbits the camera instead).
	stickScroll: boolean?,
}

export type FocusScope = {
	root: GuiObject,
	name: string,
	trap: boolean,
	activate: (self: FocusScope) -> (),
	deactivate: (self: FocusScope) -> (),
	isActive: (self: FocusScope) -> boolean,
	isTop: (self: FocusScope) -> boolean,
	--- Focuses `target` (or the best target) now, if this scope is on top and the mode is Gamepad.
	focus: (self: FocusScope, target: GuiObject?) -> (),
	setInitial: (self: FocusScope, initial: (GuiObject | () -> GuiObject?)?) -> (),
	setShoulderHandler: (self: FocusScope, handler: ((direction: number) -> ())?) -> (),
	setPageHandler: (self: FocusScope, handler: ((direction: number) -> ())?) -> (),
	remembered: (self: FocusScope) -> GuiObject?,
	--- Best element to focus now: remembered -> initial -> first selectable.
	target: (self: FocusScope) -> GuiObject?,
	Destroy: (self: FocusScope) -> (),
}

export type Neighbors = { up: GuiObject?, down: GuiObject?, left: GuiObject?, right: GuiObject? }
export type InstallOptions = {
	--- PlayerGui whose SelectionImageObject gets the brand ring (default: LocalPlayer's).
	playerGui: PlayerGui?,
	--- Skip setting GuiService flags (tests).
	skipGuiService: boolean?,
	--- Also start UIInput (default true).
	startInput: boolean?,
}

local log = Log.scope("UI.Focus")

local Focus = {}

type ScopeImpl = {
	root: GuiObject,
	name: string,
	trap: boolean,
	_remember: boolean,
	_initial: (GuiObject | () -> GuiObject?)?,
	_remembered: GuiObject?,
	-- Where the remembered element lived (for nearest-sibling restoration when it is destroyed).
	_rememberedParent: Instance?,
	_rememberedPosition: Vector2?,
	_shoulder: ((number) -> ())?,
	_page: ((number) -> ())?,
	_stickScroll: boolean,
	_destroyed: boolean,
}

local stack: { ScopeImpl } = {}

--- Max ui_hover ticks per second while the player scrolls through a list (ui-ux §1.16); the limiter lives in
--- Kit/Sound so pointer hovers and focus moves share one budget.
Focus.HOVER_SOUND_RATE = Sound.HOVER_RATE
--- Fraction of the viewport kept as context when paging with LT/RT (ui-ux §1.13: one viewport minus 10 %).
Focus.PAGE_OVERLAP = 0.1
--- Right-stick scroll speed at full deflection (px/s, ui-ux §1.13) and its dead zone.
Focus.STICK_SCROLL_SPEED = 900
Focus.STICK_DEADZONE = 0.25
--- Automatic focus repairs allowed in a burst (each within REPAIR_WINDOW seconds of the previous one) without a
--- player move: guards against an engine that keeps dropping the selection; separate incidents always repair.
Focus.MAX_REPAIRS = 3
Focus.REPAIR_WINDOW = 0.5

-- The object Focus itself selected last (its SelectionChanged is not a player move: no hover tick). It stays set
-- until a DIFFERENT selection is observed: under Workspace.SignalBehavior = Deferred (Roblox's announced default) the
-- two writes of a restore (nil, then the target) queue two handler runs that both read the final target.
local expectedSelection: GuiObject? = nil
-- Cached right-stick scroll region (declared early: selection changes invalidate it).
local stickFrame: ScrollingFrame? = nil
-- Lost-focus repair state (see repairSelection): a repair queued for the next frame, consecutive repairs without a
-- player move, and the element that was selected when the engine dropped the selection.
local repairPending = false
local repairStreak = 0
local lastRepairAt = -math.huge
local lostObject: GuiObject? = nil
local clock: () -> number = os.clock
-- Shoulder handlers registered by components (TabBar): used when the top scope has no handler of its own.
local shoulderHandlers: { { object: GuiObject, fn: (number) -> () } } = {}
local ScopeClass = {}
ScopeClass.__index = ScopeClass

--------------------------------------------------------------------------------
-- Pure-ish helpers (instance tree queries)
--------------------------------------------------------------------------------

--- True if `object` is `root` or inside it.
function Focus.contains(root: Instance, object: Instance?): boolean
	if object == nil then
		return false
	end
	return object == root or object:IsDescendantOf(root)
end

--- True if `object` can take gamepad focus: a Selectable, visible, interactable GuiObject whose ancestors (up to
--- `root` or the LayerCollector) are visible/enabled, and that lies inside `root` when given.
function Focus.isSelectable(object: Instance?, root: Instance?): boolean
	if object == nil or not object:IsA("GuiObject") then
		return false
	end
	local gui = object :: GuiObject
	if gui.Selectable ~= true or gui.Visible == false or (gui :: any).Interactable == false then
		return false
	end
	if root ~= nil and not Focus.contains(root, gui) then
		return false
	end
	local node: Instance? = gui.Parent
	while node ~= nil do
		if node:IsA("GuiObject") then
			if (node :: GuiObject).Visible == false then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return (node :: LayerCollector).Enabled ~= false
		end
		if node == root then
			-- Ancestors above the scope root are the caller's business (a hidden screen has no active scope).
			return true
		end
		node = node.Parent
	end
	return true
end

local function positionOf(object: GuiObject): Vector2
	local ok, position = pcall(function()
		return object.AbsolutePosition
	end)
	if ok and typeof(position) == "Vector2" then
		return position
	end
	return Vector2.new(0, 0)
end

--- The element GuiService:Select would pick, deterministically: lowest SelectionOrder, then top-most, then
--- left-most, then tree order.
function Focus.firstSelectable(root: Instance): GuiObject?
	local best: GuiObject? = nil
	local bestOrder, bestY, bestX = math.huge, math.huge, math.huge
	for _, descendant in root:GetDescendants() do
		if Focus.isSelectable(descendant, root) then
			local gui = descendant :: GuiObject
			local order = gui.SelectionOrder or 0
			local position = positionOf(gui)
			local better = order < bestOrder
				or (order == bestOrder and (position.Y < bestY or (position.Y == bestY and position.X < bestX)))
			if better then
				best, bestOrder, bestY, bestX = gui, order, position.Y, position.X
			end
		end
	end
	return best
end

--- Marks `root` as a SelectionGroup; `trap` stops selection at its edges (modals).
function Focus.setGroup(root: GuiObject, trap: boolean)
	local behavior = if trap then Enum.SelectionBehavior.Stop else Enum.SelectionBehavior.Escape
	root.SelectionGroup = true
	root.SelectionBehaviorUp = behavior
	root.SelectionBehaviorDown = behavior
	root.SelectionBehaviorLeft = behavior
	root.SelectionBehaviorRight = behavior
end

--- Sets explicit neighbours (only the directions given).
function Focus.setNeighbors(object: GuiObject, neighbors: Neighbors)
	if neighbors.up ~= nil then
		object.NextSelectionUp = neighbors.up
	end
	if neighbors.down ~= nil then
		object.NextSelectionDown = neighbors.down
	end
	if neighbors.left ~= nil then
		object.NextSelectionLeft = neighbors.left
	end
	if neighbors.right ~= nil then
		object.NextSelectionRight = neighbors.right
	end
end

--- Pure: neighbour indices for a linear chain of `count` items ({ prev, next } per item; nil at open ends).
function Focus.chainIndices(count: number, wrap: boolean?): { { prev: number?, next: number? } }
	local out = {}
	for i = 1, count do
		local prev: number? = if i > 1 then i - 1 elseif wrap and count > 1 then count else nil
		local nextIndex: number? = if i < count then i + 1 elseif wrap and count > 1 then 1 else nil
		out[i] = { prev = prev, next = nextIndex }
	end
	return out
end

--- Pure: 4-way neighbour indices for `count` items laid out row-major in `columns` columns. Moving down from a
--- short last row's column goes to the last item; `wrap` wraps rows horizontally.
function Focus.gridIndices(
	count: number,
	columns: number,
	wrap: boolean?
): { { up: number?, down: number?, left: number?, right: number? } }
	local cols = math.max(1, math.floor(columns))
	local out = {}
	for i = 1, count do
		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		local rowStart = row * cols + 1
		local rowEnd = math.min(rowStart + cols - 1, count)
		local left: number? = if col > 0 then i - 1 elseif wrap and rowEnd > rowStart then rowEnd else nil
		local right: number? = if i < rowEnd then i + 1 elseif wrap and rowEnd > rowStart then rowStart else nil
		local up: number? = if row > 0 then i - cols else nil
		local down: number? = nil
		if i + cols <= count then
			down = i + cols
		elseif rowEnd < count then
			down = count
		end
		out[i] = { up = up, down = down, left = left, right = right }
	end
	return out
end

--- Links a list with NextSelection* in reading order ("horizontal" = left/right, "vertical" = up/down).
function Focus.chain(list: { GuiObject }, axis: "horizontal" | "vertical", wrap: boolean?)
	local links = Focus.chainIndices(#list, wrap)
	for i, object in list do
		local link = links[i]
		local prev = if link.prev then list[link.prev] else nil
		local nextObject = if link.next then list[link.next] else nil
		if axis == "horizontal" then
			Focus.setNeighbors(object, { left = prev, right = nextObject })
		else
			Focus.setNeighbors(object, { up = prev, down = nextObject })
		end
	end
end

--- Links a row-major grid of items with 4-way NextSelection*.
function Focus.grid(list: { GuiObject }, columns: number, wrap: boolean?)
	local links = Focus.gridIndices(#list, columns, wrap)
	for i, object in list do
		local link = links[i]
		Focus.setNeighbors(object, {
			up = if link.up then list[link.up] else nil,
			down = if link.down then list[link.down] else nil,
			left = if link.left then list[link.left] else nil,
			right = if link.right then list[link.right] else nil,
		})
	end
end

--- Pure: index (into `positions`) of the point nearest to `target`; nil for an empty list. Ties keep the first.
function Focus.nearestIndex(positions: { Vector2 }, target: Vector2): number?
	local best: number? = nil
	local bestDistance = math.huge
	for i, position in positions do
		local distance = (position - target).Magnitude
		if distance < bestDistance then
			best, bestDistance = i, distance
		end
	end
	return best
end

--- Pure: the scroll offset one page away (`direction` -1/+1): one viewport minus PAGE_OVERLAP, clamped to the
--- content.
function Focus.pageOffset(offset: number, viewExtent: number, contentExtent: number, direction: number): number
	local step = math.max(1, viewExtent * (1 - Focus.PAGE_OVERLAP))
	local maxOffset = math.max(0, contentExtent - viewExtent)
	return math.clamp(offset + (if direction < 0 then -step else step), 0, maxOffset)
end

--- Pure: the scroll offset after `dt` seconds of right-stick deflection `axis` (-1..1; up is positive, so pushing
--- down scrolls forward), with the dead zone rescaled away, clamped to the content.
function Focus.stickScrollStep(
	offset: number,
	axis: number,
	dt: number,
	viewExtent: number,
	contentExtent: number
): number
	local magnitude = math.abs(axis)
	if magnitude <= Focus.STICK_DEADZONE then
		return offset
	end
	local scaled = (magnitude - Focus.STICK_DEADZONE) / (1 - Focus.STICK_DEADZONE)
	local delta = -math.sign(axis) * scaled * Focus.STICK_SCROLL_SPEED * dt
	return math.clamp(offset + delta, 0, math.max(0, contentExtent - viewExtent))
end

--- Pure: the scroll offset that reveals [itemStart, itemStart + itemSize) inside a viewport of `viewSize` currently
--- scrolled to `offset` (all in content coordinates), keeping `padding` px of context. Unchanged if visible.
function Focus.revealOffset(
	itemStart: number,
	itemSize: number,
	offset: number,
	viewSize: number,
	padding: number?
): number
	local pad = padding or 0
	if itemStart - pad < offset then
		return math.max(0, itemStart - pad)
	end
	local itemEnd = itemStart + itemSize + pad
	if itemEnd > offset + viewSize then
		return math.max(0, itemEnd - viewSize)
	end
	return offset
end

--------------------------------------------------------------------------------
-- Scopes
--------------------------------------------------------------------------------

local function gamepadMode(): boolean
	return InputMode.mode:peek() == "Gamepad"
end

local function selectedObject(): GuiObject?
	local ok, selected = pcall(function(): GuiObject?
		return Services.gui().SelectedObject
	end)
	return if ok then selected else nil
end

local function setSelected(object: GuiObject?)
	expectedSelection = object
	local ok, err = pcall(function()
		Services.gui().SelectedObject = object
	end)
	if not ok then
		log:warn("cannot set SelectedObject: %s", tostring(err))
	end
end

local function resolveInitial(scope: ScopeImpl): GuiObject?
	local initial = scope._initial
	if initial == nil then
		return nil
	end
	if type(initial) == "function" then
		local ok, result = pcall(initial)
		return if ok then result else nil
	end
	return initial :: GuiObject
end

-- The selectable left in the remembered element's list that is closest to where it was.
local function nearestSibling(scope: ScopeImpl): GuiObject?
	local parent = scope._rememberedParent
	local position = scope._rememberedPosition
	if parent == nil or position == nil or not Focus.contains(scope.root, parent) then
		return nil
	end
	local candidates: { GuiObject } = {}
	local positions: { Vector2 } = {}
	for _, child in parent:GetChildren() do
		if Focus.isSelectable(child, scope.root) then
			table.insert(candidates, child :: GuiObject)
			table.insert(positions, positionOf(child :: GuiObject))
		end
	end
	local index = Focus.nearestIndex(positions, position)
	return if index ~= nil then candidates[index] else nil
end

local function bestTarget(scope: ScopeImpl): GuiObject?
	local remembered = scope._remembered
	if scope._remember and remembered ~= nil then
		if Focus.isSelectable(remembered, scope.root) then
			return remembered
		end
		local sibling = nearestSibling(scope)
		if sibling ~= nil then
			return sibling
		end
	end
	local initial = resolveInitial(scope)
	if initial ~= nil and Focus.isSelectable(initial, scope.root) then
		return initial
	end
	return Focus.firstSelectable(scope.root)
end

--- The active scope that owns selection (top of the stack).
function Focus.top(): FocusScope?
	local top = stack[#stack]
	return if top then (top :: any) :: FocusScope else nil
end

--- Copy of the active scope stack (bottom first).
function Focus.stack(): { FocusScope }
	return table.clone(stack) :: any
end

--- Makes the selection valid for the current mode: Gamepad -> inside the top scope (restoring its remembered or
--- initial element); other modes -> no selection.
function Focus.ensureValid()
	if not gamepadMode() then
		if selectedObject() ~= nil then
			setSelected(nil)
		end
		return
	end
	local top = stack[#stack]
	if top == nil then
		return
	end
	local current = selectedObject()
	if current ~= nil and Focus.isSelectable(current, top.root) then
		return
	end
	setSelected(bestTarget(top))
end

local function remember(scope: ScopeImpl, object: GuiObject)
	scope._remembered = object
	scope._rememberedParent = object.Parent
	scope._rememberedPosition = positionOf(object)
end

local function rememberCurrent(scope: ScopeImpl)
	local current = selectedObject()
	if current ~= nil and Focus.contains(scope.root, current) then
		remember(scope, current)
	end
end

--- Pushes `scope` on top (activating it). Re-pushing an active scope moves it to the top.
function Focus.push(scope: FocusScope)
	local impl = (scope :: any) :: ScopeImpl
	if impl._destroyed then
		error("Focus.push: scope is destroyed", 2)
	end
	local previous = stack[#stack]
	if previous ~= nil and previous ~= impl then
		rememberCurrent(previous)
	end
	local index = table.find(stack, impl)
	if index ~= nil then
		table.remove(stack, index)
	end
	Focus.setGroup(impl.root, impl.trap)
	table.insert(stack, impl)
	repairStreak = 0
	UIInput.setEnabled(true)
	Focus.ensureValid()
end

--- Removes `scope` from the stack; if it was on top, the scope below regains focus where it left off.
function Focus.pop(scope: FocusScope)
	local impl = (scope :: any) :: ScopeImpl
	local index = table.find(stack, impl)
	if index == nil then
		return
	end
	local wasTop = index == #stack
	if wasTop then
		rememberCurrent(impl)
	end
	table.remove(stack, index)
	repairStreak = 0
	UIInput.setEnabled(#stack > 0)
	if wasTop then
		local current = selectedObject()
		if current ~= nil and Focus.contains(impl.root, current) then
			setSelected(nil)
		end
		Focus.ensureValid()
	end
end

--- Creates a (not yet active) focus scope over `root`.
function Focus.scope(root: GuiObject, options: ScopeOptions?): FocusScope
	if typeof(root) ~= "Instance" or not root:IsA("GuiObject") then
		error("Focus.scope expects a GuiObject root", 2)
	end
	local opts: ScopeOptions = options or {}
	local impl: ScopeImpl = setmetatable({
		root = root,
		name = opts.name or root.Name,
		trap = opts.trap == true,
		_remember = opts.remember ~= false,
		_initial = opts.initial,
		_remembered = nil,
		_rememberedParent = nil,
		_rememberedPosition = nil,
		_shoulder = opts.onShoulder,
		_page = opts.onPage,
		_stickScroll = opts.stickScroll ~= false,
		_destroyed = false,
	}, ScopeClass) :: any
	return (impl :: any) :: FocusScope
end

function ScopeClass.activate(self: ScopeImpl)
	Focus.push(self :: any)
end

function ScopeClass.deactivate(self: ScopeImpl)
	Focus.pop(self :: any)
end

function ScopeClass.isActive(self: ScopeImpl): boolean
	return table.find(stack, self) ~= nil
end

function ScopeClass.isTop(self: ScopeImpl): boolean
	return stack[#stack] == self
end

function ScopeClass.focus(self: ScopeImpl, target: GuiObject?)
	if stack[#stack] ~= self or not gamepadMode() then
		if target ~= nil and Focus.contains(self.root, target) then
			remember(self, target)
		end
		return
	end
	local chosen = if target ~= nil and Focus.isSelectable(target, self.root) then target else bestTarget(self)
	setSelected(chosen)
end

--- Selects `target` programmatically (no ui_hover tick) when in gamepad mode. Returns true if it was selected.
function Focus.select(target: GuiObject?): boolean
	if not gamepadMode() then
		return false
	end
	setSelected(target)
	return true
end

function ScopeClass.setInitial(self: ScopeImpl, initial: (GuiObject | () -> GuiObject?)?)
	self._initial = initial
end

function ScopeClass.setShoulderHandler(self: ScopeImpl, handler: ((number) -> ())?)
	self._shoulder = handler
end

function ScopeClass.setPageHandler(self: ScopeImpl, handler: ((number) -> ())?)
	self._page = handler
end

function ScopeClass.remembered(self: ScopeImpl): GuiObject?
	return self._remembered
end

function ScopeClass.target(self: ScopeImpl): GuiObject?
	return bestTarget(self)
end

function ScopeClass.Destroy(self: ScopeImpl)
	if self._destroyed then
		return
	end
	Focus.pop(self :: any)
	self._destroyed = true
	self._remembered = nil
	self._rememberedParent = nil
	self._rememberedPosition = nil
	self._initial = nil
	self._shoulder = nil
	self._page = nil
end

--- Registers a component's LB/RB handler (tab bars). It receives presses while `object` is visible inside the
--- top scope and that scope has no handler of its own (newest registration wins). Returns unregister().
function Focus.registerShoulder(object: GuiObject, handler: (direction: number) -> ()): () -> ()
	local entry = { object = object, fn = handler }
	table.insert(shoulderHandlers, entry)
	return function()
		local index = table.find(shoulderHandlers, entry)
		if index ~= nil then
			table.remove(shoulderHandlers, index)
		end
	end
end

local function visibleWithin(object: GuiObject, root: GuiObject): boolean
	if not Focus.contains(root, object) then
		return false
	end
	local node: Instance? = object
	while node ~= nil and node ~= root do
		if node:IsA("GuiObject") and (node :: GuiObject).Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end

--- Routes a shoulder press (-1 LB, +1 RB) to the top scope (its own handler, else a registered component inside
--- it). Returns true if a handler ran.
function Focus.shoulder(direction: number): boolean
	local top = stack[#stack]
	if top == nil then
		return false
	end
	local handler = top._shoulder
	if handler == nil then
		for i = #shoulderHandlers, 1, -1 do
			local entry = shoulderHandlers[i]
			if visibleWithin(entry.object, top.root) then
				handler = entry.fn
				break
			end
		end
	end
	if handler == nil then
		return false
	end
	local ok, err = pcall(handler :: any, direction)
	if not ok then
		log:error("shoulder handler of %s failed: %s", top.name, tostring(err))
	end
	return true
end

--- Replaces the clock used for the hover-tick rate limit (Kit/Sound's) and the repair window (tests). nil restores
--- os.clock.
function Focus.setClock(fn: (() -> number)?)
	clock = fn or os.clock
	Sound.setClock(fn)
	lastRepairAt = -math.huge
end

-- Lost-focus repair (REG-INP-01: SelectedObject ~= nil in gamepad mode). The engine resets SelectedObject to nil when
-- the selected element is destroyed, hidden or scrolled off screen; with AutoSelectGuiEnabled = false nothing would
-- ever select again, stranding a gamepad player. One frame later (so list reconciles and VirtualList re-binds settle)
-- the top scope's best target is selected: the remembered element if it is still selectable, else its nearest
-- sibling, else initialFocus, else the first selectable. Bounded: MAX_REPAIRS consecutive repairs without a player
-- move, and an element the engine keeps dropping is skipped in favour of the scope's first selectable.

local function repairSelection()
	repairPending = false
	local top = stack[#stack]
	if top == nil or not gamepadMode() or selectedObject() ~= nil then
		return
	end
	local now = clock()
	if now - lastRepairAt > Focus.REPAIR_WINDOW then
		-- A new incident (e.g. the player removed another row a moment later), not an engine fight.
		repairStreak = 0
	end
	lastRepairAt = now
	repairStreak += 1
	if repairStreak > Focus.MAX_REPAIRS then
		return
	end
	local target = bestTarget(top)
	if target ~= nil and target == lostObject and repairStreak > 1 then
		-- Still "selectable" but the engine dropped it again (off screen): fall back to the scope's first element.
		local first = Focus.firstSelectable(top.root)
		target = if first ~= lostObject then first else nil
	end
	if target ~= nil then
		setSelected(target)
	end
end

local function scheduleRepair()
	if repairPending then
		return
	end
	repairPending = true
	Motion.loop(function(): boolean?
		repairSelection()
		return true
	end)
end

-- Selection changes: remember per scope, keep trapped scopes closed, tick the focus sound for player moves, and
-- repair focus the engine dropped.
local function onSelectionChanged()
	local top = stack[#stack]
	local selected = selectedObject()
	local programmatic = selected ~= nil and selected == expectedSelection
	if not programmatic then
		expectedSelection = nil
	end
	-- The stick-scroll region follows the selection.
	stickFrame = nil
	if top == nil then
		return
	end
	if selected == nil then
		if gamepadMode() then
			lostObject = top._remembered
			scheduleRepair()
		end
		return
	end
	if not programmatic then
		repairStreak = 0
	end
	if Focus.contains(top.root, selected) then
		remember(top, selected)
		if gamepadMode() and not programmatic then
			Sound.hover()
		end
		return
	end
	if top.trap then
		setSelected(bestTarget(top))
		return
	end
	for i = #stack - 1, 1, -1 do
		local scope = stack[i]
		if Focus.contains(scope.root, selected) then
			remember(scope, selected)
			return
		end
	end
end

-- Product of the UIScales above `instance` (screen px -> layout px).
local function uiScaleOf(instance: Instance): number
	local scale = 1
	local current: Instance? = instance
	while current ~= nil do
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale ~= nil then
			scale *= uiScale.Scale
		end
		current = current.Parent
	end
	return if scale > 0 then scale else 1
end

-- A region LT/RT and the right stick may scroll: scrolling enabled and visible up to the scope root (a list on a
-- hidden tab page, or a fixed carousel with ScrollingEnabled = false, is never the target).
local function scrollable(frame: Instance, top: ScopeImpl): boolean
	return frame:IsA("ScrollingFrame")
		and (frame :: ScrollingFrame).ScrollingEnabled ~= false
		and visibleWithin(frame :: GuiObject, top.root)
end

local function scrollContainer(top: ScopeImpl): ScrollingFrame?
	local selected = selectedObject()
	if selected ~= nil and Focus.contains(top.root, selected) then
		-- The nearest scrollable region around the focused element.
		local node: Instance? = selected.Parent
		while node ~= nil and node ~= top.root.Parent do
			if scrollable(node, top) then
				return node :: ScrollingFrame
			end
			if node == top.root then
				break
			end
			node = node.Parent
		end
	end
	for _, descendant in top.root:GetDescendants() do
		if scrollable(descendant, top) then
			return descendant :: ScrollingFrame
		end
	end
	return nil
end

-- After a page jump, focus the first selectable that is now fully inside the scroll window (gamepad only).
local function focusInView(top: ScopeImpl, frame: ScrollingFrame, vertical: boolean)
	if not gamepadMode() or stack[#stack] ~= top then
		return
	end
	local origin, window = frame.AbsolutePosition, frame.AbsoluteWindowSize
	local best: GuiObject? = nil
	local bestMain = math.huge
	for _, descendant in frame:GetDescendants() do
		if Focus.isSelectable(descendant, top.root) then
			local gui = descendant :: GuiObject
			local relative = gui.AbsolutePosition - origin
			local main = if vertical then relative.Y else relative.X
			local extent = if vertical then window.Y else window.X
			local size = if vertical then gui.AbsoluteSize.Y else gui.AbsoluteSize.X
			if main >= -0.5 and main + size <= extent + 0.5 and main < bestMain then
				best, bestMain = gui, main
			end
		end
	end
	if best ~= nil then
		setSelected(best)
	end
end

--- Routes a page press (-1 LT/Z, +1 RT/C): the top scope's onPage handler, else scrolls the focused scroll region
--- (or the scope's first ScrollingFrame) one viewport minus 10 % and moves gamepad focus into the new page.
--- Returns true if anything handled it.
function Focus.page(direction: number): boolean
	local top = stack[#stack]
	if top == nil then
		return false
	end
	local handler = top._page
	if handler ~= nil then
		local ok, err = pcall(handler :: any, direction)
		if not ok then
			log:error("page handler of %s failed: %s", top.name, tostring(err))
		end
		return true
	end
	local frame = scrollContainer(top)
	if frame == nil then
		return false
	end
	local vertical = frame.ScrollingDirection ~= Enum.ScrollingDirection.X
	-- Absolute sizes are screen px; CanvasPosition is in the canvas' own (unscaled) units, like VirtualList assumes.
	local scale = uiScaleOf(frame)
	local window, canvas, position =
		frame.AbsoluteWindowSize / scale, frame.AbsoluteCanvasSize / scale, frame.CanvasPosition
	local offset = if vertical then position.Y else position.X
	local target = Focus.pageOffset(
		offset,
		if vertical then window.Y else window.X,
		if vertical then canvas.Y else canvas.X,
		direction
	)
	if target == offset then
		return false
	end
	frame.CanvasPosition = if vertical then Vector2.new(position.X, target) else Vector2.new(target, position.Y)
	-- Let the engine (and VirtualLists) lay the new page out before choosing the element to focus.
	local frames = 0
	Motion.loop(function(): boolean?
		frames += 1
		if frames < 2 then
			return nil
		end
		focusInView(top, frame, vertical)
		return true
	end)
	return true
end

-- Right-stick scrolling state (install wires it). The region (and its UIScale product) is resolved once and cached
-- while the stick is held; a selection change or another top scope re-resolves it (no per-frame tree walks).
local stickAxis = Vector2.zero
local stopStickLoop: (() -> ())? = nil
local stickScope: ScopeImpl? = nil
local stickScale = 1

local function canStickScroll(): boolean
	local top = stack[#stack]
	return top ~= nil and top._stickScroll and gamepadMode()
end

local function stickStep(dt: number): boolean?
	local top = stack[#stack]
	if not canStickScroll() or stickAxis.Magnitude <= Focus.STICK_DEADZONE then
		stopStickLoop = nil
		stickFrame = nil
		return true
	end
	local scope = top :: ScopeImpl
	local frame = stickFrame
	-- Re-resolve when the region went away or out of view (a tab switch while the stick is held); the check is an
	-- ancestor walk, no allocation.
	if frame == nil or stickScope ~= scope or not scrollable(frame, scope) then
		frame = scrollContainer(scope)
		if frame == nil then
			stopStickLoop = nil
			return true
		end
		stickFrame, stickScope, stickScale = frame, scope, uiScaleOf(frame)
	end
	local region = frame :: ScrollingFrame
	local vertical = region.ScrollingDirection ~= Enum.ScrollingDirection.X
	local scale = stickScale
	local window, canvas, position =
		region.AbsoluteWindowSize / scale, region.AbsoluteCanvasSize / scale, region.CanvasPosition
	if vertical then
		local y = Focus.stickScrollStep(position.Y, stickAxis.Y, dt, window.Y, canvas.Y)
		if y ~= position.Y then
			region.CanvasPosition = Vector2.new(position.X, y)
		end
	else
		-- Horizontal regions scroll with the stick's X (right = forward).
		local x = Focus.stickScrollStep(position.X, -stickAxis.X, dt, window.X, canvas.X)
		if x ~= position.X then
			region.CanvasPosition = Vector2.new(x, position.Y)
		end
	end
	return nil
end

--- Feeds the right-stick position (install does this from UserInputService; tests call it directly). A loop runs
--- only while the top scope can stick-scroll: in battle (no scope) or on a camera-orbit screen (stickScroll =
--- false) the stick's InputChanged stream starts nothing.
function Focus.setStick(axis: Vector2)
	stickAxis = axis
	if stopStickLoop == nil and axis.Magnitude > Focus.STICK_DEADZONE and canStickScroll() then
		stopStickLoop = Motion.loop(stickStep)
	end
end

--- Global wiring (call once at client start): GuiService flags, brand focus ring, selection tracking, input-mode
--- repair and LB/RB routing. Returns stop().
function Focus.install(options: InstallOptions?): () -> ()
	local opts: InstallOptions = options or {}
	local GuiService = Services.gui()
	if not opts.skipGuiService then
		pcall(function()
			GuiService.AutoSelectGuiEnabled = false
			GuiService.GuiNavigationEnabled = true
		end)
	end
	local playerGui = opts.playerGui or Services.playerGui()
	if playerGui ~= nil then
		local ok, err = pcall(function()
			(playerGui :: PlayerGui).SelectionImageObject = FocusRing.get("default")
		end)
		if not ok then
			log:warn("cannot set SelectionImageObject: %s", tostring(err))
		end
	end
	local connections: { any } = {}
	table.insert(connections, GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged))
	table.insert(
		connections,
		InputMode.mode:onChange(function()
			Focus.ensureValid()
		end)
	)
	table.insert(
		connections,
		UIInput.tabPrev:Connect(function()
			Focus.shoulder(-1)
		end)
	)
	table.insert(
		connections,
		UIInput.tabNext:Connect(function()
			Focus.shoulder(1)
		end)
	)
	table.insert(
		connections,
		UIInput.pagePrev:Connect(function()
			Focus.page(-1)
		end)
	)
	table.insert(
		connections,
		Services.input().InputChanged:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				Focus.setStick(Vector2.new(input.Position.X, input.Position.Y))
			end
		end)
	)
	table.insert(
		connections,
		UIInput.pageNext:Connect(function()
			Focus.page(1)
		end)
	)
	local stopInput: (() -> ())? = nil
	if opts.startInput ~= false then
		stopInput = UIInput.start()
	end
	UIInput.setEnabled(#stack > 0)
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		if stopInput ~= nil then
			stopInput()
		end
	end
end

--- Clears every scope (tests, full UI teardown).
function Focus.reset()
	table.clear(stack)
	stickAxis = Vector2.zero
	if stopStickLoop ~= nil then
		stopStickLoop()
		stopStickLoop = nil
	end
	stickFrame, stickScope = nil, nil
	expectedSelection = nil
	Sound.resetHover()
	repairPending = false
	repairStreak = 0
	lastRepairAt = -math.huge
	lostObject = nil
	UIInput.setEnabled(false)
end

return Focus
