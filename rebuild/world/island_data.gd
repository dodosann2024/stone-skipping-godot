class_name IslandData
extends Object
## Island outline and the height baked into the walk mesh.
## This is layout data. Nothing at runtime samples it for the body or the feet.

const TERRAIN_STEP := 1.0
const TERRAIN_HALF := 28.0


static func island_r(th: float) -> float:
	return 19.0 + 2.2 * sin(2.0 * th + 0.6) + 1.6 * sin(3.0 * th + 1.9) + 0.9 * sin(5.0 * th + 0.3)


static func shore_d(x: float, z: float) -> float:
	return Vector2(x, z).length() - island_r(atan2(z, x))


static func dock_ends() -> Vector2:
	var r0 := island_r(-PI / 2.0)
	return Vector2(-(r0 - 3.2), -(r0 + 13.5))


static func height_at(x: float, z: float) -> float:
	var d := shore_d(x, z)
	var n := 0.07 * sin(x * 0.9 + z * 0.4) + 0.05 * cos(z * 1.3 - x * 0.5) + 0.04 * sin(x * 2.1 - z * 1.7)
	if d > 0.0:
		return -(clampf(d * 0.17, 0.0, 1.7) + smoothstep(13.0, 26.0, d) * 4.0) + n * 0.6
	var beach := 0.9 * smoothstep(0.0, 6.0, -d)
	var hill := 4.0 * exp(-(pow(x - 2.0, 2) + pow(z - 3.0, 2)) / (2.0 * 6.5 * 6.5))
	var hill2 := 1.5 * exp(-(pow(x + 8.0, 2) + pow(z - 8.0, 2)) / (2.0 * 4.0 * 4.0))
	return beach + (hill + hill2) * smoothstep(1.0, 8.0, -d) + n * (0.6 + 0.4 * smoothstep(0.0, 3.0, -d))


static func surface_kind(x: float, z: float, y: float) -> String:
	var ends := dock_ends()
	if absf(x) < 3.3 and z < ends.x + 0.4 and z > ends.y - 2.2:
		return "wood"
	if y < 0.02:
		return "water"
	if shore_d(x, z) < -6.0 and y > 0.55:
		return "grass"
	return "sand"
