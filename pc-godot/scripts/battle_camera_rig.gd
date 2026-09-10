class_name BattleCameraRig
extends Node3D
## World-aligned tactical view and collision-aware orbit camera share one camera.

var tank: Node3D
var camera: Camera3D
var arm: SpringArm3D
var third_person := false
var tactical_distance := 32.0
var chase_distance := 11.5
var yaw := 0.0
var pitch := -0.22
var _blend := 0.0
var _shot_kick := 0.0
var _hit_kick := 0.0
var _hit_age := 0.0
var _hit_side := 0.0
var _precision := 0.0
var _remote_pointer := Vector2.ZERO
var _remote_last_position := Vector2.INF
var _remote_pointer_active := false

func _ready() -> void:
	top_level = true
	name = "CameraRig"
	arm = SpringArm3D.new()
	arm.name = "CollisionArm"
	arm.spring_length = tactical_distance
	arm.margin = 0.4
	arm.collision_mask = 1
	var shape := SphereShape3D.new()
	shape.radius = 0.38
	arm.shape = shape
	add_child(arm)
	if tank is CollisionObject3D:
		arm.add_excluded_object(tank.get_rid())
	camera = Camera3D.new()
	camera.name = "BattleCamera"
	camera.near = 0.12
	camera.far = 680.0
	camera.fov = 59.0
	arm.add_child(camera)
	camera.current = true
	update_view(1.0, Vector3.ZERO)

func set_third_person(value: bool) -> void:
	if third_person == value:
		return
	third_person = value
	if is_instance_valid(tank) and tank.get("game") != null and tank.game.has_method("sync_pointer_mode"):
		tank.game.sync_pointer_mode()
	if value:
		# Enter looking along the turret so the view never starts behind the shot.
		var turret: Node3D = tank.get("_turret")
		yaw = turret.global_rotation.y if is_instance_valid(turret) else tank.rotation.y
		pitch = -0.18
	if is_instance_valid(tank) and tank.get("game") != null:
		var instructions := "第三人称 · 中心准星，鼠标转动视角 · F8 远程鼠标" if value else "俯视战术镜头 · 滚轮拉近进入第三人称 · C 切换"
		if value and SettingsService.remote_mouse:
			instructions = "远程鼠标 · 移动准星，靠近画面边缘转向 · F8 本地鼠标"
		tank.game.notify(instructions, 4.0)

func toggle() -> void:
	set_third_person(not third_person)

func zoom(steps: float) -> void:
	if third_person:
		chase_distance = clampf(chase_distance + steps * 1.3, 7.0, 17.0)
		if steps > 0.0 and chase_distance >= 17.0:
			set_third_person(false)
			tactical_distance = 24.0
	else:
		tactical_distance = clampf(tactical_distance + steps * 2.5, 20.0, 48.0)
		if steps < 0.0 and tactical_distance <= 20.0:
			chase_distance = 11.5
			set_third_person(true)

func handle_look(motion: Vector2) -> void:
	if not third_person:
		return
	yaw = wrapf(yaw - motion.x * 0.0023, -PI, PI)
	pitch = clampf(pitch - motion.y * 0.0021, -0.72, 0.12)

func reset_remote_pointer(forget_position := true) -> void:
	_remote_pointer_active = false
	if forget_position:
		_remote_last_position = Vector2.INF

func handle_absolute_pointer(position: Vector2, relative_motion := false) -> bool:
	if not third_person or not SettingsService.remote_mouse or not position.is_finite():
		return false
	var moved := not _remote_last_position.is_finite() or position.distance_squared_to(_remote_last_position) > 0.0001 or relative_motion
	_remote_last_position = position
	if not moved:
		return false
	_remote_pointer = position
	_remote_pointer_active = get_viewport().get_visible_rect().has_point(position)
	return true

func update_remote_look(delta: float, precision := 0.0) -> void:
	if not third_person or not SettingsService.remote_mouse or not _remote_pointer_active:
		return
	if not is_instance_valid(tank.game) or not tank.game.is_combat_running():
		return
	var bounds := get_viewport().get_visible_rect()
	if not bounds.has_point(_remote_pointer) or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var fraction := (_remote_pointer - bounds.position) / bounds.size
	var edge := Vector2(_edge_turn(fraction.x), _edge_turn(fraction.y))
	# Absolute input cannot wrap around the screen. Holding the pointer near
	# an edge turns continuously without recentering or raw-motion capture.
	handle_look(edge * Vector2(620.0, 320.0) * minf(delta, 0.1) * lerpf(1.0, 0.55, precision))

static func _edge_turn(fraction: float) -> float:
	if fraction < 0.12:
		return -clampf((0.12 - fraction) / 0.12, 0.0, 1.0)
	if fraction > 0.88:
		return clampf((fraction - 0.88) / 0.12, 0.0, 1.0)
	return 0.0

func kick_shot(strength: float) -> void:
	_shot_kick = minf(1.4, _shot_kick + strength)

func kick_hit(strength: float, force: Vector3) -> void:
	if not SettingsService.screen_shake:
		return
	_hit_kick = maxf(_hit_kick, clampf(strength, 0.0, 1.0))
	_hit_age = 0.0
	var view_right := Basis(Vector3.UP, yaw if third_person else 0.0).x
	_hit_side = clampf(force.normalized().dot(view_right), -1.0, 1.0)

func movement(axis: Vector2) -> Vector3:
	var direction := Vector3(axis.x, 0.0, axis.y)
	return Basis(Vector3.UP, yaw) * direction if third_person else direction

func update_view(delta: float, shake: Vector3) -> void:
	if not is_instance_valid(tank) or not is_instance_valid(arm):
		return
	_blend = move_toward(_blend, 1.0 if third_person else 0.0, delta * 3.0)
	if not SettingsService.screen_shake:
		_shot_kick = 0.0
		_hit_kick = 0.0
	var running: bool = is_instance_valid(tank.game) and tank.game.is_combat_running()
	if running:
		_shot_kick = move_toward(_shot_kick, 0.0, delta * 3.8)
		_hit_kick = move_toward(_hit_kick, 0.0, delta * 1.9)
		_hit_age += delta
		var held := Input.get_action_strength("precision_aim") if InputMap.has_action("precision_aim") else 0.0
		_precision = move_toward(_precision, held, delta * 5.0)
	var pivot := Vector3(0.0, 1.25, -3.0).lerp(Vector3(0.0, 2.6, 0.0), _blend)
	global_position = tank.global_position + pivot + shake * lerpf(1.0, 0.36, _blend)
	rotation = Vector3.ZERO
	arm.rotation = Vector3(lerpf(deg_to_rad(-55.0) + _shot_kick * 0.018, pitch + _shot_kick * 0.055, _blend), lerp_angle(0.0, yaw, _blend), 0.0)
	arm.spring_length = lerpf(tactical_distance + _shot_kick * 0.45, chase_distance + _shot_kick * 0.65, _blend)
	camera.fov = lerpf(59.0 + _shot_kick * 0.35, 66.0 - _precision * 12.0 + _shot_kick * 1.6, _blend)
	# A brief directional jolt and damped oscillation convey an armor strike.
	# Rotate the collision arm, leaving aim yaw/pitch and the tank's body intact.
	var vibration := sin(_hit_age * 34.0) * exp(-_hit_age * 7.0)
	arm.rotation.x += _hit_kick * (0.075 + vibration * 0.025)
	arm.rotation.z = _hit_kick * _hit_side * (0.05 + vibration * 0.015)
	arm.spring_length += _hit_kick * 0.6
	camera.fov += _hit_kick * 2.5

func aim_screen_point() -> Vector2:
	if SettingsService.remote_mouse and _remote_pointer_active and get_viewport().get_visible_rect().has_point(_remote_pointer):
		return _remote_pointer
	return get_viewport().get_visible_rect().size * 0.5
