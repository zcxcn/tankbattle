extends Node
## Local recorded combat layers and original interface/engine synthesis.

const SAMPLE_RATE := 44100
const MAX_VOICES := 24
const CANNON_RECORDING := preload("res://assets/audio/recorded/tank_shots_preview_hq.mp3")
const EXPLOSION_RECORDING := preload("res://assets/audio/recorded/muffled_distant_explosion.wav")
const CANNON_VARIANTS := [preload("res://assets/audio/combat/cannon-01.wav"), preload("res://assets/audio/combat/cannon-02.wav"), preload("res://assets/audio/combat/cannon-03.wav")]
const EXPLOSION_VARIANTS := [preload("res://assets/audio/combat/explosion-heavy-01.wav"), preload("res://assets/audio/combat/explosion-heavy-02.wav")]
const ARMOR_VARIANTS := [preload("res://assets/audio/combat/impact-armor-01.wav"), preload("res://assets/audio/combat/impact-armor-02.wav")]
const MACHINE_RECORDING := preload("res://assets/audio/combat/mg-fire.wav")
const ROCKET_RECORDING := preload("res://assets/audio/combat/rocket-launch.wav")
const RICOCHET_RECORDING := preload("res://assets/audio/combat/ricochet-01.wav")
const VehicleAudioRig := preload("res://scripts/vehicle_audio_rig.gd")
const MUSIC_TRACKS := [
	{"id": "industrial-war", "name": "钢铁风暴", "stream": preload("res://assets/audio/battlefield/music/industrial-war.wav")},
	{"id": "electronic-pursuit", "name": "极速追击", "stream": preload("res://assets/audio/battlefield/music/electronic-pursuit.wav")},
	{"id": "epic-siege", "name": "决战重围", "stream": preload("res://assets/audio/battlefield/music/epic-siege.wav")},
]
const ENGINE_LOOP := preload("res://assets/audio/battlefield/vehicle/track-engine.wav")
const TREAD_LOOP := preload("res://assets/audio/battlefield/vehicle/track-treads.wav")
const TURN_LOOP := preload("res://assets/audio/battlefield/vehicle/track-turn.wav")
const RADIO_CLIPS := {
	"command_online": preload("res://assets/audio/battlefield/radio/command_online.wav"),
	"enemy_spotted": preload("res://assets/audio/battlefield/radio/enemy_spotted.wav"),
	"enemy_approaching": preload("res://assets/audio/battlefield/radio/enemy_approaching.wav"),
	"target_destroyed": preload("res://assets/audio/battlefield/radio/target_destroyed.wav"),
	"multiple_targets": preload("res://assets/audio/battlefield/radio/multiple_targets.wav"),
	"armor_low": preload("res://assets/audio/battlefield/radio/armor_low.wav"),
	"armor_critical": preload("res://assets/audio/battlefield/radio/armor_critical.wav"),
	"boss_detected": preload("res://assets/audio/battlefield/radio/boss_detected.wav"),
	"boss_destroyed": preload("res://assets/audio/battlefield/radio/boss_destroyed.wav"),
	"mission_complete": preload("res://assets/audio/battlefield/radio/mission_complete.wav"),
	"mission_failed": preload("res://assets/audio/battlefield/radio/mission_failed.wav"),
	"ammo_low": preload("res://assets/audio/battlefield/radio/ammo_low.wav"),
	"ammo_depleted": preload("res://assets/audio/battlefield/radio/ammo_depleted.wav"),
	"armor_restored": preload("res://assets/audio/battlefield/radio/armor_restored.wav"),
	"objective_secured": preload("res://assets/audio/battlefield/radio/objective_secured.wav"),
	"mine_deployed": preload("res://assets/audio/battlefield/radio/mine_deployed.wav"),
	"mines_cleared": preload("res://assets/audio/battlefield/radio/mines_cleared.wav"),
}
const RADIO_CAPTIONS := {
	"command_online": "指挥链路已建立。战车就位。", "enemy_spotted": "发现敌军。准备接敌。",
	"enemy_approaching": "注意，敌方装甲正在逼近。", "target_destroyed": "目标已摧毁。",
	"multiple_targets": "发现多辆敌车。注意侧翼。", "armor_low": "装甲受损。寻找掩体。",
	"armor_critical": "车体重创！立即撤离交火区。", "boss_detected": "敌方指挥战车出现。集中火力。",
	"boss_destroyed": "敌方指挥战车已击毁。", "mission_complete": "任务完成。战场已控制。",
	"mission_failed": "战车失联。任务终止。", "ammo_low": "弹药储备不足。前往补给点。",
	"ammo_depleted": "当前武器弹药耗尽。切换武器。", "armor_restored": "补给完成。装甲修复。",
	"objective_secured": "目标已控制。准备下一阶段。", "mine_deployed": "地雷已部署。注意安全距离。",
	"mines_cleared": "脉冲完成。附近地雷已清除。",
}
const RADIO_PRIORITIES := {"mission_failed": 100, "mission_complete": 100, "armor_critical": 90,
	"boss_detected": 85, "boss_destroyed": 80, "ammo_depleted": 72, "enemy_approaching": 65,
	"multiple_targets": 60, "armor_low": 58, "objective_secured": 55, "command_online": 52}
const RADIO_COOLDOWNS := {"enemy_spotted": 25.0, "enemy_approaching": 22.0, "multiple_targets": 28.0,
	"target_destroyed": 5.5, "armor_low": 32.0, "armor_critical": 24.0, "ammo_low": 24.0,
	"ammo_depleted": 18.0, "mine_deployed": 12.0, "mines_cleared": 12.0}
const RADIO_ALIASES := {"enemy_near": "enemy_approaching", "enemy_destroyed": "target_destroyed",
	"player_critical": "armor_critical", "boss_incoming": "boss_detected",
	"mission_start": "command_online", "resupply": "armor_restored"}

var streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _game_mode := "title"
var _music_index := 0
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_transition := 1.0
var _music_duck_db := 0.0
var _radio_player: AudioStreamPlayer
var _radio_id := ""
var _radio_remaining := 0.0
var _radio_gap := 0.0
var _radio_queue: Array[String] = []
var _radio_cooldowns: Dictionary = {}
var _audio_clock := 0.0
var _loop_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20490317
	for kind in ["cannon", "machine", "explosion", "mine", "emp", "boss_warning", "hit", "pickup", "click", "victory", "defeat", "engine"]:
		streams[kind] = CANNON_VARIANTS[0] if DisplayServer.get_name() == "headless" else _synthesize(kind)
	# Recorded CC0 field audio adds the pressure wave and outdoor reflections;
	# the synthesized layers keep the close transient responsive in the mix.
	streams["cannon_tail"] = CANNON_VARIANTS[0]
	streams["explosion_tail"] = EXPLOSION_RECORDING
	streams["explosion"] = EXPLOSION_VARIANTS[0]
	streams["machine"] = MACHINE_RECORDING
	streams["machine_gun"] = MACHINE_RECORDING
	streams["rocket"] = ROCKET_RECORDING
	streams["armor_hit"] = ARMOR_VARIANTS[0]
	streams["ground_hit"] = streams["hit"]
	streams["ricochet"] = RICOCHET_RECORDING
	streams["engine"] = _as_loop(ENGINE_LOOP)
	streams["collision"] = ARMOR_VARIANTS[0]
	_ensure_bus("Radio")
	for index in range(2):
		var music := AudioStreamPlayer.new()
		music.name = "MusicDeck%d" % index
		music.bus = "Music"
		music.volume_db = -80.0
		add_child(music)
		_music_players.append(music)
	_radio_player = AudioStreamPlayer.new()
	_radio_player.name = "CommandRadio"
	_radio_player.bus = "Radio"
	_radio_player.volume_db = -2.0
	add_child(_radio_player)
	_radio_player.finished.connect(_finish_radio)
	set_music_track(int(SettingsService.get("music_track")), true)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _as_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var key := source.get_instance_id()
	if _loop_cache.has(key):
		return _loop_cache[key]
	var loop := source.duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = roundi(source.get_length() * source.mix_rate)
	_loop_cache[key] = loop
	return loop


func _process(delta: float) -> void:
	_tick_audio(delta)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	set_process(false)
	for voice: Node in get_children():
		if voice is AudioStreamPlayer or voice is AudioStreamPlayer3D:
			voice.stop()
			voice.stream = null
	_music_players.clear()
	_loop_cache.clear()
	streams.clear()
	for rig: Node in get_tree().get_nodes_in_group("vehicle_audio"):
		rig.stop()


func _tick_audio(delta: float) -> void:
	if _game_mode not in ["paused", "settings"]:
		_audio_clock += delta
		_radio_gap = maxf(0.0, _radio_gap - delta)
		if _radio_remaining > 0.0:
			_radio_remaining = maxf(0.0, _radio_remaining - delta)
			if _radio_remaining <= 0.0:
				_finish_radio()
		if _radio_id.is_empty() and _radio_gap <= 0.0 and not _radio_queue.is_empty():
			_start_radio(_radio_queue.pop_front())
	_music_transition = minf(1.0, _music_transition + delta / 0.65)
	var target_duck := -10.0 if not _radio_id.is_empty() and _game_mode not in ["paused", "settings"] else 0.0
	_music_duck_db = move_toward(_music_duck_db, target_duck, delta * (45.0 if target_duck < _music_duck_db else 8.0))
	var scene_gain := -11.0 if _game_mode in ["paused", "settings"] else (-5.0 if _game_mode == "title" else 0.0)
	for index in range(_music_players.size()):
		var weight := _music_transition if index == _music_active else 1.0 - _music_transition
		_music_players[index].volume_db = -12.0 + scene_gain + _music_duck_db + linear_to_db(maxf(weight, 0.0001))
		if weight <= 0.0 and index != _music_active:
			_music_players[index].stop()


func set_game_state(mode: String) -> void:
	if mode == _game_mode:
		return
	var previous := _game_mode
	_game_mode = mode
	var paused := mode in ["paused", "settings"]
	_radio_player.stream_paused = paused
	for node: Node in get_children():
		if node is AudioStreamPlayer3D:
			node.stream_paused = paused
			if mode == "title":
				node.queue_free()
	if mode != "playing":
		for rig: Node in get_tree().get_nodes_in_group("vehicle_audio"):
			rig.stop()
	if mode == "title" or (mode == "playing" and previous not in ["paused", "settings"]):
		_clear_radio()
		_radio_cooldowns.clear()
	if mode in ["won", "lost"]:
		_radio_queue.clear()


func cycle_music() -> Dictionary:
	set_music_track((_music_index + 1) % MUSIC_TRACKS.size())
	return get_music_snapshot()


func set_music_track(index: int, immediate := false) -> void:
	_music_index = posmod(index, MUSIC_TRACKS.size())
	if _music_players.is_empty():
		return
	_music_active = 1 - _music_active
	var player := _music_players[_music_active]
	player.stop()
	player.stream = _as_loop(MUSIC_TRACKS[_music_index].stream)
	player.volume_db = -80.0
	player.play()
	_music_transition = 1.0 if immediate else 0.0
	_tick_audio(0.0)


func get_music_snapshot() -> Dictionary:
	return {"id": MUSIC_TRACKS[_music_index].id, "name": MUSIC_TRACKS[_music_index].name,
		"index": _music_index, "count": MUSIC_TRACKS.size(),
		"playing": not _music_players.is_empty() and _music_players[_music_active].playing,
		"radio_event": _radio_id, "radio_caption": RADIO_CAPTIONS.get(_radio_id, ""),
		"radio_pending": _radio_queue.size(), "duck_db": _music_duck_db}


func get_radio_caption() -> String:
	return RADIO_CAPTIONS.get(_radio_id, "")


func radio(event: String) -> bool:
	event = RADIO_ALIASES.get(event, event)
	if not RADIO_CLIPS.has(event) or _game_mode in ["title", "paused", "settings"]:
		return false
	if float(_radio_cooldowns.get(event, -100.0)) > _audio_clock or event == _radio_id or event in _radio_queue:
		return false
	var priority := int(RADIO_PRIORITIES.get(event, 40))
	var current_priority := int(RADIO_PRIORITIES.get(_radio_id, 40))
	_radio_cooldowns[event] = _audio_clock + float(RADIO_COOLDOWNS.get(event, 10.0))
	# Critical damage and terminal mission events can interrupt a low-value
	# report; normal announcements wait for one voice plus receiver spacing.
	if _radio_id.is_empty() and _radio_gap <= 0.0:
		_start_radio(event)
	elif priority == 100 or (priority >= 85 and priority >= current_priority + 20):
		_radio_player.stop()
		_start_radio(event)
	else:
		_radio_queue.append(event)
		_radio_queue.sort_custom(func(a: String, b: String) -> bool: return int(RADIO_PRIORITIES.get(a, 40)) > int(RADIO_PRIORITIES.get(b, 40)))
		if _radio_queue.size() > 3:
			var dropped: String = _radio_queue.pop_back()
			if dropped == event:
				return false
	return true


func _start_radio(event: String) -> void:
	_radio_id = event
	_radio_player.stream = RADIO_CLIPS[event]
	_radio_remaining = _radio_player.stream.get_length() + 0.05
	_radio_player.play()


func _finish_radio() -> void:
	_radio_player.stop()
	_radio_id = ""
	_radio_remaining = 0.0
	_radio_gap = 0.38


func _clear_radio() -> void:
	_finish_radio()
	_radio_gap = 0.0
	_radio_queue.clear()


func attach_vehicle(parent: Node3D) -> Node3D:
	var rig := VehicleAudioRig.new()
	rig.name = "VehicleAudio"
	rig.configure(_as_loop(ENGINE_LOOP), _as_loop(TREAD_LOOP), _as_loop(TURN_LOOP))
	parent.add_child(rig)
	return rig


func update_vehicle(rig: Node3D, speed_mps: float, yaw_rate: float, impact_speed: float, delta: float) -> void:
	if not is_instance_valid(rig):
		return
	if rig.update_motion(speed_mps, yaw_rate, impact_speed, delta, _game_mode == "playing"):
		play_3d("collision", rig.global_position, lerpf(-17.0, -5.0, clampf(impact_speed / 9.0, 0.0, 1.0)), _rng.randf_range(0.63, 0.82))


func stop_vehicle(rig: Node3D) -> void:
	if is_instance_valid(rig):
		rig.stop()


func play_3d(kind: String, world_position: Vector3, volume_db := -5.0, pitch := 1.0) -> void:
	if not streams.has(kind) or _game_mode in ["paused", "settings"]:
		return
	var fast_effect := kind in ["machine", "machine_gun", "armor_hit", "ground_hit"]
	var same_voices := 0
	var effect_voices := 0
	for node: Node in get_children():
		if node.has_meta("audio_kind") and not node.is_queued_for_deletion():
			effect_voices += 1
		if node.get_meta("audio_kind", "") == kind and not node.is_queued_for_deletion():
			same_voices += 1
	# A burst cannot consume every voice and suppress the main gun or a Boss.
	if fast_effect and same_voices >= 6:
		return
	if effect_voices >= MAX_VOICES:
		if fast_effect:
			return
		var released := false
		for node: Node in get_children():
			if node.get_meta("audio_kind", "") in ["machine", "machine_gun", "armor_hit", "ground_hit"]:
				node.free()
				released = true
				break
		if not released:
			return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = _select_stream(kind)
	voice.set_meta("audio_kind", kind)
	voice.add_to_group("combat_effects")
	voice.position = world_position
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.max_distance = 180.0
	voice.attenuation_filter_cutoff_hz = 12000.0
	voice.bus = "SFX"
	add_child(voice)
	voice.tree_exiting.connect(_stop_spatial_voice.bind(voice))
	voice.finished.connect(voice.queue_free)
	voice.play()
	var maximum_duration := {
		"cannon_tail": 3.2,
		"explosion_tail": 3.2,
	}.get(kind, 0.0) as float
	if maximum_duration > 0.0:
		# A short recording can finish before its cutoff. Binding the timer to
		# the voice cancels it on free, without a lambda capturing a dead node.
		var cutoff := voice.create_tween()
		cutoff.tween_interval(maximum_duration)
		cutoff.tween_callback(voice.queue_free)


func _select_stream(kind: String) -> AudioStream:
	match kind:
		"cannon_tail":
			return CANNON_VARIANTS[_rng.randi_range(0, CANNON_VARIANTS.size() - 1)]
		"explosion":
			return EXPLOSION_VARIANTS[_rng.randi_range(0, EXPLOSION_VARIANTS.size() - 1)]
		"armor_hit", "collision":
			return ARMOR_VARIANTS[_rng.randi_range(0, ARMOR_VARIANTS.size() - 1)]
	return streams[kind]


func _stop_spatial_voice(voice: AudioStreamPlayer3D) -> void:
	# Stop explicitly before releasing the stream, including mission changes
	# and quit while a long explosion tail is still playing.
	voice.stop()
	voice.stream = null


func play_ui(kind: String, volume_db := -8.0, pitch := 1.0) -> void:
	if not streams.has(kind) or get_child_count() >= MAX_VOICES:
		return
	var voice := AudioStreamPlayer.new()
	voice.set_meta("audio_kind", kind)
	voice.stream = streams[kind]
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.bus = "SFX"
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


func attach_engine(parent: Node3D) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	if streams.has("engine"):
		player.stream = streams["engine"]
	player.volume_db = -18.0
	player.max_distance = 80.0
	player.bus = "SFX"
	parent.add_child(player)
	player.play()
	return player


func _synthesize(kind: String) -> AudioStreamWAV:
	var duration := {
		"cannon": 1.15, "machine": 0.22, "explosion": 1.65, "mine": 1.1,
		"emp": 1.25, "boss_warning": 0.72, "hit": 0.28, "pickup": 0.5,
		"click": 0.11, "victory": 2.4, "defeat": 1.8, "engine": 3.0,
	}.get(kind, 0.5) as float
	var frames := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var low_noise := 0.0
	var crackle := 0.0
	for i in range(frames):
		var t := float(i) / SAMPLE_RATE
		var p := t / duration
		var noise := _rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.018)
		crackle = lerpf(crackle, noise, 0.24)
		var sample := 0.0
		match kind:
			"cannon":
				var attack := minf(t * 180.0, 1.0) * exp(-t * 4.0)
				sample = (sin(TAU * (72.0 - t * 24.0) * t) * 0.72 + low_noise * 0.5 + noise * exp(-t * 35.0) * 0.8) * attack
				sample += sin(TAU * 138.0 * t) * exp(-t * 8.0) * 0.18
			"machine":
				sample = (noise * 0.85 + sin(TAU * (180.0 - t * 300.0) * t) * 0.45) * minf(t * 300.0, 1.0) * exp(-t * 21.0)
			"explosion", "mine":
				var impulse := minf(t * 140.0, 1.0) * exp(-t * (3.1 if kind == "explosion" else 4.2))
				sample = (sin(TAU * (48.0 - t * 12.0) * t) * 0.82 + low_noise * 0.72 + noise * exp(-t * 18.0) * 0.55) * impulse
			"emp":
				sample = (sin(TAU * (115.0 + t * 980.0) * t) + sin(TAU * 52.0 * t) * 0.55 + crackle * 0.35) * sin(PI * clampf(p, 0.0, 1.0)) * 0.45
			"boss_warning":
				sample = (sin(TAU * 92.0 * t) + sin(TAU * 184.0 * t) * 0.35) * (0.45 + 0.55 * signf(sin(TAU * 5.0 * t))) * sin(PI * p) * 0.42
			"hit":
				sample = (noise * 0.65 + sin(TAU * 310.0 * t) * 0.3) * exp(-t * 18.0)
			"pickup":
				sample = (sin(TAU * (440.0 + t * 720.0) * t) + sin(TAU * 880.0 * t) * 0.25) * sin(PI * p) * 0.35
			"click":
				sample = (noise * 0.3 + sin(TAU * 760.0 * t) * 0.35) * exp(-t * 45.0)
			"victory":
				var note: float = [220.0, 277.18, 329.63, 440.0][mini(int(t / 0.6), 3)]
				sample = (sin(TAU * note * t) + sin(TAU * note * 1.5 * t) * 0.4) * sin(PI * fmod(t, 0.6) / 0.6) * 0.28
			"defeat":
				sample = (sin(TAU * (110.0 - t * 28.0) * t) + sin(TAU * 55.0 * t) * 0.45) * pow(1.0 - p, 1.4) * 0.3
			"engine":
				sample = (sin(TAU * 42.0 * t) * 0.5 + sin(TAU * 84.0 * t) * 0.22 + low_noise * 0.18) * (0.82 + sin(TAU * 3.5 * t) * 0.1)
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 27500.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	if kind == "engine":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
	return stream
