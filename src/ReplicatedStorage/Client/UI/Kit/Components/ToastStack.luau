--!strict
--[[
	Components/ToastStack — a column of toasts: max 3, newest on top, timed dismissal, slide in/out.

	Purpose:          `ToastStack.new({ parent })` (or the shared `ToastStack.default()` in the Toasts layer) shows
	                  toasts top-right under the top bar (ui-ux §1.5: x 1536–1896, from y 72). Each toast slides in
	                  24 px from the right over 160 ms (brand-art §8.1), holds 4 s (8 s with an action; any `duration`,
	                  e.g. 30 s invites; paused while the pointer is over it), then leaves in 120 ms and is destroyed.
	                  A 4th toast first evicts the oldest toast without an action (then the oldest with one); a `key`
	                  replaces the toast with the same key. ui_notification plays at most once per 1.5 s. Timers run on Heartbeat (Motion.loop) so tests can step
	                  them.
	Dependencies:     Kit/Create, Kit/Theme, Kit/Layout, Kit/Layers, Kit/Motion, Kit/Sound, Components/Toast,
	                  Core/Log.
	State:            Live toasts (id -> record) and one Heartbeat loop while any timed toast is alive.
	Validation:       max is clamped to 1..6.
	Error handling:   The default stack logs once when there is no Toasts layer.
	Performance notes: One loop per stack, stopped when empty.
]]

local Create = require("../Create")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Layers = require("../Layers")
local Motion = require("../Motion")
local Sound = require("../Sound")
local Toast = require("./Toast")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

export type Options = {
	parent: Instance?,
	max: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
}

export type Stack = {
	frame: Frame,
	push: (self: Stack, spec: Toast.Spec) -> number,
	dismiss: (self: Stack, id: number) -> (),
	clear: (self: Stack) -> (),
	--- Live toast ids, oldest first.
	ids: (self: Stack) -> { number },
	count: (self: Stack) -> number,
	destroy: (self: Stack) -> (),
}

type Record = {
	id: number,
	key: string?,
	hasAction: boolean,
	slot: Frame,
	card: TextButton,
	hold: number?,
	elapsed: number,
	hovered: boolean,
	leaving: boolean,
}

local log = Log.scope("UI.ToastStack")

local ToastStack = {}

ToastStack.MAX = 3
ToastStack.SLIDE = 24
--- At most one ui_notification per this many seconds; batched toasts share one (ui-ux §1.16).
ToastStack.SOUND_GAP = 1.5

local soundClock: () -> number = os.clock
local lastSoundAt = -math.huge

--- Replaces the clock of the notification-sound rate limit (tests). nil restores os.clock.
function ToastStack.setClock(fn: (() -> number)?)
	soundClock = fn or os.clock
	lastSoundAt = -math.huge
end

local function playSound(sound: (boolean | string)?)
	if sound == false then
		return
	end
	if type(sound) == "string" then
		Sound.play(sound)
		return
	end
	local now = soundClock()
	if now - lastSoundAt < ToastStack.SOUND_GAP then
		return
	end
	lastSoundAt = now
	Sound.play(Sound.KEYS.notification)
end

export type LiveToast = { id: number, action: boolean }

--- Pure: ids to evict so one more toast fits in `max` (`live` oldest first): the oldest toasts without an action
--- go first, then the oldest with one.
function ToastStack.evictions(live: { LiveToast }, max: number): { number }
	local out = {}
	local excess = #live + 1 - max
	if excess <= 0 then
		return out
	end
	for _, pass in { false, true } do
		for _, toast in live do
			if #out < excess and toast.action == pass then
				table.insert(out, toast.id)
			end
		end
	end
	return out
end

function ToastStack.new(options: Options?): Stack
	local opts: Options = options or {}
	local max = math.clamp(math.floor(opts.max or ToastStack.MAX), 1, 6)
	local frame = Create.Frame({
		Name = "ToastStack",
		BackgroundTransparency = 1,
		AnchorPoint = opts.anchorPoint or Vector2.new(1, 0),
		Position = opts.position or UDim2.new(1, -Theme.space(5), 0, 72),
		Size = UDim2.new(0, Theme.sizes.toastWidth, 1, -72),
		ZIndex = Theme.z("top"),
		[Create.Children] = {
			Layout.list({ gap = Theme.space(2) }),
		},
		Parent = opts.parent,
	})
	local records: { Record } = {}
	local nextId = 0
	local stopLoop: (() -> ())? = nil
	local destroyed = false

	local function find(id: number): (number?, Record?)
		for i, record in records do
			if record.id == id then
				return i, record
			end
		end
		return nil, nil
	end

	local function remove(record: Record)
		local index = find(record.id)
		if index ~= nil then
			table.remove(records, index)
		end
		record.slot:Destroy()
	end

	local function leave(record: Record)
		if record.leaving then
			return
		end
		record.leaving = true
		local tween = Motion.slideOut(record.card, "right", ToastStack.SLIDE, { duration = "fast" })
		Motion.onComplete(tween, function()
			remove(record)
		end)
	end

	local stack = {} :: Stack
	stack.frame = frame

	local function ensureLoop()
		if stopLoop ~= nil or destroyed then
			return
		end
		stopLoop = Motion.loop(function(dt: number): boolean?
			local anyTimed = false
			-- Backwards by index: leave() may remove a record synchronously (reduced motion = instant slide-out), and
			-- a per-frame table.clone would allocate every Heartbeat while a toast is up.
			for i = #records, 1, -1 do
				local record = records[i]
				if record ~= nil and record.hold ~= nil and not record.leaving then
					anyTimed = true
					if not record.hovered then
						record.elapsed += dt
					end
					if record.elapsed >= (record.hold :: number) then
						leave(record)
					end
				end
			end
			if not anyTimed then
				stopLoop = nil
				return true
			end
			return nil
		end)
	end

	function stack.push(self: Stack, spec: Toast.Spec): number
		if destroyed then
			error("ToastStack: push after destroy", 2)
		end
		if spec.key ~= nil then
			for _, record in table.clone(records) do
				if record.key == spec.key and not record.leaving then
					remove(record)
				end
			end
		end
		local live: { LiveToast } = {}
		for _, record in records do
			if not record.leaving then
				table.insert(live, { id = record.id, action = record.hasAction })
			end
		end
		for _, id in ToastStack.evictions(live, max) do
			local _, record = find(id)
			if record ~= nil then
				remove(record)
			end
		end
		nextId += 1
		local id = nextId
		local record: Record
		local card = Toast.new(spec, function()
			self:dismiss(id)
		end)
		local slot = Create.Frame({
			Name = "Toast_" .. id,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(Theme.sizes.toastWidth, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = -id,
			[Create.Children] = { card },
		})
		record = {
			id = id,
			key = spec.key,
			hasAction = spec.action ~= nil,
			slot = slot,
			card = card,
			hold = Toast.holdFor(spec),
			elapsed = 0,
			hovered = false,
			leaving = false,
		}
		card.MouseEnter:Connect(function()
			record.hovered = true
		end)
		card.MouseLeave:Connect(function()
			record.hovered = false
		end)
		table.insert(records, record)
		slot.Parent = frame
		Motion.slideIn(card, "right", ToastStack.SLIDE, { duration = "toast" })
		playSound(spec.sound)
		if record.hold ~= nil then
			ensureLoop()
		end
		return id
	end

	function stack.dismiss(_self: Stack, id: number)
		local _, record = find(id)
		if record ~= nil then
			leave(record)
		end
	end

	function stack.clear(_self: Stack)
		for _, record in table.clone(records) do
			remove(record)
		end
	end

	function stack.ids(_self: Stack): { number }
		local out = {}
		for _, record in records do
			table.insert(out, record.id)
		end
		return out
	end

	function stack.count(_self: Stack): number
		return #records
	end

	function stack.destroy(self: Stack)
		if destroyed then
			return
		end
		self:clear()
		destroyed = true
		if stopLoop ~= nil then
			stopLoop()
			stopLoop = nil
		end
		frame:Destroy()
	end

	frame.Destroying:Connect(function()
		if not destroyed then
			destroyed = true
			if stopLoop ~= nil then
				stopLoop()
				stopLoop = nil
			end
		end
	end)
	return stack
end

local defaultStack: Stack? = nil
local warned = false

--- The shared stack in the registered Toasts layer (re-created if that layer changed). nil without a layer.
function ToastStack.default(): Stack?
	local parent = Layers.parentFor("Toasts")
	if parent == nil then
		if not warned then
			warned = true
			log:warn("no Toasts layer registered; toast dropped (create a Kit Router first)")
		end
		return nil
	end
	local current = defaultStack
	if current ~= nil and current.frame.Parent == parent then
		return current
	end
	if current ~= nil then
		current:destroy()
	end
	local created = ToastStack.new({ parent = parent })
	defaultStack = created
	return created
end

return ToastStack
