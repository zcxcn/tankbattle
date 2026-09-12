class_name GameUI
extends Control
## Reusable presentation layer for the native PC game.
## It never changes scenes, pauses the tree, or touches persistence directly.

signal start_requested
signal endless_requested
signal upgrade_requested(id: String)
signal resume_requested
signal retry_requested
signal menu_requested
signal settings_requested
signal quit_requested
signal next_requested
signal mission_requested
signal chassis_requested
signal setting_requested(id: String)

const ThemeFactory = preload("res://ui/iron_theme.gd")
const Backdrop = preload("res://ui/iron_backdrop.gd")
const BattleOverlay = preload("res://ui/battle_overlay.gd")

const VALID_MODES: Array[String] = ["title", "playing", "paused", "won", "lost", "settings"]
const DISPLAY_MODE_NAMES: Array[String] = ["窗口", "无边框全屏", "独占全屏"]
const QUALITY_NAMES: Array[String] = ["低", "中", "高", "极高"]

var _snapshot: Dictionary = {}
var _mode := "title"
var _return_mode := "title"
var _focused_mode := ""
var _safe_containers: Array[MarginContainer] = []
var _focus_targets: Dictionary = {}
var _setting_buttons: Dictionary = {}
var _pulse := 0.0
var _shake_enabled := true
var _menu_stick := Vector2.ZERO
var _menu_direction := Vector2i.ZERO
var _menu_repeat := 0.0

var _title_layer: Control
var _hud_layer: Control
var _battle_overlay: Control
var _hud_panels: Array[Control] = []
var _pause_layer: Control
var _settings_layer: Control
var _result_layer: Control

var _title_start_button: Button
var _title_endless_button: Button
var _title_endless_record: Label
var _title_kills: Label
var _title_level: Label
var _title_best: Label
var _title_mission: Button
var _title_chassis: Button
var _title_briefing: Label
var _title_chapter: Label
var _title_vehicle: Label

var _hud_level: Label
var _hud_hp_text: Label
var _hud_hp_bar: ProgressBar
var _hud_armor: Label
var _hud_objective: Label
var _hud_kills: Label
var _hud_kill_bar: ProgressBar
var _hud_score: Label
var _hud_score_caption: Label
var _hud_defense_hint: Label
var _hud_time: Label
var _hud_boss_panel: PanelContainer
var _hud_boss_name: Label
var _hud_boss_phase: Label
var _hud_boss_bar: ProgressBar
var _hud_boss_hp: Label
var _hud_boss_warning: Label
var _hud_notice_panel: PanelContainer
var _hud_notice: Label
var _hud_weapon: Label
var _hud_reload: Label
var _hud_ammo: Label
var _hud_weapon_slots: Label
var _hud_mine: Label
var _hud_emp: Label
var _hud_dash: Label
var _hud_music: Label
var _hud_radio: Label
var _hud_controls: Label

var _pause_notice: Label
var _pause_panel: PanelContainer
var _pause_grid: GridContainer
var _pause_scroll: ScrollContainer
var _pause_heading: Label
var _pause_kicker: Label
var _pause_controls: Label
var _pause_tactics: Label
var _pause_retry: Button
var _pause_buttons: Array[Button] = []
var _shop_box: VBoxContainer
var _shop_wallet: Label
var _shop_summary: Label
var _upgrade_buttons: Dictionary = {}
var _upgrade_descriptions: Dictionary = {}
var _pause_focus_key := ""
var _result_panel: PanelContainer
var _result_kicker: Label
var _result_title: Label
var _result_score: Label
var _result_kills: Label
var _result_time: Label
var _result_career: Label
var _result_primary: Button
var _result_retry: Button
var _result_menu: Button
var _result_score_caption: Label
var _result_kills_caption: Label
var _result_time_caption: Label


func _init() -> void:
	name = "GameUI"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	theme = ThemeFactory.build()
	_build_title_layer()
	_build_hud_layer()
	_build_pause_layer()
	_build_settings_layer()
	_build_result_layer()
	resized.connect(_apply_safe_margins)
	_apply_safe_margins()
	_apply_snapshot()


func _process(delta: float) -> void:
	_update_controller_menu(delta)
	if not _hud_boss_panel or not _hud_boss_panel.visible:
		return
	_pulse = fmod(_pulse + delta, TAU)
	if _bool_value("boss_warning", false):
		var strength := 0.82 + sin(_pulse * 5.2) * 0.18
		_hud_boss_panel.modulate = Color(1.0, strength, strength, 1.0)
	else:
		_hud_boss_panel.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion or event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		return
	if event.axis == JOY_AXIS_LEFT_X:
		_menu_stick.x = event.axis_value
	else:
		_menu_stick.y = event.axis_value
	# Axis-driven UI navigation is handled by our repeat timer. Leave the event
	# available to device detection and gameplay; D-pad uses native GUI actions.


func _update_controller_menu(delta: float) -> void:
	if _mode == "playing" or (_mode in ["won", "lost"] and not _result_layer.visible):
		_menu_direction = Vector2i.ZERO
		_menu_repeat = 0.0
		return
	var direction := Vector2i.ZERO
	if _menu_stick.length() > 0.55:
		if absf(_menu_stick.x) > absf(_menu_stick.y):
			direction.x = 1 if _menu_stick.x > 0.0 else -1
		else:
			direction.y = 1 if _menu_stick.y > 0.0 else -1
	if direction == Vector2i.ZERO:
		_menu_direction = direction
		_menu_repeat = 0.0
		return
	_menu_repeat -= delta
	if direction != _menu_direction:
		_menu_direction = direction
		_move_controller_focus(direction)
		_menu_repeat = 0.36
	elif _menu_repeat <= 0.0:
		_move_controller_focus(direction)
		_menu_repeat = 0.16


func _move_controller_focus(direction: Vector2i) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused) or not focused.is_visible_in_tree():
		_focus_current_mode()
		return
	var side := SIDE_LEFT if direction.x < 0 else SIDE_RIGHT
	if direction.y != 0:
		side = SIDE_TOP if direction.y < 0 else SIDE_BOTTOM
	var neighbor := focused.get_focus_neighbor(side)
	var target := focused.get_node_or_null(neighbor) as Control
	if is_instance_valid(target) and target.is_visible_in_tree():
		target.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	match _mode:
		"paused":
			resume_requested.emit()
			get_viewport().set_input_as_handled()
		"settings", "won", "lost":
			menu_requested.emit()
			get_viewport().set_input_as_handled()


func update_snapshot(snapshot: Dictionary) -> void:
	for key: Variant in snapshot:
		_snapshot[key] = snapshot[key]
	if snapshot.has("shake"):
		_shake_enabled = bool(snapshot["shake"])
	elif snapshot.has("screen_shake"):
		_shake_enabled = bool(snapshot["screen_shake"])
	if is_node_ready():
		_apply_snapshot()


func _build_title_layer() -> void:
	_title_layer = _new_layer("TitleLayer")
	_title_layer.add_child(Backdrop.new())
	_title_layer.get_child(0).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe := _new_safe_container(_title_layer)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 14)
	safe.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 14)
	layout.add_child(header)
	var mark := Label.new()
	mark.text = "IE"
	mark.theme_type_variation = &"SectionTitle"
	mark.add_theme_color_override(&"font_color", ThemeFactory.ORANGE_BRIGHT)
	header.add_child(mark)
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override(&"separation", 0)
	header.add_child(identity)
	identity.add_child(_label("钢铁余烬 · 重铸", &"SectionTitle"))
	identity.add_child(_label("IRON EMBERS / NATIVE PC EDITION", &"Micro"))
	header.add_child(_spacer(true, false))
	var status := Label.new()
	status.text = "●  SYSTEM READY"
	status.theme_type_variation = &"Muted"
	status.add_theme_color_override(&"font_color", ThemeFactory.GREEN)
	header.add_child(status)

	layout.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.name = "TitleBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 0)
	layout.add_child(body)

	var command_scroll := ScrollContainer.new()
	command_scroll.name = "TitleScroll"
	command_scroll.custom_minimum_size = Vector2(580.0, 0.0)
	command_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	command_scroll.follow_focus = true
	body.add_child(command_scroll)
	var command := VBoxContainer.new()
	command.name = "TitleCommand"
	command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command.add_theme_constant_override(&"separation", 8)
	command_scroll.add_child(command)
	body.add_child(_spacer(true, false))
	command.add_child(_label("TACTICAL ARMORED COMMAND", &"Kicker"))
	var game_title := _label("钢铁余烬", &"DisplayTitle")
	game_title.add_theme_font_size_override(&"font_size", 52)
	game_title.add_theme_color_override(&"font_color", Color("#f4f1e7"))
	command.add_child(game_title)
	var subtitle := _label("从灰烬中点火，驾驶最后的装甲穿过尘湾。", &"Body")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(0.0, 30.0)
	subtitle.add_theme_color_override(&"font_color", ThemeFactory.MUTED)
	command.add_child(subtitle)

	_title_start_button = _button("开始行动", &"PrimaryButton", func() -> void: start_requested.emit())
	command.add_child(_title_start_button)
	_title_mission = _button("选择任务", &"CommandButton", func() -> void: mission_requested.emit())
	command.add_child(_title_mission)
	_title_chassis = _button("选择战车", &"CommandButton", func() -> void: chassis_requested.emit())
	command.add_child(_title_chassis)
	_title_vehicle = _label("", &"Micro")
	_title_vehicle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	command.add_child(_title_vehicle)
	_title_endless_button = _button("无尽防守 · 巨兽围城", &"DangerButton", func() -> void: endless_requested.emit())
	_title_endless_button.name = "EndlessStart"
	_title_endless_button.tooltip_text = "守住防线，抵挡不断逼近的巨型怪物。击杀获得资源，暂停时升级武器、修复防线。"
	command.add_child(_title_endless_button)
	_title_endless_record = _label("巨型怪物持续来袭 · 击杀换取武器升级", &"Micro")
	_title_endless_record.add_theme_color_override(&"font_color", ThemeFactory.GOLD)
	command.add_child(_title_endless_record)
	var settings_button := _button("作战设置", &"CommandButton", func() -> void: settings_requested.emit())
	command.add_child(settings_button)
	var quit_button := _button("退出游戏", &"DangerButton", func() -> void: quit_requested.emit())
	command.add_child(quit_button)
	_wire_vertical_focus([_title_start_button, _title_mission, _title_chassis, _title_endless_button, settings_button, quit_button])
	_focus_targets["title"] = _title_start_button
	command.add_child(_spacer(false, true))

	var feature := _panel(&"HUDPanel")
	feature.name = "TitleBriefing"
	command.add_child(feature)
	var briefing := VBoxContainer.new()
	briefing.add_theme_constant_override(&"separation", 6)
	feature.add_child(briefing)
	var chapter := HBoxContainer.new()
	briefing.add_child(chapter)
	_title_chapter = _label("第 01 章 · 灰中点火", &"HudValue")
	chapter.add_child(_title_chapter)
	chapter.add_child(_spacer(true, false))
	chapter.add_child(_label("行动简报", &"Kicker"))
	_title_briefing = _label("", &"Muted")
	_title_briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.add_child(_title_briefing)
	briefing.add_child(HSeparator.new())
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 10)
	briefing.add_child(stats)
	var stat_values: Array[Label] = []
	for caption: String in ["累计击毁", "坦克等级", "最高评分"]:
		var stat := VBoxContainer.new()
		stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat.add_theme_constant_override(&"separation", 0)
		stats.add_child(stat)
		stat.add_child(_label(caption, &"Micro"))
		var value := _label("0", &"HudValue")
		value.add_theme_color_override(&"font_color", ThemeFactory.GOLD)
		stat.add_child(value)
		stat_values.append(value)
	_title_kills = stat_values[0]
	_title_level = stat_values[1]
	_title_best = stat_values[2]
	var tips := _label("键鼠 / 手柄    ENTER / A  确认    ESC / B  返回", &"Micro")
	tips.add_theme_color_override(&"font_color", ThemeFactory.GREEN)
	command.add_child(tips)

	layout.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	footer.add_child(_label("BUILD 0.4.10 · FORWARD+ / PBR ARMOR", &"Micro"))
	footer.add_child(_spacer(true, false))
	var asset_credit := _label("3D：tomm8 · GRIP420 / David Falke · Comrade1280 · CC BY 4.0\n机枪录音：KuraiWolf / Nightshade Game Studios · CC BY 4.0", &"Micro")
	asset_credit.name = "AssetCredit"
	asset_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	asset_credit.tooltip_text = (
		"Challenger 2 - Shooting Range — Tom Zimmermann (tomm8)\n"
		+ "KF51 Panther — GRIP420 / David Falke\n"
		+ "KV-2 heavy tank 1940 — Comrade1280\n"
		+ "完整来源与修改记录：assets/THIRD_PARTY_ASSETS.md"
		+ "\n机枪录音：KuraiWolf / Nightshade Game Studios，CC BY 4.0\n音效完整来源与处理记录：assets/audio/combat/README.md"
	)
	footer.add_child(asset_credit)


func _build_hud_layer() -> void:
	_hud_layer = _new_layer("BattleHUD")
	_battle_overlay = BattleOverlay.new()
	_hud_layer.add_child(_battle_overlay)
	var safe := _new_safe_container(_hud_layer)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 10)
	safe.add_child(layout)

	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	layout.add_child(top)

	var player_panel := _panel(&"HUDPanel")
	_hud_panels.append(player_panel)
	player_panel.custom_minimum_size = Vector2(330.0, 104.0)
	top.add_child(player_panel)
	var player := VBoxContainer.new()
	player.add_theme_constant_override(&"separation", 5)
	player_panel.add_child(player)
	var player_header := HBoxContainer.new()
	player.add_child(player_header)
	_hud_level = _label("LV.01 · 新兵战车", &"Kicker")
	player_header.add_child(_hud_level)
	player_header.add_child(_spacer(true, false))
	_hud_armor = _label("装甲 0", &"Muted")
	player_header.add_child(_hud_armor)
	_hud_hp_text = _label("100 / 100", &"HudValue")
	player.add_child(_hud_hp_text)
	_hud_hp_bar = _progress(&"HealthBar", 100.0)
	player.add_child(_hud_hp_bar)

	var objective_panel := _panel(&"HUDPanel")
	objective_panel.name = "CompactObjective"
	_hud_panels.append(objective_panel)
	objective_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	objective_panel.custom_minimum_size = Vector2(0.0, 64.0)
	top.add_child(objective_panel)
	var objective_box := VBoxContainer.new()
	objective_box.alignment = BoxContainer.ALIGNMENT_CENTER
	objective_box.add_theme_constant_override(&"separation", 5)
	objective_panel.add_child(objective_box)
	var objective_header := HBoxContainer.new()
	objective_box.add_child(objective_header)
	_hud_objective = _label("突破封锁", &"HudValue")
	_hud_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	objective_header.add_child(_hud_objective)
	_hud_kills = _label("0 / 6", &"Muted")
	objective_header.add_child(_hud_kills)
	_hud_kill_bar = _progress(&"ObjectiveBar", 6.0)
	_hud_kill_bar.custom_minimum_size.y = 4.0
	objective_box.add_child(_hud_kill_bar)
	_hud_defense_hint = _label("Esc / Start 打开升级", &"Micro")
	_hud_defense_hint.add_theme_color_override(&"font_color", ThemeFactory.GOLD)
	objective_box.add_child(_hud_defense_hint)

	var score_panel := _panel(&"HUDPanel")
	_hud_panels.append(score_panel)
	score_panel.custom_minimum_size = Vector2(230.0, 104.0)
	top.add_child(score_panel)
	var score_box := VBoxContainer.new()
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	score_panel.add_child(score_box)
	_hud_score_caption = _label("作战评分", &"Muted")
	score_box.add_child(_hud_score_caption)
	_hud_score = _label("00000", &"Metric")
	_hud_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(_hud_score)
	_hud_time = _label("00:00", &"Muted")
	_hud_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(_hud_time)
	_hud_music = _label("N · 战斗音乐", &"Micro")
	_hud_music.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud_music.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(_hud_music)

	var boss_center := HBoxContainer.new()
	layout.add_child(boss_center)
	boss_center.add_child(_spacer(true, false))
	_hud_boss_panel = _panel(&"BossPanel")
	_hud_panels.append(_hud_boss_panel)
	_hud_boss_panel.custom_minimum_size = Vector2(760.0, 92.0)
	boss_center.add_child(_hud_boss_panel)
	boss_center.add_child(_spacer(true, false))
	var boss := VBoxContainer.new()
	boss.add_theme_constant_override(&"separation", 5)
	_hud_boss_panel.add_child(boss)
	var boss_header := HBoxContainer.new()
	boss.add_child(boss_header)
	_hud_boss_name = _label("铁牙", &"SectionTitle")
	boss_header.add_child(_hud_boss_name)
	_hud_boss_phase = _label("PHASE 1", &"Kicker")
	boss_header.add_child(_hud_boss_phase)
	boss_header.add_child(_spacer(true, false))
	_hud_boss_warning = _label("齐射锁定 · 使用 EMP 打断", &"Danger")
	boss_header.add_child(_hud_boss_warning)
	var boss_health := HBoxContainer.new()
	boss.add_child(boss_health)
	_hud_boss_bar = _progress(&"BossBar", 100.0)
	_hud_boss_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_health.add_child(_hud_boss_bar)
	_hud_boss_hp = _label("100 / 100", &"Muted")
	boss_health.add_child(_hud_boss_hp)

	layout.add_child(_spacer(false, true))
	_hud_radio = _label("", &"Body")
	_hud_radio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_radio.add_theme_color_override(&"font_color", ThemeFactory.GREEN)
	layout.add_child(_hud_radio)

	var notice_center := HBoxContainer.new()
	layout.add_child(notice_center)
	notice_center.add_child(_spacer(true, false))
	_hud_notice_panel = _panel(&"NoticePanel")
	_hud_panels.append(_hud_notice_panel)
	_hud_notice_panel.custom_minimum_size = Vector2(520.0, 0.0)
	notice_center.add_child(_hud_notice_panel)
	notice_center.add_child(_spacer(true, false))
	_hud_notice = _label("", &"Body")
	_hud_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_notice_panel.add_child(_hud_notice)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 10)
	layout.add_child(bottom)
	var mine_panel := _panel(&"HUDPanel")
	_hud_panels.append(mine_panel)
	mine_panel.custom_minimum_size = Vector2(230.0, 72.0)
	bottom.add_child(mine_panel)
	_hud_mine = _label("M  地雷 × 6", &"HudValue")
	mine_panel.add_child(_hud_mine)

	var weapon_panel := _panel(&"HUDPanel")
	_hud_panels.append(weapon_panel)
	weapon_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_panel.custom_minimum_size = Vector2(380.0, 72.0)
	bottom.add_child(weapon_panel)
	var weapon_stack := VBoxContainer.new()
	weapon_panel.add_child(weapon_stack)
	var weapon_box := HBoxContainer.new()
	weapon_box.alignment = BoxContainer.ALIGNMENT_CENTER
	weapon_stack.add_child(weapon_box)
	_hud_weapon = _label("加农炮", &"SectionTitle")
	weapon_box.add_child(_hud_weapon)
	weapon_box.add_child(_spacer(true, false))
	_hud_ammo = _label("", &"Muted")
	weapon_box.add_child(_hud_ammo)
	_hud_reload = _label("READY", &"Success")
	weapon_box.add_child(_hud_reload)
	_hud_weapon_slots = _label("1 穿甲弹  2 机枪  3 榴弹  4 火箭", &"Micro")
	weapon_stack.add_child(_hud_weapon_slots)
	_hud_controls = _label("左键 开火 · R 武器 · C 视角 · ESC 暂停", &"Micro")
	weapon_stack.add_child(_hud_controls)

	var ability_panel := _panel(&"HUDPanel")
	_hud_panels.append(ability_panel)
	ability_panel.custom_minimum_size = Vector2(390.0, 72.0)
	bottom.add_child(ability_panel)
	var abilities := HBoxContainer.new()
	abilities.alignment = BoxContainer.ALIGNMENT_CENTER
	ability_panel.add_child(abilities)
	_hud_dash = _label("SPACE 短时加速", &"Muted")
	abilities.add_child(_hud_dash)
	abilities.add_child(VSeparator.new())
	_hud_emp = _label("E EMP", &"Muted")
	abilities.add_child(_hud_emp)

	_set_mouse_passthrough(_hud_layer)


func _build_pause_layer() -> void:
	_pause_layer = _new_layer("PauseLayer")
	_add_dimmer(_pause_layer, 0.82)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	_pause_panel = _panel(&"OverlayPanel")
	center.add_child(_pause_panel)
	_pause_scroll = ScrollContainer.new()
	_pause_scroll.name = "PauseScroll"
	_pause_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pause_scroll.follow_focus = true
	_pause_panel.add_child(_pause_scroll)
	_pause_grid = GridContainer.new()
	_pause_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_grid.add_theme_constant_override(&"h_separation", 30)
	_pause_grid.add_theme_constant_override(&"v_separation", 22)
	_pause_scroll.add_child(_pause_grid)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 12)
	_pause_grid.add_child(box)
	_pause_kicker = _label("OPERATION SUSPENDED", &"Kicker")
	box.add_child(_pause_kicker)
	_pause_heading = _label("战场已暂停", &"ScreenTitle")
	box.add_child(_pause_heading)
	_pause_notice = _label("所有作战计时已经停止。", &"Muted")
	_pause_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pause_notice)
	_pause_controls = _label("WASD / 左摇杆：移动    鼠标 / 右摇杆：瞄准\n左键 / RT：开火    C / Y：视角    LT：精瞄\n1–4：选武器    R / X：切武器    N：音乐\nM / R3：布雷    E / RB：EMP    空格 / LB：加速", &"Muted")
	_pause_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pause_controls)
	_pause_tactics = _label("绿色整备点提供补给；起火残骸可能殉爆，保持距离。", &"Muted")
	_pause_tactics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pause_tactics)
	box.add_child(HSeparator.new())
	var resume_button := _button("继续行动", &"PrimaryButton", func() -> void: resume_requested.emit())
	box.add_child(resume_button)
	_pause_retry = _button("重新部署", &"CommandButton", func() -> void: retry_requested.emit())
	box.add_child(_pause_retry)
	var settings_button := _button("作战设置", &"CommandButton", func() -> void: settings_requested.emit())
	box.add_child(settings_button)
	var menu_button := _button("返回指挥中心", &"DangerButton", func() -> void: menu_requested.emit())
	box.add_child(menu_button)
	_pause_buttons.assign([resume_button, _pause_retry, settings_button, menu_button])
	_focus_targets["paused"] = resume_button
	var hint := _label("ESC / START  继续    A / ENTER  确认\nF8  远程鼠标", &"Micro")
	box.add_child(hint)

	_shop_box = VBoxContainer.new()
	_shop_box.name = "EndlessUpgrades"
	_shop_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_box.add_theme_constant_override(&"separation", 10)
	_pause_grid.add_child(_shop_box)
	_shop_box.add_child(_label("FIELD WORKSHOP / 本局升级", &"Kicker"))
	_shop_wallet = _label("整备资源 0", &"Metric")
	_shop_box.add_child(_shop_wallet)
	_shop_summary = _label("第 1 波 · 防线 1000 / 1000", &"Muted")
	_shop_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_box.add_child(_shop_summary)
	_shop_box.add_child(HSeparator.new())
	for entry: Array in [
		["firepower", "火力强化"], ["autoloader", "装填升级"],
		["fortification", "防线加固"], ["repair", "战场维修"], ["ammo", "弹药补给"],
	]:
		var id := String(entry[0])
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", 3)
		_shop_box.add_child(row)
		var button := _button(String(entry[1]), &"SettingButton", upgrade_requested.emit.bind(id))
		button.name = "Upgrade_" + id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size = Vector2(0.0, 60.0)
		row.add_child(button)
		_upgrade_buttons[id] = button
		var description := _label("", &"Muted")
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(description)
		_upgrade_descriptions[id] = description
	var note := _label("升级立即生效。结束本局后重置装备；最高波次与击杀纪录保留。", &"Micro")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_box.add_child(note)


func _build_settings_layer() -> void:
	_settings_layer = _new_layer("SettingsLayer")
	_add_dimmer(_settings_layer, 0.88)
	var safe := _new_safe_container(_settings_layer)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 18)
	safe.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title_box := VBoxContainer.new()
	header.add_child(title_box)
	title_box.add_child(_label("SYSTEM CONFIGURATION", &"Kicker"))
	title_box.add_child(_label("作战设置", &"ScreenTitle"))
	header.add_child(_spacer(true, false))
	var back_button := _button("返回", &"CommandButton", func() -> void: menu_requested.emit())
	back_button.custom_minimum_size = Vector2(150.0, 58.0)
	header.add_child(back_button)
	outer.add_child(HSeparator.new())

	var content_center := CenterContainer.new()
	content_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content_center)
	var panel := _panel(&"OverlayPanel")
	panel.custom_minimum_size = Vector2(900.0, 600.0)
	content_center.add_child(panel)
	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override(&"separation", 13)
	panel.add_child(settings_box)
	settings_box.add_child(_label("画面、声音与操作", &"SectionTitle"))
	var explanation := _label("设置立即生效并在本机保存。F8 切换远程鼠标，F11 切换显示模式。", &"Muted")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_box.add_child(explanation)
	settings_box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 13)
	grid.add_theme_constant_override(&"v_separation", 13)
	settings_box.add_child(grid)
	var buttons: Array[Button] = []
	for entry: Array in [
		["display_mode", "显示模式", "窗口 / 无边框 / 独占全屏"],
		["quality", "画面质量", "渲染比例、阴影和抗锯齿预设"],
		["fps", "目标帧率", "60 / 120 / 144 / 不限帧"],
		["vsync", "垂直同步", "减少画面撕裂"],
		["shake", "屏幕震动", "爆炸与重炮冲击反馈"],
		["master_volume", "总音量", "每次调整 10%"],
		["effects_volume", "战斗音效", "炮声、爆炸、引擎与界面音效"],
		["music_volume", "战斗音乐", "音乐独立音量，每次调整 10%"],
		["radio_volume", "战场通信", "真人战术语音独立音量，每次调整 10%"],
		["music_track", "选择音乐", "轮换三首战斗配乐，也可按 N 切换"],
		["weather_mode", "战场天气", "随机 / 晴天 / 小雨 / 大雨 / 雪天 / 雾天；立即生效，随机在每次出击时重新选择"],
		["remote_mouse", "第三人称鼠标", "远程桌面：移动鼠标调整准星，靠近屏幕边缘转动视角。F8 切换本地 / 远程桌面。"],
	]:
		var id := String(entry[0])
		var button := _button("", &"SettingButton", setting_requested.emit.bind(id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = String(entry[2])
		button.custom_minimum_size = Vector2(0.0, 64.0)
		_setting_buttons[id] = button
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
		buttons.append(button)
	settings_box.add_child(_spacer(false, true))
	var note := _label("F11：切换显示模式    ESC：返回    音量调至 0% 时静音", &"Micro")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_box.add_child(note)
	_wire_settings_focus(buttons, back_button)
	_focus_targets["settings"] = _setting_buttons["display_mode"]


func _build_result_layer() -> void:
	_result_layer = _new_layer("ResultLayer")
	_result_layer.add_child(Backdrop.new())
	_result_layer.get_child(0).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_dimmer(_result_layer, 0.46)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(center)
	_result_panel = _panel(&"OverlayPanel")
	_result_panel.custom_minimum_size = Vector2(760.0, 640.0)
	center.add_child(_result_panel)
	var result_scroll := ScrollContainer.new()
	result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_scroll.follow_focus = true
	_result_panel.add_child(result_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 16)
	result_scroll.add_child(box)
	_result_kicker = _label("MISSION ACCOMPLISHED", &"Kicker")
	_result_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_kicker)
	_result_title = _label("行动成功", &"ScreenTitle")
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	box.add_child(HSeparator.new())
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override(&"separation", 12)
	box.add_child(stats)
	var score_card := _metric_card("作战评分")
	_result_score = score_card.get_meta("value") as Label
	_result_score_caption = score_card.get_meta("caption") as Label
	stats.add_child(score_card)
	var kills_card := _metric_card("本次击毁")
	_result_kills = kills_card.get_meta("value") as Label
	_result_kills_caption = kills_card.get_meta("caption") as Label
	stats.add_child(kills_card)
	var time_card := _metric_card("作战用时")
	_result_time = time_card.get_meta("value") as Label
	_result_time_caption = time_card.get_meta("caption") as Label
	stats.add_child(time_card)
	_result_career = _label("坦克等级 LV.01 · 累计击毁 0 · 最高评分 0", &"Body")
	_result_career.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_career.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_result_career)
	box.add_child(_spacer(false, true))
	_result_primary = _button("返回指挥中心", &"PrimaryButton", func() -> void: _result_primary_action())
	box.add_child(_result_primary)
	_result_retry = _button("再战本关", &"CommandButton", func() -> void: retry_requested.emit())
	box.add_child(_result_retry)
	_result_menu = _button("返回指挥中心", &"CommandButton", func() -> void: menu_requested.emit())
	box.add_child(_result_menu)
	_wire_vertical_focus([_result_primary, _result_retry, _result_menu])
	_focus_targets["won"] = _result_primary
	_focus_targets["lost"] = _result_primary
	box.add_child(_label("ENTER / A  确认    ESC / B  返回指挥中心", &"Micro"))


func _apply_snapshot() -> void:
	var result_was_visible := _result_layer.visible
	var requested_mode := str(_snapshot.get("mode", "title")).to_lower()
	if requested_mode not in VALID_MODES:
		requested_mode = "title"
	if requested_mode == "settings" and _mode != "settings":
		_return_mode = _mode
	elif requested_mode != "settings":
		_return_mode = requested_mode
	_mode = requested_mode

	var settings_over_battle := _mode == "settings" and _return_mode in ["playing", "paused"]
	_title_layer.visible = _mode == "title" or (_mode == "settings" and not settings_over_battle)
	_hud_layer.visible = _mode in ["playing", "paused"] or settings_over_battle
	_pause_layer.visible = _mode == "paused"
	_settings_layer.visible = _mode == "settings"
	_result_layer.visible = _mode in ["won", "lost"] and _float_value("result_delay", 0.0) <= 0.0

	# Hidden menus are refreshed on entry, not rebuilt throughout every battle.
	if _title_layer.visible:
		_update_title()
	if _hud_layer.visible:
		_update_hud()
	if _settings_layer.visible:
		_update_settings()
	if _pause_layer.visible:
		_update_pause()
	if _result_layer.visible:
		_update_result()
	if _focused_mode != _mode or (_result_layer.visible and not result_was_visible):
		_menu_stick = Vector2.ZERO
		_menu_direction = Vector2i.ZERO
		_menu_repeat = 0.0
		_focused_mode = _mode
		call_deferred("_focus_current_mode")


func _update_title() -> void:
	var lifetime := _int_value("lifetime_kills", 0)
	var level := maxi(1, _int_value("tank_level", 1))
	var best := _int_value("best_score", 0)
	_title_kills.text = str(lifetime)
	_title_level.text = "LV.%02d" % level
	_title_best.text = _compact_number(best)
	_title_start_button.text = "继续行动" if lifetime > 0 or best > 0 else "开始行动"
	var chapter := _int_value("selected_mission", 0) + 1
	_title_mission.text = "任务 %02d · %s  ›" % [chapter, str(_snapshot.get("mission_name", "灰中点火"))]
	_title_mission.tooltip_text = "点击轮换已解锁任务；击败本关首领解锁下一关。"
	_title_mission.disabled = _int_value("unlocked_missions", 1) <= 1
	_title_chassis.text = "战车 · %s  ›" % str(_snapshot.get("vehicle", "主战坦克"))
	_title_vehicle.text = str(_snapshot.get("vehicle_description", ""))
	_title_chapter.text = "任务 %02d / %02d · 已解锁 %d" % [chapter, _int_value("mission_count", 3), _int_value("unlocked_missions", 1)]
	_title_briefing.text = str(_snapshot.get("mission_briefing", "清除巡逻车队，击败首领。"))
	var defense := _endless_snapshot()
	var best_wave := maxi(0, int(defense.get("best_wave", 0)))
	_title_endless_record.text = "最高守至第 %d 波 · 最多击杀 %d" % [best_wave, maxi(0, int(defense.get("best_kills", 0)))] if best_wave > 0 else "巨型怪物持续来袭 · 击杀换取武器升级"


func _update_hud() -> void:
	_battle_overlay.update_snapshot(_snapshot)
	var hp := maxf(0.0, _float_value("hp", 100.0))
	var max_hp := maxf(1.0, _float_value("max_hp", 100.0))
	var level := maxi(1, _int_value("tank_level", 1))
	_hud_level.text = "LV.%02d · %s" % [level, str(_snapshot.get("vehicle", "指挥战车"))]
	_hud_hp_text.text = "%d / %d" % [ceili(hp), ceili(max_hp)]
	_hud_hp_bar.max_value = max_hp
	_hud_hp_bar.value = clampf(hp, 0.0, max_hp)
	_hud_armor.text = "装甲 %d" % maxi(0, _int_value("armor", 0))

	var kills := maxi(0, _int_value("kills", 0))
	var target := maxi(1, _int_value("target_kills", 6))
	_hud_objective.text = str(_snapshot.get("objective", "突破封锁并击毁本关首领"))
	_hud_kills.text = "%d / %d" % [kills, target]
	_hud_kill_bar.max_value = target
	_hud_kill_bar.value = mini(kills, target)
	if str(_snapshot.get("mission_type", "clear")) in ["capture", "demolition"]:
		var progress := clampf(_float_value("objective_fraction", 0.0), 0.0, 1.0)
		_hud_kills.text = "%d%%" % roundi(progress * 100.0)
		_hud_kill_bar.max_value = 1.0
		_hud_kill_bar.value = progress
	_hud_score.text = "%05d" % maxi(0, _int_value("score", 0))
	_hud_score_caption.text = "作战评分"
	_hud_time.text = _format_time(_float_value("time", 0.0))
	_hud_defense_hint.visible = _is_endless()
	if _is_endless():
		var defense := _endless_snapshot()
		var base_hp := maxf(0.0, float(defense.get("base_hp", 0.0)))
		var base_max := maxf(1.0, float(defense.get("base_max_hp", 1.0)))
		_hud_objective.text = "第 %02d 波 · 在场 %d · 待入场 %d" % [maxi(1, int(defense.get("wave", 1))), maxi(0, int(defense.get("alive", 0))), maxi(0, int(defense.get("pending", 0)))]
		_hud_kills.text = "防线 %d / %d" % [ceili(base_hp), ceili(base_max)]
		_hud_kill_bar.max_value = base_max
		_hud_kill_bar.value = clampf(base_hp, 0.0, base_max)
		_hud_kill_bar.modulate = ThemeFactory.RED if base_hp / base_max < 0.3 else Color.WHITE
		_hud_score_caption.text = "整备资源"
		_hud_score.text = str(maxi(0, int(defense.get("scrap", 0))))
		var next_wave := maxf(0.0, float(defense.get("next_wave_in", 0.0)))
		_hud_defense_hint.text = "%s · 下波 %ds · Esc / Start 整备" % ["本波已清除" if defense.get("cleared", false) else "击杀 %d" % maxi(0, int(defense.get("kills", 0))), ceili(next_wave)]
	else:
		_hud_kill_bar.modulate = Color.WHITE
	var music: Dictionary = _snapshot.get("music", {})
	_hud_music.text = "N · " + str(music.get("name", "战斗音乐"))
	_hud_radio.text = "[车组通信] " + str(_snapshot.get("radio_caption", ""))
	_hud_radio.visible = not str(_snapshot.get("radio_caption", "")).is_empty()

	var boss_max := maxf(0.0, _float_value("boss_max_hp", 0.0))
	var boss_hp := clampf(_float_value("boss_hp", 0.0), 0.0, boss_max)
	var boss_name := str(_snapshot.get("boss_name", ""))
	_hud_boss_panel.visible = boss_max > 0.0 and not boss_name.is_empty()
	_hud_boss_name.text = boss_name
	_hud_boss_phase.text = "PHASE %d" % clampi(_int_value("boss_phase", 1), 1, 3)
	_hud_boss_bar.max_value = maxf(1.0, boss_max)
	_hud_boss_bar.value = boss_hp
	_hud_boss_hp.text = "%d / %d" % [ceili(boss_hp), ceili(boss_max)]
	_hud_boss_warning.visible = _bool_value("boss_warning", false)

	var notice := str(_snapshot.get("notice", ""))
	_hud_notice.text = notice
	_hud_notice_panel.visible = not notice.is_empty()
	_hud_weapon.text = str(_snapshot.get("weapon", "加农炮"))
	var reload := maxf(0.0, _float_value("reload", 0.0))
	_hud_reload.text = "READY" if reload <= 0.01 else "装填 %.1fs" % reload
	_hud_reload.theme_type_variation = &"Success" if reload <= 0.01 else &"Danger"
	var weapon_state: Dictionary = _snapshot.get("weapon_state", {})
	var ammo := int(weapon_state.get("ammo", -1))
	var reserve := int(weapon_state.get("reserve", 0))
	_hud_ammo.text = "弹药 ∞" if ammo < 0 else ("%d / %d" % [ammo, reserve] if weapon_state.get("id", "") == "machine_gun" else "剩余 %d" % ammo)
	if ammo == 0 and reload <= 0.01:
		_hud_reload.text = "弹药耗尽"
		_hud_reload.theme_type_variation = &"Danger"
	elif weapon_state.get("belt_reloading", false):
		_hud_reload.text = "换弹链 %.1fs" % reload
	var slot_names: Array[String] = []
	for slot: Dictionary in weapon_state.get("slots", []):
		var selected := str(slot.get("id", "")) == str(weapon_state.get("id", ""))
		slot_names.append("%s%d %s%s" % ["[" if selected else "", slot_names.size() + 1, str(slot.get("name", "")), "]" if selected else ""])
	if not slot_names.is_empty():
		_hud_weapon_slots.text = "  ".join(slot_names)
	var mine_cooldown := maxf(0.0, _float_value("mine_cooldown", 0.0))
	var pad := str(_snapshot.get("input_device", "keyboard")) == "controller"
	_hud_mine.text = "%s  地雷 × %d%s" % [
		"R3" if pad else "M",
		maxi(0, _int_value("mine_ammo", 0)),
		" · %.1fs" % mine_cooldown if mine_cooldown > 0.01 else "",
	]
	_hud_emp.text = _cooldown_text("RB  EMP" if pad else "E  EMP", _float_value("emp_cooldown", 0.0))
	_hud_dash.text = _cooldown_text("LB  短时加速" if pad else "SPACE  短时加速", _float_value("dash_cooldown", 0.0))
	_hud_controls.text = "RT 开火 · LT 精瞄 · X 武器 · Y 视角 · START 暂停" if pad else "左键 开火 · R 武器 · C 视角 · ESC 暂停"
	var regions: Array[Rect2] = []
	for panel: Control in _hud_panels:
		if panel.is_visible_in_tree():
			var region := panel.get_global_rect()
			region.position -= _battle_overlay.global_position
			regions.append(region)
	_battle_overlay.set_hud_regions(regions)


func _update_settings() -> void:
	var display_value: Variant = _snapshot.get("display_mode", 0)
	var display_text := str(display_value)
	if display_value is int or display_value is float:
		display_text = DISPLAY_MODE_NAMES[clampi(int(display_value), 0, DISPLAY_MODE_NAMES.size() - 1)]
	var quality_value: Variant = _snapshot.get("quality", 2)
	var quality_text := str(quality_value)
	if quality_value is int or quality_value is float:
		quality_text = QUALITY_NAMES[clampi(int(quality_value), 0, QUALITY_NAMES.size() - 1)]
	var cap := _int_value("fps_cap", 60)
	var values := {
		"display_mode": ["显示模式", display_text],
		"quality": ["画面质量", quality_text],
		"fps": ["目标帧率", "不限帧" if cap == 0 else "%d FPS" % cap],
		"vsync": ["垂直同步", "开启" if _bool_value("vsync", true) else "关闭"],
		"shake": ["屏幕震动", "开启" if _shake_enabled else "关闭"],
		"master_volume": ["总音量", "%d%%" % _int_value("master_volume", 80)],
		"effects_volume": ["战斗音效", "%d%%" % _int_value("effects_volume", 85)],
		"music_volume": ["战斗音乐", "%d%%" % _int_value("music_volume", 45)],
		"radio_volume": ["战场通信", "%d%%" % _int_value("radio_volume", 85)],
		"music_track": ["选择音乐 · N", str((_snapshot.get("music", {}) as Dictionary).get("name", "战斗音乐"))],
		"weather_mode": ["战场天气", str(_snapshot.get("weather_label", "随机"))],
		"remote_mouse": ["第三人称鼠标", "远程桌面" if _bool_value("remote_mouse", false) else "本地"],
	}
	for id: String in _setting_buttons:
		var parts: Array = values[id]
		(_setting_buttons[id] as Button).text = "%s\n%s" % [parts[0], parts[1]]


func _update_pause() -> void:
	var endless := _is_endless()
	_shop_box.visible = endless
	_pause_heading.text = "防线整备" if endless else "战场已暂停"
	_pause_kicker.text = "ENDLESS DEFENSE / TIME FROZEN" if endless else "OPERATION SUSPENDED"
	_pause_retry.text = "重新防守" if endless else "重新部署"
	_pause_tactics.text = "怪物与倒计时已停止。购买升级后继续防守；注意保护防线和自己的战车。" if endless else "绿色整备点提供补给；起火残骸可能殉爆，保持距离。"
	var focus_before := get_viewport().gui_get_focus_owner()
	var focus_key := str(endless)
	if endless:
		var defense := _endless_snapshot()
		_shop_wallet.text = "整备资源 %d" % maxi(0, int(defense.get("scrap", 0)))
		_shop_summary.text = "第 %d 波 · 防线 %d / %d · 击杀 %d" % [maxi(1, int(defense.get("wave", 1))), ceili(maxf(0.0, float(defense.get("base_hp", 0.0)))), ceili(maxf(1.0, float(defense.get("base_max_hp", 1.0)))), maxi(0, int(defense.get("kills", 0)))]
		var entries: Dictionary = {}
		for upgrade: Dictionary in defense.get("upgrades", []):
			entries[str(upgrade.get("id", ""))] = upgrade
		for id: String in _upgrade_buttons:
			var button := _upgrade_buttons[id] as Button
			var entry: Dictionary = entries.get(id, {})
			var level := maxi(0, int(entry.get("level", 0)))
			var maximum := maxi(0, int(entry.get("max_level", 0)))
			var cost := maxi(0, int(entry.get("cost", 0)))
			var maxed := maximum > 0 and level >= maximum
			var can_buy := not entry.is_empty() and bool(entry.get("available", false)) and not maxed and cost <= maxi(0, int(defense.get("scrap", 0)))
			button.disabled = not can_buy
			var rank := " · LV.%d/%d" % [level, maximum] if maximum > 0 else ""
			var price := "已达上限" if maxed else "%d 资源%s" % [cost, " · 资源不足" if cost > int(defense.get("scrap", 0)) else (" · 暂无需整备" if not can_buy else "")]
			button.text = "%s%s\n%s" % [str(entry.get("name", "整备项目")), rank, price]
			var description := str(entry.get("description", "等待整备信息"))
			(_upgrade_descriptions[id] as Label).text = description
			button.tooltip_text = description
			focus_key += id + str(can_buy)
	if focus_key != _pause_focus_key:
		_pause_focus_key = focus_key
		var focus_buttons: Array[Button] = [_pause_buttons[0]]
		if endless:
			for id: String in _upgrade_buttons:
				var upgrade_button := _upgrade_buttons[id] as Button
				if not upgrade_button.disabled:
					focus_buttons.append(upgrade_button)
		focus_buttons.append_array(_pause_buttons.slice(1))
		_wire_vertical_focus(focus_buttons)
		# A purchased upgrade may become unaffordable or maxed. Keep controller
		# navigation on a usable item instead of stranding it on a disabled button.
		if _mode == "paused" and focus_before is Button and (focus_before as Button).disabled:
			focus_buttons[0].grab_focus()
	_apply_pause_layout()
	var notice := str(_snapshot.get("notice", ""))
	if not notice.is_empty():
		_pause_notice.text = notice
		return
	match str(_snapshot.get("pause_reason", "manual")):
		"focus_lost":
			_pause_notice.text = "窗口失去焦点，战场已自动暂停。请主动继续行动。"
		"controller_disconnected":
			_pause_notice.text = "手柄连接已中断，战场已暂停。重新连接手柄按 A / START，或用键鼠继续。"
		_:
			_pause_notice.text = "战斗已暂停。按 ESC 或选择继续行动返回战场。"


func _update_result() -> void:
	if _is_endless():
		var defense := _endless_snapshot()
		_result_kicker.text = "ENDLESS DEFENSE / FINAL REPORT"
		_result_kicker.add_theme_color_override(&"font_color", ThemeFactory.GOLD)
		_result_title.text = str(defense.get("defeat_reason", "防守结束"))
		_result_score.text = str(maxi(1, int(defense.get("wave", 1))))
		_result_score_caption.text = "抵达波次"
		_result_kills.text = str(maxi(0, int(defense.get("kills", 0))))
		_result_kills_caption.text = "击退巨兽"
		_result_time.text = _format_time(_float_value("time", 0.0))
		_result_time_caption.text = "坚守时间"
		_result_career.text = "最高守至第 %d 波 · 最多击杀 %d\n本局剩余资源 %d · 再次防守将重新整备" % [maxi(0, int(defense.get("best_wave", 0))), maxi(0, int(defense.get("best_kills", 0))), maxi(0, int(defense.get("scrap", 0)))]
		_result_primary.text = "重新防守"
		_result_retry.visible = false
		_wire_vertical_focus([_result_primary, _result_menu])
		return
	_result_score_caption.text = "作战评分"
	_result_kills_caption.text = "本次击毁"
	_result_time_caption.text = "作战用时"
	_result_retry.visible = true
	_wire_vertical_focus([_result_primary, _result_retry, _result_menu])
	var won := _mode == "won"
	_result_kicker.text = "MISSION ACCOMPLISHED" if won else "OPERATION FAILED"
	_result_kicker.add_theme_color_override(&"font_color", ThemeFactory.GREEN if won else ThemeFactory.RED)
	_result_title.text = "行动成功" if won else "战车失去作战能力"
	_result_score.text = str(maxi(0, _int_value("score", 0)))
	_result_kills.text = str(maxi(0, _int_value("kills", 0)))
	_result_time.text = _format_time(_float_value("time", 0.0))
	_result_career.text = "坦克等级 LV.%02d · 累计击毁 %d · 最高评分 %d" % [
		maxi(1, _int_value("tank_level", 1)),
		maxi(0, _int_value("lifetime_kills", 0)),
		maxi(0, _int_value("best_score", 0)),
	]
	_result_primary.text = ("进入下一关" if _bool_value("has_next_mission", false) else "返回指挥中心") if won else "重新部署"


func _result_primary_action() -> void:
	if _is_endless():
		retry_requested.emit()
		return
	if _mode == "won":
		if _bool_value("has_next_mission", false):
			next_requested.emit()
		else:
			menu_requested.emit()
	else:
		retry_requested.emit()


func _focus_current_mode() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var target: Variant = _focus_targets.get(_mode)
	if target is Control:
		var control := target as Control
		if control.is_visible_in_tree():
			control.grab_focus()


func _apply_safe_margins() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	var horizontal_factor := 0.035 if aspect < 2.0 else 0.065
	var horizontal := clampf(viewport_size.x * horizontal_factor, 24.0, 180.0)
	var vertical := clampf(viewport_size.y * 0.032, 18.0, 58.0)
	for container: MarginContainer in _safe_containers:
		container.add_theme_constant_override(&"margin_left", int(horizontal))
		container.add_theme_constant_override(&"margin_right", int(horizontal))
		container.add_theme_constant_override(&"margin_top", int(vertical))
		container.add_theme_constant_override(&"margin_bottom", int(vertical))
	_apply_pause_layout()
	if is_instance_valid(_result_panel):
		_result_panel.custom_minimum_size = Vector2(minf(760.0, maxf(280.0, viewport_size.x - 48.0)), minf(640.0, maxf(240.0, viewport_size.y - 48.0)))


func _apply_pause_layout() -> void:
	if not is_instance_valid(_pause_panel):
		return
	var viewport_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	var available := Vector2(maxf(280.0, viewport_size.x - 64.0), maxf(240.0, viewport_size.y - 64.0))
	_pause_panel.custom_minimum_size = Vector2(minf(1100.0 if _is_endless() else 620.0, available.x), minf(740.0 if _is_endless() else 650.0, available.y))
	_pause_grid.columns = 2 if _is_endless() and available.x >= 1000.0 else 1


func _is_endless() -> bool:
	return str(_snapshot.get("run_type", "campaign")) == "endless"


func _endless_snapshot() -> Dictionary:
	var defense: Variant = _snapshot.get("endless", {})
	return defense if defense is Dictionary else {}


func _new_layer(layer_name: String) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _new_safe_container(parent: Control) -> MarginContainer:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(safe)
	_safe_containers.append(safe)
	return safe


func _add_dimmer(parent: Control, opacity: float) -> void:
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.01, 0.015, 0.012, opacity)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dimmer)


func _label(text_value: String, variation: StringName = &"Body") -> Label:
	var value := Label.new()
	value.text = text_value
	value.theme_type_variation = variation
	return value


func _button(text_value: String, variation: StringName, action: Callable) -> Button:
	var value := Button.new()
	value.text = text_value
	value.theme_type_variation = variation
	value.focus_mode = Control.FOCUS_ALL
	value.custom_minimum_size = Vector2(0.0, 58.0)
	value.pressed.connect(action)
	value.mouse_entered.connect(value.grab_focus)
	return value


func _panel(variation: StringName) -> PanelContainer:
	var value := PanelContainer.new()
	value.theme_type_variation = variation
	return value


func _progress(variation: StringName, maximum: float) -> ProgressBar:
	var value := ProgressBar.new()
	value.theme_type_variation = variation
	value.max_value = maximum
	value.show_percentage = false
	value.custom_minimum_size = Vector2(0.0, 10.0)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value


func _spacer(horizontal: bool, vertical: bool) -> Control:
	var value := Control.new()
	if horizontal:
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value


func _fixed_spacer(height: float) -> Control:
	var value := Control.new()
	value.custom_minimum_size = Vector2(0.0, height)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value


func _metric_card(caption: String) -> PanelContainer:
	var panel := _panel(&"HUDPanel")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(112.0, 112.0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var value := _label("0", &"Metric")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	var name_label := _label(caption, &"Micro")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	panel.set_meta("value", value)
	panel.set_meta("caption", name_label)
	return panel


func _wire_vertical_focus(buttons: Array[Button]) -> void:
	if buttons.is_empty():
		return
	for index in range(buttons.size()):
		var button := buttons[index]
		var previous := buttons[(index - 1 + buttons.size()) % buttons.size()]
		var following := buttons[(index + 1) % buttons.size()]
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(following)
		button.focus_neighbor_left = button.get_path_to(previous)
		button.focus_neighbor_right = button.get_path_to(following)


func _wire_settings_focus(buttons: Array[Button], back_button: Button) -> void:
	for index in buttons.size():
		var button := buttons[index]
		var beside_index := index + 1 if index % 2 == 0 else index - 1
		var beside := buttons[beside_index] if beside_index < buttons.size() else back_button
		var above := buttons[index - 2] if index >= 2 else back_button
		var below := buttons[index + 2] if index + 2 < buttons.size() else back_button
		button.focus_neighbor_top = button.get_path_to(above)
		button.focus_neighbor_bottom = button.get_path_to(below)
		button.focus_neighbor_left = button.get_path_to(beside)
		button.focus_neighbor_right = button.get_path_to(beside)
	back_button.focus_neighbor_bottom = back_button.get_path_to(buttons[0])
	back_button.focus_neighbor_top = back_button.get_path_to(buttons[-1])
	back_button.focus_neighbor_left = back_button.get_path_to(buttons[-1])
	back_button.focus_neighbor_right = back_button.get_path_to(buttons[0])


func _set_mouse_passthrough(root: Node) -> void:
	if root is Control:
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in root.get_children():
		_set_mouse_passthrough(child)


func _float_value(key: String, fallback: float) -> float:
	var value: Variant = _snapshot.get(key, fallback)
	return float(value) if value is int or value is float else fallback


func _int_value(key: String, fallback: int) -> int:
	var value: Variant = _snapshot.get(key, fallback)
	return int(value) if value is int or value is float else fallback


func _bool_value(key: String, fallback: bool) -> bool:
	var value: Variant = _snapshot.get(key, fallback)
	return bool(value) if value is bool else fallback


func _format_time(seconds: float) -> String:
	var safe_seconds := maxi(0, floori(seconds))
	return "%02d:%02d" % [floori(float(safe_seconds) / 60.0), safe_seconds % 60]


func _cooldown_text(label_text: String, seconds: float) -> String:
	return "%s · READY" % label_text if seconds <= 0.01 else "%s · %.1fs" % [label_text, seconds]


func _compact_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 10000:
		return "%.1fK" % (float(value) / 1000.0)
	return str(value)
