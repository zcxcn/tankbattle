extends SceneTree
## Production firing effects in both camera modes. Run with --fixed-fps 60
## and -- --test. Screenshots are visual evidence, never FPS benchmarks.

var game: Node3D
var directory := ""
var failed := 0
var baseline: Image
var muzzle_screen := Vector2.ZERO
var latest_muzzle: Node3D
var selected_kind := "cannon"


func _initialize() -> void:
	call_deferred("_run")


func frames(count: int) -> void:
	for tick in count:
		await process_frame


func capture(label: String, verify_hot := false, verify_cold := false) -> void:
	await RenderingServer.frame_post_draw
	var path := directory.path_join(label + ".png")
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	print("MUZZLE_CAPTURE: %s error=%d" % [path, result])
	if label.ends_with("baseline"):
		baseline = image
	if verify_hot or verify_cold:
		var hot_pixels := 0
		# Camera projection uses logical viewport coordinates; canvas stretch
		# can render those into a differently sized window image.
		var sample_center := muzzle_screen * Vector2(image.get_size()) / root.get_visible_rect().size
		for y in range(maxi(0, int(sample_center.y) - 85), mini(image.get_height(), int(sample_center.y) + 85)):
			for x in range(maxi(0, int(sample_center.x) - 85), mini(image.get_width(), int(sample_center.x) + 85)):
				var pixel := image.get_pixel(x, y)
				var previous := baseline.get_pixel(x, y)
				if pixel.r > 0.88 and pixel.g > 0.68 and pixel.r + pixel.g + pixel.b - previous.r - previous.g - previous.b > 0.45:
					hot_pixels += 1
		print("MUZZLE_GPU_HOT_PIXELS: %s %d" % [label, hot_pixels])
		if verify_hot and hot_pixels < 40:
			failed += 1
			push_error("Visible muzzle discharge missing near the actual barrel in " + label)
		if verify_cold and hot_pixels >= 40:
			failed += 1
			push_error("Muzzle heat remained after the discharge should have cleared in " + label)
		if is_instance_valid(latest_muzzle):
			print("MUZZLE_GPU_AGE: %s %.4f" % [label, latest_muzzle._age])
			if verify_cold and (latest_muzzle._flash.visible or latest_muzzle._muzzle_jet.visible):
				failed += 1
				push_error("Muzzle core or axial gas remained enabled after discharge expiry")


func prepare_shot(slot: int) -> void:
	game.player.select_weapon(slot)
	game.player._loadout.tick(10.0)
	game.player.reload = 0.0
	selected_kind = str(game.player._loadout.snapshot().id)
	game.player.aim_point = Vector3(0, 1.5, 108)
	game.player._update_turret(1.0)
	var camera := root.get_camera_3d()
	muzzle_screen = camera.unproject_position(physical_muzzle().global_position + game.player.get_firing_direction(selected_kind) * 0.8)


func physical_muzzle() -> Node3D:
	if selected_kind == "machine_gun":
		return game.player._machine_muzzle
	if selected_kind == "rocket":
		return game.player._rocket_muzzles[0]
	return game.player._muzzle


func fire() -> void:
	var physical_at := physical_muzzle().global_position
	if game.mode != "playing":
		failed += 1
		push_error("Visual test left the actual playing state")
	if not game.player.try_fire():
		failed += 1
		push_error("Production tank.try_fire refused the visual test shot")
	game.ui.update_snapshot(game.get_ui_snapshot())
	var visible := false
	latest_muzzle = null
	for effect: Node in get_nodes_in_group("muzzle_fx"):
		if effect._muzzle_priority and not effect.is_queued_for_deletion() and effect._flash != null:
			visible = true
			if latest_muzzle == null or effect._age < latest_muzzle._age:
				latest_muzzle = effect
	if not visible:
		failed += 1
		push_error("Production player shot did not receive its priority muzzle effect")
	else:
		var muzzle_error := latest_muzzle.global_position.distance_to(physical_at)
		print("MUZZLE_PHYSICAL_ORIGIN: slot=%d actual=%s effect=%s error=%.6f" % [game.player._loadout.selected, physical_at, latest_muzzle.global_position, muzzle_error])
		if muzzle_error > 0.001:
			failed += 1
			push_error("Muzzle flash departed from the physical weapon muzzle")


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		await preload("res://tests/test_shutdown.gd").finish(self, 2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/muzzle-0.4.4-final")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 720)
	root.get_node("SettingsService").set("weather_mode", 1)
	root.get_node("SettingsService").set("screen_shake", false)
	root.get_node("SaveService").set("_directory", "user://tests/muzzle_visual_044")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	await frames(6)
	game.set_meta("deployment_seed", 40910)
	game.start_game()
	for tank in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	game.player.position = Vector3(0, 0.05, 142)
	game.player.aim_point = Vector3(0, 1.5, 108)
	game.player._update_turret(1.0)
	game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
	await frames(12)
	var fx_script := load("res://actors/explosion_fx.gd")
	for view in ["tactical", "chase"]:
		if view == "chase":
			game.player.toggle_camera()
			game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
			await frames(18)
		for slot in 4:
			prepare_shot(slot)
			var cannon_discharge := selected_kind in ["cannon", "he"]
			await capture("%s-weapon-%d-baseline" % [view, slot + 1])
			fire()
			await capture("%s-weapon-%d-flash" % [view, slot + 1], cannon_discharge)
			await frames(3)
			await capture("%s-weapon-%d-gas" % [view, slot + 1], cannon_discharge)
			if cannon_discharge:
				await frames(5)
				await capture("%s-weapon-%d-hot-150ms" % [view, slot + 1], true)
			await frames(12)
			if cannon_discharge:
				await capture("%s-weapon-%d-smoke" % [view, slot + 1], false, true)
			await frames(80)
		# Real try_fire also has to survive a crowded scene's existing smoke.
		prepare_shot(0)
		await capture(view + "-crowded-baseline")
		for index in fx_script.MAX_MUZZLES:
			var old_smoke: Node3D = fx_script.create_muzzle(Vector3(70 + index, 2, 142), Vector3.FORWARD)
			game.add_child(old_smoke)
			old_smoke._process(0.7)
			old_smoke.set_process(false)
		fire()
		await frames(3)
		await capture(view + "-crowded-player-gas", true)
		for effect: Node in get_nodes_in_group("muzzle_fx"):
			effect.queue_free()
		await frames(12)
	game.free()
	await frames(3)
	print("MUZZLE_VISUAL_COMPLETE: %d failures" % failed)
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)
