class_name CameraRig
extends Node3D
## Spring arm. Large blockers pull the camera in. Nothing is cut to see the boy.

var player: PlayerBody
var pivot_y := 0.62
var dist := Constants.CAM_DIST
var pitch := Constants.CAM_PITCH
var yaw := PI
var _held := false
var framing := ""
var cam: Camera3D


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.08
	add_child(cam)


func _process(delta: float) -> void:
	if player == null:
		return
	var stick_down := player.stick.length() > Constants.DEADZONE or player.route
	var want := Constants.CAM_DIST if stick_down else Constants.CAM_DIST_WIDE
	if framing == "front":
		want = 4.2
		yaw = lerp_angle(yaw, player.face_yaw + PI, 1.0 - exp(-delta * 4.0))
	elif framing == "side":
		want = 5.0
		yaw = lerp_angle(yaw, player.face_yaw + PI * 0.5, 1.0 - exp(-delta * 4.0))
	if not stick_down and _held:
		pass
	_held = stick_down
	if player.speed > 0.3:
		var follow := lerp_angle(yaw, player.face_yaw, 1.0 - exp(-delta * 1.6))
		yaw = follow
	var chest := _chest()
	var arm := _arm_dir()
	var desired := chest + arm * want
	var cleared := _clear(chest, desired)
	var want_dist := chest.distance_to(cleared)
	if want_dist < Constants.CAM_MIN_DIST:
		pitch = minf(pitch + delta * 0.6, deg_to_rad(55.0))
		arm = _arm_dir()
		desired = chest + arm * Constants.CAM_MIN_DIST
		cleared = _clear(chest, desired)
		want_dist = chest.distance_to(cleared)
	else:
		pitch = lerpf(pitch, Constants.CAM_PITCH, 1.0 - exp(-delta * 1.5))
	var tau := 0.08 if want_dist < dist else 0.45
	if not stick_down:
		tau = 0.25
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
	global_position = pos
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
	q.collision_mask = Constants.LAYER_GROUND | Constants.LAYER_BLOCK
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
