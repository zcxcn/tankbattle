class_name IronProjectile
extends Node3D
## Continuous swept projectile; damage is resolved before visuals are destroyed.

var game: Node
var owner_tank: TankActor
var team := 0
var direction := Vector3.FORWARD
var speed := 58.0
var damage := 34.0
var splash_radius := 0.0
var weapon_kind := "cannon"
var lifetime := 5.0
var _previous := Vector3.ZERO


func _ready() -> void:
	_previous = global_position
	var color := Color("ffd06b") if team == 0 else Color("ff5d48")
	var core := ArtFactory.add_sphere(self, "Shell", Vector3.ZERO, 0.14 if weapon_kind != "rocket" else 0.22, ArtFactory.material(color, 0.45, 0.24, 5.0), 12)
	core.scale.z = 2.2
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.2
	light.omni_range = 4.5
	light.shadow_enabled = false
	add_child(light)
	_spawn_trail(color)
	look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if game == null or not game.is_combat_running():
		return
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var next := global_position + direction * speed * delta
	var mask := 1 | (4 if team == 0 else 2)
	var exclude: Array[RID] = []
	if is_instance_valid(owner_tank):
		exclude.append(owner_tank.get_rid())
	var query := PhysicsRayQueryParameters3D.create(_previous, next, mask, exclude)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = next
	_previous = next


func _impact(hit: Dictionary) -> void:
	var at: Vector3 = hit.get("position", global_position)
	var collider: Object = hit.get("collider")
	if collider is TankActor:
		(collider as TankActor).receive_damage(damage, team, at)
	elif collider != null and collider.has_method("receive_damage"):
		collider.call("receive_damage", damage, team, at)
	if splash_radius > 0.0:
		game.radial_damage(at, splash_radius, damage * 0.55, team)
	game.spawn_impact(at, splash_radius > 0.0)
	queue_free()


func _spawn_trail(color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 0.32
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 0, 1)
	process.spread = 5.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.7
	process.scale_min = 0.08
	process.scale_max = 0.18
	process.color = color
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var surface := StandardMaterial3D.new()
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.albedo_color = Color(color, 0.7)
	quad.material = surface
	particles.draw_pass_1 = quad
	add_child(particles)
	particles.emitting = true
