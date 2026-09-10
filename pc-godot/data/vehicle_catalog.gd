class_name VehicleCatalog
extends RefCounted
## Authored, licensed hulls reused as distinct playable and enemy combat roles.

const PLAYER_VEHICLES := [
	{"id": "scout", "name": "游骑 · KF51", "model": "kf51", "description": "轻装侦察：更快转向与机动，装甲较薄", "hp": 200.0, "armor": 0.05, "speed": 9.0, "acceleration": 10.5, "turn_speed": 1.12, "turret_speed": 1.5, "damage": 56.0, "interval": 2.8},
	{"id": "line", "name": "灰狼 · Challenger 2", "model": "challenger2", "description": "均衡主战：火力、装甲与机动均衡", "hp": 260.0, "armor": 0.12, "speed": 8.0, "acceleration": 10.0, "turn_speed": 1.05, "turret_speed": 1.35, "damage": 62.0, "interval": 2.9},
	{"id": "heavy", "name": "磐石 · KV-2", "model": "kv2", "description": "重装突击：高装甲与重炮，行进及转向较慢", "hp": 340.0, "armor": 0.24, "speed": 6.0, "acceleration": 7.2, "turn_speed": 0.76, "turret_speed": 1.0, "damage": 78.0, "interval": 3.6},
]

const ENEMY_ROLES := {
	"escort": {"name": "铁卫巡护车", "model": "kf51", "hp": 112.0, "armor": 0.06, "speed": 5.8, "interval": 5.4, "damage": 20.0, "acquire": 1.3, "vision": 44.0, "fov": 115.0, "ideal": 27.0, "weapon": "cannon"},
	"assault": {"name": "猎隼突击车", "model": "kf51", "hp": 128.0, "armor": 0.08, "speed": 6.8, "interval": 0.40, "damage": 6.5, "acquire": 1.0, "vision": 43.0, "fov": 110.0, "ideal": 23.0, "weapon": "machine_gun"},
	"artillery": {"name": "雷鸣榴弹车", "model": "kv2", "hp": 150.0, "armor": 0.10, "speed": 3.8, "interval": 7.0, "damage": 38.0, "acquire": 1.8, "vision": 72.0, "fov": 90.0, "ideal": 52.0, "weapon": "he"},
	"repair": {"name": "铁砧抢修车", "model": "challenger2", "hp": 130.0, "armor": 0.08, "speed": 4.6, "interval": 6.2, "damage": 14.0, "acquire": 1.6, "vision": 40.0, "fov": 110.0, "ideal": 36.0, "weapon": "cannon"},
	"destroyer": {"name": "破城重型歼击车", "model": "challenger2", "hp": 220.0, "armor": 0.22, "speed": 3.9, "interval": 6.8, "damage": 48.0, "acquire": 1.9, "vision": 65.0, "fov": 85.0, "ideal": 46.0, "weapon": "cannon"},
	"scout": {"name": "游骑侦察车", "model": "kf51", "hp": 86.0, "armor": 0.05, "speed": 7.2, "interval": 4.2, "damage": 18.0, "acquire": 1.1, "vision": 50.0, "fov": 115.0, "ideal": 24.0, "weapon": "cannon"},
	"line": {"name": "灰烬线列车", "model": "challenger2", "hp": 125.0, "armor": 0.08, "speed": 5.6, "interval": 4.8, "damage": 24.0, "acquire": 1.25, "vision": 48.0, "fov": 105.0, "ideal": 30.0, "weapon": "cannon"},
	"heavy": {"name": "磐石重装车", "model": "kv2", "hp": 185.0, "armor": 0.18, "speed": 4.2, "interval": 5.8, "damage": 38.0, "acquire": 1.45, "vision": 46.0, "fov": 100.0, "ideal": 30.0, "weapon": "he"},
	"sniper": {"name": "长枪猎歼车", "model": "challenger2", "hp": 105.0, "armor": 0.06, "speed": 4.8, "interval": 6.0, "damage": 44.0, "acquire": 1.6, "vision": 67.0, "fov": 80.0, "ideal": 43.0, "weapon": "cannon"},
	"gunner": {"name": "蜂群机枪车", "model": "kf51", "hp": 100.0, "armor": 0.05, "speed": 6.4, "interval": 0.22, "damage": 2.8, "acquire": 0.85, "vision": 42.0, "fov": 110.0, "ideal": 23.0, "weapon": "machine_gun"},
	"rocket": {"name": "火雨导弹车", "model": "kf51", "hp": 115.0, "armor": 0.06, "speed": 4.8, "interval": 6.8, "damage": 32.0, "acquire": 1.55, "vision": 53.0, "fov": 95.0, "ideal": 35.0, "weapon": "rocket"},
}


static func player_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for vehicle: Dictionary in PLAYER_VEHICLES:
		result.append(vehicle.duplicate())
	return result


static func player_vehicle(id: String) -> Dictionary:
	for vehicle: Dictionary in PLAYER_VEHICLES:
		if vehicle.id == id:
			return vehicle.duplicate()
	return PLAYER_VEHICLES[1].duplicate()


static func enemy_role(id: String) -> Dictionary:
	return (ENEMY_ROLES.get(id, ENEMY_ROLES.line) as Dictionary).duplicate()
