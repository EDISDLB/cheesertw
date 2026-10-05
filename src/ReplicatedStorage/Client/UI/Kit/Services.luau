--!strict
--[[
	Kit/Services — lazy, typed access to the engine services the UI kit uses.

	Purpose:          One indirection so kit modules never cache services at require time: tests (and the Lune
	                  harness) install fakes with `game:setService(...)` before or after requiring kit modules.
	Dependencies:     game (DataModel), workspace.
	State:            None.
	Validation:       N/A.
	Error handling:   Missing LocalPlayer/PlayerGui/Camera return nil (server-side or headless contexts).
	Performance notes: `game:GetService` is a cheap lookup; per-frame code should hold the returned service locally.
]]

local Services = {}

function Services.tween(): TweenService
	return game:GetService("TweenService")
end

function Services.input(): UserInputService
	return game:GetService("UserInputService")
end

function Services.gui(): GuiService
	return game:GetService("GuiService")
end

function Services.run(): RunService
	return game:GetService("RunService")
end

function Services.players(): Players
	return game:GetService("Players")
end

function Services.localPlayer(): Player?
	return Services.players().LocalPlayer
end

function Services.playerGui(): PlayerGui?
	local player = Services.localPlayer()
	if player == nil then
		return nil
	end
	return player:FindFirstChildOfClass("PlayerGui")
end

function Services.camera(): Camera?
	return workspace.CurrentCamera
end

--- Current viewport size in px (1920x1080 when no camera exists yet).
function Services.viewportSize(): Vector2
	local camera = Services.camera()
	if camera ~= nil then
		local size: Vector2? = camera.ViewportSize
		if size ~= nil and size.X > 0 and size.Y > 0 then
			return size
		end
	end
	return Vector2.new(1920, 1080)
end

return Services
