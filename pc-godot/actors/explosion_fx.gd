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
const MAX_COOKOFFS := 3
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
var _muzzle_jet: Node3D
var _jet_materials: Array[StandardMaterial3D] = []
var _jet_duration := 0.13
var _flash_duration := 0.09


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
	effect._muzzle_forward = forward.normalized() if forward.length_squared() > 0.01 else Vector3.FORWARD
	effect.set_meta("destructive", false)
	return effect


static func create_cookoff(at: Vector3) -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.name = "AmmunitionCookoff"
	effect.position = at
	effect._profile = "cookoff"
	effect.set_meta("destructive", true)
	return effect


func _ready() -> void:
	add_to_group("combat_effects")
	var large_blast := _profile in ["destruction", "cookoff"]
	var group := "blast_fx" if large_blast else ("muzzle_fx" if _profile == "muzzle" else "impact_fx")
	var maximum := MAX_BLASTS if large_blast else (MAX_MUZZLES if _profile == "muzzle" else MAX_IMPACTS)
	if _profile == "cookoff" and get_tree().get_nodes_in_group("cookoff_fx").size() >= MAX_COOKOFFS:
		queue_free()
		return
	if get_tree().get_nodes_in_group(group).size() >= maximum:
		if _profile != "cookoff" or not _retire_oldest_destruction():
			queue_free()
			return
	add_to_group(group)
	if _profile == "cookoff":
		add_to_group("cookoff_fx")
		_build_cookoff()
		return
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


func _retire_oldest_destruction() -> bool:
	# A delayed ammunition fire must remain visible even when the initial
	# vehicle explosions still occupy every slot with their lingering smoke.
	# Existing cookoffs keep their slots; only ordinary destruction is retired.
	var oldest: ExplosionFX
	for candidate: Node in get_tree().get_nodes_in_group("blast_fx"):
		if candidate is ExplosionFX and candidate._profile == "destruction":
			if oldest == null or candidate._age > oldest._age:
				oldest = candidate
	if oldest == null:
		return false
	oldest.remove_from_group("blast_fx")
	if is_instance_valid(oldest._light):
		oldest._light.remove_from_group("impact_flash_lights")
	oldest.queue_free()
	return true


func _build_cookoff() -> void:
	# Ammunition vents through the turret ring: a fast vertical jet precedes
	# rising fire clumps, falling hot fragments and a long, dark smoke column.
	# All layers are cosmetic; the wreck owns the single 9 m damage query.
	_duration = 6.2
	_flash_duration = 0.16
	_jet_duration = 1.2
	_add_light(17.0, 28.0)
	_add_flash(4.8, Vector3.UP * 0.65)
	_muzzle_forward = Vector3.UP
	_build_muzzle_jet(10.5, 3.2)
	_muzzle_jet.name = "UpwardFlameJet"
	_muzzle_jet.scale = Vector3(0.72, 0.72, 0.16)
	var fire := _spawn_particles("Fire", 36, 1.85, Color.WHITE, Color.TRANSPARENT, 17.0, -1.4, 1.3, true)
	fire.name = "CookoffFireColumn"
	var flame_process := fire.process_material as ParticleProcessMaterial
	flame_process.spread = 14.0
	flame_process.emission_sphere_radius = 0.55
	flame_process.initial_velocity_min = 11.5
	flame_process.damping_min = 1.2
	flame_process.damping_max = 2.5
	flame_process.scale_curve = _growth_curve([Vector2(0, 0.35), Vector2(0.2, 1.15), Vector2(0.6, 1.85), Vector2(1, 1.65)])
	var sparks := _spawn_particles("Sparks", 32, 2.1, Color.WHITE, Color.TRANSPARENT, 22.0, 12.0, 0.12, false)
	sparks.name = "CookoffBurningFragments"
	var spark_process := sparks.process_material as ParticleProcessMaterial
	spark_process.spread = 25.0
	spark_process.initial_velocity_min = 12.0
	var smoke := _spawn_particles("Smoke", 28, 5.8, Color.GRAY, Color.TRANSPARENT, 6.8, 0.0, 2.0, true)
	smoke.name = "CookoffSmokeColumn"
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	smoke_process.spread = 18.0
	smoke_process.gravity = Vector3(0.35, 0.95, 0.1)
	smoke_process.damping_min = 0.25
	smoke_process.damping_max = 0.5
	smoke_process.color_ramp.gradient.set_color(1, Color(0.11, 0.09, 0.075, 0.82))
	smoke_process.color_ramp.gradient.set_color(2, Color(0.21, 0.19, 0.17, 0.58))
	var dust := _spawn_particles("Dust", 30, 2.6, Color.GRAY, Color.TRANSPARENT, 9.0, 0.0, 1.4, true, true)
	dust.name = "CookoffPressureDust"
	dust.position.y = 0.16 - global_position.y
	var dust_process := dust.process_material as ParticleProcessMaterial
	dust_process.emission_ring_radius = 1.3
	dust_process.emission_ring_inner_radius = 0.7
	dust_process.radial_velocity_min = 4.5
	dust_process.radial_velocity_max = 8.8
	_spawn_debris(18, 0.24)
	var debris := get_node("Debris") as GPUParticles3D
	debris.lifetime = 2.4
	var debris_process := debris.process_material as ParticleProcessMaterial
	debris_process.direction = Vector3.UP
	debris_process.spread = 35.0
	debris_process.initial_velocity_min = 7.0
	debris_process.initial_velocity_max = 15.0
	for child: Node in get_children():
		if child is GPUParticles3D:
			child.visibility_aabb = AABB(Vector3(-24, -4, -24), Vector3(48, 42, 48))
	AudioService.play_3d("explosion", global_position, 0.5, 0.78)


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
	var rocket := _weapon_kind == "rocket"
	_duration = 0.32 if machine else (1.15 if rocket else 1.45)
	_flash_duration = 0.05 if machine else (0.075 if rocket else 0.12)
	_jet_duration = 0.05 if machine else (0.10 if rocket else 0.15)
	_add_flash(0.28 if machine else (0.46 if rocket else 1.12), _muzzle_forward * 0.20)
	_build_muzzle_jet(0.55 if machine else (1.6 if rocket else 2.9), 0.18 if machine else (0.45 if rocket else 1.05))
	if machine:
		var haze := _spawn_particles("Smoke", 3, 0.28, Color.GRAY, Color.TRANSPARENT, 1.8, 0.0, 0.08, true, false, _muzzle_forward)
		_tint_muzzle_smoke(haze, 0.18)
		return
	_add_light(3.2 if rocket else 10.0, 5.5 if rocket else 11.0)
	var flame := _spawn_particles("Fire", 6 if rocket else 12, 0.18 if rocket else 0.22, Color("ffddab"), Color.TRANSPARENT, 8.0 if rocket else 18.0, 0.0, 0.24 if rocket else 0.42, true, false, _muzzle_forward)
	var flame_process := flame.process_material as ParticleProcessMaterial
	flame_process.spread = 10.0 if rocket else 13.0
	flame_process.damping_min = 8.0
	flame_process.damping_max = 13.0
	var smoke := _spawn_particles("Smoke", 8 if rocket else 12, 1.05 if rocket else 1.3, Color.GRAY, Color.TRANSPARENT, 3.5 if rocket else 5.8, 0.0, 0.27 if rocket else 0.50, true, false, _muzzle_forward)
	(smoke.process_material as ParticleProcessMaterial).spread = 19.0
	_tint_muzzle_smoke(smoke, 0.30 if rocket else 0.32)
	# The pressure front stirs loose ground below the bore. Elevated launchers
	# and roof-mounted rockets do not conjure floating circles of dust.
	if not rocket and global_position.y >= 0.0 and global_position.y <= 4.2:
		var dust := _spawn_particles("Dust", 12, 1.1, Color.GRAY, Color.TRANSPARENT, 3.0, 0.0, 0.38, true, true)
		dust.name = "MuzzlePressure"
		dust.position = _muzzle_forward * 0.65
		dust.position.y = (0.16 - global_position.y) / maxf(absf(global_basis.get_scale().y), 0.01)
		var pressure := dust.process_material as ParticleProcessMaterial
		pressure.emission_ring_radius = 0.65
		pressure.emission_ring_inner_radius = 0.25
		pressure.radial_velocity_min = 2.2
		pressure.radial_velocity_max = 4.5
		pressure.color_ramp.gradient.set_color(1, Color(0.46, 0.40, 0.32, 0.21))
		pressure.color_ramp.gradient.set_color(2, Color(0.46, 0.40, 0.32, 0.12))


func _tint_muzzle_smoke(particles: GPUParticles3D, opacity: float) -> void:
	var process := particles.process_material as ParticleProcessMaterial
	process.color_ramp.gradient.set_color(1, Color(0.58, 0.55, 0.49, opacity))
	process.color_ramp.gradient.set_color(2, Color(0.62, 0.60, 0.55, opacity * 0.55))
	process.scale_curve = _growth_curve([Vector2(0.0, 0.35), Vector2(0.20, 1.0), Vector2(1.0, 2.0)])


func _build_muzzle_jet(length_m: float, width_m: float) -> void:
	# Two intersecting textured flame tongues retain the barrel's axis from
	# tactical and chase cameras. Their short lifetime leaves the aim line clear.
	_muzzle_jet = Node3D.new()
	_muzzle_jet.name = "DirectionalFlame"
	var up := Vector3.RIGHT if absf(_muzzle_forward.dot(Vector3.UP)) > 0.98 else Vector3.UP
	_muzzle_jet.basis = Basis.looking_at(_muzzle_forward, up)
	add_child(_muzzle_jet)
	for angle in [0.0, PI * 0.5]:
		var card := MeshInstance3D.new()
		card.name = "FlameTongue"
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.basis = Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP).rotated(Vector3.FORWARD, angle)
		card.position.z = -length_m * 0.48
		var quad := QuadMesh.new()
		quad.size = Vector2(width_m, length_m)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = particle_sprite("Muzzle")
		material.albedo_color = Color(2.6, 1.65, 0.60, 0.85)
		quad.material = material
		card.mesh = quad
		_jet_materials.append(material)
		_muzzle_jet.add_child(card)


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
		_light.light_energy = _light_peak * exp(-_age * (7.0 if _profile == "cookoff" else 24.0))
		_light.light_color = Color("ffe0aa").lerp(Color("df5629"), clampf(_age * 3.0, 0.0, 1.0))
		if _age > (0.7 if _profile == "cookoff" else 0.22):
			_light.queue_free()
	if is_instance_valid(_flash):
		_flash.scale = Vector3.ONE * (0.7 + _age * 3.0)
		_flash.visible = _age < _flash_duration
		((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = exp(-_age * (26.0 if _profile == "muzzle" else 48.0))
	if is_instance_valid(_muzzle_jet):
		_muzzle_jet.visible = _age < _jet_duration
		var phase := clampf(_age / _jet_duration, 0.0, 1.0)
		if _profile == "cookoff":
			var surge := minf(_age / 0.14, 1.0)
			var flicker := 1.0 + sin(_age * 41.0) * 0.07
			_muzzle_jet.scale = Vector3(0.72 + surge * 0.35, 0.72 + surge * 0.35, lerpf(0.16, 1.12, surge) * flicker)
		else:
			_muzzle_jet.scale = Vector3.ONE * (0.78 + sin(phase * PI) * 0.26)
		for material: StandardMaterial3D in _jet_materials:
			var fade := 1.0 - smoothstep(0.25, 1.0, phase) if _profile == "cookoff" else pow(1.0 - phase, 1.4)
			material.albedo_color = Color(2.6 - phase, 1.65 - phase * 1.25, 0.60 - phase * 0.50, fade * 0.85)
	if _age >= _duration:
		queue_free()


func _spawn_particles(label: String, amount: int, lifetime: float, start: Color, finish: Color, speed: float, gravity: float, size: float, billboard: bool, horizontal := false, outward := Vector3.UP) -> GPUParticles3D:
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
	return particles


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
			var color := Color(1.0, 1.0, 1.0, alpha)
			if kind == "Muzzle":
				# Quad +Y points down the barrel, and its texture V starts at 0.
				var along := (1.0 - uv.y) * 0.5
				var width := (0.22 + sin(along * PI) * 0.65) * (1.0 - along * 0.72)
				var waviness := noise.get_noise_2d(float(x), float(y)) * 0.12 * sin(along * PI)
				var lateral := 1.0 - smoothstep(width * 0.12, width, absf(uv.x + waviness))
				var ends := smoothstep(0.0, 0.06, along) * (1.0 - smoothstep(0.65, 1.0, along))
				color = Color(1.0, lerpf(0.92, 0.34, along), lerpf(0.68, 0.06, along), lateral * ends * cloud)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = "Explosion%sSoftSprite" % kind
	_sprite_cache[kind] = texture
	return texture
