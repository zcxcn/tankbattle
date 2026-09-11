extends Node
## Real game geometry under the production renderer; only the camera is staged.
var game: Node3D
var camera: Camera3D
var directory := ""

func _ready() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame

func capture(label: String, at: Vector3, target: Vector3) -> void:
	camera.position = at
	camera.look_at(target)
	camera.make_current()
	await frames(120)
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
	assert(result == OK)
	print("WORLD_CAPTURE: %s draws=%d primitives=%d fps=%d" % [label, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Engine.get_frames_per_second()])

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var settings := get_node("/root/SettingsService")
	settings.display_mode = 0
	settings.resolution = Vector2i(1600, 900)
	settings.quality = 2
	settings.weather_mode = 1
	settings.apply()
	var save := get_node("/root/SaveService")
	save.set("_directory", "user://tests/world_visual_%d" % OS.get_process_id())
	save.reset_for_tests()
	directory = ProjectSettings.globalize_path("res://../work/asset-review/world-0.4.7")
	DirAccess.make_dir_recursive_absolute(directory)
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.start_game()
	game.set_process(false)
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	game.player.set_process(false)
	game.ui.visible = false
	camera = Camera3D.new()
	camera.far = 950
	camera.fov = 64
	add_child(camera)
	game.player.position = Vector3(0, 0.05, 58)
	var weather_only := "--weather-only" in OS.get_cmdline_user_args()
	if not weather_only:
		await capture("01-city-river-overview", Vector3(168, 146, 194), Vector3(0, 9, 15))
		await capture("02-three-bridges", Vector3(118, 13, 68), Vector3(-35, 0, 34))
		await capture("03-street-towers", Vector3(-4, 4.8, 143), Vector3(-22, 24, -100))
		await capture("04-hillside", Vector3(82, 7, 136), Vector3(38, 3, 101))
		game.player.position = Vector3(0, 0.05, 56)
		game.player.toggle_camera()
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		game.player.camera.make_current()
		game.ui.visible = true
		game.ui.update_snapshot(game.get_ui_snapshot())
		await frames(20)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("05-playable-bridge-chase.png"))
		game.ui.visible = false
	game.arena.set_weather_kind("heavy_rain")
	await capture("06-rain-river", Vector3(25, 6, 63), Vector3(-7, 0, 22))
	game.arena.set_weather_kind("snow")
	await capture("07-snow-hillside", Vector3(82, 8, 136), Vector3(38, 3, 101))
	game.free()
	print("WORLD_VISUAL_RESULT: %d captures" % (2 if weather_only else 7))
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0)
