--[[
	MockPlayers — Players service + Player instances for headless tests.

	Purpose:          addPlayer/removePlayer with PlayerAdded/PlayerRemoving, GetPlayers, GetPlayerByUserId,
	                  LocalPlayer, Kick (records reason and removes the player), group ranks for dev-access tests.
	Dependencies:     MockInstance.
	State:            Players are children of the service; per-player `_kicked`, `_kickMessage`, `_groupRanks`.
	Validation:       Duplicate UserIds are rejected.
	Error handling:   Misuse raises descriptive errors.
	Performance notes: Test-only.
]]

local MockInstance = require("./MockInstance")

local MockPlayers = {}

MockInstance.defineClass("Player", {
	init = function(inst: any)
		rawset(inst, "_kicked", false)
		rawset(inst, "_kickMessage", nil)
		rawset(inst, "_groupRanks", {})
	end,
	methods = {
		Kick = function(self: any, message: string?)
			rawset(self, "_kicked", true)
			rawset(self, "_kickMessage", message)
			local service = rawget(self, "_parent")
			if service ~= nil and service:IsA("Players") then
				service:removePlayer(self)
			end
		end,
		GetRankInGroupAsync = function(self: any, groupId: number): number
			return rawget(self, "_groupRanks")[groupId] or 0
		end,
		setGroupRank = function(self: any, groupId: number, rank: number)
			rawget(self, "_groupRanks")[groupId] = rank
		end,
		wasKicked = function(self: any): (boolean, string?)
			return rawget(self, "_kicked"), rawget(self, "_kickMessage")
		end,
	},
})

MockInstance.defineClass("Players", {
	signals = { "PlayerAdded", "PlayerRemoving" },
	init = function(inst: any)
		rawset(inst, "_nextUserId", 1)
	end,
	methods = {
		GetPlayers = function(self: any): { any }
			local out = {}
			for _, child in self:GetChildren() do
				if child:IsA("Player") then
					table.insert(out, child)
				end
			end
			return out
		end,
		GetPlayerByUserId = function(self: any, userId: number): any
			for _, child in self:GetChildren() do
				if child:IsA("Player") and child.UserId == userId then
					return child
				end
			end
			return nil
		end,
		-- Creates a player, parents it to the service and fires PlayerAdded. props: { UserId?, Name?, DisplayName? }
		addPlayer = function(self: any, props: { [string]: any }?): any
			local p = props or {}
			local userId = p.UserId
			if userId == nil then
				userId = rawget(self, "_nextUserId")
				rawset(self, "_nextUserId", userId + 1)
			end
			if self:GetPlayerByUserId(userId) ~= nil then
				error(`MockPlayers:addPlayer: duplicate UserId {userId}`, 2)
			end
			local player = MockInstance.new("Player")
			player.UserId = userId
			player.Name = p.Name or `Player{userId}`
			player.DisplayName = p.DisplayName or player.Name
			player.AccountAge = p.AccountAge or 365
			for k, v in p do
				if k ~= "UserId" and k ~= "Name" and k ~= "DisplayName" then
					player[k] = v
				end
			end
			player.Parent = self
			self.PlayerAdded:Fire(player)
			return player
		end,
		-- Fires PlayerRemoving then unparents the player.
		removePlayer = function(self: any, player: any)
			if rawget(player, "_parent") ~= self then
				return
			end
			self.PlayerRemoving:Fire(player)
			player.Parent = nil
		end,
		-- Makes `player` the LocalPlayer (client-side tests).
		setLocalPlayer = function(self: any, player: any)
			self.LocalPlayer = player
		end,
	},
})

function MockPlayers.new(): any
	local players = MockInstance.new("Players")
	players.Name = "Players"
	return players
end

return MockPlayers
