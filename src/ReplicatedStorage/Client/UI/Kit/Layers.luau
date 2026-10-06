--!strict
--[[
	Kit/Layers — registry of the overlay containers (Modals, Toasts, Tooltip...) created by the Router.

	Purpose:          Components that render outside their own subtree (tooltips, dropdown lists, dialogs, toasts)
	                  ask `Layers.get("Tooltip")` for the right ScreenGui content root instead of guessing.
	Dependencies:     Theme (Layer type only).
	State:            name -> container map (one active container per layer).
	Validation:       register requires an Instance.
	Error handling:   `parentFor` falls back to the anchor's ScreenGui, then nil (caller decides).
	Performance notes: Table lookups only. `toLocal` maps screen px into a layer root's content coordinates (its
	                  UIScale AND its UIPadding — the TV-safe margin), so overlays placed next to an element land on it.
]]

local Theme = require("./Theme")

type Layer = Theme.Layer

local Layers = {}

local containers: { [string]: Instance } = {}

--- Registers the content root of a layer (the Router does this for every ScreenGui it creates).
function Layers.register(name: Layer, container: Instance)
	if typeof(container) ~= "Instance" then
		error("Layers.register expects an Instance", 2)
	end
	containers[name] = container
end

--- Removes a layer registration (only if `container` is still the registered one).
function Layers.unregister(name: Layer, container: Instance?)
	if container == nil or containers[name] == container then
		containers[name] = nil
	end
end

function Layers.get(name: Layer): Instance?
	local container: Instance? = containers[name]
	if container == nil then
		return nil
	end
	local parent: Instance? = container.Parent
	if parent == nil then
		containers[name] = nil
		return nil
	end
	return container
end

--- Where to put an overlay: the registered layer, else the anchor's ScreenGui, else nil.
function Layers.parentFor(name: Layer, anchor: Instance?): Instance?
	local layer = Layers.get(name)
	if layer ~= nil then
		return layer
	end
	if anchor ~= nil then
		local screenGui = anchor:FindFirstAncestorWhichIsA("LayerCollector")
		if screenGui ~= nil then
			return screenGui
		end
	end
	return nil
end

--- Converts a screen-space point (AbsolutePosition px) into offsets for a child of `container`: subtracts the
--- container's origin and its UIPadding (scale + offset; the layer roots carry the 5 % TV-safe margin) and divides by
--- its UIScale (layer roots are authored in reference px). Use it for every overlay placed at an element.
function Layers.toLocal(container: Instance, point: Vector2): Vector2
	local origin = Vector2.new(0, 0)
	local size = Vector2.new(0, 0)
	if container:IsA("GuiBase2d") then
		origin = (container :: GuiBase2d).AbsolutePosition
		size = (container :: GuiBase2d).AbsoluteSize
	end
	local scale = 1
	local uiScale = container:FindFirstChildOfClass("UIScale")
	if uiScale ~= nil and uiScale.Scale > 0 then
		scale = uiScale.Scale
	end
	local padding = container:FindFirstChildOfClass("UIPadding")
	if padding ~= nil then
		local left, top = padding.PaddingLeft, padding.PaddingTop
		origin += Vector2.new(left.Scale * size.X + left.Offset * scale, top.Scale * size.Y + top.Offset * scale)
	end
	return (point - origin) / scale
end

function Layers.clear()
	table.clear(containers)
end

return Layers
