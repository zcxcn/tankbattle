extends Node
## Local recorded combat layers and original interface/engine synthesis.

const SAMPLE_RATE := 44100
const MAX_VOICES := 24
const PLAYER_WEAPON_LIMITS := {"cannon": 4, "machine_gun": 6, "rocket": 4}
const PLAYER_IMPACT_LIMITS := {"light_metal": 2, "heavy_metal": 3, "blast": 2}
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
	"objective_secured": preload("res://assets/audio/battlefield/radio/objective_secured.wav"),
	"mine_deployed": preload("res://assets/audio/battlefield/radio/mine_deployed.wav"),
}
# Complete performances from the CC0 Kenney Voiceover Pack. The four status
# messages without matching recorded words remain text + a quiet UI cue.
const RADIO_CAPTIONS := {
	"command_online": "准备就绪。", "enemy_spotted": "正在接敌！",
	"enemy_approaching": "小心！", "target_destroyed": "目标已摧毁！",
	"multiple_targets": "掩护我的后方！", "armor_low": "掩护我！",
	"armor_critical": "快隐蔽！", "boss_detected": "小心！",
	"boss_destroyed": "目标已摧毁！", "mission_complete": "任务完成。",
	"mission_failed": "任务失败。", "ammo_low": "弹药储备不足。前往补给点。",
	"ammo_depleted": "当前武器弹药耗尽。切换武器。", "armor_restored": "补给完成。装甲修复。",
	"objective_secured": "目标已达成。", "mine_deployed": "当心爆炸！",
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
var _weapon_duck_remaining := 0.0
var _weapon_duck_db := 0.0
var _impact_duck_remaining := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20490317
	for kind in ["mine", "emp", "boss_warning", "hit", "pickup", "click", "victory", "defeat"]:
		streams[kind] = _synthesize(kind)
	# Each recording already contains its immediate report and outdoor decay.
	# Play it once: stacking a synthesized boom and a second full recording
	# obscures the attack and wastes two voices on one discharge.
	streams["cannon"] = CANNON_VARIANTS[0]
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
	_ensure_bus("WorldSFX", "SFX")
	_ensure_bus("PlayerWeapons", "SFX")
	_ensure_bus("PlayerImpacts", "SFX")
	# Cabin impacts have their own reserved mix and ceiling. A burst cannot
	# accumulate enough low-frequency energy to obscure the gun or radio.
	var impact_limiter := AudioEffectLimiter.new()
	impact_limiter.ceiling_db = -3.5
	impact_limiter.threshold_db = -3.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index("PlayerImpacts"), impact_limiter)
	var world_bus := AudioServer.get_bus_index("WorldSFX")
	var world_compressor := AudioEffectCompressor.new()
	world_compressor.threshold = -12.0
	world_compressor.ratio = 4.0
	world_compressor.attack_us = 2000.0
	world_compressor.release_ms = 160.0
	world_compressor.gain = 0.0
	AudioServer.add_bus_effect(world_bus, world_compressor)
	# Safety ceiling only; source and bus gains provide the working headroom.
	# Both child buses still obey the user's SFX and master volume/mute.
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -1.0
		AudioServer.add_bus_effect(master, limiter)
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
	# The audio stops naturally. Its caption lasts at least 1.8 seconds so a
	# short human shout remains readable; _tick_audio owns queue advancement.
	set_music_track(int(SettingsService.get("music_track")), true)


func _ensure_bus(bus_name: String, send := "Master") -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)


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
		_weapon_duck_remaining = maxf(0.0, _weapon_duck_remaining - delta)
		_impact_duck_remaining = maxf(0.0, _impact_duck_remaining - delta)
		_tick_player_impacts(delta)
	var weapon_target := minf(-5.0 if _weapon_duck_remaining > 0.0 else 0.0, -4.0 if _impact_duck_remaining > 0.0 else 0.0)
	_weapon_duck_db = move_toward(_weapon_duck_db, weapon_target, delta * 18.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("WorldSFX"), _weapon_duck_db)
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
	var target_duck := -10.0 if RADIO_CLIPS.has(_radio_id) and _game_mode not in ["paused", "settings"] else 0.0
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
		if node is AudioStreamPlayer3D or node.get_meta("player_weapon", false) or node.get_meta("player_impact", false) or node.get_meta("battlefield_notice", false):
			node.stream_paused = paused
			if mode == "title":
				node.queue_free()
	if mode != "playing":
		for rig: Node in get_tree().get_nodes_in_group("vehicle_audio"):
			rig.stop()
	if mode == "title" or (mode == "playing" and previous not in ["paused", "settings"]):
		_weapon_duck_remaining = 0.0
		_weapon_duck_db = 0.0
		_impact_duck_remaining = 0.0
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("WorldSFX"), 0.0)
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
		"radio_has_voice": RADIO_CLIPS.has(_radio_id), "radio_language": "en",
		"radio_pending": _radio_queue.size(), "duck_db": _music_duck_db}


func get_radio_caption() -> String:
	return RADIO_CAPTIONS.get(_radio_id, "")


func radio(event: String) -> bool:
	event = RADIO_ALIASES.get(event, event)
	if not RADIO_CAPTIONS.has(event) or _game_mode in ["title", "paused", "settings"]:
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
	_radio_player.stop()
	_radio_player.stream = RADIO_CLIPS.get(event)
	if _radio_player.stream != null:
		_radio_remaining = maxf(1.8, _radio_player.stream.get_length() + 0.05)
		_radio_player.play()
	else:
		_radio_remaining = 2.8
		play_ui("click", -20.0, 1.0, true)


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


func play_weapon_fire(kind: String, world_position: Vector3, is_player := false, is_boss := false, pitch := 1.0) -> void:
	if _game_mode != "playing":
		return
	if kind == "machine":
		kind = "machine_gun"
	elif kind == "he":
		kind = "cannon"
	if not PLAYER_WEAPON_LIMITS.has(kind):
		return
	var gain := -3.0 if kind == "cannon" else (-11.0 if kind == "machine_gun" else -8.0)
	if not is_player:
		play_3d(kind, world_position, gain - (2.0 if is_boss else 6.0), pitch, 85 if is_boss else 65)
		return
	# The local report is heard inside the player's vehicle. It must not fall
	# 30 dB with the high tactical camera or lose a slot to distant impacts.
	# Reserve separate bounded pools for main gun, MG and rocket; only retire
	# the oldest tail of the same weapon when its own pool is full.
	var same: Array[Node] = []
	for node: Node in get_children():
		if node.get_meta("player_weapon", false) and node.get_meta("audio_kind", "") == kind and not node.is_queued_for_deletion():
			same.append(node)
	if same.size() >= int(PLAYER_WEAPON_LIMITS[kind]):
		same[0].stop()
		same[0].queue_free()
	var voice := AudioStreamPlayer.new()
	voice.name = "PlayerWeapon"
	voice.set_meta("audio_kind", kind)
	voice.set_meta("player_weapon", true)
	voice.add_to_group("combat_effects")
	voice.stream = _select_stream(kind)
	voice.volume_db = gain
	voice.pitch_scale = clampf(pitch, 0.65, 1.35)
	voice.bus = "PlayerWeapons"
	add_child(voice)
	voice.tree_exiting.connect(_stop_local_voice.bind(voice))
	voice.finished.connect(voice.queue_free)
	voice.play()
	if kind != "machine_gun":
		# Give the attack a small window in the engine/enemy mix; radio and UI
		# remain clear, and the world naturally recovers during the shot tail.
		_weapon_duck_remaining = 0.18
		_weapon_duck_db = -5.0
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("WorldSFX"), _weapon_duck_db)


func _stop_local_voice(voice: AudioStreamPlayer) -> void:
	voice.stop()
	voice.stream = null


func play_player_hit(kind: String, severity: float) -> void:
	if _game_mode != "playing" or not is_finite(severity) or severity <= 0.0:
		return
	if kind not in ["machine_gun", "cannon", "he", "rocket", "blast"]:
		return
	severity = clampf(severity, 0.0, 1.0)
	if kind == "machine_gun":
		# Brief steel strike, without a cannon-sized explosion on each bullet.
		_start_player_impact("light_metal", kind, _select_stream("armor_hit"), lerpf(-16.0, -10.0, severity), 1.18, 0.24, 0.08)
		return
	var explosive := kind in ["he", "rocket", "blast"]
	_start_player_impact("heavy_metal", kind, _select_stream("armor_hit"), lerpf(-7.0, -2.0, severity), lerpf(0.97, 0.82, severity), lerpf(0.65, 0.95, severity), 0.24)
	_start_player_impact("blast", kind, _select_stream("explosion"), lerpf(-13.0, -6.0 if explosive else -8.0, severity), 0.82 if explosive else 0.92, lerpf(0.9, 1.65 if explosive else 1.35, severity), 0.45)
	_impact_duck_remaining = maxf(_impact_duck_remaining, lerpf(0.16, 0.28, severity))
	_weapon_duck_db = minf(_weapon_duck_db, -4.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("WorldSFX"), _weapon_duck_db)


func _start_player_impact(pool: String, kind: String, source: AudioStream, gain: float, pitch: float, duration: float, fade: float) -> void:
	var same: Array[Node] = []
	for node: Node in get_children():
		if node.get_meta("impact_pool", "") == pool and not node.is_queued_for_deletion():
			same.append(node)
	if same.size() >= int(PLAYER_IMPACT_LIMITS[pool]):
		same[0].stop()
		same[0].queue_free()
	var voice := AudioStreamPlayer.new()
	voice.name = "PlayerImpact"
	voice.set_meta("audio_kind", "player_hit_" + kind)
	voice.set_meta("player_impact", true)
	voice.set_meta("impact_pool", pool)
	voice.set_meta("impact_remaining", duration)
	voice.set_meta("impact_fade", fade)
	voice.set_meta("impact_gain", gain)
	voice.add_to_group("combat_effects")
	voice.stream = source
	voice.volume_db = gain
	voice.pitch_scale = pitch
	voice.bus = "PlayerImpacts"
	add_child(voice)
	voice.tree_exiting.connect(_stop_local_voice.bind(voice))
	voice.finished.connect(voice.queue_free)
	voice.play()


func _tick_player_impacts(delta: float) -> void:
	# Explicit envelopes share the stream's pause clock. A real-time tween
	# on this always-processing autoload would silently expire paused tails.
	for node: Node in get_children():
		if not node.get_meta("player_impact", false) or node.is_queued_for_deletion():
			continue
		var remaining := maxf(0.0, float(node.get_meta("impact_remaining")) - delta)
		node.set_meta("impact_remaining", remaining)
		if remaining <= 0.0:
			node.stop()
			node.queue_free()
		else:
			var envelope := minf(1.0, remaining / float(node.get_meta("impact_fade")))
			node.volume_db = float(node.get_meta("impact_gain")) + linear_to_db(maxf(0.0001, envelope))


func play_3d(kind: String, world_position: Vector3, volume_db := -5.0, pitch := 1.0, priority := 40) -> void:
	if not streams.has(kind) or _game_mode in ["paused", "settings"]:
		return
	var fast_effect := kind in ["machine", "machine_gun", "armor_hit", "ground_hit"]
	var same_voices := 0
	var effect_voices := 0
	for node: Node in get_children():
		if node.get_meta("player_weapon", false) or node.get_meta("player_impact", false):
			continue
		if node.has_meta("audio_kind") and not node.is_queued_for_deletion():
			effect_voices += 1
		if node.get_meta("audio_kind", "") == kind and not node.is_queued_for_deletion():
			same_voices += 1
	# A burst cannot consume every voice and suppress the main gun or a Boss.
	if fast_effect and same_voices >= 6:
		return
	if effect_voices >= MAX_VOICES:
		var released := false
		for node: Node in get_children():
			if node.has_meta("audio_kind") and not node.get_meta("player_weapon", false) and not node.get_meta("player_impact", false) and not node.is_queued_for_deletion() and int(node.get_meta("audio_priority", 20)) <= priority:
				node.free()
				released = true
				break
		if not released:
			return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = _select_stream(kind)
	voice.set_meta("audio_kind", kind)
	voice.set_meta("audio_priority", priority)
	voice.add_to_group("combat_effects")
	voice.position = world_position
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.max_distance = 180.0
	# Calibrated for the 32 m tactical listener, matching the vehicle loops.
	# max_db prevents a close chase camera from amplifying above source gain.
	voice.unit_size = 28.0
	voice.max_db = volume_db
	voice.attenuation_filter_cutoff_hz = 12000.0
	voice.bus = "WorldSFX"
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
		"cannon", "cannon_tail":
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


func play_ui(kind: String, volume_db := -8.0, pitch := 1.0, battlefield_notice := false) -> void:
	if not streams.has(kind):
		return
	var ui_voices := get_children().filter(func(node: Node) -> bool: return node is AudioStreamPlayer and node.has_meta("audio_kind") and not node.get_meta("player_weapon", false) and not node.get_meta("player_impact", false) and not node.is_queued_for_deletion())
	if ui_voices.size() >= 4:
		return
	var voice := AudioStreamPlayer.new()
	voice.set_meta("audio_kind", kind)
	voice.set_meta("audio_priority", 10)
	voice.set_meta("battlefield_notice", battlefield_notice)
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
	player.bus = "WorldSFX"
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
