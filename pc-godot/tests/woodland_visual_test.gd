extends "res://tests/siege_beasts_visual_test.gd"

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	SettingsService.display_mode = 0
	SettingsService.resolution = Vector2i(1600, 900)
	SettingsService.quality = 2
	SettingsService.weather_mode = 1
	SettingsService.remote_mouse = true
	SettingsService.vsync = false
	SettingsService.apply()
	SaveService._directory = "user://tests/woodland_visual_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	directory = ProjectSettings.globalize_path("res://../work/asset-review/woodland/review")
	DirAccess.make_dir_recursive_absolute(directory)
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	# Avoid Windows occluded-window presentation throttling during captures.
	get_window().always_on_top = true
	get_window().grab_focus()
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	if baseline:
		game.start_game()
	else:
		game.start_woodland()
	game.set_process(false)
	for actor in get_tree().get_nodes_in_group("tanks"):
		actor.set_physics_process(false)
	game.notice = ""
	game.ui.update_snapshot(game.get_ui_snapshot())
	game.player._camera_pivot.set_third_person(true)
	game.player._camera_pivot.update_view(1, Vector3.ZERO)
	await capture("baseline-industrial" if baseline else "01-playable-hills")
	if baseline:
		print("WOODLAND BASELINE: fps=", Engine.get_frames_per_second(), " max_fps=", Engine.max_fps, " low_processor=", OS.low_processor_usage_mode)
		game.free()
		await preload("res://tests/test_shutdown.gd").finish(get_tree())
		return
	game.ui.visible = false
	camera = Camera3D.new()
	camera.far = 1000
	camera.fov = 63
	add_child(camera)
	camera.position = Vector3(125, 68, 155)
	camera.look_at(Vector3(0, 4, -25))
	camera.make_current()
	await capture("02-valley-overview")
	camera.position = Vector3(28, 12, 75)
	camera.look_at(Vector3(-35, 10, -40))
	await capture("03-river-and-forest")
	game.arena.set_weather_kind("heavy_rain")
	await capture("04-rain")
	game.arena.set_weather_kind("snow")
	await capture("05-snow")
	game.free()
	print("WOODLAND VISUAL: 5 captures")
	await preload("res://tests/test_shutdown.gd").finish(get_tree())
