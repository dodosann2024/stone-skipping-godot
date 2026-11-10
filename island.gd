class_name Island
extends Node3D
## Procedurally builds the whole little tropical island, its dock and the sea around it.
## Static props are merged into a handful of meshes to keep draw calls low on mobile.

const DECK_Y := 0.8
var R0 := 0.0
var dock_start_z := 0.0
var dock_end_z := 0.0
var player_spot := Vector3.ZERO
var cam_blockers: Array = []
var walk_blockers: Array = []   # [Vector2 centre, radius] extra things the boy can't walk through
var hammock_a := Vector3.ZERO
var hammock_b := Vector3.ZERO
var hammock_node: Node3D
var towel_pos := Vector3.ZERO
var towel_dir := Vector3.FORWARD   # towel long axis, pointing out to sea (feet end)
var umbrella_pos := Vector3.ZERO
var hut_pos := Vector3.ZERO
var lighthouse_pos := Vector3.ZERO
var campfire_pos := Vector3.ZERO
var obstacles: Array = []   # [Vector2 centre, radius, top_y, name]
var palm_spots: Array = []  # crowns, for screenshots
var trunks: Array = []   # palm trunk polylines (camera line-of-sight checks)
var water_mat: ShaderMaterial
var terrain_mat: ShaderMaterial
var foliage_mat: ShaderMaterial
var static_mat: ShaderMaterial
var buoys: Array[Node3D] = []
var ui_font: Font

var rng := RandomNumberGenerator.new()
var SB: MeshBuilder   # static, lit
var FB: MeshBuilder   # foliage (wind sway)
var GB: MeshBuilder   # glowing lantern bits
var CB: MeshBuilder   # clouds
var prim_cache := {}
var paths: Array = []

# ------------------------------------------------------------------ shape

static func island_R(th: float) -> float:
	return 19.0 + 2.2 * sin(2.0 * th + 0.6) + 1.6 * sin(3.0 * th + 1.9) + 0.9 * sin(5.0 * th + 0.3)

static func shore_d(x: float, z: float) -> float:
	return Vector2(x, z).length() - island_R(atan2(z, x))

static func ground_h(x: float, z: float) -> float:
	var d = shore_d(x, z)
	var n = 0.07 * sin(x * 0.9 + z * 0.4) + 0.05 * cos(z * 1.3 - x * 0.5) + 0.04 * sin(x * 2.1 - z * 1.7)
	if d > 0.0:
		return -(clamp(d * 0.17, 0.0, 1.7) + smoothstep(13.0, 26.0, d) * 4.0) + n * 0.6
	var beach = 0.9 * smoothstep(0.0, 6.0, -d)
	var hill = 4.0 * exp(-(pow(x - 2.0, 2) + pow(z - 3.0, 2)) / (2.0 * 6.5 * 6.5))
	var hill2 = 1.5 * exp(-(pow(x + 8.0, 2) + pow(z - 8.0, 2)) / (2.0 * 4.0 * 4.0))
	return beach + (hill + hill2) * smoothstep(1.0, 8.0, -d) + n * (0.6 + 0.4 * smoothstep(0.0, 3.0, -d))

static func dir_at(th: float) -> Vector3:
	return Vector3(cos(th), 0.0, sin(th))

# ---- beach wash, mirrored from shaders/common.gdshaderinc + terrain.gdshader (keep in sync)

static func _fract(x: float) -> float:
	return x - floorf(x)

static func hash12(x: float, y: float) -> float:
	var a := _fract(x * 0.1031)
	var b := _fract(y * 0.1031)
	var c := a
	var d := a * (b + 33.33) + b * (c + 33.33) + c * (a + 33.33)
	a += d; b += d; c += d
	return _fract((a + b) * c)

static func vnoise(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(hash12(ix, iy), hash12(ix + 1.0, iy), ux), lerpf(hash12(ix, iy + 1.0), hash12(ix + 1.0, iy + 1.0), ux), uy)

static func sea_y(x: float, z: float, t: float) -> float:
	return 0.03 * sin((0.82 * x + 0.57 * z) * 0.5 + t * 0.9) + 0.02 * sin((-0.45 * x + 0.89 * z) * 0.8 + t * 1.2)

static func ground_near(x: float, z: float, d: float) -> float:
	var n := 0.07 * sin(x * 0.9 + z * 0.4) + 0.05 * cos(z * 1.3 - x * 0.5) + 0.04 * sin(x * 2.1 - z * 1.7)
	if d > 0.0:
		return -(clampf(d * 0.17, 0.0, 1.7) + smoothstep(13.0, 26.0, d) * 4.0) + n * 0.6
	return 0.9 * smoothstep(0.0, 6.0, -d) + n * (0.6 + 0.4 * smoothstep(0.0, 3.0, -d))

static func wash_cycle(x: float, z: float, t: float) -> float:
	return _fract(t * 0.105 + vnoise(x * 0.18, z * 0.18) * 0.6 + atan2(z, x) * (6.0 / TAU))

static func runup(c: float) -> float:
	return 0.07 * smoothstep(0.0, 0.26, c) * (1.0 - smoothstep(0.26, 0.9, c))

## true while the swash film (sea or the wash running up the beach) covers the sand at (x, z)
static func wash_covers(x: float, z: float, t: float) -> bool:
	var d := shore_d(x, z)
	if d < -4.0:
		return false
	var gy := lerpf(ground_near(x, z, d), ground_h(x, z), smoothstep(0.5, 2.5, absf(d + 0.3)))
	var hab := gy - sea_y(x, z, t)
	var ru := runup(wash_cycle(x, z, t)) + (vnoise(x * 1.1 + t * 0.08, z * 1.3) - 0.5) * 0.02
	return hab < ru + 0.002

func shore_pt(th: float, inset: float) -> Vector3:
	var p = dir_at(th) * (island_R(th) - inset)
	return Vector3(p.x, ground_h(p.x, p.z), p.z)

func gp(x: float, z: float) -> Vector3:
	return Vector3(x, ground_h(x, z), z)

# ------------------------------------------------------------------ build

func build(font: Font) -> void:
	ui_font = font
	rng.seed = 7
	R0 = island_R(-PI / 2.0)
	dock_start_z = -(R0 - 3.2)
	dock_end_z = -(R0 + 13.5)
	player_spot = Vector3(0.0, DECK_Y, dock_end_z + 1.3)
	var hth = -2.3
	hut_pos = shore_pt(hth, 3.6)
	lighthouse_pos = gp(2.0, 3.0)
	campfire_pos = shore_pt(1.75, 5.0)
	SB = MeshBuilder.new()
	FB = MeshBuilder.new()
	GB = MeshBuilder.new()
	CB = MeshBuilder.new()
	_make_paths()
	_build_terrain()
	_build_dock()
	_build_hut(hth)
	_build_lighthouse()
	_build_campfire()
	_build_beach_life()
	_build_rocks_and_reef()
	_build_palms()
	_build_vegetation()
	_build_far()
	_build_buoys()
	_flush()
	_build_water()

func _flush() -> void:
	static_mat = ShaderMaterial.new()
	static_mat.shader = load("res://shaders/static.gdshader")
	_mi(SB.commit(), static_mat)
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	_mi(FB.commit(), foliage_mat)
	var gm = ShaderMaterial.new()
	gm.shader = load("res://shaders/sky_tint.gdshader")
	gm.set_shader_parameter("boost", 1.5)
	_mi(GB.commit(), gm).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cm = ShaderMaterial.new()
	cm.shader = load("res://shaders/sky_tint.gdshader")
	cm.set_shader_parameter("boost", 1.3)
	_mi(CB.commit(), cm).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi

func set_time(t: float) -> void:
	water_mat.set_shader_parameter("game_time", t)
	terrain_mat.set_shader_parameter("game_time", t)
	foliage_mat.set_shader_parameter("game_time", t)

# ------------------------------------------------------------------ primitives

func _cylm(top: float, bot: float, h: float, seg: int) -> CylinderMesh:
	var key = "c%.3f_%.3f_%.3f_%d" % [top, bot, h, seg]
	if not prim_cache.has(key):
		var c = CylinderMesh.new()
		c.top_radius = top; c.bottom_radius = bot; c.height = h
		c.radial_segments = seg; c.rings = 1
		prim_cache[key] = c
	return prim_cache[key]

func _boxm() -> BoxMesh:
	if not prim_cache.has("box"):
		prim_cache["box"] = BoxMesh.new()
	return prim_cache["box"]

func _sphm(seg: int, rings: int) -> SphereMesh:
	var key = "s%d_%d" % [seg, rings]
	if not prim_cache.has(key):
		var s = SphereMesh.new()
		s.radius = 1.0; s.height = 2.0; s.radial_segments = seg; s.rings = rings
		prim_cache[key] = s
	return prim_cache[key]

func box(b: MeshBuilder, size: Vector3, pos: Vector3, rot: Vector3, col: Color, cv := 0.0) -> void:
	b.prim(_boxm(), Transform3D(Basis.from_euler(rot).scaled(size), pos), col, rng, 0.0, cv)

func boxb(b: MeshBuilder, size: Vector3, xf: Transform3D, col: Color, cv := 0.0) -> void:
	b.prim(_boxm(), xf * Transform3D(Basis.IDENTITY.scaled(size), Vector3.ZERO), col, rng, 0.0, cv)

func cyl(b: MeshBuilder, top: float, bot: float, h: float, seg: int, pos: Vector3, rot: Vector3, col: Color) -> void:
	b.prim(_cylm(top, bot, h, seg), Transform3D(Basis.from_euler(rot), pos), col)

func blob(b: MeshBuilder, pos: Vector3, scl: Vector3, col: Color, jitter := 0.22, seg := 7, rings := 4, cv := 0.03, sway := -1.0) -> void:
	b.prim(_sphm(seg, rings), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(scl), pos), col, rng, jitter, cv, sway)

## Tapered tube between two points (manual, flat shaded), with sway weights.
func tube(b: MeshBuilder, p0: Vector3, p1: Vector3, r0: float, r1: float, seg: int, col: Color, sw0 := 1.0, sw1 := 1.0, col1 = null) -> void:
	var ax = (p1 - p0).normalized()
	var ref = Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT
	var u = ax.cross(ref).normalized()
	var v = ax.cross(u)
	var ct: Color = col if col1 == null else col1
	for i in seg:
		var a0 = TAU * i / seg
		var a1 = TAU * (i + 1) / seg
		var d0 = u * cos(a0) + v * sin(a0)
		var d1 = u * cos(a1) + v * sin(a1)
		var out = (d0 + d1).normalized()
		var A = p0 + d0 * r0
		var B = p0 + d1 * r0
		var C = p1 + d1 * r1
		var D = p1 + d0 * r1
		b.face(A, B, C, Color(col, sw0), Color(col, sw0), Color(ct, sw1), out)
		b.face(A, C, D, Color(col, sw0), Color(ct, sw1), Color(ct, sw1), out)
	# top cap
	if r1 > 0.02:
		for i in seg:
			var a0 = TAU * i / seg
			var a1 = TAU * (i + 1) / seg
			b.face(p1, p1 + (u * cos(a0) + v * sin(a0)) * r1, p1 + (u * cos(a1) + v * sin(a1)) * r1, Color(ct, sw1), Color(ct, sw1), Color(ct, sw1), ax)

# ------------------------------------------------------------------ paths & terrain

func _make_paths() -> void:
	var base = Vector3(0.0, 0.0, dock_start_z + 1.0)
	var hut_front = hut_pos + (Vector3(0, 0, 0) - hut_pos).normalized() * -2.8
	paths = [
		[Vector2(base.x, base.z), Vector2(-3.5, base.z + 2.6), Vector2(-7.5, base.z + 3.2), Vector2(hut_front.x, hut_front.z)],
		[Vector2(base.x, base.z), Vector2(2.6, -9.5), Vector2(4.6, -5.0), Vector2(4.2, -0.8), Vector2(2.6, 1.6)],
		[Vector2(1.6, 4.4), Vector2(0.5, 8.0), Vector2(campfire_pos.x * 0.85, campfire_pos.z * 0.85)],
	]

func path_dist(x: float, z: float) -> float:
	var p = Vector2(x, z)
	var best = 999.0
	for pl in paths:
		for i in range(pl.size() - 1):
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var ab = b - a
			var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = min(best, (a + ab * t - p).length())
	return best

func _ground_color(x: float, z: float, h: float) -> Color:
	var d = shore_d(x, z)
	var n1 = sin(x * 0.37 + z * 0.21) * 0.5 + sin(x * 0.11 - z * 0.43) * 0.5
	var sand = Color(0.93, 0.85, 0.66)
	var c: Color
	if d > 0.0:
		c = Color(0.92, 0.85, 0.67).lerp(Color(0.80, 0.78, 0.66), smoothstep(2.0, 14.0, d))
		# seagrass patches in the lagoon
		if d > 3.0 and d < 13.0 and n1 > 0.45:
			c = c.lerp(Color(0.46, 0.6, 0.36), smoothstep(0.45, 0.75, n1) * 0.8)
	else:
		c = sand
		var g = smoothstep(4.0, 7.0, -d + n1 * 1.5) * smoothstep(0.6, 1.2, h + n1 * 0.3)
		var grass = Color(0.45, 0.68, 0.3).lerp(Color(0.33, 0.57, 0.25), 0.5 + 0.5 * sin(x * 0.8 + z * 0.6))
		c = c.lerp(grass, g)
		var pd = path_dist(x, z)
		if pd < 1.1:
			c = c.lerp(Color(0.82, 0.7, 0.5), (1.0 - smoothstep(0.6, 1.1, pd)) * (0.6 + 0.4 * g))
	var v = rng.randf_range(-0.025, 0.025)
	return Color(c.r + v, c.g + v, c.b + v * 0.6)

func _build_terrain() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half = 58.0
	var step = 1.0
	var n = int(half * 2.0 / step)
	for j in n + 1:
		for i in n + 1:
			var x = -half + i * step
			var z = -half + j * step
			var h = ground_h(x, z)
			st.set_color(_ground_color(x, z, h))
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, h, z))
	for j in n:
		for i in n:
			var a = j * (n + 1) + i
			var b = a + 1
			var c = a + n + 1
			var d = c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals()
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	_mi(st.commit(), terrain_mat)
	# deep floor beyond the terrain patch
	var bed = PlaneMesh.new()
	bed.size = Vector2(1400, 1400)
	var bm = StandardMaterial3D.new()
	bm.albedo_color = Color(0.25, 0.42, 0.5)
	var bmi = _mi(bed, bm)
	bmi.position.y = -5.8

func _build_water() -> void:
	var pm = PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("obj_foam", _bake_obstacle_foam())
	var arr = PackedVector4Array()
	arr.resize(8)
	water_mat.set_shader_parameter("ripples", arr)
	var mi = _mi(pm, water_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _bake_obstacle_foam() -> ImageTexture:
	var size = 256
	var img = Image.create(size, size, false, Image.FORMAT_L8)
	img.fill(Color(1, 1, 1))
	var px = 128.0 / size  # metres per pixel
	var dist = PackedFloat32Array()
	dist.resize(size * size)
	dist.fill(3.0)
	for o in obstacles:
		var c: Vector2 = o[0]
		var r: float = o[1]
		var top: float = o[2]
		var bottom: float = o[4] if o.size() > 4 else -99.0
		if top < -0.1 or bottom > 0.15:
			continue
		var reach = r + 3.0
		var i0 = int((c.x - reach + 64.0) / px)
		var i1 = int((c.x + reach + 64.0) / px)
		var j0 = int((c.y - reach + 64.0) / px)
		var j1 = int((c.y + reach + 64.0) / px)
		for j in range(max(j0, 0), min(j1 + 1, size)):
			for i in range(max(i0, 0), min(i1 + 1, size)):
				var w = Vector2(i * px - 64.0 + px * 0.5, j * px - 64.0 + px * 0.5)
				var dd: float = max((w - c).length() - r, 0.0)
				var k = j * size + i
				if dd < dist[k]:
					dist[k] = dd
	for j in size:
		for i in size:
			var v: float = dist[j * size + i] / 3.0
			if v < 1.0:
				img.set_pixel(i, j, Color(v, v, v))
	return ImageTexture.create_from_image(img)

func add_obstacle(c: Vector2, r: float, top: float, name: String, bottom := -99.0) -> void:
	obstacles.append([c, r, top, name, bottom])

# ------------------------------------------------------------------ dock

func _wood(k := 0.0) -> Color:
	var base = Color(0.66, 0.47, 0.3)
	var v = rng.randf_range(-0.06, 0.06) + k
	return Color(base.r + v, base.g + v * 0.8, base.b + v * 0.6)

func _build_dock() -> void:
	var post_c = Color(0.42, 0.29, 0.18)
	var z = dock_start_z
	# planks
	while z > dock_end_z + 3.8:
		box(SB, Vector3(2.3, 0.08, 0.3), Vector3(rng.randf_range(-0.03, 0.03), DECK_Y, z), Vector3(0, rng.randf_range(-0.025, 0.025), 0), _wood())
		z -= 0.35
	# T-shaped platform at the end
	var pz = dock_end_z + 3.8
	while pz > dock_end_z:
		box(SB, Vector3(6.2, 0.08, 0.3), Vector3(0, DECK_Y, pz), Vector3(0, rng.randf_range(-0.012, 0.012), 0), _wood())
		pz -= 0.35
	# stringers + posts
	for sx in [-1.05, 1.05]:
		box(SB, Vector3(0.14, 0.16, absf(dock_end_z - dock_start_z)), Vector3(sx, DECK_Y - 0.12, (dock_start_z + dock_end_z) * 0.5), Vector3.ZERO, post_c)
	z = dock_start_z - 0.6
	var k = 0
	while z > dock_end_z + 3.5:
		for sx in [-1.2, 1.2]:
			var top = DECK_Y + (0.55 if k % 2 == 0 else 0.1)
			var g: float = min(ground_h(sx, z), 0.0)
			tube(SB, Vector3(sx, g - 0.3, z), Vector3(sx, top, z), 0.13, 0.12, 7, post_c.lerp(Color(0.3, 0.22, 0.15), rng.randf() * 0.4))
			add_obstacle(Vector2(sx, z), 0.16, top, "码头木桩", g - 0.3)
			if k % 2 == 0:
				cyl(SB, 0.15, 0.15, 0.06, 8, Vector3(sx, top + 0.02, z), Vector3.ZERO, Color(0.36, 0.25, 0.16))
		k += 1
		z -= 2.4
	for sx in [-3.0, -1.2, 1.2, 3.0]:
		for zz in [dock_end_z + 0.15, dock_end_z + 3.6]:
			var g2: float = ground_h(sx, zz)
			var top2 = DECK_Y + (0.7 if absf(sx) > 2.0 else 0.1)
			tube(SB, Vector3(sx, g2 - 0.3, zz), Vector3(sx, top2, zz), 0.14, 0.13, 7, post_c)
			add_obstacle(Vector2(sx, zz), 0.17, top2, "码头木桩", g2 - 0.3)
	# rope rail along the right side, sagging between posts
	var zr = dock_start_z - 0.6
	while zr - 4.8 > dock_end_z + 3.0:
		var a = Vector3(1.2, DECK_Y + 0.5, zr)
		var b = Vector3(1.2, DECK_Y + 0.5, zr - 4.8)
		var prev = a
		for s in range(1, 7):
			var t = s / 6.0
			var p = a.lerp(b, t) + Vector3(0, -0.22 * sin(PI * t), 0)
			tube(SB, prev, p, 0.025, 0.025, 4, Color(0.85, 0.75, 0.55))
			prev = p
		zr -= 4.8
	# lanterns on the platform corners (tall posts)
	for sx in [-3.0, 3.0]:
		var base = Vector3(sx, DECK_Y + 0.7, dock_end_z + 0.15)
		tube(SB, base, base + Vector3(0, 1.5, 0), 0.06, 0.05, 6, post_c)
		box(SB, Vector3(0.6, 0.05, 0.05), base + Vector3(0, 1.45, 0) + Vector3(-0.3 * signf(sx), 0, 0), Vector3.ZERO, post_c)
		var lp = base + Vector3(-0.55 * signf(sx), 1.15, 0)
		box(SB, Vector3(0.24, 0.04, 0.24), lp + Vector3(0, 0.2, 0), Vector3.ZERO, Color(0.2, 0.2, 0.22))
		box(SB, Vector3(0.24, 0.04, 0.24), lp + Vector3(0, -0.2, 0), Vector3.ZERO, Color(0.2, 0.2, 0.22))
		box(GB, Vector3(0.18, 0.34, 0.18), lp, Vector3.ZERO, Color(1.0, 0.82, 0.45))
	# crates, barrel, bucket, fishing rod, life ring on the platform
	var pc = Vector3(-2.3, DECK_Y + 0.04, dock_end_z + 2.9)
	# spheres the close throw camera must not pass through (crates, barrels, corner lanterns)
	cam_blockers = [
		[pc + Vector3(0.35, 0.5, 0.05), 0.95], [Vector3(2.45, DECK_Y + 0.5, dock_end_z + 2.6), 0.8],
		[Vector3(-2.6, DECK_Y + 1.85, dock_end_z + 0.15), 0.5], [Vector3(2.6, DECK_Y + 1.85, dock_end_z + 0.15), 0.5],
		[Vector3(-3.0, DECK_Y + 1.4, dock_end_z + 0.15), 0.35], [Vector3(3.0, DECK_Y + 1.4, dock_end_z + 0.15), 0.35],
	]
	walk_blockers.append([Vector2(pc.x + 0.35, pc.z + 0.05), 0.72])
	walk_blockers.append([Vector2(2.47, dock_end_z + 2.6), 0.62])
	walk_blockers.append([Vector2(1.8, dock_end_z + 3.3), 0.2])
	_crate(pc + Vector3(0, 0.3, 0), 0.6, 0.2)
	_crate(pc + Vector3(0.75, 0.25, 0.1), 0.5, -0.3)
	_crate(pc + Vector3(0.15, 0.85, 0.05), 0.48, 0.6)
	_barrel(Vector3(2.4, DECK_Y + 0.04, dock_end_z + 3.0))
	_barrel(Vector3(2.55, DECK_Y + 0.04, dock_end_z + 2.2))
	cyl(SB, 0.17, 0.13, 0.28, 8, Vector3(1.8, DECK_Y + 0.18, dock_end_z + 3.3), Vector3.ZERO, Color(0.35, 0.55, 0.75))
	tube(SB, Vector3(-1.6, DECK_Y + 0.05, dock_end_z + 3.3), Vector3(-2.7, DECK_Y + 2.6, dock_end_z + 3.6), 0.025, 0.012, 4, Color(0.25, 0.2, 0.15))
	tube(SB, Vector3(-2.7, DECK_Y + 2.6, dock_end_z + 3.6), Vector3(-2.75, DECK_Y + 0.6, dock_end_z + 3.9), 0.004, 0.004, 3, Color(0.9, 0.9, 0.9))
	var tor = TorusMesh.new()
	tor.inner_radius = 0.22; tor.outer_radius = 0.36; tor.rings = 12; tor.ring_segments = 6
	SB.prim(tor, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-3.0, DECK_Y + 0.4, dock_end_z + 0.02)), Color(0.95, 0.3, 0.25))
	# rowboat tied alongside
	_boat(Vector3(2.3, 0.05, (dock_start_z + dock_end_z) * 0.5 - 1.0), 0.06, Color(0.3, 0.6, 0.8))
	tube(SB, Vector3(1.2, DECK_Y + 0.5, (dock_start_z + dock_end_z) * 0.5 + 0.2), Vector3(2.1, 0.45, (dock_start_z + dock_end_z) * 0.5 + 0.4), 0.02, 0.02, 4, Color(0.85, 0.75, 0.55))
	# sign at the dock entrance
	var sp = Vector3(-1.6, ground_h(-1.6, dock_start_z + 1.6), dock_start_z + 1.6)
	tube(SB, sp, sp + Vector3(0, 1.7, 0), 0.06, 0.06, 6, post_c)
	box(SB, Vector3(1.5, 0.55, 0.06), sp + Vector3(0, 1.55, 0), Vector3(0, 0.15, 0), _wood(0.05))
	var lbl = Label3D.new()
	lbl.text = "打水漂码头"
	lbl.font = ui_font
	lbl.font_size = 64
	lbl.pixel_size = 0.0045
	lbl.modulate = Color(0.32, 0.18, 0.08)
	lbl.outline_size = 0
	add_child(lbl)
	lbl.position = sp + Vector3(0, 1.55, -0.05)
	lbl.rotation = Vector3(0, 0.15 + PI, 0)
	add_obstacle(Vector2(sp.x, sp.z), 0.4, sp.y + 1.8, "路牌")

func _crate(c: Vector3, s: float, yaw: float) -> void:
	var xf = Transform3D(Basis(Vector3.UP, yaw), c)
	boxb(SB, Vector3(s, s, s), xf, _wood(-0.05))
	var dark = Color(0.45, 0.31, 0.19)
	for e in [Vector3(0, s * 0.5, 0), Vector3(0, -s * 0.5, 0)]:
		for f in [Vector3(0, 0, s * 0.5), Vector3(0, 0, -s * 0.5)]:
			boxb(SB, Vector3(s * 1.02, s * 0.1, s * 0.1), xf * Transform3D(Basis.IDENTITY, (e + f) * 0.96), dark)
	boxb(SB, Vector3(s * 1.02, s * 0.1, s * 1.15), xf * Transform3D(Basis(Vector3.FORWARD, 0.78), Vector3.ZERO), dark)

func _barrel(p: Vector3) -> void:
	cyl(SB, 0.27, 0.27, 0.8, 9, p + Vector3(0, 0.4, 0), Vector3.ZERO, Color(0.55, 0.36, 0.2))
	for y in [0.12, 0.68]:
		cyl(SB, 0.285, 0.285, 0.06, 9, p + Vector3(0, y, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))
	cyl(SB, 0.3, 0.3, 0.09, 9, p + Vector3(0, 0.4, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))

func _boat(p: Vector3, yaw: float, stripe: Color, tilt := 0.0) -> void:
	var xf = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, tilt), p)
	var secs = 9
	var prof: Array = []
	for i in secs:
		var s = -1.0 + 2.0 * i / (secs - 1)
		var w = 0.62 * pow(max(1.0 - s * s, 0.0), 0.55) + 0.03
		var dp = 0.42 * (1.0 - 0.35 * s * s)
		var z = s * 1.7
		var rise = 0.12 * s * s
		prof.append([Vector3(-w, 0.18 + rise, z), Vector3(-w * 0.85, -dp * 0.45 + rise, z), Vector3(0, -dp + rise, z), Vector3(w * 0.85, -dp * 0.45 + rise, z), Vector3(w, 0.18 + rise, z)])
	var white = Color(0.95, 0.94, 0.9)
	var inner = Color(0.62, 0.45, 0.28)
	for i in secs - 1:
		for k in 4:
			var a: Vector3 = xf * prof[i][k]
			var b: Vector3 = xf * prof[i][k + 1]
			var c: Vector3 = xf * prof[i + 1][k + 1]
			var d: Vector3 = xf * prof[i + 1][k]
			var mid: Vector3 = (prof[i][k] + prof[i + 1][k + 1]) * 0.5
			var out = xf.basis * Vector3(mid.x, mid.y + 0.1, 0).normalized()
			var col = stripe if (k == 0 or k == 3) else white
			SB.face(a, b, c, col, col, col, out)
			SB.face(a, c, d, col, col, col, out)
			SB.face(a, b, c, inner, inner, inner, -out)
			SB.face(a, c, d, inner, inner, inner, -out)
	for sz in [-0.6, 0.5]:
		boxb(SB, Vector3(1.0, 0.05, 0.25), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.08, sz)), _wood())
	boxb(SB, Vector3(0.06, 0.04, 2.0), xf * Transform3D(Basis(Vector3.UP, 0.25), Vector3(0.2, 0.15, 0.0)), _wood(-0.1))
	add_obstacle(Vector2((xf * Vector3.ZERO).x, (xf * Vector3.ZERO).z), 0.9, p.y + 0.35, "小船")

# ------------------------------------------------------------------ hut

func _build_hut(th: float) -> void:
	var out = dir_at(th)
	var yaw = atan2(out.x, out.z)
	var base = hut_pos
	var xf = Transform3D(Basis(Vector3.UP, yaw), base)
	var post_c = Color(0.42, 0.29, 0.18)
	var floor_y = 1.25
	for px in [-1.8, 0.0, 1.8]:
		for pz in [-1.5, 1.5, 2.8]:
			var w = xf * Vector3(px, 0, pz)
			tube(SB, Vector3(w.x, ground_h(w.x, w.z) - 0.2, w.z), Vector3(w.x, base.y + floor_y, w.z), 0.11, 0.1, 6, post_c)
	# floor with porch
	var fz = -1.6
	while fz < 3.0:
		boxb(SB, Vector3(4.0, 0.08, 0.3), xf * Transform3D(Basis.IDENTITY, Vector3(0, floor_y, fz)), _wood())
		fz += 0.33
	# walls of vertical planks with a door + window opening on the sea side (+z)
	var wall_h = 2.2
	for side in 4:
		var length = 3.6 if side % 2 == 0 else 3.0
		var n = int(length / 0.3)
		for i in n:
			var u = -length * 0.5 + 0.15 + i * 0.3
			var lp: Vector3
			var rot = 0.0
			match side:
				0: lp = Vector3(u, 0, 1.5)
				1: lp = Vector3(1.8, 0, u); rot = PI / 2.0
				2: lp = Vector3(u, 0, -1.5)
				_: lp = Vector3(-1.8, 0, u); rot = PI / 2.0
			var hh = wall_h + rng.randf_range(-0.04, 0.04)
			var y0 = floor_y
			if side == 0 and u > 0.2 and u < 1.2:
				continue  # door
			if side == 0 and u < -0.4 and u > -1.4:
				boxb(SB, Vector3(0.29, 0.75, 0.08), xf * Transform3D(Basis(Vector3.UP, rot), lp + Vector3(0, y0 + 0.375, 0)), _wood(0.04))
				boxb(SB, Vector3(0.29, 0.6, 0.08), xf * Transform3D(Basis(Vector3.UP, rot), lp + Vector3(0, y0 + hh - 0.3, 0)), _wood(0.04))
				continue  # window
			boxb(SB, Vector3(0.29, hh, 0.08), xf * Transform3D(Basis(Vector3.UP, rot), lp + Vector3(0, y0 + hh * 0.5, 0)), _wood(0.04))
	boxb(SB, Vector3(1.0, 0.06, 0.2), xf * Transform3D(Basis.IDENTITY, Vector3(-0.9, floor_y + 0.75, 1.6)), post_c)  # window sill
	boxb(SB, Vector3(0.9, 1.9, 0.04), xf * Transform3D(Basis(Vector3.UP, -1.1), Vector3(0.25, floor_y + 0.95, 1.95)), Color(0.35, 0.55, 0.65))  # open door
	# interior dark backdrop so the door/window read as openings
	boxb(SB, Vector3(3.5, 2.1, 0.05), xf * Transform3D(Basis.IDENTITY, Vector3(0, floor_y + 1.05, -1.3)), Color(0.18, 0.13, 0.1))
	# thatched roof: layered slabs on both slopes
	var straw = Color(0.94, 0.78, 0.46)
	for side in [-1.0, 1.0]:
		for layer in 4:
			var t = layer / 3.0
			var y = floor_y + wall_h + 1.15 - t * 1.0
			var x = side * (0.35 + t * 1.75)
			var c = straw.lerp(Color(0.74, 0.58, 0.32), 0.25 * (layer % 2))
			boxb(SB, Vector3(1.0, 0.14, 4.6), xf * Transform3D(Basis(Vector3.FORWARD, side * 0.52), Vector3(x, y, 0.25)), c, 0.02)
	boxb(SB, Vector3(0.22, 0.22, 4.7), xf * Transform3D(Basis(Vector3.FORWARD, PI / 4.0), Vector3(0, floor_y + wall_h + 1.42, 0.25)), Color(0.62, 0.48, 0.28))
	# gable triangles
	for gz in [-1.5, 1.5]:
		var a: Vector3 = xf * Vector3(-1.8, floor_y + wall_h, gz)
		var b: Vector3 = xf * Vector3(1.8, floor_y + wall_h, gz)
		var c: Vector3 = xf * Vector3(0, floor_y + wall_h + 1.3, gz)
		var o = xf.basis * Vector3(0, 0, signf(gz))
		SB.face(a, b, c, _wood(), _wood(), _wood(), o)
	# porch railing + steps
	for px in [-1.95, -1.0, 1.95]:
		tube(SB, xf * Vector3(px, floor_y, 2.85), xf * Vector3(px, floor_y + 0.85, 2.85), 0.05, 0.05, 5, post_c)
	boxb(SB, Vector3(1.0, 0.07, 0.08), xf * Transform3D(Basis.IDENTITY, Vector3(-1.48, floor_y + 0.85, 2.85)), _wood())
	boxb(SB, Vector3(0.08, 0.07, 2.9), xf * Transform3D(Basis.IDENTITY, Vector3(-1.95, floor_y + 0.85, 1.4)), _wood())
	boxb(SB, Vector3(0.08, 0.07, 2.9), xf * Transform3D(Basis.IDENTITY, Vector3(1.95, floor_y + 0.85, 1.4)), _wood())
	for s in 4:
		var sw = xf * Vector3(0.45, 0, 3.15 + s * 0.32)
		var gy = ground_h(sw.x, sw.z)
		var yy = lerp(base.y + floor_y - 0.1, gy + 0.05, (s + 1) / 4.0)
		boxb(SB, Vector3(1.1, 0.07, 0.3), Transform3D(Basis(Vector3.UP, yaw), Vector3(sw.x, yy, sw.z)), _wood())
	# bench, guitar, barrels, crate, hanging lantern on the porch
	boxb(SB, Vector3(1.3, 0.07, 0.35), xf * Transform3D(Basis.IDENTITY, Vector3(-1.1, floor_y + 0.45, 1.85)), _wood())
	for bx in [-1.65, -0.55]:
		boxb(SB, Vector3(0.07, 0.45, 0.3), xf * Transform3D(Basis.IDENTITY, Vector3(bx, floor_y + 0.22, 1.85)), post_c)
	var gxf = xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(1.4, floor_y + 0.05, 1.65))
	SB.prim(_cylm(0.2, 0.2, 0.08, 10), gxf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.25, 0)), Color(0.78, 0.45, 0.2))
	SB.prim(_cylm(0.15, 0.15, 0.08, 10), gxf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.52, 0)), Color(0.78, 0.45, 0.2))
	boxb(SB, Vector3(0.06, 0.65, 0.03), gxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0.0)), Color(0.3, 0.2, 0.12))
	boxb(SB, Vector3(0.09, 0.12, 0.04), gxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0.0)), Color(0.3, 0.2, 0.12))
	cyl(SB, 0.05, 0.05, 0.02, 8, gxf * Vector3(0, 0.3, 0.05), Vector3(PI / 2.0, 0, 0), Color(0.15, 0.1, 0.08))
	var hp: Vector3 = xf * Vector3(1.6, floor_y + 2.0, 2.75)
	box(SB, Vector3(0.2, 0.04, 0.2), hp + Vector3(0, 0.16, 0), Vector3.ZERO, Color(0.2, 0.2, 0.22))
	box(GB, Vector3(0.15, 0.25, 0.15), hp, Vector3.ZERO, Color(1.0, 0.8, 0.45))
	_barrel(xf * Vector3(2.4, 0, 2.2) + Vector3(0, ground_h((xf * Vector3(2.4, 0, 2.2)).x, (xf * Vector3(2.4, 0, 2.2)).z) - base.y, 0))
	_crate(xf * Vector3(-2.6, 0.0, 2.6) + Vector3(0, ground_h((xf * Vector3(-2.6, 0, 2.6)).x, (xf * Vector3(-2.6, 0, 2.6)).z) - base.y + 0.3, 0), 0.6, 0.4)
	# fishing net drying between two poles beside the hut
	var n0: Vector3 = xf * Vector3(2.7, 0, -0.8)
	var n1: Vector3 = xf * Vector3(2.7, 0, 2.0)
	n0.y = ground_h(n0.x, n0.z)
	n1.y = ground_h(n1.x, n1.z)
	tube(SB, n0, n0 + Vector3(0, 2.0, 0), 0.05, 0.05, 5, post_c)
	tube(SB, n1, n1 + Vector3(0, 2.0, 0), 0.05, 0.05, 5, post_c)
	var net = Color(0.32, 0.3, 0.26)
	for r in 6:
		var y = 1.9 - r * 0.3
		var prev = n0 + Vector3(0, y, 0)
		for s in range(1, 9):
			var t = s / 8.0
			var p = (n0 + Vector3(0, y, 0)).lerp(n1 + Vector3(0, y, 0), t) + Vector3(0, -0.18 * sin(PI * t) * (1.0 - r / 7.0), 0)
			tube(SB, prev, p, 0.008, 0.008, 3, net)
			prev = p
	for s in range(1, 8):
		var t = s / 8.0
		var top = (n0 + Vector3(0, 1.9, 0)).lerp(n1 + Vector3(0, 1.9, 0), t) + Vector3(0, -0.18 * sin(PI * t), 0)
		tube(SB, top, top + Vector3(0, -1.5, 0), 0.008, 0.008, 3, net)
	for f in 4:
		blob(SB, (n0 + Vector3(0, 1.9, 0)).lerp(n1 + Vector3(0, 1.9, 0), 0.2 + f * 0.2) + Vector3(0, -0.15, 0), Vector3(0.09, 0.09, 0.09), Color(0.95, 0.55, 0.2), 0.0, 6, 3, 0.0)
	var lbl = Label3D.new()
	lbl.text = "钓鱼小屋"
	lbl.font = ui_font
	lbl.font_size = 64
	lbl.pixel_size = 0.005
	lbl.modulate = Color(0.95, 0.9, 0.75)
	lbl.outline_modulate = Color(0.3, 0.2, 0.1)
	lbl.outline_size = 10
	add_child(lbl)
	lbl.global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, floor_y + wall_h + 0.3, 1.62))
	var c2 = Vector2(base.x, base.z)
	add_obstacle(c2, 2.6, base.y + floor_y + wall_h + 1.4, "钓鱼小屋")

# ------------------------------------------------------------------ lighthouse & campfire

func _build_lighthouse() -> void:
	var p = lighthouse_pos + Vector3(0, -0.15, 0)
	cyl(SB, 1.25, 1.35, 0.5, 10, p + Vector3(0, 0.2, 0), Vector3.ZERO, Color(0.62, 0.6, 0.56))
	var h = 0.45
	var bands = 6
	for i in bands:
		var r0 = 0.95 - i * 0.07
		var r1 = 0.95 - (i + 1) * 0.07
		var col = Color(0.96, 0.95, 0.92) if i % 2 == 0 else Color(0.86, 0.25, 0.22)
		cyl(SB, r1, r0, 0.9, 10, p + Vector3(0, h + 0.45, 0), Vector3.ZERO, col)
		h += 0.9
	cyl(SB, 0.95, 0.95, 0.12, 12, p + Vector3(0, h + 0.06, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))
	for i in 12:
		var a = TAU * i / 12.0
		tube(SB, p + Vector3(cos(a) * 0.88, h + 0.1, sin(a) * 0.88), p + Vector3(cos(a) * 0.88, h + 0.55, sin(a) * 0.88), 0.02, 0.02, 3, Color(0.25, 0.25, 0.27))
	cyl(SB, 0.9, 0.9, 0.04, 12, p + Vector3(0, h + 0.55, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))
	cyl(GB, 0.45, 0.45, 0.75, 8, p + Vector3(0, h + 0.5, 0), Vector3.ZERO, Color(1.0, 0.9, 0.55))
	cyl(SB, 0.0, 0.7, 0.75, 10, p + Vector3(0, h + 1.25, 0), Vector3.ZERO, Color(0.86, 0.25, 0.22))
	blob(SB, p + Vector3(0, h + 1.68, 0), Vector3(0.08, 0.08, 0.08), Color(0.9, 0.8, 0.3), 0.0, 6, 3, 0.0)
	cyl(SB, 0.06, 0.06, 0.6, 6, p + Vector3(0.35, 0.9, 0.95), Vector3.ZERO, Color(0.3, 0.22, 0.15))
	box(SB, Vector3(0.55, 1.0, 0.06), p + Vector3(0.0, 0.95, 0.96), Vector3.ZERO, Color(0.35, 0.5, 0.62))
	add_obstacle(Vector2(p.x, p.z), 1.3, p.y + h + 1.7, "灯塔")
	# bench looking out to sea
	var bp = p + Vector3(-2.2, 0, -2.0)
	bp.y = ground_h(bp.x, bp.z)
	var bxf = Transform3D(Basis(Vector3.UP, 0.7), bp)
	boxb(SB, Vector3(1.4, 0.07, 0.4), bxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), _wood())
	boxb(SB, Vector3(1.4, 0.3, 0.06), bxf * Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 0.75, 0.2)), _wood())
	for bx in [-0.6, 0.6]:
		boxb(SB, Vector3(0.07, 0.45, 0.35), bxf * Transform3D(Basis.IDENTITY, Vector3(bx, 0.22, 0)), Color(0.42, 0.29, 0.18))

func _build_campfire() -> void:
	var c = campfire_pos
	walk_blockers.append([Vector2(c.x, c.z), 0.85])
	for a0 in [0.6, 2.7, 4.8]:
		walk_blockers.append([Vector2(c.x + cos(a0) * 1.7, c.z + sin(a0) * 1.7), 0.4])
	for a1 in [1.5, -1.6]:
		walk_blockers.append([Vector2(c.x + cos(a1) * 2.6, c.z + sin(a1) * 2.6), 0.08])
	for i in 9:
		var a = TAU * i / 9.0
		blob(SB, c + Vector3(cos(a) * 0.65, 0.08, sin(a) * 0.65), Vector3(0.17, 0.12, 0.15), Color(0.5, 0.48, 0.45))
	for i in 3:
		var a = i * 2.1
		tube(SB, c + Vector3(cos(a) * 0.45, 0.05, sin(a) * 0.45), c + Vector3(-cos(a) * 0.2, 0.35, -sin(a) * 0.2), 0.07, 0.06, 5, Color(0.35, 0.22, 0.12))
	cyl(GB, 0.0, 0.28, 0.7, 5, c + Vector3(0, 0.42, 0), Vector3.ZERO, Color(1.0, 0.55, 0.15))
	cyl(GB, 0.0, 0.16, 0.5, 5, c + Vector3(0.05, 0.38, 0.05), Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.3))
	for i in 3:
		var a = 0.6 + i * 2.1
		var lp = c + Vector3(cos(a) * 1.7, 0, sin(a) * 1.7)
		lp.y = ground_h(lp.x, lp.z)
		tube(SB, lp + Vector3(-sin(a) * 0.7, 0.18, cos(a) * 0.7), lp + Vector3(sin(a) * 0.7, 0.18, -cos(a) * 0.7), 0.17, 0.17, 7, Color(0.5, 0.34, 0.2), 1.0, 1.0, Color(0.6, 0.45, 0.3))
	# tiki torches
	for a in [1.5, -1.6]:
		var tp = c + Vector3(cos(a) * 2.6, 0, sin(a) * 2.6)
		tp.y = ground_h(tp.x, tp.z)
		tube(SB, tp, tp + Vector3(0, 1.6, 0), 0.04, 0.04, 5, Color(0.4, 0.28, 0.16))
		cyl(SB, 0.1, 0.07, 0.22, 6, tp + Vector3(0, 1.65, 0), Vector3.ZERO, Color(0.55, 0.42, 0.25))
		cyl(GB, 0.0, 0.08, 0.25, 5, tp + Vector3(0, 1.88, 0), Vector3.ZERO, Color(1.0, 0.65, 0.2))

# ------------------------------------------------------------------ beach life

func _build_beach_life() -> void:
	# beached boat
	var bth = -0.75
	var bp = shore_pt(bth, 1.6)
	_boat(bp + Vector3(0, 0.12, 0), atan2(dir_at(bth).x, dir_at(bth).z) + 0.3, Color(0.9, 0.45, 0.25), 0.14)
	# umbrella + towel + deck chair
	var up = shore_pt(-0.15, 4.0)
	umbrella_pos = up
	walk_blockers.append([Vector2(up.x, up.z), 0.12])
	tube(SB, up, up + Vector3(0, 2.3, 0), 0.03, 0.03, 5, Color(0.95, 0.95, 0.95))
	for i in 8:
		var a0 = TAU * i / 8.0
		var a1 = TAU * (i + 1) / 8.0
		var top = up + Vector3(0, 2.55, 0)
		var col = Color(0.95, 0.35, 0.3) if i % 2 == 0 else Color(0.98, 0.95, 0.88)
		SB.face(top, up + Vector3(cos(a0) * 1.5, 2.05, sin(a0) * 1.5), up + Vector3(cos(a1) * 1.5, 2.05, sin(a1) * 1.5), col, col, col, Vector3.UP)
		SB.face(top, up + Vector3(cos(a0) * 1.5, 2.05, sin(a0) * 1.5), up + Vector3(cos(a1) * 1.5, 2.05, sin(a1) * 1.5), col.darkened(0.25), col.darkened(0.25), col.darkened(0.25), Vector3.DOWN)
	var out = dir_at(-0.15)
	var tyaw = atan2(out.x, out.z)
	var tw = up + out * 1.2
	towel_pos = Vector3(tw.x, ground_h(tw.x, tw.z) + 0.03, tw.z)
	towel_dir = out
	for s in 5:
		var col = Color(0.3, 0.6, 0.85) if s % 2 == 0 else Color(0.98, 0.5, 0.35)
		var sc = tw + Basis(Vector3.UP, tyaw) * Vector3(0, 0, (s - 2) * 0.36)
		# follow the beach slope: each stripe tilted to the sand under it
		var g0 = ground_h(sc.x - out.x * 0.18, sc.z - out.z * 0.18)
		var g1 = ground_h(sc.x + out.x * 0.18, sc.z + out.z * 0.18)
		var tilt = atan2(g0 - g1, 0.36)
		boxb(SB, Vector3(0.9, 0.03, 0.37), Transform3D(Basis(Vector3.UP, tyaw) * Basis(Vector3.RIGHT, tilt), Vector3(sc.x, (g0 + g1) * 0.5 + 0.03, sc.z)), col)
	var cp = tw + out.cross(Vector3.UP).normalized() * 1.15 + out * 0.1
	cp.y = ground_h(cp.x, cp.z)
	var cxf = Transform3D(Basis(Vector3.UP, tyaw), cp)
	walk_blockers.append([Vector2(cp.x, cp.z), 0.55])
	boxb(SB, Vector3(0.6, 0.05, 1.0), cxf * Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 0.3, 0)), Color(0.3, 0.55, 0.85))
	boxb(SB, Vector3(0.6, 0.05, 0.7), cxf * Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0, 0.55, -0.6)), Color(0.3, 0.55, 0.85))
	for lx in [-0.28, 0.28]:
		for lz in [-0.4, 0.4]:
			boxb(SB, Vector3(0.04, 0.3, 0.04), cxf * Transform3D(Basis.IDENTITY, Vector3(lx, 0.15, lz)), Color(0.9, 0.9, 0.9))
	# surfboard stuck in the sand
	var sp = shore_pt(0.55, 3.5)
	SB.prim(_sphm(10, 5), Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, -0.12) * Basis.IDENTITY.scaled(Vector3(0.28, 1.1, 0.05)), sp + Vector3(0, 0.95, 0)), Color(0.98, 0.7, 0.25))
	# starfish and shells scattered on the wet sand and in the shallows
	for i in 40:
		var th = rng.randf() * TAU
		var inset = rng.randf_range(-2.5, 3.0)
		var p = shore_pt(th, inset)
		if absf(wrapf(th + PI / 2.0, -PI, PI)) < 0.12:
			continue
		if rng.randf() < 0.45:
			_starfish(p + Vector3(0, 0.025, 0), rng.randf_range(0.14, 0.22), [Color(0.95, 0.45, 0.25), Color(0.9, 0.3, 0.35), Color(0.65, 0.35, 0.75), Color(0.98, 0.7, 0.3)][rng.randi() % 4])
		else:
			var sc = [Color(0.98, 0.92, 0.85), Color(0.97, 0.75, 0.7), Color(0.9, 0.85, 0.75)][rng.randi() % 3]
			SB.prim(_cylm(0.0, 0.09, 0.12, 6), Transform3D(Basis(Vector3(rng.randf(), 0.2, rng.randf()).normalized(), 1.3), p + Vector3(0, 0.04, 0)), sc)

func _starfish(p: Vector3, r: float, col: Color) -> void:
	var rot = rng.randf() * TAU
	var c = p + Vector3(0, 0.03, 0)
	var dark = col.darkened(0.15)
	for i in 5:
		var a = rot + TAU * i / 5.0
		var tip = p + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var l = p + Vector3(cos(a - 0.63) * r * 0.3, 0.0, sin(a - 0.63) * r * 0.3)
		var rr = p + Vector3(cos(a + 0.63) * r * 0.3, 0.0, sin(a + 0.63) * r * 0.3)
		SB.face(c, l, tip, col, dark, col, Vector3.UP)
		SB.face(c, tip, rr, col, col, dark, Vector3.UP)

# ------------------------------------------------------------------ rocks & reef

func _rock_at(p: Vector3, s: float, col := Color(0.5, 0.48, 0.46)) -> void:
	var sy = s * rng.randf_range(0.55, 0.9)
	var c = col.lerp(Color(0.42, 0.42, 0.44), rng.randf() * 0.5)
	blob(SB, p, Vector3(s * rng.randf_range(0.9, 1.25), sy, s), c, 0.2, 7, 4, 0.035)
	if p.y + sy > 0.05:
		add_obstacle(Vector2(p.x, p.z), s * 0.9, p.y + sy, "礁石", p.y - sy)

func _build_rocks_and_reef() -> void:
	# headland rock group on the east
	for spec in [[0.12, -1.5, 1.6], [0.2, -3.0, 1.1], [0.05, -0.2, 1.3], [0.28, -1.0, 0.8], [0.0, 1.2, 0.9], [0.36, 0.5, 0.6], [0.16, -4.6, 0.7]]:
		var p = shore_pt(spec[0], spec[1])
		_rock_at(p + Vector3(0, -0.15, 0), spec[2])
	# rocks along the west and north shores
	for spec in [[2.7, -0.8, 1.0], [2.85, 0.4, 0.6], [1.15, -1.8, 0.9], [-2.75, -1.4, 0.8], [-1.3, 0.6, 0.55], [2.2, 1.0, 0.5], [-0.35, -6.0, 0.9], [-2.0, -7.0, 1.1]]:
		var p = shore_pt(spec[0], spec[1])
		_rock_at(p + Vector3(0, -0.1, 0), spec[2])
	# little rocks + moss near the hill
	for i in 10:
		var a = rng.randf() * TAU
		var p = gp(2.0 + cos(a) * rng.randf_range(3.5, 7.0), 3.0 + sin(a) * rng.randf_range(3.5, 7.0))
		if path_dist(p.x, p.z) > 1.2:
			blob(SB, p, Vector3(0.35, 0.25, 0.3) * rng.randf_range(0.6, 1.4), Color(0.55, 0.54, 0.5))
	# coral reef patches in the lagoon
	var coral_cols = [Color(0.86, 0.1, 0.2), Color(0.95, 0.36, 0.04), Color(0.42, 0.1, 0.72), Color(0.95, 0.66, 0.0), Color(0.06, 0.6, 0.52), Color(0.78, 0.12, 0.48)]
	for patch in [[-1.05, 6.0], [-0.85, 8.5], [-2.0, 6.5], [-2.25, 9.0], [0.55, 6.5], [2.4, 7.0], [-1.9, 4.5], [-1.25, 4.2]]:
		var center = dir_at(patch[0]) * (island_R(patch[0]) + patch[1])
		for k in 7:
			var p = center + Vector3(rng.randf_range(-2.2, 2.2), 0, rng.randf_range(-2.2, 2.2))
			p.y = ground_h(p.x, p.z)
			var col: Color = coral_cols[rng.randi() % coral_cols.size()]
			match rng.randi() % 4:
				0:  # branching coral
					_branch(p, Vector3(0, 1, 0), 0.5, 0.06, 3, col)
				1:  # brain coral
					blob(SB, p, Vector3(0.45, 0.3, 0.45) * rng.randf_range(0.7, 1.3), col, 0.08, 8, 4, 0.04)
				2:  # fan coral
					var yaw = rng.randf() * TAU
					var b = Basis(Vector3.UP, yaw)
					for f in 7:
						var a0 = -1.1 + f * 0.31
						var a1 = a0 + 0.31
						SB.face(p, p + b * Vector3(sin(a0) * 0.7, cos(a0) * 0.75, 0), p + b * Vector3(sin(a1) * 0.7, cos(a1) * 0.75, 0), col.darkened(0.2), col, col, b * Vector3(0, 0, 1))
						SB.face(p, p + b * Vector3(sin(a0) * 0.7, cos(a0) * 0.75, 0), p + b * Vector3(sin(a1) * 0.7, cos(a1) * 0.75, 0), col.darkened(0.2), col, col, b * Vector3(0, 0, -1))
				_:  # seaweed
					_seaweed(p)
	for i in 45:
		var th = rng.randf() * TAU
		var p = dir_at(th) * (island_R(th) + rng.randf_range(2.0, 11.0))
		p.y = ground_h(p.x, p.z)
		if absf(p.x) < 3.0 and p.z < dock_start_z:
			continue
		if rng.randf() < 0.6:
			_seaweed(p)
		else:
			blob(SB, p, Vector3(0.35, 0.22, 0.3) * rng.randf_range(0.6, 1.6), Color(0.5, 0.52, 0.48))

func _branch(p: Vector3, dir: Vector3, length: float, r: float, depth: int, col: Color) -> void:
	var e = p + dir * length
	tube(SB, p, e, r, r * 0.75, 5, col)
	if depth <= 0:
		blob(SB, e, Vector3(r, r, r) * 1.2, col.lightened(0.15), 0.0, 5, 3, 0.0)
		return
	for k in 2:
		var nd = (dir + Vector3(rng.randf_range(-0.8, 0.8), 0.25, rng.randf_range(-0.8, 0.8))).normalized()
		_branch(e, nd, length * 0.72, r * 0.75, depth - 1, col)

func _seaweed(p: Vector3) -> void:
	var g = [Color(0.25, 0.55, 0.3), Color(0.35, 0.62, 0.28), Color(0.22, 0.48, 0.38)][rng.randi() % 3]
	for k in 3:
		var base = p + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h = rng.randf_range(0.7, 1.4)
		var yaw = rng.randf() * TAU
		var side = Vector3(cos(yaw), 0, sin(yaw)) * 0.07
		var prev_l = base - side
		var prev_r = base + side
		for s in range(1, 5):
			var t = s / 4.0
			var c = base + Vector3(sin(t * 3.0 + yaw) * 0.15, h * t, cos(t * 2.0 + yaw) * 0.1)
			var w = side * (1.0 - t * 0.7)
			FB.tri3(prev_l, prev_r, c + w, Color(g, (t - 0.25) * 0.5), Color(g, (t - 0.25) * 0.5), Color(g.lightened(0.1), t * 0.5), Vector3.UP)
			FB.tri3(prev_l, c + w, c - w, Color(g, (t - 0.25) * 0.5), Color(g.lightened(0.1), t * 0.5), Color(g.lightened(0.1), t * 0.5), Vector3.UP)
			prev_l = c - w
			prev_r = c + w

# ------------------------------------------------------------------ palms

func _frond(b: MeshBuilder, base: Vector3, dir: Vector3, length: float, rise: float, droop: float, width: float, seg: int, cd: Color, cl: Color, cv: Color, sway_base: float) -> void:
	var side = dir.cross(Vector3.UP).normalized()
	var pts: Array[Vector3] = []
	for i in seg + 1:
		var s = float(i) / seg
		pts.append(base + dir * length * s + Vector3.UP * (rise * s - droop * s * s))
	for i in seg:
		var s0 = float(i) / seg
		var s1 = float(i + 1) / seg
		var p0 = pts[i]
		var p1 = pts[i + 1]
		var tg = (p1 - p0).normalized()
		var w = width * pow(sin(PI * (0.1 + 0.85 * s0)), 0.55)
		var sw0 = sway_base + s0 * 0.6
		var sw1 = sway_base + s1 * 0.6
		for sg in [-1.0, 1.0]:
			var outd = (side * sg * 0.85 + Vector3.DOWN * 0.5).normalized()
			var tip = p0.lerp(p1, 0.3) + outd * w + tg * w * 0.75
			var b0 = p0
			var b1 = p0.lerp(p1, 0.92)
			var lc = cd if (i + (1 if sg > 0 else 0)) % 2 == 0 else cl
			if rng.randf() < 0.04:
				continue  # a torn leaflet here and there
			var n = (b1 - b0).cross(tip - b0).normalized()
			if n.y < 0.0:
				n = -n
			n = (n + Vector3.UP * 0.9).normalized()
			b.tri3(b0, b1, tip, Color(cv, sw0), Color(cv, sw1), Color(lc, sw1 + 0.15), n)
	# midrib
	for i in seg:
		var s0 = float(i) / seg
		tube(b, pts[i], pts[i + 1], 0.035 * (1.0 - s0), 0.035 * (1.0 - s0 - 1.0 / seg), 3, cv.darkened(0.15), sway_base + s0 * 0.6, sway_base + (s0 + 1.0 / seg) * 0.6)

func palm(b: MeshBuilder, base: Vector3, height: float, lean_dir: Vector3, lean: float, bend: float, leaf_scale := 1.0, nfr := 11) -> Vector3:
	var segs = 13
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t = float(i) / segs
		var off = lean_dir * height * lean * (t * 0.3 + bend * t * t)
		pts.append(base + off + Vector3.UP * height * t * (1.0 - 0.08 * lean * t))
	trunks.append(pts)
	# warm grey-brown ringed segments (each ring flares, a darker groove under it)
	var c1 = Color(0.58, 0.50, 0.41)
	var c2 = Color(0.52, 0.45, 0.37)
	for i in segs:
		var t0 = float(i) / segs
		var t1 = float(i + 1) / segs
		var r0: float = lerp(0.27, 0.15, t0)
		var r1: float = lerp(0.27, 0.15, t1)
		var col = c1 if i % 2 == 0 else c2
		tube(b, pts[i] - (pts[i + 1] - pts[i]) * 0.05, pts[i + 1], r0 * 1.1, r1 * 0.88, 8, col, t0 * t0 * 0.35, t1 * t1 * 0.35, col.darkened(0.22))
	var crown = pts[segs]
	var sw = 0.35
	blob(b, crown + Vector3(0, 0.05, 0), Vector3(0.24, 0.2, 0.24), Color(0.4, 0.36, 0.2), 0.04, 6, 3, 0.0, sw)
	# coconuts
	var nc = rng.randi_range(2, 5)
	for i in nc:
		var a = rng.randf() * TAU
		var cc = Color(0.42, 0.3, 0.16) if rng.randf() < 0.6 else Color(0.5, 0.55, 0.2)
		blob(b, crown + Vector3(cos(a) * 0.2, -0.22 - rng.randf() * 0.08, sin(a) * 0.2), Vector3(0.14, 0.15, 0.14), cc, 0.02, 6, 4, 0.02, sw)
	# fronds
	var dark = Color(0.13, 0.42, 0.17)
	var light = Color(0.27, 0.6, 0.22)
	var vein = Color(0.55, 0.62, 0.25)
	var start = rng.randf() * TAU
	for k in nfr:
		var a = start + TAU * k / nfr + rng.randf_range(-0.15, 0.15)
		var d = Vector3(cos(a), 0, sin(a))
		var old = rng.randf() < 0.12
		var cd = dark if not old else Color(0.55, 0.52, 0.2)
		var cl = light if not old else Color(0.68, 0.62, 0.25)
		var L = rng.randf_range(2.5, 3.3) * leaf_scale
		_frond(b, crown + d * 0.12, d, L, rng.randf_range(0.6, 1.0) * leaf_scale, rng.randf_range(2.0, 2.8) * leaf_scale * (1.3 if old else 1.0), 0.48 * leaf_scale, 11, cd, cl, vein, sw)
	for k in 3:
		var a = start + k * 2.1 + 0.5
		var d = Vector3(cos(a), 0, sin(a))
		_frond(b, crown + Vector3(0, 0.05, 0), d, 1.6 * leaf_scale, 1.4 * leaf_scale, 0.9 * leaf_scale, 0.35 * leaf_scale, 8, Color(0.3, 0.62, 0.22), Color(0.42, 0.7, 0.25), vein, sw)
	add_obstacle(Vector2(base.x, base.z), 0.3, base.y + height, "椰子树")
	return crown

func _build_palms() -> void:
	var specs: Array = []
	# clusters around the beach ring (theta, inset, count)
	var ring = [[-1.25, 3.5, 2], [-0.95, 5.0, 1], [-0.45, 3.0, 3], [0.3, 5.5, 1], [0.75, 3.2, 2], [1.15, 4.5, 1], [1.5, 3.0, 2],
			[2.05, 4.0, 3], [2.5, 3.0, 1], [2.95, 4.5, 2], [-2.75, 3.2, 2], [-2.0, 4.8, 1], [-1.85, 2.8, 1], [-2.55, 6.5, 1], [0.95, 7.5, 1], [2.4, 7.5, 2], [-0.2, 7.5, 1]]
	for r in ring:
		var th: float = r[0]
		var base = shore_pt(th, r[1])
		var cnt: int = r[2]
		for k in cnt:
			var p = base + Vector3(rng.randf_range(-1.4, 1.4), 0, rng.randf_range(-1.4, 1.4)) * (1.0 if cnt > 1 else 0.0)
			p.y = ground_h(p.x, p.z) - 0.05
			var out = dir_at(th).rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
			if cnt > 1:
				out = (out + (p - base).normalized() * 0.6).normalized()
			specs.append([p, rng.randf_range(4.2, 7.2), out, rng.randf_range(0.25, 0.75), rng.randf_range(0.3, 1.2)])
	# hammock pair next to the hut
	var hth = -2.3
	var h1 = shore_pt(hth + 0.17, 2.2)
	var h2 = shore_pt(hth + 0.33, 2.6)
	specs.append([h1 + Vector3(0, -0.05, 0), 5.6, dir_at(hth), 0.18, 0.4])
	specs.append([h2 + Vector3(0, -0.05, 0), 6.1, dir_at(hth + 0.3), 0.22, 0.5])
	# palms on the hill flanks
	for hp in [Vector2(-4.5, 6.0), Vector2(7.5, 6.5), Vector2(-6.0, -1.5), Vector2(8.0, -2.0), Vector2(-1.0, 11.0), Vector2(5.0, 11.5)]:
		var p = gp(hp.x, hp.y)
		specs.append([p + Vector3(0, -0.05, 0), rng.randf_range(4.5, 6.5), Vector3(hp.x - 2.0, 0, hp.y - 3.0).normalized(), rng.randf_range(0.15, 0.4), 0.5])
	for s in specs:
		var p: Vector3 = s[0]
		if path_dist(p.x, p.z) < 1.3 or (absf(p.x) < 2.0 and p.z < dock_start_z + 2.0):
			continue
		var crown = palm(FB, p, s[1], s[2], s[3], s[4], rng.randf_range(0.85, 1.1))
		palm_spots.append(crown)
	# hammock between the hut pair: its own node so it can swing about the a-b axis
	var a = h1 + Vector3(0, 1.05, 0)   # low enough that the (taller) kid sits with his feet near the sand
	var b = h2 + Vector3(0, 1.05, 0)
	hammock_a = a
	hammock_b = b
	var mid = (a + b) * 0.5
	var HB = MeshBuilder.new()
	var ab = b - a
	var side = ab.cross(Vector3.UP).normalized() * 0.4
	for s in 10:
		var t0 = s / 10.0
		var t1 = (s + 1) / 10.0
		var p0 = a + ab * t0 + Vector3(0, -0.6 * sin(PI * t0), 0) - mid
		var p1 = a + ab * t1 + Vector3(0, -0.6 * sin(PI * t1), 0) - mid
		var w0 = side * sin(PI * clamp(t0 * 1.2 - 0.1, 0.0, 1.0)) + side * 0.05
		var w1 = side * sin(PI * clamp(t1 * 1.2 - 0.1, 0.0, 1.0)) + side * 0.05
		for st in 3:
			var u0 = -1.0 + st * 2.0 / 3.0
			var u1 = u0 + 2.0 / 3.0
			var col = [Color(0.95, 0.4, 0.3), Color(0.98, 0.88, 0.5), Color(0.3, 0.6, 0.8)][st]
			var A = p0 + w0 * u0 + Vector3(0, -0.12 * (1.0 - u0 * u0), 0)
			var B = p0 + w0 * u1 + Vector3(0, -0.12 * (1.0 - u1 * u1), 0)
			var C = p1 + w1 * u1 + Vector3(0, -0.12 * (1.0 - u1 * u1), 0)
			var D = p1 + w1 * u0 + Vector3(0, -0.12 * (1.0 - u0 * u0), 0)
			HB.face(A, B, C, col, col, col, Vector3.UP)
			HB.face(A, C, D, col, col, col, Vector3.UP)
			HB.face(A, B, C, col.darkened(0.2), col.darkened(0.2), col.darkened(0.2), Vector3.DOWN)
			HB.face(A, C, D, col.darkened(0.2), col.darkened(0.2), col.darkened(0.2), Vector3.DOWN)
	# end ropes to the trunks
	for e in [a, b]:
		var q = e.lerp(mid, 0.08) + Vector3(0, -0.06, 0)
		tube(HB, e - mid, q - mid, 0.02, 0.02, 4, Color(0.85, 0.75, 0.55))
	var hsm = StandardMaterial3D.new()
	hsm.vertex_color_use_as_albedo = true
	hsm.vertex_color_is_srgb = true
	hsm.roughness = 0.9
	hsm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hammock_node = Node3D.new()
	hammock_node.position = mid
	add_child(hammock_node)
	var hmi = MeshInstance3D.new()
	hmi.mesh = HB.commit()
	hmi.material_override = hsm
	hammock_node.add_child(hmi)
	# the hanging bed blocks walking (a few circles along it)
	for k in 5:
		var q2 = a.lerp(b, 0.2 + 0.15 * k)
		walk_blockers.append([Vector2(q2.x, q2.z), 0.32])

## lowest point of the hammock bed (world, at rest)
func hammock_bed() -> Vector3:
	return (hammock_a + hammock_b) * 0.5 + Vector3(0, -0.72, 0)

func swing_hammock(ang: float) -> Transform3D:
	var mid = (hammock_a + hammock_b) * 0.5
	var axis = (hammock_b - hammock_a).normalized()
	var xf = Transform3D(Basis(axis, ang), mid)
	hammock_node.transform = xf
	# transform from rest-world to swung-world
	return xf * Transform3D(Basis.IDENTITY, -mid)

# ------------------------------------------------------------------ vegetation

func _bush(p: Vector3, s: float) -> void:
	var g = [Color(0.36, 0.64, 0.28), Color(0.42, 0.7, 0.3), Color(0.3, 0.58, 0.3)][rng.randi() % 3]
	for k in rng.randi_range(3, 5):
		var o = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 0.5), rng.randf_range(-0.5, 0.5)) * s
		blob(FB, p + o + Vector3(0, s * 0.3, 0), Vector3(0.55, 0.45, 0.55) * s * rng.randf_range(0.7, 1.1), g, 0.07 * s, 7, 4, 0.04, 0.08)
	if rng.randf() < 0.5:
		var fc = [Color(0.95, 0.3, 0.4), Color(0.98, 0.6, 0.75), Color(1.0, 0.85, 0.3), Color(0.98, 0.98, 0.95)][rng.randi() % 4]
		for k in rng.randi_range(3, 6):
			var a = rng.randf() * TAU
			var o = Vector3(cos(a) * 0.5 * s, rng.randf_range(0.5, 0.85) * s, sin(a) * 0.5 * s)
			_flower(FB, p + o, 0.1 * s + 0.05, fc, 0.1, Vector3(cos(a), 0.6, sin(a)).normalized())

func _flower(b: MeshBuilder, c: Vector3, r: float, col: Color, sway: float, up := Vector3.UP) -> void:
	var u = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var v = up.cross(u)
	for i in 5:
		var a0 = TAU * i / 5.0
		var a1 = a0 + TAU / 5.0 * 0.8
		var p0 = c + (u * cos(a0) + v * sin(a0)) * r
		var p1 = c + (u * cos(a1) + v * sin(a1)) * r
		b.tri3(c, p0, p1, Color(1.0, 0.9, 0.4, sway), Color(col, sway), Color(col, sway), up)

func _fern(p: Vector3, s: float) -> void:
	var n = rng.randi_range(6, 8)
	for k in n:
		var a = TAU * k / n + rng.randf() * 0.3
		_frond(FB, p + Vector3(0, 0.05, 0), Vector3(cos(a), 0, sin(a)), 0.9 * s, 0.55 * s, 0.75 * s, 0.17 * s, 6, Color(0.2, 0.5, 0.2), Color(0.32, 0.6, 0.24), Color(0.38, 0.58, 0.25), 0.05)

func _grass(p: Vector3, s: float) -> void:
	var g = Color(0.42, 0.68, 0.28)
	for k in 7:
		var a = rng.randf() * TAU
		var base = p + Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.18
		var tip = base + Vector3(cos(a) * 0.2, rng.randf_range(0.3, 0.55), sin(a) * 0.2) * s
		var side = Vector3(-sin(a), 0, cos(a)) * 0.035 * s
		FB.tri3(base - side, base + side, tip, Color(g.darkened(0.2), 0.0), Color(g.darkened(0.2), 0.0), Color(g.lightened(0.1), 0.25), Vector3.UP)

func _build_vegetation() -> void:
	var placed = 0
	var tries = 0
	while placed < 260 and tries < 3000:
		tries += 1
		var x = rng.randf_range(-24.0, 24.0)
		var z = rng.randf_range(-24.0, 24.0)
		var d = shore_d(x, z)
		if d > -2.5:
			continue
		if path_dist(x, z) < 1.1:
			continue
		if Vector2(x - lighthouse_pos.x, z - lighthouse_pos.z).length() < 2.6:
			continue
		if Vector2(x - hut_pos.x, z - hut_pos.z).length() < 4.0 or Vector2(x - campfire_pos.x, z - campfire_pos.z).length() < 3.2:
			continue
		var p = gp(x, z)
		var inland = -d
		var r = rng.randf()
		if inland > 5.0 and r < 0.3:
			_bush(p, rng.randf_range(0.8, 1.5))
		elif inland > 4.0 and r < 0.5:
			_fern(p, rng.randf_range(0.8, 1.3))
		elif inland > 3.5 and r < 0.62:
			var fc = [Color(0.98, 0.95, 0.95), Color(1.0, 0.85, 0.3), Color(0.95, 0.45, 0.6), Color(0.7, 0.5, 0.95)][rng.randi() % 4]
			for k in 3:
				var o = p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
				tube(FB, o, o + Vector3(0, 0.3, 0), 0.012, 0.01, 3, Color(0.3, 0.55, 0.25), 0.0, 0.2)
				_flower(FB, o + Vector3(0, 0.31, 0), 0.07, fc, 0.2)
		else:
			_grass(p, rng.randf_range(0.8, 1.4))
		placed += 1
	# a few beach grass tufts and low bushes framing the sand
	for i in 40:
		var th = rng.randf() * TAU
		var p = shore_pt(th, rng.randf_range(3.5, 5.5))
		if path_dist(p.x, p.z) > 1.0 and absf(wrapf(th + PI / 2.0, -PI, PI)) > 0.2:
			_grass(p, 1.0)
	# fence along the lighthouse path
	var pl: Array = paths[1]
	for i in range(1, pl.size() - 1):
		var a: Vector2 = pl[i]
		var b: Vector2 = pl[i + 1]
		var n = (b - a).normalized().orthogonal() * 0.9
		var segn = int((b - a).length() / 2.0)
		for s in segn + 1:
			var q = a.lerp(b, float(s) / max(segn, 1)) + n
			var gpq = gp(q.x, q.y)
			tube(SB, gpq, gpq + Vector3(0, 0.7, 0), 0.04, 0.04, 5, Color(0.48, 0.34, 0.2))
			if s > 0:
				var q0 = a.lerp(b, float(s - 1) / max(segn, 1)) + n
				var g0 = gp(q0.x, q0.y)
				tube(SB, g0 + Vector3(0, 0.6, 0), gpq + Vector3(0, 0.6, 0), 0.018, 0.018, 3, Color(0.85, 0.75, 0.55))
	# lantern posts along the beach path to the hut
	var bp: Array = paths[0]
	for i in range(1, bp.size()):
		var q: Vector2 = bp[i]
		var o: Vector2 = (bp[i] - bp[i - 1]).normalized().orthogonal() * 1.0
		var g = gp(q.x + o.x, q.y + o.y)
		tube(SB, g, g + Vector3(0, 1.1, 0), 0.04, 0.035, 5, Color(0.4, 0.28, 0.16))
		box(GB, Vector3(0.14, 0.2, 0.14), g + Vector3(0, 1.2, 0), Vector3.ZERO, Color(1.0, 0.78, 0.4))
		box(SB, Vector3(0.18, 0.03, 0.18), g + Vector3(0, 1.32, 0), Vector3.ZERO, Color(0.2, 0.2, 0.22))

# ------------------------------------------------------------------ far scenery

func _build_far() -> void:
	for isl in [[Vector3(-110, 0, -150), 16.0], [Vector3(95, 0, -175), 11.0], [Vector3(-30, 0, -235), 22.0], [Vector3(170, 0, 30), 18.0], [Vector3(-160, 0, 90), 14.0], [Vector3(40, 0, 210), 20.0]]:
		var c: Vector3 = isl[0]
		var r: float = isl[1]
		SB.prim(_cylm(r * 1.0, r * 1.2, 0.9, 14), Transform3D(Basis.IDENTITY, c + Vector3(0, 0.0, 0)), Color(0.92, 0.84, 0.64))
		blob(SB, c + Vector3(rng.randf_range(-2, 2), 0.2, 0), Vector3(r * 0.82, r * 0.28, r * 0.72), Color(0.3, 0.56, 0.28), r * 0.015, 12, 6, 0.03)
		blob(SB, c + Vector3(r * 0.3, 0.2, r * 0.2), Vector3(r * 0.45, r * 0.38, r * 0.4), Color(0.27, 0.52, 0.26), r * 0.015, 10, 5, 0.03)
		for k in 4:
			var a = rng.randf() * TAU
			var pp = c + Vector3(cos(a) * r * 0.75, 0.3, sin(a) * r * 0.75)
			palm(SB, pp, rng.randf_range(5.0, 8.0) * r / 14.0, Vector3(cos(a), 0, sin(a)), 0.3, 0.6, r / 14.0, 7)
	# clouds
	for k in 14:
		var a = rng.randf() * TAU
		var dist = rng.randf_range(170, 300)
		var cp = Vector3(cos(a) * dist, rng.randf_range(45, 85), sin(a) * dist)
		var tan = Vector3(-sin(a), 0, cos(a))
		for b in rng.randi_range(4, 7):
			var r = rng.randf_range(7, 14)
			var p = cp + tan * (b * 9.0 - 25.0) + Vector3(0, rng.randf_range(-2, 4), rng.randf_range(-4, 4))
			var cm = _sphm(7, 4)
			var arrays = cm.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var v0 = verts[idx[i]] * Vector3(r, r * 0.62, r)
				var v1 = verts[idx[i + 1]] * Vector3(r, r * 0.62, r)
				var v2 = verts[idx[i + 2]] * Vector3(r, r * 0.62, r)
				var shade = clamp(0.86 + 0.14 * ((v0.y + v1.y + v2.y) / (3.0 * r * 0.62)), 0.72, 1.0)
				var col = Color(shade, shade * 1.0, min(shade * 1.04, 1.0))
				CB.tri(p + v0, p + v1, p + v2, col)

func _build_buoys() -> void:
	for dist in [20, 40, 60]:
		var bn = Node3D.new()
		add_child(bn)
		bn.position = Vector3(player_spot.x, 0, player_spot.z - dist)
		bn.set_meta("phase", rng.randf() * TAU)
		var b = MeshBuilder.new()
		b.prim(_cylm(0.18, 0.38, 0.7, 8), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Color(0.95, 0.35, 0.22))
		b.prim(_cylm(0.2, 0.2, 0.14, 8), Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Color(0.98, 0.98, 0.95))
		b.prim(_cylm(0.04, 0.04, 0.5, 5), Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Color(0.3, 0.3, 0.3))
		var mi = MeshInstance3D.new()
		mi.mesh = b.commit()
		var m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		mi.material_override = m
		bn.add_child(mi)
		var lbl = Label3D.new()
		lbl.text = "%d 米" % dist
		lbl.font = ui_font
		lbl.font_size = 64
		lbl.pixel_size = 0.012
		lbl.outline_size = 14
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.6, 0)
		lbl.visibility_range_begin = 9.0
		bn.add_child(lbl)
		buoys.append(bn)
