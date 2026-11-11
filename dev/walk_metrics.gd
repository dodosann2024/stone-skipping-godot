class_name WalkMetrics
extends RefCounted
## Gait kinematics of a Boy ticked by hand at a steady speed on flat ground (as GaitProbe drives him): joint
## angles at heel strike / in swing, pelvis and shoulder motion, arm swing, head stability, stride vs speed.
## `measure(parent, speed)` -> [lines, numbers]. Printed by `--sim` and `--walkmetrics` (env WALK_CURVE=1: the
## left knee every frame; WALK_NOLOCK=1: without the foot lock, the clip alone).

const DT := 1.0 / 60.0

var b: Boy
var sk: Skeleton3D
var bone := {}
var heel := {}         # side -> [bone, offset in its rest frame]
var toe := {}
var g0 := {}           # side -> [heel, toe] standing heights
var down := {}         # side -> [heel down, toe down]
var swing_peak := {}   # side -> max knee flexion since toe-off
var n := {}            # running sums / extremes
var strikes := {}      # side -> [[t, heel ground position], ...]
var t := 0.0
var since := {}       # side -> s since heel strike (-1 in swing)
var load_pk := {}     # side -> knee peak over the loading response
var pitch0 := {}     # side -> rest pitch of the heel -> ball line

static func measure(parent: Node, spd: float, secs := 4.0) -> Array:
	var m := WalkMetrics.new()
	var bb := Boy.new()
	parent.add_child(bb)
	var out := m._run(bb, spd, secs)
	parent.remove_child(bb)
	bb.free()
	return out

func _run(bb: Boy, spd: float, secs: float) -> Array:
	b = bb
	b.frozen = true
	b.lock_enabled = not OS.has_environment("WALK_NOLOCK")
	b.position = Vector3(0, 60, 0)
	sk = b.skel
	for nm in ["pelvis", "spine_03", "head", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r",
			"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]:
		bone[nm] = sk.find_bone(nm)
	var g := float(b.meta["ground"])
	for s in ["l", "r"]:
		var fr := sk.get_bone_global_rest(bone["foot_" + s])
		var br := sk.get_bone_global_rest(bone["ball_" + s])
		heel[s] = [bone["foot_" + s], fr.affine_inverse() * Vector3(fr.origin.x, g, fr.origin.z - 0.035)]
		toe[s] = [bone["ball_" + s], br.affine_inverse() * Vector3(br.origin.x, g, br.origin.z + 0.02)]
		strikes[s] = []
		var fw0 := br.origin - fr.origin
		pitch0[s] = rad_to_deg(atan2(fw0.y, Vector2(fw0.x, fw0.z).length()))
		swing_peak[s] = -1.0
	# idle, then ease up to speed and settle into the cycle before measuring
	var v := 0.0
	var warm := 2.0
	while t < warm + secs:
		t += DT
		v = move_toward(v, spd if t > 0.5 else 0.0, 3.0 * DT)
		b.position += Vector3(0, 0, -v * DT)
		if v > 0.05:
			b.set_move(v)
		else:
			b.set_move(0.0)
			b.set_idle()
		b._tick(DT)
		_sample(t > warm)
	return _report(spd)

func _p(nm: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(bone[nm]).origin

func _pt(c: Array) -> Vector3:
	return sk.global_transform * (sk.get_bone_global_pose(c[0]) * (c[1] as Vector3))

static func _ang(a: Vector3, o: Vector3, c: Vector3) -> float:
	return 180.0 - rad_to_deg((a - o).angle_to(c - o))

func _acc(k: String, x: float) -> void:
	var r: Array = n.get(k, [INF, -INF, 0.0, 0])
	n[k] = [minf(r[0], x), maxf(r[1], x), float(r[2]) + x, int(r[3]) + 1]

func _sample(on: bool) -> void:
	# boy space: forward -Z, up +Y, his left +X
	var inv := b.global_transform.affine_inverse()
	var knee := {}
	for s in ["l", "r"]:
		knee[s] = _ang(_p("thigh_" + s), _p("calf_" + s), _p("foot_" + s))
		var hp := _pt(heel[s])
		var tp := _pt(toe[s])
		if not g0.has(s):
			g0[s] = [hp.y, tp.y]
			down[s] = [true, true]
			continue
		var hd: bool = hp.y < float(g0[s][0]) + 0.004
		var td: bool = tp.y < float(g0[s][1]) + 0.004
		var fw := (_p("ball_" + s) - _p("foot_" + s))
		var pitch := rad_to_deg(atan2(fw.y, Vector2(fw.x, fw.z).length())) - float(pitch0[s])
		if on:
			# heel strike: the heel lands while the toes are still up in the air
			if hd and not down[s][0] and not td:
				_acc("knee at heel strike", knee[s])
				_acc("foot pitch at heel strike (toes up +)", pitch)
				strikes[s].append([t, hp])
				since[s] = 0.0
				load_pk[s] = knee[s]
			if float(since.get(s, -1.0)) >= 0.0:
				since[s] = float(since[s]) + DT
				load_pk[s] = maxf(load_pk[s], knee[s])
				if float(since[s]) > 0.15:
					_acc("knee loading response (peak 0-0.15 s)", load_pk[s])
					since[s] = -1.0
			# toe-off: the toe pad leaves the ground (the heel is already up)
			if not td and down[s][1]:
				_acc("knee at toe-off", knee[s])
				_acc("foot pitch at toe-off", pitch)
				swing_peak[s] = 0.0
			if not hd and not td and float(swing_peak[s]) >= 0.0:
				swing_peak[s] = maxf(swing_peak[s], knee[s])
			if hd and not down[s][0] and float(swing_peak[s]) > 0.0:
				_acc("knee peak in swing", swing_peak[s])
				swing_peak[s] = -1.0
			if hd or td:
				_acc("knee in stance", knee[s])
		down[s] = [hd, td]
		if on and s == "l" and OS.has_environment("WALK_CURVE") and t < 3.0:
			print("CURVE t %.3f knee %.1f heel %d toe %d pel %.3f" % [t, knee[s], int(hd), int(td), (b.global_transform.affine_inverse() * _p("pelvis")).y])
	if not on:
		return
	# left to right across the hips / shoulders (his right is +X in boy space)
	var hips := inv * _p("thigh_r") - inv * _p("thigh_l")
	var shs := inv * _p("upperarm_r") - inv * _p("upperarm_l")
	var py := rad_to_deg(atan2(-hips.z, hips.x))
	var sy := rad_to_deg(atan2(-shs.z, shs.x))
	_acc("pelvis rotation (yaw)", py)
	_acc("pelvis tilt (drop, roll)", rad_to_deg(atan2(hips.y, Vector2(hips.x, hips.z).length())))
	_acc("pelvis height", (inv * _p("pelvis")).y * 100.0)
	_acc("shoulder line yaw", sy)
	_acc("shoulders vs pelvis yaw", sy - py)
	_acc("trunk lean (fwd +)", rad_to_deg(atan2(-(inv * _p("spine_03") - inv * _p("pelvis")).z, (inv * _p("spine_03") - inv * _p("pelvis")).y)))
	for s in ["l", "r"]:
		var ua := inv * _p("lowerarm_" + s) - inv * _p("upperarm_" + s)
		_acc("arm swing " + s + " (fwd +)", rad_to_deg(atan2(-ua.z, -ua.y)))
		_acc("elbow flexion", _ang(_p("upperarm_" + s), _p("lowerarm_" + s), _p("hand_" + s)))
	var hb := inv.basis * sk.global_transform.basis * sk.get_bone_global_pose(bone["head"]).basis
	var hf := hb * Vector3(0, 0, 1)
	_acc("head pitch (world)", rad_to_deg(atan2(hf.y, Vector2(hf.x, hf.z).length())))
	_acc("head yaw (world)", rad_to_deg(atan2(hf.x, -hf.z)))
	_acc("head height", (inv * _p("head")).y * 100.0)

func _report(spd: float) -> Array:
	var out: Array[String] = []
	var num := {}
	var mean := func(k: String) -> float:
		var r: Array = n.get(k, [0.0, 0.0, 0.0, 1])
		return float(r[2]) / maxf(float(r[3]), 1.0)
	var rng := func(k: String) -> float:
		var r: Array = n.get(k, [0.0, 0.0, 0.0, 1])
		return float(r[1]) - float(r[0])
	for k: String in ["knee at heel strike", "knee loading response (peak 0-0.15 s)", "knee in stance", "knee at toe-off", "knee peak in swing", "foot pitch at heel strike (toes up +)",
			"foot pitch at toe-off", "elbow flexion"]:
		var r: Array = n.get(k, [0.0, 0.0, 0.0, 0])
		out.append("%-38s mean %5.1f  min %5.1f  max %5.1f deg  (%d)" % [k, mean.call(k), r[0], r[1], r[3]])
		num[k] = [mean.call(k), r[0], r[1]]
	for k: String in ["pelvis rotation (yaw)", "pelvis tilt (drop, roll)", "shoulder line yaw", "shoulders vs pelvis yaw", "arm swing l (fwd +)",
			"arm swing r (fwd +)", "trunk lean (fwd +)", "head pitch (world)", "head yaw (world)"]:
		var r: Array = n.get(k, [0.0, 0.0, 0.0, 0])
		out.append("%-38s range %5.1f deg  (%5.1f .. %5.1f)" % [k, rng.call(k), r[0], r[1]])
		num[k] = [rng.call(k), r[0], r[1]]
	for k: String in ["pelvis height", "head height"]:
		out.append("%-38s bob %4.1f cm" % [k, rng.call(k)])
		num[k] = [rng.call(k)]
	# stride: same foot, strike to strike; its length over its time against the speed (no sliding)
	var sl := 0.0
	var st := 0.0
	var c := 0
	for s in ["l", "r"]:
		var a: Array = strikes[s]
		for i in range(1, a.size()):
			sl += Vector2(a[i][1].x - a[i - 1][1].x, a[i][1].z - a[i - 1][1].z).length()
			st += float(a[i][0]) - float(a[i - 1][0])
			c += 1
	if c > 0:
		out.append("%-38s %.2f m in %.2f s = %.2f m/s at %.2f m/s, cadence %d steps/min" % ["stride (same foot)", sl / c, st / c, sl / st, spd,
			roundi(120.0 * c / st)])
		num["stride"] = [sl / c, st / c, sl / st]
	return [out, num]
