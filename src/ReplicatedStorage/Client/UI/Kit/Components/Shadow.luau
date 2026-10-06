--!strict
--[[
	Components/Shadow — the single elevation shadow (brand-art §8.2: ink 45 %, offset 0/4 px, 12 px soft).

	Purpose:          Approximates a soft shadow with three stacked ink Frames of growing spread and transparency
	                  behind modals and dropdowns only ("panels on panels have no shadow, only bevel lines").
	Dependencies:     Kit/Create, Kit/Theme.
	State:            None.
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: 3 Frames with UICorner; never use on list rows.
]]

local Create = require("../Create")
local Theme = require("../Theme")

local Shadow = {}

--- Shadow layers sized to the parent (put it first, with a lower ZIndex than the surface).
export type ShadowProps = { zIndex: number?, offsetY: number?, name: string? }

function Shadow.new(props: ShadowProps?): Frame
	local opts: ShadowProps = props or {}
	local offsetY = opts.offsetY or Theme.shadow.offsetY
	local z = opts.zIndex or 0
	local layers: { Instance } = {}
	local specs: { { spread: number, transparency: number } } = {
		{ spread = 2, transparency = 0.8 },
		{ spread = 6, transparency = 0.88 },
		{ spread = 12, transparency = 0.93 },
	}
	for i, spec in specs do
		table.insert(
			layers,
			Create.Frame({
				Name = "Layer" .. i,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, offsetY),
				Size = UDim2.new(1, spec.spread * 2, 1, spec.spread * 2),
				BackgroundColor3 = Theme.ink,
				BackgroundTransparency = spec.transparency,
				ZIndex = z,
				[Create.Children] = { Create.UICorner({ CornerRadius = UDim.new(0, 4 + spec.spread) }) },
			})
		)
	end
	return Create.Frame({
		Name = opts.name or "Shadow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		[Create.Children] = layers,
	})
end

return Shadow
