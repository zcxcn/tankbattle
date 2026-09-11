class_name BattlefieldWeather
extends Node3D
## Bounded GPU-instanced rain/snow and pooled rain surface ripples. No per-drop
## nodes, ray casts or physics bodies. The simulation clock follows combat pause.
## Rain noise is synthesized here from a deterministic seed: original audio.

const RAIN_SHADER = preload("res://assets/shaders/battlefield_rain.gdshader")
const SNOW_SHADER = preload("res://assets/shaders/battlefield_snow.gdshader")
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
const MAX_SNOWFLAKES := 2300

var game: Node
var kind := "light_rain"
var elapsed := 0.0
var rain: MultiMeshInstance3D
var snow: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var puddles: MultiMeshInstance3D
var puddle_transforms: Array[Transform3D] = []
var rain_audio: AudioStreamPlayer
var roof_image: Image
var roof_texture: ImageTexture
var surface_image: Image
var surface_texture: ImageTexture
var _rain_material: ShaderMaterial
var _snow_material: ShaderMaterial
var _splash_material: ShaderMaterial
var _puddle_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _follow_target := Vector3.ZERO
var _surface_low := 0.075
var _surface_high := 0.075


func _ready() -> void:
	_rng.seed = 426190
	_build_roof_heightmap()
	if kind == "snow":
		_build_snow()
	else:
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
	for surface in [_rain_material, _splash_material, _snow_material]:
		if is_instance_valid(surface):
			surface.set_shader_parameter("field_center", center)
	var aabb := AABB(Vector3(center.x - FIELD_RADIUS - 4, _surface_low - 1.0, center.y - FIELD_RADIUS - 4), Vector3(FIELD_RADIUS * 2 + 8, RAIN_HEIGHT + _surface_high - _surface_low + 4, FIELD_RADIUS * 2 + 8))
	for batch in [rain, splashes, snow]:
		if is_instance_valid(batch):
			batch.custom_aabb = aabb


func _update_clock() -> void:
	for surface in [_rain_material, _splash_material, _puddle_material, _snow_material]:
		if is_instance_valid(surface):
			surface.set_shader_parameter("rain_time", elapsed)


func _build_snow() -> void:
	_snow_material = _common_material(SNOW_SHADER)
	_snow_material.set_shader_parameter("fall_height", RAIN_HEIGHT)
	_snow_material.set_shader_parameter("fall_speed", 1.55)
	var mesh := QuadMesh.new()
	# Soft irregular flakes have almost equal width/height: never rain streaks.
	mesh.size = Vector2(0.12, 0.12)
	var amount := int(MAX_SNOWFLAKES * (0.65 if SettingsService.quality == 0 else 1.0))
	snow = _instance_batch("SnowFlakes", mesh, amount, _snow_material)
	for index in amount:
		snow.multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		snow.multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))


func _common_material(shader: Shader) -> ShaderMaterial:
	var surface := ShaderMaterial.new()
	surface.shader = shader
	surface.set_shader_parameter("roof_height", roof_texture)
	surface.set_shader_parameter("surface_height", surface_texture)
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
	puddle_transforms.clear()
	for index in MAX_PUDDLES:
		# A complete puddle must rest on one exposed, nearly level road surface.
		# Checking the footprint also rejects a dry centre with corners over water.
		var transform := Transform3D.IDENTITY
		for attempt in 64:
			var x: float
			var z: float
			if index % 2 == 0:
				x = [-96.0, 0.0, 96.0][index % 3] + _rng.randf_range(-7.0, 7.0)
				z = _rng.randf_range(-180.0, 180.0)
			else:
				x = _rng.randf_range(-135.0, 135.0)
				z = [-144.0, -72.0, 0.0, 72.0, 144.0][index % 5] + _rng.randf_range(-6.0, 6.0)
			var size := Vector3(_rng.randf_range(2.3, 6.4), 1.0, _rng.randf_range(1.2, 3.2))
			transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(size), Vector3(x, 0, z))
			if _puddle_supported(transform):
				break
		if not _puddle_supported(transform):
			# All campaign intersections are authored open ground. Keep the fixed
			# instance budget even if a future parcel consumes many road margins.
			transform = Transform3D(Basis.IDENTITY.scaled(Vector3(2.3, 1.0, 1.2)), Vector3([-96.0, 0.0, 96.0][index % 3], 0, [-144.0, -72.0, 0.0, 72.0, 144.0][index % 5]))
		transform.origin.y = _authored_surface_height(transform.origin) + 0.008
		# Keep this bounded submission list inspectable without GPU readback.
		puddle_transforms.append(transform)
		puddles.multimesh.set_instance_transform(index, transform)
		puddles.multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))


func _puddle_supported(pose: Transform3D) -> bool:
	var level := _authored_surface_height(pose.origin)
	if level < -0.2:
		return false
	for x in [-0.5, 0.0, 0.5]:
		for z in [-0.5, 0.0, 0.5]:
			var at := pose * Vector3(x, 0.0, z)
			var surface := _authored_surface_height(at)
			if surface < -0.2 or absf(surface - level) > 0.08 or sample_roof_height(at) > surface + 0.3:
				return false
	return true


func _authored_surface_height(at: Vector3) -> float:
	var arena := get_parent()
	return arena.get_surface_height(at) if arena.has_method("get_surface_height") else 0.075


func _build_roof_heightmap() -> void:
	# R holds the actual sky-facing height; G marks a building/roof obstruction.
	# Separate smoothly sampled terrain prevents a curved hill becoming a box
	# shaped rain shelter while keeping conservative, sharp building boundaries.
	roof_image = Image.create(MAP_PIXELS.x, MAP_PIXELS.y, false, Image.FORMAT_RGF)
	surface_image = Image.create(MAP_PIXELS.x, MAP_PIXELS.y, false, Image.FORMAT_RF)
	var arena := get_parent()
	var samples_terrain := arena.has_method("get_surface_height")
	_surface_low = 0.075
	_surface_high = 0.075
	for y in MAP_PIXELS.y:
		for x in MAP_PIXELS.x:
			var point := MAP_ORIGIN + (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(MAP_PIXELS) * MAP_SIZE
			var surface: float = arena.get_surface_height(Vector3(point.x, 0, point.y)) if samples_terrain else 0.075
			roof_image.set_pixel(x, y, Color(surface, 0, 0, 1))
			surface_image.set_pixel(x, y, Color(surface, 0, 0, 1))
			_surface_low = minf(_surface_low, surface)
			_surface_high = maxf(_surface_high, surface)
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
	surface_texture = ImageTexture.create_from_image(surface_image)


func _stamp_roof(bounds: AABB) -> void:
	var start := Vector2(bounds.position.x, bounds.position.z)
	var end := Vector2(bounds.end.x, bounds.end.z)
	var from_pixel := Vector2i(((start - MAP_ORIGIN) / MAP_SIZE * Vector2(MAP_PIXELS)).floor())
	var to_pixel := Vector2i(((end - MAP_ORIGIN) / MAP_SIZE * Vector2(MAP_PIXELS)).ceil())
	for y in range(maxi(0, from_pixel.y), mini(MAP_PIXELS.y, to_pixel.y + 1)):
		for x in range(maxi(0, from_pixel.x), mini(MAP_PIXELS.x, to_pixel.x + 1)):
			if bounds.end.y > roof_image.get_pixel(x, y).r:
				roof_image.set_pixel(x, y, Color(bounds.end.y, 1, 0, 1))


func sample_roof_height(at: Vector3) -> float:
	var uv := (Vector2(at.x, at.z) - MAP_ORIGIN) / MAP_SIZE
	var pixel := Vector2i((uv * Vector2(MAP_PIXELS)).floor())
	var sky := roof_image.get_pixel(clampi(pixel.x, 0, MAP_PIXELS.x - 1), clampi(pixel.y, 0, MAP_PIXELS.y - 1))
	return sky.r if sky.g > 0.5 else sample_surface_height(at)


func sample_surface_height(at: Vector3) -> float:
	# Match the shader's linear filtering at texel centres, including map edges.
	var pixel := ((Vector2(at.x, at.z) - MAP_ORIGIN) / MAP_SIZE * Vector2(MAP_PIXELS) - Vector2.ONE * 0.5).clamp(Vector2.ZERO, Vector2(MAP_PIXELS - Vector2i.ONE))
	var cell := Vector2i(pixel.floor())
	var next := (cell + Vector2i.ONE).min(MAP_PIXELS - Vector2i.ONE)
	var blend := pixel - Vector2(cell)
	return lerpf(lerpf(surface_image.get_pixel(cell.x, cell.y).r, surface_image.get_pixel(next.x, cell.y).r, blend.x), lerpf(surface_image.get_pixel(cell.x, next.y).r, surface_image.get_pixel(next.x, next.y).r, blend.x), blend.y)


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
		"drops": rain.multimesh.instance_count if is_instance_valid(rain) else 0,
		"snowflakes": snow.multimesh.instance_count if is_instance_valid(snow) else 0,
		"splashes": splashes.multimesh.instance_count if is_instance_valid(splashes) else 0,
		"puddles": puddles.multimesh.instance_count if is_instance_valid(puddles) else 0,
		"draw_batches": 1 if kind == "snow" else 3, "roof_resolution": MAP_PIXELS,
		"audio_paused": rain_audio.stream_paused if is_instance_valid(rain_audio) else true,
	}
