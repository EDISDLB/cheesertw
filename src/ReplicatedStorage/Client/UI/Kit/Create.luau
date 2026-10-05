--!strict
--[[
	Kit/Create — declarative instance builder with reactive bindings.

	Purpose:          `Create("Frame", { Size = ..., BackgroundColor3 = Theme.color("bg.panel"), [Create.Children] =
	                  {...} })` builds an Instance tree. Any property/attribute value may be a State (Value/Computed):
	                  it is applied immediately and kept in sync until the instance is destroyed.
	Dependencies:     Kit/State, Core/Trove, Core/Log.
	State:            None at module level. Per instance (only when needed): a Trove holding bindings, connections and
	                  Cleanup entries, destroyed by the instance's Destroying event.
	Validation:       Unknown special keys, invalid property names/values and missing events raise errors that name the
	                  class and key (fail fast while building). Binding updates that fail later are logged instead.
	Error handling:   Build-time errors raise (level 2, caller's line); runtime binding failures log via "UI.Create".
	Performance notes: Constant props cost one guarded assignment; a State prop costs one non-rooted effect. Parent is
	                  assigned last so a subtree is built before it enters the DataModel (one layout/replication pass).

	Special keys (use as table keys):
	  [Create.Children] = { child, { nested }, Name = child, state }   -- arrays flatten; string keys set child.Name;
	                                                                   -- a State of instance(s) re-parents on change
	  numeric entries in props are children too:  Create("Frame", { Size = s, Create("UICorner", {}) })
	  [Create.Ref] = valueOrFunction          -- Value<Instance?>:set(instance) or fn(instance)
	  [Create.On("Activated")] = fn           -- connects instance.Activated (cleaned with the instance)
	  [Create.Change("AbsoluteSize")] = fn    -- fn(newValue) on GetPropertyChangedSignal
	  [Create.Attribute("Rarity")] = v        -- SetAttribute (State allowed)
	  [Create.Tag] = "Name" | { "A", "B" }    -- Instance:AddTag
	  [Create.Cleanup] = x | { x, y }         -- anything a Trove can clean, run when the instance is destroyed

	Typing approach (--!strict): Luau cannot type a props table per class without type functions (banned by
	research 09 R1.2), so props are `{ [any]: any }` and validated at runtime. Return types come from the typed
	shortcuts (`Create.Frame(props): Frame`, `Create.TextLabel(props): TextLabel`, ...); the generic form returns
	`Instance`. Components expose typed props tables of their own.
]]

local State = require("./State")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

type Trove = Trove.Trove
type State<T> = State.State<T>

export type Props = { [any]: any }
export type Child = any
export type Children = { [any]: Child }

export type SpecialKey = {
	kind: "Children" | "Ref" | "On" | "Change" | "Attribute" | "Tag" | "Cleanup",
	name: string,
}

local log = Log.scope("UI.Create")

local SpecialKeyClass = { __type = "UICreateSpecialKey" }
SpecialKeyClass.__index = SpecialKeyClass
SpecialKeyClass.__tostring = function(self: SpecialKey): string
	return `Create.{self.kind}({self.name})`
end

local function newSpecialKey(kind: any, name: string): SpecialKey
	return setmetatable({ kind = kind, name = name }, SpecialKeyClass) :: any
end

local function isSpecialKey(value: any): boolean
	return type(value) == "table" and getmetatable(value) == SpecialKeyClass
end

local CHILDREN = newSpecialKey("Children", "Children")
local REF = newSpecialKey("Ref", "Ref")
local TAG = newSpecialKey("Tag", "Tag")
local CLEANUP = newSpecialKey("Cleanup", "Cleanup")

local onKeys: { [string]: SpecialKey } = {}
local changeKeys: { [string]: SpecialKey } = {}
local attributeKeys: { [string]: SpecialKey } = {}

local function cachedKey(cache: { [string]: SpecialKey }, kind: string, name: string): SpecialKey
	if type(name) ~= "string" or name == "" then
		error(`Create.{kind} expects a non-empty name`, 3)
	end
	local key = cache[name]
	if key == nil then
		key = newSpecialKey(kind, name)
		cache[name] = key
	end
	return key
end

local function className(instance: Instance): string
	local ok, name = pcall(function()
		return instance.ClassName
	end)
	return if ok then tostring(name) else "Instance"
end

local function describe(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", value)
	end
	return `{kind}({tostring(value)})`
end

local function assign(instance: Instance, key: string, value: any): (boolean, string?)
	local ok, err = pcall(function()
		(instance :: any)[key] = value
	end)
	if ok then
		return true, nil
	end
	return false, `cannot set {className(instance)}.{key} = {describe(value)}: {err}`
end

-- Per-call build context: the trove is created lazily (constant-only instances never get one).
type Context = { instance: Instance, trove: Trove? }

local function getTrove(ctx: Context): Trove
	local trove = ctx.trove
	if trove ~= nil then
		return trove
	end
	local newTrove = Trove.new()
	ctx.trove = newTrove
	local instance = ctx.instance
	local ok, err = pcall(function()
		newTrove:Connect(instance.Destroying, function()
			newTrove:Destroy()
		end)
	end)
	if not ok then
		error(`Create: {className(instance)} has no Destroying event ({err})`, 0)
	end
	return newTrove
end

local function bindProperty(ctx: Context, key: string, state: State<any>)
	local instance = ctx.instance
	local first = true
	local firstError: string? = nil
	local dispose = State.bindEffect(function()
		local value = state:get()
		local ok, err = assign(instance, key, value)
		if not ok then
			if first then
				firstError = err
			else
				log:error("binding update failed: %s", tostring(err))
			end
		end
		first = false
	end, `{className(instance)}.{key}`)
	if firstError ~= nil then
		dispose()
		error(`Create: {firstError}`, 0)
	end
	getTrove(ctx):Add(dispose)
end

local function setAttribute(instance: Instance, name: string, value: any)
	local ok, err = pcall(function()
		instance:SetAttribute(name, value)
	end)
	if not ok then
		error(`Create: cannot set attribute {name} on {className(instance)} to {describe(value)}: {err}`, 0)
	end
end

local function bindAttribute(ctx: Context, name: string, value: any)
	if State.isState(value) then
		local instance = ctx.instance
		local dispose = State.bindEffect(function()
			local current = (value :: State<any>):get()
			local ok, err = pcall(function()
				instance:SetAttribute(name, current)
			end)
			if not ok then
				log:error("attribute binding %s failed: %s", name, tostring(err))
			end
		end, `attribute {name}`)
		getTrove(ctx):Add(dispose)
	else
		setAttribute(ctx.instance, name, value)
	end
end

-- Flattens a children value into `out` (Instances only); string keys name their child.
local function collectChildren(value: any, out: { Instance }, states: { State<any> }?)
	if value == nil or value == false then
		return
	end
	local kind = typeof(value)
	if kind == "Instance" then
		table.insert(out, value)
		return
	end
	if State.isState(value) then
		if states == nil then
			-- Nested states inside a state's value are not supported.
			error("Create: a State inside a Children State value is not supported", 0)
		end
		table.insert(states, value)
		return
	end
	if kind ~= "table" then
		error(`Create: invalid child {describe(value)} (expected Instance, array, State or nil)`, 0)
	end
	for key, child in value do
		if type(key) == "string" and typeof(child) == "Instance" then
			child.Name = key
		end
		collectChildren(child, out, states)
	end
end

local function bindChildrenState(ctx: Context, state: State<any>)
	local instance = ctx.instance
	local current: { [Instance]: boolean } = {}
	local dispose = State.bindEffect(function()
		local value = state:get()
		local list: { Instance } = {}
		local ok, err = pcall(collectChildren :: any, value, list, nil)
		if not ok then
			log:error("children binding on %s failed: %s", className(instance), tostring(err))
			return
		end
		local nextSet: { [Instance]: boolean } = {}
		for _, child in list do
			nextSet[child] = true
		end
		for child in current do
			if not nextSet[child] and child.Parent == instance then
				child.Parent = nil
			end
		end
		for _, child in list do
			if child.Parent ~= instance then
				child.Parent = instance
			end
		end
		current = nextSet
	end, `{className(instance)}.Children`)
	getTrove(ctx):Add(dispose)
end

local function applyChildren(ctx: Context, value: any)
	local list: { Instance } = {}
	local states: { State<any> } = {}
	collectChildren(value, list, states)
	for _, child in list do
		child.Parent = ctx.instance
	end
	for _, state in states do
		bindChildrenState(ctx, state)
	end
end

local function connectEvent(ctx: Context, eventName: string, handler: any)
	if type(handler) ~= "function" then
		error(`Create: [On("{eventName}")] expects a function, got {typeof(handler)}`, 0)
	end
	local instance = ctx.instance
	local ok, signal = pcall(function()
		return (instance :: any)[eventName]
	end)
	if not ok or signal == nil or (typeof(signal) ~= "RBXScriptSignal" and type(signal) ~= "table") then
		error(`Create: {className(instance)} has no event "{eventName}"`, 0)
	end
	getTrove(ctx):Connect(signal, handler)
end

local function connectChange(ctx: Context, property: string, handler: any)
	if type(handler) ~= "function" then
		error(`Create: [Change("{property}")] expects a function, got {typeof(handler)}`, 0)
	end
	local instance = ctx.instance
	local ok, signal = pcall(function()
		return instance:GetPropertyChangedSignal(property)
	end)
	if not ok or signal == nil then
		error(`Create: {className(instance)} has no property "{property}" to observe`, 0)
	end
	getTrove(ctx):Connect(signal, function()
		handler((instance :: any)[property])
	end)
end

local function applyTags(instance: Instance, value: any)
	local tags: { string } = if type(value) == "string" then { value } else value
	if type(tags) ~= "table" then
		error(`Create: [Tag] expects a string or array of strings, got {typeof(value)}`, 0)
	end
	for _, tag in tags do
		if type(tag) ~= "string" then
			error("Create: [Tag] entries must be strings", 0)
		end
		instance:AddTag(tag)
	end
end

local function applyCleanup(ctx: Context, value: any)
	local trove = getTrove(ctx)
	if type(value) == "table" and getmetatable(value) == nil and #value > 0 then
		for _, item in value do
			trove:Add(item)
		end
	else
		trove:Add(value)
	end
end

local function applyRef(instance: Instance, value: any)
	if type(value) == "function" then
		value(instance)
	elseif State.isState(value) and type((value :: any).set) == "function" then
		(value :: any):set(instance)
	else
		error(`Create: [Ref] expects a Value or a function, got {typeof(value)}`, 0)
	end
end

local function applyProps(instance: Instance, props: Props?, extraChildren: Children?)
	local ctx: Context = { instance = instance, trove = nil }
	if props == nil and extraChildren == nil then
		return
	end
	local properties: { [string]: any } = {}
	local parent: any = nil
	local hasParent = false
	local childValues: { any } = {}
	local events: { [string]: any } = {}
	local changes: { [string]: any } = {}
	local attributes: { [string]: any } = {}
	local tags: any = nil
	local ref: any = nil
	local cleanup: any = nil

	local propsTable: Props = props or {}
	for key, value in propsTable do
		if type(key) == "string" then
			if key == "Parent" then
				parent = value
				hasParent = true
			else
				properties[key] = value
			end
		elseif type(key) == "number" then
			table.insert(childValues, value)
		elseif isSpecialKey(key) then
			local special = key :: SpecialKey
			local kind = special.kind
			if kind == "Children" then
				table.insert(childValues, value)
			elseif kind == "On" then
				events[special.name] = value
			elseif kind == "Change" then
				changes[special.name] = value
			elseif kind == "Attribute" then
				attributes[special.name] = value
			elseif kind == "Tag" then
				tags = value
			elseif kind == "Ref" then
				ref = value
			elseif kind == "Cleanup" then
				cleanup = value
			end
		else
			error(`Create: invalid props key {describe(key)} for {className(instance)}`, 0)
		end
	end
	if extraChildren ~= nil then
		table.insert(childValues, extraChildren)
	end

	for key, value in properties do
		if State.isState(value) then
			bindProperty(ctx, key, value)
		else
			local ok, err = assign(instance, key, value)
			if not ok then
				error(`Create: {err}`, 0)
			end
		end
	end
	for name, value in attributes do
		bindAttribute(ctx, name, value)
	end
	if tags ~= nil then
		applyTags(instance, tags)
	end
	for _, value in childValues do
		applyChildren(ctx, value)
	end
	for name, handler in events do
		connectEvent(ctx, name, handler)
	end
	for property, handler in changes do
		connectChange(ctx, property, handler)
	end
	if hasParent then
		if State.isState(parent) then
			bindProperty(ctx, "Parent", parent)
		else
			local ok, err = assign(instance, "Parent", parent)
			if not ok then
				error(`Create: {err}`, 0)
			end
		end
	end
	if ref ~= nil then
		applyRef(instance, ref)
	end
	if cleanup ~= nil then
		applyCleanup(ctx, cleanup)
	end
end

local function build(class: string, props: Props?, children: Children?): Instance
	if type(class) ~= "string" then
		error(`Create expects a class name string, got {typeof(class)}`, 3)
	end
	local ok, instanceOrErr = pcall(function()
		return Instance.new(class :: any)
	end)
	if not ok then
		error(`Create: cannot create "{class}": {instanceOrErr}`, 3)
	end
	local instance: Instance = instanceOrErr
	local okProps, err = pcall(applyProps :: any, instance, props, children)
	if not okProps then
		instance:Destroy()
		error(err, 3)
	end
	return instance
end

local Create = {}

Create.Children = CHILDREN
Create.Ref = REF
Create.Tag = TAG
Create.Cleanup = CLEANUP

--- Event handler key: `[Create.On("Activated")] = function() ... end`.
function Create.On(eventName: string): SpecialKey
	return cachedKey(onKeys, "On", eventName)
end

--- Property-changed handler key: `[Create.Change("AbsoluteSize")] = function(size) ... end`.
function Create.Change(propertyName: string): SpecialKey
	return cachedKey(changeKeys, "Change", propertyName)
end

--- Attribute key: `[Create.Attribute("Tier")] = 7` (State allowed).
function Create.Attribute(name: string): SpecialKey
	return cachedKey(attributeKeys, "Attribute", name)
end

--- Generic constructor (also available by calling the module: `Create("Frame", props)`).
function Create.new(class: string, props: Props?, children: Children?): Instance
	return build(class, props, children)
end

--- Applies props (bindings, children, events...) to an existing instance ("hydrate"). Bindings live until the
--- instance is destroyed.
function Create.apply<T>(instance: T, props: Props): T
	if typeof(instance) ~= "Instance" then
		error("Create.apply expects an Instance", 2)
	end
	local ok, err = pcall(applyProps :: any, instance, props, nil)
	if not ok then
		error(err, 2)
	end
	return instance
end

--- Registers `item` (function, Instance, connection, object with Destroy) to be cleaned when `instance` is destroyed.
function Create.onDestroy(instance: Instance, item: any)
	local ctx: Context = { instance = instance, trove = nil }
	getTrove(ctx):Add(item)
end

--- True if `key` is one of Create's special keys.
Create.isSpecialKey = isSpecialKey

-- Typed shortcuts (return the precise class type for strict mode).
function Create.Frame(props: Props?, children: Children?): Frame
	return build("Frame", props, children) :: any
end
function Create.TextLabel(props: Props?, children: Children?): TextLabel
	return build("TextLabel", props, children) :: any
end
function Create.TextButton(props: Props?, children: Children?): TextButton
	return build("TextButton", props, children) :: any
end
function Create.TextBox(props: Props?, children: Children?): TextBox
	return build("TextBox", props, children) :: any
end
function Create.ImageLabel(props: Props?, children: Children?): ImageLabel
	return build("ImageLabel", props, children) :: any
end
function Create.ImageButton(props: Props?, children: Children?): ImageButton
	return build("ImageButton", props, children) :: any
end
function Create.ScrollingFrame(props: Props?, children: Children?): ScrollingFrame
	return build("ScrollingFrame", props, children) :: any
end
function Create.CanvasGroup(props: Props?, children: Children?): CanvasGroup
	return build("CanvasGroup", props, children) :: any
end
function Create.ViewportFrame(props: Props?, children: Children?): ViewportFrame
	return build("ViewportFrame", props, children) :: any
end
function Create.ScreenGui(props: Props?, children: Children?): ScreenGui
	return build("ScreenGui", props, children) :: any
end
function Create.Folder(props: Props?, children: Children?): Folder
	return build("Folder", props, children) :: any
end
function Create.UICorner(props: Props?): UICorner
	return build("UICorner", props, nil) :: any
end
function Create.UIStroke(props: Props?, children: Children?): UIStroke
	return build("UIStroke", props, children) :: any
end
function Create.UIGradient(props: Props?): UIGradient
	return build("UIGradient", props, nil) :: any
end
function Create.UIPadding(props: Props?): UIPadding
	return build("UIPadding", props, nil) :: any
end
function Create.UIListLayout(props: Props?): UIListLayout
	return build("UIListLayout", props, nil) :: any
end
function Create.UIGridLayout(props: Props?): UIGridLayout
	return build("UIGridLayout", props, nil) :: any
end
function Create.UIScale(props: Props?): UIScale
	return build("UIScale", props, nil) :: any
end
function Create.UISizeConstraint(props: Props?): UISizeConstraint
	return build("UISizeConstraint", props, nil) :: any
end
function Create.UITextSizeConstraint(props: Props?): UITextSizeConstraint
	return build("UITextSizeConstraint", props, nil) :: any
end
function Create.UIAspectRatioConstraint(props: Props?): UIAspectRatioConstraint
	return build("UIAspectRatioConstraint", props, nil) :: any
end
function Create.UIFlexItem(props: Props?): UIFlexItem
	return build("UIFlexItem", props, nil) :: any
end
function Create.UIPageLayout(props: Props?): UIPageLayout
	return build("UIPageLayout", props, nil) :: any
end

local function call(_self: any, class: string, props: Props?, children: Children?): Instance
	return build(class, props, children)
end

return setmetatable(Create, { __call = call })
