extends RefCounted
## Bakes small, static industrial fittings into one mesh per shared material.
## Decorative geometry never adds collision or changes mission navigation.

var _surfaces: Dictionary = {}
var _box := BoxMesh.new()
var _cylinders: Dictionary = {}
var _sphere := SphereMesh.new()
var _wheel := TorusMesh.new()
var piece_count := 0
var placement := Transform3D.IDENTITY


func _init() -> void:
	_box.size = Vector3.ONE
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 24
	_sphere.rings = 12
	_wheel.inner_radius = 0.76
	_wheel.outer_radius = 1.0
	_wheel.rings = 24
	_wheel.ring_segments = 8


func box(position: Vector3, size: Vector3, surface: Material, rotation := Vector3.ZERO) -> void:
	_append(_box, surface, Transform3D(Basis.from_euler(rotation) * Basis.from_scale(size), position))


func cylinder(position: Vector3, radius: float, height: float, surface: Material, top_ratio := 1.0) -> void:
	var key := snappedf(top_ratio, 0.01)
	if not _cylinders.has(key):
		var shape := CylinderMesh.new()
		shape.top_radius = top_ratio
		shape.bottom_radius = 1.0
		shape.height = 1.0
		shape.radial_segments = 24
		shape.rings = 1
		_cylinders[key] = shape
	_append(_cylinders[key], surface, Transform3D(Basis.from_scale(Vector3(radius, height, radius)), position))


func dome(position: Vector3, radii: Vector3, surface: Material) -> void:
	_append(_sphere, surface, Transform3D(Basis.from_scale(radii), position))


func valve_wheel(position: Vector3, radius: float, surface: Material) -> void:
	_append(_wheel, surface, Transform3D(Basis.from_scale(Vector3.ONE * radius), position))
	for spoke in range(3):
		box(position, Vector3(radius * 1.8, radius * 0.12, radius * 0.12), surface, Vector3(0, spoke * PI / 3.0, 0))


func pipe(start: Vector3, end: Vector3, radius: float, surface: Material) -> void:
	var direction := end - start
	if direction.length_squared() < 0.00001:
		return
	var axis_y := direction.normalized()
	var guide := Vector3.FORWARD if absf(axis_y.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var axis_x := guide.cross(axis_y).normalized()
	var axis_z := axis_x.cross(axis_y).normalized()
	if not _cylinders.has(1.0):
		var shape := CylinderMesh.new()
		shape.top_radius = 1.0
		shape.bottom_radius = 1.0
		shape.height = 1.0
		shape.radial_segments = 24
		shape.rings = 1
		_cylinders[1.0] = shape
	var basis := Basis(axis_x * radius, axis_y * direction.length(), axis_z * radius)
	_append(_cylinders[1.0], surface, Transform3D(basis, (start + end) * 0.5))


func bake(parent: Node3D, prefix := "IndustrialFittings") -> void:
	var index := 0
	for surface: Material in _surfaces:
		var builder: SurfaceTool = _surfaces[surface]
		var mesh := builder.commit()
		mesh.surface_set_material(0, surface)
		var instance := MeshInstance3D.new()
		instance.name = "%s_%02d" % [prefix, index]
		instance.mesh = mesh
		instance.set_meta("static_detail_batch", true)
		parent.add_child(instance)
		index += 1
	_surfaces.clear()


func _append(mesh: Mesh, surface: Material, transform: Transform3D) -> void:
	if not _surfaces.has(surface):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[surface] = builder
	var builder: SurfaceTool = _surfaces[surface]
	builder.append_from(mesh, 0, placement * transform)
	piece_count += 1
