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
	for kind in ["Fire", "Smoke", "Sparks"]:
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
		var material := (particles.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		textured_layers = textured_layers and material != null and material.albedo_texture != null and material.billboard_keep_scale
	_check(textured_layers and total_particles <= 128, "all four bounded particle layers preserve simulated size and use soft textures within the 128-particle budget")
	for label in ["Smoke", "Dust"]:
		var particles := effect.get_node(label) as GPUParticles3D
		var material := (particles.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		var process := particles.process_material as ParticleProcessMaterial
		_check(material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and not material.emission_enabled and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, label + " is lit matte matter instead of additive glowing rectangles")
		_check(process.scale_curve.curve.sample(1.0) > process.scale_curve.curve.sample(0.0) * 3.0 and process.color_ramp.gradient.sample(0.0).a == 0.0 and process.color_ramp.gradient.sample(1.0).a == 0.0, label + " expands and fades smoothly at birth and expiry")
		_check(process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB, label + " scale curve provides all XYZ channels so billboards retain visible width and height")
	var fire_process := (effect.get_node("Fire") as GPUParticles3D).process_material as ParticleProcessMaterial
	var hot: Color = fire_process.color_ramp.gradient.sample(0.07)
	var cool: Color = fire_process.color_ramp.gradient.sample(0.64)
	_check(hot.a > 0.7 and hot.r > cool.r and hot.g > cool.g and fire_process.color_ramp.gradient.sample(1.0).a == 0.0, "fire transitions from a hot bright core to cool fading embers")
	_check(fire_process.scale_curve.texture_mode == CurveTexture.TEXTURE_MODE_RGB, "fire scale curve cannot collapse its billboard onto a zero-height line")
	_check(effect.get_node("Debris") is GPUParticles3D, "destruction ejects finite GPU fragments instead of spawning rigid-body debris piles")
	effect.free()
	var heavy := ExplosionFX.create_impact(Vector3.ZERO, true, "ground", Vector3.UP, "he")
	add_child(heavy)
	heavy.set_process(false)
	var blast_dust := heavy.get_node("Dust") as GPUParticles3D
	var blast_dust_process := blast_dust.process_material as ParticleProcessMaterial
	var blast_fire_process := (heavy.get_node("Fire") as GPUParticles3D).process_material as ParticleProcessMaterial
	_check(blast_dust.lifetime > 2.0 and blast_dust_process.radial_velocity_max >= 6.0 and blast_fire_process.scale_max >= 0.89, "HE produces a broad pressure-driven dust front and substantial rolling fire")
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
