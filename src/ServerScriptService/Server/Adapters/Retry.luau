--!strict
--[[
	Retry — pcall + bounded exponential backoff for Roblox platform calls (adapters only).

	Purpose:          Wrap yielding platform APIs so transient failures (throttling, 5xx) are retried a few times
	                  while permanent ones (bad key, value too large, no Studio API access) fail immediately.
	Dependencies:     task.wait (injectable for tests).
	State:            None.
	Validation:       attempts >= 1.
	Error handling:   Returns (false, lastErrorMessage); never throws.
	Performance notes: Backoff base 0.5 s doubling to max 4 s; callers with their own policies (DataService) pass
	                  attempts = 1.
]]

export type RetryOptions = {
	attempts: number?,
	baseDelay: number?,
	maxDelay: number?,
	shouldRetry: ((err: string) -> boolean)?,
	wait: ((seconds: number) -> ())?,
}

local Retry = {}

local PERMANENT_DATASTORE_CODES: { [number]: boolean } = {
	[101] = true,
	[102] = true,
	[103] = true,
	[104] = true,
	[105] = true,
	[106] = true,
	[107] = true,
	[401] = true,
	[402] = true,
	[403] = true,
	[404] = true,
	[511] = true,
	[512] = true,
	[513] = true,
}

--- Numeric Roblox error code at the start of a message ("502: ..."), if any.
function Retry.errorCode(err: string): number?
	local code = string.match(err, "^%s*(%d+)%s*:")
	return if code then tonumber(code) else nil
end

--- True unless the message carries a known permanent DataStore error code.
function Retry.isTransient(err: string): boolean
	local code = Retry.errorCode(err)
	if code ~= nil and PERMANENT_DATASTORE_CODES[code] then
		return false
	end
	return true
end

--- Calls fn up to `attempts` times. Returns (true, result) or (false, lastError).
function Retry.call<T>(fn: () -> T, options: RetryOptions?): (boolean, T | string)
	local opts: RetryOptions = options or {}
	local attempts = math.max(1, opts.attempts or 3)
	local delay = opts.baseDelay or 0.5
	local maxDelay = opts.maxDelay or 4
	local shouldRetry = opts.shouldRetry or Retry.isTransient
	local waitFn: (seconds: number) -> () = opts.wait or function(seconds: number)
		task.wait(seconds)
	end
	local lastError = "unknown error"
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if attempt == attempts or not shouldRetry(lastError) then
			break
		end
		waitFn(math.min(maxDelay, delay * 2 ^ (attempt - 1)))
	end
	return false, lastError
end

return Retry
