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
## solid shapes the boy can't walk into (ground plan + a height band): [kind, a, b, r, y0, y1, name]
##   "c" circle: centre a, radius r   "s" capsule: segment a..b, radius r   "b" box: centre a, half size b, yaw r
var walls: Array = []
var wall_grid := {}   # Vector2i cell -> wall indices
const WALL_CELL := 3.0
var hammock_a := Vector3.ZERO
var hammock_b := Vector3.ZERO
var hammock_node: Node3D
## Deformable hammock grid (local to hammock_node). Empty sag is light; occupied sag deepens under the body.
var hammock_mi: MeshInstance3D
var hammock_nt := 28
var hammock_nu := 22
var hammock_empty_sag := 0.26
var hammock_occ_sag := 0.42
var hammock_half_w := 0.58
var hammock_occupied := false
var hammock_body_pts: Array[Vector3] = []  # world points that weigh the fabric
## Authored hammock_v25 cloth driven by per-frame npz (preferred over morph lerp).
var hammock_use_v25 := false
var hammock_cloth_mi: MeshInstance3D
var hammock_cloth_meta: Dictionary = {}
var hammock_cloth_bytes: PackedByteArray = PackedByteArray()
var hammock_cloth_fmt: int = 0
var hammock_cloth_mat: Material
var hammock_clip := ""
var hammock_cloth_bind: PackedVector3Array = PackedVector3Array()
## Godot import may reorder verts; remap[i] = authoring/npz index for mesh vertex i.
var hammock_cloth_remap: PackedInt32Array = PackedInt32Array()
var hammock_prop_xf := Transform3D.IDENTITY
var _ham_rest_y: PackedFloat32Array = PackedFloat32Array()  # centreline rest Y offset per t
var _ham_cur_y: PackedFloat32Array = PackedFloat32Array()
var towel_pos := Vector3.ZERO
var towel_dir := Vector3.FORWARD   # towel long axis, pointing out to sea (feet end)
## Deck-chair lounger (晒太阳): root transform, seat/backrest sizes, and hinge in local Z.
var lounger_xf := Transform3D.IDENTITY
## Contact plane at the foam top. Pads are ~7 cm thick — legs rest ON TOP with light compress.
var lounger_seat_half := Vector3(0.32, 0.03, 0.55)
var lounger_back_half := Vector3(0.32, 0.04, 0.58)   # long backrest: full torso + head
var lounger_seat_tilt := 0.08                        # rad about local +X (slight foot-down)
var lounger_back_tilt := 0.70                         # ~40° chaise: head rises away from seat
var lounger_seat_local := Vector3(0, 0.34, 0.08)      # seat centre in lounger_xf
# Centre past the seat hinge (−local Z); raised so the pad clears the crease/thighs.
# +tilt raises the −Z (head) end.
var lounger_back_local := Vector3(0, 0.92, -0.78)
var umbrella_pos := Vector3.ZERO
var hut_pos := Vector3.ZERO
var lighthouse_pos := Vector3.ZERO
var beacon_pos := Vector3.ZERO
# glowing lanterns: [position, kind] with kind "dock" / "porch" / "path" (lit at night)
var lamps: Array = []
var glow_mat: ShaderMaterial
var cloud_mat: ShaderMaterial
var campfire_pos := Vector3.ZERO
var water_mi: MeshInstance3D
var bush_spots: Array = []
var leaves: Array = []    # [Transform3D, Color tint (a = sway), Color(outward normal, ao)] per leaf spray
var leaf_mat: ShaderMaterial
var terrain_mi: MeshInstance3D
var campfire: Campfire
var torches: Array[Torch] = []
var torch_mat: ShaderMaterial
var sign_board: MeshInstance3D
## places to sit: {name, top (seat surface under the pelvis), face (where the sitter looks), approach, hint}
var seats: Array[Dictionary] = []
const SEAT_TOP := 0.22   # authored v25 sit clips (thighs reach ground; was 0.35)
var obstacles: Array = []   # [Vector2 centre, radius, top_y, name]
var dock_boat: MeshInstance3D
var boat_mat: ShaderMaterial
var boat_tie := Vector3.ZERO
var boat_rest := Transform3D.IDENTITY
var boat_t := 0.0
var boat_t0 := -1.0
var boat_q := Vector3.ZERO   # heave (m), pitch, roll (rad)
var boat_v := Vector3.ZERO
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
var TB: MeshBuilder   # the torches' wood, cup and wick: static, plus their own flame's glow
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

## the logs round the campfire stand on the hillside. Inside site_r of the fire the rise above it (and its
## bumps) is scaled by site_k, easing back to the raw hill over site_l; the ground below the fire is left
## alone so the beach and its wash stay put. Each log then gets a level pad: [a, b] (xz ends of its core
## axis), height. Flat within pad_flat of the axis (the log, and the feet of whoever sits on either side),
## back to the clearing over a wide pad_blend so the banks stay no steeper than the hill round them.
static var pads: Array = []
static var pad_half := 0.35
static var pad_flat := 0.70   # was 0.42 — keep bench/log sit footprints level
static var pad_blend := 1.4
static var site := Vector3.ZERO
static var site_on := false
static var site_k := 0.25
static var site_r := 3.0
static var site_l := 6.0

static func ground_h(x: float, z: float) -> float:
	var h := _ground_raw(x, z)
	if site_on:
		var r := Vector2(x - site.x, z - site.z).length()
		if r < site_r + site_l:
			var k := lerpf(1.0, site_k, smoothstep(-0.4, 0.4, h - site.y))
			h = lerpf(site.y + k * (h - site.y), h, smoothstep(site_r, site_r + site_l, r))
	for pd: Array in pads:
		var q := Vector2(x, z)
		var a: Vector2 = pd[0]
		var ab: Vector2 = (pd[1] as Vector2) - a
		var dist := q.distance_to(a + ab * clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0))
		h = lerpf(float(pd[2]), h, smoothstep(pad_flat, pad_flat + pad_blend, dist))
	return h

static func _ground_raw(x: float, z: float) -> float:
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

## true while the swash film (sea or the wash running up the beach) covers the sand at (x, z),
## or is within `margin` metres (height) of covering it
static func wash_covers(x: float, z: float, t: float, margin := 0.0) -> bool:
	var d := shore_d(x, z)
	if d < -4.0:
		return false
	var gy := lerpf(ground_near(x, z, d), ground_h(x, z), smoothstep(0.5, 2.5, absf(d + 0.3)))
	var hab := gy - sea_y(x, z, t)
	var ru := runup(wash_cycle(x, z, t)) + (vnoise(x * 1.1 + t * 0.08, z * 1.3) - 0.5) * 0.02
	return hab < ru + 0.002 + margin

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
	_make_pads()
	SB = MeshBuilder.new()
	TB = MeshBuilder.new()
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
	_index_walls()
	_flush()
	_build_water()

func _make_pads() -> void:
	pads.clear()
	var c := campfire_pos
	site = c
	site_on = true
	var out: Array = []
	# Campfire log pads (wider so sit feet stay on flat ground).
	for i in 3:
		var a := 0.6 + i * 2.1
		var lp := c + Vector3(cos(a) * 1.7, 0, sin(a) * 1.7)
		var t := Vector2(-sin(a), cos(a)) * 0.75
		out.append([Vector2(lp.x, lp.z) + t, Vector2(lp.x, lp.z) - t, _ground_raw(lp.x, lp.z)])
	# Bench pad at the lighthouse sit spot (same offset as _build_lighthouse).
	var lh := gp(2.0, 3.0)
	var bp := lh + Vector3(-2.2, 0, -2.0)
	var bench_h := _ground_raw(bp.x, bp.z)
	# Axis along seat width (local +X at yaw 0.7) so the whole footprint is flat.
	var bx := Vector2(cos(0.7), -sin(0.7)) * 0.85
	out.append([Vector2(bp.x, bp.z) + bx, Vector2(bp.x, bp.z) - bx, bench_h])
	# Also flatten along seat depth (±Z) so approach feet match prop origin Y.
	var bz := Vector2(sin(0.7), cos(0.7)) * 0.55
	out.append([Vector2(bp.x, bp.z) + bz, Vector2(bp.x, bp.z) - bz, bench_h])
	pads = out
	campfire_pos.y = ground_h(c.x, c.z)

func _flush() -> void:
	static_mat = ShaderMaterial.new()
	static_mat.shader = load("res://shaders/static.gdshader")
	_mi(SB.commit(), static_mat)
	torch_mat = ShaderMaterial.new()
	torch_mat.shader = load("res://shaders/torch_wood.gdshader")
	_mi(TB.commit(), torch_mat)
	for tn in torches:
		tn.wood_mat = torch_mat
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	_mi(FB.commit(), foliage_mat)
	glow_mat = ShaderMaterial.new()
	glow_mat.shader = load("res://shaders/sky_tint.gdshader")
	glow_mat.set_shader_parameter("boost", 1.5)
	_mi(GB.commit(), glow_mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://shaders/sky_tint.gdshader")
	cloud_mat.set_shader_parameter("boost", 1.3)
	_mi(CB.commit(), cloud_mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_leaves()

## the bushes' leaf sprays: one MultiMesh of two crossed cards (a twig from each half of the texture);
## from far off (the sea) a third of them, larger, stand in for the rest, and that sparse set also casts
## the bushes' shadows (dappled all the same, a third of the shadow-pass work). The mirror skips them
func _build_leaves() -> void:
	leaf_mat = ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/leaf.gdshader")
	leaf_mat.set_shader_parameter("leaf_tex", load("res://textures/leaf_cluster.png"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in 2:
		var ax := Vector3.RIGHT if q == 0 else Vector3.BACK
		var nn := Vector3.BACK if q == 0 else Vector3.LEFT
		var u0 := 0.5 * q
		var c := [[-0.5, 0.0, u0, 1.0], [0.5, 0.0, u0 + 0.5, 1.0], [0.5, 1.0, u0 + 0.5, 0.0], [-0.5, 1.0, u0, 0.0]]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var v: Array = c[i]
			st.set_normal(nn)
			st.set_uv(Vector2(v[2], v[3]))
			st.add_vertex(ax * float(v[0]) + Vector3.UP * float(v[1]))
	var card := st.commit()
	for lod in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = card
		var pick: Array = []
		for i in leaves.size():
			if lod == 0 or i % 3 == 0:
				pick.append(i)
		mm.instance_count = pick.size()
		for j in pick.size():
			var lf: Array = leaves[pick[j]]
			var xf: Transform3D = lf[0]
			if lod > 0:
				xf.basis = xf.basis.scaled(Vector3.ONE * 1.45)
			mm.set_instance_transform(j, xf)
			mm.set_instance_color(j, lf[1])
			mm.set_instance_custom_data(j, lf[2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = leaf_mat
		# visibility ranges measure to the centre of the whole island's bushes
		mmi.layers = 1 | 16
		if lod == 0:
			mmi.visibility_range_end = 62.0
			mmi.visibility_range_end_margin = 4.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif lod == 1:
			mmi.visibility_range_begin = 62.0
			mmi.visibility_range_begin_margin = 4.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mmi)

func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi

func set_time(t: float) -> void:
	RenderingServer.global_shader_parameter_set("sea_time", t)
	_bob_boat(t)
	water_mat.set_shader_parameter("game_time", t)
	terrain_mat.set_shader_parameter("game_time", t)
	foliage_mat.set_shader_parameter("game_time", t)
	leaf_mat.set_shader_parameter("game_time", t)

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
	# Fine patches over campfire logs + lighthouse bench so flatten pads draw cleanly.
	var fine_rects: Array = []
	fine_rects.append([int(floor(campfire_pos.x + half)) - 6, int(floor(campfire_pos.z + half)) - 6, 12, 12])
	var lh_xz := gp(2.0, 3.0) + Vector3(-2.2, 0, -2.0)
	fine_rects.append([int(floor(lh_xz.x + half)) - 4, int(floor(lh_xz.z + half)) - 4, 8, 8])
	for j in n:
		for i in n:
			var skip := false
			for fr in fine_rects:
				if i >= int(fr[0]) and i < int(fr[0]) + int(fr[2]) and j >= int(fr[1]) and j < int(fr[1]) + int(fr[3]):
					skip = true
					break
			if skip:
				continue
			var a = j * (n + 1) + i
			var b = a + 1
			var c = a + n + 1
			var d = c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	var sub := 4
	var base: int = (n + 1) * (n + 1)
	for fr in fine_rects:
		var fi0: int = int(fr[0])
		var fj0: int = int(fr[1])
		var fi1: int = fi0 + int(fr[2])
		var fj1: int = fj0 + int(fr[3])
		var fn := (fi1 - fi0) * sub
		var patch_base := base
		for j in fn + 1:
			for i in fn + 1:
				var x: float = -half + fi0 + float(i) / sub
				var z: float = -half + fj0 + float(j) / sub
				var h: float
				if i == 0 or i == fn or j == 0 or j == fn:
					var x0: float = floorf(x + half + 1e-4) - half
					var z0: float = floorf(z + half + 1e-4) - half
					var tx := x - x0
					var tz := z - z0
					h = lerpf(lerpf(ground_h(x0, z0), ground_h(x0 + 1.0, z0), tx), lerpf(ground_h(x0, z0 + 1.0), ground_h(x0 + 1.0, z0 + 1.0), tx), tz)
				else:
					h = ground_h(x, z)
				st.set_color(_ground_color(x, z, h))
				st.set_uv(Vector2(x, z))
				st.add_vertex(Vector3(x, h, z))
		for j in fn:
			for i in fn:
				var a2 = patch_base + j * (fn + 1) + i
				var b2 = a2 + 1
				var c2 = a2 + fn + 1
				var d2 = c2 + 1
				st.add_index(a2); st.add_index(b2); st.add_index(c2)
				st.add_index(b2); st.add_index(d2); st.add_index(c2)
		base += (fn + 1) * (fn + 1)
	st.generate_normals()
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mi = _mi(st.commit(), terrain_mat)
	# the island's gentle slopes never shade anything worth a shadow-map pass of the whole terrain
	terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# deep floor beyond the terrain patch
	var bed = PlaneMesh.new()
	bed.size = Vector2(1400, 1400)
	var bm = StandardMaterial3D.new()
	bm.albedo_color = Color(0.25, 0.42, 0.5)
	var bmi = _mi(bed, bm)
	bmi.position.y = -5.8
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
	if dock_boat:
		var o := boat_rest.origin
		var yaw := boat_rest.basis.get_euler().y
		water_mat.set_shader_parameter("boat_c", Vector4(o.x, o.z, cos(yaw), sin(yaw)))
		var wl := boat_waterline()
		water_mat.set_shader_parameter("boat_wl", wl)
		# the rings fade out 0.8 m from the hull
		water_mat.set_shader_parameter("boat_box", Vector2(wl[8].x, wl[16].y) + Vector2(0.85, 0.85))
		water_mat.set_shader_parameter("boat_on", 1.0)
	water_mi = _mi(pm, water_mat)
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
		if top < -0.1 or bottom > 0.15 or o[3] == "小船":
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

func add_obstacle(c: Vector2, r: float, top: float, name: String, bottom := -99.0, walk := true) -> void:
	obstacles.append([c, r, top, name, bottom])
	if walk:
		wall_c(c, r, bottom, top, name)

# ---- walking collision

func wall_c(c: Vector2, r: float, y0: float, y1: float, name: String) -> void:
	walls.append(["c", c, c, r, y0, y1, name])

func wall_s(a: Vector2, b: Vector2, r: float, y0: float, y1: float, name: String) -> void:
	walls.append(["s", a, b, r, y0, y1, name])

func wall_b(c: Vector2, half: Vector2, yaw: float, y0: float, y1: float, name: String) -> void:
	walls.append(["b", c, half, yaw, y0, y1, name])

## same yaw convention as Basis(Vector3.UP, yaw) acting on (x, z)
static func _rot(v: Vector2, yaw: float) -> Vector2:
	return Vector2(cos(yaw) * v.x + sin(yaw) * v.y, -sin(yaw) * v.x + cos(yaw) * v.y)

## signed ground-plan distance from p to wall w (negative inside) and the outward normal: (dist, nx, nz)
static func wall_dist(w: Array, p: Vector2) -> Vector3:
	var a: Vector2 = w[1]
	match w[0] as String:
		"c", "s":
			var b: Vector2 = w[2]
			var ab := b - a
			var t := 0.0 if ab.length_squared() < 1e-8 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := p - (a + ab * t)
			var L := d.length()
			var n := d / L if L > 1e-5 else (ab.orthogonal().normalized() if ab.length_squared() > 1e-8 else Vector2(1, 0))
			return Vector3(L - float(w[3]), n.x, n.y)
		_:
			var half: Vector2 = w[2]
			var yaw: float = w[3]
			var l := _rot(p - a, -yaw)
			var q := Vector2(absf(l.x), absf(l.y)) - half
			var nl: Vector2
			var dist: float
			if q.x > 0.0 or q.y > 0.0:
				var o := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0))
				dist = o.length()
				nl = Vector2(o.x * signf(l.x), o.y * signf(l.y)) / maxf(dist, 1e-6)
			else:
				dist = maxf(q.x, q.y)
				nl = Vector2(signf(l.x) if l.x != 0.0 else 1.0, 0.0) if q.x > q.y else Vector2(0.0, signf(l.y) if l.y != 0.0 else 1.0)
			var n2 := _rot(nl, yaw)
			return Vector3(dist, n2.x, n2.y)

func _wall_rect(w: Array) -> Rect2:
	var a: Vector2 = w[1]
	match w[0] as String:
		"c", "s":
			var b: Vector2 = w[2]
			var r: float = w[3]
			return Rect2(a, Vector2.ZERO).expand(b).grow(r)
		_:
			var e: float = (w[2] as Vector2).length()
			return Rect2(a - Vector2(e, e), Vector2(e, e) * 2.0)

func _index_walls() -> void:
	wall_grid.clear()
	for i in walls.size():
		var r := _wall_rect(walls[i]).grow(0.5)
		for cx in range(floori(r.position.x / WALL_CELL), floori(r.end.x / WALL_CELL) + 1):
			for cz in range(floori(r.position.y / WALL_CELL), floori(r.end.y / WALL_CELL) + 1):
				var k := Vector2i(cx, cz)
				if not wall_grid.has(k):
					wall_grid[k] = []
				(wall_grid[k] as Array).append(i)

## indices of walls whose (grown) bounds touch the cell around p
func walls_near(p: Vector2) -> Array:
	return wall_grid.get(Vector2i(floori(p.x / WALL_CELL), floori(p.y / WALL_CELL)), [])

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
		wall_s(Vector2(1.2, zr), Vector2(1.2, zr - 4.8), 0.04, DECK_Y, DECK_Y + 0.6, "护栏绳")
		zr -= 4.8
	# the deck is solid from below: wading kids go round it, they only get on at the beach end
	var zs := dock_start_z
	while zs > dock_end_z + 3.6 and minf(ground_h(-1.15, zs), ground_h(1.15, zs)) > DECK_Y - 0.4:
		zs -= 0.1
	wall_b(Vector2(0, (zs + dock_end_z + 3.6) * 0.5), Vector2(1.15, (zs - dock_end_z - 3.6) * 0.5), 0.0, -9.0, DECK_Y - 0.12, "码头")
	wall_b(Vector2(0, dock_end_z + 1.92), Vector2(3.1, 2.04), 0.0, -9.0, DECK_Y - 0.12, "码头")
	# lanterns on the platform corners (tall posts)
	for sx in [-3.0, 3.0]:
		var base = Vector3(sx, DECK_Y + 0.7, dock_end_z + 0.15)
		tube(SB, base, base + Vector3(0, 1.5, 0), 0.06, 0.05, 6, post_c)
		box(SB, Vector3(0.6, 0.05, 0.05), base + Vector3(0, 1.45, 0) + Vector3(-0.3 * signf(sx), 0, 0), Vector3.ZERO, post_c)
		var lp = base + Vector3(-0.55 * signf(sx), 1.15, 0)
		box(SB, Vector3(0.24, 0.04, 0.24), lp + Vector3(0, 0.2, 0), Vector3.ZERO, Color(0.2, 0.2, 0.22))
		box(SB, Vector3(0.24, 0.04, 0.24), lp + Vector3(0, -0.2, 0), Vector3.ZERO, Color(0.2, 0.2, 0.22))
		box(GB, Vector3(0.18, 0.34, 0.18), lp, Vector3.ZERO, Color(1.0, 0.82, 0.45))
		lamps.append([lp, "dock"])
	# crates, barrel, bucket, fishing rod, life ring on the platform
	var pc = Vector3(-2.3, DECK_Y + 0.04, dock_end_z + 2.9)
	# spheres the close throw camera must not pass through (crates, barrels, corner lanterns)
	cam_blockers = [
		[pc + Vector3(0.35, 0.5, 0.05), 0.95], [Vector3(2.45, DECK_Y + 0.5, dock_end_z + 2.6), 0.8],
		[Vector3(-2.6, DECK_Y + 1.85, dock_end_z + 0.15), 0.5], [Vector3(2.6, DECK_Y + 1.85, dock_end_z + 0.15), 0.5],
		[Vector3(-3.0, DECK_Y + 1.4, dock_end_z + 0.15), 0.35], [Vector3(3.0, DECK_Y + 1.4, dock_end_z + 0.15), 0.35],
	]
	wall_c(Vector2(1.8, dock_end_z + 3.3), 0.18, DECK_Y, DECK_Y + 0.32, "水桶")
	wall_s(Vector2(-1.6, dock_end_z + 3.3), Vector2(-1.95, dock_end_z + 3.39), 0.04, DECK_Y, DECK_Y + 1.6, "鱼竿")
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
	# (its line is knotted round the rope rail, where that sags between its posts)
	var tz := (dock_start_z + dock_end_z) * 0.5 + 0.2
	var tu := fposmod(dock_start_z - 0.6 - tz, 4.8) / 4.8
	_float_boat(Vector3(2.3, 0.05, (dock_start_z + dock_end_z) * 0.5 - 1.0), 0.06, Color(0.3, 0.6, 0.8), Vector3(1.2, DECK_Y + 0.5 - 0.22 * sin(PI * tu), tz))
	# sign at the dock entrance: an old broken board with a kid's doodle of stone skipping, no words
	var sp = Vector3(-1.6, ground_h(-1.6, dock_start_z + 1.6), dock_start_z + 1.6)
	var rs := rng.state
	tube(SB, sp, sp + Vector3(0, 1.62, 0), 0.06, 0.055, 6, post_c.darkened(0.15))
	tube(SB, sp + Vector3(0, 1.62, 0), sp + Vector3(0.03, 1.74, 0.01), 0.05, 0.02, 5, Color(0.5, 0.45, 0.38))   # split top
	_sign_board(sp + Vector3(0, 1.5, 0.1), 0.15)
	# the piece that broke off, lying at the foot of the post
	var chunk := Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, 0.12), sp + Vector3(0.45, 0.03, 0.35))
	boxb(SB, Vector3(0.38, 0.04, 0.2), chunk, Color(0.5, 0.47, 0.42))
	boxb(SB, Vector3(0.2, 0.035, 0.12), chunk * Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.24, -0.004, 0.08)), Color(0.46, 0.43, 0.38))
	rng.state = rs
	box(MeshBuilder.new(), Vector3(1.5, 0.55, 0.06), sp + Vector3(0, 1.55, 0), Vector3(0, 0.15, 0), _wood(0.05))   # v7's board drew from rng
	add_obstacle(Vector2(sp.x, sp.z), 0.4, sp.y + 1.8, "路牌", -99.0, false)
	wall_c(Vector2(sp.x, sp.z), 0.08, sp.y - 0.3, sp.y + 1.8, "路牌")

## two_sided: a log can be sat on from either side (facing away from the fire too); can_lie: long enough to
## lie back along it. prop_xf = authored clip prop frame (origin at seat centre on ground).
func _add_seat(name: String, top: Vector3, face: Vector3, front: float, hint: String, two_sided := false, can_lie := false, prop_xf := Transform3D.IDENTITY, approach_override := Vector3.INF) -> void:
	var ap: Vector3
	if approach_override != Vector3.INF:
		ap = approach_override
	else:
		ap = top + face * front
		ap.y = ground_h(ap.x, ap.z)
	var back := top - face * front
	back.y = ground_h(back.x, back.z)
	var pxf := prop_xf
	if pxf == Transform3D.IDENTITY:
		# Derive a prop frame: origin under seat centre, −Z = face (boy yaw 0 faces +Z = −face).
		var yaw := atan2(-face.x, -face.z) + PI
		pxf = Transform3D(Basis(Vector3.UP, yaw), Vector3(top.x, ground_h(top.x, top.z), top.z))
	seats.append({"name": name, "top": top, "face": face, "approach": ap, "back_approach": back, "front": front,
		"hint": hint, "two_sided": two_sided, "can_lie": can_lie, "prop_xf": pxf, "clip_prop": name})

## the weathered sign board: a slab with a chipped corner and a ragged broken end, doodle texture on both faces
func _sign_board(c: Vector3, yaw: float) -> void:
	var outline := PackedVector2Array([
		Vector2(-0.75, -0.25), Vector2(-0.72, -0.28), Vector2(0.44, -0.28), Vector2(0.5, -0.2), Vector2(0.57, -0.22),
		Vector2(0.61, -0.13), Vector2(0.66, -0.1), Vector2(0.64, -0.03), Vector2(0.71, 0.02), Vector2(0.69, 0.08),
		Vector2(0.75, 0.13), Vector2(0.73, 0.2), Vector2(0.75, 0.28), Vector2(-0.69, 0.28), Vector2(-0.75, 0.22)])
	var half := 0.028
	var tris := Geometry2D.triangulate_polygon(outline)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in 2:
		var z := half if face == 0 else -half
		var nrm := Vector3(0, 0, 1 if face == 0 else -1)
		for i in range(0, tris.size(), 3):
			var vs: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for o in 3:
				var v: Vector2 = outline[tris[i + o]]
				var u := (v.x + 0.75) / 1.5
				if face == 1:
					u = 1.0 - u
				vs.append(Vector3(v.x, v.y, z))
				uvs.append(Vector2(u, (0.28 - v.y) / 0.56 * 0.5 + 0.5 * face))
			_tri_facing(st, vs, uvs, nrm)
	# broken / sawn edges: thin strips of the back face's grain
	for i in outline.size():
		var a2: Vector2 = outline[i]
		var b2: Vector2 = outline[(i + 1) % outline.size()]
		var n2 := (b2 - a2).orthogonal().normalized()
		if Geometry2D.is_point_in_polygon((a2 + b2) * 0.5 + n2 * 0.01, outline):
			n2 = -n2
		var nrm2 := Vector3(n2.x, n2.y, 0)
		var ua := (a2.x + 0.75) / 1.5
		var ub := (b2.x + 0.75) / 1.5
		var pa := Vector3(a2.x, a2.y, half)
		var pb := Vector3(b2.x, b2.y, half)
		var qa := Vector3(a2.x, a2.y, -half)
		var qb := Vector3(b2.x, b2.y, -half)
		_tri_facing(st, [pa, pb, qb], [Vector2(ua, 0.6), Vector2(ub, 0.6), Vector2(ub, 0.62)], nrm2)
		_tri_facing(st, [pa, qb, qa], [Vector2(ua, 0.6), Vector2(ub, 0.62), Vector2(ua, 0.62)], nrm2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/sign_board.png")
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	add_child(mi)
	# hangs a little askew off its one good nail
	mi.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -0.07), c)
	sign_board = mi

## Godot culls counter-clockwise triangles, so order each one to face along nrm
func _tri_facing(st: SurfaceTool, vs: Array, uvs: Array, nrm: Vector3) -> void:
	var order := [0, 1, 2]
	if ((vs[1] - vs[0]) as Vector3).cross(vs[2] - vs[0]).dot(nrm) > 0.0:
		order = [0, 2, 1]
	for o: int in order:
		st.set_normal(nrm)
		st.set_uv(uvs[o])
		st.add_vertex(vs[o])

func _crate(c: Vector3, s: float, yaw: float) -> void:
	var xf = Transform3D(Basis(Vector3.UP, yaw), c)
	boxb(SB, Vector3(s, s, s), xf, _wood(-0.05))
	wall_b(Vector2(c.x, c.z), Vector2(s, s) * 0.5, yaw, c.y - s * 0.5, c.y + s * 0.5, "木箱")
	var dark = Color(0.45, 0.31, 0.19)
	for e in [Vector3(0, s * 0.5, 0), Vector3(0, -s * 0.5, 0)]:
		for f in [Vector3(0, 0, s * 0.5), Vector3(0, 0, -s * 0.5)]:
			boxb(SB, Vector3(s * 1.02, s * 0.1, s * 0.1), xf * Transform3D(Basis.IDENTITY, (e + f) * 0.96), dark)
	boxb(SB, Vector3(s * 1.02, s * 0.1, s * 1.15), xf * Transform3D(Basis(Vector3.FORWARD, 0.78), Vector3.ZERO), dark)

func _barrel(p: Vector3) -> void:
	wall_c(Vector2(p.x, p.z), 0.3, p.y - 0.1, p.y + 0.8, "木桶")
	cyl(SB, 0.27, 0.27, 0.8, 9, p + Vector3(0, 0.4, 0), Vector3.ZERO, Color(0.55, 0.36, 0.2))
	for y in [0.12, 0.68]:
		cyl(SB, 0.285, 0.285, 0.06, 9, p + Vector3(0, y, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))
	cyl(SB, 0.3, 0.3, 0.09, 9, p + Vector3(0, 0.4, 0), Vector3.ZERO, Color(0.25, 0.25, 0.27))

## a small double-ended rowboat, built closed: painted outer planking, a wooden inner skin, a capped
## gunwale, end posts, a keel, solid floorboards and two thwarts, so it is solid from every side. Boat space:
## +z bow, y up, the waterline at BOAT_WL. The floorboards sit above the waterline, so the sea (drawn as a
## see-through plane) is always hidden under them and never shows inside the hull
const BOAT_SECS := 17
const BOAT_HALF := 1.7
const BOAT_WL := -0.2
const BOAT_FLOOR := -0.13
const BOAT_SKIN := 0.035

## one hull section at s (-1 stern .. 1 bow): gunwale, chine, keel, chine, gunwale as (x, y)
static func boat_section(s: float, inner: bool) -> Array[Vector2]:
	var w := 0.62 * pow(maxf(1.0 - s * s, 0.0), 0.55) + 0.03
	var dp := 0.42 * (1.0 - 0.35 * s * s)
	var rise := 0.12 * s * s
	var t := BOAT_SKIN if inner else 0.0
	var wg := maxf(w - t, 0.006)
	var wc := maxf(w * 0.85 - t, 0.004)
	var yc := -dp * 0.45 + rise + t * 0.7
	return [Vector2(-wg, 0.18 + rise), Vector2(-wc, yc), Vector2(0.0, -dp + rise + t), Vector2(wc, yc), Vector2(wg, 0.18 + rise)]

## half-width of a section at height y (0 below its keel)
static func boat_half_width(sec: Array[Vector2], y: float) -> float:
	var g := sec[0]
	var c := sec[1]
	var k := sec[2]
	if y <= k.y:
		return 0.0
	if y <= c.y:
		return absf(lerpf(k.x, c.x, (y - k.y) / (c.y - k.y)))
	if y <= g.y:
		return absf(lerpf(c.x, g.x, (y - c.y) / (g.y - c.y)))
	return absf(g.x)

## the hull's outline where it meets the water (boat x/z, starboard half): 17 points, stern to bow
static func boat_waterline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var prev_k := 0.0
	for i in BOAT_SECS:
		var sv := -1.0 + 2.0 * i / (BOAT_SECS - 1)
		var sec := boat_section(sv, false)
		var z := sv * BOAT_HALF
		var ky := sec[2].y
		if i > 0:
			var zp := z - 2.0 * BOAT_HALF / (BOAT_SECS - 1)
			if (prev_k > BOAT_WL) != (ky > BOAT_WL):
				pts.append(Vector2(0.0, lerpf(zp, z, (BOAT_WL - prev_k) / (ky - prev_k))))
		if ky < BOAT_WL:
			pts.append(Vector2(boat_half_width(sec, BOAT_WL), z))
		prev_k = ky
	return pts

func _boat_mesh(mb: MeshBuilder, xf: Transform3D, stripe: Color, seat_c: Array, oar_c: Color) -> void:
	var white := Color(0.95, 0.94, 0.9)
	# alpha 0 marks the inside: the mirror pass (boat.gdshader) paints it the hull colour, since the clipped
	# waterline would otherwise let the bare wood show through in the reflection
	var inner := Color(0.62, 0.45, 0.28, 0.0)
	var cap := Color(0.5, 0.36, 0.23)
	var keel := Color(0.56, 0.52, 0.47)
	var floor_c := Color(0.36, 0.26, 0.17, 0.0)
	var outs: Array = []
	var ins: Array = []
	var zs: Array[float] = []
	for i in BOAT_SECS:
		var sv := -1.0 + 2.0 * i / (BOAT_SECS - 1)
		outs.append(boat_section(sv, false))
		ins.append(boat_section(sv, true))
		zs.append(sv * BOAT_HALF)
	var P := func(q: Vector2, z: float) -> Vector3:
		return xf * Vector3(q.x, q.y, z)
	var up := xf.basis * Vector3.UP
	for i in BOAT_SECS - 1:
		var z0 := zs[i]
		var z1 := zs[i + 1]
		var o0: Array[Vector2] = outs[i]
		var o1: Array[Vector2] = outs[i + 1]
		var n0: Array[Vector2] = ins[i]
		var n1: Array[Vector2] = ins[i + 1]
		for k in 4:
			# outer planking: the top strake in the boat's colour, the bottom white; inner skin bare wood
			var mid: Vector2 = (o0[k] + o1[k + 1]) * 0.5
			var out := xf.basis * Vector3(mid.x, mid.y + 0.1, 0).normalized()
			var col := stripe if (k == 0 or k == 3) else white
			var a: Vector3 = P.call(o0[k], z0)
			var b: Vector3 = P.call(o0[k + 1], z0)
			var c: Vector3 = P.call(o1[k + 1], z1)
			var d: Vector3 = P.call(o1[k], z1)
			mb.face(a, b, c, col, col, col, out)
			mb.face(a, c, d, col, col, col, out)
			var ic := Color(inner.darkened(0.05 if (k == 1 or k == 2) else 0.0), 0.0)
			a = P.call(n0[k], z0)
			b = P.call(n0[k + 1], z0)
			c = P.call(n1[k + 1], z1)
			d = P.call(n1[k], z1)
			mb.face(a, b, c, ic, ic, ic, -out)
			mb.face(a, c, d, ic, ic, ic, -out)
		# gunwale caps join the two skins along the top
		for k: int in [0, 4]:
			var a: Vector3 = P.call(o0[k], z0)
			var b: Vector3 = P.call(n0[k], z0)
			var c: Vector3 = P.call(n1[k], z1)
			var d: Vector3 = P.call(o1[k], z1)
			mb.face(a, b, c, cap, cap, cap, up)
			mb.face(a, c, d, cap, cap, cap, up)
		# keel: a narrow strip under the centre line
		var k0: Vector3 = P.call(o0[2], z0)
		var k1: Vector3 = P.call(o1[2], z1)
		var dn := xf.basis * Vector3(0, -0.05, 0)
		for sx: float in [-1.0, 1.0]:
			var off := xf.basis * Vector3(0.025 * sx, 0, 0)
			mb.face(k0 + off, k1 + off, k1 + off + dn, keel, keel, keel, xf.basis * Vector3(sx, 0, 0))
			mb.face(k0 + off, k1 + off + dn, k0 + off + dn, keel, keel, keel, xf.basis * Vector3(sx, 0, 0))
		var l := xf.basis * Vector3(0.025, 0, 0)
		mb.face(k0 - l + dn, k1 - l + dn, k1 + l + dn, keel, keel, keel, -up)
		mb.face(k0 - l + dn, k1 + l + dn, k0 + l + dn, keel, keel, keel, -up)
		# floorboards: a solid sole over the bilge with five tapering planks on top
		var f0 := boat_half_width(n0, BOAT_FLOOR)
		var f1 := boat_half_width(n1, BOAT_FLOOR)
		if f0 + f1 > 0.0:
			var F := func(x: float, z: float, dy: float) -> Vector3:
				return xf * Vector3(x, BOAT_FLOOR + dy, z)
			mb.face(F.call(-f0, z0, 0.0), F.call(f0, z0, 0.0), F.call(f1, z1, 0.0), floor_c, floor_c, floor_c, up)
			mb.face(F.call(-f0, z0, 0.0), F.call(f1, z1, 0.0), F.call(-f1, z1, 0.0), floor_c, floor_c, floor_c, up)
			for j in 5:
				var pc := Color(inner.lightened(0.06 if j % 2 == 0 else 0.0), 0.0)
				var u0 := -1.0 + 2.0 * (j + 0.07) / 5.0
				var u1 := -1.0 + 2.0 * (j + 0.93) / 5.0
				var a: Vector3 = F.call(u0 * f0, z0, 0.01)
				var b: Vector3 = F.call(u1 * f0, z0, 0.01)
				var c: Vector3 = F.call(u1 * f1, z1, 0.01)
				var d: Vector3 = F.call(u0 * f1, z1, 0.01)
				mb.face(a, b, c, pc, pc, pc, up)
				mb.face(a, c, d, pc, pc, pc, up)
	# close both ends between the skins, then an end post on each
	for e: int in [0, BOAT_SECS - 1]:
		var z := zs[e]
		var o: Array[Vector2] = outs[e]
		var n: Array[Vector2] = ins[e]
		var nz := xf.basis * Vector3(0, 0, signf(z))
		for k in 4:
			var col := stripe if (k == 0 or k == 3) else white
			var a: Vector3 = P.call(o[k], z)
			var b: Vector3 = P.call(o[k + 1], z)
			var c: Vector3 = P.call(n[k + 1], z)
			var d: Vector3 = P.call(n[k], z)
			mb.face(a, b, c, col, col, col, nz)
			mb.face(a, c, d, col, col, col, nz)
		var ky := o[2].y - 0.05
		var ty := o[0].y + 0.06
		boxb(mb, Vector3(0.07, ty - ky, 0.08), xf * Transform3D(Basis.IDENTITY, Vector3(0, (ky + ty) * 0.5, z + signf(z) * 0.02)), cap)
	# thwarts reach the inner skin; an oar lies across them
	var si := 0
	for sz: float in [-0.6, 0.5]:
		var hw := boat_half_width(boat_section(sz / BOAT_HALF, true), 0.06)
		boxb(mb, Vector3(hw * 2.0, 0.05, 0.25), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.06, sz)), Color(seat_c[si], 0.0))
		si += 1
	boxb(mb, Vector3(0.06, 0.04, 2.0), xf * Transform3D(Basis(Vector3.UP, 0.25), Vector3(0.2, 0.105, 0.0)), Color(oar_c, 0.0))

## the beached boat: part of the static mesh
func _boat(p: Vector3, yaw: float, stripe: Color, tilt := 0.0) -> void:
	var xf = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, tilt), p)
	var seat_c := [_wood(), _wood()]
	_boat_mesh(SB, xf, stripe, seat_c, _wood(-0.1))
	add_obstacle(Vector2((xf * Vector3.ZERO).x, (xf * Vector3.ZERO).z), 0.9, p.y + 0.35, "小船", -99.0, false)
	var bow: Vector3 = xf * Vector3(0, 0, 1.25)
	var stern: Vector3 = xf * Vector3(0, 0, -1.25)
	wall_s(Vector2(stern.x, stern.z), Vector2(bow.x, bow.z), 0.64, p.y - 0.6, p.y + 0.4, "小船")

## the rowboat moored by the dock floats on the swell (bob_boat): its own mesh, moved every frame, with the
## mooring line in it. p is where v13's fixed boat stood; the walls and obstacle stay as they were
func _float_boat(p: Vector3, yaw: float, stripe: Color, tie: Vector3) -> void:
	var seat_c := [_wood(), _wood()]
	var mb := MeshBuilder.new()
	_boat_mesh(mb, Transform3D.IDENTITY, stripe, seat_c, _wood(-0.1))
	boat_rest = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, -BOAT_WL, p.z))
	var bow := Vector3(0, 0.3, BOAT_HALF - 0.12)
	# the line sags a little, and its dock end is pinned in boat.gdshader (vertex alpha 0.99 at the bow
	# down to 0.69 at the tie = how far it follows the dock instead of the boat)
	boat_tie = tie
	var tie_l := boat_rest.affine_inverse() * tie
	var n := 6
	for i in n:
		var s0 := float(i) / n
		var s1 := float(i + 1) / n
		var q0 := bow.lerp(tie_l, s0) + Vector3(0, -0.05 * sin(PI * s0), 0)
		var q1 := bow.lerp(tie_l, s1) + Vector3(0, -0.05 * sin(PI * s1), 0)
		tube(mb, q0, q1, 0.02, 0.02, 4, Color(0.85, 0.75, 0.55), 0.99 - 0.3 * s0, 0.99 - 0.3 * s1)
	boat_mat = ShaderMaterial.new()
	boat_mat.shader = load("res://shaders/boat.gdshader")
	boat_mat.set_shader_parameter("hull_col", stripe)
	dock_boat = _mi(mb.commit(), boat_mat)
	dock_boat.transform = boat_rest
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	add_obstacle(Vector2(p.x, p.z), 0.9, p.y + 0.35, "小船", -99.0, false)
	var b2: Vector3 = xf * Vector3(0, 0, 1.25)
	var s2: Vector3 = xf * Vector3(0, 0, -1.25)
	wall_s(Vector2(s2.x, s2.z), Vector2(b2.x, b2.z), 0.64, p.y - 0.6, p.y + 0.4, "小船")

## the sea as drawn (water.gdshader on a 1200 m PlaneMesh with 161 cells a side): linear between the plane's
## vertices, which can be a few cm off sea_y. Matches uw_shown_y in underwater.gdshaderinc
static func shown_sea_y(x: float, z: float, t: float) -> float:
	var cell := 1200.0 / 161.0
	var gx := (x + 600.0) / cell
	var gz := (z + 600.0) / cell
	var ix := floorf(gx)
	var iz := floorf(gz)
	var fx := gx - ix
	var fz := gz - iz
	var x0 := ix * cell - 600.0
	var z0 := iz * cell - 600.0
	var h10 := sea_y(x0 + cell, z0, t)
	var h01 := sea_y(x0, z0 + cell, t)
	if fx + fz <= 1.0:
		var h00 := sea_y(x0, z0, t)
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	var h11 := sea_y(x0 + cell, z0 + cell, t)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)

## heave, pitch and roll after the water under the bow, stern and both sides, through a soft spring (a
## moored boat lags the swell a little and rocks on), plus a slow rock of its own
func _bob_boat(t: float) -> void:
	if dock_boat == null:
		return
	var dt := clampf(t - boat_t, 0.0, 0.1)
	boat_t = t
	var b := boat_rest.basis
	var c := boat_rest.origin
	var hs: Array[float] = []
	for q: Vector3 in [Vector3(0, 0, 1.3), Vector3(0, 0, -1.3), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0)]:
		var w := c + b * q
		hs.append(shown_sea_y(w.x, w.z, t))
	var tgt := Vector3((hs[0] + hs[1] + hs[2] + hs[3]) * 0.25 + 0.004 * sin(t * 2.1),
		atan2(hs[0] - hs[1], 2.6) + 0.008 * sin(t * 1.1 + 0.5),
		atan2(hs[2] - hs[3], 1.0) + 0.022 * sin(t * 1.7) + 0.008 * sin(t * 2.9 + 1.0))
	if boat_t0 < 0.0 or dt <= 0.0:
		boat_t0 = t
		boat_q = tgt
		boat_v = Vector3.ZERO
	else:
		var w0 := TAU / 1.7
		var acc := (tgt - boat_q) * w0 * w0 - boat_v * (2.0 * 0.45 * w0)
		boat_v += acc * dt
		boat_q += boat_v * dt
	dock_boat.transform = Transform3D(b * Basis(Vector3.RIGHT, -boat_q.y) * Basis(Vector3.BACK, boat_q.z), c + Vector3(0, boat_q.x, 0))
	boat_mat.set_shader_parameter("pin", dock_boat.transform.affine_inverse() * boat_rest)

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
	lamps.append([hp, "porch"])
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
	add_obstacle(c2, 2.6, base.y + floor_y + wall_h + 1.4, "钓鱼小屋", -99.0, false)
	var hc: Vector3 = xf * Vector3(0, 0, 0.65)
	wall_b(Vector2(hc.x, hc.z), Vector2(1.95, 2.3), yaw, base.y - 2.0, base.y + floor_y + wall_h + 1.4, "钓鱼小屋")
	var stc: Vector3 = xf * Vector3(0.45, 0, 3.55)
	wall_b(Vector2(stc.x, stc.z), Vector2(0.58, 0.62), yaw, base.y - 2.0, base.y + floor_y, "钓鱼小屋")
	wall_s(Vector2(n0.x, n0.z), Vector2(n1.x, n1.z), 0.07, minf(n0.y, n1.y) - 0.2, n0.y + 2.0, "渔网")

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
	beacon_pos = p + Vector3(0, h + 0.5, 0)
	cyl(SB, 0.0, 0.7, 0.75, 10, p + Vector3(0, h + 1.25, 0), Vector3.ZERO, Color(0.86, 0.25, 0.22))
	blob(SB, p + Vector3(0, h + 1.68, 0), Vector3(0.08, 0.08, 0.08), Color(0.9, 0.8, 0.3), 0.0, 6, 3, 0.0)
	cyl(SB, 0.06, 0.06, 0.6, 6, p + Vector3(0.35, 0.9, 0.95), Vector3.ZERO, Color(0.3, 0.22, 0.15))
	box(SB, Vector3(0.55, 1.0, 0.06), p + Vector3(0.0, 0.95, 0.96), Vector3.ZERO, Color(0.35, 0.5, 0.62))
	add_obstacle(Vector2(p.x, p.z), 1.3, p.y + h + 1.7, "灯塔", -99.0, false)
	wall_c(Vector2(p.x, p.z), 1.38, p.y - 1.0, p.y + h + 1.7, "灯塔")
	# Bench looking out to sea — ALWAYS use props/bench_v25.glb (prop frame = Godot axes:
	# seat top 0.22, depth 0.26 on z=0, width 1.40, backrest on +Z). Flat pad under footprint.
	var bp = p + Vector3(-2.2, 0, -2.0)
	bp.y = ground_h(bp.x, bp.z)
	var bxf = Transform3D(Basis(Vector3.UP, 0.7), bp)
	var bench_n := _spawn_prop_glb("res://props/bench_v25.glb", bxf, Color(0.58, 0.40, 0.26))
	if bench_n:
		bench_n.name = "bench_v25"
	if bench_n == null:
		push_warning("Island: bench_v25.glb missing — procedural fallback")
		var seat_y := SEAT_TOP - 0.025
		boxb(SB, Vector3(1.40, 0.05, 0.26), bxf * Transform3D(Basis.IDENTITY, Vector3(0, seat_y, 0)), _wood())
		boxb(SB, Vector3(1.35, 0.18, 0.035), bxf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(0, SEAT_TOP + 0.10, 0.13)), Color(0.55, 0.38, 0.24))
		for bx in [-0.6, 0.6]:
			boxb(SB, Vector3(0.07, SEAT_TOP, 0.22), bxf * Transform3D(Basis.IDENTITY, Vector3(bx, SEAT_TOP * 0.5, 0.0)), Color(0.42, 0.29, 0.18))
	var bc: Vector3 = bxf * Vector3(0, 0, 0)
	wall_b(Vector2(bc.x, bc.z), Vector2(0.72, 0.20), 0.7, bp.y - 0.3, bp.y + 0.75, "长椅")
	var bface: Vector3 = (bxf.basis * Vector3(0, 0, -1)).normalized()
	# Prop origin = seat centre on the (flat) ground; approach shares prop-frame Y.
	var bench_top: Vector3 = bxf * Vector3(0, SEAT_TOP, 0)
	var bench_ap: Vector3 = bxf * Vector3(0, 0, -0.50)
	bench_ap.y = bp.y
	_add_seat("长椅", bench_top, bface, 0.7, "灯塔边的长椅：点「坐下」看看海", false, false, bxf, bench_ap)

func _build_campfire() -> void:
	var c = campfire_pos
	wall_c(Vector2(c.x, c.z), 0.82, c.y - 0.5, c.y + 0.9, "篝火")
	for i in 9:
		var a = TAU * i / 9.0
		blob(SB, gp(c.x + cos(a) * 0.65, c.z + sin(a) * 0.65) + Vector3(0, 0.08, 0), Vector3(0.17, 0.12, 0.15), Color(0.5, 0.48, 0.45))
	# charred logs in a little teepee: black where they burn, grey ash further out, glowing tips in the coals
	var char_c := Color(0.09, 0.075, 0.065)
	var rs := rng.state   # keep the rest of the island's random layout as it was
	for i in 5:
		var a = i * TAU / 5.0 + 0.3
		var foot = gp(c.x + cos(a) * 0.5, c.z + sin(a) * 0.5) + Vector3(0, 0.06, 0)
		var tip = c + Vector3(-cos(a) * 0.08, 0.36 + 0.04 * (i % 2), -sin(a) * 0.08)
		tube(SB, foot, tip, 0.065, 0.05, 6, Color(0.36, 0.33, 0.3), 1.0, 1.0, char_c)
		blob(GB, foot.lerp(tip, 0.82), Vector3(0.045, 0.04, 0.045), Color(1.0, 0.42, 0.1), 0.1, 5, 3, 0.0)
	for i in 2:
		var a2 = 1.1 + i * 2.6
		tube(SB, gp(c.x + cos(a2) * 0.42, c.z + sin(a2) * 0.42) + Vector3(0, 0.07, 0), gp(c.x - cos(a2) * 0.25, c.z - sin(a2) * 0.25) + Vector3(0, 0.08, 0), 0.06, 0.06, 6, char_c, 1.0, 1.0, Color(0.3, 0.28, 0.26))
	rng.state = rs
	campfire = Campfire.new()
	add_child(campfire)
	campfire.position = c
	campfire.build()
	for i in 3:
		var a = 0.6 + i * 2.1
		var lp = c + Vector3(cos(a) * 1.7, 0, sin(a) * 1.7)
		lp.y = ground_h(lp.x, lp.z)
		# v25 authored log_v25.glb: cylinder axis along local +X, axis_y=0.10, r=0.12, top=0.22.
		var log_r := 0.12
		var axis_y := 0.10
		var to_fire := Vector3(c.x - lp.x, 0, c.z - lp.z).normalized()
		# Prop frame: origin at ground under log centre; −Z faces the fire (boy sits facing −Z).
		var log_yaw := atan2(-to_fire.x, -to_fire.z) + PI
		var lxf := Transform3D(Basis(Vector3.UP, log_yaw), lp)
		var log_n := _spawn_prop_glb("res://props/log_v25.glb", lxf, Color(0.50, 0.34, 0.20))
		if log_n:
			log_n.name = "log_v25_%d" % i
		if log_n == null:
			push_warning("Island: log_v25.glb missing — procedural fallback")
			var la: Vector3 = lxf * Vector3(-0.7, axis_y, 0)
			var lb: Vector3 = lxf * Vector3(0.7, axis_y, 0)
			tube(SB, la, lb, log_r, log_r, 7, Color(0.5, 0.34, 0.2), 1.0, 1.0, Color(0.6, 0.45, 0.3))
		wall_s(Vector2((lxf * Vector3(-0.7, 0, 0)).x, (lxf * Vector3(-0.7, 0, 0)).z),
			Vector2((lxf * Vector3(0.7, 0, 0)).x, (lxf * Vector3(0.7, 0, 0)).z),
			log_r + 0.01, lp.y - 0.3, lp.y + SEAT_TOP + 0.25, "坐木")
		var log_top: Vector3 = lxf * Vector3(0, SEAT_TOP, 0)
		var log_ap: Vector3 = lxf * Vector3(0, 0, -0.50)
		log_ap.y = lp.y
		_add_seat("坐木", log_top, to_fire, 0.45, "篝火边的木头：点「坐下」烤烤火", true, false, lxf, log_ap)
	# tiki torches
	for a in [1.5, -1.6]:
		var tp = c + Vector3(cos(a) * 2.6, 0, sin(a) * 2.6)
		tp.y = ground_h(tp.x, tp.z)
		wall_c(Vector2(tp.x, tp.z), 0.07, tp.y - 0.2, tp.y + 2.0, "火把")
		_torch(tp, torches.size())

## Lathe a smooth tube through ring centres `cs` (radii `rs`); `colf.call(ring, side)` gives each vertex colour.
func _lathe(b: MeshBuilder, cs: Array, rs: Array, seg: int, colf: Callable, cap := false, jit := 0.0) -> void:
	var rings: Array = []
	for i in cs.size():
		var ax: Vector3 = ((cs[mini(i + 1, cs.size() - 1)] as Vector3) - (cs[maxi(i - 1, 0)] as Vector3)).normalized()
		var u := ax.cross(Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.FORWARD).normalized()
		var v := ax.cross(u)
		var ring: Array = []
		for j in seg:
			var a := TAU * j / seg
			var d := u * cos(a) + v * sin(a)
			var jr := 1.0 + jit * (_fract(sin(i * 12.9898 + j * 78.233) * 43758.5453) * 2.0 - 1.0)
			ring.append([(cs[i] as Vector3) + d * float(rs[i]) * jr, d, colf.call(i, j)])
		rings.append(ring)
	for i in cs.size() - 1:
		for j in seg:
			var j1 := (j + 1) % seg
			var A: Array = rings[i][j]
			var B: Array = rings[i][j1]
			var C: Array = rings[i + 1][j1]
			var D: Array = rings[i + 1][j]
			b.tri_sm(A[0], B[0], C[0], A[1], B[1], C[1], A[2], B[2], C[2])
			b.tri_sm(A[0], C[0], D[0], A[1], C[1], D[1], A[2], C[2], D[2])
	if cap:
		var last: Array = rings[cs.size() - 1]
		var top: Vector3 = cs[cs.size() - 1]
		var n := (top - (cs[cs.size() - 2] as Vector3)).normalized()
		for j in seg:
			var A: Array = last[j]
			var B: Array = last[(j + 1) % seg]
			b.tri_sm(top, A[0], B[0], n, n, n, A[2], A[2], B[2])

## A twine/cloth band: a thin torus round `c` about `ax`, its tube radius `r` squashed along the axis by `flat`.
func _band(b: MeshBuilder, c: Vector3, ax: Vector3, R: float, r: float, col: Color, seg := 12, flat := 1.0, col2 = null) -> void:
	var u := ax.cross(Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.FORWARD).normalized()
	var v := ax.cross(u)
	var sides := 4
	var pts: Array = []
	for i in seg + 1:
		var a := TAU * i / seg
		var d := u * cos(a) + v * sin(a)
		var row: Array = []
		for k in sides:
			var q := TAU * k / sides + PI / sides
			var n := (d * cos(q) + ax * sin(q)).normalized()
			row.append([c + d * (R + r * cos(q)) + ax * (r * flat * sin(q)), n])
		pts.append(row)
	for i in seg:
		var ci: Color = col if col2 == null or i % 2 == 0 else col2
		for k in sides:
			var k1 := (k + 1) % sides
			var A: Array = pts[i][k]
			var B: Array = pts[i + 1][k]
			var C: Array = pts[i + 1][k1]
			var D: Array = pts[i][k1]
			b.tri_sm(A[0], B[0], C[0], A[1], B[1], C[1], ci, ci, ci)
			b.tri_sm(A[0], C[0], D[0], A[1], C[1], D[1], ci, ci, ci)

## A tiki torch: a weathered, cracked pole; a bamboo cup lashed on with twine; an oil-soaked cloth wick
## wound into the cup with a singed tail hanging over the rim. The flame, embers and light are a Torch node.
func _torch(tp: Vector3, idx: int) -> void:
	var lr := RandomNumberGenerator.new()
	lr.seed = 7100 + idx * 31
	var top_y := 1.5
	# pole: slightly crooked, thicker at the foot, grey-brown weathered grain with a damp dark foot
	var cs: Array = []
	var rs: Array = []
	var nr := 9
	var bend := Vector3(lr.randf_range(-1, 1), 0, lr.randf_range(-1, 1)).normalized() * 0.025
	for i in nr:
		var f := float(i) / (nr - 1)
		cs.append(tp + Vector3(0, -0.12 + (top_y + 0.12) * f, 0) + bend * sin(f * PI) + Vector3(0.004 * sin(f * 11.0 + idx), 0, 0.004 * cos(f * 9.0)))
		rs.append(lerpf(0.046, 0.035, f) * (1.0 + 0.04 * sin(f * 17.0 + idx * 2.0)))
	var grain: Array = []
	for j in 12:
		grain.append(lr.randf_range(-0.07, 0.07))
	var wood := Color(0.58, 0.5, 0.4)
	var colf := func(i: int, j: int) -> Color:
		var f := float(i) / (nr - 1)
		var g: float = grain[j] + 0.035 * sin(j * 2.3 + i * 1.7)
		var c0 := Color(wood.r + g, wood.g + g * 0.9, wood.b + g * 0.75)
		c0 = c0.lerp(Color(0.28, 0.23, 0.18), (1.0 - smoothstep(0.0, 0.16, f)) * 0.7)
		return c0.lerp(Color(0.3, 0.24, 0.18), smoothstep(0.9, 1.0, f) * 0.35)
	_lathe(TB, cs, rs, 12, colf)
	# cracks: dark, slightly sunken-looking slivers running with the grain
	for k in 4:
		var a0 := lr.randf() * TAU
		var y0 := lr.randf_range(0.15, 1.1)
		var ln := lr.randf_range(0.14, 0.32)
		var prev := Vector3.ZERO
		var steps := 5
		for s in steps + 1:
			var f := (y0 + ln * s / steps + 0.12) / (top_y + 0.12)
			var a := a0 + 0.05 * sin(s * 2.1 + k)
			var r := lerpf(0.046, 0.035, f) + 0.0012
			var cpos := tp + Vector3(0, y0 + ln * s / steps, 0) + bend * sin(f * PI) + Vector3(cos(a), 0, sin(a)) * r
			if s > 0:
				var out := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-sin(a), 0, cos(a)) * (0.0035 * sin(PI * s / steps) + 0.001)
				var cc := Color(0.13, 0.1, 0.08)
				TB.face(prev - side, prev + side, cpos + side, cc, cc, cc, out)
				TB.face(prev - side, cpos + side, cpos - side, cc, cc, cc, out)
			prev = cpos
	var head := tp + Vector3(0, top_y, 0) + bend * 0.0
	# bamboo cup: a closed node at the bottom, a raised node ring, a cut rim and a dark inside
	var cup_b := head + Vector3(0, -0.05, 0)
	var cup_h := 0.23
	var bamboo := Color(0.7, 0.6, 0.38)
	var bcol := func(i: int, j: int) -> Color:
		var g := 0.07 * sin(j * 3.7 + idx) + 0.04 * sin(j * 1.3) + (0.05 if j % 3 == 0 else 0.0)
		var c0 := Color(bamboo.r + g, bamboo.g + g, bamboo.b + g * 0.6)
		# oil runs and soot darken the cup towards the rim, unevenly round it
		var soot_k: float = [0.0, 0.05, 0.25, 0.7][i] * (0.75 + 0.25 * sin(j * 2.2 + idx))
		return c0.lerp(Color(0.2, 0.15, 0.1), soot_k)
	_lathe(TB, [cup_b + Vector3(0, -0.03, 0), cup_b, cup_b + Vector3(0, cup_h * 0.5, 0), cup_b + Vector3(0, cup_h, 0)], [0.042, 0.061, 0.063, 0.062], 14, bcol)
	_lathe(TB, [cup_b + Vector3(0, cup_h, 0), cup_b + Vector3(0, cup_h * 0.55, 0)], [0.054, 0.054], 14, func(_i: int, _j: int) -> Color: return Color(0.2, 0.15, 0.1))
	_band(TB, cup_b + Vector3(0, cup_h, 0), Vector3.UP, 0.058, 0.0045, Color(0.78, 0.68, 0.46), 14, 0.6)
	_band(TB, cup_b + Vector3(0, 0.125, 0), Vector3.UP, 0.0625, 0.0055, Color(0.62, 0.52, 0.32), 14, 0.5)
	# twine lashing: tight turns round the pole under the cup and round the cup's foot, two cross strands
	var twine := Color(0.68, 0.58, 0.42)
	var twine2 := Color(0.58, 0.49, 0.35)
	for k in 7:
		var y := -0.21 + k * 0.011
		_band(TB, head + Vector3(0, y, 0), Vector3(0.06 * sin(k * 1.9), 1, 0.06 * cos(k * 1.3)).normalized(), 0.0365, 0.0042, twine if k % 2 == 0 else twine2, 10, 1.0, twine2)
	for k in 4:
		var y := -0.035 + k * 0.012
		_band(TB, head + Vector3(0, y, 0), Vector3(0.05 * sin(k * 2.7), 1, 0.05 * cos(k * 1.1)).normalized(), 0.0625, 0.0042, twine, 14, 1.0, twine2)
	for k in 2:
		var a := 0.8 + k * PI + idx
		var p0 := head + Vector3(cos(a) * 0.039, -0.14, sin(a) * 0.039)
		var p1 := head + Vector3(cos(a + 0.9) * 0.05, -0.04, sin(a + 0.9) * 0.05)
		tube(TB, p0, p1, 0.004, 0.004, 4, twine, 0.0, 0.0)
	# oil-soaked cloth wick: a ragged rag bundle stuffed in the cup and bulging over the rim, wound
	# with a few tilted wraps whose singed edges catch the light, charred black where it burns
	var wb := cup_b + Vector3(0, cup_h - 0.03, 0)
	var soot := Color(0.17, 0.12, 0.09)
	var singe := Color(0.42, 0.33, 0.23)
	var rag := Color(0.3, 0.22, 0.15)
	_lathe(TB, [wb, wb + Vector3(0, 0.035, 0), wb + Vector3(0, 0.07, 0), wb + Vector3(0, 0.1, 0), wb + Vector3(0, 0.122, 0)], [0.05, 0.064, 0.06, 0.045, 0.016], 11,
		func(i: int, j: int) -> Color: return rag.lerp(singe, 0.35 * float((j * 7 + i * 3) % 4 == 0)).lerp(Color(0.07, 0.055, 0.045), float([0.0, 0.1, 0.35, 0.8, 1.0][i])), true, 0.12)
	for k in 3:
		var tilt := Vector3(0.18 * sin(k * 2.4 + idx), 1, 0.18 * cos(k * 1.7 + idx)).normalized()
		var ry := 0.02 + 0.027 * k
		_band(TB, wb + Vector3(0, ry, 0), tilt, [0.06, 0.059, 0.05][k], 0.009, rag.lerp(singe, 0.25 - 0.1 * k).lerp(soot, 0.25 * k), 16, 0.9 + 0.4 * k)
	var ta := lr.randf() * TAU
	var tail := [wb + Vector3(cos(ta) * 0.062, 0.045, sin(ta) * 0.062), wb + Vector3(cos(ta) * 0.071, 0.0, sin(ta) * 0.071), wb + Vector3(cos(ta + 0.12) * 0.069, -0.07, sin(ta + 0.12) * 0.069)]
	for s in 2:
		var p0: Vector3 = tail[s]
		var p1: Vector3 = tail[s + 1]
		var out := Vector3(cos(ta), 0, sin(ta))
		var side := Vector3(-sin(ta), 0, cos(ta)) * (0.017 - 0.004 * s)
		var cc := soot.lerp(singe, 0.5 * s)
		TB.face(p0 - side, p0 + side, p1 + side * 0.8, soot, soot, cc, out)
		TB.face(p0 - side, p1 + side * 0.8, p1 - side * 0.8, soot, cc, cc, out)
		TB.face(p0 - side, p0 + side, p1 + side * 0.8, soot, soot, cc, -out)
		TB.face(p0 - side, p1 + side * 0.8, p1 - side * 0.8, soot, cc, cc, -out)
	GB.prim(_sphm(6, 3), Transform3D(Basis.IDENTITY.scaled(Vector3(0.02, 0.01, 0.02)), wb + Vector3(0, 0.118, 0)), Color(1.0, 0.5, 0.14))
	var tn := Torch.new()
	add_child(tn)
	tn.position = wb + Vector3(0, 0.1, 0)
	tn.build(float(idx) * 3.1)
	tn.slot = idx
	torches.append(tn)

# ------------------------------------------------------------------ beach life

func _build_beach_life() -> void:
	# beached boat
	var bth = -0.75
	var bp = shore_pt(bth, 1.6)
	_boat(bp + Vector3(0, 0.12, 0), atan2(dir_at(bth).x, dir_at(bth).z) + 0.3, Color(0.9, 0.45, 0.25), 0.14)
	# umbrella + towel + deck chair
	var up = shore_pt(-0.15, 4.0)
	umbrella_pos = up
	wall_c(Vector2(up.x, up.z), 0.06, up.y - 0.2, up.y + 2.5, "遮阳伞")
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
	# Beach chaise: clear of the towel/umbrella/bushes, facing the sea/sun, legs on sand.
	var side_beach: Vector3 = out.cross(Vector3.UP).normalized()
	# Slightly more seaward + lateral so the backrest clears inland foliage.
	var cp = tw + side_beach * 1.55 + out * 0.55
	cp.y = ground_h(cp.x, cp.z)
	var cxf = Transform3D(Basis(Vector3.UP, tyaw), cp)
	lounger_xf = cxf
	lounger_seat_tilt = 0.08
	lounger_back_tilt = 0.70  # ~40°; head rises away from the seat (−local Z)
	lounger_seat_local = Vector3(0, 0.34, 0.08)
	# Pad raised clear of the crease so thighs rest ON the seat surface.
	lounger_back_local = Vector3(0, 0.92, -0.78)
	lounger_seat_half = Vector3(0.32, 0.03, 0.55)
	lounger_back_half = Vector3(0.32, 0.04, 0.55)
	var lc: Vector3 = cxf * Vector3(0, 0, -0.05)
	wall_b(Vector2(lc.x, lc.z), Vector2(0.36, 0.75), tyaw, cp.y - 0.3, cp.y + 1.1, "躺椅")
	var lface: Vector3 = cxf.basis * Vector3(1, 0, 0)
	if lface.dot(towel_pos - cp) > 0.0:
		lface = -lface
	_add_seat("躺椅", cp + lface * 0.12 + Vector3(0, 0.36, 0) + cxf.basis * Vector3(0, 0, 0.15), lface, 0.55, "蓝色躺椅：点「坐下」歇一会儿")
	var wood := Color(0.72, 0.55, 0.32)
	var cush := Color(0.28, 0.52, 0.82)
	# Four legs down to the sand.
	for lx in [-0.28, 0.28]:
		for lz in [-0.42, 0.48]:
			var leg_h: float = 0.34
			boxb(SB, Vector3(0.045, leg_h, 0.045), cxf * Transform3D(Basis.IDENTITY, Vector3(lx, leg_h * 0.5, lz)), wood)
	# Seat frame + ~7 cm cushion (legs lie ON TOP; 2–4 cm compress max).
	boxb(SB, Vector3(0.68, 0.04, 1.12), cxf * Transform3D(Basis(Vector3.RIGHT, lounger_seat_tilt), lounger_seat_local + Vector3(0, -0.04, 0)), wood)
	boxb(SB, Vector3(0.64, 0.06, 1.08), cxf * Transform3D(Basis(Vector3.RIGHT, lounger_seat_tilt), lounger_seat_local), cush)
	# Backrest frame + cushion (~40°) — torso/head rest on the pad surface.
	boxb(SB, Vector3(0.68, 0.04, 1.18), cxf * Transform3D(Basis(Vector3.RIGHT, lounger_back_tilt), lounger_back_local + Vector3(0, -0.04, 0)), wood)
	boxb(SB, Vector3(0.64, 0.08, 1.14), cxf * Transform3D(Basis(Vector3.RIGHT, lounger_back_tilt), lounger_back_local), cush)
	# Armrests — outboard of the cushion so heels stay clear of the rails.
	for lx2 in [-0.40, 0.40]:
		boxb(SB, Vector3(0.045, 0.04, 0.7), cxf * Transform3D(Basis.IDENTITY, Vector3(lx2, 0.48, 0.05)), wood)
	# surfboard stuck in the sand
	var sp = shore_pt(0.55, 3.5)
	wall_c(Vector2(sp.x, sp.z), 0.17, sp.y - 0.2, sp.y + 2.0, "冲浪板")
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
			var k := rng.randf_range(0.6, 1.4)
			blob(SB, p, Vector3(0.35, 0.25, 0.3) * k, Color(0.55, 0.54, 0.5))
			wall_c(Vector2(p.x, p.z), 0.3 * k, p.y - 0.3, p.y + 0.25 * k, "石头")
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
			var k2 := rng.randf_range(0.6, 1.6)
			blob(SB, p, Vector3(0.35, 0.22, 0.3) * k2, Color(0.5, 0.52, 0.48))
			wall_c(Vector2(p.x, p.z), 0.3 * k2, p.y - 0.3, p.y + 0.22 * k2, "石头")

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
	# Hammock between the hut pair — authored hammock_v25 at the game anchors.
	# Prop frame: origin = midpoint, +X = a→b, +Y up, +Z = ab × up (inland).
	var a = h1 + Vector3(0, 1.05, 0)
	var b = h2 + Vector3(0, 1.05, 0)
	hammock_a = a
	hammock_b = b
	var mid = (a + b) * 0.5
	var along := (b - a).normalized()
	var up := Vector3.UP
	var inland := along.cross(up).normalized()
	if inland.length_squared() < 1e-6:
		inland = Vector3.FORWARD
	hammock_node = Node3D.new()
	hammock_node.transform = Transform3D(Basis(along, up, inland), mid)
	add_child(hammock_node)
	_setup_hammock_v25()
	# Full fabric footprint so the boy cannot walk through the hammock.
	var qa: Vector3 = a.lerp(b, 0.12)
	var qb: Vector3 = a.lerp(b, 0.88)
	var ham_mid: Vector3 = mid
	var ham_along: Vector3 = along
	var ham_yaw := atan2(ham_along.x, ham_along.z)
	var ham_len := a.distance_to(b) * 0.76
	hammock_half_w = 0.50
	wall_s(Vector2(qa.x, qa.z), Vector2(qb.x, qb.z), hammock_half_w + 0.06, ham_mid.y - 1.1, ham_mid.y + 0.55, "吊床")
	wall_b(Vector2(ham_mid.x, ham_mid.z), Vector2(hammock_half_w + 0.04, ham_len * 0.5), ham_yaw, ham_mid.y - 1.0, ham_mid.y + 0.5, "吊床")


func _spawn_prop_glb(path: String, xf: Transform3D, wood_tint := Color(0.55, 0.38, 0.24)) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var n: Node3D = packed.instantiate() as Node3D
	if n == null:
		return null
	n.transform = xf
	# Authored GLBs ship untextured/white — tint wood props so they read as timber, not boxes.
	if wood_tint.a > 0.0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = wood_tint
		mat.roughness = 0.85
		mat.metallic = 0.0
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(n)
	return n


func _setup_hammock_v25() -> void:
	hammock_prop_xf = hammock_node.global_transform
	hammock_use_v25 = false
	var path := "res://props/hammock_v25_static.glb"
	if not ResourceLoader.exists(path):
		path = "res://props/hammock_v25.glb"
	if not ResourceLoader.exists(path):
		push_warning("Island: missing hammock_v25 — falling back to procedural cloth")
		_setup_hammock_procedural_fallback()
		return
	var packed := load(path) as PackedScene
	var root: Node3D = packed.instantiate() as Node3D
	hammock_node.add_child(root)
	# Find cloth MeshInstance (largest surface / named).
	hammock_cloth_mi = _find_cloth_mi(root)
	if hammock_cloth_mi == null:
		push_warning("Island: hammock_v25 has no cloth mesh")
		_setup_hammock_procedural_fallback()
		return
	hammock_mi = hammock_cloth_mi
	hammock_cloth_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hammock_cloth_mat = hammock_cloth_mi.get_active_material(0)
	if hammock_cloth_mi.mesh:
		hammock_cloth_fmt = 0
		if hammock_cloth_mi.mesh is ArrayMesh:
			hammock_cloth_fmt = (hammock_cloth_mi.mesh as ArrayMesh).surface_get_format(0)
	_load_hammock_cloth_frames()
	# Cache bind (empty) verts so we can restore after exit.
	if hammock_cloth_mi and hammock_cloth_mi.mesh is ArrayMesh:
		var arr0: Array = (hammock_cloth_mi.mesh as ArrayMesh).surface_get_arrays(0)
		if arr0.size() > Mesh.ARRAY_VERTEX and arr0[Mesh.ARRAY_VERTEX] != null:
			hammock_cloth_bind = (arr0[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	_build_hammock_cloth_remap()
	hammock_use_v25 = hammock_cloth_bytes.size() > 0 and hammock_cloth_remap.size() == hammock_cloth_bind.size()
	set_hammock_clip_frame("empty", 0)


func _find_cloth_mi(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := String(mi.name).to_lower()
		if nm.find("cloth") >= 0 or nm.find("hammock") >= 0:
			return mi
	for c in n.get_children():
		var f := _find_cloth_mi(c)
		if f:
			return f
	# Fallback: first MeshInstance3D with many verts.
	var best: MeshInstance3D = null
	var best_n := 0
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi2 := c as MeshInstance3D
		if mi2.mesh == null:
			continue
		var vc := 0
		if mi2.mesh is ArrayMesh:
			var arr: Array = (mi2.mesh as ArrayMesh).surface_get_arrays(0)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
				vc = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if vc > best_n:
			best_n = vc
			best = mi2
	return best


func _load_hammock_cloth_frames() -> void:
	hammock_cloth_meta = {}
	hammock_cloth_bytes = PackedByteArray()
	# Use res:// paths (not globalize_path) so packed web exports can read them.
	var meta_path := "res://props/hammock_cloth_meta.json"
	var bin_path := "res://props/hammock_cloth_frames.bin"
	if not FileAccess.file_exists(meta_path):
		return
	var f := FileAccess.open(meta_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	hammock_cloth_meta = parsed
	var bf := FileAccess.open(bin_path, FileAccess.READ)
	if bf == null:
		return
	hammock_cloth_bytes = bf.get_buffer(bf.get_length())
	bf.close()


## Map Godot-imported mesh verts → authoring/npz indices (import may reorder).
func _build_hammock_cloth_remap() -> void:
	hammock_cloth_remap = PackedInt32Array()
	if hammock_cloth_bind.is_empty():
		return
	var auth_path := "res://props/hammock_cloth_bind_auth.bin"
	if not FileAccess.file_exists(auth_path):
		push_warning("Island: missing hammock_cloth_bind_auth.bin — cloth remap skipped")
		return
	var af := FileAccess.open(auth_path, FileAccess.READ)
	if af == null:
		return
	var raw := af.get_buffer(af.get_length())
	af.close()
	var V := hammock_cloth_bind.size()
	if raw.size() < V * 12:
		push_warning("Island: hammock bind_auth size mismatch")
		return
	var auth := PackedVector3Array()
	auth.resize(V)
	for i in V:
		var b := i * 12
		auth[i] = Vector3(raw.decode_float(b), raw.decode_float(b + 4), raw.decode_float(b + 8))
	hammock_cloth_remap.resize(V)
	var max_d := 0.0
	for i in V:
		var p: Vector3 = hammock_cloth_bind[i]
		var best := 0
		var best_d := p.distance_squared_to(auth[0])
		for j in range(1, V):
			var d := p.distance_squared_to(auth[j])
			if d < best_d:
				best_d = d
				best = j
		hammock_cloth_remap[i] = best
		max_d = maxf(max_d, sqrt(best_d))
	print("Island: hammock cloth remap max dist %.4f m" % max_d)
	if max_d > 0.05:
		push_warning("Island: hammock cloth remap max dist %.3f m" % max_d)


## Drive cloth vertices from authored npz frames (hammock-local). clip="" / "empty" = bind pose.
func set_hammock_clip_frame(clip: String, frame: int) -> void:
	if not hammock_use_v25 or hammock_cloth_mi == null:
		return
	if clip == "" or clip == "empty" or not hammock_cloth_meta.has(clip):
		hammock_clip = ""
		if hammock_cloth_bind.size() > 0:
			_apply_hammock_verts(hammock_cloth_bind)
		return
	var info: Dictionary = hammock_cloth_meta[clip]
	var F: int = int(info["frames"])
	var V: int = int(info["verts"])
	var off: int = int(info["offset"])
	frame = clampi(frame, 0, F - 1)
	var need := V * 3 * 4
	var start := off + frame * need
	if start + need > hammock_cloth_bytes.size():
		return
	if hammock_cloth_remap.size() != hammock_cloth_bind.size():
		return
	var verts := PackedVector3Array()
	verts.resize(hammock_cloth_bind.size())
	for i in hammock_cloth_bind.size():
		var src: int = hammock_cloth_remap[i]
		var b := start + src * 12
		verts[i] = Vector3(
			hammock_cloth_bytes.decode_float(b),
			hammock_cloth_bytes.decode_float(b + 4),
			hammock_cloth_bytes.decode_float(b + 8))
	_apply_hammock_verts(verts)
	hammock_clip = clip


func _apply_hammock_verts(verts: PackedVector3Array) -> void:
	var mesh := hammock_cloth_mi.mesh
	if mesh == null or not (mesh is ArrayMesh):
		return
	var am := mesh as ArrayMesh
	var arrays: Array = am.surface_get_arrays(0)
	if arrays.is_empty():
		return
	arrays[Mesh.ARRAY_VERTEX] = verts
	var rebuilt := ArrayMesh.new()
	rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, hammock_cloth_fmt)
	if hammock_cloth_mat:
		rebuilt.surface_set_material(0, hammock_cloth_mat)
	elif am.get_surface_count() > 0:
		rebuilt.surface_set_material(0, am.surface_get_material(0))
	hammock_cloth_mi.mesh = rebuilt


func _setup_hammock_procedural_fallback() -> void:
	hammock_use_v25 = false
	_ham_rest_y.resize(hammock_nt + 1)
	_ham_cur_y.resize(hammock_nt + 1)
	for i in hammock_nt + 1:
		var t := float(i) / float(hammock_nt)
		_ham_rest_y[i] = -hammock_empty_sag * sin(PI * t)
		_ham_cur_y[i] = _ham_rest_y[i]
	var hsm = StandardMaterial3D.new()
	hsm.vertex_color_use_as_albedo = true
	hsm.vertex_color_is_srgb = true
	hsm.roughness = 0.92
	hsm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hsm.metallic = 0.0
	hammock_mi = MeshInstance3D.new()
	hammock_mi.material_override = hsm
	hammock_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hammock_node.add_child(hammock_mi)
	_rebuild_hammock_mesh()


## Drive fabric sag from world-space body samples. No-op for authored hammock_v25 cloth.
func set_hammock_load(pts: Array[Vector3]) -> void:
	hammock_body_pts = pts
	hammock_occupied = pts.size() > 0
	if hammock_use_v25:
		return
	var ab := hammock_b - hammock_a
	var ham_len := maxf(ab.length(), 0.01)
	var along := ab / ham_len
	var mid := (hammock_a + hammock_b) * 0.5
	var blend := 0.45 if hammock_occupied else 1.0
	for i in hammock_nt + 1:
		var t := float(i) / float(hammock_nt)
		var y := _ham_rest_y[i]
		if hammock_occupied:
			var deepen := 0.0
			for p in pts:
				var tp := clampf(0.5 + (p - mid).dot(along) / ham_len, 0.0, 1.0)
				var d := absf(tp - t)
				deepen = maxf(deepen, exp(-d * d * 18.0))
			y = -lerpf(hammock_empty_sag, hammock_occ_sag, deepen) * sin(PI * t)
		_ham_cur_y[i] = lerpf(_ham_cur_y[i], y, blend)
	_rebuild_hammock_mesh()


func _rebuild_hammock_mesh() -> void:
	if hammock_mi == null:
		return
	var mid := (hammock_a + hammock_b) * 0.5
	var ab := hammock_b - hammock_a
	var side_u := ab.cross(Vector3.UP).normalized()
	if side_u.length_squared() < 1e-6:
		side_u = Vector3.RIGHT
	# Smooth catenary cloth: subdivided grid, length sag + raised side edges, length stripes.
	var wrap := 0.16 if hammock_occupied else 0.10
	var rail := 0.20 if hammock_occupied else 0.10
	var cream := Color(0.94, 0.84, 0.62)
	var stripe := Color(0.42, 0.62, 0.78)
	var rim := Color(0.72, 0.52, 0.32)
	var HB = MeshBuilder.new()
	for s in hammock_nt:
		var t0 := float(s) / float(hammock_nt)
		var t1 := float(s + 1) / float(hammock_nt)
		var y0 := _ham_cur_y[s]
		var y1 := _ham_cur_y[s + 1]
		# Mild end gather only — keep a continuous bed, not two ribbons.
		var taper0 := 0.88 + 0.12 * sin(PI * clampf(t0, 0.0, 1.0))
		var taper1 := 0.88 + 0.12 * sin(PI * clampf(t1, 0.0, 1.0))
		var w0 := hammock_half_w * taper0
		var w1 := hammock_half_w * taper1
		var p0 := hammock_a + ab * t0 + Vector3(0, y0, 0) - mid
		var p1 := hammock_a + ab * t1 + Vector3(0, y1, 0) - mid
		var stripe_on := (int(floor(t0 * 14.0)) % 2) == 0
		var bed_col: Color = cream if stripe_on else stripe
		for st in hammock_nu - 1:
			var u0 := lerpf(-1.0, 1.0, float(st) / float(hammock_nu - 1))
			var u1 := lerpf(-1.0, 1.0, float(st + 1) / float(hammock_nu - 1))
			var edge := maxf(absf(u0), absf(u1)) > 0.86
			var col: Color = rim if edge else bed_col
			# Parabolic dish: centre sunk, sides rise above the torso.
			var cy0 := -wrap * (1.0 - u0 * u0) + rail * (u0 * u0)
			var cy1 := -wrap * (1.0 - u1 * u1) + rail * (u1 * u1)
			var A = p0 + side_u * (w0 * u0) + Vector3(0, cy0, 0)
			var B = p0 + side_u * (w0 * u1) + Vector3(0, cy1, 0)
			var C = p1 + side_u * (w1 * u1) + Vector3(0, cy1, 0)
			var D = p1 + side_u * (w1 * u0) + Vector3(0, cy0, 0)
			var n0 := ((B - A).cross(D - A)).normalized()
			if n0.dot(Vector3.UP) < 0.0:
				n0 = -n0
			HB.face(A, B, C, col, col, col, n0)
			HB.face(A, C, D, col, col, col, n0)
			HB.face(A, B, C, col.darkened(0.10), col.darkened(0.10), col.darkened(0.10), -n0)
			HB.face(A, C, D, col.darkened(0.10), col.darkened(0.10), col.darkened(0.10), -n0)
	hammock_mi.mesh = HB.commit()


## lowest point of the hammock bed (world, at rest)
func hammock_bed() -> Vector3:
	return hammock_point(0.5)

## Point on the hammock centreline. t=0 at hammock_a, t=1 at hammock_b (matches mesh sag).
func hammock_point(t: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	var p := hammock_a.lerp(hammock_b, t)
	# Interpolate current centreline sag (empty or occupied).
	var ft := t * float(hammock_nt)
	var i0 := clampi(int(ft), 0, hammock_nt - 1)
	var i1 := mini(i0 + 1, hammock_nt)
	var f := ft - float(i0)
	var y_off := lerpf(_ham_cur_y[i0] if _ham_cur_y.size() > i0 else -hammock_empty_sag * sin(PI * t),
		_ham_cur_y[i1] if _ham_cur_y.size() > i1 else -hammock_empty_sag * sin(PI * t), f)
	# MUST match visual dish wrap in _rebuild_hammock_mesh.
	var wrap := 0.16 if hammock_occupied else 0.10
	p.y = lerpf(hammock_a.y, hammock_b.y, t) + y_off - wrap
	return p

## Unit tangent along the hammock fabric (a→b), and the upward normal of the sag.
func hammock_frame(t: float) -> Dictionary:
	var eps := 0.02
	var p0 := hammock_point(clampf(t - eps, 0.0, 1.0))
	var p1 := hammock_point(clampf(t + eps, 0.0, 1.0))
	var along := (p1 - p0).normalized()
	var side := (hammock_b - hammock_a).cross(Vector3.UP).normalized()
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	var normal := along.cross(side).normalized()
	if normal.y < 0.0:
		normal = -normal
		side = -side
	return {"pos": hammock_point(t), "along": along, "side": side, "normal": normal}

## Lounger seat surface. u=0 at the foot end (+local Z), u=1 at the backrest hinge (−local Z).
func lounger_seat_point(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var z := lerpf(lounger_seat_half.z, -lounger_seat_half.z, u)
	var b := Basis(Vector3.RIGHT, lounger_seat_tilt)
	var local := lounger_seat_local + b * Vector3(0.0, lounger_seat_half.y, z)
	return {
		"pos": lounger_xf * local,
		"normal": (lounger_xf.basis * (b * Vector3.UP)).normalized(),
		"along": (lounger_xf.basis * (b * Vector3(0, 0, -1))).normalized(),
	}

## Lounger backrest FRONT surface (the face the boy rests on). v=0 near the seat hinge,
## v=1 at the raised head end. Normal points out of the cushion (sky + toward the open seat).
func lounger_back_point(v: float) -> Dictionary:
	v = clampf(v, 0.0, 1.0)
	# +tilt raises −local Z. v=0 at +Z (hinge / lower), v=1 at −Z (head / higher).
	var z := lerpf(lounger_back_half.z, -lounger_back_half.z, v)
	var b := Basis(Vector3.RIGHT, lounger_back_tilt)
	# Centre of the board slab, then step to the cushion face.
	var centre := lounger_xf * (lounger_back_local + b * Vector3(0.0, 0.0, z))
	var along := (lounger_xf.basis * (b * Vector3(0, 0, -1))).normalized()  # toward head end
	var side := (lounger_xf.basis * Vector3.RIGHT).normalized()
	# Outward cushion normal = along × side, flipped to the skyward / seat-open side.
	var n := along.cross(side).normalized()
	if n.y < 0.0:
		n = -n
	# Prefer the side that faces the seat (toward the feet).
	var feet_dir := (lounger_seat_point(0.0)["pos"] as Vector3) - (lounger_seat_point(1.0)["pos"] as Vector3)
	if n.dot(feet_dir.normalized()) < 0.0:
		n = -n
		# If that flip pointed us into the ground, blend toward sky so contact stays outside.
		if n.y < 0.2:
			n = (n * 0.35 + Vector3.UP * 0.65 + feet_dir.normalized() * 0.4).normalized()
	var pos: Vector3 = centre + n * lounger_back_half.y
	return {
		"pos": pos,
		"normal": n,
		"along": along,
	}

## True when `world` projects onto the finite backrest cushion (with a small margin).
func lounger_back_contains(world: Vector3, margin := 0.04) -> bool:
	var mid: Dictionary = lounger_back_point(0.5)
	var n: Vector3 = (mid["normal"] as Vector3).normalized()
	var along: Vector3 = (mid["along"] as Vector3).normalized()
	var side: Vector3 = n.cross(along).normalized()
	var d: Vector3 = world - (mid["pos"] as Vector3)
	# Reject points far from the board plane before the in-plane test.
	if absf(d.dot(n)) > 0.35:
		return false
	var u := d.dot(along)  # along pad length from centre
	var v := d.dot(side)
	return absf(u) <= lounger_back_half.z + margin and absf(v) <= lounger_back_half.x + margin


## True when `world` projects onto the finite seat cushion (with a small margin).
func lounger_seat_contains(world: Vector3, margin := 0.04) -> bool:
	var mid: Dictionary = lounger_seat_point(0.5)
	var n: Vector3 = (mid["normal"] as Vector3).normalized()
	var along: Vector3 = (mid["along"] as Vector3).normalized()
	var side: Vector3 = n.cross(along).normalized()
	var d: Vector3 = world - (mid["pos"] as Vector3)
	if absf(d.dot(n)) > 0.35:
		return false
	var u := d.dot(along)
	var v := d.dot(side)
	return absf(u) <= lounger_seat_half.z + margin and absf(v) <= lounger_seat_half.x + margin


## Body-parameter surface for sunbathing: s=0 feet (seat), s≈0.45 hips (hinge), s=1 head (backrest).
func lounger_body_surface(s: float) -> Dictionary:
	s = clampf(s, 0.0, 1.0)
	const HIP := 0.45
	if s <= HIP:
		return lounger_seat_point(s / HIP)
	return lounger_back_point((s - HIP) / (1.0 - HIP))

func swing_hammock(ang: float) -> Transform3D:
	# Authored hammock stays fixed in its prop frame (no swing overwrite).
	if hammock_use_v25:
		return Transform3D.IDENTITY
	var mid = (hammock_a + hammock_b) * 0.5
	var axis = (hammock_b - hammock_a).normalized()
	var xf = Transform3D(Basis(axis, ang), mid)
	hammock_node.transform = xf
	return xf * Transform3D(Basis.IDENTITY, -mid)

# ------------------------------------------------------------------ vegetation

func _bush(p: Vector3, s: float) -> void:
	wall_c(Vector2(p.x, p.z), 0.34 * s, p.y - 0.3, p.y + 0.8 * s, "灌木")
	bush_spots.append([p, s])
	var g = [Color(0.36, 0.64, 0.28), Color(0.42, 0.7, 0.3), Color(0.3, 0.58, 0.3)][rng.randi() % 3]
	# the old lobes still draw their random numbers (into a mesh that is thrown away) so everything placed
	# after a bush stays where it was; they shape the leafy bush
	var junk := MeshBuilder.new()
	var lobes: Array = []
	for k in rng.randi_range(3, 5):
		var o = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 0.5), rng.randf_range(-0.5, 0.5)) * s
		var sc: Vector3 = Vector3(0.55, 0.45, 0.55) * s * rng.randf_range(0.7, 1.1)
		blob(junk, p + o + Vector3(0, s * 0.3, 0), sc, g, 0.07 * s, 7, 4, 0.04, 0.08)
		lobes.append([p + o + Vector3(0, s * 0.3, 0), sc])
	_leafy_bush(p, s, lobes, g)
	if rng.randf() < 0.5:
		var fc = [Color(0.95, 0.3, 0.4), Color(0.98, 0.6, 0.75), Color(1.0, 0.85, 0.3), Color(0.98, 0.98, 0.95)][rng.randi() % 4]
		for k in rng.randi_range(3, 6):
			var a = rng.randf() * TAU
			var o = Vector3(cos(a) * 0.5 * s, rng.randf_range(0.5, 0.85) * s, sin(a) * 0.5 * s)
			_flower(FB, p + o, 0.05 * s + 0.03, fc, 0.1, Vector3(cos(a), 0.6, sin(a)).normalized())

## a bush of leaf sprays: LEAF_N-ish small cards (textures/leaf_cluster.png, instanced in one MultiMesh)
## over the lobes, pointing outwards, darker the deeper and lower they sit; a dark core and a few
## branches fill what shows through the gaps
func _leafy_bush(p: Vector3, s: float, lobes: Array, g: Color) -> void:
	var lr := RandomNumberGenerator.new()
	lr.seed = hash(Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0)))
	var top := p.y
	for lb: Array in lobes:
		top = maxf(top, (lb[0] as Vector3).y + (lb[1] as Vector3).y)
	var bark := Color(0.36, 0.27, 0.19)
	for lb: Array in lobes:
		var c: Vector3 = lb[0]
		var r: Vector3 = lb[1]
		for k in 2:
			var tip := c + Vector3(lr.randf_range(-0.5, 0.5) * r.x, lr.randf_range(-0.1, 0.4) * r.y, lr.randf_range(-0.5, 0.5) * r.z)
			var base := p + Vector3(lr.randf_range(-0.06, 0.06), 0.0, lr.randf_range(-0.06, 0.06)) * s
			var mid := base.lerp(tip, 0.5) + Vector3(lr.randf_range(-0.08, 0.08), 0.0, lr.randf_range(-0.08, 0.08)) * s
			tube(FB, base, mid, 0.028 * s, 0.02 * s, 4, bark, 0.0, 0.0)
			tube(FB, mid, tip, 0.02 * s, 0.008 * s, 4, bark, 0.0, 0.04)
		var n := int(12.0 * (r.x * r.z) / (0.3 * s * s) * s) + 7
		for k in n:
			# a point in the outer shell of the lobe, never under the ground
			var d := Vector3(lr.randf_range(-1, 1), lr.randf_range(-0.8, 1), lr.randf_range(-1, 1)).normalized()
			var rr := sqrt(lr.randf_range(0.12, 1.0))
			var q := c + d * r * rr
			if q.y < p.y + 0.04 * s:
				q.y = p.y + 0.04 * s + lr.randf() * 0.05
			var out := (q - Vector3(p.x, p.y + (top - p.y) * 0.35, p.z)).normalized()
			var up := (out + Vector3(0, 0.7, 0)).normalized()
			var sz := lr.randf_range(0.42, 0.56) * s
			var b := Basis(Vector3.UP, lr.randf() * TAU)
			b = Basis(Quaternion(Vector3.UP, up)) * b
			b = b.scaled(Vector3.ONE * sz)
			# deeper and lower: darker (inner ambient occlusion); a touch of hue and value variety per spray
			var depth := clampf(rr, 0.0, 1.0) * clampf(0.55 + 0.6 * (q.y - p.y) / maxf(top - p.y, 0.1), 0.0, 1.0)
			var ao := clampf(0.35 + 0.65 * depth, 0.3, 1.0)
			var tint := Color.from_hsv(g.h + lr.randf_range(-0.035, 0.035), g.s * lr.randf_range(0.45, 0.65), minf(g.v * lr.randf_range(0.95, 1.18), 1.0))
			leaves.append([Transform3D(b, q - up * sz * 0.35), Color(tint, clampf((q.y - p.y) / maxf(top - p.y, 0.1), 0.15, 1.0)), Color(out.x, out.y, out.z, ao)])

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
	var lr := RandomNumberGenerator.new()
	lr.seed = hash(Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0))) + 1
	for k in 7:
		# same draws as the old seven triangles, so the island's layout does not move
		var a = rng.randf() * TAU
		var base = p + Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.18
		var h = rng.randf_range(0.3, 0.55) * s
		for j in 2:
			var aa: float = a + lr.randf_range(-0.6, 0.6)
			var bb: Vector3 = base + Vector3(lr.randf_range(-0.05, 0.05), 0, lr.randf_range(-0.05, 0.05))
			_blade(bb, Vector3(cos(aa), 0, sin(aa)), h * lr.randf_range(0.7, 1.1), 0.014 * s * lr.randf_range(0.8, 1.2), lr.randf_range(0.25, 0.55), g, lr)

## one slender blade: a tapered strip of 3 segments arching away from `dir`, dark at the root, paler and
## a little dry at the tip; normals lean up so the tuft shades softly
func _blade(base: Vector3, dir: Vector3, h: float, w: float, lean: float, g: Color, lr: RandomNumberGenerator) -> void:
	var side := Vector3(-dir.z, 0, dir.x)
	var tipc := g.lerp(Color(0.78, 0.76, 0.5), lr.randf_range(0.1, 0.4)).lightened(0.1)
	var rootc := g.darkened(0.22)
	var hue := lr.randf_range(-0.04, 0.04)
	var prev_l := base - side * w
	var prev_r := base + side * w
	for i in range(1, 4):
		var t := i / 3.0
		var c := base + dir * (lean * h * t * t) + Vector3(0, h * (t - 0.18 * t * t * lean), 0)
		var ww := w * (1.0 - t) + 0.001
		var l := c - side * ww
		var r := c + side * ww
		var c0 := rootc.lerp(tipc, (i - 1) / 3.0)
		var c1 := rootc.lerp(tipc, t)
		c0 = Color.from_hsv(c0.h + hue, c0.s, c0.v, (i - 1) / 3.0 * 0.3)
		c1 = Color.from_hsv(c1.h + hue, c1.s, c1.v, t * 0.3)
		var n := (Vector3.UP * 1.2 + dir * 0.3).normalized()
		FB.tri_sm(prev_l, prev_r, r, n, n, n, c0, c0, c1)
		FB.tri_sm(prev_l, r, l, n, n, n, c0, c1, c1)
		prev_l = l
		prev_r = r

func _near_beach_prop(x: float, z: float) -> bool:
	# Keep grass/bushes out of the lounger, towel, umbrella and hammock footprints.
	if Vector2(x - lounger_xf.origin.x, z - lounger_xf.origin.z).length() < 2.2:
		return true
	if Vector2(x - towel_pos.x, z - towel_pos.z).length() < 1.6:
		return true
	if Vector2(x - umbrella_pos.x, z - umbrella_pos.z).length() < 1.8:
		return true
	var ham_mid := (hammock_a + hammock_b) * 0.5
	if Vector2(x - ham_mid.x, z - ham_mid.z).length() < 2.4:
		return true
	return false


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
		if _near_beach_prop(x, z):
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
		if path_dist(p.x, p.z) > 1.0 and absf(wrapf(th + PI / 2.0, -PI, PI)) > 0.2 \
				and not _near_beach_prop(p.x, p.z):
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
				wall_s(q0, q, 0.05, minf(g0.y, gpq.y) - 0.2, maxf(g0.y, gpq.y) + 0.7, "栅栏")
				tube(SB, g0 + Vector3(0, 0.6, 0), gpq + Vector3(0, 0.6, 0), 0.018, 0.018, 3, Color(0.85, 0.75, 0.55))
	# lantern posts along the beach path to the hut
	var bp: Array = paths[0]
	for i in range(1, bp.size()):
		var q: Vector2 = bp[i]
		var o: Vector2 = (bp[i] - bp[i - 1]).normalized().orthogonal() * 1.0
		var g = gp(q.x + o.x, q.y + o.y)
		tube(SB, g, g + Vector3(0, 1.1, 0), 0.04, 0.035, 5, Color(0.4, 0.28, 0.16))
		wall_c(Vector2(g.x, g.z), 0.06, g.y - 0.2, g.y + 1.35, "路灯")
		box(GB, Vector3(0.14, 0.2, 0.14), g + Vector3(0, 1.2, 0), Vector3.ZERO, Color(1.0, 0.78, 0.4))
		lamps.append([g + Vector3(0, 1.2, 0), "path"])
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
