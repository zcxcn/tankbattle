class_name TrackedDrive
extends RefCounted
## Spins the source models' real road-wheel geometry without scrolling PBR atlases.
## The mesh partitions are shared between vehicles. Only transforms are animated.

# Measurements are in the normalized source assets' metres, before presentation
# scaling. A narrow cylinder selects the rotating wheel faces/rims while keeping
# suspension arms and hull-mounted fittings stationary.
const WHEEL_LAYOUTS := {
	"challenger2": {
		"material": "laufenwerk", "height": 0.495296, "radius": 0.4093,
		"inner_x": 1.16, "half_width": 1.42,
		"left_z": [2.072360, 1.048265, 0.168626, -0.855438, -1.720070, -2.627849],
		"right_z": [2.058700, 1.051723, 0.155654, -0.869485, -1.734931, -2.636594],
	},
	"kf51": {
		"material": "Panther_KF51_Wheels", "height": 0.4492, "radius": 0.3085,
		"inner_x": 1.13, "half_width": 1.3271,
		"left_z": [2.2986, 1.4825, 0.6615, -0.1351, -0.8910, -1.6428, -2.4443],
		"right_z": [2.2986, 1.4825, 0.6615, -0.1351, -0.8910, -1.6428, -2.4443],
	},
	"kv2": {
		"material": "KV2_Wheels_PBR", "height": 0.353312, "radius": 0.276,
		"inner_x": 1.08, "half_width": 1.2635,
		"left_z": [2.049092, 1.301545, 0.486028, -0.400869, -1.341272, -2.208827],
		"right_z": [2.049092, 1.301545, 0.486028, -0.400869, -1.341272, -2.208827],
	},
}

static var _mesh_cache: Dictionary = {}
var _model: Node3D
var _wheels: Array[Dictionary] = []
var _pending_distance := 0.0
var _pending_yaw := 0.0
var _visual_time := 0.0


func setup(model: Node3D, model_key: String) -> void:
	assert(_model == null, "TrackedDrive.setup must be called only once per vehicle")
	_model = model
	if not WHEEL_LAYOUTS.has(model_key):
		return
	var layout: Dictionary = WHEEL_LAYOUTS[model_key]
	# Snapshot descendants before adding the wheel instances.
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var source := child as MeshInstance3D
		if source.mesh == null:
			continue
		var cache_key := "%s:%s" % [model_key, source.mesh.get_rid().get_id()]
		if not _mesh_cache.has(cache_key):
			_mesh_cache[cache_key] = _partition_wheels(source.mesh, layout)
		var parts: Dictionary = _mesh_cache[cache_key]
		if parts.is_empty():
			continue
		source.mesh = parts["static_mesh"]
		for wheel_data: Dictionary in parts["wheels"]:
			var wheel := MeshInstance3D.new()
			wheel.name = "DriveWheel%02d" % _wheels.size()
			wheel.mesh = wheel_data["mesh"]
			wheel.position = wheel_data["center"]
			source.add_child(wheel)
			_wheels.append({"node": wheel, "radius": float(layout["radius"]),
				"side_x": float(wheel_data["center"].x)})


func step(actual_velocity: Vector3, yaw_delta: float, delta: float, visual_interval := 0.0) -> void:
	if not is_instance_valid(_model) or delta <= 0.0:
		return
	var forward_distance := actual_velocity.dot(-_model.global_basis.z.normalized()) * delta
	_pending_distance += forward_distance
	_pending_yaw += yaw_delta
	_visual_time += delta
	if _visual_time < visual_interval:
		return
	_visual_time = 0.0
	forward_distance = _pending_distance
	yaw_delta = _pending_yaw
	_pending_distance = 0.0
	_pending_yaw = 0.0
	if absf(forward_distance) < 0.000001 and absf(yaw_delta) < 0.000001:
		return
	var world_scale := _model.global_basis.get_scale().x
	for wheel_data: Dictionary in _wheels:
		var wheel: MeshInstance3D = wheel_data["node"]
		# Positive yaw turns left: the right track advances and the left reverses.
		var distance := forward_distance + float(wheel_data["side_x"]) * world_scale * yaw_delta
		var radius := float(wheel_data["radius"]) * world_scale
		wheel.rotation.x = wrapf(wheel.rotation.x - distance / radius, -PI, PI)


func wheel_count() -> int:
	return _wheels.size()


static func _partition_wheels(source: Mesh, layout: Dictionary) -> Dictionary:
	var material_index := -1
	for index in source.get_surface_count():
		var material := source.surface_get_material(index)
		if material != null and material.resource_name == String(layout["material"]):
			material_index = index
			break
	if material_index < 0:
		return {}
	var centers: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var positions: Array = layout["left_z"] if side < 0.0 else layout["right_z"]
		for position_z: float in positions:
			centers.append(Vector3(side * float(layout["half_width"]), float(layout["height"]), position_z))
	var arrays := source.surface_get_arrays(material_index)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(vertices.size())
		for index in vertices.size():
			indices[index] = index
	var grouped: Array[PackedInt32Array] = []
	grouped.resize(centers.size() + 1)
	var select_radius := float(layout["radius"]) + 0.009
	var radius_squared := select_radius * select_radius
	for triangle_start in range(0, indices.size(), 3):
		var a := vertices[indices[triangle_start]]
		var b := vertices[indices[triangle_start + 1]]
		var c := vertices[indices[triangle_start + 2]]
		var midpoint := (a + b + c) / 3.0
		var group := centers.size()
		if absf(midpoint.x) >= float(layout["inner_x"]):
			for index in centers.size():
				var center := centers[index]
				if midpoint.x * center.x <= 0.0:
					continue
				# Whole triangles move rigidly; never bend a connected wheel rim.
				if _radial_distance_squared(a, center) <= radius_squared and _radial_distance_squared(b, center) <= radius_squared and _radial_distance_squared(c, center) <= radius_squared:
					group = index
					break
		for index in range(triangle_start, triangle_start + 3):
			grouped[group].append(indices[index])
	var static_mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		if surface != material_index:
			static_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
			static_mesh.surface_set_material(static_mesh.get_surface_count() - 1, source.surface_get_material(surface))
	if not grouped[-1].is_empty():
		static_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _subset_arrays(arrays, grouped[-1], Vector3.ZERO))
		static_mesh.surface_set_material(static_mesh.get_surface_count() - 1, source.surface_get_material(material_index))
	var wheels: Array[Dictionary] = []
	for index in centers.size():
		if grouped[index].is_empty():
			continue
		var wheel_mesh := ArrayMesh.new()
		wheel_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _subset_arrays(arrays, grouped[index], centers[index]))
		wheel_mesh.surface_set_material(0, source.surface_get_material(material_index))
		wheels.append({"mesh": wheel_mesh, "center": centers[index]})
	return {"static_mesh": static_mesh, "wheels": wheels}


static func _radial_distance_squared(vertex: Vector3, center: Vector3) -> float:
	return Vector2(vertex.y - center.y, vertex.z - center.z).length_squared()


static func _subset_arrays(source: Array, selected: PackedInt32Array, origin: Vector3) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	var remap: Dictionary = {}
	var used: PackedInt32Array = []
	var indices: PackedInt32Array = []
	for old_index in selected:
		if not remap.has(old_index):
			remap[old_index] = used.size()
			used.append(old_index)
		indices.append(remap[old_index])
	result[Mesh.ARRAY_INDEX] = indices
	var vertices: PackedVector3Array = []
	for index in used:
		vertices.append(source[Mesh.ARRAY_VERTEX][index] - origin)
	result[Mesh.ARRAY_VERTEX] = vertices
	for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if source[channel] == null or source[channel].is_empty():
			continue
		var values = source[channel].duplicate()
		values.clear()
		for index in used:
			if channel == Mesh.ARRAY_TANGENT:
				for component in 4:
					values.append(source[channel][index * 4 + component])
			else:
				values.append(source[channel][index])
		result[channel] = values
	return result
