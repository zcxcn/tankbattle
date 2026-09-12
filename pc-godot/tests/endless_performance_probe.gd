extends Node
## Repeatable CPU hot-path timings; not a substitute for rendered frame pacing.
const Monster = preload("res://actors/giant_monster.gd")
var game: Node3D

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	SaveService._directory = "user://tests/endless_perf_%d" % OS.get_process_id()
	SaveService.reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	add_child(game)
	game.start_endless()
	game.set_process(false)
	game.player.set_physics_process(false)
	game.endless.set_physics_process(false)
	for kind in ["shambler", "forest", "kaiju"]:
		var times: Array[int] = []
		for repeat in 8:
			var monster := Monster.new()
			monster.game = game
			monster.archetype = kind
			game.add_child(monster)
			monster.set_physics_process(false)
			var start := Time.get_ticks_usec()
			monster.receive_damage(1000000, 0)
			times.append(Time.get_ticks_usec() - start)
			monster.free()
			await get_tree().process_frame
		times.sort()
		print("PERF death/%s median_us=%d max_us=%d" % [kind, times[4], times[-1]])
	var ui_start := Time.get_ticks_usec()
	for repeat in 300:
		game.ui.update_snapshot(game.get_ui_snapshot())
	print("PERF playing_ui average_us=%d" % ((Time.get_ticks_usec() - ui_start) / 300))
	game._clear_combat_nodes()
	game.free()
	print("ENDLESS PERFORMANCE PROBE COMPLETE")
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0)
