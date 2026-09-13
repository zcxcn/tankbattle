extends SceneTree
func _init():call_deferred("run")
func run():
	var game=load("res://scenes/main.tscn").instance()
	get_root().add_child(game)
	game.test_mode=false
	game.state="menu"
	game.save_sequence=0
	game.unlocked=2
	game.best_wave=5
	game.save_progress()
	assert(game.save_sequence==1,"first successful write updates memory sequence")
	game.unlocked=3
	game.best_wave=6
	game.save_progress()
	assert(game.save_sequence==2,"second successful write alternates slot")
	var file=File.new()
	assert(file.file_exists("user://progress0.json") and file.file_exists("user://progress1.json"),"both slots exist")
	game.save_sequence=0
	game.load_progress()
	assert(game.unlocked==3 and game.best_wave==6,"newest valid slot loaded")
	assert(file.open("user://progress0.json",File.WRITE)==OK)
	file.store_string('{"payload":"{}","checksum":"damaged"}')
	file.close()
	game.save_sequence=0
	game.load_progress()
	assert(game.unlocked==2 and game.best_wave==5,"damaged newest slot falls back")
	print("IRON_SWITCH_SAVE_PASSED: 5")
	game.queue_free()
	quit()
