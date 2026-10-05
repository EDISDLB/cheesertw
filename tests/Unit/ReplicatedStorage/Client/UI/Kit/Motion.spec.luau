local Test = require("@tests/Harness/Test")
local Support = require("@tests/Unit/ReplicatedStorage/Client/UI/KitTestSupport")
local Motion = require("@game/ReplicatedStorage/Client/UI/Kit/Motion")
local Theme = require("@game/ReplicatedStorage/Client/UI/Kit/Theme")
local State = require("@game/ReplicatedStorage/Client/UI/Kit/State")
local Create = require("@game/ReplicatedStorage/Client/UI/Kit/Create")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

local describe, it, expect = Test.describe, Test.it, Test.expect

local env = Support.install()

local function lastTween(): any
	return env.tweens[#env.tweens]
end

describe("Motion durations and tweens", function()
	Test.beforeEach(function()
		Theme.reset()
		table.clear(env.tweens)
	end)

	it("resolves tokens and applies reduced motion per kind", function()
		expect(Motion.resolveDuration("base")).toBe(0.15)
		expect(Motion.resolveDuration(0.3, "fade")).toBe(0.3)
		expect(Motion.resolveDuration(-1)).toBe(0)
		Theme.set({ reducedMotion = true })
		expect(Motion.isReduced()).toBe(true)
		expect(Motion.resolveDuration("flourish", "move")).toBe(0)
		expect(Motion.resolveDuration("flourish", "fade")).toBe(Motion.REDUCED_FADE_MAX)
		expect(Motion.resolveDuration(0.05, "color")).toBe(0.05)
	end)

	it("plays TweenService tweens with token easing, or applies instantly", function()
		local frame = Create("Frame", { BackgroundTransparency = 1 })
		local tween = Motion.tween(frame, { BackgroundTransparency = 0.5 }, { duration = "slow", easing = "enter" })
		expect(tween).never.toBeNil()
		local args = lastTween().TweenInfo._args
		expect(args[1]).toBe(0.2)
		expect(args[2]).toBe(Enum.EasingStyle.Cubic)
		expect(args[3]).toBe(Enum.EasingDirection.Out)
		expect(frame.BackgroundTransparency).toBe(0.5)
		Theme.set({ reducedMotion = true })
		local instant = Motion.tween(frame, { BackgroundTransparency = 0.2 }, { duration = "slow" })
		expect(instant).toBeNil()
		expect(frame.BackgroundTransparency).toBe(0.2)
		expect(#env.tweens).toBe(1)
	end)

	it("fades the right property per class", function()
		local label = Create("TextLabel", {})
		Motion.fadeIn(label)
		expect(lastTween().Props).toEqual({ TextTransparency = 0 })
		local group = Create("CanvasGroup", {})
		Motion.fadeOut(group)
		expect(lastTween().Props).toEqual({ GroupTransparency = 1 })
		local image = Create("ImageLabel", {})
		Motion.fade(image, 0.5)
		expect(lastTween().Props).toEqual({ ImageTransparency = 0.5 })
		expect(function()
			Motion.fade(Instance.new("Folder"), 1)
		end).toThrow("no transparency")
		Theme.set({ reducedMotion = true })
		Motion.fade(label, 1, { duration = "flourish" })
		expect(lastTween().TweenInfo._args[1]).toBe(Motion.REDUCED_FADE_MAX)
	end)
end)

describe("Motion presets", function()
	Test.beforeEach(function()
		Theme.reset()
		table.clear(env.tweens)
		env.deferTweens = false
	end)

	it("slides in from an offset and skips movement under reduced motion", function()
		local frame = Create("Frame", { Position = UDim2.fromOffset(100, 50) })
		env.deferTweens = true
		Motion.slideIn(frame, "right")
		expect(frame.Position).toEqual(UDim2.fromOffset(124, 50))
		env:completeTweens()
		expect(frame.Position).toEqual(UDim2.fromOffset(100, 50))
		env.deferTweens = false
		Motion.slideOut(frame, "top", 10)
		expect(frame.Position).toEqual(UDim2.fromOffset(100, 40))
		Theme.set({ reducedMotion = true })
		local count = #env.tweens
		expect(Motion.slideIn(frame, "left")).toBeNil()
		expect(frame.Position).toEqual(UDim2.fromOffset(100, 40))
		expect(#env.tweens).toBe(count)
	end)

	it("pops and pulses through a MotionScale UIScale", function()
		local frame = Create("Frame", {})
		Motion.pop(frame)
		local scale = frame:FindFirstChild("MotionScale")
		expect(scale.ClassName).toBe("UIScale")
		expect(scale.Scale).toBe(1)
		env.deferTweens = true
		local stop = Motion.pulse(frame)
		local args = lastTween().TweenInfo._args
		expect(args[4]).toBe(-1)
		expect(args[5]).toBe(true)
		stop()
		expect(scale.Scale).toBe(1)
		expect(lastTween().PlaybackState).toBe(Enum.PlaybackState.Cancelled)
		Theme.set({ reducedMotion = true })
		local count = #env.tweens
		Motion.pop(frame)
		Motion.pulse(frame)()
		expect(#env.tweens).toBe(count)
	end)

	it("shakes and returns to the origin", function()
		local frame = Create("Frame", { Position = UDim2.fromOffset(10, 10) })
		Motion.shake(frame, 6, 0.3)
		env:step(1 / 60)
		env:step(1 / 60)
		local moved = frame.Position ~= UDim2.fromOffset(10, 10)
		for _ = 1, 30 do
			env:step(1 / 60)
		end
		expect(moved).toBe(true)
		expect(frame.Position).toEqual(UDim2.fromOffset(10, 10))
		Theme.set({ reducedMotion = true })
		Motion.shake(frame)
		env:step(1 / 60)
		expect(frame.Position).toEqual(UDim2.fromOffset(10, 10))
	end)

	it("counts numbers up with easing and jumps under reduced motion", function()
		local values = {}
		Motion.countUp(0, 1000, function(v)
			table.insert(values, v)
		end, { duration = 0.5 })
		for _ = 1, 40 do
			env:step(1 / 60)
		end
		expect(values[1]).toBe(0)
		expect(values[#values]).toBe(1000)
		for i = 2, #values do
			expect(values[i]).toBeGreaterThanOrEqual(values[i - 1])
		end
		expect(#values).toBeGreaterThan(10)
		Theme.set({ reducedMotion = true })
		local reduced = {}
		Motion.countUp(5, 9, function(v)
			table.insert(reduced, v)
		end)
		expect(reduced).toEqual({ 9 })
	end)

	it("stops loops early", function()
		local calls = 0
		local stop = Motion.loop(function()
			calls += 1
			return nil
		end)
		env:step()
		stop()
		env:step()
		expect(calls).toBe(1)
	end)
end)

describe("Motion math", function()
	it("eases with the standard curves", function()
		expect(Motion.ease(0, "Quad", "Out")).toBe(0)
		expect(Motion.ease(1, "Quad", "Out")).toBe(1)
		expect(Motion.ease(0.5, "Quad", "In")).toBe(0.25)
		expect(Motion.ease(0.5, "Quad", "Out")).toBe(0.75)
		expect(Motion.ease(0.5, "Cubic", "InOut")).toBeCloseTo(0.5, 1e-9)
		expect(Motion.ease(0.25, "Linear", "Out")).toBe(0.25)
		expect(Motion.ease(2, "Sine", "Out")).toBe(1)
		for _, style in { "Quad", "Cubic", "Quart", "Quint", "Sine", "Exponential", "Circular" } do
			expect(Motion.ease(0, style, "InOut")).toBeCloseTo(0, 1e-3)
			expect(Motion.ease(1, style, "InOut")).toBeCloseTo(1, 1e-3)
		end
	end)

	it("critically damped springs converge without overshoot", function()
		local x, v = 0, 0
		local maxX = 0
		for _ = 1, 120 do
			x, v = Motion.springStep(x, v, 1, 4, 1, 1 / 60)
			maxX = math.max(maxX, x)
		end
		expect(x).toBeCloseTo(1, 1e-3)
		expect(maxX).toBeLessThanOrEqual(1 + 1e-6)
	end)

	it("follow() smooths a numeric State and snaps under reduced motion", function()
		Theme.reset()
		local trove = Trove.new()
		local hp = State.Value(100)
		local shown = Motion.follow(hp, trove)
		hp:set(40)
		expect(shown:peek()).toBe(100)
		env:step(1 / 60)
		local mid = shown:peek()
		expect(mid).toBeLessThan(100)
		expect(mid).toBeGreaterThan(40)
		for _ = 1, 240 do
			env:step(1 / 60)
		end
		expect(shown:peek()).toBe(40)
		Theme.set({ reducedMotion = true })
		hp:set(10)
		expect(shown:peek()).toBe(10)
		Theme.set({ reducedMotion = false })
		trove:Destroy()
		hp:set(90)
		env:step(1 / 60)
		expect(shown:peek()).toBe(10)
	end)
end)
