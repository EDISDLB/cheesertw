--!strict
--[[
	Components/CurrencyLabel — currency glyph + formatted amount, with count-up and a floating delta.

	Purpose:          Wallets in the top bar, prices on store tiles and buttons, rewards on the results screen.
	                  The glyph is tinted with the currency token; the amount is Oswald numerals, grouped ("12,400")
	                  or compact ("12.4K"). When the amount changes it counts up/down over 0.6 s (Motion.countUp;
	                  instant under reduced motion) and, with `showDelta`, floats a signed "+1,200" in success/danger
	                  for 1.2 s. `insufficient` turns the amount state.danger (prices the player cannot afford).
	                  Styles: plain, panel (bg.inset chamfered plate — header wallets).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Format, Kit/Layout, Kit/Motion, Components/Chamfer,
	                  Components/Text, Components/Common, Icons/Icon, Core/Trove.
	State:            The displayed amount Value and the running count-up per label.
	Validation:       Non-finite amounts print "—".
	Error handling:   N/A.
	Performance notes: One Heartbeat loop only while counting.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Format = require("../Format")
local Layout = require("../Layout")
local Motion = require("../Motion")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

type CanBeState<T> = State.CanBeState<T>

export type Size = "s" | "m" | "l"
export type CurrencyLabelProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	currency: Theme.Currency,
	amount: CanBeState<number>,
	size: Size?,
	style: ("plain" | "panel")?,
	--- Animate amount changes (default true).
	countUp: boolean?,
	--- Float the signed change for 1.2 s (default false).
	showDelta: boolean?,
	--- "12.4K" instead of "12,400" (default false).
	compact: boolean?,
	insufficient: CanBeState<boolean>?,
	--- Text before the amount ("×", "+").
	prefix: string?,
}

local CurrencyLabel = {}

CurrencyLabel.DELTA_HOLD = 1.2

local ROLES: { [string]: Theme.TypeRole } = { s = "title.s", m = "num.m", l = "num.l" }
local ICONS: { [string]: number } = { s = 16, m = 20, l = 28 }

--- Pure: the amount text.
function CurrencyLabel.text(amount: number, compact: boolean?, prefix: string?): string
	local body = if compact then Format.compact(amount) else Format.integer(amount)
	return (prefix or "") .. body
end

function CurrencyLabel.new(props: CurrencyLabelProps): Frame
	local size: Size = props.size or "m"
	local role: Theme.TypeRole = ROLES[size] or "num.m"
	local iconSize = ICONS[size] or 20
	local scope = Trove.new()
	local displayed = State.Value(State.peek(props.amount), { scope = scope })
	local deltaText = State.Value("", { scope = scope })
	local deltaPositive = State.Value(true, { scope = scope })
	local insufficient: CanBeState<boolean> = props.insufficient or false
	local stopCount: (() -> ())? = nil
	local stopDeltaTimer: (() -> ())? = nil
	scope:Add(function()
		if stopCount ~= nil then
			stopCount()
		end
		if stopDeltaTimer ~= nil then
			stopDeltaTimer()
		end
	end)
	local amountState: State.State<number>? = if State.isState(props.amount) then props.amount :: any else nil
	if amountState == nil then
		-- Static amount: nothing to animate.
		amountState = State.Value(State.peek(props.amount), { scope = scope })
	end
	State.observe(amountState :: State.State<number>, function(newAmount: number, oldAmount: number?)
		local from = displayed:peek()
		if stopCount ~= nil then
			stopCount()
			stopCount = nil
		end
		if props.countUp == false or from ~= from then
			displayed:set(newAmount)
		else
			stopCount = Motion.countUp(from, newAmount, function(v: number)
				displayed:set(if v == newAmount then v else math.floor(v + 0.5))
			end)
		end
		if props.showDelta and oldAmount ~= nil and newAmount ~= oldAmount then
			local change = newAmount - oldAmount
			deltaText:set(Format.signed(change))
			deltaPositive:set(change > 0)
			if stopDeltaTimer ~= nil then
				stopDeltaTimer()
			end
			local elapsed = 0
			stopDeltaTimer = Motion.loop(function(dt: number): boolean?
				elapsed += dt
				if elapsed >= CurrencyLabel.DELTA_HOLD then
					deltaText:set("")
					stopDeltaTimer = nil
					return true
				end
				return nil
			end)
		end
	end, { scope = scope })
	local content: { Instance } = {
		Layout.list({ direction = "x", gap = Theme.space(1), align = "center" }),
		Icon.new({
			key = "currency/" .. props.currency,
			size = iconSize,
			color = Theme.currency(props.currency),
			LayoutOrder = 1,
		}),
		Text.new({
			Name = "Amount",
			text = State.map(displayed, function(v: number): string
				return CurrencyLabel.text(v, props.compact, props.prefix)
			end),
			role = role,
			color = State.Computed(function(): Color3
				return if State.get(insufficient)
					then Theme.color("state.danger"):get()
					else Theme.color("text.primary"):get()
			end),
			LayoutOrder = 2,
			ZIndex = 3,
		}),
	}
	if props.showDelta then
		table.insert(
			content,
			Text.new({
				Name = "Delta",
				text = deltaText,
				role = "body.s",
				color = State.Computed(function(): Color3
					return if deltaPositive:get()
						then Theme.color("state.success"):get()
						else Theme.color("state.danger"):get()
				end),
				Visible = State.map(deltaText, function(t: string): boolean
					return t ~= ""
				end),
				LayoutOrder = 3,
				ZIndex = 3,
			})
		)
	end
	local panel = props.style == "panel"
	if panel then
		table.insert(content, Layout.padding({ x = Theme.space(2), y = Theme.space(1) }))
	end
	-- Content sits in its own auto-sized frame so the scale-sized plate does not take a list slot.
	local children: { Instance } = {
		Create.Frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 3,
			[Create.Children] = content,
		}),
	}
	if panel then
		table.insert(
			children,
			Chamfer.new({
				corners = "brand",
				size = Theme.chamfer("s"),
				fill = Theme.color("bg.inset"),
				border = Theme.color("border.subtle"),
			})
		)
	end
	local values: { [any]: any } = Common.layout(props, {}, { Name = "Currency_" .. props.currency })
	values.BackgroundTransparency = 1
	values.Size = UDim2.fromOffset(0, iconSize + (if panel then Theme.space(1) * 2 else 0))
	values.AutomaticSize = Enum.AutomaticSize.X
	values[Create.Children] = children
	values[Create.Cleanup] = scope
	return Common.parent(Create.Frame(values), props)
end

return CurrencyLabel
