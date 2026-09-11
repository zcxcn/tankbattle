extends Node
## Production endless arena, actors, weapons and transitions using real physics.

var game: Node3D
var director: Node
var passed := 0
var failed := 0
var _campaign_before: Dictionary
var _save_directory := ""
var _save_profile: Dictionary


func _ready() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame


func _clear_projectiles() -> void:
	for shell: Node in get_tree().get_nodes_in_group("projectiles"):
		shell.free()


func _freeze_actors() -> void:
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		actor.set_physics_process(false)
	if is_instance_valid(game.player):
		game.player.set_physics_process(false)


func _spawn_at(at: Vector3) -> Node3D:
	director.pending = maxi(1, director.pending)
	var monster: Node3D = director.spawn_monster()
	if monster != null:
		monster.set_physics_process(false)
		monster.global_position = at
	return monster


func _check_campaign_unchanged(label: String) -> void:
	for key: String in ["completed_missions", "lifetime_kills", "best_score", "upgrade_points", "tank_level", "active_run"]:
		check(SaveService.profile[key] == _campaign_before[key], "%s preserves campaign %s" % [label, key])


func _startup_and_motion() -> Node3D:
	game.start_endless()
	game.set_process(false)
	game.player.set_physics_process(false)
	director = game.endless
	check(game.run_type == "endless" and game.mode == "playing", "title launches an independent playable endless mode")
	check(game.current_run_id.is_empty() and game.enemies.is_empty() and game.boss == null, "endless does not create a campaign run, tank roster or campaign boss")
	check(game.arena.get_meta("endless_arena", false) and not game.arena.has_meta("river_bounds"), "endless uses its own unobstructed siege boulevard")
	check(game.arena.get_radar_bounds() == Rect2(-110, -150, 220, 300), "endless radar matches the actual defense arena bounds")
	check(director.wave == 0 and director.monsters.is_empty(), "new defense provides its initial preparation interval")
	check(director.base_hp == 900.0 and director.base_max_hp == 900.0, "shelter starts with full readable durability")
	var initial_scrap: int = director.upgrades.scrap
	check(initial_scrap >= 60, "starter salvage permits a useful first upgrade")
	await frames(500)
	director.set_physics_process(false)
	check(director.wave == 1 and director.monsters.size() > 0, "real physics begins the first wave and spawns its first giant")
	if director.monsters.is_empty():
		return null
	var monster: Node3D = director.monsters[0]
	var start := monster.global_position
	await frames(120)
	check(monster.global_position.z > start.z + 0.2, "giant physically walks forward toward the defended shelter")
	check(monster.global_position.distance_to(start) < 12.0, "giant approach remains slow enough to plan a defense")
	check(monster.global_position.y > -0.2 and monster.global_position.y < 1.0, "giant stays supported by the boulevard collision")
	check(int(monster.collision_layer) & 4 != 0 and monster.is_targetable(), "live giant participates in hostile weapon collision")
	check(float(monster.get_meta("height", 0.0)) >= 7.0, "giant is substantially taller than the player's tank")
	_freeze_actors()
	_check_campaign_unchanged("Starting and advancing endless")
	return monster


func _damage_and_pause(monster: Node3D) -> void:
	monster.global_position = Vector3(0, 0.1, 0)
	monster.hp = maxf(1000.0, monster.max_hp)
	monster.max_hp = monster.hp
	await frames(3)
	var before := float(monster.hp)
	game.spawn_projectile(game.player, Vector3(0, 3.0, 16), Vector3.FORWARD, 25.0, 260.0, 0.0, "cannon")
	await frames(12)
	check(monster.hp < before and not monster.destroyed, "real swept cannon shell hits the giant's collision and deals damage")
	check(is_equal_approx(before - monster.hp, 25.0), "body shot applies its actual cannon damage exactly once")
	check(get_tree().get_nodes_in_group("projectiles").is_empty(), "shell resolves its giant impact and retires")
	before = monster.hp
	game.spawn_projectile(game.player, Vector3(0, monster.height * 0.85, 16), Vector3.FORWARD, 20.0, 260.0, 0.0, "cannon")
	await frames(12)
	check(is_equal_approx(before - monster.hp, 33.0), "real direct head shot receives the giant weak-point damage bonus")
	before = monster.hp
	monster.receive_damage(100.0, 1, monster.global_position + Vector3.UP * 3.0)
	check(is_equal_approx(monster.hp, before), "same-team direct damage cannot harm a giant")
	game.radial_damage(monster.global_position + Vector3.UP * 6.0, 8.0, 20.0, 0, {}, "he")
	check(monster.hp < before, "torso-height explosion damages a giant without measuring to its ground root")
	before = monster.hp
	game.radial_damage(monster.global_position + Vector3.UP * 8.0, 8.0, 20.0, 0, {}, "he")
	check(is_equal_approx(before - monster.hp, 20.0), "head-height splash damage does not receive a direct-shot weak-point bonus")
	before = monster.hp
	game.radial_damage(monster.global_position + Vector3.RIGHT * 30.0, 5.0, 100.0, 0)
	check(is_equal_approx(monster.hp, before), "out-of-range blast does not damage a distant giant")
	game.spawn_mine(game.player, Vector3.ZERO)
	var mine: Node3D = get_tree().get_nodes_in_group("mines").back()
	mine.set_physics_process(false)
	mine.armed_after = 0.0
	monster.global_position = Vector3(-10, 0.1, 0)
	mine._physics_process(0.016)
	before = monster.hp
	monster.global_position = Vector3(10, 0.1, 0)
	mine._physics_process(0.016)
	check(mine.is_queued_for_deletion() and monster.hp < before, "armed player mine catches a giant crossing between physics frames")
	await frames(2)
	monster.global_position = game.player.global_position + Vector3(0, 0, -15)
	game.spawn_mine(game.player, game.player.global_position + Vector3(4, 0, 0))
	var emp_mine: Node3D = get_tree().get_nodes_in_group("mines").back()
	game.emit_emp(game.player, 28.0)
	check(float(monster.stunned) > 0.0 and emp_mine.is_queued_for_deletion(), "EMP stuns nearby giant and safely defuses nearby player mine")
	before = monster.hp
	var position_before := monster.global_position
	monster.set_physics_process(true)
	await frames(25)
	check(Vector2(monster.global_position.x, monster.global_position.z).distance_to(Vector2(position_before.x, position_before.z)) < 0.2, "stunned giant stops advancing during the pulse window")
	director.set_physics_process(true)
	game.pause_game()
	var wave_before := float(director.wave_clock)
	var stun_before := float(monster.stunned)
	position_before = monster.global_position
	await frames(65)
	check(game.mode == "paused" and is_equal_approx(director.wave_clock, wave_before), "pause freezes endless wave scheduling")
	check(monster.global_position.is_equal_approx(position_before) and is_equal_approx(monster.stunned, stun_before), "pause freezes giant movement and EMP duration")
	game.resume_game()
	await frames(12)
	check(director.wave_clock < wave_before and monster.stunned < stun_before, "resuming restarts both wave and giant clocks")
	director.set_physics_process(false)
	_freeze_actors()
	monster.stunned = 0.0
	monster.global_position = Vector3(0, 0.1, 108)
	before = director.base_hp
	director.monster_reached_base(monster, -5.0)
	check(is_equal_approx(director.base_hp, before), "invalid negative base attack cannot heal or damage shelter")
	monster.set_physics_process(true)
	await frames(360)
	check(director.base_hp < before and director.base_hp > 0.0 and monster.global_position.z >= 112.0, "giant reaches the shelter wall and its real attack damages the defended frontline")
	monster.set_physics_process(false)
	var reward_before := int(director.upgrades.scrap)
	var kills_before := int(director.kills)
	monster.receive_damage(100000.0, 0, monster.global_position + Vector3.UP * 4.0)
	check(monster.destroyed and not monster.is_targetable(), "lethal damage makes giant untargetable immediately")
	check(is_instance_valid(monster) and not monster.is_queued_for_deletion(), "killed giant remains in the world for its falling corpse")
	check(director.kills == kills_before + 1 and director.upgrades.scrap > reward_before, "giant kill grants a reward and exactly one kill")
	var paid := int(director.upgrades.scrap)
	director.monster_killed(monster, 999)
	monster.receive_damage(100000.0, 0, monster.global_position)
	check(director.kills == kills_before + 1 and director.upgrades.scrap == paid, "replayed destruction cannot grant another reward")
	monster.set_physics_process(true)
	await frames(90)
	check(float(monster._visual.rotation.x) < -0.15 and monster.corpse_age > 1.0, "killed giant visibly tips over under its real death animation")
	game.pause_game()
	var corpse_time := float(monster.corpse_age)
	var corpse_pose: Vector3 = monster._visual.rotation
	await frames(30)
	check(is_equal_approx(monster.corpse_age, corpse_time) and monster._visual.rotation.is_equal_approx(corpse_pose), "pause freezes the visible falling body and corpse lifetime")
	game.resume_game()
	await frames(90)
	check(is_instance_valid(monster) and float(monster._visual.rotation.x) < -1.3 and monster._death_impact, "giant finishes falling with a ground impact and remains as a body")
	_check_campaign_unchanged("Combat and giant rewards")


func _upgrade_integration() -> void:
	game.player.global_position = Vector3(0, 0.1, 36)
	game.player.rotation = Vector3.ZERO
	game.player._turret.rotation.y = 0.0
	game.player._barrel.rotation.x = 0.0
	game.player.aim_point = Vector3(0, 2, -40)
	game.player._loadout.select(0)
	game.player._loadout.tick(100.0)
	game.player.reload = 0.0
	director.upgrades.add_reward(10000)
	check(not director.buy_upgrade("firepower"), "upgrades require the paused workshop")
	game.pause_game()
	game._buy_endless_upgrade("firepower")
	game._buy_endless_upgrade("autoloader")
	check(director.upgrades.levels.firepower == 1 and director.upgrades.levels.autoloader == 1, "game shop entry applies purchased firepower and autoloader levels")
	game.resume_game()
	_clear_projectiles()
	check(game.player.try_fire(), "upgraded player fires its actual cannon")
	var shots := get_tree().get_nodes_in_group("projectiles")
	check(shots.size() == 1, "upgraded cannon launches exactly one projectile")
	if not shots.is_empty():
		check(is_equal_approx(shots[0].damage, game.player.projectile_damage * 1.2), "production cannon projectile includes the purchased damage multiplier")
	check(is_equal_approx(game.player.get_weapon_snapshot().reload, game.player.fire_interval * 0.92), "production cannon uses the shorter purchased reload interval")
	var reload_before: float = game.player.get_weapon_snapshot().reload
	game.pause_game()
	game._buy_endless_upgrade("autoloader")
	check(is_equal_approx(game.player.get_weapon_snapshot().reload, reload_before), "buying a second autoloader never clears the active cannon cooldown")
	var base_max_before := float(director.base_max_hp)
	director.base_hp = 500.0
	game._buy_endless_upgrade("fortification")
	check(director.base_max_hp == base_max_before + 150.0 and director.base_hp == 650.0, "fortification raises actual base capacity and repairs its current durability")
	game.player.hp = game.player.max_hp - 80.0
	game._buy_endless_upgrade("repair")
	check(game.player.hp == game.player.max_hp and director.base_hp == 890.0, "repair restores real tank and shelter health with correct caps")
	director.base_hp = director.base_max_hp
	var scrap_before := int(director.upgrades.scrap)
	check(not director.buy_upgrade("repair") and director.upgrades.scrap == scrap_before, "fully intact defense cannot waste salvage on repairs")
	check(not director.buy_upgrade("ammo") and director.upgrades.scrap == scrap_before, "full ammunition cannot waste salvage on resupply")
	game.player._loadout.select(3)
	game.player._loadout.fire()
	game.player.mine_ammo = 2
	game._buy_endless_upgrade("ammo")
	check(game.player.get_weapon_snapshot().ammo == 8 and game.player.mine_ammo == 6, "ammo purchase refills actual rocket magazines and player mines")
	var snapshot: Dictionary = game.get_ui_snapshot()
	check(snapshot.run_type == "endless" and snapshot.endless.upgrades.size() == 5 and snapshot.endless.base_hp == director.base_hp, "UI snapshot exposes actual endless workshop and shelter state")
	game.resume_game()
	_clear_projectiles()


func _caps_and_transitions() -> void:
	# Simulate a backlog entering an elite wave; the promised elite must survive it.
	director.wave = 2
	director.pending = 13
	director.begin_wave()
	var player_at: Vector3 = game.player.global_position
	var entrance_x: float = [-32.0, 0.0, 32.0][director.spawned % 3]
	game.player.global_position = Vector3(entrance_x, 0.1, -105)
	var elite: Node3D = director.spawn_monster()
	check(elite != null and elite.global_position.distance_to(game.player.global_position) >= 28.0, "camping one entrance reroutes the next spawn while preserving player safety distance")
	game.player.global_position = player_at
	if elite != null:
		elite.set_physics_process(false)
		elite.global_position = Vector3(-34, 0.1, -65)
	check(elite != null and elite.archetype == "titan", "third wave spawns its promised elite even with an uncleared backlog")
	for index in 25:
		if director.monsters.size() >= director.MAX_ALIVE:
			break
		var grid_x := float((index % 3) - 1) * 25.0
		var grid_z := -65.0 + float(index / 3) * 22.0
		var monster := _spawn_at(Vector3(grid_x, 0.1, grid_z))
		if monster == null:
			break
	check(director.monsters.size() == director.MAX_ALIVE, "sustained spawning reaches the designed live-giant cap")
	director.pending = 20
	check(director.spawn_monster() == null and director.monsters.size() == director.MAX_ALIVE, "further spawn requests cannot exceed the live actor cap")
	for wave_index in 6:
		director.begin_wave()
	check(director.pending <= 32 and director.wave == 9, "overlapping endless waves continue while pending backlog remains bounded")
	var roster: Array = director.monsters.duplicate()
	for monster: Node3D in roster:
		monster.receive_damage(10000000.0, 0, monster.global_position + Vector3.UP * 3.0)
	await frames(3)
	check(director.monsters.is_empty() and director.corpses.size() <= director.MAX_CORPSES, "clearing a crowded wave limits persistent corpse count")
	var survivor := _spawn_at(Vector3(0, 0.1, 114))
	check(survivor != null, "endless spawning continues after previous actors are killed")
	game.play_time = 271.5
	director.base_hp = 1.0
	director.monster_reached_base(survivor, 60.0)
	check(game.mode == "lost" and director.base_hp == 0.0, "destroyed shelter ends the defense through the real game result flow")
	check(int(SaveService.profile.endless_best_wave) >= 9 and int(SaveService.profile.endless_best_kills) >= director.kills, "defeat records achieved endless wave and kill maxima")
	check(float(SaveService.profile.endless_best_time) >= 271.5, "defeat records survival time independently of campaign score")
	var reason: String = director.defeat_reason
	var score_before: int = game.score
	director.finish("late replacement")
	director.monster_killed(survivor, 999)
	check(director.defeat_reason == reason and game.score == score_before, "late attacks and rewards cannot replace a settled endless defeat")
	_check_campaign_unchanged("Endless settlement")
	var previous_id := director.get_instance_id()
	game.retry_game()
	director = game.endless
	director.set_physics_process(false)
	_freeze_actors()
	check(game.run_type == "endless" and game.mode == "playing" and director.get_instance_id() != previous_id, "retry recreates the chosen endless mode")
	check(director.kills == 0 and director.base_max_hp == 900.0 and director.upgrades.levels.firepower == 0, "retry resets run upgrades, kills and shelter durability")
	check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("monster_corpses").is_empty(), "retry removes all prior live giants and corpses")
	game.player.invulnerable = 0.0
	game.player.receive_damage(10000000.0, 1, game.player.global_position + Vector3.FORWARD * 4)
	check(game.mode == "lost" and game.player.destroyed and director.base_hp > 0.0, "losing the player tank also ends endless defense")
	game.return_to_menu()
	check(game.mode == "title" and game.run_type == "campaign" and game.endless == null, "returning to title restores ordinary campaign selection")
	check(get_tree().get_nodes_in_group("monsters").is_empty() and get_tree().get_nodes_in_group("monster_corpses").is_empty(), "title cleanup leaves no endless actors or corpses")
	_check_campaign_unchanged("Endless retry and menu exit")
	game.selected_mission = 0
	game.start_game()
	game.set_process(false)
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	check(game.run_type == "campaign" and not game.current_run_id.is_empty() and game.boss != null, "campaign can start normally after leaving endless mode")
	check(game.endless == null and game.arena.has_meta("river_bounds"), "campaign restores its river terrain without endless director state")
	check(is_equal_approx(game.player._loadout.fire().damage_multiplier, 1.0), "new campaign tank never inherits endless weapon damage")


func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	_save_directory = SaveService._directory
	_save_profile = SaveService.profile.duplicate(true)
	SaveService._directory = "user://tests/endless_mode_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	SaveService.profile.completed_missions = [0]
	SaveService.profile.lifetime_kills = 12
	SaveService.profile.best_score = 450
	SaveService.profile.upgrade_points = 2
	SaveService.save_now()
	_campaign_before = SaveService.profile.duplicate(true)
	game = load("res://scenes/main/main.tscn").instantiate()
	game.set_meta("endless_seed", 4821)
	add_child(game)
	await frames(3)
	var first := await _startup_and_motion()
	if first != null:
		await _damage_and_pause(first)
		_upgrade_integration()
		await _caps_and_transitions()
	game._clear_combat_nodes()
	game.free()
	await frames(3)
	SaveService.reset_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService._directory))
	SaveService._directory = _save_directory
	SaveService.profile = _save_profile
	print("Endless mode integration: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
