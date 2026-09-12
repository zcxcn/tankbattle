extends Node
## Drive the production scheduler through repeated kills, without begin_wave().
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

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	SaveService._directory = "user://tests/endless_waves_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.start_endless()
	game.set_process(false)
	game.player.set_physics_process(false)
	game.player._camera_pivot.handle_look(Vector2(0, -10000))
	check(game.player._camera_pivot.pitch > 0.8 and game.player._camera_pivot.pitch <= 0.85, "endless camera can look up to city-scale monsters without flipping")
	var director: Node = game.endless
	director.set_physics_process(false)
	# Advance actual physics clocks deterministically, with real actors and deaths.
	var kinds: Dictionary = {}
	var clear_count := 0
	var clear_elapsed := 0.0
	var previous_wave := 0
	var waiting := false
	for tick in 2400:
		director._physics_process(0.1)
		if director.wave != previous_wave:
			if waiting:
				check(clear_elapsed <= 6.2, "cleared wave %d advances within six seconds" % previous_wave)
			previous_wave = director.wave
			waiting = false
			clear_elapsed = 0.0
		for monster: Node3D in director.monsters.duplicate():
			kinds[monster.archetype] = true
			monster.receive_damage(1000000, 0)
		if director.wave > 0 and director.pending == 0 and director.monsters.is_empty():
			if not waiting:
				clear_count += 1
			waiting = true
			clear_elapsed += 0.1
		await get_tree().process_frame
		if director.wave >= 6:
			break
	check(director.wave >= 6 and clear_count >= 5, "production scheduler autonomously reaches wave six after clearing successive waves")
	check(game.mode == "playing", "empty waves never trigger campaign victory or stop combat")
	check(kinds.size() == 9, "all nine enemy archetypes actually enter scheduled waves")
	check(director.corpses.size() <= director.MAX_CORPSES, "accelerated clearing keeps retained corpses bounded")
	# Backlog is not a cleared wave, even when no live monsters remain.
	director.monsters.clear()
	director.pending = 3
	director.wave_clock = 40.0
	director._clear_announced = false
	director.spawn_clock = 0.0
	director._physics_process(0.1)
	check(director.wave_clock > 39.0 and director.pending == 2, "pending reinforcement is spawned instead of incorrectly advancing the wave")
	var clock_before := float(director.wave_clock)
	game.pause_game()
	director._physics_process(20.0)
	check(director.wave_clock == clock_before, "workshop pause preserves countdown")
	game.resume_game()
	# A large monster must be able to reach and damage the actual shelter wall.
	for monster: Node3D in director.monsters.duplicate():
		monster.receive_damage(1000000, 0)
	director.pending = 1
	director._elite_pending = 0
	director._kaiju_pending = 1
	var kaiju: Node3D = director.spawn_monster()
	check(kaiju != null and kaiju.height == 60.0, "scheduled kaiju is sixty metres tall")
	if kaiju != null:
		kaiju.position = Vector3(0, 0.1, 100)
		game.player.position = Vector3(40, 0.1, 10)
		var base_before := float(director.base_hp)
		for frame in 1000:
			await get_tree().physics_frame
			if director.base_hp < base_before:
				break
		check(director.base_hp < base_before, "sixty-metre collider walks to the real shelter and completes its melee attack")
		check(kaiju.global_position.y > -0.2 and kaiju.global_position.y < 1.0, "sixty-metre monster remains supported by the road")
		kaiju.receive_damage(1000000, 0)
		kaiju.set_physics_process(false)
		kaiju._tick_corpse(4.5)
		check(kaiju._death_impact and absf(kaiju._visual.rotation.z) > 1.4, "kaiju collapses onto its flank with delayed full-body ground impact")
		kaiju._tick_corpse(22.0)
		var all_fade := true
		for mesh: MeshInstance3D in kaiju._skins:
			all_fade = all_fade and mesh.transparency > 0.0
		check(all_fade, "all reptile body parts fade together after death")
	game._clear_combat_nodes()
	game.free()
	print("ENDLESS WAVES: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
