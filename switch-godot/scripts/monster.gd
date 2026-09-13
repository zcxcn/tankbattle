extends KinematicBody
const MODELS=["horror_creature/horror_creature.glb","siege_beasts/forest.glb","siege_beasts/reptile.glb","colossal/glutton.glb","colossal/golem.glb"]
var game
var team=1
var hp=200.0
var max_hp=200.0
var height=20.0
var speed=2.0
var reward=40
var damage=36.0
var dead=false
var age=0.0
var windup=0.0
var cooldown=1.5
var attack_target
var model
var animator
var stunned=0.0

func setup(owner_game,kind,wave):
	game=owner_game
	height=[18.0,26.0,58.0,36.0,70.0][kind]
	max_hp=(150+height*5)*(1+(wave-1)*0.12)
	hp=max_hp
	speed=2.4+min(wave*0.14,2.4)
	reward=int(20+height)
	damage=24+height*0.55
	model=load("res://assets/models/monsters/"+MODELS[kind]).instance()
	model.scale=Vector3.ONE*(height/1.86 if kind==0 else height)
	add_child(model)
	var anims=game.world.descendants(model,"AnimationPlayer")
	if not anims.empty():
		animator=anims[0]
		for name in animator.get_animation_list():
			if "walk" in name.to_lower() or "run" in name.to_lower():
				animator.get_animation(name).loop=true
				animator.play(name)
				break
	var cs=CollisionShape.new()
	var shape=CapsuleShape.new()
	shape.radius=height*0.13
	shape.height=height*0.74
	cs.shape=shape
	cs.translation.y=height*0.5
	add_child(cs)
	collision_layer=2
	collision_mask=2
	add_to_group("monsters")

func _physics_process(delta):
	if game.state!="play":return
	if dead:
		age+=delta
		model.rotation.z=lerp(0,1.50,smoothstep(0,2.6,age))
		if age>24:queue_free()
		return
	stunned=max(0,stunned-delta)
	if stunned>0:return
	cooldown=max(0,cooldown-delta)
	var at=global_transform.origin
	var player_at=game.player.global_transform.origin
	var target=player_at if at.distance_to(player_at)<max(55,height*1.2) else game.base_position
	var distance=at.distance_to(target)
	if windup>0:
		windup-=delta
		model.rotation.x=sin((1.5-windup)*PI/1.5)*-0.13
		if windup<=0:
			game.explosion(at-global_transform.basis.z*height*0.18,0.9)
			game.shake=0.75
			if attack_target=="player" and at.distance_to(player_at)<height*0.23+7:game.player.take_damage(damage,1)
			elif attack_target=="base" and at.distance_to(game.base_position)<height*0.23+7:game.base_hp-=damage
			cooldown=4.2
			model.rotation.x=0
		return
	if distance<height*0.23+4:
		if cooldown<=0:
			windup=1.5
			attack_target="player" if target==player_at else "base"
			game.notice="巨怪重击蓄力！立即驶离脚下"
	else:
		var direction=(target-at).normalized()
		rotation.y=lerp_angle(rotation.y,atan2(-direction.x,-direction.z),min(delta,1))
		move_and_slide(Vector3(direction.x,0,direction.z)*speed,Vector3.UP)

func take_damage(amount,attacker):
	if dead:return
	hp-=amount
	if hp<=0:
		hp=0
		dead=true
		collision_layer=0
		if animator!=null:animator.stop()
		game.credits+=reward
		game.kills+=1
		game.radio("target_destroyed")
		game.explosion(global_transform.origin+Vector3.UP*height*0.25,1.5)
