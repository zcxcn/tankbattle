class_name ExplosionFX
extends Node3D
## Layered one-shot impact: flash, fire, smoke, sparks, dust and local light.

var _age := 0.0
var _duration := 2.8
var _light: OmniLight3D
var _shockwave: MeshInstance3D
var _flash: MeshInstance3D


static func create(at: Vector3, scale_factor := 1.0, destructive := true) -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at
	effect.scale = Vector3.ONE * scale_factor
	effect.set_meta("destructive", destructive)
	return effect


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color("ff8a3d")
	_light.light_energy = 14.0
	_light.omni_range = 15.0
	_light.shadow_enabled = false
	_light.position.y = 1.2
	add_child(_light)
	_flash = ArtFactory.add_sphere(self, "Flash", Vector3(0, 0.8, 0), 0.65, ArtFactory.material(Color("fff1bb"), 0.0, 0.2, 9.0), 20)
	_shockwave = ArtFactory.add_torus(self, "Shockwave", Vector3(0, 0.12, 0), 1.0, 0.14, ArtFactory.material(Color("ffb15b"), 0.0, 0.35, 4.5))
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
	if is_instance_valid(_flash):
		_flash.scale = Vector3.ONE * (0.7 + _age * 9.0)
		_flash.visible = _age < 0.18
	if is_instance_valid(_shockwave):
		_shockwave.scale = Vector3.ONE * (1.0 + _age * 15.0)
		_shockwave.visible = _age < 0.42
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
	var gradient := Gradient.new()
	gradient.set_color(0, start)
	gradient.set_color(1, finish)
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var surface := StandardMaterial3D.new()
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.vertex_color_use_as_albedo = true
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	surface.albedo_color = Color.WHITE
	quad.material = surface
	particles.draw_pass_1 = quad
	add_child(particles)
	particles.emitting = true
