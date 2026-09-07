class_name SweepMath
extends RefCounted

const NO_HIT: float = -1.0


## Returns the first normalized hit time in [0, 1], or NO_HIT.
static func segment_circle_fraction(
	start: Vector2,
	finish: Vector2,
	center: Vector2,
	radius: float
) -> float:
	if radius < 0.0:
		return NO_HIT
	var delta := finish - start
	var offset := start - center
	var a := delta.length_squared()
	if is_zero_approx(a):
		return 0.0 if offset.length_squared() <= radius * radius else NO_HIT
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var b := 2.0 * offset.dot(delta)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return NO_HIT
	var hit := (-b - sqrt(discriminant)) / (2.0 * a)
	return hit if hit >= 0.0 and hit <= 1.0 else NO_HIT


## Slab intersection against an axis-aligned Rect2.
static func segment_rect_fraction(
	start: Vector2,
	finish: Vector2,
	rect: Rect2
) -> float:
	var low := 0.0
	var high := 1.0
	var delta := finish - start
	var starts := PackedFloat32Array([start.x, start.y])
	var directions := PackedFloat32Array([delta.x, delta.y])
	var minimums := PackedFloat32Array([rect.position.x, rect.position.y])
	var maximums := PackedFloat32Array([rect.end.x, rect.end.y])
	for axis: int in range(2):
		var direction := directions[axis]
		if is_zero_approx(direction):
			if starts[axis] < minimums[axis] or starts[axis] > maximums[axis]:
				return NO_HIT
			continue
		var first := (minimums[axis] - starts[axis]) / direction
		var second := (maximums[axis] - starts[axis]) / direction
		if first > second:
			var swap := first
			first = second
			second = swap
		low = maxf(low, first)
		high = minf(high, second)
		if low > high:
			return NO_HIT
	return low if low >= 0.0 and low <= 1.0 else NO_HIT


static func nearest_fraction(fractions: PackedFloat32Array) -> float:
	var nearest := INF
	for fraction: float in fractions:
		if fraction >= 0.0 and fraction <= 1.0:
			nearest = minf(nearest, fraction)
	return NO_HIT if is_inf(nearest) else nearest
