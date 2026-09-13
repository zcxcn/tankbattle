extends Spatial
var game
var velocity=Vector3.ZERO
var damage=60.0
var team=0
var weapon=0
var life=2.0
var shooter
var previous

func setup(owner_game, source, at, direction, kind, power):
	game=owner_game
	shooter=source
	team=source.team
	weapon=kind
	damage=power
	translation=at
	previous=at
	velocity=direction*(110.0 if kind==3 else (330.0 if kind==1 else 260.0))
	life=3.0 if kind==3 else 1.6
	var path=["ap_shell","machine_gun_bullet","he_shell","rocket"][kind]
	var mesh=load("res://assets/models/ordnance/"+path+".glb").instance()
	mesh.scale=Vector3.ONE*(1.7 if kind==1 else 1.0)
	add_child(mesh)
	look_at_from_position(at,at+direction,Vector3.UP)

func _physics_process(delta):
	life-=delta
	var at=global_transform.origin
	var end=at+velocity*delta
	var excluded=[]
	if is_instance_valid(shooter):excluded.append(shooter)
	var result=get_world().direct_space_state.intersect_ray(at,end,excluded,3,true,true)
	if not result.empty():
		var hit=result.collider
		if hit.has_method("take_damage"):
			if hit.team != team:hit.take_damage(damage,team)
		game.impact(result.position,weapon,team,damage,hit)
		queue_free()
		return
	translation=end
	if life<=0:queue_free()
