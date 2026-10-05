--!strict
--[[
	Kit/Sound — UI sound hook: components request UI cues by key; the audio team injects the real player.

	Purpose:          Components call `Sound.play("ui_click")` etc. without depending on the AudioEngine. The
	                  Audio controller calls `Sound.setPlayer(function(key) AudioEngine:playUi(key) end)` at Start.
	                  Keys are the catalogue keys from docs/design/audio.md §10 (UI bus).
	Dependencies:     Core/Log.
	State:            Injected player function, mute flag, play counters (diagnostics/tests).
	Validation:       Keys must be non-empty strings.
	Error handling:   A failing player is logged once per key and never breaks the calling component.
	Performance notes: One function call per cue; voice caps/rate limits (ui_hover x1, slider 30/s) are enforced by
	                  the AudioEngine, not here.
]]

local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

export type Player = (key: string) -> ()

local log = Log.scope("UI.Sound")

local Sound = {}

--- Catalogue keys used by the kit (docs/design/audio.md §10, UI bus).
Sound.KEYS = table.freeze({
	hover = "ui_hover",
	click = "ui_click",
	back = "ui_back",
	confirm = "ui_confirm",
	error = "ui_error",
	toggleOn = "ui_toggle_on",
	toggleOff = "ui_toggle_off",
	tab = "ui_tab_switch",
	slider = "ui_slider_tick",
	open = "ui_open_panel",
	close = "ui_close_panel",
	notification = "ui_notification",
	purchase = "ui_purchase",
})

local player: Player? = nil
local muted = false
local failedKeys: { [string]: boolean } = {}
local counts: { [string]: number } = {}

--- Installs the function that actually plays a UI sound (nil = silent).
function Sound.setPlayer(fn: Player?)
	player = fn
end

function Sound.setMuted(value: boolean)
	muted = value
end

--- Requests a UI cue by catalogue key.
function Sound.play(key: string)
	if type(key) ~= "string" or key == "" then
		error("Sound.play expects a catalogue key", 2)
	end
	counts[key] = (counts[key] or 0) + 1
	local fn = player
	if fn == nil or muted then
		return
	end
	local ok, err = pcall(fn :: any, key)
	if not ok and not failedKeys[key] then
		failedKeys[key] = true
		log:warn("UI sound %s failed: %s", key, tostring(err))
	end
end

--- Number of times each key was requested (diagnostics and tests).
function Sound.counts(): { [string]: number }
	return table.clone(counts)
end

function Sound.resetCounts()
	table.clear(counts)
end

return Sound
