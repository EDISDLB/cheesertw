-- Fixture: reports the injected globals.
return {
	vector = Vector3.new(1, 2, 3),
	cframe = CFrame.new(1, 2, 3),
	color = Color3.fromRGB(255, 0, 0),
	udim2 = UDim2.fromScale(0.5, 0.5),
	material = Enum.Material.Grass,
	hasTask = type(task) == "table" and type(task.spawn) == "function",
	gameType = typeof(game),
	workspaceName = workspace.Name,
	instanceType = typeof(Instance.new("Folder")),
	dateTime = DateTime.now().UnixTimestamp,
}
