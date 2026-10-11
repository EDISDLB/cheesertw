# UTENA RP HUD

Gyvybė, šarvai, maistas, vanduo, spidometras, viršutinė juosta (pavadinimas, laikas, prisijungę)
ir **F5 meniu**, kuriame kiekvienas žaidėjas pats keičia HUD vietą, dydį ir išvaizdą.

## Kur dėti skriptus Roblox Studio

| Pavadinimas | Tipas | Kur dėti |
|---|---|---|
| `SurvivalConfig` | ModuleScript | `ReplicatedStorage` |
| `HUDSettings` | ModuleScript | `ReplicatedStorage` |
| `SurvivalStats` | Script | `ServerScriptService` |
| `HUDSettingsSave` | Script | `ServerScriptService` |
| `SurvivalHUD` | LocalScript | `StarterPlayer > StarterPlayerScripts` |
| `HUDEditor` | LocalScript | `StarterPlayer > StarterPlayerScripts` |

Pavadinimai turi būti tiksliai tokie. Seni skriptai (`SurvivalHUB`, `HUDMenuScript`) turi būti ištrinti.

## Ką daro kiekvienas

| Skriptas | Ką daro |
|---|---|
| `SurvivalConfig` | Visi nustatymai: pavadinimas, spalvos, greičiai, numatyta vieta. |
| `HUDSettings` | Patikrina žaidėjo F5 nustatymus. Keisti nereikia. |
| `SurvivalStats` | Alkis, troškulys (40 min), šarvai, žala. |
| `HUDSettingsSave` | Išsaugo F5 nustatymus, komanda `/hud`. |
| `SurvivalHUD` | Piešia visą HUD ekrane. |
| `HUDEditor` | F5 meniu: tempimas, dydis, stilius. |

## F5 meniu

- **F5** atidaro ir uždaro. Studio teste F5 užimtas pačio Studio, todėl ten rašyk **`/hud`** pokalbyje.
- Mėlynus rėmelius tempk pele. Kai meniu uždarytas, HUD nejuda.
- Būklė: Apskritimai / Juostos / Kvadratai, Stulpelis / Eilutė, Dydis, Storis.
- Spidometras: Apvalus / Skaitmeninis, Dydis.
- Informacija: Rodyti / Slėpti, Dydis.
- **Išsaugoti** išsaugo nustatymus žaidėjui (DataStore).

Kad išsaugojimas veiktų Studio: *Game Settings > Security > Enable Studio Access to API Services*.

## Spidometras

Rodomas tik sėdint `VehicleSeat`. Kuras ir variklis rodomi, jei sėdynė turi atributus
`Fuel` ir `EngineHealth` (0–100).

## Kaip duoti šarvų, maisto, vandens (serverio skripte)

```lua
player:SetAttribute("Armor", 100)
player:SetAttribute("Hunger", player:GetAttribute("Hunger") + 25)
player:SetAttribute("Thirst", player:GetAttribute("Thirst") + 40)
```

## Jei neveikia

Atidaryk **View > Output** ir žiūrėk raudonas klaidas.

- **Nieko nesimato** → ar `SurvivalHUD` yra LocalScript `StarterPlayerScripts`, ar `SurvivalConfig` ir `HUDSettings` yra `ReplicatedStorage`.
- **F5 neveikia Studio** → rašyk `/hud` pokalbyje. Tikrame žaidime F5 veikia.
- **`/hud` neveikia** → ar `HUDSettingsSave` yra `ServerScriptService`, ar `TextChatService > ChatVersion` yra `TextChatService`.
- **Du HUD vienas ant kito** → ištrink senus `SurvivalHUB` ir `HUDMenuScript`.
- **Nustatymai neišsisaugo Studio** → įjunk API Services (žr. aukščiau).
