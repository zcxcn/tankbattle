extends Node
## Small CPU-side visual-resource checks; GPU appearance is reviewed separately.

var passed := 0
var failed := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)


func _run() -> void:
	for kind in ["Fire", "Smoke", "Sparks", "Muzzle", "MuzzleCore"]:
		var texture := ExplosionFX.particle_sprite(kind)
		var image := texture.get_image()
		var edges_clear := true
		for offset in image.get_width():
			edges_clear = edges_clear and image.get_pixel(offset, 0).a == 0.0
			edges_clear = edges_clear and image.get_pixel(offset, image.get_height() - 1).a == 0.0
			edges_clear = edges_clear and image.get_pixel(0, offset).a == 0.0
			edges_clear = edges_clear and image.get_pixel(image.get_width() - 1, offset).a == 0.0
		_check(edges_clear, kind + " sprite has fully transparent borders on every side")
		var soft_pixels := 0
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x, y).a
				if alpha > 0.01 and alpha < 0.95:
					soft_pixels += 1
		_check(soft_pixels > 200 and image.get_pixel(image.get_width() / 2, image.get_height() / 2).a > 0.1, kind + " sprite contains a visible center with continuous soft alpha")
		_check(ExplosionFX.particle_sprite(kind) == texture, kind + " sprite reuses its shared cached texture")
	var effect := ExplosionFX.create(Vector3.ZERO)
	add_child(effect)
	effect.set_process(false)
	_check(effect.is_in_group("combat_effects") and is_equal_approx(effect._duration, 4.2), "effect retains its cleanup group and a finite 4.2-second smoke lifetime")
	_check(effect.get_node_or_null("Shockwave") == null, "explosion pressure uses dust instead of a neon torus")
	var total_particles := 0
	var textured_layers := true
	for label in ["Fire", "Sparks", "Smoke", "Dust"]:
		var particles := effect.get_node_or_null(label) as GPUParticles3D
		if particles == null:
			textured_layers = false
			continue
		total_particles += particles.amount
		var material := (particles.draw_pass_1 as QuadMesh).material
		textured_layers = textured_layers and ((material is ShaderMaterial and material.get_shader_parameter("flipbook") != null) or (material is StandardMaterial3D and material.albedo_texture != null and material.billboard_keep_scale))
	_check(textured_layers and total_particles <= 128, "all four bounded particle layers preserve simulated size and use textured matter within the 128-particle budget")
	for label in ["Smoke", "Dust"]:
		var particles := effect.get_node(label) as GPUParticles3D
		var material := (particles.draw_pass_1 as QuadMesh).material as ShaderMaterial
		var process := particles.process_material as ParticleProcessMaterial
		_check(material != null and material.get_shader_parameter("heat") == 0.0 and material.get_shader_parameter("soft_distance") >= 0.5, label + " is non-emissive fluid matter with softened scene intersections")
		_check(process.scale_curve.curve.sample(1.0) > process.scale_curve.curve.sample(0.0) * 3.0 and process.color_ramp.gradient.sample(0.0).a == 0.0 and process.color_ramp.gradient.sample(1.0).a == 0.0, label + " expands and fades smoothly at birth and expiry")
		_check(process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB, label + " scale curve provides all XYZ channels so billboards retain visible width and height")
	var fire_process := (effect.get_node("Fire") as GPUParticles3D).process_material as ParticleProcessMaterial
	var fire_material := ((effect.get_node("Fire") as GPUParticles3D).draw_pass_1 as QuadMesh).material as ShaderMaterial
	var fire_image := (fire_material.get_shader_parameter("flipbook") as Texture2D).get_image()
	_check(_hot_energy(fire_image, 0) > _hot_energy(fire_image, 24) * 10.0 and fire_process.color_ramp.gradient.sample(1.0).a == 0.0, "actual fluid frames cool from fire to dark soot instead of just recoloring a repeated sphere")
	_check(fire_process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB, "fire scale curve cannot collapse its billboard onto a zero-height line")
	_check(effect.get_node("Debris") is GPUParticles3D, "destruction ejects finite GPU fragments instead of spawning rigid-body debris piles")
	var smoke_process := (effect.get_node("Smoke") as GPUParticles3D).process_material as ParticleProcessMaterial
	_check(smoke_process.turbulence_enabled and smoke_process.damping_min > 1.5 and smoke_process.gravity.y > 0.0, "smoke loses the blast impulse before drifting upward with low-frequency curl")
	var pressure_curve := ((effect.get_node("Dust") as GPUParticles3D).process_material as ParticleProcessMaterial).radial_velocity_curve as CurveTexture
	_check(pressure_curve != null and pressure_curve.curve.sample(0.0) > 0.9 and pressure_curve.curve.sample(0.5) < 0.01 and pressure_curve.curve.sample(1.0) < 0.01, "radial pressure explicitly decays to zero rather than relying on damping that cannot stop animated velocity")
	_check((effect.get_node("Fire") as GPUParticles3D).amount <= 3 and fire_process.anim_speed_min == 1.0 and fire_process.anim_speed_max == 1.0, "each destruction uses at most three evolving fluid lobes with one non-looping animation per life")
	effect.free()
	var heavy := ExplosionFX.create_impact(Vector3.ZERO, true, "ground", Vector3.UP, "he")
	add_child(heavy)
	heavy.set_process(false)
	var blast_dust := heavy.get_node("Dust") as GPUParticles3D
	var blast_dust_process := blast_dust.process_material as ParticleProcessMaterial
	var blast_fire_process := (heavy.get_node("Fire") as GPUParticles3D).process_material as ParticleProcessMaterial
	_check(blast_dust.lifetime > 2.0 and blast_dust_process.radial_velocity_max >= 6.0 and blast_fire_process.scale_max >= 0.89, "HE produces a broad pressure-driven dust front and substantial rolling fire")
	var hot_bounds := _first_hot_bounds(fire_image)
	var he_fire := heavy.get_node("Fire") as GPUParticles3D
	var initial_size: Vector2 = (he_fire.draw_pass_1 as QuadMesh).size * blast_fire_process.scale_min * blast_fire_process.scale_curve.curve.sample(0.06)
	var visible_width: float = initial_size.x * hot_bounds.size.x
	var visible_height: float = he_fire.position.y + initial_size.y * (0.5 - hot_bounds.get_center().y)
	_check(visible_width > 2.0 and visible_height > 0.3, "actual first-frame HE hot pixels span over two metres and remain above the impact floor even at minimum particle scale")
	_check(heavy.get_node("BlastSmoke") != null and heavy.get_node("Debris") != null and heavy._duration > 3.0, "HE blast separates fire, lingering smoke and finite fragments")
	_check(blast_dust_process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB and blast_fire_process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB, "enlarged HE layers retain RGB particle scale curves")
	heavy.free()
	var armor := ExplosionFX.create_impact(Vector3.ZERO, false, "armor", Vector3.RIGHT, "machine_gun")
	add_child(armor)
	armor.set_process(false)
	var earth := ExplosionFX.create_impact(Vector3.ZERO, false, "ground", Vector3.UP, "machine_gun")
	add_child(earth)
	earth.set_process(false)
	_check(armor.get_node_or_null("Sparks") != null and armor.get_node_or_null("Dust") == null and earth.get_node_or_null("Dust") != null and earth.get_node_or_null("Sparks") == null, "armor produces directional metal sparks while ground hits displace dust")
	_check(armor._light == null and earth._light == null and armor.get_node_or_null("Fire") == null, "machine-gun impacts create no lights or explosive fireballs")
	var spark_process := (armor.get_node("Sparks") as GPUParticles3D).process_material as ParticleProcessMaterial
	_check(spark_process.direction.is_equal_approx(Vector3.RIGHT), "impact spark direction follows the real collision surface normal")
	armor.free()
	earth.free()
	var firing_direction := Vector3(0.4, 0.15, -1.0).normalized()
	var muzzle := ExplosionFX.create_muzzle(Vector3(0, 2.2, 0), firing_direction, 1.5, "he")
	add_child(muzzle)
	muzzle.set_process(false)
	var flame_jet := muzzle.get_node("DirectionalFlame") as Node3D
	var tongue := flame_jet.get_child(0) as MeshInstance3D
	var tongue_mesh := tongue.mesh as QuadMesh
	_check((-flame_jet.basis.z).is_equal_approx(firing_direction) and flame_jet.get_child_count() == 2, "crossed flame tongues follow the real barrel elevation and heading")
	_check(tongue_mesh.size.y >= 3.0 and tongue_mesh.size.x >= 1.4 and tongue_mesh.size.y >= tongue_mesh.size.x * 2.0 and (tongue_mesh.material as StandardMaterial3D).billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "cannon gas retains a broad but forward elongated barrel-axis silhouette")
	var core_material := (muzzle._flash.mesh as QuadMesh).material as StandardMaterial3D
	_check(core_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and (muzzle._flash.mesh as QuadMesh).size.x >= 2.0 and core_material.albedo_texture == ExplosionFX.particle_sprite("MuzzleCore"), "camera-facing pressure body keeps hot gas visible when chase view sees axial sheets edge-on")
	var muzzle_fire := muzzle.get_node("Fire") as GPUParticles3D
	var muzzle_fire_process := muzzle_fire.process_material as ParticleProcessMaterial
	_check(muzzle_fire_process.direction.is_equal_approx(firing_direction) and muzzle_fire_process.spread <= 15.0 and muzzle_fire_process.initial_velocity_max >= 16.0, "visible hot gas is ejected forward in a narrow high-speed cone")
	_check(muzzle_fire_process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB, "muzzle flames preserve all particle scale channels")
	var pressure := muzzle.get_node("MuzzlePressure") as GPUParticles3D
	_check(is_equal_approx(pressure.global_position.y, 0.16) and (pressure.process_material as ParticleProcessMaterial).radial_velocity_max >= 4.0, "scaled heavy-gun pressure dust remains on the ground and expands away from the bore")
	var muzzle_particles := 0
	for child: Node in muzzle.get_children():
		if child is GPUParticles3D:
			muzzle_particles += child.amount
	_check(muzzle_particles <= 40 and muzzle._duration <= 1.5, "enlarged cannon discharge stays within 40 particles and expires promptly")
	var machine_muzzle := ExplosionFX.create_muzzle(Vector3.ZERO, Vector3.FORWARD, 1.0, "machine_gun")
	add_child(machine_muzzle)
	machine_muzzle.set_process(false)
	_check((muzzle._flash.mesh as QuadMesh).size.x >= (machine_muzzle._flash.mesh as QuadMesh).size.x * 3.0 and machine_muzzle._light == null and machine_muzzle.get_node_or_null("MuzzlePressure") == null, "main-gun flash is much larger than the compact light-free machine-gun discharge")
	var rocket_muzzle := ExplosionFX.create_muzzle(Vector3.ZERO, Vector3.FORWARD, 1.0, "rocket")
	add_child(rocket_muzzle)
	rocket_muzzle.set_process(false)
	_check(rocket_muzzle.get_node_or_null("MuzzlePressure") == null and (rocket_muzzle.get_node("Fire") as GPUParticles3D).amount < muzzle_fire.amount, "rocket ignition uses a smaller forward plume without a tank-cannon pressure blast")
	muzzle._process(0.12)
	_check(flame_jet.visible and muzzle._flash.visible and core_material.albedo_color.a > 0.5 and muzzle._light.light_energy > muzzle._light_peak * 0.5, "hot pressure body and local illumination remain readable through the early discharge instead of vanishing in the first few frames")
	muzzle._process(0.16)
	_check(not flame_jet.visible and not muzzle._flash.visible and muzzle.get_node("Smoke") != null, "hot gas clears the aim line within 0.28 seconds while light propellant smoke remains")
	muzzle.free()
	machine_muzzle.free()
	rocket_muzzle.free()
	var muzzle_effects: Array[ExplosionFX] = []
	for index in ExplosionFX.MAX_MUZZLES + 3:
		var discharge := ExplosionFX.create_muzzle(Vector3.ZERO, Vector3.FORWARD)
		add_child(discharge)
		muzzle_effects.append(discharge)
	_check(get_tree().get_nodes_in_group("muzzle_fx").size() == ExplosionFX.MAX_MUZZLES and get_tree().get_nodes_in_group("impact_flash_lights").size() <= ExplosionFX.MAX_FLASH_LIGHTS, "concurrent discharges and local flash lights remain capped in a large battle")
	# Every slot is occupied by AI smoke; player feedback still has to start.
	for discharge: ExplosionFX in muzzle_effects:
		discharge._age = 0.7
	var player_muzzle := ExplosionFX.create_muzzle(Vector3.ZERO, Vector3.FORWARD, 1.0, "cannon", true)
	add_child(player_muzzle)
	_check(not player_muzzle.is_queued_for_deletion() and player_muzzle._flash != null and player_muzzle._light != null and get_tree().get_nodes_in_group("muzzle_fx").size() == ExplosionFX.MAX_MUZZLES and get_tree().get_nodes_in_group("impact_flash_lights").size() <= ExplosionFX.MAX_FLASH_LIGHTS, "player discharge retires old AI smoke and receives a light without increasing either battle budget")
	_check(muzzle_effects[0].is_queued_for_deletion() and not muzzle_effects[0].is_in_group("muzzle_fx"), "reclaimed smoke leaves the active muzzle group immediately in the same firing frame")
	player_muzzle.free()
	for discharge: ExplosionFX in muzzle_effects:
		discharge.free()
	# Exercise light contention independently: destruction occupies every light.
	var light_effects: Array[ExplosionFX] = []
	for index in ExplosionFX.MAX_FLASH_LIGHTS:
		var lit_blast := ExplosionFX.create(Vector3.ZERO)
		add_child(lit_blast)
		light_effects.append(lit_blast)
	player_muzzle = ExplosionFX.create_muzzle(Vector3.ZERO, Vector3.FORWARD, 1.0, "cannon", true)
	add_child(player_muzzle)
	_check(player_muzzle._light != null and get_tree().get_nodes_in_group("impact_flash_lights").size() == ExplosionFX.MAX_FLASH_LIGHTS, "player light replaces an existing fading flash even when all light slots belong to explosions")
	player_muzzle.free()
	for lit_blast: ExplosionFX in light_effects:
		lit_blast.free()
	var effects: Array[ExplosionFX] = []
	for index in ExplosionFX.MAX_IMPACTS + 6:
		var impact := ExplosionFX.create_impact(Vector3.ZERO, false, "ground", Vector3.UP, "machine_gun")
		add_child(impact)
		effects.append(impact)
	_check(get_tree().get_nodes_in_group("impact_fx").size() == ExplosionFX.MAX_IMPACTS, "simultaneous impact effects are capped under sustained machine-gun fire")
	for impact: ExplosionFX in effects:
		impact.free()
	print("EXPLOSION_FX_RESULT: %d passed, %d failed" % [passed, failed])
	# This entire resource test otherwise runs in one frame. Let submitted
	# positional voices enter the audio mixer before the shared stop routine.
	await get_tree().create_timer(0.08).timeout
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)


func _hot_energy(image: Image, frame: int) -> float:
	var energy := 0.0
	var width := image.get_width() / 5.0
	var height := image.get_height() / 5.0
	for y in range(int(frame / 5) * int(height), int((int(frame / 5) + 1) * height), 3):
		for x in range(int((frame % 5) * width), int((frame % 5 + 1) * width), 3):
			var pixel := image.get_pixel(x, y)
			energy += maxf(0, pixel.r - pixel.b - 0.1) * pixel.a
	return energy


func _first_hot_bounds(image: Image) -> Rect2:
	var minimum := Vector2.ONE
	var maximum := Vector2.ZERO
	var tile := Vector2(image.get_width(), image.get_height()) / 5.0
	for y in int(tile.y):
		for x in int(tile.x):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.15 and pixel.r - pixel.b > 0.15:
				var uv := Vector2(x, y) / tile
				minimum = minimum.min(uv)
				maximum = maximum.max(uv)
	return Rect2(minimum, maximum - minimum)
