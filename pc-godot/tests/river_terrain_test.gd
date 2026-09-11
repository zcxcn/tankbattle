extends Node3D
## Engine collision queries validate the river opening, bridge routes and hills.

const River = preload("res://scripts/river_terrain.gd")
var game: Node
var weather_kind := "dry"
var active := false
var passed := 0
var failed := 0


func _ready() -> void:
	call_deferred("run")


func is_combat_running() -> bool:
	return active


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	game = self
	var concrete := StandardMaterial3D.new()
	var asphalt := StandardMaterial3D.new()
	var steel := StandardMaterial3D.new()
	var river := River.new()
	var result := river.build(self, concrete, asphalt, steel)
	river.set_process(false)
	var hill := river.add_hill(self, Vector3(48, -0.05, 108), Vector2(25, 17), 4.6, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(result.bridges.size() == 3, "three independent bridge routes span the river")
	for bridge: Dictionary in result.bridges:
		var route_clear := true
		for x_offset in [-6.0, 0.0, 6.0]:
			for z in [18.5, 23.0, 36.0, 49.0, 53.5]:
				var at: Vector3 = bridge.center + Vector3(x_offset, 0, z - 36.0)
				var hit := ray(at + Vector3.UP * 3, at + Vector3.DOWN * 8)
				route_clear = route_clear and not hit.is_empty() and absf(float(hit.position.y) + 0.05) < 0.015
		check(route_clear, "bridge x=%d has a continuous, level, collision-supported carriageway" % int(bridge.center.x))
		var vehicle := CharacterBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.0, 1.8, 4.2)
		shape.shape = box
		vehicle.add_child(shape)
		add_child(vehicle)
		vehicle.position = Vector3(bridge.center.x, 1.0, 18)
		await get_tree().physics_frame
		check(not vehicle.test_move(vehicle.global_transform, Vector3(0, 0, 36)), "full tank-sized body can cross bridge x=%d without transverse guardrail obstruction" % int(bridge.center.x))
		vehicle.position.z = 36
		check(vehicle.test_move(vehicle.global_transform, Vector3(16, 0, 0)), "bridge x=%d parapet physically prevents driving off the deck" % int(bridge.center.x))
		vehicle.free()
	var open_river := ray(Vector3(48, 4, 36), Vector3(48, -8, 36))
	check(not open_river.is_empty() and absf(float(open_river.position.y) + 6.0) < 0.02, "open river has a real recessed bed six meters below road level")
	check(river.water.find_children("*", "CollisionObject3D", true, false).is_empty(), "water cannot become an invisible bridge over the channel")
	for z in [22.0, 50.0]:
		var blocked := ray(Vector3(48, 0.6, z - 3), Vector3(48, 0.6, z + 3))
		check(not blocked.is_empty(), "riverbank z=%d guards the channel outside bridge mouths" % int(z))
	var bank_hit := ray(Vector3(48, -0.1, 23.2), Vector3(48, -7, 23.2))
	check(not bank_hit.is_empty() and float(bank_hit.position.y) > -3.0, "sloping embankment uses front-facing triangle collision")
	var roof_correct := true
	for bounds: AABB in result.weather_roofs:
		roof_correct = roof_correct and bounds.position.y > 5.7 and bounds.size.z < 0.5
	check(roof_correct, "only narrow overhead steel braces occlude rain; bridge surfaces remain exposed")
	check(result.hills.size() == 3 and river.find_children("DistantRidge*", "MeshInstance3D", true, false).size() == 3, "three continuous mountain ridges form the distant skyline")
	var remote_collision := false
	for background_hill: Node3D in result.hills:
		remote_collision = remote_collision or not background_hill.find_children("*", "CollisionObject3D", true, false).is_empty()
	check(not remote_collision, "distant scenery allocates no unreachable physics bodies")
	var correct_heights := true
	for offset in [Vector2.ZERO, Vector2(8, 4), Vector2(-12, -3), Vector2(16, 6), Vector2(23, 0)]:
		var at := Vector3(48 + offset.x, 0, 108 + offset.y)
		var hit := ray(at + Vector3.UP * 12, at + Vector3.DOWN)
		var expected := -0.05 + River.hill_height(Vector2(at.x, at.z), Vector2(48, 108), Vector2(25, 17), 4.6)
		correct_heights = correct_heights and not hit.is_empty() and absf(float(hit.position.y) - expected) < 0.075
	check(correct_heights, "actual hill triangle collision follows the same smooth heights used by weather and ground queries")
	var normals: PackedVector3Array = hill.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var smooth := true
	for normal in normals:
		smooth = smooth and absf(normal.length() - 1.0) < 0.001 and normal.y > 0.6
	check(smooth, "drivable hill has normalized continuous normals and no vertical or inverted faces")
	check(absf(River.hill_height(Vector2(73, 108), Vector2(48, 108), Vector2(25, 17), 4.6)) < 0.001, "hill edge joins the surrounding street height without a raised seam")
	river._process(0.5)
	check(is_zero_approx(river.elapsed), "river is still while menu or combat pause is active")
	active = true
	river._process(0.5)
	check(is_equal_approx(river.elapsed, 0.5) and is_equal_approx(float(river.water_material.get_shader_parameter("river_time")), 0.5), "flow and ripples follow the gameplay simulation clock")
	active = false
	river._process(1.0)
	check(is_equal_approx(river.elapsed, 0.5), "pausing immediately freezes the already flowing river")
	weather_kind = "heavy_rain"
	river._process(0.0)
	check(is_equal_approx(float(river.water_material.get_shader_parameter("rainfall")), 1.0) and is_equal_approx(float(river.hill_material.get_shader_parameter("wetness")), 1.0), "rain updates both water turbulence and wet hill PBR")
	weather_kind = "snow"
	river._process(0.0)
	check(is_equal_approx(float(river.hill_material.get_shader_parameter("snow_amount")), 1.0) and is_zero_approx(float(river.hill_material.get_shader_parameter("wetness"))), "snow covers upward hill slopes and clears the rain wetness")
	weather_kind = "dry"
	river._process(0.0)
	check(is_zero_approx(float(river.hill_material.get_shader_parameter("snow_amount"))) and is_zero_approx(float(river.water_material.get_shader_parameter("rainfall"))), "returning to dry weather clears both snow cover and rain turbulence")
	print("River terrain: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 1 if failed > 0 else 0)
