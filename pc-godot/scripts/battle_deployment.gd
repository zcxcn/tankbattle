class_name BattleDeployment
extends RefCounted
## Reproducible random deployments on physically validated drivable ground.

static func build(mission: Dictionary, candidates: Array[Vector3], deployment_seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = deployment_seed
	var available: Array[Vector3] = []
	var start: Vector3 = mission.player_start
	for at: Vector3 in candidates:
		if at.distance_to(start) >= 54.0 and at.z > -156.0 and at.z < 150.0:
			available.append(at)
	# Fisher-Yates on an owned RNG makes tests repeatable without fixing live runs.
	for index in range(available.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := available[index]
		available[index] = available[other]
		available[other] = swap
	var selected: Array[Dictionary] = []
	var layout: Array = mission.enemy_layout
	for candidate: Vector3 in available:
		if selected.size() >= layout.size():
			break
		var separated := true
		for placed: Dictionary in selected:
			if candidate.distance_to(placed.position) < 17.0:
				separated = false
				break
		if not separated:
			continue
		var route := patrol_for(candidate, rng)
		if not _clears_objective(mission, candidate, route):
			continue
		var facing := route[0] - candidate
		selected.append({"position": candidate, "kind": layout[selected.size()].kind, "patrol": route, "yaw": atan2(-facing.x, -facing.z)})
	return selected

static func _clears_objective(mission: Dictionary, at: Vector3, route: Array[Vector3]) -> bool:
	if str(mission.get("objective_type", "")) != "demolition":
		return true
	# The solid 8x7m fuel depot occupies a road. Include the tank envelope when
	# checking the complete patrol, including its initial approach.
	var target: Vector3 = mission.objective_position
	var points: Array[Vector3] = [at]
	points.append_array(route)
	for index in range(1, points.size()):
		var closest := Geometry2D.get_closest_point_to_segment(Vector2(target.x, target.z), Vector2(points[index - 1].x, points[index - 1].z), Vector2(points[index].x, points[index].z))
		if closest.distance_to(Vector2(target.x, target.z)) < 10.0:
			return false
	return true


static func patrol_for(at: Vector3, rng: RandomNumberGenerator) -> Array[Vector3]:
	var nearest_x := 0.0
	for x: float in [-96.0, 96.0]:
		if absf(at.x - x) < absf(at.x - nearest_x):
			nearest_x = x
	var nearest_z := roundf(at.z / 72.0) * 72.0
	var vertical := absf(at.x - nearest_x) < 8.0
	if vertical and absf(at.z - nearest_z) < 6.0:
		vertical = rng.randf() > 0.4
	var distance := rng.randf_range(17.0, 29.0)
	var route: Array[Vector3] = []
	if vertical:
		route.assign([Vector3(nearest_x, 0.05, clampf(at.z - distance, -151.0, 144.0)), Vector3(nearest_x, 0.05, clampf(at.z + distance, -151.0, 144.0))])
	else:
		route.assign([Vector3(clampf(at.x - distance, -126.0, 126.0), 0.05, nearest_z), Vector3(clampf(at.x + distance, -126.0, 126.0), 0.05, nearest_z)])
	if rng.randf() > 0.5:
		route.reverse()
	return route
