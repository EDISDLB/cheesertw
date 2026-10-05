--!strict
--[[
	LoadingBootstrap — first-frame branded loading overlay (replaced visually by the UI team later).

	Purpose:          Remove Roblox's default loading screen, show a dark full-screen overlay with "HULLDOWN" and a
	                  status line, and fade it out when Client/Main flags the LocalPlayer attribute
	                  HulldownClientReady = true.
	Dependencies:     ReplicatedFirst, Players, TweenService only (runs before ReplicatedStorage replicates, so it
	                  must not require shared modules; attribute names mirror Net/Protocol).
	State:            The overlay ScreenGui.
	Validation:       N/A.
	Error handling:   If the client never becomes ready the overlay stays and shows Main's status text (e.g. a rejoin
	                  message) so the player is never left on a blank screen.
	Performance notes: A handful of instances, one tween.

	Theme exception: this bootstrap cannot load UI/Kit/Theme yet, so its few colors are literal.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local ATTR_CLIENT_READY = "HulldownClientReady" -- keep in sync with Net/Protocol.ATTR_CLIENT_READY
local ATTR_LOADING_STATUS = "HulldownLoadingStatus" -- keep in sync with Net/Protocol.ATTR_LOADING_STATUS

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "HulldownLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(14, 16, 18)
background.BorderSizePixel = 0
background.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.45)
title.Size = UDim2.fromScale(0.8, 0.12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "HULLDOWN"
title.TextColor3 = Color3.fromRGB(226, 220, 204)
title.TextScaled = true
title.Parent = background

local sizeLimit = Instance.new("UITextSizeConstraint")
sizeLimit.MaxTextSize = 96
sizeLimit.Parent = title

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.56)
status.Size = UDim2.new(0.8, 0, 0, 28)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.Text = "Loading..."
status.TextColor3 = Color3.fromRGB(150, 150, 140)
status.TextSize = 20
status.Parent = background

gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local function refreshStatus()
	local text = player:GetAttribute(ATTR_LOADING_STATUS)
	if type(text) == "string" and text ~= "" then
		status.Text = text
	end
end

local finished = false
local function finish()
	if finished then
		return
	end
	finished = true
	local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, fade, { TextTransparency = 1 }):Play()
	local last = TweenService:Create(status, fade, { TextTransparency = 1 })
	last.Completed:Connect(function()
		gui:Destroy()
	end)
	last:Play()
end

player:GetAttributeChangedSignal(ATTR_LOADING_STATUS):Connect(refreshStatus)
player:GetAttributeChangedSignal(ATTR_CLIENT_READY):Connect(function()
	if player:GetAttribute(ATTR_CLIENT_READY) == true then
		finish()
	end
end)
refreshStatus()
if player:GetAttribute(ATTR_CLIENT_READY) == true then
	finish()
end
