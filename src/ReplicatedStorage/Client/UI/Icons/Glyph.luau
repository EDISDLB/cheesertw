--!strict
--[[
	Icons/Glyph — a tiny vector DSL that draws icons from GUI primitives on the brand 64-unit icon grid.

	Purpose:          Fallback icons before art is uploaded (brand-art §6): shapes are placed in grid units (0..64,
	                  live area 6..58) and converted to Scale UDim2s of a square canvas, so a glyph scales to any icon
	                  size. Primitives: rect / box (rotatable) / circle / ring (UIStroke, optional half-arc masks) /
	                  line / right triangles (UIGradient diagonal masks) / hexagon (3 rotated rects) / chamfered rect
	                  (strips + masked corners: octagons, plates) / chevron / arrow / text (numerals only).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme.
	State:            Per canvas: the root Frame, the px-per-unit State, a running ZIndex.
	Validation:       Coordinates are not clamped (the icon grammar is followed by the glyph authors).
	Error handling:   N/A (programming errors surface as Create errors).
	Performance notes: 3–30 Frames per glyph; strokes/text sizes are bound to the size State. Uploaded art replaces
	                  the whole glyph with one ImageLabel.
]]

local Create = require("../Kit/Create")
local State = require("../Kit/State")
local Theme = require("../Kit/Theme")

type State<T> = State.State<T>
type CanBeState<T> = State.CanBeState<T>

export type Paint = CanBeState<Color3>

export type Canvas = {
	root: Frame,
	--- Pixels per grid unit (icon size / 64).
	scale: State<number>,
	z: number,
}

--- Colours a glyph builder receives. `fg` is the tint for monochrome glyphs; `detail` draws interior marks
--- (engravings); material glyphs use highlight/base/shade.
export type Palette = {
	fg: Paint,
	detail: Paint,
	highlight: Paint,
	base: Paint,
	shade: Paint,
	ink: Paint,
	accent: Paint,
}

export type PrimitiveOptions = {
	transparency: CanBeState<number>?,
	rotation: number?,
	radius: number?,
	name: string?,
}

local Glyph = {}

Glyph.GRID = 64

local SQRT3 = math.sqrt(3)

local function u(value: number): number
	return value / Glyph.GRID
end

--- Creates a square canvas Frame of `size` px.
function Glyph.canvas(size: CanBeState<number>, name: string?): Canvas
	local sizeState: State<number> = State.of(size)
	local scale = State.Computed(function(): number
		return sizeState:get() / Glyph.GRID
	end)
	local root = Create.Frame({
		Name = name or "Glyph",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = State.Computed(function(): UDim2
			local px = sizeState:get()
			return UDim2.fromOffset(px, px)
		end),
	})
	return { root = root, scale = scale, z = 1 }
end

local function nextZ(c: Canvas): number
	c.z += 1
	return c.z
end

local function px(c: Canvas, units: number, minimum: number?): State<number>
	return State.Computed(function(): number
		return math.max(units * c.scale:get(), minimum or 0)
	end)
end

--- Axis-aligned rectangle with its top-left corner at (x, y).
function Glyph.rect(
	c: Canvas,
	x: number,
	y: number,
	w: number,
	h: number,
	paint: Paint,
	options: PrimitiveOptions?
): Frame
	local opts: PrimitiveOptions = options or {}
	local children: { Instance } = {}
	if opts.radius ~= nil and opts.radius > 0 then
		table.insert(children, Create.UICorner({ CornerRadius = UDim.new(u(opts.radius) / u(math.min(w, h)), 0) }))
	end
	return Create.Frame({
		Name = opts.name or "Rect",
		BorderSizePixel = 0,
		Position = UDim2.fromScale(u(x), u(y)),
		Size = UDim2.fromScale(u(w), u(h)),
		BackgroundColor3 = paint,
		BackgroundTransparency = opts.transparency or 0,
		Rotation = opts.rotation or 0,
		ZIndex = nextZ(c),
		Parent = c.root,
		[Create.Children] = children,
	})
end

--- Rectangle centred on (cx, cy), optionally rotated (degrees, clockwise) about its centre.
function Glyph.box(
	c: Canvas,
	cx: number,
	cy: number,
	w: number,
	h: number,
	paint: Paint,
	options: PrimitiveOptions?
): Frame
	local opts: PrimitiveOptions = options or {}
	return Create.Frame({
		Name = opts.name or "Box",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(u(cx), u(cy)),
		Size = UDim2.fromScale(u(w), u(h)),
		BackgroundColor3 = paint,
		BackgroundTransparency = opts.transparency or 0,
		Rotation = opts.rotation or 0,
		ZIndex = nextZ(c),
		Parent = c.root,
	})
end

--- Filled disc.
function Glyph.circle(c: Canvas, cx: number, cy: number, r: number, paint: Paint, options: PrimitiveOptions?): Frame
	local opts: PrimitiveOptions = options or {}
	return Create.Frame({
		Name = opts.name or "Circle",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(u(cx), u(cy)),
		Size = UDim2.fromScale(u(2 * r), u(2 * r)),
		BackgroundColor3 = paint,
		BackgroundTransparency = opts.transparency or 0,
		ZIndex = nextZ(c),
		Parent = c.root,
		[Create.Children] = { Create.UICorner({ CornerRadius = UDim.new(0.5, 0) }) },
	})
end

-- Half-plane mask (hard step) for a UIGradient: keeps the side named by `keep`.
local function halfMask(keep: "top" | "bottom" | "left" | "right"): (number, NumberSequence)
	local rotation = if keep == "top" or keep == "bottom" then 90 else 0
	local keepFirst = keep == "top" or keep == "left"
	local sequence = if keepFirst
		then NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.499, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
	return rotation, sequence
end

export type RingOptions = {
	--- Keep only one half of the ring ("top" = an arch).
	arc: ("top" | "bottom" | "left" | "right")?,
	transparency: CanBeState<number>?,
	name: string?,
}

--- Ring with OUTER radius `r` and `thickness` units (UIStroke drawn outside a disc of radius r - thickness).
function Glyph.ring(
	c: Canvas,
	cx: number,
	cy: number,
	r: number,
	thickness: number,
	paint: Paint,
	options: RingOptions?
): Frame
	local opts: RingOptions = options or {}
	local strokeChildren: { Instance } = {}
	if opts.arc ~= nil then
		local rotation, mask = halfMask(opts.arc)
		table.insert(strokeChildren, Create.UIGradient({ Rotation = rotation, Transparency = mask }))
	end
	local inner = math.max(r - thickness, 0.5)
	return Create.Frame({
		Name = opts.name or "Ring",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(u(cx), u(cy)),
		Size = UDim2.fromScale(u(2 * inner), u(2 * inner)),
		ZIndex = nextZ(c),
		Parent = c.root,
		[Create.Children] = {
			Create.UICorner({ CornerRadius = UDim.new(0.5, 0) }) :: Instance,
			Create.UIStroke({
				Color = paint,
				Thickness = px(c, thickness, 1),
				Transparency = opts.transparency or 0,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				LineJoinMode = Enum.LineJoinMode.Round,
				[Create.Children] = strokeChildren,
			}),
		},
	})
end

--- Disc cut to one half (a dome when keep = "top").
function Glyph.halfDisc(
	c: Canvas,
	cx: number,
	cy: number,
	r: number,
	keep: "top" | "bottom" | "left" | "right",
	paint: Paint
): Frame
	local rotation, mask = halfMask(keep)
	local disc = Glyph.circle(c, cx, cy, r, paint, { name = "HalfDisc" })
	Create.UIGradient({ Rotation = rotation, Transparency = mask, Parent = disc })
	return disc
end

--- Straight segment of `thickness` units between two points.
function Glyph.line(
	c: Canvas,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	thickness: number,
	paint: Paint,
	options: PrimitiveOptions?
): Frame
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	local opts: PrimitiveOptions = if options then table.clone(options) else {}
	opts.rotation = math.deg(math.atan2(dy, dx))
	opts.name = opts.name or "Line"
	-- Extend by half the thickness so joints between consecutive segments close.
	return Glyph.box(c, (x1 + x2) / 2, (y1 + y2) / 2, length + thickness * 0.5, thickness, paint, opts)
end

--- Connected segments through `points` ({ x1, y1, x2, y2, ... }).
function Glyph.polyline(c: Canvas, points: { number }, thickness: number, paint: Paint): { Frame }
	local out = {}
	for i = 1, #points - 3, 2 do
		table.insert(out, Glyph.line(c, points[i], points[i + 1], points[i + 2], points[i + 3], thickness, paint))
	end
	return out
end

export type Corner = "tl" | "tr" | "bl" | "br"

--- Right isosceles triangle filling the half of the square [x, y, size] that contains `corner` (the right angle).
function Glyph.triangle(
	c: Canvas,
	x: number,
	y: number,
	size: number,
	corner: Corner,
	paint: Paint,
	options: PrimitiveOptions?
): Frame
	local opts: PrimitiveOptions = options or {}
	-- Rotation 45 runs top-left -> bottom-right; 135 runs top-right -> bottom-left.
	local rotation = if corner == "tl" or corner == "br" then 45 else 135
	local keepFirst = corner == "tl" or corner == "tr"
	local mask = if keepFirst
		then NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.499, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
	return Create.Frame({
		Name = opts.name or ("Tri_" .. corner),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(u(x), u(y)),
		Size = UDim2.fromScale(u(size), u(size)),
		BackgroundColor3 = paint,
		BackgroundTransparency = opts.transparency or 0,
		ZIndex = nextZ(c),
		Parent = c.root,
		[Create.Children] = { Create.UIGradient({ Rotation = rotation, Transparency = mask }) },
	})
end

--- Isosceles 45° wedge pointing `direction` with its apex at (ax, ay) and `depth` units deep.
function Glyph.wedge(
	c: Canvas,
	ax: number,
	ay: number,
	depth: number,
	direction: "up" | "down" | "left" | "right",
	paint: Paint
)
	local d = depth
	if direction == "up" then
		Glyph.triangle(c, ax - d, ay, d, "br", paint)
		Glyph.triangle(c, ax, ay, d, "bl", paint)
	elseif direction == "down" then
		Glyph.triangle(c, ax - d, ay - d, d, "tr", paint)
		Glyph.triangle(c, ax, ay - d, d, "tl", paint)
	elseif direction == "left" then
		Glyph.triangle(c, ax, ay - d, d, "br", paint)
		Glyph.triangle(c, ax, ay, d, "tr", paint)
	else
		Glyph.triangle(c, ax - d, ay - d, d, "bl", paint)
		Glyph.triangle(c, ax - d, ay, d, "tl", paint)
	end
end

--- Regular hexagon with circumradius r (flat top by default; pointy top when `pointy`).
function Glyph.hexagon(c: Canvas, cx: number, cy: number, r: number, paint: Paint, pointy: boolean?): { Frame }
	local offset = if pointy then 90 else 0
	local out = {}
	for i = 0, 2 do
		table.insert(out, Glyph.box(c, cx, cy, r, r * SQRT3, paint, { rotation = offset + i * 60, name = "Hex" }))
	end
	return out
end

export type ChamferCorners = "all" | "brand" | "top" | "bottom"

--- Rectangle with 45° cut corners (cut = leg length in units). "all" with cut = w/(2+√2) gives a regular octagon.
function Glyph.chamferRect(
	c: Canvas,
	x: number,
	y: number,
	w: number,
	h: number,
	cut: number,
	paint: Paint,
	corners: ChamferCorners?,
	options: PrimitiveOptions?
)
	local which = corners or "all"
	local tl = which == "all" or which == "brand" or which == "top"
	local tr = which == "all" or which == "top"
	local bl = which == "all" or which == "bottom"
	local br = which == "all" or which == "brand" or which == "bottom"
	local s = cut
	local topCut, bottomCut = (tl or tr), (bl or br)
	local topH = if topCut then s else 0
	local bottomH = if bottomCut then s else 0
	if topCut then
		local left = if tl then s else 0
		local right = if tr then s else 0
		Glyph.rect(c, x + left, y, w - left - right, s, paint, options)
	end
	Glyph.rect(c, x, y + topH, w, h - topH - bottomH, paint, options)
	if bottomCut then
		local left = if bl then s else 0
		local right = if br then s else 0
		Glyph.rect(c, x + left, y + h - s, w - left - right, s, paint, options)
	end
	if tl then
		Glyph.triangle(c, x, y, s, "br", paint, options)
	end
	if tr then
		Glyph.triangle(c, x + w - s, y, s, "bl", paint, options)
	end
	if bl then
		Glyph.triangle(c, x, y + h - s, s, "tr", paint, options)
	end
	if br then
		Glyph.triangle(c, x + w - s, y + h - s, s, "tl", paint, options)
	end
end

--- Regular octagon with flat-to-flat diameter d centred on (cx, cy).
function Glyph.octagon(c: Canvas, cx: number, cy: number, d: number, paint: Paint)
	Glyph.chamferRect(c, cx - d / 2, cy - d / 2, d, d, d / (2 + math.sqrt(2)), paint, "all")
end

--- Open chevron (two strokes) with its apex at (cx, cy) pointing `direction`; `span` = arm reach in units.
function Glyph.chevron(
	c: Canvas,
	cx: number,
	cy: number,
	span: number,
	thickness: number,
	paint: Paint,
	direction: "up" | "down" | "left" | "right"
)
	if direction == "up" then
		Glyph.line(c, cx - span, cy + span, cx, cy, thickness, paint)
		Glyph.line(c, cx, cy, cx + span, cy + span, thickness, paint)
	elseif direction == "down" then
		Glyph.line(c, cx - span, cy - span, cx, cy, thickness, paint)
		Glyph.line(c, cx, cy, cx + span, cy - span, thickness, paint)
	elseif direction == "left" then
		Glyph.line(c, cx + span, cy - span, cx, cy, thickness, paint)
		Glyph.line(c, cx, cy, cx + span, cy + span, thickness, paint)
	else
		Glyph.line(c, cx - span, cy - span, cx, cy, thickness, paint)
		Glyph.line(c, cx, cy, cx - span, cy + span, thickness, paint)
	end
end

--- Arrow from (x1, y1) to (x2, y2) with a chevron head.
function Glyph.arrow(
	c: Canvas,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	thickness: number,
	head: number,
	paint: Paint
)
	Glyph.line(c, x1, y1, x2, y2, thickness, paint)
	local angle = math.atan2(y2 - y1, x2 - x1)
	for _, side in { -1, 1 } do
		local a = angle + math.pi + side * math.pi / 4
		Glyph.line(c, x2, y2, x2 + math.cos(a) * head, y2 + math.sin(a) * head, thickness, paint)
	end
end

--- Text drawn in the glyph (numerals and stencil letters only, per the icon grammar).
function Glyph.text(
	c: Canvas,
	text: string,
	cx: number,
	cy: number,
	height: number,
	paint: Paint,
	role: Theme.TypeRole?
): TextLabel
	return Create.TextLabel({
		Name = "Text",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(u(cx), u(cy)),
		Size = UDim2.fromScale(1, u(height)),
		Text = text,
		FontFace = Theme.font(role or "num.l"),
		TextSize = px(c, height, 6),
		TextColor3 = paint,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = nextZ(c),
		Parent = c.root,
	})
end

--- "!" mark (bar + dot) centred on (cx, cy) with total height h.
function Glyph.bang(c: Canvas, cx: number, cy: number, h: number, paint: Paint)
	local w = h * 0.22
	Glyph.box(c, cx, cy - h * 0.12, w, h * 0.62, paint, { name = "BangBar" })
	Glyph.box(c, cx, cy + h * 0.38, w, w, paint, { name = "BangDot" })
end

--- "×" mark centred on (cx, cy).
function Glyph.cross(c: Canvas, cx: number, cy: number, span: number, thickness: number, paint: Paint)
	Glyph.box(c, cx, cy, span * math.sqrt(2), thickness, paint, { rotation = 45, name = "CrossA" })
	Glyph.box(c, cx, cy, span * math.sqrt(2), thickness, paint, { rotation = -45, name = "CrossB" })
end

--- Check mark centred around (cx, cy).
function Glyph.check(c: Canvas, cx: number, cy: number, size: number, thickness: number, paint: Paint)
	local s = size / 2
	Glyph.polyline(c, { cx - s, cy, cx - s * 0.35, cy + s * 0.65, cx + s, cy - s * 0.7 }, thickness, paint)
end

return Glyph
