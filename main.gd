extends Node3D
## 海岛打水漂 v2 — a little tropical island with a dock; skip stones across the lagoon.

const GRAVITY := 9.8
const POWER_CYCLE := 1.7
const SAVE_PATH := "user://best.cfg"

enum Mode { THROW, VIEW }
enum State { READY, AIMING, FLYING, SINKING }

var island: Island
var mode: int = Mode.THROW
var state: int = State.READY
var rng := RandomNumberGenerator.new()
var gt := 0.0

# aim
var press_pos := Vector2.ZERO
var charge_t := 0.0
var power := 0.0
var aim_yaw := 0.0
var aim_pitch := 6.0
var yaw_at_press := 0.0
var pitch_at_press := 6.0

# stone
var stone_pos := Vector3.ZERO
var stone_vel := Vector3.ZERO
var spin := 0.0
var skips := 0
var throw_dist := 0.0
var throw_origin := Vector3.ZERO
var sink_timer := 0.0
var result_text := ""
var finish_hold := 0.0
var throw_anim := 0.0
var best_skips := 0
var best_dist := 0.0
var ripple_buf := PackedVector4Array()
var ripple_i := 0

# camera (orbit)
var camera: Camera3D
var cam_yaw := 0.4
var cam_pitch := 0.4
var cam_dist := 10.0
var cam_target := Vector3.ZERO
var view_yaw := 0.6
var view_pitch := 0.55
var view_dist := 34.0
var orbit_vel := Vector2.ZERO
var touches := {}
var pinch_d := 0.0
var mouse_drag := false
var dragging := false
var demo_cam := false

# nodes
var player: Node3D
var arm_pivot: Node3D
var hand_stone: MeshInstance3D
var stone: MeshInstance3D
var preview_dots: Array[MeshInstance3D] = []
var birds: Array = []

# ui
var ui_font: Font
var lbl_stats: Label
var lbl_best: Label
var lbl_hint: Label
var lbl_toast: Label
var lbl_aim: Label
var power_bar: ProgressBar
var power_box: Control
var mode_btn: Button
var toast_timer := 0.0

# demo
var demo_mode := false
var demo_t := 0.0
var demo_step := 0
var demo_shots := {}
var demo_list: Array = []

func _ready() -> void:
	rng.seed = 99
	ui_font = load("res://fonts/ui.otf")
	_load_best()
	_build_environment()
	island = Island.new()
	add_child(island)
	island.build(ui_font)
	_build_player()
	_build_stone()
	_build_birds()
	_build_ui()
	ripple_buf.resize(8)
	aim_yaw = 0.0
	cam_target = player.global_position + Vector3(0, 1.3, 0)
	cam_yaw = 0.45
	cam_pitch = 0.4
	cam_dist = 9.5
	var args := OS.get_cmdline_user_args()
	if "--sim" in args:
		_run_sim_report()
		get_tree().quit()
		return
	demo_mode = "--demo" in args
	if demo_mode:
		_setup_demo()
	_apply_camera()
	_update_ui()

# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.46, 0.84)
	sm.sky_horizon_color = Color(0.66, 0.83, 0.95)
	sm.ground_horizon_color = Color(0.66, 0.83, 0.95)
	sm.ground_bottom_color = Color(0.12, 0.36, 0.55)
	sm.sun_angle_max = 25.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.83, 0.95)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 128, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.1
	camera.far = 900.0
	add_child(camera)
	camera.current = true

# ------------------------------------------------------------------ actors

func _vc_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.8
	return m

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	player.position = island.player_spot + Vector3(0, 0.04, 0)
	var skin := Color(0.96, 0.76, 0.6)
	var b := MeshBuilder.new()
	var box := BoxMesh.new()
	for lx in [-0.11, 0.11]:
		b.prim(box, Transform3D(Basis.IDENTITY.scaled(Vector3(0.13, 0.5, 0.13)), Vector3(lx, 0.25, 0)), skin)
		b.prim(box, Transform3D(Basis.IDENTITY.scaled(Vector3(0.15, 0.08, 0.22)), Vector3(lx, 0.04, -0.03)), Color(0.95, 0.9, 0.8))
	b.prim(box, Transform3D(Basis.IDENTITY.scaled(Vector3(0.4, 0.26, 0.25)), Vector3(0, 0.6, 0)), Color(0.2, 0.5, 0.8))
	b.prim(box, Transform3D(Basis.IDENTITY.scaled(Vector3(0.42, 0.5, 0.25)), Vector3(0, 0.95, 0)), Color(0.98, 0.98, 0.95))
	b.prim(box, Transform3D(Basis.IDENTITY.scaled(Vector3(0.43, 0.08, 0.26)), Vector3(0, 0.9, 0)), Color(0.95, 0.4, 0.3))
	var head := SphereMesh.new()
	head.radius = 0.19; head.height = 0.38; head.radial_segments = 8; head.rings = 5
	b.prim(head, Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0)), skin)
	var hair := SphereMesh.new()
	hair.radius = 0.2; hair.height = 0.3; hair.radial_segments = 8; hair.rings = 4; hair.is_hemisphere = true
	b.prim(hair, Transform3D(Basis.IDENTITY, Vector3(0, 1.44, 0.02)), Color(0.25, 0.16, 0.1))
	var hat := CylinderMesh.new()
	hat.top_radius = 0.15; hat.bottom_radius = 0.36; hat.height = 0.12; hat.radial_segments = 12
	b.prim(hat, Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), Color(0.95, 0.85, 0.5))
	var band := CylinderMesh.new()
	band.top_radius = 0.16; band.bottom_radius = 0.17; band.height = 0.05; band.radial_segments = 12
	b.prim(band, Transform3D(Basis.IDENTITY, Vector3(0, 1.64, 0)), Color(0.85, 0.3, 0.25))
	b.prim(box, Transform3D(Basis(Vector3.FORWARD, -0.15).scaled(Vector3(0.1, 0.45, 0.1)), Vector3(-0.27, 0.95, 0)), skin)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = _vc_mat()
	player.add_child(mi)
	arm_pivot = Node3D.new()
	player.add_child(arm_pivot)
	arm_pivot.position = Vector3(0.27, 1.15, 0)
	var ab := MeshBuilder.new()
	ab.prim(box, Transform3D(Basis.IDENTITY.scaled(Vector3(0.1, 0.5, 0.1)), Vector3(0, -0.23, 0)), skin)
	var arm := MeshInstance3D.new()
	arm.mesh = ab.commit()
	arm.material_override = _vc_mat()
	arm_pivot.add_child(arm)
	var sm := SphereMesh.new()
	sm.radius = 0.08; sm.height = 0.16; sm.radial_segments = 8; sm.rings = 3
	hand_stone = MeshInstance3D.new()
	hand_stone.mesh = sm
	var stm := StandardMaterial3D.new()
	stm.albedo_color = Color(0.45, 0.47, 0.5)
	hand_stone.material_override = stm
	hand_stone.position = Vector3(0, -0.5, 0)
	hand_stone.scale = Vector3(1, 0.4, 1)
	arm_pivot.add_child(hand_stone)

func _build_stone() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.12; sm.height = 0.24; sm.radial_segments = 9; sm.rings = 4
	stone = MeshInstance3D.new()
	stone.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.47, 0.52)
	m.roughness = 0.5
	stone.material_override = m
	stone.scale = Vector3(1.5, 0.5, 1.5)
	add_child(stone)
	stone.visible = false
	var dot := SphereMesh.new()
	dot.radius = 0.08; dot.height = 0.16; dot.radial_segments = 6; dot.rings = 3
	for i in 18:
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(1, 1, 1, 0.85)
		var d := MeshInstance3D.new()
		d.mesh = dot
		d.material_override = dm
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		add_child(d)
		preview_dots.append(d)

func _build_birds() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 0.95)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.75, 0.77, 0.8)
	grey.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 6:
		var root := Node3D.new()
		add_child(root)
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12; sm.height = 0.24; sm.radial_segments = 6; sm.rings = 3
		body.mesh = sm
		body.scale = Vector3(0.8, 0.7, 2.0)
		body.material_override = white
		root.add_child(body)
		var wings: Array = []
		for sgn in [-1.0, 1.0]:
			var piv := Node3D.new()
			root.add_child(piv)
			piv.position = Vector3(0.06 * sgn, 0.03, 0)
			var w := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.55, 0.02, 0.28)
			w.mesh = pm
			w.material_override = grey
			w.position = Vector3(0.28 * sgn, 0, 0)
			w.rotation = Vector3(0, 0, 0)
			piv.add_child(w)
			wings.append([piv, sgn])
		birds.append({"node": root, "wings": wings, "c": Vector3(rng.randf_range(-15, 15), rng.randf_range(9, 16), rng.randf_range(-25, 10)), "r": rng.randf_range(8, 18), "sp": rng.randf_range(0.25, 0.45) * (1.0 if i % 2 == 0 else -1.0), "ph": rng.randf() * TAU})

# ------------------------------------------------------------------ UI

func _label(size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.18, 0.32, 0.9))
	l.add_theme_constant_override("outline_size", 9)
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
	top.offset_left = 18; top.offset_top = 14; top.offset_right = -200
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var title := _label(26, Color(1, 0.95, 0.7))
	title.text = "海岛打水漂"
	top.add_child(title)
	lbl_stats = _label(36)
	top.add_child(lbl_stats)
	lbl_best = _label(25, Color(0.9, 0.97, 1))
	top.add_child(lbl_best)

	mode_btn = Button.new()
	mode_btn.add_theme_font_override("font", ui_font)
	mode_btn.add_theme_font_size_override("font_size", 30)
	mode_btn.custom_minimum_size = Vector2(170, 76)
	mode_btn.anchor_left = 1.0; mode_btn.anchor_right = 1.0
	mode_btn.offset_left = -188; mode_btn.offset_right = -16; mode_btn.offset_top = 16; mode_btn.offset_bottom = 92
	mode_btn.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.82) if st_name != "pressed" else Color(0.85, 0.95, 1, 0.95)
		sb.set_corner_radius_all(38)
		sb.border_color = Color(0.1, 0.45, 0.65)
		sb.set_border_width_all(3)
		mode_btn.add_theme_stylebox_override(st_name, sb)
	mode_btn.add_theme_color_override("font_color", Color(0.05, 0.35, 0.55))
	mode_btn.add_theme_color_override("font_hover_color", Color(0.05, 0.35, 0.55))
	mode_btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.35, 0.55))
	mode_btn.pressed.connect(_toggle_mode)
	root.add_child(mode_btn)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 18; bottom.offset_right = -18; bottom.offset_bottom = -16
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
	lbl_hint = _label(26, Color(1, 1, 1, 0.96))
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(lbl_hint)

	lbl_toast = _label(46, Color(1, 0.95, 0.55))
	lbl_toast.anchor_left = 0.0; lbl_toast.anchor_right = 1.0
	lbl_toast.anchor_top = 0.3; lbl_toast.anchor_bottom = 0.3
	lbl_toast.offset_left = 10; lbl_toast.offset_right = -10
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
	mode_btn.text = "观景" if mode == Mode.THROW else "投石"
	mode_btn.visible = state == State.READY
	if mode == Mode.VIEW:
		lbl_hint.text = "观景模式：单指拖动 360° 旋转，双指捏合缩放（电脑：拖动鼠标 / 滚轮）\n点右上角「投石」回到码头，会朝你现在看的方向扔"
	else:
		match state:
			State.READY:
				lbl_hint.text = "按住屏幕蓄力 → 左右拖动转向（可转一整圈），上下拖动调角度 → 松手扔出\n角度低、力度大、转得快才跳得多；砸到岸边、礁石或船就结束"
			State.AIMING:
				lbl_hint.text = "看准力度条，松手投出！"
			_:
				lbl_hint.text = ""
	power_box.visible = state == State.AIMING

func _toggle_mode() -> void:
	if state != State.READY:
		return
	touches.clear()
	orbit_vel = Vector2.ZERO
	if mode == Mode.THROW:
		mode = Mode.VIEW
		view_yaw = cam_yaw
		view_pitch = clamp(cam_pitch + 0.15, 0.1, 1.4)
		view_dist = max(cam_dist * 1.6, 16.0)
	else:
		mode = Mode.THROW
		aim_yaw = wrapf(cam_yaw, -PI, PI)  # throw toward where you were looking
		if not _open_sea(aim_yaw):
			for k in range(1, 19):
				if _open_sea(aim_yaw + k * 0.17):
					aim_yaw += k * 0.17
					break
				if _open_sea(aim_yaw - k * 0.17):
					aim_yaw -= k * 0.17
					break
			_toast("已转向最近的开阔海面", 1.6)
	_update_ui()

func _open_sea(yaw: float) -> bool:
	var o := player.global_position
	var d := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	for i in range(2, 30):
		var p := o + d * (i * 1.5)
		if Island.ground_h(p.x, p.z) > -0.3:
			return false
		for ob in island.obstacles:
			var c: Vector2 = ob[0]
			if float(ob[2]) > 0.0 and Vector2(p.x - c.x, p.z - c.y).length() < float(ob[1]) + 0.6:
				return false
	return true

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	if mode == Mode.VIEW:
		_view_input(event)
	else:
		_throw_input(event)

func _view_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			orbit_vel = Vector2.ZERO
		else:
			touches.erase(event.index)
		if touches.size() == 2:
			var ps: Array = touches.values()
			pinch_d = (ps[0] - ps[1]).length()
		dragging = touches.size() > 0
	elif event is InputEventScreenDrag:
		var prev: Vector2 = touches.get(event.index, event.position)
		touches[event.index] = event.position
		if touches.size() == 1:
			_orbit_by(event.position - prev)
		elif touches.size() >= 2:
			var ps: Array = touches.values()
			var d: float = (ps[0] - ps[1]).length()
			if pinch_d > 1.0 and d > 1.0:
				view_dist = clamp(view_dist * pinch_d / d, 4.0, 95.0)
			pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_drag = event.pressed
			dragging = event.pressed
			if event.pressed:
				orbit_vel = Vector2.ZERO
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			view_dist = clamp(view_dist * 0.88, 4.0, 95.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			view_dist = clamp(view_dist * 1.13, 4.0, 95.0)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and mouse_drag:
		_orbit_by(event.relative)
	elif event is InputEventMagnifyGesture:
		view_dist = clamp(view_dist / event.factor, 4.0, 95.0)

func _orbit_by(rel: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var k: float = 5.0 / max(min(vs.x, vs.y), 200.0)
	var dy: float = -rel.x * k
	var dp: float = rel.y * k * 0.7
	view_yaw += dy
	view_pitch = clamp(view_pitch + dp, 0.06, 1.42)
	var dt: float = max(get_process_delta_time(), 1.0 / 120.0)
	orbit_vel = orbit_vel.lerp(Vector2(dy, dp) / dt, 0.5)

func _throw_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.READY:
				_begin_aim(event.position)
		else:
			if state == State.AIMING:
				_throw()
	elif event is InputEventMouseMotion and state == State.AIMING:
		var vs := get_viewport().get_visible_rect().size
		var unit: float = min(vs.x, vs.y)
		var d: Vector2 = event.position - press_pos
		aim_yaw = yaw_at_press - d.x / unit * 2.2
		aim_pitch = clamp(pitch_at_press - d.y / unit * 30.0, -3.0, 30.0)

func _begin_aim(p: Vector2) -> void:
	state = State.AIMING
	press_pos = p
	charge_t = 0.0
	power = 0.0
	yaw_at_press = aim_yaw
	pitch_at_press = aim_pitch
	_update_ui()

# ------------------------------------------------------------------ physics

static func launch_speed(p: float) -> float:
	return lerp(7.0, 25.0, p)

static func launch_spin(p: float) -> float:
	return clamp(0.35 + 0.65 * p, 0.0, 1.0)

static func crit_angle(s: float) -> float:
	return 13.0 + 15.0 * s

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
	var nv := Vector3(nh.x, max(-v.y * e, 0.55), nh.y)
	return [true, nv, s * (0.9 + 0.04 * jitter), ang]

func _aim_dir() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.UP, aim_yaw)

func _hand_pos() -> Vector3:
	return player.global_transform * Vector3(0.35, 1.15, -0.3)

func _initial_velocity() -> Vector3:
	var dir := _aim_dir()
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(aim_pitch))
	return dir * launch_speed(power)

func _throw() -> void:
	if power < 0.04:
		state = State.READY
		_update_ui()
		return
	state = State.FLYING
	stone_pos = _hand_pos()
	throw_origin = stone_pos
	stone_vel = _initial_velocity()
	spin = launch_spin(power) * rng.randf_range(0.92, 1.05)
	skips = 0
	throw_dist = 0.0
	stone.visible = true
	hand_stone.visible = false
	throw_anim = 0.0
	for d in preview_dots:
		d.visible = false
	_update_ui()

func _hdist(p: Vector3) -> float:
	return Vector2(p.x - throw_origin.x, p.z - throw_origin.z).length()

func _hit_test(p: Vector3) -> String:
	var gh := Island.ground_h(p.x, p.z)
	if gh > -0.05 and p.y <= gh + 0.06:
		return "石头落在沙滩上了"
	# dock deck
	if p.y < Island.DECK_Y + 0.06 and p.y > Island.DECK_Y - 0.25:
		if (absf(p.x) < 1.2 and p.z < island.dock_start_z and p.z > island.dock_end_z) or (absf(p.x) < 3.1 and p.z < island.dock_end_z + 3.9 and p.z > island.dock_end_z - 0.1):
			return "咚！砸到码头上了"
	for o in island.obstacles:
		var c: Vector2 = o[0]
		if p.y < float(o[2]) and p.y > float(o[4]) - 0.5 and Vector2(p.x - c.x, p.z - c.y).length() < float(o[1]) + 0.08:
			return "砰！撞到了%s" % o[3]
	return ""

func _step_stone(dt: float) -> void:
	stone_vel.y -= GRAVITY * dt
	stone_pos += stone_vel * dt
	stone.position = stone_pos
	stone.rotate_y(spin * 40.0 * dt)
	if _hdist(stone_pos) > 1.0:
		var hit := _hit_test(stone_pos)
		if hit != "":
			throw_dist = _hdist(stone_pos)
			result_text = hit + ("" if skips == 0 else "（之前漂了 %d 下）" % skips)
			stone_vel = Vector3(0, -1.0, 0)
			state = State.SINKING
			sink_timer = 0.6
			if stone_pos.y < 0.3:
				_splash(Vector3(stone_pos.x, 0.0, stone_pos.z), 0.6, false, Vector3.ZERO)
			return
	if stone_pos.y <= 0.02 and stone_vel.y < 0.0:
		stone_pos.y = 0.02
		var res := water_contact(stone_vel, spin, rng.randf_range(-1, 1))
		throw_dist = _hdist(stone_pos)
		if res[0]:
			skips += 1
			stone_vel = res[1]
			spin = res[2]
			_splash(stone_pos, 0.55, false, stone_vel)
			_float_text(stone_pos, "%d" % skips)
			if skips == 5:
				_toast("5 连跳！")
			elif skips == 10:
				_toast("10 连跳！太强了！")
			elif skips == 15:
				_toast("15 连跳！水漂大师！")
			for bn in island.buoys:
				if Vector2(stone_pos.x - bn.position.x, stone_pos.z - bn.position.z).length() < 2.0:
					_toast("擦过浮标！")
		else:
			_splash(stone_pos, 1.2, true, Vector3.ZERO)
			var ang: float = res[3]
			if skips == 0:
				result_text = ("扑通！入水角 %.0f°，太陡了，试试更低的角度和更大的力度" % ang) if ang > 20.0 else "扑通！速度不够，多蓄点力"
			else:
				result_text = "漂了 %d 下！" % skips
			state = State.SINKING
			sink_timer = 0.0
	elif state == State.FLYING and skips > 0:
		throw_dist = max(throw_dist, _hdist(stone_pos))
	_update_ui()

func _finish() -> void:
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
	state = State.READY
	hand_stone.visible = true
	finish_hold = 1.2
	_update_ui()

func _add_ripple(p: Vector3, strength: float, delay := 0.0) -> void:
	ripple_buf[ripple_i] = Vector4(p.x, p.z, gt + delay, strength)
	ripple_i = (ripple_i + 1) % 8
	island.water_mat.set_shader_parameter("ripples", ripple_buf)

func _splash(p: Vector3, strength: float, big: bool, vel: Vector3) -> void:
	var dm := SphereMesh.new()
	dm.radius = 0.04; dm.height = 0.08; dm.radial_segments = 4; dm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.98, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.material = m
	var crown := CPUParticles3D.new()
	crown.mesh = dm
	crown.amount = 46 if big else 22
	crown.one_shot = true
	crown.explosiveness = 0.92
	crown.lifetime = 0.9 if big else 0.6
	crown.direction = Vector3(0, 1, 0)
	crown.spread = 28.0 if big else 42.0
	crown.initial_velocity_min = 2.0 * strength
	crown.initial_velocity_max = 4.2 * strength
	crown.gravity = Vector3(0, -9.8, 0)
	crown.damping_min = 0.5
	crown.damping_max = 1.5
	crown.scale_amount_min = 0.5
	crown.scale_amount_max = 1.7 if big else 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	crown.scale_amount_curve = curve
	crown.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	crown.emission_ring_axis = Vector3.UP
	crown.emission_ring_radius = 0.18 if big else 0.1
	crown.emission_ring_inner_radius = 0.05
	crown.emission_ring_height = 0.02
	add_child(crown)
	crown.global_position = p
	crown.emitting = true
	get_tree().create_timer(2.0).timeout.connect(crown.queue_free)
	if vel.length() > 0.5:
		var spray := CPUParticles3D.new()
		spray.mesh = dm
		spray.amount = 14
		spray.one_shot = true
		spray.explosiveness = 0.95
		spray.lifetime = 0.5
		var fwd := Vector3(vel.x, 0, vel.z).normalized()
		spray.direction = (fwd + Vector3.UP * 0.9).normalized()
		spray.spread = 22.0
		spray.initial_velocity_min = 1.5
		spray.initial_velocity_max = 3.0
		spray.gravity = Vector3(0, -9.8, 0)
		spray.scale_amount_min = 0.4
		spray.scale_amount_max = 0.9
		add_child(spray)
		spray.global_position = p
		spray.emitting = true
		get_tree().create_timer(1.5).timeout.connect(spray.queue_free)
	_add_ripple(p, 1.0 if big else 0.75)
	if big:
		_add_ripple(p, 0.6, 0.35)

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
	var p := _hand_pos()
	var v := _initial_velocity()
	var s := launch_spin(power)
	var dt := 0.06
	var placed := 0
	var ok := true
	while placed < preview_dots.size():
		v.y -= GRAVITY * dt
		p += v * dt
		var stop := false
		if _hit_test(p) != "" and Vector2(p.x - player.position.x, p.z - player.position.z).length() > 1.0:
			ok = false
			stop = true
		elif p.y <= 0.02:
			var ang := rad_to_deg(atan2(-v.y, Vector2(v.x, v.z).length()))
			ok = ang <= crit_angle(s) and Vector2(v.x, v.z).length() >= 2.2
			p.y = 0.02
			stop = true
		var d := preview_dots[placed]
		d.visible = true
		d.global_position = p
		placed += 1
		if stop:
			break
	for i in range(placed, preview_dots.size()):
		preview_dots[i].visible = false
	var col := Color(0.5, 1.0, 0.6, 0.9) if ok else Color(1.0, 0.45, 0.35, 0.9)
	for d in preview_dots:
		(d.material_override as StandardMaterial3D).albedo_color = col

# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	gt += delta
	island.set_time(gt)
	if demo_mode:
		_demo_tick(delta)
	var vs := get_viewport().get_visible_rect().size
	var tall := vs.x < vs.y
	camera.keep_aspect = Camera3D.KEEP_WIDTH if tall else Camera3D.KEEP_HEIGHT
	camera.fov = 70.0 if tall else 55.0
	for bn in island.buoys:
		var ph: float = bn.get_meta("phase")
		bn.position.y = sin(gt * 1.7 + ph) * 0.08
		bn.rotation.z = sin(gt * 1.3 + ph) * 0.08
	for b in birds:
		var a: float = b["ph"] + gt * b["sp"]
		var c: Vector3 = b["c"]
		var r: float = b["r"]
		var node: Node3D = b["node"]
		node.position = c + Vector3(cos(a) * r, sin(gt * 0.7 + b["ph"]) * 1.2, sin(a) * r)
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(b["sp"])
		node.look_at(node.position + tangent, Vector3.UP)
		node.rotation.z = -0.35 * signf(b["sp"])
		var flap := sin(gt * 7.0 + b["ph"]) * 0.55 if fmod(gt + b["ph"], 6.0) < 3.0 else 0.08
		for w in b["wings"]:
			(w[0] as Node3D).rotation.z = flap * float(w[1])
	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer < 0.5:
			lbl_toast.modulate.a = max(toast_timer / 0.5, 0.0)
	match state:
		State.AIMING:
			charge_t += delta
			power = pingpong(charge_t / (POWER_CYCLE * 0.5), 1.0)
			power_bar.value = power
			var deg := wrapf(rad_to_deg(aim_yaw), -180.0, 180.0)
			lbl_aim.text = "力度 %d%%   角度 %d°   方向 %s%d°" % [roundi(power * 100), roundi(aim_pitch), "左" if deg > 0.5 else ("右" if deg < -0.5 else ""), absi(roundi(deg))]
			arm_pivot.rotation.x = lerp(arm_pivot.rotation.x, -0.6 - power * 0.9, 0.3)
			_update_preview()
		State.READY:
			arm_pivot.rotation.x = lerp(arm_pivot.rotation.x, 0.0, 0.15)
		_:
			throw_anim += delta
			arm_pivot.rotation.x = lerp(arm_pivot.rotation.x, 1.4 if throw_anim < 0.35 else 0.0, 0.25)
	if mode == Mode.THROW and state != State.FLYING and state != State.SINKING:
		player.rotation.y = lerp_angle(player.rotation.y, aim_yaw, 0.35)
	_update_camera(delta)

func _physics_process(delta: float) -> void:
	if state == State.FLYING:
		for i in 4:
			if state != State.FLYING:
				break
			_step_stone(delta / 4.0)
	elif state == State.SINKING:
		sink_timer += delta
		stone_pos += Vector3(stone_vel.x, 0, stone_vel.z) * delta * max(0.0, 0.3 - sink_timer)
		stone_pos.y -= delta * 0.6
		stone.position = stone_pos
		if sink_timer > 1.6:
			_finish()

func _update_camera(delta: float) -> void:
	if demo_cam:
		_apply_camera()
		return
	var tall := get_viewport().get_visible_rect().size.x < get_viewport().get_visible_rect().size.y
	var want_t: Vector3
	var want_yaw: float
	var want_pitch: float
	var want_dist: float
	var k: float
	if state == State.FLYING or state == State.SINKING:
		var dir := Vector3(stone_vel.x, 0, stone_vel.z)
		dir = dir.normalized() if dir.length() > 0.5 else _aim_dir()
		want_t = Vector3(stone_pos.x, max(stone_pos.y * 0.5, 0.3), stone_pos.z) + dir * 2.0
		want_yaw = atan2(-dir.x, -dir.z) + 0.35
		want_pitch = 0.42 if tall else 0.32
		want_dist = 11.0 if tall else 9.0
		k = 1.0 - exp(-delta * 4.0)
	elif mode == Mode.VIEW:
		if not dragging:
			view_yaw += orbit_vel.x * delta
			view_pitch = clamp(view_pitch + orbit_vel.y * delta, 0.06, 1.42)
			orbit_vel *= exp(-delta * 3.5)
		var head := player.global_position + Vector3(0, 1.2, 0)
		want_t = head.lerp(Vector3(0, 1.5, -2.0), smoothstep(10.0, 45.0, view_dist))
		want_yaw = view_yaw
		want_pitch = view_pitch
		want_dist = view_dist
		k = 1.0 - exp(-delta * 9.0)
	else:
		var hold := finish_hold > 0.0
		finish_hold -= delta
		var dir := _aim_dir()
		want_t = player.global_position + Vector3(0, 1.3, 0) + dir * 3.0
		want_yaw = aim_yaw + 0.45
		want_pitch = 0.5 if tall else 0.38
		want_dist = 11.0 if tall else 9.5
		k = 1.0 - exp(-delta * (1.2 if hold else 3.0))
	cam_target = cam_target.lerp(want_t, k)
	cam_yaw = lerp_angle(cam_yaw, want_yaw, k)
	cam_pitch = lerp(cam_pitch, want_pitch, k)
	cam_dist = lerp(cam_dist, want_dist, k)
	_apply_camera()

func _apply_camera() -> void:
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	var pos := cam_target + off
	var floor_y: float = max(Island.ground_h(pos.x, pos.z), 0.0) + 0.5
	if pos.y < floor_y:
		pos.y = floor_y
	camera.global_position = pos
	camera.look_at(cam_target, Vector3.UP)

# ------------------------------------------------------------------ save

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_skips = int(cf.get_value("best", "skips", 0))
		best_dist = float(cf.get_value("best", "dist", 0.0))

func _save_best() -> void:
	if demo_mode:
		return
	var cf := ConfigFile.new()
	cf.set_value("best", "skips", best_skips)
	cf.set_value("best", "dist", best_dist)
	cf.save(SAVE_PATH)

# ------------------------------------------------------------------ test hooks

func _run_sim_report() -> void:
	for pw in [0.5, 0.7, 0.85, 1.0]:
		for pitch in [0.0, 5.0, 10.0]:
			power = pw
			aim_pitch = pitch
			aim_yaw = 0.0
			var p := _hand_pos()
			var v := _initial_velocity()
			var s := launch_spin(pw)
			var n := 0
			for i in 20000:
				v.y -= GRAVITY * 0.004
				p += v * 0.004
				if p.y <= 0.02 and v.y < 0:
					p.y = 0.02
					var r := water_contact(v, s, 0.0)
					if not r[0]:
						break
					n += 1
					v = r[1]
					s = r[2]
			print("SIM power=%.2f pitch=%4.1f skips=%2d end=(%.1f, %.1f)" % [pw, pitch, n, p.x, p.z])
	print("SIM obstacles=%d palms=%d" % [island.obstacles.size(), island.palm_spots.size()])

func _setup_demo() -> void:
	var dock_mid := Vector3(0, 1.0, (island.dock_start_z + island.dock_end_z) * 0.5)
	var shore_th := -0.95
	var sp := island.shore_pt(shore_th, -1.5)
	var out := Island.dir_at(shore_th)
	var palm_c: Vector3 = island.palm_spots[min(4, island.palm_spots.size() - 1)]
	var po := Vector3(palm_c.x, 0, palm_c.z).normalized()
	var hut_out := Vector3(island.hut_pos.x, 0, island.hut_pos.z).normalized()
	demo_list = [
		["01_island_overview", Vector3(0, 1, -5), 0.55, 0.92, 80.0],
		["02_dock_closeup", dock_mid + Vector3(0, 0, -4), 2.35, 0.3, 13.0],
		["03_shore_foam_seabed", sp, atan2(out.x, out.z) + 0.25, 0.62, 8.0],
		["04_palms_closeup", palm_c + Vector3(0, -1.5, 0), atan2(po.x, po.z) + 0.3, 0.12, 9.0],
		["05_other_side", Vector3(0, 2, 0), PI + 0.5, 0.42, 50.0],
		["06_fishing_hut", island.hut_pos + Vector3(0, 2.0, 0), atan2(hut_out.x, hut_out.z) + 0.45, 0.25, 12.0],
		["07_lighthouse_hill", island.lighthouse_pos + Vector3(0, 2.5, 0), 1.0, 0.3, 17.0],
		["08_lagoon_reef", island.shore_pt(-1.0, -7.0), 0.9, 0.85, 12.0],
	]
	demo_cam = true

func _demo_shot(name: String) -> void:
	if demo_shots.has(name):
		return
	demo_shots[name] = true
	var prefix := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotprefix="):
			prefix = a.substr(13)
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/v2/%s%s.png" % [prefix, name])
	img.save_png(path)
	print("DEMO screenshot ", path)

func _demo_tick(delta: float) -> void:
	demo_t += delta
	if demo_step < demo_list.size():
		var s: Array = demo_list[demo_step]
		cam_target = s[1]; cam_yaw = s[2]; cam_pitch = s[3]; cam_dist = s[4]
		if demo_t > 1.2:
			_demo_shot(s[0])
			demo_step += 1
			demo_t = 0.0
		return
	demo_cam = false
	if demo_step == demo_list.size():
		demo_step += 1
		demo_t = 0.0
		mode = Mode.THROW
		aim_yaw = 0.12
		_update_ui()
	if demo_t > 1.6 and state == State.READY and not demo_shots.has("09_throw_aim"):
		_begin_aim(Vector2.ZERO)
		aim_pitch = 4.0
	if state == State.AIMING:
		charge_t = POWER_CYCLE * 0.5 * 0.88 - delta
		if demo_t > 3.4:
			_demo_shot("09_throw_aim")
			_throw()
	if state == State.FLYING and skips >= 4:
		_demo_shot("10_skipping")
	if demo_shots.has("10_skipping") and state == State.READY and not demo_shots.has("11_result"):
		await get_tree().create_timer(0.6).timeout
		_demo_shot("11_result")
		get_tree().quit()
