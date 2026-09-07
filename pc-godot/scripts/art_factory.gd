class_name ArtFactory
extends RefCounted
## Shared procedural military materials and mesh helpers.


static func material(color: Color, metallic := 0.0, roughness := 0.72, emission := 0.0) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.metallic = metallic
	value.roughness = roughness
	value.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if emission > 0.0:
		value.emission_enabled = true
		value.emission = color
		value.emission_energy_multiplier = emission
	return value


static func terrain_material(primary: Color, secondary: Color, seed: int) -> StandardMaterial3D:
	var value := material(primary, 0.0, 0.94)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.045
	noise.fractal_octaves = 5
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	var gradient := Gradient.new()
	gradient.set_color(0, primary.darkened(0.35))
	gradient.set_color(1, secondary)
	texture.color_ramp = gradient
	value.albedo_texture = texture
	value.uv1_triplanar = true
	value.uv1_world_triplanar = true
	value.uv1_scale = Vector3.ONE * 0.18
	return value


static func pbr_terrain_material(
	albedo_path: String,
	normal_path: String,
	roughness_path: String,
	tint: Color,
	world_scale: float,
	normal_strength := 0.72
) -> StandardMaterial3D:
	var value := material(tint, 0.0, 1.0)
	value.uv1_triplanar = true
	value.uv1_world_triplanar = true
	value.uv1_scale = Vector3.ONE * world_scale
	var albedo_resource: Resource = load(albedo_path)
	if albedo_resource is Texture2D:
		value.albedo_texture = albedo_resource as Texture2D
	var normal_resource: Resource = load(normal_path)
	if normal_resource is Texture2D:
		value.normal_enabled = true
		value.normal_texture = normal_resource as Texture2D
		value.normal_scale = normal_strength
	var roughness_resource: Resource = load(roughness_path)
	if roughness_resource is Texture2D:
		value.roughness_texture = roughness_resource as Texture2D
	return value


static func add_box(parent: Node3D, name: String, position: Vector3, size: Vector3, surface: Material, collision := false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	var shape := BoxMesh.new()
	shape.size = size
	mesh_instance.mesh = shape
	mesh_instance.position = position
	mesh_instance.material_override = surface
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)
		mesh_instance.add_child(body)
	return mesh_instance


static func add_cylinder(parent: Node3D, name: String, position: Vector3, radius: float, height: float, surface: Material, sides := 16) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = sides
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = shape
	mesh_instance.position = position
	mesh_instance.material_override = surface
	parent.add_child(mesh_instance)
	return mesh_instance


static func add_sphere(parent: Node3D, name: String, position: Vector3, radius: float, surface: Material, segments := 16) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = segments
	shape.rings = maxi(6, segments / 2)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = shape
	mesh_instance.position = position
	mesh_instance.material_override = surface
	parent.add_child(mesh_instance)
	return mesh_instance


static func add_torus(parent: Node3D, name: String, position: Vector3, radius: float, width: float, surface: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = maxf(0.02, radius - width)
	shape.outer_radius = radius
	shape.rings = 32
	shape.ring_segments = 8
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = shape
	mesh_instance.position = position
	mesh_instance.material_override = surface
	parent.add_child(mesh_instance)
	return mesh_instance
