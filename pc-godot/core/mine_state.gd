class_name MineState
extends RefCounted

const CombatEnumsRef = preload("res://data/combat_enums.gd")

var mine_id: int
var owner_id: int
var faction: CombatEnumsRef.Faction
var position: Vector3
var damage: float
var armed_at: float
var expires_at: float


func _init(
	initial_mine_id: int,
	initial_owner_id: int,
	initial_faction: CombatEnumsRef.Faction,
	initial_position: Vector3,
	initial_damage: float,
	initial_armed_at: float,
	initial_expires_at: float
) -> void:
	mine_id = initial_mine_id
	owner_id = initial_owner_id
	faction = initial_faction
	position = initial_position
	damage = maxf(0.0, initial_damage)
	armed_at = initial_armed_at
	expires_at = initial_expires_at


func is_armed(now: float) -> bool:
	return now >= armed_at and now < expires_at


func can_trigger(target_faction: CombatEnumsRef.Faction, now: float) -> bool:
	return is_armed(now) and CombatEnumsRef.are_hostile(faction, target_faction)
