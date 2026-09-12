extends SceneTree
## State and physics regressions for loadouts, patrol perception and lost contact.

const Loadout = preload("res://data/combat_loadout.gd")
const Vehicles = preload("res://data/vehicle_catalog.gd")
var passed := 0
var failed := 0

class CombatFixture extends Node3D:
	var player: Node3D
	var shots: Array[Dictionary] = []
	func is_combat_running() -> bool:
		return false
	func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
		return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()
	func spawn_projectile(owner_tank: Node3D, at: Vector3, direction: Vector3, damage: float, speed: float, splash: float, kind: String) -> void:
		shots.append({"owner": owner_tank, "at": at, "direction": direction, "damage": damage, "speed": speed, "splash": splash, "kind": kind})
	func spawn_muzzle_flash(_at: Vector3, _color: Color, _scale: float, _direction := Vector3.FORWARD, _kind := "cannon", _player_priority := false) -> void:
		pass
	func spawn_impact(_at: Vector3, _heavy: bool, _surface := "ground", _normal := Vector3.UP, _kind := "cannon", _player_priority := false) -> void:
		pass
	func radial_damage(_at: Vector3, _radius: float, _damage: float, _team: int, _contacts: Dictionary = {}, _weapon_kind := "blast") -> void:
		pass
	func spawn_mine(_owner: Node3D, _at: Vector3) -> void:
		pass
	func spawn_emp_visual(_at: Vector3, _scale: float) -> void:
		pass
	func notify(_text: String, _duration: float) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _run() -> void:
	_test_loadout()
	await _test_perception_and_actors()
	print("FIELD_COMBAT_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)


func _test_loadout() -> void:
	var loadout := Loadout.new()
	check(not loadout.select(-1) and not loadout.select(4) and loadout.selected == 0, "invalid hotkeys cannot corrupt selected weapon")
	check(loadout.fire().id == "cannon", "loadout fires the selected AP cannon")
	loadout.select(1)
	check(loadout.can_fire(), "coaxial machine gun has its own firing cycle")
	loadout.fire()
	loadout.select(0)
	check(not loadout.can_fire(), "switching away and back cannot bypass cannon loading")
	loadout.select(2)
	check(not loadout.can_fire(), "AP and HE share the physical cannon breech")
	loadout.tick(3.0)
	check(loadout.fire().id == "he" and loadout.snapshot().ammo == 23, "HE ammunition is finite and uses a fresh loaded breech")
	loadout.select(0)
	check(not loadout.can_fire(), "firing HE also locks the AP breech")
	loadout.select(3)
	for index in 8:
		check(not loadout.fire().is_empty(), "rocket %d consumes one legal round" % (index + 1))
		loadout.tick(6.0)
	check(loadout.snapshot().ammo == 0 and loadout.fire().is_empty(), "empty rocket rack cannot fire")
	loadout.select(1)
	for index in 39:
		loadout.fire()
		if index < 38:
			loadout.tick(0.15)
	check(loadout.snapshot().ammo == 0 and loadout.snapshot().belt_reloading, "empty machine-gun belt starts a real reload")
	loadout.select(3)
	loadout.tick(4.39)
	loadout.select(1)
	check(not loadout.can_fire(), "switching during a belt reload cannot shorten it")
	loadout.tick(0.02)
	check(loadout.snapshot().ammo == 40 and loadout.snapshot().reserve == 200, "completed belt replacement consumes reserve ammunition once")
	check(loadout.needs_resupply(), "partial magazines and empty rockets request supply")
	loadout.fire()
	var remaining: float = loadout.snapshot().reload
	loadout.resupply()
	check(not loadout.needs_resupply() and is_equal_approx(loadout.snapshot().reload, remaining), "resupply refills finite ammunition without resetting firing cooldown")
	var options := Vehicles.player_options()
	check(options.size() == 3 and options[0].model != options[1].model and options[1].model != options[2].model, "all three licensed hulls are playable")
	check(options[0].speed > options[1].speed and options[1].speed > options[2].speed and options[0].hp < options[2].hp, "playable chassis trade maneuverability for protection")
	check(Vehicles.ENEMY_ROLES.size() == 11 and Vehicles.enemy_role("gunner").weapon == "machine_gun" and Vehicles.enemy_role("rocket").weapon == "rocket" and Vehicles.enemy_role("artillery").weapon == "he", "eleven enemy roles include machine guns, rockets and heavy artillery")


func _actor(fixture: Node3D, role: String, player := false) -> Node3D:
	var actor: Node3D = load("res://actors/tank.gd").new()
	actor.game = fixture
	actor.is_player = player
	actor.team = 0 if player else 1
	actor.archetype = role
	fixture.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	return actor


func _test_perception_and_actors() -> void:
	var fixture := CombatFixture.new()
	root.add_child(fixture)
	var player := _actor(fixture, "line", true)
	fixture.player = player
	var enemy := _actor(fixture, "line")
	enemy.patrol_route.assign([Vector3(-15, 0, 0), Vector3(15, 0, 0)])
	player.position = Vector3(0, 0, 70)
	await physics_frame
	await physics_frame
	enemy._ai_control(0.1)
	check(enemy.ai_state == "patrol" and enemy.velocity.length() > 0.0 and fixture.shots.is_empty(), "unaware enemy follows its route without shooting a remote player")
	enemy.rotation = Vector3.ZERO
	enemy._turret.rotation = Vector3.ZERO
	player.position = Vector3(0, 0, 25)
	check(not enemy.can_see_target(player), "a silent target behind an unaware crew stays outside the sight cone")
	player.position = Vector3(0, 0, -25)
	check(enemy.can_see_target(player), "a target ahead inside the sight cone is visible")
	enemy.reload = 0.0
	enemy.velocity = Vector3.ZERO
	enemy._turret.rotation = Vector3.ZERO
	for tick in 100:
		enemy._ai_control(1.0 / 60.0)
	check(not fixture.shots.is_empty() and fixture.shots[0].kind == "cannon", "visible hostile contact receives a settled aimed shot")
	var remembered: Vector3 = enemy._last_seen_position
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 2, -12)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 6, 1)
	collision.shape = box
	wall.add_child(collision)
	fixture.add_child(wall)
	await physics_frame
	await physics_frame
	check(not enemy.can_see_target(player), "solid cover occludes a previously spotted enemy")
	player.position = Vector3(0, 0, -85)
	var shot_count := fixture.shots.size()
	enemy._ai_control(0.1)
	check(enemy.ai_state == "search" and enemy._last_seen_position == remembered and fixture.shots.size() == shot_count, "lost contact searches the last observation without tracking through cover")
	for tick in ceili(enemy.search_duration / 0.1) + 2:
		enemy._ai_control(0.1)
	check(enemy.ai_state == "patrol" and not enemy._has_contact, "expired search returns the crew to its patrol route")
	enemy.receive_damage(2.0, 0, enemy.global_position + Vector3.RIGHT)
	check(enemy.ai_state == "search" and enemy._search_remaining > 0.0 and enemy._last_seen_position != player.global_position, "incoming fire triggers a directional search without revealing shooter coordinates")
	wall.free()
	player.position = Vector3(80, 0, 0)
	enemy.position = Vector3(80, 0, -25)
	await physics_frame
	await physics_frame
	player.select_weapon(1)
	var before := fixture.shots.size()
	check(player.try_fire() and fixture.shots.size() == before + 1 and fixture.shots.back().kind == "machine_gun", "player machine gun reaches the projectile contract")
	player.select_weapon(3)
	check(player.try_fire() and fixture.shots.back().kind == "rocket", "player rocket slot fires independently of the machine gun")
	player.select_weapon(1)
	player.reload = 0.0
	check(not player.try_fire(), "legacy reload field cannot override actual weapon cooldown")
	check(player.needs_resupply(), "actor exposes its ammunition supply need")
	player.resupply()
	check(not player.needs_resupply(), "actor resupply fills weapons and mines")
	var gunner := _actor(fixture, "gunner")
	gunner.position = Vector3(110, 0, 0)
	for shot in 6:
		gunner.reload = 0.0
		gunner.try_fire()
	check(fixture.shots.back().kind == "machine_gun" and gunner.reload >= 3.0, "enemy machine gun pauses after six rounds instead of firing indefinitely")
	var scout_player := _actor(fixture, "scout", true)
	check(scout_player.get_node("ArmoredModel/Hull").get_meta("source_model") == "kf51" and scout_player.max_hp < player.max_hp and scout_player.move_speed > player.move_speed, "scout selection actually instantiates the faster lighter KF51 hull")
	var heavy_player := _actor(fixture, "heavy", true)
	check(heavy_player.get_node("ArmoredModel/Hull").get_meta("source_model") == "kv2" and heavy_player.armor > player.armor and heavy_player.move_speed < player.move_speed, "heavy selection instantiates armored KV2 geometry with slower mobility")
	var rocket_enemy := _actor(fixture, "rocket")
	rocket_enemy.position = Vector3(130, 0, 0)
	rocket_enemy.reload = 0.0
	check(rocket_enemy._rocket_muzzles.size() == 2 and rocket_enemy.try_fire() and fixture.shots.back().kind == "rocket", "rocket role has visible launch pods and actually fires rockets")
	fixture.free()
	await process_frame
