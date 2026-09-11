extends Node
## Exercise the real Control tree, joypad GUI dispatch and responsive workshop.

var passed := 0
var failed := 0
var ui: GameUI
var endless_requests := 0
var resume_requests := 0
var retry_requests := 0
var purchases: Array[String] = []


func _ready() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	call_deferred("run")


func check(value: bool, description: String) -> void:
	if value:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)


func frames(count := 3) -> void:
	for index in count:
		await get_tree().process_frame


func tap(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 7
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await frames(2)


func bind_ui_action(action: StringName, button: JoyButton) -> void:
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and existing.button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	InputMap.action_add_event(action, event)


func defense_snapshot() -> Dictionary:
	return {
		"wave": 4, "kills": 23, "scrap": 120, "base_hp": 640.0,
		"base_max_hp": 1000.0, "alive": 7, "next_wave_in": 9.5,
		"best_wave": 6, "best_kills": 48,
		"upgrades": [
			{"id": "firepower", "name": "火力强化", "description": "所有武器伤害提升 18%。", "level": 1, "max_level": 10, "cost": 100, "available": true},
			{"id": "autoloader", "name": "装填升级", "description": "缩短装填时间。", "level": 0, "max_level": 8, "cost": 200, "available": false},
			{"id": "fortification", "name": "防线加固", "description": "增加防线生命上限。", "level": 5, "max_level": 5, "cost": 100, "available": true},
			{"id": "repair", "name": "战场维修", "description": "修复防线和战车。", "level": 0, "max_level": -1, "cost": 60, "available": true},
			{"id": "ammo", "name": "弹药补给", "description": "补满弹药与地雷；不跳过正在进行的装填。", "level": 0, "max_level": -1, "cost": 40, "available": true},
		],
	}


func run() -> void:
	bind_ui_action(&"ui_accept", JOY_BUTTON_A)
	bind_ui_action(&"ui_cancel", JOY_BUTTON_B)
	bind_ui_action(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	ui = preload("res://ui/game_ui.gd").new()
	add_child(ui)
	ui.endless_requested.connect(func() -> void: endless_requests += 1)
	ui.resume_requested.connect(func() -> void: resume_requests += 1)
	ui.retry_requested.connect(func() -> void: retry_requests += 1)
	ui.upgrade_requested.connect(func(id: String) -> void: purchases.append(id))
	var defense := defense_snapshot()
	ui.update_snapshot({"mode": "title", "run_type": "campaign", "unlocked_missions": 2, "endless": defense})
	await frames()
	check(ui._title_endless_button.is_visible_in_tree(), "main menu exposes a distinct endless defense action")
	check("6" in ui._title_endless_record.text and "48" in ui._title_endless_record.text, "title displays independent endless records")
	ui._title_start_button.grab_focus()
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() == ui._title_mission, "campaign controller entry retains its existing focus order")
	ui._title_chassis.grab_focus()
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() == ui._title_endless_button, "D-pad reaches endless mode from chassis selection")
	await tap(JOY_BUTTON_A)
	check(endless_requests == 1, "controller confirm emits exactly one endless start request")
	ui.update_snapshot({"mode": "playing", "run_type": "endless", "endless": defense, "time": 125.0})
	await frames()
	check(ui._hud_kill_bar.max_value == 1000.0 and ui._hud_kill_bar.value == 640.0, "endless objective bar shows real defense health")
	check("04" in ui._hud_objective.text and "7" in ui._hud_objective.text, "combat HUD reports current wave and approaching monsters")
	check(ui._hud_score.text == "120" and ui._hud_score_caption.text == "整备资源", "combat score card becomes the spendable resource balance")
	check("Esc / Start" in ui._hud_defense_hint.text and "10s" in ui._hud_defense_hint.text, "HUD explains workshop controls and next wave countdown")
	check(not ui._shop_box.is_visible_in_tree(), "workshop does not cover active aiming")
	ui.update_snapshot({"mode": "paused"})
	await frames()
	check(ui._shop_box.is_visible_in_tree() and ui._pause_heading.text == "防线整备", "pausing endless defense exposes the workshop")
	check(not ui._upgrade_buttons.firepower.disabled and not ui._upgrade_buttons.repair.disabled, "affordable useful upgrades can be bought")
	check(ui._upgrade_buttons.autoloader.disabled and ui._upgrade_buttons.fortification.disabled, "unaffordable and maximum-level upgrades are disabled")
	check("LV.1/10" in ui._upgrade_buttons.firepower.text and "100" in ui._upgrade_buttons.firepower.text, "upgrade row states current level and purchase cost")
	check(not "LV." in ui._upgrade_buttons.repair.text and not "上限" in ui._upgrade_buttons.ammo.text, "repeatable repairs and ammunition do not display a false level cap")
	ui._pause_buttons[0].grab_focus()
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() == ui._upgrade_buttons.firepower, "D-pad enters the first available workshop purchase")
	await tap(JOY_BUTTON_A)
	check(purchases == ["firepower"] and ui._mode == "paused", "confirm purchases the selected upgrade without resuming combat")
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() == ui._upgrade_buttons.repair, "controller skips unavailable and maximum-level upgrades")
	var axis := InputEventJoypadMotion.new()
	axis.device = 7
	axis.axis = JOY_AXIS_LEFT_Y
	axis.axis_value = 0.8
	ui._input(axis)
	ui._update_controller_menu(0.01)
	check(get_viewport().gui_get_focus_owner() == ui._upgrade_buttons.ammo, "left stick navigates workshop purchase controls")
	axis.axis_value = 0.0
	ui._input(axis)
	ui._update_controller_menu(0.01)
	defense.scrap = 0
	ui.update_snapshot({"endless": defense})
	await frames()
	check(ui._upgrade_buttons.ammo.disabled and ui._shop_wallet.text == "整备资源 0", "purchase results immediately update balance and affordability")
	check(get_viewport().gui_get_focus_owner() == ui._pause_buttons[0], "depleted balance returns controller focus to an enabled action")
	await tap(JOY_BUTTON_B)
	check(resume_requests == 1, "B still resumes directly from the workshop")

	# The panel is deliberately smaller than its contents here. ScrollContainer
	# must make the last purchase reachable by keyboard/controller focus.
	var old_size := get_tree().root.content_scale_size
	get_tree().root.content_scale_size = Vector2i(960, 640)
	ui.update_snapshot({"endless": defense_snapshot()})
	await frames(6)
	ui._apply_safe_margins()
	await frames(6)
	check(ui._pause_grid.columns == 1, "compact windows stack the workshop under the pause controls")
	check(ui._pause_panel.size.x <= ui.size.x and ui._pause_panel.size.y <= ui.size.y, "compact workshop panel stays inside the viewport")
	ui._upgrade_buttons.ammo.grab_focus()
	await frames(6)
	check(ui._pause_scroll.scroll_vertical > 0, "controller focus scrolls the final purchase into view")
	var button_rect: Rect2 = ui._upgrade_buttons.ammo.get_global_rect()
	var scroll_rect: Rect2 = ui._pause_scroll.get_global_rect()
	check(scroll_rect.encloses(button_rect), "final shop button is fully visible after scrolling")
	get_tree().root.content_scale_size = old_size
	ui.update_snapshot({"mode": "lost", "result_delay": 0.0})
	await frames()
	check(ui._result_score_caption.text == "抵达波次" and ui._result_score.text == "4", "endless result reports waves rather than campaign score")
	check(ui._result_primary.text == "重新防守" and not ui._result_retry.visible, "endless defeat provides one clear retry action")
	check(not "坦克等级" in ui._result_career.text and "最高守至" in ui._result_career.text, "endless result uses its own record and reset explanation")
	await tap(JOY_BUTTON_A)
	check(retry_requests == 1, "result controller confirm retries the current mode")
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() == ui._result_menu, "endless result skips the hidden duplicate retry button")
	ui.update_snapshot({"mode": "paused", "run_type": "campaign"})
	await frames()
	check(not ui._shop_box.visible and not ui._hud_defense_hint.visible, "returning to campaign removes endless-only presentation")
	check(ui._hud_score_caption.text == "作战评分" and ui._pause_retry.text == "重新部署", "campaign labels are restored after an endless run")
	ui.queue_free()
	await frames()
	print("ENDLESS UI: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 1 if failed else 0)
