extends RefCounted
## Offline demo and screenshot sequences. Same behaviour as main.gd.

var m

func bind(host) -> void:
	m = host

func _run_sim_report() -> void:
	for stc in ["stand", "crouch"]:
		m.boy.stance = stc
		print("SIM stance ", stc, " release ", m.boy.release_local)
		_sim_block()
	m.boy.stance = "stand"
	for line in sim_sweeps():
		print("SIM sweep ", line)
	print("SIM obstacles=%d palms=%d" % [m.island.obstacles.size(), m.island.palm_spots.size()])
	# gait stress test (dev/ is not exported, so only where the sources are)
	if ResourceLoader.exists("res://dev/gait_probe.gd"):
		for line in load("res://dev/gait_probe.gd").stress(m):
			print("SIM ", line)
	if ResourceLoader.exists("res://dev/hat_probe.gd"):
		var hs: Array = load("res://dev/hat_probe.gd").sim(m)
		for line: String in hs[0]:
			print("SIM ", line)
		print("SIM hat stays on the head: %s (worst offset from its seat %.3f mm)" % ["yes" if hs[2] else "NO", float(hs[1]) * 1000.0])
	_walk_metrics_report()

## gait kinematics at the walking and running speeds (dev/walk_metrics.gd)

func _walk_metrics_report() -> void:
	if not ResourceLoader.exists("res://dev/walk_metrics.gd"):
		return
	# Tripo Mixamo bone names don't match the procedural game_engine profile walk_metrics expects
	if m.boy.meta.get("tripo", false):
		print("SIM gait metrics skipped — Tripo Mixamo (no game_engine bone map)")
		return
	for sp: Array in [["stroll", 0.55], ["walk 0.85", 0.85], ["walk", 1.15], ["run", 2.7]]:
		var r: Array = load("res://dev/walk_metrics.gd").measure(m, float(sp[1]))
		for line: String in r[0]:
			print("SIM gait %s  %s" % [sp[0], line])

func _sim_block() -> void:
	m.aim_yaw = 0.0
	m.aim_tilt = m.TILT_BEST
	for pw in [0.5, 0.7, 0.85, 1.0]:
		for pitch in [0.0, 5.0, 10.0]:
			m.power = pw
			m.aim_pitch = pitch
			var r = m.simulate(m._hand_pos(), m._initial_velocity(), m.launch_spin(pw), m.aim_tilt)
			print("SIM power=%.2f pitch=%4.1f skips=%2d dist=%5.1f entry=%4.1f" % [pw, pitch, r["skips"], r["dist"], r["entry"]])

## one swept throw setting from the standing release: {skips, dist, entry, why}

func sim_throw(pw: float, el: float, tilt: float, s: float, stance = "stand") -> Dictionary:
	var keep = [m.boy.stance, m.power, m.aim_pitch, m.aim_yaw]
	m.boy.stance = stance
	m.power = pw
	m.aim_pitch = el
	m.aim_yaw = 0.0
	var r = m.simulate(m._hand_pos(), m._initial_velocity(), s, tilt)
	m.boy.stance = keep[0]; m.power = keep[1]; m.aim_pitch = keep[2]; m.aim_yaw = keep[3]
	return r

## the angle sweeps: launch elevation, stone tilt and spin each change the skips (full power, standing)

func sim_sweeps() -> Array[String]:
	var out: Array[String] = []
	for row: Array in [["elevation", [-5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0]], ["tilt", [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0]],
			["spin", [0.2, 0.4, 0.6, 0.8, 1.0]], ["power", [0.2, 0.4, 0.6, 0.8, 1.0]]]:
		for x: float in row[1]:
			var r: Dictionary
			match row[0]:
				"elevation": r = sim_throw(1.0, x, m.TILT_BEST, 1.0)
				"tilt": r = sim_throw(1.0, 4.0, x, 1.0)
				"spin": r = sim_throw(1.0, 4.0, m.TILT_BEST, x)
				_: r = sim_throw(x, 4.0, m.TILT_BEST, 1.0)
			out.append("%-9s %5.1f  skips=%2d  dist=%5.1f m  entry=%4.1f deg  %s" % [row[0], x, r["skips"], r["dist"], r["entry"],
				("sank: " + str(r["why"])) if r["why"] != "slow" or r["skips"] == 0 else "ran out of speed"])
	return out

func _demo_shot(name: String) -> void:
	if m.demo_shots.has(name):
		return
	m.demo_shots[name] = true
	var prefix = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotprefix="):
			prefix = a.substr(13)
	var img = m.get_viewport().get_texture().get_image()
	var path = ProjectSettings.globalize_path("res://screenshots/%s/%s%s.png" % [m.shot_dir, prefix, name])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			path = a.substr(10).path_join(prefix + name + ".png")
	img.save_png(path)
	print("DEMO screenshot ", path)

# ------------------------------------------------------------------ v4/v5 scripted demo (screenshots / video)
# godot --path . --fixed-fps 30 --resolution 1280x720 -- --demo4 [--portrait] [--shotdir=/abs/dir]
# godot --path . --fixed-fps 30 --write-movie x.avi -- --video4=walk|throw|sleep|sun|getup|gait|prints

func _wait(sec: float) -> void:
	var t0 = m.gt
	while m.gt - t0 < sec:
		await m.get_tree().process_frame

func _walk_to(target: Vector3, run: bool, timeout = 14.0) -> void:
	m.walk_gen += 1
	var my = m.walk_gen
	m.demo_run = run
	var t0 = m.gt
	while m.gt - t0 < timeout:
		if my != m.walk_gen:
			return
		var d = target - m.player.position
		d.y = 0.0
		if d.length() < 0.35:
			break
		var fwd = Vector3(-sin(m.ex_yaw), 0, -cos(m.ex_yaw))
		var right = Vector3(cos(m.ex_yaw), 0, -sin(m.ex_yaw))
		var dn = d.normalized()
		m.demo_input = Vector2(dn.dot(right), -dn.dot(fwd)) * (1.0 if run else 0.72)
		await m.get_tree().process_frame
	if my == m.walk_gen:
		m.demo_input = Vector2.ZERO
		m.demo_run = false

func _hd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _stop_walk() -> void:
	m.walk_gen += 1
	m.demo_input = Vector2.ZERO
	m.demo_run = false

func _place(p: Vector3, yaw: float) -> void:
	_stop_walk()
	m.toast_timer = 0.0
	m.lbl_toast.modulate.a = 0.0
	p.y = m._surface(p.x, p.z)
	m.player_ctrl.write_position(p)
	m.ground_y = p.y
	m.face_yaw = yaw
	m.player_ctrl.write_yaw(yaw)
	m.move_vel = Vector3.ZERO
	m._sync_body_pose(true)
	m._cam_slide = 0.0
	m._cam_slide_want = 0.0
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._snap_explore_cam()
	m._update_action_kind()

func _track(yaw_off: float, pitch: float, dist: float, h: float) -> void:
	m.demo_cam = true
	m.demo_track = [yaw_off, pitch, dist, h]

func _free_cam() -> void:
	m.demo_cam = false
	m.demo_track = []

func _fixed_cam(target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	m.demo_cam = true
	m.demo_track = []
	m.cam_target = target; m.cam_yaw = yaw; m.cam_pitch = pitch; m.cam_dist = dist

func _shot(name: String) -> void:
	if m.demo_seg == "":
		_demo_shot(name)

func _throw_sequence(pre: String, crouch: bool, close: bool) -> void:
	_place(Vector3(0.3, 0, m.island.dock_end_z + 1.6), 0.1)
	await _wait(0.5)
	_shot(pre + "dock_ui")
	m._enter_throw()
	m.boy.stance = "crouch" if crouch else "stand"
	m._toast("半蹲投掷：出手更低、贴着水面" if crouch else "站立投掷", 1.4)
	m._update_ui()
	await _wait(1.3)
	_shot(pre + "throw_ready")
	m._begin_aim(Vector2.ZERO)
	m.aim_pitch = 3.0
	var t0 = m.gt
	while m.gt - t0 < 1.5:
		m.charge_t = minf((m.gt - t0) / 1.1, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
		if m.demo_seg != "":
			m.aim_yaw = 0.1 + sin((m.gt - t0) * 2.0) * 0.05
		await m.get_tree().process_frame
	_shot(pre + "charge_game")
	if close:
		_fixed_cam(m.player.global_position + Vector3(0, 0.45, 0) + m._aim_dir() * 0.2, m.aim_yaw + 1.45, 0.08, 2.4)
		await _wait(0.25)
		m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
		_shot(pre + "crouch_charge_side" if crouch else pre + "stand_charge_side")
	m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
	m._throw()
	while m.state == m.State.THROWING:
		await m.get_tree().process_frame
	await m.get_tree().process_frame
	_shot(pre + ("crouch_release" if crouch else "stand_release"))
	while m.boy.anim == "throw" and m.boy.anim_t < 0.5:
		await m.get_tree().process_frame
	_shot(pre + ("crouch_follow" if crouch else "stand_follow"))
	_free_cam()
	m.fly_t = 0.0
	while m.state == m.State.FLYING and m.skips < 4:
		await m.get_tree().process_frame
	await _wait(0.2)
	_shot(pre + "skipping")
	while m.state != m.State.READY:
		await m.get_tree().process_frame
	await _wait(0.9)
	_shot(pre + "result")
	await _wait(1.0)
	_shot(pre + "result_b")
	await _wait(1.4)
	_shot(pre + "result_c")

func _rest_sequence(pre: String, kind: String, close: bool) -> void:
	if kind == "sleep":
		var hs = m._hammock_spot()
		var bed: Vector3 = hs[0]
		var side: Vector3 = hs[2]
		var p = bed + side * 1.6
		_place(p, atan2(side.x, side.z))
	else:
		var td = m.island.towel_dir
		var sd = td.cross(Vector3.UP).normalized()
		var p2 = m.island.towel_pos + sd * 1.4 + td * 0.6
		_place(p2, atan2(sd.x, sd.z))
	await _wait(0.6)
	_shot(pre + kind + "_prompt")
	m._begin_rest(kind)
	while m.rest_phase < 3:
		await m.get_tree().process_frame
	_shot(pre + kind + "_seated")
	await _wait(0.45)
	_shot(pre + kind + "_lying_down")
	while m.rest_phase < 4:
		await m.get_tree().process_frame
	await _wait(2.4)
	_shot(pre + kind + "_rest")
	if close:
		var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
		var off = m.rest_side
		if kind == "sun":
			off = (m.island.towel_dir * 0.8 + m.rest_side * 0.6).normalized()
		_fixed_cam(head + Vector3(0, -0.05, 0), atan2(off.x, off.z) + (0.3 if kind == "sleep" else 0.0), 0.75 if kind == "sleep" else 0.6, 1.25)
		await _wait(0.3)
		_shot(pre + kind + "_close")
		var pel: Vector3 = (m.boy.parts["pelvis"] as Node3D).global_position
		_fixed_cam(pel + Vector3(0, 0.1, 0), atan2(off.x, off.z) - 0.2, 0.55, 2.3)
		await _wait(0.3)
		_shot(pre + kind + "_body")
		_free_cam()

## the sea along the beach: shallows, seabed, foam lines (high 3/4 view like the game, low and wide)

func _shore_sequence(pre: String) -> void:
	for th: float in [-1.05, 2.2]:
		var tag = "a" if th < 0.0 else "b"
		var sea = Island.dir_at(th)
		var p = m.island.shore_pt(th, 0.9)
		var along = sea.cross(Vector3.UP)
		_place(p, atan2(-sea.x, -sea.z) + 0.5)
		await _wait(0.6)
		_fixed_cam(p + sea * 2.2 + Vector3(0, 0.2, 0), atan2(sea.x, sea.z) + 0.55, 0.72, 7.0)
		await _wait(0.4)
		_shot(pre + "13%s_shore_top" % tag)
		_fixed_cam(p + sea * 1.2 + Vector3(0, 0.4, 0), atan2(along.x, along.z) - 0.5, 0.2, 5.0)
		await _wait(0.4)
		_shot(pre + "14%s_shore_low" % tag)
		_fixed_cam(p + sea * 3.0, atan2(sea.x, sea.z) - 0.6, 0.5, 14.0)
		await _wait(0.4)
		_shot(pre + "15%s_shore_wide" % tag)
		_free_cam()
	var wp = m.island.shore_pt(-1.2, -1.3)
	_place(wp, 0.4)
	_walk_to.call(m.island.shore_pt(-1.35, -1.1), false)
	await _wait(1.2)
	_shot(pre + "16_wading")
	_stop_walk()

## v8 stills: the doodled sign, the campfire, sitting on the bench / log / lounger, throw reach

func _v8_sequence(pre: String) -> void:
	var sb = m.island.sign_board
	var sn = sb.global_basis.z.normalized()
	var sc = sb.global_position
	_place(sc + sn * 2.6 + Vector3(0.8, 0, 0), 0.0)
	_fixed_cam(sc + Vector3(0, -0.05, 0), atan2(sn.x, sn.z) + 0.12, 0.08, 1.45)
	await _wait(0.5)
	_shot(pre + "20_sign_close")
	_fixed_cam(sc + Vector3(0, -0.55, 0), atan2(sn.x, sn.z) + 0.5, 0.1, 3.0)
	await _wait(0.4)
	_shot(pre + "21_sign_post")
	_fixed_cam(sc + Vector3(0, -0.05, 0), atan2(-sn.x, -sn.z) - 0.2, 0.1, 1.6)
	await _wait(0.4)
	_shot(pre + "22_sign_back")
	# campfire close and with the kid on a log
	var c = m.island.campfire_pos
	_place(c + Vector3(3.5, 0, 3.5), 0.0)
	_fixed_cam(c + Vector3(0, 0.45, 0), 0.6, 0.22, 2.4)
	await _wait(1.0)
	_shot(pre + "23_fire_close")
	_fixed_cam(c + Vector3(0, 0.3, 0), 2.0, 0.42, 5.5)
	await _wait(0.3)
	_shot(pre + "24_fire_wide")
	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		var face: Vector3 = st["face"]
		_place((st["approach"] as Vector3) + face * 0.9, atan2(face.x, face.z))
		_free_cam()
		await _wait(0.4)
		_shot(pre + "25_seat_prompt_%d" % i)
		m._on_action()
		while m.rest_phase < 4:
			await m.get_tree().process_frame
		await _wait(1.6)
		_shot(pre + "26_seat_%d" % i)
		m._wake()
		while m.mode != m.Mode.EXPLORE:
			await m.get_tree().process_frame
	# throw: the arm reaching out after the release, gameplay camera and from the side
	for crouch: bool in [false, true]:
		for side: bool in [false, true]:
			_place(Vector3(0.2, 0, m.island.dock_end_z + 1.5), 0.0)
			await _wait(0.2)
			m._enter_throw()
			m.boy.stance = "crouch" if crouch else "stand"
			await _wait(1.3)
			if side:
				m.demo_cam = true
				m.demo_track = [m.aim_yaw + PI * 0.5 + 0.1, 0.1, 2.5, 0.55 if not crouch else 0.4, true]
			m._begin_aim(Vector2.ZERO)
			m.aim_pitch = 3.0
			m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
			await _wait(1.0)
			m._throw()
			var tag = ("crouch" if crouch else "stand") + ("_side" if side else "_game")
			for k: Array in [[0.0, "a_cock"], [0.15, "b_release"], [0.21, "c_reach"], [0.32, "d_sweep"], [0.46, "e_wrap"]]:
				while m.boy.anim_t < float(k[0]) - 0.001:
					await m.get_tree().process_frame
				_shot(pre + "27_throw_%s_%s" % [tag, k[1]])
			_free_cam()
			while m.state != m.State.READY:
				await m.get_tree().process_frame
			m._leave_throw()
			await _wait(0.6)

## v9 stills: shore water through a surf cycle, wading close-ups, lying on the bench / a log, night.
## part "" = all, or one of shore / wade / lie / night

func _v9_sequence(pre: String, part: String) -> void:
	if part == "" or part == "shore":
		for th: float in [-1.05, 2.2]:
			var tag = "a" if th < 0.0 else "b"
			var sea = Island.dir_at(th)
			var p = m.island.shore_pt(th, 1.4)
			var along = sea.cross(Vector3.UP)
			_place(p, atan2(-sea.x, -sea.z) + 0.5)
			await _wait(0.4)
			for k in 4:
				_fixed_cam(p + sea * 1.6 + Vector3(0, 0.2, 0), atan2(sea.x, sea.z) + 0.55, 0.62, 5.0)
				await _wait(0.05)
				_shot(pre + "30%s_shore_%d" % [tag, k])
				_fixed_cam(p + sea * 1.0 + Vector3(0, 0.3, 0), atan2(along.x, along.z) - 0.5, 0.16, 3.6)
				await _wait(0.05)
				_shot(pre + "31%s_shore_low_%d" % [tag, k])
				await _wait(2.3)
			_free_cam()
	if part == "" or part == "wade":
		var wp = m.island.shore_pt(-1.2, -1.6)
		_place(wp, 0.4)
		_walk_to.call(m.island.shore_pt(-1.32, -2.0), false)
		await _wait(1.5)
		_shot(pre + "32_wading_game")
		_stop_walk()
		await _wait(0.6)
		var bp = m.player.global_position
		_fixed_cam(bp + Vector3(0, 0.25, 0), m.face_yaw + 1.2, 0.12, 1.9)
		await _wait(0.3)
		_shot(pre + "33_wading_low")
		_fixed_cam(bp + Vector3(0, 0.2, 0), m.face_yaw + 0.5, 0.55, 2.2)
		await _wait(0.3)
		_shot(pre + "34_wading_high")
		var dp = Vector3(0.0, 0.0, lerpf(m.island.dock_start_z, m.island.dock_end_z, 0.35))
		_fixed_cam(dp + Vector3(0, -0.2, 0), 1.3, 0.22, 4.2)
		await _wait(0.3)
		_shot(pre + "35_dock_posts")
		_free_cam()
	if part == "" or part == "lie" or part == "lieq":
		for i: int in ([0, 1, 2, 3] if part != "lieq" else [1]):
			var st: Dictionary = m.island.seats[i]
			var face: Vector3 = st["face"]
			var from_back = i == 2
			var spot: Vector3 = (st["back_approach"] as Vector3) - face * 0.7 if from_back else (st["approach"] as Vector3) + face * 0.7
			_place(m._blocked_by(spot), 0.0)
			_free_cam()
			await _wait(0.3)
			m._on_action()
			while m.rest_phase != 4:
				await m.get_tree().process_frame
			await _wait(0.8)
			_shot(pre + "36_seat_%d_sit" % i)
			m._lie_down()
			await _wait(m.SEAT_LIE_DUR * 0.5)
			_shot(pre + "37_seat_%d_lying_down" % i)
			while m.rest_phase != 4:
				await m.get_tree().process_frame
			await _wait(1.5)
			_shot(pre + "38_seat_%d_lie" % i)
			_fixed_cam(m.rest_lie + Vector3(0, 0.1, 0), atan2(m.seat_face.x, m.seat_face.z) + 0.35, 0.35, 1.8)
			await _wait(0.4)
			_shot(pre + "39_seat_%d_lie_close" % i)
			_free_cam()
			m._wake()
			while m.mode != m.Mode.EXPLORE:
				await m.get_tree().process_frame
			await _wait(0.3)

	if part == "" or part == "night":
		var c = m.island.campfire_pos
		_place(c + Vector3(2.4, 0, 2.4), 0.0)
		await _wait(0.3)
		_shot(pre + "40_day_ui")
		_fixed_cam(c + Vector3(0, 0.4, 0), 0.7, 0.25, 4.2)
		await _wait(0.4)
		_shot(pre + "40b_day_fire")
		_free_cam()
		await _wait(0.2)
		m._toggle_night()
		await _wait(1.25)
		_shot(pre + "41_dusk_transition")
		await _wait(1.6)
		_shot(pre + "42_night_ui")
		_fixed_cam(c + Vector3(0, 0.4, 0), 0.7, 0.25, 4.2)
		await _wait(0.4)
		_shot(pre + "43_night_fire")
		var st: Dictionary = m.island.seats[1]
		_place(m._blocked_by((st["approach"] as Vector3) + (st["face"] as Vector3) * 0.7), 0.0)
		_free_cam()
		await _wait(0.2)
		m._on_action()
		while m.rest_phase != 4:
			await m.get_tree().process_frame
		await _wait(1.0)
		_shot(pre + "44_night_sit_fire")
		m._wake()
		while m.mode != m.Mode.EXPLORE:
			await m.get_tree().process_frame
		_place(Vector3(0.3, 0, m.island.dock_end_z + 1.6), 0.1)
		await _wait(0.5)
		_shot(pre + "45_night_dock")
		m._enter_throw()
		await _wait(1.3)
		_shot(pre + "46_night_throw_view")
		m._leave_throw()
		await _wait(0.6)
		_fixed_cam(Vector3(0, 1.0, m.island.dock_start_z - 2.0), 2.6, 0.32, 26.0)
		await _wait(0.4)
		_shot(pre + "47_night_wide")
		_fixed_cam(m.island.beacon_pos + Vector3(0, -3.0, 0), 1.9, 0.12, 18.0)
		await _wait(0.4)
		_shot(pre + "48_night_lighthouse")
		var wp = m.island.shore_pt(-1.2, -1.6)
		_place(wp, 0.4)
		_walk_to.call(m.island.shore_pt(-1.32, -2.0), false)
		await _wait(1.5)
		_shot(pre + "49_night_wading")
		_stop_walk()
		_free_cam()
		m._toggle_night()
		await _wait(2.8)

## v11 stills: the ground round the campfire logs, the water reflection. part "" = all, logs or refl

func _v11_sequence(pre: String, part: String) -> void:
	if part == "" or part == "refl":
		for night in [false, true]:
			var tag = "night" if night else "day"
			if night:
				m._toggle_night()
				await _wait(2.9)
			_fixed_cam(Vector3(0, 1.0, m.island.dock_start_z - 2.0), 2.6, 0.32, 26.0)
			await _wait(0.4)
			_shot(pre + "61_%s_wide" % tag)
			_fixed_cam(m.island.beacon_pos + Vector3(0, -3.0, 0), 1.9, 0.12, 18.0)
			await _wait(0.4)
			_shot(pre + "62_%s_lighthouse" % tag)
			_fixed_cam(Vector3(0, 1.5, m.island.dock_start_z - 4.0), PI + 0.15, 0.07, 30.0)
			await _wait(0.4)
			_shot(pre + "63_%s_low_from_sea" % tag)
			_fixed_cam(m.island.campfire_pos + Vector3(0, 0.5, 0), 0.9, 0.1, 16.0)
			await _wait(0.4)
			_shot(pre + "64_%s_fire_from_shore" % tag)
		_free_cam()
		m._toggle_night()
		await _wait(2.8)
	if part == "" or part == "logs":
		var c = m.island.campfire_pos
		_place(c + Vector3(6.0, 0, 6.0), 0.0)
		_fixed_cam(c + Vector3(0, 0.2, 0), 0.4, 0.55, 7.5)
		await _wait(0.5)
		_shot(pre + "50_logs_wide")
		_fixed_cam(c + Vector3(0, 0.2, 0), -2.5, 0.3, 6.5)
		await _wait(0.3)
		_shot(pre + "51_logs_from_hill")
		for i in 3:
			var a = 0.6 + i * 2.1
			var lp = m.island.gp(c.x + cos(a) * 1.7, c.z + sin(a) * 1.7)
			# along the log (its bank in profile), from the fire side looking past it, and from outside
			_fixed_cam(lp + Vector3(0, 0.3, 0), atan2(-sin(a), cos(a)), 0.3, 4.2)
			await _wait(0.3)
			_shot(pre + "52_log_%d_profile" % i)
			_fixed_cam(lp + Vector3(0, 0.3, 0), atan2(-cos(a), -sin(a)) + 0.3, 0.12, 3.6)
			await _wait(0.3)
			_shot(pre + "53_log_%d_from_fire" % i)
			_fixed_cam(lp + Vector3(0, 0.25, 0), atan2(cos(a), sin(a)) + 0.35, 0.35, 3.6)
			await _wait(0.3)
			_shot(pre + "54_log_%d_outside" % i)
		_free_cam()

## v12 stills: the reflection at the screen edges, day and night, round 360 degrees and zoomed in / out

func _v12_sequence(pre: String, part: String) -> void:
	if part == "" or part == "bush":
		var best: Array = m.island.bush_spots[0]
		for b: Array in m.island.bush_spots:
			if _hd(b[0], m.island.hut_pos) < _hd(best[0], m.island.hut_pos) and _hd(b[0], m.island.hut_pos) > 4.5:
				best = b
		var bp: Vector3 = best[0]
		var bs: float = best[1]
		var away = Vector3(bp.x - m.island.hut_pos.x, 0, bp.z - m.island.hut_pos.z).normalized()
		var yaw = atan2(away.x, away.z)
		_place(bp + away * (0.9 + 0.5 * bs), yaw)
		_fixed_cam(bp + Vector3(0, 0.55 * bs, 0), yaw + 0.5, 0.2, 2.6 * bs)
		await _wait(0.6)
		_shot(pre + "80_bush_close")
		_fixed_cam(bp + Vector3(0, 0.45 * bs, 0), yaw + 2.4, 0.08, 2.0 * bs)
		await _wait(0.4)
		_shot(pre + "81_bush_close_side")
		_fixed_cam(bp + away * 1.2 + Vector3(0, 0.15, 0), yaw - 1.2, 0.05, 1.6)
		await _wait(0.4)
		_shot(pre + "82_grass_low")
		_free_cam()
		m._snap_explore_cam()
		await _wait(1.0)
		_shot(pre + "83_bush_game_view")

	if part == "" or part == "edges":
		for night in [false, true]:
			var tag = "night" if night else "day"
			if night:
				m._toggle_night()
				await _wait(2.9)
			var c = Vector3(0, 1.0, m.island.dock_end_z + 1.0)
			for k in 8:
				_fixed_cam(c, k * TAU / 8.0, 0.1, 9.0)
				await _wait(0.35)
				_shot(pre + "70_%s_yaw%d" % [tag, k * 45])
			for z: Array in [[3.5, 0.06, "near"], [30.0, 0.16, "far"]]:
				_fixed_cam(c, 0.6, z[1], z[0])
				await _wait(0.35)
				_shot(pre + "71_%s_zoom_%s" % [tag, z[2]])
			_fixed_cam(Vector3(0, 1.5, m.island.dock_start_z - 4.0), PI + 0.15, 0.07, 30.0)
			await _wait(0.35)
			_shot(pre + "72_%s_low_from_sea" % tag)
			if night:
				m._toggle_night()
				await _wait(2.9)
		_free_cam()
	if part == "" or part == "torch":
		var c = m.island.campfire_pos
		_place(c + Vector3(5.0, 0, 5.0), 0.0)
		m.demo_nocut = true
		for night in [false, true]:
			var tag = "night" if night else "day"
			if night:
				m._toggle_night()
				await _wait(2.9)
			var tp = m.island.torches[0].global_position
			var out = Vector3(tp.x - c.x, 0, tp.z - c.z).normalized()
			var yaw = atan2(out.x, out.z)
			for sh: Array in [[tp + Vector3(0, -0.05, 0), yaw + PI - 0.5, 0.12, 0.9, "90_%s_torch_head"], [tp + Vector3(0, -0.05, 0), yaw + 0.6, 0.1, 0.9, "90_%s_torch_head_back"], [tp + Vector3(0, -0.8, 0), yaw + PI - 0.9, 0.1, 2.6, "91_%s_torch_full"], [c + Vector3(0, 0.6, 0), yaw + 1.3, 0.22, 7.5, "92_%s_torches_camp"]]:
				var cy: float = sh[1]
				_fixed_cam(sh[0], cy, sh[2], sh[3])
				await _wait(0.5)
				_shot(pre + (sh[4] as String) % tag)
			if night:
				m._toggle_night()
				await _wait(2.9)
		m.demo_nocut = false
		_free_cam()

## v14 stills: the rowboat moored by the dock, from the sea, low over the water, from the dock and above,
## far enough out to see its reflection, and in the game camera; day and night

func _v14_sequence(pre: String) -> void:
	var bp = Vector3(2.3, 0.0, (m.island.dock_start_z + m.island.dock_end_z) * 0.5 - 1.0)
	var c = bp + Vector3(0, 0.1, 0)
	m.demo_nocut = true
	for night in [false, true]:
		var tag = "night" if night else "day"
		_place(Vector3(0, 0, m.island.dock_start_z - 1.0), PI)
		if night:
			m._toggle_night()
			await _wait(2.9)
		for sh: Array in [[c, PI * 0.5 + 0.25, 0.12, 4.6, "95_%s_boat_side"], [c, 0.55, 0.07, 3.8, "96_%s_boat_bow_low"],
				[c, PI - 0.7, 0.22, 4.2, "97_%s_boat_stern"], [c, -PI * 0.5 + 0.35, 0.72, 3.3, "98_%s_boat_from_dock"],
				[c, PI * 0.5, 1.35, 4.2, "99_%s_boat_top"], [c, PI * 0.5 + 0.6, 0.05, 9.0, "99_%s_boat_far_reflection"]]:
			var cy: float = sh[1]
			_fixed_cam(sh[0], cy, sh[2], sh[3])
			await _wait(0.5)
			_shot(pre + (sh[4] as String) % tag)
		# the beached boat on the sand shares the hull
		var bb = m.island.shore_pt(-0.75, 1.6) + Vector3(0, 0.3, 0)
		var bo = Island.dir_at(-0.75)
		for sh: Array in [[bb, atan2(bo.x, bo.z) + 0.9, 0.3, 4.2, "99_%s_beached_boat"], [bb, atan2(bo.x, bo.z) - 0.4, 0.95, 3.6, "99_%s_beached_boat_above"]]:
			var cy: float = sh[1]
			_fixed_cam(sh[0], cy, sh[2], sh[3])
			await _wait(0.5)
			_shot(pre + (sh[4] as String) % tag)
		_place(Vector3(0.75, 0, bp.z - 0.3), -PI * 0.5)
		_free_cam()
		m._snap_explore_cam()
		await _wait(1.2)
		_shot(pre + "99_%s_boat_game_view" % tag)
		if night:
			m._toggle_night()
			await _wait(2.9)
	m.demo_nocut = false
	_free_cam()

## A scripted swipe through the real gesture code: the finger goes down at `from`, slides by `to` (short-side
## units) over `sec`, rests `hold` s (shot `shot` then), and lets go - after a quick flick on along the swipe,
## or slowly.

func _demo_swipe(from: Vector2, to: Vector2, sec: float, hold: float, flick: bool, shot = "") -> void:
	var u = m._swipe_unit()
	m._swipe_press(from, m.gt)
	var t0 = m.gt
	while m.gt - t0 < sec:
		m._swipe_move(from + to * u * smoothstep(0.0, 1.0, (m.gt - t0) / sec), m.gt)
		await m.get_tree().process_frame
	var t1 = m.gt
	while m.gt - t1 < hold:
		m._swipe_move(from + to * u, m.gt)
		await m.get_tree().process_frame
	if shot != "":
		_shot(shot)
	if not flick:
		m._swipe_release(from + to * u, m.gt)
		return
	# the finger leaves the glass still moving: the release comes with the last move
	var d = to.normalized() * u * 0.32
	for k in range(1, 4):
		await m.get_tree().process_frame
		m._swipe_move(from + to * u + d * (k / 3.0), m.gt)
	m._swipe_release(from + to * u + d, m.gt)

func _demo_wait_ready(shots: Array) -> void:
	while m.state == m.State.THROWING:
		await m.get_tree().process_frame
	if shots.size() > 0 and shots[0] != "":
		await _wait(0.12)
		_shot(shots[0])
	m.fly_t = 0.0
	while m.state == m.State.FLYING and m.skips < 3:
		await m.get_tree().process_frame
	await _wait(0.25)
	if shots.size() > 1 and shots[1] != "":
		_shot(shots[1])
	while m.state != m.State.READY:
		await m.get_tree().process_frame
	await _wait(0.9)
	if shots.size() > 2 and shots[2] != "":
		_shot(shots[2])
	await _wait(1.6)

## the right shoulder (between the clavicle end and the arm joint), in the world

func _shoulder_pos(side = "r") -> Vector3:
	var sk = m.boy.skel
	var a = sk.get_bone_global_pose(sk.find_bone("upperarm_" + side)).origin
	var c = sk.get_bone_global_pose(sk.find_bone("clavicle_" + side)).origin
	return sk.global_transform * a.lerp(c, 0.25)

## v16: shoulder close-ups in daylight - rest pose all round, arm raised, the throws, walk / run, then the
## hammock and the towel (camera yaw relative to his facing: 0 behind, PI in front, +PI/2 his right)

func _v16_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	m.demo_nocut = true
	m.ui_root.visible = false
	var k = float(m._opt("shdist", "1.0"))
	var y0 = m.player.rotation.y
	for s: Array in [["rest_front", "idle", 0.0, 0.3, PI - 0.15, 0.05, 0.75], ["rest_34", "idle", 0.0, 0.3, PI * 0.72, 0.15, 0.6],
			["rest_side", "idle", 0.0, 0.3, PI * 0.5, 0.06, 0.6], ["rest_back34", "idle", 0.0, 0.3, PI * 0.28, 0.2, 0.6],
			["rest_back", "idle", 0.0, 0.3, 0.1, 0.12, 0.75], ["rest_top", "idle", 0.0, 0.3, PI * 0.6, 0.85, 0.6],
			["raise_front", "cheer", 1.0, 0.45, PI * 0.8, 0.1, 0.8], ["raise_back", "cheer", 1.0, 0.45, PI * 0.25, 0.2, 0.8],
			["throw_windup", "charge", 1.0, 0.3, PI * 0.4, 0.15, 0.85], ["throw_windup_back", "charge", 1.0, 0.3, 0.2, 0.25, 0.85],
			["throw_release", "release", 1.0, 0.3, PI * 0.75, 0.12, 0.85], ["throw_follow", "follow", 1.0, 0.3, 0.3, 0.2, 0.9],
			["crouch_windup", "charge_c", 1.0, 0.3, PI * 0.4, 0.2, 0.85], ["crouch_release", "release_c", 1.0, 0.3, PI * 0.75, 0.15, 0.85],
			["walk", "walk", 0.25, 0.25, PI * 0.55, 0.1, 0.75], ["run", "run", 0.2, 0.2, PI * 0.6, 0.1, 0.8]]:
		m.player_ctrl.write_yaw(y0)
		m.boy.debug_pose(s[1], s[2], s[3])
		await m.get_tree().process_frame
		_fixed_cam(_shoulder_pos(), y0 + float(s[4]), s[5], float(s[6]) * k)
		await _wait(0.3)
		_shot(pre + "v16_" + s[0])
	m.boy.frozen = false
	_free_cam()
	m.demo_nocut = false
	# lying down: the hammock, then the towel
	var hs = m._hammock_spot()
	var bed: Vector3 = hs[0]
	var side: Vector3 = hs[2]
	_place(bed + side * 1.2, atan2(side.x, side.z))
	m._begin_rest("sleep")
	while m.rest_phase < 4:
		await m.get_tree().process_frame
	await _wait(1.0)
	m.demo_nocut = true
	_fixed_cam(_shoulder_pos(), atan2(side.x, side.z) + 0.3, 0.7, 0.9)
	await _wait(0.3)
	_shot(pre + "v16_hammock")
	m.demo_nocut = false
	_free_cam()
	m._wake()
	while m.mode != m.Mode.EXPLORE:
		await m.get_tree().process_frame
	var td = m.island.towel_dir
	var sd = td.cross(Vector3.UP).normalized()
	_place(m.island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
	m._begin_rest("sun")
	while m.rest_phase < 4:
		await m.get_tree().process_frame
	await _wait(1.0)
	m.demo_nocut = true
	_fixed_cam(_shoulder_pos(), atan2(sd.x, sd.z) + 0.4, 0.75, 0.9)
	await _wait(0.3)
	_shot(pre + "v16_sun")
	m.demo_nocut = false
	m.ui_root.visible = true
	_free_cam()

## v21 video: the camera on his face (head bone, smoothed), yaw relative to his facing

func _face_cam(yaw: float, pitch: float, dist: float) -> void:
	var h = _bone_pos("head", 0.03)
	m.face_cam_tgt = h if m.face_cam_tgt == Vector3.INF else m.face_cam_tgt.lerp(h, 0.2)
	_fixed_cam(m.face_cam_tgt, m.player.rotation.y + yaw, pitch, dist)

func _follow_head(dur: float, yaw: float, pitch: float, dist: float, yaw_end = INF) -> void:
	var t0 = m.gt
	while m.gt - t0 < dur:
		_face_cam(yaw if yaw_end == INF else lerpf(yaw, yaw_end, (m.gt - t0) / dur), pitch, dist)
		await m.get_tree().process_frame

## a bone's position in the world, raised by `up` (m) along the world up axis

func _bone_pos(bone: String, up = 0.0) -> Vector3:
	var sk = m.boy.skel
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin + Vector3(0, up, 0)

## v17 close-ups in the game's light: the hair (front / side / back / three-quarter / top, with and without
## the hat, day and night, the hammock and the towel, the water reflection) and the clothes (front / side /
## back, standing, walking, running, the throws, day and night). part "" = all, "hair" or "clothes".
## Camera yaw is relative to his facing: 0 behind him, PI in front, +PI/2 his right.

func _v17_sequence(pre: String, part: String) -> void:
	_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	m.demo_nocut = true
	m.ui_root.visible = false
	var y0 = m.player.rotation.y
	var k = float(m._opt("hdist", "1.0"))
	for night in [false, true]:
		var tag = "night" if night else "day"
		if night:
			m._toggle_night()
			await _wait(2.9)
		if part == "" or part == "hair":
			var views = [["front", PI - 0.12, 0.06], ["34", PI * 0.75, 0.12], ["side", PI * 0.5, 0.06],
					["back34", PI * 0.25, 0.18], ["back", 0.05, 0.12], ["top", PI * 0.7, 0.8]]
			for hat_on in [true, false]:
				m.boy.hat.visible = hat_on
				for s: Array in views:
					if night and String(s[0]) in ["side", "back", "top"]:
						continue
					m.player_ctrl.write_yaw(y0)
					m.boy.debug_pose("idle", 1.0, 0.3)
					await m.get_tree().process_frame
					_fixed_cam(_bone_pos("head", 0.05), y0 + float(s[1]), s[2], 0.55 * k)
					await _wait(0.4)
					_shot(pre + "v17_hair_%s_%s%s" % [tag, s[0], "" if hat_on else "_nohat"])
			m.boy.hat.visible = true
		if part == "" or part == "clothes":
			for s: Array in [["front", "idle", 0.0, 0.3, PI - 0.1, 0.08, 1.35], ["34", "idle", 0.0, 0.3, PI * 0.72, 0.15, 1.35],
					["side", "idle", 0.0, 0.3, PI * 0.5, 0.08, 1.35], ["back", "idle", 0.0, 0.3, 0.08, 0.12, 1.35],
					["back34", "idle", 0.0, 0.3, PI * 0.28, 0.2, 1.35], ["walk", "walk", 1.0, 0.25, PI * 0.55, 0.1, 1.45],
					["run", "run", 1.0, 0.2, PI * 0.6, 0.1, 1.5], ["windup", "charge", 1.0, 0.3, PI * 0.4, 0.15, 1.5],
					["release", "release", 1.0, 0.3, PI * 0.75, 0.12, 1.5], ["crouch", "charge_c", 1.0, 0.3, PI * 0.45, 0.2, 1.4],
					["shorts_front", "idle", 0.0, 0.3, PI - 0.25, 0.1, 0.8], ["vest_close", "idle", 0.0, 0.3, PI * 0.8, 0.1, 0.75]]:
				if night and String(s[0]) in ["walk", "run", "windup", "release", "crouch", "back34"]:
					continue
				m.player_ctrl.write_yaw(y0)
				m.boy.debug_pose(s[1], s[2], s[3])
				await m.get_tree().process_frame
				var tgt = _bone_pos("spine_01", 0.0)
				if String(s[0]) == "shorts_front":
					tgt = _bone_pos("pelvis", -0.1)
				elif String(s[0]) == "vest_close":
					tgt = _bone_pos("spine_03", 0.0)
				_fixed_cam(tgt, y0 + float(s[4]), s[5], float(s[6]) * k)
				await _wait(0.4)
				_shot(pre + "v17_clothes_%s_%s" % [tag, s[0]])
		m.boy.frozen = false
	m._toggle_night()
	await _wait(2.8)
	if part == "" or part == "hair" or part == "refl":
		# the reflection: standing at the end of the dock, seen from above the water in front of it (his
		# mirror image lands on the water a metre or so out from the dock, clear of the deck)
		_place(Vector3(0.0, 0, m.island.dock_end_z + 0.35), 0.0)
		await _wait(1.0)
		var hp = _bone_pos("head")
		_fixed_cam(Vector3(hp.x, 0.4, hp.z - 2.4), m.player.rotation.y + PI - 0.15, 0.3, 3.8 * k)
		await _wait(0.6)
		_shot(pre + "v17_hair_day_reflection")
		_free_cam()
		# lying down: hat off in the hammock and on the towel
		var hs = m._hammock_spot()
		var side: Vector3 = hs[2]
		_place(hs[0] + side * 1.2, atan2(side.x, side.z))
		m._begin_rest("sleep")
		while m.rest_phase < 4:
			await m.get_tree().process_frame
		await _wait(1.0)
		_fixed_cam(_bone_pos("head"), atan2(side.x, side.z) + 0.5, 0.6, 0.8 * k)
		await _wait(0.4)
		_shot(pre + "v17_hair_day_hammock")
		_free_cam()
		m._wake()
		while m.mode != m.Mode.EXPLORE:
			await m.get_tree().process_frame
		var td = m.island.towel_dir
		var sd = td.cross(Vector3.UP).normalized()
		_place(m.island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
		m._begin_rest("sun")
		while m.rest_phase < 4:
			await m.get_tree().process_frame
		await _wait(1.0)
		_fixed_cam(_bone_pos("head"), atan2(sd.x, sd.z) + 0.6, 0.6, 0.8 * k)
		await _wait(0.4)
		_shot(pre + "v17_hair_day_sun")
		_free_cam()
		m._wake()
		while m.mode != m.Mode.EXPLORE:
			await m.get_tree().process_frame
	m.demo_nocut = false
	m.ui_root.visible = true
	_free_cam()

## v18 close-ups of the four v17 leftovers: the hair in the hat brim's shadow (day, and night by the lamp),
## the hair card edges very close up, the back of the left armhole (tank top edge under the vest) and the
## vest's sides under the arms. Camera yaw is relative to his facing: 0 behind him, PI in front, +PI/2 his right.

func _v18_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	m.demo_nocut = true
	m.ui_root.visible = false
	var y0 = m.player.rotation.y
	# [name, pose, p, tt, cam yaw, pitch, dist, bone, up, hat, night]
	var shots = [
		["brim_front", "idle", 1.0, 0.3, PI - 0.12, 0.02, 0.4, "head", 0.03, true, false],
		["brim_34", "idle", 1.0, 0.3, PI * 0.75, 0.05, 0.4, "head", 0.03, true, false],
		["brim_side", "idle", 1.0, 0.3, PI * 0.5, 0.02, 0.38, "head", 0.03, true, false],
		["brim_back34", "idle", 1.0, 0.3, PI * 0.25, 0.08, 0.42, "head", 0.03, true, false],
		["brim_l34", "idle", 1.0, 0.3, -PI * 0.7, 0.04, 0.4, "head", 0.03, true, false],
		["edge_side", "idle", 1.0, 0.3, PI * 0.5, 0.05, 0.2, "head", 0.06, false, false],
		["edge_back", "idle", 1.0, 0.3, 0.1, 0.15, 0.2, "head", 0.06, false, false],
		["edge_fringe", "idle", 1.0, 0.3, PI - 0.35, 0.0, 0.2, "head", 0.0, true, false],
		["armhole_idle", "idle", 1.0, 0.3, -PI * 0.2, 0.1, 0.32, "upperarm_l", -0.03, true, false],
		["armhole_charge", "charge", 0.6, 0.3, -PI * 0.2, 0.1, 0.34, "upperarm_l", -0.03, true, false],
		["armhole_cheer", "cheer", 1.0, 1.0, -PI * 0.15, 0.05, 0.34, "upperarm_l", -0.05, true, false],
		["armhole_in_charge", "charge", 0.6, 0.3, -PI * 0.62, 0.12, 0.26, "upperarm_l", -0.07, true, false],
		["armhole_in_crouch", "charge_c", 0.6, 0.3, -PI * 0.62, 0.12, 0.26, "upperarm_l", -0.07, true, false],
		["underarm_l_idle", "idle", 1.0, 0.3, -PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, false],
		["underarm_l_cheer", "cheer", 1.0, 1.0, -PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, false],
		["underarm_r_cheer", "cheer", 1.0, 1.0, PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, false],
		["underarm_l_charge", "charge", 0.6, 0.3, -PI * 0.45, 0.05, 0.45, "spine_03", 0.08, true, false],
		["underarm_r_walk", "walk", 1.0, 0.3, PI * 0.5, 0.05, 0.45, "spine_03", 0.08, true, false],
		["brim_34", "idle", 1.0, 0.3, PI * 0.75, 0.05, 0.4, "head", 0.03, true, true],
		["brim_front", "idle", 1.0, 0.3, PI - 0.12, 0.02, 0.4, "head", 0.03, true, true],
		["underarm_l_cheer", "cheer", 1.0, 1.0, -PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, true],
	]
	for s: Array in shots:
		if not String(s[0]).begins_with(m._opt("only")):
			continue
		if bool(s[10]) != m.night_on:
			m._toggle_night()
			await _wait(2.9)
		m.boy.hat.visible = bool(s[9])
		m.player_ctrl.write_yaw(y0)
		m.boy.debug_pose(s[1], s[2], s[3])
		await m.get_tree().process_frame
		_fixed_cam(_bone_pos(s[7], s[8]), y0 + float(s[4]), s[5], s[6])
		await _wait(0.4)
		_shot(pre + "v18_%s_%s" % ["night" if m.night_on else "day", s[0]])
	m.boy.hat.visible = true
	m.boy.frozen = false
	if m.night_on:
		m._toggle_night()
	m.demo_nocut = false
	m.ui_root.visible = true
	_free_cam()

## v19 close-ups: the nape tips, the card edges up close and edge-on, the vest underarm folds with the arms
## raised (cheer, release, wind-up, sunbathing), and the hair at night

func _v19_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	m.demo_nocut = true
	m.ui_root.visible = false
	var y0 = m.player.rotation.y
	# [name, pose, p, tt, cam yaw, pitch, dist, bone, up, hat, night]
	var shots = [] if m._opt("ropeonly") == "1" else [
		["nape_back34", "idle", 1.0, 0.3, PI * 0.25, 0.08, 0.42, "head", 0.03, true, false],
		["nape_back", "idle", 1.0, 0.3, 0.05, 0.05, 0.36, "head", 0.0, true, false],
		["nape_close", "idle", 1.0, 0.3, PI * 0.15, 0.02, 0.24, "head", -0.03, true, false],
		["nape_nohat", "idle", 1.0, 0.3, PI * 0.2, 0.1, 0.4, "head", 0.03, false, false],
		["edge_side", "idle", 1.0, 0.3, PI * 0.5, 0.05, 0.2, "head", 0.06, false, false],
		["edge_back", "idle", 1.0, 0.3, 0.1, 0.15, 0.2, "head", 0.06, false, false],
		["edge_top", "idle", 1.0, 0.3, PI * 0.6, 0.02, 0.16, "head", 0.1, false, false],
		["edge_fringe", "idle", 1.0, 0.3, PI - 0.35, 0.0, 0.2, "head", 0.0, true, false],
		["fold_cheer_front", "cheer", 1.0, 1.0, PI - 0.25, 0.05, 0.6, "spine_03", 0.06, true, false],
		["fold_cheer_side", "cheer", 1.0, 1.0, PI * 0.5, 0.05, 0.45, "spine_03", 0.08, true, false],
		["fold_cheer_back", "cheer", 1.0, 1.0, 0.2, 0.05, 0.6, "spine_03", 0.06, true, false],
		["fold_release_front", "release", 1.0, 0.3, PI - 0.3, 0.05, 0.65, "spine_03", 0.06, true, false],
		["fold_charge_back", "charge", 0.6, 0.3, 0.0, 0.08, 0.85, "spine_03", 0.0, true, false],
		["fold_sun", "sun", 1.0, 0.3, PI * 0.5, 0.75, 1.0, "spine_03", 0.0, false, false],
		["fold_sun_close", "sun", 1.0, 0.3, PI * 0.3, 0.5, 0.55, "upperarm_r", 0.0, false, false],
		["night_brim_34", "idle", 1.0, 0.3, PI * 0.75, 0.05, 0.4, "head", 0.03, true, true],
		["night_brim_front", "idle", 1.0, 0.3, PI - 0.12, 0.02, 0.4, "head", 0.03, true, true],
		["night_back34", "idle", 1.0, 0.3, PI * 0.25, 0.08, 0.42, "head", 0.03, true, true],
		["night_side", "idle", 1.0, 0.3, -PI * 0.5, 0.02, 0.4, "head", 0.03, true, true],
		["night_nohat", "idle", 1.0, 0.3, PI * 0.7, 0.08, 0.42, "head", 0.05, false, true],
	]
	for s: Array in shots:
		if not String(s[0]).begins_with(m._opt("only")):
			continue
		if bool(s[10]) != m.night_on:
			m._toggle_night()
			await _wait(2.9)
		m.boy.hat.visible = bool(s[9])
		m.player_ctrl.write_yaw(y0)
		m.boy.debug_pose(s[1], s[2], s[3])
		await m.get_tree().process_frame
		_fixed_cam(_bone_pos(s[7], s[8]), y0 + float(s[4]), s[5], s[6])
		await _wait(0.4)
		_shot(pre + "v19_%s" % s[0])
	m.boy.hat.visible = true
	m.boy.frozen = false
	if m.night_on:
		m._toggle_night()
		await _wait(2.9)
	# the mooring line's dock end while the boat bobs: two frames 1.3 s apart, same camera
	# (and how far that end would wander if it rode on the boat, as it did up to v18)
	_fixed_cam(m.island.boat_tie, 0.6, 0.3, 1.0)
	var drift = 0.0
	for k in 3:
		var t0 = m.gt
		while m.gt - t0 < 1.3:
			var rigid: Vector3 = m.island.dock_boat.transform * (m.island.boat_rest.affine_inverse() * m.island.boat_tie)
			drift = maxf(drift, (rigid - m.island.boat_tie).length())
			await m.get_tree().process_frame
		_shot(pre + "v19_rope_%d" % k)
	print("V19 mooring line dock end: rides the boat up to %.1f cm off the knot (pinned since v19)" % (drift * 100.0))
	m.demo_nocut = false
	m.ui_root.visible = true
	_free_cam()

## v20: the straw hat stays on his head. part "lie": the real hammock / towel / bench / log rest from the
## game (lying down, lying, close-ups at the head, getting up); part "pose": close-ups of the hat on the hair
## through walk / run / the throws / cheer / oops. part "" = both.

func _v20_sequence(pre: String, part: String) -> void:
	if part == "" or part == "lie":
		var hs = m._hammock_spot()
		var td = m.island.towel_dir
		var sd = td.cross(Vector3.UP).normalized()
		for spec: Array in [["hammock", "sleep", hs[0] + hs[2] * 1.6], ["towel", "sun", m.island.towel_pos + sd * 1.4], ["bench", 0, null], ["log", 1, null]]:
			var nm: String = spec[0]
			if m._opt("only") != "" and not nm.begins_with(m._opt("only")):
				continue
			_free_cam()
			if spec[1] is String:
				_place(spec[2], 0.0)
				await _wait(0.3)
				m._begin_rest(spec[1])
				while m.rest_phase != 3:
					await m.get_tree().process_frame
			else:
				var st: Dictionary = m.island.seats[spec[1]]
				var face: Vector3 = st["face"]
				_place(m._blocked_by((st["approach"] as Vector3) + face * 0.7), 0.0)
				await _wait(0.3)
				m._on_action()
				while m.rest_phase != 4:
					await m.get_tree().process_frame
				await _wait(0.5)
				m._lie_down()
			var dur = m.SEAT_LIE_DUR if m.rest_kind == "seat" else 1.0
			# across him: from the open side (in front of a seat)
			var lat: Vector3 = m.seat_face if m.rest_kind == "seat" else m.rest_side
			await _wait(dur * 0.55)
			_shot(pre + "v20_%s_1_lying_down" % nm)
			_fixed_cam((m.boy.parts["head"] as Node3D).global_position, atan2(lat.x, lat.z), 0.3, 1.1)
			await m.get_tree().process_frame
			_shot(pre + "v20_%s_1b_lying_down_close" % nm)
			_free_cam()
			while m.rest_phase != 4:
				await m.get_tree().process_frame
			await _wait(1.2)
			_shot(pre + "v20_%s_2_lie" % nm)
			var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
			var hd = m.rest_lie_b.y
			_fixed_cam(head, atan2(lat.x, lat.z), 0.3, 0.95)
			await _wait(0.3)
			_shot(pre + "v20_%s_3_close_side" % nm)
			_fixed_cam(head, atan2(hd.x, hd.z) + 0.5, 0.12, 0.8)
			await _wait(0.3)
			_shot(pre + "v20_%s_4_close_head_end" % nm)
			_free_cam()
			m._wake()
			while m.rest_phase != 5 and m.rest_phase != 6:
				await m.get_tree().process_frame
			await _wait(dur * 0.45)
			_shot(pre + "v20_%s_5_getting_up" % nm)
			while m.mode != m.Mode.EXPLORE:
				await m.get_tree().process_frame
			await _wait(0.3)
	if part == "" or part == "pose":
		_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
		await _wait(0.6)
		m.demo_nocut = true
		m.ui_root.visible = false
		var y0 = m.player.rotation.y
		# [name, pose, p, tt, cam yaw, pitch, dist]
		var shots = [
			["idle_side", "idle", 1.0, 0.3, PI * 0.5, 0.05, 0.55],
			["idle_front", "idle", 1.0, 0.3, PI - 0.3, 0.05, 0.55],
			["walk", "walk", 1.0, 0.3, PI * 0.6, 0.05, 0.6],
			["run", "run", 1.0, 0.15, PI * 0.6, 0.05, 0.6],
			["charge", "charge", 1.0, 0.3, PI * 0.35, 0.1, 0.7],
			["release", "release", 1.0, 0.3, PI * 0.7, 0.05, 0.7],
			["follow", "follow", 1.0, 0.3, PI * 0.75, 0.05, 0.7],
			["crouch_release", "release_c", 1.0, 0.3, PI * 0.7, 0.1, 0.7],
			["cheer", "cheer", 1.0, float(m._opt("cheer_t", "1.0")), PI - 0.4, 0.05, 0.7],
			["oops", "oops", 1.0, float(m._opt("oops_t", "0.8")), PI - 0.3, 0.05, 0.6],
		]
		for s: Array in shots:
			if not Array(m._opt("only").split(",")).any(func(o: String) -> bool: return String(s[0]).begins_with(o)):
				continue
			m.player_ctrl.write_yaw(y0)
			m.boy.debug_pose(s[1], s[2], s[3])
			await m.get_tree().process_frame
			_fixed_cam(_bone_pos("head", 0.04), y0 + float(s[4]), s[5], s[6])
			await _wait(0.4)
			_shot(pre + "v20_pose_%s" % s[0])
		m.boy.frozen = false
		m.demo_nocut = false
		m.ui_root.visible = true
		_free_cam()

## v21 face: close-ups (front / three-quarter / side), the expressions, the sleeping face (hat hidden: it lies
## over his face then), the game camera with him turned toward it; then at night by a torch

func _v21_sequence(pre: String, ver = "v21", dk = 1.0) -> void:
	m.demo_nocut = true
	var ex0 = [m.ex_dist, m.ex_pitch]
	for night: bool in [false, true]:
		var tag = "night" if night else "day"
		var p = Vector3(0.0, 0, m.island.dock_end_z + 1.6)
		var y0 = PI * 0.5
		if night:
			m._toggle_night()
			var c = m.island.campfire_pos
			var tp = m.island.torches[0].global_position
			var out = Vector3(tp.x - c.x, 0, tp.z - c.z).normalized()
			p = Vector3(tp.x, 0, tp.z) - out * 0.8 + out.cross(Vector3.UP) * 0.35
			y0 = atan2(out.x, out.z) + 0.4
			await _wait(2.9)
		_place(p, y0)
		await _wait(0.6)
		m.ui_root.visible = false
		# [name, pose, p, tt, cam yaw, pitch, dist]
		var shots = [["front", "idle", 1.0, 0.3, PI, 0.03, 0.4], ["34", "idle", 1.0, 0.3, PI - 0.75, 0.04, 0.4],
			["side", "idle", 1.0, 0.3, PI * 0.5, 0.03, 0.42], ["up", "idle", 1.0, 0.3, PI - 0.35, 0.75, 0.55]]
		if not night:
			shots += [["focus", "charge", 1.0, 0.3, PI - 0.6, -0.25, 0.45], ["cheer", "cheer", 1.0, 1.0, PI - 0.3, 0.04, 0.5],
				["oops", "oops", 1.0, 0.8, PI - 0.25, -0.3, 0.45], ["sleep", "sleep", 1.0, 0.3, PI - 0.4, 0.04, 0.42],
				["closed", "idle", 1.0, 0.3, PI - 0.4, 0.04, 0.42]]
		if ver != "v21":
			shots += [["body", "idle", 1.0, 0.3, PI - 0.3, 0.08, 1.6 / dk], ["bodyside", "idle", 1.0, 0.3, PI * 0.5, 0.08, 1.6 / dk]]
		for s: Array in shots:
			if not Array(m._opt("only").split(",")).any(func(o: String) -> bool: return String(s[0]).begins_with(o)):
				continue
			m.player_ctrl.write_yaw(y0)
			m.boy.debug_pose(s[1], s[2], s[3])
			if s[0] == "closed":
				m.boy.blink_t = 0.08
				m.boy._update_face(0.0)
			m.boy.hat.visible = s[0] != "sleep"
			if s[0] == "sleep":
				m.boy.glasses.visible = false
			await m.get_tree().process_frame
			var tgt = _bone_pos("head", 0.03)
			if String(s[0]).begins_with("body"):
				tgt = _bone_pos("pelvis", 0.0) + Vector3(0, 0.12, 0)
			_fixed_cam(tgt, y0 + float(s[4]), s[5], float(s[6]) * dk)
			await _wait(0.3)
			_shot(pre + "%s_%s_%s" % [ver, tag, s[0]])
			m.boy.hat.visible = true
		m.boy.frozen = false
		# the game camera, him turned toward it
		_free_cam()
		m.ui_root.visible = true
		_place(p, y0)
		m.ex_yaw = m.face_yaw + PI
		var ec = m._explore_cam()
		m.cam_target = ec[0]; m.cam_yaw = ec[1]; m.cam_pitch = ec[2]; m.cam_dist = ec[3]
		await _wait(1.2)
		_shot(pre + "%s_%s_game" % [ver, tag])
		# pinched in and dragged lower, as a player does to look at him
		m.ex_dist = 3.0
		m.ex_pitch = 0.55
		ec = m._explore_cam()
		m.cam_target = ec[0]; m.cam_yaw = ec[1]; m.cam_pitch = ec[2]; m.cam_dist = ec[3]
		await _wait(0.8)
		_shot(pre + "%s_%s_game_zoom" % [ver, tag])
		m.ex_dist = ex0[0]
		m.ex_pitch = ex0[1]
		if night:
			m._toggle_night()
			await _wait(2.9)
	m.demo_nocut = false

## v15: aiming by swipe - the pad and angle sliders, aiming left / right (arrow, preview, readout, the chest
## turning first), cancel, a flicked throw, a too-steep launch, a too-flat stone, a slow release (no spin)

func _v15_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), 0.0)
	await _wait(0.4)
	m._enter_throw()
	await _wait(1.8)
	_shot(pre + "v15_1_ready")
	var c = m.throw_pad.pad_c
	m._swipe_press(c, m.gt)
	for k in 12:
		m._swipe_move(c + Vector2(-0.2, -0.3) * m._swipe_unit() * (k + 1) / 12.0, m.gt)
		await m.get_tree().process_frame
	await _wait(0.9)
	_shot(pre + "v15_2_aim_left")
	if not m.portrait_demo:
		_fixed_cam(m.player.global_position + Vector3(0, 0.75, 0), m.aim_yaw + 2.2, 0.25, 2.6)
		await _wait(0.2)
		_shot(pre + "v15_2b_aim_left_body")
		_free_cam()
	for k in 10:
		m._swipe_move(c + Vector2(-0.2, -0.3).lerp(Vector2(0.02, 0.1), (k + 1) / 10.0) * m._swipe_unit(), m.gt)
		await m.get_tree().process_frame
	await _wait(0.3)
	_shot(pre + "v15_3_cancel")
	m._swipe_release(c + Vector2(0.02, 0.1) * m._swipe_unit(), m.gt)
	await _wait(1.2)
	await _demo_swipe(c, Vector2(0.17, -0.4), 0.5, 0.8, true, pre + "v15_4_aim_right")
	await _demo_wait_ready([pre + "v15_5_release", pre + "v15_6_skipping", pre + "v15_7_result"])
	m._set_angles(28.0, 20.0)
	await _wait(0.6)
	await _demo_swipe(c, Vector2(0.0, -0.45), 0.4, 0.6, true, pre + "v15_8_steep_aim")
	await _demo_wait_ready(["", "", pre + "v15_9_steep_result"])
	m._set_angles(4.0, 3.0)
	await _wait(0.6)
	await _demo_swipe(c, Vector2(-0.05, -0.45), 0.4, 0.6, true, pre + "v15_10_flat_aim")
	await _demo_wait_ready(["", "", pre + "v15_11_flat_result"])
	m._set_angles(4.0, 20.0)
	await _wait(0.6)
	await _demo_swipe(c, Vector2(0.0, -0.45), 0.4, 0.8, false)
	await _demo_wait_ready(["", "", pre + "v15_12_slow_release_result"])
	if not m.portrait_demo:
		m._toggle_night()
		await _wait(2.9)
		await _demo_swipe(c, Vector2(-0.08, -0.42), 0.5, 0.8, true, pre + "v15_13_night_aim")
		await _demo_wait_ready(["", "", ""])
		m._toggle_night()
		await _wait(2.9)

## gameplay follow camera along the beach (style checks): walk, run, then stand

func _explore_sequence(pre: String) -> void:
	var a = m.island.shore_pt(-1.3, 2.2)
	_place(a, 0.0)
	var b = m.island.shore_pt(-0.95, 2.2)
	var dirv = (b - a).normalized()
	m.face_yaw = atan2(-dirv.x, -dirv.z)
	m.player_ctrl.write_yaw(m.face_yaw)
	m._snap_explore_cam()
	_walk_to.call(b, false)
	await _wait(2.5)
	_shot(pre + "e1_walk")
	_walk_to.call(m.island.shore_pt(-0.4, 3.6), true)
	await _wait(2.0)
	_shot(pre + "e2_run")
	_stop_walk()
	await _wait(1.5)
	_shot(pre + "e3_stand")

func _run_demo4() -> void:
	await _wait(0.5)
	if m.demo_seg != "":
		await _video_seg(m.demo_seg)
		m.get_tree().quit()
		return
	var pre = "p_" if m.portrait_demo else ""
	var close = not m.portrait_demo
	for a0 in OS.get_cmdline_user_args():
		if a0.begins_with("--from="):
			var what = a0.substr(7)
			if what == "throw":
				await _throw_sequence(pre + "08_", true, close)
			elif what == "shore":
				await _shore_sequence(pre)
			elif what == "explore":
				await _explore_sequence(pre)
			elif what == "v8":
				await _v8_sequence(pre)
			elif what.begins_with("v9"):
				await _v9_sequence(pre, what.substr(2).trim_prefix("_"))
			elif what == "v14":
				await _v14_sequence(pre)
			elif what == "v15":
				await _v15_sequence(pre)
			elif what == "v16":
				await _v16_sequence(pre)
			elif what.begins_with("v17"):
				await _v17_sequence(pre, what.substr(3).trim_prefix("_"))
			elif what == "v18":
				await _v18_sequence(pre)
			elif what == "v19":
				await _v19_sequence(pre)
			elif what.begins_with("v20"):
				await _v20_sequence(pre, what.substr(3).trim_prefix("_"))
			elif what == "v21":
				await _v21_sequence(pre)
			elif what == "v22":
				await _v21_sequence(pre, "v22", 1.2)
			elif what.begins_with("v12"):
				await _v12_sequence(pre, what.substr(3).trim_prefix("_"))
			elif what.begins_with("v11"):
				await _v11_sequence(pre, what.substr(3).trim_prefix("_"))
			else:
				await _rest_sequence(pre + ("10_" if what == "sleep" else "11_"), what, close)
			m.get_tree().quit()
			return
	if close:
		_track(PI, 0.04, 0.95, 1.0)
		await _wait(0.4)
		_shot("01_face_front")
		_track(PI - 0.65, 0.06, 1.0, 1.0)
		await _wait(0.3)
		_shot("02_face_34")
		_track(PI - 0.35, 0.1, 2.3, 0.62)
		await _wait(0.3)
		_shot("03_body_vest_front")
		_track(0.7, 0.22, 2.4, 0.62)
		await _wait(0.3)
		_shot("04_body_vest_back34")
		_free_cam()
	# walk then run along the beach toward the dock
	var a = m.island.shore_pt(-1.05, 1.6)
	_place(a, 0.0)
	var dock_foot = Vector3(0.0, 0, m.island.dock_start_z + 1.5)
	var sea_dir = Island.dir_at(-1.3)
	var dirv = (dock_foot - a).normalized()
	m.face_yaw = atan2(-dirv.x, -dirv.z)
	m.player_ctrl.write_yaw(m.face_yaw)
	m._snap_explore_cam()
	var mid = m.island.shore_pt(-1.32, 1.4)
	if close:
		m.demo_cam = true
		m.demo_track = [atan2(sea_dir.x, sea_dir.z) - 0.25, 0.1, 3.0, 0.6, true]
	var t_walk = m.gt
	_walk_to.call(mid, false)
	await _wait(1.8)
	_shot(pre + "05_walk")
	await _wait(0.35)
	_shot(pre + "05b_walk")
	while _hd(m.player.position, mid) > 0.5 and m.gt - t_walk < 10.0:
		await m.get_tree().process_frame
	_walk_to.call(dock_foot, true)
	await _wait(1.2)
	_shot(pre + "06_run")
	await _wait(0.25)
	_shot(pre + "06b_run")
	_free_cam()
	while _hd(m.player.position, dock_foot) > 0.5 and m.gt - t_walk < 20.0:
		await m.get_tree().process_frame
	_walk_to.call(Vector3(0, 0, m.island.dock_end_z + 2.0), true)
	await _wait(1.6)
	_shot(pre + "07_explore_follow")
	_stop_walk()
	await _wait(0.2)
	await _throw_sequence(pre + "08_", true, close)
	m._leave_throw()
	if close:
		await _throw_sequence("09_", false, true)
		m._leave_throw()
	await _rest_sequence(pre + "10_", "sleep", close)
	m._wake()
	while m.mode != m.Mode.EXPLORE:
		await m.get_tree().process_frame
	await _wait(0.3)
	_shot(pre + "10_sleep_woke")
	await _rest_sequence(pre + "11_", "sun", close)
	if not m.portrait_demo:
		m._wake()
		while m.mode != m.Mode.EXPLORE:
			await m.get_tree().process_frame
		m._toggle_view()
		await _wait(1.5)
		_shot("12_view_mode")
	m.get_tree().quit()

func _video_seg(seg: String) -> void:
	match seg:
		"walk":
			var a = m.island.shore_pt(-1.05, 1.6)
			var mid = m.island.shore_pt(-1.32, 1.4)
			var dock_foot = Vector3(0.0, 0, m.island.dock_start_z + 1.5)
			var dirv = (mid - a).normalized()
			_place(a, atan2(-dirv.x, -dirv.z))
			m.ex_yaw = m.face_yaw + 1.1
			_snap_cam_now()
			await _walk_to(mid, false, 3.4)
			await _walk_to(dock_foot, true, 4.0)
			await _walk_to(Vector3(0, 0, m.island.dock_end_z + 2.2), true, 3.0)
			await _wait(0.3)
		"throw":
			# standing and half-kneeling throws seen from the front-right (the throwing side), then one in the game camera
			_place(Vector3(0.0, 0, m.island.dock_end_z + 3.0), 0.0)
			await _walk_to(Vector3(0.2, 0, m.island.dock_end_z + 1.5), false, 2.0)
			await _wait(0.4)
			m._enter_throw()
			for k in 3:
				await _wait(0.5)
				if (k == 1) != (m.boy.stance == "crouch"):
					m._toggle_stance()
					await _wait(0.9)
				if k < 2:
					m.demo_cam = true
					m.demo_track = [m.player.rotation.y + PI * 0.5 + 0.55, 0.22, 2.9, 0.5, true]
				else:
					_free_cam()
				m._begin_aim(Vector2.ZERO)
				m.aim_pitch = 3.0
				var t0 = m.gt
				while m.gt - t0 < 1.5:
					m.charge_t = minf((m.gt - t0) / 1.2, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
					m.aim_yaw = 0.1 + sin((m.gt - t0) * 2.0) * 0.04
					await m.get_tree().process_frame
				m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
				m._throw()
				m.fly_t = 0.0
				if k < 2:
					await _wait(3.2)
				while m.state != m.State.READY:
					await m.get_tree().process_frame
				await _wait(1.0 if k < 2 else 3.0)
			_free_cam()
		"sleep":
			var hs = m._hammock_spot()
			var bed: Vector3 = hs[0]
			var side: Vector3 = hs[2]
			_place(bed + side * 2.2 + (m.island.hammock_b - m.island.hammock_a).normalized() * 0.8, atan2(side.x, side.z))
			m.ex_yaw = m.face_yaw + PI + 0.5
			_snap_cam_now()
			await _walk_to(bed + side * 1.2, false, 1.8)
			m._begin_rest("sleep")
			while m.rest_phase < 4:
				await m.get_tree().process_frame
			await _wait(2.6)
		"sun":
			var td = m.island.towel_dir
			var sd = td.cross(Vector3.UP).normalized()
			_place(m.island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
			m.ex_yaw = m.face_yaw + PI + 0.6
			_snap_cam_now()
			m._begin_rest("sun")
			while m.rest_phase < 4:
				await m.get_tree().process_frame
			await _wait(2.2)
		"getup":
			# sunbathe -> get up -> walk away on the real touch stick (the v5 bug: stuck after getting up)
			var td2 = m.island.towel_dir
			var sd2 = td2.cross(Vector3.UP).normalized()
			_place(m.island.towel_pos + sd2 * 1.4 + td2 * 0.4, atan2(sd2.x, sd2.z))
			_snap_cam_now()
			m._begin_rest("sun")
			while m.rest_phase < 4:
				await m.get_tree().process_frame
			await _wait(1.8)
			m._toast("点「起来」", 1.0)
			m._wake()
			while m.mode != m.Mode.EXPLORE:
				await m.get_tree().process_frame
			await _wait(0.4)
			await _stick_walk([Vector2(0.2, -1), Vector2(1, -0.3), Vector2(0.4, 1)], 1.6)
			await _wait(0.8)
		"gait":
			# side-on camera out over the water: walk, run, stop; then the same stretch in the game camera
			var sea_side = Island.dir_at(-1.1)
			for game_cam: bool in [false, true]:
				var g0 = m.island.shore_pt(-1.38, 2.4)
				var gm = m.island.shore_pt(-1.15, 2.4)
				var g1 = m.island.shore_pt(-0.86, 2.6)
				var gd = (gm - g0).normalized()
				_place(g0, atan2(-gd.x, -gd.z))
				m.ex_yaw = m.face_yaw
				_snap_cam_now()
				if game_cam:
					_free_cam()
				else:
					m.demo_cam = true
					m.demo_track = [atan2(sea_side.x, sea_side.z), 0.08, 2.3, 0.62, true]
				await _wait(0.6)
				await _walk_to(gm, false, 5.0)
				await _walk_to(g1, true, 4.0)
				_stop_walk()
				await _wait(1.2)
			_free_cam()

		"face21":
			# the face up close: idle with its blinks (front round to the side), a throw (focus, then the cheer),
			# an oops, by a torch at night; then the game camera with him turned toward it
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.5)
			m.ui_root.visible = false
			m.face_cam_tgt = Vector3.INF
			await _follow_head(3.2, PI, 0.03, 0.45)
			await _follow_head(3.0, PI, 0.03, 0.45, PI * 0.5)
			await _follow_head(0.8, PI * 0.5, 0.03, 0.45)
			m._enter_throw()
			await _follow_head(1.2, PI - 0.55, -0.15, 0.6)
			m._begin_aim(Vector2.ZERO)
			m.aim_pitch = 3.0
			var ft0 = m.gt
			while m.gt - ft0 < 1.4:
				m.charge_t = minf((m.gt - ft0) / 1.2, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
				_face_cam(PI - 0.55, -0.15, 0.6)
				await m.get_tree().process_frame
			m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
			m._throw()
			m.fly_t = 0.0
			while m.state != m.State.READY:
				_face_cam(PI - 0.55, -0.15, 0.6)
				await m.get_tree().process_frame
			if m.boy.anim != "react":
				m.boy.react("cheer")
			await _follow_head(2.4, PI - 0.4, -0.1, 0.6)
			m.boy.react("oops")
			await _follow_head(2.4, PI - 0.3, -0.25, 0.55)
			m._leave_throw()
			var c = m.island.campfire_pos
			var tp = m.island.torches[0].global_position
			var out = Vector3(tp.x - c.x, 0, tp.z - c.z).normalized()
			m.night_on = true
			m.night_k = 1.0
			m._update_night(0.0, true)
			_place(Vector3(tp.x, 0, tp.z) - out * 0.8 + out.cross(Vector3.UP) * 0.35, atan2(out.x, out.z) + 0.4)
			await m.get_tree().process_frame
			m.face_cam_tgt = Vector3.INF
			await _follow_head(4.0, PI - 0.4, 0.03, 0.45)
			m.night_on = false
			m.night_k = 0.0
			m._update_night(0.0, true)
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
			_free_cam()
			m.ui_root.visible = true
			m.ex_yaw = m.face_yaw + PI
			var ec = m._explore_cam()
			m.cam_target = ec[0]; m.cam_yaw = ec[1]; m.cam_pitch = ec[2]; m.cam_dist = ec[3]
			await _wait(3.0)

		"hat20":
			# the hat, followed at head height: walk, sharp turns, run onto the dock, a throw and a cheer, then the
			# hammock, where his hand takes it over his face and back
			var a = m.island.shore_pt(-1.32, 1.4)
			var dock_foot = Vector3(0.0, 0, m.island.dock_start_z + 1.5)
			var d0 = (dock_foot - a).normalized()
			_place(a, atan2(-d0.x, -d0.z))
			m.ex_yaw = m.face_yaw
			_snap_cam_now()
			m.demo_cam = true
			m.demo_track = [m.face_yaw + PI * 0.5 + 0.5, 0.14, 2.6, 0.75, true]
			var r = Vector3(d0.z, 0, -d0.x)
			await _walk_to(a + d0 * 2.2, false, 3.0)
			await _walk_to(a + d0 * 2.2 + r * 1.6, false, 2.0)
			await _walk_to(a + d0 * 0.8 + r * 1.6, false, 2.0)
			await _walk_to(a + d0 * 2.6 + r * 0.4, false, 2.2)
			await _walk_to(dock_foot, true, 4.0)
			await _walk_to(Vector3(0.2, 0, m.island.dock_end_z + 1.5), true, 4.0)
			await _wait(0.4)
			m._enter_throw()
			await _wait(1.0)
			m.demo_track = [m.player.rotation.y + PI * 0.5 + 0.55, 0.16, 2.6, 0.6, true]
			m._begin_aim(Vector2.ZERO)
			m.aim_pitch = 3.0
			var t0 = m.gt
			while m.gt - t0 < 1.4:
				m.charge_t = minf((m.gt - t0) / 1.2, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
				await m.get_tree().process_frame
			m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
			m._throw()
			m.fly_t = 0.0
			while m.state != m.State.READY:
				await m.get_tree().process_frame
			if m.boy.anim != "react":
				m.boy.react("cheer")
			await _wait(2.6)
			m._leave_throw()
			var hs = m._hammock_spot()
			var bed: Vector3 = hs[0]
			var side: Vector3 = hs[2]
			_place(bed + side * 2.2 + (m.island.hammock_b - m.island.hammock_a).normalized() * 0.8, atan2(side.x, side.z))
			m.ex_yaw = m.face_yaw + PI + 0.5
			_snap_cam_now()
			_free_cam()
			await _walk_to(bed + side * 1.2, false, 1.8)
			m._begin_rest("sleep")
			var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
			_fixed_cam(bed + Vector3(0, 0.25, 0), atan2(side.x, side.z) + 0.35, 0.32, 2.4)
			while m.rest_phase < 4:
				await m.get_tree().process_frame
			await _wait(1.6)
			m._wake()
			while m.mode != m.Mode.EXPLORE:
				await m.get_tree().process_frame
			await _wait(0.4)
			_free_cam()
			await _walk_to(head + side * 2.5, false, 2.0)
			await _wait(0.5)

		"boat14":
			# the rowboat by the dock riding the swell: from the sea, from the dock, then at night
			var bp = Vector3(2.3, 0.1, (m.island.dock_start_z + m.island.dock_end_z) * 0.5 - 1.0)
			_place(Vector3(0, 0, m.island.dock_start_z - 1.0), PI)
			m.demo_nocut = true
			_fixed_cam(bp, PI * 0.5 + 0.3, 0.1, 4.4)
			await _wait(6.0)
			_fixed_cam(bp, -PI * 0.5 + 0.35, 0.6, 3.4)
			await _wait(4.0)
			m._toggle_night()
			await _wait(3.0)
			_fixed_cam(bp, PI * 0.5 + 0.3, 0.1, 4.4)
			await _wait(5.0)
			m._toggle_night()
			m.demo_nocut = false

		"shoulder16":
			# close on the right shoulder in daylight: once round him at rest, the arms going up (cheer),
			# a standing and a crouching throw in slow motion, then a walk and a run cycle
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			m.demo_nocut = true
			m.ui_root.visible = false
			var y0 = m.player.rotation.y
			var tc = float(m.boy.clips["throw_stand"]["t_charge"])
			var tcc = float(m.boy.clips["throw_crouch"]["t_charge"])
			var cl = float(m.boy.clips["cheer"]["length"])
			var k = float(m._opt("shdist", "0.6"))
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist]
			for s: Array in [["idle", 0.0, 2.0, 5.0, PI - 0.1, 0.15, 0.12, 0.8],
					["cheer", 0.0, cl * 0.75, 3.0, PI * 0.8, PI * 0.65, 0.12, 0.9],
					["cheer", 0.0, cl * 0.75, 3.0, PI * 0.25, PI * 0.35, 0.2, 0.9],
					["charge", 0.0, 1.0 / tc * 1.15, 4.0, PI * 0.45, PI * 0.3, 0.15, 0.95],
					["charge", 0.0, 1.0 / tc * 1.15, 4.0, PI * 0.8, PI * 0.7, 0.12, 0.95],
					["charge_c", 0.0, 1.0 / tcc * 1.15, 4.0, PI * 0.45, PI * 0.6, 0.2, 0.95],
					["walk", 0.0, 2.0, 2.5, PI * 0.55, PI * 0.45, 0.1, 0.85],
					["run", 0.0, 2.0, 2.0, PI * 0.6, PI * 0.5, 0.1, 0.9]]:
				var t0 = m.gt
				var tgt = Vector3.ZERO
				while m.gt - t0 < float(s[3]):
					var u = (m.gt - t0) / float(s[3])
					var v = lerpf(float(s[1]), float(s[2]), u)
					m.player_ctrl.write_yaw(y0)
					match String(s[0]):
						"cheer":
							m.boy.debug_pose("cheer", 1.0, v)
						"charge", "charge_c":
							m.boy.debug_pose(s[0], v)
						"walk", "run":
							m.boy.debug_pose(s[0], 1.0, fmod(v, 1.0))
						_:
							m.boy.debug_pose("idle", 1.0, v)
					var sp = _shoulder_pos()
					tgt = sp if m.gt - t0 < 0.01 else tgt.lerp(sp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], float(s[7]) * k)
					await m.get_tree().process_frame
			m.boy.frozen = false
			m.demo_nocut = false
			m.ui_root.visible = true
			_free_cam()

		"polish19":
			# v19 close-ups: the nape (hat on, then off and close enough to see single strands), the vest's
			# underarm folding as the arms go up, the hair at night away from the torches, the mooring line
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			m.demo_nocut = true
			m.ui_root.visible = false
			var y0 = m.player.rotation.y
			var cl = float(m.boy.clips["cheer"]["length"])
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist, bone, up, hat, night]
			for s: Array in [["idle", 0.0, 3.0, 5.0, PI * 0.4, -PI * 0.3, 0.05, 0.38, "head", 0.0, true, false],
					["idle", 0.0, 2.0, 4.5, PI * 0.55, -PI * 0.1, 0.1, 0.22, "head", 0.04, false, false],
					["cheer", 0.0, cl * 0.75, 4.0, PI - 0.25, PI * 0.62, 0.05, 0.6, "spine_03", 0.06, true, false],
					["cheer", 0.0, cl * 0.75, 3.5, 0.1, PI * 0.35, 0.05, 0.55, "spine_03", 0.06, true, false],
					["idle", 0.0, 3.0, 5.0, PI * 0.8, PI * 0.2, 0.06, 0.42, "head", 0.03, true, true],
					["idle", 0.0, 2.0, 3.5, PI * 0.6, PI * 0.9, 0.08, 0.42, "head", 0.05, false, true]]:
				if bool(s[11]) != m.night_on:
					m._toggle_night()
					await _wait(2.9)
				m.boy.hat.visible = bool(s[10])
				var t0 = m.gt
				var tgt = Vector3.ZERO
				while m.gt - t0 < float(s[3]):
					var u = (m.gt - t0) / float(s[3])
					var v = lerpf(float(s[1]), float(s[2]), u)
					m.player_ctrl.write_yaw(y0)
					if s[0] == "cheer":
						m.boy.debug_pose("cheer", 1.0, v)
					else:
						m.boy.debug_pose("idle", 1.0, v)
					var bp = _bone_pos(s[8], s[9])
					tgt = bp if m.gt - t0 < 0.01 else tgt.lerp(bp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], s[7])
					await m.get_tree().process_frame
			m.boy.hat.visible = true
			_fixed_cam(m.island.boat_tie, 0.6, 0.3, 1.0)
			if m.night_on:
				m._toggle_night()
				await _wait(2.9)
			await _wait(4.0)
			m.boy.frozen = false
			m.demo_nocut = false
			m.ui_root.visible = true
			_free_cam()

		"polish18":
			# v18 close-ups: the hair under the brim in daylight, the card edges up close (hat off), the vest's
			# underarm with the arms going up, the hems swaying through a walk and a run, a crouching throw
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			m.demo_nocut = true
			m.ui_root.visible = false
			var y0 = m.player.rotation.y
			var tcc = float(m.boy.clips["throw_crouch"]["t_charge"])
			var cl = float(m.boy.clips["cheer"]["length"])
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist, bone, up, hat]
			for s: Array in [["idle", 0.0, 3.0, 6.0, PI * 0.95, PI * 0.3, 0.04, 0.42, "head", 0.03, true],
					["idle", 0.0, 2.0, 4.0, PI * 0.6, PI * 0.15, 0.08, 0.24, "head", 0.06, false],
					["cheer", 0.0, cl * 0.75, 4.0, PI * 0.5, PI * 0.38, 0.05, 0.5, "spine_03", 0.08, true],
					["walk", 0.0, 3.0, 4.0, PI * 0.6, PI * 0.4, 0.06, 1.1, "spine_01", 0.0, true],
					["run", 0.0, 3.0, 3.0, PI * 0.4, PI * 0.6, 0.06, 1.2, "spine_01", 0.0, true],
					["charge_c", 0.0, 1.0 / tcc * 1.15, 3.5, -PI * 0.3, -PI * 0.55, 0.12, 0.6, "upperarm_l", -0.05, true]]:
				m.boy.hat.visible = bool(s[10])
				var t0 = m.gt
				var tgt = Vector3.ZERO
				while m.gt - t0 < float(s[3]):
					var u = (m.gt - t0) / float(s[3])
					var v = lerpf(float(s[1]), float(s[2]), u)
					m.player_ctrl.write_yaw(y0)
					match String(s[0]):
						"cheer":
							m.boy.debug_pose("cheer", 1.0, v)
						"charge_c":
							m.boy.debug_pose(s[0], v)
						"walk", "run":
							m.boy.debug_pose(s[0], 1.0, fmod(v, 1.0))
						_:
							m.boy.debug_pose("idle", 1.0, v)
					var bp = _bone_pos(s[8], s[9])
					tgt = bp if m.gt - t0 < 0.01 else tgt.lerp(bp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], s[7])
					await m.get_tree().process_frame
			m.boy.hat.visible = true
			m.boy.frozen = false
			m.demo_nocut = false
			m.ui_root.visible = true
			_free_cam()

		"outfit17":
			# close on the hair and the clothes: round his head and his body at rest, a walk, a run and a
			# crouching throw (hair / hem sway), then the same orbits at night
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			m.demo_nocut = true
			m.ui_root.visible = false
			var y0 = m.player.rotation.y
			var tcc = float(m.boy.clips["throw_crouch"]["t_charge"])
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist, bone, up, night]
			for s: Array in [["idle", 0.0, 3.0, 6.0, PI - 0.1, -0.3, 0.1, 0.55, "head", 0.05, false],
					["idle", 0.0, 3.0, 6.0, PI * 0.9, PI * 0.05, 0.08, 1.05, "spine_01", 0.0, false],
					["walk", 0.0, 3.0, 3.0, PI * 0.65, PI * 0.4, 0.08, 1.2, "spine_01", 0.0, false],
					["run", 0.0, 3.0, 2.5, PI * 0.4, PI * 0.6, 0.08, 1.3, "spine_01", 0.0, false],
					["charge_c", 0.0, 1.0 / tcc * 1.15, 3.5, PI * 0.45, PI * 0.6, 0.15, 1.2, "spine_01", 0.0, false],
					["idle", 0.0, 3.0, 5.0, PI - 0.1, PI * 0.2, 0.1, 0.55, "head", 0.05, true],
					["idle", 0.0, 3.0, 5.0, PI * 0.9, PI * 0.3, 0.08, 1.05, "spine_01", 0.0, true]]:
				if bool(s[10]) != m.night_on:
					m._toggle_night()
					await _wait(2.9)
				var t0 = m.gt
				var tgt = Vector3.ZERO
				while m.gt - t0 < float(s[3]):
					var u = (m.gt - t0) / float(s[3])
					var v = lerpf(float(s[1]), float(s[2]), u)
					m.player_ctrl.write_yaw(y0)
					match String(s[0]):
						"charge_c":
							m.boy.debug_pose(s[0], v)
						"walk", "run":
							m.boy.debug_pose(s[0], 1.0, fmod(v, 1.0))
						_:
							m.boy.debug_pose("idle", 1.0, v)
					var bp = _bone_pos(s[8], s[9])
					tgt = bp if m.gt - t0 < 0.01 else tgt.lerp(bp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], s[7])
					await m.get_tree().process_frame
			if m.night_on:
				m._toggle_night()
			m.boy.frozen = false
			m.demo_nocut = false
			m.ui_root.visible = true
			_free_cam()

		"throw15":
			# aiming by swipe on the dock: left with a flick, right with a slow release (no spin), the
			# elevation slider pushed up to a too-steep launch, then a good one straight out
			_place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), 0.0)
			await _wait(0.3)
			m._enter_throw()
			await _wait(2.2)
			var c = m.throw_pad.pad_c
			await _demo_swipe(c, Vector2(-0.2, -0.38), 0.8, 1.0, true)
			await _demo_wait_ready([])
			await _demo_swipe(c, Vector2(0.24, -0.36), 0.8, 1.0, false)
			await _demo_wait_ready([])
			for k in 24:
				m._set_angles(lerpf(4.0, 28.0, (k + 1) / 24.0), 20.0)
				await m.get_tree().process_frame
			await _wait(0.5)
			await _demo_swipe(c, Vector2(0.06, -0.45), 0.6, 0.8, true)
			await _demo_wait_ready([])
			for k in 24:
				m._set_angles(lerpf(28.0, 4.0, (k + 1) / 24.0), 20.0)
				await m.get_tree().process_frame
			await _wait(0.5)
			await _demo_swipe(c, Vector2(-0.04, -0.46), 0.6, 0.8, true)
			await _demo_wait_ready([])

		"turn12":
			# turning on the spot: stick flicks of 180 / 90 / 135 degrees from a stand, a reversal out of a
			# walk, the 180 again in slow motion, then the same in the game camera
			var push = func(dirv: Vector3, mag: float, dur: float) -> void:
				var fwd = Vector3(-sin(m.ex_yaw), 0, -cos(m.ex_yaw))
				var right = Vector3(cos(m.ex_yaw), 0, -sin(m.ex_yaw))
				m.demo_input = Vector2(dirv.dot(right), -dirv.dot(fwd)) * mag
				await _wait(dur)
				m.demo_input = Vector2.ZERO
			# mid-dock: open, flat, and the camera can stand off to the side over the water
			var g0 = Vector3(0.0, 0.0, lerpf(m.island.dock_start_z, m.island.dock_end_z, 0.45))
			var gd = Vector3(0, 0, signf(m.island.dock_end_z - m.island.dock_start_z))
			var sd = gd.cross(Vector3.UP)
			for view in ["side", "slow", "game"]:
				_place(g0, atan2(-gd.x, -gd.z))
				m.ex_yaw = m.face_yaw
				_snap_cam_now()
				if view == "game":
					_free_cam()
				else:
					m.demo_cam = true
					m.demo_track = [atan2(sd.x, sd.z) + (0.45 if view == "side" else -0.35), 0.16, 3.2, 0.55, true]
				await _wait(0.8)
				if view == "slow":
					m._toast("慢放 0.4×：原地转身 180°", 1.6)
					Engine.time_scale = 0.4
					await push.call(-gd, 0.45, 0.5)
					await _wait(1.6)
					Engine.time_scale = 1.0
					await _wait(0.5)
					continue
				m._toast("原地转身 180°", 1.2)
				await push.call(-gd, 0.45, 0.4)
				await _wait(1.8)
				m._toast("左转 90°", 1.0)
				await push.call(sd, 0.45, 0.4)
				await _wait(1.5)
				m._toast("右后方 135°", 1.0)
				await push.call((-sd + gd).normalized(), 0.45, 0.4)
				await _wait(1.8)
				m._toast("走着突然掉头", 1.2)
				await push.call(gd, 0.6, 1.4)
				await push.call(-gd, 0.6, 1.6)
				await _wait(1.2)
			_free_cam()

		"gait10":
			# walk -> run -> stop seen from the front, then side-on, then a zig-zag (turns) in the game camera
			for view in ["front", "side", "game"]:
				var g0 = m.island.shore_pt(-1.38, 2.4)
				var gm = m.island.shore_pt(-1.15, 2.4)
				var g1 = m.island.shore_pt(-0.86, 2.6)
				var gd = (gm - g0).normalized()
				_place(g0, atan2(-gd.x, -gd.z))
				m.ex_yaw = m.face_yaw
				_snap_cam_now()
				m._toast({"front": "正面：走 → 跑 → 停", "side": "侧面：走 → 跑 → 停", "game": "转弯：走、跑"}[view], 1.6)
				if view == "game":
					_free_cam()
					await _wait(0.4)
					var sd = gd.cross(Vector3.UP)
					await _walk_to(g0 + gd * 2.5 + sd * 1.2, false, 4.0)
					await _walk_to(g0 + gd * 4.5 - sd * 1.0, false, 4.0)
					await _walk_to(g0 + gd * 8.0 + sd * 1.5, true, 4.0)
					await _walk_to(g0 + gd * 11.0 - sd * 1.5, true, 4.0)
					_stop_walk()
					await _wait(1.2)
				else:
					m.demo_cam = true
					m.demo_track = [PI + 0.25 if view == "front" else PI * 0.5, 0.06, 2.6, 0.62]
					await _wait(0.6)
					await _walk_to(gm, false, 5.0)
					await _walk_to(g1, true, 4.0)
					_stop_walk()
					await _wait(1.4)
			_free_cam()

		"throw10":
			# standing and half-kneeling throws, each from the front, side-on (throwing arm side) and from above
			_place(Vector3(0.2, 0, m.island.dock_end_z + 1.5), 0.0)
			await _wait(0.3)
			m._enter_throw()
			for k in 6:
				var crouch = k >= 3
				if crouch != (m.boy.stance == "crouch"):
					m._toggle_stance()
				await _wait(1.0)
				var v = k % 3
				m.demo_cam = true
				var hgt = 0.62 if not crouch else 0.45
				m.demo_track = [[m.aim_yaw + PI + 0.15, 0.05, 2.7, hgt, true], [m.aim_yaw - PI * 0.5, 0.05, 2.7, hgt, true],
					[m.aim_yaw + PI * 0.8, 1.15, 2.6, hgt, true]][v]
				m._toast(("半蹲" if crouch else "站立") + ["投掷 · 正面", "投掷 · 侧面", "投掷 · 俯视"][v], 1.6)
				m._begin_aim(Vector2.ZERO)
				m.aim_pitch = 3.0
				var t0 = m.gt
				while m.gt - t0 < 1.0:
					m.charge_t = minf((m.gt - t0) / 0.9, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
					await m.get_tree().process_frame
				m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
				m._throw()
				m.fly_t = 0.0
				await _wait(2.6)
				while m.state != m.State.READY:
					await m.get_tree().process_frame
				await _wait(0.4)
			_free_cam()

		"throw8":
			# the reworked throw: standing in the game camera, standing side-on, crouching side-on, crouching in the game camera
			_place(Vector3(0.0, 0, m.island.dock_end_z + 3.0), 0.0)
			await _walk_to(Vector3(0.2, 0, m.island.dock_end_z + 1.5), false, 2.0)
			await _wait(0.4)
			m._enter_throw()
			for k in 4:
				await _wait(0.5)
				if (k >= 2) != (m.boy.stance == "crouch"):
					m._toggle_stance()
					await _wait(0.9)
				var side = k == 1 or k == 2
				if side:
					m.demo_cam = true
					m.demo_track = [m.aim_yaw + PI * 0.5 + 0.1, 0.1, 2.6, 0.55 if k == 1 else 0.42, true]
				else:
					_free_cam()
				m._begin_aim(Vector2.ZERO)
				m.aim_pitch = 3.0
				var t0 = m.gt
				while m.gt - t0 < 1.5:
					m.charge_t = minf((m.gt - t0) / 1.2, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
					await m.get_tree().process_frame
				m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
				m._throw()
				m.fly_t = 0.0
				if side:
					await _wait(2.6)
				while m.state != m.State.READY:
					await m.get_tree().process_frame
				await _wait(0.8 if side else 2.0)
			_free_cam()
		"bump":
			# walking into things: palm, log by the fire, the lounger, a rock, wading against the dock, the bench, the fire ring
			var tests: Array = []
			for nm: String in ["椰子树", "坐木", "躺椅", "礁石", "码头", "长椅", "篝火"]:
				for w: Array in m.island.walls:
					if w[6] != nm:
						continue
					var found = _bump_spot(w)
					if not found.is_empty():
						tests.append(found)
						break
			for tst: Array in tests:
				var sp: Vector3 = tst[0]
				var dir: Vector3 = tst[1]
				_place(sp, atan2(-dir.x, -dir.z))
				m.ex_yaw = m.face_yaw + 0.5
				_snap_cam_now()
				m._toast(tst[2], 2.0)
				await _wait(0.3)
				await _drive_dir(dir, 1.6, false)
				await _drive_dir(dir.rotated(Vector3.UP, 0.7), 1.8, false)
				await _drive_dir(dir.rotated(Vector3.UP, -0.7), 2.0, true)
				await _wait(0.3)
		"sit":
			# bench by the lighthouse, then a log at the campfire, then the lounger
			for i: int in [0, 2, 4]:
				var st: Dictionary = m.island.seats[i]
				var face: Vector3 = st["face"]
				var side = face.cross(Vector3.UP)
				_place((st["approach"] as Vector3) + face * 2.2 + side * 0.8, 0.0)
				var to = (st["approach"] as Vector3) - m.player.position
				m.face_yaw = atan2(-to.x, -to.z)
				m.player_ctrl.write_yaw(m.face_yaw)
				m.ex_yaw = m.face_yaw + 0.35
				_snap_cam_now()
				await _walk_to((st["approach"] as Vector3) + face * 0.5, false, 3.0)
				await _wait(0.5)
				m._on_action()
				while m.rest_phase < 4:
					await m.get_tree().process_frame
				await _wait(3.0)
				m._wake()
				while m.mode != m.Mode.EXPLORE:
					await m.get_tree().process_frame
				await _drive_dir(face, 1.0, false)
				await _wait(0.3)
		"fire":
			# campfire close-up, slowly circling
			var c = m.island.campfire_pos
			_place(c + Vector3(4.0, 0, 4.0), 0.0)
			var t1 = m.gt
			while m.gt - t1 < 9.0:
				var u = (m.gt - t1) / 9.0
				_fixed_cam(c + Vector3(0, 0.4, 0), 0.4 + u * 1.2, 0.2 + 0.1 * sin(u * PI), 2.3 + u * 1.2)
				await m.get_tree().process_frame
			_free_cam()
		"prints":
			# footprints along the waterline: the swash wipes out the low ones, the dry ones stay (and fade slowly)
			var a = m.island.shore_pt(-1.30, 2.0)
			var b = m.island.shore_pt(-1.27, 0.95)
			var c = m.island.shore_pt(-1.14, 0.95)
			var e = m.island.shore_pt(-1.11, 2.0)
			var f = m.island.shore_pt(-1.06, 2.1)
			var mid = m.island.shore_pt(-1.19, 1.45)
			var sea = Island.dir_at(-1.19)
			_place(a, 0.0)
			_fixed_cam(mid + Vector3(0, 0.1, 0), atan2(sea.x, sea.z), 1.08, 4.6)
			await _wait(0.4)
			for w in [b, c, e, f]:
				await _walk_to(w, false, 6.0)
			_stop_walk()
			await _wait(22.0)

		"recover":
			# the arm after the release: stand and half-kneel, side-on from the throwing side, each once at
			# full speed and once at half speed
			_place(Vector3(0.2, 0, m.island.dock_end_z + 1.5), 0.0)
			await _wait(0.3)
			m._enter_throw()
			for k in 4:
				var crouch = k >= 2
				if crouch != (m.boy.stance == "crouch"):
					m._toggle_stance()
				await _wait(1.0)
				m.demo_cam = true
				m.demo_track = [m.aim_yaw + PI - 0.7, 0.1, 2.6, 0.62 if not crouch else 0.45, true]
				m._toast(("半蹲" if crouch else "站立") + ("投掷 · 慢放 0.5×" if k % 2 == 1 else "投掷"), 1.6)
				m._begin_aim(Vector2.ZERO)
				m.aim_pitch = 3.0
				var t0 = m.gt
				while m.gt - t0 < 1.0:
					m.charge_t = minf((m.gt - t0) / 0.9, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
					await m.get_tree().process_frame
				m.charge_t = 0.9 * m.POWER_CYCLE * 0.5
				if k % 2 == 1:
					Engine.time_scale = 0.5
				m._throw()
				m.fly_t = 0.0
				await _wait(2.6)
				Engine.time_scale = 1.0
				while m.state != m.State.READY:
					await m.get_tree().process_frame
				await _wait(0.4)
			_free_cam()
		"lie":
			# the bench, then the three logs by the fire (front, back, front): sit, lie back with the hat on
			# the face and a leg crossed, nap a moment, get up
			for i: int in [0, 1, 2, 3]:
				var st: Dictionary = m.island.seats[i]
				var face: Vector3 = st["face"]
				var from_back = i == 2
				var spot: Vector3 = (st["back_approach"] as Vector3) - face * 1.6 if from_back else (st["approach"] as Vector3) + face * 1.6
				_place(m._blocked_by(spot), 0.0)
				var to = (st["top"] as Vector3) - m.player.position
				m.face_yaw = atan2(-to.x, -to.z)
				m.player_ctrl.write_yaw(m.face_yaw)
				m.ex_yaw = m.face_yaw + 0.5
				_snap_cam_now()
				m._toast("%s · 坐下 → 躺下 → 起来" % ("长椅" if i == 0 else "篝火边的木头 %d%s" % [i, "（从背面坐）" if from_back else ""]), 2.0)
				await _walk_to(m._blocked_by((st["back_approach"] as Vector3) - face * 0.6 if from_back else (st["approach"] as Vector3) + face * 0.6), false, 2.5)
				await _wait(0.3)
				m._on_action()
				while m.rest_phase != 4:
					await m.get_tree().process_frame
				await _wait(1.2)
				m._lie_down()
				await _wait(m.SEAT_LIE_DUR * 0.4)
				_fixed_cam(m.rest_lie + Vector3(0, 0.15, 0), atan2(m.seat_face.x, m.seat_face.z) + 0.45, 0.32, 2.2)
				while m.rest_phase != 4:
					await m.get_tree().process_frame
				await _wait(3.2 if i == 0 else 2.2)
				m._wake()
				while m.mode != m.Mode.EXPLORE:
					await m.get_tree().process_frame
				_free_cam()
				await _wait(0.6)
		"shore":
			# a full surf cycle from above, then low along the beach
			var sea = Island.dir_at(-1.05)
			var p = m.island.shore_pt(-1.05, 1.4)
			var along = sea.cross(Vector3.UP)
			_place(p, atan2(-sea.x, -sea.z) + 0.5)
			_fixed_cam(p + sea * 1.6 + Vector3(0, 0.2, 0), atan2(sea.x, sea.z) + 0.55, 0.62, 5.0)
			await _wait(10.5)
			_fixed_cam(p + sea * 1.0 + Vector3(0, 0.3, 0), atan2(along.x, along.z) - 0.5, 0.16, 3.6)
			await _wait(10.5)
			var sea2 = Island.dir_at(2.2)
			var p2 = m.island.shore_pt(2.2, 1.4)
			_place(p2, atan2(-sea2.x, -sea2.z) + 0.5)
			_fixed_cam(p2 + sea2 * 1.2 + Vector3(0, 0.2, 0), atan2(sea2.x, sea2.z) - 0.4, 0.35, 4.5)
			await _wait(10.0)
			_free_cam()
		"wade":
			# walk into the sea by the dock: legs go under, tinted and wobbling; foam collar + rings follow
			var a = m.island.shore_pt(-1.2, 0.6)
			var b = m.island.shore_pt(-1.24, -1.9)
			var dv = (b - a).normalized()
			_place(a, atan2(-dv.x, -dv.z))
			m.demo_cam = true
			m.demo_track = [atan2(dv.x, dv.z) + PI * 0.5 + 0.4, 0.14, 2.3, 0.35, true]
			await _walk_to(b, false, 7.0)
			await _wait(2.5)
			await _walk_to(m.island.shore_pt(-1.34, -2.2), false, 4.0)
			_free_cam()
			await _wait(0.5)
			await _walk_to(m.island.shore_pt(-1.2, -1.2), false, 4.0)
			await _wait(2.0)
		"night":
			# dusk falls by the campfire, fireflies, sit by the fire, then the dock: the moon path on the sea
			var c = m.island.campfire_pos
			_place(c + Vector3(2.6, 0, 2.6), 0.0)
			_fixed_cam(c + Vector3(0, 0.5, 0), 0.7, 0.28, 5.2)
			await _wait(1.2)
			m._toggle_night()
			await _wait(4.5)
			var st: Dictionary = m.island.seats[1]
			_free_cam()
			await _walk_to(m._blocked_by((st["approach"] as Vector3) + (st["face"] as Vector3) * 0.6), false, 3.0)
			m._on_action()
			while m.rest_phase != 4:
				await m.get_tree().process_frame
			await _wait(4.0)
			m._wake()
			while m.mode != m.Mode.EXPLORE:
				await m.get_tree().process_frame
			_free_cam()
			_place(Vector3(0.2, 0, m.island.dock_end_z + 1.5), 0.1)
			await _wait(0.5)
			m._enter_throw()
			await _wait(1.5)
			m._begin_aim(Vector2.ZERO)
			m.aim_pitch = 3.0
			var t0 = m.gt
			while m.gt - t0 < 1.2:
				m.charge_t = minf((m.gt - t0) / 1.1, 1.0) * 0.9 * m.POWER_CYCLE * 0.5
				await m.get_tree().process_frame
			m._throw()
			while m.state != m.State.READY:
				await m.get_tree().process_frame
			await _wait(1.0)
			m._leave_throw()
			_fixed_cam(Vector3(0, 1.0, m.island.dock_start_z - 2.0), 2.6, 0.32, 26.0)
			var t1 = m.gt
			while m.gt - t1 < 5.0:
				_fixed_cam(Vector3(0, 1.0, m.island.dock_start_z - 2.0), 2.6 + (m.gt - t1) * 0.08, 0.32, 26.0)
				await m.get_tree().process_frame
			m._toggle_night()
			await _wait(3.5)
			_free_cam()

## steer with the stick towards a world direction (camera-relative, like a player would)

func _drive_dir(dir: Vector3, sec: float, run: bool) -> void:
	m.demo_run = run
	var t0 = m.gt
	while m.gt - t0 < sec:
		var fwd = Vector3(-sin(m.ex_yaw), 0, -cos(m.ex_yaw))
		var right = Vector3(cos(m.ex_yaw), 0, -sin(m.ex_yaw))
		m.demo_input = Vector2(dir.dot(right), -dir.dot(fwd)) * (1.0 if run else 0.75)
		await m.get_tree().process_frame
	m.demo_input = Vector2.ZERO
	m.demo_run = false

## a clear spot ~1.5 m from a wall with flat ground towards it (collision demo)

func _bump_spot(w: Array) -> Array:
	var a: Vector2 = w[1]
	var c = a if w[0] != "s" else (a + (w[2] as Vector2)) * 0.5
	var ext: float = float(w[3]) if w[0] == "c" else (0.3 if w[0] == "s" else (w[2] as Vector2).x)
	for k in 12:
		var d = Vector2(cos(k * TAU / 12.0 + 0.3), sin(k * TAU / 12.0 + 0.3))
		var s = c + d * (ext + 1.6)
		var h = m._surface(s.x, s.y)
		var sp = Vector3(s.x, h, s.y)
		if not m._can_stand(h, s.x, s.y) or m.penetration(sp) > 0.0 or not m._wall_hits_y(w, h) or Island.wall_dist(w, s).x < 1.2:
			continue
		return [sp, Vector3(-d.x, 0, -d.y), "撞上%s：沿着它滑开" % w[6]]
	return []

## drive the on-screen joystick with real touch events (like a finger on the phone)

func _stick_walk(dirs: Array, sec_each: float) -> void:
	var vs = m.get_viewport().get_visible_rect().size
	var c = Vector2(vs.x * 0.14, vs.y * 0.86)
	var keep = m.demo_mode
	m.demo_mode = false
	var ev = InputEventScreenTouch.new()
	ev.index = 0; ev.position = c; ev.pressed = true
	m.get_viewport().push_input(ev, true)
	var last = c
	for dv: Vector2 in dirs:
		var t0 = m.gt
		while m.gt - t0 < sec_each:
			var to = c + dv.normalized() * 50.0
			var dr = InputEventScreenDrag.new()
			dr.index = 0; dr.position = last.lerp(to, 0.3); dr.relative = dr.position - last
			last = dr.position
			m.get_viewport().push_input(dr, true)
			await m.get_tree().process_frame
	var up = InputEventScreenTouch.new()
	up.index = 0; up.position = last; up.pressed = false
	m.get_viewport().push_input(up, true)
	m.demo_mode = keep

func _snap_cam_now() -> void:
	var c = m._explore_cam()
	m.cam_target = c[0]; m.cam_yaw = c[1]; m.cam_pitch = c[2]; m.cam_dist = c[3]

