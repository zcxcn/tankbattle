extends Node
var game: Node3D
var camera: Camera3D
var directory := ""

func _ready() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	for frame in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
	assert(result == OK)
	print("SIEGE_BEAST_CAPTURE: ", label, " fps=", Engine.get_frames_per_second())

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
	SaveService._directory = "user://tests/siege_beasts_visual_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	directory = ProjectSettings.globalize_path("res://../work/asset-review/siege-beasts-0.4.9")
	DirAccess.make_dir_recursive_absolute(directory)
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.start_endless()
	game.endless.set_physics_process(false)
	game.player.set_physics_process(false)
	var cast: Array[Node3D] = []
	var roles := ["shambler", "forest", "reaver", "kaiju"]
	var positions := [Vector3(-12,0.1,8),Vector3(-32,0.1,-28),Vector3(34,0.1,-28),Vector3(4,0.1,-73)]
	for index in roles.size():
		var actor := preload("res://actors/giant_monster.gd").new()
		actor.game = game
		actor.director = game.endless
		actor.archetype = roles[index]
		actor.position = positions[index]
		actor.rotation.y = PI
		game.add_child(actor)
		actor.set_physics_process(false)
		actor._tick_walk(0.7)
		game.endless.monsters.append(actor)
		cast.append(actor)
	game.notice = ""
	game.endless.wave = 2
	game.player._camera_pivot.pitch = 0.13
	game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
	await capture("01-playable-city-giants")
	camera = Camera3D.new()
	camera.far = 680
	camera.fov = 62
	add_child(camera)
	camera.position = Vector3(-3, 5, 72)
	camera.look_at(Vector3(1, 27, -55))
	camera.make_current()
	game.ui.visible = false
	await capture("02-city-scale")
	camera.position = Vector3(-25, 18, -24)
	camera.look_at(cast[3].position + Vector3(0, 27, 0))
	await capture("03-kaiju-detail")
	cast[3].receive_damage(100000,0)
	cast[2].visible = false
	for frame in 260:
		cast[3]._tick_corpse(1.0/60.0)
		await get_tree().process_frame
	camera.position = Vector3(43,31,-4)
	camera.look_at(Vector3(3,7,-65))
	await capture("04-kaiju-collapse")
	game.free()
	print("SIEGE BEAST VISUAL: 4 captures")
	await preload("res://tests/test_shutdown.gd").finish(get_tree())
