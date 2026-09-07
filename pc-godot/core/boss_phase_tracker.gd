class_name BossPhaseTracker
extends RefCounted

const PHASE_ONE_RATIO: float = 0.70
const PHASE_TWO_RATIO: float = 0.35

var _thresholds: Array[float]
var _triggered: PackedByteArray


func _init() -> void:
	_thresholds = [PHASE_ONE_RATIO, PHASE_TWO_RATIO]
	_triggered.resize(_thresholds.size())
	_triggered.fill(0)


## Returns one-based phase numbers newly crossed by this health update.
## A large hit may cross both thresholds, but every phase is returned only once.
func update(current_health: float, maximum_health: float) -> Array[int]:
	var entered: Array[int] = []
	if maximum_health <= 0.0:
		return entered
	var ratio := clampf(current_health / maximum_health, 0.0, 1.0)
	for index: int in range(_thresholds.size()):
		if _triggered[index] == 0 and ratio <= _thresholds[index]:
			_triggered[index] = 1
			entered.append(index + 1)
	return entered


func current_phase() -> int:
	var phase := 0
	for value: int in _triggered:
		phase += int(value != 0)
	return phase


func has_triggered(phase: int) -> bool:
	var index := phase - 1
	return index >= 0 and index < _triggered.size() and _triggered[index] != 0
