extends Node3D
## Measure actual bus samples; field values alone cannot prove a hit is heard.

var passed := 0
var failed := 0
var _camera: Camera3D
var _captures: Dictionary = {}
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


func _hits(pool := "") -> Array[Node]:
	return AudioService.get_children().filter(func(n: Node) -> bool:
		return n.get_meta("player_impact", false) and not n.is_queued_for_deletion() and (pool.is_empty() or n.get_meta("impact_pool", "") == pool))


func _clear_captures() -> void:
	for capture: AudioEffectCapture in _captures.values():
		capture.clear_buffer()


func _clear_effects() -> void:
	for voice: Node in AudioService.get_children():
		if voice.has_meta("audio_kind"):
			voice.stop()
			voice.queue_free()
	AudioService._clear_radio()
	await _wait(0.12)
	_clear_captures()


func _stats(bus: String) -> Dictionary:
	var capture: AudioEffectCapture = _captures[bus]
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var energy := 0.0
	var tail_energy := 0.0
	var tail_count := 0
	var first := -1
	var rate := AudioServer.get_mix_rate()
	for i in range(samples.size()):
		var value := maxf(absf(samples[i].x), absf(samples[i].y))
		peak = maxf(peak, value)
		energy += value * value
		if first < 0 and value > 0.01:
			first = i
		if first >= 0 and float(i - first) / rate >= 0.40:
			tail_energy += value * value
			tail_count += 1
	return {"frames": samples.size(), "peak": peak, "rms": sqrt(energy / maxf(1.0, samples.size())),
		"tail_rms": sqrt(tail_energy / maxf(1.0, tail_count)), "onset_ms": float(first) / rate * 1000.0 if first >= 0 else -1.0}


func _sample(label: String, kind: String, severity: float, height := 32.0, duration := 0.90) -> Dictionary:
	_camera.position = Vector3(0, height, 8)
	_clear_captures()
	AudioService._rng.seed = 2045
	AudioService.play_player_hit(kind, severity)
	await _wait(duration)
	var result := {"label": label, "kind": kind, "severity": severity, "camera_height_m": height}
	for bus: String in _captures:
		result[bus] = _stats(bus)
	_measurements.append(result)
	print("IMPACT_AUDIO_CAPTURE ", JSON.stringify(result))
	return result


func _run() -> void:
	AudioService.set_game_state("playing")
	AudioService._clear_radio()
	for deck: AudioStreamPlayer in AudioService._music_players:
		deck.stop()
	for bus in ["Master", "SFX", "WorldSFX", "PlayerImpacts", "PlayerWeapons", "Radio"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), 0.0)
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), false)
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("PlayerImpacts")) == "SFX", "reserved impacts route through user effects settings")
	for bus in ["PlayerImpacts", "Master", "PlayerWeapons", "Radio"]:
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 3.0
		_captures[bus] = capture
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), capture)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	await _wait(0.15)
	var tactical := await _sample("tactical_heavy", "he", 1.0)
	_check(tactical.PlayerImpacts.frames > 30000 and tactical.PlayerImpacts.peak > 0.40, "heavy hit has strong measured cabin impact output")
	_check(tactical.PlayerImpacts.onset_ms >= 0.0 and tactical.PlayerImpacts.onset_ms < 100.0, "metal attack starts within one mixer scheduling window")
	_check(tactical.PlayerImpacts.tail_rms > 0.015, "heavy hit retains recorded low-frequency decay")
	_check(tactical.Master.peak > 0.40 and tactical.Master.peak <= 0.90, "heavy impact reaches final output without clipping")
	await _clear_effects()
	for height in [5.0, 220.0]:
		var result := await _sample("camera_independence", "he", 1.0, height)
		_check(absf(result.PlayerImpacts.peak - tactical.PlayerImpacts.peak) < 0.015, "impact volume stays independent of camera distance: %.0f m" % height)
		await _clear_effects()
	var light := await _sample("light_machine_gun", "machine_gun", 0.3, 32.0, 0.45)
	_check(light.Master.peak > 0.04 and light.Master.peak < tactical.Master.peak * 0.65, "MG strike is audible and lighter than heavy ordnance")
	_check(_hits().is_empty(), "MG metal envelope ends promptly without an explosion tail")
	await _clear_effects()
	for kind in ["cannon", "rocket", "blast"]:
		var result := await _sample("weapon_kind", kind, 0.85)
		_check(result.Master.peak > 0.25 and result.PlayerImpacts.tail_rms > 0.01, "recorded metal and blast are audible for " + kind)
		await _clear_effects()
	var gentle := await _sample("low_severity", "he", 0.15)
	_check(gentle.Master.peak < tactical.Master.peak * 0.85, "accepted damage severity controls impact strength")
	await _clear_effects()
	for value in [0.0, -1.0, NAN, INF]:
		AudioService.play_player_hit("he", value)
	AudioService.play_player_hit("unknown", 1.0)
	_check(_hits().is_empty(), "zero, invalid and unknown hits cannot create spurious sound")
	for i in range(AudioService.MAX_VOICES):
		AudioService.play_3d("explosion", Vector3(float(i % 8) - 4.0, 0.0, float(i / 8)), -16.0)
	_check(AudioService.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D).size() == 24, "stress scene fills all 24 world voices")
	AudioService.play_weapon_fire("cannon", Vector3.ZERO, true)
	AudioService.radio("mission_start")
	var saturated := await _sample("world_full_with_gun_and_radio", "he", 1.0, 32.0, 0.50)
	_check(saturated.PlayerImpacts.peak > 0.40 and _hits("heavy_metal").size() == 1, "full battlefield cannot reject or steal cabin impact")
	_check(saturated.PlayerWeapons.peak > 0.45 and saturated.Radio.peak > 0.20, "own gun and actual human radio keep their independent output")
	_check(saturated.Master.peak > 0.40 and saturated.Master.peak <= 0.90, "combined battlefield, gun, radio and hit obey Master ceiling")
	for i in range(16):
		AudioService.play_player_hit("he", 1.0)
		AudioService.play_player_hit("machine_gun", 1.0)
	_check(_hits("heavy_metal").size() == 3 and _hits("blast").size() == 2 and _hits("light_metal").size() == 2, "rapid mixed damage stays within seven reserved impact voices")
	AudioService.play_ui("click")
	_check(AudioService.get_children().any(func(n: Node) -> bool: return n.get_meta("audio_kind", "") == "click"), "impact pool does not consume UI voice allowance")
	AudioService.play_3d("explosion", Vector3.ZERO, -12.0)
	_check(_hits().size() == 7, "new world effect cannot evict reserved hit layers")
	AudioService.set_game_state("paused")
	var remaining: float = _hits("heavy_metal")[0].get_meta("impact_remaining")
	await _wait(0.20)
	_check(_hits().all(func(n: Node) -> bool: return n.stream_paused) and is_equal_approx(float(_hits("heavy_metal")[0].get_meta("impact_remaining")), remaining), "pause freezes both playback and short impact envelopes")
	AudioService.play_player_hit("cannon", 1.0)
	_check(_hits().size() == 7, "paused state rejects new impact calls")
	AudioService.set_game_state("playing")
	_check(_hits().all(func(n: Node) -> bool: return not n.stream_paused), "resume preserves existing cabin impacts")
	await _clear_effects()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(0.25))
	var quiet := await _sample("effects_quarter", "he", 1.0)
	_check(absf(quiet.Master.peak / tactical.Master.peak - 0.25) < 0.015, "effects slider scales the actual reserved impact output")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), 0.0)
	await _clear_effects()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
	var muted := await _sample("mute_SFX", "he", 1.0, 32.0, 0.40)
	_check(muted.Master.peak < 0.0001, "SFX mute silences downstream Master impact samples")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), false)
	await _clear_effects()
	# Bus effects run before that bus's own volume and mute. Capturing Master
	# cannot observe its final mute; verify that stage's routing explicitly.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) and AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")) == "Master", "impacts retain the final Master mute stage")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)
	AudioService.play_player_hit("he", 1.0)
	AudioService.set_game_state("title")
	await _wait(0.12)
	_check(_hits().is_empty() and is_zero_approx(AudioService._impact_duck_remaining), "menu clears every impact and its world-duck timer")
	for mode in ["title", "settings", "won", "lost"]:
		AudioService.set_game_state(mode)
		AudioService.play_player_hit("cannon", 1.0)
		_check(_hits().is_empty(), "inactive or terminal state rejects new hit: " + mode)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-report="):
			var file := FileAccess.open(argument.trim_prefix("--audio-report="), FileAccess.WRITE)
			file.store_string(JSON.stringify({"passed": passed, "failed": failed, "capture_point": "Bus effects precede their own volume/mute. SFX volume/mute are measured at the downstream Master bus; Master final mute is verified by routing.", "measurements": _measurements}, "  ") + "\n")
	print("IMPACT_AUDIO_RESULT passed=%d failed=%d" % [passed, failed])
	for bus: String in _captures:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.remove_bus_effect(index, AudioServer.get_bus_effect_count(index) - 1)
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
