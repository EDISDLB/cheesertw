local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local HUDSettings = require(ReplicatedStorage:WaitForChild("HUDSettings"))

-- Ryšys su žaidėju
local remote = Instance.new("RemoteEvent")
remote.Name = "HUDEditorEvent"
remote.Parent = ReplicatedStorage

-- Duomenų saugykla
local store = nil
local warned = false
local pending = {}

local function storeWarning(message)
	if not warned then
		warned = true
		warn("HUD nustatymai neišsaugomi: " .. tostring(message))
	end
end

if Config.Editor.SaveSettings then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("HUDSettings_v1")
	end)
	if ok then
		store = result
	else
		storeWarning(result)
	end
end

-- Įkelia nustatymus
local function loadSettings(player: Player)
	if not store then
		return
	end
	local ok, json = pcall(function()
		return store:GetAsync("user_" .. player.UserId)
	end)
	if not ok then
		storeWarning(json)
	elseif type(json) == "string" and player.Parent then
		player:SetAttribute("HUDSettings", HUDSettings.encode(HUDSettings.decode(json)))
	end
end

-- Išsaugo nustatymus
local function saveSettings(player: Player)
	local json = pending[player]
	pending[player] = nil
	if not json or not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("user_" .. player.UserId, json)
	end)
	if not ok then
		storeWarning(err)
	end
end

-- Žaidėjas paspaudė išsaugoti
remote.OnServerEvent:Connect(function(player, action, json)
	if action ~= "Save" or type(json) ~= "string" or #json > 3000 then
		return
	end
	local clean = HUDSettings.encode(HUDSettings.decode(json))
	player:SetAttribute("HUDSettings", clean)
	pending[player] = clean
end)

-- Komanda pokalbyje
local command = Instance.new("TextChatCommand")
command.Name = "HUDEditorCommand"
command.PrimaryAlias = Config.Editor.ChatCommand
command.Parent = TextChatService
command.Triggered:Connect(function(textSource)
	local player = Players:GetPlayerByUserId(textSource.UserId)
	if player then
		remote:FireClient(player, "Open")
	end
end)

Players.PlayerAdded:Connect(loadSettings)
for _, player in Players:GetPlayers() do
	task.spawn(loadSettings, player)
end

Players.PlayerRemoving:Connect(saveSettings)
game:BindToClose(function()
	for player in pending do
		saveSettings(player)
	end
end)

-- Saugo kas 10 s
while true do
	task.wait(10)
	for player in pending do
		task.spawn(saveSettings, player)
	end
end
