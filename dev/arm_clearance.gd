extends RefCounted
## Arm / body interpenetration check on the exported boy.glb (same model as art/boy/clearance.py).
## The torso is a swept cross-section along a spine polyline (crotch, pelvis, spine_01..03, neck base) whose
## per-slice outline was measured from the rest mesh at export time (boy/torso_profile.json). Every frame of a
## clip is seeked and, for both arms, the elbow / forearm / wrist / hand / finger samples must stay outside
## the torso by a margin; upper arms may only touch it; the arms must not cross each other and the hands /
## forearms must stay out of the thighs and shins. Distances are in skeleton units (Blender metres);
## game metres are x0.85.

const PROFILE := "res://boy/torso_profile.json"
const NODES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]
const SAMPLES := [["upperarm", "lowerarm", 0.55, "ua"], ["upperarm", "lowerarm", 0.8, "ua"], ["lowerarm", "", 0.0, "el"],
	["lowerarm", "hand", 0.25, "fa"], ["lowerarm", "hand", 0.5, "fa"], ["lowerarm", "hand", 0.75, "fa"],
	["hand", "", 0.0, "wr"], ["hand", "middle_01", 0.6, "hd"], ["middle_01", "middle_03", 1.0, "fi"]]
const LABEL := {"ua": "upper arm", "el": "elbow", "fa": "forearm", "wr": "wrist", "hd": "hand", "fi": "fingers"}
const LEG_R := [0.07, 0.045]

var prof: Dictionary
var bins: Array
var nang: int
var lat_w: Array
var drop: float
var limb_r: Dictionary
var sk: Skeleton3D
var idx := {}


func _init() -> void:
	prof = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	bins = prof["bins"]
	nang = int(prof["angles"])
	lat_w = prof["lat_w"]
	drop = float(prof["crotch_drop"])
	limb_r = prof["limb_r"]


func _p(name: String) -> Vector3:
	return sk.get_bone_global_pose(idx[name]).origin


func _nodes() -> Array:
	var up := (_p("spine_01") - _p("pelvis")).normalized()
	var pts: Array[Vector3] = [(_p("thigh_l") + _p("thigh_r")) * 0.5 - up * drop]
	for n: String in NODES:
		pts.append(_p(n))
	var lh := (_p("thigh_l") - _p("thigh_r")).normalized()
	var ls := (_p("clavicle_l") - _p("clavicle_r")).normalized()
	var lats: Array[Vector3] = []
	for w in lat_w:
		lats.append(lh.lerp(ls, float(w)).normalized())
	return [pts, lats]


func _frame_at(pts: Array[Vector3], lats: Array[Vector3], s: float) -> Array:
	var L: Array[float] = []
	var tot := 0.0
	for i in pts.size() - 1:
		L.append(pts[i].distance_to(pts[i + 1]))
		tot += L[i]
	var d := clampf(s, 0.0, 1.0) * tot
	var i := 0
	while i < L.size() - 1 and d > L[i]:
		d -= L[i]
		i += 1
	var u := d / L[i] if L[i] > 0.0 else 0.0
	var c := pts[i].lerp(pts[i + 1], u)
	var t := (pts[i + 1] - pts[i]).normalized()
	var lat := lats[i].lerp(lats[i + 1], u)
	lat = (lat - t * lat.dot(t)).normalized()
	return [c, t, lat, lat.cross(t).normalized()]


func _project(pts: Array[Vector3], p: Vector3) -> Vector2:
	var L: Array[float] = []
	var tot := 0.0
	for i in pts.size() - 1:
		L.append(pts[i].distance_to(pts[i + 1]))
		tot += L[i]
	var best := 1e9
	var bs := 0.0
	var bo := 0.0
	var acc := 0.0
	for i in L.size():
		var ab := pts[i + 1] - pts[i]
		var u := (p - pts[i]).dot(ab) / maxf(ab.length_squared(), 1e-9)
		var uc := clampf(u, 0.0, 1.0)
		var dist := p.distance_to(pts[i] + ab * uc)
		var over := 0.0
		if i == 0 and u < 0.0:
			over = -u * ab.length()
		if i == L.size() - 1 and u > 1.0:
			over = (u - 1.0) * ab.length()
		if dist < best:
			best = dist
			bs = (acc + uc * L[i]) / tot
			bo = over
		acc += L[i]
	return Vector2(bs, bo)


func _radius(s: float, ang: float) -> float:
	var nb := bins.size()
	var x := clampf(s * nb - 0.5, 0.0, nb - 1.0)
	var b0 := int(x)
	var b1 := mini(b0 + 1, nb - 1)
	var fb := x - b0
	var y := fposmod(ang / TAU, 1.0) * nang
	var k0 := int(y) % nang
	var k1 := (k0 + 1) % nang
	var fk := y - floorf(y)
	var r0: float = lerpf(bins[b0][k0], bins[b0][k1], fk)
	var r1: float = lerpf(bins[b1][k0], bins[b1][k1], fk)
	return lerpf(r0, r1, fb)


func _torso_dist(pts: Array[Vector3], lats: Array[Vector3], p: Vector3) -> float:
	var so := _project(pts, p)
	var f := _frame_at(pts, lats, so.x)
	var q: Vector3 = p - f[0]
	var x := q.dot(f[2])
	var y := q.dot(f[3])
	var rho := sqrt(x * x + y * y)
	var a := atan2(y, x)
	var r := _radius(so.x, a)
	var dr := (_radius(so.x, a + 0.05) - _radius(so.x, a - 0.05)) / 0.1
	var d := (rho - r) * r / sqrt(r * r + dr * dr)
	if so.y > 0.0:
		d = Vector2(maxf(d, 0.0), so.y).length() if d > 0.0 else so.y
	return d


static func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	if a < 1e-9 and e < 1e-9:
		return r.length()
	if a < 1e-9:
		return p1.distance_to(p2 + d2 * clampf(f / e, 0.0, 1.0))
	var c := d1.dot(r)
	var b := d1.dot(d2)
	var den := a * e - b * b
	var s := clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-9 else 0.0
	var t := (b * s + f) / e if e > 1e-9 else 0.0
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


## one frame -> {"r": [clearance, label], "r_ua", "l", "l_ua", "arms", "legs"}
func _frame() -> Dictionary:
	var nl := _nodes()
	var pts: Array[Vector3] = nl[0]
	var lats: Array[Vector3] = nl[1]
	var res := {}
	var legs := [1e9, ""]
	for s in ["l", "r"]:
		var best := [1e9, ""]
		var best_ua := [1e9, ""]
		for smp: Array in SAMPLES:
			var p := _p(smp[0] + "_" + s)
			if smp[1] != "":
				p = p.lerp(_p(smp[1] + "_" + s), smp[2])
			var key: String = smp[3]
			var d := _torso_dist(pts, lats, p) - float(limb_r[key])
			if key == "ua":
				if d < best_ua[0]:
					best_ua = [d, LABEL[key]]
				continue
			if d < best[0]:
				best = [d, LABEL[key]]
			for leg in ["l", "r"]:
				var dt := _seg_dist(p, p, _p("thigh_" + leg), _p("calf_" + leg)) - LEG_R[0] - float(limb_r[key])
				var dc := _seg_dist(p, p, _p("calf_" + leg), _p("foot_" + leg)) - LEG_R[1] - float(limb_r[key])
				if minf(dt, dc) < legs[0]:
					legs = [minf(dt, dc), "%s %s / %s %s" % [s.to_upper(), LABEL[key], "thigh" if dt < dc else "shin", leg.to_upper()]]
		res[s] = best
		res[s + "_ua"] = best_ua
	var segs := {}
	for s in ["l", "r"]:
		segs[s] = [[_p("upperarm_" + s).lerp(_p("lowerarm_" + s), 0.5), _p("lowerarm_" + s), 0.037],
			[_p("lowerarm_" + s), _p("hand_" + s), 0.031], [_p("hand_" + s), _p("middle_03_" + s), 0.022]]
	var arms := [1e9, ""]
	var names := ["upper arm", "forearm", "hand"]
	for i in 3:
		for j in 3:
			var a1: Array = segs["r"][i]
			var a2: Array = segs["l"][j]
			var d: float = _seg_dist(a1[0], a1[1], a2[0], a2[1]) - float(a1[2]) - float(a2[2])
			if d < arms[0]:
				arms = [d, "R %s / L %s" % [names[i], names[j]]]
	res["arms"] = arms
	res["legs"] = legs
	return res


## seeks every frame (1/30 s) of each clip on a private copy of the model;
## -> {clip: {key: [worst clearance, label, time]}}
## twist: the aiming chest twist (Boy.twist_spine) applied on top of every frame, in full up to
## twist_hold[clip] s (the wind-up he aims in) and then fading as the hips square up (rate 26 /s, as in main)
func run(host: Node, clips: Array, twist := 0.0, twist_hold := {}) -> Dictionary:
	var model: Node3D = (load("res://boy/boy.glb") as PackedScene).instantiate()
	host.add_child(model)
	sk = model.find_child("Skeleton3D") as Skeleton3D
	var ap := model.find_child("AnimationPlayer") as AnimationPlayer
	for n in NODES + ["thigh_l", "thigh_r", "clavicle_l", "clavicle_r"]:
		idx[n] = sk.find_bone(n)
	for s in ["l", "r"]:
		for b in ["upperarm", "lowerarm", "hand", "middle_01", "middle_03", "thigh", "calf", "foot"]:
			idx[b + "_" + s] = sk.find_bone(b + "_" + s)
	var out := {}
	for clip: String in clips:
		ap.play(clip)
		var length := ap.get_animation(clip).length
		var worst := {}
		var n := int(round(length * 30.0))
		for f in n + 1:
			ap.seek(f / 30.0, true)
			if twist != 0.0:
				var hold := float(twist_hold.get(clip, length))
				Boy.twist_spine(sk, twist * exp(-26.0 * maxf(f / 30.0 - hold, 0.0)))
			var c := _frame()
			for k: String in c:
				if not worst.has(k) or c[k][0] < worst[k][0]:
					worst[k] = [c[k][0], c[k][1], f / 30.0]
		worst["frames"] = n + 1
		out[clip] = worst
	host.remove_child(model)
	model.free()
	return out
