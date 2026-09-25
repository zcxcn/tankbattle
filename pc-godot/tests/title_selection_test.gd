extends SceneTree
## Exercises the real title-screen vehicle button path without touching player saves.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		push_error("Title selection test requires -- --test")
		quit(2)
		return
	var saves := root.get_node("SaveService")
	saves.set("_directory", "user://tests/title_selection")
	saves.reset_for_tests()
	var game: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	var original_arena: Node = game.arena
	var original_rig: Node = game._title_rig
	var first_vehicle: Node = game.player
	var previous_chassis: int = game.selected_chassis
	var elapsed: Array[int] = []
	var okay := true
	for index in 3:
		var started := Time.get_ticks_usec()
		game.cycle_chassis()
		elapsed.append(Time.get_ticks_usec() - started)
		okay = okay and game.selected_chassis == (previous_chassis + 1) % 3
		okay = okay and game.mode == "title" and game.arena == original_arena and game._title_rig == original_rig
		okay = okay and is_instance_valid(game.player) and game.player != first_vehicle
		okay = okay and game.player.archetype == ["scout", "line", "heavy"][game.selected_chassis]
		okay = okay and get_nodes_in_group("tanks").size() == 1
		previous_chassis = game.selected_chassis
		first_vehicle = game.player
	game.start_game()
	okay = okay and game.mode == "playing" and game.player.archetype == ["scout", "line", "heavy"][game.selected_chassis]
	game.return_to_menu()
	okay = okay and game.mode == "title" and is_instance_valid(game.player) and get_nodes_in_group("tanks").size() == 1
	print("TITLE_SELECTION_US: %s" % str(elapsed))
	print("TITLE_SELECTION_PASS" if okay else "TITLE_SELECTION_FAIL")
	game.free()
	await process_frame
	quit(0 if okay else 1)
