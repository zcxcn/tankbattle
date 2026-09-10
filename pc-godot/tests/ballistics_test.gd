extends Node3D
## Real Jolt collision regression for ballistic arcs, thin walls and smoke tails.

class TestTank extends TankActor:
	func _ready() -> void:
		collision_layer = 2 if team == 0 else 4
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 3, 2)
		shape.shape = box
		add_child(shape)
		set_physics_process(false)
	func receive_damage(amount: float, _team: int, _at := Vector3.ZERO, _weapon_kind := "blast") -> float:
		hp -= amount
		return amount

var passed := 0
var failed := 0
var running := true
var impacts: Array[Dictionary] = []
var damage_events := 0


func _ready() -> void:
	call_deferred("_run")


func is_combat_running() -> bool:
	return running


func spawn_impact(at: Vector3, heavy: bool, surface_kind := "ground", normal := Vector3.UP, weapon_kind := "cannon", _player_priority := false) -> void:
	impacts.append({"at": at, "heavy": heavy, "surface": surface_kind, "normal": normal, "weapon": weapon_kind})


func radial_damage(_at: Vector3, _radius: float, _damage: float, _team: int, _contacts: Dictionary = {}, _weapon_kind := "blast") -> void:
	damage_events += 1


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


func _shell(at: Vector3, kind: String, owner: TankActor = null) -> IronProjectile:
	var shell := IronProjectile.new()
	shell.game = self
	shell.position = at
	shell.weapon_kind = kind
	shell.owner_tank = owner
	for definition: Dictionary in CombatLoadout.WEAPONS:
		if definition.id == kind:
			shell.speed = definition.speed
	shell.damage = 10.0
	shell.direction = Vector3.FORWARD
	if kind == "he" and owner != null:
		shell.direction = IronProjectile.ballistic_direction(at, owner.aim_point, Vector3.FORWARD, shell.speed, 9.8)
	add_child(shell)
	shell.set_physics_process(false)
	return shell


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var wall := _box(Vector3(0, 2, -8), Vector3(10, 5, 0.025))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shell := _shell(Vector3(0, 2, 0), "machine_gun")
	shell._physics_process(0.2)
	_check(shell.is_queued_for_deletion() and impacts.size() == 1 and absf(impacts[0].at.z + 8) < 0.03, "500 m/s round hits a 25 mm wall during a 200 ms frame")
	shell._physics_process(0.2)
	_check(impacts.size() == 1, "resolved projectile cannot apply a second hit before queued cleanup")
	wall.free()
	await get_tree().process_frame
	impacts.clear()
	var floor_body := _box(Vector3(0, -0.5, -80), Vector3(200, 1, 220))
	var owner := TestTank.new()
	owner.position = Vector3(0, 2, 0)
	owner.aim_point = Vector3(0, 0, -60)
	add_child(owner)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var he := _shell(Vector3(0, 2, -2), "he", owner)
	he.splash_radius = 5.0
	var initial_velocity := he.flight_velocity
	owner._loadout = CombatLoadout.new()
	owner._loadout.select(2)
	owner._turret = Node3D.new()
	owner.add_child(owner._turret)
	owner._barrel = Node3D.new()
	owner._turret.add_child(owner._barrel)
	owner._muzzle = Marker3D.new()
	owner._barrel.add_child(owner._muzzle)
	owner._muzzle.global_position = he.global_position
	owner._muzzle.look_at(he.global_position + initial_velocity)
	var prediction: Dictionary = preload("res://scripts/battle_telemetry.gd")._get_reticle(owner, owner._barrel, owner._muzzle, owner._turret, get_world_3d().direct_space_state, owner.aim_point)
	var flight_time := 58.0 / -initial_velocity.z
	var midpoint := Vector3(0, 2, -2) + initial_velocity * (flight_time * 0.5) + Vector3.DOWN * 4.9 * pow(flight_time * 0.5, 2)
	_check(midpoint.y > 1.06 and is_equal_approx(he.gravity, 9.8) and is_equal_approx(he.speed, 185.0), "185 m/s HE follows a gravity-driven arc above the straight origin-target chord")
	for frame in 150:
		if he.is_queued_for_deletion():
			break
		he._physics_process(1.0 / 60.0)
	_check(impacts.size() == 1 and impacts[0].surface == "ground" and impacts[0].at.distance_to(owner.aim_point) < 0.2, "HE fire-control solution lands at the selected ground point with real swept collision")
	_check(prediction.position.distance_to(impacts[0].at) < 0.2, "HUD HE impact prediction agrees with the real articulated muzzle and swept ballistic hit")
	_check(damage_events == 1, "HE ground impact resolves splash damage exactly once")
	await get_tree().process_frame
	impacts.clear()
	var target := TestTank.new()
	target.team = 1
	target.position = Vector3(0, 2, -6)
	add_child(target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start_hp := owner.hp
	var target_hp := target.hp
	var inside_owner := _shell(owner.position, "cannon", owner)
	inside_owner._physics_process(0.2)
	_check(is_equal_approx(owner.hp, start_hp) and is_equal_approx(target.hp, target_hp - 10.0), "a shell born inside its launcher's collision shape excludes that tank and strikes the hostile body")
	_check(impacts.size() == 1 and impacts[0].surface == "armor", "tank contact selects the armored-impact profile")
	await get_tree().process_frame
	target.free()
	var tracers := 0
	var ap_model := _shell(Vector3(20, 2, 0), "cannon", owner)
	var ap_again := _shell(Vector3(23, 2, 0), "cannon", owner)
	var first_ogive := ap_model.get_node("Shell/OgivePenetrator") as MeshInstance3D
	var second_ogive := ap_again.get_node("Shell/OgivePenetrator") as MeshInstance3D
	_check(first_ogive.mesh is ArrayMesh and first_ogive.mesh == second_ogive.mesh, "fired AP rounds share a real imported ogive mesh rather than per-shot primitives")
	_check(ap_model.get_node_or_null("Shell/CopperBandForward") != null and ap_model.get_node_or_null("Shell/MachinedBase") != null, "solid AP model contains separate driving bands and machined base")
	var tracer_mesh := (ap_model.get_node("Tracer") as MeshInstance3D).mesh
	_check(tracer_mesh.get_aabb().size.z < 0.06, "tracer is a compact burning base with no stretched line or cylinder")
	ap_model.free()
	ap_again.free()
	for index in 8:
		var bullet := _shell(Vector3(20, 2, 0), "machine_gun", owner)
		if bullet.has_tracer:
			tracers += 1
		_check(bullet.find_children("*", "OmniLight3D").is_empty(), "machine-gun projectile has no point light")
		bullet.free()
	_check(tracers == 2, "eight machine-gun rounds contain exactly two short tracers")
	var paused_shell := _shell(Vector3(20, 2, 0), "cannon", owner)
	var original_lifetime := paused_shell.lifetime
	running = false
	paused_shell._physics_process(0.5)
	_check(paused_shell.position.is_equal_approx(Vector3(20, 2, 0)) and is_equal_approx(paused_shell.lifetime, original_lifetime), "paused combat freezes projectile travel and expiry")
	running = true
	paused_shell.free()
	var rocket := _shell(Vector3(20, 2, 0), "rocket", owner)
	_check(rocket.get_node_or_null("Shell/StabilizerFin4") != null and rocket.get_node_or_null("Shell/ExhaustNozzle") != null, "rocket has four modeled stabilizers and a recessed motor nozzle")
	var smoke := rocket.get_node("RocketSmoke") as GPUParticles3D
	rocket._physics_process(0.2)
	rocket._finish()
	_check(smoke.get_parent() == self and not smoke.emitting and not smoke.local_coords and smoke.is_in_group("combat_effects"), "rocket smoke uses world coordinates and remains after the rocket until its bound cleanup")
	smoke.free()
	owner.free()
	floor_body.free()
	await get_tree().process_frame
	print("BALLISTICS_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
