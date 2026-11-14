extends SceneTree
## Exact CDP sequence (390×844) as InputEvents against the running game:
##   tap (195,420) → touchStart (54,754) → 10 moves up+right over 300 ms → hold.
## Places the boy on the forest grass slope first, then asserts no burial.
##   godot --path . --fixed-fps 30 -s res://dev/touch_cdp_v35.gd

const MAX_MESH_SINK := 0.04
const MAX_FOOT_SINK := 0.090  # walk clip toe dips; mesh sink is the burial signal
const OUT := "screenshots/v35"

var m: Node
var fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _fail(msg: String) -> void:
	fails.append(msg)
	print("CDP FAIL  ", msg)


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


func _mesh_sink() -> float:
	var mesh: float = m._surface(m.player.position.x, m.player.position.z)
	var worst := 0.0
	for node in m.boy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var nm: String = str(mi.name).to_lower()
		if nm.contains("blob") or nm.contains("hat") or nm.contains("stone") or nm.contains("glass") or nm.contains("scalp"):
			continue
		var ga: AABB = mi.global_transform * mi.get_aabb()
		worst = maxf(worst, mesh - ga.position.y)
	return worst


func _foot_sink() -> float:
	var mesh: float = m._surface(m.player.position.x, m.player.position.z)
	var worst := 0.0
	for side in range(2):
		for pt in m.boy.foot_points(side):
			worst = maxf(worst, mesh - float(pt.y))
	return worst


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	DisplayServer.window_set_size(Vector2i(390, 844))
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 45:
		await process_frame

	# Forest slope near spawn climb (matches live CDP burial site).
	var xz := Vector2(2.6, m.island.dock_start_z + 6.5)
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = -0.4
	m.player.rotation.y = -0.4
	for _i in 20:
		await process_frame

	# Tap (195,420)
	_touch(1, Vector2(195, 420), true)
	await process_frame
	_touch(1, Vector2(195, 420), false)
	await process_frame
	await process_frame

	# touchStart joystick (54,754), 10 moves up+right over ~300 ms (≈9 frames @30fps)
	var x0 := 54.0
	var y0 := 754.0
	_touch(0, Vector2(x0, y0), true)
	await process_frame
	var prev := Vector2(x0, y0)
	for i in 10:
		var t: float = float(i + 1) / 10.0
		var pos := Vector2(x0 + t * 40.0, y0 - t * 70.0)
		_drag(0, pos, pos - prev)
		prev = pos
		await process_frame  # ~33 ms each → ~330 ms total

	# Hold through 0.6 s mark from drag start (~18 frames from start; ~8 more)
	var max_mesh := 0.0
	var max_foot := 0.0
	for i in 12:
		_drag(0, prev, Vector2.ZERO)
		await process_frame
		max_mesh = maxf(max_mesh, _mesh_sink())
		max_foot = maxf(max_foot, _foot_sink())
		if _mesh_sink() > MAX_MESH_SINK:
			_fail("mesh sink %.1f cm at hold frame %d" % [_mesh_sink() * 100.0, i])
		if _foot_sink() > MAX_FOOT_SINK:
			_fail("foot sink %.1f cm at hold frame %d" % [_foot_sink() * 100.0, i])

	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png("%s/cdp_godot_drag_0p6.png" % OUT)
	print("SHOT cdp_godot_drag_0p6 mesh_sink=%.1fcm foot_sink=%.1fcm sole_nudge=%.3f" % [
		max_mesh * 100.0, max_foot * 100.0, Boy.SOLE_NUDGE])

	_touch(0, prev, false)
	for _i in 15:
		await process_frame

	print("CDP_SEQ max_mesh=%.1fcm max_foot=%.1fcm" % [max_mesh * 100.0, max_foot * 100.0])
	if fails.is_empty():
		print("CDP_SEQ PASS")
		quit(0)
	else:
		print("CDP_SEQ FAILED (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		quit(1)
