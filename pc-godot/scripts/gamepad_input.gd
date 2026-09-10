extends Node
## Device selection is driven by actual input, so reconnecting on a new SDL slot
## works without restarting. All InputMap bindings use device -1 (any controller).

var game: Node
var active_device := -1
var using_controller := false
var _known_devices: Array[int] = []
var _last_mode := ""


func _ready() -> void:
	name = "GamepadInput"
	for device: int in Input.get_connected_joypads():
		_known_devices.append(device)
	if not _known_devices.is_empty():
		active_device = _known_devices[0]
		using_controller = true


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_select_device(event.device)
	elif event is InputEventJoypadMotion:
		var trigger: bool = event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
		var strength: float = event.axis_value if trigger else absf(event.axis_value)
		if strength > 0.24:
			_select_device(event.device)
	elif event is InputEventKey and event.pressed and not event.echo:
		using_controller = false
	elif event is InputEventMouseButton and event.pressed:
		using_controller = false
	elif event is InputEventMouseMotion and event.relative.length_squared() > 9.0:
		using_controller = false


func _process(_delta: float) -> void:
	if not is_instance_valid(game):
		return
	var mode := str(game.get("mode"))
	if mode != _last_mode:
		_last_mode = mode
		if mode != "playing":
			stop_rumble()


func _select_device(device: int) -> void:
	if device != active_device:
		stop_rumble()
	active_device = device
	using_controller = true


func connection_changed(device: int, connected: bool) -> bool:
	if connected:
		if not device in _known_devices:
			_known_devices.append(device)
		if active_device < 0:
			active_device = device
		if is_instance_valid(game):
			game.notify("手柄已连接 · A 确认 / START 暂停 · 暂停菜单查看操作", 3.0)
		return false
	_known_devices.erase(device)
	if device != active_device:
		return false
	var was_in_use := using_controller
	stop_rumble()
	_release_device(device)
	active_device = -1
	using_controller = false
	return was_in_use


func _release_device(device: int) -> void:
	# A device pulled out with its trigger/stick held must never leave a phantom
	# fire or movement action latched when the player resumes on keyboard.
	for axis in range(JOY_AXIS_MAX):
		var motion := InputEventJoypadMotion.new()
		motion.device = device
		motion.axis = axis
		motion.axis_value = 0.0
		Input.parse_input_event(motion)
	for index in range(JOY_BUTTON_MAX):
		var button := InputEventJoypadButton.new()
		button.device = device
		button.button_index = index
		button.pressed = false
		Input.parse_input_event(button)


func get_snapshot() -> Dictionary:
	var connected := active_device in Input.get_connected_joypads()
	var label := Input.get_joy_name(active_device) if connected else "手柄"
	return {
		"input_device": "controller" if using_controller else "keyboard",
		"controller_connected": connected,
		"controller_name": label,
	}


func rumble(weak: float, strong: float, seconds: float) -> bool:
	if not using_controller or active_device not in Input.get_connected_joypads():
		return false
	if not is_instance_valid(game) or not game.is_combat_running():
		return false
	Input.start_joy_vibration(active_device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), clampf(seconds, 0.01, 0.5))
	return true


func stop_rumble() -> void:
	for device: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)


func _exit_tree() -> void:
	stop_rumble()
