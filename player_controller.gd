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


func setup(p_ground: Ground, p_host: Node = null) -> void:
	ground = p_ground
	host = p_host


func bind_host(p_host: Node) -> void:
	host = p_host


func height(x: float, z: float, hint_y: float = 10.0) -> float:
	if ground == null:
		return hint_y
	return ground.height(x, z, hint_y)


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
	p.y = height(p.x, p.z, host._body_pos.y)
	pelvis_step_m = absf(p.y - prev_y)
	host.player.global_position = p
	host.player.rotation.y = lerp_angle(host._body_yaw_prev, host._body_yaw, f)
	host.ground_y = p.y


func physics_step(delta: float) -> void:
	var m = host
	var inp: Vector2 = m.joy.read_move(m.demo_mode, m.demo_input) if m.joy != null else Vector2.ZERO
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
	to.y = height(to.x, to.z, from.y)
	m.ground_y = to.y
	var step_xz = Vector2(to.x - from.x, to.z - from.z).length()
	m.dbg_max_step = maxf(m.dbg_max_step, step_xz)
	m._body_pos = to
	m._body_yaw = m.face_yaw
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
