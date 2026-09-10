class_name BattlefieldWeather
extends Node3D
## Two bounded GPU-instanced rain layers and pooled surface ripples. No per-drop
## nodes, ray casts or physics bodies. The simulation clock follows combat pause.
## Rain noise is synthesized here from a deterministic seed: original audio.

const RAIN_SHADER = preload("res://assets/shaders/battlefield_rain.gdshader")
const SPLASH_SHADER = preload("res://assets/shaders/rain_splash.gdshader")
const PUDDLE_SHADER = preload("res://assets/shaders/rain_puddle.gdshader")
const MAP_ORIGIN := Vector2(-145.0, -193.0)
const MAP_SIZE := Vector2(290.0, 386.0)
const MAP_PIXELS := Vector2i(256, 320)
const FIELD_RADIUS := 47.0
const RAIN_HEIGHT := 38.0
const MAX_DROPS := 3200
const MAX_SPLASHES := 260
const MAX_PUDDLES := 84

var game: Node
var kind := "light_rain"
var elapsed := 0.0
var rain: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var puddles: MultiMeshInstance3D
var rain_audio: AudioStreamPlayer
var roof_image: Image
var roof_texture: ImageTexture
var _rain_material: ShaderMaterial
var _splash_material: ShaderMaterial
var _puddle_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _follow_target := Vector3.ZERO


func _ready() -> void:
	_rng.seed = 426190
	_build_roof_heightmap()
	_build_rain()
	_build_splashes()
	_build_puddles()
	_build_audio()
	_sync_follow_target()
	_update_clock()


func _process(delta: float) -> void:
	var active: bool = is_instance_valid(game) and game.has_method("is_combat_running") and game.is_combat_running()
	_sync_follow_target()
	if is_instance_valid(rain_audio):
		rain_audio.stream_paused = not active
	if not active:
		return
	elapsed += delta
	_update_clock()


func _sync_follow_target() -> void:
	if is_instance_valid(game) and is_instance_valid(game.get("player")):
		var target: Node3D = game.get("player")
		_follow_target = target.global_position
	# The camera's visible street ahead stays within a 94m square in either view.
	# Mesh transforms stay fixed: only the field centre is uploaded each frame.
	var center := Vector2(_follow_target.x, _follow_target.z)
	_rain_material.set_shader_parameter("field_center", center)
	_splash_material.set_shader_parameter("field_center", center)
	var aabb := AABB(Vector3(center.x - FIELD_RADIUS - 4, -1, center.y - FIELD_RADIUS - 4), Vector3(FIELD_RADIUS * 2 + 8, RAIN_HEIGHT + 4, FIELD_RADIUS * 2 + 8))
	rain.custom_aabb = aabb
	splashes.custom_aabb = aabb


func _update_clock() -> void:
	for surface in [_rain_material, _splash_material, _puddle_material]:
		surface.set_shader_parameter("rain_time", elapsed)


func _common_material(shader: Shader) -> ShaderMaterial:
	var surface := ShaderMaterial.new()
	surface.shader = shader
	surface.set_shader_parameter("roof_height", roof_texture)
	surface.set_shader_parameter("map_origin", MAP_ORIGIN)
	surface.set_shader_parameter("map_size", MAP_SIZE)
	surface.set_shader_parameter("field_radius", FIELD_RADIUS)
	return surface


func _instance_batch(batch_name: String, mesh: Mesh, amount: int, material: Material) -> MultiMeshInstance3D:
	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_custom_data = true
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = amount
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
	return batch


func _build_rain() -> void:
	_rain_material = _common_material(RAIN_SHADER)
	_rain_material.set_shader_parameter("fall_height", RAIN_HEIGHT)
	_rain_material.set_shader_parameter("rain_strength", 0.88 if kind == "heavy_rain" else 0.68)
	_rain_material.set_shader_parameter("fall_speed", 29.0 if kind == "heavy_rain" else 24.0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.86 if kind == "heavy_rain" else 0.68)
	var amount := MAX_DROPS if kind == "heavy_rain" else 1800
	if SettingsService.quality == 0:
		amount = int(amount * 0.65)
	rain = _instance_batch("RainStreaks", mesh, amount, _rain_material)
	for index in amount:
		rain.multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		rain.multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))


func _build_splashes() -> void:
	_splash_material = _common_material(SPLASH_SHADER)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.8, 0.8)
	var amount := MAX_SPLASHES if kind == "heavy_rain" else 150
	if SettingsService.quality == 0:
		amount = int(amount * 0.65)
	splashes = _instance_batch("RainImpacts", mesh, amount, _splash_material)
	for index in amount:
		splashes.multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		splashes.multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))


func _build_puddles() -> void:
	_puddle_material = ShaderMaterial.new()
	_puddle_material.shader = PUDDLE_SHADER
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	puddles = _instance_batch("RoadPuddles", mesh, MAX_PUDDLES, _puddle_material)
	for index in MAX_PUDDLES:
		var x: float
		var z: float
		if index % 2 == 0:
			x = [-96.0, 0.0, 96.0][index % 3] + _rng.randf_range(-7.0, 7.0)
			z = _rng.randf_range(-180.0, 180.0)
		else:
			x = _rng.randf_range(-135.0, 135.0)
			z = [-144.0, -72.0, 0.0, 72.0, 144.0][index % 5] + _rng.randf_range(-6.0, 6.0)
		var size := Vector3(_rng.randf_range(2.3, 6.4), 1.0, _rng.randf_range(1.2, 3.2))
		var transform := Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(size), Vector3(x, 0.083, z))
		puddles.multimesh.set_instance_transform(index, transform)
		puddles.multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))


func _build_roof_heightmap() -> void:
	roof_image = Image.create(MAP_PIXELS.x, MAP_PIXELS.y, false, Image.FORMAT_RF)
	roof_image.fill(Color(0.075, 0, 0, 1))
	var arena := get_parent()
	for collider in arena.find_children("*", "CollisionShape3D", true, false):
		var body: Node = collider.get_parent()
		# Destructible cover can disappear: don't bake it into the static sky mask.
		if not body is StaticBody3D or body.is_in_group("destructible_cover"):
			continue
		var shape: Shape3D = collider.shape
		if shape is BoxShape3D:
			var bounds: AABB = collider.global_transform * AABB(-shape.size * 0.5, shape.size)
			if bounds.end.y > 0.3:
				_stamp_roof(bounds)
	for bounds: AABB in arena.get_meta("weather_roofs", []):
		_stamp_roof(bounds)
	roof_texture = ImageTexture.create_from_image(roof_image)


func _stamp_roof(bounds: AABB) -> void:
	var start := Vector2(bounds.position.x, bounds.position.z)
	var end := Vector2(bounds.end.x, bounds.end.z)
	var from_pixel := Vector2i(((start - MAP_ORIGIN) / MAP_SIZE * Vector2(MAP_PIXELS)).floor())
	var to_pixel := Vector2i(((end - MAP_ORIGIN) / MAP_SIZE * Vector2(MAP_PIXELS)).ceil())
	for y in range(maxi(0, from_pixel.y), mini(MAP_PIXELS.y, to_pixel.y + 1)):
		for x in range(maxi(0, from_pixel.x), mini(MAP_PIXELS.x, to_pixel.x + 1)):
			if bounds.end.y > roof_image.get_pixel(x, y).r:
				roof_image.set_pixel(x, y, Color(bounds.end.y, 0, 0, 1))


func sample_roof_height(at: Vector3) -> float:
	var uv := (Vector2(at.x, at.z) - MAP_ORIGIN) / MAP_SIZE
	var pixel := Vector2i((uv * Vector2(MAP_PIXELS)).floor())
	return roof_image.get_pixel(clampi(pixel.x, 0, MAP_PIXELS.x - 1), clampi(pixel.y, 0, MAP_PIXELS.y - 1)).r


func _build_audio() -> void:
	# A six-second seamless deterministic filtered-noise bed. Crossfade its wrap
	# to avoid clicks; quiet transient speckles suggest drops on hard surfaces.
	const RATE := 16000
	const FRAMES := RATE * 6
	var samples := PackedFloat32Array()
	samples.resize(FRAMES)
	var noise := RandomNumberGenerator.new()
	noise.seed = 420517
	var low := 0.0
	var drip := 0.0
	for index in FRAMES:
		var white := noise.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.085)
		if noise.randf() < 0.002:
			drip = noise.randf_range(0.15, 0.55)
		drip *= 0.96
		samples[index] = clampf((white * 0.2 + low * 1.4 + white * drip) * 0.56, -0.9, 0.9)
	# The end blends into the start 40ms ahead; the loop begins at that point.
	const CROSSFADE := 640
	for index in CROSSFADE:
		samples[FRAMES - CROSSFADE + index] = lerpf(samples[FRAMES - CROSSFADE + index], samples[index], float(index) / CROSSFADE)
	var bytes := PackedByteArray()
	bytes.resize(FRAMES * 2)
	for index in FRAMES:
		bytes.encode_s16(index * 2, int(samples[index] * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = CROSSFADE
	stream.loop_end = FRAMES
	rain_audio = AudioStreamPlayer.new()
	rain_audio.name = "RainAmbience"
	rain_audio.bus = "SFX"
	rain_audio.volume_db = -18.0 if kind == "heavy_rain" else -23.0
	rain_audio.stream = stream
	add_child(rain_audio)
	rain_audio.play()
	rain_audio.stream_paused = true


func get_snapshot() -> Dictionary:
	return {
		"kind": kind, "elapsed": elapsed, "center": _follow_target,
		"drops": rain.multimesh.instance_count,
		"splashes": splashes.multimesh.instance_count,
		"puddles": puddles.multimesh.instance_count,
		"draw_batches": 3, "roof_resolution": MAP_PIXELS,
		"audio_paused": rain_audio.stream_paused,
	}
