extends SceneTree
## Inject real ScreenTouch/ScreenDrag on the joystick and assert:
##   - motion within 2 frames of drag past deadzone
##   - foot vs mesh_h < 3 cm every frame WHILE dragging
## godot --headless --path . --fixed-fps 60 -s res://dev/touch_joy_v33.gd

const MAX_LATENCY_FRAMES := 2
const MAX_FOOT_ERR := 0.03

var m: Node
var fails: Array[String] = []


func _fail(msg: String) -> void:
	fails.append(msg)
	print("TOUCH FAIL  ", msg)


func _initialize() -> void:
	call_deferred("_go")


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	m.get_viewport().push_input(e, true)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	m.get_viewport().push_input(e, true)


func _joy_center() -> Vector2:
	# Rest knob in joy control local space → viewport.
	var local: Vector2 = m.joy._rest_pos()
	return m.joy.global_position + local


func _min_foot_err() -> float:
	var p: Vector3 = m.player.global_position
	var mesh: float = m._surface(p.x, p.z)
	var best := 1e9
	for side in [0, 1]:
		var fp: Array = m.boy.foot_points(side)
		for pt in fp:
			best = minf(best, absf(float(pt.y) - mesh))
	# Also root vs mesh (display Y after interp).
	best = minf(best, absf(p.y - mesh))
	return best


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	m.cam_fixed = false
	for _i in 45:
		await process_frame

	var c := _joy_center()
	var p0: Vector3 = m.player.global_position
	# Press on the stick, then drag upward (forward) past deadzone.
	_touch(0, c, true)
	await process_frame
	# Drag in several steps like a real thumb.
	var tip := c + Vector2(0, -55.0)
	_drag(0, c + Vector2(0, -20), Vector2(0, -20))
	await process_frame
	_drag(0, tip, Vector2(0, -35))

	var moved_frame := -1
	var max_foot := 0.0
	var max_root := 0.0
	for i in 90:
		await process_frame
		# Keep the finger held — re-assert drag position (some hosts need it).
		if i % 5 == 0:
			_drag(0, tip, Vector2.ZERO)
		var p: Vector3 = m.player.global_position
		var dxz := Vector2(p.x - p0.x, p.z - p0.z).length()
		if moved_frame < 0 and (dxz > 0.02 or m.cur_speed > 0.08):
			moved_frame = i
		var mesh: float = m._surface(p.x, p.z)
		max_root = maxf(max_root, absf(p.y - mesh))
		max_foot = maxf(max_foot, _min_foot_err())
		if absf(p.y - mesh) > MAX_FOOT_ERR:
			_fail("root buried/float %.3f m at frame %d" % [p.y - mesh, i])
		# lowest foot should stay near ground (use signed: foot_y - mesh)
		for side in [0, 1]:
			for pt in m.boy.foot_points(side):
				var fe: float = float(pt.y) - mesh
				if fe < -MAX_FOOT_ERR:
					_fail("foot sunk %.3f m side=%d frame=%d" % [fe, side, i])

	_touch(0, tip, false)
	for _j in 20:
		await process_frame

	print("TOUCH latency_frames=%d joy_val=%s speed=%.2f max_root_err=%.4f max_foot_err=%.4f spot=%s" % [
		moved_frame, str(m.joy.value), m.cur_speed, max_root, max_foot, m.spot_turning])

	if moved_frame < 0:
		_fail("never moved while dragging")
	elif moved_frame > MAX_LATENCY_FRAMES:
		_fail("input-to-motion latency %d frames > %d" % [moved_frame, MAX_LATENCY_FRAMES])
	if max_root > MAX_FOOT_ERR:
		_fail("max root err %.3f > %.3f" % [max_root, MAX_FOOT_ERR])

	if fails.is_empty():
		print("TOUCH PASS")
		quit(0)
	else:
		print("TOUCH FAILED (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		quit(1)
