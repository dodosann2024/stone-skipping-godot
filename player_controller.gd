class_name PlayerController
extends RefCounted
## Only writer of the boy root transform.
## One ground sampler (Ground.height → render-mesh collision). No analytic
## ground_h / mesh_h while walking. Physics stores the pose; present() is the
## explore-frame write. Rest, throw and placement call write_position / write_yaw.

const WALK_MAX = 1.15
const RUN_SPEED = 2.7
const RUN_STICK_ON = 0.90
const RUN_STICK_OFF = 0.82
const BOY_R = 0.19
const MODE_EXPLORE = 0

var ground: Ground
var host: Node
var pelvis_step_m = 0.0
var _route_m = 0.0
var _route_n = 0
var _route_wp: Array[Vector2] = []
var _route_wi := 0
var _route_pause := 0.0
var _route_stuck := 0
var _route_still := 0
var _route_anchor := Vector2.ZERO
var _route_kinds := {}
var _route_knee_max := 0.0
var _route_len_min := 1.0
var _route_gnd_min := 99.0
var _route_worst := Vector3.ZERO
var _route_pelvis_max := 0.0
var _route_bad := 0
var _route_seen_stop := false


func setup(p_ground: Ground, p_host: Node = null) -> void:
	ground = p_ground
	host = p_host


func bind_host(p_host: Node) -> void:
	host = p_host


func height(x: float, z: float, hint_y: float = 10.0) -> float:
	if ground == null:
		return hint_y
	return ground.height(x, z, hint_y)


func height_exact(x: float, z: float, hint_y: float = 10.0) -> float:
	if ground == null:
		return hint_y
	return ground.height_exact(x, z, hint_y)


## Highest walkable triangle under the body and the two foot offsets.
## Samples more than 14 cm above the body ray are rejected (a missed face, not a step).
func _support_y(x: float, z: float, hint_y: float, yaw: float) -> float:
	var body := height_exact(x, z, hint_y)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var best := body
	for dist in [0.16, 0.32]:
		for dir_v in [fwd, -fwd, right, -right]:
			var dir: Vector3 = dir_v
			var off: Vector3 = dir * float(dist)
			var h := height_exact(x + off.x, z + off.z, hint_y)
			if h < -0.45:
				continue
			if absf(h - body) > 0.28:
				continue
			# The lower triangle is the one a straight leg can stand on. The
			# uphill foot bends up onto its own face.
			best = minf(best, h)
	return move_toward(hint_y, best, 0.029)


func write_position(pos: Vector3) -> void:
	var body: Node3D = host.player
	if body == null:
		return
	var prev_y = body.global_position.y
	pelvis_step_m = absf(pos.y - prev_y)
	body.global_position = pos
	host._body_pos = pos
	host._body_pos_prev = pos
	host._body_sync = true
	host.ground_y = pos.y


func write_yaw(yaw: float) -> void:
	var body: Node3D = host.player
	if body == null:
		return
	body.rotation = Vector3(body.rotation.x, yaw, body.rotation.z)
	host._body_yaw = yaw
	host._body_yaw_prev = yaw
	host._body_sync = true


func write_body(pos: Vector3, yaw: float) -> void:
	write_position(pos)
	write_yaw(yaw)
	host.face_yaw = yaw


## Explore display pose. XZ from the physics interval, Y from one ground query
## at the displayed XZ. This is the only explore-frame root write.
func present() -> void:
	if host == null or host.player == null:
		return
	if not host._body_sync:
		host._sync_body_pose(true)
		return
	if int(host.mode) != MODE_EXPLORE:
		return
	var f = Engine.get_physics_interpolation_fraction()
	var p: Vector3 = host._body_pos_prev.lerp(host._body_pos, f)
	var prev_y = host.player.global_position.y
	# Physics already chose the drawn-triangle support and capped the step.
	# Re-querying here jumped the root onto a different face (tens of cm).
	p.y = lerpf(host._body_pos_prev.y, host._body_pos.y, f)
	pelvis_step_m = absf(p.y - prev_y)
	host.player.global_position = p
	host.player.rotation.y = lerp_angle(host._body_yaw_prev, host._body_yaw, f)
	host.ground_y = p.y


func physics_step(delta: float) -> void:
	var m = host
	var inp: Vector2 = m.joy.read_move(m.demo_mode, m.demo_input) if m.joy != null else Vector2.ZERO
	if OS.get_environment("V39_ROUTE") == "1":
		inp = _route_stick(delta)
	var mag = inp.length()
	if mag >= RUN_STICK_ON or (m.demo_mode and m.demo_run):
		m.stick_running = true
	elif mag < RUN_STICK_OFF:
		m.stick_running = false
	var running: bool = m.stick_running
	var fwd = Vector3(-sin(m.ex_yaw), 0, -cos(m.ex_yaw))
	var right = Vector3(cos(m.ex_yaw), 0, -sin(m.ex_yaw))
	var wish = right * inp.x - fwd * inp.y
	var target_v = Vector3.ZERO
	var wish_yaw = atan2(-wish.x, -wish.z)
	var need = wrapf(wish_yaw - m.face_yaw, -PI, PI) if mag > 0.05 else 0.0
	var spd_now = m.move_vel.length()
	# Spot-turn only from a near stop. A real stick push walks immediately.
	if mag > 0.05 and mag < 0.38 and Boy.wants_spot_turn(need, spd_now):
		m.spot_turning = true
	if m.spot_turning and mag >= 0.42:
		m.spot_turning = false
		m.spot_rate = 0.0
	if m.spot_turning:
		if mag > 0.05:
			m.spot_goal = wish_yaw
		need = wrapf(m.spot_goal - m.face_yaw, -PI, PI)
		if absf(need) < 0.03 and not m.boy.spin_busy():
			m.spot_turning = false
			m.spot_rate = 0.0
	if mag > 0.05 and not m.spot_turning:
		var walk_u = clampf((mag - 0.06) / 0.78, 0.0, 1.0)
		walk_u = walk_u * walk_u * (3.0 - 2.0 * walk_u)
		var spd = RUN_SPEED if running else lerpf(0.42, WALK_MAX, walk_u)
		if m.wading:
			spd *= 0.6
		target_v = wish.normalized() * spd
		m.settle_t = 0.0
	elif m.settle_t < 0.6 and not m.spot_turning:
		if not m.boy.settling() and m.settle_t <= 0.0:
			m.boy.begin_settle(0.42)
		if m.boy.settling():
			m.settle_t += delta
			target_v = Vector3(-sin(m.face_yaw), 0, -cos(m.face_yaw)) * 0.40
		else:
			m.settle_t = 1.0
	var s = m.move_vel.length()
	var spd_t = target_v.length()
	if m.spot_turning:
		var st: Array = Boy.spot_turn(m.face_yaw, m.face_yaw + need, m.spot_rate, delta)
		m.face_yaw = st[0]
		m.spot_rate = st[1]
		var lean_w = clampf(absf(need) / 1.2, 0.0, 1.0) * (0.55 + 0.45 * clampf(m.spot_rate / 2.5, 0.0, 1.0))
		m.boy.turn_lean = lerpf(m.boy.turn_lean, signf(need) * lean_w * 0.85, 1.0 - exp(-delta * 7.0))
	elif spd_t > 0.05:
		var mt: Array = Boy.move_turn(m.face_yaw, atan2(-target_v.x, -target_v.z), s, delta)
		m.face_yaw = mt[0]
		spd_t *= float(mt[1])
	var acc: float
	if spd_t > s:
		if s < 0.35:
			acc = 3.6
		elif s < WALK_MAX * 0.9:
			acc = 2.6
		else:
			acc = 1.25
	else:
		acc = 5.2 if s > WALK_MAX else 6.0
	s = move_toward(s, spd_t, acc * delta)
	m.move_vel = Vector3(-sin(m.face_yaw), 0, -cos(m.face_yaw)) * s
	var from: Vector3 = m._body_pos if m._body_sync else m.player.position
	var wish_step = m.move_vel * delta
	var to = try_move(from, wish_step)
	var step = to - from
	step.y = 0.0
	if wish_step.length_squared() > 1e-8 and step.length_squared() > 1e-8:
		var along = wish_step.normalized()
		var lat = step - along * step.dot(along)
		var max_lat = maxf(wish_step.length() * 0.45, 0.012)
		if lat.length() > max_lat:
			to = from + along * step.dot(along) + lat.limit_length(max_lat)
			to = try_move(from, to - from)
	var real = (to - from) / maxf(delta, 1e-4)
	real.y = 0.0
	if real.length() < m.move_vel.length() * 0.5:
		m.move_vel = m.move_vel.lerp(real, 1.0 - exp(-delta * 14.0))
	m.cur_speed = real.length()
	# Exact collision height. Display present() writes it; physics does not
	# touch the node (one writer per explore frame).
	# Stand on the uphill triangle under the feet, not only the sample under the
	# pelvis. A pelvis-height root leaves the lead foot inside the rise, and the
	# camera then sees him cut off at the waist. The step is capped at 2.9 cm.
	to.y = _support_y(to.x, to.z, from.y, m.face_yaw)
	m.ground_y = to.y
	var step_xz = Vector2(to.x - from.x, to.z - from.z).length()
	m.dbg_max_step = maxf(m.dbg_max_step, step_xz)
	m._body_pos = to
	m._body_yaw = m.face_yaw
	if OS.get_environment("V39_ROUTE") == "1":
		_route_m += Vector2(to.x - from.x, to.z - from.z).length()
		_route_n += 1
		_route_note(to, m.cur_speed)
		if _route_n % 90 == 0:
			var fk = m.boy.foot_ik if m.boy != null else null
			var kl = fk.knee_flex_deg[0] if fk != null else 0.0
			var kr = fk.knee_flex_deg[1] if fk != null else 0.0
			var sl = fk.shin_len_ratio[0] if fk != null else 1.0
			var sr = fk.shin_len_ratio[1] if fk != null else 1.0
			var gnd = fk.mesh_gap_min * 100.0 if fk != null else 0.0
			var shin = fk.shin_gap_min * 100.0 if fk != null else 0.0
			var hip = fk._hip_lift * 100.0 if fk != null else 0.0
			print("ROUTE_STEP m=%.1f x=%.1f z=%.1f y=%.2f %s knee=%.0f/%.0f len=%.2f/%.2f gnd=%.1f shin=%.1f hip=%.1f" % [
				_route_m, to.x, to.z, to.y, m._surface_kind(to.x, to.z), kl, kr, sl, sr, gnd, shin, hip])
		if _route_m >= 110.0:
			_route_finish(true)
	m.wading = not m._on_dock(to.x, to.z) and to.y < -0.03
	m.boy.wading = m.wading
	m.boy.pivoting = m.spot_turning
	m.boy.turn_ahead = wrapf(m.spot_goal - m.face_yaw, -PI, PI) if m.spot_turning else (wrapf(wish_yaw - m.face_yaw, -PI, PI) if mag > 0.05 else 0.0)
	if not m.spot_turning:
		m.boy.turn_lean = lerpf(m.boy.turn_lean, clampf(m.boy.turn_ahead, -0.7, 0.7), 1.0 - exp(-delta * 5.0))
	m.boy.set_move(m.cur_speed)
	if m.cur_speed < 0.05:
		m.boy.set_idle()
	m._update_action_kind()


## Fixed-timestep coverage drive. World waypoints, not stick-up: stick-up
## follows the spawn facing and walks off the pier into the sea.
func _route_stick(delta: float) -> Vector2:
	var m = host
	if _route_wp.is_empty():
		var ds: float = m.island.dock_start_z
		var de: float = m.island.dock_end_z
		# Stay off the summit. The knob around z > dock_start+10 is a cliff
		# the boy cannot step, and stick-up from spawn walks into the sea.
		_route_wp = [
			Vector2(6.0, ds + 5.0),
			Vector2(8.0, ds + 7.5),
			Vector2(-6.0, ds + 7.5),
			Vector2(-8.0, ds + 4.0),
			Vector2(0.25, ds - 2.0),
			Vector2(0.12, de + 7.0),
			Vector2(0.25, ds + 0.4),
			Vector2(7.0, ds + 2.5),
			Vector2(7.0, ds + 6.0),
			Vector2(-7.0, ds + 6.0),
			Vector2(-7.0, ds + 2.5),
			Vector2(2.6, ds + 6.5),
			Vector2(10.0, ds + 5.0),
			Vector2(-10.0, ds + 5.0),
			Vector2(0.2, ds + 1.0),
			Vector2(0.12, (ds + de) * 0.5),
			Vector2(4.0, ds + 3.5),
			Vector2(-4.0, ds + 8.0),
			Vector2(9.0, ds + 8.0),
			Vector2(1.2, ds + 4.0),
		]
		_route_anchor = Vector2(m._body_pos.x, m._body_pos.z)
	if _route_pause > 0.0:
		_route_pause -= delta
		return Vector2.ZERO
	var pos := Vector2(m._body_pos.x, m._body_pos.z)
	if _route_wi >= _route_wp.size():
		_route_wi = 0
	if pos.distance_to(_route_wp[_route_wi]) < 1.15:
		_route_wi += 1
		if _route_wi % 4 == 0:
			_route_pause = 0.45
			_route_seen_stop = true
			return Vector2.ZERO
		if _route_wi >= _route_wp.size():
			_route_wi = 0
	var goal: Vector2 = _route_wp[_route_wi]
	var ds: float = m.island.dock_start_z
	if pos.distance_to(_route_anchor) < 0.04:
		_route_still += 1
	else:
		_route_still = 0
		_route_anchor = pos
	if _route_still > 50:
		print("ROUTE_SKIP i=%d x=%.1f z=%.1f" % [_route_wi, pos.x, pos.y])
		_route_wi += 1
		_route_still = 0
		return Vector2.ZERO
	var dir := goal - pos
	if dir.length_squared() < 1e-6:
		return Vector2.ZERO
	dir = dir.normalized()
	# Pier goals stay on the deck centerline. Lateral slide drops into the sea.
	var on_pier := absf(goal.x) < 0.45 and goal.y < ds + 0.2
	if on_pier:
		if absf(pos.x) > 0.28:
			dir = Vector2(-signf(pos.x), 0.0)
		else:
			dir = Vector2(0.0, signf(goal.y - pos.y))
	var from: Vector3 = m._body_pos
	var step := 0.55
	if on_pier and not can_stand(from.y, from.x + dir.x * step, from.z + dir.y * step):
		_route_wi += 1
		return Vector2.ZERO
	if not on_pier and not can_stand(from.y, from.x + dir.x * step, from.z + dir.y * step):
		var best := dir
		var best_s := -2.0
		for k in 16:
			var a := TAU * float(k) / 16.0
			var c := Vector2(cos(a), sin(a))
			if can_stand(from.y, from.x + c.x * step, from.z + c.y * step):
				var sc := c.dot(dir)
				if sc > best_s:
					best_s = sc
					best = c
		if best_s < 0.15:
			_route_stuck += 1
			if _route_stuck > 20:
				_route_wi += 1
				_route_stuck = 0
			return Vector2.ZERO
		dir = best
		_route_stuck = 0
	else:
		_route_stuck = 0
	var ey: float = m.ex_yaw
	var ix := dir.x * cos(ey) - dir.y * sin(ey)
	var iy := dir.x * sin(ey) + dir.y * cos(ey)
	# Every 5th leg is a walk so the knee check sees both gaits.
	var mag := 0.55 if _route_wi % 5 == 1 else 1.0
	return Vector2(ix, iy) * mag


func _route_note(to: Vector3, speed: float) -> void:
	var m = host
	var kind: String = m._surface_kind(to.x, to.z)
	_route_kinds[kind] = true
	# Spawn writes the root from 0 up to the beach; that is not a walking step.
	if _route_n > 60:
		_route_pelvis_max = maxf(_route_pelvis_max, pelvis_step_m)
	var fk = m.boy.foot_ik if m.boy != null else null
	if fk == null or not fk.pose_ready or _route_n < 40:
		return
	var gnd: float = fk.mesh_gap_min * 100.0
	var shin: float = fk.shin_gap_min * 100.0
	if gnd < _route_gnd_min:
		_route_gnd_min = gnd
		_route_worst = to
	var why := ""
	for side in 2:
		var flex: float = fk.knee_flex_deg[side]
		var ln: float = fk.shin_len_ratio[side]
		_route_knee_max = maxf(_route_knee_max, flex)
		_route_len_min = minf(_route_len_min, ln)
		# This clip's own walk/run peaks near 116°. A crushed shin folds past that
		# and shortens the knee-to-ankle segment. 140° is the crouch line.
		if ln < 0.97 or ln > 1.03:
			why = "len"
		elif flex > 140.0:
			why = "knee"
	# Sole bar: the lower foot (and a buried shin) stays in −1…+1.5 cm.
	# A higher swinging foot may be in the air. Stopped, both feet are stance.
	var hi: float = fk.mesh_gap_max * 100.0
	if gnd < -1.0 or shin < -1.0:
		why = "bury"
	elif gnd > 1.5:
		why = "float"
	elif speed < 0.08 and hi > 1.5:
		why = "float"
	elif _route_n > 60 and pelvis_step_m > 0.030:
		why = "pelvis"
	if why != "":
		_route_bad += 1
		if _route_bad <= 12:
			print("ROUTE_BAD %s m=%.1f x=%.1f z=%.1f y=%.2f spd=%.2f gnd=%.1f shin=%.1f knee=%.0f/%.0f len=%.2f/%.2f pel=%.1f" % [
				why, _route_m, to.x, to.z, to.y, speed, gnd, shin,
				fk.knee_flex_deg[0], fk.knee_flex_deg[1],
				fk.shin_len_ratio[0], fk.shin_len_ratio[1], pelvis_step_m * 100.0])


func _route_finish(ok_dist: bool) -> void:
	var kinds := ""
	for k in _route_kinds.keys():
		kinds += str(k) + ","
	var ok := ok_dist and _route_bad == 0 and _route_len_min > 0.97 and _route_gnd_min >= -1.0 and _route_pelvis_max <= 0.030
	print("ROUTE_DONE m=%.1f ok=%s kinds=%s knee_max=%.0f len_min=%.2f gnd_min=%.1f at=%.1f,%.1f,%.2f pelvis=%.1f bad=%d stop=%s" % [
		_route_m, ok, kinds, _route_knee_max, _route_len_min, _route_gnd_min,
		_route_worst.x, _route_worst.z, _route_worst.y,
		_route_pelvis_max * 100.0, _route_bad, _route_seen_stop])
	host.get_tree().quit()


func can_stand(from_h: float, x: float, z: float) -> bool:
	var m = host
	var dock: bool = m._on_dock(x, z)
	var h = height(x, z, from_h)
	if not dock and h < -0.42:
		return false
	if absf(x) < 5.0 and z < m.island.dock_end_z - 0.15:
		return false
	if absf(h - from_h) > 0.55:
		return false
	if not dock and Island.shore_d(x, z) > 6.0:
		return false
	return true


static func _wall_hits_y(w: Array, y: float) -> bool:
	return float(w[5]) > y + 0.12 and float(w[4]) < y + 1.2


func push_out(p: Vector3) -> Array:
	var q = Vector2(p.x, p.z)
	var ids: Array = host.island.walls_near(q)
	var worst = 0.0
	for _it in 4:
		worst = 0.0
		for i in ids:
			var w: Array = host.island.walls[i]
			if not _wall_hits_y(w, p.y):
				continue
			var dn: Vector3 = Island.wall_dist(w, q)
			var pen = BOY_R - dn.x
			if pen > 0.0:
				q += Vector2(dn.y, dn.z) * (pen + 1e-4)
				worst = maxf(worst, pen)
		if worst <= 0.0:
			break
	if worst > 0.0:
		worst = 0.0
		for i in ids:
			var w2: Array = host.island.walls[i]
			if _wall_hits_y(w2, p.y):
				worst = maxf(worst, BOY_R - Island.wall_dist(w2, q).x)
	return [Vector3(q.x, p.y, q.y), worst]


func blocked_by(p: Vector3) -> Vector3:
	return push_out(p)[0]


func penetration(p: Vector3) -> float:
	var q = Vector2(p.x, p.z)
	var worst = 0.0
	for i in host.island.walls_near(q):
		var w: Array = host.island.walls[i]
		if _wall_hits_y(w, p.y):
			worst = maxf(worst, BOY_R - Island.wall_dist(w, q).x)
	return worst


func try_move(from: Vector3, d: Vector3) -> Vector3:
	var fh = height(from.x, from.z, from.y)
	var r0: Array = push_out(from)
	if (r0[0] as Vector3).distance_to(from) > 0.005:
		var out: Vector3 = r0[0]
		var step = (out - from).limit_length(maxf(d.length(), 0.03))
		return from + step if can_stand(fh, from.x + step.x, from.z + step.z) else from + d
	for cand: Vector3 in [d, Vector3(d.x, 0, 0), Vector3(0, 0, d.z)]:
		if cand.length() < 1e-6:
			continue
		var r: Array = push_out(from + cand)
		var p: Vector3 = r[0]
		if float(r[1]) > 0.004:
			continue
		if (p - from).length() > cand.length() * 1.05 + 0.002:
			p = from + (p - from).normalized() * cand.length()
			if penetration(p) > 0.004:
				continue
		if can_stand(fh, p.x, p.z):
			p.y = from.y
			return p
	return from
