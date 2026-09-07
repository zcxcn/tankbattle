class_name FirstMissionSpec
extends Resource

const MISSION_ID: StringName = &"gray_ignition"
const DISPLAY_NAME: String = "灰中点火"
const REGULAR_KILL_TARGET: int = 6
const BOSS_REQUIRED: bool = true
const ARENA_SIZE_METERS: Vector2 = Vector2(384.0, 240.0)
const PLAYER_START_METERS: Vector2 = Vector2(192.0, 221.5)
const BOSS_PHASE_ONE_RATIO: float = 0.70
const BOSS_PHASE_TWO_RATIO: float = 0.35


static func boss_phase_thresholds() -> PackedFloat32Array:
	return PackedFloat32Array([BOSS_PHASE_ONE_RATIO, BOSS_PHASE_TWO_RATIO])
