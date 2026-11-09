extends Node3D
## 海岛打水漂 — a small low-poly stone skipping game.
## Everything (terrain, props, character, UI) is generated in code.

const GRAVITY := 9.8
const WATER_Y := 0.0
const DOCK_Y := 0.75
const DOCK_END_Z := -7.0
const THROW_ORIGIN := Vector3(0.35, DOCK_Y + 1.15, -6.4)
const POWER_CYCLE := 1.7  # seconds for 0 -> 100% -> 0

enum State { READY, AIMING, FLYING, SINKING, RESULT }

var state: int = State.READY
var rng := RandomNumberGenerator.new()

# aiming
var press_pos := Vector2.ZERO
var charge_t := 0.0
var power := 0.0
var aim_yaw := 0.0      # degrees, + = left
var aim_pitch := 7.0    # degrees above horizontal
var pitch_at_press := 7.0
var yaw_at_press := 0.0

# stone simulation
var stone_pos := Vector3.ZERO
var stone_vel := Vector3.ZERO
var spin := 0.0
var skips := 0
var throw_dist := 0.0
var last_contact := Vector3.ZERO
var sink_timer := 0.0
var result_text := ""
var throw_anim := 0.0

var best_skips := 0
var best_dist := 0.0
const SAVE_PATH := "user://best.cfg"

# nodes
var camera: Camera3D
var stone: MeshInstance3D
var player: Node3D
var arm_pivot: Node3D
var hand_stone: MeshInstance3D
var preview_dots: Array[MeshInstance3D] = []
var buoys: Array[Node3D] = []
var water_mat: ShaderMaterial
var cam_home_pos := Vector3(5.0, 6.6, 1.6)
var cam_home_look := Vector3(-3.5, 0.0, -15.0)
var cam_look := Vector3.ZERO

# ui
var ui_font: Font
var lbl_stats: Label
var lbl_best: Label
var lbl_hint: Label
var lbl_toast: Label
var lbl_aim: Label
var power_bar: ProgressBar
var power_box: Control
var toast_timer := 0.0

# demo / test
var demo_mode := false
var demo_t := 0.0
var demo_shots := {}

func _ready() -> void:
	rng.seed = 20261109
	ui_font = load("res://fonts/ui.otf")
	_load_best()
	_build_environment()
	_build_terrain()
	_build_water()
	_build_props()
	_build_player()
	_build_stone()
	_build_ui()
	cam_look = cam_home_look
	camera.global_position = cam_home_pos
	camera.look_at(cam_look)
	var args := OS.get_cmdline_user_args()
	if "--sim" in args:
		_run_sim_report()
		get_tree().quit()
		return
	demo_mode = "--demo" in args
	_update_ui()

# ------------------------------------------------------------------ world

static func shore_z(x: float) -> float:
	var l: float = min(x, 0.0)
	var r: float = max(x, 0.0)
	return 1.0 - 0.05 * l * l + 0.006 * r * r + 0.6 * sin(x * 0.25)

func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _vc_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	return m

## Turns any primitive mesh into a flat-shaded low-poly mesh, with optional vertex jitter.
func _flat(mesh: Mesh, jitter := 0.0, scale := Vector3.ONE) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vlist: Array[Vector3] = []
	for v in verts:
		var key := Vector3i(roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000))
		if not moved.has(key):
			moved[key] = v * scale + Vector3(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		vlist.append(moved[key])
	var n := idx.size() if idx.size() > 0 else vlist.size()
	for i in range(0, n, 3):
		var a: Vector3 = vlist[idx[i] if idx.size() > 0 else i]
		var b: Vector3 = vlist[idx[i + 1] if idx.size() > 0 else i + 1]
		var c: Vector3 = vlist[idx[i + 2] if idx.size() > 0 else i + 2]
		var nrm := (c - a).cross(b - a).normalized()
		if nrm.length() < 0.5:
			continue
		for p in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(p)
	return st.commit()

func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	(parent if parent else self).add_child(mi)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.52, 0.92)
	sm.sky_horizon_color = Color(0.72, 0.88, 0.98)
	sm.ground_horizon_color = Color(0.72, 0.88, 0.98)
	sm.ground_bottom_color = Color(0.1, 0.35, 0.6)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.86, 0.97)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true

func _terrain_h(x: float, z: float) -> float:
	var d := shore_z(x) - z
	var bump := 0.12 * sin(x * 0.9 + z * 0.4) + 0.1 * cos(z * 1.1 - x * 0.3)
	if d > 0.0:
		return -min(d * 0.14, 3.0) + bump * 0.4 - 0.05
	var h: float = min(-d * 0.16, 1.1) + bump * 0.5
	# grassy hill on the left headland
	var hill := Vector2(x + 26.0, z + 6.0).length()
	h += max(0.0, 4.5 - hill * 0.32)
	var hill2 := Vector2(x - 30.0, z - 20.0).length()
	h += max(0.0, 3.5 - hill2 * 0.2)
	return h

func _terrain_color(x: float, z: float, h: float) -> Color:
	var sand := Color(0.9, 0.8, 0.6)
	var wet := Color(0.78, 0.67, 0.48)
	var grass := Color(0.42, 0.72, 0.3)
	var under := Color(0.93, 0.86, 0.66)
	var d := shore_z(x) - z
	var c: Color
	if d > 0.0:
		c = under
	elif d > -1.2:
		c = wet.lerp(sand, clamp(-d / 1.2, 0.0, 1.0))
	else:
		c = sand
	if h > 1.15:
		c = c.lerp(grass, clamp((h - 1.15) * 2.5, 0.0, 1.0))
	var v := rng.randf_range(-0.03, 0.03)
	return Color(c.r + v, c.g + v, c.b + v)

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1.6
	var x0 := -64.0
	var z0 := -34.0
	var nx := 80
	var nz := 50
	var hs := {}
	for i in range(nx + 1):
		for j in range(nz + 1):
			var x := x0 + i * step + (rng.randf_range(-0.35, 0.35) if i > 0 and i < nx else 0.0)
			var z := z0 + j * step + (rng.randf_range(-0.35, 0.35) if j > 0 and j < nz else 0.0)
			hs[Vector2i(i, j)] = Vector3(x, _terrain_h(x, z), z)
	for i in range(nx):
		for j in range(nz):
			var a: Vector3 = hs[Vector2i(i, j)]
			var b: Vector3 = hs[Vector2i(i + 1, j)]
			var c: Vector3 = hs[Vector2i(i + 1, j + 1)]
			var d: Vector3 = hs[Vector2i(i, j + 1)]
			for tri in [[a, c, b], [a, d, c]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.y < 0.0:
					n = -n
				var ctr: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var col := _terrain_color(ctr.x, ctr.z, ctr.y)
				for p in tri:
					st.set_color(col)
					st.set_normal(n)
					st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vc_mat()
	add_child(mi)
	# deep seabed so the sky never shows through the water
	var bed := PlaneMesh.new()
	bed.size = Vector2(900, 900)
	_add(bed, _mat(Color(0.05, 0.25, 0.45)), Vector3(0, -3.3, 0))

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	pm.subdivide_width = 120
	pm.subdivide_depth = 120
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://water.gdshader")
	var mi := _add(pm, water_mat, Vector3(0, WATER_Y, -120))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _palm(pos: Vector3, lean := 0.0, yaw := 0.0, height := 5.0) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var trunk_mat := _mat(Color(0.55, 0.38, 0.22))
	var leaf_mat := _mat(Color(0.2, 0.62, 0.25))
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var leaf_mat2 := _mat(Color(0.3, 0.72, 0.28))
	leaf_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	var segs := 7
	var p := Vector3.ZERO
	var seg_h := height / segs
	for s in range(segs):
		var cy := CylinderMesh.new()
		cy.top_radius = 0.17 - s * 0.012
		cy.bottom_radius = 0.2 - s * 0.012
		cy.height = seg_h * 1.05
		cy.radial_segments = 6
		cy.rings = 1
		var t := float(s) / segs
		var off := Vector3(lean * t * t * height * 0.35, 0, 0)
		var nxt := Vector3(lean * pow(t + 1.0 / segs, 2) * height * 0.35, seg_h * (s + 1), 0)
		var mid := (Vector3(off.x, seg_h * s, 0) + nxt) * 0.5
		var mi := _add(_flat(cy), trunk_mat, mid, Vector3(0, 0, -atan2(nxt.x - off.x, seg_h)), Vector3.ONE, root)
		mi.rotation.y = s * 0.5
		p = nxt
	var top := p
	for k in range(8):
		var leaf := PrismMesh.new()
		leaf.size = Vector3(0.75, 0.06, 2.6)
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position = top
		holder.rotation = Vector3(0, k * TAU / 8.0 + rng.randf() * 0.3, 0)
		var lm := _add(_flat(leaf), leaf_mat if k % 2 == 0 else leaf_mat2, Vector3(0, -0.35, 1.25), Vector3(deg_to_rad(28 + rng.randf() * 18), 0, 0), Vector3.ONE, holder)
		lm.rotation.z = rng.randf_range(-0.1, 0.1)
	var cn := SphereMesh.new()
	cn.radius = 0.15
	cn.height = 0.3
	cn.radial_segments = 6
	cn.rings = 3
	for k in range(3):
		_add(_flat(cn), _mat(Color(0.45, 0.3, 0.15)), top + Vector3(cos(k * 2.1) * 0.22, -0.25, sin(k * 2.1) * 0.22), Vector3.ZERO, Vector3.ONE, root)

func _rock(pos: Vector3, size: float, col := Color(0.42, 0.42, 0.44)) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 7
	sm.rings = 4
	var m := _flat(sm, 0.22, Vector3(1.0, 0.7, 1.0))
	_add(m, _mat(col.lerp(Color(0.5, 0.48, 0.45), rng.randf() * 0.4)), pos, Vector3(0, rng.randf() * TAU, 0), Vector3(size, size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.8, 1.2)))

func _seaweed(pos: Vector3) -> void:
	var m := _mat(Color(0.2, 0.55, 0.3))
	for k in range(4):
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.07
		c.height = rng.randf_range(0.6, 1.3)
		c.radial_segments = 4
		c.rings = 1
		_add(c, m, pos + Vector3(rng.randf_range(-0.4, 0.4), c.height * 0.5, rng.randf_range(-0.4, 0.4)), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))

func _box(size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(b, mat, pos, rot, Vector3.ONE, parent)

func _build_props() -> void:
	var wood := _mat(Color(0.62, 0.43, 0.26))
	var wood2 := _mat(Color(0.52, 0.35, 0.2))
	var wood_dark := _mat(Color(0.38, 0.25, 0.15))
	# --- dock from the beach into the sea
	var z := 3.0
	while z > DOCK_END_Z - 0.2:
		_box(Vector3(2.4, 0.1, 0.42), wood if int(z * 10) % 2 == 0 else wood2, Vector3(0, DOCK_Y, z), Vector3(0, rng.randf_range(-0.02, 0.02), 0))
		z -= 0.48
	for pz in [2.5, -0.5, -3.5, DOCK_END_Z + 0.2]:
		for px in [-1.15, 1.15]:
			var c := CylinderMesh.new()
			c.top_radius = 0.11
			c.bottom_radius = 0.13
			c.height = 3.2
			c.radial_segments = 6
			_add(c, wood_dark, Vector3(px, DOCK_Y - 1.0, pz))
	for px in [-1.15, 1.15]:
		_box(Vector3(0.12, 0.12, 10.0), wood_dark, Vector3(px, DOCK_Y - 0.15, -2.0))
	# --- beach hut on stilts (left)
	var hut := Vector3(-11.8, _terrain_h(-11.8, shore_z(-11.8) + 4.5), shore_z(-11.8) + 4.5)
	for dx in [-1.6, 1.6]:
		for dz in [-1.4, 1.4]:
			_box(Vector3(0.22, 2.2, 0.22), wood_dark, hut + Vector3(dx, 0.9, dz))
	_box(Vector3(3.8, 0.2, 3.4), wood2, hut + Vector3(0, 1.8, 0))
	_box(Vector3(3.4, 1.9, 3.0), wood, hut + Vector3(0, 2.85, 0))
	_box(Vector3(0.9, 1.3, 0.05), wood_dark, hut + Vector3(0.6, 2.55, -1.52))
	_box(Vector3(0.7, 0.6, 0.05), _mat(Color(0.35, 0.6, 0.75)), hut + Vector3(-0.9, 2.9, -1.52))
	var roof := PrismMesh.new()
	roof.size = Vector3(4.6, 1.5, 4.0)
	_add(_flat(roof), _mat(Color(0.86, 0.72, 0.42)), hut + Vector3(0, 4.55, 0))
	# --- palms (placed relative to the curved shoreline)
	for pp in [[-5.5, 2.0, 0.9], [-8.0, 3.5, -0.8], [-10.5, 1.8, 1.0], [-13.5, 3.0, -0.6], [-16.0, 1.6, 0.8],
			[-19.0, 3.5, 1.0], [-22.5, 2.0, -0.7], [-26.0, 4.0, 0.6], [-30.0, 2.5, -0.9], [5.0, 2.0, -1.0], [8.5, 3.0, 0.8], [-3.0, 6.5, 0.4]]:
		var px: float = pp[0]
		var pz: float = shore_z(px) + pp[1]
		_palm(Vector3(px, _terrain_h(px, pz) - 0.1, pz), pp[2], rng.randf() * TAU, rng.randf_range(4.8, 6.6))
	# --- rocks along the shore and in the shallows
	for r in [[Vector3(-3.5, 0.2, 0.8), 0.7], [Vector3(-9.0, 0.0, -3.6), 0.8], [Vector3(-11.0, -0.1, -4.8), 0.5], [Vector3(-4.6, 0.1, 1.6), 0.45], [Vector3(3.0, 0.0, 0.2), 0.6],
			[Vector3(-13.0, 0.0, -4.2), 1.3], [Vector3(-14.5, 0.0, -6.5), 0.9], [Vector3(-18.0, 0.2, -10.0), 1.6],
			[Vector3(8.0, -0.3, -3.0), 0.8], [Vector3(-7.0, -0.4, -9.0), 0.7], [Vector3(12.0, -0.2, 0.5), 1.0]]:
		_rock(r[0], r[1])
	for p in [Vector3(-2.5, -0.5, -3.0), Vector3(2.8, -0.6, -4.5), Vector3(-5.5, -0.3, -1.2), Vector3(5.0, -0.4, -1.5), Vector3(-1.8, -0.8, -8.0)]:
		_seaweed(p)
	# --- beach details: umbrella and a little boat
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = 2.4
	_add(pole, _mat(Color(0.95, 0.95, 0.95)), Vector3(4.0, 1.4, 3.6))
	var umb := CylinderMesh.new()
	umb.top_radius = 0.02
	umb.bottom_radius = 1.4
	umb.height = 0.55
	umb.radial_segments = 8
	_add(_flat(umb), _mat(Color(0.95, 0.35, 0.3)), Vector3(4.0, 2.7, 3.6))
	# --- distant islands
	for isl in [[Vector3(-45, 0, -95), 14.0], [Vector3(38, 0, -120), 10.0], [Vector3(5, 0, -170), 18.0]]:
		var c := CylinderMesh.new()
		c.top_radius = isl[1] * 0.35
		c.bottom_radius = isl[1]
		c.height = isl[1] * 0.35
		c.radial_segments = 9
		_add(_flat(c, 0.6), _mat(Color(0.4, 0.65, 0.35)), isl[0] + Vector3(0, c.height * 0.4, 0))
		var s := CylinderMesh.new()
		s.top_radius = isl[1]
		s.bottom_radius = isl[1] * 1.15
		s.height = 0.6
		s.radial_segments = 9
		_add(s, _mat(Color(0.97, 0.9, 0.72)), isl[0] + Vector3(0, 0.1, 0))
	# --- clouds
	var cloud_mat := _mat(Color(1, 1, 1))
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for k in range(9):
		var cp := Vector3(rng.randf_range(-160, 160), rng.randf_range(40, 70), rng.randf_range(-260, -120))
		for b in range(4):
			var sm := SphereMesh.new()
			sm.radial_segments = 6
			sm.rings = 3
			var r := rng.randf_range(6, 11)
			sm.radius = r
			sm.height = r * 1.2
			_add(_flat(sm), cloud_mat, cp + Vector3(b * 8.0 - 12.0, rng.randf_range(-2, 2), rng.randf_range(-3, 3)))
	# --- distance buoys
	for dist in [20, 40, 60]:
		var bn := Node3D.new()
		add_child(bn)
		bn.position = THROW_ORIGIN * Vector3(1, 0, 1) + Vector3(0, 0, -dist)
		bn.set_meta("phase", rng.randf() * TAU)
		var b1 := CylinderMesh.new()
		b1.top_radius = 0.18
		b1.bottom_radius = 0.38
		b1.height = 0.7
		b1.radial_segments = 8
		_add(_flat(b1), _mat(Color(0.95, 0.3, 0.2)), Vector3(0, 0.3, 0), Vector3.ZERO, Vector3.ONE, bn)
		_box(Vector3(0.36, 0.12, 0.36), _mat(Color(1, 1, 1)), Vector3(0, 0.55, 0), Vector3.ZERO, bn)
		var lbl := Label3D.new()
		lbl.text = "%d 米" % dist
		lbl.font = ui_font
		lbl.font_size = 64
		lbl.pixel_size = 0.012
		lbl.outline_size = 14
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.4, 0)
		lbl.no_depth_test = false
		bn.add_child(lbl)
		buoys.append(bn)

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	player.position = Vector3(0, DOCK_Y + 0.05, -6.2)
	var skin := _mat(Color(0.96, 0.78, 0.62))
	var shirt := _mat(Color(0.98, 0.55, 0.25))
	var shorts := _mat(Color(0.2, 0.45, 0.75))
	for lx in [-0.12, 0.12]:
		_box(Vector3(0.14, 0.5, 0.14), skin, Vector3(lx, 0.25, 0), Vector3.ZERO, player)
	_box(Vector3(0.42, 0.25, 0.26), shorts, Vector3(0, 0.6, 0), Vector3.ZERO, player)
	_box(Vector3(0.44, 0.5, 0.26), shirt, Vector3(0, 0.95, 0), Vector3.ZERO, player)
	var head := SphereMesh.new()
	head.radius = 0.19
	head.height = 0.38
	head.radial_segments = 8
	head.rings = 4
	_add(_flat(head), skin, Vector3(0, 1.4, 0), Vector3.ZERO, Vector3.ONE, player)
	var hat := CylinderMesh.new()
	hat.top_radius = 0.16
	hat.bottom_radius = 0.38
	hat.height = 0.14
	hat.radial_segments = 10
	_add(_flat(hat), _mat(Color(0.95, 0.85, 0.5)), Vector3(0, 1.58, 0), Vector3.ZERO, Vector3.ONE, player)
	_box(Vector3(0.1, 0.45, 0.1), skin, Vector3(-0.28, 0.95, 0), Vector3(0, 0, -0.15), player)
	arm_pivot = Node3D.new()
	player.add_child(arm_pivot)
	arm_pivot.position = Vector3(0.27, 1.15, 0)
	_box(Vector3(0.1, 0.5, 0.1), skin, Vector3(0, -0.23, 0), Vector3.ZERO, arm_pivot)
	var st := SphereMesh.new()
	st.radius = 0.08
	st.height = 0.16
	st.radial_segments = 8
	st.rings = 3
	hand_stone = _add(_flat(st), _mat(Color(0.5, 0.52, 0.55)), Vector3(0, -0.5, 0), Vector3.ZERO, Vector3(1, 0.4, 1), arm_pivot)

func _build_stone() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 9
	sm.rings = 4
	stone = _add(_flat(sm), _mat(Color(0.5, 0.52, 0.56), 0.6), Vector3.ZERO, Vector3.ZERO, Vector3(1.5, 0.5, 1.5))
	stone.visible = false
	var dot := SphereMesh.new()
	dot.radius = 0.09
	dot.height = 0.18
	dot.radial_segments = 6
	dot.rings = 3
	for i in range(16):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.85)
		var d := _add(dot, m, Vector3.ZERO)
		d.visible = false
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		preview_dots.append(d)

# ------------------------------------------------------------------ UI

func _label(size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.2, 0.35, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_top = 14
	top.offset_right = -18
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var title := _label(26, Color(1, 0.95, 0.7))
	title.text = "海岛打水漂"
	top.add_child(title)
	lbl_stats = _label(38)
	top.add_child(lbl_stats)
	lbl_best = _label(27, Color(0.9, 0.97, 1))
	top.add_child(lbl_best)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 18
	bottom.offset_right = -18
	bottom.offset_bottom = -16
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	power_box = VBoxContainer.new()
	power_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(power_box)
	lbl_aim = _label(30)
	lbl_aim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_box.add_child(lbl_aim)
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(0, 26)
	power_bar.show_percentage = false
	power_bar.max_value = 1.0
	power_bar.step = 0.001
	power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0.15, 0.3, 0.5)
	bg.set_corner_radius_all(13)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1.0, 0.8, 0.25)
	fg.set_corner_radius_all(13)
	power_bar.add_theme_stylebox_override("background", bg)
	power_bar.add_theme_stylebox_override("fill", fg)
	power_box.add_child(power_bar)
	power_box.visible = false
	lbl_hint = _label(27, Color(1, 1, 1, 0.95))
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(lbl_hint)

	lbl_toast = _label(46, Color(1, 0.95, 0.55))
	lbl_toast.set_anchors_preset(Control.PRESET_CENTER)
	lbl_toast.anchor_left = 0.0
	lbl_toast.anchor_right = 1.0
	lbl_toast.anchor_top = 0.33
	lbl_toast.anchor_bottom = 0.33
	lbl_toast.offset_left = 10
	lbl_toast.offset_right = -10
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.add_theme_constant_override("outline_size", 12)
	root.add_child(lbl_toast)

func _toast(t: String, dur := 1.4) -> void:
	lbl_toast.text = t
	lbl_toast.modulate.a = 1.0
	toast_timer = dur

func _update_ui() -> void:
	lbl_stats.text = "弹跳 %d 次   距离 %.1f 米" % [skips, throw_dist]
	lbl_best.text = "最高纪录：弹跳 %d 次 · 最远 %.1f 米" % [best_skips, best_dist]
	match state:
		State.READY:
			lbl_hint.text = "按住屏幕蓄力 → 左右拖动调方向，上下拖动调角度 → 松开扔出石头\n诀窍：角度放低、力度大，石头转得快才会多跳几下"
		State.AIMING:
			lbl_hint.text = "看准力度条，松手投出！"
		State.FLYING, State.SINKING:
			lbl_hint.text = ""
		State.RESULT:
			lbl_hint.text = "点击屏幕再扔一次"
	power_box.visible = state == State.AIMING

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.READY:
				_begin_aim(event.position)
			elif state == State.RESULT:
				_reset_round()
		else:
			if state == State.AIMING:
				_throw()
	elif event is InputEventMouseMotion and state == State.AIMING:
		_drag_to(event.position)

func _begin_aim(p: Vector2) -> void:
	state = State.AIMING
	press_pos = p
	charge_t = 0.0
	power = 0.0
	pitch_at_press = aim_pitch
	yaw_at_press = aim_yaw
	_update_ui()

func _drag_to(p: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var unit: float = min(vs.x, vs.y)
	var d := p - press_pos
	aim_yaw = clamp(yaw_at_press - d.x / unit * 45.0, -30.0, 30.0)
	aim_pitch = clamp(pitch_at_press - d.y / unit * 30.0, -3.0, 30.0)

func _reset_round() -> void:
	state = State.READY
	skips = 0
	throw_dist = 0.0
	stone.visible = false
	hand_stone.visible = true
	_update_ui()

# ------------------------------------------------------------------ physics

static func launch_speed(p: float) -> float:
	return lerp(7.0, 25.0, p)

static func launch_spin(p: float) -> float:
	return clamp(0.35 + 0.65 * p, 0.0, 1.0)

static func crit_angle(s: float) -> float:
	return 13.0 + 15.0 * s  # degrees: steeper hits than this sink

## One water contact. Returns [skipped:bool, new_velocity:Vector3, new_spin:float, entry_angle_deg:float]
static func water_contact(v: Vector3, s: float, jitter: float) -> Array:
	var h := Vector2(v.x, v.z)
	var hs := h.length()
	var ang := rad_to_deg(atan2(-v.y, max(hs, 0.001)))
	if hs < 2.2 or ang > crit_angle(s) + jitter * 3.0:
		return [false, v, s, ang]
	var sa := sin(deg_to_rad(ang))
	var keep: float = clamp(0.95 - 0.75 * sa - (1.0 - s) * 0.05, 0.55, 0.95)
	var e := 0.5 + 0.2 * s
	var nh := h * keep
	var nv := Vector3(nh.x, -v.y * e, nh.y)
	nv.y = max(nv.y, 0.55)  # minimum hop so short skips still read on screen
	return [true, nv, s * (0.9 + 0.04 * jitter), ang]

func _initial_velocity() -> Vector3:
	var sp := launch_speed(power)
	var dir := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(aim_yaw))
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(aim_pitch))
	return dir * sp

func _throw() -> void:
	if power < 0.04:
		state = State.READY
		_update_ui()
		return
	state = State.FLYING
	stone_pos = player.global_position + Vector3(0.35, 1.15, -0.3)
	stone_vel = _initial_velocity()
	spin = launch_spin(power) * rng.randf_range(0.92, 1.05)
	skips = 0
	throw_dist = 0.0
	last_contact = stone_pos
	stone.visible = true
	hand_stone.visible = false
	throw_anim = 0.0
	for d in preview_dots:
		d.visible = false
	_update_ui()

func _horizontal_dist(p: Vector3) -> float:
	var o := player.global_position
	return Vector2(p.x - o.x, p.z - o.z).length()

func _step_stone(dt: float) -> void:
	var prev := stone_pos
	stone_vel.y -= GRAVITY * dt
	stone_pos += stone_vel * dt
	stone.position = stone_pos
	stone.rotate_y(spin * 40.0 * dt)
	if stone_pos.y <= WATER_Y + 0.02 and stone_vel.y < 0.0:
		stone_pos.y = WATER_Y + 0.02
		var on_land := shore_z(stone_pos.x) - stone_pos.z < 0.0
		if on_land:
			_end_throw("石头落到沙滩上了")
			return
		var res := water_contact(stone_vel, spin, rng.randf_range(-1, 1))
		if res[0]:
			skips += 1
			stone_vel = res[1]
			spin = res[2]
			last_contact = stone_pos
			throw_dist = _horizontal_dist(stone_pos)
			_splash(stone_pos, 0.5 + 0.12 * Vector2(stone_vel.x, stone_vel.z).length() * 0.1, false)
			_float_text(stone_pos, "%d" % skips)
			if skips == 5:
				_toast("5 连跳！")
			elif skips == 10:
				_toast("10 连跳！太强了！")
			elif skips == 15:
				_toast("15 连跳！水漂大师！")
			_check_buoys(prev, stone_pos)
		else:
			throw_dist = _horizontal_dist(stone_pos)
			_splash(stone_pos, 1.2, true)
			var ang: float = res[3]
			if skips == 0:
				result_text = "扑通！入水角 %.0f°，太陡了，试试更低的角度和更大的力度" % ang if ang > 20 else "扑通！速度不够，多蓄点力"
			else:
				result_text = "漂了 %d 下！" % skips
			state = State.SINKING
			sink_timer = 0.0
	throw_dist = max(throw_dist, _horizontal_dist(Vector3(stone_pos.x, 0, stone_pos.z)) if state == State.FLYING and skips > 0 else throw_dist)
	_update_ui()

func _check_buoys(_a: Vector3, b: Vector3) -> void:
	for bn in buoys:
		var p := bn.global_position
		if Vector2(b.x - p.x, b.z - p.z).length() < 2.0:
			_toast("擦过浮标！")

func _end_throw(msg: String) -> void:
	result_text = msg
	state = State.SINKING
	sink_timer = 1.0

func _finish() -> void:
	state = State.RESULT
	stone.visible = false
	var rec := false
	if skips > best_skips:
		best_skips = skips
		rec = true
	if throw_dist > best_dist and skips > 0:
		best_dist = throw_dist
		rec = true
	if rec:
		_save_best()
	_toast(result_text + ("\n新纪录！" if rec else "") + "\n%.1f 米" % throw_dist, 3.0)
	_update_ui()

func _splash(p: Vector3, strength: float, big: bool) -> void:
	var ps := CPUParticles3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.05
	dm.height = 0.1
	dm.radial_segments = 4
	dm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.98, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.material = m
	ps.mesh = dm
	ps.amount = 40 if big else 18
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.lifetime = 0.9 if big else 0.6
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 30.0 if big else 50.0
	ps.initial_velocity_min = 2.0 * strength
	ps.initial_velocity_max = 4.0 * strength
	ps.gravity = Vector3(0, -9.8, 0)
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.6 if big else 1.1
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.15
	add_child(ps)
	ps.global_position = p
	ps.emitting = true
	get_tree().create_timer(2.0).timeout.connect(ps.queue_free)
	for k in range(2 if big else 1):
		_ripple(p, 0.25 * k, big)

func _ripple(p: Vector3, delay: float, big: bool) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.85)
	var r := _add(tm, m, p + Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(0.15, 0.05, 0.15))
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var target := 2.8 if big else 1.8
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(r, "scale", Vector3(target, 0.05, target), 1.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.8)
	tw.chain().tween_callback(r.queue_free)

func _float_text(p: Vector3, t: String) -> void:
	var l := Label3D.new()
	l.text = t
	l.font = ui_font
	l.font_size = 72
	l.pixel_size = 0.01
	l.outline_size = 16
	l.modulate = Color(1, 0.95, 0.5)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = p + Vector3(0, 0.6, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.4, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)

func _update_preview() -> void:
	var p := player.global_position + Vector3(0.35, 1.15, -0.3)
	var v := _initial_velocity()
	var s := launch_spin(power)
	var t := 0.0
	var dt := 0.06
	var placed := 0
	var hit_ok := true
	var hit := false
	while placed < preview_dots.size():
		v.y -= GRAVITY * dt
		p += v * dt
		t += dt
		if p.y <= 0.02:
			var ang := rad_to_deg(atan2(-v.y, Vector2(v.x, v.z).length()))
			hit_ok = ang <= crit_angle(s) and Vector2(v.x, v.z).length() >= 2.2
			hit = true
			p.y = 0.02
		var d := preview_dots[placed]
		d.visible = true
		d.global_position = p
		placed += 1
		if hit:
			break
	for i in range(placed, preview_dots.size()):
		preview_dots[i].visible = false
	var col := Color(0.5, 1.0, 0.6, 0.9) if hit_ok else Color(1.0, 0.45, 0.35, 0.9)
	for d in preview_dots:
		(d.material_override as StandardMaterial3D).albedo_color = col

# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if demo_mode:
		_demo_tick(delta)
	var vs := get_viewport().get_visible_rect().size
	if vs.x < vs.y:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = 72.0
		cam_home_pos = Vector3(3.6, 7.6, 2.6)
		cam_home_look = Vector3(-2.0, 0.0, -11.0)
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = 58.0
		cam_home_pos = Vector3(5.0, 6.6, 1.6)
		cam_home_look = Vector3(-3.5, 0.0, -15.0)
	var tsec := Time.get_ticks_msec() / 1000.0
	for bn in buoys:
		bn.position.y = sin(tsec * 1.7 + float(bn.get_meta("phase"))) * 0.08
		bn.rotation.z = sin(tsec * 1.3 + float(bn.get_meta("phase"))) * 0.08
	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer < 0.5:
			lbl_toast.modulate.a = max(toast_timer / 0.5, 0.0)
	match state:
		State.AIMING:
			charge_t += delta
			power = pingpong(charge_t / (POWER_CYCLE * 0.5), 1.0)
			power_bar.value = power
			lbl_aim.text = "力度 %d%%   角度 %d°   方向 %s%d°" % [roundi(power * 100), roundi(aim_pitch), "左" if aim_yaw > 0.5 else ("右" if aim_yaw < -0.5 else ""), absi(roundi(aim_yaw))]
			arm_pivot.rotation.x = lerp(arm_pivot.rotation.x, -0.6 - power * 0.9, 0.3)
			player.rotation.y = deg_to_rad(aim_yaw)
			_update_preview()
		State.READY, State.RESULT:
			arm_pivot.rotation.x = lerp(arm_pivot.rotation.x, 0.0, 0.15)
			if state == State.READY:
				player.rotation.y = deg_to_rad(aim_yaw)
		State.FLYING, State.SINKING:
			throw_anim += delta
			arm_pivot.rotation.x = lerp(arm_pivot.rotation.x, 1.4 if throw_anim < 0.35 else 0.0, 0.25)
	_update_camera(delta)

func _physics_process(delta: float) -> void:
	if state == State.FLYING:
		var sub := 4
		for i in range(sub):
			if state != State.FLYING:
				break
			_step_stone(delta / sub)
	elif state == State.SINKING:
		sink_timer += delta
		stone_pos += Vector3(stone_vel.x, 0, stone_vel.z) * delta * max(0.0, 0.3 - sink_timer)
		stone_pos.y -= delta * 0.6
		stone.position = stone_pos
		if sink_timer > 1.6:
			_finish()

func _update_camera(delta: float) -> void:
	var want_pos := cam_home_pos
	var want_look := cam_home_look
	if state == State.FLYING or state == State.SINKING or state == State.RESULT:
		var flat := Vector3(stone_pos.x, 0.0, stone_pos.z)
		var back := Vector3(stone_vel.x, 0, stone_vel.z)
		var dir := back.normalized() if back.length() > 0.5 else Vector3(0, 0, -1)
		var tall := get_viewport().get_visible_rect().size.x < get_viewport().get_visible_rect().size.y
		want_pos = flat - dir * (7.5 if tall else 6.5) + Vector3(1.5, 5.2 if tall else 3.2, 0)
		want_look = flat + dir * 5.0
		if want_pos.z > cam_home_pos.z:
			want_pos = cam_home_pos
	var k: float = 1.0 - exp(-delta * (4.0 if state == State.FLYING else 2.5))
	camera.global_position = camera.global_position.lerp(want_pos, k)
	cam_look = cam_look.lerp(want_look, k)
	camera.look_at(cam_look)

# ------------------------------------------------------------------ save

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_skips = int(cf.get_value("best", "skips", 0))
		best_dist = float(cf.get_value("best", "dist", 0.0))

func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("best", "skips", best_skips)
	cf.set_value("best", "dist", best_dist)
	cf.save(SAVE_PATH)

# ------------------------------------------------------------------ test hooks

func _run_sim_report() -> void:
	for pw in [0.3, 0.5, 0.7, 0.85, 1.0]:
		for pitch in [0.0, 5.0, 10.0, 18.0]:
			power = pw
			aim_pitch = pitch
			aim_yaw = 0.0
			var p := Vector3(0.35, DOCK_Y + 1.2, -6.5)
			var v := _initial_velocity()
			var s := launch_spin(pw)
			var n := 0
			var first_ang := -1.0
			for i in range(20000):
				v.y -= GRAVITY * 0.004
				p += v * 0.004
				if p.y <= 0.02 and v.y < 0:
					p.y = 0.02
					var r := water_contact(v, s, 0.0)
					if first_ang < 0:
						first_ang = r[3]
					if not r[0]:
						break
					n += 1
					v = r[1]
					s = r[2]
			print("SIM power=%.2f pitch=%4.1f first_angle=%5.1f skips=%2d dist=%5.1f" % [pw, pitch, first_ang, n, Vector2(p.x - 0.35, p.z + 6.5).length()])

func _demo_shot(name: String) -> void:
	if demo_shots.has(name):
		return
	demo_shots[name] = true
	var img := get_viewport().get_texture().get_image()
	var prefix := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotprefix="):
			prefix = a.substr(13)
	var path := ProjectSettings.globalize_path("res://screenshots/%s%s.png" % [prefix, name])
	img.save_png(path)
	print("DEMO screenshot ", path)

func _demo_tick(delta: float) -> void:
	demo_t += delta
	if demo_t > 1.5 and state == State.READY and not demo_shots.has("01_aim"):
		_begin_aim(Vector2.ZERO)
		aim_pitch = 4.0
		aim_yaw = 3.0
	if state == State.AIMING:
		charge_t = POWER_CYCLE * 0.5 * 0.88 - delta  # hold the bar at ~88%
		if demo_t > 3.0:
			_demo_shot("01_aim")
			_throw()
	if state == State.FLYING and skips >= 3:
		_demo_shot("02_skipping")
	if state == State.FLYING and skips >= 7:
		_demo_shot("03_far_skips")
	if state == State.RESULT and not demo_shots.has("04_result"):
		await get_tree().create_timer(0.4).timeout
		_demo_shot("04_result")
		get_tree().quit()
