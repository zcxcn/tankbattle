extends SceneTree
## Run with Godot --headless --path pc-godot --script res://tests/tracked_drive_test.gd.

const Drive = preload("res://scripts/tracked_drive.gd")
const ASSETS := {
	"challenger2": "res://assets/models/realistic/challenger2/challenger2.glb",
	"kf51": "res://assets/models/realistic/kf51/kf51_panther.glb",
	"kv2": "res://assets/models/realistic/kv2/kv2_boss.glb",
}
const EXPECTED_CHECKS := 33
var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: " + message)
	else:
		_failed += 1
		push_error("FAIL: " + message)


func _run_all() -> void:
	for model_key: String in ASSETS:
		_test_model(model_key)
	if _passed + _failed != EXPECTED_CHECKS:
		_failed += 1
		push_error("Tracked-drive runner stopped before all checks completed")
	print("\nTracked drive: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_model(model_key: String) -> void:
	var scene: PackedScene = load(ASSETS[model_key])
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	model.scale = Vector3.ONE * 0.7
	var before := _geometry_snapshot(model)
	var driver := Drive.new()
	driver.setup(model, model_key)
	var after := _geometry_snapshot(model)
	_check(driver.wheel_count() == (14 if model_key == "kf51" else 12), model_key + " has a full set of road wheels")
	_check(before["triangles"] == after["triangles"], model_key + " preserves every triangle")
	# Spatial moments catch displaced or duplicated geometry even if face counts
	# happen to match. Evaluate the assembled vehicle before any wheel rotation.
	_check(before["mean"].distance_to(after["mean"]) < 0.00001 and before["second_moment"].distance_to(after["second_moment"]) < 0.00001,
		model_key + " preserves assembled geometry positions")
	_check(before["materials"] == after["materials"], model_key + " preserves original PBR resources and face assignments")

	driver.step(Vector3(0, 0, -2), 0.0, 0.04)
	var forward_ok := true
	for data: Dictionary in driver._wheels:
		forward_ok = forward_ok and data["node"].rotation.x < 0.0
	_check(forward_ok, model_key + " rolls forward in the direction of travel")
	driver.step(Vector3(0, 0, 2), 0.0, 0.04)
	var reverse_ok := true
	for data: Dictionary in driver._wheels:
		reverse_ok = reverse_ok and absf(data["node"].rotation.x) < 0.00001
	_check(reverse_ok, model_key + " reverses the same distance without drift")

	driver.step(Vector3.ZERO, 0.03, 0.04)
	var turn_ok := true
	var turn_rotations: Array[float] = []
	for data: Dictionary in driver._wheels:
		turn_ok = turn_ok and data["node"].rotation.x * float(data["side_x"]) < 0.0
		turn_rotations.append(data["node"].rotation.x)
	_check(turn_ok, model_key + " counter-rotates left and right wheels while turning in place")
	driver.step(Vector3.ZERO, 0.0, 0.5)
	var stopped_ok := true
	for index in driver._wheels.size():
		stopped_ok = stopped_ok and is_equal_approx(driver._wheels[index]["node"].rotation.x, turn_rotations[index])
	_check(stopped_ok, model_key + " leaves wheels still when the hull stops")

	var cache_count: int = Drive._mesh_cache.size()
	var second := scene.instantiate() as Node3D
	root.add_child(second)
	var second_driver := Drive.new()
	second_driver.setup(second, model_key)
	_check(Drive._mesh_cache.size() == cache_count, model_key + " reuses the partition cache for another instance")
	var shared := second_driver.wheel_count() == driver.wheel_count()
	var independent := true
	for index in mini(second_driver.wheel_count(), driver.wheel_count()):
		shared = shared and second_driver._wheels[index]["node"].mesh == driver._wheels[index]["node"].mesh
		independent = independent and is_zero_approx(second_driver._wheels[index]["node"].rotation.x)
	_check(shared, model_key + " shares extracted wheel meshes between vehicles")
	_check(independent, model_key + " keeps wheel transforms independent between vehicles")
	model.free()
	second.free()


func _geometry_snapshot(model: Node3D) -> Dictionary:
	var triangles := 0
	var vertex_count := 0
	var sums := PackedFloat64Array([0.0, 0.0, 0.0])
	var squares := PackedFloat64Array([0.0, 0.0, 0.0])
	var materials: Dictionary = {}
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var transform := model.global_transform.affine_inverse() * node.global_transform
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in vertices.size():
					indices[index] = index
			var surface_triangles: int = indices.size() / 3
			triangles += surface_triangles
			var material: Material = node.mesh.surface_get_material(surface)
			# Identity verifies that all textures, normal maps and PBR settings are
			# retained. Per-material face counts catch reassigned surfaces as well.
			var material_id := material.get_rid().get_id()
			materials[material_id] = int(materials.get(material_id, 0)) + surface_triangles
			for index in indices:
				var point := transform * vertices[index]
				for axis in 3:
					sums[axis] += point[axis]
					squares[axis] += float(point[axis]) * float(point[axis])
			vertex_count += indices.size()
	return {
		"triangles": triangles, "materials": materials,
		"mean": Vector3(sums[0], sums[1], sums[2]) / vertex_count,
		"second_moment": Vector3(squares[0], squares[1], squares[2]) / vertex_count,
	}
