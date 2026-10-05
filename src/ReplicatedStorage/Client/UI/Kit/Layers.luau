--!strict
--[[
	Kit/Layers — registry of the overlay containers (Modals, Toasts, Tooltip...) created by the Router.

	Purpose:          Components that render outside their own subtree (tooltips, dropdown lists, dialogs, toasts)
	                  ask `Layers.get("Tooltip")` for the right ScreenGui content root instead of guessing.
	Dependencies:     Theme (Layer type only).
	State:            name -> container map (one active container per layer).
	Validation:       register requires an Instance.
	Error handling:   `parentFor` falls back to the anchor's ScreenGui, then nil (caller decides).
	Performance notes: Table lookups only.
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

function Layers.clear()
	table.clear(containers)
end

return Layers
