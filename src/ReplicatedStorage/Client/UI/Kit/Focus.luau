--!strict
--[[
	Kit/Focus — gamepad navigation: focus scopes per screen/modal, initial focus, restoration, trapping, neighbours.

	Purpose:          Every screen (and modal, dropdown...) owns a FocusScope over its root. Scopes form a stack: the
	                  top scope owns GuiService.SelectedObject. Activating a scope makes its root a SelectionGroup
	                  (behaviour Escape, or Stop on all sides for trapped modals) and, in Gamepad mode, selects its
	                  remembered element, else its initial element, else the first selectable (lowest SelectionOrder,
	                  then top-left). Popping a scope restores the scope below exactly where it was. Selection that
	                  escapes a trapped scope is pulled back. Switching input mode to Gamepad repairs an invalid
	                  selection; switching away clears it (no stray focus ring for mouse/touch). LB/RB (and Q/E) go to
	                  the top scope's shoulder handler (tab bars). Helpers set explicit NextSelection* neighbours.
	Dependencies:     Kit/InputMode, Kit/UIInput, Kit/Services, Kit/Sound, Components/FocusRing, Core/Log.
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
	_shoulder: ((number) -> ())?,
	_destroyed: boolean,
}

local stack: { ScopeImpl } = {}
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

local function bestTarget(scope: ScopeImpl): GuiObject?
	local remembered = scope._remembered
	if scope._remember and remembered ~= nil and Focus.isSelectable(remembered, scope.root) then
		return remembered
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

local function rememberCurrent(scope: ScopeImpl)
	local current = selectedObject()
	if current ~= nil and Focus.contains(scope.root, current) then
		scope._remembered = current
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
		_shoulder = opts.onShoulder,
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
			self._remembered = target
		end
		return
	end
	local chosen = if target ~= nil and Focus.isSelectable(target, self.root) then target else bestTarget(self)
	setSelected(chosen)
end

function ScopeClass.setInitial(self: ScopeImpl, initial: (GuiObject | () -> GuiObject?)?)
	self._initial = initial
end

function ScopeClass.setShoulderHandler(self: ScopeImpl, handler: ((number) -> ())?)
	self._shoulder = handler
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
	self._initial = nil
	self._shoulder = nil
end

--- Routes a shoulder press (-1 LB, +1 RB) to the top scope. Returns true if a handler ran.
function Focus.shoulder(direction: number): boolean
	local top = stack[#stack]
	if top == nil or top._shoulder == nil then
		return false
	end
	local ok, err = pcall(top._shoulder :: any, direction)
	if not ok then
		log:error("shoulder handler of %s failed: %s", top.name, tostring(err))
	end
	return true
end

-- Selection changes: remember per scope, keep trapped scopes closed, tick the focus sound.
local function onSelectionChanged()
	local top = stack[#stack]
	local selected = selectedObject()
	if top == nil or selected == nil then
		return
	end
	if Focus.contains(top.root, selected) then
		top._remembered = selected
		if gamepadMode() then
			Sound.play(Sound.KEYS.hover)
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
			scope._remembered = selected
			return
		end
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
	UIInput.setEnabled(false)
end

return Focus
