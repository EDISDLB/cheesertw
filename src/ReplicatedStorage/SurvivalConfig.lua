--[[
	SurvivalConfig — VISI alkio, troškulio ir HUD nustatymai vienoje vietoje.

	Čia saugu keisti skaičius, spalvas ir tekstus (dešinėje nuo "=").
	Nekeisk pavadinimų kairėje nuo "=" (pvz. Hunger, Width, Position),
	nes juos naudoja kiti skriptai.

	Spalvos rašomos taip: Color3.fromRGB(raudona, žalia, mėlyna), kiekviena nuo 0 iki 255.
	Permatomumas (Transparency): 0 = visai nepermatoma, 1 = visai nematoma.
]]

local SurvivalConfig = {}

-- =====================================================================
-- 1. RODIKLIAI: alkis ir troškulys
-- =====================================================================
SurvivalConfig.Stats = {
	Hunger = {
		DisplayName = "Alkis", -- Tekstas virš juostos.
		Order = 1, -- Kelinta juosta iš viršaus (1 = pirma).
		Max = 100, -- Pilno rodiklio reikšmė.
		SecondsToEmpty = 600, -- Per kiek sekundžių pilnas rodiklis nukrenta iki 0 (600 = 10 min). 0 = nemažėja.
		DamagePerSecond = 2, -- Kiek gyvybės atima per sekundę, kai rodiklis tuščias. 0 = neatima.
		Color = Color3.fromRGB(240, 150, 60), -- Juostos spalva, kai viskas gerai.
		Icon = "🍗", -- Ikona (emoji).
		IconImage = "", -- Savas paveikslėlis, pvz. "rbxassetid://123456". Jei tuščia, rodomas emoji.
	},

	Thirst = {
		DisplayName = "Troškulys",
		Order = 2,
		Max = 100,
		SecondsToEmpty = 450, -- Troškulys krenta greičiau nei alkis (7,5 min).
		DamagePerSecond = 2,
		Color = Color3.fromRGB(70, 170, 245),
		Icon = "💧",
		IconImage = "",
	},
}

-- Ar po mirties alkis ir troškulys vėl pilni.
SurvivalConfig.ResetOnRespawn = true

-- Kas kiek sekundžių serveris sumažina rodiklius.
SurvivalConfig.UpdateEverySeconds = 1

-- =====================================================================
-- 2. ĮSPĖJIMAI: kada juosta keičia spalvą
-- =====================================================================
SurvivalConfig.Warnings = {
	WarningPercent = 30, -- Kai liko tiek % ar mažiau, juosta tampa geltona.
	CriticalPercent = 15, -- Kai liko tiek % ar mažiau, juosta tampa raudona ir ikona pulsuoja.
	WarningColor = Color3.fromRGB(255, 200, 50),
	CriticalColor = Color3.fromRGB(235, 70, 60),
}

-- =====================================================================
-- 3. HUD VIETA IR DYDŽIAI (pikseliais)
-- =====================================================================
SurvivalConfig.HUD = {
	-- Kompiuteryje: apačioje kairėje.
	AnchorPoint = Vector2.new(0, 1), -- Kuris HUD kampas pritvirtinamas: (0, 1) = apatinis kairysis.
	Position = UDim2.new(0, 20, 1, -20), -- 20 px nuo kairio krašto ir 20 px nuo apačios.
	Scale = 1, -- Viso HUD dydis: 1 = 100 %, 1.2 = 120 %.

	-- Telefone ir planšetėje: viršuje kairėje, kad neuždengtų valdymo vairalazdės.
	MobileAnchorPoint = Vector2.new(0, 0),
	MobilePosition = UDim2.new(0, 12, 0, 12),
	MobileScale = 0.85,

	Width = 240, -- HUD plotis.
	IconSize = 30, -- Ikonos dydis.
	BarHeight = 10, -- Juostos aukštis.
	TextSize = 14, -- Teksto dydis.
	Spacing = 8, -- Tarpas tarp juostų ir tarp ikonos bei juostos.
	Padding = 10, -- Tarpas nuo HUD krašto iki turinio.
	CornerRadius = 10, -- Kampų apvalumas (0 = kampuoti kampai).
}

-- =====================================================================
-- 4. IŠVAIZDA: spalvos, permatomumas, šriftas
-- =====================================================================
SurvivalConfig.Look = {
	PanelColor = Color3.fromRGB(20, 22, 28), -- HUD fono spalva.
	PanelTransparency = 0.35, -- HUD fono permatomumas.
	StrokeColor = Color3.fromRGB(255, 255, 255), -- Rėmelio spalva.
	StrokeTransparency = 0.85, -- Rėmelio permatomumas (1 = be rėmelio).
	BarBackgroundColor = Color3.fromRGB(0, 0, 0), -- Tuščios juostos dalies spalva.
	BarBackgroundTransparency = 0.5,
	IconBackgroundTransparency = 0.75, -- Spalvoto apskritimo už ikonos permatomumas.
	TextColor = Color3.fromRGB(235, 235, 235),
	Font = Enum.Font.GothamBold,
	ShowValueText = true, -- Ar rodyti procentus (pvz. 75%).
}

-- =====================================================================
-- 5. ANIMACIJOS (laikas sekundėmis)
-- =====================================================================
SurvivalConfig.Animation = {
	BarTweenTime = 0.4, -- Per kiek laiko juosta sklandžiai pasislenka į naują vertę. 0 = iškart.
	PulseEnabled = true, -- Ar ikona pulsuoja, kai rodiklis kritinis.
	PulseTime = 0.5, -- Vieno pulso trukmė (mažiau = greičiau).
	PulseSize = 1.2, -- Kiek kartų padidėja ikona pulsuojant.
}

return SurvivalConfig
