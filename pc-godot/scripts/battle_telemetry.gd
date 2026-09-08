extends RefCounted
## Presentation data for the radar and the cannon's actual line of fire.

static func collect(game: Node3D) -> Dictionary:
	var result := {"tactical_visible": false, "radar_contacts": [], "radar_mines": [], "enemy_markers": []}
	var player: Node3D = game.get("player")
	if game.get("mode") != "playing" or not is_instance_valid(player) or player.get("destroyed"):
		return result
	result["tactical_visible"] = true
	result["radar_player"] = Vector2(player.global_position.x, player.global_position.z)
	result["radar_heading"] = player.rotation.y
	for tank: Node in game.get_tree().get_nodes_in_group("tanks"):
		if tank == player or not game.is_ancestor_of(tank) or tank.get("destroyed"):
			continue
		var at: Vector3 = tank.global_position
		result["radar_contacts"].append({"position": Vector2(at.x, at.z), "boss": tank.get("is_boss"), "active": tank.get("active")})
	for mine: Node in game.get_tree().get_nodes_in_group("mines"):
		if not game.is_ancestor_of(mine) or mine.is_queued_for_deletion():
			continue
		var at: Vector3 = mine.global_position
		result["radar_mines"].append({"position": Vector2(at.x, at.z), "friendly": mine.get("team") == player.get("team")})
	var camera: Camera3D = player.get("camera")
	var muzzle: Node3D = player.get("_muzzle")
	var barrel: Node3D = player.get("_barrel")
	var turret: Node3D = player.get("_turret")
	if not is_instance_valid(camera) or not is_instance_valid(muzzle):
		return result
	var aim: Vector3 = player.get("aim_point")
	result["aim_visible"] = not camera.is_position_behind(aim)
	result["aim_screen"] = camera.unproject_position(aim) if result["aim_visible"] else Vector2.ZERO
	var direction := -turret.global_basis.z
	direction.y = 0.0
	direction = direction.normalized()
	var distance := clampf(Vector2(aim.x - muzzle.global_position.x, aim.z - muzzle.global_position.z).length(), 3.0, 90.0)
	var query := PhysicsRayQueryParameters3D.create(barrel.global_position, muzzle.global_position, 1 | 4, [player.get_rid()])
	query.hit_from_inside = true
	var space := player.get_world_3d().direct_space_state
	result["enemy_markers"] = _visible_enemy_markers(game, player, camera, turret, space)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		query.from = muzzle.global_position
		query.to = muzzle.global_position + direction * distance
		hit = space.intersect_ray(query)
	var impact: Vector3 = hit.get("position", muzzle.global_position + direction * distance)
	var collider: CollisionObject3D = hit.get("collider") as CollisionObject3D
	result["impact_visible"] = not camera.is_position_behind(impact)
	result["impact_screen"] = camera.unproject_position(impact) if result["impact_visible"] else Vector2.ZERO
	result["aim_blocked"] = collider != null and (collider.collision_layer & 1) != 0
	result["aim_target"] = collider != null and (collider.collision_layer & 4) != 0
	result["aim_distance"] = muzzle.global_position.distance_to(impact)
	result["fire_interval"] = player.get("fire_interval")
	return result


static func _visible_enemy_markers(game: Node3D, player: Node3D, camera: Camera3D, turret: Node3D, space: PhysicsDirectSpaceState3D) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var viewport := camera.get_viewport().get_visible_rect().grow(-38.0)
	for tank: Node in game.get_tree().get_nodes_in_group("tanks"):
		if tank == player or not game.is_ancestor_of(tank) or tank.is_queued_for_deletion():
			continue
		if tank.get("team") == player.get("team") or tank.get("is_boss") or tank.get("destroyed") or not tank.get("active"):
			continue
		var health := clampf(float(tank.get("hp")) / maxf(1.0, float(tank.get("max_hp"))), 0.0, 1.0)
		var aiming := 0.0
		if float(tank.get("stunned")) <= 0.0:
			aiming = clampf(float(tank.get("_aim_hold_time")) / maxf(0.01, float(tank.get("aim_acquire_time"))), 0.0, 1.0)
		if health >= 0.999 and aiming <= 0.08:
			continue
		var enemy_turret: Node3D = tank.get("_turret")
		if not is_instance_valid(enemy_turret):
			continue
		var target := enemy_turret.global_position + Vector3.UP * 0.3
		var anchor := target + Vector3.UP * 1.05
		if camera.is_position_behind(anchor):
			continue
		var screen := camera.unproject_position(anchor)
		if not viewport.has_point(screen):
			continue
		# Check the actual vehicle, not the floating label. A high camera or a label
		# above a roof must never reveal an enemy hidden behind that roof or a wall.
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, target, 1 | 4, [player.get_rid(), tank.get_rid()])
		query.hit_from_inside = true
		if not space.intersect_ray(query).is_empty():
			continue
		query.from = turret.global_position + Vector3.UP * 0.3
		if not space.intersect_ray(query).is_empty():
			continue
		markers.append({"screen": screen, "health": health, "aiming": aiming})
	return markers
