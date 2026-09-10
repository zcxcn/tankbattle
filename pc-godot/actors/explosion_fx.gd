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
static var _fluid_material_cache: Dictionary = {}
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
var _impact_priority := false
var _light_peak := 0.0
var _muzzle_forward := Vector3.FORWARD
var _muzzle_priority := false
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


static func create_impact(at: Vector3, heavy := false, surface_kind := "ground", normal := Vector3.UP, weapon_kind := "cannon", player_priority := false) -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at + normal * 0.035
	effect._profile = "impact"
	effect._heavy = heavy
	effect._impact_priority = player_priority
	effect._surface_kind = surface_kind
	effect._normal = normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	effect._weapon_kind = weapon_kind
	effect.set_meta("destructive", false)
	return effect


static func create_muzzle(at: Vector3, forward: Vector3, strength := 1.0, weapon_kind := "cannon", player_priority := false) -> ExplosionFX:
	var effect := ExplosionFX.new()
	effect.position = at
	effect.scale = Vector3.ONE * strength
	effect._profile = "muzzle"
	effect._weapon_kind = weapon_kind
	effect._muzzle_priority = player_priority
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
		var reclaimed := (_profile == "cookoff" and _retire_oldest_destruction()) or (_profile == "muzzle" and _muzzle_priority and _retire_oldest_muzzle()) or (_profile == "impact" and _impact_priority and _retire_oldest_impact())
		if not reclaimed:
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
	_spawn_particles("Fire", 2, 2.0, Color.WHITE, Color.TRANSPARENT, 1.6, -0.4, 6.2, true)
	_spawn_particles("Sparks", 32, 1.25, Color("fff1a0"), Color(1.0, 0.22, 0.03, 0.0), 19.0, 0.45, 0.095, false)
	_spawn_particles("Smoke", 8, 3.9, Color.WHITE, Color.TRANSPARENT, 2.2, 1.1, 3.2, true)
	_spawn_particles("Dust", 24, 2.55, Color.WHITE, Color.TRANSPARENT, 12.0, 0.35, 2.2, true, true)
	_spawn_debris(18, 0.20)
	# The mastered explosion clips already include debris and outdoor decay.
	# Layering the old long blast again would double the report and mask fire.
	AudioService.play_3d("explosion", global_position, -2.0)


func _retire_oldest_muzzle() -> bool:
	# Lingering AI smoke must never consume the player's new discharge slot.
	# Prefer retiring AI, but rapid player fire also replaces its oldest smoke.
	var oldest: ExplosionFX
	for candidate: Node in get_tree().get_nodes_in_group("muzzle_fx"):
		if candidate is ExplosionFX:
			if oldest == null or (oldest._muzzle_priority and not candidate._muzzle_priority) or (oldest._muzzle_priority == candidate._muzzle_priority and candidate._age > oldest._age):
				oldest = candidate
	if oldest == null:
		return false
	oldest.remove_from_group("muzzle_fx")
	if is_instance_valid(oldest._light):
		oldest._light.remove_from_group("impact_flash_lights")
	oldest.queue_free()
	return true


func _retire_oldest_impact() -> bool:
	# Smoke from distant hits must not suppress the player's current impact.
	# Prefer ordinary impacts, then replace the oldest player impact if needed.
	var oldest: ExplosionFX
	for candidate: Node in get_tree().get_nodes_in_group("impact_fx"):
		if candidate is ExplosionFX:
			if oldest == null or (oldest._impact_priority and not candidate._impact_priority) or (oldest._impact_priority == candidate._impact_priority and candidate._age > oldest._age):
				oldest = candidate
	if oldest == null:
		return false
	oldest.remove_from_group("impact_fx")
	if is_instance_valid(oldest._light):
		oldest._light.remove_from_group("impact_flash_lights")
	oldest.queue_free()
	return true


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
	# Three short gas surges escape different turret-ring openings. The actual
	# fluid frames cool to opaque soot while airborne; there is no stretched
	# static candle card. Damage still belongs to the wreck's single 9 m query.
	_duration = 6.2
	_flash_duration = 0.095
	_jet_duration = 0.45
	_add_light(17.0, 28.0)
	_add_flash(4.8, Vector3.UP * 0.65)
	# One continuous pressure body joins the hatch vents to the vehicle.
	var core := _spawn_particles("Fire", 1, 1.85, Color.WHITE, Color.TRANSPARENT, 0.8, -0.3, 8.5, true)
	core.name = "CookoffCore"
	for index in 3:
		var axis := Vector3(float(index - 1) * 0.22, 1.0, -0.11 if index == 1 else 0.15).normalized()
		var fire := _spawn_particles("Fire", 1, 1.2 + index * 0.08, Color.WHITE, Color.TRANSPARENT, 7.5 - index, -0.4, 5.8 if index == 1 else 4.8, true, false, axis)
		fire.name = "CookoffFireColumn" if index == 1 else "CookoffVent%d" % index
		fire.position = Vector3(float(index - 1) * 0.65, 0.25, 0)
		fire.explosiveness = 0.91
		var flame_process := fire.process_material as ParticleProcessMaterial
		flame_process.spread = 12.0
		flame_process.emission_sphere_radius = 0.18
		flame_process.initial_velocity_min = 5.0
		flame_process.damping_min = 5.0
		flame_process.damping_max = 7.0
		flame_process.scale_min = 4.4 if index == 1 else 3.8
		flame_process.scale_curve = _growth_curve([Vector2(0, 0.65), Vector2(0.13, 1.05), Vector2(0.6, 1.35), Vector2(1, 1.45)])
	var sparks := _spawn_particles("Sparks", 32, 2.1, Color.WHITE, Color.TRANSPARENT, 22.0, 12.0, 0.12, false)
	sparks.name = "CookoffBurningFragments"
	var spark_process := sparks.process_material as ParticleProcessMaterial
	spark_process.spread = 25.0
	spark_process.initial_velocity_min = 12.0
	var smoke := _spawn_particles("Smoke", 10, 5.8, Color.WHITE, Color.TRANSPARENT, 2.8, 0.0, 3.8, true)
	smoke.name = "CookoffSmokeColumn"
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	smoke_process.spread = 31.0
	smoke_process.gravity = Vector3(0.3, 0.72, 0.18)
	smoke_process.damping_min = 1.6
	smoke_process.damping_max = 2.5
	var dust := _spawn_particles("Dust", 26, 2.6, Color.WHITE, Color.TRANSPARENT, 9.0, 0.0, 2.5, true, true)
	dust.name = "CookoffPressureDust"
	dust.position.y = 0.16 - global_position.y
	var dust_process := dust.process_material as ParticleProcessMaterial
	dust_process.emission_ring_radius = 1.3
	dust_process.emission_ring_inner_radius = 0.7
	dust_process.radial_velocity_min = 9.0
	dust_process.radial_velocity_max = 14.0
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
		if not (_muzzle_priority or _impact_priority) or not _retire_flash_light():
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


func _retire_flash_light() -> bool:
	var weakest: OmniLight3D
	for candidate: Node in get_tree().get_nodes_in_group("impact_flash_lights"):
		if candidate is OmniLight3D:
			if weakest == null or candidate.light_energy < weakest.light_energy:
				weakest = candidate
	if weakest == null:
		return false
	weakest.remove_from_group("impact_flash_lights")
	weakest.queue_free()
	return true


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
	_duration = 0.7 if machine else 2.0
	if _surface_kind == "armor":
		var sparks := _spawn_particles("Sparks", 10 if machine else 28, 0.30 if machine else 0.85, Color("ffe69c"), Color(1, 0.22, 0.02, 0), 9.0 if machine else 19.0, 12.0, 0.045 if machine else 0.11, false, false, _normal)
		(sparks.process_material as ParticleProcessMaterial).spread = 42.0 if machine else 58.0
		_spawn_particles("Smoke", 3 if machine else 6, 0.62 if machine else 1.85, Color.GRAY, Color.TRANSPARENT, 1.0 if machine else 2.2, 0.2, 0.12 if machine else 1.7, true, false, _normal)
		if not machine:
			# Kinetic armor impact is a brief pressure/metal flash. The single
			# fluid lobe cools quickly; it is smaller and shorter than HE.
			_flash_duration = 0.15
			_add_impact_flash(2.5, 14.0, 15.0)
			var fire := _spawn_particles("Fire", 1, 0.82, Color.WHITE, Color.TRANSPARENT, 2.4, 0.0, 5.8, true, false, _normal)
			fire.position += _normal * 0.30
			_spawn_debris(7, 0.14)
			var fragments := (get_node("Debris") as GPUParticles3D).process_material as ParticleProcessMaterial
			fragments.initial_velocity_max = 9.0
	else:
		_spawn_particles("Dust", 7 if machine else 24, 0.6 if machine else 1.9, Color("81705b"), Color.TRANSPARENT, 3.0 if machine else 5.5, 1.0, 0.15 if machine else 1.2, true, _surface_kind == "ground", _normal)
		if not machine:
			_spawn_debris(7, 0.11)
			_flash_duration = 0.11
			_add_impact_flash(1.35, 5.0, 9.0)
	AudioService.play_3d("armor_hit" if _surface_kind == "armor" else "ground_hit", global_position, -12.0 if machine else -5.0, randf_range(0.94, 1.07))


func _add_impact_flash(size: float, energy: float, distance: float) -> void:
	_add_flash(size, _normal * 0.25 + Vector3.UP * 0.12)
	var material := (_flash.mesh as QuadMesh).material as StandardMaterial3D
	material.albedo_texture = particle_sprite("MuzzleCore")
	material.albedo_color = Color(3.5, 2.6, 1.25, 1.0)
	_add_light(energy, distance)
	if is_instance_valid(_light):
		_light.position = _normal * 0.65 + Vector3.UP * 0.4


func _build_explosive_impact() -> void:
	# A short overpressure flash gives way to a rolling fire front, expanding
	# earth/dust and a longer smoke column. HE's 8 m damage radius stays in the
	# same scale as the visible pressure-driven dust; it is not a glowing ring.
	_duration = 3.9
	_flash_duration = 0.18
	_add_impact_flash(3.8, 20.0, 21.0)
	_spawn_particles("Fire", 1, 1.8, Color.WHITE, Color.TRANSPARENT, 1.8, -0.3, 8.4 if _weapon_kind == "rocket" else 9.2, true)
	_spawn_particles("BlastSmoke", 7, 3.55, Color.WHITE, Color.TRANSPARENT, 2.4, 0.4, 3.5, true)
	_spawn_particles("Dust", 26, 2.5, Color.WHITE, Color.TRANSPARENT, 11.0, 0.2, 2.6, true, _surface_kind == "ground", _normal)
	_spawn_particles("Sparks", 32, 1.1, Color("ffe69c"), Color.TRANSPARENT, 20.0, 10.0, 0.10, false, false, _normal)
	_spawn_debris(18, 0.19)
	var fragments := (get_node("Debris") as GPUParticles3D).process_material as ParticleProcessMaterial
	fragments.initial_velocity_max = 12.0
	AudioService.play_3d("explosion", global_position, -0.5, 0.96 if _weapon_kind == "he" else 1.04)
	AudioService.play_3d("armor_hit" if _surface_kind == "armor" else "ground_hit", global_position, -5.0, 0.94)


func _build_muzzle() -> void:
	var machine := _weapon_kind == "machine_gun"
	var rocket := _weapon_kind == "rocket"
	_duration = 0.32 if machine else (1.15 if rocket else 1.45)
	_flash_duration = 0.065 if machine else (0.11 if rocket else 0.22)
	_jet_duration = 0.075 if machine else (0.14 if rocket else 0.25)
	_add_flash(0.38 if machine else (0.8 if rocket else 2.2), _muzzle_forward * (0.18 if machine else 0.5))
	# A pressure body faces the camera in addition to the axial gas sheets.
	# Axial quads alone become lines when the chase camera looks down the bore.
	var core_material := (_flash.mesh as QuadMesh).material as StandardMaterial3D
	core_material.albedo_texture = particle_sprite("MuzzleCore")
	core_material.albedo_color = Color(3.8, 2.8, 1.5, 1.0)
	_build_muzzle_jet(0.65 if machine else (1.8 if rocket else 3.5), 0.23 if machine else (0.60 if rocket else 1.65))
	if machine:
		var haze := _spawn_particles("Smoke", 3, 0.28, Color.GRAY, Color.TRANSPARENT, 1.8, 0.0, 0.08, true, false, _muzzle_forward)
		_tint_muzzle_smoke(haze, 0.18)
		return
	_add_light(4.0 if rocket else 14.0, 6.0 if rocket else 14.0)
	var flame := _spawn_particles("Fire", 6 if rocket else 12, 0.18 if rocket else 0.26, Color("ffddab"), Color.TRANSPARENT, 8.0 if rocket else 18.0, 0.0, 0.28 if rocket else 0.62, true, false, _muzzle_forward)
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
	# Side views read the forward gas impulse from two intersecting sheets;
	# the separate camera-facing pressure body remains visible along the bore.
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
		material.albedo_color = Color(3.5, 2.3, 1.0, 0.95)
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
		var light_fade := exp(-_age * (7.0 if _profile == "cookoff" else 24.0))
		if _profile == "muzzle":
			light_fade = 1.0 - smoothstep(0.035, _jet_duration + 0.04, _age)
		elif _profile == "impact":
			light_fade = 1.0 - smoothstep(0.025, 0.34 if _heavy else 0.27, _age)
		_light.light_energy = _light_peak * light_fade
		_light.light_color = Color("ffe0aa").lerp(Color("df5629"), clampf(_age * 3.0, 0.0, 1.0))
		var light_duration := 0.7 if _profile == "cookoff" else (_jet_duration + 0.04 if _profile == "muzzle" else 0.22)
		if _profile == "impact":
			light_duration = 0.34 if _heavy else 0.27
		if _age > light_duration:
			_light.queue_free()
	if is_instance_valid(_flash):
		_flash.visible = _age < _flash_duration
		if _profile == "muzzle":
			var core_phase := clampf(_age / _flash_duration, 0.0, 1.0)
			_flash.scale = Vector3.ONE * (0.80 + sin(core_phase * PI * 0.75) * 0.38)
			((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(3.8 - core_phase * 1.2, 2.8 - core_phase * 1.7, 1.5 - core_phase * 1.3, 1.0 - smoothstep(0.23, 1.0, core_phase))
		elif _profile == "impact":
			var impact_phase := clampf(_age / _flash_duration, 0.0, 1.0)
			_flash.scale = Vector3.ONE * (0.85 + impact_phase * 0.45)
			((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(3.5 - impact_phase, 2.6 - impact_phase * 1.6, 1.25 - impact_phase, 1.0 - smoothstep(0.15, 1.0, impact_phase))
		else:
			_flash.scale = Vector3.ONE * (0.7 + _age * 3.0)
			((_flash.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = exp(-_age * 48.0)
	if is_instance_valid(_muzzle_jet):
		_muzzle_jet.visible = _age < _jet_duration
		var phase := clampf(_age / _jet_duration, 0.0, 1.0)
		_muzzle_jet.scale = Vector3.ONE * (0.78 + sin(phase * PI) * 0.26)
		for material: StandardMaterial3D in _jet_materials:
			var fade := 1.0 - smoothstep(0.16, 1.0, phase)
			material.albedo_color = Color(3.5 - phase, 2.3 - phase * 1.65, 1.0 - phase * 0.88, fade * 0.95)
	if _age >= _duration:
		queue_free()


func _spawn_particles(label: String, amount: int, lifetime: float, start: Color, finish: Color, speed: float, gravity: float, size: float, billboard: bool, horizontal := false, outward := Vector3.UP) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	if label == "Fire" and _profile != "muzzle":
		# Atlas content sits below the card centre. Lift the visual, keeping the
		# real impact position and blast damage query on the physical surface.
		particles.position.y = size * 0.22
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
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
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
				# Radial velocity is an animated velocity: ordinary damping does
				# not affect it. Stop the pressure front explicitly over its life.
				process.radial_velocity_curve = _growth_curve([Vector2(0, 1), Vector2(0.1, 0.78), Vector2(0.3, 0.16), Vector2(0.48, 0), Vector2(1, 0)])
				if _profile == "destruction" or _heavy:
					process.radial_velocity_min = 7.0
					process.radial_velocity_max = 12.0
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
	var fluid := label in ["Fire", "Smoke", "BlastSmoke", "Dust"] and _profile != "muzzle"
	if fluid:
		_configure_fluid_motion(process, label)
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 2.2) if label == "Sparks" else Vector2.ONE * (2.1 if label == "Smoke" else 1.65)
	quad.material = fluid_material(label) if fluid else _sprite_material(label)
	particles.draw_pass_1 = quad
	add_child(particles)
	particles.emitting = true
	return particles


static func _configure_fluid_motion(process: ParticleProcessMaterial, label: String) -> void:
	process.anim_speed_min = 1.0
	process.anim_speed_max = 1.0
	process.angle_min = 0.0
	process.angle_max = 0.0
	process.angular_velocity_min = 0.0
	process.angular_velocity_max = 0.0
	# Color and changing silhouettes already exist inside the fluid simulation;
	# an orange overlay would also tint cold soot and keep it glowing.
	var tint := Color(0.85, 0.82, 0.76) if label == "Dust" else Color.WHITE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint, 0.0))
	gradient.set_color(1, Color(tint, 0.0))
	gradient.add_point(0.035 if label == "Fire" else 0.1, Color(tint, 0.96 if label == "Fire" else (0.4 if label == "Dust" else 0.62)))
	gradient.add_point(0.55, Color(tint, 0.83 if label == "Fire" else (0.27 if label == "Dust" else 0.45)))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	if label == "Fire":
		process.scale_min = process.scale_max * 0.85
		process.damping_min = 3.5
		process.damping_max = 5.0
		process.scale_curve = _growth_curve([Vector2(0, 0.65), Vector2(0.12, 1.0), Vector2(0.6, 1.2), Vector2(1, 1.3)])
	elif label in ["Smoke", "BlastSmoke"]:
		process.damping_min = 1.6
		process.damping_max = 2.6
		process.gravity = Vector3(0.18, 0.52, 0.12)
		process.scale_curve = _growth_curve([Vector2(0, 0.38), Vector2(0.18, 0.85), Vector2(0.65, 1.35), Vector2(1, 1.65)])
		# Low-frequency curl displaces only ten-odd particles per explosion;
		# the detailed vortices themselves come from the precomputed atlas.
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 1.5
		process.turbulence_noise_scale = 3.0
		process.turbulence_influence_min = 0.08
		process.turbulence_influence_max = 0.16
		process.turbulence_noise_speed = Vector3(0.15, 0.22, 0.1)
	elif label == "Dust":
		process.gravity = Vector3(0.06, 0.08, 0.025)
		process.scale_curve = _growth_curve([Vector2(0, 0.25), Vector2(0.18, 0.85), Vector2(0.6, 1.3), Vector2(1, 1.55)])


static func fluid_material(label: String) -> ShaderMaterial:
	if _fluid_material_cache.has(label):
		return _fluid_material_cache[label]
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/fluid_flipbook.gdshader")
	var burning := label == "BurningFlame"
	var hot := label == "Fire" or burning
	var atlas: Texture2D = load("res://assets/fx/fluid/" + ("flame" if burning else ("explosion" if hot else "smoke")) + ".png")
	material.set_shader_parameter("flipbook", atlas)
	material.set_shader_parameter("heat", 3.2 if hot else 0.0)
	material.set_shader_parameter("matter_brightness", 1.35 if hot else (2.6 if label == "Dust" else 1.3))
	material.set_shader_parameter("soft_distance", 0.5 if hot else 0.7)
	material.set_shader_parameter("flame_only", burning)
	if burning:
		material.set_shader_parameter("grid", Vector2(16, 4))
		material.set_shader_parameter("last_frame", 63.0)
	material.resource_name = "SimulatedFluid" + label
	_fluid_material_cache[label] = material
	return material


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
			if kind == "MuzzleCore":
				# Irregular hot gas lobes surround an opaque white-hot centre.
				# This is a brief discharge body, never a looping flame or halo.
				var angle := atan2(uv.y, uv.x)
				var boundary := 0.73 + sin(angle * 5.0 + 0.7) * 0.11 + sin(angle * 9.0) * 0.05 + noise.get_noise_2d(float(x), float(y)) * 0.12
				var body := 1.0 - smoothstep(0.18, boundary, radius)
				var heat := 1.0 - smoothstep(0.10, 0.72, radius)
				color = Color(1.0, lerpf(0.32, 0.96, heat), lerpf(0.025, 0.76, heat), body * lerpf(cloud, 1.0, heat))
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
