class_name MissionGate
extends RefCounted

var regular_kill_target: int
var boss_required: bool
var regular_kills: int = 0
var boss_defeated: bool = false
var _destroyed_ids: Dictionary[int, bool] = {}


func _init(target: int = 0, requires_boss: bool = false) -> void:
	regular_kill_target = maxi(0, target)
	boss_required = requires_boss
## Returns false when the report is duplicate or malformed.
func record_destroyed(enemy_id: int, is_boss: bool) -> bool:
	if enemy_id <= 0 or _destroyed_ids.has(enemy_id):
		return false
	_destroyed_ids[enemy_id] = true
	if is_boss:
		boss_defeated = true
	else:
		regular_kills = mini(regular_kill_target, regular_kills + 1)
	return true


func is_complete() -> bool:
	return (
		regular_kills >= regular_kill_target
		and (not boss_required or boss_defeated)
	)
