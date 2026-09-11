extends Node3D
## A traversable three-bridge river, engineered banks and continuous heightfields.
## Geometry and collision share the same hill mesh; water is purely visual.

const WATER_SHADER = preload("res://assets/shaders/river_water.gdshader")
const HILL_SHADER = preload("res://assets/shaders/rolling_terrain.gdshader")
const RIVER_CENTER := 36.0
const RIVER_MIN_Z := 22.0
const RIVER_MAX_Z := 50.0
const WATER_HEIGHT := -3.2
const DECK_HEIGHT := -0.05
const BRIDGE_CENTERS := [-96.0, 0.0, 96.0]
const HILL_STEPS := 48

var game: Node
var arena: Node3D
var elapsed := 0.0
var water: MeshInstance3D
var water_material: ShaderMaterial
var hill_material: ShaderMaterial
var _weather_kind := ""
var _weather_roofs: Array[AABB] = []
var _bridges: Array[Dictionary] = []
var _hills: Array[Node3D] = []


func build(target: Node3D, concrete: Material, asphalt: Material, metal: Material) -> Dictionary:
	arena = target
	game = arena.get("game")
	name = "RiverTerrain"
	if get_parent() == null:
		arena.add_child(self)
	_prepare_hill_material()
	_build_channel(concrete)
	var lane_paint := _material(Color("d8c793"), 0.78)
	for center_x: float in BRIDGE_CENTERS:
		_build_bridge(center_x, 18.0 if is_zero_approx(center_x) else 16.0, concrete, asphalt, metal, lane_paint)
	_build_bank_rails(concrete, metal)
	_build_background_ground()
	_hills.append(add_hill(self, Vector3(-285.0, -0.35, -20.0), Vector2(130.0, 190.0), 64.0, false))
	_hills.append(add_hill(self, Vector3(0.0, -0.35, -470.0), Vector2(280.0, 150.0), 80.0, false))
	_hills.append(add_hill(self, Vector3(35.0, -0.35, 375.0), Vector2(250.0, 140.0), 55.0, false))
	_bake_static_details()
	_sync_weather()
	set_meta("river_bounds", AABB(Vector3(-144, -6, RIVER_MIN_Z), Vector3(288, 6, RIVER_MAX_Z - RIVER_MIN_Z)))
	set_meta("bridge_count", _bridges.size())
	return {"root": self, "weather_roofs": _weather_roofs, "ground_surfaces": [hill_material],
		"bridges": _bridges, "hills": _hills, "water": water}


func _build_background_ground() -> void:
	# Continue the same grass material to the horizon, keeping the full river
	# opening uncovered so the background cannot become a slab over its water.
	for limits: Vector2 in [Vector2(-900.0, RIVER_MIN_Z), Vector2(RIVER_MAX_Z, 900.0)]:
		var ground := MeshInstance3D.new()
		ground.name = "NorthernGrassPlain" if limits.x < 0.0 else "SouthernGrassPlain"
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(1800.0, limits.y - limits.x)
		ground.mesh = mesh
		ground.material_override = hill_material
		ground.position = Vector3(0.0, -0.38, (limits.x + limits.y) * 0.5)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)


func _bake_static_details() -> void:
	var builders: Dictionary = {}
	var counts: Dictionary = {}
	var module_inverse := global_transform.affine_inverse()
	var source_count := 0
	for source: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		# A deck, pier or parapet owns its collision body and must stay intact.
		# Water, hills and plains have other mesh types; only leaf fittings bake.
		if not source.mesh is BoxMesh or source.get_child_count() > 0:
			continue
		var material: Material = source.get_active_material(0)
		if not builders.has(material):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builders[material] = builder
			counts[material] = 0
		var builder: SurfaceTool = builders[material]
		# Bridge parts are local to three translated bridge roots. Preserve their
		# full transforms when placing their vertices in this module's space.
		builder.append_from(source.mesh, 0, module_inverse * source.global_transform)
		counts[material] += 1
		source_count += 1
		source.free()
	var batch_index := 0
	for material: Material in builders:
		var builder: SurfaceTool = builders[material]
		var mesh := builder.commit()
		mesh.surface_set_material(0, material)
		var batch := MeshInstance3D.new()
		batch.name = "RiverFittings_%02d" % batch_index
		batch.mesh = mesh
		batch.set_meta("static_river_batch", true)
		batch.set_meta("source_piece_count", counts[material])
		add_child(batch)
		batch_index += 1
	set_meta("baked_detail_count", source_count)
	set_meta("detail_batch_count", batch_index)


func _process(delta: float) -> void:
	_sync_weather()
	if is_instance_valid(game) and game.has_method("is_combat_running") and game.is_combat_running():
		elapsed += delta
		if is_instance_valid(water_material):
			water_material.set_shader_parameter("river_time", elapsed)


func _sync_weather() -> void:
	if not is_instance_valid(arena):
		return
	var kind: String = arena.get("weather_kind")
	if kind == _weather_kind:
		return
	_weather_kind = kind
	var rain := 1.0 if kind == "heavy_rain" else (0.45 if kind == "light_rain" else 0.0)
	if is_instance_valid(water_material):
		water_material.set_shader_parameter("rainfall", rain)
	if is_instance_valid(hill_material):
		hill_material.set_shader_parameter("wetness", rain)
		hill_material.set_shader_parameter("snow_amount", 1.0 if kind == "snow" else 0.0)


func _prepare_hill_material() -> void:
	if is_instance_valid(hill_material):
		return
	hill_material = ShaderMaterial.new()
	hill_material.shader = HILL_SHADER
	var directory := "res://assets/materials/polyhaven/rough_concrete/rough_concrete_"
	hill_material.set_shader_parameter("rock_albedo", load(directory + "diff_1k.jpg"))
	hill_material.set_shader_parameter("rock_normal", load(directory + "nor_gl_1k.jpg"))
	hill_material.set_shader_parameter("rock_roughness", load(directory + "rough_1k.jpg"))
	var grass_directory := "res://assets/models/environment/polyhaven_aerial_grass/textures/aerial_grass_rock_"
	hill_material.set_shader_parameter("grass_albedo", load(grass_directory + "diff_1k.jpg"))
	hill_material.set_shader_parameter("grass_normal", load(grass_directory + "nor_gl_1k.jpg"))
	hill_material.set_shader_parameter("grass_arm", load(grass_directory + "arm_1k.jpg"))


func _build_channel(concrete: Material) -> void:
	var bed := _material(Color("3b4134"), 0.98)
	_box(self, "RiverBed", Vector3(0, -6.35, RIVER_CENTER), Vector3(460, 0.7, 28), bed, true)
	# A sloped quay, rather than a water-colored strip painted over solid ground.
	for north in [true, false]:
		var top_z := RIVER_MIN_Z if north else RIVER_MAX_Z
		var toe_z := top_z + (3.0 if north else -3.0)
		var bank := MeshInstance3D.new()
		bank.name = "NorthEmbankment" if north else "SouthEmbankment"
		var points := PackedVector3Array([Vector3(-230, DECK_HEIGHT, top_z), Vector3(230, DECK_HEIGHT, top_z), Vector3(-230, -5.9, toe_z), Vector3(230, -5.9, toe_z)])
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var order := [0, 1, 2, 1, 3, 2] if north else [0, 2, 1, 1, 2, 3]
		for index: int in order:
			surface.set_uv(Vector2(points[index].x * 0.1, points[index].y * 0.1))
			surface.add_vertex(points[index])
		surface.generate_normals()
		bank.mesh = surface.commit()
		bank.material_override = concrete
		add_child(bank)
		_trimesh_body(bank)
		for x in range(-140, 141, 14):
			_box(self, "QuayDrain", Vector3(x, -0.8, top_z + (0.45 if north else -0.45)), Vector3(1.1, 0.5, 0.18), bed)
	water_material = ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water = MeshInstance3D.new()
	water.name = "FlowingRiver"
	var plane := PlaneMesh.new()
	plane.size = Vector2(460, 28)
	plane.subdivide_width = 180
	plane.subdivide_depth = 12
	water.mesh = plane
	water.material_override = water_material
	water.position = Vector3(0, WATER_HEIGHT, RIVER_CENTER)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.extra_cull_margin = 0.2
	add_child(water)


func _build_bridge(center_x: float, width: float, concrete: Material, asphalt: Material, metal: Material, paint: Material) -> void:
	var bridge := Node3D.new()
	bridge.name = "RiverBridge_%d" % int(center_x)
	bridge.position = Vector3(center_x, 0, RIVER_CENTER)
	add_child(bridge)
	var bounds := AABB(Vector3(center_x - width * 0.5 - 1.1, -1.15, 18), Vector3(width + 2.2, 1.1, 36))
	_box(bridge, "BridgeDeck", Vector3(0, -0.6, 0), Vector3(width + 2.2, 1.1, 36), concrete, true)
	_box(bridge, "BridgeAsphalt", Vector3(0, 0.015, 0), Vector3(width, 0.05, 36), asphalt)
	for z in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_box(bridge, "BridgeLaneStripe", Vector3(0, 0.065, z), Vector3(0.18, 0.025, 3.4), paint)
	for side in [-1.0, 1.0]:
		var rail_x: float = side * (width * 0.5 + 0.42)
		# Solid rail colliders keep tracks on the road while providing clear bridge mouths.
		_box(bridge, "BridgeParapet", Vector3(rail_x, 0.55, 0), Vector3(0.6, 1.2, 36), concrete, true)
		_box(bridge, "BridgeTopRail", Vector3(rail_x, 1.42, 0), Vector3(0.18, 0.16, 36), metal)
		for z in range(-18, 19, 3):
			_box(bridge, "BridgeRailPost", Vector3(rail_x, 1.08, z), Vector3(0.16, 0.66, 0.16), metal)
		# Two haunched piers sit below the water and support longitudinal girders.
		for z in [-9.0, 9.0]:
			_box(bridge, "BridgePier", Vector3(side * (width * 0.5 - 1.15), -3.6, z), Vector3(1.65, 5.0, 2.8), concrete, true)
		_box(bridge, "UnderDeckGirder", Vector3(side * width * 0.3, -1.22, 0), Vector3(0.42, 0.5, 32), metal)
		var arch_x: float = side * (width * 0.5 + 0.36)
		for index in 12:
			var from_z := -17.0 + float(index) * 34.0 / 12.0
			var to_z := -17.0 + float(index + 1) * 34.0 / 12.0
			var from_y := 1.3 + 5.7 * sin((from_z + 17.0) / 34.0 * PI)
			var to_y := 1.3 + 5.7 * sin((to_z + 17.0) / 34.0 * PI)
			_beam(bridge, "SteelArch", Vector3(arch_x, from_y, from_z), Vector3(arch_x, to_y, to_z), Vector2(0.48, 0.55), metal)
			if index > 0:
				_beam(bridge, "ArchHanger", Vector3(arch_x, 1.4, from_z), Vector3(arch_x, from_y, from_z), Vector2(0.10, 0.1), metal)
	for z in [-5.6667, 0.0, 5.6667]:
		var y := 1.3 + 5.7 * sin((z + 17.0) / 34.0 * PI)
		_box(bridge, "ArchCrossBrace", Vector3(0, y, z), Vector3(width + 0.9, 0.28, 0.3), metal)
		_weather_roofs.append(AABB(Vector3(center_x - width * 0.5 - 0.45, y - 0.14, RIVER_CENTER + z - 0.15), Vector3(width + 0.9, 0.28, 0.3)))
	bridge.set_meta("clear_width", width)
	bridge.set_meta("deck_bounds", bounds)
	_bridges.append({"node": bridge, "center": Vector3(center_x, DECK_HEIGHT, RIVER_CENTER), "width": width,
		"deck_bounds": bounds, "traversal_bounds": AABB(Vector3(center_x - width * 0.5, DECK_HEIGHT, 18), Vector3(width, 5.7, 36))})


func _build_bank_rails(concrete: Material, metal: Material) -> void:
	var spans := [Vector2(-144, -105.8), Vector2(-86.2, -10.8), Vector2(10.8, 86.2), Vector2(105.8, 144)]
	for z in [RIVER_MIN_Z - 0.35, RIVER_MAX_Z + 0.35]:
		for span: Vector2 in spans:
			var width: float = span.y - span.x
			var middle: float = (span.x + span.y) * 0.5
			_box(self, "RiverBankBarrier", Vector3(middle, 0.48, z), Vector3(width, 1.06, 0.6), concrete, true)
			_box(self, "RiverBankRail", Vector3(middle, 1.27, z), Vector3(width, 0.12, 0.13), metal)
			for index in int(width / 3.0) + 1:
				var post_x := span.x + minf(float(index) * 3.0, width)
				_box(self, "RiverBankPost", Vector3(post_x, 0.95, z), Vector3(0.1, 0.62, 0.1), metal)


func add_hill(parent: Node3D, center: Vector3, radii: Vector2, height: float, collision := true) -> Node3D:
	_prepare_hill_material()
	var hill := MeshInstance3D.new()
	hill.name = ("RollingHill_" if collision else "DistantRidge_") + str(parent.get_child_count())
	hill.position = center
	hill.material_override = hill_material
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tangents := PackedFloat32Array()
	for z_index in HILL_STEPS + 1:
		for x_index in HILL_STEPS + 1:
			var x := (float(x_index) / HILL_STEPS * 2.0 - 1.0) * radii.x
			var z := (float(z_index) / HILL_STEPS * 2.0 - 1.0) * radii.y
			var y := sample_hill_height(Vector2(x, z), radii, height)
			var epsilon := 0.15
			var dx := (sample_hill_height(Vector2(x + epsilon, z), radii, height) - sample_hill_height(Vector2(x - epsilon, z), radii, height)) / (2.0 * epsilon)
			var dz := (sample_hill_height(Vector2(x, z + epsilon), radii, height) - sample_hill_height(Vector2(x, z - epsilon), radii, height)) / (2.0 * epsilon)
			vertices.append(Vector3(x, y, z))
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normals.append(normal)
			var tangent := (Vector3.RIGHT - normal * normal.dot(Vector3.RIGHT)).normalized()
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, 1.0]))
			uvs.append(Vector2(x, z) * 0.16)
	for z_index in HILL_STEPS:
		for x_index in HILL_STEPS:
			var index := z_index * (HILL_STEPS + 1) + x_index
			indices.append_array(PackedInt32Array([index, index + 1, index + HILL_STEPS + 1,
				index + 1, index + HILL_STEPS + 2, index + HILL_STEPS + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	hill.mesh = mesh
	parent.add_child(hill)
	if collision:
		_trimesh_body(hill)
	else:
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hill.set_meta("hill_radii", radii)
	hill.set_meta("hill_height", height)
	hill.set_meta("terrain_triangles", HILL_STEPS * HILL_STEPS * 2)
	hill.set_meta("drivable", collision)
	return hill


static func sample_hill_height(at: Vector2, radii: Vector2, height: float) -> float:
	var q := at / radii
	var radius_squared := q.length_squared()
	if radius_squared >= 1.0:
		return 0.0
	var envelope := pow(1.0 - radius_squared, 2.0)
	var ridges := 1.0 + 0.28 * sin(q.x * 7.0 + q.y * 2.0) * sin(q.y * 5.0 - q.x * 0.8)
	ridges += 0.12 * sin(q.x * 13.0 - q.y * 3.0) * sin(q.y * 9.0 + q.x * 2.0)
	return height * envelope * ridges


static func hill_height(at: Vector2, center: Vector2, radii: Vector2, height: float) -> float:
	return sample_hill_height(at - center, radii, height)


func _box(parent: Node3D, node_name: String, at: Vector3, size: Vector3, material: Material, collision := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.position = at
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	parent.add_child(mesh)
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


func _beam(parent: Node3D, node_name: String, from: Vector3, to: Vector3, section: Vector2, material: Material) -> void:
	var beam := _box(parent, node_name, (from + to) * 0.5, Vector3(section.x, (to - from).length(), section.y), material)
	var direction := (to - from).normalized()
	var axis := Vector3.UP.cross(direction)
	if axis.length_squared() > 0.0001:
		beam.basis = Basis(axis.normalized(), Vector3.UP.angle_to(direction))


func _trimesh_body(mesh: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	mesh.add_child(body)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
