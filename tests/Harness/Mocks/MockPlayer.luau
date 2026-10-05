--[[
	MockPlayer — standalone mock Player (not parented to the Players service).

	Purpose:          Unit tests that need a Player-shaped Instance without joining a server
	                  (`MockPlayer.new({ UserId = 5 })`). Use MockPlayers:addPlayer for join/leave flows.
	Dependencies:     MockPlayers (defines the "Player" class), MockInstance.
	State:            The created instance.
	Validation:       UserId defaults to 1.
	Error handling:   N/A.
	Performance notes: Test-only.

	Player members: UserId, Name, DisplayName, AccountAge, Kick(message), wasKicked(), GetRankInGroupAsync(groupId),
	setGroupRank(groupId, rank), attributes, IsA("Player").
]]

require("./MockPlayers") -- registers the "Player" class
local MockInstance = require("./MockInstance")

local MockPlayer = {}

function MockPlayer.new(props: { [string]: any }?): any
	local p = props or {}
	local player = MockInstance.new("Player")
	player.UserId = p.UserId or 1
	player.Name = p.Name or `Player{player.UserId}`
	player.DisplayName = p.DisplayName or player.Name
	player.AccountAge = p.AccountAge or 365
	for k, v in p do
		if k ~= "UserId" and k ~= "Name" and k ~= "DisplayName" and k ~= "AccountAge" then
			player[k] = v
		end
	end
	return player
end

return MockPlayer
