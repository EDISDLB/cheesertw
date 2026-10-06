--!strict
--[[
	Shared/Assets/AssetResolver — asset key -> uploaded id, with declared fallbacks and one-time warnings.

	Purpose:          The only way code turns an asset key into a Roblox content id (ARCHITECTURE §11):
	                  `AssetResolver.image("classes/heavy")` -> "rbxassetid://..." or nil (the UI then draws the
	                  glyph fallback), `AssetResolver.sound("ui_click")` -> SoundEntry or nil (silence). Also answers
	                  "does this key exist / have a fallback" for ContentRegistry and test validation.
	Dependencies:     Assets/AssetManifest (generated), Assets/FallbackKeys, Core/Log.
	State:            Per resolver: manifest reference, fallback sets, warned-key set, requested-missing sets.
	Validation:       Keys must match ^[a-z0-9_]+(/[a-z0-9_]+)*$; validateManifest checks ids, buses, durations,
	                  volumes and bank regions.
	Error handling:   Missing keys never throw: sounds warn once per key (then stay silent), images without any
	                  fallback warn once, images with a glyph/badge fallback log once at debug level.
	Performance notes: O(1) lookups; warnings are deduplicated so hot paths can call it every frame.
]]

local AssetManifest = require("./AssetManifest")
local FallbackKeys = require("./FallbackKeys")
local Log = require("../Core/Log")

export type ImageEntry = AssetManifest.ImageEntry
export type SoundEntry = AssetManifest.SoundEntry
export type Manifest = AssetManifest.Manifest

--- How an image key renders: an uploaded image, a dedicated glyph, a category badge, or nothing known.
export type ImageResolution = {
	kind: "image" | "glyph" | "badge" | "missing",
	key: string,
	id: string?,
	entry: ImageEntry?,
	category: string?,
}

export type ValidateOptions = {
	--- "image" (default) or "sound".
	kind: ("image" | "sound")?,
	--- Count declared fallbacks as present (default true). Use false after the first upload to catch typos.
	allowFallback: boolean?,
}

export type ValidationReport = { missing: { string }, invalid: { string } }

export type ResolverOptions = {
	--- Extra glyph-backed keys (in addition to FallbackKeys.glyphs).
	glyphs: { string }?,
	--- Extra badge categories.
	badgeCategories: { string }?,
	--- Logger (default Log.scope("Assets")).
	log: Log.Logger?,
}

export type Resolver = {
	image: (self: Resolver, key: string) -> string?,
	imageAsset: (self: Resolver, key: string) -> ImageEntry?,
	resolveImage: (self: Resolver, key: string) -> ImageResolution,
	sound: (self: Resolver, key: string) -> SoundEntry?,
	has: (self: Resolver, key: string) -> boolean,
	hasImage: (self: Resolver, key: string) -> boolean,
	hasSound: (self: Resolver, key: string) -> boolean,
	hasGlyph: (self: Resolver, key: string) -> boolean,
	hasFallback: (self: Resolver, key: string) -> boolean,
	declareGlyph: (self: Resolver, key: string) -> (),
	validateKeys: (self: Resolver, keys: { string }, options: ValidateOptions?) -> ValidationReport,
	missing: (self: Resolver) -> { images: { string }, sounds: { string } },
}

local AssetResolver = {}

AssetResolver.KEY_PATTERN = "^[a-z0-9_]+$"
--- Mix buses of docs/design/audio.md §3.1.
AssetResolver.BUSES = table.freeze({ "Master", "Music", "Ambience", "Vehicles", "Weapons", "Impacts", "UI", "Voice" })

--- True for well-formed keys: lowercase segments of [a-z0-9_] separated by "/".
function AssetResolver.isValidKey(key: any): boolean
	if type(key) ~= "string" or key == "" or #key > 128 then
		return false
	end
	for segment in string.gmatch(key .. "/", "([^/]*)/") do
		if not string.match(segment, AssetResolver.KEY_PATTERN) then
			return false
		end
	end
	return true
end

--- First path segment ("classes/heavy" -> "classes"); nil for single-segment keys.
function AssetResolver.categoryOf(key: string): string?
	return string.match(key, "^([^/]+)/")
end

local function isContentId(id: any): boolean
	return type(id) == "string"
		and (string.match(id, "^rbxassetid://%d+$") ~= nil or string.match(id, "^rbxasset://.+") ~= nil)
end

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

--- Checks a manifest's structure; returns human-readable problems (empty = valid).
function AssetResolver.validateManifest(manifest: any): { string }
	local problems: { string } = {}
	if type(manifest) ~= "table" then
		return { "manifest is not a table" }
	end
	if type(manifest.version) ~= "number" then
		table.insert(problems, "version must be a number")
	end
	if type(manifest.images) ~= "table" then
		table.insert(problems, "images must be a table")
	end
	if type(manifest.sounds) ~= "table" then
		table.insert(problems, "sounds must be a table")
	end
	if #problems > 0 then
		return problems
	end
	for key, entry in manifest.images do
		if not AssetResolver.isValidKey(key) then
			table.insert(problems, `image key "{tostring(key)}" is malformed`)
		end
		if type(entry) ~= "table" or not isContentId(entry.id) then
			table.insert(problems, `image "{tostring(key)}" has no valid id`)
		elseif entry.size ~= nil and typeof(entry.size) ~= "Vector2" then
			table.insert(problems, `image "{tostring(key)}" size must be a Vector2`)
		end
	end
	for key, entry in manifest.sounds do
		if not AssetResolver.isValidKey(key) then
			table.insert(problems, `sound key "{tostring(key)}" is malformed`)
		end
		if type(entry) ~= "table" or not isContentId(entry.id) then
			table.insert(problems, `sound "{tostring(key)}" has no valid id`)
			continue
		end
		if not isFiniteNumber(entry.durationS) or entry.durationS <= 0 then
			table.insert(problems, `sound "{key}" durationS must be > 0`)
		end
		if type(entry.loop) ~= "boolean" then
			table.insert(problems, `sound "{key}" loop must be a boolean`)
		end
		if table.find(AssetResolver.BUSES, entry.bus) == nil then
			table.insert(problems, `sound "{key}" bus "{tostring(entry.bus)}" is not a mix bus`)
		end
		if not isFiniteNumber(entry.volume) or entry.volume < 0 or entry.volume > 10 then
			table.insert(problems, `sound "{key}" volume must be within 0..10`)
		end
		local region = entry.region
		if region ~= nil then
			if
				type(region) ~= "table"
				or not isFiniteNumber(region.startS)
				or not isFiniteNumber(region.endS)
				or region.startS < 0
				or region.endS <= region.startS
			then
				table.insert(problems, `sound "{key}" region must satisfy 0 <= startS < endS`)
			elseif entry.loop then
				table.insert(problems, `sound "{key}" is a loop but has a bank region (loops are never banked)`)
			end
		end
	end
	return problems
end

type ResolverImpl = {
	_manifest: Manifest,
	_glyphs: { [string]: boolean },
	_badges: { [string]: boolean },
	_warned: { [string]: boolean },
	_missingImages: { [string]: boolean },
	_missingSounds: { [string]: boolean },
	_log: Log.Logger,
}

local ResolverClass = {}
ResolverClass.__index = ResolverClass

local function warnOnce(self: ResolverImpl, key: string, level: "warn" | "debug", fmt: string, ...: any)
	if self._warned[key] then
		return
	end
	self._warned[key] = true
	if level == "warn" then
		self._log:warn(fmt, ...)
	else
		self._log:debug(fmt, ...)
	end
end

--- Creates a resolver over `manifest` (default: the generated AssetManifest).
function AssetResolver.new(manifest: Manifest?, options: ResolverOptions?): Resolver
	local opts: ResolverOptions = options or {}
	local glyphs: { [string]: boolean } = {}
	for _, key in FallbackKeys.glyphs do
		glyphs[key] = true
	end
	local extraGlyphs: { string } = opts.glyphs or {}
	for _, key in extraGlyphs do
		glyphs[key] = true
	end
	local badges: { [string]: boolean } = {}
	for _, category in FallbackKeys.badgeCategories do
		badges[category] = true
	end
	local extraBadges: { string } = opts.badgeCategories or {}
	for _, category in extraBadges do
		badges[category] = true
	end
	local self: ResolverImpl = setmetatable({
		_manifest = manifest or AssetManifest,
		_glyphs = glyphs,
		_badges = badges,
		_warned = {},
		_missingImages = {},
		_missingSounds = {},
		_log = opts.log or Log.scope("Assets"),
	}, ResolverClass) :: any
	return (self :: any) :: Resolver
end

function ResolverClass.hasImage(self: ResolverImpl, key: string): boolean
	return self._manifest.images[key] ~= nil
end

function ResolverClass.hasSound(self: ResolverImpl, key: string): boolean
	return self._manifest.sounds[key] ~= nil
end

function ResolverClass.has(self: ResolverImpl, key: string): boolean
	return self._manifest.images[key] ~= nil or self._manifest.sounds[key] ~= nil
end

function ResolverClass.hasGlyph(self: ResolverImpl, key: string): boolean
	return self._glyphs[key] == true
end

--- True if an image key renders without an upload (dedicated glyph or category badge).
function ResolverClass.hasFallback(self: ResolverImpl, key: string): boolean
	if self._glyphs[key] then
		return true
	end
	local category = AssetResolver.categoryOf(key)
	return category ~= nil and self._badges[category] == true
end

--- Registers an extra glyph-backed key at runtime (Icons does this for registry additions).
function ResolverClass.declareGlyph(self: ResolverImpl, key: string)
	if not AssetResolver.isValidKey(key) then
		error(`AssetResolver: invalid key "{tostring(key)}"`, 2)
	end
	self._glyphs[key] = true
end

function ResolverClass.imageAsset(self: ResolverImpl, key: string): ImageEntry?
	local entry = self._manifest.images[key]
	if entry ~= nil then
		return entry
	end
	self._missingImages[key] = true
	if ResolverClass.hasFallback(self, key) then
		warnOnce(self, "image:" .. key, "debug", "image %s not uploaded yet; using its fallback", key)
	elseif AssetResolver.isValidKey(key) then
		warnOnce(self, "image:" .. key, "warn", "image %s is not in the asset manifest and has no fallback", key)
	else
		warnOnce(self, "image:" .. key, "warn", "malformed image key %q", tostring(key))
	end
	return nil
end

--- Uploaded content id for an image key, or nil (draw the fallback).
function ResolverClass.image(self: ResolverImpl, key: string): string?
	local entry = ResolverClass.imageAsset(self, key)
	return if entry then entry.id else nil
end

--- Full resolution for renderers: image / glyph / badge / missing.
function ResolverClass.resolveImage(self: ResolverImpl, key: string): ImageResolution
	local entry = ResolverClass.imageAsset(self, key)
	if entry ~= nil then
		return { kind = "image", key = key, id = entry.id, entry = entry, category = AssetResolver.categoryOf(key) }
	end
	if self._glyphs[key] then
		return { kind = "glyph", key = key, id = nil, entry = nil, category = AssetResolver.categoryOf(key) }
	end
	local category = AssetResolver.categoryOf(key)
	if category ~= nil and self._badges[category] then
		return { kind = "badge", key = key, id = nil, entry = nil, category = category }
	end
	return { kind = "missing", key = key, id = nil, entry = nil, category = category }
end

--- Sound entry for a catalogue key, or nil (play nothing; warned once per key).
function ResolverClass.sound(self: ResolverImpl, key: string): SoundEntry?
	local entry = self._manifest.sounds[key]
	if entry ~= nil then
		return entry
	end
	self._missingSounds[key] = true
	warnOnce(self, "sound:" .. key, "warn", "sound %s is not uploaded; playing silence", tostring(key))
	return nil
end

--- Content-validation helper: keys that are malformed, or neither in the manifest nor (optionally) covered by a
--- declared fallback.
function ResolverClass.validateKeys(self: ResolverImpl, keys: { string }, options: ValidateOptions?): ValidationReport
	local opts: ValidateOptions = options or {}
	local kind = opts.kind or "image"
	local allowFallback = opts.allowFallback ~= false
	local report: ValidationReport = { missing = {}, invalid = {} }
	for _, key in keys do
		if not AssetResolver.isValidKey(key) then
			table.insert(report.invalid, tostring(key))
		elseif kind == "sound" then
			if self._manifest.sounds[key] == nil then
				table.insert(report.missing, key)
			end
		elseif self._manifest.images[key] == nil and not (allowFallback and ResolverClass.hasFallback(self, key)) then
			table.insert(report.missing, key)
		end
	end
	table.sort(report.missing)
	table.sort(report.invalid)
	return report
end

--- Keys requested at runtime that were missing (diagnostics: a debug panel lists what still needs uploading).
function ResolverClass.missing(self: ResolverImpl): { images: { string }, sounds: { string } }
	local images, sounds = {}, {}
	for key in self._missingImages do
		table.insert(images, key)
	end
	for key in self._missingSounds do
		table.insert(sounds, key)
	end
	table.sort(images)
	table.sort(sounds)
	return { images = images, sounds = sounds }
end

local defaultResolver: Resolver? = nil

--- The shared resolver over the generated manifest.
function AssetResolver.default(): Resolver
	local resolver = defaultResolver
	if resolver == nil then
		resolver = AssetResolver.new()
		defaultResolver = resolver
	end
	return resolver :: Resolver
end

-- Module-level shortcuts on the default resolver.
function AssetResolver.image(key: string): string?
	return AssetResolver.default():image(key)
end

function AssetResolver.imageAsset(key: string): ImageEntry?
	return AssetResolver.default():imageAsset(key)
end

function AssetResolver.resolveImage(key: string): ImageResolution
	return AssetResolver.default():resolveImage(key)
end

function AssetResolver.sound(key: string): SoundEntry?
	return AssetResolver.default():sound(key)
end

function AssetResolver.has(key: string): boolean
	return AssetResolver.default():has(key)
end

function AssetResolver.hasFallback(key: string): boolean
	return AssetResolver.default():hasFallback(key)
end

return AssetResolver
