extends SceneTree
## Reproducible input-driven playthrough. Uses real TankActor/Jolt/projectiles,
## ordinary HP/damage and test saves. Not a human playthrough or a forced win.
## --headless --fixed-fps 60 --path pc-godot --script res://tests/pacing_playtest.gd -- --test --label=current
## Optional --output-dir=<absolute-directory> chooses the JSON destination.

var game: Node3D
var elapsed := 0.0
var recording := false
var shots: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var results: Array[Dictionary] = []
var output_label := "current"
var output_directory := ""
var current_scenario := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Pacing playtest requires -- --test so player saves stay untouched")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			output_label = argument.trim_prefix("--label=").validate_filename()
		elif argument.begins_with("--output-dir="):
			output_directory = argument.trim_prefix("--output-dir=")
	root.get_node("SaveService").reset_for_tests()
	for scenario in ["opening_hold", "street_maneuver", "boss_encounter"]:
		await _scenario(scenario, 30.0 if scenario == "opening_hold" else 90.0)
	if results.size() != 3:
		push_error("The playtest did not complete all three scenarios")
		quit(2)
		return
	var directory := output_directory
	if directory.is_empty():
		var script_path: String = get_script().resource_path
		if script_path.begins_with("res://"):
			directory = ProjectSettings.globalize_path("res://../work/asset-review/pacing-results")
		else:
			# An absolute external script also works with an archived --main-pack.
			directory = script_path.get_base_dir().path_join("../../work/asset-review/pacing-results").simplify_path()
	DirAccess.make_dir_recursive_absolute(directory)
	var document := {
		"label": output_label,
		"method": "Real 60 Hz Godot/Jolt scene; input actions steer, aim, fire and EMP; default HP and damage; no forced damage or wins. Boss fixture starts a full-health boss encounter at legal arena coordinates. This is a deterministic automated playtest, not human input.",
		"results": results,
	}
	var output := FileAccess.open(directory.path_join(output_label + ".json"), FileAccess.WRITE)
	if output == null:
		push_error("Could not write playtest result")
		quit(2)
		return
	output.store_string(JSON.stringify(document, "\t"))
	print("PACING_PLAYTEST_COMPLETE: " + directory.path_join(output_label + ".json"))
	quit(0)


func _scenario(scenario: String, duration: float) -> void:
	_release_inputs()
	current_scenario = scenario
	elapsed = 0.0
	shots.clear()
	samples.clear()
	seed(260908)
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.start_game()
	game.child_entered_tree.connect(_on_child_entered)
	# Keeping this signal connected is representative in the rendered game. A
	# headless focus event cannot represent a player leaving a real game window.
	if game.get_window().focus_exited.is_connected(game._on_focus_lost):
		game.get_window().focus_exited.disconnect(game._on_focus_lost)
	if scenario == "boss_encounter":
		for enemy in game.enemies.duplicate():
			if enemy != game.boss:
				game.enemies.erase(enemy)
				enemy.free()
		game.mission_kills = game.target_kills
		game._activate_boss()
		game.player.global_position = Vector3(0, 0.05, -10)
		game.player.velocity = Vector3.ZERO
		game.boss.global_position = Vector3(0, 0.05, -39)
		game.boss.velocity = Vector3.ZERO
	await physics_frame
	await process_frame
	var initial_hp: float = game.player.hp
	var last_hp := initial_hp
	var damage_taken := 0.0
	var healing := 0.0
	var first_damage_time := -1.0
	var max_speed := 0.0
	var distance_driven := 0.0
	var previous_position: Vector3 = game.player.global_position
	var maximum_active_enemies := 0
	var last_sample := -1
	recording = true
	for frame in roundi(duration * 60.0):
		elapsed = float(frame) / 60.0
		if game.mode != "playing":
			break
		if scenario != "opening_hold":
			_drive_tactics(scenario)
		await physics_frame
		var hp_now: float = game.player.hp
		if hp_now < last_hp:
			damage_taken += last_hp - hp_now
			if first_damage_time < 0.0:
				first_damage_time = elapsed
		elif hp_now > last_hp:
			healing += hp_now - last_hp
		last_hp = hp_now
		var position_now: Vector3 = game.player.global_position
		distance_driven += Vector2(position_now.x - previous_position.x, position_now.z - previous_position.z).length()
		previous_position = position_now
		max_speed = maxf(max_speed, Vector2(game.player.velocity.x, game.player.velocity.z).length())
		var active_count := 0
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.is_targetable() and (not game.has_method("can_enemy_engage") or game.can_enemy_engage(enemy)):
				active_count += 1
		maximum_active_enemies = maxi(maximum_active_enemies, active_count)
		if floori(elapsed / 5.0) != last_sample:
			last_sample = floori(elapsed / 5.0)
			samples.append({"t": snappedf(elapsed, 0.01), "hp": snappedf(hp_now, 0.01), "kills": game.total_run_kills, "position": [snappedf(position_now.x, 0.01), snappedf(position_now.z, 0.01)], "active_enemies": active_count})
	recording = false
	_release_inputs()
	var player_shots := 0
	var enemy_shots := 0
	var cannon_times: Array[float] = []
	var first_enemy_shot := -1.0
	for shot: Dictionary in shots:
		if shot.team == 0:
			player_shots += 1
		else:
			enemy_shots += 1
			if first_enemy_shot < 0.0:
				first_enemy_shot = float(shot.t)
			if shot.kind == "cannon":
				cannon_times.append(float(shot.t))
	var max_cannons_in_second := 0
	for start_time: float in cannon_times:
		var count := 0
		for other_time: float in cannon_times:
			if other_time >= start_time and other_time < start_time + 1.0:
				count += 1
		max_cannons_in_second = maxi(max_cannons_in_second, count)
	var result := {
		"scenario": scenario, "seconds": snappedf(elapsed + 1.0 / 60.0, 0.01), "outcome": game.mode,
		"initial_hp": initial_hp, "remaining_hp": snappedf(game.player.hp, 0.01),
		"damage_taken": snappedf(damage_taken, 0.01), "healing_received": snappedf(healing, 0.01),
		"first_damage_seconds": snappedf(first_damage_time, 0.01), "first_enemy_shot_seconds": snappedf(first_enemy_shot, 0.01),
		"kills": game.total_run_kills, "player_shots": player_shots, "enemy_projectiles": enemy_shots,
		"max_enemy_cannons_in_one_second": max_cannons_in_second, "max_active_enemies": maximum_active_enemies,
		"max_player_speed": snappedf(max_speed, 0.01), "distance_driven_m": snappedf(distance_driven, 0.01),
		"boss_hp": snappedf(game.boss.hp, 0.01) if is_instance_valid(game.boss) else 0.0,
		"samples": samples.duplicate(true), "shots": shots.duplicate(true),
	}
	results.append(result)
	var summary := result.duplicate()
	summary.erase("shots")
	summary.erase("samples")
	print("PLAYTEST_SCENARIO: " + JSON.stringify(summary))
	game.free()
	await physics_frame
	await process_frame


func _drive_tactics(scenario: String) -> void:
	var player: Node3D = game.player
	var target: Node3D = null
	var nearest := INF
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		if game.has_method("can_enemy_engage") and not game.can_enemy_engage(enemy):
			continue
		var candidate: float = player.global_position.distance_to(enemy.global_position)
		if candidate < nearest:
			nearest = candidate
			target = enemy
	var movement := Vector2.ZERO
	if target != null:
		var displacement := target.global_position - player.global_position
		var flight: float = displacement.length() / player.projectile_speed
		var target_position: Vector3 = target.global_position + target.velocity * minf(flight, 0.8)
		var aim: Vector3 = target_position - player.global_position
		_set_axes("aim_left", "aim_right", "aim_up", "aim_down", Vector2(aim.x, aim.z).normalized())
		var forward: Vector3 = -player._turret.global_basis.z.normalized()
		var aligned := forward.dot((target_position - player._turret.global_position).normalized()) > 0.993
		_set_action("fire", aligned and game.has_line_of_sight(player._muzzle.global_position, target.global_position + Vector3.UP))
		if nearest > 33.0:
			movement = Vector2(displacement.x, displacement.z).normalized()
		elif nearest < 21.0:
			movement = -Vector2(displacement.x, displacement.z).normalized()
		else:
			# Alternate deliberate short moves with stationary aimed shots.
			var maneuver_clock := fmod(elapsed, 12.0)
			if maneuver_clock < 3.0 or target.boss_warning:
				var sign_x := 1.0 if floori(elapsed / 12.0) % 2 == 0 else -1.0
				movement = Vector2(sign_x, 0.0)
		if target.boss_warning:
			movement.x = -1.0 if player.global_position.x > 0.0 else 1.0
			if nearest < 27.0:
				_set_action("emp", true)
			else:
				_set_action("emp", false)
		else:
			_set_action("emp", false)
	else:
		movement = Vector2(0.0, -1.0)
		_set_action("fire", false)
		_set_action("emp", false)
	# Stay in the street while weaving; obey collision and acceleration.
	if player.global_position.x > 11.0:
		movement.x = minf(movement.x, -0.7)
	elif player.global_position.x < -11.0:
		movement.x = maxf(movement.x, 0.7)
	if scenario == "boss_encounter" and player.global_position.z < -52.0:
		movement.y = maxf(movement.y, 0.7)
	if player.global_position.z > 56.0:
		movement.y = minf(movement.y, -0.7)
	_set_axes("move_left", "move_right", "move_forward", "move_back", movement.normalized() if movement.length() > 1.0 else movement)


func _set_axes(left: String, right: String, up: String, down: String, value: Vector2) -> void:
	for item: Array in [[left, maxf(-value.x, 0.0)], [right, maxf(value.x, 0.0)], [up, maxf(-value.y, 0.0)], [down, maxf(value.y, 0.0)]]:
		if float(item[1]) > 0.01:
			Input.action_press(item[0], float(item[1]))
		else:
			Input.action_release(item[0])


func _set_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_inputs() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "aim_left", "aim_right", "aim_up", "aim_down", "fire", "emp", "dash", "place_mine"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func _on_child_entered(node: Node) -> void:
	if recording and node.is_in_group("projectiles"):
		shots.append({"t": snappedf(elapsed, 0.001), "team": node.team, "kind": node.weapon_kind, "owner": str(node.owner_tank.name) if is_instance_valid(node.owner_tank) else "unknown"})
