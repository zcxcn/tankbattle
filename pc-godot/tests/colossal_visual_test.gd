extends Node
var game: Node3D
var camera: Camera3D
var directory := ""

func _ready() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	for frame in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
	assert(result == OK)
	print("COLOSSAL_CAPTURE: ", label)

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
	SaveService._directory = "user://tests/colossal_visual_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	directory = ProjectSettings.globalize_path("res://../work/asset-review/colossal-0.4.10")
	DirAccess.make_dir_recursive_absolute(directory)
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.start_endless()
	game.endless.set_physics_process(false)
	game.player.set_physics_process(false)
	var cast: Array[Node3D] = []
	var roles := ["glutton", "golem", "juggernaut"]
	var positions := [Vector3(-26, 0.1, -12), Vector3(30, 0.1, -25), Vector3(-10, 0.1, -94)]
	for index in roles.size():
		var monster := preload("res://actors/giant_monster.gd").new()
		monster.game = game
		monster.director = game.endless
		monster.archetype = roles[index]
		monster.position = positions[index]
		monster.rotation.y = PI
		game.add_child(monster)
		monster.set_physics_process(false)
		monster._tick_walk(0.7)
		game.endless.monsters.append(monster)
		cast.append(monster)
	game.notice = ""
	game.endless.wave = 4
	game.player._camera_pivot.pitch = 0.23
	game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
	await capture("01-playable-giants")
	camera = Camera3D.new()
	camera.far = 680
	camera.fov = 65
	add_child(camera)
	camera.position = Vector3(-40, 18, 35)
	camera.look_at(cast[0].position + Vector3.UP * 17)
	camera.make_current()
	game.ui.visible = false
	await capture("02-glutton-detail")
	camera.position = Vector3(8, 27, 43)
	camera.look_at(cast[1].position + Vector3.UP * 25)
	await capture("03-golem-detail")
	cast[2].receive_damage(100000, 0)
	cast[0].visible = false
	cast[1].visible = false
	for frame in 290:
		cast[2]._tick_corpse(1.0 / 60.0)
		await get_tree().process_frame
	camera.position = Vector3(40, 52, -12)
	camera.look_at(Vector3(-10, 8, -92))
	await capture("04-colossus-collapse")
	game.free()
	print("COLOSSAL VISUAL COMPLETE: 4 captures")
	await preload("res://tests/test_shutdown.gd").finish(get_tree())
