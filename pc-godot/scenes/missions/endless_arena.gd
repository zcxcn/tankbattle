extends IndustrialArena
## A dedicated siege boulevard: three broad approach lanes and a shelter front.

func _ready() -> void:
	_district = 2
	_asphalt = ArtFactory.pbr_terrain_material("res://assets/materials/polyhaven/asphalt_01/asphalt_01_diff_1k.jpg", "res://assets/materials/polyhaven/asphalt_01/asphalt_01_nor_gl_1k.jpg", "res://assets/materials/polyhaven/asphalt_01/asphalt_01_rough_1k.jpg", Color("737d80"), 0.16, 0.65)
	_concrete = ArtFactory.pbr_terrain_material("res://assets/materials/polyhaven/rough_concrete/rough_concrete_diff_1k.jpg", "res://assets/materials/polyhaven/rough_concrete/rough_concrete_nor_gl_1k.jpg", "res://assets/materials/polyhaven/rough_concrete/rough_concrete_rough_1k.jpg", Color("8a8e88"), 0.14, 0.68)
	_building = _concrete.duplicate()
	_metal = _weathered_steel(Color("727b7c"))
	_dark_metal = _weathered_steel(Color("333d41"))
	_paint = _weathered_steel(Color("b98442"))
	_glass = ArtFactory.material(Color("354952"), 0.48, 0.24)
	_lamp_lens = ArtFactory.material(Color("ffe3b3"), 0.0, 0.3, 2.3)
	_details = DetailsBuilder.new()
	_city = CityBuilder.new()
	_build_environment()
	var environment: Environment = get_node("WorldEnvironment").environment
	environment.tonemap_exposure = 0.98
	environment.fog_density = 0.0019
	environment.volumetric_fog_density = 0.0035
	ArtFactory.add_box(self, "BoulevardFoundation", Vector3(0, -0.45, 0), Vector3(220, 0.8, 300), _concrete, true)
	ArtFactory.add_box(self, "SiegeAvenue", Vector3(0, 0.015, -4), Vector3(112, 0.05, 286), _asphalt)
	var stripe := ArtFactory.material(Color("c5bca0"), 0.0, 0.8)
	for x in [-45.0, -16.0, 16.0, 45.0]:
		for z in range(-140, 110, 9):
			_details.box(Vector3(x, 0.052, z), Vector3(0.18, 0.016, 4.2), stripe)
	for side in [-1.0, 1.0]:
		for index in 5:
			var at := Vector3(side * 76, 0, -108 + index * 49)
			_city.build(self, at, 30, 34, float([54, 78, 46, 65, 42][index]), index % 3)
			_details.box(at + Vector3(0, 0.12, 0), Vector3(38, 0.24, 42), _concrete)
			_street_lamp(Vector3(side * 53, 0, at.z + 20), -side)
		# Sidewall closes noncombat gaps without blocking approach lanes.
		ArtFactory.add_box(self, "QuarantineSidewall", Vector3(side * 105, 3, 0), Vector3(1.5, 6, 296), _concrete, true)
	for z in [-150.0, 149.0]:
		ArtFactory.add_box(self, "QuarantinePerimeter", Vector3(0, 3, z), Vector3(210, 6, 1.5), _concrete, true)
	_build_shelter()
	# Small cover stays outside the giant lanes; tanks may flank through 14m gaps.
	for side in [-1.0, 1.0]:
		for z in [-8.0, 61.0]:
			ArtFactory.add_box(self, "RoadBlock", Vector3(side * 50, 0.65, z), Vector3(4, 1.3, 8), _concrete, true)
	_weather_roofs.append_array(_city.roofs)
	_details.bake(self)
	_details = null
	set_meta("arena_bounds", get_radar_bounds())
	set_meta("endless_arena", true)
	_capture_weather_baseline()
	_build_weather()

func _build_shelter() -> void:
	var refuge := Node3D.new()
	refuge.name = "EvacuationShelter"
	add_child(refuge)
	ArtFactory.add_box(refuge, "ShelterBunker", Vector3(0, 5, 131), Vector3(98, 10, 24), _concrete, true)
	_weather_roofs.append(AABB(Vector3(-49, 0, 119), Vector3(98, 10, 24)))
	for x in [-31.0, 0.0, 31.0]:
		ArtFactory.add_box(refuge, "BlastDoorFrame", Vector3(x, 4.2, 118.6), Vector3(20, 8.4, 0.9), _dark_metal)
		for panel in 8:
			_details.box(Vector3(x - 8.4 + panel * 2.4, 3.8, 118), Vector3(2.2, 7.2, 0.6), _metal)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 9.5, 115)
		lamp.light_color = Color("86dbc9")
		lamp.light_energy = 3.2
		lamp.omni_range = 18
		refuge.add_child(lamp)
		_details.box(Vector3(x, 8.7, 117.8), Vector3(14, 0.2, 0.4), ArtFactory.material(Color("63cbb9"), 0, 0.5, 2.0))
	var sign := Label3D.new()
	sign.name = "ShelterSign"
	sign.text = "09 / 避难所防线 / SHELTER"
	sign.font_size = 76
	sign.pixel_size = 0.055
	sign.position = Vector3(0, 12, 118)
	sign.modulate = Color("bfe9dd")
	refuge.add_child(sign)
	for x in range(-46, 47, 4):
		_details.box(Vector3(x, 0.056, 109), Vector3(2, 0.02, 1.5), _paint, Vector3(0, -0.5, 0))
	# Elevated gantries and searchlights make the defended end readable at distance.
	for side in [-1.0, 1.0]:
		_watch_tower(Vector3(side * 48, 0, 110))
		var beam := SpotLight3D.new()
		beam.position = Vector3(side * 42, 13, 117)
		beam.light_color = Color("cee8de")
		beam.light_energy = 8.0
		beam.spot_range = 110
		beam.spot_angle = 25
		refuge.add_child(beam)
		beam.look_at(Vector3(side * 20, 0, 15))

func get_surface_height(_at: Vector3) -> float:
	return 0.05

func get_radar_bounds() -> Rect2:
	return Rect2(-110, -150, 220, 300)
