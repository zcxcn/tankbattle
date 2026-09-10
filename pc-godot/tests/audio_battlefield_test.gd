extends Node3D
## Headless state-machine/ownership checks use actual packaged streams. The
## --test settings path is isolated by SettingsService from player preferences.

var passed := 0
var failed := 0


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS ", message)
	else:
		failed += 1
		push_error("FAIL " + message)


func _run() -> void:
	AudioService.set_process(false)
	AudioService.set_game_state("title")
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("Radio") >= 0, "Music and Radio use independent buses")
	_check(AudioService.get_music_snapshot().count == 3, "three named scores are available")
	var start_id: String = AudioService.get_music_snapshot().id
	var names: Array[String] = []
	for i in range(3):
		var snapshot: Dictionary = AudioService.cycle_music()
		names.append(snapshot.name)
	_check(names.size() == 3 and names[0] != names[1] and names[1] != names[2], "switching rotates through distinct tracks")
	_check(AudioService.get_music_snapshot().id == start_id, "music selector wraps to first track")
	AudioService._tick_audio(1.0)
	_check(AudioService._music_players.filter(func(p: AudioStreamPlayer) -> bool: return p.playing).size() == 1, "finished crossfade releases old playback")
	for definition: Dictionary in AudioService.MUSIC_TRACKS:
		var stream := AudioService._as_loop(definition.stream)
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end > 1000, "music loop covers complete PCM stream: " + definition.id)
		_check(stream.stereo and stream.get_length() > 10.0, "music retains stereo master: " + definition.id)
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.loop_end * 4 == stream.data.size(), "music import preserves every PCM loop frame: " + definition.id)
	for source: AudioStreamWAV in [AudioService.ENGINE_LOOP, AudioService.TREAD_LOOP, AudioService.TURN_LOOP]:
		var loop := AudioService._as_loop(source)
		_check(loop.format == AudioStreamWAV.FORMAT_16_BITS and loop.data.decode_s16(0) == loop.data.decode_s16(loop.data.size() - 2), "mechanical loop remains seamless after engine import")
	for event: String in AudioService.RADIO_CLIPS:
		var clip: AudioStreamWAV = AudioService.RADIO_CLIPS[event]
		_check(clip.get_length() > 0.35 and clip.data.size() > 4096, "radio contains complete actor take: " + event)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/audio/radio_lines.json"))
	for event: String in manifest:
		_check(AudioService.RADIO_CAPTIONS[event] == manifest[event].caption, "subtitle matches the reviewed recording/notice: " + event)
	_check(not AudioService.radio("enemy_spotted"), "menu suppresses stale battlefield announcements")
	AudioService.set_game_state("playing")
	_check(AudioService.radio("mission_start"), "mission-start alias starts actual radio playback")
	_check(not AudioService.get_radio_caption().is_empty() and AudioService._radio_id == "command_online", "caption belongs to currently playing line")
	_check(not AudioService.radio("mission_start"), "duplicate reports are suppressed")
	_check(AudioService._radio_remaining >= 1.8 and AudioService.get_music_snapshot().radio_has_voice, "short actor shouts retain a readable subtitle")
	_check(AudioService.radio("enemy_destroyed"), "ordinary report queues behind current voice")
	_check(AudioService._radio_id == "command_online" and AudioService._radio_queue.size() == 1, "queued speech never overlaps current speech")
	_check(AudioService.radio("player_critical"), "critical armor report is accepted")
	_check(AudioService._radio_id == "armor_critical", "urgent damage interrupts low-priority status")
	AudioService._tick_audio(0.3)
	_check(AudioService.get_music_snapshot().duck_db <= -9.9, "radio lowers music by ten decibels")
	var radio_time: float = AudioService._radio_remaining
	AudioService.set_game_state("paused")
	AudioService._tick_audio(2.0)
	_check(AudioService._radio_player.stream_paused and is_equal_approx(AudioService._radio_remaining, radio_time), "pause freezes radio playback and its timer")
	_check(not AudioService.radio("enemy_near"), "paused combat cannot enqueue new alerts")
	AudioService.set_game_state("playing")
	_check(not AudioService._radio_player.stream_paused and AudioService._radio_id == "armor_critical", "resume preserves interrupted radio position")
	_check(AudioService.radio("mission_complete"), "mission success report overrides combat chatter")
	AudioService.set_game_state("won")
	_check(AudioService._radio_id == "mission_complete", "result screen retains terminal spoken report")
	AudioService._tick_audio(5.0)
	AudioService._tick_audio(2.0)
	_check(AudioService.get_radio_caption().is_empty() and is_zero_approx(AudioService._music_duck_db), "finished report clears caption and restores music")
	AudioService.set_game_state("title")
	AudioService.set_game_state("playing")
	_check(AudioService.radio("enemy_near"), "new mission resets radio cooldowns")
	AudioService.radio("enemy_destroyed")
	AudioService.radio("ammo_low")
	AudioService.radio("resupply")
	AudioService.radio("mine_deployed")
	_check(AudioService._radio_queue.size() <= 3, "radio queue is bounded during busy combat")
	AudioService._finish_radio()
	_check(not AudioService.radio("enemy_near"), "cooldown outlives one completed clip")
	AudioService._clear_radio()
	for notice: String in ["ammo_low", "ammo_depleted", "armor_restored", "mines_cleared"]:
		AudioService._radio_cooldowns.clear()
		_check(AudioService.radio(notice), "unvoiced status still enters bounded reporting queue: " + notice)
		_check(not AudioService._radio_player.playing and AudioService._radio_player.stream == null and not AudioService.get_music_snapshot().radio_has_voice, "unvoiced status never plays unrelated speech: " + notice)
		AudioService._tick_audio(2.0)
		_check(not AudioService.get_radio_caption().is_empty() and is_zero_approx(AudioService._music_duck_db), "text notice stays readable without ducking music: " + notice)
		AudioService._tick_audio(1.0)
		_check(AudioService.get_radio_caption().is_empty(), "text notice expires without waiting for an audio finished signal: " + notice)
		AudioService._clear_radio()
	var vehicle := Node3D.new()
	add_child(vehicle)
	var rig: Node3D = AudioService.attach_vehicle(vehicle)
	AudioService.update_vehicle(rig, 0.0, 0.0, 0.0, 0.2)
	_check(rig.engine.playing and not rig.treads.playing and not rig.steering.playing, "stationary tank idles without false rolling or turning sounds")
	AudioService.update_vehicle(rig, 5.0, 0.0, 0.0, 0.2)
	_check(rig.treads.playing and not rig.steering.playing, "real forward motion starts tread layer")
	AudioService.update_vehicle(rig, 0.0, 0.65, 0.0, 0.2)
	_check(rig.treads.playing and rig.steering.playing, "measured pivot rotation drives tread and steering foley")
	AudioService.update_vehicle(rig, 0.0, 0.0, 0.0, 0.2)
	_check(not rig.treads.playing and not rig.steering.playing, "blocked or stopped hull produces no track motion")
	AudioService.update_vehicle(rig, 0.0, 0.0, 4.5, 0.1)
	_check(rig.impact_count == 1, "real collision impulse creates one impact")
	AudioService.update_vehicle(rig, 0.0, 0.0, 4.5, 0.1)
	_check(rig.impact_count == 1, "continuous wall contact cannot spam collision audio")
	AudioService.update_vehicle(rig, 0.0, 0.0, 0.3, 1.0)
	_check(rig.impact_count == 1, "small contact jitter cannot trigger a crash")
	AudioService.update_vehicle(rig, 5.0, 0.5, 0.0, 0.2)
	AudioService.set_game_state("paused")
	_check(not rig.engine.playing and not rig.treads.playing and not rig.steering.playing, "pause immediately stops every vehicle motion layer")
	AudioService.set_game_state("playing")
	AudioService.update_vehicle(rig, 5.0, 0.0, 0.0, 0.2)
	AudioService.stop_vehicle(rig)
	_check(not rig.engine.playing and not rig.treads.playing, "destroyed tank explicitly stops all mechanical loops")
	var listener := Camera3D.new()
	add_child(listener)
	listener.position = Vector3(0, 0, 140)
	listener.current = true
	AudioService.update_vehicle(rig, 5.0, 0.4, 0.0, 0.3)
	_check(not rig.engine.playing and not rig.treads.playing and not rig.steering.playing, "inaudible distant vehicles release all three mechanical playback layers")
	listener.position = Vector3(0, 0, 30)
	AudioService.update_vehicle(rig, 5.0, 0.4, 0.0, 0.3)
	_check(rig.engine.playing and rig.treads.playing and rig.steering.playing, "approaching the listener restores mechanical layers without changing motion")
	listener.free()
	vehicle.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(rig), "vehicle deletion frees attached audio voices")
	AudioService.set_game_state("title")
	await get_tree().process_frame
	_check(AudioService.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer3D).is_empty(), "return to menu releases battlefield one-shots")
	_check(AudioService.get_child_count() == 3, "only two music decks and one command radio persist")
	AudioService.set_music_track(99)
	_check(AudioService.get_music_snapshot().index < 3, "invalid saved music index safely wraps")
	print("AUDIO_BATTLEFIELD_RESULT passed=%d failed=%d" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
