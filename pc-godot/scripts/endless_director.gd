extends Node
## Bounded, overlapping siege waves. Campaign progression is never credited here.

const Monster = preload("res://actors/giant_monster.gd")
const Upgrades = preload("res://data/endless_upgrades.gd")
const MAX_ALIVE := 18
const MAX_CORPSES := 8
const BASE_POSITION := Vector3(0, 0.05, 112)
const WAVE_SECONDS := 65.0
var game: Node3D
var upgrades: RefCounted = Upgrades.new()
var wave := 0
var kills := 0
var base_hp := 900.0
var base_max_hp := 900.0
var wave_clock := 8.0
var spawn_clock := 0.0
var pending := 0
var spawned := 0
var monsters: Array[Node3D] = []
var corpses: Array[Node3D] = []
var defeat_reason := ""
var _settled := false
var _rewarded: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _warning_clock := 0.0
var _elite_pending := 0

func _ready() -> void:
	name = "EndlessDirector"
	_rng.seed = int(game.get_meta("endless_seed", randi()))
	upgrades.add_reward(60)

func _physics_process(delta: float) -> void:
	if not game.is_combat_running():
		return
	wave_clock -= delta
	spawn_clock -= delta
	_warning_clock = maxf(0.0, _warning_clock - delta)
	monsters = monsters.filter(func(m: Node3D) -> bool: return is_instance_valid(m) and not m.destroyed)
	corpses = corpses.filter(func(m: Node3D) -> bool: return is_instance_valid(m))
	if wave_clock <= 0.0:
		begin_wave()
	if pending > 0 and spawn_clock <= 0.0 and monsters.size() < MAX_ALIVE:
		if spawn_monster() != null:
			spawn_clock = maxf(3.0, 7.0 - float(wave) * 0.22)
	game.objective = "无尽防守 · 第 %d 波 · 守住避难所" % maxi(1, wave)
	if not monsters.is_empty() and _warning_clock <= 0.0:
		for monster in monsters:
			if monster.global_position.z > 68.0:
				game.notify("巨怪已逼近防线 · 优先阻止最近的目标！", 3.0)
				AudioService.radio("enemy_spotted")
				_warning_clock = 22.0
				break

func begin_wave() -> void:
	wave += 1
	wave_clock = WAVE_SECONDS
	pending = mini(32, pending + mini(20, 5 + wave))
	if wave % 3 == 0:
		_elite_pending = mini(3, _elite_pending + 1)
	spawn_clock = 0.0
	game.notify("第 %d 波 · %s\nEsc / Start：升级火力、维修防线、购买弹药" % [wave, "巨型精英正在接近" if wave % 3 == 0 else "怪物正在穿过封锁区"], 5.0)
	AudioService.radio("boss_incoming" if wave % 3 == 0 else "mission_start")
	# A wave is an interval, not a requirement to kill the previous wave.
	# A stalled front remains bounded by MAX_ALIVE and the pending queue cap.

func spawn_monster() -> Node3D:
	if monsters.size() >= MAX_ALIVE or pending <= 0 or not game.is_combat_running():
		return null
	var lane := spawned % 3
	var chosen := Vector3.ZERO
	var found := false
	# Try all lanes: parking at one entrance must never freeze the whole siege.
	for attempt in 6:
		lane = (spawned + attempt) % 3
		var spawn_x: float = [-32.0, 0.0, 32.0][lane] + _rng.randf_range(-5.0, 5.0)
		var spawn_z := -96.0 - _rng.randf_range(0.0, 18.0) - float(attempt / 3) * 12.0
		if wave == 1 and spawned < 2:
			spawn_z = -42.0 - spawned * 12.0
		chosen = Vector3(spawn_x, 0.1, spawn_z)
		var occupied := false
		for other in monsters:
			if is_instance_valid(other) and other.global_position.distance_to(chosen) < 11.0:
				occupied = true
		if chosen.distance_to(game.player.global_position) >= 28.0 and not occupied:
			found = true
			break
	if not found:
		spawn_clock = 1.0
		return null
	var monster: Node3D = Monster.new()
	monster.name = "Giant_%04d" % spawned
	monster.game = game
	monster.director = self
	monster.wave = maxi(1, wave)
	monster.archetype = "titan" if _elite_pending > 0 else ("brute" if wave >= 2 and spawned % 4 == 3 else "shambler")
	if _elite_pending > 0:
		_elite_pending -= 1
	monster.position = chosen
	monster.set_meta("siege_lane", lane)
	game.add_child(monster)
	monsters.append(monster)
	spawned += 1
	pending -= 1
	return monster

func get_monster_goal(monster: Node3D) -> Vector3:
	# Broad parallel lanes prevent a single tank/body from blocking the entire horde.
	return Vector3(clampf(monster.global_position.x, -35.0, 35.0), 0.05, 116.0)

func monster_reached_base(monster: Node3D, damage: float) -> void:
	if not game.is_combat_running() or not is_instance_valid(monster) or monster.destroyed or monster not in monsters:
		return
	if monster.global_position.z < 96.0 or absf(monster.global_position.x) > 44.0 or not is_finite(damage) or damage <= 0.0:
		return
	base_hp = maxf(0.0, base_hp - damage)
	var at := Vector3(monster.global_position.x, 2.0, 118.8)
	game.spawn_impact(at, true, "stone", Vector3.FORWARD, "he")
	game.player.add_camera_shake(0.45)
	AudioService.play_3d("collision", at, -1.0, 0.65)
	if base_hp <= 0.0:
		finish("避难所防线失守")

func monster_killed(monster: Node3D, reward: int) -> void:
	if not game.is_combat_running() or not is_instance_valid(monster) or monster not in monsters:
		return
	var id := monster.get_instance_id()
	if _rewarded.has(id):
		return
	_rewarded[id] = true
	monsters.erase(monster)
	corpses.append(monster)
	while corpses.size() > MAX_CORPSES:
		var oldest: Node3D = corpses.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	# Only a bounded set of corpse IDs is needed, membership above prevents replay.
	if _rewarded.size() > 128:
		_rewarded.clear()
	kills += 1
	upgrades.add_reward(clampi(reward, 0, 1000))
	game.mission_kills = kills
	game.total_run_kills = kills
	game.score += maxi(0, reward) * 10
	game.notify("巨怪倒下 · 战利品 +%d · 当前 %d\nEsc / Start 打开升级" % [reward, upgrades.scrap], 2.5)
	AudioService.radio("enemy_destroyed")

func buy_upgrade(id: String) -> bool:
	if game.mode != "paused" or not is_instance_valid(game.player) or game.player.destroyed:
		return false
	if id == "repair" and base_hp >= base_max_hp and game.player.hp >= game.player.max_hp:
		game.notify("装甲和防线完好，无需维修", 2.0)
		return false
	if id == "ammo" and not game.player.needs_resupply():
		game.notify("当前弹药已满", 2.0)
		return false
	var effect: Dictionary = upgrades.purchase(id)
	if effect.is_empty():
		return false
	game.player._loadout.set_endless_upgrades(effect.damage_level, effect.reload_level)
	base_max_hp += float(effect.get("base_max_hp", 0.0))
	base_hp = minf(base_max_hp, base_hp + float(effect.get("base_heal", 0.0)))
	game.player.hp = minf(game.player.max_hp, game.player.hp + float(effect.get("player_heal", 0.0)))
	if effect.get("resupply", false):
		game.player.resupply()
	game.notify("整备完成 · 剩余战利品 %d" % upgrades.scrap, 2.0)
	AudioService.play_ui("click")
	return true

func finish(reason: String) -> void:
	if not game.is_combat_running():
		return
	defeat_reason = reason
	game.mode = "lost"
	game.objective = reason
	game.result_delay = 2.4
	game.sync_pointer_mode()
	AudioService.set_game_state("lost")
	AudioService.play_ui("defeat", -3.0)
	AudioService.radio("mission_failed")
	settle()

func settle() -> void:
	if _settled:
		return
	_settled = true
	SaveService.record_endless_result(wave, kills, game.play_time)

func snapshot() -> Dictionary:
	var offers: Array = upgrades.catalog()
	for offer: Dictionary in offers:
		if offer.id == "repair" and is_instance_valid(game.player) and base_hp >= base_max_hp and game.player.hp >= game.player.max_hp:
			offer.available = false
		if offer.id == "ammo" and is_instance_valid(game.player) and not game.player.needs_resupply():
			offer.available = false
	return {"wave": wave, "kills": kills, "scrap": upgrades.scrap, "base_hp": base_hp, "base_max_hp": base_max_hp,
		"alive": monsters.size(), "next_wave_in": maxf(0.0, wave_clock), "best_wave": SaveService.profile.get("endless_best_wave", 0),
		"best_kills": SaveService.profile.get("endless_best_kills", 0), "upgrades": offers, "defeat_reason": defeat_reason}
