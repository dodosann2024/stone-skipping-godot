class_name Ground
extends RefCounted
## v37: single walk-surface query against render-mesh collision (terrain tris +
## dock boxes). No analytic ground_h / mesh_h for walking or foot plant.

var island: Island
var walker: CollisionObject3D


func setup(p_island: Island, p_walker: CollisionObject3D = null) -> void:
	island = p_island
	walker = p_walker


func _exclude() -> Array:
	if walker != null and is_instance_valid(walker):
		return [walker.get_rid()]
	return []


## Walkable height under (x,z). Never falls through to analytic sea ground_h.
func height(x: float, z: float, hint_y: float = 10.0) -> float:
	if island == null:
		return hint_y
	return island.collision_h_walk(x, z, hint_y, _exclude())


func normal(x: float, z: float, hint_y: float = 10.0) -> Vector3:
	if island == null:
		return Vector3.UP
	return island.collision_n(x, z, hint_y, _exclude())


func ray(from: Vector3, to: Vector3) -> Dictionary:
	if island == null:
		return {}
	return island.ray_ground(from, to, _exclude())


## Downward foot ray from well above the ankle (avoids starting inside the mesh).
func ray_foot(ankle: Vector3, body_y: float) -> Dictionary:
	var top_y := maxf(body_y + 2.4, ankle.y + 1.2)
	var bot_y := minf(body_y - 2.0, ankle.y - 1.5)
	var hit := ray(Vector3(ankle.x, top_y, ankle.z), Vector3(ankle.x, bot_y, ankle.z))
	if hit.has("position") and float(hit.position.y) < -0.35:
		hit = {}
	if hit.is_empty():
		var y := height(ankle.x, ankle.z, body_y)
		if y > -0.35:
			return {"position": Vector3(ankle.x, y, ankle.z), "normal": Vector3.UP}
	return hit
