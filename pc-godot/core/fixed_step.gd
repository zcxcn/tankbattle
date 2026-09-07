class_name FixedStep
extends RefCounted

const STEP_SECONDS: float = 1.0 / 60.0
const MAX_FRAME_DELTA_SECONDS: float = 0.15
const MAX_STEPS_PER_FRAME: int = 9

var accumulator_seconds: float = 0.0


## callback is invoked once per 60 Hz simulation tick.
func advance(frame_delta_seconds: float, callback: Callable) -> int:
	if not callback.is_valid():
		return 0
	accumulator_seconds += clampf(
		frame_delta_seconds,
		0.0,
		MAX_FRAME_DELTA_SECONDS
	)
	var steps := 0
	while (
		accumulator_seconds + 0.0000000001 >= STEP_SECONDS
		and steps < MAX_STEPS_PER_FRAME
	):
		callback.call(STEP_SECONDS)
		accumulator_seconds -= STEP_SECONDS
		steps += 1
	return steps


func reset() -> void:
	accumulator_seconds = 0.0
