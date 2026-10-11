local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("SurvivalConfig"))
local HUDSettings = require(ReplicatedStorage:WaitForChild("HUDSettings"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("SurvivalHUD")

local ACCENT = Config.Look.AccentColor
local FONT = Config.Look.Font
local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.fromRGB(160, 166, 178)
local BUTTON = Color3.fromRGB(40, 44, 54)

local settings = HUDSettings.decode(player:GetAttribute("HUDSettings"))
local isOpen = false
local remote = nil
local refreshers = {}

-- Pagalbinės funkcijos

local function round(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = object
end

local function newLabel(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function newButton(parent: Instance, text: string, width: number): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(width, 28)
	button.BackgroundColor3 = BUTTON
	button.BackgroundTransparency = 0.1
	button.Font = FONT
	button.TextSize = 13
	button.TextColor3 = WHITE
	button.Text = text
	button.Parent = parent
	round(button, 8)
	return button
end

local function newList(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

-- Pritaiko nustatymus
local function apply()
	player:SetAttribute("HUDSettings", HUDSettings.encode(settings))
	settings = HUDSettings.decode(player:GetAttribute("HUDSettings"))
	for _, refresh in refreshers do
		refresh()
	end
end

-- Išsaugo serveryje
local function save()
	if remote then
		remote:FireServer("Save", HUDSettings.encode(settings))
	end
end

-- Langas

local gui = Instance.new("ScreenGui")
gui.Name = "HUDEditor"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dim = Instance.new("TextButton")
dim.Name = "Background"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.75
dim.AutoButtonColor = false
dim.Text = ""
dim.Modal = true -- Atlaisvina pelę
dim.ZIndex = 1
dim.Parent = gui

-- Rėmeliai tempimui

local targets = {
	{ key = "Status", title = "BŪKLĖ" },
	{ key = "Speedometer", title = "SPIDOMETRAS" },
	{ key = "Info", title = "INFORMACIJA" },
}
local dragging = nil

for _, target in targets do
	local handle = Instance.new("TextButton")
	handle.Name = target.key .. "Handle"
	handle.AutoButtonColor = false
	handle.Text = ""
	handle.BackgroundColor3 = ACCENT
	handle.BackgroundTransparency = 0.85
	handle.ZIndex = 2
	handle.Parent = gui
	round(handle, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = handle

	local tag = newLabel(handle, target.title, 11, WHITE)
	tag.AnchorPoint = Vector2.new(0, 1)
	tag.Position = UDim2.new(0, 0, 0, -4)
	tag.Size = UDim2.fromOffset(0, 18)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = ACCENT
	local tagPadding = Instance.new("UIPadding")
	tagPadding.PaddingLeft = UDim.new(0, 6)
	tagPadding.PaddingRight = UDim.new(0, 6)
	tagPadding.Parent = tag
	round(tag, 6)

	target.handle = handle
	target.tag = tag

	handle.InputBegan:Connect(function(input)
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
		local element = hud:FindFirstChild(target.key)
		if isClick and element and isOpen then
			dragging = {
				key = target.key,
				startMouse = Vector2.new(input.Position.X, input.Position.Y),
				startAnchor = element.AbsolutePosition + element.AbsoluteSize * element.AnchorPoint - hud.AbsolutePosition,
				size = element.AbsoluteSize,
				anchor = element.AnchorPoint,
			}
		end
	end)
end

-- Rėmeliai seka elementus
local function syncHandles()
	for _, target in targets do
		local element = hud:FindFirstChild(target.key)
		local visible = element ~= nil and element.Visible
		target.handle.Visible = visible
		if visible then
			local position = element.AbsolutePosition - hud.AbsolutePosition
			target.handle.Position = UDim2.fromOffset(position.X - 6, position.Y - 6)
			target.handle.Size = UDim2.fromOffset(element.AbsoluteSize.X + 12, element.AbsoluteSize.Y + 12)

			-- Užrašas apačioje
			local below = position.Y < 30
			target.tag.AnchorPoint = Vector2.new(0, if below then 0 else 1)
			target.tag.Position = if below then UDim2.new(0, 0, 1, 4) else UDim2.new(0, 0, 0, -4)
		end
	end
end

-- Tempimas pele
UserInputService.InputChanged:Connect(function(input)
	local isMove = input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
	if not dragging or not isMove or not isOpen then
		return
	end
	local screen = hud.AbsoluteSize
	local delta = Vector2.new(input.Position.X, input.Position.Y) - dragging.startMouse
	local point = dragging.startAnchor + delta

	-- Neišeina už ekrano
	local minX = dragging.anchor.X * dragging.size.X
	local minY = dragging.anchor.Y * dragging.size.Y
	local maxX = math.max(minX, screen.X - (1 - dragging.anchor.X) * dragging.size.X)
	local maxY = math.max(minY, screen.Y - (1 - dragging.anchor.Y) * dragging.size.Y)
	local x = math.clamp(point.X, minX, maxX)
	local y = math.clamp(point.Y, minY, maxY)

	settings[dragging.key].Position = { x / math.max(screen.X, 1), 0, y / math.max(screen.Y, 1), 0 }
	apply()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = nil
	end
end)

-- Nustatymų langas

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
panel.BackgroundTransparency = 0.15
panel.ZIndex = 3
panel.Parent = gui
round(panel, 14)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = WHITE
panelStroke.Transparency = 0.85
panelStroke.Parent = panel
local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 14)
panelPadding.PaddingBottom = UDim.new(0, 14)
panelPadding.PaddingLeft = UDim.new(0, 16)
panelPadding.PaddingRight = UDim.new(0, 16)
panelPadding.Parent = panel
newList(panel, Enum.FillDirection.Vertical, 8)

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

-- Antraštė
local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 40)
header.LayoutOrder = nextOrder()
header.Parent = panel

local title = newLabel(header, "HUD NUSTATYMAI", 18, WHITE)
title.Size = UDim2.new(1, -40, 0, 22)
local subtitle = newLabel(header, "Tempk elementus pele  •  F5 uždaro", 12, GREY)
subtitle.Position = UDim2.fromOffset(0, 22)
subtitle.Size = UDim2.new(1, -40, 0, 16)

local closeButton = newButton(header, "X", 28)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0)

-- Skilties pavadinimas
local function section(text: string)
	local label = newLabel(panel, text, 12, ACCENT)
	label.Size = UDim2.new(1, 0, 0, 22)
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.LayoutOrder = nextOrder()
end

-- Eilutė su mygtukais
local function row(text: string): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 28)
	frame.LayoutOrder = nextOrder()
	frame.Parent = panel

	local label = newLabel(frame, text, 13, GREY)
	label.Size = UDim2.new(0, 90, 1, 0)

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundTransparency = 1
	controls.Position = UDim2.fromOffset(90, 0)
	controls.Size = UDim2.new(1, -90, 1, 0)
	controls.Parent = frame
	local layout = newList(controls, Enum.FillDirection.Horizontal, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	return controls
end

-- Pasirinkimas
local function choiceRow(text: string, key: string, field: string, options)
	local controls = row(text)
	local buttons = {}
	for index, option in options do
		local button = newButton(controls, option[2], option[3] or 74)
		button.LayoutOrder = index
		button.MouseButton1Click:Connect(function()
			settings[key][field] = option[1]
			apply()
		end)
		buttons[index] = button
	end
	table.insert(refreshers, function()
		for index, option in options do
			local selected = settings[key][field] == option[1]
			buttons[index].BackgroundColor3 = if selected then ACCENT else BUTTON
		end
	end)
end

-- Didinti ir mažinti
local function stepperRow(text: string, key: string, field: string, step: number, format)
	local controls = row(text)
	local minus = newButton(controls, "-", 32)
	minus.LayoutOrder = 1
	local value = newLabel(controls, "", 13, WHITE)
	value.Size = UDim2.fromOffset(56, 28)
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.LayoutOrder = 2
	local plus = newButton(controls, "+", 32)
	plus.LayoutOrder = 3

	minus.MouseButton1Click:Connect(function()
		settings[key][field] -= step
		apply()
	end)
	plus.MouseButton1Click:Connect(function()
		settings[key][field] += step
		apply()
	end)
	table.insert(refreshers, function()
		value.Text = format(settings[key][field])
	end)
end

local function percent(value: number): string
	return math.floor(value * 100 + 0.5) .. "%"
end

section("BŪKLĖ  (gyvybė, šarvai, maistas, vanduo)")
choiceRow("Stilius", "Status", "Style", { { "Circles", "Apskritimai", 86 }, { "Bars", "Juostos", 70 }, { "Squares", "Kvadratai", 76 } })
choiceRow("Išdėstymas", "Status", "Layout", { { "Vertical", "Stulpelis", 90 }, { "Horizontal", "Eilutė", 90 } })
stepperRow("Dydis", "Status", "Scale", 0.1, percent)
stepperRow("Storis", "Status", "Thickness", 1, tostring)

section("SPIDOMETRAS")
choiceRow("Stilius", "Speedometer", "Style", { { "Round", "Apvalus", 90 }, { "Digital", "Skaitmeninis", 100 } })
stepperRow("Dydis", "Speedometer", "Scale", 0.1, percent)

section("INFORMACIJA  (pavadinimas, laikas)")
choiceRow("Rodyti", "Info", "Visible", { { true, "Rodyti", 90 }, { false, "Slėpti", 90 } })
stepperRow("Dydis", "Info", "Scale", 0.1, percent)

-- Apačios mygtukai
local footer = Instance.new("Frame")
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, 0, 0, 36)
footer.LayoutOrder = nextOrder()
footer.Parent = panel
local footerList = newList(footer, Enum.FillDirection.Horizontal, 8)
footerList.HorizontalAlignment = Enum.HorizontalAlignment.Right

local resetButton = newButton(footer, "Atstatyti", 110)
resetButton.LayoutOrder = 1
local saveButton = newButton(footer, "Išsaugoti", 110)
saveButton.LayoutOrder = 2
saveButton.BackgroundColor3 = ACCENT

-- Langą galima tempti
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local start = Vector2.new(input.Position.X, input.Position.Y)
		local startPosition = panel.Position
		local moveConnection, endConnection
		moveConnection = UserInputService.InputChanged:Connect(function(move)
			if move.UserInputType == Enum.UserInputType.MouseMovement or move.UserInputType == Enum.UserInputType.Touch then
				local delta = Vector2.new(move.Position.X, move.Position.Y) - start
				panel.Position = startPosition + UDim2.fromOffset(delta.X, delta.Y)
			end
		end)
		endConnection = UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == input.UserInputType then
				moveConnection:Disconnect()
				endConnection:Disconnect()
			end
		end)
	end
end)
header.Active = true

-- Atidaryti ir uždaryti

local syncConnection = nil

local function setOpen(open: boolean)
	if open == isOpen then
		return
	end
	isOpen = open
	dragging = nil
	gui.Enabled = open
	player:SetAttribute("HUDEditing", open)

	if open then
		settings = HUDSettings.decode(player:GetAttribute("HUDSettings"))
		for _, refresh in refreshers do
			refresh()
		end
		syncConnection = RunService.RenderStepped:Connect(syncHandles)
	else
		if syncConnection then
			syncConnection:Disconnect()
			syncConnection = nil
		end
		save()
	end
end

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)
saveButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)
resetButton.MouseButton1Click:Connect(function()
	settings = HUDSettings.defaults()
	apply()
end)

-- F5 mygtukas
UserInputService.InputBegan:Connect(function(input)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if table.find(Config.Editor.Keys, input.KeyCode) then
		setOpen(not isOpen)
	end
end)

-- Komanda /hud
task.spawn(function()
	remote = ReplicatedStorage:WaitForChild("HUDEditorEvent")
	remote.OnClientEvent:Connect(function(action)
		if action == "Open" then
			setOpen(true)
		end
	end)
end)

gui.Parent = playerGui
