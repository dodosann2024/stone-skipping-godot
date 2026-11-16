class_name OccluderFader
extends Node
## Five rays. A mesh fades only when two of them hit it. Alpha never drops
## below 35%, and no pixel is discarded.

var camera: Camera3D
var player: PlayerBody
var props: Props
var enabled := true
var _tick := 0
var _points: Array[Vector3] = []


func _process(delta: float) -> void:
	if props == null:
		return
	_tick += 1
	if enabled and camera != null and player != null and _tick % 2 == 0:
		for item in props.items:
			item.set_target(1.0)
		_mark()
		_near_camera()
	for item in props.items:
		item.tick(delta)


func _mark() -> void:
	var space := camera.get_world_3d().direct_space_state
	if space == null:
		return
	var origin := camera.global_position
	var feet := player.global_position
	if _points.is_empty():
		_points.resize(5)
	_points[0] = feet + Vector3(0, 1.25, 0)
	_points[1] = feet + Vector3(0, 0.9, 0)
	_points[2] = feet + Vector3(0, 0.55, 0)
	_points[3] = feet + Vector3(-0.1, 0.05, 0)
	_points[4] = feet + Vector3(0.1, 0.05, 0)
	var counts := {}
	for p in _points:
		var q := PhysicsRayQueryParameters3D.create(origin, p)
		q.collision_mask = Constants.LAYER_BLOCK | Constants.LAYER_PROP
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.has("collider"):
			continue
		var body := hit.collider as StaticBody3D
		if body == null or not body.has_meta("fadable"):
			continue
		var id := body.get_instance_id()
		counts[id] = int(counts.get(id, 0)) + 1
		if int(counts[id]) >= 2:
			var fad: Fadable = body.get_meta("fadable")
			fad.set_target(Constants.OCCLUSION_MIN)


func _near_camera() -> void:
	var origin := camera.global_position
	var size := camera.get_viewport().get_visible_rect().size
	for item in props.items:
		var fade := false
		for h in [0.15, 0.7, 1.25]:
			var p := item.global_position + Vector3(0, h, 0)
			var dist := origin.distance_to(p)
			if dist < 3.2:
				fade = true
				break
			if dist > 6.5 or camera.is_position_behind(p):
				continue
			var screen := camera.unproject_position(p)
			if screen.y > size.y * 0.5:
				fade = true
				break
		if fade:
			item.set_target(Constants.OCCLUSION_MIN)
