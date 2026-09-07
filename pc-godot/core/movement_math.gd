class_name MovementMath
extends RefCounted


static func normalized_input(input_vector: Vector2) -> Vector2:
	if not input_vector.is_finite():
		return Vector2.ZERO
	return input_vector.limit_length(1.0)


static func integrate(
	position: Vector2,
	input_vector: Vector2,
	speed_mps: float,
	delta_seconds: float
) -> Vector2:
	return (
		position
		+ normalized_input(input_vector)
		* maxf(0.0, speed_mps)
		* maxf(0.0, delta_seconds)
	)
