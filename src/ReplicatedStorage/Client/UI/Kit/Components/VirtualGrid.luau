--!strict
--[[
	Components/VirtualGrid — windowed grid (see Components/VirtualList for the engine and the windowing math).

	Purpose:          `VirtualGrid.new({ items, cell = Vector2.new(220, 140), gap = 12, render = ... })` returns the
	                  ScrollingFrame and a controller; columns fit the width (vertical) or rows fit the height
	                  (horizontal), only the visible rows + overscan exist, slots are pooled and re-bound.
	Dependencies:     Components/VirtualList.
	State:            See VirtualList.
	Validation:       cell must be a positive Vector2.
	Error handling:   See VirtualList.
	Performance notes: See VirtualList.
]]

local VirtualList = require("./VirtualList")

export type VirtualGridProps = VirtualList.VirtualGridProps
export type Controller = VirtualList.Controller

local VirtualGrid = {}

function VirtualGrid.new(props: VirtualGridProps): (ScrollingFrame, Controller)
	return VirtualList.grid(props)
end

VirtualGrid.lanesFor = VirtualList.lanesFor
VirtualGrid.cellOf = VirtualList.cellOf
VirtualGrid.itemRange = VirtualList.itemRange

return VirtualGrid
