class_name DestructibleCover
extends StaticBody3D
## Cheap battlefield cover with explicit health and a physical destruction transition.

var game: Node
var hp := 110.0
var size := Vector3(5.0, 1.5, 1.1)
var surface: Material
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = size.y * 0.5
	add_child(collider)
	var box := BoxMesh.new()
	box.size = size
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.position.y = size.y * 0.5
	_mesh.material_override = surface
	add_child(_mesh)
	add_to_group("destructible_cover")


func receive_damage(amount: float, _attacker_team: int, hit_position: Vector3) -> void:
	hp -= amount
	if hp > 0.0:
		return
	collision_layer = 0
	game.spawn_explosion(global_position + Vector3.UP * 0.5, 0.72)
	for index in range(5):
		var fragment := RigidBody3D.new()
		fragment.mass = 18.0
		fragment.position = global_position + Vector3(randf_range(-1.8, 1.8), randf_range(0.4, 1.2), randf_range(-0.35, 0.35))
		var fragment_size := Vector3(randf_range(0.45, 1.2), randf_range(0.35, 0.8), randf_range(0.35, 0.75))
		var fragment_mesh := BoxMesh.new()
		fragment_mesh.size = fragment_size
		var view := MeshInstance3D.new()
		view.mesh = fragment_mesh
		view.material_override = surface
		fragment.add_child(view)
		var fragment_shape := BoxShape3D.new()
		fragment_shape.size = fragment_size
		var fragment_collider := CollisionShape3D.new()
		fragment_collider.shape = fragment_shape
		fragment.add_child(fragment_collider)
		game.add_child(fragment)
		fragment.apply_central_impulse(Vector3(randf_range(-5.0, 5.0), randf_range(4.0, 8.0), randf_range(-4.0, 4.0)) * fragment.mass)
		game.schedule_cleanup(fragment, 5.0)
	queue_free()
