class_name EndlessUpgrades
extends RefCounted
## A single defense run owns its salvage and upgrades; no campaign credits.

const MAX_SCRAP := 1000000000
const DEFINITIONS := [
	{"id": "firepower", "name": "弹头强化", "description": "全部武器伤害 +20%", "max_level": 8, "costs": [60, 100, 150, 230, 350, 530, 800, 1200]},
	{"id": "autoloader", "name": "自动装填", "description": "射击间隔和换弹耗时减少 8%", "max_level": 6, "costs": [80, 130, 200, 310, 470, 700]},
	{"id": "fortification", "name": "基地加固", "description": "基地最大耐久 +150，修复 150", "max_level": 6, "costs": [70, 110, 170, 260, 390, 590]},
	{"id": "repair", "name": "战地维修", "description": "坦克恢复 140，基地恢复 240", "max_level": -1, "costs": [75]},
	{"id": "ammo", "name": "弹药补给", "description": "补满全部武器弹药和地雷", "max_level": -1, "costs": [60]},
]

var scrap := 0
var levels: Dictionary = {"firepower": 0, "autoloader": 0, "fortification": 0}


func add_reward(amount: int) -> void:
	# Clamp before adding so even a malformed reward cannot overflow the bank.
	scrap = mini(MAX_SCRAP, clampi(scrap, 0, MAX_SCRAP) + clampi(amount, 0, MAX_SCRAP))


func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in DEFINITIONS:
		var level := int(levels.get(definition.id, 0))
		var maximum := int(definition.max_level)
		var complete := maximum > 0 and level >= maximum
		var cost := 0 if complete else int(definition.costs[clampi(level, 0, definition.costs.size() - 1)])
		result.append({"id": definition.id, "name": definition.name, "description": definition.description, "level": level, "max_level": maximum, "cost": cost, "available": not complete and scrap >= cost})
	return result


func can_purchase(id: String) -> bool:
	for item: Dictionary in catalog():
		if item.id == id:
			return bool(item.available)
	return false


func purchase(id: String) -> Dictionary:
	for item: Dictionary in catalog():
		if item.id != id or not bool(item.available):
			continue
		scrap -= int(item.cost)
		if int(item.max_level) > 0:
			levels[id] = int(item.level) + 1
		var effect := {"id": id, "cost": int(item.cost), "level": int(levels.get(id, 0)), "scrap": scrap, "damage_level": int(levels.firepower), "reload_level": int(levels.autoloader)}
		match id:
			"fortification":
				effect.base_max_hp = 150.0
				effect.base_heal = 150.0
			"repair":
				effect.player_heal = 140.0
				effect.base_heal = 240.0
			"ammo":
				effect.resupply = true
		return effect
	return {}
