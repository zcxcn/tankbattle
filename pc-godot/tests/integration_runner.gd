extends Node
## Runs the real scene graph and combat actors against an isolated test profile.

var passed := 0
var failed := 0
var game: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Integration tests require -- --test")
		get_tree().quit(2)
		return
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	await _frames(4)
	_check(game.mode == "title", "native project opens at the command menu")
	_check(is_instance_valid(game.player.camera), "title presentation uses the real tank and 3D camera")
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "default audio layout exposes independent music and effects buses")
	game.start_game()
	await _frames(5)
	_check(game.mode == "playing", "start action enters Chapter 01")
	_check(game.enemies.size() == 7, "mission creates six enemies and Iron Fang")
	var regular: Array = game.enemies.filter(func(tank: TankActor) -> bool: return not tank.is_boss)
	_check(regular.size() == 6 and not game.boss.active, "boss remains shielded behind the first objective")
	var clear_spawns := true
	for tank: TankActor in regular:
		for cover: Node in get_tree().get_nodes_in_group("destructible_cover"):
			var delta_xz := Vector2(tank.global_position.x - (cover as Node3D).global_position.x, tank.global_position.z - (cover as Node3D).global_position.z)
			if delta_xz.length() < 5.0:
				clear_spawns = false
	_check(clear_spawns, "regular enemies spawn clear of destructible cover")
	for tank: TankActor in game.enemies:
		tank.set_physics_process(false)
	game.player.set_physics_process(false)
	_check(game.player.try_place_mine(), "player can place a mine with finite inventory")
	var enemy: TankActor = regular[0]
	enemy.global_position = game.player.global_position + Vector3(7.0, 0.0, 0.0)
	await _frames(1)
	_check(enemy.try_place_mine(), "enemy uses the same physical mine system")
	await _frames(2)
	_check(get_tree().get_nodes_in_group("mines").size() == 2, "both faction mines exist in the world")
	var friendly_mine: TankMine
	for node: Node in get_tree().get_nodes_in_group("mines"):
		if node is TankMine and (node as TankMine).team == TankActor.TEAM_PLAYER:
			friendly_mine = node as TankMine
			break
	var mine_position := friendly_mine.global_position
	friendly_mine.armed_after = 0.0
	enemy.global_position = mine_position + Vector3(-8.0, 0.0, 0.0)
	await _frames(1)
	enemy.global_position = mine_position + Vector3(8.0, 0.0, 0.0)
	await _frames(2)
	_check(not is_instance_valid(friendly_mine), "runtime mine catches a tank crossing its trigger between physics frames")
	game.player.mine_cooldown = 0.0
	_check(game.player.try_place_mine(), "player can replenish the swept-trigger test mine")
	await _frames(2)
	game.player.emp_cooldown = 0.0
	_check(game.player.try_emp(), "player EMP activates through the tank ability")
	await _frames(2)
	_check(get_tree().get_nodes_in_group("mines").is_empty(), "EMP safely clears friendly and hostile mines")
	for tank: TankActor in regular:
		tank.active = true
		tank.receive_damage(10000.0, TankActor.TEAM_PLAYER, tank.global_position)
	await _frames(3)
	_check(game.mission_kills == 6, "six regular destructions satisfy the street objective")
	_check(game.boss.active and game.mode == "playing", "Iron Fang activates and blocks completion")
	game.boss.boss_warning = true
	game.boss._charge_clock = 1.0
	game.boss.apply_emp(1.0)
	_check(not game.boss.boss_warning and game.boss._charge_clock == 0.0, "EMP interrupts a telegraphed boss salvo")
	var phase_events: Array[int] = []
	game.boss.boss_phase_changed.connect(func(phase: int) -> void: phase_events.append(phase))
	game.boss.receive_damage(game.boss.max_hp * 0.90, TankActor.TEAM_PLAYER, game.boss.global_position)
	_check(game.boss.boss_phase == 3, "one heavy hit can cross both boss armor thresholds")
	_check(phase_events == [2, 3], "runtime boss emits the 70 and 35 percent phases once and in order")
	game.boss.receive_damage(10000.0, TankActor.TEAM_PLAYER, game.boss.global_position)
	await _frames(3)
	_check(game.mode == "won", "destroying Iron Fang completes the mission")
	_check(0 in SaveService.profile.completed_missions, "mission completion is persisted")
	_check(int(SaveService.profile.lifetime_kills) == 7, "confirmed kills persist exactly once")
	SaveService.profile["lifetime_kills"] = 23
	SaveService.save_now()
	SaveService.profile["lifetime_kills"] = 24
	SaveService.save_now()
	var corrupt_primary := FileAccess.open("user://tests/profile_0.json", FileAccess.WRITE)
	corrupt_primary.store_string("{}")
	corrupt_primary.close()
	SaveService.load_profile()
	_check(SaveService.recovered_from_backup and int(SaveService.profile.lifetime_kills) == 23, "invalid primary save recovers the last validated backup")
	print("INTEGRATION_RESULT: %d passed, %d failed" % [passed, failed])
	game.queue_free()
	await _frames(3)
	SaveService.reset_for_tests()
	get_tree().quit(0 if failed == 0 else 1)
