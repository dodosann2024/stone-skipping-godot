class_name BoyMesh
extends RefCounted
## Smooth, softly stylized geometry for the straw-hat boy (v5): chibi head with painted-on face,
## chunky rounded hair tufts, open red vest over a white tank, yellow board shorts, flip-flops.
## Every part is built in its own joint space (front = -Z, limbs hang along -Y).
## Vertex colour alpha is a material id for character.gdshader: 1 cloth, 0.8 skin, 0.6 straw, 0.4 hair.

const SKIN := Color(0.97, 0.75, 0.59, 0.8)
const SKIN_D := Color(0.9, 0.62, 0.48, 0.8)
const RED := Color(0.87, 0.2, 0.16)
const RED_D := Color(0.62, 0.12, 0.1)
const TRIM := Color(0.98, 0.95, 0.88)
const TANK := Color(0.97, 0.97, 0.95)
const YEL := Color(1.0, 0.8, 0.26)
const YEL2 := Color(0.95, 0.63, 0.12)
const STRAW := Color(0.97, 0.86, 0.6, 0.6)
const STRAW2 := Color(0.88, 0.73, 0.47, 0.6)
const HAIR := Color(0.2, 0.13, 0.09, 0.4)
const SOLE := Color(0.18, 0.55, 0.9)
const INK := Color(0.1, 0.06, 0.05)
const IRIS := Color(0.2, 0.11, 0.07)
const IRIS_L := Color(0.5, 0.3, 0.16)
const MOUTH := Color(0.5, 0.14, 0.12)
const TONGUE := Color(0.95, 0.47, 0.45)
const WHITE := Color(1, 1, 1)

const HC := Vector3(0, 0.165, 0.0)       # head centre (head space, origin at the neck top)
const HR := Vector3(0.182, 0.168, 0.172)  # head radii
const EYE_X := 0.07
const EYE_Y := 0.148

# torso cross-sections in spine space: [y, half-width, half-depth]
const PROF := [[-0.07, 0.124, 0.094], [-0.02, 0.121, 0.094], [0.05, 0.114, 0.09], [0.13, 0.119, 0.089],
		[0.2, 0.128, 0.089], [0.245, 0.13, 0.083], [0.275, 0.11, 0.07], [0.3, 0.064, 0.052]]

# ------------------------------------------------------------------ smooth surface helpers

## Smooth surface through a grid of points (rows[j][i]); wrap closes every row into a ring.
## ref (a point, or one centre per row) only decides which side is "outside".
static func grid(b: MeshBuilder, rows: Array, col: Variant, wrap: bool, ref: Variant, outward := true) -> void:
	var nr := rows.size()
	var nc: int = (rows[0] as PackedVector3Array).size()
	var cu := nc if wrap else nc - 1
	var acc: Array[PackedVector3Array] = []
	for j in nr:
		var a := PackedVector3Array()
		a.resize(nc)
		acc.append(a)
	var sgn := 0.0
	for j in nr - 1:
		var r0: PackedVector3Array = rows[j]
		var r1: PackedVector3Array = rows[j + 1]
		var rc: Vector3 = ref if ref is Vector3 else ((ref as Array)[j] as Vector3).lerp((ref as Array)[j + 1] as Vector3, 0.5)
		for i in cu:
			var i1 := (i + 1) % nc
			var n := (r1[i1] - r0[i]).cross(r1[i] - r0[i1])
			sgn += n.dot((r0[i] + r1[i1]) * 0.5 - rc)
			acc[j][i] += n; acc[j][i1] += n
			acc[j + 1][i] += n; acc[j + 1][i1] += n
	var s := (1.0 if sgn >= 0.0 else -1.0) * (1.0 if outward else -1.0)
	# collapsed rows (poles / tips) share one normal
	for j in nr:
		var r: PackedVector3Array = rows[j]
		if r[0].distance_to(r[nc / 2]) < 1e-5 and r[0].distance_to(r[nc - 1]) < 1e-5:
			var sum := Vector3.ZERO
			for i in nc:
				sum += acc[j][i]
			for i in nc:
				acc[j][i] = sum
	for j in nr:
		for i in nc:
			acc[j][i] = (acc[j][i] * s).normalized()
	for j in nr - 1:
		var r0: PackedVector3Array = rows[j]
		var r1: PackedVector3Array = rows[j + 1]
		for i in cu:
			var i1 := (i + 1) % nc
			var c: Color = col if col is Color else (col as Callable).call(j, i)
			b.tri_sm(r0[i], r0[i1], r1[i1], acc[j][i], acc[j][i1], acc[j + 1][i1], c, c, c)
			b.tri_sm(r0[i], r1[i1], r1[i], acc[j][i], acc[j + 1][i1], acc[j + 1][i], c, c, c)

static func ell(b: MeshBuilder, c: Vector3, r: Vector3, col: Color, seg := 14, rings := 8, basis := Basis.IDENTITY) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0; m.height = 2.0; m.radial_segments = seg; m.rings = rings
	b.prim_smooth(m, Transform3D(basis * Basis.from_scale(r), c), col)

static func _perp(ax: Vector3) -> Vector3:
	var ref := Vector3.BACK if absf(ax.z) < 0.9 else Vector3.RIGHT
	return ax.cross(ref).normalized()

## Tapered capsule from a to c (rounded joints overlap so bent limbs stay continuous).
static func capsule(b: MeshBuilder, a: Vector3, c: Vector3, r0: float, r1: float, col: Variant, seg := 14, rings := 4, zs := 1.0) -> void:
	var ax := (c - a).normalized()
	var u := _perp(ax)
	var v := ax.cross(u) * zs
	var rows: Array = []
	var cen: Array = []
	for k in rings + 1:
		var th := -PI * 0.5 + PI * 0.5 * k / rings
		rows.append(_ring(a + ax * (r0 * sin(th)), u, v, r0 * cos(th), seg))
		cen.append(a + ax * (r0 * sin(th)))
	for k in rings + 1:
		var th := PI * 0.5 * k / rings
		rows.append(_ring(c + ax * (r1 * sin(th)), u, v, r1 * cos(th), seg))
		cen.append(c + ax * (r1 * sin(th)))
	grid(b, rows, col, true, cen)

static func _ring(c: Vector3, u: Vector3, v: Vector3, r: float, seg: int) -> PackedVector3Array:
	var p := PackedVector3Array()
	for i in seg:
		var a := TAU * i / seg
		p.append(c + (u * sin(a) + v * cos(a)) * r)
	return p

## Surface of revolution about the local Y axis; prof = [Vector2(radius, y)], a = 0 faces -Z.
static func lathe(b: MeshBuilder, prof: PackedVector2Array, seg: int, xf: Transform3D, col: Variant, zs := 1.0) -> void:
	var rows: Array = []
	var cen: Array = []
	for pr in prof:
		var p := PackedVector3Array()
		for i in seg:
			var a := TAU * i / seg
			p.append(xf * Vector3(sin(a) * pr.x, pr.y, -cos(a) * pr.x * zs))
		rows.append(p)
		cen.append(xf * Vector3(0, pr.y, 0))
	grid(b, rows, col, true, cen)

## Round tube along a polyline (piping, straps, cords).
static func tube(b: MeshBuilder, pts: PackedVector3Array, r: float, col: Color, seg := 6, caps := true) -> void:
	var n := pts.size()
	var rows: Array = []
	var cen: Array = []
	var t0 := (pts[1] - pts[0]).normalized()
	var u := _perp(t0)
	if caps:
		rows.append(_ring(pts[0] - t0 * r * 0.6, u, t0.cross(u), 0.0, seg))
		cen.append(pts[0])
	for i in n:
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		u = (u - tg * u.dot(tg)).normalized()
		rows.append(_ring(pts[i], u, tg.cross(u), r, seg))
		cen.append(pts[i])
	if caps:
		var tl := (pts[n - 1] - pts[n - 2]).normalized()
		rows.append(_ring(pts[n - 1] + tl * r * 0.6, u, tl.cross(u), 0.0, seg))
		cen.append(pts[n - 1])
	grid(b, rows, col, true, cen)

## Flat print (flower / patch) lying on a surface with normal n.
static func flat_poly(b: MeshBuilder, c: Vector3, n: Vector3, pts: Array, col: Color) -> void:
	var z := n.normalized()
	var x := _perp(z)
	var y := z.cross(x)
	for i in pts.size():
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		b.tri_sm(c, c + x * p0.x + y * p0.y, c + x * p1.x + y * p1.y, z, z, z, col, col, col)

static func flower(b: MeshBuilder, p: Vector3, n: Vector3, s: float, petal: Color, centre: Color) -> void:
	for k in 5:
		var a := k * TAU / 5.0
		flat_poly(b, p + n.normalized() * 0.0005, n, ellipse(cos(a) * s * 0.85, sin(a) * s * 0.85, s * 0.62, s * 0.62, 7), petal)
	flat_poly(b, p + n.normalized() * 0.0012, n, ellipse(0, 0, s * 0.42, s * 0.42, 7), centre)

static func ellipse(cx: float, cy: float, rx: float, ry: float, n := 12) -> Array:
	var pts := []
	for i in n:
		var a := TAU * float(i) / n
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

static func rrect(cx: float, cy: float, w: float, h: float, ang: float) -> Array:
	var pts := []
	var r := minf(w, h) * 0.5
	for k in 4:
		var c := Vector2((w * 0.5 - r) * (1 if k == 0 or k == 3 else -1), (h * 0.5 - r) * (1 if k < 2 else -1))
		for j in 4:
			var a := (k + j / 3.0) * PI * 0.5
			pts.append((c + Vector2(cos(a), sin(a)) * r).rotated(ang) + Vector2(cx, cy))
	return pts

# ------------------------------------------------------------------ head shape + face decals

static func head_r(d: Vector3) -> float:
	var r := 1.0 / Vector3(d.x / HR.x, d.y / HR.y, d.z / HR.z).length()
	var low := smoothstep(0.05, 0.95, -d.y)
	var front := smoothstep(-0.2, 0.9, -d.z)
	r *= 1.0 - 0.13 * low * low * (0.35 + 0.65 * front)                       # soft chin
	r *= 1.0 + 0.035 * exp(-pow((absf(d.x) - 0.55) / 0.28, 2.0) - pow((d.y + 0.25) / 0.25, 2.0)) * front   # round cheeks
	r *= 1.0 - 0.03 * smoothstep(0.7, 1.0, -d.z) * (1.0 - low)                # flatter face plane
	r *= 1.0 + 0.04 * smoothstep(0.2, 1.0, d.z) * smoothstep(-0.3, 0.4, d.y)  # fuller back of the skull
	return r

static func head_dir(e: float, a: float) -> Vector3:
	return Vector3(cos(e) * sin(a), sin(e), -cos(e) * cos(a))

static func head_pt(d: Vector3, off := 0.0) -> Vector3:
	var dn := d.normalized()
	return HC + dn * (head_r(dn) + off)

static func _head_f(p: Vector3) -> float:
	var dv := p - HC
	return dv.length() - head_r(dv.normalized())

static func head_n(p: Vector3) -> Vector3:
	var e := 0.002
	return Vector3(_head_f(p + Vector3(e, 0, 0)) - _head_f(p - Vector3(e, 0, 0)),
		_head_f(p + Vector3(0, e, 0)) - _head_f(p - Vector3(0, e, 0)),
		_head_f(p + Vector3(0, 0, e)) - _head_f(p - Vector3(0, 0, e))).normalized()

## point on the face straight in front of head-space (x, y)
static func face_pt(x: float, y: float, lift := 0.0) -> Vector3:
	var lo := 0.0
	var hi := 0.4
	for k in 22:
		var m := (lo + hi) * 0.5
		if _head_f(Vector3(x, y, HC.z - m)) < 0.0:
			lo = m
		else:
			hi = m
	var p := Vector3(x, y, HC.z - lo)
	return p + head_n(p) * lift

static func eye_c() -> Vector3:
	return Vector3(0, EYE_Y, face_pt(EYE_X, EYE_Y).z)

## convex polygon painted onto the face (smooth normals follow the head)
static func decal(b: MeshBuilder, pts: Array, col: Color, lift := 0.002, shift := Vector3.ZERO) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var cc := face_pt(c.x, c.y, lift)
	var nc := head_n(cc)
	for i in pts.size():
		var pa: Vector2 = pts[i]
		var pb: Vector2 = pts[(i + 1) % pts.size()]
		var a := face_pt(pa.x, pa.y, lift)
		var bb := face_pt(pb.x, pb.y, lift)
		b.tri_sm(cc - shift, a - shift, bb - shift, nc, head_n(a), head_n(bb), col, col, col)

## thick curved stroke (lids, brows, closed eyes, sleepy mouth)
static func stroke(b: MeshBuilder, cx: float, cy: float, rx: float, ry: float, th0: float, th1: float, a0: float, a1: float, col: Color, lift := 0.003, n := 8, shift := Vector3.ZERO) -> void:
	for i in n:
		var u0 := lerpf(a0, a1, float(i) / n)
		var u1 := lerpf(a0, a1, float(i + 1) / n)
		var w0 := lerpf(th0, th1, float(i) / n) * sin(PI * clampf(float(i) / n * 0.8 + 0.1, 0.0, 1.0))
		var w1 := lerpf(th0, th1, float(i + 1) / n) * sin(PI * clampf(float(i + 1) / n * 0.8 + 0.1, 0.0, 1.0))
		var p0 := Vector2(cx + cos(u0) * rx, cy + sin(u0) * ry)
		var p1 := Vector2(cx + cos(u1) * rx, cy + sin(u1) * ry)
		var d0 := Vector2(cos(u0) * ry, sin(u0) * rx).normalized() * w0 * 0.5
		var d1 := Vector2(cos(u1) * ry, sin(u1) * rx).normalized() * w1 * 0.5
		decal(b, [p0 - d0, p1 - d1, p1 + d1, p0 + d0], col, lift, shift)

static func d_shape(cx: float, top: float, w: float, h: float, n := 12) -> Array:
	var pts := [Vector2(cx + w * 0.5, top)]
	for i in range(1, n):
		var a := PI * float(i) / n
		pts.append(Vector2(cx + cos(a) * w * 0.5, top - sin(a) * h))
	pts.append(Vector2(cx - w * 0.5, top))
	return pts

## hairline elevation (radians above the head's equator) for azimuth a (0 = front)
static func hairline(a: float) -> float:
	var c := cos(a)
	return 0.04 + 0.5 * pow(maxf(c, 0.0), 1.4) - 0.62 * pow(maxf(-c, 0.0), 1.2)

## rounded, slightly flattened hair clump growing from the scalp at (elevation e, azimuth a)
static func tuft(b: MeshBuilder, e: float, a: float, length: float, width: float, tilt: float, bow: float) -> void:
	var dir0 := head_dir(e, a)
	var base := head_pt(dir0, 0.004)
	var out := head_n(base)
	var down := (head_pt(head_dir(e - 0.05, a)) - head_pt(dir0)).normalized()
	var side := out.cross(down).normalized()
	var dv := (down * cos(tilt) + side * sin(tilt)).normalized()
	var rows: Array = []
	var cen: Array = []
	var n := 7
	for k in n + 1:
		var t := float(k) / n
		var c := base + dv * (length * t) + out * (length * (bow * t - (bow + 0.12) * t * t)) - dv * 0.012
		var w := width * pow(1.0 - t, 0.8) * (0.85 + 0.15 * sin(PI * minf(t * 2.0, 1.0)))
		var h := w * 0.5
		var sd := out.cross(dv).normalized()
		var r := PackedVector3Array()
		for i in 8:
			var an := TAU * i / 8.0
			r.append(c + sd * cos(an) * w + out * sin(an) * h)
		rows.append(r)
		cen.append(c)
	grid(b, rows, HAIR, true, cen)

# ------------------------------------------------------------------ torso / vest

static func prof(y: float) -> Vector2:
	if y <= PROF[0][0]:
		return Vector2(PROF[0][1], PROF[0][2])
	for i in range(1, PROF.size()):
		if y <= PROF[i][0]:
			var k: float = smoothstep(0.0, 1.0, (y - PROF[i - 1][0]) / (PROF[i][0] - PROF[i - 1][0]))
			return Vector2(lerpf(PROF[i - 1][1], PROF[i][1], k), lerpf(PROF[i - 1][2], PROF[i][2], k))
	var l: Array = PROF[PROF.size() - 1]
	return Vector2(l[1], l[2])

## rounded-rectangle cross-section; a = 0 front (-Z), PI/2 right (+X)
static func body_pt(a: float, y: float, off: float) -> Vector3:
	var r := prof(y)
	var s := sin(a)
	var c := cos(a)
	var k := 0.8
	var sx := signf(s) * pow(absf(s), k)
	var cz := signf(c) * pow(absf(c), k)
	var belly := 0.008 * maxf(c, 0.0) * exp(-pow((y - 0.06) / 0.07, 2.0))
	return Vector3(sx * (r.x + off), y, -cz * (r.y + off + belly))

static func loft(b: MeshBuilder, y0: float, y1: float, rows_n: int, seg: int, col: Variant, off := 0.0) -> void:
	var rows: Array = []
	var cen: Array = []
	for j in rows_n + 1:
		var y := lerpf(y0, y1, float(j) / rows_n)
		var r := PackedVector3Array()
		for i in seg:
			r.append(body_pt(TAU * i / seg, y, off))
		rows.append(r)
		cen.append(Vector3(0, y, 0))
	grid(b, rows, col, true, cen)

## point on the open vest: u runs from the right front edge (0) around the back to the left front edge (1)
static func vest_pt(u: float, t: float, off: float) -> Vector3:
	var yy := lerpf(-0.06, 0.28, t)
	var op := lerpf(0.11, 0.82, smoothstep(0.0, 0.27, yy))
	var a := lerpf(op, TAU - op, u)
	var d := minf(absf(a - PI * 0.5), absf(a - PI * 1.5))
	var bump := 1.0 - smoothstep(0.3, 0.85, d)
	var ytop := 0.288 - 0.135 * bump
	var ybot := -0.065 + 0.006 * sin(a * 5.0 + 1.3)
	var y := lerpf(ybot, ytop, t)
	var flare := 0.024 * (1.0 - smoothstep(0.0, 0.12, y + 0.065))
	return body_pt(a, y, off + flare)

static func vest_panel(b: MeshBuilder, u0: float, u1: float, nu: int) -> void:
	var nt := 9
	var outer := 0.017
	var inner := 0.01
	var ro: Array = []
	var ri: Array = []
	for j in nt + 1:
		var po := PackedVector3Array()
		var pi := PackedVector3Array()
		for i in nu + 1:
			var u := lerpf(u0, u1, float(i) / nu)
			po.append(vest_pt(u, float(j) / nt, outer))
			pi.append(vest_pt(u, float(j) / nt, inner))
		ro.append(po)
		ri.append(pi)
	grid(b, ro, RED, false, Vector3(0, 0.12, 0))
	grid(b, ri, RED_D, false, Vector3(0, 0.12, 0), false)
	# rolled white piping: hem, neckline / armholes, and the open front edges
	var mid := (outer + inner) * 0.5
	for tt in [0.0, 1.0]:
		var line := PackedVector3Array()
		for i in nu * 2 + 1:
			line.append(vest_pt(lerpf(u0, u1, float(i) / (nu * 2)), tt, mid))
		tube(b, line, 0.0062, TRIM, 6, false)
	for ue in [u0, u1]:
		if ue != 0.0 and ue != 1.0:
			continue
		var line2 := PackedVector3Array()
		for j in nt + 1:
			line2.append(vest_pt(ue, float(j) / nt, mid))
		tube(b, line2, 0.0062, TRIM, 6, true)

static func vest_patch(b: MeshBuilder, u0: float, u1: float, t0: float, t1: float, col: Color, off: float) -> void:
	var rows: Array = []
	for j in 4:
		var r := PackedVector3Array()
		for i in 4:
			r.append(vest_pt(lerpf(u0, u1, i / 3.0), lerpf(t0, t1, j / 3.0), off))
		rows.append(r)
	grid(b, rows, col, false, Vector3(0, 0.12, 0))

# ------------------------------------------------------------------ build all parts

static func build(boy: Boy) -> void:
	var b: MeshBuilder
	# ---- pelvis: board shorts
	b = MeshBuilder.new()
	var sp := PackedVector2Array([Vector2(0.0, 0.098), Vector2(0.128, 0.096), Vector2(0.134, 0.085), Vector2(0.137, 0.05),
			Vector2(0.142, 0.0), Vector2(0.14, -0.045), Vector2(0.125, -0.085), Vector2(0.08, -0.11), Vector2(0.0, -0.118)])
	lathe(b, sp, 22, Transform3D.IDENTITY, func(j: int, _i: int) -> Color: return YEL2 if j == 1 or j == 2 else YEL, 0.77)
	for sx: int in [-1, 1]:
		tube(b, PackedVector3Array([Vector3(0.008 * sx, 0.082, -0.106), Vector3(0.016 * sx, 0.05, -0.108), Vector3(0.02 * sx, 0.03, -0.107)]), 0.004, TRIM, 5)
	for k in 7:
		var a := -2.5 + k * 0.83
		var y := -0.03 + (k % 2) * 0.05
		var p := Vector3(sin(a) * 0.141, y, -cos(a) * 0.141 * 0.77)
		flower(b, p, Vector3(sin(a), 0, -cos(a) * 1.3), 0.014, Color(1, 0.98, 0.93), Color(1, 0.45, 0.12))
	boy.add_part("pelvis", b)
	# ---- spine: white tank top, skin shoulders + neck, back panel of the vest
	b = MeshBuilder.new()
	loft(b, -0.06, 0.305, 16, 28, _tank_col)
	lathe(b, PackedVector2Array([Vector2(0.05, 0.26), Vector2(0.047, 0.3), Vector2(0.045, 0.34), Vector2(0.044, 0.37)]), 14, Transform3D.IDENTITY, SKIN)
	for sx: int in [-1, 1]:
		ell(b, Vector3(0.118 * sx, 0.252, 0), Vector3(0.046, 0.046, 0.046), SKIN, 12, 8)
	flower(b, Vector3(0.0, 0.17, -0.0935), Vector3(0, -0.05, -1), 0.016, Color(0.3, 0.66, 0.95), Color(1.0, 1.0, 1.0))
	vest_panel(b, 0.24, 0.76, 14)
	boy.add_part("spine", b)
	# ---- vest front flaps (swing a little with the body)
	for side in ["r", "l"]:
		b = MeshBuilder.new()
		var u0 := 0.0 if side == "r" else 0.76
		var u1 := 0.24 if side == "r" else 1.0
		vest_panel(b, u0, u1, 7)
		var pu0 := 0.06 if side == "r" else 0.85
		var pu1 := 0.15 if side == "r" else 0.94
		vest_patch(b, pu0, pu1, 0.14, 0.36, RED.darkened(0.08), 0.0185)
		var seam := PackedVector3Array()
		for i in 5:
			seam.append(vest_pt(lerpf(pu0, pu1, i / 4.0), 0.36, 0.0195))
		tube(b, seam, 0.0035, TRIM, 5)
		if side == "r":
			for k in 3:
				ell(b, vest_pt(0.02, 0.25 + k * 0.2, 0.019), Vector3(0.008, 0.008, 0.005), Color(1.0, 0.86, 0.3), 8, 4)
		boy.add_part("vest_" + side, b)
	# ---- head (origin at the neck top)
	b = MeshBuilder.new()
	var hrows: Array = []
	var hcen: Array = []
	for j in 21:
		var e := PI * 0.5 - PI * j / 20.0
		var r := PackedVector3Array()
		for i in 32:
			r.append(head_pt(head_dir(e, TAU * i / 32.0)))
		hrows.append(r)
		hcen.append(HC)
	grid(b, hrows, SKIN, true, hcen)
	for sx: int in [-1, 1]:
		var ep := Vector3(0.176 * sx, 0.14, 0.012)
		ell(b, ep, Vector3(0.028, 0.044, 0.03), SKIN, 12, 8, Basis(Vector3.UP, 0.25 * sx))
		ell(b, ep + Vector3(0.012 * sx, 0, -0.004), Vector3(0.012, 0.027, 0.016), SKIN_D, 8, 6, Basis(Vector3.UP, 0.25 * sx))
		# thick, determined brows (inner end lower)
		var bx := EYE_X * sx
		decal(b, [Vector2(bx - 0.03 * sx, 0.197), Vector2(bx + 0.028 * sx, 0.209), Vector2(bx + 0.026 * sx, 0.221), Vector2(bx - 0.03 * sx, 0.21)], HAIR, 0.003)
		# freckles
		for k in 3:
			var fx := (0.07 + k * 0.015) * sx
			var fy := 0.104 + (k % 2) * 0.009
			decal(b, ellipse(fx, fy, 0.0042, 0.0042, 6), Color(0.82, 0.5, 0.36, 0.8), 0.0015)
	ell(b, face_pt(0, 0.115, -0.004), Vector3(0.015, 0.012, 0.013), SKIN_D.lightened(0.15), 10, 6)   # button nose
	# band-aid on the left cheek
	decal(b, rrect(-0.088, 0.098, 0.05, 0.017, 0.5), Color(0.97, 0.87, 0.7, 0.8), 0.0025)
	decal(b, rrect(-0.088, 0.098, 0.016, 0.012, 0.5), Color(0.92, 0.74, 0.58, 0.8), 0.0035)
	# hair: a smooth cap whose rim sits high at the front and low at the nape, plus chunky tufts
	var crow: Array = []
	var ccen: Array = []
	for j in 15:
		var r := PackedVector3Array()
		for i in 36:
			var a := TAU * i / 36.0
			var e := lerpf(PI * 0.5, hairline(a), float(j) / 14.0)
			r.append(head_pt(head_dir(e, a), 0.0125 if j < 14 else 0.002))
		crow.append(r)
		ccen.append(HC)
	grid(b, crow, HAIR, true, ccen)
	for k in 7:   # fringe
		var a := -0.84 + k * 0.28
		tuft(b, hairline(a) + 0.13, a, 0.07 + 0.012 * float((k * 5) % 3) + absf(a) * 0.012, 0.036, a * 0.45, 0.32)
	for sx: int in [-1, 1]:
		tuft(b, 0.16, 1.32 * sx, 0.075, 0.03, 0.2 * sx, 0.12)     # sideburn
		tuft(b, 0.3, 1.62 * sx, 0.085, 0.036, -0.25 * sx, 0.2)    # above the ear
		tuft(b, 0.25, 2.05 * sx, 0.09, 0.04, -0.3 * sx, 0.3)
	for k in 5:   # nape spikes
		var a := PI - 0.9 + k * 0.45
		tuft(b, hairline(a) + 0.2, a, 0.085, 0.042, (a - PI) * 0.5, 0.35)
	for k in 3:   # spikes poking out under the brim at the back
		var a := PI - 0.6 + k * 0.6
		tuft(b, 0.2, a, 0.085, 0.045, (a - PI) * 0.6, 0.38)
	boy.add_part("head", b)
	# ---- eyes (open, blinkable). Built around eye_c() so they can be squashed about the eye line.
	var ec := eye_c()
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		var ex := EYE_X * sx
		decal(b, ellipse(ex, EYE_Y, 0.026, 0.034, 16), IRIS, 0.0022, ec)
		decal(b, ellipse(ex, EYE_Y - 0.012, 0.019, 0.015, 12), IRIS_L, 0.0027, ec)
		decal(b, ellipse(ex, EYE_Y + 0.003, 0.012, 0.017, 12), INK, 0.0032, ec)
		decal(b, ellipse(ex - 0.008, EYE_Y + 0.013, 0.0085, 0.0095, 10), WHITE, 0.0038, ec)
		decal(b, ellipse(ex + 0.009, EYE_Y - 0.013, 0.004, 0.004, 8), WHITE, 0.0038, ec)
		stroke(b, ex, EYE_Y + 0.001, 0.029, 0.036, 0.009, 0.006, PI * (0.5 + 0.45 * sx), PI * (0.5 - 0.42 * sx), INK, 0.0042, 9, ec)
	boy.add_part("eyes", b)
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		stroke(b, EYE_X * sx, EYE_Y + 0.004, 0.025, 0.012, 0.0085, 0.0085, PI + 0.2, TAU - 0.2, INK, 0.003)   # sleepy closed eyes
	boy.add_part("eyes_closed", b)
	# ---- mouths
	b = MeshBuilder.new()   # big cheeky grin with teeth
	decal(b, d_shape(0.0, 0.085, 0.062, 0.03), MOUTH)
	decal(b, [Vector2(-0.027, 0.0845), Vector2(0.027, 0.0845), Vector2(0.023, 0.0755), Vector2(-0.023, 0.0755)], WHITE, 0.0026)
	decal(b, ellipse(0.0, 0.0625, 0.015, 0.0075, 10), TONGUE, 0.0026)
	boy.add_part("mouth_smile", b)
	b = MeshBuilder.new()   # gritted teeth (effort)
	decal(b, rrect(0.0, 0.077, 0.07, 0.026, 0.0), MOUTH)
	decal(b, rrect(0.0, 0.077, 0.062, 0.018, 0.0), WHITE, 0.0026)
	decal(b, [Vector2(-0.03, 0.0775), Vector2(0.03, 0.0775), Vector2(0.03, 0.0765), Vector2(-0.03, 0.0765)], INK, 0.0034)
	for k in 3:
		var x := -0.015 + k * 0.015
		decal(b, [Vector2(x - 0.0007, 0.085), Vector2(x + 0.0007, 0.085), Vector2(x + 0.0007, 0.069), Vector2(x - 0.0007, 0.069)], INK, 0.0034)
	boy.add_part("mouth_grit", b)
	b = MeshBuilder.new()   # wide laugh
	decal(b, d_shape(0.0, 0.09, 0.076, 0.045), MOUTH)
	decal(b, [Vector2(-0.032, 0.0895), Vector2(0.032, 0.0895), Vector2(0.027, 0.08), Vector2(-0.027, 0.08)], WHITE, 0.0026)
	decal(b, ellipse(0.0, 0.06, 0.02, 0.01, 10), TONGUE, 0.0026)
	boy.add_part("mouth_laugh", b)
	b = MeshBuilder.new()   # sleepy content smile
	stroke(b, 0.0, 0.088, 0.022, 0.011, 0.0065, 0.0065, PI + 0.35, TAU - 0.35, MOUTH)
	boy.add_part("mouth_sleep", b)
	b = MeshBuilder.new()   # "oh no" o-mouth
	decal(b, ellipse(0.0, 0.072, 0.016, 0.019, 14), MOUTH)
	decal(b, ellipse(0.0, 0.066, 0.009, 0.007, 10), TONGUE, 0.0026)
	boy.add_part("mouth_oops", b)
	# ---- sunglasses (sunbathing)
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		var gx := EYE_X * sx
		var gp := face_pt(gx, EYE_Y + 0.004, 0.012)
		ell(b, gp, Vector3(0.039, 0.029, 0.009), Color(0.06, 0.07, 0.1), 14, 6, Basis(Vector3.UP, -0.42 * sx))
		ell(b, gp + Vector3(-0.012, 0.01, -0.006), Vector3(0.01, 0.006, 0.003), Color(0.5, 0.6, 0.7), 8, 4, Basis(Vector3.UP, -0.42 * sx))
		tube(b, PackedVector3Array([gp + Vector3(0.036 * sx, 0.006, 0.01), face_pt(0.165 * sx, EYE_Y + 0.01, 0.01), Vector3(0.19 * sx, EYE_Y + 0.01, 0.05)]), 0.004, INK, 5)
	tube(b, PackedVector3Array([face_pt(-0.033, EYE_Y + 0.012, 0.012), face_pt(0.0, EYE_Y + 0.016, 0.014), face_pt(0.033, EYE_Y + 0.012, 0.012)]), 0.004, INK, 5)
	boy.add_part("glasses", b)
	# ---- straw hat
	b = MeshBuilder.new()
	var crown := PackedVector2Array([Vector2(0.176, -0.012), Vector2(0.174, 0.03), Vector2(0.165, 0.07), Vector2(0.15, 0.095),
			Vector2(0.12, 0.112), Vector2(0.07, 0.121), Vector2(0.0, 0.124)])
	lathe(b, crown, 32, Transform3D.IDENTITY, STRAW)
	lathe(b, PackedVector2Array([Vector2(0.176, -0.006), Vector2(0.18, 0.0), Vector2(0.179, 0.036), Vector2(0.172, 0.042)]), 32, Transform3D.IDENTITY, Color(0.85, 0.15, 0.12))
	var rows: Array = []
	var cen: Array = []
	var rings := [0.16, 0.2, 0.24, 0.275, 0.305, 0.322]
	for ri in rings.size():
		var r: float = rings[ri]
		var y := -0.045 * pow((r - 0.16) / 0.16, 1.5)
		var p := PackedVector3Array()
		for i in 48:
			var a := TAU * i / 48.0
			p.append(Vector3(sin(a) * r, y + 0.004 * sin(a * 3.0 + 1.0) * (r - 0.16) / 0.16, cos(a) * r))
		rows.append(p)
		cen.append(Vector3(0, y - 1.0, 0))
	grid(b, rows, func(j: int, _i: int) -> Color: return STRAW if j % 2 == 0 else STRAW.lerp(STRAW2, 0.45), true, cen)
	var under: Array = []
	for p in rows:
		var q := PackedVector3Array()
		for v in p:
			q.append(v + Vector3(0, -0.011, 0))
		under.append(q)
	grid(b, under, STRAW2, true, cen, false)
	var rim := PackedVector3Array()
	var last: PackedVector3Array = rows[rows.size() - 1]
	for i in 49:
		rim.append(last[i % 48] + Vector3(0, -0.0055, 0))
	tube(b, rim, 0.0075, STRAW2.lerp(STRAW, 0.3), 6, false)
	boy.add_part("hat", b)
	# ---- arms
	for key: String in ["r", "l"]:
		var sx := 1.0 if key == "r" else -1.0
		b = MeshBuilder.new()
		capsule(b, Vector3(0, 0.0, 0), Vector3(0, -Boy.UARM, 0), 0.044, 0.037, SKIN)
		boy.add_part("uarm_" + key, b)
		b = MeshBuilder.new()
		capsule(b, Vector3(0, 0.0, 0), Vector3(0, -Boy.FARM, 0), 0.037, 0.031, SKIN)
		boy.add_part("farm_" + key, b)
		b = MeshBuilder.new()
		ell(b, Vector3(0, -0.038, 0.002), Vector3(0.033, 0.042, 0.025), SKIN, 12, 8)
		ell(b, Vector3(0.002 * sx, -0.068, -0.008), Vector3(0.03, 0.022, 0.023), SKIN, 12, 6)
		capsule(b, Vector3(-0.022 * sx, -0.026, -0.012), Vector3(-0.03 * sx, -0.055, -0.024), 0.012, 0.0105, SKIN, 8, 3)
		boy.add_part("hand_" + key, b)
	# ---- legs
	for key: String in ["r", "l"]:
		var sx := 1.0 if key == "r" else -1.0
		b = MeshBuilder.new()
		var leg := PackedVector2Array([Vector2(0.0, 0.07), Vector2(0.06, 0.066), Vector2(0.077, 0.04), Vector2(0.08, -0.04),
				Vector2(0.083, -0.115), Vector2(0.085, -0.13), Vector2(0.083, -0.15), Vector2(0.06, -0.152)])
		lathe(b, leg, 18, Transform3D(Basis.IDENTITY, Vector3(0.004 * sx, 0, 0)), func(j: int, _i: int) -> Color: return YEL2 if j >= 4 and j <= 5 else YEL, 0.95)
		for k in 3:
			var a := (0.7 + k * 1.75) * sx
			var fy := -0.03 - k * 0.035
			flower(b, Vector3(sin(a) * 0.082 + 0.004 * sx, fy, -cos(a) * 0.082 * 0.95), Vector3(sin(a), 0, -cos(a)), 0.013, Color(1, 0.98, 0.93), Color(1, 0.45, 0.12))
		capsule(b, Vector3(0, -0.1, 0), Vector3(0, -Boy.THIGH, 0), 0.06, 0.05, SKIN)
		boy.add_part("thigh_" + key, b)
		b = MeshBuilder.new()
		var calf := PackedVector2Array([Vector2(0.0, 0.05), Vector2(0.035, 0.043), Vector2(0.05, 0.0), Vector2(0.053, -0.05),
				Vector2(0.05, -0.09), Vector2(0.042, -0.145), Vector2(0.035, -0.2), Vector2(0.034, -Boy.SHIN), Vector2(0.022, -Boy.SHIN - 0.027), Vector2(0.0, -Boy.SHIN - 0.034)])
		lathe(b, calf, 16, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.003)), SKIN)
		boy.add_part("shin_" + key, b)
		b = MeshBuilder.new()
		ell(b, Vector3(0, -0.026, 0.012), Vector3(0.034, 0.03, 0.045), SKIN, 12, 8)
		ell(b, Vector3(0, -0.04, -0.045), Vector3(0.039, 0.022, 0.06), SKIN, 12, 8)
		for k in 4:
			ell(b, Vector3((-0.023 + k * 0.0155) * sx, -0.044, -0.1 + absf(k - 1.2) * 0.005), Vector3(0.009, 0.009, 0.01), SKIN, 8, 5)
		_sandal(b, sx)
		boy.add_part("foot_" + key, b)
	# ---- the flat skipping stone in the right hand
	b = MeshBuilder.new()
	var srng := RandomNumberGenerator.new()
	srng.seed = 3
	var sm := SphereMesh.new()
	sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 9; sm.rings = 4
	b.prim(sm, Transform3D(Basis.from_scale(Vector3(0.05, 0.017, 0.04)), Vector3.ZERO), Color(0.5, 0.52, 0.55), srng, 0.12, 0.04)
	boy.add_part("stone", b)

## tank top colouring of the torso loft (16 rows x 28 columns): bare shoulders, straps, scoop neck
static func _tank_col(j: int, i: int) -> Color:
	var y := lerpf(-0.06, 0.305, (j + 0.5) / 16.0)
	var a := TAU * (i + 0.5) / 28.0
	var x := absf(sin(a)) * prof(y).x
	if y > 0.287:
		return SKIN
	if y > 0.2 and x > 0.088:
		return SKIN
	if y > 0.215 and x < 0.05 and cos(a) > 0.0:
		return SKIN
	return TANK

## flip-flop: rounded sole slab with soft vertical edges + a red Y strap
static func _sandal(b: MeshBuilder, sx: float) -> void:
	var y0 := -Boy.ANKLE_H
	var outline := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var z := -0.03 + cos(a) * 0.104
		var w := 0.043 * (1.0 + 0.12 * cos(a)) * (1.0 if cos(a) < 0.6 else 1.0)
		outline.append(Vector2(sin(a) * w + 0.004 * sx * cos(a), z))
	var top := y0 + 0.014
	var spec := [[y0, 0.0], [y0, 0.9], [y0 + 0.002, 1.0], [y0 + 0.007, 1.0], [top - 0.002, 1.0], [top, 0.92], [top, 0.0]]
	var rows: Array = []
	var cen: Array = []
	for s in spec:
		rows.append(_flat_ring(outline, s[0], s[1]))
		cen.append(Vector3(0, float(s[0]) + (0.003 if float(s[0]) < y0 + 0.005 else -0.003), -0.03))
	grid(b, rows, func(j: int, _i: int) -> Color: return Color(0.96, 0.96, 0.92) if j < 3 else SOLE, true, cen)
	var post := Vector3(0.008 * sx, y0 + 0.02, -0.088)
	for s2: int in [-1, 1]:
		tube(b, PackedVector3Array([post, Vector3(0.024 * s2, -0.037, -0.06), Vector3(0.041 * s2, y0 + 0.016, -0.025)]), 0.0065, Color(0.95, 0.27, 0.22), 6)

static func _flat_ring(outline: PackedVector2Array, y: float, k: float) -> PackedVector3Array:
	var p := PackedVector3Array()
	var c := Vector2(0, -0.03)
	for o in outline:
		var q := c.lerp(o, k)
		p.append(Vector3(q.x, y, q.y))
	return p
