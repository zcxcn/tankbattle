extends SceneTree
## Headless construction smoke test: run with --script res://ui/game_ui_smoke_test.gd.

const GameUIScript = preload("res://ui/game_ui.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var requested_size := Vector2i.ZERO
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-size="):
			var dimensions := argument.trim_prefix("--ui-size=").split("x")
			if dimensions.size() == 2:
				requested_size = Vector2i(maxi(640, int(dimensions[0])), maxi(360, int(dimensions[1])))
	await process_frame
	if requested_size != Vector2i.ZERO and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(requested_size)
		root.size = requested_size
		await process_frame
	var ui := GameUIScript.new() as GameUI
	root.add_child(ui)
	await process_frame
	assert(ui.get_node("TitleLayer").visible)
	var render_ui := "--render-ui" in OS.get_cmdline_user_args()
	var render_directory := OS.get_temp_dir().path_join("iron-embers-ui-test")
	if render_ui:
		DirAccess.make_dir_recursive_absolute(render_directory)
	for mode: String in ["playing", "paused", "settings", "won", "lost", "title"]:
		ui.update_snapshot({
			"mode": mode,
			"hp": 73.0,
			"max_hp": 120.0,
			"armor": 48,
			"kills": 4,
			"target_kills": 6,
			"score": 8450,
			"time": 94.2,
			"mine_ammo": 5,
			"mine_cooldown": 1.2,
			"emp_cooldown": 4.5,
			"dash_cooldown": 0.0,
			"weapon": "加农炮",
			"reload": 0.8,
			"boss_name": "铁牙",
			"boss_hp": 640.0,
			"boss_max_hp": 1000.0,
			"boss_phase": 2,
			"boss_warning": true,
			"objective": "歼灭守军并击毁铁牙",
			"notice": "敌军正在布设地雷",
			"lifetime_kills": 17,
			"tank_level": 4,
			"best_score": 12000,
			"display_mode": 1,
			"quality": 2,
			"fps_cap": 120,
			"vsync": true,
			"shake": true,
		})
		await process_frame
		await process_frame
		match mode:
			"playing":
				assert(ui.get_node("BattleHUD").visible)
			"paused":
				assert(ui.get_node("PauseLayer").visible)
			"settings":
				assert(ui.get_node("SettingsLayer").visible)
			"won", "lost":
				assert(ui.get_node("ResultLayer").visible)
			"title":
				assert(ui.get_node("TitleLayer").visible)
		if render_ui:
			var image := root.get_texture().get_image()
			var output := render_directory.path_join("game-ui-%dx%d-%s.png" % [root.size.x, root.size.y, mode])
			assert(image.save_png(output) == OK)
			print("GameUI render: %s" % output)
	ui.queue_free()
	await process_frame
	print("GameUI smoke test passed")
	quit(0)
