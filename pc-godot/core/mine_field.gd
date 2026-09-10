class_name MineField
extends RefCounted

const CombatEnumsRef = preload("res://data/combat_enums.gd")
const MineStateRef = preload("res://core/mine_state.gd")
const SweepMathRef = preload("res://core/sweep_math.gd")

const DEFAULT_ARM_DELAY_SECONDS: float = 1.2
const DEFAULT_LIFETIME_SECONDS: float = 90.0
const DEFAULT_TRIGGER_RADIUS_M: float = 1.8
const DEFAULT_MIN_SPACING_M: float = 3.4

var max_total: int = 32
var max_per_owner: int = 8
var mines: Array[MineStateRef] = []
var _next_id: int = 1


func try_place(
	owner_id: int,
	faction: CombatEnumsRef.Faction,
	position: Vector3,
	damage: float,
	now: float,
	arm_delay: float = DEFAULT_ARM_DELAY_SECONDS,
	lifetime: float = DEFAULT_LIFETIME_SECONDS
) -> MineStateRef:
	prune_expired(now)
	if faction != CombatEnumsRef.Faction.PLAYER or damage <= 0.0:
		return null
	if mines.size() >= max_total or count_for_owner(owner_id) >= max_per_owner:
		return null
	for mine: MineStateRef in mines:
		if mine.position.distance_to(position) < DEFAULT_MIN_SPACING_M:
			return null
	var placed := MineStateRef.new(
		_next_id,
		owner_id,
		faction,
		position,
		damage,
		now + maxf(0.0, arm_delay),
		now + maxf(maxf(arm_delay, 0.0), lifetime)
	)
	_next_id += 1
	mines.append(placed)
	return placed


func count_for_owner(owner_id: int) -> int:
	var count := 0
	for mine: MineStateRef in mines:
		if mine.owner_id == owner_id:
			count += 1
	return count


## Consumes and returns the nearest armed hostile mine within trigger radius.
func take_triggered(
	target_position: Vector3,
	target_faction: CombatEnumsRef.Faction,
	now: float,
	trigger_radius: float = DEFAULT_TRIGGER_RADIUS_M
) -> MineStateRef:
	return take_triggered_swept(
		target_position,
		target_position,
		target_faction,
		now,
		trigger_radius
	)


## Sweeps on the XZ ground plane so a fast target cannot tunnel through a mine.
func take_triggered_swept(
	target_start: Vector3,
	target_end: Vector3,
	target_faction: CombatEnumsRef.Faction,
	now: float,
	trigger_radius: float = DEFAULT_TRIGGER_RADIUS_M
) -> MineStateRef:
	prune_expired(now)
	var best: MineStateRef = null
	var best_fraction := INF
	var sweep_start := Vector2(target_start.x, target_start.z)
	var sweep_end := Vector2(target_end.x, target_end.z)
	for mine: MineStateRef in mines:
		if not mine.can_trigger(target_faction, now):
			continue
		var mine_center := Vector2(mine.position.x, mine.position.z)
		var fraction: float = SweepMathRef.segment_circle_fraction(
			sweep_start,
			sweep_end,
			mine_center,
			maxf(0.0, trigger_radius)
		)
		if fraction != SweepMathRef.NO_HIT and fraction < best_fraction:
			best = mine
			best_fraction = fraction
	if best != null:
		mines.erase(best)
	return best


## EMP removes friendly and hostile mines, including mines still arming.
func clear_with_emp(center: Vector3, radius: float, now: float) -> int:
	prune_expired(now)
	if radius < 0.0:
		return 0
	var kept: Array[MineStateRef] = []
	var removed := 0
	for mine: MineStateRef in mines:
		if mine.position.distance_to(center) <= radius:
			removed += 1
		else:
			kept.append(mine)
	mines = kept
	return removed


func prune_expired(now: float) -> int:
	var kept: Array[MineStateRef] = []
	var removed := 0
	for mine: MineStateRef in mines:
		if now >= mine.expires_at:
			removed += 1
		else:
			kept.append(mine)
	mines = kept
	return removed
