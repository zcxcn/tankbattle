extends SceneTree
var checks=0
var game
func check(value,message):
	if not value:
		printerr("CHECK_FAILED: "+message)
		quit(2)
		assert(value,message)
	checks+=1

func _init():
	call_deferred("run")

func run():
	game=load("res://scenes/main.tscn").instance()
	get_root().add_child(game)
	game.test_mode=true
	game.selected_weather=1
	check(game.player.turret!=null and game.player.muzzle!=null,"real articulated tank model")
	check(game.Missions.count()==7,"seven mission definitions")
	for i in range(7):
		var data=game.Missions.get_mission(i)
		check(data.enemy_layout.size()==data.enemy_count,"chapter patrol count %d"%i)
	check(game.sound_cache["cannon-01"].get_length()>0.5,"recorded cannon stream")
	check(game.radio_cache["enemy_spotted"].get_length()>0.1,"actor radio recording")
	check(not game.world.allowed(Vector3(42,0,36)),"water blocks hull")
	check(game.world.allowed(Vector3(0,0,36)),"bridge corridor accessible")
	check(game.world.route(Vector3(40,0,80),Vector3(40,0,-80)).z>50,"crossing aligns before river")
	game.state="play"
	check(game.place_mine(),"player deploys mine")
	check(not game.place_mine(),"mine cooldown")
	game.pulse()
	check(game.mines.empty(),"pulse removes nearby mines")
	var enemies=game.get_tree().get_nodes_in_group("tanks")
	for tank in enemies:
		if tank.team==1:tank.take_damage(100000,0)
	game.tick_progress(0.2)
	check(game.boss_spawned and game.enemy_count()==1,"boss appears after patrol deaths")
	for tank in game.targets():
		if tank.team==1 and not tank.dead:tank.take_damage(100000,0)
	game.tick_progress(0.2)
	check(game.state=="victory","boss death completes mission")
	game.create_battle(0,true)
	for wave_index in range(1,4):
		var guard=0
		while game.state=="play" and guard<120:
			game.tick_progress(1.0)
			for enemy in game.targets():
				if enemy.team==1 and not enemy.dead:enemy.take_damage(100000,0)
			guard+=1
		check(game.state=="shop","natural wave completion reaches shop %d"%wave_index)
		check(game.pending==0 and game.enemy_count()==0,"no queued or live enemies after wave")
		check(game.wave==wave_index,"wave index retained through settlement")
		var cash=game.credits
		game.tick_progress(50)
		check(game.credits==cash,"settlement cannot be paid twice")
		check(game.buy_upgrade(0),"earned reward buys real upgrade")
		game.menu_index=3
		var event=InputEventJoypadButton.new()
		event.device=0
		event.button_index=1
		event.pressed=true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		game.last_buttons.clear()
		game.menu_input()
		check(game.state=="play" and game.wave==wave_index+1,"Switch A starts next wave through menu")
		event.pressed=false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	check(game.wave_history==[1,2,3,4],"continuous waves 1 to 4")
	game.create_battle(6,false)
	check(game.player.translation.y>0.1,"woodland spawn uses heightfield")
	check(game.world.height_at(68,-64)>18,"authored hills preserved")
	check(game.enemy_count()==24,"woodland 24 patrols")
	game.state="play"
	game._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
	check(game.state=="pause","focus notification pauses game")
	game.state="play"
	game.joy_connection(0,false)
	check(game.state=="pause","disconnect event pauses game")
	print("IRON_SWITCH_CHECKS_PASSED: ",checks)
	game.queue_free()
	yield(self,"idle_frame")
	quit(0)
