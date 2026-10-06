local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local KitGallery = require("@game/ReplicatedStorage/Client/UI/Dev/KitGallery")
local Kit = require("@game/ReplicatedStorage/Client/UI/Kit")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

describe("Kit aggregate", function()
	it("re-exports the core and every component", function()
		for _, name in
			{
				"State",
				"Create",
				"Theme",
				"Layout",
				"Motion",
				"InputMode",
				"Focus",
				"Router",
				"Format",
				"Button",
				"Dropdown",
				"TabBar",
				"Modal",
				"ConfirmDialog",
				"Toast",
				"ToastStack",
				"VirtualList",
				"VirtualGrid",
				"CurrencyLabel",
				"Skeleton",
			}
		do
			expect(type((Kit :: any)[name])).toBe("table")
		end
		expect(table.isfrozen(Kit)).toBe(true)
	end)

	it("starts and stops the engine bindings", function()
		local played = {}
		env.guiService.AutoSelectGuiEnabled = true
		local stop = Kit.start({
			playerGui = env.playerGui,
			soundPlayer = function(key: string)
				table.insert(played, key)
			end,
		})
		expect(env.guiService.AutoSelectGuiEnabled).toBe(false)
		expect(env.playerGui.SelectionImageObject).never.toBeNil()
		Kit.Sound.play(Kit.Sound.KEYS.click)
		expect(played).toEqual({ "ui_click" })
		stop()
		Kit.Sound.setPlayer(nil)
	end)
end)

describe("KitGallery", function()
	Test.afterEach(function()
		Kit.Theme.reset()
		Kit.Focus.reset()
		Kit.InputMode.set("MouseKeyboard")
	end)

	it("builds every section with valid Roblox properties", function()
		local router = Kit.Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		local scope = Trove.new()
		for _, section in KitGallery.SECTIONS do
			local frame = KitGallery.buildSection(section.id :: any, scope)
			expect(frame.Name).toBe("Section_" .. section.id)
			-- A failing builder renders a "Section failed to build" EmptyState instead; none should.
			for _, label in Support.descendants(frame, "TextLabel") do
				expect({ label = label:GetFullName(), text = type(label.Text) }).toEqual({
					label = label:GetFullName(),
					text = "string",
				})
				if string.find(string.lower(label.Text), "failed to build", 1, true) then
					error(`section {section.id} failed: {Support.find(frame, "Body").Text}`)
				end
			end
			frame.Parent = router:layerRoot("Screens")
			Support.validateTree(frame)
		end
		scope:Destroy()
		router:destroy()
		expect(function()
			KitGallery.buildSection("nope" :: any, Trove.new())
		end).toThrow("unknown section")
	end)

	it("registers as a screen, switches sections lazily and drives the theme controls", function()
		local router = Kit.Router.new({ parent = env.playerGui, backSignal = Signal.new() })
		KitGallery.register(router)
		KitGallery.register(router)
		expect(router:push(KitGallery.NAME)).toBe(true)
		local root = Support.find(router:layerRoot("Screens"), "KitGallery")
		expect(root).never.toBeNil()
		local content = Support.find(root, "Content")
		expect(Support.find(content, "Section_foundations")).never.toBeNil()
		expect(Support.find(content, "Section_icons")).toBeNil()
		local tabs = Support.find(root, "SectionTabs")
		Support.click(Support.find(tabs, "Tab_icons"))
		expect(Support.find(content, "Section_icons").Visible).toBe(true)
		expect(Support.find(content, "Section_foundations").Visible).toBe(false)
		Support.click(Support.find(Support.find(root, "SchemeTabs"), "Segment_protanopia"))
		expect(Kit.Theme.state.scheme:peek()).toBe("protanopia")
		local highContrast = Support.find(root, "Controls"):GetChildren()
		local toggles = {}
		for _, child in highContrast do
			if child.Name == "Toggle" then
				table.insert(toggles, child)
			end
		end
		Support.click(toggles[1])
		expect(Kit.Theme.state.highContrast:peek()).toBe(true)
		Support.click(toggles[2])
		expect(Kit.Theme.state.reducedMotion:peek()).toBe(true)
		router:pop()
		router:destroy()
	end)
end)
