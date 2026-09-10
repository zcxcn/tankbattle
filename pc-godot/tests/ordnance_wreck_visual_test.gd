extends Node3D
## GPU-only authored model and destruction review. Screenshots are real renders.

const OUTPUT := "res://../work/pc040-ordnance-review"
var mode := "playing"
var camera: Camera3D
var stage: Node3D
var title: Label


func _ready() -> void:
	call_deferred("_run")


func is_combat_running() -> bool:
	return mode == "playing"


func notify(_message: String, _duration: float) -> void:
	pass


func spawn_explosion(at: Vector3, strength: float) -> void:
	add_child(ExplosionFX.create(at, strength))


func _setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("333d48")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8d2e0")
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.7
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -24, 0)
	sun.light_energy = 2.4
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 150, 0)
	fill.light_color = Color("b7cee8")
	fill.light_energy = 0.55
	add_child(fill)
	var floor_surface := ArtFactory.material(Color("6a685f"), 0.05, 0.91)
	ArtFactory.add_box(self, "Ground", Vector3(0, -0.15, 0), Vector3(90, 0.3, 90), floor_surface, true)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 200.0
	camera.fov = 47.0
	add_child(camera)
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var bar := ColorRect.new()
	bar.color = Color(0.02, 0.03, 0.04, 0.82)
	bar.size = Vector2(1920, 116)
	canvas.add_child(bar)
	title = Label.new()
	title.position = Vector2(42, 22)
	title.add_theme_font_size_override("font_size", 30)
	canvas.add_child(title)


func _capture(label: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(label + ".png")))
	print("CAPTURED: " + label)


func _clear_effects() -> void:
	for node: Node in get_tree().get_nodes_in_group("combat_effects"):
		if is_instance_valid(node):
			node.free()


func _run() -> void:
	_setup()
	stage = Node3D.new()
	add_child(stage)
	title.text = "钢铁余烬 0.4.0 · 实体弹药建模检视\n原始 GLB 网格 / 弧形弹头 / 铜制弹带 / 引信 / 火箭尾翼与喷口（仅此检视放大）"
	var kinds := ["cannon", "he", "machine_gun", "rocket"]
	var sizes := [2.7, 2.7, 24.0, 1.65]
	var labels := ["穿甲弹", "高爆弹", "12.7 mm 弹头", "反装甲火箭"]
	for index in kinds.size():
		var model := (IronProjectile.ORDNANCE[kinds[index]] as PackedScene).instantiate() as Node3D
		model.position = Vector3((float(index) - 1.5) * 1.55, 0.90, 0)
		model.rotation.x = PI * 0.5
		model.scale = Vector3.ONE * float(sizes[index])
		stage.add_child(model)
		ArtFactory.add_box(stage, "Plinth", Vector3(model.position.x, 0.075, 0), Vector3(1.15, 0.15, 1.15), ArtFactory.material(Color("202830"), 0.35, 0.5))
		var label := Label3D.new()
		label.text = labels[index]
		label.position = Vector3(model.position.x, 0.35, 0.75)
		label.font_size = 46
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage.add_child(label)
	camera.position = Vector3(1.8, 2.7, 6.4)
	camera.look_at(Vector3(0, 1, 0))
	await _capture("01-solid-ordnance", 1.3)
	stage.free()
	stage = null
	title.text = "钢铁余烬 0.4.0 · 三种实体残骸\n发动机舱起火 / 炮塔环破坏与脱落 / 弹药舱喷火 · 原车模型保留，焦黑钢铁材质"
	var wrecks: Array[TankWreck] = []
	for index in 3:
		var tank := TankActor.new()
		tank.game = self
		tank.position = Vector3((float(index) - 1.0) * 11.0, 0.02, 0)
		tank.is_player = true
		tank.archetype = ["scout", "line", "heavy"][index]
		add_child(tank)
		tank.set_physics_process(false)
		tank.set_process(false)
		var wreck := TankWreck.create_from_tank(tank, index, 0)
		add_child(wreck)
		wrecks.append(wreck)
		tank.free()
	camera.current = true
	camera.position = Vector3(16, 14, 31)
	camera.look_at(Vector3(0, 1.5, 0))
	await _capture("02-wreck-initial-explosions", 0.36)
	await _capture("03-wrecks-burning", 3.8)
	var central: TankWreck = wrecks[1]
	central.will_cook_off = true
	central.cookoff_time = central.age + 0.2
	title.text = "钢铁余烬 0.4.0 · 延迟弹药殉爆\n25% 概率 / 炮塔被冲击抛飞 / 周围 9 米双方受伤 / 建筑可遮挡"
	await _capture("04-cookoff-flash", 0.42)
	await _capture("05-cookoff-turret-flight", 0.42)
	await _capture("06-cookoff-smoke", 1.3)
	_clear_effects()
	camera.position = Vector3(11, 10, 18)
	camera.look_at(Vector3(0, 1, 0))
	title.text = "钢铁余烬 0.4.0 · 高爆弹冲击\n强闪光 → 火焰团 → 径向尘土 → 金属碎片与残烟 / 8 米伤害范围"
	add_child(ExplosionFX.create_impact(Vector3(0, 0.1, 0), true, "ground", Vector3.UP, "he"))
	await _capture("07-he-fire-front", 0.2)
	await _capture("08-he-expanding-dust", 0.5)
	await _capture("09-he-lingering-smoke", 1.1)
	_clear_effects()
	await get_tree().process_frame
	print("ORDNANCE_WRECK_VISUAL_RESULT: captured 9 GPU frames")
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0)
