extends SceneTree
## Real swept projectiles strike the player in both production camera views.
## Run with --fixed-fps 60 -- --test. Captures are appearance evidence, not FPS.

var game: Node3D
var source: Node3D
var latest_impact: Node3D
var directory := ""
var baseline: Image
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func frames(count: int) -> void:
	for tick in count:
		await process_frame


func capture(label: String, verify_hot := false) -> void:
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var path := directory.path_join(label + ".png")
	print("IMPACT_CAPTURE: %s error=%d" % [path, rendered.save_png(path)])
	if label.ends_with("baseline"):
		baseline = rendered
	if verify_hot and is_instance_valid(latest_impact):
		var projected := root.get_camera_3d().unproject_position(latest_impact.global_position + Vector3.UP * 0.7)
		var center := projected * Vector2(rendered.get_size()) / root.get_visible_rect().size
		var hot_pixels := 0
		for y in range(maxi(0, int(center.y) - 115), mini(rendered.get_height(), int(center.y) + 115)):
			for x in range(maxi(0, int(center.x) - 115), mini(rendered.get_width(), int(center.x) + 115)):
				var pixel := rendered.get_pixel(x, y)
				var old := baseline.get_pixel(x, y)
				if pixel.r > 0.65 and pixel.g > 0.28 and pixel.r - pixel.b > 0.15 and pixel.r + pixel.g - old.r - old.g > 0.20:
					hot_pixels += 1
		print("IMPACT_GPU_HOT: %s pixels=%d age=%.4f" % [label, hot_pixels, latest_impact._age])
		if hot_pixels < 100:
			failed += 1
			push_error("Impact heat was not visible around the actual player hit: " + label)


func shoot_player(kind: String) -> void:
	game.player.hp = game.player.max_hp
	game.player.invulnerable = 0.0
	var start: Vector3 = game.player.global_position + Vector3(12, 1.7, 9)
	var target: Vector3 = game.player.global_position + Vector3(0, 1.2, 0)
	var splash := 8.0 if kind == "he" else (6.0 if kind == "rocket" else 0.0)
	game.spawn_projectile(source, start, (target - start).normalized(), 8.0, 185.0 if kind == "he" else (95.0 if kind == "rocket" else 260.0), splash, kind)
	latest_impact = null
	for tick in 90:
		await process_frame
		for effect: Node3D in get_nodes_in_group("impact_fx"):
			if effect._impact_priority and effect._weapon_kind == kind and not effect.is_queued_for_deletion():
				if latest_impact == null or effect._age < latest_impact._age:
					latest_impact = effect
		if latest_impact != null:
			break
	if latest_impact == null or game.player.hp >= game.player.max_hp:
		failed += 1
		push_error("Real projectile did not produce a priority player hit: " + kind)
		return
	print("IMPACT_REAL_HIT: kind=%s surface=%s position=%s priority=%s hp=%.1f" % [kind, latest_impact._surface_kind, latest_impact.global_position, latest_impact._impact_priority, game.player.hp])
	if latest_impact._surface_kind != "armor":
		failed += 1
		push_error("Real player impact did not resolve as armor")
	if kind == "machine_gun" and (latest_impact._light != null or latest_impact.get_node_or_null("Fire") != null):
		failed += 1
		push_error("Machine-gun hit incorrectly generated an explosive fireball")


func clear_impacts() -> void:
	for effect: Node in get_nodes_in_group("impact_fx"):
		effect.free()
	for projectile: Node in get_nodes_in_group("projectiles"):
		projectile.free()
	latest_impact = null


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		await preload("res://tests/test_shutdown.gd").finish(self, 2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/impact-0.4.5")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/impact_visual_045")
	root.get_node("SaveService").reset_for_tests()
	root.get_node("SettingsService").set("weather_mode", 1)
	root.get_node("SettingsService").set("screen_shake", false)
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.set_meta("deployment_seed", 40910)
	game.start_game()
	for tank: Node3D in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
		if not tank.is_player:
			tank.hide()
			if source == null:
				source = tank
	game.player.position = Vector3(0, 0.05, 142)
	var effect_script := load("res://actors/explosion_fx.gd")
	for view in ["tactical", "chase"]:
		game.player._camera_pivot.set_third_person(view == "chase")
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		await frames(30)
		for kind in ["cannon", "he", "rocket", "machine_gun"]:
			await capture(view + "-" + kind + "-baseline")
			await shoot_player(kind)
			await frames(3)
			await capture(view + "-" + kind + "-flash", kind != "machine_gun")
			await frames(8)
			await capture(view + "-" + kind + "-pressure", kind != "machine_gun")
			await frames(16)
			await capture(view + "-" + kind + "-debris")
			await frames(42)
			await capture(view + "-" + kind + "-smoke")
			clear_impacts()
			await frames(12)
		await capture(view + "-crowded-baseline")
		for index in effect_script.MAX_IMPACTS:
			var busy: Node3D = effect_script.create_impact(Vector3(100 + index, 2, 140), false, "armor", Vector3.RIGHT, "cannon")
			game.add_child(busy)
			busy.set_process(false)
		await shoot_player("cannon")
		await frames(3)
		await capture(view + "-crowded-player-hit", true)
		if latest_impact == null or latest_impact._light == null or get_nodes_in_group("impact_fx").size() > effect_script.MAX_IMPACTS or get_nodes_in_group("impact_flash_lights").size() > effect_script.MAX_FLASH_LIGHTS:
			failed += 1
			push_error("Player impact priority failed in the saturated battle budgets")
		clear_impacts()
		await frames(12)
	game.free()
	await frames(3)
	print("IMPACT_VISUAL_COMPLETE: %d failures" % failed)
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)
