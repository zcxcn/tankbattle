extends SceneTree
## Validates random deployment, route clearance and meaningful specialist behavior.

var passed := 0
var failed := 0
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func clear_at(at: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.6, 1.8, 6.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform.origin = at + Vector3.UP * 1.4
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	root.get_node("SaveService").set("_directory", "user://tests/deployment_040")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	for chapter in 6:
		game.selected_mission = chapter
		game.set_meta("deployment_seed", 40910 + chapter)
		game.start_game()
		for tank in get_nodes_in_group("tanks"):
			tank.set_physics_process(false)
		await frames(2)
		var mission: Dictionary = game.mission_data
		var candidates: Array[Vector3] = game.arena.get_spawn_candidates()
		check(candidates.size() >= 70, "chapter %d provides broad drivable spawn coverage" % chapter)
		var a := BattleDeployment.build(mission, candidates, 171)
		var b := BattleDeployment.build(mission, candidates, 172)
		check(a.size() == int(mission.enemy_count) and b.size() == a.size(), "chapter %d fits its complete roster across seeds" % chapter)
		check(a == BattleDeployment.build(mission, candidates, 171) and a != b, "chapter %d seed reproduces a layout while new runs vary" % chapter)
		var safe := true
		var routes_clear := true
		var spread: Dictionary = {}
		for layout in [a, b]:
			for unit: Dictionary in layout:
				safe = safe and clear_at(unit.position) and unit.position.distance_to(mission.player_start) >= 54.0
				spread[int((unit.position.x + 144) / 96)] = true
				var points: Array[Vector3] = [unit.position]
				points.append_array(unit.patrol)
				points.append(unit.patrol[0])
				for index in range(1, points.size()):
					var steps := maxi(1, ceili(points[index - 1].distance_to(points[index]) / 4.0))
					for step in steps + 1:
						routes_clear = routes_clear and clear_at(points[index - 1].lerp(points[index], float(step) / steps))
		check(safe, "chapter %d spawns clear of walls, gates and player deployment" % chapter)
		check(routes_clear, "chapter %d random patrol segments fit a 6.6m vehicle envelope" % chapter)
		check(spread.size() >= 2, "chapter %d distributes contacts across the map" % chapter)
		check(game.enemies.size() == int(mission.enemy_count) + 1 and not game.boss.active, "chapter %d actual scene deploys patrols plus a protected boss" % chapter)
	check(VehicleCatalog.ENEMY_ROLES.size() == 11, "eleven enemy combat roles are available")
	var repair = game._spawn_tank("RepairFixture", Vector3(0, 0.05, 110), 1, false, false, "repair")
	var ally = game._spawn_tank("AllyFixture", Vector3(0, 0.05, 99), 1, false, false, "line")
	repair.set_physics_process(false)
	ally.set_physics_process(false)
	ally.hp -= 30.0
	await frames(2)
	var before: float = ally.hp
	repair._repair_allies(1.0)
	check(ally.hp > before and repair._repair_reserve < 120.0, "repair specialist spends limited stores restoring a visible damaged ally")
	repair._repair_reserve = 0.0
	before = ally.hp
	repair._repair_allies(5.0)
	check(ally.hp == before, "exhausted repair stores cannot create infinite regeneration")
	var mines = game._spawn_tank("MineLayerFixture", Vector3(96, 0.05, 72), 1, false, false, "minelayer")
	mines.set_physics_process(false)
	check(mines.mine_ammo == 12 and mines.find_child("ReserveMine", true, false) != null, "minelayer carries twelve mines and a visible mine rack")
	check(mines.try_place_mine() and mines.mine_ammo == 11, "minelayer deploys a real finite-inventory mine")
	var audio_service := root.get_node("AudioService")
	var settings := root.get_node("SettingsService")
	var track_before: int = audio_service.get_music_snapshot().index
	var key := InputEventKey.new()
	key.physical_keycode = KEY_N
	key.pressed = true
	game._unhandled_input(key)
	check(audio_service.get_music_snapshot().index == (track_before + 1) % 3 and settings.music_track == audio_service.get_music_snapshot().index, "N input switches the real playlist and saves its selected track")
	game._on_setting_requested("music_track")
	check(audio_service.get_music_snapshot().index == (track_before + 2) % 3, "settings music selector controls the same playlist")
	for property in ["master_volume", "music_volume", "effects_volume", "radio_volume"]:
		settings.set(property, 85)
		for tick in 3:
			game._on_setting_requested(property)
		check(settings.get(property) == 0, "%s can reach mute from a non-round default without exceeding 100%%" % property)
	settings.load_settings()
	check(settings.music_track == (track_before + 2) % 3 and settings.radio_volume == 0, "selected music and radio volume survive a config reload")
	game.free()
	await frames(2)
	print("DEPLOYMENT_EXPANSION_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)
