extends Node
## Tactical pacing invariants exercised against the real actors and physics.
## Run: godot --headless --path pc-godot res://tests/pacing_regression_test.tscn -- --test

var passed := 0
var failed := 0
var game: Node3D
var shots: Array[Dictionary] = []
var clock := 0.0


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
	for index in count:
		clock += 1.0 / 60.0
		await get_tree().physics_frame


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Pacing regression checks require -- --test")
		get_tree().quit(2)
		return
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		push_error("Pacing regression runner timed out")
		get_tree().quit(2)
	)
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.start_game()
	game.set_process(false)
	game.child_entered_tree.connect(_observe_shell)
	_freeze()
	await _frames(3)
	_check_role_pacing()
	await _check_real_motion_and_reload()
	await _check_enemy_acquisition()
	await _check_boss_windows()
	await _check_encounters()
	await _check_enemy_feedback()
	if passed + failed != 50:
		failed += 1
		push_error("Pacing regression runner stopped before all 50 checks completed")
	print("PACING_REGRESSION_RESULT: %d passed, %d failed" % [passed, failed])
	game.free()
	await _frames(2)
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)


func _freeze() -> void:
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	return body


func _clear_shots() -> void:
	for shell: Node in get_tree().get_nodes_in_group("projectiles"):
		shell.free()
	shots.clear()


func _observe_shell(node: Node) -> void:
	if node.is_in_group("projectiles"):
		shots.append({"time": clock, "owner": node.owner_tank.get_instance_id(), "kind": node.weapon_kind})


func _owner_shots(tank: TankActor, kind := "cannon") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for shot: Dictionary in shots:
		if shot.owner == tank.get_instance_id() and shot.kind == kind:
			result.append(shot)
	return result


func _check_role_pacing() -> void:
	var player: TankActor = game.player
	_check(player.move_speed >= 6.0 and player.move_speed <= 9.0, "player cruising speed fits deliberate armored movement")
	_check(player.fire_interval >= 2.5 and player.fire_interval <= 4.0, "player main gun has a readable multi-second reload")
	var kinds := {}
	for enemy: TankActor in game.enemies:
		if enemy.is_boss or kinds.has(enemy.archetype):
			continue
		kinds[enemy.archetype] = true
		_check(enemy.move_speed >= 3.0 and enemy.move_speed <= 7.5, enemy.archetype + " speed stays below the player's cruising speed")
		_check(enemy.fire_interval >= 4.0 and enemy.aim_acquire_time >= 1.0, enemy.archetype + " gun provides a multi-second reload and visible aiming interval")
	var boss: TankActor = game.boss
	_check(boss.move_speed <= 5.0 and boss.fire_interval >= 5.0, "boss weight is represented by slower movement and main-gun loading")
	_check(player.projectile_speed >= 60.0 and boss.projectile_speed >= 50.0, "slower fire cadence preserves fast shell flight")


func _check_real_motion_and_reload() -> void:
	_box(Vector3(300, -0.5, 0), Vector3(100, 1, 160))
	var player: TankActor = game.player
	player.global_position = Vector3(300, 0.03, 30)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await _frames(4)
	Input.action_press("move_forward")
	await _frames(12)
	var early_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(early_speed > 0.5 and early_speed < player.move_speed * 0.5, "throttle builds momentum instead of instantly reaching top speed")
	await _frames(100)
	_check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), player.move_speed), "held forward input reaches the configured cruise speed in real physics")
	var moving_at := player.global_position
	Input.action_release("move_forward")
	await _frames(6)
	_check(player.global_position.distance_to(moving_at) > 0.3 and Vector2(player.velocity.x, player.velocity.z).length() > 0.1, "releasing throttle retains a short controlled braking distance")
	await _frames(65)
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "braking fully stops the tank without residual drift")
	var old_yaw := player.rotation.y
	Input.action_press("move_right")
	await _frames(6)
	_check(absf(angle_difference(old_yaw, player.rotation.y)) <= player.turn_speed * 0.12, "hull turns at a bounded angular speed rather than snapping sideways")
	Input.action_release("move_right")
	await _frames(65)
	player.rotation = Vector3.ZERO
	player._turret.rotation = Vector3.ZERO
	player._controller_aim_active = true
	player._controller_aim_direction = Vector3.FORWARD
	player.reload = 0.0
	_clear_shots()
	Input.action_press("fire")
	await _frames(420)
	Input.action_release("fire")
	player.set_physics_process(false)
	var fired := _owner_shots(player)
	_check(fired.size() >= 2 and fired.size() <= 3, "holding fire for seven seconds produces deliberate cannon shots")
	var cadence_ok := fired.size() >= 2
	for index in range(1, fired.size()):
		cadence_ok = cadence_ok and float(fired[index].time) - float(fired[index - 1].time) >= player.fire_interval - 0.035
	_check(cadence_ok, "actual spawned shells never bypass the player reload interval")
	_clear_shots()


func _check_enemy_acquisition() -> void:
	var enemy: TankActor = game.enemies[1]
	var player: TankActor = game.player
	player.global_position = Vector3(300, 0.03, -29)
	player.velocity = Vector3.ZERO
	enemy.remove_meta("encounter_index")
	enemy.global_position = Vector3(300, 0.03, 0)
	enemy.rotation = Vector3.ZERO
	enemy._turret.rotation = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	enemy.reload = 0.0
	enemy._aim_hold_time = 0.0
	enemy._observation_clock = 0.0
	enemy._salvo_clock = 99.0
	await _frames(3)
	_clear_shots()
	var observed_at := clock
	enemy.set_physics_process(true)
	await _frames(60)
	_check(_owner_shots(enemy).is_empty(), "a newly visible, already aligned enemy cannot fire in its first second")
	await _frames(42)
	var fired := _owner_shots(enemy)
	_check(fired.size() == 1 and float(fired[0].time) - observed_at >= enemy.aim_acquire_time - 0.035, "continuous settled aim eventually fires after its announced acquisition interval")
	enemy.set_physics_process(false)
	_clear_shots()
	enemy.reload = 0.0
	enemy._aim_hold_time = enemy.aim_acquire_time * 0.85
	var wall := _box(Vector3(300, 3, -13), Vector3(16, 6, 1))
	await _frames(3)
	enemy._ai_control(0.1)
	_check(is_zero_approx(enemy._aim_hold_time) and _owner_shots(enemy).is_empty(), "solid cover discards the prior firing solution and blocks a last-instant shot")
	wall.free()
	enemy.velocity = Vector3.ZERO
	await _frames(3)
	enemy.set_physics_process(true)
	await _frames(48)
	_check(_owner_shots(enemy).is_empty(), "emerging from cover starts a fresh reaction window")
	await _frames(48)
	_check(_owner_shots(enemy).size() == 1, "the enemy can reacquire normally after the fresh reaction window")
	enemy.set_physics_process(false)
	enemy._aim_hold_time = enemy.aim_acquire_time * 0.8
	enemy.apply_emp(2.0)
	_check(is_zero_approx(enemy._aim_hold_time) and enemy.stunned >= 2.0, "EMP cancels an ordinary enemy's prepared shot as well as stopping its hull")
	_clear_shots()


func _check_boss_windows() -> void:
	var boss: TankActor = game.boss
	var player: TankActor = game.player
	player.global_position = Vector3(300, 0.03, -30)
	boss.global_position = Vector3(300, 0.03, 0)
	boss.rotation = Vector3.ZERO
	boss._turret.rotation = Vector3.ZERO
	boss.active = true
	await _frames(3)
	for phase in range(1, 4):
		boss.boss_phase = phase
		_check(boss.boss_telegraph_duration() >= 2.3 and boss.boss_salvo_interval() >= 10.0, "boss phase %d keeps an escapable warning and long salvo interval" % phase)
		_check(boss.boss_salvo_count() <= 5, "boss phase %d limits simultaneous rocket coverage" % phase)
	boss.boss_phase = 1
	boss._salvo_clock = 0.0
	boss._charge_clock = 0.0
	boss._salvo_recovery = 0.0
	_clear_shots()
	boss._update_boss_attack(0.01, player, 30.0)
	var announced := boss._salvo_aim_point
	var warning_time := boss.boss_telegraph_duration()
	boss._update_boss_attack(warning_time - 0.15, player, 30.0)
	_check(boss.boss_warning and _owner_shots(boss, "rocket").is_empty(), "rockets do not appear before the full warning expires")
	player.global_position.x += 10.0
	_check(boss._salvo_aim_point.is_equal_approx(announced), "moving clear of danger lanes does not redirect the committed strike")
	# A phase transition during an announced attack must not add hidden lanes.
	boss.boss_phase = 2
	boss._update_boss_attack(0.16, player, 30.0)
	_check(_owner_shots(boss, "rocket").size() == 3 and not boss.boss_warning, "a phase change cannot add rockets to the three lanes already announced")
	_check(boss._salvo_recovery >= 3.0 and boss.reload >= 3.0, "rocket discharge creates a main-gun recovery window")
	_clear_shots()
	boss.reload = 0.0
	boss._ai_control(1.0)
	_check(_owner_shots(boss).is_empty() and boss.ai_state == "recover", "boss cannot stack an immediate main-gun hit onto the rocket salvo")
	boss._salvo_recovery = 0.0
	boss._salvo_clock = 0.0
	boss._charge_clock = 0.0
	boss._update_boss_attack(0.01, player, 30.0)
	boss.apply_emp(1.6)
	_check(not boss.boss_warning and boss._salvo_clock >= 6.0, "interrupting a salvo grants time to exploit the EMP instead of instantly recharging")
	boss.active = false
	_clear_shots()


func _check_encounters() -> void:
	game.retry_game()
	_freeze()
	await _frames(3)
	var active_count := 0
	var routes_present := true
	for enemy: TankActor in game.enemies:
		if not enemy.is_boss:
			active_count += int(game.can_enemy_engage(enemy))
			routes_present = routes_present and enemy.patrol_route.size() >= 2
	_check(active_count == game.target_kills and routes_present, "all ordinary crews patrol authored routes without an artificial encounter freeze")
	var reserve: TankActor = game.enemies[4]
	game.player.global_position = Vector3(300, 0.03, 300)
	reserve._ai_control(0.2)
	_check(reserve.ai_state == "patrol" and reserve.velocity.length() > 0.01 and is_zero_approx(reserve._aim_hold_time), "distant patrols move normally without preparing cross-map shots")
	var health := reserve.hp
	reserve.receive_damage(5.0, 0, reserve.global_position + Vector3.RIGHT)
	_check(reserve.hp < health and reserve.ai_state == "search" and reserve._last_seen_position != game.player.global_position, "a patrol reacts to incoming damage without discovering the distant shooter's exact position")
	game.retry_game()
	_freeze()
	await _frames(3)
	game.player.hp = 100.0
	game.player.mine_ammo = 3
	game.player.select_weapon(3)
	game.player._loadout.fire()
	var supply: Dictionary = game._supply_points[0]
	game.player.global_position = supply.position
	game._update_supplies()
	_check(is_equal_approx(game.player.hp, 185.0) and game.player.mine_ammo == 6 and game.player.get_weapon_snapshot().ammo == 8, "entering an unused supply zone repairs armor and restores mines and finite weapons")
	game.player.hp = 150.0
	game._update_supplies()
	_check(supply.used and is_equal_approx(game.player.hp, 150.0), "a consumed supply point cannot repeatedly regenerate armor")
	game.player.hp = game.player.max_hp
	game.player.resupply()
	var untouched: Dictionary = game._supply_points[1]
	game.player.global_position = untouched.position
	game._update_supplies()
	_check(not untouched.used, "a fully stocked tank does not waste an unused field supply")
	game.player.hp = 30.0
	game.player.emp_cooldown = 8.0
	game._activate_boss()
	_check(game.player.hp >= game.player.max_hp * 0.75 and is_zero_approx(game.player.emp_cooldown), "boss transition gives a damaged player a usable hull and EMP")
	game._on_boss_phase_changed(2)
	game._on_boss_phase_changed(3)
	var guards := 0
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.is_boss and not enemy.counts_for_objective:
			guards += 1
	_check(guards == 1, "overlapping boss phases cannot pile multiple live guards onto the player")


func _check_enemy_feedback() -> void:
	game.retry_game()
	_freeze()
	await _frames(3)
	var player: TankActor = game.player
	var enemy: TankActor = game.enemies[0]
	player.global_position = Vector3(300, 0.03, 0)
	player.rotation = Vector3.ZERO
	player._process(0.1)
	enemy.global_position = Vector3(300, 0.03, -15)
	enemy._aim_hold_time = 0.0
	await _frames(3)
	var telemetry: Script = load("res://scripts/battle_telemetry.gd")
	var data: Dictionary = telemetry.collect(game)
	_check(data.enemy_markers.is_empty(), "undamaged, non-aiming enemies do not clutter the view with permanent health bars")
	enemy.hp -= 10.0
	data = telemetry.collect(game)
	_check(data.enemy_markers.size() == 1 and float(data.enemy_markers[0].health) < 1.0, "a visible damaged enemy exposes its remaining armor")
	enemy.hp = enemy.max_hp
	enemy._aim_hold_time = enemy.aim_acquire_time * 0.5
	data = telemetry.collect(game)
	_check(data.enemy_markers.size() == 1 and float(data.enemy_markers[0].aiming) > 0.4, "actual enemy acquisition time drives the on-screen aiming warning")
	var wall := _box(Vector3(300, 3, -7), Vector3(18, 6, 1))
	await _frames(3)
	_check(telemetry.collect(game).enemy_markers.is_empty(), "enemy aiming and damage labels cannot reveal tanks through solid cover")
	wall.free()
	enemy.hp = enemy.max_hp
	enemy._aim_hold_time = 0.0
	game.boss.global_position = Vector3(300, 0.03, -17)
	game.boss.active = true
	game.boss.hp -= 10.0
	await _frames(3)
	_check(telemetry.collect(game).enemy_markers.is_empty(), "boss feedback uses its dedicated HUD rather than redundant floating bars")
