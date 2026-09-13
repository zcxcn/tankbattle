extends SceneTree
var game
var enemy
var phase=0
var clock=0.0
var damage_done=false
var player_hp=0.0
var checks=0

func check(value,message):
	if not value:
		printerr("SMOKE_FAILED: "+message)
		quit(2)
		return false
	checks+=1
	return true

func _init():call_deferred("start")

func button(index,pressed):
	var event=InputEventJoypadButton.new()
	event.device=0
	event.button_index=index
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func start():
	game=load("res://scenes/main.tscn").instance()
	get_root().add_child(game)
	game.test_mode=true
	game.selected_weather=1
	game.state="play"
	for actor in game.targets():
		if actor.team!=0:
			if enemy==null:enemy=actor
			else:actor.queue_free()
	game.player.translation=Vector3(0,0.08,174)
	game.player.cooldown=0
	enemy.translation=Vector3(0,0.08,98)
	enemy.rotation.y=PI
	enemy.hp=1000
	enemy.max_hp=1000
	player_hp=game.player.hp
	game.aim_position=enemy.translation+Vector3.UP*1.6
	button(7,true)

func _idle(delta):
	if game==null:return false
	clock+=min(delta,0.05)
	if phase==0:
		game.aim_position=enemy.translation+Vector3.UP*1.6
		if enemy.hp<1000:damage_done=true
		if clock>=10:
			button(7,false)
			if not check(damage_done,"player real muzzle -> fast shell -> enemy collision damage"):return false
			if not check(game.player.hp<player_hp,"enemy sees player and fires at long range"):return false
			if not check(enemy.translation.z>98,"enemy pursues after contact"):return false
			if not check(game.shots_fired>=4,"weapons fire through gameplay input"):return false
			game.state="pause"
			enemy.queue_free()
			game.create_battle(0,true)
			game.player.translation=Vector3(0,0.08,110)
			game.player.hp=1000
			var monster=game.Monster.new()
			game.battle.add_child(monster)
			monster.setup(game,0,1)
			monster.translation=Vector3(0,0,125)
			enemy=monster
			phase=1
			clock=0
	elif phase==1 and clock>=10:
		if not check(game.player.hp<1000,"giant moves into range, telegraphs and hits player"):return false
		if not check(enemy.translation.z<125,"monster closes distance"):return false
		game.state="pause"
		print("IRON_SWITCH_SMOKE_FINISHED: ",checks," checks; shots=",game.shots_fired)
		game.queue_free()
		quit()
	return false
