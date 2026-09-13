extends KinematicBody
const Vehicles=preload("res://data/vehicle_catalog.gd")
const MODELS={"challenger2":"challenger2/challenger2.glb","kf51":"kf51/kf51_panther.glb","kv2":"kv2/kv2_boss.glb"}
var game
var team=1
var boss=false
var role="line"
var hp=200.0
var max_hp=200.0
var armor=0.08
var speed=6.0
var acceleration=7.0
var turn_rate=1.05
var turret_rate=1.35
var damage=24.0
var interval=4.8
var weapon=0
var cooldown=2.0
var vision=85.0
var engage=150.0
var ideal=34.0
var fov=105.0
var lock_time=1.2
var memory=0.0
var last_seen=Vector3.ZERO
var reaction=0.0
var sense_clock=0.0
var sees=false
var route=[]
var route_index=0
var drive=0.0
var turret
var gun
var muzzle
var model
var gun_rest=Vector3.ZERO
var recoil=0.0
var dead=false
var dead_age=0.0
var cookoff=false
var cookoff_done=false
var stunned=0.0
var last_track=Vector3.ZERO

func setup(owner_game, kind, is_player=false, is_boss=false):
	game=owner_game
	role=kind
	team=0 if is_player else 1
	boss=is_boss
	var data=Vehicles.player_vehicle(kind) if is_player else Vehicles.enemy_role(kind)
	max_hp=data.hp*(1.0 if is_player else game.mission.health_multiplier)
	armor=data.armor
	speed=data.speed
	damage=data.damage*(1.0 if is_player else game.mission.damage_multiplier)
	interval=data.interval
	if is_player:
		acceleration=data.acceleration
		turn_rate=data.turn_speed
		turret_rate=data.turret_speed
	else:
		vision=data.vision
		engage=data.engage
		ideal=data.ideal
		fov=data.fov
		lock_time=data.acquire
		weapon={"cannon":0,"machine_gun":1,"he":2,"rocket":3}[data.weapon]
	var key=data.model
	if boss:
		key="kv2"
		max_hp=580+game.chapter*100
		damage=44+game.chapter*3
		interval=4.5
		vision=115
		engage=210
		speed=3.8
		ideal=45
	hp=max_hp
	cooldown=game.rng.randf_range(1.8,3.5)
	model=load("res://assets/models/realistic/"+MODELS[key]).instance()
	model.scale=Vector3.ONE*{"challenger2":0.68,"kf51":0.70,"kv2":0.90}[key]
	add_child(model)
	var root=model.find_node("TankRoot",true,false)
	if model.name=="TankRoot":root=model
	assert(root!=null)
	turret=root.get_node("Turret")
	gun=turret.get_node("Gun")
	muzzle=gun.get_node("Muzzle")
	gun_rest=gun.translation
	var cs=CollisionShape.new()
	var shape=BoxShape.new()
	shape.extents=Vector3(1.38,1.2,2.85)
	cs.shape=shape
	cs.translation.y=1.2
	add_child(cs)
	collision_layer=2
	collision_mask=3
	add_to_group("tanks")
	var marker=MeshInstance.new()
	var ring=CylinderMesh.new()
	ring.top_radius=0.23
	ring.bottom_radius=0.23
	ring.height=0.13
	marker.mesh=ring
	var mat=SpatialMaterial.new()
	mat.albedo_color=Color("74e0d9") if is_player else Color("ff6b41")
	mat.emission_enabled=true
	mat.emission=mat.albedo_color
	marker.material_override=mat
	marker.translation=Vector3(0,2.75,0)
	add_child(marker)

func _physics_process(delta):
	if game.state!="play":return
	if dead:
		dead_age+=delta
		if cookoff and not cookoff_done and dead_age>1.1:
			cookoff_done=true
			game.explosion(global_transform.origin+Vector3.UP*2,2.1,true)
			game.radial_damage(global_transform.origin,9,45,team,self)
			game.play_sound("explosion-heavy-02",global_transform.origin)
			game.shake=1.2
		if dead_age>30 and team!=0:queue_free()
		return
	cooldown=max(0,cooldown-delta)
	stunned=max(0,stunned-delta)
	recoil=move_toward(recoil,0,delta*2.2)
	gun.translation=gun_rest+Vector3(0,0,recoil)
	model.rotation.x=sin(recoil*3)*0.018
	if stunned>0:return
	if team==0:
		player_tick(delta)
	else:
		ai_tick(delta)
	if global_transform.origin.distance_squared_to(last_track)>3.6 and abs(drive)>0.8:
		last_track=global_transform.origin
		game.track_mark(self)

func player_tick(delta):
	var move=game.move_input()
	rotation.y-=move.x*turn_rate*delta
	drive=move_toward(drive,-move.y*speed,acceleration*delta)
	move_tank(-global_transform.basis.z*drive,delta)
	aim_at(game.aim_position,delta)
	if game.fire_held():fire()

func move_tank(velocity,delta):
	var at=global_transform.origin
	var target=at+velocity*delta
	if not game.world.allowed(target):
		drive=move_toward(drive,0,delta*20)
		return
	velocity.y=-9
	move_and_slide(velocity,Vector3.UP,true,4,deg2rad(40))
	# Exact authored terrain height keeps both tracks grounded after river portals.
	translation.y=game.world.height_at(translation.x,translation.z)+0.08
	var forward=-global_transform.basis.z
	var ahead=game.world.height_at(at.x+forward.x*2.5,at.z+forward.z*2.5)
	var behind=game.world.height_at(at.x-forward.x*2.5,at.z-forward.z*2.5)
	model.rotation.x=lerp(model.rotation.x,atan2(ahead-behind,5),min(delta*5,1))

func ai_tick(delta):
	if not is_instance_valid(game.player) or game.player.dead:return
	var at=global_transform.origin
	var target=game.player.global_transform.origin
	var offset=target-at
	var distance=offset.length()
	sense_clock-=delta
	memory=max(0,memory-delta)
	if sense_clock<=0:
		sense_clock=0.20+game.rng.randf()*0.12
		var forward=-global_transform.basis.z
		var facing=forward.dot(offset.normalized())>cos(deg2rad(fov*0.5))
		var within=(distance<engage if memory>0 else (distance<vision and (facing or distance<22)))
		sees=within and game.visible_between(at+Vector3.UP*2,target+Vector3.UP*1.5,self,game.player)
		if sees:
			if memory<=0:game.radio("enemy_spotted")
			memory=16.0
			last_seen=target
	if sees:
		reaction+=delta
		aim_at(target+Vector3.UP*1.5,delta)
		if reaction>lock_time and distance<engage:fire()
	else:reaction=0
	var destination=last_seen
	var should_move=memory>0 and (not sees or distance>ideal)
	if memory<=0:
		if route.empty():return
		destination=route[route_index]
		if at.distance_to(destination)<5:
			route_index=(route_index+1)%route.size()
			destination=route[route_index]
		should_move=true
	if should_move:
		destination=game.world.route(at,destination)
		var direction=destination-at
		direction.y=0
		var desired=atan2(-direction.x,-direction.z)
		rotation.y=lerp_angle(rotation.y,desired,min(delta*1.1,1))
		var alignment=max(0,-global_transform.basis.z.dot(direction.normalized()))
		drive=move_toward(drive,speed*alignment,delta*4)
		var advance=-global_transform.basis.z*drive
		if not game.world.allowed(at+advance*0.8):
			rotation.y+=delta*1.6
			drive=1.0
		move_tank(-global_transform.basis.z*drive,delta)
	else:drive=move_toward(drive,0,delta*5)

func aim_at(target,delta):
	var direction=target-turret.global_transform.origin
	var yaw=atan2(-direction.x,-direction.z)-rotation.y
	turret.rotation.y=lerp_angle(turret.rotation.y,yaw,min(delta*turret_rate*2,1))
	var pitch=clamp(atan2(direction.y,Vector2(direction.x,direction.z).length()),-0.17,0.42)
	gun.rotation.x=lerp(gun.rotation.x,pitch,min(delta*3,1))

func fire():
	if cooldown>0 or dead or stunned>0:return false
	var aim=game.aim_position if team==0 else game.player.global_transform.origin+Vector3.UP*1.5
	var at=muzzle.global_transform.origin
	var barrel=-muzzle.global_transform.basis.z.normalized()
	var towards=(aim-at).normalized()
	if team!=0 and barrel.dot(towards)<0.985:return false
	var kind=game.weapon if team==0 else weapon
	var power=damage
	var reload_time=interval
	if kind==1:
		power=7.5 if team==0 else min(damage,5)
		reload_time=0.15 if team==0 else 0.32
	elif kind==2:
		power*=1.10
		reload_time*=1.15
	elif kind==3:
		power*=1.65
		reload_time=5.2
	if team==0:
		power*=1.0+game.upgrades[0]*0.15
		reload_time*=pow(0.9,game.upgrades[1])
	cooldown=reload_time
	recoil=0.10 if kind==1 else 0.65
	game.launch(self,at,barrel,kind,power)
	return true

func take_damage(amount, attacker):
	if dead:return
	hp-=amount*(1-armor)
	if team==0:
		game.shake=max(game.shake,0.55)
		game.play_sound("impact-armor-01",global_transform.origin)
		if hp<max_hp*0.3:game.radio("armor_critical")
	else:
		memory=16
		last_seen=game.player.global_transform.origin
	if hp<=0:
		hp=0
		dead=true
		collision_layer=1
		cookoff=game.rng.randf()<0.28
		var burnt=SpatialMaterial.new()
		burnt.albedo_color=Color("272924")
		burnt.roughness=1
		for mesh in game.world.descendants(model,"MeshInstance"):mesh.material_overlay=burnt
		game.explosion(global_transform.origin+Vector3.UP,1.4)
		game.play_sound("explosion-heavy-01",global_transform.origin)
		game.tank_destroyed(self,attacker)
