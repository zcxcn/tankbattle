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
	_check(effect.is_in_group("combat_effects") and is_equal_approx(effect._duration, 2.8), "effect retains its cleanup group and original lifetime")
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
	_check(textured_layers and total_particles == 122, "all four bounded particle layers preserve simulated size and use soft textures")
	for label in ["Smoke", "Dust"]:
		var particles := effect.get_node(label) as GPUParticles3D
		var material := (particles.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		var process := particles.process_material as ParticleProcessMaterial
		_check(material.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and not material.emission_enabled and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, label + " is lit matte matter instead of additive glowing rectangles")
		_check(process.scale_curve.curve.sample(1.0) > process.scale_curve.curve.sample(0.0) * 3.0 and process.color_ramp.gradient.sample(0.0).a == 0.0 and process.color_ramp.gradient.sample(1.0).a == 0.0, label + " expands and fades smoothly at birth and expiry")
	var fire_process := (effect.get_node("Fire") as GPUParticles3D).process_material as ParticleProcessMaterial
	var hot: Color = fire_process.color_ramp.gradient.sample(0.07)
	var cool: Color = fire_process.color_ramp.gradient.sample(0.64)
	_check(hot.a > 0.7 and hot.r > cool.r and hot.g > cool.g and fire_process.color_ramp.gradient.sample(1.0).a == 0.0, "fire transitions from a hot bright core to cool fading embers")
	effect.free()
	print("EXPLOSION_FX_RESULT: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
