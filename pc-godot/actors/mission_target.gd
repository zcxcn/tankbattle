extends StaticBody3D
## A real destructible objective, struck through the same collider as scenery.

var game: Node3D
var hp := 320.0
var destroyed := false
var label: Label3D

func _ready() -> void:
	name = "EnemyFuelDepot"
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 4.5, 7.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 2.25
	add_child(collider)
	var steel := ArtFactory.material(Color("765542"), 0.5, 0.68)
	var support := ArtFactory.material(Color("45473e"), 0.25, 0.85)
	for x in [-2.2, 2.2]:
		ArtFactory.add_cylinder(self, "FuelTank", Vector3(x, 2.0, 0), 1.7, 4.0, steel)
		ArtFactory.add_box(self, "Foundation", Vector3(x, 0.15, 0), Vector3(3.9, 0.3, 4.6), support)
	label = Label3D.new()
	label.text = "敌军燃料库 · 炮击摧毁"
	label.position = Vector3(0, 6.0, 0)
	label.font_size = 44
	label.pixel_size = 0.016
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("ffbf78")
	add_child(label)

func receive_damage(amount: float, attacker_team: int, _at := Vector3.ZERO) -> void:
	if destroyed or attacker_team != 0 or game == null or not game.is_combat_running():
		return
	hp = maxf(0.0, hp - maxf(0.0, amount))
	label.text = "敌军燃料库 · %d%%" % ceili(hp / 320.0 * 100.0)
	if hp <= 0.0:
		destroyed = true
		collision_layer = 0
		visible = false
		game.spawn_explosion(global_position + Vector3.UP * 2.0, 1.8)
		game.notify("燃料库已摧毁 · 指挥车暴露", 3.0)
