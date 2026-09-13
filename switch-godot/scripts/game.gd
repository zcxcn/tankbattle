extends Spatial
const Tank=preload("res://scripts/tank.gd")
const Monster=preload("res://scripts/monster.gd")
const World=preload("res://scripts/world.gd")
const Shot=preload("res://scripts/shot.gd")
const Effect=preload("res://scripts/fx.gd")
const Hud=preload("res://scripts/hud.gd")
const Missions=preload("res://data/mission_catalog.gd")
const Vehicles=preload("res://data/vehicle_catalog.gd")
var state="menu"
var chapter=0
var selected_chapter=0
var selected_vehicle=1
var selected_weather=0
var menu_index=0
var mode="campaign"
var mission={}
var world
var battle
var player
var camera
var ui
var env
var weather
var rng=RandomNumberGenerator.new()
var weapon=0
var aim_position=Vector3.ZERO
var camera_yaw=0.0
var camera_pitch=0.17
var third_person=true
var shake=0.0
var notice=""
var kills=0
var credits=0
var upgrades=[0,0,0]
var wave=0
var pending=0
var spawn_clock=0.0
var wave_wait=-1.0
var base_hp=1000.0
var base_position=Vector3(0,0,-130)
var objective_hp=220.0
var objective_time=0.0
var objective_done=false
var objective_marker
var boss_spawned=false
var mine_cooldown=0.0
var pulse_cooldown=0.0
var mines=[]
var track_nodes=[]
var elapsed=0.0
var radio_clock=0.0
var music_index=0
var music
var engine_sound
var radio_player
var voices=[]
var music_streams=[]
var sound_cache={}
var radio_cache={}
var last_buttons={}
var event_buttons={}
var pad=0
var save_sequence=0
var unlocked=0
var best_wave=0
var test_mode=false
var shots_fired=0
var wave_history=[]

func _ready():
	rng.randomize()
	OS.set_window_title("钢铁余烬 · Switch 1")
	Engine.target_fps=30
	test_mode="--self-test" in OS.get_cmdline_args()
	var save_dir=Directory.new()
	save_dir.make_dir_recursive(OS.get_user_data_dir())
	load_progress()
	camera=Camera.new()
	camera.far=520
	camera.near=0.2
	camera.fov=67
	add_child(camera)
	var environment=WorldEnvironment.new()
	env=Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky=ProceduralSky.new()
	sky.sky_top_color=Color("3c657c")
	sky.sky_horizon_color=Color("c6cdbf")
	sky.ground_horizon_color=Color("8b9686")
	sky.ground_bottom_color=Color("313f3a")
	env.background_sky=sky
	env.ambient_light_color=Color("a9c5d2")
	env.ambient_light_energy=0.55
	env.fog_enabled=true
	env.fog_color=Color("9eb1b0")
	env.fog_depth_begin=110
	env.fog_depth_end=440
	environment.environment=env
	add_child(environment)
	var sun=DirectionalLight.new()
	sun.rotation_degrees=Vector3(-43,-28,0)
	sun.light_color=Color("fff1d6")
	sun.light_energy=1.35
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=100
	add_child(sun)
	setup_audio()
	var layer=CanvasLayer.new()
	ui=Hud.new()
	ui.game=self
	layer.add_child(ui)
	add_child(layer)
	Input.connect("joy_connection_changed",self,"joy_connection")
	create_battle(0,false)
	state="menu"
	menu_index=0
	notice=""
	print("IRON_SWITCH_READY 0.1.0")

func setup_audio():
	for name in ["cannon-01","cannon-02","explosion-heavy-01","explosion-heavy-02","impact-armor-01","mg-fire","rocket-launch"]:
		sound_cache[name]=load("res://assets/audio/combat/"+name+".wav")
	for name in ["enemy_spotted","target_destroyed","armor_critical","boss_detected","mission_complete","mission_failed"]:
		radio_cache[name]=load("res://assets/audio/battlefield/radio/"+name+".wav")
	for name in ["industrial-war","electronic-pursuit","epic-siege"]:
		var stream=load("res://assets/audio/battlefield/music/"+name+".wav")
		stream.loop_mode=AudioStreamSample.LOOP_FORWARD
		music_streams.append(stream)
	music=AudioStreamPlayer.new()
	music.volume_db=-22
	music.stream=music_streams[0]
	add_child(music)
	music.play()
	radio_player=AudioStreamPlayer.new()
	radio_player.volume_db=-5
	add_child(radio_player)
	engine_sound=AudioStreamPlayer.new()
	engine_sound.stream=load("res://assets/audio/battlefield/vehicle/track-engine.wav")
	engine_sound.stream.loop_mode=AudioStreamSample.LOOP_FORWARD
	engine_sound.volume_db=-32
	add_child(engine_sound)
	engine_sound.play()

func play_sound(name,at):
	if not sound_cache.has(name):return
	for i in range(voices.size()-1,-1,-1):
		if not is_instance_valid(voices[i]):voices.remove(i)
	if voices.size()>=16:return
	var sound=AudioStreamPlayer.new()
	sound.stream=sound_cache[name]
	var distance=player.global_transform.origin.distance_to(at) if is_instance_valid(player) else 0
	sound.volume_db=-1-clamp(distance*0.09,0,23)
	sound.pitch_scale=rng.randf_range(0.95,1.04)
	add_child(sound)
	sound.connect("finished",sound,"queue_free")
	sound.play()
	voices.append(sound)

func radio(name):
	if radio_clock>0:return
	radio_clock=5
	radio_player.stream=radio_cache[name]
	radio_player.play()

func create_battle(index,endless):
	state="loading"
	if is_instance_valid(battle):
		remove_child(battle)
		battle.free()
	mines.clear()
	track_nodes.clear()
	chapter=index
	mode="endless" if endless else "campaign"
	mission=Missions.get_mission(index)
	battle=Spatial.new()
	add_child(battle)
	world=World.new()
	battle.add_child(world)
	world.build(index==6 and not endless,413+index)
	player=Tank.new()
	battle.add_child(player)
	player.setup(self,Vehicles.PLAYER_VEHICLES[selected_vehicle].id,true)
	player.translation=world.ground(Vector3(0,0,130) if endless else mission.player_start)
	weapon=0
	kills=0
	credits=0
	upgrades=[0,0,0]
	base_hp=1000
	objective_hp=220
	objective_time=0
	objective_done=mission.objective_type=="clear" or endless
	boss_spawned=false
	wave=0
	pending=0
	wave_wait=-1
	wave_history.clear()
	pulse_cooldown=0
	mine_cooldown=0
	camera_yaw=0
	camera_pitch=0.18
	aim_position=player.translation+Vector3(0,2,-80)
	if endless:
		base_position=world.ground(Vector3(0,0,-130))
		add_objective(base_position,Color("4ecbc0"))
		begin_wave()
	else:
		for item in mission.enemy_layout:
			var enemy=Tank.new()
			battle.add_child(enemy)
			enemy.setup(self,item.kind)
			enemy.translation=world.ground(item.position)
			enemy.rotation.y=rng.randf_range(-PI,PI)
			enemy.route=item.patrol.duplicate()
		if not objective_done:add_objective(world.ground(mission.objective_position),Color("efb760"))
	setup_weather()
	state="play"
	notice=mission.briefing if not endless else "守住北侧中继站。击败巨怪获得资金，波次间整备升级。"
	update_camera(1)

func add_objective(at,color):
	objective_marker=MeshInstance.new()
	var cylinder=CylinderMesh.new()
	cylinder.top_radius=4
	cylinder.bottom_radius=4
	cylinder.height=6
	objective_marker.mesh=cylinder
	objective_marker.translation=at+Vector3.UP*3
	var mat=SpatialMaterial.new()
	mat.albedo_color=color
	mat.metallic=0.4
	objective_marker.material_override=mat
	battle.add_child(objective_marker)
	var body=StaticBody.new()
	body.translation=at+Vector3.UP*3
	var shape=CollisionShape.new()
	var cylinder_shape=CylinderShape.new()
	cylinder_shape.radius=4
	cylinder_shape.height=6
	shape.shape=cylinder_shape
	body.add_child(shape)
	battle.add_child(body)

func setup_weather():
	var kind=selected_weather
	if kind==0:kind=rng.randi_range(1,3)
	weather=CPUParticles.new()
	weather.amount=450 if kind==2 else 250
	weather.lifetime=2.5
	weather.emission_shape=CPUParticles.EMISSION_SHAPE_BOX
	weather.emission_box_extents=Vector3(25,2,25)
	weather.direction=Vector3(0,-1,0)
	weather.spread=8
	weather.initial_velocity=24 if kind==2 else 3
	weather.gravity=Vector3(0,-5,0)
	var drop=CubeMesh.new()
	drop.size=Vector3(0.025,0.8,0.025) if kind==2 else Vector3.ONE*0.09
	weather.mesh=drop
	var mat=SpatialMaterial.new()
	mat.albedo_color=Color(0.7,0.84,0.9,0.65) if kind==2 else Color.white
	mat.flags_unshaded=true
	mat.flags_transparent=kind==2
	weather.mesh.material=mat
	weather.emitting=kind>1
	battle.add_child(weather)
	env.fog_depth_end=260 if kind>1 else 440

func axis(index):
	var value=Input.get_joy_axis(pad,index)
	return sign(value)*max(0,(abs(value)-0.18)/0.82)

func move_input():
	return Vector2(clamp(axis(0)+int(Input.is_key_pressed(KEY_D))-int(Input.is_key_pressed(KEY_A)),-1,1),clamp(axis(1)+int(Input.is_key_pressed(KEY_S))-int(Input.is_key_pressed(KEY_W)),-1,1))

func held(name):
	# The pinned Switch runtime maps B,A,Y,X to Godot 0,1,2,3 and ZR to button 7.
	var buttons={"accept":1,"back":0,"mine":2,"camera":3,"prev":4,"next":5,"pulse":6,"fire":7,"music":10,"pause":11,"up":12,"down":13,"left":14,"right":15}
	var keys={"accept":KEY_ENTER,"back":KEY_ESCAPE,"mine":KEY_Q,"camera":KEY_C,"prev":KEY_1,"next":KEY_2,"pulse":KEY_E,"fire":KEY_SPACE,"music":KEY_M,"pause":KEY_ESCAPE,"up":KEY_UP,"down":KEY_DOWN,"left":KEY_LEFT,"right":KEY_RIGHT}
	return event_buttons.get(buttons[name],Input.is_joy_button_pressed(pad,buttons[name])) or Input.is_key_pressed(keys[name])

func fire_held():
	return held("fire") or Input.is_mouse_button_pressed(BUTTON_LEFT)

func just(name):
	return held(name) and not last_buttons.get(name,false)

func joy_connection(device,connected):
	if connected:pad=device
	elif device==pad and state=="play":
		event_buttons.clear()
		state="pause"
		menu_index=0
		notice="手柄断开。重新连接后按 A 继续。"

func _notification(what):
	if what==MainLoop.NOTIFICATION_WM_FOCUS_OUT and state=="play":
		state="pause"
		menu_index=0
		last_buttons.clear()
		event_buttons.clear()

func _input(event):
	if event is InputEventJoypadButton:
		pad=event.device
		event_buttons[event.button_index]=event.pressed
	if event is InputEventMouseMotion and state=="play" and not OS.get_name()=="Switch":
		# Absolute cursor mapping works through Remote Desktop without mouse capture.
		var screen=get_viewport().size
		var cursor=event.position
		if third_person:
			camera_yaw=lerp(-PI,PI,clamp(cursor.x/screen.x,0,1))
			camera_pitch=lerp(-0.10,0.55,clamp(cursor.y/screen.y,0,1))
		else:
			var origin=camera.project_ray_origin(cursor)
			var direction=camera.project_ray_normal(cursor)
			if direction.y< -0.01:aim_position=origin+direction*((player.translation.y+1.5-origin.y)/direction.y)

func _process(delta):
	if test_mode:return
	delta=min(delta,0.05)
	elapsed+=delta
	radio_clock=max(0,radio_clock-delta)
	if state=="play":
		if just("pause"):
			state="pause"
			menu_index=0
		else:
			if just("camera"):third_person=not third_person
			if just("next"):weapon=(weapon+1)%4
			if just("prev"):weapon=(weapon+3)%4
			if just("mine"):place_mine()
			if just("pulse"):pulse()
			if just("music"):
				music_index=(music_index+1)%3
				music.stream=music_streams[music_index]
				music.play()
			camera_yaw-=axis(2)*delta*1.6
			camera_pitch=clamp(camera_pitch+axis(3)*delta*0.75,-0.1,0.6)
			update_camera(delta)
			tick_progress(delta)
			mine_cooldown=max(0,mine_cooldown-delta)
			pulse_cooldown=max(0,pulse_cooldown-delta)
			tick_mines(delta)
			engine_sound.volume_db=-25+min(abs(player.drive),9)*1.5
	else:
		menu_input()
		engine_sound.volume_db=-60
	if is_instance_valid(weather):
		weather.translation=player.translation+Vector3.UP*25
		weather.speed_scale=1 if state=="play" else 0
	engine_sound.stream_paused=state!="play"
	music.volume_db=-22 if state=="play" else -29
	for name in ["accept","back","mine","camera","prev","next","pulse","fire","music","pause","up","down","left","right"]:last_buttons[name]=held(name)
	ui.update()

func menu_input():
	var count=7 if state=="menu" else (4 if state=="shop" else (3 if state=="pause" else 2))
	if just("up"):menu_index=posmod(menu_index-1,count)
	if just("down"):menu_index=(menu_index+1)%count
	var shift=int(just("right"))-int(just("left"))
	if state=="menu":
		if menu_index==3:selected_chapter=posmod(selected_chapter+shift,7)
		if menu_index==4:selected_vehicle=posmod(selected_vehicle+shift,3)
		if menu_index==5:selected_weather=posmod(selected_weather+shift,4)
	if not just("accept"):return
	match state:
		"menu":
			if menu_index<=2:
				create_battle(selected_chapter if menu_index==0 else (6 if menu_index==2 else 0),menu_index==1)
			elif menu_index==3:selected_chapter=(selected_chapter+1)%7
			elif menu_index==4:selected_vehicle=(selected_vehicle+1)%3
			elif menu_index==5:selected_weather=(selected_weather+1)%4
			else:get_tree().quit()
		"pause":
			if menu_index==0:state="play"
			elif menu_index==1:create_battle(chapter,mode=="endless")
			else:state="menu"
		"shop":
			if menu_index<3:buy_upgrade(menu_index)
			else:
				state="play"
				begin_wave()
		"victory":
			if menu_index==0:create_battle(min(chapter+1,6),false)
			else:state="menu"
		"defeat":
			if menu_index==0:create_battle(chapter,mode=="endless")
			else:state="menu"
	menu_index=0

func update_camera(delta):
	var at=player.global_transform.origin
	var forward=Vector3(-sin(camera_yaw),0,-cos(camera_yaw))
	var target
	if third_person:
		target=at-forward*12+Vector3.UP*(5+camera_pitch*8)
		var hit=get_world().direct_space_state.intersect_ray(at+Vector3.UP*2,target,[player],1)
		if not hit.empty():target=hit.position+(at+Vector3.UP*2-hit.position).normalized()*0.6
		camera.translation=camera.translation.linear_interpolate(target,min(delta*8,1))
		var look=at+forward*45+Vector3.UP*(2-camera_pitch*30)
		camera.look_at(look,Vector3.UP)
		var ray=-camera.global_transform.basis.z
		var aim_hit=get_world().direct_space_state.intersect_ray(camera.translation,camera.translation+ray*300,[player],3)
		aim_position=aim_hit.position if not aim_hit.empty() else camera.translation+ray*220
	else:
		target=at+Vector3(0,65,42)
		camera.translation=camera.translation.linear_interpolate(target,min(delta*6,1))
		camera.look_at(at,Vector3.UP)
		if abs(axis(2))+abs(axis(3))>0.05:aim_position=at+Vector3(axis(2)*85,1.5,axis(3)*85)
	shake=max(0,shake-delta*2)
	camera.translation+=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),0)*shake*0.22

func launch(source,at,direction,kind,power):
	shots_fired+=1
	# Segment from the gun breech to muzzle prevents shooting through adjacent walls.
	var blocked=get_world().direct_space_state.intersect_ray(source.global_transform.origin+Vector3.UP*2,at,[source],3)
	if not blocked.empty():
		impact(blocked.position,kind,source.team,power,blocked.collider)
	else:
		var shot=Shot.new()
		battle.add_child(shot)
		shot.setup(self,source,at,direction,kind,power)
	var fx=Effect.new()
	battle.add_child(fx)
	fx.setup(at,0.3 if kind==1 else 1,true)
	play_sound("mg-fire" if kind==1 else ("rocket-launch" if kind==3 else "cannon-01"),at)
	if source.team==0:shake=max(shake,0.10 if kind==1 else 0.50)

func impact(at,kind,team,power,direct):
	explosion(at,0.25 if kind==1 else (1.25 if kind==2 else 0.8))
	if kind!=1:
		play_sound("explosion-heavy-01",at)
		radial_damage(at,11 if kind==2 else (9 if kind==3 else 4.5),power*0.6,team,direct)
	if mode=="campaign" and mission.objective_type=="demolition" and not objective_done and at.distance_to(mission.objective_position+Vector3.UP*3)<12:
		objective_hp-=power
		if objective_hp<=0:
			objective_done=true
			if is_instance_valid(objective_marker):objective_marker.hide()
			explosion(mission.objective_position,2,true)

func explosion(at,strength=1.0,cookoff=false):
	var effects=get_tree().get_nodes_in_group("effects")
	if effects.size()>=32:effects[0].queue_free()
	var fx=Effect.new()
	fx.add_to_group("effects")
	battle.add_child(fx)
	fx.setup(at,strength,false,cookoff)

func radial_damage(at,radius,power,team,excluded):
	for actor in targets():
		if actor.dead or actor==excluded or actor.team==team:continue
		var distance=actor.global_transform.origin.distance_to(at)
		if distance<radius:actor.take_damage(power*(1-distance/radius),team)

func targets():
	return get_tree().get_nodes_in_group("tanks")+get_tree().get_nodes_in_group("monsters")

func visible_between(a,b,source,target):
	var hit=get_world().direct_space_state.intersect_ray(a,b,[source],3)
	return hit.empty() or hit.collider==target

func tank_destroyed(actor,attacker):
	if actor.team==0:
		state="defeat"
		menu_index=0
		radio("mission_failed")
	else:
		kills+=1
		radio("target_destroyed")

func enemy_count():
	var count=0
	for actor in targets():
		if actor.team==1 and not actor.dead:count+=1
	return count

func tick_progress(delta):
	if state!="play":return
	if mode=="endless":
		if base_hp<=0:
			state="defeat"
			menu_index=0
			return
		spawn_clock-=delta
		if pending>0 and spawn_clock<=0 and enemy_count()<7:
			spawn_monster()
			pending-=1
			spawn_clock=2.8
		if pending==0 and enemy_count()==0:
			if wave_wait<0:wave_wait=4.0
			wave_wait-=delta
			if wave_wait<=0:
				credits+=50+wave*10
				best_wave=max(best_wave,wave)
				save_progress()
				state="shop"
				menu_index=0
		return
	if mission.objective_type=="capture" and not objective_done:
		if player.translation.distance_to(world.ground(mission.objective_position))<mission.objective_radius:
			objective_time+=delta
			if objective_time>=mission.objective_seconds:objective_done=true
	if enemy_count()==0 and objective_done:
		if not boss_spawned:
			boss_spawned=true
			var boss=Tank.new()
			battle.add_child(boss)
			boss.setup(self,"heavy",false,true)
			boss.translation=world.ground(mission.boss_position)
			boss.route=[boss.translation,world.ground(mission.boss_position+Vector3(0,0,25))]
			notice=mission.boss_name+" 已进入战场"
			radio("boss_detected")
		else:
			state="victory"
			menu_index=0
			unlocked=max(unlocked,min(6,chapter+1))
			save_progress()
			radio("mission_complete")

func begin_wave():
	wave+=1
	pending=3+wave*2
	spawn_clock=0.5
	wave_wait=-1
	wave_history.append(wave)
	notice="第 %d 波：%d 只巨怪正在逼近" % [wave,pending]

func spawn_monster():
	var actor=Monster.new()
	battle.add_child(actor)
	var kind=(wave+pending)%min(5,wave+2)
	actor.setup(self,kind,wave)
	var x=rng.randf_range(-110,110)
	actor.translation=Vector3(x,0,175)

func upgrade_cost(index):return 70+upgrades[index]*50

func buy_upgrade(index):
	if index<0 or index>2 or state!="shop":return false
	var cost=upgrade_cost(index)
	if credits<cost or upgrades[index]>=6:return false
	credits-=cost
	upgrades[index]+=1
	if index==2:
		player.max_hp+=55
		player.hp=min(player.max_hp,player.hp+100)
		base_hp=min(1000,base_hp+120)
	return true

func place_mine():
	if mine_cooldown>0 or mines.size()>=8:return false
	var position=player.translation+player.global_transform.basis.z*4
	if not world.allowed(position,0.8):return false
	var mesh=MeshInstance.new()
	var shape=CylinderMesh.new()
	shape.top_radius=0.48
	shape.bottom_radius=0.65
	shape.height=0.22
	mesh.mesh=shape
	mesh.translation=world.ground(position)+Vector3.UP*0.15
	var mat=SpatialMaterial.new()
	mat.albedo_color=Color("c19952")
	mesh.material_override=mat
	battle.add_child(mesh)
	mines.append({"node":mesh,"age":0.0})
	mine_cooldown=4
	return true

func tick_mines(delta):
	for i in range(mines.size()-1,-1,-1):
		var mine=mines[i]
		mine.age+=delta
		if mine.age<1:continue
		for enemy in targets():
			if enemy.team!=1 or enemy.dead:continue
			if enemy.translation.distance_to(mine.node.translation)<4:
				radial_damage(mine.node.translation,12,200,0,null)
				explosion(mine.node.translation,1.6)
				play_sound("explosion-heavy-02",mine.node.translation)
				mine.node.queue_free()
				mines.remove(i)
				break

func pulse():
	if pulse_cooldown>0:return
	pulse_cooldown=18
	for i in range(mines.size()-1,-1,-1):
		if mines[i].node.translation.distance_to(player.translation)<28:
			mines[i].node.queue_free()
			mines.remove(i)
	for enemy in targets():
		if enemy.team==1 and enemy.translation.distance_to(player.translation)<28:enemy.stunned=4
	notice="脉冲释放：附近地雷已排除，敌人短暂瘫痪"

func track_mark(tank):
	if track_nodes.size()>=180:
		var old=track_nodes.pop_front()
		if is_instance_valid(old):old.queue_free()
	var mark=MeshInstance.new()
	var mesh=CubeMesh.new()
	mesh.size=Vector3(2.8,0.02,0.45)
	mark.mesh=mesh
	mark.material_override=world.material(Color(0.18,0.20,0.16))
	mark.translation=world.ground(tank.translation)+Vector3.UP*0.015
	mark.rotation.y=tank.rotation.y
	battle.add_child(mark)
	track_nodes.append(mark)

func load_progress():
	for slot in [0,1]:
		var file=File.new()
		if file.open("user://progress%d.json"%slot,File.READ)!=OK:continue
		var parsed=JSON.parse(file.get_as_text())
		file.close()
		if parsed.error!=OK or typeof(parsed.result)!=TYPE_DICTIONARY:continue
		var record=parsed.result
		if not record.has_all(["payload","checksum"]):continue
		if str(record.payload).sha256_text()!=record.checksum:continue
		var inner=JSON.parse(record.payload)
		if inner.error!=OK:continue
		var data=inner.result
		if typeof(data)!=TYPE_DICTIONARY:continue
		if not data.has_all(["magic","seq","chapter","best_wave"]):continue
		if typeof(data.seq)!=TYPE_REAL or typeof(data.chapter)!=TYPE_REAL or typeof(data.best_wave)!=TYPE_REAL:continue
		if data.magic!="IronEmbersSwitch/1" or data.chapter<0 or data.chapter>6 or data.best_wave<0:continue
		if data.seq>=save_sequence:
			save_sequence=int(data.seq)
			unlocked=int(data.chapter)
			best_wave=int(data.best_wave)
	selected_chapter=unlocked

func save_progress():
	if test_mode:return
	var data={"magic":"IronEmbersSwitch/1","seq":save_sequence+1,"chapter":unlocked,"best_wave":best_wave}
	var payload=JSON.print(data)
	var file=File.new()
	if file.open("user://progress%d.json"%int((save_sequence+1)%2),File.WRITE)!=OK:return
	file.store_string(JSON.print({"payload":payload,"checksum":payload.sha256_text()}))
	file.close()
	if file.get_error()==OK:save_sequence+=1
