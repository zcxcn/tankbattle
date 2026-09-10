extends Node3D
## Six-mission campaign, patrol encounters and native PC game flow.

const TankScript = preload("res://actors/tank.gd")
const ProjectileScript = preload("res://actors/projectile.gd")
const MineScript = preload("res://actors/mine.gd")
const ExplosionScript = preload("res://actors/explosion_fx.gd")
const MissionCatalog = preload("res://data/mission_catalog.gd")
const VehicleCatalog = preload("res://data/vehicle_catalog.gd")
const MissionTarget = preload("res://actors/mission_target.gd")
const ArenaScript = preload("res://scenes/missions/industrial_arena.gd")
const Deployment = preload("res://scripts/battle_deployment.gd")
const WreckScript = preload("res://actors/tank_wreck.gd")
const TrackMarksScript = preload("res://scripts/track_marks.gd")
const WeatherCatalog = preload("res://data/weather_catalog.gd")

var current_weather := "dry"

var mission_index := 0
var selected_mission := 0
var selected_chassis := 1
var mission_data: Dictionary = {}
var objective_complete := false
var objective_progress := 0.0
var mission_target: StaticBody3D
var _objective_marker: Node3D
var _supply_points: Array[Dictionary] = []
var deployment_seed := 0
var result_delay := 0.0
var _contact_scan := 0.0
var _reported_contacts: Dictionary = {}
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
var _settings_return_mode := "title"
var _title_rig: Node3D
var _cleanup: Array[Dictionary] = []
var _smoke_test := false
var _quitting := false
var _active_encounter := 0
var _encounter_pause := 0.0
var _encounter_cleared := false
const ENCOUNTER_INTERVAL := 5.0


func _ready() -> void:
	selected_chassis = clampi(int(SaveService.profile.get("selected_chassis", 1)), 0, 2)
	selected_mission = unlocked_mission_count() - 1
	_setup_inputs()
	var gamepad := preload("res://scripts/gamepad_input.gd").new()
	gamepad.name = "GamepadInput"
	gamepad.game = self
	add_child(gamepad)
	mission_data = MissionCatalog.get_mission(selected_mission)
	_resolve_weather()
	_create_ui()
	_show_title_tank()
	get_window().focus_exited.connect(_on_focus_lost)
	get_tree().auto_accept_quit = false
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_smoke_test = "--smoke-test" in OS.get_cmdline_user_args()
	print("IRON_EMBERS_PC_READY | Godot native | Campaign 0.4.4 | audible weapons + visible muzzle + stronger recoil")
	if _smoke_test:
		call_deferred("start_game")


func _build_arena() -> void:
	if is_instance_valid(arena):
		arena.free()
	arena = ArenaScript.new()
	arena.name = "GrayIgnitionArena"
	arena.game = self
	arena.mission_index = mission_index
	arena.weather_kind = current_weather
	add_child(arena)
	var tracks := TrackMarksScript.new()
	tracks.game = self
	tracks.set_wetness(WeatherCatalog.wetness(current_weather))
	arena.add_child(tracks)


func _resolve_weather() -> void:
	current_weather = WeatherCatalog.resolve(SettingsService.weather_mode, int(get_meta("weather_seed", randi())))


func _apply_weather_setting() -> void:
	_resolve_weather()
	if is_instance_valid(arena):
		arena.set_weather_kind(current_weather)
		var tracks := arena.get_node_or_null("TrackMarks")
		if is_instance_valid(tracks):
			tracks.set_wetness(WeatherCatalog.wetness(current_weather))


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
	_connect_ui_signal("next_requested", next_mission)
	_connect_ui_signal("mission_requested", cycle_mission)
	_connect_ui_signal("chassis_requested", cycle_chassis)
	if ui.has_signal("setting_requested"):
		ui.connect("setting_requested", _on_setting_requested)


func _connect_ui_signal(signal_name: StringName, target: Callable) -> void:
	if ui.has_signal(signal_name):
		ui.connect(signal_name, target)


func _show_title_tank() -> void:
	_clear_combat_nodes()
	mission_index = selected_mission
	_build_arena()
	player = _spawn_tank("CommandTank", Vector3(7.0, 0.05, 44.5), TankActor.TEAM_PLAYER, true, false, ["scout", "line", "heavy"][selected_chassis])
	player.rotation.y = PI - 0.05
	player.active = false
	_build_title_shot()
	objective = "第 %02d 章 · %s" % [selected_mission + 1, MissionCatalog.get_mission(selected_mission).name]
	mode = "title"
	AudioService.set_game_state(mode)
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
	_settle_abandoned_run()
	AudioService.set_game_state("title")
	_clear_combat_nodes()
	mission_index = clampi(selected_mission, 0, MissionCatalog.count() - 1)
	mission_data = MissionCatalog.get_mission(mission_index)
	_resolve_weather()
	_build_arena()
	mission_kills = 0
	total_run_kills = 0
	target_kills = mission_data.enemy_layout.size()
	score = 0
	play_time = 0.0
	objective_complete = false
	objective_progress = 0.0
	result_delay = 0.0
	_reported_contacts.clear()
	_contact_scan = 0.0
	_active_encounter = 0
	_encounter_pause = 0.0
	_encounter_cleared = false
	pause_reason = "manual"
	_settings_return_mode = "paused"
	current_run_id = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	SaveService.begin_run(current_run_id)
	player = _spawn_tank("PlayerTank", mission_data.player_start, TankActor.TEAM_PLAYER, true, false, ["scout", "line", "heavy"][selected_chassis])
	deployment_seed = int(get_meta("deployment_seed", randi()))
	var deployed := Deployment.build(mission_data, arena.get_spawn_candidates(), deployment_seed)
	if deployed.size() != mission_data.enemy_layout.size():
		push_error("Validated deployment candidates could not fit the mission roster")
		deployed.assign(mission_data.enemy_layout)
	for index in range(deployed.size()):
		var data: Dictionary = deployed[index]
		var enemy := _spawn_tank("Enemy_%02d" % index, data.position, TankActor.TEAM_ENEMY, false, false, data.kind)
		enemy.patrol_route.assign(data.get("patrol", []))
		enemy.rotation.y = float(data.get("yaw", 0.0))
		enemy.max_hp *= float(mission_data.health_multiplier)
		enemy.hp = enemy.max_hp
		enemy.projectile_damage *= float(mission_data.damage_multiplier)
		enemy.fire_interval *= float(mission_data.reload_multiplier)
		enemy.set_meta("encounter_index", index >> 1)
		enemies.append(enemy)
	boss = _spawn_tank("Boss_IronFang", mission_data.boss_position, TankActor.TEAM_ENEMY, false, true, "boss")
	boss.display_name = mission_data.boss_name
	boss.max_hp *= 1.0 + mission_index * 0.12
	boss.hp = boss.max_hp
	boss.boss_phase_changed.connect(_on_boss_phase_changed)
	enemies.append(boss)
	arena.set_boss_gate_open(false)
	_create_mission_props()
	mode = "playing"
	AudioService.set_game_state(mode)
	AudioService.radio("mission_start")
	_update_encounter_objective()
	notify("第 %02d 章 · %s\n%s" % [mission_index + 1, mission_data.name, mission_data.briefing], 6.0)
	sync_pointer_mode()
	if _smoke_test:
		get_tree().create_timer(1.5).timeout.connect(_finish_smoke_test)


func retry_game() -> void:
	start_game()


func return_to_menu() -> void:
	if mode == "settings":
		_close_settings()
		return
	_settle_abandoned_run()
	current_run_id = ""
	_show_title_tank()


func pause_game(reason := "manual") -> void:
	if mode != "playing":
		return
	pause_reason = reason
	mode = "paused"
	AudioService.set_game_state(mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	notify("行动已暂停", 1.2)


func resume_game() -> void:
	if mode != "paused":
		return
	mode = "playing"
	AudioService.set_game_state(mode)
	sync_pointer_mode()


func open_settings() -> void:
	if mode == "settings":
		return
	if mode == "playing":
		pause_game("settings")
	_settings_return_mode = mode
	mode = "settings"
	AudioService.set_game_state(mode)


func _close_settings() -> void:
	mode = _settings_return_mode
	AudioService.set_game_state(mode)


func _settle_abandoned_run() -> void:
	if not current_run_id.is_empty():
		SaveService.settle_run(current_run_id, false, score, mission_index)


func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	_settle_abandoned_run()
	SaveService.save_now()
	SettingsService.save_settings()
	mode = "paused"
	set_process(false)
	AudioService.set_game_state(mode)
	AudioService.shutdown()
	await get_tree().create_timer(0.22).timeout
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func is_combat_running() -> bool:
	return mode == "playing"


func _process(delta: float) -> void:
	AudioService.set_game_state(mode)
	if mode in ["won", "lost"]:
		result_delay = maxf(0.0, result_delay - delta)
	sync_pointer_mode()
	notice_time = maxf(0.0, notice_time - delta)
	if notice_time <= 0.0:
		notice = ""
	if mode == "playing":
		play_time += delta
		_update_mouse_aim()
		_update_encounters(delta)
		_update_contact_reports(delta)
	_update_cleanup(delta)
	if is_instance_valid(ui) and ui.has_method("update_snapshot"):
		ui.call("update_snapshot", get_ui_snapshot())


func sync_pointer_mode() -> void:
	var desired := Input.MOUSE_MODE_VISIBLE
	if mode == "playing":
		desired = Input.MOUSE_MODE_CAPTURED if is_instance_valid(player) and player.is_third_person() else Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != desired:
		Input.mouse_mode = desired


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("music_next"):
		_cycle_music()
		get_viewport().set_input_as_handled()
		return
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
			_close_settings()
		get_viewport().set_input_as_handled()


func _update_mouse_aim() -> void:
	if not is_instance_valid(player) or player.destroyed or not is_instance_valid(player.camera):
		return
	if player.is_controller_aiming() and not player.is_third_person():
		return
	var mouse := get_viewport().get_visible_rect().size * 0.5 if player.is_third_person() else get_viewport().get_mouse_position()
	var origin := player.camera.project_ray_origin(mouse)
	var ray := player.camera.project_ray_normal(mouse)
	var muzzle := player.get_node_or_null("ArmoredModel/TurretPivot/GunRecoil/Muzzle") as Node3D
	var aim_height := muzzle.global_position.y if muzzle != null else player.global_position.y + 1.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * player.camera.far, 1 | 4, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		if hit.get("collider") is TankActor:
			var target: TankActor = hit.collider
			player.aim_point = target._turret.global_position + Vector3.UP * 0.1
		elif not player.is_third_person() and float(hit.position.y) < 0.5 and player.get_weapon_snapshot().id != "he":
			var level_target: Variant = Plane(Vector3.UP, aim_height).intersects_ray(origin, ray)
			player.aim_point = level_target if level_target is Vector3 else hit.position
		else:
			player.aim_point = hit.position
		return
	if player.is_third_person():
		player.aim_point = origin + ray * 160.0
		return
	var intersection: Variant = Plane(Vector3.UP, aim_height).intersects_ray(origin, ray)
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
	if not is_instance_valid(source) or not source.is_player or source.team != TankActor.TEAM_PLAYER:
		return
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


func radial_damage(at: Vector3, radius: float, damage: float, attacker_team: int, contact_positions: Dictionary = {}) -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		if not is_combat_running():
			break
		if not node is TankActor:
			continue
		var tank := node as TankActor
		if tank.team == attacker_team or not tank.is_targetable():
			continue
		# A swept mine may trigger between physics frames, after the tank has
		# already moved beyond the blast. Resolve that target at its contact point.
		var target_position: Vector3 = contact_positions.get(tank.get_instance_id(), tank.global_position)
		var distance := at.distance_to(target_position)
		if distance <= radius and has_line_of_sight(at + Vector3.UP * 0.2, target_position + Vector3.UP):
			var falloff := lerpf(0.35, 1.0, 1.0 - distance / maxf(radius, 0.01))
			tank.receive_damage(damage * falloff, attacker_team, target_position)


func spawn_explosion(at: Vector3, scale_factor := 1.0) -> void:
	var effect := ExplosionScript.create(at, scale_factor, true)
	add_child(effect)
	if mode == "playing" and is_instance_valid(player) and not player.destroyed:
		var distance := player.global_position.distance_to(at)
		var shake := clampf(1.0 - distance / 48.0, 0.0, 1.0) * scale_factor * 0.72
		player.add_camera_shake(shake)


func spawn_tank_wreck(source: TankActor) -> void:
	var wreck := WreckScript.create_from_tank(source)
	add_child(wreck)


func spawn_impact(at: Vector3, heavy: bool, surface_kind := "ground", normal := Vector3.UP, weapon_kind := "cannon") -> void:
	add_child(ExplosionScript.create_impact(at, heavy, surface_kind, normal, weapon_kind))


func spawn_muzzle_flash(at: Vector3, _color: Color, scale_factor: float, forward := Vector3.FORWARD, weapon_kind := "cannon", player_priority := false) -> void:
	add_child(ExplosionScript.create_muzzle(at, forward, scale_factor, weapon_kind, player_priority))


func spawn_emp_visual(at: Vector3, scale_factor := 1.0) -> void:
	var root := Node3D.new()
	root.add_to_group("combat_effects")
	root.position = at + Vector3.UP * 0.18
	add_child(root)
	for offset in [0.0, 0.13, 0.26]:
		var surface := ArtFactory.material(Color(0.18, 0.8, 1.0, 0.42), 0.0, 0.8, 1.2)
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var ring := ArtFactory.add_torus(root, "EMPWave", Vector3.UP * offset * 0.2, 0.4, 0.045, surface)
		ring.scale.y = 0.35
		var torus := ring.mesh as TorusMesh
		torus.rings = 64
		torus.ring_segments = 8
		var tween := ring.create_tween()
		tween.tween_interval(offset)
		# Keep the expanding pulse thin enough to see the battlefield through it.
		tween.tween_method(func(radius: float) -> void:
			torus.inner_radius = maxf(0.01, radius - 0.045)
			torus.outer_radius = radius + 0.045
		, 0.4, maxf(0.4, 18.0 * scale_factor), 0.65)
		tween.parallel().tween_property(surface, "albedo_color:a", 0.0, 0.65)
		tween.tween_callback(ring.queue_free)
	get_tree().create_timer(1.2).timeout.connect(root.queue_free)


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_tank_destroyed(tank: TankActor, attacker_team: int) -> void:
	# Destruction signals from an impact already in progress must not replace
	# a terminal result or mutate the score after the save has been settled.
	if mode != "playing":
		return
	if tank.is_player:
		mode = "lost"
		AudioService.set_game_state(mode)
		result_delay = 2.4
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		objective = "主战坦克失去战斗能力"
		SaveService.settle_run(current_run_id, false, score, mission_index)
		AudioService.play_ui("defeat", -3.0)
		AudioService.radio("mission_failed")
		return
	if attacker_team == TankActor.TEAM_PLAYER:
		AudioService.radio("enemy_destroyed")
		total_run_kills += 1
		score += 900 if tank.is_boss else (180 if tank.archetype == "heavy" else 120)
		SaveService.credit_run_kills(current_run_id, total_run_kills)
	if tank.is_boss:
		mode = "won"
		AudioService.set_game_state(mode)
		result_delay = 2.4
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		objective = "%s已摧毁 · %s行动完成" % [mission_data.get("boss_name", "指挥车"), mission_data.get("name", "当前")]
		score += 2500
		SaveService.settle_run(current_run_id, true, score, mission_index)
		AudioService.play_ui("victory", -2.0)
		AudioService.radio("mission_complete")
		notify("行动成功 · 下一关已解锁" if mission_index < MissionCatalog.count() - 1 else "战役完成 · 尘湾防线已肃清", 5.0)
		return
	if not tank.counts_for_objective:
		return
	mission_kills += 1
	_update_encounter_objective()
	if mission_data.get("objective_type", "clear") == "clear" and mission_kills >= target_kills and is_instance_valid(boss) and not boss.active:
		objective_complete = true
		_activate_boss()


func _activate_boss() -> void:
	arena.set_boss_gate_open(true)
	_encounter_pause = 0.0
	# Chapter transition is a visible, one-time resupply, never regeneration
	# during a firefight. A battered player can still attempt the boss fight.
	if is_instance_valid(player) and not player.destroyed:
		player.hp = maxf(player.hp, player.max_hp * 0.75)
		player.emp_cooldown = 0.0
		player.resupply()
	boss.activate_boss()
	AudioService.radio("boss_incoming")
	if is_instance_valid(_objective_marker):
		_objective_marker.global_position = mission_data.boss_position
		for child: Node in _objective_marker.get_children():
			if child is Label3D:
				child.text = "首领阵地 · " + boss.display_name
	objective = "最终目标 · 摧毁%s" % boss.display_name
	notify("前线补给：装甲恢复至至少 75%，EMP 就绪\n首领出动 · 离开红色射线，或靠近后用 EMP 打断", 5.0)


func _on_boss_phase_changed(phase: int) -> void:
	if mode != "playing" or not is_instance_valid(boss) or boss.hp <= 0.0:
		return
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.destroyed and not enemy.is_boss and not enemy.counts_for_objective:
			notify("%s 阶段 %d / 3 · 注意火箭预警" % [boss.display_name, phase], 3.0)
			return
	notify("%s 阶段 %d / 3 · 一辆护卫进入战场" % [boss.display_name, phase], 3.0)
	var offset := _find_guard_deployment()
	var guard := _spawn_tank("BossGuard_%d" % phase, offset, TankActor.TEAM_ENEMY, false, false, "scout" if phase == 2 else "line")
	guard.counts_for_objective = false
	guard.reload = guard.fire_interval
	enemies.append(guard)


func _find_guard_deployment() -> Vector3:
	var chosen: Vector3 = mission_data.boss_position + Vector3(0, 0, 30)
	var nearest := INF
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.6, 1.8, 6.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 2 | 4
	for at: Vector3 in arena.get_spawn_candidates():
		var distance := at.distance_to(boss.global_position)
		if distance < 17.0 or distance >= nearest or at.distance_to(player.global_position) < 20.0:
			continue
		query.transform.origin = at + Vector3.UP * 1.4
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		chosen = at
		nearest = distance
	return chosen


func can_enemy_engage(tank: TankActor) -> bool:
	return tank.active and not tank.destroyed


func alert_enemy(tank: TankActor) -> void:
	tank.set_meta("alerted", true)


func _update_encounter_objective() -> void:
	if is_instance_valid(boss) and boss.active:
		objective = "%s · 摧毁%s" % [mission_data.get("name", "最终目标"), boss.display_name]
		return
	var prefix := "%02d · %s" % [mission_index + 1, mission_data.get("name", "灰中点火")]
	match str(mission_data.get("objective_type", "clear")):
		"capture":
			objective = "%s · 占领通信站 %d%%" % [prefix, roundi(objective_progress / maxf(1.0, float(mission_data.get("objective_seconds", 12.0))) * 100.0)]
		"demolition":
			objective = "%s · 炮击敌军燃料库" % prefix
		_:
			objective = "%s · 肃清巡逻部队 %d/%d" % [prefix, mini(mission_kills, target_kills), target_kills]


func _update_encounters(delta: float) -> void:
	if not is_instance_valid(player) or player.destroyed:
		return
	_update_supplies()
	if not is_instance_valid(boss) or boss.active:
		return
	var kind := str(mission_data.get("objective_type", "clear"))
	if kind == "capture":
		var at: Vector3 = mission_data.objective_position
		var nearby := Vector2(player.position.x - at.x, player.position.z - at.z).length() <= float(mission_data.get("objective_radius", 10.0))
		var contested := false
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.destroyed and enemy.active and enemy.global_position.distance_to(at) < 22.0:
				contested = true
		if nearby and not contested:
			objective_progress = minf(float(mission_data.get("objective_seconds", 12.0)), objective_progress + delta)
		objective_complete = objective_progress >= float(mission_data.get("objective_seconds", 12.0))
		_update_encounter_objective()
		if nearby and contested:
			objective += " · 清除争夺敌军"
	elif kind == "demolition":
		objective_complete = is_instance_valid(mission_target) and mission_target.destroyed
	else:
		objective_complete = mission_kills >= target_kills
	if objective_complete:
		_activate_boss()


func notify(text: String, duration := 2.0) -> void:
	notice = text
	notice_time = duration


func schedule_cleanup(node: Node, delay: float) -> void:
	node.add_to_group("combat_effects")
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
	var snapshot := {
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
		"weapon": str(player.get_weapon_snapshot().get("name", "120mm 滑膛炮")) if player_valid else "120mm 滑膛炮",
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
		"weather_mode": SettingsService.weather_mode,
		"weather_label": WeatherCatalog.mode_label(SettingsService.weather_mode, current_weather),
		"current_weather": current_weather,
		"master_volume": SettingsService.master_volume,
		"effects_volume": SettingsService.effects_volume,
		"music_volume": SettingsService.music_volume,
		"radio_volume": SettingsService.radio_volume,
		"music": AudioService.get_music_snapshot(),
		"radio_caption": AudioService.get_radio_caption(),
		"result_delay": result_delay,
		"pause_reason": pause_reason,
	}
	snapshot["mission_index"] = mission_index
	snapshot["selected_mission"] = selected_mission
	snapshot["mission_name"] = MissionCatalog.get_mission(selected_mission).name
	snapshot["mission_briefing"] = MissionCatalog.get_mission(selected_mission).briefing
	snapshot["mission_count"] = MissionCatalog.count()
	snapshot["mission_type"] = mission_data.get("objective_type", "clear")
	snapshot["objective_fraction"] = objective_progress / maxf(1.0, float(mission_data.get("objective_seconds", 12.0)))
	if snapshot["mission_type"] == "demolition" and is_instance_valid(mission_target):
		snapshot["objective_fraction"] = 1.0 - mission_target.hp / 320.0
	snapshot["unlocked_missions"] = unlocked_mission_count()
	snapshot["has_next_mission"] = mode == "won" and mission_index < MissionCatalog.count() - 1
	snapshot["selected_chassis"] = selected_chassis
	snapshot["vehicle"] = VehicleCatalog.player_options()[selected_chassis].name
	snapshot["vehicle_description"] = VehicleCatalog.player_options()[selected_chassis].description
	snapshot["camera_mode"] = "第三人称" if player_valid and player.is_third_person() else "俯视"
	snapshot["weapon_state"] = player.get_weapon_snapshot() if player_valid else {}
	snapshot["world_bounds"] = Rect2(-144, -192, 288, 384)
	var destination: Vector3 = boss.global_position if boss_valid else mission_data.get("objective_position", Vector3.ZERO)
	snapshot["objective_world"] = Vector2(destination.x, destination.z)
	snapshot["objective_distance"] = player.global_position.distance_to(destination) if player_valid else 0.0
	snapshot["supply_positions"] = []
	for supply: Dictionary in _supply_points:
		if not supply.used:
			snapshot["supply_positions"].append(Vector2(supply.position.x, supply.position.z))
	snapshot.merge(preload("res://scripts/battle_telemetry.gd").collect(self))
	var gamepad := get_node_or_null("GamepadInput")
	if is_instance_valid(gamepad):
		snapshot.merge(gamepad.get_snapshot())
	return snapshot


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
			SettingsService.master_volume = _next_volume(SettingsService.master_volume)
			SettingsService.apply()
		"effects_volume":
			SettingsService.effects_volume = _next_volume(SettingsService.effects_volume)
			SettingsService.apply()
		"music_volume":
			SettingsService.music_volume = _next_volume(SettingsService.music_volume)
			SettingsService.apply()
		"radio_volume":
			SettingsService.radio_volume = _next_volume(SettingsService.radio_volume)
			SettingsService.apply()
		"music_track":
			_cycle_music()
		"weather_mode":
			SettingsService.weather_mode = (SettingsService.weather_mode + 1) % WeatherCatalog.MODE_COUNT
			_apply_weather_setting()
			SettingsService.apply()
	AudioService.play_ui("click")


func _next_volume(current: int) -> int:
	return 0 if current >= 100 else mini(100, current + 10)


func _on_focus_lost() -> void:
	if mode == "playing":
		pause_game("focus_lost")


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var gamepad := get_node_or_null("GamepadInput")
	var disconnected_active := bool(gamepad.connection_changed(device, connected)) if is_instance_valid(gamepad) else false
	if disconnected_active and mode == "playing":
		pause_game("controller_disconnected")


func _clear_combat_nodes() -> void:
	if is_instance_valid(_title_rig):
		_title_rig.free()
	_title_rig = null
	for group in ["tanks", "mines", "projectiles", "combat_effects"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node):
				node.free()
	if is_instance_valid(mission_target):
		mission_target.free()
	mission_target = null
	_objective_marker = null
	_supply_points.clear()
	enemies.clear()
	_cleanup.clear()
	notice = ""
	notice_time = 0.0
	boss = null
	player = null


func _setup_inputs() -> void:
	var keyboard := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"fire": [], "dash": [KEY_SPACE], "emp": [KEY_E], "place_mine": [KEY_M],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4], "weapon_next": [KEY_R],
		"camera": [KEY_C], "pause": [KEY_ESCAPE], "confirm": [KEY_ENTER],
		"music_next": [KEY_N],
		"precision_aim": [], "zoom_in": [], "zoom_out": [],
		"menu_up": [KEY_UP, KEY_W], "menu_down": [KEY_DOWN, KEY_S],
	}
	for action: String in keyboard:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode: int in keyboard[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			if not InputMap.action_has_event(action, key):
				InputMap.action_add_event(action, key)
	for action in ["aim_left", "aim_right", "aim_up", "aim_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.20)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("fire", mouse):
		InputMap.action_add_event("fire", mouse)
	_add_joy_button("dash", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("emp", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("place_mine", JOY_BUTTON_RIGHT_STICK)
	_add_joy_button("camera", JOY_BUTTON_Y)
	_add_joy_button("weapon_next", JOY_BUTTON_X)
	_add_joy_button("pause", JOY_BUTTON_START)
	_add_joy_button("confirm", JOY_BUTTON_A)
	# The UI provides radial deadzone + repeat for menu sticks. Removing the
	# built-in axis bindings avoids moving focus twice for one physical nudge.
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		for existing: InputEvent in InputMap.action_get_events(action):
			if existing is InputEventJoypadMotion:
				InputMap.action_erase_event(action, existing)
	_add_joy_button("ui_accept", JOY_BUTTON_A)
	_add_joy_button("ui_cancel", JOY_BUTTON_B)
	_add_joy_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("zoom_in", JOY_BUTTON_DPAD_UP)
	_add_joy_button("zoom_out", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("music_next", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("weapon_next", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_axis("precision_aim", JOY_AXIS_TRIGGER_LEFT, 1.0)


func _add_joy_button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _finish_smoke_test() -> void:
	var okay := is_instance_valid(player) and enemies.size() == target_kills + 1 and is_instance_valid(ui) and mode == "playing"
	print("IRON_EMBERS_SMOKE_PASS" if okay else "IRON_EMBERS_SMOKE_FAIL")
	mode = "paused"
	set_process(false)
	AudioService.set_game_state(mode)
	AudioService.shutdown()
	await get_tree().create_timer(0.24).timeout
	get_tree().quit(0 if okay else 1)

func unlocked_mission_count() -> int:
	var completed: Array = SaveService.profile.get("completed_missions", [])
	var count := 1
	while count < MissionCatalog.count() and count - 1 in completed:
		count += 1
	return count

func cycle_mission() -> void:
	if mode != "title":
		return
	selected_mission = (selected_mission + 1) % unlocked_mission_count()
	mission_data = MissionCatalog.get_mission(selected_mission)
	_show_title_tank()
	AudioService.play_ui("click")

func cycle_chassis() -> void:
	if mode != "title":
		return
	selected_chassis = (selected_chassis + 1) % VehicleCatalog.player_options().size()
	SaveService.profile["selected_chassis"] = selected_chassis
	SaveService.save_now()
	_show_title_tank()
	AudioService.play_ui("click")

func next_mission() -> void:
	if mode != "won" or mission_index >= MissionCatalog.count() - 1:
		return
	selected_mission = mission_index + 1
	start_game()

func _create_mission_props() -> void:
	var at: Vector3 = mission_data.get("objective_position", Vector3.ZERO)
	_objective_marker = _make_beacon(at, Color("e9bf70"), "任务目标", float(mission_data.get("objective_radius", 9.0)))
	if mission_data.get("objective_type") == "demolition":
		mission_target = MissionTarget.new()
		mission_target.game = self
		mission_target.position = at
		add_child(mission_target)
	for point: Vector3 in mission_data.get("supply_positions", [Vector3(12, 0.05, 110), Vector3(-12, 0.05, -65)]):
		var marker := _make_beacon(point, Color("73ddb1"), "整备点 · 驶入补给", 6.0)
		_supply_points.append({"position": point, "node": marker, "used": false})

func _make_beacon(at: Vector3, color: Color, text: String, radius: float) -> Node3D:
	var marker := Node3D.new()
	marker.add_to_group("combat_effects")
	marker.position = at
	add_child(marker)
	var surface := ArtFactory.material(color, 0.0, 0.7, 0.65)
	ArtFactory.add_torus(marker, "ZoneRing", Vector3.UP * 0.07, radius, 0.07, surface)
	var label := Label3D.new()
	label.text = text
	label.position.y = 4.0
	label.font_size = 40
	label.pixel_size = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	marker.add_child(label)
	return marker

func _update_supplies() -> void:
	for supply: Dictionary in _supply_points:
		if supply.used or player.global_position.distance_to(supply.position) > 6.0:
			continue
		# A supply point is consumed only when something can actually be restored.
		if player.hp >= player.max_hp and player.mine_ammo >= 6 and not player.needs_resupply():
			continue
		supply.used = true
		player.hp = minf(player.max_hp, player.hp + 85.0)
		player.resupply()
		supply.node.queue_free()
		AudioService.radio("resupply")
		notify("整备补给 · 装甲 +85 · 弹药/地雷补满", 3.0)


func _cycle_music() -> void:
	var track := AudioService.cycle_music()
	SettingsService.music_track = int(track.get("index", 0))
	SettingsService.save_settings()
	notify("战斗音乐 · " + str(track.get("name", "")), 2.0)


func _update_contact_reports(delta: float) -> void:
	_contact_scan -= delta
	if _contact_scan > 0.0 or not is_instance_valid(player) or player.destroyed:
		return
	_contact_scan = 0.5
	for enemy: TankActor in enemies:
		if not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		var distance := player.global_position.distance_to(enemy.global_position)
		if distance > 70.0 or not has_line_of_sight(player.global_position + Vector3.UP * 2, enemy.global_position + Vector3.UP * 1.5):
			continue
		if distance < 24.0:
			AudioService.radio("enemy_near")
		if not _reported_contacts.has(enemy.get_instance_id()):
			_reported_contacts[enemy.get_instance_id()] = true
			AudioService.radio("enemy_spotted")
	var weapon := player.get_weapon_snapshot()
	if int(weapon.get("ammo", -1)) == 0:
		AudioService.radio("ammo_low")
