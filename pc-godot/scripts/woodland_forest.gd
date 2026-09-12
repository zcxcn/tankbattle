extends RefCounted
## Shared imported tree meshes, spatially batched; only trunks collide.
const Layout = preload("res://data/woodland_layout.gd")
const TREE_PATH := "res://assets/models/environment/polyhaven_tree_small02/woodland_tree.glb"

func build(arena: Node3D) -> void:
	var source: Node3D = load(TREE_PATH).instantiate()
	var parts: Array[MeshInstance3D] = []
	for node in source.find_children("*", "MeshInstance3D", true, false):
		parts.append(node)
	for part in parts:
		for surface in part.mesh.get_surface_count():
			var material := part.mesh.surface_get_material(surface) as StandardMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.25
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 413
	var trees: Array[Vector3] = []
	var cells: Dictionary = {}
	for attempt in 1800:
		if trees.size() >= 160:
			break
		var x := rng.randf_range(-135, 135)
		var z := rng.randf_range(-180, 180)
		if (z > 8 and z < 64) or Layout.road_distance(x, z) < 12.0:
			continue
		var at := Layout.ground(Vector3(x, 0, z))
		var clear := true
		for tree in trees:
			if Vector2(at.x - tree.x, at.z - tree.z).length_squared() < 100.0:
				clear = false
				break
		if not clear:
			continue
		trees.append(at)
		var scale := rng.randf_range(0.75, 1.3)
		var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(scale * rng.randf_range(0.85, 1.12), scale, scale))
		var cell := Vector2i(floori(x / 64), floori(z / 64))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(Transform3D(basis, at - Vector3.UP * 0.1))
		var trunk := StaticBody3D.new()
		trunk.name = "WoodlandTrunk"
		trunk.position = at + Vector3.UP * (3.0 * scale)
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.55 * scale
		cylinder.height = 6.0 * scale
		collision.shape = cylinder
		trunk.add_child(collision)
		arena.add_child(trunk)
	for cell in cells:
		for part in parts:
			var batch := MultiMeshInstance3D.new()
			batch.name = "WoodlandCanopy"
			# Tiny disconnected leaf clusters need a stricter screen-error budget
			# than solid buildings, otherwise distant crowns turn into bare sticks.
			batch.lod_bias = 6.0
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.mesh = part.mesh
			instances.instance_count = cells[cell].size()
			var local := part.transform
			var parent := part.get_parent() as Node3D
			while parent != null:
				local = parent.transform * local
				parent = parent.get_parent() as Node3D
			for index in cells[cell].size():
				instances.set_instance_transform(index, cells[cell][index] * local)
			batch.multimesh = instances
			arena.add_child(batch)
	arena.set_meta("woodland_tree_count", trees.size())
	arena.set_meta("woodland_tree_positions", trees)
	source.free()
