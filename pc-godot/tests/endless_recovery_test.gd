extends Node
## Real physics, production HUD and scheduler; no direct wave/timer advancement.
const Monster = preload("res://actors/giant_monster.gd")
var game: Node3D
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func actor(kind: String, at: Vector3) -> Node3D:
	var monster := Monster.new()
	monster.game = game
	monster.director = game.endless
	monster.archetype = kind
	monster.position = at
	game.add_child(monster)
	game.endless.monsters.append(monster)
	return monster

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	SaveService._directory = "user://tests/endless_recovery_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.start_endless()
	game.player.set_physics_process(false)
	# Keep game._process and every UI snapshot active, unlike the older unit test.
	var cleared_at := -1
	var resumed := false
	for frame in 4200:
		await get_tree().physics_frame
		for monster: Node3D in game.endless.monsters.duplicate():
			monster.receive_damage(1000000, 0)
		if game.endless.wave == 1 and game.endless.pending == 0 and cleared_at < 0:
			cleared_at = frame
			game.pause_game()
			var clock_before := float(game.endless.wave_clock)
			await frames(60)
			check(game.endless.wave_clock == clock_before, "cleared-wave pause freezes the countdown with real HUD active")
			game.resume_game()
			resumed = true
		if game.endless.wave >= 2:
			check(cleared_at >= 0 and frame - cleared_at <= 365, "real first wave clears and wave two arrives within six unpaused seconds")
			break
	check(game.endless.wave >= 2 and resumed and game.mode == "playing", "normal game process, shop resume and HUD never terminate endless after first wave")
	game.start_endless()
	game.player.set_physics_process(false)
	game.endless.set_physics_process(false)
	# Reproduce exhaustion of the old six entrance candidates, without fake actors.
	for z in [-36.0, -64.0, -92.0]:
		for x in [-36.0, 0.0, 36.0]:
			actor("golem", Vector3(x, 0.1, z)).set_physics_process(false)
	game.endless.wave = 2
	game.endless.pending = 1
	game.endless._kaiju_pending = 1 # A small shambler can fit the gaps; a kaiju cannot.
	var reinforcement: Node3D = game.endless.spawn_monster()
	check(reinforcement != null and reinforcement.position.z < -115, "blocked old entrances use a free deeper approach without losing pending reinforcement")
	check(game.endless.pending == 0, "successful fallback consumes exactly one pending monster")
	game.start_endless()
	game.player.set_physics_process(false)
	game.endless.set_physics_process(false)
	game.player.position = Vector3(25, 0.1, 20)
	var hunter := actor("shambler", Vector3(-5, 0.1, -5))
	var distance_before := hunter.position.distance_to(game.player.position)
	await frames(180)
	check(hunter._pursuing and hunter.position.x > -1 and hunter.position.distance_to(game.player.position) < distance_before - 7, "monster notices tank and pursues it across the lane at increased speed")
	# Give the real collider time to approach, wind up and hit the stationary tank.
	var hp_before := float(game.player.hp)
	for frame in 900:
		await get_tree().physics_frame
		if game.player.hp < hp_before:
			break
	check(game.player.hp < hp_before, "pursuit ends in a real telegraphed attack that damages the player")
	hunter.set_physics_process(false)
	hunter.attack_cooldown = 0.0
	hunter.attack_remaining = 0.0
	hunter._begin_attack(game.player, false)
	game.player.position = Vector3(38, 0.1, 90)
	hp_before = game.player.hp
	hunter._tick_attack(2.0)
	check(game.player.hp == hp_before, "moving away during windup dodges the committed strike")
	game.start_endless()
	game.player.set_physics_process(false)
	game.endless.set_physics_process(false)
	game.player.position = Vector3(50, 0.1, 20)
	var blocked := actor("shambler", Vector3(50, 0.1, 78))
	blocked.receive_damage(1, 0)
	await frames(2)
	blocked._update_awareness(game.player)
	# The actual roadblock here is below the ray; use an actual tall world collider.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 8, 2)
	shape.shape = box
	wall.position = Vector3(50, 4, 48)
	wall.add_child(shape)
	game.add_child(wall)
	await frames(2)
	blocked._update_awareness(game.player)
	check(not blocked._pursuing, "retaliation still respects tall world occluders")
	check(Monster.ROLES.juggernaut.height == 72.0 and Monster.ROLES.glutton.height == 34.0, "new giant sizes retain building-scale silhouettes")
	game.free()
	print("ENDLESS RECOVERY: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
