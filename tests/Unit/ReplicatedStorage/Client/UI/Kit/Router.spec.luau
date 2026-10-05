local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Router = require("@game/ReplicatedStorage/Client/UI/Kit/Router")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local Focus = require("@game/ReplicatedStorage/Client/UI/Kit/Focus")
local InputMode = require("@game/ReplicatedStorage/Client/UI/Kit/InputMode")
local Layers = require("@game/ReplicatedStorage/Client/UI/Kit/Layers")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

local events: { string } = {}

-- A screen module that records its lifecycle into `events`.
local function fakeScreen(options: { [string]: any }?): any
	local opts = options or {}
	return {
		new = function(ctx: any): any
			if opts.failNew then
				error("cannot construct")
			end
			table.insert(events, `new {ctx.name}`)
			local screen: any = { ctx = ctx }
			function screen.mount(_self: any, parent: any)
				table.insert(events, `mount {ctx.name}`)
				screen.button = Create("TextButton", { Name = "First", Parent = parent })
				screen.second = Create("TextButton", { Name = "Second", Parent = parent })
			end
			function screen.show(_self: any, params: any, info: any)
				if opts.failShow then
					error("show exploded")
				end
				table.insert(events, `show {ctx.name} {info.reason}`)
				screen.lastParams = params
			end
			function screen.hide(_self: any)
				table.insert(events, `hide {ctx.name}`)
			end
			function screen.destroy(_self: any)
				table.insert(events, `destroy {ctx.name}`)
			end
			if opts.onBack then
				function screen.onBack(_self: any): boolean?
					table.insert(events, `onBack {ctx.name}`)
					return opts.onBack()
				end
			end
			if opts.initialSecond then
				function screen.initialFocus(_self: any): any
					return screen.second
				end
			end
			return screen
		end,
	}
end

local function newRouter(extra: { [string]: any }?): any
	local backSignal = Signal.new()
	local options: { [string]: any } = { parent = env.playerGui, backSignal = backSignal, app = { tag = "app" } }
	for k, v in extra or {} do
		options[k] = v
	end
	local router = Router.new(options :: any)
	router:register("Garage", fakeScreen())
	router:register("TechTree", fakeScreen())
	router:register("Research", fakeScreen())
	router:register("Confirm", fakeScreen(), { modal = true })
	router:register("Locked", fakeScreen(), { modal = true, dismissible = false })
	router:register("Alive", fakeScreen(), { keepAlive = true })
	return router, backSignal
end

describe("Router layers", function()
	it("creates one ScreenGui per layer with the decided properties", function()
		local router = newRouter()
		local expected = {
			Background3D = 0,
			HUD = 10,
			Screens = 20,
			Modals = 30,
			Toasts = 40,
			Tooltip = 50,
			Debug = 90,
		}
		for name, order in expected do
			local gui = router:layer(name :: any)
			expect(gui.Parent).toBe(env.playerGui)
			expect(gui.DisplayOrder).toBe(order)
			expect(gui.ResetOnSpawn).toBe(false)
			expect(gui.ZIndexBehavior).toBe(Enum.ZIndexBehavior.Sibling)
			expect(gui.SafeAreaCompatibility).toBe(Enum.SafeAreaCompatibility.None)
			Support.validateTree(gui)
		end
		expect(router:layer("Background3D").ScreenInsets).toBe(Enum.ScreenInsets.None)
		expect(router:layer("Background3D").IgnoreGuiInset).toBe(true)
		expect(router:layer("Screens").ScreenInsets).toBe(Enum.ScreenInsets.CoreUISafeInsets)
		expect(router:layer("Screens").IgnoreGuiInset).toBe(false)
		expect(Layers.get("Tooltip")).toBe(router:layerRoot("Tooltip"))
		expect(router:layerRoot("Screens"):FindFirstChildOfClass("UIScale")).never.toBeNil()
		router:destroy()
		expect(router:layer("Screens").Parent).toBeNil()
		expect(Layers.get("Tooltip")).toBeNil()
		expect(function()
			router:layer("Nope")
		end).toThrow("unknown layer")
	end)
end)

describe("Router stack semantics", function()
	Test.beforeEach(function()
		table.clear(events)
		Focus.reset()
	end)

	it("pushes and pops with the full lifecycle", function()
		local router = newRouter()
		local changes = {}
		router.changed:Connect(function(current, previous)
			table.insert(changes, `{previous or "-"}>{current or "-"}`)
		end)
		expect(router:push("Garage", { slot = 1 })).toBe(true)
		expect(router:push("TechTree")).toBe(true)
		expect(router:history()).toEqual({ "Garage", "TechTree" })
		expect(router:current().name).toBe("TechTree")
		expect(router:canGoBack()).toBe(true)
		expect(router:pop()).toBe(true)
		expect(router:pop()).toBe(false)
		expect(events).toEqual({
			"new Garage",
			"mount Garage",
			"show Garage push",
			-- The new screen is built before the old one hides, so a failing build leaves the old screen up.
			"new TechTree",
			"mount TechTree",
			"hide Garage",
			"show TechTree push",
			"hide TechTree",
			"destroy TechTree",
			"show Garage return",
		})
		expect(changes).toEqual({ "->Garage", "Garage>TechTree", "TechTree>Garage" })
		expect(router:screenOf("Garage").lastParams).toEqual({ slot = 1 })
		expect(router:screenOf("Garage").ctx.app.tag).toBe("app")
		expect(router:canGoBack()).toBe(false)
		router:destroy()
		expect(events[#events]).toBe("destroy Garage")
	end)

	it("covers and hides the screen below; hosts toggle Visible", function()
		local router = newRouter()
		router:push("Garage")
		router:push("TechTree")
		local screens = router:layerRoot("Screens")
		expect(screens:FindFirstChild("Screen_Garage").Visible).toBe(false)
		expect(screens:FindFirstChild("Screen_TechTree").Visible).toBe(true)
		router:pop()
		expect(screens:FindFirstChild("Screen_Garage").Visible).toBe(true)
		expect(screens:FindFirstChild("Screen_TechTree")).toBeNil()
		router:destroy()
	end)

	it("opens modals above the current screen with a scrim; Back closes dismissible ones", function()
		local router = newRouter()
		router:push("Garage")
		router:openModal("Confirm", { item = "x" })
		local scrim = router:layerRoot("Modals"):FindFirstChild("Scrim")
		expect(scrim.Visible).toBe(true)
		expect(router:currentScreen().name).toBe("Garage")
		expect(router:current().modal).toBe(true)
		expect(table.find(events, "hide Garage")).toBeNil()
		expect(router:layerRoot("Modals"):FindFirstChild("Screen_Confirm").ZIndex).toBeGreaterThan(scrim.ZIndex)
		expect(router:back()).toBe(true)
		expect(scrim.Visible).toBe(false)
		expect(router:history()).toEqual({ "Garage" })
		router:openModal("Locked")
		expect(router:back()).toBe(false)
		expect(router:history()).toEqual({ "Garage", "Locked" })
		Support.click(scrim)
		expect(router:history()).toEqual({ "Garage", "Locked" })
		expect(router:closeModal()).toBe(true)
		router:openModal("Confirm")
		Support.click(scrim)
		expect(router:history()).toEqual({ "Garage" })
		expect(function()
			router:openModal("TechTree")
		end).toThrow("not registered as a modal")
		router:destroy()
	end)

	it("closes all modals at once and covering screens hide modals beneath", function()
		local router = newRouter()
		router:push("Garage")
		router:openModal("Confirm")
		router:openModal("Locked")
		router:closeAllModals()
		expect(router:history()).toEqual({ "Garage" })
		router:openModal("Confirm")
		router:push("Research")
		expect(router:layerRoot("Modals"):FindFirstChild("Screen_Confirm").Visible).toBe(false)
		router:pop()
		expect(router:layerRoot("Modals"):FindFirstChild("Screen_Confirm").Visible).toBe(true)
		router:destroy()
	end)

	it("asks onBack first and only pops when unhandled", function()
		local handled = true
		local router = newRouter()
		router:register("Drawer", fakeScreen({
			onBack = function()
				return handled
			end,
		}))
		router:push("Garage")
		router:push("Drawer")
		expect(router:back()).toBe(true)
		expect(router:history()).toEqual({ "Garage", "Drawer" })
		handled = false
		expect(router:back()).toBe(true)
		expect(router:history()).toEqual({ "Garage" })
		expect(router:back()).toBe(false)
		router:destroy()
	end)

	it("handles Back from the injected signal", function()
		local router, backSignal = newRouter()
		router:push("Garage")
		router:push("TechTree")
		backSignal:Fire()
		expect(router:history()).toEqual({ "Garage" })
		router:destroy()
	end)

	it("replaces and resets", function()
		local router = newRouter()
		router:push("Garage")
		router:push("TechTree")
		router:replace("Research", { id = 3 })
		expect(router:history()).toEqual({ "Garage", "Research" })
		expect(table.find(events, "destroy TechTree")).never.toBeNil()
		expect(table.find(events, "show Research replace")).never.toBeNil()
		router:reset("TechTree")
		expect(router:history()).toEqual({ "TechTree" })
		expect(table.find(events, "destroy Garage")).never.toBeNil()
		expect(router:depth()).toBe(1)
		expect(function()
			router:push("Unknown")
		end).toThrow("unknown screen")
		expect(function()
			router:reset("Unknown")
		end).toThrow("unknown screen")
		router:destroy()
	end)

	it("keeps keepAlive screens and reuses them", function()
		local router = newRouter()
		router:push("Garage")
		router:push("Alive")
		router:pop()
		router:push("Alive")
		local newCount = 0
		for _, event in events do
			if event == "new Alive" then
				newCount += 1
			end
		end
		expect(newCount).toBe(1)
		expect(table.find(events, "destroy Alive")).toBeNil()
		router:destroy()
		expect(table.find(events, "destroy Alive")).never.toBeNil()
	end)

	it("aborts pushes whose screen fails to construct and survives failing callbacks", function()
		local capture = LogCapture.start()
		local router = newRouter()
		router:register("Broken", fakeScreen({ failNew = true }))
		router:register("BadShow", fakeScreen({ failShow = true }))
		router:push("Garage")
		expect(router:push("Broken")).toBe(false)
		expect(router:history()).toEqual({ "Garage" })
		expect(capture:find("error", "cannot construct")).never.toBeNil()
		expect(router:push("BadShow")).toBe(true)
		expect(capture:find("error", "show exploded")).never.toBeNil()
		expect(router:history()).toEqual({ "Garage", "BadShow" })
		capture:stop()
		router:destroy()
	end)

	it("validates registrations", function()
		local router = newRouter()
		expect(function()
			router:register("bad name", fakeScreen())
		end).toThrow("invalid screen name")
		expect(function()
			router:register("NoNew", {} :: any)
		end).toThrow("new(ctx)")
		expect(router:isRegistered("Garage")).toBe(true)
		router:destroy()
	end)
end)

describe("Router deep links", function()
	it("parses links", function()
		expect(Router.parseLink("Garage")).toEqual({ screens = { "Garage" }, params = {} })
		expect(Router.parseLink("Garage/TechTree?faction=iron_union&tier=5&elite=true&name=A%20B+C")).toEqual({
			screens = { "Garage", "TechTree" },
			params = { faction = "iron_union", tier = 5, elite = true, name = "A B C" },
		})
		expect(Router.parseLink("")).toBeNil()
		expect(Router.parseLink("?x=1")).toBeNil()
		expect(Router.parseLink("Bad-Name")).toBeNil()
	end)

	it("navigates by resetting to the first screen and pushing the rest", function()
		table.clear(events)
		local router = newRouter()
		router:push("Research")
		expect(router:navigate("Garage/TechTree?tier=7")).toBe(true)
		expect(router:history()).toEqual({ "Garage", "TechTree" })
		expect(router:screenOf("TechTree").lastParams).toEqual({ tier = 7 })
		local capture = LogCapture.start()
		expect(router:navigate("Garage/Nope")).toBe(false)
		expect(router:navigate("%%")).toBe(false)
		expect(capture:count("warn")).toBe(2)
		capture:stop()
		expect(router:history()).toEqual({ "Garage", "TechTree" })
		router:destroy()
	end)
end)

describe("Router focus integration", function()
	Test.beforeEach(function()
		Focus.reset()
		InputMode.set("Gamepad")
	end)
	Test.afterEach(function()
		InputMode.set("MouseKeyboard")
		Focus.reset()
	end)

	it("focuses new screens, traps modals and restores selection on return", function()
		local stop = Focus.install({ playerGui = env.playerGui, startInput = false })
		local router = newRouter()
		router:register("Picky", fakeScreen({ initialSecond = true }))
		router:push("Picky")
		local picky = router:screenOf("Picky")
		expect(env.guiService.SelectedObject).toBe(picky.second)
		Support.select(env.guiService, picky.button)
		router:openModal("Confirm")
		local confirm = router:screenOf("Confirm")
		expect(env.guiService.SelectedObject).toBe(confirm.button)
		Support.select(env.guiService, picky.second)
		expect(env.guiService.SelectedObject).toBe(confirm.button)
		router:closeModal()
		expect(env.guiService.SelectedObject).toBe(picky.button)
		router:push("Garage")
		expect(env.guiService.SelectedObject).toBe(router:screenOf("Garage").button)
		router:pop()
		expect(env.guiService.SelectedObject).toBe(picky.button)
		router:destroy()
		stop()
	end)
end)

describe("Router.define", function()
	it("builds functional screens that toggle with show/hide", function()
		local shown = {}
		local Simple = Router.define({
			build = function(ctx)
				return Create("Frame", {
					Name = "SimpleRoot",
					Size = UDim2.fromScale(1, 1),
					[Create.Children] = {
						Create("TextLabel", {
							Name = "Title",
							Text = ctx.params:get() and ctx.params:get().title or "none",
						}),
					},
				})
			end,
			onShow = function(_ctx, params)
				table.insert(shown, params and params.title or "nil")
			end,
			onBack = function()
				return false
			end,
		})
		local router = newRouter()
		router:register("Simple", Simple)
		router:register("Other", Simple)
		router:push("Simple", { title = "Hello" })
		local host = router:layerRoot("Screens"):FindFirstChild("Screen_Simple")
		local root = host:FindFirstChild("SimpleRoot")
		expect(root.Visible).toBe(true)
		expect(root:FindFirstChild("Title").Text).toBe("Hello")
		router:push("Other")
		expect(root.Visible).toBe(false)
		router:pop()
		expect(root.Visible).toBe(true)
		expect(shown).toEqual({ "Hello", "nil", "Hello" })
		router:destroy()
		expect(rawget(root, "_destroyed")).toBe(true)
	end)
end)
