class_name MissionCatalog
extends RefCounted
## Campaign definitions in world metres. Routes follow authored, unobstructed roads.

const ARENA_BOUNDS := Rect2(-144.0, -192.0, 288.0, 384.0)


static func count() -> int:
	return 3


static func get_mission(index: int) -> Dictionary:
	var chapter := clampi(index, 0, count() - 1)
	var mission := {
		"id": ["industrial_outskirts", "supply_harbor", "command_fortress"][chapter],
		"name": ["工业外围", "补给港区", "指挥堡垒"][chapter],
		"briefing": [
			"沿主干道进入工业区，清除六支巡逻队，再摧毁铁牙指挥车。利用街区掩体逐队接敌。",
			"深入港区，占领东侧补给中继站，再击败港区守卫。遭遇机枪车时保持距离，导弹来袭时利用仓库掩护。",
			"突入堡垒，摧毁西侧燃料库，最后击败堡垒指挥官。重装巡逻队、火箭车与机枪车交错守卫。",
		][chapter],
		"player_start": Vector3(0, 0.05, 174),
		"boss_position": Vector3(0, 0.05, -174),
		"boss_name": ["铁牙 · 围城指挥车", "海狼 · 港区守卫", "暴君 · 堡垒指挥官"][chapter],
		"objective_type": ["clear", "capture", "demolition"][chapter],
		"objective_position": [Vector3(0, 0.05, -138), Vector3(96, 0.05, -108), Vector3(-96, 0.05, -108)][chapter],
		"objective_radius": 10.0,
		"objective_seconds": 12.0 if chapter == 1 else 0.0,
		"supply_positions": [Vector3(24, 0.05, 144), Vector3(-24, 0.05, 0), Vector3(24, 0.05, -144)],
		"enemy_layout": [],
	}
	var enemies: Array[Dictionary] = []
	enemies.append(_patrol(Vector3(0, 0.05, 120), "scout", [Vector3(0, 0.05, 110), Vector3(0, 0.05, 132)]))
	enemies.append(_patrol(Vector3(-96, 0.05, 96), "line", [Vector3(-96, 0.05, 114), Vector3(-96, 0.05, 72), Vector3(-48, 0.05, 72), Vector3(-96, 0.05, 72)]))
	enemies.append(_patrol(Vector3(96, 0.05, 48), "gunner" if chapter > 0 else "scout", [Vector3(96, 0.05, 30), Vector3(96, 0.05, 72), Vector3(48, 0.05, 72), Vector3(96, 0.05, 72)]))
	enemies.append(_patrol(Vector3(-96, 0.05, -20), "heavy", [Vector3(-96, 0.05, -38), Vector3(-96, 0.05, 0), Vector3(-48, 0.05, 0), Vector3(-96, 0.05, 0)]))
	enemies.append(_patrol(Vector3(0, 0.05, -84), "sniper", [Vector3(0, 0.05, -68), Vector3(0, 0.05, -102)]))
	enemies.append(_patrol(Vector3(96, 0.05, -124), "heavy", [Vector3(96, 0.05, -124), Vector3(96, 0.05, -144), Vector3(48, 0.05, -144), Vector3(96, 0.05, -144)]))
	if chapter >= 1:
		enemies.append(_patrol(Vector3(0, 0.05, 28), "rocket", [Vector3(0, 0.05, 40), Vector3(0, 0.05, 14)]))
		enemies.append(_patrol(Vector3(-96, 0.05, -132), "line", [Vector3(-96, 0.05, -124), Vector3(-96, 0.05, -152)]))
	if chapter >= 2:
		enemies.append(_patrol(Vector3(96, 0.05, -30), "gunner", [Vector3(96, 0.05, -12), Vector3(96, 0.05, -54)]))
		enemies.append(_patrol(Vector3(-48, 0.05, -72), "rocket", [Vector3(-68, 0.05, -72), Vector3(-28, 0.05, -72)]))
	mission["enemy_layout"] = enemies
	return mission


static func _patrol(position: Vector3, kind: String, route: Array) -> Dictionary:
	var patrol: Array[Vector3] = []
	for point: Vector3 in route:
		patrol.append(point)
	return {"position": position, "kind": kind, "patrol": patrol}
