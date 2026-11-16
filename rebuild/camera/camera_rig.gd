class_name CameraRig
extends Node3D
## Spring arm. Large blockers pull the camera in. Nothing is cut to see the boy.

var player: PlayerBody
var pivot_y := 0.62
var dist := Constants.CAM_DIST
var pitch := Constants.CAM_PITCH
var yaw := PI
var framing := ""
var follow := true
var looking := false
var hold_pitch := false
var cam: Camera3D
var _eye := Vector3.ZERO
var _eye_ok := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.08
	add_child(cam)


func _process(delta: float) -> void:
	if player == null:
		return
	var want := Constants.CAM_DIST
	if framing == "front":
		want = 4.6
		yaw = lerp_angle(yaw, player.face_yaw + PI, 1.0 - exp(-delta * 5.0))
	elif framing == "side":
		want = 5.2
		yaw = lerp_angle(yaw, player.face_yaw + PI * 0.5, 1.0 - exp(-delta * 5.0))
	elif follow and not looking and player.speed > 0.25:
		var err := absf(angle_difference(yaw, player.face_yaw))
		var rate := lerpf(2.4, 7.0, clampf(err / 1.1, 0.0, 1.0))
		yaw = lerp_angle(yaw, player.face_yaw, 1.0 - exp(-delta * rate))
	var pitch_goal := deg_to_rad(40.0) if hold_pitch else Constants.CAM_PITCH
	pitch = lerpf(pitch, pitch_goal, 1.0 - exp(-delta * 2.2))
	pitch = clampf(pitch, deg_to_rad(30.0), deg_to_rad(40.0))
	var chest := _chest()
	var arm := _arm_dir()
	var desired := chest + arm * want
	var cleared := _clear(chest, desired)
	# Stay far enough that the hat brim is not the camera. Pitch stays inside 30–40.
	var want_dist := maxf(chest.distance_to(cleared), Constants.CAM_MIN_DIST)
	var tau := 0.12 if want_dist < dist - 0.05 else 0.22
	dist = lerpf(dist, want_dist, 1.0 - exp(-delta / tau))
	var pos := chest + arm * dist
	if chest.distance_to(pos) > dist:
		pos = chest + arm * dist
	var space := get_world_3d().direct_space_state
	if space != null:
		var down := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 4, 0), pos + Vector3(0, -8, 0))
		down.collision_mask = Constants.LAYER_GROUND
		if player != null:
			down.exclude = [player.get_rid()]
		var floor_hit := space.intersect_ray(down)
		if floor_hit.has("position"):
			var floor_y := float(floor_hit.position.y)
			pos.y = maxf(pos.y, floor_y + 0.55)
	if not _eye_ok:
		_eye = pos
		_eye_ok = true
	else:
		_eye = _eye.lerp(pos, 1.0 - exp(-delta / 0.05))
	global_position = _eye
	look_at(chest, Vector3.UP)
	player.cam_basis = global_transform.basis


func _chest() -> Vector3:
	var p := player.global_position
	if player.is_physics_interpolated():
		p = player.get_global_transform_interpolated().origin
	return p + Vector3(0, pivot_y, 0)


func _arm_dir() -> Vector3:
	var flat := Vector3(sin(yaw), 0, cos(yaw))
	return (flat * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


func _clear(chest: Vector3, desired: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired
	var q := PhysicsRayQueryParameters3D.create(chest, desired)
	q.collision_mask = Constants.LAYER_GROUND | Constants.LAYER_BLOCK | Constants.LAYER_PROP
	if player != null:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.has("position"):
		return desired
	var n := hit.normal as Vector3
	if n.y > 0.65:
		return desired
	var pos: Vector3 = hit.position + n * Constants.CAM_CLEAR
	return pos
