extends SceneTree
## Uncapped real-time GPU benchmark. Never captures pixels or writes files during samples.

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 240
var game: Node3D
var report_path := ""
var results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for frame in range(count):
		await process_frame


func _summary(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in samples:
		total += sample
	return {
		"mean": total / float(samples.size()),
		"median": sorted[sorted.size() / 2],
		"p95": sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)],
		"max": sorted.back(),
	}


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("GPU benchmark requires a rendering backend and -- --test")
		quit(2)
		return
	await _frames(3) # Allow the settings autoload's deferred apply to finish first.
	var saves := root.get_node("SaveService")
	saves.set("_directory", "user://tests/campaign_performance")
	saves.reset_for_tests()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_title("Iron Embers 0.4 Performance")
	DisplayServer.window_move_to_foreground()
	report_path = ProjectSettings.globalize_path("res://../work/asset-review/expansion-0.4.0/performance-baseline.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.set_process_unhandled_input(false)
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	var measured_times := RenderingServer.has_method("viewport_set_measure_render_time")
	if measured_times:
		RenderingServer.call("viewport_set_measure_render_time", root.get_viewport_rid(), true)
	var settings := root.get_node("SettingsService")
	for profile in [{"label": "1440p_high", "size": Vector2i(2560, 1440), "quality": 2}, {"label": "1080p_medium", "size": Vector2i(1920, 1080), "quality": 1}]:
		# Apply only runtime quality, so no user settings or window preferences are saved.
		settings.quality = profile.quality
		settings._apply_quality()
		DisplayServer.window_set_size(profile.size)
		DisplayServer.window_move_to_foreground()
		await _frames(3)
		for mission in range(6):
			game.selected_mission = mission
			game.selected_chassis = 1
			game.set_meta("deployment_seed", 40910 + mission)
			game.start_game()
			game.player.position = Vector3(0, 0.05, 142)
			game.player.invulnerable = 9999.0
			game.player.set_process_input(false)
			game.player.toggle_camera()
			game.player._camera_pivot.update_view(1.0, Vector3.ZERO)
			game.notice = ""
			game.notice_time = 0.0
			if mission == 5:
				# Additional corpses preserve the full live roster while testing the cap.
				for index in 14:
					var wreck = load("res://actors/tank_wreck.gd").create_from_tank(game.enemies[index], index % 3, 0)
					game.add_child(wreck)
					wreck.position = Vector3(-5.0 if index % 2 == 0 else 5.0, 0.05, 125.0 - floorf(index / 2.0) * 12.0)
			await _frames(WARMUP_FRAMES)
			print("PERFORMANCE_STATE: focused=%s window_mode=%d max_fps=%d low_processor=%s" % [root.has_focus(), DisplayServer.window_get_mode(), Engine.max_fps, OS.low_processor_usage_mode])
			var frame_ms: Array[float] = []
			var cpu_ms: Array[float] = []
			var gpu_ms: Array[float] = []
			var draw_calls: Array[float] = []
			var primitives: Array[float] = []
			var physics_ms: Array[float] = []
			var process_ms: Array[float] = []
			var last_tick := Time.get_ticks_usec()
			for frame in range(SAMPLE_FRAMES):
				await process_frame
				var now := Time.get_ticks_usec()
				frame_ms.append(float(now - last_tick) / 1000.0)
				last_tick = now
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
				process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
				if measured_times:
					cpu_ms.append(float(RenderingServer.call("viewport_get_measured_render_time_cpu", root.get_viewport_rid())))
					gpu_ms.append(float(RenderingServer.call("viewport_get_measured_render_time_gpu", root.get_viewport_rid())))
			var summary := _summary(frame_ms)
			var result := {
				"profile": profile.label, "mission": mission + 1, "mission_name": game.mission_data.name,
				"window_size": [root.size.x, root.size.y], "render_scale": root.scaling_3d_scale,
				"msaa": root.msaa_3d, "warmup_frames": WARMUP_FRAMES, "sample_frames": SAMPLE_FRAMES,
				"frame_ms": summary, "average_fps": 1000.0 / float(summary.mean),
				"draw_calls": _summary(draw_calls), "primitives": _summary(primitives),
				"physics_ms": _summary(physics_ms), "process_ms": _summary(process_ms),
				"cpu_render_ms": _summary(cpu_ms) if measured_times else {},
				"gpu_render_ms": _summary(gpu_ms) if measured_times else {},
				"player_position": [game.player.position.x, game.player.position.y, game.player.position.z],
				"game_mode": game.mode,
				"live_vehicles": get_nodes_in_group("tanks").size(), "wrecks": get_nodes_in_group("tank_wrecks").size(),
			}
			results.append(result)
			print("PERFORMANCE_SAMPLE: " + JSON.stringify(result))
	var report := {
		"method": "Real-time, uncapped, VSync disabled; live AI; stationary invulnerable player; third-person view at (0,142); 60 warm-up and 240 measured frames; no screenshots or disk IO inside sampling loops; same player chassis in all chapters. Final chapter retains all 24 live vehicles and adds 14 wrecks along the viewed road to measure retained aftermath cost.",
		"gpu": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info(),
		"results": results,
	}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	game.free()
	await _frames(3)
	print("CAMPAIGN_PERFORMANCE_COMPLETE: " + report_path)
	await preload("res://tests/test_shutdown.gd").finish(self, 0)
