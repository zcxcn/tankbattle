extends SceneTree
## Persistent weather preferences and in-place changes through the real settings UI.

const Catalog = preload("res://data/weather_catalog.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
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
		await process_frame

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	await frames(3)
	var settings: Node = root.get_node("SettingsService")
	check(settings.weather_mode == 0, "a fresh installation defaults to random weather")
	var observed: Dictionary = {}
	for seed_value in 80:
		var kind := Catalog.resolve(0, seed_value)
		observed[kind] = true
		if not Catalog.KINDS.has(kind) or kind != Catalog.resolve(0, seed_value):
			check(false, "random seeds only yield reproducible supported weather")
			break
	check(observed.size() == 5, "random selection can produce clear, light rain, heavy rain, snow and fog")
	for mode in range(1, 6):
		check(Catalog.resolve(mode, 12) == Catalog.KINDS[mode - 1] and Catalog.resolve(mode, 982) == Catalog.KINDS[mode - 1], "fixed weather ignores random seed: mode %d" % mode)
		settings.weather_mode = mode
		settings.save_settings()
		settings.weather_mode = 0
		settings.load_settings()
		check(settings.weather_mode == mode, "selected weather survives config reload: mode %d" % mode)
	var legacy := ConfigFile.new()
	legacy.set_value("gameplay", "screen_shake", true)
	legacy.save(settings.config_path)
	settings.load_settings()
	check(settings.weather_mode == 0, "an older config without weather migrates to random")
	legacy.set_value("gameplay", "weather", -20)
	legacy.save(settings.config_path)
	settings.load_settings()
	check(settings.weather_mode == 0, "invalid negative stored weather is safely clamped")
	root.get_node("SaveService").set("_directory", "user://tests/weather_settings_%d" % OS.get_process_id())
	root.get_node("SaveService").reset_for_tests()
	var game = load("res://scenes/main/main.tscn").instantiate()
	game.set_meta("weather_seed", 42)
	root.add_child(game)
	game.get_window().focus_exited.disconnect(game._on_focus_lost)
	check(game.current_weather == Catalog.resolve(0, 42), "title preview resolves the default weather once")
	var title_weather: String = game.current_weather
	game.cycle_chassis()
	check(game.current_weather == title_weather, "chassis previews keep the current random weather")
	settings.weather_mode = 1
	game.start_game()
	game.player.hp -= 11.0
	game.objective_progress = 3.0
	game.score = 123
	game.pause_game()
	game.open_settings()
	var original_arena: Node = game.arena
	var original_player: Node = game.player
	var original_enemy: Node = game.enemies[0]
	var original_tracks: Node = game.arena.get_node("TrackMarks")
	var original_position: Vector3 = game.player.global_position
	var original_hp: float = game.player.hp
	for mode in [2, 3, 4, 5, 0, 1]:
		# Emit the actual UI signal rather than calling the arena directly.
		game.ui.setting_requested.emit("weather_mode")
		await frames(2)
		check(settings.weather_mode == mode and game.current_weather == Catalog.resolve(mode, 42), "settings button cycles and applies mode %d immediately" % mode)
		check(game.arena == original_arena and game.player == original_player and game.enemies[0] == original_enemy, "weather changes preserve the live battle actors: mode %d" % mode)
		check(game.player.hp == original_hp and game.player.global_position == original_position and game.score == 123 and game.objective_progress == 3.0, "weather changes preserve position, damage and objective progress: mode %d" % mode)
		check(game.arena.get_node("TrackMarks") == original_tracks and is_equal_approx(original_tracks.get_snapshot().wetness, Catalog.wetness(game.current_weather)), "weather changes update existing trail pool wetness: mode %d" % mode)
		check(game.mode == "settings", "weather selection keeps the paused settings screen open: mode %d" % mode)
	game.ui.update_snapshot(game.get_ui_snapshot())
	var weather_button: Button = game.ui._setting_buttons["weather_mode"]
	check(weather_button.text.contains("晴天"), "settings button names the applied weather")
	check(weather_button.get_node(weather_button.focus_neighbor_right) is Button and weather_button.get_node(weather_button.focus_neighbor_top) is Button, "the odd final settings row has valid controller focus neighbors")
	var selected: String = game.current_weather
	game.ui.setting_requested.emit("radio_volume")
	check(game.current_weather == selected, "audio settings do not reroll weather")
	game._close_settings()
	game.resume_game()
	check(game.current_weather == selected, "closing settings and resuming do not reroll weather")
	settings.weather_mode = 4
	game.selected_mission = 3
	game.start_game()
	check(game.current_weather == "snow" and game.arena.weather_kind == "snow", "a fixed weather preference applies in a different campaign chapter")
	settings.weather_mode = 0
	game.set_meta("weather_seed", 52)
	game.start_game()
	check(game.current_weather == Catalog.resolve(0, 52), "a new deployment resolves random weather from its new seed")
	game.free()
	print("WEATHER_SETTINGS_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)
