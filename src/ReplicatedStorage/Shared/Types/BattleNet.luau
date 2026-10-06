--!strict
--[[
	Types/BattleNet — the BATTLE NETWORK PROTOCOL wire contract: decoded forms of the binary battle packets
	(BattleInput, BattleSnapshot, BattleEvents) and the table payloads of the reliable battle remotes (BattleAction,
	BattleReady/bootstrap, BattleState, BattleResults, BattleLeave, BattleSpectate).

	Purpose:          One shape shared by Net/Codecs/Battle/* (encoders/decoders), Net/RemoteDefs/Battle (validators),
	                  the battle server (replication producer) and the battle client (prediction, interpolation, HUD).
	                  Catalogue, rates and security notes: docs/systems/battle-protocol.md.
	Dependencies:     Types/Content, Types/Battle, Types/Vehicle, Types/VehicleSim (type-only).
	State:            None (type-only).
	Validation:       Codecs validate every decoded value (hostile-safe); servers build these records from trusted
	                  state. Table payloads are validated by the Schema validators in Codecs/Battle/Messages.
	Error handling:   N/A.
	Performance notes: Erased at runtime. Decoders write into caller-owned records where documented (reuse them).

	Units: positions STUDS (world), hull angles RADIANS (VehicleSimState convention), turret/gun angles DEGREES
	(TurretSimState convention), speeds km/h, times seconds, HP in hit points. Entity ids are 1..255 (0 = none).
	Ticks are server simulation ticks (Config.Battle.TICK_RATE); input sequences are wrapped to 16 bits on the wire.
]]

local Content = require("./Content")
local Battle = require("./Battle")
local Vehicle = require("./Vehicle")
local VehicleSim = require("./VehicleSim")

type VehicleId = Content.VehicleId
type MapId = Content.MapId
type EventId = Content.EventId
type ShellKind = Content.ShellKind
type CrewRole = Content.CrewRole
type MechanicKind = Content.MechanicKind
type InternalModuleKind = Content.InternalModuleKind
type ConsumableId = Content.ConsumableId
type VehicleClass = Content.VehicleClass
type ReloadKind = Content.ReloadKind
type EntityId = Battle.EntityId
type TeamId = Battle.TeamId
type BattleMode = Battle.BattleMode
type BattleType = Battle.BattleType
type DamageKind = Battle.DamageKind
type BattleEndReason = Battle.BattleEndReason
type BattleOutcomeKind = Battle.BattleOutcomeKind
type ModuleState = Vehicle.ModuleState
type InputCommand = Vehicle.InputCommand
type ImmobileReason = VehicleSim.ImmobileReason
type VehicleSimModifiers = VehicleSim.VehicleSimModifiers
type MechanicRuntime = VehicleSim.MechanicRuntime

--- Battle lifecycle phase (same values as Shared/Battle/Rules/Phases.Phase).
export type NetPhase = "Preparing" | "Loading" | "Countdown" | "Active" | "Ending" | "Results" | "Closed"

--------------------------------------------------------------------------------
-- BattleInput (C2S, UnreliableRemoteEvent, one buffer; InputCodec)
--------------------------------------------------------------------------------

--- Decoded input packet: the newest command plus up to two older ones (loss tolerance, ARCHITECTURE §5.2).
export type InputBatch = {
	seq: number, -- newest command's input sequence, wrapped to [0, 65535]
	count: number, -- commands in the packet (1..InputCodec.MAX_COMMANDS)
	--- Newest first; commands[i].seq = (seq - i + 1) mod 65536. Entries beyond `count` are stale scratch.
	commands: { InputCommand },
}

--------------------------------------------------------------------------------
-- BattleAction (C2S, RemoteEvent, one table; Codecs/Battle/Actions)
--------------------------------------------------------------------------------

export type ActionKind = "Fire" | "SwitchShell" | "UseConsumable" | "ActivateMechanic" | "QuickCommand" | "MapPing"
--- The 12 command presets of 00-DECISIONS §9 (no end punctuation in their display strings).
export type QuickCommandId =
	"Attack"
	| "DefendBase"
	| "NeedHelp"
	| "Affirmative"
	| "Negative"
	| "Reloading"
	| "Thanks"
	| "HoldPosition"
	| "FollowMe"
	| "EnemySpotted"
	| "MovingHere"
	| "FocusFire"
--- Minimap pings: LMB "attention", RMB "moving here" (00-DECISIONS §9).
export type PingKind = "Attention" | "Moving"

--- Discrete, reliable player actions. Map points are 2-D world STUDS (mapX, mapZ) — designations, never vehicle
--- positions (REG-NET-03); the server re-validates every field against battle state.
---   Fire             reliable copy of a trigger PRESS made at input `seq` (wrapped u16): insurance against losing
---                    every redundant copy of the press edge in BattleInput. The server applies it only when the
---                    input stream has not already delivered a press at or after `seq` (it never adds a shot).
---   SwitchShell      select ammo slot 1..3 (Loadout.ammo / GunStats.shells order).
---   UseConsumable    activate consumable slot 1..3.
---   ActivateMechanic toggle/trigger the vehicle's mechanic of that kind (must match the vehicle).
---   QuickCommand     a command preset, optionally about an entity (targetId) or a map point (mapX + mapZ).
---   MapPing          a minimap marker.
export type BattleAction =
	{ kind: "Fire", seq: number }
	| { kind: "SwitchShell", slot: number }
	| { kind: "UseConsumable", slot: number }
	| { kind: "ActivateMechanic", mechanic: MechanicKind }
	| { kind: "QuickCommand", command: QuickCommandId, targetId: EntityId?, mapX: number?, mapZ: number? }
	| { kind: "MapPing", ping: PingKind, mapX: number, mapZ: number }

--------------------------------------------------------------------------------
-- BattleSnapshot (S2C, UnreliableRemoteEvent, buffer chunks; SnapshotCodec)
--------------------------------------------------------------------------------

--- Compact state of another vehicle (allies always; enemies only while team-visible and <= 564 m; wrecks).
export type EntityState = {
	id: EntityId,
	position: Vector3, -- studs, hull origin (footprint centre at track-bottom level)
	yaw: number, -- radians, VehicleSimState convention; decoded in [-pi, pi)
	pitch: number,
	roll: number,
	--- Turret bearing for turreted vehicles, gun yaw for casemates (TurretSimState.turretYawDeg + gunYawDeg), deg.
	turretYawDeg: number,
	gunPitchDeg: number,
	speedKmh: number, -- signed hull speed (+ forward)
	hpFraction: number, -- hp / maxHp in [0, 1]; > 0 whenever hp > 0 (maxHp comes from the roster)
	moving: boolean,
	firing: boolean, -- fired since the previous snapshot (muzzle effects of unidentified tracers excluded)
	burning: boolean,
	tracksBroken: boolean, -- a track (or wheel side) is destroyed
	destroyed: boolean,
	stunned: boolean,
	mechanicActive: boolean, -- siege/speed mode/boost visuals
}

--- Coarse minimap-only record (team-visible enemies beyond 564 m, 2 Hz; ARCHITECTURE §6.1 step 9).
export type MinimapRecord = {
	id: EntityId,
	x: number, -- studs, 1-stud resolution
	z: number,
	yaw: number, -- radians, 256 steps
}

--- The owner's hull state for reconciliation (ARCHITECTURE §6.2). Field names and units are VehicleSimState's, so a
--- VehicleSimState can be passed to the encoder as is; the client copies these fields into its predicted state and
--- replays unacknowledged inputs. Terrain fields (terrainClass, terrainResistance, traction, material) and the
--- private caches are not replicated: the client re-probes the ground on the next step.
export type OwnerSim = {
	position: Vector3,
	yaw: number,
	pitch: number,
	roll: number,
	speed: number, -- studs/s along the hull forward axis
	lateralSpeed: number,
	yawRate: number,
	verticalVelocity: number,
	grounded: boolean,
	groundPitch: number,
	groundRoll: number,
	waterDepthM: number,
	submerged: boolean,
	airborneTime: number,
	submergedTime: number,
	tiltTime: number,
	overturnedTime: number,
	stillTime: number,
	overturned: boolean,
	drowned: boolean,
	wrecked: boolean,
	immobilized: boolean,
	immobileReason: ImmobileReason?,
	mechanicActive: boolean,
	gunDepressionBonusDeg: number,
	gunElevationBonusDeg: number,
	modifiers: VehicleSimModifiers, -- every field replicated (speedCapKmh may be math.huge)
	mechanic: MechanicRuntime, -- every field replicated (charges may be math.huge)
}

--- The owner's turret/gun laying state (TurretSimState angles + the runtime modifiers the client cannot derive).
export type OwnerTurret = {
	turretYawDeg: number,
	gunYawDeg: number,
	gunPitchDeg: number,
	bearingSpeedDegS: number,
	pitchSpeedDegS: number,
	traverseMul: number, -- TurretSimModifiers.traverseMul
	elevationSpeedMul: number,
	depressionBonusDeg: number,
	elevationBonusDeg: number,
	enabled: boolean,
}

export type GunPhase = "Ready" | "Reloading" | "IntraClip" | "Charging" | "Empty" | "Disabled" | "Dead"

--- HUD view of the owner's gun: exactly the fields of Vehicle/GunState.GunSnapshot, so the server passes
--- GunState.snapshot(...) as is. Times travel in centiseconds (65535 = math.huge); reloadProgress and totalAmmo
--- are derived on decode.
export type GunView = {
	kind: ReloadKind,
	phase: GunPhase,
	alive: boolean,
	enabled: boolean,
	canFire: boolean,
	selectedSlot: number,
	loadedSlot: number,
	reloadProgress: number,
	reloadRemainingS: number,
	reloadDurationS: number,
	nextShotS: number,
	intraClipRemainingS: number,
	roundsLoaded: number,
	magazineSize: number,
	toppingOff: boolean,
	refillSlotIndex: number,
	chargeProgress: number,
	reloadMul: number,
	ammo: { number },
	totalAmmo: number,
	barrelProgress: { number },
}

--- One damageable module of the owner (DamageModel ModuleCombatState subset), in DamageModel moduleOrder.
export type ModuleView = {
	kind: InternalModuleKind,
	state: ModuleState,
	repairRemainingS: number, -- > 0 while a Destroyed module is being field-repaired
	repairS: number, -- full field-repair time
}

--- One consumable slot of the owner (array index = loadout slot).
export type ConsumableView = {
	active: boolean, -- effect running (durationS)
	charges: number, -- uses left (math.huge = unlimited)
	cooldownRemainingS: number,
	cooldownS: number, -- effective full cooldown
	activeRemainingS: number,
}

--- The owner's combat/HUD state (hp, modules, crew, fire, stun, aiming circle, consumables).
export type OwnerCombat = {
	hp: number, -- integer HP (maxHp comes from the roster)
	burning: boolean,
	stunRemainingS: number,
	modules: { ModuleView },
	crewInjured: { boolean }, -- by crew slot
	aimMultiplier: number, -- server Dispersion M (1 = fully aimed) for the optional server reticle
	consumables: { ConsumableView },
}

export type OwnerState = {
	entityId: EntityId,
	sim: OwnerSim,
	turret: OwnerTurret,
	gun: GunView?, -- nil for gunless vehicles / spectators
	combat: OwnerCombat,
}

--- One per-observer snapshot (filtered by the server; anti-wallhack invariants in docs/systems/battle-protocol.md).
export type SnapshotFrame = {
	tick: number, -- server tick = the stream's sequence number (strictly increasing per observer)
	lastInputSeq: number, -- owner's last processed input seq, wrapped to 16 bits (0 without owner)
	owner: OwnerState?,
	entities: { EntityState },
	minimap: { MinimapRecord },
}

--------------------------------------------------------------------------------
-- BattleEvents (S2C, RemoteEvent, one buffer per batch; EventCodec)
--------------------------------------------------------------------------------

--- Projectile outcome as replicated (Types/Battle.ShotResultKind + "Miss" for map/terrain impacts and expiry).
export type NetShotResult =
	"Penetration"
	| "NonPenetration"
	| "Ricochet"
	| "Absorbed"
	| "Splash"
	| "AllyBlocked"
	| "Miss"
export type CaliberClass = "Small" | "Medium" | "Large"
export type RibbonKind =
	"Damage"
	| "Kill"
	| "Spotted"
	| "AssistSpot"
	| "AssistTrack"
	| "AssistStun"
	| "Crit"
	| "Blocked"
	| "Capture"
	| "Defense"
	| "Fire"
	| "Ram"
export type NoticeKind = "AfkWarning" | "BotTakeover" | "ControlRestored"

--- Reliable, ordered battle events for one observer. `tick` = server tick of the event. Entity fields use 0 for
--- "none / not revealed": an attacker the observer's team cannot see is always 0 (REG-SPT-08).
---   ShotFired   tracer start: shooter 0 + tracerOnly = anonymous tracer of the last <= 100 m of flight.
---   ShotHeard   anonymous gunfire of an unseen shooter: position snapped to 50 m with bearing noise (server).
---   ShotResult  impact of `shotId` (0 = unidentified shell) at `point`, `direction` = shell travel direction.
---   Damage      non-shell HP damage (fire, ram, fall, drown, ammo rack).
---   Lost        team lost sight of `target`; (x, z) = last-known position (30 s marker).
export type NetEvent =
	{
		type: "ShotFired",
		tick: number,
		shooter: EntityId,
		shotId: number, -- u16, wraps
		shellIndex: number, -- 1..3 (0 = unknown)
		shellKind: ShellKind,
		caliberMm: number,
		origin: Vector3,
		direction: Vector3, -- unit
		speedMps: number,
		gravityMps2: number,
		volley: boolean,
		charged: boolean,
		tracerOnly: boolean,
	}
	| { type: "ShotHeard", tick: number, caliberClass: CaliberClass, x: number, z: number }
	| {
		type: "ShotResult",
		tick: number,
		shotId: number,
		target: EntityId,
		attacker: EntityId,
		result: NetShotResult,
		damage: number,
		critical: boolean,
		fireStarted: boolean,
		killed: boolean,
		point: Vector3,
		direction: Vector3,
	}
	| {
		type: "ModuleState",
		tick: number,
		target: EntityId,
		module: InternalModuleKind,
		state: ModuleState,
		attacker: EntityId,
	}
	| { type: "CrewInjured", tick: number, target: EntityId, slot: number, role: CrewRole, healed: boolean }
	| { type: "Damage", tick: number, target: EntityId, attacker: EntityId, kind: DamageKind, damage: number }
	| { type: "Destroyed", tick: number, target: EntityId, attacker: EntityId, cause: DamageKind }
	| { type: "Spotted", tick: number, target: EntityId, spotter: EntityId, first: boolean }
	| { type: "Lost", tick: number, target: EntityId, x: number, z: number }
	| { type: "SixthSense", tick: number }
	| { type: "Fire", tick: number, target: EntityId, burning: boolean }
	| { type: "Stunned", tick: number, target: EntityId, durationS: number }
	| { type: "ConsumableUsed", tick: number, participant: EntityId, consumable: ConsumableId }
	| {
		type: "Command",
		tick: number,
		sender: EntityId,
		command: QuickCommandId,
		targetId: EntityId,
		hasPoint: boolean,
		x: number,
		z: number,
	}
	| { type: "Ping", tick: number, sender: EntityId, ping: PingKind, x: number, z: number }
	| { type: "Ribbon", tick: number, ribbon: RibbonKind, value: number, target: EntityId }
	| { type: "Notice", tick: number, notice: NoticeKind }
export type NetEventType =
	"ShotFired"
	| "ShotHeard"
	| "ShotResult"
	| "ModuleState"
	| "CrewInjured"
	| "Damage"
	| "Destroyed"
	| "Spotted"
	| "Lost"
	| "SixthSense"
	| "Fire"
	| "Stunned"
	| "ConsumableUsed"
	| "Command"
	| "Ping"
	| "Ribbon"
	| "Notice"

--------------------------------------------------------------------------------
-- BattleState / BattleReady / BattleResults (reliable tables; Codecs/Battle/Messages)
--------------------------------------------------------------------------------

export type TeamView = {
	team: TeamId,
	alive: number,
	total: number,
	hp: number, -- Σ current HP of the team (public team HP bar)
	maxHp: number,
	kills: number,
}

--- Capture base (fields of Shared/Battle/Rules/Capture.BaseSnapshot, so Capture.snapshot output passes as is).
export type BaseView = {
	base: string,
	team: TeamId, -- team that captures this base (attackers)
	progress: number, -- 0..100 points
	frozen: boolean,
	contested: boolean,
	cappers: number,
	capturedBy: TeamId?,
}

--- Public roster line (team lists are public, like the WoT team panels; never positions or spotted state).
export type RosterEntry = {
	entityId: EntityId,
	team: TeamId,
	name: string,
	userId: number?, -- humans only
	isBot: boolean,
	controller: "Player" | "Bot", -- current driver (disconnect / AFK hand-over)
	vehicleId: VehicleId,
	tier: number,
	class: VehicleClass,
	maxHp: number,
	platoon: number?, -- platoon pip (1..) within the team
	alive: boolean,
}

--- Full battle state, sent reliably on change (phase, timer, scores, capture) and after BattleReady. `roster` is
--- present when it changed since the previous message (and always in the bootstrap).
export type BattleStateMessage = {
	seq: number, -- per-battle message counter (strictly increasing)
	tick: number,
	phase: NetPhase,
	phaseEndsAtTick: number?, -- server tick when the current timed phase ends (countdown, battle timer, banner)
	timeLeftS: number?, -- convenience copy of the battle timer
	teams: { TeamView },
	bases: { BaseView },
	roster: { RosterEntry }?,
}

--- BattleReady request: sent once the client finished loading the map and its assets.
export type BattleReadyRequest = {
	protocol: number, -- Net/Protocol.PROTOCOL_VERSION
	contentHash: string, -- ContentRegistry:contentHash() of the client
}

--- BattleReady response value (wrapped in a Result).
export type BattleBootstrap = {
	protocol: number,
	battleId: string,
	mapId: MapId,
	mode: BattleMode,
	battleType: BattleType?,
	eventId: EventId?,
	entityId: EntityId?, -- nil = spectator
	team: TeamId?,
	tickRate: number,
	snapshotRate: number,
	serverTick: number,
	state: BattleStateMessage,
}

export type PersonalResult = {
	survived: boolean,
	damageDealt: number,
	assist: number, -- spotting + tracking + stun
	damageBlocked: number,
	kills: number,
	spotted: number,
}

--- End-of-battle banner (6 s); full results and rewards are shown in the Hub from the reward inbox.
export type BattleResultsMessage = {
	battleId: string,
	winner: TeamId?,
	reason: BattleEndReason,
	outcome: BattleOutcomeKind, -- for the receiving player's team (spectators: the winner's view)
	durationS: number,
	endedAtTick: number,
	personal: PersonalResult?,
}

export type BattleLeaveRequest = { requestId: string }
export type BattleSpectateRequest = { targetId: EntityId? } -- nil = next available

return {}
