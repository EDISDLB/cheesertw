--!strict
--[[
	Components/Badge — small status marks: tier numeral, vehicle class, premium/elite, NEW, counters, text tags.

	Purpose:          One component for the marks that sit on cards, tabs and list rows:
	                    tier    — the tier glyph (band material + numeral, Icons "tiers/tier_NN");
	                    class   — the class silhouette glyph, tinted bone, bullion (premium) or dusk_hi (elite);
	                    premium — a bullion plate "PREMIUM" (or "P" when `compact`);
	                    new     — a dusk plate "NEW";
	                    count   — a counter pill (hidden at 0, "99+" above 99);
	                    text    — a plate with any short text in a tone colour.
	                  Plates are 4 px-chamfered, Oswald "badge" role, text.inverse on the fill colour.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Format, Kit/Layout, Components/Chamfer, Components/Text,
	                  Components/Common, Icons/Icon.
	State:            None.
	Validation:       Unknown kinds raise; tiers are clamped to 1..11.
	Error handling:   N/A.
	Performance notes: Plates ~8 Frames + 1 label; glyph badges reuse Icon.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Format = require("../Format")
local Layout = require("../Layout")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type Kind = "tier" | "class" | "premium" | "new" | "count" | "text"
export type VehicleClass = "light" | "medium" | "heavy" | "td" | "artillery"
export type BadgeProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	kind: Kind,
	tier: CanBeState<number>?,
	class: CanBeState<VehicleClass>?,
	--- class: premium (bullion tint) / elite (dusk tint) vehicles.
	premium: CanBeState<boolean>?,
	elite: CanBeState<boolean>?,
	count: CanBeState<number>?,
	text: CanBeState<string>?,
	tone: Theme.Tone?,
	--- Badge height in px (default 20; glyph badges are square).
	size: number?,
	--- premium: "P" instead of "PREMIUM".
	compact: boolean?,
}

local Badge = {}

--- Pure: counter text ("" hides the badge; "99+" above 99).
function Badge.countText(count: number): string
	if count ~= count or count <= 0 then
		return ""
	elseif count > 99 then
		return "99+"
	end
	return tostring(math.floor(count))
end

--- Pure: icon key for a tier (clamped 1..11).
function Badge.tierKey(tier: number): string
	local n = math.clamp(math.floor(tier), 1, 11)
	return string.format("tiers/tier_%02d", n)
end

local function plate(props: BadgeProps, text: CanBeState<string>, fill: CanBeState<Color3>, height: number): Frame
	local values: { [any]: any } = Common.layout(props, {}, { Name = "Badge" })
	values.BackgroundTransparency = 1
	values.Size = UDim2.fromOffset(height, height)
	values.AutomaticSize = Enum.AutomaticSize.X
	values[Create.Children] = {
		Chamfer.new({ corners = "brand", size = Theme.chamfer("s"), fill = fill }) :: Instance,
		Layout.padding({ x = 6 }),
		Create.UISizeConstraint({ MinSize = Vector2.new(height, height) }),
		Text.new({
			Name = "Label",
			text = text,
			role = "badge",
			color = "text.inverse",
			align = "center",
			Size = UDim2.new(0, 0, 1, 0),
			autoSize = "x",
			ZIndex = 3,
		}),
	}
	return Create.Frame(values)
end

--- Builds a badge.
function Badge.new(props: BadgeProps): GuiObject
	local height = props.size or 20
	local kind = props.kind
	local result: GuiObject
	if kind == "tier" then
		local tier = props.tier or 1
		result = Icon.new({
			key = State.map(tier, Badge.tierKey),
			size = math.max(height, 24),
			Name = props.Name or "TierBadge",
			Position = props.Position,
			AnchorPoint = State.peek(props.AnchorPoint or Vector2.new(0, 0)),
			LayoutOrder = props.LayoutOrder,
			ZIndex = props.ZIndex,
			Visible = props.Visible,
		})
		result:SetAttribute("BadgeKind", "tier")
	elseif kind == "class" then
		local class = props.class or "medium"
		local premium = props.premium or false
		local elite = props.elite or false
		result = Icon.new({
			key = State.map(class, function(c: VehicleClass): string
				return "classes/" .. c
			end),
			size = math.max(height, 20),
			color = State.Computed(function(): Color3
				if State.get(premium) then
					return Theme.color("currency.bullion"):get()
				elseif State.get(elite) then
					return Theme.color("accent.dusk_hi"):get()
				end
				return Theme.color("brand.bone"):get()
			end),
			Name = props.Name or "ClassBadge",
			Position = props.Position,
			AnchorPoint = State.peek(props.AnchorPoint or Vector2.new(0, 0)),
			LayoutOrder = props.LayoutOrder,
			ZIndex = props.ZIndex,
			Visible = props.Visible,
		})
		result:SetAttribute("BadgeKind", "class")
	elseif kind == "premium" then
		result = plate(props, if props.compact then "P" else "PREMIUM", Theme.color("currency.bullion"), height)
	elseif kind == "new" then
		result = plate(props, "NEW", Theme.color("accent.dusk"), height)
	elseif kind == "count" then
		local count = props.count or 0
		local text = State.map(count, Badge.countText)
		result = plate(props, text, Theme.color("accent.dusk"), math.max(height, Theme.sizes.badgeMin))
		local visible: CanBeState<boolean> = State.Computed(function(): boolean
			return State.get(text) ~= "" and (props.Visible == nil or State.get(props.Visible))
		end)
		Create.apply(result, { Visible = visible })
	elseif kind == "text" then
		local tone: Theme.Tone = props.tone or "neutral"
		local fill = if tone == "neutral" then Theme.color("accent.steel") else Theme.tone(tone)
		result = plate(props, props.text or "", fill, height)
	else
		error(`Badge: unknown kind "{tostring(kind)}"`, 2)
	end
	if result:GetAttribute("BadgeKind") == nil then
		result:SetAttribute("BadgeKind", kind)
	end
	return Common.parent(result, props)
end

--- Shortcut: tier glyph badge.
function Badge.tier(tier: CanBeState<number>, props: BadgeProps?): GuiObject
	local merged: BadgeProps = if props then table.clone(props) else { kind = "tier" }
	merged.kind = "tier"
	merged.tier = tier
	return Badge.new(merged)
end

--- Format helper re-exported for list rows that print tiers as text ("VIII").
Badge.tierText = Format.tier

return Badge
