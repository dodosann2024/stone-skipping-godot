class_name FollowCamera
extends RefCounted
## Explore / rest / throw / orbit camera. Runs after FootIK so framing
## uses the posed head and feet. State stays on main; this file owns the math.
var m: Node

func setup(p_main: Node) -> void:
	m = p_main


func _begin_cam_blend() -> void:
	m._cam_blend_from_t = m.cam_target
	m._cam_blend_from_yaw = m.cam_yaw
	m._cam_blend_from_pitch = m.cam_pitch
	m._cam_blend_from_dist = m.cam_dist
	m._cam_blend_t = m._cam_blend_dur



func _explore_cam_input(event: InputEvent) -> void:
	# ScreenTouch/ScreenDrag only (not emulated mouse). Joystick finger never orbits.
	if event is InputEventScreenTouch:
		var e = event as InputEventScreenTouch
		if m._is_joy_finger(e.index) or (e.pressed and m._touch_on_joystick(e.position)):
			return
		if e.pressed:
			m.touches[e.index] = e.position
		else:
			m.touches.erase(e.index)
		m.dragging = m.touches.size() > 0
		if m.touches.size() == 2:
			var ps: Array = m.touches.values()
			m.pinch_d = (ps[0] - ps[1]).length()
	elif event is InputEventScreenDrag:
		var d_ev = event as InputEventScreenDrag
		if m._is_joy_finger(d_ev.index):
			return
		# Don't start a camera drag that began on the stick pad.
		if not m.touches.has(d_ev.index) and m._touch_on_joystick(d_ev.position):
			return
		var prev: Vector2 = m.touches.get(d_ev.index, d_ev.position)
		m.touches[d_ev.index] = d_ev.position
		if m.touches.size() == 1:
			_explore_orbit(d_ev.position - prev)
		elif m.touches.size() >= 2:
			var ps: Array = m.touches.values()
			var d: float = (ps[0] - ps[1]).length()
			if m.pinch_d > 1.0 and d > 1.0:
				m.zoom_pending *= m.pinch_d / d
			m.pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			m.mouse_drag = event.pressed
			m.dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_nudge_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_nudge_zoom(1.11)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and m.mouse_drag:
		_explore_orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		_nudge_zoom(1.0 / maxf(event.factor, 0.05))


func _explore_orbit(rel: Vector2) -> void:
	var vs = m.get_viewport().get_visible_rect().size
	var k: float = 5.0 / max(min(vs.x, vs.y), 200.0)
	# Accumulate; applied once in _update_camera so multi-event ProMotion frames don't stutter.
	m.orbit_pending += Vector2(-rel.x * k, rel.y * k * 0.6)
	m.orbit_vel = Vector2(-rel.x * k * 12.0, rel.y * k * 8.0)
	if m.mode == 3:
		m.rest_touch_dragged = true
	m.last_drag = m.gt




func _flush_orbit_pending() -> void:
	if m.orbit_pending.length_squared() < 1e-12 and absf(m.zoom_pending - 1.0) < 1e-6:
		m._orbit_ease = move_toward(m._orbit_ease, 0.0, 0.35)
		m._orbit_smooth = m._orbit_smooth.lerp(Vector2.ZERO, 0.35)
		return
	# Light 1-exp smoothing on drag; no long ease-in lag (orbit feels direct).
	m._orbit_ease = 1.0
	m._orbit_smooth = m._orbit_smooth.lerp(m.orbit_pending, 1.0 - exp(-12.0 * maxf(m.get_process_delta_time(), 1.0 / 120.0)))
	var dy = m._orbit_smooth.x
	var dp = m._orbit_smooth.y
	m.orbit_pending = Vector2.ZERO
	m._orbit_smooth = Vector2.ZERO
	# Keep live cam angles in lockstep with the orbit targets (no lag→spike).
	if m.cam_fixed:
		m.fix_yaw += dy
		m.fix_pitch = clampf(m.fix_pitch + dp, 0.06, 1.35)
		m.cam_yaw = m.fix_yaw
		m.cam_pitch = m.fix_pitch
	elif m.mode == 3:
		m.rest_cam_yaw += dy
		m.rest_cam_pitch = clampf(m.rest_cam_pitch + dp, 0.06, 1.15)
		m.cam_yaw = m.rest_cam_yaw
		m.cam_pitch = m.rest_cam_pitch
	elif m.mode == 2:
		m.view_yaw += dy
		m.view_pitch = clamp(m.view_pitch + dp, 0.06, 1.42)
		m.cam_yaw = m.view_yaw
		m.cam_pitch = m.view_pitch
	else:
		m.ex_yaw += dy
		m.ex_pitch = clamp(m.ex_pitch + dp, 0.05, 1.25)
		m.cam_yaw = m.ex_yaw
		m.cam_pitch = m.ex_pitch
	if absf(m.zoom_pending - 1.0) > 1e-6:
		var z = m.zoom_pending
		m.zoom_pending = 1.0
		if m.cam_fixed:
			m.fix_dist = clampf(m.fix_dist * z, 2.5, 28.0)
			m.cam_dist = m.fix_dist
		elif m.mode == 3:
			m.rest_cam_dist = clampf(m.rest_cam_dist * z, 1.6, 7.5)
			m.cam_dist *= z
		elif m.mode == 2:
			m.view_dist = clamp(m.view_dist * z, 4.0, 95.0)
			m.cam_dist = m.view_dist
		else:
			m.ex_dist = clamp(m.ex_dist * z, 3.0, 14.0)
			m.cam_dist = m.ex_dist


## Orbit / zoom while sitting or sleeping; a tap with no drag still stands up.

func _rest_cam_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			m.touches[event.index] = event.position
			if m.touches.size() == 1:
				m.rest_touch_dragged = false
		else:
			var was_drag = m.rest_touch_dragged
			m.touches.erase(event.index)
			m.dragging = m.touches.size() > 0
			if m.touches.is_empty() and not was_drag:
				m._wake()
			return
		m.dragging = m.touches.size() > 0
		if m.touches.size() == 2:
			var ps: Array = m.touches.values()
			m.pinch_d = (ps[0] - ps[1]).length()
	elif event is InputEventScreenDrag:
		var prev: Vector2 = m.touches.get(event.index, event.position)
		m.touches[event.index] = event.position
		if m.touches.size() == 1:
			if (event.position - prev).length() > 2.0:
				m.rest_touch_dragged = true
			_explore_orbit(event.position - prev)
		elif m.touches.size() >= 2:
			m.rest_touch_dragged = true
			var ps2: Array = m.touches.values()
			var d: float = (ps2[0] - ps2[1]).length()
			if m.pinch_d > 1.0 and d > 1.0:
				m.rest_cam_dist = clampf(m.rest_cam_dist * m.pinch_d / d, 1.6, 7.5)
			m.pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			m.mouse_drag = event.pressed
			m.dragging = event.pressed
			if event.pressed:
				m.rest_touch_dragged = false
			elif not m.rest_touch_dragged:
				m._wake()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			m.rest_cam_dist = clampf(m.rest_cam_dist * 0.9, 1.6, 7.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			m.rest_cam_dist = clampf(m.rest_cam_dist * 1.11, 1.6, 7.5)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and m.mouse_drag:
		if event.relative.length() > 1.0:
			m.rest_touch_dragged = true
		_explore_orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		m.rest_cam_dist = clampf(m.rest_cam_dist / maxf(event.factor, 0.05), 1.6, 7.5)


func _view_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			m.touches[event.index] = event.position
			m.orbit_vel = Vector2.ZERO
		else:
			m.touches.erase(event.index)
		if m.touches.size() == 2:
			var ps: Array = m.touches.values()
			m.pinch_d = (ps[0] - ps[1]).length()
		m.dragging = m.touches.size() > 0
	elif event is InputEventScreenDrag:
		var prev: Vector2 = m.touches.get(event.index, event.position)
		m.touches[event.index] = event.position
		if m.touches.size() == 1:
			_orbit_by(event.position - prev)
		elif m.touches.size() >= 2:
			var ps: Array = m.touches.values()
			var d: float = (ps[0] - ps[1]).length()
			if m.pinch_d > 1.0 and d > 1.0:
				m.view_dist = clamp(m.view_dist * m.pinch_d / d, 4.0, 95.0)
			m.pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			m.mouse_drag = event.pressed
			m.dragging = event.pressed
			if event.pressed:
				m.orbit_vel = Vector2.ZERO
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			m.view_dist = clamp(m.view_dist * 0.88, 4.0, 95.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			m.view_dist = clamp(m.view_dist * 1.13, 4.0, 95.0)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and m.mouse_drag:
		_orbit_by(event.relative)
	elif event is InputEventMagnifyGesture:
		m.view_dist = clamp(m.view_dist / event.factor, 4.0, 95.0)


func _orbit_by(rel: Vector2) -> void:
	var vs = m.get_viewport().get_visible_rect().size
	var k: float = 5.0 / max(min(vs.x, vs.y), 200.0)
	var dy: float = -rel.x * k
	var dp: float = rel.y * k * 0.7
	m.view_yaw += dy
	m.view_pitch = clamp(m.view_pitch + dp, 0.06, 1.42)
	var dt: float = max(m.get_process_delta_time(), 1.0 / 120.0)
	m.orbit_vel = m.orbit_vel.lerp(Vector2(dy, dp) / dt, 0.5)

## Throwing on a phone: put a finger down (on the stone pad, or anywhere that is not a button) and swipe out
## towards the sea - the swipe's direction on screen is the aim, its length the power; letting go throws, and
## the speed of the finger as it lets go is the spin (a flick spins the stone, a slow release barely does).
## Swiping back towards the kid cancels. Desktop: the same with the mouse, or keys (see _throw_keys).

func _throw_cam() -> Array:
	var tall = m._tall()
	var dir = Vector3(0, 0, -1).rotated(Vector3.UP, m.cam_aim_yaw)
	var h = m._ideal_hand(m.cam_aim_yaw)
	# look at a point on the aim line `ahead` m out, from `back` m behind the hand and `high` m up
	var ahead = 7.0 if tall else 9.0
	var back = 4.0 if tall else 4.6
	var high = 2.6 if tall else 2.5
	var t = Vector3(h.x, 0.6, h.z) + dir * ahead
	return [t, m.cam_aim_yaw, atan2(high - 0.6, ahead + back), Vector2(ahead + back, high - 0.6).length()]

## the chest turns to the aim first and the hips and feet follow; once the swing starts they square up fast

func _explore_cam() -> Array:
	var tall = m._tall()
	# One frame for walk, run, turn and idle. A speed-scaled look-ahead used to
	# collapse on stick release and the hat went through the top of the screen.
	# Look at the neck so the face stays in frame and the feet stay in frame.
	var hy = 1.18 if m.boy.meta.get("tripo", false) else 1.06
	var base = m.player.global_position + Vector3(0, hy, 0)
	var ahead_dir = Vector3(-sin(m.face_yaw), 0.0, -cos(m.face_yaw))
	var ahead_m = 0.10
	var t = base + ahead_dir * ahead_m
	# ex_dist is the user zoom preference. The floor is the default whole-body
	# frame; release eases back to this, it does not dolly in.
	var zoom = clampf(m.ex_dist, 3.0, 14.0)
	var dist = maxf(zoom, 6.70 if tall else 6.35)
	var pitch = clampf(m.ex_pitch, 0.28, 0.36)
	var gx = m.player.global_position.x
	var gz = m.player.global_position.z
	var ahead_p = m.player.global_position + ahead_dir * 1.2
	var grade = m._surface(ahead_p.x, ahead_p.z) - m._surface(gx, gz)
	if grade > 0.12:
		dist = maxf(dist, 6.30)
		t.y += clampf(grade * 0.12, 0.0, 0.20)
	return [t, m.ex_yaw, pitch, dist]


## Critically damped spring (Game Programming Gems / Ryan Juckett).
## Returns [new_value, new_velocity].

func _crit_damp(current: float, target: float, vel: float, smooth_time: float, dt: float) -> Array:
	smooth_time = maxf(0.0001, smooth_time)
	var omega = 2.0 / smooth_time
	var x = omega * dt
	var exp_x = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change = current - target
	var temp = (vel + omega * change) * dt
	var new_vel = (vel - omega * temp) * exp_x
	var new_pos = target + (change + temp) * exp_x
	return [new_pos, new_vel]



func _crit_damp_vec3(current: Vector3, target: Vector3, vel: Vector3, smooth_time: float, dt: float) -> Array:
	var rx: Array = _crit_damp(current.x, target.x, vel.x, smooth_time, dt)
	var ry: Array = _crit_damp(current.y, target.y, vel.y, smooth_time, dt)
	var rz: Array = _crit_damp(current.z, target.z, vel.z, smooth_time, dt)
	return [
		Vector3(float(rx[0]), float(ry[0]), float(rz[0])),
		Vector3(float(rx[1]), float(ry[1]), float(rz[1])),
	]



func _crit_damp_angle(current: float, target: float, vel: float, smooth_time: float, dt: float) -> Array:
	var delta = wrapf(current - target, -PI, PI)
	var r: Array = _crit_damp(target + delta, target, vel, smooth_time, dt)
	return [float(r[0]), float(r[1])]


func _rest_bone(name: String, fallback: Vector3) -> Vector3:
	if m.boy and m.boy.skel:
		var p: Vector3 = m.boy.lie_bone_world(name)
		if p.length_squared() > 1e-6:
			return p
	return fallback


## Live sit/sleep look-at: chest/face centred so the boy sits in the middle third.

func _rest_cam_target() -> Vector3:
	var hips = _rest_bone("mixamorig_Hips", m.boy.global_position + Vector3(0, 0.55, 0))
	var head = _rest_bone("mixamorig_Head", m.boy.global_position + Vector3(0, 1.15, 0))
	if m.rest_phase <= 1 and m.rest_root_sit.length_squared() > 1e-6:
		var walk_t = m.player.global_position.lerp(m.rest_root_sit, clampf(m.rest_t * 0.55, 0.0, 1.0))
		return walk_t + Vector3(0, 0.72, 0)
	if m.rest_kind == "sleep" or m.seat_lying:
		# Bias toward the face so the cradle + expression read.
		return hips.lerp(head, 0.68)
	if m.rest_kind == "seat":
		return hips.lerp(head, 0.58)
	return hips.lerp(head, 0.52)



func _rest_face_fwd() -> Vector3:
	if m.rest_kind == "seat" and m.seat_face.length_squared() > 1e-6:
		var f = m.seat_face
		f.y = 0.0
		if f.length_squared() > 1e-6:
			return f.normalized()
	return Vector3(-sin(m.face_yaw), 0.0, -cos(m.face_yaw))


## Ideal distance so boy+prop fill ~45–60% of portrait height (KEEP_HEIGHT FOV).

func _rest_frame_dist(fig_h: float) -> float:
	var tall = m._tall()
	var fov_v = deg_to_rad(66.0 if tall else 52.0)
	var fill = 0.52
	var d = (fig_h / fill) / (2.0 * tan(fov_v * 0.5))
	return clampf(d, 2.15, 4.0)



func _rest_cam() -> Array:
	var head = _rest_bone("mixamorig_Head", m.boy.global_position + Vector3(0, 1.15, 0))
	var hips = _rest_bone("mixamorig_Hips", m.boy.global_position + Vector3(0, 0.55, 0))
	var t = _rest_cam_target()
	var fig_h = maxf(head.y - (hips.y - 0.55), 1.05)
	if m.rest_kind == "sleep" or m.seat_lying:
		fig_h = 1.20
	var dist = _rest_frame_dist(fig_h)
	var pitch = 0.16
	if m.rest_kind == "sleep" or m.seat_lying:
		pitch = 0.24
	elif m.rest_kind == "seat":
		pitch = 0.14
	if m.rest_cam_yaw == INF:
		var pick: Array = _pick_rest_framing(t, head, hips, pitch, dist)
		var adj0: Array = _rest_los_adjust(t, head, float(pick[0]), float(pick[1]), float(pick[2]))
		m.rest_cam_yaw = float(adj0[0])
		m.rest_cam_pitch = float(adj0[1])
		m.rest_cam_dist = float(adj0[2])
	elif m.rest_cam_ease < 0.95 and not m.dragging:
		# While easing onto the framing, keep clearing LOS; stop fighting once the user orbits.
		var adj: Array = _rest_los_adjust(t, head, m.rest_cam_yaw, m.rest_cam_pitch, m.rest_cam_dist)
		m.rest_cam_yaw = float(adj[0])
		m.rest_cam_pitch = float(adj[1])
		m.rest_cam_dist = float(adj[2])
	return [t, m.rest_cam_yaw, m.rest_cam_pitch, m.rest_cam_dist]


## Front three-quarter (±25–35° off facing). Hammock: side-of-face, slightly above.
## Picks the ± side with clearer sea/scenery behind the boy and a clear LOS to the head.

func _pick_rest_framing(t: Vector3, head: Vector3, hips: Vector3, pitch: float, dist: float) -> Array:
	var cands: Array = []
	if m.rest_kind == "sleep" or m.seat_lying:
		var side = m.rest_side
		side.y = 0.0
		if side.length_squared() < 1e-6:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		var along = head - hips
		along.y = 0.0
		if along.length_squared() < 1e-6:
			along = (m.island.hammock_b - m.island.hammock_a)
			along.y = 0.0
		along = along.normalized() if along.length_squared() > 1e-6 else Vector3.FORWARD
		# Side of the face, a touch toward the feet so eyes/mouth read (not crown-only).
		for sgn in [-1.0, 1.0]:
			var dir: Vector3 = (side * sgn * 0.92 - along * 0.28).normalized()
			var yaw = atan2(dir.x, dir.z)
			cands.append([yaw, pitch, dist])
			cands.append([yaw, pitch + 0.06, dist * 0.95])
	else:
		var face = _rest_face_fwd()
		for ang_deg in [28.0, 32.0, 25.0, 35.0]:
			var ang = deg_to_rad(ang_deg)
			for sgn in [-1.0, 1.0]:
				# Camera in front of the boy, angled off his facing.
				var dir: Vector3 = face.rotated(Vector3.UP, sgn * ang)
				var yaw = atan2(dir.x, dir.z)
				cands.append([yaw, pitch, dist])
	var best: Array = cands[0]
	var best_score = -INF
	for c in cands:
		var yaw: float = float(c[0])
		var p: float = float(c[1])
		var d: float = float(c[2])
		var cam = t + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * d
		var score = _score_rest_view(t, head, cam, yaw, p, d)
		if score > best_score:
			best_score = score
			best = [yaw, p, d]
	return best



func _score_rest_view(t: Vector3, head: Vector3, cam: Vector3, yaw: float, pitch: float, dist: float) -> float:
	var score = 0.0
	if _rest_los_blocked(cam, head):
		score -= 40.0
	elif _rest_los_blocked(cam, t):
		score -= 18.0
	# Prefer open water / low ground behind the boy (continuation past look-at).
	var toward = (t - cam)
	toward.y = 0.0
	if toward.length_squared() > 1e-6:
		toward = toward.normalized()
		var beyond = t + toward * 10.0
		var gh = m._surface(beyond.x, beyond.z)
		if gh < 0.12:
			score += 8.0
		score += clampf(0.6 - gh * 0.25, -2.0, 3.0)
	# Torch poles near the look line are expensive (log sit).
	for ob in m.island.obstacles:
		if String(ob[3]).find("火把") < 0 and String(ob[3]).find("torch") < 0:
			continue
		var c2: Vector2 = ob[0]
		var closest = Geometry3D.get_closest_point_to_segment(Vector3(c2.x, cam.y, c2.y), cam, head)
		if Vector2(closest.x - c2.x, closest.z - c2.y).length() < float(ob[1]) + 0.35:
			score -= 12.0
	# Prefer camera not buried in terrain.
	var floor_y = maxf(m._surface(cam.x, cam.z), 0.0) + 0.35
	if cam.y < floor_y:
		score -= 20.0
	score -= absf(dist - 2.8) * 0.15
	score -= absf(pitch - 0.18) * 0.5
	return score


## Ray from camera to head: trunks, torch/obstacle cylinders, terrain mounds.

func _rest_los_blocked(cam: Vector3, head: Vector3) -> bool:
	for tr: Array in m.island.trunks:
		if _seg_hits_trunk(cam, head, tr):
			return true
	for ob in m.island.obstacles:
		var c2: Vector2 = ob[0]
		var top_y: float = float(ob[2])
		var bot_y: float = float(ob[4]) if ob.size() > 4 else 0.0
		var rad: float = float(ob[1]) + 0.12
		var closest = Geometry3D.get_closest_point_to_segment(Vector3(c2.x, 0.5 * (bot_y + top_y), c2.y), cam, head)
		if closest.y < bot_y - 0.1 or closest.y > top_y + 0.15:
			continue
		if Vector2(closest.x - c2.x, closest.z - c2.y).length() < rad:
			return true
	# Terrain bite: sample along the ray; ground poking above the ray blocks.
	var n = 6
	for i in range(1, n):
		var u = float(i) / float(n)
		var p: Vector3 = cam.lerp(head, u)
		var gh = m._surface(p.x, p.z)
		if p.y < gh + 0.28:
			return true
	return false


## If LOS is blocked, pull in / nudge yaw·pitch until the head is clear.

func _rest_los_adjust(t: Vector3, head: Vector3, yaw: float, pitch: float, dist: float) -> Array:
	var y = yaw
	var p = pitch
	var d = dist
	for n in 10:
		var cam = t + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d
		var floor_y = maxf(m._surface(cam.x, cam.z), 0.0) + 0.35
		if cam.y < floor_y:
			p = clampf(p + 0.05, 0.08, 0.55)
			cam.y = floor_y
		if not _rest_los_blocked(cam, head):
			return [y, p, d]
		d = maxf(d * 0.88, 1.55)
		y += 0.11 * (1.0 if n % 2 == 0 else -1.0)
		p = clampf(p + 0.035, 0.08, 0.55)
	return [y, p, d]


## the yaw closest to `pref` from which no palm trunk stands between the camera and the resting kid

func _clear_yaw(t: Vector3, pref: float, pitch: float, dist: float) -> float:
	var along = m.island.towel_dir * 0.7 if m.rest_kind != "sleep" else (m.island.hammock_b - m.island.hammock_a).normalized() * 0.7
	if m.rest_kind == "seat":
		along = m.rest_side * 0.3
	var looks: Array[Vector3] = [t, t + along, t - along]
	var best = pref
	var best_cost = INF
	for n in 15:
		var dy = floori((n + 1) * 0.5) * 0.17 * (1.0 if n % 2 == 1 else -1.0)
		var yaw = pref + dy
		var cam = t + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
		var hits = 0
		for l in looks:
			for tr: Array in m.island.trunks:
				if _seg_hits_trunk(cam, l, tr):
					hits += 1
					break
		var cost = hits * 10.0 + absf(dy)
		if cost < best_cost:
			best_cost = cost
			best = yaw
		if hits == 0:
			break
	return best


func _seg_hits_trunk(a: Vector3, b: Vector3, pts: Array) -> bool:
	if Vector2(pts[0].x - a.x, pts[0].z - a.z).length() > a.distance_to(b) + 6.0:
		return false
	for i in pts.size() - 1:
		var c = Geometry3D.get_closest_points_between_segments(a, b, pts[i], pts[i + 1])
		if c[0].distance_to(c[1]) < 0.42:
			return true
	return false


func _snap_explore_cam(front = false) -> void:
	# follow-behind while exploring; optional 3/4-front for start / face checks
	m.ex_yaw = m.face_yaw + PI + 0.45 if front else m.face_yaw
	var c = _explore_cam()
	m.cam_target = c[0]; m.cam_yaw = c[1]; m.cam_pitch = c[2]; m.cam_dist = c[3]
	m._cam_t_vel = Vector3.ZERO
	m._cam_yaw_vel = 0.0
	m._cam_pitch_vel = 0.0
	m._cam_dist_vel = 0.0
	m._cam_teleport = true


func _toggle_cam_fixed() -> void:
	_begin_cam_blend()
	m.cam_fixed = not m.cam_fixed
	if m.cam_fixed:
		# Freeze at the current follow framing (retarget if already resting).
		var c: Array
		if m.mode == 3:
			c = _rest_cam()
		elif m.mode == 2:
			c = [m.cam_target, m.view_yaw, m.view_pitch, m.view_dist]
		else:
			c = _explore_cam()
		m.fix_target = c[0]
		m.fix_yaw = float(c[1])
		m.fix_pitch = float(c[2])
		m.fix_dist = float(c[3])
		# Don't snap — _update_camera eases from _cam_blend_from_* over 0.35 s.
	_persist_cam_fixed()
	m._update_ui()



func _nudge_zoom(factor: float) -> void:
	m.zoom_pending *= factor



func _persist_cam_fixed() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("try{localStorage.setItem('ss_cam_fixed',%s)}catch(e){}" % ("'1'" if m.cam_fixed else "'0'"), true)



func _load_cam_fixed() -> void:
	if not OS.has_feature("web"):
		return
	# CDP / debug probes always start in follow — a stale localStorage "固定视角"
	# left the boy walking off-screen while the lens sat on empty grass.
	if m._opt("debug") == "1" or m._opt("at") != "":
		m.cam_fixed = false
		JavaScriptBridge.eval("try{localStorage.setItem('ss_cam_fixed','0')}catch(e){}", true)
		return
	var v = JavaScriptBridge.eval("try{localStorage.getItem('ss_cam_fixed')}catch(e){null}", true)
	m.cam_fixed = str(v) == "1"



func _mix_cam_blend() -> void:
	if m._cam_blend_t <= 0.0:
		return
	var u = 1.0 - (m._cam_blend_t / maxf(m._cam_blend_dur, 0.001))
	var e = u * u * (3.0 - 2.0 * u)
	m.cam_target = m._cam_blend_from_t.lerp(m.cam_target, e)
	m.cam_yaw = lerp_angle(m._cam_blend_from_yaw, m.cam_yaw, e)
	m.cam_pitch = lerpf(m._cam_blend_from_pitch, m.cam_pitch, e)
	m.cam_dist = lerpf(m._cam_blend_from_dist, m.cam_dist, e)


## Foliage / leaf / static cutout from the post-plant boy focus.

func _update_camera(delta: float) -> void:
	_flush_orbit_pending()
	if m._cam_blend_t > 0.0:
		m._cam_blend_t = maxf(m._cam_blend_t - delta, 0.0)
	if m.demo_cam:
		if m.demo_track.size() > 0:
			var tr: Array = m.demo_track
			m.cam_target = m.player.global_position + Vector3(0, tr[3], 0)
			m.cam_yaw = (float(tr[0]) if tr.size() > 4 else m.face_yaw + float(tr[0]))
			m.cam_pitch = tr[1]
			m.cam_dist = tr[2]
		_mix_cam_blend()
		_apply_camera(delta)
		return
	# Fixed mode: never auto-follow while exploring; on REST soft-retarget once so
	# sit/lie aren't off-frame after toggling 固定视角 in explore.
	if m.cam_fixed and m.mode != 1:
		if m.mode == 3 and not get_meta("fix_rest_locked", false):
			var rc: Array = _rest_cam()
			m.fix_target = rc[0]
			m.fix_yaw = float(rc[1])
			m.fix_pitch = float(rc[2])
			m.fix_dist = float(rc[3])
			set_meta("fix_rest_locked", true)
		if not m.dragging:
			m.orbit_vel *= exp(-delta * 3.5)
			m.fix_yaw += m.orbit_vel.x * delta
			m.fix_pitch = clampf(m.fix_pitch + m.orbit_vel.y * delta, 0.06, 1.25)
			m.cam_dist = lerpf(m.cam_dist, m.fix_dist, 1.0 - exp(-delta * 5.0))
		else:
			m.cam_dist = m.fix_dist
		m.cam_target = m.fix_target
		m.cam_yaw = m.fix_yaw
		m.cam_pitch = m.fix_pitch
		if m.dragging:
			m.cam_dist = m.fix_dist
		_mix_cam_blend()
		_apply_camera(delta)
		return
	var want: Array
	var k: float
	if m.mode == 1 and (m.state == 3 or m.state == 4) and m.fly_t > 0.45:
		var tall = m._tall()
		var dir = Vector3(m.stone_vel.x, 0, m.stone_vel.z)
		dir = dir.normalized() if dir.length() > 0.5 else m._aim_dir()
		want = [Vector3(m.stone_pos.x, max(m.stone_pos.y * 0.5, 0.3), m.stone_pos.z) + dir * 2.0, atan2(-dir.x, -dir.z) + 0.35, 0.42 if tall else 0.32, 11.0 if tall else 9.0]
		k = 1.0 - exp(-delta * 4.0 * smoothstep(0.45, 1.1, m.fly_t))
	elif m.mode == 2:
		if not m.dragging:
			m.view_yaw += m.orbit_vel.x * delta
			m.view_pitch = clamp(m.view_pitch + m.orbit_vel.y * delta, 0.06, 1.42)
			m.orbit_vel *= exp(-delta * 3.5)
		var head = m.player.global_position + Vector3(0, 0.8, 0)
		want = [head.lerp(Vector3(0, 1.5, -2.0), smoothstep(10.0, 45.0, m.view_dist)), m.view_yaw, m.view_pitch, m.view_dist]
		k = 1.0 - exp(-delta * 9.0)
	elif m.mode == 1:
		var hold = m.finish_hold > 0.0
		m.finish_hold -= delta
		want = _throw_cam()
		if (m.state == 2 or m.state == 3) and not m._tall():
			want[3] = float(want[3]) + 0.4
		k = 1.0 - exp(-delta * (2.2 if hold else 3.0))
		if hold:
			# coming back from the stone view: re-centre on the kid first, then dolly in, so the
			# camera never passes in front of him
			m.cam_target = m.cam_target.lerp(want[0], 1.0 - exp(-delta * 5.5))
			m.cam_dist = maxf(m.cam_dist, float(want[3]))
	elif m.mode == 3 and m.rest_phase >= 1:
		# Smooth ~0.8 s ease onto the per-prop face-forward framing; orbit edits rest_cam_*.
		want = _rest_cam()
		m.rest_cam_ease = minf(m.rest_cam_ease + delta / 0.8, 1.0)
		var ease_k = smoothstep(0.0, 1.0, m.rest_cam_ease)
		# While easing in, blend faster toward the framing; after, track tightly (orbit feels direct).
		k = lerpf(1.0 - exp(-delta * 2.2), 1.0 - exp(-delta * 10.0), ease_k)
		if m.dragging:
			k = 1.0 - exp(-delta * 14.0)
	else:
		# Explore follow: critically damped spring behind the boy + look-ahead.
		# Hard requirement: whole body in the central ~60% of the viewport while
		# walking / running / turning / on slopes / after stick release.
		var orbiting_now = m.dragging or m.orbit_pending.length_squared() > 1e-10 or m._orbit_ease > 0.05
		var stick_mag = m.joy.value.length() if m.joy else 0.0
		# Stick / walk: keep desired yaw locked behind the boy (no lag off-frame).
		if not orbiting_now and (m.cur_speed > 0.12 or stick_mag > 0.08):
			m.ex_yaw = m.face_yaw
		want = _explore_cam()
		if orbiting_now:
			# Drag: angles already snapped in _flush_orbit_pending; keep target tight.
			m.cam_target = want[0]
			m.cam_yaw = want[1]
			m.cam_pitch = want[2]
			m.cam_dist = want[3]
			m.ex_yaw = m.cam_yaw
			m.ex_pitch = m.cam_pitch
			m.ex_dist = m.cam_dist
			m._cam_t_vel = Vector3.ZERO
			m._cam_yaw_vel = 0.0
			m._cam_pitch_vel = 0.0
			m._cam_dist_vel = 0.0
			_mix_cam_blend()
			_apply_camera(delta)
			return
		# Critically damped chase. While stick/speed is live: hard-lock look-at + yaw
		# so lag can never push him out of the central 60% (dir_e edge fails).
		# Pitch/dist keep a fast spring. Idle/release: full spring on everything.
		var stick_lock = stick_mag > 0.08 or m.cur_speed > 0.08
		m._cam_stick_lock = stick_lock
		# Release eases back to the same default frame over ~0.45 s. The old
		# 0.14 s spring plus a vanishing look-ahead read as a dolly into a crop.
		var st_t = 0.08 if stick_lock else 0.45
		if m.rest_exit_cam_t > 0.0:
			m.rest_exit_cam_t = maxf(m.rest_exit_cam_t - delta, 0.0)
			st_t = lerpf(0.22, st_t, 1.0 - m.rest_exit_cam_t / 0.8)
		if m.mode == 3:
			st_t = 0.22
		if stick_lock:
			m.cam_target = want[0]
			m.cam_yaw = float(want[1])
			m._cam_t_vel = Vector3.ZERO
			m._cam_yaw_vel = 0.0
		else:
			var td: Array = _crit_damp_vec3(m.cam_target, want[0], m._cam_t_vel, st_t, delta)
			m.cam_target = td[0]
			m._cam_t_vel = td[1]
			var yd2: Array = _crit_damp_angle(m.cam_yaw, float(want[1]), m._cam_yaw_vel, st_t, delta)
			m.cam_yaw = float(yd2[0])
			m._cam_yaw_vel = float(yd2[1])
		var pd: Array = _crit_damp(m.cam_pitch, float(want[2]), m._cam_pitch_vel, st_t * 1.15, delta)
		m.cam_pitch = float(pd[0])
		m._cam_pitch_vel = float(pd[1])
		var dd: Array = _crit_damp(m.cam_dist, float(want[3]), m._cam_dist_vel, st_t * 1.25, delta)
		m.cam_dist = float(dd[0])
		m._cam_dist_vel = float(dd[1])
		# Stick motion is camera-relative via ex_yaw. Do NOT write cam_dist/pitch
		# back into ex_* — those are user zoom/orbit prefs; framing may pad dist.
		m.ex_yaw = m.cam_yaw
		_mix_cam_blend()
		_apply_camera(delta)
		m._cam_stick_lock = false
		return
	m._cam_stick_lock = false
	m.cam_target = m.cam_target.lerp(want[0], k)
	if m.dragging or m.orbit_pending.length_squared() > 1e-10 or m._orbit_ease > 0.01:
		m.cam_yaw = want[1]
		m.cam_pitch = want[2]
		m.cam_dist = want[3]
	else:
		m.cam_yaw = lerp_angle(m.cam_yaw, want[1], k)
		m.cam_pitch = lerp(m.cam_pitch, want[2], k)
		m.cam_dist = lerp(m.cam_dist, want[3], k)
	# Mode switch ease-in-out (~0.55 s) — no snap / stall.
	_mix_cam_blend()
	_apply_camera(delta)


func _cam_blocked(q: Vector3) -> bool:
	# Always respect small prop blockers (crates / posts) so explore doesn't hide the boy.
	for bl in m.island.cam_blockers:
		if q.distance_to(bl[0]) < float(bl[1]):
			return true
	if m.mode == 1 or m.mode == 2:
		return false
	for ob in m.island.obstacles:
		var c: Vector2 = ob[0]
		if q.y < float(ob[2]) and q.y > float(ob[4]) and Vector2(q.x - c.x, q.z - c.y).length() < float(ob[1]) + 0.25:
			return true
	return false

## Smoothed lateral dodge (m along camera-right). Never snaps — was the walk_120 boy_ds spike.


func _apply_camera(delta: float = 1.0 / 60.0) -> void:
	var full_off = Vector3(sin(m.cam_yaw) * cos(m.cam_pitch), sin(m.cam_pitch), cos(m.cam_yaw) * cos(m.cam_pitch)) * m.cam_dist
	# Soft spring arm: frame-rate independent pull-in (no constant-α snap at 120Hz).
	# Floor: never crush below ~82% in explore — v35 slope probe + ankle pull
	# shrank the arm to ~0.4 and framed a head crop after stick release.
	const ARM_FLOOR = 0.82
	var want_k = 1.0
	var orbiting = m.dragging or m.orbit_pending.length_squared() > 1e-10 or m._orbit_ease > 0.05
	var moving = m.cur_speed > 0.12
	# Probe every frame; smooth the result so clearance never chatters.
	if m.cam_dist < 20.0 and (not m.demo_cam or m.demo_track.size() > 0):
		var steps = 8 if moving else 10
		for i in range(2, steps + 1):
			var q = m.cam_target + full_off * (float(i) / float(steps))
			if _cam_blocked(q):
				want_k = maxf(float(i - 1) / float(steps), 1.35 / maxf(m.cam_dist, 0.01))
				break
	# During orbit, hold arm length — probe flicker was the cam_ds spike source.
	if orbiting:
		want_k = m._cam_arm_k
	elif m.mode == 0:
		want_k = maxf(want_k, ARM_FLOOR)
	# Soft chase of probe result (no step hysteresis snap).
	m._cam_arm_want = lerpf(m._cam_arm_want, want_k, 1.0 - exp(-delta * 10.0))
	if m.mode == 0 and not orbiting:
		m._cam_arm_want = maxf(m._cam_arm_want, ARM_FLOOR)
	# Pull-in smoothed; recover slower so clearance doesn't ping-pong.
	var arm_rate = 2.6 if orbiting else (3.0 if m._cam_arm_want < m._cam_arm_k - 0.01 else 1.8)
	m._cam_arm_k = lerpf(m._cam_arm_k, m._cam_arm_want, 1.0 - exp(-delta * arm_rate))
	if m.mode == 0 and not orbiting:
		m._cam_arm_k = maxf(m._cam_arm_k, ARM_FLOOR)
	var off = full_off * m._cam_arm_k
	var right = Vector3(cos(m.cam_yaw), 0, -sin(m.cam_yaw))
	# Lateral dodge only while nearly idle.
	m._cam_slide_want = 0.0
	if m.mode == 0 and not orbiting and not moving:
		var probe = m.cam_target + off
		if _cam_blocked(probe):
			for s in [0.55, -0.55, 1.1, -1.1, 1.8, -1.8]:
				if not _cam_blocked(probe + right * s):
					m._cam_slide_want = s
					break
			# Never pull the arm in while idle. That crush (down to 0.42) is the
			# head-crop after stick release. Slide sideways; the hill lift owns height.
	var slide_rate = (1.6 if absf(m._cam_slide_want) > absf(m._cam_slide) else 2.4) if not moving else 4.0
	if moving:
		m._cam_slide_want = 0.0
	m._cam_slide = lerpf(m._cam_slide, m._cam_slide_want, 1.0 - exp(-delta * slide_rate))
	var pos = m.cam_target + off + right * m._cam_slide
	# Keep the lens above the *drawn* mesh (not analytic ground_h) so slope follow
	# never sits under a triangle and makes the boy look buried to the shorts.
	var floor_y: float = m._surface(pos.x, pos.z) + 0.65
	if m._on_dock(pos.x, pos.z):
		floor_y = maxf(floor_y, Island.DECK_Y + 0.45)
	if pos.y < floor_y:
		pos.y = floor_y
	# Soft terrain probe along the arm so we don't look through a hillside.
	# Prefer lift over pull-in so framing height stays stable on slopes.
	if m.mode == 0 and m.cam_dist < 12.0:
		for i in range(3, 9):
			var t: float = float(i) / 9.0
			var q: Vector3 = m.cam_target.lerp(pos, t)
			var h: float = m._surface(q.x, q.z) + 0.45
			if q.y < h:
				pos.y = maxf(pos.y, h + 0.55)
				# Mild pull only — never below the arm floor plan-distance.
				pos = m.cam_target + (pos - m.cam_target) * maxf(t - 0.04, 0.72)
				pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 0.95)
				break
		var p_mh: float = m._surface(m.cam_target.x, m.cam_target.z)
		var c_mh: float = m._surface(pos.x, pos.z)
		var uphill: float = p_mh - c_mh
		if uphill > 0.08:
			var lift: float = clampf(uphill * 0.85, 0.35, 2.2)
			pos.y = maxf(pos.y, m.cam_target.y + 0.95 + lift * 0.65)
			pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 1.05)
			pos.y = maxf(pos.y, m.cam_target.y + 1.05)
		# Ankle-line clearance: raise until cam→ankles clears the crest (lift only).
		var ankle = Vector3(m.cam_target.x, p_mh + 0.10, m.cam_target.z)
		for _iter in range(4):
			var blocked = false
			var block_h = 0.0
			for i in range(2, 10):
				var t3: float = float(i) / 10.0
				var q3: Vector3 = pos.lerp(ankle, t3)
				var hill3: float = m._surface(q3.x, q3.z)
				if hill3 > q3.y + 0.04:
					blocked = true
					block_h = maxf(block_h, hill3)
			if not blocked:
				break
			pos.y = maxf(pos.y, block_h + 1.25)
			pos.y = maxf(pos.y, m.cam_target.y + 1.25)
			pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 1.15)
		# Keep a minimum plan-distance so the boy stays whole-body framed (not a face crop).
		var flat = Vector2(pos.x - m.cam_target.x, pos.z - m.cam_target.z)
		var min_flat: float = maxf(m.cam_dist * 0.94, 5.60)
		if flat.length() > 0.05 and flat.length() < min_flat:
			var sc: float = min_flat / flat.length()
			pos.x = m.cam_target.x + (pos.x - m.cam_target.x) * sc
			pos.z = m.cam_target.z + (pos.z - m.cam_target.z) * sc
			pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 1.05)
		# Hillside lift: when crest-blocked, snap lift up immediately (green-plane
		# boy-crop). Ease down with a short spring so release isn't a pop.
		var nom = m.cam_target + full_off * m._cam_arm_k
		var want_lift: float = maxf(0.0, pos.y - nom.y)
		if want_lift > m._cam_hill_lift:
			m._cam_hill_lift = want_lift
			m._cam_hill_vel = 0.0
		else:
			var hl: Array = _crit_damp(m._cam_hill_lift, want_lift, m._cam_hill_vel, 0.14, delta)
			m._cam_hill_lift = float(hl[0])
			m._cam_hill_vel = float(hl[1])
		pos = nom
		pos.y = nom.y + m._cam_hill_lift
		pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 0.95)
		# Lifted / crest-blocked → push out so we look *over* the slope, not into it.
		if m._cam_hill_lift > 0.06 or want_lift > 0.20:
			var flat2 = Vector2(pos.x - m.cam_target.x, pos.z - m.cam_target.z)
			var push: float = 1.0 + clampf(maxf(m._cam_hill_lift, want_lift) * 0.55, 0.0, 1.10)
			if flat2.length() > 0.05:
				pos.x = m.cam_target.x + flat2.x * push
				pos.z = m.cam_target.z + flat2.y * push
				pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 0.95)
		# Cap height above look-at on flat ground. On a crest, a tight cap put the
		# lens *inside* the hillside (cdp_slope_up_3 = green plane, boy missing).
		# Prefer push-out + look-raise for framing; only soft-cap when clear.
		var max_above = 2.15 if want_lift > 0.35 else 1.70
		if pos.y > m.cam_target.y + max_above:
			var flat3 = Vector2(pos.x - m.cam_target.x, pos.z - m.cam_target.z)
			if flat3.length() > 0.05 and want_lift > 0.25:
				var need: float = (pos.y - (m.cam_target.y + max_above)) * 0.85
				var sc: float = 1.0 + clampf(need / maxf(flat3.length(), 0.5), 0.0, 0.8)
				pos.x = m.cam_target.x + flat3.x * sc
				pos.z = m.cam_target.z + flat3.y * sc
			pos.y = minf(pos.y, m.cam_target.y + max_above)
			pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 0.90)
		# Final LOS: if cam→ankle still hits the hill, force height + push-out.
		# Sync into _cam_hill_lift so the next frame doesn't rebuild from nom and
		# throw the raise away (that was the green-plane boy-crop on slope_up_3).
		var p_mh2: float = m._surface(m.cam_target.x, m.cam_target.z)
		var ankle2 = Vector3(m.cam_target.x, p_mh2 + 0.12, m.cam_target.z)
		for _k in range(4):
			var hit = false
			var hit_h = 0.0
			for i in range(1, 12):
				var t4: float = float(i) / 12.0
				var q4: Vector3 = pos.lerp(ankle2, t4)
				var h4: float = m._surface(q4.x, q4.z)
				if h4 > q4.y + 0.04:
					hit = true
					hit_h = maxf(hit_h, h4)
			if not hit:
				break
			pos.y = maxf(pos.y, hit_h + 1.35)
			pos.y = maxf(pos.y, m.cam_target.y + 1.35)
			var flat4 = Vector2(pos.x - m.cam_target.x, pos.z - m.cam_target.z)
			if flat4.length() > 0.05:
				pos.x = m.cam_target.x + flat4.x * 1.12
				pos.z = m.cam_target.z + flat4.y * 1.12
				pos.y = maxf(pos.y, m._surface(pos.x, pos.z) + 1.05)
		m._cam_hill_lift = maxf(m._cam_hill_lift, pos.y - nom.y)
	else:
		m._cam_hill_lift = lerpf(m._cam_hill_lift, 0.0, 1.0 - exp(-delta * 4.0))
		m._cam_hill_vel = 0.0
	# Look slightly higher while the arm is hillside-lifted (local only — do not
	# accumulate into cam_target or the spring drifts skyward over frames).
	var look = m.cam_target
	if m.mode == 0 and m._cam_hill_lift > 0.05:
		# Keep the hat under the top of the frame when the slope lifts the lens.
		look.y += m._cam_hill_lift * 0.72
	# Step budget: follow + look-ahead need ~7 cm at run speed; yaw spring on a
	# ~4.5 m arm needs more while turning. Cap straight follow tightly; allow
	# turn-proportional motion; hard-stop true teleports without the flag.
	# Stick-lock: camera must sit on the orbit behind the boy every frame. A step
	# clamp here left the lens beside him on 180° face turns (CDP UV.x < 0).
	if m._cam_pos_init and not m._cam_teleport and not m.demo_cam and not m._cam_stick_lock:
		var dpos = pos - m._cam_pos_prev
		var hill_extra: float = clampf(m._cam_hill_lift * 0.5, 0.0, 0.45) if m.mode == 0 else 0.0
		var max_step: float = 0.08 + hill_extra
		if dpos.length() > max_step:
			pos = m._cam_pos_prev + dpos.limit_length(max_step)
	m._cam_pos_vel = Vector3.ZERO
	# Walk/settle snaps vs stick-lock orbit follow (face turns) — separate meters.
	if m._cam_pos_init and not m._cam_teleport:
		var step_cm: float = m._cam_pos_prev.distance_to(pos) * 100.0
		if m._cam_stick_lock:
			m._cam_orbit_step_cm = maxf(m._cam_orbit_step_cm, step_cm)
		else:
			m._cam_max_step_cm = maxf(m._cam_max_step_cm, step_cm)
	m._cam_teleport = false
	m._cam_pos_prev = pos
	m._cam_pos_init = true
	if not pos.is_finite() or not look.is_finite() or pos.distance_squared_to(look) < 1e-6:
		pos = look + Vector3(0.0, 1.2, 3.5)
	m.camera.global_position = pos
	var up = Vector3.UP
	var to_look = (look - pos).normalized()
	if absf(to_look.dot(up)) > 0.98:
		up = Vector3.RIGHT
	m.camera.look_at(look, up)
	m._export_frame_probe()
	if m.refl:
		m.refl.update()



## ?name=value in the page URL (web) or --name=value on the command line
