--!strict
--[[
	ErrorCodes — the registry of SCREAMING_SNAKE error codes used in Result.err and remote responses.

	Purpose:          One list of codes shared by server, client and UI; extensible by every team (add entries here).
	Dependencies:     None.
	State:            Frozen constant tables.
	Validation:       ErrorCodes.isKnown(code) for boundary checks; tests assert key == value for every entry.
	Error handling:   N/A.
	Performance notes: Constant lookups.

	Adding a code: add `NAME = "NAME"` to `codes` and a default player-facing message to `messages`.
]]

local ErrorCodes = {
	-- Transport / protocol
	RATE_LIMITED = "RATE_LIMITED",
	INVALID_ARGS = "INVALID_ARGS",
	NOT_ALLOWED = "NOT_ALLOWED",
	PROTOCOL_VIOLATION = "PROTOCOL_VIOLATION",
	TIMEOUT = "TIMEOUT",
	NOT_READY = "NOT_READY",
	DUPLICATE_REQUEST = "DUPLICATE_REQUEST",
	INTERNAL = "INTERNAL",
	UNAVAILABLE = "UNAVAILABLE",
	VERSION_MISMATCH = "VERSION_MISMATCH",
	-- Domain (generic)
	NOT_FOUND = "NOT_FOUND",
	INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS",
	CONFLICT = "CONFLICT",
	LIMIT_REACHED = "LIMIT_REACHED",
}

export type ErrorCode = string

local MESSAGES: { [string]: string } = table.freeze({
	RATE_LIMITED = "You're doing that too fast. Please wait a moment.",
	INVALID_ARGS = "That request was invalid.",
	NOT_ALLOWED = "You can't do that right now.",
	PROTOCOL_VIOLATION = "Unexpected request.",
	TIMEOUT = "The server took too long to respond.",
	NOT_READY = "The server is still starting. Please wait.",
	DUPLICATE_REQUEST = "That request was already processed.",
	INTERNAL = "Something went wrong on our side.",
	UNAVAILABLE = "That service is temporarily unavailable.",
	VERSION_MISMATCH = "A new version of the game is available. Please rejoin.",
	NOT_FOUND = "Not found.",
	INSUFFICIENT_FUNDS = "Not enough currency.",
	CONFLICT = "That changed in the meantime. Please try again.",
	LIMIT_REACHED = "Limit reached.",
})

local codeSet: { [string]: boolean } = {}
for key, value in ErrorCodes :: any do
	if type(value) == "string" then
		codeSet[key] = true
	end
end

--- True if `code` is a registered error code.
function ErrorCodes.isKnown(code: unknown): boolean
	return type(code) == "string" and codeSet[code] == true
end

--- Default player-facing text for `code` (UI may localize by code instead).
function ErrorCodes.message(code: string): string
	return MESSAGES[code] or MESSAGES.INTERNAL
end

--- All codes, sorted.
function ErrorCodes.all(): { string }
	local out = {}
	for code in codeSet do
		table.insert(out, code)
	end
	table.sort(out)
	return out
end

--- Code -> message table (read-only), for UI localization tables and tests.
function ErrorCodes.messages(): { [string]: string }
	return MESSAGES
end

return table.freeze(ErrorCodes)
