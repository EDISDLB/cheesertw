--!strict
--[[
	Codecs/Battle/Enums — the byte codes of every string enum carried by the binary battle codecs.

	Purpose:          Stable wire codes for the string unions of Types/Content, Types/Battle, Types/VehicleSim and
	                  Types/BattleNet. Codes are 1-based list positions; 0 is reserved for "none" (optional enums).
	                  APPEND ONLY: reordering or removing a value is a protocol change (bump Net/Protocol).
	Dependencies:     None.
	State:            Frozen lookup tables built at load.
	Validation:       encode raises on unknown values (server/client bug); decode returns nil for unknown codes
	                  (decoders turn that into a clean Err).
	Error handling:   See Validation.
	Performance notes: O(1) table lookups, no allocation.
]]

export type Enum = {
	name: string,
	values: { string }, -- code -> value (1-based)
	codes: { [string]: number }, -- value -> code
}

local function makeEnum(name: string, values: { string }): Enum
	local codes: { [string]: number } = {}
	for i, value in values do
		assert(codes[value] == nil, `Enums.{name}: duplicate value {value}`)
		codes[value] = i
	end
	assert(#values <= 255, `Enums.{name}: more than 255 values`)
	return table.freeze({ name = name, values = table.freeze(values), codes = table.freeze(codes) })
end

local Enums = {}

Enums.ImmobileReason = makeEnum("ImmobileReason", {
	"Tracks",
	"Engine",
	"Overturned",
	"Drowned",
	"FellOut",
	"Wrecked",
	"External",
})
Enums.MechanicPhase = makeEnum("MechanicPhase", { "Off", "Engaging", "On", "Disengaging", "Cooldown" })
Enums.MechanicKind = makeEnum("MechanicKind", {
	"SiegeMode",
	"Hydropneumatic",
	"Wheeled",
	"Turbo",
	"RocketBoost",
	"ChargedShot",
	"ActiveCooling",
	"AdaptiveMagazine",
	"ReserveTracks",
})
Enums.ModuleState = makeEnum("ModuleState", { "Ok", "Damaged", "Destroyed" })
Enums.ModuleKind = makeEnum("ModuleKind", {
	"Engine",
	"AmmoRack",
	"FuelTank",
	"Gun",
	"TurretRing",
	"Optics",
	"TrackLeft",
	"TrackRight",
})
Enums.CrewRole = makeEnum("CrewRole", { "Commander", "Gunner", "Driver", "Loader" })
Enums.ReloadKind = makeEnum("ReloadKind", { "Single", "Magazine", "Autoreloader", "DualGun" })
Enums.GunPhase = makeEnum("GunPhase", { "Ready", "Reloading", "IntraClip", "Charging", "Empty", "Disabled", "Dead" })
Enums.ShellKind = makeEnum("ShellKind", { "AP", "APCR", "HEAT", "HE", "HESH" })
Enums.ShotResult = makeEnum("ShotResult", {
	"Penetration",
	"NonPenetration",
	"Ricochet",
	"Absorbed",
	"Splash",
	"AllyBlocked",
	"Miss",
})
Enums.DamageKind = makeEnum("DamageKind", { "Shell", "Splash", "Fire", "Ram", "Fall", "AmmoRack", "Drown" })
Enums.CaliberClass = makeEnum("CaliberClass", { "Small", "Medium", "Large" })
Enums.QuickCommand = makeEnum("QuickCommand", {
	"Attack",
	"DefendBase",
	"NeedHelp",
	"Affirmative",
	"Negative",
	"Reloading",
	"Thanks",
	"HoldPosition",
	"FollowMe",
	"EnemySpotted",
	"MovingHere",
	"FocusFire",
})
Enums.PingKind = makeEnum("PingKind", { "Attention", "Moving" })
Enums.RibbonKind = makeEnum("RibbonKind", {
	"Damage",
	"Kill",
	"Spotted",
	"AssistSpot",
	"AssistTrack",
	"AssistStun",
	"Crit",
	"Blocked",
	"Capture",
	"Defense",
	"Fire",
	"Ram",
})
Enums.NoticeKind = makeEnum("NoticeKind", { "AfkWarning", "BotTakeover", "ControlRestored" })
--- NetEvent.type codes (EventCodec record tags).
Enums.EventType = makeEnum("EventType", {
	"ShotFired",
	"ShotHeard",
	"ShotResult",
	"ModuleState",
	"CrewInjured",
	"Damage",
	"Destroyed",
	"Spotted",
	"Lost",
	"SixthSense",
	"Fire",
	"Stunned",
	"ConsumableUsed",
	"Command",
	"Ping",
	"Ribbon",
	"Notice",
})

--- Code of `value` in `enum`; raises on unknown values (encoders only ever see trusted, typed values).
function Enums.encode(enum: Enum, value: string): number
	local code = enum.codes[value]
	if code == nil then
		error(`Enums.{enum.name}: unknown value {tostring(value)}`, 2)
	end
	return code
end

--- Like encode, but nil / "" map to 0 ("none").
function Enums.encodeOptional(enum: Enum, value: string?): number
	if value == nil or value == "" then
		return 0
	end
	return Enums.encode(enum, value)
end

--- Value of `code`, or nil for 0 / unknown codes.
function Enums.decode(enum: Enum, code: number): string?
	return enum.values[code]
end

return table.freeze(Enums)
