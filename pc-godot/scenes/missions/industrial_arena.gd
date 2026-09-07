class_name IndustrialArena
extends Node3D
## Authored procedural city block for Chapter 01: Ash Ignition.

var game: Node
var boss_gate: Array[MeshInstance3D] = []
var _asphalt: StandardMaterial3D
var _concrete: StandardMaterial3D
var _building: StandardMaterial3D
var _metal: StandardMaterial3D
var _paint: StandardMaterial3D
var _vegetation: StandardMaterial3D


func _ready() -> void:
	_asphalt = ArtFactory.pbr_terrain_material(
		"res://assets/materials/polyhaven/asphalt_01/asphalt_01_diff_1k.jpg",
		"res://assets/materials/polyhaven/asphalt_01/asphalt_01_nor_gl_1k.jpg",
		"res://assets/materials/polyhaven/asphalt_01/asphalt_01_rough_1k.jpg",
		Color("9aa096"), 0.16, 0.82
	)
	_concrete = ArtFactory.pbr_terrain_material(
		"res://assets/materials/polyhaven/rough_concrete/rough_concrete_diff_1k.jpg",
		"res://assets/materials/polyhaven/rough_concrete/rough_concrete_nor_gl_1k.jpg",
		"res://assets/materials/polyhaven/rough_concrete/rough_concrete_rough_1k.jpg",
		Color("908e82"), 0.14, 0.68
	)
	_building = ArtFactory.pbr_terrain_material(
		"res://assets/materials/polyhaven/rough_concrete/rough_concrete_diff_1k.jpg",
		"res://assets/materials/polyhaven/rough_concrete/rough_concrete_nor_gl_1k.jpg",
		"res://assets/materials/polyhaven/rough_concrete/rough_concrete_rough_1k.jpg",
		Color("59615b"), 0.10, 0.55
	)
	_metal = ArtFactory.material(Color("4d574f"), 0.82, 0.34)
	_paint = ArtFactory.material(Color("c9793f"), 0.55, 0.45)
	_vegetation = ArtFactory.material(Color("344b2f"), 0.0, 0.9)
	_build_environment()
	_build_ground()
	_build_boundaries()
	_build_industrial_blocks()
	_build_cover()
	_build_details()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("17232a")
	sky_material.sky_horizon_color = Color("786957")
	sky_material.ground_bottom_color = Color("171914")
	sky_material.ground_horizon_color = Color("5c5142")
	sky_material.sun_angle_max = 4.0
	sky_material.sun_curve = 0.09
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.58
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.18
	environment.ssao_enabled = true
	environment.ssao_radius = 2.5
	environment.ssao_intensity = 2.0
	environment.ssil_enabled = true
	environment.ssil_radius = 3.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("807569")
	environment.fog_light_energy = 0.30
	environment.fog_density = 0.0018
	environment.fog_sky_affect = 0.32
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0038
	environment.volumetric_fog_length = 120.0
	environment.volumetric_fog_sky_affect = 0.24
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "LowSun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0)
	sun.light_color = Color("ffd1a0")
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_fade_start = 0.72
	add_child(sun)


func _build_ground() -> void:
	ArtFactory.add_box(self, "Terrain", Vector3(0, -0.45, 0), Vector3(190, 0.8, 132), _concrete, true)
	ArtFactory.add_box(self, "MainAvenue", Vector3(0, 0.015, 0), Vector3(24, 0.05, 128), _asphalt)
	for z in [-36.0, 0.0, 36.0]:
		ArtFactory.add_box(self, "CrossStreet", Vector3(0, 0.025, z), Vector3(186, 0.06, 18), _asphalt)
	var stripe := ArtFactory.material(Color("d3bd72"), 0.05, 0.6, 0.12)
	for z in range(-60, 63, 8):
		ArtFactory.add_box(self, "LaneMark", Vector3(0, 0.065, float(z)), Vector3(0.22, 0.03, 3.4), stripe)
	for x in range(-84, 85, 8):
		ArtFactory.add_box(self, "CrossMark", Vector3(float(x), 0.07, 0), Vector3(3.3, 0.03, 0.18), stripe)


func _build_boundaries() -> void:
	for data in [
		[Vector3(0, 2.1, -65), Vector3(190, 4.2, 1.3)],
		[Vector3(0, 2.1, 65), Vector3(190, 4.2, 1.3)],
		[Vector3(-94, 2.1, 0), Vector3(1.3, 4.2, 132)],
		[Vector3(94, 2.1, 0), Vector3(1.3, 4.2, 132)],
	]:
		ArtFactory.add_box(self, "PerimeterWall", data[0], data[1], _concrete, true)
	for x in range(-90, 91, 10):
		ArtFactory.add_box(self, "WallPier", Vector3(float(x), 2.5, -64.1), Vector3(1.1, 5.0, 1.6), _metal)
		ArtFactory.add_box(self, "WallPier", Vector3(float(x), 2.5, 64.1), Vector3(1.1, 5.0, 1.6), _metal)
	for x in [-4.5, -2.7, -0.9, 0.9, 2.7, 4.5]:
		var gate_bar := ArtFactory.add_box(self, "BossGate", Vector3(x, 2.25, -43.0), Vector3(0.32, 4.5, 1.0), _metal, true)
		boss_gate.append(gate_bar)


func _build_industrial_blocks() -> void:
	var buildings := [
		[Vector3(-57, 5.5, -48), Vector3(48, 11, 15)], [Vector3(56, 7.0, -48), Vector3(50, 14, 15)],
		[Vector3(-59, 6.5, -18), Vector3(44, 13, 16)], [Vector3(61, 4.8, -17), Vector3(45, 9.6, 17)],
		[Vector3(-58, 5.0, 19), Vector3(48, 10, 16)], [Vector3(59, 6.8, 19), Vector3(47, 13.6, 16)],
		[Vector3(-59, 7.4, 49), Vector3(46, 14.8, 15)], [Vector3(58, 5.3, 49), Vector3(48, 10.6, 15)],
	]
	for index in range(buildings.size()):
		var data: Array = buildings[index]
		var building_position: Vector3 = data[0]
		var building_size: Vector3 = data[1]
		var building := ArtFactory.add_box(self, "Warehouse_%02d" % index, building_position, building_size, _building, true)
		ArtFactory.add_box(building, "Roof", Vector3(0, building_size.y * 0.52, 0), Vector3(building_size.x * 1.02, 0.45, building_size.z * 1.04), _metal)
		for column in range(-2, 3):
			var x: float = float(column) * building_size.x * 0.16
			var face_z: float = -building_size.z * 0.505
			ArtFactory.add_box(building, "Window", Vector3(x, 1.0, face_z), Vector3(2.4, 1.35, 0.08), ArtFactory.material(Color("d78a4a"), 0.1, 0.4, 1.7))
		for vent in range(3):
			ArtFactory.add_cylinder(building, "RoofVent", Vector3(-building_size.x * 0.22 + vent * 3.2, building_size.y * 0.55 + 0.8, 0), 0.55, 1.5, _metal, 12)


func _build_cover() -> void:
	var positions := [
		Vector3(-7, 0, 30), Vector3(8, 0, 22), Vector3(-7, 0, 10), Vector3(7, 0, -8),
		Vector3(-8, 0, -23), Vector3(7, 0, -34), Vector3(-24, 0, 35), Vector3(26, 0, 34),
		Vector3(-28, 0, 4), Vector3(31, 0, -4), Vector3(-27, 0, -32), Vector3(29, 0, -31),
	]
	for index in range(positions.size()):
		var cover := DestructibleCover.new()
		cover.name = "DestructibleCover_%02d" % index
		cover.game = game
		cover.position = positions[index]
		cover.rotation.y = PI * 0.5 if index % 3 == 0 else (0.35 if index % 2 == 0 else -0.28)
		cover.size = Vector3(5.5 if index < 6 else 4.2, 1.45, 1.1)
		cover.hp = 120.0
		cover.surface = _concrete if index % 2 == 0 else _metal
		add_child(cover)


func _build_details() -> void:
	for z in range(-55, 58, 12):
		for side in [-1.0, 1.0]:
			var x: float = side * 15.2
			ArtFactory.add_cylinder(self, "LampPost", Vector3(x, 3.0, float(z)), 0.1, 6.0, _metal, 10)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 5.65, float(z))
			lamp.light_color = Color("ffb36b")
			lamp.light_energy = 1.4
			lamp.omni_range = 13.0
			lamp.shadow_enabled = false
			add_child(lamp)
	for z in [-27.0, 12.0, 43.0]:
		for side in [-1.0, 1.0]:
			var root := Node3D.new()
			root.position = Vector3(side * 22.0, 0, z)
			add_child(root)
			ArtFactory.add_cylinder(root, "TreeTrunk", Vector3(0, 2.1, 0), 0.38, 4.2, ArtFactory.material(Color("4b3626"), 0.0, 0.92), 10)
			ArtFactory.add_sphere(root, "TreeCanopy", Vector3(0, 5.0, 0), 2.5, _vegetation, 12)
	for index in range(18):
		var side := -1.0 if index % 2 == 0 else 1.0
		var container_color: Color = [Color("6e3c2d"), Color("425968"), Color("5b6439")][index % 3]
		var container := ArtFactory.add_box(self, "Container", Vector3(side * (34.0 + (index % 3) * 6.4), 1.3, -54.0 + float(index) * 6.2), Vector3(5.8, 2.6, 2.45), ArtFactory.material(container_color, 0.65, 0.45), false)
		container.rotation.y = 0.03 * float((index % 5) - 2)
		for rib in [-2.4, -1.2, 0.0, 1.2, 2.4]:
			ArtFactory.add_box(container, "ContainerRib", Vector3(rib, 0, -1.25), Vector3(0.08, 2.45, 0.05), _metal)


func set_boss_gate_open(open: bool) -> void:
	for bar in boss_gate:
		if not is_instance_valid(bar):
			continue
		bar.visible = not open
		for child in bar.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).collision_layer = 0 if open else 1
