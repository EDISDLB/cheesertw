--!strict
--[[
	Components/Icon — re-export of Icons/Icon so screens import every component from Kit/Components.

	Purpose:          `local Icon = require("@game/ReplicatedStorage/Client/UI/Kit/Components/Icon")` is the same
	                  module as Client/UI/Icons/Icon (uploaded art -> glyph -> category badge).
	Dependencies:     Icons/Icon.
	State:            None.
	Validation:       See Icons/Icon.
	Error handling:   See Icons/Icon.
	Performance notes: N/A.
]]

local Icon = require("../../Icons/Icon")

export type IconProps = Icon.IconProps

return Icon
