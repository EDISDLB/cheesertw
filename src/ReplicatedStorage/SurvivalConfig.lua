local SurvivalConfig = {}

-- Serverio pavadinimas
SurvivalConfig.ServerName = "UTENA RP"
SurvivalConfig.ServerNameColor = Color3.fromRGB(30, 85, 210) -- Tamsiai mėlyna
SurvivalConfig.OnlineText = "Prisijungusių"

-- Alkis, troškulys, šarvai
SurvivalConfig.Stats = {
	Hunger = {
		Max = 100, -- Pilna reikšmė
		StartValue = 100, -- Pradžioje
		SecondsToEmpty = 2400, -- 40 minučių
		DamagePerSecond = 2, -- Žala badaujant
	},

	Thirst = {
		Max = 100,
		StartValue = 100,
		SecondsToEmpty = 2400, -- 40 minučių
		DamagePerSecond = 2,
	},

	Armor = {
		Max = 100,
		StartValue = 0, -- Šarvų nėra
		SecondsToEmpty = 0, -- Nemažėja
		DamagePerSecond = 0,
	},
}

SurvivalConfig.ResetOnRespawn = true -- Atgimus pilna
SurvivalConfig.ArmorAbsorbsDamage = true -- Šarvai saugo
SurvivalConfig.UpdateEverySeconds = 1 -- Atnaujinimas

-- Būklės ikonos
SurvivalConfig.Circles = {
	{ Stat = "Health", Color = Color3.fromRGB(225, 50, 60), Icon = "Heart", IconImage = "", Warnings = true },
	{ Stat = "Armor", Color = Color3.fromRGB(240, 240, 240), Icon = "Shield", IconImage = "", Warnings = false },
	{ Stat = "Hunger", Color = Color3.fromRGB(245, 185, 30), Icon = "Burger", IconImage = "", Warnings = true },
	{ Stat = "Thirst", Color = Color3.fromRGB(45, 140, 245), Icon = "Drop", IconImage = "", Warnings = true },
}

-- Įspėjimai
SurvivalConfig.Warnings = {
	WarningPercent = 30, -- Oranžinė riba
	CriticalPercent = 15, -- Raudona riba
	WarningColor = Color3.fromRGB(255, 120, 30),
	CriticalColor = Color3.fromRGB(235, 45, 45),
}

-- Išvaizda
SurvivalConfig.Look = {
	BackgroundColor = Color3.fromRGB(18, 18, 22), -- Fono spalva
	BackgroundTransparency = 0.35, -- Fono permatomumas
	BackgroundTint = 0.15, -- Atspalvis
	TrackTransparency = 0.8, -- Tuščia dalis
	IconColor = Color3.fromRGB(255, 255, 255), -- Ikonų spalva
	AccentColor = Color3.fromRGB(45, 140, 245), -- Spidometro spalva
	Font = Enum.Font.GothamBold, -- Šriftas
}

-- Animacijos
SurvivalConfig.Animation = {
	RingTweenTime = 0.4, -- Žiedo greitis
	PulseEnabled = true, -- Pulsavimas
	PulseTime = 0.5, -- Pulso trukmė
	PulseSize = 1.15, -- Pulso dydis
}

-- Spidometras
SurvivalConfig.Speedometer = {
	MaxSpeed = 200, -- Skalės galas
	SpeedFactor = 1, -- Greičio daugiklis
	Unit = "KM/H", -- Vienetai
}

-- F5 meniu
SurvivalConfig.Editor = {
	Keys = { Enum.KeyCode.F5 }, -- Atidarymo mygtukai
	ChatCommand = "/hud", -- Komanda pokalbyje
	SaveSettings = true, -- Išsaugoti nustatymus
}

-- Numatyta vieta
-- Position = { X dalis, X pikseliai, Y dalis, Y pikseliai }
SurvivalConfig.DefaultLayout = {
	Status = {
		Style = "Circles", -- Circles, Bars, Squares
		Layout = "Vertical", -- Vertical, Horizontal
		Scale = 1,
		Thickness = 4,
		Position = { 0, 16, 1, -16 }, -- Apačia kairėje
	},
	Speedometer = {
		Style = "Round", -- Round, Digital
		Scale = 1,
		Position = { 1, -24, 1, -24 }, -- Apačia dešinėje
	},
	Info = {
		Visible = true,
		Scale = 1,
		Position = { 1, -16, 0, 12 }, -- Viršus dešinėje
	},
}

return SurvivalConfig
