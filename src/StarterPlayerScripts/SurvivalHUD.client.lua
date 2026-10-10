--[[
	SurvivalHUD — parodo žaidėjo alkio ir troškulio juostas ekrane.

	Reikšmes nustato serverio skriptas SurvivalStats (atributai "Hunger" ir "Thirst").
	Spalvos, dydžiai, vieta ir animacijos keičiami faile SurvivalConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local HUD = Config.HUD
local Look = Config.Look
local Warnings = Config.Warnings
local Animation = Config.Animation

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Ar žaidžiama telefone ar planšetėje (lietimo ekranas be klaviatūros).
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local barTweenInfo = TweenInfo.new(Animation.BarTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local pulseTweenInfo = TweenInfo.new(Animation.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- Prideda užapvalintus kampus. radius = UDim.new(0.5, 0) daro apskritimą.
local function addCorner(parent: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

-- =====================================================================
-- Pagrindinis HUD langas (panelė, kurioje sudėtos visos juostos)
-- =====================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalHUD"
screenGui.ResetOnSpawn = false -- HUD neišnyksta po mirties.

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = if isMobile then HUD.MobileAnchorPoint else HUD.AnchorPoint
panel.Position = if isMobile then HUD.MobilePosition else HUD.Position
panel.Size = UDim2.fromOffset(HUD.Width, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y -- Aukštis prisitaiko prie juostų skaičiaus.
panel.BackgroundColor3 = Look.PanelColor
panel.BackgroundTransparency = Look.PanelTransparency
panel.Parent = screenGui
addCorner(panel, UDim.new(0, HUD.CornerRadius))

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Look.StrokeColor
panelStroke.Transparency = Look.StrokeTransparency
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, HUD.Padding)
panelPadding.PaddingBottom = UDim.new(0, HUD.Padding)
panelPadding.PaddingLeft = UDim.new(0, HUD.Padding)
panelPadding.PaddingRight = UDim.new(0, HUD.Padding)
panelPadding.Parent = panel

-- Sudeda juostas vieną po kita iš viršaus į apačią.
local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, HUD.Spacing)
panelLayout.Parent = panel

-- Padidina arba sumažina visą HUD.
local panelScale = Instance.new("UIScale")
panelScale.Scale = if isMobile then HUD.MobileScale else HUD.Scale
panelScale.Parent = panel

-- =====================================================================
-- Viena eilutė: ikona + pavadinimas + procentai + juosta
-- =====================================================================
local infoHeight = HUD.TextSize + 4 + HUD.BarHeight
local rowHeight = math.max(HUD.IconSize, infoHeight)

-- Sukuria vieno rodiklio (pvz. alkio) eilutę ir grąžina jos dalis.
local function createRow(statName: string, stat)
	local row = Instance.new("Frame")
	row.Name = statName
	row.LayoutOrder = stat.Order
	row.Size = UDim2.new(1, 0, 0, rowHeight)
	row.BackgroundTransparency = 1
	row.Parent = panel

	-- Spalvotas apskritimas, kuriame yra ikona.
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.fromScale(0, 0.5)
	iconHolder.Size = UDim2.fromOffset(HUD.IconSize, HUD.IconSize)
	iconHolder.BackgroundColor3 = stat.Color
	iconHolder.BackgroundTransparency = Look.IconBackgroundTransparency
	iconHolder.Parent = row
	addCorner(iconHolder, UDim.new(0.5, 0))

	-- Šitą dydį keičia pulsavimo animacija.
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = iconHolder

	-- Ikona: savas paveikslėlis, jei nurodytas, kitaip emoji.
	if stat.IconImage ~= "" then
		local iconImage = Instance.new("ImageLabel")
		iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
		iconImage.Position = UDim2.fromScale(0.5, 0.5)
		iconImage.Size = UDim2.fromScale(0.7, 0.7)
		iconImage.BackgroundTransparency = 1
		iconImage.Image = stat.IconImage
		iconImage.ScaleType = Enum.ScaleType.Fit
		iconImage.Parent = iconHolder
	else
		local iconText = Instance.new("TextLabel")
		iconText.Size = UDim2.fromScale(1, 1)
		iconText.BackgroundTransparency = 1
		iconText.Text = stat.Icon
		iconText.TextSize = math.floor(HUD.IconSize * 0.6)
		iconText.Parent = iconHolder
	end

	-- Dešinė pusė: pavadinimas, procentai ir juosta.
	local infoLeft = HUD.IconSize + HUD.Spacing
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.AnchorPoint = Vector2.new(0, 0.5)
	info.Position = UDim2.new(0, infoLeft, 0.5, 0)
	info.Size = UDim2.new(1, -infoLeft, 0, infoHeight)
	info.BackgroundTransparency = 1
	info.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "StatName"
	nameLabel.Size = UDim2.new(1, 0, 0, HUD.TextSize)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Look.Font
	nameLabel.TextSize = HUD.TextSize
	nameLabel.TextColor3 = Look.TextColor
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = stat.DisplayName
	nameLabel.Parent = info

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.new(1, 0, 0, HUD.TextSize)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Look.Font
	valueLabel.TextSize = HUD.TextSize
	valueLabel.TextColor3 = Look.TextColor
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Visible = Look.ShowValueText
	valueLabel.Parent = info

	-- Juostos fonas (tuščia dalis).
	local barBackground = Instance.new("Frame")
	barBackground.Name = "Bar"
	barBackground.AnchorPoint = Vector2.new(0, 1)
	barBackground.Position = UDim2.fromScale(0, 1)
	barBackground.Size = UDim2.new(1, 0, 0, HUD.BarHeight)
	barBackground.BackgroundColor3 = Look.BarBackgroundColor
	barBackground.BackgroundTransparency = Look.BarBackgroundTransparency
	barBackground.Parent = info
	addCorner(barBackground, UDim.new(0.5, 0))

	-- Užpildyta juostos dalis. Jos plotis = kiek procentų liko.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = stat.Color
	fill.Parent = barBackground
	addCorner(fill, UDim.new(0.5, 0))

	-- Lengvas šešėlis: viršus šviesesnis, apačia tamsesnė.
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 185))
	fillGradient.Rotation = 90
	fillGradient.Parent = fill

	return {
		statName = statName,
		stat = stat,
		fill = fill,
		valueLabel = valueLabel,
		iconScale = iconScale,
		pulseTween = nil :: Tween?,
	}
end

-- Įjungia arba išjungia ikonos pulsavimą.
local function setPulse(row, shouldPulse: boolean)
	if shouldPulse and Animation.PulseEnabled and not row.pulseTween then
		row.pulseTween = TweenService:Create(row.iconScale, pulseTweenInfo, { Scale = Animation.PulseSize })
		row.pulseTween:Play()
	elseif not shouldPulse and row.pulseTween then
		row.pulseTween:Cancel()
		row.pulseTween = nil
		row.iconScale.Scale = 1
	end
end

-- Atnaujina vieną eilutę pagal žaidėjo atributą (pvz. "Hunger").
local function updateRow(row, instant: boolean)
	local value = player:GetAttribute(row.statName)
	if type(value) ~= "number" then
		value = row.stat.Max -- Kol serveris dar nenustatė reikšmės, rodome pilną juostą.
	end

	local percent = math.clamp(value / row.stat.Max, 0, 1) * 100

	-- Parenka spalvą pagal tai, kiek liko.
	local barColor = row.stat.Color
	local textColor = Look.TextColor
	local isCritical = percent <= Warnings.CriticalPercent
	if isCritical then
		barColor = Warnings.CriticalColor
		textColor = Warnings.CriticalColor
	elseif percent <= Warnings.WarningPercent then
		barColor = Warnings.WarningColor
	end

	local goal = {
		Size = UDim2.fromScale(percent / 100, 1),
		BackgroundColor3 = barColor,
	}
	if instant then
		row.fill.Size = goal.Size
		row.fill.BackgroundColor3 = goal.BackgroundColor3
	else
		TweenService:Create(row.fill, barTweenInfo, goal):Play()
	end

	row.valueLabel.Text = math.ceil(percent) .. "%"
	row.valueLabel.TextColor3 = textColor
	setPulse(row, isCritical)
end

-- =====================================================================
-- Sukuria eilutes ir seka reikšmių pokyčius
-- =====================================================================
for statName, stat in Config.Stats do
	local row = createRow(statName, stat)
	updateRow(row, true)

	player:GetAttributeChangedSignal(statName):Connect(function()
		updateRow(row, false)
	end)
end

screenGui.Parent = playerGui
