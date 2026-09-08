class_name IndustrialArena
extends Node3D
## Authored procedural city block for Chapter 01: Ash Ignition.

const DetailsBuilder = preload("res://scripts/industrial_details.gd")

var game: Node
var boss_gate: Array[MeshInstance3D] = []
var _asphalt: StandardMaterial3D
var _concrete: StandardMaterial3D
var _building: StandardMaterial3D
var _metal: StandardMaterial3D
var _paint: StandardMaterial3D
var _dark_metal: StandardMaterial3D
var _glass: StandardMaterial3D
var _lamp_lens: StandardMaterial3D
var _details: RefCounted


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
	_metal = _weathered_steel(Color("727b7c"))
	_dark_metal = _weathered_steel(Color("333d41"))
	_paint = _weathered_steel(Color("b98442"))
	_glass = ArtFactory.material(Color("354952"), 0.48, 0.24)
	_lamp_lens = ArtFactory.material(Color("ffe3b3"), 0.0, 0.3, 2.3)
	_details = DetailsBuilder.new()
	_build_environment()
	_build_ground()
	_build_boundaries()
	_build_industrial_blocks()
	_build_cover()
	_build_details()
	_details.bake(self)
	set_meta("industrial_detail_pieces", _details.piece_count)
	_details = null


func _weathered_steel(tint: Color) -> StandardMaterial3D:
	var surface := _building.duplicate() as StandardMaterial3D
	surface.albedo_color = tint
	surface.metallic = 0.58
	surface.roughness = 0.84
	surface.normal_scale = 0.22
	surface.uv1_scale = Vector3.ONE * 0.45
	return surface


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("566b79")
	sky_material.sky_horizon_color = Color("abb4b5")
	sky_material.ground_bottom_color = Color("343a3d")
	sky_material.ground_horizon_color = Color("747d80")
	sky_material.sun_angle_max = 4.0
	sky_material.sun_curve = 0.09
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.80
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.06
	environment.ssao_enabled = true
	environment.ssao_radius = 2.5
	environment.ssao_intensity = 1.1
	environment.ssil_enabled = true
	environment.ssil_radius = 3.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("88969c")
	environment.fog_light_energy = 0.30
	environment.fog_density = 0.0012
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
	sun.light_color = Color("fff1dd")
	sun.light_energy = 1.15
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
		_details.placement = building.transform
		_warehouse_fittings(building_size)
	_details.placement = Transform3D.IDENTITY


func _warehouse_fittings(size: Vector3) -> void:
	var roof_y := size.y * 0.5
	var floor_y := -size.y * 0.5
	_details.box(Vector3(0, roof_y + 0.12, 0), Vector3(size.x + 0.35, 0.24, size.z + 0.35), _dark_metal)
	for side in [-1.0, 1.0]:
		var face_z: float = side * (size.z * 0.5 + 0.06)
		_details.box(Vector3(0, floor_y + 0.35, face_z), Vector3(size.x, 0.7, 0.16), _concrete)
		_details.box(Vector3(0, roof_y - 0.2, face_z), Vector3(size.x + 0.5, 0.4, 0.32), _metal)
		for column in range(-3, 4):
			var x: float = float(column) * size.x * 0.135
			_details.box(Vector3(x, 0, face_z), Vector3(0.24, size.y - 0.7, 0.2), _concrete)
			# Framed clerestory glazing on both long elevations, with mullions and sills.
			var window_y := roof_y - 2.15
			_details.box(Vector3(x + 1.55, window_y, face_z + side * 0.045), Vector3(2.5, 1.5, 0.1), _dark_metal)
			_details.box(Vector3(x + 1.55, window_y, face_z + side * 0.11), Vector3(2.28, 1.29, 0.06), _glass)
			_details.box(Vector3(x + 1.55, window_y, face_z + side * 0.16), Vector3(0.07, 1.36, 0.06), _metal)
			_details.box(Vector3(x + 1.55, window_y - 0.77, face_z + side * 0.13), Vector3(2.65, 0.1, 0.3), _metal)
		for bay_x in [-size.x * 0.24, size.x * 0.24]:
			var door_y: float = floor_y + 2.2
			_details.box(Vector3(bay_x, door_y, face_z + side * 0.04), Vector3(5.4, 4.45, 0.16), _dark_metal)
			_details.box(Vector3(bay_x, door_y, face_z + side * 0.15), Vector3(5.05, 4.2, 0.08), _metal)
			for slat in range(13):
				_details.box(Vector3(bay_x, floor_y + 0.18 + slat * 0.32, face_z + side * 0.21), Vector3(5.03, 0.035, 0.025), _dark_metal)
			_details.box(Vector3(bay_x, floor_y + 4.6, face_z + side * 0.4), Vector3(5.85, 0.16, 1.1), _dark_metal)
			_details.box(Vector3(bay_x, floor_y + 4.43, face_z + side * 0.22), Vector3(5.2, 0.1, 0.12), _lamp_lens)
			_details.box(Vector3(bay_x, floor_y + 0.1, face_z + side * 0.2), Vector3(5.6, 0.2, 0.4), _concrete)
		for edge in [-1.0, 1.0]:
			var drain_x: float = edge * (size.x * 0.5 - 0.4)
			_details.pipe(Vector3(drain_x, floor_y + 0.3, face_z + side * 0.21), Vector3(drain_x, roof_y - 0.25, face_z + side * 0.21), 0.085, _dark_metal)
			for clamp_y in [floor_y + 1.0, 0.0, roof_y - 0.9]:
				_details.box(Vector3(drain_x, clamp_y, face_z + side * 0.21), Vector3(0.23, 0.065, 0.23), _metal)
		# End walls face the avenue; their glazed bands give the facades depth from play cameras.
		var face_x: float = side * (size.x * 0.5 + 0.07)
		_details.box(Vector3(face_x, roof_y - 0.2, 0), Vector3(0.3, 0.4, size.z + 0.5), _metal)
		for z in [-size.z * 0.28, 0.0, size.z * 0.28]:
			_details.box(Vector3(face_x, roof_y - 2.1, z), Vector3(0.12, 1.5, 2.7), _dark_metal)
			_details.box(Vector3(face_x + side * 0.08, roof_y - 2.1, z), Vector3(0.07, 1.27, 2.46), _glass)
			_details.box(Vector3(face_x + side * 0.13, roof_y - 2.1, z), Vector3(0.06, 1.36, 0.075), _metal)
		_details.box(Vector3(face_x, floor_y + 1.35, 0), Vector3(0.14, 2.7, 1.25), _dark_metal)
		_details.box(Vector3(face_x + side * 0.1, floor_y + 1.3, 0), Vector3(0.1, 2.45, 1.0), _metal)
		_details.box(Vector3(face_x + side * 0.19, floor_y + 1.2, 0.34), Vector3(0.08, 0.07, 0.17), _paint)
	for unit in range(2):
		var center := Vector3((-0.23 if unit == 0 else 0.23) * size.x, roof_y, 0)
		_details.box(center + Vector3(0, 0.25, 0), Vector3(4.5, 0.5, 3.0), _concrete)
		_details.box(center + Vector3(0, 1.05, 0), Vector3(4.2, 1.2, 2.7), _metal)
		for row in range(7):
			_details.box(center + Vector3(0, 0.56 + row * 0.16, 1.375), Vector3(3.6, 0.065, 0.08), _dark_metal)
		for fan_x in [-1.1, 1.1]:
			_details.cylinder(center + Vector3(fan_x, 1.71, 0), 0.7, 0.16, _dark_metal)
			_details.cylinder(center + Vector3(fan_x, 1.81, 0), 0.13, 0.12, _metal)
			for spoke in range(6):
				_details.box(center + Vector3(fan_x, 1.815, 0), Vector3(1.32, 0.025, 0.035), _metal, Vector3(0, spoke * PI / 6.0, 0))
		# Short duct and weather hood communicate a connected ventilation system.
		_details.box(center + Vector3(0, 0.75, -2.15), Vector3(1.1, 0.85, 1.8), _dark_metal)
		_details.cylinder(center + Vector3(0, 1.55, -2.8), 0.44, 1.0, _metal)
		_details.cylinder(center + Vector3(0, 2.04, -2.8), 0.68, 0.18, _dark_metal, 0.65)


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
			var center := Vector3(side * 15.2, 0, float(z))
			_street_lamp(center, side)
	for z in [-27.0, 12.0, 43.0]:
		for side in [-1.0, 1.0]:
			_utility_station(Vector3(side * 22.0, 0, z))
	var container_paints: Array[StandardMaterial3D] = [
		_weathered_steel(Color("7b4b39")),
		_weathered_steel(Color("49616b")),
		_weathered_steel(Color("626952")),
	]
	# Keep complete containers in the loading aprons instead of intersecting warehouses.
	var container_rows := [-59.0, -51.0, -23.0, -15.0, 15.0, 23.0, 48.0, 54.0, 60.0]
	for index in range(18):
		var side := -1.0 if index % 2 == 0 else 1.0
		var container := ArtFactory.add_box(self, "Container_%02d" % index, Vector3(side * 27.5, 1.3, container_rows[index >> 1]), Vector3(5.8, 2.6, 2.45), container_paints[index % 3], true)
		container.rotation.y = (PI if side > 0.0 else 0.0) + 0.025 * float((index % 5) - 2)
		_details.placement = container.transform
		_container_fittings(container_paints[index % 3])
	_details.placement = Transform3D.IDENTITY


func _street_lamp(center: Vector3, side: float) -> void:
	_details.box(center + Vector3(0, 0.12, 0), Vector3(0.56, 0.24, 0.56), _concrete)
	_details.cylinder(center + Vector3(0, 0.3, 0), 0.22, 0.22, _metal, 0.78)
	_details.cylinder(center + Vector3(0, 3.05, 0), 0.105, 5.6, _metal, 0.6)
	_details.box(center + Vector3(0, 0.75, 0.105), Vector3(0.13, 0.32, 0.04), _dark_metal)
	for dx in [-0.17, 0.17]:
		for dz in [-0.17, 0.17]:
			_details.cylinder(center + Vector3(dx, 0.265, dz), 0.035, 0.08, _dark_metal)
	var elbow := center + Vector3(-side * 0.35, 6.0, 0)
	var head := center + Vector3(-side * 1.35, 6.04, 0)
	_details.pipe(center + Vector3(0, 5.73, 0), elbow, 0.063, _metal)
	_details.pipe(elbow, head, 0.063, _metal)
	_details.pipe(center + Vector3(0, 5.18, 0), center + Vector3(-side * 0.9, 6.0, 0), 0.035, _dark_metal)
	_details.box(head, Vector3(0.88, 0.19, 0.36), _dark_metal)
	_details.box(head + Vector3(0, -0.105, 0), Vector3(0.69, 0.035, 0.26), _lamp_lens)
	var lamp := OmniLight3D.new()
	lamp.name = "StreetLampLight"
	lamp.position = head + Vector3(0, -0.25, 0)
	lamp.light_color = Color("ffe0b0")
	lamp.light_energy = 0.85
	lamp.omni_range = 11.0
	lamp.shadow_enabled = false
	add_child(lamp)


func _utility_station(center: Vector3) -> void:
	# Service skids replace ornamental ball trees without adding navigation obstacles.
	_details.box(center + Vector3(0, 0.1, 0), Vector3(3.7, 0.2, 3.0), _concrete)
	var tank := center + Vector3(-0.75, 0, 0.3)
	for offset in [-0.43, 0.43]:
		_details.box(tank + Vector3(offset, 0.45, 0), Vector3(0.15, 0.7, 1.1), _dark_metal)
	_details.cylinder(tank + Vector3(0, 1.5, 0), 0.66, 1.6, _metal)
	_details.dome(tank + Vector3(0, 2.3, 0), Vector3(0.66, 0.32, 0.66), _metal)
	_details.dome(tank + Vector3(0, 0.7, 0), Vector3(0.66, 0.22, 0.66), _metal)
	for y in [0.82, 2.18]:
		_details.cylinder(tank + Vector3(0, y, 0), 0.685, 0.08, _dark_metal)
	_details.pipe(center + Vector3(-0.1, 1.25, 0.3), center + Vector3(1.3, 1.25, 0.3), 0.14, _metal)
	_details.pipe(center + Vector3(1.3, 0.25, 0.3), center + Vector3(1.3, 1.25, 0.3), 0.14, _metal)
	_details.cylinder(center + Vector3(0.7, 1.38, 0.3), 0.21, 0.3, _paint)
	_details.cylinder(center + Vector3(0.7, 1.63, 0.3), 0.045, 0.3, _dark_metal)
	_details.valve_wheel(center + Vector3(0.7, 1.79, 0.3), 0.28, _paint)
	_details.box(center + Vector3(0.75, 0.75, -0.88), Vector3(1.0, 1.3, 0.55), _dark_metal)
	_details.box(center + Vector3(0.75, 0.76, -1.18), Vector3(0.9, 1.17, 0.07), _metal)
	_details.box(center + Vector3(1.04, 0.82, -1.24), Vector3(0.055, 0.2, 0.06), _dark_metal)
	_details.box(center + Vector3(0.66, 0.98, -1.224), Vector3(0.23, 0.2, 0.025), _paint)
	for vent in range(4):
		_details.box(center + Vector3(0.72, 0.3 + vent * 0.09, -1.225), Vector3(0.63, 0.035, 0.025), _dark_metal)


func _container_fittings(paint: Material) -> void:
	# ISO-sized shell: continuous side corrugation, corner castings and end doors.
	for side in [-1.0, 1.0]:
		for y in [-1.23, 1.23]:
			_details.box(Vector3(0, y, side * 1.24), Vector3(5.82, 0.14, 0.13), _dark_metal)
		for x in [-2.81, 2.81]:
			_details.box(Vector3(x, 0, side * 1.24), Vector3(0.15, 2.48, 0.14), paint)
			for y in [-1.19, 1.19]:
				_details.box(Vector3(x, y, side * 1.255), Vector3(0.19, 0.19, 0.19), _metal)
				_details.box(Vector3(x, y, side * 1.357), Vector3(0.08, 0.07, 0.015), _dark_metal)
		for rib in range(23):
			var x := -2.64 + rib * 0.24
			_details.box(Vector3(x, 0, side * 1.255), Vector3(0.13, 2.28, 0.065), paint)
	for rib in range(23):
		_details.box(Vector3(-2.64 + rib * 0.24, 1.312, 0), Vector3(0.13, 0.04, 2.26), paint)
	for z in [-0.58, 0.58]:
		_details.box(Vector3(2.915, 0, z), Vector3(0.035, 2.3, 1.13), _dark_metal)
		_details.box(Vector3(2.947, 0, z), Vector3(0.045, 2.19, 1.02), paint)
		for lock_z in [z - 0.29, z + 0.29]:
			_details.pipe(Vector3(3.0, -1.1, lock_z), Vector3(3.0, 1.1, lock_z), 0.025, _metal)
			_details.box(Vector3(3.04, -0.42, lock_z + 0.085), Vector3(0.06, 0.055, 0.2), _dark_metal)
			for clamp_y in [-0.96, -0.35, 0.65, 0.97]:
				_details.box(Vector3(3.01, clamp_y, lock_z), Vector3(0.1, 0.07, 0.13), _metal)
		for hinge_y in [-0.88, 0, 0.88]:
			_details.box(Vector3(2.99, hinge_y, signf(z) * 1.03), Vector3(0.1, 0.1, 0.26), _dark_metal)
		_details.box(Vector3(2.974, 0.57, z), Vector3(0.015, 0.16, 0.4), _paint)
	for rib in range(9):
		_details.box(Vector3(-2.917, 0, -1.02 + rib * 0.255), Vector3(0.065, 2.28, 0.13), paint)


func set_boss_gate_open(open: bool) -> void:
	for bar in boss_gate:
		if not is_instance_valid(bar):
			continue
		bar.visible = not open
		for child in bar.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).collision_layer = 0 if open else 1
