extends Node
## PC display, graphics and audio preferences kept outside campaign progress.

signal settings_changed

const CONFIG_PATH := "user://settings.cfg"
var config_path := CONFIG_PATH

var display_mode := 0 # 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen.
var resolution := Vector2i(1600, 900)
var quality := 2 # low, medium, high, ultra.
var fps_cap := 60
var vsync := true
var screen_shake := true
var remote_mouse := false # Absolute cursor aiming for remote desktop sessions.
var weather_mode := 0 # Random, clear, light rain, heavy rain, snow, fog.
var master_volume := 80
var music_volume := 45
var effects_volume := 85
var radio_volume := 85
var music_track := 0


func _ready() -> void:
	# Automated runs get a private config and cannot alter the player's preferences.
	if "--test" in OS.get_cmdline_user_args():
		config_path = "user://tests/settings_%d.cfg" % OS.get_process_id()
		DirAccess.make_dir_recursive_absolute("user://tests")
	load_settings()
	call_deferred("apply")


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	display_mode = clampi(int(config.get_value("display", "mode", display_mode)), 0, 2)
	resolution.x = clampi(int(config.get_value("display", "width", resolution.x)), 1280, 7680)
	resolution.y = clampi(int(config.get_value("display", "height", resolution.y)), 720, 4320)
	quality = clampi(int(config.get_value("graphics", "quality", quality)), 0, 3)
	fps_cap = int(config.get_value("graphics", "fps_cap", fps_cap))
	if fps_cap not in [0, 60, 120, 144]:
		fps_cap = 60
	vsync = bool(config.get_value("graphics", "vsync", vsync))
	screen_shake = bool(config.get_value("gameplay", "screen_shake", screen_shake))
	remote_mouse = bool(config.get_value("gameplay", "remote_mouse", false))
	weather_mode = clampi(int(config.get_value("gameplay", "weather", 0)), 0, 5)
	master_volume = clampi(int(config.get_value("audio", "master", master_volume)), 0, 100)
	music_volume = clampi(int(config.get_value("audio", "music", music_volume)), 0, 100)
	effects_volume = clampi(int(config.get_value("audio", "effects", effects_volume)), 0, 100)
	radio_volume = clampi(int(config.get_value("audio", "radio", radio_volume)), 0, 100)
	music_track = clampi(int(config.get_value("audio", "track", music_track)), 0, 2)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "mode", display_mode)
	config.set_value("display", "width", resolution.x)
	config.set_value("display", "height", resolution.y)
	config.set_value("graphics", "quality", quality)
	config.set_value("graphics", "fps_cap", fps_cap)
	config.set_value("graphics", "vsync", vsync)
	config.set_value("gameplay", "screen_shake", screen_shake)
	config.set_value("gameplay", "remote_mouse", remote_mouse)
	config.set_value("gameplay", "weather", weather_mode)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "radio", radio_volume)
	config.set_value("audio", "track", music_track)
	config.save(config_path)


func _exit_tree() -> void:
	if config_path != CONFIG_PATH:
		DirAccess.remove_absolute(config_path)


func apply() -> void:
	Engine.max_fps = fps_cap
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		match display_mode:
			0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(resolution)
				_center_window()
			1:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			2:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_apply_quality()
	_apply_audio_buses()
	save_settings()
	settings_changed.emit()


func cycle_display_mode() -> void:
	display_mode = (display_mode + 1) % 3
	apply()


func cycle_quality() -> void:
	quality = (quality + 1) % 4
	apply()


func cycle_fps_cap() -> void:
	var caps := [60, 120, 144, 0]
	var index := caps.find(fps_cap)
	fps_cap = caps[(index + 1) % caps.size()]
	apply()


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(usable.position + (usable.size - resolution) / 2)


func _apply_quality() -> void:
	var viewport := get_tree().root
	viewport.scaling_3d_scale = [0.72, 0.85, 1.0, 1.0][quality]
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][quality]
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 4096][quality], true)


func _apply_audio_buses() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", effects_volume)
	_set_bus("Radio", radio_volume)


func _set_bus(bus_name: String, percent: int) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(float(percent) / 100.0) if percent > 0 else -80.0)
	AudioServer.set_bus_mute(index, percent == 0)
