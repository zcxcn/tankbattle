extends RefCounted
## Presentation data for the radar and the cannon's actual line of fire.

static func collect(game: Node3D) -> Dictionary:
	var result := {"tactical_visible": false, "radar_contacts": [], "radar_mines": []}
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
