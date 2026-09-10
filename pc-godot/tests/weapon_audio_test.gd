extends Node3D
## Real AudioEffectCapture samples verify the routed mixer output, including
## the transient, tail, camera independence, saturation and user mute.

var passed := 0
var failed := 0
var _capture: AudioEffectCapture
var _master_capture: AudioEffectCapture
var _camera: Camera3D
var _measurements: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS ", message)
	else:
		failed += 1
		push_error("FAIL " + message)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _clear_effects() -> void:
	for voice: Node in AudioService.get_children():
		if voice.has_meta("audio_kind"):
			voice.stop()
			voice.queue_free()
	await _wait(0.10)
	_capture.clear_buffer()
	_master_capture.clear_buffer()


func _sample(kind: String, height: float, duration := 1.35) -> Dictionary:
	_camera.position = Vector3(0.0, height, 8.0)
	_capture.clear_buffer()
	_master_capture.clear_buffer()
	# Reset variation so moving the camera compares the identical recording.
	AudioService._rng.seed = 1044
	AudioService.play_weapon_fire(kind, Vector3.ZERO, true, false, 1.0)
	await _wait(duration)
	var frames := _capture.get_buffer(_capture.get_frames_available())
	var final_frames := _master_capture.get_buffer(_master_capture.get_frames_available())
	var peak := 0.0
	var final_peak := 0.0
	var first := -1
	var energy := 0.0
	var tail_energy := 0.0
	var tail_frames := 0
	var rate := AudioServer.get_mix_rate()
	for i in range(frames.size()):
		var sample: float = maxf(absf(frames[i].x), absf(frames[i].y))
		peak = maxf(peak, sample)
		energy += sample * sample
		if first < 0 and sample > 0.01:
			first = i
		if first >= 0 and float(i - first) / rate >= 0.45:
			tail_energy += sample * sample
			tail_frames += 1
	for frame: Vector2 in final_frames:
		final_peak = maxf(final_peak, maxf(absf(frame.x), absf(frame.y)))
	var result := {"kind": kind, "height_m": height, "frames": frames.size(), "peak": peak,
		"master_peak": final_peak, "rms": sqrt(energy / maxf(1.0, frames.size())),
		"tail_rms": sqrt(tail_energy / maxf(1.0, tail_frames)),
		"onset_ms": float(first) / rate * 1000.0 if first >= 0 else -1.0}
	_measurements.append(result)
	print("WEAPON_AUDIO_CAPTURE ", JSON.stringify(result))
	return result


func _player_voices(kind := "") -> Array[Node]:
	return AudioService.get_children().filter(func(n: Node) -> bool:
		return n.get_meta("player_weapon", false) and not n.is_queued_for_deletion() and (kind.is_empty() or n.get_meta("audio_kind", "") == kind))


func _run() -> void:
	AudioService.set_game_state("playing")
	AudioService._clear_radio()
	for deck: AudioStreamPlayer in AudioService._music_players:
		deck.stop()
	for bus_name in ["Master", "SFX", "PlayerWeapons", "WorldSFX"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), 0.0)
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus_name), false)
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("PlayerWeapons")) == "SFX", "reserved player shots still obey effects volume")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 4.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("PlayerWeapons"), _capture)
	_master_capture = AudioEffectCapture.new()
	_master_capture.buffer_length = 4.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _master_capture)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	await _wait(0.15)
	var tactical := await _sample("cannon", 32.0)
	_check(tactical.frames > 40000 and tactical.peak > 0.28, "actual tactical cannon mixer output has an unmistakable attack")
	_check(tactical.onset_ms >= 0.0 and tactical.onset_ms < 100.0, "recorded cannon transient starts within one audio scheduling window")
	_check(tactical.tail_rms > 0.015, "recorded cannon retains audible pressure and reflection tail")
	_check(tactical.master_peak > 0.20 and tactical.master_peak < 0.90, "local shot reaches final Master bus with headroom")
	await _clear_effects()
	var chase := await _sample("cannon", 5.0)
	_check(absf(chase.peak - tactical.peak) < 0.015, "chase and tactical cameras hear equal local cannon attack")
	await _clear_effects()
	var distant := await _sample("cannon", 220.0)
	_check(absf(distant.peak - tactical.peak) < 0.015, "camera zoom beyond spatial range cannot mute the player's weapon")
	await _clear_effects()
	for kind in ["machine_gun", "rocket", "he"]:
		var result := await _sample(kind, 32.0, 0.75)
		_check(result.peak > 0.12 and result.master_peak > 0.08, "distinct recorded weapon reaches output: " + kind)
		await _clear_effects()
	_camera.position = Vector3(0, 32, 8)
	var vehicle := Node3D.new()
	add_child(vehicle)
	var rig: Node3D = AudioService.attach_vehicle(vehicle)
	AudioService.update_vehicle(rig, 7.5, 0.8, 0.0, 0.3)
	AudioService.set_music_track(0, true)
	await _wait(0.35)
	_master_capture.clear_buffer()
	await _wait(0.35)
	var ambient_frames := _master_capture.get_buffer(_master_capture.get_frames_available())
	var ambient_peak := 0.0
	for frame: Vector2 in ambient_frames:
		ambient_peak = maxf(ambient_peak, maxf(absf(frame.x), absf(frame.y)))
	var moving := await _sample("cannon", 32.0, 0.75)
	_check(ambient_peak > 0.001 and moving.master_peak > ambient_peak + 0.2, "local cannon attack cuts through actual engine, tread, turn and music playback")
	AudioService.stop_vehicle(rig)
	vehicle.queue_free()
	for deck: AudioStreamPlayer in AudioService._music_players:
		deck.stop()
	await _clear_effects()
	for i in range(AudioService.MAX_VOICES):
		AudioService.play_3d("explosion", Vector3(float(i % 8) - 4.0, 0.0, float(i / 8)), -16.0)
	_check(AudioService.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D).size() == AudioService.MAX_VOICES, "stress scenario fills every ordinary effect voice")
	for i in range(12):
		AudioService.play_ui("click")
	var saturated := await _sample("cannon", 32.0, 0.50)
	_check(saturated.peak > 0.28 and _player_voices("cannon").size() == 1, "full enemy and UI pools cannot steal or reject the player's cannon")
	_check(saturated.master_peak > 0.20 and saturated.master_peak <= 0.90, "busy battlefield reaches Master without clipping")
	for i in range(20):
		AudioService.play_weapon_fire("machine_gun", Vector3.ZERO, true)
	_check(_player_voices("machine_gun").size() == 6 and _player_voices("cannon").size() == 1, "sustained MG retires only its own oldest tails")
	AudioService.set_game_state("paused")
	_check(_player_voices().all(func(n: Node) -> bool: return n.stream_paused), "pause freezes all reserved weapon tails")
	var paused_count := _player_voices().size()
	AudioService.play_weapon_fire("cannon", Vector3.ZERO, true)
	_check(_player_voices().size() == paused_count, "paused weapon cannot create a fresh report")
	AudioService.set_game_state("playing")
	_check(_player_voices().all(func(n: Node) -> bool: return not n.stream_paused), "resume restores weapon tails")
	await _clear_effects()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(0.25))
	var quiet := await _sample("cannon", 32.0, 0.4)
	_check(absf(quiet.master_peak / tactical.master_peak - 0.25) < 0.01, "effects slider scales reserved weapon output without bypassing player preference")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), 0.0)
	await _clear_effects()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
	var muted := await _sample("cannon", 32.0, 0.4)
	_check(muted.master_peak < 0.0001, "effects mute silences the reserved weapon at final output")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), false)
	AudioService.set_game_state("title")
	await _wait(0.1)
	_check(_player_voices().is_empty(), "return to title releases every reserved weapon")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/audio/radio_lines.json"))
	_check(manifest.command_online.source == "Male/ready.ogg" and manifest.command_online.transcript == "Ready.", "opening uses the complete CC0 Ready actor take")
	_check(AudioService.RADIO_CAPTIONS.command_online == manifest.command_online.caption, "Ready caption matches its actual recording")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-report="):
			var file := FileAccess.open(argument.trim_prefix("--audio-report="), FileAccess.WRITE)
			file.store_string(JSON.stringify({"passed": passed, "failed": failed, "measurements": _measurements}, "  ") + "\n")
	print("WEAPON_AUDIO_RESULT passed=%d failed=%d" % [passed, failed])
	AudioServer.remove_bus_effect(AudioServer.get_bus_index("PlayerWeapons"), 0)
	AudioServer.remove_bus_effect(AudioServer.get_bus_index("Master"), AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")) - 1)
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
