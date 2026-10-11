local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local HUDSettings = require(ReplicatedStorage:WaitForChild("HUDSettings"))
local Look = Config.Look
local Warnings = Config.Warnings
local Animation = Config.Animation

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ringTweenInfo = TweenInfo.new(Animation.RingTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local pulseTweenInfo = TweenInfo.new(Animation.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local HALF_VISIBLE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local FULL_ROUND = UDim.new(0.5, 0)
local NAME_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

-- Pagalbinės funkcijos

local function newFrame(parent: Instance, name: string, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function newShape(parent: Instance, width: number, height: number, x: number, y: number, color: Color3, rotation: number?): Frame
	local frame = newFrame(parent, "Shape", color, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, x, 0.5, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.Rotation = rotation or 0
	return frame
end

local function round(frame: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = frame
end

local function newText(parent: Instance, name: string, text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(0, size + 4)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Look.Font
	label.TextSize = size
	label.TextColor3 = color
	label.RichText = true
	label.Text = text
	label.Parent = parent
	return label
end

local function newList(parent: Instance, direction: Enum.FillDirection, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

local function padding(parent: Instance, vertical: number, horizontal: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, vertical)
	pad.PaddingBottom = UDim.new(0, vertical)
	pad.PaddingLeft = UDim.new(0, horizontal)
	pad.PaddingRight = UDim.new(0, horizontal)
	pad.Parent = parent
end

local function toUDim2(position): UDim2
	return UDim2.new(position[1], position[2], position[3], position[4])
end

-- Ikonos

local IconShapes = {}

function IconShapes.Heart(box: Frame, size: number, color: Color3)
	local side = size / 1.71
	local shift = side * 0.07
	newShape(box, side, side, 0, shift, color, 45)
	round(newShape(box, side, side, -side * 0.354, shift - side * 0.354, color), FULL_ROUND)
	round(newShape(box, side, side, side * 0.354, shift - side * 0.354, color), FULL_ROUND)
end

function IconShapes.Shield(box: Frame, size: number, color: Color3)
	local width = size * 0.8
	local height = size * 0.95
	local bodyHeight = height - width / 2
	local top = -height / 2
	round(newShape(box, width, bodyHeight, 0, top + bodyHeight / 2, color), UDim.new(0, width * 0.3))
	newShape(box, width, bodyHeight / 2, 0, top + bodyHeight * 0.75, color)
	newShape(box, width / math.sqrt(2), width / math.sqrt(2), 0, top + bodyHeight, color, 45)
end

function IconShapes.Burger(box: Frame, size: number, color: Color3)
	local width = size * 0.9
	local bunTop = newShape(box, width, size * 0.36, 0, -size * 0.25, color)
	bunTop.BackgroundTransparency = 1
	bunTop.ClipsDescendants = true
	local dome = newFrame(bunTop, "Dome", color, 0)
	dome.Size = UDim2.fromScale(1, 2)
	round(dome, FULL_ROUND)
	round(newShape(box, width, size * 0.16, 0, size * 0.07, color), FULL_ROUND)
	round(newShape(box, width, size * 0.22, 0, size * 0.32, color), UDim.new(0.3, 0))
end

function IconShapes.Drop(box: Frame, size: number, color: Color3)
	local radius = size * 0.39
	local centerY = radius * 0.207
	round(newShape(box, radius * 2, radius * 2, 0, centerY, color), FULL_ROUND)
	newShape(box, radius, radius, 0, centerY - radius * 0.707, color, 45)
end

local function createIcon(parent: Instance, circleConfig, size: number, y: number?)
	local box = Instance.new("Frame")
	box.Name = "Icon"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.new(0.5, 0, 0.5, y or 0)
	box.Size = UDim2.fromOffset(size, size)
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
		IconShapes[circleConfig.Icon](box, size, Look.IconColor)
	else
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = circleConfig.Icon
		text.TextScaled = true
		text.Parent = box
	end
end

-- Pagrindinis langas

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function newRoot(name: string, anchorPoint: Vector2): (Frame, UIScale)
	local root = Instance.new("Frame")
	root.Name = name
	root.AnchorPoint = anchorPoint
	root.Size = UDim2.fromOffset(0, 0)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.BackgroundTransparency = 1
	root.Parent = screenGui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	return root, scale
end

local statusRoot, statusScale = newRoot("Status", Vector2.new(0, 1))
local infoRoot, infoScale = newRoot("Info", Vector2.new(1, 0))
local speedRoot, speedScale = newRoot("Speedometer", Vector2.new(1, 1))

-- Būklės ikonos

local statusContent = nil
local statusWidgets = {}
local currentHumanoid = nil

-- Apskritimas
local function buildCircle(parent: Instance, circleConfig, thickness: number)
	local size = 44
	local ringSize = size - 4
	local innerSize = math.max(ringSize - thickness * 2, 8)

	local slot = newFrame(parent, circleConfig.Stat, Color3.new(), 1)
	slot.Size = UDim2.fromOffset(size, size)

	local base = newShape(slot, size, size, 0, 0, Look.BackgroundColor)
	base.Name = "Circle"
	round(base, FULL_ROUND)
	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = base

	local track = newShape(base, ringSize, ringSize, 0, 0, circleConfig.Color)
	track.Name = "Track"
	track.BackgroundTransparency = Look.TrackTransparency
	track.ZIndex = 1
	round(track, FULL_ROUND)

	local function createHalf(side: string)
		local half = newFrame(base, side .. "Half", Color3.new(), 1)
		half.AnchorPoint = Vector2.new(if side == "Right" then 0 else 1, 0.5)
		half.Position = UDim2.fromScale(0.5, 0.5)
		half.Size = UDim2.fromOffset(ringSize / 2, ringSize)
		half.ClipsDescendants = true
		half.ZIndex = 2

		local fill = newFrame(half, "Fill", circleConfig.Color, 0)
		fill.Position = UDim2.fromScale(if side == "Right" then -1 else 0, 0)
		fill.Size = UDim2.fromScale(2, 1)
		round(fill, FULL_ROUND)

		local gradient = Instance.new("UIGradient")
		gradient.Transparency = HALF_VISIBLE
		gradient.Parent = fill
		return fill, gradient
	end
	local rightFill, rightGradient = createHalf("Right")
	local leftFill, leftGradient = createHalf("Left")

	local inner = newShape(base, innerSize, innerSize, 0, 0, Look.BackgroundColor:Lerp(circleConfig.Color, Look.BackgroundTint))
	inner.Name = "Inner"
	inner.ZIndex = 3
	round(inner, FULL_ROUND)

	createIcon(base, circleConfig, 20)

	local progress = Instance.new("NumberValue")
	progress.Changed:Connect(function(percent)
		local angle = percent / 100 * 360
		rightGradient.Rotation = math.clamp(angle, 0, 180)
		leftGradient.Rotation = math.clamp(angle, 180, 360)
	end)
	rightGradient.Rotation = 0
	leftGradient.Rotation = 180

	return { slot = slot, progress = progress, colorTargets = { rightFill, leftFill }, pulseScale = pulseScale }
end

-- Juosta
local function buildBar(parent: Instance, circleConfig, thickness: number)
	local row = newFrame(parent, circleConfig.Stat, Look.BackgroundColor, Look.BackgroundTransparency)
	row.Size = UDim2.fromOffset(170, 32)
	round(row, FULL_ROUND)

	local iconHolder = newShape(row, 26, 26, -170 / 2 + 16, 0, Look.BackgroundColor:Lerp(circleConfig.Color, 0.35))
	iconHolder.Name = "Circle"
	round(iconHolder, FULL_ROUND)
	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = iconHolder
	createIcon(iconHolder, circleConfig, 14)

	local barHeight = thickness + 2
	local barBack = newFrame(row, "Bar", Color3.new(1, 1, 1), 0.85)
	barBack.AnchorPoint = Vector2.new(0, 0.5)
	barBack.Position = UDim2.new(0, 36, 0.5, 0)
	barBack.Size = UDim2.new(1, -36 - 46, 0, barHeight)
	round(barBack, FULL_ROUND)

	local fill = newFrame(barBack, "Fill", circleConfig.Color, 0)
	fill.Size = UDim2.fromScale(1, 1)
	round(fill, FULL_ROUND)

	local value = newText(row, "Value", "100%", 12, Look.IconColor)
	value.AnchorPoint = Vector2.new(1, 0.5)
	value.Position = UDim2.new(1, -12, 0.5, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right

	local progress = Instance.new("NumberValue")
	progress.Changed:Connect(function(percent)
		fill.Size = UDim2.fromScale(percent / 100, 1)
		value.Text = math.ceil(percent) .. "%"
	end)

	return { slot = row, progress = progress, colorTargets = { fill }, pulseScale = pulseScale }
end

-- Kvadratas
local function buildSquare(parent: Instance, circleConfig, thickness: number)
	local size = 46
	local slot = newFrame(parent, circleConfig.Stat, Color3.new(), 1)
	slot.Size = UDim2.fromOffset(size, size)

	local tile = newShape(slot, size, size, 0, 0, Look.BackgroundColor:Lerp(circleConfig.Color, Look.BackgroundTint))
	tile.Name = "Circle"
	tile.BackgroundTransparency = 0.25
	round(tile, UDim.new(0, 8))
	local pulseScale = Instance.new("UIScale")
	pulseScale.Parent = tile

	createIcon(tile, circleConfig, 18, -thickness / 2 - 2)

	local barBack = newFrame(tile, "Bar", Color3.new(1, 1, 1), 0.85)
	barBack.AnchorPoint = Vector2.new(0.5, 1)
	barBack.Position = UDim2.new(0.5, 0, 1, -5)
	barBack.Size = UDim2.new(1, -12, 0, thickness)
	round(barBack, FULL_ROUND)

	local fill = newFrame(barBack, "Fill", circleConfig.Color, 0)
	fill.Size = UDim2.fromScale(1, 1)
	round(fill, FULL_ROUND)

	local progress = Instance.new("NumberValue")
	progress.Changed:Connect(function(percent)
		fill.Size = UDim2.fromScale(percent / 100, 1)
	end)

	return { slot = slot, progress = progress, colorTargets = { fill }, pulseScale = pulseScale }
end

local builders = { Circles = buildCircle, Bars = buildBar, Squares = buildSquare }

-- Kiek procentų liko
local function getPercent(stat: string): number
	local value, max
	if stat == "Health" then
		if not currentHumanoid then
			return 100
		end
		value, max = currentHumanoid.Health, currentHumanoid.MaxHealth
	else
		local statConfig = Config.Stats[stat]
		value = player:GetAttribute(stat)
		if type(value) ~= "number" then
			value = statConfig.StartValue
		end
		max = statConfig.Max
	end
	if max <= 0 then
		return 0
	end
	return math.clamp(value / max, 0, 1) * 100
end

-- Pulsavimas
local function setPulse(widget, shouldPulse: boolean)
	if shouldPulse and Animation.PulseEnabled and not widget.pulseTween then
		widget.pulseTween = TweenService:Create(widget.pulseScale, pulseTweenInfo, { Scale = Animation.PulseSize })
		widget.pulseTween:Play()
	elseif not shouldPulse and widget.pulseTween then
		widget.pulseTween:Cancel()
		widget.pulseTween = nil
		widget.pulseScale.Scale = 1
	end
end

-- Atnaujina ikoną
local function updateWidget(widget, instant: boolean)
	local percent = getPercent(widget.config.Stat)
	local color = widget.config.Color
	local isCritical = false
	if widget.config.Warnings then
		if percent <= Warnings.CriticalPercent then
			color = Warnings.CriticalColor
			isCritical = true
		elseif percent <= Warnings.WarningPercent then
			color = Warnings.WarningColor
		end
	end

	if instant then
		widget.progress.Value = percent
		for _, target in widget.colorTargets do
			target.BackgroundColor3 = color
		end
	else
		TweenService:Create(widget.progress, ringTweenInfo, { Value = percent }):Play()
		for _, target in widget.colorTargets do
			TweenService:Create(target, ringTweenInfo, { BackgroundColor3 = color }):Play()
		end
	end
	setPulse(widget, isCritical)
end

local function updateStat(stat: string)
	for _, widget in statusWidgets do
		if widget.config.Stat == stat then
			updateWidget(widget, false)
		end
	end
end

-- Sukuria būklės ikonas
local function buildStatus(statusSettings)
	for _, widget in statusWidgets do
		setPulse(widget, false)
	end
	statusWidgets = {}
	if statusContent then
		statusContent:Destroy()
	end

	local isSquares = statusSettings.Style == "Squares"
	statusContent = newFrame(statusRoot, "Content", Look.BackgroundColor, if isSquares then Look.BackgroundTransparency else 1)
	statusContent.Size = UDim2.fromOffset(0, 0)
	statusContent.AutomaticSize = Enum.AutomaticSize.XY
	local direction = if statusSettings.Layout == "Horizontal" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	newList(statusContent, direction, if isSquares then 6 else 8)
	if isSquares then
		round(statusContent, UDim.new(0, 12))
		padding(statusContent, 8, 8)
	end

	for order, circleConfig in Config.Circles do
		if circleConfig.Stat == "Health" or Config.Stats[circleConfig.Stat] then
			local widget = builders[statusSettings.Style](statusContent, circleConfig, statusSettings.Thickness)
			widget.config = circleConfig
			widget.slot.LayoutOrder = order
			table.insert(statusWidgets, widget)
			updateWidget(widget, true)
		else
			warn("SurvivalHUD: nežinomas rodiklis " .. tostring(circleConfig.Stat))
		end
	end
end

for statName in Config.Stats do
	player:GetAttributeChangedSignal(statName):Connect(function()
		updateStat(statName)
	end)
end

-- Informacijos juosta

local timeLabel, onlineLabel = nil, nil

local function updateInfoText()
	if timeLabel then
		timeLabel.Text = os.date("%Y.%m.%d  %H:%M")
		onlineLabel.Text = string.format('<font color="#9aa3b2">%s</font>  <b>%d</b>', Config.OnlineText, #Players:GetPlayers())
	end
end

local function buildInfo()
	local bar = newFrame(infoRoot, "Content", Look.BackgroundColor, Look.BackgroundTransparency)
	bar.Size = UDim2.fromOffset(0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.XY
	round(bar, UDim.new(0, 10))
	padding(bar, 6, 14)
	newList(bar, Enum.FillDirection.Horizontal, 16)

	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new(0.55, 0)
	fade.Parent = bar

	timeLabel = newText(bar, "Time", "", 14, Look.IconColor)
	timeLabel.LayoutOrder = 1
	onlineLabel = newText(bar, "Online", "", 14, Look.IconColor)
	onlineLabel.LayoutOrder = 2

	local nameLabel = newText(bar, "ServerName", Config.ServerName, 28, Config.ServerNameColor)
	nameLabel.LayoutOrder = 3
	nameLabel.RichText = false
	nameLabel.FontFace = NAME_FONT
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.7
	stroke.Parent = nameLabel

	updateInfoText()
end

buildInfo()
Players.PlayerAdded:Connect(updateInfoText)
Players.PlayerRemoving:Connect(function()
	task.defer(updateInfoText)
end)
task.spawn(function()
	while true do
		updateInfoText()
		task.wait(1)
	end
end)

-- Spidometras

local speedContent = nil
local speedWidget = nil
local speedConnection = nil

local function speedText(speed: number): string
	local digits = string.format("%03d", math.clamp(math.floor(speed + 0.5), 0, 999))
	local zeros = string.match(digits, "^0*") or ""
	if #zeros == 3 then
		zeros = "00"
	end
	return string.format('<font color="#5c616b">%s</font>%s', zeros, string.sub(digits, #zeros + 1))
end

-- Kuro ar variklio eilutė
local function buildMeter(parent: Instance, name: string, label: string, order: number)
	local row = newFrame(parent, name, Color3.new(), 1)
	row.Size = UDim2.fromOffset(0, 16)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.LayoutOrder = order
	newList(row, Enum.FillDirection.Horizontal, 8)

	local caption = newText(row, "Label", label, 11, Color3.fromRGB(170, 176, 188))
	caption.AutomaticSize = Enum.AutomaticSize.None
	caption.Size = UDim2.fromOffset(62, 16)
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.LayoutOrder = 1
	local back = newFrame(row, "Bar", Color3.new(1, 1, 1), 0.85)
	back.Size = UDim2.fromOffset(110, 6)
	back.LayoutOrder = 2
	round(back, FULL_ROUND)
	local fill = newFrame(back, "Fill", Look.AccentColor, 0)
	fill.Size = UDim2.fromScale(1, 1)
	round(fill, FULL_ROUND)
	local value = newText(row, "Value", "100%", 11, Look.IconColor)
	value.AutomaticSize = Enum.AutomaticSize.None
	value.Size = UDim2.fromOffset(34, 16)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.LayoutOrder = 3

	return function(percent: number?)
		row.Visible = percent ~= nil
		if percent then
			fill.Size = UDim2.fromScale(math.clamp(percent, 0, 100) / 100, 1)
			value.Text = math.floor(percent + 0.5) .. "%"
		end
	end
end

-- Apvalus spidometras
local function buildRound(parent: Instance)
	local dial = newFrame(parent, "Dial", Look.BackgroundColor, Look.BackgroundTransparency)
	dial.Size = UDim2.fromOffset(180, 180)
	round(dial, FULL_ROUND)

	local segments = {}
	local count = 36
	for i = 1, count do
		local angle = 225 + (i - 1) / (count - 1) * 270
		local radians = math.rad(angle)
		local segment = newShape(dial, 4, 12, math.sin(radians) * 74, -math.cos(radians) * 74, Color3.new(1, 1, 1), angle)
		segment.BackgroundTransparency = 0.8
		round(segment, UDim.new(0, 2))
		segments[i] = segment
	end

	local speed = newText(dial, "Speed", speedText(0), 42, Look.IconColor)
	speed.AnchorPoint = Vector2.new(0.5, 0.5)
	speed.Position = UDim2.new(0.5, 0, 0.5, -8)
	local unit = newText(dial, "Unit", Config.Speedometer.Unit, 12, Color3.fromRGB(170, 176, 188))
	unit.AnchorPoint = Vector2.new(0.5, 0.5)
	unit.Position = UDim2.new(0.5, 0, 0.5, 20)

	local fuelBack = newFrame(dial, "Fuel", Color3.new(1, 1, 1), 0.85)
	fuelBack.AnchorPoint = Vector2.new(0.5, 0.5)
	fuelBack.Position = UDim2.new(0.5, 0, 0.5, 44)
	fuelBack.Size = UDim2.fromOffset(64, 4)
	round(fuelBack, FULL_ROUND)
	local fuelFill = newFrame(fuelBack, "Fill", Look.AccentColor, 0)
	fuelFill.Size = UDim2.fromScale(1, 1)
	round(fuelFill, FULL_ROUND)

	local lit = -1
	return function(kmh: number, fuel: number?, _engine: number?)
		speed.Text = speedText(kmh)
		local newLit = math.floor(math.clamp(kmh / Config.Speedometer.MaxSpeed, 0, 1) * count + 0.5)
		if newLit ~= lit then
			lit = newLit
			for i, segment in segments do
				segment.BackgroundColor3 = if i <= lit then Look.AccentColor else Color3.new(1, 1, 1)
				segment.BackgroundTransparency = if i <= lit then 0 else 0.8
			end
		end
		fuelBack.Visible = fuel ~= nil
		if fuel then
			fuelFill.Size = UDim2.fromScale(math.clamp(fuel, 0, 100) / 100, 1)
		end
	end
end

-- Skaitmeninis spidometras
local function buildDigital(parent: Instance)
	local panel = newFrame(parent, "Panel", Look.BackgroundColor, Look.BackgroundTransparency)
	panel.Size = UDim2.fromOffset(0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.XY
	round(panel, UDim.new(0, 12))
	padding(panel, 8, 14)
	local list = newList(panel, Enum.FillDirection.Vertical, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local speedRow = newFrame(panel, "SpeedRow", Color3.new(), 1)
	speedRow.Size = UDim2.fromOffset(0, 0)
	speedRow.AutomaticSize = Enum.AutomaticSize.XY
	speedRow.LayoutOrder = 1
	local rowList = newList(speedRow, Enum.FillDirection.Horizontal, 6)
	rowList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	local speed = newText(speedRow, "Speed", speedText(0), 56, Look.IconColor)
	speed.LayoutOrder = 1
	local unit = newText(speedRow, "Unit", Config.Speedometer.Unit, 13, Color3.fromRGB(170, 176, 188))
	unit.LayoutOrder = 2

	local setFuel = buildMeter(panel, "Fuel", "KURAS", 2)
	local setEngine = buildMeter(panel, "Engine", "VARIKLIS", 3)

	return function(kmh: number, fuel: number?, engine: number?)
		speed.Text = speedText(kmh)
		setFuel(fuel)
		setEngine(engine)
	end
end

local function buildSpeedometer(style: string)
	if speedContent then
		speedContent:Destroy()
	end
	speedContent = newFrame(speedRoot, "Content", Color3.new(), 1)
	speedContent.Size = UDim2.fromOffset(0, 0)
	speedContent.AutomaticSize = Enum.AutomaticSize.XY
	speedWidget = if style == "Digital" then buildDigital(speedContent) else buildRound(speedContent)
end

local function getVehicleSeat()
	local seat = currentHumanoid and currentHumanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		return seat
	end
	return nil
end

local function readNumber(seat: Instance, name: string): number?
	local value = seat:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

-- Rodo tik mašinoje
local function updateSpeedometer()
	local seat = getVehicleSeat()
	local editing = player:GetAttribute("HUDEditing") == true
	speedRoot.Visible = seat ~= nil or editing

	if seat and not speedConnection then
		speedConnection = RunService.RenderStepped:Connect(function()
			local current = getVehicleSeat()
			if current and speedWidget then
				local kmh = current.AssemblyLinearVelocity.Magnitude * Config.Speedometer.SpeedFactor
				speedWidget(kmh, readNumber(current, "Fuel"), readNumber(current, "EngineHealth"))
			end
		end)
	elseif not seat and speedConnection then
		speedConnection:Disconnect()
		speedConnection = nil
	end

	if not seat and editing and speedWidget then
		speedWidget(0, 75, 100)
	end
end

-- Nustatymai

local currentSettings = nil

local function applySettings()
	local settings = HUDSettings.decode(player:GetAttribute("HUDSettings"))
	local old = currentSettings
	local editing = player:GetAttribute("HUDEditing") == true

	if not old or old.Status.Style ~= settings.Status.Style or old.Status.Layout ~= settings.Status.Layout or old.Status.Thickness ~= settings.Status.Thickness then
		buildStatus(settings.Status)
	end
	statusRoot.Position = toUDim2(settings.Status.Position)
	statusScale.Scale = settings.Status.Scale

	if not old or old.Speedometer.Style ~= settings.Speedometer.Style then
		buildSpeedometer(settings.Speedometer.Style)
	end
	speedRoot.Position = toUDim2(settings.Speedometer.Position)
	speedScale.Scale = settings.Speedometer.Scale

	infoRoot.Position = toUDim2(settings.Info.Position)
	infoScale.Scale = settings.Info.Scale
	infoRoot.Visible = settings.Info.Visible or editing

	currentSettings = settings
	updateSpeedometer()
end

player:GetAttributeChangedSignal("HUDSettings"):Connect(applySettings)
player:GetAttributeChangedSignal("HUDEditing"):Connect(applySettings)

-- Personažas

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	currentHumanoid = humanoid
	updateStat("Health")
	updateSpeedometer()

	humanoid.HealthChanged:Connect(function()
		if humanoid == currentHumanoid then
			updateStat("Health")
		end
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if humanoid == currentHumanoid then
			updateStat("Health")
		end
	end)
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if humanoid == currentHumanoid then
			updateSpeedometer()
		end
	end)
end

applySettings()
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

screenGui.Parent = playerGui
