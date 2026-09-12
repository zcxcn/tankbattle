extends RefCounted
## One height function for rendered ground, physical ground and deployment.

const HILLS := [Vector4(-66, 114, 62, 18), Vector4(68, -64, 72, 23), Vector4(-76, -112, 68, 19), Vector4(80, 152, 55, 13)]

static func height_at(x: float, z: float) -> float:
	var bank_distance := maxf(22.0 - z, z - 50.0)
	var bank_blend := smoothstep(4.0, 45.0, bank_distance)
	var height := 0.0
	for hill: Vector4 in HILLS:
		var d := Vector2(x - hill.x, z - hill.y).length_squared() / (hill.z * hill.z)
		height += hill.w * exp(-d * 1.6)
	height += (sin(x * 0.034 + z * 0.012) * sin(z * 0.027) + 1.0) * 0.65
	return -0.05 + height * bank_blend

static func ground(at: Vector3) -> Vector3:
	return Vector3(at.x, height_at(at.x, at.z) + 0.10, at.z)

static func road_distance(x: float, z: float) -> float:
	var vertical := minf(absf(x), minf(absf(x - 96.0), absf(x + 96.0)))
	var horizontal := absf(z - clampf(roundf(z / 72.0) * 72.0, -144.0, 144.0))
	return minf(vertical, horizontal)
