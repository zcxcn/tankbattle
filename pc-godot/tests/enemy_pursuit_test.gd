extends "res://tests/enemy_range_test.gd"
## A visible target outside preferred range must draw a real moving attacker.

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	SaveService._directory = "user://tests/enemy_pursuit_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.start_game()
	game.set_process(false)
	for tank: Node in get_tree().get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	box(Vector3(400, -0.5, -70), Vector3(100, 1, 320))
	game.player.position = Vector3(400, 0.05, -70)
	game.player.velocity = Vector3.ZERO
	game.player.hp = 10000.0
	game.player.max_hp = 10000.0
	game.player.invulnerable = 0.0
	var enemy: TankActor = game._spawn_tank("Pursuer", Vector3(400, 0.05, 0), 1, false, false, "line")
	enemy._rng.seed = 412
	enemy._turret.rotation = Vector3.ZERO
	var before := float(game.player.hp)
	await frames(720)
	check(enemy._has_contact, "visible tank is genuinely acquired by the production AI")
	check(enemy.position.z < -20.0, "line tank advances over twenty metres toward a spotted target within twelve seconds")
	check(game.player.hp < before, "pursuing enemy also stops and fires real damaging shells")
	print("PURSUIT_TRACE z=%.2f state=%s contact=%s" % [enemy.position.z, enemy.ai_state, enemy._has_contact])
	# Cover then movement must not disclose the hidden player's new coordinates.
	var wall := box(Vector3(400, 4, enemy.position.z - 10), Vector3(30, 8, 2))
	await frames(3)
	var last_seen: Vector3 = enemy._last_seen_position
	game.player.position += Vector3(8, 0, -20)
	await frames(60)
	check(enemy.ai_state == "search" and enemy._search_remaining > 0.0, "losing line of sight starts an active search rather than abandoning combat")
	check(enemy._last_seen_position.is_equal_approx(last_seen), "search uses last observed position, never the hidden player's new position")
	game.pause_game()
	var clock_before := float(enemy._search_remaining)
	var position_before := enemy.position
	await frames(60)
	check(enemy._search_remaining == clock_before and enemy.position.is_equal_approx(position_before), "pause freezes pursuit and search memory")
	game.resume_game()
	wall.free()
	await frames(120)
	check(enemy._has_contact and enemy.ai_state != "patrol", "visible target is reacquired after cover is removed")
	game.player.position = Vector3(400, 0.05, -350)
	await frames(ceili(enemy.search_duration * 60.0) + 5)
	check(not enemy._has_contact and enemy.ai_state == "patrol", "expired search memory returns the enemy to patrol")
	enemy.set_physics_process(false)
	game.player.position = enemy.position - enemy._turret.global_basis.z.normalized() * (enemy.sight_range + 20.0)
	check(not enemy.can_see_target(game.player), "expired contact cannot grant permanent long-range detection")
	enemy.free()
	for kind: String in ["gunner", "sniper", "rocket", "boss"]:
		for shell: Node in get_tree().get_nodes_in_group("projectiles"):
			shell.free()
		enemy = game._spawn_tank("RolePursuer", Vector3(400, 0.05, 0), 1, false, kind == "boss", "line" if kind == "boss" else kind)
		enemy.active = true
		enemy._rng.seed = 412
		enemy._turret.rotation = Vector3.ZERO
		enemy._salvo_clock = 999.0
		game.player.position = Vector3(400, 0.05, -minf(enemy.sight_range - 5.0, enemy._ideal_distance + 40.0))
		before = float(game.player.hp)
		await frames(720)
		check(enemy.position.z < -10.0 and game.player.hp < before, "%s advances between shots and actually damages its spotted target" % kind)
		print("PURSUIT_TRACE %s z=%.2f hit=%s" % [kind, enemy.position.z, game.player.hp < before])
		enemy.free()
	game.free()
	print("ENEMY PURSUIT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
