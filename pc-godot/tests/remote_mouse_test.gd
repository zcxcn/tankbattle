extends Node
## Exercise absolute-only remote events through the viewport and real battle UI.
## Optional --visual writes GPU screenshots; it never modifies player settings.

var passed := 0
var failed := 0
var game: Node3D
var visual := false
var directory := ""

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func motion(at: Vector2, relative := Vector2.ZERO, screen_relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.screen_relative = screen_relative
	get_viewport().push_input(event, true)

func f8() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F8
		event.keycode = KEY_F8
		event.pressed = pressed
		get_viewport().push_input(event, true)

func tactical_motion(at: Vector2) -> void:
	# Tactical code polls Input's pointer rather than storing event.position;
	# parse_input_event updates that global state before viewport dispatch.
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func stick(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_RIGHT_X
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func capture(label: String) -> void:
	if not visual:
		return
	game.ui.update_snapshot(game.get_ui_snapshot())
	await frames(3)
	await RenderingServer.frame_post_draw
	var output := directory.path_join(label + ".png")
	var result := get_viewport().get_texture().get_image().save_png(output)
	check(result == OK, "GPU screenshot saved: " + label)
	print("REMOTE_MOUSE_CAPTURE: " + output)

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	await frames(3)
	visual = "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	directory = ProjectSettings.globalize_path("res://../work/asset-review/remote-mouse-0.4.6")
	if visual:
		DirAccess.make_dir_recursive_absolute(directory)
	var settings := get_node("/root/SettingsService")
	check(not settings.remote_mouse, "a private fresh config preserves standard local mouse control")
	settings.display_mode = 0
	settings.resolution = Vector2i(1280, 720)
	settings.quality = 1
	settings.weather_mode = 1
	settings.screen_shake = false
	settings.apply()
	var save := get_node("/root/SaveService")
	save.set("_directory", "user://tests/remote_mouse_%d" % OS.get_process_id())
	save.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	game.start_game()
	game.set_process(false)
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	var player = game.player
	player.set_process(false)
	player.position = Vector3(0.0, 0.05, 142.0)
	player.toggle_camera()
	var rig = player._camera_pivot
	rig.update_view(1.0, Vector3.ZERO)
	await get_tree().physics_frame
	await frames(2)
	var bounds := get_viewport().get_visible_rect()
	var center := bounds.get_center()
	var point_a := bounds.position + bounds.size * Vector2(0.62, 0.45)
	var point_b := bounds.position + bounds.size * Vector2(0.39, 0.53)
	var edge := bounds.position + bounds.size * Vector2(0.985, 0.5)
	f8()
	check(settings.remote_mouse and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_HIDDEN), "F8 enables remote aiming without capture or pointer warping")
	motion(point_a)
	game._update_mouse_aim()
	var first_aim: Vector3 = player.aim_point
	check(rig.aim_screen_point().distance_to(point_a) < 0.01 and player.camera.unproject_position(first_aim).distance_to(point_a) < 1.0, "pure absolute position with zero relative deltas drives the actual third-person aiming ray")
	motion(point_b)
	game._update_mouse_aim()
	check(player.aim_point.distance_to(first_aim) > 2.0, "moving an absolute-only pointer changes the world target")
	var snapshot: Dictionary = game.get_ui_snapshot()
	check(snapshot.aim_visible and Vector2(snapshot.aim_screen).distance_to(point_b) < 1.0, "the existing HUD receives a freely moving reticle from the real world target")
	var stationary_yaw: float = rig.yaw
	var stationary_pitch: float = rig.pitch
	for frame in 30:
		player._player_control(1.0 / 60.0)
	check(is_equal_approx(rig.yaw, stationary_yaw) and is_equal_approx(rig.pitch, stationary_pitch), "absolute aiming inside the central area does not rotate the camera")
	motion(edge)
	player._player_control(1.0 / 60.0)
	var edge_yaw: float = rig.yaw
	check(edge_yaw < stationary_yaw - 0.01, "a pointer near the right edge starts turning through real player controls")
	for frame in 30:
		player._player_control(1.0 / 60.0)
	check(rig.yaw < edge_yaw - 0.5, "holding the pointer at the edge keeps turning without further motion events")
	motion(center)
	stationary_yaw = rig.yaw
	for frame in 12:
		player._player_control(1.0 / 60.0)
	check(is_equal_approx(rig.yaw, stationary_yaw), "returning the pointer to the center stops continuous turning")
	motion(edge)
	motion(bounds.end + Vector2(15.0, 0.0))
	player._player_control(0.1)
	check(is_equal_approx(rig.yaw, stationary_yaw) and rig.aim_screen_point().is_equal_approx(center), "leaving the viewport stops turning and removes an invalid offscreen target")
	motion(edge)
	# Windows may send only WM_MOUSELEAVE, with no final out-of-bounds motion.
	# Emit the real Window signal to exercise the production connection.
	game.get_window().mouse_exited.emit()
	for frame in 18:
		player._player_control(1.0 / 60.0)
	check(game.mode == "playing" and is_equal_approx(rig.yaw, stationary_yaw) and rig.aim_screen_point().is_equal_approx(center), "a window mouse-exit signal alone stops stale edge turning without pausing combat")
	motion(point_a)
	game._update_mouse_aim()
	check(rig.aim_screen_point().is_equal_approx(point_a), "the first absolute input after reentering the window restores remote targeting")
	motion(edge)
	stick(0.8)
	player._player_control(1.0 / 60.0)
	var gamepad: Node = game.get_node("GamepadInput")
	check(gamepad.using_controller and rig.aim_screen_point().is_equal_approx(center), "right-stick input takes priority and returns remote aiming to the center")
	stick(0.0)
	stationary_yaw = rig.yaw
	player._player_control(0.1)
	check(is_equal_approx(rig.yaw, stationary_yaw), "releasing the right stick does not resurrect stale edge turning")
	motion(edge)
	player._player_control(0.1)
	check(gamepad.using_controller and rig.aim_screen_point().is_equal_approx(center) and is_equal_approx(rig.yaw, stationary_yaw), "an unchanged absolute coordinate does not steal control back from the gamepad")
	motion(point_a)
	game._update_mouse_aim()
	check(not gamepad.using_controller and rig.aim_screen_point().is_equal_approx(point_a), "a real absolute pointer change takes aiming and HUD device hints back from the controller")
	motion(edge)
	game.pause_game()
	motion(point_b)
	player._physics_process(0.1)
	check(game.mode == "paused" and is_equal_approx(rig.yaw, stationary_yaw) and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE), "pause releases the pointer and blocks remote camera movement")
	game.resume_game()
	player._player_control(0.1)
	check(rig.aim_screen_point().is_equal_approx(center) and is_equal_approx(rig.yaw, stationary_yaw), "resume waits for new absolute input rather than turning from the menu cursor")
	motion(point_a)
	game._update_mouse_aim()
	check(rig.aim_screen_point().is_equal_approx(point_a), "the first real pointer movement after resume restores remote targeting")
	game._on_focus_lost()
	check(game.mode == "paused" and game.pause_reason == "focus_lost" and rig.aim_screen_point().is_equal_approx(center), "the production focus-loss handler pauses and clears remote edge state")
	game.open_settings()
	game.ui.update_snapshot(game.get_ui_snapshot())
	var remote_button: Button = game.ui._setting_buttons["remote_mouse"]
	var player_id: int = player.get_instance_id()
	check(remote_button.is_visible_in_tree() and remote_button.text.contains("远程"), "remote input preference is visible in the actual settings menu")
	await capture("settings-remote-mouse")
	remote_button.pressed.emit()
	check(not settings.remote_mouse and game.mode == "settings" and game.player.get_instance_id() == player_id, "the settings button toggles remote input without replacing the paused battle")
	remote_button.pressed.emit()
	settings.remote_mouse = false
	settings.load_settings()
	check(settings.remote_mouse, "the selected remote mouse preference survives a config reload")
	var legacy := ConfigFile.new()
	legacy.set_value("gameplay", "screen_shake", false)
	legacy.save(settings.config_path)
	settings.load_settings()
	check(not settings.remote_mouse, "an older settings file without remote_mouse keeps local input as default")
	settings.remote_mouse = true
	settings.save_settings()
	game._close_settings()
	game.resume_game()
	rig.yaw = 0.0
	rig.pitch = -0.18
	rig.update_view(1.0, Vector3.ZERO)
	motion(point_a)
	game._update_mouse_aim()
	player._update_turret(1.0)
	await capture("chase-absolute-reticle")
	f8()
	check(not settings.remote_mouse and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "F8 restores the original captured local third-person mode")
	stationary_yaw = rig.yaw
	motion(center, Vector2.ZERO, Vector2(24.0, 0.0))
	check(absf(angle_difference(stationary_yaw, rig.yaw) + 24.0 * 0.0023) < 0.00001, "screen-relative local mouse motion still rotates with its original sensitivity")
	stationary_yaw = rig.yaw
	motion(center, Vector2(15.0, 0.0))
	check(absf(angle_difference(stationary_yaw, rig.yaw) + 15.0 * 0.0023) < 0.00001, "the original relative-only backend fallback still rotates the camera")
	player.toggle_camera()
	rig.update_view(1.0, Vector3.ZERO)
	if DisplayServer.get_name() == "headless":
		# Native Window.get_mouse_position polls the operating-system cursor;
		# injected Input events only control this polling API in headless runs.
		# Do not warp the user's real cursor just to verify the old tactical path.
		tactical_motion(point_b)
		game._update_mouse_aim()
		first_aim = player.aim_point
		tactical_motion(point_a)
		game._update_mouse_aim()
		check(not player.is_third_person() and first_aim.distance_to(player.aim_point) > 2.0, "tactical absolute cursor aiming still works after remote and local chase modes")
	game.free()
	print("REMOTE_MOUSE_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
