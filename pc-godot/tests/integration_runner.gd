extends Node
## Runs the real scene graph and combat actors against an isolated test profile.

var passed := 0
var failed := 0
var game: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


func _hull_bounds_in_tank(tank: TankActor, hull: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child: Node in hull.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var relative := tank.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds: AABB = relative * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	return bounds


func _clear_test_projectiles() -> void:
	for projectile: Node in get_tree().get_nodes_in_group("projectiles"):
		projectile.free()


func _check_scaled_ai_and_obstructed_barrel() -> void:
	var player_transform: Transform3D = game.player.global_transform
	var player_velocity: Vector3 = game.player.velocity
	var player_hp: float = game.player.hp
	var player_reload: float = game.player.reload
	var player_turret := game.player.get_node("ArmoredModel/TurretPivot") as Node3D
	var player_turret_rotation := player_turret.rotation
	var tested_models: Dictionary = {}
	game.player.global_position = Vector3(300.0, 5.0, -25.0)
	game.player.velocity = Vector3.ZERO
	for tank: TankActor in game.enemies:
		var model_key := tank._model_key()
		if tested_models.has(model_key):
			continue
		tested_models[model_key] = true
		var turret := tank.get_node("ArmoredModel/TurretPivot") as Node3D
		var saved_transform := tank.global_transform
		var saved_turret_rotation := turret.rotation
		var saved_active := tank.active
		var saved_reload := tank.reload
		var saved_velocity := tank.velocity
		var saved_salvo := tank._salvo_clock
		var saved_charge := tank._charge_clock
		var saved_warning := tank.boss_warning
		_clear_test_projectiles()
		tank.global_transform = Transform3D(Basis.IDENTITY, Vector3(300.0, 5.0, 0.0))
		turret.rotation = Vector3.ZERO
		tank.active = true
		tank.reload = 0.0
		tank._salvo_clock = 99.0
		tank._charge_clock = 0.0
		tank.boss_warning = false
		await _frames(2)
		tank._ai_control(0.0)
		var fired := false
		for projectile: Node in get_tree().get_nodes_in_group("projectiles"):
			if projectile is IronProjectile and (projectile as IronProjectile).owner_tank == tank:
				fired = true
		_check(fired, "%s AI fires its main gun with its scaled turret basis" % model_key)
		var before_hit: float = game.player.hp
		await _frames(45)
		_check(game.player.hp < before_hit, "%s AI shell reaches and damages the player collision" % model_key)
		game.player.hp = player_hp
		tank.global_transform = saved_transform
		turret.rotation = saved_turret_rotation
		tank.active = saved_active
		tank.reload = saved_reload
		tank.velocity = saved_velocity
		tank._salvo_clock = saved_salvo
		tank._charge_clock = saved_charge
		tank.boss_warning = saved_warning

	# Place thin cover between the gun pivot and its muzzle, entirely outside
	# the vehicle hull. A shell must stop here instead of appearing beyond it.
	_clear_test_projectiles()
	game.player.global_transform = Transform3D(Basis.IDENTITY, Vector3(300.0, 5.0, 0.0))
	player_turret.rotation = Vector3.ZERO
	game.player.reload = 0.0
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(8.0, 6.0, 0.30)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	game.add_child(wall)
	wall.global_position = Vector3(300.0, 7.0, -4.0)
	await _frames(2)
	_check(game.player.try_fire(), "player can fire when the long barrel intersects cover")
	var wall_shell: IronProjectile
	for projectile: Node in get_tree().get_nodes_in_group("projectiles"):
		if projectile is IronProjectile and (projectile as IronProjectile).owner_tank == game.player:
			wall_shell = projectile as IronProjectile
			break
	_check(
		wall_shell != null and wall_shell.global_position.z > wall.global_position.z,
		"obstructed cannon shell starts on the near side of thin cover"
	)
	await _frames(3)
	_check(not is_instance_valid(wall_shell), "obstructed shell impacts the wall instead of escaping past the muzzle")
	wall.free()
	_clear_test_projectiles()
	game.player.global_transform = player_transform
	game.player.velocity = player_velocity
	game.player.hp = player_hp
	game.player.reload = player_reload
	player_turret.rotation = player_turret_rotation


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Integration tests require -- --test")
		get_tree().quit(2)
		return
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	await _frames(4)
	_check(game.mode == "title", "native project opens at the command menu")
	_check(is_instance_valid(game.player.camera), "title presentation uses the real tank and 3D camera")
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "default audio layout exposes independent music and effects buses")
	game.start_game()
	await _frames(5)
	_check(game.mode == "playing", "start action enters Chapter 01")
	_check(game.enemies.size() == 7, "mission creates six enemies and Iron Fang")
	var player_turret := game.player.get_node_or_null("ArmoredModel/TurretPivot") as Node3D
	var player_recoil := game.player.get_node_or_null("ArmoredModel/TurretPivot/GunRecoil") as Node3D
	var player_muzzle := game.player.get_node_or_null("ArmoredModel/TurretPivot/GunRecoil/Muzzle") as Node3D
	var player_hull := game.player.get_node_or_null("ArmoredModel/Hull") as Node3D
	_check(
		player_turret != null and player_recoil != null and player_muzzle != null,
		"PBR tank model preserves turret, recoil and authored muzzle anchors"
	)
	_check(
		player_hull != null and player_hull.get_meta("source_model", "") == "challenger2",
		"player uses the curated high-detail Challenger 2 model"
	)
	if player_turret != null and player_muzzle != null:
		var muzzle_direction := (player_muzzle.global_position - player_turret.global_position).normalized()
		_check(
			muzzle_direction.dot(-player_turret.global_basis.z.normalized()) > 0.94,
			"modeled gun and projectile muzzle share the same forward axis"
		)
	var regular: Array = game.enemies.filter(func(tank: TankActor) -> bool: return not tank.is_boss)
	_check(regular.size() == 6 and not game.boss.active, "boss remains shielded behind the first objective")
	var model_keys: Dictionary = {}
	var centered_visuals := true
	var fitted_collisions := true
	var muzzle_contracts := true
	var imported_pbr_intact := true
	var pbr_by_model: Dictionary = {}
	var model_tanks: Array = [game.player]
	model_tanks.append_array(game.enemies)
	for tank: TankActor in model_tanks:
		var hull := tank.get_node_or_null("ArmoredModel/Hull") as Node3D
		if hull != null:
			var source_model := String(hull.get_meta("source_model", ""))
			model_keys[source_model] = true
			centered_visuals = centered_visuals and absf(hull.position.x) < 0.05 and absf(hull.position.z) < 0.05
			var bounds := _hull_bounds_in_tank(tank, hull)
			var collision := tank.get_node("HullCollision") as CollisionShape3D
			var collision_size := (collision.shape as BoxShape3D).size
			fitted_collisions = fitted_collisions and absf(collision_size.x - bounds.size.x) < 0.16
			fitted_collisions = fitted_collisions and absf(collision_size.z - bounds.size.z) < 0.16
			fitted_collisions = fitted_collisions and absf(bounds.get_center().x - collision.position.x) < 0.08
			fitted_collisions = fitted_collisions and absf(bounds.get_center().z - collision.position.z) < 0.08
			var saw_albedo := false
			var saw_normal := false
			var saw_metal_rough := false
			for node: Node in tank.get_node("ArmoredModel").find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh == null:
					continue
				# Team IFF and Boss launchers are runtime PrimitiveMesh equipment;
				# imported glTF geometry is ArrayMesh and must retain its own PBR.
				if mesh_instance.mesh is PrimitiveMesh:
					continue
				imported_pbr_intact = imported_pbr_intact and mesh_instance.material_override == null
				for surface in range(mesh_instance.mesh.get_surface_count()):
					imported_pbr_intact = imported_pbr_intact and mesh_instance.get_surface_override_material(surface) == null
					var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
					if material != null:
						saw_albedo = saw_albedo or material.albedo_texture != null
						saw_normal = saw_normal or material.normal_texture != null
						saw_metal_rough = saw_metal_rough or material.metallic_texture != null or material.roughness_texture != null
			pbr_by_model[source_model] = bool(pbr_by_model.get(source_model, false)) or (saw_albedo and saw_normal and saw_metal_rough)
		else:
			centered_visuals = false
		var turret := tank.get_node_or_null("ArmoredModel/TurretPivot") as Node3D
		var muzzle := tank.get_node_or_null("ArmoredModel/TurretPivot/GunRecoil/Muzzle") as Node3D
		if turret == null or muzzle == null:
			muzzle_contracts = false
		else:
			var muzzle_offset := muzzle.global_position - turret.global_position
			muzzle_contracts = muzzle_contracts and muzzle_offset.length() > 2.0
			muzzle_contracts = muzzle_contracts and muzzle_offset.normalized().dot(-turret.global_basis.z.normalized()) > 0.94
	_check(
		model_keys.size() == 3 and model_keys.has("challenger2") and model_keys.has("kf51") and model_keys.has("kv2"),
		"combat roster uses all three licensed high-detail armored silhouettes"
	)
	_check(centered_visuals, "all realistic hulls stay centered on their gameplay collision")
	_check(fitted_collisions, "each simple collision box fits the measured hull width, length and center")
	_check(muzzle_contracts, "all authored guns preserve a forward external muzzle")
	_check(
		imported_pbr_intact
			and bool(pbr_by_model.get("challenger2", false))
			and bool(pbr_by_model.get("kf51", false))
			and bool(pbr_by_model.get("kv2", false)),
		"all three models retain source base-color, normal and metal-rough PBR maps without runtime overrides"
	)
	if player_recoil != null and player_muzzle != null:
		var gun_rotation := player_recoil.rotation
		var trunnion_before := player_recoil.global_position
		var muzzle_height_before := player_muzzle.global_position.y
		player_recoil.rotation.x += deg_to_rad(6.0)
		_check(
			player_recoil.global_position.is_equal_approx(trunnion_before)
				and player_muzzle.global_position.y > muzzle_height_before + 0.08,
			"authored gun pivot elevates the muzzle without moving the trunnion"
		)
		player_recoil.rotation = gun_rotation
	var left_rocket_muzzle := game.boss.get_node_or_null("ArmoredModel/TurretPivot/RocketPodLeft/RocketMuzzleLeft") as Marker3D
	var right_rocket_muzzle := game.boss.get_node_or_null("ArmoredModel/TurretPivot/RocketPodRight/RocketMuzzleRight") as Marker3D
	_check(
		left_rocket_muzzle != null and right_rocket_muzzle != null and left_rocket_muzzle.global_position.distance_to(right_rocket_muzzle.global_position) > 2.0,
		"Iron Fang salvo has distinct left and right rocket launch points"
	)
	var clear_spawns := true
	for tank: TankActor in regular:
		for cover: Node in get_tree().get_nodes_in_group("destructible_cover"):
			var delta_xz := Vector2(tank.global_position.x - (cover as Node3D).global_position.x, tank.global_position.z - (cover as Node3D).global_position.z)
			if delta_xz.length() < 5.0:
				clear_spawns = false
	_check(clear_spawns, "regular enemies spawn clear of destructible cover")
	for tank: TankActor in game.enemies:
		tank.set_physics_process(false)
	game.player.set_physics_process(false)
	await _check_scaled_ai_and_obstructed_barrel()
	_check(game.player.try_place_mine(), "player can place a mine with finite inventory")
	var enemy: TankActor = regular[0]
	enemy.global_position = game.player.global_position + Vector3(7.0, 0.0, 0.0)
	await _frames(1)
	_check(enemy.try_place_mine(), "enemy uses the same physical mine system")
	await _frames(2)
	_check(get_tree().get_nodes_in_group("mines").size() == 2, "both faction mines exist in the world")
	var friendly_mine: TankMine
	for node: Node in get_tree().get_nodes_in_group("mines"):
		if node is TankMine and (node as TankMine).team == TankActor.TEAM_PLAYER:
			friendly_mine = node as TankMine
			break
	var mine_position := friendly_mine.global_position
	friendly_mine.armed_after = 0.0
	enemy.global_position = mine_position + Vector3(-8.0, 0.0, 0.0)
	await _frames(1)
	enemy.global_position = mine_position + Vector3(8.0, 0.0, 0.0)
	await _frames(2)
	_check(not is_instance_valid(friendly_mine), "runtime mine catches a tank crossing its trigger between physics frames")
	game.player.mine_cooldown = 0.0
	_check(game.player.try_place_mine(), "player can replenish the swept-trigger test mine")
	await _frames(2)
	game.player.emp_cooldown = 0.0
	_check(game.player.try_emp(), "player EMP activates through the tank ability")
	await _frames(2)
	_check(get_tree().get_nodes_in_group("mines").is_empty(), "EMP safely clears friendly and hostile mines")
	for tank: TankActor in regular:
		tank.active = true
		tank.receive_damage(10000.0, TankActor.TEAM_PLAYER, tank.global_position)
	await _frames(3)
	_check(game.mission_kills == 6, "six regular destructions satisfy the street objective")
	_check(game.boss.active and game.mode == "playing", "Iron Fang activates and blocks completion")
	game.boss.boss_warning = true
	game.boss._charge_clock = 1.0
	game.boss.apply_emp(1.0)
	_check(not game.boss.boss_warning and game.boss._charge_clock == 0.0, "EMP interrupts a telegraphed boss salvo")
	var phase_events: Array[int] = []
	game.boss.boss_phase_changed.connect(func(phase: int) -> void: phase_events.append(phase))
	game.boss.receive_damage(game.boss.max_hp * 0.90, TankActor.TEAM_PLAYER, game.boss.global_position)
	_check(game.boss.boss_phase == 3, "one heavy hit can cross both boss armor thresholds")
	_check(phase_events == [2, 3], "runtime boss emits the 70 and 35 percent phases once and in order")
	game.boss.receive_damage(10000.0, TankActor.TEAM_PLAYER, game.boss.global_position)
	await _frames(3)
	_check(game.mode == "won", "destroying Iron Fang completes the mission")
	_check(0 in SaveService.profile.completed_missions, "mission completion is persisted")
	_check(int(SaveService.profile.lifetime_kills) == 7, "confirmed kills persist exactly once")
	SaveService.profile["lifetime_kills"] = 23
	SaveService.save_now()
	SaveService.profile["lifetime_kills"] = 24
	SaveService.save_now()
	var corrupt_primary := FileAccess.open("user://tests/profile_0.json", FileAccess.WRITE)
	corrupt_primary.store_string("{}")
	corrupt_primary.close()
	SaveService.load_profile()
	_check(SaveService.recovered_from_backup and int(SaveService.profile.lifetime_kills) == 23, "invalid primary save recovers the last validated backup")
	print("INTEGRATION_RESULT: %d passed, %d failed" % [passed, failed])
	game.queue_free()
	await _frames(3)
	SaveService.reset_for_tests()
	get_tree().quit(0 if failed == 0 else 1)
