extends SceneTree
## Compare every selectable weather on one production street and both cameras.

var game: Node3D
var directory := ""


func _initialize() -> void:
	call_deferred("_run")


func frames(amount: int) -> void:
	for frame in amount:
		await process_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := directory.path_join(label + ".png")
	var result := root.get_texture().get_image().save_png(path)
	print("WEATHER_CAPTURE: %s error=%d" % [path, result])


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/weather-0.4.3")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/weather_visual_043")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	for weather_kind: String in ["dry", "light_rain", "heavy_rain", "snow", "fog"]:
		if "--snow-only" in OS.get_cmdline_user_args() and weather_kind != "snow":
			continue
		game.selected_mission = 1
		root.get_node("SettingsService").set("weather_mode", {"dry": 1, "light_rain": 2, "heavy_rain": 3, "snow": 4, "fog": 5}[weather_kind])
		game.start_game()
		game.arena.set_weather_kind(weather_kind)
		game.set_process(false)
		for tank in get_nodes_in_group("tanks"):
			tank.set_physics_process(false)
		game.player.position = Vector3(0, 0.05, 126)
		game.player.rotation.y = 0.0
		game.player.aim_point = Vector3(0, 1.5, 70)
		game.player._update_turret(1.0)
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		game.ui.update_snapshot(game.get_ui_snapshot())
		await frames(60)
		await capture(weather_kind + "-tactical")
		game.player.toggle_camera()
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		game.ui.update_snapshot(game.get_ui_snapshot())
		await frames(60)
		await capture(weather_kind + "-chase")
		if is_instance_valid(game.arena.weather):
			print("WEATHER_SNAPSHOT: ", game.arena.weather.get_snapshot())
	game.free()
	await frames(3)
	print("WEATHER_VISUAL_COMPLETE")
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
