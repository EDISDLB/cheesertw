--[[
	HULLDOWN test runner (Lune).

	Purpose:          Discover *.spec.luau under tests/Unit, tests/Integration and tests/Regression, run each file in a
	                  fresh Loader (fresh module cache + MockGame), print per-file results and a summary.
	Dependencies:     @lune/fs, @lune/process, @lune/stdio, Harness/Loader, Harness/Test (loaded per file).
	State:            None beyond the running totals.
	Validation:       A filter that matches no spec file is an error (prevents false green runs).
	Error handling:   Load errors and test failures are reported with message + location; exit code 1 on any.
	                  Files using it.only/describe.only fail the run unless HULLDOWN_ALLOW_ONLY=1 (local focusing).
	Performance notes: Bytecode is cached across files by the Loader.

	Usage: lune run tests/run.luau [-- filter ...]   (filters are case-insensitive substrings of the spec path)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local Loader = require("./Harness/Loader")

local SPEC_ROOTS = { "tests/Unit", "tests/Integration", "tests/Regression" }
local TEST_TIMEOUT_SECONDS = 15

local useColor = process.env.NO_COLOR == nil
-- Focused specs (it.only / describe.only) silently skip the rest of their file; they must never reach a commit.
local allowFocus = process.env.HULLDOWN_ALLOW_ONLY == "1"

local function color(name: string, text: string): string
	if not useColor then
		return text
	end
	return stdio.color(name :: any) .. text .. stdio.color("reset")
end

local function discover(dir: string, out: { string })
	if not fs.isDir(dir) then
		return
	end
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			discover(path, out)
		elseif string.sub(entry, -10) == ".spec.luau" then
			table.insert(out, path)
		end
	end
end

local filters = {}
for _, arg in process.args do
	if arg ~= "--" and arg ~= "" then
		table.insert(filters, string.lower(arg))
	end
end

local files = {}
for _, root in SPEC_ROOTS do
	discover(root, files)
end

local selected = {}
for _, file in files do
	local include = #filters == 0
	for _, f in filters do
		if string.find(string.lower(file), f, 1, true) then
			include = true
			break
		end
	end
	if include then
		table.insert(selected, file)
	end
end

if #selected == 0 then
	if #filters == 0 then
		print(color("red", "No spec files found under " .. table.concat(SPEC_ROOTS, ", ")))
	else
		print(
			color("red", `No spec files matched filter(s): {table.concat(filters, ", ")} ({#files} spec files found)`)
		)
	end
	process.exit(1)
end

local MAX_LOG_LINES = 40

local function printLogs(lines: { string })
	if #lines == 0 then
		return
	end
	print(color("yellow", `  captured log ({#lines} lines, last {math.min(#lines, MAX_LOG_LINES)}):`))
	for i = math.max(1, #lines - MAX_LOG_LINES + 1), #lines do
		print("    " .. lines[i])
	end
end

local totals = { passed = 0, failed = 0, skipped = 0, loadErrors = 0, focusErrors = 0, files = 0 }
local startedAll = os.clock()
local failedFiles = {}

for _, file in selected do
	totals.files += 1
	local started = os.clock()
	local result: any = nil
	local loadError: string? = nil
	local logLines: { string } = {}
	local ok, loaderOrErr = pcall(Loader.new, {
		root = process.cwd,
		onWarn = function(text: string)
			table.insert(logLines, "[warn] " .. text)
		end,
	})
	if not ok then
		loadError = tostring(loaderOrErr)
	else
		local loader = loaderOrErr
		-- Buffer src logging per file; it is printed only when the file fails.
		local okLog, Log = pcall(loader.require, loader, "@game/ReplicatedStorage/Shared/Core/Log")
		if okLog then
			Log.setSink(function(level: string, scope: string, message: string)
				table.insert(logLines, `[{level}] [{scope}] {message}`)
			end)
		end
		local okTest, Test = pcall(loader.require, loader, "@tests/Harness/Test")
		if not okTest then
			loadError = tostring(Test)
		else
			local okRun, err = pcall(loader.runFile, loader, file)
			if not okRun then
				loadError = tostring(err)
			else
				local okResult, res = pcall(Test.run, { timeout = TEST_TIMEOUT_SECONDS })
				if okResult then
					result = res
				else
					loadError = "test runner crashed: " .. tostring(res)
				end
			end
		end
	end
	local ms = (os.clock() - started) * 1000

	if loadError ~= nil then
		totals.loadErrors += 1
		table.insert(failedFiles, file)
		print(color("red", "LOAD ERROR ") .. file)
		print("    " .. string.gsub(loadError, "\n", "\n    "))
		printLogs(logLines)
	else
		totals.passed += result.passed
		totals.failed += result.failed
		totals.skipped += result.skipped
		local count = result.passed + result.failed + result.skipped
		local rejectedFocus = result.focused and not allowFocus
		if rejectedFocus then
			totals.focusErrors += 1
		end
		local label = if result.failed > 0 or rejectedFocus then color("red", "FAIL ") else color("green", "PASS ")
		local extra = if result.skipped > 0 then `, {result.skipped} skipped` else ""
		print(`{label}{file} ({count} tests{extra}, {string.format("%.1f", ms)} ms)`)
		if count == 0 then
			print(color("yellow", "    warning: spec file declares no tests"))
		end
		if rejectedFocus then
			if result.failed == 0 then
				table.insert(failedFiles, file)
			end
			print(
				color(
					"red",
					"    focused tests (.only) skip the rest of this file: remove them (HULLDOWN_ALLOW_ONLY=1 allows it locally)"
				)
			)
		end
		if result.failed > 0 then
			table.insert(failedFiles, file)
			printLogs(logLines)
			for _, failure in result.failures do
				print(color("red", "  x " .. failure.name))
				local message = string.gsub(failure.message or "?", "\n", "\n      ")
				print("      " .. message)
				if failure.location and not string.find(failure.message or "", failure.location, 1, true) then
					print(color("cyan", "      at " .. failure.location))
				end
			end
		end
	end
end

local elapsed = os.clock() - startedAll
print("")
print(
	string.format(
		"Tests: %d passed, %d failed, %d skipped | Files: %d (%d load errors) | Time: %.2f s",
		totals.passed,
		totals.failed,
		totals.skipped,
		totals.files,
		totals.loadErrors,
		elapsed
	)
)
if totals.failed > 0 or totals.loadErrors > 0 or totals.focusErrors > 0 then
	print(color("red", "FAILED: " .. table.concat(failedFiles, ", ")))
	process.exit(1)
end
print(color("green", "ALL TESTS PASSED"))
process.exit(0)
