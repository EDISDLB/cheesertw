# CheeserTW

## GTA stiliaus HUD: gyvybė, šarvai, alkis ir troškulys

Apačioje kairėje ekrano pusėje rodomas stulpelis iš keturių apskritimų:
❤ **gyvybė**, 🛡 **šarvai**, 🍔 **alkis**, 💧 **troškulys**.
Kiekvieną apskritimą juosia spalvotas žiedas, kuris ištuštėja, kai rodiklis mažėja.

- Alkis ir troškulys lėtai krenta. Kai jie tušti, žaidėjas praranda gyvybę.
- Šarvai sugeria žalą prieš gyvybę (kaip GTA).
- Kai rodiklis žemas, žiedas tampa oranžinis, o vėliau raudonas ir apskritimas pulsuoja.
- Po atgimimo alkis ir troškulys vėl 100, šarvai 0.

### Failai

| Failas projekte | Kur yra Roblox Studio | Ką daro |
|---|---|---|
| `src/ReplicatedStorage/SurvivalConfig.lua` | `ReplicatedStorage > SurvivalConfig` (ModuleScript) | **Visi nustatymai**: spalvos, dydžiai, vieta, greitis, įspėjimai. |
| `src/ServerScriptService/SurvivalStats.server.lua` | `ServerScriptService > SurvivalStats` (Script) | Serveryje mažina alkį ir troškulį, valdo šarvus, atima gyvybę. |
| `src/StarterPlayerScripts/SurvivalHUD.client.lua` | `StarterPlayer > StarterPlayerScripts > SurvivalHUD` (LocalScript) | Nupiešia apskritimus, žiedus ir ikonas, juos animuoja. |
| `default.project.json` | — | Rojo nustatymas: kuris failas į kurią Roblox Studio vietą. |

### Kaip įkelti į Roblox Studio

**Su Rojo:** terminale paleisk `rojo serve`, o Roblox Studio Rojo įskiepyje spausk *Connect*.

**Be Rojo (rankiniu būdu):** Roblox Studio sukurk tris objektus ir į kiekvieną nukopijuok atitinkamo failo turinį:

1. `ReplicatedStorage` → **ModuleScript**, pavadinimas `SurvivalConfig`.
2. `ServerScriptService` → **Script**, pavadinimas `SurvivalStats`.
3. `StarterPlayer > StarterPlayerScripts` → **LocalScript**, pavadinimas `SurvivalHUD`.

Pavadinimai turi būti tiksliai tokie, nes skriptai vienas kitą randa pagal pavadinimą.

### Kaip keisti išvaizdą ir elgesį

Viskas keičiama faile `SurvivalConfig.lua`. Prie kiekvienos reikšmės yra paaiškinimas.

| Ką nori pakeisti | Skiltis faile | Reikšmės |
|---|---|---|
| Kurie apskritimai rodomi ir kokia tvarka | `Circles` | Eilučių tvarka; ištrink eilutę, kad paslėptum |
| Žiedo spalvą, ikoną | `Circles` | `Color`, `Icon`, `IconImage` |
| Kaip greitai krenta alkis / troškulys | `Stats` | `SecondsToEmpty` |
| Kiek žalos daro tuščias rodiklis | `Stats` | `DamagePerSecond` |
| Kiek šarvų turi pradžioje | `Stats > Armor` | `StartValue` |
| Ar šarvai sugeria žalą | — | `ArmorAbsorbsDamage` |
| Kada žiedas tampa oranžinis / raudonas | `Warnings` | `WarningPercent`, `CriticalPercent` |
| HUD vietą ekrane | `HUD` | `Position`, `AnchorPoint` (telefone `MobilePosition`, `MobileAnchorPoint`) |
| Stulpelis ar eilutė | `HUD` | `Layout` (`"Vertical"` arba `"Horizontal"`) |
| Dydžius | `HUD` | `CircleSize`, `RingThickness`, `RingInset`, `IconSize`, `Scale`, `MobileScale` |
| Tarpus | `HUD` | `Spacing` |
| Fono spalvą ir permatomumą | `Look` | `BackgroundColor`, `BackgroundTint`, `TrackTransparency`, `IconColor` |
| Animacijų greitį | `Animation` | `RingTweenTime`, `MoveTweenTime`, `PulseTime`, `PulseSize`, `PulseEnabled` |

### Kaip perkelti HUD per skriptą

Bet kuris skriptas gali perkelti HUD, pakeitęs žaidėjo atributus. HUD sklandžiai nuslenka į naują vietą.

```lua
-- Perkelia HUD į apatinį dešinį kampą.
player:SetAttribute("HUDAnchorPoint", Vector2.new(1, 1))
player:SetAttribute("HUDPosition", UDim2.new(1, -16, 1, -16))

-- Grąžina HUD į vietą iš SurvivalConfig.
player:SetAttribute("HUDAnchorPoint", nil)
player:SetAttribute("HUDPosition", nil)
```

- Iš **serverio** skripto (Script) — veikia iš karto.
- Iš **LocalScript** — naudok `game.Players.LocalPlayer` vietoje `player`.

`AnchorPoint` nurodo, kuris HUD kampas pritvirtinamas: `(0, 0)` viršutinis kairys, `(0, 1)` apatinis kairys,
`(1, 1)` apatinis dešinys. `Position` — kur tas kampas yra ekrane.

### Kaip duoti šarvų, maisto ar vandens

Bet kuriame **serverio** skripte (Script):

```lua
player:SetAttribute("Armor", 100) -- Pilni šarvai.
player:SetAttribute("Hunger", player:GetAttribute("Hunger") + 25) -- Pavalgė.
player:SetAttribute("Thirst", player:GetAttribute("Thirst") + 40) -- Atsigėrė.
```

Daugiau nei maksimumas nebus — serveris tai apriboja.

### Kaip patikrinti

1. Roblox Studio spausk **Play**. Apačioje kairėje turi atsirasti 4 apskritimai (šarvų žiedas tuščias).
2. Skirtuke **Test** perjunk *Current: Client* į *Current: Server*.
3. **Command Bar** eilutėje įvesk ir spausk Enter:
   - `game.Players:GetPlayers()[1]:SetAttribute("Armor", 100)` → šarvų žiedas užsipildo.
   - `game.Players:GetPlayers()[1].Character.Humanoid:TakeDamage(30)` → sumažėja šarvai, o ne gyvybė.
   - `game.Players:GetPlayers()[1]:SetAttribute("Hunger", 25)` → alkio žiedas oranžinis.
   - `game.Players:GetPlayers()[1]:SetAttribute("Hunger", 10)` → žiedas raudonas, apskritimas pulsuoja.
   - `game.Players:GetPlayers()[1]:SetAttribute("HUDPosition", UDim2.new(0, 16, 0.5, 0))` → HUD pasislenka aukštyn.
4. Norėdamas greitai pamatyti, kaip žiedai mažėja, laikinai nustatyk `SecondsToEmpty = 30`.

### Jei kas neveikia

Pirmiausia atsidaryk **View > Output** ir ieškok raudonų klaidų — jose parašytas failo pavadinimas ir eilutės numeris.

- **HUD visai nesimato** → tikrink `SurvivalHUD`: ar tai **LocalScript**, ar jis yra `StarterPlayer > StarterPlayerScripts`.
  Patikrink, ar `ReplicatedStorage` yra `SurvivalConfig` (tiksliai toks pavadinimas).
- **HUD yra, bet ne toje vietoje / už ekrano** → faile `SurvivalConfig`, skiltyje `HUD`, tikrink `Position` ir `AnchorPoint`.
  Jei kitas skriptas keitė `HUDPosition`, grąžink jį į `nil`.
- **Trūksta apskritimo** → faile `SurvivalConfig`, skiltyje `Circles`, patikrink, ar yra jo eilutė ir ar `Stat` parašytas teisingai.
  Klaidingas `Stat` parašomas Output lange (`SurvivalHUD: nežinomas rodiklis`).
- **Žiedai nemažėja** → tikrink `SurvivalStats`: ar tai **Script** (ne LocalScript), ar jis yra `ServerScriptService`.
  Faile `SurvivalConfig` patikrink, ar `SecondsToEmpty` nėra `0`.
- **Ikonos atrodo keistai** → faile `SurvivalConfig` tikrink `Icon` (`"Heart"`, `"Shield"`, `"Burger"`, `"Drop"` arba emoji)
  ir `IconImage` (turi būti `"rbxassetid://skaičius"`).
- **Šarvai nesugeria žalos** → faile `SurvivalConfig` tikrink `ArmorAbsorbsDamage = true`. Jei vienas smūgis iškart nužudo,
  šarvai neišgelbsti (tai žinomas apribojimas).
- **Per dideli / per maži apskritimai** → faile `SurvivalConfig`, skiltyje `HUD`, keisk `Scale` arba `CircleSize`.
