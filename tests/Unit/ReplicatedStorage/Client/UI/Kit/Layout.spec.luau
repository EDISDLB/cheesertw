local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Layout = require("@game/ReplicatedStorage/Client/UI/Kit/Layout")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

describe("Layout math", function()
	it("scales Regular viewports by height with clamps and the TV multiplier", function()
		expect(Layout.computeScale(Vector2.new(1920, 1080))).toBe(1)
		expect(Layout.computeScale(Vector2.new(1280, 720))).toBe(0.75)
		expect(Layout.computeScale(Vector2.new(1366, 768))).toBeCloseTo(0.75, 1e-9)
		expect(Layout.computeScale(Vector2.new(2560, 1440))).toBeCloseTo(1440 / 1080, 1e-9)
		expect(Layout.computeScale(Vector2.new(3840, 2160))).toBe(1.5)
		expect(Layout.computeScale(Vector2.new(1920, 1080), { tenFoot = true })).toBe(1.25)
		expect(Layout.computeScale(Vector2.new(3840, 2160), { tenFoot = true })).toBe(1.875)
	end)

	it("scales Compact viewports against the 844x390 authoring size", function()
		expect(Layout.computeScale(Vector2.new(844, 390))).toBe(1)
		expect(Layout.computeScale(Vector2.new(667, 375))).toBeCloseTo(375 / 390, 1e-9)
		expect(Layout.computeScale(Vector2.new(568, 320))).toBe(0.92)
		expect(Layout.computeScale(Vector2.new(1000, 599))).toBe(1.25)
		expect(Layout.computeScale(Vector2.new(844, 390), { tenFoot = true })).toBe(1)
	end)

	it("applies the clamped user UI scale", function()
		expect(Layout.computeScale(Vector2.new(1920, 1080), { userScale = 1.2 })).toBeCloseTo(1.2, 1e-9)
		expect(Layout.computeScale(Vector2.new(1920, 1080), { userScale = 5 })).toBeCloseTo(1.2, 1e-9)
		expect(Layout.computeScale(Vector2.new(1920, 1080), { userScale = 0.1 })).toBeCloseTo(0.8, 1e-9)
		expect(Layout.computeScale(Vector2.new(1920, 1080), { userScale = 0 / 0 })).toBe(1)
	end)

	it("picks breakpoints by viewport height and survives invalid viewports", function()
		expect(Layout.breakpointFor(Vector2.new(844, 390))).toBe("Compact")
		expect(Layout.breakpointFor(Vector2.new(2000, 599))).toBe("Compact")
		expect(Layout.breakpointFor(Vector2.new(800, 600))).toBe("Regular")
		expect(Layout.breakpointFor(Vector2.new(0, 0))).toBe("Regular")
		expect(Layout.computeScale(Vector2.new(-5, 0))).toBe(1)
	end)

	it("detects TV only on the 10-ft interface (ui-ux §1.1, §5.4 #3) and caps tablets", function()
		expect(Layout.isTv(true)).toBe(true)
		-- A PC with a gamepad or on a Large display stays Regular (no 1.25x jump when PreferredInput flips).
		expect(Layout.isTv(false)).toBe(false)
		expect(Layout.computeScale(Vector2.new(2732, 2048), { tablet = true })).toBeCloseTo(1.2, 1e-9)
		expect(Layout.computeScale(Vector2.new(2732, 2048))).toBe(1.5)
		expect(Layout.computeScale(Vector2.new(2732, 2048), { tablet = true, userScale = 1.1 })).toBeCloseTo(1.32, 1e-9)
	end)

	it("derives the platform profile and safe margins", function()
		expect(Layout.platformFor(Vector2.new(1920, 1080), Enum.DisplaySize.Medium, false)).toBe("pc")
		expect(Layout.platformFor(Vector2.new(1920, 1080), nil, true)).toBe("console")
		expect(Layout.platformFor(Vector2.new(1920, 1080), Enum.DisplaySize.Large, false)).toBe("pc")
		expect(Layout.platformFor(Vector2.new(844, 390), Enum.DisplaySize.Small, false)).toBe("phone")
		expect(Layout.platformFor(Vector2.new(1024, 768), Enum.DisplaySize.Small, false)).toBe("tablet")
		expect(Layout.safeMargin(true)).toBe(0.05)
		expect(Layout.safeMargin(false)).toBe(0)
		local canvas = Layout.canvasSize(Vector2.new(1280, 720), 0.75)
		expect(canvas.X).toBeCloseTo(1706.67, 0.01)
		expect(canvas.Y).toBe(960)
	end)
end)

describe("Layout live state", function()
	it("pushes scale and platform into Theme and follows the engine after start()", function()
		Layout.setEnvironment({
			viewport = Vector2.new(1280, 720),
			tenFoot = false,
			displaySize = Enum.DisplaySize.Medium,
		})
		expect(Layout.state.scale:peek()).toBe(0.75)
		expect(Theme.snapshot().renderScale).toBe(0.75)
		expect(Theme.snapshot().platform).toBe("pc")
		env:setViewport(Vector2.new(844, 390))
		env.guiService.ViewportDisplaySize = Enum.DisplaySize.Small
		local stop = Layout.start()
		expect(Layout.state.breakpoint:peek()).toBe("Compact")
		expect(Layout.isCompact:peek()).toBe(true)
		expect(Theme.snapshot().platform).toBe("phone")
		env:setViewport(Vector2.new(1920, 1080))
		expect(Layout.state.breakpoint:peek()).toBe("Regular")
		expect(Theme.snapshot().platform).toBe("tablet")
		Theme.set({ uiScale = 1.1 })
		expect(Theme.snapshot().renderScale).toBeCloseTo(1.1, 1e-9)
		stop()
		env:setViewport(Vector2.new(844, 390))
		expect(Layout.state.breakpoint:peek()).toBe("Regular")
		Theme.set({ uiScale = 1 })
	end)

	it("keeps a PC Regular when a gamepad or a Large display shows up (no rescale on input switches)", function()
		Layout.setEnvironment({
			viewport = Vector2.new(1920, 1080),
			tenFoot = false,
			displaySize = Enum.DisplaySize.Medium,
			gamepad = false,
		})
		expect(Layout.state.tv:peek()).toBe(false)
		expect(Layout.state.scale:peek()).toBe(1)
		Layout.setEnvironment({ gamepad = true })
		expect(Layout.state.gamepad:peek()).toBe(true)
		expect(Layout.state.tv:peek()).toBe(false)
		expect(Layout.state.scale:peek()).toBe(1)
		expect(Theme.snapshot().layout).toBe("regular")
		expect(Theme.snapshot().platform).toBe("pc")
		Layout.setEnvironment({ displaySize = Enum.DisplaySize.Large })
		expect(Layout.state.tv:peek()).toBe(false)
		expect(Theme.snapshot().platform).toBe("pc")
		Layout.setEnvironment({ tenFoot = true })
		expect(Layout.state.tv:peek()).toBe(true)
		expect(Layout.state.scale:peek()).toBe(1.25)
		expect(Theme.snapshot().platform).toBe("console")
		Layout.setEnvironment({ tenFoot = false, gamepad = false, displaySize = Enum.DisplaySize.Medium })
		expect(Theme.snapshot().layout).toBe("regular")
	end)

	it("caps the UI scale per display (Compact fixed, touch >= 1.0, canvas >= 1280x800) and reports it", function()
		-- Compact ignores the setting entirely (ui-ux §1.1: fixed 100 %, touch targets would shrink).
		expect(Layout.computeScale(Vector2.new(844, 390), { userScale = 0.8 })).toBe(1)
		expect(Layout.computeScale(Vector2.new(844, 390), { userScale = 1.2 })).toBe(1)
		expect(select(2, Layout.effectiveUserScale(Vector2.new(844, 390), { userScale = 0.8 }))).toBe(false)
		-- Tablets: 1.0-1.2.
		expect(Layout.computeScale(Vector2.new(2732, 2048), { tablet = true, userScale = 0.8 })).toBeCloseTo(1.2, 1e-9)
		-- 1024x768 at 120 % would be a 1138x853 canvas: lowered to 1280 wide and flagged.
		local scale = Layout.computeScale(Vector2.new(1024, 768), { userScale = 1.2 })
		expect(1024 / scale).toBeCloseTo(1280, 1e-6)
		local effective, limited = Layout.effectiveUserScale(Vector2.new(1024, 768), { userScale = 1.2 })
		expect(effective).toBeLessThan(1.2)
		expect(limited).toBe(true)
		-- 1080p at 120 % keeps 1600x900: not limited.
		expect(select(2, Layout.effectiveUserScale(Vector2.new(1920, 1080), { userScale = 1.2 }))).toBe(false)
		-- A TV at 120 % would be 1280x720 (< 800 tall): lowered to an 800-tall canvas.
		local tvScale = Layout.computeScale(Vector2.new(1920, 1080), { tenFoot = true, userScale = 1.2 })
		expect(1080 / tvScale).toBeCloseTo(800, 1e-6)
		-- Never below the setting's minimum, even when the window is tiny.
		expect(Layout.effectiveUserScale(Vector2.new(640, 600), { userScale = 1 })).toBe(Theme.UI_SCALE_MIN)
		-- Live state follows.
		Layout.setEnvironment({
			viewport = Vector2.new(1024, 768),
			tenFoot = false,
			displaySize = Enum.DisplaySize.Medium,
		})
		Theme.set({ uiScale = 1.2 })
		expect(Layout.state.scaleLimited:peek()).toBe(true)
		expect(Layout.state.scale:peek()).toBeCloseTo(0.8, 1e-9)
		Theme.set({ uiScale = 1 })
		expect(Layout.state.scaleLimited:peek()).toBe(false)
		Layout.setEnvironment({ viewport = Vector2.new(1920, 1080) })
	end)

	it("scales the battle HUD by hud.scale with its own caps (ui-ux §1.1.1, §S31)", function()
		expect(Layout.computeHudScale(Vector2.new(1920, 1080))).toBe(1)
		-- 1080p at 150 % would be a 1280 x 720 HUD canvas (too narrow): capped to 1360 wide (~141 %).
		local capped, limited = Layout.computeHudScale(Vector2.new(1920, 1080), { hudScale = 1.5 })
		expect(1920 / capped).toBeCloseTo(1360, 1e-6)
		expect(limited).toBe(true)
		local withAbilities = Layout.computeHudScale(Vector2.new(1920, 1080), { hudScale = 1.5, abilities = true })
		expect(1920 / withAbilities).toBeCloseTo(1448, 1e-6)
		-- A 1280 x 720 laptop above 100 %: E never drops under 720.
		local laptop = Layout.computeHudScale(Vector2.new(1280, 720), { hudScale = 1.5 })
		expect(720 / laptop).toBeGreaterThanOrEqual(720 - 1e-6)
		expect(1280 / laptop).toBeGreaterThanOrEqual(1360 - 1e-6)
		-- Compact battle root: min(1.25, vh / 390), whatever hud.scale says.
		expect(Layout.computeHudScale(Vector2.new(667, 375))).toBeCloseTo(375 / 390, 1e-9)
		expect(Layout.computeHudScale(Vector2.new(1000, 590))).toBe(1.25)
		expect(Layout.computeHudScale(Vector2.new(844, 390), { hudScale = 0.8 })).toBe(1)
		-- Touch on a Regular display: fixed 700-tall canvas.
		expect(Layout.computeHudScale(Vector2.new(1024, 768), { tablet = true })).toBeCloseTo(768 / 700, 1e-9)
		expect(Layout.computeHudScale(Vector2.new(1920, 1080), { tenFoot = true })).toBe(1.25)
		-- Live: independent of the menu UI scale.
		Layout.setEnvironment({
			viewport = Vector2.new(1920, 1080),
			tenFoot = false,
			displaySize = Enum.DisplaySize.Medium,
		})
		Theme.set({ uiScale = 1.2, hudScale = 0.8 })
		expect(Layout.state.scale:peek()).toBeCloseTo(1.2, 1e-9)
		expect(Layout.state.hudScale:peek()).toBeCloseTo(0.8, 1e-9)
		local hudRoot = Layout.root({ Name = "HUD", scale = "hud" })
		expect(hudRoot:FindFirstChildOfClass("UIScale").Scale).toBeCloseTo(0.8, 1e-9)
		expect(hudRoot.Size).toEqual(UDim2.fromScale(1 / 0.8, 1 / 0.8))
		Layout.setHudAbilities(true)
		Theme.set({ hudScale = 1.5 })
		expect(1920 / Layout.state.hudScale:peek()).toBeCloseTo(1448, 1e-6)
		expect(Layout.state.hudLimited:peek()).toBe(true)
		Layout.setHudAbilities(false)
		Theme.set({ uiScale = 1, hudScale = 1 })
		Support.validateTree(hudRoot)
		hudRoot:Destroy()
	end)

	it("pushes the layout family into Theme (TV wins over Compact)", function()
		expect(Layout.layoutModeFor("Regular", false)).toBe("regular")
		expect(Layout.layoutModeFor("Compact", false)).toBe("compact")
		expect(Layout.layoutModeFor("Compact", true)).toBe("tv")
		Layout.setEnvironment({ viewport = Vector2.new(844, 390), tenFoot = false })
		expect(Theme.snapshot().layout).toBe("compact")
		Layout.setEnvironment({ viewport = Vector2.new(1920, 1080), tenFoot = true })
		expect(Theme.snapshot().layout).toBe("tv")
		Layout.setEnvironment({ tenFoot = false })
		expect(Theme.snapshot().layout).toBe("regular")
	end)

	it("builds a scaled root that still fills the screen, with TV-safe padding", function()
		Layout.setEnvironment({ viewport = Vector2.new(1280, 720), tenFoot = false })
		local root = Layout.root({ Name = "Screens", safeArea = true })
		local scale = root:FindFirstChildOfClass("UIScale")
		expect(scale.Scale).toBe(0.75)
		expect(root.Size).toEqual(UDim2.fromScale(1 / 0.75, 1 / 0.75))
		local padding = root:FindFirstChild("SafeArea")
		expect(padding.PaddingTop).toEqual(UDim.new(0, 0))
		Layout.setEnvironment({ viewport = Vector2.new(1920, 1080), tenFoot = true })
		expect(scale.Scale).toBe(1.25)
		expect(padding.PaddingLeft).toEqual(UDim.new(0.05, 0))
		Support.validateTree(root)
		root:Destroy()
		Layout.setEnvironment({ tenFoot = false })
	end)
end)

describe("Layout helpers", function()
	it("builds padding, list, grid, flex and constraints", function()
		local padAll = Layout.padding(8)
		expect(padAll.PaddingLeft).toEqual(UDim.new(0, 8))
		local padXY = Layout.padding({ x = 16, y = 4, top = 2 })
		expect(padXY.PaddingTop).toEqual(UDim.new(0, 2))
		expect(padXY.PaddingBottom).toEqual(UDim.new(0, 4))
		expect(padXY.PaddingRight).toEqual(UDim.new(0, 16))

		local row = Layout.list({ direction = "x", gap = 8, align = "center", justify = "between" })
		expect(row.FillDirection).toBe(Enum.FillDirection.Horizontal)
		expect(row.Padding).toEqual(UDim.new(0, 8))
		expect(row.VerticalAlignment).toBe(Enum.VerticalAlignment.Center)
		expect(row.HorizontalFlex).toBe(Enum.UIFlexAlignment.SpaceBetween)
		expect(row.SortOrder).toBe(Enum.SortOrder.LayoutOrder)
		local column = Layout.list({ justify = "end", align = "center" })
		expect(column.FillDirection).toBe(Enum.FillDirection.Vertical)
		expect(column.VerticalAlignment).toBe(Enum.VerticalAlignment.Bottom)
		expect(column.HorizontalAlignment).toBe(Enum.HorizontalAlignment.Center)

		local grid = Layout.grid({ cell = Vector2.new(200, 120), gap = 12, maxCells = 4 })
		expect(grid.CellSize).toEqual(UDim2.fromOffset(200, 120))
		expect(grid.CellPadding).toEqual(UDim2.fromOffset(12, 12))
		expect(grid.FillDirectionMaxCells).toBe(4)

		expect(Layout.flex().FlexMode).toBe(Enum.UIFlexMode.Grow)
		expect(Layout.flex({ fill = true }).FlexMode).toBe(Enum.UIFlexMode.Fill)
		local custom = Layout.flex({ grow = 2, shrink = 1 })
		expect(custom.FlexMode).toBe(Enum.UIFlexMode.Custom)
		expect(custom.GrowRatio).toBe(2)

		expect(Layout.sizeConstraint(Vector2.new(10, 10)).MinSize).toEqual(Vector2.new(10, 10))
		expect(Layout.aspect(16 / 9).AspectRatio).toBeCloseTo(16 / 9, 1e-9)
		expect(Layout.px(3, 4)).toEqual(UDim2.fromOffset(3, 4))
		expect(Layout.fill()).toEqual(UDim2.fromScale(1, 1))
		expect(Layout.row(40)).toEqual(UDim2.new(1, 0, 0, 40))
		expect(Layout.column(40)).toEqual(UDim2.new(0, 40, 1, 0))

		local holder = Create("Frame", {
			[Create.Children] = { padAll, padXY, row, column, grid, Layout.flex({ grow = 1 }) },
		})
		Support.validateTree(holder)
	end)
end)
