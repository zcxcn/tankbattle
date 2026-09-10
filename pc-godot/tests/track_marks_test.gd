extends SceneTree
## Surface physics, tread geometry, differential turning and bounded lifecycle.

const Marks = preload("res://scripts/track_marks.gd")
var passed := 0
var failed := 0
var scene: Node3D
var marks: Node3D

class PauseFixture:
	extends Node3D
	var running := true
	func is_combat_running() -> bool:
		return running


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		push_error("FAIL: " + message)


func pose(at: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), at)


func floor_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	scene = PauseFixture.new()
	root.add_child(scene)
	floor_box(Vector3(0, -0.1, 0), Vector3(1600, 0.2, 1600))
	marks = Marks.new()
	marks.game = scene
	scene.add_child(marks)
	marks.set_physics_process(false)
	marks.configure_quality(0)
	await physics_frame
	await physics_frame
	check(marks.get_snapshot().cap == 128 and marks.get_child_count() == 128, "low preset preallocates exactly 128 reusable decal nodes")
	check(marks.get_snapshot().active == 0, "fresh scene has no prepainted tracks")
	var time_before: float = marks._time
	scene.running = false
	marks._physics_process(0.4)
	check(is_equal_approx(marks._time, time_before), "pausing combat freezes trail aging and sampling")
	scene.running = true
	marks.sample_vehicle(1, pose(Vector3(0, 0.01, 0)), true, true)
	check(marks.get_snapshot().active == 0, "first contact seeds both tracks without a connecting teleport line")
	marks.sample_vehicle(1, pose(Vector3(0, 0.01, -0.85)), true, true)
	check(marks.get_snapshot().player == 2, "forward travel paints left and right player tracks")
	var left: Decal = marks._pool[0]
	var right: Decal = marks._pool[1]
	check(absf(left.position.x + 0.97) < 0.001 and absf(right.position.x - 0.97) < 0.001, "parallel impressions use the tank's measured track spacing")
	check(absf(left.size.x - 0.53) < 0.001 and absf(left.size.z - 0.95) < 0.001, "print width and travelled length are in world metres")
	check(left.position.y - left.size.y * 0.5 < 0.0 and left.position.y + left.size.y * 0.5 > 0.10, "projection covers the collision floor and the higher visual asphalt layer")
	check(left.global_basis.y.dot(Vector3.UP) > 0.99 and left.normal_fade >= 0.8, "prints project onto ground while rejecting vertical building walls")
	check(left.texture_albedo == right.texture_albedo and left.texture_normal == right.texture_normal, "all impressions share one tread albedo and one normal texture")
	var stationary_before: Dictionary = marks.get_snapshot()
	for tick in 100:
		marks.sample_vehicle(1, pose(Vector3(0, 0.01, -0.85)), true, true)
	check(marks.get_snapshot().emitted == stationary_before.emitted, "an idling vehicle never stacks darker prints")
	check(marks.get_snapshot().ground_rays == stationary_before.ground_rays, "stationary contacts also avoid unnecessary physics rays")
	marks.sample_vehicle(1, pose(Vector3(0, 0.01, 0.0)), true, true)
	check(marks.get_snapshot().emitted == stationary_before.emitted, "reversing resets the contact anchor instead of drawing across the hull")
	marks.sample_vehicle(1, pose(Vector3(0, 0.01, 0.85)), true, true)
	check(marks.get_snapshot().player == 4, "continued reverse movement paints tracks behind the front contact patch")
	marks.sample_vehicle(2, pose(Vector3(6, 0.01, 0)), true, false, Vector3(1.137, 0.63, 1.65))
	marks.sample_vehicle(2, pose(Vector3(6, 0.01, -0.85)), true, false, Vector3(1.137, 0.63, 1.65))
	check(marks.get_snapshot().enemy == 2, "enemy tanks also leave impressions")
	var enemy: Decal = marks._pool[marks._player_capacity]
	check(absf(enemy.position.x - 4.863) < 0.001 and absf(enemy.size.x - 0.63) < 0.001, "heavy tank impressions use their wider physical track layout")
	marks.clear_marks()
	marks.sample_vehicle(3, pose(Vector3(0, 0.01, 0)), true, true)
	for tick in 12:
		marks.sample_vehicle(3, pose(Vector3(0, 0.01, 0), float(tick + 1) * 0.10), true, true)
	check(marks.get_snapshot().emitted >= 4, "pivot turning makes curved differential track impressions without forward translation")
	check(absf(marks._pool[0].global_basis.z.x) > 0.2, "turning impressions follow each track's tangent rather than a fixed world direction")
	marks.clear_marks()
	marks.sample_vehicle(4, pose(Vector3(0, 0.01, 0)), true, true)
	marks.sample_vehicle(4, pose(Vector3(100, 0.01, 0)), true, true)
	check(marks.get_snapshot().active == 0, "teleporting does not draw a long trail between locations")
	marks.sample_vehicle(4, pose(Vector3(100, 0.01, -0.85)), true, true)
	check(marks.get_snapshot().active == 2, "normal impressions restart after teleporting")
	marks.clear_marks()
	marks.sample_vehicle(5, pose(Vector3(0, 0.01, 0)), true, true)
	marks.sample_vehicle(5, pose(Vector3(0, 0.30, -1)), false, true)
	marks.sample_vehicle(5, pose(Vector3(0, 0.40, -2)), false, true)
	check(marks.get_snapshot().active == 0 and marks.get_snapshot().vehicles == 0, "airborne travel neither paints the ground nor preserves a bridge anchor")
	marks.sample_vehicle(5, pose(Vector3(0, 0.01, -3)), true, true)
	check(marks.get_snapshot().active == 0, "landing seeds a fresh contact instead of joining the jump")
	marks.sample_vehicle(5, pose(Vector3(0, 0.01, -3.85)), true, true)
	check(marks.get_snapshot().active == 2, "prints resume after stable ground contact")
	marks.clear_marks()
	marks.sample_vehicle(6, pose(Vector3(0, 1.0, 0)), true, true)
	marks.sample_vehicle(6, pose(Vector3(0, 1.0, -1)), true, true)
	check(marks.get_snapshot().active == 0, "grounded flag alone cannot paint a floor a metre below the tank")
	marks.sample_vehicle(7, pose(Vector3(900, 0.01, 0)), true, true)
	marks.sample_vehicle(7, pose(Vector3(900, 0.01, -1)), true, true)
	check(marks.get_snapshot().active == 0, "contacts beyond actual terrain do not create floating prints")
	var step := floor_box(Vector3(12, 0.06, 0), Vector3(5, 0.12, 0.7))
	await physics_frame
	await physics_frame
	marks.sample_vehicle(8, pose(Vector3(12, 0.01, -0.75)), true, true)
	marks.sample_vehicle(8, pose(Vector3(12, 0.01, -1.55)), true, true)
	check(marks.get_snapshot().active == 0, "a new raised collider breaks the trail at a step instead of spanning surfaces")
	step.free()
	marks.clear_marks()
	var slope := floor_box(Vector3(28, 0.4, 0), Vector3(6, 0.1, 10))
	slope.rotation.x = deg_to_rad(5.0)
	await physics_frame
	await physics_frame
	marks.sample_vehicle(81, pose(Vector3(28, 0.46, 0)), true, true)
	marks.sample_vehicle(81, pose(Vector3(28, 0.46 + tan(deg_to_rad(5.0)) * 0.85, -0.85)), true, true)
	check(marks.get_snapshot().active == 2, "continuous gentle slopes retain impressions while discrete steps break them")
	check(marks._pool[0].global_basis.y.dot(slope.global_basis.y) > 0.999, "projected impressions align with the actual inclined surface normal")
	slope.free()
	marks.clear_marks()
	marks.sample_vehicle(9, pose(Vector3(0, 0.01, 0)), true, true)
	for tick in 80:
		marks.sample_vehicle(9, pose(Vector3(0, 0.01, -0.85 * float(tick + 1))), true, true)
	var reserved_player: int = marks.get_snapshot().player
	marks.sample_vehicle(10, pose(Vector3(8, 0.01, 0)), true, false)
	for tick in 180:
		marks.sample_vehicle(10, pose(Vector3(8, 0.01, -0.85 * float(tick + 1))), true, false)
	check(marks.get_snapshot().active == 128 and marks.get_child_count() == 128, "sustained driving reuses a strict fixed-size pool without allocating more nodes")
	check(marks.get_snapshot().player == reserved_player and reserved_player == marks.get_snapshot().player_cap, "enemy traffic cannot evict the player's reserved trail budget")
	check(marks.get_snapshot().enemy == marks.get_snapshot().enemy_cap, "enemy print history is bounded independently")
	marks.set_wetness(1.5)
	check(is_equal_approx(float(marks.get_snapshot().wetness), 1.0), "wetness is clamped to a valid rain amount")
	marks.advance_time(0.3)
	check(is_equal_approx(marks._pool[0].modulate.a, 1.0), "rain leaves visibly darker fresh impressions")
	marks.advance_time(65.0)
	check(marks._pool[0].modulate.a > 0.0 and marks._pool[0].modulate.a < 1.0, "older wet impressions gradually fade instead of popping away")
	marks.advance_time(11.0)
	check(marks.get_snapshot().active == 0 and not marks._pool[0].visible, "expired marks become invisible and release active budget")
	marks.configure_quality(2)
	check(marks.get_snapshot().cap == 448 and marks.get_child_count() == 448, "high quality still has a strict 448-decal ceiling")
	check(marks.get_snapshot().distance == 85.0 and marks._pool[0].distance_fade_enabled, "distance fading limits visible trail cost at every preset")
	marks.clear_marks()
	check(marks.get_snapshot().vehicles == 0 and marks.get_snapshot().active == 0, "explicit level reset clears impressions and all vehicle contact history")
	scene.free()
	await process_frame
	await run_scene_integration()
	print("TRACK_MARKS_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)


func frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func run_scene_integration() -> void:
	root.get_node("SettingsService").weather_mode = 1
	root.get_node("SaveService").set("_directory", "user://tests/tracks_integration_042_%d" % OS.get_process_id())
	root.get_node("SaveService").reset_for_tests()
	var game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	if game.get_window().focus_exited.is_connected(game._on_focus_lost):
		game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.selected_mission = 0
	game.set_meta("deployment_seed", 40910)
	game.start_game()
	game.set_process(false)
	var live_marks: Node3D = game.arena.get_node_or_null("TrackMarks")
	check(is_instance_valid(live_marks) and live_marks.game == game, "the real game creates and owns its active trail manager under the arena")
	if not is_instance_valid(live_marks):
		game.free()
		return
	check(live_marks.get_snapshot().wetness == 0.0, "the first playable mission wires dry track weather")
	for tank in game.enemies:
		tank.set_physics_process(false)
	var player: CharacterBody3D = game.player
	player.global_position = Vector3(0, 0.05, 168)
	player.velocity = Vector3.ZERO
	var enemy: CharacterBody3D = game.enemies[0]
	enemy.global_position = Vector3(8, 0.05, 145)
	enemy.rotation.y = 0.0
	enemy.velocity = Vector3.ZERO
	enemy.patrol_route.assign([Vector3(8, 0.05, 110), Vector3(8, 0.05, 145)])
	enemy._patrol_pause = 0.0
	enemy._has_contact = false
	enemy._search_remaining = 0.0
	enemy.set_physics_process(true)
	await frames(12)
	var initial_player := player.global_position
	var initial_enemy := enemy.global_position
	Input.action_press("move_forward")
	await frames(150)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(initial_player) > 6.0 and player.is_on_floor(), "real input accelerates the player across the Jolt collision ground")
	check(live_marks.get_snapshot().player >= 6, "automatic manager sampling paints actual player driving without manual contact calls")
	check(enemy.global_position.distance_to(initial_enemy) > 3.0, "the actual enemy AI moves along its patrol route")
	check(live_marks.get_snapshot().enemy >= 4, "automatic manager sampling also paints actual enemy patrol movement")
	# The stock stunned branch brakes the AI vehicle; leave physics and the
	# manager running to check both remain stationary without accumulating marks.
	enemy.stunned = 1000.0
	await frames(100)
	var stopped_emitted: int = live_marks.get_snapshot().emitted
	var stopped_rays: int = live_marks.get_snapshot().ground_rays
	await frames(72)
	check(player.velocity.length() < 0.05 and enemy.velocity.length() < 0.05, "release input and the stock braking path bring both real tanks to rest")
	check(live_marks.get_snapshot().emitted == stopped_emitted, "automatic stopped-vehicle sampling never adds idle tread marks")
	check(live_marks.get_snapshot().ground_rays == stopped_rays, "automatic stopped-vehicle sampling performs no extra surface rays")
	game.pause_game()
	var paused_time: float = live_marks._time
	var paused_emitted: int = live_marks.get_snapshot().emitted
	await frames(30)
	check(is_equal_approx(live_marks._time, paused_time) and live_marks.get_snapshot().emitted == paused_emitted, "real pause_game freezes trail age and generation")
	game.resume_game()
	await frames(12)
	check(live_marks._time > paused_time, "real resume_game resumes trail age")
	var old_arena: Node3D = game.arena
	var old_marks: Node3D = live_marks
	game.retry_game()
	live_marks = game.arena.get_node("TrackMarks")
	check(not is_instance_valid(old_arena) and not is_instance_valid(old_marks), "retry frees the previous arena and all of its pooled decals")
	check(live_marks.get_snapshot().active == 0 and live_marks.get_snapshot().vehicles == 0, "retry starts with no old tread impressions or stale contact anchors")
	check(live_marks.get_snapshot().wetness == 0.0, "retry retains the current mission's dry ground state")
	game.mode = "won"
	root.get_node("SettingsService").weather_mode = 2
	game.next_mission()
	live_marks = game.arena.get_node("TrackMarks")
	check(game.mission_index == 1 and is_equal_approx(float(live_marks.get_snapshot().wetness), 0.55), "next_mission connects light rain to the new trail manager")
	check(live_marks.get_snapshot().active == 0 and live_marks.get_snapshot().vehicles == 0, "entering the rain chapter never carries tracks from the previous map")
	old_marks = live_marks
	game.selected_mission = 4
	root.get_node("SettingsService").weather_mode = 3
	game.start_game()
	live_marks = game.arena.get_node("TrackMarks")
	check(not is_instance_valid(old_marks) and live_marks.get_snapshot().wetness == 1.0, "starting the heavy-rain chapter replaces old decals and applies maximum wetness")
	game.free()
	await process_frame
