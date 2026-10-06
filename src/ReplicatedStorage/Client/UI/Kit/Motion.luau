--!strict
--[[
	Kit/Motion — UI animation helpers (TweenService + Heartbeat loops) that honour reduced motion.

	Purpose:          `Motion.tween(inst, props, spec)` with token durations/easings, presets (fadeIn/fadeOut,
	                  slideIn/slideOut, pop, pulse, shake, countUp) and spring smoothing (`follow`). Brand motion is
	                  calm: 120–200 ms ease-out, nothing bounces, one 400 ms flourish for rewards (brand-art §8.1).
	                  Reduced motion (player setting OR GuiService.ReducedMotionEnabled, via Theme) removes movement
	                  (slides, pops, pulses, shakes, springs snap, count-ups jump to the final value) and caps fades
	                  and colour changes at 0.1 s, per Roblox guidance ("set tween time to 0 or use a fade instead").
	Dependencies:     Kit/Theme (tokens, reduced-motion state), Kit/Services (TweenService, RunService), Kit/State.
	State:            None at module level; loops/tweens are returned to the caller as stop functions or Tweens.
	Validation:       Unknown duration/easing tokens raise (Theme); negative durations are treated as 0.
	Error handling:   Step callbacks run under the caller's responsibility; a failing callback stops its loop and
	                  is logged.
	Performance notes: Property tweens run in the engine (TweenService). Lua loops (countUp, shake, follow) use one
	                  Heartbeat connection each and disconnect themselves when done.
]]

local Theme = require("./Theme")
local State = require("./State")
local Services = require("./Services")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

type Trove = Trove.Trove
type State<T> = State.State<T>

export type Kind = "move" | "scale" | "fade" | "color"
export type Spec = {
	--- Seconds or a Theme motion token (default "base" = 0.15 s).
	duration: (number | Theme.MotionToken)?,
	--- Theme easing token (default "standard" = Quad Out).
	easing: Theme.EasingToken?,
	delay: number?,
	--- -1 repeats forever.
	repeatCount: number?,
	reverses: boolean?,
	--- What the tween animates; decides the reduced-motion treatment (default "move").
	kind: Kind?,
}
export type Direction = "left" | "right" | "top" | "bottom"
export type FollowOptions = {
	--- Oscillation frequency in Hz (default 4).
	frequency: number?,
	--- Damping ratio (default 1 = critical, no overshoot).
	damping: number?,
}

local log = Log.scope("UI.Motion")

local Motion = {}

--- Longest fade/colour change allowed under reduced motion (seconds).
Motion.REDUCED_FADE_MAX = 0.1

function Motion.isReduced(): boolean
	return Theme.state.reducedMotion:peek()
end

--- Effective duration for a spec under the current reduced-motion setting.
function Motion.resolveDuration(duration: (number | Theme.MotionToken)?, kind: Kind?): number
	local seconds = if type(duration) == "number" then duration else Theme.duration((duration or "base") :: any)
	if seconds ~= seconds or seconds < 0 then
		seconds = 0
	end
	if Motion.isReduced() then
		if kind == "fade" or kind == "color" then
			return math.min(seconds, Motion.REDUCED_FADE_MAX)
		end
		return 0
	end
	return seconds
end

local function applyProps(instance: Instance, props: { [string]: any })
	for key, value in props do
		(instance :: any)[key] = value
	end
end

--- Tweens `props` on `instance`. Returns the playing Tween, or nil when the change was applied instantly
--- (zero duration, e.g. under reduced motion).
function Motion.tween(instance: Instance, props: { [string]: any }, spec: Spec?): Tween?
	local opts: Spec = spec or {}
	local duration = Motion.resolveDuration(opts.duration, opts.kind)
	local delay = math.max(opts.delay or 0, 0)
	if Motion.isReduced() and opts.kind ~= "fade" and opts.kind ~= "color" then
		delay = 0
	end
	if duration <= 0 and delay <= 0 then
		applyProps(instance, props)
		return nil
	end
	local style, direction = Theme.easing(opts.easing or "standard")
	local info = TweenInfo.new(duration, style, direction, opts.repeatCount or 0, opts.reverses == true, delay)
	local tween = Services.tween():Create(instance, info, props)
	tween:Play()
	return tween
end

local function transparencyProperty(instance: Instance): string?
	if instance:IsA("CanvasGroup") then
		return "GroupTransparency"
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		return "TextTransparency"
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return "ImageTransparency"
	elseif instance:IsA("GuiObject") then
		return "BackgroundTransparency"
	elseif instance:IsA("UIStroke") then
		return "Transparency"
	end
	return nil
end

--- Fades the instance's main transparency (GroupTransparency for CanvasGroups — use one to fade a whole panel).
function Motion.fade(instance: Instance, to: number, spec: Spec?): Tween?
	local property = transparencyProperty(instance)
	if property == nil then
		error(`Motion.fade: {instance.ClassName} has no transparency to fade`, 2)
	end
	local opts: Spec = if spec then table.clone(spec) else {}
	opts.kind = "fade"
	return Motion.tween(instance, { [property] = to }, opts)
end

function Motion.fadeIn(instance: Instance, spec: Spec?): Tween?
	local property = transparencyProperty(instance)
	if property == nil then
		error(`Motion.fadeIn: {instance.ClassName} has no transparency to fade`, 2)
	end
	local writable: any = instance
	writable[property] = 1
	return Motion.fade(instance, 0, spec)
end

function Motion.fadeOut(instance: Instance, spec: Spec?): Tween?
	return Motion.fade(instance, 1, spec)
end

local function offsetFor(direction: Direction, distance: number): UDim2
	if direction == "left" then
		return UDim2.fromOffset(-distance, 0)
	elseif direction == "right" then
		return UDim2.fromOffset(distance, 0)
	elseif direction == "top" then
		return UDim2.fromOffset(0, -distance)
	end
	return UDim2.fromOffset(0, distance)
end

--- Slides from `distance` px away (default 24, the toast/screen slide) to the current Position.
--- Reduced motion: no movement.
function Motion.slideIn(guiObject: GuiObject, from: Direction, distance: number?, spec: Spec?): Tween?
	local target = guiObject.Position
	if Motion.isReduced() then
		return nil
	end
	guiObject.Position = target + offsetFor(from, distance or 24)
	local opts: Spec = if spec then table.clone(spec) else {}
	opts.kind = "move"
	opts.easing = opts.easing or "enter"
	return Motion.tween(guiObject, { Position = target }, opts)
end

--- Slides `distance` px towards `to` from the current Position (instant under reduced motion).
function Motion.slideOut(guiObject: GuiObject, to: Direction, distance: number?, spec: Spec?): Tween?
	local opts: Spec = if spec then table.clone(spec) else {}
	opts.kind = "move"
	opts.easing = opts.easing or "exit"
	return Motion.tween(guiObject, { Position = guiObject.Position + offsetFor(to, distance or 24) }, opts)
end

--- The UIScale child Motion uses for pop/pulse (created on demand, named "MotionScale").
function Motion.scaleOf(guiObject: GuiObject): UIScale
	local existing = guiObject:FindFirstChild("MotionScale")
	if existing ~= nil and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MotionScale"
	scale.Scale = 1
	scale.Parent = guiObject
	return scale
end

--- Runs `fn` once when `tween` finishes (immediately when it is nil — applied instantly — or already finished).
function Motion.onComplete(tween: Tween?, fn: () -> ())
	if tween == nil then
		fn()
		return
	end
	local state = tween.PlaybackState
	if state == Enum.PlaybackState.Completed or state == Enum.PlaybackState.Cancelled then
		fn()
		return
	end
	tween.Completed:Once(function()
		fn()
	end)
end

--- Start scale of the modal `pop` entrance (ui-ux §1.3: scale 0.98 -> 1 + fade).
Motion.POP_FROM = 0.98

--- Small scale-up entrance (POP_FROM -> 1). Reduced motion: none.
function Motion.pop(guiObject: GuiObject, spec: Spec?): Tween?
	if Motion.isReduced() then
		return nil
	end
	local scale = Motion.scaleOf(guiObject)
	scale.Scale = Motion.POP_FROM
	local opts: Spec = if spec then table.clone(spec) else {}
	opts.kind = "scale"
	opts.easing = opts.easing or "emphasized"
	opts.duration = opts.duration or "slow"
	return Motion.tween(scale, { Scale = 1 }, opts)
end

--- Gentle repeating pulse (scale 1 <-> 1.04, ~0.9 s period) for attention states. Returns stop().
--- Reduced motion: no pulse.
function Motion.pulse(guiObject: GuiObject, spec: Spec?): () -> ()
	if Motion.isReduced() then
		return function() end
	end
	local scale = Motion.scaleOf(guiObject)
	local opts: Spec = if spec then table.clone(spec) else {}
	opts.kind = "scale"
	opts.duration = opts.duration or "focusPulse"
	opts.easing = opts.easing or "linear"
	opts.repeatCount = -1
	opts.reverses = true
	local tween = Motion.tween(scale, { Scale = 1.04 }, opts)
	return function()
		if tween ~= nil then
			tween:Cancel()
		end
		scale.Scale = 1
	end
end

--- Runs `step(dt)` every Heartbeat until it returns true or stop() is called.
function Motion.loop(step: (dt: number) -> boolean?): () -> ()
	local connection: RBXScriptConnection? = nil
	local stopped = false
	local function stop()
		stopped = true
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
	end
	connection = Services.run().Heartbeat:Connect(function(dt: number)
		if stopped then
			return
		end
		local ok, done = pcall(step, dt)
		if not ok then
			log:error("loop step failed: %s", tostring(done))
			stop()
		elseif done == true then
			stop()
		end
	end)
	if stopped and connection ~= nil then
		(connection :: RBXScriptConnection):Disconnect()
	end
	return stop
end

--- Short horizontal shake for errors (amplitude px, default 6; 0.3 s decaying). Reduced motion: none.
function Motion.shake(guiObject: GuiObject, amplitude: number?, duration: number?): () -> ()
	if Motion.isReduced() then
		return function() end
	end
	local origin = guiObject.Position
	local amp = amplitude or 6
	local total = duration or 0.3
	local elapsed = 0
	local stopLoop = Motion.loop(function(dt: number): boolean?
		elapsed += dt
		if elapsed >= total then
			guiObject.Position = origin
			return true
		end
		local decay = 1 - elapsed / total
		local offset = math.sin(elapsed * 2 * math.pi * 12) * amp * decay
		guiObject.Position = origin + UDim2.fromOffset(math.floor(offset + 0.5), 0)
		return nil
	end)
	return function()
		stopLoop()
		guiObject.Position = origin
	end
end

--------------------------------------------------------------------------------
-- Easing and number animation
--------------------------------------------------------------------------------

local function easeIn(name: string, t: number): number
	if name == "Linear" then
		return t
	elseif name == "Quad" then
		return t * t
	elseif name == "Cubic" then
		return t * t * t
	elseif name == "Quart" then
		return t * t * t * t
	elseif name == "Quint" then
		return t * t * t * t * t
	elseif name == "Sine" then
		return 1 - math.cos(t * math.pi / 2)
	elseif name == "Exponential" then
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	elseif name == "Circular" then
		return 1 - math.sqrt(1 - t * t)
	end
	return t
end

--- Pure easing: `alpha` in [0,1] -> eased progress for an Enum.EasingStyle name and direction name.
function Motion.ease(alpha: number, style: string?, direction: string?): number
	local t = math.clamp(alpha, 0, 1)
	local name = style or "Quad"
	local dir = direction or "Out"
	if dir == "In" then
		return easeIn(name, t)
	elseif dir == "Out" then
		return 1 - easeIn(name, 1 - t)
	end
	if t < 0.5 then
		return easeIn(name, t * 2) / 2
	end
	return 1 - easeIn(name, (1 - t) * 2) / 2
end

--- Animates a number from `from` to `to`, calling `onStep(value)` each frame and `onStep(to)` at the end.
--- Default duration "countUp" (0.6 s), Quad Out. Reduced motion: one call with `to`. Returns stop().
function Motion.countUp(from: number, to: number, onStep: (value: number) -> (), spec: Spec?): () -> ()
	local opts: Spec = spec or {}
	local duration = Motion.resolveDuration(opts.duration or "countUp", "move")
	if duration <= 0 or from == to then
		onStep(to)
		return function() end
	end
	local style, direction = "Quad", "Out"
	if opts.easing ~= nil then
		local s, d = Theme.easing(opts.easing)
		style, direction = s.Name, d.Name
	end
	local elapsed = 0
	onStep(from)
	return Motion.loop(function(dt: number): boolean?
		elapsed += dt
		if elapsed >= duration then
			onStep(to)
			return true
		end
		onStep(from + (to - from) * Motion.ease(elapsed / duration, style, direction))
		return nil
	end)
end

--- One semi-implicit Euler spring step (sub-stepped for stability). Returns (position, velocity).
function Motion.springStep(
	position: number,
	velocity: number,
	target: number,
	frequency: number,
	damping: number,
	dt: number
): (number, number)
	local omega = 2 * math.pi * frequency
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	local x, v = position, velocity
	for _ = 1, steps do
		local acceleration = omega * omega * (target - x) - 2 * damping * omega * v
		v += acceleration * h
		x += v * h
	end
	return x, v
end

--- Spring-smoothed copy of a numeric State (HP bars draining, gauges). Snaps under reduced motion. The returned
--- State and its Heartbeat loop live until `scope` is cleaned.
function Motion.follow(source: State<number>, scope: Trove, options: FollowOptions?): State<number>
	local opts: FollowOptions = options or {}
	local frequency = opts.frequency or 4
	local damping = opts.damping or 1
	local value = State.Value(source:peek(), { scope = scope })
	local velocity = 0
	local stopLoop: (() -> ())? = nil

	local function stop()
		if stopLoop ~= nil then
			local fn = stopLoop
			stopLoop = nil
			fn()
		end
	end

	local function start()
		if stopLoop ~= nil then
			return
		end
		stopLoop = Motion.loop(function(dt: number): boolean?
			local target = source:peek()
			if Motion.isReduced() then
				value:set(target)
				velocity = 0
				stopLoop = nil
				return true
			end
			local x, v = Motion.springStep(value:peek(), velocity, target, frequency, damping, dt)
			if math.abs(target - x) < 1e-3 and math.abs(v) < 1e-3 then
				value:set(target)
				velocity = 0
				stopLoop = nil
				return true
			end
			velocity = v
			value:set(x)
			return nil
		end)
	end

	State.observe(source, function(target: number)
		if Motion.isReduced() then
			stop()
			velocity = 0
			value:set(target)
			return
		end
		start()
	end, { scope = scope })
	scope:Add(stop)
	return value
end

return Motion
