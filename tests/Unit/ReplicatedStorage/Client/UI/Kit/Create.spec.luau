local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")

local describe, it, expect = Test.describe, Test.it, Test.expect

Support.install()

describe("Create", function()
	it("creates instances with properties and assigns Parent last", function()
		local parent = Create("Frame", { Name = "Parent" })
		local sizeWhenParented = nil
		parent.ChildAdded:Connect(function(child)
			sizeWhenParented = child.Size
		end)
		local frame = Create("Frame", {
			Name = "Child",
			Size = UDim2.fromOffset(10, 20),
			Parent = parent,
		})
		expect(frame.ClassName).toBe("Frame")
		expect(frame.Parent).toBe(parent)
		expect(sizeWhenParented).toEqual(UDim2.fromOffset(10, 20))
		Support.validateTree(parent)
	end)

	it("supports the callable form, Create.new and typed shortcuts", function()
		expect(Create.new("TextLabel", { Text = "a" }).Text).toBe("a")
		expect(Create.TextButton({ Text = "b" }).ClassName).toBe("TextButton")
		expect(Create.UICorner({ CornerRadius = UDim.new(0, 4) }).CornerRadius).toEqual(UDim.new(0, 4))
		expect(Create.Frame().ClassName).toBe("Frame")
	end)

	it("parents children from [Children], numeric entries and the third argument; string keys name them", function()
		local a = Create("Frame", {})
		local b = Create("Frame", {})
		local c = Create("Frame", {})
		local d = Create("Frame", {})
		local root = Create("Frame", {
			[Create.Children] = { a, { b, Named = c }, nil, false },
			Create("UICorner", {}),
		}, { d })
		expect(a.Parent).toBe(root)
		expect(b.Parent).toBe(root)
		expect(c.Parent).toBe(root)
		expect(c.Name).toBe("Named")
		expect(d.Parent).toBe(root)
		expect(root:FindFirstChildOfClass("UICorner")).never.toBeNil()
	end)

	it("binds State properties and unbinds when destroyed", function()
		local baseline = State.stats().liveEffects
		local text = State.Value("one")
		local visible = State.Value(true)
		local label = Create("TextLabel", { Text = text, Visible = visible })
		expect(label.Text).toBe("one")
		text:set("two")
		expect(label.Text).toBe("two")
		visible:set(false)
		expect(label.Visible).toBe(false)
		expect(State.stats().liveEffects).toBe(baseline)
		label:Destroy()
		text:set("three")
		expect(label.Text).toBe("two")
	end)

	it("binds Computeds and destroys descendant bindings with the ancestor", function()
		local n = State.Value(1)
		local child = Create("TextLabel", {
			Text = State.Computed(function()
				return `n={n:get()}`
			end),
		})
		local root = Create("Frame", { [Create.Children] = { child } })
		n:set(2)
		expect(child.Text).toBe("n=2")
		root:Destroy()
		n:set(3)
		expect(child.Text).toBe("n=2")
	end)

	it("connects events and property-change handlers", function()
		local clicks = 0
		local sizes = {}
		local button = Create("TextButton", {
			[Create.On("Activated")] = function()
				clicks += 1
			end,
			[Create.Change("Text")] = function(newText)
				table.insert(sizes, newText)
			end,
		})
		Support.click(button)
		button.Text = "changed"
		expect(clicks).toBe(1)
		expect(sizes).toEqual({ "changed" })
		button:Destroy()
		expect(clicks).toBe(1)
	end)

	it("sets attributes (constant and reactive) and tags", function()
		local tier = State.Value(5)
		local frame = Create("Frame", {
			[Create.Attribute("Kind")] = "card",
			[Create.Attribute("Tier")] = tier,
			[Create.Tag] = { "KitCard", "Selectable" },
		})
		expect(frame:GetAttribute("Kind")).toBe("card")
		expect(frame:GetAttribute("Tier")).toBe(5)
		tier:set(7)
		expect(frame:GetAttribute("Tier")).toBe(7)
		expect(frame:GetTags()).toEqual({ "KitCard", "Selectable" })
		local single = Create("Frame", { [Create.Tag] = "One" })
		expect(single:HasTag("One")).toBe(true)
	end)

	it("supports Ref as a Value or a function", function()
		local ref = State.Value(nil :: any)
		local seen = nil
		local a = Create("Frame", { [Create.Ref] = ref })
		local b = Create("Frame", {
			[Create.Ref] = function(instance)
				seen = instance
			end,
		})
		expect(ref:peek()).toBe(a)
		expect(seen).toBe(b)
	end)

	it("runs Cleanup entries when the instance is destroyed", function()
		local log = {}
		local frame = Create("Frame", {
			[Create.Cleanup] = {
				function()
					table.insert(log, "first")
				end,
				function()
					table.insert(log, "second")
				end,
			},
		})
		local other = Create("Frame", {
			[Create.Cleanup] = function()
				table.insert(log, "single")
			end,
		})
		frame:Destroy()
		other:Destroy()
		expect(log).toEqual({ "second", "first", "single" })
	end)

	it("re-parents children bound to a State", function()
		local a = Create("Frame", { Name = "A" })
		local b = Create("Frame", { Name = "B" })
		local children = State.Value({ a } :: { any })
		local root = Create("Frame", { [Create.Children] = children })
		expect(a.Parent).toBe(root)
		children:set({ b })
		expect(a.Parent).toBeNil()
		expect(b.Parent).toBe(root)
		children:set({ a, b })
		expect(a.Parent).toBe(root)
		expect(b.Parent).toBe(root)
	end)

	it("renders keyed lists through State.list", function()
		local items = State.Value({ "x", "y" })
		local root = Create("Frame", {
			[Create.Children] = State.list(items, function(item)
				return item
			end, function(item, index)
				return Create("TextLabel", {
					Name = item:peek(),
					Text = item,
					LayoutOrder = index,
				})
			end),
		})
		local x = root:FindFirstChild("x")
		expect(x).never.toBeNil()
		expect(root:FindFirstChild("y").LayoutOrder).toBe(2)
		items:set({ "y", "z" })
		expect(root:FindFirstChild("x")).toBeNil()
		expect(root:FindFirstChild("y").LayoutOrder).toBe(1)
		expect(root:FindFirstChild("z")).never.toBeNil()
		expect(rawget(x, "_destroyed")).toBe(true)
	end)

	it("hydrates existing instances with Create.apply and registers cleanups with onDestroy", function()
		local existing = Instance.new("Frame")
		local color = State.Value(Color3.new(1, 0, 0))
		local returned = Create.apply(existing, { BackgroundColor3 = color, Name = "Hydrated" })
		expect(returned).toBe(existing)
		expect(existing.Name).toBe("Hydrated")
		color:set(Color3.new(0, 1, 0))
		expect(existing.BackgroundColor3).toEqual(Color3.new(0, 1, 0))
		local cleaned = false
		Create.onDestroy(existing, function()
			cleaned = true
		end)
		existing:Destroy()
		expect(cleaned).toBe(true)
	end)

	it("raises clear errors for invalid input", function()
		expect(function()
			Create("Frame", { ClassName = "Nope" })
		end).toThrow("cannot set Frame.ClassName")
		expect(function()
			Create("Frame", { [Create.On("NotAnEvent")] = function() end })
		end).toThrow('has no event "NotAnEvent"')
		expect(function()
			Create("Frame", { [true :: any] = 1 })
		end).toThrow("invalid props key")
		expect(function()
			Create("Frame", { [Create.Ref] = 5 })
		end).toThrow("[Ref] expects")
		expect(function()
			Create("Frame", { [Create.Children] = { 5 } })
		end).toThrow("invalid child")
		expect(function()
			Create.On("")
		end).toThrow("non-empty name")
		expect(function()
			(Create :: any)(5)
		end).toThrow("class name string")
	end)

	it("caches special keys per name", function()
		expect(Create.On("Activated")).toBe(Create.On("Activated"))
		expect(Create.Change("Text")).toBe(Create.Change("Text"))
		expect(Create.Attribute("A")).toBe(Create.Attribute("A"))
		expect(Create.isSpecialKey(Create.Children)).toBe(true)
		expect(Create.isSpecialKey("Children")).toBe(false)
	end)
end)
