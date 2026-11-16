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
var _was_looking := false
var _drag_ms := 0
var _ahead_for := 0.0


func _ready() -> void:
	# The eye is placed every render frame from the interpolated body.
	# An interpolated Camera3D warns if that write happens outside the physics
	# tick, and interpolating it again would smooth the camera twice.
	# The documented path is to turn interpolation off on this camera and
	# drive it from the body's already-interpolated transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 48.0
	cam.near = 0.12
	add_child(cam)


func note_drag() -> void:
	_drag_ms = Time.get_ticks_msec()
	looking = true
	_ahead_for = 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	# A drag that stopped without a touch-end is a release. Otherwise the
	# orbit sticks and the next walk runs off the boards.
	if looking and _drag_ms > 0 and Time.get_ticks_msec() - _drag_ms > 380:
		looking = false
	if _was_looking and not looking:
		# Long enough that the orbit frame, taken after the finger lifts, already shows the path.
		_ahead_for = 4.2
	_was_looking = looking
	if looking:
		_ahead_for = 0.0
	var want := Constants.CAM_DIST
	var ahead := _ahead_for > 0.0 and not looking and framing == ""
	if ahead:
		_ahead_for = maxf(_ahead_for - delta, 0.0)
	if framing == "front":
		want = 4.6
		yaw = lerp_angle(yaw, player.face_yaw + PI, 1.0 - exp(-delta * 5.0))
	elif framing == "side":
		want = 5.2
		yaw = lerp_angle(yaw, player.face_yaw + PI * 0.5, 1.0 - exp(-delta * 5.0))
	elif framing == "throw":
		# Just behind him, looking along the throw. The portrait field is narrow,
		# so a bigger side angle puts the stone out of the frame.
		want = 5.4
		yaw = lerp_angle(yaw, player.face_yaw + 0.12, 1.0 - exp(-delta * 8.0))
	elif ahead:
		yaw = lerp_angle(yaw, _ahead_yaw(), 1.0 - exp(-delta * 5.5))
	elif follow and not looking and player.speed > 0.25:
		var err := absf(angle_difference(yaw, player.face_yaw))
		var rate := lerpf(2.4, 7.0, clampf(err / 1.1, 0.0, 1.0))
		yaw = lerp_angle(yaw, player.face_yaw, 1.0 - exp(-delta * rate))
	# While a finger is orbiting, the drag owns the pitch. Easing back to 35
	# in the same frame eats the drag.
	if not looking:
		var pitch_goal := deg_to_rad(40.0) if hold_pitch else Constants.CAM_PITCH
		pitch = lerpf(pitch, pitch_goal, 1.0 - exp(-delta * 2.2))
	pitch = clampf(pitch, deg_to_rad(30.0), deg_to_rad(40.0))
	var chest := _chest()
	var arm := _arm_dir()
	var desired := chest + arm * want
	var cleared := _clear(chest, desired)
	var want_dist := maxf(chest.distance_to(cleared), Constants.CAM_MIN_DIST)
	var tau := 0.12 if want_dist < dist - 0.05 else 0.22
	dist = lerpf(dist, want_dist, 1.0 - exp(-delta / tau))
	dist = maxf(dist, Constants.CAM_MIN_DIST)
	var pos := chest + arm * dist
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
	if ahead:
		pos = _frame_path(chest, pos)
	var look := chest
	if ahead:
		look = _path_look(chest)
	pos = _outside_boy(chest, pos)
	# The Camera3D stays at the rig origin. A leftover local offset is how the
	# eye ended up inside the hat.
	cam.position = Vector3.ZERO
	cam.rotation = Vector3.ZERO
	global_position = pos
	look_at(look, Vector3.UP)
	player.cam_basis = global_transform.basis


func _chest() -> Vector3:
	var p := player.global_position
	if player.is_physics_interpolated():
		p = player.get_global_transform_interpolated().origin
	return p + Vector3(0, pivot_y, 0)


func _on_path() -> bool:
	var ends := IslandData.dock_ends()
	var p := player.global_position
	return absf(p.x) < 4.2 and p.z > ends.y - 1.2 and p.z < ends.x + 12.0


func _ahead_yaw() -> float:
	# On the dock the way ahead is inland (+Z). Camera sits on the sea side of the boy.
	if _on_path():
		return PI
	return player.face_yaw


func _frame_path(chest: Vector3, pos: Vector3) -> Vector3:
	if not _on_path():
		return pos
	# Stand off toward the side he is already on, so the planks ahead
	# sit in the middle instead of the water beside the lip.
	var side := clampf(player.global_position.x, -1.5, 1.5)
	pos.x += side * 0.85
	return pos


func _path_look(chest: Vector3) -> Vector3:
	if not _on_path():
		return chest
	var p := player.global_position
	return Vector3(lerpf(chest.x, 0.0, 0.7), chest.y, p.z + 2.2)


func _outside_boy(chest: Vector3, pos: Vector3) -> Vector3:
	var away := pos - chest
	if away.length() < Constants.CAM_MIN_DIST:
		if away.length_squared() < 1e-6:
			away = _arm_dir()
		pos = chest + away.normalized() * Constants.CAM_MIN_DIST
	# Hat and shoulders. The portrait field crops the head if the eye is this close.
	var head := chest + Vector3(0, 0.42, 0)
	var from_head := pos - head
	var keep := 1.55
	if from_head.length() < keep:
		if from_head.length_squared() < 1e-6:
			from_head = _arm_dir()
		pos = head + from_head.normalized() * keep
	away = pos - chest
	if away.length() < Constants.CAM_MIN_DIST:
		if away.length_squared() < 1e-6:
			away = _arm_dir()
		pos = chest + away.normalized() * Constants.CAM_MIN_DIST
	return pos


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
