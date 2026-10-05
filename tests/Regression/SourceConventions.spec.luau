-- Repository-wide guard for ARCHITECTURE §3 coding conventions. Applies to every file under src/ (all teams).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require("@lune/fs")

local HEADER_KEYS = { "Purpose", "Dependencies", "State", "Validation", "Error handling", "Performance notes" }

-- Files allowed to touch the engine/scheduler despite living in Shared (Roblox-facing by design).
local SHARED_IMPURITY_ALLOWLIST = {
	["src/ReplicatedStorage/Shared/Net/NetServer.luau"] = true,
	["src/ReplicatedStorage/Shared/Net/NetClient.luau"] = true,
	["src/ReplicatedStorage/Shared/Core/Clock.luau"] = true,
}

-- The only files allowed to take `require` as a value (plug-in discovery through a local dynamicRequire alias).
local DYNAMIC_REQUIRE_ALLOWLIST = {
	["src/ServerScriptService/Server/Main.server.luau"] = true,
	["src/ReplicatedStorage/Client/Main.luau"] = true,
}

local PRINT_ALLOWLIST = {
	["src/ReplicatedStorage/Shared/Core/Log.luau"] = true,
}

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" or string.sub(entry, -4) == ".lua" then
			table.insert(out, path)
		end
	end
end

local function longBracketLevel(source: string, i: number): number?
	local eqs = string.match(source, "^%[(=*)%[", i)
	return if eqs then #eqs else nil
end

-- Removes comments and replaces string contents with "" while preserving line breaks.
local function stripCommentsAndStrings(source: string): string
	local out = {}
	local i, n = 1, #source
	local function keepNewlines(chunk: string)
		local _, count = string.gsub(chunk, "\n", "")
		table.insert(out, string.rep("\n", count))
	end
	while i <= n do
		local c = string.sub(source, i, i)
		if c == "-" and string.sub(source, i, i + 1) == "--" then
			local level = longBracketLevel(source, i + 2)
			if level ~= nil then
				local close = "]" .. string.rep("=", level) .. "]"
				local stop = string.find(source, close, i + 4 + level, true) or n
				keepNewlines(string.sub(source, i, stop))
				i = stop + #close
			else
				local stop = string.find(source, "\n", i, true) or (n + 1)
				i = stop
			end
		elseif c == "[" and longBracketLevel(source, i) ~= nil then
			local level = longBracketLevel(source, i) :: number
			local close = "]" .. string.rep("=", level) .. "]"
			local stop = string.find(source, close, i + 2 + level, true) or n
			keepNewlines(string.sub(source, i, stop))
			table.insert(out, '""')
			i = stop + #close
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(source, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or (d == "\n" and c ~= "`") then
					break
				else
					j += 1
				end
			end
			keepNewlines(string.sub(source, i, j))
			table.insert(out, '""')
			i = j + 1
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

local function findViolations(code: string, patterns: { { pattern: string, label: string } }): { string }
	local found = {}
	local lineNumber = 0
	for line in string.gmatch(code .. "\n", "([^\n]*)\n") do
		lineNumber += 1
		for _, rule in patterns do
			if string.find(line, rule.pattern) then
				table.insert(found, `{lineNumber}: {rule.label}`)
			end
		end
	end
	return found
end

-- Every use of the `require` global must be a call with a string literal ("@game/...", "./X"). Taking `require` as a
-- value (an alias that could later require Instances) is only allowed for the dynamicRequire line of the two Mains.
-- `code` is already stripped (strings are "", comments removed). Returns "line: message" entries.
local function requireViolations(code: string, file: string): { string }
	local found = {}
	local lineNumber = 0
	for line in string.gmatch(code .. "\n", "([^\n]*)\n") do
		lineNumber += 1
		local start = 1
		while true do
			local s, e = string.find(line, "%f[%w_%.:]require%f[^%w_]", start)
			if s == nil then
				break
			end
			local rest = string.sub(line, e + 1)
			local literalCall = string.match(rest, "^%s*%(%s*[\"'`]") ~= nil or string.match(rest, "^%s*[\"'`]") ~= nil
			local tableKey = string.match(rest, "^%s*=[^=]") ~= nil
				and string.match(string.sub(line, 1, s - 1), "[{,]%s*$")
			local sanctionedAlias = DYNAMIC_REQUIRE_ALLOWLIST[file] == true
				and string.match(line, "^%s*local%s+dynamicRequire%s*=%s*require%s*::%s*any%s*$") ~= nil
			if not literalCall and not tableKey and not sanctionedAlias then
				local what = if string.match(rest, "^%s*%(") then "non-string require" else "require used as a value"
				table.insert(found, `{lineNumber}: {what}`)
			end
			start = e + 1
		end
	end
	return found
end

local files = {}
collect("src", files)
table.sort(files)

local function report(problems: { string })
	if #problems > 0 then
		error("convention violations:\n  " .. table.concat(problems, "\n  "), 0)
	end
end

describe("Source conventions (ARCHITECTURE §3)", function()
	it("finds source files", function()
		expect(#files).toBeGreaterThan(20)
	end)

	it("every file starts with --!strict (optionally after --!native)", function()
		local problems = {}
		for _, file in files do
			local source = fs.readFile(file)
			local ok = false
			for line in string.gmatch(source, "([^\n]*)\n") do
				if line == "--!strict" then
					ok = true
					break
				elseif line ~= "--!native" and line ~= "--!optimize 2" then
					break
				end
			end
			if not ok then
				table.insert(problems, file)
			end
		end
		report(problems)
	end)

	it(
		"every file has the header block (Purpose, Dependencies, State, Validation, Error handling, Performance notes)",
		function()
			local problems = {}
			for _, file in files do
				local head = string.sub(fs.readFile(file), 1, 3000)
				local missing = {}
				for _, key in HEADER_KEYS do
					if not string.find(head, key .. ":", 1, true) then
						table.insert(missing, key)
					end
				end
				if #missing > 0 then
					table.insert(problems, `{file}: missing {table.concat(missing, ", ")}`)
				end
			end
			report(problems)
		end
	)

	it("no bare print, _G, shared, getfenv/setfenv, loadstring or deprecated wait/spawn/delay globals", function()
		local problems = {}
		for _, file in files do
			local code = stripCommentsAndStrings(fs.readFile(file))
			local rules = {
				{ pattern = "%f[%w_%.:]_G%f[^%w_]", label = "_G" },
				{ pattern = "%f[%w_%.:]shared%f[^%w_]", label = "shared" },
				{ pattern = "%f[%w_%.:]getfenv%f[^%w_]", label = "getfenv" },
				{ pattern = "%f[%w_%.:]setfenv%f[^%w_]", label = "setfenv" },
				{ pattern = "%f[%w_%.:]loadstring%f[^%w_]", label = "loadstring" },
				{ pattern = "%f[%w_%.:]wait%s*%(", label = "global wait() (use task.wait)" },
				{ pattern = "%f[%w_%.:]spawn%s*%(", label = "global spawn() (use task.spawn)" },
				{ pattern = "%f[%w_%.:]delay%s*%(", label = "global delay() (use task.delay)" },
			}
			if not PRINT_ALLOWLIST[file] then
				table.insert(rules, { pattern = "%f[%w_%.:]print%s*%(", label = "bare print (use Core/Log)" })
			end
			for _, v in findViolations(code, rules) do
				table.insert(problems, `{file}:{v}`)
			end
		end
		report(problems)
	end)

	it("requires use string literals (instance requires only through the sanctioned dynamicRequire in Main)", function()
		local problems = {}
		for _, file in files do
			for _, v in requireViolations(stripCommentsAndStrings(fs.readFile(file)), file) do
				table.insert(problems, `{file}:{v}`)
			end
		end
		report(problems)
	end)

	it("every Shared module with logic has a mirrored unit spec (rule 10)", function()
		-- Type-only and data-only modules (no `function`) are exempt; their consumers' specs cover them.
		local problems = {}
		for _, file in files do
			if string.find(file, "^src/ReplicatedStorage/Shared/") then
				local code = stripCommentsAndStrings(fs.readFile(file))
				if string.find(code, "%f[%w_]function%f[^%w_]") then
					local rel = string.gsub(string.gsub(file, "^src/", ""), "%.luau$", "")
					local dir, name = string.match(rel, "^(.*)/([^/]+)$")
					local spec = if name == "init"
						then `tests/Unit/{dir}/{string.match(dir :: string, "([^/]+)$")}.spec.luau`
						else `tests/Unit/{dir}/{name}.spec.luau`
					if not fs.isFile(spec) then
						table.insert(problems, `{file}: missing {spec}`)
					end
				end
			end
		end
		report(problems)
	end)

	it("Shared modules are pure (no services, workspace, scheduler, wall-clock or math.random)", function()
		local problems = {}
		for _, file in files do
			if string.find(file, "^src/ReplicatedStorage/Shared/") and not SHARED_IMPURITY_ALLOWLIST[file] then
				local code = stripCommentsAndStrings(fs.readFile(file))
				local rules = {
					{ pattern = ":GetService%s*%(", label = "GetService" },
					{ pattern = "%f[%w_%.:]workspace%f[^%w_]", label = "workspace" },
					{ pattern = "task%.wait", label = "task.wait" },
					{ pattern = "task%.spawn", label = "task.spawn" },
					{ pattern = "task%.delay", label = "task.delay" },
					{ pattern = "task%.defer", label = "task.defer" },
					{ pattern = "os%.clock", label = "os.clock (inject a Clock)" },
					{ pattern = "os%.time", label = "os.time (inject a Clock)" },
					{ pattern = "%f[%w_%.:]tick%s*%(", label = "tick()" },
					{ pattern = "math%.random", label = "math.random (use Core/RNG)" },
					{ pattern = "Random%.new", label = "Random.new (use Core/RNG)" },
				}
				for _, v in findViolations(code, rules) do
					table.insert(problems, `{file}:{v}`)
				end
			end
		end
		report(problems)
	end)

	it("the require rule flags aliases and non-literal calls", function()
		local function count(source: string, file: string): number
			return #requireViolations(stripCommentsAndStrings(source), file)
		end
		expect(count('local A = require("./A")\nlocal B = require(script.B)', "src/X.luau")).toBe(1)
		expect(count("local r = require\nlocal x = r(script.Y)", "src/X.luau")).toBe(1)
		expect(count("local dynamicRequire = require :: any", "src/X.luau")).toBe(1)
		expect(count("local dynamicRequire = require :: any", "src/ServerScriptService/Server/Main.server.luau")).toBe(
			0
		)
		expect(count("local t = { require = 1, x = 2 }\nt.require(x)\nlocal requireX = 2", "src/X.luau")).toBe(0)
		expect(count("pcall(require, script.Z)", "src/X.luau")).toBe(1)
	end)

	it("the comment/string stripper itself works", function()
		local code =
			stripCommentsAndStrings('local a = "print(" -- print(\n--[[ print( ]]\nprint(`x`) local b = [[print(]]')
		local found = findViolations(code, { { pattern = "%f[%w_%.:]print%s*%(", label = "print" } })
		expect(found).toEqual({ "3: print" })
		expect(code).toContain('local a = ""')
	end)
end)
