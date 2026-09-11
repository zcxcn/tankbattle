extends Node3D
## GPU-only model/rig inspection; stores actual rendered views.
var player: Node3D
var monster: CharacterBody3D
func is_combat_running() -> bool:
	return true
func get_monster_goal(_monster: Node3D) -> Vector3:
	return Vector3(0, 0, 120)
func monster_killed(_monster: Node3D, _reward: int) -> void:
	pass
func monster_reached_base(_monster: Node3D, _damage: float) -> void:
	pass
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	if not "--test" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1400, 900)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.10, 0.135, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.67, 0.78)
	environment.environment.ambient_light_energy = 0.55
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -30, 0)
	light.light_energy = 2.4
	light.shadow_enabled = true
	add_child(light)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(120, 120)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.20, 0.23, 0.21)
	ground.material_override = ground_material
	add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(13, 7, 24)
	camera.fov = 57
	add_child(camera)
	camera.look_at(Vector3(0, 5.0, 0))
	monster = preload("res://actors/giant_monster.gd").new()
	monster.game = self
	monster.director = self
	monster.rotation.y = PI
	add_child(monster)
	monster.set_physics_process(false)
	for frame in 120:
		monster._tick_walk(1.0 / 60.0)
		await get_tree().process_frame
	await capture("01-creature-front")
	camera.position = Vector3(-4, 3.4, 15)
	camera.look_at(Vector3(0, 5.6, 0))
	for frame in 80:
		monster._tick_walk(1.0 / 60.0)
		await get_tree().process_frame
	await capture("02-creature-close")
	monster.receive_damage(5000, 0)
	for frame in 170:
		monster._tick_corpse(1.0 / 60.0)
		await get_tree().process_frame
	camera.position = Vector3(12, 10, 16)
	camera.look_at(Vector3(0, 1.5, 3.0))
	await capture("03-creature-fallen")
	print("MONSTER VISUAL PASS: 3 actual GPU captures")
	await preload("res://tests/test_shutdown.gd").finish(get_tree())
func capture(label: String) -> void:
	for frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../work/asset-review/monsters-0.4.8")
	DirAccess.make_dir_recursive_absolute(directory)
	get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
