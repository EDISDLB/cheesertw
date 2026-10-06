--!strict
--[[
	Components/ScrollFrame — the kit's ScrollingFrame: themed bars, auto canvas, gamepad scroll-into-view.

	Purpose:          Every scrolling region on a screen should be one of these (or a VirtualList for long data):
	                  transparent background, accent.steel scroll bar sized per input mode (6 px mouse, 4 px gamepad/
	                  touch), AutomaticCanvasSize along the scroll axis, optional list/grid layout and padding, and —
	                  for gamepad — when selection moves to a descendant the frame scrolls it fully into view with
	                  `revealPadding` px of context (Focus.revealOffset, a 120 ms ease; instant under reduced motion).
	                  `ScrollFrame.reveal(frame, object)` does the same on demand (e.g. after a search jump).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Focus, Kit/InputMode, Kit/Motion,
	                  Kit/Services, Components/Common, Core/Trove.
	State:            One SelectedObject connection per frame (when reveal is on).
	Validation:       N/A.
	Error handling:   GuiService access failures (tests without it) disable reveal-on-select silently.
	Performance notes: AutomaticCanvasSize is engine-side; reveal math runs only on selection changes.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Focus = require("../Focus")
local InputMode = require("../InputMode")
local Motion = require("../Motion")
local Services = require("../Services")
local Common = require("./Common")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

type CanBeState<T> = State.CanBeState<T>

export type ScrollFrameProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	--- Scroll axis (default "y").
	direction: ("x" | "y" | "xy")?,
	list: Layout.ListOptions?,
	grid: Layout.GridOptions?,
	padding: Layout.PaddingSpec?,
	children: Common.Children?,
	--- Scroll gamepad selection into view (default true).
	reveal: boolean?,
	--- Context kept around the revealed element in px (default 48, ui-ux §1.13).
	revealPadding: number?,
}

local ScrollFrame = {}

--- Pure: the CanvasPosition that reveals an object at `objectPosition`/`objectSize` (content px) in a view of
--- `viewSize` scrolled to `canvasPosition`, on the allowed axes.
function ScrollFrame.revealPosition(
	objectPosition: Vector2,
	objectSize: Vector2,
	canvasPosition: Vector2,
	viewSize: Vector2,
	padding: number,
	axes: "x" | "y" | "xy"
): Vector2
	local x, y = canvasPosition.X, canvasPosition.Y
	if axes ~= "y" then
		x = Focus.revealOffset(objectPosition.X, objectSize.X, canvasPosition.X, viewSize.X, padding)
	end
	if axes ~= "x" then
		y = Focus.revealOffset(objectPosition.Y, objectSize.Y, canvasPosition.Y, viewSize.Y, padding)
	end
	return Vector2.new(x, y)
end

--- Scrolls `frame` so `object` (a descendant) is fully visible with `padding` (default 48) px of context. Returns the
--- target CanvasPosition.
function ScrollFrame.reveal(frame: ScrollingFrame, object: GuiObject, padding: number?, animate: boolean?): Vector2
	local scale = Common.effectiveScale(frame)
	local relative = (object.AbsolutePosition - frame.AbsolutePosition) / scale
	local contentPosition = relative + frame.CanvasPosition
	local window = (frame :: any).AbsoluteWindowSize
	local view = (if typeof(window) == "Vector2" and window.X > 0 then window else frame.AbsoluteSize) / scale
	local direction = frame.ScrollingDirection
	local axes: "x" | "y" | "xy" = if direction == Enum.ScrollingDirection.X
		then "x"
		elseif direction == Enum.ScrollingDirection.Y then "y"
		else "xy"
	local target = ScrollFrame.revealPosition(
		contentPosition,
		object.AbsoluteSize / scale,
		frame.CanvasPosition,
		view,
		padding or 48,
		axes
	)
	if target ~= frame.CanvasPosition then
		if animate == false then
			frame.CanvasPosition = target
		else
			Motion.tween(frame, { CanvasPosition = target }, { duration = "fast", kind = "move" })
		end
	end
	return target
end

function ScrollFrame.new(props: ScrollFrameProps): ScrollingFrame
	local direction = props.direction or "y"
	local children: { Instance } = {}
	if props.padding ~= nil then
		table.insert(children, Layout.padding(props.padding))
	end
	if props.list ~= nil then
		table.insert(children, Layout.list(props.list))
	elseif props.grid ~= nil then
		table.insert(children, Layout.grid(props.grid))
	end
	local extra: { Instance } = props.children or {}
	for _, child in extra do
		table.insert(children, child)
	end
	local values: { [any]: any } = Common.layout(props, {}, { Name = "ScrollFrame", Size = UDim2.fromScale(1, 1) })
	values.BackgroundTransparency = 1
	values.BorderSizePixel = 0
	values.Selectable = false
	values.ScrollingDirection = if direction == "x"
		then Enum.ScrollingDirection.X
		elseif direction == "y" then Enum.ScrollingDirection.Y
		else Enum.ScrollingDirection.XY
	values.CanvasSize = UDim2.new()
	values.CanvasPosition = Vector2.new(0, 0)
	values.AutomaticCanvasSize = if direction == "x"
		then Enum.AutomaticSize.X
		elseif direction == "y" then Enum.AutomaticSize.Y
		else Enum.AutomaticSize.XY
	values.ScrollBarThickness = State.Computed(function(): number
		local mode = InputMode.mode:get()
		if mode == "Gamepad" then
			return Theme.sizes.scrollBar.gamepad
		elseif mode == "Touch" then
			return Theme.sizes.scrollBar.touch
		end
		return Theme.sizes.scrollBar.mouse
	end)
	values.ScrollBarImageColor3 = Theme.color("accent.steel")
	values.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	values.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	values.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	values[Create.Children] = children
	local frame = Create.ScrollingFrame(values)
	if props.reveal ~= false then
		local scope = Trove.new()
		local ok, guiService = pcall(Services.gui)
		if ok then
			scope:Add(guiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
				local selected = guiService.SelectedObject
				if selected ~= nil and selected:IsDescendantOf(frame) then
					ScrollFrame.reveal(frame, selected, props.revealPadding)
				end
			end))
		end
		Create.onDestroy(frame, scope)
	end
	return Common.parent(frame, props)
end

return ScrollFrame
