extends SceneTree
## Production scene weather, lifecycle, authored roof occlusion and GPU budgets.

var passed := 0
var failed := 0
var game: Node


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func freeze() -> void:
	game.set_process(false)
	for tank in get_nodes_in_group("tanks"):
		tank.set_physics_process(false)
	if is_instance_valid(game.arena.weather):
		game.arena.weather.set_process(false)


func frames(amount: int) -> void:
	for frame in amount:
		await process_frame


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		quit(2)
		return
	root.get_node("SaveService").set("_directory", "user://tests/weather_042")
	root.get_node("SaveService").reset_for_tests()
	game = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(game)
	freeze()
	var dry_roughness: float = game.arena._asphalt.roughness
	var dry_sun_energy: float = game.arena.get_node("LowSun").light_energy
	check(not is_instance_valid(game.arena.weather), "dry opening mission allocates no rain, ripple or rain-audio nodes")
	for chapter in 6:
		var mission: Dictionary = preload("res://data/mission_catalog.gd").get_mission(chapter)
		check((mission.weather != "dry") == (chapter in [1, 4]), "only authored harbor chapters 2 and 5 have rain: chapter %d" % (chapter + 1))
	game.selected_mission = 1
	game._show_title_tank()
	freeze()
	var menu_weather: Node = game.arena.weather
	menu_weather._process(1.0)
	check(menu_weather.kind == "light_rain", "mission preview uses selected chapter weather without starting a battle")
	check(menu_weather.elapsed == 0.0 and menu_weather.rain_audio.stream_paused, "mission preview has a still rain frame and does not play ambient audio")
	check(menu_weather.get_snapshot().center.distance_to(game.player.global_position) < 0.01, "title camera tank receives the local weather field after creation")
	game.start_game()
	freeze()
	check(not is_instance_valid(menu_weather), "deploying releases the previous menu weather and its audio player")
	var light: Node = game.arena.weather
	light._process(0.5)
	check(is_equal_approx(light.elapsed, 0.5) and not light.rain_audio.stream_paused, "active combat advances rain, ripple and audio together")
	check(light._rain_material.get_shader_parameter("rain_time") == light.elapsed and light._puddle_material.get_shader_parameter("rain_time") == light.elapsed, "all weather animation uses the same pauseable simulation clock")
	var light_drops: int = light.rain.multimesh.instance_count
	check(light_drops > 0 and light_drops <= light.MAX_DROPS, "light rain has a fixed GPU instance budget")
	check(light.splashes.multimesh.instance_count <= light.MAX_SPLASHES and light.puddles.multimesh.instance_count == light.MAX_PUDDLES, "ground ripples and puddles remain within their fixed budgets")
	check(light.find_children("*", "CollisionObject3D", true, false).is_empty(), "rain adds no individual collision bodies")
	check(light.get_snapshot().draw_batches == 3, "weather consists of three instanced draw batches")
	check(light.sample_roof_height(Vector3(0, 0, 100)) < 0.3, "uncovered avenue receives rain and ground impacts")
	check(light.sample_roof_height(Vector3(-48, 0, -108)) >= 6.0, "rain stops above the first west-side building roof")
	check(light.sample_roof_height(Vector3(-21, 0, -158)) >= 6.0, "static gatehouse collision also occludes rain")
	var roof_volumes: Array = game.arena.get_meta("weather_roofs")
	var canopy_checked := false
	var roofs_valid := true
	for volume: AABB in roof_volumes:
		var center := volume.get_center()
		roofs_valid = roofs_valid and light.sample_roof_height(center) >= volume.end.y - 0.01
		if is_equal_approx(volume.end.y, 3.63):
			canopy_checked = canopy_checked or light.sample_roof_height(center) >= 3.63 - 0.01
	check(roofs_valid, "all authored flat, curved and overhanging roof centres block drops")
	check(canopy_checked, "covered loading bays stop rainfall even without gameplay colliders")
	var puddles_on_roads := true
	for index in light.puddles.multimesh.instance_count:
		var at: Vector3 = light.puddles.multimesh.get_instance_transform(index).origin
		puddles_on_roads = puddles_on_roads and light.sample_roof_height(at) < 0.3
	check(puddles_on_roads, "puddles are placed on outdoor road surfaces, not inside buildings")
	check(game.arena._asphalt.roughness < dry_roughness and game.arena.get_node("LowSun").light_energy < dry_sun_energy, "rain darkens and smooths wet asphalt under softer overcast lighting")
	var original_center: Vector3 = light.get_snapshot().center
	game.player.position += Vector3(96, 0, -100)
	light._process(0.25)
	check(light.get_snapshot().center.distance_to(game.player.global_position) < 0.01 and light.get_snapshot().center.distance_to(original_center) > 90.0, "the bounded weather field follows the player across the larger map")
	check(light.rain.custom_aabb.has_point(game.player.global_position + Vector3.UP * 10), "GPU culling bounds follow the rain field instead of staying at world origin")
	check(light.rain.multimesh.instance_count == light_drops, "travelling cannot grow the rain instance count")
	game.pause_game()
	var before: float = light.elapsed
	light._process(5.0)
	check(light.elapsed == before and light.rain_audio.stream_paused, "pause freezes drops and puddle ripples and pauses rain audio")
	game.resume_game()
	light._process(0.2)
	check(is_equal_approx(light.elapsed, before + 0.2) and not light.rain_audio.stream_paused, "resume continues the existing rain clock without a catch-up jump")
	var stream: AudioStreamWAV = light.rain_audio.stream
	check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end <= stream.data.size() / 2 and stream.loop_begin > 0, "rain audio uses a bounded seamless PCM loop")
	check(light.rain_audio.bus == "SFX" and light.rain_audio.volume_db <= -18.0, "rain respects effects volume and stays below combat sound effects")
	game.selected_mission = 4
	game.start_game()
	freeze()
	check(not is_instance_valid(light), "changing rainy chapters destroys the old field and sound player")
	var heavy: Node = game.arena.weather
	heavy._process(0.2)
	check(heavy.kind == "heavy_rain" and heavy.rain.multimesh.instance_count > light_drops and heavy.rain.multimesh.instance_count <= heavy.MAX_DROPS, "fifth chapter has visibly denser rain without exceeding the maximum")
	check(game.arena._asphalt.roughness <= 0.3, "heavy rain has a wetter road response")
	game.selected_mission = 2
	game.start_game()
	freeze()
	check(not is_instance_valid(heavy) and not is_instance_valid(game.arena.weather), "returning to a dry chapter removes every rain layer and its audio")
	check(game.arena._asphalt.roughness == dry_roughness, "wet-road material changes cannot leak into the next dry chapter")
	game.free()
	await frames(3)
	print("WEATHER_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(self, 0 if failed == 0 else 1)
