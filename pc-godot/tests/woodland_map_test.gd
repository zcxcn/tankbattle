extends "res://tests/enemy_range_test.gd"
const Layout = preload("res://data/woodland_layout.gd")

func surface(at: Vector3) -> Dictionary:
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 40, at - Vector3.UP * 10, 1))

func drive(enemy: TankActor, from: Vector3, to: Vector3, ticks: int) -> Dictionary:
	enemy.set_physics_process(false)
	enemy.position = Layout.ground(from)
	enemy.velocity = Vector3.ZERO
	enemy.rotation = Vector3.ZERO
	enemy._has_contact = false
	enemy._search_remaining = 0.0
	enemy._patrol_pause = 0.0
	enemy.patrol_route.assign([Layout.ground(to)])
	await frames(3)
	enemy.set_physics_process(true)
	var peak := enemy.position.y
	var low := enemy.position.y
	var reached := false
	for tick in ticks:
		await get_tree().physics_frame
		peak = maxf(peak, enemy.position.y)
		low = minf(low, enemy.position.y)
		if Vector2(enemy.position.x - to.x, enemy.position.z - to.z).length() < 3.5:
			reached = true
			break
	enemy.set_physics_process(false)
	print("WOODLAND_DRIVE from=%s to=%s actual=%s reached=%s peak=%.2f low=%.2f" % [from, to, enemy.position, reached, peak, low])
	return {"reached": reached, "peak": peak, "low": low}

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	SaveService._directory = "user://tests/woodland_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	SettingsService.weather_mode = 1
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	var button := game.ui.find_child("WoodlandStart", true, false) as Button
	check(button != null and button.focus_mode == Control.FOCUS_ALL, "new map has a keyboard/gamepad-focusable direct menu entry")
	button.pressed.emit()
	game.set_process(false)
	for actor in get_tree().get_nodes_in_group("tanks"):
		actor.set_physics_process(false)
	await frames(3)
	check(game.mission_index == 6 and game.mode == "playing" and game.arena.has_meta("woodland_arena"), "fresh profile can enter the real woodland mission through the menu")
	check(game.enemies.size() == 25 and not game.boss.active and game.target_kills == 24, "woodland deploys twenty-four patrols and its protected boss")
	check(game.arena.get_meta("woodland_tree_count", 0) >= 100, "imported textured trees form a substantial woodland")
	print("WOODLAND_TREES: ", game.arena.get_meta("woodland_tree_count"))
	check(game.arena.get_meta("bridges").size() == 3, "three independent bridges span the river")
	var ground_ok := true
	var highest := 0.0
	for x in [-96.0, 0.0, 96.0]:
		for z in [-144.0, -72.0, 0.0, 72.0, 144.0, 174.0]:
			var at := Vector3(x, 0, z)
			var hit := surface(at)
			ground_ok = ground_ok and not hit.is_empty() and absf(hit.position.y - Layout.height_at(x, z)) < 0.08
			highest = maxf(highest, Layout.height_at(x, z))
	check(ground_ok and highest > 17, "render height samples match real hillside collision with over seventeen metres of relief")
	var spawn_ok := true
	for actor in game.enemies + [game.player]:
		spawn_ok = spawn_ok and absf(actor.position.y - game.arena.get_surface_height(actor.position)) < 0.02
	check(spawn_ok, "all initial tanks and boss spawn at local terrain height")
	check(not game.has_line_of_sight(Layout.ground(Vector3(96, 0, -12)) + Vector3.UP * 2, Layout.ground(Vector3(96, 0, -130)) + Vector3.UP * 2), "hill crests genuinely occlude enemy sight and shell paths")
	for kind in ["heavy_rain", "snow", "dry"]:
		game.arena.set_weather_kind(kind)
		await frames(2)
		check(game.arena.get_meta("weather") == kind and is_instance_valid(game.arena.landscape.water), "%s weather preserves woodland terrain and river" % kind)
		var surface_material: ShaderMaterial = game.arena.landscape.find_child("WoodlandHeightfield", false, false).material_override
		check(is_equal_approx(float(surface_material.get_shader_parameter("wetness")), 1.0 if kind == "heavy_rain" else 0.0) and is_equal_approx(float(surface_material.get_shader_parameter("snow_amount")), 1.0 if kind == "snow" else 0.0), "%s reaches the playable heightfield material" % kind)
	for actor in game.enemies:
		actor.collision_layer = 0
	game.player.position = Vector3(-500, 0, 500)
	var enemy: TankActor = game._spawn_tank("WoodlandDriver", Vector3(96, 0, -12), 1, false, false, "line")
	var uphill := await drive(enemy, Vector3(96, 0, -12), Vector3(96, 0, -100), 2600)
	check(uphill.reached and uphill.peak > 17, "production tank drives up and across the northern hillside without stalling")
	var across := await drive(enemy, Vector3(30, 0, 62), Vector3(-20, 0, 10), 3000)
	check(across.reached and across.low > -0.2, "production patrol finds the bridge and stays above the riverbed")
	enemy.free()
	game.return_to_menu()
	check(game.unlocked_mission_count() == 1, "direct woodland access does not falsely unlock earlier campaign chapters")
	game.free()
	print("WOODLAND MAP: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
