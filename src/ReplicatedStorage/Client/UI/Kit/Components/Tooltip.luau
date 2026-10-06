--!strict
--[[
	Components/Tooltip — one shared tooltip for mouse hover, gamepad focus and touch long-press.

	Purpose:          `Tooltip.attach(target, "Reload 7.4 s")` (or `{ title, body }`) shows a small chamfered bg.panel
	                  card with the elevation shadow next to the target (ui-ux §1.7): after a 0.4 s hover (mouse),
	                  0.6 s after the element gains gamepad focus, or on a touch long-press (hidden again 1.5 s after
	                  release). Placement priority right -> left -> below -> above, 8 px from the target; the first
	                  side that fits wins, otherwise it is clamped into the viewport (pure `Tooltip.place`). Disabled
	                  buttons keep their tooltip reachable so the reason is readable (research 06 A5). A long-press never
	                  activates the button it explains (Common.markLongPress); activating, hiding or removing the target
	                  hides its tooltip (it must not linger over the next screen).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layers, Kit/Layout, Kit/Services, Kit/Motion,
	                  Components/Chamfer, Components/Shadow, Components/Text, Components/Common.
	State:            The shared view (created on first use in the Tooltip layer), the current owner and a pending
	                  show token.
	Validation:       Targets must be GuiObjects.
	Error handling:   Missing layers fall back to the target's ScreenGui; with neither, nothing is shown.
	Performance notes: One view for the whole UI; positions recomputed only when shown or resized.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layers = require("../Layers")
local Layout = require("../Layout")
local Services = require("../Services")
local Motion = require("../Motion")
local Chamfer = require("./Chamfer")
local Shadow = require("./Shadow")
local Text = require("./Text")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type Content = CanBeState<string> | { title: CanBeState<string>, body: CanBeState<string>? }
export type Placement = "top" | "bottom" | "left" | "right"
export type AttachOptions = {
	placement: Placement?,
	--- Hover delay in seconds (default Theme "tooltipDelay" = 0.4).
	delay: number?,
}

local Tooltip = {}

Tooltip.GAP = 8
Tooltip.TOUCH_HIDE_DELAY = 1.5
Tooltip.GAMEPAD_DELAY = 0.6
--- Default side priority (ui-ux §1.7).
local PRIORITY: { Placement } = { "right", "left", "bottom", "top" }
Tooltip.PRIORITY = table.freeze(PRIORITY)

--- Pure placement: top-left corner (screen px) for a tip of `tipSize` next to the target. With `placement`, tries
--- that side then its opposite; without, follows Tooltip.PRIORITY. The first side that fits wins; if none fits, the
--- first candidate is clamped inside the viewport.
function Tooltip.place(
	targetPosition: Vector2,
	targetSize: Vector2,
	tipSize: Vector2,
	viewport: Vector2,
	placement: Placement?,
	gap: number?
): (Vector2, Placement)
	local g = gap or Tooltip.GAP
	local function at(side: Placement): Vector2
		local cx = targetPosition.X + targetSize.X / 2 - tipSize.X / 2
		local cy = targetPosition.Y + targetSize.Y / 2 - tipSize.Y / 2
		if side == "top" then
			return Vector2.new(cx, targetPosition.Y - g - tipSize.Y)
		elseif side == "bottom" then
			return Vector2.new(cx, targetPosition.Y + targetSize.Y + g)
		elseif side == "left" then
			return Vector2.new(targetPosition.X - g - tipSize.X, cy)
		end
		return Vector2.new(targetPosition.X + targetSize.X + g, cy)
	end
	local function fits(position: Vector2, side: Placement): boolean
		if side == "top" then
			return position.Y >= 0
		elseif side == "bottom" then
			return position.Y + tipSize.Y <= viewport.Y
		elseif side == "left" then
			return position.X >= 0
		end
		return position.X + tipSize.X <= viewport.X
	end
	local opposite: { [string]: Placement } = { top = "bottom", bottom = "top", left = "right", right = "left" }
	local candidates: { Placement } = PRIORITY
	if placement ~= nil then
		candidates = { placement, opposite[placement] }
	end
	local side: Placement = candidates[1]
	local position = at(side)
	-- Indexed loop: generalized iteration widens the literal union to string in the old solver.
	for i = 1, #candidates do
		local candidate: Placement = candidates[i]
		local candidatePosition = at(candidate)
		if fits(candidatePosition, candidate) then
			side, position = candidate, candidatePosition
			break
		end
	end
	local x = math.clamp(position.X, 0, math.max(0, viewport.X - tipSize.X))
	local y = math.clamp(position.Y, 0, math.max(0, viewport.Y - tipSize.Y))
	return Vector2.new(x, y), side
end

type ViewState = {
	frame: Frame,
	title: State.Value<string>,
	body: State.Value<string>,
	hasTitle: State.Value<boolean>,
	hasBody: State.Value<boolean>,
}

local view: ViewState? = nil
local owner: GuiObject? = nil
local ownerPlacement: Placement? = nil
local showToken = 0

local reposition: () -> ()

local function ensureView(anchor: Instance): ViewState?
	local current = view
	local parent = Layers.parentFor("Tooltip", anchor)
	if parent == nil then
		return nil
	end
	if current ~= nil and current.frame.Parent == parent then
		return current
	end
	if current ~= nil then
		current.frame:Destroy()
	end
	local title = State.Value("")
	local body = State.Value("")
	local hasTitle = State.Value(false)
	local hasBody = State.Value(false)
	local frame = Create.Frame({
		Name = "KitTooltip",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = Theme.z("top"),
		Active = false,
		[Create.Children] = {
			Shadow.new({ zIndex = Theme.z("top") - 1 }) :: Instance,
			Chamfer.new({
				corners = "brand",
				size = Theme.chamfer("s"),
				fill = Theme.color("bg.panel"),
				border = Theme.color("border.strong"),
				borderThickness = Theme.borderWidth(),
				zIndex = Theme.z("top"),
			}),
			Create.UISizeConstraint({ MaxSize = Vector2.new(Theme.sizes.tooltipMaxWidth, math.huge) }),
			Layout.padding({ x = Theme.space(3), y = Theme.space(2) }),
			Layout.list({ gap = Theme.space(1) }),
			Text.new({
				Name = "Title",
				text = title,
				role = "title.s",
				Visible = hasTitle,
				LayoutOrder = 1,
				ZIndex = Theme.z("top") + 2,
			}),
			Text.new({
				Name = "Body",
				text = body,
				role = "body.s",
				color = "text.secondary",
				maxWidth = Theme.sizes.tooltipMaxWidth - 2 * Theme.space(3),
				Visible = hasBody,
				LayoutOrder = 2,
				ZIndex = Theme.z("top") + 2,
			}),
		},
		Parent = parent,
	})
	local created: ViewState = { frame = frame, title = title, body = body, hasTitle = hasTitle, hasBody = hasBody }
	view = created
	-- AutomaticSize settles after the text is set: re-place the tip once its real size is known.
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if owner ~= nil and frame.Visible then
			reposition()
		end
	end)
	return created
end

-- True while `target` is in a ScreenGui and it and its GuiObject ancestors are visible (a covered screen's host is
-- Visible = false; MouseLeave/SelectionLost do not reliably fire for elements hidden under the pointer/focus).
local function isShown(target: GuiObject): boolean
	local node: Instance? = target
	while node ~= nil do
		if node:IsA("GuiObject") then
			if (node :: GuiObject).Visible == false then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return (node :: LayerCollector).Enabled ~= false
		end
		node = node.Parent
	end
	return false
end

function reposition()
	local current = view
	local target = owner
	if current == nil or target == nil then
		return
	end
	if not isShown(target) then
		Tooltip.hide(target)
		return
	end
	local parent = current.frame.Parent
	if parent == nil or not parent:IsA("GuiObject") and not parent:IsA("LayerCollector") then
		return
	end
	local tipSize = current.frame.AbsoluteSize or Vector2.new(0, 0)
	local viewport = Services.viewportSize()
	local position = Tooltip.place(target.AbsolutePosition, target.AbsoluteSize, tipSize, viewport, ownerPlacement)
	-- Layer roots carry a UIScale and (on TV) a UIPadding safe margin: convert into the root's content space.
	local localPosition = Layers.toLocal(parent, position)
	current.frame.Position = UDim2.fromOffset(math.floor(localPosition.X + 0.5), math.floor(localPosition.Y + 0.5))
end

local function readContent(content: Content): (string, string)
	if type(content) == "table" and not State.isState(content) then
		local rich = content :: { title: CanBeState<string>, body: CanBeState<string>? }
		return State.peek(rich.title), if rich.body ~= nil then State.peek(rich.body) else ""
	end
	return "", State.peek(content :: CanBeState<string>)
end

--- Shows the tooltip for `target` now.
function Tooltip.show(target: GuiObject, content: Content, placement: Placement?)
	local current = ensureView(target)
	if current == nil then
		return
	end
	local title, body = readContent(content)
	State.batch(function()
		current.title:set(title)
		current.body:set(body)
		current.hasTitle:set(title ~= "")
		current.hasBody:set(body ~= "")
	end)
	owner = target
	ownerPlacement = placement
	current.frame.Visible = title ~= "" or body ~= ""
	reposition()
end

--- Hides the tooltip (only if `target` owns it, when given).
function Tooltip.hide(target: GuiObject?)
	showToken += 1
	if target ~= nil and owner ~= target then
		return
	end
	owner = nil
	local current = view
	if current ~= nil then
		current.frame.Visible = false
	end
end

--- The GuiObject currently showing a tooltip (nil when hidden).
function Tooltip.owner(): GuiObject?
	return owner
end

-- Runs `fn` after `delay` seconds of Heartbeat time unless another schedule/hide happens first.
local function schedule(delay: number, fn: () -> ())
	showToken += 1
	local token = showToken
	if delay <= 0 then
		fn()
		return
	end
	local elapsed = 0
	Motion.loop(function(dt: number): boolean?
		if token ~= showToken then
			return true
		end
		elapsed += dt
		if elapsed >= delay then
			fn()
			return true
		end
		return nil
	end)
end

--- Attaches a tooltip to `target`. Returns detach(); it also detaches when the target is destroyed.
function Tooltip.attach(target: GuiObject, content: Content, options: AttachOptions?): () -> ()
	if typeof(target) ~= "Instance" or not target:IsA("GuiObject") then
		error("Tooltip.attach expects a GuiObject", 2)
	end
	local opts: AttachOptions = options or {}
	local delay = opts.delay or Theme.duration("tooltipDelay")
	local placement: Placement? = opts.placement
	local connections: { RBXScriptConnection } = {}
	local function show()
		Tooltip.show(target, content, placement)
	end
	local function connect(signal: any, fn: (...any) -> ())
		table.insert(connections, signal:Connect(fn))
	end
	connect(target.MouseEnter, function()
		schedule(delay, show)
	end)
	connect(target.MouseLeave, function()
		Tooltip.hide(target)
	end)
	connect(target.SelectionGained, function()
		schedule(Tooltip.GAMEPAD_DELAY, show)
	end)
	connect(target.SelectionLost, function()
		Tooltip.hide(target)
	end)
	connect(target.InputBegan, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			-- A new press: forget a long-press mark that no Activated consumed (finger slid off).
			Common.clearLongPress(target)
		end
	end)
	connect(target.TouchLongPress, function(_positions: { Vector2 }, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			-- The release that ends this press must not activate the button (Button/Card/... consume the mark).
			Common.markLongPress(target)
			schedule(0, show)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			schedule(Tooltip.TOUCH_HIDE_DELAY, function()
				Tooltip.hide(target)
			end)
		end
	end)
	connect(target:GetPropertyChangedSignal("AbsolutePosition"), function()
		if owner == target then
			reposition()
		end
	end)
	connect(target.AncestryChanged, function()
		Tooltip.hide(target)
	end)
	if target:IsA("GuiButton") then
		-- Activating usually navigates or opens something: the explanation is no longer wanted.
		connect((target :: GuiButton).Activated, function()
			Tooltip.hide(target)
		end)
	end
	local detached = false
	local function detach()
		if detached then
			return
		end
		detached = true
		for _, connection in connections do
			connection:Disconnect()
		end
		if owner == target then
			Tooltip.hide(target)
		end
	end
	connect(target.Destroying, detach)
	return detach
end

return Tooltip
