extends SceneTree
## Short uncapped render/physics benchmark with live AI and populated track pools.
## Run without --fixed-fps. Screenshots and file IO occur outside sample windows.

var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in count:
		await process_frame

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	await frames(3)
	var settings: Node = root.get_node("SettingsService")
	settings.quality = 1
	settings._apply_quality()
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.get_node("SaveService").set("_directory", "user://tests/weather_tracks_benchmark_042")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	var results: Array[Dictionary] = []
	for chapter in [0, 4]:
		game.selected_mission = chapter
		game.set_meta("deployment_seed", 40910 + chapter)
		game.start_game()
		game.player.position = Vector3(0, 0.05, 142)
		game.player.invulnerable = 9999.0
		game.player.set_process_input(false)
		game.player.toggle_camera()
		game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
		await physics_frame
		await physics_frame
		var marks: Node = game.arena.get_node("TrackMarks")
		# Real terrain projection populates the visible avenue with synthetic
		# print histories; current vehicles still run their normal AI/physics.
		for index in 150:
			var at := Vector3(-6.0 + float(index % 5) * 3.0, 0.05, 135.0 - float(index / 5) * 1.25)
			marks.sample_vehicle(10000 + index, Transform3D(Basis.IDENTITY, at), true, index % 3 == 0)
			marks.sample_vehicle(10000 + index, Transform3D(Basis.IDENTITY, at + Vector3.FORWARD * 0.8), true, index % 3 == 0)
		var warm_started := Time.get_ticks_msec()
		await frames(12)
		if Time.get_ticks_msec() - warm_started > 10000:
			print("WEATHER_TRACKS_PERFORMANCE_UNAVAILABLE: rendering is throttled; discard this run")
			game.free()
			await preload("res://tests/test_shutdown.gd").finish(self, 2)
			return
		await frames(78)
		var samples: Array[float] = []
		var physics_total := 0.0
		var draws_total := 0.0
		var last := Time.get_ticks_usec()
		for index in 240:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - last) / 1000.0)
			last = now
			physics_total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			draws_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var sum := 0.0
		for sample in samples:
			sum += sample
		samples.sort()
		var result := {"chapter": chapter + 1, "weather": game.mission_data.weather,
			"window": [root.size.x, root.size.y], "render_scale": root.scaling_3d_scale,
			"quality": settings.quality, "samples": samples.size(), "average_fps": 240000.0 / sum,
			"p95_frame_ms": samples[227], "mean_physics_ms": physics_total / 240.0,
			"mean_draw_calls": draws_total / 240.0, "tracks": marks.get_snapshot(),
			"vehicles": get_nodes_in_group("tanks").size(), "mode": game.mode}
		results.append(result)
		print("WEATHER_TRACKS_PERFORMANCE: " + JSON.stringify(result))
	var directory := ProjectSettings.globalize_path("res://../work/asset-review/pc-0.4.2")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("performance.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(),
		"method": "1080p medium, uncapped/VSync off, stationary invulnerable player, live AI, synthetic print histories projected onto real terrain, 90 warmup + 240 sample frames; no captures or file writes during samples. Different chapters are separate workloads, not a controlled weather on/off comparison.",
		"results": results}, "\t"))
	file.close()
	game.free()
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
