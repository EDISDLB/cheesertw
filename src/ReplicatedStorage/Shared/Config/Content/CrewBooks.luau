--!strict
--[[
	Content/CrewBooks — Crew books (00-DECISIONS §12): Booklet 5,000 XP (credits), Guide 25,000 (missions/pass), Manual 60,000 (events).

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: xpPerMember > 0; prices valid.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  { id = "crew_booklet", name = "Crew Booklet", description = "+5,000 crew XP to every member.",
	  icon = "crew/book_booklet", xpPerMember = 5000, price = { credits = 60000 } }
]]

local Content = require("../../Types/Content")

local crewBooks: { Content.CrewBookDefinition } = {}

return crewBooks
