extends SceneTree
## Production effects rendered at real scale. --record adds a 30 fps cookoff
## frame sequence; screenshots and recording are visual evidence, not benchmarks.

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
	print("FLUID_FX_CAPTURE: %s error=%d" % [path, result])


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		await preload("res://tests/test_shutdown.gd").finish(self, 2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/fluid-0.4.3")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 720)
	root.get_node("SettingsService").set("weather_mode", 1)
	root.get_node("SaveService").set("_directory", "user://tests/fluid_visual_043")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	await frames(6)
	game.set_meta("deployment_seed", 40910)
	game.start_game()
	var source: Node3D
	var wreck_script := load("res://actors/tank_wreck.gd")
	var fx_script := load("res://actors/explosion_fx.gd")
	for tank: Node3D in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
		if not tank.is_player:
			tank.hide()
			if source == null:
				source = tank
	game.player.position = Vector3(0, 0.05, 142)
	game.player.aim_point = Vector3(0, 1.5, 122)
	game.player._update_turret(1.0)
	source.position = Vector3(0, 0.05, 122)
	source.aim_point = Vector3(0, 1.5, 105)
	source._update_turret(1.0)
	source.destroyed = true
	var quick := "--quick" in OS.get_cmdline_user_args()
	for view in (["chase"] if quick else ["tactical", "chase"]):
		source.position.z = 132.0 if view == "tactical" else 122.0
		game.player._camera_pivot.set_third_person(view == "chase")
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		for profile in ["he", "destruction", "cookoff"]:
			var wreck: Node3D = wreck_script.create_from_tank(source, 2, 0)
			game.add_child(wreck)
			await frames(80 if quick else 260)
			if profile == "he":
				game.add_child(fx_script.create_impact(source.position + Vector3(5.0, 0.06, 0), true, "ground", Vector3.UP, "he"))
			elif profile == "destruction":
				game.add_child(fx_script.create(source.position + Vector3.UP * 0.9))
			else:
				wreck._detonate()
			var previous := 0
			for target in [6, 18, 36, 72, 144, 240]:
				await frames(target - previous)
				await capture("%s-%s-%03d" % [view, profile, target])
				previous = target
			_cleanup()
			await frames(3)
	if "--record" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(directory.path_join("recording"))
		var wreck: Node3D = wreck_script.create_from_tank(source, 2, 0)
		game.add_child(wreck)
		await frames(260)
		wreck._detonate()
		for index in 150:
			await frames(2)
			await capture("recording/frame-%04d" % index)
	game.free()
	await frames(3)
	print("FLUID_VISUAL_COMPLETE: %d review frames" % (18 if quick else 36))
	await preload("res://tests/test_shutdown.gd").finish(self, 0)


func _cleanup() -> void:
	for effect: Node in get_nodes_in_group("combat_effects"):
		if effect.is_in_group("tank_wrecks") or effect.is_in_group("blast_fx") or effect.is_in_group("impact_fx") or effect.is_in_group("muzzle_fx"):
			effect.free()
