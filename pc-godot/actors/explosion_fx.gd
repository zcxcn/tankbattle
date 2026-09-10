class_name ExplosionFX
extends Node3D
## Layered one-shot impact: flash, fire, smoke, sparks, dust and local light.

var _age := 0.0
var _duration := 4.2
var _light: OmniLight3D
var _flash: MeshInstance3D
static var _sprite_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _curve_cache: Dictionary = {}
const MAX_BLASTS := 8
const MAX_IMPACTS := 18
const MAX_MUZZLES := 8
const MAX_FLASH_LIGHTS := 5
var _profile := "destruction"
var _surface_kind := "ground"
var _normal := Vector3.UP
var _weapon_kind := "cannon"
var _heavy := false
var _light_peak := 0.0
var _muzzle_forward := Vector3.FORWARD


static func create(at: Vector3, scale_factor := 1.0, destructive := true) -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at
	effect.scale = Vector3.ONE * scale_factor
	effect.set_meta("destructive", destructive)
	if not destructive:
		effect._profile = "impact"
	return effect


static func create_impact(at: Vector3, heavy := false, surface_kind := "ground", normal := Vector3.UP, weapon_kind := "cannon") -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at + normal * 0.035
	effect._profile = "impact"
	effect._heavy = heavy
	effect._surface_kind = surface_kind
	effect._normal = normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	effect._weapon_kind = weapon_kind
	effect.set_meta("destructive", false)
	return effect


static func create_muzzle(at: Vector3, forward: Vector3, strength := 1.0, weapon_kind := "cannon") -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at
	effect.scale = Vector3.ONE * strength
	effect._profile = "muzzle"
	effect._weapon_kind = weapon_kind
	effect._muzzle_forward = forward.normalized()
	effect.set_meta("destructive", false)
	return effect


func _ready() -> void:
	add_to_group("combat_effects")
	var group := "blast_fx" if _profile == "destruction" else ("muzzle_fx" if _profile == "muzzle" else "impact_fx")
	var maximum := MAX_BLASTS if _profile == "destruction" else (MAX_MUZZLES if _profile == "muzzle" else MAX_IMPACTS)
	if get_tree().get_nodes_in_group(group).size() >= maximum:
		queue_free()
		return
	add_to_group(group)
	if _profile == "impact":
		_build_impact()
		return
	if _profile == "muzzle":
		_build_muzzle()
		return
	_add_light(12.0, 19.0)
	_add_flash(3.3, Vector3.UP * 0.8)
	_spawn_particles("Fire", 28, 0.95, Color("ffcf66"), Color(1.0, 0.12, 0.015, 0.0), 7.6, 3.4, 1.05, true)
	_spawn_particles("Sparks", 32, 1.25, Color("fff1a0"), Color(1.0, 0.22, 0.03, 0.0), 19.0, 0.45, 0.095, false)
	_spawn_particles("Smoke", 30, 3.9, Color(0.16, 0.14, 0.12, 0.78), Color(0.055, 0.06, 0.055, 0.0), 4.0, 1.1, 1.5, true)
	_spawn_particles("Dust", 34, 2.55, Color(0.36, 0.29, 0.19, 0.6), Color(0.18, 0.15, 0.1, 0.0), 12.0, 0.35, 1.05, true, true)
	_spawn_debris(18, 0.20)
	# The mastered explosion clips already include debris and outdoor decay.
	# Layering the old long blast again would double the report and mask fire.
	AudioService.play_3d("explosion", global_position, -2.0)


func _add_light(energy: float, distance: float) -> void:
	if get_tree().get_nodes_in_group("impact_flash_lights").size() >= MAX_FLASH_LIGHTS:
		return
	_light = OmniLight3D.new()
	_light.add_to_group("impact_flash_lights")
	_light.light_color = Color("ff8a3d")
	_light_peak = energy
	_light.light_energy = energy
	_light.omni_range = distance
	_light.shadow_enabled = false
	_light.position.y = 0.3
	add_child(_light)


func _add_flash(size: float, offset := Vector3.ZERO) -> void:
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.position = offset
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2.ONE * size
	var flash_material := _sprite_material("Fire").duplicate() as StandardMaterial3D
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.albedo_color = Color(1.8, 1.45, 0.95, 0.8)
	flash_quad.material = flash_material
	_flash.mesh = flash_quad
	add_child(_flash)


func _build_impact() -> void:
	var machine := _weapon_kind == "machine_gun"
	if _heavy and not machine:
		_build_explosive_impact()
		return
	_duration = 0.7 if machine else 1.75
	if _surface_kind == "armor":
		_spawn_particles("Sparks", 7 if machine else 18, 0.34 if machine else 0.6, Color("ffe69c"), Color(1, 0.22, 0.02, 0), 6.5 if machine else 12.0, 12.0, 0.035 if machine else 0.065, false, false, _normal)
		_spawn_particles("Smoke", 3 if machine else 10, 0.62 if machine else 1.4, Color.GRAY, Color.TRANSPARENT, 1.0, 0.2, 0.12 if machine else 0.46, true, false, _normal)
	else:
		_spawn_particles("Dust", 6 if machine else 20, 0.6 if machine else 1.6, Color("81705b"), Color.TRANSPARENT, 3.0, 1.0, 0.13 if machine else 0.62, true, _surface_kind == "ground", _normal)
		if not machine:
			_spawn_debris(5, 0.06)
	if _heavy:
		_add_light(4.0, 7.0)
		_add_flash(0.9)
		_spawn_particles("Fire", 12, 0.4, Color("ffd596"), Color.TRANSPARENT, 4.0, 1.8, 0.24, true)
		_spawn_particles("BlastSmoke", 12, 1.6, Color.GRAY, Color.TRANSPARENT, 2.1, 0.4, 0.48, true)
	elif not machine and _surface_kind == "armor":
		_add_flash(0.38)
	AudioService.play_3d("armor_hit" if _surface_kind == "armor" else "ground_hit", global_position, -13.0 if machine else (-3.5 if _heavy else -7.5), randf_range(0.94, 1.07))
	if _heavy:
		AudioService.play_3d("explosion", global_position, -8.0, 1.15)


func _build_explosive_impact() -> void:
	# A short overpressure flash gives way to a rolling fire front, expanding
	# earth/dust and a longer smoke column. HE's 8 m damage radius stays in the
	# same scale as the visible pressure-driven dust; it is not a glowing ring.
	_duration = 3.7
	_add_light(8.5, 16.0)
	_add_flash(2.5, Vector3.UP * 0.22)
	_spawn_particles("Fire", 24, 0.90, Color("ffd596"), Color.TRANSPARENT, 8.0, 1.2, 1.20, true)
	_spawn_particles("BlastSmoke", 24, 3.35, Color.GRAY, Color.TRANSPARENT, 3.7, 0.4, 1.55, true)
	_spawn_particles("Dust", 30, 2.25, Color("88755f"), Color.TRANSPARENT, 9.0, 0.2, 1.15, true, _surface_kind == "ground", _normal)
	_spawn_particles("Sparks", 18, 0.9, Color("ffe69c"), Color.TRANSPARENT, 14.0, 10.0, 0.065, false, false, _normal)
	_spawn_debris(12, 0.13)
	AudioService.play_3d("explosion", global_position, -1.8, 0.96 if _weapon_kind == "he" else 1.04)
	AudioService.play_3d("armor_hit" if _surface_kind == "armor" else "ground_hit", global_position, -6.0, 0.94)


func _build_muzzle() -> void:
	var machine := _weapon_kind == "machine_gun"
	_duration = 0.45 if machine else 0.8
	_add_flash(0.17 if machine else 0.65, _muzzle_forward * 0.16)
	if not machine:
		_add_light(4.5, 6.0)
		_spawn_particles("Fire", 5, 0.12, Color("ffddab"), Color.TRANSPARENT, 9.0, 0.0, 0.15, true, false, _muzzle_forward)
		_spawn_particles("Smoke", 7, 0.7, Color.GRAY, Color.TRANSPARENT, 2.8, 0.0, 0.23, true, false, _muzzle_forward)


func _process(delta: float) -> void:
	var owner := get_parent()
	if owner != null and owner.has_method("is_combat_running") and not owner.is_combat_running():
		var mode: String = str(owner.get("mode")) if "mode" in owner else "paused"
		if mode not in ["won", "lost"]:
			for child: Node in get_children():
				if child is GPUParticles3D:
					child.speed_scale = 0.0
			return
	for child: Node in get_children():
		if child is GPUParticles3D:
			child.speed_scale = 1.0
	_age += delta
	if is_instance_valid(_light):
		_light.light_energy = _light_peak * exp(-_age * 24.0)
		_light.light_color = Color("ffe0aa").lerp(Color("df5629"), clampf(_age * 3.0, 0.0, 1.0))
		if _age > 0.22:
			_light.queue_free()
	if is_instance_valid(_flash):
		_flash.scale = Vector3.ONE * (0.7 + _age * 3.0)
		_flash.visible = _age < 0.09
		((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = exp(-_age * 48.0)
	if _age >= _duration:
		queue_free()


func _spawn_particles(label: String, amount: int, lifetime: float, start: Color, finish: Color, speed: float, gravity: float, size: float, billboard: bool, horizontal := false, outward := Vector3.UP) -> void:
	var particles := GPUParticles3D.new()
	particles.name = label
	if label == "Dust":
		particles.position.y = size * 0.32
	elif label in ["Smoke", "BlastSmoke"]:
		particles.position.y = size * 0.3
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
	process.emission_sphere_radius = 0.35 if _profile == "destruction" else 0.04
	process.direction = outward
	process.spread = 88.0 if horizontal else (70.0 if _profile == "destruction" else 28.0)
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
		"Smoke", "BlastSmoke":
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
			gradient.add_point(0.12, Color(0.43, 0.35, 0.26, 0.68 if _heavy else 0.52))
			gradient.add_point(0.5, Color(0.46, 0.40, 0.32, 0.31))
			gradient.set_color(gradient.get_point_count() - 1, Color(0.48, 0.43, 0.36, 0.0))
			# Ground pressure displaces dust radially, replacing the luminous torus.
			if horizontal:
				process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				process.emission_ring_axis = Vector3.UP
				process.emission_ring_height = 0.04
				process.emission_ring_radius = 0.6 if _profile == "destruction" else 0.08
				process.emission_ring_inner_radius = 0.35 if _profile == "destruction" else 0.03
				process.initial_velocity_min = 0.0
				process.initial_velocity_max = 0.15
				process.radial_velocity_min = 3.0 if _profile == "destruction" or _heavy else 1.2
				process.radial_velocity_max = 6.0 if _profile == "destruction" or _heavy else 2.4
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


func _spawn_debris(amount: int, size: float) -> void:
	# GPU fragments have bounded lifetime and no expensive rigid-body pileup.
	var particles := GPUParticles3D.new()
	particles.name = "Debris"
	particles.amount = amount
	particles.lifetime = 1.15 if _profile == "destruction" else 0.7
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 25, 30))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP if _profile == "destruction" else _normal
	process.spread = 68.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 10.0 if _profile == "destruction" else 5.0
	process.gravity = Vector3.DOWN * 12.0
	process.scale_min = size * 0.4
	process.scale_max = size
	process.angular_velocity_min = -300.0
	process.angular_velocity_max = 300.0
	particles.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.28, 0.55)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4b4136")
	material.roughness = 0.86
	mesh.material = material
	particles.draw_pass_1 = mesh
	add_child(particles)
	particles.emitting = true


static func _sprite_material(label: String) -> StandardMaterial3D:
	if _material_cache.has(label):
		return _material_cache[label]
	var surface := StandardMaterial3D.new()
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if label in ["Fire", "Sparks"] else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	surface.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if label in ["Fire", "Sparks"] else BaseMaterial3D.BLEND_MODE_MIX
	surface.vertex_color_use_as_albedo = true
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.billboard_keep_scale = true
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.albedo_color = Color(0.42, 0.40, 0.37) if label in ["Smoke", "BlastSmoke"] else (Color(0.72, 0.62, 0.48) if label == "Dust" else Color.WHITE)
	surface.albedo_texture = particle_sprite("Fire" if label == "Fire" else ("Sparks" if label == "Sparks" else "Smoke"))
	surface.roughness = 1.0
	surface.metallic_specular = 0.0
	_material_cache[label] = surface
	return surface


static func _growth_curve(points: Array[Vector2]) -> CurveTexture:
	var key := str(points)
	if _curve_cache.has(key):
		return _curve_cache[key]
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 3.0
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	# ParticleProcessMaterial samples scale_curve as RGB -> XYZ. A red-only
	# curve collapses Y/Z to zero, making billboard fire/smoke/dust invisible.
	# Keep RGB even on devices that harmlessly promote RGBFloat to RGBAFloat.
	texture.texture_mode = CurveTexture.TEXTURE_MODE_RGB
	texture.curve = curve
	_curve_cache[key] = texture
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
