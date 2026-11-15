class_name PlayerController
extends RefCounted
## v37: owns explore root XZ/Y. One ground query per sample; write physics Y once.
## main.gd still drives mode glue / throw / rest, but walk height always goes
## through Ground (render-mesh collision — never analytic ground_h / mesh_h).

var ground: Ground
var body_pos := Vector3.ZERO
var body_yaw := 0.0


func setup(p_ground: Ground) -> void:
	ground = p_ground


func height(x: float, z: float, hint_y: float = 10.0) -> float:
	if ground == null:
		return hint_y
	return ground.height(x, z, hint_y)


## Pelvis Y step ≤2.9 cm/frame (AAA bar) both up and down.
func apply_walk_y(from_y: float, x: float, z: float) -> float:
	var h := height(x, z, from_y)
	return from_y + clampf(h - from_y, -0.029, 0.029)


func display_y(prev_y: float, x: float, z: float) -> float:
	var hy := height(x, z, prev_y)
	return prev_y + clampf(hy - prev_y, -0.029, 0.029)
