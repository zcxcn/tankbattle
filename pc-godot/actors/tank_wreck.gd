class_name TankWreck
extends StaticBody3D
## A persistent, solid copy of the destroyed vehicle. Meshes stay shared, while
## charred material overrides and detached turret motion belong to the wreck.

const MAX_WRECKS := 14
const MAX_BURNING_WRECKS := 6
const BURN_SECONDS := 27.0
const COOKOFF_CHANCE := 0.25
const COOKOFF_RADIUS := 9.0
const COOKOFF_DAMAGE := 44.0

var game: Node
var variant := 0 # 0 engine fire; 1 fractured turret ring; 2 ammunition fire.
var will_cook_off := false
var cooked_off := false
var age := 0.0
var cookoff_time := 4.0
var _model: Node3D
var _turret: Node3D
var _turret_velocity := Vector3.ZERO
var _turret_spin := Vector3.ZERO
var _turret_airborne := false
var _turret_bounced := false
var _emitters: Array[GPUParticles3D] = []
var _rng := RandomNumberGenerator.new()
static var _charred_material: ShaderMaterial


static func create_from_tank(tank: TankActor, variant_override := -1, cookoff_override := -1) -> TankWreck:
	var wreck := TankWreck.new()
	wreck.name = "TankWreck"
	wreck.game = tank.game
	wreck.transform = tank.global_transform
	wreck._rng.randomize()
	wreck.variant = variant_override if variant_override >= 0 else wreck._rng.randi_range(0, 2)
	wreck.will_cook_off = cookoff_override == 1 if cookoff_override >= 0 else wreck._rng.randf() < COOKOFF_CHANCE
	wreck.cookoff_time = wreck._rng.randf_range(3.3, 7.2)
	wreck.set_meta("source_archetype", tank.archetype)
	wreck.set_meta("source_team", tank.team)
	var original := tank.get_node_or_null("ArmoredModel") as Node3D
	if original != null:
		wreck._model = original.duplicate(0) as Node3D
		wreck._model.name = "BurntArmoredModel"
		wreck.add_child(wreck._model)
		wreck._turret = wreck._model.get_node_or_null("TurretPivot") as Node3D
		for node: Node in wreck._model.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			mesh.material_override = _burnt_material()
			mesh.material_overlay = null
			# Track materials are shared resources; replacing an override never
			# changes another live tank's paint or shader uniforms.
		for node: Node in wreck._model.find_children("*", "Light3D", true, false):
			node.free()
	var original_shape := tank.get_node_or_null("HullCollision") as CollisionShape3D
	if original_shape != null:
		var collider := CollisionShape3D.new()
		collider.name = "WreckCollision"
		collider.shape = original_shape.shape
		collider.transform = original_shape.transform
		wreck.add_child(collider)
	return wreck


func _ready() -> void:
	add_to_group("combat_effects")
	add_to_group("tank_wrecks")
	collision_layer = 1
	collision_mask = 0
	var existing := get_tree().get_nodes_in_group("tank_wrecks")
	while existing.size() > MAX_WRECKS:
		var oldest: Node = existing.pop_front()
		if oldest != self:
			oldest.remove_from_group("tank_wrecks")
			oldest.collision_layer = 0
			oldest.queue_free()
	if variant == 1:
		_launch_turret(3.7)
	if get_tree().get_nodes_in_group("burning_wrecks").size() < MAX_BURNING_WRECKS:
		add_to_group("burning_wrecks")
		_build_burning_effects()
	_set_simulation_speed(1.0 if _combat_running() else 0.0)
	if is_instance_valid(game) and game.has_method("spawn_explosion"):
		game.spawn_explosion(global_position + Vector3.UP * 0.9, 1.5 if get_meta("source_archetype", "") == "boss" else 1.0)
	if will_cook_off and _combat_running() and game.has_method("notify") and "player" in game:
		var player: Node = game.get("player")
		if player is TankActor and not player.destroyed and global_position.distance_to(player.global_position) < 24.0:
			game.notify("残骸弹药正在燃烧 · 远离车体 9 米", 2.0)


func _combat_running() -> bool:
	return is_instance_valid(game) and game.has_method("is_combat_running") and game.is_combat_running()


func _physics_process(delta: float) -> void:
	var running := _combat_running()
	var mode: String = str(game.get("mode")) if is_instance_valid(game) and "mode" in game else "playing"
	var visual_running: bool = running or mode in ["won", "lost"]
	_set_simulation_speed(1.0 if visual_running else 0.0)
	if not visual_running:
		return
	age += delta
	if running and will_cook_off and not cooked_off and age >= cookoff_time:
		_detonate()
	_update_turret(delta)
	if age >= BURN_SECONDS and is_in_group("burning_wrecks"):
		remove_from_group("burning_wrecks")
		for particles: GPUParticles3D in _emitters:
			if is_instance_valid(particles):
				particles.emitting = false
	if age >= BURN_SECONDS + 6.0 and not _emitters.is_empty():
		for particles: GPUParticles3D in _emitters:
			if is_instance_valid(particles):
				particles.queue_free()
		_emitters.clear()


func _set_simulation_speed(value: float) -> void:
	for particles: GPUParticles3D in _emitters:
		if is_instance_valid(particles):
			particles.speed_scale = value


func _launch_turret(strength: float) -> void:
	if not is_instance_valid(_turret):
		return
	if _turret.get_parent() != self:
		_turret.reparent(self, true)
	_turret_velocity = Vector3(_rng.randf_range(-2.0, 2.0), strength, _rng.randf_range(-2.0, 2.0))
	_turret_spin = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.1, 1.1), _rng.randf_range(-0.6, 0.6))
	_turret_airborne = true
	_turret_bounced = false


func _update_turret(delta: float) -> void:
	if not _turret_airborne or not is_instance_valid(_turret):
		return
	var from := _turret.global_position
	_turret_velocity.y -= 9.8 * delta
	var next := from + _turret_velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, next - Vector3.UP * 0.25, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_turret.global_position = hit.position + hit.normal * 0.28
		if not _turret_bounced and _turret_velocity.length() > 2.0:
			_turret_velocity = _turret_velocity.bounce(hit.normal) * 0.19
			_turret_spin *= 0.2
			_turret_bounced = true
		else:
			_turret_airborne = false
	else:
		_turret.global_position = next
		_turret.rotate_x(_turret_spin.x * delta)
		_turret.rotate_y(_turret_spin.y * delta)
		_turret.rotate_z(_turret_spin.z * delta)
	# Defensive floor for isolated test worlds and maps without a local floor.
	if _turret.global_position.y < global_position.y + 0.25:
		_turret.global_position.y = global_position.y + 0.25
		_turret_airborne = false


func _detonate() -> void:
	if cooked_off or not _combat_running():
		return
	cooked_off = true
	_launch_turret(9.0)
	var at := global_position + Vector3.UP * 1.5
	game.spawn_explosion(at, 1.35)
	# Neutral secondary damage may hit either faction. The wreck's own hull
	# is explicitly excluded from LOS; intervening buildings still shield tanks.
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		if not _combat_running():
			break
		if not node is TankActor or not game.is_ancestor_of(node):
			continue
		var tank := node as TankActor
		if not tank.is_targetable():
			continue
		var distance := global_position.distance_to(tank.global_position)
		if distance > COOKOFF_RADIUS:
			continue
		var query := PhysicsRayQueryParameters3D.create(at, tank.global_position + Vector3.UP, 1, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var falloff := lerpf(1.0, 0.3, distance / COOKOFF_RADIUS)
		tank.receive_damage(COOKOFF_DAMAGE * falloff, -1, at)


func _build_burning_effects() -> void:
	var origin := Vector3(0.0, 1.1, 1.3) if variant == 0 else Vector3(0.0, 1.8, 0.0)
	_add_burn_layer("WreckFire", "Fire", origin, 12, 0.95, 0.7, 1.35)
	_add_burn_layer("WreckSmoke", "Smoke", origin + Vector3.UP * 0.55, 22, 5.0, 1.18, 1.5)
	if variant == 2:
		_add_burn_layer("EscapingFlame", "Fire", Vector3(0.8, 1.7, -0.35), 6, 0.65, 0.36, 2.2)


func _add_burn_layer(label: String, sprite: String, at: Vector3, amount: int, duration: float, size: float, speed: float) -> void:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.position = at
	particles.amount = amount
	particles.lifetime = duration
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-14, -3, -14), Vector3(28, 27, 28))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.46
	process.direction = Vector3.UP
	process.spread = 18.0 if sprite == "Smoke" else 30.0
	process.initial_velocity_min = speed * 0.7
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.35, 0.26, 0.12)
	process.damping_min = 0.2
	process.damping_max = 0.4
	process.scale_min = size * 0.7
	process.scale_max = size
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_curve = ExplosionFX._growth_curve([Vector2(0, 0.45), Vector2(0.3, 1.1), Vector2(1, 2.6 if sprite == "Smoke" else 0.65)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.2, 0.18, 0.16, 0.0))
	gradient.set_color(1, Color(0.17, 0.16, 0.14, 0.0))
	gradient.add_point(0.14, Color(0.13, 0.12, 0.11, 0.83) if sprite == "Smoke" else Color(2.4, 1.2, 0.25, 0.88))
	gradient.add_point(0.6, Color(0.19, 0.18, 0.16, 0.55) if sprite == "Smoke" else Color(1.3, 0.22, 0.02, 0.48))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	ramp.use_hdr = sprite == "Fire"
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.65
	quad.material = ExplosionFX._sprite_material(sprite)
	particles.draw_pass_1 = quad
	add_child(particles)
	_emitters.append(particles)


static func _burnt_material() -> ShaderMaterial:
	if _charred_material != null:
		return _charred_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() { local_position = VERTEX; local_normal = NORMAL; }
void fragment() {
    vec3 p = local_position * 5.0;
    float soot = fract(sin(dot(floor(p), vec3(127.1,311.7,74.7))) * 43758.5453);
    float abrasion = pow(max(0.0, local_normal.y), 3.0);
    ALBEDO = mix(vec3(0.025,0.027,0.025), vec3(0.115,0.077,0.043), soot * 0.5 + abrasion * 0.25);
    METALLIC = 0.62;
    ROUGHNESS = 0.82;
}
"""
	_charred_material = ShaderMaterial.new()
	_charred_material.shader = shader
	_charred_material.resource_name = "SharedScorchedSteel"
	return _charred_material
