extends "res://scripts/river_terrain.gd"
## Continuous rolling grassland with an actual river opening and three bridges.
const Layout = preload("res://data/woodland_layout.gd")
var _surface_weather := ""

func build(target: Node3D, concrete: Material, asphalt: Material, metal: Material) -> Dictionary:
	var result := super.build(target, concrete, asphalt, metal)
	for limits: Vector2 in [Vector2(-192, 22), Vector2(50, 192)]:
		_build_heightfield(limits)
	_surface_weather = ""
	_sync_weather()
	return result

func _build_channel(_concrete: Material) -> void:
	super._build_channel(hill_material)
	water.mesh.size.x = 1800.0
	_box(self, "DistantStreamBed", Vector3(0, -6.4, 36), Vector3(1800, 0.1, 28), _material(Color("3b4134"), 0.98))
	for drain in find_children("QuayDrain*", "MeshInstance3D", true, false):
		drain.free()

func _build_bank_rails(_concrete: Material, _metal: Material) -> void:
	# Timber barriers retain the safe bridge-only crossing contract.
	var timber := _material(Color("645844"), 0.94)
	var spans := [Vector2(-144, -106), Vector2(-86, -11), Vector2(11, 86), Vector2(106, 144)]
	for z in [21.5, 50.5]:
		for span: Vector2 in spans:
			_box(self, "TimberBankGuard", Vector3((span.x + span.y) * 0.5, 0.65, z), Vector3(span.y - span.x, 0.32, 0.35), timber, true)
			for x in range(int(span.x), int(span.y) + 1, 4):
				_box(self, "TimberPost", Vector3(x, 0.42, z), Vector3(0.3, 1.1, 0.3), timber)

func _build_heightfield(limits: Vector2) -> void:
	var x_count := 144
	var z_count := int((limits.y - limits.x) / 2.0)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	for row in z_count + 1:
		for col in x_count + 1:
			var x := -144.0 + col * 2.0
			var z := limits.x + row * 2.0
			var dx := (Layout.height_at(x + 0.1, z) - Layout.height_at(x - 0.1, z)) / 0.2
			var dz := (Layout.height_at(x, z + 0.1) - Layout.height_at(x, z - 0.1)) / 0.2
			var normal := Vector3(-dx, 1, -dz).normalized()
			var tangent := (Vector3.RIGHT - normal * normal.x).normalized()
			vertices.append(Vector3(x, Layout.height_at(x, z), z))
			normals.append(normal)
			uvs.append(Vector2(x, z) * 0.16)
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, 1.0]))
	for row in z_count:
		for col in x_count:
			var i := row * (x_count + 1) + col
			indices.append_array(PackedInt32Array([i, i + 1, i + x_count + 1, i + 1, i + x_count + 2, i + x_count + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ground := MeshInstance3D.new()
	ground.name = "WoodlandHeightfield"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ground.mesh = mesh
	var paths := hill_material.duplicate() as ShaderMaterial
	paths.set_shader_parameter("woodland_paths", true)
	ground.material_override = paths
	ground.set_meta("woodland_surface", true)
	add_child(ground)
	_trimesh_body(ground)

func _prepare_hill_material() -> void:
	super._prepare_hill_material()
	hill_material.set_shader_parameter("turf_tint", Vector3(0.68, 0.97, 0.62))

func _build_background_ground() -> void:
	super._build_background_ground()
	for ground in get_children():
		if ground.name in ["NorthernGrassPlain", "SouthernGrassPlain"]:
			var northern := ground.name == "NorthernGrassPlain"
			ground.mesh.size = Vector2(6000, 3000)
			ground.position.z = 22.0 - 1500.0 if northern else 50.0 + 1500.0

func _sync_weather() -> void:
	super._sync_weather()
	if _surface_weather == _weather_kind:
		return
	_surface_weather = _weather_kind
	for ground in get_children():
		if ground.has_meta("woodland_surface"):
			for parameter in ["wetness", "snow_amount"]:
				ground.material_override.set_shader_parameter(parameter, hill_material.get_shader_parameter(parameter))
