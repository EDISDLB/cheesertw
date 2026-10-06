--!strict
--[[
	Components/StatBar — one vehicle/module stat row with a magnitude bar and comparison delta.

	Purpose:          The garage/tech-tree/equipment comparison row: label (body.s, text.secondary) on the left,
	                  value (title.s, mono-width digits via Format) and a coloured delta on the right, a 4 px bar
	                  underneath. With `compare` (the previewed value), the bar shows the shared part solid and the
	                  difference as a segment in the delta tone; the tone follows `lowerIsBetter` (reload time,
	                  dispersion) so "better" is always state.success and "worse" state.danger — plus a sign
	                  (+/−) so colour is never the only cue (accessibility checklist).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Format, Kit/Layout, Components/Text, Components/Common.
	State:            Derived Computeds only.
	Validation:       max <= 0 is treated as 1; values are clamped into the bar.
	Error handling:   Non-finite values print "—" (Format.INVALID).
	Performance notes: ~8 instances per row.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Format = require("../Format")
local Layout = require("../Layout")
local Text = require("./Text")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type StatBarProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	label: CanBeState<string>,
	value: CanBeState<number>,
	--- Bar scale (the value that fills the bar).
	max: CanBeState<number>?,
	--- Previewed value to compare against `value`.
	compare: CanBeState<number?>?,
	lowerIsBetter: boolean?,
	unit: string?,
	decimals: number?,
	--- Custom value formatter (default Format.number(v, decimals) .. " " .. unit).
	format: ((value: number) -> string)?,
	--- Hide the bar (text-only row).
	bar: boolean?,
}

export type Segments = {
	--- Solid part (fraction of the bar).
	base: number,
	--- Delta segment start/end (fractions); equal when there is no difference.
	deltaStart: number,
	deltaEnd: number,
	--- compare > value.
	increase: boolean,
}

local StatBar = {}

--- Pure: bar segments for a value, optional comparison and scale.
function StatBar.segments(value: number, compare: number?, max: number): Segments
	local scale = if max > 0 and max == max then max else 1
	local function fraction(v: number): number
		if v ~= v then
			return 0
		end
		return math.clamp(v / scale, 0, 1)
	end
	local current = fraction(value)
	if compare == nil then
		return { base = current, deltaStart = current, deltaEnd = current, increase = false }
	end
	local other = fraction(compare)
	if other >= current then
		return { base = current, deltaStart = current, deltaEnd = other, increase = other > current }
	end
	return { base = other, deltaStart = other, deltaEnd = current, increase = false }
end

function StatBar.new(props: StatBarProps): Frame
	local decimals = props.decimals or 0
	local unit = props.unit
	local max: CanBeState<number> = props.max or 1
	local compare: CanBeState<number?> = props.compare or (nil :: number?)
	local function formatValue(v: number): string
		if props.format ~= nil then
			return props.format(v)
		end
		local text = Format.number(v, decimals)
		if unit ~= nil and unit ~= "" then
			text ..= " " .. unit
		end
		return text
	end
	local delta = State.Computed(function(): Format.Delta?
		local other: number? = State.get(compare)
		if other == nil then
			return nil
		end
		return Format.delta(other - State.get(props.value), {
			decimals = decimals,
			unit = unit,
			lowerIsBetter = props.lowerIsBetter,
		})
	end)
	local deltaTone = State.Computed(function(): Color3
		local d = delta:get()
		local tone: Theme.Tone = if d ~= nil then d.tone else "neutral"
		return Theme.tone(tone):get()
	end)
	local segments = State.Computed(function(): Segments
		return StatBar.segments(State.get(props.value), State.get(compare), State.get(max))
	end)
	local showBar = props.bar ~= false
	local children: { Instance } = {
		Text.new({
			Name = "Label",
			text = props.label,
			role = "body.s",
			color = "text.secondary",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(0.55, 0, 0, 20),
			truncate = true,
		}),
		Create.Frame({
			Name = "Values",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.45, 0, 0, 20),
			[Create.Children] = {
				Layout.list({ direction = "x", gap = Theme.space(2), align = "center", justify = "end" }) :: Instance,
				Text.new({
					Name = "Value",
					text = State.map(props.value, formatValue),
					role = "title.s",
					LayoutOrder = 1,
				}),
				Text.new({
					Name = "Delta",
					text = State.Computed(function(): string
						local d = delta:get()
						return if d ~= nil and d.sign ~= 0 then d.text else ""
					end),
					role = "body.s",
					color = deltaTone,
					LayoutOrder = 2,
					Visible = State.Computed(function(): boolean
						local d = delta:get()
						return d ~= nil and d.sign ~= 0
					end),
				}),
			},
		}),
	}
	if showBar then
		table.insert(
			children,
			Create.Frame({
				Name = "Bar",
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.color("bg.inset"),
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 0, 4),
				[Create.Children] = {
					Create.Frame({
						Name = "Base",
						BorderSizePixel = 0,
						BackgroundColor3 = Theme.color("accent.steel"),
						Size = State.map(segments, function(s: Segments): UDim2
							return UDim2.fromScale(s.base, 1)
						end),
						ZIndex = 2,
					}) :: Instance,
					Create.Frame({
						Name = "Delta",
						BorderSizePixel = 0,
						BackgroundColor3 = deltaTone,
						Position = State.map(segments, function(s: Segments): UDim2
							return UDim2.fromScale(s.deltaStart, 0)
						end),
						Size = State.map(segments, function(s: Segments): UDim2
							return UDim2.fromScale(s.deltaEnd - s.deltaStart, 1)
						end),
						Visible = State.map(segments, function(s: Segments): boolean
							return s.deltaEnd > s.deltaStart
						end),
						ZIndex = 3,
					}),
				},
			})
		)
	end
	local values: { [any]: any } = Common.layout(props, {}, {
		Name = "StatBar",
		Size = UDim2.new(1, 0, 0, if showBar then 32 else 20),
	})
	values.BackgroundTransparency = 1
	values[Create.Children] = children
	return Common.parent(Create.Frame(values), props)
end

return StatBar
