extends SceneTree
## Production firing effects in both camera modes. Run with --fixed-fps 60
## and -- --test. Screenshots are visual evidence, never FPS benchmarks.

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
	print("MUZZLE_CAPTURE: %s error=%d" % [path, result])


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/muzzle-0.4.1")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/muzzle_visual_041")
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
	for view in ["tactical", "chase"]:
		if view == "chase":
			game.player.toggle_camera()
			game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
			await frames(18)
		for slot in 4:
			game.player.select_weapon(slot)
			game.player._loadout.tick(10.0)
			game.player.reload = 0.0
			game.player.aim_point = Vector3(0, 1.5, 108)
			game.player._update_turret(1.0)
			game.player.try_fire()
			game.ui.update_snapshot(game.get_ui_snapshot())
			await capture("%s-weapon-%d-flash" % [view, slot + 1])
			await frames(3)
			await capture("%s-weapon-%d-gas" % [view, slot + 1])
			await frames(12)
			if slot < 2:
				await capture("%s-weapon-%d-smoke" % [view, slot + 1])
			await frames(80)
	game.free()
	await frames(3)
	print("MUZZLE_VISUAL_COMPLETE")
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
