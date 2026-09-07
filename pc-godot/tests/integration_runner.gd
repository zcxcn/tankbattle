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
	var player_muzzle := game.player.get_node_or_null("ArmoredModel/TurretPivot/GunRecoil/Muzzle") as Marker3D
	var player_hull := game.player.get_node_or_null("ArmoredModel/Hull") as Node3D
	_check(
		player_turret != null and player_recoil != null and player_muzzle != null,
		"downloaded tank model preserves turret, recoil and muzzle gameplay anchors"
	)
	_check(
		player_hull != null and player_hull.get_meta("source_model", "") == "tank",
		"player uses the curated animated armored model"
	)
	if player_turret != null and player_muzzle != null:
		var muzzle_direction := (player_muzzle.global_position - player_turret.global_position).normalized()
		_check(
			muzzle_direction.dot(-player_turret.global_basis.z) > 0.94,
			"modeled gun and projectile muzzle share the same forward axis"
		)
	var regular: Array = game.enemies.filter(func(tank: TankActor) -> bool: return not tank.is_boss)
	_check(regular.size() == 6 and not game.boss.active, "boss remains shielded behind the first objective")
	var model_keys: Dictionary = {}
	var centered_visuals := true
	var muzzle_contracts := true
	var complete_track_sets := true
	var model_tanks: Array = [game.player]
	model_tanks.append_array(game.enemies)
	var required_track_animations := [
		"TankArmature|Tank_Forward",
		"TankArmature|Tank_Backwards",
		"TankArmature|Tank_TurningLeft",
		"TankArmature|Tank_TurningRight",
	]
	for tank: TankActor in model_tanks:
		var hull := tank.get_node_or_null("ArmoredModel/Hull") as Node3D
		if hull != null:
			model_keys[hull.get_meta("source_model", "")] = true
			centered_visuals = centered_visuals and absf(hull.position.x) < 0.05
			var animator := hull.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if animator == null:
				complete_track_sets = false
			else:
				for animation_name: String in required_track_animations:
					complete_track_sets = complete_track_sets and animator.has_animation(animation_name)
		else:
			centered_visuals = false
			complete_track_sets = false
		var turret := tank.get_node_or_null("ArmoredModel/TurretPivot") as Node3D
		var muzzle := tank.get_node_or_null("ArmoredModel/TurretPivot/GunRecoil/Muzzle") as Marker3D
		if turret == null or muzzle == null:
			muzzle_contracts = false
		else:
			var muzzle_offset := muzzle.global_position - turret.global_position
			muzzle_contracts = muzzle_contracts and muzzle_offset.length() > 1.4
			muzzle_contracts = muzzle_contracts and muzzle_offset.normalized().dot(-turret.global_basis.z) > 0.94
	_check(model_keys.size() == 4, "enemy roster uses all four distinct armored silhouettes")
	_check(centered_visuals, "all four skinned hulls stay centered on their gameplay collision")
	_check(muzzle_contracts, "all four modeled guns preserve a forward external muzzle")
	_check(complete_track_sets, "all four armored silhouettes preserve their complete track animation set")
	var player_animator := player_hull.get_node_or_null("AnimationPlayer") as AnimationPlayer if player_hull != null else null
	game.player.velocity = Vector3(0.0, 0.0, -3.0)
	game.player._update_track_animation()
	_check(
		player_animator != null and player_animator.is_playing() and player_animator.current_animation == "TankArmature|Tank_Forward",
		"vehicle movement drives the imported track skeleton"
	)
	game.player.velocity = Vector3.ZERO
	if player_animator != null:
		player_animator.pause()
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
