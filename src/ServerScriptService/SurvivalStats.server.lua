local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))

-- Pradinės reikšmės
local function resetStats(player: Player)
	for statName, stat in Config.Stats do
		player:SetAttribute(statName, stat.StartValue)
	end
end

-- Šarvai sugeria žalą
local function protectWithArmor(player: Player, humanoid)
	local lastHealth = humanoid.Health

	humanoid.HealthChanged:Connect(function()
		local health = humanoid.Health
		local damage = lastHealth - health
		local armor = player:GetAttribute("Armor")

		if Config.ArmorAbsorbsDamage and damage > 0 and health > 0 and type(armor) == "number" and armor > 0 then
			local absorbed = math.min(armor, damage)
			player:SetAttribute("Armor", armor - absorbed)
			health += absorbed
			humanoid.Health = health
		end

		lastHealth = health
	end)
end

-- Naujas žaidėjas
local function onPlayerAdded(player: Player)
	resetStats(player)

	local function onCharacterAdded(character)
		if Config.ResetOnRespawn then
			resetStats(player)
		end
		protectWithArmor(player, character:WaitForChild("Humanoid"))
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Alkis ir troškulys
while true do
	local deltaTime = task.wait(Config.UpdateEverySeconds)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if humanoid and humanoid.Health > 0 then
			for statName, stat in Config.Stats do
				local value = player:GetAttribute(statName)
				if type(value) ~= "number" then
					value = stat.StartValue
				end

				if stat.SecondsToEmpty > 0 then
					value -= stat.Max / stat.SecondsToEmpty * deltaTime
				end
				value = math.clamp(value, 0, stat.Max)
				player:SetAttribute(statName, value)

				if value <= 0 and stat.DamagePerSecond > 0 then
					humanoid:TakeDamage(stat.DamagePerSecond * deltaTime)
				end
			end
		end
	end
end
