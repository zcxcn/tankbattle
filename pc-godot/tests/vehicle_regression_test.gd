extends Node
## Run with --headless --path pc-godot res://tests/vehicle_regression_test.tscn -- --test.

var passed := 0
var failed := 0
var game: Node3D


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
		await get_tree().physics_frame


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Vehicle regression checks require -- --test")
		get_tree().quit(2)
		return
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	if not game.has_method("start_game"):
		push_error("Vehicle regression fixture failed to load the game scene")
		get_tree().quit(2)
		return
	game.start_game()
	if game.get("mode") != "playing":
		push_error("Vehicle regression fixture could not enter combat")
		get_tree().quit(2)
		return
	game.set_process(false)
	for tank: TankActor in game.enemies:
		tank.set_physics_process(false)
	var player: TankActor = game.player
	player.set_physics_process(false)
	await _frames(3)
	var forward_camera := player.camera.global_basis
	player.rotation.y = PI * 0.5
	player._process(0.1)
	await _frames(2)
	_check(player.camera.global_basis.is_equal_approx(forward_camera), "turning the hull preserves the camera world axes used by keyboard and gamepad")
	var camera_offset := player.camera.global_position - player.global_position
	player.global_position += Vector3(4.0, 0.0, -2.0)
	player._process(0.1)
	await _frames(2)
	_check((player.camera.global_position - player.global_position).distance_to(camera_offset) < 0.01, "fixed-heading camera follows tank translation")
	player.toggle_camera()
	player._process(0.5)
	await _frames(2)
	_check(player.is_third_person() and player._camera_arm.spring_length < 18.0 and player._camera_arm.rotation.x > -0.5, "camera toggle reaches a genuinely close third-person viewing angle")
	player.toggle_camera()
	player._process(0.5)
	await _check_motion_and_wheels(player)
	await _check_aim_and_abilities(player)
	await _check_boss_telegraph_and_cover(player)
	if passed + failed != 29:
		failed += 1
		push_error("Vehicle regression runner stopped before all checks completed")
	print("VEHICLE_REGRESSION_RESULT: %d passed, %d failed" % [passed, failed])
	game.free()
	await _frames(2)
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	return body


func _clear_shells() -> void:
	for shell: Node in get_tree().get_nodes_in_group("projectiles"):
		shell.free()


func _check_motion_and_wheels(player: TankActor) -> void:
	_box(Vector3(300.0, -0.5, 0.0), Vector3(120.0, 1.0, 160.0))
	player.global_position = Vector3(300.0, 0.03, 25.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.invulnerable = 0.0
	player.active = true
	player.set_physics_process(true)
	await _frames(4)
	var controls := {"move_forward": Vector3.FORWARD, "move_back": Vector3.BACK,
		"move_left": Vector3.LEFT, "move_right": Vector3.RIGHT}
	for action: String in controls:
		var start := player.global_position
		Input.action_press(action)
		# Heavy tracked steering now takes up to three seconds to reverse its
		# heading. Keep the original distance/direction assertion with enough
		# real input time to cover that intended turning behavior.
		await _frames(120)
		Input.action_release(action)
		var travelled := player.global_position - start
		_check(travelled.dot(controls[action]) > 3.0, action + " moves through real physics along its world direction after a hull turn")
		_check(player.camera.global_basis.x.dot(Vector3.RIGHT) > 0.999, action + " keeps screen-right aligned with world-right")
		await _frames(65)
	var wall := _box(Vector3(300.0, 3.0, -12.0), Vector3(18.0, 6.0, 0.30))
	player.global_position = Vector3(300.0, 0.03, 0.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await _frames(3)
	var wheel: Node3D = player.get_node("ArmoredModel").find_child("DriveWheel00", true, false)
	var rotation_before := wheel.rotation.x
	Input.action_press("move_forward")
	await _frames(24)
	_check(absf(angle_difference(rotation_before, wheel.rotation.x)) > 0.01, "real displacement rotates the vehicle's road wheel mesh")
	await _frames(120)
	_check(player.global_position.z > -9.1 and player.global_position.z < -8.8, "the long Challenger hull stops against a thin wall without crossing it")
	rotation_before = wheel.rotation.x
	await _frames(30)
	_check(absf(angle_difference(rotation_before, wheel.rotation.x)) < 0.001, "wheels stop at a wall even while the forward control remains held")
	Input.action_release("move_forward")
	player.set_physics_process(false)
	wall.free()
	player.velocity = Vector3.ZERO
	await _frames(2)


func _check_aim_and_abilities(player: TankActor) -> void:
	player.global_position = Vector3(300.0, 0.03, 0.0)
	player.rotation = Vector3.ZERO
	Input.action_press("aim_right")
	player._player_control(0.2)
	var stick_bearing := player.aim_point - player.global_position
	_check(player.is_controller_aiming() and Vector2(stick_bearing.x, stick_bearing.z).normalized().dot(Vector2.RIGHT) > 0.999 and stick_bearing.y > 0.9, "right stick sets its independent horizontal bearing at armor height")
	var stick_target := player.aim_point
	game._update_mouse_aim()
	_check(player.aim_point.is_equal_approx(stick_target), "an idle mouse cannot overwrite active gamepad aim on a rendering frame")
	Input.action_release("aim_right")
	player.global_position += Vector3(0.0, 0.0, 4.0)
	player._player_control(0.1)
	stick_bearing = player.aim_point - player.global_position
	_check(player.is_controller_aiming() and Vector2(stick_bearing.x, stick_bearing.z).normalized().dot(Vector2.RIGHT) > 0.999 and stick_bearing.y > 0.9, "releasing the right stick preserves bearing and armor-height aim while the hull moves")
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(8.0, 0.0)
	player._input(mouse_motion)
	_check(not player.is_controller_aiming(), "moving the mouse explicitly restores mouse aiming")
	player.aim_point = player._turret.global_position + Vector3(-18.0, 0.0, -12.0)
	player._update_turret(3.0)
	var exact_direction := (player.aim_point - player._turret.global_position).normalized()
	_check((-player._turret.global_basis.z.normalized()).dot(exact_direction) > 0.9999, "nearby aim uses the authored turret pivot instead of the chassis center")
	_clear_shells()
	player.reload = 0.0
	player.aim_point = player._turret.global_position + Vector3(25.0, 0.0, 0.0)
	player._turret.rotation.y = 0.0
	var expected_direction := Vector3.FORWARD.rotated(Vector3.UP, -player.turret_turn_speed * 0.2)
	Input.action_press("fire")
	player._player_control(0.2)
	Input.action_release("fire")
	var shells := get_tree().get_nodes_in_group("projectiles")
	_check(shells.size() == 1 and (shells[0] as IronProjectile).direction.dot(expected_direction) > 0.999, "a fire input launches after the current frame's bounded turret aim update")
	_clear_shells()
	player.active = false
	player.emp_cooldown = 0.0
	player.dash_cooldown = 0.0
	_check(not player.try_emp() and not player.try_dash(Vector3.FORWARD), "inactive display tanks cannot spend EMP or dash abilities")
	player.active = true
	player.destroyed = true
	_check(not player.try_emp() and not player.try_dash(Vector3.FORWARD), "destroyed tanks cannot activate EMP or dash")
	player.destroyed = false
	await _frames(2)


func _check_boss_telegraph_and_cover(player: TankActor) -> void:
	var boss: TankActor = game.boss
	boss.global_position = Vector3(300.0, 0.03, -25.0)
	boss.rotation = Vector3.ZERO
	boss._turret.rotation = Vector3.ZERO
	boss.active = true
	boss.boss_phase = 1
	boss.reload = 10.0
	boss._salvo_clock = 0.0
	boss._charge_clock = 0.0
	boss.boss_warning = false
	player.global_position = Vector3(300.0, 0.03, -55.0)
	player.velocity = Vector3.ZERO
	await _frames(2)
	boss._ai_control(0.01)
	_check(boss.boss_warning and is_instance_valid(boss._salvo_telegraph) and boss._salvo_telegraph.visible, "boss charge exposes visible danger lanes before launching")
	var locked_target := boss._salvo_aim_point
	player.global_position.x += 15.0
	boss._ai_control(0.5)
	_check(boss._salvo_aim_point.is_equal_approx(locked_target) and boss.aim_point.is_equal_approx(locked_target), "boss telegraph commits to a position the player can dodge")
	_clear_shells()
	boss._ai_control(boss.boss_telegraph_duration() - 0.5 + 0.02)
	var rockets: Array = get_tree().get_nodes_in_group("projectiles").filter(func(node: Node) -> bool: return node is IronProjectile and node.weapon_kind == "rocket")
	var locked_spread := rockets.size() == 3
	for rocket: IronProjectile in rockets:
		var announced_direction := (locked_target - rocket.global_position).normalized()
		locked_spread = locked_spread and rocket.direction.dot(announced_direction) > cos(deg_to_rad(9.1))
	_check(locked_spread, "phase-one salvo fires three rockets within the announced spread instead of tracking the last instant")
	_check(not boss.boss_warning and not boss._salvo_telegraph.visible, "danger lanes clear after the salvo fires")
	_clear_shells()
	boss._salvo_clock = 0.0
	boss._charge_clock = 0.0
	boss._salvo_recovery = 0.0
	boss._ai_control(0.01)
	boss.apply_emp(1.6)
	_check(not boss.boss_warning and not boss._salvo_telegraph.visible and not boss._salvo_target_locked, "EMP clears both the charged attack and its ground warning")
	boss.stunned = 0.0
	boss.rotation = Vector3.ZERO
	boss._turret.rotation = Vector3.ZERO
	var walls: Array[StaticBody3D] = []
	for side in [-1.0, 1.0]:
		walls.append(_box(boss.global_position + Vector3(side * 1.51, 3.0, 0.0), Vector3(0.025, 6.0, 5.0)))
	await _frames(2)
	boss._fire_boss_salvo(player)
	_check(get_tree().get_nodes_in_group("projectiles").is_empty(), "rocket launch pods cannot bypass side cover they protrude into")
	for wall: StaticBody3D in walls:
		wall.free()
	player.global_position = Vector3(300.0, 0.03, 20.0)
	player.rotation = Vector3.ZERO
	player._turret.rotation = Vector3.ZERO
	player._barrel.position.z = player._base_barrel_z
	var midpoint := (player._barrel.global_position + player._muzzle.global_position) * 0.5
	var barrel_cover := _box(Vector3(midpoint.x, 3.0, midpoint.z), Vector3(12.0, 6.0, 0.06))
	await _frames(2)
	player._loadout.tick(10.0)
	player.select_weapon(0)
	_check(player.try_fire() and get_tree().get_nodes_in_group("projectiles").is_empty(), "a long barrel inside thin cover resolves its impact without spawning a shell beyond the wall")
	barrel_cover.free()
