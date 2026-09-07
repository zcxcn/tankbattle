class_name TankMine
extends Node3D
## Team-aware mine with a visible arming cycle and EMP-safe disposal.

var game: Node
var team := 0
var armed_after := 1.2
var lifetime := 90.0
var trigger_radius := 3.7
var damage := 92.0
var source_tank: TankActor
var _light: OmniLight3D
var _ring: MeshInstance3D
var _exploded := false
var _previous_tank_positions: Dictionary = {}


func _ready() -> void:
	add_to_group("mines")
	var team_color := Color("42d9e8") if team == 0 else Color("ff4e41")
	ArtFactory.add_cylinder(self, "MineBody", Vector3(0, 0.16, 0), 0.62, 0.28, ArtFactory.material(Color("252b25"), 0.82, 0.35), 18)
	_ring = ArtFactory.add_torus(self, "TeamRing", Vector3(0, 0.32, 0), 0.58, 0.08, ArtFactory.material(team_color, 0.1, 0.3, 4.0))
	for angle in range(0, 360, 45):
		var spike := ArtFactory.add_box(self, "Spike", Vector3(0, 0.13, -0.82).rotated(Vector3.UP, deg_to_rad(angle)), Vector3(0.11, 0.11, 0.52), ArtFactory.material(Color("4c5147"), 0.75, 0.38))
		spike.rotation.y = deg_to_rad(angle)
	_light = OmniLight3D.new()
	_light.position.y = 0.46
	_light.light_color = team_color
	_light.light_energy = 0.8
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	add_child(_light)


func _physics_process(delta: float) -> void:
	if game == null or not game.is_combat_running() or _exploded:
		return
	armed_after -= delta
	lifetime -= delta
	var pulse := 0.35 + (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.32
	_light.light_energy = pulse if armed_after <= 0.0 else 0.16
	_ring.scale = Vector3.ONE * (1.0 + pulse * 0.08)
	if lifetime <= 0.0:
		queue_free()
		return
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		if not node is TankActor:
			continue
		var tank := node as TankActor
		var tank_id := tank.get_instance_id()
		var previous: Vector3 = _previous_tank_positions.get(tank_id, tank.global_position)
		_previous_tank_positions[tank_id] = tank.global_position
		if armed_after > 0.0:
			continue
		if tank.team == team or tank.destroyed or not tank.is_targetable():
			continue
		var swept_point := _closest_point_xz(previous, tank.global_position, global_position)
		if global_position.distance_to(swept_point) <= trigger_radius and game.has_line_of_sight(global_position + Vector3.UP * 0.25, swept_point + Vector3.UP):
			explode()
			return


func _closest_point_xz(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var segment := Vector2(to.x - from.x, to.z - from.z)
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return Vector3(to.x, point.y, to.z)
	var offset := Vector2(point.x - from.x, point.z - from.z)
	var fraction := clampf(offset.dot(segment) / length_squared, 0.0, 1.0)
	return Vector3(
		lerpf(from.x, to.x, fraction),
		point.y,
		lerpf(from.z, to.z, fraction)
	)


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	game.radial_damage(global_position, 5.5, damage, team)
	game.spawn_explosion(global_position, 1.15)
	AudioService.play_3d("mine", global_position, -3.0)
	queue_free()


func defuse() -> void:
	if _exploded:
		return
	_exploded = true
	game.spawn_emp_visual(global_position, 0.55)
	queue_free()
