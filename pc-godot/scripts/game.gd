extends Node3D
## Chapter 01 vertical slice and top-level game flow.

const TankScript = preload("res://actors/tank.gd")
const ProjectileScript = preload("res://actors/projectile.gd")
const MineScript = preload("res://actors/mine.gd")
const ExplosionScript = preload("res://actors/explosion_fx.gd")
const ArenaScript = preload("res://scenes/missions/industrial_arena.gd")

var mode := "title"
var player: TankActor
var boss: TankActor
var arena: IndustrialArena
var ui: Control
var enemies: Array[TankActor] = []
var mission_kills := 0
var total_run_kills := 0
var target_kills := 6
var score := 0
var play_time := 0.0
var current_run_id := ""
var objective := "整备装甲，等待行动命令"
var notice := ""
var notice_time := 0.0
var pause_reason := "manual"
var _title_rig: Node3D
var _cleanup: Array[Dictionary] = []
var _smoke_test := false


func _ready() -> void:
	_setup_inputs()
	_create_ui()
	_show_title_tank()
	get_window().focus_exited.connect(_on_focus_lost)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_smoke_test = "--smoke-test" in OS.get_cmdline_user_args()
	print("IRON_EMBERS_PC_READY | Godot native | Chapter 01 | mines + EMP + boss")
	if _smoke_test:
		call_deferred("start_game")


func _build_arena() -> void:
	if is_instance_valid(arena):
		arena.free()
	arena = ArenaScript.new()
	arena.name = "GrayIgnitionArena"
	arena.game = self
	add_child(arena)


func _create_ui() -> void:
	var ui_script: Script = load("res://ui/game_ui.gd")
	ui = ui_script.new()
	ui.name = "GameUI"
	add_child(ui)
	_connect_ui_signal("start_requested", start_game)
	_connect_ui_signal("resume_requested", resume_game)
	_connect_ui_signal("retry_requested", retry_game)
	_connect_ui_signal("menu_requested", return_to_menu)
	_connect_ui_signal("settings_requested", open_settings)
	_connect_ui_signal("quit_requested", quit_game)
	if ui.has_signal("setting_requested"):
		ui.connect("setting_requested", _on_setting_requested)


func _connect_ui_signal(signal_name: StringName, target: Callable) -> void:
	if ui.has_signal(signal_name):
		ui.connect(signal_name, target)


func _show_title_tank() -> void:
	_clear_combat_nodes()
	_build_arena()
	player = _spawn_tank("CommandTank", Vector3(7.0, 0.05, 44.5), TankActor.TEAM_PLAYER, true, false, "line")
	player.rotation.y = PI - 0.05
	player.active = false
	_build_title_shot()
	objective = "灰中点火 / CHAPTER 01"
	mode = "title"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_title_shot() -> void:
	_title_rig = Node3D.new()
	_title_rig.name = "TitleShowcaseRig"
	add_child(_title_rig)

	var showcase_camera := Camera3D.new()
	showcase_camera.name = "TitleCamera"
	showcase_camera.fov = 47.0
	showcase_camera.near = 0.08
	showcase_camera.far = 260.0
	showcase_camera.position = Vector3(1.0, 3.6, 53.0)
	_title_rig.add_child(showcase_camera)
	showcase_camera.look_at(Vector3(5.5, 1.2, 43.7), Vector3.UP)
	showcase_camera.current = true

	var key_light := SpotLight3D.new()
	key_light.name = "ArmorKeyLight"
	key_light.position = Vector3(4.0, 10.5, 51.0)
	key_light.light_color = Color("ffd5aa")
	key_light.light_energy = 6.0
	key_light.spot_range = 28.0
	key_light.spot_angle = 38.0
	key_light.shadow_enabled = true
	_title_rig.add_child(key_light)
	key_light.look_at(player.global_position + Vector3.UP * 1.0, Vector3.UP)

	var rim_light := OmniLight3D.new()
	rim_light.name = "ArmorRimLight"
	rim_light.position = Vector3(14.0, 3.2, 38.0)
	rim_light.light_color = Color("53cbd2")
	rim_light.light_energy = 2.2
	rim_light.omni_range = 13.0
	rim_light.shadow_enabled = false
	_title_rig.add_child(rim_light)


func start_game() -> void:
	_clear_combat_nodes()
	_build_arena()
	mission_kills = 0
	total_run_kills = 0
	score = 0
	play_time = 0.0
	current_run_id = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	SaveService.begin_run(current_run_id)
	player = _spawn_tank("PlayerTank", Vector3(0, 0.05, 51), TankActor.TEAM_PLAYER, true, false, "line")
	var layout := [
		[Vector3(-4, 0.05, 19), "scout"], [Vector3(4, 0.05, 13), "line"],
		[Vector3(-4, 0.05, 1), "heavy"], [Vector3(4, 0.05, -15), "scout"],
		[Vector3(-4, 0.05, -29), "sniper"], [Vector3(4, 0.05, -39), "heavy"],
	]
	for index in range(layout.size()):
		var data: Array = layout[index]
		var enemy := _spawn_tank("Enemy_%02d" % index, data[0], TankActor.TEAM_ENEMY, false, false, data[1])
		enemies.append(enemy)
	boss = _spawn_tank("Boss_IronFang", Vector3(0, 0.05, -54), TankActor.TEAM_ENEMY, false, true, "boss")
	boss.boss_phase_changed.connect(_on_boss_phase_changed)
	enemies.append(boss)
	arena.set_boss_gate_open(false)
	mode = "playing"
	objective = "突破工业街区 · 击毁敌军 0 / %d" % target_kills
	notify("第一章 · 灰中点火\n突破封锁，找到围城指挥车“铁牙”", 4.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _smoke_test:
		get_tree().create_timer(1.5).timeout.connect(_finish_smoke_test)


func retry_game() -> void:
	start_game()


func return_to_menu() -> void:
	if mode == "settings":
		mode = "paused" if not current_run_id.is_empty() and is_instance_valid(player) and not player.destroyed else "title"
		return
	if not current_run_id.is_empty() and mode in ["playing", "paused"]:
		SaveService.settle_run(current_run_id, false, score, 0)
	current_run_id = ""
	_show_title_tank()


func pause_game(reason := "manual") -> void:
	if mode != "playing":
		return
	pause_reason = reason
	mode = "paused"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	notify("行动已暂停", 1.2)


func resume_game() -> void:
	if mode != "paused":
		return
	mode = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_settings() -> void:
	if mode == "playing":
		pause_game("settings")
	mode = "settings"


func quit_game() -> void:
	SaveService.save_now()
	SettingsService.save_settings()
	get_tree().quit()


func is_combat_running() -> bool:
	return mode == "playing"


func _process(delta: float) -> void:
	notice_time = maxf(0.0, notice_time - delta)
	if notice_time <= 0.0:
		notice = ""
	if mode == "playing":
		play_time += delta
		_update_mouse_aim()
	_update_cleanup(delta)
	if is_instance_valid(ui) and ui.has_method("update_snapshot"):
		ui.call("update_snapshot", get_ui_snapshot())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		SettingsService.cycle_display_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if mode == "playing":
			pause_game()
		elif mode == "paused":
			resume_game()
		elif mode == "settings":
			mode = "paused" if is_instance_valid(player) and not player.destroyed else "title"
		get_viewport().set_input_as_handled()


func _update_mouse_aim() -> void:
	if not is_instance_valid(player) or player.destroyed or not is_instance_valid(player.camera):
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := player.camera.project_ray_origin(mouse)
	var ray := player.camera.project_ray_normal(mouse)
	var intersection: Variant = Plane(Vector3.UP, 0.08).intersects_ray(origin, ray)
	if intersection is Vector3:
		player.aim_point = intersection


func _spawn_tank(node_name: String, at: Vector3, tank_team: int, controlled: bool, chapter_boss: bool, kind: String) -> TankActor:
	var tank := TankScript.new() as TankActor
	tank.name = node_name
	tank.game = self
	tank.team = tank_team
	tank.is_player = controlled
	tank.is_boss = chapter_boss
	tank.archetype = kind
	tank.position = at
	add_child(tank)
	tank.tank_destroyed.connect(_on_tank_destroyed)
	return tank


func spawn_projectile(owner_tank: TankActor, at: Vector3, direction: Vector3, damage: float, speed: float, splash: float, kind: String) -> void:
	var projectile := ProjectileScript.new() as IronProjectile
	projectile.name = "Shell_%d" % Time.get_ticks_usec()
	projectile.game = self
	projectile.owner_tank = owner_tank
	projectile.team = owner_tank.team
	projectile.position = at
	projectile.direction = direction.normalized()
	projectile.damage = damage
	projectile.speed = speed
	projectile.splash_radius = splash
	projectile.weapon_kind = kind
	projectile.add_to_group("projectiles")
	add_child(projectile)


func spawn_mine(source: TankActor, at: Vector3) -> void:
	var mine := MineScript.new() as TankMine
	mine.name = "Mine_%d" % Time.get_ticks_usec()
	mine.game = self
	mine.team = source.team
	mine.source_tank = source
	mine.position = Vector3(at.x, 0.02, at.z)
	add_child(mine)
	if source.is_player:
		notify("地雷已部署 · 1.2 秒后完成武装", 1.5)


func emit_emp(source: TankActor, radius: float) -> void:
	spawn_emp_visual(source.global_position, radius / 18.0)
	var removed := 0
	for node: Node in get_tree().get_nodes_in_group("mines"):
		if node is TankMine and source.global_position.distance_to((node as TankMine).global_position) <= radius:
			(node as TankMine).defuse()
			removed += 1
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		if node is TankActor:
			var tank := node as TankActor
			if tank.team != source.team and tank.is_targetable() and source.global_position.distance_to(tank.global_position) <= radius:
				tank.apply_emp(2.8 if not tank.is_boss else 1.6)
	notify("电磁脉冲释放 · 排除 %d 枚地雷" % removed, 2.0)


func radial_damage(at: Vector3, radius: float, damage: float, attacker_team: int) -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		if not node is TankActor:
			continue
		var tank := node as TankActor
		if tank.team == attacker_team or not tank.is_targetable():
			continue
		var distance := at.distance_to(tank.global_position)
		if distance <= radius and has_line_of_sight(at + Vector3.UP * 0.2, tank.global_position + Vector3.UP):
			var falloff := lerpf(0.35, 1.0, 1.0 - distance / maxf(radius, 0.01))
			tank.receive_damage(damage * falloff, attacker_team, tank.global_position)


func spawn_explosion(at: Vector3, scale_factor := 1.0) -> void:
	var effect := ExplosionScript.create(at, scale_factor, true)
	add_child(effect)
	if mode == "playing" and is_instance_valid(player) and not player.destroyed:
		var distance := player.global_position.distance_to(at)
		var shake := clampf(1.0 - distance / 48.0, 0.0, 1.0) * scale_factor * 0.72
		player.add_camera_shake(shake)


func spawn_impact(at: Vector3, heavy: bool) -> void:
	var effect := ExplosionScript.create(at, 0.42 if heavy else 0.2, false)
	add_child(effect)


func spawn_muzzle_flash(at: Vector3, color: Color, scale_factor: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = 7.0 * scale_factor
	light.omni_range = 8.0 * scale_factor
	light.shadow_enabled = false
	add_child(light)
	var flash := ArtFactory.add_sphere(light, "MuzzleFlash", Vector3.ZERO, 0.28 * scale_factor, ArtFactory.material(color, 0.0, 0.2, 8.0), 10)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.12)
	tween.parallel().tween_property(flash, "scale", Vector3.ONE * 3.0, 0.12)
	tween.tween_callback(light.queue_free)


func spawn_emp_visual(at: Vector3, scale_factor := 1.0) -> void:
	var root := Node3D.new()
	root.position = at + Vector3.UP * 0.18
	add_child(root)
	var surface := ArtFactory.material(Color(0.18, 0.88, 1.0, 0.65), 0.1, 0.25, 5.0)
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for offset in [0.0, 0.18, 0.36]:
		var ring := ArtFactory.add_torus(root, "EMPWave", Vector3.UP * offset, 1.0, 0.09, surface)
		ring.scale = Vector3.ONE * maxf(0.1, scale_factor)
		var tween := create_tween()
		tween.tween_interval(offset * 0.35)
		tween.tween_property(ring, "scale", Vector3.ONE * (18.0 * scale_factor), 0.65)
		tween.tween_callback(ring.queue_free)
	get_tree().create_timer(1.2).timeout.connect(root.queue_free)


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_tank_destroyed(tank: TankActor, attacker_team: int) -> void:
	if tank.is_player:
		mode = "lost"
		objective = "主战坦克失去战斗能力"
		SaveService.settle_run(current_run_id, false, score, 0)
		AudioService.play_ui("defeat", -3.0)
		return
	if attacker_team == TankActor.TEAM_PLAYER:
		total_run_kills += 1
		score += 900 if tank.is_boss else (180 if tank.archetype == "heavy" else 120)
		SaveService.credit_run_kills(current_run_id, total_run_kills)
	if tank.is_boss:
		mode = "won"
		objective = "铁牙已摧毁 · 灰中点火行动完成"
		SaveService.settle_run(current_run_id, true, score + 2500, 0)
		AudioService.play_ui("victory", -2.0)
		notify("行动成功 · 围城指挥车已摧毁", 5.0)
		return
	if tank.counts_for_objective:
		mission_kills += 1
	objective = "突破工业街区 · 击毁敌军 %d / %d" % [mini(mission_kills, target_kills), target_kills]
	if mission_kills >= target_kills and is_instance_valid(boss) and not boss.active:
		_activate_boss()


func _activate_boss() -> void:
	arena.set_boss_gate_open(true)
	boss.activate_boss()
	objective = "最终目标 · 摧毁“铁牙”围城指挥车"
	notify("警告：铁牙进入战场\n红色预警表示火箭齐射，可用 EMP 打断", 4.5)


func _on_boss_phase_changed(phase: int) -> void:
	notify("铁牙装甲阶段 %d / 3 · 呼叫护卫" % phase, 3.0)
	var offsets := [Vector3(-10, 0.05, -48), Vector3(10, 0.05, -48)]
	for index in range(2):
		var guard := _spawn_tank("BossGuard_%d_%d" % [phase, index], offsets[index] + Vector3(0, 0, phase * 2.0), TankActor.TEAM_ENEMY, false, false, "scout" if phase == 2 else "heavy")
		guard.counts_for_objective = false
		enemies.append(guard)


func notify(text: String, duration := 2.0) -> void:
	notice = text
	notice_time = duration


func schedule_cleanup(node: Node, delay: float) -> void:
	_cleanup.append({"node": node, "time": delay})


func _update_cleanup(delta: float) -> void:
	for index in range(_cleanup.size() - 1, -1, -1):
		_cleanup[index]["time"] = float(_cleanup[index]["time"]) - delta
		if float(_cleanup[index]["time"]) <= 0.0:
			var node: Node = _cleanup[index]["node"]
			if is_instance_valid(node):
				node.queue_free()
			_cleanup.remove_at(index)


func get_ui_snapshot() -> Dictionary:
	var player_valid := is_instance_valid(player)
	var boss_valid := is_instance_valid(boss) and boss.active and not boss.destroyed
	return {
		"mode": mode,
		"hp": player.hp if player_valid else 0.0,
		"max_hp": player.max_hp if player_valid else 240.0,
		"armor": roundi(player.armor * 100.0) if player_valid else 0,
		"kills": mission_kills,
		"target_kills": target_kills,
		"score": score,
		"time": play_time,
		"mine_ammo": player.mine_ammo if player_valid else 0,
		"mine_cooldown": player.mine_cooldown if player_valid else 0.0,
		"emp_cooldown": player.emp_cooldown if player_valid else 0.0,
		"dash_cooldown": player.dash_cooldown if player_valid else 0.0,
		"weapon": "120mm 滑膛炮",
		"reload": player.reload if player_valid else 0.0,
		"boss_name": boss.display_name if boss_valid else "",
		"boss_hp": boss.hp if boss_valid else 0.0,
		"boss_max_hp": boss.max_hp if boss_valid else 1.0,
		"boss_phase": boss.boss_phase if boss_valid else 0,
		"boss_warning": boss.boss_warning if boss_valid else false,
		"objective": objective,
		"notice": notice,
		"lifetime_kills": int(SaveService.profile.get("lifetime_kills", 0)),
		"tank_level": int(SaveService.profile.get("tank_level", 1)),
		"best_score": int(SaveService.profile.get("best_score", 0)),
		"display_mode": SettingsService.display_mode,
		"quality": SettingsService.quality,
		"fps_cap": SettingsService.fps_cap,
		"vsync": SettingsService.vsync,
		"screen_shake": SettingsService.screen_shake,
		"master_volume": SettingsService.master_volume,
		"effects_volume": SettingsService.effects_volume,
		"pause_reason": pause_reason,
	}


func _on_setting_requested(id: String) -> void:
	match id:
		"display_mode": SettingsService.cycle_display_mode()
		"quality": SettingsService.cycle_quality()
		"fps": SettingsService.cycle_fps_cap()
		"vsync":
			SettingsService.vsync = not SettingsService.vsync
			SettingsService.apply()
		"shake":
			SettingsService.screen_shake = not SettingsService.screen_shake
			SettingsService.apply()
		"master_volume":
			SettingsService.master_volume = (SettingsService.master_volume + 10) % 110
			SettingsService.apply()
		"effects_volume":
			SettingsService.effects_volume = (SettingsService.effects_volume + 10) % 110
			SettingsService.apply()
	AudioService.play_ui("click")


func _on_focus_lost() -> void:
	if mode == "playing":
		pause_game("focus_lost")


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and mode == "playing":
		pause_game("controller_disconnected")


func _clear_combat_nodes() -> void:
	if is_instance_valid(_title_rig):
		_title_rig.free()
	_title_rig = null
	for group in ["tanks", "mines", "projectiles"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node):
				node.free()
	enemies.clear()
	boss = null
	player = null


func _setup_inputs() -> void:
	var keyboard := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"fire": [], "dash": [KEY_SPACE], "emp": [KEY_E], "place_mine": [KEY_M],
		"camera": [KEY_C], "pause": [KEY_ESCAPE], "confirm": [KEY_ENTER],
		"menu_up": [KEY_UP, KEY_W], "menu_down": [KEY_DOWN, KEY_S],
	}
	for action: String in keyboard:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode: int in keyboard[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
	if not InputMap.has_action("aim_left"):
		for action in ["aim_left", "aim_right", "aim_up", "aim_down"]:
			InputMap.add_action(action, 0.24)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mouse)
	_add_joy_button("dash", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("emp", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("place_mine", JOY_BUTTON_RIGHT_STICK)
	_add_joy_button("camera", JOY_BUTTON_Y)
	_add_joy_button("pause", JOY_BUTTON_START)
	_add_joy_button("confirm", JOY_BUTTON_A)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)


func _add_joy_button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


func _finish_smoke_test() -> void:
	var okay := is_instance_valid(player) and enemies.size() == 7 and is_instance_valid(ui) and mode == "playing"
	print("IRON_EMBERS_SMOKE_PASS" if okay else "IRON_EMBERS_SMOKE_FAIL")
	get_tree().quit(0 if okay else 1)
