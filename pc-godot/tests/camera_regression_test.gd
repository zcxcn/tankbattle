extends SceneTree
## Real SpringArm physics, view controls and paused input contracts.

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)

func frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	var game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.start_game()
	game.set_process(false)
	for tank in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	var player = game.player
	var rig = player._camera_pivot
	await frames(4)
	check(not player.is_third_person() and rig.arm.spring_length >= 30.0, "deployment begins in tactical view")
	player.rotation.y = 1.2
	await frames(2)
	check(absf(rig.arm.rotation.y) < 0.001, "tactical camera remains north-up as the hull turns")
	player.rotation.y = 0.0
	player._turret.rotation.y = 0.0
	player.toggle_camera()
	rig.update_view(1.0, Vector3.ZERO)
	await frames(3)
	check(player.is_third_person() and rig.arm.spring_length < 15.0 and absf(rig.arm.rotation.x) < 0.3, "C enters a low third-person view")
	rig.handle_look(Vector2(180.0, -80.0))
	rig.update_view(1.0, Vector3.ZERO)
	check(rig.yaw < -0.3 and rig.pitch > -0.18, "mouse motion rotates chase yaw and elevation")
	rig.yaw = PI * 0.5
	check(rig.movement(Vector2(0, -1)).distance_to(Vector3.LEFT) < 0.01, "third-person driving follows camera-relative forward")
	rig.handle_look(Vector2(0, -100000))
	check(rig.pitch <= 0.12, "camera cannot flip above its elevation limit")
	rig.handle_look(Vector2(0, 100000))
	check(rig.pitch >= -0.72, "camera cannot flip beneath its depression limit")
	rig.yaw = 0.0
	rig.pitch = -0.18
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = player.global_position + Vector3(0, 3.0, 7.0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, 6, 0.5)
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	rig.update_view(1.0, Vector3.ZERO)
	await frames(5)
	check(rig.arm.get_hit_length() < rig.chase_distance - 1.0, "SpringArm shortens when a building blocks the chase view")
	check(player.camera.global_position.z < wall.position.z - 0.4, "camera remains in front of the wall with near-plane clearance")
	wall.free()
	await frames(5)
	check(rig.arm.get_hit_length() > rig.chase_distance - 0.5, "camera restores its distance after cover clears")
	game.pause_game()
	var yaw_before: float = rig.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	motion.screen_relative = motion.relative
	player._input(motion)
	check(is_equal_approx(rig.yaw, yaw_before), "paused mouse input cannot rotate the battle camera")
	game.resume_game()
	for tick in 12:
		rig.zoom(1.0)
	check(not player.is_third_person(), "scrolling outward returns to tactical view")
	for tick in 20:
		rig.zoom(-1.0)
	check(player.is_third_person() and rig.chase_distance >= 7.0, "scrolling inward enters third person without crossing the tank")
	game.free()
	await process_frame
	print("CAMERA_RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
