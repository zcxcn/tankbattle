extends Node
## Actual AI acquisition and ballistic hits at distance, without forcing try_fire.
var game: Node3D
var passed := 0
var failed := 0
var shots := 0
var first_shot_positions: Dictionary = {}

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

func box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	game.add_child(body)
	return body

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	SaveService._directory = "user://tests/enemy_range_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.start_game()
	game.set_process(false)
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	# A flat extension beyond the authored map isolates range from city cover.
	box(Vector3(400, -0.5, -85), Vector3(90, 1, 330))
	game.player.position = Vector3(400, 0.05, -120)
	game.player.velocity = Vector3.ZERO
	game.player.invulnerable = 0.0
	game.player.hp = 10000.0
	game.player.max_hp = 10000.0
	game.child_entered_tree.connect(func(node: Node) -> void:
		if node is IronProjectile:
			shots += 1
			var owner_id: int = node.owner_tank.get_instance_id()
			if not first_shot_positions.has(owner_id):
				first_shot_positions[owner_id] = node.owner_tank.global_position
	)
	for setup in [["line", 120.0], ["heavy", 120.0], ["sniper", 190.0], ["rocket", 160.0], ["gunner", 100.0], ["boss", 190.0]]:
		var kind: String = setup[0]
		var distance: float = setup[1]
		game.player.position = Vector3(400, 0.05, -distance)
		var enemy: TankActor = game._spawn_tank("RangeEnemy", Vector3(400, 0.05, 0), 1, false, kind == "boss", "line" if kind == "boss" else kind)
		enemy.active = true
		enemy._rng.seed = 411
		enemy._turret.rotation = Vector3.ZERO
		enemy._salvo_clock = 999.0 # Measure Boss main gun independently of rockets.
		var before := float(game.player.hp)
		var shots_before := shots
		for frame in 1200:
			await get_tree().physics_frame
			if game.player.hp < before:
				break
		check(shots > shots_before and game.player.hp < before, "%s AI actually fires and hits the tank at %.0fm" % [kind, distance])
		var first_at: Vector3 = first_shot_positions.get(enemy.get_instance_id(), Vector3.INF)
		check(first_at.is_finite() and first_at.distance_to(game.player.position) > enemy._ideal_distance + 15.0, "%s first shot happens at long range before closing to preferred maneuver distance" % kind)
		print("RANGE_TRACE %s shots=%d first_at=%s hit=%s" % [kind, shots - shots_before, first_at, game.player.hp < before])
		if kind == "line":
			enemy.set_physics_process(false)
			for shell: Node in get_tree().get_nodes_in_group("projectiles"):
				shell.free()
			var wall := box(Vector3(400, 4, -60), Vector3(35, 8, 2))
			await frames(3)
			check(not enemy.can_see_target(game.player), "building cover still blocks long-range acquisition")
			enemy.reload = 0.0
			enemy._aim_hold_time = enemy.aim_acquire_time
			shots_before = shots
			enemy._ai_control(0.1)
			check(shots == shots_before and enemy._aim_hold_time == 0.0, "occlusion cancels a prepared distant shot")
			wall.free()
			game.player.position.z = -enemy.sight_range - 20.0
			check(not enemy.can_see_target(game.player), "enemy vision remains bounded beyond its extended range")
		if kind == "boss":
			enemy.set_physics_process(false)
			enemy._salvo_clock = 0.0
			enemy._salvo_recovery = 0.0
			enemy._update_boss_attack(0.01, game.player, distance)
			check(enemy.boss_warning and enemy._charge_clock > 2.0, "Boss can announce a distant salvo while retaining its dodge warning")
		enemy.free()
		for shell: Node in get_tree().get_nodes_in_group("projectiles"):
			shell.free()
		await frames(2)
	game.free()
	print("ENEMY RANGE: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
