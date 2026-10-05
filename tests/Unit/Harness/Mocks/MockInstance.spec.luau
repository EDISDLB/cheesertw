local Test = require("@tests/Harness/Test")
local MockPlayer = require("@tests/Harness/Mocks/MockPlayer")
local describe, it, expect = Test.describe, Test.it, Test.expect

describe("MockInstance tree", function()
	it("supports Name/Parent/children lookups like Roblox", function()
		local root = Instance.new("Folder")
		root.Name = "Root"
		local child = Instance.new("Folder", root)
		child.Name = "Child"
		local leaf = Instance.new("RemoteEvent")
		leaf.Name = "Leaf"
		leaf.Parent = child
		expect(root:FindFirstChild("Child")).toBe(child)
		expect(root.Child).toBe(child)
		expect(root:FindFirstChild("Leaf")).toBeNil()
		expect(root:FindFirstChild("Leaf", true)).toBe(leaf)
		expect(#root:GetDescendants()).toBe(2)
		expect(leaf:IsDescendantOf(root)).toBe(true)
		expect(leaf:FindFirstAncestor("Root")).toBe(root)
		expect(leaf:GetFullName()).toBe("Root.Child.Leaf")
		expect(leaf:IsA("RemoteEvent")).toBe(true)
		expect(leaf:IsA("Instance")).toBe(true)
		expect(leaf:IsA("Folder")).toBe(false)
		expect(child:FindFirstChildOfClass("RemoteEvent")).toBe(leaf)
		expect(typeof(leaf)).toBe("Instance")
		expect(tostring(leaf)).toBe("Leaf")
	end)

	it("fires ChildAdded/ChildRemoved and rejects circular parents", function()
		local a = Instance.new("Folder")
		local b = Instance.new("Folder")
		local added, removed = 0, 0
		a.ChildAdded:Connect(function()
			added += 1
		end)
		a.ChildRemoved:Connect(function()
			removed += 1
		end)
		b.Parent = a
		b.Parent = nil
		expect(added).toBe(1)
		expect(removed).toBe(1)
		b.Parent = a
		expect(function()
			a.Parent = b
		end).toThrow("circular reference")
	end)

	it("Destroy locks Parent and destroys descendants", function()
		local a = Instance.new("Folder")
		local b = Instance.new("Folder", a)
		local destroying = false
		b.Destroying:Connect(function()
			destroying = true
		end)
		a:Destroy()
		expect(destroying).toBe(true)
		expect(b.Parent).toBeNil()
		expect(function()
			b.Parent = Instance.new("Folder")
		end).toThrow("locked")
	end)

	it("attributes and property change signals", function()
		local part = Instance.new("Part")
		local changed = {}
		part:GetAttributeChangedSignal("Hp"):Connect(function()
			table.insert(changed, part:GetAttribute("Hp"))
		end)
		part:SetAttribute("Hp", 100)
		part:SetAttribute("Hp", 100)
		part:SetAttribute("Hp", 50)
		expect(changed).toEqual({ 100, 50 })
		expect(part:GetAttributes()).toEqual({ Hp = 50 })
		local props = 0
		part:GetPropertyChangedSignal("Transparency"):Connect(function()
			props += 1
		end)
		part.Transparency = 0.5
		expect(props).toBe(1)
		expect(part.Transparency).toBe(0.5)
	end)

	it("WaitForChild returns existing/late children and nil after a timeout", function()
		local folder = Instance.new("Folder")
		task.delay(0.01, function()
			local late = Instance.new("Folder")
			late.Name = "Late"
			late.Parent = folder
		end)
		expect(folder:WaitForChild("Late", 1).Name).toBe("Late")
		expect(folder:WaitForChild("Never", 0.02)).toBeNil()
	end)

	it("Clone copies properties, attributes and children", function()
		local a = Instance.new("Folder")
		a.Name = "A"
		a:SetAttribute("X", 1)
		local b = Instance.new("Folder", a)
		b.Name = "B"
		local copy = a:Clone()
		expect(copy.Name).toBe("A")
		expect(copy:GetAttribute("X")).toBe(1)
		expect(copy:FindFirstChild("B")).never.toBe(b)
		expect(copy:FindFirstChild("B")).never.toBeNil()
	end)
end)

describe("MockInstance remotes (loopback network)", function()
	it("FireServer arrives as OnServerEvent(localPlayer, copiedArgs)", function()
		local players = game:GetService("Players")
		local me = players:addPlayer({ UserId = 77 })
		players:setLocalPlayer(me)
		local remote = Instance.new("RemoteEvent")
		local got
		remote.OnServerEvent:Connect(function(player, payload, fn)
			got = { player = player, payload = payload, fn = fn }
		end)
		local payload = { nested = { 1, 2 } }
		remote:FireServer(payload, function() end)
		expect(got.player).toBe(me)
		expect(got.payload).toEqual(payload)
		expect(got.payload).never.toBe(payload)
		expect(got.fn).toBeNil()
	end)

	it("FireClient only reaches the local player's OnClientEvent", function()
		local players = game:GetService("Players")
		local me = players:GetPlayerByUserId(77) or players:addPlayer({ UserId = 77 })
		players:setLocalPlayer(me)
		local other = players:addPlayer({ UserId = 78 })
		local remote = Instance.new("RemoteEvent")
		local got = {}
		remote.OnClientEvent:Connect(function(x)
			table.insert(got, x)
		end)
		remote:FireClient(other, "not me")
		remote:FireClient(me, "me")
		remote:FireAllClients("all")
		expect(got).toEqual({ "me", "all" })
		expect(#remote._sent).toBe(3)
	end)

	it("RemoteFunction InvokeServer calls OnServerInvoke", function()
		local remote = Instance.new("RemoteFunction")
		expect(function()
			remote:InvokeServer()
		end).toThrow("OnServerInvoke is not set")
		remote.OnServerInvoke = function(player, a, b)
			return a + b, player
		end
		local sum = remote:_simulateInvokeServer("p", 2, 3)
		expect(sum).toBe(5)
	end)

	it("BindableEvent and BindableFunction", function()
		local event = Instance.new("BindableEvent")
		local got
		event.Event:Connect(function(x)
			got = x
		end)
		event:Fire(9)
		expect(got).toBe(9)
		local fn = Instance.new("BindableFunction")
		fn.OnInvoke = function(x)
			return x * 2
		end
		expect(fn:Invoke(4)).toBe(8)
	end)
end)

describe("MockGame / MockRunService / MockPlayers", function()
	it("GetService returns stable services and rejects unknown names", function()
		expect(game:GetService("ReplicatedStorage")).toBe(game:GetService("ReplicatedStorage"))
		expect(game:GetService("Workspace")).toBe(workspace)
		expect(function()
			game:GetService("NotAService")
		end).toThrow("is not a valid Service name")
		local fake = { custom = true }
		game:setService("NotAService", fake)
		expect(game:GetService("NotAService")).toBe(fake)
		expect(game:IsLoaded()).toBe(true)
		expect(game.PlaceId).toBe(0)
	end)

	it("BindToClose callbacks run on close()", function()
		local ran = {}
		game:BindToClose(function()
			table.insert(ran, 1)
		end)
		game:BindToClose(function()
			error("close failed")
		end)
		local errors = game:close()
		expect(ran).toEqual({ 1 })
		expect(#errors).toBe(1)
	end)

	it("RunService steps signals and exposes flags", function()
		local rs = game:GetService("RunService")
		local beats = {}
		rs.Heartbeat:Connect(function(dt)
			table.insert(beats, dt)
		end)
		rs:step(0.5)
		rs:step()
		expect(beats[1]).toBe(0.5)
		expect(beats[2]).toBeCloseTo(1 / 60)
		expect(rs:IsServer()).toBe(true)
		rs:setClient(true)
		local rendered = 0
		rs:BindToRenderStep("cam", 1, function()
			rendered += 1
		end)
		rs:step(0.1)
		rs:UnbindFromRenderStep("cam")
		rs:step(0.1)
		expect(rendered).toBe(1)
		expect(rs:elapsed()).toBeCloseTo(0.5 + 1 / 60 + 0.2)
	end)

	it("Players add/remove/kick with signals", function()
		local players = game:GetService("Players")
		local added, removing = {}, {}
		players.PlayerAdded:Connect(function(p)
			table.insert(added, p.UserId)
		end)
		players.PlayerRemoving:Connect(function(p)
			table.insert(removing, p.UserId)
		end)
		local p = players:addPlayer({ UserId = 500, Name = "Tanker" })
		expect(p.Name).toBe("Tanker")
		expect(players:GetPlayerByUserId(500)).toBe(p)
		expect(function()
			players:addPlayer({ UserId = 500 })
		end).toThrow("duplicate UserId")
		p:Kick("bye")
		local kicked, message = p:wasKicked()
		expect(kicked).toBe(true)
		expect(message).toBe("bye")
		expect(players:GetPlayerByUserId(500)).toBeNil()
		expect(added).toEqual({ 500 })
		expect(removing).toEqual({ 500 })
	end)
end)

describe("MockPlayer", function()
	it("creates standalone players with Player behaviour", function()
		local p = MockPlayer.new({ UserId = 9, Name = "Solo", Team = "Red" })
		expect(p:IsA("Player")).toBe(true)
		expect(p.UserId).toBe(9)
		expect(p.DisplayName).toBe("Solo")
		expect(p.Team).toBe("Red")
		expect(p.Parent).toBeNil()
		p:setGroupRank(5, 200)
		expect(p:GetRankInGroupAsync(5)).toBe(200)
		p:Kick("x")
		expect((p:wasKicked())).toBe(true)
	end)
end)
