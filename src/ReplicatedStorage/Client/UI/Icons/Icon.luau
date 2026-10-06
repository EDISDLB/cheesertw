--!strict
--[[
	Icons/Icon — the Icon component: uploaded art when available, otherwise a primitive glyph or category badge.

	Purpose:          `Icon.new({ key = "classes/heavy", size = 24, color = Theme.color("team.ally") })` returns a
	                  square Frame. The key resolves through Shared/Assets/AssetResolver: an uploaded id renders one
	                  ImageLabel (tinted with `color` when given — monochrome art is white for tinting), a dedicated
	                  glyph renders from Icons/Registry, anything else renders the generic category badge. Key, size
	                  and colour may be States; the content rebuilds when the key changes.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Icons/Glyph, Icons/Registry, Shared/Assets/AssetResolver.
	State:            The resolver in use (default shared resolver; swappable for tests/gallery).
	Validation:       Keys are validated by AssetResolver (malformed keys warn once and draw the badge).
	Error handling:   A failing glyph builder logs and falls back to the badge.
	Performance notes: Uploaded art = 1 ImageLabel; glyphs = 3–30 Frames. Prefer uploaded art in long lists.
]]

local Create = require("../Kit/Create")
local State = require("../Kit/State")
local Theme = require("../Kit/Theme")
local Glyph = require("./Glyph")
local Registry = require("./Registry")
local AssetResolver = require("@game/ReplicatedStorage/Shared/Assets/AssetResolver")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

type CanBeState<T> = State.CanBeState<T>
type State<T> = State.State<T>

export type IconProps = {
	key: CanBeState<string>,
	--- Square size in px (default 24).
	size: CanBeState<number>?,
	--- Tint: monochrome glyphs and uploaded (white) art; multi-tone glyphs keep their materials unless given.
	color: CanBeState<Color3>?,
	transparency: CanBeState<number>?,
	--- Always draw the glyph/badge, even if art is uploaded (gallery comparisons).
	forceGlyph: boolean?,
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: Vector2?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
}

local log = Log.scope("UI.Icon")

local Icon = {}

local resolver: AssetResolver.Resolver = AssetResolver.default()

--- Uses a different resolver (tests, gallery previews of an upload manifest).
function Icon.setResolver(newResolver: AssetResolver.Resolver?)
	resolver = newResolver or AssetResolver.default()
end

function Icon.resolver(): AssetResolver.Resolver
	return resolver
end

local WHITE = Color3.new(1, 1, 1)

local function shadeOf(color: Color3): Color3
	return color:Lerp(Theme.ink, 0.45)
end

local function highlightOf(color: Color3): Color3
	return color:Lerp(WHITE, 0.45)
end

--- Builds the palette for an entry: material colours, or a tint with derived shade/highlight.
function Icon.palette(entry: Registry.Entry, color: CanBeState<Color3>?): Glyph.Palette
	local accent = Theme.color("accent.dusk")
	if color == nil and entry.material ~= nil then
		local material = Theme.material(entry.material)
		return {
			fg = material.base,
			detail = material.shade,
			highlight = material.highlight,
			base = material.base,
			shade = material.shade,
			ink = Theme.ink,
			accent = accent,
		}
	end
	local fg: CanBeState<Color3> = color or Theme.color((entry.color or "text.primary") :: any)
	return {
		fg = fg,
		detail = Theme.ink,
		highlight = State.map(fg, highlightOf),
		base = fg,
		shade = State.map(fg, shadeOf),
		ink = Theme.ink,
		accent = accent,
	}
end

local function categoryColor(key: string): string
	local category = AssetResolver.categoryOf(key)
	return (category and (Registry.CATEGORY_COLORS :: any)[category]) or "text.secondary"
end

--- Draws the glyph (or badge) for `key` without consulting the asset manifest.
function Icon.glyph(key: string, size: CanBeState<number>?, color: CanBeState<Color3>?): Frame
	local entry = Registry.get(key)
	local isBadge = entry == nil
	local chosen: Registry.Entry = entry or Registry.badge
	local canvas = Glyph.canvas(size or 24, if isBadge then "Badge" else "Glyph")
	local tint = color
	if isBadge and tint == nil then
		tint = Theme.color(categoryColor(key) :: any)
	end
	local ok, err = pcall(chosen.build :: any, canvas, Icon.palette(chosen, tint))
	if not ok then
		log:error("glyph %s failed: %s", key, tostring(err))
		canvas.root:ClearAllChildren()
		Registry.badge.build(canvas, Icon.palette(Registry.badge, tint))
	end
	canvas.root:SetAttribute("IconKey", key)
	return canvas.root
end

local function buildContent(key: string, props: IconProps): GuiObject
	local resolution = if props.forceGlyph then nil else resolver:resolveImage(key)
	if resolution ~= nil and resolution.kind == "image" then
		local entry = resolution.entry
		local image = Create.ImageLabel({
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = resolution.id,
			ImageColor3 = props.color or WHITE,
			ImageTransparency = props.transparency or 0,
			ScaleType = Enum.ScaleType.Fit,
		})
		if entry ~= nil and entry.rectSize ~= nil then
			image.ImageRectSize = entry.rectSize
			image.ImageRectOffset = entry.rectOffset or Vector2.new(0, 0)
		end
		image:SetAttribute("IconKey", key)
		return image
	end
	local root = Icon.glyph(key, props.size, props.color)
	root.Size = UDim2.fromScale(1, 1)
	return root
end

--- The Icon component (square Frame).
function Icon.new(props: IconProps): Frame
	local sizeState: State<number> = State.of(props.size or 24)
	local content = State.Computed(function(): GuiObject
		local key = State.get(props.key)
		return State.untracked(function(): GuiObject
			return buildContent(key, props)
		end)
	end, {
		cleanup = function(old: GuiObject)
			old:Destroy()
		end,
	})
	local frame = Create.Frame({
		Name = props.Name or "Icon",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = State.Computed(function(): UDim2
			local px = sizeState:get()
			return UDim2.fromOffset(px, px)
		end),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = if props.Visible == nil then true else props.Visible,
		[Create.Children] = content,
		[Create.Cleanup] = content,
	})
	if props.Parent ~= nil then
		frame.Parent = props.Parent
	end
	return frame
end

--- True if `key` has a dedicated glyph.
function Icon.has(key: string): boolean
	return Registry.has(key)
end

--- All glyph keys (sorted).
function Icon.keys(): { string }
	return Registry.keys()
end

--- Registers a feature glyph and declares it to the resolver (so it counts as a fallback).
function Icon.register(key: string, entry: Registry.Entry)
	Registry.register(key, entry)
	resolver:declareGlyph(key)
end

return Icon
