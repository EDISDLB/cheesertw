--!strict
--[[
	Components/Chamfer — the "HULLDOWN cut": chamfered (45°) surfaces built from GUI primitives.

	Purpose:          brand-art §6.4/§8.2 want 45° chamfers (8 px on the top-left and bottom-right of panels and CTAs)
	                  instead of rounded corners, drawn as 9-slices in the final art. Until 9-slice images are
	                  uploaded this module draws the exact polygon with plain Frames:
	                    * fill  = top strip + middle + bottom strip (non-overlapping, so translucent fills stay even)
	                              + one right triangle per cut corner: a square Frame whose UIGradient transparency has a
	                              hard step at 0.5 along the diagonal (Rotation 45/135), i.e. a gradient MASK;
	                    * border = four edge Frames + one rotated Frame per cut corner (length s·√2);
	                    * bevel = 1 px inner top highlight (border.bevel_hi at 35 %) and bottom shadow (border.bevel_lo);
	                    * a vertical two-colour fill (primary CTA) is approximated per strip: strips take the gradient
	                      colour at their position, the middle strip carries a UIGradient between them.
	                  Everything is positioned with UDim2 scale+offset, so the shape follows any Size (also as a
	                  SelectionImageObject template).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme.
	State:            None (returns instances; bindings live with them).
	Validation:       Chamfer size is clamped to >= 0; unknown corner sets raise.
	Error handling:   Raises on invalid props (build time).
	Performance notes: 3–13 Frames per surface. Keep it on containers, never on high-churn text (GuiEffect cost,
	                  research 09 §2.3). Swap to a 9-slice ImageLabel per surface once art is uploaded (one instance).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")

type CanBeState<T> = State.CanBeState<T>

export type Corners = "brand" | "all" | "none" | "top" | "bottom"
export type ChamferProps = {
	--- Cut size in px (default Theme chamfer "m" = 8).
	size: number?,
	--- "brand" = top-left + bottom-right (HULLDOWN cut, default); "all"; "none"; "top" (TL+TR); "bottom" (BL+BR).
	corners: Corners?,
	fill: CanBeState<Color3>?,
	fillTransparency: CanBeState<number>?,
	--- Vertical two-colour fill (overrides `fill`). nominalHeight = the surface height in px used to place stops.
	gradient: { top: Color3, bottom: Color3, nominalHeight: number }?,
	border: CanBeState<Color3>?,
	borderThickness: CanBeState<number>?,
	borderTransparency: CanBeState<number>?,
	--- Inner bevel lines (raised metal look).
	bevel: boolean?,
	zIndex: number?,
	name: string?,
}

local Chamfer = {}

local SQRT2 = math.sqrt(2)

type CornerSizes = { tl: number, tr: number, bl: number, br: number }

function Chamfer.cornerSizes(corners: Corners, size: number): CornerSizes
	local s = math.max(size, 0)
	if corners == "brand" then
		return { tl = s, tr = 0, bl = 0, br = s }
	elseif corners == "all" then
		return { tl = s, tr = s, bl = s, br = s }
	elseif corners == "top" then
		return { tl = s, tr = s, bl = 0, br = 0 }
	elseif corners == "bottom" then
		return { tl = 0, tr = 0, bl = s, br = s }
	elseif corners == "none" then
		return { tl = 0, tr = 0, bl = 0, br = 0 }
	end
	error(`Chamfer: unknown corners "{tostring(corners)}"`, 3)
end

-- Transparency mask with a hard step on the diagonal: `visibleAfter` shows t > 0.5, else t < 0.5.
local function diagonalMask(visibleAfter: boolean): NumberSequence
	if visibleAfter then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.501, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Corner triangle (the visible part is the half inside the polygon).
local function triangle(
	corner: "tl" | "tr" | "bl" | "br",
	s: number,
	color: CanBeState<Color3>,
	transparency: CanBeState<number>,
	zIndex: number
): Frame
	local position, rotation, visibleAfter
	if corner == "tl" then
		position, rotation, visibleAfter = UDim2.new(0, 0, 0, 0), 45, true
	elseif corner == "tr" then
		position, rotation, visibleAfter = UDim2.new(1, -s, 0, 0), 135, true
	elseif corner == "br" then
		position, rotation, visibleAfter = UDim2.new(1, -s, 1, -s), 45, false
	else
		position, rotation, visibleAfter = UDim2.new(0, 0, 1, -s), 135, false
	end
	return Create.Frame({
		Name = "Corner_" .. corner,
		BorderSizePixel = 0,
		Position = position,
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		ZIndex = zIndex,
		[Create.Children] = {
			Create.UIGradient({ Rotation = rotation, Transparency = diagonalMask(visibleAfter) }),
		},
	})
end

local function piece(
	name: string,
	position: UDim2,
	size: UDim2,
	color: CanBeState<Color3>,
	transparency: CanBeState<number>,
	zIndex: number
): Frame
	return Create.Frame({
		Name = name,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		ZIndex = zIndex,
	})
end

--- Fill pieces for the chamfered polygon (parent them into a transparent container).
function Chamfer.fillPieces(props: ChamferProps): { Instance }
	local sizes = Chamfer.cornerSizes(props.corners or "brand", props.size or Theme.chamfer("m"))
	local z = props.zIndex or 1
	local transparency: CanBeState<number> = props.fillTransparency or 0
	local s = math.max(sizes.tl, sizes.tr, sizes.bl, sizes.br)
	local topColor: CanBeState<Color3>, midColor: CanBeState<Color3>, bottomColor: CanBeState<Color3>
	local midGradient: UIGradient? = nil
	local gradient = props.gradient
	if gradient ~= nil then
		local h = math.max(gradient.nominalHeight, 2 * s + 1)
		local a, b = s / h, 1 - s / h
		topColor = gradient.top:Lerp(gradient.bottom, a / 2)
		bottomColor = gradient.top:Lerp(gradient.bottom, (1 + b) / 2)
		midColor = Color3.new(1, 1, 1)
		midGradient = Create.UIGradient({
			Rotation = 90,
			Color = ColorSequence.new(gradient.top:Lerp(gradient.bottom, a), gradient.top:Lerp(gradient.bottom, b)),
		})
	else
		local fill: CanBeState<Color3> = props.fill or Theme.color("bg.panel")
		topColor, midColor, bottomColor = fill, fill, fill
	end
	local pieces: { Instance } = {}
	local topH = math.max(sizes.tl, sizes.tr)
	local bottomH = math.max(sizes.bl, sizes.br)
	if topH > 0 then
		table.insert(
			pieces,
			piece(
				"FillTop",
				UDim2.new(0, sizes.tl, 0, 0),
				UDim2.new(1, -(sizes.tl + sizes.tr), 0, topH),
				topColor,
				transparency,
				z
			)
		)
	end
	local middle =
		piece("FillMiddle", UDim2.new(0, 0, 0, topH), UDim2.new(1, 0, 1, -(topH + bottomH)), midColor, transparency, z)
	if midGradient ~= nil then
		midGradient.Parent = middle
	end
	table.insert(pieces, middle)
	if bottomH > 0 then
		table.insert(
			pieces,
			piece(
				"FillBottom",
				UDim2.new(0, sizes.bl, 1, -bottomH),
				UDim2.new(1, -(sizes.bl + sizes.br), 0, bottomH),
				bottomColor,
				transparency,
				z
			)
		)
	end
	-- Corner triangles (an uncut corner is covered by its strip, which then starts/ends at the edge).
	local cornerColors = { tl = topColor, tr = topColor, bl = bottomColor, br = bottomColor }
	for _, corner in { "tl", "tr", "bl", "br" } do
		local cut = (sizes :: any)[corner] :: number
		if cut > 0 then
			table.insert(pieces, triangle(corner :: any, cut, (cornerColors :: any)[corner], transparency, z))
		end
	end
	return pieces
end

--- Border pieces (edges + diagonal cut lines) and optional bevel lines.
function Chamfer.borderPieces(props: ChamferProps): { Instance }
	local sizes = Chamfer.cornerSizes(props.corners or "brand", props.size or Theme.chamfer("m"))
	local z = (props.zIndex or 1) + 1
	local color: CanBeState<Color3> = props.border or Theme.color("border.subtle")
	local transparency: CanBeState<number> = props.borderTransparency or 0
	local thicknessState: CanBeState<number> = props.borderThickness or 1
	local t = State.peek(thicknessState)
	local pieces: { Instance } = {}
	local function edge(name: string, position: UDim2, size: UDim2)
		table.insert(pieces, piece(name, position, size, color, transparency, z))
	end
	edge("EdgeTop", UDim2.new(0, sizes.tl, 0, 0), UDim2.new(1, -(sizes.tl + sizes.tr), 0, t))
	edge("EdgeBottom", UDim2.new(0, sizes.bl, 1, -t), UDim2.new(1, -(sizes.bl + sizes.br), 0, t))
	edge("EdgeLeft", UDim2.new(0, 0, 0, sizes.tl), UDim2.new(0, t, 1, -(sizes.tl + sizes.bl)))
	edge("EdgeRight", UDim2.new(1, -t, 0, sizes.tr), UDim2.new(0, t, 1, -(sizes.tr + sizes.br)))
	local diagonals = {
		{ corner = "tl", cut = sizes.tl, position = UDim2.new(0, sizes.tl / 2, 0, sizes.tl / 2), rotation = -45 },
		{ corner = "tr", cut = sizes.tr, position = UDim2.new(1, -sizes.tr / 2, 0, sizes.tr / 2), rotation = 45 },
		{ corner = "br", cut = sizes.br, position = UDim2.new(1, -sizes.br / 2, 1, -sizes.br / 2), rotation = -45 },
		{ corner = "bl", cut = sizes.bl, position = UDim2.new(0, sizes.bl / 2, 1, -sizes.bl / 2), rotation = 45 },
	}
	for _, diagonal in diagonals do
		if diagonal.cut > 0 then
			table.insert(
				pieces,
				Create.Frame({
					Name = "Cut_" .. diagonal.corner,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = diagonal.position,
					Size = UDim2.fromOffset(diagonal.cut * SQRT2 + t, t),
					Rotation = diagonal.rotation,
					BackgroundColor3 = color,
					BackgroundTransparency = transparency,
					ZIndex = z,
				})
			)
		end
	end
	if props.bevel then
		table.insert(
			pieces,
			piece(
				"BevelTop",
				UDim2.new(0, sizes.tl, 0, t),
				UDim2.new(1, -(sizes.tl + sizes.tr), 0, 1),
				Theme.color("border.bevel_hi"),
				0.65,
				z
			)
		)
		table.insert(
			pieces,
			piece(
				"BevelBottom",
				UDim2.new(0, sizes.bl, 1, -(t + 1)),
				UDim2.new(1, -(sizes.bl + sizes.br), 0, 1),
				Theme.color("border.bevel_lo"),
				0,
				z
			)
		)
	end
	return pieces
end

--- A full-size transparent Frame holding the chamfered fill and (optional) border. Put it first inside a
--- transparent container and give content a higher ZIndex.
function Chamfer.new(props: ChamferProps): Frame
	local children: { Instance } = {}
	if props.fill ~= nil or props.gradient ~= nil then
		for _, item in Chamfer.fillPieces(props) do
			table.insert(children, item)
		end
	end
	if props.border ~= nil or props.bevel then
		for _, item in Chamfer.borderPieces(props) do
			table.insert(children, item)
		end
	end
	return Create.Frame({
		Name = props.name or "Surface",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = props.zIndex or 1,
		Active = false,
		[Create.Children] = children,
	})
end

return Chamfer
