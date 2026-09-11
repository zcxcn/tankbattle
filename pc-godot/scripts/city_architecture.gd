extends RefCounted
## Metric, stepped city architecture: modeled bays, chamfered corners, podiums,
## balconies and mechanical roofs. Details are merged by material per tower.

const Details = preload("res://scripts/industrial_details.gd")
var concrete: BaseMaterial3D
var stone: BaseMaterial3D
var metal: StandardMaterial3D
var glass: Array[StandardMaterial3D] = []
var roofs: Array[AABB] = []
var piece_count := 0

func _init() -> void:
	concrete = load("res://assets/models/environment/polyhaven_concrete_facade/concrete_tile_facade.tres").duplicate()
	concrete.albedo_color = Color("b8b6a8")
	stone = concrete.duplicate()
	stone.albedo_color = Color("78858b")
	metal = ArtFactory.material(Color("35434a"), 0.65, 0.38)
	for color in [Color("375666"), Color("486672"), Color("2e414d"), Color("677674")]:
		glass.append(ArtFactory.material(color, 0.48, 0.23))

func build(parent: Node3D, at: Vector3, width: float, depth: float, height: float, variant: int, collision := true) -> Node3D:
	var root := Node3D.new()
	root.name = "CityTower_%d" % parent.get_child_count()
	root.position = at
	root.set_meta("city_building", true)
	root.set_meta("building_type", ["office_tower", "residential_tower", "stepped_civic_tower"][posmod(variant, 3)])
	root.set_meta("height", height)
	parent.add_child(root)
	var details := Details.new()
	var residential := posmod(variant, 3) == 1
	var wall: Material = concrete if residential else stone
	var podium_height := 5.4
	var podium_size := Vector3(width, podium_height, depth)
	_shell(root, Vector3(0, podium_height * 0.5, 0), podium_size, wall, collision)
	_bays(details, podium_size, 0.0, 1, variant, false)
	details.box(Vector3(0, 5.5, 0), Vector3(width + 0.5, 0.3, depth + 0.5), concrete)
	# Three progressively recessed volumes break up the silhouette at street scale.
	var floors := maxi(6, roundi((height - podium_height) / 3.25))
	var level_start := 0
	var base_y := podium_height
	for tier in 3:
		var count := floors / 3 + (1 if tier < floors % 3 else 0)
		var tier_height := count * 3.25
		var size := Vector3(width * (0.84 - tier * 0.12), tier_height, depth * (0.82 - tier * 0.10))
		_shell(root, Vector3(0, base_y + tier_height * 0.5, 0), size, wall, collision)
		_bays(details, size, base_y, count, variant + level_start, residential)
		details.box(Vector3(0, base_y + tier_height + 0.10, 0), Vector3(size.x + 0.5, 0.20, size.z + 0.5), concrete)
		for side in [-1.0, 1.0]:
			details.box(Vector3(0, base_y + tier_height + 0.42, side * size.z * 0.5), Vector3(size.x, 0.64, 0.18), metal)
			details.box(Vector3(side * size.x * 0.5, base_y + tier_height + 0.42, 0), Vector3(0.18, 0.64, size.z), metal)
		if collision:
			roofs.append(AABB(at + Vector3(-size.x * 0.5 - 0.2, 0, -size.z * 0.5 - 0.2), Vector3(size.x + 0.4, base_y + tier_height + 0.75, size.z + 0.4)))
		base_y += tier_height
		level_start += count
	# Recessed entrance with a suspended canopy and modeled glazed doors.
	for side in [-1.0, 1.0]:
		var entrance := Vector3(0, 0, side * (depth * 0.5 + 0.2))
		details.box(entrance + Vector3(0, 1.8, 0), Vector3(5.2, 3.6, 0.16), glass[0])
		details.box(entrance + Vector3(0, 3.85, side * 0.75), Vector3(7.8, 0.2, 2.0), metal)
		for x in [-2.7, 0.0, 2.7]:
			details.box(entrance + Vector3(x, 1.8, side * 0.1), Vector3(0.12, 3.6, 0.12), metal)
		if collision:
			roofs.append(AABB(at + entrance + Vector3(-4.0, 0, -1.0), Vector3(8.0, 3.95, 2.0)))
	for x in [-3.0, 3.0]:
		details.box(Vector3(x, base_y + 1.1, 0), Vector3(3.6, 2.0, 3.0), metal)
		for z in [-0.7, 0.7]:
			details.cylinder(Vector3(x, base_y + 2.18, z), 0.6, 0.14, stone)
		for rib in 6:
			details.box(Vector3(x, base_y + 0.45 + rib * 0.23, 1.52), Vector3(3.2, 0.06, 0.10), concrete)
	if posmod(variant, 3) == 2:
		details.pipe(Vector3(0, base_y, 0), Vector3(0, base_y + 12, 0), 0.13, metal)
		details.pipe(Vector3(-2, base_y + 3, 0), Vector3(2, base_y + 3, 0), 0.065, metal)
	details.bake(root, "CityFacade")
	piece_count += details.piece_count
	if not collision:
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if collision:
		roofs.append(AABB(at + Vector3(-width * 0.5, 0, -depth * 0.5), Vector3(width, podium_height + 0.3, depth)))
	return root

func _bays(details: RefCounted, size: Vector3, base_y: float, floors: int, variant: int, residential: bool) -> void:
	var step_y := size.y / float(floors)
	for face in 4:
		var yaw := face * PI * 0.5
		var face_width := size.x if face % 2 == 0 else size.z
		var face_depth := size.z if face % 2 == 0 else size.x
		details.placement = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
		var columns := maxi(2, floori((face_width - 2.0) / 2.8))
		var bay := (face_width - 2.0) / float(columns)
		for level in floors:
			var y := base_y + (level + 0.5) * step_y
			for column in columns:
				var x := -face_width * 0.5 + 1.0 + (column + 0.5) * bay
				var z := face_depth * 0.5 + 0.025
				var pane := glass[posmod(column * 7 + level * 3 + variant + face, glass.size())]
				details.box(Vector3(x, y, z), Vector3(bay - 0.22, step_y - 0.58, 0.08), pane)
				details.box(Vector3(x - bay * 0.5, y, z + 0.08), Vector3(0.10, step_y, 0.16), metal)
				details.box(Vector3(x, y - step_y * 0.5 + 0.18, z + 0.12), Vector3(bay, 0.23, 0.28), concrete)
				if residential and column % 2 == 0:
					details.box(Vector3(x, y - step_y * 0.5 + 0.12, z + 0.65), Vector3(bay - 0.10, 0.18, 1.4), concrete)
					details.box(Vector3(x, y - step_y * 0.5 + 0.70, z + 1.3), Vector3(bay - 0.15, 0.9, 0.10), glass[1])
					details.box(Vector3(x, y - step_y * 0.5 + 1.19, z + 1.3), Vector3(bay, 0.06, 0.14), metal)
				else:
					details.box(Vector3(x, y + step_y * 0.5 - 0.12, z + 0.18), Vector3(bay, 0.15, 0.40), metal)
	details.placement = Transform3D.IDENTITY

func _shell(parent: Node3D, center: Vector3, size: Vector3, surface: Material, collision: bool) -> void:
	var half := Vector2(size.x, size.z) * 0.5
	var chamfer := 0.7
	var ring: Array[Vector2] = [Vector2(-half.x + chamfer, -half.y), Vector2(half.x - chamfer, -half.y), Vector2(half.x, -half.y + chamfer), Vector2(half.x, half.y - chamfer), Vector2(half.x - chamfer, half.y), Vector2(-half.x + chamfer, half.y), Vector2(-half.x, half.y - chamfer), Vector2(-half.x, -half.y + chamfer)]
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	for index in ring.size():
		var a := ring[index]
		var b := ring[(index + 1) % ring.size()]
		var points := [Vector3(a.x, -size.y * 0.5, a.y), Vector3(b.x, -size.y * 0.5, b.y), Vector3(b.x, size.y * 0.5, b.y), Vector3(a.x, size.y * 0.5, a.y)]
		for vertex in [0, 1, 2, 0, 2, 3]:
			builder.set_uv(Vector2(points[vertex].x + points[vertex].z, points[vertex].y) * 0.25)
			builder.add_vertex(points[vertex])
		for point in [Vector3.ZERO + Vector3.UP * size.y * 0.5, points[3], points[2]]:
			builder.set_uv(Vector2(point.x, point.z) * 0.25)
			builder.add_vertex(point)
	builder.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = builder.commit()
	mesh.position = center
	mesh.material_override = surface
	parent.add_child(mesh)
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = size - Vector3(0.1, 0, 0.1)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		mesh.add_child(body)
