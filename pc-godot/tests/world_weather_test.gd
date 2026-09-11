extends Node3D
## Actual campaign weather volumes on river, road bridges, curved hills and towers.

const ArenaScene = preload("res://scenes/missions/industrial_arena.gd")
var passed := 0
var failed := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	for chapter in 6:
		var arena: Node3D = ArenaScene.new()
		arena.mission_index = chapter
		arena.weather_kind = "dry"
		add_child(arena)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var prefix := "chapter %d " % (chapter + 1)
		_check(arena.has_method("get_surface_height"), prefix + "provides actual terrain elevation to weather")
		if not arena.has_method("get_surface_height"):
			arena.free()
			continue
		arena.set_weather_kind("heavy_rain")
		var rain: Node3D = arena.weather
		rain.set_process(false)
		var water := Vector3(48, 0, 36)
		var water_height: float = arena.get_surface_height(water)
		_check(water_height < -3.0 and absf(rain.sample_surface_height(water) - water_height) < 0.03, prefix + "height texture samples the recessed river at its visible water surface")
		_check(absf(rain.sample_roof_height(water) - water_height) < 0.03, prefix + "open river has no invisible roof or ground sheet at road height")
		_check(rain.splashes.custom_aabb.has_point(Vector3(water.x, water_height + 0.022, water.z)), prefix + "rain and ripple culling includes the lowered river")
		var bridges_receive_rain := true
		for x in [-96.0, 0.0, 96.0]:
			var bridge := Vector3(x, 0, 36)
			bridges_receive_rain = bridges_receive_rain and absf(rain.sample_surface_height(bridge) - float(arena.get_surface_height(bridge))) < 0.03 and rain.sample_surface_height(bridge) > -0.1
		_check(bridges_receive_rain, prefix + "all three bridge decks remain distinct from the river in the weather map")
		var hill := Vector3(48, 0, 108)
		var slope := Vector3(59, 0, 108)
		var hill_height: float = arena.get_surface_height(hill)
		var slope_height: float = arena.get_surface_height(slope)
		_check(hill_height > 4.0 and slope_height > 0.15 and hill_height > slope_height + 0.1, prefix + "driveable hill has a curved elevated surface")
		_check(absf(rain.sample_surface_height(hill) - hill_height) < 0.05 and absf(rain.sample_surface_height(slope) - slope_height) < 0.05, prefix + "weather follows the hill summit and descending slope instead of a flat bounding box")
		_check(absf(rain.sample_roof_height(slope) - rain.sample_surface_height(slope)) < 0.03, prefix + "an exposed hillside receives precipitation at its own elevation")
		var tall_roofs := 0
		var towers_block := true
		for roof: AABB in arena.get_meta("weather_roofs", []):
			if roof.end.y < 30.0:
				continue
			tall_roofs += 1
			towers_block = towers_block and rain.sample_roof_height(roof.get_center()) >= roof.end.y - 0.01
		_check(tall_roofs >= 2 and towers_block, prefix + "multiple city tower roofs actually occlude rainfall")
		# DummyRenderingServer has no transform readback; inspect the exact CPU
		# submissions used by the same renderer in normal play instead.
		var supported_puddles: bool = rain.puddle_transforms.size() == rain.puddles.multimesh.instance_count
		for index in rain.puddle_transforms.size():
			var pose: Transform3D = rain.puddle_transforms[index]
			var level: float = arena.get_surface_height(pose.origin)
			if absf(pose.origin.y - level - 0.008) >= 0.002 and supported_puddles:
				print("Puddle height mismatch ", index, " position ", pose.origin, " actual surface ", level)
			supported_puddles = supported_puddles and absf(pose.origin.y - level - 0.008) < 0.002
			for x in [-0.5, 0.0, 0.5]:
				for z in [-0.5, 0.0, 0.5]:
					var at := pose * Vector3(x, 0, z)
					var height: float = arena.get_surface_height(at)
					var supported: bool = height > -0.2 and absf(height - level) <= 0.08 and rain.sample_roof_height(at) < height + 0.3
					if not supported and supported_puddles:
						print("Unsupported puddle ", index, " at ", at, " level ", level, " ground ", height, " roof ", rain.sample_roof_height(at))
					supported_puddles = supported_puddles and supported
		_check(supported_puddles, prefix + "all rotated puddle footprints rest on exposed level land or bridge decks")
		var river_puddle := Transform3D(Basis.IDENTITY.scaled(Vector3(4, 1, 3)), water)
		_check(not rain._puddle_supported(river_puddle), prefix + "water cannot receive a floating road puddle")
		_check(rain.puddles.multimesh.instance_count == 84 and rain.rain.multimesh.instance_count <= 3200 and rain.splashes.multimesh.instance_count <= 260, prefix + "terrain awareness does not increase the precipitation instance budgets")
		_check(rain._rain_material.get_shader_parameter("surface_height") == rain.surface_texture and rain._splash_material.get_shader_parameter("surface_height") == rain.surface_texture, prefix + "rain streaks and slope-following impacts use the same elevation texture")
		arena.set_weather_kind("snow")
		var snow: Node3D = arena.weather
		snow.set_process(false)
		_check(not is_instance_valid(rain) and snow._snow_material.get_shader_parameter("surface_height") == snow.surface_texture and absf(snow.sample_surface_height(water) - water_height) < 0.03, prefix + "switching to snow retains the real river landing height and releases rain")
		_check(snow.snow.multimesh.instance_count <= 2300 and absf(snow.sample_roof_height(slope) - slope_height) < 0.05, prefix + "snow follows exposed hill contours within its original fixed budget")
		arena.set_weather_kind("dry")
		_check(not is_instance_valid(snow) and not is_instance_valid(arena.weather), prefix + "dry weather frees the new maps with their weather root")
		arena.free()
		await get_tree().process_frame
	print("WORLD_WEATHER_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
