extends SceneTree
## GPU-only production road projection and curved dual-track review.
## Run with --fixed-fps 60 -- --test. Captures are not performance benchmarks.

var game: Node3D
var directory := ""


func _initialize() -> void:
	call_deferred("_run")


func frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := directory.path_join(label + ".png")
	print("TRACK_CAPTURE: %s error=%d" % [path, root.get_texture().get_image().save_png(path)])


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	directory = ProjectSettings.globalize_path("res://../work/asset-review/tracks-0.4.2")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("SaveService").set("_directory", "user://tests/tracks_visual_042")
	root.get_node("SaveService").reset_for_tests()
	root.get_node("SettingsService").weather_mode = 1
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.set_meta("deployment_seed", 40910)
	game.start_game()
	game.set_process(false)
	game.ui.hide()
	for tank in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	var marks: Node3D = game.arena.get_node_or_null("TrackMarks")
	if marks == null:
		marks = load("res://scripts/track_marks.gd").new()
		marks.game = game
		game.arena.add_child(marks)
	marks.set_physics_process(false)
	marks.clear_marks()
	await frames(3)
	var pose := Transform3D.IDENTITY
	for step in 34:
		pose.origin = Vector3(0, 0.01, 166.0 - float(step) * 0.8)
		marks.sample_vehicle(991, pose, true, true)
	for step in 17:
		var turn := float(step) * PI * 0.5 / 16.0
		pose = Transform3D(Basis(Vector3.UP, -turn), Vector3(8.0 - 8.0 * cos(turn), 0.01, 139.6 - 8.0 * sin(turn)))
		marks.sample_vehicle(991, pose, true, true)
	game.player.global_transform = pose
	game.player.aim_point = game.player.position + Vector3(50, 1, 0)
	game.player._update_turret(2.0)
	var camera := Camera3D.new()
	camera.fov = 51.0
	camera.near = 0.05
	game.add_child(camera)
	camera.current = true
	camera.position = Vector3(19, 17, 155)
	camera.look_at(Vector3(2, 0.1, 143))
	await frames(8)
	await capture("01-dry-road-curved-tracks")
	camera.position = Vector3(4.5, 5.5, 153)
	camera.look_at(Vector3(0.0, 0.08, 145))
	await frames(4)
	await capture("02-dry-tread-closeup")
	marks.set_wetness(1.0)
	marks.advance_time(0.3)
	await frames(4)
	await capture("03-wet-tread-closeup")
	var file := FileAccess.open(directory.path_join("track-budget.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(marks.get_snapshot(), "  "))
	file.close()
	game.free()
	await frames(3)
	print("TRACK_VISUAL_COMPLETE")
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
