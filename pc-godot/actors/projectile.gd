class_name IronProjectile
extends Node3D
## Ballistic flight with swept collision on every substep. Visual trails never
## decide hits, and the launcher's RID stays excluded for the whole flight.

const MAX_SWEEP_LENGTH := 4.0
const MAX_ROCKET_TRAILS := 14
const ORDNANCE := {
	"cannon": preload("res://assets/models/ordnance/ap_shell.glb"),
	"he": preload("res://assets/models/ordnance/he_shell.glb"),
	"machine_gun": preload("res://assets/models/ordnance/machine_gun_bullet.glb"),
	"rocket": preload("res://assets/models/ordnance/rocket.glb"),
}

var game: Node
var owner_tank: TankActor
var team := 0
var direction := Vector3.FORWARD
var speed := 260.0
var damage := 34.0
var splash_radius := 0.0
var weapon_kind := "cannon"
var lifetime := 8.0
var flight_velocity := Vector3.ZERO
var gravity := 0.85
var has_tracer := false
var _previous := Vector3.ZERO
var _trail: GPUParticles3D
var _resolved := false
static var _tracer_material: StandardMaterial3D
static var _tracer_mesh: SphereMesh


func _ready() -> void:
	_previous = global_position
	gravity = 0.0 if weapon_kind == "rocket" else 9.8
	# The tank's articulated barrel has already applied fire control. Respect
	# its real direction even at near-zero pitch; never compensate it twice.
	flight_velocity = direction.normalized() * speed
	has_tracer = weapon_kind != "machine_gun"
	if weapon_kind == "machine_gun":
		var shot_index := int(owner_tank.get_meta("tracer_shots", 0)) if is_instance_valid(owner_tank) else 0
		has_tracer = shot_index % 4 == 0
		if is_instance_valid(owner_tank):
			owner_tank.set_meta("tracer_shots", shot_index + 1)
	_build_shell()
	if weapon_kind == "rocket":
		_spawn_rocket_trail()
	_align_to_velocity()


static func ballistic_direction(origin: Vector3, target: Vector3, forward: Vector3, muzzle_speed: float, acceleration: float) -> Vector3:
	var planar := Vector3(forward.x, 0.0, forward.z).normalized()
	var offset := target - origin
	var distance := Vector2(offset.x, offset.z).length()
	if distance < 1.0 or acceleration <= 0.0 or muzzle_speed <= 0.0:
		return forward.normalized()
	var speed_squared := muzzle_speed * muzzle_speed
	var discriminant := speed_squared * speed_squared - acceleration * (acceleration * distance * distance + 2.0 * offset.y * speed_squared)
	if discriminant < 0.0:
		# Unreachable selections remain real shots; never teleport to the aim.
		return (planar + Vector3.UP * 0.35).normalized()
	var tangent := (speed_squared - sqrt(discriminant)) / (acceleration * distance)
	return (planar + Vector3.UP * tangent).normalized()


func _physics_process(delta: float) -> void:
	if _resolved or game == null or not game.is_combat_running():
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_finish()
		return
	var steps := maxi(1, int(ceil(flight_velocity.length() * delta / MAX_SWEEP_LENGTH)))
	# Curved substeps preserve thin-wall/ground collision during slow frames.
	if weapon_kind == "he":
		steps = maxi(steps, int(ceil(delta * 120.0)))
	var step := delta / float(steps)
	var acceleration := Vector3.DOWN * gravity
	var mask := 1 | (4 if team == 0 else 2)
	var exclude: Array[RID] = []
	if is_instance_valid(owner_tank):
		exclude.append(owner_tank.get_rid())
	for index in steps:
		var next := _previous + flight_velocity * step + acceleration * (0.5 * step * step)
		var query := PhysicsRayQueryParameters3D.create(_previous, next, mask, exclude)
		query.collide_with_areas = false
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit["position"]
			_impact(hit)
			return
		flight_velocity += acceleration * step
		_previous = next
	global_position = _previous
	direction = flight_velocity.normalized()
	_align_to_velocity()


func _align_to_velocity() -> void:
	if flight_velocity.length_squared() > 0.01:
		var up := Vector3.RIGHT if absf(flight_velocity.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
		look_at(global_position + flight_velocity, up)


func _impact(hit: Dictionary) -> void:
	if _resolved:
		return
	_resolved = true
	var at: Vector3 = hit.get("position", global_position)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider: Object = hit.get("collider")
	var armored: bool = collider is TankActor or (collider is Node and collider.is_in_group("tank_wrecks"))
	var surface_kind := "armor" if armored else ("ground" if normal.y > 0.55 else "stone")
	if collider is TankActor:
		collider.receive_damage(damage, team, at, weapon_kind)
	elif collider != null and collider.has_method("receive_damage"):
		collider.call("receive_damage", damage, team, at)
	if splash_radius > 0.0:
		game.radial_damage(at, splash_radius, damage * 0.55, team, {}, weapon_kind)
	game.spawn_impact(at, splash_radius > 0.0, surface_kind, normal, weapon_kind, collider is TankActor and collider.is_player)
	_finish()


func _finish() -> void:
	_resolved = true
	if is_instance_valid(_trail) and is_instance_valid(game) and game.is_inside_tree():
		# Existing smoke stays where the rocket travelled; the bound tween and
		# combat_effects group respect pause and scene exit.
		_trail.emitting = false
		_trail.reparent(game, true)
		var cleanup := _trail.create_tween()
		cleanup.tween_interval(_trail.lifetime + 0.1)
		cleanup.tween_callback(_trail.queue_free)
		_trail = null
	queue_free()


func _build_shell() -> void:
	if _tracer_material == null:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_material.albedo_color = Color("ffca77")
		_tracer_material.emission_enabled = true
		_tracer_material.emission = Color("ffb64d")
		_tracer_material.emission_energy_multiplier = 2.0
		_tracer_mesh = SphereMesh.new()
		_tracer_mesh.radius = 0.024
		_tracer_mesh.height = 0.048
		_tracer_mesh.radial_segments = 12
		_tracer_mesh.rings = 6
		_tracer_mesh.material = _tracer_material
	var model: PackedScene = ORDNANCE.get(weapon_kind, ORDNANCE.cannon)
	var shell := model.instantiate() as Node3D
	shell.name = "Shell"
	for part: Node in shell.find_children("*", "MeshInstance3D"):
		(part as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	if has_tracer:
		# A compact burning base is visible from behind. It is not a drawn line,
		# beam or stretched cylinder: the solid ordnance remains the projectile.
		var tracer := MeshInstance3D.new()
		tracer.name = "Tracer"
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.mesh = _tracer_mesh
		tracer.position.z = 0.48 if weapon_kind == "rocket" else (0.025 if weapon_kind == "machine_gun" else 0.25)
		tracer.scale = Vector3.ONE * (0.36 if weapon_kind == "machine_gun" else (1.5 if weapon_kind == "rocket" else 0.8))
		add_child(tracer)


func _spawn_rocket_trail() -> void:
	if get_tree().get_nodes_in_group("rocket_trails").size() >= MAX_ROCKET_TRAILS:
		return
	_trail = GPUParticles3D.new()
	_trail.name = "RocketSmoke"
	_trail.add_to_group("combat_effects")
	_trail.add_to_group("rocket_trails")
	_trail.position.z = 0.38
	_trail.amount = 32
	_trail.lifetime = 0.8
	_trail.fixed_fps = 60
	_trail.local_coords = false
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visibility_aabb = AABB(Vector3(-70, -10, -70), Vector3(140, 35, 140))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 0, 1)
	process.spread = 18.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.2
	process.gravity = Vector3(0.15, 0.5, 0)
	process.scale_min = 0.12
	process.scale_max = 0.22
	process.scale_curve = ExplosionFX._growth_curve([Vector2(0, 0.3), Vector2(0.3, 1.2), Vector2(1, 2.8)])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.48, 0.45, 0.4, 0.3))
	gradient.set_color(1, Color(0.38, 0.38, 0.36, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	_trail.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = ExplosionFX._sprite_material("Smoke")
	_trail.draw_pass_1 = quad
	add_child(_trail)
	_trail.emitting = true
