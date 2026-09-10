extends SceneTree
## Runtime regressions for menu flow, swept mines, terminal settlement and cleanup.
## Run: godot --headless --path pc-godot --script res://tests/combat_regression_test.gd -- --test

var _passed := 0
var _failed := 0
var game: Node
var saves: Node


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		push_error("FAIL: " + label)


func _frames(count := 2) -> void:
	for _index in range(count):
		await physics_frame


func _freeze_tanks() -> void:
	for tank: Node in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)


func _escape() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	game._unhandled_input(event)


func _new_mine(at: Vector3) -> Node3D:
	game.spawn_mine(game.player, at)
	var mine := get_nodes_in_group("mines").back() as Node3D
	mine.set_physics_process(false)
	return mine


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Combat regression tests require -- --test")
		quit(2)
		return
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Combat regression test did not finish")
		quit(2)
	)
	saves = root.get_node("SaveService")
	saves.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	await _frames()
	game.open_settings()
	_escape()
	_check(game.mode == "title", "Escape returns title settings to the title")
	game.mode = "title"
	game.open_settings()
	game.return_to_menu()
	_check(game.mode == "title", "settings Back and Escape share the same return target")
	game.start_game()
	_freeze_tanks()
	await _frames()
	game.open_settings()
	_escape()
	_check(game.mode == "paused", "in-mission settings returns to pause without resuming combat")
	game.resume_game()
	_check(game.mode == "playing", "paused mission can resume after settings")

	var enemy := game.enemies[0] as Node3D
	enemy.global_position = Vector3(300.0, 0.05, 0.0)
	game.player.global_position = Vector3(320.0, 0.05, 0.0)
	var mine := _new_mine(Vector3(300.0, 0.02, 0.0))
	mine.armed_after = 0.0
	enemy.global_position.x = 292.0
	mine._physics_process(0.016)
	var health_before: float = enemy.hp
	enemy.global_position.x = 308.0
	mine._physics_process(0.016)
	_check(mine.is_queued_for_deletion(), "armed mine detects the swept crossing")
	_check(enemy.hp < health_before, "swept crossing applies damage at contact even beyond the final blast radius")
	await _frames()

	var arming_mine := _new_mine(Vector3(300.0, 0.02, 0.0))
	enemy.global_position.x = 292.0
	arming_mine._physics_process(0.001)
	arming_mine.armed_after = 0.08
	enemy.global_position.x = 316.0
	arming_mine._physics_process(0.10)
	_check(not arming_mine.is_queued_for_deletion(), "crossing before arming does not detonate retroactively in the same frame")
	if is_instance_valid(arming_mine):
		arming_mine.free()

	var paused_mine := _new_mine(Vector3(350.0, 0.02, 0.0))
	game.spawn_projectile(game.player, Vector3(350.0, 3.0, 0.0), Vector3.FORWARD, 20.0, 58.0, 0.0, "cannon")
	var shell := get_nodes_in_group("projectiles").back() as Node3D
	shell.set_physics_process(false)
	var old_arm: float = paused_mine.armed_after
	var old_life: float = shell.lifetime
	var old_position := shell.global_position
	game.pause_game()
	paused_mine._physics_process(4.0)
	shell._physics_process(4.0)
	_check(is_equal_approx(old_arm, paused_mine.armed_after), "pause preserves mine arming time")
	_check(is_equal_approx(old_life, shell.lifetime) and shell.global_position == old_position, "pause preserves shell lifetime and position")
	game.resume_game()
	var friendly := _new_mine(game.player.global_position + Vector3(5, 0, 0))
	game.spawn_mine(enemy, game.player.global_position + Vector3(7, 0, 0))
	var hostile := get_nodes_in_group("mines").back() as Node3D
	enemy.global_position = game.player.global_position + Vector3(8, 0, 0)
	health_before = enemy.hp
	game.emit_emp(game.player, 28.0)
	_check(friendly.is_queued_for_deletion() and hostile.is_queued_for_deletion(), "EMP defuses both factions inside its radius")
	_check(not paused_mine.is_queued_for_deletion(), "EMP preserves a mine outside its radius")
	friendly.explode()
	_check(is_equal_approx(enemy.hp, health_before), "EMP disposal cannot later explode or damage nearby armor")
	_check(enemy.stunned > 0.0, "EMP also stuns hostile armor inside its radius")

	game.score = 470
	game.retry_game()
	_freeze_tanks()
	_check(int(saves.profile.best_score) == 470, "retry settles the abandoned run score before starting a new run")
	game.mission_kills = game.target_kills
	game._activate_boss()
	game._on_boss_phase_changed(2)
	var guard := game.enemies.back() as Node3D
	var boss_objective: String = game.objective
	guard.receive_damage(10000.0, 0, guard.global_position)
	_check(game.objective == boss_objective and game.mission_kills == game.target_kills, "destroying a boss guard preserves the active boss objective and street kill count")
	var roster_before_lethal: int = game.enemies.size()
	game.score = 0
	game.boss.receive_damage(10000.0, 0, game.boss.global_position)
	_check(game.mode == "won" and game.score == 3400, "victory screen includes the boss score and completion bonus")
	_check(int(saves.profile.best_score) == game.score, "victory screen score matches the persisted result")
	_check(game.enemies.size() == roster_before_lethal, "lethal boss damage does not spawn phase reinforcements")
	game.open_settings()
	_escape()
	_check(game.mode == "won", "settings opened after victory returns to victory")
	game.player.receive_damage(10000.0, 1, game.player.global_position)
	_check(game.mode == "won", "late destruction cannot replace an already settled victory")
	game.retry_game()
	_freeze_tanks()
	game.player.receive_damage(10000.0, 1, game.player.global_position)
	game.boss.active = true
	game.boss.receive_damage(10000.0, 0, game.boss.global_position)
	_check(game.mode == "lost", "late boss destruction cannot replace an already settled defeat")
	game.open_settings()
	game.return_to_menu()
	_check(game.mode == "lost", "settings Back preserves the defeat screen")

	game.retry_game()
	_freeze_tanks()
	var cover := get_nodes_in_group("destructible_cover")[0] as Node3D
	cover.receive_damage(10000.0, 0, cover.global_position)
	var debris_count: int = game._cleanup.size()
	cover.receive_damage(10000.0, 0, cover.global_position)
	_check(game._cleanup.size() == debris_count, "same-frame repeat damage cannot destroy a cover twice")
	game.spawn_muzzle_flash(Vector3(300, 3, 0), Color.WHITE, 1.0)
	game.spawn_emp_visual(Vector3(300, 0, 0))
	var old_effects: Array[Node] = []
	for child: Node in game.get_children():
		if child == game.arena or child == game.ui or child.is_in_group("tanks"):
			continue
		old_effects.append(child)
	_check(old_effects.size() >= 8, "restart test includes explosion, debris, muzzle flash and EMP")
	game.retry_game()
	_freeze_tanks()
	var all_removed := true
	for effect in old_effects:
		all_removed = all_removed and not is_instance_valid(effect)
	_check(all_removed, "restart removes every prior combat visual and rigid fragment immediately")
	_check(game._cleanup.is_empty(), "restart resets cleanup references and timers")
	game.return_to_menu()
	_check(get_nodes_in_group("mines").is_empty() and get_nodes_in_group("projectiles").is_empty(), "return to menu clears mines and shells")
	print("COMBAT_REGRESSION_RESULT: %d passed, %d failed" % [_passed, _failed])
	game.free()
	await _frames()
	saves.reset_for_tests()
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if _failed == 0 else 1)
