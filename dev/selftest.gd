extends RefCounted
## Regression check: every action (hammock, towel, dock throw + cheer / oops, view mode) must hand control
## back - afterwards the joystick has to move the kid and the walk animation has to play.
## godot --headless --path . --fixed-fps 30 -- --selftest      (exit code 0 = pass)

var m: Node
var fails: Array[String] = []

func _frames(n: int) -> void:
	for i in n:
		await m.get_tree().process_frame

func _wait(sec: float) -> void:
	await _frames(int(ceil(sec * 30.0)))

func _until(cond: Callable, timeout: float) -> bool:
	var n := int(timeout * 30.0)
	for i in n:
		if cond.call():
			return true
		await m.get_tree().process_frame
	return false

func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	m.get_viewport().push_input(e, true)

func _drag(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	m.get_viewport().push_input(e, true)

## push the on-screen stick (real touch events, like a phone) in four directions;
## the kid has to get somewhere and the walk cycle has to run
func _can_walk(tag: String) -> void:
	var best := 0.0
	var saw_move := false
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var c := Vector2(vs.x * 0.14, vs.y * 0.86)
	m.demo_mode = false
	for dir: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var p0: Vector3 = m.player.position
		_touch(c, true)
		await _frames(1)
		_drag(c + dir * 55.0, dir * 55.0)
		for i in 24:
			await m.get_tree().process_frame
			if m.boy.anim == "move":
				saw_move = true
		_touch(c + dir * 55.0, false)
		await _frames(12)
		best = maxf(best, Vector2(m.player.position.x - p0.x, m.player.position.z - p0.z).length())
	m.demo_mode = true
	var ok: bool = best > 0.35 and saw_move and m.mode == m.Mode.EXPLORE
	print("SELFTEST %-28s %s  (moved %.2f m, walk anim %s, mode %d)" % [tag, "ok" if ok else "FAIL", best, saw_move, m.mode])
	if not ok:
		fails.append(tag)

func _rest(kind: String, approach: Vector3) -> void:
	m._place(approach, 0.0)
	await _frames(5)
	m._begin_rest(kind)
	if not await _until(func() -> bool: return m.rest_phase == 4, 12.0):
		fails.append(kind + " never lay down")
		return
	await _wait(1.0)
	m._wake()
	if not await _until(func() -> bool: return m.mode == m.Mode.EXPLORE, 6.0):
		fails.append(kind + " never got up")
		return
	await _frames(3)
	await _can_walk("after " + kind + " from " + str(approach.snapped(Vector3.ONE * 0.1)))

func run(main: Node) -> void:
	m = main
	await _wait(0.5)
	await _can_walk("start")
	# towel: from both sides and from the sea end
	var td: Vector3 = m.island.towel_dir
	var sd: Vector3 = td.cross(Vector3.UP).normalized()
	for off: Vector3 in [sd * 1.4, -sd * 1.4, td * 1.6, -td * 1.8]:
		await _rest("sun", m.island.towel_pos + off)
	# hammock: both sides
	var hs: Array = m._hammock_spot()
	for s: float in [1.6, -1.6]:
		await _rest("sleep", hs[0] + hs[2] * s)
	# dock: throw (cheer / oops), throw from the half-crouch, then leave
	for crouch: bool in [false, true]:
		m._place(Vector3(0.3, 0, m.island.dock_end_z + 1.6), 0.1)
		await _frames(5)
		m._enter_throw()
		await _wait(1.2)
		m.boy.stance = "crouch" if crouch else "stand"
		for power: float in [0.9, 0.05]:
			m._begin_aim(Vector2.ZERO)
			m.aim_pitch = 3.0
			m.charge_t = power * m.POWER_CYCLE * 0.5
			await _frames(4)
			m._throw()
			if not await _until(func() -> bool: return m.state == m.State.READY, 20.0):
				fails.append("throw never finished")
				return
			await _wait(3.2)
		m._leave_throw()
		await _frames(3)
		await _can_walk("after dock throw" + (" (crouch)" if crouch else ""))
	# entering and leaving the dock without throwing
	m._place(Vector3(-0.3, 0, m.island.dock_end_z + 1.6), 0.1)
	m._enter_throw()
	await _wait(0.2)
	m._leave_throw()
	await _wait(1.5)
	m._leave_throw()
	await _can_walk("after dock enter/leave")
	m._toggle_view()
	await _wait(0.8)
	m._toggle_view()
	await _can_walk("after view mode")
	print("SELFTEST %s" % ("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
	m.get_tree().quit(0 if fails.is_empty() else 1)
