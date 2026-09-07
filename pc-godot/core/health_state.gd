class_name HealthState
extends RefCounted

const CombatEnumsRef = preload("res://data/combat_enums.gd")

var faction: CombatEnumsRef.Faction = CombatEnumsRef.Faction.NEUTRAL
var max_health: float = 1.0
var health: float = 1.0
var shielded: bool = false


func _init(
	initial_faction: CombatEnumsRef.Faction = CombatEnumsRef.Faction.NEUTRAL,
	initial_max_health: float = 1.0
) -> void:
	faction = initial_faction
	max_health = maxf(0.0, initial_max_health)
	health = max_health


func is_alive() -> bool:
	return health > 0.0


func restore(amount: float) -> float:
	if amount <= 0.0 or not is_alive():
		return 0.0
	var before := health
	health = minf(max_health, health + amount)
	return health - before
