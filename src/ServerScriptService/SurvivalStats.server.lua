--[[
	SurvivalStats — serveryje mažina žaidėjų alkį ir troškulį.

	Reikšmės saugomos kaip žaidėjo atributai "Hunger" ir "Thirst".
	HUD (SurvivalHUD) juos skaito automatiškai.
	Visi skaičiai (greitis, žala, maksimumas) yra faile SurvivalConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))

-- Užpildo visus rodiklius iki maksimumo.
local function fillStats(player: Player)
	for statName, stat in Config.Stats do
		player:SetAttribute(statName, stat.Max)
	end
end

-- Paruošia naują žaidėją.
local function onPlayerAdded(player: Player)
	fillStats(player)

	player.CharacterAdded:Connect(function()
		if Config.ResetOnRespawn then
			fillStats(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Kas kelias sekundes sumažina rodiklius ir atima gyvybę, jei jie tušti.
while true do
	local deltaTime = task.wait(Config.UpdateEverySeconds)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		-- Mirusiems ir dar neatsiradusiems žaidėjams rodikliai nemažėja.
		if humanoid and humanoid.Health > 0 then
			for statName, stat in Config.Stats do
				local value = player:GetAttribute(statName)
				if type(value) ~= "number" then
					value = stat.Max
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
