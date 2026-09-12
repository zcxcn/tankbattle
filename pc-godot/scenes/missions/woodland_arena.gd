extends IndustrialArena
## Seventh chapter and directly accessible woodland operation.
const Layout = preload("res://data/woodland_layout.gd")
const WoodlandTerrain = preload("res://scripts/woodland_terrain.gd")
const Forest = preload("res://scripts/woodland_forest.gd")

func _ready() -> void:
	_district = 0
	_asphalt = ArtFactory.pbr_terrain_material("res://assets/materials/polyhaven/asphalt_01/asphalt_01_diff_1k.jpg", "res://assets/materials/polyhaven/asphalt_01/asphalt_01_nor_gl_1k.jpg", "res://assets/materials/polyhaven/asphalt_01/asphalt_01_rough_1k.jpg", Color("aaa38a"), 0.16, 0.82)
	_concrete = ArtFactory.pbr_terrain_material("res://assets/materials/polyhaven/rough_concrete/rough_concrete_diff_1k.jpg", "res://assets/materials/polyhaven/rough_concrete/rough_concrete_nor_gl_1k.jpg", "res://assets/materials/polyhaven/rough_concrete/rough_concrete_rough_1k.jpg", Color("a4a08b"), 0.14, 0.7)
	_building = _concrete.duplicate()
	_metal = _weathered_steel(Color("626f65"))
	_dark_metal = _weathered_steel(Color("363f34"))
	_paint = _weathered_steel(Color("b98442"))
	_glass = ArtFactory.material(Color("354952"), 0.48, 0.24)
	_lamp_lens = ArtFactory.material(Color("ffe3b3"), 0, 0.3, 2.3)
	_city = CityBuilder.new()
	_details = DetailsBuilder.new()
	_build_environment()
	var environment: Environment = get_node("WorldEnvironment").environment
	environment.tonemap_exposure = 1.04
	environment.ambient_light_energy = 0.95
	environment.fog_density = 0.00085
	environment.volumetric_fog_density = 0.0015
	var sky: ProceduralSkyMaterial = environment.sky.sky_material
	sky.sky_top_color = Color("5f8fab")
	sky.sky_horizon_color = Color("c5d4d1")
	sky.ground_horizon_color = Color("93a699")
	sky.ground_bottom_color = Color("748473")
	landscape = WoodlandTerrain.new()
	_landscape_data = landscape.build(self, _concrete, _asphalt, _metal)
	_weather_roofs.append_array(_landscape_data.weather_roofs)
	Forest.new().build(self)
	_build_river_rocks()
	_build_outpost()
	_build_limits()
	_details.bake(self)
	_details = null
	set_meta("woodland_arena", true)
	set_meta("arena_bounds", get_radar_bounds())
	set_meta("river_bounds", Rect2(-144, 22, 288, 28))
	set_meta("bridges", _landscape_data.bridges)
	_capture_weather_baseline()
	_build_weather()

func _build_outpost() -> void:
	for x in [-24.0, 24.0]:
		var at := Layout.ground(Vector3(x, 0, -172))
		ArtFactory.add_box(self, "RidgeCommandBunker", at + Vector3.UP * 2.4, Vector3(10, 4.8, 8), _concrete, true)
		_details.box(at + Vector3(0, 4.9, 0), Vector3(11, 0.3, 9), _dark_metal)
		_details.box(at + Vector3(0, 2.8, 4.1), Vector3(7, 0.9, 0.18), _glass)
		_weather_roofs.append(AABB(at - Vector3(5, 0, 4), Vector3(10, 5.1, 8)))
	for x in [-7.5, -4.5, -1.5, 1.5, 4.5, 7.5]:
		var at := Layout.ground(Vector3(x, 0, -156))
		boss_gate.append(ArtFactory.add_box(self, "WoodlandBossGate", at + Vector3.UP * 2.0, Vector3(0.3, 4, 0.8), _metal, true))

func _build_limits() -> void:
	# Collision-only outer limits lie beyond all roads and clearings.
	for data in [[Vector3(-145, 25, 0), Vector3(2, 80, 390)], [Vector3(145, 25, 0), Vector3(2, 80, 390)], [Vector3(0, 25, -193), Vector3(288, 80, 2)], [Vector3(0, 25, 193), Vector3(288, 80, 2)]]:
		var body := StaticBody3D.new()
		body.name = "WoodlandBoundary"
		body.position = data[0]
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = data[1]
		collision.shape = shape
		body.add_child(collision)
		add_child(body)

func get_surface_height(at: Vector3) -> float:
	if at.z > 22 and at.z < 50:
		return super.get_surface_height(at)
	return Layout.height_at(at.x, at.z) + 0.10

func get_spawn_candidates() -> Array[Vector3]:
	var candidates := super.get_spawn_candidates()
	for index in candidates.size():
		candidates[index] = Layout.ground(candidates[index])
	return candidates
