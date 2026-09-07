class_name DamageResolver
extends RefCounted

const CombatEnumsRef = preload("res://data/combat_enums.gd")
const HealthStateRef = preload("res://core/health_state.gd")


## Returns the damage actually removed from the target.
static func apply_damage(
	target: HealthStateRef,
	source_faction: CombatEnumsRef.Faction,
	amount: float,
	ignores_shield: bool = false
) -> float:
	if (
		target == null
		or amount <= 0.0
		or not target.is_alive()
		or not CombatEnumsRef.are_hostile(source_faction, target.faction)
		or (target.shielded and not ignores_shield)
	):
		return 0.0
	var before := target.health
	target.health = maxf(0.0, target.health - amount)
	return before - target.health
