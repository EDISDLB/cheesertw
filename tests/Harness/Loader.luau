--[[
	Loader — Lune module loader that reproduces Roblox require-by-string semantics for HULLDOWN tests.

	Purpose:          Load src/ and tests/ modules in Lune exactly as Roblox / luau-lsp resolve them, with Roblox
	                  datatypes, `task`, a mock `game`/`workspace` and a mock-aware `typeof` injected as globals.
	Dependencies:     @lune/fs, @lune/luau, @lune/roblox, @lune/task, @lune/serde, @lune/datetime, @lune/stdio,
	                  @lune/process, Harness/Mocks/*.
	State:            One Loader per spec file: a fresh module cache + fresh MockGame. Compiled bytecode is cached
	                  process-wide (sources do not change during a run).
	Validation:       Paths must start with "./", "../" or "@alias/". "@self" only inside init modules. Scripts
	                  (*.server.luau / *.client.luau) and plain folders are not requirable. Modules must return
	                  exactly one value. Cyclic requires are reported with the full chain.
	Error handling:   Every resolution/load failure raises an error naming the requested path and the requiring file.
	Performance notes: Bytecode cache shared across loaders; env tables are shallow copies of the global table.

	Resolution rules (identical to Roblox, Lune and luau-lsp):
	  * A module's *instance* is its file without extension, or its folder for `init.luau`.
	  * "./X"  -> sibling of the module instance        (D/Foo.luau: D/X;  D/F/init.luau: D/X)
	  * "../X" -> sibling of the module's parent         (D/Foo.luau: parent(D)/X)
	  * "@self/X" -> child of the module instance        (only valid in init modules: D/F/init.luau: D/F/X)
	  * "@game/A/B" -> src/A/B, "@tests/A" -> tests/A    (aliases read from .luaurc)
	  * "@lune/x" -> passed through to Lune's own require.
	  * A path P resolves to P.luau, P.lua, P/init.luau or P/init.lua (in that order).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local serde = require("@lune/serde")
local datetime = require("@lune/datetime")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local lunerequire = require

local Loader = {}
Loader.__index = Loader

local bytecodeCache: { [string]: buffer | string } = {}

local MODULE_EXTENSIONS = { ".luau", ".lua" }

local function splitPath(path: string): { string }
	local segments = {}
	for segment in string.gmatch(path, "[^/]+") do
		table.insert(segments, segment)
	end
	return segments
end

local function normalizeRelative(path: string): string
	local out = {}
	for _, segment in splitPath(path) do
		if segment == "." then
			continue
		elseif segment == ".." then
			if #out == 0 then
				error(`Loader: path escapes the repository root: {path}`, 0)
			end
			table.remove(out)
		else
			table.insert(out, segment)
		end
	end
	return table.concat(out, "/")
end

local function stripModuleExtension(name: string): (string, string?)
	for _, ext in MODULE_EXTENSIONS do
		if string.sub(name, -#ext) == ext then
			local base = string.sub(name, 1, -#ext - 1)
			local kind = nil
			if string.sub(base, -7) == ".server" then
				kind = "server"
				base = string.sub(base, 1, -8)
			elseif string.sub(base, -7) == ".client" then
				kind = "client"
				base = string.sub(base, 1, -8)
			end
			return base, kind
		end
	end
	return name, nil
end

-- Instance path (segments relative to the repo root) of the module defined by `file`.
local function instanceSegments(file: string): ({ string }, boolean)
	local segments = splitPath(file)
	local base = stripModuleExtension(segments[#segments])
	if base == "init" then
		table.remove(segments)
		return segments, true
	end
	segments[#segments] = base
	return segments, false
end

local function isFile(path: string): boolean
	local ok, result = pcall(fs.isFile, path)
	return ok and result == true
end

local function isDir(path: string): boolean
	local ok, result = pcall(fs.isDir, path)
	return ok and result == true
end

-- Parses .luaurc (JSON with optional trailing commas) and returns alias -> normalized relative directory.
local function readAliases(root: string): { [string]: string }
	local aliases: { [string]: string } = {}
	local path = root .. "/.luaurc"
	if not isFile(path) then
		return aliases
	end
	local text = fs.readFile(path)
	text = string.gsub(text, ",(%s*[}%]])", "%1")
	local ok, decoded = pcall(serde.decode, "json", text)
	if not ok or type(decoded) ~= "table" or type(decoded.aliases) ~= "table" then
		return aliases
	end
	for name, target in decoded.aliases do
		if type(name) == "string" and type(target) == "string" then
			aliases[string.lower(name)] = normalizeRelative(target)
		end
	end
	return aliases
end

-- Minimal DateTime shim (Roblox API shape) on top of @lune/datetime.
local function makeDateTimeShim()
	local DateTime = {}
	local function wrap(millis: number)
		local obj = {
			UnixTimestamp = math.floor(millis / 1000),
			UnixTimestampMillis = millis,
		}
		function obj.ToIsoDate(_self)
			return datetime.fromUnixTimestamp(millis / 1000):toIsoDate()
		end
		return obj
	end
	function DateTime.now()
		return wrap(datetime.now().unixTimestampMillis)
	end
	function DateTime.fromUnixTimestamp(seconds: number)
		return wrap(seconds * 1000)
	end
	function DateTime.fromUnixTimestampMillis(millis: number)
		return wrap(millis)
	end
	return DateTime
end

-- Plain data shims for Roblox parameter classes that @lune/roblox does not provide.
local function makeParamsShim(defaults: { [string]: any })
	return {
		new = function(...)
			local obj = table.clone(defaults)
			obj._args = table.pack(...)
			return obj
		end,
	}
end

local ROBLOX_DATATYPES = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Content",
	"Enum",
	"Faces",
	"Font",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"PhysicalProperties",
	"Ray",
	"Rect",
	"Region3",
	"Region3int16",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector2int16",
	"Vector3",
	"Vector3int16",
}

local nativeTypeof = typeof

local function mockAwareTypeof(value: any): string
	if type(value) == "table" then
		local mt = getmetatable(value)
		if type(mt) == "table" then
			local tag = rawget(mt, "__type")
			if type(tag) == "string" then
				return tag
			end
		end
	end
	return nativeTypeof(value)
end

local function buildBaseGlobals(): { [string]: any }
	local globals: { [string]: any } = {}
	for _, name in ROBLOX_DATATYPES do
		local value = (roblox :: any)[name]
		if value ~= nil then
			globals[name] = value
		end
	end
	globals.DateTime = makeDateTimeShim()
	globals.RaycastParams = makeParamsShim({
		FilterDescendantsInstances = {},
		IgnoreWater = false,
		CollisionGroup = "Default",
		RespectCanCollide = false,
	})
	globals.OverlapParams = makeParamsShim({ FilterDescendantsInstances = {}, MaxParts = 0 })
	globals.TweenInfo = makeParamsShim({})
	globals.task = task
	globals.typeof = mockAwareTypeof
	return globals
end

export type LoaderOptions = {
	root: string?,
	mockGame: boolean?,
	--- Receives text passed to the injected `warn` (default: written to stderr).
	onWarn: ((text: string) -> ())?,
}

function Loader.new(options: LoaderOptions?)
	local opts = options or {}
	local root = opts.root or process.cwd
	root = string.gsub(root, "/+$", "")
	local self = setmetatable({
		root = root,
		aliases = readAliases(root),
		cache = {} :: { [string]: { state: string, value: any } },
		stack = {} :: { string },
		globals = buildBaseGlobals(),
		game = nil :: any,
	}, Loader)
	local onWarn = opts.onWarn or function(text: string)
		stdio.ewrite("[warn] " .. text .. "\n")
	end
	self.globals.warn = function(...)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		onWarn(table.concat(parts, " ", 1, parts.n))
	end
	if opts.mockGame ~= false then
		self:_installMocks()
	end
	return self
end

function Loader._installMocks(self: any)
	local MockInstance = self:require("@tests/Harness/Mocks/MockInstance")
	local MockGame = self:require("@tests/Harness/Mocks/MockGame")
	local mockGame = MockGame.new()
	self.game = mockGame
	self.globals.game = mockGame
	self.globals.workspace = mockGame:GetService("Workspace")
	self.globals.Instance = MockInstance.InstanceApi
end

function Loader._abs(self: any, rel: string): string
	return self.root .. "/" .. rel
end

function Loader._resolve(self: any, request: string, fromFile: string?): string
	local baseSegments: { string }
	local rest: string
	local first = string.sub(request, 1, 1)
	if first == "@" then
		local alias, remainder = string.match(request, "^@([^/]+)/?(.*)$")
		if alias == nil then
			error(`Loader: malformed alias path "{request}"`, 0)
		end
		local aliasName = string.lower(alias :: string)
		if aliasName == "self" then
			if fromFile == nil then
				error(`Loader: "@self" used outside a module: "{request}"`, 0)
			end
			local segments, isInit = instanceSegments(fromFile)
			if not isInit then
				error(
					`Loader: "@self" is only valid inside init modules ("{request}" required from {fromFile}); `
						.. 'use "./" for siblings',
					0
				)
			end
			baseSegments = segments
		else
			local target = self.aliases[aliasName]
			if target == nil then
				error(`Loader: unknown alias "@{alias}" in "{request}" (from {fromFile or "?"})`, 0)
			end
			baseSegments = splitPath(target)
		end
		rest = remainder :: string
	elseif string.sub(request, 1, 2) == "./" or string.sub(request, 1, 3) == "../" then
		if fromFile == nil then
			error(`Loader: relative require "{request}" has no requiring file`, 0)
		end
		local segments = instanceSegments(fromFile)
		table.remove(segments)
		baseSegments = segments
		rest = request
	else
		error(`Loader: require path must start with "./", "../" or "@alias/": "{request}" (from {fromFile or "?"})`, 0)
	end

	for segment in string.gmatch(rest, "[^/]+") do
		if segment == "." then
			continue
		elseif segment == ".." then
			if #baseSegments == 0 then
				error(`Loader: "{request}" escapes the repository root (from {fromFile or "?"})`, 0)
			end
			table.remove(baseSegments)
		else
			table.insert(baseSegments, segment)
		end
	end

	local base = table.concat(baseSegments, "/")
	for _, ext in MODULE_EXTENSIONS do
		if isFile(self:_abs(base .. ext)) then
			return base .. ext
		end
	end
	for _, ext in MODULE_EXTENSIONS do
		local candidate = base .. "/init" .. ext
		if isFile(self:_abs(candidate)) then
			return candidate
		end
	end
	for _, kind in { ".server", ".client" } do
		for _, ext in MODULE_EXTENSIONS do
			if isFile(self:_abs(base .. kind .. ext)) or isFile(self:_abs(base .. "/init" .. kind .. ext)) then
				error(`Loader: "{request}" resolves to a Script ({base}{kind}{ext}), not a ModuleScript`, 0)
			end
		end
	end
	if isDir(self:_abs(base)) then
		error(`Loader: "{request}" resolves to folder "{base}" which has no init module (from {fromFile or "?"})`, 0)
	end
	error(`Loader: module not found: "{request}" -> "{base}" (from {fromFile or "?"})`, 0)
end

function Loader._compile(self: any, file: string): () -> ...any
	local bytecode = bytecodeCache[file]
	if bytecode == nil then
		local source = fs.readFile(self:_abs(file))
		local ok, compiled = pcall(luau.compile, source)
		if not ok then
			error(`Loader: syntax error in {file}: {compiled}`, 0)
		end
		bytecode = compiled
		bytecodeCache[file] = compiled
	end
	local env = table.clone(self.globals)
	env.require = function(path: any)
		if type(path) ~= "string" then
			error(`Loader: only string requires are supported (in {file})`, 2)
		end
		return self:require(path, file)
	end
	return luau.load(bytecode :: any, {
		debugName = "@" .. file,
		environment = env,
		injectGlobals = true,
	})
end

-- Resolves and loads `request` as required from `fromFile` (a repo-relative path), with module caching.
function Loader.require(self: any, request: string, fromFile: string?): any
	if string.sub(request, 1, 6) == "@lune/" then
		return lunerequire(request)
	end
	local file = self:_resolve(request, fromFile)
	return self:_loadModule(file)
end

function Loader._loadModule(self: any, file: string): any
	local entry = self.cache[file]
	if entry ~= nil then
		if entry.state == "loading" then
			local chain = table.clone(self.stack)
			table.insert(chain, file)
			error(`Loader: cyclic require: {table.concat(chain, " -> ")}`, 0)
		end
		return entry.value
	end
	local chunk = self:_compile(file)
	self.cache[file] = { state = "loading", value = nil }
	table.insert(self.stack, file)
	local results = table.pack(pcall(chunk))
	table.remove(self.stack)
	if not results[1] then
		self.cache[file] = nil
		error(results[2], 0)
	end
	if results.n ~= 2 then
		self.cache[file] = nil
		error(`Loader: module {file} did not return exactly one value (returned {results.n - 1})`, 0)
	end
	local value = results[2]
	self.cache[file] = { state = "loaded", value = value }
	return value
end

-- Executes a (spec) file with module semantics but without requiring a return value.
function Loader.runFile(self: any, file: string): any
	local chunk = self:_compile(file)
	table.insert(self.stack, file)
	local results = table.pack(pcall(chunk))
	table.remove(self.stack)
	if not results[1] then
		error(results[2], 0)
	end
	return results[2]
end

-- Exposed for harness self-tests.
Loader._internals = {
	instanceSegments = instanceSegments,
	normalizeRelative = normalizeRelative,
	mockAwareTypeof = mockAwareTypeof,
}

return Loader
