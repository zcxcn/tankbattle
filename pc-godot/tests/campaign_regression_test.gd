extends Node
## Real game-state and actor transitions; this suite owns its own test-save directory.

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


func _freeze_actors() -> void:
	game.set_process(false)
	for tank in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)


func _gate_is_open() -> bool:
	for bar: MeshInstance3D in game.arena.boss_gate:
		if bar.visible:
			return false
		for child in bar.get_children():
			if child is StaticBody3D and child.collision_layer != 0:
				return false
	return true


func _destroy(tank: Node) -> void:
	tank.receive_damage(100000.0, 0 if not tank.is_player else 1, tank.global_position + Vector3.FORWARD * 10)


func _check_win(index: int, lifetime_before: int) -> void:
	var defeated_boss: Node = game.boss
	_destroy(defeated_boss)
	_check(game.mode == "won" and index in SaveService.profile.completed_missions, "chapter %d boss destruction completes and persists the mission" % (index + 1))
	_check(int(SaveService.profile.lifetime_kills) == lifetime_before + 1, "chapter %d boss is credited exactly once" % (index + 1))
	_check(game.unlocked_mission_count() == mini(3, index + 2), "chapter %d unlocks only its following chapter" % (index + 1))
	var score_at_win: int = game.score
	var profile_at_win := SaveService.profile.duplicate(true)
	game._on_tank_destroyed(defeated_boss, 0)
	game._on_tank_destroyed(game.player, 1)
	game._settle_abandoned_run()
	_check(game.mode == "won" and game.score == score_at_win and SaveService.profile == profile_at_win, "chapter %d ignores duplicate terminal signals and repeated settlement" % (index + 1))
	_check(not SaveService.settle_run(game.current_run_id, true, game.score, index), "chapter %d refuses a second run reward" % (index + 1))


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Campaign regression tests require -- --test")
		get_tree().quit(2)
		return
	# Other suites can run concurrently without deleting or settling their profiles.
	SaveService._directory = "user://tests/campaign_regression"
	SaveService.reset_for_tests()
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		push_error("Campaign regression suite timed out")
		get_tree().quit(2)
	)
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	_freeze_actors()
	_check(game.unlocked_mission_count() == 1 and game.selected_mission == 0, "fresh campaign exposes only chapter one")
	game.cycle_mission()
	_check(game.selected_mission == 0, "mission selection cannot cycle into locked chapters")
	game.start_game()
	_freeze_actors()
	var first_run: String = game.current_run_id
	game.next_mission()
	_check(game.current_run_id == first_run and game.mission_index == 0, "next chapter cannot skip an unfinished mission")
	_check(game.mode == "playing" and game.enemies.size() == 7 and not game.boss.active and not _gate_is_open(), "chapter one starts six patrols with a dormant protected boss")
	var boss_health: float = game.boss.hp
	game.boss.receive_damage(100000.0, 0, game.boss.position)
	_check(game.boss.hp == boss_health and game.mode == "playing", "an inactive boss cannot be destroyed to bypass the mission objective")
	_destroy(game.player)
	_check(game.mode == "lost" and game.unlocked_mission_count() == 1 and SaveService.profile.completed_missions.is_empty() and SaveService.profile.upgrade_points == 0, "player defeat settles failure without unlocking or awarding a chapter")
	game.next_mission()
	game._on_tank_destroyed(game.boss, 0)
	_check(game.mode == "lost" and game.current_run_id == first_run and SaveService.profile.completed_missions.is_empty(), "a late boss signal or next request cannot replace defeat")
	game.retry_game()
	_freeze_actors()
	_check(game.mode == "playing" and game.current_run_id != first_run and game.mission_index == 0 and game.mission_kills == 0, "retry begins a fresh run in the same chapter")

	var supply_at: Vector3 = game._supply_points[0].position
	game.player.global_position = supply_at
	game._update_supplies()
	_check(not game._supply_points[0].used, "driving through a supply site at full strength preserves it")
	game.player.hp -= 100.0
	game.player.mine_ammo = 1
	game.player._loadout.select(3)
	game.player._loadout.fire()
	var injured_health: float = game.player.hp
	var reload_before: float = game.player._loadout.snapshot().reload
	game._update_supplies()
	_check(game._supply_points[0].used and is_equal_approx(game.player.hp, injured_health + 85.0) and game.player.mine_ammo == 6 and not game.player.needs_resupply(), "supply restores 85 armour, mines and weapon ammunition")
	_check(game.player._loadout.snapshot().reload >= reload_before, "supply does not bypass a weapon's firing cooldown")
	game.player.hp -= 40.0
	game.player.mine_ammo = 2
	var health_after_revisit: float = game.player.hp
	game._update_supplies()
	_check(game.player.hp == health_after_revisit and game.player.mine_ammo == 2, "a consumed supply site cannot be harvested a second time")
	_check(game.get_ui_snapshot().supply_positions.size() == 2, "consumed supply sites disappear from the radar snapshot")
	game.player.global_position = game.mission_data.player_start
	var patrols: Array = game.enemies.duplicate()
	for index in range(5):
		_destroy(patrols[index])
	_check(game.mission_kills == 5 and not game.boss.active and not _gate_is_open(), "five regular kills leave the sixth patrol and boss objective unfinished")
	_destroy(patrols[5])
	_check(game.mission_kills == 6 and game.objective_complete and game.boss.active and _gate_is_open(), "six actual patrol destructions activate the boss and remove gate collision")
	_check(game.player.hp >= game.player.max_hp * 0.75 and not game.player.needs_resupply(), "boss transition grants the advertised one-time repair and resupply")
	game.player.hp = 40.0
	game.player.mine_ammo = 1
	game._update_encounters(60.0)
	_check(game.player.hp == 40.0 and game.player.mine_ammo == 1, "an active boss cannot repeatedly grant transition supplies")
	_check_win(0, int(SaveService.profile.lifetime_kills))
	_check(SaveService.profile.upgrade_points == 2, "first completion grants exactly two upgrade points")
	game.next_mission()
	_freeze_actors()
	_check(game.mode == "playing" and game.mission_index == 1 and game.enemies.size() == 9 and game.mission_data.objective_type == "capture", "next mission loads the harbor capture scenario and eight patrols")
	_check(game._supply_points.size() == 3 and game.mission_kills == 0 and not game.boss.active, "new chapter replaces supplies and resets encounter progress")

	var capture_at: Vector3 = game.mission_data.objective_position
	game.player.global_position = capture_at
	game._update_encounters(30.0)
	_check(game.objective_progress == 0.0 and not game.boss.active and "争夺" in game.objective, "an enemy inside the capture perimeter blocks capture progress")
	for enemy in game.enemies:
		if enemy != game.boss and enemy.global_position.distance_to(capture_at) < 25.0:
			enemy.global_position = Vector3(-96, 0.05, 144)
	game.player.global_position = capture_at + Vector3(0, 0, 14)
	game._update_encounters(30.0)
	_check(game.objective_progress == 0.0, "capture does not advance outside the marked zone")
	game.player.global_position = capture_at
	game._update_encounters(6.0)
	_check(is_equal_approx(game.objective_progress, 6.0) and not game.boss.active, "half the required uncontested hold time advances only half the capture")
	game.pause_game()
	game._process(30.0)
	_check(is_equal_approx(game.objective_progress, 6.0) and game.mode == "paused", "pausing freezes capture time")
	game.resume_game()
	game.player.global_position = capture_at + Vector3(0, 0, 14)
	game._update_encounters(30.0)
	_check(is_equal_approx(game.objective_progress, 6.0), "leaving the zone holds accumulated capture progress")
	game.player.global_position = capture_at
	game._update_encounters(6.0)
	_check(game.objective_complete and game.boss.active and _gate_is_open() and game.mission_kills == 0, "full uncontested capture unlocks the boss without requiring every patrol kill")
	_check_win(1, int(SaveService.profile.lifetime_kills))
	_check(SaveService.profile.upgrade_points == 4, "second distinct mission awards only its own two points")
	game.next_mission()
	_freeze_actors()
	_check(game.mode == "playing" and game.mission_index == 2 and game.enemies.size() == 11 and game.mission_data.objective_type == "demolition", "next mission loads the fortress demolition scenario and ten patrols")
	var fuel: Node = game.mission_target
	_check(is_instance_valid(fuel) and fuel.hp == 320.0 and fuel.collision_layer == 1, "demolition creates a damageable solid fuel-depot objective")
	fuel.receive_damage(320.0, 1, fuel.position)
	_check(fuel.hp == 320.0 and not fuel.destroyed, "enemy fire cannot accidentally complete the player's demolition objective")
	game.pause_game()
	fuel.receive_damage(320.0, 0, fuel.position)
	_check(fuel.hp == 320.0, "paused gameplay cannot damage the mission target")
	game.resume_game()
	fuel.receive_damage(160.0, 0, fuel.position)
	game._update_encounters(0.0)
	_check(fuel.hp == 160.0 and not game.objective_complete and not game.boss.active, "partial target damage cannot activate the fortress boss")
	fuel.receive_damage(160.0, 0, fuel.position)
	game._update_encounters(0.0)
	_check(fuel.destroyed and fuel.collision_layer == 0 and not fuel.visible and game.objective_complete and game.boss.active and _gate_is_open(), "destroying the depot removes its obstruction and activates the final boss")
	_check_win(2, int(SaveService.profile.lifetime_kills))
	_check(SaveService.profile.completed_missions == [0, 1, 2] and SaveService.profile.upgrade_points == 6, "campaign persists each chapter once with six total upgrade points")
	var final_run: String = game.current_run_id
	game.next_mission()
	_check(game.mode == "won" and game.current_run_id == final_run and game.mission_index == 2 and not game.get_ui_snapshot().has_next_mission, "final victory does not create a nonexistent fourth chapter")
	game.return_to_menu()
	game.selected_mission = 0
	game.start_game()
	_freeze_actors()
	for enemy in game.enemies.duplicate():
		if enemy != game.boss:
			_destroy(enemy)
	_destroy(game.boss)
	_check(game.mode == "won" and SaveService.profile.upgrade_points == 6 and SaveService.profile.completed_missions == [0, 1, 2], "replaying a completed chapter never duplicates unlock rewards")
	game.free()
	await get_tree().process_frame
	print("CAMPAIGN_REGRESSION_RESULT: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
