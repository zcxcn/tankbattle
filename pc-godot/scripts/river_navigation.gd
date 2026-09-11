extends RefCounted
## A small, stateless river portal router for the authored three-bridge layout.
## Entry/exit points include eight meters of bank clearance for a turning hull.

const BRIDGES := [-96.0, 0.0, 96.0]
const NORTH_BANK := 22.0
const SOUTH_BANK := 50.0
const NORTH_ENTRY := 14.0
const SOUTH_ENTRY := 58.0


static func next_waypoint(from: Vector3, target: Vector3) -> Vector3:
	var current_bridge := _nearest_bridge(from.x)
	var half_width := 9.0 if is_zero_approx(current_bridge) else 8.0
	# Stay on the axis until the entire hull has cleared the rail ends, even if
	# the target is already on the same bank as the front half of this vehicle.
	if from.z > NORTH_ENTRY and from.z < SOUTH_ENTRY and absf(from.x - current_bridge) < half_width - 2.8:
		if target.z > NORTH_BANK and target.z < SOUTH_BANK and is_equal_approx(_nearest_bridge(target.x), current_bridge):
			return Vector3(current_bridge, target.y, target.z)
		return Vector3(current_bridge, target.y, NORTH_ENTRY if target.z <= NORTH_BANK else SOUTH_ENTRY)
	if (from.z <= NORTH_BANK and target.z <= NORTH_BANK) or (from.z >= SOUTH_BANK and target.z >= SOUTH_BANK):
		return target
	var from_south := from.z >= (NORTH_BANK + SOUTH_BANK) * 0.5
	var entry_z := SOUTH_ENTRY if from_south else NORTH_ENTRY
	var exit_z := NORTH_ENTRY if from_south else SOUTH_ENTRY
	var bridge := _choose_bridge(from, target, entry_z, exit_z)
	var entry := Vector3(bridge, target.y, entry_z)
	# First move along the safe bank toward the bridge mouth. Cutting directly
	# toward the far exit from a diagonal bank approach intersects the rail.
	if absf(from.x - bridge) > 1.8 or absf(from.z - entry_z) > 2.0:
		return entry
	if target.z > NORTH_BANK and target.z < SOUTH_BANK:
		return Vector3(bridge, target.y, target.z)
	return Vector3(bridge, target.y, exit_z)


static func _nearest_bridge(x: float) -> float:
	var nearest := 0.0
	var distance := INF
	for bridge: float in BRIDGES:
		if absf(x - bridge) < distance:
			nearest = bridge
			distance = absf(x - bridge)
	return nearest


static func _choose_bridge(from: Vector3, target: Vector3, entry_z: float, exit_z: float) -> float:
	if target.z > NORTH_BANK and target.z < SOUTH_BANK:
		return _nearest_bridge(target.x)
	var selected := 0.0
	var best_cost := INF
	for bridge: float in BRIDGES:
		var cost := Vector2(from.x - bridge, from.z - entry_z).length() + Vector2(target.x - bridge, target.z - exit_z).length()
		if cost < best_cost:
			selected = bridge
			best_cost = cost
	return selected
