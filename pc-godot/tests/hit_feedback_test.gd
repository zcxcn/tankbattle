extends Node
## Real projectile sweeps into the imported player hull exercise damage, local
## audio, impact priority and both collision-aware camera modes together.

var passed := 0
var failed := 0
var game: Node3D
var player: TankActor
var rig: BattleCameraRig
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("run")


func get_nodes_in_group(group: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(group)


func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)


func reports() -> Array[Node]:
	return root.get_node("AudioService").get_children().filter(func(node: Node) -> bool:
		return node.get_meta("player_impact", false) and not node.is_queued_for_deletion())


func clear_feedback() -> void:
	for voice: Node in reports():
		voice.free()
	for effect: Node in get_nodes_in_group("impact_fx"):
		effect.free()
	player._hit_feedback_remaining = 0.0
	player._camera_shake = 0.0
	player._camera_shake_offset = Vector3.ZERO
	rig.update_view(2.0, Vector3.ZERO)


func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	root.get_node("SaveService").set("_directory", "user://tests/hit_feedback_045")
	root.get_node("SaveService").reset_for_tests()
	var settings: Node = root.get_node("SettingsService")
	settings.weather_mode = 1
	settings.screen_shake = true
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.start_game()
	game.set_process(false)
	for tank: TankActor in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
		tank.set_process(false)
	player = game.player
	rig = player._camera_pivot
	player.position = Vector3(300.0, 0.03, 0.0)
	player.hp = 5000.0
	player.max_hp = 5000.0
	player.invulnerable = 0.0
	rig.set_third_person(true)
	rig.update_view(1.0, Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hull_pose := player.transform
	var gun_pose := player._barrel.transform
	var collision_pose: Transform3D = player.get_node("HullCollision").transform
	var peaks: Dictionary = {}
	for kind in ["machine_gun", "cannon", "he", "rocket"]:
		clear_feedback()
		var before_hp := player.hp
		var damage := 8.0 if kind == "machine_gun" else 40.0
		var splash := 8.0 if kind in ["he", "rocket"] else 0.0
		game.spawn_projectile(game.boss, player.global_position + Vector3(8, 1.2, 0), Vector3.LEFT, damage, 260.0, splash, kind)
		var shell: IronProjectile = get_nodes_in_group("projectiles")[-1]
		shell.set_physics_process(false)
		shell._physics_process(0.08)
		check(shell._resolved and shell.is_queued_for_deletion() and player.hp < before_hp, kind + " physically sweeps into the real hull and applies damage")
		var voices := reports()
		check(voices.size() == (1 if kind == "machine_gun" else 2) and voices.all(func(n: Node) -> bool: return n.playing and n.get_meta("audio_kind", "") == "player_hit_" + kind), kind + " produces exactly one matching local impact despite direct plus splash damage")
		var effects := get_nodes_in_group("impact_fx")
		check(effects.size() == 1 and effects[0].get("_impact_priority") == true and effects[0].get("_weapon_kind") == kind, kind + " physical hit requests the player's priority impact effect")
		if splash == 0.0:
			check(is_equal_approx(before_hp - player.hp, damage * (1.0 - player.armor)), kind + " feedback preserves the original armor damage calculation")
		else:
			check(before_hp - player.hp > damage * (1.0 - player.armor), kind + " feedback coalescing does not suppress splash damage")
		peaks[kind] = rig._hit_kick
		await get_tree().process_frame
	check(float(peaks.cannon) > float(peaks.machine_gun) * 2.5 and float(peaks.he) > float(peaks.cannon), "main-gun and explosive camera impacts are substantially stronger than machine-gun taps")
	check(player.transform.is_equal_approx(hull_pose) and player._barrel.transform.is_equal_approx(gun_pose) and player.get_node("HullCollision").transform.is_equal_approx(collision_pose), "incoming feedback never moves the physical hull, collision or authored gun")
	for chase in [false, true]:
		clear_feedback()
		rig.set_third_person(chase)
		rig.update_view(1.0, Vector3.ZERO)
		var rest_pitch := rig.arm.rotation.x
		var rest_fov := rig.camera.fov
		var aim := Vector2(rig.yaw, rig.pitch)
		player.receive_damage(50.0, 1, player.global_position + Vector3.RIGHT, "cannon")
		player._update_camera_shake(1.0 / 60.0)
		check(rig.arm.rotation.x - rest_pitch > 0.035 and rig.camera.fov - rest_fov > 1.0 and absf(rig.arm.rotation.z) > 0.015, "view %s shows a clear pitch, directional roll and pressure jolt" % chase)
		check(Vector2(rig.yaw, rig.pitch).is_equal_approx(aim), "view %s hit impulse preserves the player's stored aim" % chase)
	var active_kick := rig._hit_kick
	var active_clock := player._hit_feedback_remaining
	var paused_pose := rig.global_transform
	var paused_arm := rig.arm.transform
	game.pause_game()
	player._physics_process(0.3)
	player._update_camera_shake(0.3)
	check(is_equal_approx(rig._hit_kick, active_kick) and is_equal_approx(player._hit_feedback_remaining, active_clock) and rig.global_transform.is_equal_approx(paused_pose) and rig.arm.transform.is_equal_approx(paused_arm), "pause freezes damage impulse, directional camera pose and duplicate-hit clock")
	settings.screen_shake = false
	player._update_camera_shake(0.016)
	check(is_zero_approx(rig._hit_kick) and is_zero_approx(player._camera_shake) and is_zero_approx(rig.arm.rotation.z), "disabling screen shake while paused clears incoming damage motion immediately")
	game.resume_game()
	clear_feedback()
	player.receive_damage(40.0, 1, player.global_position + Vector3.LEFT, "he")
	player._update_camera_shake(0.016)
	check(reports().size() == 2 and is_zero_approx(rig._hit_kick) and is_zero_approx(player._camera_shake), "screen-shake-off retains clear recorded hit audio without forcing camera motion")
	settings.screen_shake = true
	clear_feedback()
	player.receive_damage(60.0, 1, player.global_position + Vector3.LEFT, "he")
	player._update_camera_shake(0.6)
	check(is_zero_approx(rig._hit_kick) and is_zero_approx(player._camera_shake) and is_zero_approx(rig.arm.rotation.z) and is_equal_approx(rig.arm.rotation.x, rig.pitch), "heavy impact settles to the exact chase camera rest pose within 0.6 seconds")
	clear_feedback()
	player.invulnerable = 1.0
	var protected_hp := player.hp
	check(is_zero_approx(player.receive_damage(50, 1, player.global_position, "he")) and reports().is_empty() and player.hp == protected_hp, "invulnerability does not generate false damage audio or motion")
	player.invulnerable = 0.0
	check(is_zero_approx(player.receive_damage(50, 0, player.global_position, "he")) and reports().is_empty(), "friendly fire does not generate false incoming-hit feedback")
	player.hp = 1.0
	player.receive_damage(60, 1, player.global_position + Vector3.RIGHT, "cannon")
	check(game.mode == "lost" and reports().size() == 2 and reports().all(func(n: Node) -> bool: return n.playing), "the fatal accepted hit starts its full report before the defeat transition")
	game.return_to_menu()
	await get_tree().process_frame
	check(reports().is_empty(), "return to title releases the last hit's audio")
	game.free()
	print("HIT_FEEDBACK_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
