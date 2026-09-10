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
	var outside := _tank(Vector3(10, 0, 0), 1)
	var wall := _box(Vector3(0, 2, -4.0), Vector3(4, 4, 0.4))
	var floor_body := _box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	var wreck := TankWreck.create_from_tank(source, 2, 1)
	add_child(wreck)
	wreck.set_physics_process(false)
	_check(TankWreck.COOKOFF_CHANCE == 0.25 and wreck.cookoff_time >= 3.3 and wreck.cookoff_time <= 7.2, "ammunition fires retain a 25 percent chance with a 3.3 to 7.2 second warning interval")
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
	wreck.age = 1.99
	wreck._physics_process(0.02)
	_check(wreck.cooked_off and explosions == 1 and get_tree().get_nodes_in_group("cookoff_fx").size() == 1 and wreck._turret.get_parent() == wreck and wreck._turret_airborne, "delayed ammunition cookoff occurs once with its own effect and ejects the original modeled turret")
	_check(wreck._turret_velocity.y > 12.0, "ammunition pressure launches the real modeled turret high above the vehicle")
	_check(ally.hits == 1 and enemy.hits == 1 and ally.last_attacker == -1 and enemy.last_attacker == -1, "neutral secondary explosion damages both nearby factions without awarding a player kill")
	_check(protected.hits == 0, "a solid building shields a nearby tank from cookoff blast damage")
	_check(outside.hits == 0 and TankWreck.COOKOFF_RADIUS == 9.0, "more violent fire visuals do not enlarge the established 9 meter damage boundary")
	wreck._physics_process(0.1)
	_check(explosions == 1 and get_tree().get_nodes_in_group("cookoff_fx").size() == 1 and ally.hits == 1 and enemy.hits == 1, "cookoff cannot apply repeated explosions or damage on later frames")
	var plume := get_tree().get_nodes_in_group("cookoff_fx")[0] as ExplosionFX
	plume.set_process(false)
	var fire := plume.get_node("CookoffFireColumn") as GPUParticles3D
	var fire_process := fire.process_material as ParticleProcessMaterial
	_check(fire_process.direction.dot(Vector3.UP) > 0.98 and fire_process.spread <= 25.0 and fire_process.initial_velocity_min >= 4.0 and fire_process.initial_velocity_max <= 8.0 and fire.lifetime < 1.5, "cookoff pressure rises briefly while remaining connected to the vehicle instead of launching fireballs")
	_check(plume._muzzle_jet == null and plume.get_node_or_null("CookoffCore") != null and plume.get_node_or_null("CookoffVent0") != null and plume.get_node_or_null("CookoffVent2") != null and fire_process.damping_min >= 5.0, "a continuous fluid core and three decelerating vents replace the fixed stretched flame card")
	var smoke := plume.get_node("CookoffSmokeColumn") as GPUParticles3D
	_check(smoke.lifetime > 5.0 and plume._duration > smoke.lifetime and plume.get_node("CookoffBurningFragments") is GPUParticles3D, "the fire column leaves lingering dark smoke and finite ballistic glowing fragments")
	var dust := plume.get_node("CookoffPressureDust") as GPUParticles3D
	_check(is_equal_approx(dust.global_position.y, 0.16) and (dust.process_material as ParticleProcessMaterial).radial_velocity_max >= 8.0, "large pressure dust expands across the floor rather than floating at the turret height")
	mode = "paused"
	var age_before := plume._age
	var fire_position_before := fire.position
	plume._process(0.4)
	_check(plume._age == age_before and fire.position == fire_position_before and fire.speed_scale == 0.0 and smoke.speed_scale == 0.0, "pause freezes each fluid vent and smoke without consuming their lifetime")
	mode = "playing"
	plume._process(0.14)
	_check(plume._age > age_before and fire.speed_scale == 1.0 and smoke.speed_scale == 1.0, "resume restores the same vent simulation instead of restarting or advancing the fluid animation while paused")
	plume._process(1.25)
	_check(plume._age > fire.lifetime and not plume.is_queued_for_deletion() and smoke.lifetime > plume._age, "the hot pressure surge burns out before its dark smoke instead of leaving a permanent flame column")
	var cookoff_particles := 0
	var cookoff_rgb := true
	for child: Node in plume.get_children():
		if child is GPUParticles3D:
			cookoff_particles += child.amount
			var process := child.process_material as ParticleProcessMaterial
			if process.scale_curve != null:
				cookoff_rgb = cookoff_rgb and process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB
	_check(cookoff_particles <= 144 and cookoff_rgb, "all five cookoff layers fit 144 GPU particles and preserve RGB scale channels")
	for frame in 300:
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
	for index in ExplosionFX.MAX_COOKOFFS + 3:
		var extra_plume := ExplosionFX.create_cookoff(Vector3(index * 12.0, 1.5, 0))
		add_child(extra_plume)
		extra_plume.set_process(false)
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("cookoff_fx").size() == ExplosionFX.MAX_COOKOFFS, "simultaneous ammunition fires obey an independent three-column performance limit")
	for index in ExplosionFX.MAX_BLASTS + 2:
		var blast := ExplosionFX.create(Vector3(index * 12.0, 1, 20))
		add_child(blast)
		blast.set_process(false)
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("blast_fx").size() == ExplosionFX.MAX_BLASTS and get_tree().get_nodes_in_group("impact_flash_lights").size() <= ExplosionFX.MAX_FLASH_LIGHTS, "cookoffs share the eight-blast and five-flash-light limits with ordinary explosions")
	for node: Node in get_tree().get_nodes_in_group("combat_effects"):
		node.free()
	await _test_cookoff_priority()
	_check(get_tree().get_nodes_in_group("tank_wrecks").is_empty() and get_tree().get_nodes_in_group("burning_wrecks").is_empty() and get_tree().get_nodes_in_group("cookoff_fx").is_empty(), "standard mission cleanup removes all wreck collision, fire, turret and pending cookoff state")
	for tank in [source, ally, enemy, protected, outside]:
		tank.free()
	wall.free()
	floor_body.free()
	await get_tree().process_frame
	print("TANK_WRECK_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)


func _test_cookoff_priority() -> void:
	var ordinary: Array[ExplosionFX] = []
	for index in ExplosionFX.MAX_BLASTS:
		var blast := ExplosionFX.create(Vector3(index * 12.0, 1, 20))
		add_child(blast)
		blast.set_process(false)
		blast._age = 3.4 - index * 0.01
		ordinary.append(blast)
	var priority := ExplosionFX.create_cookoff(Vector3(0, 1.5, 0))
	add_child(priority)
	priority.set_process(false)
	_check(not priority.is_queued_for_deletion() and priority.get_node_or_null("CookoffFireColumn") != null and ordinary[0].is_queued_for_deletion() and not ordinary[1].is_queued_for_deletion() and get_tree().get_nodes_in_group("blast_fx").size() == ExplosionFX.MAX_BLASTS and get_tree().get_nodes_in_group("impact_flash_lights").size() <= ExplosionFX.MAX_FLASH_LIGHTS, "a full eight-death burst gives the imminent cookoff visible fire vents by retiring only the oldest ordinary blast")
	for index in ExplosionFX.MAX_COOKOFFS:
		var followup := ExplosionFX.create_cookoff(Vector3(index * 12.0, 1.5, 0))
		add_child(followup)
		followup.set_process(false)
	await get_tree().process_frame
	_check(is_instance_valid(priority) and not priority.is_queued_for_deletion() and get_tree().get_nodes_in_group("cookoff_fx").size() == ExplosionFX.MAX_COOKOFFS and get_tree().get_nodes_in_group("blast_fx").size() == ExplosionFX.MAX_BLASTS and not is_instance_valid(ordinary[0]) and is_instance_valid(ordinary[3]), "successive priority cookoffs preserve existing fire columns and still obey three-cookoff and eight-blast limits")
	for effect: Node in get_tree().get_nodes_in_group("combat_effects"):
		effect.free()
