class_name BoyMesh
extends RefCounted
## Low-poly geometry for the straw-hat boy (v4): boyish face + spiky short hair, open red vest over a white tank.
## Every part is built in its own joint space (front = -Z, limbs hang along -Y).

const SKIN := Color(0.93, 0.70, 0.52)
const SKIN_D := Color(0.86, 0.60, 0.44)
const RED := Color(0.85, 0.13, 0.11)
const RED_D := Color(0.6, 0.08, 0.07)
const TRIM := Color(0.98, 0.95, 0.88)
const TANK := Color(0.97, 0.97, 0.94)
const YEL := Color(1.0, 0.8, 0.12)
const YEL2 := Color(0.93, 0.62, 0.04)
const STRAW := Color(0.95, 0.85, 0.6)
const STRAW2 := Color(0.84, 0.69, 0.42)
const HAIR := Color(0.13, 0.08, 0.05)
const SOLE := Color(0.12, 0.5, 0.85)
const INK := Color(0.07, 0.05, 0.04)
const MOUTH := Color(0.45, 0.1, 0.09)
const TONGUE := Color(0.93, 0.42, 0.42)

# torso cross-sections in spine space: [y, half-width, half-depth]
const PROF := [[-0.06, 0.116, 0.086], [-0.03, 0.113, 0.083], [0.05, 0.106, 0.079], [0.13, 0.114, 0.085],
		[0.2, 0.125, 0.088], [0.245, 0.127, 0.083], [0.275, 0.107, 0.071], [0.3, 0.06, 0.05]]

# ------------------------------------------------------------------ primitives

static func cyl(b: MeshBuilder, a: Vector3, c: Vector3, r0: float, r1: float, col: Color, seg := 10, zs := 1.0) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r0; m.top_radius = r1; m.height = 1.0
	m.radial_segments = seg; m.rings = 1
	var d := c - a
	var y := d.normalized()
	var x := y.cross(Vector3(0, 0, 1))
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3(1, 0, 0))
	x = x.normalized()
	var z := x.cross(y).normalized()
	b.prim(m, Transform3D(Basis(x, y * d.length(), z * zs), (a + c) * 0.5), col)

static func sph(b: MeshBuilder, c: Vector3, r: Vector3, col: Color, seg := 10, rings := 6, basis := Basis.IDENTITY) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0; m.height = 2.0; m.radial_segments = seg; m.rings = rings
	b.prim(m, Transform3D(basis * Basis.from_scale(r), c), col)

static func hemi(b: MeshBuilder, c: Vector3, r: Vector3, col: Color, basis: Basis, seg := 14, rings := 6) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0; m.height = 1.0; m.is_hemisphere = true; m.radial_segments = seg; m.rings = rings
	b.prim(m, Transform3D(basis * Basis.from_scale(r), c), col)

static func box(b: MeshBuilder, c: Vector3, s: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	b.prim(BoxMesh.new(), Transform3D(basis * Basis.from_scale(s), c), col)

static func flower(b: MeshBuilder, p: Vector3, n: Vector3, s: float, petal: Color, centre: Color) -> void:
	var z := n.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	var bs := Basis(x, y, z)
	for k in 5:
		var a := k * TAU / 5.0
		sph(b, p + bs * Vector3(cos(a), sin(a), 0) * s * 0.9, Vector3(s * 0.75, s * 0.75, s * 0.25), petal, 6, 3, bs)
	sph(b, p + z * s * 0.15, Vector3(s * 0.45, s * 0.45, s * 0.3), centre, 6, 3, bs)

# ------------------------------------------------------------------ face decals

## front surface of the head (skull + jaw ellipsoids), head space
static func face_z(x: float, y: float) -> float:
	var s := 1.0 - pow(x / 0.152, 2.0) - pow((y - 0.15) / 0.145, 2.0)
	var zs := -0.145 * sqrt(maxf(s, 0.0)) if s > 0.0 else 0.0
	var j := 1.0 - pow(x / 0.132, 2.0) - pow((y - 0.088) / 0.088, 2.0)
	var zj := -0.022 - 0.122 * sqrt(maxf(j, 0.0)) if j > 0.0 else 0.0
	return minf(zs, zj)

static func _fp(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, p.y, face_z(p.x, p.y) - lift)

## convex polygon painted onto the face
static func decal(b: MeshBuilder, pts: Array, col: Color, lift := 0.003) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var cc := _fp(c, lift)
	for i in pts.size():
		var a := _fp(pts[i], lift)
		var bb := _fp(pts[(i + 1) % pts.size()], lift)
		b.face(cc, a, bb, col, col, col, Vector3(0, 0, -1))

## thick curved stroke (closed eyes, sleepy mouth)
static func stroke(b: MeshBuilder, cx: float, cy: float, rx: float, ry: float, th: float, a0: float, a1: float, col: Color, n := 8) -> void:
	for i in n:
		var u0 := lerpf(a0, a1, float(i) / n)
		var u1 := lerpf(a0, a1, float(i + 1) / n)
		var p0 := Vector2(cx + cos(u0) * rx, cy + sin(u0) * ry)
		var p1 := Vector2(cx + cos(u1) * rx, cy + sin(u1) * ry)
		var d0 := Vector2(cos(u0), sin(u0) * rx / maxf(ry, 0.001)).normalized() * th * 0.5
		var d1 := Vector2(cos(u1), sin(u1) * rx / maxf(ry, 0.001)).normalized() * th * 0.5
		decal(b, [p0 - d0, p1 - d1, p1 + d1, p0 + d0], col, 0.004)

static func d_shape(cx: float, top: float, w: float, h: float, n := 10) -> Array:
	var pts := [Vector2(cx + w * 0.5, top)]
	for i in range(1, n):
		var a := PI * float(i) / n
		pts.append(Vector2(cx + cos(a) * w * 0.5, top - sin(a) * h))
	pts.append(Vector2(cx - w * 0.5, top))
	return pts

static func ellipse(cx: float, cy: float, rx: float, ry: float, n := 12) -> Array:
	var pts := []
	for i in n:
		var a := TAU * float(i) / n
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

# ------------------------------------------------------------------ torso / vest

static func prof(y: float) -> Vector2:
	if y <= PROF[0][0]:
		return Vector2(PROF[0][1], PROF[0][2])
	for i in range(1, PROF.size()):
		if y <= PROF[i][0]:
			var k: float = (y - PROF[i - 1][0]) / (PROF[i][0] - PROF[i - 1][0])
			return Vector2(lerpf(PROF[i - 1][1], PROF[i][1], k), lerpf(PROF[i - 1][2], PROF[i][2], k))
	var l: Array = PROF[PROF.size() - 1]
	return Vector2(l[1], l[2])

static func body_pt(a: float, y: float, off: float) -> Vector3:
	var r := prof(y)
	return Vector3(sin(a) * (r.x + off), y, -cos(a) * (r.y + off))

## loft of the bare body between y0..y1 (full ring)
static func loft(b: MeshBuilder, y0: float, y1: float, rows: int, seg: int, col: Color, off := 0.0) -> void:
	for j in rows:
		var ya := lerpf(y0, y1, float(j) / rows)
		var yb := lerpf(y0, y1, float(j + 1) / rows)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p00 := body_pt(a0, ya, off); var p01 := body_pt(a1, ya, off)
			var p10 := body_pt(a0, yb, off); var p11 := body_pt(a1, yb, off)
			var n := Vector3(sin(a0 + PI / seg), 0, -cos(a0 + PI / seg))
			b.face(p00, p10, p11, col, col, col, n)
			b.face(p00, p11, p01, col, col, col, n)

## point on the open vest: u runs from the right front edge (0) around the back to the left front edge (1)
static func vest_pt(u: float, t: float, off: float) -> Vector3:
	var yy := lerpf(-0.05, 0.28, t)
	var op := lerpf(0.09, 0.8, smoothstep(0.0, 0.27, yy))
	var a := lerpf(op, TAU - op, u)
	var d := minf(absf(a - PI * 0.5), absf(a - PI * 1.5))
	var bump := 1.0 - smoothstep(0.3, 0.85, d)
	var ytop := 0.286 - 0.13 * bump
	var ybot := -0.055 + 0.007 * sin(a * 5.0 + 1.3) + 0.004 * sin(a * 11.0)
	var y := lerpf(ybot, ytop, t)
	var flare := 0.026 * (1.0 - smoothstep(0.0, 0.11, y + 0.055))
	return body_pt(a, y, off + flare)

static func vest_panel(b: MeshBuilder, u0: float, u1: float, nu: int) -> void:
	var nt := 7
	var outer := 0.016
	var inner := 0.009
	for i in nu:
		var ua := lerpf(u0, u1, float(i) / nu)
		var ub := lerpf(u0, u1, float(i + 1) / nu)
		for j in nt:
			var ta := float(j) / nt
			var tb := float(j + 1) / nt
			var col := RED if (i + j) % 3 != 0 else RED.darkened(0.04)
			var o00 := vest_pt(ua, ta, outer); var o10 := vest_pt(ub, ta, outer)
			var o01 := vest_pt(ua, tb, outer); var o11 := vest_pt(ub, tb, outer)
			var n := Vector3(o00.x + o11.x, 0, o00.z + o11.z)
			b.face(o00, o10, o11, col, col, col, n)
			b.face(o00, o11, o01, col, col, col, n)
			var i00 := vest_pt(ua, ta, inner); var i10 := vest_pt(ub, ta, inner)
			var i01 := vest_pt(ua, tb, inner); var i11 := vest_pt(ub, tb, inner)
			b.face(i00, i10, i11, RED_D, RED_D, RED_D, -n)
			b.face(i00, i11, i01, RED_D, RED_D, RED_D, -n)
		# piping on the bottom hem and the top (neckline / armholes / straps)
		for tt in [0.0, 1.0]:
			var a0 := vest_pt(ua, tt, outer); var a1 := vest_pt(ub, tt, outer)
			var b0 := vest_pt(ua, tt, inner - 0.002); var b1 := vest_pt(ub, tt, inner - 0.002)
			var up := Vector3(0, 1 if tt > 0.5 else -1, 0)
			b.face(a0, a1, b1, TRIM, TRIM, TRIM, up)
			b.face(a0, b1, b0, TRIM, TRIM, TRIM, up)
	# front edges (open vest) with piping
	for ue in [u0, u1]:
		if ue != 0.0 and ue != 1.0:
			continue
		for j in nt:
			var ta := float(j) / nt
			var tb := float(j + 1) / nt
			var a0 := vest_pt(ue, ta, outer); var a1 := vest_pt(ue, tb, outer)
			var b0 := vest_pt(ue, ta, inner - 0.002); var b1 := vest_pt(ue, tb, inner - 0.002)
			var side := Vector3(-1 if ue == 0.0 else 1, 0, -0.3)
			b.face(a0, a1, b1, TRIM, TRIM, TRIM, side)
			b.face(a0, b1, b0, TRIM, TRIM, TRIM, side)

static func vest_patch(b: MeshBuilder, u0: float, u1: float, t0: float, t1: float, col: Color, off: float) -> void:
	var p00 := vest_pt(u0, t0, off); var p10 := vest_pt(u1, t0, off)
	var p01 := vest_pt(u0, t1, off); var p11 := vest_pt(u1, t1, off)
	var n := Vector3(p00.x + p11.x, 0, p00.z + p11.z)
	b.face(p00, p10, p11, col, col, col, n)
	b.face(p00, p11, p01, col, col, col, n)

# ------------------------------------------------------------------ build all parts

static func build(boy: Boy) -> void:
	var b: MeshBuilder
	# ---- pelvis: board shorts
	b = MeshBuilder.new()
	cyl(b, Vector3(0, -0.07, 0), Vector3(0, 0.07, 0), 0.13, 0.125, YEL, 12, 0.78)
	cyl(b, Vector3(0, 0.05, 0), Vector3(0, 0.085, 0), 0.128, 0.127, YEL2, 12, 0.8)
	sph(b, Vector3(0, -0.065, 0.005), Vector3(0.125, 0.06, 0.097), YEL, 12, 5)
	for sx: int in [-1, 1]:
		box(b, Vector3(0.012 * sx, 0.045, -0.104), Vector3(0.006, 0.04, 0.006), TRIM, Basis(Vector3.BACK, 0.12 * sx))
	for k in 7:
		var a := -2.6 + k * 0.85
		var y := -0.035 + (k % 2) * 0.05
		flower(b, Vector3(sin(a) * 0.128, y, -cos(a) * 0.1), Vector3(sin(a), 0, -cos(a) * 1.25), 0.014, Color(1, 0.98, 0.92), Color(1, 0.42, 0.08))
	boy.add_part("pelvis", b)
	# ---- spine: white tank top (shaped chest/waist), skin shoulders + neck
	b = MeshBuilder.new()
	loft(b, -0.045, 0.255, 6, 14, TANK)
	loft(b, 0.255, 0.3, 2, 14, SKIN)
	cyl(b, Vector3(0, 0.27, 0), Vector3(0, 0.33, 0), 0.047, 0.044, SKIN, 8)
	for sx: int in [-1, 1]:
		sph(b, Vector3(0.12 * sx, 0.258, 0), Vector3(0.042, 0.042, 0.042), SKIN, 8, 5)
	# tiny surf-wave print on the tank (shows in the V of the vest)
	sph(b, Vector3(0.0, 0.17, -0.093), Vector3(0.022, 0.016, 0.006), Color(0.2, 0.62, 0.92), 8, 3)
	sph(b, Vector3(0.006, 0.175, -0.097), Vector3(0.012, 0.008, 0.005), TRIM, 8, 3)
	# back panel of the vest (static, follows the spine)
	vest_panel(b, 0.24, 0.76, 12)
	boy.add_part("spine", b)
	# ---- vest front flaps (swing a little with the body)
	for side in ["r", "l"]:
		b = MeshBuilder.new()
		var u0 := 0.0 if side == "r" else 0.76
		var u1 := 0.24 if side == "r" else 1.0
		vest_panel(b, u0, u1, 6)
		# patch pocket with a white top seam
		var pu0 := 0.055 if side == "r" else 0.85
		var pu1 := 0.15 if side == "r" else 0.945
		vest_patch(b, pu0, pu1, 0.16, 0.38, RED.darkened(0.12), 0.0175)
		vest_patch(b, pu0, pu1, 0.36, 0.4, TRIM, 0.018)
		if side == "r":
			for k in 3:
				var bp := vest_pt(0.018, 0.25 + k * 0.2, 0.019)
				sph(b, bp, Vector3(0.008, 0.008, 0.005), Color(1.0, 0.84, 0.25), 6, 3)
		boy.add_part("vest_" + side, b)
	# ---- head (origin at the neck top; head centre at y 0.15)
	b = MeshBuilder.new()
	sph(b, Vector3(0, 0.15, 0), Vector3(0.152, 0.145, 0.145), SKIN, 16, 10)
	sph(b, Vector3(0, 0.088, -0.022), Vector3(0.132, 0.088, 0.122), SKIN, 10, 6)   # broader, squarer jaw
	sph(b, Vector3(0, 0.045, -0.085), Vector3(0.05, 0.03, 0.045), SKIN, 8, 4)      # chin
	for sx: int in [-1, 1]:
		sph(b, Vector3(0.152 * sx, 0.128, 0.006), Vector3(0.027, 0.045, 0.03), SKIN, 8, 5)
		sph(b, Vector3(0.162 * sx, 0.128, 0.0), Vector3(0.012, 0.026, 0.014), SKIN_D, 6, 3)
		# thick, slightly frowning-in brows
		var bx := 0.058 * sx
		box(b, Vector3(bx, 0.206, face_z(bx, 0.206) - 0.004), Vector3(0.046, 0.014, 0.012), HAIR, Basis(Vector3.UP, -0.4 * sx) * Basis(Vector3.BACK, 0.2 * sx))
		# freckles
		for k in 3:
			var fx := (0.06 + k * 0.014) * sx
			var fy := 0.112 + (k % 2) * 0.008
			sph(b, Vector3(fx, fy, face_z(fx, fy) - 0.002), Vector3(0.0045, 0.0045, 0.002), Color(0.62, 0.38, 0.24), 6, 3, Basis(Vector3.UP, -0.5 * sx))
	sph(b, Vector3(0, 0.12, -0.146), Vector3(0.016, 0.013, 0.014), SKIN.darkened(0.08), 8, 4)   # button nose
	# band-aid on the left cheek
	var ba := Basis(Vector3.UP, 0.55) * Basis(Vector3.BACK, 0.45)
	box(b, Vector3(-0.082, 0.098, face_z(-0.082, 0.098) - 0.004), Vector3(0.042, 0.014, 0.006), Color(0.96, 0.86, 0.68), ba)
	box(b, Vector3(-0.082, 0.098, face_z(-0.082, 0.098) - 0.0065), Vector3(0.014, 0.012, 0.004), Color(0.92, 0.72, 0.55), ba)
	# short boy hair: a close cap whose rim sits high at the front and low at the nape
	hemi(b, Vector3(0, 0.168, 0.006), Vector3(0.158, 0.15, 0.156), HAIR, Basis(Vector3.RIGHT, 0.5), 16, 6)
	# spiky fringe poking out under the brim
	for k in 7:
		var a := -0.78 + k * 0.26
		var base := Vector3(sin(a) * 0.15, 0.232 - absf(a) * 0.01, -cos(a) * 0.142)
		var ln := 0.048 + 0.012 * float((k * 5) % 3) - absf(a) * 0.01
		var tip := base + Vector3(sin(a) * 0.012 + (0.008 if k % 2 == 0 else -0.006), -ln, -0.024)
		cyl(b, base, tip, 0.021, 0.002, HAIR, 5)
	# short sideburns + nape spikes
	for sx: int in [-1, 1]:
		cyl(b, Vector3(0.143 * sx, 0.19, -0.035), Vector3(0.147 * sx, 0.148, -0.04), 0.016, 0.003, HAIR, 5)
		cyl(b, Vector3(0.12 * sx, 0.2, 0.08), Vector3(0.135 * sx, 0.16, 0.1), 0.02, 0.003, HAIR, 5)
	for k in 4:
		var a := PI - 0.6 + k * 0.4
		var base := Vector3(sin(a) * 0.14, 0.13, -cos(a) * 0.135)
		cyl(b, base, base + Vector3(sin(a) * 0.01, -0.04, -cos(a) * 0.02), 0.019, 0.002, HAIR, 5)
	boy.add_part("head", b)
	# ---- eyes (open, blinkable): big glossy eyes, centred at the origin of the part
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		var eb := Basis(Vector3.UP, -0.38 * sx)
		sph(b, Vector3(0.058 * sx, 0.0, 0.0), Vector3(0.024, 0.031, 0.012), INK, 10, 6, eb)
		sph(b, Vector3(0.058 * sx + 0.008, 0.011, -0.01), Vector3(0.008, 0.008, 0.004), Color(1, 1, 1), 6, 3, eb)
		sph(b, Vector3(0.058 * sx - 0.006, -0.011, -0.01), Vector3(0.004, 0.004, 0.003), Color(1, 1, 1), 6, 3, eb)
	boy.add_part("eyes", b)
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		stroke(b, 0.058 * sx, 0.162, 0.024, 0.012, 0.009, PI + 0.15, TAU - 0.15, INK)   # sleepy closed eyes
	boy.add_part("eyes_closed", b)
	# ---- mouths
	b = MeshBuilder.new()   # big cheeky grin with teeth
	decal(b, d_shape(0.0, 0.086, 0.066, 0.03), MOUTH)
	decal(b, [Vector2(-0.029, 0.086), Vector2(0.029, 0.086), Vector2(0.024, 0.076), Vector2(-0.024, 0.076)], TRIM, 0.0045)
	decal(b, ellipse(0.0, 0.063, 0.015, 0.007, 10), TONGUE, 0.0045)
	boy.add_part("mouth_smile", b)
	b = MeshBuilder.new()   # gritted teeth (effort)
	decal(b, [Vector2(-0.036, 0.09), Vector2(0.036, 0.09), Vector2(0.032, 0.066), Vector2(-0.032, 0.066)], MOUTH)
	decal(b, [Vector2(-0.031, 0.086), Vector2(0.031, 0.086), Vector2(0.028, 0.07), Vector2(-0.028, 0.07)], TRIM, 0.0045)
	decal(b, [Vector2(-0.03, 0.0785), Vector2(0.03, 0.0785), Vector2(0.03, 0.0775), Vector2(-0.03, 0.0775)], INK, 0.006)
	for k in 3:
		var x := -0.015 + k * 0.015
		decal(b, [Vector2(x - 0.0008, 0.086), Vector2(x + 0.0008, 0.086), Vector2(x + 0.0008, 0.07), Vector2(x - 0.0008, 0.07)], INK, 0.006)
	boy.add_part("mouth_grit", b)
	b = MeshBuilder.new()   # wide laugh
	decal(b, d_shape(0.0, 0.09, 0.08, 0.045), MOUTH)
	decal(b, [Vector2(-0.034, 0.09), Vector2(0.034, 0.09), Vector2(0.029, 0.08), Vector2(-0.029, 0.08)], TRIM, 0.0045)
	decal(b, ellipse(0.0, 0.06, 0.02, 0.01, 10), TONGUE, 0.0045)
	boy.add_part("mouth_laugh", b)
	b = MeshBuilder.new()   # sleepy content smile
	stroke(b, 0.0, 0.084, 0.022, 0.01, 0.007, PI + 0.3, TAU - 0.3, MOUTH)
	boy.add_part("mouth_sleep", b)
	b = MeshBuilder.new()   # "oh no" o-mouth
	decal(b, ellipse(0.0, 0.07, 0.016, 0.019, 12), MOUTH)
	boy.add_part("mouth_oops", b)
	# ---- sunglasses (sunbathing)
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		var gx := 0.058 * sx
		sph(b, Vector3(gx, 0.158, face_z(gx, 0.158) - 0.012), Vector3(0.036, 0.026, 0.008), Color(0.05, 0.06, 0.09), 10, 4, Basis(Vector3.UP, -0.38 * sx))
		box(b, Vector3(0.135 * sx, 0.163, -0.065), Vector3(0.006, 0.008, 0.13), INK, Basis(Vector3.UP, -0.25 * sx))
	box(b, Vector3(0, 0.166, face_z(0.0, 0.166) - 0.012), Vector3(0.04, 0.007, 0.006), INK)
	boy.add_part("glasses", b)
	# ---- straw hat
	b = MeshBuilder.new()
	cyl(b, Vector3(0, -0.005, 0), Vector3(0, 0.08, 0), 0.152, 0.13, STRAW, 16)
	sph(b, Vector3(0, 0.08, 0), Vector3(0.13, 0.035, 0.13), STRAW, 16, 4)
	cyl(b, Vector3(0, 0.0, 0), Vector3(0, 0.03, 0), 0.155, 0.151, Color(0.82, 0.14, 0.1), 16)
	box(b, Vector3(0.13, 0.016, -0.08), Vector3(0.03, 0.04, 0.01), Color(0.82, 0.14, 0.1), Basis(Vector3.UP, 1.0))
	for k in 16:
		var a0 := k * TAU / 16.0
		var col := STRAW2 if k % 2 == 0 else STRAW.lightened(0.05)
		box(b, Vector3(sin(a0) * 0.142, 0.055, cos(a0) * 0.142), Vector3(0.012, 0.03, 0.004), col, Basis(Vector3.UP, a0))
	var seg := 32
	var rings := [0.145, 0.19, 0.235, 0.275]
	for ri in 3:
		for k in seg:
			var a0 := k * TAU / seg
			var a1 := (k + 1) * TAU / seg
			var r0: float = rings[ri]
			var r1: float = rings[ri + 1]
			var y0 := -0.03 * pow((r0 - 0.145) / 0.13, 2.0)
			var y1 := -0.03 * pow((r1 - 0.145) / 0.13, 2.0)
			var p00 := Vector3(sin(a0) * r0, y0, cos(a0) * r0)
			var p01 := Vector3(sin(a1) * r0, y0, cos(a1) * r0)
			var p10 := Vector3(sin(a0) * r1, y1, cos(a0) * r1)
			var p11 := Vector3(sin(a1) * r1, y1, cos(a1) * r1)
			var col := STRAW if (k + ri) % 2 == 0 else STRAW2
			b.face(p00, p10, p11, col, col, col, Vector3.UP)
			b.face(p00, p11, p01, col, col, col, Vector3.UP)
			var d := Vector3(0, -0.009, 0)
			var cu := col.darkened(0.1)
			b.face(p00 + d, p10 + d, p11 + d, cu, cu, cu, Vector3.DOWN)
			b.face(p00 + d, p11 + d, p01 + d, cu, cu, cu, Vector3.DOWN)
			if ri == 2:
				b.face(p10, p10 + d, p11 + d, cu, cu, cu, Vector3(p10.x, 0, p10.z))
				b.face(p10, p11 + d, p11, cu, cu, cu, Vector3(p10.x, 0, p10.z))
	boy.add_part("hat", b)
	# ---- arms
	for key: String in ["r", "l"]:
		b = MeshBuilder.new()
		cyl(b, Vector3(0, 0.0, 0), Vector3(0, -Boy.UARM, 0), 0.037, 0.031, SKIN, 8)
		sph(b, Vector3(0, -Boy.UARM, 0), Vector3(0.031, 0.031, 0.031), SKIN, 8, 4)
		boy.add_part("uarm_" + key, b)
		b = MeshBuilder.new()
		cyl(b, Vector3(0, 0.0, 0), Vector3(0, -Boy.FARM, 0), 0.031, 0.026, SKIN, 8)
		boy.add_part("farm_" + key, b)
		b = MeshBuilder.new()
		var sx := 1.0 if key == "r" else -1.0
		sph(b, Vector3(0, -0.04, 0), Vector3(0.03, 0.042, 0.027), SKIN, 8, 5)
		sph(b, Vector3(-0.022 * sx, -0.03, -0.014), Vector3(0.011, 0.024, 0.011), SKIN, 6, 3, Basis(Vector3.BACK, 0.5 * sx))
		boy.add_part("hand_" + key, b)
	# ---- legs
	for key: String in ["r", "l"]:
		b = MeshBuilder.new()
		cyl(b, Vector3(0, 0.03, 0), Vector3(0, -0.135, 0), 0.07, 0.064, YEL, 10)
		cyl(b, Vector3(0, -0.125, 0), Vector3(0, -0.142, 0), 0.066, 0.066, YEL2, 10)
		var sx := 1.0 if key == "r" else -1.0
		for k in 3:
			var a := (0.6 + k * 1.7) * sx
			flower(b, Vector3(sin(a) * 0.068, -0.03 - k * 0.035, -cos(a) * 0.068), Vector3(sin(a), 0, -cos(a)), 0.013, Color(1, 0.98, 0.92), Color(1, 0.42, 0.08))
		cyl(b, Vector3(0, -0.12, 0), Vector3(0, -Boy.THIGH, 0), 0.05, 0.044, SKIN, 8)
		sph(b, Vector3(0, -Boy.THIGH, -0.004), Vector3(0.045, 0.045, 0.045), SKIN, 8, 4)
		boy.add_part("thigh_" + key, b)
		b = MeshBuilder.new()
		cyl(b, Vector3(0, 0.0, 0), Vector3(0, -Boy.SHIN, 0), 0.043, 0.03, SKIN, 8)
		sph(b, Vector3(0, -0.075, 0.01), Vector3(0.044, 0.07, 0.045), SKIN, 8, 5)
		boy.add_part("shin_" + key, b)
		b = MeshBuilder.new()
		sph(b, Vector3(0, -0.005, 0), Vector3(0.03, 0.03, 0.03), SKIN, 8, 4)
		sph(b, Vector3(0, -0.035, -0.035), Vector3(0.04, 0.026, 0.082), SKIN, 10, 5)
		for k in 4:
			sph(b, Vector3((-0.024 + k * 0.016) * sx, -0.042, -0.107 + absf(k - 1.2) * 0.004), Vector3(0.009, 0.009, 0.011), SKIN, 6, 3)
		box(b, Vector3(0, -Boy.ANKLE_H + 0.006, -0.03), Vector3(0.08, 0.012, 0.2), SOLE)
		box(b, Vector3(0, -Boy.ANKLE_H, -0.03), Vector3(0.082, 0.005, 0.202), Color(0.95, 0.95, 0.9))
		for s2: int in [-1, 1]:
			box(b, Vector3(0.02 * s2, -0.04, -0.055), Vector3(0.008, 0.01, 0.065), Color(0.95, 0.25, 0.2), Basis(Vector3.UP, 0.55 * s2))
		boy.add_part("foot_" + key, b)
	# ---- the flat skipping stone in the right hand
	b = MeshBuilder.new()
	var srng := RandomNumberGenerator.new()
	srng.seed = 3
	var sm := SphereMesh.new()
	sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 9; sm.rings = 4
	b.prim(sm, Transform3D(Basis.from_scale(Vector3(0.05, 0.017, 0.04)), Vector3.ZERO), Color(0.5, 0.52, 0.55), srng, 0.12, 0.04)
	boy.add_part("stone", b)
