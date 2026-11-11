class_name GaitProbe
extends RefCounted
## Drives a Boy (ticked by hand, fixed dt) through idle -> walk -> run -> turns -> zig-zags -> stop and
## measures how far each planted heel / toe pad slides per frame. Used by dev/gait_view.gd and the selftest.

# ground contacts: heel (under the back of the foot bone) and the ball / toe pad (under the toe bone)
const POINTS := ["heel_l", "toe_l", "heel_r", "toe_r"]
# [from, to, label]
const SEGS := [[1.0, 1.5, "idle -> walk"], [1.5, 4.0, "walk straight"], [5.5, 6.3, "walk -> run"], [6.3, 8.0, "run straight"],
	[8.0, 10.5, "run turning 1.3 rad/s"], [10.5, 11.0, "run -> walk"], [11.0, 12.0, "walk turning -1.6 rad/s"],
	[12.0, 14.5, "stop -> idle"], [14.5, 16.0, "walk zig-zag (game turn)"], [16.0, 17.6, "run zig-zag (game turn)"],
	[17.6, 19.0, "run -> stop"], [19.4, 21.2, "turn on the spot 180 left"], [21.2, 22.6, "turn on the spot 90 right"],
	[22.6, 24.2, "walk off"], [24.2, 26.2, "walk, flick back 180"], [26.2, 27.4, "stop"]]
# after PROFILE: the stick is pushed to a heading (main.gd's explore steering, turning on the spot as it does)
const TURNS := [[19.4, PI, 0.0], [21.2, -PI * 0.5, 0.0], [22.6, 0.0, 1.15], [24.2, PI, 1.15], [26.2, 0.0, 0.0], [27.4, 0.0, -1.0]]
# [until t, target speed, yaw rate, zig-zag amplitude]: a zig-zag swings the heading +-amp every 0.8 s the way
# main.gd turns the boy towards the stick (Boy.move_turn: as fast as his feet can corner, slowing into it)
const PROFILE := [
	[1.0, 0.0, 0.0, 0.0],
	[4.0, 1.15, 0.0, 0.0],
	[5.5, 0.5, 0.0, 0.0],
	[8.0, 2.7, 0.0, 0.0],
	[10.5, 2.7, 1.3, 0.0],
	[12.0, 1.15, -1.6, 0.0],
	[13.5, 0.0, 0.0, 0.0],
	[14.5, 0.0, 0.0, 0.0],
	[16.0, 1.15, 0.0, 1.1],
	[17.6, 2.7, 0.0, 1.1],
	[19.0, 0.0, 0.0, 0.0],
]

var boy: Boy
var origin := Vector3.ZERO
var t := 0.0
var frame := 0
var speed := 0.0
var yaw := 0.0
var zig_base := 0.0
var contact := {}     # point -> [bone index, offset in the bone's rest frame]
var rest_h: Array = []
var prev_pt: Array = []
var prev_down: Array = []
var slide_max := 0.0
var slide_sum := 0.0
var slide_n := 0
var seg_max := {}
var seg_sum := {}
var seg_n := {}
var worst := 0.0      # this frame's worst planted slide
var log_slides := false
var steps := 0          # footstep sounds
var prints := 0         # foot_flat events (footprints)
var print_err := 0.0    # worst drift of a footprint spot over the next 0.06 s of stance
var _pend: Array = []
var want := 0.0
var spot_rate := 0.0
var pivot := false
var turn_i := 0
var wish_spd := 0.0
var seg_quick := {}     # segment -> quick steps started in it
var seg_spot := {}      # segment -> steps on the spot started in it
var seg_print := {}     # segment -> worst footprint spot drift
var seg_spot_t := {}    # segment -> [first, last] time a step on the spot started in it
var seg_root := {}      # segment -> how far the boy's root moved beyond what the probe moved it (turning on the spot)
var _q0 := 0
var _s0 := 0
var _own := Vector3.ZERO
var _seg_from := {}

func _init(b: Boy, at := Vector3.ZERO) -> void:
	boy = b
	origin = at
	boy.frozen = true
	boy.footstep.connect(func(_s: int, _r: bool) -> void: steps += 1)
	boy.foot_flat.connect(func(side: int) -> void:
		prints += 1
		_pend.append([side, _print_spot(side), t]))
	boy.position = origin
	var sk := boy.skel
	var g := float(boy.meta["ground"])
	for s in ["l", "r"]:
		var fb := sk.find_bone("foot_" + s)
		var bb := sk.find_bone("ball_" + s)
		var fr := sk.get_bone_global_rest(fb)
		var br := sk.get_bone_global_rest(bb)
		contact["heel_" + s] = [fb, fr.affine_inverse() * Vector3(fr.origin.x, g, fr.origin.z - 0.035)]
		contact["toe_" + s] = [bb, br.affine_inverse() * Vector3(br.origin.x, g, br.origin.z + 0.02)]

func _target(tt: float) -> Array:
	for s in PROFILE:
		if tt < float(s[0]):
			return [float(s[1]), float(s[2]), float(s[3])]
	return [-1.0, 0.0, 0.0]

## one frame: move the boy, tick him, measure. false once the profile is over
func step(dt: float) -> bool:
	t += dt
	var tg := _target(t)
	if tg[0] < 0.0:
		if not _turn_step(dt):
			return false
		boy._tick(dt)
		_measure()
		_track_prints()
		frame += 1
		return true
	if float(tg[2]) > 0.0:
		_steer(dt, zig_base + float(tg[2]) * (1.0 if int(t / 0.8) % 2 == 0 else -1.0), float(tg[0]), true)
		boy._tick(dt)
		_measure()
		_track_prints()
		frame += 1
		return true
	var want_spd: float = tg[0]
	if want_spd < 0.05 and boy.settling():
		want_spd = 0.5     # as main.gd: finish the step before stopping
	var acc := 6.0 if want_spd > speed else 9.0
	speed = move_toward(speed, want_spd, acc * dt)
	yaw += float(tg[1]) * dt * minf(speed / 1.0, 1.0)
	zig_base = yaw
	pivot = false
	spot_rate = 0.0
	boy.pivoting = false
	boy.turn_ahead = 0.0
	boy.rotation.y = yaw
	boy.position += Basis(Vector3.UP, yaw) * Vector3(0, 0, -speed * dt)
	_own += Basis(Vector3.UP, yaw) * Vector3(0, 0, -speed * dt)
	if speed > 0.05:
		boy.set_move(speed)
	else:
		boy.set_move(0.0)
		boy.set_idle()
	boy._tick(dt)
	_measure()
	_track_prints()
	frame += 1
	return true

func _track_prints() -> void:
	# a quick step picks the foot up again: it gets a fresh print where it lands
	_pend = _pend.filter(func(pd: Array) -> bool: return float(boy.step_t[pd[0]]) < 0.0)
	for pd in _pend:
		if t - float(pd[2]) >= 0.06:
			var e := (_print_spot(pd[0]) - (pd[1] as Vector2)).length()
			print_err = maxf(print_err, e)
			var lb := _seg_at(float(pd[2]))
			seg_print[lb] = maxf(float(seg_print.get(lb, 0.0)), e)
	_pend = _pend.filter(func(pd: Array) -> bool: return t - float(pd[2]) < 0.06)

## main.gd's explore steering after the stick moves to `want`: a big change of heading at walking pace or
## slower stops and turns on the spot (Boy.spot_turn), otherwise the heading eases round while moving
func _turn_step(dt: float) -> bool:
	if turn_i == 0:
		want = yaw
	while turn_i < TURNS.size() and t >= float(TURNS[turn_i][0]):
		if float(TURNS[turn_i][2]) < 0.0:
			return false
		want += float(TURNS[turn_i][1])
		wish_spd = float(TURNS[turn_i][2])
		turn_i += 1
	_steer(dt, want, wish_spd, turn_i > 0)
	return true

## main.gd's explore steering with the stick pushed towards heading `to` (wish_spd 0: let go)
func _steer(dt: float, to: float, wish_spd: float, on: bool) -> void:
	var need := wrapf(to - yaw, -PI, PI)
	var active := on and (wish_spd > 0.0 or absf(need) > 0.01)
	if active and Boy.wants_spot_turn(need, speed):
		pivot = true
	if pivot and absf(need) < 0.03 and not boy.spin_busy():
		pivot = false
	if pivot:
		speed = move_toward(speed, 0.0, 10.0 * dt)
		var r := Boy.spot_turn(yaw, to, spot_rate, dt)
		yaw = r[0]
		spot_rate = r[1]
	else:
		spot_rate = 0.0
		var ws := wish_spd
		if ws < 0.05 and boy.settling():
			ws = 0.5
		if ws > 0.05:
			var mt := Boy.move_turn(yaw, to, speed, dt)
			yaw = mt[0]
			ws *= float(mt[1])
		var acc := 6.0 if ws > speed else 10.0
		speed = move_toward(speed, ws, acc * dt)
	boy.pivoting = pivot
	boy.turn_ahead = wrapf(to - yaw, -PI, PI) if (pivot or speed > 0.05) else 0.0
	boy.rotation.y = yaw
	boy.position += Basis(Vector3.UP, yaw) * Vector3(0, 0, -speed * dt)
	_own += Basis(Vector3.UP, yaw) * Vector3(0, 0, -speed * dt)
	if speed > 0.05:
		boy.set_move(speed)
	else:
		boy.set_move(0.0)
		boy.set_idle()

## the spot main.gd stamps a footprint on (60 % of the way from heel to ball)
func _print_spot(side: int) -> Vector2:
	var fp := boy.foot_points(side)
	var h: Vector3 = fp[0]
	var b: Vector3 = fp[1]
	return Vector2(h.x, h.z) + Vector2(b.x - h.x, b.z - h.z) * 0.6

func _seg_at(tt: float) -> String:
	for sg in SEGS:
		if tt >= float(sg[0]) and tt < float(sg[1]):
			return sg[2]
	return "-"

func _measure() -> void:
	worst = 0.0
	var lb0 := _seg_at(t)
	if lb0 != "-":
		if not _seg_from.has(lb0):
			_seg_from[lb0] = [boy.position, _own]
		var sf: Array = _seg_from[lb0]
		var r := (boy.position - (sf[0] as Vector3)) - (_own - (sf[1] as Vector3))
		r.y = 0.0
		seg_root[lb0] = maxf(float(seg_root.get(lb0, 0.0)), r.length())
	if boy.steps_taken != _q0:
		seg_quick[lb0] = int(seg_quick.get(lb0, 0)) + boy.steps_taken - _q0
		_q0 = boy.steps_taken
	if boy.spot_steps != _s0:
		seg_spot[lb0] = int(seg_spot.get(lb0, 0)) + boy.spot_steps - _s0
		_s0 = boy.spot_steps
		var st: Array = seg_spot_t.get(lb0, [t, t])
		seg_spot_t[lb0] = [st[0], t]
	for i in POINTS.size():
		var c: Array = contact[POINTS[i]]
		var pt: Vector3 = boy.skel.global_transform * (boy.skel.get_bone_global_pose(c[0]) * (c[1] as Vector3))
		if rest_h.size() < POINTS.size():
			rest_h.append(pt.y); prev_pt.append(pt); prev_down.append(false)
			continue
		# a heel / toe pad counts as planted while it sits at its standing height
		var down: bool = pt.y < float(rest_h[i]) + 0.004
		if down and prev_down[i] and frame > 3:
			var d := Vector2(pt.x - prev_pt[i].x, pt.z - prev_pt[i].z).length()
			if log_slides and d > 0.004:
				print("  slide t=%.2f %s d=%.3f anim=%s spd=%.2f" % [t, POINTS[i], d, boy.anim, speed])
			slide_max = maxf(slide_max, d)
			worst = maxf(worst, d)
			for sg in SEGS:
				if t >= float(sg[0]) and t < float(sg[1]):
					var lb: String = sg[2]
					seg_max[lb] = maxf(float(seg_max.get(lb, 0.0)), d)
					seg_sum[lb] = float(seg_sum.get(lb, 0.0)) + d
					seg_n[lb] = int(seg_n.get(lb, 0)) + 1
			slide_sum += d
			slide_n += 1
		prev_pt[i] = pt
		prev_down[i] = down

func run_all(dt: float) -> void:
	while step(dt):
		pass

func report() -> Array[String]:
	var out: Array[String] = []
	for sg in SEGS:
		var lb: String = sg[2]
		out.append("%-26s max %.1f mm/frame  mean %.2f mm/frame  (%d planted frames)  quick %d  spot %d  print drift %.1f mm" % [lb, float(seg_max.get(lb, 0.0)) * 1000.0,
			float(seg_sum.get(lb, 0.0)) / maxf(float(seg_n.get(lb, 0)), 1.0) * 1000.0, int(seg_n.get(lb, 0)),
			int(seg_quick.get(lb, 0)), int(seg_spot.get(lb, 0)), float(seg_print.get(lb, 0.0)) * 1000.0])
	return out

## the stress run of `--sim`: the whole profile at 30 / 20 / 60 fps; per rate the totals, then per segment the
## quick steps (shuffles), steps on the spot (with the time from the first to the last one) and the worst drift
## of a footprint spot
static func stress(parent: Node) -> Array[String]:
	var out: Array[String] = []
	for fps: int in [30, 20, 60]:
		var b := Boy.new()
		parent.add_child(b)
		var p := GaitProbe.new(b, Vector3(0, 60, 0))
		p.run_all(1.0 / fps)
		out.append("gait @%d fps: %d quick steps, %d steps on the spot, planted slide max %.1f mm/frame, footprint drift max %.1f mm" % [
			fps, b.steps_taken, b.spot_steps, p.slide_max * 1000.0, p.print_err * 1000.0])
		for sg in SEGS:
			var lb: String = sg[2]
			var span := ""
			if p.seg_spot_t.has(lb):
				var st: Array = p.seg_spot_t[lb]
				span = "  (steps %.2f-%.2f s into it, root moved %.1f cm)" % [float(st[0]) - float(sg[0]), float(st[1]) - float(sg[0]),
					float(p.seg_root.get(lb, 0.0)) * 100.0]
			out.append("gait @%d fps   %-26s quick %d  spot %d  print drift %4.1f mm%s" % [fps, lb, int(p.seg_quick.get(lb, 0)),
				int(p.seg_spot.get(lb, 0)), float(p.seg_print.get(lb, 0.0)) * 1000.0, span])
		parent.remove_child(b)
		b.free()
	return out
