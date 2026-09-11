extends Node
## Exercise river routing through the production enemy movement and collision.

const Navigation = preload("res://scripts/river_navigation.gd")
var game: Node3D
var enemy: CharacterBody3D
var passed := 0
var failed := 0


func _ready() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame


func follow_patrol(from: Vector3, target: Vector3) -> Dictionary:
	enemy.set_physics_process(false)
	enemy.position = from + Vector3.UP * 0.15
	enemy.velocity = Vector3.ZERO
	enemy.rotation = Vector3.ZERO
	enemy.patrol_route.assign([target])
	enemy._patrol_index = 0
	enemy._patrol_pause = 0.0
	enemy._search_remaining = 0.0
	enemy._has_contact = false
	await frames(3)
	enemy.set_physics_process(true)
	var crossed := false
	var reached := false
	var lateral_hits := 0
	var min_y := 100.0
	var deck_offset := 0.0
	for frame in 2600:
		await get_tree().physics_frame
		var at: Vector3 = enemy.global_position
		min_y = minf(min_y, at.y)
		if at.z > 24.0 and at.z < 48.0:
			crossed = true
			deck_offset = maxf(deck_offset, absf(at.x))
		for index in enemy.get_slide_collision_count():
			var collision := enemy.get_slide_collision(index)
			if absf(collision.get_normal().y) < 0.6:
				lateral_hits += 1
				if lateral_hits < 3:
					print("Unexpected lateral contact at ", at, " with ", collision.get_collider().get_path())
		if Vector2(at.x - target.x, at.z - target.z).length() < 3.3:
			reached = true
			break
	enemy.set_physics_process(false)
	print("Enemy patrol from=%s target=%s actual=%s reached=%s crossed=%s side_hits=%d deck_offset=%.3f min_y=%.3f" % [from, target, enemy.global_position, reached, crossed, lateral_hits, deck_offset, min_y])
	return {"reached": reached, "crossed": crossed, "lateral_hits": lateral_hits, "deck_offset": deck_offset, "min_y": min_y}


func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	var target := Vector3(-20, 0, 10)
	check(Navigation.next_waypoint(Vector3(30, 0, 62), target) == Vector3(0, 0, 58), "a diagonal southern approach first aligns with the safe central bridge mouth")
	check(Navigation.next_waypoint(Vector3(1, 0, 57), target) == Vector3(0, 0, 14), "an aligned vehicle crosses along the bridge axis")
	check(Navigation.next_waypoint(Vector3(0, 0, 20), target) == Vector3(0, 0, 14), "the rear of a northbound hull clears the bank before a lateral turn")
	check(Navigation.next_waypoint(Vector3(0, 0, 13), target) == target, "the original target resumes after exiting the bridge corridor")
	check(Navigation.next_waypoint(Vector3(80, 0, 72), Vector3(110, 0, 0)).x == 96.0, "eastern traffic selects the eastern bridge")
	check(Navigation.next_waypoint(Vector3(-80, 0, 0), Vector3(-110, 0, 72)).x == -96.0, "western traffic selects the western bridge")
	check(Navigation.next_waypoint(Vector3(30, 0, 80), Vector3(-20, 0, 90)) == Vector3(-20, 0, 90), "movement between targets on the same bank remains unchanged")
	check(Navigation.next_waypoint(Vector3(30, 0, 62), Vector3(96, 0, 36)) == Vector3(96, 0, 58), "a target on a bridge selects that bridge's own entry")
	var settings := get_tree().root.get_node("SettingsService")
	settings.set("weather_mode", 1)
	var save := get_tree().root.get_node("SaveService")
	save.set("_directory", "user://tests/river_navigation_%d" % OS.get_process_id())
	save.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(game)
	game.set_process(false)
	game.start_game()
	game.set_process(false)
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
		tank.set("collision_layer", 0)
		tank.set("collision_mask", 0)
	game.player.position = Vector3(-120, 0.05, 170)
	enemy = game._spawn_tank("RiverNavigationEnemy", Vector3(30, 0.05, 62), 1, false, false, "line")
	enemy.set_physics_process(false)
	await frames(3)
	var outward := await follow_patrol(Vector3(30, 0.05, 62), target)
	check(outward.reached and outward.crossed, "real enemy patrol independently finds and crosses the central bridge to a diagonal north-bank target")
	check(outward.lateral_hits == 0 and outward.deck_offset < 3.5, "northbound enemy leaves sufficient turn clearance and never collides with bridge or riverbank rails")
	check(outward.min_y > -0.17, "northbound enemy remains supported over the entire river crossing")
	var homeward := await follow_patrol(Vector3(-20, 0.05, 10), Vector3(30, 0, 62))
	check(homeward.reached and homeward.crossed, "the same production enemy can navigate the return crossing southbound")
	check(homeward.lateral_hits == 0 and homeward.deck_offset < 3.5, "southbound cornering also avoids the riverbanks and bridge parapets")
	check(homeward.min_y > -0.17, "southbound enemy never falls through the channel")
	enemy.position = Vector3(30, 0, 62)
	enemy.velocity = Vector3.ZERO
	enemy._last_seen_position = target
	enemy._search_remaining = 8.0
	enemy._search_control(1.0 / 60.0)
	check(enemy.velocity.x < 0.0 and absf(enemy.velocity.x) > absf(enemy.velocity.z) * 3.0 and enemy.aim_point == target, "search moves toward the bridge entry while its gun continues aiming at the remembered contact")
	enemy.position = Vector3(15, 0, 58)
	enemy.velocity = Vector3.ZERO
	game.player.position = Vector3(-5, 0, 16)
	enemy._turret.global_rotation.y = atan2(20.0, 42.0)
	enemy._observation_clock = 0.0
	enemy.reload = 999.0
	await frames(2)
	enemy._ai_control(1.0 / 60.0)
	check(enemy.ai_state == "navigate" and enemy.velocity.x < 0.0 and absf(enemy.velocity.z) < 0.001, "visible-target pursuit routes laterally to the bridge without changing sight range or engagement distance")
	check(enemy.aim_point.distance_to(game.player.position + Vector3.UP * 1.1) < 0.01, "bridge routing does not replace the real target used for aiming")
	enemy.velocity = Vector3.ZERO
	game.player.position = Vector3(14, 0, 57)
	enemy._ai_control(1.0 / 60.0)
	check(enemy.ai_state == "retreat" and enemy.velocity.x > 0.0 and enemy.velocity.z > 0.0, "close-range reverse movement retains its original direction")
	var original_game: Node = enemy.game
	var standalone := Node.new()
	add_child(standalone)
	enemy.game = standalone
	var offset: Vector3 = enemy._navigation_offset(target)
	check(offset.is_equal_approx(Vector3(target.x - enemy.position.x, 0, target.z - enemy.position.z)), "standalone encounters without river metadata retain direct movement")
	enemy.game = original_game
	standalone.free()
	print("RIVER_NAVIGATION_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
