extends Node3D
## Real authored bores and swept projectiles must agree with a vertical aim point.

var passed := 0
var failed := 0
var shells: Array[IronProjectile] = []
var impacts: Array[Dictionary] = []
var running := true


func _ready() -> void:
	call_deferred("_run")


func is_combat_running() -> bool:
	return running


func notify(_message: String, _duration: float) -> void:
	pass


func spawn_projectile(owner_tank: TankActor, at: Vector3, direction: Vector3, damage: float, speed: float, splash: float, kind: String) -> void:
	var shell := IronProjectile.new()
	shell.game = self
	shell.owner_tank = owner_tank
	shell.team = owner_tank.team
	shell.position = at
	shell.direction = direction
	shell.damage = damage
	shell.speed = speed
	shell.splash_radius = splash
	shell.weapon_kind = kind
	add_child(shell)
	shell.set_physics_process(false)
	shells.append(shell)


func spawn_muzzle_flash(_at: Vector3, _color: Color, _scale: float, _direction: Vector3, _kind: String) -> void:
	pass


func spawn_impact(at: Vector3, _heavy: bool, surface: String, _normal: Vector3, weapon: String) -> void:
	impacts.append({"position": at, "surface": surface, "weapon": weapon})


func radial_damage(_at: Vector3, _radius: float, _damage: float, _team: int) -> void:
	pass


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	add_child(body)
	return body


func _run() -> void:
	var player := TankActor.new()
	player.game = self
	player.is_player = true
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var target := _box(Vector3(0, 8, -35), Vector3(3, 3, 3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for slot in 4:
		player._loadout.tick(20.0)
		player.select_weapon(slot)
		player.aim_point = target.global_position
		for step in 40:
			player._update_turret(0.1)
		var kind: String = player.get_weapon_snapshot().id
		var bore := player.get_firing_direction()
		_check(bore.y > 0.12 and bore.y < 0.42, kind + " physically elevates its authored bore toward the high target")
		var fired := player.try_fire()
		_check(fired and not shells.is_empty() and shells.back().direction.dot(bore) > 0.999, kind + " projectile starts along the visible bore without another pitch correction")
		for step in 240:
			if not shells.is_empty() and not shells.back().is_queued_for_deletion():
				shells.back()._physics_process(1.0 / 120.0)
		_check(not impacts.is_empty() and impacts.back().weapon == kind and impacts.back().position.distance_to(target.position) < 2.7, kind + " hits the elevated target using real swept flight")
		impacts.clear()
		shells.clear()
		await get_tree().process_frame
	target.free()
	var floor_body := _box(Vector3(0, -0.5, -55), Vector3(100, 1, 140))
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._loadout.tick(20.0)
	player.select_weapon(2)
	player.aim_point = Vector3(0, 0, -60)
	for step in 60:
		player._update_turret(0.1)
	player.try_fire()
	var he: IronProjectile = shells.back()
	for step in 300:
		if not he.is_queued_for_deletion():
			he._physics_process(1.0 / 120.0)
	_check(not impacts.is_empty() and impacts.back().position.distance_to(player.aim_point) < 0.2, "settled physical HE bore lands at the selected ground point")
	player.select_weapon(0)
	player.aim_point = Vector3(0, 90, -12)
	for step in 50:
		player._update_turret(0.1)
	_check(asin(player.get_firing_direction().y) <= deg_to_rad(20.01), "extreme upward aim respects the main gun elevation stop")
	player.aim_point = Vector3(0, -20, -12)
	for step in 50:
		player._update_turret(0.1)
	_check(asin(player.get_firing_direction().y) >= deg_to_rad(-10.01), "extreme downward aim respects the gun depression stop")
	player._barrel_pitch = 0.0
	player._barrel.rotation.x = player._base_barrel_pitch
	player.aim_point = Vector3(0, 10, -30)
	player._update_turret(0.016)
	_check(player._barrel_pitch > 0.0 and player._barrel_pitch <= 0.7 * 0.016 + 0.00001, "gun elevation takes real traverse time instead of snapping")
	floor_body.free()
	player.free()
	await get_tree().process_frame
	print("BARREL_ELEVATION_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
