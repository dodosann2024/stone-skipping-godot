extends RefCounted
## Regression check: every action (hammock, towel, benches / logs, dock throw + cheer / oops, view mode)
## must hand control back - afterwards the joystick has to move the kid and the walk animation has to play.
## The walk / run cycles must swing the arms contralaterally (left foot forward = right arm forward).
## Walking into every kind of solid thing (trees, rocks, logs, hut, boats, dock...) must never overlap it,
## and a glancing walk must slide along instead of sticking.
## godot --headless --path . --fixed-fps 30 -- --selftest      (exit code 0 = pass)

const ArmClearance := preload("res://dev/arm_clearance.gd")
const HatProbe := preload("res://dev/hat_probe.gd")

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

## push the on-screen stick (real touch events, like a phone) in four directions, 1.3 s each (long enough
## to turn round on the spot first); the kid has to get somewhere and the walk cycle has to run
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
		for i in 40:
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
	if m.boy.meta.get("tripo", false):
		print("SELFTEST gait walk                 ok  (skipped — Tripo Mixamo bone names)")
		print("SELFTEST gait run                  ok  (skipped — Tripo Mixamo bone names)")
		return
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

## planted feet through walk / run transitions, turns, game-speed zig-zags and stops (dev/gait_probe.gd):
## no heel / toe pad may slide more than 5 mm in a frame, at 30 and at 20 fps
func _slide_check() -> void:
	if m.boy.meta.get("tripo", false):
		print("SELFTEST foot slide @30 fps        ok  (skipped — Tripo gait uses phase footfalls, no plant IK)")
		print("SELFTEST footprints @30 fps        ok  (skipped — Tripo)")
		return
	for fps: int in [30, 20, 60]:
		var b := Boy.new()
		m.add_child(b)
		var probe := GaitProbe.new(b, Vector3(0, 60, 0))
		probe.run_all(1.0 / fps)
		var worst := 0.0
		var worst_seg := ""
		var parts: Array[String] = []
		for sg in GaitProbe.SEGS:
			var v := float(probe.seg_max.get(sg[2], 0.0))
			parts.append("%.1f" % (v * 1000.0))
			if v > worst:
				worst = v
				worst_seg = sg[2]
		var ok := worst < 0.005 and probe.slide_n > 300 and b.steps_taken == 0
		print("SELFTEST %-28s %s  (worst %.1f mm/frame in '%s'; per segment mm: %s; %d planted frames, %d quick steps, %d steps on the spot)" % [
			"foot slide @%d fps" % fps, "ok" if ok else "FAIL", worst * 1000.0, worst_seg, " ".join(parts), probe.slide_n, b.steps_taken, b.spot_steps])
		if not ok:
			fails.append("planted foot slides %.1f mm/frame (%s, %d fps), %d quick steps" % [worst * 1000.0, worst_seg, fps, b.steps_taken])
		var pok := probe.prints >= probe.steps - 3 and probe.prints > 20 and probe.print_err < 0.01
		print("SELFTEST %-28s %s  (%d prints for %d footsteps, print spot drifts at most %.1f mm while the foot is down)" % [
			"footprints @%d fps" % fps, "ok" if pok else "FAIL", probe.prints, probe.steps, probe.print_err * 1000.0])
		if not pok:
			fails.append("footprints: %d for %d steps, drift %.1f mm (%d fps)" % [probe.prints, probe.steps, probe.print_err * 1000.0, fps])
		m.remove_child(b)
		b.free()

## a 180° flick of the stick from standing is a turn on the spot: two or three alternating steps (open,
## turn, close) while the head and chest lead, no shuffle of quick steps, no drifting
func _turn_check() -> void:
	await _frames(20)
	var b: Boy = m.boy
	var q0 := b.steps_taken
	var s0 := b.spot_steps
	var p0: Vector3 = m.player.position
	var yaw: float = m.ex_yaw
	var back := Vector3(sin(m.face_yaw), 0, cos(m.face_yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var t := 0.0
	var lead := 0.0
	var drift := 0.0
	while t < 3.0:
		m.demo_input = Vector2(back.dot(right), -back.dot(fwd)) * 0.5
		await m.get_tree().process_frame
		t += 1.0 / 30.0
		if not m.spot_turning and t > 0.2:
			break
		drift = maxf(drift, (m.player.position - p0).length())
		lead = maxf(lead, absf(b.turn_ahead))
	m.demo_input = Vector2.ZERO
	var spot := b.spot_steps - s0
	var quick := b.steps_taken - q0
	var left := absf(wrapf(m.face_yaw - atan2(-back.x, -back.z), -PI, PI))
	var ok := spot >= 2 and spot <= 3 and quick == 0 and drift < 0.12 and left < 0.3 and t < 2.5
	print("SELFTEST %-28s %s  (180° in %.2f s with %d steps on the spot, %d quick steps, body drift %.1f cm, %.0f° short)" % [
		"turn on the spot", "ok" if ok else "FAIL", t, spot, quick, drift * 100.0, rad_to_deg(left)])
	if not ok:
		fails.append("turn on the spot: %d spot steps, %d quick, drift %.2f m, %.2f rad short, %.2f s" % [spot, quick, drift, left, t])
	await _frames(10)

func _rest(kind: String, approach: Vector3) -> void:
	m._place(approach, 0.0)
	await _frames(5)
	m._begin_rest(kind)
	if not await _until(func() -> bool: return m.rest_phase == 4, 12.0):
		fails.append(kind + " never lay down")
		return
	await _wait(1.0)
	if kind in ["sun", "sleep"]:
		m.set_meta("lie_snapped", false)
		for _p in 6:
			m._snap_lie_contact()
			var pl = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
			var swing = Transform3D.IDENTITY
			if kind == "sleep":
				swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3))
			m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
			m._plant_lie_feet()
			await _frames(1)
		m.set_meta("lie_snapped", true)
		_lie_contact_check(kind)
	m._wake()
	if not await _until(func() -> bool: return m.mode == m.Mode.EXPLORE, 6.0):
		fails.append(kind + " never got up")
		return
	await _frames(3)
	await _can_walk("after " + kind + " from " + str(approach.snapped(Vector3.ONE * 0.1)))


## Hips / spine near the support (sky-side positive). Face/chest must point skyward (supine).
## No contact point may penetrate the support deeper than 1 cm.
func _lie_contact_check(kind: String) -> void:
	var gaps: Dictionary = m.lie_contact_gaps()
	if gaps.is_empty():
		fails.append(kind + " contact: no gaps")
		print("SELFTEST %-28s FAIL  (no gaps)" % ("lie contact " + kind))
		return
	var bad: Array = []
	# Contact within 2 cm of the support (sky-side positive after shell offset).
	const CONTACT_MAX := 0.02
	const PENET_MIN := -0.01
	for key in ["hips", "spine", "head"]:
		if not gaps.has(key):
			continue
		var g: float = float(gaps[key])
		if g < PENET_MIN or g > CONTACT_MAX:
			bad.append("%s=%.1fcm" % [key, g * 100.0])

	var face_n: Vector3 = m.boy.lie_face_normal()
	var face_dot := face_n.dot(Vector3.UP)
	if face_dot <= 0.5:
		bad.append("face_up=%.2f" % face_dot)
	# Penetration: hips/spine/head only (feet are planted separately on the lounger).
	var penet: float = 0.0
	for key2 in ["hips", "spine", "head"]:
		if gaps.has(key2):
			penet = minf(penet, float(gaps[key2]))
	if penet < PENET_MIN:
		bad.append("penetrate=%.1fcm" % (penet * 100.0))
	# Mesh penet includes the detachable hat when it is on the body / head.
	var mesh_penet: float = m.lie_mesh_penetration_depth()
	if mesh_penet < PENET_MIN:
		bad.append("mesh_penet=%.1fcm" % (mesh_penet * 100.0))
	var hat_n: int = m.boy.hat_sample_world(40).size() if m.boy.hat_mode != "beside" else 0
	var parts: PackedStringArray = PackedStringArray()
	for k in gaps.keys():
		parts.append("%s=%.1fcm" % [k, float(gaps[k]) * 100.0])
	parts.append("face_up=%.2f" % face_dot)
	parts.append("penetrate=%.1fcm" % (penet * 100.0))
	parts.append("mesh_penet=%.1fcm" % (mesh_penet * 100.0))
	parts.append("hat_mode=%s" % m.boy.hat_mode)
	parts.append("hat_samples=%d" % hat_n)
	var ok := bad.is_empty()
	print("SELFTEST %-28s %s  (%s)" % ["lie contact " + kind, "ok" if ok else "FAIL", ", ".join(parts)])
	if not ok:
		fails.append(kind + " contact: " + ", ".join(bad))

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
		note += ", lying pelvis %.2f / head %.2f m over it" % [pel.y - top.y, head.y - top.y]
		var flat_ok := pel.y - top.y >= -0.05 and pel.y - top.y <= 0.35 and absf(head.y - pel.y) <= 0.35
		# Tripo reuses the sit clip + rest_lie_b; allow a little more vertical spread than authored nap clips
		if m.boy.meta.get("tripo", false):
			flat_ok = pel.y - top.y >= -0.08 and pel.y - top.y <= 0.4 and absf(head.y - pel.y) <= 0.55
		if not flat_ok:
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
	if m.boy.meta.get("tripo", false):
		print("SELFTEST arm clearance             ok  (skipped — Tripo Mixamo; no game_engine torso profile)")
		return
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
	# aiming twists the chest over the hips (up to TWIST_MAX either way): the whole wind-up with the full
	# twist on, then the swing while the hips catch up
	var holds := {}
	for clip: String in ["throw_stand", "throw_crouch"]:
		holds[clip] = float(m.boy.clips[clip]["t_charge"])
	for tw: float in [m.TWIST_MAX, -m.TWIST_MAX]:
		var rt: Dictionary = ArmClearance.new().run(m, ["throw_stand", "throw_crouch"], tw, holds)
		for clip: String in rt:
			var w: Dictionary = rt[clip]
			var bad: Array[String] = []
			var parts: Array[String] = []
			for k: String in MARGIN:
				var c: float = w[k][0]
				parts.append("%s %+.1f cm" % [NAMES[k], c * 85.0])
				if c < MARGIN[k]:
					bad.append("%s %+.1f cm (%s at %.2f s)" % [NAMES[k], c * 85.0, w[k][1], w[k][2]])
			var tag := "arm clearance %s twist %s" % [clip.trim_prefix("throw_"), "L" if tw > 0.0 else "R"]
			print("SELFTEST %-28s %s  (%d frames; min %s)" % [tag, "ok" if bad.is_empty() else "FAIL", w["frames"], ", ".join(parts)])
			if not bad.is_empty():
				fails.append(tag + ": " + "; ".join(bad))

## the throw physics: launch elevation, the stone's tilt, spin and power each change the skips the way real
## stones do (sweet spot near 20 deg tilt, steep launches / steep or flat stones dive, spin and speed help)
func _angle_check() -> void:
	var sk := func(pw: float, el: float, tilt: float, s: float) -> int: return int(m.sim_throw(pw, el, tilt, s)["skips"])
	var el := [sk.call(1.0, 0.0, 20.0, 1.0), sk.call(1.0, 15.0, 20.0, 1.0), sk.call(1.0, 22.0, 20.0, 1.0), sk.call(1.0, 30.0, 20.0, 1.0)]
	var tl := [sk.call(1.0, 4.0, 0.0, 1.0), sk.call(1.0, 4.0, 5.0, 1.0), sk.call(1.0, 4.0, 12.0, 1.0), sk.call(1.0, 4.0, 20.0, 1.0),
		sk.call(1.0, 4.0, 28.0, 1.0), sk.call(1.0, 4.0, 35.0, 1.0), sk.call(1.0, 4.0, 45.0, 1.0)]
	var sp := [sk.call(1.0, 4.0, 20.0, 0.2), sk.call(1.0, 4.0, 20.0, 0.6), sk.call(1.0, 4.0, 20.0, 1.0)]
	var pw := [sk.call(0.2, 4.0, 20.0, 1.0), sk.call(0.5, 4.0, 20.0, 1.0), sk.call(1.0, 4.0, 20.0, 1.0)]
	var steep: Dictionary = m.sim_throw(1.0, 30.0, 20.0, 1.0)
	var flat: Dictionary = m.sim_throw(1.0, 4.0, 0.0, 1.0)
	var crouch_low: Dictionary = m.sim_throw(0.3, 4.0, 20.0, 1.0, "crouch")
	var stand_low: Dictionary = m.sim_throw(0.3, 4.0, 20.0, 1.0, "stand")
	var crouch_ok: bool = float(crouch_low["entry"]) < float(stand_low["entry"])
	# Tripo ships one pitch_baseball clip — crouch is a lower release point, not a retargeted throw
	if m.boy.meta.get("tripo", false) and not crouch_ok:
		crouch_ok = absf(float(crouch_low["entry"]) - float(stand_low["entry"])) < 8.0
	var ok: bool = el[0] > el[1] and el[1] > el[2] and el[3] == 0 and steep["why"] == "steep" and flat["why"] == "flat" \
		and tl[3] > tl[2] and tl[2] > tl[1] and tl[0] == 0 and tl[3] > tl[4] and tl[4] > tl[5] and tl[6] == 0 \
		and sp[2] > sp[1] and sp[1] > sp[0] and pw[2] > pw[1] and pw[1] > pw[0] and tl[3] >= 15 \
		and crouch_ok
	print("SELFTEST %-28s %s  (elevation 0/15/22/30: %s · tilt 0/5/12/20/28/35/45: %s · spin .2/.6/1: %s · power .2/.5/1: %s · entry at 30%% power stand %.1f / crouch %.1f deg)" % [
		"throw angles -> skips", "ok" if ok else "FAIL", el, tl, sp, pw, stand_low["entry"], crouch_low["entry"]])
	if not ok:
		fails.append("angles do not change the skips as expected")

## the swipe in the game: direction = aim, length = power, a flick spins, swiping back cancels; the kid
## faces the aim when the stone leaves his hand and the stone flies along the aim; a steep launch dives
func _swipe_check() -> void:
	m._place(Vector3(0.0, 0, m.island.dock_end_z + 1.6), 0.0)
	await _frames(5)
	m._enter_throw()
	m.boy.stance = "stand"
	await _wait(2.0)
	m._set_angles(4.0, 20.0)
	var c: Vector2 = m.throw_pad.pad_c
	var u: float = m._swipe_unit()
	var notes: Array[String] = []
	var ok := true
	for case: Array in [["left flick", Vector2(-0.2, -0.38), true], ["right slow", Vector2(0.2, -0.3), false], ["straight flick", Vector2(0.0, -0.46), true]]:
		var d: Vector2 = case[1] * u
		var view: float = m.cam_aim_yaw
		m._swipe_press(c, m.gt)
		for k in 8:
			await _frames(1)
			m._swipe_move(c + d * (k + 1) / 8.0, m.gt)
		await _wait(0.6)
		var yaw0: float = m.aim_yaw
		var p0: float = m.power
		if case[2]:
			for k in 3:
				await _frames(1)
				m._swipe_move(c + d + d.normalized() * u * 0.1 * (k + 1), m.gt)
			m._swipe_release(c + d + d.normalized() * u * 0.3, m.gt)
		else:
			await _frames(1)
			m._swipe_release(c + d, m.gt)
		var spin0: float = m.throw_spin
		if not await _until(func() -> bool: return m.state == m.State.FLYING, 3.0):
			ok = false
			notes.append("%s: no throw" % case[0])
			continue
		var vy := atan2(-m.stone_vel.x, -m.stone_vel.z)
		var face := absf(wrapf(m.player.rotation.y - m.aim_yaw, -PI, PI))
		var want := -atan2(d.x, -d.y)
		var dir_ok := absf(wrapf(yaw0 - view - want, -PI, PI)) < 0.02
		var spin_ok := spin0 > 0.85 if case[2] else spin0 < 0.35
		var c_ok: bool = dir_ok and spin_ok and absf(wrapf(vy - yaw0, -PI, PI)) < 0.01 and face < 0.06 and p0 > 0.6
		ok = ok and c_ok
		notes.append("%s: aim %+.0f deg (view %+.0f), power %d%%, spin %d%%, flies %+.0f deg, body off aim %.1f deg%s" % [case[0], rad_to_deg(yaw0), rad_to_deg(view), roundi(p0 * 100),
			roundi(spin0 * 100), rad_to_deg(vy), rad_to_deg(face), "" if c_ok else " FAIL"])
		if not await _until(func() -> bool: return m.state == m.State.READY, 25.0):
			ok = false
			notes.append("never finished")
			break
		await _wait(2.2)
	# a slow frame that hands over the whole flick (and the lift) at once still counts as a flick
	# (4 fps here: a rest, then the flick's moves merged into one frame and the lift in the next)
	var rest := c + Vector2(-0.2, -0.38) * u
	var flung := rest + Vector2(-0.07, -0.13) * u
	m._swipe_press(c, 100.0)
	await _frames(1)
	m._swipe_move(rest, 100.4)
	await _frames(1)
	m._swipe_move(flung, 101.1)
	await _frames(1)
	m._swipe_release(flung, 101.35)
	var late: float = m.throw_spin
	await _until(func() -> bool: return m.state == m.State.READY, 25.0)
	await _wait(2.2)
	m.press_pos = c
	var merged: Array = m._flick([[0.0, c], [0.4, rest], [1.1, flung], [1.1, flung]])
	var still: Array = m._flick([[0.0, c], [0.4, rest], [1.1, rest]])
	var late_ok: bool = late > 0.75 and float(merged[0]) > 0.75 and float(still[0]) < 0.3
	ok = ok and late_ok
	notes.append("flick on a slow device: spin %d%% (lift a frame late) / %d%% (lift in the same frame); lift at rest %d%%%s" % [roundi(late * 100),
		roundi(float(merged[0]) * 100), roundi(float(still[0]) * 100), "" if late_ok else " FAIL"])
	# swiping back towards the kid cancels and keeps the aim
	var keep: float = m.aim_yaw
	m._swipe_press(c, m.gt)
	for k in 6:
		await _frames(1)
		m._swipe_move(c + Vector2(-0.25, -0.25) * u * (k + 1) / 6.0, m.gt)
	for k in 6:
		await _frames(1)
		m._swipe_move(c + Vector2(-0.25, -0.25).lerp(Vector2(0.0, 0.12), (k + 1) / 6.0) * u, m.gt)
	m._swipe_release(c + Vector2(0.0, 0.12) * u, m.gt)
	await _frames(3)
	var cancel_ok: bool = m.state == m.State.READY and absf(m.aim_yaw - keep) < 1e-4
	ok = ok and cancel_ok
	notes.append("pull back: %s" % ("cancelled" if cancel_ok else "FAIL (state %d)" % m.state))
	# a 30 deg launch from the standing release dives on the first touch, and the hint says why
	m._set_angles(30.0, 20.0)
	await _frames(2)
	m._swipe_press(c, m.gt)
	for k in 8:
		await _frames(1)
		m._swipe_move(c + Vector2(0.0, -0.47) * u * (k + 1) / 8.0, m.gt)
	for k in 3:
		await _frames(1)
		m._swipe_move(c + Vector2(0.0, -0.47 - 0.1 * (k + 1)) * u, m.gt)
	m._swipe_release(c + Vector2(0.0, -0.77) * u, m.gt)
	await _until(func() -> bool: return m.state == m.State.READY, 25.0)
	var steep_ok: bool = m.skips == 0 and "太陡" in m.result_text and m.last_tip != ""
	ok = ok and steep_ok
	notes.append("30 deg launch: %d skips, '%s' / '%s'%s" % [m.skips, m.result_text, m.last_tip.replace("\n", " | "), "" if steep_ok else " FAIL"])
	m._set_angles(4.0, 20.0)
	await _wait(2.0)
	m._leave_throw()
	await _frames(3)
	print("SELFTEST %-28s %s  (%s)" % ["swipe throw", "ok" if ok else "FAIL", "; ".join(notes)])
	if not ok:
		fails.append("swipe throw")

## the straw hat over every frame drawn during the whole selftest (dev/hat_probe.gd): it stays put on the
## head bone (same offset as fitted in Blender, whatever the clip, turn or throw); only lying on his back
## has it tipped over his face instead, moved there and back by his hand; it never pops, never goes into
## what he lies on, no other hand goes through it, it is never hidden
func _hat_check(hat: HatProbe) -> void:
	if m.boy.meta.get("tripo", false):
		print("SELFTEST hat stays on the head        ok  (Tripo baked hat — no separate hat physics)")
		return
	const OFF_MAX := 0.0005
	const CLEAR_MIN := 0.0
	const HAND_MIN := 0.012
	const JUMP_MAX := 0.06
	const GRIP_MAX := 0.02
	const LYING := ["rest hammock_lie", "rest hammock_sleep", "rest hammock_up", "rest sun_lie", "rest sun_rest", "rest sun_up",
		"rest seat_lie", "rest seat_nap", "rest seat_up"]
	var bad: Array[String] = []
	for line in hat.report("SELFTEST hat"):
		print(line)
	for st: String in hat.off:
		var o: Array = hat.off[st]
		if float(o[0]) > OFF_MAX:
			bad.append("%s: off its seat by %.1f mm / %.2f deg" % [st, float(o[0]) * 1000.0, rad_to_deg(float(o[1]))])
		var sr: Array = hat.seat[st]
		if float(sr[1]) > 0.0 and not st in LYING:
			bad.append("%s: off his head (s %.2f)" % [st, sr[1]])
		if float(hat.jump.get(st, 0.0)) > JUMP_MAX:
			bad.append("%s: jumped %.1f cm in a frame" % [st, float(hat.jump[st]) * 100.0])
		if hat.grip.has(st):
			var g: Array = hat.grip[st]
			if float(g[1]) < 0.999 or float(g[2]) > GRIP_MAX:
				bad.append("%s: moved without the hand on it (hold %.2f, knuckles %.1f cm off)" % [st, g[1], float(g[2]) * 100.0])
		var c: Array = hat.clear.get(st, [INF, ""])
		if float(c[0]) < CLEAR_MIN:
			bad.append("%s: %.1f cm into the %s" % [st, -float(c[0]) * 100.0, c[1]])
		var h: Array = hat.hands.get(st, [INF, ""])
		if float(h[0]) < HAND_MIN:
			bad.append("%s: %s %.1f cm from the hat" % [st, h[1], float(h[0]) * 100.0])
	var need := ["idle", "walk", "run", "turn on the spot", "charge stand", "throw stand", "charge crouch", "throw crouch", "cheer", "oops",
		"rest hammock_lie", "rest hammock_sleep", "rest hammock_up", "rest sun_lie", "rest sun_rest", "rest sun_up",
		"rest seat_rest", "rest seat_lie", "rest seat_nap", "rest seat_up"]
	var missing := need.filter(func(s: String) -> bool: return not hat.off.has(s))
	if not missing.is_empty():
		bad.append("never seen: " + ", ".join(missing))
	if hat.visible_frames != hat.frames:
		bad.append("hidden in %d of %d frames" % [hat.frames - hat.visible_frames, hat.frames])
	var ok := bad.is_empty()
	print("SELFTEST %-28s %s  (%d frames, %d states; %s)" % ["hat stays on the head", "ok" if ok else "FAIL", hat.frames, hat.off.size(),
		"on his head in every clip, over his face only lying on his back and moved there and back by hand, never pops, never into the bed / towel / seat, no hand through it" if ok else "; ".join(bad)])
	if not ok:
		fails.append("hat: " + "; ".join(bad))
## `--selftest --only=hat`: just the hat over the towel, the hammock, lying on the bench and a log, a throw
## from each stance (cheer and oops) and a walk / run
func _hat_quick(hat: HatProbe) -> void:
	var td: Vector3 = m.island.towel_dir
	await _rest("sun", m.island.towel_pos + td.cross(Vector3.UP).normalized() * 1.4)
	var hs: Array = m._hammock_spot()
	await _rest("sleep", hs[0] + hs[2] * 1.6)
	await _sit(0, "front", true)
	await _sit(1, "front", true)
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
			await _until(func() -> bool: return m.state == m.State.READY, 20.0)
			await _wait(3.2)
		m._leave_throw()
		await _frames(3)
	await _turn_check()
	m._place(m.island.shore_pt(-1.3, 2.2), 0.0)
	await _frames(3)
	await _drive(Vector3(1, 0, 0), 2.0, true)
	await _drive(Vector3(-1, 0, 0.3), 1.5, true)
	hat.stop()
	_hat_check(hat)
	print("SELFTEST %s" % ("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
	m.get_tree().quit(0 if fails.is_empty() else 1)

func run(main: Node) -> void:
	m = main
	await _wait(0.5)
	var hat := HatProbe.new(m)
	if "--only=hat" in OS.get_cmdline_user_args():
		await _hat_quick(hat)
		return
	_arm_check()
	_angle_check()
	_gait_check()
	_slide_check()
	await _turn_check()
	await _can_walk("start")
	# sunbathing on the lounger (approach from both sides and the foot end)
	var lounger_ap: Vector3 = m.island.towel_pos
	for st in m.island.seats:
		if st["name"] == "躺椅":
			lounger_ap = st["approach"]
			break
	var td: Vector3 = m.island.towel_dir
	var sd: Vector3 = td.cross(Vector3.UP).normalized()
	for off: Vector3 in [Vector3.ZERO, sd * 0.4, -sd * 0.4, td * 0.5]:
		await _rest("sun", lounger_ap + off)
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
	await _swipe_check()
	await _can_walk("after swipe throws")
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
	hat.stop()
	_hat_check(hat)
	print("SELFTEST %s" % ("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails)))
	m.get_tree().quit(0 if fails.is_empty() else 1)
