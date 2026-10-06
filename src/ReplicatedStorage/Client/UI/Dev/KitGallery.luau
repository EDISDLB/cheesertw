--!strict
--[[
	Dev/KitGallery — every kit component in every state, under every theme setting (Studio / dev builds).

	Purpose:          A Router screen for designers and screen authors: pick a section with the tab bar (LB/RB on
	                  gamepad), flip the colour-blind scheme, high contrast, reduced motion, text scale and the input
	                  mode preview in the header, and check each component's idle / hover / pressed / disabled /
	                  loading / selected states, sizes and variants. Sections are built lazily the first time they
	                  are opened. Register it with `KitGallery.register(router)` and open it with
	                  `router:push("KitGallery")` (dev menu / Studio command bar).
	Dependencies:     Client/UI/Kit (core + components), Icons/Registry.
	State:            Section selection and theme-control Values (scoped to the screen); the theme settings it
	                  changes are global on purpose (that is what the gallery previews).
	Validation:       N/A.
	Error handling:   Section builders run once; a failing section shows an EmptyState with the error.
	Performance notes: Only the visible section exists; the icon sheet and the 500-row list are virtualised.
]]

local Create = require("../Kit/Create")
local State = require("../Kit/State")
local Theme = require("../Kit/Theme")
local Tokens = require("../Kit/Tokens")
local Layout = require("../Kit/Layout")
local InputMode = require("../Kit/InputMode")
local Router = require("../Kit/Router")
local Format = require("../Kit/Format")
local Badge = require("../Kit/Components/Badge")
local Button = require("../Kit/Components/Button")
local Card = require("../Kit/Components/Card")
local Chamfer = require("../Kit/Components/Chamfer")
local Chip = require("../Kit/Components/Chip")
local ConfirmDialog = require("../Kit/Components/ConfirmDialog")
local CurrencyLabel = require("../Kit/Components/CurrencyLabel")
local Divider = require("../Kit/Components/Divider")
local Dropdown = require("../Kit/Components/Dropdown")
local EmptyState = require("../Kit/Components/EmptyState")
local Icon = require("../Kit/Components/Icon")
local IconButton = require("../Kit/Components/IconButton")
local KeyPrompt = require("../Kit/Components/KeyPrompt")
local Modal = require("../Kit/Components/Modal")
local Panel = require("../Kit/Components/Panel")
local ProgressBar = require("../Kit/Components/ProgressBar")
local ScrollFrame = require("../Kit/Components/ScrollFrame")
local Skeleton = require("../Kit/Components/Skeleton")
local Slider = require("../Kit/Components/Slider")
local Spinner = require("../Kit/Components/Spinner")
local StatBar = require("../Kit/Components/StatBar")
local TabBar = require("../Kit/Components/TabBar")
local Text = require("../Kit/Components/Text")
local Toast = require("../Kit/Components/Toast")
local Toggle = require("../Kit/Components/Toggle")
local Tooltip = require("../Kit/Components/Tooltip")
local VirtualGrid = require("../Kit/Components/VirtualGrid")
local VirtualList = require("../Kit/Components/VirtualList")
local Registry = require("../Icons/Registry")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

type Trove = Trove.Trove

local KitGallery = {}

KitGallery.NAME = "KitGallery"

export type SectionId = "foundations" | "buttons" | "inputs" | "surfaces" | "feedback" | "data" | "icons" | "lists"

KitGallery.SECTIONS = {
	{ id = "foundations", label = "Foundations" },
	{ id = "buttons", label = "Buttons" },
	{ id = "inputs", label = "Inputs" },
	{ id = "surfaces", label = "Surfaces" },
	{ id = "feedback", label = "Feedback" },
	{ id = "data", label = "Data" },
	{ id = "icons", label = "Icons" },
	{ id = "lists", label = "Lists" },
}

local SCHEME_LABELS: { [string]: string } = {
	default = "Default",
	deuteranopia = "Deutan",
	protanopia = "Protan",
	tritanopia = "Tritan",
}

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function row(children: { any }, gap: number?): Frame
	local all: { Instance } =
		{ Layout.list({ direction = "x", gap = gap or Theme.space(3), align = "center", wraps = true }) }
	for i, child in children do
		if child:IsA("GuiObject") and child.LayoutOrder == 0 then
			child.LayoutOrder = i
		end
		table.insert(all, child)
	end
	return Create.Frame({
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		[Create.Children] = all,
	})
end

local function caption(text: string): TextLabel
	return Text.new({ text = text, role = "caption", LayoutOrder = nextOrder() })
end

local function group(title: string, children: { any }): Frame
	local panel = Panel.new({
		Name = "Group_" .. string.gsub(title, "%W", ""),
		title = title,
		Size = UDim2.fromScale(1, 0),
		autoHeight = true,
		list = { gap = Theme.space(3) },
		LayoutOrder = nextOrder(),
	})
	local content = Panel.content(panel)
	for i, child in children do
		if child:IsA("GuiObject") and child.LayoutOrder == 0 then
			child.LayoutOrder = i
		end
		child.Parent = content
	end
	return panel
end

local function labelled(label: string, child: GuiObject): Frame
	return Create.Frame({
		Name = "Labelled",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		[Create.Children] = {
			Layout.list({ gap = Theme.space(1) }) :: Instance,
			Text.new({ text = label, role = "micro", color = "text.tertiary", LayoutOrder = 1 }),
			(function(): Instance
				child.LayoutOrder = 2
				return child
			end)(),
		},
	})
end

local function swatch(name: string, color: State.CanBeState<Color3>, width: number?): Frame
	return Create.Frame({
		Name = "Swatch",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width or 112, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Layout.list({ gap = Theme.space(1) }) :: Instance,
			Create.Frame({
				Name = "Chip",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Size = UDim2.new(1, 0, 0, 40),
				LayoutOrder = 1,
				[Create.Children] = {
					Create.UIStroke({ Color = Theme.color("border.subtle"), Thickness = 1 }),
				},
			}),
			Text.new({ text = name, role = "micro", upper = false, color = "text.secondary", LayoutOrder = 2 }),
		},
	})
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

local function foundations(_scope: Trove): { Instance }
	local groups: { [string]: { string } } = {}
	local groupOrder: { string } = {}
	local names: { string } = {}
	for name in pairs(Tokens.colors :: { [string]: string }) do
		table.insert(names, name)
	end
	for name in pairs(Tokens.extraColors :: { [string]: string }) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local prefix = string.match(name, "^([%w_]+)%.") or name
		if groups[prefix] == nil then
			groups[prefix] = {}
			table.insert(groupOrder, prefix)
		end
		table.insert(groups[prefix], name)
	end
	local colorRows: { Instance } = {}
	for _, prefix in groupOrder do
		local swatches: { Instance } = {}
		for _, name in groups[prefix] do
			table.insert(swatches, swatch(name, Theme.color(name :: any)))
		end
		table.insert(colorRows, caption(prefix))
		table.insert(colorRows, row(swatches, Theme.space(2)))
	end
	local schemeRows: { Instance } = {}
	for _, scheme in Theme.SCHEMES do
		local colors = Theme.schemeColors(scheme :: any)
		table.insert(
			schemeRows,
			row({
				Text.new({ text = SCHEME_LABELS[scheme], role = "label", Size = UDim2.fromOffset(120, 24) }),
				swatch("ally", colors.ally, 88),
				swatch("enemy", colors.enemy, 88),
				swatch("platoon", colors.platoon, 88),
				swatch("self", colors.self, 88),
			})
		)
	end
	local typeRows: { Instance } = {}
	local roles: { Theme.TypeRole } = {
		"display.hero",
		"h1",
		"h2",
		"h3",
		"h4",
		"body.l",
		"body",
		"body.s",
		"label",
		"caption",
		"num.xl",
		"num.l",
		"num.m",
		"mono",
		"micro",
		"button",
		"button.cta",
		"button.battle",
		"tab",
		"badge",
		"title.s",
	}
	for _, role in roles do
		local sample = if string.sub(role, 1, 4) == "num." then "1,234,567" else "Hull down, gun up"
		typeRows[#typeRows + 1] = row({
			Text.new({ text = role, role = "mono", color = "text.tertiary", Size = UDim2.fromOffset(140, 24) }),
			Text.new({ text = sample, role = role :: Theme.TypeRole }),
		})
	end
	local surfaces: { Instance } = {}
	for _, corners in { "brand", "all", "top", "bottom", "none" } do
		table.insert(
			surfaces,
			labelled(
				corners,
				Create.Frame({
					Name = "Surface_" .. corners,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(120, 72),
					[Create.Children] = {
						Chamfer.new({
							corners = corners :: any,
							size = Theme.chamfer("m"),
							fill = Theme.color("bg.raised"),
							border = Theme.color("border.strong"),
							bevel = true,
						}),
					},
				})
			)
		)
	end
	local spacing: { Instance } = {}
	for step = 1, 8 do
		table.insert(
			spacing,
			labelled(
				`space({step}) = {Theme.space(step)}`,
				Create.Frame({
					Name = "Space",
					BorderSizePixel = 0,
					BackgroundColor3 = Theme.color("accent.steel"),
					Size = UDim2.fromOffset(Theme.space(step), 12),
				})
			)
		)
	end
	return {
		group("Colour tokens", colorRows),
		group("Team colours per colour-blind scheme", schemeRows),
		group("Typography roles", typeRows),
		group("Surfaces (HULLDOWN cut)", { row(surfaces) }),
		group("Spacing", { row(spacing) }),
	}
end

local function buttons(_scope: Trove): { Instance }
	local rows: { Instance } = {}
	for _, variant in { "primary", "secondary", "ghost", "danger", "battle" } do
		local v = variant :: Button.Variant
		table.insert(rows, caption(variant))
		table.insert(
			rows,
			row({
				Button.new({ text = "Idle", variant = v :: any }),
				Button.new({ text = "With icon", variant = v :: any, icon = "ui/check" }),
				Button.new({ text = "Hint", variant = v :: any, hint = "Tertiary" }),
				Button.new({ text = "Loading", variant = v :: any, loading = true }),
				Button.new({ text = "Disabled", variant = v :: any, disabled = true, tooltip = "Requires Tier V" }),
			})
		)
	end
	table.insert(rows, caption("sizes"))
	table.insert(
		rows,
		row({
			Button.new({ text = "Large", size = "large" }),
			Button.new({ text = "Medium", size = "medium" }),
			Button.new({ text = "Compact", size = "compact" }),
			Button.new({ text = "Fixed 320", width = 320 }),
		})
	)
	local iconButtons: { Instance } = {}
	for _, variant in { "ghost", "secondary", "primary" } do
		table.insert(
			iconButtons,
			IconButton.new({ icon = "ui/settings", label = "Settings", variant = variant :: any })
		)
	end
	table.insert(iconButtons, IconButton.new({ icon = "ui/search", label = "Search", selected = true }))
	table.insert(iconButtons, IconButton.new({ icon = "ui/lock", label = "Locked", disabled = true }))
	return {
		group("Buttons — variants and states (hover / press / gamepad focus live)", rows),
		group("Icon buttons", { row(iconButtons) }),
	}
end

local function inputs(scope: Trove): { Instance }
	local toggleValue = State.Value(true, { scope = scope })
	local sliderValue = State.Value(0.6, { scope = scope })
	local stepped = State.Value(1, { scope = scope })
	local quality = State.Value("high", { scope = scope })
	local tab = State.Value("garage", { scope = scope })
	local segment = State.Value("all", { scope = scope })
	local filter = State.Value(true, { scope = scope })
	return {
		group("Toggles", {
			Toggle.new({ label = "Bound value", value = toggleValue, Size = UDim2.fromOffset(420, 44) }),
			Toggle.new({ label = "Off", checked = false, Size = UDim2.fromOffset(420, 44) }),
			Toggle.new({ label = "Disabled", checked = true, disabled = true, Size = UDim2.fromOffset(420, 44) }),
		}),
		group("Sliders", {
			Slider.new({
				label = "Master volume",
				value = sliderValue,
				min = 0,
				max = 1,
				format = function(v: number): string
					return Format.percent(v)
				end,
			}),
			Slider.new({ label = "Text scale (step 0.1)", value = stepped, min = 0.8, max = 1.5, step = 0.1 }),
			Slider.new({
				label = "Disabled",
				value = State.Value(0.3, { scope = scope }),
				min = 0,
				max = 1,
				disabled = true,
			}),
		}),
		group("Dropdowns", {
			row({
				Dropdown.new({
					options = {
						{ value = "low", label = "Low" },
						{ value = "medium", label = "Medium" },
						{ value = "high", label = "High" },
						{ value = "ultra", label = "Ultra (locked)", disabled = true },
					},
					selected = quality,
				}),
				Dropdown.new({
					options = {},
					selected = State.Value(nil, { scope = scope }),
					placeholder = "Placeholder",
				}),
				Dropdown.new({ options = {}, selected = State.Value(nil, { scope = scope }), disabled = true }),
			}),
		}),
		group("Tab bars", {
			TabBar.new({
				tabs = {
					{ id = "garage", label = "Garage" },
					{ id = "research", label = "Research", badge = 3 },
					{ id = "store", label = "Store", icon = "currency/bullion" },
					{ id = "locked", label = "Locked", disabled = true },
				},
				selected = tab,
			}),
			TabBar.new({
				tabs = {
					{ id = "all", label = "All" },
					{ id = "owned", label = "Owned" },
					{ id = "premium", label = "Premium" },
				},
				selected = segment,
				variant = "segmented",
				Size = UDim2.fromOffset(420, 36),
			}),
		}),
		group("Chips and tags", {
			row({
				Chip.new({
					label = "Filter (toggle)",
					selected = filter,
					onActivated = function()
						filter:set(not filter:peek())
					end,
				}),
				Chip.new({ label = "Heavy", icon = "classes/heavy", selected = true, onActivated = function() end }),
				Chip.new({ label = "Removable", removable = true, onRemove = function() end }),
				Chip.new({ label = "Disabled", disabled = true, onActivated = function() end }),
				Chip.tag("Neutral"),
				Chip.tag("Success", "success"),
				Chip.tag("Warning", "warning"),
				Chip.tag("Danger", "danger"),
				Chip.tag("Info", "info"),
			}),
		}),
		group("Key prompts (follow the input mode)", {
			row({
				KeyPrompt.new({ action = "Confirm", label = "Select" }),
				KeyPrompt.new({ action = "Back", label = "Back" }),
				KeyPrompt.new({ action = "Secondary", label = "Details" }),
				KeyPrompt.new({ action = "Tertiary", label = "Compare" }),
				KeyPrompt.new({ action = "TabPrev" }),
				KeyPrompt.new({ action = "TabNext" }),
			}),
			KeyPrompt.hintBar({
				hints = {
					{ action = "Confirm", label = "Select" },
					{ action = "Secondary", label = "Details" },
					{ action = "Back", label = "Back" },
				},
				align = "left",
			}),
		}),
	}
end

local function surfaces(_scope: Trove): { Instance }
	local panels: { Instance } = {}
	for i, variant in { "default", "raised", "inset", "hero" } do
		table.insert(
			panels,
			Panel.new({
				title = variant,
				number = string.format("%02d", i),
				variant = variant :: any,
				Size = UDim2.fromOffset(300, 160),
				children = { Text.body("Panel body text.", { Size = UDim2.fromScale(1, 0) }) },
			})
		)
	end
	local cards: { Instance } = {}
	for _, rarity in { "common", "uncommon", "rare", "epic", "legendary", "prototype" } do
		table.insert(
			cards,
			Card.new({
				rarity = rarity :: any,
				Size = UDim2.fromOffset(160, 96),
				onActivated = function() end,
				children = { Text.label(rarity) },
			})
		)
	end
	table.insert(
		cards,
		Card.new({ selected = true, Size = UDim2.fromOffset(160, 96), children = { Text.label("Selected") } })
	)
	table.insert(
		cards,
		Card.new({ disabled = true, Size = UDim2.fromOffset(160, 96), children = { Text.label("Disabled") } })
	)
	local dialogs = row({
		Button.new({
			text = "Modal (s)",
			onActivated = function()
				Modal.open({
					title = "Small dialog",
					size = "s",
					body = "Back, the close button or the scrim closes it.",
					actions = { { text = "Cancel" }, { text = "OK" } },
				})
			end,
		}),
		Button.new({
			text = "Modal (l)",
			onActivated = function()
				Modal.open({
					title = "Large dialog",
					icon = "ui/info",
					size = "l",
					body = "Focus is trapped inside; LB/RB and Back never reach the screen below.",
					children = { ProgressBar.new({ value = 0.6 }) },
					actions = { { text = "Close" } },
				})
			end,
		}),
		Button.new({
			text = "Not dismissible",
			onActivated = function()
				Modal.open({
					title = "Updating",
					dismissible = false,
					body = "Back is swallowed; only the action closes it.",
					actions = { { text = "Done" } },
				})
			end,
		}),
		Button.new({
			text = "Confirm",
			onActivated = function()
				ConfirmDialog.open({ title = "Apply settings?", body = "Graphics settings change immediately." })
			end,
		}),
		Button.new({
			text = "Destructive confirm",
			variant = "danger",
			onActivated = function()
				ConfirmDialog.open({
					title = "Sell vehicle?",
					body = "Sell the T-34 for 120,000 credits. Crew is sent to the barracks.",
					confirmLabel = "Sell",
					destructive = true,
				})
			end,
		}),
	})
	return {
		group("Panels", { row(panels) }),
		group("Cards (rarity, selected, disabled)", { row(cards) }),
		group("Dividers", {
			Divider.new(),
			Divider.new({ variant = "ridge" }),
			Divider.new({ label = "or" }),
			row({
				Text.body("Left"),
				Divider.new({ direction = "vertical", Size = UDim2.fromOffset(1, 24) }),
				Text.body("Right"),
			}),
		}),
		group("Dialogs", { dialogs }),
	}
end

local function feedback(scope: Trove): { Instance }
	local progress = State.Value(0.35, { scope = scope })
	local busy = State.Value(true, { scope = scope })
	local toastButtons: { Instance } = {}
	for _, tone in { "neutral", "info", "success", "warning", "danger" } do
		table.insert(
			toastButtons,
			Button.new({
				text = tone,
				size = "compact",
				onActivated = function()
					Toast.show({ title = `{tone} toast`, body = "Auto-dismisses after 4 s.", tone = tone :: any })
				end,
			})
		)
	end
	table.insert(
		toastButtons,
		Button.new({
			text = "With action",
			size = "compact",
			onActivated = function()
				Toast.show({
					title = "Module sold",
					body = "Held for 8 s.",
					tone = "success",
					action = { text = "Undo", onActivated = function() end },
				})
			end,
		})
	)
	local tooltipTarget = Button.new({ text = "Hover / focus / long-press me" })
	Tooltip.attach(tooltipTarget, { title = "Reload time", body = "Time to load the next round with a full crew." })
	return {
		group("Toasts", { row(toastButtons) }),
		group("Progress", {
			labelled("determinate (spring)", ProgressBar.new({ value = progress, Size = UDim2.fromOffset(420, 6) })),
			row({
				Button.new({
					text = "Randomise",
					size = "compact",
					onActivated = function()
						progress:set(math.random())
					end,
				}),
				Toggle.new({ label = "Indeterminate", value = busy, Size = UDim2.fromOffset(260, 44) }),
			}),
			labelled("indeterminate", ProgressBar.new({ indeterminate = busy, Size = UDim2.fromOffset(420, 6) })),
			labelled(
				"ghost + segments (XP)",
				ProgressBar.new({
					value = 0.4,
					ghost = 0.65,
					segments = 5,
					color = "currency.vehicle_xp",
					height = 10,
					Size = UDim2.fromOffset(420, 10),
				})
			),
		}),
		group("Spinners and skeletons", {
			row({
				Spinner.new({ size = 16 }),
				Spinner.new({ size = 24 }),
				Spinner.new({ size = 48, color = "accent.dusk" }),
			}),
			row({
				Skeleton.new({ shape = "circle", Size = UDim2.fromOffset(48, 48) }),
				Skeleton.new({ Size = UDim2.fromOffset(220, 48) }),
				Skeleton.new({ shape = "lines", lines = 3, Size = UDim2.fromOffset(300, 0) }),
			}),
		}),
		group("Empty state", {
			EmptyState.new({
				icon = "ui/search",
				title = "No vehicles match",
				body = "Clear the filters to see the whole hangar.",
				action = { text = "Clear filters", onActivated = function() end },
				Size = UDim2.new(1, 0, 0, 260),
			}),
		}),
		group("Tooltip", { row({ tooltipTarget }) }),
	}
end

local function data(scope: Trove): { Instance }
	local credits = State.Value(125400, { scope = scope })
	local currencies: { Instance } = {}
	for _, currency in { "credits", "bullion", "vehicle_xp", "free_xp", "crew_xp", "campaign_token" } do
		table.insert(currencies, CurrencyLabel.new({ currency = currency :: any, amount = 12400, style = "panel" }))
	end
	local badges: { Instance } = {}
	for tier = 1, 11 do
		table.insert(badges, Badge.tier(tier, { kind = "tier", size = 32 }))
	end
	local classBadges: { Instance } = {}
	for _, class in { "light", "medium", "heavy", "td", "artillery" } do
		table.insert(classBadges, Badge.new({ kind = "class", class = class :: any, size = 28 }))
		table.insert(classBadges, Badge.new({ kind = "class", class = class :: any, size = 28, premium = true }))
		table.insert(classBadges, Badge.new({ kind = "class", class = class :: any, size = 28, elite = true }))
	end
	return {
		group("Stat bars (comparison)", {
			StatBar.new({
				label = "Penetration (higher is better)",
				value = 175,
				compare = 212,
				max = 300,
				unit = "mm",
			}),
			StatBar.new({
				label = "Reload (lower is better)",
				value = 7.4,
				compare = 6.9,
				max = 12,
				unit = "s",
				decimals = 1,
				lowerIsBetter = true,
			}),
			StatBar.new({ label = "Top speed (worse)", value = 56, compare = 48, max = 80, unit = "km/h" }),
			StatBar.new({ label = "No comparison", value = 1450, max = 2000, unit = "HP" }),
			StatBar.new({ label = "Text only", value = 0.34, decimals = 2, unit = "m", bar = false }),
		}),
		group("Currencies", {
			row(currencies),
			row({
				CurrencyLabel.new({ currency = "credits", amount = credits, size = "l", showDelta = true }),
				Button.new({
					text = "+1,500",
					size = "compact",
					onActivated = function()
						credits:set(credits:peek() + 1500)
					end,
				}),
				Button.new({
					text = "−700",
					size = "compact",
					onActivated = function()
						credits:set(credits:peek() - 700)
					end,
				}),
				CurrencyLabel.new({ currency = "bullion", amount = 2500, insufficient = true }),
				CurrencyLabel.new({ currency = "credits", amount = 1250000, compact = true, size = "s" }),
			}),
		}),
		group("Badges", {
			row(badges),
			row(classBadges),
			row({
				Badge.new({ kind = "premium" }),
				Badge.new({ kind = "premium", compact = true }),
				Badge.new({ kind = "new" }),
				Badge.new({ kind = "count", count = 3 }),
				Badge.new({ kind = "count", count = 150 }),
				Badge.new({ kind = "text", text = "Elite", tone = "warning" }),
				Badge.new({ kind = "text", text = "Info", tone = "info" }),
			}),
		}),
	}
end

local function icons(_scope: Trove): { Instance }
	local keys = Registry.keys()
	table.sort(keys)
	table.insert(keys, "equipment/rammer")
	table.insert(keys, "unknown/category")
	local grid = VirtualGrid.new({
		items = keys,
		cell = Vector2.new(132, 104),
		gap = 8,
		padding = 8,
		Size = UDim2.new(1, 0, 0, 640),
		render = function(item: State.State<any>, _index: State.State<number>): GuiObject
			return Create.TextButton({
				Name = "IconCell",
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.color("bg.inset"),
				BorderSizePixel = 0,
				Selectable = true,
				[Create.Children] = {
					Icon.new({
						key = State.map(item, function(key: any): string
							return tostring(key)
						end),
						size = 48,
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 10),
					}) :: Instance,
					Text.new({
						text = State.map(item, function(key: any): string
							return tostring(key)
						end),
						role = "micro",
						upper = false,
						color = "text.tertiary",
						align = "center",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -8),
						Size = UDim2.new(1, -8, 0, 14),
					}),
				},
			})
		end,
	})
	return {
		group(`Icons ({#keys} keys; last two show the category badge fallback)`, { grid }),
	}
end

local function lists(_scope: Trove): { Instance }
	local items = {}
	for i = 1, 500 do
		table.insert(items, { id = i, name = `Vehicle {i}`, tier = (i - 1) % 11 + 1 })
	end
	local list = VirtualList.new({
		items = items,
		itemSize = 56,
		gap = 4,
		padding = 8,
		Size = UDim2.new(1, 0, 0, 560),
		render = function(item: State.State<any>, index: State.State<number>): GuiObject
			return Card.new({
				Name = "VehicleRow",
				onActivated = function() end,
				padding = 8,
				list = { direction = "x", gap = Theme.space(3), align = "center" },
				children = {
					Text.new({
						text = State.map(index, function(i: number): string
							return string.format("%03d", i)
						end),
						role = "mono",
						color = "text.tertiary",
						LayoutOrder = 1,
					}) :: any,
					Badge.new({
						kind = "tier",
						tier = State.map(item, function(v: any): number
							return v.tier
						end),
						size = 28,
						LayoutOrder = 2,
					}),
					Text.new({
						text = State.map(item, function(v: any): string
							return v.name
						end),
						role = "body",
						LayoutOrder = 3,
					}),
				},
			})
		end,
	})
	return {
		group("VirtualList — 500 rows, pooled (gamepad scrolls the selection into view)", { list }),
	}
end

local BUILDERS: { [string]: (scope: Trove) -> { Instance } } = {
	foundations = foundations,
	buttons = buttons,
	inputs = inputs,
	surfaces = surfaces,
	feedback = feedback,
	data = data,
	icons = icons,
	lists = lists,
}

--- Builds one section's scroll frame (exposed for tests and for embedding a single section elsewhere).
function KitGallery.buildSection(id: SectionId, scope: Trove): ScrollingFrame
	local builder = BUILDERS[id]
	if builder == nil then
		error(`KitGallery: unknown section "{tostring(id)}"`, 2)
	end
	order = 0
	local ok, result = pcall(builder, scope)
	local children: { Instance }
	if ok then
		children = result
	else
		children = {
			EmptyState.new({
				icon = "ui/error",
				title = "Section failed to build",
				body = tostring(result),
				Size = UDim2.new(1, 0, 0, 240),
			}),
		}
	end
	return ScrollFrame.new({
		Name = "Section_" .. id,
		list = { gap = Theme.space(4) },
		padding = { x = Theme.space(5), y = Theme.space(4) },
		children = children,
	})
end

local function controls(scope: Trove): Frame
	local scheme = State.Value(Theme.state.scheme:peek() :: string, { scope = scope })
	local highContrast = State.Value(Theme.state.highContrast:peek(), { scope = scope })
	local reduced = State.Value(Theme.state.reducedMotion:peek(), { scope = scope })
	local textScale = State.Value(Theme.state.textScale:peek(), { scope = scope })
	local inputPreview = State.Value(InputMode.mode:peek() :: string, { scope = scope })
	State.observe(scheme, function(value: string)
		Theme.set({ scheme = value :: any })
	end, { scope = scope })
	State.observe(highContrast, function(value: boolean)
		Theme.set({ highContrast = value })
	end, { scope = scope })
	State.observe(reduced, function(value: boolean)
		Theme.set({ reducedMotion = value })
	end, { scope = scope })
	State.observe(textScale, function(value: number)
		Theme.set({ textScale = value })
	end, { scope = scope })
	State.observe(inputPreview, function(value: string)
		InputMode.set(value :: any)
	end, { scope = scope })
	local schemeTabs = {}
	for _, name in Theme.SCHEMES do
		table.insert(schemeTabs, { id = name :: string, label = SCHEME_LABELS[name] })
	end
	return Create.Frame({
		Name = "Controls",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = 2,
		[Create.Children] = {
			Layout.list({ direction = "x", gap = Theme.space(4), align = "center" }) :: Instance,
			TabBar.new({
				Name = "SchemeTabs",
				tabs = schemeTabs,
				selected = scheme,
				variant = "segmented",
				Size = UDim2.fromOffset(380, 36),
				LayoutOrder = 1,
			}),
			Toggle.new({
				label = "High contrast",
				value = highContrast,
				Size = UDim2.fromOffset(220, 44),
				LayoutOrder = 2,
			}),
			Toggle.new({ label = "Reduced motion", value = reduced, Size = UDim2.fromOffset(230, 44), LayoutOrder = 3 }),
			Slider.new({
				label = "Text scale",
				value = textScale,
				min = Theme.TEXT_SCALE_MIN,
				max = Theme.TEXT_SCALE_MAX,
				step = 0.1,
				Size = UDim2.fromOffset(240, 56),
				LayoutOrder = 4,
			}),
			Dropdown.new({
				Name = "InputPreview",
				options = {
					{ value = "MouseKeyboard", label = "Mouse & keyboard" },
					{ value = "Gamepad", label = "Gamepad" },
					{ value = "Touch", label = "Touch" },
				},
				selected = inputPreview,
				width = 220,
				LayoutOrder = 5,
			}),
		},
	})
end

--- Builds the gallery root (the Router screen's build function).
function KitGallery.build(ctx: Router.ScreenContext): Frame
	local scope = ctx.scope
	local selected = State.Value("foundations", { scope = scope })
	local built: { [string]: ScrollingFrame } = {}
	local content = Create.Frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -(72 + 56 + Theme.sizes.tabHeight + 3 * Theme.space(2))),
		LayoutOrder = 4,
	})
	local function show(id: string)
		if not built[id] then
			local section = KitGallery.buildSection(id :: SectionId, scope)
			section.Parent = content
			built[id] = section
		end
		for name, section in built do
			section.Visible = name == id
		end
	end
	State.observe(selected, show, { scope = scope, immediate = true })
	return Create.Frame({
		Name = "KitGallery",
		BackgroundColor3 = Theme.color("bg.base"),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		[Create.Children] = {
			Layout.list({ gap = Theme.space(2) }) :: Instance,
			Layout.padding({ x = Theme.space(5), top = Theme.space(3) }),
			Create.Frame({
				Name = "Header",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 72),
				LayoutOrder = 1,
				[Create.Children] = {
					Layout.list({ gap = 0 }) :: Instance,
					Text.h1("UI Kit", { LayoutOrder = 1 }),
					Text.caption(
						"Every component, every state. Theme and input controls apply globally.",
						{ LayoutOrder = 2 }
					),
				},
			}),
			controls(scope),
			TabBar.new({
				Name = "SectionTabs",
				tabs = KitGallery.SECTIONS,
				selected = selected,
				LayoutOrder = 3,
			}),
			content,
		},
	})
end

--- The Router screen module.
KitGallery.Screen = Router.define({ build = KitGallery.build })

--- Registers the gallery on a router as "KitGallery" (fade transition).
function KitGallery.register(router: Router.Router)
	if not router:isRegistered(KitGallery.NAME) then
		router:register(KitGallery.NAME, KitGallery.Screen, { transition = "fade" })
	end
end

return KitGallery
