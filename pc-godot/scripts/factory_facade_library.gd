extends RefCounted
## Real CC0 facade geometry. Shared imported meshes retain Godot's generated LODs;
## each building uses MultiMesh batches instead of a node per window or brick panel.

const SOURCE = preload("res://assets/models/environment/polyhaven_factory/modular_factory_facade_1k.gltf")
static var _library: Dictionary = {}
var _placements: Dictionary = {}
var instance_count := 0


func _init() -> void:
	if not _library.is_empty():
		return
	var imported: Node = SOURCE.instantiate()
	_collect(imported)
	imported.free()


func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		_library[String(node.name)] = (node as MeshInstance3D).mesh
	for child in node.get_children():
		_collect(child)


func add_elevation(center: Vector3, width: float, height: float, yaw: float, use_garage := false) -> void:
	var columns := maxi(2, roundi(width / 3.0))
	var floors := maxi(1, roundi(height / 3.0))
	var scale_x := width / float(columns) / 3.0
	var scale_y := height / float(floors) / 3.0
	var orientation := Basis(Vector3.UP, yaw)
	for level in range(floors):
		var column := 0
		while column < columns:
			var right := width * 0.5 - float(column) * 3.0 * scale_x
			var origin := center + orientation * Vector3(right, float(level) * 3.0 * scale_y, 0)
			var transform := Transform3D(orientation * Basis.from_scale(Vector3(scale_x, scale_y, 1.0)), origin)
			if level == 0 and use_garage and column % 4 == 1 and column + 1 < columns:
				_place("wall_door_garage_centered_01", transform)
				_place("door_garage_centered_01", transform)
				column += 2
			elif level == 0 and not use_garage and column == columns / 2:
				_place("wall_door_centered_large_01", transform)
				_place("door_centered_large_01", transform)
				column += 1
			else:
				_place("wall_window_centered_large_01", transform)
				_place("window_centered_large_01", transform)
				column += 1
			if level == floors - 1:
				var cornice := transform
				cornice.origin.y += 3.0 * scale_y
				_place("cornice02_standard_standard_01", cornice)


func _place(key: String, transform: Transform3D) -> void:
	if not _library.has(key):
		push_error("Missing licensed facade component: " + key)
		return
	if not _placements.has(key):
		_placements[key] = []
	_placements[key].append(transform)
	instance_count += 1


func bake(parent: Node3D, prefix: String) -> void:
	for key: String in _placements:
		var mesh: Mesh = _library[key]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = _placements[key].size()
		for index in range(batch.instance_count):
			batch.set_instance_transform(index, _placements[key][index])
		var node := MultiMeshInstance3D.new()
		node.name = prefix + "_" + key
		node.multimesh = batch
		node.visibility_range_end = 175.0
		node.visibility_range_end_margin = 15.0
		node.set_meta("licensed_facade_batch", true)
		node.set_meta("source", "Poly Haven: Modular Factory Facade / CC0")
		parent.add_child(node)
	_placements.clear()
