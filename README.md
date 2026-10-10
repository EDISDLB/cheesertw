# CheeserTW

## Alkio ir troškulio HUD

Ekrane rodomos dvi juostos: **Alkis** ir **Troškulys**. Jos lėtai mažėja. Kai rodiklis
nukrenta žemai, juosta pagelsta, o vėliau parausta ir ikona pradeda pulsuoti.
Kai rodiklis tuščias, žaidėjas po truputį praranda gyvybę.

### Failai

| Failas projekte | Kur yra Roblox Studio | Ką daro |
|---|---|---|
| `src/ReplicatedStorage/SurvivalConfig.lua` | `ReplicatedStorage > SurvivalConfig` (ModuleScript) | **Visi nustatymai**: spalvos, dydžiai, vieta, greitis, įspėjimai. |
| `src/ServerScriptService/SurvivalStats.server.lua` | `ServerScriptService > SurvivalStats` (Script) | Serveryje mažina alkį ir troškulį, atima gyvybę, kai jie tušti. |
| `src/StarterPlayerScripts/SurvivalHUD.client.lua` | `StarterPlayer > StarterPlayerScripts > SurvivalHUD` (LocalScript) | Nupiešia juostas ekrane ir jas animuoja. |
| `default.project.json` | — | Rojo nustatymas: kuris failas į kurią Roblox Studio vietą. |

### Kaip įkelti į Roblox Studio

**Su Rojo (rekomenduojama):** terminale paleisk `rojo serve`, o Roblox Studio Rojo įskiepyje spausk *Connect*.

**Be Rojo (rankiniu būdu):** Roblox Studio sukurk tris objektus ir į kiekvieną nukopijuok atitinkamo failo turinį:

1. `ReplicatedStorage` → **ModuleScript**, pavadinimas `SurvivalConfig`.
2. `ServerScriptService` → **Script**, pavadinimas `SurvivalStats`.
3. `StarterPlayer > StarterPlayerScripts` → **LocalScript**, pavadinimas `SurvivalHUD`.

Pavadinimai turi būti tiksliai tokie, nes skriptai vienas kitą randa pagal pavadinimą.

### Kaip keisti išvaizdą ir elgesį

Viskas keičiama tik faile `SurvivalConfig.lua`. Prie kiekvienos reikšmės yra paaiškinimas.

| Ką nori pakeisti | Skiltis faile | Reikšmės |
|---|---|---|
| Kaip greitai krenta alkis / troškulys | `Stats` | `SecondsToEmpty` |
| Kiek žalos daro tuščias rodiklis | `Stats` | `DamagePerSecond` |
| Juostų spalvas, ikonas, pavadinimus | `Stats` | `Color`, `Icon`, `IconImage`, `DisplayName` |
| Kada juosta pagelsta / parausta | `Warnings` | `WarningPercent`, `CriticalPercent` |
| HUD vietą ekrane | `HUD` | `Position`, `AnchorPoint` (telefone `MobilePosition`, `MobileAnchorPoint`) |
| HUD dydį | `HUD` | `Scale`, `MobileScale`, `Width`, `IconSize`, `BarHeight`, `TextSize` |
| Tarpus ir kampų apvalumą | `HUD` | `Spacing`, `Padding`, `CornerRadius` |
| Fono spalvą ir permatomumą | `Look` | `PanelColor`, `PanelTransparency`, `StrokeTransparency` ir kt. |
| Animacijų greitį | `Animation` | `BarTweenTime`, `PulseTime`, `PulseSize`, `PulseEnabled` |

### Kaip papildyti alkį ar troškulį (pvz. kai žaidėjas valgo)

Bet kuriame **serverio** skripte (Script):

```lua
-- Prideda 25 alkio. Daugiau nei maksimumas nebus — serveris tai apriboja.
player:SetAttribute("Hunger", player:GetAttribute("Hunger") + 25)

-- Prideda 40 troškulio.
player:SetAttribute("Thirst", player:GetAttribute("Thirst") + 40)
```

### Kaip patikrinti

1. Roblox Studio spausk **Play**. Apačioje kairėje turi atsirasti HUD su dviem juostomis (100%).
2. Viršuje, skirtuke **Test**, perjunk *Current: Client* į *Current: Server*.
3. Apačioje esančioje **Command Bar** eilutėje įvesk ir spausk Enter:
   - `game.Players:GetPlayers()[1]:SetAttribute("Hunger", 25)` → alkio juosta turi pagelsti.
   - `game.Players:GetPlayers()[1]:SetAttribute("Hunger", 10)` → juosta parausta, ikona pulsuoja.
   - `game.Players:GetPlayers()[1]:SetAttribute("Thirst", 0)` → žaidėjas pradeda prarasti gyvybę.
4. Norėdamas greitai pamatyti, kaip juostos krenta, laikinai nustatyk `SecondsToEmpty = 30`.

### Jei kas neveikia

Pirmiausia atsidaryk **View > Output** ir ieškok raudonų klaidų — jose parašytas failo pavadinimas ir eilutės numeris.

- **HUD visai nesimato** → tikrink `SurvivalHUD`: ar tai **LocalScript**, ar jis yra `StarterPlayer > StarterPlayerScripts`.
  Taip pat patikrink, ar `ReplicatedStorage` yra `SurvivalConfig` (tiksliai toks pavadinimas).
  Jei HUD yra, bet už ekrano ribų — tikrink `Position` ir `AnchorPoint` faile `SurvivalConfig`.
- **Juostos nemažėja** → tikrink `SurvivalStats`: ar tai **Script** (ne LocalScript), ar jis yra `ServerScriptService`.
  Faile `SurvivalConfig` patikrink, ar `SecondsToEmpty` nėra `0`.
- **Nesimato ikonų** → faile `SurvivalConfig` tikrink `Icon` (emoji) ir `IconImage`. Jei naudoji `IconImage`,
  jis turi būti formato `"rbxassetid://skaičius"` ir paveikslėlis turi būti patvirtintas Roblox.
- **Blogas išdėstymas (persidengia, per didelis, per mažas)** → faile `SurvivalConfig`, skiltyje `HUD`,
  keisk `Width`, `IconSize`, `BarHeight`, `TextSize`, `Scale`. Telefone naudojamos `Mobile...` reikšmės.
- **Reikšmės keičiasi, bet HUD neatsinaujina** → tikrink, ar keiti atributą **serveryje**.
  Atributo pavadinimas turi sutapti su pavadinimu `Stats` skiltyje (`Hunger`, `Thirst`).
