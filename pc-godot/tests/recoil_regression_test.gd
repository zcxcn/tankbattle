extends SceneTree
## Exercise a real imported vehicle: recoil must be visible but must not move
## its physical hull, alter launch geometry, or bypass the accessibility setting.

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	root.get_node("SaveService").set("_directory", "user://tests/recoil_041")
	root.get_node("SaveService").reset_for_tests()
	var settings: Node = root.get_node("SettingsService")
	settings.screen_shake = true
	settings.weather_mode = 1
	var game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.start_game()
	game.set_process(false)
	for tank: Node in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	var player = game.player
	player.set_process(false)
	var rig = player._camera_pivot
	player.toggle_camera()
	rig.update_view(1.0, Vector3.ZERO)
	player.position = Vector3(0, 0.05, 142)
	player.aim_point = Vector3(0, 9, 100)
	for step in 40:
		player._update_turret(0.1)
	await physics_frame
	await process_frame
	var hull_pose: Transform3D = player.transform
	var collision: Transform3D = player.get_node("HullCollision").transform
	var gun_home: Vector3 = player._barrel.position
	var bore: Vector3 = player.get_firing_direction()
	var expected_muzzle: Vector3 = player._muzzle.global_position
	var view_pitch: float = rig.arm.rotation.x
	var view_length: float = rig.arm.spring_length
	check(player.try_fire(), "main gun fires through the production loadout")
	var local_reports := root.get_node("AudioService").get_children().filter(func(node: Node) -> bool: return node.get_meta("player_weapon", false) and node.get_meta("audio_kind", "") == "cannon")
	check(local_reports.size() == 1 and local_reports[0].playing and local_reports[0].bus == "PlayerWeapons", "a real tank shot starts its reserved recorded cannon voice instead of distance-attenuated world audio")
	var shells := get_nodes_in_group("projectiles")
	check(shells.size() == 1 and shells[0].direction.dot(bore) > 0.999, "shot direction remains on the authored elevated bore before visual recoil")
	check(shells.size() == 1 and shells[0].global_position.distance_to(expected_muzzle) < 0.1, "visual recoil cannot move the projectile launch away from its muzzle")
	for shell in shells:
		shell.set_physics_process(false)
	check(rig._shot_kick > 0.9, "main gun starts a short third-person camera kick")
	rig.update_view(1.0 / 60.0, Vector3.ZERO)
	check(rig.arm.rotation.x - view_pitch > 0.04 and rig.arm.spring_length - view_length > 0.4, "the real chase camera tilts and moves back enough for the shot to register visually")
	player._update_recoil(0.065)
	var displacement: Vector3 = player._barrel.position - gun_home
	check(displacement.length() > 0.55, "main barrel visibly retreats at peak recoil")
	check(player._muzzle.global_position.distance_to(expected_muzzle) > 0.58, "the scaled imported barrel retracts at least 58 centimetres in actual world space")
	check(displacement.normalized().dot(player._barrel.basis.z.normalized()) > 0.999, "elevated gun retreats along its own bore rather than world Z")
	check(player._hull_body.rotation.distance_to(player._hull_base_rotation) > 0.02, "suspension artwork rocks under the main gun impulse")
	check(player.transform.is_equal_approx(hull_pose) and player.get_node("HullCollision").transform.is_equal_approx(collision), "recoil never displaces the authoritative tank body or collision envelope")
	check(player.get_firing_direction().dot(bore) > 0.99999, "suspension rocking cannot deflect the physical gun bore")
	var peak: float = player._recoil
	player._update_recoil(0.2)
	check(player._recoil > 0.1 and player._recoil < peak, "barrel returns progressively instead of snapping home")
	var paused_recoil: float = player._recoil
	var paused_kick: float = rig._shot_kick
	game.pause_game()
	player._physics_process(0.3)
	rig.update_view(0.3, Vector3.ZERO)
	check(is_equal_approx(paused_recoil, player._recoil) and is_equal_approx(paused_kick, rig._shot_kick), "pause freezes gun and camera recoil together")
	settings.screen_shake = false
	rig.update_view(0.016, Vector3.ZERO)
	check(is_zero_approx(rig._shot_kick), "disabling screen shake while paused clears an existing camera kick")
	game.resume_game()
	player._update_recoil(1.0)
	check(player._barrel.position.is_equal_approx(gun_home) and player._hull_body.rotation.is_equal_approx(player._hull_base_rotation), "barrel and suspension return exactly to their imported rest transforms")
	player._loadout.tick(10.0)
	player.reload = 0.0
	check(player.try_fire() and is_zero_approx(rig._shot_kick), "screen-shake-off permits cannon fire without applying camera recoil")
	player._update_recoil(0.065)
	check(player._recoil > 0.55, "screen-shake-off retains visible mechanical gun recoil")
	player._update_recoil(1.0)
	for slot in [1, 3]:
		player.select_weapon(slot)
		player._loadout.tick(10.0)
		player.reload = 0.0
		var settled_time: float = player._recoil_time
		check(player.try_fire() and is_equal_approx(player._recoil_time, settled_time), "weapon %d does not incorrectly retract the main cannon" % slot)
		var selected: String = player.get_weapon_snapshot().id
		var weapon_reports := root.get_node("AudioService").get_children().filter(func(node: Node) -> bool: return node.get_meta("player_weapon", false) and node.get_meta("audio_kind", "") == selected)
		check(weapon_reports.size() > 0 and weapon_reports[-1].playing, "actual weapon %s firing also starts its own recorded local sound" % selected)
	settings.screen_shake = true
	game.free()
	await process_frame
	print("RECOIL_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)
