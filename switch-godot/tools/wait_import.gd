tool
extends SceneTree
var elapsed = 0.0
var stable = 0.0
var plugin
func _idle(delta):
	elapsed += delta
	if elapsed > 240:
		printerr("IMPORT_TIMEOUT")
		quit(2)
		return false
	if plugin == null:
		plugin = EditorPlugin.new()
		return false
	var fs = plugin.get_editor_interface().get_resource_filesystem()
	if fs.is_scanning():
		stable = 0.0
	else:
		stable += delta
	if elapsed > 3 and stable > 2:
		print("IRON_SWITCH_IMPORT_FINISHED")
		plugin.free()
		quit()
	return false
