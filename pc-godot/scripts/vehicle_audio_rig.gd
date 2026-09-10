extends Node3D
## Mechanical layers follow measured motion. The owner frees every voice with
## the vehicle; inactive/destroyed vehicles explicitly stop their loops.

var engine: AudioStreamPlayer3D
var treads: AudioStreamPlayer3D
var steering: AudioStreamPlayer3D
var current_speed := 0.0
var current_yaw_rate := 0.0
var impact_cooldown := 0.0
var audible := false
var impact_count := 0
var _listener_refresh := 0.0
var _within_hearing := true
var _engine_stream: AudioStream
var _tread_stream: AudioStream
var _turn_stream: AudioStream


func configure(engine_stream: AudioStream, tread_stream: AudioStream, turn_stream: AudioStream) -> void:
	_engine_stream = engine_stream
	_tread_stream = tread_stream
	_turn_stream = turn_stream


func _ready() -> void:
	add_to_group("vehicle_audio")
	engine = _make_layer("Engine", _engine_stream, 100.0)
	treads = _make_layer("Treads", _tread_stream, 62.0)
	steering = _make_layer("Steering", _turn_stream, 48.0)
	tree_exiting.connect(stop)


func _make_layer(layer_name: String, stream: AudioStream, maximum_distance: float) -> AudioStreamPlayer3D:
	var layer := AudioStreamPlayer3D.new()
	layer.name = layer_name
	layer.stream = stream
	layer.bus = "WorldSFX"
	# The tactical listener sits around 32 m above its own tank. Calibrate the
	# reference distance for that camera so tracks remain audible in both views.
	layer.unit_size = 28.0
	layer.max_distance = maximum_distance
	layer.attenuation_filter_cutoff_hz = 5600.0
	layer.volume_db = -80.0
	add_child(layer)
	return layer


func update_motion(speed_mps: float, yaw_rate: float, impact_speed: float, delta: float, enabled: bool) -> bool:
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	if not enabled:
		stop()
		return false
	_listener_refresh -= delta
	if _listener_refresh <= 0.0:
		_listener_refresh = 0.25
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			# Hysteresis keeps an inaudible distant engine from repeatedly restarting.
			var limit := 120.0 if _within_hearing else 105.0
			_within_hearing = camera.global_position.distance_squared_to(global_position) <= limit * limit
	if not _within_hearing:
		stop()
		return false
	current_speed = absf(speed_mps)
	current_yaw_rate = absf(yaw_rate)
	# A pivot turn moves the tracks even when the hull center is stationary.
	var track_motion := maxf(current_speed, current_yaw_rate * 1.65)
	var movement := clampf(track_motion / 8.0, 0.0, 1.0)
	var turn := clampf(current_yaw_rate / 1.1, 0.0, 1.0)
	_set_layer(engine, -22.0 + movement * 9.0, 0.72 + movement * 0.65, true, delta)
	_set_layer(treads, -20.0 + movement * 13.0, 0.64 + movement * 0.9, track_motion > 0.08, delta)
	_set_layer(steering, -24.0 + turn * 12.0, 0.7 + turn * 0.36, current_yaw_rate > 0.04, delta)
	audible = true
	if impact_speed >= 1.4 and impact_cooldown <= 0.0:
		impact_cooldown = 0.85
		impact_count += 1
		return true
	return false


func _set_layer(layer: AudioStreamPlayer3D, target_db: float, pitch: float, enabled: bool, delta: float) -> void:
	if not enabled:
		layer.volume_db = -80.0
		layer.stop()
		return
	if not layer.playing:
		layer.volume_db = -60.0
		layer.play()
	layer.volume_db = lerpf(layer.volume_db, target_db, minf(1.0, delta * 9.0))
	layer.pitch_scale = lerpf(layer.pitch_scale, pitch, minf(1.0, delta * 6.0))


func stop() -> void:
	audible = false
	current_speed = 0.0
	current_yaw_rate = 0.0
	for layer in [engine, treads, steering]:
		if is_instance_valid(layer):
			layer.stop()
			layer.volume_db = -80.0


func _exit_tree() -> void:
	stop()
	for layer in [engine, treads, steering]:
		if is_instance_valid(layer):
			layer.stream = null
	_engine_stream = null
	_tread_stream = null
	_turn_stream = null
