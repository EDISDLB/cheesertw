--[[
	MockRunService — RunService stand-in with manual frame stepping and settable environment flags.

	Purpose:          Drive Heartbeat/Stepped/RenderStepped deterministically and fake IsServer/IsClient/IsStudio.
	Dependencies:     MockInstance, Core/Signal (via MockInstance signals).
	State:            Flags, elapsed simulated time, render-step bindings.
	Validation:       step(dt) requires dt >= 0.
	Error handling:   Callback errors propagate through Signal's handler error logging (never abort a step).
	Performance notes: Test-only.

	API: runService:step(dt) fires PreSimulation, Stepped(time, dt), Heartbeat(dt), PostSimulation(dt), then
	     BindToRenderStep callbacks (priority order) and RenderStepped(dt) when IsClient().
	     setServer(bool) / setClient(bool) / setStudio(bool) / setRunning(bool).
]]

local MockInstance = require("./MockInstance")

local MockRunService = {}

MockInstance.defineClass("RunService", {
	signals = {
		"Heartbeat",
		"Stepped",
		"RenderStepped",
		"PreSimulation",
		"PostSimulation",
		"PreRender",
		"PreAnimation",
	},
	init = function(inst: any)
		rawset(inst, "_flags", { server = true, client = false, studio = true, running = true })
		rawset(inst, "_time", 0)
		rawset(inst, "_bindings", {})
	end,
	methods = {
		IsServer = function(self: any): boolean
			return rawget(self, "_flags").server
		end,
		IsClient = function(self: any): boolean
			return rawget(self, "_flags").client
		end,
		IsStudio = function(self: any): boolean
			return rawget(self, "_flags").studio
		end,
		IsRunning = function(self: any): boolean
			return rawget(self, "_flags").running
		end,
		IsRunMode = function(self: any): boolean
			return rawget(self, "_flags").running
		end,
		IsEdit = function(_self: any): boolean
			return false
		end,
		setServer = function(self: any, value: boolean)
			rawget(self, "_flags").server = value
		end,
		setClient = function(self: any, value: boolean)
			rawget(self, "_flags").client = value
		end,
		setStudio = function(self: any, value: boolean)
			rawget(self, "_flags").studio = value
		end,
		setRunning = function(self: any, value: boolean)
			rawget(self, "_flags").running = value
		end,
		BindToRenderStep = function(self: any, name: string, priority: number, fn: (number) -> ())
			local bindings = rawget(self, "_bindings")
			for i, b in bindings do
				if b.name == name then
					table.remove(bindings, i)
					break
				end
			end
			table.insert(bindings, { name = name, priority = priority, fn = fn })
			table.sort(bindings, function(a, b)
				return a.priority < b.priority
			end)
		end,
		UnbindFromRenderStep = function(self: any, name: string)
			local bindings = rawget(self, "_bindings")
			for i, b in bindings do
				if b.name == name then
					table.remove(bindings, i)
					return
				end
			end
		end,
		elapsed = function(self: any): number
			return rawget(self, "_time")
		end,
		step = function(self: any, dt: number?)
			local delta = dt or 1 / 60
			assert(delta >= 0, "MockRunService:step dt must be >= 0")
			local t = rawget(self, "_time") + delta
			rawset(self, "_time", t)
			self.PreSimulation:Fire(delta)
			self.Stepped:Fire(t, delta)
			self.Heartbeat:Fire(delta)
			self.PostSimulation:Fire(delta)
			if rawget(self, "_flags").client then
				self.PreRender:Fire(delta)
				for _, b in table.clone(rawget(self, "_bindings")) do
					b.fn(delta)
				end
				self.RenderStepped:Fire(delta)
			end
		end,
	},
})

function MockRunService.new(): any
	local rs = MockInstance.new("RunService")
	rs.Name = "RunService"
	return rs
end

return MockRunService
