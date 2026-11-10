extends RefCounted
## Regression check: every action (hammock, towel, benches / logs, dock throw + cheer / oops, view mode)
## must hand control back - afterwards the joystick has to move the kid and the walk animation has to play.
## The walk / run cycles must swing the arms contralaterally (left foot forward = right arm forward).
## Walking into every kind of solid thing (trees, rocks, logs, hut, boats, dock...) must never overlap it,
## and a glancing walk must slide along instead of sticking.
## godot --headless --path . --fixed-fps 30 -- --selftest      (exit code 0 = pass)

const ArmClearance := preload("res://dev/arm_clearance.gd")

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

static func _corr(a: Array[float], b: Array[float]) -> float:
	var ma := 0.0
	var mb := 0.0
	for i in a.size():
		ma += a[i] / a.size()
		mb += b[i] / b.size()
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in a.size():
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / maxf(sqrt(saa * sbb), 1e-9)

## contralateral gait: sample the imported walk / run cycles through the real mixer and correlate the
## forward offsets (along the kid's facing, relative to the pelvis) of feet, hands, hips and shoulders
func _gait_check() -> void:
	var b: Boy = m.boy
	var sk: Skeleton3D = b.skel
	var fwd: Vector3 = -b.global_basis.z.normalized()
	for run: bool in [false, true]:
		var s := {}
		for k in ["foot_l", "foot_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "upperarm_l", "upperarm_r"]:
			s[k] = [] as Array[float]
		for i in 40:
			b.act_w = 0.0
			b.move_w = 1.0
			b.run_k = 1.0 if run else 0.0
			b.phase = i / 40.0
			b._apply_mixer()
			var pel := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
			for k: String in s:
				var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(k)).origin
				(s[k] as Array[float]).append((p - pel).dot(fwd))
		var hips: Array[float] = []
		var shoulders: Array[float] = []
		for i in 40:
			hips.append(s["thigh_l"][i] - s["thigh_r"][i])
			shoulders.append(s["upperarm_l"][i] - s["upperarm_r"][i])
		if "--gaitcsv" in OS.get_cmdline_user_args():
			for i in 40:
				print("GAITCSV %s,%.3f,%.4f,%.4f,%.4f,%.4f" % ["run" if run else "walk", i / 40.0, s["foot_l"][i], s["foot_r"][i], s["hand_l"][i], s["hand_r"][i]])
		var c_ll := _corr(s["foot_l"], s["hand_l"])
		var c_rr := _corr(s["foot_r"], s["hand_r"])
		var c_lr := _corr(s["foot_l"], s["hand_r"])
		var c_hip := _corr(s["foot_l"], hips)
		var c_sh := _corr(s["foot_l"], shoulders)
		var ok := c_ll < -0.5 and c_rr < -0.5 and c_lr > 0.5 and c_hip > 0.5 and c_sh < -0.5
		var tag := "gait " + ("run" if run else "walk")
		print("SELFTEST %-28s %s  (footL~handL %.2f, footR~handR %.2f, footL~handR %.2f, hips %.2f, shoulders %.2f)" % [tag, "ok" if ok else "FAIL", c_ll, c_rr, c_lr, c_hip, c_sh])
		if not ok:
			fails.append(tag + " not contralateral")
	b.move_w = 0.0
	b.run_k = 0.0
	b.phase = 0.0
	b._to_idle()
	b._apply_mixer()

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

var jitter := 0

## steer the kid with the virtual stick towards a world direction for `sec` seconds; returns the
## worst overlap with any solid thing seen on the way (frames where he snaps backwards go to `jitter`)
func _drive(dir: Vector3, sec: float, run_: bool) -> float:
	var worst := 0.0
	jitter = 0
	var last := Vector3.ZERO
	var prev_p: Vector3 = m.player.position
	m.demo_run = run_
	for i in int(sec * 30.0):
		var yaw: float = m.ex_yaw
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		m.demo_input = Vector2(dir.dot(right), -dir.dot(fwd)) * (1.0 if run_ else 0.75)
		await m.get_tree().process_frame
		var pp: Vector3 = m.player.position
		var stp := Vector3(pp.x - prev_p.x, 0, pp.z - prev_p.z)
		if stp.length() > 0.004 and last.length() > 0.004 and stp.dot(last) < -0.2 * stp.length() * last.length():
			jitter += 1
		if stp.length() > 0.004:
			last = stp
		prev_p = pp
		var pn: float = m.penetration(pp)
		if pn > 0.01 and "--bumpdbg" in OS.get_cmdline_user_args():
			for wi: int in m.island.walls_near(Vector2(pp.x, pp.z)):
				var ww: Array = m.island.walls[wi]
				var dd: float = Island.wall_dist(ww, Vector2(pp.x, pp.z)).x
				if m._wall_hits_y(ww, pp.y) and dd < m.BOY_R:
					print("BUMPDBG ", ww, " d ", dd, " at ", pp, " mode ", m.mode, " frame ", i)
		worst = maxf(worst, pn)
	m.demo_input = Vector2.ZERO
	m.demo_run = false
	await _frames(2)
	return worst

static func _wall_centre(w: Array) -> Vector2:
	return ((w[1] as Vector2) + (w[2] as Vector2)) * 0.5 if w[0] == "s" else (w[1] as Vector2)

static func _wall_extent(w: Array) -> float:
	match w[0] as String:
		"c": return float(w[3])
		"s": return ((w[2] as Vector2) - (w[1] as Vector2)).length() * 0.5 + float(w[3])
		_: return (w[2] as Vector2).length()

## candidate (start, direction) pairs that run straight at the wall: radial for posts / trees, square on
## to the sides (and ends) of logs, boats, boxes
static func _approaches(w: Array) -> Array:
	var out: Array = []
	var a: Vector2 = w[1]
	match w[0] as String:
		"c":
			for k in 8:
				var d := Vector2(cos(k * TAU / 8.0 + 0.2), sin(k * TAU / 8.0 + 0.2))
				out.append([a + d * (float(w[3]) + 1.3), -d])
		"s":
			var b: Vector2 = w[2]
			var n := (b - a).orthogonal().normalized()
			var r: float = w[3]
			for t: float in [0.5, 0.25, 0.75]:
				for sg: float in [1.0, -1.0]:
					out.append([a.lerp(b, t) + n * sg * (r + 1.3), -n * sg])
			var ax := (b - a).normalized()
			out.append([b + ax * (r + 1.3), -ax])
			out.append([a - ax * (r + 1.3), ax])
		_:
			var half: Vector2 = w[2]
			var yaw: float = w[3]
			for t: float in [0.0, 0.5, -0.5, 0.8, -0.8]:
				for side in 4:
					var nl := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][side] as Vector2
					var along := Vector2(nl.y, nl.x) * t * (half.y if side < 2 else half.x)
					var lp := Vector2(nl.x * (half.x + 1.3), nl.y * (half.y + 1.3)) + Vector2(along.x * (1 if side >= 2 else 0), along.y * (1 if side < 2 else 0))
					out.append([a + Island._rot(lp, yaw), -Island._rot(nl, yaw)])
	return out

## a start spot from which the kid can walk straight at the wall over plain ground
func _approach_spot(w: Array, cand: Array) -> Array:
	var s: Vector2 = cand[0]
	var dir: Vector2 = cand[1]
	var h: float = m._surface(s.x, s.y)
	var sp := Vector3(s.x, h, s.y)
	if not m._can_stand(h, s.x, s.y) or m.penetration(sp) > 0.0 or not m._wall_hits_y(w, h):
		return []
	var prev := h
	for j in range(1, 13):
		var q := s + dir * (1.3 * j / 12.0)
		var hq: float = m._surface(q.x, q.y)
		if not m._can_stand(prev, q.x, q.y) and j < 12:
			return []
		prev = hq
	return [sp, Vector3(dir.x, 0, dir.y)]

func _collision_check() -> void:
	var walls: Array = m.island.walls
	var tested := {}
	var kinds := {}
	for w: Array in walls:
		kinds[w[6]] = true
	for i in walls.size():
		var w: Array = walls[i]
		var nm: String = w[6]
		if int(tested.get(nm, 0)) >= 2:
			continue
		var cands := _approaches(w)
		for k in cands.size():
			var a := _approach_spot(w, cands[k])
			if a.is_empty():
				continue
			var sp: Vector3 = a[0]
			var dir: Vector3 = a[1]
			# head on (running), then a glancing walk that has to slide past
			m._place(sp, atan2(-dir.x, -dir.z))
			await _frames(3)
			var pen := await _drive(dir, 1.6, true)
			var gap: float = Island.wall_dist(w, Vector2(m.player.position.x, m.player.position.z)).x - m.BOY_R
			if gap > 0.08:
				continue   # something else stopped him first: try another side
			var side := dir.rotated(Vector3.UP, 0.75 if k % 2 == 0 else -0.75)
			m._place(sp, atan2(-side.x, -side.z))
			await _frames(3)
			var p0: Vector3 = m.player.position
			pen = maxf(pen, await _drive(side, 2.4, false))
			var moved: float = Vector2(m.player.position.x - p0.x, m.player.position.z - p0.z).length()
			var ok := pen <= 0.01 and moved > 0.6 and jitter <= 1
			print("SELFTEST %-28s %s  (deepest overlap %.3f m, glancing walk slid %.2f m, back-steps %d)" % ["bump " + nm, "ok" if ok else "FAIL", pen, moved, jitter])
			if not ok:
				fails.append("bump " + nm)
			tested[nm] = int(tested.get(nm, 0)) + 1
			break
	var missing: Array = []
	for nm: String in kinds:
		if not tested.has(nm):
			missing.append(nm)
	print("SELFTEST bump: %d kinds tested, not reachable on foot: %s" % [tested.size(), ", ".join(missing)])
	for need: String in ["椰子树", "礁石", "坐木", "篝火", "长椅", "躺椅", "路牌", "钓鱼小屋", "小船", "码头", "码头木桩", "灌木", "灯塔"]:
		if not tested.has(need):
			fails.append("bump %s never tested" % need)

## sit on seat i coming from `from` (front / back / end); lie back along it too when `lie`
func _sit(i: int, from: String, lie: bool) -> void:
	var st: Dictionary = m.island.seats[i]
	var face: Vector3 = st["face"]
	var top: Vector3 = st["top"]
	var side := face.cross(Vector3.UP).normalized()
	var tag := "%s #%d (%s%s)" % [st["name"], i, from, ", lie" if lie else ""]
	var spot: Vector3
	match from:
		"back": spot = (st["back_approach"] as Vector3) - face * 0.5 + side * 0.3
		"end": spot = top + side * 1.05 - face * 0.1
		_: spot = (st["approach"] as Vector3) + face * 0.5 + side * 0.4
	spot.y = 0.0
	spot = m._blocked_by(spot)
	m._place(spot, 0.0)
	await _frames(5)
	if m.action_kind != "seat" or m.seat_i != i:
		fails.append("no sit prompt at " + tag)
		return
	var want_face := -face if from == "back" else face
	if from != "end" and m.seat_face.dot(want_face) < 0.9:
		fails.append("sits the wrong way round on " + tag)
	m._on_action()
	if not await _until(func() -> bool: return m.rest_phase == 4, 12.0):
		fails.append("never sat on " + tag)
		return
	await _wait(0.8)
	var pel: Vector3 = (m.boy.parts["pelvis"] as Node3D).global_position
	var sit_h := pel.y - top.y
	var note := "sat (pelvis %.2f m over the seat" % sit_h
	if st["two_sided"]:
		# the logs rest on levelled sand: no slope under the log ends or the feet on either side
		var base: float = top.y - m.island.SEAT_TOP
		var worst := 0.0
		for o: Vector3 in [face * 0.4, -face * 0.4, side * 0.65, -side * 0.65]:
			worst = maxf(worst, absf(Island.ground_h(top.x + o.x, top.z + o.z) - base))
		note += ", ground off level %.3f m" % worst
		if worst > 0.01:
			fails.append("ground not level under " + tag)
	if lie:
		if not m.lie_btn.visible:
			fails.append("no lie button on " + tag)
			return
		m._lie_down()
		if not await _until(func() -> bool: return m.rest_phase == 4 and m.seat_lying, 6.0):
			fails.append("never lay down on " + tag)
			return
		await _wait(1.2)
		pel = (m.boy.parts["pelvis"] as Node3D).global_position
		var head: Vector3 = (m.boy.parts["head"] as Node3D).global_position
		note += ", lying pelvis %.2f / head %.2f m over it, hat %s" % [pel.y - top.y, head.y - top.y, m.boy.hat_mode]
		if m.boy.hat_mode != "face":
			fails.append("hat not over the face on " + tag)
		if pel.y - top.y < 0.0 or pel.y - top.y > 0.25 or absf(head.y - pel.y) > 0.3:
			fails.append("not lying flat on " + tag)
	m._wake()
	if not await _until(func() -> bool: return m.mode == m.Mode.EXPLORE, 8.0):
		fails.append("never got up from " + tag)
		return
	await _frames(3)
	print("SELFTEST seat %-26s %s)" % [tag, note])
	await _can_walk("after " + tag)

## every frame of the throws (charge, release, follow-through, recovery) and the locomotion cycles:
## no part of either arm inside the torso, the other arm or the legs (game cm = skeleton m x 85)
func _arm_check() -> void:
	const MARGIN := {"r": 0.01, "l": 0.01, "r_ua": -0.01, "l_ua": -0.01, "arms": 0.01, "legs": 0.0}
	const NAMES := {"r": "R elbow/forearm/hand", "l": "L elbow/forearm/hand", "r_ua": "R upper arm", "l_ua": "L upper arm",
		"arms": "arm-arm", "legs": "arm-legs"}
	var res: Dictionary = ArmClearance.new().run(m, ["throw_stand", "throw_crouch", "cheer", "oops", "idle", "walk", "run"])
	for clip: String in res:
		var w: Dictionary = res[clip]
		var bad: Array[String] = []
		var parts: Array[String] = []
		for k: String in MARGIN:
			var c: float = w[k][0]
			parts.append("%s %+.1f cm" % [NAMES[k], c * 85.0])
			if c < MARGIN[k]:
				bad.append("%s %+.1f cm (%s at %.2f s)" % [NAMES[k], c * 85.0, w[k][1], w[k][2]])
		var tag := "arm clearance " + clip
		print("SELFTEST %-28s %s  (%d frames; min %s)" % [tag, "ok" if bad.is_empty() else "FAIL", w["frames"], ", ".join(parts)])
		if not bad.is_empty():
			fails.append(tag + ": " + "; ".join(bad))


func run(main: Node) -> void:
	m = main
	await _wait(0.5)
	_arm_check()
	_gait_check()
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
	# bench, each campfire log (from the fire side, from behind, from its end), lounger; lie on bench + logs
	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		await _sit(i, "front", st["can_lie"])
		if st["two_sided"]:
			await _sit(i, "back", false)
			await _sit(i, "end", false)
			await _sit(i, "back", true)
	await _collision_check()
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
			if m.boy.anim == "throw" or m.boy.act_w > 0.05 and m.boy.anim != "react":
				fails.append("throw clip did not hand back to idle (anim %s, act_w %.2f)" % [m.boy.anim, m.boy.act_w])
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
	# night: the button fades everything over, the lamps / beams come on, and back to day
	m.night_btn.pressed.emit()
	await _wait(3.0)
	var lit: bool = m.night_fx.visible and m.night_fx.beacon_light.visible and m.night_fx.beam_pivot.visible
	var moon_e: float = m.sun.light_energy
	print("SELFTEST night                 %s  (k %.2f, button '%s', moonlight %.2f, fire %.2f, lamps+beams %s)" % [
			"ok" if m.night_k > 0.999 and lit else "FAIL", m.night_k, m.night_btn.text, moon_e, m.island.campfire.light.light_energy, lit])
	if m.night_k < 0.999 or not lit or m.night_btn.text != "白天":
		fails.append("night mode did not come on")
	await _can_walk("at night")
	m.night_btn.pressed.emit()
	await _wait(3.0)
	print("SELFTEST day again             %s  (k %.2f, button '%s', fx %s)" % ["ok" if m.night_k < 0.001 and not m.night_fx.visible else "FAIL", m.night_k, m.night_btn.text, m.night_fx.visible])
	if m.night_k > 0.001 or m.night_fx.visible:
		fails.append("day did not come back")
	await _can_walk("after night")
	print("SELFTEST %s" % ("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
	m.get_tree().quit(0 if fails.is_empty() else 1)
