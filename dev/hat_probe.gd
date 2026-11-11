extends RefCounted
## The straw hat stays on his head (v20). Sampled at the start of every frame, i.e. what was just drawn:
##   offset   the hat's pose relative to the head bone, per state (walk / run / turns / throws / cheer /
##            oops / every resting clip...): exactly one of its two seats (on his head as fitted in Blender,
##            over his face when lying on his back) or on the arc between them
##   seat     which: s 0 on his head .. 1 over his face (only the lying clips may leave 0)
##   jump     how far the hat moved on the head from one frame to the next (a pop would show here)
##   grip     while it is between its seats: the hand on the brim (IK fully in, knuckles at the grip)
##   clear    the lowest hat point above whatever he lies / sits on (hammock fabric, towel, sand, bench seat
##            and backrest, log): never below it
##   hands    the other hand / finger joints against the hat (may touch the brim, never pass through it)

var m: Node
var b: Boy
var verts := PackedVector3Array()
var off := {}     # state -> [worst offset m, worst angle rad, frames]
var seat := {}    # state -> [lowest s, highest s]
var jump := {}    # state -> largest frame-to-frame move of the hat on the head (m, game scale)
var grip := {}    # state -> [frames between seats, weakest hold, widest knuckle gap m]
var clear := {}   # state -> [lowest clearance m, what]
var hands := {}   # state -> [closest hand joint to the hat m, joint]
var _prev_c := Vector3.INF
var frames := 0
var visible_frames := 0
var on := true
var hand_bones: Array[int] = []
var hand_names: Array[String] = []

func _init(main: Node) -> void:
	m = main
	b = main.boy
	var arr: Array = (b.hat as MeshInstance3D).mesh.surface_get_arrays(0)
	var all: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var step := maxi(1, all.size() / 900)
	for i in range(0, all.size(), step):
		verts.append(all[i])
	for nm in ["hand_l", "hand_r", "middle_01_l", "middle_01_r", "middle_03_l", "middle_03_r", "thumb_03_l", "thumb_03_r"]:
		var bi := b.skel.find_bone(nm)
		if bi >= 0:
			hand_bones.append(bi)
			hand_names.append(nm)
	m.get_tree().process_frame.connect(_sample)

func stop() -> void:
	on = false
	if m.get_tree().process_frame.is_connected(_sample):
		m.get_tree().process_frame.disconnect(_sample)

func state() -> String:
	match b.anim:
		"activity":
			return "rest " + String(b.slot_clip[b.cur_slot])
		"move":
			if m.spot_turning:
				return "turn on the spot"
			if absf(b.turn_lean) > 0.05:
				return "sharp turn (" + ("run" if b.run_k > 0.5 else "walk") + ")"
			return "run" if b.run_k > 0.5 else "walk"
		"charge", "throw":
			return b.anim + " " + b._throw_clip().trim_prefix("throw_")
		"react":
			return b.react_kind
	if m.spot_turning:
		return "turn on the spot"
	return b.anim

func _sample() -> void:
	if not on or not is_instance_valid(b):
		return
	frames += 1
	if b.hat.is_visible_in_tree():
		visible_frames += 1
	var st := state()
	var e: Vector2 = b.hat_offset_error()
	var o: Array = off.get(st, [0.0, 0.0, 0])
	off[st] = [maxf(o[0], e.x), maxf(o[1], e.y), int(o[2]) + 1]
	var sr: Array = seat.get(st, [INF, -INF])
	seat[st] = [minf(sr[0], b.hat_s), maxf(sr[1], b.hat_s)]
	var hc: Vector3 = b.hat_on_head() * b.hat_band_c * b.skel.global_transform.basis.get_scale().x
	if _prev_c != Vector3.INF:
		jump[st] = maxf(float(jump.get(st, 0.0)), hc.distance_to(_prev_c))
	_prev_c = hc
	var holding: bool = b.hat_hold > 0.0
	if b.hat_s > 0.0 and b.hat_s < 1.0:
		var gr: Array = grip.get(st, [0, INF, 0.0])
		grip[st] = [int(gr[0]) + 1, minf(gr[1], b.hat_hold), maxf(gr[2], b.hat_grip_gap())]
	var xf: Transform3D = b.hat.global_transform
	var lo := INF
	var what := ""
	for v in verts:
		var p := xf * v
		var s := _support(p)
		if s[0] < lo:
			lo = s[0]
			what = "%s (%s%s)" % [s[1], _part(v), "" if b.hat_s <= 0.0 or b.hat_s >= 1.0 else ", hat %d%% of the way to his face" % roundi(b.hat_s * 100.0)]
	var c: Array = clear.get(st, [INF, ""])
	if lo < float(c[0]):
		clear[st] = [lo, what]	# hand joints: the closest hat vertex (the brim / crown are 4 mm shells)
	var sk: Skeleton3D = b.skel
	var near := INF
	var who := ""
	for j in hand_bones.size():
		if holding and hand_names[j].ends_with("_" + b.hat_side):
			continue
		var hp := sk.global_transform * sk.get_bone_global_pose(hand_bones[j]).origin
		var lp := xf.affine_inverse() * hp
		for v in verts:
			var d := lp.distance_squared_to(v)
			if d < near:
				near = d
				who = hand_names[j]
	var h: Array = hands.get(st, [INF, ""])
	if sqrt(near) < float(h[0]):
		hands[st] = [sqrt(near), who]

## which part of the hat a (hat local) vertex is on
func _part(v: Vector3) -> String:
	var d := v - b.hat_band_c
	if d.y > 0.03:
		return "crown"
	var a := rad_to_deg(atan2(-d.x, d.z))
	return "brim %s" % ("front" if absf(a) < 45.0 else "back" if absf(a) > 135.0 else "right" if a > 0.0 else "left")

## [clearance of world point p above what is under it, its name]
func _support(p: Vector3) -> Array:
	var best: Array = [p.y - Island.ground_h(p.x, p.z), "sand"]
	var isl = m.island
	# towel (5 stripes, 0.9 x 1.8 m, 3 cm on the sand)
	var tp: Vector3 = isl.towel_pos
	var td: Vector3 = isl.towel_dir
	var ts := td.cross(Vector3.UP).normalized()
	var r := Vector3(p.x - tp.x, 0, p.z - tp.z)
	if absf(r.dot(td)) < 0.9 and absf(r.dot(ts)) < 0.45:
		var top := Island.ground_h(p.x, p.z) + 0.045
		if p.y - top < float(best[0]):
			best = [p.y - top, "towel"]
	# hammock fabric (island.gd: 10 sagging segments, 3 stripes curved across)
	var hn: Node3D = isl.hammock_node
	if hn != null:
		var mid: Vector3 = (isl.hammock_a + isl.hammock_b) * 0.5
		var a: Vector3 = isl.hammock_a - mid
		var ab: Vector3 = isl.hammock_b - isl.hammock_a
		var q := hn.global_transform.affine_inverse() * p
		var t := (q - a).dot(ab) / ab.length_squared()
		if t > 0.0 and t < 1.0:
			var side := ab.cross(Vector3.UP).normalized() * 0.4
			var w := side * (sin(PI * clampf(t * 1.2 - 0.1, 0.0, 1.0)) + 0.05)
			var p0 := a + ab * t + Vector3(0, -0.6 * sin(PI * t), 0)
			var u := (q - p0).dot(w.normalized()) / w.length()
			if absf(u) <= 1.0:
				var y := p0.y + (w * u).y - 0.12 * (1.0 - u * u)
				if q.y - y < float(best[0]) and q.y - y > -0.25:
					best = [q.y - y, "hammock"]
	# seats: the bench (seat board + backrest) and the campfire logs
	for st: Dictionary in isl.seats:
		var top: Vector3 = st["top"]
		if Vector2(p.x - top.x, p.z - top.z).length() > 1.2:
			continue
		var face: Vector3 = st["face"]
		var nm: String = st["name"]
		if nm == "长椅":
			var bb := Basis(Vector3.UP, atan2(-face.x, -face.z))
			var bxf := Transform3D(bb, top - bb * Vector3(0, Island.SEAT_TOP, 0.03))
			var sy := Island.SEAT_TOP - 0.035
			var d1 := _box_sd(Transform3D(Basis.IDENTITY, Vector3(0, sy, 0)), Vector3(0.7, 0.035, 0.2), bxf.affine_inverse() * p)
			var d2 := _box_sd(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, sy + 0.3, 0.2)), Vector3(0.7, 0.15, 0.03), bxf.affine_inverse() * p)
			if d1 < float(best[0]):
				best = [d1, "bench seat"]
			if d2 < float(best[0]):
				best = [d2, "bench backrest"]
		elif nm == "坐木":
			var ax := face.cross(Vector3.UP).normalized()
			var c := top - Vector3(0, 0.17, 0)
			var rel := p - c
			var dr := (rel - ax * rel.dot(ax)).length() - 0.17
			var da := absf(rel.dot(ax)) - 0.7
			var d := minf(maxf(dr, da), 0.0) + Vector2(maxf(dr, 0.0), maxf(da, 0.0)).length()
			if d < float(best[0]):
				best = [d, "log"]
	return best

## signed distance from point q (in the parent frame of box xf) to a box of half extents h
static func _box_sd(xf: Transform3D, h: Vector3, q: Vector3) -> float:
	var l := xf.affine_inverse() * q
	var d := l.abs() - h
	return Vector3(maxf(d.x, 0.0), maxf(d.y, 0.0), maxf(d.z, 0.0)).length() + minf(maxf(d.x, maxf(d.y, d.z)), 0.0)

## `--sim`: a Boy ticked by hand (no frames drawn, so no deferred skeleton update to lean on) through the
## throws, cheer / oops and every resting clip, spun round 0.35 rad a tick (sharper than any turn in the
## game); the hat's offset from the head after every tick. [lines, worst offset m]
static func sim(parent: Node) -> Array:
	var out: Array[String] = []
	var b := Boy.new()
	parent.add_child(b)
	b.frozen = true
	b.position = Vector3(0, 60, 0)
	var dt := 1.0 / 30.0
	var res := {}
	var prev := [Vector3.INF]
	var tick := func(tag: String) -> void:
		b.rotation.y += 0.35
		b._tick(dt)
		var e: Vector2 = b.hat_offset_error()
		var hc: Vector3 = b.hat_on_head() * b.hat_band_c * 0.85
		var mv := 0.0 if prev[0] == Vector3.INF else hc.distance_to(prev[0])
		prev[0] = hc
		var r: Array = res.get(tag, [0.0, 0.0, 0, 0.0, 0.0])
		res[tag] = [maxf(r[0], e.x), maxf(r[1], e.y), int(r[2]) + 1, maxf(r[3], b.hat_s), maxf(r[4], mv)]
	for stc: String in ["stand", "crouch"]:
		b.stance = stc
		for i in 24:
			b.charge(i / 23.0)
			tick.call("charge " + stc)
		b.start_throw(1.0)
		for i in 90:
			tick.call("throw " + stc)
			if b.anim == "idle":
				break
	for k: String in ["cheer", "oops"]:
		b.react(k)
		for i in 120:
			tick.call(k)
			if b.anim == "idle":
				break
	var tt := 0.0
	var back_on := true
	for kind: String in ["sleep", "sun", "seat", "seatlie"]:
		var seq: Array = [[26, 0.0, 1.0, 0.0, 0.0]]   # [ticks, sit from, to, lie from, to]
		if kind != "seat":
			seq += [[30, 1.0, 1.0, 0.0, 1.0], [60, 1.0, 1.0, 1.0, 1.0], [30, 1.0, 1.0, 1.0, 0.0]]
		else:
			seq += [[60, 1.0, 1.0, 1.0, 1.0]]
		seq += [[26, 1.0, 0.0, 0.0, 0.0]]
		for s: Array in seq:
			for i in int(s[0]):
				var u := (i + 1) / float(s[0])
				tt += dt
				b.activity(kind, lerpf(s[1], s[2], u), lerpf(s[3], s[4], u), tt)
				tick.call("rest " + kind)
		if b.hat_s > 0.0:
			back_on = false
		b.end_activity()
		tick.call("rest " + kind)
	var worst := 0.0
	var ok := back_on
	for tag: String in res:
		var r: Array = res[tag]
		worst = maxf(worst, r[0])
		# only lying on his back takes it off his head (over his face), and never faster than a hand moves
		if (float(r[3]) > 0.0 and not tag in ["rest sleep", "rest sun", "rest seatlie"]) or float(r[4]) > 0.06:
			ok = false
		out.append("hat %-14s offset max %.3f mm / %.4f deg over %d ticks; %s; moves on the head <= %.1f cm/tick" % [tag, float(r[0]) * 1000.0,
			rad_to_deg(float(r[1])), int(r[2]), "on his head throughout" if float(r[3]) <= 0.0 else "tipped over his face by hand and back", float(r[4]) * 100.0])
	parent.remove_child(b)
	b.free()
	return [out, worst, ok and worst < 0.0005]

func report(tag: String) -> Array[String]:
	var lines: Array[String] = []
	for st: String in off:
		var o: Array = off[st]
		var sr: Array = seat[st]
		var c: Array = clear.get(st, [INF, ""])
		var h: Array = hands.get(st, [INF, ""])
		var where := "on his head" if float(sr[1]) <= 0.0 else "over his face" if float(sr[0]) >= 1.0 else "head %.2f..%.2f face" % [sr[0], sr[1]]
		var gr := ""
		if grip.has(st):
			var g: Array = grip[st]
			gr = " · hand on the brim while it moves (%d frames, hold >= %.2f, knuckles <= %.1f cm off the grip)" % [g[0], g[1], float(g[2]) * 100.0]
		lines.append("%s %-28s %-13s offset %.2f mm / %.3f deg, moves <= %.1f cm/frame over %4d frames · lowest point %+.1f cm over %s · other hand %.1f cm (%s)%s" % [
			tag, st, where, float(o[0]) * 1000.0, rad_to_deg(float(o[1])), float(jump.get(st, 0.0)) * 100.0, int(o[2]), float(c[0]) * 100.0, c[1],
			float(h[0]) * 100.0, h[1], gr])
	return lines
