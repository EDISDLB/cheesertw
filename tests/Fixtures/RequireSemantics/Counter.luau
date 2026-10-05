-- Fixture: module-level state shows whether the module cache is shared.
local count = 0
return {
	inc = function(): number
		count += 1
		return count
	end,
}
