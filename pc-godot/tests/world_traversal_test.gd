extends Node
## Drive the production player through the new world using real input/physics.
## --fixed-fps 60 makes this deterministic simulation finish quickly headless.

var passed := 0
var failed := 0
var game: Node3D
var player: CharacterBody3D


func _ready() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func release_movement() -> void:
	for movement in ["move_forward", "move_back", "move_left", "move_right"]:
		action(movement, false)


func physics_frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame


func road_hit(at: Vector3) -> Dictionary:
	return player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(at + Vector3.UP * 12.0, at + Vector3.DOWN * 12.0, 1))


func drive_route(from: Vector3, to: Vector3) -> Dictionary:
	release_movement()
	player.position = from + Vector3.UP * 0.18
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0, 0 if to.z < from.z else PI, 0)
	await physics_frames(18)
	var movement := "move_forward" if to.z < from.z else "move_back"
	action(movement, true)
	var min_height := 1000.0
	var max_height := -1000.0
	var has_penetration := false
	var reached := false
	var river_supported := true
	var river_samples := 0
	var moving_samples := 0
	for frame in 1000:
		await get_tree().physics_frame
		var at: Vector3 = player.global_position
		min_height = minf(min_height, at.y)
		max_height = maxf(max_height, at.y)
		if player.get_real_velocity().length() > 1.0:
			moving_samples += 1
		var ground := road_hit(at)
		if not ground.is_empty() and at.y < float(ground.position.y) - 0.12:
			has_penetration = true
		if at.z > 24.0 and at.z < 48.0:
			river_samples += 1
			river_supported = river_supported and at.y > -0.16 and at.y < 0.3 and not ground.is_empty()
		if (to.z < from.z and at.z <= to.z) or (to.z > from.z and at.z >= to.z):
			reached = true
			break
	release_movement()
	await physics_frames(30)
	print("Traversal from=%s to=%s reached=%s actual=%s y=[%.3f, %.3f] moving_frames=%d" % [from, to, reached, player.global_position, min_height, max_height, moving_samples])
	return {"reached": reached, "min_height": min_height, "max_height": max_height,
		"penetrated": has_penetration, "supported": river_supported, "river_samples": river_samples,
		"moving_samples": moving_samples, "final_height": player.global_position.y}


func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	var settings := get_tree().root.get_node("SettingsService")
	settings.set("weather_mode", 1)
	settings.set("remote_mouse", false)
	var save := get_tree().root.get_node("SaveService")
	save.set("_directory", "user://tests/world_traversal_%d" % OS.get_process_id())
	save.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(game)
	game.set_process(false)
	game.start_game()
	game.set_process(false)
	player = game.player
	player._camera_pivot.set_third_person(false)
	# Keep the actual enemies present but prevent encounters or parked hulls from
	# influencing the geometry test; the real player keeps its normal collider.
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		if tank != player:
			tank.set_physics_process(false)
			tank.set("active", false)
			tank.set("collision_layer", 0)
			tank.set("collision_mask", 0)
	game.arena.set_boss_gate_open(true)
	await physics_frames(3)
	check(player.is_player and player.is_physics_processing(), "production player runs its normal input, acceleration, gravity and move_and_slide")
	for x in [-96.0, 0.0, 96.0]:
		for southbound in [true, false]:
			var from := Vector3(x, 0.05, 10.0 if southbound else 62.0)
			var to := Vector3(x, 0.05, 62.0 if southbound else 10.0)
			var travel := await drive_route(from, to)
			var label := "bridge x=%d %s" % [int(x), "southbound" if southbound else "northbound"]
			check(travel.reached and travel.moving_samples > 60, label + " crosses both banks under actual held movement input")
			check(travel.supported and travel.river_samples > 20 and travel.min_height > -0.16, label + " remains supported on the low bridge deck throughout the crossing")
			check(not travel.penetrated and travel.final_height > -0.12, label + " keeps the tank above solid terrain and exits back onto the road")
	var hill := await drive_route(Vector3(48, 0.05, 140), Vector3(48, 0.05, 80))
	check(hill.reached and hill.moving_samples > 120, "production tank enters the hillside from the southern avenue and traverses the park")
	check(hill.max_height > 2.0 and hill.max_height < 6.5, "actual gravity and terrain collision lift the tank more than two meters on the hillside")
	check(not hill.penetrated and hill.min_height > -0.16 and absf(hill.final_height) < 0.25, "tank remains above hill geometry and descends back to level ground")
	var supported_candidates := true
	var candidate_count := 0
	for candidate: Vector3 in game.arena.get_spawn_candidates():
		candidate_count += 1
		var hit := road_hit(candidate)
		if hit.is_empty() or float(hit.position.y) < -0.1 or float(hit.position.y) > 0.25:
			supported_candidates = false
			print("Unsupported spawn candidate: ", candidate, " hit=", hit)
	check(supported_candidates and candidate_count >= 70, "every production randomized spawn candidate has level solid support, including bridge candidates")
	release_movement()
	print("WORLD_TRAVERSAL_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
