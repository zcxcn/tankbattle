class_name TankTrackMarks
extends Node3D
## Pooled projected tread impressions. The native decals conform to the visible
## road layer as well as the collision ground beneath it, without floating quads.

const CAPACITIES := [128, 256, 448, 640]
const VIEW_DISTANCES := [45.0, 65.0, 85.0, 105.0]
const SAMPLE_INTERVAL := 0.10
const MIN_SPACING := 0.62
const TELEPORT_DISTANCE := 4.0
const MARK_LIFETIME := 100.0
const TRACK_LAYOUTS := {
	"challenger2": Vector3(0.966, 0.53, 1.58),
	"kf51": Vector3(0.929, 0.52, 1.56),
	"kv2": Vector3(1.137, 0.63, 1.65),
}

static var _tread_texture: ImageTexture
static var _tread_normal: ImageTexture
var game: Node
var _pool: Array[Decal] = []
var _born := PackedFloat32Array()
var _states: Dictionary = {}
var _capacity := 0
var _player_capacity := 0
var _player_cursor := 0
var _enemy_cursor := 0
var _quality := -1
var _wetness := 0.0
var _time := 0.0
var _sample_clock := 0.0
var _maintenance_clock := 0.0
var _focus := Vector3.ZERO
var _ground_query := PhysicsRayQueryParameters3D.new()
var _emitted := 0
var _ground_rays := 0


func _ready() -> void:
	name = "TrackMarks"
	_ground_query.collision_mask = 1
	_ground_query.collide_with_areas = false
	_create_textures()
	configure_quality(int(get_node("/root/SettingsService").get("quality")))


func configure_quality(value: int) -> void:
	value = clampi(value, 0, 3)
	if value == _quality:
		return
	for mark in _pool:
		mark.free()
	_pool.clear()
	_states.clear()
	_quality = value
	_capacity = CAPACITIES[value]
	_player_capacity = int(_capacity * 0.43)
	_player_cursor = 0
	_enemy_cursor = _player_capacity
	_born.resize(_capacity)
	_born.fill(-1.0)
	for index in _capacity:
		var mark := Decal.new()
		mark.texture_albedo = _tread_texture
		mark.texture_normal = _tread_normal
		mark.albedo_mix = 0.94
		mark.normal_fade = 0.82
		mark.upper_fade = 0.25
		mark.lower_fade = 0.20
		mark.distance_fade_enabled = true
		mark.distance_fade_begin = VIEW_DISTANCES[value] * 0.72
		mark.distance_fade_length = VIEW_DISTANCES[value] * 0.28
		mark.visible = false
		add_child(mark)
		_pool.append(mark)


func set_wetness(value: float) -> void:
	_wetness = clampf(value, 0.0, 1.0)
	_maintenance_clock = 0.25


func clear_marks() -> void:
	for mark in _pool:
		mark.visible = false
	_born.fill(-1.0)
	_states.clear()
	_player_cursor = 0
	_enemy_cursor = _player_capacity
	_emitted = 0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.is_combat_running():
		return
	advance_time(delta)
	_sample_clock += delta
	if _sample_clock < SAMPLE_INTERVAL:
		return
	_sample_clock = fmod(_sample_clock, SAMPLE_INTERVAL)
	configure_quality(int(get_node("/root/SettingsService").get("quality")))
	var player: Node3D = game.get("player")
	if not is_instance_valid(player):
		return
	_focus = player.global_position
	var present: Dictionary = {}
	for tank: Node3D in get_tree().get_nodes_in_group("tanks"):
		var identity := tank.get_instance_id()
		present[identity] = true
		if tank.get("destroyed") or not tank.get("active") or tank.global_position.distance_squared_to(_focus) > pow(VIEW_DISTANCES[_quality], 2.0):
			_states.erase(identity)
			continue
		var layout: Vector3 = TRACK_LAYOUTS.get(tank.call("_model_key"), TRACK_LAYOUTS.challenger2)
		sample_vehicle(identity, tank.global_transform, tank.is_on_floor(), bool(tank.get("is_player")), layout)
	for identity in _states.keys():
		if not present.has(identity):
			_states.erase(identity)


func advance_time(delta: float) -> void:
	_time += maxf(delta, 0.0)
	_maintenance_clock += delta
	if _maintenance_clock < 0.25:
		return
	_maintenance_clock = fmod(_maintenance_clock, 0.25)
	var lifetime := lerpf(MARK_LIFETIME, 75.0, _wetness)
	for index in _pool.size():
		if _born[index] < 0.0:
			continue
		var remaining := lifetime - (_time - _born[index])
		if remaining <= 0.0:
			_born[index] = -1.0
			_pool[index].visible = false
			continue
		var age_fade := smoothstep(0.0, 15.0, remaining)
		_pool[index].modulate = Color(1.0, 1.0, 1.0, age_fade * lerpf(0.72, 1.0, _wetness))
		_pool[index].visible = true


## Public sampling seam also exercises real surface raycasts in regression tests.
## Layout is track half-spacing, print width, rear contact distance in metres.
func sample_vehicle(identity: int, pose: Transform3D, grounded: bool, player_owned: bool, layout := Vector3(0.97, 0.53, 1.58)) -> void:
	if not grounded:
		_states.erase(identity)
		return
	var state: Dictionary = _states.get(identity, {})
	var movement := Vector3.ZERO
	if not state.is_empty():
		movement = pose.origin - Vector3(state.position)
		if movement.length() > TELEPORT_DISTANCE or pose.basis.z.dot(state.forward) < 0.72:
			state = {}
	var direction := 1.0
	if not state.is_empty():
		direction = float(state.direction)
		var signed_movement := movement.dot(pose.basis.z)
		if absf(signed_movement) > 0.06:
			var next_direction := -1.0 if signed_movement > 0.0 else 1.0
			if next_direction != direction:
				state = {} # Front/rear contact changes must never bridge the hull.
			direction = next_direction
	var points: Array = state.get("points", [{}, {}])
	for side in 2:
		var contact := pose * Vector3((-1.0 if side == 0 else 1.0) * layout.x, 0.0, layout.z * direction)
		var previous: Dictionary = points[side]
		if not previous.is_empty() and contact.distance_to(previous.contact) < MIN_SPACING:
			continue # An idling tank does not raycast or stack darker impressions.
		var hit := _sample_ground(contact)
		if hit.is_empty():
			points[side] = {}
			continue
		if not previous.is_empty():
			var from: Vector3 = previous.position
			var to: Vector3 = hit.position
			var separation := from.distance_to(to)
			# Do not bridge steps, unsupported gaps or sharp slope transitions.
			var plane_gap := absf((to - from).dot(Vector3(previous.normal)))
			if separation <= 2.0 and plane_gap <= 0.12 and Vector3(previous.normal).dot(hit.normal) > 0.95 and previous.rid == hit.rid:
				_stamp(from, to, (Vector3(previous.normal) + Vector3(hit.normal)).normalized(), layout.y, player_owned)
		hit["contact"] = contact
		points[side] = hit
	_states[identity] = {"position": pose.origin, "forward": pose.basis.z, "direction": direction, "points": points}


func _sample_ground(contact: Vector3) -> Dictionary:
	_ground_query.from = contact + Vector3.UP * 0.36
	_ground_query.to = contact - Vector3.UP * 0.29
	_ground_rays += 1
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.82:
		return {}
	if absf(Vector3(hit.position).y - contact.y) > 0.20:
		return {}
	return {"position": hit.position, "normal": hit.normal, "rid": hit.rid}


func _stamp(from: Vector3, to: Vector3, normal: Vector3, width: float, player_owned: bool) -> void:
	var index := _player_cursor if player_owned else _enemy_cursor
	if player_owned:
		_player_cursor = (_player_cursor + 1) % _player_capacity
	else:
		_enemy_cursor = _player_capacity + (_enemy_cursor - _player_capacity + 1) % (_capacity - _player_capacity)
	var forward := (to - from).normalized()
	var across := normal.cross(forward).normalized()
	var stamp_basis := Basis(across, normal, across.cross(normal).normalized())
	var mark := _pool[index]
	mark.global_transform = Transform3D(stamp_basis, (from + to) * 0.5 + normal * 0.11)
	# Projection depth includes asphalt above the collision ground, but does not
	# reach vehicle hulls. normal_fade rejects walls and other vertical geometry.
	mark.size = Vector3(width, 0.48, from.distance_to(to) + 0.10)
	mark.modulate = Color(1.0, 1.0, 1.0, lerpf(0.72, 1.0, _wetness))
	mark.visible = true
	_born[index] = _time
	_emitted += 1


func get_snapshot() -> Dictionary:
	var player_marks := 0
	var enemy_marks := 0
	for index in _born.size():
		if _born[index] >= 0.0:
			if index < _player_capacity:
				player_marks += 1
			else:
				enemy_marks += 1
	return {"active": player_marks + enemy_marks, "player": player_marks, "enemy": enemy_marks,
		"cap": _capacity, "player_cap": _player_capacity, "enemy_cap": _capacity - _player_capacity,
		"emitted": _emitted, "ground_rays": _ground_rays, "vehicles": _states.size(),
		"wetness": _wetness, "distance": VIEW_DISTANCES[maxi(_quality, 0)]}


static func _create_textures() -> void:
	if _tread_texture != null:
		return
	var image := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	var normals := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 128:
			var u := (float(x) + 0.5) / 128.0
			var v := (float(y) + 0.5) / 256.0
			var noise := fposmod(sin(float(x * 127 + y * 311)) * 43758.5453, 1.0)
			var edge := smoothstep(0.0, 0.08, minf(u, 1.0 - u) - noise * 0.024)
			var ends := smoothstep(0.0, 0.055, minf(v, 1.0 - v))
			# Five broad segmented shoes with paired diagonal chevrons and a broken
			# center joint, plus a lighter disturbed-soil film beneath the pads.
			var row := fposmod(v * 5.0 + absf(u - 0.5) * 0.7, 1.0)
			var shoe := smoothstep(0.09, 0.17, row) * (1.0 - smoothstep(0.67, 0.80, row))
			var center_joint := 1.0 - (1.0 - smoothstep(0.018, 0.04, absf(u - 0.5))) * 0.68
			var alpha := edge * ends * (0.13 + shoe * center_joint * 0.56) * (0.77 + noise * 0.23)
			image.set_pixel(x, y, Color(0.075 + noise * 0.04, 0.064 + noise * 0.03, 0.048 + noise * 0.025, alpha))
			var bevel := (smoothstep(0.08, 0.14, row) - smoothstep(0.15, 0.21, row) - smoothstep(0.63, 0.70, row) + smoothstep(0.71, 0.79, row)) * 0.18
			normals.set_pixel(x, y, Color(0.5 + bevel * signf(u - 0.5) * 0.4, 0.5 + bevel, 0.985, alpha * 0.45))
	image.generate_mipmaps()
	normals.generate_mipmaps()
	_tread_texture = ImageTexture.create_from_image(image)
	_tread_normal = ImageTexture.create_from_image(normals)
