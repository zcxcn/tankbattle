extends SceneTree
## Production wreck and ammunition fire at their true scale in both cameras.
## GPU visual review only: --fixed-fps 60 --script ... -- --test

var game: Node3D
var directory := ""


func _initialize() -> void:
	call_deferred("_run")


func frames(count: int) -> void:
	for tick in count:
		await process_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := directory.path_join(label + ".png")
	var result := root.get_texture().get_image().save_png(path)
	print("COOKOFF_CAPTURE: %s error=%d" % [path, result])


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		await preload("res://tests/test_shutdown.gd").finish(self, 2)
		return
	var rainy := "--rain" in OS.get_cmdline_user_args()
	root.get_node("SettingsService").set("weather_mode", 3 if rainy else 1)
	directory = ProjectSettings.globalize_path("res://../work/asset-review/cookoff-0.4.2" + ("-rain" if rainy else ""))
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/cookoff_visual_042")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	await frames(6)
	game.set_meta("deployment_seed", 40910)
	game.selected_mission = 4 if rainy else 0
	game.start_game()
	var source: Node3D
	var wreck_script := load("res://actors/tank_wreck.gd")
	for tank: Node3D in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
		if not tank.is_player:
			tank.hide()
			if source == null:
				source = tank
	game.player.position = Vector3(0, 0.05, 142)
	game.player.aim_point = Vector3(0, 1.5, 124)
	game.player._update_turret(1.0)
	source.position = Vector3(0, 0.05, 124)
	source.aim_point = Vector3(0, 1.5, 105)
	source._update_turret(1.0)
	source.destroyed = true
	for view in ["tactical", "chase"]:
		# Keep the entire 10 m upward jet in the tactical frame. The chase
		# view has a longer forward sightline and demonstrates its true height.
		source.position.z = 132.0 if view == "tactical" else 124.0
		game.player._camera_pivot.set_third_person(view == "chase")
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		var wreck: Node3D = wreck_script.create_from_tank(source, 2, 1)
		wreck.cookoff_time = 100.0
		game.add_child(wreck)
		await frames(250)
		await capture(view + "-01-ammunition-burning")
		wreck._detonate()
		await frames(8)
		await capture(view + "-02-pressure-jet")
		await frames(19)
		await capture(view + "-03-turret-ejection")
		await frames(30)
		await capture(view + "-04-rising-fire")
		await frames(60)
		await capture(view + "-05-smoke-and-debris")
		for effect: Node in get_nodes_in_group("combat_effects"):
			if effect.is_in_group("tank_wrecks") or effect.is_in_group("blast_fx") or effect.is_in_group("impact_fx") or effect.is_in_group("muzzle_fx"):
				effect.free()
		await frames(3)
	game.free()
	await frames(3)
	print("COOKOFF_VISUAL_COMPLETE: 10 captures")
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
