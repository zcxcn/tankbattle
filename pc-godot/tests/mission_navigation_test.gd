extends Node3D
## Instantiates every district and sweeps a conservative tank envelope through its roads.

const Catalog = preload("res://data/mission_catalog.gd")
const ArenaScript = preload("res://scenes/missions/industrial_arena.gd")
var passed := 0
var failed := 0
var _shape := BoxShape3D.new()


func _ready() -> void:
	_shape.size = Vector3(6.6, 2.8, 6.6)
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failed += 1
		push_error("FAIL: " + description)


func _clear(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = 1
	query.transform.origin = Vector3(at.x, 1.52, at.z)
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
	if not hits.is_empty():
		print("Blocked tank envelope at ", at, " by ", hits[0].collider.get_path())
	return hits.is_empty()


func _segment_clear(from: Vector3, to: Vector3) -> bool:
	var samples := maxi(1, ceili(from.distance_to(to) / 2.0))
	for sample in range(samples + 1):
		if not _clear(from.lerp(to, float(sample) / float(samples))):
			return false
	return true


func _run() -> void:
	_check(Catalog.count() == 7, "campaign contains six industrial missions and a woodland chapter")
	# Woodland heightfield movement is covered by woodland_map_test.tscn.
	for chapter in range(Catalog.WOODLAND_CHAPTER):
		var spec := Catalog.get_mission(chapter)
		var arena := ArenaScript.new()
		arena.mission_index = chapter
		add_child(arena)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var label := "chapter %d " % (chapter + 1)
		var candidates := arena.get_spawn_candidates()
		var candidates_clear := candidates.size() >= 70
		for point: Vector3 in candidates:
			candidates_clear = _clear(point) and candidates_clear
		_check(candidates_clear, label + "random deployment candidates have 6.6 m hull clearance")
		_check(arena.get_meta("building_types", []).size() >= 6, label + "contains at least six distinct architectural types")
		_check(arena.get_radar_bounds() == Rect2(-144, -192, 288, 384), label + "reports expanded world bounds")
		_check(spec.enemy_layout.size() == [6, 9, 12, 15, 18, 22][chapter], label + "contains the intended dispersed enemy count")
		_check(_clear(spec.player_start) and _clear(spec.boss_position) and _clear(Vector3(0, 0, 51)), label + "player, boss and legacy spawn have full hull clearance")
		_check(spec.player_start.distance_to(spec.enemy_layout[0].position) >= 45.0 and spec.player_start.distance_to(spec.enemy_layout[0].position) <= 60.0, label + "first contact gives the player time to enter the district")
		var objective_clear := _clear(spec.objective_position)
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			objective_clear = _clear(spec.objective_position + direction * float(spec.objective_radius) * 0.7) and objective_clear
		_check(objective_clear, label + "objective and its approach area are clear")
		var supplies_clear := true
		for point: Vector3 in spec.supply_positions:
			supplies_clear = _clear(point) and supplies_clear
		_check(supplies_clear, label + "all repair and rearm sites have full hull clearance")
		var patrols_clear := true
		for enemy: Dictionary in spec.enemy_layout:
			patrols_clear = _clear(enemy.position) and patrols_clear
			patrols_clear = _segment_clear(enemy.position, enemy.patrol[0]) and patrols_clear
			for index in range(enemy.patrol.size()):
				patrols_clear = _segment_clear(enemy.patrol[index], enemy.patrol[(index + 1) % enemy.patrol.size()]) and patrols_clear
		_check(patrols_clear, label + "all patrol segments and their return loops are traversable")
		_check(not _clear(Vector3(0, 0, -156)), label + "closed boss gate has a physical barrier")
		arena.set_boss_gate_open(true)
		await get_tree().physics_frame
		var roads_clear := true
		for x in [-96.0, 0.0, 96.0]:
			roads_clear = _segment_clear(Vector3(x, 0, 184), Vector3(x, 0, -184)) and roads_clear
		for z in [-144.0, -72.0, 0.0, 72.0, 144.0]:
			roads_clear = _segment_clear(Vector3(-136, 0, z), Vector3(136, 0, z)) and roads_clear
		_check(roads_clear, label + "all three avenues and five cross streets connect after gate opens")
		_check(not _clear(Vector3(144, 0, 0)) and not _clear(Vector3(0, 0, 192)), label + "expanded outer walls retain collision")
		var mesh_batches := 0
		var facade_batches := 0
		var shared_mesh_ids := {}
		for child in arena.get_children():
			if child is MultiMeshInstance3D and child.has_meta("licensed_facade_batch"):
				facade_batches += 1
				shared_mesh_ids[child.multimesh.mesh.get_instance_id()] = true
			if child.has_meta("static_detail_batch"):
				mesh_batches += 1
		_check(facade_batches >= 30 and shared_mesh_ids.size() <= 8, label + "licensed facade components are genuinely instantiated and reuse imported meshes")
		_check(mesh_batches > 0 and mesh_batches < 140 and int(arena.get_meta("industrial_detail_pieces")) > 4000, label + "detailed industrial fixtures are batched instead of individual scene nodes")
		arena.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	print("MISSION_NAVIGATION_RESULT: %d passed, %d failed" % [passed, failed])
	await preload("res://tests/test_shutdown.gd").finish(get_tree(), 0 if failed == 0 else 1)
