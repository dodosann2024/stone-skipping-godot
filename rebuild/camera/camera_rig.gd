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
var tight := false
var aim_yaw := 0.0
var _swing_on := false
var _swing_from := 0.0
var _swing_to := 0.0
var _swing_dist_from := 6.0
var _swing_t := 1.0
var _swung_flip := false
var _near_sphere: SphereShape3D


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
		# In front of his face, on the dock centerline, high enough to clear the posts.
		want = 4.4
		yaw = lerp_angle(yaw, player.face_yaw, 1.0 - exp(-delta * 8.0))
	elif framing == "seat" or framing == "lie":
		# Open side of the bench, never through the backrest. 3–4 m, 35° down.
		var goal := 4.0 if framing == "lie" else (2.5 if tight else 3.6)
		if _swing_on:
			_swing_t = minf(_swing_t + delta / 0.7, 1.0)
			var e := _swing_t * _swing_t * (3.0 - 2.0 * _swing_t)
			yaw = lerp_angle(_swing_from, _swing_to, e)
			want = lerpf(_swing_dist_from, goal, e)
			if _swing_t >= 1.0:
				_swing_on = false
				print("CAM_FRONT")
		else:
			want = goal
			yaw = aim_yaw
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
	var rest_view := framing == "seat" or framing == "lie"
	var desired := chest + arm * want
	var want_dist := want
	if not rest_view:
		var cleared := _clear(chest, desired)
		want_dist = maxf(chest.distance_to(cleared), Constants.CAM_MIN_DIST)
	var tau := 0.12 if want_dist < dist - 0.05 else 0.22
	dist = lerpf(dist, want_dist, 1.0 - exp(-delta / tau))
	if not rest_view:
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
	elif framing == "lie":
		look = _lie_look(chest)
	elif framing == "seat":
		look = chest + Vector3(0, 0.22 if tight else 0.08, 0)
	if rest_view:
		# Stay on the open side. A blocker pushes the camera out, not back through the seat.
		pos = _keep_clear(chest, pos)
	else:
		pos = _off_prop(chest, pos)
		pos = _keep_clear(chest, pos)
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


func start_swing(target_yaw: float) -> void:
	aim_yaw = target_yaw
	_swing_from = yaw
	_swing_to = target_yaw
	_swing_dist_from = dist
	_swing_t = 0.0
	_swing_on = true
	_swung_flip = false
	print("CAM_SWING")


func _bench_between(pos: Vector3, chest: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(pos, chest)
	q.collision_mask = Constants.LAYER_BLOCK | Constants.LAYER_PROP
	if player != null:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.has("collider")


func _keep_clear(chest: Vector3, pos: Vector3) -> Vector3:
	# Nothing but the ground and the boy may sit inside 1.2 m of the lens.
	if pos.y < 1.22:
		pos.y = 1.22
	var space := get_world_3d().direct_space_state
	if space == null:
		return pos
	var point := PhysicsPointQueryParameters3D.new()
	point.position = pos
	point.collision_mask = Constants.LAYER_BLOCK | Constants.LAYER_PROP
	if player != null:
		point.exclude = [player.get_rid()]
	if not space.intersect_point(point, 1).is_empty():
		var back := pos - chest
		if back.length_squared() < 0.04:
			back = Vector3(sin(yaw), 0.4, cos(yaw))
		pos = chest + back.normalized() * (back.length() + 1.6)
		pos.y = maxf(pos.y, 1.22)
	for _step in 4:
		var moved := false
		var origin := pos
		var dirs: Array[Vector3] = [chest - origin, Vector3.DOWN, Vector3.UP]
		for i in 8:
			var a := TAU * float(i) / 8.0
			dirs.append(Vector3(cos(a), -0.25, sin(a)))
		for d in dirs:
			if d.length_squared() < 1e-6:
				continue
			var q := PhysicsRayQueryParameters3D.create(origin, origin + d.normalized() * 1.2)
			q.collision_mask = Constants.LAYER_BLOCK | Constants.LAYER_PROP
			if player != null:
				q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.has("position"):
				continue
			var at: Vector3 = hit.position
			var gap := origin.distance_to(at)
			if gap >= 1.15:
				continue
			var n: Vector3 = hit.normal
			if n.length_squared() < 1e-6:
				n = -d.normalized()
			pos = at + n.normalized() * 1.25
			moved = true
			break
		if pos.y < 1.22:
			pos.y = 1.22
		if not moved:
			break
	return pos


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
	var pos: Vector3 = hit.position + n * 0.85
	return pos


func _off_prop(chest: Vector3, pos: Vector3) -> Vector3:
	# Sitting inside a trunk lets the near plane cut it into floating segments.
	var space := get_world_3d().direct_space_state
	if space == null:
		return pos
	var q := PhysicsRayQueryParameters3D.create(pos, chest)
	q.collision_mask = Constants.LAYER_BLOCK | Constants.LAYER_PROP
	if player != null:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.has("position"):
		return pos
	var at: Vector3 = hit.position
	if pos.distance_to(at) > 0.75:
		return pos
	var n := hit.normal as Vector3
	if n.length_squared() < 1e-6:
		n = (pos - chest).normalized()
	return at + n.normalized() * 0.9


func _lie_yaw() -> float:
	var along := _body_along()
	if along.length_squared() < 0.04:
		return player.face_yaw + PI * 0.5
	# Camera sits to the side of the body, on the +Z side of that axis.
	var side := Vector3(-along.z, 0, along.x).normalized()
	if side.z < 0.0:
		side = -side
	return atan2(side.x, side.z)


func _lie_look(chest: Vector3) -> Vector3:
	var ends := _body_ends()
	if ends.is_empty():
		return chest
	return ((ends[0] + ends[1]) * 0.5) + Vector3(0, 0.28, 0)


func _body_along() -> Vector3:
	var ends := _body_ends()
	if ends.size() < 2:
		return Vector3.ZERO
	var flat: Vector3 = ends[1] - ends[0]
	flat.y = 0.0
	return flat


func _body_ends() -> Array[Vector3]:
	if player.boy == null or player.boy.skel == null:
		return []
	var skel: Skeleton3D = player.boy.skel
	var head := skel.find_bone("mixamorig_Head")
	var foot := skel.find_bone("mixamorig_LeftFoot")
	if head < 0 or foot < 0:
		return []
	var h: Vector3 = (skel.global_transform * skel.get_bone_global_pose(head)).origin
	var f: Vector3 = (skel.global_transform * skel.get_bone_global_pose(foot)).origin
	return [h, f]
