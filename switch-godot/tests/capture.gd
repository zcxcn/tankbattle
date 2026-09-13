extends SceneTree
var game
var elapsed=0.0
var phase=0

func _init():call_deferred("start")

func start():
	game=load("res://scenes/main.tscn").instance()
	get_root().add_child(game)
	game.test_mode=true
	game.selected_weather=1
	game.state="menu"
	game.ui.update()

func _idle(delta):
	if game==null:return false
	elapsed+=delta
	if elapsed<2.0:return false
	elapsed=0
	var image=get_root().get_texture().get_data()
	image.flip_y()
	image.save_png("user://switch-capture-%d.png"%phase)
	print("CAPTURE ",phase," ",OS.get_user_data_dir())
	if phase==0:
		game.state="play"
		game.third_person=true
		game.update_camera(1)
	elif phase==1:
		game.create_battle(6,false)
		game.third_person=false
		game.update_camera(1)
	elif phase==2:
		game.create_battle(0,true)
		game.spawn_monster()
		var monsters=get_nodes_in_group("monsters")
		monsters[0].translation=Vector3(0,0,70)
		game.third_person=true
		game.camera_yaw=0
		game.camera_pitch=-0.1
		game.update_camera(1)
	elif phase==3:
		print("IRON_SWITCH_CAPTURE_FINISHED")
		quit()
	phase+=1
	game.ui.update()
	return false
