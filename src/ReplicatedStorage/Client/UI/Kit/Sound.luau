--!strict
--[[
	Kit/Sound — UI sound hook: components request UI cues by key; the audio team injects the real player.

	Purpose:          Components call `Sound.play("ui_click")` etc. without depending on the AudioEngine. The
	                  Audio controller calls `Sound.setPlayer(function(key) AudioEngine:playUi(key) end)` at Start.
	                  Keys are the catalogue keys from docs/design/audio.md §10 (UI bus).
	Dependencies:     Core/Log.
	                  `Sound.hover()` is the one entry for ui_hover (pointer enter AND gamepad focus moves share it):
	                  at most HOVER_RATE ticks per second, so sweeping the pointer across a grid or scrolling fast
	                  never machine-guns the cue (ui-ux §1.16: "not while scrolling faster than 6 items/s").
	State:            Injected player function, mute flag, play counters (diagnostics/tests), the hover limiter's
	                  clock and last tick.
	Validation:       Keys must be non-empty strings.
	Error handling:   A failing player is logged once per key and never breaks the calling component.
	Performance notes: One function call per cue; voice caps (ui_hover x1, slider 30/s) are enforced by the
	                  AudioEngine, not here.
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

--- Max ui_hover ticks per second (pointer and gamepad focus together; ui-ux §1.16).
Sound.HOVER_RATE = 6

local hoverClock: () -> number = os.clock
local lastHoverAt = -math.huge

--- Plays ui_hover unless one played less than 1 / HOVER_RATE s ago. Returns true if it played.
function Sound.hover(): boolean
	local now = hoverClock()
	if now - lastHoverAt < 1 / Sound.HOVER_RATE then
		return false
	end
	lastHoverAt = now
	Sound.play(Sound.KEYS.hover)
	return true
end

--- Replaces the clock of the hover rate limit (tests) and resets it. nil restores os.clock.
function Sound.setClock(fn: (() -> number)?)
	hoverClock = fn or os.clock
	lastHoverAt = -math.huge
end

--- Forgets the last hover tick (the next hover plays).
function Sound.resetHover()
	lastHoverAt = -math.huge
end

--- Number of times each key was requested (diagnostics and tests).
function Sound.counts(): { [string]: number }
	return table.clone(counts)
end

function Sound.resetCounts()
	table.clear(counts)
end

return Sound
