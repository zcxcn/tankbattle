extends SceneTree
## Real InputEventJoypad events exercise InputMap, GUI dispatch and tank controls.
## Synthetic device IDs intentionally differ from zero. No physical-pad claim.

var passed := 0
var failed := 0
var game: Node
const DEVICE := 7

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func axis(which: JoyAxis, value: float, device := DEVICE) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = which
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func button(which: JoyButton, pressed: bool, device := DEVICE) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = which
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(which: JoyButton, device := DEVICE) -> void:
	button(which, true, device)
	await frames(2)
	button(which, false, device)
	await frames(2)

func sync_ui() -> void:
	game.ui.update_snapshot(game.get_ui_snapshot())

func freeze_tanks() -> void:
	for tank: Node in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	root.get_node("SaveService").set("_directory", "user://tests/gamepad_041")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	sync_ui()
	await frames(3)
	var helper: Node = game.get_node("GamepadInput")
	print("GAMEPAD HARDWARE: %s; automated checks inject device IDs 7 and 9" % str(Input.get_connected_joypads()))
	var counts: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		counts[action] = InputMap.action_get_events(action).size()
	game._setup_inputs()
	game._setup_inputs()
	var stable := true
	for action: StringName in counts:
		stable = stable and counts[action] == InputMap.action_get_events(action).size()
	check(stable, "repeated game initialization does not duplicate input bindings")
	for action in ["move_forward", "aim_right", "fire", "precision_aim", "camera", "ui_accept", "ui_cancel"]:
		var all_devices := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion or event is InputEventJoypadButton:
				all_devices = all_devices or event.device == -1
		check(all_devices, action + " accepts any controller slot")
	axis(JOY_AXIS_LEFT_X, 0.1)
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").is_zero_approx(), "stick drift remains inside the movement deadzone")
	axis(JOY_AXIS_LEFT_X, 0.65)
	check(Input.get_action_strength("move_right") > 0.4, "nonzero device left stick drives InputMap movement")
	axis(JOY_AXIS_LEFT_X, 0.0)
	check(helper.using_controller and helper.active_device == DEVICE, "controller use is detected from real joypad events")
	var start_focus: Control = game.ui._title_start_button
	start_focus.grab_focus()
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == game.ui._title_mission, "D-pad moves menu focus exactly one item")
	var chassis_before: int = game.selected_chassis
	await tap(JOY_BUTTON_DPAD_DOWN)
	var woodland_focus: Control = game.ui.find_child("WoodlandStart", true, false)
	check(root.gui_get_focus_owner() == woodland_focus, "D-pad reaches the new woodland entry between mission and chassis selection")
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(game.selected_chassis != chassis_before and game.mode == "title", "A activates the focused chassis button without starting combat")
	start_focus.grab_focus()
	axis(JOY_AXIS_LEFT_Y, 0.8)
	game.ui._update_controller_menu(0.01)
	check(root.gui_get_focus_owner() == game.ui._title_mission, "left-stick menu nudge moves focus once")
	game.ui._update_controller_menu(0.37)
	check(root.gui_get_focus_owner() == woodland_focus, "held left stick repeats menu navigation after its delay")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	game.ui._update_controller_menu(0.01)
	game.open_settings()
	sync_ui()
	await frames(2)
	check(root.gui_get_focus_owner() == game.ui._setting_buttons["display_mode"], "settings receive controller focus on entry")
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == game.ui._setting_buttons["fps"], "settings D-pad down stays in the same column")
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(root.gui_get_focus_owner() == game.ui._setting_buttons["vsync"], "settings D-pad right enters the neighboring column")
	await tap(JOY_BUTTON_B)
	check(game.mode == "title", "B returns from settings without a mouse")
	sync_ui()
	await frames(2)
	await tap(JOY_BUTTON_A)
	check(game.mode == "playing", "A starts combat from the focused title action")
	freeze_tanks()
	sync_ui()
	await frames(2)
	var player = game.player
	axis(JOY_AXIS_LEFT_Y, -0.8)
	player._player_control(0.1)
	check(player.velocity.z < -0.1, "left stick drives the actual player tank forward")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	axis(JOY_AXIS_RIGHT_X, 0.75)
	player._player_control(0.016)
	check(player.is_controller_aiming() and player.aim_point.x > player.global_position.x, "right stick aims the turret in tactical view")
	axis(JOY_AXIS_RIGHT_X, 0.0)
	button(JOY_BUTTON_X, true)
	player._player_control(0.016)
	button(JOY_BUTTON_X, false)
	check(player.get_weapon_snapshot().id == "machine_gun", "X selects the next actual weapon")
	await frames(2)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	var ammo_before: int = player.get_weapon_snapshot().ammo
	player._player_control(0.016)
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(player.get_weapon_snapshot().ammo == ammo_before - 1, "RT fires the selected weapon and consumes one round")
	await frames(2)
	button(JOY_BUTTON_Y, true)
	player._player_control(0.016)
	button(JOY_BUTTON_Y, false)
	check(player.is_third_person(), "Y switches the actual tank camera to third person")
	await frames(2)
	axis(JOY_AXIS_RIGHT_X, 0.7)
	var rig: Node3D = player._camera_pivot
	var yaw_before: float = rig.yaw
	player._player_control(0.1)
	var normal_turn: float = absf(angle_difference(yaw_before, rig.yaw))
	check(normal_turn > 0.01, "right stick rotates the third-person camera")
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	yaw_before = rig.yaw
	player._player_control(0.1)
	var precise_turn: float = absf(angle_difference(yaw_before, rig.yaw))
	check(precise_turn > 0.001 and precise_turn < normal_turn * 0.5, "LT reduces aim sensitivity for precise third-person fire")
	axis(JOY_AXIS_RIGHT_X, 0.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	var zoom_before: float = rig.chase_distance
	button(JOY_BUTTON_DPAD_UP, true)
	player._player_control(0.016)
	button(JOY_BUTTON_DPAD_UP, false)
	check(rig.chase_distance < zoom_before, "D-pad up zooms the chase camera without a mouse")
	await frames(2)
	var mines_before: int = player.mine_ammo
	button(JOY_BUTTON_RIGHT_STICK, true)
	player._player_control(0.016)
	button(JOY_BUTTON_RIGHT_STICK, false)
	check(player.mine_ammo == mines_before - 1, "R3 places a mine through player controls")
	await frames(2)
	button(JOY_BUTTON_RIGHT_SHOULDER, true)
	player._player_control(0.016)
	button(JOY_BUTTON_RIGHT_SHOULDER, false)
	check(player.emp_cooldown > 0.0, "RB activates the EMP ability")
	await frames(2)
	axis(JOY_AXIS_LEFT_Y, -0.8)
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	player._player_control(0.016)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	check(player.dash_cooldown > 0.0, "LB activates tracked acceleration")
	sync_ui()
	check(game.ui._hud_mine.text.begins_with("R3") and "RT" in game.ui._hud_controls.text, "HUD hints follow the active controller")
	await tap(JOY_BUTTON_START)
	check(game.mode == "paused", "START pauses a live battle")
	sync_ui()
	await frames(2)
	await tap(JOY_BUTTON_B)
	check(game.mode == "playing", "B resumes the pause menu without a mouse")
	sync_ui()
	await frames(2)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(JOY_AXIS_LEFT_Y, -0.8)
	game._on_joy_connection_changed(11, false)
	check(game.mode == "playing", "disconnecting an unused controller does not interrupt combat")
	game._on_joy_connection_changed(DEVICE, false)
	Input.flush_buffered_events()
	check(game.mode == "paused" and game.pause_reason == "controller_disconnected", "disconnecting the active pad pauses safely")
	check(not Input.is_action_pressed("fire") and Input.get_vector("move_left", "move_right", "move_forward", "move_back").is_zero_approx(), "unplugging clears held trigger and movement instead of leaving phantom inputs")
	game._on_joy_connection_changed(9, true)
	check(game.mode == "paused", "reconnecting a pad never resumes combat without confirmation")
	sync_ui()
	await frames(2)
	await tap(JOY_BUTTON_START, 9)
	check(game.mode == "playing" and helper.active_device == 9, "a reconnected controller on a new device slot resumes with START")
	axis(JOY_AXIS_RIGHT_X, 0.6, 9)
	check(Input.get_action_strength("aim_right") > 0.2, "reconnected controller can aim without restarting the game")
	axis(JOY_AXIS_RIGHT_X, 0.0, 9)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(not helper.using_controller, "keyboard input restores keyboard HUD hints")
	key = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(not helper.rumble(0.4, 0.7, 0.2), "keyboard play never vibrates an unrelated controller")
	game.mode = "paused"
	game.free()
	await frames(3)
	print("GAMEPAD REGRESSION: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 1 if failed else 0)
