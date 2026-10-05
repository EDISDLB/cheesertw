--[[
	TypeSource — reads Types/*.luau source text so specs can check type declarations against runtime mirrors
	(validator enums, example values, ledger keys). Types are erased at runtime, so drift between a declaration
	and the code that mirrors it can only be caught by reading the declaration itself.

	unionMembers(source, "StatKey") -> { "damage", ... }   string-literal members of `export type StatKey = ...`
	fieldsOf(source, "Profile") -> { { name = "userId", optional = false }, ... } top-level fields of a table type
	tagsOf(source, "BattleEvent", "type") -> { "Started", ... } literal tags `type: "X"` inside a union declaration
]]

local fs = require("@lune/fs")

local TypeSource = {}

function TypeSource.read(module: string): string
	return fs.readFile(`src/ReplicatedStorage/Shared/Types/{module}.luau`)
end

local function stripComment(line: string): string
	local quote = false
	for i = 1, #line - 1 do
		local c = string.sub(line, i, i)
		if c == '"' then
			quote = not quote
		elseif not quote and string.sub(line, i, i + 1) == "--" then
			return string.sub(line, 1, i - 1)
		end
	end
	return line
end

-- Lines of one `export type Name = ...` declaration. Table types run to their closing "}" at column 0 (blank and
-- comment lines inside are kept); unions run until the next blank or top-level line.
local function declaration(source: string, name: string): { string }
	local lines = {}
	local inside = false
	local tableMode = false
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		if not inside then
			if string.find(line, `^export type {name} =`) then
				inside = true
				table.insert(lines, line)
				tableMode = string.find(stripComment(line), "{%s*$") ~= nil
				if not tableMode and string.find(line, "}%s*$") then
					break -- single-line table type
				end
			end
		elseif tableMode then
			if string.find(line, "^%S") ~= nil and string.find(line, "^}") == nil then
				break -- the next top-level statement
			end
			table.insert(lines, line)
			-- "}" closes the declaration unless a union continues ("} | {")
			if string.find(line, "^}") and not string.find(line, "^}%s*|") then
				break
			end
		elseif line == "" or (string.find(line, "^%S") ~= nil and string.find(line, "^}") == nil) then
			break
		else
			table.insert(lines, line)
			if string.find(line, "^}") and not string.find(line, "^}%s*|") then
				break
			end
		end
	end
	assert(#lines > 0, `type {name} not found`)
	return lines
end

function TypeSource.unionMembers(source: string, name: string): { string }
	local out = {}
	for _, line in declaration(source, name) do
		for literal in string.gmatch(stripComment(line), '"([^"]*)"') do
			table.insert(out, literal)
		end
	end
	table.sort(out)
	return out
end

function TypeSource.tagsOf(source: string, name: string, tag: string): { string }
	local out = {}
	local seen = {}
	for _, line in declaration(source, name) do
		for literal in string.gmatch(stripComment(line), tag .. ':%s*"([^"]*)"') do
			if not seen[literal] then
				seen[literal] = true
				table.insert(out, literal)
			end
		end
	end
	table.sort(out)
	return out
end

export type Field = { name: string, optional: boolean }

function TypeSource.fieldsOf(source: string, name: string): { Field }
	local lines = declaration(source, name)
	local out = {}
	if #lines == 1 then
		-- single-line table type: split the top level of "{ a: T, b: U? }" on commas
		local body = string.match(stripComment(lines[1]), "=%s*{(.*)}%s*$") or ""
		local depth, start = 0, 1
		local parts = {}
		for i = 1, #body do
			local c = string.sub(body, i, i)
			if c == "{" or c == "(" then
				depth += 1
			elseif c == "}" or c == ")" then
				depth -= 1
			elseif c == "," and depth == 0 then
				table.insert(parts, string.sub(body, start, i - 1))
				start = i + 1
			end
		end
		table.insert(parts, string.sub(body, start))
		for _, part in parts do
			local field, rest = string.match(part, "^%s*([%a_][%w_]*):%s*(.-)%s*$")
			if field ~= nil then
				table.insert(out, { name = field, optional = string.sub(rest, -1) == "?" })
			end
		end
		return out
	end
	local i = 2
	while i <= #lines do
		local line = stripComment(lines[i])
		local field, rest = string.match(line, "^\t([%a_][%w_]*):%s*(.-)%s*$")
		if field ~= nil then
			local optional
			if string.sub(rest, -1) == "{" then
				-- multi-line nested table: optional when its closing line ends with "}?,"
				local j = i + 1
				while j <= #lines and not string.find(lines[j], "^\t}") do
					j += 1
				end
				optional = string.find(stripComment(lines[j] or ""), "^\t}%?") ~= nil
				i = j
			else
				optional = string.find(rest, "%?,?$") ~= nil
			end
			table.insert(out, { name = field, optional = optional })
		end
		i += 1
	end
	return out
end

function TypeSource.fieldNames(source: string, name: string, includeOptional: boolean?): { string }
	local out = {}
	for _, field in TypeSource.fieldsOf(source, name) do
		if includeOptional or not field.optional then
			table.insert(out, field.name)
		end
	end
	table.sort(out)
	return out
end

--- Problems with a value against a table type: missing required fields and keys the type does not declare.
function TypeSource.shapeProblems(value: { [string]: any }, source: string, name: string): { string }
	local problems = {}
	local declared = {}
	for _, field in TypeSource.fieldsOf(source, name) do
		declared[field.name] = true
		if not field.optional and value[field.name] == nil then
			table.insert(problems, `missing {field.name}`)
		end
	end
	for key in value do
		if not declared[key] then
			table.insert(problems, `undeclared {tostring(key)}`)
		end
	end
	table.sort(problems)
	return problems
end

function TypeSource.sortedKeys(t: { [string]: any }): { string }
	local out = {}
	for key in t do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

return TypeSource
