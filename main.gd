extends Node3D
## 海岛打水漂 v5 — walk / run around a little tropical island, nap in the hammock, sunbathe on the
## beach towel, and skip stones from the end of the dock (standing or half-kneeling).

const GRAVITY := 9.8
const POWER_CYCLE := 1.7
const SAVE_PATH := "user://best.cfg"
const WALK_MAX := 1.15
const RUN_SPEED := 2.7

enum Mode { EXPLORE, THROW, VIEW, REST }
enum State { READY, AIMING, THROWING, FLYING, SINKING }

var island: Island
var mode: int = Mode.EXPLORE
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
var best_skips := 0
var best_dist := 0.0
var ripple_buf := PackedVector4Array()
var ripple_i := 0
const PRINTS := 48
const PRINT_LIFE := 75.0
var print_buf := PackedVector4Array()   # footprints on the sand: x, z, yaw, time stamped
var print_wash := PackedFloat32Array()  # when the swash first ran over each print (-1: not yet)
var print_i := 0

# camera
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
var demo_nocut := false   # showcase stills of a prop: no see-through cut-out towards the boy
var ex_yaw := 0.0
# high, slightly telephoto follow camera (the reference looks down at ~55-60 degrees)
var ex_pitch := 0.98
var ex_dist := 6.2
var last_drag := -10.0

# explore
var player: Node3D
var boy: Boy
var face_yaw := 0.0
var move_vel := Vector3.ZERO
var spot_turning := false
var spot_goal := 0.0
var spot_rate := 0.0
var ground_y := 0.0
var cur_speed := 0.0
var wading := false
var action_kind := ""
var keys_run := false

# rest (hammock / towel)
var rest_kind := ""
var rest_phase := 0
var rest_t := 0.0
var rest_approach := Vector3.ZERO
var rest_seat := Vector3.ZERO
var rest_lie := Vector3.ZERO
var rest_sit_b := Basis.IDENTITY
var rest_lie_b := Basis.IDENTITY
var rest_root_sit := Vector3.ZERO
var rest_side := Vector3.ZERO
var rest_cam_yaw := INF
var seat_i := -1   # island.seats entry near the kid / being sat on
var seat_face := Vector3.FORWARD   # the way he sits on it (logs: whichever side he came from)
var seat_ap := Vector3.ZERO
var seat_lying := false   # lying back along the bench / log
var lie_btn: Button
var swing_amp := 0.0
var zzz: Label3D

# nodes
var fly_t := 0.0
var stone: MeshInstance3D
var preview_dots: Array[MeshInstance3D] = []
var birds: Array = []

# ui
var ui_font: Font
var ui_root: Control
var lbl_title: Label
var lbl_stats: Label
var lbl_best: Label
var lbl_hint: Label
var lbl_toast: Label
var lbl_aim: Label
var power_bar: ProgressBar
var power_box: Control
var view_btn: Button
var sound_btn: Button
var stance_btn: Button
var leave_btn: Button
var action_btn: Button
var joy: Joystick
var tip_box: Control
var tip_timer := 0.0
var toast_timer := 0.0
var start_overlay: Control
var top_box: VBoxContainer
var bottom_box: VBoxContainer
var right_box: VBoxContainer

# audio
var sfx := {}
var amb: AudioStreamPlayer
var fire_amb: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_i := 0
var last_skip := -1
var muted := false
var audio_started := false
var chime_pending := false
var chime_wait := 0.0
var is_web := false

# demo
var demo_mode := false
var demo_t := 0.0
var demo_shots := {}
var portrait_demo := false
var shot_dir := "v12"
var night_k := 0.0
var night_on := false
var saved_night := false
var settle_t := 1.0
var night_btn: Button
var night_fx: NightFx
var night_amb: AudioStreamPlayer
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
const SUN_DAY := Vector3(-38, 135, 0)
const MOON_NIGHT := Vector3(-14, 206, 0)
var demo_release_pending := 0
var demo_input := Vector2.ZERO
var demo_run := false
var demo_track: Array = []
var demo_seg := ""
var selftest: RefCounted

func _ready() -> void:
	rng.seed = 99
	is_web = OS.has_feature("web")
	ui_font = load("res://fonts/ui.otf")
	_load_best()
	_build_environment()
	island = Island.new()
	add_child(island)
	island.build(ui_font)
	night_fx = NightFx.new()
	add_child(night_fx)
	night_fx.build(island)
	_build_player()
	_build_wade_ring()
	_build_stone()
	_build_birds()
	_build_audio()
	_build_ui()
	_build_reflection()
	ripple_buf.resize(8)
	print_buf.resize(PRINTS)
	print_wash.resize(PRINTS)
	for i in PRINTS:
		print_buf[i] = Vector4(0, 0, 0, -1000.0)
		print_wash[i] = -1.0
	var args := OS.get_cmdline_user_args()
	if "--sim" in args:
		_run_sim_report()
		get_tree().quit()
		return
	portrait_demo = "--portrait" in args
	if _opt("night") == "1":
		night_on = true
		night_k = 1.0
		_update_night(0.0, true)
	for a in args:
		if a.begins_with("--video4="):
			demo_seg = a.substr(9)
	demo_mode = "--demo4" in args or demo_seg != "" or "--selftest" in args
	if saved_night and not demo_mode and not night_on:
		night_on = true
		night_k = 1.0
		_update_night(0.0, true)
	_snap_explore_cam()
	if demo_mode:
		_start_audio()
		if "--selftest" in args:
			selftest = load("res://dev/selftest.gd").new()
			selftest.run.call_deferred(self)
		else:
			_run_demo4.call_deferred()
	_apply_camera()
	_update_ui()

var wade_ring: MeshInstance3D
var wade_mat: ShaderMaterial
var wade_k := 0.0

## foam collar + ripple rings around the legs while the kid stands or walks in the sea
func _build_wade_ring() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.6, 2.6)
	wade_mat = ShaderMaterial.new()
	wade_mat.shader = load("res://shaders/wade_ring.gdshader")
	wade_ring = MeshInstance3D.new()
	wade_ring.mesh = pm
	wade_ring.material_override = wade_mat
	wade_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wade_ring.visible = false
	add_child(wade_ring)

func _update_wade_ring(delta: float) -> void:
	var p := player.global_position
	var sy := Island.sea_y(p.x, p.z, gt)
	var dep := sy - _surface(p.x, p.z)
	var want := smoothstep(0.02, 0.1, dep) * (1.0 - smoothstep(0.9, 1.2, dep))
	if mode == Mode.REST or _on_dock(p.x, p.z):
		want = 0.0
	wade_k = move_toward(wade_k, want, delta * 2.5)
	wade_ring.visible = wade_k > 0.001
	if not wade_ring.visible:
		return
	wade_ring.global_position = Vector3(p.x, sy + 0.006, p.z)
	var v := move_vel if mode == Mode.EXPLORE else Vector3.ZERO
	var r := player.global_basis.x
	wade_mat.set_shader_parameter("strength", wade_k)
	wade_mat.set_shader_parameter("vel", Vector2(v.x, v.z))
	wade_mat.set_shader_parameter("right", Vector2(r.x, r.z).normalized())
	wade_mat.set_shader_parameter("time", gt)
	wade_mat.set_shader_parameter("night", night_k)

func _build_player() -> void:
	boy = Boy.new()
	player = boy
	add_child(boy)
	# start on the beach at the foot of the dock, looking along it
	var sp := Vector3(0.6, 0, island.dock_start_z + 3.2)
	sp.y = _surface(sp.x, sp.z)
	boy.position = sp
	face_yaw = 0.15
	boy.rotation.y = face_yaw
	ground_y = sp.y
	boy.released.connect(_launch)
	boy.footstep.connect(_on_footstep)
	boy.foot_flat.connect(_stamp_footprint)
	zzz = Label3D.new()
	zzz.font = ui_font
	zzz.font_size = 64
	zzz.pixel_size = 0.004
	zzz.outline_size = 14
	zzz.modulate = Color(1, 1, 1)
	zzz.outline_modulate = Color(0.1, 0.25, 0.45)
	zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zzz.visible = false
	add_child(zzz)
# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky_mat = sm
	sm.sky_top_color = Color(0.40, 0.58, 0.76)
	sm.sky_horizon_color = Color(0.78, 0.85, 0.88)
	sm.ground_horizon_color = Color(0.78, 0.85, 0.88)
	sm.ground_bottom_color = Color(0.30, 0.46, 0.52)
	sm.sun_angle_max = 25.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.2
	# muted, slightly lifted pastel grade
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 0.92
	env.adjustment_brightness = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.86, 0.88)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = SUN_DAY
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	if is_web:
		# phones: one shadow map pass instead of two; the far split only shaded palms 40+ m away
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 50.0
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

func _build_stone() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.12; sm.height = 0.24; sm.radial_segments = 9; sm.rings = 4
	stone = MeshInstance3D.new()
	stone.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.47, 0.52)
	m.roughness = 0.5
	stone.material_override = m
	stone.scale = Vector3(0.7, 0.24, 0.6)
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
		d.layers = 1 | WaterReflection.SKIP_LAYER
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
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.layers = 1 | WaterReflection.SKIP_LAYER
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
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			w.layers = 1 | WaterReflection.SKIP_LAYER
			w.position = Vector3(0.28 * sgn, 0, 0)
			w.rotation = Vector3(0, 0, 0)
			piv.add_child(w)
			wings.append([piv, sgn])
		birds.append({"node": root, "wings": wings, "c": Vector3(rng.randf_range(-15, 15), rng.randf_range(9, 16), rng.randf_range(-25, 10)), "r": rng.randf_range(8, 18), "sp": rng.randf_range(0.25, 0.45) * (1.0 if i % 2 == 0 else -1.0), "ph": rng.randf() * TAU})

func _label(size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.18, 0.32, 0.9))
	l.add_theme_constant_override("outline_size", 9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ------------------------------------------------------------------ UI

func _btn(text: String, size: int, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		if primary:
			sb.bg_color = Color(1.0, 0.82, 0.3, 0.95) if st_name != "pressed" else Color(1.0, 0.92, 0.6, 1.0)
			sb.border_color = Color(0.55, 0.3, 0.05)
		else:
			sb.bg_color = Color(1, 1, 1, 0.82) if st_name != "pressed" else Color(0.85, 0.95, 1, 0.95)
			sb.border_color = Color(0.1, 0.45, 0.65)
		sb.set_corner_radius_all(40)
		sb.set_border_width_all(3)
		sb.content_margin_left = 18; sb.content_margin_right = 18
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(st_name, sb)
	var fc := Color(0.45, 0.2, 0.02) if primary else Color(0.05, 0.35, 0.55)
	for cn in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, fc)
	return b

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	ui_root = root

	# joystick: the bottom-left part of the screen (explore mode)
	joy = Joystick.new()
	joy.anchor_left = 0.0; joy.anchor_right = 0.5; joy.anchor_top = 0.55; joy.anchor_bottom = 1.0
	root.add_child(joy)

	top_box = VBoxContainer.new()
	top_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_box.offset_left = 18; top_box.offset_top = 12; top_box.offset_right = -190
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_theme_constant_override("separation", 0)
	root.add_child(top_box)
	lbl_title = _label(26, Color(1, 0.95, 0.7))
	lbl_title.text = "海岛打水漂"
	top_box.add_child(lbl_title)
	lbl_stats = _label(32)
	top_box.add_child(lbl_stats)
	lbl_best = _label(22, Color(0.9, 0.97, 1))
	top_box.add_child(lbl_best)

	right_box = VBoxContainer.new()
	right_box.anchor_left = 1.0; right_box.anchor_right = 1.0
	right_box.offset_left = -176; right_box.offset_right = -14; right_box.offset_top = 14
	right_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_theme_constant_override("separation", 10)
	root.add_child(right_box)
	view_btn = _btn("观景", 26)
	view_btn.custom_minimum_size = Vector2(162, 62)
	view_btn.pressed.connect(_toggle_view)
	right_box.add_child(view_btn)
	sound_btn = _btn("声音：开", 22)
	sound_btn.custom_minimum_size = Vector2(162, 50)
	sound_btn.pressed.connect(_toggle_sound)
	right_box.add_child(sound_btn)
	night_btn = _btn("夜晚", 22)
	night_btn.custom_minimum_size = Vector2(162, 50)
	night_btn.pressed.connect(_toggle_night)
	right_box.add_child(night_btn)
	stance_btn = _btn("姿势：站立", 22)
	stance_btn.custom_minimum_size = Vector2(162, 56)
	stance_btn.pressed.connect(_toggle_stance)
	right_box.add_child(stance_btn)
	leave_btn = _btn("离开码头", 22)
	leave_btn.custom_minimum_size = Vector2(162, 56)
	leave_btn.pressed.connect(_leave_throw)
	right_box.add_child(leave_btn)

	# context action (打水漂 / 睡觉 / 晒太阳 / 起来), bottom right
	action_btn = _btn("打水漂", 34, true)
	action_btn.anchor_left = 1.0; action_btn.anchor_right = 1.0; action_btn.anchor_top = 1.0; action_btn.anchor_bottom = 1.0
	action_btn.offset_left = -214; action_btn.offset_right = -24; action_btn.offset_top = -134; action_btn.offset_bottom = -40
	action_btn.pressed.connect(_on_action)
	root.add_child(action_btn)
	lie_btn = _btn("躺下", 30, true)
	lie_btn.anchor_left = 1.0; lie_btn.anchor_right = 1.0; lie_btn.anchor_top = 1.0; lie_btn.anchor_bottom = 1.0
	lie_btn.pressed.connect(_lie_down)
	root.add_child(lie_btn)

	bottom_box = VBoxContainer.new()
	bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_box.offset_left = 18; bottom_box.offset_right = -18; bottom_box.offset_bottom = -14
	bottom_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_box.alignment = BoxContainer.ALIGNMENT_END
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_box)
	power_box = VBoxContainer.new()
	power_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(power_box)
	lbl_aim = _label(28)
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
	lbl_hint = _label(24, Color(1, 1, 1, 0.96))
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom_box.add_child(lbl_hint)

	lbl_toast = _label(44, Color(1, 0.95, 0.55))
	lbl_toast.anchor_left = 0.0; lbl_toast.anchor_right = 1.0
	lbl_toast.anchor_top = 0.24; lbl_toast.anchor_bottom = 0.24
	lbl_toast.offset_left = 10; lbl_toast.offset_right = -10
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.add_theme_constant_override("outline_size", 12)
	root.add_child(lbl_toast)

	# "no sound?" tip (web only), dismissible
	tip_box = PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.02, 0.15, 0.28, 0.82)
	tsb.set_corner_radius_all(18)
	tsb.content_margin_left = 16; tsb.content_margin_right = 8; tsb.content_margin_top = 8; tsb.content_margin_bottom = 8
	tip_box.add_theme_stylebox_override("panel", tsb)
	tip_box.anchor_left = 0.5; tip_box.anchor_right = 0.5; tip_box.anchor_top = 0.0
	tip_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tip_box.offset_top = 150
	var th := HBoxContainer.new()
	tip_box.add_child(th)
	var tl := _label(22, Color(1, 0.95, 0.75))
	tl.text = "没声音？请关闭 iPhone 侧边静音开关并调高音量"
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(260, 0)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	var tx := _btn("×", 26)
	tx.custom_minimum_size = Vector2(52, 52)
	tx.pressed.connect(func() -> void: tip_box.visible = false)
	th.add_child(tx)
	tip_box.visible = false
	root.add_child(tip_box)

	# iOS / browsers only allow sound after a tap: a "tap to start" curtain unlocks the audio
	if not audio_started:
		start_overlay = ColorRect.new()
		(start_overlay as ColorRect).color = Color(0.02, 0.12, 0.22, 0.55)
		start_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		start_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		start_overlay.gui_input.connect(_on_start_input)
		root.add_child(start_overlay)
		var big := _label(64, Color(1, 0.95, 0.6))
		big.text = "点击开始"
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		big.set_anchors_preset(Control.PRESET_FULL_RECT)
		big.offset_bottom = -60
		start_overlay.add_child(big)
		var small := _label(26)
		small.text = "轻点屏幕开始，开启海浪声\niPhone 请先关闭侧边静音开关、调高音量"
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		small.set_anchors_preset(Control.PRESET_FULL_RECT)
		small.offset_top = 110; small.offset_left = 16; small.offset_right = -16
		start_overlay.add_child(small)
	get_viewport().size_changed.connect(_layout_ui)
	bottom_box.resized.connect(_fit_action)
	_layout_ui()

func _tall() -> bool:
	var vs := get_viewport().get_visible_rect().size
	return vs.x < vs.y

## Screen insets (notch / Dynamic Island, home indicator, rounded corners) in UI units: top, right,
## bottom, left. The page asks for viewport-fit=cover and reports env(safe-area-inset-*) (export
## head_include); `--safe=t,r,b,l` (CSS px) fakes a phone's insets for desktop checks.
var safe := Vector4.ZERO
var safe_css := ""
var safe_t := 0.0

func _read_safe_area() -> bool:
	var raw := ""
	var css_h := float(DisplayServer.window_get_size().y)
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("window.__safeArea ? window.__safeArea() : ''", true))
	else:
		for a0 in OS.get_cmdline_user_args():
			if a0.begins_with("--safe="):
				raw = a0.substr(7) + ",0," + str(css_h)
	if raw == safe_css:
		return false
	safe_css = raw
	var v := raw.split(",")
	if v.size() < 6 or float(v[5]) <= 0.0:
		safe = Vector4.ZERO
		return true
	var k := get_viewport().get_visible_rect().size.y / float(v[5])
	safe = Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3])) * k
	return true

## The context buttons sit bottom right; on a tall screen the hint spans the width, so they stand on top of it.
func _fit_action() -> void:
	var tall := _tall()
	var base := 56.0 if tall else 36.0
	if tall and is_instance_valid(bottom_box) and lbl_hint.text != "":
		base = maxf(base, 14.0 + bottom_box.size.y + 14.0)
	action_btn.offset_right = -24 - safe.y
	action_btn.offset_left = action_btn.offset_right - 190
	action_btn.offset_bottom = -base - safe.z
	action_btn.offset_top = action_btn.offset_bottom - 94
	lie_btn.offset_left = action_btn.offset_left; lie_btn.offset_right = action_btn.offset_right
	lie_btn.offset_bottom = action_btn.offset_top - 16
	lie_btn.offset_top = lie_btn.offset_bottom - 80

## portrait: smaller title, action button a bit higher; landscape: roomier. Everything anchored to an
## edge keeps clear of the safe-area insets.
func _layout_ui() -> void:
	if not is_instance_valid(action_btn):
		return
	_read_safe_area()
	var st := safe.x
	var sr := safe.y
	var sb := safe.z
	var sl := safe.w
	var tall := _tall()
	lbl_title.add_theme_font_size_override("font_size", 24 if tall else 26)
	lbl_stats.add_theme_font_size_override("font_size", 28 if tall else 32)
	top_box.offset_left = 18 + sl
	top_box.offset_top = 12 + st
	top_box.offset_right = -184 - sr
	right_box.offset_top = 14 + st
	right_box.offset_right = -14 - sr
	right_box.offset_left = right_box.offset_right - 162
	_fit_action()
	joy.anchor_top = 0.6 if tall else 0.45
	joy.anchor_right = 0.62 if tall else 0.45
	joy.offset_left = sl
	joy.offset_bottom = -sb
	joy.radius = 66.0 if tall else 72.0
	joy.lift = 62.0 if tall else 0.0
	bottom_box.offset_left = 18 + sl
	bottom_box.offset_right = -18 - sr
	bottom_box.offset_bottom = -14 - sb
	tip_box.offset_top = (170 if tall else 120) + st

func _toast(t: String, dur := 1.4) -> void:
	lbl_toast.text = t
	lbl_toast.modulate.a = 1.0
	toast_timer = dur

func _update_ui() -> void:
	var throw_mode := mode == Mode.THROW
	lbl_stats.visible = throw_mode
	lbl_best.visible = throw_mode or mode == Mode.EXPLORE
	lbl_stats.text = "弹跳 %d 次   距离 %.1f 米" % [skips, throw_dist]
	lbl_best.text = "最高纪录：弹跳 %d 次 · 最远 %.1f 米" % [best_skips, best_dist]
	view_btn.text = "返回" if mode == Mode.VIEW else "观景"
	view_btn.visible = (mode == Mode.EXPLORE) or mode == Mode.VIEW or (throw_mode and state == State.READY)
	sound_btn.text = "声音：关" if muted else "声音：开"
	night_btn.text = "白天" if night_on else "夜晚"
	stance_btn.visible = throw_mode and state == State.READY
	stance_btn.text = "姿势：半蹲" if boy.stance == "crouch" else "姿势：站立"
	leave_btn.visible = throw_mode and state == State.READY
	joy.visible = mode == Mode.EXPLORE
	if mode != Mode.EXPLORE:
		joy._end()
	var act := ""
	if mode == Mode.EXPLORE:
		act = {"throw": "打水漂", "sleep": "睡觉", "sun": "晒太阳", "seat": "坐下"}.get(action_kind, "")
	elif mode == Mode.REST and rest_phase == 4:
		act = "起来"
	action_btn.visible = act != ""
	action_btn.text = act
	lie_btn.visible = mode == Mode.REST and rest_phase == 4 and rest_kind == "seat" and not seat_lying \
		and seat_i >= 0 and island.seats[seat_i]["can_lie"]
	match mode:
		Mode.VIEW:
			lbl_hint.text = "观景：单指拖动 360° 旋转，双指捏合缩放（电脑：拖鼠标 / 滚轮）\n点右上角「返回」继续玩"
		Mode.EXPLORE:
			var h := "左下摇杆走路，推到底就跑（电脑：WASD/方向键，Shift 跑）· 拖动屏幕转视角"
			match action_kind:
				"throw":
					h = "到码头尽头了！点「打水漂」开始扔石子"
				"sleep":
					h = "椰子树间的吊床，点「睡觉」躺上去打个盹"
				"sun":
					h = "沙滩毛巾，点「晒太阳」躺下晒一会儿"
				"seat":
					h = island.seats[seat_i]["hint"]
				_:
					if _tall():
						h = "左下摇杆走路，推到底就跑 · 拖屏幕转视角\n打水漂要去码头尽头"
					else:
						h += "\n打水漂要走到码头尽头；吊床可以睡觉，沙滩毛巾可以晒太阳，长椅和篝火边可以坐"
			lbl_hint.text = h
		Mode.REST:
			var rh := {"sleep": "呼……睡着了 · 轻点屏幕或「起来」叫醒他", "sun": "晒太阳中 · 轻点屏幕或「起来」站起来", "seat": "坐着歇一会儿 · 轻点屏幕或「起来」站起来",
				"seatcan": "坐着歇一会儿 · 点「躺下」翘腿躺一会儿，轻点屏幕或「起来」站起来",
				"seatlie": "草帽盖脸，翘着腿躺着 · 轻点屏幕或「起来」起身"}
			var rk := rest_kind
			if rest_kind == "seat" and seat_lying:
				rk = "seatlie"
			elif rest_kind == "seat" and island.seats[seat_i]["can_lie"]:
				rk = "seatcan"
			lbl_hint.text = rh[rk] if rest_phase == 4 else ""
		_:
			match state:
				State.READY:
					lbl_hint.text = "按住蓄力 → 左右拖转向、上下拖调角度 → 松手扔出\n角度低、力度大才跳得多 · 右上角切换站立/半蹲"
				State.AIMING:
					lbl_hint.text = "看准力度条，松手投出！"
				_:
					lbl_hint.text = ""
	power_box.visible = state == State.AIMING and throw_mode

func _toggle_view() -> void:
	if mode == Mode.VIEW:
		mode = Mode.EXPLORE if view_from == Mode.EXPLORE else Mode.THROW
		touches.clear()
		_update_ui()
		return
	if state != State.READY or not (mode == Mode.EXPLORE or mode == Mode.THROW):
		return
	view_from = mode
	touches.clear()
	orbit_vel = Vector2.ZERO
	mode = Mode.VIEW
	view_yaw = cam_yaw
	view_pitch = clamp(cam_pitch + 0.15, 0.1, 1.4)
	view_dist = max(cam_dist * 1.6, 16.0)
	_update_ui()

var view_from: int = Mode.EXPLORE

func _toggle_stance() -> void:
	if state != State.READY:
		return
	boy.stance = "stand" if boy.stance == "crouch" else "crouch"
	_toast("半蹲投掷：出手更低、贴着水面" if boy.stance == "crouch" else "站立投掷：力量更大", 1.6)
	_update_ui()

func _open_sea(yaw: float) -> bool:
	var o := player.global_position
	var d := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	for i in range(1, 46):
		var p := o + d * (0.5 * i if i <= 6 else 3.0 + (i - 6) * 1.5)
		if Island.ground_h(p.x, p.z) > -0.3:
			return false
		for ob in island.obstacles:
			var c: Vector2 = ob[0]
			if float(ob[2]) > 0.0 and Vector2(p.x - c.x, p.z - c.y).length() < float(ob[1]) + 0.6:
				return false
	return true

# ------------------------------------------------------------------ modes

func _in_throw_zone(p: Vector3) -> bool:
	return absf(p.x) < 3.15 and p.z < island.dock_end_z + 4.3 and p.z > island.dock_end_z - 0.2 and p.y > Island.DECK_Y - 0.1

func _hammock_spot() -> Array:
	var a := island.hammock_a
	var b := island.hammock_b
	var bed := island.hammock_bed()
	var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var to_p := Vector3(player.position.x - bed.x, 0, player.position.z - bed.z)
	if to_p.dot(side) < 0.0:
		side = -side
	return [bed, along, side]

func _update_action_kind() -> void:
	var k := ""
	var p := player.position
	if _in_throw_zone(p):
		k = "throw"
	else:
		var hs := _hammock_spot()
		var bed: Vector3 = hs[0]
		if Vector2(p.x - bed.x, p.z - bed.z).length() < 1.9:
			k = "sleep"
		var tp := island.towel_pos
		if Vector2(p.x - tp.x, p.z - tp.z).length() < 1.7:
			k = "sun"
		var best := 1.25
		for i in island.seats.size():
			var st: Dictionary = island.seats[i]
			var face: Vector3 = st["face"]
			var top: Vector3 = st["top"]
			var front := (p - top).dot(face)
			var ap: Vector3 = st["approach"]
			var lim := 1.25
			if st["two_sided"]:
				# a log: sit on whichever side he is on; from the ends too (the approach is mid-log)
				lim = 1.35
				if front < -0.05:
					face = -face
					ap = st["back_approach"]
				front = absf(front) + 0.2
			var dd := Vector2(p.x - ap.x, p.z - ap.z).length()
			if dd < minf(best, lim) and front > 0.15:
				best = dd
				k = "seat"
				if seat_i != i or not seat_face.is_equal_approx(face):
					seat_i = i
					seat_face = face
					seat_ap = ap
					action_kind = ""
	if k != action_kind:
		action_kind = k
		_update_ui()

func _on_action() -> void:
	if mode == Mode.REST:
		_wake()
		return
	if mode != Mode.EXPLORE:
		return
	match action_kind:
		"throw":
			_enter_throw()
		"sleep", "sun", "seat":
			_begin_rest(action_kind)

var throw_walk := false
var throw_spot := Vector3.ZERO

func _enter_throw() -> void:
	mode = Mode.THROW
	state = State.READY
	move_vel = Vector3.ZERO
	# step to the nearest clear spot on the front edge of the T platform (between the posts)
	var p := player.position
	var best_x := 0.0
	for sx: float in [-2.1, 0.0, 2.1]:
		if absf(p.x - sx) < absf(p.x - best_x):
			best_x = sx
	throw_spot = Vector3(best_x, Island.DECK_Y + 0.04, island.dock_end_z + 0.85)
	throw_walk = Vector2(p.x - throw_spot.x, p.z - throw_spot.z).length() > 0.08
	aim_yaw = face_yaw
	var keep_yaw := player.rotation.y
	player.position = throw_spot
	if absf(wrapf(aim_yaw, -PI, PI)) > 1.2:
		aim_yaw = 0.0
	if not _open_sea(aim_yaw):
		for k in range(1, 19):
			if _open_sea(aim_yaw + k * 0.17):
				aim_yaw += k * 0.17
				break
			if _open_sea(aim_yaw - k * 0.17):
				aim_yaw -= k * 0.17
				break
	player.position = p
	player.rotation.y = keep_yaw
	_toast("打水漂！按住蓄力，松手扔出", 1.8)
	_update_ui()

func _throw_walk_tick(delta: float) -> void:
	var d := throw_spot - player.position
	d.y = 0.0
	if d.length() < 0.04:
		player.position = Vector3(throw_spot.x, player.position.y, throw_spot.z)
		throw_walk = false
		move_vel = Vector3.ZERO
		boy.set_move(0.0)
		boy.set_idle()
		return
	var spd := minf(1.1, d.length() * 3.0 + 0.35)
	move_vel = move_vel.move_toward(d.normalized() * spd, 8.0 * delta)
	var step := move_vel * delta
	if step.length() > d.length():
		step = d
	player.position += step
	player.position.y = Island.DECK_Y + 0.04
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-move_vel.x, -move_vel.z), 1.0 - exp(-delta * 10.0))
	boy.set_move(move_vel.length())

func _leave_throw() -> void:
	if mode != Mode.THROW or state != State.READY:
		return
	mode = Mode.EXPLORE
	face_yaw = player.rotation.y
	ex_yaw = face_yaw + PI
	boy.set_idle()
	for d in preview_dots:
		d.visible = false
	_update_ui()
# ------------------------------------------------------------------ explore: walking / running

func _on_dock(x: float, z: float) -> bool:
	return (absf(x) < 1.15 and z < island.dock_start_z + 0.1 and z > island.dock_end_z + 3.6) or (absf(x) < 3.1 and z <= island.dock_end_z + 3.95 and z > island.dock_end_z - 0.12)

## walkable surface height (dock deck or terrain)
func _surface(x: float, z: float) -> float:
	if _on_dock(x, z):
		return Island.DECK_Y + 0.04
	return Island.ground_h(x, z)

func _surface_kind(x: float, z: float) -> String:
	if _on_dock(x, z):
		return "wood"
	var h := Island.ground_h(x, z)
	if h < 0.02:
		return "water"
	var d := Island.shore_d(x, z)
	var n1 := sin(x * 0.37 + z * 0.21) * 0.5 + sin(x * 0.11 - z * 0.43) * 0.5
	var g := smoothstep(4.0, 7.0, -d + n1 * 1.5) * smoothstep(0.6, 1.2, h + n1 * 0.3)
	if g > 0.5 and island.path_dist(x, z) > 0.8:
		return "grass"
	return "sand"

func _can_stand(from_h: float, x: float, z: float) -> bool:
	var dock := _on_dock(x, z)
	var h := _surface(x, z)
	if not dock and h < -0.42:
		return false   # too deep: the kid only wades in the shallows
	if absf(h - from_h) > 0.42:
		return false   # dock edge / big step
	# keep off the far reef etc.: stay within the island's shallows
	if not dock and Island.shore_d(x, z) > 6.0:
		return false
	return true

const BOY_R := 0.19   # walking radius of the kid (feet to shoulders)

## does wall w stand in the way of a kid whose feet are at height y?
static func _wall_hits_y(w: Array, y: float) -> bool:
	return float(w[5]) > y + 0.12 and float(w[4]) < y + 1.2

## pushes p out of every solid thing around it (a few relaxation passes, so corners between two
## shapes settle instead of fighting); returns the resolved point and how deep it still overlaps
func _push_out(p: Vector3) -> Array:
	var q := Vector2(p.x, p.z)
	var ids := island.walls_near(q)
	var worst := 0.0
	for it in 4:
		worst = 0.0
		for i in ids:
			var w: Array = island.walls[i]
			if not _wall_hits_y(w, p.y):
				continue
			var dn := Island.wall_dist(w, q)
			var pen := BOY_R - dn.x
			if pen > 0.0:
				q += Vector2(dn.y, dn.z) * (pen + 1e-4)
				worst = maxf(worst, pen)
		if worst <= 0.0:
			break
	if worst > 0.0:
		# re-measure after the last pass
		worst = 0.0
		for i in ids:
			var w2: Array = island.walls[i]
			if _wall_hits_y(w2, p.y):
				worst = maxf(worst, BOY_R - Island.wall_dist(w2, q).x)
	return [Vector3(q.x, p.y, q.y), worst]

func _blocked_by(p: Vector3) -> Vector3:
	return _push_out(p)[0]

## how far the kid at p overlaps solid things (0 = clear); used by the self test
func penetration(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var worst := 0.0
	for i in island.walls_near(q):
		var w: Array = island.walls[i]
		if _wall_hits_y(w, p.y):
			worst = maxf(worst, BOY_R - Island.wall_dist(w, q).x)
	return worst

func _try_move(from: Vector3, d: Vector3) -> Vector3:
	var fh := _surface(from.x, from.z)
	# already overlapping something (put down there after an action): ease out of it
	var r0: Array = _push_out(from)
	if (r0[0] as Vector3).distance_to(from) > 0.005:
		var out: Vector3 = r0[0]
		var step := (out - from).limit_length(maxf(d.length(), 0.03))
		return from + step if _can_stand(fh, from.x + step.x, from.z + step.z) else from + d
	# move, then slide along whatever is in the way; terrain limits (deep water, dock edge) slide on the axes
	for cand: Vector3 in [d, Vector3(d.x, 0, 0), Vector3(0, 0, d.z)]:
		if cand.length() < 1e-6:
			continue
		var r: Array = _push_out(from + cand)
		var p: Vector3 = r[0]
		if float(r[1]) > 0.004:
			continue   # wedged between things: no room here
		if (p - from).length() > cand.length() * 1.05 + 0.002:
			p = from + (p - from).normalized() * cand.length()
			if penetration(p) > 0.004:
				continue
		if _can_stand(fh, p.x, p.z):
			p.y = from.y
			return p
	return from

func _move_input() -> Vector2:
	if demo_mode:
		return demo_input
	var v := joy.value
	var k := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if Input.is_physical_key_pressed(KEY_A): k.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): k.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): k.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): k.y += 1.0
	keys_run = Input.is_physical_key_pressed(KEY_SHIFT)
	if k.length() > 0.1:
		v = k.normalized() * (1.0 if keys_run else 0.7)
	return v.limit_length(1.0)

func _explore_tick(delta: float) -> void:
	var inp := _move_input()
	var mag := inp.length()
	var running := mag >= 0.88 or (demo_mode and demo_run)
	var fwd := Vector3(-sin(ex_yaw), 0, -cos(ex_yaw))
	var right := Vector3(cos(ex_yaw), 0, -sin(ex_yaw))
	var wish := right * inp.x - fwd * inp.y
	var target_v := Vector3.ZERO
	# a sharp turn from (nearly) standing is a turn on the spot: he stops, steps round, then sets off. Once
	# begun it goes round to the heading the stick last pointed at, even if the stick is let go
	var wish_yaw := atan2(-wish.x, -wish.z)
	var need := wrapf(wish_yaw - face_yaw, -PI, PI) if mag > 0.05 else 0.0
	var spd_now := move_vel.length()
	if mag > 0.05 and Boy.wants_spot_turn(need, spd_now):
		spot_turning = true
	if spot_turning:
		if mag > 0.05:
			spot_goal = wish_yaw
		need = wrapf(spot_goal - face_yaw, -PI, PI)
		if absf(need) < 0.03 and not boy.spin_busy():
			spot_turning = false
			spot_rate = 0.0
	if mag > 0.05 and not spot_turning:
		var spd := RUN_SPEED if running else lerpf(0.55, WALK_MAX, clampf(mag / 0.85, 0.0, 1.0))
		if wading:
			spd *= 0.6
		target_v = wish.normalized() * spd
		settle_t = 0.0
	elif settle_t < 0.6 and not spot_turning:
		# let go mid-stride: finish the step at a stroll, so the planted foot is not dragged into idle
		if boy.settling():
			settle_t += delta
			target_v = Vector3(-sin(face_yaw), 0, -cos(face_yaw)) * 0.5
		else:
			settle_t = 1.0
	# he walks the way he faces: the heading turns towards the stick as fast as his feet can corner (slowing
	# into a sharp turn), the speed eases into a run (a kid needs a couple of steps) and stops a little quicker
	var s := move_vel.length()
	var spd_t := target_v.length()
	if spot_turning:
		var st := Boy.spot_turn(face_yaw, face_yaw + need, spot_rate, delta)
		face_yaw = st[0]
		spot_rate = st[1]
	elif spd_t > 0.05:
		var mt := Boy.move_turn(face_yaw, atan2(-target_v.x, -target_v.z), s, delta)
		face_yaw = mt[0]
		spd_t *= float(mt[1])
	var acc := (6.5 if s < WALK_MAX else 4.5) if spd_t > s else 10.0
	s = move_toward(s, spd_t, acc * delta)
	move_vel = Vector3(-sin(face_yaw), 0, -cos(face_yaw)) * s
	var from := player.position
	var to := _try_move(from, move_vel * delta)
	var real := (to - from) / maxf(delta, 1e-4)
	real.y = 0.0
	if real.length() < move_vel.length() * 0.5:
		move_vel = move_vel.lerp(real, 0.5)   # bumping into something
	cur_speed = real.length()
	var h := _surface(to.x, to.z)
	ground_y = h if absf(h - ground_y) > 0.5 else lerpf(ground_y, h, 1.0 - exp(-delta * 18.0))
	to.y = ground_y
	player.position = to
	player.rotation.y = face_yaw
	wading = not _on_dock(to.x, to.z) and h < -0.03
	boy.wading = wading
	boy.pivoting = spot_turning
	boy.turn_ahead = need if spot_turning else (wrapf(wish_yaw - face_yaw, -PI, PI) if mag > 0.05 else 0.0)
	boy.set_move(cur_speed)
	if cur_speed < 0.05:
		boy.set_idle()
	_update_action_kind()

func _on_footstep(_side: int, running: bool) -> void:
	var p := player.position
	var kind := _surface_kind(p.x, p.z)
	var i := rng.randi() % 2
	var vol := -9.0 if running else -14.0
	match kind:
		"wood":
			vol += 1.5
		"grass":
			vol -= 1.0
		"water":
			vol += 1.0
			_splash(Vector3(p.x, 0.01, p.z), 0.35 if running else 0.25, false, Vector3.ZERO)
	_play("step_%s_%d" % [kind, i], vol + rng.randf_range(-1.5, 1.0), rng.randf_range(0.9, 1.1) * (1.08 if running else 1.0))

# ------------------------------------------------------------------ rest: hammock nap / sunbathing

func _begin_rest(kind: String) -> void:
	mode = Mode.REST
	rest_kind = kind
	rest_phase = 0
	rest_t = 0.0
	rest_cam_yaw = INF
	move_vel = Vector3.ZERO
	if kind == "sleep":
		var hs := _hammock_spot()
		var bed: Vector3 = hs[0]
		var along: Vector3 = hs[1]
		var side: Vector3 = hs[2]
		rest_side = side
		rest_seat = bed + side * 0.27 + Vector3(0, 0.11, 0)
		rest_seat.y = maxf(rest_seat.y, Island.ground_h(rest_seat.x, rest_seat.z) + 0.3)
		rest_lie = bed + Vector3(0, 0.12, 0) - along * 0.05
		rest_sit_b = Basis(Vector3.UP, atan2(-side.x, -side.z))
		rest_lie_b = _lie_basis(along)
		rest_approach = rest_seat + side * 0.26
	elif kind == "seat":
		var st: Dictionary = island.seats[seat_i]
		var face: Vector3 = seat_face
		seat_lying = false
		rest_side = face.cross(Vector3.UP).normalized()
		rest_sit_b = Basis(Vector3.UP, atan2(-face.x, -face.z))
		rest_approach = seat_ap
		var pl0 := boy.activity("seat", 1.0, 0.0, 0.0)
		# the clips sit on a SEAT_TOP high seat: put the pelvis over the seat point at that height
		var top: Vector3 = st["top"]
		rest_seat = top + Vector3(0, pl0.y - Island.SEAT_TOP, 0)
		# lying back: head towards his right, pelvis a little towards the foot end, back on the seat
		rest_lie = top + Vector3(0, LIE_BACK, 0) - rest_side * 0.1
		rest_lie_b = _lie_basis(rest_side)
	else:
		var td := island.towel_dir
		var tp := island.towel_pos
		rest_side = td.cross(Vector3.UP).normalized()
		rest_seat = tp + td * 0.06 + Vector3(0, 0.1, 0)
		rest_lie = tp + td * 0.1 + Vector3(0, 0.1, 0)
		rest_sit_b = Basis(Vector3.UP, atan2(-td.x, -td.z))
		var gh := Island.ground_h(tp.x - td.x * 0.8, tp.z - td.z * 0.8)
		var gf := Island.ground_h(tp.x + td.x * 0.8, tp.z + td.z * 0.8)
		rest_lie_b = _lie_basis(-td + Vector3(0, (gh - gf) / 1.6, 0))
		rest_approach = rest_seat + td * 0.36
	rest_approach.y = _surface(rest_approach.x, rest_approach.z)
	var pl := boy.activity(kind, 1.0, 0.0, 0.0)
	rest_root_sit = rest_seat - rest_sit_b * pl
	if kind == "seat":
		rest_root_sit.y = (island.seats[seat_i]["top"] as Vector3).y - Island.SEAT_TOP
	boy.end_activity()
	boy.rotation = Vector3(0, face_yaw, 0)
	_update_ui()

const LIE_BACK := 0.085   # pelvis centre above the seat when lying on the back
const SEAT_LIE_DUR := 1.6

## sit -> lie back along the bench / log (the seated boy's「躺下」)
func _lie_down() -> void:
	if mode != Mode.REST or rest_kind != "seat" or rest_phase != 4 or seat_lying:
		return
	if not island.seats[seat_i]["can_lie"]:
		return
	seat_lying = true
	rest_phase = 3
	rest_t = 0.0
	_update_ui()

func _act_kind() -> String:
	return "seatlie" if rest_kind == "seat" and seat_lying else rest_kind

## lying on the back: local +Y (head) along head_dir, local -Z (chest) facing the sky
func _lie_basis(head_dir: Vector3) -> Basis:
	var y := (head_dir.normalized() + Vector3(0, 0.12, 0)).normalized()
	var z := Vector3.DOWN - y * Vector3.DOWN.dot(y)
	z = z.normalized()
	return Basis(y.cross(z), y, z)

func _wake() -> void:
	if mode == Mode.REST and rest_phase == 4:
		rest_phase = 6 if rest_kind == "seat" and not seat_lying else 5
		rest_t = 0.0
		_update_ui()

func _rest_tick(delta: float) -> void:
	rest_t += delta
	var sleep := rest_kind == "sleep"
	var swing := Transform3D.IDENTITY
	match rest_phase:
		0:
			# walk to the spot next to the bed
			var d := rest_approach - player.position
			d.y = 0.0
			if d.length() < 0.06 or rest_t > 7.0:
				player.position = Vector3(rest_approach.x, player.position.y, rest_approach.z)
				move_vel = Vector3.ZERO
				boy.set_move(0.0)
				boy.set_idle()
				rest_phase = 1
				rest_t = 0.0
			else:
				var spd := minf(1.0, d.length() * 3.0 + 0.3)
				move_vel = move_vel.move_toward(d.normalized() * spd, 8.0 * delta)
				face_yaw = lerp_angle(face_yaw, atan2(-d.x, -d.z), 1.0 - exp(-delta * 10.0))
				var to := _try_move(player.position, move_vel * delta)
				if to.distance_to(player.position) < move_vel.length() * delta * 0.2 and rest_t > 0.5:
					to = player.position + move_vel * delta   # wedged: the spot is right there, just go
				var h := _surface(to.x, to.z)
				ground_y = lerpf(ground_y, h, 1.0 - exp(-delta * 18.0))
				to.y = ground_y
				player.position = to
				player.rotation.y = face_yaw
				boy.set_move(move_vel.length())
		1:
			# turn around: back to the bed (hammock) / face the sea (towel)
			var want := rest_sit_b.get_euler().y
			face_yaw = lerp_angle(face_yaw, want, 1.0 - exp(-delta * 9.0))
			player.rotation = Vector3(0, face_yaw, 0)
			if rest_t > 0.55:
				face_yaw = want
				rest_phase = 2
				rest_t = 0.0
		2, 6:
			var dur := 0.85
			var k := clampf(rest_t / dur, 0.0, 1.0)
			if rest_phase == 6:
				k = 1.0 - k
			var ks := smoothstep(0.0, 1.0, k)
			var pl := boy.activity(rest_kind, k, 0.0, gt)
			var root := rest_approach.lerp(rest_root_sit, ks)
			var _pw := root + rest_sit_b * pl
			swing = island.swing_hammock(swing_amp * sin(gt * 1.3)) if sleep else Transform3D.IDENTITY
			boy.global_transform = swing * Transform3D(rest_sit_b, root)
			if rest_t >= dur:
				rest_t = 0.0
				if rest_phase == 2:
					rest_phase = 4 if rest_kind == "seat" else 3
					_update_ui()
				else:
					boy.end_activity()
					player.position = _blocked_by(rest_approach)
					player.rotation = Vector3(0, face_yaw, 0)
					ground_y = _surface(player.position.x, player.position.z)
					move_vel = Vector3.ZERO
					mode = Mode.EXPLORE
					ex_yaw = face_yaw
					_update_action_kind()
					_update_ui()
		3, 5:
			var dur2 := SEAT_LIE_DUR if rest_kind == "seat" else 1.0
			var k2 := clampf(rest_t / dur2, 0.0, 1.0)
			if rest_phase == 5:
				k2 = 1.0 - k2
			var ks2 := smoothstep(0.0, 1.0, k2)
			var pl2 := boy.activity(_act_kind(), 1.0, k2, gt)
			var b := rest_sit_b.slerp(rest_lie_b, ks2)
			var w := rest_seat.lerp(rest_lie, ks2) + Vector3(0, 0.07 * sin(PI * k2), 0)
			if sleep:
				swing_amp = lerpf(swing_amp, 0.06 * ks2 + 0.01, 1.0 - exp(-delta * 2.0))
				swing = island.swing_hammock(swing_amp * sin(gt * 1.3))
			boy.global_transform = swing * Transform3D(b, w - b * pl2)
			if rest_t >= dur2:
				rest_t = 0.0
				rest_phase = 4 if rest_phase == 3 else 6
				if rest_phase == 6 and rest_kind == "seat":
					seat_lying = false
				_update_ui()
		4 when rest_kind == "seat" and not seat_lying:
			boy.activity("seat", 1.0, 1.0, rest_t)
			boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
		4:
			var pl3 := boy.activity(_act_kind(), 1.0, 1.0, gt)
			if sleep:
				swing_amp = lerpf(swing_amp, 0.07, 1.0 - exp(-delta * 1.0))
				swing = island.swing_hammock(swing_amp * sin(gt * 1.3))
			boy.global_transform = swing * Transform3D(rest_lie_b, rest_lie - rest_lie_b * pl3)
	# floating Zzz above the sleeping head
	zzz.visible = sleep and rest_phase == 4
	if zzz.visible:
		var head: Vector3 = (boy.parts["head"] as Node3D).global_position
		var cyc := fmod(rest_t * 0.5, 1.0)
		zzz.text = ["z", "z Z", "z Z z", "z Z z"][int(cyc * 4.0) % 4]
		zzz.global_position = head + Vector3(0, 0.38 + cyc * 0.12, 0) + rest_side * 0.1
		zzz.modulate.a = 1.0 - smoothstep(0.75, 1.0, cyc)

func _idle_hammock(delta: float) -> void:
	if mode == Mode.REST and rest_kind == "sleep":
		return
	swing_amp = lerpf(swing_amp, 0.015, 1.0 - exp(-delta * 1.0))
	island.swing_hammock(swing_amp * sin(gt * 1.1))
# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	_poke_audio(event)
	match mode:
		Mode.VIEW:
			_view_input(event)
		Mode.THROW:
			_throw_input(event)
		Mode.EXPLORE:
			_explore_cam_input(event)
		Mode.REST:
			var tap: bool = (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
			if tap:
				_wake()

## every tap also retries the Web Audio unlock (iOS may suspend the context after a call / app switch)
func _poke_audio(event: InputEvent) -> void:
	if not is_web or not audio_started:
		return
	if (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
		JavaScriptBridge.eval("window.__unlockAudio && window.__unlockAudio()", true)

func _explore_cam_input(event: InputEvent) -> void:
	# one finger (outside the joystick) drags the camera around the boy; pinch / wheel zooms
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
		if touches.size() == 2:
			var ps: Array = touches.values()
			pinch_d = (ps[0] - ps[1]).length()
	elif event is InputEventScreenDrag:
		var prev: Vector2 = touches.get(event.index, event.position)
		touches[event.index] = event.position
		if touches.size() == 1:
			_explore_orbit(event.position - prev)
		elif touches.size() >= 2:
			var ps: Array = touches.values()
			var d: float = (ps[0] - ps[1]).length()
			if pinch_d > 1.0 and d > 1.0:
				ex_dist = clamp(ex_dist * pinch_d / d, 3.0, 14.0)
			pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			ex_dist = clamp(ex_dist * 0.9, 3.0, 14.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			ex_dist = clamp(ex_dist * 1.11, 3.0, 14.0)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and mouse_drag:
		_explore_orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		ex_dist = clamp(ex_dist / event.factor, 3.0, 14.0)

func _explore_orbit(rel: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var k: float = 5.0 / max(min(vs.x, vs.y), 200.0)
	ex_yaw -= rel.x * k
	ex_pitch = clamp(ex_pitch + rel.y * k * 0.6, 0.05, 1.25)
	last_drag = gt

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
			if state == State.READY and not throw_walk:
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

## where the stone leaves the kid's hand (the release key pose, power independent)
func _hand_pos() -> Vector3:
	return player.global_transform * boy.release_local

func _initial_velocity() -> Vector3:
	var dir := _aim_dir()
	# half-kneeling: lower release, flatter angle, a little less power
	var crouch := boy.stance == "crouch"
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(aim_pitch - (1.0 if crouch else 0.0)))
	return dir * launch_speed(power) * (0.92 if crouch else 1.0)

func _throw() -> void:
	if power < 0.04:
		state = State.READY
		boy.set_idle()
		_update_ui()
		return
	# the swing starts now; the stone leaves the hand on the release frame (Boy.released -> _launch)
	state = State.THROWING
	boy.start_throw(power)
	_play("whoosh", lerpf(-13.0, -3.0, power), lerpf(0.85, 1.15, power) * rng.randf_range(0.96, 1.04))
	for d in preview_dots:
		d.visible = false
	_update_ui()

func _launch() -> void:
	if state != State.THROWING:
		return
	state = State.FLYING
	fly_t = 0.0
	stone_pos = _hand_pos()
	throw_origin = stone_pos
	stone_vel = _initial_velocity()
	spin = launch_spin(power) * rng.randf_range(0.92, 1.05)
	skips = 0
	throw_dist = 0.0
	stone.position = stone_pos
	stone.visible = true
	demo_release_pending = 1
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
			_hit_sound(hit)
			throw_dist = _hdist(stone_pos)
			result_text = hit + ("" if skips == 0 else "（之前漂了 %d 下）" % skips)
			stone_vel = Vector3(0, -1.0, 0)
			state = State.SINKING
			sink_timer = 0.6
			if stone_pos.y < 0.3:
				_splash(Vector3(stone_pos.x, 0.0, stone_pos.z), 0.6, false, Vector3.ZERO)
				_play("sink", -8.0, rng.randf_range(1.0, 1.15))
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
			_skip_sound(Vector2(stone_vel.x, stone_vel.z).length())
			_float_text(stone_pos, "%d" % skips)
			if skips == 5:
				_toast("5 连跳！")
				_play("combo", -6.0)
			elif skips == 10:
				_toast("10 连跳！太强了！")
				_play("combo", -5.0, 1.12)
			elif skips == 15:
				_toast("15 连跳！水漂大师！")
				_play("combo", -4.0, 1.26)
			for bn in island.buoys:
				if Vector2(stone_pos.x - bn.position.x, stone_pos.z - bn.position.z).length() < 2.0:
					_toast("擦过浮标！")
		else:
			_splash(stone_pos, 1.2, true, Vector3.ZERO)
			_play("sink", -2.0 + rng.randf_range(-1.0, 1.0), rng.randf_range(0.92, 1.06))
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
		_play("record", -4.0)
	_toast(result_text + ("\n新纪录！" if rec else "") + "\n%.1f 米" % throw_dist, 3.0)
	state = State.READY
	if skips >= 5 or (rec and skips > 0):
		boy.react("cheer")
	elif skips == 0:
		boy.react("oops")
	else:
		boy.react("")
	finish_hold = 1.2
	_update_ui()

func _stamp_footprint(side: int) -> void:
	var fp := boy.foot_points(side)
	var heel: Vector3 = fp[0]
	var ball: Vector3 = fp[1]
	var f := Vector2(ball.x - heel.x, ball.z - heel.z)
	if f.length() < 0.03:
		return
	var c := Vector2(heel.x, heel.z) + f * 0.6
	# only on dry or wet sand: not on the dock, the grass, in the sea or under the running wash
	if _surface_kind(c.x, c.y) != "sand" or Island.wash_covers(c.x, c.y, gt, 0.012):
		return
	print_buf[print_i] = Vector4(c.x, c.y, atan2(f.y, f.x), gt)
	print_wash[print_i] = -1.0
	print_i = (print_i + 1) % PRINTS
	_upload_prints()

## the swash erases the prints it runs over (same wash front as the terrain shader); old ones fade out
func _update_prints() -> void:
	var dirty := false
	for i in PRINTS:
		var fp := print_buf[i]
		if print_wash[i] < 0.0 and gt - fp.w < PRINT_LIFE and Island.wash_covers(fp.x, fp.y, gt, 0.004):
			print_wash[i] = gt
			dirty = true
	if dirty:
		_upload_prints()

func _upload_prints() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in PRINTS:
		var fp := print_buf[i]
		if gt - fp.w < PRINT_LIFE and (print_wash[i] < 0.0 or gt - print_wash[i] < 1.0):
			lo = lo.min(Vector2(fp.x, fp.y))
			hi = hi.max(Vector2(fp.x, fp.y))
	var box := Vector4(lo.x - 0.25, lo.y - 0.25, hi.x + 0.25, hi.y + 0.25) if lo.x < INF else Vector4(1, 1, -1, -1)
	island.terrain_mat.set_shader_parameter("prints", print_buf)
	island.terrain_mat.set_shader_parameter("print_wash", print_wash)
	island.terrain_mat.set_shader_parameter("print_box", box)

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
	crown.layers = 1 | WaterReflection.SKIP_LAYER
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
		spray.layers = 1 | WaterReflection.SKIP_LAYER
		spray.emitting = true
		get_tree().create_timer(1.5).timeout.connect(spray.queue_free)
	_add_ripple(p, 1.0 if big else (0.75 if strength > 0.4 else 0.3))
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

# ------------------------------------------------------------------ audio
# All sounds are synthesized by tools/synth_audio.py (no third-party recordings).
# Plain non-positional players: compatible with the Web "Sample" playback mode used on iOS Safari.

func _build_audio() -> void:
	var names := ["skip_0", "skip_1", "skip_2", "skip_3", "sink", "whoosh", "hit_wood", "hit_rock", "hit_sand", "combo", "record"]
	for k in ["sand", "wood", "grass", "water"]:
		for i in 2:
			names.append("step_%s_%d" % [k, i])
	for n in names:
		sfx[n] = load("res://audio/%s.ogg" % n)
	var ocean: AudioStreamOggVorbis = load("res://audio/ocean_loop.ogg")
	ocean.loop = true
	amb = AudioStreamPlayer.new()
	amb.stream = ocean
	amb.volume_db = -6.0
	add_child(amb)
	var crackle: AudioStreamOggVorbis = load("res://audio/fire_loop.ogg")
	crackle.loop = true
	fire_amb = AudioStreamPlayer.new()
	fire_amb.stream = crackle
	fire_amb.volume_db = -60.0
	add_child(fire_amb)
	var crickets: AudioStreamOggVorbis = load("res://audio/night_loop.ogg")
	crickets.loop = true
	night_amb = AudioStreamPlayer.new()
	night_amb.stream = crickets
	night_amb.volume_db = -60.0
	add_child(night_amb)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)

func _on_start_input(event: InputEvent) -> void:
	# start on the *release* of the tap: iOS only counts touchend / click as a user activation
	var released: bool = (event is InputEventMouseButton and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	if released and not audio_started:
		get_viewport().set_input_as_handled()
		_start_audio()

func _start_audio() -> void:
	if audio_started:
		return
	audio_started = true
	if start_overlay:
		start_overlay.queue_free()
		start_overlay = null
	if is_web:
		JavaScriptBridge.eval("window.__unlockAudio && window.__unlockAudio()", true)
	amb.play()
	amb.stream_paused = muted
	fire_amb.play()
	night_amb.play()
	fire_amb.stream_paused = muted
	chime_pending = true
	chime_wait = 0.0
	if is_web:
		tip_box.visible = true
		tip_timer = 9.0

## a short "ding" right after start proves to the player that sound works
func _audio_tick(delta: float) -> void:
	if tip_timer > 0.0:
		tip_timer -= delta
		if tip_timer <= 0.0:
			tip_box.visible = false
	if not chime_pending:
		return
	chime_wait += delta
	var ok := true
	if is_web:
		ok = bool(JavaScriptBridge.eval("window.__audioUnlocked === true", true)) or chime_wait > 4.0
	if ok and chime_wait > 0.25:
		chime_pending = false
		_play("combo", -9.0)
		if is_web:
			JavaScriptBridge.eval("window.__chimePlayed = (window.__chimePlayed || 0) + 1", true)

func _toggle_night() -> void:
	night_on = not night_on
	_save_best()
	_toast("夜晚：篝火和灯都亮起来了" if night_on else "天亮了", 1.6)
	_update_ui()

## day <-> night over ~2.5 s: sky, sun -> moon, ambient, fog, water glints, lamps, fire, sounds
func _update_night(delta: float, force := false) -> void:
	var target := 1.0 if night_on else 0.0
	if night_k == target and not force:
		return
	night_k = move_toward(night_k, target, delta / 2.5)
	var k := smoothstep(0.0, 1.0, night_k)
	RenderingServer.global_shader_parameter_set("night_k", k)
	sky_mat.sky_top_color = Color(0.40, 0.58, 0.76).lerp(Color(0.025, 0.05, 0.13), k)
	sky_mat.sky_horizon_color = Color(0.78, 0.85, 0.88).lerp(Color(0.09, 0.14, 0.25), k)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.30, 0.46, 0.52).lerp(Color(0.02, 0.05, 0.09), k)
	var qd := Basis.from_euler(SUN_DAY * PI / 180.0).get_rotation_quaternion()
	var qn := Basis.from_euler(MOON_NIGHT * PI / 180.0).get_rotation_quaternion()
	sun.basis = Basis(qd.slerp(qn, k))
	sun.light_energy = lerpf(1.0, 0.42, k)
	sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(0.62, 0.72, 1.0), k)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY if k > 0.5 else DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	env.ambient_light_color = Color(0.22, 0.30, 0.50)
	env.ambient_light_sky_contribution = 1.0 - k
	env.ambient_light_energy = lerpf(0.75, 0.42, k)
	env.fog_light_color = Color(0.80, 0.86, 0.88).lerp(Color(0.07, 0.11, 0.19), k)
	env.tonemap_exposure = lerpf(1.0, 1.2, k)
	env.adjustment_saturation = lerpf(0.85, 0.95, k)
	var moon := sun.global_basis.z.normalized()
	island.water_mat.set_shader_parameter("glint_dir", moon)
	island.water_mat.set_shader_parameter("glint_col", Color(1.0, 0.95, 0.85).lerp(Color(0.8, 0.88, 1.0), k))
	island.water_mat.set_shader_parameter("night", k)
	island.glow_mat.set_shader_parameter("boost", lerpf(1.5, 3.4, k))
	island.cloud_mat.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(0.13, 0.16, 0.26), k))
	island.campfire.night = k
	for tn in island.torches:
		tn.night = k
	for b in birds:
		(b["node"] as Node3D).visible = k < 0.5
	if night_amb:
		night_amb.volume_db = lerpf(-60.0, -13.0, sqrt(k))

func _toggle_sound() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	if audio_started:
		amb.stream_paused = muted
		fire_amb.stream_paused = muted
		night_amb.stream_paused = muted
		if not muted and not amb.playing:
			amb.play()
		if not muted and not fire_amb.playing:
			fire_amb.play()
		if not muted and not night_amb.playing:
			night_amb.play()
	if muted:
		for p in sfx_players:
			p.stop()
	else:
		_play("combo", -12.0, 1.2)
	_update_ui()

func _play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if muted or not audio_started or not sfx.has(n):
		return
	var p := sfx_players[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_players.size()
	p.stop()
	p.stream = sfx[n]
	p.volume_db = vol_db
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()

## light "pat" of a skip: louder and brighter when fast, never twice the same take in a row
func _skip_sound(speed: float) -> void:
	var k := clampf(speed / 18.0, 0.0, 1.0)
	var i := rng.randi() % 4
	if i == last_skip:
		i = (i + 1 + rng.randi() % 3) % 4
	last_skip = i
	_play("skip_%d" % i, lerpf(-11.0, -2.0, k) + rng.randf_range(-1.5, 1.0), lerpf(0.86, 1.18, k) * rng.randf_range(0.94, 1.07))

func _hit_sound(hit: String) -> void:
	if hit.contains("沙滩"):
		_play("hit_sand", -3.0, rng.randf_range(0.9, 1.1))
	elif hit.contains("礁石") or hit.contains("灯塔"):
		_play("hit_rock", -2.0, rng.randf_range(0.9, 1.1))
	else:
		_play("hit_wood", -2.0, rng.randf_range(0.9, 1.1))

## ocean ambience gets quieter as the camera moves away from the shore / up into the sky
func _update_audio(_delta: float) -> void:
	if not audio_started or muted:
		return
	var cp := camera.global_position
	var d := absf(Island.shore_d(cp.x, cp.z)) + maxf(cp.y - 2.0, 0.0) * 0.6
	var want := lerpf(-3.0, -15.0, smoothstep(6.0, 70.0, d)) - 4.0 * night_k   # softer waves at night
	amb.volume_db = lerpf(amb.volume_db, want, 0.05)
	# campfire crackle: heard from a few metres away, loud when sitting by it
	var fd := minf(cp.distance_to(island.campfire_pos), player.global_position.distance_to(island.campfire_pos) + 1.5)
	var fwant := lerpf(-4.0, -40.0, smoothstep(1.5, 16.0, fd))
	fire_amb.volume_db = lerpf(fire_amb.volume_db, fwant, 0.08)

# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if OS.has_feature("web"):
		safe_t += delta
		if safe_t > 1.0:
			safe_t = 0.0
			if _read_safe_area():
				_layout_ui()
	gt += delta
	island.set_time(gt)
	var tall := _tall()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var fov_want := (66.0 if tall else 52.0)
	if mode == Mode.EXPLORE and not demo_cam:
		fov_want = 44.0 if tall else 36.0
	camera.fov = fov_want if gt < 0.1 else lerpf(camera.fov, fov_want, 1.0 - exp(-delta * 3.0))
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
	_update_wade_ring(delta)
	_watch_fps(delta)
	_update_night(delta)
	night_fx.apply(night_k, camera.global_position, sun.global_basis.z.normalized(), delta)
	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer < 0.5:
			lbl_toast.modulate.a = max(toast_timer / 0.5, 0.0)
	# the stick only exists while exploring; never leave it hidden (or shown) after a mode change
	if joy.visible != (mode == Mode.EXPLORE):
		_update_ui()
	if mode != Mode.EXPLORE:
		spot_turning = false
		boy.pivoting = false
		boy.turn_ahead = 0.0
	match mode:
		Mode.EXPLORE:
			_explore_tick(delta)
		Mode.REST:
			_rest_tick(delta)
	_idle_hammock(delta)
	if mode != Mode.REST:
		zzz.visible = false
	match state:
		State.AIMING:
			charge_t += delta
			power = pingpong(charge_t / (POWER_CYCLE * 0.5), 1.0)
			power_bar.value = power
			var deg := wrapf(rad_to_deg(aim_yaw), -180.0, 180.0)
			lbl_aim.text = "力度 %d%%   角度 %d°   方向 %s%d°" % [roundi(power * 100), roundi(aim_pitch), "左" if deg > 0.5 else ("右" if deg < -0.5 else ""), absi(roundi(deg))]
			boy.charge(power)
			_update_preview()
		State.READY:
			if mode == Mode.THROW and not throw_walk:
				boy.set_idle()
		State.FLYING, State.SINKING:
			fly_t += delta
	if mode == Mode.THROW and throw_walk:
		_throw_walk_tick(delta)
	elif mode == Mode.THROW and (state == State.READY or state == State.AIMING):
		player.rotation.y = lerp_angle(player.rotation.y, aim_yaw, 1.0 - exp(-delta * 10.0))
	_update_camera(delta)
	var focus := player.global_position + Vector3(0, 0.7, 0)
	if demo_nocut:
		focus.y = -100.0
	island.foliage_mat.set_shader_parameter("focus", focus)
	island.leaf_mat.set_shader_parameter("focus", focus)
	island.static_mat.set_shader_parameter("focus", focus)
	island.torch_mat.set_shader_parameter("focus", focus)
	_update_prints()
	_update_audio(delta)
	_audio_tick(delta)

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

## throw-mode camera: rear three-quarter view, the kid in front and the sea beyond
func _throw_cam() -> Array:
	var tall := _tall()
	var dir := _aim_dir()
	var crouch := boy.stance == "crouch"
	var t := player.global_position + Vector3(0, (0.8 if tall else 0.68) - (0.12 if crouch else 0.0), 0) + dir * (0.55 if tall else 1.3)
	return [t, aim_yaw + (0.36 if tall else 0.8), 0.15 if tall else 0.2, 3.4 if tall else 3.9]

func _explore_cam() -> Array:
	var tall := _tall()
	var t := player.global_position + Vector3(0, 0.55, 0)
	return [t, ex_yaw, ex_pitch, ex_dist * (1.1 if tall else 1.0)]

func _rest_cam() -> Array:
	var tall := _tall()
	var t := rest_lie + Vector3(0, 0.25, 0)
	var dist := 3.0 if not tall else 3.6
	if rest_cam_yaw == INF:
		var off: Vector3
		if rest_kind == "sleep":
			off = rest_side
			var along := (island.hammock_b - island.hammock_a).normalized()
			off = (off + Vector3(along.x, 0, along.z) * 0.45).normalized()
		elif rest_kind == "seat":
			off = (seat_face * 0.45 + rest_side * 0.9).normalized()
		else:
			off = (rest_side * 0.75 + island.towel_dir * 0.75).normalized()
		rest_cam_yaw = _clear_yaw(t, atan2(off.x, off.z), 0.42, dist)
	return [t, rest_cam_yaw, 0.42, dist]

## the yaw closest to `pref` from which no palm trunk stands between the camera and the resting kid
func _clear_yaw(t: Vector3, pref: float, pitch: float, dist: float) -> float:
	var along := island.towel_dir * 0.7 if rest_kind != "sleep" else (island.hammock_b - island.hammock_a).normalized() * 0.7
	if rest_kind == "seat":
		along = rest_side * 0.3
	var looks: Array[Vector3] = [t, t + along, t - along]
	var best := pref
	var best_cost := INF
	for n in 15:
		var dy := floori((n + 1) * 0.5) * 0.17 * (1.0 if n % 2 == 1 else -1.0)
		var yaw := pref + dy
		var cam := t + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
		var hits := 0
		for l in looks:
			for tr: Array in island.trunks:
				if _seg_hits_trunk(cam, l, tr):
					hits += 1
					break
		var cost := hits * 10.0 + absf(dy)
		if cost < best_cost:
			best_cost = cost
			best = yaw
		if hits == 0:
			break
	return best

func _seg_hits_trunk(a: Vector3, b: Vector3, pts: Array) -> bool:
	if Vector2(pts[0].x - a.x, pts[0].z - a.z).length() > a.distance_to(b) + 6.0:
		return false
	for i in pts.size() - 1:
		var c := Geometry3D.get_closest_points_between_segments(a, b, pts[i], pts[i + 1])
		if c[0].distance_to(c[1]) < 0.42:
			return true
	return false

func _snap_explore_cam() -> void:
	ex_yaw = face_yaw
	var c := _explore_cam()
	cam_target = c[0]; cam_yaw = c[1]; cam_pitch = c[2]; cam_dist = c[3]

func _update_camera(delta: float) -> void:
	if demo_cam:
		if demo_track.size() > 0:
			var tr: Array = demo_track
			cam_target = player.global_position + Vector3(0, tr[3], 0)
			cam_yaw = (float(tr[0]) if tr.size() > 4 else face_yaw + float(tr[0]))
			cam_pitch = tr[1]
			cam_dist = tr[2]
		_apply_camera()
		return
	var want: Array
	var k: float
	if mode == Mode.THROW and (state == State.FLYING or state == State.SINKING) and fly_t > 0.45:
		var tall := _tall()
		var dir := Vector3(stone_vel.x, 0, stone_vel.z)
		dir = dir.normalized() if dir.length() > 0.5 else _aim_dir()
		want = [Vector3(stone_pos.x, max(stone_pos.y * 0.5, 0.3), stone_pos.z) + dir * 2.0, atan2(-dir.x, -dir.z) + 0.35, 0.42 if tall else 0.32, 11.0 if tall else 9.0]
		k = 1.0 - exp(-delta * 4.0 * smoothstep(0.45, 1.1, fly_t))
	elif mode == Mode.VIEW:
		if not dragging:
			view_yaw += orbit_vel.x * delta
			view_pitch = clamp(view_pitch + orbit_vel.y * delta, 0.06, 1.42)
			orbit_vel *= exp(-delta * 3.5)
		var head := player.global_position + Vector3(0, 0.8, 0)
		want = [head.lerp(Vector3(0, 1.5, -2.0), smoothstep(10.0, 45.0, view_dist)), view_yaw, view_pitch, view_dist]
		k = 1.0 - exp(-delta * 9.0)
	elif mode == Mode.THROW:
		var hold := finish_hold > 0.0
		finish_hold -= delta
		want = _throw_cam()
		if (state == State.THROWING or state == State.FLYING) and not _tall():
			want[3] = float(want[3]) + 0.4
		k = 1.0 - exp(-delta * (2.2 if hold else 3.0))
		if hold:
			# coming back from the stone view: re-centre on the kid first, then dolly in, so the
			# camera never passes in front of him
			cam_target = cam_target.lerp(want[0], 1.0 - exp(-delta * 5.5))
			cam_dist = maxf(cam_dist, float(want[3]))
	elif mode == Mode.REST and rest_phase >= 2:
		want = _rest_cam()
		k = 1.0 - exp(-delta * 1.8)
	else:
		# explore follow camera: drags turn it, otherwise it slowly swings in behind the walking kid
		if cur_speed > 0.3 and gt - last_drag > 1.5:
			var rate := 0.6 + 0.5 * clampf(cur_speed / RUN_SPEED, 0.0, 1.0)
			ex_yaw = lerp_angle(ex_yaw, face_yaw, 1.0 - exp(-delta * rate))
		want = _explore_cam()
		k = 1.0 - exp(-delta * 6.0)
		if mode == Mode.REST:
			k = 1.0 - exp(-delta * 3.0)
	cam_target = cam_target.lerp(want[0], k)
	cam_yaw = lerp_angle(cam_yaw, want[1], k)
	cam_pitch = lerp(cam_pitch, want[2], k)
	cam_dist = lerp(cam_dist, want[3], k)
	_apply_camera()

func _cam_blocked(q: Vector3) -> bool:
	if mode == Mode.THROW or mode == Mode.VIEW:
		# the high follow camera ignores these small dock props: the cut-out shader dithers them instead
		for bl in island.cam_blockers:
			if q.distance_to(bl[0]) < float(bl[1]):
				return true
		return false
	for ob in island.obstacles:
		var c: Vector2 = ob[0]
		if q.y < float(ob[2]) and q.y > float(ob[4]) and Vector2(q.x - c.x, q.z - c.y).length() < float(ob[1]) + 0.25:
			return true
	return false

func _apply_camera() -> void:
	var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	# small spring arm: pull the camera in front of props / trunks / walls instead of clipping through
	if cam_dist < 20.0 and (not demo_cam or demo_track.size() > 0):
		for i in range(4, 25):
			var q := cam_target + off * (i / 24.0)
			if _cam_blocked(q):
				off *= maxf((i - 1) / 24.0, 1.3 / cam_dist)
				break
	var pos := cam_target + off
	var floor_y: float = max(Island.ground_h(pos.x, pos.z), 0.0) + 0.35
	if _on_dock(pos.x, pos.z):
		floor_y = maxf(floor_y, Island.DECK_Y + 0.4)
	if pos.y < floor_y:
		pos.y = floor_y
	camera.global_position = pos
	camera.look_at(cam_target, Vector3.UP)
	if refl:
		refl.update()

# ------------------------------------------------------------------ water reflection

var refl: WaterReflection
## 0 full, 1 lighter reflection (smaller, every other frame), 2 reflection off (the shader's approximations),
## 3 also no sun shadows (the kid keeps his blob shadow)
var refl_level := 0
var refl_auto := true
var fps_t := 0.0
var fps_n := 0
var fps_avg := 0.0
var fps_low := 0
var lbl_fps: Label
var url_opts := {}

## ?name=value in the page URL (web) or --name=value on the command line
func _opt(name: String, def := "") -> String:
	if url_opts.is_empty():
		url_opts["_"] = true
		if is_web:
			var q := str(JavaScriptBridge.eval("location.search", true)).trim_prefix("?")
			for kv in q.split("&", false):
				var p := kv.split("=")
				url_opts[p[0]] = p[1] if p.size() > 1 else "1"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--"):
				var p := a.substr(2).split("=")
				url_opts[p[0]] = p[1] if p.size() > 1 else "1"
	return str(url_opts.get(name, def))

func _build_reflection() -> void:
	island.water_mi.layers = WaterReflection.WATER_LAYER
	wade_ring.layers = WaterReflection.WATER_LAYER
	refl = WaterReflection.new()
	add_child(refl)
	refl.setup(camera, sun)
	island.water_mat.set_shader_parameter("refl_tex", refl.texture())
	island.water_mat.set_shader_parameter("refl_guard", WaterReflection.GUARD)
	var want := _opt("refl", "auto")
	refl_auto = want == "auto"
	_set_refl_level({"0": 2, "low": 1}.get(want, 0))
	if _opt("shadow") == "0":
		_set_refl_level(3)
	# lights whose glitter streaks across the waves at night: the campfire, the lighthouse, then the lamps
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	pos.append(Vector4(island.campfire_pos.x, island.campfire_pos.y + 0.45, island.campfire_pos.z, 2.2))
	col.append(Vector4(1.0, 0.55, 0.2, 1.0))
	pos.append(Vector4(island.beacon_pos.x, island.beacon_pos.y, island.beacon_pos.z, 6.0))
	col.append(Vector4(1.0, 0.86, 0.58, 1.0))
	for l: Array in island.lamps:
		if pos.size() >= 12:
			break
		var lp: Vector3 = l[0]
		pos.append(Vector4(lp.x, lp.y, lp.z, 0.9 if l[1] == "path" else 1.4))
		col.append(Vector4(1.0, 0.72, 0.38, 1.0))
	while pos.size() < 12:
		pos.append(Vector4.ZERO)
		col.append(Vector4.ZERO)
	island.water_mat.set_shader_parameter("lamp_pos", pos)
	island.water_mat.set_shader_parameter("lamp_col", col)
	if _opt("fps") != "":
		lbl_fps = _label(18, Color(1, 1, 0.8))
		lbl_fps.position = Vector2(18, 150)
		ui_root.add_child(lbl_fps)

func _set_refl_level(l: int) -> void:
	refl_level = l
	refl.scale = 0.35 if l == 0 else 0.25
	refl.every = 1 if l == 0 else 2
	refl.set_enabled(l < 2)
	island.water_mat.set_shader_parameter("refl_on", 1.0 if l < 2 else 0.0)
	sun.shadow_enabled = l < 3

## a phone that cannot keep up drops the reflection to the lighter setting, then to the approximations,
## then the sun's shadow maps
func _watch_fps(delta: float) -> void:
	fps_t += delta
	fps_n += 1
	if fps_t < 2.0:
		return
	fps_avg = fps_n / fps_t
	fps_t = 0.0
	fps_n = 0
	# two slow windows in a row (4 s), so one hitch such as a first-use shader compile does not count
	fps_low = fps_low + 1 if fps_avg < 26.0 else 0
	if refl_auto and not demo_mode and gt > 5.0 and fps_low >= 2 and refl_level < 3:
		_set_refl_level(refl_level + 1)
		fps_low = 0
	if lbl_fps:
		lbl_fps.text = "%.0f fps · 倒影 %s" % [fps_avg, ["高", "低", "关", "关 · 无阴影"][refl_level]]
		var dc := Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
		var vt := Viewport.RENDER_INFO_TYPE_VISIBLE
		print("FPS %.1f refl %d night %d draws %d+%d size %s" % [fps_avg, refl_level, int(night_on),
			get_viewport().get_render_info(vt, dc), refl.vp.get_render_info(vt, dc) if refl_level < 2 else 0,
			str(refl.vp.size)])

# ------------------------------------------------------------------ save

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_skips = int(cf.get_value("best", "skips", 0))
		best_dist = float(cf.get_value("best", "dist", 0.0))
		saved_night = bool(cf.get_value("settings", "night", false))

## best record and settings (night mode); user:// is IndexedDB in the web build, so it survives reloads
func _save_best() -> void:
	if demo_mode:
		return
	var cf := ConfigFile.new()
	cf.set_value("best", "skips", best_skips)
	cf.set_value("best", "dist", best_dist)
	cf.set_value("settings", "night", night_on)
	cf.save(SAVE_PATH)

# ------------------------------------------------------------------ test hooks

func _run_sim_report() -> void:
	for stc in ["stand", "crouch"]:
		boy.stance = stc
		print("SIM stance ", stc, " release ", boy.release_local)
		_sim_block()
	print("SIM obstacles=%d palms=%d" % [island.obstacles.size(), island.palm_spots.size()])
	# gait stress test (dev/ is not exported, so only where the sources are)
	if ResourceLoader.exists("res://dev/gait_probe.gd"):
		for line in load("res://dev/gait_probe.gd").stress(self):
			print("SIM ", line)

func _sim_block() -> void:
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

func _demo_shot(name: String) -> void:
	if demo_shots.has(name):
		return
	demo_shots[name] = true
	var prefix := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotprefix="):
			prefix = a.substr(13)
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/%s/%s%s.png" % [shot_dir, prefix, name])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			path = a.substr(10).path_join(prefix + name + ".png")
	img.save_png(path)
	print("DEMO screenshot ", path)

# ------------------------------------------------------------------ v4/v5 scripted demo (screenshots / video)
# godot --path . --fixed-fps 30 --resolution 1280x720 -- --demo4 [--portrait] [--shotdir=/abs/dir]
# godot --path . --fixed-fps 30 --write-movie x.avi -- --video4=walk|throw|sleep|sun|getup|gait|prints

func _wait(sec: float) -> void:
	var t0 := gt
	while gt - t0 < sec:
		await get_tree().process_frame

var walk_gen := 0

func _walk_to(target: Vector3, run: bool, timeout := 14.0) -> void:
	walk_gen += 1
	var my := walk_gen
	demo_run = run
	var t0 := gt
	while gt - t0 < timeout:
		if my != walk_gen:
			return
		var d := target - player.position
		d.y = 0.0
		if d.length() < 0.35:
			break
		var fwd := Vector3(-sin(ex_yaw), 0, -cos(ex_yaw))
		var right := Vector3(cos(ex_yaw), 0, -sin(ex_yaw))
		var dn := d.normalized()
		demo_input = Vector2(dn.dot(right), -dn.dot(fwd)) * (1.0 if run else 0.72)
		await get_tree().process_frame
	if my == walk_gen:
		demo_input = Vector2.ZERO
		demo_run = false

func _hd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _stop_walk() -> void:
	walk_gen += 1
	demo_input = Vector2.ZERO
	demo_run = false

func _place(p: Vector3, yaw: float) -> void:
	_stop_walk()
	toast_timer = 0.0
	lbl_toast.modulate.a = 0.0
	p.y = _surface(p.x, p.z)
	player.position = p
	ground_y = p.y
	face_yaw = yaw
	player.rotation = Vector3(0, yaw, 0)
	move_vel = Vector3.ZERO
	_snap_explore_cam()
	_update_action_kind()

func _track(yaw_off: float, pitch: float, dist: float, h: float) -> void:
	demo_cam = true
	demo_track = [yaw_off, pitch, dist, h]

func _free_cam() -> void:
	demo_cam = false
	demo_track = []

func _fixed_cam(target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	demo_cam = true
	demo_track = []
	cam_target = target; cam_yaw = yaw; cam_pitch = pitch; cam_dist = dist

func _shot(name: String) -> void:
	if demo_seg == "":
		_demo_shot(name)

func _throw_sequence(pre: String, crouch: bool, close: bool) -> void:
	_place(Vector3(0.3, 0, island.dock_end_z + 1.6), 0.1)
	await _wait(0.5)
	_shot(pre + "dock_ui")
	_enter_throw()
	boy.stance = "crouch" if crouch else "stand"
	_toast("半蹲投掷：出手更低、贴着水面" if crouch else "站立投掷", 1.4)
	_update_ui()
	await _wait(1.3)
	_shot(pre + "throw_ready")
	_begin_aim(Vector2.ZERO)
	aim_pitch = 3.0
	var t0 := gt
	while gt - t0 < 1.5:
		charge_t = minf((gt - t0) / 1.1, 1.0) * 0.9 * POWER_CYCLE * 0.5
		if demo_seg != "":
			aim_yaw = 0.1 + sin((gt - t0) * 2.0) * 0.05
		await get_tree().process_frame
	_shot(pre + "charge_game")
	if close:
		_fixed_cam(player.global_position + Vector3(0, 0.45, 0) + _aim_dir() * 0.2, aim_yaw + 1.45, 0.08, 2.4)
		await _wait(0.25)
		charge_t = 0.9 * POWER_CYCLE * 0.5
		_shot(pre + "crouch_charge_side" if crouch else pre + "stand_charge_side")
	charge_t = 0.9 * POWER_CYCLE * 0.5
	_throw()
	while state == State.THROWING:
		await get_tree().process_frame
	await get_tree().process_frame
	_shot(pre + ("crouch_release" if crouch else "stand_release"))
	while boy.anim == "throw" and boy.anim_t < 0.5:
		await get_tree().process_frame
	_shot(pre + ("crouch_follow" if crouch else "stand_follow"))
	_free_cam()
	fly_t = 0.0
	while state == State.FLYING and skips < 4:
		await get_tree().process_frame
	await _wait(0.2)
	_shot(pre + "skipping")
	while state != State.READY:
		await get_tree().process_frame
	await _wait(0.9)
	_shot(pre + "result")
	await _wait(1.0)
	_shot(pre + "result_b")
	await _wait(1.4)
	_shot(pre + "result_c")

func _rest_sequence(pre: String, kind: String, close: bool) -> void:
	if kind == "sleep":
		var hs := _hammock_spot()
		var bed: Vector3 = hs[0]
		var side: Vector3 = hs[2]
		var p := bed + side * 1.6
		_place(p, atan2(side.x, side.z))
	else:
		var td := island.towel_dir
		var sd := td.cross(Vector3.UP).normalized()
		var p2 := island.towel_pos + sd * 1.4 + td * 0.6
		_place(p2, atan2(sd.x, sd.z))
	await _wait(0.6)
	_shot(pre + kind + "_prompt")
	_begin_rest(kind)
	while rest_phase < 3:
		await get_tree().process_frame
	_shot(pre + kind + "_seated")
	await _wait(0.45)
	_shot(pre + kind + "_lying_down")
	while rest_phase < 4:
		await get_tree().process_frame
	await _wait(2.4)
	_shot(pre + kind + "_rest")
	if close:
		var head: Vector3 = (boy.parts["head"] as Node3D).global_position
		var off := rest_side
		if kind == "sun":
			off = (island.towel_dir * 0.8 + rest_side * 0.6).normalized()
		_fixed_cam(head + Vector3(0, -0.05, 0), atan2(off.x, off.z) + (0.3 if kind == "sleep" else 0.0), 0.75 if kind == "sleep" else 0.6, 1.25)
		await _wait(0.3)
		_shot(pre + kind + "_close")
		var pel: Vector3 = (boy.parts["pelvis"] as Node3D).global_position
		_fixed_cam(pel + Vector3(0, 0.1, 0), atan2(off.x, off.z) - 0.2, 0.55, 2.3)
		await _wait(0.3)
		_shot(pre + kind + "_body")
		_free_cam()

## the sea along the beach: shallows, seabed, foam lines (high 3/4 view like the game, low and wide)
func _shore_sequence(pre: String) -> void:
	for th: float in [-1.05, 2.2]:
		var tag := "a" if th < 0.0 else "b"
		var sea := Island.dir_at(th)
		var p := island.shore_pt(th, 0.9)
		var along := sea.cross(Vector3.UP)
		_place(p, atan2(-sea.x, -sea.z) + 0.5)
		await _wait(0.6)
		_fixed_cam(p + sea * 2.2 + Vector3(0, 0.2, 0), atan2(sea.x, sea.z) + 0.55, 0.72, 7.0)
		await _wait(0.4)
		_shot(pre + "13%s_shore_top" % tag)
		_fixed_cam(p + sea * 1.2 + Vector3(0, 0.4, 0), atan2(along.x, along.z) - 0.5, 0.2, 5.0)
		await _wait(0.4)
		_shot(pre + "14%s_shore_low" % tag)
		_fixed_cam(p + sea * 3.0, atan2(sea.x, sea.z) - 0.6, 0.5, 14.0)
		await _wait(0.4)
		_shot(pre + "15%s_shore_wide" % tag)
		_free_cam()
	var wp := island.shore_pt(-1.2, -1.3)
	_place(wp, 0.4)
	_walk_to.call(island.shore_pt(-1.35, -1.1), false)
	await _wait(1.2)
	_shot(pre + "16_wading")
	_stop_walk()

## v8 stills: the doodled sign, the campfire, sitting on the bench / log / lounger, throw reach
func _v8_sequence(pre: String) -> void:
	var sb := island.sign_board
	var sn := sb.global_basis.z.normalized()
	var sc := sb.global_position
	_place(sc + sn * 2.6 + Vector3(0.8, 0, 0), 0.0)
	_fixed_cam(sc + Vector3(0, -0.05, 0), atan2(sn.x, sn.z) + 0.12, 0.08, 1.45)
	await _wait(0.5)
	_shot(pre + "20_sign_close")
	_fixed_cam(sc + Vector3(0, -0.55, 0), atan2(sn.x, sn.z) + 0.5, 0.1, 3.0)
	await _wait(0.4)
	_shot(pre + "21_sign_post")
	_fixed_cam(sc + Vector3(0, -0.05, 0), atan2(-sn.x, -sn.z) - 0.2, 0.1, 1.6)
	await _wait(0.4)
	_shot(pre + "22_sign_back")
	# campfire close and with the kid on a log
	var c := island.campfire_pos
	_place(c + Vector3(3.5, 0, 3.5), 0.0)
	_fixed_cam(c + Vector3(0, 0.45, 0), 0.6, 0.22, 2.4)
	await _wait(1.0)
	_shot(pre + "23_fire_close")
	_fixed_cam(c + Vector3(0, 0.3, 0), 2.0, 0.42, 5.5)
	await _wait(0.3)
	_shot(pre + "24_fire_wide")
	for i in island.seats.size():
		var st: Dictionary = island.seats[i]
		var face: Vector3 = st["face"]
		_place((st["approach"] as Vector3) + face * 0.9, atan2(face.x, face.z))
		_free_cam()
		await _wait(0.4)
		_shot(pre + "25_seat_prompt_%d" % i)
		_on_action()
		while rest_phase < 4:
			await get_tree().process_frame
		await _wait(1.6)
		_shot(pre + "26_seat_%d" % i)
		_wake()
		while mode != Mode.EXPLORE:
			await get_tree().process_frame
	# throw: the arm reaching out after the release, gameplay camera and from the side
	for crouch: bool in [false, true]:
		for side: bool in [false, true]:
			_place(Vector3(0.2, 0, island.dock_end_z + 1.5), 0.0)
			await _wait(0.2)
			_enter_throw()
			boy.stance = "crouch" if crouch else "stand"
			await _wait(1.3)
			if side:
				demo_cam = true
				demo_track = [aim_yaw + PI * 0.5 + 0.1, 0.1, 2.5, 0.55 if not crouch else 0.4, true]
			_begin_aim(Vector2.ZERO)
			aim_pitch = 3.0
			charge_t = 0.9 * POWER_CYCLE * 0.5
			await _wait(1.0)
			_throw()
			var tag := ("crouch" if crouch else "stand") + ("_side" if side else "_game")
			for k: Array in [[0.0, "a_cock"], [0.15, "b_release"], [0.21, "c_reach"], [0.32, "d_sweep"], [0.46, "e_wrap"]]:
				while boy.anim_t < float(k[0]) - 0.001:
					await get_tree().process_frame
				_shot(pre + "27_throw_%s_%s" % [tag, k[1]])
			_free_cam()
			while state != State.READY:
				await get_tree().process_frame
			_leave_throw()
			await _wait(0.6)

## v9 stills: shore water through a surf cycle, wading close-ups, lying on the bench / a log, night.
## part "" = all, or one of shore / wade / lie / night
func _v9_sequence(pre: String, part: String) -> void:
	if part == "" or part == "shore":
		for th: float in [-1.05, 2.2]:
			var tag := "a" if th < 0.0 else "b"
			var sea := Island.dir_at(th)
			var p := island.shore_pt(th, 1.4)
			var along := sea.cross(Vector3.UP)
			_place(p, atan2(-sea.x, -sea.z) + 0.5)
			await _wait(0.4)
			for k in 4:
				_fixed_cam(p + sea * 1.6 + Vector3(0, 0.2, 0), atan2(sea.x, sea.z) + 0.55, 0.62, 5.0)
				await _wait(0.05)
				_shot(pre + "30%s_shore_%d" % [tag, k])
				_fixed_cam(p + sea * 1.0 + Vector3(0, 0.3, 0), atan2(along.x, along.z) - 0.5, 0.16, 3.6)
				await _wait(0.05)
				_shot(pre + "31%s_shore_low_%d" % [tag, k])
				await _wait(2.3)
			_free_cam()
	if part == "" or part == "wade":
		var wp := island.shore_pt(-1.2, -1.6)
		_place(wp, 0.4)
		_walk_to.call(island.shore_pt(-1.32, -2.0), false)
		await _wait(1.5)
		_shot(pre + "32_wading_game")
		_stop_walk()
		await _wait(0.6)
		var bp := player.global_position
		_fixed_cam(bp + Vector3(0, 0.25, 0), face_yaw + 1.2, 0.12, 1.9)
		await _wait(0.3)
		_shot(pre + "33_wading_low")
		_fixed_cam(bp + Vector3(0, 0.2, 0), face_yaw + 0.5, 0.55, 2.2)
		await _wait(0.3)
		_shot(pre + "34_wading_high")
		var dp := Vector3(0.0, 0.0, lerpf(island.dock_start_z, island.dock_end_z, 0.35))
		_fixed_cam(dp + Vector3(0, -0.2, 0), 1.3, 0.22, 4.2)
		await _wait(0.3)
		_shot(pre + "35_dock_posts")
		_free_cam()
	if part == "" or part == "lie" or part == "lieq":
		for i: int in ([0, 1, 2, 3] if part != "lieq" else [1]):
			var st: Dictionary = island.seats[i]
			var face: Vector3 = st["face"]
			var from_back := i == 2
			var spot: Vector3 = (st["back_approach"] as Vector3) - face * 0.7 if from_back else (st["approach"] as Vector3) + face * 0.7
			_place(_blocked_by(spot), 0.0)
			_free_cam()
			await _wait(0.3)
			_on_action()
			while rest_phase != 4:
				await get_tree().process_frame
			await _wait(0.8)
			_shot(pre + "36_seat_%d_sit" % i)
			_lie_down()
			await _wait(SEAT_LIE_DUR * 0.5)
			_shot(pre + "37_seat_%d_lying_down" % i)
			while rest_phase != 4:
				await get_tree().process_frame
			await _wait(1.5)
			_shot(pre + "38_seat_%d_lie" % i)
			_fixed_cam(rest_lie + Vector3(0, 0.1, 0), atan2(seat_face.x, seat_face.z) + 0.35, 0.35, 1.8)
			await _wait(0.4)
			_shot(pre + "39_seat_%d_lie_close" % i)
			_free_cam()
			_wake()
			while mode != Mode.EXPLORE:
				await get_tree().process_frame
			await _wait(0.3)

	if part == "" or part == "night":
		var c := island.campfire_pos
		_place(c + Vector3(2.4, 0, 2.4), 0.0)
		await _wait(0.3)
		_shot(pre + "40_day_ui")
		_fixed_cam(c + Vector3(0, 0.4, 0), 0.7, 0.25, 4.2)
		await _wait(0.4)
		_shot(pre + "40b_day_fire")
		_free_cam()
		await _wait(0.2)
		_toggle_night()
		await _wait(1.25)
		_shot(pre + "41_dusk_transition")
		await _wait(1.6)
		_shot(pre + "42_night_ui")
		_fixed_cam(c + Vector3(0, 0.4, 0), 0.7, 0.25, 4.2)
		await _wait(0.4)
		_shot(pre + "43_night_fire")
		var st: Dictionary = island.seats[1]
		_place(_blocked_by((st["approach"] as Vector3) + (st["face"] as Vector3) * 0.7), 0.0)
		_free_cam()
		await _wait(0.2)
		_on_action()
		while rest_phase != 4:
			await get_tree().process_frame
		await _wait(1.0)
		_shot(pre + "44_night_sit_fire")
		_wake()
		while mode != Mode.EXPLORE:
			await get_tree().process_frame
		_place(Vector3(0.3, 0, island.dock_end_z + 1.6), 0.1)
		await _wait(0.5)
		_shot(pre + "45_night_dock")
		_enter_throw()
		await _wait(1.3)
		_shot(pre + "46_night_throw_view")
		_leave_throw()
		await _wait(0.6)
		_fixed_cam(Vector3(0, 1.0, island.dock_start_z - 2.0), 2.6, 0.32, 26.0)
		await _wait(0.4)
		_shot(pre + "47_night_wide")
		_fixed_cam(island.beacon_pos + Vector3(0, -3.0, 0), 1.9, 0.12, 18.0)
		await _wait(0.4)
		_shot(pre + "48_night_lighthouse")
		var wp := island.shore_pt(-1.2, -1.6)
		_place(wp, 0.4)
		_walk_to.call(island.shore_pt(-1.32, -2.0), false)
		await _wait(1.5)
		_shot(pre + "49_night_wading")
		_stop_walk()
		_free_cam()
		_toggle_night()
		await _wait(2.8)

## v11 stills: the ground round the campfire logs, the water reflection. part "" = all, logs or refl
func _v11_sequence(pre: String, part: String) -> void:
	if part == "" or part == "refl":
		for night in [false, true]:
			var tag := "night" if night else "day"
			if night:
				_toggle_night()
				await _wait(2.9)
			_fixed_cam(Vector3(0, 1.0, island.dock_start_z - 2.0), 2.6, 0.32, 26.0)
			await _wait(0.4)
			_shot(pre + "61_%s_wide" % tag)
			_fixed_cam(island.beacon_pos + Vector3(0, -3.0, 0), 1.9, 0.12, 18.0)
			await _wait(0.4)
			_shot(pre + "62_%s_lighthouse" % tag)
			_fixed_cam(Vector3(0, 1.5, island.dock_start_z - 4.0), PI + 0.15, 0.07, 30.0)
			await _wait(0.4)
			_shot(pre + "63_%s_low_from_sea" % tag)
			_fixed_cam(island.campfire_pos + Vector3(0, 0.5, 0), 0.9, 0.1, 16.0)
			await _wait(0.4)
			_shot(pre + "64_%s_fire_from_shore" % tag)
		_free_cam()
		_toggle_night()
		await _wait(2.8)
	if part == "" or part == "logs":
		var c := island.campfire_pos
		_place(c + Vector3(6.0, 0, 6.0), 0.0)
		_fixed_cam(c + Vector3(0, 0.2, 0), 0.4, 0.55, 7.5)
		await _wait(0.5)
		_shot(pre + "50_logs_wide")
		_fixed_cam(c + Vector3(0, 0.2, 0), -2.5, 0.3, 6.5)
		await _wait(0.3)
		_shot(pre + "51_logs_from_hill")
		for i in 3:
			var a := 0.6 + i * 2.1
			var lp := island.gp(c.x + cos(a) * 1.7, c.z + sin(a) * 1.7)
			# along the log (its bank in profile), from the fire side looking past it, and from outside
			_fixed_cam(lp + Vector3(0, 0.3, 0), atan2(-sin(a), cos(a)), 0.3, 4.2)
			await _wait(0.3)
			_shot(pre + "52_log_%d_profile" % i)
			_fixed_cam(lp + Vector3(0, 0.3, 0), atan2(-cos(a), -sin(a)) + 0.3, 0.12, 3.6)
			await _wait(0.3)
			_shot(pre + "53_log_%d_from_fire" % i)
			_fixed_cam(lp + Vector3(0, 0.25, 0), atan2(cos(a), sin(a)) + 0.35, 0.35, 3.6)
			await _wait(0.3)
			_shot(pre + "54_log_%d_outside" % i)
		_free_cam()

## v12 stills: the reflection at the screen edges, day and night, round 360 degrees and zoomed in / out
func _v12_sequence(pre: String, part: String) -> void:
	if part == "" or part == "bush":
		var best: Array = island.bush_spots[0]
		for b: Array in island.bush_spots:
			if _hd(b[0], island.hut_pos) < _hd(best[0], island.hut_pos) and _hd(b[0], island.hut_pos) > 4.5:
				best = b
		var bp: Vector3 = best[0]
		var bs: float = best[1]
		var away := Vector3(bp.x - island.hut_pos.x, 0, bp.z - island.hut_pos.z).normalized()
		var yaw := atan2(away.x, away.z)
		_place(bp + away * (0.9 + 0.5 * bs), yaw)
		_fixed_cam(bp + Vector3(0, 0.55 * bs, 0), yaw + 0.5, 0.2, 2.6 * bs)
		await _wait(0.6)
		_shot(pre + "80_bush_close")
		_fixed_cam(bp + Vector3(0, 0.45 * bs, 0), yaw + 2.4, 0.08, 2.0 * bs)
		await _wait(0.4)
		_shot(pre + "81_bush_close_side")
		_fixed_cam(bp + away * 1.2 + Vector3(0, 0.15, 0), yaw - 1.2, 0.05, 1.6)
		await _wait(0.4)
		_shot(pre + "82_grass_low")
		_free_cam()
		_snap_explore_cam()
		await _wait(1.0)
		_shot(pre + "83_bush_game_view")

	if part == "" or part == "edges":
		for night in [false, true]:
			var tag := "night" if night else "day"
			if night:
				_toggle_night()
				await _wait(2.9)
			var c := Vector3(0, 1.0, island.dock_end_z + 1.0)
			for k in 8:
				_fixed_cam(c, k * TAU / 8.0, 0.1, 9.0)
				await _wait(0.35)
				_shot(pre + "70_%s_yaw%d" % [tag, k * 45])
			for z: Array in [[3.5, 0.06, "near"], [30.0, 0.16, "far"]]:
				_fixed_cam(c, 0.6, z[1], z[0])
				await _wait(0.35)
				_shot(pre + "71_%s_zoom_%s" % [tag, z[2]])
			_fixed_cam(Vector3(0, 1.5, island.dock_start_z - 4.0), PI + 0.15, 0.07, 30.0)
			await _wait(0.35)
			_shot(pre + "72_%s_low_from_sea" % tag)
			if night:
				_toggle_night()
				await _wait(2.9)
		_free_cam()
	if part == "" or part == "torch":
		var c := island.campfire_pos
		_place(c + Vector3(5.0, 0, 5.0), 0.0)
		demo_nocut = true
		for night in [false, true]:
			var tag := "night" if night else "day"
			if night:
				_toggle_night()
				await _wait(2.9)
			var tp := island.torches[0].global_position
			var out := Vector3(tp.x - c.x, 0, tp.z - c.z).normalized()
			var yaw := atan2(out.x, out.z)
			for sh: Array in [[tp + Vector3(0, -0.05, 0), yaw + PI - 0.5, 0.12, 0.9, "90_%s_torch_head"], [tp + Vector3(0, -0.05, 0), yaw + 0.6, 0.1, 0.9, "90_%s_torch_head_back"], [tp + Vector3(0, -0.8, 0), yaw + PI - 0.9, 0.1, 2.6, "91_%s_torch_full"], [c + Vector3(0, 0.6, 0), yaw + 1.3, 0.22, 7.5, "92_%s_torches_camp"]]:
				var cy: float = sh[1]
				_fixed_cam(sh[0], cy, sh[2], sh[3])
				await _wait(0.5)
				_shot(pre + (sh[4] as String) % tag)
			if night:
				_toggle_night()
				await _wait(2.9)
		demo_nocut = false
		_free_cam()

## gameplay follow camera along the beach (style checks): walk, run, then stand
func _explore_sequence(pre: String) -> void:
	var a := island.shore_pt(-1.3, 2.2)
	_place(a, 0.0)
	var b := island.shore_pt(-0.95, 2.2)
	var dirv := (b - a).normalized()
	face_yaw = atan2(-dirv.x, -dirv.z)
	player.rotation.y = face_yaw
	_snap_explore_cam()
	_walk_to.call(b, false)
	await _wait(2.5)
	_shot(pre + "e1_walk")
	_walk_to.call(island.shore_pt(-0.4, 3.6), true)
	await _wait(2.0)
	_shot(pre + "e2_run")
	_stop_walk()
	await _wait(1.5)
	_shot(pre + "e3_stand")

func _run_demo4() -> void:
	await _wait(0.5)
	if demo_seg != "":
		await _video_seg(demo_seg)
		get_tree().quit()
		return
	var pre := "p_" if portrait_demo else ""
	var close := not portrait_demo
	for a0 in OS.get_cmdline_user_args():
		if a0.begins_with("--from="):
			var what := a0.substr(7)
			if what == "throw":
				await _throw_sequence(pre + "08_", true, close)
			elif what == "shore":
				await _shore_sequence(pre)
			elif what == "explore":
				await _explore_sequence(pre)
			elif what == "v8":
				await _v8_sequence(pre)
			elif what.begins_with("v9"):
				await _v9_sequence(pre, what.substr(2).trim_prefix("_"))
			elif what.begins_with("v12"):
				await _v12_sequence(pre, what.substr(3).trim_prefix("_"))
			elif what.begins_with("v11"):
				await _v11_sequence(pre, what.substr(3).trim_prefix("_"))
			else:
				await _rest_sequence(pre + ("10_" if what == "sleep" else "11_"), what, close)
			get_tree().quit()
			return
	if close:
		_track(PI, 0.04, 0.95, 1.0)
		await _wait(0.4)
		_shot("01_face_front")
		_track(PI - 0.65, 0.06, 1.0, 1.0)
		await _wait(0.3)
		_shot("02_face_34")
		_track(PI - 0.35, 0.1, 2.3, 0.62)
		await _wait(0.3)
		_shot("03_body_vest_front")
		_track(0.7, 0.22, 2.4, 0.62)
		await _wait(0.3)
		_shot("04_body_vest_back34")
		_free_cam()
	# walk then run along the beach toward the dock
	var a := island.shore_pt(-1.05, 1.6)
	_place(a, 0.0)
	var dock_foot := Vector3(0.0, 0, island.dock_start_z + 1.5)
	var sea_dir := Island.dir_at(-1.3)
	var dirv := (dock_foot - a).normalized()
	face_yaw = atan2(-dirv.x, -dirv.z)
	player.rotation.y = face_yaw
	_snap_explore_cam()
	var mid := island.shore_pt(-1.32, 1.4)
	if close:
		demo_cam = true
		demo_track = [atan2(sea_dir.x, sea_dir.z) - 0.25, 0.1, 3.0, 0.6, true]
	var t_walk := gt
	_walk_to.call(mid, false)
	await _wait(1.8)
	_shot(pre + "05_walk")
	await _wait(0.35)
	_shot(pre + "05b_walk")
	while _hd(player.position, mid) > 0.5 and gt - t_walk < 10.0:
		await get_tree().process_frame
	_walk_to.call(dock_foot, true)
	await _wait(1.2)
	_shot(pre + "06_run")
	await _wait(0.25)
	_shot(pre + "06b_run")
	_free_cam()
	while _hd(player.position, dock_foot) > 0.5 and gt - t_walk < 20.0:
		await get_tree().process_frame
	_walk_to.call(Vector3(0, 0, island.dock_end_z + 2.0), true)
	await _wait(1.6)
	_shot(pre + "07_explore_follow")
	_stop_walk()
	await _wait(0.2)
	await _throw_sequence(pre + "08_", true, close)
	_leave_throw()
	if close:
		await _throw_sequence("09_", false, true)
		_leave_throw()
	await _rest_sequence(pre + "10_", "sleep", close)
	_wake()
	while mode != Mode.EXPLORE:
		await get_tree().process_frame
	await _wait(0.3)
	_shot(pre + "10_sleep_woke")
	await _rest_sequence(pre + "11_", "sun", close)
	if not portrait_demo:
		_wake()
		while mode != Mode.EXPLORE:
			await get_tree().process_frame
		_toggle_view()
		await _wait(1.5)
		_shot("12_view_mode")
	get_tree().quit()

func _video_seg(seg: String) -> void:
	match seg:
		"walk":
			var a := island.shore_pt(-1.05, 1.6)
			var mid := island.shore_pt(-1.32, 1.4)
			var dock_foot := Vector3(0.0, 0, island.dock_start_z + 1.5)
			var dirv := (mid - a).normalized()
			_place(a, atan2(-dirv.x, -dirv.z))
			ex_yaw = face_yaw + 1.1
			_snap_cam_now()
			await _walk_to(mid, false, 3.4)
			await _walk_to(dock_foot, true, 4.0)
			await _walk_to(Vector3(0, 0, island.dock_end_z + 2.2), true, 3.0)
			await _wait(0.3)
		"throw":
			# standing and half-kneeling throws seen from the front-right (the throwing side), then one in the game camera
			_place(Vector3(0.0, 0, island.dock_end_z + 3.0), 0.0)
			await _walk_to(Vector3(0.2, 0, island.dock_end_z + 1.5), false, 2.0)
			await _wait(0.4)
			_enter_throw()
			for k in 3:
				await _wait(0.5)
				if (k == 1) != (boy.stance == "crouch"):
					_toggle_stance()
					await _wait(0.9)
				if k < 2:
					demo_cam = true
					demo_track = [player.rotation.y + PI * 0.5 + 0.55, 0.22, 2.9, 0.5, true]
				else:
					_free_cam()
				_begin_aim(Vector2.ZERO)
				aim_pitch = 3.0
				var t0 := gt
				while gt - t0 < 1.5:
					charge_t = minf((gt - t0) / 1.2, 1.0) * 0.9 * POWER_CYCLE * 0.5
					aim_yaw = 0.1 + sin((gt - t0) * 2.0) * 0.04
					await get_tree().process_frame
				charge_t = 0.9 * POWER_CYCLE * 0.5
				_throw()
				fly_t = 0.0
				if k < 2:
					await _wait(3.2)
				while state != State.READY:
					await get_tree().process_frame
				await _wait(1.0 if k < 2 else 3.0)
			_free_cam()
		"sleep":
			var hs := _hammock_spot()
			var bed: Vector3 = hs[0]
			var side: Vector3 = hs[2]
			_place(bed + side * 2.2 + (island.hammock_b - island.hammock_a).normalized() * 0.8, atan2(side.x, side.z))
			ex_yaw = face_yaw + PI + 0.5
			_snap_cam_now()
			await _walk_to(bed + side * 1.2, false, 1.8)
			_begin_rest("sleep")
			while rest_phase < 4:
				await get_tree().process_frame
			await _wait(2.6)
		"sun":
			var td := island.towel_dir
			var sd := td.cross(Vector3.UP).normalized()
			_place(island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
			ex_yaw = face_yaw + PI + 0.6
			_snap_cam_now()
			_begin_rest("sun")
			while rest_phase < 4:
				await get_tree().process_frame
			await _wait(2.2)
		"getup":
			# sunbathe -> get up -> walk away on the real touch stick (the v5 bug: stuck after getting up)
			var td2 := island.towel_dir
			var sd2 := td2.cross(Vector3.UP).normalized()
			_place(island.towel_pos + sd2 * 1.4 + td2 * 0.4, atan2(sd2.x, sd2.z))
			_snap_cam_now()
			_begin_rest("sun")
			while rest_phase < 4:
				await get_tree().process_frame
			await _wait(1.8)
			_toast("点「起来」", 1.0)
			_wake()
			while mode != Mode.EXPLORE:
				await get_tree().process_frame
			await _wait(0.4)
			await _stick_walk([Vector2(0.2, -1), Vector2(1, -0.3), Vector2(0.4, 1)], 1.6)
			await _wait(0.8)
		"gait":
			# side-on camera out over the water: walk, run, stop; then the same stretch in the game camera
			var sea_side := Island.dir_at(-1.1)
			for game_cam: bool in [false, true]:
				var g0 := island.shore_pt(-1.38, 2.4)
				var gm := island.shore_pt(-1.15, 2.4)
				var g1 := island.shore_pt(-0.86, 2.6)
				var gd := (gm - g0).normalized()
				_place(g0, atan2(-gd.x, -gd.z))
				ex_yaw = face_yaw
				_snap_cam_now()
				if game_cam:
					_free_cam()
				else:
					demo_cam = true
					demo_track = [atan2(sea_side.x, sea_side.z), 0.08, 2.3, 0.62, true]
				await _wait(0.6)
				await _walk_to(gm, false, 5.0)
				await _walk_to(g1, true, 4.0)
				_stop_walk()
				await _wait(1.2)
			_free_cam()

		"turn12":
			# turning on the spot: stick flicks of 180 / 90 / 135 degrees from a stand, a reversal out of a
			# walk, the 180 again in slow motion, then the same in the game camera
			var push := func(dirv: Vector3, mag: float, dur: float) -> void:
				var fwd := Vector3(-sin(ex_yaw), 0, -cos(ex_yaw))
				var right := Vector3(cos(ex_yaw), 0, -sin(ex_yaw))
				demo_input = Vector2(dirv.dot(right), -dirv.dot(fwd)) * mag
				await _wait(dur)
				demo_input = Vector2.ZERO
			# mid-dock: open, flat, and the camera can stand off to the side over the water
			var g0 := Vector3(0.0, 0.0, lerpf(island.dock_start_z, island.dock_end_z, 0.45))
			var gd := Vector3(0, 0, signf(island.dock_end_z - island.dock_start_z))
			var sd := gd.cross(Vector3.UP)
			for view in ["side", "slow", "game"]:
				_place(g0, atan2(-gd.x, -gd.z))
				ex_yaw = face_yaw
				_snap_cam_now()
				if view == "game":
					_free_cam()
				else:
					demo_cam = true
					demo_track = [atan2(sd.x, sd.z) + (0.45 if view == "side" else -0.35), 0.16, 3.2, 0.55, true]
				await _wait(0.8)
				if view == "slow":
					_toast("慢放 0.4×：原地转身 180°", 1.6)
					Engine.time_scale = 0.4
					await push.call(-gd, 0.45, 0.5)
					await _wait(1.6)
					Engine.time_scale = 1.0
					await _wait(0.5)
					continue
				_toast("原地转身 180°", 1.2)
				await push.call(-gd, 0.45, 0.4)
				await _wait(1.8)
				_toast("左转 90°", 1.0)
				await push.call(sd, 0.45, 0.4)
				await _wait(1.5)
				_toast("右后方 135°", 1.0)
				await push.call((-sd + gd).normalized(), 0.45, 0.4)
				await _wait(1.8)
				_toast("走着突然掉头", 1.2)
				await push.call(gd, 0.6, 1.4)
				await push.call(-gd, 0.6, 1.6)
				await _wait(1.2)
			_free_cam()

		"gait10":
			# walk -> run -> stop seen from the front, then side-on, then a zig-zag (turns) in the game camera
			for view in ["front", "side", "game"]:
				var g0 := island.shore_pt(-1.38, 2.4)
				var gm := island.shore_pt(-1.15, 2.4)
				var g1 := island.shore_pt(-0.86, 2.6)
				var gd := (gm - g0).normalized()
				_place(g0, atan2(-gd.x, -gd.z))
				ex_yaw = face_yaw
				_snap_cam_now()
				_toast({"front": "正面：走 → 跑 → 停", "side": "侧面：走 → 跑 → 停", "game": "转弯：走、跑"}[view], 1.6)
				if view == "game":
					_free_cam()
					await _wait(0.4)
					var sd := gd.cross(Vector3.UP)
					await _walk_to(g0 + gd * 2.5 + sd * 1.2, false, 4.0)
					await _walk_to(g0 + gd * 4.5 - sd * 1.0, false, 4.0)
					await _walk_to(g0 + gd * 8.0 + sd * 1.5, true, 4.0)
					await _walk_to(g0 + gd * 11.0 - sd * 1.5, true, 4.0)
					_stop_walk()
					await _wait(1.2)
				else:
					demo_cam = true
					demo_track = [PI + 0.25 if view == "front" else PI * 0.5, 0.06, 2.6, 0.62]
					await _wait(0.6)
					await _walk_to(gm, false, 5.0)
					await _walk_to(g1, true, 4.0)
					_stop_walk()
					await _wait(1.4)
			_free_cam()

		"throw10":
			# standing and half-kneeling throws, each from the front, side-on (throwing arm side) and from above
			_place(Vector3(0.2, 0, island.dock_end_z + 1.5), 0.0)
			await _wait(0.3)
			_enter_throw()
			for k in 6:
				var crouch := k >= 3
				if crouch != (boy.stance == "crouch"):
					_toggle_stance()
				await _wait(1.0)
				var v := k % 3
				demo_cam = true
				var hgt := 0.62 if not crouch else 0.45
				demo_track = [[aim_yaw + PI + 0.15, 0.05, 2.7, hgt, true], [aim_yaw - PI * 0.5, 0.05, 2.7, hgt, true],
					[aim_yaw + PI * 0.8, 1.15, 2.6, hgt, true]][v]
				_toast(("半蹲" if crouch else "站立") + ["投掷 · 正面", "投掷 · 侧面", "投掷 · 俯视"][v], 1.6)
				_begin_aim(Vector2.ZERO)
				aim_pitch = 3.0
				var t0 := gt
				while gt - t0 < 1.0:
					charge_t = minf((gt - t0) / 0.9, 1.0) * 0.9 * POWER_CYCLE * 0.5
					await get_tree().process_frame
				charge_t = 0.9 * POWER_CYCLE * 0.5
				_throw()
				fly_t = 0.0
				await _wait(2.6)
				while state != State.READY:
					await get_tree().process_frame
				await _wait(0.4)
			_free_cam()

		"throw8":
			# the reworked throw: standing in the game camera, standing side-on, crouching side-on, crouching in the game camera
			_place(Vector3(0.0, 0, island.dock_end_z + 3.0), 0.0)
			await _walk_to(Vector3(0.2, 0, island.dock_end_z + 1.5), false, 2.0)
			await _wait(0.4)
			_enter_throw()
			for k in 4:
				await _wait(0.5)
				if (k >= 2) != (boy.stance == "crouch"):
					_toggle_stance()
					await _wait(0.9)
				var side := k == 1 or k == 2
				if side:
					demo_cam = true
					demo_track = [aim_yaw + PI * 0.5 + 0.1, 0.1, 2.6, 0.55 if k == 1 else 0.42, true]
				else:
					_free_cam()
				_begin_aim(Vector2.ZERO)
				aim_pitch = 3.0
				var t0 := gt
				while gt - t0 < 1.5:
					charge_t = minf((gt - t0) / 1.2, 1.0) * 0.9 * POWER_CYCLE * 0.5
					await get_tree().process_frame
				charge_t = 0.9 * POWER_CYCLE * 0.5
				_throw()
				fly_t = 0.0
				if side:
					await _wait(2.6)
				while state != State.READY:
					await get_tree().process_frame
				await _wait(0.8 if side else 2.0)
			_free_cam()
		"bump":
			# walking into things: palm, log by the fire, the lounger, a rock, wading against the dock, the bench, the fire ring
			var tests: Array = []
			for nm: String in ["椰子树", "坐木", "躺椅", "礁石", "码头", "长椅", "篝火"]:
				for w: Array in island.walls:
					if w[6] != nm:
						continue
					var found := _bump_spot(w)
					if not found.is_empty():
						tests.append(found)
						break
			for tst: Array in tests:
				var sp: Vector3 = tst[0]
				var dir: Vector3 = tst[1]
				_place(sp, atan2(-dir.x, -dir.z))
				ex_yaw = face_yaw + 0.5
				_snap_cam_now()
				_toast(tst[2], 2.0)
				await _wait(0.3)
				await _drive_dir(dir, 1.6, false)
				await _drive_dir(dir.rotated(Vector3.UP, 0.7), 1.8, false)
				await _drive_dir(dir.rotated(Vector3.UP, -0.7), 2.0, true)
				await _wait(0.3)
		"sit":
			# bench by the lighthouse, then a log at the campfire, then the lounger
			for i: int in [0, 2, 4]:
				var st: Dictionary = island.seats[i]
				var face: Vector3 = st["face"]
				var side := face.cross(Vector3.UP)
				_place((st["approach"] as Vector3) + face * 2.2 + side * 0.8, 0.0)
				var to := (st["approach"] as Vector3) - player.position
				face_yaw = atan2(-to.x, -to.z)
				player.rotation.y = face_yaw
				ex_yaw = face_yaw + 0.35
				_snap_cam_now()
				await _walk_to((st["approach"] as Vector3) + face * 0.5, false, 3.0)
				await _wait(0.5)
				_on_action()
				while rest_phase < 4:
					await get_tree().process_frame
				await _wait(3.0)
				_wake()
				while mode != Mode.EXPLORE:
					await get_tree().process_frame
				await _drive_dir(face, 1.0, false)
				await _wait(0.3)
		"fire":
			# campfire close-up, slowly circling
			var c := island.campfire_pos
			_place(c + Vector3(4.0, 0, 4.0), 0.0)
			var t1 := gt
			while gt - t1 < 9.0:
				var u := (gt - t1) / 9.0
				_fixed_cam(c + Vector3(0, 0.4, 0), 0.4 + u * 1.2, 0.2 + 0.1 * sin(u * PI), 2.3 + u * 1.2)
				await get_tree().process_frame
			_free_cam()
		"prints":
			# footprints along the waterline: the swash wipes out the low ones, the dry ones stay (and fade slowly)
			var a := island.shore_pt(-1.30, 2.0)
			var b := island.shore_pt(-1.27, 0.95)
			var c := island.shore_pt(-1.14, 0.95)
			var e := island.shore_pt(-1.11, 2.0)
			var f := island.shore_pt(-1.06, 2.1)
			var mid := island.shore_pt(-1.19, 1.45)
			var sea := Island.dir_at(-1.19)
			_place(a, 0.0)
			_fixed_cam(mid + Vector3(0, 0.1, 0), atan2(sea.x, sea.z), 1.08, 4.6)
			await _wait(0.4)
			for w in [b, c, e, f]:
				await _walk_to(w, false, 6.0)
			_stop_walk()
			await _wait(22.0)

		"recover":
			# the arm after the release: stand and half-kneel, side-on from the throwing side, each once at
			# full speed and once at half speed
			_place(Vector3(0.2, 0, island.dock_end_z + 1.5), 0.0)
			await _wait(0.3)
			_enter_throw()
			for k in 4:
				var crouch := k >= 2
				if crouch != (boy.stance == "crouch"):
					_toggle_stance()
				await _wait(1.0)
				demo_cam = true
				demo_track = [aim_yaw + PI - 0.7, 0.1, 2.6, 0.62 if not crouch else 0.45, true]
				_toast(("半蹲" if crouch else "站立") + ("投掷 · 慢放 0.5×" if k % 2 == 1 else "投掷"), 1.6)
				_begin_aim(Vector2.ZERO)
				aim_pitch = 3.0
				var t0 := gt
				while gt - t0 < 1.0:
					charge_t = minf((gt - t0) / 0.9, 1.0) * 0.9 * POWER_CYCLE * 0.5
					await get_tree().process_frame
				charge_t = 0.9 * POWER_CYCLE * 0.5
				if k % 2 == 1:
					Engine.time_scale = 0.5
				_throw()
				fly_t = 0.0
				await _wait(2.6)
				Engine.time_scale = 1.0
				while state != State.READY:
					await get_tree().process_frame
				await _wait(0.4)
			_free_cam()
		"lie":
			# the bench, then the three logs by the fire (front, back, front): sit, lie back with the hat on
			# the face and a leg crossed, nap a moment, get up
			for i: int in [0, 1, 2, 3]:
				var st: Dictionary = island.seats[i]
				var face: Vector3 = st["face"]
				var from_back := i == 2
				var spot: Vector3 = (st["back_approach"] as Vector3) - face * 1.6 if from_back else (st["approach"] as Vector3) + face * 1.6
				_place(_blocked_by(spot), 0.0)
				var to := (st["top"] as Vector3) - player.position
				face_yaw = atan2(-to.x, -to.z)
				player.rotation.y = face_yaw
				ex_yaw = face_yaw + 0.5
				_snap_cam_now()
				_toast("%s · 坐下 → 躺下 → 起来" % ("长椅" if i == 0 else "篝火边的木头 %d%s" % [i, "（从背面坐）" if from_back else ""]), 2.0)
				await _walk_to(_blocked_by((st["back_approach"] as Vector3) - face * 0.6 if from_back else (st["approach"] as Vector3) + face * 0.6), false, 2.5)
				await _wait(0.3)
				_on_action()
				while rest_phase != 4:
					await get_tree().process_frame
				await _wait(1.2)
				_lie_down()
				await _wait(SEAT_LIE_DUR * 0.4)
				_fixed_cam(rest_lie + Vector3(0, 0.15, 0), atan2(seat_face.x, seat_face.z) + 0.45, 0.32, 2.2)
				while rest_phase != 4:
					await get_tree().process_frame
				await _wait(3.2 if i == 0 else 2.2)
				_wake()
				while mode != Mode.EXPLORE:
					await get_tree().process_frame
				_free_cam()
				await _wait(0.6)
		"shore":
			# a full surf cycle from above, then low along the beach
			var sea := Island.dir_at(-1.05)
			var p := island.shore_pt(-1.05, 1.4)
			var along := sea.cross(Vector3.UP)
			_place(p, atan2(-sea.x, -sea.z) + 0.5)
			_fixed_cam(p + sea * 1.6 + Vector3(0, 0.2, 0), atan2(sea.x, sea.z) + 0.55, 0.62, 5.0)
			await _wait(10.5)
			_fixed_cam(p + sea * 1.0 + Vector3(0, 0.3, 0), atan2(along.x, along.z) - 0.5, 0.16, 3.6)
			await _wait(10.5)
			var sea2 := Island.dir_at(2.2)
			var p2 := island.shore_pt(2.2, 1.4)
			_place(p2, atan2(-sea2.x, -sea2.z) + 0.5)
			_fixed_cam(p2 + sea2 * 1.2 + Vector3(0, 0.2, 0), atan2(sea2.x, sea2.z) - 0.4, 0.35, 4.5)
			await _wait(10.0)
			_free_cam()
		"wade":
			# walk into the sea by the dock: legs go under, tinted and wobbling; foam collar + rings follow
			var a := island.shore_pt(-1.2, 0.6)
			var b := island.shore_pt(-1.24, -1.9)
			var dv := (b - a).normalized()
			_place(a, atan2(-dv.x, -dv.z))
			demo_cam = true
			demo_track = [atan2(dv.x, dv.z) + PI * 0.5 + 0.4, 0.14, 2.3, 0.35, true]
			await _walk_to(b, false, 7.0)
			await _wait(2.5)
			await _walk_to(island.shore_pt(-1.34, -2.2), false, 4.0)
			_free_cam()
			await _wait(0.5)
			await _walk_to(island.shore_pt(-1.2, -1.2), false, 4.0)
			await _wait(2.0)
		"night":
			# dusk falls by the campfire, fireflies, sit by the fire, then the dock: the moon path on the sea
			var c := island.campfire_pos
			_place(c + Vector3(2.6, 0, 2.6), 0.0)
			_fixed_cam(c + Vector3(0, 0.5, 0), 0.7, 0.28, 5.2)
			await _wait(1.2)
			_toggle_night()
			await _wait(4.5)
			var st: Dictionary = island.seats[1]
			_free_cam()
			await _walk_to(_blocked_by((st["approach"] as Vector3) + (st["face"] as Vector3) * 0.6), false, 3.0)
			_on_action()
			while rest_phase != 4:
				await get_tree().process_frame
			await _wait(4.0)
			_wake()
			while mode != Mode.EXPLORE:
				await get_tree().process_frame
			_free_cam()
			_place(Vector3(0.2, 0, island.dock_end_z + 1.5), 0.1)
			await _wait(0.5)
			_enter_throw()
			await _wait(1.5)
			_begin_aim(Vector2.ZERO)
			aim_pitch = 3.0
			var t0 := gt
			while gt - t0 < 1.2:
				charge_t = minf((gt - t0) / 1.1, 1.0) * 0.9 * POWER_CYCLE * 0.5
				await get_tree().process_frame
			_throw()
			while state != State.READY:
				await get_tree().process_frame
			await _wait(1.0)
			_leave_throw()
			_fixed_cam(Vector3(0, 1.0, island.dock_start_z - 2.0), 2.6, 0.32, 26.0)
			var t1 := gt
			while gt - t1 < 5.0:
				_fixed_cam(Vector3(0, 1.0, island.dock_start_z - 2.0), 2.6 + (gt - t1) * 0.08, 0.32, 26.0)
				await get_tree().process_frame
			_toggle_night()
			await _wait(3.5)
			_free_cam()

## steer with the stick towards a world direction (camera-relative, like a player would)
func _drive_dir(dir: Vector3, sec: float, run: bool) -> void:
	demo_run = run
	var t0 := gt
	while gt - t0 < sec:
		var fwd := Vector3(-sin(ex_yaw), 0, -cos(ex_yaw))
		var right := Vector3(cos(ex_yaw), 0, -sin(ex_yaw))
		demo_input = Vector2(dir.dot(right), -dir.dot(fwd)) * (1.0 if run else 0.75)
		await get_tree().process_frame
	demo_input = Vector2.ZERO
	demo_run = false

## a clear spot ~1.5 m from a wall with flat ground towards it (collision demo)
func _bump_spot(w: Array) -> Array:
	var a: Vector2 = w[1]
	var c := a if w[0] != "s" else (a + (w[2] as Vector2)) * 0.5
	var ext: float = float(w[3]) if w[0] == "c" else (0.3 if w[0] == "s" else (w[2] as Vector2).x)
	for k in 12:
		var d := Vector2(cos(k * TAU / 12.0 + 0.3), sin(k * TAU / 12.0 + 0.3))
		var s := c + d * (ext + 1.6)
		var h := _surface(s.x, s.y)
		var sp := Vector3(s.x, h, s.y)
		if not _can_stand(h, s.x, s.y) or penetration(sp) > 0.0 or not _wall_hits_y(w, h) or Island.wall_dist(w, s).x < 1.2:
			continue
		return [sp, Vector3(-d.x, 0, -d.y), "撞上%s：沿着它滑开" % w[6]]
	return []

## drive the on-screen joystick with real touch events (like a finger on the phone)
func _stick_walk(dirs: Array, sec_each: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var c := Vector2(vs.x * 0.14, vs.y * 0.86)
	var keep := demo_mode
	demo_mode = false
	var ev := InputEventScreenTouch.new()
	ev.index = 0; ev.position = c; ev.pressed = true
	get_viewport().push_input(ev, true)
	var last := c
	for dv: Vector2 in dirs:
		var t0 := gt
		while gt - t0 < sec_each:
			var to := c + dv.normalized() * 50.0
			var dr := InputEventScreenDrag.new()
			dr.index = 0; dr.position = last.lerp(to, 0.3); dr.relative = dr.position - last
			last = dr.position
			get_viewport().push_input(dr, true)
			await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0; up.position = last; up.pressed = false
	get_viewport().push_input(up, true)
	demo_mode = keep

func _snap_cam_now() -> void:
	var c := _explore_cam()
	cam_target = c[0]; cam_yaw = c[1]; cam_pitch = c[2]; cam_dist = c[3]
