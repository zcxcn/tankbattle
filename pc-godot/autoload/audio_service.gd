extends Node
## Original synthesized weapon, engine and interface audio. No runtime network access.

const SAMPLE_RATE := 44100
const MAX_VOICES := 24
const CANNON_RECORDING := preload("res://assets/audio/recorded/tank_shots_preview_hq.mp3")
const EXPLOSION_RECORDING := preload("res://assets/audio/recorded/muffled_distant_explosion.wav")

var streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_rng.seed = 20490317
	for kind in ["cannon", "machine", "explosion", "mine", "emp", "boss_warning", "hit", "pickup", "click", "victory", "defeat", "engine"]:
		streams[kind] = _synthesize(kind)
	# Recorded CC0 field audio adds the pressure wave and outdoor reflections;
	# the synthesized layers keep the close transient responsive in the mix.
	streams["cannon_tail"] = CANNON_RECORDING
	streams["explosion_tail"] = EXPLOSION_RECORDING


func play_3d(kind: String, world_position: Vector3, volume_db := -5.0, pitch := 1.0) -> void:
	if not streams.has(kind) or get_child_count() >= MAX_VOICES:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = streams[kind]
	voice.position = world_position
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.max_distance = 180.0
	voice.attenuation_filter_cutoff_hz = 12000.0
	voice.bus = "SFX"
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	var maximum_duration := {
		"cannon_tail": 1.15,
		"explosion_tail": 3.2,
	}.get(kind, 0.0) as float
	if maximum_duration > 0.0:
		# A short recording can finish before its cutoff. Binding the timer to
		# the voice cancels it on free, without a lambda capturing a dead node.
		var cutoff := voice.create_tween()
		cutoff.tween_interval(maximum_duration)
		cutoff.tween_callback(voice.queue_free)


func play_ui(kind: String, volume_db := -8.0, pitch := 1.0) -> void:
	if not streams.has(kind) or get_child_count() >= MAX_VOICES:
		return
	var voice := AudioStreamPlayer.new()
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
