class_name TankActor
extends CharacterBody3D
## Native tank pawn shared by player, regular enemies and the chapter boss.

signal tank_destroyed(tank: TankActor, attacker_team: int)
signal boss_phase_changed(phase: int)

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1
const TrackedDriveScript = preload("res://scripts/tracked_drive.gd")
const CombatLoadoutScript = preload("res://data/combat_loadout.gd")
const VehicleCatalogScript = preload("res://data/vehicle_catalog.gd")
const MODEL_SCENES := {
	"challenger2": preload("res://assets/models/realistic/challenger2/challenger2.glb"),
	"kf51": preload("res://assets/models/realistic/kf51/kf51_panther.glb"),
	"kv2": preload("res://assets/models/realistic/kv2/kv2_boss.glb"),
}
const MODEL_PRESENTATION := {
	# Source assets are authored at real-world scale. Collision envelopes below
	# follow their scaled hull footprints and exclude guns and thin antennas.
	"challenger2": {"scale": 0.68, "iff_y": 0.58, "iff_z": 0.82},
	"kf51": {"scale": 0.70, "iff_y": 0.52, "iff_z": 0.88},
	"kv2": {"scale": 0.90, "iff_y": 1.12, "iff_z": 0.44},
}
const MODEL_COLLISION_SIZES := {
	"challenger2": Vector3(2.65, 2.28, 5.69),
	"kf51": Vector3(2.64, 2.28, 5.65),
	"kv2": Vector3(2.94, 2.90, 6.02),
}

var game: Node
var team := TEAM_PLAYER
var is_player := false
var is_boss := false
var archetype := "line"
var display_name := "主战坦克"
var max_hp := 240.0
var hp := 240.0
var armor := 0.08
var move_speed := 8.0
var acceleration := 10.0
var turn_speed := 1.05
var turret_turn_speed := 1.35
var projectile_speed := 260.0
var projectile_damage := 62.0
var fire_interval := 2.9
var aim_acquire_time := 1.25
var mine_ammo := 6
var mine_cooldown := 0.0
var emp_cooldown := 0.0
var dash_cooldown := 0.0
var reload := 0.0
var stunned := 0.0
var invulnerable := 0.0
var destroyed := false
var active := true
var counts_for_objective := true
var boss_phase := 1
var boss_warning := false
var aim_point := Vector3.FORWARD * -20.0
var ai_state := "spawn"
var patrol_route: Array[Vector3] = []
var sight_range := 48.0
var sight_angle := 105.0
var search_duration := 9.0
var _loadout: RefCounted
var _patrol_index := 0
var _patrol_pause := 0.0
var _has_contact := false
var _last_seen_position := Vector3.ZERO
var _search_remaining := 0.0
var _search_scan := 0.0
var _enemy_weapon_kind := "cannon"
var _enemy_burst_remaining := 6
var _enemy_rocket_ammo := 8
var _ideal_distance := 30.0

var _model: Node3D
var _turret: Node3D
var _barrel: Node3D
var _muzzle: Node3D
var _machine_muzzle: Marker3D
var _rocket_muzzles: Array[Marker3D] = []
var _drive: RefCounted
var _camera_pivot: Node3D
var _camera_arm: SpringArm3D
var camera: Camera3D
var _engine_audio: AudioStreamPlayer3D
var _vehicle_audio: Node3D
var _repair_reserve := 120.0
var _repair_clock := 0.0
var _ai_clock := 0.0
var _salvo_clock := 5.0
var _ai_mine_clock := 10.0
var _charge_clock := 0.0
var _salvo_recovery := 0.0
var _aim_hold_time := 0.0
var _observation_clock := 0.0
var _observed_target_position := Vector3.ZERO
var _observed_target_velocity := Vector3.ZERO
var _dash_remaining := 0.0
var _salvo_aim_point := Vector3.ZERO
var _salvo_target_locked := false
var _salvo_shot_count := 3
var _salvo_telegraph: MeshInstance3D
var _strafe_sign := 1.0
var _rng := RandomNumberGenerator.new()
var _base_barrel_z := 0.0
var _base_barrel_pitch := 0.0
var _barrel_pitch := 0.0
var _recoil := 0.0
var _recoil_peak := 0.0
var _recoil_time := 1.0
var _base_barrel_position := Vector3.ZERO
var _hull_body: Node3D
var _hull_base_rotation := Vector3.ZERO
var _hull_recoil_axis := Vector3.RIGHT
var _last_move := Vector3.FORWARD
var _camera_shake := 0.0
var _camera_base_position := Vector3.ZERO
var _controller_aim_active := false
var _controller_aim_direction := Vector3.FORWARD


func _ready() -> void:
	add_to_group("tanks")
	_rng.seed = hash(name) + (701 if is_boss else 31)
	_build_collision()
	_apply_role_stats()
	if is_player:
		_loadout = CombatLoadoutScript.new()
	_build_model()
	if is_player:
		_build_camera()
	_vehicle_audio = AudioService.attach_vehicle(self)


func _build_collision() -> void:
	collision_layer = 2 if team == TEAM_PLAYER else 4
	collision_mask = 1 | 2 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	var collider := CollisionShape3D.new()
	collider.name = "HullCollision"
	var shape := BoxShape3D.new()
	shape.size = MODEL_COLLISION_SIZES[_model_key()]
	collider.shape = shape
	collider.position.y = shape.size.y * 0.5 + 0.015
	add_child(collider)


func _apply_role_stats() -> void:
	if is_player:
		var vehicle: Dictionary = VehicleCatalogScript.player_vehicle(archetype)
		display_name = vehicle.name
		max_hp = vehicle.hp
		hp = max_hp
		armor = vehicle.armor
		move_speed = vehicle.speed
		acceleration = vehicle.acceleration
		turn_speed = vehicle.turn_speed
		turret_turn_speed = vehicle.turret_speed
		projectile_damage = vehicle.damage
		fire_interval = vehicle.interval
		return
	acceleration = 6.5
	turn_speed = 0.75
	turret_turn_speed = 0.85
	if is_boss:
		display_name = "铁牙 · 围城指挥车"
		max_hp = 780.0
		hp = max_hp
		armor = 0.18
		move_speed = 4.3
		acceleration = 4.5
		turn_speed = 0.52
		turret_turn_speed = 0.65
		projectile_damage = 32.0
		fire_interval = 5.4
		aim_acquire_time = 1.5
		projectile_speed = 220.0
		sight_range = 68.0
		sight_angle = 130.0
		_ideal_distance = 32.0
		active = false
		counts_for_objective = false
		return
	var role: Dictionary = VehicleCatalogScript.enemy_role(archetype)
	display_name = role.name
	max_hp = role.hp
	armor = role.armor
	move_speed = role.speed
	fire_interval = role.interval
	projectile_damage = role.damage
	aim_acquire_time = role.acquire
	sight_range = role.vision
	sight_angle = role.fov
	_ideal_distance = role.ideal
	_enemy_weapon_kind = role.weapon
	projectile_speed = 185.0 if role.weapon == "he" else (500.0 if role.weapon == "machine_gun" else (95.0 if role.weapon == "rocket" else 210.0))
	if archetype == "heavy":
		acceleration = 4.8
		turn_speed = 0.58
		turret_turn_speed = 0.72
	elif archetype == "sniper":
		projectile_speed = 280.0
	if archetype == "minelayer":
		mine_ammo = 12
	hp = max_hp
	_ai_clock = _rng.randf_range(0.3, 1.2)
	_ai_mine_clock = _rng.randf_range(10.0, 15.0)
	reload = _rng.randf_range(1.8, 3.2)
	_strafe_sign = -1.0 if _rng.randi() % 2 == 0 else 1.0


func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "ArmoredModel"
	add_child(_model)
	var model_key := _model_key()
	var presentation: Dictionary = MODEL_PRESENTATION[model_key]
	_model.scale = Vector3.ONE * float(presentation["scale"])
	var scene_resource: PackedScene = MODEL_SCENES.get(model_key) as PackedScene
	assert(scene_resource != null, "Missing armored vehicle model: %s" % model_key)
	var imported := scene_resource.instantiate() as Node3D
	assert(imported != null, "Armored vehicle model is not a Node3D: %s" % model_key)
	_model.add_child(imported)
	var tank_root := imported.get_node_or_null("TankRoot") as Node3D
	if tank_root == null and imported.name == "TankRoot":
		tank_root = imported
	assert(tank_root != null, "Model lacks its TankRoot contract node: %s" % model_key)
	var body := tank_root.get_node_or_null("Body") as Node3D
	_turret = tank_root.get_node_or_null("Turret") as Node3D
	_barrel = _turret.get_node_or_null("Gun") as Node3D if _turret != null else null
	_muzzle = _barrel.get_node_or_null("Muzzle") as Node3D if _barrel != null else null
	assert(
		body != null and _turret != null and _barrel != null and _muzzle != null,
		"Model does not satisfy TankRoot/{Body,Turret/Gun/Muzzle}: %s" % model_key
	)

	# Flatten the authored wrapper while preserving the stable gameplay paths used
	# by projectiles, tests and Boss rocket launchers.
	body.reparent(_model, true)
	body.name = "Hull"
	_hull_body = body
	_hull_base_rotation = body.rotation
	body.set_meta("source_model", model_key)
	_turret.reparent(_model, true)
	_turret.name = "TurretPivot"
	_barrel.name = "GunRecoil"
	_base_barrel_z = _barrel.position.z
	_base_barrel_position = _barrel.position
	_base_barrel_pitch = _barrel.rotation.x
	if imported != body and imported != _turret:
		imported.free()
	_drive = TrackedDriveScript.new()
	_drive.setup(_model, model_key)
	_add_team_iff(model_key)
	if is_player or is_boss or archetype == "rocket":
		_add_boss_rocket_pods()
	if is_player or archetype in ["gunner", "assault"]:
		_add_machine_gun()
	_add_specialist_equipment()


func _model_key() -> String:
	if is_boss:
		return "kv2"
	if is_player:
		return str(VehicleCatalogScript.player_vehicle(archetype).model)
	return str(VehicleCatalogScript.enemy_role(archetype).model)


func _add_specialist_equipment() -> void:
	if is_player or is_boss:
		return
	var steel := ArtFactory.material(Color("39433c"), 0.7, 0.6)
	var warning := ArtFactory.material(Color("d6ac52"), 0.35, 0.6)
	if archetype == "minelayer":
		for side in [-1.0, 1.0]:
			ArtFactory.add_box(_model, "MineRack", Vector3(side * 1.2, 1.5, 2.0), Vector3(0.7, 0.16, 1.5), steel)
			for offset in [-0.5, 0.0, 0.5]:
				ArtFactory.add_cylinder(_model, "ReserveMine", Vector3(side * 1.2, 1.7, 2.0 + offset), 0.23, 0.14, warning, 16)
	elif archetype == "repair":
		ArtFactory.add_box(_model, "RecoveryToolChest", Vector3(0.0, 1.4, 2.3), Vector3(2.0, 0.6, 0.65), steel)
		var boom := ArtFactory.add_box(_turret, "RecoveryCrane", Vector3(-0.8, 1.7, 0.1), Vector3(0.22, 0.28, 2.1), warning)
		boom.rotation.x = -0.24
		ArtFactory.add_box(_turret, "RecoveryHoist", Vector3(-0.8, 1.1, -0.85), Vector3(0.10, 1.2, 0.10), steel)
	elif archetype == "destroyer":
		for side in [-1.0, 1.0]:
			var plate := ArtFactory.add_box(_turret, "SpacedArmor", Vector3(side * 1.08, 0.6, -0.8), Vector3(0.26, 0.75, 1.45), steel)
			plate.rotation.z = side * -0.12
	elif archetype == "artillery":
		ArtFactory.add_box(_model, "ArtilleryRangefinder", Vector3(0.0, 3.05, 0.0), Vector3(1.2, 0.24, 0.25), steel)
	elif archetype == "assault" and is_instance_valid(_machine_muzzle):
		var tube := ArtFactory.add_cylinder(_machine_muzzle.get_parent(), "CoaxialAutocannon", Vector3(-0.22, 0.16, -0.65), 0.085, 1.25, steel, 16)
		tube.rotation.x = PI * 0.5


func _repair_allies(delta: float) -> void:
	_repair_clock = maxf(0.0, _repair_clock - delta)
	if _repair_reserve <= 0.0 or _repair_clock > 0.0:
		return
	_repair_clock = 1.0
	for ally: Node in get_tree().get_nodes_in_group("tanks"):
		if ally == self or not ally is TankActor or ally.team != team or ally.destroyed or ally.is_boss or not ally.active:
			continue
		if ally.hp >= ally.max_hp or global_position.distance_to(ally.global_position) > 18.0:
			continue
		if not game.has_line_of_sight(global_position + Vector3.UP * 2, ally.global_position + Vector3.UP * 2):
			continue
		var restored := minf(5.0, minf(ally.max_hp - ally.hp, _repair_reserve))
		ally.hp += restored
		_repair_reserve -= restored
		# Limited repair stores and one target per second prevent an immortal pack.
		return


func _add_machine_gun() -> void:
	var steel := ArtFactory.material(Color("202824"), 0.8, 0.36)
	var mount := ArtFactory.add_box(_turret, "MachineGunMount", Vector3(0.62, 1.32, -0.3), Vector3(0.28, 0.32, 0.45), steel)
	var tube := ArtFactory.add_cylinder(mount, "MachineGunBarrel", Vector3(0, 0.16, -0.65), 0.065, 1.25, steel, 16)
	tube.rotation.x = PI * 0.5
	_machine_muzzle = Marker3D.new()
	_machine_muzzle.name = "MachineMuzzle"
	_machine_muzzle.position = Vector3(0, 0.16, -1.3)
	mount.add_child(_machine_muzzle)


func _add_team_iff(model_key: String) -> void:
	var presentation: Dictionary = MODEL_PRESENTATION[model_key]
	var team_color := Color("54edf2") if team == TEAM_PLAYER else (Color("ffad55") if is_boss else Color("ff5347"))
	var lens := ArtFactory.material(team_color, 0.08, 0.24, 4.8 if is_boss else 3.6)
	for side in [-1.0, 1.0]:
		ArtFactory.add_box(
			_turret,
			"TeamIFFLeft" if side < 0.0 else "TeamIFFRight",
			Vector3(side * (1.08 if model_key != "kv2" else 1.24), float(presentation["iff_y"]), float(presentation["iff_z"])),
			Vector3(0.30, 0.12, 0.10),
			lens
		)


func _add_boss_rocket_pods() -> void:
	var pod_armor := ArtFactory.material(Color("282d2c"), 0.74, 0.38)
	var tube_steel := ArtFactory.material(Color("111514"), 0.86, 0.48)
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var pod := ArtFactory.add_box(
			_turret,
			"RocketPod" + side_name,
			Vector3(side * 1.72, 0.92, 0.18),
			Vector3(0.68, 0.82, 1.62),
			pod_armor
		)
		for row in [-0.19, 0.19]:
			for z in [-0.48, 0.0, 0.48]:
				var tube := ArtFactory.add_cylinder(pod, "RocketTube", Vector3(row, 0.04, z), 0.12, 0.76, tube_steel, 20)
				tube.rotation.x = PI * 0.5
		var rocket_muzzle := Marker3D.new()
		rocket_muzzle.name = "RocketMuzzle" + side_name
		rocket_muzzle.position = Vector3(0.0, 0.04, -0.90)
		pod.add_child(rocket_muzzle)
		_rocket_muzzles.append(rocket_muzzle)


func _build_camera() -> void:
	_camera_pivot = preload("res://scripts/battle_camera_rig.gd").new()
	_camera_pivot.name = "CameraRig"
	_camera_pivot.tank = self
	add_child(_camera_pivot)
	_camera_base_position = Vector3(0, 1.25, -3.0)
	_camera_arm = _camera_pivot.arm
	camera = _camera_pivot.camera


func _process(delta: float) -> void:
	if is_player and is_instance_valid(_camera_pivot):
		_update_camera_shake(delta)


func _input(event: InputEvent) -> void:
	if not is_player or game == null or not game.is_combat_running():
		return
	if event is InputEventMouseMotion:
		# Raw screen deltas avoid stretch/DPI scaling. Some backends and injected
		# events only provide relative; accept those and sub-pixel fine movement.
		var motion: Vector2 = event.screen_relative
		if motion.is_zero_approx():
			motion = event.relative
		if motion.is_zero_approx():
			return
		_controller_aim_active = false
		if is_third_person():
			var precision := Input.get_action_strength("precision_aim") if InputMap.has_action("precision_aim") else 0.0
			_camera_pivot.handle_look(motion * lerpf(1.0, 0.55, precision))
	elif event is InputEventMouseButton and event.pressed:
		_controller_aim_active = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_pivot.zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_pivot.zoom(1.0)


func is_controller_aiming() -> bool:
	return _controller_aim_active or Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down").length() > 0.01


func _physics_process(delta: float) -> void:
	if destroyed or game == null or not game.is_combat_running():
		if is_instance_valid(_engine_audio):
			_engine_audio.volume_db = -80.0
		if is_instance_valid(_vehicle_audio):
			AudioService.stop_vehicle(_vehicle_audio)
		return
	var old_yaw := rotation.y
	if is_player and _loadout != null:
		_loadout.tick(delta)
		reload = float(_loadout.snapshot().reload)
	else:
		reload = maxf(0.0, reload - delta)
	mine_cooldown = maxf(0.0, mine_cooldown - delta)
	emp_cooldown = maxf(0.0, emp_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	_dash_remaining = maxf(0.0, _dash_remaining - delta)
	stunned = maxf(0.0, stunned - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	_update_recoil(delta)
	if active and stunned <= 0.0:
		if is_player:
			_player_control(delta)
		else:
			_ai_control(delta)
	else:
		_aim_hold_time = 0.0
		_observation_clock = 0.0
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_update_turret(delta)
	_apply_gravity(delta)
	var requested_velocity := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	var wheel_interval := 0.0
	if not is_player and is_instance_valid(game.player) and global_position.distance_squared_to(game.player.global_position) > 8100.0:
		wheel_interval = 0.12
	_drive.step(get_real_velocity(), angle_difference(old_yaw, rotation.y), delta, wheel_interval)
	var impact_speed := 0.0
	for contact in get_slide_collision_count():
		var normal := get_slide_collision(contact).get_normal()
		if absf(normal.y) < 0.6:
			impact_speed = maxf(impact_speed, maxf(0.0, -requested_velocity.dot(normal)))
	if is_instance_valid(_vehicle_audio):
		if active:
			AudioService.update_vehicle(_vehicle_audio, Vector2(get_real_velocity().x, get_real_velocity().z).length(), absf(angle_difference(old_yaw, rotation.y)) / maxf(delta, 0.001), impact_speed, delta)
		else:
			AudioService.stop_vehicle(_vehicle_audio)


func _player_control(delta: float) -> void:
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var desired: Vector3 = _camera_pivot.movement(axis)
	_set_planar_velocity(desired, delta, move_speed * (1.35 if _dash_remaining > 0.0 else 1.0))
	var pad_aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if is_third_person():
		_controller_aim_active = false
		if pad_aim.length() > 0.01:
			var precision := Input.get_action_strength("precision_aim") if InputMap.has_action("precision_aim") else 0.0
			_camera_pivot.handle_look(pad_aim * delta * 820.0 * lerpf(1.0, 0.35, precision))
	elif pad_aim.length() > 0.01:
		_controller_aim_active = true
		_controller_aim_direction = Vector3(pad_aim.x, 0, pad_aim.y).normalized()
	if _controller_aim_active:
		aim_point = global_position + _controller_aim_direction * 35.0
		# A flat right-stick bearing aims at armor height. Ground targeting is
		# reserved for the HE slot rather than depressing AP into the roadway.
		if _selected_weapon_kind() != "he":
			aim_point.y = _muzzle.global_position.y
	for slot in 4:
		if Input.is_action_just_pressed("weapon_%d" % (slot + 1)):
			select_weapon(slot)
	if Input.is_action_just_pressed("weapon_next"):
		cycle_weapon()
	_update_turret(delta)
	if Input.is_action_pressed("fire"):
		try_fire()
	if Input.is_action_just_pressed("dash"):
		try_dash(desired)
	if Input.is_action_just_pressed("emp"):
		try_emp()
	if Input.is_action_just_pressed("place_mine"):
		try_place_mine()
	if Input.is_action_just_pressed("camera"):
		toggle_camera()
	if InputMap.has_action("zoom_in") and Input.is_action_just_pressed("zoom_in"):
		_camera_pivot.zoom(-1.0)
	if InputMap.has_action("zoom_out") and Input.is_action_just_pressed("zoom_out"):
		_camera_pivot.zoom(1.0)


func _ai_control(delta: float) -> void:
	if archetype == "repair":
		_repair_allies(delta)
	var target: TankActor = game.player
	if not is_instance_valid(target) or target.destroyed:
		_aim_hold_time = 0.0
		_patrol_control(delta)
		return
	var target_delta := target.global_position - global_position
	target_delta.y = 0.0
	var distance := target_delta.length()
	var visible_target := can_see_target(target)
	_observation_clock -= delta
	_salvo_clock -= delta
	_ai_mine_clock -= delta
	_ai_clock -= delta
	if visible_target:
		_has_contact = true
		_search_remaining = search_duration
		_last_seen_position = target.global_position
		if _observation_clock <= 0.0:
			_observed_target_position = target.global_position
			_observed_target_velocity = Vector3(target.velocity.x, 0.0, target.velocity.z)
			_observation_clock = _rng.randf_range(0.32, 0.5)
		aim_point = _observed_target_position + _observed_target_velocity * clampf(distance / projectile_speed, 0.0, 0.65) * 0.3
		aim_point.y += 1.1
	else:
		_aim_hold_time = 0.0
		_observation_clock = 0.0
		_search_remaining = maxf(0.0, _search_remaining - delta)
	if is_boss:
		_update_boss_attack(delta, target, distance if visible_target else INF)
		if boss_warning:
			_aim_hold_time = 0.0
			aim_point = _salvo_aim_point
			_set_planar_velocity(Vector3.ZERO, delta, move_speed)
			_update_turret(delta)
			return
		if _salvo_recovery > 0.0:
			_salvo_recovery = maxf(0.0, _salvo_recovery - delta)
			_aim_hold_time = 0.0
			ai_state = "recover"
			_set_planar_velocity(Vector3.ZERO, delta, move_speed)
			_update_turret(delta)
			return
	if not visible_target:
		if _search_remaining > 0.0:
			_search_control(delta)
		else:
			_has_contact = false
			_patrol_control(delta)
		return
	var desired := Vector3.ZERO
	if distance > _ideal_distance + 7.0:
		ai_state = "navigate"
		desired = target_delta.normalized()
	elif distance < _ideal_distance - 12.0:
		ai_state = "retreat"
		desired = -target_delta.normalized()
	else:
		ai_state = "aim" if reload < aim_acquire_time else "reload"
		if archetype == "scout" and not is_boss and reload > 2.4:
			ai_state = "reposition"
			desired = Vector3(-target_delta.z, 0, target_delta.x).normalized() * _strafe_sign * 0.45
	if _ai_clock <= 0.0:
		_ai_clock = _rng.randf_range(0.8, 1.8)
		if _rng.randf() < 0.3:
			_strafe_sign *= -1.0
	desired = _avoid_obstacles(desired)
	_set_planar_velocity(desired, delta, move_speed)
	_update_turret(delta)
	var forward := -_turret.global_basis.z.normalized()
	var aim_delta := aim_point - _turret.global_position
	aim_delta.y = 0.0
	var settled := Vector2(velocity.x, velocity.z).length() < 1.1
	var aligned := aim_delta.length_squared() > 0.05 and forward.dot(aim_delta.normalized()) > cos(deg_to_rad(5.0))
	if aligned and settled and reload <= aim_acquire_time:
		_aim_hold_time += delta
		if _aim_hold_time >= aim_acquire_time and try_fire():
			# A settled machine gun fires a six-round burst, then reacquires.
			if _enemy_weapon_kind != "machine_gun" or _enemy_burst_remaining == 6:
				_aim_hold_time = 0.0
	else:
		_aim_hold_time = 0.0
	if mine_cooldown <= 0.0 and distance > 8.0 and distance < 25.0 and _ai_mine_clock <= 0.0:
		try_place_mine()
		_ai_mine_clock = _rng.randf_range(5.0, 8.0) if archetype == "minelayer" else _rng.randf_range(12.0, 17.0)


func can_see_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.get("destroyed") == true:
		return false
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > sight_range:
		return false
	# Close crews hear tracks around them, but neither vision nor hearing can
	# reveal a tank through a wall. A known contact widens observation, not range.
	var cone := 165.0 if _has_contact else sight_angle
	var forward := -_turret.global_basis.z.normalized() if is_instance_valid(_turret) else -global_basis.z.normalized()
	if distance > 10.0 and forward.dot(offset.normalized()) < cos(deg_to_rad(cone * 0.5)):
		return false
	var eye := global_position + Vector3.UP * 2.0
	return game.has_line_of_sight(eye, target.global_position + Vector3.UP * 1.3)


func _patrol_control(delta: float) -> void:
	ai_state = "patrol"
	_aim_hold_time = 0.0
	if archetype == "minelayer" and _ai_mine_clock <= 0.0 and get_real_velocity().length() > 1.5:
		try_place_mine()
		_ai_mine_clock = _rng.randf_range(8.0, 12.0)
	if patrol_route.is_empty():
		# Standalone encounters still patrol locally; campaign spawns provide
		# authored routes through streets and clearings.
		var center := global_position
		for offset: Vector3 in [Vector3(0, 0, -14), Vector3(14, 0, -14), Vector3(14, 0, 0), Vector3.ZERO]:
			patrol_route.append(Vector3(clampf(center.x + offset.x, -137, 137), center.y, clampf(center.z + offset.z, -185, 185)))
	_patrol_index %= patrol_route.size()
	var waypoint := patrol_route[_patrol_index]
	var offset := waypoint - global_position
	offset.y = 0.0
	if offset.length() < 3.2:
		_patrol_index = (_patrol_index + 1) % patrol_route.size()
		_patrol_pause = _rng.randf_range(0.8, 1.5)
	if _patrol_pause > 0.0:
		_patrol_pause = maxf(0.0, _patrol_pause - delta)
		_search_scan += delta
		aim_point = global_position - global_basis.z.rotated(Vector3.UP, sin(_search_scan * 1.2) * 0.7) * 25.0
		_set_planar_velocity(Vector3.ZERO, delta, move_speed)
	else:
		aim_point = waypoint
		_set_planar_velocity(_avoid_obstacles(offset.normalized()), delta, move_speed * 0.58)
	_update_turret(delta)


func _search_control(delta: float) -> void:
	ai_state = "search"
	_search_scan += delta
	var offset := _last_seen_position - global_position
	offset.y = 0.0
	if offset.length() > 7.0 and _search_remaining > 2.0:
		aim_point = _last_seen_position
		_set_planar_velocity(_avoid_obstacles(offset.normalized()), delta, move_speed * 0.65)
	else:
		var heading := offset.normalized() if offset.length_squared() > 0.1 else -global_basis.z
		aim_point = global_position + heading.rotated(Vector3.UP, sin(_search_scan * 1.5) * 1.05) * 20.0
		_set_planar_velocity(Vector3.ZERO, delta, move_speed)
	_update_turret(delta)


func alert_from_hit(hit_position: Vector3) -> void:
	# Damage carries an impact position, not an omniscient attacker position.
	# Search the incoming side until an actual line-of-sight observation occurs.
	if not _has_contact:
		var incoming := hit_position - global_position
		incoming.y = 0.0
		if incoming.length_squared() < 0.1:
			incoming = -global_basis.z
		_last_seen_position = global_position + incoming.normalized() * 22.0
	_search_remaining = search_duration
	ai_state = "search"


func _update_boss_attack(delta: float, target: TankActor, distance: float) -> void:
	if _charge_clock > 0.0:
		_charge_clock -= delta
		boss_warning = true
		if _charge_clock <= 0.0:
			boss_warning = false
			_fire_boss_salvo(target)
			_clear_salvo_telegraph()
			_salvo_clock = boss_salvo_interval()
			_salvo_recovery = 3.2
			reload = maxf(reload, 3.2)
	elif _salvo_clock <= 0.0 and _salvo_recovery <= 0.0 and distance < 62.0:
		_charge_clock = boss_telegraph_duration()
		_salvo_aim_point = target.global_position + Vector3.UP
		_salvo_shot_count = boss_salvo_count()
		_salvo_target_locked = true
		boss_warning = true
		ai_state = "telegraph"
		_show_salvo_telegraph()
		AudioService.play_3d("boss_warning", global_position, -4.0, 0.88 + boss_phase * 0.08)


func _fire_boss_salvo(target: TankActor) -> void:
	# Damage can advance a Boss phase during the warning. Keep the announced
	# number of lanes for this volley; the stronger pattern begins next time.
	var shots := _salvo_shot_count if _salvo_target_locked else boss_salvo_count()
	for index in range(shots):
		var launch_marker := _rocket_muzzles[index % _rocket_muzzles.size()] if not _rocket_muzzles.is_empty() else _muzzle
		var target_point := _salvo_aim_point if _salvo_target_locked else target.global_position + Vector3.UP
		var base := (target_point - launch_marker.global_position).normalized()
		var spread := deg_to_rad((float(index) - float(shots - 1) * 0.5) * 7.0)
		var direction := base.rotated(Vector3.UP, spread)
		var launch_position := _launch_weapon(_turret.global_position, launch_marker.global_position, direction, projectile_damage * 0.55, 95.0, 4.2, "rocket")
		game.spawn_muzzle_flash(launch_position, Color("ff593d"), 0.82, direction, "rocket")
	var audio_origin := _rocket_muzzles[0].global_position if not _rocket_muzzles.is_empty() else _muzzle.global_position
	AudioService.play_3d("cannon", audio_origin, -1.0, 0.68)
	AudioService.play_3d("cannon_tail", audio_origin, -4.5, 0.82)
	_salvo_target_locked = false


func boss_salvo_count() -> int:
	return 2 + boss_phase


func boss_telegraph_duration() -> float:
	return 3.0 - float(boss_phase) * 0.2


func boss_salvo_interval() -> float:
	return 14.0 - float(boss_phase)


func _show_salvo_telegraph() -> void:
	if not is_instance_valid(_salvo_telegraph):
		_salvo_telegraph = MeshInstance3D.new()
		_salvo_telegraph.name = "SalvoDangerLanes"
		add_child(_salvo_telegraph)
		_salvo_telegraph.top_level = true
		_salvo_telegraph.global_transform = Transform3D.IDENTITY
		_salvo_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.albedo_color = Color(1.0, 0.12, 0.035, 0.42)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, surface)
	var center := global_position
	center.y = 0.06
	var direction := _salvo_aim_point - center
	direction.y = 0.0
	var reach := clampf(direction.length() + 12.0, 18.0, 75.0)
	direction = direction.normalized()
	var shots := _salvo_shot_count
	for index in shots:
		var spread := deg_to_rad((float(index) - float(shots - 1) * 0.5) * 7.0)
		var lane := direction.rotated(Vector3.UP, spread)
		var side := lane.cross(Vector3.UP) * 0.22
		var start := center + lane * 4.0
		var end := center + lane * reach
		for point: Vector3 in [start - side, start + side, end + side, start - side, end + side, end - side]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	_salvo_telegraph.mesh = mesh
	_salvo_telegraph.visible = true


func _clear_salvo_telegraph() -> void:
	_salvo_target_locked = false
	if is_instance_valid(_salvo_telegraph):
		_salvo_telegraph.visible = false


func _set_planar_velocity(input_direction: Vector3, delta: float, speed: float) -> void:
	var direction := input_direction
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if direction.length_squared() > 0.02:
		_last_move = direction.normalized()
		var wanted_yaw := atan2(-direction.x, -direction.z)
		rotation.y = rotate_toward(rotation.y, wanted_yaw, turn_speed * delta)
	# Turning a tracked hull takes time. Reduce travel until the hull faces the
	# requested world direction instead of skating sideways at cruising speed.
	var alignment := (-global_basis.z).dot(direction.normalized()) if direction.length_squared() > 0.02 else 1.0
	var steering_speed := lerpf(0.32, 1.0, clampf(alignment, 0.0, 1.0))
	var target_velocity := direction * speed * steering_speed
	var planar_velocity := Vector2(velocity.x, velocity.z).move_toward(Vector2(target_velocity.x, target_velocity.z), acceleration * delta)
	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.y


func _avoid_obstacles(desired: Vector3) -> Vector3:
	if desired.length_squared() < 0.01:
		return desired
	var from := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, from + desired.normalized() * 5.0, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	var normal: Vector3 = hit.get("normal", Vector3.RIGHT)
	var tangent := Vector3(-normal.z, 0, normal.x) * _strafe_sign
	return (desired * 0.2 + tangent).normalized()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.1


func _update_turret(delta: float) -> void:
	if not is_instance_valid(_turret):
		return
	var aim_delta := aim_point - _turret.global_position
	aim_delta.y = 0.0
	if aim_delta.length_squared() < 0.05:
		return
	var world_yaw := atan2(-aim_delta.x, -aim_delta.z)
	var local_yaw := wrapf(world_yaw - rotation.y, -PI, PI)
	_turret.rotation.y = rotate_toward(_turret.rotation.y, local_yaw, turret_turn_speed * delta)
	if not is_instance_valid(_barrel) or not is_instance_valid(_muzzle):
		return
	var kind := _selected_weapon_kind()
	var main_kind := kind if kind != "machine_gun" else "cannon"
	var pitch := _desired_weapon_pitch(_muzzle.global_position, main_kind)
	_barrel_pitch = rotate_toward(_barrel_pitch, pitch, 0.7 * delta)
	_barrel.rotation.x = _base_barrel_pitch + _barrel_pitch
	if is_instance_valid(_machine_muzzle):
		var mount := _machine_muzzle.get_parent() as Node3D
		mount.rotation.x = rotate_toward(mount.rotation.x, _desired_weapon_pitch(_machine_muzzle.global_position, "machine_gun"), 1.1 * delta)
	for socket: Marker3D in _rocket_muzzles:
		var pod := socket.get_parent() as Node3D
		var target := _salvo_aim_point if boss_warning else aim_point
		var offset := target - socket.global_position
		var launch_pitch := atan2(offset.y, maxf(0.1, Vector2(offset.x, offset.z).length()))
		pod.rotation.x = rotate_toward(pod.rotation.x, clampf(launch_pitch, deg_to_rad(-10.0), deg_to_rad(20.0)), 0.7 * delta)


func _selected_weapon_kind() -> String:
	return str(CombatLoadoutScript.WEAPONS[_loadout.selected].id) if is_player and _loadout != null else _enemy_weapon_kind


func _desired_weapon_pitch(origin: Vector3, kind: String) -> float:
	var forward := -_turret.global_basis.z.normalized()
	var speed := projectile_speed
	if kind != "cannon":
		for definition: Dictionary in CombatLoadoutScript.WEAPONS:
			if definition.id == kind:
				speed = float(definition.speed) if is_player else projectile_speed
				break
	var gravity := 0.0 if kind == "rocket" else 9.8
	var solved := IronProjectile.ballistic_direction(origin, aim_point, forward, speed, gravity)
	if kind == "rocket":
		var offset := aim_point - origin
		solved = Vector3(forward.x, offset.y / maxf(0.1, Vector2(offset.x, offset.z).length()), forward.z).normalized()
	return clampf(asin(clampf(solved.y, -1.0, 1.0)), deg_to_rad(-10.0), deg_to_rad(25.0 if kind == "he" else 20.0))


func get_firing_direction(kind := "") -> Vector3:
	var selected := _selected_weapon_kind() if kind.is_empty() else kind
	if selected == "machine_gun" and is_instance_valid(_machine_muzzle):
		return -_machine_muzzle.global_basis.z.normalized()
	if selected == "rocket" and not _rocket_muzzles.is_empty():
		return -_rocket_muzzles[0].global_basis.z.normalized()
	return -_muzzle.global_basis.z.normalized() if is_instance_valid(_muzzle) else -global_basis.z.normalized()


func _update_engine_audio() -> void:
	if not is_instance_valid(_engine_audio):
		return
	var ratio := Vector2(velocity.x, velocity.z).length() / maxf(move_speed, 0.1)
	_engine_audio.volume_db = -23.0 + ratio * 7.0
	_engine_audio.pitch_scale = 0.76 + ratio * 0.62


func select_weapon(index: int) -> void:
	if not is_player or _loadout == null:
		return
	if _loadout.select(index):
		reload = float(_loadout.snapshot().reload)


func cycle_weapon() -> void:
	if not is_player or _loadout == null:
		return
	_loadout.cycle()
	reload = float(_loadout.snapshot().reload)


func get_weapon_snapshot() -> Dictionary:
	if is_player and _loadout != null:
		return _loadout.snapshot()
	return {"id": _enemy_weapon_kind, "name": "主炮", "ammo": -1, "reload": reload, "reload_max": fire_interval, "slots": []}


func resupply() -> void:
	if _loadout != null:
		_loadout.resupply()
	mine_ammo = 6
	_enemy_rocket_ammo = 8


func needs_resupply() -> bool:
	return mine_ammo < 6 or (_loadout != null and _loadout.needs_resupply())


func try_fire() -> bool:
	if reload > 0.0 or stunned > 0.0 or destroyed or not active:
		return false
	var kind := _enemy_weapon_kind
	var damage := projectile_damage
	var speed := projectile_speed
	var splash := 2.4 if is_boss else (7.0 if kind == "he" else (5.0 if kind == "rocket" else 0.0))
	if is_player and _loadout != null:
		var weapon: Dictionary = _loadout.fire(fire_interval if _loadout.selected == 0 else -1.0)
		if weapon.is_empty():
			return false
		kind = weapon.id
		damage = projectile_damage if kind == "cannon" else float(weapon.damage)
		speed = projectile_speed if kind == "cannon" else float(weapon.speed)
		splash = float(weapon.splash)
		reload = float(_loadout.snapshot().reload)
	else:
		reload = fire_interval
		if kind == "machine_gun":
			_enemy_burst_remaining -= 1
			if _enemy_burst_remaining <= 0:
				_enemy_burst_remaining = 6
				reload = 3.0
		elif kind == "rocket":
			_enemy_rocket_ammo -= 1
			if _enemy_rocket_ammo <= 0:
				_enemy_weapon_kind = "cannon"
				projectile_speed = 210.0
				projectile_damage = 22.0
	var direction := get_firing_direction(kind)
	var speed_ratio := clampf(Vector2(velocity.x, velocity.z).length() / move_speed, 0.0, 1.0)
	if not is_player or kind == "machine_gun":
		var spread_degrees := lerpf(0.6, 3.4, speed_ratio) if not is_player else lerpf(0.25, 1.2, speed_ratio)
		direction = direction.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-spread_degrees, spread_degrees)))
	var muzzle: Node3D = _muzzle
	var origin := _barrel.global_position
	if kind == "machine_gun" and is_instance_valid(_machine_muzzle):
		muzzle = _machine_muzzle
		origin = _turret.global_position
	elif kind == "rocket" and not _rocket_muzzles.is_empty():
		muzzle = _rocket_muzzles[0]
		origin = _turret.global_position
	var launch_position := _launch_weapon(origin, muzzle.global_position, direction, damage, speed, splash, kind)
	if kind == "machine_gun":
		game.spawn_muzzle_flash(launch_position, Color("ffd8a2"), 0.85, direction, kind)
		add_camera_shake(0.012)
		_rumble(0.07, 0.12, 0.065)
		AudioService.play_3d("machine_gun", launch_position, -16.0, _rng.randf_range(0.96, 1.04))
	elif kind == "rocket":
		game.spawn_muzzle_flash(launch_position, Color("ffc392"), 0.7, direction, kind)
		add_camera_shake(0.08)
		_rumble(0.25, 0.4, 0.18)
		AudioService.play_3d("rocket", launch_position, -6.0, 0.95)
	else:
		game.spawn_muzzle_flash(launch_position, Color("ffcc6d") if team == TEAM_PLAYER else Color("ff5c43"), 1.0 if not is_boss else 1.5, direction, kind)
		_recoil_peak = 0.75 if is_boss or archetype == "heavy" else 0.6
		_recoil_time = 0.0
		_hull_recoil_axis = Vector3.UP.cross(global_basis.inverse() * -direction).normalized()
		add_camera_shake(0.24)
		if is_player and SettingsService.screen_shake:
			_camera_pivot.kick_shot(1.25 if archetype == "heavy" else 1.0)
		_rumble(0.45, 0.82, 0.24)
		var firing_pitch := 1.04 if is_player else (0.72 if is_boss else 0.9)
		AudioService.play_3d("cannon", launch_position, -3.0 if not is_boss else -1.0, firing_pitch)
		AudioService.play_3d("cannon_tail", launch_position, -7.0 if not is_boss else -4.0, firing_pitch)
	return true


func _update_recoil(delta: float) -> void:
	_recoil_time += delta
	if _recoil_time < 0.065:
		_recoil = _recoil_peak * sin(_recoil_time / 0.065 * PI * 0.5)
	else:
		_recoil = _recoil_peak * pow(maxf(0.0, 1.0 - (_recoil_time - 0.065) / 0.56), 2.0)
	if is_instance_valid(_barrel):
		_barrel.position = _base_barrel_position + _barrel.basis.z * _recoil
	if is_instance_valid(_hull_body):
		# Only the suspension artwork rocks; the physical hull stays authoritative.
		_hull_body.rotation = _hull_base_rotation + _hull_recoil_axis * _recoil * 0.06


func _rumble(weak: float, strong: float, duration: float) -> void:
	if not is_player or not is_instance_valid(game):
		return
	var pad := game.get_node_or_null("GamepadInput")
	if pad != null:
		pad.rumble(weak, strong, duration)


func _launch_weapon(origin: Vector3, muzzle: Vector3, direction: Vector3, damage: float, speed: float, splash: float, kind: String) -> Vector3:
	# Long authored barrels can extend through cover while the hull remains
	# outside. Resolve the first obstruction before spawning a shell. Rocket pods
	# also need this check because their wide offset can protrude into side cover.
	var muzzle_path := PhysicsRayQueryParameters3D.create(
		origin, muzzle, 1 | (4 if team == TEAM_PLAYER else 2), [get_rid()]
	)
	muzzle_path.hit_from_inside = true
	var obstruction := get_world_3d().direct_space_state.intersect_ray(muzzle_path)
	if not obstruction.is_empty():
		var impact_position: Vector3 = obstruction["position"]
		var collider: Object = obstruction.get("collider")
		if collider != null and collider.has_method("receive_damage"):
			collider.call("receive_damage", damage, team, impact_position)
		if splash > 0.0:
			game.radial_damage(impact_position, splash, damage * 0.55, team)
		var normal: Vector3 = obstruction.get("normal", Vector3.UP)
		var surface := "armor" if collider is TankActor else ("ground" if normal.y > 0.55 else "stone")
		game.spawn_impact(impact_position, splash > 0.0, surface, normal, kind)
		return impact_position
	game.spawn_projectile(self, muzzle, direction, damage, speed, splash, kind)
	return muzzle


func try_dash(direction: Vector3) -> bool:
	if not is_player or dash_cooldown > 0.0 or stunned > 0.0 or destroyed or not active:
		return false
	var impulse := direction.normalized() if direction.length_squared() > 0.04 else _last_move
	velocity.x = impulse.x * move_speed * 1.35
	velocity.z = impulse.z * move_speed * 1.35
	_dash_remaining = 0.8
	dash_cooldown = 6.0
	invulnerable = 0.18
	return true


func try_emp() -> bool:
	if not is_player or emp_cooldown > 0.0 or stunned > 0.0 or destroyed or not active:
		return false
	emp_cooldown = 13.0
	game.emit_emp(self, 28.0)
	AudioService.play_3d("emp", global_position, -2.0)
	AudioService.radio("mines_cleared")
	return true


func try_place_mine() -> bool:
	if mine_ammo <= 0 or mine_cooldown > 0.0 or stunned > 0.0 or destroyed or not active:
		return false
	var behind := global_position + global_basis.z * 3.4
	game.spawn_mine(self, behind)
	mine_ammo -= 1
	mine_cooldown = 2.0 if is_player else 7.0
	if is_player:
		AudioService.radio("mine_deployed")
	return true


func apply_emp(duration: float) -> void:
	stunned = maxf(stunned, duration)
	velocity = Vector3.ZERO
	_aim_hold_time = 0.0
	_observation_clock = 0.0
	if boss_warning:
		boss_warning = false
		_charge_clock = 0.0
		_clear_salvo_telegraph()
		_salvo_clock = 7.0
		game.notify("EMP 已打断%s的火箭齐射" % display_name, 2.2)


func activate_boss() -> void:
	if not is_boss:
		return
	active = true
	ai_state = "acquire"
	_salvo_clock = 7.0
	reload = maxf(reload, 3.0)
	_aim_hold_time = 0.0
	game.spawn_emp_visual(global_position, 1.4)


func receive_damage(amount: float, attacker_team: int, hit_position := Vector3.ZERO) -> float:
	if destroyed or attacker_team == team or invulnerable > 0.0 or not active:
		return 0.0
	if not is_player:
		alert_from_hit(hit_position)
		if game.has_method("alert_enemy"):
			game.alert_enemy(self)
	var accepted := maxf(1.0, amount * (1.0 - armor))
	hp = maxf(0.0, hp - accepted)
	if is_player:
		_rumble(0.35, clampf(accepted / 70.0, 0.2, 0.9), 0.18)
	if is_player and hp > 0.0 and hp <= max_hp * 0.3:
		AudioService.radio("player_critical")
	AudioService.play_3d("hit", hit_position if hit_position != Vector3.ZERO else global_position, -9.0, _rng.randf_range(0.9, 1.12))
	if is_boss:
		var fraction := hp / max_hp
		var next_phase := 3 if fraction <= 0.35 else (2 if fraction <= 0.70 else 1)
		while boss_phase < next_phase:
			boss_phase += 1
			fire_interval = maxf(4.6, 5.4 - float(boss_phase - 1) * 0.4)
			move_speed = 4.3 + float(boss_phase - 1) * 0.25
			boss_phase_changed.emit(boss_phase)
	if hp <= 0.0:
		_die(attacker_team)
	return accepted


func add_camera_shake(strength: float) -> void:
	if not is_player or not SettingsService.screen_shake:
		return
	_camera_shake = minf(1.15, _camera_shake + maxf(0.0, strength))


func _update_camera_shake(delta: float) -> void:
	if not SettingsService.screen_shake:
		_camera_shake = 0.0
	_camera_shake = move_toward(_camera_shake, 0.0, delta * 2.9)
	var offset := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.58, 0.58),
		_rng.randf_range(-0.35, 0.35)
	) * _camera_shake
	_camera_pivot.update_view(delta, offset)


func _die(attacker_team: int) -> void:
	if destroyed:
		return
	destroyed = true
	active = false
	AudioService.stop_vehicle(_vehicle_audio)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if game.has_method("spawn_tank_wreck"):
		game.spawn_tank_wreck(self)
	visible = false
	if not game.has_method("spawn_tank_wreck"):
		game.spawn_explosion(global_position + Vector3.UP * 0.7, 1.75 if is_boss else 1.0)
	tank_destroyed.emit(self, attacker_team)
	if not is_player:
		queue_free()


func is_targetable() -> bool:
	return not destroyed and active and visible


func toggle_camera() -> void:
	if not is_player or not is_instance_valid(_camera_arm):
		return
	_controller_aim_active = false
	_camera_pivot.toggle()


func is_third_person() -> bool:
	return is_player and is_instance_valid(_camera_pivot) and _camera_pivot.third_person
