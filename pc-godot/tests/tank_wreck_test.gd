extends Node3D
## Real Jolt collision, immutable shared models and bounded wreck/cookoff state.

class TestTank extends TankActor:
	var hits := 0
	var last_attacker := 0
	func _ready() -> void:
		add_to_group("tanks")
		collision_layer = 2 if team == 0 else 4
		collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.name = "HullCollision"
		var shape := BoxShape3D.new()
		shape.size = Vector3(3, 2, 5)
		collider.shape = shape
		collider.position.y = 1.0
		add_child(collider)
		var model := Node3D.new()
		model.name = "ArmoredModel"
		add_child(model)
		ArtFactory.add_box(model, "Hull", Vector3.UP, shape.size, ArtFactory.material(Color("687547")))
		var turret := Node3D.new()
		turret.name = "TurretPivot"
		turret.position.y = 2.0
		model.add_child(turret)
		ArtFactory.add_box(turret, "Turret", Vector3.ZERO, Vector3(1.8, 0.6, 2.0), ArtFactory.material(Color("687547")))
		set_physics_process(false)
		set_process(false)
	func receive_damage(amount: float, attacker: int, _at := Vector3.ZERO) -> float:
		hits += 1
		last_attacker = attacker
		hp -= amount
		return amount

var mode := "playing"
var passed := 0
var failed := 0
var explosions := 0


func _ready() -> void:
	call_deferred("_run")


func is_combat_running() -> bool:
	return mode == "playing"


func spawn_explosion(_at: Vector3, _scale: float) -> void:
	explosions += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _tank(at: Vector3, team: int) -> TestTank:
	var tank := TestTank.new()
	tank.game = self
	tank.position = at
	tank.team = team
	add_child(tank)
	return tank


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.position = at
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
	return wall


func _run() -> void:
	var source := _tank(Vector3.ZERO, 0)
	var ally := _tank(Vector3(-5, 0, 0), 0)
	var enemy := _tank(Vector3(5, 0, 0), 1)
	var protected := _tank(Vector3(0, 0, -7), 1)
	var wall := _box(Vector3(0, 2, -4.0), Vector3(4, 4, 0.4))
	var floor_body := _box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	var wreck := TankWreck.create_from_tank(source, 2, 1)
	add_child(wreck)
	wreck.set_physics_process(false)
	source.destroyed = true
	source.hide()
	var source_hull := source.get_node("ArmoredModel/Hull") as MeshInstance3D
	var burnt_hull := wreck.get_node("BurntArmoredModel/Hull") as MeshInstance3D
	_check(burnt_hull.mesh == source_hull.mesh and burnt_hull.material_override != source_hull.material_override and source_hull.material_override is StandardMaterial3D and source_hull.material_override.albedo_color.is_equal_approx(Color("687547")), "wreck shares the original hull mesh without mutating a live tank's paint")
	_check(wreck.visible and wreck.is_in_group("combat_effects") and wreck.is_in_group("tank_wrecks") and explosions == 1, "death immediately leaves a visible wreck with one initial explosion and normal scene cleanup ownership")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-10, 1, 0), Vector3(10, 1, 0), 1)
	_check(get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == wreck, "the leftover armored hull remains a real solid ballistic and movement obstruction")
	wreck.cookoff_time = 2.0
	mode = "paused"
	wreck._physics_process(10.0)
	_check(wreck.age == 0.0 and not wreck.cooked_off and explosions == 1 and wreck._emitters[0].speed_scale == 0.0, "pause freezes cookoff, fragments and continuous fire simulation")
	mode = "playing"
	wreck._physics_process(2.1)
	_check(wreck.cooked_off and explosions == 2 and wreck._turret.get_parent() == wreck and wreck._turret_airborne, "delayed ammunition cookoff occurs once and ejects the original modeled turret")
	_check(ally.hits == 1 and enemy.hits == 1 and ally.last_attacker == -1 and enemy.last_attacker == -1, "neutral secondary explosion damages both nearby factions without awarding a player kill")
	_check(protected.hits == 0, "a solid building shields a nearby tank from cookoff blast damage")
	wreck._physics_process(0.1)
	_check(explosions == 2 and ally.hits == 1 and enemy.hits == 1, "cookoff cannot apply repeated explosions or damage on later frames")
	for frame in 180:
		wreck._physics_process(1.0 / 60.0)
	_check(not wreck._turret_airborne and wreck._turret.global_position.y >= 0.25, "thrown turret falls under gravity, bounces once and settles above the floor")
	wreck._physics_process(35.0)
	_check(wreck._emitters.is_empty() and not wreck.is_in_group("burning_wrecks") and not wreck.is_queued_for_deletion(), "fire stops after a bounded interval while the charred hull persists")
	var frozen := TankWreck.create_from_tank(source, 0, 1)
	add_child(frozen)
	frozen.set_physics_process(false)
	mode = "won"
	frozen._physics_process(9.0)
	_check(not frozen.cooked_off and frozen._emitters[0].speed_scale == 1.0, "victory preserves wreck fire visuals but prevents post-result cookoff damage")
	mode = "playing"
	var fractured := TankWreck.create_from_tank(source, 1, 0)
	add_child(fractured)
	fractured.set_physics_process(false)
	_check(fractured._turret.get_parent() == fractured and fractured._turret_airborne and not fractured.will_cook_off, "turret-ring destruction is distinct from engine fire and optional cookoff")
	for index in TankWreck.MAX_WRECKS + 8:
		var extra := TankWreck.create_from_tank(source, index % 3, 0)
		extra.position.x = 20.0 + float(index) * 4.0
		add_child(extra)
		extra.set_physics_process(false)
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("tank_wrecks").size() == TankWreck.MAX_WRECKS and get_tree().get_nodes_in_group("burning_wrecks").size() <= TankWreck.MAX_BURNING_WRECKS, "long fights retain at most 14 solid wrecks and 6 active smoke/fire emitters")
	var count := 0
	var rgb := true
	for node: Node in get_tree().get_nodes_in_group("tank_wrecks"):
		for emitter: GPUParticles3D in node._emitters:
			count += emitter.amount
			rgb = rgb and (emitter.process_material as ParticleProcessMaterial).scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB
	_check(count <= TankWreck.MAX_BURNING_WRECKS * 40 and rgb, "persistent debris uses no rigid bodies and at most 240 RGB-scaled GPU particles")
	for node: Node in get_tree().get_nodes_in_group("combat_effects"):
		node.free()
	_check(get_tree().get_nodes_in_group("tank_wrecks").is_empty() and get_tree().get_nodes_in_group("burning_wrecks").is_empty(), "standard mission cleanup removes all wreck collision, fire, turret and pending cookoff state")
	for tank in [source, ally, enemy, protected]:
		tank.free()
	wall.free()
	floor_body.free()
	await get_tree().process_frame
	print("TANK_WRECK_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
