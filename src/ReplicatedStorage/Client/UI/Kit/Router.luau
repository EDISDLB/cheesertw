--!strict
--[[
	Kit/Router — screen registry, navigation stack, modal layer, transitions, Back handling and deep links.

	Purpose:          Owns the UI layers (one ScreenGui per layer, ui-ux §1.1: Background3D, HUD, HUDInput, Screens,
	                  TopBar, Modals, Toasts, Tooltip, Debug — DisplayOrder from Theme, ResetOnSpawn off, Sibling
	                  ZIndex, SafeAreaCompatibility None; CoreUISafeInsets for interactive layers, TopbarSafeInsets for
	                  TopBar, DeviceSafeInsets for the HUD gauges, None + IgnoreGuiInset for Background3D/Debug) with a
	                  scaled Layout root each (HUD and HUDInput use the battle HUD scale), and a stack of screens. A screen module is `{ new(ctx) -> Screen }`;
	                  Screen = { mount(parent), show(params, info), hide(), destroy(), onBack()? }. push/pop/replace/
	                  reset/openModal/closeModal/back/navigate drive the lifecycle:
	                    create (new) -> mount (once, into a host Frame) -> show (each time it becomes visible)
	                    -> hide (covered by a full screen, or popped) -> destroy (popped/reset, unless keepAlive).
	                  Modals stay above the screen beneath (which keeps rendering) with a scrim and a trapped focus
	                  scope. Back (gamepad B / Backspace via Kit/UIInput; Esc is reserved by Roblox) asks the top screen's
	                  onBack first, then closes the top modal or pops; at the root it fires `rootBack` / calls
	                  `onRootBack` (the Garage opens the Game menu, ui-ux §1.2). Exits are cuts: the revealed screen
	                  plays its "return" entrance; the modal scrim fades out.
	Dependencies:     Kit/State, Kit/Create, Kit/Theme, Kit/Layout, Kit/Motion, Kit/Focus, Kit/UIInput, Kit/Layers,
	                  Kit/Sound, Kit/Services, Core/Signal, Core/Trove, Core/Log.
	State:            Registry (name -> module/options), stack of entries, keep-alive cache, layer ScreenGuis.
	Validation:       Unknown screen names raise in push/replace/reset; navigate() returns false for bad links.
	Error handling:   Screen callbacks run under pcall: a failing new/mount aborts the push (returns false, logs);
	                  failing show/hide/destroy/onBack are logged and navigation continues.
	Performance notes: Hidden screens keep their instances only while on the stack (or keepAlive); covered full
	                  screens are Visible=false (no render, no input). One veil Frame per transition.
]]

local State = require("./State")
local Create = require("./Create")
local Theme = require("./Theme")
local Layout = require("./Layout")
local Motion = require("./Motion")
local Focus = require("./Focus")
local UIInput = require("./UIInput")
local Layers = require("./Layers")
local Sound = require("./Sound")
local Services = require("./Services")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

type Trove = Trove.Trove
type Layer = Theme.Layer

export type ShowReason = "push" | "return" | "replace" | "reset"
export type ShowInfo = { reason: ShowReason, previous: string? }

export type ScreenContext = {
	router: Router,
	name: string,
	layer: Layer,
	--- Params of the latest show (reactive: bind to it or read it in show()).
	params: State.Value<any>,
	--- Destroyed with the screen instance (put connections, states and instances here).
	scope: Trove,
	--- App-wide context passed to Router.new (controllers, client store, net...).
	app: any,
	--- Screen-level KitUI action (Secondary X/F, Tertiary Y/G, ...): `ctx.on("Secondary", openDetails)`. Fires only
	--- while this screen is the active one — the top of the stack and the owner of gamepad focus (not covered by a
	--- drill-in, a modal, a Modal.open dialog or an open dropdown; its own drawers count as the screen). Lives as long
	--- as the screen (ctx.scope).
	on: (name: UIInput.ActionName, fn: () -> ()) -> Signal.Connection,
	--- True while this screen is the active one (see `on`).
	isActive: () -> boolean,
}

--- The interface screens implement (self is `any` so any class shape fits).
export type Screen = {
	mount: (self: any, parent: GuiObject) -> (),
	show: (self: any, params: any, info: ShowInfo) -> (),
	hide: (self: any) -> (),
	destroy: (self: any) -> (),
	--- Return true when handled (e.g. closed an inner drawer) so the router does not pop.
	onBack: ((self: any) -> boolean?)?,
	--- Element to focus first for gamepads (else the first selectable).
	initialFocus: ((self: any) -> GuiObject?)?,
	--- LB/RB handler (tab bars).
	onShoulder: ((self: any, direction: number) -> ())?,
	--- LT/RT handler; replaces the default scroll paging (e.g. tech-tree zoom).
	onPage: ((self: any, direction: number) -> ())?,
}

export type ScreenModule = { new: (ctx: ScreenContext) -> Screen }

export type ScreenOptions = {
	--- Parent layer (default "Screens"; modals default to "Modals").
	layer: Layer?,
	--- Modal: shown above the current screen with a scrim and a trapped focus scope.
	modal: boolean?,
	--- Modal only: Back / scrim click closes it (default true).
	dismissible: boolean?,
	--- Keep the instance after pop and reuse it on the next push (expensive screens: garage, tech tree).
	keepAlive: boolean?,
	--- Entrance transition (default: "slide" for pushed drill-ins, "fade" when the screen is the `reset` root, "pop" for
	--- modals; "sheet" slides a Compact modal up). Register rail sections with "fade" (ui-ux §1.3: sections never slide).
	transition: ("slide" | "fade" | "pop" | "sheet" | "none")?,
	--- Manage gamepad focus (default true).
	focus: boolean?,
	--- Right stick scrolls the focused region (default true; false on screens where it orbits the camera).
	stickScroll: boolean?,
}

export type Entry = {
	name: string,
	params: any,
	modal: boolean,
}

export type RouterOptions = {
	--- Where the layer ScreenGuis go (default LocalPlayer.PlayerGui).
	parent: Instance?,
	--- Passed to every screen as ctx.app.
	app: any?,
	--- Prefix for ScreenGui names (default "Kit").
	name: string?,
	--- Signal that triggers back() (default Kit/UIInput.back). Pass false to disable.
	backSignal: any?,
	--- Register the layer roots in Kit/Layers (default true).
	registerLayers: boolean?,
	--- Called when Back reaches the root screen with nothing to close (open the Game menu, ui-ux §1.2).
	onRootBack: (() -> ())?,
}

export type Link = { screens: { string }, params: { [string]: any } }

export type Router = {
	--- Fires (current, previous) after every navigation (names of the top entry, modals included).
	changed: Signal.Signal<string?, string?>,
	--- Fires (root screen name) when Back has nothing left to close or pop.
	rootBack: Signal.Signal<string>,
	register: (self: Router, name: string, module: ScreenModule, options: ScreenOptions?) -> (),
	isRegistered: (self: Router, name: string) -> boolean,
	push: (self: Router, name: string, params: any?) -> boolean,
	pop: (self: Router) -> boolean,
	replace: (self: Router, name: string, params: any?) -> boolean,
	reset: (self: Router, name: string, params: any?) -> boolean,
	openModal: (self: Router, name: string, params: any?) -> boolean,
	closeModal: (self: Router) -> boolean,
	closeAllModals: (self: Router) -> (),
	back: (self: Router) -> boolean,
	navigate: (self: Router, link: string) -> boolean,
	current: (self: Router) -> Entry?,
	currentScreen: (self: Router) -> Entry?,
	history: (self: Router) -> { string },
	depth: (self: Router) -> number,
	canGoBack: (self: Router) -> boolean,
	layer: (self: Router, name: Layer) -> ScreenGui,
	layerRoot: (self: Router, name: Layer) -> Frame,
	screenOf: (self: Router, name: string) -> Screen?,
	destroy: (self: Router) -> (),
}

local log = Log.scope("UI.Router")

local LAYERS: { Layer } =
	{ "Background3D", "HUD", "HUDInput", "Screens", "TopBar", "Modals", "Toasts", "Tooltip", "Debug" }
local NON_INTERACTIVE: { [string]: boolean } = { Background3D = true, Debug = true }

-- (ScreenInsets, IgnoreGuiInset, TV safe-area padding) for a layer (ui-ux §1.1).
local function layerInsets(name: string): (Enum.ScreenInsets, boolean, boolean)
	if NON_INTERACTIVE[name] then
		return Enum.ScreenInsets.None, true, false
	elseif name == "HUD" then
		-- Gauges clear notches but may use the top-bar row; touch controls live in HUDInput.
		return Enum.ScreenInsets.DeviceSafeInsets, true, true
	elseif name == "TopBar" then
		-- The top-bar row is already inside the engine's safe area; no extra TV margin there.
		return Enum.ScreenInsets.TopbarSafeInsets, false, false
	end
	return Enum.ScreenInsets.CoreUISafeInsets, false, true
end

type Registration = { module: ScreenModule, options: ScreenOptions }

type EntryImpl = {
	name: string,
	params: any,
	modal: boolean,
	options: ScreenOptions,
	screen: Screen,
	host: Frame,
	ctx: ScreenContext,
	scope: Trove,
	focus: Focus.FocusScope?,
	visible: boolean,
}

type RouterImpl = {
	changed: Signal.Signal<string?, string?>,
	rootBack: Signal.Signal<string>,
	_onRootBack: (() -> ())?,
	_scrimToken: number,
	_registry: { [string]: Registration },
	_stack: { EntryImpl },
	_alive: { [string]: EntryImpl },
	_guis: { [string]: ScreenGui },
	_roots: { [string]: Frame },
	_scrim: TextButton,
	_app: any,
	_trove: Trove,
	_destroyed: boolean,
	_registerLayers: boolean,
}

local RouterClass = {}
RouterClass.__index = RouterClass

local Router = {}

local function safe(what: string, name: string, fn: (...any) -> ...any, ...: any): (boolean, any)
	local ok, result = pcall(fn, ...)
	if not ok then
		log:error("%s of screen %s failed: %s", what, name, tostring(result))
	end
	return ok, result
end

--------------------------------------------------------------------------------
-- Deep links (pure)
--------------------------------------------------------------------------------

local function decodeComponent(text: string): string
	local plusDecoded = string.gsub(text, "+", " ")
	local decoded = string.gsub(plusDecoded, "%%(%x%x)", function(hex: string): string
		return string.char(tonumber(hex, 16) :: number)
	end)
	return decoded
end

local function convertValue(text: string): any
	if text == "true" then
		return true
	elseif text == "false" then
		return false
	end
	local number = tonumber(text)
	if number ~= nil and string.match(text, "^%-?%d+%.?%d*$") then
		return number
	end
	return text
end

--- Parses "Garage/TechTree?faction=iron_union&tier=5" -> { screens = { "Garage", "TechTree" }, params = { faction =
--- "iron_union", tier = 5 } }. Numbers and true/false are converted; %XX and + are decoded. nil if malformed.
function Router.parseLink(link: string): Link?
	if type(link) ~= "string" or link == "" then
		return nil
	end
	local path, query = string.match(link, "^([^?]*)%??(.*)$")
	if path == nil then
		return nil
	end
	local screens: { string } = {}
	for segment in string.gmatch(path, "[^/]+") do
		if not string.match(segment, "^[%w_]+$") then
			return nil
		end
		table.insert(screens, segment)
	end
	if #screens == 0 then
		return nil
	end
	local params: { [string]: any } = {}
	if query ~= nil and query ~= "" then
		for pair in string.gmatch(query, "[^&]+") do
			local key, value = string.match(pair, "^([^=]+)=?(.*)$")
			if key == nil then
				return nil
			end
			params[decodeComponent(key)] = convertValue(decodeComponent(value or ""))
		end
	end
	return { screens = screens, params = params }
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function createLayer(self: RouterImpl, name: Layer, parent: Instance?, prefix: string)
	local insets, ignoreInset, safeArea = layerInsets(name)
	local gui = Create.ScreenGui({
		Name = `{prefix}_{name}`,
		DisplayOrder = Theme.layer(name),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
	})
	-- IgnoreGuiInset and ScreenInsets are coupled in the engine (writing one updates the other), so they are written
	-- in a fixed order with ScreenInsets last instead of through a props table (hash order is unspecified).
	gui.IgnoreGuiInset = ignoreInset
	gui.ScreenInsets = insets
	-- Battle HUD layers scale with `hud.scale` (Layout.state.hudScale), never with the menu UI scale (ui-ux §1.1.1).
	local hudLayer = name == "HUD" or name == "HUDInput"
	local root = Layout.root({ Name = "Root", safeArea = safeArea, scale = if hudLayer then "hud" else "menu" })
	root.Parent = gui
	gui.Parent = parent
	self._guis[name] = gui
	self._roots[name] = root
	self._trove:Add(gui)
	if self._registerLayers then
		Layers.register(name, root)
		self._trove:Add(function()
			Layers.unregister(name, root)
		end)
	end
end

--- Creates a router with its layers. Call `router:destroy()` to remove everything.
function Router.new(options: RouterOptions?): Router
	local opts: RouterOptions = options or {}
	local self: RouterImpl = setmetatable({
		changed = Signal.new(),
		rootBack = Signal.new(),
		_onRootBack = opts.onRootBack,
		_scrimToken = 0,
		_registry = {},
		_stack = {},
		_alive = {},
		_guis = {},
		_roots = {},
		_scrim = nil :: any,
		_app = opts.app,
		_trove = Trove.new(),
		_destroyed = false,
		_registerLayers = opts.registerLayers ~= false,
	}, RouterClass) :: any
	local parent = opts.parent or Services.playerGui()
	local prefix = opts.name or "Kit"
	for _, name in LAYERS do
		createLayer(self, name :: Layer, parent, prefix)
	end
	self._scrim = Create.TextButton({
		Name = "Scrim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Visible = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color("bg.scrim"),
		BackgroundTransparency = Theme.tokenTransparency("bg.scrim"),
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = self._roots.Modals,
		[Create.On("Activated")] = function()
			local top = self._stack[#self._stack]
			if top ~= nil and top.modal and top.options.dismissible ~= false then
				RouterClass.closeModal(self)
			end
		end,
	})
	local backSignal = if opts.backSignal == nil then UIInput.back else opts.backSignal
	if backSignal then
		self._trove:Connect(backSignal, function()
			RouterClass.back(self)
		end)
	end
	return (self :: any) :: Router
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

function RouterClass.register(self: RouterImpl, name: string, module: ScreenModule, options: ScreenOptions?)
	if type(name) ~= "string" or not string.match(name, "^[%w_]+$") then
		error(`Router:register: invalid screen name "{tostring(name)}"`, 2)
	end
	if type(module) ~= "table" or type(module.new) ~= "function" then
		error(`Router:register: screen "{name}" must be a module with new(ctx)`, 2)
	end
	local opts: ScreenOptions = if options then table.clone(options) else {}
	if opts.modal then
		opts.layer = opts.layer or "Modals"
	end
	opts.layer = opts.layer or "Screens"
	self._registry[name] = { module = module, options = opts }
end

function RouterClass.isRegistered(self: RouterImpl, name: string): boolean
	return self._registry[name] ~= nil
end

--------------------------------------------------------------------------------
-- Entry lifecycle helpers
--------------------------------------------------------------------------------

local function topEntry(self: RouterImpl): EntryImpl?
	return self._stack[#self._stack]
end

local function topName(self: RouterImpl): string?
	local top = topEntry(self)
	return if top then top.name else nil
end

local function updateScrim(self: RouterImpl)
	local topModal: EntryImpl? = nil
	for i = #self._stack, 1, -1 do
		local entry = self._stack[i]
		if entry.modal then
			topModal = entry
			break
		end
	end
	local scrim = self._scrim
	self._scrimToken += 1
	local token = self._scrimToken
	if topModal == nil then
		if scrim.Visible then
			-- Fade out, then hide (unless a modal opened meanwhile).
			local tween = Motion.tween(scrim, { BackgroundTransparency = 1 }, { duration = "fast", kind = "fade" })
			Motion.onComplete(tween, function()
				if self._scrimToken == token then
					scrim.Visible = false
				end
			end)
		end
		return
	end
	scrim.ZIndex = topModal.host.ZIndex - 1
	if not scrim.Visible or scrim.BackgroundTransparency >= 1 then
		scrim.Visible = true
		scrim.BackgroundTransparency = 1
		Motion.tween(
			scrim,
			{ BackgroundTransparency = Theme.tokenTransparency("bg.scrim"):peek() },
			{ duration = "base", kind = "fade" }
		)
	end
end

--- Pure: the entrance transition for an entry (ui-ux §1.3): the registered one, else modals pop, a root `reset`
--- fades (roots and sections never slide) and pushed drill-ins slide.
function Router.transitionFor(options: ScreenOptions, modal: boolean, reason: ShowReason): string
	if options.transition ~= nil then
		return options.transition
	elseif modal then
		return "pop"
	elseif reason == "reset" then
		return "fade"
	end
	return "slide"
end

local function playEntrance(entry: EntryImpl, reason: ShowReason)
	local transition = Router.transitionFor(entry.options, entry.modal, reason)
	if transition == "none" then
		return
	end
	if transition == "pop" then
		Motion.pop(entry.host, { duration = "base" })
		return
	end
	if transition == "sheet" then
		entry.host.Position = UDim2.new()
		Motion.slideIn(entry.host, "bottom", 64, { duration = "slow" })
		return
	end
	-- Veil: a full-size bg.base frame fading out over the incoming screen (fades without a CanvasGroup).
	local veil = Create.Frame({
		Name = "TransitionVeil",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color("bg.base"),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = Theme.z("top") * 10,
		Parent = entry.host,
	})
	local tween = Motion.tween(veil, { BackgroundTransparency = 1 }, { duration = "slow", kind = "fade" })
	Motion.onComplete(tween, function()
		veil:Destroy()
	end)
	if transition == "slide" then
		entry.host.Position = UDim2.new()
		Motion.slideIn(entry.host, if reason == "return" then "left" else "right", 24, { duration = "base" })
	end
end

local function showEntry(_self: RouterImpl, entry: EntryImpl, reason: ShowReason, previous: string?)
	entry.ctx.params:set(entry.params, true)
	entry.host.Visible = true
	entry.visible = true
	safe("show", entry.name, entry.screen.show, entry.screen, entry.params, { reason = reason, previous = previous })
	playEntrance(entry, reason)
	if entry.focus ~= nil then
		(entry.focus :: Focus.FocusScope):activate()
	end
end

local function hideEntry(entry: EntryImpl)
	if not entry.visible then
		return
	end
	entry.visible = false
	safe("hide", entry.name, entry.screen.hide, entry.screen)
	entry.host.Visible = false
end

local function destroyEntry(self: RouterImpl, entry: EntryImpl)
	hideEntry(entry)
	if entry.focus ~= nil then
		(entry.focus :: Focus.FocusScope):Destroy()
		entry.focus = nil
	end
	if entry.options.keepAlive and not self._destroyed then
		local cached = self._alive[entry.name]
		if cached == nil or cached == entry then
			self._alive[entry.name] = entry
			return
		end
		-- One cached instance per name: a keepAlive screen pushed while already on the stack has a second instance;
		-- keep the one already cached and really destroy this one (overwriting the cache would leak the other).
	end
	if self._alive[entry.name] == entry then
		self._alive[entry.name] = nil
	end
	safe("destroy", entry.name, entry.screen.destroy, entry.screen)
	entry.scope:Destroy()
	entry.host:Destroy()
end

local function makeFocusScope(entry: EntryImpl): Focus.FocusScope?
	if entry.options.focus == false then
		return nil
	end
	local screen = entry.screen
	return Focus.scope(entry.host, {
		name = entry.name,
		trap = entry.modal,
		stickScroll = entry.options.stickScroll,
		initial = function(): GuiObject?
			local initialFocus = screen.initialFocus
			if initialFocus == nil then
				return nil
			end
			local ok, result = pcall(initialFocus, screen)
			return if ok then result else nil
		end,
		-- Only screens that define onShoulder get a scope handler: otherwise LB/RB must fall through to the TabBar
		-- registered inside the screen (Focus.registerShoulder), which a no-op wrapper would shadow.
		onShoulder = if screen.onShoulder ~= nil
			then function(direction: number)
				local handler = screen.onShoulder
				if handler ~= nil then
					handler(screen, direction)
				end
			end
			else nil,
		onPage = if screen.onPage ~= nil
			then function(direction: number)
				local handler = screen.onPage
				if handler ~= nil then
					handler(screen, direction)
				end
			end
			else nil,
	})
end

local function createEntry(self: RouterImpl, name: string, params: any): EntryImpl?
	local registration = self._registry[name]
	if registration == nil then
		error(`Router: unknown screen "{name}"`, 3)
	end
	local options = registration.options
	local modal = options.modal == true
	local cached = self._alive[name]
	if cached ~= nil then
		self._alive[name] = nil
		cached.params = params
		cached.focus = makeFocusScope(cached)
		return cached
	end
	local layer: Layer = options.layer :: any
	local layerRoot = self._roots[layer]
	local modalCount = 0
	for _, entry in self._stack do
		if entry.modal then
			modalCount += 1
		end
	end
	local host = Create.Frame({
		Name = "Screen_" .. name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = if modal then 10 + 2 * (modalCount + 1) else 2,
		Parent = layerRoot,
	})
	local scope = Trove.new()
	local router = (self :: any) :: Router
	-- The entry this context belongs to (set below, once the screen is built).
	local owner: EntryImpl? = nil
	local function isActive(): boolean
		local current = owner
		if current == nil or topEntry(self) ~= current or not current.visible then
			return false
		end
		-- A self-managed overlay in another layer (Modal.open, a Dropdown list) owns input while open; a scope inside
		-- the screen itself (a drawer) is still this screen.
		local focusScope = current.focus
		local top = Focus.top()
		return focusScope == nil or top == nil or top == focusScope or Focus.contains(current.host, top.root)
	end
	local ctx: ScreenContext = {
		router = router,
		name = name,
		layer = layer,
		params = State.Value(params, { scope = scope }),
		scope = scope,
		app = self._app,
		on = function(actionName: UIInput.ActionName, fn: () -> ()): Signal.Connection
			local connection = UIInput.on(actionName, function()
				if isActive() then
					fn()
				end
			end)
			scope:Add(connection)
			return connection
		end,
		isActive = isActive,
	}
	local okNew, screen = safe("new", name, registration.module.new, ctx)
	if not okNew or type(screen) ~= "table" then
		scope:Destroy()
		host:Destroy()
		return nil
	end
	local okMount = safe("mount", name, (screen :: Screen).mount, screen, host)
	if not okMount then
		safe("destroy", name, (screen :: Screen).destroy, screen)
		scope:Destroy()
		host:Destroy()
		return nil
	end
	local entry: EntryImpl = {
		name = name,
		params = params,
		modal = modal,
		options = options,
		screen = screen :: Screen,
		host = host,
		ctx = ctx,
		scope = scope,
		focus = nil,
		visible = false,
	}
	owner = entry
	entry.focus = makeFocusScope(entry)
	return entry
end

local function fireChanged(self: RouterImpl, previous: string?)
	local current = topName(self)
	if current ~= previous then
		self.changed:Fire(current, previous)
	end
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

function RouterClass.push(self: RouterImpl, name: string, params: any?): boolean
	if self._destroyed then
		return false
	end
	local previous = topName(self)
	local entry = createEntry(self, name, params)
	if entry == nil then
		return false
	end
	if not entry.modal then
		-- A full screen covers everything below it (including open modals of the previous screen).
		for _, below in ipairs(self._stack) do
			hideEntry(below)
		end
	end
	table.insert(self._stack, entry)
	updateScrim(self)
	showEntry(self, entry, "push", previous)
	if entry.modal then
		Sound.play(Sound.KEYS.open)
	end
	fireChanged(self, previous)
	return true
end

function RouterClass.openModal(self: RouterImpl, name: string, params: any?): boolean
	local registration = self._registry[name]
	if registration == nil then
		error(`Router: unknown screen "{name}"`, 2)
	end
	if not registration.options.modal then
		error(`Router:openModal: "{name}" is not registered as a modal`, 2)
	end
	return RouterClass.push(self, name, params)
end

-- Removes the top entry and reveals whatever it covered. `reveal` = show the entries that become visible.
local function popTop(self: RouterImpl, reveal: boolean): EntryImpl?
	local entry = table.remove(self._stack)
	if entry == nil then
		return nil
	end
	destroyEntry(self, entry)
	updateScrim(self)
	if reveal then
		-- Reveal from the last full screen upwards (modals above it stay visible).
		local firstVisible = #self._stack
		for i = #self._stack, 1, -1 do
			firstVisible = i
			if not self._stack[i].modal then
				break
			end
		end
		for i = firstVisible, #self._stack do
			local below = self._stack[i]
			if not below.visible then
				showEntry(self, below, "return", entry.name)
			end
		end
		local top = topEntry(self)
		if top ~= nil and top.focus ~= nil then
			Focus.push(top.focus :: Focus.FocusScope)
		end
	end
	return entry
end

function RouterClass.pop(self: RouterImpl): boolean
	local top = topEntry(self)
	if top == nil or self._destroyed then
		return false
	end
	if not top.modal and #self._stack <= 1 then
		return false
	end
	local previous = top.name
	popTop(self, true)
	Sound.play(if top.modal then Sound.KEYS.close else Sound.KEYS.back)
	fireChanged(self, previous)
	return true
end

function RouterClass.closeModal(self: RouterImpl): boolean
	local top = topEntry(self)
	if top == nil or not top.modal then
		return false
	end
	return RouterClass.pop(self)
end

function RouterClass.closeAllModals(self: RouterImpl)
	local previous = topName(self)
	local closed = false
	while true do
		local top = topEntry(self)
		if top == nil or not top.modal then
			break
		end
		popTop(self, false)
		closed = true
	end
	if closed then
		local top = topEntry(self)
		if top ~= nil then
			if not top.visible then
				showEntry(self, top, "return", previous)
			elseif top.focus ~= nil then
				Focus.push(top.focus :: Focus.FocusScope)
			end
		end
		fireChanged(self, previous)
	end
end

function RouterClass.replace(self: RouterImpl, name: string, params: any?): boolean
	if self._registry[name] == nil then
		error(`Router: unknown screen "{name}"`, 2)
	end
	local previous = topName(self)
	if #self._stack > 0 then
		popTop(self, false)
	end
	local entry = createEntry(self, name, params)
	if entry == nil then
		fireChanged(self, previous)
		return false
	end
	if not entry.modal then
		for _, below in ipairs(self._stack) do
			hideEntry(below)
		end
	end
	table.insert(self._stack, entry)
	updateScrim(self)
	showEntry(self, entry, "replace", previous)
	fireChanged(self, previous)
	return true
end

function RouterClass.reset(self: RouterImpl, name: string, params: any?): boolean
	if self._registry[name] == nil then
		error(`Router: unknown screen "{name}"`, 2)
	end
	local previous = topName(self)
	while #self._stack > 0 do
		popTop(self, false)
	end
	local entry = createEntry(self, name, params)
	if entry == nil then
		fireChanged(self, previous)
		return false
	end
	table.insert(self._stack, entry)
	updateScrim(self)
	showEntry(self, entry, "reset", previous)
	fireChanged(self, previous)
	return true
end

--- Back: the top screen's onBack first (true = handled), then close the top modal (if dismissible) or pop; at the
--- root, `rootBack` fires and `onRootBack` runs (Game menu). Returns true if anything handled it.
function RouterClass.back(self: RouterImpl): boolean
	local top = topEntry(self)
	if top == nil then
		return false
	end
	local onBack = top.screen.onBack
	if onBack ~= nil then
		local ok, handled = safe("onBack", top.name, onBack, top.screen)
		if ok and handled == true then
			return true
		end
	end
	if top.modal then
		if top.options.dismissible == false then
			return false
		end
		return RouterClass.pop(self)
	end
	if #self._stack > 1 then
		return RouterClass.pop(self)
	end
	self.rootBack:Fire(top.name)
	local onRootBack = self._onRootBack
	if onRootBack ~= nil then
		local ok, err = pcall(onRootBack :: any)
		if not ok then
			log:error("onRootBack failed: %s", tostring(err))
		end
		return true
	end
	return false
end

--- Deep link: "Garage/TechTree?faction=iron_union&tier=5" resets to the first screen and pushes the rest; params go
--- to the last screen. Returns false (and logs) for malformed links or unknown screens.
function RouterClass.navigate(self: RouterImpl, link: string): boolean
	local parsed = Router.parseLink(link)
	if parsed == nil then
		log:warn("malformed deep link %q", tostring(link))
		return false
	end
	for _, name in parsed.screens do
		if self._registry[name] == nil then
			log:warn("deep link %q names unknown screen %s", link, name)
			return false
		end
	end
	local screens = parsed.screens
	for i, name in screens do
		local params = if i == #screens then parsed.params else nil
		local ok = if i == 1 then RouterClass.reset(self, name, params) else RouterClass.push(self, name, params)
		if not ok then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

local function publicEntry(entry: EntryImpl?): Entry?
	if entry == nil then
		return nil
	end
	return { name = entry.name, params = entry.params, modal = entry.modal }
end

--- Top entry (modals included).
function RouterClass.current(self: RouterImpl): Entry?
	return publicEntry(topEntry(self))
end

--- Top non-modal entry.
function RouterClass.currentScreen(self: RouterImpl): Entry?
	for i = #self._stack, 1, -1 do
		if not self._stack[i].modal then
			return publicEntry(self._stack[i])
		end
	end
	return nil
end

--- Stack names, bottom first.
function RouterClass.history(self: RouterImpl): { string }
	local names = {}
	for _, entry in self._stack do
		table.insert(names, entry.name)
	end
	return names
end

function RouterClass.depth(self: RouterImpl): number
	return #self._stack
end

function RouterClass.canGoBack(self: RouterImpl): boolean
	local top = topEntry(self)
	return top ~= nil and (top.modal or #self._stack > 1)
end

function RouterClass.layer(self: RouterImpl, name: Layer): ScreenGui
	local gui: ScreenGui? = self._guis[name]
	if gui == nil then
		error(`Router: unknown layer "{tostring(name)}"`, 2)
	end
	return gui
end

function RouterClass.layerRoot(self: RouterImpl, name: Layer): Frame
	local root: Frame? = self._roots[name]
	if root == nil then
		error(`Router: unknown layer "{tostring(name)}"`, 2)
	end
	return root
end

--- The live Screen object for a name on the stack (or kept alive), for tests and tooling.
function RouterClass.screenOf(self: RouterImpl, name: string): Screen?
	for i = #self._stack, 1, -1 do
		if self._stack[i].name == name then
			return self._stack[i].screen
		end
	end
	local alive = self._alive[name]
	return if alive then alive.screen else nil
end

function RouterClass.destroy(self: RouterImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	while #self._stack > 0 do
		popTop(self, false)
	end
	for name, entry in pairs(self._alive) do
		self._alive[name] = nil
		safe("destroy", entry.name, entry.screen.destroy, entry.screen)
		entry.scope:Destroy()
		entry.host:Destroy()
	end
	self._trove:Destroy()
	self.changed:DisconnectAll()
	self.rootBack:DisconnectAll()
end

--------------------------------------------------------------------------------
-- Functional screen helper
--------------------------------------------------------------------------------

export type DefineSpec = {
	--- Builds the screen root once (mount). Add instances/connections to `ctx.scope`.
	build: (ctx: ScreenContext) -> GuiObject,
	onShow: ((ctx: ScreenContext, params: any, info: ShowInfo) -> ())?,
	onHide: ((ctx: ScreenContext) -> ())?,
	onBack: ((ctx: ScreenContext) -> boolean?)?,
	initialFocus: ((ctx: ScreenContext) -> GuiObject?)?,
	onShoulder: ((ctx: ScreenContext, direction: number) -> ())?,
	onPage: ((ctx: ScreenContext, direction: number) -> ())?,
}

--- Turns a build function into a ScreenModule: mount builds the root (Size 1,1) into the host, show/hide toggle
--- it, destroy cleans ctx.scope. Most screens only need this.
function Router.define(spec: DefineSpec): ScreenModule
	local module = {}
	function module.new(ctx: ScreenContext): Screen
		local root: GuiObject? = nil
		local screen: { [string]: any } = {}
		function screen.mount(_self: any, parent: GuiObject)
			local built = spec.build(ctx)
			ctx.scope:Add(built)
			built.Parent = parent
			root = built
		end
		function screen.show(_self: any, params: any, info: ShowInfo)
			if root ~= nil then
				root.Visible = true
			end
			if spec.onShow ~= nil then
				spec.onShow(ctx, params, info)
			end
		end
		function screen.hide(_self: any)
			if root ~= nil then
				root.Visible = false
			end
			if spec.onHide ~= nil then
				spec.onHide(ctx)
			end
		end
		function screen.destroy(_self: any)
			root = nil
		end
		if spec.onBack ~= nil then
			local onBack = spec.onBack
			screen.onBack = function(_self: any): boolean?
				return onBack(ctx)
			end
		end
		if spec.initialFocus ~= nil then
			local initialFocus = spec.initialFocus
			screen.initialFocus = function(_self: any): GuiObject?
				return initialFocus(ctx)
			end
		end
		if spec.onShoulder ~= nil then
			local onShoulder = spec.onShoulder
			screen.onShoulder = function(_self: any, direction: number)
				onShoulder(ctx, direction)
			end
		end
		if spec.onPage ~= nil then
			local onPage = spec.onPage
			screen.onPage = function(_self: any, direction: number)
				onPage(ctx, direction)
			end
		end
		return (screen :: any) :: Screen
	end
	return module :: ScreenModule
end

return Router
