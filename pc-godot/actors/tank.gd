class_name TankActor
extends CharacterBody3D
## Native tank pawn shared by player, regular enemies and the chapter boss.

signal tank_destroyed(tank: TankActor, attacker_team: int)
signal boss_phase_changed(phase: int)

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1
const MODEL_SCALE := 0.35
const MODEL_SCENES := {
	"tank": preload("res://assets/models/quaternius/animated_tanks/Tank.glb"),
	"tank2": preload("res://assets/models/quaternius/animated_tanks/Tank2.glb"),
	"tank3": preload("res://assets/models/quaternius/animated_tanks/Tank3.glb"),
	"tank4": preload("res://assets/models/quaternius/animated_tanks/Tank4.glb"),
}
const MODEL_SOURCE_ANCHORS := {
	"tank": Vector3(0.0, -0.012609, -0.07009),
	"tank2": Vector3(0.0, -0.012609, -0.07009),
	"tank3": Vector3(0.0, -0.012609, -0.06748),
	"tank4": Vector3(0.0, -0.012609, -0.05219),
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
var move_speed := 13.5
var acceleration := 28.0
var turn_speed := 5.8
var projectile_speed := 66.0
var projectile_damage := 42.0
var fire_interval := 0.92
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

var _model: Node3D
var _turret: Node3D
var _barrel: Node3D
var _muzzle: Marker3D
var _rocket_muzzles: Array[Marker3D] = []
var _track_animator: AnimationPlayer
var _track_animation := ""
var _camera_pivot: Node3D
var _camera_arm: SpringArm3D
var camera: Camera3D
var _engine_audio: AudioStreamPlayer3D
var _ai_clock := 0.0
var _salvo_clock := 5.0
var _charge_clock := 0.0
var _strafe_sign := 1.0
var _rng := RandomNumberGenerator.new()
var _base_barrel_z := 0.0
var _recoil := 0.0
var _last_move := Vector3.FORWARD
var _camera_shake := 0.0
var _camera_base_position := Vector3.ZERO


func _ready() -> void:
	add_to_group("tanks")
	_rng.seed = hash(name) + (701 if is_boss else 31)
	_build_collision()
	_apply_role_stats()
	_build_model()
	if is_player:
		_build_camera()
	_engine_audio = AudioService.attach_engine(self)


func _build_collision() -> void:
	collision_layer = 2 if team == TEAM_PLAYER else 4
	collision_mask = 1 | 2 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.55, 2.25, 5.25) * (1.22 if is_boss else 1.0)
	collider.shape = shape
	collider.position.y = 1.14 * (1.22 if is_boss else 1.0)
	add_child(collider)


func _apply_role_stats() -> void:
	if is_player:
		display_name = "灰狼主战坦克"
		return
	if is_boss:
		display_name = "铁牙 · 围城指挥车"
		max_hp = 1050.0
		hp = max_hp
		armor = 0.22
		move_speed = 8.4
		projectile_damage = 48.0
		fire_interval = 1.12
		projectile_speed = 54.0
		active = false
		counts_for_objective = false
		return
	match archetype:
		"scout":
			display_name = "游骑侦察车"
			max_hp = 86.0
			move_speed = 14.5
			fire_interval = 0.78
			projectile_damage = 22.0
		"heavy":
			display_name = "磐石重装车"
			max_hp = 185.0
			armor = 0.18
			move_speed = 7.2
			fire_interval = 1.65
			projectile_damage = 55.0
		"sniper":
			display_name = "长枪猎歼车"
			max_hp = 105.0
			move_speed = 8.5
			fire_interval = 2.0
			projectile_damage = 67.0
			projectile_speed = 86.0
		_:
			display_name = "灰烬线列车"
			max_hp = 125.0
			move_speed = 10.2
			fire_interval = 1.28
			projectile_damage = 31.0
	hp = max_hp
	_ai_clock = _rng.randf_range(0.3, 1.2)
	_salvo_clock = _rng.randf_range(4.0, 7.0)
	_strafe_sign = -1.0 if _rng.randi() % 2 == 0 else 1.0


func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "ArmoredModel"
	_model.scale = Vector3.ONE * (1.18 if is_boss else 1.0)
	add_child(_model)
	var model_key := _model_key()
	var scene_resource: PackedScene = MODEL_SCENES.get(model_key) as PackedScene
	assert(scene_resource != null, "Missing armored vehicle model: %s" % model_key)
	var imported := scene_resource.instantiate() as Node3D
	assert(imported != null, "Armored vehicle model is not a Node3D: %s" % model_key)
	imported.name = "Hull"
	imported.set_meta("source_model", model_key)
	var imported_turret := imported.get_node_or_null("Tank_Turret") as MeshInstance3D
	var imported_gun := imported.get_node_or_null("Tank_Gun") as MeshInstance3D
	assert(imported_turret != null and imported_gun != null, "Tank model lacks separate turret or gun nodes")

	# The source pack faces -X and is authored at a larger scale. Skinned mesh
	# AABBs omit the skeleton's inverse-bind transform, so use measured rest-pose
	# anchors to keep every visible hull centered on its gameplay collision.
	var source_anchor: Vector3 = MODEL_SOURCE_ANCHORS[model_key]
	var imported_basis := Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * MODEL_SCALE)
	imported.transform = Transform3D(imported_basis, -(imported_basis * source_anchor))
	_model.add_child(imported)

	var turret_transform := imported.transform * imported_turret.transform
	var gun_transform := imported.transform * imported_gun.transform
	_turret = Node3D.new()
	_turret.name = "TurretPivot"
	_turret.position = turret_transform.origin
	_model.add_child(_turret)
	imported_turret.reparent(_turret, false)
	imported_turret.transform = Transform3D(turret_transform.basis, Vector3.ZERO)

	_barrel = Node3D.new()
	_barrel.name = "GunRecoil"
	_barrel.position = gun_transform.origin - turret_transform.origin
	_base_barrel_z = _barrel.position.z
	_turret.add_child(_barrel)
	imported_gun.reparent(_barrel, false)
	imported_gun.transform = Transform3D(gun_transform.basis, Vector3.ZERO)

	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, _gun_forward_extent(imported_gun) - 0.08)
	_barrel.add_child(_muzzle)

	_track_animator = imported.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_configure_track_animations()
	_tune_imported_materials()
	_add_vehicle_equipment()


func _model_key() -> String:
	if is_boss:
		return "tank4"
	if is_player:
		return "tank"
	match archetype:
		"scout":
			return "tank2"
		"heavy":
			return "tank3"
		"sniper":
			return "tank4"
		_:
			return "tank"


func _gun_forward_extent(gun_mesh: MeshInstance3D) -> float:
	var bounds := gun_mesh.get_aabb()
	var forward_extent := 0.0
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var point := gun_mesh.transform * Vector3(x, y, z)
				forward_extent = minf(forward_extent, point.z)
	return minf(-0.6, forward_extent)


func _configure_track_animations() -> void:
	if not is_instance_valid(_track_animator):
		return
	for animation_name: StringName in _track_animator.get_animation_list():
		var animation := _track_animator.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR


func _tune_imported_materials() -> void:
	var body_color := Color("53624a") if is_player else (Color("783c34") if not is_boss else Color("682a27"))
	var materials := {
		"armor": ArtFactory.material(body_color, 0.12, 0.68),
		"light": ArtFactory.material(body_color.lightened(0.18), 0.16, 0.58),
		"dark": ArtFactory.material(body_color.darkened(0.28), 0.24, 0.62),
		"steel": ArtFactory.material(Color("2d312e"), 0.82, 0.42),
	}
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source_material := mesh_instance.mesh.surface_get_material(surface)
			var material_name := source_material.resource_name.to_lower() if source_material != null else ""
			var category := "armor"
			if mesh_instance.name.begins_with("TrackMesh") or "wheel" in material_name:
				category = "steel"
			elif "dark" in material_name or "detail" in material_name:
				category = "dark"
			elif "light" in material_name:
				category = "light"
			mesh_instance.set_surface_override_material(surface, materials[category])


func _add_vehicle_equipment() -> void:
	var body_color := Color("53624a") if is_player else (Color("783c34") if not is_boss else Color("682a27"))
	var armor := ArtFactory.material(body_color.darkened(0.04), 0.14, 0.66)
	var armor_edge := ArtFactory.material(body_color.lightened(0.13), 0.18, 0.54)
	var steel := ArtFactory.material(Color("242925"), 0.82, 0.39)
	var soot := ArtFactory.material(Color("111412"), 0.55, 0.78)
	var glass := ArtFactory.material(Color("4deaf0") if is_player else Color("ff5948"), 0.12, 0.22, 5.0)
	var lamp := ArtFactory.material(Color("ffe4a1"), 0.08, 0.22, 1.8)
	var convoy_light := ArtFactory.material(Color("76bbb6") if is_player else Color("a7463d"), 0.1, 0.34, 1.35)

	# Headlights, convoy lights and exhausts make the hull readable in both
	# close title shots and the tactical camera.
	for side in [-1.0, 1.0]:
		ArtFactory.add_box(_model, "Headlamp", Vector3(side * 1.0, 0.64, -2.28), Vector3(0.24, 0.17, 0.08), lamp)
		ArtFactory.add_box(_model, "LampGuard", Vector3(side * 1.0, 0.64, -2.34), Vector3(0.32, 0.05, 0.035), steel)
		ArtFactory.add_box(_model, "RearConvoyLight", Vector3(side * 1.0, 0.64, 2.24), Vector3(0.14, 0.11, 0.06), convoy_light)
		ArtFactory.add_cylinder(_model, "Exhaust", Vector3(side * 1.02, 0.94, 1.9), 0.1, 0.48, soot, 12)

	# Commander cupola, independent optics, smoke launchers and flexible radio
	# masts add the top-surface detail that dominates this camera angle.
	ArtFactory.add_cylinder(_turret, "CommanderCupola", Vector3(0.34, 0.52, 0.28), 0.34, 0.16, armor_edge, 20)
	ArtFactory.add_box(_turret, "GunnerSight", Vector3(0.62, 0.48, -0.32), Vector3(0.25, 0.28, 0.34), steel)
	ArtFactory.add_box(_turret, "SightGlass", Vector3(0.62, 0.52, -0.51), Vector3(0.14, 0.13, 0.04), glass)
	for side in [-1.0, 1.0]:
		var antenna := ArtFactory.add_cylinder(_turret, "RadioAntenna", Vector3(side * 0.68, 1.02, 0.62), 0.018, 1.55 if is_boss else 1.25, steel, 8)
		antenna.rotation.z = deg_to_rad(side * 4.0)
		for launcher_index in range(3):
			var launcher := ArtFactory.add_cylinder(
				_turret,
				"SmokeLauncher",
				Vector3(side * (0.88 + launcher_index * 0.08), 0.25, -0.26 + launcher_index * 0.23),
				0.075,
				0.42,
				soot,
				10
			)
			launcher.rotation_degrees = Vector3(58.0, 0.0, side * 18.0)

	ArtFactory.add_box(_turret, "TeamIFF", Vector3(-0.48, 0.64, 0.18), Vector3(0.18, 0.18, 0.18), glass)
	var muzzle_brake := ArtFactory.add_cylinder(_barrel, "MuzzleBrake", Vector3(0, 0, _muzzle.position.z + 0.18), 0.19 if is_boss else 0.14, 0.38, soot, 16)
	muzzle_brake.rotation.x = PI * 0.5

	if archetype == "heavy" and not is_boss:
		for side in [-1.0, 1.0]:
			for z in [-1.25, -0.42, 0.42, 1.25]:
				ArtFactory.add_box(_model, "SideArmor", Vector3(side * 1.72, 1.08, z), Vector3(0.18, 0.54, 0.68), armor_edge)
	elif archetype == "sniper" and not is_boss:
		var sleeve := ArtFactory.add_cylinder(_barrel, "ThermalSleeve", Vector3(0, 0, _muzzle.position.z * 0.46), 0.18, 1.35, armor, 18)
		sleeve.rotation.x = PI * 0.5

	if is_boss:
		ArtFactory.add_box(_turret, "CommandSensor", Vector3(0, 0.86, 0.38), Vector3(0.48, 0.42, 0.52), steel)
		ArtFactory.add_sphere(_turret, "CommandOptic", Vector3(0, 1.12, 0.38), 0.18, glass, 16)
		for side in [-1.0, 1.0]:
			var side_name := "Left" if side < 0.0 else "Right"
			var pod := ArtFactory.add_box(_turret, "RocketPod" + side_name, Vector3(side * 1.38, 0.34, 0.18), Vector3(0.62, 0.72, 1.52), steel)
			for row in [-0.18, 0.18]:
				for z in [-0.44, 0.0, 0.44]:
					var tube := ArtFactory.add_cylinder(pod, "RocketTube", Vector3(row, 0.06, z), 0.11, 0.68, soot, 12)
					tube.rotation.x = PI * 0.5
			var rocket_muzzle := Marker3D.new()
			rocket_muzzle.name = "RocketMuzzle" + side_name
			rocket_muzzle.position = Vector3(0.0, 0.06, -0.82)
			pod.add_child(rocket_muzzle)
			_rocket_muzzles.append(rocket_muzzle)


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraRig"
	add_child(_camera_pivot)
	_camera_pivot.position = Vector3(0, 1.2, 1.5)
	_camera_base_position = _camera_pivot.position
	_camera_arm = SpringArm3D.new()
	_camera_arm.spring_length = 21.5
	_camera_arm.margin = 0.35
	_camera_arm.collision_mask = 1
	_camera_arm.rotation_degrees = Vector3(-49.0, 0, 0)
	_camera_pivot.add_child(_camera_arm)
	camera = Camera3D.new()
	camera.name = "BattleCamera"
	camera.fov = 57.0
	camera.near = 0.08
	camera.far = 500.0
	camera.current = true
	_camera_arm.add_child(camera)


func _process(delta: float) -> void:
	if is_player and is_instance_valid(_camera_pivot):
		_update_camera_shake(delta)


func _physics_process(delta: float) -> void:
	if destroyed or game == null or not game.is_combat_running():
		if is_instance_valid(_engine_audio):
			_engine_audio.volume_db = -80.0
		if is_instance_valid(_track_animator):
			_track_animator.pause()
		return
	reload = maxf(0.0, reload - delta)
	mine_cooldown = maxf(0.0, mine_cooldown - delta)
	emp_cooldown = maxf(0.0, emp_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	stunned = maxf(0.0, stunned - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	_recoil = move_toward(_recoil, 0.0, delta * 4.5)
	if is_instance_valid(_barrel):
		_barrel.position.z = _base_barrel_z + _recoil
	if active and stunned <= 0.0:
		if is_player:
			_player_control(delta)
		else:
			_ai_control(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_turret(delta)
	_update_track_animation()
	_update_engine_audio()


func _player_control(delta: float) -> void:
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var desired := Vector3(axis.x, 0, axis.y)
	_set_planar_velocity(desired, delta, move_speed * (2.15 if invulnerable > 0.0 and dash_cooldown > 3.35 else 1.0))
	var pad_aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if pad_aim.length() > 0.24:
		var aim_direction := Vector3(pad_aim.x, 0, pad_aim.y).normalized()
		aim_point = global_position + aim_direction * 35.0
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


func _ai_control(delta: float) -> void:
	var target: TankActor = game.player
	if not is_instance_valid(target) or target.destroyed:
		return
	var delta_to := target.global_position - global_position
	var distance := delta_to.length()
	var predicted := target.global_position + Vector3(target.velocity.x, 0, target.velocity.z) * clampf(distance / projectile_speed, 0.0, 0.8)
	aim_point = predicted
	if is_boss:
		_update_boss_attack(delta, target, distance)
		if boss_warning:
			_set_planar_velocity(Vector3.ZERO, delta, move_speed)
			return
	_ai_clock -= delta
	_salvo_clock -= delta
	var desired := Vector3.ZERO
	var ideal := 19.0 if archetype == "scout" else (34.0 if archetype == "sniper" else 25.0)
	if is_boss:
		ideal = 27.0
	if distance > ideal + 4.0:
		ai_state = "navigate"
		desired = delta_to.normalized()
	elif distance < ideal - 7.0:
		ai_state = "retreat"
		desired = -delta_to.normalized()
	else:
		ai_state = "strafe"
		desired = Vector3(-delta_to.z, 0, delta_to.x).normalized() * _strafe_sign
	if _ai_clock <= 0.0:
		_ai_clock = _rng.randf_range(0.8, 1.8)
		if _rng.randf() < 0.3:
			_strafe_sign *= -1.0
	desired = _avoid_obstacles(desired)
	_set_planar_velocity(desired, delta, move_speed)
	if distance < 62.0 and game.has_line_of_sight(_muzzle.global_position, target.global_position + Vector3.UP):
		var forward := -_turret.global_basis.z
		if forward.dot(delta_to.normalized()) > 0.96:
			try_fire()
	if mine_cooldown <= 0.0 and distance > 8.0 and distance < 25.0 and _salvo_clock <= 0.0:
		try_place_mine()
		_salvo_clock = _rng.randf_range(7.0, 11.0)


func _update_boss_attack(delta: float, target: TankActor, distance: float) -> void:
	if _charge_clock > 0.0:
		_charge_clock -= delta
		boss_warning = true
		if _charge_clock <= 0.0:
			boss_warning = false
			_fire_boss_salvo(target)
			_salvo_clock = 8.0 - boss_phase * 1.15
	elif _salvo_clock <= 0.0 and distance < 70.0:
		_charge_clock = 1.55 if boss_phase == 1 else 1.15
		boss_warning = true
		ai_state = "telegraph"
		AudioService.play_3d("boss_warning", global_position, -4.0, 0.88 + boss_phase * 0.08)


func _fire_boss_salvo(target: TankActor) -> void:
	var shots := 3 + boss_phase * 2
	for index in range(shots):
		var launch_marker := _rocket_muzzles[index % _rocket_muzzles.size()] if not _rocket_muzzles.is_empty() else _muzzle
		var launch_position := launch_marker.global_position
		var base := (target.global_position + Vector3.UP - launch_position).normalized()
		var spread := deg_to_rad((float(index) - float(shots - 1) * 0.5) * (5.5 - boss_phase))
		var direction := base.rotated(Vector3.UP, spread)
		game.spawn_projectile(self, launch_position, direction, projectile_damage * 0.72, projectile_speed * 0.9, 3.2, "rocket")
		game.spawn_muzzle_flash(launch_position, Color("ff593d"), 0.82)
	var audio_origin := _rocket_muzzles[0].global_position if not _rocket_muzzles.is_empty() else _muzzle.global_position
	AudioService.play_3d("cannon", audio_origin, -1.0, 0.68)
	AudioService.play_3d("cannon_tail", audio_origin, -4.5, 0.82)


func _set_planar_velocity(input_direction: Vector3, delta: float, speed: float) -> void:
	var direction := input_direction
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var target_velocity := direction * speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	if direction.length_squared() > 0.02:
		_last_move = direction.normalized()
		var wanted_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, wanted_yaw, clampf(turn_speed * delta, 0.0, 1.0))


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
	var aim_delta := aim_point - global_position
	aim_delta.y = 0.0
	if aim_delta.length_squared() < 0.05:
		return
	var world_yaw := atan2(-aim_delta.x, -aim_delta.z)
	var local_yaw := wrapf(world_yaw - rotation.y, -PI, PI)
	_turret.rotation.y = lerp_angle(_turret.rotation.y, local_yaw, clampf(delta * (9.0 if is_player else 5.0), 0.0, 1.0))


func _update_engine_audio() -> void:
	if not is_instance_valid(_engine_audio):
		return
	var ratio := Vector2(velocity.x, velocity.z).length() / maxf(move_speed, 0.1)
	_engine_audio.volume_db = -23.0 + ratio * 7.0
	_engine_audio.pitch_scale = 0.76 + ratio * 0.62


func _update_track_animation() -> void:
	if not is_instance_valid(_track_animator):
		return
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if planar_speed < 0.25:
		_track_animator.pause()
		return
	var local_velocity := global_basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	var suffix := "Tank_Forward"
	if absf(local_velocity.x) > absf(local_velocity.z) * 0.48:
		suffix = "Tank_TurningRight" if local_velocity.x > 0.0 else "Tank_TurningLeft"
	elif local_velocity.z > 0.0:
		suffix = "Tank_Backwards"
	var requested := "TankArmature|" + suffix
	if _track_animation != requested or not _track_animator.is_playing():
		_track_animation = requested
		_track_animator.play(requested, 0.12)
	_track_animator.speed_scale = clampf(planar_speed / maxf(move_speed, 0.1), 0.45, 1.7)


func try_fire() -> bool:
	if reload > 0.0 or stunned > 0.0 or destroyed or not active:
		return false
	reload = fire_interval
	var direction := -_turret.global_basis.z
	direction.y = 0.0
	direction = direction.normalized()
	game.spawn_projectile(self, _muzzle.global_position, direction, projectile_damage, projectile_speed, 2.1 if is_boss or archetype == "heavy" else 0.0, "cannon")
	game.spawn_muzzle_flash(_muzzle.global_position, Color("ffcc6d") if team == TEAM_PLAYER else Color("ff5c43"), 1.0 if not is_boss else 1.5)
	_recoil = 0.46 if is_boss else 0.34
	add_camera_shake(0.16)
	var firing_pitch := 1.04 if is_player else (0.72 if is_boss else 0.9)
	AudioService.play_3d("cannon", _muzzle.global_position, -3.0 if not is_boss else -1.0, firing_pitch)
	AudioService.play_3d("cannon_tail", _muzzle.global_position, -7.0 if not is_boss else -4.0, firing_pitch)
	return true


func try_dash(direction: Vector3) -> bool:
	if not is_player or dash_cooldown > 0.0 or stunned > 0.0:
		return false
	var impulse := direction.normalized() if direction.length_squared() > 0.04 else _last_move
	velocity.x = impulse.x * move_speed * 2.15
	velocity.z = impulse.z * move_speed * 2.15
	dash_cooldown = 4.0
	invulnerable = 0.32
	return true


func try_emp() -> bool:
	if not is_player or emp_cooldown > 0.0 or stunned > 0.0:
		return false
	emp_cooldown = 13.0
	game.emit_emp(self, 28.0)
	AudioService.play_3d("emp", global_position, -2.0)
	return true


func try_place_mine() -> bool:
	if mine_ammo <= 0 or mine_cooldown > 0.0 or stunned > 0.0 or destroyed or not active:
		return false
	var behind := global_position + global_basis.z * 3.4
	game.spawn_mine(self, behind)
	mine_ammo -= 1
	mine_cooldown = 2.0 if is_player else 7.0
	return true


func apply_emp(duration: float) -> void:
	stunned = maxf(stunned, duration)
	velocity = Vector3.ZERO
	if boss_warning:
		boss_warning = false
		_charge_clock = 0.0
		_salvo_clock = 3.4
		game.notify("EMP 已打断铁牙的火箭齐射", 2.2)


func activate_boss() -> void:
	if not is_boss:
		return
	active = true
	ai_state = "acquire"
	_salvo_clock = 2.8
	game.spawn_emp_visual(global_position, 1.4)


func receive_damage(amount: float, attacker_team: int, hit_position := Vector3.ZERO) -> float:
	if destroyed or attacker_team == team or invulnerable > 0.0 or not active:
		return 0.0
	var accepted := maxf(1.0, amount * (1.0 - armor))
	hp = maxf(0.0, hp - accepted)
	AudioService.play_3d("hit", hit_position if hit_position != Vector3.ZERO else global_position, -9.0, _rng.randf_range(0.9, 1.12))
	if is_boss:
		var fraction := hp / max_hp
		var next_phase := 3 if fraction <= 0.35 else (2 if fraction <= 0.70 else 1)
		while boss_phase < next_phase:
			boss_phase += 1
			fire_interval *= 0.82
			move_speed *= 1.08
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
		_camera_pivot.position = _camera_base_position
		return
	_camera_shake = move_toward(_camera_shake, 0.0, delta * 2.9)
	if _camera_shake <= 0.001:
		_camera_pivot.position = _camera_base_position
		return
	var offset := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.58, 0.58),
		_rng.randf_range(-0.35, 0.35)
	) * _camera_shake
	_camera_pivot.position = _camera_base_position + offset


func _die(attacker_team: int) -> void:
	if destroyed:
		return
	destroyed = true
	active = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	visible = false
	game.spawn_explosion(global_position + Vector3.UP * 0.7, 1.75 if is_boss else 1.0)
	tank_destroyed.emit(self, attacker_team)
	if not is_player:
		queue_free()


func is_targetable() -> bool:
	return not destroyed and active and visible


func toggle_camera() -> void:
	if not is_player or not is_instance_valid(_camera_arm):
		return
	var tactical := _camera_arm.spring_length < 29.0
	_camera_arm.spring_length = 36.0 if tactical else 21.5
	_camera_arm.rotation_degrees.x = -63.0 if tactical else -49.0
