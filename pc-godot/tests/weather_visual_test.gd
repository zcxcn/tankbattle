extends SceneTree
## Render the production harbor weather from both real gameplay camera modes.

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
	directory = ProjectSettings.globalize_path("res://../work/asset-review/weather-0.4.2")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/weather_visual_042")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	for chapter in [0, 1, 4]:
		game.selected_mission = chapter
		game.start_game()
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
		await capture("chapter-%d-tactical" % (chapter + 1))
		game.player.toggle_camera()
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		game.ui.update_snapshot(game.get_ui_snapshot())
		await frames(60)
		await capture("chapter-%d-chase" % (chapter + 1))
		if is_instance_valid(game.arena.weather):
			print("WEATHER_SNAPSHOT: ", game.arena.weather.get_snapshot())
	game.free()
	await frames(3)
	print("WEATHER_VISUAL_COMPLETE")
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
