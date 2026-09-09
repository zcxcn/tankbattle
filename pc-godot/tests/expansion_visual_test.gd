extends SceneTree
## GPU review frames from the real game. Fixtures position the camera/vehicles;
## all terrain, lights, HUD and weapon effects use production implementations.

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
	root.get_texture().get_image().save_png(path)
	print("RENDER_CAPTURE: " + path)

func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/expansion-0.3.0")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/expansion_visual")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	await frames(12)
	var quick := "--quick" in OS.get_cmdline_user_args()
	if not quick:
		await capture("title")
	for mission in ([1] if quick else [0, 1, 2]):
		game.selected_mission = mission
		game.selected_chassis = mission
		game.start_game()
		for tank in get_nodes_in_group("tanks"):
			tank.set_physics_process(false)
		game.player.position = Vector3(0, 0.05, 142)
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		await frames(12)
		game.notice = ""
		game.notice_time = 0
		await capture("mission-%d-tactical" % (mission + 1))
		game.player.toggle_camera()
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		await frames(24)
		game.notice = ""
		game.notice_time = 0
		await frames(2)
		await capture("mission-%d-chase" % (mission + 1))
		for slot in (0 if quick else 4):
			game.player.select_weapon(slot)
			game.player._loadout.tick(10.0)
			game.player.reload = 0.0
			game.player.aim_point = Vector3(0, 1.2, 108)
			game.player._update_turret(1.0)
			game.player.try_fire()
			game.ui.update_snapshot(game.get_ui_snapshot())
			await capture("mission-%d-weapon-%d" % [mission + 1, slot + 1])
			await frames(12)
		# Use open roadway; a living fixture tank must not occlude the effect.
		game.spawn_explosion(Vector3(5.5, 0.7, 127), 1.0)
		await frames(18)
		await capture("mission-%d-explosion" % (mission + 1))
		print("RENDER_METRICS: mission=%d fps=%d draws=%d primitives=%d" % [mission + 1, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	game.free()
	await frames(3)
	print("EXPANSION_VISUAL_COMPLETE")
	quit()
