extends RefCounted
## Throw approach, aim, swipe and stone flight. Same behaviour as main.gd.

var m

func bind(host) -> void:
	m = host

func _enter_throw() -> void:
	m.mode = m.Mode.THROW
	m.state = m.State.READY
	m.move_vel = Vector3.ZERO
	# step to the nearest clear spot on the front edge of the T platform (between the posts)
	var p = m.player.position
	var best_x = 0.0
	for sx: float in [-2.1, 0.0, 2.1]:
		if absf(p.x - sx) < absf(p.x - best_x):
			best_x = sx
	m.throw_spot = Vector3(best_x, Island.DECK_Y + 0.04, m.island.dock_end_z + 0.85)
	m.throw_walk = Vector2(p.x - m.throw_spot.x, p.z - m.throw_spot.z).length() > 0.08
	m.aim_yaw = m.face_yaw
	var keep_yaw = m.player.rotation.y
	m.player_ctrl.write_position(m.throw_spot)
	if absf(wrapf(m.aim_yaw, -PI, PI)) > 1.2:
		m.aim_yaw = 0.0
	if not m._open_sea(m.aim_yaw):
		for k in range(1, 19):
			if m._open_sea(m.aim_yaw + k * 0.17):
				m.aim_yaw += k * 0.17
				break
			if m._open_sea(m.aim_yaw - k * 0.17):
				m.aim_yaw -= k * 0.17
				break
	m.player_ctrl.write_position(p)
	m.player_ctrl.write_yaw(keep_yaw)
	m.cam_aim_yaw = m.aim_yaw
	m._toast("打水漂！按住石头往海面划", 1.8)
	m._update_ui()

func _throw_walk_tick(delta: float) -> void:
	var d = m.throw_spot - m.player.position
	d.y = 0.0
	if d.length() < 0.04:
		m.player_ctrl.write_position(Vector3(m.throw_spot.x, m.player.position.y, m.throw_spot.z))
		m.throw_walk = false
		m.move_vel = Vector3.ZERO
		m.boy.set_move(0.0)
		m.boy.set_idle()
		return
	var spd = minf(1.1, d.length() * 3.0 + 0.35)
	m.move_vel = m.move_vel.move_toward(d.normalized() * spd, 8.0 * delta)
	var step = m.move_vel * delta
	if step.length() > d.length():
		step = d
	m.player_ctrl.write_position(m.player.position + (step))
	m.player_ctrl.write_position(Vector3(m.player.position.x, Island.DECK_Y + 0.04, m.player.position.z))
	m.player_ctrl.write_yaw(lerp_angle(m.player.rotation.y, atan2(-m.move_vel.x, -m.move_vel.z), 1.0 - exp(-delta * 10.0)))
	m.boy.set_move(m.move_vel.length())

func _leave_throw() -> void:
	if m.mode != m.Mode.THROW or m.state != m.State.READY:
		return
	m.mode = m.Mode.EXPLORE
	m.face_yaw = m.player.rotation.y
	m.ex_yaw = m.face_yaw + PI
	m.boy.set_idle()
	m._sync_body_pose(true)
	_hide_preview()
	m._update_ui()
# ------------------------------------------------------------------ explore: walking / running

func _throw_input(event: InputEvent) -> void:
	var now = Time.get_ticks_usec() / 1e6
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if m.state == m.State.READY and not m.throw_walk:
				_swipe_press(event.position, now)
		elif m.state == m.State.AIMING and m.aim_src == "swipe":
			_swipe_release(event.position, now)
	elif event is InputEventMouseMotion and m.state == m.State.AIMING and m.aim_src == "swipe":
		_swipe_move(event.position, now)
	elif event is InputEventKey and event.physical_keycode == KEY_SPACE and not event.echo:
		if event.pressed and m.state == m.State.READY and not m.throw_walk:
			_begin_aim(Vector2.ZERO, "key")
		elif not event.pressed and m.state == m.State.AIMING and m.aim_src == "key":
			m.throw_spin = m.KEY_SPIN
			_throw()

## arrow keys / A D aim, W S (or up / down) the launch elevation, Q E the stone's tilt; hold space to charge

func _throw_keys(delta: float) -> void:
	if m.mode != m.Mode.THROW or m.throw_walk or not (m.state == m.State.READY or (m.state == m.State.AIMING and m.aim_src == "key")):
		return
	var k = func(a: Key, b: Key) -> float: return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0
	var turn: float = k.call(KEY_LEFT, KEY_A) - k.call(KEY_RIGHT, KEY_D)
	var el: float = k.call(KEY_UP, KEY_W) - k.call(KEY_DOWN, KEY_S)
	var tl: float = k.call(KEY_E, KEY_PAGEUP) - k.call(KEY_Q, KEY_PAGEDOWN)
	if turn != 0.0:
		m.aim_yaw = clampf(m.aim_yaw + turn * 0.8 * delta, -m.AIM_LIM, m.AIM_LIM)
	if el != 0.0 or tl != 0.0:
		m.key_angles += Vector2(el * 14.0, tl * 16.0) * delta
		_set_angles(m.aim_pitch + m.key_angles.x, m.aim_tilt + m.key_angles.y)
		# whole degrees, but holding the key keeps creeping
		m.key_angles -= Vector2(roundf(m.key_angles.x), roundf(m.key_angles.y))
	else:
		m.key_angles = Vector2.ZERO

func _set_angles(el: float, tilt: float) -> void:
	m.aim_pitch = clampf(roundf(el), m.EL_MIN, m.EL_MAX)
	m.aim_tilt = clampf(roundf(tilt), 0.0, m.TILT_MAX)
	m.el_slider.set_value(m.aim_pitch)
	m.tilt_slider.set_value(m.aim_tilt)

## scripted / keyboard charge: the power bar ping-pongs while held (POWER_CYCLE)

func _begin_aim(p: Vector2, src = "script") -> void:
	m.state = m.State.AIMING
	m.aim_src = src
	m.press_pos = p
	m.charge_t = 0.0
	m.power = 0.0
	m.yaw_at_press = m.aim_yaw
	m._update_ui()

func _swipe_unit() -> float:
	var vs = m.get_viewport().get_visible_rect().size
	return minf(vs.x, vs.y)

func _swipe_press(p: Vector2, t: float) -> void:
	m.state = m.State.AIMING
	m.aim_src = "swipe"
	m.press_pos = p
	m.swipe_hist = [[t, p]]
	m.swipe_d = Vector2.ZERO
	m.charge_t = 0.0
	m.power = 0.0
	m.yaw_at_press = m.aim_yaw
	m.view_at_press = m.cam_aim_yaw
	m._update_ui()

func _swipe_move(p: Vector2, t: float) -> void:
	m.swipe_hist.append([t, p])
	m.swipe_move_frame = Engine.get_process_frames()
	while m.swipe_hist.size() > 3 and t - float(m.swipe_hist[1][0]) > 0.5:
		m.swipe_hist.pop_front()
	_apply_swipe(p - m.press_pos)

func _swipe_release(p: Vector2, t: float) -> void:
	# a slow device can hand over the lift a frame after the finger's last move: it left the glass moving
	var last: Array = m.swipe_hist[m.swipe_hist.size() - 1]
	if m.swipe_hist.size() > 1 and Engine.get_process_frames() - m.swipe_move_frame <= 1 and p.distance_to(last[1]) < _swipe_unit() * 0.02:
		t = minf(t, float(last[0]))
	m.swipe_hist.append([t, p])
	var fl = _flick(m.swipe_hist)
	_apply_swipe(fl[1] if fl[1] != null else p - m.press_pos)
	m.throw_spin = fl[0]
	_throw()

## power from the swipe's length, aim from its direction; pointing back towards the kid means "cancel"

func _apply_swipe(d: Vector2) -> void:
	m.swipe_d = d
	var unit = _swipe_unit()
	if d.y > unit * 0.03 or d.length() < unit * m.SWIPE_DEAD:
		m.power = 0.0
		m.aim_yaw = m.yaw_at_press
		return
	m.power = clampf((d.length() - unit * m.SWIPE_DEAD) / (unit * m.SWIPE_FULL), 0.0, 1.0)
	# at most 70 deg off straight up: a sideways swipe is not a throw along the dock
	var a = atan2(d.x, -d.y)
	if absf(a) > deg_to_rad(70.0):
		var c = signf(a) * deg_to_rad(70.0)
		d = Vector2(sin(c), -cos(c)) * d.length()
	m.aim_yaw = _swipe_yaw(d)

## The swipe's angle off straight up is the aim's angle off the view line the camera had when the finger
## went down (it sits right behind the release point). A true screen-to-water projection would squeeze a
## 30 deg swipe into ~7 deg near the horizon, which feels dead under the thumb.

func _swipe_yaw(d: Vector2) -> float:
	return clampf(wrapf(m.view_at_press - atan2(d.x, -d.y), -PI, PI), -m.AIM_LIM, m.AIM_LIM)

## Spin from how fast the finger was going when it let go (over the last ~90 ms). A finger that rested on
## an aim and then flicked (within ~0.2 s) throws the aim it rested on, so aiming carefully and then
## flicking works as well as one quick swipe. Returns [spin 0.2..1, the rested swipe vector or null].

func _flick(hist: Array) -> Array:
	var unit = _swipe_unit()
	var n = hist.size()
	var t1: float = hist[n - 1][0]
	var p1: Vector2 = hist[n - 1][1]
	var j = n - 1
	while j > 0 and t1 - float(hist[j - 1][0]) <= 0.09:
		j -= 1
	# a slow frame can hand over a whole flick at once (moves merged, all stamped with the same time): measure
	# from the sample before it, as if that was at most 50 ms ago
	var dt = t1 - float(hist[j][0])
	if dt < 1.0 / 240.0 and j > 0:
		j -= 1
		dt = minf(t1 - float(hist[j][0]), 0.05)
	var speed = 0.0
	if j < n - 1:
		speed = (p1 - (hist[j][1] as Vector2)).length() / maxf(dt, 1.0 / 120.0) / unit
	var s = clampf(0.2 + 0.8 * smoothstep(0.6, 3.2, speed), 0.2, 1.0)
	var held: Variant = null
	if speed > 1.5:
		for k in range(n - 1, 0, -1):
			var a: Array = hist[k - 1]
			var b: Array = hist[k]
			var v = ((b[1] as Vector2) - (a[1] as Vector2)).length() / maxf(float(b[0]) - float(a[0]), 1e-3) / unit
			if v < 0.5:
				var hd: Vector2 = (a[1] as Vector2) - m.press_pos
				if t1 - float(a[0]) < 0.22 and hd.length() > unit * 0.12 and hd.y < 0.0:
					held = hd
				break
	return [s, held]

# ------------------------------------------------------------------ physics
# After Clanet, Hersen & Bocquet, "Secrets of successful stone-skipping" (Nature 2004): the stone's own tilt
# to the water (attack angle) works best near 20 deg; its flight path must come in low (the steepest entry
# that still bounces shrinks for a badly tilted, slow or spin-less stone); every bounce costs a roughly fixed
# amount of kinetic energy (so the number of skips grows with the speed squared), more for a badly tilted
# stone; spin keeps the tilt steady - without it the stone wobbles and pitches up a little at each bounce.

func _aim_dir() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.UP, m.aim_yaw)

## where the stone leaves the kid's hand (the release key pose, power independent)

func _hand_pos() -> Vector3:
	return _ideal_hand(m.aim_yaw)

## the release point if he faced `yaw` (the throw turns him square to the aim before the release)

func _ideal_hand(yaw: float) -> Vector3:
	var b = Basis(Vector3.UP, yaw).scaled(m.player.global_basis.get_scale())
	return m.player.global_position + b * m.boy.release_local

func _initial_velocity() -> Vector3:
	var dir = _aim_dir()
	# half-kneeling: lower release, flatter angle, a little less power
	var crouch = m.boy.stance == "crouch"
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(m.aim_pitch - (1.0 if crouch else 0.0)))
	return dir * m.launch_speed(m.power) * (0.92 if crouch else 1.0)

func _throw() -> void:
	if m.power < 0.04:
		m.state = m.State.READY
		m.boy.set_idle()
		_hide_preview()
		m._update_ui()
		return
	if m.aim_src == "script":
		m.throw_spin = m.launch_spin(m.power)
	# the swing starts now; the stone leaves the hand on the release frame (Boy.released -> _launch)
	m.state = m.State.THROWING
	m.boy.start_throw(m.power)
	m._play("whoosh", lerpf(-13.0, -3.0, m.power), lerpf(0.85, 1.15, m.power) * m.rng.randf_range(0.96, 1.04))
	_hide_preview()
	m._update_ui()

func _hide_preview() -> void:
	for d in m.preview_dots:
		d.visible = false
	m.preview_ring.visible = false

func _launch() -> void:
	if m.state != m.State.THROWING:
		return
	m.state = m.State.FLYING
	m.fly_t = 0.0
	m.stone_pos = _hand_pos()
	m.throw_origin = m.stone_pos
	m.stone_vel = _initial_velocity()
	m.spin = clampf(m.throw_spin * m.rng.randf_range(0.95, 1.03), 0.1, 1.0)
	m.stone_tilt = m.aim_tilt + m.rng.randf_range(-1.5, 1.5)
	m.launch_spin_v = m.spin
	m.first_entry = -1.0
	m.spin_ang = 0.0
	m.skips = 0
	m.throw_dist = 0.0
	m.stone.position = m.stone_pos
	m.stone.visible = true
	m.demo_release_pending = 1
	m._update_ui()

func _hdist(p: Vector3) -> float:
	return Vector2(p.x - m.throw_origin.x, p.z - m.throw_origin.z).length()

func _hit_test(p: Vector3) -> String:
	var gh = Island.ground_h(p.x, p.z)
	if gh > -0.05 and p.y <= gh + 0.06:
		return "石头落在沙滩上了"
	# dock deck
	if p.y < Island.DECK_Y + 0.06 and p.y > Island.DECK_Y - 0.25:
		if (absf(p.x) < 1.2 and p.z < m.island.dock_start_z and p.z > m.island.dock_end_z) or (absf(p.x) < 3.1 and p.z < m.island.dock_end_z + 3.9 and p.z > m.island.dock_end_z - 0.1):
			return "咚！砸到码头上了"
	for o in m.island.obstacles:
		var c: Vector2 = o[0]
		if p.y < float(o[2]) and p.y > float(o[4]) - 0.5 and Vector2(p.x - c.x, p.z - c.y).length() < float(o[1]) + 0.08:
			return "砰！撞到了%s" % o[3]
	return ""

func _step_stone(dt: float) -> void:
	m.stone_vel.y -= m.GRAVITY * dt
	m.stone_pos += m.stone_vel * dt
	_orient_stone(dt)
	if _hdist(m.stone_pos) > 1.0:
		var hit = _hit_test(m.stone_pos)
		if hit != "":
			m._hit_sound(hit)
			m.throw_dist = _hdist(m.stone_pos)
			m.result_text = hit + ("" if m.skips == 0 else "（之前漂了 %d 下）" % m.skips)
			m.last_tip = "朝开阔的海面瞄准"
			m.stone_vel = Vector3(0, -1.0, 0)
			m.state = m.State.SINKING
			m.sink_timer = 0.6
			if m.stone_pos.y < 0.3:
				m._splash(Vector3(m.stone_pos.x, 0.0, m.stone_pos.z), 0.6, false, Vector3.ZERO)
				m._play("sink", -8.0, m.rng.randf_range(1.0, 1.15))
			return
	if m.stone_pos.y <= 0.02 and m.stone_vel.y < 0.0:
		m.stone_pos.y = 0.02
		var res = m.water_contact(m.stone_vel, m.spin, m.stone_tilt, m.rng.randf_range(-1, 1))
		m.throw_dist = _hdist(m.stone_pos)
		if m.first_entry < 0.0:
			m.first_entry = res[4]
		if res[0]:
			m.skips += 1
			m.stone_vel = res[1]
			m.spin = res[2]
			m.stone_tilt = res[3]
			m._splash(m.stone_pos, 0.55, false, m.stone_vel)
			m._skip_sound(Vector2(m.stone_vel.x, m.stone_vel.z).length())
			m._float_text(m.stone_pos, "%d" % m.skips)
			if m.skips == 5:
				m._toast("5 连跳！")
				m._play("combo", -6.0)
			elif m.skips == 10:
				m._toast("10 连跳！太强了！")
				m._play("combo", -5.0, 1.12)
			elif m.skips == 15:
				m._toast("15 连跳！水漂大师！")
				m._play("combo", -4.0, 1.26)
			elif m.skips == 20:
				m._toast("20 连跳！完美！")
				m._play("combo", -3.0, 1.4)
			for bn in m.island.buoys:
				if Vector2(m.stone_pos.x - bn.position.x, m.stone_pos.z - bn.position.z).length() < 2.0:
					m._toast("擦过浮标！")
		else:
			m._splash(m.stone_pos, 1.2, true, Vector3.ZERO)
			m._play("sink", -2.0 + m.rng.randf_range(-1.0, 1.0), m.rng.randf_range(0.92, 1.06))
			_judge(res[5], res[4])
			m.state = m.State.SINKING
			m.sink_timer = 0.0
	elif m.state == m.State.FLYING and m.skips > 0:
		m.throw_dist = max(m.throw_dist, _hdist(m.stone_pos))
	m._update_ui()

## the stone flies nose-up by its tilt and spins flat about its own axis; with little spin it wobbles

func _orient_stone(dt: float) -> void:
	m.stone.position = m.stone_pos
	m.spin_ang += m.spin * 40.0 * dt
	var f = Vector3(m.stone_vel.x, 0, m.stone_vel.z)
	if f.length() < 0.1:
		f = _aim_dir()
	var wob = (1.0 - m.spin) * 0.35 * sin(m.fly_t * 9.0)
	var b = Basis(Vector3.UP, atan2(-f.x, -f.z)) * Basis(Vector3.RIGHT, deg_to_rad(m.stone_tilt)) \
		* Basis(Vector3.FORWARD, wob) * Basis(Vector3.UP, m.spin_ang)
	m.stone.basis = b * Basis.from_scale(Vector3(0.7, 0.24, 0.6))

## when the stone goes under: the toast says what happened, the hint bar keeps a quiet tip for the next go

func _judge(why: String, ang: float) -> void:
	var tip = ""
	var tilt = m.aim_tilt
	if m.skips == 0:
		match why:
			"tilt":
				m.result_text = "扑通！石头倾角太陡，一头扎进水里"
				tip = "倾角 20° 左右最好"
			"flat":
				m.result_text = "啪！石头太平，拍在水面上停住了"
				tip = "倾角调到 20° 左右：前端微微翘起"
			"slow":
				m.result_text = "扑通！速度不够，沉了"
				tip = "往海面划得更长 = 更用力"
			_:
				m.result_text = "扑通！入水角 %d°，太陡了" % roundi(ang)
				if tilt < 10.0 or tilt > 32.0:
					tip = "倾角 %d° 不合适，调到 20° 左右" % roundi(tilt)
				elif m.aim_pitch > 10.0:
					tip = "出手仰角 %d° 太高，放低一点" % roundi(m.aim_pitch)
				elif m.power < 0.6:
					tip = "划得更长、更用力，石头飞得更平"
				elif m.launch_spin_v < 0.45:
					tip = "松手时顺势快甩，转起来的石头更稳"
				else:
					tip = "试试半蹲，出手更低"
	else:
		m.result_text = "漂了 %d 下！" % m.skips
		if m.launch_spin_v < 0.45:
			tip = "旋转不足：松手时顺势快速一甩"
		elif tilt < 12.0:
			tip = "倾角偏平：跳得矮、停得快，20° 左右最好"
		elif tilt > 28.0:
			tip = "倾角偏陡：每跳都损失很多速度"
		elif m.first_entry > 22.0:
			tip = "入水偏陡（%d°），放低仰角会跳得更多" % roundi(m.first_entry)
		elif m.power < 0.7:
			tip = "多用点力，跳得更多"
		elif m.skips >= 15:
			tip = "完美的一甩！"
	m.last_tip = "上一投：入水 %d° · 倾角 %d° · 旋转 %d%%" % [roundi(maxf(m.first_entry, 0.0)), roundi(tilt), roundi(m.launch_spin_v * 100.0)]
	if tip != "":
		m.last_tip += "\n" + tip

func _finish() -> void:
	m.stone.visible = false
	var rec = false
	if m.skips > m.best_skips:
		m.best_skips = m.skips
		rec = true
	if m.throw_dist > m.best_dist and m.skips > 0:
		m.best_dist = m.throw_dist
		rec = true
	if rec:
		m._save_best()
		m._play("record", -4.0)
	m._toast(m.result_text + ("\n新纪录！" if rec else "") + "\n%.1f 米" % m.throw_dist, 3.0)
	m.state = m.State.READY
	if m.skips >= 5 or (rec and m.skips > 0):
		m.boy.react("cheer")
	elif m.skips == 0:
		m.boy.react("oops")
	else:
		m.boy.react("")
	m.finish_hold = 1.2
	m._update_ui()

