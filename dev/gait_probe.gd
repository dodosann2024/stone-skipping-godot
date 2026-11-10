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
	[17.6, 19.0, "run -> stop"]]
# [until t, target speed, yaw rate, zig-zag amplitude]: a zig-zag swings the heading +-amp every 0.8 s the way
# main.gd turns the boy towards the stick (lerp_angle at rate 9: up to ~10 rad/s right after a flick)
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
		return false
	var acc := 6.0 if tg[0] > speed else 9.0
	var want_spd: float = tg[0]
	if want_spd < 0.05 and boy.settling():
		want_spd = 0.5     # as main.gd: finish the step before stopping
	speed = move_toward(speed, want_spd, acc * dt)
	if float(tg[2]) > 0.0:
		var want_yaw := zig_base + float(tg[2]) * (1.0 if int(t / 0.8) % 2 == 0 else -1.0)
		yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-dt * 9.0))
	else:
		yaw += float(tg[1]) * dt * minf(speed / 1.0, 1.0)
		zig_base = yaw
	boy.rotation.y = yaw
	boy.position += Basis(Vector3.UP, yaw) * Vector3(0, 0, -speed * dt)
	if speed > 0.05:
		boy.set_move(speed)
	else:
		boy.set_move(0.0)
		boy.set_idle()
	boy._tick(dt)
	_measure()
	# a quick step picks the foot up again: it gets a fresh print where it lands
	_pend = _pend.filter(func(pd: Array) -> bool: return float(boy.step_t[pd[0]]) < 0.0)
	for pd in _pend:
		if t - float(pd[2]) >= 0.06:
			print_err = maxf(print_err, (_print_spot(pd[0]) - (pd[1] as Vector2)).length())
	_pend = _pend.filter(func(pd: Array) -> bool: return t - float(pd[2]) < 0.06)
	frame += 1
	return true

## the spot main.gd stamps a footprint on (60 % of the way from heel to ball)
func _print_spot(side: int) -> Vector2:
	var fp := boy.foot_points(side)
	var h: Vector3 = fp[0]
	var b: Vector3 = fp[1]
	return Vector2(h.x, h.z) + Vector2(b.x - h.x, b.z - h.z) * 0.6

func _measure() -> void:
	worst = 0.0
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
		out.append("%-26s max %.1f mm/frame  mean %.2f mm/frame  (%d planted frames)" % [lb, float(seg_max.get(lb, 0.0)) * 1000.0,
			float(seg_sum.get(lb, 0.0)) / maxf(float(seg_n.get(lb, 0)), 1.0) * 1000.0, int(seg_n.get(lb, 0))])
	return out
