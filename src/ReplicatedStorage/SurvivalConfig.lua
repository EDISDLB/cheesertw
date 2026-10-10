--[[
	SurvivalConfig — VISI HUD, gyvybės, šarvų, alkio ir troškulio nustatymai vienoje vietoje.

	Čia saugu keisti skaičius, spalvas ir tekstus (dešinėje nuo "=").
	Nekeisk pavadinimų kairėje nuo "=" (pvz. Hunger, CircleSize, Position),
	nes juos naudoja kiti skriptai.

	Spalvos rašomos taip: Color3.fromRGB(raudona, žalia, mėlyna), kiekviena nuo 0 iki 255.
	Permatomumas (Transparency): 0 = visai nepermatoma, 1 = visai nematoma.
]]

local SurvivalConfig = {}

-- =====================================================================
-- 1. RODIKLIAI (serverio taisyklės)
-- Kiekvienas rodiklis saugomas kaip žaidėjo atributas tokiu pačiu pavadinimu,
-- pvz. player:GetAttribute("Hunger"). Gyvybė (Health) imama iš Humanoid, todėl jos čia nėra.
-- =====================================================================
SurvivalConfig.Stats = {
	Hunger = {
		Max = 100, -- Pilno rodiklio reikšmė.
		StartValue = 100, -- Kiek turi prisijungus ir po atgimimo.
		SecondsToEmpty = 600, -- Per kiek sekundžių nukrenta nuo pilno iki 0 (600 = 10 min). 0 = nemažėja.
		DamagePerSecond = 2, -- Kiek gyvybės atima per sekundę, kai rodiklis tuščias. 0 = neatima.
	},

	Thirst = {
		Max = 100,
		StartValue = 100,
		SecondsToEmpty = 450, -- Troškulys krenta greičiau nei alkis (7,5 min).
		DamagePerSecond = 2,
	},

	Armor = {
		Max = 100,
		StartValue = 0, -- Šarvų pradžioje nėra. Duoti šarvų: player:SetAttribute("Armor", 100)
		SecondsToEmpty = 0, -- Šarvai savaime nemažėja.
		DamagePerSecond = 0,
	},
}

-- Ar po atgimimo rodikliai grįžta į StartValue (alkis ir troškulys = 100, šarvai = 0).
SurvivalConfig.ResetOnRespawn = true

-- Ar šarvai sugeria žalą prieš gyvybę (kaip GTA). Sugeria bet kokią žalą, ir nuo bado.
SurvivalConfig.ArmorAbsorbsDamage = true

-- Kas kiek sekundžių serveris sumažina rodiklius.
SurvivalConfig.UpdateEverySeconds = 1

-- =====================================================================
-- 2. HUD APSKRITIMAI
-- Tvarka sąraše = tvarka ekrane (iš viršaus į apačią).
-- Norint paslėpti apskritimą, ištrink jo eilutę.
--
-- Stat:      "Health" (gyvybė) arba pavadinimas iš Stats ("Armor", "Hunger", "Thirst").
-- Color:     žiedo spalva.
-- Icon:      "Heart", "Shield", "Burger", "Drop" (nupieštos baltos ikonos) arba bet koks emoji, pvz. "🍗".
-- IconImage: savas paveikslėlis, pvz. "rbxassetid://123456". Jei įrašytas, naudojamas vietoj Icon.
-- Warnings:  ar apskritimas keičia spalvą ir pulsuoja, kai rodiklis žemas.
-- =====================================================================
SurvivalConfig.Circles = {
	{ Stat = "Health", Color = Color3.fromRGB(225, 50, 60), Icon = "Heart", IconImage = "", Warnings = true },
	{ Stat = "Armor", Color = Color3.fromRGB(240, 240, 240), Icon = "Shield", IconImage = "", Warnings = false },
	{ Stat = "Hunger", Color = Color3.fromRGB(245, 185, 30), Icon = "Burger", IconImage = "", Warnings = true },
	{ Stat = "Thirst", Color = Color3.fromRGB(45, 140, 245), Icon = "Drop", IconImage = "", Warnings = true },
}

-- =====================================================================
-- 3. ĮSPĖJIMAI (tik apskritimams su Warnings = true)
-- =====================================================================
SurvivalConfig.Warnings = {
	WarningPercent = 30, -- Kai liko tiek % ar mažiau, žiedas tampa oranžinis.
	CriticalPercent = 15, -- Kai liko tiek % ar mažiau, žiedas tampa raudonas ir apskritimas pulsuoja.
	WarningColor = Color3.fromRGB(255, 120, 30),
	CriticalColor = Color3.fromRGB(235, 45, 45),
}

-- =====================================================================
-- 4. HUD VIETA IR DYDŽIAI (pikseliais)
-- Vietą galima keisti ir per skriptą, žr. README.md („Kaip perkelti HUD per skriptą“).
-- =====================================================================
SurvivalConfig.HUD = {
	-- Kompiuteryje: apačioje kairėje.
	AnchorPoint = Vector2.new(0, 1), -- Kuris HUD kampas pritvirtinamas: (0, 1) = apatinis kairysis.
	Position = UDim2.new(0, 16, 1, -16), -- 16 px nuo kairio krašto ir 16 px nuo apačios.
	Scale = 1, -- Viso HUD dydis: 1 = 100 %, 1.2 = 120 %.

	-- Telefone ir planšetėje: kairėje, per vidurį, kad neuždengtų valdymo vairalazdės apačioje.
	MobileAnchorPoint = Vector2.new(0, 0.5),
	MobilePosition = UDim2.new(0, 10, 0.5, 0),
	MobileScale = 0.8,

	Layout = "Vertical", -- "Vertical" = stulpelis (kaip GTA), "Horizontal" = eilutė.
	CircleSize = 44, -- Apskritimo dydis. Geriau lyginis skaičius.
	RingThickness = 4, -- Spalvoto žiedo storis.
	RingInset = 2, -- Tamsus kraštelis aplink žiedą.
	IconSize = 20, -- Baltos ikonos dydis apskritimo viduje.
	Spacing = 8, -- Tarpas tarp apskritimų.
}

-- =====================================================================
-- 5. IŠVAIZDA
-- =====================================================================
SurvivalConfig.Look = {
	BackgroundColor = Color3.fromRGB(18, 18, 22), -- Apskritimo vidaus spalva.
	BackgroundTint = 0.15, -- Kiek vidus nusidažo žiedo spalva: 0 = visai ne, 1 = visiškai.
	TrackTransparency = 0.8, -- Tuščios žiedo dalies permatomumas (1 = tuščios dalies nesimato).
	IconColor = Color3.fromRGB(255, 255, 255), -- Nupieštų ikonų spalva.
}

-- =====================================================================
-- 6. ANIMACIJOS (laikas sekundėmis)
-- =====================================================================
SurvivalConfig.Animation = {
	RingTweenTime = 0.4, -- Per kiek laiko žiedas sklandžiai pasikeičia. 0 = iškart.
	MoveTweenTime = 0.3, -- Per kiek laiko HUD nuslenka į naują vietą, kai ją keičia skriptas.
	PulseEnabled = true, -- Ar apskritimas pulsuoja, kai rodiklis kritinis.
	PulseTime = 0.5, -- Vieno pulso trukmė (mažiau = greičiau).
	PulseSize = 1.15, -- Kiek kartų padidėja apskritimas pulsuojant.
}

return SurvivalConfig
