--!strict
--[[
	ClientBootstrap — tiny client entry point (ARCHITECTURE §2).

	Purpose:          Wait for the DataModel to load, then hand over to ReplicatedStorage/Client/Main.
	Dependencies:     Client/Main.
	State:            None.
	Validation:       N/A.
	Error handling:   Main.start reports failures through the loading screen status and returns an error Result.
	Performance notes: Runs once.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Main = require("@game/ReplicatedStorage/Client/Main")

Main.start()
