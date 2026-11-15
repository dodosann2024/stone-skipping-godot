class_name PlayerBody
extends CharacterBody3D
## The only writer of the root. Display uses this node's transform.

signal stepped(kind: String)

var ground: Ground
var boy: BoyVisual
var stick := Vector2.ZERO
var speed := 0.0
var running := false
var face_yaw := PI
var cam_basis := Basis.IDENTITY
var route := false
var route_m := 0.0
var _route_i := 0
var _route_pts: Array[Vector2] = []
var _frames := 0
var _step_cd := 0.0
var _route_closed := false
var _scored := 0
var _ok := 0
var _hist := {}
var _skate_max := 0.0
var _shin_min := 1.0
var contact_y := 0.0
var _walk_skate := 0.0
var _last_route_m := 0.0


func _ready() -> void:
	collision_layer = Constants.LAYER_PLAYER
	collision_mask = Constants.LAYER_GROUND | Constants.LAYER_BLOCK | Constants.LAYER_PROP
	floor_snap_length = 0.28
	floor_max_angle = deg_to_rad(50.0)
	floor_block_on_wall = false
	floor_constant_speed = true
	motion_mode = MOTION_MODE_GROUNDED
	var shape := CapsuleShape3D.new()
	shape.radius = 0.16
	shape.height = 1.05
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)
	boy = BoyVisual.new()
	add_child(boy)
	rotation.y = face_yaw
	route = OS.get_environment("R42_ROUTE") == "1"


func _physics_process(delta: float) -> void:
	if ground == null:
		return
	var inp := stick
	if route:
		inp = _route_stick()
	_move(inp, delta)
	if boy != null:
		boy.set_speed(speed)
	_frames += 1
	if route and _frames % 300 == 0:
		var w0 := 0.0
		var w1 := 0.0
		var g0 := 0.0
		var g1 := 0.0
		if boy != null and boy.ik != null:
			w0 = boy.ik.weight[0]
			w1 = boy.ik.weight[1]
			g0 = boy.ik.sole_gap[0] * 100.0
			g1 = boy.ik.sole_gap[1] * 100.0
		print("ROUTE_POS f=%d m=%.1f y=%.2f spd=%.2f w=%.2f/%.2f gap=%.1f/%.1f scored=%d" % [
			_frames, route_m, global_position.y, speed, w0, w1, g0, g1, _scored])
	if route and not _route_closed and route_m >= 110.0 and _frames > 30:
		_route_closed = true
		_route_finish()


func _move(inp: Vector2, delta: float) -> void:
	var mag := inp.length()
	if mag >= Constants.RUN_ON or (running and mag >= Constants.RUN_OFF):
		running = mag >= Constants.RUN_OFF
	else:
		running = false
	var wish := Vector3.ZERO
	if mag > Constants.DEADZONE:
		var m := (mag - Constants.DEADZONE) / (1.0 - Constants.DEADZONE)
		m = pow(clampf(m, 0.0, 1.0), 0.85)
		var fwd := -cam_basis.z
		fwd.y = 0.0
		fwd = Vector3(0, 0, 1) if fwd.length_squared() < 1e-6 else fwd.normalized()
		var right := cam_basis.x
		right.y = 0.0
		right = right.normalized()
		wish = (right * inp.x + fwd * (-inp.y)).normalized()
		var target_yaw := atan2(-wish.x, -wish.z)
		face_yaw = lerp_angle(face_yaw, target_yaw, 1.0 - exp(-delta * Constants.TURN_RATE))
		wish = Vector3(-sin(face_yaw), 0, -cos(face_yaw)) * m
	var target := wish.length() * (Constants.RUN_SPEED if running else Constants.WALK_SPEED)
	var smooth := Constants.BRAKE_S
	if target > speed:
		smooth = Constants.FIRST_STEP_S if speed < 0.50 else Constants.ACCEL_S
	speed = lerpf(speed, target, 1.0 - exp(-delta / smooth))
	if target < 0.02 and speed < 0.04:
		speed = 0.0
	var dir := Vector3(-sin(face_yaw), 0, -cos(face_yaw))
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 9.8 * delta
	var before := global_position
	move_and_slide()
	contact_y = global_position.y + Constants.CAPSULE_BOTTOM
	if boy != null and boy.ik != null:
		boy.ik.contact_y = contact_y
	if not is_on_floor() and ground != null:
		var h := ground.height(global_position.x, global_position.z)
		if global_position.y < h - 0.08 and h > Constants.WADE_MIN_Y:
			global_position.y = h
			velocity.y = 0.0
	rotation.y = face_yaw
	var stepped_m := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if route:
		route_m += stepped_m
		_score_feet()
	_step_cd -= delta
	if speed > 0.2 and _step_cd <= 0.0 and boy != null and boy.ik != null:
		var planted := boy.ik.weight[0] > 0.9 or boy.ik.weight[1] > 0.9
		if planted:
			_step_cd = 0.34 if speed < 1.5 else 0.24
			var kind := IslandData.surface_kind(global_position.x, global_position.z, global_position.y)
			emit_signal("stepped", kind)


func _route_stick() -> Vector2:
	if _route_pts.is_empty():
		var ends := IslandData.dock_ends()
		_route_pts = [
			Vector2(0.2, ends.x + 4.0),
			Vector2(4.0, ends.x + 6.0),
			Vector2(6.0, -2.0),
			Vector2(2.0, 4.0),
			Vector2(-6.0, 2.0),
			Vector2(-6.0, ends.x + 5.0),
			Vector2(0.3, ends.x + 5.0),
		]
	if _frames > 90 and _frames % 45 == 0 and route_m - _last_route_m < 0.15:
		_route_i += 1
	if _frames % 45 == 0:
		_last_route_m = route_m
	var goal: Vector2 = _route_pts[_route_i % _route_pts.size()]
	var here := Vector2(global_position.x, global_position.z)
	if here.distance_to(goal) < 1.2:
		_route_i += 1
		goal = _route_pts[_route_i % _route_pts.size()]
	var dir := goal - here
	if dir.length() < 0.05:
		return Vector2.ZERO
	dir = dir.normalized()
	var fwd := -cam_basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, 1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var world := Vector3(dir.x, 0, dir.y)
	var sx := world.dot(right)
	var sy := -world.dot(fwd)
	var stick_out := Vector2(sx, sy).limit_length(1.0)
	if route_m < 25.0:
		return stick_out * 0.85
	return stick_out


func _score_feet() -> void:
	if boy == null or boy.ik == null or _frames < 40:
		return
	var ik := boy.ik
	_shin_min = minf(_shin_min, minf(ik.shin_ratio[0], ik.shin_ratio[1]))
	_skate_max = maxf(_skate_max, ik.skate_m)
	if not running:
		_walk_skate = maxf(_walk_skate, ik.skate_m)
	for side in 2:
		if ik.weight[side] < 0.98:
			continue
		_scored += 1
		var cm := ik.sole_gap[side] * 100.0
		var bin := int(floor(cm))
		_hist[bin] = int(_hist.get(bin, 0)) + 1
		if cm >= -1.0 and cm <= 1.0:
			_ok += 1


func _route_finish() -> void:
	var hist := ""
	var keys: Array = _hist.keys()
	keys.sort()
	for k in keys:
		hist += "%d:%d " % [int(k), int(_hist[k])]
	var pct := 100.0 * float(_ok) / maxf(float(_scored), 1.0)
	print("ROUTE_HIST %s" % hist)
	print("ROUTE_DONE m=%.1f stance=%d in_1cm=%.1f skate_max_cm=%.2f walk_skate_cm=%.2f shin_min=%.2f" % [
		route_m, _scored, pct, _skate_max * 100.0, _walk_skate * 100.0, _shin_min])
	get_tree().quit()
