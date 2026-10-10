--[[
	SurvivalHUD — apvalūs gyvybės, šarvų, alkio ir troškulio rodikliai (GTA stiliaus).
	Rodomi apačioje kairėje ekrano pusėje.

	Gyvybė imama iš Humanoid, kiti rodikliai — iš žaidėjo atributų (juos nustato SurvivalStats).
	Spalvos, dydžiai, vieta ir animacijos keičiami faile SurvivalConfig.

	HUD galima perkelti iš bet kurio skripto (plačiau README.md):
		player:SetAttribute("HUDAnchorPoint", Vector2.new(1, 1))
		player:SetAttribute("HUDPosition", UDim2.new(1, -16, 1, -16))
	Grąžinti į vietą iš SurvivalConfig:
		player:SetAttribute("HUDAnchorPoint", nil)
		player:SetAttribute("HUDPosition", nil)
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

local ringTweenInfo = TweenInfo.new(Animation.RingTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local moveTweenInfo = TweenInfo.new(Animation.MoveTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local pulseTweenInfo = TweenInfo.new(Animation.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- Gradientas, kuris pusę apskritimo palieka matomą, o kitą pusę paslepia.
-- Sukant jį (Rotation) žiedas pasipildo arba ištuštėja.
local HALF_VISIBLE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local FULL_ROUND = UDim.new(0.5, 0) -- Kampų apvalumas, kuris daro apskritimą.

-- =====================================================================
-- Pagalbinės funkcijos
-- =====================================================================

-- Sukuria spalvotą stačiakampį. x ir y — kiek pikselių nuo tėvo centro, rotation — pasukimas laipsniais.
local function newShape(parent: Instance, width: number, height: number, x: number, y: number, color: Color3, rotation: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, x, 0.5, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.Rotation = rotation or 0
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- Užapvalina kampus.
local function round(frame: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = frame
end

-- =====================================================================
-- Baltos ikonos, nupieštos iš paprastų formų (nereikia įkelti paveikslėlių)
-- =====================================================================
local IconShapes = {}

-- Širdis: pasuktas kvadratas ir du apskritimai viršuje.
function IconShapes.Heart(box: Frame, size: number, color: Color3)
	local side = size / 1.71
	local shift = side * 0.07 -- Kad širdis būtų per vidurį.
	newShape(box, side, side, 0, shift, color, 45)
	round(newShape(box, side, side, -side * 0.354, shift - side * 0.354, color), FULL_ROUND)
	round(newShape(box, side, side, side * 0.354, shift - side * 0.354, color), FULL_ROUND)
end

-- Skydas: viršus su apvaliais kampais ir smailus galas apačioje (pasuktas kvadratas).
function IconShapes.Shield(box: Frame, size: number, color: Color3)
	local width = size * 0.8
	local height = size * 0.95
	local bodyHeight = height - width / 2
	local top = -height / 2
	round(newShape(box, width, bodyHeight, 0, top + bodyHeight / 2, color), UDim.new(0, width * 0.3))
	newShape(box, width, bodyHeight / 2, 0, top + bodyHeight * 0.75, color) -- Apačia be apvalių kampų.
	newShape(box, width / math.sqrt(2), width / math.sqrt(2), 0, top + bodyHeight, color, 45)
end

-- Mėsainis: apvali viršutinė bandelė, kotletas ir apatinė bandelė.
function IconShapes.Burger(box: Frame, size: number, color: Color3)
	local width = size * 0.9
	local bunHeight = size * 0.36

	-- Viršutinė bandelė: matoma tik viršutinė apvalios formos pusė.
	local bunTop = newShape(box, width, bunHeight, 0, -size * 0.25, color)
	bunTop.BackgroundTransparency = 1
	bunTop.ClipsDescendants = true
	local dome = Instance.new("Frame")
	dome.Size = UDim2.fromScale(1, 2)
	dome.BackgroundColor3 = color
	dome.BorderSizePixel = 0
	dome.Parent = bunTop
	round(dome, FULL_ROUND)

	round(newShape(box, width, size * 0.16, 0, size * 0.07, color), FULL_ROUND)
	round(newShape(box, width, size * 0.22, 0, size * 0.32, color), UDim.new(0.3, 0))
end

-- Lašas: apskritimas ir pasuktas kvadratas viršuje (smailus galas).
function IconShapes.Drop(box: Frame, size: number, color: Color3)
	local radius = size * 0.39
	local centerY = radius * 0.207 -- Kad lašas būtų per vidurį.
	round(newShape(box, radius * 2, radius * 2, 0, centerY, color), FULL_ROUND)
	newShape(box, radius, radius, 0, centerY - radius * 0.707, color, 45)
end

-- Įdeda ikoną į apskritimo vidurį: savą paveikslėlį, nupieštą formą arba emoji.
local function createIcon(parent: Instance, circleConfig)
	local box = Instance.new("Frame")
	box.Name = "Icon"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(HUD.IconSize, HUD.IconSize)
	box.BackgroundTransparency = 1
	box.ZIndex = 4
	box.Parent = parent

	if circleConfig.IconImage and circleConfig.IconImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = circleConfig.IconImage
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = box
	elseif IconShapes[circleConfig.Icon] then
		IconShapes[circleConfig.Icon](box, HUD.IconSize, Look.IconColor)
	else
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = circleConfig.Icon
		text.TextScaled = true
		text.Parent = box
	end
end

-- =====================================================================
-- HUD langas ir apskritimų stulpelis
-- =====================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalHUD"
screenGui.ResetOnSpawn = false -- HUD neišnyksta po mirties.
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local container = Instance.new("Frame")
container.Name = "StatusCircles"
container.Size = UDim2.fromOffset(0, 0)
container.AutomaticSize = Enum.AutomaticSize.XY -- Dydis prisitaiko prie apskritimų skaičiaus.
container.BackgroundTransparency = 1
container.Parent = screenGui

-- Sudeda apskritimus vieną po kito.
local layout = Instance.new("UIListLayout")
layout.FillDirection = if HUD.Layout == "Horizontal" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, HUD.Spacing)
layout.Parent = container

-- Padidina arba sumažina visą HUD.
local containerScale = Instance.new("UIScale")
containerScale.Scale = if isMobile then HUD.MobileScale else HUD.Scale
containerScale.Parent = container

-- Grąžina HUD vietą: iš atributų (jei skriptas ją pakeitė), kitaip iš SurvivalConfig.
local function getHUDPlacement()
	local anchorPoint = player:GetAttribute("HUDAnchorPoint")
	local position = player:GetAttribute("HUDPosition")
	if typeof(anchorPoint) ~= "Vector2" then
		anchorPoint = if isMobile then HUD.MobileAnchorPoint else HUD.AnchorPoint
	end
	if typeof(position) ~= "UDim2" then
		position = if isMobile then HUD.MobilePosition else HUD.Position
	end
	return anchorPoint, position
end

-- Padeda HUD į vietą. instant = true — iškart, be animacijos.
local function placeHUD(instant: boolean)
	local anchorPoint, position = getHUDPlacement()
	if instant then
		container.AnchorPoint = anchorPoint
		container.Position = position
	else
		TweenService:Create(container, moveTweenInfo, { AnchorPoint = anchorPoint, Position = position }):Play()
	end
end

-- =====================================================================
-- Vienas apskritimas: tamsus pagrindas, spalvotas žiedas ir ikona
-- =====================================================================
local function createCircle(circleConfig, order: number)
	local ringSize = HUD.CircleSize - HUD.RingInset * 2
	local innerSize = ringSize - HUD.RingThickness * 2

	-- Nematoma vieta sąraše, kad pulsavimas nestumdytų kitų apskritimų.
	local slot = Instance.new("Frame")
	slot.Name = circleConfig.Stat
	slot.LayoutOrder = order
	slot.Size = UDim2.fromOffset(HUD.CircleSize, HUD.CircleSize)
	slot.BackgroundTransparency = 1
	slot.Parent = container

	-- Tamsus apskritimas — visų dalių pagrindas.
	local base = newShape(slot, HUD.CircleSize, HUD.CircleSize, 0, 0, Look.BackgroundColor)
	base.Name = "Circle"
	round(base, FULL_ROUND)

	-- Pulsavimas keičia šitą dydį.
	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = base

	-- Blanki žiedo dalis (tuščia vieta).
	local track = newShape(base, ringSize, ringSize, 0, 0, circleConfig.Color)
	track.Name = "Track"
	track.BackgroundTransparency = Look.TrackTransparency
	track.ZIndex = 1
	round(track, FULL_ROUND)

	-- Spalvotas žiedas iš dviejų pusių: dešinė rodo 0–50 %, kairė 50–100 %.
	local function createHalf(side: string)
		local half = Instance.new("Frame")
		half.Name = side .. "Half"
		half.AnchorPoint = Vector2.new(if side == "Right" then 0 else 1, 0.5)
		half.Position = UDim2.fromScale(0.5, 0.5)
		half.Size = UDim2.fromOffset(ringSize / 2, ringSize)
		half.BackgroundTransparency = 1
		half.ClipsDescendants = true -- Rodo tik savo pusę.
		half.ZIndex = 2
		half.Parent = base

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Position = UDim2.fromScale(if side == "Right" then -1 else 0, 0)
		fill.Size = UDim2.fromScale(2, 1)
		fill.BackgroundColor3 = circleConfig.Color
		fill.BorderSizePixel = 0
		fill.Parent = half
		round(fill, FULL_ROUND)

		local gradient = Instance.new("UIGradient")
		gradient.Transparency = HALF_VISIBLE
		gradient.Parent = fill
		return fill, gradient
	end
	local rightFill, rightGradient = createHalf("Right")
	local leftFill, leftGradient = createHalf("Left")

	-- Vidinis apskritimas uždengia centrą, todėl matosi tik žiedas.
	local innerColor = Look.BackgroundColor:Lerp(circleConfig.Color, Look.BackgroundTint)
	local inner = newShape(base, innerSize, innerSize, 0, 0, innerColor)
	inner.Name = "Inner"
	inner.ZIndex = 3
	round(inner, FULL_ROUND)

	createIcon(base, circleConfig)

	-- Pasuka žiedo puses taip, kad žiedas būtų užpildytas percent procentų (pagal laikrodžio rodyklę nuo viršaus).
	local function showProgress(percent: number)
		local angle = percent / 100 * 360
		rightGradient.Rotation = math.clamp(angle, 0, 180)
		leftGradient.Rotation = math.clamp(angle, 180, 360)
	end
	showProgress(0)

	-- Žiedo užpildymas (0–100). Animuojame šitą skaičių, o žiedas pasisuka pagal jį.
	local progress = Instance.new("NumberValue")
	progress.Name = "Progress"
	progress.Changed:Connect(showProgress)
	progress.Parent = slot

	return {
		config = circleConfig,
		fills = { rightFill, leftFill },
		progress = progress,
		pulseScale = pulseScale,
		pulseTween = nil :: Tween?,
	}
end

-- =====================================================================
-- Reikšmių skaitymas ir atnaujinimas
-- =====================================================================
local currentHumanoid = nil -- Dabartinio personažo Humanoid (iš jo imama gyvybė).

-- Grąžina, kiek procentų (0–100) liko rodiklio.
local function getPercent(stat: string): number
	local value, max
	if stat == "Health" then
		if not currentHumanoid then
			return 100 -- Kol personažas dar neatsirado, rodome pilną.
		end
		value, max = currentHumanoid.Health, currentHumanoid.MaxHealth
	else
		local statConfig = Config.Stats[stat]
		value = player:GetAttribute(stat)
		if type(value) ~= "number" then
			value = statConfig.StartValue -- Kol serveris dar nenustatė reikšmės.
		end
		max = statConfig.Max
	end

	if max <= 0 then
		return 0
	end
	return math.clamp(value / max, 0, 1) * 100
end

-- Įjungia arba išjungia apskritimo pulsavimą.
local function setPulse(circle, shouldPulse: boolean)
	if shouldPulse and Animation.PulseEnabled and not circle.pulseTween then
		circle.pulseTween = TweenService:Create(circle.pulseScale, pulseTweenInfo, { Scale = Animation.PulseSize })
		circle.pulseTween:Play()
	elseif not shouldPulse and circle.pulseTween then
		circle.pulseTween:Cancel()
		circle.pulseTween = nil
		circle.pulseScale.Scale = 1
	end
end

-- Atnaujina apskritimą: žiedo ilgį, spalvą ir pulsavimą.
local function updateCircle(circle, instant: boolean)
	local percent = getPercent(circle.config.Stat)

	-- Parenka spalvą pagal tai, kiek liko.
	local color = circle.config.Color
	local isCritical = false
	if circle.config.Warnings then
		if percent <= Warnings.CriticalPercent then
			color = Warnings.CriticalColor
			isCritical = true
		elseif percent <= Warnings.WarningPercent then
			color = Warnings.WarningColor
		end
	end

	if instant then
		circle.progress.Value = percent
		for _, fill in circle.fills do
			fill.BackgroundColor3 = color
		end
	else
		TweenService:Create(circle.progress, ringTweenInfo, { Value = percent }):Play()
		for _, fill in circle.fills do
			TweenService:Create(fill, ringTweenInfo, { BackgroundColor3 = color }):Play()
		end
	end

	setPulse(circle, isCritical)
end

-- =====================================================================
-- Sukuria apskritimus ir seka pokyčius
-- =====================================================================
local circles = {}
for order, circleConfig in Config.Circles do
	if circleConfig.Stat == "Health" or Config.Stats[circleConfig.Stat] then
		local circle = createCircle(circleConfig, order)
		table.insert(circles, circle)
		updateCircle(circle, true)

		if circleConfig.Stat ~= "Health" then
			player:GetAttributeChangedSignal(circleConfig.Stat):Connect(function()
				updateCircle(circle, false)
			end)
		end
	else
		warn("SurvivalHUD: nežinomas rodiklis '" .. tostring(circleConfig.Stat) .. "'. Patikrink SurvivalConfig.Circles.")
	end
end

-- Atnaujina gyvybės apskritimą.
local function updateHealth()
	for _, circle in circles do
		if circle.config.Stat == "Health" then
			updateCircle(circle, false)
		end
	end
end

-- Kai atsiranda naujas personažas (ir po atgimimo), sekame jo gyvybę.
local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	currentHumanoid = humanoid
	updateHealth()

	humanoid.HealthChanged:Connect(function()
		if humanoid == currentHumanoid then
			updateHealth()
		end
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if humanoid == currentHumanoid then
			updateHealth()
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

-- HUD vieta: pradžioje iš SurvivalConfig, vėliau ją gali keisti kiti skriptai per atributus.
placeHUD(true)
player:GetAttributeChangedSignal("HUDPosition"):Connect(function()
	placeHUD(false)
end)
player:GetAttributeChangedSignal("HUDAnchorPoint"):Connect(function()
	placeHUD(false)
end)

screenGui.Parent = playerGui
