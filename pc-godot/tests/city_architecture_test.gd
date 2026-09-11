extends Node
## Real generated geometry, collision, licensed PBR and merged draw budgets.

var passed := 0
var failed := 0

func _ready() -> void:
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
		await get_tree().physics_frame

func triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		count += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count

func trace(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_viewport().world_3d.direct_space_state.intersect_ray(query)

func inspect_shells(tower: Node3D) -> Dictionary:
	var result := {"shells": 0, "outward": true, "tops_up": true,
		"base_y": INF, "roof_y": -INF, "meshes": 0, "triangles": 0, "merged": 0}
	for child in tower.get_children():
		if not child is MeshInstance3D:
			continue
		result.meshes += 1
		result.triangles += triangle_count(child.mesh)
		if child.get_meta("static_detail_batch", false):
			result.merged += 1
			continue
		result.shells += 1
		var bounds: AABB = child.transform * child.mesh.get_aabb()
		result.base_y = minf(result.base_y, bounds.position.y)
		result.roof_y = maxf(result.roof_y, bounds.end.y)
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			if absf(normals[i].y) > 0.5:
				result.tops_up = result.tops_up and normals[i].y > 0.999
			else:
				var radial := Vector3(vertices[i].x, 0, vertices[i].z)
				result.outward = result.outward and normals[i].dot(radial) > 0.1
	return result

func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	var script: Script = load("res://scripts/city_architecture.gd")
	var city: RefCounted = script.new()
	var container := Node3D.new()
	add_child(container)
	var towers: Array[Node3D] = []
	var summaries: Array[Dictionary] = []
	var previous_pieces := 0
	for variant in 3:
		var tower: Node3D = city.build(container, Vector3(variant * 90, 0, 0), 36.0, 23.0, 38.0 + variant * 13.0, variant)
		towers.append(tower)
		var summary := inspect_shells(tower)
		summaries.append(summary)
		check(summary.shells == 4, "variant %d has a podium and three stepped solid volumes" % variant)
		check(summary.outward, "variant %d exterior wall normals face out through all chamfered sides" % variant)
		check(summary.tops_up, "variant %d roof normals face up without wall smoothing" % variant)
		check(absf(summary.base_y) < 0.001 and summary.roof_y > 35.0, "variant %d is grounded with a complete high-rise shell" % variant)
		check(summary.meshes <= 12 and summary.merged >= 3 and summary.merged <= 8,
			"variant %d merges facade fittings into bounded material batches" % variant)
		check(summary.triangles < 60000 and city.piece_count - previous_pieces > 400 and city.piece_count - previous_pieces < 5000,
			"variant %d preserves modeled details within the geometry budget" % variant)
		previous_pieces = city.piece_count
		var colliders := tower.find_children("*", "CollisionShape3D", true, false)
		var fitted := colliders.size() == 4
		for collider: CollisionShape3D in colliders:
			fitted = fitted and collider.shape is BoxShape3D and collider.get_parent().collision_layer == 1
		check(fitted, "variant %d uses four solid conservative shell colliders" % variant)
		print("CITY_BUDGET variant=%d meshes=%d triangles=%d" % [variant, summary.meshes, summary.triangles])
	await frames(3)
	for variant in towers.size():
		var origin: Vector3 = towers[variant].global_position
		var wall_hit := trace(origin + Vector3(-30, 2, 0), origin + Vector3(30, 2, 0))
		check(not wall_hit.is_empty() and wall_hit.normal.x < -0.99,
			"variant %d blocks horizontal projectiles at street height" % variant)
		var roof_hit := trace(origin + Vector3(0, 110, 0), origin + Vector3(0, 0.1, 0))
		check(not roof_hit.is_empty() and absf(roof_hit.position.y - summaries[variant].roof_y) < 0.01 and roof_hit.normal.y > 0.99,
			"variant %d roof collision follows the visible top shell" % variant)
		check(trace(origin + Vector3(24, 2, -25), origin + Vector3(24, 2, 25)).is_empty(),
			"variant %d leaves the adjacent street clear" % variant)
	var roofs_before: int = city.roofs.size()
	var distant: Node3D = city.build(container, Vector3(350, 0, 0), 30, 24, 88, 2, false)
	check(distant.find_children("*", "CollisionShape3D", true, false).is_empty() and city.roofs.size() == roofs_before,
		"distant skyline adds no gameplay collision or false rain shelter")
	var concrete: ORMMaterial3D = city.concrete
	check(concrete.albedo_texture.resource_path.ends_with("concrete_tile_facade_diff_1k.jpg")
		and concrete.normal_texture.resource_path.ends_with("concrete_tile_facade_nor_gl_1k.jpg")
		and concrete.orm_texture.resource_path.ends_with("concrete_tile_facade_arm_1k.jpg"),
		"city walls use the licensed albedo, OpenGL normal and packed PBR textures")
	check(concrete.uv1_world_triplanar and concrete.uv1_triplanar and absf(concrete.uv1_scale.x - 1.0 / 2.1) < 0.0001
		and concrete.normal_scale > 0.0 and concrete.normal_scale <= 0.65,
		"world-scale facade mapping retains physical tile size and restrained normals")
	check(city.stone.albedo_texture == concrete.albedo_texture and city.stone.orm_texture == concrete.orm_texture,
		"building color variants share texture resources")
	container.free()
	await frames(2)
	verify_asset_provenance()
	verify_rocks()
	await verify_arena_integration()
	print("City architecture tests: %d passed, %d failed" % [passed, failed])
	await load("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)

func verify_asset_provenance() -> void:
	for directory in ["polyhaven_rock09", "polyhaven_concrete_facade", "polyhaven_aerial_grass"]:
		var base: String = "res://assets/models/environment/" + directory + "/"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "download-manifest.json"))
		var hashes_valid: bool = manifest.get("license", "") == "CC0-1.0"
		var textures_valid := true
		for record: Dictionary in manifest.get("files", []):
			var path: String = base + record.path
			hashes_valid = hashes_valid and FileAccess.get_sha256(path) == record.sha256
			if path.ends_with(".jpg"):
				var texture: Texture2D = load(path)
				textures_valid = textures_valid and texture.get_size() == Vector2(1024, 1024)
		check(hashes_valid, directory + " source bytes match the recorded official download hashes")
		check(textures_valid, directory + " limits all PBR maps to 1K")

func verify_rocks() -> void:
	var scene: PackedScene = load("res://assets/models/environment/polyhaven_rock09/rock_09_normalized.tscn")
	var first: Node3D = scene.instantiate()
	var second: Node3D = scene.instantiate()
	add_child(first)
	add_child(second)
	var mesh_a: MeshInstance3D = first.get_node("Scan/rock_09_LOD0")
	var mesh_b: MeshInstance3D = second.get_node("Scan/rock_09_LOD0")
	var bounds := mesh_a.global_transform * mesh_a.get_aabb()
	check(absf(bounds.position.y) < 0.0001 and bounds.size.is_equal_approx(Vector3(0.511738, 0.227274, 1.0)),
		"the scanned rock is ground aligned with a one metre longest axis")
	check(mesh_a.mesh == mesh_b.mesh and mesh_a.get_active_material(0) == mesh_b.get_active_material(0)
		and triangle_count(mesh_a.mesh) < 15000, "rock instances share scanned geometry and PBR within budget")
	first.free()
	second.free()

func verify_arena_integration() -> void:
	var arena: Node3D = load("res://scenes/missions/industrial_arena.gd").new()
	arena.set("weather_kind", "dry")
	add_child(arena)
	await frames(2)
	var city_count := 0
	var playable_count := 0
	var rock_count := 0
	var rock_meshes: Dictionary = {}
	for child in arena.get_children():
		if child.get_meta("city_building", false):
			city_count += 1
			if not child.find_children("*", "CollisionShape3D", true, false).is_empty():
				playable_count += 1
		if child.get_meta("licensed_rock", false):
			rock_count += 1
			var mesh: MeshInstance3D = child.get_node("Scan/rock_09_LOD0")
			rock_meshes[mesh.mesh.get_instance_id()] = true
	check(city_count >= 12 and playable_count >= 2, "the real arena contains both skyline and reachable solid city towers")
	check(rock_count >= 8 and rock_meshes.size() == 1, "the real riverbank reuses the licensed scanned rock mesh")
	var landscape: Node3D = arena.get("landscape")
	var hill: ShaderMaterial = landscape.get("hill_material")
	var grass: Texture2D = hill.get_shader_parameter("grass_albedo")
	check(grass.resource_path.ends_with("aerial_grass_rock_diff_1k.jpg") and hill.get_shader_parameter("grass_normal") is Texture2D
		and hill.get_shader_parameter("grass_arm") is Texture2D, "actual hills bind all three real grass PBR maps")
	arena.free()
	await frames(2)
