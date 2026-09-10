class_name IndustrialArena
extends Node3D
## Three authored industrial districts sharing real-world scale modular fittings.

const DetailsBuilder = preload("res://scripts/industrial_details.gd")
const Catalog = preload("res://data/mission_catalog.gd")
const FacadeLibrary = preload("res://scripts/factory_facade_library.gd")
const WeatherScript = preload("res://scripts/battlefield_weather.gd")
const SNOW_COVER_SHADER = preload("res://assets/shaders/snow_cover.gdshader")
const WEATHER_KINDS := ["dry", "light_rain", "heavy_rain", "snow", "fog"]

var game: Node
var mission_index := 0
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
var _district := 0
var _building_types: Array[String] = []
var weather: Node3D
var weather_kind := ""
var _weather_roofs: Array[AABB] = []
var _weather_baseline: Array[Dictionary] = []


func _ready() -> void:
	_district = posmod(mission_index, 3)
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
	_build_landmarks()
	_details.bake(self)
	set_meta("industrial_detail_pieces", _details.piece_count)
	set_meta("mission_index", mission_index)
	set_meta("arena_bounds", get_radar_bounds())
	set_meta("building_types", _building_types)
	_details = null
	_capture_weather_baseline()
	_build_weather()


func _build_weather() -> void:
	var selected_kind := weather_kind
	if selected_kind.is_empty():
		selected_kind = Catalog.get_mission(mission_index).get("weather", "dry")
	set_weather_kind(selected_kind)


func _remember_weather_properties(target: Object, properties: Array) -> void:
	var values := {}
	for property: String in properties:
		values[property] = target.get(property)
	_weather_baseline.append({"target": target, "values": values})


func _capture_weather_baseline() -> void:
	for surface in [_asphalt, _concrete, _building, _metal, _dark_metal]:
		_remember_weather_properties(surface, ["albedo_color", "roughness", "normal_scale", "next_pass"])
	var environment: Environment = get_node("WorldEnvironment").environment
	_remember_weather_properties(environment, ["ambient_light_energy", "fog_light_color", "fog_density", "volumetric_fog_density", "fog_sky_affect", "volumetric_fog_sky_affect"])
	_remember_weather_properties(environment.sky.sky_material, ["sky_top_color", "sky_horizon_color"])
	_remember_weather_properties(get_node("LowSun"), ["light_color", "light_energy", "light_angular_distance"])


func set_weather_kind(value: String) -> void:
	var resolved := value if value in WEATHER_KINDS else "dry"
	if _weather_baseline.is_empty():
		weather_kind = resolved
		return
	if get_meta("weather", "") == resolved:
		return
	# Keep the same arena, enemy actors and authored PBR resources. Only weather
	# nodes and the explicitly recorded atmosphere/material properties change.
	if is_instance_valid(weather):
		weather.free()
	weather = null
	for record in _weather_baseline:
		for property: String in record.values:
			record.target.set(property, record.values[property])
	weather_kind = resolved
	set_meta("weather", weather_kind)
	# The same authored roof volumes drive rain occlusion and dry loading bays.
	set_meta("weather_roofs", _weather_roofs)
	if weather_kind == "dry":
		return
	if weather_kind in ["light_rain", "heavy_rain", "snow"]:
		weather = WeatherScript.new()
		weather.name = "BattlefieldWeather"
		weather.game = game
		weather.kind = weather_kind
		add_child(weather)
	if weather_kind == "snow":
		_apply_snow()
	elif weather_kind == "fog":
		_apply_fog()
	else:
		_apply_rain()


func _apply_rain() -> void:
	_asphalt.albedo_color = Color("687578")
	_asphalt.roughness = 0.28 if weather_kind == "heavy_rain" else 0.43
	_asphalt.normal_scale = 0.46
	_concrete.albedo_color = Color("757e7e")
	_concrete.roughness = 0.63
	var environment: Environment = get_node("WorldEnvironment").environment
	var sky_material: ProceduralSkyMaterial = environment.sky.sky_material
	sky_material.sky_top_color = Color("52616d")
	sky_material.sky_horizon_color = Color("96a4ae")
	environment.ambient_light_energy = 0.92
	environment.fog_light_color = Color("91a4b1")
	environment.fog_density = 0.0025 if weather_kind == "heavy_rain" else 0.0015
	environment.volumetric_fog_density = 0.0045 if weather_kind == "heavy_rain" else 0.003
	var sun: DirectionalLight3D = get_node("LowSun")
	sun.light_color = Color("cbdbe9")
	sun.light_energy = 0.64 if weather_kind == "heavy_rain" else 0.82
	sun.light_angular_distance = 1.4


func _apply_snow() -> void:
	var cover := ShaderMaterial.new()
	cover.shader = SNOW_COVER_SHADER
	cover.set_shader_parameter("roof_height", weather.roof_texture)
	cover.set_shader_parameter("map_origin", WeatherScript.MAP_ORIGIN)
	cover.set_shader_parameter("map_size", WeatherScript.MAP_SIZE)
	# The extra pass only coats upward, sky-exposed faces. Original texture,
	# normals and imported building materials are left intact underneath.
	for surface in [_asphalt, _concrete, _building, _metal, _dark_metal]:
		surface.next_pass = cover
	_asphalt.albedo_color = Color("8b989f")
	_asphalt.roughness = 0.86
	_concrete.albedo_color = Color("a3a9ad")
	var environment: Environment = get_node("WorldEnvironment").environment
	var sky_material: ProceduralSkyMaterial = environment.sky.sky_material
	sky_material.sky_top_color = Color("748796")
	sky_material.sky_horizon_color = Color("b5c4cd")
	environment.ambient_light_energy = 0.96
	environment.fog_light_color = Color("b3c5d1")
	environment.fog_density = 0.0024
	environment.volumetric_fog_density = 0.0038
	var sun: DirectionalLight3D = get_node("LowSun")
	sun.light_color = Color("deebf5")
	sun.light_energy = 0.72
	sun.light_angular_distance = 1.65


func _apply_fog() -> void:
	var environment: Environment = get_node("WorldEnvironment").environment
	var sky_material: ProceduralSkyMaterial = environment.sky.sky_material
	sky_material.sky_top_color = Color("899396")
	sky_material.sky_horizon_color = Color("b7bfbe")
	environment.ambient_light_energy = 0.85
	environment.fog_light_color = Color("a5b4b7")
	environment.fog_density = 0.0085
	environment.volumetric_fog_density = 0.010
	environment.fog_sky_affect = 0.65
	environment.volumetric_fog_sky_affect = 0.62
	var sun: DirectionalLight3D = get_node("LowSun")
	sun.light_color = Color("dbe2df")
	sun.light_energy = 0.55
	sun.light_angular_distance = 2.0


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
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = [Color("566b79"), Color("687d8f"), Color("4b5967")][_district]
	sky_material.sky_horizon_color = [Color("abb4b5"), Color("d0c3ac"), Color("afb2b5")][_district]
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
	environment.fog_density = 0.0008 if _district == 1 else 0.0012
	environment.fog_sky_affect = 0.32
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0025 if _district == 1 else 0.0032
	environment.volumetric_fog_length = 180.0
	environment.volumetric_fog_sky_affect = 0.24
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "LowSun"
	sun.rotation_degrees = [Vector3(-52, -32, 0), Vector3(-32, 48, 0), Vector3(-44, -70, 0)][_district]
	sun.light_color = [Color("fff1dd"), Color("ffe1b7"), Color("e9f0ff")][_district]
	sun.light_energy = 1.10 if _district == 2 else 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 190.0
	sun.directional_shadow_fade_start = 0.72
	add_child(sun)


func _build_ground() -> void:
	ArtFactory.add_box(self, "Terrain", Vector3(0, -0.45, 0), Vector3(290, 0.8, 386), _concrete, true)
	for x in [-96.0, 0.0, 96.0]:
		ArtFactory.add_box(self, "MainAvenue", Vector3(x, 0.015, 0), Vector3(24 if x == 0 else 20, 0.05, 380), _asphalt)
	for z in [-144.0, -72.0, 0.0, 72.0, 144.0]:
		ArtFactory.add_box(self, "CrossStreet", Vector3(0, 0.025, z), Vector3(282, 0.06, 18), _asphalt)
	var stripe := ArtFactory.material(Color("d3bd72"), 0.05, 0.6, 0.12)
	for x in [-96.0, 0.0, 96.0]:
		for z in range(-184, 185, 8):
			_details.box(Vector3(x, 0.065, float(z)), Vector3(0.18, 0.025, 3.4), stripe)
	for z in [-144.0, -72.0, 0.0, 72.0, 144.0]:
		for x in range(-136, 137, 8):
			_details.box(Vector3(float(x), 0.07, z), Vector3(3.3, 0.025, 0.16), stripe)
	# Loading aprons, kerbs and drainage sit outside the three clear vehicle lanes.
	for side in [-1.0, 1.0]:
		for z in [-108.0, -36.0, 36.0, 108.0]:
			_details.box(Vector3(side * 48, 0.04, z), Vector3(66, 0.04, 48), _asphalt)
			for dz in [-25.0, 25.0]:
				_details.box(Vector3(side * 48, 0.15, z + dz), Vector3(64, 0.24, 0.4), _concrete)
			_details.box(Vector3(side * 82, 0.04, z), Vector3(0.4, 0.06, 44), _dark_metal)


func _build_boundaries() -> void:
	for data in [
		[Vector3(0, 2.1, -192), Vector3(288, 4.2, 1.3)],
		[Vector3(0, 2.1, 192), Vector3(288, 4.2, 1.3)],
		[Vector3(-144, 2.1, 0), Vector3(1.3, 4.2, 384)],
		[Vector3(144, 2.1, 0), Vector3(1.3, 4.2, 384)],
	]:
		ArtFactory.add_box(self, "PerimeterWall", data[0], data[1], _concrete, true)
	for x in range(-140, 141, 12):
		for z in [-191.1, 191.1]:
			_details.box(Vector3(float(x), 2.5, z), Vector3(1.1, 5, 1.6), _metal)
	for z in range(-180, 181, 12):
		for x in [-143.1, 143.1]:
			_details.box(Vector3(x, 2.5, float(z)), Vector3(1.6, 5, 1.1), _metal)
	for x in [-7.5, -4.5, -1.5, 1.5, 4.5, 7.5]:
		var gate_bar := ArtFactory.add_box(self, "BossGate", Vector3(x, 2.25, -156.0), Vector3(0.32, 4.5, 1.0), _metal, true)
		boss_gate.append(gate_bar)
	for side in [-1.0, 1.0]:
		ArtFactory.add_box(self, "GateHouse", Vector3(side * 21, 3.0, -158), Vector3(12, 6, 10), _building, true)
		_details.box(Vector3(side * 21, 6.15, -158), Vector3(13, 0.3, 11), _dark_metal)
		_details.box(Vector3(side * 21, 3.9, -152.92), Vector3(8, 1.4, 0.12), _glass)


func _build_industrial_blocks() -> void:
	var buildings: Array = []
	for row in range(4):
		var z := -108.0 + row * 72.0
		for side in [-1.0, 1.0]:
			if _district == 1 and side > 0:
				continue # This district's eastern parcels are working container yards.
			if _district == 2 and row % 2 == 0:
				# Two independent magazines per parcel create traversable inner courtyards.
				for x in [34.0, 64.0]:
					buildings.append([Vector3(side * x, 3.0, z), Vector3(20, 6, 28)])
				continue
			var height := 8.0 + float((row + int(side)) % 3) * 1.3
			if _district == 2:
				height = 6.2 + row * 0.6
			var width := 44.0 + 2.0 * (row % 3)
			var depth := 24.0 + 2.0 * (row % 2)
			buildings.append([Vector3(side * 48, height * 0.5, z), Vector3(width, height, depth)])
	for side in [-1.0, 1.0]:
		buildings.append([Vector3(side * 55, 5.0, 175), Vector3(42, 10, 20)])
		if _district != 1:
			buildings.append([Vector3(side * 58, 7.0, -174), Vector3(42, 14, 20)])
	for index in range(buildings.size()):
		var data: Array = buildings[index]
		_construct_building(data[0], data[1], index)
	_details.placement = Transform3D.IDENTITY


func _warehouse_fittings(size: Vector3) -> void:
	var roof_y := size.y * 0.5
	var floor_y := -size.y * 0.5
	_details.box(Vector3(0, roof_y + 0.12, 0), Vector3(size.x + 0.35, 0.24, size.z + 0.35), _dark_metal)
	for side in [-1.0, 1.0]:
		var face_z: float = side * (size.z * 0.5 + 0.06)
		_details.box(Vector3(0, floor_y + 0.35, face_z), Vector3(size.x, 0.7, 0.16), _concrete)
		_details.box(Vector3(0, roof_y - 0.2, face_z), Vector3(size.x + 0.5, 0.4, 0.32), _metal)
		var columns := 2 if size.x < 28.0 else 3
		for column in range(-columns, columns + 1):
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
		Vector3(-14, 0, 130), Vector3(14, 0, 92), Vector3(-14, 0, 54), Vector3(14, 0, 16),
		Vector3(-14, 0, -20), Vector3(14, 0, -58), Vector3(-14, 0, -96), Vector3(14, 0, -130),
		Vector3(-81, 0, 54), Vector3(81, 0, 18), Vector3(-81, 0, -56), Vector3(81, 0, -130),
		Vector3(-116, 0, 122), Vector3(116, 0, 84), Vector3(-116, 0, -84), Vector3(116, 0, -152),
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
	for z in [-132, -60, 12, 84, 156]:
		for side in [-1.0, 1.0]:
			var center := Vector3(side * 15.2, 0, float(z))
			_street_lamp(center, side)
	for z in [-120.0, 24.0, 120.0]:
		for side in [-1.0, 1.0]:
			_utility_station(Vector3(side * 78.0, 0, z))
	var container_paints: Array[StandardMaterial3D] = [
		_weathered_steel(Color("7b4b39")),
		_weathered_steel(Color("49616b")),
		_weathered_steel(Color("626952")),
	]
	# Keep complete containers in the loading aprons instead of intersecting warehouses.
	var container_rows := [-128.0, -88.0, -56.0, -16.0, 16.0, 56.0, 88.0, 128.0]
	for index in range(16):
		var side := -1.0 if index % 2 == 0 else 1.0
		_add_container(Vector3(side * 60, 1.3, container_rows[index >> 1]), container_paints[index % 3], index)
	if _district == 1:
		for row in range(4):
			for column in range(4):
				var z := -108.0 + row * 72.0
				var x := 29.0 + column * 13.0
				for dz in [-7.0, 7.0]:
					_add_container(Vector3(x, 1.3, z + dz), container_paints[(row + column) % 3], 16 + row * 8 + column * 2 + int(dz > 0))
				if column % 2 == row % 2:
					_add_container(Vector3(x, 3.9, z - 7), container_paints[(row + column + 1) % 3], 48 + row * 4 + column)
	_details.placement = Transform3D.IDENTITY


func _fortification_fittings(size: Vector3) -> void:
	var top := size.y * 0.5
	# Thick blast parapets, roof access and shielded window apertures distinguish the forts.
	for side in [-1.0, 1.0]:
		_details.box(Vector3(0, top + 0.63, side * (size.z * 0.5 - 0.2)), Vector3(size.x + 0.6, 1.0, 0.75), _concrete)
		_details.box(Vector3(side * (size.x * 0.5 - 0.2), top + 0.63, 0), Vector3(0.75, 1.0, size.z + 0.6), _concrete)
		for x in [-size.x * 0.32, 0.0, size.x * 0.32]:
			_details.box(Vector3(x, top - 1.9, side * (size.z * 0.5 + 0.24)), Vector3(3.8, 0.16, 0.65), _dark_metal)
			_details.box(Vector3(x, top - 2.65, side * (size.z * 0.5 + 0.18)), Vector3(3.8, 0.5, 0.45), _concrete)
		for z in [-size.z * 0.3, size.z * 0.3]:
			_details.box(Vector3(side * (size.x * 0.5 + 0.3), -0.6, z), Vector3(0.6, size.y - 1.5, 1.1), _concrete)
	_details.box(Vector3(size.x * 0.32, top + 0.25, size.z * 0.25), Vector3(2.4, 0.35, 2.4), _dark_metal)
	_details.cylinder(Vector3(size.x * 0.32, top + 0.48, size.z * 0.25), 0.55, 0.12, _metal)


func _add_container(at: Vector3, paint: Material, index: int) -> void:
	var container := ArtFactory.add_box(self, "Container_%02d" % index, at, Vector3(5.8, 2.6, 2.45), paint, true)
	container.rotation.y = PI if index % 2 == 0 else 0.0
	_details.placement = container.transform
	_container_fittings(paint)
	_details.placement = Transform3D.IDENTITY


func _build_landmarks() -> void:
	match _district:
		1:
			# The quay and water are beyond the perimeter: every playable road stays solid.
			var water := ArtFactory.material(Color("264753"), 0.3, 0.18)
			ArtFactory.add_box(self, "HarborWater", Vector3(208, -0.22, 0), Vector3(124, 0.1, 420), water)
			for z in [-108.0, 36.0, 108.0]:
				_port_crane(Vector3(124, 0, z))
			for z in range(-174, 175, 24):
				_details.cylinder(Vector3(140, 0.75, float(z)), 0.7, 1.5, _dark_metal)
				_details.cylinder(Vector3(140, 1.5, float(z)), 0.95, 0.25, _metal)
		2:
			for side in [-1.0, 1.0]:
				for z in [-108.0, 36.0, 108.0]:
					_watch_tower(Vector3(side * 125, 0, z))
				for z in [-36.0, 108.0]:
					# Cast revetments around the outer forts have gaps aligned to cross streets.
					ArtFactory.add_box(self, "FortRevetment", Vector3(side * 126, 2, z + 23), Vector3(20, 4, 2.4), _concrete, true)
			_radar_mast(Vector3(58, 14.2, -174))
		_:
			for z in [-108.0, 36.0]:
				for x in [-125.0, 125.0]:
					_storage_tank(Vector3(x, 0, z))
			_radar_mast(Vector3(-58, 14.2, -174))
	_details.placement = Transform3D.IDENTITY


func _port_crane(center: Vector3) -> void:
	for dx in [-7.0, 7.0]:
		for dz in [-8.0, 8.0]:
			ArtFactory.add_box(self, "CraneFoot", center + Vector3(dx, 1.0, dz), Vector3(2.3, 2, 3), _concrete, true)
			ArtFactory.add_box(self, "CraneLeg", center + Vector3(dx, 10.0, dz), Vector3(0.9, 18, 0.9), _paint, true)
		_details.box(center + Vector3(dx, 19.4, 0), Vector3(1.2, 1.8, 20), _paint)
	for z in [-8.0, 8.0]:
		_details.box(center + Vector3(5, 20.2, z), Vector3(31, 1.2, 1.1), _paint)
		_details.pipe(center + Vector3(-7, 19, z), center + Vector3(7, 11, z), 0.16, _metal)
	_details.box(center + Vector3(-5.0, 17, 0), Vector3(3.5, 3, 3), _dark_metal)
	_details.box(center + Vector3(-6.81, 17.3, 0), Vector3(0.08, 1.4, 2.65), _glass)
	for z in [-3.0, 3.0]:
		_details.pipe(center + Vector3(0, 20, z), center + Vector3(0, 8, z), 0.055, _dark_metal)
	_details.box(center + Vector3(0, 8, 0), Vector3(3, 0.5, 7), _paint)


func _watch_tower(center: Vector3) -> void:
	for dx in [-3.0, 3.0]:
		for dz in [-3.0, 3.0]:
			ArtFactory.add_box(self, "TowerLeg", center + Vector3(dx, 5.0, dz), Vector3(0.7, 10, 0.7), _metal, true)
		_details.pipe(center + Vector3(dx, 1.5, -3), center + Vector3(dx, 8.5, 3), 0.14, _dark_metal)
	_details.box(center + Vector3(0, 10, 0), Vector3(8, 0.4, 8), _concrete)
	_details.box(center + Vector3(0, 11.2, 0), Vector3(5.4, 2.2, 5.4), _dark_metal)
	for side in [-1.0, 1.0]:
		_details.box(center + Vector3(0, 11.5, side * 2.75), Vector3(4.7, 0.95, 0.09), _glass)
		_details.box(center + Vector3(side * 2.75, 11.5, 0), Vector3(0.09, 0.95, 4.7), _glass)
	_details.box(center + Vector3(0, 12.5, 0), Vector3(6.2, 0.28, 6.2), _metal)
	_details.pipe(center + Vector3(0, 12.6, 0), center + Vector3(0, 18, 0), 0.07, _dark_metal)
	_details.cylinder(center + Vector3(0, 18.1, 0), 0.14, 0.16, _lamp_lens)


func _storage_tank(center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "StorageTankCollision"
	body.position = center + Vector3(0, 5, 0)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 6.8
	cylinder.height = 10.0
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)
	_details.cylinder(center + Vector3(0, 0.22, 0), 7.2, 0.44, _concrete)
	_details.cylinder(center + Vector3(0, 5.1, 0), 6.7, 9.8, _metal)
	_details.dome(center + Vector3(0, 10, 0), Vector3(6.7, 1.2, 6.7), _metal)
	for y in [0.5, 3.2, 6.1, 9.5]:
		_details.cylinder(center + Vector3(0, y, 0), 6.79, 0.11, _dark_metal)
	for y in range(1, 11):
		_details.box(center + Vector3(-6.8, float(y), 0), Vector3(0.25, 0.09, 0.9), _dark_metal)
	for z in [-0.47, 0.47]:
		_details.pipe(center + Vector3(-6.8, 0.3, z), center + Vector3(-6.8, 10.6, z), 0.055, _dark_metal)


func _radar_mast(center: Vector3) -> void:
	_details.cylinder(center + Vector3(0, 5, 0), 0.26, 10, _dark_metal)
	for side in [-1.0, 1.0]:
		_details.pipe(center + Vector3(side * 4, 0, 0), center + Vector3(0, 8, 0), 0.065, _metal)
		_details.pipe(center + Vector3(0, 0, side * 4), center + Vector3(0, 8, 0), 0.065, _metal)
	_details.box(center + Vector3(0, 9.5, 0), Vector3(7, 2.2, 0.4), _metal, Vector3(0, 0.28, 0))
	for x in range(-3, 4):
		_details.box(center + Vector3(float(x), 9.5, -0.32), Vector3(0.11, 2.4, 0.17), _dark_metal)
	_details.cylinder(center + Vector3(0, 10.85, 0), 0.13, 0.2, _lamp_lens)


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


func get_radar_bounds() -> Rect2:
	return Catalog.ARENA_BOUNDS


func get_spawn_candidates() -> Array[Vector3]:
	# Authored road axes are clear before the first physics synchronization.
	# The 6.6 m tank-envelope sweep in mission_navigation_test verifies these
	# exact points and every route to the adjoining intersection in all districts.
	var points: Array[Vector3] = []
	for x in [-96.0, 0.0, 96.0]:
		for z in range(-144, 145, 12):
			points.append(Vector3(x, 0.05, float(z)))
	for z in [-144.0, -72.0, 0.0, 72.0, 144.0]:
		for x in range(-132, 133, 12):
			var point := Vector3(float(x), 0.05, z)
			if not points.has(point):
				points.append(point)
	return points



func _construct_building(at: Vector3, footprint: Vector3, index: int) -> void:
	var kinds := ["warehouse", "factory", "office", "apartment", "hangar", "substation", "garage"]
	var kind: String = kinds[(index + mission_index * 2) % kinds.size()]
	if not _building_types.has(kind):
		_building_types.append(kind)
	var height: float = {"warehouse": 6.0, "factory": 9.0, "office": 12.0, "apartment": 15.0, "hangar": 6.0, "substation": 6.0, "garage": 6.0}[kind]
	var size := Vector3(footprint.x, height, footprint.z)
	var origin := Vector3(at.x, 0.0, at.z)
	_weather_roofs.append(AABB(origin + Vector3(-size.x * 0.5 - 0.35, 0, -size.z * 0.5 - 0.35), Vector3(size.x + 0.7, height + 0.24, size.z + 0.7)))
	# A dark interior set behind actual modeled openings gives depth to glass.
	# One conservative hull collider per building keeps navigation inexpensive.
	var shell := ArtFactory.add_box(self, kind.capitalize() + "_%02d" % index,
		origin + Vector3(0, height * 0.5, 0), Vector3(size.x - 0.42, height, size.z - 0.42), _dark_metal, true)
	shell.set_meta("building_type", kind)
	var facade := FacadeLibrary.new()
	facade.add_elevation(origin + Vector3(0, 0, size.z * 0.5), size.x, height, 0.0, kind in ["warehouse", "factory", "hangar", "garage"])
	facade.add_elevation(origin + Vector3(0, 0, -size.z * 0.5), size.x, height, PI, kind in ["warehouse", "factory", "hangar", "garage"])
	facade.add_elevation(origin + Vector3(size.x * 0.5, 0, 0), size.z, height, PI * 0.5, false)
	facade.add_elevation(origin + Vector3(-size.x * 0.5, 0, 0), size.z, height, -PI * 0.5, false)
	facade.bake(self, "Facade_%02d" % index)
	_details.placement = Transform3D(Basis.IDENTITY, origin)
	_details.box(Vector3(0, 0.22, 0), Vector3(size.x + 0.28, 0.44, size.z + 0.28), _concrete)
	_details.box(Vector3(0, height + 0.12, 0), Vector3(size.x + 0.65, 0.24, size.z + 0.65), _dark_metal)
	# Roof cornices, drainage and parapets follow the actual perimeter.
	for side in [-1.0, 1.0]:
		_details.box(Vector3(0, height + 0.42, side * size.z * 0.5), Vector3(size.x + 0.65, 0.7, 0.3), _concrete)
		_details.box(Vector3(side * size.x * 0.5, height + 0.42, 0), Vector3(0.3, 0.7, size.z + 0.65), _concrete)
		for z in [-size.z * 0.44, size.z * 0.44]:
			_details.pipe(Vector3(side * (size.x * 0.5 + 0.14), 0.3, z), Vector3(side * (size.x * 0.5 + 0.14), height, z), 0.09, _metal)
	match kind:
		"warehouse", "garage":
			# Loading canopies use steel posts, gutter edges and corrugated roofs.
			for side in [-1.0, 1.0]:
				_details.box(Vector3(0, 3.55, side * (size.z * 0.5 + 0.7)), Vector3(size.x - 2.5, 0.16, 1.6), _metal)
				_weather_roofs.append(AABB(origin + Vector3(-(size.x - 2.5) * 0.5, 0, side * (size.z * 0.5 + 0.7) - 0.8), Vector3(size.x - 2.5, 3.63, 1.6)))
				for x in [-size.x * 0.42, 0.0, size.x * 0.42]:
					_details.pipe(Vector3(x, 2.6, side * size.z * 0.5), Vector3(x, 3.5, side * (size.z * 0.5 + 1.45)), 0.08, _dark_metal)
			_roof_ventilation(size, 3)
		"factory":
			# Brick flue stacks, catwalks and saw-tooth northlights identify process halls.
			for x in [-size.x * 0.32, 0.0, size.x * 0.32]:
				_details.box(Vector3(x, height + 1.35, 0), Vector3(size.x * 0.24, 0.2, size.z * 0.72), _metal, Vector3(0, 0, -0.16))
				_details.box(Vector3(x + size.x * 0.12, height + 0.8, 0), Vector3(0.12, 1.5, size.z * 0.72), _glass)
			for x in [-size.x * 0.36, size.x * 0.36]:
				_details.cylinder(Vector3(x, height + 6.0, -size.z * 0.3), 1.18, 12.0, _building, 0.7)
				_details.cylinder(Vector3(x, height + 12.0, -size.z * 0.3), 0.9, 0.55, _dark_metal)
				for y in [height + 3.0, height + 6.0, height + 9.0]:
					_details.cylinder(Vector3(x, y, -size.z * 0.3), 1.15, 0.16, _metal, 0.95)
		"office":
			_roof_ventilation(size, 2)
			# Setback glazed stair core breaks up the solid silhouette.
			_details.box(Vector3(size.x * 0.27, height + 2.0, 0), Vector3(size.x * 0.32, 4.0, size.z * 0.62), _glass)
			for y in [height, height + 2.0, height + 4.0]:
				_details.box(Vector3(size.x * 0.27, y, 0), Vector3(size.x * 0.33, 0.2, size.z * 0.64), _concrete)
			for z in [-size.z * 0.32, size.z * 0.32]:
				for x in [size.x * 0.11, size.x * 0.27, size.x * 0.43]:
					_details.box(Vector3(x, height + 2.0, z), Vector3(0.13, 4.0, 0.13), _metal)
		"apartment":
			_roof_ventilation(size, 1)
			# Repeated balconies have solid slabs, open railings and side privacy walls.
			for side in [-1.0, 1.0]:
				for floor in range(1, 5):
					for x in [-size.x * 0.32, 0.0, size.x * 0.32]:
						var y := float(floor) * 3.0
						var z: float = side * (size.z * 0.5 + 0.6)
						_details.box(Vector3(x, y, z), Vector3(3.2, 0.18, 1.4), _concrete)
						_details.pipe(Vector3(x - 1.5, y + 1.0, z + side * 0.65), Vector3(x + 1.5, y + 1.0, z + side * 0.65), 0.045, _metal)
						for rail in range(9):
							_details.box(Vector3(x - 1.5 + float(rail) * 0.375, y + 0.54, z + side * 0.65), Vector3(0.045, 0.9, 0.045), _dark_metal)
		"hangar":
			# Match the curved roof instead of letting drops enter the arch volume.
			for band in range(24):
				var roof_radius := size.z * 0.48
				var band_z := -roof_radius + (float(band) + 0.5) * roof_radius * 2.0 / 24.0
				var roof_height := height + sqrt(maxf(0.0, roof_radius * roof_radius - band_z * band_z)) * 0.38 + 0.1
				_weather_roofs.append(AABB(origin + Vector3(-size.x * 0.5 - 0.2, 0, band_z - roof_radius / 24.0), Vector3(size.x + 0.4, roof_height, roof_radius * 2.0 / 24.0)))
			# A curved standing-seam barrel roof replaces the flat warehouse roofline.
			for side in [-1.0, 1.0]:
				# Closed arch gables seal the barrel roof; no hollow floating roof shell.
				var radius := size.z * 0.48
				for panel in range(40):
					var z := -radius + (float(panel) + 0.5) * radius * 2.0 / 40.0
					var rise := sqrt(maxf(0.0, radius * radius - z * z)) * 0.38
					_details.box(Vector3(side * size.x * 0.5, height + rise * 0.5, z), Vector3(0.2, rise, radius * 2.0 / 40.0 + 0.02), _metal)
				for z in [-radius * 0.5, 0.0, radius * 0.5]:
					var rise := sqrt(maxf(0.0, radius * radius - z * z)) * 0.38
					_details.box(Vector3(side * (size.x * 0.5 + 0.14), height + rise * 0.5, z), Vector3(0.16, rise, 0.14), _dark_metal)
			for strip in range(18):
				var angle := -PI * 0.5 + (float(strip) + 0.5) * PI / 18.0
				var radius := size.z * 0.48
				var z := sin(angle) * radius
				var y := height + cos(angle) * radius * 0.38
				_details.box(Vector3(0, y, z), Vector3(size.x + 0.4, 0.18, PI * radius / 18.0 * 1.05), _metal, Vector3(angle * 0.38, 0, 0))
		"substation":
			_roof_ventilation(size, 2)
			# Roof-mounted transformer assemblies and porcelain insulators.
			for x in [-size.x * 0.28, size.x * 0.28]:
				_details.box(Vector3(x, height + 1.3, 0), Vector3(5.0, 2.6, 4.0), _metal)
				for rib in range(12):
					_details.box(Vector3(x - 2.6 + float(rib) * 0.47, height + 1.4, 0), Vector3(0.16, 2.1, 4.7), _dark_metal)
				for z in [-1.3, 0.0, 1.3]:
					_details.cylinder(Vector3(x, height + 3.3, z), 0.16, 1.5, _concrete)
					for ring in range(5):
						_details.cylinder(Vector3(x, height + 2.8 + float(ring) * 0.19, z), 0.38, 0.09, _concrete)
	_details.placement = Transform3D.IDENTITY
	_details.bake(self, "Architecture_%02d" % index)


func _roof_ventilation(size: Vector3, count: int) -> void:
	for index in range(count):
		var x := (float(index) - float(count - 1) * 0.5) * minf(8.0, size.x / float(count + 1))
		var center := Vector3(x, size.y, 0)
		_details.box(center + Vector3(0, 0.2, 0), Vector3(4.0, 0.4, 3.2), _concrete)
		_details.box(center + Vector3(0, 1.0, 0), Vector3(3.7, 1.2, 2.9), _metal)
		for z in [-0.8, 0.8]:
			_details.cylinder(center + Vector3(0, 1.65, z), 0.6, 0.14, _dark_metal)
			for spoke in range(6):
				_details.box(center + Vector3(0, 1.73, z), Vector3(1.1, 0.03, 0.04), _metal, Vector3(0, float(spoke) * PI / 6.0, 0))
		for rib in range(6):
			_details.box(center + Vector3(1.87, 0.55 + float(rib) * 0.17, 0), Vector3(0.08, 0.05, 2.6), _dark_metal)
