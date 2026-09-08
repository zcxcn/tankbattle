class_name ExplosionFX
extends Node3D
## Layered one-shot impact: flash, fire, smoke, sparks, dust and local light.

var _age := 0.0
var _duration := 2.8
var _light: OmniLight3D
var _flash: MeshInstance3D
static var _sprite_cache: Dictionary = {}


static func create(at: Vector3, scale_factor := 1.0, destructive := true) -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at
	effect.scale = Vector3.ONE * scale_factor
	effect.set_meta("destructive", destructive)
	return effect


func _ready() -> void:
	add_to_group("combat_effects")
	_light = OmniLight3D.new()
	_light.light_color = Color("ff8a3d")
	_light.light_energy = 14.0
	_light.omni_range = 15.0
	_light.shadow_enabled = false
	_light.position.y = 1.2
	add_child(_light)
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.position.y = 0.8
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2.ONE * 2.1
	var flash_material := _sprite_material("Fire")
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.albedo_color = Color(3.0, 2.3, 1.5, 0.95)
	flash_quad.material = flash_material
	_flash.mesh = flash_quad
	add_child(_flash)
	_spawn_particles("Fire", 30, 0.75, Color("ffcf66"), Color(1.0, 0.12, 0.015, 0.0), 7.5, 3.4, 0.36, true)
	_spawn_particles("Sparks", 40, 0.9, Color("fff1a0"), Color(1.0, 0.22, 0.03, 0.0), 16.0, 0.45, 0.08, false)
	_spawn_particles("Smoke", 24, 2.5, Color(0.16, 0.14, 0.12, 0.78), Color(0.055, 0.06, 0.055, 0.0), 4.2, 1.1, 1.05, true)
	_spawn_particles("Dust", 28, 1.45, Color(0.36, 0.29, 0.19, 0.6), Color(0.18, 0.15, 0.1, 0.0), 9.0, 0.35, 0.58, true, true)
	AudioService.play_3d("explosion" if bool(get_meta("destructive", true)) else "hit", global_position, -2.0)
	if bool(get_meta("destructive", true)):
		AudioService.play_3d("explosion_tail", global_position, -7.0)


func _process(delta: float) -> void:
	_age += delta
	if is_instance_valid(_light):
		_light.light_energy = 14.0 * exp(-_age * 7.5)
		_light.light_color = Color("ffe0aa").lerp(Color("df5629"), clampf(_age * 3.0, 0.0, 1.0))
	if is_instance_valid(_flash):
		_flash.scale = Vector3.ONE * (0.7 + _age * 7.0)
		_flash.visible = _age < 0.16
		((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = exp(-_age * 32.0)
	if _age >= _duration:
		queue_free()


func _spawn_particles(label: String, amount: int, lifetime: float, start: Color, finish: Color, speed: float, gravity: float, size: float, billboard: bool, horizontal := false) -> void:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.96
	particles.randomness = 0.45
	particles.fixed_fps = 30
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-20, -4, -20), Vector3(40, 30, 40))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.55
	process.direction = Vector3(0, 0.2 if horizontal else 1.0, 0)
	process.spread = 88.0 if horizontal else 70.0
	process.initial_velocity_min = speed * 0.55
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, -gravity, 0)
	process.scale_min = size * 0.45
	process.scale_max = size
	process.angle_min = -180.0 if billboard else 0.0
	process.angle_max = 180.0 if billboard else 0.0
	process.angular_velocity_min = -24.0 if billboard else 0.0
	process.angular_velocity_max = 24.0 if billboard else 0.0
	var gradient := Gradient.new()
	gradient.set_color(0, start)
	gradient.set_color(1, finish)
	match label:
		"Fire":
			gradient.set_color(0, Color(2.8, 2.1, 1.2, 0.0))
			gradient.add_point(0.07, Color(2.6, 1.6, 0.65, 0.92))
			gradient.add_point(0.28, Color(1.85, 0.57, 0.08, 0.80))
			gradient.add_point(0.64, Color(0.56, 0.095, 0.02, 0.30))
			gradient.set_color(gradient.get_point_count() - 1, Color(0.16, 0.035, 0.01, 0.0))
			process.damping_min = 4.0
			process.damping_max = 7.0
			process.scale_curve = _growth_curve([Vector2(0.0, 0.28), Vector2(0.22, 1.3), Vector2(0.65, 1.7), Vector2(1.0, 1.4)])
		"Smoke":
			gradient.set_color(0, Color(0.22, 0.19, 0.16, 0.0))
			gradient.add_point(0.12, Color(0.19, 0.17, 0.15, 0.67))
			gradient.add_point(0.55, Color(0.32, 0.30, 0.27, 0.47))
			gradient.set_color(gradient.get_point_count() - 1, Color(0.39, 0.38, 0.35, 0.0))
			process.gravity = Vector3.UP * 0.65
			process.damping_min = 0.8
			process.damping_max = 1.6
			process.scale_curve = _growth_curve([Vector2(0.0, 0.4), Vector2(0.18, 1.0), Vector2(0.65, 2.0), Vector2(1.0, 2.7)])
		"Dust":
			gradient.set_color(0, Color(0.45, 0.37, 0.28, 0.0))
			gradient.add_point(0.12, Color(0.43, 0.35, 0.26, 0.52))
			gradient.add_point(0.5, Color(0.46, 0.40, 0.32, 0.31))
			gradient.set_color(gradient.get_point_count() - 1, Color(0.48, 0.43, 0.36, 0.0))
			# Ground pressure displaces dust radially, replacing the luminous torus.
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_height = 0.04
			process.emission_ring_radius = 0.6
			process.emission_ring_inner_radius = 0.35
			process.initial_velocity_min = 0.0
			process.initial_velocity_max = 0.15
			process.radial_velocity_min = 3.0
			process.radial_velocity_max = 6.0
			process.gravity = Vector3.UP * 0.08
			process.scale_curve = _growth_curve([Vector2(0.0, 0.25), Vector2(0.2, 1.1), Vector2(1.0, 2.4)])
		"Sparks":
			gradient.set_color(0, Color(3.0, 2.1, 0.85, 1.0))
			gradient.add_point(0.35, Color(1.3, 0.35, 0.04, 0.85))
			process.gravity = Vector3.DOWN * 12.0
			process.damping_min = 0.4
			process.damping_max = 1.2
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	ramp.use_hdr = label in ["Fire", "Sparks"]
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 2.2) if label == "Sparks" else Vector2.ONE * (2.1 if label == "Smoke" else 1.65)
	quad.material = _sprite_material(label)
	particles.draw_pass_1 = quad
	add_child(particles)
	particles.emitting = true


static func _sprite_material(label: String) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if label in ["Fire", "Sparks"] else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if label in ["Fire", "Sparks"] else BaseMaterial3D.BLEND_MODE_MIX
	surface.vertex_color_use_as_albedo = true
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.billboard_keep_scale = true
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.albedo_color = Color.WHITE
	surface.albedo_texture = particle_sprite("Fire" if label == "Fire" else ("Sparks" if label == "Sparks" else "Smoke"))
	surface.roughness = 1.0
	surface.metallic_specular = 0.0
	return surface


static func _growth_curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 3.0
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func particle_sprite(kind: String) -> ImageTexture:
	if _sprite_cache.has(kind):
		return _sprite_cache[kind]
	var size := 64 if kind == "Sparks" else 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 701 if kind == "Smoke" else 1729
	noise.frequency = 0.048 if kind == "Smoke" else 0.075
	noise.fractal_octaves = 4
	for y in size:
		for x in size:
			var uv := Vector2(float(x) / float(size - 1), float(y) / float(size - 1)) * 2.0 - Vector2.ONE
			var radius := uv.length()
			var softness := 1.0 - smoothstep(0.12 if kind == "Smoke" else 0.0, 1.0, radius)
			var cloud := clampf(0.65 + noise.get_noise_2d(float(x), float(y)) * 0.9, 0.15, 1.0)
			var alpha := softness * cloud
			if kind == "Sparks":
				alpha = pow(maxf(0.0, 1.0 - absf(uv.x)), 2.5) * (1.0 - smoothstep(0.05, 1.0, absf(uv.y)))
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = "Explosion%sSoftSprite" % kind
	_sprite_cache[kind] = texture
	return texture
