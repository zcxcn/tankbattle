class_name CombatLoadout
extends RefCounted
## Weapon state belongs to each vehicle. Switching never restarts a timer.

const WEAPONS := [
	{"id": "cannon", "name": "穿甲主炮", "interval": 2.9, "damage": 62.0, "speed": 260.0, "splash": 0.0, "capacity": -1, "reserve": 0},
	{"id": "machine_gun", "name": "同轴机枪", "interval": 0.15, "damage": 3.4, "speed": 500.0, "splash": 0.0, "capacity": 40, "reserve": 240, "belt_reload": 4.4},
	{"id": "he", "name": "高爆榴弹", "interval": 3.8, "damage": 52.0, "speed": 185.0, "splash": 8.0, "capacity": 24, "reserve": 0},
	{"id": "rocket", "name": "反装甲火箭", "interval": 5.8, "damage": 88.0, "speed": 95.0, "splash": 6.0, "capacity": 8, "reserve": 0},
]

var selected := 0
var _states: Array[Dictionary] = []


func _init() -> void:
	for definition: Dictionary in WEAPONS:
		_states.append({"ammo": int(definition.capacity), "reserve": int(definition.reserve), "cooldown": 0.0, "reload_max": float(definition.interval), "belt_reloading": false})


func select(index: int) -> bool:
	if index < 0 or index >= WEAPONS.size():
		return false
	selected = index
	return true


func cycle() -> void:
	selected = (selected + 1) % WEAPONS.size()


func tick(delta: float) -> void:
	for index in _states.size():
		var state: Dictionary = _states[index]
		state.cooldown = maxf(0.0, float(state.cooldown) - maxf(delta, 0.0))
		if state.belt_reloading and state.cooldown <= 0.0:
			var count := mini(int(WEAPONS[index].capacity), int(state.reserve))
			state.ammo = count
			state.reserve -= count
			state.belt_reloading = false
			state.reload_max = float(WEAPONS[index].interval)


func can_fire() -> bool:
	var state: Dictionary = _states[selected]
	return state.cooldown <= 0.0 and state.ammo != 0


func fire(interval_override := -1.0) -> Dictionary:
	if not can_fire():
		return {}
	var definition: Dictionary = WEAPONS[selected]
	var state: Dictionary = _states[selected]
	var interval := interval_override if interval_override > 0.0 else float(definition.interval)
	state.cooldown = interval
	state.reload_max = interval
	if state.ammo > 0:
		state.ammo -= 1
	# AP and HE use the same breech. Cycling ammunition cannot double-fire it.
	if selected == 0 or selected == 2:
		var shared: Dictionary = _states[2 if selected == 0 else 0]
		shared.cooldown = maxf(float(shared.cooldown), interval)
		shared.reload_max = maxf(float(shared.reload_max), interval)
	if state.ammo == 0 and state.reserve > 0:
		state.belt_reloading = true
		state.cooldown = float(definition.get("belt_reload", interval))
		state.reload_max = state.cooldown
	return definition.duplicate()


func resupply() -> void:
	# Supply replaces ammunition without clearing weapon/breech cooldowns.
	for index in _states.size():
		_states[index].ammo = int(WEAPONS[index].capacity)
		_states[index].reserve = int(WEAPONS[index].reserve)
		_states[index].belt_reloading = false


func needs_resupply() -> bool:
	for index in _states.size():
		if _states[index].ammo < int(WEAPONS[index].capacity) or _states[index].reserve < int(WEAPONS[index].reserve):
			return true
	return false


func snapshot() -> Dictionary:
	var slots: Array[Dictionary] = []
	for index in WEAPONS.size():
		var definition: Dictionary = WEAPONS[index]
		var state: Dictionary = _states[index]
		slots.append({"id": definition.id, "name": definition.name, "index": index, "ammo": state.ammo, "reserve": state.reserve, "capacity": definition.capacity, "reload": state.cooldown, "reload_max": state.reload_max, "selected": selected == index, "belt_reloading": state.belt_reloading})
	var result: Dictionary = slots[selected].duplicate()
	result.slots = slots
	return result
