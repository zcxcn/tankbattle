extends Node
## Production renderer capture: game geometry, authored animation and real UI.
var game: Node3D
var camera: Camera3D
var directory := ""

func _ready() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame

func capture(label: String) -> void:
	await frames(12)
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK)
	print("ENDLESS_CAPTURE: %s draws=%d primitives=%d fps=%d" % [label, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Engine.get_frames_per_second()])

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	SettingsService.display_mode = 0
	SettingsService.resolution = Vector2i(1600, 900)
	SettingsService.quality = 2
	SettingsService.weather_mode = 1
	SettingsService.remote_mouse = true
	SettingsService.apply()
	SaveService.set("_directory", "user://tests/endless_visual_%d" % OS.get_process_id())
	SaveService.reset_for_tests()
	directory = ProjectSettings.globalize_path("res://../work/asset-review/endless-0.4.8")
	DirAccess.make_dir_recursive_absolute(directory)
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	await frames(60)
	await capture("01-mode-menu")
	game.start_endless()
	game.endless.begin_wave()
	game.endless.set_physics_process(false)
	for index in 3:
		game.endless.spawn_monster()
	game.endless.wave = 3
	game.endless._elite_pending = 1
	game.endless.spawned = 10
	var titan: Node3D = game.endless.spawn_monster()
	if titan != null:
		titan.position = Vector3(10, 0.1, -10)
	for index in game.endless.monsters.size():
		var monster: Node3D = game.endless.monsters[index]
		if monster != titan:
			monster.position = Vector3(-30 + index * 22, 0.1, -20 - index * 18)
	game.player.set_physics_process(false)
	game.player._camera_pivot.pitch = -0.035
	game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
	game.notice = ""
	await frames(130)
	await capture("02-playable-giants")
	camera = Camera3D.new()
	camera.far = 680
	camera.fov = 61
	add_child(camera)
	camera.position = Vector3(-9, 3.2, 18)
	camera.look_at(Vector3(9, 9, -8))
	camera.make_current()
	game.ui.visible = false
	await capture("03-giant-scale")
	# Exercise the actor's authored/procedural death sequence, not a posed mesh.
	if titan != null:
		titan.receive_damage(100000, 0, titan.global_position + Vector3.UP * 8, "cannon")
		await frames(95)
		await capture("04-collapsed-giant")
	game.player.camera.make_current()
	game.ui.visible = true
	game.endless.upgrades.add_reward(350)
	game.pause_game()
	game.ui.update_snapshot(game.get_ui_snapshot())
	await capture("05-upgrade-workshop")
	game._buy_endless_upgrade("firepower")
	game._buy_endless_upgrade("autoloader")
	await capture("06-purchased-upgrades")
	game.free()
	print("ENDLESS_VISUAL_RESULT: 6 captures")
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0)
