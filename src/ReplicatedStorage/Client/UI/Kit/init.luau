--!strict
--[[
	Kit — the HULLDOWN client UI kit in one require.

	Purpose:          `local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")` gives screens the whole kit:
	                  the core (State, Create, Theme, Layout, Motion, InputMode, Focus, Router, Format, Sound, Layers,
	                  UIInput) and every component (Kit.Button.new{...}, Kit.Text.h3("Crew"), ...). Modules can still be
	                  required one by one (`.../Kit/State`) — use that for types (`State.Value<T>`, `Theme.ColorToken`)
	                  and in kit-internal code (components never require this aggregate, so there are no cycles).
	                  See docs/systems/ui-kit.md.
	                  `Kit.start()` starts the engine bindings (input mode, layout, accessibility, KitUI input, focus).
	Dependencies:     Every Kit module and component.
	State:            None (re-exports).
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: Requiring this loads every component once (all client-side, a few ms).
]]

local State = require("@self/State")
local Create = require("@self/Create")
local Theme = require("@self/Theme")
local Tokens = require("@self/Tokens")
local Format = require("@self/Format")
local Layout = require("@self/Layout")
local Motion = require("@self/Motion")
local InputMode = require("@self/InputMode")
local Focus = require("@self/Focus")
local Router = require("@self/Router")
local Layers = require("@self/Layers")
local Sound = require("@self/Sound")
local UIInput = require("@self/UIInput")
local Services = require("@self/Services")

local Badge = require("@self/Components/Badge")
local Button = require("@self/Components/Button")
local Card = require("@self/Components/Card")
local Chamfer = require("@self/Components/Chamfer")
local Chip = require("@self/Components/Chip")
local Common = require("@self/Components/Common")
local ConfirmDialog = require("@self/Components/ConfirmDialog")
local CurrencyLabel = require("@self/Components/CurrencyLabel")
local Divider = require("@self/Components/Divider")
local Dropdown = require("@self/Components/Dropdown")
local EmptyState = require("@self/Components/EmptyState")
local FocusRing = require("@self/Components/FocusRing")
local Icon = require("@self/Components/Icon")
local IconButton = require("@self/Components/IconButton")
local KeyPrompt = require("@self/Components/KeyPrompt")
local Modal = require("@self/Components/Modal")
local Panel = require("@self/Components/Panel")
local ProgressBar = require("@self/Components/ProgressBar")
local ScrollFrame = require("@self/Components/ScrollFrame")
local Shadow = require("@self/Components/Shadow")
local Skeleton = require("@self/Components/Skeleton")
local Slider = require("@self/Components/Slider")
local Spinner = require("@self/Components/Spinner")
local StatBar = require("@self/Components/StatBar")
local TabBar = require("@self/Components/TabBar")
local Text = require("@self/Components/Text")
local Toast = require("@self/Components/Toast")
local ToastStack = require("@self/Components/ToastStack")
local Toggle = require("@self/Components/Toggle")
local Tooltip = require("@self/Components/Tooltip")
local VirtualGrid = require("@self/Components/VirtualGrid")
local VirtualList = require("@self/Components/VirtualList")

export type State<T> = State.State<T>
export type Value<T> = State.Value<T>
export type CanBeState<T> = State.CanBeState<T>
export type ColorToken = Theme.ColorToken
export type TypeRole = Theme.TypeRole
export type Layer = Theme.Layer
export type MotionSetting = Theme.MotionSetting
export type Screen = Router.Screen
export type ScreenContext = Router.ScreenContext
export type RouterObject = Router.Router
export type StartOptions = {
	--- PlayerGui that gets the brand focus ring (default: LocalPlayer's).
	playerGui: PlayerGui?,
	--- Plays kit UI sounds by key (the audio system's player; default: counted but silent).
	soundPlayer: Sound.Player?,
}

--- Starts the kit's engine bindings once per client, before the first Router: input-mode tracking, viewport/scale
--- (Layout), the engine accessibility settings (Theme.bindEngine), the KitUI input context and gamepad focus
--- (Focus.install: AutoSelectGuiEnabled off, brand focus ring, LB/RB and Back routing). Returns stop().
local function start(options: StartOptions?): () -> ()
	local opts: StartOptions = options or {}
	if opts.soundPlayer ~= nil then
		Sound.setPlayer(opts.soundPlayer)
	end
	local stops: { () -> () } = {
		InputMode.start(),
		Layout.start(),
		Theme.bindEngine(),
		Focus.install({ playerGui = opts.playerGui }),
	}
	return function()
		for i = #stops, 1, -1 do
			stops[i]()
		end
	end
end

local Kit = {
	start = start,
	-- Core
	State = State,
	Create = Create,
	Theme = Theme,
	Tokens = Tokens,
	Format = Format,
	Layout = Layout,
	Motion = Motion,
	InputMode = InputMode,
	Focus = Focus,
	Router = Router,
	Layers = Layers,
	Sound = Sound,
	UIInput = UIInput,
	Services = Services,
	-- Components
	Badge = Badge,
	Button = Button,
	Card = Card,
	Chamfer = Chamfer,
	Chip = Chip,
	Common = Common,
	ConfirmDialog = ConfirmDialog,
	CurrencyLabel = CurrencyLabel,
	Divider = Divider,
	Dropdown = Dropdown,
	EmptyState = EmptyState,
	FocusRing = FocusRing,
	Icon = Icon,
	IconButton = IconButton,
	KeyPrompt = KeyPrompt,
	Modal = Modal,
	Panel = Panel,
	ProgressBar = ProgressBar,
	ScrollFrame = ScrollFrame,
	Shadow = Shadow,
	Skeleton = Skeleton,
	Slider = Slider,
	Spinner = Spinner,
	StatBar = StatBar,
	TabBar = TabBar,
	Text = Text,
	Toast = Toast,
	ToastStack = ToastStack,
	Toggle = Toggle,
	Tooltip = Tooltip,
	VirtualGrid = VirtualGrid,
	VirtualList = VirtualList,
}

return table.freeze(Kit)
