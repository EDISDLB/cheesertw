--!strict
--[[
	Kit/Layout — responsive scaling, breakpoints, safe areas and layout-object helpers.

	Purpose:          Implements the scale decisions (00-DECISIONS §16, brand-art §4.1): screens are authored at a
	                  reference canvas and a root UIScale maps it to the viewport —
	                    Regular (viewport height >= 600): scale = clamp(vh / 1080, 0.75, 1.5), x1.25 on TV (10-ft UI)
	                    Compact (viewport height <  600): authored at 844x390, scale = clamp(vh / 390, 0.92, 1.25)
	                  both multiplied by the player's UI-scale setting (0.8-1.2, Theme). TV gets a 5 % safe margin.
	                  Also derives the text-size platform profile (pc/console/phone/tablet) and pushes renderScale +
	                  platform into Theme so text minimums hold after scaling. Helpers build UIPadding / UIListLayout
	                  (incl. flex) / UIGridLayout / UIFlexItem / constraints from tokens.
	Dependencies:     Kit/State, Kit/Theme, Kit/Create, Kit/Services (engine reads in `start` only).
	State:            Module-level Values: viewport, tenFoot, displaySize; Computeds: breakpoint, scale, platform.
	Validation:       Viewport sizes <= 0 fall back to the reference size; helper options are checked.
	Error handling:   `start` tolerates a missing camera (waits for CurrentCamera) and missing engine properties.
	Performance notes: Recomputes only when the viewport/display/UI-scale changes; one UIScale per layer root.

	Compact scale bounds are a kit choice (decisions fix only the 844x390 authoring size): the 0.92 floor keeps a
	48 px primary target >= 44 rendered px (brand-art §4.2 touch minimum).
]]

local State = require("./State")
local Theme = require("./Theme")
local Create = require("./Create")
local Services = require("./Services")

type State<T> = State.State<T>

export type Breakpoint = "Regular" | "Compact"
export type Platform = Theme.Platform
export type ScaleOptions = {
	tenFoot: boolean?,
	userScale: number?,
}
export type PaddingSpec = number | {
	top: number?,
	bottom: number?,
	left: number?,
	right: number?,
	x: number?,
	y: number?,
}
export type Align = "start" | "center" | "end"
export type Justify = "start" | "center" | "end" | "between" | "around" | "evenly" | "fill"
export type ListOptions = {
	direction: ("x" | "y")?,
	gap: number?,
	align: Align?,
	justify: Justify?,
	wraps: boolean?,
	itemAlign: ("start" | "center" | "end" | "stretch")?,
}
export type GridOptions = {
	cell: Vector2 | UDim2,
	gap: (number | Vector2)?,
	maxCells: number?,
	direction: ("x" | "y")?,
	align: Align?,
}
export type FlexOptions = {
	grow: number?,
	shrink: number?,
	fill: boolean?,
}

local Layout = {}

Layout.REFERENCE = Vector2.new(1920, 1080)
Layout.COMPACT_REFERENCE = Vector2.new(844, 390)
Layout.CONFIG = table.freeze({
	SCALE_MIN = 0.75,
	SCALE_MAX = 1.5,
	TV_MULTIPLIER = 1.25,
	COMPACT_HEIGHT = 600,
	COMPACT_SCALE_MIN = 0.92,
	COMPACT_SCALE_MAX = 1.25,
	TV_SAFE_MARGIN = 0.05,
})

local function validViewport(viewport: Vector2?): Vector2
	if viewport == nil or viewport.X <= 0 or viewport.Y <= 0 or viewport.X ~= viewport.X then
		return Layout.REFERENCE
	end
	return viewport
end

--- Regular or Compact by viewport HEIGHT (not DisplaySize.Small, which includes tablets).
function Layout.breakpointFor(viewport: Vector2): Breakpoint
	local size = validViewport(viewport)
	return if size.Y < Layout.CONFIG.COMPACT_HEIGHT then "Compact" else "Regular"
end

--- Root UIScale for a viewport (pure).
function Layout.computeScale(viewport: Vector2, options: ScaleOptions?): number
	local opts: ScaleOptions = options or {}
	local size = validViewport(viewport)
	local config = Layout.CONFIG
	local scale
	if Layout.breakpointFor(size) == "Compact" then
		scale = math.clamp(size.Y / Layout.COMPACT_REFERENCE.Y, config.COMPACT_SCALE_MIN, config.COMPACT_SCALE_MAX)
	else
		scale = math.clamp(size.Y / Layout.REFERENCE.Y, config.SCALE_MIN, config.SCALE_MAX)
		if opts.tenFoot then
			scale *= config.TV_MULTIPLIER
		end
	end
	local user = opts.userScale or 1
	if user ~= user then
		user = 1
	end
	return scale * math.clamp(user, Theme.UI_SCALE_MIN, Theme.UI_SCALE_MAX)
end

--- Logical canvas size (reference px) that fills the viewport at `scale`.
function Layout.canvasSize(viewport: Vector2, scale: number): Vector2
	local size = validViewport(viewport)
	return Vector2.new(size.X / scale, size.Y / scale)
end

--- Text-size platform profile (brand-art §4.2).
function Layout.platformFor(viewport: Vector2, displaySize: EnumItem?, tenFoot: boolean): Platform
	if tenFoot or displaySize == Enum.DisplaySize.Large then
		return "console"
	end
	if displaySize == Enum.DisplaySize.Small then
		return if Layout.breakpointFor(viewport) == "Compact" then "phone" else "tablet"
	end
	return "pc"
end

--- Extra inner margin (fraction of the screen per side) for TV-safe areas; 0 elsewhere.
function Layout.safeMargin(tenFoot: boolean): number
	return if tenFoot then Layout.CONFIG.TV_SAFE_MARGIN else 0
end

--------------------------------------------------------------------------------
-- Live state
--------------------------------------------------------------------------------

local viewportValue = State.Value(Layout.REFERENCE)
local tenFootValue = State.Value(false)
local displaySizeValue: State.Value<EnumItem?> = State.Value(nil :: EnumItem?) :: any

local breakpointComputed: State<Breakpoint> = State.Computed(function(): Breakpoint
	return Layout.breakpointFor(viewportValue:get())
end) :: any

local scaleComputed = State.Computed(function(): number
	return Layout.computeScale(viewportValue:get(), {
		tenFoot = tenFootValue:get(),
		userScale = Theme.state.uiScale:get(),
	})
end)

local platformComputed: State<Platform> = State.Computed(function(): Platform
	return Layout.platformFor(viewportValue:get(), displaySizeValue:get(), tenFootValue:get())
end) :: any

local inverseScaleSize = State.Computed(function(): UDim2
	local scale = scaleComputed:get()
	return UDim2.fromScale(1 / scale, 1 / scale)
end)

local safePadding = State.Computed(function(): UDim
	return UDim.new(Layout.safeMargin(tenFootValue:get()), 0)
end)

Layout.state = {
	viewport = State.readonly(viewportValue),
	tenFoot = State.readonly(tenFootValue),
	breakpoint = breakpointComputed,
	scale = scaleComputed,
	platform = platformComputed,
}

--- True while the Compact layout is active (bind visibility/sizes to it).
Layout.isCompact = State.Computed(function(): boolean
	return breakpointComputed:get() == "Compact"
end)

--- Pure: the Theme layout family for an environment (TV wins over Compact).
function Layout.layoutModeFor(breakpoint: Breakpoint, tenFoot: boolean): Theme.LayoutMode
	if tenFoot then
		return "tv"
	elseif breakpoint == "Compact" then
		return "compact"
	end
	return "regular"
end

local function pushToTheme()
	Theme.setSystem({
		renderScale = scaleComputed:peek(),
		platform = platformComputed:peek(),
		layout = Layout.layoutModeFor(breakpointComputed:peek(), tenFootValue:peek()),
	})
end

--- Overrides the environment (tests, gallery previews, the device emulator). `start` keeps it in sync otherwise.
function Layout.setEnvironment(env: { viewport: Vector2?, tenFoot: boolean?, displaySize: EnumItem? })
	State.batch(function()
		if env.viewport ~= nil then
			viewportValue:set(validViewport(env.viewport))
		end
		if env.tenFoot ~= nil then
			tenFootValue:set(env.tenFoot)
		end
		if env.displaySize ~= nil then
			displaySizeValue:set(env.displaySize)
		end
	end)
	pushToTheme()
end

--- Follows the camera viewport, GuiService display size / 10-ft mode and the UI-scale setting. Returns stop().
function Layout.start(): () -> ()
	local connections: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local GuiService = Services.gui()

	local function readEngine()
		local tenFoot = false
		local okTenFoot, result = pcall(function()
			return GuiService:IsTenFootInterface()
		end)
		if okTenFoot then
			tenFoot = result == true
		end
		local okSize, displaySize = pcall(function()
			return GuiService.ViewportDisplaySize
		end)
		Layout.setEnvironment({
			viewport = Services.viewportSize(),
			tenFoot = tenFoot,
			displaySize = if okSize then displaySize else nil,
		})
	end

	local function bindCamera()
		if cameraConnection ~= nil then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = Services.camera()
		if camera ~= nil then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(readEngine)
		end
		readEngine()
	end

	bindCamera()
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
	local okDisplay, displaySignal = pcall(function()
		return GuiService:GetPropertyChangedSignal("ViewportDisplaySize")
	end)
	if okDisplay and displaySignal ~= nil then
		table.insert(connections, displaySignal:Connect(readEngine))
	end
	local uiScaleConnection = Theme.state.uiScale:onChange(pushToTheme)

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		if cameraConnection ~= nil then
			cameraConnection:Disconnect()
		end
		uiScaleConnection:Disconnect()
	end
end

--------------------------------------------------------------------------------
-- Root and helpers
--------------------------------------------------------------------------------

--- Scaled root for a ScreenGui layer: a full-screen Frame (size compensated by 1/scale so it still fills the
--- screen) with the shared UIScale and, when `safeArea` is true, the TV-safe padding. Children are authored in
--- reference px.
export type RootProps = { Name: string?, safeArea: boolean?, [any]: any }

function Layout.root(props: RootProps?): Frame
	local opts: RootProps = props or {}
	local extra: { [any]: any } = {}
	for key, value in opts do
		if key ~= "safeArea" then
			extra[key] = value
		end
	end
	extra.Name = opts.Name or "Root"
	extra.BackgroundTransparency = 1
	extra.Size = inverseScaleSize
	extra.Position = UDim2.new()
	extra.AnchorPoint = Vector2.new(0, 0)
	local children: { Instance } = {
		Create("UIScale", { Name = "RootScale", Scale = scaleComputed }),
	}
	if opts.safeArea then
		table.insert(
			children,
			Create("UIPadding", {
				Name = "SafeArea",
				PaddingTop = safePadding,
				PaddingBottom = safePadding,
				PaddingLeft = safePadding,
				PaddingRight = safePadding,
			})
		)
	end
	extra[Create.Children] = children
	return Create.Frame(extra)
end

--- UIPadding from a number (all sides) or { top, bottom, left, right, x, y } in px.
function Layout.padding(spec: PaddingSpec): UIPadding
	local top, bottom, left, right
	if type(spec) == "number" then
		top, bottom, left, right = spec, spec, spec, spec
	else
		top = spec.top or spec.y or 0
		bottom = spec.bottom or spec.y or 0
		left = spec.left or spec.x or 0
		right = spec.right or spec.x or 0
	end
	return Create.UIPadding({
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
	})
end

local function horizontalAlignment(align: Align?): Enum.HorizontalAlignment
	if align == "center" then
		return Enum.HorizontalAlignment.Center
	elseif align == "end" then
		return Enum.HorizontalAlignment.Right
	end
	return Enum.HorizontalAlignment.Left
end

local function verticalAlignment(align: Align?): Enum.VerticalAlignment
	if align == "center" then
		return Enum.VerticalAlignment.Center
	elseif align == "end" then
		return Enum.VerticalAlignment.Bottom
	end
	return Enum.VerticalAlignment.Top
end

local function flexAlignment(justify: Justify?): Enum.UIFlexAlignment
	if justify == "between" then
		return Enum.UIFlexAlignment.SpaceBetween
	elseif justify == "around" then
		return Enum.UIFlexAlignment.SpaceAround
	elseif justify == "evenly" then
		return Enum.UIFlexAlignment.SpaceEvenly
	elseif justify == "fill" then
		return Enum.UIFlexAlignment.Fill
	end
	return Enum.UIFlexAlignment.None
end

local function lineAlignment(align: ("start" | "center" | "end" | "stretch")?): Enum.ItemLineAlignment
	if align == "start" then
		return Enum.ItemLineAlignment.Start
	elseif align == "center" then
		return Enum.ItemLineAlignment.Center
	elseif align == "end" then
		return Enum.ItemLineAlignment.End
	elseif align == "stretch" then
		return Enum.ItemLineAlignment.Stretch
	end
	return Enum.ItemLineAlignment.Automatic
end

--- UIListLayout (LayoutOrder sort). `direction` "x"|"y" (default "y"); `gap` px; `align` = cross axis;
--- `justify` = main axis ("start"/"center"/"end" use alignment, "between"/"around"/"evenly"/"fill" use flex).
function Layout.list(options: ListOptions?): UIListLayout
	local opts: ListOptions = options or {}
	local horizontal = opts.direction == "x"
	local props: { [string]: any } = {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, opts.gap or 0),
		Wraps = opts.wraps == true,
		ItemLineAlignment = lineAlignment(opts.itemAlign),
	}
	local justify: Justify? = opts.justify
	local flexJustify = justify == "between" or justify == "around" or justify == "evenly" or justify == "fill"
	local mainAlign: Align? = if flexJustify then nil else justify :: any
	if horizontal then
		props.HorizontalAlignment = horizontalAlignment(mainAlign)
		props.VerticalAlignment = verticalAlignment(opts.align)
		props.HorizontalFlex = flexAlignment(justify)
	else
		props.VerticalAlignment = verticalAlignment(mainAlign)
		props.HorizontalAlignment = horizontalAlignment(opts.align)
		props.VerticalFlex = flexAlignment(justify)
	end
	return Create.UIListLayout(props)
end

--- UIGridLayout with px cells (Vector2) or UDim2 cells, px gap (number or Vector2).
function Layout.grid(options: GridOptions): UIGridLayout
	local cell = options.cell
	local cellSize = if typeof(cell) == "Vector2"
		then UDim2.fromOffset((cell :: Vector2).X, (cell :: Vector2).Y)
		else cell
	local gap = options.gap or 0
	local gapSize = if typeof(gap) == "Vector2"
		then UDim2.fromOffset((gap :: Vector2).X, (gap :: Vector2).Y)
		else UDim2.fromOffset(gap :: number, gap :: number)
	local props: { [string]: any } = {
		CellSize = cellSize,
		CellPadding = gapSize,
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = if options.direction == "y" then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		HorizontalAlignment = horizontalAlignment(options.align),
	}
	if options.maxCells ~= nil then
		props.FillDirectionMaxCells = options.maxCells
	end
	return Create.UIGridLayout(props)
end

--- UIFlexItem: `{ grow = 1 }` grows into free space, `{ shrink = 1 }` shrinks, `{ fill = true }` fills.
function Layout.flex(options: FlexOptions?): UIFlexItem
	local opts: FlexOptions = options or {}
	if opts.fill then
		return Create.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill })
	end
	if opts.grow == nil and opts.shrink == nil then
		return Create.UIFlexItem({ FlexMode = Enum.UIFlexMode.Grow })
	end
	return Create.UIFlexItem({
		FlexMode = Enum.UIFlexMode.Custom,
		GrowRatio = opts.grow or 0,
		ShrinkRatio = opts.shrink or 0,
	})
end

function Layout.sizeConstraint(min: Vector2?, max: Vector2?): UISizeConstraint
	return Create.UISizeConstraint({
		MinSize = min or Vector2.new(0, 0),
		MaxSize = max or Vector2.new(math.huge, math.huge),
	})
end

function Layout.aspect(ratio: number): UIAspectRatioConstraint
	return Create.UIAspectRatioConstraint({ AspectRatio = ratio })
end

--- UDim2 shortcuts.
function Layout.px(x: number, y: number): UDim2
	return UDim2.fromOffset(x, y)
end

function Layout.fill(): UDim2
	return UDim2.fromScale(1, 1)
end

--- Full width, fixed height in px.
function Layout.row(height: number): UDim2
	return UDim2.new(1, 0, 0, height)
end

--- Fixed width in px, full height.
function Layout.column(width: number): UDim2
	return UDim2.new(0, width, 1, 0)
end

return Layout
