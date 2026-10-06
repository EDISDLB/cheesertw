--!strict
--[[
	Battle/Ledger/KillCredit — who is credited with destroying a vehicle (00-DECISIONS §2: fire credited to the
	igniter, drowning gives no credit, friendly fire off; REG-BTL-02 mutual kills).

	Purpose:          One pure rule used by the Ledger (kills, kill feed, killedBy) and by BattleInstance when it fills
	                  the Destroyed event, so both always agree:
	                    Shell / Splash / Ram / AmmoRack → the attacker (the rammer; the shooter whose hit detonated
	                                                       the ammo rack)
	                    Fire                            → the attacker of the fire damage = the igniter
	                    Fall                            → the attacker when there is one (landing on a vehicle),
	                                                       else the last enemy that dealt HP damage to the victim
	                                                       within FALL_CREDIT_WINDOW_S (O: pushed off a cliff)
	                    Drown                           → nobody
	                  An attacker counts only when it is a known participant of the OTHER team (never the victim,
	                  an ally or the environment). A dead attacker still gets the kill (shells in flight, mutual kills).
	Dependencies:     Types/Battle (types only).
	State:            None.
	Validation:       Unknown kinds credit nobody; non-finite times disable the fall window.
	Error handling:   No throws.
	Performance notes: O(1).
]]

local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type EntityId = BattleTypes.EntityId
type TeamId = BattleTypes.TeamId
type DamageKind = BattleTypes.DamageKind

export type CreditRule = "Attacker" | "AttackerOrLastDamager" | "None"

local KillCredit = {}

--- The rule per damage kind (data for docs/tests; resolve() implements it).
KillCredit.RULES = table.freeze({
	Shell = "Attacker" :: CreditRule,
	Splash = "Attacker" :: CreditRule,
	Ram = "Attacker" :: CreditRule,
	AmmoRack = "Attacker" :: CreditRule,
	Fire = "Attacker" :: CreditRule,
	Fall = "AttackerOrLastDamager" :: CreditRule,
	Drown = "None" :: CreditRule,
})

--- True when `a` and `b` are known participants of different teams.
function KillCredit.isEnemy(teamOf: { [EntityId]: TeamId }, a: EntityId?, b: EntityId?): boolean
	if a == nil or b == nil or a == b then
		return false
	end
	local ta, tb = teamOf[a], teamOf[b]
	return ta ~= nil and tb ~= nil and ta ~= tb
end

--- The participant credited with destroying `victim` at battle time `t` by `cause`, or nil.
--- `lastDamager`/`lastDamageT` = the last enemy that dealt HP damage to the victim (fall rule only).
function KillCredit.resolve(
	cause: DamageKind,
	attacker: EntityId?,
	victim: EntityId,
	t: number,
	teamOf: { [EntityId]: TeamId },
	lastDamager: EntityId?,
	lastDamageT: number?,
	fallWindowS: number
): EntityId?
	local rule: CreditRule? = (KillCredit.RULES :: any)[cause]
	if rule == nil or rule == "None" then
		return nil
	end
	if KillCredit.isEnemy(teamOf, attacker, victim) then
		return attacker
	end
	if rule == "AttackerOrLastDamager" and lastDamageT ~= nil and KillCredit.isEnemy(teamOf, lastDamager, victim) then
		local age = t - lastDamageT
		if age >= 0 and age <= fallWindowS then
			return lastDamager
		end
	end
	return nil
end

return KillCredit
