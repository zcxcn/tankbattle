extends SceneTree
func _init():
	var texture=load("res://assets/icon.svg")
	var image=texture.get_data()
	image.resize(256,256,Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	var result=image.save_png("res://assets/icon-export.png")
	if result!=OK:
		printerr("ICON_FAILED")
		quit(2)
	else:
		print("IRON_SWITCH_ICON_READY")
		quit()
